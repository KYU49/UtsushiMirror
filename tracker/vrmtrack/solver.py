"""MediaPipe のランドマークから VRM 1.0 正規化ボーン回転と表情を求める。

プラットフォームに依存しない純粋な計算部分 (numpy のみ)。Windows / Linux の
Python から使うほか、同じ考え方を Android 版へ移植しやすいよう入出力を単純な
配列・辞書にしている。

出力の回転は VRM 正規化空間 (Godot/glTF 座標: Y 上, +Z 前, +X = モデルの左)。
VMC で送るときに Unity 座標へ変換する (vmc.py)。

精度・安定性のための工夫:
- One Euro フィルタ: 止まっているときは強くなめらかに、速く動くときは遅れを小さく。
- キャリブレーション: 正面を向いた無表情の状態を基準にする (カメラの傾き・座る向き・
  普段の目の開き具合や口元の個人差を打ち消す)。
- 手のひらの裏返り誤検出を数フレームまで無視、画面端の不安定な手は使わない。
- 見失った腕・手は少し待ってから自然に下ろす (固まったり跳ねたりしない)。
"""
from __future__ import annotations

import math
import time
from dataclasses import asdict, dataclass, field

import numpy as np

from .mathq import (IDENT, angle_between, frame, norm, q_axis_angle, q_from_matrix,
                    q_from_to, q_inv, q_mul, q_rot, q_scale, q_slerp)

# MediaPipe Pose のランドマーク番号 (左右は「本人から見た」左右)
P_NOSE = 0
P_L_EAR, P_R_EAR = 7, 8
P_L_SH, P_R_SH = 11, 12
P_L_EL, P_R_EL = 13, 14
P_L_WR, P_R_WR = 15, 16
P_L_HIP, P_R_HIP = 23, 24
P_L_KNEE, P_R_KNEE = 25, 26
P_L_ANK, P_R_ANK = 27, 28
P_L_FOOT, P_R_FOOT = 31, 32

FINGERS = {
    # VRM 名: (MediaPipe Hand のランドマーク番号の連なり)
    "Thumb": (1, 2, 3, 4),
    "Index": (5, 6, 7, 8),
    "Middle": (9, 10, 11, 12),
    "Ring": (13, 14, 15, 16),
    "Little": (17, 18, 19, 20),
}
FINGER_BONES = {
    "Thumb": ("ThumbMetacarpal", "ThumbProximal", "ThumbDistal"),
    "Index": ("IndexProximal", "IndexIntermediate", "IndexDistal"),
    "Middle": ("MiddleProximal", "MiddleIntermediate", "MiddleDistal"),
    "Ring": ("RingProximal", "RingIntermediate", "RingDistal"),
    "Little": ("LittleProximal", "LittleIntermediate", "LittleDistal"),
}
ARM_BONES = ("Shoulder", "UpperArm", "LowerArm")
LEG_BONES = ("UpperLeg", "LowerLeg")
HAND_BONES = ("Hand",) + tuple(b for names in FINGER_BONES.values() for b in names)
SHOULDER_WIDTH_M = 0.38  # 腰の移動量を画像から求めるときの目安

# ARKit 系ブレンドシェイプ名で左右がある接尾辞
_LR_SWAP = (("Left", "\x00"), ("Right", "Left"), ("\x00", "Right"))
_BLINK_KEYS = ("blinkLeft", "blinkRight", "blink")


def _swap_lr(name: str) -> str:
    for a, b in _LR_SWAP:
        name = name.replace(a, b)
    return name


def _clamp01(v: float) -> float:
    return max(0.0, min(1.0, v))


def _ramp(v: float, lo: float, hi: float) -> float:
    return _clamp01((v - lo) / max(1e-6, hi - lo))


def _twist(q: np.ndarray, axis: np.ndarray) -> np.ndarray:
    """回転 q のうち、axis まわりのひねり成分 (swing-twist 分解の twist)。"""
    q = np.asarray(q, dtype=float)
    v = axis * float(np.dot(q[:3], axis))
    t = np.array([v[0], v[1], v[2], q[3]])
    n = float(np.linalg.norm(t))
    if n < 1e-9:
        return IDENT.copy()
    t /= n
    return t if t[3] >= 0 else -t


def q_angle(a: np.ndarray, b: np.ndarray) -> float:
    d = abs(float(np.dot(a, b)))
    return 2.0 * math.acos(min(1.0, d))


def q_average(qs: list) -> np.ndarray:
    """近い回転どうしの平均 (符号をそろえて足し、正規化)。"""
    ref = np.asarray(qs[0], dtype=float)
    acc = np.zeros(4)
    for q in qs:
        q = np.asarray(q, dtype=float)
        acc += q if np.dot(q, ref) >= 0 else -q
    return acc / max(1e-9, float(np.linalg.norm(acc)))


@dataclass
class SolverConfig:
    mirror: bool = True            # 鏡のように動かす (右手を上げると画面上の同じ側が上がる)
    smooth: float = 0.85           # 0 = 平滑化なし, 1 に近いほど止まっているときに滑らか
    stabilize: float = 0.5         # 小刻みな揺れの抑制 (0 = なし)。この大きさ以下の細かい動きを止める
    responsiveness: float = 0.5    # 速い動きへの追従 (One Euro の beta)。大きいほど遅れが少ない
    use_face: bool = True
    use_body: bool = True          # 胴体と腕
    use_hands: bool = True
    use_legs: bool = False         # 脚 (Webカメラでは映らないことが多いので既定はオフ)
    hips_move: bool = True         # 全身: 立ち位置の移動・しゃがみを腰の位置へ
    min_visibility: float = 0.55
    head_gain: float = 1.0         # 頭の回転の大きさ
    body_follow: float = 0.35      # 体が映っていないとき、頭の回転の何割を上半身へ回すか
    gaze: bool = True
    gaze_gain: float = 1.0
    gaze_link: bool = True         # 左右の目の視線を同期 (オフ: 片目ずつ。寄り目・離れ目も出る)
    gaze_limit_h: float = 25.0     # 目の可動限界 左右 (度)
    gaze_limit_up: float = 15.0    # 目の可動限界 上 (度)
    gaze_limit_down: float = 12.0  # 目の可動限界 下 (度)
    blink_link: bool = False       # 両目のまばたきを連動
    blink_sens: float = 0.5        # まばたきの感度 (大きいほど閉じやすい)
    mouth_gain: float = 1.0        # 口の開きの大きさ
    expressions: bool = True       # 喜・怒・驚 を自動で付ける
    happy_sens: float = 0.2        # 笑顔の感度 (大きいほど小さな笑顔でも付く)
    happy_gain: float = 0.5        # 笑顔の強さ (付いたときの最大値)
    angry_sens: float = 0.5
    angry_gain: float = 0.8
    surprised_sens: float = 0.5
    surprised_gain: float = 0.8
    fingers: bool = True
    arm_from_hand: bool = True     # 腕が取れず手だけ見えているとき、手の位置から腕を推定する
    shoulder_gain: float = 1.0     # 肩の上げ下げの強さ (0 = 動かさない)
    shoulder_sens: float = 0.5     # 肩の上げ下げの感度 (大きいほど小さな動きでも動く)
    forearm_twist: float = 0.7     # 手首のひねりのうち、前腕に回す割合 (手首だけがねじれるのを防ぐ)
    hand_edge: float = 0.03        # 画面の端からこの割合以内にある手は不安定なので使わない
    arms_rest: bool = True         # 見失った腕・手を下ろす
    lost_hold: float = 0.5         # 見失ってから下ろし始めるまで (秒)
    lost_return: float = 0.6       # 下ろすのにかける時間 (秒)

    def update(self, d: dict) -> None:
        for k, v in d.items():
            if hasattr(self, k):
                cur = getattr(self, k)
                try:
                    if isinstance(cur, bool):
                        setattr(self, k, bool(v))
                    else:
                        val = type(cur)(v)
                        if isinstance(val, float) and not math.isfinite(val):
                            continue
                        setattr(self, k, val)
                except (ValueError, TypeError):
                    continue


@dataclass
class Calibration:
    head: list | None = None       # 正面を向いたときの頭の回転 (カメラ座標)
    body: list | None = None       # 正面を向いたときの胸の回転 (カメラの傾き・座る向き)
    blends: dict = field(default_factory=dict)  # 無表情のときの各ブレンドシェイプ値
    gaze: list | None = None       # 正面を見たときの視線 [左右, 上下]
    hip: list | None = None        # 腰の中心 (画像座標) [x, y, 肩幅]
    shoulder: list | None = None   # 肩の高さ (耳からの距離 / 肩幅) [左, 右]
    mirror: bool = True
    time: str = ""

    def to_dict(self) -> dict:
        return asdict(self)

    @staticmethod
    def from_dict(d: dict) -> "Calibration":
        c = Calibration()
        for k in asdict(c):
            if k in d:
                setattr(c, k, d[k])
        return c

    @property
    def done(self) -> bool:
        return bool(self.time)


@dataclass
class SolveResult:
    bones: dict = field(default_factory=dict)   # vrm ボーン名 → quat [x,y,z,w]
    blends: dict = field(default_factory=dict)  # vrm 表情名 → 0..1
    hips_pos: np.ndarray | None = None


class _Euro:
    """方向コヒーレンス加重・2 次カスケード One Euro フィルタ (スカラー・ベクトル・四元数)。"""

    def __init__(self) -> None:
        self.prev = None
        self.stage2 = None
        self.raw_prev = None
        self.speed = 0.0
        self.speed_ema = 0.0
        self.coh_env = 0.0
        self.vel_env = 0.0
        self.vel_vec = np.zeros(3, dtype=float)

    @staticmethod
    def alpha(cutoff: float, dt: float) -> float:
        tau = 1.0 / (2.0 * math.pi * max(1e-3, cutoff))
        return 1.0 / (1.0 + tau / dt)

    def _cut(self, dist: float, dt: float, mc: float, beta: float) -> float:
        a_d = self.alpha(1.0, dt)
        self.speed += a_d * (dist / dt - self.speed)
        return self.alpha(mc + beta * abs(self.speed), dt)

    def reset_quat(self, q: np.ndarray) -> None:
        self.prev = q
        self.stage2 = q
        self.raw_prev = q
        self.speed = 0.0
        self.speed_ema = 0.0
        self.coh_env = 0.0
        self.vel_env = 0.0
        self.vel_vec.fill(0.0)

    def quat(self, q: np.ndarray, dt: float, mc: float, beta: float, stab: float = 0.0) -> np.ndarray:
        q = np.asarray(q, dtype=float)
        if not np.all(np.isfinite(q)):
            out = self.stage2 if self.stage2 is not None else self.prev
            return out if out is not None else IDENT.copy()
        n = float(np.linalg.norm(q))
        if n < 1e-12:
            out = self.stage2 if self.stage2 is not None else self.prev
            return out if out is not None else IDENT.copy()
        q = q / n
        if self.prev is None:
            self.reset_quat(q)
            return q

        ref = self.raw_prev if self.raw_prev is not None else self.prev
        dq = q_mul(q, q_inv(ref))
        if dq[3] < 0.0:
            dq = -dq
        v_norm = float(np.linalg.norm(dq[:3]))
        theta = 2.0 * math.atan2(v_norm, max(0.0, float(dq[3])))
        vel = (theta / dt) * (dq[:3] / v_norm) if v_norm > 1e-9 else np.zeros(3, dtype=float)
        self.raw_prev = q

        a_d = self.alpha(3.0, dt)
        self.vel_vec = self.vel_vec + a_d * (vel - self.vel_vec)
        self.speed_ema += a_d * (theta / dt - self.speed_ema)
        v_mag = float(np.linalg.norm(self.vel_vec))
        self.speed = v_mag
        c_inst = min(1.0, v_mag / max(1e-6, self.speed_ema)) if self.speed_ema > 1e-6 else 0.0

        # 速い立ち上がり・緩やかな減衰 (150ms 級) により、手振り折り返しでの遮断周波数急落 (位相鞭打ち) を防ぐ
        a_rel = self.alpha(1.2, dt)
        self.coh_env = c_inst if c_inst > self.coh_env else self.coh_env + a_rel * (c_inst - self.coh_env)
        v_stroke = v_mag * self.coh_env
        self.vel_env = v_stroke if v_stroke > self.vel_env else self.vel_env + a_rel * (v_stroke - self.vel_env)

        mc_eff = mc
        if stab > 0.0:
            cur_out = self.stage2 if self.stage2 is not None else self.prev
            amp = _clamp01(q_angle(cur_out, q) / max(1e-6, stab))
            gate = max(self.coh_env * self.coh_env, amp)
            strength = min(2.0, stab / math.radians(1.0))
            mc_eff = mc / (1.0 + 10.0 * strength * (1.0 - gate) ** 2)

        # 2 段カスケード (-12 dB/oct, 臨界減衰的) の実効遮断周波数を揃えるため 1.55 倍
        a = self.alpha(1.55 * (mc_eff + beta * self.vel_env), dt)
        s1 = q_slerp(self.prev, q, a)
        base2 = self.stage2 if self.stage2 is not None else self.prev
        s2 = q_slerp(base2, s1, a)
        if np.all(np.isfinite(s1)) and np.all(np.isfinite(s2)):
            self.prev = s1
            self.stage2 = s2
        return self.stage2 if self.stage2 is not None else self.prev

    def value(self, v, dt: float, mc: float, beta: float):
        v = np.asarray(v, dtype=float)
        if not np.all(np.isfinite(v)):
            return self.prev if self.prev is not None else np.zeros_like(v)
        if self.prev is None:
            self.prev = v
            return v
        a = self._cut(float(np.linalg.norm(v - self.prev)), dt, mc, beta)
        out = self.prev + a * (v - self.prev)
        if np.all(np.isfinite(out)):
            self.prev = out
        return self.prev


def rest_pose(bone: str) -> np.ndarray:
    """腕を見失ったときに戻す自然な姿勢 (腕を体の横に下ろす)。"""
    if bone == "leftUpperArm":
        return q_axis_angle([0, 0, 1], -math.radians(72))
    if bone == "rightUpperArm":
        return q_axis_angle([0, 0, 1], math.radians(72))
    if bone == "leftLowerArm":
        return q_axis_angle([0, 1, 0], math.radians(8))
    if bone == "rightLowerArm":
        return q_axis_angle([0, 1, 0], -math.radians(8))
    return IDENT.copy()


class Solver:
    def __init__(self, cfg: SolverConfig | None = None, calib: Calibration | None = None) -> None:
        self.cfg = cfg or SolverConfig()
        self.calib = calib or Calibration()
        self._bone_f: dict[str, _Euro] = {}
        self._blend_f: dict[str, _Euro] = {}
        self._hips_f = _Euro()
        self._last_out: dict[str, np.ndarray] = {}
        self._seen: dict[str, float] = {}
        self._prev_hand: dict[str, np.ndarray] = {}
        self._flip: dict[str, int] = {}
        self._t_prev: float | None = None
        self._raw: dict = {}
        self._capture: dict | None = None
        self._img = None
        self.aspect = 16.0 / 9.0       # 画像の横/縦 (トラッカーが毎フレーム入れる)
        self._sh_base: list | None = None
        self._hip_base: list | None = None
        self._hip_base_mirror: bool | None = None
        self._sh_q: dict = {}
        self._chest_world = None
        self._inv0 = None
        self._dt = 1.0 / 30.0
        self._t_now = 0.0
        self._arm_ok: dict[str, bool] = {}       # 前のフレームで姿勢推定の腕を使えたか (しきい値のヒステリシス)
        self._knee_ok: dict[str, bool] = {}      # 前のフレームで膝を使えたか (しきい値のヒステリシス)
        self._leg_ok: dict[str, bool] = {}       # 前のフレームで足首まで使えたか (しきい値のヒステリシス)
        self._pose_arm: dict[str, tuple] = {}    # 側 → (上腕, 前腕, 時刻): 最後に信用できた姿勢推定の腕
        self._est_w: dict[str, float] = {}       # 側 → 手から推定した腕を混ぜる割合 (0 = 姿勢推定, 1 = 推定)
        self._pose_arm_vec: dict[str, tuple] = {}
        self._good_pose_vec: dict[str, tuple] = {}
        self._last_hand2d: dict[str, tuple] = {}
        self._hand_pos_f: dict[str, _Euro] = {}
        self._hand_jump: dict[str, int] = {}
        self._pole_f: dict[str, np.ndarray] = {}
        self._palm_base: dict[str, float] = {}
        self._pose_trust: dict[str, float] = {}

    # ------------------------------------------------------------------ キャリブレーション
    def start_capture(self) -> None:
        self._capture = {"n": 0, "head": [], "body": [], "blends": [], "gaze": [], "hip": [], "shoulder": []}

    @property
    def capturing(self) -> bool:
        return self._capture is not None

    def finish_capture(self) -> Calibration:
        cap, self._capture = self._capture or {}, None
        c = Calibration(mirror=self.cfg.mirror, time=time.strftime("%Y-%m-%d %H:%M"))
        need = max(1, cap.get("n", 0) // 2)  # 半分以上のフレームで取れた部位だけ使う
        cap = {k: v for k, v in cap.items() if k == "n" or len(v) >= need}
        if not cap.get("head") and not cap.get("body"):
            return Calibration()
        if self.cfg.use_face and not cap.get("head"):
            return Calibration()  # 顔が映っていない
        if cap.get("head"):
            c.head = q_average(cap["head"]).tolist()
        if cap.get("body"):
            c.body = q_average(cap["body"]).tolist()
        if cap.get("blends"):
            keys = set().union(*[b.keys() for b in cap["blends"]])
            c.blends = {k: float(np.mean([b.get(k, 0.0) for b in cap["blends"]])) for k in keys}
        if cap.get("gaze"):
            c.gaze = np.mean(np.asarray(cap["gaze"]), axis=0).tolist()
        if cap.get("hip"):
            c.hip = np.mean(np.asarray(cap["hip"]), axis=0).tolist()
            self._hip_base = None
        if cap.get("shoulder"):
            c.shoulder = np.mean(np.asarray(cap["shoulder"]), axis=0).tolist()
            self._sh_base = None
        self.calib = c
        return c

    def clear_calibration(self) -> None:
        self.calib = Calibration()
        self._sh_base = None
        self._hip_base = None
        self._hip_base_mirror = None
        self._palm_base.clear()

    def _cal_q(self, key: str):
        q = getattr(self.calib, key)
        if q is None or self.calib.mirror != self.cfg.mirror:
            return None
        return np.asarray(q, dtype=float)

    # ------------------------------------------------------------------ 座標変換
    def _pw(self, lm) -> np.ndarray:
        """MediaPipe ワールド座標 (x右, y下, z奥行=小さいほど手前) → VRM 空間。"""
        x = -lm.x if self.cfg.mirror else lm.x
        return np.array([x, -lm.y, -lm.z], dtype=float)

    def _pa(self, lm) -> np.ndarray:
        """画像座標を、横と縦の長さがそろった 2D に (x に横/縦の比を掛ける)。"""
        v = self._pi(lm)
        return np.array([v[0] * self.aspect, v[1]], dtype=float)

    def _pi(self, lm) -> np.ndarray:
        """正規化画像座標 (0..1) を、鏡像を考慮した 2D に。"""
        x = 1.0 - lm.x if self.cfg.mirror else lm.x
        return np.array([x, lm.y], dtype=float)

    def _side(self, left_idx: int, right_idx: int) -> tuple[int, int]:
        """モデルの (左, 右) に使うランドマーク番号。鏡モードでは本人の左右を入れ替える。"""
        return (right_idx, left_idx) if self.cfg.mirror else (left_idx, right_idx)

    # ------------------------------------------------------------------ 本体
    def solve(self, pose_world=None, pose_image=None, hands=None, face=None, t: float | None = None) -> SolveResult:
        cfg = self.cfg
        t = time.perf_counter() if t is None else t
        dt = 1.0 / 30.0 if self._t_prev is None else min(0.25, max(1e-3, t - self._t_prev))
        self._dt, self._t_now = dt, t
        self._t_prev = t
        self._raw = {}
        res = SolveResult()
        chest_world = IDENT.copy()

        body_ok = cfg.use_body and pose_world is not None and len(pose_world) >= 25
        self._img = pose_image
        self._chest_world = None
        self._sh_q = {}
        if body_ok:
            chest_world = self._solve_body(pose_world, res)
            if cfg.hips_move and pose_image is not None:
                self._solve_hips(pose_image, res)

        if cfg.use_face and face is not None:
            self._solve_face(face, chest_world, res, body_ok)

        if cfg.use_hands and hands and body_ok and pose_image is not None:
            self._solve_hands(hands, pose_image, res)

        if self._capture is not None:
            self._capture["n"] += 1
            for k in ("head", "body", "blends", "gaze", "hip", "shoulder"):
                if k in self._raw:
                    self._capture[k].append(self._raw[k])

        for k in [k for k in res.bones if k.startswith("__")]:
            res.bones.pop(k)
        held = self._handle_lost(res, t, dt)
        return self._smooth(res, dt, held)

    # ------------------------------------------------------------------ 体
    @staticmethod
    def _in_frame(lm, margin: float) -> bool:
        x, y = float(lm.x), float(lm.y)
        return -margin <= x <= 1.0 + margin and -margin <= y <= 1.0 + margin

    def _vis(self, lms, i: int) -> float:
        v = getattr(lms[i], "visibility", 1.0)
        return 1.0 if v is None else float(v)

    def _solve_body(self, w, res: SolveResult) -> np.ndarray:
        cfg = self.cfg
        ls, rs = self._side(P_L_SH, P_R_SH)
        le, re = self._side(P_L_EL, P_R_EL)
        lw, rw = self._side(P_L_WR, P_R_WR)
        lh, rh = self._side(P_L_HIP, P_R_HIP)
        hips_ok = min(self._vis(w, lh), self._vis(w, rh)) > cfg.min_visibility

        need_idx = {ls, rs, le, re, lw, rw, lh, rh}
        if cfg.use_legs and hips_ok:
            lk, rk = self._side(P_L_KNEE, P_R_KNEE)
            la, ra = self._side(P_L_ANK, P_R_ANK)
            need_idx.update((lk, rk, la, ra))
        p = {i: self._pw(w[i]) for i in need_idx}

        def chest_of(pts) -> np.ndarray:
            sh_c = (pts[ls] + pts[rs]) * 0.5
            up = sh_c - (pts[lh] + pts[rh]) * 0.5 if hips_ok else np.array([0.0, 1.0, 0.0])
            return q_from_matrix(frame(pts[ls] - pts[rs], up))

        self._raw["body"] = chest_of(p).tolist()
        body0 = self._cal_q("body")
        self._inv0 = None
        if body0 is not None:
            inv0 = q_inv(body0)
            self._inv0 = inv0
            p = {i: q_rot(inv0, v) for i, v in p.items()}

        # 胸: X = 肩ライン (右肩→左肩), Y = 背骨方向
        chest_world = chest_of(p)
        # 体のひねり・傾きを spine と chest に半分ずつ
        half = q_scale(chest_world, 0.5)
        res.bones["spine"] = half
        res.bones["chest"] = q_mul(q_inv(half), chest_world)
        res.bones["upperChest"] = IDENT.copy()
        self._chest_world = chest_world
        self._solve_shoulders(res)

        # 腕
        self._pose_arm_vec = {}
        for side, s_i, e_i, w_i, rest_x in (("left", ls, le, lw, 1.0), ("right", rs, re, rw, -1.0)):
            thr = cfg.min_visibility * (0.55 if self._arm_ok.get(side) else 0.8)
            self._arm_ok[side] = False
            vis_arm = min(self._vis(w, e_i), self._vis(w, w_i))
            if vis_arm < thr:
                continue
            if self._img is not None and not self._in_frame(self._img[w_i], 0.02):
                continue  # 画面の外の手首は推測の位置なので、腕を動かさない (反対の手の誤動作の元)
            self._arm_ok[side] = True
            self._pose_arm_vec[side] = (p[e_i] - p[s_i], p[w_i] - p[s_i], vis_arm)
            rest = np.array([rest_x, 0.0, 0.0])
            parent = q_mul(chest_world, self._sh_q.get(side, IDENT))  # 肩の先
            up_world = q_mul(q_from_to(q_rot(parent, rest), p[e_i] - p[s_i]), parent)
            res.bones[f"{side}UpperArm"] = q_mul(q_inv(parent), up_world)
            lo_world = q_mul(q_from_to(q_rot(up_world, rest), p[w_i] - p[e_i]), up_world)
            res.bones[f"{side}LowerArm"] = q_mul(q_inv(up_world), lo_world)
            res.bones[f"__{side}LowerArmWorld"] = lo_world

        # 脚 (任意)
        if cfg.use_legs and hips_ok:
            down = np.array([0.0, -1.0, 0.0])
            for side, h_i, k_i, a_i in (("left", lh, lk, la), ("right", rh, rk, ra)):
                thr_k = cfg.min_visibility * (0.55 if self._knee_ok.get(side) else 0.8)
                thr_a = cfg.min_visibility * (0.55 if self._leg_ok.get(side) else 0.8)
                knee_ok = self._vis(w, k_i) >= thr_k
                if knee_ok and self._img is not None and not self._in_frame(self._img[k_i], 0.02):
                    knee_ok = False
                ank_ok = knee_ok and self._vis(w, a_i) >= thr_a
                if ank_ok and self._img is not None and not self._in_frame(self._img[a_i], 0.02):
                    ank_ok = False
                self._knee_ok[side] = knee_ok
                self._leg_ok[side] = ank_ok
                if not knee_ok:
                    continue
                ul = q_from_to(down, p[k_i] - p[h_i])
                res.bones[f"{side}UpperLeg"] = ul
                if not ank_ok:
                    continue
                ll_world = q_mul(q_from_to(q_rot(ul, down), p[a_i] - p[k_i]), ul)
                ll = q_mul(q_inv(ul), ll_world)
                # 膝の過伸展 (+Z 方向への逆関節曲げ) を防ぐ
                shin = q_rot(ll, down)
                if shin[2] > 0.02:
                    clamped = np.array([shin[0], shin[1], 0.0], dtype=float)
                    ll = q_from_to(down, clamped) if float(np.linalg.norm(clamped)) > 1e-6 else IDENT.copy()
                res.bones[f"{side}LowerLeg"] = ll
        else:
            self._knee_ok.clear()
            self._leg_ok.clear()
        return chest_world

    def _solve_shoulders(self, res: SolveResult) -> None:
        """肩の上げ下げ: 耳から肩までの縦の距離 (肩幅で割る) が、ふだん (補正時) より縮んだ分だけ肩を上げる。
        耳はうなずいてもほとんど上下しないので、頭の動きに引きずられにくい。"""
        cfg = self.cfg
        img = self._img
        for side in ("left", "right"):
            res.bones[f"{side}Shoulder"] = IDENT.copy()
        if img is None or cfg.shoulder_gain <= 0.0 or len(img) < 13:
            return
        ls, rs = self._side(P_L_SH, P_R_SH)
        if min(self._vis(img, ls), self._vis(img, rs), self._vis(img, 7), self._vis(img, 8)) < cfg.min_visibility:
            return
        sw = float(np.linalg.norm(self._pa(img[ls]) - self._pa(img[rs])))
        if sw < 0.03:
            return
        ear_y = (float(img[7].y) + float(img[8].y)) * 0.5
        cur = [(float(img[ls].y) - ear_y) / sw, (float(img[rs].y) - ear_y) / sw]
        self._raw["shoulder"] = cur
        base = self.calib.shoulder if (self.calib.shoulder and self.calib.mirror == cfg.mirror) else None
        if base is None:
            # 補正していないときは、ふだんの高さをゆっくり追いかける (最初のフレームが基準)
            if self._sh_base is None:
                self._sh_base = list(cur)
            else:
                alpha_sh = 1.0 - math.exp(-self._dt * 0.06)
                self._sh_base = [b + (c - b) * alpha_sh for b, c in zip(self._sh_base, cur)]
            base = self._sh_base
        dead = max(0.0, 0.03 + (0.5 - _clamp01(cfg.shoulder_sens)) * 0.06)
        for i, side in enumerate(("left", "right")):
            delta = float(base[i]) - cur[i]  # 正 = 肩が上がった
            mag = math.copysign(max(0.0, abs(delta) - dead), delta)
            ang = max(-10.0, min(30.0, mag * 110.0 * cfg.shoulder_gain))
            sign = 1.0 if side == "left" else -1.0
            q = q_axis_angle(np.array([0.0, 0.0, sign]), math.radians(ang))
            self._sh_q[side] = q
            res.bones[f"{side}Shoulder"] = q

    def _arm_from_hand(
        self,
        side: str,
        hand2d: np.ndarray,
        sh2d: np.ndarray,
        sw: float,
        pose_trust: float = 0.0,
        pose_vec: tuple | None = None,
        palm_scale: float = 1.0,
        face_near: float = 0.0,
    ) -> tuple:
        """手主導ハイブリッド 2-Bone IK: 手首位置から上腕・前腕を連続的に求め、
        信頼できる Pose 肘・奥行きと高度適応型ポールベクトルを滑らかに融合する。"""
        sign = 1.0 if side == "left" else -1.0
        k = SHOULDER_WIDTH_M / max(0.03, sw)
        dx = float(hand2d[0] - sh2d[0]) * k
        dy = -float(hand2d[1] - sh2d[1]) * k
        lu, ll = 0.28, 0.26
        reach = (lu + ll) * 0.98
        planar = math.hypot(dx, dy)
        if planar > reach * 0.99:
            s_cl = (reach * 0.99) / planar
            dx, dy, planar = dx * s_cl, dy * s_cl, reach * 0.99
        base_r = reach * 0.72
        dz_geo = math.sqrt(max(0.02 * 0.02, base_r * base_r - planar * planar * 0.65))
        dz_est = max(0.02, dz_geo + 0.14 * (palm_scale - 1.0))
        t = np.array([dx, dy, dz_est], dtype=float)
        if self._inv0 is not None:
            t = q_rot(self._inv0, t)
        if pose_vec is not None and pose_trust > 0.01:
            p_wr = np.asarray(pose_vec[1], dtype=float)
            z_pose = float(p_wr[2]) if abs(float(p_wr[2])) > 0.02 else float(t[2])
            t_p = np.array([t[0], t[1], z_pose], dtype=float)
            len_p = max(0.08, min(reach, float(np.linalg.norm(p_wr))))
            if float(np.linalg.norm(t_p)) > 1e-6:
                t_p = norm(t_p) * len_p
                t = t * (1.0 - pose_trust) + t_p * pose_trust

        dist = max(0.06, min(reach, float(np.linalg.norm(t))))
        n = norm(t)

        # 高さと顔近接度に応じた特異点フリーの肘ポールベクトル (手を顔前に上げた際の180度反転を防ぐ)
        elev = _clamp01((float(t[1]) + 0.10) / 0.45)
        cross = _clamp01((-sign * float(t[0])) / 0.25)
        pole_low = np.array([sign * 0.25, -1.0, -0.35], dtype=float)
        pole_high = np.array([sign * (0.55 + 0.25 * cross), -0.65, 0.30], dtype=float)
        pole_target = norm(pole_low * (1.0 - elev) + pole_high * elev)

        if pose_vec is not None and pose_trust > 0.01:
            p_el = np.asarray(pose_vec[0], dtype=float)
            el_perp = p_el - n * float(np.dot(p_el, n))
            if float(np.linalg.norm(el_perp)) > 0.04:
                swivel_w = pose_trust * 0.7
                pole_target = norm(pole_target * (1.0 - swivel_w) + norm(el_perp) * swivel_w)

        b = pole_target - n * float(np.dot(pole_target, n))
        if float(np.linalg.norm(b)) < 0.08:
            fb = np.array([sign, 0.0, -0.3], dtype=float)
            b = fb - n * float(np.dot(fb, n))
            if float(np.linalg.norm(b)) < 1e-6:
                b = np.array([0.0, -1.0, 0.0]) - n * float(-n[1])
        b = norm(b)

        prev_b = self._pole_f.get(side)
        if prev_b is not None:
            rate = 8.0 if face_near > 0.2 else 16.0
            a_p = 1.0 - math.exp(-self._dt * rate) if self.cfg.smooth > 0.0 else 1.0
            b_mix = prev_b * (1.0 - a_p) + b * a_p
            b_ortho = b_mix - n * float(np.dot(b_mix, n))
            if float(np.linalg.norm(b_ortho)) > 1e-6:
                b = norm(b_ortho)
        self._pole_f[side] = b

        cos_a = max(-1.0, min(1.0, (lu * lu + dist * dist - ll * ll) / (2.0 * lu * dist)))
        sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
        elbow = n * cos_a * lu + b * sin_a * lu
        lower = n * dist - elbow
        rest = np.array([sign, 0.0, 0.0])
        parent = q_mul(self._chest_world, self._sh_q.get(side, IDENT))
        up_world = q_mul(q_from_to(q_rot(parent, rest), elbow), parent)
        lo_world = q_mul(q_from_to(q_rot(up_world, rest), lower), up_world)
        return q_mul(q_inv(parent), up_world), q_mul(q_inv(up_world), lo_world)

    def _solve_hips(self, img, res: SolveResult) -> None:
        """画像上の腰の位置と肩幅の変化から、立ち位置の移動・しゃがみ・前後を求める。"""
        if min(self._vis(img, P_L_HIP), self._vis(img, P_R_HIP)) < self.cfg.min_visibility:
            return
        hip = (self._pi(img[P_L_HIP]) + self._pi(img[P_R_HIP])) * 0.5
        sw = float(np.linalg.norm(self._pi(img[P_L_SH]) - self._pi(img[P_R_SH])))
        if sw < 0.02:
            return
        self._raw["hip"] = [float(hip[0]), float(hip[1]), sw]
        base = self.calib.hip if (self.calib.hip and self.calib.mirror == self.cfg.mirror) else None
        if base is None:
            if self._hip_base is None or self._hip_base_mirror != self.cfg.mirror:
                self._hip_base = [float(hip[0]), float(hip[1]), sw]  # 未補正なら最初の位置を基準に (calib 自体は汚さない)
                self._hip_base_mirror = self.cfg.mirror
            base = self._hip_base
        x0, y0, sw0 = base
        k = SHOULDER_WIDTH_M / max(0.02, sw0)
        x = (hip[0] - x0) * k
        y = -(hip[1] - y0) * k
        z = 1.5 * (1.0 - sw0 / sw)
        res.hips_pos = np.clip(np.array([x, y, z]), -1.0, 1.0)

    # ------------------------------------------------------------------ 顔
    def _solve_face(self, face: dict, chest_world: np.ndarray, res: SolveResult, body_ok: bool) -> None:
        cfg = self.cfg
        mat = face.get("matrix")
        if mat is not None:
            r = np.asarray(mat, dtype=float)[:3, :3]
            # 拡大成分を除く
            r = np.stack([norm(r[:, 0]), norm(r[:, 1]), norm(r[:, 2])], axis=1)
            if cfg.mirror:
                s = np.diag([-1.0, 1.0, 1.0])
                r = s @ r @ s
            head_world = q_from_matrix(r)
            self._raw["head"] = head_world.tolist()
            head0 = self._cal_q("head")
            if head0 is not None:
                head_world = q_mul(head_world, q_inv(head0))
            if cfg.head_gain != 1.0:
                head_world = q_scale(head_world, cfg.head_gain)
            if not body_ok and cfg.use_body is False and cfg.body_follow > 0.0:
                # 顔だけのとき: 頭の回転の一部を背骨へ回して、首だけが回る不自然さを減らす
                part = q_scale(head_world, cfg.body_follow * 0.5)
                res.bones["spine"] = part
                res.bones["chest"] = part.copy()
                chest_world = q_mul(part, part)
            rel = q_mul(q_inv(chest_world), head_world)
            neck = q_scale(rel, 0.4)
            res.bones["neck"] = neck
            res.bones["head"] = q_mul(q_inv(neck), rel)

        bs: dict = face.get("blendshapes") or {}
        if cfg.mirror:
            bs = {_swap_lr(k): v for k, v in bs.items()}
        self._raw["blends"] = {k: float(v) for k, v in bs.items()}
        base = self.calib.blends if self.calib.mirror == cfg.mirror else {}

        def g(k: str) -> float:
            v = float(bs.get(k, 0.0))
            b0 = float(base.get(k, 0.0))
            if 0.0 < b0 < 0.9:
                v = (v - b0) / (1.0 - b0)  # 無表情のときを 0 とする
            return _clamp01(v)

        b = res.blends
        lo = 0.38 - 0.28 * _clamp01(cfg.blink_sens)
        hi = lo + 0.4
        bl, br = _ramp(g("eyeBlinkLeft"), lo, hi), _ramp(g("eyeBlinkRight"), lo, hi)
        if cfg.blink_link:
            bl = br = (bl + br) * 0.5
        mg = cfg.mouth_gain
        jaw = _ramp(g("jawOpen"), 0.04, 0.55)
        funnel = _ramp(g("mouthFunnel"), 0.1, 0.6)
        pucker = _ramp(g("mouthPucker"), 0.2, 0.8)
        smile = _ramp((g("mouthSmileLeft") + g("mouthSmileRight")) * 0.5, 0.15, 0.7)
        stretch = _ramp((g("mouthStretchLeft") + g("mouthStretchRight")) * 0.5, 0.1, 0.5)
        b["oh"] = _clamp01(funnel * 0.9 * mg)
        b["ou"] = _clamp01(pucker * (1.0 - funnel) * 0.9 * mg)
        b["aa"] = _clamp01(max(0.0, jaw - funnel * 0.6) * mg)
        b["ee"] = _clamp01(stretch * (1.0 - jaw) * 0.8 * mg)
        b["ih"] = _clamp01(max(0.0, smile * 0.4 * jaw) * mg)
        if cfg.expressions:
            # 目を閉じると、頬が上がって口角の値 (mouthSmile) も上がりやすい。その分を差し引いて誤反応を防ぐ
            eye_closed = max(0.0, (g("eyeBlinkLeft") + g("eyeBlinkRight")) * 0.5 - 0.25)
            squint = (g("eyeSquintLeft") + g("eyeSquintRight")) * 0.5
            smile_e = (g("mouthSmileLeft") + g("mouthSmileRight")) * 0.5 - 0.45 * eye_closed - 0.15 * squint
            lo_h = 0.3 + (0.5 - _clamp01(cfg.happy_sens)) * 0.4
            happy = _ramp(smile_e, lo_h, lo_h + 0.4) * cfg.happy_gain
            lo_s = 0.35 + (0.5 - _clamp01(cfg.surprised_sens)) * 0.4
            surprised = _ramp(g("browInnerUp"), lo_s, lo_s + 0.5) * _ramp(g("eyeWideLeft") + g("eyeWideRight"), 0.3, 1.2)
            lo_a = 0.35 + (0.5 - _clamp01(cfg.angry_sens)) * 0.4
            angry = _ramp((g("browDownLeft") + g("browDownRight")) * 0.5, lo_a, lo_a + 0.45) * (1.0 - smile)
            b["happy"] = _clamp01(happy)
            b["surprised"] = _clamp01(surprised * cfg.surprised_gain)
            b["angry"] = _clamp01(angry * cfg.angry_gain)
            # 笑顔の表情は多くのモデルで目を閉じる形を含む。まばたきと重なると目が崩れるので、その分まばたきを減らす
            keep = 1.0 - _clamp01(b["happy"] * 1.2)
            bl, br = bl * keep, br * keep
        else:
            b["happy"] = b["surprised"] = b["angry"] = 0.0
        b["blinkLeft"], b["blinkRight"] = bl, br

        # 視線 → 目のボーン (片目ずつ求め、同期オンなら平均。可動限界で止める)
        raw = lambda k: float(bs.get(k, 0.0))  # noqa: E731
        eyes = {
            # モデルの左目: 外 (= モデルの左) へ向くと +, 右目: 内 (= モデルの左) へ向くと +
            "left": [raw("eyeLookOutLeft") - raw("eyeLookInLeft"), raw("eyeLookUpLeft") - raw("eyeLookDownLeft")],
            "right": [raw("eyeLookInRight") - raw("eyeLookOutRight"), raw("eyeLookUpRight") - raw("eyeLookDownRight")],
        }
        avg = [(eyes["left"][i] + eyes["right"][i]) * 0.5 for i in (0, 1)]
        self._raw["gaze"] = avg
        if cfg.gaze_link:
            eyes = {"left": list(avg), "right": list(avg)}
        if self.calib.gaze is not None and self.calib.mirror == cfg.mirror:
            for v in eyes.values():
                v[0] -= self.calib.gaze[0]
                v[1] -= self.calib.gaze[1]
        for side, (lr, ud) in eyes.items():
            if cfg.gaze:
                yaw = max(-cfg.gaze_limit_h, min(cfg.gaze_limit_h, 22.0 * lr * cfg.gaze_gain))
                up = max(-cfg.gaze_limit_down, min(cfg.gaze_limit_up, 14.0 * ud * cfg.gaze_gain))
                eye = q_mul(q_axis_angle([0, 1, 0], math.radians(yaw)), q_axis_angle([1, 0, 0], -math.radians(up)))
            else:
                eye = IDENT.copy()
            res.bones[f"{side}Eye"] = eye

    # ------------------------------------------------------------------ 手
    def _solve_hands(self, hands: list, pose_image, res: SolveResult) -> None:
        """見えている手を左右の腕に割り当て、手主導ハイブリッド腕 IK で腕と手を安定させる。"""
        cfg = self.cfg
        lw, rw = self._side(P_L_WR, P_R_WR)
        wrist2d = {"left": self._pi(pose_image[lw]), "right": self._pi(pose_image[rw])}
        ls, rs = self._side(P_L_SH, P_R_SH)
        sw = float(np.linalg.norm(self._pi(pose_image[ls]) - self._pi(pose_image[rs])))
        max_d = max(0.08, min(0.25, sw * 0.7))
        sh2d = {"left": self._pa(pose_image[ls]), "right": self._pa(pose_image[rs])}
        swa = max(0.03, float(np.linalg.norm(sh2d["left"] - sh2d["right"])))
        sh_mid_a = (sh2d["left"] + sh2d["right"]) * 0.5
        face_c = sh_mid_a + np.array([0.0, -swa * 0.72])
        if len(pose_image) > P_NOSE and self._vis(pose_image, P_NOSE) >= cfg.min_visibility:
            nose_a = self._pa(pose_image[P_NOSE])
            if nose_a[1] < sh_mid_a[1]:
                face_c = nose_a
        face_r = max(0.06, swa * 0.55)

        e = cfg.hand_edge
        dup_r = max(0.06, sw * 0.35)
        dup_same_hl_r = max(0.14, sw * 0.75)
        good: list = []  # [(img_lms, world_lms, h2d, p2d, h2a, hand_hl, f_near)]
        for item in hands:
            img_lms, world_lms = item[0], item[1]
            hand_hl = item[2] if len(item) >= 3 else None
            h2d = self._pi(img_lms[0])
            if e > 0 and not (e <= h2d[0] <= 1 - e and e <= h2d[1] <= 1 - e):
                continue  # 画面の端の手は形が崩れやすい
            p2d = (h2d + self._pi(img_lms[9])) * 0.5
            hl_label = str(hand_hl[0]) if (hand_hl is not None and len(hand_hl) >= 2 and float(hand_hl[1]) >= 0.55) else ""
            hl_score = float(hand_hl[1]) if (hand_hl is not None and len(hand_hl) >= 2) else 0.0

            # 同じ手の二重検出 (手首/掌が近いもの、または同左右判定で近接するゴースト) を抑止
            dup_idx = -1
            for gi, existing in enumerate(good):
                _, _, eh2d, ep2d, _, ehl, _ = existing
                d_w = float(np.linalg.norm(h2d - eh2d))
                d_p = float(np.linalg.norm(p2d - ep2d))
                same_hl = (
                    hl_label != ""
                    and ehl is not None
                    and len(ehl) >= 2
                    and float(ehl[1]) >= 0.55
                    and str(ehl[0]) == hl_label
                )
                if d_w < dup_r or d_p < dup_r or (same_hl and d_w < dup_same_hl_r):
                    dup_idx = gi
                    break
            h2a = self._pa(img_lms[0])
            f_near = 1.0 - _ramp(float(np.linalg.norm(h2a - face_c)), face_r * 0.5, face_r * 1.5)
            cand = (img_lms, world_lms, h2d, p2d, h2a, hand_hl, f_near)
            if dup_idx >= 0:
                ehl = good[dup_idx][5]
                escore = float(ehl[1]) if (ehl is not None and len(ehl) >= 2) else 0.0
                if hl_score > escore + 0.1:
                    good[dup_idx] = cand  # より信頼度の高い方を残す
                continue
            good.append(cand)

        can_est = (cfg.arm_from_hand and self._chest_world is not None
                   and min(self._vis(pose_image, ls), self._vis(pose_image, rs)) >= cfg.min_visibility)

        assigned: dict = {}  # 側 → (img_lms, world_lms, h2d, h2a, f_near)
        if not can_est:
            # 推定オフ時やテスト時 (胸ワールド回転なし): 姿勢推定の手首が近い腕にのみ割り当てる
            used: set = set()
            for idx, (img_lms, world_lms, h2d, _p2d, h2a, _hl, f_near) in enumerate(good):
                cands = [s for s in ("left", "right") if f"__{s}LowerArmWorld" in res.bones and s not in assigned]
                if not cands:
                    continue
                d = {s: float(np.linalg.norm(wrist2d[s] - h2d)) for s in cands}
                side = min(cands, key=lambda s: d[s])
                if d[side] <= max_d:
                    assigned[side] = (img_lms, world_lms, h2d, h2a, f_near)
                    used.add(idx)
        elif good:
            def assign_cost(entry, side: str) -> float:
                _il, _wl, h2d, _p2d, h2a, hand_hl, f_near = entry
                cost = 0.0
                prev_e = self._last_hand2d.get(side)
                if prev_e is not None and (self._t_now - prev_e[1]) < 0.5:
                    dt_h = max(0.0, self._t_now - prev_e[1])
                    cost += min(1.4, 1.4 * (1.0 - dt_h / 0.5) * float(np.linalg.norm(h2a - prev_e[0])) / swa)
                else:
                    cost += 0.65
                if hand_hl is not None and len(hand_hl) >= 2 and float(hand_hl[1]) >= 0.55:
                    label = str(hand_hl[0])
                    if label in ("Left", "Right"):
                        # 非反転入力前提: MediaPipe の "Left" = 本人の物理右手
                        exp_side = ("left" if label == "Left" else "right") if cfg.mirror else ("right" if label == "Left" else "left")
                        if exp_side != side:
                            cost += 0.75 * float(hand_hl[1])
                w_pw = 1.0 - 0.55 * f_near
                if f"__{side}LowerArmWorld" in res.bones:
                    d_pw = float(np.linalg.norm(wrist2d[side] - h2d))
                    cost += w_pw * 1.1 * min(1.5, d_pw / max(0.05, max_d))
                else:
                    # 姿勢推定でその側の腕が取れていない場合も対称な基準コストを課し、片腕だけ取れている側の手を奪わせない
                    cost += w_pw * 1.1 * 1.15
                cost += 0.25 * float(np.linalg.norm(sh2d[side] - h2a)) / swa
                return cost

            def steals_other_pose(entry, target_side: str) -> bool:
                _il, _wl, h2d_pt, _p2d, _h2a, hand_hl, _fn = entry
                other = "right" if target_side == "left" else "left"
                if f"__{target_side}LowerArmWorld" in res.bones or f"__{other}LowerArmWorld" not in res.bones:
                    return False
                prev_t = self._last_hand2d.get(target_side)
                tracked_target = prev_t is not None and (self._t_now - prev_t[1]) < 0.35
                if tracked_target and hand_hl is not None and len(hand_hl) >= 2 and float(hand_hl[1]) >= 0.75:
                    lbl = str(hand_hl[0])
                    if lbl in ("Left", "Right"):
                        exp_s = ("left" if lbl == "Left" else "right") if cfg.mirror else ("right" if lbl == "Left" else "left")
                        if exp_s == target_side:
                            return False
                return float(np.linalg.norm(wrist2d[other] - h2d_pt)) <= max_d * 1.1

            if len(good) == 1:
                c_l = assign_cost(good[0], "left")
                c_r = assign_cost(good[0], "right")
                best_s = "left" if c_l <= c_r else "right"
                il, wl, h2d, _p2d, h2a, _hl, fn = good[0]
                if steals_other_pose(good[0], best_s):
                    best_s = "right" if best_s == "left" else "left"
                assigned[best_s] = (il, wl, h2d, h2a, fn)
            else:
                pool = good[:4]
                # 最良の片手割り当て (もう片方は無理に付けない比較基準)
                best_single_side = "left"
                best_single_idx = 0
                best_single_c = float("inf")
                for i in range(len(pool)):
                    for s in ("left", "right"):
                        if steals_other_pose(pool[i], s):
                            continue
                        sc = assign_cost(pool[i], s)
                        if sc < best_single_c:
                            best_single_c = sc
                            best_single_side = s
                            best_single_idx = i

                best_pair = None
                best_pair_c = float("inf")
                for i in range(len(pool)):
                    if steals_other_pose(pool[i], "left"):
                        continue
                    c_l = assign_cost(pool[i], "left")
                    if c_l >= 2.3:
                        continue
                    for j in range(len(pool)):
                        if i == j:
                            continue
                        if steals_other_pose(pool[j], "right"):
                            continue
                        c_r = assign_cost(pool[j], "right")
                        if c_r >= 2.3:
                            continue
                        tot = c_l + c_r
                        if tot < best_pair_c:
                            best_pair_c = tot
                            best_pair = (i, j)

                if best_pair is not None and best_pair_c <= best_single_c + 1.65:
                    il0, wl0, h2d0, _p0, h2a0, _hl0, fn0 = pool[best_pair[0]]
                    il1, wl1, h2d1, _p1, h2a1, _hl1, fn1 = pool[best_pair[1]]
                    assigned["left"] = (il0, wl0, h2d0, h2a0, fn0)
                    assigned["right"] = (il1, wl1, h2d1, h2a1, fn1)
                else:
                    il, wl, h2d, _p2d, h2a, _hl, fn = pool[best_single_idx]
                    assigned[best_single_side] = (il, wl, h2d, h2a, fn)

        # 腕を決めて手を付ける
        trust_rate = self._dt / 0.45
        for side in ("left", "right"):
            if side not in assigned:
                if f"{side}UpperArm" in res.bones and side in self._pose_arm_vec:
                    self._good_pose_vec[side] = (self._pose_arm_vec[side][0], self._pose_arm_vec[side][1], self._t_now)
                self._est_w[side] = 0.0
                self._pose_trust[side] = max(0.0, self._pose_trust.get(side, 0.0) - trust_rate)
                continue

            img_lms, world_lms, h2d, h2a, f_near = assigned[side]
            pose_ok = f"__{side}LowerArmWorld" in res.bones and side in self._pose_arm_vec
            d_pw = float(np.linalg.norm(wrist2d[side] - h2d)) if pose_ok else max_d * 2.0
            if not can_est:
                if pose_ok and f"{side}UpperArm" not in res.bones:
                    self._solve_one_hand(side, world_lms, res)
                    continue
                if pose_ok and d_pw <= max_d:
                    self._pose_arm[side] = (res.bones[f"{side}UpperArm"], res.bones[f"{side}LowerArm"], self._t_now)
                elif side in self._pose_arm and self._t_now - self._pose_arm[side][2] < 0.6:
                    up, lo = self._pose_arm[side][:2]
                    res.bones[f"{side}UpperArm"] = up
                    res.bones[f"{side}LowerArm"] = lo
                    parent = q_mul(self._chest_world, self._sh_q.get(side, IDENT)) if self._chest_world is not None else IDENT
                    res.bones[f"__{side}LowerArmWorld"] = q_mul(q_mul(parent, up), lo)
                if f"__{side}LowerArmWorld" in res.bones:
                    self._solve_one_hand(side, world_lms, res)
                continue

            # 1) 顔付近などで起きやすい 1 フレーム外れ値ジャンプの棄却
            jump_lim = max(0.08, swa * (0.45 if f_near > 0.3 else 0.95)) * max(1.0, self._dt / (1.0 / 30.0))
            prev_e = self._last_hand2d.get(side)
            if prev_e is not None and (self._t_now - prev_e[1]) < 0.25:
                step = float(np.linalg.norm(h2a - prev_e[0]))
                if step > jump_lim and self._hand_jump.get(side, 0) < 2:
                    self._hand_jump[side] = self._hand_jump.get(side, 0) + 1
                    h2a = prev_e[0].copy()
                else:
                    self._hand_jump[side] = 0
            else:
                self._hand_jump[side] = 0
            self._last_hand2d[side] = (h2a.copy(), self._t_now)

            # 2) 見かけの手の大きさ比による奥行き補助 + IK 前座標フィルタ
            palm_px = float(np.linalg.norm(self._pa(img_lms[9]) - self._pa(img_lms[0])))
            if palm_px > 1e-4:
                palm_rel = palm_px / swa
                base_p = self._palm_base.get(side)
                if base_p is None:
                    base_p = max(0.14, min(0.30, palm_rel))
                    self._palm_base[side] = base_p
                palm_scale = max(0.6, min(1.8, palm_rel / base_p))
            else:
                palm_scale = 1.0

            hp = np.array([float(h2a[0]), float(h2a[1]), float(palm_scale)], dtype=float)
            f_hp = self._hand_pos_f.setdefault(side, _Euro())
            if cfg.smooth > 0.0:
                s_sm = _clamp01(cfg.smooth)
                mc_h = 0.5 * 10 ** (1.3 * (1.0 - s_sm)) * (1.8 - 1.1 * f_near)
                beta_h = 0.1 + 2.4 * _clamp01(cfg.responsiveness)
                hp = f_hp.value(hp, self._dt, mc_h, beta_h)
            else:
                f_hp.prev = hp
            h2a_f = hp[:2]
            palm_scale_f = float(hp[2])

            # 3) Pose 腕の肘・奥行きへの連続ブレンド重み (瞬間的な欠損・飛びは保ちつつ緩やかに切替)
            agree = pose_ok and (d_pw <= max_d)
            good_v = self._good_pose_vec.get(side)
            if agree:
                p_el, p_wr, raw_vis = self._pose_arm_vec[side]
                self._good_pose_vec[side] = (p_el, p_wr, self._t_now)
                good_v = self._good_pose_vec[side]
                t_target = _clamp01((raw_vis - 0.35) / 0.45) * (1.0 - 0.6 * f_near) * _clamp01(1.15 - d_pw / max(0.05, max_d))
            elif good_v is not None and (self._t_now - good_v[2]) < 0.12:
                # 数フレーム程度の Pose ちらつきでは補助重みを揺らさない (手首 XY は常に手に追従)
                t_target = self._pose_trust.get(side, 0.0)
            else:
                t_target = 0.0

            if side not in self._pose_trust:
                pt = t_target
            else:
                cur_pt = self._pose_trust[side]
                pt = min(t_target, cur_pt + trust_rate) if cur_pt < t_target else max(t_target, cur_pt - trust_rate)
            self._pose_trust[side] = pt

            pose_vec = None
            if pt > 0.01 and good_v is not None and (self._t_now - good_v[2]) < 0.6:
                pose_vec = (good_v[0], good_v[1])
            else:
                pt = 0.0

            up, lo = self._arm_from_hand(
                side, h2a_f, sh2d[side], swa,
                pose_trust=pt, pose_vec=pose_vec, palm_scale=palm_scale_f, face_near=f_near,
            )
            self._est_w[side] = 1.0 - pt
            parent = q_mul(self._chest_world, self._sh_q.get(side, IDENT)) if self._chest_world is not None else IDENT
            res.bones[f"{side}UpperArm"] = up
            res.bones[f"{side}LowerArm"] = lo
            res.bones[f"__{side}LowerArmWorld"] = q_mul(q_mul(parent, up), lo)
            self._solve_one_hand(side, world_lms, res)

    def _solve_one_hand(self, side: str, wl, res: SolveResult) -> None:
        p = [self._pw(l) for l in wl]
        sign = 1.0 if side == "left" else -1.0
        # 掌の向き: 手首→中指付け根 = 指方向, 小指付け根→人差し指付け根 = 前 (+Z)
        meas = frame(p[9] - p[0], p[5] - p[17])
        rest = frame(np.array([sign, 0.0, 0.0]), np.array([0.0, 0.0, 1.0]))
        hand_world = q_from_matrix(meas @ rest.T)
        prev = self._prev_hand.get(side)
        if prev is not None and q_angle(prev, hand_world) > math.radians(110) and self._flip.get(side, 0) < 3:
            # 1 フレームで手のひらが裏返るのはたいてい誤検出。数フレームだけ無視する
            self._flip[side] = self._flip.get(side, 0) + 1
            return
        self._flip[side] = 0
        self._prev_hand[side] = hand_world
        lo_world = res.bones.pop(f"__{side}LowerArmWorld", None)
        if lo_world is not None:
            hand_local = q_mul(q_inv(lo_world), hand_world)
            k = _clamp01(self.cfg.forearm_twist)
            lower = res.bones.get(f"{side}LowerArm")
            if k > 0.0 and lower is not None:
                # 手首のひねり (前腕の軸まわりの回転) の一部を前腕に移す。人の腕も前腕全体でひねっている
                tw = q_scale(_twist(hand_local, np.array([sign, 0.0, 0.0])), k)
                res.bones[f"{side}LowerArm"] = q_mul(lower, tw)
                hand_local = q_mul(q_inv(tw), hand_local)
            res.bones[f"{side}Hand"] = hand_local
        if not self.cfg.fingers:
            return

        # 指の曲げ: 各関節での折れ角を、掌側へ曲げる回転として与える
        finger_axis = np.array([0.0, 0.0, -sign])
        for fname, idx in FINGERS.items():
            if fname == "Thumb":
                self._solve_thumb(side, p, hand_world, res)
                continue
            chain = [p[0]] + [p[i] for i in idx]
            names = FINGER_BONES[fname]
            for j, bname in enumerate(names):
                a = chain[j + 1] - chain[j]
                b = chain[j + 2] - chain[j + 1]
                ang = angle_between(a, b)
                ang = max(0.0, ang - math.radians(8))
                ang = min(ang, math.radians(100))
                res.bones[f"{side}{bname}"] = q_axis_angle(finger_axis, ang)

    def _solve_thumb(self, side: str, p: list, hand_world: np.ndarray, res: SolveResult) -> None:
        """親指: 各節の向きを手の基準姿勢の空間で測り、基準の向き (T ポーズの親指) からの回転にする。
        親指は曲げる向き (掌の上を横切る・開く・前に出す) が自由なので、決まった軸ではなく 3D の向きで求める。"""
        sign = 1.0 if side == "left" else -1.0
        inv_hand = q_inv(hand_world)
        # VRM の T ポーズの親指: 指先方向と前方向の間 (45°)、掌の面の中
        rest = norm(np.array([sign, 0.0, 1.0]))
        parent = IDENT.copy()  # 親の節までの回転 (手の基準姿勢の空間)
        lim = math.radians(95)
        for j, bname in enumerate(FINGER_BONES["Thumb"]):
            a, b = FINGERS["Thumb"][j], FINGERS["Thumb"][j + 1]
            d = q_rot(inv_hand, p[b] - p[a])
            if float(np.linalg.norm(d)) < 1e-6:
                return
            d = q_rot(q_inv(parent), norm(d))  # 親の節から見た向き
            q = q_from_to(rest, d)
            ang = 2.0 * math.acos(min(1.0, abs(float(q[3]))))
            if ang > lim:
                q = q_scale(q, lim / ang)
            res.bones[f"{side}{bname}"] = q
            parent = q_mul(parent, q)

    # ------------------------------------------------------------------ 見失ったとき
    def _handle_lost(self, res: SolveResult, t: float, dt: float) -> set:
        """腕・手・脚が今フレームで取れなかったら、少し待ってから自然な姿勢へ戻す。"""
        cfg = self.cfg
        groups = []
        if cfg.use_body:
            groups += [(f"{s}Arm", [f"{s}{b}" for b in ARM_BONES]) for s in ("left", "right")]
        if cfg.use_hands:
            groups += [(f"{s}Hand", [f"{s}{b}" for b in HAND_BONES]) for s in ("left", "right")]
        if cfg.use_legs:
            groups += [(f"{s}{b}", [f"{s}{b}"]) for s in ("left", "right") for b in LEG_BONES]
        held = set()
        for gname, bones in groups:
            # 肩は腕が見えていなくても毎フレーム出すので、見えているかの判定には使わない
            if any(b in res.bones for b in bones if not b.endswith("Shoulder")):
                self._seen[gname] = t
                continue
            if gname not in self._seen:
                continue  # 一度も見ていない部位は送らない (アニメーションに任せる)
            lost_for = t - self._seen[gname]
            k = 0.0
            if cfg.arms_rest and lost_for > cfg.lost_hold:
                ease = _ramp(lost_for - cfg.lost_hold, 0.0, min(0.25, max(0.05, cfg.lost_return) * 0.5))
                k = ease * (1.0 - math.exp(-dt * 3.0 / max(0.05, cfg.lost_return)))
            for b in bones:
                if b in res.bones:
                    continue  # 今フレームで求まっている (肩)
                last = self._last_out.get(b)
                if last is None:
                    continue
                q = q_slerp(last, rest_pose(b), k) if k > 0 else last
                res.bones[b] = q
                held.add(b)
        return held

    # ------------------------------------------------------------------ 平滑化
    def _smooth(self, res: SolveResult, dt: float, held: set) -> SolveResult:
        s = max(0.0, min(0.95, self.cfg.smooth))
        if s <= 0.0:
            for k, q in res.bones.items():
                qv = np.asarray(q, dtype=float)
                if np.all(np.isfinite(qv)):
                    self._bone_f.setdefault(k, _Euro()).reset_quat(qv)
            self._last_out.update(res.bones)
            return res
        mc = 0.5 * 10 ** (1.3 * (1.0 - s))          # 止まっているときの遮断周波数 (Hz)
        beta = 0.1 + 2.4 * _clamp01(self.cfg.responsiveness)
        stab_base = math.radians(2.0 * max(0.0, self.cfg.stabilize))
        out = {}
        for k, q in res.bones.items():
            f = self._bone_f.setdefault(k, _Euro())
            if k in held:
                f.reset_quat(np.asarray(q, dtype=float))
            else:
                eye_mul = 1.5 if "Eye" in k else 1.0
                stab_thr = stab_base * (0.5 if "Eye" in k else 1.0)
                q = f.quat(np.asarray(q, dtype=float), dt, mc * eye_mul, beta, stab=stab_thr)
            out[k] = q
        res.bones = out
        self._last_out.update(out)
        b_out = {}
        for k, v in res.blends.items():
            f = self._blend_f.setdefault(k, _Euro())
            # まばたきは速さが命なので弱めに
            m = mc * (6.0 if k in _BLINK_KEYS else 2.5)
            b_out[k] = float(np.clip(f.value(v, dt, m, beta * 2.0), 0.0, 1.0))
        res.blends = b_out
        if res.hips_pos is not None:
            res.hips_pos = self._hips_f.value(res.hips_pos, dt, mc, beta * 2.0)
        return res

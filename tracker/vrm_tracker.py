"""うつしみらー (UtsushiMirror) Webカメラトラッカー

Webカメラから顔・手・全身を MediaPipe で推定し、VMC Protocol で うつしみらー
(既定 127.0.0.1:39539) へ送る。

プライバシー: カメラ画像は推論にだけ使い、どこにも表示・保存・送信しない。
プレビューは黒い画面にランドマークのワイヤーだけを描いた別ウィンドウ。
制御ポートの状態返信も fps・検出の有無・明るさ (平均値) などの数値だけ。

対応: Windows / Linux (V4L2) / macOS。Android 版は同じ VMC 出力を使う別実装
(docs/TRACKING_XR.md 参照)。

使い方:
    python vrm_tracker.py                     # 既定: カメラ自動, 顔と手 (上半身), 鏡モード
    python vrm_tracker.py --mode face         # 顔だけ (軽い)
    python vrm_tracker.py --mode full         # 全身 (脚・立ち位置も)
    python vrm_tracker.py --camera 1 --port 39539
    python vrm_tracker.py --list-cameras

動作中の調整: 制御ポート (既定 39540, UDP で JSON) で設定変更・キャリブレーション・状態取得ができる。
    {"cmd": "set", "params": {"smooth": 0.6, "blink_link": true}}
    {"cmd": "calibrate", "delay": 3}   → 3 秒後から約 1 秒間、正面・無表情・腕を下ろした姿勢を基準として記録
    {"cmd": "reset_calibration"}
    {"cmd": "status"}                   → 送り主へ JSON で返信
    {"cmd": "wire_start", "path": "C:/.../rec_wire.mp4", "fps": 60}
                                        → ワイヤー表示 (文字なし・黒地) を、その fps の動画に書き出し始める
                                          (うつしみらーの録画に合わせる。カメラの映像は入らない)
    {"cmd": "wire_stop"}                → 書き出しを終えて動画を閉じる
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
import platform
import shutil
import socket
import sys
import tempfile
import threading
import time
import urllib.request
from pathlib import Path

import cv2
import numpy as np
import mediapipe as mp

sys.path.insert(0, str(Path(__file__).resolve().parent))
from vrmtrack.solver import Calibration, Solver, SolverConfig  # noqa: E402
from vrmtrack.vmc import VmcSender  # noqa: E402

MODEL_DIR = Path(__file__).resolve().parent / "models"
_MP = "https://storage.googleapis.com/mediapipe-models"
MODELS = {
    "face": ("face_landmarker.task", f"{_MP}/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"),
    "hand": ("hand_landmarker.task", f"{_MP}/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"),
    "pose_lite": ("pose_landmarker_lite.task",
                  f"{_MP}/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"),
    "pose_full": ("pose_landmarker_full.task",
                  f"{_MP}/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task"),
    "pose_heavy": ("pose_landmarker_heavy.task",
                   f"{_MP}/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task"),
}
MODES = {
    # モード: (顔, 手, 体, 脚, 立ち位置)
    "face": (True, False, False, False, False),
    "upper": (True, True, True, False, False),
    "full": (True, True, True, True, True),
}
LOCKED_KEYS = ("use_face", "use_hands", "use_body", "use_legs")  # モードで決まるので set では変えない

WIN_TITLE = "UtsushiMirror Tracking (wireframe)"
RED = (35, 28, 200)       # BGR: #c81c23 付近
RED_HI = (74, 64, 226)
WHITE = (236, 233, 232)
GREY = (110, 104, 98)
DARK = (22, 18, 15)


def log(msg: str) -> None:
    print(msg, flush=True)


def ensure_model(key: str) -> str:
    fname, url = MODELS[key]
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    path = MODEL_DIR / fname
    if not path.exists():
        log(f"[tracker] モデルをダウンロード中: {fname}")
        tmp = path.with_suffix(".part")
        try:
            with urllib.request.urlopen(url, timeout=60) as resp, open(tmp, "wb") as out_f:
                shutil.copyfileobj(resp, out_f)
            tmp.replace(path)
        except Exception:
            try:
                tmp.unlink(missing_ok=True)
            except OSError:
                pass
            raise
    return str(path)


def open_camera(index: int, width: int, height: int, fps: int = 30):
    sysname = platform.system()
    if sysname == "Windows":
        cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)
    elif sysname == "Linux":
        cap = cv2.VideoCapture(index, cv2.CAP_V4L2)
    else:
        cap = cv2.VideoCapture(index)
    if not cap.isOpened():
        cap = cv2.VideoCapture(index)
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
    cap.set(cv2.CAP_PROP_FPS, fps)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    return cap


VIRTUAL_HINTS = ("virtual", "warudo", "obs", "capture", "vcam", "spout", "ndi", "droidcam obs")


def list_cameras(max_n: int = 8) -> list[dict]:
    """[{index, name}] を返す。名前が取れない環境では番号だけ。"""
    try:
        from cv2_enumerate_cameras import enumerate_cameras
        backend = cv2.CAP_DSHOW if platform.system() == "Windows" else cv2.CAP_ANY
        cams = [{"index": c.index, "name": c.name} for c in enumerate_cameras(backend)]
        if cams:
            return cams
    except Exception:
        pass
    found = []
    for i in range(max_n):
        cap = open_camera(i, 640, 480)
        ok = cap.isOpened() and cap.read()[0]
        cap.release()
        if ok:
            found.append({"index": i, "name": f"Camera {i}"})
    return found


def _frame_alive(cap) -> bool:
    ok, f = False, None
    for _ in range(4):
        ok, f = cap.read()
    return bool(ok) and f is not None and float(f[::16, ::16].mean()) > 3.0


def pick_camera(spec: str, width: int, height: int, fps: int = 30):
    """spec が数字ならその番号、"auto" なら仮想カメラ等を避けて映るものを選ぶ。"""
    if spec != "auto":
        return int(spec), open_camera(int(spec), width, height, fps)
    cams = list_cameras()
    order = sorted(cams, key=lambda c: any(h in c["name"].lower() for h in VIRTUAL_HINTS))
    for c in order:
        cap = open_camera(c["index"], width, height, fps)
        if cap.isOpened() and _frame_alive(cap):
            log(f"[tracker] auto: {c['index']} {c['name']}")
            return c["index"], cap
        cap.release()
    return 0, open_camera(0, width, height, fps)


class Grabber(threading.Thread):
    """カメラを別スレッドで読み続け、常に最新の 1 枚だけを渡す (溜まったフレームによる遅延を防ぐ)。"""

    def __init__(self, cap) -> None:
        super().__init__(daemon=True)
        self.cap = cap
        self.frame = None
        self.seq = 0
        self.cam_fps = 0.0
        self.cond = threading.Condition()
        self.running = True

    def run(self) -> None:
        n, t = 0, time.perf_counter()
        while self.running:
            ok, f = self.cap.read()
            if not ok:
                time.sleep(0.01)
                continue
            with self.cond:
                self.frame = f
                self.seq += 1
                self.cond.notify_all()
            n += 1
            if n >= 30:
                now = time.perf_counter()
                self.cam_fps = n / max(1e-6, now - t)
                n, t = 0, now

    def wait_latest(self, last_seq: int, timeout: float = 0.05):
        with self.cond:
            if self.seq == last_seq and self.running:
                self.cond.wait(timeout=timeout)
            if self.seq == last_seq or self.frame is None:
                return None, last_seq
            return self.frame, self.seq

    def stop(self) -> None:
        with self.cond:
            self.running = False
            self.frame = None
            self.cond.notify_all()


class Control:
    """制御ポート (UDP, JSON)。設定の即時変更・キャリブレーション・状態取得。"""

    def __init__(self, port: int) -> None:
        self.sock = None
        if port <= 0:
            return
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.bind(("127.0.0.1", port))
            self.sock.setblocking(False)
        except OSError as e:
            log(f"[tracker] 制御ポート {port} を開けません: {e}")
            self.sock = None

    def poll(self) -> list:
        out = []
        while self.sock is not None:
            try:
                data, addr = self.sock.recvfrom(65536)
            except OSError:  # BlockingIOError / ConnectionResetError を含む
                break
            try:
                msg = json.loads(data.decode("utf-8"))
                if isinstance(msg, dict):
                    out.append((msg, addr))
            except ValueError:
                pass
        return out

    def reply(self, addr, obj: dict) -> None:
        if self.sock is not None:
            try:
                self.sock.sendto(json.dumps(obj, ensure_ascii=False).encode("utf-8"), addr)
            except OSError:
                pass

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None


def load_json(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save_json(path: str, d: dict) -> None:
    try:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, indent=1)
        os.replace(tmp, path)
    except OSError as e:
        log(f"[tracker] 保存できません: {path}: {e}")


# ---------------------------------------------------------------------------
# ワイヤー描画 (カメラ画像は使わない。黒いキャンバスに点と線だけ)
# ---------------------------------------------------------------------------
class WireView:
    def __init__(self, aspect: float, mirror: bool, width: int = 640, window: bool = True) -> None:
        self.w = width
        self.h = int(width / aspect) // 2 * 2
        self.k = width / 640  # 線の太さの倍率
        self.mirror = mirror
        V = mp.tasks.vision
        self.pose_conn = [(c.start, c.end) for c in V.PoseLandmarksConnections.POSE_LANDMARKS]
        self.body_conn = [c for c in self.pose_conn if c[0] > 10 and c[1] > 10]
        self.hand_conn = [(c.start, c.end) for c in V.HandLandmarksConnections.HAND_CONNECTIONS]
        F = V.FaceLandmarksConnections
        self.face_conn = [(c.start, c.end) for c in F.FACE_LANDMARKS_CONTOURS]
        self.iris_conn = [(c.start, c.end) for c in (F.FACE_LANDMARKS_LEFT_IRIS + F.FACE_LANDMARKS_RIGHT_IRIS)]
        if not window:
            self._bg = np.zeros((self.h, self.w, 3), dtype=np.uint8)
            return
        self._bg = np.full((self.h, self.w, 3), DARK, dtype=np.uint8)
        for x in range(0, self.w, 40):
            cv2.line(self._bg, (x, 0), (x, self.h), (30, 26, 23), 1)
        for y in range(0, self.h, 40):
            cv2.line(self._bg, (0, y), (self.w, y), (30, 26, 23), 1)
        cv2.namedWindow(WIN_TITLE, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(WIN_TITLE, self.w, self.h)

    def _pt(self, lm) -> tuple[int, int]:
        x = 1.0 - lm.x if self.mirror else lm.x
        return int(x * self.w), int(lm.y * self.h)

    def _lines(self, img, lms, conn, color, th) -> None:
        for a, b in conn:
            if a < len(lms) and b < len(lms):
                cv2.line(img, self._pt(lms[a]), self._pt(lms[b]), color, max(1, round(th * self.k)), cv2.LINE_AA)

    def paint(self, pose, hands, face):
        """点と線だけの絵 (文字なし)"""
        img = self._bg.copy()
        if face is not None:
            self._lines(img, face, self.face_conn, GREY, 1)
            self._lines(img, face, self.iris_conn, RED_HI, 1)
        if pose is not None:
            self._lines(img, pose, self.body_conn, RED, 3)
            for i, lm in enumerate(pose):
                if i > 10 and (getattr(lm, "visibility", 1.0) or 0) > 0.5:
                    cv2.circle(img, self._pt(lm), round(4 * self.k), WHITE, -1, cv2.LINE_AA)
        for lms in hands:
            self._lines(img, lms, self.hand_conn, WHITE, 2)
            for lm in lms:
                cv2.circle(img, self._pt(lm), round(3 * self.k), RED_HI, -1, cv2.LINE_AA)
        return img

    def draw(self, pose, hands, face, fps: float, status: str, overlay: str = "") -> bool:
        img = self.paint(pose, hands, face)
        if overlay:
            # キャリブレーション中: 顔を置く目安の枠と案内
            cx, cy = self.w // 2, int(self.h * 0.38)
            cv2.ellipse(img, (cx, cy), (int(self.w * 0.11), int(self.h * 0.2)), 0, 0, 360, RED_HI, 2, cv2.LINE_AA)
            (tw, _th), _ = cv2.getTextSize(overlay, cv2.FONT_HERSHEY_SIMPLEX, 0.7, 2)
            cv2.rectangle(img, (cx - tw // 2 - 12, self.h - 84), (cx + tw // 2 + 12, self.h - 50), (14, 12, 10), -1)
            cv2.putText(img, overlay, (cx - tw // 2, self.h - 60), cv2.FONT_HERSHEY_SIMPLEX, 0.7, WHITE, 2, cv2.LINE_AA)
        # HUD
        cv2.rectangle(img, (0, 0), (self.w, 26), (14, 12, 10), -1)
        cv2.rectangle(img, (0, 0), (4, 26), RED, -1)
        cv2.putText(img, f"UtsushiMirror Tracking  {fps:5.1f} fps  {status}", (12, 18),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.48, WHITE, 1, cv2.LINE_AA)
        cv2.putText(img, "camera image is never displayed  |  ESC: stop", (12, self.h - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, GREY, 1, cv2.LINE_AA)
        cv2.imshow(WIN_TITLE, img)
        key = cv2.waitKey(1) & 0xFF
        if key == 27:
            return False
        try:
            if cv2.getWindowProperty(WIN_TITLE, cv2.WND_PROP_VISIBLE) < 1:
                return False
        except cv2.error:
            return False
        return True


class WireDump(WireView):
    """ワイヤー表示 (文字なし・黒地・1280 幅) を動画に書き出す。カメラの映像は入らない。

    fps を渡すと、書き始めてからの実際の時間に合わせてコマを足し引きし、その fps の動画にする
    (うつしみらーの録画と同じ長さになる)。fps=None のときはカメラのコマのまま書き、各コマの時刻
    (time.time()) を同じ名前の .txt に 1 行ずつ残す (環境変数 VRMTRACK_WIRE_OUT。宣伝動画などの素材用)。"""

    def __init__(self, path: str, aspect: float, mirror: bool, fps: float | None = None) -> None:
        super().__init__(aspect, mirror, width=1280, window=False)
        self.path = os.path.abspath(path)
        self.fps = fps
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        # OpenCV は Windows で英数字以外を含むパスに書けないので、そのときは英数字だけの場所に書いてから移す
        self.work = self.path
        if not self.path.isascii():
            work_dir = next((d for d in (os.path.dirname(self.path), tempfile.gettempdir(), os.getcwd(),
                                         os.path.dirname(os.path.abspath(__file__))) if d.isascii()), None)
            if work_dir is None:
                raise OSError("書き出し先に使える英数字だけのフォルダがありません")
            self.work = os.path.join(work_dir, f"utsushi_wire_{os.getpid()}_{int(time.time() * 1000)}.mp4")
        self.writer = cv2.VideoWriter(self.work, cv2.VideoWriter_fourcc(*"mp4v"), fps or 30, (self.w, self.h))
        if not self.writer.isOpened():
            raise OSError(f"動画を書き出せません: {self.work}")
        self.times = open(os.path.splitext(self.path)[0] + ".txt", "w", encoding="utf-8") if fps is None else None
        self.t0 = time.time()
        self.n = 0
        self.last = None
        log(f"[tracker] wireframe dump → {self.path}")

    def write(self, pose, hands, face) -> None:
        img = self.paint(pose, hands, face)
        if self.fps is None:
            self.writer.write(img)
            self.times.write(f"{time.time():.4f}\n")
            self.times.flush()
            return
        self._fill(img)
        self.last = img

    def _fill(self, img) -> None:
        due = int((time.time() - self.t0) * self.fps) + 1
        while self.n < due:
            self.writer.write(img)
            self.n += 1

    def close(self) -> None:
        if self.fps is not None:
            self._fill(self.last if self.last is not None else np.zeros((self.h, self.w, 3), np.uint8))
        self.writer.release()
        if self.times is not None:
            self.times.close()
        if self.work != self.path:
            try:
                shutil.move(self.work, self.path)
            except OSError as e:
                log(f"[tracker] ワイヤー表示の動画を移せません ({self.work} に残しました): {e}")
        log(f"[tracker] wireframe saved: {self.path}")


# ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description="うつしみらー Webカメラトラッカー (VMC 送信)")
    ap.add_argument("--camera", default="auto", help="番号 または auto")
    ap.add_argument("--width", type=int, default=1280)
    ap.add_argument("--height", type=int, default=720)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=39539)
    ap.add_argument("--control-port", type=int, default=39540, help="制御用 UDP ポート (0 で無効)")
    ap.add_argument("--mode", choices=["face", "upper", "full", "custom"], default="upper",
                    help="face=顔だけ, upper=顔と手 (上半身), full=全身, custom=--no-* で個別指定")
    ap.add_argument("--no-face", action="store_true")
    ap.add_argument("--no-hands", action="store_true")
    ap.add_argument("--no-pose", action="store_true")
    ap.add_argument("--legs", action="store_true", help="脚と立ち位置も動かす (custom のとき)")
    ap.add_argument("--pose-model", choices=["lite", "full", "heavy"], default="full",
                    help="体の推定モデル (lite=軽い, heavy=高精度だが重い)")
    ap.add_argument("--detect-confidence", type=float, default=0.5, help="検出の確からしさのしきい値")
    ap.add_argument("--no-mirror", action="store_true")
    ap.add_argument("--smooth", type=float, default=None)
    ap.add_argument("--settings-file", default="", help="調整値 (SolverConfig のキー) の JSON")
    ap.add_argument("--calib-file", default="", help="キャリブレーション結果の保存先")
    ap.add_argument("--no-preview", action="store_true", help="ワイヤー表示ウィンドウを出さない")
    ap.add_argument("--list-cameras", action="store_true")
    ap.add_argument("--max-frames", type=int, default=0, help="テスト用: 指定フレームで終了")
    args = ap.parse_args()

    if args.list_cameras:
        print(json.dumps({"cameras": list_cameras()}))
        return 0

    if args.mode == "custom":
        use_face, use_hands, use_pose, use_legs = not args.no_face, not args.no_hands, not args.no_pose, args.legs
        hips = args.legs
    else:
        use_face, use_hands, use_pose, use_legs, hips = MODES[args.mode]
    if use_hands or use_legs:
        use_pose = True  # 手を腕につなぐ・脚を動かすのに体の推定が要る

    cfg = SolverConfig()
    if args.settings_file:
        cfg.update({k: v for k, v in load_json(args.settings_file).items() if k not in LOCKED_KEYS})
    if args.smooth is not None:
        cfg.smooth = args.smooth
    cfg.mirror = not args.no_mirror
    cfg.use_face, cfg.use_hands, cfg.use_body, cfg.use_legs = use_face, use_hands, use_pose, use_legs
    cfg.hips_move = hips and cfg.hips_move
    calib = Calibration.from_dict(load_json(args.calib_file)) if args.calib_file else Calibration()

    V = mp.tasks.vision
    Base = mp.tasks.BaseOptions
    RM = V.RunningMode.VIDEO
    conf = max(0.1, min(0.95, args.detect_confidence))
    face_lm = hand_lm = pose_lm = None
    if use_face:
        face_lm = V.FaceLandmarker.create_from_options(V.FaceLandmarkerOptions(
            base_options=Base(model_asset_path=ensure_model("face")), running_mode=RM, num_faces=1,
            min_face_detection_confidence=conf, min_face_presence_confidence=conf, min_tracking_confidence=conf,
            output_face_blendshapes=True, output_facial_transformation_matrixes=True))
    if use_hands:
        hand_lm = V.HandLandmarker.create_from_options(V.HandLandmarkerOptions(
            base_options=Base(model_asset_path=ensure_model("hand")), running_mode=RM, num_hands=2,
            min_hand_detection_confidence=conf, min_hand_presence_confidence=conf, min_tracking_confidence=conf))
    if use_pose:
        pose_lm = V.PoseLandmarker.create_from_options(V.PoseLandmarkerOptions(
            base_options=Base(model_asset_path=ensure_model("pose_" + args.pose_model)), running_mode=RM,
            num_poses=1, min_pose_detection_confidence=conf, min_pose_presence_confidence=conf,
            min_tracking_confidence=conf))

    cam_index, cap = pick_camera(str(args.camera), args.width, args.height, args.fps)
    args.camera = cam_index
    if not cap.isOpened():
        log(f"[tracker] ERROR: カメラ {args.camera} を開けません")
        return 2
    fw = cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 16
    fh = cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 9
    log(f"[tracker] camera {args.camera} {int(fw)}x{int(fh)} mode={args.mode} → VMC {args.host}:{args.port}")

    solver = Solver(cfg, calib)
    sender = VmcSender(args.host, args.port)
    control = Control(args.control_port)
    view = None if args.no_preview else WireView(fw / fh, cfg.mirror)
    dump = None  # 環境変数で常に書き出す分 (素材用)
    if os.environ.get("VRMTRACK_WIRE_OUT"):
        dump = WireDump(os.path.join(os.environ["VRMTRACK_WIRE_OUT"], time.strftime("wire_%Y%m%d_%H%M%S.mp4")), fw / fh, cfg.mirror)
    rec_dump = None  # うつしみらーの録画に合わせて書き出す分 (wire_start / wire_stop)
    grab = Grabber(cap)
    grab.start()

    n_models = sum(1 for m in (pose_lm, face_lm, hand_lm) if m is not None)
    executor = ThreadPoolExecutor(max_workers=n_models) if n_models > 1 else None

    t0 = time.perf_counter()
    last_ts = -1
    last_seq = 0
    fps = 0.0
    frames = 0
    t_fps = time.perf_counter()
    brightness = 0.0
    det = {"face": False, "hands": 0, "pose": False}
    calib_at = 0.0      # キャリブレーションの記録開始時刻 (0 = 予定なし)
    capture_sec = 1.2
    last_msg = ""
    try:
        while True:
            # ---- 制御コマンド
            for msg, addr in control.poll():
                cmd = msg.get("cmd")
                if cmd == "set":
                    cfg.update({k: v for k, v in (msg.get("params") or {}).items() if k not in LOCKED_KEYS})
                    if view is not None:
                        view.mirror = cfg.mirror
                    for d in (dump, rec_dump):
                        if d is not None:
                            d.mirror = cfg.mirror
                elif cmd == "wire_start":
                    if rec_dump is not None:
                        rec_dump.close()
                        rec_dump = None
                    try:
                        rec_dump = WireDump(str(msg.get("path", "")), fw / fh, cfg.mirror, float(msg.get("fps", 30) or 30))
                        last_msg = ""
                    except (OSError, ValueError, TypeError) as e:
                        log(f"[tracker] ワイヤー表示を書き出せません: {e}")
                        last_msg = "wire error"
                elif cmd == "wire_stop":
                    if rec_dump is not None:
                        rec_dump.close()
                        rec_dump = None
                elif cmd == "calibrate":
                    try:
                        delay = max(0.0, float(msg.get("delay", 3.0)))
                    except (ValueError, TypeError):
                        delay = 3.0
                    calib_at = time.perf_counter() + delay
                    last_msg = "calibrating"
                elif cmd == "reset_calibration":
                    solver.clear_calibration()
                    calib_at = 0.0
                    if args.calib_file and os.path.exists(args.calib_file):
                        try:
                            os.remove(args.calib_file)
                        except OSError:
                            pass
                    last_msg = "calibration cleared"
                elif cmd == "stop":
                    raise KeyboardInterrupt
                now = time.perf_counter()
                control.reply(addr, {
                    "fps": round(fps, 1), "camera_fps": round(grab.cam_fps, 1),
                    "camera": args.camera, "resolution": [int(fw), int(fh)], "mode": args.mode,
                    "face": det["face"], "hands": det["hands"], "pose": det["pose"],
                    "brightness": round(brightness, 1),
                    "calibrated": solver.calib.done, "calibrated_at": solver.calib.time,
                    "calib_countdown": round(max(0.0, calib_at - now), 1) if calib_at else -1,
                    "calib_capturing": solver.capturing, "message": last_msg,
                })

            frame, seq = grab.wait_latest(last_seq, timeout=0.05)
            if frame is None:
                continue
            last_seq = seq
            ts = int((time.perf_counter() - t0) * 1000)
            if ts <= last_ts:
                ts = last_ts + 1
            last_ts = ts
            if frames % 15 == 0:
                brightness = float(cv2.cvtColor(frame[::16, ::16], cv2.COLOR_BGR2GRAY).mean())
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            solver.aspect = frame.shape[1] / max(1, frame.shape[0])  # 画像の横/縦 (腕の推定で縦横の長さをそろえる)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            # 以降 frame / rgb / image は推論にのみ使う (表示しない)

            pose_w = pose_i = face_pts = None
            face_in = None
            hands_in, hands_draw = [], []
            if executor is not None:
                f_pose = executor.submit(pose_lm.detect_for_video, image, ts) if pose_lm is not None else None
                f_face = executor.submit(face_lm.detect_for_video, image, ts) if face_lm is not None else None
                f_hand = executor.submit(hand_lm.detect_for_video, image, ts) if hand_lm is not None else None
                r_pose = f_pose.result() if f_pose is not None else None
                r_face = f_face.result() if f_face is not None else None
                r_hand = f_hand.result() if f_hand is not None else None
            else:
                r_pose = pose_lm.detect_for_video(image, ts) if pose_lm is not None else None
                r_face = face_lm.detect_for_video(image, ts) if face_lm is not None else None
                r_hand = hand_lm.detect_for_video(image, ts) if hand_lm is not None else None

            if r_pose is not None and r_pose.pose_landmarks:
                pose_i = r_pose.pose_landmarks[0]
                pose_w = r_pose.pose_world_landmarks[0]
            if r_face is not None and r_face.face_landmarks:
                face_pts = r_face.face_landmarks[0]
                bs = {c.category_name: c.score for c in (r_face.face_blendshapes[0] if r_face.face_blendshapes else [])}
                mat = r_face.facial_transformation_matrixes[0] if r_face.facial_transformation_matrixes else None
                face_in = {"matrix": mat, "blendshapes": bs}
            if r_hand is not None:
                for i, lms in enumerate(r_hand.hand_landmarks or []):
                    hands_draw.append(lms)
                    hl = None
                    if getattr(r_hand, "handedness", None) and i < len(r_hand.handedness) and r_hand.handedness[i]:
                        cat = r_hand.handedness[i][0]
                        hl = (str(getattr(cat, "category_name", "")), float(getattr(cat, "score", 0.0)))
                    hands_in.append((lms, r_hand.hand_world_landmarks[i], hl))
            del frame, rgb, image
            det = {"face": face_in is not None, "hands": len(hands_in), "pose": pose_w is not None}

            # ---- キャリブレーション (カウントダウン → 一定時間の平均)
            overlay = ""
            now = time.perf_counter()
            if calib_at:
                if now < calib_at:
                    overlay = f"Face the screen, neutral face, arms down  {int(calib_at - now) + 1}"
                elif not solver.capturing:
                    solver.start_capture()
                if solver.capturing:
                    overlay = "Hold still ..."
                    if now >= calib_at + capture_sec:
                        c = solver.finish_capture()
                        calib_at = 0.0
                        if c.done:
                            last_msg = "calibrated"
                            if args.calib_file:
                                save_json(args.calib_file, c.to_dict())
                        else:
                            last_msg = "calibration failed: face/body not found"
                        log(f"[tracker] {last_msg}")

            res = solver.solve(pose_world=pose_w, pose_image=pose_i, hands=hands_in, face=face_in, t=now)
            if res.bones or res.blends:
                sender.send(res.bones, res.blends, res.hips_pos)

            frames += 1
            if frames % 15 == 0:
                fps = 15.0 / max(1e-6, time.perf_counter() - t_fps)
                t_fps = time.perf_counter()
            status = " ".join(s for s, on in (("FACE", face_in), ("POSE", pose_w), ("HANDS", hands_in)) if on)
            if solver.calib.done:
                status += "  [calibrated]"
            for d in (dump, rec_dump):
                if d is not None:
                    d.write(pose_i, hands_draw, face_pts)
            if view is not None and not view.draw(pose_i, hands_draw, face_pts, fps, status or "searching...", overlay):
                break
            if frames % 90 == 0:
                log(f"[tracker] {fps:.1f} fps  {status}")
            if args.max_frames and frames >= args.max_frames:
                break
    except KeyboardInterrupt:
        pass
    finally:
        grab.stop()
        grab.join(timeout=1.0)
        for d in (dump, rec_dump):
            if d is not None:
                d.close()
        if executor is not None:
            executor.shutdown(wait=True)
        for lm in (face_lm, hand_lm, pose_lm):
            if lm is not None:
                try:
                    lm.close()
                except Exception:
                    pass
        cap.release()
        sender.close()
        control.close()
        cv2.destroyAllWindows()
    log("[tracker] stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())

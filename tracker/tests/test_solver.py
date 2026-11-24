"""合成ランドマークで Solver の向き・符号を確かめる (カメラ不要)。"""
import math
import sys
from pathlib import Path
from types import SimpleNamespace as L

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from vrmtrack.mathq import q_rot  # noqa: E402
from vrmtrack.solver import Solver, SolverConfig  # noqa: E402


def body(arm_down: bool):
    # MediaPipe ワールド座標: x = 画像右 (本人の左), y = 下, z = 奥
    pts = [L(x=0, y=0, z=0, visibility=1.0) for _ in range(33)]
    def s(i, x, y, z=0.0): pts[i] = L(x=x, y=y, z=z, visibility=1.0)
    s(11, 0.2, -0.5); s(12, -0.2, -0.5)       # 肩 (本人の左が +x)
    s(23, 0.1, 0.0); s(24, -0.1, 0.0)         # 腰
    if arm_down:
        s(13, 0.2, -0.2); s(15, 0.2, 0.05)    # 左腕を下ろす
    else:
        s(13, 0.5, -0.5); s(15, 0.8, -0.5)    # 左腕を水平
    s(14, -0.5, -0.5); s(16, -0.5, -0.8, -0.0)  # 右腕: 肘から先を上へ
    return pts


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    return cond


ok = True
sv = Solver(SolverConfig(mirror=False, smooth=0.0))
r = sv.solve(pose_world=body(False))
d = q_rot(r.bones["leftUpperArm"], np.array([1.0, 0, 0]))
ok &= check("T字の左上腕は+Xのまま", d[0] > 0.99)
r = sv.solve(pose_world=body(True))
d = q_rot(r.bones["leftUpperArm"], np.array([1.0, 0, 0]))
ok &= check("下ろした左上腕は-Yを向く", d[1] < -0.95)
dl = q_rot(r.bones["rightLowerArm"], np.array([-1.0, 0, 0]))
ok &= check("右前腕は上 (+Y) へ曲がる", dl[1] > 0.95)
ok &= check("胴体はほぼ回転なし", abs(r.bones["spine"][3]) > 0.99)

# 鏡モード: 本人の左腕を下ろす → モデルの右腕が下がる
sv = Solver(SolverConfig(mirror=True, smooth=0.0))
r = sv.solve(pose_world=body(True))
d = q_rot(r.bones["rightUpperArm"], np.array([-1.0, 0, 0]))
ok &= check("鏡モードで左右が入れ替わる", d[1] < -0.95)

# 顔: 本人が自分の左へ向く (カメラから見て画像右 = +X 方向へ鼻が向く)
ang = math.radians(30)
m = np.eye(4)
m[:3, :3] = [[math.cos(ang), 0, math.sin(ang)], [0, 1, 0], [-math.sin(ang), 0, math.cos(ang)]]
sv = Solver(SolverConfig(mirror=False, smooth=0.0))
r = sv.solve(face={"matrix": m, "blendshapes": {"jawOpen": 0.7, "eyeBlinkLeft": 0.9}})
head = r.bones["head"]
from vrmtrack.mathq import q_mul
nose = q_rot(q_mul(r.bones["neck"], head), np.array([0, 0, 1.0]))
ok &= check("顔の向きが+X側へ回る", nose[0] > 0.4)
ok &= check("口が開くと aa", r.blends["aa"] > 0.5)
ok &= check("左目を閉じると blinkLeft", r.blends["blinkLeft"] > 0.8 and r.blends["blinkRight"] < 0.1)
sv = Solver(SolverConfig(mirror=True, smooth=0.0))
r = sv.solve(face={"matrix": m, "blendshapes": {"eyeBlinkLeft": 0.9}})
ok &= check("鏡モードで目の左右も入れ替わる", r.blends["blinkRight"] > 0.8)

# ---- キャリブレーション: カメラが上から見下ろす (頭が 20 度うつむいて見える) → 補正後は正面
from vrmtrack.solver import rest_pose  # noqa: E402
pitch = math.radians(20)
mp_ = np.eye(4)
mp_[:3, :3] = [[1, 0, 0], [0, math.cos(pitch), -math.sin(pitch)], [0, math.sin(pitch), math.cos(pitch)]]
neutral = {"eyeBlinkLeft": 0.35, "eyeBlinkRight": 0.35, "jawOpen": 0.1}
sv = Solver(SolverConfig(mirror=False, smooth=0.0))
sv.start_capture()
for i in range(10):
    sv.solve(face={"matrix": mp_, "blendshapes": neutral}, pose_world=body(True), t=i / 30)
cal = sv.finish_capture()
ok &= check("キャリブレーション結果が記録される", cal.done and cal.head is not None and cal.body is not None)
r = sv.solve(face={"matrix": mp_, "blendshapes": neutral}, pose_world=body(True), t=0.5)
nose = q_rot(q_mul(r.bones["neck"], r.bones["head"]), np.array([0, 0, 1.0]))
ok &= check("補正後は同じ姿勢で正面を向く", nose[2] > 0.99)
ok &= check("補正後は普段の目の細さで閉じない", r.blends["blinkLeft"] < 0.05 and r.blends["aa"] < 0.05)

# ---- 両目の連動
sv = Solver(SolverConfig(mirror=False, smooth=0.0, blink_link=True))
r = sv.solve(face={"matrix": m, "blendshapes": {"eyeBlinkLeft": 1.0, "eyeBlinkRight": 0.0}})
ok &= check("連動オンで両目が同じ値", abs(r.blends["blinkLeft"] - r.blends["blinkRight"]) < 1e-6)

# ---- 表情の自動付与オフ
sv = Solver(SolverConfig(mirror=False, smooth=0.0, expressions=False))
r = sv.solve(face={"matrix": m, "blendshapes": {"mouthSmileLeft": 1.0, "mouthSmileRight": 1.0}})
ok &= check("表情オフで happy は 0", r.blends["happy"] == 0.0)

# ---- 顔だけモード: 頭の回転の一部が背骨へ
sv = Solver(SolverConfig(mirror=False, smooth=0.0, use_body=False, use_hands=False, body_follow=0.5))
r = sv.solve(face={"matrix": m, "blendshapes": {}})
ok &= check("顔だけモードで上半身も少し回る", "spine" in r.bones and abs(r.bones["spine"][3]) < 0.9999)
full = q_mul(q_mul(r.bones["spine"], r.bones["chest"]), q_mul(r.bones["neck"], r.bones["head"]))
ok &= check("頭の最終的な向きは変わらない", q_rot(full, np.array([0, 0, 1.0]))[0] > 0.45)

# ---- 見失った腕は待ってから下ろす
sv = Solver(SolverConfig(mirror=False, smooth=0.0, lost_hold=0.3, lost_return=0.3))
sv.solve(pose_world=body(False), t=0.0)
r = sv.solve(pose_world=None, t=0.1)
d = q_rot(r.bones["leftUpperArm"], np.array([1.0, 0, 0]))
ok &= check("見失った直後は姿勢を保つ", d[0] > 0.99)
for i in range(30):
    r = sv.solve(pose_world=None, t=0.4 + i / 30)
d = q_rot(r.bones["leftUpperArm"], np.array([1.0, 0, 0]))
ok &= check("しばらくすると腕を下ろす", d[1] < -0.9)
ok &= check("下ろした姿勢は rest_pose", abs(abs(float(np.dot(r.bones["leftUpperArm"], rest_pose("leftUpperArm")))) - 1) < 1e-3)

# ---- 全身: 横へ移動すると腰が動く
def img_pose(cx):
    pts = [L(x=0.5, y=0.5, z=0, visibility=1.0) for _ in range(33)]
    for i, (x, y) in {11: (cx + 0.1, 0.4), 12: (cx - 0.1, 0.4), 23: (cx + 0.05, 0.7), 24: (cx - 0.05, 0.7)}.items():
        pts[i] = L(x=x, y=y, z=0, visibility=1.0)
    return pts
sv = Solver(SolverConfig(mirror=False, smooth=0.0, hips_move=True))
sv.solve(pose_world=body(True), pose_image=img_pose(0.5), t=0)
r = sv.solve(pose_world=body(True), pose_image=img_pose(0.6), t=0.03)
ok &= check("画面右へ動くと腰が +X へ", r.hips_pos is not None and r.hips_pos[0] > 0.1)

# ---- One Euro: 止まっているときの揺れを抑える
rng = np.random.default_rng(1)
def jitter_std(smooth):
    sv = Solver(SolverConfig(mirror=False, smooth=smooth))
    ys = []
    for i in range(90):
        a = math.radians(rng.normal(0, 2.0))
        mm = np.eye(4)
        mm[:3, :3] = [[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]]
        rr = sv.solve(face={"matrix": mm, "blendshapes": {}}, t=i / 30)
        ys.append(q_rot(q_mul(rr.bones["neck"], rr.bones["head"]), np.array([0, 0, 1.0]))[0])
    return float(np.std(ys[30:]))
ok &= check("なめらかさを上げると揺れが小さい", jitter_std(0.8) < jitter_std(0.0) * 0.5)

# ---- 目: 左右の同期と可動限界
look = {"eyeLookOutLeft": 1.0, "eyeLookInLeft": 0.0, "eyeLookInRight": 0.2, "eyeLookUpLeft": 1.0, "eyeLookUpRight": 1.0}
def eye_dir(r, side):
    return q_rot(r.bones[side + "Eye"], np.array([0, 0, 1.0]))
sv = Solver(SolverConfig(mirror=False, smooth=0.0, gaze_link=True, gaze_gain=2.0, gaze_limit_h=10.0, gaze_limit_up=5.0))
r = sv.solve(face={"matrix": m, "blendshapes": look})
ok &= check("同期オンで両目が同じ向き", np.allclose(r.bones["leftEye"], r.bones["rightEye"]))
d = eye_dir(r, "left")
ok &= check("左右の可動限界で止まる", abs(math.degrees(math.atan2(d[0], d[2])) - 10.0) < 0.5)
ok &= check("上の可動限界で止まる", abs(math.degrees(math.asin(d[1])) - 5.0) < 0.5)
sv = Solver(SolverConfig(mirror=False, smooth=0.0, gaze_link=False))
r = sv.solve(face={"matrix": m, "blendshapes": look})
ok &= check("同期オフで左右の目が別々に動く", not np.allclose(r.bones["leftEye"], r.bones["rightEye"]))
ok &= check("同期オフ: 外を見る左目の方が大きく動く", eye_dir(r, "left")[0] > eye_dir(r, "right")[0] > 0)

# ---- 表情: 目を閉じただけで笑顔にならない・笑顔のときはまばたきを減らす・感度と強さ
from vrmtrack.mathq import q_axis_angle  # noqa: E402
from vrmtrack.solver import SolveResult, _twist  # noqa: E402
def blends(cfg_kw, bs):
    sv = Solver(SolverConfig(mirror=False, smooth=0.0, use_body=False, use_hands=False, **cfg_kw))
    return sv.solve(face={"matrix": m, "blendshapes": bs}).blends
b = blends({}, {"eyeBlinkLeft": 0.9, "eyeBlinkRight": 0.9, "mouthSmileLeft": 0.4, "mouthSmileRight": 0.4,
                "eyeSquintLeft": 0.5, "eyeSquintRight": 0.5})
ok &= check("目を閉じただけでは笑顔にならない", b["happy"] < 0.05 and b["blinkLeft"] > 0.8)
b = blends({"happy_sens": 0.5, "happy_gain": 0.7}, {"mouthSmileLeft": 0.9, "mouthSmileRight": 0.9, "eyeBlinkLeft": 0.9, "eyeBlinkRight": 0.9})
ok &= check("笑顔のときはまばたきを減らす (目が崩れない)", b["happy"] > 0.4 and b["blinkLeft"] < 0.5)
mid = {"mouthSmileLeft": 0.5, "mouthSmileRight": 0.5}
ok &= check("笑顔の強さ 0 で笑顔が付かない", blends({"happy_gain": 0.0}, mid)["happy"] == 0.0)
ok &= check("笑顔の感度を上げると付きやすい", blends({"happy_sens": 0.9}, mid)["happy"] > blends({"happy_sens": 0.1}, mid)["happy"])
brow = {"browDownLeft": 0.6, "browDownRight": 0.6}
ok &= check("怒りの強さで最大値が変わる", blends({"angry_gain": 0.3}, brow)["angry"] < blends({"angry_gain": 1.0}, brow)["angry"])

# ---- 手首のひねりの多くは前腕へ回す
def flat_hand(rot):
    # 左手の基準姿勢: 指は +X、人差し指側が +Z。solver 空間の点を MediaPipe 座標 (x, -y, -z) に戻して渡す
    pts = {0: (0, 0, 0), 5: (0.9, 0, 0.2), 9: (1.0, 0, 0), 13: (0.9, 0, -0.1), 17: (0.9, 0, -0.2), 1: (0.2, 0, 0.3)}
    out = []
    for i in range(21):
        if i in pts:
            v = np.array(pts[i], dtype=float)
        else:
            base = {2: 1, 3: 1, 4: 1, 6: 5, 7: 5, 8: 5, 10: 9, 11: 9, 12: 9, 14: 13, 15: 13, 16: 13, 18: 17, 19: 17, 20: 17}[i]
            k = (i - base)
            v = np.array(pts[base], dtype=float) + np.array([0.15 * k, 0, 0])
        v = q_rot(rot, v)
        out.append(L(x=v[0], y=-v[1], z=-v[2]))
    return out
for share, name in ((0.7, "ひねりの 7 割が前腕へ"), (0.0, "割合 0 なら手首だけでひねる")):
    sv = Solver(SolverConfig(mirror=False, smooth=0.0, forearm_twist=share))
    res = SolveResult()
    res.bones["leftLowerArm"] = np.array([0, 0, 0, 1.0])
    res.bones["__leftLowerArmWorld"] = np.array([0, 0, 0, 1.0])
    sv._solve_one_hand("left", flat_hand(q_axis_angle([1, 0, 0], math.radians(80))), res)
    lo_ang = math.degrees(2 * math.acos(min(1.0, abs(res.bones["leftLowerArm"][3]))))
    hd_ang = math.degrees(2 * math.acos(min(1.0, abs(res.bones["leftHand"][3]))))
    ok &= check(name, abs(lo_ang - 80 * share) < 2.0 and abs(hd_ang - 80 * (1 - share)) < 2.0)
tw = _twist(q_mul(q_axis_angle([1, 0, 0], 0.6), q_axis_angle([0, 1, 0], 0.3)), np.array([1.0, 0, 0]))
ok &= check("ひねり成分は軸まわりだけ", abs(tw[1]) < 1e-9 and abs(tw[2]) < 1e-9 and tw[0] > 0.2)

# ---- 手の割り当て: 腕が取れていない側には付けない / 画面外の手首では腕を動かさない
def img_wrists(lw, rw):
    pts = img_pose(0.5)
    pts[15] = L(x=lw[0], y=lw[1], z=0, visibility=1.0)
    pts[16] = L(x=rw[0], y=rw[1], z=0, visibility=1.0)
    return pts
sv = Solver(SolverConfig(mirror=False, smooth=0.0))
res = SolveResult()
res.bones["__rightLowerArmWorld"] = np.array([0, 0, 0, 1.0])
hand_at_left = flat_hand(np.array([0, 0, 0, 1.0]))
hand_at_left[0] = L(x=0.62, y=0.5, z=0)
sv._solve_hands([(hand_at_left, flat_hand(np.array([0, 0, 0, 1.0])))], img_wrists((0.62, 0.5), (0.38, 0.5)), res)
ok &= check("腕が取れていない側の手は使わない", not any(k.startswith("left") for k in res.bones) and "rightHand" not in res.bones)
sv = Solver(SolverConfig(mirror=False, smooth=0.0))
r = sv.solve(pose_world=body(True), pose_image=img_wrists((0.6, 1.3), (0.4, 0.5)))
ok &= check("画面の外の手首では腕を動かさない", "leftUpperArm" not in r.bones and "rightUpperArm" in r.bones)

# ---- 小刻みな揺れの抑制
def small_jitter(stab):
    sv = Solver(SolverConfig(mirror=False, smooth=0.3, stabilize=stab))
    rg = np.random.default_rng(3)
    ys = []
    for i in range(120):
        a = math.radians(rg.normal(0, 0.4))
        mm = np.eye(4)
        mm[:3, :3] = [[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]]
        rr = sv.solve(face={"matrix": mm, "blendshapes": {}}, t=i / 30)
        ys.append(q_rot(q_mul(rr.bones["neck"], rr.bones["head"]), np.array([0, 0, 1.0]))[0])
    return float(np.std(np.diff(ys[30:])))
ok &= check("揺れの抑制で細かい揺れが減る", small_jitter(0.5) < small_jitter(0.0) * 0.5)
def big_turn(stab):
    sv = Solver(SolverConfig(mirror=False, smooth=0.3, stabilize=stab))
    for i in range(40):
        a = math.radians(30)
        mm = np.eye(4)
        mm[:3, :3] = [[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]]
        rr = sv.solve(face={"matrix": mm, "blendshapes": {}}, t=i / 30)
    return q_rot(q_mul(rr.bones["neck"], rr.bones["head"]), np.array([0, 0, 1.0]))[0]
ok &= check("大きな動きは抑制されずに届く", abs(big_turn(0.5) - big_turn(0.0)) < 0.02)

# ---- 親指: 3D の向きから求める (開いた親指はほぼそのまま、曲げると大きく回る)
from vrmtrack.mathq import norm  # noqa: E402
def thumb_hand(tdir):
    tdir = norm(np.array(tdir, dtype=float))
    pts = {0: (0, 0, 0), 5: (0.9, 0, 0.2), 9: (1.0, 0, 0), 13: (0.9, 0, -0.1), 17: (0.9, 0, -0.2), 1: (0.2, 0, 0.3)}
    out = []
    for i in range(21):
        if i in pts:
            v = np.array(pts[i], dtype=float)
        elif i in (2, 3, 4):
            v = np.array(pts[1], dtype=float) + tdir * 0.25 * (i - 1)
        else:
            base = {6: 5, 7: 5, 8: 5, 10: 9, 11: 9, 12: 9, 14: 13, 15: 13, 16: 13, 18: 17, 19: 17, 20: 17}[i]
            v = np.array(pts[base], dtype=float) + np.array([0.15 * (i - base), 0, 0])
        out.append(L(x=v[0], y=-v[1], z=-v[2]))
    return out
def thumb_angles(tdir):
    sv = Solver(SolverConfig(mirror=False, smooth=0.0))
    res = SolveResult()
    sv._solve_one_hand("left", thumb_hand(tdir), res)
    return [math.degrees(2 * math.acos(min(1.0, abs(res.bones["leftThumb" + b][3])))) for b in ("Metacarpal", "Proximal", "Distal")], res
a_open, _ = thumb_angles((1, 0, 1))
ok &= check("開いた親指はほぼ回らない", max(a_open) < 3.0)
curl = (0.3, -0.5, -0.8)
a_curl, rr = thumb_angles(curl)
ok &= check("親指を掌の上へ曲げると大きく回る", sum(a_curl) > 60.0)
tip = q_rot(rr.bones["leftThumbMetacarpal"], norm(np.array([1.0, 0, 1.0])))
ok &= check("親指の向きが測った向きに合う", float(np.dot(tip, norm(np.array(curl)))) > 0.95)

# ---- 手は見えているのに腕が取れていない: 手の位置から腕を推定する
def body_no_left_arm():
    pts = body(True)
    for i in (13, 15):
        pts[i] = L(x=pts[i].x, y=pts[i].y, z=pts[i].z, visibility=0.05)
    return pts
def arm_tip(r, side="left"):
    sign = 1.0 if side == "left" else -1.0
    rest = np.array([sign, 0, 0])
    up = q_mul(q_mul(r.bones["chest"], r.bones["spine"]), q_mul(r.bones[side + "Shoulder"], r.bones[side + "UpperArm"]))
    lo = q_mul(up, r.bones[side + "LowerArm"])
    return q_rot(up, rest) * 0.28 + q_rot(lo, rest) * 0.26
img = img_pose(0.5)
for i in (15, 13):
    img[i] = L(x=img[i].x, y=img[i].y, z=0, visibility=0.05)
hand_img = [L(x=0.66, y=0.12, z=0) for _ in range(21)]
sv = Solver(SolverConfig(mirror=False, smooth=0.0))
r = sv.solve(pose_world=body_no_left_arm(), pose_image=img, hands=[(hand_img, flat_hand(np.array([0, 0, 0, 1.0])))])
ok &= check("手から腕を推定する", "leftUpperArm" in r.bones and "leftHand" in r.bones)
tip = arm_tip(r) if "leftUpperArm" in r.bones else np.zeros(3)
ok &= check("推定した腕は手の方 (右上) へ伸びる", tip[1] > 0.1 and tip[0] > 0.05)
sv = Solver(SolverConfig(mirror=False, smooth=0.0, arm_from_hand=False))
r = sv.solve(pose_world=body_no_left_arm(), pose_image=img, hands=[(hand_img, flat_hand(np.array([0, 0, 0, 1.0])))])
ok &= check("推定オフなら腕を付けない", "leftUpperArm" not in r.bones)

# ---- 肩の上げ下げ
def img_shrug(dl, dr):
    pts = img_pose(0.5)
    pts[7] = L(x=0.55, y=0.25, z=0, visibility=1.0)
    pts[8] = L(x=0.45, y=0.25, z=0, visibility=1.0)
    pts[11] = L(x=0.6, y=0.4 - dl, z=0, visibility=1.0)
    pts[12] = L(x=0.4, y=0.4 - dr, z=0, visibility=1.0)
    return pts
def shrug(gain, sens=0.5, dl=0.06):
    sv = Solver(SolverConfig(mirror=False, smooth=0.0, shoulder_gain=gain, shoulder_sens=sens))
    sv.solve(pose_world=body(True), pose_image=img_shrug(0, 0), t=0)
    return sv.solve(pose_world=body(True), pose_image=img_shrug(dl, 0), t=0.03)
r = shrug(1.0)
ok &= check("左肩をすくめると左肩が上がる", q_rot(r.bones["leftShoulder"], np.array([1.0, 0, 0]))[1] > 0.1)
ok &= check("右肩はそのまま", abs(r.bones["rightShoulder"][3]) > 0.999)
ok &= check("肩を上げても腕の向きは変わらない", arm_tip(r)[1] < -0.5)
ok &= check("強さ 0 なら肩は動かない", abs(shrug(0.0).bones["leftShoulder"][3]) > 0.9999)
ok &= check("感度を下げると小さな動きでは動かない", abs(shrug(1.0, 0.0, 0.015).bones["leftShoulder"][3]) > 0.9999
            and abs(shrug(1.0, 1.0, 0.015).bones["leftShoulder"][3]) < 0.9999)

# ---- 手が止まっているのに腕の検出がちらつく: 腕が跳ねない
def flicker_run(mode, frames=40):
    sv = Solver(SolverConfig(mirror=False, smooth=0.0, stabilize=0.0))
    tips = []
    for i in range(frames):
        bad = i % 2 == 1
        bw = body(True)
        im = img_pose(0.5)
        im[15] = L(x=0.6, y=0.675, z=0, visibility=1.0)
        im[13] = L(x=0.6, y=0.55, z=0, visibility=1.0)
        if bad and mode == "lost":   # 腕が取れたり取れなかったり
            for k in (13, 15):
                bw[k] = L(x=bw[k].x, y=bw[k].y, z=bw[k].z, visibility=0.05)
                im[k] = L(x=im[k].x, y=im[k].y, z=0, visibility=0.05)
        if bad and mode == "jump":   # 姿勢推定の手首だけが別の所へ飛ぶ
            bw = body(False)
            im[15] = L(x=0.95, y=0.4, z=0, visibility=1.0)
        hand = [L(x=0.6, y=0.675, z=0) for _ in range(21)]
        r = sv.solve(pose_world=bw, pose_image=im, hands=[(hand, flat_hand(np.array([0, 0, 0, 1.0])))], t=i / 30)
        tips.append(arm_tip(r))
    steps = [math.degrees(angle_between(tips[i], tips[i - 1])) for i in range(10, frames)]
    return max(steps), tips[-1]
from vrmtrack.mathq import angle_between  # noqa: E402
mx, last = flicker_run("lost")
ok &= check(f"腕の検出がちらついても腕は跳ねない (最大 {mx:.1f}°/フレーム)", mx < 4.0 and last[1] < -0.3)
mx, last = flicker_run("jump")
ok &= check(f"姿勢推定の手首だけ飛んでも腕は手に合わせたまま (最大 {mx:.1f}°/フレーム)", mx < 4.0 and last[1] < -0.3)

# ---- 数値安全性・設定エラー耐性・VMC
from vrmtrack.mathq import frame as q_frame, q_from_matrix, q_slerp  # noqa: E402
from vrmtrack.solver import _Euro  # noqa: E402
from vrmtrack.vmc import _cap, osc_message  # noqa: E402

v_rot = q_rot(q_axis_angle([0, 1, 0], math.pi * 0.5), np.array([0.0, 0.0, 1.0]))
ok &= check("q_rot で Z軸が90度回転し +X になる", np.allclose(v_rot, [1.0, 0.0, 0.0], atol=1e-6))

basis_col = q_frame(np.array([1.0, 0.0, 0.0]), np.array([1.0, 0.0, 0.0]))
ok &= check("collinear な frame 入力でも正規直交行列を返す", np.allclose(basis_col.T @ basis_col, np.eye(3), atol=1e-6))

q_deg = q_from_matrix(np.diag([-1.0001, -1.0001, 1.0]))
ok &= check("わずかに非直交な行列でも NaN/例外にならない", np.all(np.isfinite(q_deg)) and abs(np.linalg.norm(q_deg) - 1.0) < 1e-6)
ok &= check("同一クォータニオンの slerp は有限", np.all(np.isfinite(q_slerp(np.array([0, 0, 0, 1.0]), np.array([0, 0, 0, 1.0]), 0.5))))

cfg_bad = SolverConfig()
cfg_bad.update({"smooth": "not_a_float", "calib_delay": "bad", "head_gain": float("nan")})
ok &= check("不正な型や NaN の update は無視して維持する", cfg_bad.smooth == 0.85 and cfg_bad.head_gain == 1.0)

eu = _Euro()
eu.quat(np.array([0, 0, 0, 1.0]), 1.0 / 30, 1.0, 0.5)
q_after_nan = eu.quat(np.array([float("nan"), 0, 0, 1.0]), 1.0 / 30, 1.0, 0.5)
ok &= check("_Euro.quat は NaN を入れても壊れない", np.allclose(q_after_nan, [0, 0, 0, 1.0]))
eu_v = _Euro()
eu_v.value(0.5, 1.0 / 30, 1.0, 0.5)
v_after_nan = eu_v.value(float("nan"), 1.0 / 30, 1.0, 0.5)
ok &= check("_Euro.value は NaN を入れても壊れない", float(v_after_nan) == 0.5)

sv_hip = Solver(SolverConfig(mirror=True, smooth=0.0, hips_move=True))
sv_hip.solve(pose_world=body(True), pose_image=img_pose(0.45), t=0.0)
ok &= check("未キャリブレーションの _solve_hips は calib.hip を書き換えない", sv_hip.calib.hip is None)
sv_hip.cfg.mirror = False
r_hip_flip = sv_hip.solve(pose_world=body(True), pose_image=img_pose(0.45), t=0.03)
ok &= check("ミラー切替時に hips 基準が再初期化される", r_hip_flip.hips_pos is not None and abs(float(r_hip_flip.hips_pos[0])) < 1e-5)

ok &= check("VMC 親指マッピング", _cap("leftThumbMetacarpal") == "LeftThumbProximal" and _cap("rightThumbProximal") == "RightThumbIntermediate")
osc_pkt = osc_message("/VMC/Ext/OK", 1)
ok &= check("OSC メッセージは4バイト境界", len(osc_pkt) % 4 == 0 and osc_pkt.startswith(b"/VMC/Ext/OK\x00"))

# ---- 脚: 画角外検出・部分ロスト時の自然垂下・膝の過伸展防止
def leg_frame(knee_z=-0.25, ank_z=0.1, leg_vis=1.0, ank_img_y=0.90, knee_img_y=0.72):
    w = body(True)
    # 脚を持ち上げて膝を後ろへ曲げる姿勢 (MediaPipe: -z が前方, +y が下)
    w[25] = L(x=0.1, y=0.35, z=knee_z, visibility=leg_vis)
    w[26] = L(x=-0.1, y=0.35, z=knee_z, visibility=leg_vis)
    w[27] = L(x=0.1, y=0.65, z=ank_z, visibility=leg_vis)
    w[28] = L(x=-0.1, y=0.65, z=ank_z, visibility=leg_vis)
    im = img_pose(0.5)
    im[25] = L(x=0.55, y=knee_img_y, z=0.0, visibility=leg_vis)
    im[26] = L(x=0.45, y=knee_img_y, z=0.0, visibility=leg_vis)
    im[27] = L(x=0.55, y=ank_img_y, z=0.0, visibility=leg_vis)
    im[28] = L(x=0.45, y=ank_img_y, z=0.0, visibility=leg_vis)
    return w, im

sv_leg = Solver(SolverConfig(mirror=False, smooth=0.0, use_legs=True, arms_rest=True, lost_hold=0.2, lost_return=0.3))
# まず通常状態で脚を上げた姿勢を数フレーム記録
for i in range(5):
    wl, il = leg_frame(knee_z=-0.35, ank_z=0.05)
    r_leg_on = sv_leg.solve(pose_world=wl, pose_image=il, t=i / 30.0)
ul_dir_on = q_rot(r_leg_on.bones["leftUpperLeg"], np.array([0.0, -1.0, 0.0]))
ok &= check("脚トラッキング中は上腿が前へ上がる", ul_dir_on[2] > 0.3)

# 足首・膝が画角外 (y=1.15) に出たら lost_hold 中は保持し、その後自然に下がる
leg_dirs = []
for i in range(5, 65):
    wl, il = leg_frame(knee_z=-0.35, ank_z=0.05, ank_img_y=1.18, knee_img_y=1.12)
    rl = sv_leg.solve(pose_world=wl, pose_image=il, t=i / 30.0)
    leg_dirs.append(q_rot(rl.bones["leftUpperLeg"], np.array([0.0, -1.0, 0.0])))
leg_steps = [math.degrees(angle_between(leg_dirs[i], leg_dirs[i - 1])) for i in range(1, len(leg_dirs))]
ok &= check(f"画角外の脚は滑らかに下りる (最大 {max(leg_steps):.1f}°/F, 最終Y={leg_dirs[-1][1]:.2f})",
            max(leg_steps) < 8.0 and leg_dirs[-1][1] < -0.98)

# 膝だけ映り足首のみ画角外: 上腿は追い続け、下腿だけ垂直 (IDENT) に戻る
sv_knee = Solver(SolverConfig(mirror=False, smooth=0.0, use_legs=True, arms_rest=True, lost_hold=0.1, lost_return=0.25))
for i in range(5):
    wk, ik = leg_frame(knee_z=-0.3, ank_z=0.25, ank_img_y=0.92, knee_img_y=0.70)
    sv_knee.solve(pose_world=wk, pose_image=ik, t=i / 30.0)
for i in range(5, 50):
    wk, ik = leg_frame(knee_z=-0.3, ank_z=0.25, ank_img_y=1.18, knee_img_y=0.70)
    rk = sv_knee.solve(pose_world=wk, pose_image=ik, t=i / 30.0)
ul_k = q_rot(rk.bones["leftUpperLeg"], np.array([0.0, -1.0, 0.0]))
ll_k = q_rot(rk.bones["leftLowerLeg"], np.array([0.0, -1.0, 0.0]))
ok &= check("膝のみ見えている時は上腿が追従し下腿は自然に戻る", ul_k[2] > 0.3 and ll_k[1] < -0.95)

# 膝の過伸展クランプ: 膝より大きく前方 (-z) に足首が突き出ても逆関節にならない
sv_hyp = Solver(SolverConfig(mirror=False, smooth=0.0, use_legs=True))
wh, ih = leg_frame(knee_z=0.0, ank_z=-0.35)
rh = sv_hyp.solve(pose_world=wh, pose_image=ih, t=0.0)
shin_h = q_rot(rh.bones["leftLowerLeg"], np.array([0.0, -1.0, 0.0]))
ok &= check("膝の過伸展 (+Z 方向) が防止される", shin_h[2] <= 0.025)

# ---- 方向コヒーレンス加重 + 2次カスケードフィルタ: 手振り滑らかさ & 交互ジッター抑制
eu_wave = _Euro()
wave_raw = []
wave_filt = []
rng_w = np.random.default_rng(7)
for i in range(90):
    t_w = i / 30.0
    ang_w = math.radians(28.0) * math.sin(2.0 * math.pi * 1.2 * t_w) + math.radians(float(rng_w.normal(0.0, 0.35)))
    q_raw = q_axis_angle([0.0, 0.0, 1.0], ang_w)
    wave_raw.append(q_raw)
    wave_filt.append(eu_wave.quat(q_raw, 1.0 / 30.0, 1.2, 1.3, stab=math.radians(1.0)))
raw_jerk = float(np.std(np.diff([2.0 * math.atan2(q[2], q[3]) for q in wave_raw[30:]], n=3)))
filt_jerk = float(np.std(np.diff([2.0 * math.atan2(q[2], q[3]) for q in wave_filt[30:]], n=3)))
filt_amp = max(abs(2.0 * math.atan2(q[2], q[3])) for q in wave_filt[30:])
ok &= check(f"手振り軌道のジャークを大幅に低減しつつ振幅を維持 (jerk比={filt_jerk / raw_jerk:.2f}, 振幅={math.degrees(filt_amp):.1f}°)",
            filt_jerk < raw_jerk * 0.50 and math.degrees(filt_amp) > 22.0)

eu_jit = _Euro()
jit_deg = []
for i in range(60):
    sgn = 1.0 if (i % 2 == 0) else -1.0
    q_j = q_axis_angle([0.0, 1.0, 0.0], math.radians(0.8 * sgn))
    q_o = eu_jit.quat(q_j, 1.0 / 30.0, 2.0, 1.3, stab=math.radians(1.0))
    jit_deg.append(math.degrees(2.0 * math.atan2(q_o[1], q_o[3])))
ok &= check(f"交互微細振動 (±0.8°) を 1/4 以下に減衰 (std={float(np.std(jit_deg[20:])):.3f}°)",
            float(np.std(jit_deg[20:])) < 0.20)

print("ALL PASS" if ok else "SOME FAILED")
sys.exit(0 if ok else 1)

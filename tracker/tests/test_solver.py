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

# ---- 表情: 目を閉じただけで笑顔にならない・笑顔で目を閉じてもまばたきを送る・感度と強さ
from vrmtrack.mathq import q_axis_angle  # noqa: E402
from vrmtrack.solver import SolveResult, _twist  # noqa: E402
def blends(cfg_kw, bs):
    sv = Solver(SolverConfig(mirror=False, smooth=0.0, use_body=False, use_hands=False, **cfg_kw))
    return sv.solve(face={"matrix": m, "blendshapes": bs}).blends
b = blends({}, {"eyeBlinkLeft": 0.9, "eyeBlinkRight": 0.9, "mouthSmileLeft": 0.4, "mouthSmileRight": 0.4,
                "eyeSquintLeft": 0.5, "eyeSquintRight": 0.5})
ok &= check("目を閉じただけでは笑顔にならない", b["happy"] < 0.05 and b["blinkLeft"] > 0.8)
b = blends({"happy_sens": 0.5, "happy_gain": 0.7}, {"mouthSmileLeft": 0.9, "mouthSmileRight": 0.9, "eyeBlinkLeft": 0.9, "eyeBlinkRight": 0.9})
ok &= check("笑顔で目を閉じると、笑顔もまばたきも送る (目の崩れはうつしみらー側で防ぐ)", b["happy"] > 0.4 and b["blinkLeft"] > 0.8)
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

# ---- 手主導ハイブリッド腕IK・handedness割り当て・顔近接安定化
def pose_with_face():
    im = img_pose(0.5)
    im[0] = L(x=0.50, y=0.25, z=0.0, visibility=1.0)
    im[15] = L(x=0.60, y=0.675, z=0.0, visibility=1.0)
    im[13] = L(x=0.60, y=0.55, z=0.0, visibility=1.0)
    return im

# 1) Pose腕ロスト直後でも手が動けば手主導で腕が即座に追従する
sv_hd = Solver(SolverConfig(mirror=False, smooth=0.0, stabilize=0.0))
for i in range(4):
    h0 = [L(x=0.60, y=0.675, z=0.0) for _ in range(21)]
    sv_hd.solve(pose_world=body(True), pose_image=pose_with_face(), hands=[(h0, flat_hand(np.array([0, 0, 0, 1.0])))], t=i / 30.0)
tip_low = arm_tip(sv_hd.solve(pose_world=body(True), pose_image=pose_with_face(),
                              hands=[([L(x=0.60, y=0.675, z=0.0) for _ in range(21)], flat_hand(np.array([0, 0, 0, 1.0])))], t=4 / 30.0))
im_lost = pose_with_face()
for k in (13, 15):
    im_lost[k] = L(x=0.60, y=0.675, z=0.0, visibility=0.05)
bw_lost = body_no_left_arm()
for i in range(5, 8):
    y_up = 0.675 - 0.14 * (i - 4)  # 上へ手を動かす
    h_up = [L(x=0.66, y=y_up, z=0.0) for _ in range(21)]
    r_hd = sv_hd.solve(pose_world=bw_lost, pose_image=im_lost, hands=[(h_up, flat_hand(np.array([0, 0, 0, 1.0])))], t=i / 30.0)
tip_hi = arm_tip(r_hd)
ok &= check("Pose腕欠損中に手が動くと即座に腕が追従する", tip_hi[1] > tip_low[1] + 0.15)

# 2) 顔付近に手を上げても肘ポールが180度反転せず安定する
sv_fc = Solver(SolverConfig(mirror=False, smooth=0.5, stabilize=0.3))
elbows = []
rng_fc = np.random.default_rng(11)
for i in range(30):
    im_fc = pose_with_face()
    for k in (13, 15):
        im_fc[k] = L(x=0.50, y=0.28, z=0.0, visibility=0.2)
    hx = 0.51 + float(rng_fc.normal(0.0, 0.008))
    hy = 0.27 + float(rng_fc.normal(0.0, 0.008))
    h_fc = [L(x=hx, y=hy, z=0.0) for _ in range(21)]
    h_fc[9] = L(x=hx, y=hy - 0.04, z=0.0)
    rf = sv_fc.solve(pose_world=body_no_left_arm(), pose_image=im_fc,
                     hands=[(h_fc, flat_hand(np.array([0, 0, 0, 1.0])), ("Right", 0.95))], t=i / 30.0)
    up_f = q_mul(q_mul(rf.bones["chest"], rf.bones["spine"]), q_mul(rf.bones["leftShoulder"], rf.bones["leftUpperArm"]))
    elbows.append(q_rot(up_f, np.array([1.0, 0.0, 0.0])))
el_steps = [math.degrees(angle_between(elbows[i], elbows[i - 1])) for i in range(5, len(elbows))]
ok &= check(f"顔付近で手を動かしても肘ポールが急反転しない (最大 {max(el_steps):.1f}°/F)", max(el_steps) < 12.0)

# 3) 正中線越えの左手も handedness により右腕と取り違えない
sv_hn = Solver(SolverConfig(mirror=False, smooth=0.0, stabilize=0.0))
im_hn = pose_with_face()
for k in (13, 15):
    im_hn[k] = L(x=0.5, y=0.35, z=0.0, visibility=0.1)
for i, hx in enumerate((0.62, 0.55, 0.44)):
    h_cross = [L(x=hx, y=0.36, z=0.0) for _ in range(21)]
    # 非反転入力で本人の物理左手 = MediaPipe handedness "Right"
    r_hn = sv_hn.solve(pose_world=body_no_left_arm(), pose_image=im_hn,
                       hands=[(h_cross, flat_hand(np.array([0, 0, 0, 1.0])), ("Right", 0.95))], t=i / 30.0)
ok &= check("正中線を越えても handedness で左手として維持される", "leftHand" in r_hn.bones and "rightHand" not in r_hn.bones)

# 4) 顔付近の 1 フレーム外れ値ジャンプは棄却される
sv_out = Solver(SolverConfig(mirror=False, smooth=0.0, stabilize=0.0))
im_o = pose_with_face()
for k in (13, 15):
    im_o[k] = L(x=0.52, y=0.28, z=0.0, visibility=0.1)
for i in range(6):
    r_prev = sv_out.solve(pose_world=body_no_left_arm(), pose_image=im_o,
                          hands=[([L(x=0.52, y=0.28, z=0.0) for _ in range(21)], flat_hand(np.array([0, 0, 0, 1.0])), ("Right", 0.95))], t=i / 30.0)
tip_before_spike = arm_tip(r_prev)
r_spike = sv_out.solve(pose_world=body_no_left_arm(), pose_image=im_o,
                       hands=[([L(x=0.80, y=0.22, z=0.0) for _ in range(21)], flat_hand(np.array([0, 0, 0, 1.0])), ("Right", 0.95))], t=6 / 30.0)
tip_on_spike = arm_tip(r_spike)
spike_deg = math.degrees(angle_between(tip_before_spike, tip_on_spike))
ok &= check(f"顔付近の1フレーム外れ値テレポートを棄却 (跳ね={spike_deg:.2f}°)", spike_deg < 3.0)

# 5) 片手(右手)だけ見えて左腕がPoseで欠損していても、左腕が右手を奪って崩れない (非ミラー / ミラー両対応)
for mir, hl_lbl in ((False, "Left"), (True, "Right")):
    sv_one = Solver(SolverConfig(mirror=mir, smooth=0.0, stabilize=0.0))
    bw_one = body_no_left_arm() if not mir else body(True)
    if mir:
        # 鏡モード時は本人の左手(lm 13,15)を欠損させてモデルの右腕のみ生かすつもりの逆に、モデルの左腕(14,16)を欠損させる
        for k in (14, 16):
            bw_one[k] = L(x=bw_one[k].x, y=bw_one[k].y, z=bw_one[k].z, visibility=0.05)
    im_one = pose_with_face()
    if mir:
        # mirror=True: _side(15,16) -> lw=16, rw=15。モデルの右腕(=lm 15)を有効にし、モデルの左腕(=lm 16)を無効に
        im_one[15] = L(x=0.60, y=0.50, z=0.0, visibility=1.0)
        im_one[16] = L(x=0.40, y=0.50, z=0.0, visibility=0.05)
        hx_one = 0.62  # _pi(0.62) = 0.38 (モデル右側)
    else:
        # mirror=False: rw=16 を有効、lw=15 を無効に
        im_one[16] = L(x=0.38, y=0.50, z=0.0, visibility=1.0)
        im_one[15] = L(x=0.62, y=0.50, z=0.0, visibility=0.05)
        im_one[13] = L(x=0.62, y=0.45, z=0.0, visibility=0.05)
        hx_one = 0.43  # Pose 右手首から少しだけ内側にズレた位置
    h_one = [L(x=hx_one, y=0.48, z=0.0) for _ in range(21)]
    r_one = sv_one.solve(pose_world=bw_one, pose_image=im_one,
                         hands=[(h_one, flat_hand(np.array([0, 0, 0, 1.0])), (hl_lbl, 0.85))], t=0.0)
    ok &= check(f"右手のみ検出時に左腕が右手を奪わない (mirror={mir})",
                "rightHand" in r_one.bones and "leftHand" not in r_one.bones and "leftUpperArm" not in r_one.bones)

# 6) 同じ右手への二重検出 (距離 0.07) があっても片腕に重複・反対腕奪取しない
sv_dup = Solver(SolverConfig(mirror=False, smooth=0.0, stabilize=0.0))
im_dup = pose_with_face()
im_dup[16] = L(x=0.38, y=0.50, z=0.0, visibility=1.0)
im_dup[15] = L(x=0.62, y=0.50, z=0.0, visibility=0.05)
im_dup[13] = L(x=0.62, y=0.45, z=0.0, visibility=0.05)
h_dup1 = [L(x=0.38, y=0.48, z=0.0) for _ in range(21)]
h_dup2 = [L(x=0.45, y=0.48, z=0.0) for _ in range(21)]
r_dup = sv_dup.solve(pose_world=body_no_left_arm(), pose_image=im_dup,
                     hands=[(h_dup1, flat_hand(np.array([0, 0, 0, 1.0])), ("Left", 0.9)),
                            (h_dup2, flat_hand(np.array([0, 0, 0, 1.0])), ("Right", 0.55))], t=0.0)
ok &= check("右手の二重検出ゴーストで左腕が奪われない",
            "rightHand" in r_dup.bones and "leftHand" not in r_dup.bones and "leftUpperArm" not in r_dup.bones)

# 7) Poseで両腕が欠損中に右側へ左手と同じ位置に同ラベルのゴーストが2つ出ても片手のみ採用
sv_gh = Solver(SolverConfig(mirror=False, smooth=0.0, stabilize=0.0))
bw_none = body_no_left_arm()
for k in (14, 16):
    bw_none[k] = L(x=bw_none[k].x, y=bw_none[k].y, z=bw_none[k].z, visibility=0.05)
im_none = pose_with_face()
for k in (13, 14, 15, 16):
    im_none[k] = L(x=0.5, y=0.5, z=0.0, visibility=0.05)
h_gh1 = [L(x=0.32, y=0.45, z=0.0) for _ in range(21)]
h_gh2 = [L(x=0.42, y=0.45, z=0.0) for _ in range(21)]
r_gh = sv_gh.solve(pose_world=bw_none, pose_image=im_none,
                   hands=[(h_gh1, flat_hand(np.array([0, 0, 0, 1.0])), ("Left", 0.92)),
                          (h_gh2, flat_hand(np.array([0, 0, 0, 1.0])), ("Left", 0.70))], t=0.0)
ok &= check("同ラベルの近接ゴースト手があっても右手のみに割り当てる",
            "rightHand" in r_gh.bones and "leftHand" not in r_gh.bones and "leftUpperArm" not in r_gh.bones)

# ---- 画面下端手首・傾いたカメラ補正・離脱後の再進入反転
# 8) 手首が画面下端 (y=0.995) でも掌中心 (y=0.78) が画角内なら手と指を反映し、手の甲向きが正しく反映される
sv_edge = Solver(SolverConfig(mirror=True, smooth=0.0, hand_edge=0.03))
im_edge = img_pose(0.5)
im_edge[11] = L(x=0.60, y=0.93, z=0.0, visibility=0.8)  # mirror=True -> model right shoulder at _pi=0.40
im_edge[12] = L(x=0.40, y=0.93, z=0.0, visibility=0.8)
im_edge[15] = L(x=0.65, y=0.995, z=0.0, visibility=0.8)
im_edge[13] = L(x=0.65, y=0.95, z=0.0, visibility=0.8)
im_edge[16] = L(x=0.35, y=1.10, z=0.0, visibility=0.05)
im_edge[14] = L(x=0.35, y=1.05, z=0.0, visibility=0.05)
h_img_edge = [L(x=0.65, y=0.995, z=0.0) for _ in range(21)]
h_img_edge[9] = L(x=0.65, y=0.78, z=0.0)
# mirror=True で本人の左手手の甲がカメラ向き -> raw pinky->index = (+0.2, 0, 0), 指上 (0, -1, 0)
pts_back = [L(x=0.0, y=0.0, z=0.0) for _ in range(21)]
pts_back[9] = L(x=0.0, y=-1.0, z=0.0)
pts_back[5] = L(x=0.2, y=-0.9, z=0.0)
pts_back[17] = L(x=-0.2, y=-0.9, z=0.0)
for ki, kv in ((1, (0.2, -0.3, 0.0)), (2, (0.35, -0.5, 0.0)), (3, (0.5, -0.7, 0.0)), (4, (0.6, -0.85, 0.0))):
    pts_back[ki] = L(x=kv[0], y=kv[1], z=kv[2])
bw_edge = body(True)
bw_edge[14] = L(x=-0.5, y=-0.5, z=0.0, visibility=0.05)
bw_edge[16] = L(x=-0.5, y=-0.8, z=0.0, visibility=0.05)
r_edge = sv_edge.solve(pose_world=bw_edge, pose_image=im_edge, hands=[(h_img_edge, pts_back, ("Left", 0.92))], t=0.0)
ok &= check("手首が画面下端(y=0.995)でも掌が画角内なら右手が反映される", "rightHand" in r_edge.bones)
if "rightHand" in r_edge.bones:
    q_rw = q_mul(q_mul(r_edge.bones["chest"], r_edge.bones["spine"]),
                 q_mul(r_edge.bones["rightShoulder"], q_mul(r_edge.bones["rightUpperArm"],
                 q_mul(r_edge.bones["rightLowerArm"], r_edge.bones["rightHand"]))))
    palm_w = q_rot(q_rw, np.array([0.0, -1.0, 0.0]))
    thumb_side_w = q_rot(q_rw, np.array([0.0, 0.0, 1.0]))
    ok &= check("手の甲をカメラに向けたとき掌(-Y)が奥(-Z)、親指側が外側(-X)になる", palm_w[2] < -0.7 and thumb_side_w[0] < -0.7)

# 9) 掌ごと画面左端外 (p2d.x=0.01) のときは依然として除外される
h_img_oob = [L(x=0.99, y=0.50, z=0.0) for _ in range(21)]  # mirror=True -> _pi=0.01 < 0.03
h_img_oob[9] = L(x=0.99, y=0.40, z=0.0)
r_oob = Solver(SolverConfig(mirror=True, smooth=0.0, hand_edge=0.03)).solve(
    pose_world=bw_edge, pose_image=im_edge, hands=[(h_img_oob, pts_back, ("Left", 0.92))], t=0.0)
ok &= check("掌ごと画面端外のときは従来どおり除外される", "rightHand" not in r_oob.bones and "leftHand" not in r_oob.bones)

# 10) 体キャリブレーション(_inv0)で傾いたカメラでも手の向きが補正される
sv_cal = Solver(SolverConfig(mirror=False, smooth=0.0, use_face=False))
tilt = math.radians(25.0)
q_tilt = q_axis_angle([1.0, 0.0, 0.0], tilt)  # カメラが25度ピッチで傾いている基準姿勢
# MediaPipe ワールド座標に逆回転を与えて calib.body に傾いた姿勢を記録
pts_tilted_body = [L(x=0, y=0, z=0, visibility=1.0) for _ in range(33)]
for idx_b, v in ((11, [0.2, 0.5, 0.0]), (12, [-0.2, 0.5, 0.0]), (23, [0.1, 0.0, 0.0]), (24, [-0.1, 0.0, 0.0])):
    vr = q_rot(q_tilt, np.array(v, dtype=float))
    pts_tilted_body[idx_b] = L(x=vr[0], y=-vr[1], z=-vr[2], visibility=1.0)
sv_cal.start_capture()
for i in range(5):
    sv_cal.solve(pose_world=pts_tilted_body, pose_image=img_pose(0.5), t=i / 30.0)
cal_b = sv_cal.finish_capture()
sv_cal._inv0 = np.array([-cal_b.body[0], -cal_b.body[1], -cal_b.body[2], cal_b.body[3]])
# 傾いたカメラ座標内で「体の基準上方向」に沿った手を作る
hand_tilted = flat_hand(q_mul(q_tilt, q_axis_angle([0.0, 0.0, 1.0], math.pi * 0.5)))
res_cal = SolveResult()
res_cal.bones["leftLowerArm"] = np.array([0.0, 0.0, 0.0, 1.0])
res_cal.bones["__leftLowerArmWorld"] = np.array([0.0, 0.0, 0.0, 1.0])
sv_cal._solve_one_hand("left", hand_tilted, res_cal)
finger_cal = q_rot(res_cal.bones["leftHand"], np.array([1.0, 0.0, 0.0]))
ok &= check("体キャリブレーション(_inv0)が手の向きにも効いて上向き(+Y)になる", finger_cal[1] > 0.95)

# 11) 手が0.4秒以上画面から消えてから180度裏返って再登場しても即座に反映される
sv_re = Solver(SolverConfig(mirror=False, smooth=0.0, arms_rest=False))
im_re = pose_with_face()
h_re = [L(x=0.60, y=0.65, z=0.0) for _ in range(21)]
sv_re.solve(pose_world=body(True), pose_image=im_re,
            hands=[(h_re, flat_hand(np.array([0.0, 0.0, 0.0, 1.0])), ("Right", 0.95))], t=0.0)
sv_re.solve(pose_world=body(True), pose_image=im_re, hands=[], t=0.5)
# 180度回転した手 (x 軸反転相当の y-flip -> [0, 1, 0, 0])
r_re = sv_re.solve(pose_world=body(True), pose_image=im_re,
                   hands=[(h_re, flat_hand(q_axis_angle([1.0, 0.0, 0.0], math.pi)), ("Right", 0.95))], t=0.55)
q_lw_re = IDENT = np.array([0.0, 0.0, 0.0, 1.0])
if "leftHand" in r_re.bones:
    q_lw_re = q_mul(q_mul(r_re.bones["chest"], r_re.bones["spine"]),
                    q_mul(r_re.bones["leftShoulder"], q_mul(r_re.bones["leftUpperArm"],
                    q_mul(r_re.bones["leftLowerArm"], r_re.bones["leftHand"]))))
ok &= check("手が一時離脱後に裏返って再登場しても初フレームで反映される",
            "leftHand" in r_re.bones and q_rot(q_lw_re, np.array([0.0, 0.0, 1.0]))[2] < -0.7)

# 12) 反対側の手を下げた直後に頬横に手を上げても、誤 handedness で反対側の腕がクロスして奪わない
sv_cross = Solver(SolverConfig(mirror=True, smooth=0.0, stabilize=0.0))
im_cr0 = pose_with_face()
# mirror=True -> lm 15 はモデル右手, lm 16 はモデル左手
im_cr0[11] = L(x=0.68, y=0.86, z=0.0, visibility=0.9)
im_cr0[12] = L(x=0.32, y=0.86, z=0.0, visibility=0.9)
im_cr0[15] = L(x=0.72, y=0.75, z=0.0, visibility=0.9)
im_cr0[13] = L(x=0.76, y=0.92, z=0.0, visibility=0.9)
im_cr0[16] = L(x=0.28, y=1.10, z=0.0, visibility=0.05)
im_cr0[14] = L(x=0.28, y=1.05, z=0.0, visibility=0.05)
h_cr_r = [L(x=0.72, y=0.75, z=0.0) for _ in range(21)]
sv_cross.solve(pose_world=body(True), pose_image=im_cr0,
               hands=[(h_cr_r, flat_hand(np.array([0.0, 0.0, 0.0, 1.0])), ("Left", 0.90))], t=0.0)

im_cr1 = pose_with_face()
im_cr1[11] = L(x=0.68, y=0.86, z=0.0, visibility=0.9)
im_cr1[12] = L(x=0.32, y=0.86, z=0.0, visibility=0.9)
im_cr1[16] = L(x=0.28, y=0.58, z=0.0, visibility=0.9)   # mirror=True でモデル左手首 (_pi=0.72)
im_cr1[14] = L(x=0.22, y=0.88, z=0.0, visibility=0.85)
im_cr1[15] = L(x=0.72, y=1.12, z=0.0, visibility=0.05)  # モデル右手首は下がって欠損
im_cr1[13] = L(x=0.72, y=1.05, z=0.0, visibility=0.05)
bw_cr1 = body(True)
bw_cr1[14] = L(x=-0.25, y=-0.35, z=-0.10, visibility=0.9)
bw_cr1[16] = L(x=-0.18, y=-0.65, z=-0.20, visibility=0.9)
bw_cr1[13] = L(x=0.2, y=-0.2, z=0.0, visibility=0.05)
bw_cr1[15] = L(x=0.2, y=0.05, z=0.0, visibility=0.05)
h_cr_l = [L(x=0.28, y=0.58, z=0.0) for _ in range(21)]
h_cr_l[9] = L(x=0.30, y=0.45, z=0.0)
# 顔横のエッジ姿勢で誤って handedness=("Right", 0.90) (mirror=True では右腕を主張) が来たケース
r_cr = sv_cross.solve(pose_world=bw_cr1, pose_image=im_cr1,
                      hands=[(h_cr_l, pts_back, ("Right", 0.90))], t=0.35)
ok &= check("反対手下げ直後の顔横で誤handednessが来てもクロス取り違えしない",
            "leftHand" in r_cr.bones and sv_cross._hand_seen_t.get("right", -1.0) == 0.0)

# 13) こめかみ横の手が体キャリブレーションのヨー回転(18°)で顔の中心へ流れず顔外側に保たれる
sv_yaw = Solver(SolverConfig(mirror=True, smooth=0.0, stabilize=0.0, use_face=False))
sv_yaw.aspect = 16.0 / 9.0
yaw18 = math.radians(18.0)
q_yaw = q_axis_angle([0.0, 1.0, 0.0], yaw18)
pts_y = [L(x=0, y=0, z=0, visibility=1.0) for _ in range(33)]
for idx_b, v in ((11, [0.2, 0.5, 0.0]), (12, [-0.2, 0.5, 0.0]), (23, [0.1, 0.0, 0.0]), (24, [-0.1, 0.0, 0.0])):
    vr = q_rot(q_yaw, np.array(v, dtype=float))
    pts_y[idx_b] = L(x=vr[0], y=-vr[1], z=-vr[2], visibility=1.0)
im_y = [L(x=0.5, y=0.5, z=0.0, visibility=1.0) for _ in range(33)]
im_y[0] = L(x=1.0 - 0.48, y=0.48, z=0.0, visibility=1.0)
im_y[11] = L(x=1.0 - 0.28, y=0.87, z=0.0, visibility=1.0)
im_y[12] = L(x=1.0 - 0.72, y=0.88, z=0.0, visibility=1.0)
sv_yaw.start_capture()
for i in range(4):
    sv_yaw.solve(pose_world=pts_y, pose_image=im_y, t=i / 30.0)
sv_yaw.finish_capture()

im_y[13] = L(x=1.0 - 0.18, y=0.98, z=0.0, visibility=0.9)
im_y[15] = L(x=1.0 - 0.28, y=0.62, z=0.0, visibility=0.95)
im_y[14] = L(x=1.0 - 0.75, y=1.05, z=0.0, visibility=0.05)
im_y[16] = L(x=1.0 - 0.75, y=1.20, z=0.0, visibility=0.05)
pw_y = [L(x=vr[0], y=-vr[1], z=-vr[2], visibility=1.0) for vr in
        [q_rot(q_yaw, np.array([0.0, 0.0, 0.0])) for _ in range(33)]]
for idx_b, v in ((11, [0.19, 0.45, 0.0]), (12, [-0.19, 0.45, 0.0]), (23, [0.10, 0.0, 0.0]), (24, [-0.10, 0.0, 0.0]),
                 (13, [0.28, 0.22, 0.12]), (15, [0.18, 0.60, 0.25])):
    vr = q_rot(q_yaw, np.array(v, dtype=float))
    pw_y[idx_b] = L(x=vr[0], y=-vr[1], z=-vr[2], visibility=1.0)
for k_off in (14, 16):
    pw_y[k_off] = L(x=0.0, y=0.0, z=0.0, visibility=0.05)
h_y = [L(x=1.0 - 0.28, y=0.62, z=0.0) for _ in range(21)]
h_y[9] = L(x=1.0 - 0.30, y=0.49, z=0.0)
r_y = sv_yaw.solve(pose_world=pw_y, pose_image=im_y, hands=[(h_y, pts_back, ("Right", 0.92))], t=0.3)
wr_y_x = -0.13 + arm_tip(r_y, "right")[0]
ok &= check(f"こめかみ横の手はキャリブレーション(18°)後も顔外側に保たれる (wr_x={wr_y_x:.3f})", wr_y_x < -0.11)

# 14) 胸高さの低い手で手首が画面下外 (y=1.06) でも指付け根 (y=0.94) が映っていれば手が維持される
sv_low = Solver(SolverConfig(mirror=True, smooth=0.0, hand_edge=0.03))
im_low = pose_with_face()
im_low[11] = L(x=0.68, y=0.88, z=0.0, visibility=0.8)
im_low[12] = L(x=0.32, y=0.88, z=0.0, visibility=0.8)
im_low[16] = L(x=0.22, y=1.06, z=0.0, visibility=0.8)
im_low[14] = L(x=0.16, y=1.15, z=0.0, visibility=0.7)
h_low = [L(x=0.22, y=1.06, z=0.0) for _ in range(21)]
h_low[9] = L(x=0.28, y=0.94, z=0.0)
r_low = sv_low.solve(pose_world=body(True), pose_image=im_low, hands=[(h_low, pts_back, ("Right", 0.90))], t=0.0)
ok &= check("画面下端(手首y=1.06, 掌付け根y=0.94)でも手が維持され勝手に下がらない", "leftHand" in r_low.bones)

# 15) 顎前の片手で handedness がちらついても右腕が左腕に飛ばない
sv_fl = Solver(SolverConfig(mirror=True, smooth=0.0, stabilize=0.0))
im_fl = pose_with_face()
im_fl[11] = L(x=0.68, y=0.86, z=0.0, visibility=0.9)
im_fl[12] = L(x=0.32, y=0.86, z=0.0, visibility=0.9)
im_fl[15] = L(x=0.58, y=0.84, z=0.0, visibility=0.9)   # mirror=True -> モデル右手 (_pi=0.42)
im_fl[13] = L(x=0.64, y=0.96, z=0.0, visibility=0.85)
im_fl[16] = L(x=0.32, y=1.10, z=0.0, visibility=0.05)
im_fl[14] = L(x=0.32, y=1.04, z=0.0, visibility=0.05)
bw_fl = body(True)
bw_fl[14] = L(x=-0.2, y=-0.2, z=0.0, visibility=0.05)
bw_fl[16] = L(x=-0.2, y=0.05, z=0.0, visibility=0.05)
h_fl = [L(x=0.58, y=0.84, z=0.0) for _ in range(21)]
h_fl[9] = L(x=0.54, y=0.72, z=0.0)
r_fl0 = sv_fl.solve(pose_world=bw_fl, pose_image=im_fl, hands=[(h_fl, pts_back, ("Left", 0.85))], t=0.0)
r_fl1 = sv_fl.solve(pose_world=bw_fl, pose_image=im_fl, hands=[(h_fl, pts_back, ("Right", 0.85))], t=1 / 30.0)
ok &= check("顎前片手のhandednessちらつきでも反対腕に飛ばない",
            "rightHand" in r_fl0.bones and "rightHand" in r_fl1.bones and "leftHand" not in r_fl1.bones)

# 16) クローズアップで肩が画面下外(y=1.10, vis=0.10)・片側Pose肘欠損でも、挙げた両手が両方とも反映される
sv_cu = Solver(SolverConfig(mirror=True, smooth=0.0, stabilize=0.0))
sv_cu.aspect = 16.0 / 9.0
im_cu = [L(x=0.5, y=0.5, z=0.0, visibility=1.0) for _ in range(33)]
im_cu[0] = L(x=0.50, y=0.52, z=0.0, visibility=1.0)
im_cu[11] = L(x=0.86, y=1.10, z=0.0, visibility=0.10)  # mirror=True -> モデル右肩
im_cu[12] = L(x=0.14, y=1.10, z=0.0, visibility=0.10)  # mirror=True -> モデル左肩
im_cu[13] = L(x=0.84, y=1.02, z=0.0, visibility=0.80)
im_cu[15] = L(x=0.78, y=0.88, z=0.0, visibility=0.90)  # モデル右手Poseは映っている
im_cu[14] = L(x=0.16, y=1.20, z=0.0, visibility=0.05)  # モデル左腕Poseは画角外
im_cu[16] = L(x=0.22, y=1.22, z=0.0, visibility=0.05)
bw_cu = body(True)
bw_cu[14] = L(x=-0.2, y=-0.2, z=0.0, visibility=0.05)
bw_cu[16] = L(x=-0.2, y=0.05, z=0.0, visibility=0.05)
h_cu_r = [L(x=0.78, y=0.88, z=0.0) for _ in range(21)]
h_cu_r[9] = L(x=0.77, y=0.72, z=0.0)
h_cu_l = [L(x=0.20, y=0.88, z=0.0) for _ in range(21)]
h_cu_l[9] = L(x=0.21, y=0.72, z=0.0)
r_cu = sv_cu.solve(pose_world=bw_cu, pose_image=im_cu,
                   hands=[(h_cu_r, pts_back, ("Left", 0.90)), (h_cu_l, pts_back, ("Right", 0.90))], t=0.0)
ok &= check("クローズアップ両手で肩低vis・片腕Pose欠損でも両手・両腕が反映される",
            "leftHand" in r_cu.bones and "rightHand" in r_cu.bones
            and "leftUpperArm" in r_cu.bones and "rightUpperArm" in r_cu.bones)

# 17) 同クローズアップ条件で両腕Pose欠損＆両手のhandednessが一時的に同ラベルでも2本とも維持される
bw_cu2 = body(True)
for k in (13, 14, 15, 16):
    bw_cu2[k] = L(x=bw_cu2[k].x, y=bw_cu2[k].y, z=0.0, visibility=0.05)
im_cu2 = list(im_cu)
for k in (13, 14, 15, 16):
    im_cu2[k] = L(x=im_cu2[k].x, y=im_cu2[k].y, z=0.0, visibility=0.05)
r_cu2 = sv_cu.solve(pose_world=bw_cu2, pose_image=im_cu2,
                    hands=[(h_cu_r, pts_back, ("Left", 0.90)), (h_cu_l, pts_back, ("Left", 0.85))], t=0.1)
ok &= check("クローズアップで両腕Pose欠損＆同handednessでも離れた両手が両方維持される",
            "leftHand" in r_cu2.bones and "rightHand" in r_cu2.bones)

# 18) 肘が画面下外 (arm_ok=False) でも Pose 手首が右手上に映っていれば誤 handedness に負けず正しい腕へ付く
sv_pw = Solver(SolverConfig(mirror=True, smooth=0.0, stabilize=0.0))
sv_pw.aspect = 16.0 / 9.0
im_pw = pose_with_face()
im_pw[11] = L(x=0.72, y=0.92, z=0.0, visibility=0.8)  # mirror=True -> モデル右肩
im_pw[12] = L(x=0.28, y=0.92, z=0.0, visibility=0.8)  # mirror=True -> モデル左肩
im_pw[14] = L(x=0.22, y=1.08, z=0.0, visibility=0.05) # モデル左肘は画角外
im_pw[16] = L(x=0.28, y=0.94, z=0.0, visibility=0.85) # モデル左手首 Pose は画面下端手上で可視 (_pi=0.72)
im_pw[13] = L(x=0.76, y=1.10, z=0.0, visibility=0.05)
im_pw[15] = L(x=0.72, y=1.15, z=0.0, visibility=0.05) # モデル右手首は画面外
bw_pw = body(True)
for k_off in (13, 14, 15, 16):
    bw_pw[k_off] = L(x=bw_pw[k_off].x, y=bw_pw[k_off].y, z=0.0, visibility=0.05)
h_pw = [L(x=0.28, y=0.94, z=0.0) for _ in range(21)]
h_pw[9] = L(x=0.32, y=0.76, z=0.0)
r_pw = sv_pw.solve(pose_world=bw_pw, pose_image=im_pw, hands=[(h_pw, pts_back, ("Right", 0.92))], t=0.0)
ok &= check("肘が画角外でもPose手首が一致する腕(左手)へ正しく付く",
            "leftHand" in r_pw.bones and "rightHand" not in r_pw.bones)

# 19) 肘もPose手首も欠損中の左側手で、ノイズ水準(0.66)の誤handednessに負けて反対腕にならない
im_ns = pose_with_face()
im_ns[11] = L(x=0.72, y=0.92, z=0.0, visibility=0.8)
im_ns[12] = L(x=0.28, y=0.92, z=0.0, visibility=0.8)
for k_off in (13, 14, 15, 16):
    im_ns[k_off] = L(x=0.5, y=1.15, z=0.0, visibility=0.05)
h_ns = [L(x=0.25, y=0.78, z=0.0) for _ in range(21)]  # _pi=0.75 (モデル左側)
h_ns[9] = L(x=0.26, y=0.62, z=0.0)
sv_ns = Solver(SolverConfig(mirror=True, smooth=0.0, stabilize=0.0))
sv_ns.aspect = 16.0 / 9.0
r_ns = sv_ns.solve(pose_world=bw_pw, pose_image=im_ns, hands=[(h_ns, pts_back, ("Right", 0.66))], t=0.0)
ok &= check("ノイズ水準(0.66)の誤handednessで反対側の腕へ裏返らない",
            "leftHand" in r_ns.bones and "rightHand" not in r_ns.bones)

print("ALL PASS" if ok else "SOME FAILED")
sys.exit(0 if ok else 1)

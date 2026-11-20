"""クォータニオン [x, y, z, w] とベクトルの小さな数学ライブラリ (numpy のみ)。

座標系は VRM 1.0 正規化ボーン空間 (= Godot / glTF): Y 上, モデルは +Z を向く,
+X はモデルの左手側。
"""
from __future__ import annotations

import math

import numpy as np

IDENT = np.array([0.0, 0.0, 0.0, 1.0])


def norm(v: np.ndarray) -> np.ndarray:
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-9 else v


def q_mul(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ])


def q_inv(q: np.ndarray) -> np.ndarray:
    return np.array([-q[0], -q[1], -q[2], q[3]])


def q_rot(q: np.ndarray, v: np.ndarray) -> np.ndarray:
    p = np.array([v[0], v[1], v[2], 0.0])
    return q_mul(q_mul(q, p), q_inv(q))[:3]


def q_axis_angle(axis, ang: float) -> np.ndarray:
    a = norm(np.asarray(axis, dtype=float))
    s = math.sin(ang * 0.5)
    return np.array([a[0] * s, a[1] * s, a[2] * s, math.cos(ang * 0.5)])


def q_from_to(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """u を v に重ねる最短回転。"""
    u = norm(u)
    v = norm(v)
    d = float(np.dot(u, v))
    if d < -0.999999:
        axis = np.cross([1.0, 0.0, 0.0], u)
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross([0.0, 1.0, 0.0], u)
        return q_axis_angle(axis, math.pi)
    c = np.cross(u, v)
    q = np.array([c[0], c[1], c[2], 1.0 + d])
    return q / np.linalg.norm(q)


def q_from_matrix(m: np.ndarray) -> np.ndarray:
    """3x3 回転行列 (列ベクトル = 各軸) → クォータニオン。"""
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = np.array(q)
    return q / np.linalg.norm(q)


def frame(primary: np.ndarray, secondary: np.ndarray) -> np.ndarray:
    """primary を第1軸、secondary を第2軸 (直交化) とする正規直交基底 (列)。"""
    a = norm(primary)
    b = norm(secondary - a * float(np.dot(secondary, a)))
    c = np.cross(a, b)
    return np.stack([a, b, c], axis=1)


def q_slerp(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    d = float(np.dot(a, b))
    if d < 0:
        b = -b
        d = -d
    if d > 0.9995:
        r = a + (b - a) * t
        return r / np.linalg.norm(r)
    th = math.acos(min(1.0, d))
    s = math.sin(th)
    return (a * math.sin((1 - t) * th) + b * math.sin(t * th)) / s


def q_scale(q: np.ndarray, t: float) -> np.ndarray:
    """単位回転から q へ t の割合だけ回した回転。"""
    return q_slerp(IDENT, q, t)


def angle_between(u: np.ndarray, v: np.ndarray) -> float:
    u = norm(u)
    v = norm(v)
    return math.acos(max(-1.0, min(1.0, float(np.dot(u, v)))))

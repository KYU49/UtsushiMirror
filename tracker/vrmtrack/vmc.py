"""VMC Protocol (OSC over UDP) 送信。外部ライブラリなしで OSC を組み立てる。

VMC Protocol は Unity 座標 (左手系) が標準なので、VRM/glTF 座標から
位置 (-x, y, z)・回転 (x, -y, -z, w) に変換して送る。
"""
from __future__ import annotations

import socket
import struct
import time


def _pad(b: bytes) -> bytes:
    return b + b"\x00" * (4 - len(b) % 4)


def osc_message(addr: str, *args) -> bytes:
    tags = ","
    payload = b""
    for a in args:
        if isinstance(a, str):
            tags += "s"
            payload += _pad(a.encode("utf-8"))
        elif isinstance(a, int):
            tags += "i"
            payload += struct.pack(">i", a)
        else:
            tags += "f"
            payload += struct.pack(">f", float(a))
    return _pad(addr.encode("ascii")) + _pad(tags.encode("ascii")) + payload


def osc_bundle(msgs: list[bytes]) -> bytes:
    out = b"#bundle\x00" + struct.pack(">Q", 1)
    for m in msgs:
        out += struct.pack(">i", len(m)) + m
    return out


def _cap(name: str) -> str:
    """VRM 1.0 のボーン名 (leftUpperArm) → VMC/Unity HumanBodyBones 名 (LeftUpperArm)。"""
    n = name[0].upper() + name[1:]
    # VRM 1.0 の親指名を Unity の名前へ
    for vrm, unity in (("ThumbMetacarpal", "ThumbProximal"), ("ThumbProximal", "ThumbIntermediate")):
        if n.endswith(vrm):
            return n[: -len(vrm)] + unity
    return n


class VmcSender:
    def __init__(self, host: str = "127.0.0.1", port: int = 39539) -> None:
        self.addr = (host, port)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._t0 = time.perf_counter()

    def send(self, bones: dict, blends: dict, hips_pos=None) -> None:
        msgs = [osc_message("/VMC/Ext/OK", 1), osc_message("/VMC/Ext/T", time.perf_counter() - self._t0)]
        if hips_pos is not None:
            x, y, z = hips_pos
            msgs.append(osc_message("/VMC/Ext/Root/Pos", "root", -x, y, z, 0.0, 0.0, 0.0, 1.0))
        for name, q in bones.items():
            msgs.append(osc_message("/VMC/Ext/Bone/Pos", _cap(name), 0.0, 0.0, 0.0,
                                    float(q[0]), -float(q[1]), -float(q[2]), float(q[3])))
        for name, v in blends.items():
            msgs.append(osc_message("/VMC/Ext/Blend/Val", name, float(v)))
        if blends:
            msgs.append(osc_message("/VMC/Ext/Blend/Apply"))
        # 1 パケットを小さく保つ (LAN 越し・Android 宛てでも分割されないように)
        for i in range(0, len(msgs), 12):
            self.sock.sendto(osc_bundle(msgs[i:i + 12]), self.addr)

    def close(self) -> None:
        self.sock.close()

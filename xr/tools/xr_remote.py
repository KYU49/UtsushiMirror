"""VRMViewer XR を外部から動かすサンプル兼テスト用クライアント。

    python xr_remote.py --host 192.168.0.20 state
    python xr_remote.py --host 192.168.0.20 call play_animation '{"name":"walk"}'
    python xr_remote.py --host 192.168.0.20 call set_expressions '{"weights":{"happy":1}}'
    python xr_remote.py --host 192.168.0.20 call place_in_front '{"distance":1.2}'

VMC (ボーン・表情のリアルタイム制御) は tracker/vrm_tracker.py --host <XRのIP> で送れる。
"""
import argparse
import asyncio
import json

import websockets


async def call(host: str, port: int, method: str, params: dict):
    async with websockets.connect(f"ws://{host}:{port}") as ws:
        await ws.send(json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}))
        return json.loads(await asyncio.wait_for(ws.recv(), 30))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=19100)
    ap.add_argument("cmd", choices=["state", "call"])
    ap.add_argument("method", nargs="?")
    ap.add_argument("params", nargs="?", default="{}")
    a = ap.parse_args()
    method = "get_state" if a.cmd == "state" else a.method
    res = asyncio.run(call(a.host, a.port, method, json.loads(a.params)))
    print(json.dumps(res, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

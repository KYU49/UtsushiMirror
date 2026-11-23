"""assets/licenses/THIRD_PARTY_NOTICES.txt を作る (依存を更新したら実行し直す)。

    python scripts/gen_licenses.py

Rust の依存は `cargo metadata --offline` から、同梱アニメーションは
assets/animations/*/*.motion.json の license から集める。
アプリ内の「ライセンス」ページがこのファイルと Godot 自身のライセンス全文を表示する。
"""
from __future__ import annotations

import json
import subprocess
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "licenses" / "THIRD_PARTY_NOTICES.txt"

MIT_TEXT = """Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE."""


def rust_crates() -> list[dict]:
    out = subprocess.run(["cargo", "metadata", "--format-version", "1", "--offline"],
                         cwd=ROOT, capture_output=True, text=True, encoding="utf-8", check=True).stdout
    meta = json.loads(out)
    ws = set(meta["workspace_members"])
    pkgs = [p for p in meta["packages"] if p["id"] not in ws]
    return sorted(pkgs, key=lambda p: p["name"])


def animations() -> dict[str, list[str]]:
    groups: dict[str, list[str]] = defaultdict(list)
    for mj in sorted((ROOT / "assets" / "animations").glob("*/*.motion.json")):
        lic = json.loads(mj.read_text(encoding="utf-8")).get("license", {})
        key = f"{lic.get('attribution', mj.parent.name)}\n    License: {lic.get('spdx', '?')} {lic.get('url', '')}"
        src = lic.get("source", {}).get("url", "")
        if src:
            key += f"\n    Source: {src}"
        groups[key].append(mj.name.replace(".motion.json", ""))
    return groups


def main() -> None:
    L: list[str] = []
    w = L.append
    w("うつしみらー (UtsushiMirror) — サードパーティのライセンス / Third-party notices")
    w("=" * 64)
    w("")
    w("このソフトウェアは次のオープンソース・素材を利用しています。")
    w("Godot Engine 本体とその内蔵ライブラリのライセンス全文は、この下 (アプリ内表示) に続けて表示されます。")
    w("")
    w("[エンジン / Engine]")
    w("- Godot Engine — MIT License — Copyright (c) 2014-present Godot Engine contributors; (c) 2007-2014 Juan Linietsky, Ariel Manzur.")
    w("  https://godotengine.org/license")
    w("- Godot OpenXR Vendors plugin (XR 版のみ) — MIT License — Copyright (c) 2022-present Godot XR contributors")
    w("  https://github.com/GodotVR/godot_openxr_vendors")
    w("")
    w("[同梱アニメーション / Bundled animations]")
    w("- assets/animations/*.vrma (直下、確認用) と assets/animations/utsushi/*.vrma — このプロジェクトで作成したもの")
    w("    utsushi/ の動きは、NVIDIA の動き生成モデル (NVIDIA Open Model License) で作り、手で直したもの。")
    w("    文章の読み取りに Meta Llama 3 (Meta Llama 3 Community License) を使った。Built with Meta Llama 3.")
    for key, names in animations().items():
        w(f"- {key}")
        w(f"    VRMA conversion: open-vrma (CC0 1.0) https://huggingface.co/datasets/Sanami/open-vrma")
        w(f"    Files: {', '.join(names)}")
    w("")
    w("[同梱サンプルモデル / Bundled sample models]")
    w("- Seed-san.vrm — (c) VirtualCast, Inc. — VRM Public License 1.0 https://vrm.dev/licenses/1.0/")
    w("- VRM1_Constraint_Twist_Sample.vrm — (c) 2022 pixiv Inc. — VRM Public License 1.0 https://vrm.dev/licenses/1.0/")
    w("")
    w("[Webカメラトラッカー (tracker/, 別プロセス) / Webcam tracker]")
    w("- MediaPipe (ライブラリとモデル) — Apache License 2.0 — Copyright Google LLC https://github.com/google-ai-edge/mediapipe")
    w("- OpenCV (opencv-python) — Apache License 2.0 https://opencv.org/license/")
    w("- NumPy — BSD 3-Clause https://numpy.org/license/")
    w("- cv2-enumerate-cameras — MIT License https://github.com/chinaheyu/cv2_enumerate_cameras")
    w("- websockets — BSD 3-Clause https://github.com/python-websockets/websockets")
    w("")
    crates = rust_crates()
    w(f"[Rust ライブラリ / Rust crates] ({len(crates)} 個)")
    w("MPL-2.0 のもの (godot-rust 等) のソースは各リポジトリで公開されています。")
    for p in crates:
        authors = ", ".join(a.split("<")[0].strip() for a in p.get("authors", [])) or "-"
        repo = p.get("repository") or ""
        w(f"- {p['name']} {p['version']} — {p.get('license') or '?'} — {authors} {repo}".rstrip())
    w("")
    w("[MIT License 本文 / MIT License text] (上記で MIT とあるもの全てに適用。著作権表示は各項目を参照)")
    w("")
    w(MIT_TEXT)
    w("")
    w("[Apache License 2.0] https://www.apache.org/licenses/LICENSE-2.0")
    w("[Mozilla Public License 2.0] https://mozilla.org/MPL/2.0/")
    w("[BSD 3-Clause] https://opensource.org/license/bsd-3-clause")
    w("[CC0 1.0] https://creativecommons.org/publicdomain/zero/1.0/")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({len(crates)} crates)")


if __name__ == "__main__":
    main()

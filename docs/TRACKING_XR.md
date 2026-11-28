# Webカメラトラッキング と Android XR

## 1. Webカメラトラッキング

```
[Webカメラ] → tracker/vrm_tracker.py (MediaPipe: 顔・手・上半身)
                 │  カメラ画像はここで推論に使うだけ。表示・保存・送信しない
                 ├─▶ ワイヤー表示ウィンドウ (黒地に点と線だけ)
                 └─▶ VMC Protocol (UDP) ─▶ VRMViewer 本体 :39539 / VRMViewer XR :39539
```

### 準備 (初回のみ)

```powershell
cd tracker
uv sync
```

MediaPipe のモデル (約 30MB) は初回起動時に `tracker/models/` へ自動で取得されます。

### 使い方

- **本体から**: 設定ウィンドウ → 「トラッキング」 → 「▶ トラッキング開始」。
- **単体で**: `tracker\.venv\Scripts\python tracker\vrm_tracker.py --mode upper --camera auto`
  - `--mode face | upper | full | custom` (顔だけ / 顔と手 / 全身 / `--no-face` 等で個別指定)。
  - `--host <IP>` で別の PC や XR ヘッドセットへ送れます。
  - `--list-cameras` でカメラ一覧 (JSON)。`--camera auto` は仮想カメラ・キャプチャボードを避けて、映像が来るカメラを選びます。
  - `--pose-model lite|full|heavy`、`--width/--height/--fps`、`--detect-confidence`。
- **API から**: WebSocket JSON-RPC `tracking.start` (`{"mode":"upper","camera":"auto"}`) / `tracking.stop` / `tracking.status` /
  `tracking.set` (調整値の変更) / `tracking.calibrate` / `tracking.reset_calibration`。

### 設定ページの項目

| 区分 | 項目 | 変えたとき |
| --- | --- | --- |
| モード | 顔だけ / 顔と手 (上半身) / 全身 / カスタム | 再起動 |
| キャリブレーション | 実行 (開始までの秒数: すぐ (既定)・3・5・10 秒) / 補正を消す | 即時 |
| カメラ | カメラ、解像度、フレームレート、ミラー、ワイヤー表示 | 再起動 |
| 顔・表情 | 頭の動きの大きさ、体の追従 (顔だけのとき)、口の動きの大きさ、表情の自動付与 (笑顔・怒り・驚きそれぞれの感度と強さ) | 即時 |
| 目 | 左右のまばたきの同期、まばたきの感度、視線の有無、左右の視線の同期、視線の大きさ、可動限界 (左右・上・下、度) | 即時 |
| 手・腕 | 指 (親指は 3D の向きから)、手首のひねりを前腕へ回す割合、手だけ見えているときに手の位置から腕を推定、肩の上げ下げ (強さ・感度)、見失った腕・手を下ろす (待ち時間・下ろす時間)、画面端の手を無視 | 即時 |
| 全身 | 立ち位置の移動・しゃがみ | 即時 |
| 精度・安定性 | なめらかさ・速い動きへの追従 (One Euro フィルタ)、小刻みな揺れの抑制 (小さな動きだけを止める不感帯)、体の推定モデル、検出のしきい値、初期値に戻す | 即時 / 再起動 |

誤反応を防ぐ工夫: 目を閉じると口角の値も上がりやすいので、その分を差し引いてから笑顔を判定します。笑顔の表情は多くのモデルで
目を閉じる形を含むため、笑顔が付いている間は、うつしみらーがその強さの分だけまばたきを弱めて、まぶたが下がりすぎないようにしています (トラッキング以外の自動のまばたき・表情の操作にも効きます)。腕は、手首が画面の外にあるときや
見え方の信頼度が低いときは動かさず、手は腕が取れている側にだけ (肩幅に応じた距離以内で) 割り当てます。

動作中は fps・検出中の部位 (顔・手・体)・カメラの実 fps を表示し、映像が暗い・fps が低い・顔が見つからないときは注意を出します
(トラッカーから届くのは数値だけで、画像は届きません)。

即時に変わる項目は制御ポート (UDP `127.0.0.1:39540`、JSON) でトラッカーへ送ります。調整値は設定ファイルと同じフォルダの
`tracker_settings.json`、キャリブレーション結果は `tracker_calibration.json` に保存されます。

### キャリブレーション

画面を見るいつもの姿勢で、無表情のまま正面を向き、腕を下ろして実行します。約 1 秒間の平均を基準にして、次を打ち消します。

- 頭の向き: カメラが画面の上にあると、画面を見ているだけでうつむいて見える。
- 体の向き: カメラの傾き・斜めに座る向き (腕の向きの計算にも使う)。
- 表情: 普段の目の細さ・口元の癖 (無表情のときを 0 とする)。視線の中心。
- 全身: 立ち位置の基準。

顔 (または体) が半分以上のフレームで映っていないときは失敗として、前の結果を残します。

トラッキングが目の向きを送っている間は、本体のカメラ目線などの自動の視線より優先します。表情で目を動かすモデル (Seed-san など) では、目の向きを lookLeft / lookRight / lookUp / lookDown に変換して動かします。

### 精度・安定性のための処理

- カメラを別スレッドで読み、常に最新の 1 枚だけを推論する (溜まったフレームによる遅れを防ぐ)。
- One Euro フィルタ: 止まっているときは強く平滑化し、速く動くときは遅れを小さくする。まばたきは弱めにかける。
- 手のひらが 1 フレームで 110 度以上裏返るのは誤検出として数フレーム無視する。画面端の手は形が崩れやすいので使わない。
- 見失った腕・手は、少し待ってから自然な位置 (体の横) へ下ろす (固まったり、急に T ポーズへ戻ったりしない)。

### プライバシー

- カメラ画像を描画する処理はありません。ワイヤー表示は `np.zeros` の黒キャンバスに、ランドマークの点と線だけを描いています (`WireView.draw`)。
- 本体へ送るのはボーン回転と表情の数値だけです。

### 動きの対応

| 入力 | VRM |
| --- | --- |
| 顔の向き (顔の変換行列) | neck / head |
| まばたき・口・眉・笑顔 (ブレンドシェイプ) | blinkLeft/Right, aa, ih, ou, ee, oh, happy, angry, surprised |
| 視線 | leftEye / rightEye |
| 肩・肘・手首 (Pose) | spine / chest / UpperArm / LowerArm |
| 手のランドマーク | Hand (手首の向き) と各指の曲げ |
| 腰・膝・足首 (全身モード) | UpperLeg / LowerLeg |
| 腰の画像上の位置と肩幅 (全身モード) | 腰の位置 (左右・上下・前後の移動) |
| 頭の回転の一部 (顔だけモード) | spine / chest (体の追従) |

### Linux / Android での利用

- **Linux**: そのまま動きます (V4L2)。`uv sync` で同じ手順。
- **Android**: 計算部分 `tracker/vrmtrack/solver.py` は numpy だけの純粋な計算で、入出力も単純な配列・辞書にしてあります。
  Android 版は MediaPipe Tasks (Kotlin) でランドマークを得て、同じ計算を移植し、VMC で送れば本体・XR のどちらもそのまま受け取れます。
  既存の VMC 対応スマホアプリ (例: iPhone/Android の顔トラッキングアプリ) からの送信も受け付けます。

### テスト

```powershell
tracker\.venv\Scripts\python tracker\tests\test_solver.py   # 合成データで向き・左右・表情・補正・平滑化・見失い時の動作を確認
```

## 2. VRMViewer XR (Android XR)

`xr/` は Android XR 向けの別 Godot プロジェクトです。VRM の読み込み・MToon・SpringBone・VRMA は本体と同じコード (`godot/scripts/vrm`) を同期して使います。

### 機能

- パススルー (現実の部屋) の上に VRM キャラクターを表示
- コントローラー/手で **握る (グリップ)** とキャラクターをつかんで移動。離すとこちらを向く
- キャラクターはユーザーの頭を目で追う
- 足元の赤い円と、起動直後の頭上表示に **IP アドレスと受信ポート** が出る
- **外部プログラムからの制御**
  - WebSocket JSON-RPC `:19100` — `ping`, `get_state`, `load_vrm` (`path` または `url`), `load_vrma` (`path`/`url`),
    `play_animation`, `stop_animation`, `set_expression(s)`, `reset_expressions`, `set_lookat`, `set_bones`, `reset_bones`,
    `set_avatar_transform` (`position`/`rotation_y_deg`/`scale`), `place_in_front`, `face_user`, `set_passthrough`, `show_info`
  - VMC Protocol `:39539` — PC のトラッカーをそのまま XR のキャラクターへ:
    `tracker\.venv\Scripts\python tracker\vrm_tracker.py --host <XRのIP>`
  - サンプルクライアント: `xr/tools/xr_remote.py`

### ビルド

```powershell
.\scripts\build_xr.ps1            # デバッグ APK → xr\build\VRMViewerXR.apk
.\scripts\build_xr.ps1 -Release   # リリース (署名設定が必要)
```

スクリプトが共有コード・アセットの同期、Godot OpenXR Vendors プラグイン (5.2.0) の取得、
Android ビルドテンプレートの導入、APK 出力まで行います。インストールは `adb install -r xr\build\VRMViewerXR.apk`。

### PC での確認 (ヘッドセットなし)

```powershell
godot --path xr --xr-mode off
```

平面カメラで同じシーンが起動し、RPC・VMC の受信も試せます。

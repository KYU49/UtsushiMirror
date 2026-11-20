# うつしみらー (UtsushiMirror)

VRM のキャラクターをデスクトップに表示して、Web カメラだけで顔・手・体の動きを写せるアプリです。
細かい見た目の調整・背景の透過・配信や録画への出力まで、設定画面からまとめて行えます。

- **VRM 1.0 / 0.x のモデル**をそのまま読み込めます (ウィンドウにドラッグ&ドロップするだけ)
- **Web カメラでトラッキング**: 顔の向き・表情・まばたき・視線、手と指、上半身、(全身が映れば) 脚まで動かせます。カメラの映像はアプリに表示しません
- **デスクトップに透過表示**: 背景を透明にして、キャラクターだけを画面に置けます (クリックを後ろのウィンドウに通すこともできます)
- **見た目の調整**: カメラ・ライト・影・アニメ風などの画面効果・背景を、設定画面のスライダーで調整できます
- **配信・録画**: PNG スクリーンショット、MP4 / 背景透過 WebM の録画、OBS 向けの Spout2 出力、Discord / Zoom 向けの仮想カメラ
- **アニメーション**: `.vrma` を再生できます。待機・歩き・ダンスなどのモーションを同梱しています
- **設定の保存と持ち運び**: 設定をファイル (`.umset`) に書き出して、別の PC で読み込めます。シェーダー設定だけ (`.umshader`) の書き出しもできます

---

## 動作環境 (要求スペック)

| | 必要 | おすすめ |
|---|---|---|
| OS | Windows 10 / 11 (64 bit) | Windows 11 |
| CPU | 4 コア以上の x64 CPU | 6 コア以上 (トラッキングを使うとき) |
| メモリ | 4 GB | 8 GB 以上 |
| GPU | DirectX 12 または Vulkan 1.0 に対応したもの | 内蔵 GPU でも動きます。影や画面効果を強くするなら単体 GPU |
| 空き容量 | 約 200 MB | トラッキングを使うときは、さらに約 500 MB (Python とライブラリ) |
| Web カメラ | トラッキングを使うときだけ | 720p・30fps 以上 |

トラッキング・録画・配信を使うときだけ、次のものも必要です。

| 使う機能 | 必要なもの |
|---|---|
| Web カメラのトラッキング | [uv](https://docs.astral.sh/uv/) (Python 3.11 の環境を自動で用意します。下の「トラッキングの準備」を参照) |
| 動画の録画 | [FFmpeg](https://ffmpeg.org/download.html) (`ffmpeg.exe` に PATH が通っていること) |
| OBS への Spout2 出力 | [OBS Studio](https://obsproject.com/) と [obs-spout2-plugin](https://github.com/Off-World-Live/obs-spout2-plugin) |
| 仮想カメラ (Discord / Zoom) | [OBS Studio](https://obsproject.com/) (仮想カメラのドライバを借ります) と管理者権限 |

---

## インストール

1. [Releases](https://github.com/KYU49/UtsushiMirror/releases) から最新の `UtsushiMirror-vX.Y.Z-windows.zip` をダウンロードします。
2. zip を好きな場所に展開します (例: `C:\Tools\UtsushiMirror`)。
   - `Program Files` の中は書き込みが制限されるので避けてください。
3. 展開したフォルダの `UtsushiMirror.exe` を起動します。
   - 「Windows によって PC が保護されました」と出たときは、「詳細情報」→「実行」を押してください (署名していないアプリのため表示されます)。

アンインストールは、展開したフォルダを消すだけです。
設定は `%APPDATA%\UtsushiMirror` に保存されているので、設定も消すときはこのフォルダも消してください。

---

## 使い方

### モデルを表示する
- `.vrm` ファイルをウィンドウにドラッグ&ドロップします。設定画面の「モデル」ページから選ぶこともできます。
- 試しに使えるサンプルモデルが `assets/samples/Seed-san.vrm` にあります。
- 前回のモデルと設定は、次に起動したときに自動で読み込まれます。

### 画面の操作
| 操作 | 動作 |
|---|---|
| 左ドラッグ / 右ドラッグ | カメラを回す |
| `Shift` + 左ドラッグ / 中ドラッグ | カメラを平行移動 |
| ホイール | ズーム |
| `Alt` + 左ドラッグ | 枠なし・透過のウィンドウを動かす |
| 右クリック | メニュー (設定画面を開く・カメラやポーズの切り替え・撮影など) |

### 設定画面
左のメニューで、モデル / カメラ / ライト / シェーダー / ポーズ / アニメーション / 表情・視線 / トラッキング / 背景・ウィンドウ / 出力 / API・設定 / ライセンス のページを切り替えます。

- スライダーの名前をダブルクリックすると、初期値に戻ります。
- 「?」マークにマウスを乗せると、その項目で何が変わるかの説明が出ます。
- 設定画面を閉じてしまったときは、キャラクターの画面を右クリックするか、`Ctrl+Shift+S` で開き直せます。
- 画面下の「設定を保存」で、今の設定が次回の起動用に保存されます。「ファイルに書き出す…」「ファイルから読み込む…」で、設定をファイルとして持ち運べます。

### ショートカット
| キー | 動作 |
|---|---|
| `F1` 〜 `F10` | 表情の切り替え (普通・喜・怒・哀・楽・驚・あ・い・う・まばたき) |
| `F11` | スクリーンショット (`screenshots/` に保存) |
| `F12` | 録画の開始 / 停止 (`recordings/` に保存) |
| `Ctrl+Shift+S` | 設定画面の表示 / 非表示 |

ショートカットは設定画面の「表情・視線」ページで変えられます。

### 透過表示で操作できなくなったとき
クリックを後ろに通す設定 (クリックスルー) にすると、キャラクターの画面はクリックできなくなります。
タスクトレイの うつしみらー のアイコンを右クリックして、クリックスルーを解除してください。
モデルが表示されていないときは、透過・枠なし・クリックスルー・最前面が自動で解除されます。

---

## トラッキングの準備 (初回だけ)

Web カメラのトラッキングは、同梱の Python プログラム (`tracker/`) で行います。
初めて使う前に、[uv](https://docs.astral.sh/uv/) で `tracker\.venv` に Python の環境を作ります。Python 本体も uv が自動で用意するので、別に入れる必要はありません。

1. uv をインストールします (入っていない場合だけ)。PowerShell で次を実行し、終わったら PowerShell を開き直します。

```powershell
winget install --id=astral-sh.uv -e
```

2. 展開したフォルダの `tracker` に移動して、次を実行します (数分かかります)。

```powershell
cd C:\Tools\UtsushiMirror\tracker
```

```powershell
uv venv --python 3.11 .venv
```

```powershell
uv pip install --python .venv -r requirements.txt
```

3. うつしみらーの設定画面の「トラッキング」ページで、カメラとモード (顔だけ / 顔と手 / 全身 / カスタム) を選んで「開始」を押します。
4. 正面を向いて腕を下ろした姿勢で「キャリブレーション」を押すと、今の姿勢が基準になります。

- カメラの映像はアプリに表示しません。別ウィンドウには、検出した顔や手の線だけが表示されます。
- 表情・視線・腕の動き方などは、同じページのスライダーで調整できます。視線は「視線を動かす / カメラ目線 / 目線固定」から選べます。
- うまく動かないときは、明るい場所で、上半身がカメラに収まるようにしてください。

---

## 配信・録画で使う

### OBS (Spout2)
1. OBS に [obs-spout2-plugin](https://github.com/Off-World-Live/obs-spout2-plugin) を入れます。
2. うつしみらーの設定画面の「出力」ページで Spout2 をオンにします。
3. OBS のソースに **Spout2 Capture** を追加し、送信元に `UtsushiMirror` を選びます。背景の透過もそのまま使えます。

### Discord / Zoom (仮想カメラ)
OBS Studio をインストールしたうえで、管理者権限の PowerShell で次を実行します。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\register_vcam.ps1 -Elevate
```

その後、設定画面の「出力」ページで仮想カメラをオンにし、Discord / Zoom のカメラに「UtsushiMirror」を選びます。
登録していないときは、仮想カメラの機能だけが無効になります (アプリは普通に動きます)。

### 出力の解像度と背景
「出力」ページで、表示ウィンドウとは別に、録画・配信用の解像度と背景 (透過・単色・グリーンバックなど) を決められます。

---

## 外部から操作する (上級者向け)

うつしみらーは、起動中に外部のプログラムから操作できます。

- **WebSocket JSON-RPC** (`ws://127.0.0.1:19100`): モデルの読み込み・表情・ポーズ・カメラ・撮影など、ほぼすべての機能
- **OSC / VMC** (UDP `39539`): ほかのトラッキングソフトや VMC 対応ソフトからの動き
- **`vrmviewer-cli.exe`**: コマンドラインから操作 (`vrmviewer-cli.exe --help` で一覧)
- **`vrmviewer-mcp.exe`**: AI (MCP クライアント) から操作する MCP サーバー

```powershell
.\vrmviewer-cli.exe expr set happy 0.9 --transition 0.2
```

MCP クライアントへの登録例:

```json
{
  "mcpServers": {
    "utsushimirror": {
      "command": "C:\\Tools\\UtsushiMirror\\vrmviewer-mcp.exe",
      "env": { "VRMVIEWER_WS_URL": "ws://127.0.0.1:19100" }
    }
  }
}
```

ポート番号は設定画面の「API・設定」ページで変えられます。

---

## ライセンス

- うつしみらー本体: [GNU Affero General Public License v3.0](LICENSE)
- 同梱しているライブラリ・モーション・サンプルモデルは、それぞれのライセンスに従います。一覧は設定画面の「ライセンス」ページか、[`assets/licenses/THIRD_PARTY_NOTICES.txt`](assets/licenses/THIRD_PARTY_NOTICES.txt) を見てください。
  - サンプルモデル (`Seed-san.vrm` ほか) は VRM Public License 1.0 です。
  - 同梱モーションの多くは Quaternius (CC0) のものです。

---

## ソースからビルドする (開発者向け)

必要なもの: Windows 11、[Godot 4.7.2](https://godotengine.org/) と Windows 用のエクスポートテンプレート、Rust (stable)、[uv](https://docs.astral.sh/uv/) (トラッカー用。準備は上の「トラッキングの準備」と同じく `tracker` で `uv venv --python 3.11 .venv` と `uv pip install --python .venv -r requirements.txt`)。

```powershell
# ビルドして起動
powershell -ExecutionPolicy Bypass -File scripts/run.ps1 -GodotPath <Godot の exe のパス>
```

```powershell
# 配布用に out/ へ書き出す (配布するときは -NoTrackerVenv を付ける)
powershell -ExecutionPolicy Bypass -File scripts/export_win.ps1 -GodotPath <Godot の exe のパス> -NoTrackerVenv
```

構成:

- `godot/`: 本体 (Godot 4.7、VRM 1.0 のランタイムと MToon 1.0)
- `rust/`: GDExtension (VRM の読み込み・通信・Spout2・仮想カメラ)、CLI、MCP サーバー
- `tracker/`: Web カメラのトラッカー (MediaPipe → VMC)
- `xr/`: Android XR 版 (試作)
- 詳しい資料: [docs/TRACKING_XR.md](docs/TRACKING_XR.md)

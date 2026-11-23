# うつしみらー (UtsushiMirror)

VRM のキャラクターをデスクトップに表示して、Web カメラだけで顔・手・体の動きを写せるアプリです。
細かい見た目の調整・背景の透過・配信や録画への出力まで、設定画面からまとめて行えます。

- **VRM 1.0 / 0.x のモデル**をそのまま読み込めます (ウィンドウにドラッグ&ドロップするだけ)
- **Web カメラでトラッキング**: 顔の向き・表情・まばたき・視線、手と指、上半身、(全身が映れば) 脚まで動かせます。カメラの映像はアプリに表示しません
- **デスクトップに透過表示**: 背景を透明にして、キャラクターだけを画面に置けます (クリックを後ろのウィンドウに通すこともできます)
- **見た目の調整**: カメラ・ライト・影・アニメ風などの画面効果・背景を、設定画面のスライダーで調整できます
- **配信・録画**: PNG スクリーンショット、MP4 / 背景透過 WebM の録画、OBS 向けの Spout2 出力、Discord / Zoom 向けの仮想カメラ
- **アニメーション**: `.vrma` と、AMASS などの SMPL 系のモーション (`.npz`) を再生できます。待機・あいさつ・ポーズ・応援・歩く・走る・跳ぶ・回る・座るなどのモーションを同梱し、カテゴリーごとに並べて選べます (男性・女性の版があるものは名前の先頭が `male_` / `female_`)
- **プリセットのフォルダ**: 決まったフォルダに `.vrma` / `.npz` / シェーダー設定 (`.umshader`) を入れておくと、一覧やボタンにいつも出ます
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
| Web カメラのトラッキング | インターネット接続 (初回だけ。アプリのボタンから uv と Python の環境を自動で入れます。下の「トラッキングの準備」を参照) |
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

---

## アンインストール

うつしみらーはインストーラーを使わないので、下の場所を消せば元に戻ります。レジストリには何も書きません (仮想カメラを登録したときだけ例外。下の表を参照)。

### うつしみらーが作るもの
| 場所 | 中身 | 消し方 |
|---|---|---|
| 展開したフォルダ (例: `C:\Tools\UtsushiMirror`) | アプリ本体。その中に作られるものもあります:<br>・`tracker\.venv` … トラッキング用の Python の環境 (約 400 MB)<br>・`tracker\models` … 初めてトラッキングしたときにダウンロードする顔・体の認識モデル<br>・`screenshots`、`recordings` … スクリーンショットと録画の既定の保存先 | フォルダごと消します。残したい画像や動画は先に移してください |
| `%APPDATA%\UtsushiMirror` | 設定 (`vrmviewer_config.json`)、プリセット (`presets`)、トラッキングの設定と補正 (`tracker_settings.json`、`tracker_calibration.json`)、トラッキング用のシステムのインストールの記録 (`tracker_install.log`)、動作の記録 (`logs`)、描画のキャッシュ (`shader_cache`、`vulkan`) | フォルダごと消します。設定を残して入れ直すときは、消さずに残してください |

### トラッキング用のシステムを入れたときに入るもの
設定画面の「トラッキング」ページからインストールしたとき、うつしみらーのフォルダの外にも次のものが入ります。
uv は他のアプリでも使う道具なので、**うつしみらーのために初めて入れた場合だけ**消してください。

| 場所 | 中身 |
|---|---|
| `%USERPROFILE%\.local\bin\uv.exe`、`uvx.exe`、`uvw.exe` | uv 本体 (uv が入っていなかったときだけ入れます) |
| ユーザーの環境変数 `PATH` の `%USERPROFILE%\.local\bin` | uv を入れたときに、uv のインストーラーが足します |
| `%APPDATA%\uv\python` | uv が用意した Python 3.11 (約 70 MB) |
| `%LOCALAPPDATA%\uv\cache` | ダウンロードしたライブラリのキャッシュ (数百 MB) |

uv ごと消すときは、PowerShell で次の順に実行します ([uv の公式の手順](https://docs.astral.sh/uv/getting-started/installation/#uninstallation)と同じです)。

```powershell
uv cache clean
Remove-Item -Recurse -Force "$(uv python dir)", "$(uv tool dir)"
Remove-Item "$env:USERPROFILE\.local\bin\uv.exe", "$env:USERPROFILE\.local\bin\uvx.exe", "$env:USERPROFILE\.local\bin\uvw.exe"
```

最後に、「環境変数を編集」(Windows の検索で出ます) で、ユーザーの `Path` から `%USERPROFILE%\.local\bin` の行を消してください (他に何も入っていなければ)。
uv は残して容量だけ空けたいときは、`uv cache clean` だけでも十分です。

### 仮想カメラを登録したとき
`scripts\register_vcam.ps1` は、OBS Studio に入っている仮想カメラのドライバ (`obs-virtualcam-module64.dll`) を Windows に登録するだけで、うつしみらー独自のものは入れません。
OBS の仮想カメラと同じものなので、OBS を使い続けるなら登録はそのままにしてください。OBS ごと消すときは、OBS のアンインストールで一緒に消えます。

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

### プリセットのフォルダ
`%APPDATA%\UtsushiMirror\presets` の中のフォルダにファイルを入れておくと、いつでも選べるようになります。アプリを新しくしても消えません。

| フォルダ | 入れるもの | 出てくる場所 |
|---|---|---|
| `presets\animations` | `.vrma`、`.npz` | 「アニメーション」ページの一覧 |
| `presets\shaders` | `.umshader` (シェーダー設定を書き出したもの) | 「シェーダー」ページの「保存したプリセット」のボタン |

- 各ページの「プリセットのフォルダを開く」で、このフォルダを開けます。ファイルを入れたら「フォルダを読み直す」を押してください。
- 「シェーダー」ページでは、名前を入れて「今の設定をプリセットに保存」を押すと、このフォルダに保存されます。

### npz のモーション
AMASS などで配られている、SMPL / SMPL-H / SMPL-X の形式のモーション (`.npz`) を、`.vrma` と同じように再生できます。

- 中に `poses` (または `root_orient` と `pose_body`) と、`trans` (体の位置) が入っているファイルに対応しています。指の動きがあれば指も動きます。
- 関節の位置だけが入ったファイル (HumanML3D の `new_joints` など) には対応していません。
- モーションのデータには、商用利用できないものもあります (AMASS など)。使う前に、配っている所のライセンスを確かめてください。

### リップシンク (音声・テキストに口を合わせる)
設定の「トラッキング」タブの「リップシンク (音声・テキスト)」で、口の動きの元を選びます。

- **音声から** (既定): 音声・動画ファイル (mp3 / wav / ogg / flac / m4a / mp4 / mov / mkv など) に口を合わせます。ファイルをウィンドウへドロップしても始まります。
  - 音はうつしみらーからは鳴りません。別のソフトで流す音と同時に始めてください。
  - 読み込むときに一度だけ音を調べるので、動かしている間はほとんど負担がありません (AI のモデルは使いません)。
  - 「声の調子から感情も乗せる」をオンにすると、声の高さ・大きさ・抑揚から、喜び・驚き・悲しみを軽く乗せます (カメラのトラッキングで表情を動かしているときは乗せません)。
  - webm (Opus) など一部の形式は、[FFmpeg](https://ffmpeg.org/) が入っているときだけ読めます。
- **テキストから**: 文を入れて「しゃべる」を押すと、かなに合わせて口を動かします。
- **なし**: 口はトラッキング・アニメーションのまま動きます。

どちらで動かしているときも、口だけがリップシンクに揃い、体・頭・目・ほかの表情はトラッキングやアニメーションのまま動きます。

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
初めて使うときは、アプリから「トラッキング用のシステム」(Python 3.11 と MediaPipe などのライブラリ) を入れます。

1. 設定画面の「トラッキング」ページを開き、「⬇ トラッキング用のシステムをインストール」を押します。
2. 入るもの・必要な空き容量・要求スペックの案内が出るので、確かめて「インストールする」を押します。
   - [uv](https://docs.astral.sh/uv/) (Python の管理ツール) が入っていないときは、先に公式のインストーラーで uv を入れます (あなたのユーザーの PATH に uv が追加されます)。
   - 続けて `tracker` フォルダで `uv sync` を行い、Python とライブラリをダウンロードします。回線にもよりますが、数分かかります。
   - 使う容量は、アプリのフォルダに約 400 MB、ユーザーのフォルダ (uv の Python とキャッシュ) に約 500 MB です。
3. 終わると「▶ トラッキング開始」のボタンに変わります。

<details>
<summary>自分で入れる場合 (ボタンを使わないとき)</summary>

1. uv を入れます (入っていない場合だけ)。スタートメニューで「ターミナル」を開いて次を実行し、終わったらターミナルを閉じます。

```powershell
winget install --id=astral-sh.uv -e
```

2. エクスプローラーで、展開したフォルダの中の `tracker` フォルダを開きます。
3. フォルダの中の何もないところを右クリックして、「ターミナルで開く」を選びます。
   - Windows 10 で見当たらないときは、`Shift` を押しながら右クリックして「PowerShell ウィンドウをここで開く」を選んでください。
4. 開いたターミナルで次を実行します (数分かかります)。

```powershell
uv sync
```

</details>

4. 同じページで、カメラとモード (顔だけ / 顔と手 / 全身 / カスタム) を選んで「開始」を押します。
5. 正面を向いて腕を下ろした姿勢で「キャリブレーション」を押すと、今の姿勢が基準になります。

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

MCP では、モデル・表情・ポーズ・カメラ・撮影などの操作に加えて、次のような自然な動きもさせられます。

| 命令 | できること |
|---|---|
| `vrm_lipsync` | 音声・動画ファイル (`path`) に口を合わせます。音は出さないので、別で流す音と同時に呼びます。`emotion` で声の調子からの感情も乗せます |
| `vrm_talk` | 文 (`text`) や長さ (`duration_sec`) を渡すと、しゃべっているように口を動かします。かなは「あいうえお」の口の形に合わせます (音は出しません) |
| `vrm_set_lipsync_mode` | 口の動きの元を `off` / `audio` (`vrm_lipsync`) / `text` (`vrm_talk`) から選びます。選んだ方の命令だけが使えます |
| `vrm_walk` | 前後左右 (`direction`)・角度・行き先を指定すると、そちらを向いて歩き、着いたらカメラの方を向きます。キャラクターから見た向きか、画面から見た向きかを選べます |
| `vrm_stop_lipsync` / `vrm_stop_talk` / `vrm_stop_walk` | リップシンク・しゃべる・歩くを途中で止めます |
| `vrm_turn` | その場でくるっと回ります (`angle_deg: 360` で 1 回転)。`to: "camera"` でカメラの方を向きます |
| `vrm_set_model_transform` | キャラクターの位置・向き・大きさを決めます (画面の端から歩いてこさせるときなど) |
| `vrm_apply_pose_preset` | ピース・手を振るなどのポーズ。`keep_animation` で待機のアニメーションを止めずに重ねられます |
| `vrm_set_bones` / `vrm_reset_pose` | ボーンを直接動かす・戻す。`transition_sec` を付けると、今の姿勢からなめらかに移ります |
| `vrm_set_output_viewport` | 録画・Spout・仮想カメラの出力の大きさと背景。録画 (mp4) に背景を付けるときは `background_mode: "match_main"` にします (既定は透過で、mp4 では黒になります) |
| `vrm_apply_shader_preset` | プリセットのフォルダのシェーダー設定を名前で選びます |

---

## ライセンス

- うつしみらー本体: [GNU Affero General Public License v3.0](LICENSE)
- 同梱しているライブラリ・モーション・サンプルモデルは、それぞれのライセンスに従います。一覧は設定画面の「ライセンス」ページか、[`assets/licenses/THIRD_PARTY_NOTICES.txt`](assets/licenses/THIRD_PARTY_NOTICES.txt) を見てください。
  - サンプルモデル (`Seed-san.vrm` ほか) は VRM Public License 1.0 です。
  - 同梱モーションのうち、名前が英語の大文字で始まるものは Quaternius (CC0) のものです。`male_` / `female_` で始まるものは、このプロジェクトで NVIDIA の動き生成モデル (NVIDIA Open Model License) を使って作り、手で直したものです。

---

## ソースからビルドする (開発者向け)

必要なもの: Windows 11、[Godot 4.7.2](https://godotengine.org/) と Windows 用のエクスポートテンプレート、Rust (stable)、[uv](https://docs.astral.sh/uv/) (トラッカー用。`tracker` フォルダで `uv sync`)。

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

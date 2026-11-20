param(
    [switch]$Release,
    [switch]$SyncOnly,
    [string]$GodotPath = "",
    [string]$VendorsVersion = "5.2.0-stable"
)

# VRMViewer XR (Android XR) の APK を作る。
# 1. 共有コード・アセットを ../godot, ../assets から xr/ へ同期
# 2. Godot OpenXR Vendors プラグイン (Android XR 対応) を取得
# 3. Android ビルドテンプレートを導入し、インポート → APK 出力
# 出力: xr/build/VRMViewerXR.apk

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Xr = Join-Path $RepoRoot "xr"

function Sync-Dir($src, $dst) {
    if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    Copy-Item -Recurse $src $dst
}

Write-Host "[1/4] 共有コードとアセットを同期" -ForegroundColor Cyan
Sync-Dir (Join-Path $RepoRoot "godot/scripts/vrm") (Join-Path $Xr "scripts/vrm")
Sync-Dir (Join-Path $RepoRoot "godot/shaders") (Join-Path $Xr "shaders")
New-Item -ItemType Directory -Force (Join-Path $Xr "scripts/core") | Out-Null
Copy-Item -Force (Join-Path $RepoRoot "godot/scripts/core/procedural_idle.gd") (Join-Path $Xr "scripts/core/")
Sync-Dir (Join-Path $RepoRoot "assets/animations") (Join-Path $Xr "assets/animations")
Sync-Dir (Join-Path $RepoRoot "assets/samples") (Join-Path $Xr "assets/samples")
# .uid / .import はコピー先で作り直させる
Get-ChildItem -Recurse (Join-Path $Xr "scripts/vrm"), (Join-Path $Xr "shaders") -Include *.uid | Remove-Item -Force
if ($SyncOnly) { Write-Host "同期のみ完了"; exit 0 }

Write-Host "[2/4] OpenXR Vendors プラグイン ($VendorsVersion)" -ForegroundColor Cyan
$addonDir = Join-Path $Xr "addons/godotopenxrvendors"
if (-not (Test-Path (Join-Path $addonDir "plugin.gdextension"))) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "vrmviewer_xrvendors"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp "addon.zip"
    $url = "https://github.com/GodotVR/godot_openxr_vendors/releases/download/$VendorsVersion/godotopenxrvendorsaddon.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp "x") -Force
    New-Item -ItemType Directory -Force (Join-Path $Xr "addons") | Out-Null
    Copy-Item -Recurse -Force (Join-Path $tmp "x/asset/addons/godotopenxrvendors") (Join-Path $Xr "addons/")
}

if ($GodotPath -eq "") {
    $candidates = @(
        "D:\portableSoft\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe",
        "D:\portableSoft\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe"
    )
    $GodotPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $GodotPath) {
        $cmd = Get-Command godot4, godot -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { $GodotPath = $cmd.Source }
    }
}
if (-not $GodotPath) { throw "Godot が見つかりません。-GodotPath で指定してください" }

# Godot は警告を標準エラーに出すので、ここからはネイティブコマンドの出力で止めない
$ErrorActionPreference = "Continue"
Write-Host "[3/4] Android ビルドテンプレートとインポート" -ForegroundColor Cyan
& $GodotPath --headless --xr-mode off --path $Xr --import 2>&1 | Out-Host

Write-Host "[4/4] APK を出力" -ForegroundColor Cyan
New-Item -ItemType Directory -Force (Join-Path $Xr "build") | Out-Null
$apk = Join-Path $Xr "build/VRMViewerXR.apk"
$mode = if ($Release) { "--export-release" } else { "--export-debug" }
# 初回はビルドテンプレート (xr/android/build) も同時に導入する
$tpl = @()
if (-not (Test-Path (Join-Path $Xr "android/build/build.gradle"))) { $tpl = @("--install-android-build-template") }
& $GodotPath --headless --xr-mode off --path $Xr @tpl $mode "Android XR" $apk 2>&1 | Out-Host
if (-not (Test-Path $apk)) { throw "APK の出力に失敗しました" }
Write-Host "完了: $apk" -ForegroundColor Green

param(
    [switch]$SkipRustBuild,
    [switch]$Offline,
    [switch]$NoTrackerVenv,
    [string]$OutDir = "out",
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
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
    if (-not $GodotPath) {
        throw "Godot 4.7 executable not found. Pass -GodotPath <path>."
    }

    if (-not $SkipRustBuild) {
        Write-Host "[1/6] Building Rust crates (--release)..." -ForegroundColor Cyan
        $cargoArgs = @("build", "--workspace", "--release")
        if ($Offline) { $cargoArgs += "--offline" }
        & cargo @cargoArgs
        if ($LASTEXITCODE -ne 0) { throw "Cargo release build failed" }
    } else {
        Write-Host "[1/6] Skipping Rust build (-SkipRustBuild)." -ForegroundColor Yellow
    }

    Write-Host "[2/6] Staging release GDExtension DLL into godot/bin/..." -ForegroundColor Cyan
    $gdBinDir = Join-Path $RepoRoot "godot\bin"
    New-Item -ItemType Directory -Force -Path $gdBinDir | Out-Null
    $releaseDll = Join-Path $RepoRoot "target\release\vrm_gdext.dll"
    if (-not (Test-Path $releaseDll)) {
        throw "Missing release DLL: $releaseDll"
    }
    Copy-Item $releaseDll (Join-Path $gdBinDir "vrm_gdext.dll") -Force

    Write-Host "[3/6] Refreshing Godot resource/extension cache (--import)..." -ForegroundColor Cyan
    & $GodotPath --path godot --headless --import
    if ($LASTEXITCODE -ne 0) { throw "Godot --import failed with code $LASTEXITCODE" }

    Write-Host "[4/6] Exporting Windows Desktop release executable..." -ForegroundColor Cyan
    $absOutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) {
        $OutDir
    } else {
        Join-Path $RepoRoot $OutDir
    }
    if (Test-Path $absOutDir) {
        # Keep user data written by the exported app (screenshots / recordings)
        Get-ChildItem $absOutDir -Force |
            Where-Object { $_.Name -notin @("screenshots", "recordings") } |
            Remove-Item -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $absOutDir | Out-Null
    $absOutDir = (Resolve-Path $absOutDir).Path
    $absExePath = Join-Path $absOutDir "UtsushiMirror.exe"

    & $GodotPath --path godot --headless --export-release "Windows Desktop" $absExePath
    if ($LASTEXITCODE -ne 0) {
        throw "Godot --export-release failed with exit code $LASTEXITCODE"
    }
    if (-not (Test-Path $absExePath)) {
        throw "Expected exported executable was not created: $absExePath"
    }

    Write-Host "[5/6] Staging companion executables and runtime assets..." -ForegroundColor Cyan
    Copy-Item (Join-Path $RepoRoot "target\release\vrmviewer-cli.exe") (Join-Path $absOutDir "vrmviewer-cli.exe") -Force
    Copy-Item (Join-Path $RepoRoot "target\release\vrmviewer-mcp.exe") (Join-Path $absOutDir "vrmviewer-mcp.exe") -Force

    $dstAnimDir = Join-Path $absOutDir "assets\animations"
    New-Item -ItemType Directory -Force -Path $dstAnimDir | Out-Null
    Copy-Item (Join-Path $RepoRoot "assets\animations\*.vrma") $dstAnimDir -Force
    # Bundled CC0 animation packs live in sub folders (e.g. quaternius\), keep their license metadata too
    Get-ChildItem (Join-Path $RepoRoot "assets\animations") -Directory | ForEach-Object {
        Copy-Item $_.FullName $dstAnimDir -Recurse -Force
    }

    $dstLicDir = Join-Path $absOutDir "assets\licenses"
    New-Item -ItemType Directory -Force -Path $dstLicDir | Out-Null
    Copy-Item (Join-Path $RepoRoot "assets\licenses\*") $dstLicDir -Recurse -Force

    $dstSampleDir = Join-Path $absOutDir "assets\samples"
    New-Item -ItemType Directory -Force -Path $dstSampleDir | Out-Null
    $seedSample = Join-Path $RepoRoot "assets\samples\Seed-san.vrm"
    if (Test-Path $seedSample) {
        Copy-Item $seedSample (Join-Path $dstSampleDir "Seed-san.vrm") -Force
    }

    $dstScriptsDir = Join-Path $absOutDir "scripts"
    New-Item -ItemType Directory -Force -Path $dstScriptsDir | Out-Null
    Copy-Item (Join-Path $RepoRoot "scripts\register_vcam.ps1") (Join-Path $dstScriptsDir "register_vcam.ps1") -Force

    # Webcam tracker (separate Python process). The venv only works on a PC that has the same base Python,
    # so it is copied for local use; other PCs create tracker\.venv with `uv sync` (see README).
    $srcTracker = Join-Path $RepoRoot "tracker"
    $dstTracker = Join-Path $absOutDir "tracker"
    New-Item -ItemType Directory -Force -Path $dstTracker | Out-Null
    Copy-Item (Join-Path $srcTracker "vrm_tracker.py") $dstTracker -Force
    foreach ($f in @("pyproject.toml", "uv.lock", ".python-version", "install_tracker.ps1")) {
        Copy-Item (Join-Path $srcTracker $f) $dstTracker -Force
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $dstTracker "vrmtrack") | Out-Null
    Copy-Item (Join-Path $srcTracker "vrmtrack\*.py") (Join-Path $dstTracker "vrmtrack") -Force
    if (Test-Path (Join-Path $srcTracker "models")) {
        Copy-Item (Join-Path $srcTracker "models") $dstTracker -Recurse -Force
    }
    if (-not $NoTrackerVenv -and (Test-Path (Join-Path $srcTracker ".venv"))) {
        Write-Host "      Copying tracker Python environment (.venv)..." -ForegroundColor Cyan
        Copy-Item (Join-Path $srcTracker ".venv") $dstTracker -Recurse -Force
    }

    Copy-Item (Join-Path $RepoRoot "README.md") (Join-Path $absOutDir "README.md") -Force

    Write-Host "[6/6] Export complete: $absOutDir" -ForegroundColor Green
    Get-ChildItem -Path $absOutDir -Recurse -File |
        Where-Object { $_.FullName -notlike "*\tracker\.venv\*" } |
        Select-Object @{Name="RelativePath";Expression={$_.FullName.Substring($absOutDir.Length + 1)}}, Length |
        Format-Table -AutoSize
} finally {
    Pop-Location
}

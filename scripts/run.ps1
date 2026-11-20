param(
    [switch]$Release,
    [switch]$SkipBuild,
    [string]$ModelPath = "",
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    if (-not $SkipBuild) {
        Write-Host "[1/3] Building Rust crates..." -ForegroundColor Cyan
        if ($Release) {
            cargo build --workspace --release
        } else {
            cargo build --workspace
        }
        if ($LASTEXITCODE -ne 0) { throw "Cargo build failed" }
    }

    if ($GodotPath -eq "") {
        $candidates = @(
            "D:\portableSoft\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe",
            "D:\portableSoft\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
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

    $extCfg = Join-Path $RepoRoot "godot\.godot\extension_list.cfg"
    if (-not (Test-Path $extCfg)) {
        Write-Host "[2/3] Initializing Godot GDExtension registry (--import)..." -ForegroundColor Cyan
        & $GodotPath --path godot --headless --import | Out-Null
    }

    Write-Host "[3/3] Launching UtsushiMirror ($GodotPath)..." -ForegroundColor Green
    if ($ModelPath -ne "") {
        $absModel = (Resolve-Path $ModelPath).Path
        Write-Host "Loading model via CLI after launch: $absModel"
        $proc = Start-Process -FilePath $GodotPath -ArgumentList @("--path", "godot") -PassThru
        $cli = Join-Path $RepoRoot ("target\" + ($(if ($Release) { "release" } else { "debug" })) + "\vrmviewer-cli.exe")
        for ($i = 0; $i -lt 40; $i++) {
            Start-Sleep -Milliseconds 300
            & $cli ping *> $null
            if ($LASTEXITCODE -eq 0) {
                & $cli load $absModel
                break
            }
        }
        Wait-Process -Id $proc.Id
    } else {
        & $GodotPath --path godot
    }
} finally {
    Pop-Location
}

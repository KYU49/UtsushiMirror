# Installs what the webcam tracker needs, called from UtsushiMirror ("install tracking system" button).
#  1. uv (only when it is not installed yet), with the official installer from astral.sh
#  2. `uv sync --frozen` in this folder: downloads Python 3.11 and the libraries into .venv
# Progress goes to -Log as lines. Lines starting with "@@" are read by the app:
#   @@STEP uv | @@STEP sync | @@UV <path> | @@DONE | @@ERROR <message>
# Keep this file ASCII only (Windows PowerShell 5.1 reads scripts in the ANSI code page).
param(
    [Parameter(Mandatory = $true)][string]$Log
)

$ErrorActionPreference = "Continue"
$env:UV_NO_PROGRESS = "1"
$env:NO_COLOR = "1"

function Write-Log([string]$Line) {
    [System.IO.File]::AppendAllText($Log, $Line + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

function Find-Uv {
    $cmd = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:USERPROFILE ".local\bin\uv.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\uv.exe"),
        (Join-Path $env:USERPROFILE ".cargo\bin\uv.exe")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

try {
    Set-Location $PSScriptRoot
    $uv = Find-Uv
    if (-not $uv) {
        Write-Log "@@STEP uv"
        $installer = "Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $installer 2>&1 | ForEach-Object { Write-Log ([string]$_) }
        $uv = Find-Uv
        if (-not $uv) { throw "uv install failed" }
    }
    Write-Log "@@UV $uv"
    Write-Log "@@STEP sync"
    & $uv sync --frozen 2>&1 | ForEach-Object { Write-Log ([string]$_) }
    if ($LASTEXITCODE -ne 0) { throw "uv sync failed (exit code $LASTEXITCODE)" }
    if (-not (Test-Path (Join-Path $PSScriptRoot ".venv\Scripts\python.exe"))) { throw ".venv was not created" }
    Write-Log "@@DONE"
} catch {
    Write-Log ("@@ERROR " + $_.Exception.Message)
}

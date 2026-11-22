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
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

function Write-Log([string]$Line) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    for ($i = 0; $i -lt 5; $i++) {
        try {
            [System.IO.File]::AppendAllText($Log, $Line + "`n", $enc)
            return
        } catch {
            Start-Sleep -Milliseconds 40
        }
    }
}

function Find-Uv {
    $cmd = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $candidates = @()
    if ($env:UV_INSTALL_DIR) {
        $candidates += (Join-Path $env:UV_INSTALL_DIR "uv.exe")
        $candidates += (Join-Path $env:UV_INSTALL_DIR "bin\uv.exe")
    }
    if ($env:XDG_BIN_HOME) {
        $candidates += (Join-Path $env:XDG_BIN_HOME "uv.exe")
    }
    if ($env:USERPROFILE) {
        $candidates += (Join-Path $env:USERPROFILE ".local\bin\uv.exe")
        $candidates += (Join-Path $env:USERPROFILE ".cargo\bin\uv.exe")
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\uv.exe")
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

try {
    Set-Location $PSScriptRoot -ErrorAction Stop
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

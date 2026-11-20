param(
    [string]$DllPath = "",
    [switch]$Elevate,
    [switch]$StatusOnly
)

$ErrorActionPreference = "Stop"
$clsidKey = "HKLM:\SOFTWARE\Classes\CLSID\{A3FCE0F5-3493-419F-958A-ABA1250EC20B}"

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isAdmin = Test-IsAdmin
$registered = Test-Path $clsidKey

if ($StatusOnly) {
    Write-Output "is_admin=$isAdmin"
    Write-Output "vcam_registered=$registered"
    exit 0
}

if ($registered) {
    Write-Host "[OK] Virtual Camera CLSID is already registered ($clsidKey)." -ForegroundColor Green
    exit 0
}

if (-not $isAdmin) {
    Write-Host "[INFO] Administrator privileges are required to register the Virtual Camera filter." -ForegroundColor Yellow
    if ($Elevate) {
        $argList = @("-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
        if ($DllPath -ne "") { $argList += @("-DllPath", "`"$DllPath`"") }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        exit 0
    } else {
        Write-Host "Run this script from an elevated (Administrator) PowerShell, or run:"
        Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\register_vcam.ps1 -Elevate"
        exit 2
    }
}

$candidates = @()
if ($DllPath -ne "") { $candidates += $DllPath }
$candidates += @(
    "C:\Program Files\obs-studio\data\obs-plugins\win-dshow\obs-virtualcam-module64.dll",
    "C:\Program Files (x86)\obs-studio\data\obs-plugins\win-dshow\obs-virtualcam-module64.dll",
    "$env:ProgramData\obs-studio\obs-virtualcam-module64.dll"
)

$found = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $found) {
    Write-Host "[WARN] obs-virtualcam-module64.dll not found on this machine." -ForegroundColor Red
    Write-Host "Install OBS Studio (includes the Virtual Camera DirectShow/MediaFoundation driver) or pass -DllPath <path-to-obs-virtualcam-module64.dll>."
    exit 1
}

Write-Host "Registering Virtual Camera DLL: $found"
$proc = Start-Process regsvr32.exe -ArgumentList @("/s", "`"$found`"") -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Host "[ERROR] regsvr32 exited with code $($proc.ExitCode)" -ForegroundColor Red
    exit $proc.ExitCode
}

if (Test-Path $clsidKey) {
    Write-Host "[OK] Virtual Camera registered successfully! Restart UtsushiMirror to enable Virtual Camera output." -ForegroundColor Green
    exit 0
} else {
    Write-Host "[ERROR] Registration completed, but CLSID key was not found." -ForegroundColor Red
    exit 1
}

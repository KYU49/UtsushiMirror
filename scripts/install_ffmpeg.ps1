# Installs FFmpeg into <AppDir>\tools\ffmpeg, called from UtsushiMirror ("install FFmpeg" button).
# The user's PATH and registry are not changed: the app looks in tools\ffmpeg first, then on PATH.
#  1. download a pinned build (gyan.dev "essentials", GPLv3) from GitHub releases
#  2. check its SHA-256
#  3. extract it to tools\ffmpeg (bin\ffmpeg.exe, LICENSE, README)
# Progress goes to -Log as lines. Lines starting with "@@" are read by the app:
#   @@STEP download | @@PROGRESS <0-100> | @@STEP verify | @@STEP extract | @@DONE | @@ERROR <message>
# Keep this file ASCII only (Windows PowerShell 5.1 reads scripts in the ANSI code page).
param(
    [Parameter(Mandatory = $true)][string]$Log,
    [Parameter(Mandatory = $true)][string]$AppDir,
    # For tests only (e.g. a file:/// URL to a local zip). Normal use takes the pinned values below.
    [string]$Url = "",
    [string]$Sha256 = ""
)

# When updating the version, take the digest from the GitHub release (asset "digest" field).
$Version = "9.1"
if (-not $Url) { $Url = "https://github.com/GyanD/codexffmpeg/releases/download/9.1/ffmpeg-9.1-essentials_build.zip" }
if (-not $Sha256) { $Sha256 = "b9bbbb3acece000cbeec994f856649354e52c773807841e78908374b24d658fd" }

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
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

function Get-File([string]$From, [string]$To) {
    $req = [System.Net.WebRequest]::Create($From)
    $req.Timeout = 30000
    if ($req -is [System.Net.HttpWebRequest]) {
        $req.UserAgent = "UtsushiMirror-ffmpeg-installer"
        $req.ReadWriteTimeout = 60000
    }
    $res = $req.GetResponse()
    try {
        $total = $res.ContentLength
        $src = $res.GetResponseStream()
        $dst = [System.IO.File]::Create($To)
        try {
            $buf = New-Object byte[] (1024 * 1024)
            $done = [int64]0
            $last = -1
            while (($n = $src.Read($buf, 0, $buf.Length)) -gt 0) {
                $dst.Write($buf, 0, $n)
                $done += $n
                if ($total -gt 0) {
                    $pct = [int][Math]::Floor($done * 100 / $total)
                    if ($pct -ne $last) {
                        Write-Log ("@@PROGRESS " + $pct)
                        $last = $pct
                    }
                }
            }
        } finally {
            $dst.Close()
            $src.Close()
        }
    } finally {
        $res.Close()
    }
}

$tools = Join-Path $AppDir "tools"
$dest = Join-Path $tools "ffmpeg"
$zip = Join-Path $tools "ffmpeg-download.zip"
$tmp = Join-Path $tools "ffmpeg-extract"
try {
    New-Item -ItemType Directory -Force -Path $tools | Out-Null
    # The app folder must be writable (not under Program Files)
    $probe = Join-Path $tools ".write-test"
    try {
        [System.IO.File]::WriteAllText($probe, "ok")
        Remove-Item $probe -Force
    } catch {
        throw "Cannot write to $tools. Move the UtsushiMirror folder out of Program Files."
    }

    Write-Log "@@STEP download"
    Write-Log "FFmpeg $Version : $Url"
    Get-File $Url $zip

    Write-Log "@@STEP verify"
    $hash = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToLowerInvariant()
    if ($hash -ne $Sha256) { throw "SHA-256 mismatch (got $hash)" }

    Write-Log "@@STEP extract"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $root = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (-not $root -or -not (Test-Path (Join-Path $root.FullName "bin\ffmpeg.exe"))) { throw "ffmpeg.exe was not found in the archive" }
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Join-Path $dest "bin") | Out-Null
    Move-Item (Join-Path $root.FullName "bin\ffmpeg.exe") (Join-Path $dest "bin\ffmpeg.exe")
    foreach ($f in @("LICENSE", "README.txt")) {
        $p = Join-Path $root.FullName $f
        if (Test-Path $p) { Move-Item $p (Join-Path $dest $f) }
    }
    Set-Content -Path (Join-Path $dest "VERSION.txt") -Value ("FFmpeg " + $Version + " essentials (gyan.dev, GPLv3)`r`n" + $Url) -Encoding ASCII

    & (Join-Path $dest "bin\ffmpeg.exe") -hide_banner -version 2>&1 | Select-Object -First 1 | ForEach-Object { Write-Log ([string]$_) }
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg.exe does not run (exit code $LASTEXITCODE)" }
    Write-Log "@@DONE"
} catch {
    Write-Log ("@@ERROR " + $_.Exception.Message)
} finally {
    if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

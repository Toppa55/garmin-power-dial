$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "Analog Power Dial - Edge 130 Plus" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectDir

function Find-MonkeyC {
    $cmd = Get-Command monkeyc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $roots = @(
        "$env:APPDATA\Garmin\ConnectIQ\Sdks",
        "$env:LOCALAPPDATA\Garmin\ConnectIQ\Sdks",
        "$env:USERPROFILE\AppData\Roaming\Garmin\ConnectIQ\Sdks"
    ) | Select-Object -Unique

    $found = @()
    foreach ($root in $roots) {
        if (Test-Path $root) {
            $found += Get-ChildItem -Path $root -Filter monkeyc.bat -Recurse -ErrorAction SilentlyContinue
        }
    }

    if ($found.Count -gt 0) {
        return ($found | Sort-Object FullName -Descending | Select-Object -First 1).FullName
    }
    return $null
}

$MonkeyC = Find-MonkeyC
if (-not $MonkeyC) {
    Write-Host ""
    Write-Host "Garmin Connect IQ SDK was not found." -ForegroundColor Yellow
    Write-Host "Install Garmin's Connect IQ SDK Manager + SDK, then double-click BUILD_AND_INSTALL.cmd again."
    Write-Host "Official SDK page: https://developer.garmin.com/connect-iq/sdk/"
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

Write-Host "Found compiler:" $MonkeyC -ForegroundColor Green

$BuildDir = Join-Path $ProjectDir "build"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$Prg = Join-Path $BuildDir "AnalogPowerDial.prg"
$KeyCandidates = @(
    $env:GARMIN_DEVELOPER_KEY,
    (Join-Path $ProjectDir "developer_key.der"),
    (Join-Path $env:USERPROFILE "Documents\Garmin Connect IQ\Keys\garmin-power-dial-developer-key.der"),
    (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Garmin Connect IQ\Keys\garmin-power-dial-developer-key.der")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
$Key = $KeyCandidates | Select-Object -First 1
if (-not $Key) {
    throw "Garmin signing key not found. Set GARMIN_DEVELOPER_KEY or provide developer_key.der in the project folder."
}
$Jungle = Join-Path $ProjectDir "monkey.jungle"

Write-Host "Using signing key:" $Key -ForegroundColor Green
Write-Host "Building for Edge 130 Plus..." -ForegroundColor Cyan
& $MonkeyC -d edge130plus -f $Jungle -o $Prg -y $Key
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Prg)) {
    throw "Garmin build failed. See compiler messages above."
}

Write-Host "Build complete:" $Prg -ForegroundColor Green

# Edge 130 Plus normally appears as USB mass storage. Look for GARMIN\APPS.
$garminApps = $null
$drives = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -in 2,3 }
foreach ($drive in $drives) {
    $candidate = Join-Path ($drive.DeviceID + "\") "GARMIN\APPS"
    if (Test-Path $candidate) {
        $garminApps = $candidate
        break
    }
}

if ($garminApps) {
    $dest = Join-Path $garminApps "AnalogPowerDial.prg"
    Copy-Item -Force $Prg $dest
    Write-Host ""
    Write-Host "Installed to Garmin:" $dest -ForegroundColor Green
    Write-Host "Safely eject the Edge, then add 'Analog Power Dial' as a Connect IQ data field on a cycling data screen." -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "The .prg is ready, but I couldn't find a connected Garmin drive." -ForegroundColor Yellow
    Write-Host "Connect the Edge 130 Plus by USB, then either rerun this file or copy:" 
    Write-Host "  $Prg"
    Write-Host "to:" 
    Write-Host "  GARMIN\APPS\"
}

Write-Host ""
Read-Host "Press Enter to close"

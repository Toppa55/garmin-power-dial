$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile = Join-Path $ProjectDir ".env.local"
if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "Missing .env.local. Configure the companion service first."
}
$TokenLine = Get-Content -LiteralPath $EnvFile | Where-Object { $_ -match '^COMPANION_TOKEN=\S+' } | Select-Object -Last 1
if (-not $TokenLine) { throw "COMPANION_TOKEN is missing from .env.local." }
$PairingToken = $TokenLine.Substring("COMPANION_TOKEN=".Length)
$Port = 8787
while (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) { $Port++ }
$Addresses = Get-NetIPConfiguration |
    Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address } |
    ForEach-Object { $_.IPv4Address.IPAddress } |
    Where-Object { $_ -and $_ -notmatch '^(127\.|169\.254\.)' } |
    Select-Object -Unique

Write-Host ""
Write-Host "Ride Brain iPhone web app" -ForegroundColor Cyan
Write-Host "Keep this window open while using the app." -ForegroundColor Cyan
foreach ($Address in $Addresses) {
    Write-Host "On the same Wi-Fi, open: http://$Address`:$Port/phone" -ForegroundColor Green
}
Write-Host "Pairing token: $PairingToken" -ForegroundColor Yellow
Write-Host "Keep the token private. For rides away from this Wi-Fi, use an HTTPS-hosted backend." -ForegroundColor Yellow
Write-Host ""

$env:HOST = "0.0.0.0"
$env:PORT = [string]$Port
Set-Location (Join-Path $ProjectDir "backend")
& node --env-file=../.env.local src/server.mjs

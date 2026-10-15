param([string]$BackendHost = '10.0.2.2', [switch]$Https, [string]$Device)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$scheme = if ($Https) { 'https' } else { 'http' }
$arguments = @('run', "--dart-define=ACCOUNT_API_URL=${scheme}://${BackendHost}:8002",
    "--dart-define=PACKAGED_FOOD_API_URL=${scheme}://${BackendHost}:8000",
    "--dart-define=COOKED_FOOD_API_URL=${scheme}://${BackendHost}:8001")
if ($Device) { $arguments += @('-d', $Device) }
Push-Location $projectRoot
try {
    & (Join-Path $PSScriptRoot 'Flutter.ps1') @arguments
    exit $LASTEXITCODE
} finally { Pop-Location }

param([ValidateSet('accounts','packaged','cooked')][string]$Service = 'accounts',
      [string]$ListenAddress = '0.0.0.0')
$ErrorActionPreference = 'Stop'
$backend = Join-Path (Split-Path $PSScriptRoot -Parent) 'backend'
$python = Join-Path $backend '.venv-accounts/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $python)) { throw 'Run scripts/Setup-Backend.ps1 first.' }
$environment = Join-Path $backend '.env'
if (-not (Test-Path -LiteralPath $environment)) { Copy-Item (Join-Path $backend '.env.example') $environment }
$module = @{ accounts = 'account_api:app'; packaged = 'main:app'; cooked = 'main2:app' }[$Service]
$port = @{ accounts = 8002; packaged = 8000; cooked = 8001 }[$Service]
Push-Location $backend
try {
    & $python -m uvicorn $module --env-file $environment --host $ListenAddress --port $port
    exit $LASTEXITCODE
} finally { Pop-Location }

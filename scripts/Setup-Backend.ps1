param([string]$PythonExecutable = 'python', [switch]$WithFood)
$ErrorActionPreference = 'Stop'
$backend = Join-Path (Split-Path $PSScriptRoot -Parent) 'backend'
$venv = Join-Path $backend '.venv-accounts'
$python = Join-Path $venv 'Scripts/python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    & $PythonExecutable -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the Python environment. Use a standard Python 3.11 or 3.12 installation.' }
}
$requirements = if ($WithFood) { 'requirements-food.txt' } else { 'requirements-accounts-test.txt' }
& $python -m pip install -r (Join-Path $backend $requirements)
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
$environment = Join-Path $backend '.env'
if (-not (Test-Path -LiteralPath $environment)) { Copy-Item (Join-Path $backend '.env.example') $environment }
Write-Host 'Backend ready. Set backend/.env, start MongoDB, then run scripts/Start-Backend.ps1.'

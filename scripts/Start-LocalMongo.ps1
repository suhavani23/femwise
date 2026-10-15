param([int]$Port = 27017)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$mongo = Get-Command mongod -ErrorAction SilentlyContinue
$executable = if ($mongo) { $mongo.Source } else {
    Get-ChildItem (Join-Path $projectRoot '.tools/mongodb') -Filter mongod.exe -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $executable) { throw 'Install MongoDB Community Server, or use Atlas in backend/.env.' }
$data = Join-Path $projectRoot '.local-data/mongodb'
New-Item -ItemType Directory -Path $data -Force | Out-Null
Write-Host "Starting local-only MongoDB on port $Port. Keep this window open."
& $executable --dbpath $data --bind_ip 127.0.0.1 --port $Port
exit $LASTEXITCODE

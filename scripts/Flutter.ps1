param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$localFlutter = Join-Path $projectRoot '.tools/flutter/bin/flutter.bat'
$flutter = if (Test-Path -LiteralPath $localFlutter) { $localFlutter } else { 'flutter' }
Push-Location $projectRoot
try {
    if (Test-Path -LiteralPath $localFlutter) {
        # Isolate this project's Android setup from global Flutter preferences.
        $env:APPDATA = Join-Path $projectRoot '.tools/flutter-settings'
        $env:PUB_CACHE = Join-Path $projectRoot '.tools/pub-cache'
        # Windows Unix-domain sockets cannot use the sandbox's long temp path.
        $taskTemp = (Join-Path $projectRoot '.tools/tmp').Replace('\', '/')
        New-Item -ItemType Directory -Path $taskTemp -Force | Out-Null
        $env:JAVA_TOOL_OPTIONS = "$env:JAVA_TOOL_OPTIONS `"-Djava.io.tmpdir=$taskTemp`" `"-Djdk.net.unixdomain.tmpdir=$taskTemp`"".Trim()
        New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
        $jdk = Get-ChildItem (Join-Path $projectRoot '.tools/jdk17') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        $configuration = @('config', '--no-enable-windows-desktop', '--no-analytics')
        if ($jdk) {
            $env:JAVA_HOME = $jdk.FullName
            $configuration += "--jdk-dir=$($jdk.FullName)"
        }
        if (-not $env:ANDROID_HOME -and (Test-Path -LiteralPath 'C:/Android/Sdk')) { $env:ANDROID_HOME = 'C:/Android/Sdk' }
        if ($env:ANDROID_HOME) { $configuration += "--android-sdk=$env:ANDROID_HOME" }
        & $flutter @configuration | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not configure the local Flutter toolchain.' }
    }
    & $flutter @FlutterArguments
    exit $LASTEXITCODE
} finally { Pop-Location }

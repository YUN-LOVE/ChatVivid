# Compatibility shim: canonical script moved to platforms/windows/package.ps1.
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path "$PSScriptRoot\..").Path
& "$Root\platforms\windows\package.ps1" @args
exit $LASTEXITCODE

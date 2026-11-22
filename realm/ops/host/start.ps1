# Starts the realm and keeps it up. Run: powershell -ExecutionPolicy Bypass -File start.ps1
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$cur = (Get-Content (Join-Path $root 'current') -TotalCount 1).Trim()
& (Join-Path $root "releases\$cur\realm-ops.exe") run "--root=$root"
exit $LASTEXITCODE

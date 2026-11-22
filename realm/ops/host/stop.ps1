$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$cur = (Get-Content (Join-Path $root 'current') -TotalCount 1).Trim()
& (Join-Path $root "releases\$cur\realm-ops.exe") stop "--root=$root"
exit $LASTEXITCODE

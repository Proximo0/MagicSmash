# Any realm-ops command: .\ops.ps1 status | backup | backups | drill | restore | releases | install DIR | switch V | rollback
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$cur = (Get-Content (Join-Path $root 'current') -TotalCount 1).Trim()
& (Join-Path $root "releases\$cur\realm-ops.exe") @args "--root=$root"
exit $LASTEXITCODE

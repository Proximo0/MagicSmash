# The restore drill (see drill.sh). Schedule weekly with Task Scheduler.
& (Join-Path $PSScriptRoot 'ops.ps1') drill
exit $LASTEXITCODE

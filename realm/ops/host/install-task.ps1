# Makes Windows start the realm at logon (run once, in an elevated PowerShell): the realm then survives a reboot.
# Remove with: Unregister-ScheduledTask -TaskName HordeAndHearthRealm -Confirm:$false
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$root\start.ps1`"" -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'HordeAndHearthRealm' -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Write-Host "HordeAndHearthRealm will start at logon. Start it now with: Start-ScheduledTask -TaskName HordeAndHearthRealm"

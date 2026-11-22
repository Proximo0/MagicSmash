# Sample alarm hook (set alarm_hook in ops.conf to the full path of a copy of this). Args: kind, message.
# Replace the body with a Discord/Slack webhook call or a mail; this one appends to logs\alarms.txt.
param([string]$Kind, [string]$Message)
Add-Content -Path (Join-Path $PSScriptRoot 'logs\alarms.txt') -Value "$(Get-Date -Format o) $Kind $Message"
# Invoke-RestMethod -Method Post -Uri 'https://discord.com/api/webhooks/...' -Body (@{content="realm: $Kind $Message"} | ConvertTo-Json) -ContentType 'application/json'

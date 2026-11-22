#!/bin/sh
# Sample alarm hook (set alarm_hook in ops.conf to the full path of a copy of this). Args: kind, message
# (also in $ALARM_KIND and $ALARM_MSG). Replace the body with a webhook (curl) or mail; this one appends to a file.
echo "$(date -u +%FT%TZ) $ALARM_KIND $ALARM_MSG" >> "$(dirname "$0")/logs/alarms.txt"
# curl -fsS -H 'Content-Type: application/json' -d "{\"content\":\"realm: $ALARM_KIND $ALARM_MSG\"}" https://discord.com/api/webhooks/...

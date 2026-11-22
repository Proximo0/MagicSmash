#!/bin/sh
# The restore drill: the newest backup is restored to a scratch file and verified, the realm keeps running.
# Put it in cron weekly:  0 4 * * 0  /opt/realm/drill.sh >> /opt/realm/logs/drill.log 2>&1
exec "$(dirname "$0")/ops.sh" drill

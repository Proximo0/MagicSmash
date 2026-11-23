#!/usr/bin/env bash
# Linux station launcher, the counterpart of start_station.cmd: runs station.sh --watch idle and starts it again 60 s
# after it exits. One copy only (flock), so cron @reboot plus a hand start cannot double-run.
# Name: $STATION_NAME, else the first line of ~/.station_name. Log: ~/station_restarts.log (rotated to .1 over 20 MB).
# Test knobs: STATION_RESTART_WAIT (seconds, default 60), STATION_LOCK (lock file), STATION_LOG, STATION_JOBS (default idle).
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
cd "$here/../.." || exit 1
if [ -z "${STATION_NAME:-}" ] && [ -s "$HOME/.station_name" ]; then STATION_NAME=$(head -1 "$HOME/.station_name" | tr -d '\r\n'); fi
[ -n "${STATION_NAME:-}" ] && export STATION_NAME
PATH="$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/bin:$PATH"; export PATH  # cron starts with a bare PATH: cargo and godot live here
lock="${STATION_LOCK:-$HOME/.station_start.lock}"
log="${STATION_LOG:-$HOME/station_restarts.log}"
wait_s="${STATION_RESTART_WAIT:-60}"
exec 9>"$lock" || exit 1
flock -n 9 || { echo "start_station: another copy is running (lock $lock)"; exit 1; }
while :; do
	if [ -f "$log" ] && [ "$(stat -c %s "$log" 2>/dev/null || echo 0)" -gt 20971520 ]; then mv -f "$log" "$log.1"; fi
	bash tools/station/station.sh --watch ${STATION_JOBS:-idle} >>"$log" 2>&1 9>&-
	rc=$?
	echo "$(date '+%F %T') station.sh stopped with exit code $rc, restarting in $wait_s s" >>"$log"
	sleep "$wait_s"
done

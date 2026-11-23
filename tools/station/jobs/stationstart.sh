#!/usr/bin/env bash
# A queue `shell` job: the station on this Linux PC comes back after a reboot. Adds one crontab @reboot line of this
# user that runs tools/station/start_station.sh (setsid nohup), and writes ~/.station_name if absent. Does NOT start a
# station now: the one running this job is already up. Windows uses start_station.cmd (SKIP). Safe to re-run.
# Note: an @reboot cron job has no desktop session; the station's `frames` role needs xvfb-run there, which
# station.sh already uses when DISPLAY is empty.
#   queue.sh add kind=shell args="script=stationstart name=<machine>" needs=<machine> priority=9
case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*) echo "SKIP stationstart windows uses start_station.cmd"; exit 0 ;;
esac
command -v crontab >/dev/null 2>&1 || { echo "FAIL stationstart crontab is not installed (apt install cron)"; exit 1; }
launcher=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/start_station.sh
[ -f "$launcher" ] || { echo "FAIL stationstart $launcher is missing"; exit 1; }
name="${STATION_NAME:-${MACHINE:-$(hostname)}}"
for a in "$@"; do case "$a" in name=*) name="${a#name=}"; rm -f "$HOME/.station_name" ;; esac; done  # name=<machine> wins: the name must match roles.txt
if [ -s "$HOME/.station_name" ]; then name=$(head -1 "$HOME/.station_name" | tr -d '\r\n'); else echo "$name" >"$HOME/.station_name" || { echo "FAIL stationstart could not write ~/.station_name"; exit 1; }; fi
line="@reboot setsid nohup bash $launcher >/dev/null 2>&1 &"
cur=$(crontab -l 2>/dev/null)
if ! printf '%s\n' "$cur" | grep -qF "$launcher"; then
	{ [ -n "$cur" ] && printf '%s\n' "$cur"; echo "$line"; } | crontab - || { echo "FAIL stationstart could not write the crontab"; exit 1; }
fi
crontab -l 2>/dev/null | grep -qF "$launcher" || { echo "FAIL stationstart crontab line not present after writing"; exit 1; }
echo "PASS stationstart at_boot=yes launcher=$launcher name=$name"

#!/usr/bin/env bash
# The station watchdog: looks at the two station branches and says what needs attention. It needs no station and no
# person: .github/workflows/station-watch.yml runs it every 30 minutes on GitHub.
#   watch.sh           one ALERT line per problem, then "WATCH ok machines=N" or "WATCH alerts=N"; exit 1 with alerts
#   watch.sh --heal    also releases every claim older than the limit (deletes claims/<id>.<machine> on the queue
#                      branch), so the job is free again for that station's next pick or for another station
# Problems: a station whose <machine>-hours.txt has not been pushed for STATION_WATCH_SILENT_S (default 2 h: a
# running station pushes it about every half hour, also during a long job); a claim older than
# STATION_WATCH_CLAIM_S (default 5 h: no job may run longer than STATION_QUEUE_MAX_S, 4 h).
# Machines come from tools/station/roles.txt. STATION_WATCH_NOW=<epoch> replaces the clock (tests).
set -u
cd "$(dirname "$0")/../.."
MACHINE=watch
. tools/station/queue_lib.sh
heal=0; [ "${1:-}" = "--heal" ] && heal=1
now="${STATION_WATCH_NOW:-$(date +%s)}"
silent="${STATION_WATCH_SILENT_S:-7200}"
old="${STATION_WATCH_CLAIM_S:-18000}"
alerts=0
alert() { echo "ALERT $1"; alerts=$((alerts + 1)); }
age() { local s=$1; printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60)); }

gb_fetch "$BRANCH" || alert "the results branch $BRANCH cannot be fetched"
gb_fetch "$QBRANCH" || alert "the queue branch $QBRANCH cannot be fetched"

machines=$(sed -n 's/^\([A-Za-z0-9_-]\{1,\}\):.*/\1/p' tools/station/roles.txt)
n=0
for m in $machines; do
  n=$((n + 1))
  t=$(git log -1 --format=%ct "refs/remotes/origin/$BRANCH" -- "$m-hours.txt" 2>/dev/null)
  if [ -z "$t" ]; then alert "$m has never reported its hours"
  elif [ $((now - t)) -gt "$silent" ]; then alert "$m has been silent for $(age $((now - t))): is the PC on, signed in, and its station window running?"; fi
done

ops=()
while read -r path; do
  [ -n "$path" ] || continue
  t=$(gb_cat "$QBRANCH" "$path" | q_time_of)
  [ -n "$t" ] || continue
  if [ $((now - t)) -gt "$old" ]; then
    name=${path#claims/}; id=${name%%.*}; m=${name#*.}
    job=$(gb_cat "$QBRANCH" "queue/$id.job")
    what="$(q_get "$job" kind) $(q_get "$job" args)"
    if [ "$heal" = 1 ]; then alert "$m held job $id ($what) for $(age $((now - t))): released"; ops+=("-$path")
    else alert "$m has held job $id ($what) for $(age $((now - t)))"; fi
  fi
done < <(git ls-tree -r --name-only "refs/remotes/origin/$QBRANCH" claims/ 2>/dev/null)
if [ ${#ops[@]} -gt 0 ]; then
  gb_put "$QBRANCH" "watch: release ${#ops[@]} stale claim(s)" "${ops[@]}" || alert "could not release the stale claims (the push was rejected; the next run tries again)"
fi

if [ "$alerts" = 0 ]; then echo "WATCH ok machines=$n"; else echo "WATCH alerts=$alerts"; exit 1; fi

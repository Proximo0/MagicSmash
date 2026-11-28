#!/usr/bin/env bash
# The station watchdog: looks at the two station branches and says what needs attention. It needs no station and no
# person: .github/workflows/station-watch.yml runs it every 30 minutes on GitHub.
#   watch.sh           one ALERT line per problem, then "WATCH ok machines=N" or "WATCH alerts=N"; exit 1 with alerts
#   watch.sh --heal    also releases every claim older than the limit (deletes claims/<id>.<machine> on the queue
#                      branch), so the job is free again for that station's next pick or for another station
# Problems: a station whose <machine>-heartbeat.txt (or -hours.txt) has not been pushed for STATION_WATCH_SILENT_S (default 2 h: a
# running station pushes it about every half hour, also during a long job); a claim older than
# STATION_WATCH_CLAIM_S (default 5 h: no job may run longer than STATION_QUEUE_MAX_S, 4 h); a station that reports
# its hours but has published no result of any kind for STATION_WATCH_IDLE_S (default 5 h) and holds no job.
# a machine whose last 6 queue result lines (work/*/<machine>.txt) are all FAIL.
# Machines come from tools/station/roles.txt. STATION_WATCH_NOW=<epoch> replaces the clock (tests).
set -u
cd "$(dirname "$0")/../.."
MACHINE=watch
. tools/station/queue_lib.sh
heal=0; [ "${1:-}" = "--heal" ] && heal=1
now="${STATION_WATCH_NOW:-$(date +%s)}"
silent="${STATION_WATCH_SILENT_S:-7200}"
old="${STATION_WATCH_CLAIM_S:-18000}"
idle="${STATION_WATCH_IDLE_S:-18000}"
alerts=0
alert() { echo "ALERT $1"; alerts=$((alerts + 1)); }
age() { local s=$1; printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60)); }

gb_fetch "$BRANCH" || alert "the results branch $BRANCH cannot be fetched"
gb_fetch "$QBRANCH" || alert "the queue branch $QBRANCH cannot be fetched"

machines=$(sed -n 's/^\([A-Za-z0-9_-]\{1,\}\):.*/\1/p' tools/station/roles.txt | grep -vx -e lanes -e stopped -e simscale)   # "lanes:", "stopped:" and "simscale:" lines are not machines
# Machines the owner stopped (roles.txt "stopped: <machine> ..." or "stopped: all"): silence there is wanted, nothing is checked.
stopped=" $(grep -i '^stopped:' tools/station/roles.txt | tr -d '\r' | cut -d: -f2- | tr ',A-Z\n' ' a-z ') "
n=0
for m in $machines; do
  case "$stopped" in *" all "*|*" $(printf %s "$m" | tr 'A-Z' 'a-z') "*) continue ;; esac
  n=$((n + 1))
  # Alive = its newest heartbeat or hours push (the hours file changes only when a job ends: a PC two hours into a
  # soak was reported silent while its heartbeat was 20 minutes old).
  t=$(git log -1 --format=%ct "refs/remotes/origin/$BRANCH" -- "$m-heartbeat.txt" "$m-hours.txt" 2>/dev/null)
  if [ -z "$t" ]; then alert "$m has never reported a heartbeat"
  elif [ $((now - t)) -gt "$silent" ]; then alert "$m has been silent for $(age $((now - t))): is the PC on, signed in, and its station window running?"; fi
  # Low disk: the heartbeat line carries disk_free_gb=<n> (an older heartbeat has none and never alerts).
  gb=$(gb_cat "$BRANCH" "$m-heartbeat.txt" | tail -1 | sed -n 's/.*disk_free_gb=\([0-9]\{1,\}\).*/\1/p')
  [ -z "$gb" ] || [ "$gb" -ge "${STATION_WATCH_DISK_GB:-10}" ] || alert "$m: only $gb GB free disk"
  # On, but doing nothing: no result line of any kind from it for a while, and it holds no job now.
  w=$(git log -1 --format=%ct "refs/remotes/origin/$BRANCH" -- "$m.txt" "$m-deep.txt" ":(glob)work/*/$m.txt" 2>/dev/null)
  if [ -n "$t" ] && [ $((now - t)) -le "$silent" ] && [ $((now - ${w:-0})) -gt "$idle" ] \
    && ! git ls-tree -r --name-only "refs/remotes/origin/$QBRANCH" claims/ 2>/dev/null | grep -q "\.$m\$"; then
    alert "$m is on but has finished no job for $(age $((now - ${w:-0}))) and holds none: its station may be stuck between jobs"
  fi
  # Every one of its last 6 queue results FAIL: a broken job spinning (the commit adds one result line each).
  last6=$(git log -6 --format=%x01 -p -U0 "refs/remotes/origin/$BRANCH" -- ":(glob)work/*/$m.txt" 2>/dev/null | sed -n -E 's/^\+[0-9T:Z-]+ (PASS|FAIL|INFO|SKIP) .*/\1/p')
  if [ "$(grep -c . <<<"$last6")" -ge 6 ] && [ "$(head -6 <<<"$last6" | grep -vc '^FAIL$')" = 0 ]; then
    alert "$m: its last 6 queue results are all FAIL: a job may be failing in a loop"
  fi
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

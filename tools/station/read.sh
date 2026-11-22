#!/usr/bin/env bash
# Read every station's latest report (a few lines each). A machine with heartbeats is STALE after STATION_HEARTBEAT_STALE_HOURS (default 2) of silence; else a report older than STATION_STALE_HOURS (default 6) is STALE.
# Usage: tools/station/read.sh    Ends with: STATIONS n=<machines> failed=<n> stale=<n>
set -uo pipefail
cd "$(dirname "$0")/../.."
git fetch -q origin "+refs/heads/station-results:refs/remotes/origin/station-results" 2>/dev/null \
  || { echo "STATIONS n=0 failed=0 stale=0 (no station has reported yet)"; exit 0; }
n=0; failed=0; stale=0; now=$(date -u +%s); limit=$(( ${STATION_STALE_HOURS:-6} * 3600 ))
while IFS= read -r f; do
  n=$((n + 1)); text=$(git show "origin/station-results:$f")
  when=$(sed -nE '1s/.* time=([^ ]+).*/\1/p' <<<"$text")
  age=$(( now - $(date -u -d "${when/T/ }" +%s 2>/dev/null || echo 0) ))
  m=${f%.txt}; m=${m%-deep}
  hb=$(git show "origin/station-results:$m-heartbeat.txt" 2>/dev/null | sed -nE '1s/.* time=([^ ]+).*/\1/p')
  if [ -n "$hb" ]; then  # heartbeats exist: stale means the machine is silent for 2 hours
    hage=$(( now - $(date -u -d "${hb/T/ }" +%s 2>/dev/null || echo 0) ))
    (( hage > ${STATION_HEARTBEAT_STALE_HOURS:-2} * 3600 )) && { stale=$((stale + 1)); echo "STALE $m: last heartbeat $hb"; }
  elif (( age > limit )); then stale=$((stale + 1)); echo "STALE ${f%.txt}: last report $when"; fi
  grep -qE '^STATION (FAIL|HELD)' <<<"$text" && failed=$((failed + 1))
  echo "$text"
done < <(git ls-tree --name-only origin/station-results | grep '\.txt$' | grep -v -e '-heartbeat\.txt$' -e '-failures\.txt$')
echo "STATIONS n=$n failed=$failed stale=$stale"
(( failed + stale == 0 ))

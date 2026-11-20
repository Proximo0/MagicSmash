#!/usr/bin/env bash
# Read every station's latest report (a few lines each). A report older than STATION_STALE_HOURS (default 36) is STALE.
# Usage: tools/station/read.sh    Ends with: STATIONS n=<machines> failed=<n> stale=<n>
set -uo pipefail
cd "$(dirname "$0")/../.."
git fetch -q origin "+refs/heads/station-results:refs/remotes/origin/station-results" 2>/dev/null \
  || { echo "STATIONS n=0 failed=0 stale=0 (no station has reported yet)"; exit 0; }
n=0; failed=0; stale=0; now=$(date -u +%s); limit=$(( ${STATION_STALE_HOURS:-36} * 3600 ))
while IFS= read -r f; do
  n=$((n + 1)); text=$(git show "origin/station-results:$f")
  when=$(sed -nE '1s/.* time=([^ ]+).*/\1/p' <<<"$text")
  age=$(( now - $(date -u -d "${when/T/ }" +%s 2>/dev/null || echo 0) ))
  if (( age > limit )); then stale=$((stale + 1)); echo "STALE ${f%.txt}: last report $when"; fi
  grep -qE '^STATION (FAIL|HELD)' <<<"$text" && failed=$((failed + 1))
  echo "$text"
done < <(git ls-tree --name-only origin/station-results | grep '\.txt$')
echo "STATIONS n=$n failed=$failed stale=$stale"
(( failed + stale == 0 ))

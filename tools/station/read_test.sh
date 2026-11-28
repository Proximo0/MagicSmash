#!/usr/bin/env bash
# Test of the lead's reader (tools/station/read.sh): what counts as a report and what counts as stale. (28 Nov 2026:
# every <machine>-hours.txt was read as a report with no time, `date -d ""` is today's midnight, so four healthy PCs
# read as STALE from 06:00 UTC to midnight, every day.) A bare repository stands in for GitHub, its branch
# station-results holds the files a station pushes, and a clone holds the reader.
# Prints READ ok when everything held. Fast (a second): CI's `tools` row runs it.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export TMPDIR="$T" GIT_TERMINAL_PROMPT=0
fails=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; sed 's/^/         | /' "$T/out"; fails=$((fails + 1)); fi; }
ago() { date -u -d "$1" +%Y-%m-%dT%H:%MZ; }
push() { ( cd "$T/pc" && git add -A && git -c user.name=t -c user.email=t@t commit -qm "$1" && git -c push.negotiate=false push -q origin HEAD:station-results ); }
reader() { bash "$T/lead/tools/station/read.sh" >"$T/out" 2>&1; }

git init -q --bare -b main "$T/origin.git"
mkdir -p "$T/lead/tools/station" && cp "$REPO/tools/station/read.sh" "$T/lead/tools/station/"
( cd "$T/lead" && git init -q -b main && git remote add origin "$T/origin.git" && git add -A && git -c user.name=t -c user.email=t@t commit -qm seed && git -c push.negotiate=false push -q origin HEAD:main )

reader
check "no station has reported yet: nothing is stale" 'grep -q "^STATIONS n=0 failed=0 stale=0" "$T/out"'

# One healthy machine with everything a station pushes: a report, a deep report, a heartbeat, its failures, its hours.
mkdir -p "$T/pc" && ( cd "$T/pc" && git init -q -b station-results && git remote add origin "$T/origin.git" )
printf 'STATION machine=alpha time=%s commit=abc1234 took=60s\nJOB checks PASS\nSTATION PASS jobs=1 failed=0 skipped=0\n' "$(ago '5 minutes ago')" >"$T/pc/alpha.txt"
printf 'STATION machine=alpha time=%s commit=abc1234 took=60s\nSTATION PASS deep pass\n' "$(ago '9 hours ago')" >"$T/pc/alpha-deep.txt"
printf 'HEARTBEAT machine=alpha time=%s lanes_busy=1/4\n' "$(ago '10 minutes ago')" >"$T/pc/alpha-heartbeat.txt"
printf '%s alpha queue FAIL id=1 kind=shell an old failure\n' "$(ago '3 days ago')" >"$T/pc/alpha-failures.txt"
printf '%s busy_h=20.00 idle_h=0.10 lane_h=40.00 lanes=4\n' "$(date -u -d yesterday +%F)" >"$T/pc/alpha-hours.txt"
push alpha
reader; rc=$?
check "a machine's hours, failures and heartbeat files are not reports" 'grep -q "^STATIONS n=2 failed=0 stale=0" "$T/out" && [ "$rc" = 0 ] && ! grep -q -e "busy_h=" -e "an old failure" -e "^HEARTBEAT" "$T/out"'
check "a machine with a fresh heartbeat is not stale, however old its deep report is" '! grep -q "^STALE" "$T/out"'

# A machine that pushes heartbeats and went silent; one that never pushed a heartbeat and reported long ago.
printf 'STATION machine=quiet time=%s commit=abc1234 took=60s\nSTATION PASS jobs=1 failed=0 skipped=0\n' "$(ago '30 minutes ago')" >"$T/pc/quiet.txt"
printf 'HEARTBEAT machine=quiet time=%s lanes_busy=0/4\n' "$(ago '3 hours ago')" >"$T/pc/quiet-heartbeat.txt"
printf 'STATION machine=old time=%s commit=abc1234 took=60s\nSTATION PASS jobs=1 failed=0 skipped=0\n' "$(ago '7 hours ago')" >"$T/pc/old.txt"
push silent
reader; rc=$?
check "silent for more than two hours of heartbeats: stale" 'grep -q "^STALE quiet: last heartbeat " "$T/out"'
check "no heartbeats and a report older than six hours: stale" 'grep -q "^STALE old: last report " "$T/out"'
check "two stale machines fail the read" 'grep -q "^STATIONS n=4 failed=0 stale=2" "$T/out" && [ "$rc" != 0 ]'

# A report whose first line has no time is stale at every hour of the day, and says why.
( cd "$T/pc" && git rm -q quiet.txt quiet-heartbeat.txt old.txt ) && printf 'STATION machine=blank commit=abc1234\nSTATION PASS jobs=1 failed=0 skipped=0\n' >"$T/pc/blank.txt"
push blank
reader
check "a report with no time is stale and says so" 'grep -q "^STALE blank: last report has no time in its first line" "$T/out" && grep -q "^STATIONS n=3 failed=0 stale=1" "$T/out"'

# A failed and a held station are counted.
( cd "$T/pc" && git rm -q blank.txt ) && printf 'STATION machine=alpha time=%s commit=abc1234 took=60s\nJOB checks FAIL unit\nSTATION FAIL jobs=1 failed=1 skipped=0\n' "$(ago '5 minutes ago')" >"$T/pc/alpha.txt"
push fail
reader; rc=$?
check "a failed report is counted and fails the read" 'grep -q "^STATIONS n=2 failed=1 stale=0" "$T/out" && [ "$rc" != 0 ] && grep -q "^JOB checks FAIL unit" "$T/out"'

if [ "$fails" = 0 ]; then echo "READ ok"; else echo "READ FAIL problems=$fails"; exit 1; fi

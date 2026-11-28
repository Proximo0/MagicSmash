#!/usr/bin/env bash
# Test of the station's skip rule: a job that failed its last run on this station is run again on the next commit, whatever
# that commit changed. (28 Nov 2026: a PC whose `checks` failed said STATION PASS one docs-only merge later, because the
# job was skipped as "nothing it tests changed".) A bare repository stands in for GitHub, one clone is the station, and
# the job is the `world` stub (tools/station/jobs/worldlong.sh), which a commit here swaps for one that fails.
# Prints SKIPRULE ok when everything held. Fast (a few seconds): CI's `tools` row runs it.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export STATION_QUEUE_STUB=1 TMPDIR="$T" GIT_TERMINAL_PROMPT=0
fails=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; sed 's/^/         | /' "$T/out"; fails=$((fails + 1)); fi; }
commit() { ( cd "$T/seed" && git add -A && git -c user.name=t -c user.email=t@t commit -qm "$1" && git -c push.negotiate=false push -q origin HEAD:main ); }
station() { ( cd "$T/pc" && STATION_NAME=pc bash tools/station/station.sh --no-push world >"$T/out" 2>&1 ); }
short() { git -C "$T/seed" rev-parse --short=7 HEAD; }

git init -q --bare -b main "$T/origin.git"
mkdir -p "$T/seed/tools/station/jobs" "$T/seed/realm" "$T/seed/docs"
cp "$REPO"/tools/station/{queue_lib.sh,queue.sh,station.sh,roles.txt} "$T/seed/tools/station/"
cp "$REPO"/tools/station/jobs/*.sh "$T/seed/tools/station/jobs/"
( cd "$T/seed" && git init -q -b main && git remote add origin "$T/origin.git" ); commit seed
git clone -q "$T/origin.git" "$T/pc"

station
check "the first commit a station sees is tested" 'grep -q "^JOB world PASS" "$T/out" && grep -q "^STATION PASS jobs=1 failed=0 skipped=0" "$T/out"'

echo 1 >"$T/seed/docs/notes.md"; commit docs
station
check "a commit that changed nothing the job tests is skipped while the job's last run passed" 'grep -q "^JOB world SKIP nothing it tests changed" "$T/out" && grep -q "^STATION PASS jobs=0 failed=0 skipped=1" "$T/out"'

echo 1 >"$T/seed/realm/one"; printf '#!/usr/bin/env bash\necho "FAIL world stub broke"; exit 1\n' >"$T/seed/tools/station/jobs/worldlong.sh"; commit break
station
check "a commit that breaks the job fails the station" 'grep -q "^JOB world FAIL world stub broke" "$T/out" && grep -q "^STATION FAIL jobs=1 failed=1 skipped=0" "$T/out"'

echo 2 >"$T/seed/docs/notes.md"; commit docs-again; broke=$(short)
station
check "the next commit changed only documents: the failed job runs again and the station still says FAIL" 'grep -q "commit=$broke " "$T/out" && grep -q "^JOB world FAIL world stub broke" "$T/out" && grep -q "^STATION FAIL jobs=1 failed=1 skipped=0" "$T/out" && ! grep -q "SKIP" "$T/out"'

# The cure is a path the job's skip rule does not count (tools/station/, as a roles.txt limit would be): it is still tested.
cp "$REPO/tools/station/jobs/worldlong.sh" "$T/seed/tools/station/jobs/worldlong.sh"; commit cure
station
check "a cure under tools/station/ is tested: the job runs and passes" 'grep -q "^JOB world PASS" "$T/out" && grep -q "^STATION PASS jobs=1 failed=0 skipped=0" "$T/out"'

echo 3 >"$T/seed/docs/notes.md"; commit docs-last
station
check "once it has passed, the job is skipped again when nothing it tests changed" 'grep -q "^JOB world SKIP nothing it tests changed" "$T/out" && grep -q "^STATION PASS jobs=0 failed=0 skipped=1" "$T/out"'

# A report always names the newest commit the station tested, also when its lines are the same as the last report's.
# (28 Nov 2026: a station that passed two merges in a row published only the first, so its file could not tell "passed the
# new commit" from "has not run it yet".)
pushing() { ( cd "$T/pc" && STATION_PUBLISH_SLEEP=0 STATION_NAME=pc bash tools/station/station.sh world >"$T/out" 2>&1 ); }
published() { git -C "$T/pc" fetch -q origin "+refs/heads/station-results:refs/remotes/origin/station-results" 2>/dev/null; git -C "$T/pc" show "refs/remotes/origin/station-results:pc.txt" 2>/dev/null; }
echo 2 >"$T/seed/realm/two"; commit realm-two; two=$(short)
pushing; published >"$T/out"
check "a pass is published with its commit" 'grep -q "commit=$two " "$T/out" && grep -q "^STATION PASS jobs=1 failed=0 skipped=0" "$T/out"'
echo 3 >"$T/seed/realm/three"; commit realm-three; three=$(short)
pushing; published >"$T/out"
check "the next commit passes with the same lines: its report is published too and names the new commit" 'grep -q "commit=$three " "$T/out" && grep -q "^STATION PASS jobs=1 failed=0 skipped=0" "$T/out"'

if [ $fails = 0 ]; then echo "SKIPRULE ok"; else echo "SKIPRULE FAILED $fails"; exit 1; fi

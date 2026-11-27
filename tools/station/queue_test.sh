#!/usr/bin/env bash
# Tests of the station work queue with no heavy command: a bare repository stands in for GitHub, two clones are two
# machines (alpha, beta), STATION_QUEUE_STUB=1 replaces every real job. Prints QUEUE ok when everything held.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export STATION_QUEUE_FAIL_SLEEP=0 STATION_QUEUE_STUB=1 STATION_QUEUE_RETRY_SLEEP=1 TMPDIR="$T" GIT_TERMINAL_PROMPT=0 STATION_FREE_MB=100000   # the RAM gate sees plenty unless a test says otherwise
fails=0
ok() { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1 ($2)"; fi; }

git init -q --bare -b main "$T/origin.git"
git init -q --bare -b main "$T/other.git"   # a second bare repository: a station whose origin is a different one sees nothing of this queue
mkdir -p "$T/seed/tools/station/jobs"; cp "$REPO"/tools/station/{queue_lib.sh,queue.sh,station.sh,roles.txt} "$T/seed/tools/station/"; cp "$REPO"/tools/station/jobs/*.sh "$T/seed/tools/station/jobs/"
printf 'alpha: idle queue deep\nbeta: idle queue deep\n' >"$T/seed/tools/station/roles.txt"
( cd "$T/seed" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm seed && git remote add origin "$T/origin.git" && git push -q origin main )
for m in alpha beta; do git clone -q "$T/origin.git" "$T/$m"; done

Q() { local m=$1; shift; ( cd "$T/$m" && STATION_NAME=$m bash tools/station/queue.sh "$@" ); }       # queue.sh as machine m
rd() { git -C "$T/alpha" fetch -q origin "+refs/heads/$1:refs/remotes/origin/$1" 2>/dev/null; git -C "$T/alpha" show "refs/remotes/origin/$1:$2" 2>/dev/null; }
files() { git -C "$T/alpha" fetch -q origin "+refs/heads/$1:refs/remotes/origin/$1" 2>/dev/null; git -C "$T/alpha" ls-tree -r --name-only "refs/remotes/origin/$1" 2>/dev/null; }

echo "== empty queue falls back to deep"
Q alpha step >"$T/o" 2>&1; rc=$?
check "step on a missing queue branch returns 1 (station then runs deep)" '[ $rc = 1 ]'
id0=$(Q alpha add kind=fuzz args="seeds=1-2 ops=1000" needs=alpha priority=1 | tail -1)
check "add prints an id and creates queue/<id>.job" 'files station-queue | grep -qx "queue/$id0.job"'
check "job file holds the keys" 'rd station-queue queue/$id0.job | grep -q "^kind=fuzz" && rd station-queue queue/$id0.job | grep -q "^timeout_s=3600" && rd station-queue queue/$id0.job | grep -q "^added="'
Q beta step >"$T/o" 2>&1; rc=$?
check "a job for another machine is not taken (needs=alpha): beta gets nothing, rc=1" '[ $rc = 1 ]'
Q alpha step >"$T/o" 2>&1; rc=$?
check "alpha runs it, rc=0" '[ $rc = 0 ]'
check "result line on the results branch" 'rd station-results work/$id0/alpha.txt | grep -q " PASS id=$id0 kind=fuzz .*seeds_run=2"'
check "done record on the queue branch and the claim is gone" 'files station-queue | grep -qx "done/$id0.alpha" && ! files station-queue | grep -q "^claims/$id0"'
Q alpha step >"$T/o" 2>&1; rc=$?
check "a finished once-job is not run again, queue empty gives rc=1" '[ $rc = 1 ]'

echo "== arg validation"
Q alpha add kind=fuzz 'args=$(rm -rf x)' >"$T/o" 2>&1; rc=$?
check "add refuses args=\$(rm -rf x)" '[ $rc != 0 ] && grep -q refused "$T/o"'
Q alpha add kind=fuzz 'args=seeds=1;ls' >"$T/o" 2>&1; check "add refuses a semicolon" '[ $? != 0 ]'
Q alpha add kind=rm args=x >"$T/o" 2>&1; check "add refuses an unknown kind" '[ $? != 0 ]'
# a hostile file pushed straight to the branch is refused at run time, never executed
mkdir -p "$T/evil" && printf 'kind=fuzz\nargs=$(touch %s/PWNED)\nneeds=any\npriority=9\nrepeat=once\ntimeout_s=600\nadded=x\n' "$T" >"$T/evil/j"
( cd "$T/alpha" && . tools/station/queue_lib.sh && MACHINE=alpha gb_put station-queue "hostile" "+queue/evil-1.job:$T/evil/j" )
printf 'kind=wat\nargs=1\nneeds=any\npriority=9\nrepeat=once\ntimeout_s=600\nadded=x\n' >"$T/evil/k"
( cd "$T/alpha" && . tools/station/queue_lib.sh && MACHINE=alpha gb_put station-queue "unknown" "+queue/evil-2.job:$T/evil/k" )
Q beta step >"$T/o" 2>&1; rc=$?
check "hostile and unknown jobs are skipped with a line, nothing runs" '[ $rc = 1 ] && [ ! -e "$T/PWNED" ] && grep -q "evil-1: refused" "$T/o" && grep -q "evil-2: refused: unknown kind" "$T/o"'
Q alpha cancel evil-1 >/dev/null; Q alpha cancel evil-2 >/dev/null

echo "== two machines race for one job"
idr=$(Q alpha add kind=soak args="secs=5 seeds=7" priority=9 | tail -1)
( Q alpha step >"$T/ra" 2>&1; echo $? >"$T/ra.rc" ) & ( Q beta step >"$T/rb" 2>&1; echo $? >"$T/rb.rc" ) & wait
wins=0; [ "$(cat "$T/ra.rc")" = 0 ] && wins=$((wins + 1)); [ "$(cat "$T/rb.rc")" = 0 ] && wins=$((wins + 1))
check "exactly one of two parallel stations ran it" '[ $wins = 1 ]'
check "one result file, one done record" '[ "$(files station-results | grep -c "^work/$idr/[a-z]*\.txt$")" = 1 ] && [ "$(files station-queue | grep -c "^done/$idr\.")" = 1 ]'
# deterministic race: beta fetched, alpha claims in between, beta's push is rejected
idc=$(Q alpha add kind=soak args="secs=5" priority=9 | tail -1)
( cd "$T/beta" && . tools/station/queue_lib.sh && MACHINE=beta
  gb_hook() { unset -f gb_hook; ( cd "$T/alpha" && . tools/station/queue_lib.sh && MACHINE=alpha && q_fetch && q_claim "$idc" ) ; }
  q_claim "$idc" ) ; rc=$?
check "a claim whose push is rejected loses (rc=1) and only alpha holds the claim" '[ $rc = 1 ] && [ "$(files station-queue | grep -c "^claims/$idc\.")" = 1 ] && files station-queue | grep -qx "claims/$idc.alpha-0"'
Q beta step >"$T/o" 2>&1; rc=$?
check "beta sees the live claim and takes nothing" '[ $rc = 1 ]'

echo "== stale claim takeover"
# alpha's claim is 3 hours old, timeout_s=60 so stale after 2 minutes
cat >"$T/stale" <<EOF
machine=alpha time=$(( $(date +%s) - 10800 ))
EOF
ids=$(Q alpha add kind=fuzz args="seeds=5" timeout_s=60 priority=9 | tail -1)
( cd "$T/alpha" && . tools/station/queue_lib.sh && MACHINE=alpha gb_put station-queue "old claim" "+claims/$ids.alpha:$T/stale" "-claims/$idc.alpha" "+done/$idc.alpha:$T/stale" )
Q beta step >"$T/o" 2>&1; rc=$?
check "beta takes over the stale claim and finishes the job" '[ $rc = 0 ] && files station-queue | grep -qx "done/$ids.beta" && ! files station-queue | grep -q "^claims/$ids\."'
check "its result is on the results branch" 'rd station-results work/$ids/beta.txt | grep -q " PASS id=$ids kind=fuzz"'

echo "== a forever job runs twice with different seeds; every_s and priority order"
idf=$(Q alpha add kind=fuzz args="seeds=1000-9999999 ops=500" needs=alpha repeat=forever priority=2 | tail -1)
Q alpha step >"$T/o" 2>&1; Q alpha step >>"$T/o" 2>&1
lines=$(rd station-results work/$idf/alpha.txt | grep -c " PASS id=$idf ")
seeds=$(rd station-results work/$idf/alpha.txt | grep -o 'seeds_run=[0-9]*' | wc -l)
check "two passes, two lines in one result file" '[ "$lines" = 2 ]'
# the stub does not print the seed; the seed is chosen by q_seeds: prove it differs between passes
s1=$(cd "$T/alpha" && . tools/station/queue_lib.sh && q_seeds 1000-9999999 forever); s2=$(cd "$T/alpha" && . tools/station/queue_lib.sh && q_seeds 1000-9999999 forever)
check "a forever job draws a fresh seed each pass" '[ "$s1" != "$s2" ] && [ "$s1" -ge 1000 ]'
check "a forever job is never exhausted: its done record counts passes=2" 'rd station-queue done/$idf.alpha | grep -q "passes=2"'
ide=$(Q alpha add kind=bench args="fields=0,1 threads=1 monsters=100" needs=alpha repeat=forever every_s=99999 priority=9 | tail -1)
Q alpha step >"$T/o" 2>&1; Q alpha step >>"$T/o" 2>&1
check "every_s keeps a job off for a day; the other forever job still gets turns" 'rd station-results work/$ide/alpha.txt | grep -c " PASS " | grep -qx 1 && [ "$(rd station-results work/$idf/alpha.txt | grep -c PASS)" -ge 3 ]'
check "bench writes a CSV artifact" 'files station-results | grep -q "^work/$ide/art/alpha-bench.csv$"'
Q alpha cancel "$idf" >/dev/null; Q alpha cancel "$ide" >/dev/null

echo "== a failing job, the shell kind, list, digest"
idx=$(Q alpha add kind=fuzz args="seeds=666" needs=alpha priority=9 | tail -1)
Q alpha step >"$T/o" 2>&1
check "seed 666 FAILs in the stub and the line names the seed" 'rd station-results work/$idx/alpha.txt | grep -q " FAIL id=$idx .*seed=666 FAILED"'
idsh=$(Q alpha add kind=shell args="script=selftest hello" needs=alpha | tail -1)
Q alpha step >"$T/o" 2>&1
check "a shell job runs tools/station/jobs/selftest.sh" 'rd station-results work/$idsh/alpha.txt | grep -q " INFO id=$idsh kind=shell .*selftest ok .*words=hello"'
Q alpha add kind=shell args="script=nope" needs=alpha >/dev/null
Q alpha step >"$T/o" 2>&1; check "a shell job without its script file is skipped with a line" 'grep -q "no script" "$T/o"'
Q alpha list >"$T/o" 2>&1; check "list shows states and ends with QUEUE jobs=" 'grep -q "^QUEUE jobs=" "$T/o" && grep -q "done" "$T/o"'
# station hours: one line a day on the results branch
( cd "$T/alpha" && . tools/station/queue_lib.sh && MACHINE=alpha && hours_init && sleep 2 && hours_mark busy && hours_mark idle && hours_flush )
check "hours file has a line for today" 'rd station-results alpha-hours.txt | grep -q "^$(date -u +%F) busy_h=[0-9.]* idle_h=[0-9.]* lane_h=[0-9.]* lanes=[0-9]*$"'
Q alpha digest --since=2 >"$T/o" 2>&1
check "digest has per-machine jobs, hours, the FAIL with its seed, and a summary line" 'grep -q "jobs=" "$T/o" && grep -q "alpha " "$T/o" && grep -q "seed=666" "$T/o" && grep -q "^DIGEST jobs=[0-9]* fail=[1-9]" "$T/o" && grep -q "busy=" "$T/o"'
Q alpha fill-week >"$T/o" 2>&1; n1=$(grep -c '^added' "$T/o"); Q alpha fill-week >"$T/o" 2>&1; n2=$(grep -c '^added' "$T/o")
check "fill-week loads jobs for both machines and is idempotent" '[ "$n1" -ge 12 ] && [ "$n2" = 0 ]'
fz=$(files station-queue | grep '^queue/' | while read -r f; do rd station-queue "$f" | grep -q "^kind=fuzz" && rd station-queue "$f" | grep -q "^needs=alpha" && echo "$f"; done | tail -1)
check "fill-week gives the seeded forever kinds several lanes and the agreed priority (fuzz: 4 lanes, priority 4)" 'rd station-queue "$fz" | grep -qx "max_lanes=4" && rd station-queue "$fz" | grep -qx "priority=4"'

echo "== the world soak: short on a merge, long from the queue; wirefuzz is a queue job"
git clone -q "$T/origin.git" "$T/gamma"
( cd "$T/gamma" && STATION_NAME=gamma bash tools/station/station.sh --no-push world >"$T/w1" 2>&1 )
check "a merge's world job runs 600 s by default" 'grep -q "^JOB world PASS world stub secs=600" "$T/w1"'
( cd "$T/gamma" && rm -f "$(git rev-parse --git-dir)/station_last" && STATION_WORLD_SECS=33 STATION_NAME=gamma bash tools/station/station.sh --no-push world >"$T/w2" 2>&1 )
check "STATION_WORLD_SECS still sets it" 'grep -q "^JOB world PASS world stub secs=33" "$T/w2"'
check "worldlong.sh defaults to 7200 s and takes secs=" '[ "$(bash "$REPO/tools/station/jobs/worldlong.sh")" = "PASS world stub secs=7200" ] && [ "$(bash "$REPO/tools/station/jobs/worldlong.sh" secs=90)" = "PASS world stub secs=90" ]'
idw2=$(Q alpha add kind=shell args="script=worldlong secs=7200" needs=alpha timeout_s=9000 | tail -1)
Q alpha step >"$T/o" 2>&1
check "the queue runs the long world soak as a shell job" 'rd station-results work/$idw2/alpha.txt | grep -q " PASS id=$idw2 kind=shell .*world stub secs=7200"'
idz=$(Q alpha add kind=shell args="script=wirefuzz iters=2000000" repeat=forever every_s=3600 | tail -1)
check "wirefuzz queues forever and its script exists" '[ -n "$idz" ] && [ -x "$REPO/tools/station/jobs/wirefuzz.sh" ] && files station-queue | grep -qx "queue/$idz.job"'
Q alpha cancel "$idz" >/dev/null
# the newest main only: two commits land while a station is busy, one run covers both
( cd "$T/seed" && echo a >realm_a.txt && mkdir -p realm && echo 1 >realm/one && git add -A && git -c user.name=t -c user.email=t@t commit -qm one && echo 2 >realm/two && git add -A && git -c user.name=t -c user.email=t@t commit -qm two && git push -q origin HEAD:main )
( cd "$T/gamma" && STATION_NAME=gamma bash tools/station/station.sh --no-push world >"$T/w3" 2>&1 )
check "two merges that landed while busy are tested once, at the newest main" '[ "$(grep -c "^STATION machine=" "$T/w3")" = 1 ] && grep -q "commit=$(git -C "$T/seed" rev-parse --short=7 HEAD) " "$T/w3"'

echo "== a failed push keeps the finished report: the jobs are not run again, only the push is retried"
( cd "$T/seed" && echo 3 >realm/three && git add -A && git -c user.name=t -c user.email=t@t commit -qm three && git push -q origin HEAD:main )
gd=$(git -C "$T/gamma" rev-parse --absolute-git-dir); head3=$(git -C "$T/seed" rev-parse HEAD)
( cd "$T/gamma" && git config remote.origin.pushurl "$T/nowhere.git" && STATION_PUBLISH_SLEEP=0 STATION_NAME=gamma bash tools/station/station.sh world >"$T/p1" 2>&1 )
check "push failed: the commit is marked tested and the report is kept" '[ "$(cat "$gd/station_last")" = "$head3" ] && [ -s "$gd/station_last.unpushed" ] && grep -q "report kept" "$T/p1" && ! rd station-results gamma.txt | grep -q "commit=${head3:0:7} "'
( cd "$T/gamma" && git config --unset remote.origin.pushurl && STATION_POLL=1 STATION_NAME=gamma timeout 12 bash tools/station/station.sh --watch world >"$T/p2" 2>&1 )
check "the watching station pushed the kept report without running the jobs again" 'grep -q "kept report was pushed" "$T/p2" && ! grep -q "^STATION PASS" "$T/p2" && [ ! -e "$gd/station_last.unpushed" ] && rd station-results gamma.txt | grep -q "commit=${head3:0:7} "'

echo "== the LAN rehearsal jobs (stubs here; tools/station/lan_test.sh runs the real pair)"
check "lanhost.sh and lanplay.sh answer with a stub line and exist as queue shell scripts" '[ "$(bash "$REPO/tools/station/jobs/lanhost.sh" secs=30)" = "PASS lanhost stub secs=30" ] && [ "$(bash "$REPO/tools/station/jobs/lanplay.sh" secs=30 bots=3)" = "PASS lanplay stub secs=30 bots=3" ]'
idl=$(Q alpha add kind=shell args="script=lanhost secs=1800" needs=alpha | tail -1)
Q alpha step >"$T/o" 2>&1
check "the queue runs lanhost as a shell job" 'rd station-results work/$idl/alpha.txt | grep -q " PASS id=$idl kind=shell .*lanhost stub secs=1800"'
if [ -x "$REPO/realm/target/release/realm-lanplay" ] && [ -x "$REPO/realm/target/release/realm-gateway" ]; then
  STATION_QUEUE_STUB= bash "$REPO/tools/station/lan_test.sh" >"$T/lan.out" 2>&1; check "the local host and player pair (lan_test.sh) prints LAN ok" 'tail -1 "$T/lan.out" | grep -q "^LAN ok"'
else echo "  skip the real LAN pair: build realm first (cargo build --release -p realm-gateway); run tools/station/lan_test.sh"; fi

echo "== a machine's own old claim does not block it; a claim is checked and pushed on one view"
cancel_all() { Q alpha list | awk '$1 ~ /^[0-9]/ { print $1 }' | while read -r i; do Q alpha cancel "$i" >/dev/null; done; }
cancel_all
ido=$(Q alpha add kind=soak args="secs=5 seeds=3" needs=any priority=9 | tail -1)
printf 'machine=alpha time=%s\n' "$(date +%s)" >"$T/own"   # alpha crashed a minute ago holding this claim; it is not stale for others yet
( cd "$T/alpha" && . tools/station/queue_lib.sh && MACHINE=alpha gb_put station-queue "own claim" "+claims/$ido.alpha:$T/own" )
Q beta step >"$T/o" 2>&1; rc=$?
check "another machine still respects the live claim" '[ $rc = 1 ]'
Q alpha step >"$T/o" 2>&1; rc=$?
check "alpha retakes its own claim and finishes the job" '[ $rc = 0 ] && rd station-results work/$ido/alpha.txt | grep -q " PASS id=$ido " && ! files station-queue | grep -q "^claims/$ido\."'
idr2=$(Q alpha add kind=soak args="secs=5 seeds=4" needs=any priority=9 | tail -1)
( cd "$T/beta" && . tools/station/queue_lib.sh && MACHINE=beta
  eval "$(declare -f q_load | sed '1s/q_load/q_load_orig/')"
  q_load() { q_load_orig "$@"; local lrc=$?; if [ -z "${raced:-}" ]; then raced=1; ( cd "$T/alpha" && . tools/station/queue_lib.sh && MACHINE=alpha && q_fetch && q_claim "$idr2" ); fi; return $lrc; }
  q_claim "$idr2" ); rc=$?
check "alpha claims after beta looked but before beta pushed: beta loses, one claim" '[ $rc = 1 ] && [ "$(files station-queue | grep -c "^claims/$idr2\.")" = 1 ] && files station-queue | grep -qx "claims/$idr2.alpha-0"'
cancel_all

echo "== the resource gate: RAM and the GPU"
idm=$(Q alpha add kind=soak args="secs=5 seeds=5" needs=alpha needs_free_mb=500 | tail -1)
check "the job file carries needs_free_mb" 'rd station-queue queue/$idm.job | grep -qx "needs_free_mb=500"'
STATION_FREE_MB=100 Q alpha step >"$T/o" 2>&1; rc=$?
check "100 MB free for a 500 MB job: nothing runs, one clear SKIP line" '[ $rc = 1 ] && grep -qx "SKIP queue job $idm: needs 500 MB free RAM, only 100 MB free" "$T/o" && ! rd station-results work/$idm/alpha.txt | grep -q .'
Q alpha step >"$T/o" 2>&1; rc=$?
check "with enough RAM the same job runs" '[ $rc = 0 ] && rd station-results work/$idm/alpha.txt | grep -q " PASS id=$idm "'
idg=$(Q alpha add kind=frames args="zooms=16" needs=alpha | tail -1)
echo "RUNNING" >"$T/art-status"
HH_ART_STATUS="$T/art-status" Q alpha step >"$T/o" 2>&1; rc=$?
check "a GPU job waits while art generation is RUNNING (SKIP line)" '[ $rc = 1 ] && grep -q "SKIP queue job $idg: the GPU is busy" "$T/o"'
echo "DONE" >"$T/art-status"
HH_ART_STATUS="$T/art-status" Q alpha step >"$T/o" 2>&1; rc=$?
check "and runs when the art status file says otherwise" '[ $rc = 0 ] && rd station-results work/$idg/alpha.txt | grep -q " INFO id=$idg kind=frames "'
Q alpha add kind=soak args="secs=5" needs_free_mb=abc >"$T/o" 2>&1; check "add refuses a bad needs_free_mb" '[ $? != 0 ] && grep -q "bad needs_free_mb" "$T/o"'

echo "== a job that dies silently reports its exit code and last stderr"
ids2=$(Q alpha add kind=soak args="secs=5 seeds=9" needs=alpha | tail -1)
( cd "$T/alpha" && . tools/station/queue_lib.sh && MACHINE=alpha
  qk_soak() { echo "boom on stderr" >&2; exit 7; }
  q_fetch && q_run_job "$ids2" ) >"$T/o" 2>&1
check "the FAIL line has exit 7 and the stderr text, not just 'printed nothing'" 'rd station-results work/$ids2/alpha.txt | grep -q " FAIL id=$ids2 .*job printed nothing (exit 7; stderr: boom on stderr"'

echo "== lanes: several queue jobs at once on one machine"
cancel_all
LQ() { ( cd "$T/alpha" && . tools/station/queue_lib.sh && MACHINE=alpha && eval "$1" ); }   # queue_lib as alpha's station
waitlanes() { for _ in $(seq 1 90); do [ "$(LQ 'lanes_busy')" = 0 ] && break; sleep 1; done; }
claims() { files station-queue | grep "^claims/$1\." | grep -c .; }
check "lane count: STATION_LANES, else the roles.txt line, else from cores" '[ "$(cd "$T/alpha" && STATION_LANES=2 bash -c ". tools/station/queue_lib.sh; MACHINE=alpha; q_lane_total")" = 2 ] && [ "$(cd "$T/alpha" && echo "lanes: alpha 7" >>tools/station/roles.txt && bash -c ". tools/station/queue_lib.sh; MACHINE=alpha; q_lane_total"; git checkout -q tools/station/roles.txt)" = 7 ] && [ "$(LQ q_lane_total)" -ge 1 ]'
idA=$(Q alpha add kind=fuzz args="seeds=1-99999 ops=500" needs=alpha repeat=forever priority=9 max_lanes=3 | tail -1)
idB=$(Q alpha add kind=soak args="secs=5 seeds=1-99999" needs=alpha repeat=forever priority=1 | tail -1)
idC=$(Q alpha add kind=soak args="secs=5 seeds=8" needs=alpha priority=9 | tail -1)
check "the job file carries max_lanes" 'rd station-queue queue/$idA.job | grep -qx "max_lanes=3"'
LQ 'Q_NLANES=6 STATION_QUEUE_STUB_SLEEP=25; q_build_all; lanes_fill; echo "started=$Q_STARTED busy=$(lanes_busy)"' >"$T/l1" 2>&1
check "6 lanes, a once job, a max_lanes=3 forever job and a max_lanes=1 one: 5 lanes start, the 6th finds nothing" 'grep -q "^started=5 busy=5" "$T/l1"'
check "the max_lanes=3 job runs in 3 lanes, the others in one each" '[ "$(claims $idA)" = 3 ] && [ "$(claims $idB)" = 1 ] && [ "$(claims $idC)" = 1 ]'
check "every claim names its lane, and no lane holds two claims" '[ "$(files station-queue | grep "^claims/" | sed "s/.*\.alpha-//" | sort -u | grep -c "^[1-6]$")" = 5 ]'
LQ 'Q_NLANES=6; q_build_all; lanes_fill; echo "again started=$Q_STARTED"' >"$T/l2" 2>&1
check "a second fill while they run starts nothing: two lanes never take one claim" 'grep -q "^again started=0" "$T/l2" && [ "$(claims $idA)" = 3 ]'
waitlanes
check "when the lanes end: 3 result lines of the max_lanes job, the once job done, no claim left" '[ "$(rd station-results work/$idA/alpha.txt | grep -c " PASS id=$idA ")" = 3 ] && files station-queue | grep -qx "done/$idC.alpha" && ! files station-queue | grep -qE "^claims/($idA|$idB|$idC)\\."'
cancel_all
idD=$(Q alpha add kind=soak args="secs=5 seeds=11" priority=9 timeout_s=60 | tail -1)
idE=$(Q alpha add kind=soak args="secs=5 seeds=12" priority=9 | tail -1)
printf 'machine=beta lane=2 time=%s\n' "$(( $(date +%s) - 10800 ))" >"$T/st1"; printf 'machine=alpha lane=4 time=%s\n' "$(date +%s)" >"$T/st2"
( cd "$T/alpha" && . tools/station/queue_lib.sh && MACHINE=alpha gb_put station-queue "lane claims" "+claims/$idD.beta-2:$T/st1" "+claims/$idE.alpha-4:$T/st2" )
Q beta step >"$T/o" 2>&1; rc=$?
check "another machine respects a live lane claim (alpha-4, fresh) and takes the stale one (beta-2) only as a takeover" '[ $rc = 0 ] && rd station-results work/$idD/beta.txt | grep -q " PASS id=$idD " && ! rd station-results work/$idE/beta.txt | grep -q .'
LQ 'Q_NLANES=2; q_build_all; lanes_fill; echo "started=$Q_STARTED"' >"$T/l3" 2>&1; waitlanes
check "a lane claim of this machine whose lane is not running (a crash) is taken over by a lane" 'grep -q "^started=1" "$T/l3" && rd station-results work/$idE/alpha.txt | grep -q " PASS id=$idE " && ! files station-queue | grep -q "^claims/$idE\."'
cancel_all

echo "== Smart App Control: jobs that run programs built here are skipped, signed ones run"
idF=$(Q alpha add kind=fuzz args="seeds=5" needs=alpha priority=9 | tail -1)
idG=$(Q alpha add kind=economy args="seeds=5" needs=alpha priority=9 | tail -1)
idH=$(Q alpha add kind=shell args="script=selftest sac" needs=alpha priority=5 | tail -1)
idX=$(Q alpha add kind=shell args="script=exediag" needs=alpha priority=1 | tail -1)
LQ 'STATION_SAC=1; Q_NLANES=3; q_build_all; lanes_fill; echo "started=$Q_STARTED"' >"$T/s1" 2>&1; waitlanes
LQ 'STATION_SAC=1; Q_NLANES=3; q_build_all; lanes_fill; echo "started=$Q_STARTED"' >"$T/s2" 2>&1; waitlanes
check "the signed-program job runs (selftest), and exediag (marked station-sac: ok)" 'rd station-results work/$idH/alpha.txt | grep -q " INFO id=$idH .*selftest ok" && rd station-results work/$idX/alpha.txt | grep -q "id=$idX"'
check "fuzz and economy are not run, no FAIL, nothing published for them" '! rd station-results work/$idF/alpha.txt | grep -q . && ! rd station-results work/$idG/alpha.txt | grep -q . && ! files station-queue | grep -q "^done/$idF\."'
check "one SKIP line in half an hour for them, not one per job or per pick" '[ "$(cat "$T/s1" "$T/s2" | grep -c "^SKIP queue job own-binaries: 2 job(s) run programs built here and Smart App Control")" = 1 ] && ! grep -q "SKIP queue job $idF" "$T/s1"'
check "a SAC station builds nothing for the lanes" '! grep -q "building" "$T/s1"'
check "the jobs that need our programs are recognised (frames needs our GDExtension DLL; wirefuzz, worldlong, lanhost, lanplay, sizepick run cargo or realm/target)" '( cd "$T/alpha" && . tools/station/queue_lib.sh && for k in fuzz soak bench balance economy frames package; do J_KIND=$k; J_OWNBIN=; q_ownbin || exit 1; done; for sc in wirefuzz worldlong lanhost lanplay sizepick; do J_KIND=shell J_ARGS="script=$sc"; q_ownbin || exit 1; done; for sc in selftest blender charbody exediag sysinfo; do J_KIND=shell J_ARGS="script=$sc"; q_ownbin && exit 1; done; exit 0 )'

echo "== the build: once per commit, and no lane starts a job that runs our programs while it builds"
agd2=$(git -C "$T/alpha" rev-parse --absolute-git-dir); rm -rf "$agd2/station_bin"
( cd "$T/alpha" && . tools/station/queue_lib.sh && MACHINE=alpha STATION_QUEUE_STUB_BUILD_SLEEP=6 q_build_all >"$T/b1" 2>&1 ) & bp=$!
for _ in $(seq 1 20); do [ -d "$agd2/station_build.lock" ] && break; sleep 0.5; done
LQ 'Q_NLANES=2; Q_SNAP=$(q_snap_dir); lanes_fill; echo "started=$Q_STARTED"' >"$T/b2" 2>&1
check "during the build no lane starts the fuzz and economy jobs (one SKIP line)" '[ -d "$agd2/station_build.lock" ] && grep -q "^started=0" "$T/b2" && grep -q "SKIP queue job build-running" "$T/b2"'
wait $bp
check "the build made one copy of the programs for this commit" 'grep -q "building" "$T/b1" && ls "$agd2"/station_bin/*/.ok >/dev/null 2>&1 && [ ! -d "$agd2/station_build.lock" ]'
LQ 'Q_NLANES=2; q_build_all; lanes_fill; echo "started=$Q_STARTED"' >"$T/b3" 2>&1; waitlanes
check "after the build the lanes start them, and the build is not run again" 'grep -q "^started=2" "$T/b3" && ! grep -q building "$T/b3" && rd station-results work/$idF/alpha.txt | grep -q " PASS id=$idF "'
cancel_all

echo "== a queue of signed-program jobs only (Four of Wands jobs): nothing is built"
rm -rf "$agd2/station_bin" "$agd2/station_build.state"
idN=$(Q alpha add kind=shell args="script=selftest nobuild" needs=alpha | tail -1)
LQ 'Q_NLANES=2; q_build_all; echo "snap=[${Q_SNAP:-}]"; lanes_fill; echo "started=$Q_STARTED"' >"$T/n1" 2>&1; waitlanes
check "no build, no copy of the programs, and the job still runs in a lane" '! grep -q "building" "$T/n1" && grep -q "^snap=\[\]" "$T/n1" && [ ! -d "$agd2/station_bin" ] && grep -q "^started=1" "$T/n1" && rd station-results work/$idN/alpha.txt | grep -q "selftest ok"'
idB=$(Q alpha add kind=fuzz args="seeds=5" needs=alpha | tail -1)
LQ 'Q_NLANES=2; q_build_all; lanes_fill; q_build_all; lanes_fill; echo "started=$Q_STARTED"' >"$T/n2" 2>&1; waitlanes
check "a job that runs our programs joins the queue: the build is back one loop later at the latest, and the job runs" 'grep -q "building" "$T/n2" && ls "$agd2"/station_bin/*/.ok >/dev/null 2>&1 && rd station-results work/$idB/alpha.txt | grep -q " PASS id=$idB "'
cancel_all

echo "== the real station loop: queue job first, deep only when the queue is empty"
if command -v setsid >/dev/null 2>&1; then
  Q alpha list | awk '$1 ~ /^[0-9]/ { print $1 }' | while read -r i; do Q alpha cancel "$i" >/dev/null; done
  idw=$(Q alpha add kind=soak args="secs=5 seeds=42" needs=alpha priority=9 | tail -1)
  ( cd "$T/alpha" && git checkout -q main && git pull -q origin main )
  ( cd "$T/seed" && printf 'alpha: idle queue deep\nbeta: idle queue deep\n' >tools/station/roles.txt )
  ( cd "$T/alpha" && STATION_NAME=alpha STATION_POLL=1 STATION_DEEP_GAP=1 setsid bash -c 'echo $$ >"$1"; exec bash tools/station/station.sh --watch idle' _ "$T/station.pid" >"$T/station.log" 2>&1 & )
  for _ in $(seq 1 40); do rd station-results alpha-deep.txt | grep -q 'JOB deep PASS stub' && break; sleep 1; done
  kill -- -"$(cat "$T/station.pid")" 2>/dev/null; sleep 1
  check "the station ran the queued job (result on the results branch)" 'rd station-results work/$idw/alpha.txt | grep -q " PASS id=$idw kind=soak"'
  check "then, queue empty, it fell back to deep" 'rd station-results alpha-deep.txt | grep -q "JOB deep PASS stub"'
else echo "  skip the station-loop test: no setsid here"; fi

echo "== a re-exec leaves one heartbeat loop, and the loop ends with its station"
if command -v setsid >/dev/null 2>&1; then
  hb="$T/hb.log"; : >"$hb"
  ( cd "$T/alpha" && git checkout -q main && git pull -q origin main )
  ( cd "$T/alpha" && STATION_NAME=alpha STATION_POLL=1 STATION_DEEP_GAP=1 STATION_HEARTBEAT_SECS=1 STATION_HEARTBEAT_LOG="$hb" setsid bash -c 'echo $$ >"$1"; exec bash tools/station/station.sh --watch idle' _ "$T/hb.pid" >"$T/hb_station.log" 2>&1 & )
  for _ in $(seq 1 20); do [ -s "$hb" ] && [ -s "$T/hb.pid" ] && break; sleep 1; done
  first=$(awk '{ print $1; exit }' "$hb")
  ( cd "$T/seed" && echo "# re-exec" >>tools/station/roles.txt && git -c user.name=t -c user.email=t@t commit -qam reexec && git push -q origin HEAD:main )  # a merge that changes the script's inputs
  for _ in $(seq 1 40); do grep -qv "^$first " "$hb" && break; sleep 1; done
  sleep 3; : >"$hb"; sleep 4
  check "the heartbeat line reports lanes busy/total" 'rd station-results alpha-heartbeat.txt | grep -Eq "lanes_busy=[0-9]+/[0-9]+"'
  check "after a re-exec exactly one heartbeat loop runs, the new one" '[ -n "$first" ] && [ "$(awk "{ print \$1 }" "$hb" | sort -u | wc -l)" = 1 ] && ! grep -q "^$first " "$hb"'
  kill -9 "$(cat "$T/hb.pid")" 2>/dev/null; sleep 3; : >"$hb"; sleep 3
  check "the heartbeat loop ends by itself when its station process is gone" '[ ! -s "$hb" ]'
  kill -- -"$(cat "$T/hb.pid")" 2>/dev/null; sleep 1
else echo "  skip the heartbeat test: no setsid here"; fi

echo "== a merge lands while a queue job runs: the merge is tested at once, a long job finishes in its lane; a short one is cut"
if command -v setsid >/dev/null 2>&1; then
  cancel_all
  ( cd "$T/seed" && printf '#!/usr/bin/env bash\nsleep "${1#secs=}"; echo "PASS sleepy done"\n' >tools/station/jobs/sleepy.sh && echo "delta: world queue" >>tools/station/roles.txt \
    && git add -A && git -c user.name=t -c user.email=t@t commit -qm sleepy && git push -q origin HEAD:main )
  git clone -q "$T/origin.git" "$T/delta"; dgd=$(git -C "$T/delta" rev-parse --absolute-git-dir)
  ( cd "$T/delta" && STATION_NAME=delta STATION_POLL=1 STATION_DEEP_POLL=1 setsid bash -c 'echo $$ >"$1"; exec bash tools/station/station.sh --watch idle' _ "$T/d.pid" >"$T/d.log" 2>&1 & )
  for _ in $(seq 1 30); do grep -q "^STATION PASS" "$T/d.log" && break; sleep 1; done
  merge() { ( cd "$T/seed" && echo "$1" >"realm/m_$1" && git add -A && git -c user.name=t -c user.email=t@t commit -qm "m $1" && git push -q origin HEAD:main ); git -C "$T/seed" rev-parse HEAD; }
  idL=$(Q alpha add kind=shell args="script=sleepy secs=14" needs=delta timeout_s=3600 | tail -1)
  for _ in $(seq 1 30); do grep -q "delta runs $idL" "$T/d.log" && break; sleep 1; done
  mh=$(merge long)
  for _ in $(seq 1 60); do [ "$(cat "$dgd/station_last" 2>/dev/null)" = "$mh" ] && break; sleep 1; done
  check "with lanes the merge is tested while the long job still runs in its lane" '[ "$(cat "$dgd/station_last")" = "$mh" ] && ! rd station-results work/$idL/delta.txt | grep -q "sleepy done"'
  for _ in $(seq 1 40); do rd station-results work/$idL/delta.txt | grep -q "sleepy done" && break; sleep 1; done
  check "long job (timeout 3600 s): not interrupted, its PASS is published" '! grep -q "interrupted" "$T/d.log" && rd station-results work/$idL/delta.txt | grep -q " PASS id=$idL .*sleepy done"'
  idS=$(Q alpha add kind=shell args="script=sleepy secs=40" needs=delta timeout_s=60 | tail -1)
  for _ in $(seq 1 30); do grep -q "delta runs $idS" "$T/d.log" && break; sleep 1; done
  mh2=$(merge short)
  for _ in $(seq 1 30); do grep -q "job $idS interrupted" "$T/d.log" && break; sleep 1; done
  check "short job (timeout 60 s): killed by the merge, claim released" 'grep -q "job $idS interrupted" "$T/d.log" && ! files station-queue | grep -q "^claims/$idS\.delta"'
  kill -- -"$(cat "$T/d.pid")" 2>/dev/null; sleep 1
else echo "  skip the merge-vs-queue-job test: no setsid here"; fi

echo "== a job started 3 times without a result is parked; a result that cannot be pushed is spooled and sent on the next step"
agd=$(git -C "$T/alpha" rev-parse --absolute-git-dir)
idp=$(Q alpha add kind=fuzz args="seeds=1" needs=alpha priority=9 | tail -1)
echo "$idp 3" >"$agd/station_attempts"
Q alpha step >"$T/o" 2>&1; rc=$?
check "the 4th start is not run: a parked FAIL line is published and the job counts as done" '[ $rc = 0 ] && rd station-results work/$idp/alpha.txt | grep -q " FAIL id=$idp kind=fuzz .*parked: started 3 times on this machine without finishing" && files station-queue | grep -qx "done/$idp.alpha" && ! grep -q "^$idp " "$agd/station_attempts"'
idq=$(Q alpha add kind=fuzz args="seeds=1" needs=alpha priority=9 | tail -1)
printf '#!/bin/sh\n[ -e "%s/nopush" ] && while read -r o n r; do case "$r" in refs/heads/station-results) exit 1 ;; esac; done\nexit 0\n' "$T" >"$T/origin.git/hooks/pre-receive"; chmod +x "$T/origin.git/hooks/pre-receive"
touch "$T/nopush"; Q alpha step >"$T/o" 2>&1
check "with the results branch refusing pushes the line is spooled, not lost" 'grep -q "spooled" "$T/o" && grep -q "^$idq .* PASS id=$idq " "$agd/station_spool" && ! rd station-results work/$idq/alpha.txt | grep -q "id=$idq"'
rm -f "$T/nopush"; Q alpha step >"$T/o" 2>&1
check "the next step sends the spooled line and empties the spool" 'rd station-results work/$idq/alpha.txt | grep -q " PASS id=$idq " && [ ! -s "$agd/station_spool" ]'
old="$T/station-job-alpha-OLD"; mkdir "$old"; touch -d '3 days ago' "$old" 2>/dev/null || touch -t 200001010000 "$old"; mkdir "$T/station-job-beta-KEEP"; touch -t 200001010000 "$T/station-job-beta-KEEP"
Q alpha step >"$T/o" 2>&1
check "the step prunes this machine's old work dirs and nothing else" '[ ! -e "$old" ] && [ -d "$T/station-job-beta-KEEP" ]'

echo "== a failed commit never deletes a branch (23 Nov: an empty commit in the push deleted station-results)"
before=$(git -C "$T/origin.git" rev-parse -q --verify refs/heads/station-results)
( cd "$T/alpha" && MACHINE=alpha && . tools/station/queue_lib.sh && echo x >"$T/x" && GB_BASE=0123456789012345678901234567890123456789 gb_put station-results "bad base" "+x.txt:$T/x" ); rc=$?
check "gb_put on a base it cannot read returns 1 and leaves the branch as it was" '[ $rc = 1 ] && [ "$(git -C "$T/origin.git" rev-parse -q --verify refs/heads/station-results)" = "$before" ]'

echo "== silence, a merge on a repeatable job, the lead's stop, the circuit breaker"
cancel_all; t_new=$SECONDS
J="$T/alpha/tools/station/jobs"   # scripts of these tests, untracked in alpha's work tree
printf '#!/usr/bin/env bash\necho one; echo two; echo three; sleep 30; echo "PASS late"\n' >"$J/quiet.sh"
printf '#!/usr/bin/env bash\nfor i in $(seq 1 30); do echo "tick $i"; sleep 1; done; echo "PASS talked"\n' >"$J/talk.sh"
check "silence defaults by kind: shell 900, a building script 3600, a rendering one off, package off, fuzz 1800" \
  '[ "$(LQ "q_default_silent shell script=quiet; q_default_silent shell script=wirefuzz; q_default_silent shell script=render; q_default_silent package x; q_default_silent fuzz x" | tr "\n" " ")" = "900 3600 0 0 1800 " ]'
ids=$(Q alpha add kind=shell args="script=quiet" needs=alpha silent_s=3 | tail -1)
check "the job file carries silent_s" 'rd station-queue queue/$ids.job | grep -qx "silent_s=3"'
Q alpha step >"$T/o" 2>&1
check "1 silence: a job quiet for silent_s is stopped, FAIL silent for N s with its last 3 lines, done recorded" 'rd station-results work/$ids/alpha.txt | grep -q " FAIL id=$ids kind=shell .*silent for [3-9] s: one two three" && files station-queue | grep -qx "done/$ids.alpha"'
idm=$(Q alpha add kind=soak args="secs=5" needs=alpha timeout_s=3600 | tail -1)
( cd "$T/alpha" && MACHINE=alpha && . tools/station/queue_lib.sh && pending_merge() { [ -e "$T/merged" ]; } && STATION_DEEP_POLL=1 STATION_QUEUE_STUB_SLEEP=30 queue_step ) >"$T/o" 2>&1 & mp=$!
for _ in $(seq 1 20); do files station-queue | grep -q "^claims/$idm\." && break; sleep 0.5; done; sleep 1; touch "$T/merged"; wait $mp; rm -f "$T/merged"
check "2 merge: a long soak (timeout 3600) is stopped for a merge, INFO line, no done record, claim gone, job still queued" 'rd station-results work/$idm/alpha.txt | grep -q " INFO id=$idm kind=soak .*stopped for a merge after [0-9]* s" && ! files station-queue | grep -q "^done/$idm\." && ! files station-queue | grep -q "^claims/$idm\." && files station-queue | grep -qx "queue/$idm.job"'
Q alpha cancel "$idm" >/dev/null
idt=$(Q alpha add kind=shell args="script=talk" needs=alpha | tail -1)
Q beta stop "$idt" >"$T/o2" 2>&1
check "3 stop of a job that is not running is a note and writes nothing" 'grep -q "not running anywhere" "$T/o2" && ! files station-queue | grep -qx "stop/$idt"'
( STATION_DEEP_POLL=1 STATION_QUEUE_FETCH_S=1 Q alpha step >"$T/o" 2>&1 ) & sp=$!
for _ in $(seq 1 20); do files station-queue | grep -q "^claims/$idt\." && break; sleep 0.5; done
Q beta stop "$idt" >"$T/o2" 2>&1; t_stop=$SECONDS; wait $sp
check "3 stop: queue.sh stop on another machine stops alpha's run within seconds, INFO stopped by the lead, the job stays" 'grep -q "run(s) stop" "$T/o2" && [ $((SECONDS - t_stop)) -lt 15 ] && rd station-results work/$idt/alpha.txt | grep -q " INFO id=$idt kind=shell .*stopped by the lead" && rd station-queue done/$idt.alpha | grep -q "status=INFO" && files station-queue | grep -qx "queue/$idt.job" && files station-queue | grep -qx "stop/$idt"'
Q alpha cancel "$idt" >/dev/null
check "cancel also removes the stop file" '! files station-queue | grep -qx "stop/$idt"'
git -C "$T/beta" fetch -q "$T/alpha" HEAD && git -C "$T/beta" checkout -q --detach FETCH_HEAD   # both machines on one main commit
idf=$(Q alpha add kind=fuzz args="seeds=666" repeat=forever | tail -1)
Q alpha step >/dev/null 2>&1; Q beta step >/dev/null 2>&1; Q alpha step >/dev/null 2>&1
head12=$(git -C "$T/alpha" rev-parse --short=12 HEAD)
check "4 fails= counts FAILs in a row on the commit (alpha 2, beta 1)" 'rd station-queue done/$idf.alpha | grep -q "commit=$head12 fails=2" && rd station-queue done/$idf.beta | grep -q "commit=$head12 fails=1"'
Q alpha step >"$T/o" 2>&1; rc=$?
check "4 breaker: after 3 FAILs on one commit (two machines) the job is skipped with one SKIP line" '[ $rc = 1 ] && grep -q "SKIP queue job $idf: paused: 3 failures on $head12" "$T/o"'
git -C "$T/alpha" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "main moves"
Q alpha step >"$T/o" 2>&1; rc=$?
check "4 when main moves the job runs again" '[ $rc = 0 ] && rd station-queue done/$idf.alpha | grep -q "fails=1"'
Q alpha cancel "$idf" >/dev/null; rm -f "$J/quiet.sh" "$J/talk.sh"
# q_sac on Windows the first time (no cache file yet) under set -u: it once killed every Windows station ("c: unbound variable")
out=$(cd "$T/alpha" && bash -c 'set -uo pipefail; source tools/station/queue_lib.sh; Q_GD=$(mktemp -d); uname() { echo MINGW64_NT; }; timeout() { echo Off; }
  q_sac; echo "rc=$? cache=$(cat "$Q_GD/station_sac" | cut -d" " -f2)"' 2>&1)
check "q_sac with no cache file under set -u: no unbound error, says off and writes the cache" '[[ "$out" == *"rc=1 cache=off"* ]] && [[ "$out" != *unbound* ]]'
snapd=$(cd "$T/alpha" && bash -c 'source tools/station/queue_lib.sh; q_snap_dir')
check "the programs' folder (STATION_BIN) is absolute, so a shell job that cds into realm/ still finds it" '[[ "$snapd" == /* ]]'
idS=$(Q alpha add kind=economy args="seeds=7 days=1 bots=2" needs=alpha priority=9 | tail -1)
LQ 'Q_NLANES=1; Q_SNAP="$T/gone_snap"; lanes_fill; echo "started=$Q_STARTED"' >"$T/g1" 2>&1; waitlanes
check "a lane whose programs' folder is gone hands its job back: no FAIL, no done record, no claim left" 'grep -q "^started=1" "$T/g1" && grep -q "programs. folder .* is gone" "$T/g1" && ! rd station-results work/$idS/alpha.txt | grep -q FAIL && ! files station-queue | grep -q "^done/$idS\." && ! files station-queue | grep -q "^claims/$idS\."'
Q alpha cancel "$idS" >/dev/null
# A station restart (exec keeps the pid) reaps leftover heartbeat loops among its children, but not its running lanes.
mkdir -p "$T/reap/lanes"
bash -c 'sleep 30 & lane=$!; sleep 30 & loop=$!; echo "pid=$lane id=x kind=soak" >"$1/lanes/1"
  Q_LD="$1/lanes"; eval "$(sed -n "/^heartbeat_reap()/,/^}/p" "$2")"; heartbeat_reap
  wait $loop; echo "loop_rc=$?"; st=$(ps -o stat= -p $lane | tr -d " "); [ -n "$st" ] && [ "${st:0:1}" != Z ] && echo lane_alive; kill $lane' _ "$T/reap" "$REPO/tools/station/station.sh" >"$T/reap/out" 2>&1
check "a station restart kills a leftover loop but spares a running lane (merges used to kill every job and park it)" 'grep -q "^loop_rc=143" "$T/reap/out" && grep -q "^lane_alive" "$T/reap/out"'
echo "  (these checks took $((SECONDS - t_new)) s)"

echo "== the stop line: a station it names ends; once the line is off main a start runs at once, however fresh the last stop"
if command -v setsid >/dev/null 2>&1; then
  ( cd "$T/seed" && git pull -q origin main 2>/dev/null; printf 'stopped: alpha\n' >>tools/station/roles.txt && git -c user.name=t -c user.email=t@t commit -qam stop-alpha && git push -q origin HEAD:main )
  ( cd "$T/alpha" && git checkout -q main 2>/dev/null; git pull -q origin main )
  ( cd "$T/alpha" && STATION_NAME=alpha STATION_POLL=1 timeout 90 bash tools/station/station.sh --watch idle >"$T/st1" 2>&1 ); rc1=$?
  check "main names alpha on the stop line: the station publishes STOPPED and exits 0" '[ $rc1 = 0 ] && grep -q "roles.txt stops this station" "$T/st1" && rd station-results alpha.txt | grep -q "STATION STOPPED"'
  ( cd "$T/seed" && sed -i '/^stopped:/d' tools/station/roles.txt && git -c user.name=t -c user.email=t@t commit -qam unstop-alpha && git push -q origin HEAD:main )
  ( cd "$T/alpha" && STATION_NAME=alpha STATION_POLL=1 STATION_DEEP_GAP=1 setsid bash -c 'echo $$ >"$1"; exec bash tools/station/station.sh --watch idle' _ "$T/st.pid" >"$T/st2" 2>&1 & )
  for _ in $(seq 1 40); do grep -q "origin/main does not: running\|stops this station" "$T/st2" 2>/dev/null && break; sleep 1; done
  sleep 2; kill -- -"$(cat "$T/st.pid" 2>/dev/null)" 2>/dev/null; sleep 1
  check "seconds later the line is off main while the checkout still has it: the station runs (27 Nov 2026: it stopped again for 30 minutes)" 'grep -q "origin/main does not: running" "$T/st2" && ! grep -q "stops this station" "$T/st2"'
  ( cd "$T/alpha" && git checkout -q main 2>/dev/null; git pull -q origin main 2>/dev/null )
else echo "  skip the stop-line test: no setsid here"; fi

if [ $fails = 0 ]; then echo "QUEUE ok"; else echo "QUEUE FAILED $fails"; exit 1; fi

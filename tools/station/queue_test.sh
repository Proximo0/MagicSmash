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
check "a claim whose push is rejected loses (rc=1) and only alpha holds the claim" '[ $rc = 1 ] && [ "$(files station-queue | grep -c "^claims/$idc\.")" = 1 ] && files station-queue | grep -qx "claims/$idc.alpha"'
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
check "hours file has a line for today" 'rd station-results alpha-hours.txt | grep -q "^$(date -u +%F) busy_h=[0-9.]* idle_h=[0-9.]*$"'
Q alpha digest --since=2 >"$T/o" 2>&1
check "digest has per-machine jobs, hours, the FAIL with its seed, and a summary line" 'grep -q "jobs=" "$T/o" && grep -q "alpha " "$T/o" && grep -q "seed=666" "$T/o" && grep -q "^DIGEST jobs=[0-9]* fail=[1-9]" "$T/o" && grep -q "busy=" "$T/o"'
Q alpha fill-week >"$T/o" 2>&1; n1=$(grep -c '^added' "$T/o"); Q alpha fill-week >"$T/o" 2>&1; n2=$(grep -c '^added' "$T/o")
check "fill-week loads jobs for both machines and is idempotent" '[ "$n1" -ge 12 ] && [ "$n2" = 0 ]'

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
check "alpha claims after beta looked but before beta pushed: beta loses, one claim" '[ $rc = 1 ] && [ "$(files station-queue | grep -c "^claims/$idr2\.")" = 1 ] && files station-queue | grep -qx "claims/$idr2.alpha"'
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
  check "after a re-exec exactly one heartbeat loop runs, the new one" '[ -n "$first" ] && [ "$(awk "{ print \$1 }" "$hb" | sort -u | wc -l)" = 1 ] && ! grep -q "^$first " "$hb"'
  kill -9 "$(cat "$T/hb.pid")" 2>/dev/null; sleep 3; : >"$hb"; sleep 3
  check "the heartbeat loop ends by itself when its station process is gone" '[ ! -s "$hb" ]'
  kill -- -"$(cat "$T/hb.pid")" 2>/dev/null; sleep 1
else echo "  skip the heartbeat test: no setsid here"; fi

echo "== a merge lands while a queue job runs: a long job finishes, then the commit is tested; a short one is cut"
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
  check "long job (timeout 3600 s): not interrupted, its PASS is published" '! grep -q "interrupted" "$T/d.log" && rd station-results work/$idL/delta.txt | grep -q " PASS id=$idL .*sleepy done"'
  check "and the station then tested the merge" '[ "$(cat "$dgd/station_last")" = "$mh" ]'
  idS=$(Q alpha add kind=shell args="script=sleepy secs=40" needs=delta timeout_s=60 | tail -1)
  for _ in $(seq 1 30); do grep -q "delta runs $idS" "$T/d.log" && break; sleep 1; done
  mh2=$(merge short)
  for _ in $(seq 1 30); do grep -q "job $idS interrupted" "$T/d.log" && break; sleep 1; done
  check "short job (timeout 60 s): killed by the merge, claim released" 'grep -q "job $idS interrupted" "$T/d.log" && ! files station-queue | grep -q "^claims/$idS\.delta"'
  kill -- -"$(cat "$T/d.pid")" 2>/dev/null; sleep 1
else echo "  skip the merge-vs-queue-job test: no setsid here"; fi

if [ $fails = 0 ]; then echo "QUEUE ok"; else echo "QUEUE FAILED $fails"; exit 1; fi

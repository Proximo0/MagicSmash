#!/usr/bin/env bash
# Test of jobs/wirefuzz.sh with a fake cargo (no build, about 20 s): progress lines, the budget, a kill by the queue's
# timeout (a summary line, never nothing, and no test process left behind), a pass and a failure. Prints WIREFUZZ_TEST ok.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/art"
# Fake cargo: --no-run builds at once; a run prints one ok test, then sleeps FAKE_SECS (a long test), then ends FAKE_END.
cat >"$T/bin/cargo" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --no-run "*) echo "Finished"; exit 0 ;; esac
echo "test fast::one ... ok"
echo $$ >"$FAKE_PIDS"
sleep "${FAKE_SECS:-0}" & echo $! >>"$FAKE_PIDS"; wait $!
echo "test slow::two has been running for over 60 seconds"
case "${FAKE_END:-ok}" in ok) echo "test slow::two ... ok" ;; *) echo "test slow::two ... FAILED"; echo "thread 'slow::two' panicked at x.rs:1:1:"; exit 101 ;; esac
EOF
chmod +x "$T/bin/cargo"
export PATH="$T/bin:$PATH" FAKE_PIDS="$T/pids" STATION_JOB_SEED=42 WIREFUZZ_TICK=1 STATION_JOB_ART="$T/art"
fails=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1 ($2)"; fails=$((fails + 1)); fi; }
alive() { local p; for p in $(cat "$T/pids" 2>/dev/null); do kill -0 "$p" 2>/dev/null && return 0; done; return 1; }
job=("$REPO/tools/station/jobs/wirefuzz.sh")

FAKE_SECS=0 bash "${job[@]}" iters=5 >"$T/pass.out" 2>&1; rc=$?
check "a pass: PASS with iters and seed, rc 0" '[ $rc = 0 ] && tail -1 "$T/pass.out" | grep -q "^PASS wirefuzz iters=5 seed=42 2 tests"'
check "the start line comes first" 'head -1 "$T/pass.out" | grep -q "^wirefuzz iters=5 seed=42 secs=3000 started"'

FAKE_SECS=0 FAKE_END=fail bash "${job[@]}" iters=5 >"$T/fail.out" 2>&1; rc=$?
check "a failure: FAIL with the rerun, rc 1, the log kept" '[ $rc = 1 ] && tail -1 "$T/fail.out" | grep -q "^FAIL wirefuzz iters=5 seed=42 1 tests ok, 1 failed .*WIRE_FUZZ_SEED=42" && [ -s "$T/art/wirefuzz.log" ]'

rm -f "$T/pids"; FAKE_SECS=100 bash "${job[@]}" iters=5 secs=4 >"$T/budget.out" 2>&1; rc=$?
check "at its budget: INFO with the tests done, rc 0" '[ $rc = 0 ] && tail -1 "$T/budget.out" | grep -q "^INFO wirefuzz iters=5 seed=42 stopped at its budget of 4 s: 1 tests ok, 0 failed"'
check "progress lines while it runs" 'grep -q "^wirefuzz iters=5 seed=42 [0-9]* s: 1 tests ok" "$T/budget.out"'
check "no test process left after the budget" '! alive'

rm -f "$T/pids"; FAKE_SECS=100 timeout -k 10 4 bash "${job[@]}" iters=5 >"$T/killed.out" 2>&1; rc=$?
check "killed by the queue's timeout: rc 124 and a FAIL summary last, not nothing" '[ $rc = 124 ] && tail -1 "$T/killed.out" | grep -q "^FAIL wirefuzz iters=5 seed=42 killed after [0-9]* s: 1 tests ok"'
sleep 1
check "no test process left after the kill" '! alive'

FAKE_SECS=0 bash "${job[@]}" iters=x >"$T/bad.out" 2>&1
check "bad words: FAIL" 'grep -q "^FAIL wirefuzz bad words" "$T/bad.out"'

[ $fails = 0 ] && echo "WIREFUZZ_TEST ok" || { echo "WIREFUZZ_TEST FAILED $fails"; exit 1; }

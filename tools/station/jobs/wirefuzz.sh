#!/usr/bin/env bash
# A queue `shell` job: the wire decoder fuzz tests (gateway protocol, core PvP block and field state, server HELLO/INPUT,
# tick records, snapshots, join state) with a fresh seed and many iterations, to hunt between merges.
# Words after script=wirefuzz: `iters=N` (default 2000000), `secs=N` (default 3000): the job's own time budget, build
# included. The field state and join state tests take most of it, linear in iters (about 0.5 ms an iteration on a Linux
# desktop, both together; a few times that on Windows): at the budget the tests are stopped and the summary is INFO with
# the tests done. Keep the queue job's timeout_s above secs (by 5 minutes or more).
# Output: a start line, a progress line every WIREFUZZ_TICK seconds (default 60), the summary last. Killed (the queue's
# timeout), it still stops the tests (on Windows the whole process tree) and prints a FAIL summary of how far it got.
iters=2000000 secs=3000 tick="${WIREFUZZ_TICK:-60}"
for w in "$@"; do case "$w" in iters=*) iters="${w#iters=}" ;; secs=*) secs="${w#secs=}" ;; esac; done
seed="${STATION_JOB_SEED:-1}"
re='^[0-9]+$'; [[ "$iters" =~ $re && "$secs" =~ $re && "$tick" =~ $re ]] || { echo "FAIL wirefuzz bad words: iters=$iters secs=$secs"; exit 1; }
cd "$(dirname "$0")/../../../realm" || { echo "FAIL no realm directory"; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "FAIL cargo is not installed"; exit 1; }
tag="wirefuzz iters=$iters seed=$seed"
rerun="(rerun: WIRE_FUZZ_ITERS=$iters WIRE_FUZZ_SEED=$seed cargo test --release --lib fuzz in realm/)"
log=$(mktemp); pid=""; t0=$SECONDS
trap 'rm -f "$log"' EXIT
echo "$tag secs=$secs started"

# The test processes: cargo and what it started. In a session of their own where setsid exists (then the queue's
# timeout reaches them only through this script, which stops them); on Windows taskkill /T takes the native tree.
stop_tests() {
	[ -n "$pid" ] || return 0
	if [ -r "/proc/$pid/winpid" ] && command -v taskkill >/dev/null 2>&1; then taskkill //F //T //PID "$(cat "/proc/$pid/winpid")" >/dev/null 2>&1; fi
	kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
	local n=0; while kill -0 "$pid" 2>/dev/null && [ $n -lt 20 ]; do sleep 0.5; n=$((n + 1)); done
	kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
	wait "$pid" 2>/dev/null; pid=""
}
# How far the tests got: "K tests ok, F failed[, running: names]" (libtest names a test running for over 60 s).
state() {
	local ok bad run=""
	ok=$(tr -d '\r' <"$log" | grep -c '^test .* ok$'); bad=$(tr -d '\r' <"$log" | grep -c '^test .* FAILED$')
	run=$(tr -d '\r' <"$log" | awk '/^test .* has been running for over/ { r[$2] = 1 } /^test .* (ok|FAILED)$/ { delete r[$2] } END { for (n in r) printf " %s", n }')
	echo "$ok tests ok, $bad failed${run:+, running:$run}"
}
keep_log() { [ -n "${STATION_JOB_ART:-}" ] && [ -d "$STATION_JOB_ART" ] && tail -300 "$log" >"$STATION_JOB_ART/wirefuzz.log"; return 0; }
killed() {
	stop_tests; keep_log
	echo "FAIL $tag killed after $((SECONDS - t0)) s: $(state) $rerun"
	exit 143
}
trap killed TERM INT HUP

# Build first (its time counts in the budget), then the tests in the background, polled.
WIRE_FUZZ_ITERS="$iters" WIRE_FUZZ_SEED="$seed" cargo test --release -j2 -p realm-core -p realm-server -p realm-gateway --lib fuzz --no-run >"$log" 2>&1 &
pid=$!; wait "$pid"; rc=$?; pid=""
if [ $rc != 0 ]; then
	keep_log; grep -E "error(\[|:)" "$log" | head -8 | grep . || tail -4 "$log" | cut -c1-200
	echo "FAIL $tag build failed (rc=$rc) $rerun"; exit 1
fi
echo "$tag built in $((SECONDS - t0)) s"
run=(env WIRE_FUZZ_ITERS="$iters" WIRE_FUZZ_SEED="$seed" cargo test --release -j2 -p realm-core -p realm-server -p realm-gateway --lib fuzz)
command -v setsid >/dev/null 2>&1 && run=(setsid "${run[@]}")
"${run[@]}" >"$log" 2>&1 </dev/null &
pid=$!; next=$((SECONDS + tick))
while kill -0 "$pid" 2>/dev/null; do
	sleep 1 & wait $!
	if [ $((SECONDS - t0)) -ge "$secs" ]; then
		stop_tests; keep_log
		echo "INFO $tag stopped at its budget of $secs s: $(state) (fewer iters or more secs to finish)"; exit 0
	fi
	[ "$SECONDS" -ge "$next" ] && { echo "$tag $((SECONDS - t0)) s: $(state)"; next=$((SECONDS + tick)); }
done
wait "$pid"; rc=$?; pid=""
if [ $rc = 0 ]; then
	echo "PASS $tag $(tr -d '\r' <"$log" | grep -c '^test .* ok$') tests in $((SECONDS - t0)) s"
else
	keep_log
	# No test line at all (the build or the launch failed): the log's end says why.
	grep -E "panicked|assertion|ask for|FAILED|error(\[|:)" "$log" | head -8 | grep . || tail -4 "$log" | cut -c1-200
	echo "FAIL $tag $(state) $rerun"
	exit 1
fi

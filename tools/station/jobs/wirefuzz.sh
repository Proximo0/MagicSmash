#!/usr/bin/env bash
# A queue `shell` job: the wire decoder fuzz tests (gateway protocol, core PvP block and field state, server HELLO/INPUT,
# tick records, snapshots, join state) with a fresh seed and many iterations, to hunt between merges.
# Words after script=wirefuzz: `iters=N` (default 2000000).
iters=2000000
for w in "$@"; do case "$w" in iters=*) iters="${w#iters=}" ;; esac; done
seed="${STATION_JOB_SEED:-1}"
cd "$(dirname "$0")/../../../realm" || { echo "FAIL no realm directory"; exit 1; }
command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
command -v cargo >/dev/null 2>&1 || { echo "FAIL cargo is not installed"; exit 1; }
# In a station lane (STATION_BIN set) the tests build into their own target dir, never into realm/target, whose programs the station
# builds once per commit for every lane. One dir per machine; run it in one lane at a time (max_per_machine=1).
[ -n "${STATION_BIN:-}" ] && export CARGO_TARGET_DIR="${STATION_TARGETS:-$HOME/station-targets}/wirefuzz"
log=$(mktemp); trap 'rm -f "$log"' EXIT
if WIRE_FUZZ_ITERS="$iters" WIRE_FUZZ_SEED="$seed" cargo test --release -j2 -p realm-core -p realm-server -p realm-gateway --lib fuzz >"$log" 2>&1; then
	echo "PASS wirefuzz iters=$iters seed=$seed $(grep -c '^test .* ok$' "$log") tests"
else
	# No test line at all (the build or the launch failed): the log's end says why.
	grep -E "panicked|assertion|ask for|FAILED|error(\[|:)" "$log" | head -8 | grep . || tail -4 "$log" | cut -c1-200
	echo "FAIL wirefuzz iters=$iters seed=$seed (rerun: WIRE_FUZZ_ITERS=$iters WIRE_FUZZ_SEED=$seed cargo test --release --lib fuzz in realm/)"
	exit 1
fi

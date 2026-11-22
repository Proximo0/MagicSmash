#!/usr/bin/env bash
# A queue `shell` job: the wire decoder fuzz tests (gateway protocol, core PvP block and field state, server HELLO/INPUT,
# tick records, snapshots, join state) with a fresh seed and many iterations, to hunt between merges.
# Words after script=wirefuzz: `iters=N` (default 2000000).
iters=2000000
for w in "$@"; do case "$w" in iters=*) iters="${w#iters=}" ;; esac; done
seed="${STATION_JOB_SEED:-1}"
cd "$(dirname "$0")/../../../realm" || { echo "FAIL no realm directory"; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "FAIL cargo is not installed"; exit 1; }
log=$(mktemp); trap 'rm -f "$log"' EXIT
if WIRE_FUZZ_ITERS="$iters" WIRE_FUZZ_SEED="$seed" cargo test --release -j2 -p realm-core -p realm-server -p realm-gateway --lib fuzz >"$log" 2>&1; then
	echo "PASS wirefuzz iters=$iters seed=$seed $(grep -c '^test .* ok$' "$log") tests"
else
	grep -E "panicked|assertion|ask for|FAILED|error(\[|:)" "$log" | head -8
	echo "FAIL wirefuzz iters=$iters seed=$seed (rerun: WIRE_FUZZ_ITERS=$iters WIRE_FUZZ_SEED=$seed cargo test --release --lib fuzz in realm/)"
	exit 1
fi

#!/bin/bash
# realm/store check: build (no warnings), the tests, then a short crash fuzz (5,000 operations, 20 kills).
# Quiet: failures only, then one summary line.
set -u
command -v sccache >/dev/null 2>&1 && export RUSTC_WRAPPER=sccache
cd "$(dirname "$0")"
if [ -n "${CARGO_BUILD_JOBS:-}" ]; then jobs="$CARGO_BUILD_JOBS"; elif [ -n "${CI:-}" ]; then jobs=$(nproc 2>/dev/null || echo 2); else jobs=2; fi
log=$(mktemp)
trap 'rm -f "$log"' EXIT
scratch=${REALM_STORE_SCRATCH:-${TMPDIR:-/tmp}/realm-store-check}
mkdir -p "$scratch"
export REALM_STORE_SCRATCH="$scratch"

if ! cargo build --release -j"$jobs" >"$log" 2>&1; then
	grep -A6 -E "^(error|warning)" "$log" | head -20
	echo "STORE failed: cargo build"
	exit 1
fi
if grep -q "^warning" "$log"; then
	grep -A4 "^warning" "$log" | head -20
	echo "STORE failed: build warnings"
	exit 1
fi
if ! cargo test --release -j"$jobs" -q -- --test-threads=2 >"$log" 2>&1; then
	grep -A2 -E "^---- |panicked|FAILED|error(\[|:)" "$log" | cut -c1-600 | head -40
	echo "STORE failed: cargo test"
	exit 1
fi
tests=$(grep -Eo "[0-9]+ passed" "$log" | awk '{s += $1} END {print s + 0}')
if grep -q "^warning" "$log"; then
	grep -A4 "^warning" "$log" | head -20
	echo "STORE failed: warnings"
	exit 1
fi
if ! ./target/release/realm-store fuzz --seed=7 --ops=5000 --kills=20 --dir="$scratch/fuzz" >"$log" 2>&1; then
	tail -8 "$log"
	echo "STORE failed: crash fuzz"
	exit 1
fi
fuzz=$(tail -1 "$log" | grep -Eo "kills=[0-9]+|acked=[0-9]+|digest=[0-9a-f]+|secs=[0-9.]+" | tr '\n' ' ')
echo "STORE ok tests=$tests fuzz ops=5000 $fuzz"

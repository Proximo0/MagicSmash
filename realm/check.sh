#!/bin/bash
# realm check: the tests, then a 10 second (200 tick) --bench smoke with the in-process protocol B follower.
# Quiet: failures only, then one summary line.
set -u
cd "$(dirname "$0")"
log=$(mktemp)
trap 'rm -f "$log"' EXIT

if ! cargo build --release -j3 >"$log" 2>&1; then
	grep -A6 -E "^(error|warning)" "$log" | head -20
	echo "REALM failed: cargo build"
	exit 1
fi
if grep -q "^warning" "$log"; then
	grep -A4 "^warning" "$log" | head -20
	echo "REALM failed: build warnings"
	exit 1
fi
if ! cargo test --release -j3 -q >"$log" 2>&1; then
	grep -E "panicked|FAILED|error(\[|:)" "$log" | head -20
	echo "REALM failed: cargo test"
	exit 1
fi
tests=$(grep -Eo "[0-9]+ passed" "$log" | awk '{s += $1} END {print s + 0}')
if grep -q "^warning" "$log"; then
	grep -A4 "^warning" "$log" | head -20
	echo "REALM failed: warnings"
	exit 1
fi

if ! ./target/release/realm-server --bench --bots=300 --monsters=8000 --rally=0.3 --threads=2 --ticks=200 --warmup=40 --report=100 --follow >"$log" 2>&1; then
	tail -5 "$log"
	echo "REALM failed: bench"
	exit 1
fi
row=$(grep -E "^ +[0-9]+x[0-9]+ " "$log" | tail -1)
hash=$(echo "$row" | awk -F'|' '{print $NF}' | xargs)
if [[ "$hash" != ok* ]]; then
	echo "$row"
	echo "REALM failed: follower hash ($hash)"
	exit 1
fi
tick=$(echo "$row" | awk -F'|' '{print $2}' | xargs)
echo "REALM ok tests=$tests bench 300x8000 tick_ms=$tick follower=$hash"

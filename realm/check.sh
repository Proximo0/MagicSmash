#!/bin/bash
# realm check: the tests, then a 10 second (200 tick) --bench smoke with the in-process protocol B follower on
# THE FOOL'S ROAD, and a 100 tick one on THE TOWER (walls, spitters, zones).
# Quiet: failures only, then one summary line.
set -u
command -v sccache >/dev/null 2>&1 && export RUSTC_WRAPPER=sccache
cd "$(dirname "$0")"
log=$(mktemp)
trap 'rm -f "$log"' EXIT

# Jobs: CARGO_BUILD_JOBS if set, else every core on CI, else 2 (local and station PCs stay responsive).
if [ -n "${CARGO_BUILD_JOBS:-}" ]; then jobs="$CARGO_BUILD_JOBS"
elif [ -n "${CI:-}" ]; then jobs=$(nproc 2>/dev/null || echo 2)
else jobs=2; fi
# GATES=0 skips the slow determinism gates (core/tests/gates.rs); the Windows job does that and a nightly runs them there.
skip=()
if [ "${GATES:-1}" = 0 ]; then
	skip=(-- --skip hash_equal_on_1_to_4_threads --skip a_run_of_the_bot_gates --skip a_lone_novice_kiting_bot --skip a_party_holds_the_middle_ring)
fi

# One compile: the tests build the release libraries and binaries; the build after them only fills in binaries
# no test target needed (a no-op otherwise) and its warnings are checked with the tests' own.
if ! cargo test --release -j"$jobs" -q "${skip[@]}" >"$log" 2>&1; then
	# the two lines after "panicked" hold the assertion's values, the part a red CI run needs to be diagnosed
	grep -A2 -E "^---- |panicked|FAILED|error(\[|:)" "$log" | cut -c1-600 | head -40
	echo "REALM failed: cargo test"
	exit 1
fi
build_log=$(mktemp)
if ! cargo build --release -j"$jobs" >"$build_log" 2>&1; then
	grep -A6 -E "^(error|warning)" "$build_log" | head -20
	rm -f "$build_log"
	echo "REALM failed: cargo build"
	exit 1
fi
cat "$build_log" >>"$log"
rm -f "$build_log"
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

if ! ./target/release/realm-server --bench --field=4 --bots=300 --monsters=8000 --rally=0.3 --threads=2 --ticks=100 --warmup=40 --report=100 --follow >"$log" 2>&1; then
	tail -5 "$log"
	echo "REALM failed: tower bench"
	exit 1
fi
row=$(grep -E "^ +[0-9]+x[0-9]+ " "$log" | tail -1)
thash=$(echo "$row" | awk -F'|' '{print $NF}' | xargs)
if [[ "$thash" != ok* ]]; then
	echo "$row"
	echo "REALM failed: tower follower hash ($thash)"
	exit 1
fi
ttick=$(echo "$row" | awk -F'|' '{print $2}' | xargs)
echo "REALM ok tests=$tests bench 300x8000 tick_ms=$tick follower=$hash tower_tick_ms=$ttick tower_follower=$thash"

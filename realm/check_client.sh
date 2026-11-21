#!/bin/bash
# realm client check: builds the native module (realm/godot) into realm/client/bin, builds the server, starts
# a server with 300 bots and 8 000 monsters and a lossy relay in front of it (5% loss, 80 ms delay, 20 ms
# jitter, each way), then runs realm/client/tests/follow_test.gd twice at once, straight to the server and
# through the relay: 400 ticks each, every hash check must pass. Quiet: failures, then one summary line.
# Ports: SERVER_PORT (7791) and RELAY_PORT (7792). GODOT picks the Godot binary (default godot).
set -u
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
SERVER_PORT="${SERVER_PORT:-7791}"
RELAY_PORT="${RELAY_PORT:-7792}"
work=$(mktemp -d)
pids=()
cleanup() {
	for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
	rm -rf "$work"
}
trap cleanup EXIT

fail() {
	echo "REALM_CLIENT failed: $1"
	exit 1
}

# The native module, with no warnings, copied where realm/client/realm.gdextension looks for it.
if ! (cd godot && cargo build --release -j3) >"$work/build.log" 2>&1; then
	grep -A6 -E "^(error|warning)" "$work/build.log" | head -20
	fail "cargo build (realm/godot)"
fi
if grep -q "^warning" "$work/build.log"; then
	grep -A4 "^warning" "$work/build.log" | head -20
	fail "build warnings (realm/godot)"
fi
if ! (cd godot && cargo test --release -j3 -q) >"$work/test.log" 2>&1; then
	grep -E "panicked|FAILED|error(\[|:)" "$work/test.log" | head -20
	fail "cargo test (realm/godot)"
fi
cp godot/target/release/librealm_godot.so client/bin/ || fail "copy the module"
if ! cargo build --release -j3 >"$work/build.log" 2>&1; then
	grep -A6 -E "^(error|warning)" "$work/build.log" | head -20
	fail "cargo build (realm)"
fi

# Import the client project (the pictures, and the extension list Godot loads the module from).
if ! timeout 120 "$GODOT" --headless --path client --import >"$work/import.log" 2>&1; then
	grep -E "ERROR" "$work/import.log" | head -10
	fail "godot --import"
fi

./target/release/realm-server --port="$SERVER_PORT" --bots=300 --monsters=8000 --rally=0.3 --threads=2 --report=60 >"$work/server.log" 2>&1 &
pids+=($!)
./target/release/realm-loadtest --relay="$RELAY_PORT" --to=127.0.0.1:"$SERVER_PORT" --loss=0.05 --delay-ms=80 --jitter-ms=20 --seed=7 >"$work/relay_proc.log" 2>&1 &
pids+=($!)

run_test() {
	timeout 120 "$GODOT" --headless --path client -s res://tests/follow_test.gd -- --server=127.0.0.1:"$1" --ticks=400 --timeout=90 >"$work/$2.log" 2>&1
	echo $? >"$work/$2.rc"
}
run_test "$SERVER_PORT" direct &
direct=$!
run_test "$RELAY_PORT" relay &
relay=$!
wait "$direct" "$relay"

line() { grep -m1 "^FOLLOW_TEST" "$work/$1.log"; }
field() { line "$1" | grep -Eo "$2=[^ ]+" | head -1 | cut -d= -f2-; }
bad=0
for t in direct relay; do
	if [ "$(cat "$work/$t.rc")" != 0 ]; then
		echo "$t: $(line "$t" || true)"
		grep -E "ERROR|SCRIPT ERROR" "$work/$t.log" | head -5
		bad=1
	fi
done
if ! kill -0 "${pids[0]}" 2>/dev/null; then
	tail -3 "$work/server.log"
	fail "the server stopped"
fi
[ "$bad" = 0 ] || fail "follow test"

# The relay reports every 10 s: its last line covers the whole test (to the server / to the clients).
d_hash=$(line direct | grep -Eo "passed=[0-9]+ failed=[0-9]+")
r_hash=$(line relay | grep -Eo "passed=[0-9]+ failed=[0-9]+")
echo "REALM_CLIENT ok server 300x8000 direct: hashes $d_hash sim_ms=$(field direct sim_ms) in_kb_s=$(field direct in_kb_s) stall_ms_max=$(field direct stall_ms_max) | relay 5% loss 80+-20 ms: hashes $r_hash in_kb_s=$(field relay in_kb_s) stall_ms_max=$(field relay stall_ms_max) mispredicts=$(field relay mispredicts) lost=$(grep RELAY "$work/relay_proc.log" | tail -1 | grep -Eo "[0-9.]+%" | paste -sd/ -)"

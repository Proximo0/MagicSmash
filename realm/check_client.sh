#!/bin/bash
# realm client check: builds the native module (realm/godot) into realm/client/bin, builds the server, starts
# a server with 300 bots and 8 000 monsters and a lossy relay in front of it (5% loss, 80 ms delay, 20 ms
# jitter, each way), then runs realm/client/tests/follow_test.gd twice at once, straight to the server and
# through the relay: 400 ticks each, every hash check must pass. Before that it runs the field client's
# pieces with no server (tests/field_test.gd) and the shell (title, login, hero builder, town, bank, smith,
# merchants, card reader, trainer, sheet, bag, settings, a field gate and back, tests/shell_test.gd) against a
# real realm-gateway; after it, when a display or xvfb-run is there, the real client as the bot for a second at
# zoom 1, 2 and 4 (screenshots in SHOTS_DIR, default a temp dir; the shell's screens in SHELL_SHOTS_DIR).
# Quiet: failures, then one summary line.
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
if ! (cd godot && cargo build --release -j2) >"$work/build.log" 2>&1; then
	grep -A6 -E "^(error|warning)" "$work/build.log" | head -20
	fail "cargo build (realm/godot)"
fi
if grep -q "^warning" "$work/build.log"; then
	grep -A4 "^warning" "$work/build.log" | head -20
	fail "build warnings (realm/godot)"
fi
if ! (cd godot && cargo test --release -j2 -q) >"$work/test.log" 2>&1; then
	grep -E "panicked|FAILED|error(\[|:)" "$work/test.log" | head -20
	fail "cargo test (realm/godot)"
fi
cp godot/target/release/librealm_godot.so client/bin/ || fail "copy the module"
if ! cargo build --release -j2 >"$work/build.log" 2>&1; then
	grep -A6 -E "^(error|warning)" "$work/build.log" | head -20
	fail "cargo build (realm)"
fi

# Import the client project (the pictures, and the extension list Godot loads the module from). On a fresh
# clone the first import does its work and then Godot aborts while quitting; the second one is clean.
import() { (timeout 120 "$GODOT" --headless --path client --import >"$work/import.log" 2>&1) 2>/dev/null; }
if ! import && ! import; then
	grep -E "ERROR" "$work/import.log" | head -10
	fail "godot --import"
fi

# The art gallery: every picture in client/art at game size over each field'"'"'s ground colour, with a 56 px ruler,
# in the shots folder (art_gallery.png, its row names in art_gallery.txt).
gallery_dir="${SHOTS_DIR:-$work/shots}"
mkdir -p "$gallery_dir"
gallery=$(timeout 120 "$GODOT" --headless --path client -s res://tests/art_gallery.gd -- --out="$gallery_dir/art_gallery.png" 2>&1 | grep -m1 "^ART_GALLERY")
if [[ "$gallery" != "ART_GALLERY ok"* ]]; then
	echo "${gallery:-ART_GALLERY printed nothing}"
	fail "art gallery"
fi

field=$(timeout 120 "$GODOT" --headless --path client -s res://tests/field_test.gd 2>&1 | grep -m1 "^FIELD_TEST")
if [[ "$field" != "FIELD_TEST ok"* ]]; then
	echo "${field:-FIELD_TEST printed nothing}"
	fail "field test"
fi

# The shell against a real gateway (dev login and a starter kit for a new hero): every screen once, with a
# screenshot of each when there is somewhere to draw.
./target/release/realm-gateway --db="$work/shell.db" --dev-login --dev-grant --port=0 --field-port=0 --fields=0 --monsters=300 >"$work/gateway.log" 2>&1 &
pids+=($!)
for _ in $(seq 1 50); do grep -q LISTEN "$work/gateway.log" && break; sleep 0.2; done
gw_addr=$(grep -m1 -o "tcp=[^ ]*" "$work/gateway.log" | cut -d= -f2)
[ -n "$gw_addr" ] || fail "the gateway did not start"
shell_runner=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then shell_runner=(xvfb-run -a -s "-screen 0 1440x810x24"); fi
shell_shots="${SHELL_SHOTS_DIR:-$work/shell_shots}"
if [ -n "${DISPLAY:-}" ] || [ ${#shell_runner[@]} -gt 0 ]; then
	shell_line=$(timeout 240 "${shell_runner[@]}" "$GODOT" --path client -s res://tests/shell_test.gd -- --gateway="$gw_addr" --shots="$shell_shots" 2>&1 | grep -E "^SHELL_TEST|^  FAILED" | tr '\n' ' ')
else
	shell_line=$(timeout 240 "$GODOT" --headless --path client -s res://tests/shell_test.gd -- --gateway="$gw_addr" 2>&1 | grep -E "^SHELL_TEST|^  FAILED" | tr '\n' ' ')
fi
if [[ "$shell_line" != *"SHELL_TEST ok"* ]]; then
	echo "${shell_line:-SHELL_TEST printed nothing}"
	fail "shell test"
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

# The real client, drawing: the bot plays one second at each zoom, a screenshot each. Needs somewhere to draw.
shots="skipped (no display)"
runner=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then runner=(xvfb-run -a -s "-screen 0 1440x810x24"); fi
if [ -n "${DISPLAY:-}" ] || [ ${#runner[@]} -gt 0 ]; then
	shots_dir="${SHOTS_DIR:-$work/shots}"
	mkdir -p "$shots_dir"
	if ! timeout 120 "${runner[@]}" "$GODOT" --path client -- --server=127.0.0.1:"$SERVER_PORT" --shots="$shots_dir" --secs=1 --mute >"$work/shots.log" 2>&1; then
		grep -E "CLIENT_FRAMES|ERROR|SCRIPT ERROR" "$work/shots.log" | grep -v ALSA | head -6
		fail "scripted client"
	fi
	for z in 1 2 4; do [ -s "$shots_dir/zoom$z.png" ] || fail "no screenshot at zoom $z"; done
	shots="zoom 1/2/4 $(grep -m1 -Eo 'monsters_drawn=[0-9]+' "$work/shots.log")"
fi

# The relay reports every 10 s: its last line covers the whole test (to the server / to the clients).
d_hash=$(line direct | grep -Eo "passed=[0-9]+ failed=[0-9]+")
r_hash=$(line relay | grep -Eo "passed=[0-9]+ failed=[0-9]+")
echo "REALM_CLIENT ok $(echo "$gallery" | grep -Eo "sprites=[0-9]+" | sed 's/sprites/gallery_sprites/') $(echo "$field" | grep -Eo "checks=[0-9]+" | sed 's/checks/field_test_checks/') $(echo "$shell_line" | grep -Eo "checks=[0-9]+" | sed 's/checks/shell_test_checks/') $(echo "$shell_line" | grep -Eo "shots=[0-9]+" | sed 's/shots/shell_shots/') shots: $shots | server 300x8000 direct: hashes $d_hash sim_ms=$(field direct sim_ms) in_kb_s=$(field direct in_kb_s) stall_ms_max=$(field direct stall_ms_max) | relay 5% loss 80+-20 ms: hashes $r_hash in_kb_s=$(field relay in_kb_s) stall_ms_max=$(field relay stall_ms_max) mispredicts=$(field relay mispredicts) lost=$(grep RELAY "$work/relay_proc.log" | tail -1 | grep -Eo "[0-9.]+%" | paste -sd/ -)"

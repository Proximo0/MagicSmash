#!/bin/bash
# Still pictures of every shell screen (title, builder, town, bank, smith ...): usage stills.sh [out dir, default out].
# Starts a dev gateway and a virtual display, runs realm/client/tests/shell_test.gd with --shots (as
# realm/check_client.sh does), writes <out>/stills/*.png, <out>/stills.log and a contact sheet stills/sheet.png.
# Always exits 0: the log tells what the test found. Prints "STILLS n=<count>" or "STILLS FAILED <why>".
set -u
out="${1:-out}"; mkdir -p "$out"; out=$(cd "$out" && pwd)
cd "$(dirname "$0")/../.."
root=$(pwd)
shots="$out/stills"; log="$out/stills.log"
rm -rf "$shots"; mkdir -p "$shots"
work=$(mktemp -d); : >"$log"
pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT
fail() { echo "STILLS FAILED $*"; echo "STILLS FAILED $*" >>"$log"; exit 0; }

[ -x realm/target/release/realm-gateway ] || fail "realm/target/release/realm-gateway is not built"
export DISPLAY=:98
Xvfb :98 -screen 0 1440x810x24 >/dev/null 2>&1 &
pids+=($!)
sleep 2
realm/target/release/realm-gateway --db="$work/shell.db" --dev-cert --dev-login --dev-grant --bind=127.0.0.1 --port=0 --field-port=0 --fields=0 --monsters=300 >"$work/gateway.log" 2>&1 &
pids+=($!)
for _ in $(seq 1 50); do grep -q LISTEN "$work/gateway.log" && break; sleep 0.2; done
gw=$(grep -m1 -o "tcp=[^ ]*" "$work/gateway.log" | cut -d= -f2)
[ -n "$gw" ] || { cp "$work/gateway.log" "$out/stills_gateway.log"; fail "the gateway did not start (see stills_gateway.log)"; }

timeout 300 godot --path realm/client -s res://tests/shell_test.gd -- --gateway="$gw" --dev-cert="$work/shell.db.dev-cert.pem" --shots="$shots" >"$log" 2>&1
echo "exit=$?" >>"$log"
grep -E "^SHELL_TEST|^  FAILED" "$log" | head -20

n=$(ls "$shots"/*.png 2>/dev/null | wc -l)
[ "$n" -gt 0 ] || fail "no picture was written ($(tail -2 "$log" | cut -c1-200 | tr '\n' ' '))"

# Contact sheet: 4 per row, 480 px wide, file name under each. ImageMagick (on ubuntu-latest); else ffmpeg, no names.
if command -v montage >/dev/null 2>&1; then
	(cd "$shots" && montage -background '#202020' -fill white -pointsize 14 -label '%t' [0-9]*.png -tile 4x -geometry 480x+6+6 sheet.png) >>"$log" 2>&1 || echo "sheet: montage failed" >>"$log"
elif command -v ffmpeg >/dev/null 2>&1; then
	rows=$(( (n + 3) / 4 ))
	(cd "$shots" && ffmpeg -loglevel error -y -pattern_type glob -i '[0-9]*.png' -vf "scale=480:-2,tile=4x$rows:padding=6" -frames:v 1 sheet.png) >>"$log" 2>&1 || echo "sheet: ffmpeg failed" >>"$log"
fi
[ -f "$shots/sheet.png" ] || echo "sheet: not made" >>"$log"
echo "STILLS n=$n"
exit 0

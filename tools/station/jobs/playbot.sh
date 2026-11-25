#!/usr/bin/env bash
# Player-like bots on the live playtest server (docs/realm/ops.md "Player-like bots (playbot)"). A queue `shell` job:
#   queue.sh add kind=shell args="script=playbot secs=900 bots=1" needs=<machine> timeout_s=1800
# Runs realm/client/tests/playbot.gd in the real game client (the copy station job playkit made in
# ~/HordeAndHearthPlay/client) with this station's Godot: it plays through the same input path as a person (keys and
# mouse events), title -> login -> hero -> town -> fields and back, and records frame times, hitches, errors, screens.
# Words: secs=N (default 900), bots=K windows at once (default 1, each its own name and seed), wait=N (seconds to wait
# for a fresh live host, default 300). The host is the one realm/playtest/play.sh finds (lan/host.txt on station-results,
# by its raw URL; STATION_LAN_DIR=dir reads dir/host.txt instead, the local test). PLAYBOT_CLIENT=dir overrides the
# client folder. Linux: the real DISPLAY when set, else xvfb-run. Art: botN/summary.json, botN/*.png, botN.log.
# Last line: PASS playbot ..., `INFO playbot: no live host`, or FAIL playbot <reason>.
set -u
secs=900 bots=1 wait=300
for w in "$@"; do case "$w" in secs=[0-9]*) secs="${w#secs=}" ;; bots=[0-9]*) bots="${w#bots=}" ;; wait=[0-9]*) wait="${w#wait=}" ;; esac; done
[ -n "${STATION_QUEUE_STUB:-}" ] && { echo "PASS playbot stub secs=$secs bots=$bots"; exit 0; }
url=https://raw.githubusercontent.com/Proximo0/MagicSmash/station-results/lan/host.txt
art="${STATION_JOB_ART:-$(mktemp -d)}"; mkdir -p "$art"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
win=""; case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) win=1 ;; esac
gp=$(command -v "${GODOT:-godot}" 2>/dev/null) || { echo "FAIL playbot no Godot (GODOT=${GODOT:-unset})"; exit 1; }
case "$gp" in *_console.exe) ;; *.exe) [ -f "${gp%.exe}_console.exe" ] && gp="${gp%.exe}_console.exe" ;; esac   # one that prints
client="${PLAYBOT_CLIENT:-$HOME/HordeAndHearthPlay/client}"
[ -f "$client/project.godot" ] && [ -d "$client/.godot" ] || { echo "FAIL playbot no imported client in $client (run the playkit job first)"; exit 1; }
# The newest bot from this checkout (the client copy may be older than it).
[ -f realm/client/tests/playbot.gd ] && [ "$(cd "$client" && pwd)" != "$(pwd)/realm/client" ] && { mkdir -p "$client/tests" && cp realm/client/tests/playbot.gd "$client/tests/"; }
[ -f "$client/tests/playbot.gd" ] || { echo "FAIL playbot no tests/playbot.gd in $client"; exit 1; }

# The live host, fresh: state=live, rewritten in the last 15 minutes (playhost rewrites it every 300 s, lanhost every
# ~90 s; a file left by a host that died goes stale), and two minutes or more left.
get() { if [ -n "${STATION_LAN_DIR:-}" ]; then cat "$STATION_LAN_DIR/host.txt" 2>/dev/null; else curl -fsSL "$url?nocache=$RANDOM" 2>/dev/null; fi | tr -d '\r'; }
field() { sed -n "s/^$1=//p" "$work/host.txt" | head -1; }
live() {
	get >"$work/host.txt"
	[ "$(field state)" = live ] || return 1
	upd=$(field updated_epoch); [ -n "$upd" ] && [ "$upd" -ge $(($(date +%s) - 900)) ] || return 1
	end=$(field end_epoch); [ -n "$end" ] && [ $((end - $(date +%s))) -ge 120 ]
}
waited=0
until live; do
	[ "$waited" -ge "$wait" ] && { echo "INFO playbot: no live host"; exit 0; }
	sleep 10; waited=$((waited + 10))
done
sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' "$work/host.txt" >"$work/host.pem"
[ -s "$work/host.pem" ] || { echo "FAIL playbot the host info has no certificate"; exit 1; }
host="$(field machine)"; gw="$(field ip):$(field tcp_port)"
left=$(( $(field end_epoch) - $(date +%s) - 60 ))
[ "$secs" -gt "$left" ] && secs=$left

run=()
if [ -z "$win" ] && [ -z "${DISPLAY:-}" ]; then
	command -v xvfb-run >/dev/null 2>&1 || { echo "FAIL playbot no DISPLAY and no xvfb-run"; exit 1; }
	run=(xvfb-run -a -s "-screen 0 1440x810x24")
fi
wp() { if [ -n "$win" ]; then cygpath -w "$1"; else echo "$1"; fi; }
me=$(hostname 2>/dev/null | tr -cd 'A-Za-z0-9' | cut -c1-8); [ -n "$me" ] || me=STATION
seed0=${STATION_JOB_SEED:-$RANDOM}
echo "playbot: $bots bot(s) for ${secs}s on $host at $gw"
for i in $(seq 1 "$bots"); do
	out="$art/bot$i"; mkdir -p "$out"
	( timeout -k 30 $((secs + 300)) "${run[@]}" "$gp" --path "$(wp "$client")" -s res://tests/playbot.gd -- "--gateway=$gw" \
		"--dev-cert=$(wp "$work/host.pem")" "--secs=$secs" "--out=$(wp "$out")" "--name=$me$i" "--seed=$(( (seed0 % 100000) * 10 + i ))" \
		>"$art/bot$i.log" 2>&1
	  echo $? >"$work/bot$i.rc" ) &
	sleep 5   # windows a moment apart, as people log in
done
wait
ok=0 lines=""
for i in $(seq 1 "$bots"); do
	line=$(grep -a '^PLAYBOT \(ok\|FAILED\)' "$art/bot$i.log" | tail -1)
	[ -n "$line" ] || line="PLAYBOT FAILED no result (rc $(cat "$work/bot$i.rc" 2>/dev/null), $(grep -a -m1 -E 'ERROR|error' "$art/bot$i.log" | cut -c1-100))"
	echo "bot$i $line"
	case "$line" in "PLAYBOT ok "*) ok=$((ok + 1)) ;; esac
	lines="$line"
done
if [ "$ok" -eq "$bots" ]; then
	echo "PASS playbot bots=$bots host=$host ${lines#PLAYBOT ok }"
else
	echo "FAIL playbot ok=$ok/$bots host=$host last: ${lines#PLAYBOT }"
	exit 1
fi

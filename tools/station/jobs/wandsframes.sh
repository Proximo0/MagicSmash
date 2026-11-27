#!/usr/bin/env bash
# station-sac: ok
# (the line above: this job starts only Godot, a signed program, never one built on this PC, so a Smart App Control PC runs it too)
# A queue `shell` job for Four of Wands: the real game drawn on this machine's own graphics, from an immutable imported copy (see
# ../wands_lib.sh): godot --path <tree> -- --autotest=WAVE --players=P --perf (not headless: it must draw). On Linux without a DISPLAY
# it runs under xvfb-run (software GL then: the gpu name says so). Words after script=wandsframes: wave=N (default 15), players=1..4
# (default 4), limit=SECS (default 900). Summary: the GPU and the fields of the PERF frames= line. Frames: $STATION_JOB_ART/frames_<seed>.txt.
# Test mode: WANDS_STUB=1 WANDS_STUB_OUT=<file> reads a canned output instead of starting Godot.
main() {
	WANDS_JOB=wandsframes
	. "$(dirname "$0")/../wands_lib.sh"
	local wave=15 players=4 limit=900 w
	for w in "$@"; do case "$w" in
		wave=*) wave=${w#wave=} ;; players=*) players=${w#players=} ;; limit=*) limit=${w#limit=} ;;
		*) echo "FAIL wandsframes unknown word $w"; return 1 ;; esac
	done
	wands_num "$wave" wave && wands_num "$players" players && wands_num "$limit" limit || return 1
	{ [ "$players" -ge 1 ] && [ "$players" -le 4 ]; } || { echo "FAIL wandsframes players must be 1..4"; return 1; }
	local seed="${STATION_JOB_SEED:-1}" art="${STATION_JOB_ART:-}" tmp="${TMPDIR:-/tmp}"
	wands_prep || return 1
	local log="$tmp/frames.log" rc pre=() perf gpu fields f
	mkdir -p "$tmp/shots"
	case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *)
		if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then pre=(xvfb-run -a -s "-screen 0 1440x810x24"); fi ;; esac
	echo "wandsframes key=$WANDS_KEY seed=$seed started: wave=$wave players=$players"
	wands_run "$limit" "$log" "${pre[@]}" "${GODOT:-godot}" --path "$(wands_native "$WANDS_TREE")" -- --autotest="$wave" --players="$players" --seed="$seed" --perf --out="$(wands_native "$tmp/shots")"; rc=$?
	perf=$(grep '^PERF frames=' "$log" | head -1)
	[ -z "$art" ] || [ ! -d "$art" ] || grep '^PERF' "$log" >"$art/frames_$seed.txt"
	if [ -z "$perf" ]; then
		echo "FAIL wandsframes key=$WANDS_KEY wave=$wave players=$players no PERF frames= line (rc=$rc): $(grep -E 'ERROR|error' "$log" | tail -1 | cut -c1-120 | tr -cd 'A-Za-z0-9 ._:=-')"; return 1
	fi
	gpu=$(grep -m1 'Using Device' "$log" | sed 's/.*Using Device[^:]*: *//')
	[ -n "$gpu" ] || gpu=$(grep -m1 -E 'OpenGL API|Vulkan' "$log")
	gpu=$(printf %s "$gpu" | tr -d '",' | tr -cd 'A-Za-z0-9 ._:=-' | cut -c1-40); : "${gpu:=unknown}"
	fields=""; for f in frames enemies_peak particles draw_calls p50 p95; do
		fields+=" $f=$(grep -o "\b$f=[^ ]*" <<<"$perf" | head -1 | cut -d= -f2)"
	done
	echo "INFO wandsframes key=$WANDS_KEY gpu=\"$gpu\" wave=$wave players=$players$fields"
}
main "$@"

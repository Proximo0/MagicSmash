#!/usr/bin/env bash
# station-sac: ok
# (the line above: this job starts only Godot, a signed program, never one built on this PC, so a Smart App Control PC runs it too)
# A queue `shell` job for Four of Wands: one call of the career tool (tools/career.gd via tools/tool.gd: a bot plays run after run on one
# in-memory profile, buying meta levels, until it wins) from an immutable imported copy of the game (see ../wands_lib.sh), godot, headless.
# Words after script=wandscareer: careers=N (default 2), party=A,B (the tool's --party; a word cannot hold ":", so write "." instead:
# party=casual.knight,casual.priest), hero=NAME, maxruns=N (--max-runs), minutes=N (--minutes), limit=SECS (default 3000).
# Always --until=win and --seed=$STATION_JOB_SEED. Full output: $STATION_JOB_ART/career_<seed>.txt.
# Test mode: WANDS_STUB=1 WANDS_STUB_OUT=<file> reads a canned output instead of starting Godot.
main() {
	WANDS_JOB=wandscareer
	. "$(dirname "$0")/../wands_lib.sh"
	local careers=2 party="" hero="" maxruns="" minutes="" limit=3000 w
	for w in "$@"; do case "$w" in
		careers=*) careers=${w#careers=} ;; party=*) party=${w#party=} ;; hero=*) hero=${w#hero=} ;; maxruns=*) maxruns=${w#maxruns=} ;;
		minutes=*) minutes=${w#minutes=} ;; limit=*) limit=${w#limit=} ;;
		*) echo "FAIL wandscareer unknown word $w"; return 1 ;; esac
	done
	wands_num "$careers" careers && wands_num "$limit" limit || return 1
	[ -z "$maxruns" ] || wands_num "$maxruns" maxruns || return 1
	[ -z "$minutes" ] || wands_num "$minutes" minutes || return 1
	local seed="${STATION_JOB_SEED:-1}" art="${STATION_JOB_ART:-}" tmp="${TMPDIR:-/tmp}"
	wands_prep || return 1
	local args=(career --careers="$careers" --seed="$seed" --until=win) log="$tmp/career.log" rc line err t0=$SECONDS
	[ -z "$party" ] || args+=(--party="${party//./:}"); [ -z "$hero" ] || args+=(--hero="$hero")
	[ -z "$maxruns" ] || args+=(--max-runs="$maxruns"); [ -z "$minutes" ] || args+=(--minutes="$minutes")
	echo "wandscareer key=$WANDS_KEY seed=$seed started: ${args[*]}"
	wands_run "$limit" "$log" "${GODOT:-godot}" --headless --path "$(wands_native "$WANDS_TREE")" -s tools/tool.gd -- "${args[@]}"; rc=$?
	[ -z "$art" ] || [ ! -d "$art" ] || cp "$log" "$art/career_$seed.txt"
	line=$(grep '^CAREER ' "$log" | tail -1); err=$(wands_script_error "$log")
	if [ $rc = 124 ] || [ $rc = 137 ]; then echo "FAIL wandscareer key=$WANDS_KEY seed=$seed timed out after $limit s: $(tail -1 "$log" | cut -c1-120)"; return 1; fi
	if [ -n "$err" ] || [ -z "$line" ]; then echo "FAIL wandscareer key=$WANDS_KEY seed=$seed ${err:-no CAREER line (rc=$rc)}: $(tail -1 "$log" | cut -c1-120)"; return 1; fi
	echo "INFO wandscareer key=$WANDS_KEY seed=$seed wall_s=$((SECONDS - t0)) $(printf %s "$line" | cut -c1-180)"
}
main "$@"

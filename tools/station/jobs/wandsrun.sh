#!/usr/bin/env bash
# station-sac: ok
# (the line above: this job starts only Godot, a signed program, never one built on this PC, so a Smart App Control PC runs it too)
# A queue `shell` job for Four of Wands: whole bot runs (tools/full_run.gd, start to the Archlich) from an immutable imported copy of
# the game (see ../wands_lib.sh), one fresh seed each, to hunt crashes and watch the balance between merges.
# Words after script=wandsrun: runs=N (default 1), wizards=1..4 (default 1 + seed % 4), seal=N, persona=NAME, limit=SECS (one run, default 1800).
# Seed of run i (1..N) = $STATION_JOB_SEED + i. Judged like the merge job `boss`: no FULL_RUN line, an engine SCRIPT ERROR that is not
# a compile error, or UNFINISHED = broken (FAIL); winning or losing is information (INFO). One CSV row per run in $STATION_JOB_ART/wandsrun.csv.
# Test mode: WANDS_STUB=1 WANDS_STUB_OUT=<file> reads a canned output instead of starting Godot.
main() {
	WANDS_JOB=wandsrun
	. "$(dirname "$0")/../wands_lib.sh"
	local runs=1 wizards="" seal="" persona="" limit=1800 w
	for w in "$@"; do case "$w" in
		runs=*) runs=${w#runs=} ;; wizards=*) wizards=${w#wizards=} ;; seal=*) seal=${w#seal=} ;;
		persona=*) persona=${w#persona=} ;; limit=*) limit=${w#limit=} ;;
		*) echo "FAIL wandsrun unknown word $w"; return 1 ;; esac
	done
	wands_num "$runs" runs && wands_num "$limit" limit || return 1
	[ -z "$wizards" ] || { wands_num "$wizards" wizards && [ "$wizards" -ge 1 ] && [ "$wizards" -le 4 ]; } || { echo "FAIL wandsrun wizards must be 1..4"; return 1; }
	[ -z "$seal" ] || [[ "$seal" =~ ^-?[0-9]+$ ]] || { echo "FAIL wandsrun bad seal=$seal"; return 1; }
	[ -z "$persona" ] || [[ "$persona" =~ ^[A-Za-z_]+$ ]] || { echo "FAIL wandsrun bad persona=$persona"; return 1; }
	local base="${STATION_JOB_SEED:-1}" art="${STATION_JOB_ART:-}" tmp="${TMPDIR:-/tmp}"
	wands_prep || return 1
	local godot="${GODOT:-godot}" csv="" i seed wiz log line err why rc t0 wall total0=$SECONDS won=0 lost=0 seeds="" outcome clock
	[ -n "$art" ] && [ -d "$art" ] && { csv="$art/wandsrun.csv"; echo "key,seed,wizards,persona,seal,outcome,clock,wall_s" >"$csv"; }
	for ((i = 1; i <= runs; i++)); do
		seed=$((base + i)); wiz=${wizards:-$((1 + seed % 4))}; log="$tmp/run_$seed.log"; t0=$SECONDS
		local args=(--wizards="$wiz" --seed="$seed"); [ -z "$persona" ] || args+=(--persona="$persona"); [ -z "$seal" ] || args+=(--seal="$seal")
		echo "wandsrun key=$WANDS_KEY run $i/$runs seed=$seed wizards=$wiz started"
		wands_run "$limit" "$log" "$godot" --headless --path "$(wands_native "$WANDS_TREE")" -s tools/full_run.gd -- "${args[@]}"; rc=$?
		wall=$((SECONDS - t0))
		line=$(grep '^FULL_RUN ' "$log" | tail -1); err=$(wands_script_error "$log")
		if [ -z "$line" ] || [ -n "$err" ] || [[ "$line" == *UNFINISHED* ]]; then
			case $rc in 124|137) why="timed out after $limit s" ;; *) why="${err:-${line:-no FULL_RUN line (rc=$rc): $(tail -1 "$log" | cut -c1-80)}}" ;; esac
			[ -z "$csv" ] || echo "$WANDS_KEY,$seed,$wiz,${persona:-default},${seal:-0},BROKEN,,$wall" >>"$csv"
			[ -z "$art" ] || tail -60 "$log" >"$art/run_${seed}_fail.log"
			echo "FAIL wandsrun key=$WANDS_KEY seed=$seed wizards=$wiz: $(printf %s "$why" | tr ',' ';' | cut -c1-160); rerun: godot --headless --path . -s tools/full_run.gd -- --wizards=$wiz --seed=$seed"
			return 1
		fi
		outcome=$(sed -E 's/.* (WON|LOST) at ([0-9:]+).*/\1/' <<<"$line"); clock=$(sed -E 's/.* (WON|LOST) at ([0-9:]+).*/\2/' <<<"$line")
		[ "$outcome" = WON ] && won=$((won + 1)) || lost=$((lost + 1))
		seeds+="${seeds:+,}$seed"
		[ -z "$csv" ] || echo "$WANDS_KEY,$seed,$wiz,${persona:-default},${seal:-0},$outcome,$clock,$wall" >>"$csv"
		echo "run $i: seed=$seed wizards=$wiz $outcome at $clock in $wall s"
		rm -f "$log"
	done
	echo "INFO wandsrun key=$WANDS_KEY runs=$runs won=$won lost=$lost wall_s=$((SECONDS - total0)) seeds=$seeds"
}
main "$@"

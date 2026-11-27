#!/usr/bin/env bash
# Quick test of wands_lib.sh and the three Four of Wands jobs. No Godot run: the import the tree needs is a stub program (GODOT=stub).
# Runs in a throwaway clone of this checkout (git clone --local into a temp folder); nothing is committed in the checkout. Ends with
# one line: `WANDS ok` or the failures.
main() {
	local here root T fails="" GD0
	here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
	T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
	ck() { [ "$2" = "$3" ] || fails+=" [$1: got '$2' want '$3']"; }
	for f in "$here"/jobs/wands*.sh "$here/wands_lib.sh" "$here/wands_test.sh"; do bash -n "$f" 2>/dev/null || fails+=" [bash -n $(basename "$f")]"; done
	git clone -q --local "$root" "$T/clone" 2>/dev/null || { echo "WANDS FAIL: clone failed"; return 1; }
	cd "$T/clone" || return 1
	git config user.email t@t; git config user.name t; git config commit.gpgsign false
	. "$here/wands_lib.sh"
	# A stub engine: --version prints a line; --import takes a few seconds, counts itself, writes the class cache import.sh looks for.
	cat >"$T/godot_stub" <<STUB
#!/usr/bin/env bash
case "\$*" in *--version*) echo stub; exit 0 ;; esac
echo x >>"$T/imports"; sleep \${STUB_SLEEP:-1}; mkdir -p .godot; echo cache >.godot/global_script_class_cache.cfg
STUB
	chmod +x "$T/godot_stub"; export GODOT="$T/godot_stub" TMPDIR="$T"
	local k0 k1 k2 k3
	k0=$(wands_key); ck key-shape "${#k0}" 12
	mkdir -p docs tools/station game; echo a >docs/note.txt; echo b >tools/station/zz.txt; git add -A; git commit -qm docs-and-station
	k1=$(wands_key); ck key-keeps-for-docs-and-station "$k1" "$k0"
	echo c >game/zz_new.gd; git add -A; git commit -qm game; k2=$(wands_key)
	[ "$k2" != "$k0" ] || fails+=" [key-changes-for-game]"
	# the tree: twice = one folder, one build
	local p1 p2 gd; p1=$(wands_tree 2>/dev/null); p2=$(wands_tree 2>/dev/null); gd=$(wands_gd)
	ck tree-path "$p1" "$gd/station_wands/$k2"; ck tree-same "$p2" "$p1"; ck builds-once "$(wc -l <"$T/imports" 2>/dev/null | tr -d ' ')" 1
	[ -f "$p1/.ok" ] && [ -f "$p1/.used" ] && [ -f "$p1/game/zz_new.gd" ] && [ ! -e "$p1/tools/station" ] && [ ! -e "$p1/docs" ] || fails+=" [tree contents]"
	# two callers at once: one build, both get the folder
	echo d >game/zz_two.gd; git add -A; git commit -qm game2; k3=$(wands_key)
	: >"$T/imports"
	( STUB_SLEEP=4 wands_tree >"$T/c1" 2>/dev/null ) & ( sleep 1; wands_tree >"$T/c2" 2>/dev/null ) & wait
	ck concurrent-builds "$(wc -l <"$T/imports" | tr -d ' ')" 1; ck concurrent-same "$(cat "$T/c1")" "$(cat "$T/c2")"; ck concurrent-path "$(cat "$T/c1")" "$gd/station_wands/$k3"
	# garbage collection: another key idle 6 hours goes, a fresh one stays, so does the old tree of k2 (used a moment ago)
	mkdir -p "$gd/station_wands/aaaaaaaaaaaa" "$gd/station_wands/bbbbbbbbbbbb"
	touch "$gd/station_wands/aaaaaaaaaaaa/.ok" "$gd/station_wands/bbbbbbbbbbbb/.ok" "$gd/station_wands/bbbbbbbbbbbb/.used"
	touch -d "6 hours ago" "$gd/station_wands/aaaaaaaaaaaa/.used"
	wands_tree >/dev/null 2>&1
	[ ! -e "$gd/station_wands/aaaaaaaaaaaa" ] || fails+=" [stale tree kept]"
	[ -e "$gd/station_wands/bbbbbbbbbbbb" ] && [ -e "$gd/station_wands/$k2" ] || fails+=" [fresh tree removed]"
	# a lock older than 45 minutes is taken over
	echo e >game/zz_three.gd; git add -A; git commit -qm game3; mkdir "$gd/station_wands/$(wands_key).lock"; touch -d "2 hours ago" "$gd/station_wands/$(wands_key).lock"
	[ -d "$(wands_tree 2>/dev/null)" ] || fails+=" [stale lock not taken over]"
	# the jobs in stub mode
	mkdir -p "$T/art" "$T/out"; export STATION_JOB_ART="$T/art" STATION_JOB_SEED=100 WANDS_STUB=1 WANDS_STUB_OUT="$T/out/o.txt"
	local J="$here/jobs" s rc
	job() { bash "$J/$1.sh" "${@:2}" 2>&1 | tail -1; return "${PIPESTATUS[0]}"; }
	echo "FULL_RUN wizards=2 seed=101 persona=casual LOST at 13:06 (x) score=5" >"$T/out/o.txt"
	s=$(job wandsrun runs=2 wizards=2); rc=$?; ck run-good-rc "$rc" 0
	[[ "$s" == "INFO wandsrun key=$(wands_key) runs=2 won=0 lost=2 wall_s="*" seeds=101,102" ]] || fails+=" [run-good: $s]"
	[ "$(wc -l <"$T/art/wandsrun.csv" | tr -d ' ')" = 3 ] || fails+=" [run csv rows]"
	echo "FULL_RUN wizards=2 seed=101 persona=casual WON at 17:40 (Archlich) score=5" >"$T/out/o.txt"; s=$(job wandsrun wizards=2); [[ "$s" == *"won=1 lost=0"* ]] || fails+=" [run-won: $s]"
	printf 'SCRIPT ERROR: Invalid call\n' >"$T/out/o.txt"; s=$(job wandsrun wizards=2); rc=$?
	{ [ "$rc" != 0 ] && [[ "$s" == "FAIL wandsrun key="*"seed=101 wizards=2: SCRIPT ERROR"*"rerun: godot"* ]]; } || fails+=" [run-bad: $rc $s]"
	echo "FULL_RUN wizards=1 seed=101 persona=casual UNFINISHED at 30:00 score=1" >"$T/out/o.txt"; s=$(job wandsrun wizards=1); [ $? != 0 ] || fails+=" [run-unfinished passes]"
	echo "CAREER casual:mage seal=0 careers=2 | median runs 4" >"$T/out/o.txt"; s=$(job wandscareer careers=2); rc=$?
	{ [ $rc = 0 ] && [[ "$s" == "INFO wandscareer key="*" seed=100 "*"CAREER casual:mage"* ]]; } || fails+=" [career-good: $s]"
	[ -f "$T/art/career_100.txt" ] || fails+=" [career art]"
	echo "nothing" >"$T/out/o.txt"; s=$(job wandscareer); rc=$?; { [ $rc != 0 ] && [[ "$s" == "FAIL wandscareer"* ]]; } || fails+=" [career-bad: $s]"
	printf 'Vulkan 1.3 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce, RTX 4070 "x"\nPERF frames=300 enemies_peak=250 particles=410 draw_calls=88 frame_ms p50=6.1 p95=9.8\nPERF ent_layer 1.00 ms/frame\n' >"$T/out/o.txt"
	s=$(job wandsframes wave=15 players=4); rc=$?
	[[ "$s" == 'INFO wandsframes key='*' gpu="NVIDIA - NVIDIA GeForce RTX 4070 x" wave=15 players=4 frames=300 enemies_peak=250 particles=410 draw_calls=88 p50=6.1 p95=9.8' ]] || fails+=" [frames-good: $s]"
	grep -q 'PERF ent_layer' "$T/art/frames_100.txt" 2>/dev/null || fails+=" [frames art]"
	echo "ERROR: boom" >"$T/out/o.txt"; s=$(job wandsframes); rc=$?; { [ $rc != 0 ] && [[ "$s" == "FAIL wandsframes"* ]]; } || fails+=" [frames-bad: $s]"
	cd "$root"
	if [ -z "$fails" ]; then echo "WANDS ok"; else echo "WANDS FAIL:$fails"; return 1; fi
}
main "$@"

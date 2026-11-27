#!/usr/bin/env bash
# Sourced by the Four of Wands queue jobs (jobs/wands*.sh); not a job itself.
# The tree: an immutable, imported copy of the game's files at HEAD, so a job never runs from the work tree that the next merge
# changes. Folder <git dir>/station_wands/<key>/, key = 12 hex digits of the content of the game paths (tools/station/ left out:
# a commit that changes only docs, realm/, .github/ or tools/station/ keeps the key and so the tree).
# No flock, no GNU-only options: Git Bash on Windows runs this too.

WANDS_PATHS=(project.godot export_presets.cfg icon.svg icon.svg.import game assets tools tests addons)

wands_gd() {  # the absolute git dir of the current checkout (a linked work tree has its own)
	local g; g=$(git rev-parse --git-dir 2>/dev/null) || return 1
	(cd "$g" 2>/dev/null && pwd)
}

wands_key() {  # 12 hex digits of the game's content at HEAD
	git ls-tree -r HEAD -- "${WANDS_PATHS[@]}" 2>/dev/null | grep -v "$(printf '\ttools/station/')" | { sha1sum 2>/dev/null || shasum; } | cut -c1-12
}

wands_native() {  # a path in the form the native Godot wants (Windows style under Git Bash)
	if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi
}

wands_age_gt() {  # $1 = file or folder, $2 = minutes: 0 when it is older than that
	[ -n "$(find "$1" -maxdepth 0 -mmin +"$2" 2>/dev/null)" ]
}

wands_build() {  # $1 = key, $2 = final folder: build in a temp sibling, import, rename into place
	local key=$1 dir=$2 tmp="$2.tmp.$$" top existing try rc=1
	top=$(git rev-parse --show-toplevel) || return 1
	rm -rf "$tmp"; mkdir -p "$tmp" || return 1
	existing=$(git -C "$top" ls-tree --name-only HEAD -- "${WANDS_PATHS[@]}" | tr -d '\r')
	# shellcheck disable=SC2086
	if ! (cd "$top" && git archive HEAD -- $(printf '%s\n' "$existing" | tr '\n' ' ')) | tar -x -C "$tmp"; then
		echo "wands_tree: git archive failed for $key" >&2; rm -rf "$tmp"; return 1
	fi
	rm -rf "$tmp/tools/station"
	for try in 1 2; do
		if (cd "$tmp" && GODOT="${GODOT:-godot}" timeout -k 30 900 bash tools/import.sh >"$tmp.import.log" 2>&1); then rc=0; break; fi
		echo "wands_tree: import of $key failed (try $try): $(tail -2 "$tmp.import.log" 2>/dev/null | tr -d '\r' | tr '\n' ' ' | cut -c1-200)" >&2
		rm -rf "$tmp/.godot"
	done
	rm -f "$tmp.import.log"
	[ $rc = 0 ] || { rm -rf "$tmp"; return 1; }
	[ -f "$dir/.ok" ] && { rm -rf "$tmp"; return 0; }   # another builder finished this key meanwhile (a taken-over lock): its tree may be in use, keep it
	rm -rf "$dir"; mv "$tmp" "$dir" || { rm -rf "$tmp"; return 1; }
	date >"$dir/.ok"
}

wands_gc() {  # $1 = base folder, $2 = key kept: other keys' trees idle for 5 hours (the longest job is 4), stale temp folders
	local d
	for d in "$1"/*/; do
		d=${d%/}; [ -d "$d" ] || continue
		case "$d" in *"/$2") continue ;; *.tmp.*) wands_age_gt "$d" 60 && rm -rf "$d" 2>/dev/null; continue ;; esac
		if [ -f "$d/.used" ]; then wands_age_gt "$d/.used" 300 && rm -rf "$d" 2>/dev/null
		elif [ -f "$d/.ok" ]; then wands_age_gt "$d/.ok" 300 && rm -rf "$d" 2>/dev/null
		fi
	done
	return 0
}

wands_tree() {  # prints the absolute path of the tree for HEAD's key; builds it when missing; non-zero + reason on stderr on failure
	local key gd base dir lock waited=0 got=0
	key=$(wands_key); [ -n "$key" ] || { echo "wands_tree: no key (not a git checkout?)" >&2; return 1; }
	gd=$(wands_gd) || { echo "wands_tree: no git dir" >&2; return 1; }
	base="$gd/station_wands"; dir="$base/$key"; lock="$base/$key.lock"
	mkdir -p "$base" || { echo "wands_tree: cannot create $base" >&2; return 1; }
	while [ ! -f "$dir/.ok" ]; do
		if mkdir "$lock" 2>/dev/null; then
			got=1
			if [ ! -f "$dir/.ok" ]; then
				echo "wands_tree: building $key" >&2
				wands_build "$key" "$dir" || { rmdir "$lock" 2>/dev/null; echo "wands_tree: build of $key failed" >&2; return 1; }
			fi
			rmdir "$lock" 2>/dev/null; break
		fi
		if wands_age_gt "$lock" 45; then echo "wands_tree: taking over a lock older than 45 minutes" >&2; rm -rf "$lock"; continue; fi   # a build is two import tries of 15 minutes at most
		[ $waited -lt 1200 ] || { echo "wands_tree: waited 20 minutes for the build of $key" >&2; return 1; }
		sleep 2; waited=$((waited + 2))
	done
	touch "$dir/.used" 2>/dev/null
	wands_gc "$base" "$key" 2>/dev/null
	printf '%s\n' "$dir"
}

wands_env() {  # private user data for this job's Godot runs: never the PC's own save or log. Needs TMPDIR (the queue gives each job its own).
	# Windows: only APPDATA (where user:// lives). LOCALAPPDATA stays the PC's own: the graphics driver keeps its compiled shaders there,
	# and a frame timing that recompiled them on every run would measure the compiler, not the game.
	local t="${TMPDIR:-/tmp}/wands_user"
	mkdir -p "$t/data" "$t/config" "$t/cache" "$t/appdata"
	case "$(uname -s)" in
		MINGW*|MSYS*|CYGWIN*) export APPDATA="$(wands_native "$t/appdata")" ;;
		*) export XDG_DATA_HOME="$t/data" XDG_CONFIG_HOME="$t/config" XDG_CACHE_HOME="$t/cache" ;;
	esac
}

# wands_run SECS LOG CMD...: the command under timeout, output to LOG (CRs removed afterwards), status returned (124 / 137 = timed out).
# The queue's own kill reaches the command too. WANDS_STUB=1: nothing runs, LOG is a copy of the file WANDS_STUB_OUT (tests).
wands_run() {
	local secs=$1 log=$2 rc; shift 2
	if [ "${WANDS_STUB:-}" = 1 ]; then cat "$WANDS_STUB_OUT" >"$log" 2>/dev/null; return "${WANDS_STUB_RC:-0}"; fi
	timeout -k 30 "$secs" "$@" >"$log" 2>&1 </dev/null & WANDS_PID=$!
	trap 'kill -TERM "$WANDS_PID" 2>/dev/null; exit 143' TERM INT HUP
	wait "$WANDS_PID"; rc=$?
	trap - TERM INT HUP
	tr -d '\r' <"$log" >"$log.nocr" && mv "$log.nocr" "$log"
	return $rc
}

# wands_script_error LOG: the first engine script error that is not a compile error (a bare -s run prints those before it starts).
wands_script_error() {
	grep -E '^SCRIPT ERROR:' "$1" | grep -v 'Compile Error' | head -1 | cut -c1-100
}

wands_num() {  # value, name: 0 when it is a plain number
	local re='^[0-9]+$'; [[ "$1" =~ $re ]] || { echo "FAIL ${WANDS_JOB:-wands} bad word $2=$1"; return 1; }
}

wands_prep() {  # sets WANDS_TREE and WANDS_KEY (stub: no tree) and the private user data. Prints a FAIL line and returns 1 on failure.
	WANDS_KEY=$(wands_key 2>/dev/null); : "${WANDS_KEY:=nokey}"
	wands_env
	if [ "${WANDS_STUB:-}" = 1 ]; then WANDS_TREE="$PWD"; return 0; fi
	WANDS_TREE=$(wands_tree 2>"${TMPDIR:-/tmp}/wands_tree.err") || { echo "FAIL ${WANDS_JOB:-wands} key=$WANDS_KEY no tree: $(tail -2 "${TMPDIR:-/tmp}/wands_tree.err" | tr '\n' ' ' | cut -c1-160)"; return 1; }
}

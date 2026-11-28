#!/usr/bin/env bash
# Refuse paths that must not change. Usage: tools/guard.sh [--base=origin/main] [--] [file ...]
# With files: checks those paths. With none: `git diff --name-only <base>...HEAD` plus staged and unstaged changes.
# Prints each offending path with its reason, then `GUARD problems=N`. Exit 1 when N > 0. Bash 4, no GNU-only flags.
set -u

# Folders refused (path prefix): the shelved other game, import churn, the Sentry addon.
DENY_DIRS=( "realm/" "docs/realm/" "game/crowd/" ".godot/" "addons/sentry/" )
# Suffix refused: Godot import churn.
DENY_SUFFIXES=( ".import" )
# Path globs refused: credential configs (injected at export, never in git).
DENY_GLOBS=( "config/*credentials*" "*/config/*credentials*" )
# File names refused (case-insensitive globs on the name alone): private keys, signing stores, env files.
DENY_NAMES=( "*.pem" "*.key" "*.p12" "*.pfx" "*.keystore" "*.jks" "id_rsa*" "id_ed25519*" ".env" ".env.*" "*.env" )
# A name with "secret" in it is refused only as a data or config file: game/logic/secrets.gd is the game's own module.
SECRET_SUFFIXES=( ".json" ".cfg" ".ini" ".txt" ".yml" ".yaml" ".toml" ".xml" )
# The one name allowed through the fragments above: the shared version pins.
ALLOW_PATHS=( "tools/versions.env" )
# Largest single file allowed, in bytes (25 MB: a music track is 14 to 17 MB; a build or a zip is far more).
MAX_BYTES=26214400

base="origin/main"; files=(); have_files=0
while [ $# -gt 0 ]; do
	case "$1" in
		--base=*) base="${1#--base=}" ;;
		--) shift; while [ $# -gt 0 ]; do files+=("$1"); have_files=1; shift; done; break ;;
		*) files+=("$1"); have_files=1 ;;
	esac
	shift
done

if [ "$have_files" = 0 ]; then
	root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "GUARD problems=1"; echo "not in a git repository" >&2; exit 1; }
	cd "$root" || exit 1
	list=$( { git diff --name-only "$base...HEAD" 2>/dev/null; git diff --name-only --cached; git diff --name-only; } | sort -u)
	while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done <<<"$list"
fi

problems=0
refuse() { echo "$1: $2"; problems=$((problems + 1)); }

for f in ${files[@]+"${files[@]}"}; do
	p="${f#./}"
	reason=""
	for a in "${ALLOW_PATHS[@]}"; do [ "$p" = "$a" ] && continue 2; done
	for d in "${DENY_DIRS[@]}"; do
		case "$p" in "$d"*) reason="under $d (not for this change)" ;; */"$d"*) [ "$d" = ".godot/" ] && reason="under .godot/ (import churn)" ;; esac
		[ -n "$reason" ] && break
	done
	if [ -z "$reason" ]; then for s in "${DENY_SUFFIXES[@]}"; do case "$p" in *"$s") reason="$s file (import churn)" ;; esac; done; fi
	if [ -z "$reason" ]; then for g in "${DENY_GLOBS[@]}"; do case "$p" in $g) reason="credentials config" ;; esac; done; fi
	if [ -z "$reason" ]; then
		base_name="${p##*/}"; lower="${base_name,,}"
		for n in "${DENY_NAMES[@]}"; do case "$lower" in $n) reason="name matches '$n' (key, signing store or env file)" ;; esac; [ -n "$reason" ] && break; done
		if [ -z "$reason" ]; then case "$lower" in *secret*) for x in "${SECRET_SUFFIXES[@]}"; do case "$lower" in *"$x") reason="name contains 'secret' in a $x file" ;; esac; done ;; esac; fi
	fi
	if [ -z "$reason" ] && [ -f "$p" ]; then
		size=$(wc -c <"$p" | tr -d ' ')
		[ "$size" -gt "$MAX_BYTES" ] && reason="file is $size bytes (over $MAX_BYTES)"
	fi
	[ -n "$reason" ] && refuse "$p" "$reason"
done
echo "GUARD problems=$problems"
[ "$problems" = 0 ]

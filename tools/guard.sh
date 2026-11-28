#!/usr/bin/env bash
# Refuse paths that must not change. Usage: tools/guard.sh [--base=origin/main] [--] [file ...]
# With files: checks those paths. With none: `git diff --name-only <base>...HEAD` plus staged and unstaged changes.
# Prints each offending path with its reason, then `GUARD problems=N`. Exit 1 when N > 0. Bash 4, no GNU-only flags.
set -u

# Folders refused (path prefix): the shelved other game, import churn, the Sentry addon.
DENY_DIRS=( "realm/" "docs/realm/" "game/crowd/" ".godot/" "addons/sentry/" )
# An asset's import file (the suffix below) passes only when it enters git beside its asset or leaves with it;
# a change to one that is already in the base is import churn (import_reason).
IMPORT_SUFFIX=".import"
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
# import_reason <path>: why this import file is refused, or nothing when it may pass. It may pass when the base does
# not have it and it lies beside its asset (a new asset), or when the base has it and both it and its asset are gone.
import_reason() {
	local p="$1" src="${1%"$IMPORT_SUFFIX"}"
	git rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1 || { echo "$IMPORT_SUFFIX file (import churn; no base '$base' to compare with)"; return; }
	if git cat-file -e "$base:./$p" 2>/dev/null; then
		{ [ ! -e "$p" ] && [ ! -e "$src" ]; } || echo "$IMPORT_SUFFIX file already in $base (import churn)"
	else
		{ [ -f "$p" ] && [ -f "$src" ]; } || echo "$IMPORT_SUFFIX file without its asset ${src##*/}"
	fi
}

for f in ${files[@]+"${files[@]}"}; do
	p="${f#./}"
	reason=""
	for a in "${ALLOW_PATHS[@]}"; do [ "$p" = "$a" ] && continue 2; done
	for d in "${DENY_DIRS[@]}"; do
		case "$p" in "$d"*) reason="under $d (not for this change)" ;; */"$d"*) [ "$d" = ".godot/" ] && reason="under .godot/ (import churn)" ;; esac
		[ -n "$reason" ] && break
	done
	if [ -z "$reason" ]; then case "$p" in *"$IMPORT_SUFFIX") reason=$(import_reason "$p") ;; esac; fi
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

#!/usr/bin/env bash
# Run a command with a private save folder, so user:// is never the player's own save, settings or log.
# Usage: tools/private_save.sh <command> [args ...]     Exit status: the command's.
# Linux: XDG_DATA_HOME. Windows: APPDATA, the only place Godot looks there (it does not read XDG_DATA_HOME on
# Windows: platform/windows/os_windows.cpp, get_data_path). PRIVATE_SAVE holds the folder on every system: a run
# that must be private compares user:// with it (tests/bot/bot_heroes.gd, save_is_private). The folder is removed
# afterwards. Quiet: prints nothing of its own on success.
set -u
[ $# -gt 0 ] || { echo "usage: tools/private_save.sh <command> [args ...]" >&2; exit 2; }
dir=$(mktemp -d "${TMPDIR:-/tmp}/private_save.XXXXXX") || { echo "private_save: no temp folder" >&2; exit 1; }
trap 'rm -rf "$dir"' EXIT
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*)
		# C:/Users/... : the form a Windows program reads. Git Bash would hand a /tmp/... path over unchanged in some cases.
		native=$(cygpath -m "$dir" 2>/dev/null) || native="$dir"
		APPDATA="$native" PRIVATE_SAVE="$native" "$@" ;;
	*)
		XDG_DATA_HOME="$dir" PRIVATE_SAVE="$dir" "$@" ;;
esac

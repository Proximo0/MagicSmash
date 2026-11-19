#!/usr/bin/env bash
# Shared import step for every tool: runs `godot --import` only when something an import depends on changed.
# A no-op import still costs ~4.6 s, and every tool used to pay it, so "edit a script, run one test" took 5.5 s.
# The fingerprint below takes ~0.1 s and does not change when a function body is edited, so that loop is ~0.7 s.
# FORCE_IMPORT=1 imports anyway. Holds /tmp/<project>_import.lock (the only lock any tool takes).
# Quiet: prints the import log only on failure.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
STAMP=".godot/import.stamp"
LOG="/tmp/$(basename "$PWD")_import.log"
if command -v flock >/dev/null 2>&1; then  # one import at a time; Git Bash on Windows has no flock and skips this
  exec 9>"/tmp/$(basename "$PWD")_import.lock"
  flock 9
fi
# What an import depends on: the Godot version, which files exist, the declarations at the top of each script (the
# class cache holds class_name, extends, @tool, @icon and @abstract), project.godot, and the size and time of every
# file that has an .import sidecar (images, audio, fonts). Scripts are read from source at run time, so a body edit
# needs no import.
fingerprint() {
  local skip=(\( -path ./.godot -o -path ./.git -o -path ./build -o -path ./out \) -prune -o -type f)
  { "$GODOT" --version 2>/dev/null
    find . "${skip[@]}" -print | LC_ALL=C sort
    find . "${skip[@]}" -name '*.gd' -print0 | LC_ALL=C sort -z \
      | xargs -0 -r grep -HE '^(class_name|extends|@tool|@icon|@abstract)' 2>/dev/null
    find . "${skip[@]}" -name '*.import' -print | LC_ALL=C sort \
      | while IFS= read -r i; do stat -c '%n %s %Y' "${i%.import}" "$i" 2>/dev/null; done
    stat -c '%n %s %Y' project.godot
  } | md5sum | cut -d' ' -f1
}
fp=$(fingerprint)
if [[ "${FORCE_IMPORT:-0}" != 1 && -f "$STAMP" && -f .godot/global_script_class_cache.cfg && "$(cat "$STAMP")" == "$fp" ]]; then
  exit 0
fi
rm -f "$STAMP"
"$GODOT" --headless --path . --import >"$LOG" 2>&1 || { cat "$LOG"; exit 1; }
# The stamp is the fingerprint from before the import, so a file added while it ran triggers another import next time
# (as does the .uid file the import writes for a new script: one extra import, never a stale cache).
echo "$fp" >"$STAMP"

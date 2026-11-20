#!/usr/bin/env bash
# A map of a script instead of the script: its section banners, inner classes and functions, each with the lines
# it spans. Read this first, then read only the function you need (sed -n '1114,1284p' game/logic/world.gd).
# A big script costs thousands of tokens to read whole; its outline is a few KB.
# Usage: tools/outline.sh <file.gd> [...]
set -uo pipefail
[ $# -gt 0 ] || { echo "usage: tools/outline.sh <file.gd> [...]" >&2; exit 2; }
for f in "$@"; do
  [ -f "$f" ] || { echo "outline: no such file: $f" >&2; exit 2; }
  [ $# -gt 1 ] && echo "== $f"
  awk '
    function flush(last) { if (start) printf "%d-%d %s\n", start, last, sig; start = 0 }
    /^# ?=+ .* =+ *$/ { flush(NR - 1); gsub(/^# ?=+ | =+ *$/, ""); print "## " $0; next }
    /^(static )?func [A-Za-z_]/ || /^class [A-Za-z_]/ {
      flush(NR - 1); start = NR; sig = $0
      sub(/^func /, "", sig); sub(/ -> void:$/, "", sig); sub(/:$/, "", sig); next }
    END { flush(NR) }
  ' "$f"
done

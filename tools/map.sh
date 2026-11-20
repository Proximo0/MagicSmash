#!/usr/bin/env bash
# A map of the project's scripts: one line per .gd file (path, KB, class_name, first ## doc line), then a summary.
# Read this first to find the script you need; then use tools/outline.sh <file> and read by line range.
# Usage: tools/map.sh [dir ...]   (default: game tools tests)
set -uo pipefail
[ $# -gt 0 ] || set -- game tools tests
for d in "$@"; do [ -d "$d" ] || { echo "map: no such dir: $d" >&2; exit 2; }; done
mapfile -t files < <(find "$@" -name '*.gd' -type f 2>/dev/null | LC_ALL=C sort)
awk '
  function emit() { if (path != "") { printf "%s %.1fK%s%s\n", path, size / 1024, (cls != "" ? " " cls : ""), (doc != "" ? "  " substr(doc, 1, 90) : ""); n++; kb += size / 1024 } }
  FNR == 1 { emit(); path = FILENAME; size = 0; cls = ""; doc = "" }
  { size += length($0) + 1 }
  cls == "" && /^class_name [A-Za-z_]/ { cls = $2 }
  doc == "" && /^## ?[^#]/ { doc = $0; sub(/^## ?/, "", doc) }
  END { emit(); printf "MAP scripts=%d kb=%.0f\n", n, kb }
' "${files[@]}"

#!/usr/bin/env bash
# Queue `shell` job: make the rigged base body of one race with Blender + MPFB (installed by jobs/blender.sh) and
# publish it as an artifact (<machine>-<race>.glb, under the 2 MB cap), for the 3D character route.
# Queue it: queue.sh add kind=shell args="script=charbody race=human" needs=<machine> priority=9 repeat=once timeout_s=900
# Summary line: PASS|FAIL charbody race=.. verts=.. bones=.. bytes=..
set -u
race=human
for a in "$@"; do case "$a" in race=*) race="${a#race=}" ;; esac; done
case "$race" in *[!a-z,]*) echo "FAIL charbody bad race '$race'"; exit 1 ;; esac
T="${HH_TOOLS:-$HOME/hh_tools}"; art="${STATION_JOB_ART:-${TMPDIR:-/tmp}}"; mkdir -p "$art"
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) exe=blender.exe; p() { cygpath -w "$1"; } ;; *) exe=blender; p() { echo "$1"; } ;; esac
B=$(find "$T/blender" -maxdepth 2 -name "$exe" -type f 2>/dev/null | head -1)
[ -n "$B" ] || { [ -s "$T/blender_path" ] && B=$(head -1 "$T/blender_path"); }   # the owner's own Blender, found by jobs/blender.sh
[ -n "$B" ] && [ -d "$T/mpfb2/src/mpfb" ] || { echo "FAIL charbody Blender or MPFB missing under $T (run script=blender first)"; exit 1; }
repo="$(cd "$(dirname "$0")/../../.." && pwd)"; tmp=$(mktemp -d); log="$art/charbody-$race.txt"
"$B" -b --factory-startup --python "$(p "$repo/tools/char3d/make_body.py")" -- "$(p "$T/mpfb2/src")" "$(p "$tmp")" "$race" >"$tmp/log.txt" 2>&1
grep -aE "^(BODY|BONES|NOTE|BODYFAIL)|Error|Traceback" "$tmp/log.txt" | tr -d '\r' | cut -c1-1500 >"$log"
n=0; for f in "$tmp"/*.glb; do [ -s "$f" ] && { cp "$f" "$art/"; n=$((n + 1)); }; done
line=$(grep -a "^BODY " "$log" | tr '\n' ';' | cut -c1-500)
rm -rf "$tmp"
if [ "$n" -gt 0 ]; then echo "PASS charbody made=$n ${line#BODY }"; else echo "FAIL charbody $(tail -3 "$log" | tr '\n' ' ' | cut -c1-400)"; exit 1; fi

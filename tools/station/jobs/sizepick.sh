#!/usr/bin/env bash
# Queue `shell` job: show the hero size-pick scene (realm/client/tests/size_pick.tscn) fullscreen on one screen of this
# station for secs seconds, so Curtis can compare the 56 px and 112 px heroes on the real monitor. Needs Godot (GODOT or
# `godot` on PATH) and a display. Builds and installs the native module the way station.sh's `frames` job does (the
# scene needs no server, but FieldArt names the module's RealmLink class). Queue it:
#   queue.sh add kind=shell args="script=sizepick screen=1 secs=900" needs=<machine>
# Summary: PASS sizepick shown secs=<n> screen=<n> heights=A=..,B=..   (FAIL sizepick <why> otherwise)
cd "$(dirname "$0")/../../.." || exit 2
secs=900; screen=0
for w in "$@"; do case "$w" in secs=[0-9]*) secs="${w#secs=}" ;; screen=[0-9]*) screen="${w#screen=}" ;; esac; done
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || { echo "FAIL sizepick Godot is not installed on this station (set GODOT)"; exit 1; }
command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
dir="${TMPDIR:-/tmp}/station-sizepick"; rm -rf "$dir"; mkdir -p "$dir"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) lib=realm_godot.dll ;; Darwin) lib=librealm_godot.dylib ;; *) lib=librealm_godot.so ;; esac
if [ ! -f "realm/client/bin/$lib" ]; then
  command -v cargo >/dev/null 2>&1 || { echo "FAIL sizepick cargo is not installed and realm/client/bin/$lib is missing"; exit 1; }
  ( cd realm/godot && cargo build --release -j2 -q ) >"$dir/build.log" 2>&1 && cp "realm/godot/target/release/$lib" realm/client/bin/ \
    || { echo "FAIL sizepick build: $(tail -2 "$dir/build.log" | tr '\n' ' ' | cut -c1-160)"; exit 1; }
fi
# A fresh clone's first import does its work and then aborts while quitting: the second is clean.
( timeout 180 "$GODOT" --headless --path realm/client --import || timeout 180 "$GODOT" --headless --path realm/client --import ) >"$dir/import.log" 2>&1 || true
runner=()
if [ -z "${DISPLAY:-}" ] && [ "$(uname -s)" = Linux ] && command -v xvfb-run >/dev/null 2>&1; then runner=(xvfb-run -a -s "-screen 0 1920x1080x24"); fi
out=$(timeout $((secs + 120)) "${runner[@]}" "$GODOT" --path realm/client res://tests/size_pick.tscn -- --fullscreen --screen="$screen" --secs="$secs" 2>&1)
line=$(grep '^SIZEPICK shown ' <<<"$out" | tail -1)
rm -rf "$dir"
if [ -z "$line" ]; then echo "FAIL sizepick the scene did not finish: $(tail -2 <<<"$out" | tr '\n' ' ' | cut -c1-160)"; exit 1; fi
echo "PASS ${line/SIZEPICK /sizepick }"

#!/usr/bin/env bash
# A hash trace: bots play each seed and the state hash (and the --fields hash) is printed every second of game
# time, one "TRACE seed= t= hash= fields=" line each, so a refactor can be shown to leave the game identical:
#   tools/hash_trace.sh > before.txt; <move code>; tools/hash_trace.sh > after.txt; diff before.txt after.txt
# Usage: tools/hash_trace.sh   (TRACE_SEEDS="7 21" TRACE_SECONDS=120 TRACE_PLAYERS=4 TRACE_EVERY=1)
# Two seeds run at once. Last line: TRACE_DONE lines=n (n = seeds x seconds / every when every run finished).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
tools/import.sh || { echo "TRACE FAIL import"; exit 2; }
TMP=$(mktemp -d "/tmp/trace.$(basename "$PWD").XXXXXX")
trap 'rm -rf "$TMP"' EXIT
for s in ${TRACE_SEEDS:-7 21}; do
  ( timeout 900 "$GODOT" --headless --path . -s tools/tool.gd -- golden_run "--seed=$s" "--seconds=${TRACE_SECONDS:-120}" \
      "--players=${TRACE_PLAYERS:-4}" "--every=${TRACE_EVERY:-1}" --trace >"$TMP/$s.log" 2>&1 ) &
done
wait
n=0
for s in ${TRACE_SEEDS:-7 21}; do
  grep -E '^(TRACE|SCRIPT ERROR|ERROR)' "$TMP/$s.log"
  n=$((n + $(grep -c '^TRACE' "$TMP/$s.log")))
done
echo "TRACE_DONE lines=$n"

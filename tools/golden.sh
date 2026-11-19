#!/usr/bin/env bash
# Did this change alter the game? Plays the same seeded bot runs in the working tree and in a base commit and
# compares the state hash every 15 s of game time (tools/golden_run.gd). One line per seed, then the summary:
#   GOLDEN same seeds=2             identical runs: the change did not alter the game
#   GOLDEN changed seeds=1 of 2     and, per seed, the first game second at which the two runs part ways
# A refactor, a speed-up or a tooling change must say "same". A feature or a balance change is expected to say
# "changed". Nothing is stored in the repo, so parallel pull requests never conflict over a golden value.
# Usage: tools/golden.sh [base-ref]     (default origin/main; GOLDEN_SEEDS="7 21" GOLDEN_SECONDS=90)
# Exit 0 same, 1 changed, 2 could not compare. About 30 s on four cores.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
BASE="${1:-origin/main}"
SEEDS="${GOLDEN_SEEDS:-7 21}"
SECS="${GOLDEN_SECONDS:-90}"
git rev-parse --verify -q "$BASE^{commit}" >/dev/null || { echo "GOLDEN FAIL no such commit: $BASE"; exit 2; }
tools/import.sh || { echo "GOLDEN FAIL import"; exit 2; }
TMP=$(mktemp -d "/tmp/golden.$(basename "$PWD").XXXXXX")
cleanup() { git worktree remove --force "$TMP/base" >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT
git worktree add -q --detach "$TMP/base" "$BASE" || { echo "GOLDEN FAIL could not check out $BASE"; exit 2; }
# The same probe plays both trees, even when the base commit is older than the probe.
cp tools/tool.gd tools/golden_run.gd "$TMP/base/tools/"
"$GODOT" --headless --path "$TMP/base" --import >"$TMP/import.log" 2>&1 || { cat "$TMP/import.log"; echo "GOLDEN FAIL base import"; exit 2; }
for s in $SEEDS; do
  for tree in base head; do
    dir="$PWD"; [ "$tree" = base ] && dir="$TMP/base"
    ( timeout 600 "$GODOT" --headless --path "$dir" -s tools/tool.gd -- golden_run "--seed=$s" "--seconds=$SECS" \
        >"$TMP/$tree.$s.log" 2>&1 ) &
  done
done
wait
changed=0; total=0
for s in $SEEDS; do
  total=$((total + 1))
  b=$(grep -m1 '^GOLDEN seed=' "$TMP/base.$s.log"); h=$(grep -m1 '^GOLDEN seed=' "$TMP/head.$s.log")
  if [ -z "$b" ] || [ -z "$h" ]; then
    for tree in base head; do grep -q '^GOLDEN seed=' "$TMP/$tree.$s.log" || { echo "--- $tree, seed $s:"; grep -vE '^(Godot Engine v|$)' "$TMP/$tree.$s.log" | tail -15; }; done
    echo "GOLDEN FAIL seed $s did not finish (see above)"; exit 2
  fi
  if [ "$b" = "$h" ]; then
    echo "GOLDEN seed=$s same"
    continue
  fi
  changed=$((changed + 1))
  IFS=, read -ra bm <<<"${b##*marks=}"; IFS=, read -ra hm <<<"${h##*marks=}"
  at="after the last mark, or only in the run's record"
  for i in "${!bm[@]}"; do
    if [ "${bm[$i]}" != "${hm[$i]:-}" ]; then at="by $(( (i + 1) * 15 )) s of game time (still the same at $(( i * 15 )) s)"; break; fi
  done
  echo "GOLDEN seed=$s changed $at"
done
if (( changed > 0 )); then
  echo "GOLDEN changed seeds=$changed of $total against $BASE"
  exit 1
fi
echo "GOLDEN same seeds=$total against $BASE"

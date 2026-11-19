#!/usr/bin/env bash
# Engine-free unit tests, headless. Usage: tools/run_tests.sh [test_name]
# All files: JOBS Godot processes (default: CPU count) share one queue of test methods. Quiet: on a pass it prints
# only the summary line; on a failure it prints every failing process's output (FAIL lines, engine errors).
# A test fails if an assert fails, if the engine logs an error while it runs (a script error abandons the test
# function), if it runs no assert at all, or if it takes longer than a unit test should (see tests/runner.gd).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
FILTER='^(Godot Engine v|$|WARNING: .*audio|   at: )'
# Refresh the class_name cache so new classes resolve (skipped when nothing an import needs changed).
tools/import.sh || exit 1
if [ $# -gt 0 ]; then
  "$GODOT" --headless --path . -s res://tests/runner.gd -- "--only=$1" 2>&1 | grep -vE "$FILTER"
  exit "${PIPESTATUS[0]}"
fi
files=$(ls tests/unit/test_*.gd | wc -l)
JOBS="${JOBS:-$(nproc)}"
(( JOBS > files )) && JOBS=$files
OUT=$(mktemp -d "/tmp/tests.$(basename "$PWD").XXXXXX")
mkdir "$OUT/claims"  # one dir per test method taken; the processes share this queue (see tests/runner.gd)
for ((i = 0; i < JOBS; i++)); do
  ( "$GODOT" --headless --path . -s res://tests/runner.gd -- "--claims=$OUT/claims" >"$OUT/$i.log" 2>&1
    echo $? >"$OUT/$i.rc" ) &
done
wait
passed=0; failed=0; rc=0
for ((i = 0; i < JOBS; i++)); do
  line=$(grep -E '^TESTS passed=' "$OUT/$i.log" | tail -1)
  if [[ "$line" =~ passed=([0-9]+)\ failed=([0-9]+) ]]; then
    passed=$((passed + BASH_REMATCH[1])); failed=$((failed + BASH_REMATCH[2]))
  else
    failed=$((failed + 1)); echo "test process $i crashed:"
  fi
  if [ "$(cat "$OUT/$i.rc")" != 0 ] || [ -z "$line" ]; then
    rc=1
    grep -vE "$FILTER" "$OUT/$i.log" | grep -v '^TESTS passed='
  fi
done
rm -rf "$OUT"
(( passed + failed == 0 )) && rc=1  # nothing ran at all
echo "TESTS passed=$passed failed=$failed"
exit "$rc"

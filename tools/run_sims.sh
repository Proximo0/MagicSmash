#!/usr/bin/env bash
# Regression sims, headless. Usage: tools/run_sims.sh [sim_name ...]
# Runs tests/sim/sim_suite.tscn once per sim file (SIM_FILES in sim_suite.gd), all in parallel: the sims are CPU-bound,
# so the total is about the slowest one rather than the sum. Prints one "SIM <name> PASS|FAIL <detail>" line per
# scenario (INFO = report only) and one "SIMS passed=N failed=M total=T". Exit 1 on any failure or if a run dies
# before printing its totals.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# Only the import needs the shared lock; the scene runs take none.
(flock 9; "$GODOT" --headless --path . --import) 9>"/tmp/$(basename "$PWD")_import.lock" >/tmp/godot_import.log 2>&1 || { cat /tmp/godot_import.log; exit 1; }
if [ $# -gt 0 ]; then
  sims=("$@")
else
  mapfile -t sims < <(sed -n '/^const SIM_FILES/,/^]/p' tests/sim/sim_suite.gd | grep -oE '"sim_[a-z0-9_]+"' | tr -d '"')
fi
OUT=$(mktemp -d "/tmp/sims.$(basename "$PWD").XXXXXX")
for s in "${sims[@]}"; do
  ( timeout 600 "$GODOT" --headless --path . res://tests/sim/sim_suite.tscn -- "$s" >"$OUT/$s.log" 2>&1 ) &
done
wait
passed=0; failed=0
for s in "${sims[@]}"; do
  out=$(grep -vE '^(Godot Engine v|$|WARNING: .*audio|   at: )' "$OUT/$s.log")
  echo "$out" | grep -v '^SIMS passed='
  totals=$(echo "$out" | grep '^SIMS passed=' | tail -1)
  if [[ -z "$totals" ]]; then
    echo "SIM $s FAIL ended without printing its SIMS totals (crash, script error or timeout)"
    failed=$((failed + 1)); continue
  fi
  p=${totals#SIMS passed=}; p=${p%% *}
  f=${totals##*failed=}
  passed=$((passed + p)); failed=$((failed + f))
done
rm -rf "$OUT"
echo "SIMS passed=$passed failed=$failed total=$((passed + failed))"
(( failed > 0 )) && exit 1
exit 0

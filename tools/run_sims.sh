#!/usr/bin/env bash
# Regression sims, headless. Usage: tools/run_sims.sh [sim_name ...] [--except=sim_name]
# Runs tests/sim/sim_suite.tscn once per sim file (SIM_FILES in sim_suite.gd), all in parallel: the sims are CPU-bound,
# so the total is about the slowest one rather than the sum. Prints one "SIM <name> PASS|FAIL <detail>" line per
# scenario (INFO = report only) and one "SIMS passed=N failed=M total=T". Exit 1 on any failure or if a run dies
# before printing its totals. sim_horde asserts a per-step budget in CPU time (see its header), which holds on a
# busy machine; CI still gives it a runner of its own (--except=sim_horde on the other row).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
tools/import.sh || exit 1
except=""; sims=()
for a in "$@"; do
  case "$a" in --except=*) except="${a#--except=}" ;; *) sims+=("$a") ;; esac
done
if [ ${#sims[@]} -eq 0 ]; then
  mapfile -t sims < <(sed -n '/^const SIM_FILES/,/^]/p' tests/sim/sim_suite.gd | grep -oE '"sim_[a-z0-9_]+"' | tr -d '"' \
    | grep -vxF "${except:-//none//}")
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

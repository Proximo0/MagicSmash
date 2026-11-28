#!/usr/bin/env bash
# Every check at once, in parallel: unit tests, sims, lint, and two optional hooks that are skipped when their
# scene does not exist: the play-bot (tests/bot/bot.tscn) and the lab (tests/lab/lab.tscn).
# JOBS (default: CPU count) caps how many Godot processes run together.
# BOT_LIMIT (default 240) is the longest one bot shard may run, in seconds: a slow station passes more (station.sh).
# Usage: tools/check_all.sh. Logs go to /tmp/check.<repo>.XXXXXX/<name>.log (path printed in the header); the last lines print one summary row per check.
# Exit 1 if any check fails.
#
# Hook contract: a bot/lab scene prints "BOT ..." / "LAB ..." lines, any line containing " FAIL " fails the check,
# and a scene that exits non-zero fails it too. Add shards by adding TASKS rows (see the BOT block).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
JOBS="${JOBS:-$(nproc)}"
BOT_LIMIT="${BOT_LIMIT:-240}"; case "$BOT_LIMIT" in ''|*[!0-9]*) BOT_LIMIT=240 ;; esac
OUT=$(mktemp -d "/tmp/check.$(basename "$PWD").XXXXXX")  # per run, so two check_all runs never share logs
FILTER='^(Godot Engine v|$|WARNING: .*audio|   at: )'
start=$(date +%s)
tools/import.sh || { echo "CHECK_ALL FAIL (import)"; exit 1; }

# One command per line: name|command.
BOT_SHARDS=3
COVER_SHARDS=2
TASKS=()
HAVE_BOT=0; [[ -f tests/bot/bot.tscn ]] && HAVE_BOT=1
HAVE_LAB=0; [[ -f tests/lab/lab.tscn ]] && HAVE_LAB=1
if (( HAVE_BOT )); then
  for ((i = 0; i < BOT_SHARDS; i++)); do
    TASKS+=("bot$i|timeout $BOT_LIMIT $GODOT --headless --fixed-fps 60 --path . res://tests/bot/bot.tscn -- --shard=$i --nshards=$BOT_SHARDS")
  done
  # The hero shard and its three kin (boss, win, again): saved heroes seated in an in-memory profile, each in a private
  # save folder of its own (tools/private_save.sh: it works on Windows too; docs/bots.md).
  for m in heroes boss win again; do
    TASKS+=("bot$m|tools/private_save.sh timeout $BOT_LIMIT $GODOT --headless --fixed-fps 60 --path . res://tests/bot/bot.tscn -- --$m")
  done
  # The coverage robot (tests/bot/bot_cover.gd): each shard deals its share of the rows one by one, about 1.6 s of wall
  # time a row here plus 5 s to boot. Keep a shard under about 18 rows (90 s); the finished list (~110 rows) takes 6.
  for ((i = 0; i < COVER_SHARDS; i++)); do
    TASKS+=("botcover$i|timeout $BOT_LIMIT $GODOT --headless --fixed-fps 60 --path . res://tests/bot/bot.tscn -- --cover --shard=$i --nshards=$COVER_SHARDS")
  done
fi
LAB_LIMIT=600
(( HAVE_LAB )) && TASKS+=("lab|timeout $LAB_LIMIT $GODOT --headless --fixed-fps 60 --path . res://tests/lab/lab.tscn")
# The horde's step budget is doubled here: this script's other Godot processes slow it through shared caches even in
# CPU time. CI's sims-horde row runs alone and holds the real budget.
TASKS+=("sims|SIM_BUDGET_SCALE=${SIM_BUDGET_SCALE:-2} tools/run_sims.sh")  # a slow station passes a larger scale
TASKS+=("unit|tools/run_tests.sh")
TASKS+=("lint|tools/lint.sh")

running=0
for t in "${TASKS[@]}"; do
  name="${t%%|*}"; cmd="${t#*|}"
  while (( running + 1 > JOBS )); do wait -n; running=$((running - 1)); done
  ( eval "$cmd" 2>&1 | grep -vE "$FILTER" >"$OUT/$name.log"; echo "${PIPESTATUS[0]}" >"$OUT/$name.rc" ) &
  running=$((running + 1))
done
wait

rc=0
row() { printf '%-10s %s\n' "$1" "$2"; }
echo "=== check_all ($(( $(date +%s) - start )) s, $JOBS jobs, logs $OUT) ==="
u=$(grep -E '^TESTS passed=' "$OUT/unit.log" | tail -1); row unit "${u:-CRASH}"
if [[ "$u" != *"failed=0"* ]]; then
  rc=1
  # Which test files fail and how often, then the first failures: a station's report has room for a few lines only.
  files=$(grep -E '^FAIL ' "$OUT/unit.log" | sed -E 's/^FAIL ([^: ]+)::.*/\1/' | sort | uniq -c | awk '{ printf "%s(%s) ", $2, $1 }')
  [[ -z "$files" ]] || echo "    unit FAIL in: ${files% }"
  grep -E '^(LOAD )?FAIL ' "$OUT/unit.log" | head -3 | cut -c1-200 | sed 's/^/    /'
fi
s=$(grep -E '^SIMS passed=' "$OUT/sims.log" | tail -1); row sims "${s:-CRASH}"
[[ "$s" == *"failed=0"* ]] || rc=1
grep -E '^SIM .* FAIL ' "$OUT/sims.log" | sed 's/^/    /'
# Optional hooks: pass = every shard exited 0 and printed no " FAIL " line.
hook() {  # hook <label> <log glob prefix> <line prefix> <time limit, s>
  local label="$1" pre="$2" lp="$3" limit="$4" n=0 bad=0 f code why last stopped=()
  for f in "$OUT/$pre"*.log; do
    [[ -e "$f" ]] || continue
    n=$((n + 1))
    # A shard that stopped without a FAIL line of its own (the time limit, a crash) is named here with its exit status,
    # so that a station's report says which shard and why. 124 is `timeout`'s status.
    code=$(cat "${f%.log}.rc" 2>/dev/null)
    if [[ "$code" != "0" ]]; then
      bad=$((bad + 1))
      why="exit ${code:-unknown}"; [[ "$code" == "124" ]] && why="stopped at the $limit s limit"
      last=$(grep -E "^$lp " "$f" | tail -1 | cut -c1-110)
      stopped+=("$(basename "${f%.log}") FAIL $why; its last $lp line: ${last:-none}")
    fi
    grep -q "^$lp .* FAIL " "$f" && bad=$((bad + 1))
    # An engine error line fails a bot run too (tests/bot/no_engine_errors.sh has the rule).
    if [[ "$lp" == BOT ]] && ! tests/bot/no_engine_errors.sh "$f" >"$f.err"; then bad=$((bad + 1)); head -3 "$f.err" | sed 's/^/    /'; fi
  done
  row "$label" "shards=$n failed=$bad"
  (( ${#stopped[@]} == 0 )) || printf '    %s\n' "${stopped[@]}"
  grep -hE "^$lp .* FAIL " "$OUT/$pre"*.log 2>/dev/null | sed 's/^/    /'
  (( bad == 0 ))
}
if (( HAVE_BOT )); then hook bot bot BOT "$BOT_LIMIT" || rc=1; else row bot "skipped (no tests/bot/bot.tscn)"; fi
if (( HAVE_LAB )); then hook lab lab LAB "$LAB_LIMIT" || rc=1; else row lab "skipped (no tests/lab/lab.tscn)"; fi
lint=$(tail -1 "$OUT/lint.log"); row lint "$lint"; [[ "$lint" == *"problems=0"* ]] || rc=1
if (( rc == 0 )); then echo "CHECK_ALL PASS"; else echo "CHECK_ALL FAIL (see rows above)"; fi
exit $rc

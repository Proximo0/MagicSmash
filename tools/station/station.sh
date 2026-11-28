#!/usr/bin/env bash
# A station: a spare computer that runs long jobs with no Claude on it and reports a few lines.
# Usage: tools/station/station.sh [--watch] [--no-push] job [job ...]
#   jobs: realm   Horde & Hearth: realm/check.sh and realm/store/check.sh (the Rust core, server and store). Needs cargo;
#                 a station without it reports FAIL.
#         soak    bots through the wire server (gateway, towns, field hosts, store) for STATION_SOAK_SECS (default 7200),
#                 one summary line; FAIL when the line is not "SOAK ok" (a mismatch, a bot error or a store problem)
#         world   the world's long proof (realm-world): STATION_WORLD_BOTS (default 200) bots live STATION_WORLD_DAYS (default 7)
#                 days of the realm clock in STATION_WORLD_SECS (default 600, a short soak so a merge never holds the station for hours)
#                 with hosts at 20 Hz: copies open and merge, the queue, vaults, a field host killed halfway; FAIL when the line is not
#                 "WORLD ok". The 7200 s run is the queue's `shell` job `script=worldlong` (tools/station/jobs/worldlong.sh).
#         economy Horde & Hearth's market simulation (realm-economy, record only): STATION_ECONOMY_BOTS (default 4000) bots for
#                 STATION_ECONOMY_DAYS (default 180) game days with a fresh seed; one line of the sim's summary
#         ops     Horde & Hearth's operations rehearsal (realm-ops rehearse): a store with play, an online backup with writes going on,
#                 the live file wrecked and restored, the restore drill, a release, a rollback and the schema-downgrade refusal;
#                 one line, FAIL when it is not "OPS ok". Also runs inside `deep` at most once a day (the nightly rehearsal).
#         balance Horde & Hearth's careers 1 to 60 (realm-loadtest balance career, record only): STATION_BALANCE_SEEDS
#                 (default 1) cohorts of STATION_BALANCE_PER (default 2) careers of each of the ten jobs, alone and in
#                 parties, every tick played (STATION_BALANCE_FAST=1); one line: hours to 10/20/40/60, worst class, sinks
#         idle    nothing: the station stays reachable (a role is a commit away) and reports that it is alive
#         deep    (a role word only) between merges: seeded soaks, reported in <machine>-deep.txt
#         The three below test Four of Wands, which is stopped; no station runs them now.
#         boss    bots play STATION_SEEDS (default "7 21 33 101 102") to the Archlich, side by side
#         checks  tools/check_all.sh; on FAIL the failing rows follow the JOB line
#         frames  Horde & Hearth's client (realm/client) drawing 10,000 monsters or more on this machine's screen and
#                 graphics card for 60 s: a realm-server with bots and a horde, the client as the bot at zoom 16 (the
#                 whole rally), one line with the mean and 99th-percentile frame in ms and the monsters drawn. Needs
#                 cargo, godot and a desktop session (xvfb-run is used when there is none). INFO unless a limit is
#                 set (--p95=<ms> in roles.txt or STATION_FRAME_P99_MS, applied to the 99th percentile; 0 = record only).
#         golden  tools/golden.sh against the commit this station tested last (INFO: did the game change?)
#   --after=M  relay: run a commit only once station M has reported PASS for it; if M failed, report HELD and do nothing
#   --watch    stay running: every STATION_POLL seconds (default 120) fetch origin/main and run the jobs on a new commit
#   --no-push  print the report instead of pushing it
# In watch mode a line for this machine in tools/station/roles.txt replaces the jobs and --after given here, for
# example `msi: realm frames deep`.
# Run it from a clone kept for the station alone: it checks out origin/main detached and refuses a dirty tree.
# Report: branch `station-results`, file <machine>.txt (never main, never CI). Read with tools/station/read.sh.
# STATION_ON_FAIL: optional command run with the report on stdin when a job fails (for example to wake a helper).
# Quiet: prints the report's last line. Exit 0 pass, 1 a job failed, 2 could not run.
set -uo pipefail
cd "$(dirname "$0")/../.."
main() {  # the whole script is one function, so bash has read all of it before a checkout can change the file
ARGS=("$@")
export GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=60  # no git fetch or push waits for a prompt or a dead connection
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || { command -v godot4 >/dev/null 2>&1 && GODOT=godot4; }   # a Linux PC whose Godot is installed as godot4 only (ubuntu, 27 Nov 2026)
export GODOT   # the jobs' own scripts (check_all.sh, the queue's shell jobs) read it from the environment
MACHINE="${STATION_NAME:-$(hostname)}"
SEEDS="${STATION_SEEDS:-7 21 33 101 102}"
POLL="${STATION_POLL:-120}"
BRANCH=station-results
. tools/station/queue_lib.sh  # the work queue (queue_step, hours_mark); read now, like the rest of the script
watch=0; push=1; after=""; jobs=(); deep=0; queue=0; ci_covered=0
for a in "$@"; do
  case "$a" in --watch) watch=1 ;; --no-push) push=0 ;; --ci-covered) ci_covered=1 ;; --after=*) after="${a#--after=}" ;; boss|checks|frames|golden|realm|soak|world|economy|ops|balance|idle) jobs+=("$a") ;; deep) deep=1 ;; queue) queue=1 ;;
    *) echo "station: unknown argument $a" >&2; exit 2 ;; esac
done
# tools/station/roles.txt decides what a watching station does, so changing a machine's job is a commit, not a visit.
P95=""  # `deep` in a role: between merges, run seeded soaks (job_deep) instead of sleeping
role_ok() {  # $1 = a roles.txt line's words: 0 when every word is known (the start-up check, also run on a new tree before a restart)
  local a; for a in $1; do
    case "$a" in --after=*|--ci-covered|--p95=*|--p99=*|lanes=[0-9]*|boss|checks|frames|golden|realm|soak|world|economy|ops|balance|idle|deep|queue) ;;
      *) echo "station: roles.txt: unknown word $a for $MACHINE" >&2; return 1 ;; esac
  done
}
role=$(grep -i "^$MACHINE:" tools/station/roles.txt 2>/dev/null | head -1 | cut -d: -f2-)
[ "$watch" = 1 ] && [ -n "$role" ] && { role_ok "$role" || exit 2; }
if [ "$watch" = 1 ] && [ -n "$role" ]; then
  after=""; jobs=()
  for a in $role; do
    case "$a" in --after=*) after="${a#--after=}" ;; lanes=[0-9]*) : "${STATION_LANES:=${a#lanes=}}" ;; --ci-covered) ci_covered=1 ;; --p95=*) P95="${a#--p95=}" ;; --p99=*) P95="${a#--p99=}" ;; boss|checks|frames|golden|realm|soak|world|economy|ops|balance|idle) jobs+=("$a") ;; deep) deep=1 ;; queue) queue=1 ;;
      *) echo "station: roles.txt: unknown word $a for $MACHINE" >&2; exit 2 ;; esac
  done
fi
[ ${#jobs[@]} -gt 0 ] || { echo "station: name at least one job (realm idle boss checks frames golden)" >&2; exit 2; }
STATE="$(git rev-parse --git-dir)/station_last"  # the commit this station tested last

job_boss() {  # one line: how each seed ended; FAIL on a crash, an engine error, or a run that did not finish
  local out; out=$(mktemp -d) bad=0 detail=""
  # At most one run per core at a time: a 4-core Celeron takes 17 min for one seed, and five at once would time out.
  local n=0 cores; cores=$(nproc 2>/dev/null || echo 2)
  for s in $SEEDS; do
    ( timeout -k 30 "${STATION_BOSS_TIMEOUT:-3600}" "$GODOT" --headless --path . -s tools/full_run.gd -- --wizards=4 "--seed=$s" >"$out/$s.log" 2>&1 ) &
    n=$((n + 1)); (( n % cores == 0 )) && wait
  done
  wait
  for s in $SEEDS; do
    local line; line=$(grep '^FULL_RUN ' "$out/$s.log" | tail -1)
    # A bare -s script prints compile errors before it runs (see CLAUDE.md); only errors raised while it runs count.
    local err; err=$(grep -E '^SCRIPT ERROR:' "$out/$s.log" | grep -v 'Compile Error' | head -1 | cut -c1-80)
    if [ -z "$line" ] || [ -n "$err" ] || [[ "$line" == *UNFINISHED* ]]; then
      bad=$((bad + 1)); detail+=" seed$s=BROKEN(${err:-no result})"
    else
      detail+=" seed$s=$(sed -E 's/.* (WON|LOST) at ([0-9:]+).*/\1@\2/' <<<"$line")"
    fi
  done
  rm -rf "$out"
  echo "JOB boss $([ $bad -eq 0 ] && echo PASS || echo FAIL)$detail"
  return $bad
}
job_checks() {
  # The 10 s per-test limit is CI's to enforce; a slow station gets room (STATION_SLOW_TEST_MS, default 30000).
  # Same for the horde sims' budget, which is set for CI's processor: STATION_SIM_BUDGET_SCALE, else this machine's line
  # "simscale: <machine> N" in roles.txt, else 4. Only Linux counts a step in CPU time: a Windows station times it with a
  # stopwatch beside its queue jobs, so the slowest PC needs a wide budget.
  local scale; scale=$(awk -v M="$(printf %s "$MACHINE" | tr 'A-Z' 'a-z')" '$1 == "simscale:" && tolower($2) == M { print $3; exit }' tools/station/roles.txt 2>/dev/null)
  case "$scale" in ''|*[!0-9]*) scale=4 ;; esac
  # And for the time one bot shard may take (check_all.sh BOT_LIMIT, 240 s): STATION_BOT_LIMIT, else this machine's line
  # "botlimit: <machine> seconds" in roles.txt, else 240.
  local limit; limit=$(awk -v M="$(printf %s "$MACHINE" | tr 'A-Z' 'a-z')" '$1 == "botlimit:" && tolower($2) == M { print $3; exit }' tools/station/roles.txt 2>/dev/null)
  case "$limit" in ''|*[!0-9]*) limit=240 ;; esac
  # In a private save folder (tools/private_save.sh): no robot run reads or writes this PC's own save.
  local out; out=$(SLOW_TEST_MS="${STATION_SLOW_TEST_MS:-30000}" SIM_BUDGET_SCALE="${STATION_SIM_BUDGET_SCALE:-$scale}" BOT_LIMIT="${STATION_BOT_LIMIT:-$limit}" tools/private_save.sh tools/check_all.sh 2>&1)
  [[ "$(tail -1 <<<"$out")" == "CHECK_ALL PASS" ]] && { echo "JOB checks PASS"; return 0; }
  echo "JOB checks FAIL"
  grep -E ' FAIL |failed=[1-9]|problems=[1-9]|CRASH' <<<"$out" | head -12 | cut -c1-200 | sed 's/^ */  /'
  return 1
}
job_frames() {  # one line: the realm client's frame times with a full horde on screen, on this machine's own graphics
  command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  command -v cargo >/dev/null 2>&1 || { echo "JOB frames FAIL cargo is not installed on this station"; return 1; }
  if q_gpu_busy; then echo "JOB frames INFO gpu busy (art generation is RUNNING), skipped"; return 0; fi
  local limit="${P95:-${STATION_FRAME_P99_MS:-0}}" dir port="${STATION_FRAMES_PORT:-7811}" lib out line server runner=()
  dir="${TMPDIR:-/tmp}/station-frames-$MACHINE"; rm -rf "$dir"; mkdir -p "$dir"
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) lib=realm_godot.dll ;; Darwin) lib=librealm_godot.dylib ;; *) lib=librealm_godot.so ;; esac
  # Needs programs built here: realm-server and our GDExtension module ($lib), so a Smart App Control PC skips it (q_ownbin).
  # In a lane realm-server comes from the commit's one build ($Q_RBIN = Q_SNAP); the Godot module has its own target dir.
  { [ -n "${Q_SNAP:-}" ] || ( cd realm && timeout -k 30 3600 cargo build --release -j2 -q ) >"$dir/build.log" 2>&1; } && ( cd realm/godot && timeout -k 30 3600 cargo build --release -j2 -q ) >>"$dir/build.log" 2>&1 \
    && cp "realm/godot/target/release/$lib" realm/client/bin/ || { echo "JOB frames FAIL build: $(tail -2 "$dir/build.log" | tr '\n' ' ' | cut -c1-160)"; return 1; }
  # A fresh clone's first import does its work and then aborts while quitting: the second is clean.
  ( timeout -k 30 180 "$GODOT" --headless --path realm/client --import || timeout -k 30 180 "$GODOT" --headless --path realm/client --import ) >"$dir/import.log" 2>&1 || true
  if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then runner=(xvfb-run -a -s "-screen 0 1440x810x24"); fi
  # 1,200 bots, 25,000 monsters, half the bots rallied at the heart: a screen at zoom 16 holds 10,000 and more.
  "$Q_RBIN"/realm-server --port="$port" --bots=1200 --monsters=25000 --rally=0.5 --threads=2 --report=600 >"$dir/server.log" 2>&1 &
  server=$!
  sleep 5
  kill -0 "$server" 2>/dev/null || { echo "JOB frames FAIL the server did not start: $(tail -1 "$dir/server.log" | cut -c1-120)"; return 1; }
  # The run plays secs at each zoom; a busy 4-core PC with an old GPU needs about 3x that plus start-up (ubuntu, 24 Nov:
  # 300 s was not enough for zooms=16,4 secs=60 beside three lanes).
  local fsecs="${STATION_FRAMES_SECS:-60}" fz="${STATION_FRAMES_ZOOM:-16}" ftime rc=0
  ftime=$(( 120 + 3 * fsecs * $(tr ',' '\n' <<<"$fz" | grep -c .) )); [ "$ftime" -ge 300 ] || ftime=300
  ftime="${STATION_FRAMES_TIMEOUT:-$ftime}"
  out=$(timeout -k 30 "$ftime" "${runner[@]}" "$GODOT" --path realm/client -- --server=127.0.0.1:"$port" --shots="$dir/shots" --secs="$fsecs" --zooms="$fz" --mute 2>&1) || rc=$?
  [ "$rc" != 124 ] || out+=$'\n'"timed out after $ftime s"
  line=$(grep '^CLIENT_FRAMES ' <<<"$out" | tail -1)
  # Pictures for Curtis, at most once in 20 hours a machine: the same battle at zoom 16 (already saved), 4 and 2,
  # pushed to the results branch as shots/<machine>-zoom<N>.png (overwritten, so the branch holds only the newest).
  local stamp="${TMPDIR:-/tmp}/station-shots-stamp-$MACHINE"
  if [ "$push" = 1 ] && [ "${STATION_SHOTS:-1}" = 1 ] && [[ "$line" == "CLIENT_FRAMES ok"* ]] && [ -z "$(find "$stamp" -mmin -1200 2>/dev/null)" ]; then
    timeout -k 30 120 "${runner[@]}" "$GODOT" --path realm/client -- --server=127.0.0.1:"$port" --shots="$dir/shots_near" --secs=3 --zooms=4,2 --mute >/dev/null 2>&1 || true
    cp "$dir"/shots_near/zoom*.png "$dir/shots/" 2>/dev/null
    publish_shots "$dir/shots" && touch "$stamp"
  fi
  kill "$server" 2>/dev/null; wait "$server" 2>/dev/null
  rm -rf "$dir"
  [ -n "$line" ] || { echo "JOB frames FAIL no CLIENT_FRAMES line (no display, or the client died): $(grep -aE 'ERROR|error|panic|Aborted|timed out' <<<"$out" | grep -av ALSA | tail -3 | tr '\n' ' ' | cut -c1-240) last: $(tail -1 <<<"$out" | cut -c1-120)"; return 1; }
  [[ "$line" == "CLIENT_FRAMES ok"* ]] || { echo "JOB frames FAIL ${line#CLIENT_FRAMES }"; return 1; }
  local p99; p99=$(sed -E 's/.* p99_ms=([0-9.]+).*/\1/' <<<"$line")
  if [ "$limit" = 0 ]; then
    echo "JOB frames INFO ${line#CLIENT_FRAMES ok }"
  elif awk -v a="$p99" -v b="$limit" 'BEGIN { exit !(a <= b) }'; then
    echo "JOB frames PASS ${line#CLIENT_FRAMES ok } limit_p99=$limit"
  else
    echo "JOB frames FAIL ${line#CLIENT_FRAMES ok } limit_p99=$limit"; return 1
  fi
}
job_golden() {  # information only: which pushes changed how the game plays
  local base; base=$(cat "$STATE" 2>/dev/null)
  [ -n "$base" ] && git cat-file -e "$base^{commit}" 2>/dev/null || { echo "JOB golden INFO first run, nothing to compare"; return 0; }
  echo "JOB golden INFO $(tools/golden.sh "$base" 2>&1 | tail -1) since ${base:0:7}"
}

job_realm() {  # one line: the summary line of each check script; FAIL when a script does not end with its "ok" line
  # A station that was started before Rust was installed still has its old PATH: look in rustup's own folder too.
  command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  command -v cargo >/dev/null 2>&1 || { echo "JOB realm FAIL cargo is not installed on this station"; return 1; }
  local c out line bad=0 detail=""
  for c in realm/check.sh realm/store/check.sh; do
    [ -f "$c" ] || continue
    # Busy lanes share the cores: timing budgets are printed, not held (a correctness gate, not a benchmark).
    out=$(if [ "$(lanes_busy 2>/dev/null || echo 0)" -gt 0 ]; then export PVP_BENCH_LOADED=1; fi; timeout -k 30 "${STATION_REALM_TIMEOUT:-3600}" bash "$c" 2>&1); line=$(tail -1 <<<"$out")
    if [[ "$line" == *" ok "* ]]; then detail+=" | ${line:0:120}"
    else bad=$((bad + 1)); detail+=" | $c: $(fail_detail <<<"$out") $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-1500)"; fi
  done
  if [ "$(uname -s)" = Linux ] && command -v "$GODOT" >/dev/null 2>&1 && [ -f realm/check_client.sh ]; then  # the client against a real server, on Linux machines with Godot
    local runner=(); [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1 && runner=(xvfb-run -a)
    out=$(GODOT="$GODOT" timeout -k 30 "${STATION_REALM_TIMEOUT:-3600}" "${runner[@]}" bash realm/check_client.sh 2>&1); line=$(tail -1 <<<"$out")
    if [[ "$line" == "REALM_CLIENT ok "* ]]; then detail+=" | ${line:0:120}"
    else bad=$((bad + 1)); detail+=" | realm/check_client.sh: $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-1500)"; fi
  fi
  echo "JOB realm $([ $bad -eq 0 ] && echo PASS || echo FAIL)${detail# |}"
  return $bad
}
job_ops() {  # one line: realm-ops rehearse on this machine's own disk
  command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  command -v cargo >/dev/null 2>&1 || { echo "JOB ops FAIL cargo is not installed on this station"; return 1; }
  local out line dir="${TMPDIR:-/tmp}/station-ops-$MACHINE"
  out=$(cd realm && timeout -k 30 3600 cargo build --release -j2 -p realm-ops --bin realm-ops 2>&1 && timeout -k 30 600 target/release/realm-ops rehearse --dir="$dir" 2>&1); line=$(tail -1 <<<"$out")
  rm -rf "$dir"
  if [[ "$line" == "OPS ok "* ]]; then echo "JOB ops PASS ${line:7:300}"; return 0; fi
  echo "JOB ops FAIL $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-1500)"; return 1
}
job_economy() {  # one line: realm-economy's summary; recorded, never a failure of the merge. Kept to minutes (the 4000-bot 180-day
  # run took two hours a merge and kept the station from the work queue; that long run is the queue's `economy` job now)
  command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  command -v cargo >/dev/null 2>&1 || { echo "JOB economy FAIL cargo is not installed on this station"; return 1; }
  local seed=$(( (RANDOM << 15 | RANDOM) % 1000000 + 1 )) out line
  out=$(cd realm && timeout -k 30 3600 cargo build --release -j2 -p realm-gateway --bin realm-economy 2>&1 && timeout -k 30 "${STATION_ECONOMY_TIMEOUT:-900}" target/release/realm-economy --bots="${STATION_ECONOMY_BOTS:-1000}" --days="${STATION_ECONOMY_DAYS:-30}" --seed=$seed --quiet --db="${TMPDIR:-/tmp}/station-economy.db" 2>&1); line=$(tail -1 <<<"$out")
  rm -f "${TMPDIR:-/tmp}"/station-economy.db*
  if [[ "$line" == "ECONOMY ok "* ]]; then echo "JOB economy INFO seed=$seed ${line:8:260}"; else echo "JOB economy INFO seed=$seed $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-260)"; fi
  return 0
}
job_balance() {  # one line: the careers' BALANCE summary (docs/realm/balance.md); recorded, never a failure of the merge. Kept to
  # minutes: its old limit was a day per merge; the full careers run is the queue's `balance` job now
  command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  command -v cargo >/dev/null 2>&1 || { echo "JOB balance SKIP cargo is not installed on this station"; return 0; }
  local out line
  out=$(cd realm && timeout -k 30 3600 cargo build --release -j2 -p realm-loadtest 2>&1 && BOT_THREADS="${STATION_BALANCE_THREADS:-2}" timeout -k 30 "${STATION_BALANCE_TIMEOUT:-1800}" target/release/realm-loadtest balance career "${STATION_BALANCE_SEEDS:-1}" "${STATION_BALANCE_PER:-1}" "${STATION_BALANCE_MINUTES:-5}" "${STATION_BALANCE_FAST:-16}" "${STATION_BALANCE_HOURS:-40}" 2>&1); line=$(tail -1 <<<"$out")
  if [[ "$line" == "BALANCE "* ]]; then echo "JOB balance INFO ${line:8:260}"; else echo "JOB balance INFO $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-260)"; fi
  return 0
}
job_soak() {  # one line: realm-soak's summary
  command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  command -v cargo >/dev/null 2>&1 || { echo "JOB soak FAIL cargo is not installed on this station"; return 1; }
  local secs="${STATION_SOAK_SECS:-7200}" out line
  out=$(cd realm && timeout -k 30 3600 cargo build --release -j2 -p realm-gateway --bin realm-soak 2>&1 && timeout -k 30 $((secs + 900)) target/release/realm-soak --bots="${STATION_SOAK_BOTS:-40}" --secs="$secs" --fields=0,1,2,3,4,5 --monsters=3000 --progress=0 --fast --db="${TMPDIR:-/tmp}/station-soak.db" 2>&1); line=$(tail -1 <<<"$out")
  rm -f "${TMPDIR:-/tmp}"/station-soak.db*
  if [[ "$line" == "SOAK ok "* ]]; then echo "JOB soak PASS ${line:0:300}"; return 0; fi
  echo "JOB soak FAIL $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-1500)"; return 1
}
job_world() {  # one line: realm-world's summary, a short soak on a merge (jobs/worldlong.sh runs the long one from the queue)
  local line; line=$(STATION_QUEUE_STUB="${STATION_QUEUE_STUB:-}" bash tools/station/jobs/worldlong.sh "secs=${STATION_WORLD_SECS:-600}" | tail -1)
  case "$line" in PASS*) echo "JOB world $line"; return 0 ;; esac
  echo "JOB world FAIL ${line#FAIL }"; return 1
}
job_idle() { echo "JOB idle INFO this station has no job yet"; }
# Deep steps must not make a merge wait: pending_merge says a commit has landed on main that changes something one of this
# station's jobs tests (STATION_MAIN_REF overrides origin/main for a dry run); step_run runs a command in the background,
# polls that every STATION_DEEP_POLL seconds (default 60) and kills the command when it is true (returns 99).
# Inside a lane the station's own loop fetches (every STATION_POLL), and the base is the commit the lane's job started on.
pending_merge() {
  local ref="${STATION_MAIN_REF:-origin/main}" head base changed j
  [ "${Q_IN_LANE:-0}" = 1 ] || git fetch -q origin main 2>/dev/null
  head=$(git rev-parse -q --verify "$ref") || return 1
  base=${Q_LANE_BASE:-$(cat "$STATE" 2>/dev/null)}
  [ "$head" = "$base" ] && return 1
  [ -n "$base" ] && changed=$(git diff --name-only "$base" "$head" 2>/dev/null) || return 0
  for j in "${jobs[@]}"; do touched "$j" <<<"$changed" && return 0; done
  return 1
}
# Queue jobs are watched by queue_lib's q_watch (merge, GPU, silence, the lead's stop); step_run is for the deep steps, killed by any merge.
step_run() {  # $1 = output file, rest = command; the command's status, or 99 when it was killed (a merge landed)
  local f="$1" pid last=$SECONDS; shift
  "$@" >"$f" 2>&1 & pid=$!
  while q_alive "$pid"; do
    sleep 1
    if [ $((SECONDS - last)) -ge "${STATION_DEEP_POLL:-60}" ]; then
      last=$SECONDS
      if pending_merge; then q_kill "$pid"; return 99; fi
    fi
  done
  wait "$pid"; return $?
}
job_deep() {  # between merges: a fresh seed each pass; a big crash fuzz of the store and a full-size field bench
  # Returns 0 pass, 1 fail, 2 skipped (no cargo), 3 interrupted: a merge landed, the rest of the pass was abandoned (not a failure).
  [ -n "${STATION_QUEUE_STUB:-}" ] && { echo "JOB deep PASS stub"; return 0; }  # tests: no heavy commands
  command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  command -v cargo >/dev/null 2>&1 || { echo "JOB deep SKIP cargo is not installed on this station"; return 2; }
  local seed=$(( (RANDOM << 15 | RANDOM) % 1000000 + 1 )) field=$(( RANDOM % 6 )) out bad=0 detail="" dir rc
  dir="${TMPDIR:-/tmp}/station-deep-$MACHINE"; rm -rf "$dir"; mkdir -p "$dir"
  ( cd realm && timeout -k 30 3600 cargo build --release -j2 -q ) >"$dir/build.log" 2>&1 && ( cd realm/store && timeout -k 30 3600 cargo build --release -j2 -q ) >>"$dir/build.log" 2>&1 \
    || { echo "JOB deep FAIL build, last 40 lines:"; tail -40 "$dir/build.log" | tr -d '\r' | cut -c1-300 | sed 's/^/  /'; rm -rf "$dir"; return 1; }
  interrupted() { rm -rf "$dir"; echo "JOB deep INTERRUPTED a merge landed (seed=$seed)"; return 3; }
  pending_merge && { interrupted; return 3; }
  step_run "$dir/fuzz.out" timeout -k 30 1800 realm/store/target/release/realm-store fuzz --seed=$seed --ops="${STATION_DEEP_OPS:-50000}" --kills=200 --dir="$dir/fuzz"; rc=$?
  [ $rc = 99 ] && { interrupted; return 3; }
  out=$(cat "$dir/fuzz.out")
  if [ $rc = 0 ]; then detail+=" | fuzz seed=$seed $(tail -1 <<<"$out" | cut -c1-120)"
  else bad=$((bad + 1)); detail+=" | fuzz seed=$seed FAILED: $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-1500)"; fi
  pending_merge && { interrupted; return 3; }
  step_run "$dir/bench.out" timeout -k 30 1800 realm/target/release/realm-server --bench --field=$field --seed=$seed --bots=1000 --monsters=20000 --rally=0.3 --threads=2 --ticks="${STATION_DEEP_TICKS:-600}" --warmup=100 --report=300; rc=$?
  [ $rc = 99 ] && { interrupted; return 3; }
  out=$(cat "$dir/bench.out")
  if [ $rc = 0 ]; then detail+=" | bench field=$field seed=$seed $(tail -1 <<<"$out" | cut -c1-140)"
  else bad=$((bad + 1)); detail+=" | bench field=$field seed=$seed FAILED: $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-1500)"; fi
  local ssecs="${STATION_DEEP_SOAK_SECS:-900}"  # a time-boxed soak with a fresh seed (0 = none); the per-merge soak job is gone from roles.txt
  if [ "$ssecs" -gt 0 ]; then
    pending_merge && { interrupted; return 3; }
    ( cd realm && timeout -k 30 3600 cargo build --release -j2 -p realm-gateway --bin realm-soak ) >"$dir/soakbuild.out" 2>&1
    step_run "$dir/soak.out" timeout -k 30 $((ssecs + 600)) realm/target/release/realm-soak --bots="${STATION_SOAK_BOTS:-40}" --secs="$ssecs" --seed=$seed --fields=0,1,2,3,4,5 --monsters=3000 --progress=0 --fast --db="$dir/soak.db"; rc=$?
    [ $rc = 99 ] && { interrupted; return 3; }
    out=$(cat "$dir/soak.out")
    if [[ "$(tail -1 <<<"$out")" == "SOAK ok "* ]]; then detail+=" | soak seed=$seed $(tail -1 <<<"$out" | cut -c1-120)"
    else bad=$((bad + 1)); detail+=" | soak seed=$seed FAILED: $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-1500)"; fi
  fi
  local stamp="${TMPDIR:-/tmp}/station-ops-last-$MACHINE"  # the nightly operations rehearsal: backup and restore, at most once in 20 hours
  if [ ! -f "$stamp" ] || [ -n "$(find "$stamp" -mmin +1200 2>/dev/null)" ]; then
    pending_merge && { interrupted; return 3; }
    if out=$(job_ops 2>&1); then detail+=" | ${out:4:200}"; else bad=$((bad + 1)); detail+=" | ${out:4:200}"; fi
    touch "$stamp"
  fi
  rm -rf "$dir"
  echo "JOB deep $([ $bad -eq 0 ] && echo PASS || echo FAIL)${detail# |}"
  return $bad
}

# A job is skipped for a commit that changed nothing it tests. $1 = job, stdin = the paths changed since this station's
# last commit. Godot jobs test everything except the realm, the docs and the stations themselves.
touched() {
  case "$1" in
    idle) return 0 ;;
    realm|frames|soak|world|economy|ops|balance) grep -q '^realm/' ;;
    *) grep -qvE '^(realm/|docs/|\.github/|\.claude/|tools/station/|tools/ops_board/|[^/]*\.md$)' ;;
  esac
}

publish() {  # $1 = report text, $2 = file (default <machine>.txt). Adds it to the results branch without touching the work tree.
  local blob parent tree commit idx
  for _try in 1 2 3; do
    git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null
    parent=$(git rev-parse -q --verify "refs/remotes/origin/$BRANCH" || true)
    idx=$(mktemp -u)
    if [ -n "$parent" ] && ! GIT_INDEX_FILE="$idx" git read-tree "$parent"; then rm -f "$idx"; sleep "${STATION_PUBLISH_SLEEP:-5}"; continue; fi
    blob=$(git hash-object -w --stdin <<<"$1")
    GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo 100644 "$blob" "${2:-$MACHINE.txt}"
    tree=$(GIT_INDEX_FILE="$idx" git write-tree); rm -f "$idx"
    commit=$(git -c user.name="station $MACHINE" -c user.email="station@localhost" commit-tree "$tree" ${parent:+-p "$parent"} -m "$MACHINE: $(tail -1 <<<"$1")")
    gb_sha_ok "$tree" && gb_sha_ok "$commit" && GIT_TERMINAL_PROMPT=0 git push -q origin "$commit:refs/heads/$BRANCH" 2>/dev/null && return 0
    sleep "${STATION_PUBLISH_SLEEP:-5}"
  done
  echo "station: could not push the report" >&2; return 1
}

publish_shots() {  # $1 = a folder of zoom<N>.png: adds them to the results branch as shots/<machine>-zoom<N>.png in one commit
  local parent tree commit idx f blob n=0
  git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null
  parent=$(git rev-parse -q --verify "refs/remotes/origin/$BRANCH" || true)
  idx=$(mktemp -u)
  if [ -n "$parent" ] && ! GIT_INDEX_FILE="$idx" git read-tree "$parent"; then rm -f "$idx"; return 1; fi
  for f in "$1"/zoom*.png; do
    [ -s "$f" ] || continue
    blob=$(git hash-object -w "$f")
    GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo 100644 "$blob" "shots/$MACHINE-$(basename "$f")"; n=$((n+1))
  done
  [ "$n" -gt 0 ] || { rm -f "$idx"; return 1; }
  tree=$(GIT_INDEX_FILE="$idx" git write-tree); rm -f "$idx"
  commit=$(git -c user.name="station $MACHINE" -c user.email="station@localhost" commit-tree "$tree" ${parent:+-p "$parent"} -m "$MACHINE: $n crowd screenshots")
  gb_sha_ok "$tree" && gb_sha_ok "$commit" || return 1
  GIT_TERMINAL_PROMPT=0 git push -q origin "$commit:refs/heads/$BRANCH" 2>/dev/null
}

publish_append() {  # $1 = one line, $2 = file: append it to the file on the results branch (a history, not an overwrite)
  local old; git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null
  old=$(git show "refs/remotes/origin/$BRANCH:$2" 2>/dev/null | tail -200)
  publish "${old:+$old$'\n'}$(tr '\n' ' ' <<<"$1")" "$2"
}

# Watch mode restarts itself when a pull changed this script, so a station always runs the current version.
# The heartbeat loop, one per station: every STATION_HEARTBEAT_SECS (default 1800) it publishes <machine>-heartbeat.txt.
# A re-exec runs no EXIT trap, so `restart` stops the loop before every exec. The loop also ends by itself when the
# station process is gone or a newer loop has written its pid to $STATE.heartbeat (an exec keeps the pid, so the pid
# alone cannot tell the old station from the new). STATION_HEARTBEAT_LOG (tests) gets "<loop pid> <time>" each round.
# Keep-awake (Curtis, 22 Nov 2026: "some kind of thing that keeps everything fresh and active as if im here"): while a station
# watches, the PC is asked to stay awake with its screen on, the request video players make (Windows SetThreadExecutionState;
# Linux systemd-inhibit). Nothing is installed, no window, no mouse or key is touched. The helper lives only while the station
# refreshes $STATE.awake (the heartbeat loop touches it every 10 s) and while its token is the newest, so a restart leaves one.
# STATION_KEEPAWAKE=0 turns it off.
keepawake_start() {
  [ "${STATION_KEEPAWAKE:-1}" = 1 ] || return 0
  local tok="$$-$RANDOM-$(date +%s)" f; f="$(cd "$(dirname "$STATE")" && pwd)/$(basename "$STATE").awake"
  echo "$tok" >"$f"
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
      command -v powershell.exe >/dev/null 2>&1 || return 0
      local wf; wf=$(cygpath -w "$f" 2>/dev/null || echo "$f")
      STATION_AWAKE_FILE="$wf" STATION_AWAKE_TOKEN="$tok" powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command '
        $sig = "[DllImport(\"kernel32.dll\")] public static extern uint SetThreadExecutionState(uint f);"
        $k = Add-Type -MemberDefinition $sig -Name Awake -Namespace Station -PassThru
        while ($true) {
          $i = Get-Item -LiteralPath $env:STATION_AWAKE_FILE -ErrorAction SilentlyContinue
          if (-not $i) { break }
          if (((Get-Date) - $i.LastWriteTime).TotalSeconds -gt 180) { break }
          if ((Get-Content -LiteralPath $env:STATION_AWAKE_FILE -TotalCount 1) -ne $env:STATION_AWAKE_TOKEN) { break }
          [void]$k::SetThreadExecutionState(0x80000003)
          Start-Sleep -Seconds 30
        }
        [void]$k::SetThreadExecutionState(0x80000000)' >/dev/null 2>&1 &
      ;;
    Linux)
      command -v systemd-inhibit >/dev/null 2>&1 || return 0
      STATION_AWAKE_FILE="$f" STATION_AWAKE_TOKEN="$tok" systemd-inhibit --what=idle:sleep:handle-lid-switch --who=station \
        --why="test station running" bash -c 'while [ "$(head -1 "$STATION_AWAKE_FILE" 2>/dev/null)" = "$STATION_AWAKE_TOKEN" ] &&
          [ -n "$(find "$STATION_AWAKE_FILE" -newermt "-180 seconds" 2>/dev/null)" ]; do sleep 30; done' >/dev/null 2>&1 &
      ;;
  esac
  disown 2>/dev/null || true
}
keepawake_touch() { [ -f "$STATE.awake" ] && touch "$STATE.awake" 2>/dev/null; return 0; }
hb_pid=""
heartbeat_start() {
  local station=$$
  (
    me=$BASHPID
    echo "$me" >"$STATE.heartbeat"
    mine() { kill -0 "$station" 2>/dev/null && [ "$(cat "$STATE.heartbeat" 2>/dev/null)" = "$me" ]; }
    while mine; do
      [ -z "${STATION_HEARTBEAT_LOG:-}" ] || echo "$me $(date +%s)" >>"$STATION_HEARTBEAT_LOG"
      publish "HEARTBEAT machine=$MACHINE time=$(date -u +%Y-%m-%dT%H:%MZ) disk_free_gb=$(q_disk_gb) lanes_busy=$(lanes_busy)/${Q_NLANES:-1}$(q_idle_why)$(q_sac && echo " sac=on")" "$MACHINE-heartbeat.txt" 2>/dev/null
      left="${STATION_HEARTBEAT_SECS:-1800}"
      while [ "$left" -gt 0 ] && mine; do keepawake_touch; sleep $((left < 10 ? left : 10)); left=$((left - 10)); done
    done
  ) &
  hb_pid=$!
}
heartbeat_stop() { [ -z "$hb_pid" ] || kill "$hb_pid" 2>/dev/null; hb_pid=""; }
# Loops an older version of this script left behind (it exec'd without stopping its loop): children of this pid,
# killed before this station starts any of its own. Linux ps, else Git Bash's (an optional status letter, PID, PPID).
# Running lanes are children of this pid too (an exec keeps it): their pids, from the lane files ($Q_LD/<lane>), are spared,
# or every merge that restarts the station kills every running job and counts a start toward parking it.
heartbeat_reap() {
  local p keep; keep=" $(cat "${Q_LD:-/nonexistent}"/[0-9]* 2>/dev/null | sed -nE 's/^pid=([0-9]+).*/\1/p' | tr '\n' ' ') "
  for p in $({ ps -e -o pid=,ppid= 2>/dev/null || ps 2>/dev/null | awk 'NR > 1 { if ($1 !~ /^[0-9]+$/) $1 = ""; $0 = $0; print $1, $2 }'; } | awk -v pp=$$ '$2 == pp { print $1 }'); do
    [[ "$keep" == *" $p "* ]] && continue
    kill "$p" 2>/dev/null
  done
}
restart() { heartbeat_stop; exec bash tools/station/station.sh "$@"; }
SELF_WARN=""
self_ok() {  # the new tree must parse before it is exec'd; on a bad tree keep the loaded code (started = what is on disk now, so the next good commit differs)
  local f bad="" r
  for f in tools/station/station.sh tools/station/queue_lib.sh tools/station/jobs/*.sh; do bash -n "$f" 2>/dev/null || bad+=" $f"; done
  r=$(grep -i "^$MACHINE:" tools/station/roles.txt 2>/dev/null | head -1 | cut -d: -f2-)
  [ -z "$r" ] || { role_ok "$r" 2>/dev/null && grep -qwE 'boss|checks|frames|golden|realm|soak|world|economy|ops|balance|idle' <<<"$r"; } || bad+=" roles.txt"  # unknown word, or no job named: both stop a starting station
  [ -z "$bad" ] && return 0
  SELF_WARN="station: NOT restarting, the new commit has a broken script:$bad; running the loaded code"
  echo "$SELF_WARN" >&2; started=$(self_sum); return 1
}
self_sum() { cat tools/station/station.sh tools/station/queue_lib.sh tools/station/roles.txt tools/station/jobs/*.sh 2>/dev/null | cksum; }
started=$(self_sum)
deep_has_room() { q_free_mb_set; [ -z "$Q_FREE_MB" ] || [ "$Q_FREE_MB" -ge "${STATION_DEEP_FREE_MB:-2048}" ]; }  # the same RAM gate the queue has
# A finished report whose push failed is kept in $STATE.unpushed and only the push is retried (at the start of every run_once);
# the jobs are not run again. A newer report replaces it.
retry_unpushed() {
  [ -s "$STATE.unpushed" ] || return 0
  if publish "$(cat "$STATE.unpushed")"; then
    tail -n +2 "$STATE.unpushed" | sed -E 's/[0-9.]+ ?(ms|s)\b//g' | cksum >"$STATE.report"; rm -f "$STATE.unpushed"; echo "station: the kept report was pushed"
  fi
}
# merge_job J: runs job_J (its report on stdout, its status returned) and, while it runs, keeps the queue's free lanes filled
# once a minute (with or without a build: q_eligible holds back the jobs that need one while Q_SNAP is empty). A merge test can take most of an hour on a 4-core PC; before this, lanes that
# finished during it stayed empty until it ended, and on a day of many merges the Linux station sat at 1 of 3 lanes (24 Nov).
merge_job() {
  local j=$1 out rc p last=$SECONDS
  if [ "$queue" != 1 ] || [ "$push" != 1 ]; then "job_$j"; return; fi
  out=$(mktemp); ( "job_$j" ) >"$out" & p=$!
  while kill -0 "$p" 2>/dev/null; do
    sleep "${STATION_LANE_TICK:-5}"
    if [ $((SECONDS - last)) -ge 60 ]; then last=$SECONDS; lanes_fill >&2; fi
  done
  wait "$p"; rc=$?; cat "$out"; rm -f "$out"; return $rc
}
run_once() {
  [ "$push" = 1 ] && retry_unpushed
  git fetch -q origin main || { echo "station: fetch failed" >&2; return 2; }
  git config core.autocrlf false  # Godot rewrites .import files with LF; Windows Git's autocrlf=true would call the clone changed
  local dirty; dirty=$(git status --porcelain --untracked-files=no)
  if [ -n "$dirty" ] && ! grep -qv '\.import$' <<<"$dirty"; then  # only Godot's import files (line endings): put them back
    git rm -r -q --cached . >/dev/null 2>&1; git reset -q --hard; dirty=$(git status --porcelain --untracked-files=no)
  fi
  [ -z "$dirty" ] || { echo "station: this clone has local changes; keep a clone for the station alone" >&2; return 2; }
  local head; head=$(git rev-parse origin/main)
  [ "$watch" = 1 ] && [ "$head" = "$(cat "$STATE" 2>/dev/null)" ] && return 3  # nothing new
  local held=""
  if [ -n "$after" ]; then  # relay: wait for the stage before this one
    git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null
    local prev; prev=$(git show "refs/remotes/origin/$BRANCH:$after.txt" 2>/dev/null)
    grep -q "^STATION machine=.* commit=${head:0:7} " <<<"$prev" || return 3  # not reported for this commit yet
    grep -q '^STATION PASS' <<<"$prev" || held="$after did not pass"
  fi
  git checkout -q --detach "$head"
  # This commit changed the script: restart first, so the commit is tested by its own version (the state is not saved yet).
  if [ "$watch" = 1 ] && [ "$(self_sum)" != "$started" ] && self_ok; then restart "${ARGS[@]}"; fi
  local start=$SECONDS failed=0 body="${SELF_WARN:+$SELF_WARN$'\n'}" skipped=0 run=() j
  local base changed="" known=0; base=$(cat "$STATE" 2>/dev/null)
  if [ -n "$base" ] && changed=$(git diff --name-only "$base" "$head" 2>/dev/null); then known=1; fi
  for j in "${jobs[@]}"; do
    if [ $known = 1 ] && ! touched "$j" <<<"$changed"; then
      body+="JOB $j SKIP nothing it tests changed since ${base:0:7}"$'\n'; skipped=$((skipped + 1))
    elif [ "$j" != idle ] && [ "$j" != boss ] && [ "$j" != checks ] && [ "$j" != golden ] && q_sac; then   # every realm merge job runs programs built here
      body+="JOB $j SKIP Smart App Control refuses programs built on this PC (security settings untouched)"$'\n'; skipped=$((skipped + 1))
    elif [ "$j" = realm ] && [ "$ci_covered" = 1 ] && ! grep -qE "${STATION_REALM_OWN_PATHS:-\.(ps1|cmd|bat)$|^realm/ops/host/|^tools/station/start_station}" <<<"$changed"; then
      body+="JOB realm SKIP CI tests this commit (role flag --ci-covered); only Windows-only paths run here"$'\n'; skipped=$((skipped + 1))
    else run+=("$j"); fi
  done
  local verdict
  if [ -n "$held" ]; then
    verdict="STATION HELD $held"
  else
    if grep -qE '(^| )(boss|checks|golden)( |$)' <<<"${run[*]:-}"; then  # only Godot jobs need the import
      tools/import.sh >/dev/null 2>&1 || { echo "station: import failed" >&2; return 2; }
    fi
    for j in "${run[@]:+${run[@]}}"; do
      body+="$(merge_job "$j")"$'\n' || failed=$((failed + 1))
    done
    verdict="STATION $([ $failed -eq 0 ] && echo PASS || echo FAIL) jobs=${#run[@]} failed=$failed skipped=$skipped"
  fi
  local report="STATION machine=$MACHINE time=$(date -u +%Y-%m-%dT%H:%MZ) commit=${head:0:7} took=$((SECONDS - start))s"$'\n'"$body$verdict"
  if [ $failed -gt 0 ] && [ -n "${STATION_ON_FAIL:-}" ]; then bash -c "$STATION_ON_FAIL" <<<"$report" >/dev/null 2>&1 || true; fi
  if [ "$push" = 1 ]; then
    # Push only a report that differs from the last one pushed (ignoring time and took). The commit counts as tested once its jobs ran; a failed push keeps the report ($STATE.unpushed) and only the push is retried.
    local sig; sig=$(tail -n +2 <<<"$report" | sed -E 's/[0-9.]+ ?(ms|s)\b//g' | cksum)
    if [ "$sig" != "$(cat "$STATE.report" 2>/dev/null)" ]; then
      printf '%s\n' "$report" >"$STATE.unpushed"
      if publish "$report"; then echo "$sig" >"$STATE.report"; rm -f "$STATE.unpushed"
      else echo "station: report kept, the push will be retried; the jobs are not run again" >&2; fi
    fi
    if [ $failed -gt 0 ]; then  # the failed jobs' lines (test names, first panics) stay in the history too
      publish_append "$(date -u +%Y-%m-%dT%H:%MZ) $MACHINE ${head:0:7} $(grep '^JOB .* FAIL' <<<"$body" | tr '\n' ' ' | cut -c1-1500)" "$MACHINE-failures.txt" || true
    fi
    echo "$head" >"$STATE"; tail -1 <<<"$report"
  else echo "$head" >"$STATE"; echo "$report"; fi
  [ $failed -eq 0 ]
}

# Stopped stations (27 Nov 2026: Horde & Hearth is shelved and the owner asked for every PC to stop its station and work).
# A line `stopped: <machine> ...` (or `stopped: all`) in roles.txt ends a watching station: it ends the jobs still running in its
# lanes and the playtest server, publishes one STOPPED report, ends its launcher (start_station.sh, start_station.cmd or a wrapper
# named run_station.cmd, which would start it again in 60 s) and exits 0. Nothing is uninstalled and no setting is touched, so
# a start at boot or log-on comes this way again and ends at once. To run the stations again: take the machine off the
# `stopped:` line on main, then start its launcher once (or restart the PC); the station then follows main as before.
station_stopped() {  # $1 = roles text (default: the file in the work tree): 0 when a `stopped:` line names this machine or `all`
  local w t; t=${1-$(cat tools/station/roles.txt 2>/dev/null)}
  for w in $(grep -i '^stopped:' <<<"$t" | tr -d '\r' | cut -d: -f2- | tr ',' ' '); do
    if [ "${w,,}" = all ] || [ "${w,,}" = "${MACHINE,,}" ]; then return 0; fi
  done
  return 1
}
tree_pids() { local c; echo "$1"; for c in $(pgrep -P "$1" 2>/dev/null); do tree_pids "$c"; done; }  # a pid and all under it, parents first
station_stop() {  # 0 = stopped (the caller exits); 1 = main no longer stops this machine (the caller runs on)
  local f p c pids n=0 now last mark="$STATE.stopped" tree d
  now=$(date +%s); last=$(cat "$mark" 2>/dev/null); [[ "$last" =~ ^[0-9]+$ ]] || last=0
  # Un-stopped on main while this PC was off, or minutes ago: run normally (the loop checks out that commit and restarts into its roles).
  # Asked on every start. It used to be asked only when the last stop was 30 minutes old, to spare a fetch a minute where a launcher
  # could not be ended; on 27 Nov 2026 that made three PCs stop again right after the stop line came off main, because each had
  # been started (and had stopped) a few minutes before the merge. One fetch a start is what a running station does anyway.
  if git fetch -q origin main 2>/dev/null && tree=$(git show origin/main:tools/station/roles.txt 2>/dev/null) \
    && [ -n "$tree" ] && ! station_stopped "$tree"; then
    echo "station: this checkout says stopped, origin/main does not: running"; return 1
  fi
  echo "station: roles.txt stops this station: ending its jobs, its launcher and itself"
  rm -f "$STATE.awake" "$STATE.heartbeat"  # the keep-awake helper and any old heartbeat loop end on their own
  for f in "$Q_LD"/[0-9]*; do  # jobs still running in lanes (the queue's stop files normally ended them already)
    case "$f" in *.cool|*.log) continue ;; esac; [ -f "$f" ] || continue
    p=$(q_lane_get "$f" pid)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
      n=$((n + 1))
      if [ -r "/proc/$p/winpid" ]; then q_kill "$p"  # Windows: taskkill /T takes the whole tree
      else pids=$(tree_pids "$p"); for c in $pids; do kill -TERM "$c" 2>/dev/null; done; sleep 2; for c in $pids; do kill -KILL "$c" 2>/dev/null; done; fi
    fi
    rm -f "$f"
  done
  # The playtest server (jobs/playhost.sh) runs detached from the queue; its stop file ends it cleanly (heroes banked, store kept).
  d="${STATION_PLAYHOST_DIR:-$HOME/HordeAndHearthServer}"; [ -d "$d" ] && touch "$d/stop" 2>/dev/null
  # The art generator on the MSI (tools/art_runner on branch art-pipeline) and its supervisor end after the current picture
  # when the STOP file exists in their folder (the same file stop_runner.ps1 writes).
  d="${HH_ART_DIR:-/d/projects/hh_art}"; [ -d "$d" ] && : >"$d/STOP" 2>/dev/null
  if [ "$push" = 1 ] && [ $((now - last)) -ge 1800 ]; then  # one report; a station that is started again reports at most half-hourly
    publish "STATION machine=$MACHINE time=$(date -u +%Y-%m-%dT%H:%MZ) commit=$(git rev-parse --short=7 HEAD 2>/dev/null) took=0s"$'\n'"JOB stop INFO roles.txt stops this station: jobs_ended=$n, nothing runs, the station and its launcher end now"$'\n'"STATION STOPPED" \
      && echo "$now" >"$mark"
    publish "HEARTBEAT machine=$MACHINE time=$(date -u +%Y-%m-%dT%H:%MZ) disk_free_gb=$(q_disk_gb) lanes_busy=0/0 stopped=1" "$MACHINE-heartbeat.txt" 2>/dev/null || true
  fi
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
      # No double quote inside the command: nothing for the Windows command line to re-quote on the way to PowerShell.
      command -v powershell.exe >/dev/null 2>&1 && powershell.exe -NoProfile -NonInteractive -Command \
        "Get-CimInstance Win32_Process | Where-Object { \$_.Name -eq 'cmd.exe' -and \$_.CommandLine -match 'start_station|run_station' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1
      ;;
    *)
      p=$PPID
      if [ -r "/proc/$p/cmdline" ] && tr '\0' ' ' <"/proc/$p/cmdline" | grep -q 'start_station\.sh'; then kill -TERM "$p" 2>/dev/null; fi
      ;;
  esac
  return 0
}
if [ "$watch" = 1 ] && station_stopped && station_stop; then exit 0; fi

if [ "$watch" = 1 ]; then
  if [ "$push" = 1 ]; then  # a heartbeat every 30 min, so read.sh can tell a dead machine from a quiet one
    heartbeat_reap
    keepawake_start
    Q_NLANES=$(q_lane_total)   # before the heartbeat forks, so its lanes_busy=B/N shows the real N
    heartbeat_start
    trap 'heartbeat_stop; rm -f "$STATE.awake"' EXIT
  fi
  after_merge=1; last_pub=0; deep_n=0; deep_cut=0; deep_seeds=""
  # Lanes: the queue jobs run in the background, Q_NLANES at a time (q_lane_total: STATION_LANES, a "lanes: <machine> N" line of
  # roles.txt, else from cores and RAM). This loop stays free: it tests every merge as it lands (a lane's short job is cut by a merge
  # that touches what it tests, a long one finishes on its own build), builds once per commit for all lanes (q_build_all; no job that
  # runs our programs starts during the build), then fills the free lanes. A restart (exec) leaves running lanes alone: their pid
  # files in $Q_LD let the new process count them. deep runs only when no lane is busy and the queue has nothing for this machine.
  Q_NLANES=$(q_lane_total); [ "$queue" = 1 ] && echo "station: $MACHINE runs up to $Q_NLANES queue job(s) at once (lanes)"
  hours_init
  while true; do
    run_once; rc=$?
    [ "$(self_sum)" = "$started" ] || ! self_ok || restart "$@"
    if [ $rc != 3 ]; then after_merge=1; hours_mark busy "$(lanes_busy)"; fi  # a merge was just tested: the next deep pass is published
    if [ "$queue" = 1 ] && [ "$push" = 1 ]; then
      q_prune; q_spool_flush; q_build_all; lanes_fill
      nb=$(lanes_busy)
      if [ "$nb" -gt 0 ]; then  # wait up to STATION_POLL, less when a lane comes free
        t0=$SECONDS
        while [ $((SECONDS - t0)) -lt "$POLL" ]; do
          sleep "${STATION_LANE_TICK:-5}"; n2=$(lanes_busy); hours_mark busy "$nb"; [ "$n2" -lt "$nb" ] && break; nb=$n2
        done
        continue
      fi
    fi
    if [ $rc = 3 ] && [ "$deep" = 1 ] && q_sac; then sleep "$POLL"; hours_mark idle; continue; fi  # deep runs programs built here
    if [ $rc = 3 ] && [ "$deep" = 1 ] && ! deep_has_room; then echo "SKIP deep pass: needs ${STATION_DEEP_FREE_MB:-2048} MB free RAM, only $Q_FREE_MB MB free" >&2; sleep "$POLL"; hours_mark idle; continue; fi
    if [ $rc = 3 ] && [ "$deep" = 1 ]; then  # nothing new on main: one deep pass instead of sleeping
      t0=$SECONDS; body=$(job_deep); drc=$?
      now=$(date +%s); hours_mark busy
      if [ $drc = 3 ]; then deep_cut=$((deep_cut + 1)); echo "station: deep pass interrupted, a merge landed"; continue; fi
      hourly=0; [ $((now - last_pub)) -ge 3600 ] && hourly=1
      if [ $drc = 2 ]; then  # no cargo: SKIP, a broken machine sleeps and tells the branch at most hourly
        if [ "$push" = 1 ] && [ $hourly = 1 ]; then
          publish "STATION machine=$MACHINE time=$(date -u +%Y-%m-%dT%H:%MZ) commit=$(git rev-parse --short=7 HEAD) took=0s"$'\n'"$body"$'\n'"STATION SKIP deep pass" "$MACHINE-deep.txt" && last_pub=$now || true
        fi
        sleep "$POLL"; hours_mark idle; continue
      fi
      deep_n=$((deep_n + 1)); deep_seeds="$(printf %s "${deep_seeds:+$deep_seeds,}$(grep -o 'seed=[0-9]*' <<<"$body" | head -1 | cut -d= -f2)" | tail -c 120)"
      v=$([ $drc = 0 ] && echo PASS || echo FAIL)
      rep="STATION machine=$MACHINE time=$(date -u +%Y-%m-%dT%H:%MZ) commit=$(git rev-parse --short=7 HEAD) took=$((SECONDS - t0))s"$'\n'"$body"$'\n'"STATION $v deep pass passes=$deep_n interrupted=$deep_cut seeds=$deep_seeds"
      if [ "$push" = 1 ]; then
        if [ $drc != 0 ] || [ $after_merge = 1 ] || [ $hourly = 1 ]; then
          publish "$rep" "$MACHINE-deep.txt" && { last_pub=$now; after_merge=0; deep_n=0; deep_cut=0; deep_seeds=""; } || true
        fi
        if [ $drc != 0 ]; then publish_append "$(date -u +%Y-%m-%dT%H:%MZ) $MACHINE ${body:0:1500}" "$MACHINE-failures.txt" || true; fi
      else echo "$rep"; fi
      if [ $drc = 0 ]; then sleep "${STATION_DEEP_GAP:-10}"; else sleep "$POLL"; fi
      hours_mark idle; continue
    fi
    sleep "$POLL"; hours_mark idle
  done
fi
run_once
exit $?
}
main "$@"

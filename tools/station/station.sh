#!/usr/bin/env bash
# A station: a spare computer that runs long jobs with no Claude on it and reports a few lines.
# Usage: tools/station/station.sh [--watch] [--no-push] job [job ...]
#   jobs: realm   Horde & Hearth: realm/check.sh and realm/store/check.sh (the Rust core, server and store). Needs cargo;
#                 a station without it reports SKIP.
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
GODOT="${GODOT:-godot}"
MACHINE="${STATION_NAME:-$(hostname)}"
SEEDS="${STATION_SEEDS:-7 21 33 101 102}"
POLL="${STATION_POLL:-120}"
BRANCH=station-results
watch=0; push=1; after=""; jobs=(); deep=0
for a in "$@"; do
  case "$a" in --watch) watch=1 ;; --no-push) push=0 ;; --after=*) after="${a#--after=}" ;; boss|checks|frames|golden|realm|idle) jobs+=("$a") ;; deep) deep=1 ;;
    *) echo "station: unknown argument $a" >&2; exit 2 ;; esac
done
# tools/station/roles.txt decides what a watching station does, so changing a machine's job is a commit, not a visit.
P95=""  # `deep` in a role: between merges, run seeded soaks (job_deep) instead of sleeping
role=$(grep -i "^$MACHINE:" tools/station/roles.txt 2>/dev/null | head -1 | cut -d: -f2-)
if [ "$watch" = 1 ] && [ -n "$role" ]; then
  after=""; jobs=()
  for a in $role; do
    case "$a" in --after=*) after="${a#--after=}" ;; --p95=*) P95="${a#--p95=}" ;; --p99=*) P95="${a#--p99=}" ;; boss|checks|frames|golden|realm|idle) jobs+=("$a") ;; deep) deep=1 ;;
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
    ( timeout "${STATION_BOSS_TIMEOUT:-3600}" "$GODOT" --headless --path . -s tools/full_run.gd -- --wizards=4 "--seed=$s" >"$out/$s.log" 2>&1 ) &
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
  # Same for the horde sim's CPU budget, which is set for CI's processor (STATION_SIM_BUDGET_SCALE, default 4).
  local out; out=$(SLOW_TEST_MS="${STATION_SLOW_TEST_MS:-30000}" SIM_BUDGET_SCALE="${STATION_SIM_BUDGET_SCALE:-4}" tools/check_all.sh 2>&1)
  [[ "$(tail -1 <<<"$out")" == "CHECK_ALL PASS" ]] && { echo "JOB checks PASS"; return 0; }
  echo "JOB checks FAIL"
  grep -E ' FAIL |failed=[1-9]|problems=[1-9]|CRASH' <<<"$out" | head -6 | cut -c1-160 | sed 's/^ */  /'
  return 1
}
job_frames() {  # one line: the realm client's frame times with a full horde on screen, on this machine's own graphics
  command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  command -v cargo >/dev/null 2>&1 || { echo "JOB frames SKIP cargo is not installed on this station"; return 0; }
  local limit="${P95:-${STATION_FRAME_P99_MS:-0}}" dir port="${STATION_FRAMES_PORT:-7811}" lib out line server runner=()
  dir="${TMPDIR:-/tmp}/station-frames-$MACHINE"; rm -rf "$dir"; mkdir -p "$dir"
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) lib=realm_godot.dll ;; Darwin) lib=librealm_godot.dylib ;; *) lib=librealm_godot.so ;; esac
  ( cd realm && cargo build --release -j2 -q ) >"$dir/build.log" 2>&1 && ( cd realm/godot && cargo build --release -j2 -q ) >>"$dir/build.log" 2>&1 \
    && cp "realm/godot/target/release/$lib" realm/client/bin/ || { echo "JOB frames FAIL build: $(tail -2 "$dir/build.log" | tr '\n' ' ' | cut -c1-160)"; return 1; }
  # A fresh clone's first import does its work and then aborts while quitting: the second is clean.
  ( timeout 180 "$GODOT" --headless --path realm/client --import || timeout 180 "$GODOT" --headless --path realm/client --import ) >"$dir/import.log" 2>&1 || true
  if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then runner=(xvfb-run -a -s "-screen 0 1440x810x24"); fi
  # 1,200 bots, 25,000 monsters, half the bots rallied at the heart: a screen at zoom 16 holds 10,000 and more.
  realm/target/release/realm-server --port="$port" --bots=1200 --monsters=25000 --rally=0.5 --threads=2 --report=600 >"$dir/server.log" 2>&1 &
  server=$!
  sleep 5
  kill -0 "$server" 2>/dev/null || { echo "JOB frames FAIL the server did not start: $(tail -1 "$dir/server.log" | cut -c1-120)"; return 1; }
  out=$(timeout "${STATION_FRAMES_TIMEOUT:-300}" "${runner[@]}" "$GODOT" --path realm/client -- --server=127.0.0.1:"$port" --shots="$dir/shots" --secs="${STATION_FRAMES_SECS:-60}" --zooms="${STATION_FRAMES_ZOOM:-16}" --mute 2>&1)
  kill "$server" 2>/dev/null; wait "$server" 2>/dev/null
  line=$(grep '^CLIENT_FRAMES ' <<<"$out" | tail -1)
  rm -rf "$dir"
  [ -n "$line" ] || { echo "JOB frames FAIL no CLIENT_FRAMES line (no display, or the client died)"; return 1; }
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
  command -v cargo >/dev/null 2>&1 || { echo "JOB realm SKIP cargo is not installed on this station"; return 0; }
  local c out line bad=0 detail=""
  for c in realm/check.sh realm/store/check.sh; do
    [ -f "$c" ] || continue
    out=$(timeout "${STATION_REALM_TIMEOUT:-3600}" bash "$c" 2>&1); line=$(tail -1 <<<"$out")
    if [[ "$line" == *" ok "* ]]; then detail+=" | ${line:0:120}"
    else bad=$((bad + 1)); detail+=" | $c: $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-200)"; fi
  done
  echo "JOB realm $([ $bad -eq 0 ] && echo PASS || echo FAIL)${detail# |}"
  return $bad
}
job_idle() { echo "JOB idle INFO this station has no job yet"; }
job_deep() {  # between merges: a fresh seed each pass; a big crash fuzz of the store and a full-size field bench
  command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  command -v cargo >/dev/null 2>&1 || { echo "JOB deep SKIP cargo is not installed on this station"; return 0; }
  local seed=$(( (RANDOM << 15 | RANDOM) % 1000000 + 1 )) field=$(( RANDOM % 6 )) out bad=0 detail="" dir
  dir="${TMPDIR:-/tmp}/station-deep-$MACHINE"; rm -rf "$dir"; mkdir -p "$dir"
  ( cd realm && cargo build --release -j2 -q ) >/dev/null 2>&1 && ( cd realm/store && cargo build --release -j2 -q ) >/dev/null 2>&1 \
    || { echo "JOB deep FAIL build"; return 1; }
  if out=$(timeout 1800 realm/store/target/release/realm-store fuzz --seed=$seed --ops="${STATION_DEEP_OPS:-50000}" --kills=200 --dir="$dir/fuzz" 2>&1); then
    detail+=" | fuzz seed=$seed $(tail -1 <<<"$out" | cut -c1-120)"
  else bad=$((bad + 1)); detail+=" | fuzz seed=$seed FAILED: $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-200)"; fi
  if out=$(timeout 1800 realm/target/release/realm-server --bench --field=$field --seed=$seed --bots=1000 --monsters=20000 --rally=0.3 --threads=2 --ticks="${STATION_DEEP_TICKS:-600}" --warmup=100 --report=300 2>&1); then
    detail+=" | bench field=$field seed=$seed $(tail -1 <<<"$out" | cut -c1-140)"
  else bad=$((bad + 1)); detail+=" | bench field=$field seed=$seed FAILED: $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-200)"; fi
  rm -rf "$dir"
  echo "JOB deep $([ $bad -eq 0 ] && echo PASS || echo FAIL)${detail# |}"
  return $bad
}

# A job is skipped for a commit that changed nothing it tests. $1 = job, stdin = the paths changed since this station's
# last commit. Godot jobs test everything except the realm, the docs and the stations themselves.
touched() {
  case "$1" in
    idle) return 0 ;;
    realm|frames) grep -q '^realm/' ;;
    *) grep -qvE '^(realm/|docs/|\.github/|\.claude/|tools/station/|tools/ops_board/|[^/]*\.md$)' ;;
  esac
}

publish() {  # $1 = report text, $2 = file (default <machine>.txt). Adds it to the results branch without touching the work tree.
  local blob parent tree commit idx
  for _try in 1 2 3; do
    git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null
    parent=$(git rev-parse -q --verify "refs/remotes/origin/$BRANCH" || true)
    idx=$(mktemp -u)
    [ -n "$parent" ] && GIT_INDEX_FILE="$idx" git read-tree "$parent"
    blob=$(git hash-object -w --stdin <<<"$1")
    GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo 100644 "$blob" "${2:-$MACHINE.txt}"
    tree=$(GIT_INDEX_FILE="$idx" git write-tree); rm -f "$idx"
    commit=$(git -c user.name="station $MACHINE" -c user.email="station@localhost" commit-tree "$tree" ${parent:+-p "$parent"} -m "$MACHINE: $(tail -1 <<<"$1")")
    GIT_TERMINAL_PROMPT=0 git push -q origin "$commit:refs/heads/$BRANCH" 2>/dev/null && return 0
    sleep 5
  done
  echo "station: could not push the report" >&2; return 1
}

# Watch mode restarts itself when a pull changed this script, so a station always runs the current version.
self_sum() { cat tools/station/station.sh tools/station/roles.txt 2>/dev/null | cksum; }
started=$(self_sum)
run_once() {
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
  if [ "$watch" = 1 ] && [ "$(self_sum)" != "$started" ]; then exec bash tools/station/station.sh "${ARGS[@]}"; fi
  local start=$SECONDS failed=0 body="" skipped=0 run=() j
  local base changed="" known=0; base=$(cat "$STATE" 2>/dev/null)
  if [ -n "$base" ] && changed=$(git diff --name-only "$base" "$head" 2>/dev/null); then known=1; fi
  for j in "${jobs[@]}"; do
    if [ $known = 1 ] && ! touched "$j" <<<"$changed"; then
      body+="JOB $j SKIP nothing it tests changed since ${base:0:7}"$'\n'; skipped=$((skipped + 1))
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
      body+="$("job_$j")"$'\n' || failed=$((failed + 1))
    done
    verdict="STATION $([ $failed -eq 0 ] && echo PASS || echo FAIL) jobs=${#run[@]} failed=$failed skipped=$skipped"
  fi
  local report="STATION machine=$MACHINE time=$(date -u +%Y-%m-%dT%H:%MZ) commit=${head:0:7} took=$((SECONDS - start))s"$'\n'"$body$verdict"
  echo "$head" >"$STATE"
  if [ $failed -gt 0 ] && [ -n "${STATION_ON_FAIL:-}" ]; then bash -c "$STATION_ON_FAIL" <<<"$report" >/dev/null 2>&1 || true; fi
  if [ "$push" = 1 ]; then publish "$report" || return 2; tail -1 <<<"$report"; else echo "$report"; fi
  [ $failed -eq 0 ]
}

if [ "$watch" = 1 ]; then
  while true; do
    run_once; rc=$?
    [ "$(self_sum)" = "$started" ] || exec bash tools/station/station.sh "$@"
    if [ $rc = 3 ] && [ "$deep" = 1 ]; then  # nothing new on main: one deep pass instead of sleeping
      t0=$SECONDS; body=$(job_deep); v=$([[ "$body" == *" PASS"* || "$body" == *" SKIP "* ]] && echo PASS || echo FAIL)
      rep="STATION machine=$MACHINE time=$(date -u +%Y-%m-%dT%H:%MZ) commit=$(git rev-parse --short=7 HEAD) took=$((SECONDS - t0))s"$'\n'"$body"$'\n'"STATION $v deep pass"
      if [ "$push" = 1 ]; then publish "$rep" "$MACHINE-deep.txt" || true; else echo "$rep"; fi
      continue
    fi
    sleep "$POLL"
  done
fi
run_once
exit $?
}
main "$@"

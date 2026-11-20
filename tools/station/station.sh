#!/usr/bin/env bash
# A station: a spare computer that runs long jobs with no Claude on it and reports a few lines.
# Usage: tools/station/station.sh [--watch] [--no-push] job [job ...]
#   jobs: boss    bots play STATION_SEEDS (default "7 21 33 101 102") to the Archlich, side by side
#         checks  tools/check_all.sh
#         frames  the real game at wave 10 with a full horde on this machine's screen and graphics card; FAIL when the
#                 95th-percentile frame is over STATION_FRAME_P95_MS (default 25). Needs a desktop session.
#         golden  tools/golden.sh against the commit this station tested last (INFO: did the game change?)
#   --after=M  relay: run a commit only once station M has reported PASS for it; if M failed, report HELD and do nothing
#   --watch    stay running: every STATION_POLL seconds (default 120) fetch origin/main and run the jobs on a new commit
#   --no-push  print the report instead of pushing it
# Run it from a clone kept for the station alone: it checks out origin/main detached and refuses a dirty tree.
# Report: branch `station-results`, file <machine>.txt (never main, never CI). Read with tools/station/read.sh.
# STATION_ON_FAIL: optional command run with the report on stdin when a job fails (for example to wake a helper).
# Quiet: prints the report's last line. Exit 0 pass, 1 a job failed, 2 could not run.
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
MACHINE="${STATION_NAME:-$(hostname)}"
SEEDS="${STATION_SEEDS:-7 21 33 101 102}"
POLL="${STATION_POLL:-120}"
BRANCH=station-results
watch=0; push=1; after=""; jobs=()
for a in "$@"; do
  case "$a" in --watch) watch=1 ;; --no-push) push=0 ;; --after=*) after="${a#--after=}" ;; boss|checks|frames|golden) jobs+=("$a") ;;
    *) echo "station: unknown argument $a" >&2; exit 2 ;; esac
done
[ ${#jobs[@]} -gt 0 ] || { echo "station: name at least one job (boss checks frames golden)" >&2; exit 2; }
STATE="$(git rev-parse --git-dir)/station_last"  # the commit this station tested last

job_boss() {  # one line: how each seed ended; FAIL on a crash, an engine error, or a run that did not finish
  local out; out=$(mktemp -d) bad=0 detail=""
  for s in $SEEDS; do
    ( timeout 1800 "$GODOT" --headless --path . -s tools/full_run.gd -- --wizards=4 "--seed=$s" >"$out/$s.log" 2>&1 ) &
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
  local line; line=$(tools/check_all.sh 2>&1 | tail -1)
  [[ "$line" == "CHECK_ALL PASS" ]] && { echo "JOB checks PASS"; return 0; }
  echo "JOB checks FAIL ${line:0:120}"; return 1
}
job_frames() {
  local line script p95 limit="${STATION_FRAME_P95_MS:-25}"
  local out; out=$(timeout 900 "$GODOT" --path . -- --autotest=10 --perf --seed=7 2>&1)
  line=$(grep '^PERF frames=' <<<"$out" | tail -1); script=$(grep '^PERF total_script' <<<"$out" | tail -1 | awk '{print $3}')
  [ -n "$line" ] || { echo "JOB frames FAIL no PERF line (no display, or the run died)"; return 1; }
  p95=$(sed -E 's/.* p95=([0-9.]+).*/\1/' <<<"$line")
  if awk -v a="$p95" -v b="$limit" 'BEGIN { exit !(a <= b) }'; then
    echo "JOB frames PASS ${line#PERF } script_ms=$script limit_p95=$limit"
  else
    echo "JOB frames FAIL ${line#PERF } script_ms=$script limit_p95=$limit"; return 1
  fi
}
job_golden() {  # information only: which pushes changed how the game plays
  local base; base=$(cat "$STATE" 2>/dev/null)
  [ -n "$base" ] && git cat-file -e "$base^{commit}" 2>/dev/null || { echo "JOB golden INFO first run, nothing to compare"; return 0; }
  echo "JOB golden INFO $(tools/golden.sh "$base" 2>&1 | tail -1) since ${base:0:7}"
}

publish() {  # $1 = report text. Adds <machine>.txt to the results branch without touching the work tree.
  local blob parent tree commit idx
  for _try in 1 2 3; do
    git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null
    parent=$(git rev-parse -q --verify "refs/remotes/origin/$BRANCH" || true)
    idx=$(mktemp -u)
    [ -n "$parent" ] && GIT_INDEX_FILE="$idx" git read-tree "$parent"
    blob=$(git hash-object -w --stdin <<<"$1")
    GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo 100644 "$blob" "$MACHINE.txt"
    tree=$(GIT_INDEX_FILE="$idx" git write-tree); rm -f "$idx"
    commit=$(git -c user.name="station $MACHINE" -c user.email="station@localhost" commit-tree "$tree" ${parent:+-p "$parent"} -m "$MACHINE: $(tail -1 <<<"$1")")
    GIT_TERMINAL_PROMPT=0 git push -q origin "$commit:refs/heads/$BRANCH" 2>/dev/null && return 0
    sleep 5
  done
  echo "station: could not push the report" >&2; return 1
}

run_once() {
  git fetch -q origin main || { echo "station: fetch failed" >&2; return 2; }
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "station: this clone has local changes; keep a clone for the station alone" >&2; return 2; }
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
  tools/import.sh >/dev/null 2>&1 || { echo "station: import failed" >&2; return 2; }
  local start=$SECONDS failed=0 body=""
  local verdict
  if [ -n "$held" ]; then
    verdict="STATION HELD $held"
  else
    for j in "${jobs[@]}"; do
      body+="$("job_$j")"$'\n' || failed=$((failed + 1))
    done
    verdict="STATION $([ $failed -eq 0 ] && echo PASS || echo FAIL) jobs=${#jobs[@]} failed=$failed"
  fi
  local report="STATION machine=$MACHINE time=$(date -u +%Y-%m-%dT%H:%MZ) commit=${head:0:7} took=$((SECONDS - start))s"$'\n'"$body$verdict"
  echo "$head" >"$STATE"
  if [ $failed -gt 0 ] && [ -n "${STATION_ON_FAIL:-}" ]; then bash -c "$STATION_ON_FAIL" <<<"$report" >/dev/null 2>&1 || true; fi
  if [ "$push" = 1 ]; then publish "$report" || return 2; tail -1 <<<"$report"; else echo "$report"; fi
  [ $failed -eq 0 ]
}

if [ "$watch" = 1 ]; then
  while true; do run_once; sleep "$POLL"; done
fi
run_once

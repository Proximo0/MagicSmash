#!/usr/bin/env bash
# The station work queue: functions sourced by station.sh (watch mode), queue.sh (the lead's tool) and queue_test.sh.
# Storage is two git branches, read and written without touching the work tree (same trick as station.sh `publish`):
#   station-queue    queue/<id>.job      one job, key=value lines: kind args needs priority repeat timeout_s added [every_s]
#                    claims/<id>.<m>     "machine= time=<epoch>": the push of this file is the lock
#                    done/<id>.<m>       "machine= time= status= passes=": the job finished on machine m
#   station-results  work/<id>/<m>.txt   one result line per pass (forever jobs append), work/<id>/art/<m>-<name> small artifacts
#                    <m>-hours.txt        one line a day: busy and idle hours
# Nothing from a job file is ever run as text: kind must be one of the functions qk_* below, and every argument is
# checked against a whitelist of characters (letters, digits, comma, dot, dash, underscore, equals, space) and then read
# by name (seeds=.. ops=..) with its own digit checks. `shell` runs only tools/station/jobs/<name>.sh.
# Needs from the caller (station.sh sets them): MACHINE, BRANCH (results). Optional functions of the caller are used when
# they exist: step_run and pending_merge (kill a long job when a merge lands), job_frames, publish_append.
# Job fields beyond the five: needs_free_mb (RAM that must be free to start; default by kind, 0 = no check), needs_gpu_idle (1 = no art
# generation may be using the GPU; default 1 for frames and for needs=gpu). A merge never kills a queue job longer than
# STATION_QUEUE_KILL_MAX_S (default 900 s timeout_s): the job finishes, then the station takes the new commit (step_run).
# STATION_QUEUE_STUB=1 replaces every heavy command with a stub line (tests); a seed of 666 makes the stub fail.
# Lanes (station.sh watch mode): a station runs up to Q_NLANES jobs at once, each in a background "lane" (lanes_fill). The station claims
# for a lane (claims/<id>.<machine>-<lane>), so two lanes never run one claim; a job runs in at most max_lanes lanes at once (all machines,
# default 1) and max_per_machine on one machine (default max_lanes). Lanes never build: the station builds once per commit (q_build_all)
# and copies the programs into a per-commit folder (Q_SNAP) the lanes run from, so a build never replaces a program a lane is running.
# Smart App Control (q_sac): a PC that refuses programs built here skips every job that runs them (q_ownbin) with one SKIP line per half hour.
: "${MACHINE:=${STATION_NAME:-$(hostname)}}"
: "${BRANCH:=station-results}"
QBRANCH="${STATION_QUEUE_BRANCH:-station-queue}"
Q_CAP="${STATION_QUEUE_ARTIFACT_CAP:-2097152}"   # bytes of artifacts a job may publish
Q_KINDS="fuzz soak bench balance economy frames package shell"
Q_WARNED_FILE="${TMPDIR:-/tmp}/station-queue-warned-${MACHINE//[^A-Za-z0-9_-]/_}"
Q_RBIN=realm/target/release; Q_SBIN=realm/store/target/release   # where jobs find the programs; a lane uses its commit's copy (Q_SNAP)

q_now() { date +%s; }
q_me() { printf %s "${MACHINE//[^A-Za-z0-9_-]/_}"; }
q_rand() { echo $(( ((RANDOM << 15) | RANDOM) % 1000000 + 1 )); }
Q_GD="$(git rev-parse --git-dir 2>/dev/null)"; Q_ATT="$Q_GD/station_attempts"; Q_SPOOL="$Q_GD/station_spool"   # local state: "id count" lines; unsent "id line" lines
Q_LD="$Q_GD/station_lanes"   # one file per busy lane: "pid= id= kind= start= mb= timeout="; <lane>.cool = epoch until the lane may start again
q_cl() { printf %s "$(q_me)-${Q_LANE:-0}"; }   # this lane's claim suffix; lane 0 = `queue.sh step` by hand
q_lock() {  # $1 = file: a mkdir lock (Git Bash and Linux alike), broken after about 30 s (a lane killed while holding it)
  local n=0; while ! mkdir "$1.lock" 2>/dev/null; do n=$((n + 1)); [ $n -gt 300 ] && { rm -rf "$1.lock"; n=0; }; sleep 0.1; done
}
q_unlock() { rmdir "$1.lock" 2>/dev/null; return 0; }
q_lane_get() { local v; v=$(sed -n "s/.*\(^\| \)$2=\([^ ]*\).*/\2/p" "$1" 2>/dev/null | head -1); printf %s "${v:-${3:-}}"; }   # lane file, field, default
q_lane_live_f() { local p; p=$(q_lane_get "$1" pid); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
q_lane_runs() { [ -f "$Q_LD/$1" ] && q_lane_live_f "$Q_LD/$1" && [ "$(q_lane_get "$Q_LD/$1" id)" = "$2" ]; }   # lane, id
q_disk_gb() { timeout -k 30 20 df -Pk . 2>/dev/null | awk 'NR==2 { print int($4 / 1048576) }'; }   # free GB of the repo filesystem, empty when unknown
q_prune() {  # delete this station's own work dirs (station-job-<machine>-*, station-<what>-<machine>) under TMPDIR older than 24 h
  local t="${TMPDIR:-/tmp}" me; me=$(q_me); [ -n "$t" ] && [ -n "$me" ] && [ -d "$t" ] || return 0
  timeout -k 30 120 find "$t" -maxdepth 1 -mindepth 1 -type d -mmin +1440 \( -name "station-job-${me}-*" -o -name "station-*-${me}" \) -exec rm -rf {} + 2>/dev/null; return 0
}
q_att_get() { local i c; [ -f "$Q_ATT" ] && while read -r i c; do [ "$i" = "$1" ] && { echo "${c:-0}"; return; }; done <"$Q_ATT"; echo 0; }
q_att_set() {  # id count (0 clears); drops ids no longer in the queue (when Q_TREE is known), keeps at most 200 lines
  local i c tmp; tmp=$(mktemp)
  { [ -f "$Q_ATT" ] && while read -r i c; do
      [ "$i" = "$1" ] && continue; [ -z "${Q_TREE:-}" ] || grep -qx "queue/$i.job" <<<"$Q_TREE" || continue; echo "$i $c"; done <"$Q_ATT"
    [ "$2" -gt 0 ] && echo "$1 $2"; true; } | tail -200 >"$tmp"; mv -f "$tmp" "$Q_ATT"; return 0
}
q_att_add() {  # id delta: unfinished starts of a job on this machine (lanes of one job count together), under a lock
  local n; q_lock "$Q_ATT"; n=$(( $(q_att_get "$1") + $2 )); [ $n -lt 0 ] && n=0; q_att_set "$1" $n; q_unlock "$Q_ATT"; echo $n
}
q_spool_add() { q_lock "$Q_SPOOL"; echo "$1 $2" >>"$Q_SPOOL"; tail -200 "$Q_SPOOL" >"$Q_SPOOL.t" && mv -f "$Q_SPOOL.t" "$Q_SPOOL"; q_unlock "$Q_SPOOL"; }
q_spool_flush() {  # try the results that could not be published earlier; a failure leaves the rest for the next step
  local id line tmp rest=0; [ -s "$Q_SPOOL" ] || return 0; tmp=$(mktemp)
  q_lock "$Q_SPOOL"; mv -f "$Q_SPOOL" "$tmp.in"; q_unlock "$Q_SPOOL"   # lanes may append while we push
  while read -r id line; do
    if [ "$rest" = 0 ] && q_publish_result "$id" "$line" ""; then echo "queue: sent the spooled result of $id"; else rest=1; echo "$id $line" >>"$tmp"; fi
  done <"$tmp.in"
  [ -s "$tmp" ] && { q_lock "$Q_SPOOL"; cat "$tmp" >>"$Q_SPOOL"; q_unlock "$Q_SPOOL"; }; rm -f "$tmp" "$tmp.in"; return 0
}

# ---- git branch storage -------------------------------------------------------------------------------------------
gb_fetch() { git fetch -q origin "+refs/heads/$1:refs/remotes/origin/$1" 2>/dev/null; }   # fails when the branch does not exist yet
gb_cat() { git show "refs/remotes/origin/$1:$2" 2>/dev/null; }
gb_has() { git rev-parse -q --verify "refs/remotes/origin/$1" >/dev/null 2>&1; }
# gb_put BRANCH MESSAGE op...   op = +path:file (add or replace from a file) or -path (delete). One commit, one push on top of the
# freshly fetched branch; returns 1 when the push is rejected (somebody else got there first). gb_hook, when defined, runs
# between building the commit and pushing it (tests use it to make a race happen). GB_BASE=<commit> builds on that commit
# without fetching again, so a push is rejected when anybody pushed after the caller looked (q_claim: check and lock on one view).
gb_put() {
  local br=$1 msg=$2 parent idx blob tree commit op p f; shift 2
  if [ -n "${GB_BASE:-}" ]; then parent=$GB_BASE
  else gb_fetch "$br"; parent=$(git rev-parse -q --verify "refs/remotes/origin/$br" || true); fi
  idx=$(mktemp -u)
  [ -n "$parent" ] && GIT_INDEX_FILE="$idx" git read-tree "$parent"
  for op in "$@"; do
    case "$op" in
      +*) p=${op#+}; f=${p#*:}; p=${p%%:*}; blob=$(git hash-object -w "$f")
          GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo 100644 "$blob" "$p" ;;
      -*) GIT_INDEX_FILE="$idx" git update-index --force-remove "${op#-}" 2>/dev/null ;;
    esac
  done
  tree=$(GIT_INDEX_FILE="$idx" git write-tree); rm -f "$idx"
  commit=$(git -c user.name="station $MACHINE" -c user.email="station@localhost" commit-tree "$tree" ${parent:+-p "$parent"} -m "$msg")
  declare -F gb_hook >/dev/null && gb_hook
  GIT_TERMINAL_PROMPT=0 git push -q origin "$commit:refs/heads/$br" 2>/dev/null
}
gb_put_retry() {  # same, a few tries; for writes that only we make (results, done, release). Lanes of one station push at the same
  # moments, so the waits get a random part and there are 8 tries
  local n; for n in 1 2 3 4 5 6 7 8; do gb_put "$@" && return 0; sleep $(( ${STATION_QUEUE_RETRY_SLEEP:-3} + RANDOM % 4 )); done; return 1
}
q_fetch() {  # refresh our view of the queue branch; fails (nothing to do) when the branch does not exist
  gb_fetch "$QBRANCH" || return 1
  Q_TREE=$(git ls-tree -r --name-only "refs/remotes/origin/$QBRANCH" 2>/dev/null)
}
q_get() { sed -n "s/^$2=//p" <<<"$1" | tr -d '\r' | head -1; }
q_time_of() { sed -n 's/.*time=\([0-9]*\).*/\1/p' | head -1; }

# ---- validation ---------------------------------------------------------------------------------------------------
q_args_ok() {  # letters, digits, comma, dot, dash, underscore, equals and space only; no newline
  local re='^[A-Za-z0-9,._= -]*$'
  case "$1" in *$'\n'*) return 1 ;; esac
  [[ "$1" =~ $re ]]
}
q_valid_job() {  # uses the J_* variables; sets Q_WHY
  local re
  case " $Q_KINDS " in *" $J_KIND "*) ;; *) Q_WHY="unknown kind '${J_KIND:0:20}'"; return 1 ;; esac
  q_args_ok "$J_ARGS" || { Q_WHY="args hold characters outside letters digits , . - _ = space"; return 1; }
  re='^[A-Za-z0-9_.-]+$'; [[ "$J_NEEDS" =~ $re ]] || { Q_WHY="bad needs"; return 1; }
  re='^[0-9]$'; [[ "$J_PRIO" =~ $re ]] || { Q_WHY="bad priority"; return 1; }
  case "$J_REPEAT" in once|forever) ;; *) Q_WHY="bad repeat"; return 1 ;; esac
  re='^[0-9]+$'; [[ "$J_TIMEOUT" =~ $re ]] && [[ "$J_EVERY" =~ $re ]] || { Q_WHY="bad timeout_s or every_s"; return 1; }
  [[ "${J_MB:-0}" =~ $re ]] || { Q_WHY="bad needs_free_mb"; return 1; }
  re='^[01]$'; [[ "${J_GPUIDLE:-0}" =~ $re ]] || { Q_WHY="bad needs_gpu_idle"; return 1; }
  re='^([1-9]|[1-5][0-9]|6[0-4])$'; [[ "${J_MAXL:-1}" =~ $re ]] && [[ "${J_MAXM:-1}" =~ $re ]] || { Q_WHY="bad max_lanes or max_per_machine (1 to 64)"; return 1; }
  return 0
}
q_warn() {  # a line on stdout, once per job and reason
  grep -qxF "$1 $2" "$Q_WARNED_FILE" 2>/dev/null && return 0
  echo "$1 $2" >>"$Q_WARNED_FILE"; echo "queue: skipping job $1: $2" >&2
}
q_gpu() { case "${STATION_HAS_GPU:-}" in 1) return 0 ;; 0) return 1 ;; esac; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac; [ -n "${DISPLAY:-}" ]; }
# ---- resource gate: free RAM and the GPU, checked before a job starts (q_eligible) and while it runs (step_run) ------------------
q_default_mb() {  # RAM a kind needs free, by default (MB)
  case "$1" in fuzz) echo 512 ;; soak|balance|package) echo 1024 ;; bench|economy) echo 2048 ;; frames) echo 3072 ;; *) echo 256 ;; esac
}
Q_FREE_MB=""; Q_FREE_AT=0
q_free_mb_set() {  # sets Q_FREE_MB (empty = unknown, which never blocks); cached 60 s, because PowerShell is slow to start
  local now; now=$(q_now)
  [ -n "${STATION_FREE_MB:-}" ] && { Q_FREE_MB=$STATION_FREE_MB; return 0; }
  [ $((now - Q_FREE_AT)) -lt 60 ] && return 0
  Q_FREE_AT=$now; Q_FREE_MB=""
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)   # kB of free physical memory
    Q_FREE_MB=$(timeout -k 5 60 powershell.exe -NoProfile -Command '[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+$' | head -1) ;;
  esac
  if [ -z "$Q_FREE_MB" ] && [ -r /proc/meminfo ]; then
    Q_FREE_MB=$(awk '/^MemAvailable:/ { print int($2 / 1024); exit }' /proc/meminfo 2>/dev/null)
    [ -n "$Q_FREE_MB" ] || Q_FREE_MB=$(awk '/^MemFree:/ { print int($2 / 1024); exit }' /proc/meminfo 2>/dev/null)
  fi
  return 0
}
q_gpu_busy() {  # Horde & Hearth art generation owns the GPU while its status file says RUNNING (HH_ART_STATUS, "" = no such file)
  local gs="${HH_ART_STATUS-D:\\projects\\hh_art\\status.txt}"
  command -v cygpath >/dev/null 2>&1 && [ -n "$gs" ] && gs=$(cygpath -u "$gs" 2>/dev/null || echo "$gs")
  [ -n "$gs" ] && [ -f "$gs" ] && grep -q RUNNING "$gs" 2>/dev/null
}
q_reserved_mb() {  # RAM promised to lanes started in the last 5 minutes (a job takes a while to reach its size)
  local f t=0 now; now=$(q_now)
  for f in "$Q_LD"/[0-9]*; do
    case "$f" in *.cool|*.log) continue ;; esac; [ -f "$f" ] || continue
    [ $((now - $(q_lane_get "$f" start 0))) -lt 300 ] && q_lane_live_f "$f" && t=$((t + $(q_lane_get "$f" mb 0)))
  done; echo $t
}
q_resources_ok() {  # uses J_MB and J_GPUIDLE; 1 with Q_WHY when short
  if [ "${J_MB:-0}" -gt 0 ]; then
    q_free_mb_set
    local free=$Q_FREE_MB; [ -n "$free" ] && free=$((free - $(q_reserved_mb)))
    if [ -n "$free" ] && [ "$free" -lt "$J_MB" ]; then Q_WHY="needs ${J_MB} MB free RAM, only ${free} MB free"; [ "$free" != "$Q_FREE_MB" ] && Q_WHY+=" (${Q_FREE_MB} MB less what lanes just started)"; return 1; fi
  fi
  if [ "${J_GPUIDLE:-0}" = 1 ] && q_gpu_busy; then Q_WHY="the GPU is busy (art generation is RUNNING)"; return 1; fi
  return 0
}
q_skip() {  # $1 = id, $2 = why: one SKIP line on stderr per job and half an hour (the pick runs every few minutes)
  local f="$Q_WARNED_FILE.skip" now last; now=$(q_now)
  last=$(awk -v k="$1" '$1 == k { t = $2 } END { print t }' "$f" 2>/dev/null)
  [ -n "$last" ] && [ $((now - last)) -lt "${STATION_QUEUE_SKIP_NOTE_S:-1800}" ] && return 0
  echo "$1 $now" >>"$f"; echo "SKIP queue job $1: $2" >&2
}
# ---- Smart App Control and programs built here -------------------------------------------------------------------------------------
# q_ownbin: does the loaded job (J_*) start a program this station compiled (realm binaries, cargo test, the Godot module)? Built-in kinds
# all do except shell; `frames` too: it loads our GDExtension DLL (realm_godot) and starts realm-server. A shell script does when it names
# realm/target, target/release, STATION_BIN or cargo build/test/run, unless it carries the line `# station-sac: ok`. Field own_bin=0|1 overrides.
q_ownbin() {
  case "${J_OWNBIN:-}" in 0) return 1 ;; 1) return 0 ;; esac
  case "$J_KIND" in
    shell) local f="tools/station/jobs/$(q_tok "$J_ARGS" script "").sh"
           grep -q '^# station-sac: ok' "$f" 2>/dev/null && return 1
           grep -qE 'realm/target|target/release|STATION_BIN|cargo (build|test|run)' "$f" 2>/dev/null ;;
    *) return 0 ;;
  esac
}
# q_sac: 0 when this PC refuses programs built here (Windows Smart App Control on, or the build's test start was refused with 126).
# Read only, no setting is touched. Cached per commit in $Q_GD/station_sac. STATION_SAC=0|1 overrides (tests).
q_sac() {
  case "${STATION_SAC:-}" in 1) return 0 ;; 0) return 1 ;; esac
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *) return 1 ;; esac
  local head c v; head=$(git rev-parse -q --verify HEAD 2>/dev/null)
  read -r c v <"$Q_GD/station_sac" 2>/dev/null
  if [ "$c" != "$head" ]; then
    v=$(timeout -k 5 60 powershell.exe -NoProfile -NonInteractive -Command 'try { (Get-MpComputerStatus).SmartAppControlState } catch { "" }' 2>/dev/null | tr -d '\r ' | head -1)
    case "$v" in On) v=on ;; *) v=off ;; esac
    echo "$head $v" >"$Q_GD/station_sac"
  fi
  [ "$v" = on ] || [ "$v" = refused ]
}
q_needs_ok() {
  case "$J_NEEDS" in
    any) return 0 ;;
    gpu) q_gpu ;;
    linux) [ "$(uname -s)" = Linux ] ;;
    windows) case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac ;;
    *) [ "${J_NEEDS,,}" = "${MACHINE,,}" ] || [ "${J_NEEDS,,}" = "$(q_me | tr 'A-Z' 'a-z')" ] ;;
  esac
}
q_load() {  # $1 = id: read and validate queue/<id>.job into J_*; 0 usable here
  local txt; txt=$(gb_cat "$QBRANCH" "queue/$1.job" | tr -d '\r'); [ -n "$txt" ] || return 1
  J_KIND=$(q_get "$txt" kind); J_ARGS=$(q_get "$txt" args); J_NEEDS=$(q_get "$txt" needs); J_PRIO=$(q_get "$txt" priority)
  J_REPEAT=$(q_get "$txt" repeat); J_TIMEOUT=$(q_get "$txt" timeout_s); J_EVERY=$(q_get "$txt" every_s)
  J_MB=$(q_get "$txt" needs_free_mb); J_GPUIDLE=$(q_get "$txt" needs_gpu_idle); J_OWNBIN=$(q_get "$txt" own_bin)
  J_MAXL=$(q_get "$txt" max_lanes); J_MAXM=$(q_get "$txt" max_per_machine); : "${J_MAXL:=1}"; : "${J_MAXM:=$J_MAXL}"
  : "${J_NEEDS:=any}" "${J_PRIO:=5}" "${J_REPEAT:=once}" "${J_TIMEOUT:=3600}" "${J_EVERY:=0}"
  : "${J_MB:=$(q_default_mb "$J_KIND")}"
  if [ -z "$J_GPUIDLE" ]; then if [ "$J_KIND" = frames ] || [ "$J_NEEDS" = gpu ]; then J_GPUIDLE=1; else J_GPUIDLE=0; fi; fi
  q_valid_job || { q_warn "$1" "refused: $Q_WHY"; return 1; }
  if [ "$J_KIND" = shell ]; then
    local s; s=$(q_tok "$J_ARGS" script ""); re='^[A-Za-z0-9_-]+$'
    [[ "$s" =~ $re ]] && [ -f "tools/station/jobs/$s.sh" ] || { q_warn "$1" "skipped: no script tools/station/jobs/${s:-?}.sh here"; return 1; }
  fi
  [ "$J_TIMEOUT" -ge 60 ] || J_TIMEOUT=60
  # No job holds a station longer than this, whatever its file says (a 12 hour job once ran to its limit and recorded nothing).
  [ "$J_TIMEOUT" -le "${STATION_QUEUE_MAX_S:-14400}" ] || J_TIMEOUT="${STATION_QUEUE_MAX_S:-14400}"
  [ "$J_REPEAT" = once ] && { J_MAXL=1; J_MAXM=1; }   # a once job runs once
  [ "$J_MAXM" -le "$J_MAXL" ] || J_MAXM=$J_MAXL
  return 0
}
# q_eligible id: after q_load. Sets Q_KEY for ordering: finite (once) jobs first by priority, then the forever jobs, oldest
# run first with priority worth an hour of age, so a forever job of high priority cannot starve the others; a job already running
# in a lane counts two hours younger per lane, so free lanes spread over different jobs before they double up.
# Claims: another machine's claim is live until 2 x timeout_s old. This machine's claim (claims/<id>.<me>-<lane>) is live only while
# that lane really runs the job (its pid is alive): a claim left by a crash or a reboot never blocks this machine. Q_DEAD = the claim
# files a claim may remove. Live claims < max_lanes (all machines) and own live claims < max_per_machine, or the job waits.
q_eligible() {
  local id=$1 now f t last=0 cl dn me live=0 mine=0 L; now=$(q_now); me=$(q_me); Q_DEAD=""
  q_needs_ok || return 1
  if q_ownbin; then
    if q_sac; then Q_SAC_N=$((${Q_SAC_N:-0} + 1)); return 1; fi
    if [ -d "$Q_GD/station_build.lock" ]; then Q_BUILD_N=$((${Q_BUILD_N:-0} + 1)); return 1; fi   # lanes wait while the build replaces programs
    if [ "${Q_LANES_MODE:-0}" = 1 ] && [ -z "${Q_SNAP:-}" ]; then Q_NOSNAP_N=$((${Q_NOSNAP_N:-0} + 1)); return 1; fi  # this commit did not build
  fi
  cl=$(grep "^claims/$id\." <<<"$Q_TREE"); dn=$(grep "^done/$id\." <<<"$Q_TREE")
  for f in $cl; do
    L=${f#claims/$id.$me}
    if [ "$f" = "claims/$id.$me" ] || { [ "$L" != "$f" ] && [[ "$L" =~ ^-[0-9]+$ ]]; }; then   # ours (the plain form is from before lanes)
      L=${L#-}; t=$(gb_cat "$QBRANCH" "$f" | q_time_of)
      if [ -n "$L" ] && q_lane_runs "$L" "$id" && [ "$now" -lt $((${t:-0} + 2 * J_TIMEOUT)) ]; then live=$((live + 1)); mine=$((mine + 1)); else Q_DEAD+=" $f"; fi
    else
      t=$(gb_cat "$QBRANCH" "$f" | q_time_of)
      if [ "$now" -lt $((${t:-0} + 2 * J_TIMEOUT)) ]; then live=$((live + 1)); else Q_DEAD+=" $f"; fi
    fi
  done
  [ "$live" -ge "$J_MAXL" ] || [ "$mine" -ge "$J_MAXM" ] && return 1
  for f in $dn; do t=$(gb_cat "$QBRANCH" "$f" | q_time_of); [ "${t:-0}" -gt "$last" ] && last=$t; done
  if [ "$J_REPEAT" = once ]; then [ -n "$dn" ] && return 1; Q_KEY="0 $((9 - J_PRIO))"
  else [ $((now - last)) -ge "$J_EVERY" ] || return 1; Q_KEY="1 $((last - J_PRIO * 3600 + live * 7200))"; fi
  q_resources_ok || { q_skip "$id" "$Q_WHY"; return 1; }
  return 0
}
q_pick() {  # the best eligible job id, or nothing. Jobs held back by Smart App Control or the build get one SKIP line per half hour.
  local f id rows=""; Q_SAC_N=0; Q_BUILD_N=0; Q_NOSNAP_N=0
  for f in $(grep '^queue/.*\.job$' <<<"$Q_TREE"); do
    id=${f#queue/}; id=${id%.job}
    if q_load "$id" && q_eligible "$id"; then rows+="$Q_KEY $id"$'\n'; fi
  done
  [ "$Q_SAC_N" -gt 0 ] && q_skip own-binaries "$Q_SAC_N job(s) run programs built here and Smart App Control refuses them on this PC; taking only jobs that run signed programs"
  [ "$Q_BUILD_N" -gt 0 ] && q_skip build-running "$Q_BUILD_N job(s) wait while the build replaces the programs"
  [ "$Q_NOSNAP_N" -gt 0 ] && q_skip no-build "$Q_NOSNAP_N job(s) need this commit's programs and its build failed or has not run ($(tail -1 "$Q_GD/station_build.state" 2>/dev/null | cut -c1-200))"
  printf %s "$rows" | grep . | sort -k1,1n -k2,2n -k3,3 | head -1 | cut -d' ' -f3
}
q_claim() {  # $1 = id; the push is the lock. 0 won, 1 lost or no longer free
  local id=$1 tmp me f ops=() base; me=$(q_me)
  q_fetch || return 1
  base=$(git rev-parse -q --verify "refs/remotes/origin/$QBRANCH") || return 1   # the view we check below is the one we push on
  q_load "$id" && q_eligible "$id" || return 1
  tmp=$(mktemp); echo "machine=$MACHINE lane=${Q_LANE:-0} time=$(q_now)" >"$tmp"
  for f in $Q_DEAD; do ops+=("-$f"); done     # a stale claim (or our own left by a crash) is taken over: its file goes
  ops+=("+claims/$id.$(q_cl):$tmp")
  GB_BASE=$base gb_put "$QBRANCH" "$MACHINE claims $id" "${ops[@]}"; local rc=$?
  rm -f "$tmp"; return $rc
}

# ---- running a job ------------------------------------------------------------------------------------------------
q_tok() {  # $1 = args, $2 = name, $3 = default
  local t; for t in $1; do case "$t" in "$2="*) printf %s "${t#*=}"; return ;; esac; done; printf %s "${3:-}"
}
q_int() {  # value default min max
  local re='^[0-9]+$' v=$1
  [[ "$v" =~ $re ]] || v=$2; [ "$v" -lt "$3" ] && v=$3; [ "$v" -gt "$4" ] && v=$4; echo "$v"
}
q_list() {  # comma list of digits, at most 12 items, default $2
  local re='^[0-9]+(,[0-9]+){0,11}$'; [[ "$1" =~ $re ]] && echo "${1//,/ }" || echo "$2"
}
q_seeds() {  # $1 = seeds spec (empty, N, A-B or A,B,C), $2 = repeat. once: every seed of a range; forever: one random seed in it
  local s=$1 re='^[0-9]+$' a b
  case "$s" in
    *-*) a=${s%%-*}; b=${s#*-}
         if [[ "$a" =~ $re && "$b" =~ $re && "$b" -ge "$a" ]]; then
           if [ "$2" = forever ]; then echo $(( a + ((RANDOM << 15) | RANDOM) % (b - a + 1) ))
           else [ $((b - a)) -gt 199 ] && b=$((a + 199)); a=$(seq "$a" "$b" | tr '\n' ' '); echo "${a% }"; fi
         else q_rand; fi ;;
    *,*) q_list "$s" "$(q_rand)" ;;
    "") q_rand ;;
    *) [[ "$s" =~ $re ]] && echo "$s" || q_rand ;;
  esac
}
q_left() { local l=$((QDEADLINE - SECONDS)); [ "$l" -lt 10 ] && l=10; echo "$l"; }
q_late() { [ $((QDEADLINE - SECONDS)) -le 0 ]; }
q_cut() { [ $((QDEADLINE - SECONDS)) -le 5 ] && { [ "$1" = 124 ] || [ "$1" = 137 ]; }; }  # rc $1 is a timeout kill after the job deadline: a time limit, not a failure
q_cargo() {  # make cargo findable; 1 when it is not installed (stubbed runs do not need it)
  [ -n "${STATION_QUEUE_STUB:-}" ] && return 0
  command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  command -v cargo >/dev/null 2>&1
}
q_build() {  # build dir, cargo args...; output to $Q_WD/build.log. A lane does not build: the station built this commit once (Q_SNAP)
  [ -n "${STATION_QUEUE_STUB:-}" ] && return 0
  [ -n "${Q_SNAP:-}" ] && return 0
  local d=$1; shift; ( cd "$d" && timeout -k 30 3600 cargo build --release -j2 -q "$@" ) >>"$Q_WD/build.log" 2>&1
}
# q_run OUTFILE cmd...: runs it in the background and kills it when a merge lands (step_run polls pending_merge); 99 = killed
q_run() {
  local f=$1; shift
  if [ -n "${STATION_QUEUE_STUB:-}" ] && [ "$QK" != shell ]; then  # shell jobs are light scripts of the repo: they run for real
    case "$QK" in soak) echo "SOAK ok stub" ;; economy) echo "ECONOMY ok stub" ;; balance) echo "BALANCE careers=0 stub" ;; *) echo "$QK ok stub" ;; esac >"$f"
    [ -n "${STATION_QUEUE_STUB_SLEEP:-}" ] && sleep "$STATION_QUEUE_STUB_SLEEP"
    case " $* " in *=666\ *|*=666) echo "stub failure" >>"$f"; return 1 ;; esac
    return 0
  fi
  # Windows can refuse to start a program it is still scanning right after a build ("Permission denied", status 126;
  # seen on the laptop after merges): wait and try again, up to 4 starts.
  local try rc
  for try in 1 2 3 4; do
    if declare -F step_run >/dev/null; then step_run "$f" "$@"; rc=$?; else "$@" >"$f" 2>&1; rc=$?; fi
    [ "$rc" = 126 ] && [ "$try" -lt 4 ] && grep -q "Permission denied" "$f" 2>/dev/null || return "$rc"
    echo "queue: could not start $QK (Permission denied), trying again in ${STATION_QUEUE_EXEC_WAIT:-20} s" >&2; sleep "${STATION_QUEUE_EXEC_WAIT:-20}"
  done
}
fail_detail() {  # stdin = a check's output; one compact line (about 600 characters) naming the failed tests and each first panic
  tr -d '\r' | awk '
    /^test .* \.\.\. FAILED/ { n = $2; if (!(n in seen)) { seen[n] = 1; names = names (names ? " " : "") n } }
    /^---- .* stdout ----/ { n = $2; if (!(n in seen)) { seen[n] = 1; names = names (names ? " " : "") n } }
    /to rerun pass/ { r = $0; sub(/.*to rerun pass `/, "", r); sub(/`.*/, "", r); rerun = r }
    /^(REALM|STORE) failed:/ { fin = $0 }
    want { m = $0; sub(/^ +/, "", m); panics = panics " " where ": " m ";"; want = 0; next }
    /panicked at / {
      if (np >= 3) next; np++
      t = $0; w = $0; sub(/.*panicked at /, "", w)
      c = substr(w, 1, 1)
      if (c == sprintf("%c", 39) || c == "\"") {   # old style: panicked at (quote)msg(quote), file:line:col
        f = w; sub(/.*, /, "", f); m = w; sub(/, [^ ]+$/, "", m); panics = panics " " f ": " m ";"
      } else { sub(/:$/, "", w); sub(/:[0-9]+$/, "", w); where = w; want = 1 }
    }
    END {
      o = ""
      if (names != "") o = "failed tests: " names
      if (panics != "") o = o (o ? " | " : "") "panic:" panics
      if (rerun != "") o = o (o ? " | " : "") "rerun " rerun
      if (fin != "") o = o (o ? " | " : "") fin
      if (o != "") print o
    }' | tr '\n' ' ' | cut -c1-600
}
q_tail() { tail -3 "$1" | tr -d '\r' | tr '\n' ' ' | cut -c1-1500; }   # a failure's last lines: long enough to hold the cause

q_lanes() {  # how many seeds one fuzz job runs side by side: lanes=N in the args, else STATION_FUZZ_LANES, else 1 inside a station
  # lane (the station's lanes already fill the cores), else cores-1 capped by memory (`queue.sh step` by hand)
  local n c m; n=$(q_tok "$1" lanes); [ -n "$n" ] || n=${STATION_FUZZ_LANES:-}
  [ -z "$n" ] && [ "${Q_IN_LANE:-0}" = 1 ] && n=1
  if [ -z "$n" ]; then
    c=$(nproc 2>/dev/null || echo "${NUMBER_OF_PROCESSORS:-2}"); n=$((c - 1))
    m=$(awk '/MemTotal/ {print int($2 / 1024 / 1500)}' /proc/meminfo 2>/dev/null); [ -n "$m" ] && [ "$m" -lt "$n" ] && n=$m
  fi
  q_int "$n" 1 1 16
}
qk_fuzz() {  # args: seeds=A-B ops=N kills=N lanes=N. realm-store fuzz per seed, `lanes` seeds at a time (one core each).
  local args=$1 rep=$2 s seeds="" ops kills bad=0 n=0 detail="" rc lanes i batch
  q_cargo || { echo "FAIL cargo is not installed on this station"; return 0; }
  ops=$(q_int "$(q_tok "$args" ops)" 50000 100 5000000); kills=$(q_int "$(q_tok "$args" kills)" 200 1 100000)
  lanes=$(q_lanes "$args")
  q_build realm/store || { echo "FAIL build $(q_tail "$Q_WD/build.log")"; return 0; }
  if [ "$rep" = forever ]; then  # a forever pass draws one seed for every lane
    for ((i = 0; i < lanes; i++)); do seeds+=" $(q_seeds "$(q_tok "$args" seeds)" forever)"; done
  else seeds=$(q_seeds "$(q_tok "$args" seeds)" "$rep"); fi
  set -- $seeds
  while [ $# -gt 0 ]; do
    q_late && { detail+=" stopped at the time limit;"; break; }
    batch=""
    for ((i = 0; i < lanes && $# > 0; i++)); do
      s=$1; shift; batch+=" $s"
      ( q_run "$Q_WD/fuzz.$s" timeout -k 30 "$(q_left)" "$Q_SBIN"/realm-store fuzz --seed=$s --ops=$ops --kills=$kills --dir="$Q_WD/fz$s"; echo $? >"$Q_WD/rc.$s" ) &
    done
    wait
    for s in $batch; do
      rc=$(cat "$Q_WD/rc.$s" 2>/dev/null || echo 1)
      [ "$rc" = 99 ] && return 3
      n=$((n + 1)); rm -rf "$Q_WD/fz$s"
      if [ "$rc" = 0 ]; then LAST="$(tail -1 "$Q_WD/fuzz.$s" | cut -c1-100)"; elif q_cut "$rc"; then detail+=" seed=$s stopped at the time limit;"; else bad=$((bad + 1)); detail+=" seed=$s FAILED: $(q_tail "$Q_WD/fuzz.$s");"; fi
    done
  done
  echo "$([ $bad = 0 ] && echo PASS || echo FAIL) fuzz seeds_run=$n lanes=$lanes ops=$ops kills=$kills${detail}${LAST:+ last: $LAST}"
}
qk_soak() {  # args: secs=N bots=N seeds=A-B
  local args=$1 rep=$2 secs bots seed out rc
  q_cargo || { echo "FAIL cargo is not installed on this station"; return 0; }
  secs=$(q_int "$(q_tok "$args" secs)" 900 5 14400); bots=$(q_int "$(q_tok "$args" bots)" 40 1 400)
  seed=$(q_seeds "$(q_tok "$args" seeds)" forever | cut -d' ' -f1)
  q_build realm -p realm-gateway --bin realm-soak || { echo "FAIL seed=$seed build $(q_tail "$Q_WD/build.log")"; return 0; }
  q_run "$Q_WD/soak.out" timeout -k 30 "$(q_left)" "$Q_RBIN"/realm-soak --bots="$bots" --secs="$secs" --seed="$seed" --fields=0,1,2,3,4,5 --monsters=3000 --progress=0 --fast --db="$Q_WD/soak.db"; rc=$?
  [ $rc = 99 ] && return 3
  out=$(tail -1 "$Q_WD/soak.out")
  if [[ "$out" == "SOAK ok "* ]]; then echo "PASS soak seed=$seed secs=$secs ${out:0:200}"; elif q_cut $rc; then echo "INFO soak seed=$seed secs=$secs stopped at the time limit"; else echo "FAIL soak seed=$seed secs=$secs $(q_tail "$Q_WD/soak.out")"; fi
}
qk_bench() {  # args: fields=0,1 threads=1,2 monsters=5000,20000 bots=N ticks=N seeds=.. ; one CSV row per combination
  local args=$1 rep=$2 f t m bots ticks seed rc n=0 bad=0 detail="" csv="$Q_WD/art/bench.csv"
  q_cargo || { echo "FAIL cargo is not installed on this station"; return 0; }
  bots=$(q_int "$(q_tok "$args" bots)" 1000 1 20000); ticks=$(q_int "$(q_tok "$args" ticks)" 600 50 20000)
  seed=$(q_seeds "$(q_tok "$args" seeds)" forever | cut -d' ' -f1)
  q_build realm || { echo "FAIL seed=$seed build $(q_tail "$Q_WD/build.log")"; return 0; }
  echo "field,threads,monsters,seed,status,summary" >"$csv"
  for f in $(q_list "$(q_tok "$args" fields)" 0); do for t in $(q_list "$(q_tok "$args" threads)" 2); do for m in $(q_list "$(q_tok "$args" monsters)" 20000); do
    q_late && { detail+=" stopped at the time limit;"; break 3; }
    q_run "$Q_WD/bench.out" timeout -k 30 "$(q_left)" "$Q_RBIN"/realm-server --bench --field=$f --seed=$seed --bots=$bots --monsters=$m --rally=0.3 --threads=$t --ticks=$ticks --warmup=100 --report=300; rc=$?
    [ $rc = 99 ] && return 3
    n=$((n + 1)); LAST=$(tail -1 "$Q_WD/bench.out" | tr -d ',' | cut -c1-140)
    if [ $rc = 0 ]; then echo "$f,$t,$m,$seed,ok,$LAST" >>"$csv"; elif q_cut $rc; then detail+=" stopped at the time limit;"; echo "$f,$t,$m,$seed,cut,$LAST" >>"$csv"; else bad=$((bad + 1)); detail+=" field=$f threads=$t monsters=$m FAILED: $(q_tail "$Q_WD/bench.out");"; echo "$f,$t,$m,$seed,FAIL,$LAST" >>"$csv"; fi
  done; done; done
  echo "$([ $bad = 0 ] && echo PASS || echo FAIL) bench seed=$seed runs=$n bad=$bad${detail} last: ${LAST:-none}"
}
qk_balance() {  # args: seeds=N (cohorts) per=N minutes=N fast=K hours=N. fast is the compression k of career.rs (an outing counts k
  # times as long), 16 as in balance.md, never 0 or 1 here: uncompressed careers take days and print nothing. realm-loadtest balance career; record only
  local args=$1 n per mins fast hours rc line
  q_cargo || { echo "FAIL cargo is not installed on this station"; return 0; }
  n=$(q_int "$(q_tok "$args" seeds)" 1 1 50); per=$(q_int "$(q_tok "$args" per)" 2 1 20); mins=$(q_int "$(q_tok "$args" minutes)" 20 1 600)
  fast=$(q_int "$(q_tok "$args" fast)" 16 2 64); hours=$(q_int "$(q_tok "$args" hours)" 200 1 2000)
  q_build realm -p realm-loadtest || { echo "FAIL build $(q_tail "$Q_WD/build.log")"; return 0; }
  BOT_THREADS="${STATION_BALANCE_THREADS:-2}" q_run "$Q_WD/balance.out" timeout -k 30 "$(q_left)" "$Q_RBIN"/realm-loadtest balance career "$n" "$per" "$mins" "$fast" "$hours"; rc=$?
  [ $rc = 99 ] && return 3
  line=$(grep '^BALANCE ' "$Q_WD/balance.out" | tail -1)
  tail -300 "$Q_WD/balance.out" >"$Q_WD/art/balance.out"
  if [ -n "$line" ]; then
    { echo "cohorts,per,minutes,fast,summary"; echo "$n,$per,$mins,$fast,$(tr -d ',' <<<"${line:8}")"; } >"$Q_WD/art/balance.csv"
    echo "INFO balance cohorts=$n per=$per ${line:8:220}"
  else echo "FAIL balance cohorts=$n no BALANCE line: $(q_tail "$Q_WD/balance.out")"; fi
}
qk_economy() {  # args: seeds=A-B days=N bots=N. realm-economy per seed; record only
  local args=$1 rep=$2 s days bots rc line n=0 bad=0 csv="$Q_WD/art/economy.csv" first=""
  q_cargo || { echo "FAIL cargo is not installed on this station"; return 0; }
  days=$(q_int "$(q_tok "$args" days)" 180 1 3650); bots=$(q_int "$(q_tok "$args" bots)" 4000 10 50000)
  q_build realm -p realm-gateway --bin realm-economy || { echo "FAIL build $(q_tail "$Q_WD/build.log")"; return 0; }
  echo "seed,bots,days,status,summary" >"$csv"
  for s in $(q_seeds "$(q_tok "$args" seeds)" "$rep"); do
    q_late && break
    q_run "$Q_WD/eco.out" timeout -k 30 "$(q_left)" "$Q_RBIN"/realm-economy --bots="$bots" --days="$days" --seed=$s --quiet --db="$Q_WD/eco.db"; rc=$?
    [ $rc = 99 ] && return 3
    rm -f "$Q_WD"/eco.db*; line=$(tail -1 "$Q_WD/eco.out" | tr -d ',' | cut -c1-240)
    n=$((n + 1)); first=${first:-$s}
    if q_cut $rc; then LAST="seed=$s stopped at the time limit"; break
    elif [[ "$line" == "ECONOMY ok "* ]]; then echo "$s,$bots,$days,ok,${line:8}" >>"$csv"; LAST="seed=$s ${line:8:200}"
    else bad=$((bad + 1)); echo "$s,$bots,$days,fail,$line" >>"$csv"; LAST="seed=$s no ECONOMY ok line: $(q_tail "$Q_WD/eco.out")"; fi
  done
  echo "$([ $bad = 0 ] && echo INFO || echo FAIL) economy runs=$n bad=$bad $LAST"
}
qk_frames() {  # args: zooms=16,4 secs=60. The client frame test of job_frames; needs a screen or xvfb
  local args=$1 zooms secs line
  zooms=$(q_list "$(q_tok "$args" zooms)" 16); zooms=${zooms// /,}; secs=$(q_int "$(q_tok "$args" secs)" 60 5 600)
  if [ -n "${STATION_QUEUE_STUB:-}" ]; then echo "INFO frames zooms=$zooms stub"; return 0; fi
  declare -F job_frames >/dev/null || { echo "FAIL frames: not available outside station.sh"; return 0; }
  line=$(STATION_FRAMES_ZOOM="$zooms" STATION_FRAMES_SECS="$secs" STATION_SHOTS=0 job_frames 2>&1 | tail -1)  # job_frames is a function: its own cargo builds (3600 s) and godot runs (180/300/120 s) are bounded inside it
  line=${line#JOB frames }
  case "$line" in PASS*|INFO*|FAIL*) echo "$line" ;; *) echo "FAIL frames $line" ;; esac
}
qk_package() {  # args: target=linux|windows. Server and client into a dated folder, with a hash of its files
  local args=$1 target bins out ver commit ext="" root hash cl="no client" keep
  target=$(q_tok "$args" target linux)
  case "$target" in linux|windows) ;; *) echo "FAIL package: target must be linux or windows"; return 0 ;; esac
  local here=linux; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) here=windows ;; esac
  [ "$target" = "$here" ] || { echo "INFO package target=$target skipped: this machine is $here"; return 0; }
  [ "$target" = windows ] && ext=.exe
  commit=$(git rev-parse --short=7 HEAD 2>/dev/null || echo nogit); ver="$(date -u +%Y%m%d)-$commit"
  root="${STATION_PACKAGE_DIR:-$HOME/station-packages}"; out="$root/$(date -u +%Y%m%d)-$target-$commit"
  if [ -n "${STATION_QUEUE_STUB:-}" ]; then echo "INFO package target=$target dir=$out hash=stub"; return 0; fi
  q_cargo || { echo "FAIL cargo is not installed on this station"; return 0; }
  q_build realm || { echo "FAIL package build $(q_tail "$Q_WD/build.log")"; return 0; }
  q_build realm/store || { echo "FAIL package store build $(q_tail "$Q_WD/build.log")"; return 0; }
  bins="$Q_WD/bins"; mkdir -p "$bins"
  for b in realm-gateway realm-server realm-ops; do cp "$Q_RBIN/$b$ext" "$bins/" 2>/dev/null || { echo "FAIL package: $Q_RBIN/$b$ext missing"; return 0; }; done
  cp "$Q_SBIN/realm-store$ext" "$bins/" 2>/dev/null
  rm -rf "$out"; mkdir -p "$out"
  q_run "$Q_WD/pkg.out" timeout -k 30 "$(q_left)" "$Q_RBIN"/realm-ops$ext package --bins="$bins" --out="$out/server" --version="$ver" --host=realm/ops/host
  [ $? = 0 ] || { echo "FAIL package: realm-ops package: $(q_tail "$Q_WD/pkg.out")"; return 0; }
  if command -v "${GODOT:-godot}" >/dev/null 2>&1 && [ -f realm/client/export_presets.cfg ] && [ "$target" = windows ]; then
    mkdir -p "$out/client"
    if timeout -k 30 900 "${GODOT:-godot}" --headless --path realm/client --export-release "Windows Desktop" "$out/client/HordeAndHearth.exe" >"$Q_WD/export.out" 2>&1 && [ -s "$out/client/HordeAndHearth.exe" ]; then cl="client exported"; else cl="client export failed"; fi
  fi
  hash=$( (cd "$out" && find . -type f | sort | xargs sha256sum 2>/dev/null) | sha256sum | cut -c1-16)
  echo "$hash  $ver $target" >"$out/HASH.txt"
  keep=$(ls -d "$root"/*-"$target"-* 2>/dev/null | sort | head -n -"${STATION_PACKAGE_KEEP:-5}"); [ -n "$keep" ] && rm -rf $keep
  echo "INFO package target=$target version=$ver hash=$hash dir=$out $cl"
}
qk_shell() {  # args: script=NAME plus words for it. tools/station/jobs/NAME.sh; its last stdout line is the summary
  local args=$1 name rest="" t rc line
  name=$(q_tok "$args" script ""); for t in $args; do case "$t" in script=*) ;; *) rest+=" $t" ;; esac; done
  STATION_BIN="${Q_SNAP:-}" STATION_JOB_ART="$Q_WD/art" STATION_JOB_SEED="$(q_rand)" q_run "$Q_WD/shell.out" timeout -k 30 "$(q_left)" bash "tools/station/jobs/$name.sh" $rest; rc=$?
  [ $rc = 99 ] && return 3
  q_cut $rc && { echo "INFO shell $name stopped at the time limit"; return 0; }
  line=$(tail -1 "$Q_WD/shell.out" | cut -c1-240)
  case "$line" in PASS*|FAIL*|INFO*) [ $rc = 0 ] && echo "$line" || echo "FAIL ${line#* }" ;; *) [ $rc = 0 ] && echo "INFO shell $name: $line" || echo "FAIL shell $name rc=$rc: $line" ;; esac
}
q_exec() {  # kind args repeat -> one line "STATUS summary" on stdout; 3 = interrupted
  case "$1" in
    fuzz|soak|bench|balance|economy|frames|package|shell) "qk_$1" "$2" "$3" ;;
    *) echo "SKIP unknown kind $1" ;;
  esac
}

q_publish_result() {  # id line artdir: result line appended to work/<id>/<machine>.txt plus small artifacts, in one push
  local id=$1 line=$2 art=$3 n tmp f sz total=0 skipped="" ops old
  tmp=$(mktemp)
  for n in 1 2 3 4 5 6 7 8; do
    gb_fetch "$BRANCH"; old=$(gb_cat "$BRANCH" "work/$id/$MACHINE.txt" | tail -300)
    { [ -n "$old" ] && printf '%s\n' "$old"; printf '%s\n' "$line"; } >"$tmp"
    ops=("+work/$id/$MACHINE.txt:$tmp"); total=0; skipped=""
    for f in $(ls -S -r "$art" 2>/dev/null); do   # smallest first, so one big file cannot crowd out the rest
      sz=$(wc -c <"$art/$f"); sz=${sz// /}
      if [ $((total + sz)) -le "$Q_CAP" ] && [ "$sz" -gt 0 ]; then total=$((total + sz)); ops+=("+work/$id/art/$(q_me)-$f:$art/$f"); else skipped+=" $f"; fi
    done
    if gb_put "$BRANCH" "$MACHINE: job $id ${line%% *}" "${ops[@]}"; then rm -f "$tmp"; [ -n "$skipped" ] && echo "queue: artifacts over the ${Q_CAP}-byte cap not published:$skipped"; return 0; fi
    sleep $(( ${STATION_QUEUE_RETRY_SLEEP:-3} + RANDOM % 4 ))
  done
  rm -f "$tmp"; return 1
}
q_run_job() {  # $1 = id, claimed by us. 0 done, 3 interrupted (claim released)
  local id=$1 me line rc status t0=$SECONDS tmp passes=1 prev n cl; me=$(q_me); cl=$(q_cl); Q_FAST_FAIL=0
  q_load "$id" || { gb_put_retry "$QBRANCH" "$MACHINE releases $id" "-claims/$id.$cl"; return 0; }
  QK=$J_KIND; Q_WD=$(mktemp -d "${TMPDIR:-/tmp}/station-job-$me-XXXXXX"); mkdir -p "$Q_WD/art"; QDEADLINE=$((SECONDS + J_TIMEOUT)); LAST=""
  mkdir -p "$Q_WD/tmp"
  echo "queue: $MACHINE runs $id kind=$J_KIND args='$J_ARGS' repeat=$J_REPEAT lane=${Q_LANE:-0}"
  # step_run reads these: a merge may kill only a short job; a long one finishes first (a merge used to throw away up to hours of work)
  Q_IN_JOB=1; Q_KILLABLE=0; [ "$J_TIMEOUT" -le "${STATION_QUEUE_KILL_MAX_S:-900}" ] && Q_KILLABLE=1
  # Unfinished starts on this machine (lanes of one job add up): the third beyond its lanes is the last. Its own TMPDIR keeps a lane's
  # temporary files (databases, scratch dirs of the scripts) apart from every other lane's, and goes with the work dir.
  n=$(q_att_get "$id")
  if [ "$n" -ge $((2 + J_MAXM)) ]; then line="FAIL parked: started $n times on this machine without finishing"; rc=0; echo "queue: $id parked"; n=-1
  else q_att_add "$id" 1 >/dev/null; line=$(TMPDIR="$Q_WD/tmp" q_exec "$J_KIND" "$J_ARGS" "$J_REPEAT" 2>"$Q_WD/stderr.log"); rc=$?; fi
  Q_IN_JOB=0; Q_KILLABLE=0
  [ -s "$Q_WD/stderr.log" ] && tail -20 "$Q_WD/stderr.log" >&2
  if [ $rc = 3 ]; then
    q_att_add "$id" -1 >/dev/null; rm -rf "$Q_WD"; gb_put_retry "$QBRANCH" "$MACHINE releases $id" "-claims/$id.$cl"; echo "queue: job $id interrupted (a merge landed or the GPU was needed); claim released"; return 3
  fi
  if [ -z "$line" ]; then  # silent death: say how it ended and what it last wrote
    local last; last=$(ls -t "$Q_WD" 2>/dev/null | grep -v '^stderr.log$' | head -1)
    line="FAIL job printed nothing (exit $rc; stderr: $(tail -5 "$Q_WD/stderr.log" 2>/dev/null | tr -d '\r' | tr '\n' ' ' | cut -c1-600); last output${last:+ $last}: $([ -f "$Q_WD/$last" ] && tail -3 "$Q_WD/$last" | tr -d '\r' | tr '\n' ' ' | cut -c1-600))"
  fi
  status=${line%% *}; case "$status" in PASS|FAIL|INFO|SKIP) ;; *) status=FAIL; line="FAIL $line" ;; esac
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ) $status id=$id kind=$J_KIND secs=$((SECONDS - t0)) ${line#* }"
  if ! q_publish_result "$id" "$line" "$Q_WD/art"; then   # keep the line (not the artifacts) for the next step
    echo "queue: could not publish the result of $id (spooled for the next step)"; q_spool_add "$id" "$line"
  fi
  if [ "$n" = -1 ]; then q_lock "$Q_ATT"; q_att_set "$id" 0; q_unlock "$Q_ATT"; else q_att_add "$id" -1 >/dev/null; fi
  tmp=$(mktemp)
  prev=$(gb_cat "$QBRANCH" "done/$id.$me" | sed -n 's/.*passes=\([0-9]*\).*/\1/p'); [ -n "$prev" ] && passes=$((prev + 1))
  echo "machine=$MACHINE time=$(q_now) status=$status passes=$passes" >"$tmp"
  gb_put_retry "$QBRANCH" "$MACHINE done $id $status" "+done/$id.$me:$tmp" "-claims/$id.$cl" || echo "queue: could not record done for $id (the claim will go stale)"
  rm -f "$tmp"; rm -rf "$Q_WD"
  [ "$status" = FAIL ] && [ $((SECONDS - t0)) -lt 60 ] && Q_FAST_FAIL=1  # the station loop sleeps STATION_QUEUE_FAIL_SLEEP before the next step
  echo "queue: $id $status ${line:0:200}"
  if [ "$status" = FAIL ] && declare -F publish_append >/dev/null; then publish_append "$(date -u +%Y-%m-%dT%H:%MZ) $MACHINE queue ${line:0:1500}" "$MACHINE-failures.txt" || true; fi
  return 0
}
queue_step() {  # one job from the queue, here and now (`queue.sh step`, lane 0). 0 ran one, 1 nothing to do, 3 interrupted by a merge
  local id tries=0; Q_LANE=${Q_LANE:-0}
  q_prune; q_spool_flush
  while [ $tries -lt 5 ]; do
    q_fetch || return 1
    id=$(q_pick); [ -n "$id" ] || return 1
    if q_claim "$id"; then q_run_job "$id"; return $?; fi
    tries=$((tries + 1)); sleep 1
  done
  return 1
}

# ---- lanes: the station runs Q_NLANES queue jobs at once (station.sh watch mode) ------------------------------------------------------
q_lane_total() {  # STATION_LANES, else the line "lanes: <machine> N" of roles.txt, else cores/2 capped at total RAM / 1.5 GB (1 to 32)
  local n c m; n=${STATION_LANES:-}
  [ -n "$n" ] || n=$(awk -v m="$(q_me | tr 'A-Z' 'a-z')" -v M="$(printf %s "$MACHINE" | tr 'A-Z' 'a-z')" '$1 == "lanes:" && (tolower($2) == m || tolower($2) == M) { print $3; exit }' tools/station/roles.txt 2>/dev/null)
  if [ -z "$n" ]; then
    c=$(nproc 2>/dev/null || echo "${NUMBER_OF_PROCESSORS:-2}"); n=$((c / 2))
    m=$(awk '/^MemTotal:/ { print int($2 / 1024 / 1536); exit }' /proc/meminfo 2>/dev/null); [ -n "$m" ] && [ "$m" -lt "$n" ] && n=$m
  fi
  q_int "$n" 1 1 32
}
lanes_busy() {  # how many lanes run a job now (files of live lanes; a dead lane's file is removed)
  local f n=0; for f in "$Q_LD"/[0-9]*; do
    case "$f" in *.cool|*.log) continue ;; esac; [ -f "$f" ] || continue
    if q_lane_live_f "$f"; then n=$((n + 1)); else rm -f "$f"; fi
  done; echo $n
}
q_snap_dir() { printf %s "$Q_GD/station_bin/$(git rev-parse --short=12 HEAD 2>/dev/null || echo none)"; }
# q_build_all: the one build of a commit for every lane, run by the station between merge jobs and lane starts. Builds realm and the
# store (the same command as the merge jobs and deep, so a build already done is a no-op), copies every realm-* program into
# $Q_GD/station_bin/<commit>/ and starts one (realm-store --help) to see that this PC lets it run. While it builds it holds
# $Q_GD/station_build.lock: no job that runs our programs starts then. Sets Q_SNAP (empty when there is nothing to run).
# A failed build is tried again after STATION_BUILD_RETRY_S (default 3600). Old copies go when no live lane uses them.
q_build_all() {
  local snap head st tmp f rc; Q_SNAP=""; snap=$(q_snap_dir); head=$(git rev-parse -q --verify HEAD 2>/dev/null)
  [ -f "$snap/.ok" ] && { Q_SNAP=$snap; return 0; }
  q_sac && return 1
  st=$(tail -1 "$Q_GD/station_build.state" 2>/dev/null)
  [[ "$st" == "FAIL $head "* ]] && [ $(( $(q_now) - $(cut -d' ' -f3 <<<"$st") )) -lt "${STATION_BUILD_RETRY_S:-3600}" ] && return 1
  q_cargo || { echo "FAIL $head $(q_now) cargo is not installed" >"$Q_GD/station_build.state"; return 1; }
  mkdir "$Q_GD/station_build.lock" 2>/dev/null || { [ -n "$(find "$Q_GD/station_build.lock" -maxdepth 0 -mmin +240 2>/dev/null)" ] && rm -rf "$Q_GD/station_build.lock"; return 1; }
  echo "queue: building ${head:0:7} once for the lanes"
  tmp="$snap.tmp"; rm -rf "$tmp"; mkdir -p "$tmp"
  if [ -n "${STATION_QUEUE_STUB:-}" ]; then sleep "${STATION_QUEUE_STUB_BUILD_SLEEP:-0}"; rc=0
  else
    { ( cd realm && timeout -k 30 3600 cargo build --release -j"${STATION_BUILD_JOBS:-2}" -q ) && ( cd realm/store && timeout -k 30 3600 cargo build --release -j"${STATION_BUILD_JOBS:-2}" -q ); } >"$Q_GD/station_build.log" 2>&1; rc=$?
    if [ $rc = 0 ]; then
      for f in realm/target/release/realm-* realm/store/target/release/realm-store realm/store/target/release/realm-store.exe; do
        case "$f" in *.d|*.pdb|*.rlib) continue ;; esac; [ -f "$f" ] && [ -x "$f" ] && cp -p "$f" "$tmp/"
      done
      timeout -k 5 30 "$tmp/realm-store" --help >/dev/null 2>&1; [ $? = 126 ] && { sleep 20; timeout -k 5 30 "$tmp/realm-store" --help >/dev/null 2>&1; [ $? = 126 ] && rc=126; }
    fi
  fi
  rmdir "$Q_GD/station_build.lock" 2>/dev/null
  if [ $rc = 126 ]; then rm -rf "$tmp"; echo "$head refused" >"$Q_GD/station_sac"; echo "REFUSED $head $(q_now) this PC refuses programs built here" >"$Q_GD/station_build.state"; echo "queue: this PC refuses programs built here (status 126): only jobs that run signed programs"; return 1; fi
  if [ $rc != 0 ]; then rm -rf "$tmp"; echo "FAIL $head $(q_now) build: $(tail -3 "$Q_GD/station_build.log" 2>/dev/null | tr -d '\r' | tr '\n' ' ' | cut -c1-300)" >"$Q_GD/station_build.state"; echo "queue: the build of ${head:0:7} failed; jobs that need it wait"; return 1; fi
  rm -rf "$snap"; mv "$tmp" "$snap"; touch "$snap/.ok"; Q_SNAP=$snap; echo "OK $head $(q_now)" >"$Q_GD/station_build.state"
  for f in "$Q_GD"/station_bin/*; do   # old commits' copies, unless a live lane still runs from one (Windows cannot delete a running program)
    [ "$f" = "$snap" ] && continue; grep -qs "snap=$f\( \|$\)" $(for l in "$Q_LD"/[0-9]*; do case "$l" in *.cool|*.log) ;; *) q_lane_live_f "$l" && echo "$l" ;; esac; done) /dev/null && continue
    rm -rf "$f" 2>/dev/null
  done
  return 0
}
lanes_fill() {  # claim and start a job in every free lane (one claim at a time, so two lanes never take one claim). Sets Q_STARTED.
  local L now cool id tries=0; Q_STARTED=0; Q_LANES_MODE=1; now=$(q_now); mkdir -p "$Q_LD"
  q_fetch || return 1
  for ((L = 1; L <= Q_NLANES; L++)); do
    [ -f "$Q_LD/$L" ] && q_lane_live_f "$Q_LD/$L" && continue
    cool=$(cat "$Q_LD/$L.cool" 2>/dev/null); [ "${cool:-0}" -gt "$now" ] && continue
    Q_LANE=$L; id=$(q_pick)
    [ -n "$id" ] || break
    if ! q_claim "$id"; then tries=$((tries + 1)); [ $tries -ge 5 ] && break; L=$((L - 1)); sleep 1; q_fetch || break; continue; fi
    lane_start "$L" "$id"; Q_STARTED=$((Q_STARTED + 1))
  done
  Q_LANE=0; return 0
}
lane_start() {  # lane id: run the claimed job in the background; its file says which job, since when and from which build
  local L=$1 id=$2 base; base=$(git rev-parse -q --verify HEAD 2>/dev/null)
  rm -f "$Q_LD/$L.cool"
  ( trap - EXIT; Q_LANE=$L Q_IN_LANE=1 Q_LANE_BASE=$base
    [ -n "${Q_SNAP:-}" ] && { Q_RBIN=$Q_SNAP; Q_SBIN=$Q_SNAP; }
    q_run_job "$id"
    [ "${Q_FAST_FAIL:-0}" = 1 ] && { echo "queue: lane $L: the job failed within a minute; the lane rests ${STATION_QUEUE_FAIL_SLEEP:-300} s"; echo $(( $(q_now) + ${STATION_QUEUE_FAIL_SLEEP:-300} )) >"$Q_LD/$L.cool"; }
    exit 0 ) &
  echo "pid=$! id=$id kind=$J_KIND start=$(q_now) mb=${J_MB:-0} timeout=$J_TIMEOUT snap=${Q_SNAP:-}" >"$Q_LD/$L"
}

# ---- idle accounting: hours busy and idle a day, appended to <machine>-hours.txt on the results branch ------------------
# busy = at least one lane (or a merge job, or deep) worked; lane_h = lane-hours of queue jobs (lanes x hours), lanes = lanes this station has.
H_STATE="$(git rev-parse --git-dir 2>/dev/null)/station_hours"; H_DAY=""; H_BUSY=0; H_IDLE=0; H_LANE=0; H_LAST=$SECONDS; H_FLUSHED=$SECONDS
hours_init() {
  H_LAST=$SECONDS; H_FLUSHED=$SECONDS
  local d="" b="" i="" l=""; [ -f "$H_STATE" ] && read -r d b i l <"$H_STATE"
  if [ "$d" = "$(date -u +%F)" ]; then H_DAY=$d H_BUSY=${b:-0} H_IDLE=${i:-0} H_LANE=${l:-0}; else H_DAY=$(date -u +%F); H_BUSY=0 H_IDLE=0 H_LANE=0; fi
}
hours_flush() {
  local f="$MACHINE-hours.txt" old tmp line; [ -n "$H_DAY" ] || return 0
  line=$(awk -v d="$H_DAY" -v b="$H_BUSY" -v i="$H_IDLE" -v l="$H_LANE" -v n="${Q_NLANES:-1}" 'BEGIN { printf "%s busy_h=%.2f idle_h=%.2f lane_h=%.2f lanes=%d", d, b / 3600, i / 3600, l / 3600, n }')
  gb_fetch "$BRANCH"; old=$(gb_cat "$BRANCH" "$f" | grep -v "^$H_DAY " | tail -400)
  tmp=$(mktemp); { [ -n "$old" ] && printf '%s\n' "$old"; printf '%s\n' "$line"; } >"$tmp"
  gb_put "$BRANCH" "$MACHINE: hours $line" "+$f:$tmp" || true; rm -f "$tmp"; H_FLUSHED=$SECONDS
}
hours_mark() {  # $1 = busy | idle: the time since the last mark was spent so; $2 = lanes that were busy (default 1 when busy)
  local d delta=$((SECONDS - H_LAST)) nl=${2:-}; H_LAST=$SECONDS; d=$(date -u +%F)
  if [ "$d" != "$H_DAY" ]; then [ -n "$H_DAY" ] && hours_flush; H_DAY=$d; H_BUSY=0; H_IDLE=0; H_LANE=0; fi
  case "$1" in busy) H_BUSY=$((H_BUSY + delta)); H_LANE=$((H_LANE + delta * ${nl:-1})) ;; *) H_IDLE=$((H_IDLE + delta)) ;; esac
  echo "$H_DAY $H_BUSY $H_IDLE $H_LANE" >"$H_STATE" 2>/dev/null
  [ $((SECONDS - H_FLUSHED)) -ge "${STATION_HOURS_FLUSH:-1800}" ] && hours_flush
  return 0
}

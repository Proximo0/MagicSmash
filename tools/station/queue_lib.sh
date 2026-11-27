#!/usr/bin/env bash
# The station work queue: functions sourced by station.sh (watch mode), queue.sh (the lead's tool) and queue_test.sh.
# Storage is two git branches, read and written without touching the work tree (same trick as station.sh `publish`):
#   station-queue    queue/<id>.job      one job, key=value lines: kind args needs priority repeat timeout_s added [every_s]
#                    claims/<id>.<m>     "machine= time=<epoch>": the push of this file is the lock
#                    done/<id>.<m>       "machine= time= status= passes= commit= fails=": the job finished on machine m
#                    stop/<id>           "claim=<id>.<m>-<lane> time=" lines (queue.sh stop): those runs stop within a minute, INFO
#   station-results  work/<id>/<m>.txt   one result line per pass (forever jobs append), work/<id>/art/<m>-<name> small artifacts
#                    <m>-hours.txt        one line a day: busy and idle hours
# Nothing from a job file is ever run as text: kind must be one of the functions qk_* below, and every argument is
# checked against a whitelist of characters (letters, digits, comma, dot, dash, underscore, equals, space) and then read
# by name (seeds=.. ops=..) with its own digit checks. `shell` runs only tools/station/jobs/<name>.sh.
# Needs from the caller (station.sh sets them): MACHINE, BRANCH (results). Optional functions of the caller are used when
# they exist: pending_merge (q_watch stops a job when a merge lands), job_frames, publish_append.
# Job fields beyond the five: needs_free_mb (RAM that must be free to start; default by kind, 0 = no check), needs_gpu_idle (1 = no art
# generation may be using the GPU; default 1 for frames and for needs=gpu). A merge never kills a queue job longer than
# STATION_QUEUE_KILL_MAX_S (default 900 s timeout_s), unless its kind repeats with fresh seeds (q_repeatable): the job finishes, then the
# station takes the new commit. A job silent for silent_s is stopped (q_watch); 3 FAILs in a row on one commit pause it (q_paused).
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
gb_sha_ok() { [[ "${1:-}" =~ ^[0-9a-f]{40,64}$ ]]; }   # a real object name, never empty (an empty one in a push deletes the branch)
gb_put() {
  local br=$1 msg=$2 parent idx blob tree commit op p f; shift 2
  if [ -n "${GB_BASE:-}" ]; then parent=$GB_BASE
  else gb_fetch "$br"; parent=$(git rev-parse -q --verify "refs/remotes/origin/$br" || true); fi
  idx=$(mktemp -u)
  # A failed read-tree would commit a tree without the branch's files; an empty $commit would make the push below
  # ":refs/heads/<branch>", which DELETES the branch (23 Nov: station-results was deleted that way once lanes pushed at once).
  if [ -n "$parent" ] && ! GIT_INDEX_FILE="$idx" git read-tree "$parent"; then rm -f "$idx"; return 1; fi
  for op in "$@"; do
    case "$op" in
      +*) p=${op#+}; f=${p#*:}; p=${p%%:*}; blob=$(git hash-object -w "$f")
          GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo 100644 "$blob" "$p" ;;
      -*) GIT_INDEX_FILE="$idx" git update-index --force-remove "${op#-}" 2>/dev/null ;;
    esac
  done
  tree=$(GIT_INDEX_FILE="$idx" git write-tree); rm -f "$idx"
  commit=$(git -c user.name="station $MACHINE" -c user.email="station@localhost" commit-tree "$tree" ${parent:+-p "$parent"} -m "$msg")
  gb_sha_ok "$tree" && gb_sha_ok "$commit" || return 1
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
  [[ "${J_SILENT:-0}" =~ $re ]] || { Q_WHY="bad silent_s"; return 1; }
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
  printf '%s %s\n' "$now" "$2" >"$Q_GD/station_lastskip" 2>/dev/null   # the heartbeat says why lanes stand idle
  return 0
}
q_idle_why() {  # for the heartbeat: free RAM and the newest SKIP reason of the last hour, one short field each
  local t w now; now=$(q_now); q_free_mb_set 2>/dev/null; printf ' free_mb=%s' "${Q_FREE_MB:-?}"
  read -r t w <"$Q_GD/station_lastskip" 2>/dev/null || return 0
  [ $((now - ${t:-0})) -lt 3600 ] && printf ' last_skip="%s"' "$(printf %s "$w" | tr -d '"\r' | cut -c1-120)"
  return 0
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
  local head c="" v=""; head=$(git rev-parse -q --verify HEAD 2>/dev/null)   # c and v stay set when the cache file is missing (set -u)
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
  J_SILENT=$(q_get "$txt" silent_s); J_MAXL=$(q_get "$txt" max_lanes); J_MAXM=$(q_get "$txt" max_per_machine); : "${J_MAXL:=1}"; : "${J_MAXM:=$J_MAXL}"
  : "${J_NEEDS:=any}" "${J_PRIO:=5}" "${J_REPEAT:=once}" "${J_TIMEOUT:=3600}" "${J_EVERY:=0}"
  : "${J_MB:=$(q_default_mb "$J_KIND")}"
  if [ -z "$J_GPUIDLE" ]; then if [ "$J_KIND" = frames ] || [ "$J_NEEDS" = gpu ]; then J_GPUIDLE=1; else J_GPUIDLE=0; fi; fi
  q_valid_job || { q_warn "$1" "refused: $Q_WHY"; return 1; }
  : "${J_SILENT:=$(q_default_silent "$J_KIND" "$J_ARGS")}"
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
  local recs="" r; for f in $dn; do r=$(gb_cat "$QBRANCH" "$f" | tr -d '\r' | head -1); recs+="$r"$'\n'; t=$(q_time_of <<<"$r"); [ "${t:-0}" -gt "$last" ] && last=$t; done
  q_paused "$recs" && { q_skip "$id" "$Q_WHY"; return 1; }
  if [ "$J_REPEAT" = once ]; then [ -n "$dn" ] && return 1; Q_KEY="0 $((9 - J_PRIO))"
  else [ $((now - last)) -ge "$J_EVERY" ] || return 1; Q_KEY="1 $((last - J_PRIO * 3600 + live * 7200))"; fi
  q_resources_ok || { q_skip "$id" "$Q_WHY"; return 1; }
  return 0
}
# q_paused DONE_RECORDS: the circuit breaker. Every done record says its commit and its FAILs in a row there (fails=). On this station's
# commit, the fails of FAIL records newer than the last non-FAIL record (any machine) add up; at 3 the job waits until main moves.
q_paused() {
  local head n; head=$(git rev-parse -q --short=12 HEAD 2>/dev/null) || return 1
  n=$(awk -v c="commit=$head" '
    { t = 0; st = ""; f = 0; hit = 0
      for (i = 1; i <= NF; i++) { if ($i == c) hit = 1; if ($i ~ /^time=/) t = substr($i, 6) + 0; if ($i ~ /^status=/) st = substr($i, 8); if ($i ~ /^fails=/) f = substr($i, 7) + 0 }
      if (!hit) next; if (st == "FAIL") { ft[NR] = t; fc[NR] = f } else if (t > ok) ok = t }
    END { for (k in ft) if (ft[k] > ok) s += fc[k]; print s + 0 }' <<<"$1")
  [ "$n" -ge "${STATION_QUEUE_PAUSE_FAILS:-3}" ] || return 1
  Q_WHY="paused: ${STATION_QUEUE_PAUSE_FAILS:-3} failures on $head"; return 0
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
  Q_CLAIM_T=$(q_now); tmp=$(mktemp); echo "machine=$MACHINE lane=${Q_LANE:-0} time=$Q_CLAIM_T" >"$tmp"   # q_stop_wanted knows this run by it
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
# ---- the watch over a running command (q_watch): silence, a merge, the GPU, the lead's stop ---------------------------------------
q_alive() { kill -0 "$1" 2>/dev/null && [ "$(awk '{print $3}' "/proc/$1/stat" 2>/dev/null)" != Z ]; }   # a zombie (init that never reaps) is dead
q_kill() {  # pid: the timeout path: taskkill /T takes the native tree on Windows, TERM (timeout passes it to its command's group), KILL after 10 s
  local p=$1 n=0
  if [ -r "/proc/$p/winpid" ] && command -v taskkill >/dev/null 2>&1; then taskkill //F //T //PID "$(cat "/proc/$p/winpid")" >/dev/null 2>&1; fi
  kill -TERM "$p" 2>/dev/null
  while q_alive "$p" && [ $n -lt 20 ]; do sleep 0.5; n=$((n + 1)); done
  q_alive "$p" && kill -KILL "$p" 2>/dev/null
  wait "$p" 2>/dev/null; return 0
}
# Silence: a job whose output has not grown for J_SILENT seconds (job field silent_s, 0 = off) is stopped and FAILs "silent for N s".
# Defaults by kind: 900 for kinds that print as they go (economy every day, bench every report, soak every --progress=300 s);
# balance 1800 (one line a round); fuzz 1800 (realm-store prints only at a seed's end); package and frames off
# (copies, exports and Godot are quiet); shell 900, but 3600 for a script that builds (names cargo: its build is quiet) and off for one
# that renders (names blender or godot). The station's own build (q_build_all) runs before the jobs and is never watched.
q_default_silent() {
  case "$1" in
    economy|bench|soak) echo 900 ;; balance|fuzz) echo 1800 ;; package|frames) echo 0 ;;
    shell) local f="tools/station/jobs/$(q_tok "$2" script x).sh"
      if grep -qiE 'blender|godot' "$f" 2>/dev/null; then echo 0; elif grep -q 'cargo' "$f" 2>/dev/null; then echo 3600; else echo 900; fi ;;
    *) echo 900 ;;
  esac
}
# Kinds a merge may stop at any length (Q_REPEATABLE): their passes are fresh seeds, so a stopped pass loses nothing worth keeping;
# it is recorded INFO "stopped for a merge after N s", writes no done record and runs again on the new commit.
q_repeatable() { case "$1" in fuzz|soak|bench|balance|economy) return 0 ;; shell) [ "$(q_tok "$2" script)" = wirefuzz ] ;; *) return 1 ;; esac; }
q_qfetch_soon() {  # fetch the queue branch when no lane of this station did in the last STATION_QUEUE_FETCH_S (55) s: one fetch a minute
  local st="$Q_GD/station_qfetch" now; now=$(q_now)
  [ $((now - $(cat "$st" 2>/dev/null || echo 0))) -ge "${STATION_QUEUE_FETCH_S:-55}" ] || return 0
  echo "$now" >"$st"; gb_fetch "$QBRANCH"
}
q_stop_wanted() {  # stop/<id> names this run's claim and its time (queue.sh stop): the lead wants it stopped. No clocks compared.
  [ -n "${Q_ID:-}" ] && [ -n "${Q_CLAIM_T:-}" ] || return 1
  q_qfetch_soon; gb_cat "$QBRANCH" "stop/$Q_ID" | tr -d '\r' | grep -qxF "claim=$Q_ID.$(q_cl) time=$Q_CLAIM_T"
}
q_stopped() {  # class line: the first stop of this job wins; q_run_job reads it ($Q_WD/stopped: class on line 1, the result line on 2)
  [ -e "$Q_WD/stopped" ] || printf '%s\n%s\n' "$1" "$2" >"$Q_WD/stopped"
}
# q_watch OUTFILE cmd...: runs it in the background, checks silence every second and the rest every STATION_DEEP_POLL (60) s.
# The command's status, or 99 when it was stopped (a merge, the GPU, silence, the lead); $Q_WD/stopped then says why when it counts.
q_watch() {
  local f=$1 pid last=$SECONDS grew=$SECONDS size=-1 sz merge=0; shift
  if declare -F pending_merge >/dev/null && { [ "${Q_KILLABLE:-0}" = 1 ] || [ "${Q_REPEATABLE:-0}" = 1 ]; }; then merge=1; fi
  "$@" >"$f" 2>&1 & pid=$!
  while q_alive "$pid"; do
    sleep 1
    sz=$(wc -c <"$f" 2>/dev/null); sz=${sz// /}; [ "${sz:-0}" != "$size" ] && { size=${sz:-0}; grew=$SECONDS; }
    if [ "${J_SILENT:-0}" -gt 0 ] && [ $((SECONDS - grew)) -ge "$J_SILENT" ]; then
      q_kill "$pid"; q_stopped silent "FAIL silent for $((SECONDS - grew)) s: $(q_tail "$f")"; return 99
    fi
    [ $((SECONDS - last)) -ge "${STATION_DEEP_POLL:-60}" ] || continue
    last=$SECONDS
    if [ "${J_GPUIDLE:-0}" = 1 ] && q_gpu_busy; then echo "station: art generation needs the GPU, stopping the queue job" >&2; q_kill "$pid"; return 99; fi
    if q_stop_wanted; then q_kill "$pid"; q_stopped lead "INFO stopped by the lead after $((SECONDS - ${Q_T0:-0})) s"; return 99; fi
    if [ $merge = 1 ] && pending_merge; then
      q_kill "$pid"; [ "${Q_REPEATABLE:-0}" = 1 ] && q_stopped merge "INFO stopped for a merge after $((SECONDS - ${Q_T0:-0})) s"; return 99
    fi
  done
  wait "$pid"
}
# q_run OUTFILE cmd...: q_watch, and a retry when Windows refuses to start a fresh program; 99 = stopped
q_run() {
  local f=$1; shift
  if [ -n "${STATION_QUEUE_STUB:-}" ] && [ "$QK" != shell ]; then  # shell jobs are light scripts of the repo: they run for real
    if [ -n "${STATION_QUEUE_STUB_SLEEP:-}" ]; then q_watch "$f" sleep "$STATION_QUEUE_STUB_SLEEP"; [ $? = 99 ] && return 99; fi   # watched like a real job
    case "$QK" in soak) echo "SOAK ok stub" ;; economy) echo "ECONOMY ok stub" ;; balance) echo "BALANCE careers=0 stub" ;; *) echo "$QK ok stub" ;; esac >"$f"
    case " $* " in *=666\ *|*=666) echo "stub failure" >>"$f"; return 1 ;; esac
    return 0
  fi
  # Windows can refuse to start a program it is still scanning right after a build ("Permission denied", status 126;
  # seen on the laptop after merges): wait and try again, up to 4 starts.
  local try rc
  for try in 1 2 3 4; do
    q_watch "$f" "$@"; rc=$?
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
  local args=$1 rep=$2 s seeds="" ops kills bad=0 n=0 detail="" rc lanes i batch pids
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
    pids=""
    for ((i = 0; i < lanes && $# > 0; i++)); do
      s=$1; shift; batch+=" $s"
      # -v: a line per killed child, so a 400,000-op seed (two hours on a busy PC) is not stopped by the silence check (MSI
      # 24 Nov: "silent for 1800 s" twice); the result line stays last.
      ( q_run "$Q_WD/fuzz.$s" timeout -k 30 "$(q_left)" "$Q_SBIN"/realm-store fuzz --seed=$s --ops=$ops --kills=$kills --dir="$Q_WD/fz$s" -v; echo $? >"$Q_WD/rc.$s" ) &
      pids+=" $!"
    done
    for i in $pids; do wait "$i"; done   # only our seeds: a bare wait in a lane also met the station's jobs ("not a child of this shell" on Windows)
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
  q_run "$Q_WD/soak.out" timeout -k 30 "$(q_left)" "$Q_RBIN"/realm-soak --bots="$bots" --secs="$secs" --seed="$seed" --fields=0,1,2,3,4,5 --monsters=3000 --progress=300 --fast --db="$Q_WD/soak.db"; rc=$?
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
  # The store lives on the repo's disk (the one the heartbeat's disk_free_gb measures), one file per lane, not in TMPDIR:
  # a 4000 x 180 store passes 1 GB, and where TMPDIR is a RAM-sized tmpfs (Ubuntu 25.10's /tmp) two lanes of it filled
  # it (24 Nov: "outing_failed: 19613", the store's commits failing "database or disk is full"). A killed run's file is
  # reused by the lane's next run, never piled up.
  local args=$1 rep=$2 s days bots rc line n=0 bad=0 csv="$Q_WD/art/economy.csv" first="" db="${Q_GD:-.}/station_eco-$(q_cl).db"
  q_cargo || { echo "FAIL cargo is not installed on this station"; return 0; }
  days=$(q_int "$(q_tok "$args" days)" 180 1 3650); bots=$(q_int "$(q_tok "$args" bots)" 4000 10 50000)
  q_build realm -p realm-gateway --bin realm-economy || { echo "FAIL build $(q_tail "$Q_WD/build.log")"; return 0; }
  echo "seed,bots,days,status,summary" >"$csv"
  for s in $(q_seeds "$(q_tok "$args" seeds)" "$rep"); do
    q_late && break
    q_run "$Q_WD/eco.out" timeout -k 30 "$(q_left)" "$Q_RBIN"/realm-economy --bots="$bots" --days="$days" --seed=$s --quiet --db="$db"; rc=$?
    rm -f "$db" "$db-wal" "$db-shm"
    [ $rc = 99 ] && return 3
    line=$(tail -1 "$Q_WD/eco.out" | tr -d ',' | cut -c1-240)
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
  local id=$1 me line rc status t0=$SECONDS tmp passes=1 prev pn n cl; me=$(q_me); cl=$(q_cl); Q_FAST_FAIL=0
  q_load "$id" || { gb_put_retry "$QBRANCH" "$MACHINE releases $id" "-claims/$id.$cl"; return 0; }
  QK=$J_KIND; Q_WD=$(mktemp -d "${TMPDIR:-/tmp}/station-job-$me-XXXXXX"); mkdir -p "$Q_WD/art"; QDEADLINE=$((SECONDS + J_TIMEOUT)); LAST=""
  mkdir -p "$Q_WD/tmp"
  echo "queue: $MACHINE runs $id kind=$J_KIND args='$J_ARGS' repeat=$J_REPEAT lane=${Q_LANE:-0}"
  # q_watch reads these: a merge may kill a short job or a repeatable one (fresh seeds); a long one finishes first (a merge used to throw
  # away up to hours of work). Q_ID and Q_CLAIM_T name this run for the lead's stop file.
  Q_IN_JOB=1; Q_KILLABLE=0; [ "$J_TIMEOUT" -le "${STATION_QUEUE_KILL_MAX_S:-900}" ] && Q_KILLABLE=1
  Q_REPEATABLE=0; q_repeatable "$J_KIND" "$J_ARGS" && Q_REPEATABLE=1
  Q_ID=$id; Q_T0=$t0; [ -n "${Q_CLAIM_T:-}" ] || Q_CLAIM_T=$(gb_cat "$QBRANCH" "claims/$id.$cl" | q_time_of)
  # Unfinished starts on this machine (lanes of one job add up): the third beyond its lanes is the last. Its own TMPDIR keeps a lane's
  # temporary files (databases, scratch dirs of the scripts) apart from every other lane's, and goes with the work dir.
  # A lane whose programs' folder is gone (cleaned away under it, or never finished) must not FAIL or count a start: it hands the job back.
  if [ "${Q_IN_LANE:-0}" = 1 ] && [ -n "${Q_SNAP:-}" ] && [ ! -f "$Q_SNAP/.ok" ] && q_ownbin; then
    Q_IN_JOB=0; Q_KILLABLE=0; Q_REPEATABLE=0; Q_ID=""; Q_CLAIM_T=""; rm -rf "$Q_WD"
    gb_put_retry "$QBRANCH" "$MACHINE releases $id" "-claims/$id.$cl"; echo "queue: job $id: the programs' folder $Q_SNAP is gone; claim released, it runs again"; return 3
  fi
  n=$(q_att_get "$id")
  if [ "$n" -ge $((2 + J_MAXM)) ]; then line="FAIL parked: started $n times on this machine without finishing"; rc=0; echo "queue: $id parked"; n=-1
  else q_att_add "$id" 1 >/dev/null; line=$(TMPDIR="$Q_WD/tmp" q_exec "$J_KIND" "$J_ARGS" "$J_REPEAT" 2>"$Q_WD/stderr.log"); rc=$?; fi
  Q_IN_JOB=0; Q_KILLABLE=0; Q_REPEATABLE=0; Q_ID=""; Q_CLAIM_T=""
  [ -s "$Q_WD/stderr.log" ] && tail -20 "$Q_WD/stderr.log" >&2
  if [ -s "$Q_WD/stopped" ]; then   # q_watch stopped it: silent (FAIL), the lead (INFO), a merge (INFO, no done record: it runs again)
    line=$(sed -n 2p "$Q_WD/stopped"); rc=0
    if [ "$(head -1 "$Q_WD/stopped")" = merge ]; then
      line="$(date -u +%Y-%m-%dT%H:%M:%SZ) INFO id=$id kind=$J_KIND secs=$((SECONDS - t0)) ${line#* }"
      q_publish_result "$id" "$line" "$Q_WD/art" || q_spool_add "$id" "$line"
      q_att_add "$id" -1 >/dev/null; rm -rf "$Q_WD"; gb_put_retry "$QBRANCH" "$MACHINE releases $id" "-claims/$id.$cl"; echo "queue: job $id ${line#* INFO id=$id kind=$J_KIND }; claim released, it runs again"; return 3
    fi
  fi
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
  prev=$(gb_cat "$QBRANCH" "done/$id.$me"); pn=$(sed -n 's/.*passes=\([0-9]*\).*/\1/p' <<<"$prev"); [ -n "$pn" ] && passes=$((pn + 1))
  # commit and fails (FAILs in a row here on this commit) feed the circuit breaker (q_paused)
  local commit fails=0; commit=$(git rev-parse -q --short=12 "${Q_LANE_BASE:-HEAD}" 2>/dev/null)
  if [ "$status" = FAIL ]; then
    fails=1; [[ "$prev" == *" status=FAIL "* && "$prev" == *" commit=$commit "* ]] && { pn=$(sed -n 's/.* fails=\([0-9]*\).*/\1/p' <<<"$prev" | head -1); fails=$((${pn:-0} + 1)); }
  fi
  echo "machine=$MACHINE time=$(q_now) status=$status passes=$passes commit=${commit:-none} fails=$fails" >"$tmp"
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
q_snap_dir() { printf %s "$(cd "$Q_GD" 2>/dev/null && pwd || echo "$Q_GD")/station_bin/$(git rev-parse --short=12 HEAD 2>/dev/null || echo none)"; }   # absolute: shell jobs cd into realm/ before running from it
# q_any_ownbin: 0 when some queued job runs a program built here (q_load ok and q_ownbin). Reads the queue as lanes_fill last fetched it
# (no fetch of its own: a job added since then gets its build one loop later). A subshell, so q_load's J_* stay out of the caller.
# With no queue branch or no such job: 1.
q_any_ownbin() (
  tree=$(git ls-tree -r --name-only "refs/remotes/origin/$QBRANCH" 2>/dev/null) || exit 1
  for f in $(grep '^queue/.*\.job$' <<<"$tree"); do
    id=${f#queue/}; id=${id%.job}
    q_load "$id" && q_ownbin && exit 0
  done
  exit 1
)
# q_build_all: the one build of a commit for every lane, run by the station between merge jobs and lane starts. Builds realm and the
# store (the same command as the merge jobs and deep, so a build already done is a no-op), copies every realm-* program into
# $Q_GD/station_bin/<commit>/ and starts one (realm-store --help) to see that this PC lets it run. While it builds it holds
# $Q_GD/station_build.lock: no job that runs our programs starts then. Sets Q_SNAP (empty when there is nothing to run).
# A failed build is tried again after STATION_BUILD_RETRY_S (default 3600). Old copies go when no live lane uses them and they are 6 h old.
q_build_all() {
  local snap head st tmp f rc; Q_SNAP=""; snap=$(q_snap_dir); head=$(git rev-parse -q --verify HEAD 2>/dev/null)
  [ -f "$snap/.ok" ] && { Q_SNAP=$snap; return 0; }
  q_any_ownbin || return 1   # nothing queued runs a program built here (e.g. only Four of Wands jobs): build nothing, quietly
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
  for f in "$(dirname "$snap")"/*; do   # old commits' copies, unless a live lane still runs from one (Windows cannot delete a running program)
    [ "$f" = "$snap" ] && continue; [ -n "$(find "$f" -maxdepth 0 -mmin -360 2>/dev/null)" ] && continue   # young: another station on this checkout may use it
    grep -qs "snap=$f\( \|$\)" $(for l in "$Q_LD"/[0-9]*; do case "$l" in *.cool|*.log) ;; *) q_lane_live_f "$l" && echo "$l" ;; esac; done) /dev/null && continue
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

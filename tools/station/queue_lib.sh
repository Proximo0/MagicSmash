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
: "${MACHINE:=${STATION_NAME:-$(hostname)}}"
: "${BRANCH:=station-results}"
QBRANCH="${STATION_QUEUE_BRANCH:-station-queue}"
Q_CAP="${STATION_QUEUE_ARTIFACT_CAP:-2097152}"   # bytes of artifacts a job may publish
Q_KINDS="fuzz soak bench balance economy frames package shell"
Q_WARNED_FILE="${TMPDIR:-/tmp}/station-queue-warned-${MACHINE//[^A-Za-z0-9_-]/_}"

q_now() { date +%s; }
q_me() { printf %s "${MACHINE//[^A-Za-z0-9_-]/_}"; }
q_rand() { echo $(( ((RANDOM << 15) | RANDOM) % 1000000 + 1 )); }

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
gb_put_retry() {  # same, a few tries; for writes that only we make (results, done, release)
  local n; for n in 1 2 3 4; do gb_put "$@" && return 0; sleep "${STATION_QUEUE_RETRY_SLEEP:-3}"; done; return 1
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
    Q_FREE_MB=$(powershell.exe -NoProfile -Command '[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+$' | head -1) ;;
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
q_resources_ok() {  # uses J_MB and J_GPUIDLE; 1 with Q_WHY when short
  if [ "${J_MB:-0}" -gt 0 ]; then
    q_free_mb_set
    if [ -n "$Q_FREE_MB" ] && [ "$Q_FREE_MB" -lt "$J_MB" ]; then Q_WHY="needs ${J_MB} MB free RAM, only ${Q_FREE_MB} MB free"; return 1; fi
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
  J_MB=$(q_get "$txt" needs_free_mb); J_GPUIDLE=$(q_get "$txt" needs_gpu_idle)
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
  return 0
}
# q_eligible id: after q_load. Sets Q_KEY for ordering: finite (once) jobs first by priority, then the forever jobs, oldest
# run first with priority worth an hour of age, so a forever job of high priority cannot starve the others.
q_eligible() {
  local id=$1 now f t newest=0 last=0 cl dn me; now=$(q_now); me=$(q_me)
  q_needs_ok || return 1
  cl=$(grep "^claims/$id\." <<<"$Q_TREE"); dn=$(grep "^done/$id\." <<<"$Q_TREE")
  # A claim of this machine never blocks it: one station runs one job at a time, so our own claim is left from a crash or a reboot.
  cl=$(grep -v "^claims/$id\.$me\$" <<<"$cl")
  for f in $cl; do t=$(gb_cat "$QBRANCH" "$f" | q_time_of); [ "${t:-0}" -gt "$newest" ] && newest=$t; done
  [ -n "$cl" ] && [ "$now" -lt $((newest + 2 * J_TIMEOUT)) ] && return 1       # claimed and not stale
  for f in $dn; do t=$(gb_cat "$QBRANCH" "$f" | q_time_of); [ "${t:-0}" -gt "$last" ] && last=$t; done
  if [ "$J_REPEAT" = once ]; then [ -n "$dn" ] && return 1; Q_KEY="0 $((9 - J_PRIO))"
  else [ $((now - last)) -ge "$J_EVERY" ] || return 1; Q_KEY="1 $((last - J_PRIO * 3600))"; fi
  q_resources_ok || { q_skip "$id" "$Q_WHY"; return 1; }
  return 0
}
q_pick() {  # the best eligible job id, or nothing
  local f id
  for f in $(grep '^queue/.*\.job$' <<<"$Q_TREE"); do
    id=${f#queue/}; id=${id%.job}
    if q_load "$id" && q_eligible "$id"; then echo "$Q_KEY $id"; fi
  done | sort -k1,1n -k2,2n -k3,3 | head -1 | cut -d' ' -f3
}
q_claim() {  # $1 = id; the push is the lock. 0 won, 1 lost or no longer free
  local id=$1 tmp me f ops=() base; me=$(q_me)
  q_fetch || return 1
  base=$(git rev-parse -q --verify "refs/remotes/origin/$QBRANCH") || return 1   # the view we check below is the one we push on
  q_load "$id" && q_eligible "$id" || return 1
  tmp=$(mktemp); echo "machine=$MACHINE time=$(q_now)" >"$tmp"
  for f in $(grep "^claims/$id\." <<<"$Q_TREE"); do ops+=("-$f"); done     # a stale claim is taken over: its file goes
  ops+=("+claims/$id.$me:$tmp")
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
q_cargo() {  # make cargo findable; 1 when it is not installed (stubbed runs do not need it)
  [ -n "${STATION_QUEUE_STUB:-}" ] && return 0
  command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  command -v cargo >/dev/null 2>&1
}
q_build() {  # build dir, cargo args...; output to $Q_WD/build.log
  [ -n "${STATION_QUEUE_STUB:-}" ] && return 0
  local d=$1; shift; ( cd "$d" && cargo build --release -j2 -q "$@" ) >>"$Q_WD/build.log" 2>&1
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
  if declare -F step_run >/dev/null; then step_run "$f" "$@"; return $?; fi
  "$@" >"$f" 2>&1
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

q_lanes() {  # how many seeds a job runs side by side: lanes=N in the args, else STATION_LANES, else cores-1 capped by memory
  local n c m; n=$(q_tok "$1" lanes); [ -n "$n" ] || n=${STATION_LANES:-}
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
      ( q_run "$Q_WD/fuzz.$s" timeout "$(q_left)" realm/store/target/release/realm-store fuzz --seed=$s --ops=$ops --kills=$kills --dir="$Q_WD/fz$s"; echo $? >"$Q_WD/rc.$s" ) &
    done
    wait
    for s in $batch; do
      rc=$(cat "$Q_WD/rc.$s" 2>/dev/null || echo 1)
      [ "$rc" = 99 ] && return 3
      n=$((n + 1)); rm -rf "$Q_WD/fz$s"
      if [ "$rc" = 0 ]; then LAST="$(tail -1 "$Q_WD/fuzz.$s" | cut -c1-100)"; else bad=$((bad + 1)); detail+=" seed=$s FAILED: $(q_tail "$Q_WD/fuzz.$s");"; fi
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
  q_run "$Q_WD/soak.out" timeout "$(q_left)" realm/target/release/realm-soak --bots="$bots" --secs="$secs" --seed="$seed" --fields=0,1,2,3,4,5 --monsters=3000 --progress=0 --fast --db="$Q_WD/soak.db"; rc=$?
  [ $rc = 99 ] && return 3
  out=$(tail -1 "$Q_WD/soak.out")
  if [[ "$out" == "SOAK ok "* ]]; then echo "PASS soak seed=$seed secs=$secs ${out:0:200}"; else echo "FAIL soak seed=$seed secs=$secs $(q_tail "$Q_WD/soak.out")"; fi
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
    q_run "$Q_WD/bench.out" timeout "$(q_left)" realm/target/release/realm-server --bench --field=$f --seed=$seed --bots=$bots --monsters=$m --rally=0.3 --threads=$t --ticks=$ticks --warmup=100 --report=300; rc=$?
    [ $rc = 99 ] && return 3
    n=$((n + 1)); LAST=$(tail -1 "$Q_WD/bench.out" | tr -d ',' | cut -c1-140)
    if [ $rc = 0 ]; then echo "$f,$t,$m,$seed,ok,$LAST" >>"$csv"; else bad=$((bad + 1)); detail+=" field=$f threads=$t monsters=$m FAILED: $(q_tail "$Q_WD/bench.out");"; echo "$f,$t,$m,$seed,FAIL,$LAST" >>"$csv"; fi
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
  BOT_THREADS="${STATION_BALANCE_THREADS:-2}" q_run "$Q_WD/balance.out" timeout "$(q_left)" realm/target/release/realm-loadtest balance career "$n" "$per" "$mins" "$fast" "$hours"; rc=$?
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
    q_run "$Q_WD/eco.out" timeout "$(q_left)" realm/target/release/realm-economy --bots="$bots" --days="$days" --seed=$s --quiet --db="$Q_WD/eco.db"; rc=$?
    [ $rc = 99 ] && return 3
    rm -f "$Q_WD"/eco.db*; line=$(tail -1 "$Q_WD/eco.out" | tr -d ',' | cut -c1-240)
    n=$((n + 1)); first=${first:-$s}
    if [[ "$line" == "ECONOMY ok "* ]]; then echo "$s,$bots,$days,ok,${line:8}" >>"$csv"; LAST="seed=$s ${line:8:200}"
    else bad=$((bad + 1)); echo "$s,$bots,$days,fail,$line" >>"$csv"; LAST="seed=$s no ECONOMY ok line: $(q_tail "$Q_WD/eco.out")"; fi
  done
  echo "$([ $bad = 0 ] && echo INFO || echo FAIL) economy runs=$n bad=$bad $LAST"
}
qk_frames() {  # args: zooms=16,4 secs=60. The client frame test of job_frames; needs a screen or xvfb
  local args=$1 zooms secs line
  zooms=$(q_list "$(q_tok "$args" zooms)" 16); zooms=${zooms// /,}; secs=$(q_int "$(q_tok "$args" secs)" 60 5 600)
  if [ -n "${STATION_QUEUE_STUB:-}" ]; then echo "INFO frames zooms=$zooms stub"; return 0; fi
  declare -F job_frames >/dev/null || { echo "FAIL frames: not available outside station.sh"; return 0; }
  line=$(STATION_FRAMES_ZOOM="$zooms" STATION_FRAMES_SECS="$secs" STATION_SHOTS=0 job_frames 2>&1 | tail -1)
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
  for b in realm-gateway realm-server realm-ops; do cp "realm/target/release/$b$ext" "$bins/" 2>/dev/null || { echo "FAIL package: realm/target/release/$b$ext missing"; return 0; }; done
  cp "realm/store/target/release/realm-store$ext" "$bins/" 2>/dev/null
  rm -rf "$out"; mkdir -p "$out"
  q_run "$Q_WD/pkg.out" timeout "$(q_left)" realm/target/release/realm-ops$ext package --bins="$bins" --out="$out/server" --version="$ver" --host=realm/ops/host
  [ $? = 0 ] || { echo "FAIL package: realm-ops package: $(q_tail "$Q_WD/pkg.out")"; return 0; }
  if command -v "${GODOT:-godot}" >/dev/null 2>&1 && [ -f realm/client/export_presets.cfg ] && [ "$target" = windows ]; then
    mkdir -p "$out/client"
    if "${GODOT:-godot}" --headless --path realm/client --export-release "Windows Desktop" "$out/client/HordeAndHearth.exe" >"$Q_WD/export.out" 2>&1 && [ -s "$out/client/HordeAndHearth.exe" ]; then cl="client exported"; else cl="client export failed"; fi
  fi
  hash=$( (cd "$out" && find . -type f | sort | xargs sha256sum 2>/dev/null) | sha256sum | cut -c1-16)
  echo "$hash  $ver $target" >"$out/HASH.txt"
  keep=$(ls -d "$root"/*-"$target"-* 2>/dev/null | sort | head -n -"${STATION_PACKAGE_KEEP:-5}"); [ -n "$keep" ] && rm -rf $keep
  echo "INFO package target=$target version=$ver hash=$hash dir=$out $cl"
}
qk_shell() {  # args: script=NAME plus words for it. tools/station/jobs/NAME.sh; its last stdout line is the summary
  local args=$1 name rest="" t rc line
  name=$(q_tok "$args" script ""); for t in $args; do case "$t" in script=*) ;; *) rest+=" $t" ;; esac; done
  STATION_JOB_ART="$Q_WD/art" STATION_JOB_SEED="$(q_rand)" q_run "$Q_WD/shell.out" timeout "$(q_left)" bash "tools/station/jobs/$name.sh" $rest; rc=$?
  [ $rc = 99 ] && return 3
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
  for n in 1 2 3 4; do
    gb_fetch "$BRANCH"; old=$(gb_cat "$BRANCH" "work/$id/$MACHINE.txt" | tail -300)
    { [ -n "$old" ] && printf '%s\n' "$old"; printf '%s\n' "$line"; } >"$tmp"
    ops=("+work/$id/$MACHINE.txt:$tmp"); total=0; skipped=""
    for f in $(ls -S -r "$art" 2>/dev/null); do   # smallest first, so one big file cannot crowd out the rest
      sz=$(wc -c <"$art/$f"); sz=${sz// /}
      if [ $((total + sz)) -le "$Q_CAP" ] && [ "$sz" -gt 0 ]; then total=$((total + sz)); ops+=("+work/$id/art/$(q_me)-$f:$art/$f"); else skipped+=" $f"; fi
    done
    if gb_put "$BRANCH" "$MACHINE: job $id ${line%% *}" "${ops[@]}"; then rm -f "$tmp"; [ -n "$skipped" ] && echo "queue: artifacts over the ${Q_CAP}-byte cap not published:$skipped"; return 0; fi
    sleep "${STATION_QUEUE_RETRY_SLEEP:-3}"
  done
  rm -f "$tmp"; return 1
}
q_run_job() {  # $1 = id, claimed by us. 0 done, 3 interrupted (claim released)
  local id=$1 me line rc status t0=$SECONDS tmp passes=1 prev; me=$(q_me)
  q_load "$id" || { gb_put_retry "$QBRANCH" "$MACHINE releases $id" "-claims/$id.$me"; return 0; }
  QK=$J_KIND; Q_WD=$(mktemp -d); mkdir -p "$Q_WD/art"; QDEADLINE=$((SECONDS + J_TIMEOUT)); LAST=""
  echo "queue: $MACHINE runs $id kind=$J_KIND args='$J_ARGS' repeat=$J_REPEAT"
  # step_run reads these: a merge may kill only a short job; a long one finishes first (a merge used to throw away up to hours of work)
  Q_IN_JOB=1; Q_KILLABLE=0; [ "$J_TIMEOUT" -le "${STATION_QUEUE_KILL_MAX_S:-900}" ] && Q_KILLABLE=1
  line=$(q_exec "$J_KIND" "$J_ARGS" "$J_REPEAT" 2>"$Q_WD/stderr.log"); rc=$?
  Q_IN_JOB=0; Q_KILLABLE=0
  [ -s "$Q_WD/stderr.log" ] && tail -20 "$Q_WD/stderr.log" >&2
  if [ $rc = 3 ]; then
    rm -rf "$Q_WD"; gb_put_retry "$QBRANCH" "$MACHINE releases $id" "-claims/$id.$me"; echo "queue: job $id interrupted (a merge landed or the GPU was needed); claim released"; return 3
  fi
  if [ -z "$line" ]; then  # silent death: say how it ended and what it last wrote
    local last; last=$(ls -t "$Q_WD" 2>/dev/null | grep -v '^stderr.log$' | head -1)
    line="FAIL job printed nothing (exit $rc; stderr: $(tail -5 "$Q_WD/stderr.log" 2>/dev/null | tr -d '\r' | tr '\n' ' ' | cut -c1-600); last output${last:+ $last}: $([ -f "$Q_WD/$last" ] && tail -3 "$Q_WD/$last" | tr -d '\r' | tr '\n' ' ' | cut -c1-600))"
  fi
  status=${line%% *}; case "$status" in PASS|FAIL|INFO|SKIP) ;; *) status=FAIL; line="FAIL $line" ;; esac
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ) $status id=$id kind=$J_KIND secs=$((SECONDS - t0)) ${line#* }"
  q_publish_result "$id" "$line" "$Q_WD/art" || echo "queue: could not publish the result of $id"
  tmp=$(mktemp)
  prev=$(gb_cat "$QBRANCH" "done/$id.$me" | sed -n 's/.*passes=\([0-9]*\).*/\1/p'); [ -n "$prev" ] && passes=$((prev + 1))
  echo "machine=$MACHINE time=$(q_now) status=$status passes=$passes" >"$tmp"
  gb_put_retry "$QBRANCH" "$MACHINE done $id $status" "+done/$id.$me:$tmp" "-claims/$id.$me" || echo "queue: could not record done for $id (the claim will go stale)"
  rm -f "$tmp"; rm -rf "$Q_WD"
  echo "queue: $id $status ${line:0:200}"
  if [ "$status" = FAIL ] && declare -F publish_append >/dev/null; then publish_append "$(date -u +%Y-%m-%dT%H:%MZ) $MACHINE queue ${line:0:1500}" "$MACHINE-failures.txt" || true; fi
  return 0
}
queue_step() {  # one job from the queue. 0 ran one, 1 nothing to do (the caller falls back to deep), 3 interrupted by a merge
  local id tries=0
  while [ $tries -lt 5 ]; do
    q_fetch || return 1
    id=$(q_pick); [ -n "$id" ] || return 1
    if q_claim "$id"; then q_run_job "$id"; return $?; fi
    tries=$((tries + 1)); sleep 1
  done
  return 1
}

# ---- idle accounting: hours busy and idle a day, appended to <machine>-hours.txt on the results branch ------------------
H_STATE="$(git rev-parse --git-dir 2>/dev/null)/station_hours"; H_DAY=""; H_BUSY=0; H_IDLE=0; H_LAST=$SECONDS; H_FLUSHED=$SECONDS
hours_init() {
  H_LAST=$SECONDS; H_FLUSHED=$SECONDS
  local d="" b="" i=""; [ -f "$H_STATE" ] && read -r d b i <"$H_STATE"
  if [ "$d" = "$(date -u +%F)" ]; then H_DAY=$d H_BUSY=${b:-0} H_IDLE=${i:-0}; else H_DAY=$(date -u +%F); H_BUSY=0 H_IDLE=0; fi
}
hours_flush() {
  local f="$MACHINE-hours.txt" old tmp line; [ -n "$H_DAY" ] || return 0
  line=$(awk -v d="$H_DAY" -v b="$H_BUSY" -v i="$H_IDLE" 'BEGIN { printf "%s busy_h=%.2f idle_h=%.2f", d, b / 3600, i / 3600 }')
  gb_fetch "$BRANCH"; old=$(gb_cat "$BRANCH" "$f" | grep -v "^$H_DAY " | tail -400)
  tmp=$(mktemp); { [ -n "$old" ] && printf '%s\n' "$old"; printf '%s\n' "$line"; } >"$tmp"
  gb_put "$BRANCH" "$MACHINE: hours $line" "+$f:$tmp" || true; rm -f "$tmp"; H_FLUSHED=$SECONDS
}
hours_mark() {  # $1 = busy | idle: the time since the last mark was spent so
  local d delta=$((SECONDS - H_LAST)); H_LAST=$SECONDS; d=$(date -u +%F)
  if [ "$d" != "$H_DAY" ]; then [ -n "$H_DAY" ] && hours_flush; H_DAY=$d; H_BUSY=0; H_IDLE=0; fi
  case "$1" in busy) H_BUSY=$((H_BUSY + delta)) ;; *) H_IDLE=$((H_IDLE + delta)) ;; esac
  echo "$H_DAY $H_BUSY $H_IDLE" >"$H_STATE" 2>/dev/null
  [ $((SECONDS - H_FLUSHED)) -ge "${STATION_HOURS_FLUSH:-1800}" ] && hours_flush
  return 0
}

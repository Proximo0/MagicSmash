#!/usr/bin/env bash
# The lead's tool for the station work queue (see tools/station/README.md). Run it from any clone of the repository.
#   queue.sh add kind=fuzz args="seeds=1-50 ops=50000" [needs=any|gpu|linux|windows|<machine>] [priority=0-9] [repeat=once|forever]
#                [timeout_s=3600] [every_s=0] [needs_free_mb=MB] [needs_gpu_idle=0|1] [max_lanes=1] [max_per_machine=N] [own_bin=0|1]
#                max_lanes: how many station lanes may run a forever job at once (all machines); max_per_machine: on one machine
#   queue.sh list                 pending jobs, who holds a claim and for how long, done counts
#   queue.sh cancel <id>
#   queue.sh fill-week            load the default forever work for every machine's lanes (safe to run again: jobs already queued are
#                                 not repeated, their priority and lane limits are brought up to date). fill-month: the same (forever
#                                 jobs run until cancelled, so one fill covers to 2026-12-31 and beyond)
#   queue.sh digest [--since=DAYS]   what the PCs did while nobody watched; read this first
#   queue.sh step                 run one queue job on THIS machine now (what a watching station does between merges)
# Kinds: fuzz soak bench balance economy frames package shell. Args are words name=value (letters, digits , . - _ only).
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/station/queue_lib.sh

cmd=${1:-}; shift || true

q_job_text() {  # words 8 to 12 (needs_free_mb, needs_gpu_idle, max_lanes, max_per_machine, own_bin) are written only when given
  printf 'kind=%s\nargs=%s\nneeds=%s\npriority=%s\nrepeat=%s\ntimeout_s=%s\nevery_s=%s\nadded=%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${Q_ADDED:-$(date -u +%FT%TZ)}"
  [ -z "${8:-}" ] || printf 'needs_free_mb=%s\n' "$8"; [ -z "${9:-}" ] || printf 'needs_gpu_idle=%s\n' "$9"
  [ -z "${10:-}" ] || printf 'max_lanes=%s\n' "${10}"; [ -z "${11:-}" ] || printf 'max_per_machine=%s\n' "${11}"; [ -z "${12:-}" ] || printf 'own_bin=%s\n' "${12}"
}
q_add() {  # kind args needs priority repeat timeout every [mb gpuidle max_lanes max_per_machine own_bin] -> prints the id (Q_ID= rewrites that job)
  J_KIND=$1 J_ARGS=$2 J_NEEDS=$3 J_PRIO=$4 J_REPEAT=$5 J_TIMEOUT=$6 J_EVERY=$7 J_MB=${8:-} J_GPUIDLE=${9:-} J_MAXL=${10:-1} J_MAXM=${11:-1}
  q_valid_job || { echo "queue: refused: $Q_WHY" >&2; return 1; }
  case "${12:-}" in ""|0|1) ;; *) echo "queue: refused: own_bin must be 0 or 1" >&2; return 1 ;; esac
  local id tmp; id=${Q_ID:-"$(date -u +%y%m%d%H%M%S)-$(printf %04d $((RANDOM % 10000)))"}
  tmp=$(mktemp); q_job_text "$@" >"$tmp"
  gb_put_retry "$QBRANCH" "queue: add $id $1" "+queue/$id.job:$tmp" || { rm -f "$tmp"; echo "queue: could not push" >&2; return 1; }
  rm -f "$tmp"; echo "$id"
}
q_age() { local s=$1; if [ "$s" -ge 3600 ]; then echo "$((s / 3600))h$(((s % 3600) / 60))m"; else echo "$((s / 60))m"; fi; }
q_machines() { grep -v '^#' tools/station/roles.txt | grep -iw queue | cut -d: -f1; }

case "$cmd" in
  add)
    kind="" args="" needs=any prio=5 rep=once to=3600 every=0 mb="" gpuidle="" maxl="" maxm="" ownbin=""
    for a in "$@"; do
      case "$a" in kind=*) kind=${a#kind=} ;; args=*) args=${a#args=} ;; needs=*) needs=${a#needs=} ;; priority=*) prio=${a#priority=} ;;
        repeat=*) rep=${a#repeat=} ;; timeout_s=*) to=${a#timeout_s=} ;; every_s=*) every=${a#every_s=} ;;
        needs_free_mb=*) mb=${a#needs_free_mb=} ;; needs_gpu_idle=*) gpuidle=${a#needs_gpu_idle=} ;;
        max_lanes=*) maxl=${a#max_lanes=} ;; max_per_machine=*) maxm=${a#max_per_machine=} ;; own_bin=*) ownbin=${a#own_bin=} ;;
        *) echo "queue: unknown word '${a:0:30}'" >&2; exit 2 ;; esac
    done
    q_add "$kind" "$args" "$needs" "$prio" "$rep" "$to" "$every" "$mb" "$gpuidle" "$maxl" "$maxm" "$ownbin" || exit 1 ;;
  list)
    q_fetch || { echo "queue: no branch $QBRANCH yet (use add or fill-week)"; exit 0; }
    now=$(q_now); n=0
    printf '%-18s %-8s %-8s %-3s %-7s %-12s %s\n' ID KIND NEEDS PRI REPEAT STATE ARGS
    for f in $(grep '^queue/.*\.job$' <<<"$Q_TREE"); do
      id=${f#queue/}; id=${id%.job}; txt=$(gb_cat "$QBRANCH" "$f" | tr -d '\r'); n=$((n + 1))
      J_TIMEOUT=$(q_get "$txt" timeout_s); : "${J_TIMEOUT:=3600}"; state=pending; by=""; nc=0
      for c in $(grep "^claims/$id\." <<<"$Q_TREE"); do
        t=$(gb_cat "$QBRANCH" "$c" | q_time_of); by+="${by:+, }${c#claims/$id.} $(q_age $((now - ${t:-now})))"
        if [ "$now" -lt $((${t:-0} + 2 * J_TIMEOUT)) ]; then nc=$((nc + 1)); state="claimed$([ $nc -gt 1 ] && echo "x$nc")"; elif [ $nc = 0 ]; then state="STALE-claim"; fi
      done
      d=$(grep -c "^done/$id\." <<<"$Q_TREE"); passes=0
      for c in $(grep "^done/$id\." <<<"$Q_TREE"); do p=$(gb_cat "$QBRANCH" "$c" | sed -n 's/.*passes=\([0-9]*\).*/\1/p'); passes=$((passes + ${p:-1})); done
      [ "$(q_get "$txt" repeat)" = once ] && [ "$d" -gt 0 ] && state=done
      printf '%-18s %-8s %-8s %-3s %-7s %-12s %s%s%s\n' "$id" "$(q_get "$txt" kind)" "$(q_get "$txt" needs)" "$(q_get "$txt" priority)" "$(q_get "$txt" repeat)" "$state" \
        "$(q_get "$txt" args)" "${by:+  [by $by]}" "  [passes $passes on $d machines]"
    done
    echo "QUEUE jobs=$n" ;;
  cancel)
    [ -n "${1:-}" ] || { echo "usage: queue.sh cancel <id>" >&2; exit 2; }
    q_fetch || { echo "queue: no queue branch"; exit 1; }
    grep -qx "queue/$1.job" <<<"$Q_TREE" || { echo "queue: no job $1"; exit 1; }
    gb_put_retry "$QBRANCH" "queue: cancel $1" "-queue/$1.job" && echo "cancelled $1" ;;
  fill-week|fill-month)
    # Priority (Curtis via the lead, 23 Nov 2026), high to low: 9 once-off lead jobs; 8 packages and frames; 7 balance and economy;
    # 6 worldlong and soak; 5 bench; 4 fuzz and wirefuzz; 3 lan play (queued by the lead). Render jobs come at 7 with max_per_machine=1.
    # Per machine the seeded forever jobs together offer more lanes than the biggest station has (msi 10): fuzz 4, soak 3, economy 2,
    # bench 1 (a timing measure: one at a time), worldlong 1, wirefuzz 1 (its own target dir). Each pass draws a fresh seed.
    q_fetch || true; have=""
    for f in $(grep '^queue/.*\.job$' <<<"${Q_TREE:-}"); do t=$(gb_cat "$QBRANCH" "$f" | tr -d '\r'); id=${f#queue/}; id=${id%.job}
      have+="$(q_get "$t" kind)|$(q_get "$t" args)|$(q_get "$t" needs)|$id|$(q_get "$t" priority) $(q_get "$t" repeat) $(q_get "$t" timeout_s) $(q_get "$t" every_s) $(q_get "$t" needs_free_mb) $(q_get "$t" max_lanes) $(q_get "$t" max_per_machine)|$(q_get "$t" added)"$'\n'; done
    added=0 updated=0
    fw() {  # kind args needs priority repeat timeout every [needs_free_mb max_lanes max_per_machine]: add, or bring an existing job up to date
      local row want id
      row=$(grep -F "$1|$2|$3|" <<<"$have" | head -1)
      want="$4 $5 $6 $7 ${8:-} ${9:-} ${10:-}"
      if [ -n "$row" ]; then
        id=$(cut -d'|' -f4 <<<"$row")
        [ "$(cut -d'|' -f5 <<<"$row")" = "$want" ] && return 0
        Q_ID=$id Q_ADDED=$(cut -d'|' -f6 <<<"$row") q_add "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${8:-}" "" "${9:-}" "${10:-}" >/dev/null && { echo "updated $id $1 $3 $2 (priority=$4 max_lanes=${9:-1})"; updated=$((updated + 1)); }
        return 0
      fi
      id=$(q_add "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${8:-}" "" "${9:-}" "${10:-}") && { echo "added $id $1 $3 $2"; have+="$1|$2|$3|$id|$want|"$'\n'; added=$((added + 1)); }
    }
    i=0; machines=$(q_machines); [ -n "$machines" ] || machines=$(hostname)
    for m in $machines; do
      lo=$((i * 100000 + 1)); hi=$(((i + 1) * 100000)); r="seeds=$lo-$hi"
      fw economy "bots=4000 days=180 $r" "$m" 7 forever 14400 0 "" 2 2
      fw soak "secs=1800 bots=40 $r" "$m" 6 forever 5400 0 "" 3 3
      fw shell "script=worldlong secs=7200" "$m" 6 forever 10800 0 1024 1 1
      fw bench "fields=0,1,2,3,4,5 threads=1,2 monsters=5000,20000 bots=1000 $r" "$m" 5 forever 7200 0 "" 1 1
      fw fuzz "$r ops=50000 kills=200" "$m" 4 forever 3600 0 "" 4 4
      fw shell "script=wirefuzz iters=2000000" "$m" 4 forever 7200 0 1024 1 1
      i=$((i + 1))
    done
    fw balance "seeds=1 per=2 minutes=10 fast=16 hours=160" any 7 forever 14400 21600
    fw package "target=linux" linux 8 forever 7200 86400
    fw package "target=windows" windows 8 forever 7200 86400
    fw frames "zooms=16,4 secs=60" gpu 8 forever 1800 43200
    echo "FILL-WEEK machines=$(echo $machines | tr ' ' ,) added=$added updated=$updated jobs=$(grep -c . <<<"$have") (forever jobs: they run until cancelled)" ;;
  digest)
    days=7; for a in "$@"; do case "$a" in --since=*) days=${a#--since=} ;; esac; done
    re='^[0-9]+$'; [[ "$days" =~ $re ]] || { echo "queue: --since=DAYS" >&2; exit 2; }
    gb_fetch "$BRANCH" || { echo "queue: no results branch yet"; exit 1; }; q_fetch || true
    R="refs/remotes/origin/$BRANCH"; cut=$(date -u -d "$days days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"$days"d +%Y-%m-%dT%H:%M:%SZ)
    cutday=${cut%%T*}
    echo "DIGEST of the last $days day(s), since $cut (newest first below; read this before anything else)"
    rows=$(git grep -I -e '' "$R" -- 'work/' 2>/dev/null | sed "s#^$R:##" \
      | awk -F: -v c="$cut" '$1 ~ /^work\/[^\/]+\/[^\/]+\.txt$/ { p=$1; sub(/^[^:]*:/,""); if (substr($0,1,20) >= c) print p "\t" $0 }')
    echo "-- jobs done per machine"
    awk -F'\t' '{ n=split($1,a,"/"); m=a[n]; sub(/\.txt$/,"",m); split($2,w," "); st=w[2]; c[m]++; s[m,st]++; if(!(m in seen)){seen[m]=1; ms=ms " " m} }
      END { for (m in c) printf "  %-14s jobs=%d pass=%d info=%d fail=%d skip=%d\n", m, c[m], s[m,"PASS"], s[m,"INFO"], s[m,"FAIL"], s[m,"SKIP"] }' <<<"$rows" | sort
    nrows=$(grep -c . <<<"$rows"); nfail=$(grep -c $'\t[^ ]* FAIL ' <<<"$rows")
    echo "-- hours worked versus idle (from <machine>-hours.txt; busy = any lane worked; up = heartbeats x 0.5 h)"
    tb=0; ti=0
    for f in $(git ls-tree --name-only "$R" | grep -e '-hours\.txt$'); do
      m=${f%-hours.txt}
      read -r b i lh ln < <(gb_cat "$BRANCH" "$f" | awk -v c="$cutday" '$1 >= c { split($2,x,"="); split($3,y,"="); b+=x[2]; i+=y[2]
        for (k = 4; k <= NF; k++) { split($k,z,"="); if (z[1] == "lane_h") l += z[2]; if (z[1] == "lanes") n = z[2] } } END { printf "%.1f %.1f %.1f %d\n", b, i, l, n }')
      hb=$(git log --since="$days days ago" --format=%h "$R" -- "$m-heartbeat.txt" 2>/dev/null | grep -c .)
      printf '  %-14s busy=%sh idle=%sh up~%sh%s\n' "$m" "$b" "$i" "$(awk -v h="$hb" 'BEGIN { printf "%.1f", h / 2 }')" "$([ "${ln:-0}" -gt 0 ] && echo " lane_h=${lh} lanes=$ln (lane_h / (busy+idle) = lanes in use on average)")"
      tb=$(awk -v a="$tb" -v b="$b" 'BEGIN { print a + b }'); ti=$(awk -v a="$ti" -v b="$i" 'BEGIN { print a + b }')
    done
    echo "-- FAIL lines (machine, job, seed and detail)"
    fails=$(awk -F'\t' '$2 ~ /^[^ ]+ FAIL / { n=split($1,a,"/"); m=a[n]; sub(/\.txt$/,"",m); print "  " m " " $2 }' <<<"$rows" | sort -k2 -r | cut -c1-260)
    [ -n "$fails" ] && echo "$fails" || echo "  none"
    echo "-- newest artifacts (CSV and tables, on branch $BRANCH)"
    git log --since="$days days ago" --diff-filter=AM --name-only --format='@%cI' "$R" -- work/ 2>/dev/null \
      | awk '/^@/ { d=substr($0,2,16); next } /\/art\// && !s[$0]++ { print "  " d " " $0 }' | head -8
    echo "-- queue now"
    if [ -n "${Q_TREE:-}" ]; then
      echo "  pending/known jobs=$(grep -c '^queue/' <<<"$Q_TREE") claims=$(grep -c '^claims/' <<<"$Q_TREE") done_records=$(grep -c '^done/' <<<"$Q_TREE") (queue.sh list for detail)"
    else echo "  empty: the stations are on their built-in deep soak. Run: tools/station/queue.sh fill-week"; fi
    echo "DIGEST jobs=$nrows fail=$nfail busy_h=$tb idle_h=$ti since=${days}d" ;;
  step)
    queue_step; rc=$?; echo "queue step rc=$rc (0 ran a job, 1 nothing to do, 3 interrupted)"; exit $rc ;;
  *)
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

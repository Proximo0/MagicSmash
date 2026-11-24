#!/usr/bin/env bash
# Live view of all four station PCs, refreshed every minute. Read-only: it never changes the queue or the PCs.
# Usage: tools/station/monitor.sh [--once] [seconds]     (Windows: double-click tools\station\monitor.cmd)
# Per PC: heartbeat age (OK under 45 min, LATE under 2 h, DOWN after), lanes busy, free RAM, why it last skipped
# a job, and the jobs it holds now. Then failures of the last 6 hours and the queue size.
# It fetches into its own cache (~/.hh_monitor.git), so it never touches a station's checkout.
set -uo pipefail
once=0; every=60
for a in "$@"; do case $a in --once) once=1 ;; *[!0-9]*) ;; *) every=$a ;; esac; done
url=${HH_REPO_URL:-https://github.com/Proximo0/MagicSmash.git}
cache=${HH_MONITOR_CACHE:-$HOME/.hh_monitor.git}
[ -d "$cache" ] || git init -q --bare "$cache"
G() { git --git-dir="$cache" "$@"; }
secs() { date -u -d "$(sed 's/T/ /; s/Z$//' <<<"$1")" +%s 2>/dev/null || echo 0; }
ago() { local s=$1; if (( s < 120 )); then echo "${s}s"; elif (( s < 7200 )); then echo "$((s/60))m"; else echo "$((s/3600))h$(( (s%3600)/60 ))m"; fi; }
if [ -t 1 ]; then R=$'\e[31m'; Y=$'\e[33m'; Gn=$'\e[32m'; B=$'\e[1m'; N=$'\e[0m'; else R=; Y=; Gn=; B=; N=; fi

show() {
  local now ok=1 m hb t age state jobs f mm lane st kind
  if ! G fetch -q --depth=1 "$url" "+refs/heads/station-results:refs/heads/r" "+refs/heads/station-queue:refs/heads/q" 2>/dev/null; then
    echo "${R}Could not reach GitHub (no internet?). Showing the last copy.${N}"; ok=0
  fi
  G rev-parse -q --verify r >/dev/null || { echo "No data yet."; return; }
  now=$(date -u +%s)
  printf '%sHORDE & HEARTH STATIONS%s   %s (your time)   refresh every %ss, Ctrl+C to quit\n\n' "$B" "$N" "$(date '+%a %d %b %H:%M')" "$every"
  local claims; claims=$(G ls-tree -r --name-only q claims 2>/dev/null)
  for m in msi laptop heatherspc ubuntu; do
    hb=$(G show "r:$m-heartbeat.txt" 2>/dev/null | head -1)
    t=$(sed -nE 's/.* time=([^ ]+).*/\1/p' <<<"$hb")
    if [ -z "$t" ]; then printf '%s%-11s NO HEARTBEAT%s\n' "$R" "$m" "$N"; continue; fi
    age=$(( now - $(secs "$t") ))
    if (( age < 2700 )); then state="${Gn}OK  ${N}"; elif (( age < 7200 )); then state="${Y}LATE${N}"; else state="${R}DOWN${N}"; fi
    printf '%s%-11s%s %s  seen %-6s ago  lanes %-5s free RAM %s MB  disk %s GB\n' "$B" "$m" "$N" "$state" "$(ago $age)" \
      "$(sed -nE 's/.*lanes_busy=([^ ]+).*/\1/p' <<<"$hb")" "$(sed -nE 's/.*free_mb=([0-9]+).*/\1/p' <<<"$hb")" \
      "$(sed -nE 's/.*disk_free_gb=([0-9]+).*/\1/p' <<<"$hb")"
    st=$(sed -nE 's/.*last_skip="([^"]*)".*/\1/p' <<<"$hb"); [ -n "$st" ] && printf '              last skip: %s\n' "${st:0:100}"
    jobs=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      mm=${f##*.}; [ "${mm%-*}" = "$m" ] || continue
      lane=${mm##*-}; local id=${f#claims/}; id=${id%.*}
      kind=$(G show "q:queue/$id.job" 2>/dev/null | sed -nE 's/^kind=//p' | head -1)
      local args; args=$(G show "q:queue/$id.job" 2>/dev/null | sed -nE 's/^args=//p' | head -1)
      local ct; ct=$(G show "q:$f" 2>/dev/null | sed -nE 's/.*time=([0-9]+).*/\1/p')
      printf '              lane %-2s %-8s running %-7s %s\n' "$lane" "${kind:-?}" "$( [ -n "$ct" ] && ago $(( now - ct )) )" "${args:0:60}"
      jobs=$((jobs + 1))
    done <<<"$claims"
    (( jobs == 0 )) && printf '              %sno job running%s\n' "$Y" "$N"
  done
  echo
  local since fails; since=$(date -u -d '6 hours ago' +%Y-%m-%dT%H:%MZ)
  fails=$(for m in msi laptop heatherspc ubuntu; do G show "r:$m-failures.txt" 2>/dev/null; done | awk -v s="$since" '$1 >= s' | sort | tail -8)
  if [ -n "$fails" ]; then
    printf '%sFailures, last 6 hours (newest last):%s\n' "$Y" "$N"
    while IFS= read -r l; do echo "  ${l:0:140}"; done <<<"$fails"
  else echo "${Gn}No failures in the last 6 hours.${N}"; fi
  printf '\nQueue: %s jobs waiting or repeating, %s running.   ' "$(G ls-tree --name-only q queue/ 2>/dev/null | grep -c '\.job$')" "$(grep -c . <<<"$claims")"
  (( ok )) && echo "Data fresh from GitHub." || echo
  echo "A PC that says DOWN: see the cheatsheet (restart its station)."
}

while :; do
  out=$(show 2>&1)
  (( once )) || printf '\e[H\e[2J'
  printf '%s\n' "$out"
  (( once )) && exit 0
  sleep "$every"
done

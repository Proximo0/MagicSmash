#!/usr/bin/env bash
# Shared by jobs/lanhost.sh and jobs/lanplay.sh (the LAN rehearsal, docs/realm/ops.md "LAN rehearsal"). Sourced, never run.
# The host's info (LAN address, ports, times, the PUBLIC dev certificate, never a key) travels as ONE file on the
# results branch, `lan/host.txt`, written with queue_lib's gb_put (a queue job's art is published only when the job
# ends, which is too late for players). STATION_LAN_DIR=dir keeps it in dir/host.txt instead of git (the local test).
. "$(dirname "${BASH_SOURCE[0]}")/queue_lib.sh"
LAN_FILE="lan/host.txt"

lan_put() {  # $1 = file to publish as lan/host.txt
  if [ -n "${STATION_LAN_DIR:-}" ]; then mkdir -p "$STATION_LAN_DIR" && cp "$1" "$STATION_LAN_DIR/host.txt"; return; fi
  ( cd "$(dirname "${BASH_SOURCE[0]}")/../.." && gb_put_retry "$BRANCH" "$MACHINE: lan host info" "+$LAN_FILE:$1" )
}
lan_get() {  # prints the published host file, or nothing
  if [ -n "${STATION_LAN_DIR:-}" ]; then cat "$STATION_LAN_DIR/host.txt" 2>/dev/null; return 0; fi
  ( cd "$(dirname "${BASH_SOURCE[0]}")/../.." && gb_fetch "$BRANCH" && gb_cat "$BRANCH" "$LAN_FILE" ) | tr -d '\r'
}

lan_ip() {  # this machine's LAN IPv4. STATION_LAN_IP overrides. Linux: the source address of the route to the internet;
  # Windows (Git Bash): PowerShell's default-gateway adapter, else the first private address `ipconfig` lists.
  local ip=${STATION_LAN_IP:-}
  if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then ip=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1); fi
  if [ -z "$ip" ] && command -v hostname >/dev/null 2>&1; then ip=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1); fi
  if [ -z "$ip" ] && command -v powershell.exe >/dev/null 2>&1; then
    ip=$(powershell.exe -NoProfile -Command '(Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq "Up" } | Select-Object -First 1).IPv4Address.IPAddress' 2>/dev/null | tr -d '\r' | grep -E '^[0-9.]+$' | head -1)
  fi
  if [ -z "$ip" ] && command -v ipconfig >/dev/null 2>&1; then
    ip=$(ipconfig 2>/dev/null | tr -d '\r' | sed -n 's/^ *IPv4[^:]*: *\([0-9.]*\).*/\1/p' | grep -E '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -1)
  fi
  [ -n "$ip" ] && echo "$ip"
}

lan_field() {  # $1 = key, stdin = host file: the value of key=value
  sed -n "s/^$1=//p" | head -1
}

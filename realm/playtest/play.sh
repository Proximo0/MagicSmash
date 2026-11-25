#!/usr/bin/env bash
# Horde & Hearth playtest launcher for Linux (and Git Bash): the same as play.ps1. Reads the LAN host's info (lan/host.txt on
# branch station-results), waits for a live server with 10+ minutes left, saves its certificate and runs the game from this
# checkout with a Godot editor binary (debug, so it honours --dev-cert):
#   GODOT=/path/to/godot bash realm/playtest/play.sh [--dry-run]
# The native module must be built into realm/client/bin (the station job playkit does it).
set -u
url=https://raw.githubusercontent.com/Proximo0/MagicSmash/station-results/lan/host.txt
root=$(cd "$(dirname "$0")/../.." && pwd)
godot="${GODOT:-godot}"
pem="${TMPDIR:-/tmp}/horde_and_hearth_lan.pem"
field() { sed -n "s/^$1=//p" <<<"$text" | head -1 | tr -d '\r'; }
ok=""
for i in $(seq 1 40); do
  text=$(curl -fsSL "$url?nocache=$RANDOM" 2>/dev/null || true)
  now=$(date +%s); end=$(field end_epoch); upd=$(field updated_epoch)
  if [ "$(field state)" = live ] && [ -n "$end" ] && [ -n "$upd" ] && [ "$end" -gt $((now + 600)) ] && [ "$upd" -gt $((now - 900)) ]; then ok=1; break; fi
  echo "Waiting for the game server on the Linux PC to come up (check $i of 40, every 30 s)..."; sleep 30
done
[ -n "$ok" ] || { echo "No live server found in 20 minutes. Is the Linux PC on and running its station?"; exit 1; }
sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' <<<"$text" | tr -d '\r' >"$pem"
[ -s "$pem" ] || { echo "The server info has no certificate."; exit 1; }
gw="$(field ip):$(field tcp_port)"
echo "Server found on $(field machine) at $gw, $(( ($(field end_epoch) - $(date +%s)) / 60 )) minutes left in this session. Starting the game."
cmd=("$godot" --path "$root/realm/client" -- "--gateway=$gw" "--dev-cert=$pem")
[ "${1:-}" = --dry-run ] && { echo "DRYRUN ${cmd[*]}"; exit 0; }
exec "${cmd[@]}"

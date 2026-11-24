#!/usr/bin/env bash
# LAN rehearsal, the HOST (docs/realm/ops.md "LAN rehearsal"). A queue `shell` job for ONE named machine:
#   queue.sh add kind=shell args="script=lanhost secs=1800" needs=ubuntu timeout_s=3600
# Builds the realm release binaries, starts the real gateway (TLS with --dev-cert, a fresh temp store, field hosts) on the
# LAN address, publishes the host info (lan/host.txt on station-results, at once, and lanhost.txt as art) and serves for
# secs seconds, then stops cleanly. While it serves it rewrites the host info every STATION_LAN_REFRESH seconds (default 90; field
# updated_epoch), so players can tell a live host from a file a dead one left; a kill (a merge, a reboot) writes state=ended first. Words: secs=N (default 1800), port=N (TCP, default 7700), fieldport=N (first UDP, 7800).
# Players need: TCP port and UDP fieldport..fieldport+1 open (this script changes no firewall setting). Last line: PASS/FAIL.
secs=1800 port=7700 fieldport=7800
for w in "$@"; do case "$w" in secs=[0-9]*) secs="${w#secs=}" ;; port=[0-9]*) port="${w#port=}" ;; fieldport=[0-9]*) fieldport="${w#fieldport=}" ;; esac; done
[ -n "${STATION_QUEUE_STUB:-}" ] && { echo "PASS lanhost stub secs=$secs"; exit 0; }
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../lan_lib.sh"
command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
command -v cargo >/dev/null 2>&1 || { echo "FAIL lanhost: cargo is not installed on this station"; exit 1; }
ip=$(lan_ip) || true
[ -n "$ip" ] || { echo "FAIL lanhost: no LAN address found (set STATION_LAN_IP)"; exit 1; }
art="${STATION_JOB_ART:-$(mktemp -d)}"; mkdir -p "$art"
work=$(mktemp -d); gw_pid=""
cleanup() { [ -n "$gw_pid" ] && kill "$gw_pid" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT
if [ -z "${STATION_LAN_SKIP_BUILD:-}" ] && [ -z "${STATION_BIN:-}" ]; then   # STATION_BIN: a station lane, the station built this commit
	( cd "$here/../../../realm" && cargo build --release -j2 -p realm-gateway --bin realm-gateway --bin realm-lanplay >"$work/build.log" 2>&1 ) || { tail -5 "$work/build.log"; echo "FAIL lanhost: build failed"; exit 1; }
fi
bin="${STATION_BIN:-$here/../../../realm/target/release}/realm-gateway"
ngw=2
"$bin" --db="$work/realm.db" --dev-login --dev-cert --public-host="$ip" --bind=0.0.0.0 --port="$port" --fields=0,1 --field-port="$fieldport" \
	--max-copies=1 --monsters=1500 --seed="${STATION_JOB_SEED:-1}" --secs="$secs" >"$work/out.log" 2>"$work/err.log" &
gw_pid=$!
for _ in $(seq 1 120); do grep -q '^LISTEN ' "$work/out.log" 2>/dev/null && break; kill -0 "$gw_pid" 2>/dev/null || break; sleep 0.5; done
grep -q '^LISTEN ' "$work/out.log" || { tail -3 "$work/err.log"; echo "FAIL lanhost: the gateway did not start"; exit 1; }
cert="$work/realm.db.dev-cert.pem"
[ -s "$cert" ] || { echo "FAIL lanhost: no dev certificate was made"; exit 1; }
grep -q "PRIVATE" "$cert" && { echo "FAIL lanhost: refusing to publish a file with a private key"; exit 1; }
t0=$(date +%s); t1=$((t0 + secs))
info() {  # $1 = state
	{
		echo "LANHOST v1"; echo "machine=$(q_me)"; echo "ip=$ip"; echo "tcp_port=$port"
		echo "udp_ports=$fieldport-$((fieldport + ngw - 1))"; echo "start_epoch=$t0"; echo "end_epoch=$t1"
		echo "start=$(date -u -d "@$t0" +%FT%TZ 2>/dev/null || date -u +%FT%TZ)"; echo "end=$(date -u -d "@$t1" +%FT%TZ 2>/dev/null || echo "+${secs}s")"
		echo "state=$1"; echo "updated_epoch=$(date +%s)"; cat "$cert"
	} >"$art/lanhost.txt"
}
info live
lan_put "$art/lanhost.txt" || echo "lanhost: could not publish the host info (players will not find it)" >&2
trap 'info ended; lan_put "$art/lanhost.txt"; exit 143' TERM INT
echo "lanhost: serving $ip:$port (udp $fieldport-$((fieldport + ngw - 1))) for ${secs}s" >&2
refresh="${STATION_LAN_REFRESH:-90}"; since=0
for _ in $(seq 1 $((secs + 180))); do
	kill -0 "$gw_pid" 2>/dev/null || break; sleep 1; since=$((since + 1))
	if [ "$since" -ge "$refresh" ]; then   # the line keeps the queue's silence watch (q_watch) from stopping a healthy host
		since=0; info live; lan_put "$art/lanhost.txt" || true; echo "lanhost: live, $((t1 - $(date +%s))) s left" >&2
	fi
done
wait "$gw_pid" 2>/dev/null; rc=$?; gw_pid=""
info ended; lan_put "$art/lanhost.txt" || true
stats=$(grep '^STATS ' "$work/out.log" | tail -1)
errs=$(grep -ciE 'panicked|not applied|could not|not kept|unknown hero|error' "$work/err.log")
cp "$work/err.log" "$art/lanhost-gateway.log" 2>/dev/null; tail -c 60000 "$art/lanhost-gateway.log" >"$art/lanhost-gateway.tail" 2>/dev/null; mv "$art/lanhost-gateway.tail" "$art/lanhost-gateway.log"
logins=$(sed -n 's/.*logins=\([0-9]*\).*/\1/p' <<<"$stats")
if [ "${logins:-0}" = 0 ] && [ -n "$stats" ] && [ "$rc" = 0 ]; then echo "FAIL lanhost: no player connected (ip=$ip secs=$secs ${stats#STATS })"; exit 1; fi
if [ -n "$stats" ] && [ "$rc" = 0 ] && [ "$errs" = 0 ]; then echo "PASS lanhost ip=$ip secs=$secs ${stats#STATS } errors=0"; exit 0; fi
echo "FAIL lanhost ip=$ip secs=$secs rc=$rc ${stats#STATS } errors=$errs $(grep -iE 'panicked|error' "$work/err.log" | head -1 | cut -c1-120)"; exit 1

#!/usr/bin/env bash
# LAN rehearsal, the PLAYERS (docs/realm/ops.md "LAN rehearsal"). A queue `shell` job for the machines that are not the host:
#   queue.sh add kind=shell args="script=lanplay secs=600 bots=4" needs=msi timeout_s=1800
# Reads the live host's info (lan/host.txt on station-results), then runs `bots` bots of realm-lanplay through the real
# client path: TLS trusting exactly the published certificate (--ca), login, hero, town, field ticket, field play over UDP
# with the per-admission key, bank. Words: secs=N (default 300), bots=K (default 4), wait=N (seconds to wait for a host, 900).
# A host file counts only when it is FRESH: state=live, time left, and updated_epoch (the host rewrites it every ~90 s) not older than
# this job's own start (minus STATION_LAN_SLACK, default 60 s, for clocks that differ). A file left by a host that died is stale.
# Last line: PASS (no handshake or auth failure, outings done), `INFO lanplay: no live host`, or FAIL.
secs=300 bots=4 wait=900
for w in "$@"; do case "$w" in secs=[0-9]*) secs="${w#secs=}" ;; bots=[0-9]*) bots="${w#bots=}" ;; wait=[0-9]*) wait="${w#wait=}" ;; esac; done
[ -n "${STATION_QUEUE_STUB:-}" ] && { echo "PASS lanplay stub secs=$secs bots=$bots"; exit 0; }
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../lan_lib.sh"
command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
command -v cargo >/dev/null 2>&1 || { echo "FAIL lanplay: cargo is not installed on this station"; exit 1; }
art="${STATION_JOB_ART:-$(mktemp -d)}"; mkdir -p "$art"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
pstart=$(date +%s)
live() {  # a fresh live host file in $work/host.txt, with time left
	lan_get >"$work/host.txt"
	[ "$(lan_field state <"$work/host.txt")" = live ] || return 1
	upd=$(lan_field updated_epoch <"$work/host.txt"); [ -n "$upd" ] && [ "$upd" -ge $((pstart - ${STATION_LAN_SLACK:-60})) ] || return 1
	end=$(lan_field end_epoch <"$work/host.txt"); [ -n "$end" ] && [ $((end - $(date +%s))) -ge 20 ]
}
waited=0
until live; do
	[ "$waited" -ge "$wait" ] && { echo "INFO lanplay: no live host"; exit 0; }
	sleep 10; waited=$((waited + 10))
done
ip=$(lan_field ip <"$work/host.txt"); port=$(lan_field tcp_port <"$work/host.txt"); host=$(lan_field machine <"$work/host.txt")
sed -n '/^-----BEGIN CERTIFICATE-----/,/^-----END CERTIFICATE-----/p' "$work/host.txt" >"$work/host-cert.pem"
[ -s "$work/host-cert.pem" ] && [ -n "$ip" ] && [ -n "$port" ] || { echo "FAIL lanplay: the host info is incomplete"; exit 1; }
if [ -z "${STATION_LAN_SKIP_BUILD:-}" ]; then
	( cd "$here/../../../realm" && cargo build --release -j2 -p realm-gateway --bin realm-lanplay >"$work/build.log" 2>&1 ) || { tail -5 "$work/build.log"; echo "FAIL lanplay: build failed"; exit 1; }
fi
left=$(( $(lan_field end_epoch <"$work/host.txt") - $(date +%s) - 10 )); [ "$left" -lt "$secs" ] && secs=$left
me=$(q_me); base=$(( ($(printf %s "$me" | cksum | cut -d' ' -f1) % 900 + 1) * 1000 ))   # bot numbers differ per machine: no shared hero names
"$here/../../../realm/target/release/realm-lanplay" --addr="$ip:$port" --ca="$work/host-cert.pem" --bots="$bots" --secs="$secs" --base="$base" --field=0,1 >"$work/out.log" 2>"$work/err.log"
rc=$?
cp "$work/out.log" "$art/lanplay.txt"; head -20 "$work/err.log" >>"$art/lanplay.txt"
line=$(tail -1 "$work/out.log")
case $rc in
	0) echo "PASS lanplay host=$host ${line#LANPLAY ok }" ;;
	3) echo "FAIL lanplay: host unreachable (firewall?) $ip:$port from $me" ;;
	*) echo "FAIL lanplay host=$host ${line#LANPLAY } $(head -1 "$work/err.log" | cut -c1-120)" ;;
esac
exit $((rc == 0 ? 0 : 1))

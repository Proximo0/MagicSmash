#!/usr/bin/env bash
# Local two-process test of the LAN rehearsal: jobs/lanhost.sh and jobs/lanplay.sh on ONE machine, the host info passed
# through STATION_LAN_DIR (no git). The host is built to listen on the LAN address (this machine's, else 127.0.0.1), so the dev
# certificate is checked for that IP (the player trusts only the published PEM). Needs cargo; about 45 s after the build.
# Prints LAN ok. queue_test.sh runs it when the release binaries are already built.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T=$(mktemp -d); trap 'kill $hp 2>/dev/null; rm -rf "$T"' EXIT; hp=""
. "$REPO/tools/station/lan_lib.sh"
# The real LAN address when this machine has one (then the certificate must carry it as a subjectAltName IP: it is not in the
# loopback names), else loopback.
ip=$(lan_ip); case "$ip" in ""|127.*) ip=127.0.0.1 ;; esac
export STATION_LAN_DIR="$T/lan" STATION_LAN_IP=$ip TMPDIR="$T" STATION_JOB_SEED=7
mkdir -p "$T/h" "$T/p"; fails=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1 ($2)"; fails=$((fails + 1)); fi; }
( cd "$REPO/realm" && cargo build --release -j2 -p realm-gateway --bin realm-gateway --bin realm-lanplay >"$T/build.log" 2>&1 ) || { tail -5 "$T/build.log"; echo "LAN FAILED build"; exit 1; }
export STATION_LAN_SKIP_BUILD=1
bash "$REPO/tools/station/jobs/lanplay.sh" secs=5 bots=1 wait=0 >"$T/none.out" 2>&1
check "no host published: INFO lanplay: no live host" '[ "$(tail -1 "$T/none.out")" = "INFO lanplay: no live host" ]'
STATION_JOB_ART="$T/h" bash "$REPO/tools/station/jobs/lanhost.sh" secs=40 port=17700 fieldport=17800 >"$T/host.out" 2>"$T/host.err" & hp=$!
for _ in $(seq 1 60); do grep -q '^state=live' "$STATION_LAN_DIR/host.txt" 2>/dev/null && break; sleep 1; done
check "the host published its info while running (ip, ports, certificate, no key)" 'grep -q "^ip=$ip" "$STATION_LAN_DIR/host.txt" && grep -q "^tcp_port=17700" "$STATION_LAN_DIR/host.txt" && grep -q "BEGIN CERTIFICATE" "$STATION_LAN_DIR/host.txt" && ! grep -q "PRIVATE" "$STATION_LAN_DIR/host.txt"'
STATION_JOB_ART="$T/p" bash "$REPO/tools/station/jobs/lanplay.sh" secs=25 bots=2 wait=10 >"$T/play.out" 2>"$T/play.err"
echo "  player: $(tail -1 "$T/play.out")"
check "the player passed over TLS with the published certificate" 'tail -1 "$T/play.out" | grep -q "^PASS lanplay .*handshake_failed=0 auth_failed=0"'
check "logins and outings happened, nothing refused" 'tail -1 "$T/play.out" | grep -Eq "logins_ok=[1-9]" && tail -1 "$T/play.out" | grep -Eq "outings=[1-9]" && tail -1 "$T/play.out" | grep -q "refused_datagrams=0"'
check "the player wrote lanplay.txt" '[ -s "$T/p/lanplay.txt" ]'
wait "$hp"; hp=""
echo "  host: $(tail -1 "$T/host.out")"
check "the host stopped cleanly and reported the logins and tickets" 'tail -1 "$T/host.out" | grep -Eq "^PASS lanhost .*logins=[1-9].* tickets=[1-9].*errors=0"'
check "the published file now says ended" 'grep -q "^state=ended" "$STATION_LAN_DIR/host.txt"'
bash "$REPO/tools/station/jobs/lanplay.sh" secs=5 bots=1 wait=0 >"$T/none2.out" 2>&1
check "after the host ended: no live host" '[ "$(tail -1 "$T/none2.out")" = "INFO lanplay: no live host" ]'
# the host is gone but its file looks live (a crashed host, a closed firewall)
sed -i '/^state=/s/ended/live/; s/^end_epoch=.*/end_epoch=9999999999/; s/^updated_epoch=.*/updated_epoch=9999999999/' "$STATION_LAN_DIR/host.txt"
bash "$REPO/tools/station/jobs/lanplay.sh" secs=5 bots=1 wait=0 >"$T/dead.out" 2>&1
check "a live-looking host that is down: FAIL host unreachable (firewall?) with the address" 'tail -1 "$T/dead.out" | grep -q "^FAIL lanplay: host unreachable (firewall?) $ip:17700"'
[ $fails = 0 ] && echo "LAN ok" || { echo "LAN FAILED $fails"; exit 1; }

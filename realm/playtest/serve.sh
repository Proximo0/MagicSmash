#!/usr/bin/env bash
# The playtest server's supervisor (started detached by the station job playhost; never run by hand while one runs).
#   serve.sh DIR REPO IP PORT FIELDPORT
# Runs DIR/bin/realm-gateway on the kept store DIR/realm.db (heroes stay between restarts), publishes the host info as
# lan/host.txt on station-results (the same file and format as jobs/lanhost.sh, so the Play launchers and the lanplay
# bots both find it) every STATION_LAN_REFRESH seconds (default 300) with end_epoch a day ahead, restarts the gateway
# 10 s after it exits, and stops cleanly (heroes banked) when DIR/stop appears.
set -u
dir=$1 repo=$2 ip=$3 port=$4 fport=$5
. "$repo/tools/station/lan_lib.sh"
refresh="${STATION_LAN_REFRESH:-300}"
info() {  # $1 = state
	local now; now=$(date +%s)
	{
		echo "LANHOST v1"; echo "machine=$(q_me)"; echo "ip=$ip"; echo "tcp_port=$port"; echo "udp_ports=$fport-$((fport + 1))"
		echo "start_epoch=$t0"; echo "end_epoch=$((now + 86400))"; echo "start=$(date -u -d "@$t0" +%FT%TZ)"
		echo "end=$(date -u -d "@$((now + 86400))" +%FT%TZ)"; echo "state=$1"; echo "updated_epoch=$now"; echo "kept_store=yes"
		cat "$dir/realm.db.dev-cert.pem"
	} >"$dir/host.txt"
	( cd "$repo" && lan_put "$dir/host.txt" ) >>"$dir/serve.log" 2>&1 || echo "$(date -u +%FT%TZ) publish failed" >>"$dir/serve.log"
}
echo $$ >"$dir/serve.pid"
while [ ! -e "$dir/stop" ]; do
	rm -f "$dir/gateway.stop"
	[ -f "$dir/err.log" ] && tail -c 200000 "$dir/err.log" >"$dir/err.old" && mv "$dir/err.old" "$dir/err.log"
	"$dir/bin/realm-gateway" --db="$dir/realm.db" --dev-login --dev-cert --public-host="$ip" --bind=0.0.0.0 --port="$port" \
		--fields=0,1 --field-port="$fport" --max-copies=1 --monsters=1500 --stop-file="$dir/gateway.stop" >"$dir/out.log" 2>>"$dir/err.log" &
	gw=$!; t0=$(date +%s)
	echo "$(date -u +%FT%TZ) gateway pid=$gw started" >>"$dir/serve.log"
	for _ in $(seq 1 120); do grep -q '^LISTEN ' "$dir/out.log" 2>/dev/null && break; kill -0 "$gw" 2>/dev/null || break; sleep 0.5; done
	if grep -q '^LISTEN ' "$dir/out.log" && [ -s "$dir/realm.db.dev-cert.pem" ] && ! grep -q PRIVATE "$dir/realm.db.dev-cert.pem"; then
		since=$refresh
		while kill -0 "$gw" 2>/dev/null && [ ! -e "$dir/stop" ]; do
			[ "$since" -ge "$refresh" ] && { info live; since=0; }
			sleep 5; since=$((since + 5))
		done
	fi
	[ -e "$dir/stop" ] && touch "$dir/gateway.stop"
	wait "$gw"; echo "$(date -u +%FT%TZ) gateway exited rc=$?" >>"$dir/serve.log"
	[ -s "$dir/realm.db.dev-cert.pem" ] && info ended
	[ -e "$dir/stop" ] || sleep 10
done
rm -f "$dir/serve.pid"

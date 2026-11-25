#!/usr/bin/env bash
# Queue `shell` job: the PLAYTEST server, always up, so Curtis can log in from any of the four PCs (25 Nov 2026: "make
# sure i can log in on all four pcs if i want to for playtesting"). Unlike lanhost (a timed rehearsal on a fresh store),
# it keeps its store in ~/HordeAndHearthServer (heroes stay) and runs detached from the queue, supervised by
# realm/playtest/serve.sh, which restarts the gateway if it exits and publishes lan/host.txt (the same file as lanhost,
# so the Play launchers and the lanplay bots find it). Re-run to update the server to this commit: the old gateway stops
# cleanly first (heroes banked). Words: port=N (TCP, default 7700), fieldport=N (first UDP, 7800). Do not run lanhost on
# the same PC at the same time (same ports). Stop for good: touch ~/HordeAndHearthServer/stop.
#   queue.sh add kind=shell args=script=playhost needs=ubuntu priority=9
set -u
port=7700 fieldport=7800
for w in "$@"; do case "$w" in port=[0-9]*) port="${w#port=}" ;; fieldport=[0-9]*) fieldport="${w#fieldport=}" ;; esac; done
[ -n "${STATION_QUEUE_STUB:-}" ] && { echo "PASS playhost stub"; exit 0; }
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(cd "$here/../../.." && pwd)"
. "$here/../lan_lib.sh"
command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
ip=$(lan_ip) || true
[ -n "$ip" ] || { echo "FAIL playhost: no LAN address found (set STATION_LAN_IP)"; exit 1; }
dir="${STATION_PLAYHOST_DIR:-$HOME/HordeAndHearthServer}"; mkdir -p "$dir/bin"
log="${STATION_JOB_ART:-$dir}/playhost_build.log"; mkdir -p "$(dirname "$log")"
if [ -n "${STATION_BIN:-}" ] && [ -x "$STATION_BIN/realm-gateway" ]; then src="$STATION_BIN/realm-gateway"
else
	( cd "$repo/realm" && cargo build --release -j2 -p realm-gateway --bin realm-gateway ) >"$log" 2>&1 || { echo "FAIL playhost: build: $(tail -2 "$log" | tr '\n' ' ' | cut -c1-160)"; exit 1; }
	src="$repo/realm/target/release/realm-gateway"
fi
old=$(cat "$dir/serve.pid" 2>/dev/null)
if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then   # stop the running server cleanly (serve.sh banks heroes via gateway.stop)
	touch "$dir/stop"
	for _ in $(seq 1 90); do kill -0 "$old" 2>/dev/null || break; sleep 1; done
	kill -0 "$old" 2>/dev/null && { echo "FAIL playhost: the old server (pid $old) did not stop in 90 s"; exit 1; }
fi
rm -f "$dir/stop" "$dir/gateway.stop"
cp "$src" "$dir/bin/realm-gateway.new" && mv "$dir/bin/realm-gateway.new" "$dir/bin/realm-gateway" || { echo "FAIL playhost: copy the gateway"; exit 1; }
cp "$repo/realm/playtest/serve.sh" "$dir/serve.sh"
: >"$dir/out.log"
MACHINE="$(q_me)" BRANCH="$BRANCH" setsid nohup bash "$dir/serve.sh" "$dir" "$repo" "$ip" "$port" "$fieldport" >/dev/null 2>&1 </dev/null &
for _ in $(seq 1 120); do grep -q '^LISTEN ' "$dir/out.log" 2>/dev/null && break; sleep 1; done
grep -q '^LISTEN ' "$dir/out.log" || { tail -3 "$dir/err.log" 2>/dev/null; echo "FAIL playhost: the gateway did not start (see $dir/err.log)"; exit 1; }
sleep 5
echo "PASS playhost ip=$ip port=$port udp=$fieldport-$((fieldport + 1)) store=$dir/realm.db supervisor=$(cat "$dir/serve.pid" 2>/dev/null)"

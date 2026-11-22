#!/usr/bin/env bash
# The world's long proof (realm-world): bots live days of the realm clock with hosts at 20 Hz; copies open and merge, the queue,
# vaults, a field host killed halfway. A queue `shell` job: `kind=shell args="script=worldlong secs=7200"` (secs default 7200).
# station.sh's merge job `world` runs this same script for a short time (STATION_WORLD_SECS, default 600), so there is one command line.
# Also read: STATION_WORLD_BOTS (default 200), STATION_WORLD_DAYS (default 7). Last line: PASS (the sim ended "WORLD ok") or FAIL.
secs=7200
for w in "$@"; do case "$w" in secs=[0-9]*) secs="${w#secs=}" ;; esac; done
[ -n "${STATION_QUEUE_STUB:-}" ] && { echo "PASS world stub secs=$secs"; exit 0; }  # the queue tests run no heavy command
command -v cargo >/dev/null 2>&1 || PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
command -v cargo >/dev/null 2>&1 || { echo "FAIL world: cargo is not installed on this station"; exit 1; }
cd "$(dirname "$0")/../../../realm" || { echo "FAIL world: no realm directory"; exit 1; }
db="${TMPDIR:-/tmp}/station-world.db"
out=$(cargo build --release -j2 -p realm-gateway --bin realm-world 2>&1 && timeout $((secs + 900)) target/release/realm-world --bots="${STATION_WORLD_BOTS:-200}" --days="${STATION_WORLD_DAYS:-7}" --secs="$secs" --tick-us=50000 --vault-tick-us=50000 --monsters=2000 --vault-monsters=2000 --copy-cap=60 --open-at=45 --merge-under=30 --max-copies=4 --merge-grace-ms=5000 --realm-cap=150 --vault-max=8 --outing-ticks=600 --db="$db" 2>&1)
line=$(tail -1 <<<"$out")
rm -f "$db"*
if [[ "$line" == "WORLD ok "* ]]; then echo "PASS world secs=$secs ${line:0:280}"; exit 0; fi
echo "FAIL world secs=$secs $(tail -3 <<<"$out" | tr '\n' ' ' | cut -c1-280)"; exit 1

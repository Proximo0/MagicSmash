#!/usr/bin/env bash
# Every shard of the coverage robot, one after another (tests/bot/bot_cover.gd, docs/bots.md "The coverage robot").
# Usage: tests/bot/cover.sh [nshards=2]. Run from anywhere. A shard is bad on a FAIL row, a missing summary line, a
# non-zero exit or an engine error line. Prints the FAIL rows, one summary line a shard (and the last 40 lines of a bad
# shard's output), then `COVER_ALL shards=N rows=R ok=A pending=P failed=F bad_shards=B` (exit 1 unless F and B are 0).
set -u
N="${1:-2}"; GODOT="${GODOT:-godot}"; LIMIT="${COVER_LIMIT:-300}"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE/../.." || exit 1
LOGS=$(mktemp -d "${TMPDIR:-/tmp}/cover.XXXXXX") || exit 1
trap 'rm -rf "$LOGS"' EXIT
rows=0; ok=0; pending=0; failed=0; bad=0
field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1; }
for ((i = 0; i < N; i++)); do
	log="$LOGS/cover$i.log"
	timeout "$LIMIT" "$GODOT" --headless --fixed-fps 60 --path . res://tests/bot/bot.tscn -- --cover --shard="$i" --nshards="$N" >"$log" 2>&1
	rc=$?
	grep '^COVER .* FAIL ' "$log"
	line=$(grep '^COVER rows=' "$log" | tail -n 1)
	errs=$("$HERE/no_engine_errors.sh" "$log"); erc=$?
	if [ "$rc" != 0 ] || [ -z "$line" ] || [ "$erc" != 0 ]; then
		bad=$((bad + 1))
		echo "cover shard $i/$N is bad (exit $rc): ${line:-no summary line} $(printf '%s' "$errs" | head -n 3 | tr '\n' '|')"
		tail -n 40 "$log"
	else
		echo "cover shard $i/$N: $line"
	fi
	if [ -n "$line" ]; then
		rows=$((rows + $(field "$line" rows))); ok=$((ok + $(field "$line" ok)))
		pending=$((pending + $(field "$line" pending))); failed=$((failed + $(field "$line" failed)))
	fi
done
echo "COVER_ALL shards=$N rows=$rows ok=$ok pending=$pending failed=$failed bad_shards=$bad"
[ "$failed" = 0 ] && [ "$bad" = 0 ]

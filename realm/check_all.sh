#!/bin/bash
# The one Horde & Hearth gate: realm/check.sh and realm/store/check.sh at once (separate workspaces), then
# realm/check_client.sh (it reuses the realm build). One row per check (its own summary line, or its failure lines),
# then one summary line. SKIP_CLIENT=1 leaves the client check out (no Godot on the machine).
# Exit 0 when every check that ran passed.
set -u
cd "$(dirname "$0")"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

./check.sh >"$work/realm" 2>&1 & p1=$!
store/check.sh >"$work/store" 2>&1 & p2=$!
wait $p1; r1=$?
wait $p2; r2=$?
r3=0
if [ "${SKIP_CLIENT:-0}" = 1 ]; then
	echo "REALM_CLIENT skipped (SKIP_CLIENT=1)" >"$work/client"
elif ! command -v "${GODOT:-godot}" >/dev/null 2>&1; then
	echo "REALM_CLIENT skipped (no godot; set GODOT)" >"$work/client"
else
	./check_client.sh >"$work/client" 2>&1; r3=$?
fi

failed=0
for c in realm store client; do
	out="$work/$c"
	rc=$([ $c = realm ] && echo $r1 || { [ $c = store ] && echo $r2 || echo $r3; })
	if [ "$rc" = 0 ]; then
		echo "  $c: $(tail -1 "$out")"
	else
		failed=$((failed + 1))
		echo "  $c: FAILED"
		tail -12 "$out" | sed 's/^/    /'
	fi
done
echo "REALM_CHECK_ALL $([ $failed = 0 ] && echo PASS || echo FAIL) failed=$failed"
[ $failed = 0 ]

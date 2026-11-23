#!/usr/bin/env bash
# Test of fail_detail (queue_lib.sh): a canned cargo failure log must give a FAIL detail with the test name and first panic line.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/station/queue_lib.sh
fails=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails + 1)); fi; }

new=$'running 9 tests\r\n.......F.\n\nfailures:\n\n---- the_tick_is_deterministic stdout ----\n\nthread \'the_tick_is_deterministic\' panicked at gateway/tests/world.rs:212:9:\nassertion `left == right` failed: hash drifted\n  left: 1\n right: 2\nnote: run with `RUST_BACKTRACE=1`\n\nfailures:\n    the_tick_is_deterministic\n\ntest result: FAILED. 8 passed; 1 failed\nerror: test failed, to rerun pass `-p realm-gateway --test world`\nREALM failed: cargo test\n'
d=$(fail_detail <<<"$new")
check "names the failing test" '[[ "$d" == *"failed tests: the_tick_is_deterministic"* ]]'
check "has file:line and the message" '[[ "$d" == *"gateway/tests/world.rs:212: assertion"*"hash drifted"* ]]'
check "has the rerun target and the REALM line" '[[ "$d" == *"rerun -p realm-gateway --test world"* && "$d" == *"REALM failed: cargo test"* ]]'
check "no line break, at most 600 characters" '[[ "$d" != *$'"'"'\n'"'"'* && ${#d} -le 600 ]]'

old=$'test a::b ... FAILED\nthread \'a::b\' panicked at \'boom\', src/lib.rs:7:5\nSTORE failed: cargo test\n'
d=$(fail_detail <<<"$old")
check "old panic format and the test FAILED line" '[[ "$d" == *"failed tests: a::b"* && "$d" == *"src/lib.rs:7:5: "*boom* && "$d" == *"STORE failed: cargo test"* ]]'

long=$(for i in $(seq 1 40); do echo "---- some::very_long_test_name_number_$i stdout ----"; done)
d=$(fail_detail <<<"$long")
check "capped at 600 characters" '[ ${#d} -le 600 ]'
check "a passing log gives an empty detail" '[ -z "$(fail_detail <<<"test result: ok. 9 passed")" ]'

if [ $fails = 0 ]; then echo "FAILDETAIL ok"; else echo "FAILDETAIL FAILED $fails"; exit 1; fi

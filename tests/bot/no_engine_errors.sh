#!/usr/bin/env bash
# Usage: tests/bot/no_engine_errors.sh <bot output log>. Exit 1 and print the lines when a bot run logged an engine
# error: "SCRIPT ERROR:" or "ERROR:" (tools/run_tests.sh counts every engine error but a warning; a test run has the
# same rule in tests/runner.gd). The one line left out is the engine's own exit-time leak report, "ERROR: n resources
# still in use at exit", which every run prints after the game has quit (it is not a game error).
bad=$(grep -E '^(SCRIPT )?ERROR: ' "$1" | grep -v 'resources still in use at exit')
[ -z "$bad" ] || { printf '%s\n' "$bad"; exit 1; }

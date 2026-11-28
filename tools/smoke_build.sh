#!/usr/bin/env bash
# Usage: tools/smoke_build.sh <built game> [--headless]
# Runs the built game's own smoke test (game/debug/smoke.gd) under xvfb-run -a (or --headless), waits at most 120 s
# and checks: exit code 0, a line starting "SMOKE ok", kills above 0, pack_tests/realm/docs all false, no engine
# error line in the log. Prints the SMOKE line and one summary line SMOKE_BUILD ok|FAIL <why>. docs/release_build.md.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:-}"
MODE="${2:-}"
[[ -x "${BIN}" ]] || { echo "SMOKE_BUILD FAIL not an executable: ${BIN}"; exit 1; }
WORK="$(mktemp -d)"
LOG="${WORK}/log.txt"
OUT="${WORK}/smoke.txt"
# A private data folder (the run writes none, but the engine makes its folders) and a silent audio driver (a CI box has no sound card).
ARGS=(--audio-driver Dummy)
RUN=(xvfb-run -a)
if [[ "${MODE}" == "--headless" ]]; then ARGS+=(--headless); RUN=(); fi
"${ROOT}/tools/private_save.sh" timeout 120 "${RUN[@]}" "${BIN}" "${ARGS[@]}" -- --smoke --smoke-out="${OUT}" >"${LOG}" 2>&1
CODE=$?
LINE="$(head -n 1 "${OUT}" 2>/dev/null || true)"
[[ -n "${LINE}" ]] && echo "${LINE}"
why=""
if [[ ${CODE} -ne 0 ]]; then why="exit code ${CODE} (124 means timeout)"
elif [[ "${LINE}" != "SMOKE ok"* ]]; then why="no SMOKE ok line"
elif [[ "${LINE}" =~ kills=([0-9]+) && ${BASH_REMATCH[1]} -le 0 ]] || [[ ! "${LINE}" =~ kills=[0-9]+ ]]; then why="kills is not above 0"
elif [[ "${LINE}" != *"pack_tests=false"* || "${LINE}" != *"pack_realm=false"* || "${LINE}" != *"pack_docs=false"* ]]; then why="tests/realm/docs are inside the pack"
elif ! errs="$("${ROOT}/tests/bot/no_engine_errors.sh" "${LOG}")"; then why="engine error in the log: $(echo "${errs}" | head -n 3 | tr '\n' '|')"
fi
if [[ -n "${why}" ]]; then
	tail -n 20 "${LOG}" >&2
	echo "SMOKE_BUILD FAIL ${why}"
	rm -rf "${WORK}"
	exit 1
fi
echo "SMOKE_BUILD ok"
rm -rf "${WORK}"

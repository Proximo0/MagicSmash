#!/usr/bin/env bash
# Test of the "versions agree" rule in tools/lint.py: a scratch copy of the seven files it reads (never the tree itself), once green,
# then one change per place and a missing versions file. Ends with `LINT_VERSIONS passed=N failed=M` (exit 1 on any failure).
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
PY=$(command -v python3 || command -v python); [ -n "$PY" ] || { echo "LINT_VERSIONS passed=0 failed=1 (no python)"; exit 1; }
T="${TMPDIR:-/tmp}/l1/lint_versions.$$"; rm -rf "$T"; mkdir -p "$T"; trap 'rm -rf "$T"' EXIT
FILES=(tools/lint.py tools/versions.env .github/workflows/build.yml .github/workflows/checks.yml CLAUDE.md docs/agent/preamble.md project.godot)
P=0; F=0
fresh() { rm -rf "$T/t"; for f in "${FILES[@]}"; do mkdir -p "$T/t/$(dirname "$f")"; cp "$ROOT/$f" "$T/t/$f"; done; }
lint() { "$PY" "$T/t/tools/lint.py" 2>&1; }
# red <name> <file> <sed expr> <text expected in the problem line>
red() {
	fresh; sed -e "$3" "$ROOT/$2" >"$T/t/$2"
	local out; out=$(lint)
	if printf '%s\n' "$out" | grep -q "$2:[0-9]* versions" && printf '%s\n' "$out" | tail -n 1 | grep -q '^LINT problems=1$'; then P=$((P + 1)); else F=$((F + 1)); echo "FAIL case: $1: $out" >&2; fi
	[ "${SHOW:-}" = 1 ] && printf '%s\n' "$out"
}
fresh; out=$(lint)
if [ "$(printf '%s\n' "$out" | tail -n 1)" = "LINT problems=0" ]; then P=$((P + 1)); else F=$((F + 1)); echo "FAIL case: green: $out" >&2; fi
red build.yml .github/workflows/build.yml 's/GODOT_VERSION: 4.7.2/GODOT_VERSION: 4.7.1/'
red checks.yml .github/workflows/checks.yml 's/GODOT_VERSION: 4.7.2/GODOT_VERSION: 4.6.0/'
red claude-md CLAUDE.md '1s/4\.7\.2/4.8.0/'
red preamble docs/agent/preamble.md '2s/4\.7\.2/4.5.1/'
red project.godot project.godot 's/PackedStringArray("4.7"/PackedStringArray("4.6"/'
fresh; rm "$T/t/tools/versions.env"; out=$(lint)
if printf '%s\n' "$out" | grep -q 'tools/versions.env:1 versions' && [ "$(printf '%s\n' "$out" | tail -n 1)" = "LINT problems=1" ]; then P=$((P + 1)); else F=$((F + 1)); echo "FAIL case: missing-env: $out" >&2; fi
fresh; sed -e 's/4\.7\.2/4.8.0/' "$ROOT/tools/versions.env" >"$T/t/tools/versions.env"; out=$(lint)
if [ "$(printf '%s\n' "$out" | tail -n 1)" = "LINT problems=5" ]; then P=$((P + 1)); else F=$((F + 1)); echo "FAIL case: env-changed: $out" >&2; fi
echo "LINT_VERSIONS passed=$P failed=$F"
[ "$F" = 0 ]

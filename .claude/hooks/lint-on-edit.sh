#!/bin/bash
# PostToolUse hook (Edit|Write): when the agent edits a .gd file, parse-check that one script and run the static lint
# on it, so a mistake comes back at once instead of at the next test run. Exit 2 shows stderr to Claude (the edit
# already happened); exit 0 stays silent. Any other file, or a missing godot, is a no-op.
set -uo pipefail
input=$(cat)
file=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null)
root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
case "$file" in *.gd) ;; *) exit 0 ;; esac
rel="${file#"$root"/}"
[ "$rel" != "$file" ] && [ -f "$root/$rel" ] || exit 0
# realm/ is its own Godot project (realm/client) with GDExtension classes the root project does not know: checking it
# against the root project gives false errors. realm/check_client.sh covers those scripts.
case "$rel" in realm/*) exit 0 ;; esac
command -v "${GODOT:-godot}" >/dev/null 2>&1 || exit 0
cd "$root" || exit 0
problems=""
# A class_name the class cache does not yet list for this file needs an import first (about 5 s); otherwise under a second.
cls=$(sed -n 's/^class_name \([A-Za-z0-9_]*\).*/\1/p' "$rel" | head -1)
cache=.godot/global_script_class_cache.cfg
if [ -n "$cls" ] && ! { [ -f "$cache" ] && python3 - "$cache" "$cls" "res://$rel" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
for block in text.split("}, {"):
    if f'"class": &"{sys.argv[2]}"' in block and f'"path": "{sys.argv[3]}"' in block:
        sys.exit(0)
sys.exit(1)
PY
}; then
  tools/import.sh >/dev/null 2>&1 || problems+="import failed, see /tmp/$(basename "$PWD")_import.log"$'\n'
fi
if [ "$rel" != "tools/lint_parse.gd" ]; then
  out=$("${GODOT:-godot}" --headless --path . -s res://tools/lint_parse.gd -- "res://$rel" 2>&1)
  if printf '%s\n' "$out" | grep -q '^PARSE_FAIL '; then
    problems+=$(printf '%s\n' "$out" | grep -E '^(SCRIPT )?ERROR: |res://[^ ]+:[0-9]+' | head -6)$'\n'
  fi
fi
lint=$(python3 tools/lint.py 2>&1 | grep -F "$rel:" || true)
[ -n "$lint" ] && problems+="$lint"$'\n'
[ -z "$problems" ] && exit 0
printf 'lint-on-edit %s:\n%s' "$rel" "$problems" >&2
exit 2

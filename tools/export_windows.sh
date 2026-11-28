#!/usr/bin/env bash
# Export the "Windows Desktop" preset to build/windows/ and zip it to build/Four-of-Wands-windows.zip.
# Default is a release build; --playtest exports the "... Playtest" preset (feature tag playtest, debug flags honoured, .bat launchers copied).
# Quiet: errors (last 20 engine lines) and one summary line. Exit 1 on failure. See docs/release_build.md.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/export_lib.sh"
export_build windows "${1:-}"

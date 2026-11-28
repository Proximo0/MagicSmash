#!/bin/bash
# Cloud session setup: Godot (pinned), render/export helpers and the Rust toolchain, so realm/check_all.sh and
# renders work the moment a session or agent starts. Idempotent; cloud sessions only.
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi
# The engine version has one home: tools/versions.env.
source <(tr -d '\r' <"$(cd "$(dirname "$0")" && pwd)/../../tools/versions.env")
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Godot editor binary (headless-capable), pinned to the project's version.
if ! godot --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/godot.zip" \
    "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  unzip -q "$tmp/godot.zip" -d "$tmp"
  install -m 755 "$tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot
  rm -rf "$tmp"
fi

# xvfb for renders, zip for the Windows export (export templates are fetched by tools/export_windows.sh on first use).
missing=()
command -v xvfb-run >/dev/null 2>&1 || missing+=(xvfb)
command -v zip >/dev/null 2>&1 || missing+=(zip)
command -v unzip >/dev/null 2>&1 || missing+=(unzip)
if [ ${#missing[@]} -gt 0 ]; then
  (apt-get update -qq && apt-get install -y -qq "${missing[@]}") >/dev/null 2>&1 || echo "session-start: could not apt-get ${missing[*]}" >&2
fi

# Rust for Horde & Hearth (realm/check_all.sh), pinned like CI (RUST_TOOLCHAIN in .github/workflows/realm.yml).
RUST_TOOLCHAIN="1.97.0"
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v rustup >/dev/null 2>&1; then
  curl -fsSL https://sh.rustup.rs | sh -s -- -y -q --profile minimal --default-toolchain "$RUST_TOOLCHAIN" >/dev/null 2>&1 \
    || echo "session-start: could not install rustup" >&2
fi
if command -v rustup >/dev/null 2>&1 && ! rustup toolchain list 2>/dev/null | grep -q "^${RUST_TOOLCHAIN}"; then
  (rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal && rustup default "$RUST_TOOLCHAIN") >/dev/null 2>&1 \
    || echo "session-start: could not install Rust $RUST_TOOLCHAIN" >&2
fi
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then echo 'export PATH="$HOME/.cargo/bin:$PATH"' >>"$CLAUDE_ENV_FILE"; fi
# Four of Wands is stopped, so its project is no longer imported here (tools/import.sh does it on first use).

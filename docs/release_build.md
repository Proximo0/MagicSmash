# Release build (Windows and Linux)

## Build
- `tools/export_linux.sh` and `tools/export_windows.sh` write `build/<platform>/` (binary, `.pck` beside it,
  `THIRD_PARTY_NOTICES.txt`, the Sentry files when the addon was fetched, credentials if present) and a zip
  `build/Four-of-Wands-<platform>.zip`. They fetch the export templates (1.2 GB, cached in `~/.cache/godot-templates`).
  On a failure they print the last 20 lines of the engine output; on success one summary line.
- Default = release: no `playtest` feature tag, no `.bat` launchers, `--autotest --capture --scripted --dev --hero`
  ignored (`Flags.DEBUG_ARGS`). `--seed`, `--smoke` and `--sentry-test` work in every build.
  `--playtest` (`tools/export_windows.sh --playtest`) = the presets "Windows Desktop Playtest" / "Linux Playtest"
  (same settings plus tag `playtest`, written to `build/<platform>-playtest/`, with the `.bat` launchers on Windows).
- The pack holds the game only (exclude list in the presets, see `docs/systems.md`, "Release builds").
- Windows version: `application/file_version` and `product_version` are `G.VERSION` + `.0`. When you bump
  `G.VERSION` edit both (4 lines, presets 0 and 3); `test_flags` and the export script fail until they match.
- Icon: `tools/windows/icon.ico` from `python3 tools/make_icon.py` (Pillow; the mage portrait). A stand-in: the
  drawn emblem that reads at 16 px is on the stage 4 art list.
- Still empty in the presets: `application/company_name` and `application/copyright` (the owner names them).
- Crash reports: the build sends them only when `config/sentry_credentials.cfg` exists where it is built (it is
  git-ignored, so a CI build has none and reports nothing).
- Notices: `godot --headless --path . -s tools/tool.gd -- notices [file]`, from the engine's own licence data.
  With `addons/sentry` present it adds the addon's own licence text (MIT), then the sentry-native and Crashpad
  licence texts from `tools/notices/` (sources and hashes in `tools/notices/SOURCES.md`; refetch when the addon is updated).

## Smoke
`tools/smoke_build.sh <binary> [--headless]` runs `<binary> -- --smoke[=seconds] --smoke-out=<file>`: the real title, one
seat with a bot, 20 s of game time (default), one line, exit 0 or 1:
`SMOKE ok version= seconds= kills= pack_tests= pack_realm= pack_docs= renderer=`. The script fails unless the exit code
is 0, kills > 0, the three pack values are `false` (`res://tests`, `realm`, `docs` are not in the pack) and the log has
no engine error. It prints `SMOKE_BUILD ok|FAIL <why>`. Under the editor binary the pack values are `true`.

## CI (`.github/workflows/build.yml`)
On push to main and by hand (not on pull requests, not a required check; a push that changes only documents or
`realm/` starts no build). `build` (ubuntu) exports both, smokes the Linux
build, uploads both for 14 days (a downloaded Linux artifact needs `chmod +x`). `smoke-windows` (windows-latest) runs
the Windows exe with `--headless` and fails unless the exit code is 0, the line starts `SMOKE ok`, kills are above 0
and the three pack values are `false`. Both smoke results are also written as annotations (`smoke-linux`,
`smoke-windows`), so they can be read from the commit's check runs without the log.

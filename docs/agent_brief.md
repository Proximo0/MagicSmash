# Worker brief · shorthand (key in CLAUDE.md)
Base rules = `docs/agent/preamble.md` (every W prompt names it; job shape `docs/agent/brief_template.md`). Repo extras below. Contracts: use, never change.

## Hard rules
- Edit only your listed files. Never: others' files, `project.godot`, autoloads, `tests/runner.gd`, shared bases ⇒ put needed lines in your report.
- No `mcp__hearthbot__`, no messaging the owner. No git at all. Never delete files you didn't make.
- No `flock` (T/*.sh lock import themselves). ≤2 engine runs; never leave one running; `kill <pid>` own only, never `pkill godot`.
- Own checks only: `T/run_tests.sh <name>`, `T/lint.sh`, `T/run_sims.sh` if sim-covered.
- CLI tools via `T/tool.gd` (else `-s` scripts `load()` game classes in `call_deferred`).
- Render: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 <scene|-s script> -- --scripted`. Scratch in `/tmp/<task>/`; look at every PNG.
- No pure `#00FF00` debug colour (classic GPU-glitch colour).
- Failure in a file you didn't touch ⇒ report, don't fix. Long runs: watch log size + error lines.
- Report: 1 files (abs paths) · 2 checks + result lines (`TESTS`/`LINT`/`SIMS`) · 3 what renders showed · 4 notes + lines for L.

## Contracts
- Wave 1 (19 Nov 2026): `docs/push_brief.md` (ownership, shared XP, bots, art).
- Step briefs live in `docs/<step>_brief.md`; point here, don't copy.

## Debug layer
- `Flags`: `args`, `frame`, `commands`, `is_scripted_run()`, `dev_menu()`, `seed_value()`, `register_hash(c)`, `state_hash()`.
- `FrameStamp` (F10/`--stamp`): frame, hash, 112-bit strip; decode `python3 T/frame_code.py decode <png>`.
- `RenderToggles`: F4 hide, F6 particles, F7 MSAA, F8 shadows, F9 3D text.
- `Tuning.shared().<field>` read each tick (`game/debug/tuning.gd`).

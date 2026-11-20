# Magic Smash (Godot 4.7.2, GDScript)

FOUR OF WANDS (working title Magic Smash): a co-op survivors-like wizard shooter, 1 to 4 players (local + LAN,
host-authoritative ENet), Steam launch 18 Dec 2026. 480x270 pixel art, Compatibility renderer.

## Commands
- `tools/run_tests.sh [test_name]`: headless unit tests (`tests/unit/`, ~3 s for all). A pass prints one `TESTS` line, a
  failure its output. A test also fails if the engine logs an error, runs no assert, or takes over 10 s.
- `tools/lint.sh`: parse and static checks for every script. Ends with `LINT problems=<n>`.
- `tools/run_sims.sh [sim_name ...]`: regression sims (`tests/sim/sim_*.gd`, listed in `tests/sim/sim_suite.gd`), in parallel. `sim_horde` asserts a step budget in CPU time; CI gives it its own
  runner (`sims-horde`) with the real budget; `check_all` shares the CPU, so it doubles it.
- `tools/check_all.sh`: everything at once (unit, sims, lint, plus the bot and lab if their scenes exist).
- `tools/import.sh`: the shared import step every tool calls; skipped unless an import input changed (a new file, a
  `class_name` line, an asset). `FORCE_IMPORT=1` forces it.
- `tools/golden.sh [base-ref, default origin/main]`: did this change alter the game? Plays the same seeded bot runs here and in the base
  commit and compares state hashes every 15 s. Ends with `GOLDEN same` or `GOLDEN changed`.
- `tools/map.sh [dir ...]`: one line per script. `tools/outline.sh <file.gd>`: a script's functions with line ranges.
- `.claude/hooks/lint-on-edit.sh`: after every Edit or Write of a `.gd` file, parse-checks and lints it, reporting problems at once.
- `godot --headless --path . -s tools/full_run.gd -- --wizards=4`: bots play a whole run (to the Archlich), one line
  per minute. For balancing; too slow for check_all.
- New command-line tools run through `tools/tool.gd` (`godot --headless --path . -s tools/tool.gd -- <name> [args]`),
  which starts `tools/<name>.gd` after the autoloads exist. A bare `-s` script that names a game class prints eight
  lines of compile errors, then runs anyway (`tools/full_run.gd` does): ignore them, or move it over.
- `tools/export_windows.sh` (zip) and `tools/export_android.sh` (debug APK) write to `build/`.
- `tools/fetch_sentry.sh`: fetches the pinned sentry-godot addon into git-ignored `addons/sentry`.
- Run the game: `godot --path .` (`-- --seed=N` repeats a run). Bots with screenshots (needs a display):
  `xvfb-run -a godot --path . -- --autotest[=wave] [--out=dir]`.

## Layout
- `game/logic/`: pure classes: `World` (the authoritative simulation), `SmashBot`, `Upgrades`, `Spells`, `Loot`, `Gamble`,
  `Profile`, `Results`, `Wizards`, `Achievements`. `game/debug/`: `Tuning` (gameplay numbers, read as `world.tune`), autotest.
- `game/autoload/`: `Flags`, `Controls`, `G`, `Save` (the only reader/writer of `user://profile.json`), `Sfx`, `Net`,
  `Platform` (the only Steam code, `docs/steam.md`), `Crash` (the only Sentry code, `docs/sentry.md`).
- `game/arena/` (renders snapshots), `game/ui/`, `game/input/`, `game/art/` (ASCII-map sprites), `assets/audio`.
- `tests/unit/` (`test_<module>.gd`, `extends TestCase`), `tests/sim/`, `tests/bot/` (`bot.tscn`). `tools/`: shell and stdlib Python.

## Rules
- Static typing everywhere (vars, params, returns). Tabs for indentation.
- Gameplay logic is pure `RefCounted` classes with `class_name`: no Node, no wall clock, no `randf()`; take `delta` and a
  seeded `RandomNumberGenerator`. Pure logic goes in `game/logic/` (or edit `PURE_PREFIXES` in `tools/lint.py`).
- Gameplay numbers live in `Tuning` (or data files), never as literals in logic.
- Every logic module has a unit test file. A change is done when `tools/run_tests.sh` and `tools/lint.sh` pass; a change not
  meant to alter the game (refactor, speed-up) also needs `GOLDEN same`.
- File-local helper names must be unique across the project (one `class_name` space).
- Tools are quiet: errors and failures, then one summary line.
- Scripted shots key on game state with a time fallback, never fixed seconds alone. Compare state hashes only on frames
  where `Flags.commands == 0`. Captures, tests and gates never write player data (`Flags.is_scripted_run()`).
- No secrets in git: credentials live in git-ignored `config/*credentials*`, injected at export.
- Reproduce a bug (test, sim, bot, replay) before fixing it; fix the traced mechanism, not a guess.
- Reading CI: list the run's jobs and steps first, then fetch only the failing job's log, last ~40 lines.

## Reading (keep it small)
- This file is enough to start most tasks. A worker's prompt carries its own contract; do not read the whole brief or handoff unless told to.
- `tools/map.sh` lists every script on one screen; `tools/outline.sh <file>` gives a script's functions. Read functions by line range (`sed -n '409,454p' game/logic/world.gd`); never read a script over 400 lines whole.
- `docs/handoff.md`: the plan and the decisions, for whoever plans the next step. `docs/systems.md`: how each system works, one section per system; read only yours.
- `docs/lessons_learned.md` is for the lead, by section. Workers skip it unless their prompt names a section. Add a row whenever something goes wrong.

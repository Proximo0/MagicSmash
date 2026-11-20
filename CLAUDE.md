# Magic Smash (Godot 4.7.2, GDScript)

FOUR OF WANDS (working title Magic Smash): a co-op survivors-like wizard shooter, 1 to 4 players (local + LAN,
host-authoritative ENet), Steam launch 18 Dec 2026. 480x270 pixel art, Compatibility renderer.

## Commands
Key: `T/` = `tools/`. `GD` = `godot --headless --path .`. Every tool is quiet and ends with one summary line (in caps below).
- `T/run_tests.sh [test_name]`: unit tests (`tests/unit/`, ~3 s). `TESTS`. Also fails on an engine error, no assert, or over 10 s.
- `T/lint.sh`: parse and static checks. `LINT problems=<n>`.
- `T/run_sims.sh [sim ...]`: sims in `tests/sim/` (listed in `sim_suite.gd`), in parallel. `SIMS`. `sim_horde` holds a CPU-time step
  budget: real on CI's own `sims-horde` runner, doubled in `check_all`.
- `T/check_all.sh`: unit, sims, lint, bot (and lab if present). `CHECK_ALL`.
- `T/golden.sh [base=origin/main]`: same seeded bot runs here and in base, state hash every 15 s. `GOLDEN same|changed`.
- `T/map.sh [dir ...]`: one line per script. `T/outline.sh <file.gd>`: its functions with line ranges.
  `T/graph.sh [Class ...]`: who uses a class or autoload and what it uses.
- `T/import.sh`: shared import step, skipped unless an import input changed; `FORCE_IMPORT=1` forces. Every tool calls it.
- `.claude/hooks/lint-on-edit.sh`: lints a `.gd` file after each Edit or Write.
- `GD -s tools/tool.gd -- <name> [args]`: runs `tools/<name>.gd` after autoloads exist (new tools go here). A bare `-s` script
  that names a game class prints eight compile-error lines, then runs (`tools/full_run.gd` does).
- `GD -s tools/full_run.gd -- --wizards=4`: bots play to the Archlich, one line a minute. Balancing only.
- `T/export_windows.sh` (zip), `T/export_android.sh` (debug APK): into `build/`. `T/fetch_sentry.sh`: pinned addon into `addons/sentry`.
- Play: `godot --path .` (`-- --seed=N`). Bots with screenshots: `xvfb-run -a godot --path . -- --autotest[=wave] [--out=dir]`.

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
- Helpers: use agent type `worker` for a change and `scout` for a question (`.claude/agents/`), never `general-purpose`: a general helper costs about 57,000 tokens before it reads anything.
- Fan-out and feel-bug method live in the skills `agent-fanout-playbook` and `measure-fix-loop`: invoke the skill, do not read `docs/playbook.md`.
- `tools/map.sh` lists every script on one screen; `tools/graph.sh <Class>` who uses it; `tools/outline.sh <file>` gives a script's functions. Read functions by line range (`sed -n '409,454p' game/logic/world.gd`); never read a script over 400 lines whole.
- `docs/handoff.md`: the plan and the decisions, for whoever plans the next step. `docs/systems.md`: how each system works, one section per system; read only yours.
- `docs/lessons_learned.md` is for the lead, by section. Workers skip it unless their prompt names a section. Add a row whenever something goes wrong.

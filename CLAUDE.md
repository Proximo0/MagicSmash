# Magic Smash (Godot 4.7.2, GDScript)

Magic Smash: a Smash TV style twin-stick arena shooter with up to 4 wizards (local + LAN, host-authoritative ENet).
It is being reworked into a **co-op survivors-like** for a Steam launch on 18 Dec 2026, priced $4.99-6.99 with
no demo; friends join free through Steam Remote Play Together. Start with `docs/handoff.md`: the plan, the
decisions already made and the loot/gambling rules. 480x270 pixel art drawn from ASCII maps (`game/art/sprites.gd`),
audio in `assets/audio`, music synth in `tools/music`. Renderer: Compatibility on every platform.

## Commands
- `tools/run_tests.sh [test_name]`: headless unit tests (`tests/unit/test_*.gd`); one process per CPU, sharing one queue
  of test methods (~3 s for all, ~0.7 s for one file). A pass prints one `TESTS` line; a failure prints that process's
  output. A test also fails if the engine logs an error while it runs, if it runs no assert, or if it takes over 10 s.
- `tools/lint.sh`: parse and static checks for every script. Ends with `LINT problems=<n>`.
- `tools/run_sims.sh [sim_name ...]`: regression sims (`tests/sim/sim_*.gd`, listed in `tests/sim/sim_suite.gd`), one
  process per sim file, all in parallel (about 60 s). `sim_horde` asserts a step budget in CPU time. CI gives it its
  own runner (`sims-horde`), which holds the real budget; `check_all` shares the CPU, so it doubles the budget.
- `tools/check_all.sh`: everything at once (unit, sims, lint, plus the bot and lab if their scenes exist).
- `tools/import.sh`: the shared import step every tool calls; skipped unless something an import needs changed (a new
  file, a `class_name` line, an asset), so editing a function body costs nothing. `FORCE_IMPORT=1` forces it.
- `tools/golden.sh [base-ref]`: did this change alter the game? Plays the same seeded bot runs here and in the base
  commit (default `origin/main`) and compares the state hash every 15 s of game time. Ends with `GOLDEN same` or
  `GOLDEN changed` and the game second where the two runs part ways. Nothing is stored, so PRs never conflict over it.
- `tools/outline.sh <file.gd>`: a map of a script instead of the script: sections, classes and functions with the lines
  each spans. `world.gd` and `arena.gd` cost about 17,000 and 22,000 tokens to read whole; an outline is about 1,000.
- `.claude/hooks/lint-on-edit.sh`: after every Edit or Write of a `.gd` file, parse-checks that script and lints it (about
  0.8 s; about 5 s when the file adds a new `class_name`). Problems come back to the agent at once.
- `godot --headless --path . -s tools/full_run.gd -- --wizards=4`: bots play a whole run (to the Archlich) and
  print a line per minute. For balancing; too slow for check_all.
- New command-line tools run through `tools/tool.gd` (`godot --headless --path . -s tools/tool.gd -- <name> [args]`),
  which starts `tools/<name>.gd` after the autoloads exist. A bare `-s` script that names a game class prints eight
  lines of compile errors first and then runs anyway (`tools/full_run.gd` still does): ignore those, or move it over.
- `tools/export_windows.sh`: Windows build zip in `build/`. `tools/export_android.sh`: debug APK in `build/`.
- `tools/fetch_sentry.sh`: downloads the pinned sentry-godot addon into the git-ignored `addons/sentry` (the
  Windows export runs it).
- Run the game: `godot --path .` (add `-- --seed=N` for a repeatable run).

## Layout
- `game/autoload/`: `Flags` (run flags, frame counter, state hash), `Controls` (input actions).
- `game/debug/`: `Tuning` (live-tunable gameplay numbers: player speed, spell cooldown scale, auto-aim range, spawn budget, wave scaling, XP curve; `World` reads `world.tune`), kit frame stamp and render toggles (sized for 1080p 3D, not wired in yet).
- `game/logic/`: `World` (the whole authoritative simulation: the timed horde, the Archlich and the win, enemies, spells, pickups, snapshots; seeded
  with `World.new(slots, seed)`), `SmashBot` (play-bot brain shared by the arena and the sims), `Upgrades` (level-up catalogue, seeded offer
  roll and effect values), `Spells` (spell weapon stats per level and the evolutions),
  `Loot` (rarity tiers, chest items, armor stats, run gold), `Gamble` (shrine outcomes and costs),
  `Profile` (crystals and meta unlocks between runs), `Results` (the run's stats, awards and best moments),
  `Wizards` (the four pickable wizards: colour and starting spell), `Achievements` (Steam achievements a run
  earns).
- `game/arena/` (renders snapshots, fx, sound cues), `game/ui/` (title, lobby, font, touch), `game/input/`,
  `game/art/`. Autoloads `G` (constants, scene switch), `Save` (the only reader and writer of
  player data, `user://profile.json`), `Sfx`, `Net` (LAN roster, inputs, snapshots),
  `Platform` (the only code that talks to Steam; a no-op without GodotSteam, an App ID, or in scripted runs;
  see `docs/steam.md`), `Crash` (the only code that talks to Sentry: crash and script-error reports; a no-op
  without the fetched addon, a DSN, or in scripted and editor runs; see `docs/sentry.md`).
- `game/debug/autotest.gd`: `godot --path . -- --autotest[=wave] [--out=dir]` plays with bots and saves screenshots
  (needs a display: `xvfb-run -a godot ...`).
- `tests/bot/bot.tscn`: boots the real game and lets bots play 75 s per shard (seed 101+shard, 1+shard%4 wizards).
  Any run takes `-- --seed=N` for a repeatable World.
- `tests/unit/`: one `test_<module>.gd` per module, `extends TestCase`. `tests/sim/`: regression sims.
- `tools/`: shell and Python tools. Python uses the standard library only.
- `docs/`: `playbook.md` (kickoff, fan-out, measure-fix loop), `agent_brief.md` (contracts and subagent rules),
  `lessons_learned.md`, `new_project_checklist.md`, `production_pipeline.md`, `performance.md`, `online.md`,
  `android.md`, `agent_dashboard.md`, `character_creation_lessons.md`.

## Rules
- Static typing everywhere: typed vars, params and returns. Tabs for indentation.
- Gameplay logic is pure `RefCounted` classes with `class_name`, no Node, no wall clock, no `randf()`: take `delta`
  and a seeded `RandomNumberGenerator`. Nodes are thin wrappers that feed them input. Put pure logic in
  `game/logic/` (or edit `PURE_PREFIXES` in `tools/lint.py`).
- Gameplay numbers live in `Tuning` (or data files), never as literals in logic.
- Every logic module has a unit test file. A change is done when `tools/run_tests.sh` and `tools/lint.sh` pass.
- A change that is not meant to alter the game (a refactor, a file split, a speed-up) is done when `tools/golden.sh`
  prints `GOLDEN same`.
- File-local helper names must be unique across the project (one `class_name` space).
- Tools are quiet: print errors and failures, then one summary line.
- Read a big script through its outline: `tools/outline.sh <file>`, then only the functions you need by line range
  (`sed -n '409,454p' game/logic/world.gd`). Read it whole only when the task really spans the file.
- Reading CI: list the run's jobs and steps first (names, times, conclusion), then fetch only the failing job's log
  with a small tail (about 40 lines); every tool's last line is its summary. A full CI log is thousands of tokens of setup.
- Scripted shots key on game state (an observed condition) with a time fallback, never fixed seconds alone.
- Compare state hashes only on frames where `Flags.commands == 0`.
- Captures, tests and gates never write player data (`Flags.is_scripted_run()`).
- No secrets in git: credentials live in git-ignored `config/*credentials*` and are injected at export.
- Reproduce a bug (test, sim, bot, replay) before fixing it; fix the traced mechanism, not a guess.
- Read `docs/lessons_learned.md` before starting; add a row whenever something goes wrong.

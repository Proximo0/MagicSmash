# Magic Smash (Godot 4.7.2, GDScript)

Magic Smash: a Smash TV style twin-stick arena shooter with up to 4 wizards (local + LAN, host-authoritative ENet).
It is being reworked into a **co-op survivors-like** for a Steam launch on 18 Dec 2026, priced $4.99-6.99 with
no demo; friends join free through Steam Remote Play Together. Start with `docs/handoff.md`: the plan, the
decisions already made and the loot/gambling rules. 480x270 pixel art drawn from ASCII maps (`game/art/sprites.gd`),
audio in `assets/audio`, music synth in `tools/music`. Renderer: Compatibility on every platform.

## Commands
- `tools/run_tests.sh [test_name]`: headless unit tests (`tests/unit/test_*.gd`). Prints failures only.
- `tools/lint.sh`: parse and static checks for every script. Ends with `LINT problems=<n>`.
- `tools/run_sims.sh`: regression sims (`tests/sim/sim_*.gd`, listed in `tests/sim/sim_suite.gd`).
- `tools/check_all.sh`: everything at once (unit, sims, lint, plus the bot and lab if their scenes exist).
- `tools/export_windows.sh`: Windows build zip in `build/`. `tools/export_android.sh`: debug APK in `build/`.
- Run the game: `godot --path .` (add `-- --seed=N` for a repeatable run).

## Layout
- `game/autoload/`: `Flags` (run flags, frame counter, state hash), `Controls` (input actions).
- `game/debug/`: `Tuning` (live-tunable gameplay numbers: player speed, spell cooldown scale, auto-aim range, spawn budget, wave scaling, XP curve; `World` reads `world.tune`), kit frame stamp and render toggles (sized for 1080p 3D, not wired in yet).
- `game/logic/`: `World` (the whole authoritative simulation: waves, enemies, spells, pickups, snapshots; seeded
  with `World.new(slots, seed)`), `SmashBot` (play-bot brain shared by the arena and the sims), `Upgrades` (level-up catalogue, seeded offer
  roll and effect values), `Spells` (spell weapon stats per level and the evolutions).
- `game/arena/` (renders snapshots, fx, sound cues), `game/ui/` (title, lobby, font, touch), `game/input/`,
  `game/art/`. Autoloads `G` (constants, scene switch), `Sfx`, `Net` (LAN roster, inputs, snapshots).
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
- File-local helper names must be unique across the project (one `class_name` space).
- Tools are quiet: print errors and failures, then one summary line.
- Scripted shots key on game state (an observed condition) with a time fallback, never fixed seconds alone.
- Compare state hashes only on frames where `Flags.commands == 0`.
- Captures, tests and gates never write player data (`Flags.is_scripted_run()`).
- No secrets in git: credentials live in git-ignored `config/*credentials*` and are injected at export.
- Reproduce a bug (test, sim, bot, replay) before fixing it; fix the traced mechanism, not a guess.
- Read `docs/lessons_learned.md` before starting; add a row whenever something goes wrong.

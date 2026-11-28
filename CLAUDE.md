# FOUR OF WANDS (repo MagicSmash) · Godot 4.7.2 · GDScript
The only game in work (Curtis, 27 Nov 2026: Horde & Hearth is saved for later in the year, Four of Wands is back up front).
Horde & Hearth lives in `realm/` and `docs/realm/` (its notes: `docs/realm/claude_notes.md`): leave it buildable, do not work on it or read it.

Co-op survivors-like wizard shooter, 1-4p (local+LAN, host-auth ENet). 480x270 pixel art, Compat renderer.
Target (C, 27 Nov 2026): no date. Finish the full, professional game; a later Steam Next Fest (not Feb 2027) is marketing, planned when C says so.
Seven stages closed by gates, never cuts for a date; C gets a playable build at each gate; never a cut-down slice. Plan: `docs/release_plan.md`.

Key: `T/` tools/ · `GD` `godot --headless --path .` · CAPS = the tool's 1 summary line · `⇒` rule · L lead · W worker
· pure = `RefCounted` + `class_name`, no Node · § = doc section

## Find code (never read a script >400 lines whole)
- `T/graph.sh [Class ...]` who uses it / what it uses · `T/map.sh [dir]` 1 line/script · `T/outline.sh f.gd` funcs + line ranges ⇒ read by range.

## Commands
- `T/run_tests.sh [name]` unit ~3 s `TESTS` (fails on engine error, 0 asserts, >10 s) · `T/lint.sh` `LINT problems=n`
- `T/run_sims.sh [sim]` parallel `SIMS` (`sim_horde` CPU budget: real on CI `sims-horde`, ×2 in check_all) · `T/check_all.sh` `CHECK_ALL`
- `T/station/` C's 4 PCs run every merge (`roles.txt`: `checks`, `boss`, `golden`) and queue jobs between merges (`T/station/queue.sh`, shell jobs `T/station/jobs/`; never `fill-week`, that is H&H's). `T/station/read.sh` `STATIONS n= failed= stale=`; setup `T/station/README.md`
- `T/golden.sh [base=origin/main]` `GOLDEN same|changed` · `T/import.sh` only import path, skips no-ops (`FORCE_IMPORT=1`)
- L lands a branch with `T/land.sh` `LAND ok|FAIL` (guard `T/guard.sh` `GUARD problems=n`; `docs/agent/land.md`) · the engine version lives in `T/versions.env` (lint checks the other copies)
- `.claude/hooks/lint-on-edit.sh` auto on .gd edit · new CLI tools: `T/<name>.gd` via `GD -s T/tool.gd -- <name>` (bare `-s` prints 8 bogus errors)
- `tests/bot/cover.sh` `COVER_ALL` every catalog row dealt by force and proven used (`docs/bots.md`) · `GD -s T/tool.gd -- coverage [--gate]` `COVERAGE` its plan
- `GD -s T/full_run.gd -- --wizards=4` one bot run to the Archlich · `GD -s T/playtest.gd -- --runs=4 --wizards=2 --persona=casual` a group (1 run is noise, 4 are too) · win rate ⇒ `gh workflow run balance.yml -f ref=<ref>` (100 runs on GitHub) per arm, `T/balance_compare.py <run> <run>` `COMPARE`
- `T/export_windows.sh` / `T/export_linux.sh` [`--playtest`] / `T/export_android.sh` → `build/` · `T/smoke_build.sh <bin>` `SMOKE_BUILD` (`docs/release_build.md`) · `T/fetch_sentry.sh`
- Play `godot --path . [-- --seed=N]` · bots+shots `xvfb-run -a godot --path . -- --autotest[=wave] [--out=dir] [--perf]`

## Layout
- `game/logic/` pure: World (authoritative sim) SmashBot Upgrades Spells Readings Seals Classes Loot Gamble Profile Results Wizards Achievements Cards LobbyRules
- Split scripts: `World` = `game/logic/world.gd` (fields, step, snapshot, forwarders) + `game/logic/world/*.gd` (`World*` static helpers, 1st arg `w: World`; a kind of cast = `cast_<kind>.gd`); `Arena` = `game/arena/arena.gd` + `view_sync seats events fate_view draw_world draw_fallen draw_fx draw_enemies enemy_view hud tray tray_art results_view` (`Arena*` statics, 1st arg `a: Arena`). `test_world` covers the World helpers.
- `game/debug/` Tuning (all gameplay numbers, `world.tune`), autotest · `game/autoload/` Flags Controls G Save Sfx Net Platform Crash
- Sole owners: Save ↔ `user://profile.json` · Platform ↔ Steam (`docs/steam.md`) · Crash ↔ Sentry (`docs/sentry.md`)
- `game/arena/` renders snapshots · `game/ui/` `game/input/` `game/art/` (ASCII sprites) · `assets/audio`
- `tests/unit/test_<mod>.gd` (TestCase) · `tests/sim/` · `tests/bot/bot.tscn` · `T/` sh + stdlib py

## Rules
- Static types everywhere; tabs. Helper names unique project-wide.
- Logic pure: `delta` + seeded RNG; no wall clock, no `randf()`; in `game/logic/` (other dir ⇒ `PURE_PREFIXES` in `T/lint.py`).
- Numbers ⇒ Tuning/data, never literals. Each logic module has a test.
- Done = tests + lint; no-behaviour change also `GOLDEN same`.
- Unbuilt rows sit on a shelf (`Upgrades.UNBUILT`, `Readings.UNBUILT`, `Profile.UNBUILT`) until the change that builds them; a rule a card adds ⇒ `SmashBot` learns it in the same change.
- Shots key on game state (time fallback). Hash compare only when `Flags.commands == 0`. Scripted runs never write player data (`Flags.is_scripted_run()`).
- No secrets in git (ignored `config/*credentials*`, injected at export). Never commit `.import` churn.
- Repro first (test/sim/bot/replay); fix the traced mechanism.
- CI: list jobs first, then failing log tail ~40.
- Tools quiet: errors/failures, then 1 summary line.

## Helpers and skills (invoke, don't copy into docs)
- Agent types: `worker` (a change), `scout` (a question); a session that lacks them (repo was not its project root at start) uses `claude` + a model override. Never `general-purpose` (~57k tokens before reading anything).
- Every W prompt = `Read docs/agent/preamble.md, then <the job>` (job shape: `docs/agent/brief_template.md`). Model: sonnet for art/UI/tools/docs, opus for game logic.
- Fan-out, briefs, ownership, models → skill `agent-fanout-playbook` · feel/perf bug → `measure-fix-loop` · new project / PC setup → `game-project-kickoff`
- Generic lessons from other games → starter kit `Proximo0/game-starter-kit` `docs/lessons_learned.md`

## Read only when needed
- This file starts most tasks; a W prompt is its whole contract.
- `docs/handoff.md` plan + decisions (L planning) · `docs/systems.md` 1 § per system, yours only
- `docs/stage3_brief.md` stage 3's contract: job order, file owners, shared ids (§ 4.x); W reads only the § its prompt names
- `docs/lessons_learned.md` shorthand, by §; W reads only a § its prompt names. Add a row when something breaks.
- `docs/performance.md` · `docs/online.md` · `docs/android.md` · `docs/bots.md` on those topics
- `docs/content_list.md` part 1 every content row as built (source line, test); part 2 (§ 36-54) the frozen list stage 3 builds, by § · `docs/asset_sources.md` who or what made each asset
- `docs/archive/` full long originals (lessons, brief, process docs); only when a prompt names one

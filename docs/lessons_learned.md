# Lessons (this game) · shorthand, read by §

Key: `X ⇒ Y` = X happened, so do Y · L lead · W worker · PC owner's PC (Remote Control) · RC Remote Control
· CI GitHub Actions · T/ tools/ · p50/p95 frame-time percentiles · §X a section here
`grep -n '^## ' docs/lessons_learned.md` lists §. L reads §Workflow + §Testing when planning; W only the § its prompt names.
Skills hold the process (`agent-fanout-playbook`, `measure-fix-loop`, `game-project-kickoff`). Generic lessons from
other games (3D, physics, Houdini, UE, voxels, MSVC): `docs/archive/lessons_learned_full.md` and the starter kit.
Add a row the day something breaks: `what (numbers) ⇒ rule`. At milestones copy generic rows to the kit.

## Workflow and agents
- Spec said "shorten `Upgrades` texts" but `test_spells` asserts they equal `Spells.EVOS` ⇒ grep tests for a string before planning to change it; list mirrored data in the spec.
- New per-column HUD element collided with the centred LV pill ⇒ map every HUD element's rectangle before giving a brief a screen region.
- L showed owner a portrait with weak spots it had listed itself; owner: not Steam quality ⇒ finished art is judged against shipped store-page games; known weak spots = not ready to show as finished.
- W messaged owner ⇒ W never calls `mcp__hearthbot__`; reports to L only.
- Global `flock` on Godot runs deadlocked ⇒ only `godot --import` takes the import lock; never flock `T/*.sh`.
- Subagents lack Agent tool ⇒ nested fan-out = Workflow tool, or L starts every W.
- 4 cloud cores cap engine runs ⇒ ≤~8 local W; more = remote cloud agents (own branch), CI matrix for scale.
- Engine work queues on one PC ⇒ split step: engine-free core (fan out wide) + narrow engine part (1-2 W, one batched PC run). ≤~4 W per L.
- `git commit -a` took another W's half file ⇒ L stages by name. W never runs git, never deletes files it didn't make.
- Finished W's untracked files vanished ⇒ commit finished W files promptly.
- Tree green locally, red in CI (others' WIP hid it) ⇒ L verifies in a clean clone / worktree of HEAD, commits by name, pushes from it.
- W typed a param as an uncommitted contract class ⇒ duck-type (`Node`) until it lands; lint clean clone before push.
- `(lint; tests; sims) && commit` pushed red ⇒ gate on summary lines (`failed=0`, `problems=0`), not subshell exit.
- W said "skipped as instructed" ⇒ L reruns check_all + bot before committing sim-adjacent files.
- Restarts killed W 3× ⇒ relaunch on the WIP with prior findings, never from scratch.
- `pkill godot` killed another W's run ⇒ kill own PIDs only.
- Shared test failed outside your files ⇒ check other W's recent change first; tell that W.
- Duplicate hand-backs ⇒ TaskStop a W once integrated.
- Misquoted hashes ⇒ quote a hash only after push returns it.
- Owner read long replies for status ⇒ Dashboard artifact fed by JSON, refreshed each merge.
- RC refused guarded action (push, download, install, source edit) on L's say-so ⇒ needs owner's own words in that session; ask once, name the whole step.
- Cloud can't read PC files ⇒ move outputs via git (throwaway orphan branch, e.g. `shots`).
- Two leads pushed main after handover ⇒ one L at a time; check `git log origin/main` before each merge.
- Largest model as L for days ate the budget ⇒ L mid-tier, W small; largest only for short design passes owner asks for.
- Weekly limit stopped 4 W for 23 h ⇒ pace spend; snapshot worktrees to `wip/*` each milestone.
- Commit pushed without attribution trailers (no force-push) ⇒ `git log -1 --format=%B` before every push.
- Unattended git hung 20 min on a credential prompt ⇒ `GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never -c credential.helper=`; every network CI step has `timeout-minutes`.
- "Proof" run skipped the new code ⇒ a proof runs through the code it proves; run every new workflow branch once.
- One PC runner, 4 queued 6-20 min runs ⇒ fast CI mode; slow gates only when diff touches them; cancel covered runs.
- Unattended loops stalled 45 min unseen ⇒ `claude -p` in restart loop, prompt re-read from file; lanes share engine/GPU via lock dir with stale timeout; `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`; external supervisor; cloud L checks newest PC push < 45 min hourly.
- "Work the queue" ran 1 agent for hours ⇒ prompt states W count, model, one worktree + wip branch per W; W never push.
- Agent loops on CI PC pushed perf gate 26-33% over ⇒ loops at Idle priority; one engine process at a time.
- New test matched its own hypothesis, passed with fix off ⇒ every new test shown red without fix, then green; L reruns the red build.
- W report claimed an unmade change ⇒ reports state only what was verified; L checks each claimed fix in the code.
- Hours of guessing a render bug ⇒ cheap env-var/flag-gated "why" traces per subsystem before the 2nd guess.
- Brief said "draw shots 7 px above position" without reading hit code ⇒ before a contract says where something is drawn, read the spawn/aim/hit code and quote its numbers.
- Brief named a new autotest flag `--heroes`; one already ran the Sanctum shots ⇒ grep the flag in `game/debug/autotest.gd` + `tests/bot/` before a brief names one.
- Brief put `sanctum_view.gd` under `game/ui/` (it is `game/sanctum/`) ⇒ `git ls-files | grep <name>` for every owned path before a brief goes out.
- W tree stacked on an unmerged branch, parent then squash-merged ⇒ `git rebase --onto origin/main <parent> <branch>` (clean twice, 27 Nov); until then its golden base is the parent branch.
- `git rev-parse origin/<branch>` failed after a good push; `origin/station-results` stayed stale after a plain fetch ⇒ check a push with `git ls-remote origin <branch>`; fetch station branches as `+refs/heads/X:refs/remotes/origin/X`.
- W's save fix read a newer build's file with a changed field type as damage (put aside as `.bad`) ⇒ L reads each fix for the case next to the tested one; version before types, a newer save is never put aside or written.

## Dashboards
Story: kit `docs/lessons/ops_board.md`.
- Debug runs passed, board missed most agents ⇒ first diff real sources (sessions, workers, `gh run list`, `git log origin/main`) vs board.
- "Every session pushes status": 2 of 5 did ⇒ automate pushes (hook, routine, L's own script); show silent sources.
- Rows said "running" 32 h after pause ⇒ every row has a time and expires; >2 h quiet = gone quiet.
- Same fact, two field names → blank cols, dup cards ⇒ one name per fact, one shared normaliser.
- Card showed $172 / 31% (real $413 / 60%) ⇒ check values against the primary source, not presence; never let a party report its own metrics (`get_session`).
- Page couldn't reach a tool an agent could ⇒ relay on a schedule; make one real call from the page before building on a source.

## Testing and measurement
- Feel bugs found by players ⇒ debug layer + bot before content.
- Fix looked right, bug predated it ⇒ check git history for first appearance.
- Lab WARN almost undid a wanted design ⇒ check WARN vs owner's wishes first.
- Evaluator "bugs" were capture artefacts ⇒ reproduce in the live scene first.
- Balance from stale numbers ⇒ re-measure baseline on current tree after any AI change.
- Bot run hung 15 min, 334 MB log (another W's half-saved script) ⇒ watch log size/error lines, not just exit.
- Rate/s check failed on a 4 s fight ⇒ divide by a floor duration (8 s); bursts → max/s check.
- 4p sim: one wizard stuck at lvl 1 (bots shared orbit `slot*PI`) ⇒ own lane `slot*TAU/4`; check per-player stats.
- False "crash" under pipefail (`echo | grep -q` SIGPIPE) ⇒ `grep -q pat <<<"$out"`.
- Averaged `Performance.TIME_PROCESS`: 36 ms vs real 5.2 ⇒ time real frames (p50/p95/max) after warm-up; profile on real GPU (cloud = software GL).
- First run after import 4× slower; `--fixed-fps` + no vsync ran game time fast ⇒ warm up, rerun a gap twice, report game + wall time.
- Per-script cost unknown ⇒ in the window `set_process(false)` and call each `_process` from one timing node, sum by script.
- Re-stamping unchanged work 30×/s ⇒ time sections in a scripted worst case; gate repeated work on changed input.
- Per-match hitches (63 ms start, 596 ms shader) ⇒ long soak on real hardware; pre-warm effects in the intro.
- Parallel heavy jobs on one laptop skewed results ⇒ one heavy job at a time.
- Fixed ports collided across suites ⇒ `net_port(slot)` in `tests/sim/sim_base.gd`; never a literal port.
- `check_all` logs shared `/tmp/check` ⇒ own `mktemp` dir; last line `CHECK_ALL PASS|FAIL`, exit matches.
- Cloud can't download CI logs ⇒ key results as `::notice`/`::error` annotations; read via `gh api .../check-runs/<id>/annotations`.
- Shots black 3× (no GPU service, bad material, exposure) ⇒ grade every capture (mean, black %), fail on BLACK.
- Once/s debug hash ran every frame at long frames → 0.5 fps ⇒ bound debug work per frame; cache hashes, invalidate on mutation.
- Capture with perf bands off graded 0.5 fps ok ⇒ keep a hard fps floor.
- CI runner checkout belongs to the service ⇒ read with `git -c safe.directory=...`; never pull/clean it; engine only after the job exits.
- PC CI perf gate 2.5-3.7× golden (service on E-cores, EcoQoS) ⇒ perf tests at High priority, EcoQoS off; rerun interactively before blaming code.
- Pinned clock froze the sim in shots ⇒ pin presentation separately from sim; shots wait on observed state.
- 1 unit test = 81% of suite (260-horde 70 s; passed with rule deleted) ⇒ set up only what's tested; delete the rule once to see red; >10 s = fail, long = sim.
- Crash / no-assert test counted as pass ⇒ runner counts asserts + engine errors (`tests/runner.gd`).
- Every tool re-imported (4.6 s) ⇒ `T/import.sh` fingerprints inputs; the only import path.
- `horde_peak_cost_4p` flaky beside other Godot processes (stopwatch) ⇒ budgets count CPU time (`/proc/self/stat`); real budget on its own CI row; shared runs ×2 (`SIM_BUDGET_SCALE`).
- `-s` tool printed 8 bogus compile errors ⇒ start CLI tools via `T/tool.gd` (after autoloads).
- Peak-cost sim made enemies "unkillable" via `Tuning.set_value` (clamps) → empty arena measured ⇒ set the field directly for out-of-range values; sim asserts the condition it measures.
- Killing a horde left 1700 gems, step cost ×2 ⇒ `Tuning.xp_gem_cap` merges XP; watch pickups in cost probes.
- Bot gate "wave 2 within 75 s" paused 1/3 on level-ups ⇒ gate on `World.wave_time`.
- `--autotest` wrote profile.json ⇒ every new capture/bot flag goes into `Flags.is_scripted_run()` same day; check `user://` unchanged.
- Headless runs are scripted: no heroes seated, no unlocks, nothing saved; a bug in heroes, cards or unlocks passed every check ⇒ `bot-heroes` shard builds that state (`Net.force_heroes`, own `XDG_DATA_HOME`); every bot row fails on `SCRIPT ERROR:` / `ERROR:` lines (`tests/bot/no_engine_errors.sh`).
- Socketed card counted twice (`Profile.bonuses()` "armor" to every seat + each hero's own via `apply_hero`) ⇒ one path per stat into the World; test through the real chain with two seats.
- "First kill after the moment gets the card" gave it to the commonest kind (goblins + bats 54% of card runs; PRIEST, GARGOYLE, LICH never) ⇒ roll the kind at run start from what the run can spawn, wait for that kind's kill; test the spread over seeds.
- One pad's B emptied the lobby; the hub's device was lost through the shop ⇒ a button that ends something for the group is checked against the device that pressed it, in a pure rule (`LobbyRules.decide`).
- Run booked only on EV_GAMEOVER: quit, window close, quit during the victory countdown lost it ⇒ every run end goes through one once-guarded booking (`ArenaEvents.book_run_once`). SIGTERM skips the close request in 4.7 (open).
- Balance tools stopped runs at 16 / 18 min, mid-Archlich, and booked a loss ⇒ cap above a run's length (25 min); a capped run is `unfinished` ("U"), never a loss.
- `check_all` beside 3 W: one unit test failed only on the 10 s limit (10.4 s) ⇒ re-run that test alone before believing it.
- `T/run_tests.sh x | tail -1` showed exit-leak lines, not the result ⇒ `grep '^TESTS'`.
- Celeron frame 134 ms: 8 physics ticks a frame, each with its own snapshot (world_step 67 + snapshot 23 ms) ⇒ compare machines per tick (section / ticks a frame); `docs/performance.md` pass 4.
- "Skip if the last one is still here" guard on a timed event dropped it for good (act II boss never came if act I lived past 10:00) ⇒ consume every due row: replace or retire what stands, never skip; test with the earlier event kept alive.
- Boss tuned for a one-screen room fired and teleported from out of sight in the 800x450 room ⇒ boss positions come from the party's middle, never the room's; an attack starts only in the party's sight; probe with the party held in a corner.
- Bot shard stalled silently once the run's scene was swapped (no error, a core at 100%): a freed node reads as `null`, so its `if _arena == null: return` guard held forever ⇒ a shard that leaves the arena reads `G.main.current` each tick and keeps its own started flag.

## Rendering and art
- GPU glitch blamed on a guess ⇒ sample screenshot pixels, reproduce; else ship toggles.
- `-s` render script couldn't see autoloads ⇒ `load()` game classes in a deferred call (or `T/tool.gd`).
- First-use shader hitches at match start ⇒ instance every effect once off-screen at start; GPU perf on real hardware (xvfb skews).
- Service runner, no GPU: captures black at 0.2 fps ⇒ shots in owner's desktop session only.
- Changed bake recipe kept old look ⇒ bake tools take `--force <asset>`; look before pushing.
- 4×4 Bayer dither on dark floor = screen door ⇒ 2×2 + ≥32 levels on dark floors; view at 2×.
- Act change: overlays jumped while backdrop faded 2 s ⇒ overlays cross-fade with their picture; state-keyed shot per transition (`act_fade.png`).
- PS5 JSON had a BOM ⇒ `[IO.File]::WriteAllText` with `UTF8Encoding($false)`.
- Godot bump / Windows import rewrote every `.import` ⇒ never commit that churn; `git restore -- '*.import'`.

## Online, Steam, Android
- Closed ENet peer inside its own `poll()` signal → SIGSEGV ⇒ defer close to next idle frame.
- ENet throttle dropped ~½ unreliable snapshots after a hitch ⇒ throttle off on connect (deceleration 0).
- Reliable events packet >1164 B dropped by relay ⇒ split by bytes under limit, not record count.
- Net soak recorded host pose 1 tick off → 3× error ⇒ record reference at the snapshot's exact tick.
- Secrets must ship but not be public ⇒ git-ignored `config/*credentials*`, injected at export (`docs/online.md`).
- Sentry addon import reordered `project.godot` ⇒ write addon settings by hand in the same change; `git diff project.godot` empty after import.
- `dl.google.com` blocked in cloud ⇒ `T/export_android.sh` builds JDK 17 + SDK from distro packages; real machine: `ANDROID_SDK_ROOT`.
- Android export refused ⇒ keep `import_etc2_astc=true` in `project.godot`.
- APK has no side folder for credentials ⇒ credentials file in the preset's `include_filter`.
- `sims-horde` passed on a fast CI runner, auto-merged, then failed on main (runners differ 1.5x) ⇒ a time-budget row needs 15%+ headroom on the slowest runner before merging; read the row's number in the PR's own log, not only pass/fail.
- A branch cut from an unmerged branch, whose parent was then squash-merged: merging main back doubled a block (`profile.gd`, two `active_hero`) and conflicted on lines both sides had ⇒ cut worker branches from main; if one must stack, after the merge run `git diff origin/main --stat` and check each file shows only the new work, then lint.
- Release export packed the whole repo (tests, realm, docs) and honoured `--autotest` / `--dev`; a CI box without a sound card logged an ALSA `ERROR:` ⇒ pack only the game (`exclude_filter`); debug flags only in editor | debug build | `playtest` tag (`Flags.DEBUG_ARGS`); smoke the built game and read `pack_tests=false` from inside it (`T/smoke_build.sh`); `--audio-driver Dummy` on CI.

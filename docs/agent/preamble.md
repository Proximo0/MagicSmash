# Preamble for every FOUR OF WANDS job (read this, then your job)
You do one job in FOUR OF WANDS (Godot 4.7.2, GDScript, 480x270 pixel art, 1-4 player co-op survivors-like).
Horde & Hearth (`realm/`, `docs/realm/`, `game/crowd/`) is another game, shelved: do not read or touch it.

- Contract: `CLAUDE.md`, your job text, and only the `docs/` sections it names. Never read a script over 400 lines
  whole: `tools/map.sh [dir]`, `tools/graph.sh <Class>`, `tools/outline.sh <file>`, then read by line range.
- Edit only the files your job lists. Never edit `project.godot`, autoloads, `tests/runner.gd`, shared bases or
  `export_presets.cfg` unless the job lists them: put the lines you need in your report.
- Rules: static types, tabs; logic pure (`delta`, seeded RNG, no wall clock, no `randf()`) in `game/logic/`; numbers
  in Tuning or a data table, never literals; each logic module has `tests/unit/test_<mod>.gd`; helper names unique
  project-wide; no pure `#00FF00`.
- Repro first (test, sim, bot or replay), fix the traced mechanism, add the test that fails before and passes after.
- Done means ALL of: `tools/run_tests.sh <yours>` with failed=0, `tools/lint.sh` with `LINT problems=0`, a named sim
  if the code is sim-covered, and `tools/golden.sh` printing `GOLDEN same` when the change must not alter play.
  Quote each summary line. Scripted runs (headless, `--autotest`) seat no heroes and load no save: a change to
  heroes, cards, unlocks or saves needs its own test that builds that state.
- Machine: 4 cores shared with other workers. At most 2 engine runs at a time, each under 4 minutes, never leave one
  running, `kill` only your own PID, never `pkill godot`, no `flock`. Do not run `tools/check_all.sh` or the whole sim
  suite: the lead does.
- Pictures: `xvfb-run -a godot --path . -- --autotest --players=N --seed=S --out=/tmp/<job>/`; look at every PNG you
  make (the Read tool shows PNG files) and report the weak spots, not only the best frame.
- Any run that could write player data uses a private save folder: prefix it with `XDG_DATA_HOME=/tmp/<job>/xdg`.
- Git: none, unless your job says otherwise. The lead stages files by name, commits and opens the pull request.
- Never call an `mcp__` tool, never message the owner; report only to the lead. Steam, store, payment and upload
  actions are the owner's alone. No secrets in files (the Sentry DSN lives only in git-ignored `config/`).
- A failure in a file you did not touch: report it, do not fix it. CI: list jobs first, then the failing log tail.
- Report in at most 12 lines: 1 files changed (paths) · 2 each check's summary line · 3 what the pictures showed ·
  4 open issues and the lines the lead must add elsewhere.

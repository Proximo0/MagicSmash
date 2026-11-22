# Preamble for every Horde & Hearth code job (read this, then your job section)
You build one job of HORDE & HEARTH, a persistent survivor-horde MMO (dark occult, Diablo tone) in `realm/` of this
repo. Your worktree is your own checkout of `main`. Ignore Four of Wands (the Godot game outside `realm/`).
- Contract: `docs/realm/build_plan.md` (your row), `docs/realm/rules.md` (only the sections named), `realm/README.md`,
  `docs/realm/rules_built.md` (what R1 built and changed). Read code by line range; use `grep -n` to find things.
- FULL BUILD, never a demo or sample: build the system for the whole game (all six fields, classes to 60, every kind).
- Rust, std only, except crates already in a Cargo.toml (store: rusqlite; godot: godot). Whole numbers in the sim,
  seeded RNG, no wall clock in `realm/core`. Determinism across thread counts and OS is a law (`same-hash` CI job).
- Stay inside the files your job owns; if you must touch another owner's file, keep it to a small interface
  addition and say so in the report.
- Tests for every rule you add. Done = `cd realm && ./check.sh` prints `REALM ok ...` (and `realm/store/check.sh`
  `STORE ok` if you touched the store), and the proof named in your job passes. Use `cargo build --release -j2`
  (other jobs share the 4 cores).
- Write a short doc for what you built (named in your job), with every number you chose and why, and open questions.
- Do not run git commit/push, do not install packages, do not write under /mnt/project-files, do not message anyone.
- Report in at most 15 lines: what is built, files changed, check summary lines, the proof's numbers, what is left.

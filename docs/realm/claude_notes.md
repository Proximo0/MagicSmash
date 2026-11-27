# Horde & Hearth working notes (moved out of CLAUDE.md on 27 Nov 2026; the game is shelved for later in the year)

# HORDE & HEARTH is the only game in work (Curtis, 21 Nov 2026: "stop four of wands and work entirely on this title")
Code in `realm/`: Rust core, server, gateway, store, ops, loot, loadtest; Godot client in `realm/client`.

## Read only this, then the files your job touches
- Jobs, owners, proofs: `docs/realm/build_plan.md`. Job briefs: `docs/realm/briefs/`. One doc per system in
  `docs/realm/` (rules, store, wire, world, homes, ops, balance, economy, social, client, shell): read only yours.
- Do not read `docs/handoff.md`, `docs/lessons_learned.md`, `docs/archive/` or `docs/four_of_wands/`: they are for
  FOUR OF WANDS (the rest of the repo), which is stopped. Leave it buildable; change it only when asked.
- Never read a large source file whole; grep, then read by line range.

## Checks
- `realm/check.sh` (`REALM ok ...`), `realm/store/check.sh` (`STORE ok ...`), `realm/check_client.sh` (needs Godot;
  not run by CI: run it after changes to core, server or the client), `realm/check_all.sh`.
- CI `.github/workflows/realm.yml`. Test stations on four PCs: `tools/station/roles.txt`, results `tools/station/read.sh`.

## Rules
- Deterministic sim: seeded RNG, no wall clock in core logic; Linux and Windows must hash the same.
- Wire tags: each system owns a range in `realm/gateway/src/proto/ranges.rs`; never reuse a number.
- Art models must be commercial-OK and listed in the art runner's `licences.json`.
- No secrets in git (ignored `config/*credentials*`). Never commit `target/` or `.import` churn.
- Repro first (test, sim, bot or replay); fix the traced mechanism. Done = checks green.
- Agent types: `worker` (a change), `scout` (a question), never `general-purpose`.

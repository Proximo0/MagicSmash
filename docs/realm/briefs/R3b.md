# R3b: finish players against players on the server (plunder items, guild wars in the field hosts)

Why: R3 (#123) left two halves unjoined (docs/realm/pvp.md, "Open questions" 1 and 2). Until they are joined, a
plundered haul loses only coin and an altar war declared in town never reaches a field.

## Build
1. Plunder items. On the core's `Plunder` event the server moves the lost haul items to the plunderer (`by`):
   find where the host applies outing results and where the loot job's `Haul::fall` decides what is lost. One store
   transaction per plunder, ledger lines on both sides, origin kept on every item (botter tools must still trace it),
   idempotent if the event is applied twice. Bag full: the overflow goes to the winner's mail or parcel as other
   overflow does today; never destroyed silently.
2. Wars in the field hosts. Bridge gateway social to field hosts:
   - at admit, tag the hero with its guild (`Field::set_guild`, from `Social::guild_of_account`);
   - before each tide, arm `declare_war` on every copy of the field (`Social::wars_for`);
   - send the war's end back (`Social::war_result`).
   Followers must apply the same calls so hashes match: the Join record carries the guild and a WAR record is added to
   the lockstep wire. Wire tags only from the PvP range reserved in `realm/gateway/src/proto/ranges.rs`; never reuse a
   number. Copies that open or merge mid-war must carry the war (W2: copies open and merge).
3. Tests: a plundered haul moves items and coin once, with ledger lines, and survives a crash between the two sides
   (store fuzz style); a declared war arms in two copies, follower hash equals host hash through a war, the result
   reaches Social; a merge during a war keeps it; decoders of the new records are in the wire fuzz list.
4. Docs: update docs/realm/pvp.md (close questions 1 and 2), docs/realm/wire.md for the new records.

## Rules
- Deterministic sim: seeded RNG only, no wall clock in core logic; Linux and Windows hash the same.
- Field hosts now authenticate packets (TLS job, `realm/server/src/mac.rs`); keep that intact.
- Keep `realm/check.sh` (`REALM ok`) and `realm/store/check.sh` (`STORE ok`) green. check.sh takes over 10 minutes:
  run it in the background with a long timeout; while fixing, re-run only failing tests.
- Do not run git. Do not message anyone. Read only: this brief, docs/realm/pvp.md, the parts of wire.md and world.md
  you need, and the files you touch (grep, then read by line range).

## Done
Report in at most 15 lines: what is built, the check summary lines, new wire tags, and honest weak points (what a
reviewer should attack first).

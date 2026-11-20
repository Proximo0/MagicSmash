# Handoff: the plan and the decisions

For whoever plans the next step. How each system works: `docs/systems.md` (one section per system).

**The game:** FOUR OF WANDS (working title Magic Smash), a tarot-dealt co-op survivors-like. One to four wizards
hold their tower, level up together, and bet the whole party's fate on a card. Pillars: co-op first (shared party
XP, one pick screen, revives, a readable shared screen, AI apprentices for empty seats); fate (tarot draws, gamble
shrines, the party's fate card); a tower worth exploring (the Sanctum, secrets, monster cards).

## Where things stand (20 Nov 2026)

- The launch title is FOUR OF WANDS (Curtis approved it on 19 Nov). The repo, class names and save folder keep
  "Magic Smash"; the rename lands with the new title screen.
- Steam setup is set aside until the game itself is Steam-worthy (Curtis, 19 Nov).
- The big push runs in three waves; `docs/push_brief.md` holds wave 1's contracts.
- Wave 1 is merged: one shared party level, level-ups that never pause (cards queue, E / LB opens a tray
  mid-fight, a 20 s lull after each Lich opens them), human-like test bots with a playtest report, and new art
  for the wizards, the enemies, the Act I floor and the title screen.
- Art bar (Curtis, 20 Nov): finished art must hold up on a Steam store page beside shipped games. The lead's
  re-judgement: the logo, title backdrop and Act I floor hold up; the fight HUD, wizard readability, room
  lighting, lobby cards and menu text do not yet (job R in `docs/wave2_brief.md`, before new content).
- Wave 2 (`docs/wave2_brief.md`, 21 Nov to 4 Dec): script split, core commit, polish job R, spell slots,
  the fallen and rituals, apprentices, Seals, fate deck, new enemies and act bosses (`docs/bestiary_design.md`),
  hub with NPC chats and full-height portraits, acts II and III art. Wave 3 (`docs/wave3_plan.md`, 5 to 15 Dec):
  10 spells, 8 wizards, endless mode, achievements, balance. After that: store art, Steam.

## Launch scope (targets)

- Wizards: 4 now, 8 at launch (4 to unlock), each with a starting spell and a trait.
- Spells: 6 now, 12 at launch, each with an evolution; 4 spell slots per wizard.
- Passives (Major Arcana): 8 now, 12 at launch; 4 slots per wizard. Enemies: 12, redrawn bigger, plus elites.
- Bosses: the Lich twice then the Archlich now; at launch a boss per act, the Archlich last.
- Difficulty: one now; at launch 8 Seals, stacking modifiers unlocked by winning.
- Stage: one tower, three acts. Between runs: unlocks, 12 cards, 8 secrets, achievements, wizards to unlock.
- Quality bars: readable (every wizard found within a second in a 4-player Lich fight: bigger sprites, outlines,
  colour floor rings, calmer floors); finished art everywhere a player looks, plain placeholders until then (the
  lead judges it from screenshots at 2x and merges it, Curtis 19 Nov); measured (the playtest tool with three bot
  personas sets the difficulty curve, `docs/bots.md`); stable (crash reports on, `docs/sentry.md`, check_all
  green).
- Not for launch: online lobbies, paid cosmetics, Android, web, a second stage, key rebinding.
- Risk to the date: Steam wants the app fee 30 days before release and the store page live 2 weeks before. If the
  fee was not paid by 18 Nov, 18 Dec moves by as many days.

## Decisions already made (by Curtis, 19 Nov 2026)

- **Genre:** a co-op survivors-like (auto-ish fighting, level-up picks, growing hordes, short runs) built on Magic
  Smash's wizards, spells, enemies, Lich boss, art and music. Curtis: make the design calls yourself; spend the week
  on scope, playability, art and better bots; competitors use the same tools, so stand out. A new title is allowed.
- **Price:** cheap and paid, $4.99 to $6.99. **No demo.**
- **Friends:** Steam Remote Play Together at launch, so friends without the game join free. Full online lobbies
  (GodotSteam on the host-authoritative `Net`) are a stretch goal.
- **Platform:** desktop, Steam first. No web build.
- **Launch:** Friday 18 Dec 2026. The app fee is due 30 days before and the store page live 2 weeks before.
- **Collectibles and gambling are wanted:** gacha-style collection, ultra-rare armors, consumables, loot boxes and
  gambling moments, under the rules below.
- **Title:** FOUR OF WANDS is the tarot card of four staffs raised before a castle: four wizards, their home, a
  celebration. A web search found no game of that name; Steam's own search is unreachable from the cloud box, so
  Curtis checks it there.
- **Still open:** when the paid cosmetic box shop goes in (recommended: a January update, not launch); the
  "screaming moment" for 4 friends (proposed: the team gamble shrine).

## Loot and gambling rules (from the CursedPawn gacha / lawsuit research)

Research doc: https://claude.ai/artifact/HeWHGkv8j31YYkXppPvAsR

1. **Everything that changes a run is earned in play, never bought.** Stat armor, consumables and run gold drop or
   come from in-run chests and shrines.
2. **Paid boxes are cosmetic only** (robes, staff skins, spell colours, nova effects): account-locked, with no
   trading, no Steam Market and no cash-out; real-money prices with the odds shown and tested; off in Belgium;
   gated for under-16s; every purchase confirmed; accounts never locked over refunds.
3. **In-run gambling uses run currency only.** Chests open with a slot-style reveal. Shrines take run gold.
   **Team gamble shrine:** one player bets for the whole party (double the party's level-up or curse everyone) and
   everybody watches the reel. That is the clip moment.
4. **Rarity tiers** (common, rare, epic, legendary, ultra-rare) show by colour and sound, readable in 3 seconds
   with the sound off.

## Rework plan, in order

Each step lands with tests and keeps `tools/check_all.sh` green. Logic goes in `game/logic/` as pure classes;
numbers go in `Tuning` or data tables. Notes per step are in `docs/systems.md`.

1. **Fill `Tuning`** with the numbers the rework turns: player speed, cast rates, spawn budget, wave HP scaling,
   XP curve. Replace the template's `gravity` and `move_speed` rows and update `test_tuning.gd`. (Done.)
2. **XP and level-ups.** (Done.) XP gems; a pick of 1 of 3 upgrades per level-up in `game/logic/upgrades.gd` with
   a seeded roll; the bot has a pick policy.
3. **Spell stacking and evolution.** (Done.) Five spells (arcane, fire, frost, storm, star) as levelled auto-cast
   weapons, with evolutions at max level plus a pairing.
4. **Continuous horde.** (Done.) A timer-driven spawn budget that ramps, elites and the Lich as minute bosses, a
   higher enemy cap, and a sim holding frame cost under budget (`tests/sim/sim_waves.gd` reports `us_per_step`).
5. **Loot layer.** (Done.) Chests, gamble shrines, consumables and rarity armor, meta unlocks between runs; saves
   go through one module that never writes when `Flags.is_scripted_run()`.
6. **Run structure.** A 15 to 20 minute run, a final boss, a results screen with the team's best moments, and a
   character select with the four wizard colours. (Done, per its notes.)
7. **Steam.** GodotSteam (achievements, Remote Play Together), the store page and the capsule art; then online
   lobbies if there is time. 7a (`Achievements`, `Platform` no-op) and 7b (`tools/capsules.gd`) exist; see
   `docs/steam.md`. Ask Curtis before any store action, payment or upload.
8. **Paid cosmetic boxes**, only after the open decision above, following the loot rules.

## Checks and tools

- `tools/check_all.sh`: unit, sims, lint and 3 bot shards in about 80 s. CI (`.github/workflows/checks.yml`) runs
  unit, lint, sims and bot-0..2 on every push and PR. `tools/map.sh` maps every script; `tools/outline.sh <file>`
  maps one.
- Watch it play: `xvfb-run -a godot --path . -- --autotest --out=/tmp/shots` (`--autotest=5` starts at the Lich,
  `--autotest=15` at the Archlich).
- Music: `tools/music`; SFX: `tools/gen_audio.py`. A whole bot run: `godot --headless --path . -s tools/full_run.gd -- --wizards=4 --seed=7` (about 3 minutes; add
  `--tune=f:v`).

## Known gaps

- The kit's frame stamp and render toggles are sized for a 1080p 3D game, so they are not in the 480x270 main
  scene. Scale them down before use.
- Most of `arena.gd`, `title.gd` and `net.gd` are untyped (only `game/logic` is strict in spirit); lint passes
  because its rules are narrow. Type things as you touch them.

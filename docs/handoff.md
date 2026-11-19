# Handoff: Magic Smash → co-op survivors-like

Written 19 Nov 2026, when the project moved onto the game starter kit. Read this first, then `CLAUDE.md` and
`docs/lessons_learned.md`.

## Where things stand

- Ported from Godot 4.3 to **4.7.2** with the starter kit's tooling (unit tests, lint, sims, play-bot, CI matrix,
  cloud session hook). The game plays the same as v0.2.0.
- `tools/check_all.sh` is green: 23 unit tests, 3 sims, 3 bot shards, lint 0.
- What changed in the port:
  - Scripts moved from `scripts/` + `scenes/` to `game/<system>/`.
  - `World` now takes a seed: `World.new(slots, seed)`, where 0 means random. The `--seed=N` flag reaches it.
  - `World` has a `state_hash()` for determinism checks.
  - The arena's demo bot became `game/logic/smash_bot.gd` (`SmashBot`). The arena, the sims and the bot scene
    all share it.
  - Cosmetic randomness (particles, shake, sound pitch) uses a local `_fx_rng`. Gameplay randomness is only
    `World.rng`.
  - The desktop renderer changed from Mobile to Compatibility, the kit standard. It looks the same: the
    xvfb screenshots match `docs/screenshots`.
  - High scores are not saved during bot, test or capture runs (`Flags.is_scripted_run()`).
- Measured: the 4-player sim peaks at about 60 enemies and costs about 130 µs per `World.step` on the cloud box.
  A survivors horde of several hundred enemies needs the spatial grid (`World._build_grid` / `_query`, already
  there) and batched drawing (MultiMesh or one `_draw` per enemy type) in `game/arena/arena.gd`.

## Decisions already made (by Curtis, 19 Nov 2026)

- **Genre:** a co-op survivors-like (auto-ish fighting, level-up picks, growing hordes, short runs) built on
  Magic Smash's wizards, spells, enemies, Lich boss, art and music.
- **Price:** cheap and paid, $4.99 to $6.99. **No demo.**
- **Friends:** Steam Remote Play Together at launch, so friends without the game can join for free. Full online
  lobbies (GodotSteam on top of the existing host-authoritative `Net`) are a stretch goal if time allows.
- **Platform:** desktop (Steam first). No web build.
- **Launch:** Friday 18 Dec 2026. The Steam app fee must be paid at least 30 days before release, and the store
  page must be live 2 weeks before.
- **Collectibles and gambling are wanted:** gacha-style collection, ultra-rare armors, consumables, loot boxes and
  gambling moments. Follow the rules in the next section.
- **Still open:**
  - When the paid cosmetic box shop goes in. The recommendation is a January update, not launch.
  - The "screaming moment" for 4 friends. The proposal is the team gamble shrine, described below.

## Loot and gambling rules (from the CursedPawn gacha / lawsuit research)

Research doc: https://claude.ai/artifact/HeWHGkv8j31YYkXppPvAsR

1. **Everything that changes a run is earned in play, never bought.** Stat armor, consumables and run gold all
   drop or come from in-run chests and shrines.
2. **Paid boxes are cosmetic only** (robes, staff skins, spell colours, nova effects).
   - Account-locked, with no trading, no Steam Market and no cash-out.
   - Sold for real-money prices, with the odds shown and tested.
   - Off in Belgium.
   - Gated for under-16s.
   - Every purchase confirmed, and accounts are never locked over refunds.
3. **In-run gambling uses run currency only.**
   - Chests open with a slot-style reveal.
   - Shrines take run gold.
   - **Team gamble shrine:** one player bets for the whole party (double the party's level-up or curse
     everyone), and everybody watches the reel. That is the clip moment.
4. **Rarity tiers** (common → rare → epic → legendary → ultra-rare) are shown by colour and sound, readable
   in 3 seconds with the sound off.

## Rework plan, in order

Each step lands with tests and keeps `tools/check_all.sh` green. Logic goes in `game/logic/` as pure classes,
and numbers go in `Tuning` or data tables.

1. **Fill `Tuning`** with the numbers the rework will turn: player speed, cast rates, spawn budget, wave HP
   scaling and XP curve. Replace the template's `gravity` and `move_speed` rows and update `test_tuning.gd`.
2. **(Done, see below.) XP and level-up picks.** Enemies drop XP gems. A level-up pauses for a pick of 1 of 3 upgrades, each player
   picking for themselves. Put it in a new `game/logic/upgrades.gd` with a seeded roll, and give the bot a pick
   policy so sims keep running.
3. **(Done, see below.) Spell stacking and evolution.** Turn the five spells (arcane, fire, frost, storm, star) into levelled
   weapons that auto-cast, with evolutions at max level plus a pairing, for example fire + storm.
4. **Continuous horde.** Replace wave clears with a timer-driven spawn budget that ramps up, with elites and
   the Lich as minute bosses. Raise the enemy cap. Add a sim that holds frame cost under budget at peak
   (`tests/sim/sim_waves.gd` already reports `us_per_step`).
5. **Loot layer.** In-run chests, the gamble shrines, consumables and armor drops with rarity, plus meta
   unlocks between runs. Saves go through one save module that never writes when `Flags.is_scripted_run()`.
6. **Run structure.** A 15 to 20 minute run, a final boss, a results screen with the team's best moments, and a
   character select with the four wizard colours.
7. **Steam.** GodotSteam (achievements, Remote Play Together), the store page and the capsule art. After that,
   online lobbies if there is time.
8. **Paid cosmetic boxes**, only after the decision above, following the rules in the previous section.

## Step 2 notes (XP and level-ups)

- Every kill drops an XP shard (`World.PK_XP`, value from `World.XP_VALUES`). Shards near a wizard fly to them
  (`Tuning.xp_magnet_*`); the wizard who collects a shard gets its XP. Levels need `Tuning.xp_to_next(level)`.
- A level-up opens an offer of `Tuning.level_choices` upgrades from `game/logic/upgrades.gd` (seeded by
  `World.rng`). The whole world waits while any player has an offer open; each player picks their own card.
  A pick is input fields 6 and 7, [card, offer id], so a held or late pick never applies to the next offer.
- Bots pick by `SmashBot.PICK_PRIORITY`. In the arena (autotest, bot shards) they wait `BOT_PICK_THINK` so the
  pick screen shows; `--autotest` saves `levelup.png` the first time it does.
- Open question for Curtis: XP goes to whoever picks the shard up. Shared party XP (everyone levels together)
  is kinder to a mixed-skill Remote Play group; it is a small change in `World._collect`.

## Step 3 notes (spell weapons and evolutions)

- Every wizard starts with Arcane Bolt level 1. All owned spells cast on their own cooldowns, along the aim
  stick when it is held, otherwise at the nearest enemy within `Tuning.auto_aim_range`. The fire button no
  longer does anything; the nova button still does.
- Stats per level and the evolutions are data in `game/logic/spells.gd`. Weapon levels and evolutions are
  entries in the `Upgrades` catalogue (`weapon_entry`, `evo_entry`); an evolution is offered once its weapon is
  level 5 and its partner is owned. Pairs: Astral Lance (arcane + star, piercing), Thunderfire (fire + storm,
  blasts fork lightning), Blizzard (frost + arcane), Tempest (storm + fire, twin chains), Comet Rain (star +
  frost, ice bursts). `Tuning.spell_cd_mul` scales every cooldown.
- Tomes now grant or level their spell weapon (points once it is maxed) and weapons are kept through death.
  Snapshots carry the 5 weapon levels (6 = evolved) and shot kinds are +5 when evolved; the HUD shows a pip per
  weapon.
- Seen in a 2-player bot probe (seeds 11 and 12): first evolutions around minute 3 to 4, most weapons evolved by
  minute 8, and the bots never lost a life by wave 27. Tomes level weapons fast, so balance belongs to step 4,
  where the horde ramps.

## Checks and tools

- `tools/check_all.sh`: unit, sims, lint and 3 bot shards in about 15 s.
- Watch it play: `xvfb-run -a godot --path . -- --autotest --out=/tmp/shots` saves screenshots every few seconds.
  Use `--autotest=5` to start at the boss wave.
- CI (`.github/workflows/checks.yml`) runs unit, lint, sims and bot-0..2 on every push and PR.
- Music: `tools/music` renders the soundtrack (see `tools/music/SOUNDTRACK.md`). SFX come from
  `tools/gen_audio.py`.

## Known gaps

- The kit's frame stamp and render toggles are sized for a 1080p 3D game, so they are not added to the 480x270
  main scene. Scale them down before using them.
- `Tuning` holds the rework's first numbers (step 1, done). The XP curve rows are in place but nothing uses them until step 2.
- Most of `arena.gd`, `title.gd` and `net.gd` are untyped (only `game/logic` is strict in spirit). Lint passes
  because its rules are narrow. Type things as you touch them.
- `README.md` still says Godot 4.3 and describes v0.2.0 play; update it once the survivors loop exists.

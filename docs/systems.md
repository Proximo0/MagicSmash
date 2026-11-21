# How each system works

How each system works: read only the section for the system you touch (`grep -n '^## ' docs/systems.md`).

## Port to Godot 4.7.2 (what changed, 19 Nov)

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
  there) and batched drawing. Both are in now; see `docs/performance.md`, "This project's numbers".

## XP and level-ups (rework step 2)

- Every kill drops an XP shard (`World.PK_XP`, value from `World.XP_VALUES`). Shards near a wizard fly to them
  (`Tuning.xp_magnet_*`); the wizard who collects a shard gets its XP. Levels need `Tuning.xp_to_next(level)`.
- XP is shared: one party level (`World.party_level`, `party_xp`, `xp_needed()`); a level-up queues one draw for
  every wizard. The world never waits: a wizard's draws show as a tab under their HUD column and a marker over
  their head; E / LB / LT opens the tray, 1 2 3 / X Y B takes a card (input fields 6 and 7, [card, offer id]),
  and taking a card pushes nearby enemies back. After a Lich (not the Archlich) falls, a 20 s lull
  (`World.lull_left`, `EV_LULL`) stops spawns and opens the trays.
- Bots take their cards at once (`SmashBot.PICK_PRIORITY`); `--autotest` saves `levelup.png`, `tab.png`,
  `tray.png`, `lull.png`, `lull_end.png`.

## Spell weapons and evolutions (rework step 3)

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

## Continuous horde (rework step 4)

- No more wave clears. After a 2.5 s intro the run clock (`World.wave_time`) runs until game over, and
  `World.wave` is now the minute of the run (1 from 0:00). The HUD shows the clock; each new minute gets a
  short banner.
- The horde earns spawn budget every second, `(horde_rate_base + horde_rate_per_min x minutes) x party scale`,
  and spends it on groups rolled from `World.HORDE` (type, cost, unlock time, weight, group size). It holds at
  `Tuning.enemy_cap` (260) and slows to `horde_boss_mul` while the Lich is up.
- An elite every `elite_interval` s (a skeleton, then orcs and mages) has `elite_hp_mul` x HP, a gold aura and
  pays 5x score and XP plus gems and a tome. A boss arrives every `boss_every_min` minutes: THE BONE CHANDELIER
  at 5:00, THE GHOST WRITER at 10:00 (`Bosses.SCHEDULE`; any later visit is the Lich); killing one still clears
  the arena, starts the lull and resets the horde's budget. Each turns a phase at half health: the Chandelier's
  chain snaps (ALOFT to THE WHEEL), the Ghost Writer spells faster and adds GOODBYE (`docs/bestiary_design.md` 2, 6).
- XP gems past `Tuning.xp_gem_cap` merge into the nearest gem, so the floor stays readable and cheap.
- Cost: `tests/sim/sim_horde.gd` fills the arena to the cap with 4 wizards and asserts `World.step` stays under
  4 ms. It measured about 2.2 ms on the cloud box (crowd separation now reads the grid directly and runs for
  half the crowd per tick). Drawing was the next cost; the perf pass on 19 Nov cut a 12:00 frame from about
  1000 draw calls to about 250 (see `docs/performance.md`).
- Balance pass 1 (after step 4), measured with bot teams on seed 21:
  - The XP curve is now 20 + 60 per level, x1.04 per level (`Tuning.xp_*`): about level 6 at 1:00, 15 at
    5:00 and 25 at 12:00, so pick screens come about every 20 to 30 s instead of every few seconds.
  - Before, 4 bots killed about 200 enemies a second as they filed through the doors. Now 60% of groups open a
    rift: a marker shows for `rift_warning` s at least `rift_min_dist` px from every wizard, then the group bursts
    out in a clump. Doors stay for the rest, and a door group walks in `World.DOOR_STAGGER` apart.
  - `spawn_party_scale` is 1.1. Bots: 1 player loses a first life around 8:00, 2 players around 9:30, and 4 bots
    in their tidy formation still lose none by 12:00. Bots dodge better than they play as a team, so set the
    final pressure from human playtests; `sim_horde` reports the bot numbers on every check.
  - Each player levels and picks on their own, so 4 players pause the world about 4 times as often as 1. Shared
    party XP (one pick screen for everyone at once) would cut that to the solo rate; it is Curtis's call.
- Balance pass 2 (wave 2 job P, 21 Nov; `tools/playtest.gd`, part 3 of `docs/wave2_brief.md`). Every number is a
  `Tuning` default unless named otherwise:
  - The early wall was the start budget (10) and rate (10/s); the late cakewalk was drops and power that scale
    with the kill count (2.5% of kills dropped a spell tome, so every spell was maxed by 3:00) and evolutions worth
    3 to 10 times level 5. Now: `horde_start_budget` 0, `horde_rate_base` 2, `horde_rate_per_min` 7,
    `enemy_speed_mul` 0.85 with `enemy_speed_per_min` 0.05 (slow at 0:00, faster than before after 3:00),
    enemy HP `enemy_hp_mul` 1 x (1 + `enemy_hp_per_min` 0.1 x (minute - 1)) x `enemy_hp_growth` 1.14 ^ (minute - 1).
  - Drops (`Tuning` Loot rows, read by `WorldDrops`): `tome_drop_chance` 0.005 (was 0.025), `big_tome_chance`
    0.15 (0.25), `coin_drop_chance` 0.1 (0.22), `potion_drop_chance` 0.05 (0.02).
  - XP: `xp_per_level` 90 (60), `xp_gem_life` 90 s (30), `xp_magnet_radius` 44 (24).
  - Enemy shots: `enemy_shot_cd_mul` 2 (skeleton arrows and mage volleys), `arrow_speed` 120 (150),
    `mage_orb_speed` 85 (95). The pass first tried 5, 75 and 80: the bots' win rate did not move, and arrows
    slower than a wizard (102 px/s) are no threat to a person.
  - Bosses: `boss_hp_mul` 3.5, `boss_hp_per_cycle` 2.0 (0.25), `final_hp_mul` 3.6 (10, now on a Lich 5x by its
    third visit), `boss_rest_mul` 1.8 (seconds between the Lich's attacks).
  - Party: `spawn_party_scale` 0.4 (1.1), `enemy_hp_per_player` 0.12, `xp_party_scale` 0.8 (1.0),
    `boss_hp_per_player` 0.3 (0.6), `final_hp_per_player` -0.15.
  - Shrines: `shrine_interval` 25 s (60), `shrine_life` 50 s (30), `shrine_min_dist` 30 (50),
    `shrine_cost_base` 60 (15), `shrine_cost_per_min` 25 (6).
  - `Spells`: arcane bolt damage 2.2-3.0 (1.0-1.6), fireball 1.8-3.0 and 1/1/2/2/2 balls (2.0-3.8, 1/1/2/2/3),
    frost fan 2.0-3.5 (1.6-2.6), chain lightning 2.6-5.0 (2.6-4.0), starfall 2.8-4.2 (2.6-4.0); Astral Lance
    cd 0.11 (0.09) dmg 3.0 (2.2), Thunderfire cd 0.9 (0.75) dmg 3.0 (4.4), Blizzard dmg 3.2 (2.8), Comet Rain
    dmg 3.0 (2.6) 5 stars (6) and `BURST_DMG` 0.3 (0.5), Seal of Solomon dmg 1.0 (1.2).

## Loot, gamble shrines, meta unlocks and saves (rework step 5)

- 5a, chests and run gold:
  - Rarity tiers, chest items, armor stats and gold values are data in `game/logic/loot.gd` (`Loot`).
  - Tiers run from common to ultra rare at 60 / 26 / 10 / 3.4 / 0.6 weight. A chest's luck (elites 1, the
    Lich 3) moves common odds up the tiers.
  - Elites drop a chest. The Lich drops one per wizard.
  - Opening a chest is instant in the simulation. The arena plays a 1 s reel over the wizard, then shows the
    item in its tier colour, with sound and bursts that grow by tier.
  - Armor stacks for the run, up to `Loot.STAT_CAPS`: might, focus, swift, vigor (max hearts), ward (block
    chance), greed (more gold). Consumables work at once: elixir, nova flask, ancient tome, insight.
  - Coins and gems give run gold (`Player.gold`) as well as score. Gold is per wizard and only lives inside a
    run; shrines (5b) spend it.
  - `--autotest --tune=elite_interval:8` saves `chest.png` at the first reel.
- 5b, gamble shrines (tables in `game/logic/gamble.gd`, `Gamble`; timers and costs in `Tuning`, Shrines group):
  - A solo shrine appears every `shrine_interval` s, from 0:40, away from the wizards, and fades after
    `shrine_life`. Its price grows each minute.
  - To bet, a wizard who can pay stands on a shrine for `shrine_hold` s while a ring fills. The gold goes at
    once, a reel spins over the shrine, and the outcome lands when it stops: jackpot chest, chest, double gold
    back, nothing, or a curse (lose a heart, never the last).
  - The team shrine (the clip moment) appears every `team_shrine_interval` s, from 2:00, with a banner. It costs
    `team_cost_mul` x a solo shrine, and one wizard pays it all. A 3 s reel spins in the middle of the screen
    for everyone, with boss music. It lands on a coin flip:
    - Blessed: every wizard gains 2 levels.
    - Cursed: every wizard loses a heart (never the last), and an elite comes for each of them.
  - Bots walk to shrines they can afford (`SmashBot.shrine_goal`); `sim_waves` checks they bet.
  - `--autotest --tune=team_shrine_first:12,shrine_cost_base:2,shrine_cost_per_min:0` saves `team_shrine.png`.
- 5c, meta unlocks and saves:
  - `game/logic/profile.gd` (`Profile`) holds the best score, crystals and the unlock catalogue (`META`, costs
    per level, `EFFECTS`).
  - A run pays 1 crystal per 30 s survived, 1 per 250 kills and 10 per Lich. Crystals are earned in play and
    never sold.
  - The title menu's UNLOCKS screen spends crystals: hearts, damage, XP, gold, novas, chest luck.
  - In co-op the host's unlocks apply to every wizard (`World.apply_meta`), so Remote Play guests get the same
    head start.
  - `game/autoload/save.gd` (`Save`) is the only module that reads or writes player data (`user://profile.json`;
    the old `save.cfg` high score is carried over once). `Save.write()` refuses in scripted runs, and scripted
    runs start with no unlocks so bots and sims do not depend on the machine.
  - The game over screen shows the crystals earned.
- Step 5 is done.

## Run structure: Archlich, results, wizard select (rework step 6)

- 6a, the final boss (`Tuning` Run group):
  - At `run_minutes` (15:00) the Archlich comes: a Lich with `Bosses.FINAL_HP` (5) x `final_hp_mul` (3.6) x the
    HP and a bigger body. Three phases: LICH LORD (the calm set) to 75%; THE ASCENSION (3 s, the field clears,
    wizards heal 2) and ASCENDANT (the enraged set, an elite with every summon, COMETFALL every third attack) to
    35%; THE NINTH PAGE (2.5 s turn) adds a NAME every fourth attack and LAST CANDLE every 30 s. A boss of another
    kind still standing at 15:00 leaves; a Lich ascends. No boss comes after it; the horde keeps the boss rate.
  - Slaying it wins the run (`World.won`, `EV_VICTORY`): the clock and the horde stop, everyone is safe, and
    after `victory_delay` s the results screen says VICTORY. A win pays `Profile.CRYSTAL_WIN` (25) crystals
    and counts in `Profile.wins`. The Archlich pays 4x the Lich's score.
  - `tools/full_run.gd` plays a whole run with bots and prints a line per minute. Seed 11, final_hp_mul 12:
    1, 2 and 4 bots won at 16:43, 17:38 and 16:42 (fights of 100 to 156 s); 10 leaves room for human play.
  - `--autotest=15` saves `archlich.png` once the Archlich is up. A victory saves `victory.png`.
- 6b, the results screen (`game/logic/results.gd`, `Results`):
  - `World.record` notes each wizard's damage, kills, elites, best combo, chests and best tier, gold, gold bet
    and deaths, and the run's moments: Liches and the Archlich slain, legendary and ultra chests, team blessings
    and curses, jackpots, x100/x200/x400 combos and evolutions.
  - At the end, `EV_RESULTS` carries `record.to_dict()` to every client, just before `EV_GAMEOVER`.
  - The screen shows a column per wizard with an award, then the 4 best moments with their times. An award goes
    only to a wizard who really leads its stat (MVP, SLAYER, HIGH ROLLER, LUCKY, GOLD DIGGER, UNTOUCHABLE); in a
    party anyone left without one is a TEAM PLAYER.
  - `--autotest --end=45` ends the run at 45 s and saves `results.png`; `--end=45:win` shows it as a victory.
- 6c, wizard select (`game/logic/wizards.gd`, `Wizards`):
  - In the lobby each player steps left or right through the four wizards with their own keyboard or pad. Two
    players can't pick the same one. Each wizard is one robe colour and starts with its own spell: Violet
    Arcanist (arcane bolt), Crimson Pyromancer (fireball), Emerald Frostwarden (frost fan), Amber Stormcaller
    (chain lightning). Star is the spell nobody starts with.
  - The roster carries `wizard`; the host passes `Net.wizard_picks()` to `World.new`. Snapshots send the wizard
    at player index 10, and `G.wizard_of(slot)` colours everything a slot draws (robe, HUD, spell fx).
  - A slot with no pick (tests, sims, the bot) plays the wizard of its own colour, so 4-bot runs cover all four.
  - `--autotest --wizard=2` steps the first player two wizards right before the run.
- Step 6 is done.

## Steam (rework step 7)

- See `docs/steam.md`: what the code does with Steam and the Steamworks checklist for Curtis.
- 7a: the achievements (`Achievements`) and the `Platform` autoload, a no-op until GodotSteam and an App ID are
  in. Asked Curtis on 19 Nov for the App ID and whether the app fee is paid (it was due 18 Nov for 18 Dec).
- 7b: `tools/capsules.gd` draws draft store and library capsules (see `docs/steam.md`).
- Ask Curtis before any store action, payment or upload.

## Polish rounds: menus, tarot, story, acts, horde, sound (19 Nov)

Curtis set Steam aside and gave creative control: occult accents and menus, a ouija board for typed text, tarot,
runes and magic books, fantasy mixed with history and myth, and no placeholder text or UI. What went in (PRs
#16 to #24 and the spell PR):

- **Menus:** `Occult` (`game/ui/occult.gd`) draws the frames, runes, pentagrams, candles and the menu cursor.
  `OptionsPanel` + `Settings` (music, sound, window, screen shake; saved in `user://settings.json` by `Save`).
  Typed text (names, LAN addresses) goes through the ouija board (`Ouija` logic, drawn in `title.gd`). The lobby's
  empty seats show the wizard's shadow between candles.
- **Tarot level-ups:** `TarotArt` draws the cards (16x16 ASCII emblems); passives are Major Arcana
  (`Upgrades`), spells are grimoires.
- **Story:** `Lore` holds the prologue (THE TALE on the title, shown once before the first PLAY), the three acts
  (I The Ossuary, II The Burning Library from 5:00, III The Starless Sanctum from 10:00), a line per minute,
  Morvane's names, omens, elite epithets and the endings. World waves count from 1; Lore minutes from 0.
- **Acts:** `ArenaBg.build(act)` bakes each act's floor and walls (the painters are `game/art/arena_art_*.gd`) and
  `ArenaBg.scene(act)` lists what the arena draws live over it (flames, light pools, doors, the seal). The arena
  crossfades both and changes the music (`music_battle`, `music_library`, `music_sanctum`) and ambient particles.
  The Ossuary is finished art; the Library and the Sanctum share its base and get their full pass in wave 2.
- **Gambling dressed up:** solo shrines are rune altars (three rune stones), the team shrine is the fate card
  (The Sun or Death).
- **Horde:** wraith (phases out, spells pass through), cursed tome (circles, dashes), bone priest (raises
  skeletons), gargoyle (stone takes 25% damage, swoops). Omens (`World.OMENS`) at 3:00, 8:00 and 13:00.
- **Names:** mythic loot (Gauntlets of Tyr, Hermes' Sandals, Eye of Odin...) and unlocks; achievement texts
  match. Version 0.9.0.
- **Sound:** 14 occult SFX (`card_deal`, `rune_cast`, `bell_toll`, `ghost`...) from `tools/gen_audio.py`.

## Talk (hub and run chats)
- `game/logic/talk.gd` (`Talk`): the lines as data (`LINES`: speaker, condition, text) for the SHOPKEEPER, the CARD
  READER and MORVANE. `Talk.pick(speaker, context, rng)` returns `{id, name, portrait, text, rows}`; the context has
  `first`, `new_card`, `result` (loss or win), `act`, `seal`, `apprentice`, `lull`, `last`. `first` and `new_card`
  speak alone, a lull gets an act line, otherwise result, act, Seal and apprentice lines pool with `idle`. The line
  shown last (`last`) is skipped whenever another fits. Text is at most 2 rows of `Talk.TEXT_COLS` characters
  (`test_talk` measures them); portraits are the owner's `portraits/characters` keys (`_tall` in the box).
- `game/ui/dialogue_box.gd` (`DialogueBox`): portrait panel on the left, text box along the bottom, typed text,
  confirm completes then closes. A missing picture is a dark silhouette with the name.
- Sanctum: `Sanctum.SHOPKEEPER` (118,176) and `Sanctum.CARD_READER` (362,176) are things like the rest (walk up,
  confirm). The shopkeeper's box then opens the title's UNLOCKS (`G.title_shop`; back returns to the Sanctum). After
  a run (`G.last_run`, set by `G.finish_run`) Morvane speaks once on arrival. "First" and the apprentice line are
  remembered per session (`G.talk_seen`), a first visit is `Profile.runs == 0`.
- Run: `ArenaTalk.start` (called at EV_LULL; the World emits no EV_TALK) shows Morvane's line for the act in a small
  box at the top for 6 s. It takes no input. Shots: `--autotest --talk`, `--autotest --talk-lull`.

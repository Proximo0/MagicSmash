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
- One shared screen, every wizard in sight (`ArenaDrawWorld.wanted_camera`, `eased_camera`, `leash_room`;
  `ArenaHud.edge_arrows`; `ArenaTrayArt.tray_hides_wizard`, `hand_hides_wizard`): the camera frames every living human,
  standing or fallen (apprentices only when no human lives), centred, shifted just enough to keep each body
  (`WIZARD_BOX`) 2 px inside the play window, and held there while it eases, so a running party never outruns it. The
  leash (`leash_x/y`) may not exceed `leash_room()` (448 x 203). A living wizard not wholly in the window gets one
  steady edge arrow (`P<n>`, apprentice `A<n>`) that blinks after her call. The four trays and tabs (`TRAY_X`, 120
  apart) never share a pixel; a tray whose rect a living wizard's body touches fades to `TRAY_GLASS` over `TRAY_FADE` s
  (a layer of its own per seat, hidden while the game is paused or over); the painted hand under a tray is not drawn
  where it would cover any wizard.
- The shop's run options reach every wizard on the run's first step (`World.apply_meta`, `WorldLevels._shop_start`):
  `Upgrades.REDRAWS` and `BANISHES` plus the bought THE SECOND GLANCE and THE BLACK RIBBON, and THE HEAD START's
  `start_level` N: the party starts at level 1 + N (no XP, no stats) and keeps that lead all run, because
  `World.xp_needed` never prices those N levels (`World.head_start_levels`); every wizard has N hands to draw, and a
  local seat's tray opens by itself as in a lull (`ArenaViewSync`). While one
  is undrawn the intro holds (`WorldLevels._intro_held`: no horde, no clock) for at most `Tuning.head_start_wait`
  seconds; a fallen, away or departed wizard holds nothing, and whoever has not drawn keeps her draws.
- Bots take their cards at once (`SmashBot.PICK_PRIORITY`); `--autotest` saves `levelup.png`, `tab.png`,
  `tray.png`, `lull.png`, `lull_end.png`.

## Spell weapons and evolutions (rework step 3)

- Every wizard starts with Arcane Bolt level 1. All owned spells cast on their own cooldowns, along the aim
  stick when it is held, otherwise at the nearest enemy within `Tuning.auto_aim_range`. The fire button no
  longer does anything; the nova button still does.
- Stats per level and the evolutions are data in `game/logic/spells.gd`. Weapon levels and evolutions are
  entries in the `Upgrades` catalogue (`weapon_entry`, `evo_entry`); an evolution is offered once its weapon is
  level 5 and she holds its arcana at level 1 (a PASSIVE row, never another spell; since stage 3, see "The
  catalog's stage 3 rows" below). `Tuning.spell_cd_mul` scales every cooldown.
- Tomes now grant or level their spell weapon (points once it is maxed) and weapons are kept through death.
  Snapshots carry the 5 weapon levels (6 = evolved) and shot kinds are +5 when evolved; the HUD shows a pip per
  weapon.
- Seen in a 2-player bot probe (seeds 11 and 12): first evolutions around minute 3 to 4, most weapons evolved by
  minute 8, and the bots never lost a life by wave 27. Tomes level weapons fast, so balance belongs to step 4,
  where the horde ramps.

## Continuous horde (rework step 4)

- No more wave clears. After a 2.5 s intro (held longer while THE HEAD START's hands are drawn:
  `WorldLevels._intro_held`, at most `Tuning.head_start_wait`) the run clock (`World.wave_time`) runs until game over, and
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
  Every boss comes at its minute whatever the party did: one still up when the next row falls due leaves
  (`Bosses._leave`: no bounty, no deed, no lull; `WorldWaves._tick_minute`), so a slow party meets the Ghost Writer
  at 10:02 and the run keeps its 15-minute shape. The Lich's summons stop at `World.enemy_cap()` like the priest's.
- Eight more kinds join from 1:30 (`docs/bestiary_design.md` 1, 6 "Job K as built"): the BLOAT, RESTLESS COFFIN
  and TOMB GUARD (act I), CINDERLING, THE CENSOR and ASH HOUND (act II), COMET SHARD and TEN OF SWORDS (act III).
  Their brains live in `game/logic/kinds_*.gd` (named by `Bestiary.BRAINS`), most of their danger is hazard rows,
  and three formations (POWDER TRAIN, SHIELD WALL, FIRE DRILL) come one roll in five once unlocked.
  `Tuning.new_kinds` scales their weights; 0 plays the old horde exactly.
- XP gems past `Tuning.xp_gem_cap` merge into the nearest gem, so the floor stays readable and cheap.
- Cost: `tests/sim/sim_horde.gd` fills the arena to the cap with 4 wizards and asserts `World.step` stays under
  4 ms. It times the peak in three windows and takes the cheapest (noise only adds); `tools/step_profile.gd`
  times each phase of the step for a loadout (`docs/performance.md`, pass 3). It measured about 2.2 ms on the cloud box (crowd separation now reads the grid directly and runs for
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
    enemy HP `enemy_hp_mul` 0.70 x (1 + `enemy_hp_per_min` 0 x (minute - 1)) x `enemy_hp_growth` 1.20 ^ (minute - 1).
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
  - A chest rolls common to legendary at 60 / 26 / 10 / 0.3 weight (`Loot.RARITY_WEIGHTS`; was 60 / 26 / 10 / 3.4
    / 0.6 with ULTRA): about 1 solo run in 6 opens a legendary. A chest's luck (elites 1, the Lich 3) moves common
    odds up the tiers.
  - A chest's item is `Loot.roll_item(rng, tier)`, one draw by weight. Items whose effect does not grow with the
    tier are marked flat in `Loot.ITEMS` (the ELIXIR, which heals to full at any tier) and have no weight at
    `Loot.LEGENDARY` or above, so a LEGENDARY or ULTRA RARE chest is never a dud; below LEGENDARY every seed rolls the
    item it always did.
  - ULTRA RARE and monster cards are a property of the run, not of each kill (job U): `Loot.run_rolls` draws once
    in `World._init` from the run's own stream (`Loot.run_stream`, the run's seed xor `Loot.RUN_SALT`; `w.rng` never
    feeds it). An ULTRA RARE run (`ultra_run_chance` 0.01, + `ultra_run_luck` per point of meta and Seal luck, at
    most `ultra_run_cap` 0.03; none under APPRENTICE) drops one prismatic chest (`PK_CHEST_ULTRA`, opens ULTRA RARE)
    from the first plain kill after its moment (`WorldDrops.ultra_due`); no other chest opens ULTRA RARE. A card run
    (`card_run_chance` 0.01 x `seal_cards`) drops exactly one card. Its kind is rolled at the start (`run_rolls`
    "card_kind", drawn last so every older key keeps its value): `WorldDrops.run_card` picks uniformly from
    `run_card_choices`, every monster card whose kind the run's horde spawns before the Archlich (a `Bestiary.HORDE`
    row unlocked by then, or a kind in `WorldDrops.SPAWNED_FROM`: the DROPLET with its slime) plus the final boss's
    card (the Seal's card under a Seal, THE LICH otherwise). It drops from the first kill of that kind at or after
    its moment (`Cards.run_card` maps a kill to the card it stands for; the Archlich's kill for its card), or, for
    `card_run_urn` 0.15 of card runs, waits in the first urn broken at or after it (the urn_card secret), with the
    same kind. `World.apply_meta`'s "urn_card" (bool) makes the run such an urn card run: `Profile.bonuses()` sends
    it while the lifetime urn count (`Profile.urns`, each run's `World.urns_broken`, `run_so_far` "urns", booked by
    `finish_run`) is at least `Profile.URN_CARD_AFTER` 120 and the urn_card secret is unfound, so ALL_SECRETS can be
    earned; a run that breaks no urn after the moment leaves the secret for the next run. Each kill still takes its
    one `w.rng` draw in `_roll_card`. Moments fall between `loot_moment_from` 0.1 and `loot_moment_to` 0.4 of the run
    up to the Archlich. Out of a card run no kill, urn or boss drops a card; a first win at a Seal still pays its
    card (`Profile.finish_run`). The Sanctum: a pot holds a card at `Sanctum.POT_CARD` 0.001, a sealed deck costs
    `Sanctum.DECK_COST` 1500 crystals and draws only monster cards the player lacks while any remain
    (`Sanctum.roll_card(r, Sanctum.owned_cards(prof))`; plain weights once she owns them all; pots never pass the
    list). THE LICH weighs `Sanctum.LICH_WEIGHT` 5 against `CARD_WEIGHT` 10 for each other monster card. THE FULL
    DECK (ALL_CARDS) counts monster cards only (`Cards.monster_count`, 12; the party's "monster_cards").
  - An away human (her seat `ai` and `away`) keeps her loot: `WorldApprentices.may_take` and `payee` treat her seat
    as a human's (`is_human_seat`) and THE EMPEROR pays every human seat (`human_seats`); `World.humans()` still
    leaves her out, and her damage and XP shares stay an apprentice's.
  - A card found in a fight shows as a small notice under the HUD for `Arena.CARD_SHOW` s ("CARD FOUND: NAME" and
    the card's painting at 16x24 when it has one; no shake), then as a "CARD FOUND" line with the results' deeds.
    `--autotest --tune=card_run_chance:1,loot_moment_from:0,loot_moment_to:0.01` saves `card.png` with the notice.
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
    `team_cost_mul` x a solo shrine, and the table pays it into one pot (`WorldShrines._fill_pot`):
    - The pot fills only while two living wizards stand in the shrine (one, when only one is left); an
      apprentice neither pays nor counts. The altar says `2 WIZARDS`, then `1 MORE`, and the pot waits, never
      drains, while too few stand in it.
    - The whole price takes `team_pay_time` s, in equal parts from the wizards standing there who have gold. One
      who runs dry pays what she has and the others cover the rest; a wizard with no gold still counts as the
      second. The ring shows pot / price.
    - A full pot bets for everybody, and the wizard who paid the most is the one who drew (a tie: the lowest
      slot). `bets` are booked then, each wizard her own share. A shrine that fades before its pot is full gives
      every wizard back exactly what she paid.
    - A 3 s reel spins in the middle of the screen for everyone, with boss music, and a fate is turned from the
      fate deck (`docs/content_list.md` § 10). A solo run's team shrine keeps the coin flip: every wizard gains
      2 levels, or loses a heart (never the last) with an elite coming for each.
  - The snapshot's shrine row is `World.SHRINE_FLOATS` wide: kind, x, y, life, charge fraction (a team shrine:
    pot / price), cost, wizards still needed.
  - Bots walk to shrines they can pay (`SmashBot.shrine_goal`: a solo shrine from her own gold, a team shrine
    when she has gold and the living wizards' gold together covers what the pot lacks). A bot that has stood in
    a team shrine for `SmashBot.SHRINE_PATIENCE` s without the pot growing gives it up, and takes it up again
    once a partner stands in it (`SmashBot.shrine_pick`). `sim_waves` checks they bet.
  - `--autotest --tune=team_shrine_first:12,shrine_cost_base:2,shrine_cost_per_min:0` saves `team_shrine.png`.
- 5c, meta unlocks and saves:
  - `game/logic/profile.gd` (`Profile`) holds the best score, crystals and the unlock catalogue (`META`, costs
    per level, `EFFECTS`).
  - A run pays 1 crystal per 30 s survived, 1 per 250 kills and 10 per Lich. Crystals are earned in play and
    never sold.
  - The title menu's UNLOCKS screen spends crystals on the rows of `Profile.shelf()` (the nine not on
    `Profile.UNBUILT`): hearts, damage, XP, gold, novas, chest luck, redraws, banishes, THE HEAD START.
  - In co-op the host's unlocks apply to every wizard (`World.apply_meta`), so Remote Play guests get the same
    head start.
  - `game/autoload/save.gd` (`Save`) is the only module that reads or writes player data (`user://profile.json`;
    the old `save.cfg` high score is carried over once). `Save.write()` refuses in scripted runs, and scripted
    runs start with no unlocks so bots and sims do not depend on the machine.
  - Socketed cards count once (job A1): `Profile.bonuses()` has no "armor"; a hero's sockets reach a run only
    through her own `World.apply_hero` (`Hero.stats`), so a +1 HEART card gives its hero +1 and other seats none.
    The career tool and the playtest's `--profile` seat the same way.
  - Damaged saves (job A1): a file that parses but holds a wrong type (a list, map or null where a number is read,
    a non-bool where a bool is read: `Profile.profile_types_ok`, `Settings.settings_types_ok`) makes `from_dict`
    return null, and `Save.read_converted` treats that like text that does not parse: kept aside as .bad, the
    .bak tried, else a fresh profile or the default settings.
  - Newer saves (job A1): a profile whose "version" is above `Profile.VERSION` loads as well as it can and is
    marked `Profile.newer` (not saved); `Save.write_profile` (every profile write: `write`, `finish_run`,
    `add_card`) then returns false without touching the disk, and `Save.newer_save()` is true for the title.
  - The balance tools (career, playtest) cap runs at 25 minutes of run clock; a run that reaches the cap is
    counted UNFINISHED (its own count in the summary line), never a loss.
  - The game over screen shows the crystals earned.
- Step 5 is done.

## Run structure: Archlich, results, wizard select (rework step 6)

- 6a, the final boss (`Tuning` Run group):
  - At `run_minutes` (15:00) the Archlich comes: a Lich with `Bosses.FINAL_HP` (5) x `final_hp_mul` (3.6) x the
    HP and a bigger body. Three phases: LICH LORD (the calm set) to 75%; THE ASCENSION (3 s, the field clears,
    wizards heal 2) and ASCENDANT (the enraged set, an elite with every summon, COMETFALL every third attack) to
    35%; THE NINTH PAGE (2.5 s turn) adds a NAME every fourth attack and LAST CANDLE every 30 s. A boss of another
    kind still standing at 15:00 leaves; a Lich ascends. No boss comes after it; the horde keeps the boss rate.
    The Lich and the Archlich drift between waypoints taken from the party's middle (`BossLich.DRIFT_*`: 140 px
    to a side, 60 to 100 px above, below it at the top wall). They choose an attack only inside the screen the
    party sees and stride three times as fast while outside it (`SIGHT_INSET`, `SIGHT_HASTE`), so a party low in
    the room is not shot from the top door. The teleport lands 80 px from the party's middle, across it from the
    wizard followed (`TELE_KEEP`, `_lich_landing`).
  - Slaying it wins the run (`World.won`, `EV_VICTORY`; it drops only its gems and coins, no chest, potion or
    tome; a curse (team or solo) or THE EMPEROR landing in the countdown does nothing, other fates land; once the phase is game
    over nothing on the floor is picked up or broken): the clock and the horde stop, everyone is safe, and
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
  - **Booking a run** has one path, `ArenaEvents.book_run_once` (once: `Arena.run_booked`): the `EV_GAMEOVER`
    handler, QUIT TO TITLE's YES and `NOTIFICATION_WM_CLOSE_REQUEST` (`Arena._book_run_now`, host/offline only:
    `World.run_so_far()` is the record and totals `_end_run` would report now, read-only). In the victory
    countdown it books the win. A LAN client's mid-run quit books nothing. Tests: `test_run_booking`.
  - **Pause** opens from the keyboard or a pad holding a seat, not in the victory countdown (the automatic
    pauses still do). Paused, it hears the keyboard, the pausing pad and P1's pad; B / Escape resumes. Heading
    PAUSED BY Pn in the seat's colour (plain PAUSED when automatic). QUIT TO TITLE asks END THE RUN? / WHAT YOU
    EARNED IS KEPT (NO first); only P1's pad or the keyboard may choose it, anyone else sees it dimmed and a
    short ONLY P1 CAN END THE RUN.
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

## Steam (stage 7 of the release plan)

- See `docs/steam.md`: what the code does with Steam and the Steamworks checklist for Curtis.
- 7a: the achievements (`Achievements`) and the `Platform` autoload, a no-op until GodotSteam and an App ID are
  in. Nothing is due on Steam now: stage 7 of `docs/release_plan.md` starts when Curtis says the marketing starts.
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
- **Sound:** 58 SFX (`card_deal`, `rune_cast`, `bell_toll`, `ghost`...) from `tools/gen_audio.py`
  (`--only=name,name` writes just those). Mixing (28 Nov, `Sfx`): buses Music, SFX and UI under Master with a
  hard limiter at -1 dB; the options' two volumes set the buses. Twenty voices by priority (`Sfx.PRIORITY`,
  `pick_voice`): a free voice first, else the lowest priority that has played longest, never a higher one, so
  a crowd of hits cannot cut the boss's roar; a taken voice fades for 10 ms. `enemy_die` and `hit` play one of
  four files. Every co-op moment has a voice (`ArenaEvents`): down, revive, boss phase, fate, redraw, banish,
  level up, victory, the team shrine's result, one heart left; a hurt is pitched by seat.

## Economy retune (job E, 21 Nov): level-ups carry the power curve

`floor_tomes` is 0 by default: no spell tome falls from kills or powerups, and the party tome (pickup
`World.PK_TOME_PARTY`, one random owned spell level for every wizard) drops instead: every Lich, every elite
(`party_tome_elite` 1.0, a new Tuning row; was a 0.25 constant; the frozen list's 0.35 is applied by stage 5's first tune job) and 2% of urns (`party_tome_urn`). Floor tomes used to
evolve every spell by about 1:40; now the first evolution comes at about 4:00 to 5:00 from picks and party tomes.

- XP: `xp_per_level` 90 -> 55, so level 11 to 12 at 6:00 (was 8.7 without floor tomes).
- Spells: level 1 to 4 damage up about 20/15/8/3% in `Spells.STATS` (level 5 and evolutions unchanged), because a
  spell now sits at level 1 to 3 for the first minutes.
- Horde: `horde_rate_base` 2 -> 1.5, `horde_rate_per_min` 7 -> 5, `enemy_hp_per_min` 0.1 -> 0 and `enemy_hp_mul`
  1 -> 0.85 (compound `enemy_hp_growth` 1.14 kept). Job P: `enemy_hp_mul` 0.85 -> 0.70 and `enemy_hp_growth`
  1.14 -> 1.20 (a milder start, the same climb by minute 12; casual solo 5/6, veteran 4/6, four casuals 3/3). The bots' danger is a hump at minutes 3 to 4 (arrows, orbs,
  orcs before the first evolution); runs that pass the first Lich mostly win.
- Bosses: `boss_hp_mul` 3.5 -> 3.0 and `final_hp_mul` 3.6 -> 3.2, set with the act bosses and the eight enemies
  merged (solo casual bots: Bone Chandelier 1:16, Ghost Writer 1:36, Archlich 1:58; at the first try of 4.5 and 2.5
  they took 2:12, 2:57 and 2:10). A playtest's 18:00 cap is not a game rule: an Archlich fight past 2:57 counts as
  a loss in the bot tables only.
- Still open for the final balance job: solo bots that fall do so at 4:25 to 4:45, just before the first boss
  (2 of 6 veterans, 1 of 6 casuals). `horde_rate_per_min` 4.5 removes it but drops the pressure at minutes 3 to 5
  to about 2, under the target of 3 to 6.
- Party: `spawn_party_scale` 0.4 -> 1.0, `enemy_hp_per_player` 0.12 -> 0.3, `boss_hp_per_player` 0.3 -> 0.5
  (`Bosses.PARTY_HP` follows), `xp_party_scale` 0.8 -> 1.0 (party level within 1 of solo): four wizards' AoE overlaps, so without these
  a party saw almost no pressure and won every run.
- Bots value the party tome like a rare chest (`SmashBot.PICKUP_VALUE[15]` 4.0).
- Before and after bot tables: the job E hand-back (wave 2).

## Wave 3 spells and passives (BONE SPEAR, VIGIL CANDLE, JUSTICE, THE LOVERS)
- Rows: `World.SP_BONE` 6, `SP_CANDLE` 7, `SP_CLEAVE` 8 (`Spells.STATS`, `Spells.EVOS`); catalogue rows 24 to 31
  (`Upgrades.W_BONE`, `W_CANDLE`, `JUSTICE`, `LOVERS`, `E_BONE`, `E_CANDLE`, `W_CLEAVE`, `E_CLEAVE`). Their evolutions pair
  with a passive: the `Spells.EVOS` row names its key in `passive`, the catalogue's `requires` is the truth.
- BONE SPEAR: a "bolt" row with `pierce` `Spells.PIERCE_ALL` (a shot with pierce -1 never runs out), 220 px (speed x
  life). OSSUARY LANCE (with JUSTICE): each hit throws `splinter` splinters square to the spear (`SPLINTER_DMG` of
  its damage, `SPLINTER_LIFE` s, never the foe it came from, never splintering again).
- VIGIL CANDLE: cast kind "candle", a circle of kind `Spells.CIRCLE_CANDLE` (the snapshot's reserved `R_KIND`) of
  radius 32 (24 before job P; level 1 to 5 damage 0.8 to 1.0 a tick, was 0.8 to 1.6, so level 5 in a dense crowd
  stays under 60 dps; CONSECRATION's radius 28 -> 32) on the densest cluster within `CANDLE_RANGE` 60 px (else `CANDLE_AIM_DIST` along the aim); it burns on
  the rune circle's timer (`RUNE_TICK`). Every standing hero inside (the caster too) keeps `VIGIL_HASTE` cast speed
  for `VIGIL_AFTER` s (`Player.vigil`). CONSECRATION (with THE LOVERS): the light heals 1 heart every `heal_every` 10 s
  to the most hurt hero inside (`WorldCastCircles._light_heals`, a timer per caster that runs while her light burns).
- Cast speed: THE LOVERS (8/16/24% within `LOVERS_RANGE` 60 px of a standing ally, an apprentice counts; alone
  `LOVERS_ALONE` of it) and the candle add up (`WorldCasting._cast_speed`) and divide the cooldown multiplier, which
  still never goes below `Spells.CAST_FLOOR`. Without them the divisor is exactly 1, so old runs are unchanged.
- JUSTICE: a foe its holder slays (not a boss, not by a burst) bursts 6/12/18% of the time (`World.rng`, drawn only
  for a holder) for `JUSTICE_SHARE` of its max health within `JUSTICE_RADIUS` px. Bursts queue in `World.bursts`
  and go off after the runes (`WorldCasting._update_bursts`, `World.bursting` set), `EV_BURST`, source
  `Results.SRC_JUSTICE`.
- Shot kinds: `Spells.shot_kind` (blocks of `SHOT_BLOCK` 6: the first six keep spell and spell + 6 evolved; BONE
  SPEAR is 12, evolved 18); clients decode with `shot_spell` / `shot_evolved`.
- Gate (`godot --headless --path . -s tools/tool.gd -- spell_dps --gate`): see the PR; `sim_horde` has a four-wizard
  row per new cast kind (`WAVE3_ROWS`: each wizard holds it evolved on top of the six at level 3).
- Card art: stand-in emblems `w_bone`, `w_candle`, `w_cleave`, `justice`, `lovers` in `TarotArt.EMBLEMS` (an
  evolution shows its spell's), `TarotArt.ARCANA` XI JUSTICE and VI THE LOVERS (paintings `cards/tarot/justice`,
  `cards/tarot/the_lovers` when they exist).

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

## Classes and races (job C1: logic, data, saves; design in `docs/classes_design.md`)
- Data: `Classes.ROWS` (key, name, role, hearts, weapon, skin, skill, threat, stat points, then the passive
  columns: walk, ritual, redraws, aura radius, aura WARD points) and `Classes.SKILLS` (the nova button's skills and
  their numbers); `Races.ROWS` (key, name, stat points, trait, build) and `Races.TRAITS`. Append only; saves store
  the keys, seats and the snapshot row carry the indices.
- Row 0 is HUMAN and MAGE, and nothing happens without a hero: a wizard gets a class only from
  `World.apply_hero(p, hero_dict)` (after `apply_meta`). Every Player field it sets (`threat`, `threat_k`, `skill`,
  `walk_mul`, `ritual_mul`, `aura_r`, `aura_ward`, `fury`, `reach_mul`, `safe_mul`, `luck`) is neutral by default,
  so a seat with no hero plays exactly as before (the pinned solo run and the golden sims are unchanged).
- `Hero` (`game/logic/hero.gd`): name, race, cls, school, look (skin + 4 x (hair + 6 x style)), level 1 to 20 (100 x
  level XP each), xp, points[6] (one per level past the first, at most 10 in a stat), sockets[3]. `stats()` is
  race + class + points at `Hero.POINT_VALUE` (MIGHT 2%, FOCUS 1%, SWIFT 1%, VIGOR 1/4 heart, WARD 1%, FORTUNE 3%
  gold) plus the socketed cards, capped by `Loot.STAT_CAPS`; `luck()` is FORTUNE x 0.2. `Hero.class_xp(seconds,
  bosses, won, mul)` = 10 per whole minute + 50 per boss + 150 for a win, x mul; `run_xp` adds the HUMAN's 5%. Not
  wired to the end of a run yet (comes with the screens).
- `Profile` version 2: `heroes` (1 to `MAX_HEROES` 8; a new profile has one) and `hero` (the active one). The socket
  calls (`socket_card`, `unsocket`, `socket_indices`, `sockets`) work on the active hero, and `bonuses().armor` is its
  cards, so the card album and a run play as before. A version 1 save becomes one HUMAN MAGE of school 0 (a v1 save
  never stored a school) holding the old sockets; top-level `sockets` is still written (a copy of the active hero's).
- Threat: enemies pick the wizard with the least distance / threat (`Player.threat_k` = 1 / threat^2 times the
  squared distance, exactly 1 at threat 1; both in `WorldEnemies._nearest_player` and inline in `_update_enemy`).
  `World.threat_spread` (largest / smallest threat) widens the contact test's reach so a threat pick never skips a
  nearer wizard in touch. A PROVOKE sets `Enemy.taunt` / `taunt_t`.
- Skills (`WorldPlayers._skill`, where the nova was; each spends a nova charge, emits `EV_SKILL` (slot, skill) and is
  sealed by THE HANGED MAN like the nova): NOVA as ever (mage, and every wizard with no hero); PROVOKE (enemies
  but bosses within 100 px taunted 5 s, knight unhurt 2 s); VOLLEY (50 px roll along her movement, unhurt 0.4 s, 12
  shots of her weapon fanned behind her); SANCTUARY (standing heroes +2 hearts, `EV_HEAL` (slot, hearts); the fallen
  within 80 px rise); AEGIS (heroes within 60 px unhurt 3 s, using `invuln`).
- Passives: mage +2 redraws; knight walks x0.94, archer x1.08 (`walk_mul`); a priest counts twice in a ritual
  (`ritual_mul`); a paladin's aura gives heroes within 50 px (her too) +8 WARD points (0.08, one aura, capped) in
  `hurt_player`. Traits: ORC +10% damage at 2 hearts or fewer (`_damage_enemy`); ELF magnet x1.25 (`reach_mul`: read
  by the spirit's magnet; the standing magnet in `WorldDrops._magnets` does not read it yet); DWARF
  STURDY "UNHURT 50% LONGER AFTER A HIT": `safe_mul` 1.5 multiplies the hurt safety a hit sets
  (`Classes.hurt_safe` in `WorldPlayers.hurt_player`; a WARD shrug keeps its own 0.5 s); FORTUNE's `luck` is not read by chests yet (`WorldDrops`).
- Weapons (job C2): a class weapon is a skinned entry of a spell row. `Classes.C_WEAPON` names the row and the hero
  holds that row's own Upgrades entry, so it levels and evolves like the row; `Classes.C_SKIN` names a
  `Classes.SKINS` entry: its name (cards via `Classes.card_name`, screens via `Classes.weapon_name`) and overrides
  (`range` px a bolt flies, `heal` hearts every `heal_every` s for a light, `dmg_mul` and `cd_mul` on the class
  weapon's damage and cooldown at every level, `knock_mul` on a sweep's knock-back; `WorldCasting._skin_mul` reads
  them for the class weapon only, so a BONE SPEAR or STARFALL from a card is the row as it is). `apply_hero` sets `Player.class_weapon`
  and `Player.skin` (-1 and "" without a hero, for a mage, and so for every spell picked up later); the logic reads
  them (`WorldCastBolts._cast_bolts`, `WorldCastCircles._light_heals`), the arena reads the snapshot's `P_CLASS` through
  `Classes.weapon_skin(cls, spell)` (`ArenaDrawFx._skin`), so no snapshot row changed. MAGE: the school's spell,
  unskinned. KNIGHT: CLEAVE, its own row (`SP_CLEAVE`, cast kind `sweep`: a `arc` 100 degree swing reaching `r`
  34 px along the aim when a foe stands in that arc, else toward the nearest foe it can reach, and it waits while
  it can reach none (`_sweep_dir` uses `_cast_sweep`'s reach test); every foe in it hit once, knock-back
  `SWEEP_KNOCK`, `EV_SWEEP` draws a steel arc); its catalogue row requires itself, so only a hero who starts with it is offered it. Its
  evolution WHIRLWIND (job K, `Upgrades.E_CLEAVE`: CLEAVE at level 5 and STRENGTH, the one passive no other
  evolution pairs with, so STRENGTH weighs `PARTNER_WEIGHT` only for a hero holding CLEAVE) swings a full circle
  (`arc` TAU) reaching 60 px, 36 damage every 0.55 s, and strikes at most `most` 3 foes a swing, the nearest first
  (without the cap the full circle read 900 dps in `spell_dps`' dense crowd, four times the other evolutions; with
  it and 48 damage 233, beside ASTRAL LANCE's 234). The damage came down from 48 to 36 once the bot fought at
  WHIRLWIND's reach (`SmashBot._melee_r` reads the evolved reach) and a sweep reached wide bosses (its search is
  reach + `World.CELL`): solo knight, 12 casual seeds and 6 veteran: 48 gave 12 and 5 wins, 36 gives 10 and 4
  (0 wipes; the mage wins 6 and 5). `EV_SWEEP`'s b carries + 8 when evolved (as `EV_RUNE`); the arena draws the
  same steel flash all the way round (`Fx.swing` takes more arc points for a wider swing). ARCHER: LONGBOW, the BONE SPEAR row as arrows,
  260 px (her VOLLEY's arrows too). PRIEST: HOLY LIGHT, the VIGIL CANDLE row, white with a cross; it heals the most hurt standing hero inside
  one of her lights (her too) 1 heart every 6 s of burning (`EV_HEAL`). PALADIN: SMITE, the STARFALL row as hammers
  of light. Job P's numbers (solo casual bots at WIZARD, 12 seeds: mage 9, priest 8, paladin 8, knight 7, archer 7 wins when
  tuned; mage 6, knight 6, archer 10, priest 5, paladin 8 after the audit fixes of #84 merged, so read a 12-seed
  table as plus or minus 2 to 3 wins; before, the four classes won 0 or 1 of 6):
  CLEAVE x0.7 damage (x1.2 since job K), x0.85 cooldown, x2.5 knock-back; LONGBOW x1.5, x0.5; HOLY LIGHT x1.3; SMITE x1.6, x0.55;
  hearts knight 9 (was 7), archer 5 (4), priest 6 (5); `Classes.C_HURT_SAFE`, the seconds a hit leaves a hero
  unhurt (`hurt_player`, was 1.1 for all): knight 2.0, archer 1.6, others 1.1; class stat points knight MIGHT 30
  FOCUS 10 (MIGHT 5 FOCUS 2 since job K, his damage moved into CLEAVE's skin and WHIRLWIND), priest MIGHT 25.
  CLEAVE's row (only a knight is offered it) grows to 20 damage every 0.7 s at level 5 (was 12 every 0.8 s). `spell_dps --clear` prints each class's weapon with its skin and its
  class stats (a HUMAN of class level 1): every one within 15% of the mage's ARCANE BOLT.
- Developer flag: `--hero=<race>,<class>[,<school>]` (keys, names or indices; school a Wizards index, name or title)
  gives every local seat that hero (`Arena._ready`, after `apply_meta`). Nothing happens without it.

## Apprentices and seats
- Roster (`game/autoload/net.gd`): a row is `{slot, peer, device, wizard, ai, away, ...}`. `Net.add_apprentice()`
  seats an apprentice (device `G.DEV_AI`) at the lowest free seat and returns it (-1 full, a client, or in a run);
  `Net.remove_apprentice(slot := -1)` removes that one or the highest. A joining human (local or LAN) takes the
  highest apprentice's seat, keeping its wizard. `Net.kept_apprentices` (their wizards) seats them again in every
  `start_offline` and `host_game` of the session. A human seat whose device is silent for `Tuning.seat_silence`
  (5 s: no input packet or once-a-second hello from a LAN seat, an unplugged local pad; never the keyboard, never in
  scripted runs) turns `away` (`Net.check_silence`): `seat_builds` and the arena make its `World.Player.ai` true and
  the host's `my_slots` leaves it out, so the World plays it, until its device speaks again.
- World (`game/logic/world/apprentices.gd`, `WorldApprentices`, numbers in Tuning's "Apprentices" rows):
  `with_inputs` gives every ai wizard with no input a `SmashBot` (see `docs/bots.md`); `WorldLevels` takes its
  card at once (`Upgrades.best_pick`); damage x `apprentice_damage`
  (`WorldEnemies._damage_enemy`), party weight `apprentice_scale` (the horde, `pscale`, and the XP a level
  needs, `xp_needed`); `may_take` keeps chests, tomes, cards
  and (unless at `apprentice_potion_hp` hearts or fewer with no standing human hurt) potions off it; `payee` sends
  its coins and gems to the nearest human; shrines take no bet from it (`WorldShrines._update_shrines`), so it never
  draws a fate; `gets_up` raises it free after `apprentice_up_time` down, never under DARKNESS
  (`seal_ritual > 1`). Enemy and boss health count an apprentice as `apprentice_scale` of a wizard too
  (`World.party_weight`, `Bosses.party_share`). The run ends when no human can return (apprentices play on alone only with no human seat);
  a human down on her last life with nobody standing ends it even when an apprentice would get up soon (kept on
  purpose: an apprentice is a helper, not a second life). A human seat gone silent (`Player.away`) is played like
  an apprentice but never gets up free and keeps her queued draws; when a seat changes hands `Arena` resets
  `last_bomb` so the bot's and the hand's Nova counts never mix.
  `World.remove_player(slot)` (a LAN leaver) keeps her score and kills in `total_score` and `total_kills`.
- Input: keyboard seat 2 (`G.DEV_KB2`): arrows move, right Ctrl fires the way it faces and confirms, Enter is its
  nova, I opens its tray (O redraws, 8, 9, 0 pick); while it is seated the arrows are its own (`PlayerInput.key_device`). Right Ctrl is told from the left by
  key events (`PlayerInput.note_key`, fed by `G._input`).
- Lobby (`game/ui/title.gd`; what a press does is `LobbyRules.decide`, pure, tested in `test_lobby_rules`): player 1's
  (the first seat's) Y or + adds an apprentice, X or - removes one, START (or Enter) begins the run, A never starts it.
  An unseated device's A / fire / START joins ("A/ENTER: JOIN"); its back, X and Y do nothing. Back from player 1
  leaves the lobby at once when no other human holds a seat, else asks "LEAVE THE LOBBY?  ENTER/A: YES  ESC/B: NO"
  (only player 1's device answers; back or NO closes it). Back from another seated device frees only its seat
  (`Net.remove_local_device`: nobody shifts, the next device takes the free slot). SELECT or I calls
  `Platform.invite_friends()` (Steam's Remote Play Together invite; a no-op without Steam). An apprentice's seat says
  APPRENTICE over a dashed hem, an away seat AWAY. Player 1's two hints name the key of its own device
  (`LobbyRules.add_hint`, `remove_hint`): the lowest free seat, the one the next apprentice takes, shows
  `+: APPRENTICE` (a pad: `Y:`), and the last apprentice's seat swaps its name with `-: REMOVE` (a pad: `X:`) every
  `SEAT_HINT_SWAP` 2 s; a LAN client sees neither. Shots: `--autotest --seats`.
- Sanctum hub: the device that walks it (`G.local_devices[0]`, else the keyboard) alone leaves it with back. It rides
  through the shopkeeper's UNLOCKS in `G.title_lobby_device` and is seated again on the way back, so the portal seats
  the same device as player 1.
- LAN fixes: run-ending and saved-data events (`Net.RELIABLE_EVENTS`) go by reliable RPC (`Net.send_events`,
  channel 3), the rest stay on the snapshot; a client that sees the host's game-over phase for 1.5 s without them
  ends the run itself. The ENet throttle is off on connect. The host answers every join (`_refused`: version or
  snapshot layout, a run on, full), hides other versions from discovery and refuses connections during a run. A
  remote input packet must be 6 or 8 finite numbers (`Net.clean_input`), and `WorldPlayers._update_player` drops a
  non-finite one. A client leaves the results screen with fire; the host tells clients to go to the title and closes
  0.25 s later, and a client closes its side quietly when the message comes.

## Heroes in a run
- Lobby: every human seat holds a hero. `Net.seat_heroes` (device -> index into `Save.profile.heroes`, -1 a guest that
  earns nothing) is this machine's; seat 1 starts on the active hero, the others on the first no local seat holds.
  Left/right step the free heroes (then the guest when heroes < local seats: `Net.step_seat_hero`), H or the right
  bumper opens `HeroRoster` for that seat's device (`Net.set_seat_hero` on a pick, `refresh_seat_heroes` after).
  The roster row gets `hero` (the cleaned `Hero.to_dict`, `{}` for an apprentice) and race, cls, look, cls_level
  from it; a LAN client sends its seat's hero by reliable RPC (`_submit_hero`) and the host cleans it with
  `Hero.from_dict`. The seat's `wizard` is only its colour (a mage prefers her school's).
- Guests differ by seat (`Net.GUEST_PRESETS`, `Net.guest_hero(slot)`, `Net.hero_at(idx, slot)`): slot 0 HUMAN MAGE, 1 ELF ARCHER, 2 DWARF KNIGHT,
  3 ORC PRIEST, level 1, no cards, named after the class; a guest is still stored nowhere and earns nothing (index -1).
  `--autotest --players=N --seat-heroes` seats heroes in a scripted run (`Net.force_heroes`); `--heroes` is the Sanctum's mirror shots.
- Seat rim: a hero drawn from her picture gets `Still.draw_rim` under it (1 px in `G.player_color(slot)` lightened 0.3, 1 px
  `Sprites.OUTLINE` outside, built once per picture from its alpha, `Still.rim_textures`); an apprentice's is `ArenaDrawWorld.RIM_AI_ALPHA`.
- Scripted runs (`Flags.is_scripted_run()`) seat no heroes (`Net.force_heroes` is the test seam), so autotest, bot and
  sims play as before; `Arena._ready` applies each row's `hero` after `apply_meta`, `--hero=` still overrides local seats.
- Class XP: `Net._start` sets `G.run_heroes` (`Net.played_heroes`: local human seats' saved heroes, once each);
  `G.finish_run` passes them as `run.heroes` (empty when scripted) and `Profile.finish_run` gives each
  `run_xp(seconds, liches, won, seal mul)`. Levels gained: `Profile.last_hero_levels` and `G.last_run.hero_levels`.

## Hero screens
The Sanctum's MIRROR (`Sanctum.MIRROR`, left of the portal) opens `HeroRoster` (`game/ui/hero_roster.gd`, over `Save.profile`; it takes all input and draws over the hub like the card album). The roster lists up to `Profile.MAX_HEROES` heroes and has four actions: PICK (makes the row the active hero, `picked` = its index, closes), SHEET (opens `HeroSheet`), NEW HERO (opens `HeroBuilder`; hidden when full) and DELETE (hold confirm `HOLD_TIME` s; never the last hero). `HeroBuilder` steps RACE, CLASS, SCHOOL (mage only: the four `Wizards` spells), NAME (Ouija board), confirm; it adds the hero, makes it active and saves. `HeroSheet` shows level and XP, hearts, the six stats by source (race, class, spent, cards), spends points (`Hero.spend_point`), weapon and skill numbers, the race trait, the three card sockets and runs and wins. All three save through `HeroSheet.save_now` (nothing in a scripted run). Portraits come from `assets/art/portraits/heroes/hero_<race>_<class>.png` through `Art`, with `DialogueBox.draw_stand_in` when a file is missing. Each screen has `active`, `open`, `handle(event) -> bool`, `update`, `draw(ci, t)`.
Autotest: `xvfb-run -a godot --path . -- --autotest --heroes --out=<dir>` shoots the Sanctum with the mirror, the roster, each builder step, and a sheet.

## Class play for bots and apprentices (21 Nov)
- `SmashBot` plays a hero's class when `Player.skill` is not NOVA (`_class_play`; details and numbers in
  `docs/bots.md` "Class play"): tanks guard the ally under the thickest crowd, the priest keeps the most hurt ally in
  her light, the archer keeps range, and the nova button's skill is used for what it does. No hero, or a MAGE: as
  before (pinned in `test_smash_bot`).
- Apprentices: `Net.add_apprentice` (via `_add_to_roster`) gives the new seat `Net.apprentice_class()` (first missing
  of tank, healer, ranged, damage; `Net.APPRENTICE_ROLES`), `race` 0, `cls_level` 1; `World.new` copies them from
  `seat_builds`, and `WorldApprentices.take_class` (the first `with_inputs`, once: `World.classes_taken`) applies
  the level 1 HUMAN hero. A human taking an apprentice's seat clears its class fields. Every roster change outside
  a run deals the apprentices' classes again, humans counted first (`Net._fill_apprentice_roles`, from
  `_push_roster`), so a human who picks another hero or joins never leaves two tanks and no healer.
- `tools/playtest.gd`: `--party=persona[:class[:race]],...` and `--hero=class[:race],...`; a `skills` line.

## The last of the 19 Nov bug audit (21 Nov)

All 35 verified findings are closed; 30 were fixed along the way by the wave 1 and 2 jobs. The last five:
- The Lich aims its volley from the muzzle (16 px up) at a wizard's hit centre (6 px up), so one standing beside
  it is hit (`BossLich.think`).
- Knockback an enemy carries adds up only to `Bestiary.KNOCK_MAX` (280 px/s, times its heft): one nova still
  pushes in full, a crowd of hits no longer throws an elite to the wall or pins the Lich (`_damage_enemy`).
- An orc's charge ends on its timer only; the wall test that ended it also ended every charge in the bottom 7 px.
- The Lich summons nothing once the run is lost.
- A card still on the floor when the Archlich dies is taken for the party (`Bosses._pay_floor_cards`: the slayer,
  else the nearest standing human, then a standing apprentice).

The golden run of seed 21 changes from 60 s on (the knockback cap and the orc's charge), as meant.

## The Book of Deeds (21 Nov)

Achievements you can see and are paid for, without Steam. Files: `game/logic/achievements.gd`, `game/ui/deeds_book.gd`,
the deeds parts of `profile.gd`, `Sanctum.DEEDS` and `sanctum_view.gd`, `results_view.gd`.
- **Catalogue.** `Achievements.LIST` rows are `[api, name, description, crystals, secret?]`: the first 14 are
  Steam's (order and names fixed), 38 more follow (win with each class and race, the tank/healer/ranged trinity, each
  evolution but RUNE CIRCLE's, the two act bosses, ARCHMAGE and Seals I to VIII, revive, kill, hero level, card and
  secret totals, apprentices only, a fast four-hero win). Rewards 5 to 50 crystals. A row past the 14 has its rule in
  `Achievements.RULES` (`api -> [kind, argument]`, checked by `_rule_met`); numbers are named constants there.
- **`Achievements.earned(record, won, seconds, party = {})`** returns every api name the run (and the profile's
  totals) earns. `party` keys, all optional (a missing fact earns nothing): `classes`, `races` (one per hero a person
  plays, apprentices left out, built by `Achievements.party_of` from the snapshot), `seal`, and the totals `Profile.deed_facts()`
  adds: `revives_total`, `kills_total`, `hero_level` (highest class level), `cards`, `secrets`. Apprentices are
  `record.ai`. A win at a Seal counts for every step below it. Only the Lich Lord and the Archlich were already
  deeds (LICH, ARCHLICH needs a win); no new deed for the Archlich.
- **Saved.** `Profile.deeds` (api name -> true, in the order earned) is saved as a list; an old save has none,
  and a name this build does not know is kept (`deeds_earned()` counts the catalogue's only). `finish_run` books
  the new ones after the totals and hero XP, adds their crystals to `crystals` once (the return value stays the
  run's own pay) and sets `last_pay.deeds` (api names) and `last_pay.deeds_pay`. A run dictionary with no
  `results` earns no deeds. `Platform.finish_run(record, won, seconds, party)` still sends every earned name.
- **Results screen.** Under the pay line, `Achievements.result_lines`: "DEED: NAME +N", three lines at most in all, the
  last "+K MORE DEEDS" when they do not fit; with deeds the ending line gives way (`ArenaResultsView.DEED_*`).
- **The station.** `Sanctum.DEEDS` (a lectern at 338,112; a plain rect stand-in, `_draw_lectern`) opens `DeedsBook`
  (`active`, `open(profile)`, `handle`, `update`, `draw`): 12 rows on view, up/down move, left/right a page, back closes,
  earned rows gold with a tick, locked dim, locked secrets `???`, the selected description at the bottom.
- Shots: `xvfb-run -a godot --path . -- --autotest --deeds --out=<dir>`; the results lines show on
  `--autotest --players=2 --end=20:win`.

## Results: damage by spell, first-visit lines, deleted heroes (21 Nov)
- **Damage page.** `Results.damage_rows(slot, limit)` -> `[source, damage, share]`, most damage first, ties to the lower
  source, shares in whole percent (rounded down, so at most 100 together), sources under `MIN_SHARE_PCT` dropped, at
  most `DAMAGE_ROWS`. `Results.source_name(src, cls)`: the class weapon's own name, a spell's name, NOVA / ORBIT / JUSTICE.
- The first page has no room (columns, moments, pay, deeds), so the fire press that used to leave goes to the DAMAGE page
  first (`Arena.results_page`, `ArenaResultsView.next_page`; the first page's hint reads PRESS FIRE FOR DAMAGE when any
  wizard has rows) and leaves from there. Shot: `--autotest --players=N --end=40:win` also writes `results_damage.png`.
- **Footer crystals** are `Profile.run_gain(earned)`: the run's pay plus the deeds' (`last_pay.deeds_pay`).
- **First visits** are saved: `Profile.talked` (`first_time(key)`, `first_key(speaker)`), written by the Sanctum when a
  greeting is told (nothing in a scripted run); old saves load with none.
- **Deleting a hero** shifts held indices: `Profile.index_after_removal` is the one rule; `Profile.remove_hero` applies it
  to the active hero, `Net.hero_removed(i)` to every local seat (a seat that held her takes the first free hero).

## Figures from still pictures, icons and scenes (21 Nov)
- **Groups.** `Art.GROUPS` gained `sprites`, `icons` and `scenes`; they are found like the others (`Art.find`), and
  `Art.wanted()` lists every name (`Still.names()`, `Still.icon_names()`, `Art.SCENES`). `Art.drop_root` (the
  autotest flag `--art=<dir>`) is a folder searched before all others, for art shots with test pictures.
- **`Still`** (`game/art/still.gd`) is the one place: `hero_name(cls, ai)` (apprentice picture, else the class's, else
  "" and the code sprite stays), `enemy_name(type, final)` (`enemy_<key>`, `boss_<key>`, `enemy_archlich`), `draw`
  (the figure, `motion` applied, hit flash as a white copy), `draw_static` (hub pieces), `icon`/`draw_icon`,
  `draw_scene`, `deed_icon` and `DEED_MARKS` (the Achievements.RULES kind -> win, slay, time or secret mark).
- **`Still.motion(t, moving, facing)`** is pure: `{off, lean, squash}`. Walking: a bob (`WALK_BOB` px at `WALK_RATE`) and
  a lean toward the facing (`LEAN_MOVE` plus `LEAN_SWAY`); standing: a breath (`BREATH`, share of height). Sizes are
  rounded to whole pixels, so the figure steps rather than blurs.
- **Callers.** Arena heroes `ArenaDrawWorld._draw_player` (seat ring and pip kept, no staff) and the spirit
  `ArenaDrawFallen._draw_spirit`; the hub walker `SanctumView._draw_wizard`; monsters and bosses through
  `EnemyView.draw_still` from `ArenaDrawEnemies._draw_enemy` (pose offsets and tints arrive in `feet` and `mod`); hub
  `_draw_lectern`, `_draw_mirror`, `_draw_npc`. Icons: `ArenaHud.build` slots, `TarotArt.emblem` (level-up cards,
  tray, results awards), the builder's class and race rows, the Book of Deeds marks. Scenes: builder, sheet, album,
  deeds (drawn again inside the frame, `Still.SCENE_INNER`) and the lobby (`Title._draw_front`).
- Tests: `tests/unit/test_still.gd`. Shots: any autotest mode with `--art=<dir>`.

## Release builds and debug flags (B4)
- `Flags.args` drops `--autotest`, `--capture`, `--scripted`, `--dev` and `--hero` (`Flags.DEBUG_ARGS`) unless the engine is the editor, a debug build or the export has the feature tag `playtest` (`Flags.debug_args_allowed`, `without_debug_args`). `--smoke` works in every build and counts as a scripted run (no player data written). `game/main.gd` starts the autotest and `game/debug/smoke.gd` from `Flags.args`, so a release ignores `--autotest`.
- Desktop packs hold the game only (`exclude_filter` in all four desktop presets: tests, realm, docs, tools, .github, build, game/crowd, *.md/*.py/*.sh). `game/debug/` stays: Tuning and the autotest preload live there. Pack is beside the binary (`embed_pck=false`).
- Presets: "Windows Desktop", "Linux" (release) and "Windows Desktop Playtest", "Linux Playtest" (tag `playtest`). The Windows version fields are `G.VERSION + ".0"`; `test_flags` fails when they drift. How to build and read the smoke line: `docs/release_build.md`.

## Credits and licences
- `Credits` (`game/logic/credits.gd`, pure) turns facts into the roll: `roll(maker, pictures_by, has_sentry, version, components)` gives `[kind, text]` rows (`HEAD`, `LINE`, `GAP`). `MAKER` and `PICTURES_BY` are empty until the owner gives them; an empty one leaves its whole section out. Text is upper-cased and glyphs `PixelFont` lacks become spaces. `fit(text, px, scale, tail)` is the one rule for a long line: the text is cut with `..`, the tail (a component's `, LICENCE`) stays whole. `MAX_PX` 448 holds today's engine list uncut; `test_credits` fails when an engine update brings a longer name.
- The engine's third-party list is never typed: `CreditsView.open()` passes `Engine.get_copyright_info()` (one `NAME, LICENCE` line per component; the engine's own row is left out because BUILT WITH names it) and `Engine.has_singleton("SentrySDK")` (the test `Crash` uses) for the crash-report section.
- `CreditsView` (`game/ui/credits_view.gd`, the title's CREDITS board): scrolls by itself, stops at the end; up/down/wheel scroll by hand and stop the automatic scroll (`scroll_to`); B, ESC or a click leaves. The title leaves its version label off the two boards whose frame reaches that corner (CARDS, CREDITS). Shots: `--autotest --credits` saves `credits.png`, `credits_licences.png`, `credits_end.png`.
- The built game's full texts are `THIRD_PARTY_NOTICES.txt` (`tools/notices.gd`); the sentry-native and Crashpad texts come from `tools/notices/` (`SOURCES.md` lists URL, ref, date, sha256).

## The catalog's stage 3 rows (job A3: spell + arcana pairs, held arcana, shut rows)

- Pairs. Every evolution needs its spell at level 5 and one arcana (a PASSIVE row) at level 1, never another
  spell; the chart is `docs/content_list.md` § 37 and the truth in code is the catalogue's `requires`. Today's
  nine: ASTRAL LANCE with THE MAGICIAN (`quick`), THUNDERFIRE with THE TOWER (`nova`), BLIZZARD with TEMPERANCE
  (`regen`), TEMPEST with THE CHARIOT (`swift`), COMET RAIN with THE HERMIT (`wisdom`), SEAL OF SOLOMON with THE
  MOON (`magnet`), OSSUARY LANCE with JUSTICE, CONSECRATION with THE LOVERS, WHIRLWIND with STRENGTH.
  `Spells.passive_partner(spell, evo)` and `Upgrades.partner_row(spell, evo)` name the arcana of either
  evolution; `Spells.partner` and the `partner` key are gone.
- Twelve new rows at catalogue indices 32 to 43 (`Upgrades.PRIESTESS` .. `E_BLADES`): four arcana, HEX and SPIRIT
  BLADES (`World.SP_HEX` 9, `SP_BLADES` 10, `Spells.COUNT` 11), the four schools' second evolutions
  (`Spells.EVOS2`) and the two new spells' evolutions. Ten of the twelve are on `Upgrades.UNBUILT` (job A4 built
  THE STAR and THE EMPRESS, § The cast hooks): never available, never counted in a pair, never planned for by a bot;
  a spell with no caster casts nothing (`WorldCasting._cast`). `WorldGrants.give` is the one path past the list, and
  the job that builds a row takes it off. An arcana of two spells (STRENGTH: WHIRLWIND and GREEK FIRE) completes
  either pair.
- THE TOWER (`nova`, 3 levels) and JUDGEMENT (`life`, 2 levels) are PASSIVE rows that take an arcana slot; a pick
  still gives the charge or the life at once, and no row is INSTANT any more. THE TOWER's refill, JUDGEMENT's
  blast and their new words come with job C5; until then both cards keep their old words.
- Shut rows (`docs/stage3_brief.md` § 4.3). `World.locked` is the table's mask, from `apply_meta`'s `"locked"`
  (`Profile.locked_rows` through `Save.run_bonuses()`); it goes into every wizard's `banned`, and `apply_hero`
  takes a hero's own class weapon, that weapon's arcana and its evolution out again (`_open_own_rows`). The
  snapshot carries the mask as `"lk"`. A scripted run has no mask.
- `Upgrades.row_name(idx)` is the name a tray row writes: the full name, or without its leading `THE ` when
  wider than `TarotArt.ROW_TITLE_CHARS` (HIGH PRIESTESS). A class skin's own name still wins.
- Bots. A casual bot (damage first) takes the arcana that completes a pair ahead of everything but an evolution
  once the pair's spell is at level 3 (`SmashBot.PAIR_FROM_LEVEL`, `_pair_spell_level`); before that the arcana
  counts for what it does alone, because taken early it costs her the spell levels that carry the first minutes
  (two casual bots: 1 of 4 runs won when they took it at once, 4 of 4 with the rule, as before the pairs). A novice
  takes it as the shiniest card, and a veteran never plans for an unbuilt evolution or for the other road of a
  spell she has evolved (`SmashBot._plan_open`).
- `Sprites.SPELL_COLORS` and `SPELL_DARK` have one entry per spell (11).

## The cast hooks (stage 3, job A4: THE STAR, THE EMPRESS, the damage hooks, the use counters)
- Four hooks every cast and every hit reads (`docs/stage3_brief.md` § 4.5); a later card changes a hook, never a
  caster. `WorldCasting._missiles(p) -> int`: THE STAR's value at her level (1 / 2), 0 without her or with no wizard.
  `WorldCasting._area(p) -> float`: THE EMPRESS's (1.1 / 1.2 / 1.3), 1 without her. `WorldEnemies._dealt_mul(w,
  src) -> float`: STRENGTH and WANDS (`Upgrades.damage_mul`) x (1 + might + the shop's damage + an ORC's fury) x an
  apprentice's share, in the order of operations it always had; 1 with no wizard. `WorldEnemies._taken_mul(w, e)
  -> float`: 1 today (HEX, PROVOKE's second effect later). `_damage_enemy` multiplies by both and by nothing else.
- Missiles. `WorldCasting._cast` hands every caster the spell's count plus `_missiles` (an evolution's count too):
  bolts (the fan's, the stars, the spears), the jumps of each chain (TEMPEST's two chains each), rune circles and
  candle lights (each on a cluster no circle of the cast covers). A sweep sends none: half its arc grows by
  `Tuning.star_sweep_arc` (0.5, group Casting) of itself per missile (`WorldCastSweep._sweep_half`). A caster
  returns how many it sent in the units of its count (a chain: the most foes one chain struck; circles: those
  placed; a sweep: its count), and a new caster must too.
- Areas, read through `_area` at the cast or at the hit, never in `Spells` data: a blast's radius and the reach its
  bonus fades over (FIREBALL, THUNDERFIRE; THUNDERFIRE's zap reach is not an area), COMET RAIN's frost burst, an
  OSSUARY LANCE splinter's flight (`SPLINTER_LIFE` x area), a rune circle's and a candle light's radius (never their
  life; the clusters they are placed on, the light's haste and heal and the Seal's pull follow the radius), a
  sweep's reach (`_sweep_reach`, where it waits too). JUSTICE's burst is not one of them.
- What is drawn follows the World: `EV_EXPLODE` carries the scaled radius (the arena's ring and flashes follow it,
  and the scorch is `ArenaEvents.BLAST_SCORCH` px times that radius over `Spells` FIREBALL's `blast`; the `fx_blast`
  ball is a fixed sprite), `EV_FROST` and `EV_RUNE` theirs, a circle's snapshot row its `r`, and `EV_SWEEP`'s `a` is
  `Vector3(angle, reach, half arc)` as swung. `test_the_arena_draws_the_sizes_the_world_used` feeds the arena those
  events and checks what it draws.
- THE STAR and THE EMPRESS are off `Upgrades.UNBUILT` and dealt like any arcana; their evolutions (LODESTAR, DANSE
  MACABRE) are not, so neither completes a pair yet. Bots: `SmashBot.PASSIVE_TASTE` star 32, empress 22, by what each
  adds in a crowd of 40 (the A4 balance review: THE STAR I adds ARCANE BOLT +34%, FIREBALL +49%, RUNE CIRCLE +28%;
  THE EMPRESS I adds FIREBALL +16%, RUNE CIRCLE +13% and nothing to the bolts, chains and stars). Both under THE
  MAGICIAN, since a slot filled early is one STRENGTH or a pair's arcana cannot have. Measured (two casual bots, 100
  runs each on GitHub, seeds 1-100): main won 82; with both dealt and tastes star 36 / empress 40, 56; with both
  dealt and never taken, 69. A card that completes no pair thins the hands, and the deck grows all through stage 3:
  the balance pass tunes for it with the numbers in hand. Not built yet: their D rows, and THE STAR's S row
  (`sim_horde` with four wizards holding THE STAR II went over the step budget on the bone and vigil loadouts in the
  A4 cost review, because `_place_circles` searches every candidate's cluster again for each extra circle). Unlocks
  (content list § 39) are not built: THE STAR opens with the deed LEVEL_5, which is not in `Achievements.LIST` yet,
  so every profile has her; THE EMPRESS opens only with THE DUELLIST'S DECK (`Profile.OPENS` `deck_blades`, on
  `Profile.UNBUILT`), so every real profile locks her (`locked_rows`, `World.apply_meta`) until the job that sells
  the deck. Scripted runs, bots and tools have no mask (brief § 4.3) and deal both.
- Use counters (`Results.use`, § 4.4), at the event, never at a hit or once an enemy in a step's loop: `quick` a
  cast whose cooldown THE MAGICIAN shortened (not one the cast floor holds; `_auto_cast`), `lovers` a cast with an
  ally near (`_lovers_near`), `star` a cast that sent more than the spell's own count, `empress` a cast of a spell
  with an area (`_has_area`), `justice` a burst (`_update_bursts`), `power` a kill by her (`_kill_enemy`), `swift`
  each game second in which she moved, credited at its turn (`WorldPlayers._update_player`; `Player.swift_moved`
  holds it), `regen` a heart TEMPERANCE gives back, `magnet` a gem THE MOON starts to pull from beyond
  the reach she would have without it (`_update_pickups`: a gem not yet flying at the magnet's speed; never in a lull
  or a gem rush, when every reach is the floor; marked at the pull's start in `Pickup.moon`, credited when she takes
  it in `_collect`, never when another wizard does), `wisdom` a gem whose rounded XP THE HERMIT raised (`_collect`; at x1.15 no gem under 4 XP is raised), `nova`
  and `life` the pick of THE TOWER and JUDGEMENT (`WorldLevels._pick` and its twin `WorldGrants._grant_effect`). Each
  credit goes to the seat whose card acted (`test_each_credit_goes_to_the_seat_whose_card_acted`).
- Two credits sit on paths that run every step (Contract 6's cost clause). `swift`: for every wizard, `p.moving`;
  for a moving one who has not moved yet this second (every moving step for one without the card) also
  `Upgrades.level_of` (a call and a dictionary get), and two `floori` a step once `swift_moved` is set, about 0.27 us
  at most (the A4 cost review), about 1 us a step for four. `magnet`: for a gem in someone's reach only (after
  `best >= 0`), one `vel.length()`, about 0.06-0.09 us a pulled gem, and `Upgrades.magnet_mul` only when a pull starts
  (once a gem), then one comparison when a gem is taken; about 11 us a step at worst (120 gems pulled at once in a lull), under 0.3% of the 4000 us budget. Both cost more
  than a comparison because each must ask something the step does not keep for it: swift whether she holds the card
  and whether a second turned, magnet whether this gem's pull is just starting. `length_squared` would save only the
  square root, and `_magnets` works once a wizard, not once a gem, so the start test cannot move there.
  `sim_horde`'s five rows run both lines every step and hold their budget, within noise of main (the cost review
  found no row 8% slower).
- The coverage robot credits all twelve (`tests/bot/bot_cover.gd` has no `PENDING` row); `tests/bot/cover/catalog.gd`
  stages two: TEMPERANCE's wizard lacks a heart more than a potion gives back (the card as dealt), THE HERMIT's
  holds it at its top. Tests: `tests/unit/test_cast_hooks.gd`.

## The Reading (stage 3, job R1: the rows and the values path)
- `Readings` (`game/logic/readings.gd`, pure, the data file for the Reading's numbers): `ROWS` is the sixteen Minor Arcana of `docs/content_list.md` § 42 as `[key, name, words, party only, values]`. `deal(rng, open, seats, n)` draws n different open rows with its own rng (a PARTY card only for two seats or more, never a row of `UNBUILT`); `vote(votes, seats)` gives the hand index a table keeps (most votes, seat 1 breaks a tie, -1 abstains, nobody keeps 0).
- `World.apply_reading(key)` runs once after `apply_seal` (`arena.gd` passes `Net.reading`, the host's; tools take `--reading=<key>`). A value named in `Readings.MERGE_MUL` (`hp`, `horde`, `boss`, `speed`, `potions`) multiplies the Seal's `seal_<key>`, `hearts` is added to every wizard, and any other value sets `World.read_<key>` for the row's rule (job R2). `World.reading` holds the key and the snapshot header carries its index (`W_READING`, -1 for none), so every seat can show the card.
- A boss is a foe: a row whose words say FOES names `hp` and `boss`. EIGHT OF WANDS is one number, `read_pace`, the run's clock (R2 makes `step` play that many seconds for each second given); no other number moves with it.
- Credit (`Results.use(key)`): a Reading that is only merged numbers is credited when applied; one with a rule is credited where its rule fires. `Readings.UNBUILT` lists the rows whose rule is not built: they are never dealt, and the coverage robot's family `tests/bot/cover/readings.gd` plans them as unbuilt.

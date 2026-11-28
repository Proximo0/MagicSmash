# Content list

Part 1 is read from the code on 28 Nov 2026 at commit 64306bc0. Part 2 (from § 36) is the frozen list the game is
built to: what the finished game holds, what each row pairs with and how it is tested.
Every number is copied from the file named in the Source column (`game/...:line`); nothing is taken from another doc.
Test column of part 1: files in `tests/unit`, `tests/sim` and `tests/bot` that name the row (its key, name or
constant); `none` if no file does. Part 2's Test column is explained in § 36.
`(!)` marks a row that looks unfinished; the list of them is at the end.

## Part 1. As built on 28 Nov 2026

Counts (table rows, each checked against the code): Spells 9 · Evolutions 9 · Passives 8 · Instant picks 2 · Minor
Arcana 4 · Wizards 4 · Classes 5 · Class weapon skins 5 · Skills 5 · Races 4 · Race traits 4 · Team fates 8 · Solo
shrine outcomes 5 · Rarity tiers 5 · Chest items 10 · Pickups 16 · Monster cards 12 · Seal cards 8 · Enemy kinds 22 ·
Horde rows 18 · Formations 3 · Omens 3 · Bosses 3 · Boss attack names 20 · Hazard kinds 9 · Difficulty steps 11 · Seal
rules (inside the steps) 8 · Shop unlocks 6 · Sanctum things 10 · Sanctum pots 12 · Well fortunes 12 · Achievements 54
· Secrets 8 · Ouija words 12 · Result moments 10 · Awards 7 · Talk lines 36 · Acts 3 · Prologue pages 4 · Minute
banners 15 · Elite epithets 12

## 1. Spells

Per-level arrays read level 1/2/3/4/5 (`Spells.MAX_LEVEL` 5). Order is the `World.SP_*` index. `n` is bolts, jumps,
stars or circles per cast.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| ARCANE BOLT (`w_arcane`) | cast bolt; cd 0.16/0.15/0.14/0.13/0.12 s; dmg 2.6/2.75/2.8/2.9/3; n 1/1/2/2/3; speed 310; r 3; life 1; spread 0.12; jitter 0.04 | Start spell of wizard VIOLET (Wizards.ROSTER); the school of a MAGE hero who picks ARCANE BOLT; level-up card `w_arcane`, weight 9 | ASTRAL LANCE (with STARFALL) | game/logic/spells.gd:24; game/logic/upgrades.gd:93 | test_classes.gd, test_hero.gd, test_hero_screens.gd +5 |
| FIREBALL (`w_fire`) | cast bolt; cd 1.2/1.1/1/0.9/0.8 s; dmg 2.2/2.4/2.6/2.8/3; n 1/1/2/2/2; speed 200; r 4.5; life 1.6; spread 0.3; blast 28; blast_reach 40; blast_bonus 1.5 | Start spell of wizard CRIMSON; mage school; level-up card `w_fire`, weight 9 | THUNDERFIRE (with CHAIN LIGHTNING) | game/logic/spells.gd:26; game/logic/upgrades.gd:94 | test_achievements.gd, test_results.gd, test_smash_bot.gd +5 |
| FROST FAN (`w_frost`) | cast bolt; cd 1/0.95/0.9/0.85/0.8 s; dmg 2.4/2.65/2.8/3.1/3.5; n 3/4/5/6/7; speed 255; r 2.5; life 0.75; spread 0.17; slow 1.8 | Start spell of wizard EMERALD; mage school; level-up card `w_frost`, weight 9 | BLIZZARD (with ARCANE BOLT) | game/logic/spells.gd:29; game/logic/upgrades.gd:95 | test_kinds_crypt.gd, test_results.gd, test_spells.gd +2 |
| CHAIN LIGHTNING (`w_storm`) | cast chain; cd 0.9/0.8/0.7/0.65/0.6 s; dmg 3.1/3.45/3.8/4.3/5; n 3/4/5/6/7 | Start spell of wizard AMBER; mage school; level-up card `w_storm`, weight 9 | TEMPEST (with FIREBALL) | game/logic/spells.gd:31; game/logic/upgrades.gd:96 | test_classes.gd, test_hero.gd, test_upgrades.gd +2 |
| STARFALL (`w_star`) | cast bolt; cd 1.1/1/0.9/0.8/0.7 s; dmg 3.4/3.55/3.7/3.9/4.2; n 2/2/3/3/4; speed 175; r 3; life 2.2; spread 0.45; home 160; turn 5.5 | Level-up card `w_star`, weight 9; the PALADIN's class weapon (skin SMITE) | COMET RAIN (with FROST FAN) | game/logic/spells.gd:33; game/logic/upgrades.gd:97 | test_classes.gd, test_kinds_crypt.gd, test_spells.gd +3 |
| RUNE CIRCLE (`w_rune`) | cast rune; cd 2.6/2.4/2.2/2/1.8 s; dmg 0.66/0.8/0.92/1.08/1.25; n 1/1/2/2/3; r 14/16/18/20/22; life 2/2/2.25/2.5/2.5 | Level-up card `w_rune`, weight 9 | SEAL OF SOLOMON (with STARFALL) | game/logic/spells.gd:35; game/logic/upgrades.gd:98 | sim/sim_horde.gd, test_achievements.gd, test_spells.gd +3 |
| BONE SPEAR (`w_bone`) | cast bolt; cd 1.5/1.4/1.25/1.1/1 s; dmg 3/3.5/4/4.5/5; n 2/2/2/2/2; speed 275; r 3; life 0.8; spread 0.3; pierce -1 | Level-up card `w_bone`, weight 9; the ARCHER's class weapon (skin LONGBOW) | OSSUARY LANCE (with passive JUSTICE) | game/logic/spells.gd:38; game/logic/upgrades.gd:110 | sim/sim_horde.gd, test_classes.gd, test_hero_screens.gd +2 |
| VIGIL CANDLE (`w_candle`) | cast candle; cd 2/2/2/2/2 s; dmg 0.8/0.85/0.9/0.95/1; n 1/1/1/1/1; r 32; life 3.5 | Level-up card `w_candle`, weight 9; the PRIEST's class weapon (skin HOLY LIGHT) | CONSECRATION (with passive THE LOVERS) | game/logic/spells.gd:40; game/logic/upgrades.gd:111 | sim/sim_horde.gd, test_classes.gd, test_world_fallen.gd +1 |
| CLEAVE (`w_cleave`) | cast sweep; cd 0.9/0.85/0.8/0.75/0.7 s; dmg 9/11/13.5/16.5/20; n 1/1/1/1/1; r 34; arc 1.745 | The KNIGHT's class weapon; its card `w_cleave` requires itself, so only a knight is ever offered it | WHIRLWIND (with passive STRENGTH) | game/logic/spells.gd:42; game/logic/upgrades.gd:118 | sim/sim_horde.gd, test_classes.gd, test_smash_bot.gd +4 |

Spell tuning constants shared by all rows (spells.gd:77-121): CAST_FLOOR 0.35 (least a cooldown can fall to),
BOLT_KNOCK 70, BLAST_KNOCK 160, CHAIN_FIRST_RANGE 140, CHAIN_JUMP_RANGE 70, CHAIN_FALLOFF 0.85, RUNE_TICK 0.5,
VIGIL_HASTE 0.2 for 2 s after leaving a light, SWEEP_KNOCK 120.

## 2. Evolutions

An evolution replaces its spell's level-5 numbers. It is offered when the spell is at level 5 and the partner is owned
(level 1 or more); the card weighs 40 and a row that completes a pair weighs x4 more in the roll
(`Upgrades.PARTNER_WEIGHT`).

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| ASTRAL LANCE (`e_arcane`) | PIERCING BOLTS; cd 0.11 s; dmg 3; n 3; pierce 2 | Base spell ARCANE BOLT at level 5 + STARFALL at level 1+; card `e_arcane`, weight 40 | STARFALL | game/logic/spells.gd:56; game/logic/upgrades.gd:99 | test_world_builds.gd |
| THUNDERFIRE (`e_fire`) | ZAPPING BLASTS; cd 0.9 s; dmg 3; n 3; chain 3 | Base spell FIREBALL at level 5 + CHAIN LIGHTNING at level 1+; card `e_fire`, weight 40 | CHAIN LIGHTNING | game/logic/spells.gd:58; game/logic/upgrades.gd:100 | test_world_builds.gd |
| BLIZZARD (`e_frost`) | A STORM OF ICE; cd 0.7 s; dmg 3.2; n 9; pierce 1; slow 3.5 | Base spell FROST FAN at level 5 + ARCANE BOLT at level 1+; card `e_frost`, weight 40 | ARCANE BOLT | game/logic/spells.gd:60; game/logic/upgrades.gd:101 | test_world_builds.gd |
| TEMPEST (`e_storm`) | TWIN CHAINS; cd 0.5 s; dmg 4.4; n 9; chains 2 | Base spell CHAIN LIGHTNING at level 5 + FIREBALL at level 1+; card `e_storm`, weight 40 | FIREBALL | game/logic/spells.gd:62; game/logic/upgrades.gd:102 | test_still.gd, test_world_builds.gd |
| COMET RAIN (`e_star`) | ICY STARBURSTS; cd 0.6 s; dmg 3; n 5; burst 30 | Base spell STARFALL at level 5 + FROST FAN at level 1+; card `e_star`, weight 40 | FROST FAN | game/logic/spells.gd:64; game/logic/upgrades.gd:103 | none |
| SEAL OF SOLOMON (`e_rune`) | SIGILS PULL IN; cd 1.4 s; dmg 1; n 3; r 32; life 3.5; pull 42 | Base spell RUNE CIRCLE at level 5 + STARFALL at level 1+; card `e_rune`, weight 40 | STARFALL | game/logic/spells.gd:66; game/logic/upgrades.gd:104 | none |
| OSSUARY LANCE (`e_bone`) | SPLINTER HITS; cd 0.9 s; dmg 5.5; n 3; splinter 2 | Base spell BONE SPEAR at level 5 + passive JUSTICE (`justice`) at level 1+; card `e_bone`, weight 40 | passive JUSTICE | game/logic/spells.gd:68; game/logic/upgrades.gd:116 | test_classes.gd, test_world_wave3.gd |
| CONSECRATION (`e_candle`) | HEALING LIGHT; cd 1.8 s; dmg 1.8; n 2; r 32; life 3.5; heal_every 10 | Base spell VIGIL CANDLE at level 5 + passive THE LOVERS (`lovers`) at level 1+; card `e_candle`, weight 40 | passive THE LOVERS | game/logic/spells.gd:70; game/logic/upgrades.gd:117 | test_world_wave3.gd |
| WHIRLWIND (`e_cleave`) | A FULL CIRCLE; cd 0.55 s; dmg 36; n 1; r 60; arc TAU (full circle); most 3 | Base spell CLEAVE at level 5 + passive STRENGTH (`power`) at level 1+; card `e_cleave`, weight 40; knight only | passive STRENGTH | game/logic/spells.gd:72; game/logic/upgrades.gd:119 | sim/sim_horde.gd, test_smash_bot.gd, test_world_wave3.gd |

## 3. Passives (Major Arcana), level-up picks

A passive takes a passive slot (3 until the first boss falls, 4 after: `Upgrades.SLOTS_EARLY/LATE`). Values read level
1/2/...; max level is the number of values. Each is drawn as a Major Arcana card (TarotArt).

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| THE CHARIOT (`swift`) | move speed x1.08/1.16/1.24/1.32/1.4; card text "MOVE FASTER" | Level-up card, weight 10, max level 5 | none | game/logic/upgrades.gd:85 | test_smash_bot.gd, test_still.gd, test_upgrades.gd +1 |
| THE MAGICIAN (`quick`) | spell cooldowns x0.92/0.85/0.79/0.74/0.7 (never below CAST_FLOOR 0.35 of base); card text "CAST FASTER" | Level-up card, weight 10, max level 5 | none | game/logic/upgrades.gd:86 | test_arena_tray.gd, test_smash_bot.gd, test_upgrades.gd +2 |
| STRENGTH (`power`) | damage x1.15/1.3/1.45/1.6/1.8; card text "MORE DAMAGE" | Level-up card, weight 10, max level 5 | evolution WHIRLWIND (knight) | game/logic/upgrades.gd:87 | test_arena_tray.gd, test_smash_bot.gd, test_upgrades.gd +3 |
| TEMPERANCE (`regen`) | one heart regained every 18/12/8 s; card text "HEAL OVER TIME" | Level-up card, weight 6, max level 3 | none | game/logic/upgrades.gd:88 | test_world_builds.gd |
| THE MOON (`magnet`) | XP pull range x1.6/2.2/3; card text "WIDER XP PULL" | Level-up card, weight 7, max level 3 | none | game/logic/upgrades.gd:89 | test_smash_bot.gd, test_upgrades.gd |
| THE HERMIT (`wisdom`) | XP gained x1.15/1.3/1.5; card text "MORE XP" | Level-up card, weight 7, max level 3 | none | game/logic/upgrades.gd:90 | none |
| JUSTICE (`justice`) | chance 0.06/0.12/0.18 that a slain foe bursts for 0.6 of its max health within 30 px (JUSTICE_SHARE, JUSTICE_RADIUS); card text "FOES BURST" | Level-up card, weight 7, max level 3 | evolution OSSUARY LANCE (with BONE SPEAR) | game/logic/upgrades.gd:113 | test_world_wave3.gd |
| THE LOVERS (`lovers`) | cast speed +0.08/0.16/0.24 within 60 px of an ally (an apprentice counts); half of it when alone (LOVERS_ALONE 0.5); card text "HASTE TOGETHER" | Level-up card, weight 7, max level 3 | evolution CONSECRATION (with VIGIL CANDLE) | game/logic/upgrades.gd:115 | test_world_wave3.gd |

## 4. Instant picks (Major Arcana)

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| THE TOWER (`nova`) | adds 1 nova charge at once (p.bombs +1); card text "+1 NOVA NOW" | Level-up card, weight 5, max level 5 | none | game/logic/upgrades.gd:91 | test_input_pause.gd, test_smash_bot.gd, test_world_builds.gd |
| JUDGEMENT (`life`) | adds 1 life at once (p.lives +1); card text "+1 LIFE NOW" | Level-up card, weight 3, max level 2; banned by DARKNESS (world.gd:556) | none | game/logic/upgrades.gd:92 | test_smash_bot.gd, test_spells.gd, test_world.gd +1 |

## 5. Minor Arcana (filler cards)

Never rolled by weight (1.0 each): they fill a hand that would be short of cards to learn; taken any number of times.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| CUPS (`cups`) (!) text and effect differ | heals 1 heart (hp +1, capped at max; max hearts unchanged); card text "+1 HEART" | Dealt into a short level-up hand only (Upgrades.minor_fill) | none | game/logic/upgrades.gd:106 | test_arena_tray.gd, test_still.gd, test_world_builds.gd |
| PENTACLES (`pentacles`) | +10 gold (x greed and meta gold bonus); card text "+10 GOLD" | Dealt into a short level-up hand only (Upgrades.minor_fill) | none | game/logic/upgrades.gd:107 | test_world_builds.gd |
| SWORDS (`swords`) | +1 nova charge; card text "+1 NOVA" | Dealt into a short level-up hand only (Upgrades.minor_fill) | none | game/logic/upgrades.gd:108 | test_still.gd, test_world_builds.gd |
| WANDS (`wands`) | +3% damage per card (multiplies STRENGTH); card text "+3% DAMAGE" | Dealt into a short level-up hand only (Upgrades.minor_fill) | none | game/logic/upgrades.gd:109 | test_world_builds.gd |

Level-up rules (upgrades.gd:66-72): hand of 3 cards (tuning.gd `level_choices` 3); redraws 2 and banishes 2 per wizard
per run; slots 3 spells + 3 passives, 4 + 4 after the first boss. The CATALOG has 32 rows: 8 passives, 2 instants, 9
spells, 9 evolutions, 4 minor.

## 6. Wizards (lobby robes)

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| VIOLET, ARCANIST (index 0) | Robe colour; starts the run with ARCANE BOLT at level 1 (the code has no other trait field) | Picked in the lobby; no two wizards in a party are the same | Start spell ARCANE BOLT | game/logic/wizards.gd:9 | test_boss_ghostwriter.gd, test_classes.gd, test_wizards.gd +2 |
| CRIMSON, PYROMANCER (index 1) | Robe colour; starts the run with FIREBALL at level 1 (the code has no other trait field) | Picked in the lobby; no two wizards in a party are the same | Start spell FIREBALL | game/logic/wizards.gd:10 | test_classes.gd, test_wizards.gd, test_world.gd +1 |
| EMERALD, FROSTWARDEN (index 2) | Robe colour; starts the run with FROST FAN at level 1 (the code has no other trait field) | Picked in the lobby; no two wizards in a party are the same | Start spell FROST FAN | game/logic/wizards.gd:11 | test_boss_ghostwriter.gd, test_classes.gd, test_wizards.gd +2 |
| AMBER, STORMCALLER (index 3) | Robe colour; starts the run with CHAIN LIGHTNING at level 1 (the code has no other trait field) | Picked in the lobby; no two wizards in a party are the same | Start spell CHAIN LIGHTNING | game/logic/wizards.gd:12 | test_classes.gd, test_wizards.gd, test_world.gd +1 |

## 7. Hero classes

A hero is a saved profile row (race, class, school, look, class level 1-20, stat points). Up to 8 heroes per profile
(`Profile.MAX_HEROES`). No unlock gate on a class or race was found in the logic or the builder: all are chosen when a
hero is built (`Hero.make`).

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| MAGE (`mage`) | DAMAGE; 5 hearts; weapon the school's spell (ARCANE BOLT, FIREBALL, FROST FAN or CHAIN LIGHTNING), skin staff (the spell as is); nova button = NOVA; threat 1; stat points FOCUS 2; walk x1; rituals x1; extra redraws 2; hit-safe 1.1 s | Chosen in the hero builder | weapon row school spell | game/logic/classes.gd:47 | bot/bot_heroes.gd, test_achievements.gd, test_career.gd +9 |
| KNIGHT (`knight`) | TANK; 9 hearts; weapon CLEAVE, skin CLEAVE {dmg_mul: 1.2, cd_mul: 0.85, knock_mul: 2.5}; nova button = PROVOKE; threat 2.5; stat points MIGHT 5, FOCUS 2, WARD 2; walk x0.94; rituals x1; extra redraws 0; hit-safe 2 s | Chosen in the hero builder | weapon row CLEAVE; evolution WHIRLWIND | game/logic/classes.gd:48 | bot/bot_heroes.gd, test_achievements.gd, test_career.gd +11 |
| ARCHER (`archer`) | RANGED; 5 hearts; weapon BONE SPEAR, skin LONGBOW {range: 260.0, dmg_mul: 1.5, cd_mul: 0.5}; nova button = VOLLEY; threat 0.8; stat points MIGHT 1, FOCUS 1, SWIFT 1; walk x1.08; rituals x1; extra redraws 0; hit-safe 1.6 s | Chosen in the hero builder | weapon row BONE SPEAR; evolution OSSUARY LANCE | game/logic/classes.gd:49 | bot/bot_heroes.gd, test_achievements.gd, test_classes.gd +6 |
| PRIEST (`priest`) (!) MIGHT 25 | HEALER; 6 hearts; weapon VIGIL CANDLE, skin HOLY LIGHT {heal: 1, heal_every: 6.0, dmg_mul: 1.3}; nova button = SANCTUARY; threat 0.7; stat points MIGHT 25, FOCUS 1, WARD 2; walk x1; rituals x2; extra redraws 0; hit-safe 1.1 s | Chosen in the hero builder | weapon row VIGIL CANDLE; evolution CONSECRATION | game/logic/classes.gd:50 | bot/bot_heroes.gd, test_achievements.gd, test_career.gd +8 |
| PALADIN (`paladin`) | TANK AND SUPPORT; 6 hearts; weapon STARFALL, skin SMITE {dmg_mul: 1.6, cd_mul: 0.55}; nova button = AEGIS; threat 1.6; stat points MIGHT 1, WARD 1; walk x1; rituals x1; extra redraws 0; hit-safe 1.1 s; aura 50 px gives WARD +8 | Chosen in the hero builder | weapon row STARFALL; evolution COMET RAIN | game/logic/classes.gd:51 | test_achievements.gd, test_classes.gd, test_hero.gd +4 |

## 8. Class weapon skins and skills

Skins (classes.gd:62): how a class weapon differs. Skills (classes.gd:83): what the nova button does; each spends one
nova charge.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| STAFF skin (`staff`) | no change (the spell as it is) | Class weapon of the MAGE | none | game/logic/classes.gd:63 | none |
| CLEAVE skin (`cleave`) | dmg_mul 1.2, cd_mul 0.85, knock_mul 2.5 | Class weapon of the KNIGHT | none | game/logic/classes.gd:64 | test_world_wave3.gd |
| LONGBOW skin (`longbow`) | range 260, dmg_mul 1.5, cd_mul 0.5 | Class weapon of the ARCHER | none | game/logic/classes.gd:65 | test_classes.gd, test_hero_screens.gd, test_world_wave3.gd |
| HOLY LIGHT skin (`holy_light`) | heal 1, heal_every 6, dmg_mul 1.3 | Class weapon of the PRIEST | none | game/logic/classes.gd:66 | test_classes.gd, test_world_wave3.gd |
| SMITE skin (`smite`) | dmg_mul 1.6, cd_mul 0.55 | Class weapon of the PALADIN | none | game/logic/classes.gd:67 | test_world_wave3.gd |

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| NOVA (`nova`) | NOVA: numbers live in WorldPlayers._nova, not in the table | Nova button of the MAGE | none | game/logic/classes.gd:84 | test_classes.gd, test_still.gd, test_world_apprentice.gd |
| PROVOKE (`provoke`) | enemies within radius want the caster for taunt s; she takes no damage for safe s; radius 100, taunt 5, safe 2 | Nova button of the KNIGHT | none | game/logic/classes.gd:85 | test_classes.gd, test_still.gd, test_world_apprentice.gd |
| VOLLEY (`volley`) | a roll of 50 px along her movement (safe s unhurt), then arrows fanned behind her; roll 50, safe 0.4, arrows 12, fan 1.75, speed_mul 1 | Nova button of the ARCHER | none | game/logic/classes.gd:86 | test_classes.gd, test_still.gd |
| SANCTUARY (`sanctuary`) | every standing hero heals 2 hearts; the fallen within radius rise; heal 2, radius 80 | Nova button of the PRIEST | none | game/logic/classes.gd:87 | test_classes.gd, test_still.gd |
| AEGIS (`aegis`) | heroes within radius take no damage for safe s; radius 60, safe 3 | Nova button of the PALADIN | none | game/logic/classes.gd:88 | test_classes.gd, test_still.gd |

## 9. Hero races (with their traits)

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| HUMAN (`human`) | Stat points MIGHT 1, FOCUS 1, SWIFT 1, VIGOR 1, WARD 1, FORTUNE 1; build MEDIUM; trait `scholar`: +5% CLASS XP (value 0.05) | Chosen in the hero builder | none | game/logic/races.gd:40 | bot/bot_heroes.gd, test_achievements.gd, test_career.gd +9 |
| ELF (`elf`) | Stat points FOCUS 3, SWIFT 4; build MEDIUM; trait `far_sight`: XP FLIES IN FROM 25% FARTHER (value 0.25) | Chosen in the hero builder | none | game/logic/races.gd:41 | bot/bot_heroes.gd, test_achievements.gd, test_classes.gd +6 |
| DWARF (`dwarf`) | Stat points VIGOR 4, WARD 3; build SHORT; trait `sturdy`: UNHURT 50% LONGER AFTER A HIT (value 0.5) | Chosen in the hero builder | none | game/logic/races.gd:42 | bot/bot_heroes.gd, test_achievements.gd, test_classes.gd +3 |
| ORC (`orc`) | Stat points MIGHT 5, VIGOR 2; build TALL; trait `fury`: +10% DAMAGE AT 2 HEARTS OR FEWER (value 0.1) | Chosen in the hero builder | none | game/logic/races.gd:43 | bot/bot_heroes.gd, test_achievements.gd, test_classes.gd +6 |

Hero facts (hero.gd:8-26): class level 1-20; XP to next level = 100 x level; 1 stat point per level past the first, at
most 10 in one stat; class XP per run: 10 per whole minute, 50 per boss, 150 for a win, times the Seal's crystal
multiplier. One stat point is worth: MIGHT +2% damage, FOCUS +1% cast speed, SWIFT +1% move speed, VIGOR a quarter
heart, WARD +1% shrug chance, FORTUNE +3% gold. Look: 4 skins x 6 hairs x 3 styles; schools: the 4 robe spells.

## 10. Team fates (the fate deck)

A team shrine (party of 2 or more): the table pays tuning `team_cost_mul` 1.5 x the solo cost into one pot (two
living wizards must stand in it, an apprentice never counts; the price takes `team_pay_time` 2 s in equal parts; a
shrine that fades unpaid gives the gold back; test_team_shrine.gd) and a tarot card is turned. A fate is drawn
from a side: the cruel side with chance `fate_cruel` (0.5; 0.6 from SEAL VI MISFORTUNE), then each fate of that
side equally likely (WHEEL OF FORTUNE is left out of a chain it started). In a solo run a team shrine plays the old
weighted roll: PARTY BLESSED 50, PARTY CURSED 50.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| PARTY BLESSED! (`blessing`, tarot `sun`, id 0) | every wizard gains 2 levels (BLESSING_LEVELS) (reel line "EVERY WIZARD GAINS %d LEVELS") | good side; solo-run weight 50; a party draws it at the team shrine (weight is not used in a party) | tarot card THE SUN | game/logic/gamble.gd:37 | test_fate.gd, test_gamble.gd, test_world.gd |
| PARTY CURSED! (`curse`, tarot `death`, id 1) | every wizard loses a heart and an elite comes for each of them (reel line "A HEART LOST AND AN ELITE FOR EACH WIZARD") | cruel side; solo-run weight 50; a party draws it at the team shrine (weight is not used in a party) | tarot card DEATH | game/logic/gamble.gd:38 | test_fate.gd, test_gamble.gd, test_world.gd +1 |
| THE WORLD! (`world`, tarot `world`, id 2) (!) no picture | every XP gem flies to the party for 3 s; all heal 2 hearts (reel line "EVERY GEM FLIES IN, ALL HEAL %d HEARTS") | good side; solo-run weight 0; a party draws it at the team shrine (weight is not used in a party) | tarot card THE WORLD | game/logic/gamble.gd:39 | bot/bot.gd, test_fate.gd |
| THE EMPEROR! (`emperor`, tarot `emperor`, id 3) (!) no picture | a chest for each human wizard (reel line "A CHEST FOR EACH WIZARD") | good side; solo-run weight 0; a party draws it at the team shrine (weight is not used in a party) | tarot card THE EMPEROR | game/logic/gamble.gd:40 | test_fate.gd, test_gamble.gd |
| THE FOOL! (`fool`, tarot `fool`, id 4) | the next fate drawn counts twice (reel line "THE NEXT FATE COUNTS TWICE") | good side; solo-run weight 0; a party draws it at the team shrine (weight is not used in a party) | tarot card THE FOOL | game/logic/gamble.gd:41 | test_fate.gd, test_gamble.gd |
| HANGED MAN! (`hanged`, tarot `hanged`, id 5) (!) no picture | novas sealed for 60 s (tuning.gd:115) (reel line "NOVAS SEALED FOR %d SECONDS") | cruel side; solo-run weight 0; a party draws it at the team shrine (weight is not used in a party) | tarot card THE HANGED MAN | game/logic/gamble.gd:42 | test_fate.gd, test_gamble.gd |
| HIEROPHANT! (`hierophant`, tarot `hierophant`, id 6) (!) no picture | no potions drop for 90 s (tuning.gd:116) (reel line "NO POTIONS DROP FOR %d SECONDS") | cruel side; solo-run weight 0; a party draws it at the team shrine (weight is not used in a party) | tarot card THE HIEROPHANT | game/logic/gamble.gd:43 | test_fate.gd |
| WHEEL TURNS! (`wheel`, tarot `wheel`, id 7) (!) no picture | 2 more fates are drawn at once (tuning.gd:117) (reel line "%d MORE FATES ARE DRAWN AT ONCE") | cruel side; solo-run weight 0; a party draws it at the team shrine (weight is not used in a party) | tarot card WHEEL OF FORTUNE | game/logic/gamble.gd:44 | test_fate.gd, test_gamble.gd |

## 11. Solo shrine outcomes

A gamble shrine: first at 40 s of fighting, then every 25 s (tuning.gd); costs 60 gold in minute 1 plus 25 per minute;
stays 50 s. Pays run gold only. One roll over these weights (total 100).

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| JACKPOT! (`jackpot`, id 0) | a lucky chest (luck from `boss_chest_luck` 3); weight 12 of 100 | Pay at a gamble shrine, solo run | none | game/logic/gamble.gd:17 | none |
| TREASURE (`chest`, id 1) | a plain chest (luck from `elite_chest_luck` 1); weight 30 of 100 | Pay at a gamble shrine, solo run | none | game/logic/gamble.gd:18 | none |
| DOUBLE GOLD (`double`, id 2) | the stake back twice; weight 18 of 100 | Pay at a gamble shrine, solo run | none | game/logic/gamble.gd:19 | none |
| NOTHING... (`nothing`, id 3) | nothing; weight 22 of 100 | Pay at a gamble shrine, solo run | none | game/logic/gamble.gd:20 | none |
| CURSED! (`curse`, id 4) | lose a heart (never the last one); weight 18 of 100 | Pay at a gamble shrine, solo run | none | game/logic/gamble.gd:21 | none |

## 12. Rarity tiers

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| COMMON (tier 0) | Chest weight 60; item value x1 | Plain chests | none | game/logic/loot.gd:13; weights :17; multipliers :19 | test_loot.gd, test_world.gd |
| RARE (tier 1) | Chest weight 26; item value x1.5 | Chests; a kill drops a rare (blue) chest at tuning `rare_drop_chance` 0.0015 | none | game/logic/loot.gd:13; weights :17; multipliers :19 | test_loot.gd, test_world.gd |
| EPIC (tier 2) | Chest weight 10; item value x2 | Chests, more with luck | none | game/logic/loot.gd:13; weights :17; multipliers :19 | test_loot.gd, test_world.gd |
| LEGENDARY (tier 3) | Chest weight 0.3; item value x3 | Chests, more with luck (about 1 run in 6 solo, per the source comment) | none | game/logic/loot.gd:13; weights :17; multipliers :19 | test_achievements.gd, test_loot.gd, test_world_seals.gd |
| ULTRA RARE (tier 4) | Chest weight 0; item value x5 | Never rolled: given only by the prismatic chest of an ULTRA RARE run (tuning `ultra_run_chance` 0.01, cap 0.03); not under APPRENTICE | none | game/logic/loot.gd:13; weights :17; multipliers :19 | test_achievements.gd, test_loot.gd, test_results.gd +1 |

## 13. Chest items

Value = base x tier multiplier (VIGOR rounds down to whole hearts, at least 1). Armor stats add up for the rest of the
run, capped by `Loot.STAT_CAPS` [MIGHT 2.0, FOCUS 0.5, SWIFT 0.6, VIGOR 5, WARD 0.5, GREED 3.0]. A flat item (ELIXIR)
is never rolled at LEGENDARY or above.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| GAUNTLETS OF TYR (`might`, id 0) | armor +damage 0.08 x tier | Chest drop, weight 10 | none | game/logic/loot.gd:43 | bot/bot_heroes.gd, test_profile.gd |
| CIRCLET OF THOTH (`focus`, id 1) | armor -cooldown 0.05 x tier | Chest drop, weight 10 | none | game/logic/loot.gd:44 | none |
| HERMES' SANDALS (`swift`, id 2) | armor +move speed 0.05 x tier | Chest drop, weight 8 | none | game/logic/loot.gd:45 | test_still.gd |
| TROLL HIDE (`vigor`, id 3) | armor +hearts 1 x tier | Chest drop, weight 6 | none | game/logic/loot.gd:46 | bot/bot_heroes.gd, test_profile.gd |
| AEGIS CLOAK (`ward`, id 4) | armor +shrug chance 0.06 x tier | Chest drop, weight 7 | none | game/logic/loot.gd:47 | none |
| MISER'S RING (`greed`, id 5) | armor +run gold 0.15 x tier | Chest drop, weight 6 | none | game/logic/loot.gd:48 | none |
| ELIXIR (`elixir`, id 6) | consumable: heals to full (strength 1 x tier, flat) | Chest drop, weight 8 | none | game/logic/loot.gd:49 | test_loot.gd |
| NOVA FLASK (`novas`, id 7) | consumable: adds novas (strength 1 x tier) | Chest drop, weight 7 | none | game/logic/loot.gd:50 | test_profile.gd |
| SIBYLLINE BOOK (`tome`, id 8) | consumable: levels a random owned spell weapon that is not maxed (strength 1 x tier) | Chest drop, weight 7 | none | game/logic/loot.gd:51 | none |
| EYE OF ODIN (`insight`, id 9) | consumable: XP worth a fraction of the current level (strength 0.5 x tier) | Chest drop, weight 6 | none | game/logic/loot.gd:52 | none |

## 14. Pickups (floor drops)

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| GOLD COIN (`World.PK_COIN`) | 1 gold (x greed) and 100 points | Kill drop, chance `coin_drop_chance` 0.1; urn | none | game/logic/world.gd:34 | test_world.gd, test_world_apprentice.gd |
| GOLD GEM (`World.PK_GEM`) | 5 gold (x greed) and 500 points | Kill drop (0.05 band); orc and mage always; urn | none | game/logic/world.gd:35 | test_kinds_crypt.gd, test_world.gd, test_world_apprentice.gd |
| POTION (`World.PK_POTION`) | heals 2 hearts (1 under SEAL III FAMINE; apprentices take one only when hurt to 2 hearts or fewer) | Kill drop, `potion_drop_chance` 0.05; urn 6%; none while THE HIEROPHANT holds | none | game/logic/world.gd:36 | test_boss_ghostwriter.gd, test_fate.gd, test_smash_bot.gd +2 |
| SPELL TOME (fireball) (`World.PK_TOME_FIRE`) | grants or levels FIREBALL if slots allow, else 500 points | Does not drop at default tuning (tuning.gd:49 `floor_tomes` 0; the party tome replaces them) | none | game/logic/world.gd:37 | test_world.gd, test_world_apprentice.gd |
| SPELL TOME (frost) (`World.PK_TOME_FROST`) | grants or levels FROST FAN, else 500 points | Does not drop at default tuning (tuning.gd:49 `floor_tomes` 0; the party tome replaces them) | none | game/logic/world.gd:38 | test_world_builds.gd |
| SPELL TOME (storm) (`World.PK_TOME_STORM`) | grants or levels CHAIN LIGHTNING, else 500 points | Does not drop at default tuning (tuning.gd:49 `floor_tomes` 0; the party tome replaces them) | none | game/logic/world.gd:39 | none |
| SPELL TOME (star) (`World.PK_TOME_STAR`) | grants or levels STARFALL, else 500 points | Does not drop at default tuning (tuning.gd:49 `floor_tomes` 0; the party tome replaces them) | none | game/logic/world.gd:40 | none |
| BOOTS (`World.PK_BOOTS`) | haste for 10 s | Rare kill drop (0.007 band); timed floor powerup | none | game/logic/world.gd:41 | none |
| ORBIT (`World.PK_ORBIT`) | orbiting damage for 12 s (damage source ORBIT) | Rare kill drop (0.008 band); timed floor powerup | none | game/logic/world.gd:42 | none |
| XP GEM (`World.PK_XP`) | experience | Kill drop (every kill) | none | game/logic/world.gd:43 | test_fate.gd, test_kinds_crypt.gd, test_smash_bot.gd +1 |
| CHEST (`World.PK_CHEST`) | opens at once: a tier from luck, then an item (Loot) | Elite, Lich, solo JACKPOT / TREASURE, THE EMPEROR | none | game/logic/world.gd:44 | test_fate.gd, test_world.gd, test_world_apprentice.gd +2 |
| SPELL TOME (rune) (`World.PK_TOME_RUNE`) | grants or levels RUNE CIRCLE, else 500 points | Does not drop at default tuning (tuning.gd:49 `floor_tomes` 0; the party tome replaces them) | none | game/logic/world.gd:45 | test_world.gd, test_world_apprentice.gd |
| MONSTER CARD (`World.PK_CARD`) | a monster card kept in the collection (Cards index) | Card run (1 run in 100): one card, first kill of its kind after a seeded moment, or in an urn | none | game/logic/world.gd:46 | test_world.gd, test_world_apprentice.gd, test_world_seals.gd |
| RARE CHEST (blue) (`World.PK_CHEST_RARE`) | opens RARE or better | Any kill at `rare_drop_chance` 0.0015; urn at `urn_rare_chance` 0.03 | none | game/logic/world.gd:47 | test_world.gd, test_world_apprentice.gd |
| PRISMATIC CHEST (`World.PK_CHEST_ULTRA`) | opens LEGENDARY or better (ULTRA RARE unless APPRENTICE) | The one chest of an ULTRA RARE run | none | game/logic/world.gd:48 | test_world.gd, test_world_apprentice.gd, test_world_seals.gd |
| PARTY TOME (`World.PK_TOME_PARTY`) | levels a random owned spell of every wizard | Each Lich drops one; elite chance `party_tome_elite` 1.0; urn `party_tome_urn` 0.02 (floor_tomes 0) | none | game/logic/world.gd:49 | test_world_builds.gd |

## 15. Monster cards

Collected between runs; one card goes in each socket (HAT, ROBE, STAFF) of the active hero and adds its stat to every
run. A card fits only its own socket. Earned only by play: about 1 run in 100 is a card run (tuning `card_run_chance`
0.01 x the Seal's card odds; 15% of card runs hide the card in an urn); a sealed deck at the reliquary costs 1500
crystals; a broken Sanctum pot holds one at 0.1%.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| THE CUTPURSE (`goblin`, index 0) | ROBE socket; run gold 0.15 ("+15% GOLD"); lore "IT ALWAYS KNOWS WHICH POCKET." | Drops from kills of GOBLIN in a card run; Sanctum pots, sealed deck | monster GOBLIN | game/logic/cards.gd:20 | none |
| THE SENTINEL (`skeleton`, index 1) | ROBE socket; shrug (ward) 0.06 ("6% WARD"); lore "IT STILL GUARDS A GATE LONG GONE." | Drops from kills of SKELETON in a card run; Sanctum pots, sealed deck | monster SKELETON | game/logic/cards.gd:21 | none |
| THE OOZE (`slime`, index 2) | ROBE socket; hearts 1 ("+1 HEART"); lore "WHAT IT SWALLOWS, IT KEEPS." | Drops from kills of SLIME in a card run; Sanctum pots, sealed deck | monster SLIME | game/logic/cards.gd:22 | bot/bot_heroes.gd, test_profile.gd |
| THE DROPLET (`mslime`, index 3) (!) no painted card | HAT socket; move speed 0.06 ("+6% SPEED"); lore "SMALL, QUICK AND EVERYWHERE." | Drops from kills of SLIMELING in a card run; Sanctum pots, sealed deck | monster SLIMELING | game/logic/cards.gd:23 | none |
| THE NIGHT WING (`bat`, index 4) | HAT socket; move speed 0.1 ("+10% SPEED"); lore "IT HAS NEVER SEEN THE SUN." | Drops from kills of BAT in a card run; Sanctum pots, sealed deck | monster BAT | game/logic/cards.gd:24 | bot/bot_heroes.gd, test_hero.gd, test_profile.gd |
| THE WARCHIEF (`orc`, index 5) | STAFF socket; damage 0.1 ("+10% DAMAGE"); lore "HE COUNTS HIS VICTORIES IN TEETH." | Drops from kills of ORC BRUTE in a card run; Sanctum pots, sealed deck | monster ORC BRUTE | game/logic/cards.gd:25 | bot/bot_heroes.gd, test_hero.gd, test_profile.gd +1 |
| THE HEXER (`mage`, index 6) | STAFF socket; cooldown 0.06 ("-6% COOLDOWN"); lore "A CURSE FOR EVERY OCCASION." | Drops from kills of DARK MAGE in a card run; Sanctum pots, sealed deck | monster DARK MAGE | game/logic/cards.gd:26 | test_classes.gd |
| THE LICH (`lich`, index 7) | STAFF socket; damage 0.2 ("+20% DAMAGE"); lore "DEATH WAS ONLY A DOORWAY." | Drops from kills of LICH LORD in a card run; Sanctum pots, sealed deck | monster LICH LORD | game/logic/cards.gd:27 | test_cards.gd, test_profile.gd, test_sanctum.gd +1 |
| THE WRAITH (`wraith`, index 8) | ROBE socket; shrug (ward) 0.1 ("10% WARD"); lore "HALF HERE. HALF ELSEWHERE." | Drops from kills of WRAITH in a card run; Sanctum pots, sealed deck | monster WRAITH | game/logic/cards.gd:28 | none |
| THE GRIMOIRE (`tome`, index 9) | HAT socket; cooldown 0.08 ("-8% COOLDOWN"); lore "IT READS YOU BACK." | Drops from kills of CURSED TOME in a card run; Sanctum pots, sealed deck | monster CURSED TOME | game/logic/cards.gd:29 | none |
| THE GARGOYLE (`gargoyle`, index 10) | ROBE socket; hearts 2 ("+2 HEARTS"); lore "STONE BY DAY. HUNGRY BY NIGHT." | Drops from kills of GARGOYLE in a card run; Sanctum pots, sealed deck | monster GARGOYLE | game/logic/cards.gd:30 | test_hero.gd |
| THE BONE PRIEST (`priest`, index 11) | HAT socket; damage 0.08 ("+8% DAMAGE"); lore "HIS SERMONS RAISE THE DEAD." | Drops from kills of BONE PRIEST in a card run; Sanctum pots, sealed deck | monster BONE PRIEST | game/logic/cards.gd:31 | test_classes.gd, test_profile.gd |

## 16. Seal cards

One per Seal, paid on its first win at that Seal; the Archlich also drops it in a card run at that Seal. Never found
in pots or sealed decks (`Sanctum._card_weight` 0).

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| THE HUNGER (`seal_1`, index 12) (!) no painted card | ROBE socket; hearts 2 ("+2 HEARTS"); lore "IT ATE ITS FILL AND WAS STILL EMPTY." | First win at SEAL I; the SEAL I Archlich in a card run | SEAL I | game/logic/cards.gd:33 | test_still.gd |
| THE AMBUSH (`seal_2`, index 13) (!) no painted card | HAT socket; move speed 0.12 ("+12% SPEED"); lore "THE DOOR WAS NEVER WHERE YOU LOOKED." | First win at SEAL II; the SEAL II Archlich in a card run | SEAL II | game/logic/cards.gd:34 | none |
| THE FAMINE (`seal_3`, index 14) (!) no painted card | ROBE socket; run gold 0.4 ("+40% GOLD"); lore "THE TOWER'S GRANARIES ARE DUST." | First win at SEAL III; the SEAL III Archlich in a card run | SEAL III | game/logic/cards.gd:35 | test_still.gd |
| THE LEGION (`seal_4`, index 15) (!) no painted card | STAFF socket; damage 0.25 ("+25% DAMAGE"); lore "WE ARE MANY. WE ARE ONE." | First win at SEAL IV; the SEAL IV Archlich in a card run | SEAL IV | game/logic/cards.gd:36 | none |
| THE CHAMPION (`seal_5`, index 16) (!) no painted card | ROBE socket; shrug (ward) 0.15 ("15% WARD"); lore "IT NEVER WALKS ALONE." | First win at SEAL V; the SEAL V Archlich in a card run | SEAL V | game/logic/cards.gd:37 | none |
| MISFORTUNE (`seal_6`, index 17) (!) no painted card | HAT socket; cooldown 0.12 ("-12% COOLDOWN"); lore "THE DECK WAS MARKED BEFORE YOU SAT." | First win at SEAL VI; the SEAL VI Archlich in a card run | SEAL VI | game/logic/cards.gd:38 | test_world_seals.gd |
| THE SILENCE (`seal_7`, index 18) (!) no painted card | STAFF socket; cooldown 0.15 ("-15% COOLDOWN"); lore "NO SPELL IS SPOKEN HERE TWICE." | First win at SEAL VII; the SEAL VII Archlich in a card run | SEAL VII | game/logic/cards.gd:39 | none |
| THE DARKNESS (`seal_8`, index 19) (!) no painted card | STAFF socket; damage 0.35 ("+35% DAMAGE"); lore "BEYOND THE LAST SEAL, NOTHING." | First win at SEAL VIII; the SEAL VIII Archlich in a card run | SEAL VIII | game/logic/cards.gd:40 | test_hero.gd, test_still.gd |

## 17. Enemy kinds

Columns of each KINDS row: hp and speed before the minute's scaling (tuning `enemy_hp_mul` 0.70, `enemy_speed_per_min`
0.05 up to minute 12), radius px, score, contact (hearts a touch takes), xp, heft (knock-back scale), flags. Names are
as the HUD prints them (enemy_view.gd NAMES). Kinds 12-19 are the eight added by the bestiary job; 20-21 are the act
bosses. 10 of the 22 kinds (12-21) have no monster card row.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| GOBLIN (`goblin`, type 0) | hp 2, speed 58, radius 5, score 50, contact 1, xp 1, heft 1, flags none; runs at the nearest wizard with a sideways sway | Horde director from 0:00 (see the Horde director table) | card THE CUTPURSE | game/logic/bestiary.gd:58 | sim/sim_horde.gd, test_bestiary.gd, test_bosses.gd +13 |
| SKELETON (`skeleton`, type 1) | hp 3, speed 40, radius 5, score 100, contact 1, xp 2, heft 1, flags none; keeps 80-125 px away and strafes; shoots an arrow every 1.8-2.8 s inside 240 px | Horde director from 1:00 (see the Horde director table) | card THE SENTINEL | game/logic/bestiary.gd:59 | sim/sim_horde.gd, test_fate.gd, test_kinds_crypt.gd +3 |
| SLIME (`slime`, type 2) | hp 5, speed 34, radius 6, score 80, contact 1, xp 2, heft 1, flags none; hops (x2.2 speed for half of every second); splits into 2 SLIMELINGs on death | Horde director from 0:30 (see the Horde director table) | card THE OOZE | game/logic/bestiary.gd:60 | bot/bot_heroes.gd, sim/sim_horde.gd, test_profile.gd +1 |
| SLIMELING (`mslime`, type 3) | hp 1.5, speed 52, radius 4, score 20, contact 1, xp 1, heft 1, flags none; small and quick; the children of a SLIME | Not in the horde table: two spawn when a SLIME dies | card THE DROPLET | game/logic/bestiary.gd:61 | none |
| BAT (`bat`, type 4) | hp 1, speed 88, radius 5, score 60, contact 1, xp 1, heft 1, flags NO_SEP/NO_BLOCK; swerves hard; never pushed by the crowd and does not block it | Horde director from 0:00 (see the Horde director table) | card THE NIGHT WING | game/logic/bestiary.gd:62 | bot/bot_heroes.gd, sim/sim_horde.gd, test_achievements.gd +4 |
| ORC BRUTE (`orc`, type 5) | hp 18, speed 30, radius 8, score 300, contact 2, xp 5, heft 0.4, flags none; walks, winds up 0.6 s inside 160 px, then charges at 240 px/s for 0.6 s; again after 2-3.2 s | Horde director from 2:30 (see the Horde director table) | card THE WARCHIEF | game/logic/bestiary.gd:63 | bot/bot_heroes.gd, test_bestiary.gd, test_cards.gd +11 |
| DARK MAGE (`mage`, type 6) | hp 6, speed 22, radius 5, score 250, contact 1, xp 4, heft 1, flags BLINK; strafes, blinks to 80-130 px from a wizard, then fires a fan of 3 orbs every 2.6-3.6 s | Horde director from 3:30 (see the Horde director table) | card THE HEXER | game/logic/bestiary.gd:64 | test_classes.gd, test_world.gd |
| LICH LORD (`lich`, type 7) (!) Archlich has no sprite file | hp 380, speed 26, radius 14, score 5000, contact 2, xp 25, heft 0.15, flags BOSS/ARROW/BLINK; boss kind; the Lich Lord and the Archlich (see Bosses) | Boss: the final visit at 15:00 as the Archlich (Bosses.SCHEDULE) | card THE LICH | game/logic/bestiary.gd:65 | test_bestiary.gd, test_bosses.gd, test_cards.gd +11 |
| WRAITH (`wraith`, type 8) | hp 4, speed 44, radius 5, score 120, contact 1, xp 2, heft 1, flags NO_SEP; walks through the crowd; fades out for 0.9 s of every 2.5 s cycle (solid 1.6 s) | Horde director from 4:00 (see the Horde director table) | card THE WRAITH | game/logic/bestiary.gd:66 | test_world.gd, test_world_builds.gd |
| CURSED TOME (`tome`, type 9) | hp 3, speed 64, radius 5, score 90, contact 1, xp 2, heft 1, flags none; circles a wizard at 70 px, rears 0.4 s, dashes at 210 px/s for 0.55 s | Horde director from 5:00 (see the Horde director table) | card THE GRIMOIRE | game/logic/bestiary.gd:67 | test_world_builds.gd |
| GARGOYLE (`gargoyle`, type 10) | hp 12, speed 30, radius 7, score 260, contact 1, xp 4, heft 0.4, flags none; perched as stone (takes 25% damage) 2.2 s, then swoops at 150 px/s for 1.1 s | Horde director from 10:00 (see the Horde director table) | card THE GARGOYLE | game/logic/bestiary.gd:68 | test_hero.gd, test_world.gd |
| BONE PRIEST (`priest`, type 11) | hp 9, speed 24, radius 5, score 300, contact 1, xp 5, heft 1, flags none; keeps 105-150 px away; every 6 s raises 2 skeletons | Horde director from 7:00 (see the Horde director table) | card THE BONE PRIEST | game/logic/bestiary.gd:69 | test_bestiary.gd, test_classes.gd, test_profile.gd +2 |
| BLOAT (`bloat`, type 12) | hp 6, speed 30, radius 7, score 100, contact 0, xp 2, heft 1, flags HAZARD; pops itself within 16 px of a wizard; its death is a blast of radius 30 (warn 0.9 s); no XP or drop when it pops; contact 0 | Horde director from 1:30 (see the Horde director table) | no monster card row | game/logic/bestiary.gd:71 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_crypt.gd +1 |
| RESTLESS COFFIN (`coffin`, type 13) | hp 10, speed 0, radius 8, score 200, contact 0, xp 4, heft 0, flags ANCHORED/FIXED_SPEED/ARROW; anchored; shut 4 s, rattles 2 s, then hatches 3 skeletons (4 from 10:00) and is gone; breaks to a gem; contact 0 | Horde director from 2:00 (see the Horde director table) | no monster card row | game/logic/bestiary.gd:72 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_crypt.gd +2 |
| TOMB GUARD (`guard`, type 14) | hp 10, speed 26, radius 7, score 150, contact 1, xp 3, heft 0.6, flags none; turns 1.2 rad/s to the nearest wizard; a hit from within 70 degrees of its facing does nothing | Horde director from 3:30 (see the Horde director table) | no monster card row | game/logic/bestiary.gd:73 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_crypt.gd +1 |
| CINDERLING (`cinderling`, type 15) | hp 4, speed 70, radius 5, score 100, contact 1, xp 2, heft 1, flags HAZARD; holds 90-130 px away, kindles 0.6 s (a 210 px mark), runs 190 px/s for 1.1 s laying a flame line (burns 2 s more) | Horde director from 5:30 (see the Horde director table) | no monster card row | game/logic/bestiary.gd:74 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_bots.gd +2 |
| THE CENSOR (`censor`, type 16) | hp 9, speed 24, radius 6, score 200, contact 1, xp 4, heft 1, flags HAZARD; holds 100-150 px; every 5 s winds up 0.5 s and throws a FIRE disc (radius 22, warn 1.2 s, hot 2.5 s) at a wizard's feet; panics under 60 px | Horde director from 6:00 (see the Horde director table) | no monster card row | game/logic/bestiary.gd:75 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_bots.gd +2 |
| ASH HOUND (`hound`, type 17) | hp 4, speed 70, radius 5, score 100, contact 1, xp 2, heft 1, flags none; a pack circles the party at 150 px; names the stray wizard, howls 0.7 s, hunts at 125 px/s for 4 s (3 s solo) | Horde director from 7:30 (see the Horde director table) | no monster card row | game/logic/bestiary.gd:76 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_library.gd +1 |
| COMET SHARD (`shard`, type 18) | hp 22, speed 0, radius 8, score 300, contact 1, xp 6, heft 0, flags ANCHORED/HAZARD/FIXED_SPEED; a seed: a FALL disc (radius 18, warn 1.2 s) lays where it lands; 1.5 s later a 120 px BEAM warns 1 s then turns 0.6 rad/s; burns out at 30 s | Horde director from 11:00 (see the Horde director table) | no monster card row | game/logic/bestiary.gd:77 | bot/bot.gd, sim/sim_horde.gd, test_bestiary.gd +4 |
| TEN OF SWORDS (`swords`, type 19) | hp 16, speed 36, radius 6, score 300, contact 1, xp 6, heft 1, flags HAZARD; on death a burst disc (radius 22) kneels 0.7 s then rings 10 sword shots | Horde director from 12:30 (see the Horde director table) | no monster card row | game/logic/bestiary.gd:78 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_sanctum.gd +1 |
| THE BONE CHANDELIER (`chandelier`, type 20) | hp 900, speed 34, radius 16, score 5000, contact 0, xp 25, heft 0.15, flags BOSS/FIXED_SPEED/ARROW; boss: see Bosses (THE BONE CHANDELIER) | Boss at 5:00 (Bosses.SCHEDULE) | no monster card row | game/logic/bestiary.gd:81 | test_achievements.gd, test_bestiary.gd, test_boss_chandelier.gd +3 |
| THE GHOST WRITER (`ghostwriter`, type 21) | hp 3800, speed 150, radius 14, score 5000, contact 0, xp 25, heft 0.15, flags BOSS/FIXED_SPEED/ARROW/BLINK; boss: see Bosses (THE GHOST WRITER) | Boss at 10:00 (Bosses.SCHEDULE) | no monster card row | game/logic/bestiary.gd:82 | test_achievements.gd, test_bestiary.gd, test_boss_ghostwriter.gd +2 |

Painted pictures: `assets/art/sprites/enemy_<key>.png` exist for bloat, coffin, guard, cinderling, censor, hound,
shard, swords and `boss_chandelier`, `boss_ghostwriter`; the first twelve kinds and the Lich are code-drawn ASCII
sprites (sprites_enemies.gd). The flat `STAND_INS` shapes (sprites_enemies.gd:1018) remain as the fallback for the ten
kinds 12-21.

## 18. Horde director rows (who comes at which minute)

Columns of each HORDE row: budget cost, unlock time (seconds of fighting), weight in act I / II / III (act I 0:00, II
5:00, III 10:00; `Lore.ACTS`), group size min-max (+ extra max per minute), cap alive (+1 with 3 or 4 wizards; 0
none), form (GROUP through a door or rift, RISE up from the floor, WALL abreast at a door). Rows of kinds 12-19 are
scaled by tuning `new_kinds` (1.0). No kind of a horde row is rolled while a boss is up if it is a HAZARD kind.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| GOBLIN (`goblin`) | cost 1; from 0:00; weights 2/2/2; group 6-10 +1 per minute; cap none; form GROUP | Horde director (unlock at 0:00) | kind row 0 | game/logic/bestiary.gd:102 | test_sanctum.gd, test_still.gd |
| BAT (`bat`) | cost 1; from 0:00; weights 1/1/1; group 4-8; cap none; form GROUP | Horde director (unlock at 0:00) | kind row 4 | game/logic/bestiary.gd:103 | none |
| SLIME (`slime`) | cost 3; from 0:30; weights 1/1/1; group 2-4; cap none; form GROUP | Horde director (unlock at 0:30) | kind row 2 | game/logic/bestiary.gd:104 | none |
| SKELETON (`skeleton`) | cost 3; from 1:00; weights 1/1/1; group 2-5; cap none; form GROUP | Horde director (unlock at 1:00) | kind row 1 | game/logic/bestiary.gd:105 | test_still.gd |
| ORC BRUTE (`orc`) | cost 9; from 2:30; weights 1/1/1; group 1-1; cap none; form GROUP | Horde director (unlock at 2:30) | kind row 5 | game/logic/bestiary.gd:106 | test_bestiary.gd |
| DARK MAGE (`mage`) | cost 6; from 3:30; weights 1/1/1; group 1-2; cap none; form GROUP | Horde director (unlock at 3:30) | kind row 6 | game/logic/bestiary.gd:107 | none |
| WRAITH (`wraith`) | cost 2; from 4:00; weights 1/1/1; group 2-4; cap none; form GROUP | Horde director (unlock at 4:00) | kind row 8 | game/logic/bestiary.gd:108 | none |
| CURSED TOME (`tome`) | cost 2; from 5:00; weights 2/2/2; group 3-6; cap none; form GROUP | Horde director (unlock at 5:00) | kind row 9 | game/logic/bestiary.gd:109 | none |
| BONE PRIEST (`priest`) | cost 8; from 7:00; weights 1/1/1; group 1-1; cap none; form GROUP | Horde director (unlock at 7:00) | kind row 11 | game/logic/bestiary.gd:110 | test_bestiary.gd |
| GARGOYLE (`gargoyle`) | cost 7; from 10:00; weights 1/1/1; group 1-2; cap none; form GROUP | Horde director (unlock at 10:00) | kind row 10 | game/logic/bestiary.gd:111 | none |
| BLOAT (`bloat`) | cost 2; from 1:30; weights 1/1/1; group 1-2; cap 4; form GROUP | Horde director (unlock at 1:30) | kind row 12 | game/logic/bestiary.gd:112 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_crypt.gd |
| RESTLESS COFFIN (`coffin`) | cost 5; from 2:00; weights 1/1/0; group 1-1; cap 2; form RISE | Horde director (unlock at 2:00) | kind row 13 | game/logic/bestiary.gd:113 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_crypt.gd +1 |
| TOMB GUARD (`guard`) | cost 3; from 3:30; weights 1/1/0; group 2-3; cap 4; form WALL | Horde director (unlock at 3:30) | kind row 14 | game/logic/bestiary.gd:114 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_crypt.gd |
| CINDERLING (`cinderling`) | cost 5; from 5:30; weights 0/1/1; group 1-2; cap 2; form GROUP | Horde director (unlock at 5:30) | kind row 15 | game/logic/bestiary.gd:115 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_bots.gd +1 |
| THE CENSOR (`censor`) | cost 6; from 6:00; weights 0/1/0; group 1-2; cap 2; form GROUP | Horde director (unlock at 6:00) | kind row 16 | game/logic/bestiary.gd:116 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_bots.gd +1 |
| ASH HOUND (`hound`) | cost 2; from 7:30; weights 0/1/1; group 3-3; cap 6; form GROUP | Horde director (unlock at 7:30) | kind row 17 | game/logic/bestiary.gd:117 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_library.gd |
| COMET SHARD (`shard`) | cost 8; from 11:00; weights 0/0/1; group 1-1; cap 1; form RISE | Horde director (unlock at 11:00) | kind row 18 | game/logic/bestiary.gd:118 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_bots.gd +2 |
| TEN OF SWORDS (`swords`) | cost 7; from 12:30; weights 0/0/1; group 1-3; cap 3; form GROUP | Horde director (unlock at 12:30) | kind row 19 | game/logic/bestiary.gd:119 | sim/sim_horde.gd, test_bestiary.gd, test_kinds_sanctum.gd |

## 19. Formations (set pieces)

When any formation is unlocked, one group roll in 5 (`FORMATION_ROLL`) is a formation. A part of more than one is
multiplied by 0.5 / 0.67 / 0.83 / 1.0 for 1-4 wizards.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| POWDER TRAIN | 8 GOBLIN, 1 BLOAT; weight 1; comes through one rift near the party | From 2:30 of fighting | BLOAT, GOBLIN | game/logic/bestiary.gd:129 | test_bestiary.gd |
| SHIELD WALL | 3 TOMB GUARD, 3 SKELETON; weight 1; comes through one door | From 3:30 of fighting | SKELETON, TOMB GUARD | game/logic/bestiary.gd:130 | test_bestiary.gd |
| FIRE DRILL | 1 CINDERLING, 1 CINDERLING, 1 THE CENSOR; weight 1; comes through two opposite doors | From 6:30 of fighting | CINDERLING, THE CENSOR | game/logic/bestiary.gd:131 | test_bestiary.gd |

## 20. Omens (set-piece hordes)

One in the middle of each act, warned 2 s ahead (`OMEN_WARN`). A ring forms around the party and closes in (radius 105
px), or the group pours from every door at once. `[wave, kind, count, ring]` rows; names and subtitles are in
`Lore.OMENS`.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| THE DEAD ENCIRCLE (omen 0) | wave 4: 14 SKELETON, a closing ring; subtitle "BACK TO BACK, WIZARDS" | Happens in every run at wave 4 | SKELETON | game/logic/world.gd:241; game/logic/lore.gd:42 | test_achievements.gd, test_world.gd |
| THE LIBRARY TAKES FLIGHT (omen 1) | wave 9: 20 CURSED TOME, from every door; subtitle "EVERY DOOR, EVERY BOOK" | Happens in every run at wave 9 | CURSED TOME | game/logic/world.gd:242; game/logic/lore.gd:43 | test_achievements.gd, test_world.gd |
| THE PROCESSION OF WRAITHS (omen 2) | wave 14: 24 WRAITH, a closing ring; subtitle "THEY WALK THROUGH WALLS" | Happens in every run at wave 14 | WRAITH | game/logic/world.gd:243; game/logic/lore.gd:44 | test_achievements.gd, test_world.gd |

## 21. Bosses

`Bosses.SCHEDULE` (bosses.gd:9): [run second, kind, final]. Health is KINDS hp x tuning `boss_hp_mul` (3.0) x party
share (1, 1.5, 2, 2.5 for 1-4 wizards; apprentices count 0.7) x the Seal's `boss` multiplier; the Archlich also x
FINAL_HP 5.0 x tuning `final_hp_mul` 3.2 x (1 - 0.15 per extra wizard). A boss turning a phase holds still and cannot
be hurt.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| THE BONE CHANDELIER (`chandelier`) | Act I boss; hp 900, speed 34, radius 16. Phase 1 ALOFT (above half health): DRIP, DROP, RAIN, DROP in order. Phase 2 THE WHEEL (its chain snaps): ROLL, RAIN, ROLL, LAST CANDLE, HOP. Takes x1.5 damage while grounded or dizzy. Slaying it: achievement BRING DOWN THE HOUSE and the moment SLEW THE BONE CHANDELIER | Comes at 5:00 of every run (Bosses.SCHEDULE) | Act I (Lore: THE OSSUARY) | game/logic/bosses.gd:9; game/logic/boss_chandelier.gd:3 | test_achievements.gd, test_bestiary.gd, test_boss_chandelier.gd +6 |
| THE GHOST WRITER (`ghostwriter`) | Act II boss; hp 3800, speed 150, radius 14. A planchette that spells each attack letter by letter. Phase 1: FIRE, NAME, SHELF, ERRATA, NAME. Phase 2 (under half health): NAME+FIRE, SHELF+NAME, GOODBYE, ERRATA; NAME calls two wizards in a party of 3 or 4. Slaying it: achievement THE LAST WORD and the moment SLEW THE GHOST WRITER | Comes at 10:00 of every run (Bosses.SCHEDULE) | Act II (Lore: THE BURNING LIBRARY) | game/logic/bosses.gd:9; game/logic/boss_ghostwriter.gd:3 | test_achievements.gd, test_bestiary.gd, test_boss_chandelier.gd +6 |
| MORVANE, LICH LORD / THE ARCHLICH (`lich`, final) (!) no non-final Lich visit | Final boss (the Lich made final: hp 380 x 5.0 x the multipliers above). Three phases: LICH LORD (calm set); at 75% health THE ASCENSION (3 s turn, field clears, all heal 2) then ASCENDANT (enraged set, COMETFALL every 3rd attack); at 35% THE NINTH PAGE (2.5 s turn; NAME every 4th attack, LAST CANDLE every 30 s). Slaying it wins the run (achievements THE LAST LICH, LICH BANE; moment SLEW THE ARCHLICH) | Comes at 15:00 of every run (Bosses.SCHEDULE, final row) | Act III (Lore: THE STARLESS SANCTUM); Lore names: MORVANE, LICH LORD / MORVANE ASCENDANT / THE ARCHLICH | game/logic/bosses.gd:9; game/logic/boss_lich.gd:3 | test_bestiary.gd, test_boss_chandelier.gd, test_boss_ghostwriter.gd +7 |

Also in bosses.gd: `VISITS` (line 13) lists two more rows, [420 s, ward 150] and [720 s, ward 400], marked in a
comment as Morvane's visits; nothing in `game/` or `tests/` reads it. `Bosses.SCHEDULE` has no row for them.

## 22. Boss attacks, by name

Each attack is hazard rows (warn time, kind, radius px) or enemy shots. Warn times are seconds. Attacks listed per
boss file's `ATTACKS` plus the comments that name them.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| DRIP | LANE r10 warn 0.9 along its glide, then FLAME r8 wax behind it (hot 4 s); glide speed 90 | Used by THE BONE CHANDELIER (phase 1) | THE BONE CHANDELIER | game/logic/boss_chandelier.gd:21 | test_boss_chandelier.gd |
| DROP | tracks a wizard 1.4 s then locks 1.1 s: BLAST r44 (warn 2.5), 12 bones fly out at 85 px/s; it is then grounded 3.5 s (x1.5 damage) | Used by THE BONE CHANDELIER (phase 1) | THE BONE CHANDELIER | game/logic/boss_chandelier.gd:23 | test_boss_chandelier.gd |
| RAIN | for 3 s a BLAST r13 (warn 0.9) every 0.3 s, aimed with 0.4 s of lead, a second drop within 70 px of the party's middle | Used by THE BONE CHANDELIER (both) | THE BONE CHANDELIER | game/logic/boss_chandelier.gd:24 | test_boss_chandelier.gd |
| THE CHAIN SNAPS | a heavy BLAST r50 (warn 1.3) under it; the turn to phase 2 holds 1.6 s | Used by THE BONE CHANDELIER (turn) | THE BONE CHANDELIER | game/logic/boss_chandelier.gd:25 | test_boss_chandelier.gd |
| ROLL | LANE r18 warn 0.8, then rolls 3 legs at 170 px/s leaving FLAME r10 (hot 3 s); trample damage x30 to enemies; dizzy 2.5 s after | Used by THE BONE CHANDELIER (phase 2) | THE BONE CHANDELIER | game/logic/boss_chandelier.gd:26 | test_boss_chandelier.gd |
| LAST CANDLE | a SAFE disc r40 (warn 3.5): everyone outside it is hurt 2 hearts; placed within 150 px of every living wizard, else skipped | Used by THE BONE CHANDELIER, THE ARCHLICH (phase 2 / Archlich page 3) | THE BONE CHANDELIER, THE ARCHLICH | game/logic/boss_chandelier.gd:27 | test_boss_chandelier.gd, test_bosses.gd |
| HOP | tracks 0.9 s, locks 1.0 s: BLAST r40 (warn 1.9) | Used by THE BONE CHANDELIER (phase 2) | THE BONE CHANDELIER | game/logic/boss_chandelier.gd:28 | none |
| FIRE | spells F-I-R-E, then a LANE r12 and a run at 190 px/s leaving FLAME r10 (hot 5 s) | Used by THE GHOST WRITER (both phases) | THE GHOST WRITER | game/logic/boss_ghostwriter.gd:31 | test_boss_ghostwriter.gd |
| NAME | spells a wizard's name; BLAST r30 on that wizard locks 0.9 s before landing and leaves a FIRE r22; two wizards in a party of 3 or 4 (phase 2) | Used by THE GHOST WRITER, THE ARCHLICH (both phases; Archlich page 3) | THE GHOST WRITER, THE ARCHLICH | game/logic/boss_ghostwriter.gd:33 | test_boss_ghostwriter.gd |
| SHELF | spells S-H-E-L-F: FLAME lanes r38 (odd lanes warn 1.62, even lanes 1.3 s later), 76 px apart | Used by THE GHOST WRITER (both phases) | THE GHOST WRITER | game/logic/boss_ghostwriter.gd:35 | test_boss_ghostwriter.gd |
| ERRATA | spells E-R-R-A-T-A: FALL discs r10 (something lands) | Used by THE GHOST WRITER (both phases) | THE GHOST WRITER | game/logic/boss_ghostwriter.gd:37 | none |
| GOODBYE | spells G-O-O-D-B-Y-E at 0.5 s a letter, then rings of shots; a check on her health as it began (boss_meter) | Used by THE GHOST WRITER (phase 2) | THE GHOST WRITER | game/logic/boss_ghostwriter.gd:38 | test_boss_ghostwriter.gd |
| RADIAL BURSTS (state 1) | enemy-shot rings around it; part of the calm set, also used by ASCENDANT | Used by THE LICH LORD (LICH LORD, ASCENDANT) | THE LICH LORD | game/logic/boss_lich.gd:91 | test_bosses.gd, test_world.gd, test_world_seals.gd |
| AIMED VOLLEYS (state 2) | shots aimed at every wizard from muzzle to hit centre | Used by THE LICH LORD (LICH LORD, ASCENDANT) | THE LICH LORD | game/logic/boss_lich.gd:105 | test_bosses.gd, test_world.gd, test_world_seals.gd |
| SPIRAL (state 3) | a spiral of shots; its pause before is 2.4 s | Used by THE LICH LORD (LICH LORD, ASCENDANT) | THE LICH LORD | game/logic/boss_lich.gd:118 | test_bosses.gd, test_world.gd, test_world_seals.gd |
| SUMMON MINIONS (state 4) | calls minions from every door (not in a lost run's results screen) | Used by THE LICH LORD (LICH LORD, ASCENDANT) | THE LICH LORD | game/logic/boss_lich.gd:131 | test_bosses.gd, test_world.gd, test_world_seals.gd |
| TELEPORT THEN BURST (state 5) | enraged set only: teleports to the far side of the nearest wizard, then bursts; the enraged Lich also moves 1.5x faster | Used by THE LICH LORD (ASCENDANT (and a Lich under half health)) | THE LICH LORD | game/logic/boss_lich.gd:142 | test_bosses.gd, test_world.gd, test_world_seals.gd |
| COMETFALL | 3 heavy BLASTs r30 (warn 1.4) that leave FIRE r22, one on each aimed wizard and the rest within 60 px of the party; every 3rd attack from ASCENDANT | Used by THE ARCHLICH (ASCENDANT, NINTH PAGE) | THE ARCHLICH | game/logic/boss_lich.gd:14 | test_bosses.gd |
| THE ASCENSION (phase turn) | at 75% health: a 3 s turn, the field clears, every wizard heals 2 hearts; then ASCENDANT (enraged set, COMETFALL every 3rd attack) | Used by THE ARCHLICH (LICH LORD to ASCENDANT) | THE ARCHLICH | game/logic/boss_lich.gd:22 | test_bosses.gd |
| THE NINTH PAGE (phase turn) | at 35% health: a 2.5 s turn, then ASCENDANT plus NAME every 4th attack and a LAST CANDLE every 30 s | Used by THE ARCHLICH (ASCENDANT to NINTH PAGE) | THE ARCHLICH | game/logic/boss_lich.gd:24 | test_bosses.gd, test_sanctum.gd |

`ATTACKS` rows in code: THE BONE CHANDELIER 9, THE GHOST WRITER 8, the Lich file 4 (several rows make one named attack
above, so the named-attack count is 20, not 21). The Lich's calm states 1-5 carry only the comments named in the
table: boss_lich.gd has no name strings for them.

## 23. Hazard kinds (floor rows)

A hazard warns (dashed rim, fill growing) then turns hot. Every warning lasts at least 0.3 + (r + 4) / 71 s. At most
48 rows at once (32 not made by a boss); the nova clears regular rows within 150 px.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| MARK (`Hazards.MARK`) | a path shown, never hot; line; hearts while hot 0; on hot: nothing | Made by boss telegraphs (CINDERLING mark, Chandelier lanes) | none | game/logic/hazards.gd:50 | test_boss_chandelier.gd, test_boss_ghostwriter.gd, test_hazards.gd +1 |
| BLAST (`Hazards.BLAST`) | hurts wizards and enemies once (foe damage 6 x the minute's hp scale, shove 120); disc; hearts while hot 1; on hot: blast | Made by BLOAT death, bosses | none | game/logic/hazards.gd:51 | sim/sim_horde.gd, test_boss_chandelier.gd, test_boss_ghostwriter.gd +3 |
| FIRE (`Hazards.FIRE`) | a burning patch; disc; hearts while hot 1; on hot: nothing | Made by CENSOR throw, boss leftovers | none | game/logic/hazards.gd:52 | sim/sim_horde.gd, test_boss_ghostwriter.gd, test_bosses.gd +3 |
| FLAME (`Hazards.FLAME`) | a burning line; line; hearts while hot 1; on hot: nothing | Made by CINDERLING run, bosses | none | game/logic/hazards.gd:53 | sim/sim_horde.gd, test_boss_chandelier.gd, test_boss_ghostwriter.gd +2 |
| FALL (`Hazards.FALL`) | something lands (aux = enemy type); disc; hearts while hot 1; on hot: spawn | Made by COMET SHARD seed, ERRATA | none | game/logic/hazards.gd:54 | test_hazards.gd, test_kinds_crypt.gd, test_kinds_sanctum.gd |
| BEAM (`Hazards.BEAM`) | a line a brain turns while hot; line; hearts while hot 1; on hot: nothing | Made by COMET SHARD | none | game/logic/hazards.gd:55 | sim/sim_horde.gd, test_kinds_sanctum.gd |
| BURST (`Hazards.BURST`) | a ring of shots; disc; hearts while hot 0; on hot: ring of shots | Made by TEN OF SWORDS death | none | game/logic/hazards.gd:56 | test_hazards.gd, test_kinds_sanctum.gd |
| LANE (`Hazards.LANE`) | where a boss is about to go; line; hearts while hot 0; on hot: nothing | Made by boss paths | none | game/logic/hazards.gd:57 | sim/sim_horde.gd, test_boss_chandelier.gd, test_boss_ghostwriter.gd +1 |
| SAFE (`Hazards.SAFE`) | everyone outside it is hurt (2 hearts); disc; hearts while hot 2; on hot: nothing | Made by LAST CANDLE | none | game/logic/hazards.gd:58 | test_boss_chandelier.gd, test_bosses.gd, test_hazards.gd |

## 24. Difficulty steps (the ladder)

`Seals.MIN -1 .. MAX 9`: 11 steps. Open on a new profile: APPRENTICE, WIZARD, ARCHMAGE; a win at a step opens the
next. WIZARD is the game as tuned. ARCHMAGE: enemy hp x1.08, boss x1.15. Each Seal adds enemy hp +0.03, horde budget
+0.03, boss health +0.06 on top of the step below, plus its one rule (rules are cumulative). Card odds +0.1 per point
of luck. First-win prize: 50 x step squared crystals from ARCHMAGE up.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| APPRENTICE (step -1) | enemy hp x0.75, boss x0.7, +2 hearts, potions x2, no ULTRA RARE loot; gentler foes; crystal bounty x0.5; chest luck +0 | Open from the start | none | game/logic/seals.gd:13 | test_achievements.gd, test_lobby_rules.gd, test_profile.gd +4 |
| WIZARD (step 0) | the game as tuned; all values neutral; crystal bounty x1; chest luck +0 | Open from the start | none | game/logic/seals.gd:13 | test_achievements.gd, test_deeds_book.gd, test_gamble.gd +5 |
| ARCHMAGE (step 1) | tougher foes and bosses (hp x1.08, boss x1.15); crystal bounty x1.5; chest luck +1; first win pays 50 crystals | Open from the start | none | game/logic/seals.gd:13 | test_achievements.gd, test_profile.gd, test_seals.gd +1 |
| SEAL I (step 2) | HUNGER: FEWER POTIONS FROM KILLS (values {potions: 0.6}); hp x1.11, horde x1.03, boss x1.21; crystal bounty x2; chest luck +2; first win pays 200 crystals and the card THE HUNGER | Opens when the step below is won | Seal card THE HUNGER | game/logic/seals.gd:49 | test_achievements.gd, test_seals.gd |
| SEAL II (step 3) | AMBUSH: RIFTS WARN HALF AS LONG (values {rift: 0.5}); hp x1.14, horde x1.06, boss x1.27; crystal bounty x2.5; chest luck +3; first win pays 450 crystals and the card THE AMBUSH | Opens when the step below is won | Seal card THE AMBUSH | game/logic/seals.gd:50 | test_achievements.gd |
| SEAL III (step 4) | FAMINE: POTIONS HEAL 1 HEART (values {potion_heal: 1}); hp x1.17, horde x1.09, boss x1.33; crystal bounty x3.25; chest luck +4; first win pays 800 crystals and the card THE FAMINE | Opens when the step below is won | Seal card THE FAMINE | game/logic/seals.gd:51 | test_achievements.gd, test_still.gd |
| SEAL IV (step 5) | LEGION: GROUPS 25% BIGGER (values {group: 1.25, cap: 325}); hp x1.2, horde x1.12, boss x1.39; crystal bounty x4; chest luck +5; first win pays 1250 crystals and the card THE LEGION | Opens when the step below is won | Seal card THE LEGION | game/logic/seals.gd:52 | test_achievements.gd |
| SEAL V (step 6) | CHAMPIONS: ESCORTED ELITES (values {elite_hp: 1.5, escort: 4}); hp x1.23, horde x1.15, boss x1.45; crystal bounty x5; chest luck +6; first win pays 1800 crystals and the card THE CHAMPION | Opens when the step below is won | Seal card THE CHAMPION | game/logic/seals.gd:53 | test_achievements.gd |
| SEAL VI (step 7) | MISFORTUNE: CRUEL FATES (values {cruel: 0.6}); hp x1.26, horde x1.18, boss x1.51; crystal bounty x6.5; chest luck +7; first win pays 2450 crystals and the card MISFORTUNE | Opens when the step below is won | Seal card MISFORTUNE | game/logic/seals.gd:54 | test_achievements.gd, test_world_seals.gd |
| SEAL VII (step 8) | SILENCE: 2-CARD LEVEL-UPS (values {hand: 2}); hp x1.29, horde x1.21, boss x1.57; crystal bounty x8; chest luck +8; first win pays 3200 crystals and the card THE SILENCE | Opens when the step below is won | Seal card THE SILENCE | game/logic/seals.gd:55 | test_achievements.gd |
| SEAL VIII (step 9) | DARKNESS: 1 LIFE, NO JUDGEMENT (values {lives: 1, solo_lives: 2, judgement: False, ritual: 2.0}); hp x1.32, horde x1.24, boss x1.63; crystal bounty x10; chest luck +10; first win pays 4050 crystals and the card THE DARKNESS | Opens when the step below is won | Seal card THE DARKNESS | game/logic/seals.gd:56 | test_achievements.gd, test_deeds_book.gd, test_seals.gd |

## 25. Sanctum shop (the shopkeeper's unlocks)

Bought with crystals; every unlock stays for every run (and for the whole party: the host's profile powers a co-op
run). Crystals are earned only: per run 1 per 30 s survived, 1 per 250 kills, 10 per Lich slain (the Archlich counts),
25 for a win; the Lich and win bounties are x the step's crystal multiplier (`Profile.crystals_for_run`,
profile.gd:36-39).

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| WARDED ROBES (`vigor`) | 1 per level (hearts += 1); text "+1 HEART" | Crystals: level 1 costs 40; level 2 costs 160 (total 200) | none | game/logic/profile.gd:17; effect game/logic/profile.gd:38 | bot/bot_heroes.gd, test_profile.gd |
| RUNED STAFF (`might`) | 0.04 per level (damage += 0.04), 5 levels; text "+4% DAMAGE"; levels 4 and 5 open at the SEAL IV win (`Profile.GATES`) | Crystals: 30, 70, 150, 300, 600 (total 1,150) | none | game/logic/profile.gd:18; effect game/logic/profile.gd:39; gate game/logic/profile.gd:53 | bot/bot_heroes.gd, test_profile.gd, test_unlocks.gd |
| FORBIDDEN LORE (`wisdom`) | 0.06 per level (xp += 0.06); text "+6% XP" | Crystals: level 1 costs 30; level 2 costs 80; level 3 costs 200 (total 310) | none | game/logic/profile.gd:19; effect game/logic/profile.gd:40 | test_profile.gd |
| MIDAS' PURSE (`fortune`) | 0.15 per level (gold += 0.15); text "+15% GOLD" | Crystals: level 1 costs 20; level 2 costs 60; level 3 costs 150 (total 230) | none | game/logic/profile.gd:20; effect game/logic/profile.gd:41 | test_profile.gd |
| BOTTLED STAR (`novas`) | 1 per level (novas += 1); text "+1 NOVA" | Crystals: level 1 costs 40; level 2 costs 140 (total 180) | none | game/logic/profile.gd:21; effect game/logic/profile.gd:42 | test_profile.gd |
| FOUR-LEAF RUNE (`luck`) | 1 per level (luck += 1); text "LUCKIER CHESTS" | Crystals: level 1 costs 80; level 2 costs 240 (total 320) | none | game/logic/profile.gd:22; effect game/logic/profile.gd:43 | test_profile.gd, test_seals.gd |
| THE SECOND GLANCE (`redraw`) | 1 per level (redraws += 1): every wizard starts the run with Upgrades.REDRAWS + its level (WorldLevels._shop_start, the first step); text "+1 REDRAW EACH RUN"; level 2 opens at the SEAL V win | Crystals: 60, 220 (total 280) | The level-up hand | game/logic/profile.gd:23; effect game/logic/world/levels.gd:61 | test_shop_options.gd, test_unlocks.gd |
| THE BLACK RIBBON (`banish`) | 1 per level (banishes += 1), as THE SECOND GLANCE; text "+1 BANISH EACH RUN"; level 2 opens at the SEAL II win | Crystals: 60, 220 (total 280) | The level-up hand | game/logic/profile.gd:24; effect game/logic/world/levels.gd:61 | test_shop_options.gd, test_unlocks.gd |
| THE HEAD START (`start_level`) | 1 per level: the party starts at level 1 + its level and keeps the lead all run (World.xp_needed never prices those levels: World.head_start_levels); each wizard draws that many hands while the intro holds (at most Tuning.head_start_wait, 12 s; WorldLevels._intro_held) and a local seat's tray opens by itself; use counter shop_start_level; text "THE PARTY STARTS A LEVEL UP"; level 2 opens at the SEAL VII win | Crystals: 120, 400 (total 520) | The pair she plans | game/logic/profile.gd:25; effect game/logic/world/levels.gd:61, game/logic/world.gd:718 | test_shop_options.gd, test_unlocks.gd, cover robot family shop |

Since 28 Nov the prices and RUNED STAFF's five levels are those of § 45. `Profile.META` also holds § 45's six
other rows (THE SATCHEL to THE VEILED DECK); they stay off the shelf (`Profile.UNBUILT`, `Profile.shelf`)
until the job that builds each one's effect takes its key off the list, so the screen shows these nine.

## 26. Sanctum things

The room (428x190 px) a wizard walks between runs. The alcove behind the cracked wall opens after pushing on it 1.2 s.
`[key, position, prompt]`.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| The portal (`portal`, THINGS 0) | starts a run; prompt "ENTER THE TOWER" | Walk up to it in the Sanctum (reach 20 px) | none | game/logic/sanctum.gd:30 | none |
| The card album (altar) (`altar`, THINGS 1) | opens the monster card album and the sockets; prompt "THE CARD ALBUM" | Walk up to it in the Sanctum (reach 20 px) | none | game/logic/sanctum.gd:31 | none |
| The reliquary (`reliquary`, THINGS 2) | buys a sealed deck for 1500 crystals: one monster card the player lacks (the Lich card half as likely: weight 5 vs 10); prompt "SEALED DECK  %d CRYSTALS" | Walk up to it in the Sanctum (reach 20 px) | none | game/logic/sanctum.gd:32 | test_sanctum.gd |
| The music box (`music`, THINGS 3) | plays the music box (a note drifts up); prompt "MUSIC BOX" | Walk up to it in the Sanctum (reach 20 px) | none | game/logic/sanctum.gd:33 | test_text_glyphs.gd |
| The wishing well (`well`, THINGS 4) | 1 crystal in: 12 crystals back at 8%, else a fortune line; every 9th toss grants the secret THE NINTH WISH, 30 crystals once; prompt "WISHING WELL  1 CRYSTAL" | Walk up to it in the Sanctum (reach 20 px) | none | game/logic/sanctum.gd:34 | test_sanctum.gd |
| The cat (`cat`, THINGS 5) | pet the cat; reachable only from the alcove (a secret); prompt "PET THE CAT" | Walk up to it in the Sanctum (reach 20 px) | none | game/logic/sanctum.gd:35 | test_sanctum.gd |
| The shopkeeper (`shopkeeper`, THINGS 6) | talk, then the shop (table 25); prompt "TALK TO THE SHOPKEEPER" | Walk up to it in the Sanctum (reach 20 px) | none | game/logic/sanctum.gd:36 | none |
| The card reader (`card_reader`, THINGS 7) | talk: fates, Seals and spell pairs; prompt "TALK TO THE CARD READER" | Walk up to it in the Sanctum (reach 20 px) | none | game/logic/sanctum.gd:37 | none |
| The mirror (`mirror`, THINGS 8) | opens the hero screens; prompt "LOOK INTO THE MIRROR" | Walk up to it in the Sanctum (reach 20 px) | none | game/logic/sanctum.gd:38 | none |
| The Book of Deeds (`deeds`, THINGS 9) | opens the Book of Deeds; prompt "BOOK OF DEEDS" | Walk up to it in the Sanctum (reach 20 px) | none | game/logic/sanctum.gd:39 | test_sanctum.gd |

Sanctum pots (sanctum.gd:43-47): 12 pots along the walls; broken ones stay broken until the next run is played. Each
holds: a monster card 0.1%, a 5-crystal cache 6%, 1 crystal 35%, else nothing. Alcove: 50 crystals the first time it
is found. Wishing-well fortunes (12 lines, sanctum.gd:265): THE TOWER REMEMBERS EVERY WIZARD.; WHAT HERMES HID,
PATIENCE FINDS.; THE NINTH WAVE IS THE STRONGEST.; A LICH FEARS ONLY BEING FORGOTTEN.; SOLOMON SEALED SEVENTY-TWO. NOT
ALL.; LOOK UP. SOME WALLS ARE TIRED.; THE CAT KNOWS. THE CAT ALWAYS KNOWS.; FORTUNE FAVOURS THE SECOND TRY.; ODIN GAVE
AN EYE. YOU GAVE A CRYSTAL.; THE ORACLE SAYS: DODGE LEFT.; WHAT IS BROKEN MAY HOLD A CARD.; THE MOON IS LISTENING
TONIGHT.

## 27. Achievements (the Book of Deeds)

Each is paid in crystals once. The first 14 are the Steam names (their rules are in `Achievements.earned`); the other
40 have a rule in `Achievements.RULES` and live in the Book only until added to Steam. `???` = secret until earned.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| THE LAST LICH (`ARCHLICH`) | "Slay the Archlich and win a run." Rule: won the run. Pays 50 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:12 | test_achievements.gd, test_profile.gd |
| LONE WIZARD (`SOLO_WIN`) | "Win a run alone." Rule: won with 1 wizard in the record. Pays 30 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:13 | test_achievements.gd, test_deeds_book.gd, test_profile.gd |
| FULL TOWER (`PARTY_WIN`) | "Win a run with four wizards." Rule: won with 4 or more wizards. Pays 25 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:14 | test_achievements.gd |
| UNTOUCHED (`FLAWLESS`) | "Win a run without any wizard losing a life." Rule: won with no deaths or downs. Pays 40 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:15 | test_achievements.gd |
| LICH BANE (`LICH`) | "Slay the Lich Lord." Rule: a Lich or Archlich moment (the Archlich counts). Pays 15 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:16 | test_achievements.gd |
| HOLD THE TOWER (`TEN_MINUTES`) | "Survive for 10 minutes." Rule: survived 600 s. Pays 10 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:17 | test_achievements.gd |
| BLESSED BE (`BLESSED`) | "Draw The Sun for the whole party at the fate card." Rule: a team-fate PARTY BLESSED moment. Pays 5 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:18 | test_achievements.gd |
| WORTH IT (`CURSED`) [secret] | "Draw Death for the whole party at the fate card." Rule: a team-fate PARTY CURSED moment. Pays 5 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:19 | test_achievements.gd, test_deeds_book.gd |
| JACKPOT (`JACKPOT`) (!) text says rune altar | "Hit the jackpot at a rune altar." Rule: a solo-shrine JACKPOT moment. Pays 10 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:20 | test_achievements.gd |
| ULTRA RARE (`ULTRA`) | "Find ultra rare loot in a chest." Rule: opened an ULTRA RARE chest (best tier 4). Pays 50 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:21 | test_achievements.gd |
| EVOLUTION (`EVOLVE`) | "Evolve a spell." Rule: any evolution taken. Pays 10 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:22 | test_achievements.gd |
| TOTAL SORCERY (`COMBO_200`) | "Chain a 200 kill combo." Rule: a 200-kill combo. Pays 20 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:23 | test_achievements.gd |
| THE KEY OF SOLOMON (`SEAL`) [secret] | "Evolve Rune Circle into the Seal of Solomon." Rule: evolved RUNE CIRCLE. Pays 25 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:24 | test_achievements.gd |
| OMEN-PROOF (`OMENS`) | "Survive all three omens." Rule: survived 840 s (the last omen's minute). Pays 20 crystals | Earned at the end of a run (Steam) | none | game/logic/achievements.gd:25 | test_achievements.gd |
| THE MAGICIAN (`WIN_MAGE`) | "Win a run with a Mage among the players." Rule: won with class MAGE in the party. Pays 10 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:26 | test_achievements.gd, test_deeds_book.gd, test_profile.gd +1 |
| THE CHARIOT (`WIN_KNIGHT`) | "Win a run with a Knight among the players." Rule: won with class KNIGHT in the party. Pays 10 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:27 | test_achievements.gd |
| THE HERMIT'S AIM (`WIN_ARCHER`) | "Win a run with an Archer among the players." Rule: won with class ARCHER in the party. Pays 10 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:28 | test_achievements.gd |
| THE HIEROPHANT (`WIN_PRIEST`) | "Win a run with a Priest among the players." Rule: won with class PRIEST in the party. Pays 10 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:29 | test_achievements.gd |
| STRENGTH (`WIN_PALADIN`) | "Win a run with a Paladin among the players." Rule: won with class PALADIN in the party. Pays 10 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:30 | test_achievements.gd |
| ALL TOO HUMAN (`WIN_HUMAN`) | "Win a run with a Human among the players." Rule: won with race HUMAN in the party. Pays 10 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:31 | test_achievements.gd, test_profile.gd |
| LONG IN THE TOOTH (`WIN_ELF`) | "Win a run with an Elf among the players." Rule: won with race ELF in the party. Pays 10 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:32 | test_achievements.gd |
| DEEP AND STUBBORN (`WIN_DWARF`) | "Win a run with a Dwarf among the players." Rule: won with race DWARF in the party. Pays 10 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:33 | test_achievements.gd |
| POLITE FURY (`WIN_ORC`) | "Win a run with an Orc among the players." Rule: won with race ORC in the party. Pays 10 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:34 | test_achievements.gd, test_still.gd |
| BALANCED READING (`TRINITY`) | "Win a run with a tank, a healer and a ranged hero among the players." Rule: won with a tank (or support), a healer and a ranged hero. Pays 20 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:35 | test_achievements.gd |
| STRAIGHT AND NARROW (`EVO_ARCANE`) | "Evolve Arcane Bolt into Astral Lance." Rule: took the evolution of ASTRAL LANCE. Pays 15 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:36 | none |
| FIRE AND LIGHTNING (`EVO_FIRE`) | "Evolve Fireball into Thunderfire." Rule: took the evolution of THUNDERFIRE. Pays 15 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:37 | test_still.gd |
| WHITEOUT (`EVO_FROST`) | "Evolve Frost Fan into Blizzard." Rule: took the evolution of BLIZZARD. Pays 15 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:38 | none |
| THE PERFECT STORM (`EVO_STORM`) | "Evolve Chain Lightning into Tempest." Rule: took the evolution of TEMPEST. Pays 15 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:39 | none |
| THE STARS ALIGN (`EVO_STAR`) | "Evolve Starfall into Comet Rain." Rule: took the evolution of COMET RAIN. Pays 15 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:40 | none |
| TO THE MARROW (`EVO_BONE`) | "Evolve Bone Spear into Ossuary Lance." Rule: took the evolution of OSSUARY LANCE. Pays 15 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:41 | none |
| LET THERE BE MORE LIGHT (`EVO_CANDLE`) | "Evolve Vigil Candle into Consecration." Rule: took the evolution of CONSECRATION. Pays 15 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:42 | none |
| BRING DOWN THE HOUSE (`BOSS_CHANDELIER`) | "Slay the Bone Chandelier." Rule: slew THE BONE CHANDELIER. Pays 15 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:43 | test_achievements.gd, test_still.gd |
| THE LAST WORD (`BOSS_GHOSTWRITER`) | "Slay the Ghost Writer." Rule: slew THE GHOST WRITER. Pays 15 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:44 | test_achievements.gd |
| THE UPPER SHELF (`WIN_ARCHMAGE`) | "Win a run at Archmage." Rule: won at ARCHMAGE or above. Pays 20 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:45 | test_achievements.gd |
| FIRST SEAL BROKEN (`WIN_SEAL_1`) | "Win a run at Seal I." Rule: won at SEAL I or above. Pays 25 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:46 | test_achievements.gd |
| SECOND SEAL BROKEN (`WIN_SEAL_2`) | "Win a run at Seal II." Rule: won at SEAL II or above. Pays 30 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:47 | test_achievements.gd |
| THIRD SEAL BROKEN (`WIN_SEAL_3`) | "Win a run at Seal III." Rule: won at SEAL III or above. Pays 30 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:48 | test_achievements.gd, test_still.gd |
| FOURTH SEAL BROKEN (`WIN_SEAL_4`) | "Win a run at Seal IV." Rule: won at SEAL IV or above. Pays 35 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:49 | test_achievements.gd |
| FIFTH SEAL BROKEN (`WIN_SEAL_5`) | "Win a run at Seal V." Rule: won at SEAL V or above. Pays 40 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:50 | test_achievements.gd |
| SIXTH SEAL BROKEN (`WIN_SEAL_6`) | "Win a run at Seal VI." Rule: won at SEAL VI or above. Pays 45 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:51 | test_achievements.gd |
| SEVENTH SEAL BROKEN (`WIN_SEAL_7`) | "Win a run at Seal VII." Rule: won at SEAL VII or above. Pays 50 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:52 | test_achievements.gd |
| THE LAST SEAL (`WIN_SEAL_8`) [secret] | "Win a run at Seal VIII." Rule: won at SEAL VIII or above. Pays 50 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:53 | test_achievements.gd, test_deeds_book.gd |
| SECOND WIND (`REVIVE_3`) | "Raise 3 fallen allies in one run." Rule: raised 3 fallen allies in one run. Pays 10 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:54 | test_achievements.gd, test_still.gd |
| UNIONISED DEAD (`REVIVE_25`) | "Raise 25 fallen allies over all your runs." Rule: raised 25 fallen allies over all runs. Pays 20 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:55 | test_achievements.gd |
| BODY COUNT (`KILLS_1K`) | "Slay 1,000 foes over all your runs." Rule: 1000 kills over all runs. Pays 10 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:56 | test_achievements.gd, test_profile.gd, test_still.gd |
| MASS GRAVE (`KILLS_10K`) | "Slay 10,000 foes over all your runs." Rule: 10000 kills over all runs. Pays 25 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:57 | test_achievements.gd, test_profile.gd |
| THE LONG HARVEST (`KILLS_100K`) | "Slay 100,000 foes over all your runs." Rule: 100000 kills over all runs. Pays 50 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:58 | test_achievements.gd |
| JOURNEYMAN (`HERO_10`) | "Raise a hero to class level 10." Rule: a hero reached class level 10. Pays 15 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:59 | test_achievements.gd |
| THE FULL DECK (`ALL_CARDS`) | "Collect every monster card." Rule: every monster card found. Pays 40 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:60 | test_achievements.gd, test_profile.gd |
| NOTHING LEFT UNSAID (`ALL_SECRETS`) [secret] | "Find every secret in the game." Rule: every secret found. Pays 30 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:61 | test_achievements.gd, test_still.gd |
| THE MASTER'S HAND (`APPRENTICES`) [secret] | "Win a run with only apprentices beside you." Rule: won with one human and only apprentices beside. Pays 20 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:62 | test_achievements.gd |
| ON SCHEDULE (`FAST_WIN`) | "Win a run with four heroes before 16:30." Rule: won with 4 or more heroes in under 990 s. Pays 30 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:63 | test_achievements.gd, test_still.gd |
| WIDDERSHINS (`EVO_CLEAVE`) | "Evolve Cleave into Whirlwind." Rule: took the evolution of WHIRLWIND. Pays 15 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:64 | none |
| THE QUERENT (`FIRST_CARD`) | "Find your first monster card." Rule: found 1 card(s). Pays 25 crystals | Earned at the end of a run (Book only) | none | game/logic/achievements.gd:65 | test_achievements.gd |

Rule check: all 54 api names have a rule (14 in `earned()` plus 40 in `RULES`); no deed was found whose rule nothing
can satisfy at default tuning.

## 28. Secrets

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| THE TIRED WALL IN THE SANCTUM (`alcove`) | Found by: push on the cracked wall in the Sanctum (1.2 s) to open the alcove | Found in play; the Sanctum counts them (SECRETS n/8) | none | game/logic/secrets.gd:8 | test_profile.gd |
| THE CAT IN THE ALCOVE (`cat`) | Found by: pet the cat in the alcove | Found in play; the Sanctum counts them (SECRETS n/8) | none | game/logic/secrets.gd:9 | test_cards.gd |
| THE MOON OVER THE TITLE (`eclipse`) | Found by: title screen: the moon | Found in play; the Sanctum counts them (SECRETS n/8) | none | game/logic/secrets.gd:10 | none |
| A LIT WINDOW OF THE CASTLE (`ghost`) | Found by: title screen: a lit window of the castle | Found in play; the Sanctum counts them (SECRETS n/8) | none | game/logic/secrets.gd:11 | none |
| THE OLDEST WORD (`abracadabra`) | Found by: spell ABRACADABRA on the Ouija board (+25 crystals) | Found in play; the Sanctum counts them (SECRETS n/8) | none | game/logic/secrets.gd:12 | test_cards.gd |
| THE KING'S NAME (`solomon`) | Found by: spell SOLOMON on the Ouija board (+10 crystals) | Found in play; the Sanctum counts them (SECRETS n/8) | none | game/logic/secrets.gd:13 | none |
| A CARD IN AN ARENA URN (`urn_card`) | Found by: find a card in an arena urn | Found in play; the Sanctum counts them (SECRETS n/8) | none | game/logic/secrets.gd:14 | test_world.gd |
| THE NINTH WISH (`ninth`) | Found by: the ninth toss into the wishing well (+30 crystals, once) | Found in play; the Sanctum counts them (SECRETS n/8) | none | game/logic/secrets.gd:15 | test_sanctum.gd |

## 29. Ouija board words

Spelled on the LAN join screen (`Secrets.WORDS`: [reply, secret key, crystals once]).

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| HELLO | Reply "HELLO, WIZARD. WE HAVE BEEN WAITING." | Typed on the Ouija board | none | game/logic/secrets.gd:20 | none |
| ABRACADABRA | Reply "THE OLD WORD STILL WORKS."; finds secret `abracadabra`, +25 crystals once | Typed on the Ouija board | none | game/logic/secrets.gd:21 | none |
| SOLOMON | Reply "THE SEAL HOLDS. MOSTLY."; finds secret `solomon`, +10 crystals once | Typed on the Ouija board | none | game/logic/secrets.gd:22 | none |
| MEOW | Reply "SOMEWHERE IN THE SANCTUM, A CAT LOOKS UP." | Typed on the Ouija board | none | game/logic/secrets.gd:23 | none |
| LICH | Reply "DO NOT SAY ITS NAME. IT HEARS." | Typed on the Ouija board | none | game/logic/secrets.gd:24 | test_achievements.gd |
| XYZZY | Reply "NOTHING HAPPENS." | Typed on the Ouija board | none | game/logic/secrets.gd:25 | none |
| HERMES | Reply "AS ABOVE, SO BELOW." | Typed on the Ouija board | none | game/logic/secrets.gd:26 | none |
| ODIN | Reply "HE WATCHES WITH THE OTHER EYE." | Typed on the Ouija board | none | game/logic/secrets.gd:27 | none |
| MERLIN | Reply "HE LIVES BACKWARDS. HE SAYS GOODBYE." | Typed on the Ouija board | none | game/logic/secrets.gd:28 | none |
| 42 | Reply "THE ANSWER. BUT WHAT WAS THE QUESTION?" | Typed on the Ouija board | none | game/logic/secrets.gd:29 | none |
| 666 | Reply "NOT THAT NUMBER. TRY 777." | Typed on the Ouija board | none | game/logic/secrets.gd:30 | none |
| 777 | Reply "LUCKY. THE SPIRITS APPROVE." | Typed on the Ouija board | none | game/logic/secrets.gd:31 | none |

## 30. Results-screen moments

The screen shows the best 4 moments (higher weight first; ties go to the later). Index order is the record's.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| <wizard> SLEW THE LICH LORD (`lich`, M_LICH 0) (!) not produced by default schedule | Shown after a non-final Lich is slain; rank weight 60 | Noted during the run | none | game/logic/results.gd:20 | test_boss_ghostwriter.gd, test_results.gd, test_world.gd |
| <wizard> SLEW THE ARCHLICH (`archlich`, M_ARCHLICH 1) | Shown after the Archlich is slain; rank weight 100 | Noted during the run | none | game/logic/results.gd:21 | test_achievements.gd, test_profile.gd, test_results.gd |
| <wizard> FOUND <detail> (`chest`, M_CHEST 2) | Shown after a LEGENDARY or better chest is opened; rank weight 50 | Noted during the run | none | game/logic/results.gd:22 | test_achievements.gd, test_results.gd |
| <wizard> BLESSED THE PARTY (`blessing`, M_BLESSING 3) | Shown after THE SUN is drawn at a team shrine; rank weight 70 | Noted during the run | none | game/logic/results.gd:23 | test_achievements.gd |
| <wizard> CURSED THE PARTY (`curse`, M_CURSE 4) | Shown after DEATH is drawn at a team shrine; rank weight 75 | Noted during the run | none | game/logic/results.gd:24 | test_achievements.gd |
| <wizard> HIT THE JACKPOT (`jackpot`, M_JACKPOT 5) | Shown after a solo-shrine JACKPOT; rank weight 45 | Noted during the run | none | game/logic/results.gd:25 | test_achievements.gd, test_results.gd |
| <wizard> CHAINED A <detail> COMBO (`combo`, M_COMBO 6) | Shown after a combo of 100, 200 or 400; rank weight 40 | Noted during the run | none | game/logic/results.gd:26 | test_achievements.gd, test_results.gd |
| <wizard> EVOLVED <detail> (`evolve`, M_EVOLVE 7) | Shown after a spell evolves; rank weight 30 | Noted during the run | none | game/logic/results.gd:27 | test_achievements.gd, test_results.gd |
| <wizard> DREW <detail> (`card`, M_CARD 8) | Shown after a monster card is found; rank weight 90 | Noted during the run | none | game/logic/results.gd:28 | none |
| <wizard> SLEW <detail> (`act_boss`, M_ACT_BOSS 9) | Shown after an act boss is slain (THE BONE CHANDELIER or THE GHOST WRITER); rank weight 60 | Noted during the run | none | game/logic/results.gd:29 | test_achievements.gd, test_boss_ghostwriter.gd |

## 31. Results-screen awards

Awards go only to the wizard who really leads the stat; a wizard who leads several shows the first. In a party anyone
left without one is a TEAM PLAYER.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| MVP (`damage`) | Highest damage | Computed from the run's stats | none | game/logic/results.gd:46 | test_results.gd |
| SLAYER (`kills`) | Highest kills | Computed from the run's stats | none | game/logic/results.gd:47 | none |
| HIGH ROLLER (`bets`) | Highest bets | Computed from the run's stats | none | game/logic/results.gd:48 | test_results.gd |
| LUCKY (`best_tier`) | Highest best_tier | Computed from the run's stats | none | game/logic/results.gd:49 | none |
| GOLD DIGGER (`gold`) | Highest gold | Computed from the run's stats | none | game/logic/results.gd:50 | none |
| UNTOUCHABLE (`falls`) | Fewest falls (lives lost plus falls in a party) | Computed from the run's stats | none | game/logic/results.gd:51 | test_results.gd |
| TEAM PLAYER | Given in a party to a wizard with no other award | Computed from the run's stats | none | game/logic/results.gd:53 | test_results.gd |

Results stats kept per wizard (results.gd:40): damage, kills, elites, best_combo, chests, best_tier, gold, bets,
deaths, level, downs, revives. Damage-by-spell page also names the sources NOVA, ORBIT, JUSTICE.

## 32. Talk lines

Three speakers; every line has a condition (`first`, `new_card`, `loss`, `win`, `act1`-`act3`, `seal`, `apprentice`,
`idle`); lines are upper case, at most two rows of 52 characters.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| SHOPKEEPER (speaker 0) | 12 lines (first 1, new_card 1, loss 1, win 1, act1 1, act2 1, act3 1, seal 1, apprentice 1, idle 3) | Sells the Sanctum's unlocks; talks on a first visit, after a run, on each act, on a Seal | portrait key `shopkeeper` | game/logic/talk.gd:32 | test_profile.gd, test_talk.gd |
| CARD READER (speaker 1) | 12 lines (first 1, new_card 1, loss 1, win 1, act1 1, act2 1, act3 1, seal 1, apprentice 1, idle 3) | Fates, Seals and spell pairs | portrait key `card_reader` | game/logic/talk.gd:45 | test_talk.gd |
| MORVANE (speaker 2) | 12 lines (first 1, loss 2, win 1, act1 2, act2 2, act3 1, seal 1, apprentice 1, idle 1) | Taunts after a run and in each lull of the run | portrait key `archlich` | game/logic/talk.gd:58 | test_profile.gd, test_talk.gd |

Talk lines total 36 (SHOPKEEPER 12, CARD READER 12, MORVANE 12).

## 33. Acts (Lore)

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Source | Test |
|---|---|---|---|---|---|
| ACT I: THE OSSUARY | Subtitle "WHERE THE TOWER KEEPS ITS DEAD"; first minute 0; weights of the eight added kinds: BLOAT, COFFIN, GUARD (weight 1 each); CINDERLING, CENSOR, HOUND, SHARD, SWORDS weigh 0 | Minute 0 of the run | act boss: THE BONE CHANDELIER at 5:00 | game/logic/lore.gd:16 | test_bestiary.gd, test_lore.gd |
| ACT II: THE BURNING LIBRARY | Subtitle "EVERY BOOK A SPELL, EVERY SPELL ON FIRE"; first minute 5; weights of the eight added kinds: BLOAT, COFFIN, GUARD, CINDERLING, CENSOR, HOUND (1 each); SHARD, SWORDS weigh 0 | Minute 5 of the run | act boss: THE GHOST WRITER at 10:00 | game/logic/lore.gd:17 | test_bestiary.gd, test_lore.gd |
| ACT III: THE STARLESS SANCTUM | Subtitle "UNDER THE COMET, MORVANE ASCENDS"; first minute 10; weights of the eight added kinds: BLOAT, CINDERLING, HOUND, SHARD, SWORDS (1 each); COFFIN, GUARD, CENSOR weigh 0 | Minute 10 of the run | act boss: the Archlich at 15:00 | game/logic/lore.gd:18 | test_bestiary.gd, test_lore.gd |

Story text (lore.gd): 4 prologue pages (THE BLACK COMET, MORVANE, THE TOWER, THE LAST COVEN); 15 minute banner lines
(2 blank: they use the boss banner); 12 elite epithets; 2 victory lines and 2 defeat lines; boss titles `MORVANE, LICH
LORD`, `MORVANE ASCENDANT`, `THE ARCHLICH`. Elites: one every 45 s (tuning `elite_interval`), hp x8, drop gems, a
chest and a party tome.

## 34. Families found that the job text did not name

- Pickups (table 14), rarity tiers (12), hazard kinds (23), formations (19), omens (20), Minor Arcana (5), class
  weapon skins and skills (8), Ouija words (29), well fortunes (26), acts and story text (33), results awards (31),
  `Wizards` robes (6).
- Not tabled (they are rules, not content rows): urns (5 along the walls, replaced each minute; drop coins, gems,
  potions, a rare chest 3%, the card run's card), rifts, apprentices (computer wizards: damage x0.7, count 0.7 of a
  wizard), the fallen and rituals, the combo calls (`World.COMBO_CALLS`: 10 SMASHING!, 25 ARCANE CARNAGE!, 50
  WIZARDLY!, 100 TOTAL SORCERY!, 200 LEGENDARY!), the controls and settings.
- Painted card files `cards/monsters/cinderling.png` and `ten_of_swords.png` exist (art.gd:18, `NEW_MONSTERS`) but
  `Cards.CARDS` has no row for those kinds, so nothing shows them.

## 35. Rows marked (!)

- Minor Arcana: CUPS (`cups`): text says +1 HEART; code heals 1 heart and does not raise max hearts (levels.gd:114)
- Classes: PRIEST (`priest`): MIGHT 25 points is far above every other class and race value (0-5) and above the
  10-point cap on spent points (hero.gd:13)
- Team fates: THE WORLD! (`world`, tarot `world`, id 2): no painted card and no code emblem: the reel shows the card
  back with the title on a plate (fate_view.gd:229-246)
- Team fates: THE EMPEROR! (`emperor`, tarot `emperor`, id 3): no painted card and no code emblem: the reel shows the
  card back with the title on a plate (fate_view.gd:229-246)
- Team fates: HANGED MAN! (`hanged`, tarot `hanged`, id 5): no painted card and no code emblem: the reel shows the
  card back with the title on a plate (fate_view.gd:229-246)
- Team fates: HIEROPHANT! (`hierophant`, tarot `hierophant`, id 6): no painted card and no code emblem: the reel shows
  the card back with the title on a plate (fate_view.gd:229-246)
- Team fates: WHEEL TURNS! (`wheel`, tarot `wheel`, id 7): no painted card and no code emblem: the reel shows the card
  back with the title on a plate (fate_view.gd:229-246)
- Monster cards: THE DROPLET (`mslime`, index 3): no painted card file (assets/art/cards/monsters/mslime.png); the
  code-drawn face is used
- Seal cards: THE HUNGER (`seal_1`, index 12): no painted card file; the card face shows a plain stand-in with its
  numeral (monster_card.gd:47)
- Seal cards: THE AMBUSH (`seal_2`, index 13): no painted card file; the card face shows a plain stand-in with its
  numeral (monster_card.gd:47)
- Seal cards: THE FAMINE (`seal_3`, index 14): no painted card file; the card face shows a plain stand-in with its
  numeral (monster_card.gd:47)
- Seal cards: THE LEGION (`seal_4`, index 15): no painted card file; the card face shows a plain stand-in with its
  numeral (monster_card.gd:47)
- Seal cards: THE CHAMPION (`seal_5`, index 16): no painted card file; the card face shows a plain stand-in with its
  numeral (monster_card.gd:47)
- Seal cards: MISFORTUNE (`seal_6`, index 17): no painted card file; the card face shows a plain stand-in with its
  numeral (monster_card.gd:47)
- Seal cards: THE SILENCE (`seal_7`, index 18): no painted card file; the card face shows a plain stand-in with its
  numeral (monster_card.gd:47)
- Seal cards: THE DARKNESS (`seal_8`, index 19): no painted card file; the card face shows a plain stand-in with its
  numeral (monster_card.gd:47)
- Enemy kinds: LICH LORD (`lich`, type 7): the Archlich has no painted sprite file (Still.ARCHLICH `enemy_archlich` is
  not in assets/art/sprites)
- Bosses: MORVANE, LICH LORD / THE ARCHLICH (`lich`, final): a non-final Lich visit (moment M_LICH, 'SLEW THE LICH
  LORD') is not produced by the default schedule
- Bosses: Bosses.VISITS: two rows (7:00, 12:00) that no code reads (bosses.gd:13)
- Achievements: JACKPOT (`JACKPOT`): text says 'rune altar', the game calls the place a gamble shrine; the rule needs
  a solo-shrine JACKPOT outcome
- Result moments: <wizard> SLEW THE LICH LORD (`lich`, M_LICH 0): not produced at default tuning: the default schedule
  has no non-final Lich visit (bosses.gd:421-427)

The lead's notes on these rows (28 Nov 2026):
- PRIEST, MIGHT 25: as designed (`docs/classes_design.md:35`, "MIGHT +25 points": her candle's ticks are small).
  Whether it is right is the tune stage's question, not a fault.
- CUPS's "+1 HEART" is a wording fault (the cards use "+1 HEART" for one more heart to hold; CUPS heals one):
  fixed with the stage 1 wording pass. The JACKPOT deed's "rune altar" is right: the game shows the solo shrine to
  the player as RUNE ALTAR (`game/arena/events.gd:188`); "gamble shrine" is only the code's name for it.
- `Bosses.VISITS` and the moment M_LICH (Morvane's visits at 7:00 and 12:00) are an idea left half built: part 2
  decides whether the visits are built or the rows go. Decided in § 51: the rows go.
- The cards and sprites with no painted file (five team fates, THE DROPLET, the eight Seal cards, the Archlich) are
  stage 4's list. The two painted cards with no `Cards.CARDS` row (cinderling, ten_of_swords) are part 2's: they get
  their rows in § 48.

## Part 2. The frozen list (stage 2, 28 Nov 2026)

## 36. How to read part 2

Part 2 is the list the game is built to in stage 3. Part 1 says what the code holds today; part 2 says what the
finished game holds. Where the two differ, part 2 is the plan and the Change column names the difference.

Frozen: which rows exist, their names and code keys, what each one does, how it is got, what it pairs with and how it
is tested. A row is added, dropped or re-paired only with a line in `docs/handoff.md` that says why.
Not frozen: numbers. Every number in part 2 is a starting value. Stage 5 tunes them against the gates of § 53, and
they live in `Tuning` or the data tables, never in this file after they are built.

A part 1 section that part 2 does not name is frozen as built: the lobby robes (§ 6), weapon skins and skills (§ 8),
races (§ 9), the fate deck (§ 10), the solo shrine (§ 11), rarity tiers (§ 12), chest items (§ 13), pickups (§ 14,
but ORBIT changes: § 38), enemy kinds and the horde (§ 17 to 20), bosses and their attacks (§ 21, 22), hazards (§ 23),
the Sanctum (§ 26), secrets, ouija words, moments, awards, talk lines and acts (§ 28 to 33; the talk lines that name
pairs are rewritten: § 51).

Change column: `as built` (part 1 holds the numbers), `changed` (what changes), `new`.

Test column, one letter per kind of proof. A row is built only when every letter it carries is green.
- **U** a unit test that names the row's key and proves its rule with numbers. Written first and seen red.
- **D** a row of the damage table (`GD -s T/tool.gd -- spell_dps --gate`) held against the gates of § 53.
- **S** a `sim_horde` row with four wizards holding it, inside the step budget.
- **B** the coverage robot: a robot run that is dealt the row by force, ends with no engine error, and credits the row
  (damage by source for a spell or an evolution; the row's use counter for anything else: § 52). Stage 3's gate is
  every B green on the four PCs.
- **C** a career or win-rate measure in stage 5 (robot careers on the four PCs).

Counts (part 2): Spells 11 (10 shared, 1 class) · Arcana a wizard holds 14 · Evolutions 15 · Minor Arcana fillers 4 ·
Fate cards 8 · Readings 16 · Ladder steps 11 · Seal rules 8 · Boss rewards 7 · Shop rows 15 · Provisions 3 · Monster
cards 22 · Seal cards 8 · Deeds 65 · Classes 5 · Class level 5 effects 5 · Catalog rows 44 (32 today).

## 37. The frame: one tarot deck, every card with a job

The game is dealt from one tarot deck. A player who knows tarot can guess what a card does, and a player who does
not learns the deck by playing it.

- **The 22 Major Arcana** are split in two. Fourteen are the arcana a wizard holds (§ 39). Eight are the fate deck of
  the team shrine (§ 10, as built): THE FOOL, THE EMPEROR, THE HIEROPHANT, WHEEL OF FORTUNE, THE HANGED MAN, DEATH,
  THE SUN, THE WORLD. Upright, no Major Arcana is left without a job and none has two.
- **The Minor Arcana** are the Reading (§ 42): sixteen numbered cards, four of each suit, one kept before each run.
  The four plain suit cards stay the fillers of a short level-up hand (§ 5, as built). The title card, FOUR OF
  WANDS, is a Reading.
- **Reversed cards** are the Seals (§ 43): each of the eight Seals is a Major Arcana turned upside down.
- **One rule for every evolution:** the spell at level 5 and its arcana at level 1 or more. No spell needs another
  spell. Each arcana pairs with at least one spell, so no card in the deck is a dead pick.

The chart every pair is read from (the game draws it as THE SPREAD, § 41):

| Spell | + arcana | = evolution | + second arcana | = second evolution |
|---|---|---|---|---|
| ARCANE BOLT | THE MAGICIAN | ASTRAL LANCE | THE STAR | LODESTAR |
| FIREBALL | STRENGTH | GREEK FIRE | THE TOWER | THUNDERFIRE |
| FROST FAN | TEMPERANCE | BLIZZARD | THE HIGH PRIESTESS | WINTER VEIL |
| CHAIN LIGHTNING | THE CHARIOT | TEMPEST | JUDGEMENT | DIES IRAE |
| STARFALL | THE HERMIT | COMET RAIN | | |
| RUNE CIRCLE | THE MOON | SEAL OF SOLOMON | | |
| BONE SPEAR | JUSTICE | OSSUARY LANCE | | |
| VIGIL CANDLE | THE LOVERS | CONSECRATION | | |
| HEX | THE DEVIL | EVIL EYE | | |
| SPIRIT BLADES | THE EMPRESS | DANSE MACABRE | | |
| CLEAVE (knight) | STRENGTH | WHIRLWIND | | |

The six spells and six arcana a new profile starts with (§ 44) pair one to one, down the first three columns of the
first six rows: a first-night player can evolve every spell she is dealt. The four mage schools have a second road
each; taking one evolution closes the other for that run.

## 38. Spells

Eleven rows: ten any wizard can learn and the knight's CLEAVE. Each has one job, said in the first words of the row.
`n` is bolts, jumps, stars, circles or blades. New spells take the next `World.SP_*` index (HEX 9, SPIRIT BLADES 10)
and new rows go at the end of `Upgrades.CATALOG` (it is append-only).

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| ARCANE BOLT (`w_arcane`) | ONE TARGET. Fast auto-aimed bolts. Numbers as built | Open on a new profile; a MAGE school | ASTRAL LANCE (THE MAGICIAN) · LODESTAR (THE STAR) | changed: its pair was STARFALL | U D S B |
| FIREBALL (`w_fire`) | CROWD. A slow bolt that bursts. Numbers as built | Open on a new profile; a MAGE school | GREEK FIRE (STRENGTH) · THUNDERFIRE (THE TOWER) | changed: its pair was CHAIN LIGHTNING | U D S B |
| FROST FAN (`w_frost`) | CROWD CONTROL. A fan of short bolts that slow. Numbers as built | Open on a new profile; a MAGE school | BLIZZARD (TEMPERANCE) · WINTER VEIL (THE HIGH PRIESTESS) | changed: its pair was ARCANE BOLT | U D S B |
| CHAIN LIGHTNING (`w_storm`) | CROWD. Jumps from foe to foe, weaker each jump. Numbers as built | Open on a new profile; a MAGE school | TEMPEST (THE CHARIOT) · DIES IRAE (JUDGEMENT) | changed: its pair was FIREBALL | U D S B |
| STARFALL (`w_star`) | ONE TARGET, HOMING. Slow stars that turn after their foe. Numbers as built | Open on a new profile; the PALADIN's weapon | COMET RAIN (THE HERMIT) | changed: its pair was FROST FAN | U D S B |
| RUNE CIRCLE (`w_rune`) | ZONE. Sigils on the floor that burn what stands in them. Numbers as built | Open on a new profile | SEAL OF SOLOMON (THE MOON) | changed: its pair was STARFALL | U D S B |
| BONE SPEAR (`w_bone`) | LINE. Two spears that pierce everything in their path. Numbers as built | Deed THE LAST WORD; always open to an ARCHER (her weapon) | OSSUARY LANCE (JUSTICE) | changed: locked on a new profile | U D S B |
| VIGIL CANDLE (`w_candle`) | SUPPORT. A light that burns foes a little and hastes the wizards in it. Numbers as built | Deed OMEN-PROOF; always open to a PRIEST (her weapon) | CONSECRATION (THE LOVERS) | changed: locked on a new profile | U D S B |
| HEX (`w_hex`) | SUPPORT. A curse thrown at the toughest foe within 160 px: cd 1.6/1.45/1.3/1.15/1.0 s; dmg 5/5.5/6/6.5/7. The hexed foe takes +25/30/35/40/45% damage from every wizard for 4 s (half of that on an elite or a boss). When it dies the hex jumps to the nearest foe within 70 px, up to 2/3/4/5/6 times. A hexed foe wears a violet mark every player can read | THE WITCH'S DECK at the shopkeeper (§ 45) | EVIL EYE (THE DEVIL) | new | U D S B |
| SPIRIT BLADES (`w_blades`) | CLOSE DEFENCE. 2/2/3/3/4 blades circle her at 30 px, one turn each 1.6 s, always out. A touch deals 1.2/1.45/1.7/1.95/2.2 and pushes the foe back; one foe is cut at most every 0.5 s. The ORBIT pickup lends any wizard 3 more blades for 12 s (its count and time today) | THE DUELLIST'S DECK at the shopkeeper (§ 45) | DANSE MACABRE (THE EMPRESS) | new; the ORBIT pickup's own damage source goes | U D S B |
| CLEAVE (`w_cleave`) | MELEE ARC, the knight's. Numbers as built | Comes with the KNIGHT (deed HOLD THE TOWER); only a knight is offered it | WHIRLWIND (STRENGTH) | changed: the KNIGHT is locked on a new profile | U D S B |

How the arcana change a spell that is not a bolt: THE MAGICIAN turns SPIRIT BLADES faster. THE STAR adds bolts,
jumps, stars, circles, lights or blades, and widens a sweep's arc by a half for each missile. THE HIGH PRIESTESS
echoes a cast, or makes every fourth, third or second touch of a blade cut twice. THE EMPRESS widens every area named
in her row.

## 39. Arcana a wizard holds (passives)

Fourteen rows. Each takes an arcana slot and each is one half of a pair. THE TOWER and JUDGEMENT were instant picks
that took no slot (§ 4): they become held arcana with a second effect, and the kind INSTANT has no rows left.
Lesson kept from wave 3: an effect nobody can see is cut, so every new arcana shows on screen.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| I THE MAGICIAN (`quick`) | Cast faster. Numbers as built (5 levels, weight 10) | Open on a new profile | ASTRAL LANCE (ARCANE BOLT) | changed: gains a pair | U B |
| II THE HIGH PRIESTESS (`priestess`) | Every 4th / 3rd / 2nd cast of each spell is cast twice: the echo follows 0.15 s later at the same aim, drawn pale. 3 levels, weight 6 | THE VEILED DECK at the shopkeeper (§ 45) | WINTER VEIL (FROST FAN) | new (her painted card is in the repo) | U D S B |
| III THE EMPRESS (`empress`) | Every area is 10 / 20 / 30% wider: blasts, bursts and splinters, rune and candle circles, a sweep's reach, the blades' ring, the hex's jump, the veil. 3 levels, weight 7 | THE DUELLIST'S DECK at the shopkeeper (§ 45) | DANSE MACABRE (SPIRIT BLADES) | new | U D B |
| VI THE LOVERS (`lovers`) | Cast faster near an ally. Numbers as built (3 levels, weight 7) | Deed OMEN-PROOF; always open to a PRIEST | CONSECRATION (VIGIL CANDLE) | changed: locked on a new profile | U B |
| VII THE CHARIOT (`swift`) | Move faster. Numbers as built (5 levels, weight 10) | Open on a new profile | TEMPEST (CHAIN LIGHTNING) | changed: gains a pair | U B |
| VIII STRENGTH (`power`) | More damage. Numbers as built (5 levels, weight 10) | Open on a new profile | GREEK FIRE (FIREBALL) · WHIRLWIND (CLEAVE) | changed: gains a second pair | U B |
| IX THE HERMIT (`wisdom`) | More XP. Numbers as built (3 levels, weight 7) | Open on a new profile | COMET RAIN (STARFALL) | changed: gains a pair | U B |
| XI JUSTICE (`justice`) | A slain foe may burst. Numbers as built (3 levels, weight 7) | Deed THE LAST WORD; always open to an ARCHER | OSSUARY LANCE (BONE SPEAR) | changed: locked on a new profile | U B |
| XIV TEMPERANCE (`regen`) | A heart back every 18 / 12 / 8 s. Numbers as built (3 levels, weight 6) | Open on a new profile | BLIZZARD (FROST FAN) | changed: gains a pair | U B |
| XV THE DEVIL (`devil`) | +12 / 18 / 24% damage for each heart she is missing, at most 4 hearts counted. Her staff burns red while it holds. 3 levels, weight 6 | THE WITCH'S DECK at the shopkeeper (§ 45) | EVIL EYE (HEX) | new | U D B |
| XVI THE TOWER (`nova`) | +1 nova charge at once, each level. Then a charge comes back every 75 / 60 / 45 s while she holds fewer than 3. 3 levels, weight 5. The build of a hero who lives by her class skill | Deed EVOLUTION | THUNDERFIRE (FIREBALL) | changed: was an instant pick of 5 levels with no slot and no refill | U B |
| XVII THE STAR (`star`) | +1 / +2 missiles for every spell (§ 38 says what a missile is for each). 2 levels, weight 5 | Deed THE FIRST PAGE | LODESTAR (ARCANE BOLT) | new (its painted card is in the repo) | U D S B |
| XVIII THE MOON (`magnet`) | Wider XP pull. Numbers as built (3 levels, weight 7) | Open on a new profile | SEAL OF SOLOMON (RUNE CIRCLE) | changed: gains a pair | U B |
| XX JUDGEMENT (`life`) | +1 life at once, each level. When she spends a life she rises with a nova's blast that costs no charge. 2 levels, weight 4. SEAL VIII still bans it | Deed THE TOWER REMEMBERS | DIES IRAE (CHAIN LIGHTNING) | changed: was an instant pick with no slot and no blast | U B |

## 40. Evolutions

Fifteen rows. An evolution replaces its spell's level 5 numbers and adds one new behaviour, said in its card's two
or three words: at most 14 letters, what a row of the level-up tray holds (a name holds 15; the tray writes THE HIGH
PRIESTESS as HIGH PRIESTESS). The card weighs 40, and a row that completes a pair weighs four times more in the roll
(as built). Two evolutions of one spell are told apart by an id where the code holds a flag today (§ 52). The words
on the new spells' and arcana's cards are in `docs/stage3_brief.md` § 4.2.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| ASTRAL LANCE (`e_arcane`) | PIERCING BOLTS. Numbers as built. The crowd road for ARCANE BOLT | ARCANE BOLT 5 + THE MAGICIAN | THE MAGICIAN | changed: its partner was STARFALL | U D S B |
| LODESTAR (`e_lodestar`) | HUNTS BIG PREY. cd 0.12 s; dmg 3; n 3. Bolts turn after the toughest foe within 160 px and deal double to elites and bosses. The boss road for ARCANE BOLT | ARCANE BOLT 5 + THE STAR | THE STAR | new | U D S B |
| GREEK FIRE (`e_greek`) | BURNING GROUND. cd 0.8 s; dmg 3; n 2. Each blast leaves a burning patch of 28 px for 3 s that ticks 1.2 each 0.5 s | FIREBALL 5 + STRENGTH | STRENGTH | new | U D S B |
| THUNDERFIRE (`e_fire`) | ZAPPING BLASTS. Numbers as built | FIREBALL 5 + THE TOWER | THE TOWER | changed: its partner was CHAIN LIGHTNING | U D S B |
| BLIZZARD (`e_frost`) | A STORM OF ICE. Numbers as built | FROST FAN 5 + TEMPERANCE | TEMPERANCE | changed: its partner was ARCANE BOLT | U D S B |
| WINTER VEIL (`e_veil`) | CLOAK OF FROST. The fan keeps its level 5 numbers, and a mist of 40 px stays on her: foes in it are slowed as by the fan and take 1.6 each 0.5 s | FROST FAN 5 + THE HIGH PRIESTESS | THE HIGH PRIESTESS | new | U D S B |
| TEMPEST (`e_storm`) | TWIN CHAINS. Numbers as built | CHAIN LIGHTNING 5 + THE CHARIOT | THE CHARIOT | changed: its partner was FIREBALL | U D S B |
| DIES IRAE (`e_dies`) | SLAYS THE WEAK. cd 0.6 s; dmg 5; n 7. Jumps do not weaken. A plain foe left under a fifth of its health by a jump dies; never an elite or a boss | CHAIN LIGHTNING 5 + JUDGEMENT | JUDGEMENT | new | U D S B |
| COMET RAIN (`e_star`) | ICY STARBURSTS. Numbers as built | STARFALL 5 + THE HERMIT | THE HERMIT | changed: its partner was FROST FAN | U D S B |
| SEAL OF SOLOMON (`e_rune`) | SIGILS PULL IN. Numbers as built | RUNE CIRCLE 5 + THE MOON | THE MOON | changed: its partner was STARFALL | U D S B |
| OSSUARY LANCE (`e_bone`) | SPLINTER HITS. Numbers as built | BONE SPEAR 5 + JUSTICE | JUSTICE | as built | U D S B |
| CONSECRATION (`e_candle`) | HEALING LIGHT. Numbers as built | VIGIL CANDLE 5 + THE LOVERS | THE LOVERS | as built | U D S B |
| EVIL EYE (`e_hex`) | HEXED BURST. cd 0.9 s; dmg 8; +50% damage taken; 6 jumps. A hexed foe bursts when it dies: half of its full health within 26 px, at most 40 a burst | HEX 5 + THE DEVIL | THE DEVIL | new | U D S B |
| DANSE MACABRE (`e_blades`) | A SECOND RING. 4 blades at 30 px and 4 more at 52 px turning the other way; 3 a touch | SPIRIT BLADES 5 + THE EMPRESS | THE EMPRESS | new | U D S B |
| WHIRLWIND (`e_cleave`) | A FULL CIRCLE. It strikes every foe in reach: the cap of 3 goes, and dmg starts at 24 (was 36) | CLEAVE 5 + STRENGTH; knight only | STRENGTH | changed: today it is weaker than CLEAVE 5 in a crowd (§ 53) | U D S B |

## 41. Level-up rules, the fillers and the chart

| Rule (code key) | What it is | Change | Test |
|---|---|---|---|
| The hand (`level_choices`) | Three cards; two under SEAL VII. Each wizard draws her own and nothing pauses (as built) | as built | U |
| Slots (`Upgrades.SLOTS_EARLY`, `SLOTS_LATE`) | 3 spells and 3 arcana until the first boss falls, then 4 and 4. TEN OF WANDS makes it 5 and 2 from the start | as built; the Reading is new | U B |
| Evolution rule (`requires`) | The spell at level 5 and its arcana at level 1 or more. A school spell's two evolutions shut each other out for the run | changed: six partners were spells | U |
| Redraws and banishes (`REDRAWS`, `BANISHES`) | 2 and 2 for each wizard each run, plus the shop's THE SECOND GLANCE and THE BLACK RIBBON, plus the card THE GHOST WRITER | changed: three sources add to them | U |
| Free spell levels (`party_tome_elite`) | An elite drops a PARTY TOME 0.35 of the time (was every time: up to twenty free levels a run, which chose the build for her). Each of the first two bosses still drops one; an urn holds one at 0.02 | changed | U C |
| Locked rows (the profile's mask) | A row the profile has not opened (§ 44) is never dealt: the path SEAL VIII uses to ban JUDGEMENT. A hero's class weapon, its arcana and its evolution are always open to her. The host's profile sets the mask for the table | new | U B |
| Fillers (`cups`, `pentacles`, `swords`, `wands`) | The four Minor Arcana that fill a short hand, as built (§ 5) | as built | U |
| THE SPREAD (the chart) | A page in the pause menu and at the card reader's table: every spell with its arcana and its evolutions, read from the catalog's `requires` and never typed twice. A locked row lies face down and says how it opens. The rows a wizard holds are lit | new | U |

## 42. The Reading

Before each run the table is dealt three Minor Arcana from the run's seed and keeps one; it changes that run's rules.
Every seat votes, seat 1 breaks a tie, and a seat that does not vote in 15 s abstains. A card marked PARTY is dealt
only to a table of two or more (an apprentice counts). The Reading opens for a profile when THE BONE CHANDELIER first
falls, with the four aces and FOUR OF WANDS; the other eleven are opened by deeds (§ 44). The five opening cards are
gifts, so the first Readings teach the idea kindly; each of the other eleven takes something or raises the danger for
what it gives. A Reading's values merge into the run after the Seal's (the path `Seals.values` uses), so a Reading
and a Seal that touch the same number multiply.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| ACE OF WANDS (`r_wands_1`) | Every wizard starts with a second spell at level 1, drawn from the seed among the open spells she does not hold | With the Reading (deed BRING DOWN THE HOUSE) | Any build: a head start on a second evolution | new | U B C |
| FOUR OF WANDS (`r_wands_4`) | The title card. An apprentice joins the table for this run. With all four seats taken, every wizard has +1 heart | With the Reading | The solo and two-player table; THE LOVERS | new | U S B C |
| EIGHT OF WANDS (`r_wands_8`) | Everything is a fifth faster: wizards, foes, bolts, the horde's clock, and XP comes a fifth faster too | Deed TOTAL SORCERY | THE CHARIOT; a table that wants a shorter, harder run | new | U S B C |
| TEN OF WANDS (`r_wands_10`) | The burden: 5 spell slots and 2 arcana slots from the first second | Deed THE KEY OF SOLOMON | STRENGTH (the one arcana with two pairs) | new; the tray must hold 5 and 2 | U B C |
| ACE OF CUPS (`r_cups_1`) | Every wizard has +2 hearts | With the Reading | THE DEVIL (more hearts to be missing) | new | U B C |
| TWO OF CUPS (`r_cups_2`) PARTY | The bond: a hit takes its heart from the wizard who holds the most | Deed SECOND WIND | A table with a KNIGHT or a PRIEST | new | U B C |
| FIVE OF CUPS (`r_cups_5`) | No potions drop. Every boss phase and every boss death heals every wizard to full | Deed THE UPPER SHELF | TEMPERANCE; CONSECRATION | new | U B C |
| NINE OF CUPS (`r_cups_9`) | The wish: each wizard's first two hands hold only arcana, and their redraws are free. Her second spell comes later for it | Deed BLESSED BE | The pair she plans to evolve | new | U B C |
| ACE OF SWORDS (`r_swords_1`) | Every wizard has +2 nova charges, and each time a boss arrives her charges are filled back to what she started the run with | With the Reading | THE TOWER; class skills | new | U B C |
| THREE OF SWORDS (`r_swords_3`) | Hearts are capped at 3. All damage is x1.6 | Deed WORTH IT | THE DEVIL; JUDGEMENT | new | U B C |
| SEVEN OF SWORDS (`r_swords_7`) | Elites come twice as often and each one drops a PARTY TOME | Deed MASS GRAVE | Any evolution plan: more free spell levels for more danger | new | U S B C |
| TEN OF SWORDS (`r_swords_10`) | TEN OF SWORDS foes join the horde from 1:00; the horde is a fifth bigger; XP is x1.3 | Deed FIRST SEAL BROKEN | THE HERMIT; crowd spells | new | U S B C |
| ACE OF PENTACLES (`r_pent_1`) | Every wizard starts with 150 gold and a gamble shrine stands at the door | With the Reading | The team shrine and the fate deck | new | U B C |
| FOUR OF PENTACLES (`r_pent_4`) | The miser: no shrines appear. Every 100 gold a wizard picks up heals her a heart | Deed JACKPOT | The card THE CUTPURSE; MIDAS' PURSE | new | U B C |
| NINE OF PENTACLES (`r_pent_9`) | Every chest holds two items. Foes have a fifth more health | Deed THE LONG HARVEST | FOUR-LEAF RUNE; the satchel | new | U B C |
| TEN OF PENTACLES (`r_pent_10`) | The run is played at the next step's numbers and rule, and pays double crystals | Deed THE LAST LICH (the first win) | The ladder: a look at the next step before it is open | new | U B C |

THE READER'S FAVOUR (§ 45) deals the three again once a run, then deals four. The Daily Draw (§ 49) deals one card
and nobody chooses.

## 43. The ladder and the reversed Seals

Eleven steps, as built, with more weight on each. ARCHMAGE is no longer open on a new profile: the WIZARD win opens
it (`START_UNLOCKED` 0; an old profile keeps what it has). Starting numbers: ARCHMAGE enemy health x1.20 and boss
health x1.25 (today x1.08 and x1.15); each Seal adds +0.08 enemy health, +0.05 horde and +0.10 boss health on the
step below (today +0.03, +0.03, +0.06). The crystal bounty, chest luck and first-win prize of each step are as built
(§ 24). Each Seal is a Major Arcana reversed: its card is that arcana upside down under a red seal, its rule is that
arcana's gift turned against the table. Rules pile up: SEAL V is played under the rules of I to V.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| APPRENTICE (step -1) | As built: gentler foes, +2 hearts, twice the potions, half the crystals | Open on a new profile | none | as built | U C |
| WIZARD (step 0) | The game as tuned | Open on a new profile | The Daily Draw is always played here | as built | U C |
| ARCHMAGE (step 1) | Enemy health x1.20, boss health x1.25 | A win at WIZARD | Its first win opens FIVE OF CUPS | changed: locked on a new profile; numbers up | U C |
| SEAL I, HUNGER (step 2) | THE EMPRESS REVERSED. Potions from kills x0.6. Health x1.28, horde x1.05, boss x1.35 | A win at ARCHMAGE | Card THE HUNGER; its first win opens TEN OF SWORDS | changed: numbers up | U B C |
| SEAL II, AMBUSH (step 3) | THE HIGH PRIESTESS REVERSED. Rifts warn half as long, and so do the three omens (`omen` 0.5). Health x1.36, horde x1.10, boss x1.45 | A win at SEAL I | Card THE AMBUSH; opens THE BLACK RIBBON level 2 | changed: the omen half is new; numbers up | U B C |
| SEAL III, FAMINE (step 4) | TEMPERANCE REVERSED. A potion heals one heart. Health x1.44, horde x1.15, boss x1.55 | A win at SEAL II | Card THE FAMINE; opens THE SATCHEL level 2 | changed: numbers up | U B C |
| SEAL IV, LEGION (step 5) | THE EMPEROR REVERSED. Groups a quarter bigger, cap 325. Health x1.52, horde x1.20, boss x1.65 | A win at SEAL III | Card THE LEGION; opens RUNED STAFF levels 4 and 5 | changed: numbers up | U S B C |
| SEAL V, CHAMPIONS (step 6) | STRENGTH REVERSED. Elites have half again the health and an escort of 4. Health x1.60, horde x1.25, boss x1.75 | A win at SEAL IV | Card THE CHAMPION; opens THE SECOND GLANCE level 2 | changed: numbers up | U B C |
| SEAL VI, MISFORTUNE (step 7) | WHEEL OF FORTUNE REVERSED. The cruel side comes up 0.6 of the time, and a cruel fate is drawn on the table as each act boss arrives (`boss_fate`), solo too. Health x1.68, horde x1.30, boss x1.85 | A win at SEAL V | Card MISFORTUNE; opens THE READER'S FAVOUR level 2 | changed: the boss fate is new; numbers up | U B C |
| SEAL VII, SILENCE (step 8) | THE HIEROPHANT REVERSED. Hands of two cards. Health x1.76, horde x1.35, boss x1.95 | A win at SEAL VI | Card THE SILENCE; opens THE HEAD START level 2 | changed: numbers up | U B C |
| SEAL VIII, DARKNESS (step 9) | THE SUN REVERSED. One life (two alone), no JUDGEMENT, rituals take twice as long. Health x1.84, horde x1.40, boss x2.05 | A win at SEAL VII | Card THE DARKNESS; a gold rim on her seat and name | changed: numbers up; the rim is new | U S B C |

## 44. The unlock track

What a new profile holds, and the deed that opens each thing after it. The aim is one new thing about every second
run up to the first win, then one for each step of the ladder. A guest seat always plays one of the four preset
heroes (`Net.GUEST_PRESETS`: a HUMAN MAGE, an ELF ARCHER, a DWARF KNIGHT, an ORC PRIEST), so a first night with four
on the couch already shows four classes; the locks are on the heroes a profile may build and on the deck it is dealt.
An old profile opens everything its record proves: the deeds it holds, and the class and race of every hero saved.

Open on a new profile:
- the MAGE with her four schools; HUMAN and ELF;
- ARCANE BOLT, FIREBALL, FROST FAN, CHAIN LIGHTNING, STARFALL, RUNE CIRCLE;
- THE MAGICIAN, STRENGTH, TEMPERANCE, THE CHARIOT, THE HERMIT, THE MOON;
- APPRENTICE and WIZARD; every shop level that § 43 does not hold back for a Seal; one satchel pocket.

| Deed that opens it (code key) | What opens | About when | Change | Test |
|---|---|---|---|---|
| THE FIRST PAGE (`LEVEL_5`) | THE STAR | The first run | new deed | U B C |
| BRING DOWN THE HOUSE (`BOSS_CHANDELIER`) | The Reading, with ACE OF WANDS, ACE OF CUPS, ACE OF SWORDS, ACE OF PENTACLES and FOUR OF WANDS | Run 2 or 3 | new unlock | U B C |
| EVOLUTION (`EVOLVE`) | THE TOWER | Run 2 to 4 | new unlock | U C |
| HOLD THE TOWER (`TEN_MINUTES`) | The KNIGHT (with CLEAVE and WHIRLWIND) and the DWARF | Run 4 to 6 | new unlock | U C |
| THE TOWER REMEMBERS (`FALLS_5`) | JUDGEMENT | The fifth run lost | new deed | U C |
| THE LAST WORD (`BOSS_GHOSTWRITER`) | The ARCHER, BONE SPEAR and JUSTICE | Run 5 to 8 | new unlock | U C |
| OMEN-PROOF (`OMENS`) | The PRIEST, the ORC, VIGIL CANDLE and THE LOVERS | Run 6 to 10 | new unlock | U C |
| THE LAST LICH (`ARCHLICH`) | The PALADIN, Overtime, the Daily Draw and TEN OF PENTACLES | The first win | new unlock | U C |
| A win at WIZARD | ARCHMAGE | The first win, or the one after an APPRENTICE win | changed | U C |
| TOTAL SORCERY (`COMBO_200`) | EIGHT OF WANDS | By play | new unlock | U |
| THE KEY OF SOLOMON (`SEAL`) | TEN OF WANDS | By play | new unlock | U |
| SECOND WIND (`REVIVE_3`) | TWO OF CUPS | By play at a table of two or more | new unlock | U |
| BLESSED BE (`BLESSED`) | NINE OF CUPS | By play at a team shrine | new unlock | U |
| WORTH IT (`CURSED`) | THREE OF SWORDS | By play at a team shrine | new unlock | U |
| JACKPOT (`JACKPOT`) | FOUR OF PENTACLES | By play at a rune altar | new unlock | U |
| MASS GRAVE (`KILLS_10K`) | SEVEN OF SWORDS | About the first win | new unlock | U |
| THE LONG HARVEST (`KILLS_100K`) | NINE OF PENTACLES | Deep in the ladder | new unlock | U |
| THE UPPER SHELF (`WIN_ARCHMAGE`) | FIVE OF CUPS | The ARCHMAGE win | new unlock | U |
| FIRST SEAL BROKEN (`WIN_SEAL_1`) | TEN OF SWORDS | The SEAL I win | new unlock | U |
| The wins at SEAL II to VIII | The shop levels and the rim named in § 43 | One a step | new unlock | U |
| Crystals at the shopkeeper | HEX with THE DEVIL · SPIRIT BLADES with THE EMPRESS · THE HIGH PRIESTESS (§ 45) | When she chooses | new | U |

## 45. The shop

Crystals are earned only (§ 25, as built). The shopkeeper has three shelves and a counter: fourteen rows that stay
bought (6,170 crystals to own them all; 940 today), A CLEAN SLATE, and three provisions that are used up. An old
profile keeps the levels it bought; RUNED STAFF's three old levels are worth 12% in place of 15%.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| WARDED ROBES (`vigor`) | +1 heart a level, 2 levels | 40, 160 crystals | none | changed: prices (were 30, 90) | U |
| RUNED STAFF (`might`) | +4% damage a level, 5 levels; levels 4 and 5 open at the SEAL IV win | 30, 70, 150, 300, 600 | none | changed: was +5% for 3 levels (20, 50, 110) | U |
| FORBIDDEN LORE (`wisdom`) | +6% XP a level, 3 levels | 30, 80, 200 | none | changed: prices (were 20, 50, 110) | U |
| MIDAS' PURSE (`fortune`) | +15% gold a level, 3 levels | 20, 60, 150 | none | changed: prices (were 15, 40, 90) | U |
| BOTTLED STAR (`novas`) | +1 nova a level, 2 levels | 40, 140 | none | changed: prices (were 25, 70) | U |
| FOUR-LEAF RUNE (`luck`) | +1 chest luck a level, 2 levels | 80, 240 | none | changed: prices (were 60, 160) | U |
| THE SECOND GLANCE (`redraw`) | +1 redraw each run a level, 2 levels; level 2 opens at the SEAL V win | 60, 220 | The level-up hand | new | U |
| THE BLACK RIBBON (`banish`) | +1 banish each run a level, 2 levels; level 2 opens at the SEAL II win | 60, 220 | The level-up hand | new | U |
| THE HEAD START (`start_level`) | The party starts at level 2, then 3, and keeps the lead all run (each later level costs what it would without it): each wizard draws those hands before the first door opens. Level 2 opens at the SEAL VII win | 120, 400 | The pair she plans | new | U B |
| THE SATCHEL (`satchel`) | One more pocket a level, 2 levels (§ 46); level 2 opens at the SEAL III win | 300, 900 | The satchel | new | U |
| THE READER'S FAVOUR (`favour`) | Level 1: the table may have the Reading dealt again once. Level 2: the Reading deals four cards. Level 2 opens at the SEAL VI win | 250, 750 | The Reading | new | U B |
| A CLEAN SLATE (`respec`) | Gives the active hero her stat points back to spend again | 50, each time | Hero stat points (§ 9) | new | U |
| THE WITCH'S DECK (`deck_hex`) | Opens HEX and THE DEVIL, and with them EVIL EYE | 150, once | § 38 to 40 | new | U |
| THE DUELLIST'S DECK (`deck_blades`) | Opens SPIRIT BLADES and THE EMPRESS, and with them DANSE MACABRE | 150, once | § 38 to 40 | new | U |
| THE VEILED DECK (`deck_priestess`) | Opens THE HIGH PRIESTESS, and with her WINTER VEIL | 200, once | § 39, 40 | new | U |

Provisions are sold at the counter into a satchel pocket and are used up by the next run (§ 46). Their keys are the
chest items' (§ 13).

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| ELIXIR (`elixir`) | The first time her hearts would reach none, she drinks it and stands at full hearts | 40 crystals | A step she has not won yet | new use of the chest item | U B |
| NOVA FLASK (`novas`) | She starts the run with 2 more nova charges | 25 | THE TOWER; class skills | new use of the chest item | U B |
| SIBYLLINE BOOK (`tome`) | Her class weapon starts the run at level 2 | 60 | Her first evolution | new use of the chest item | U B |

The reliquary's sealed deck stays 1,500 crystals for one monster card she lacks (§ 26); with 22 monster cards its
price is one of stage 5's numbers.

## 46. The satchel and keepsakes

The inventory bag the owner asked for on 21 Nov ("for consumable items and socketable collectables"). One small
screen among the mirror's hero screens shows everything the active hero carries into a run: her three sockets with
their cards (§ 15), her pockets, and her keepsake.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| Pocket (`satchel.pockets`) | Holds one item for her next run and is emptied by that run. Either a piece of armour she found in the run that just ended, picked on the results screen and worn from the first second at the tier it was found; or a provision from the counter (§ 45). A kept piece cannot be kept a second time | Every saved hero has one; THE SATCHEL gives each of the profile's heroes two more | Chest armour (§ 13); provisions | new | U B |
| Keepsake (`satchel.keepsake`) | An ULTRA RARE piece of armour is never lost: when its run ends it joins the profile's keepsakes for good. A hero wears one keepsake at a time; in later runs it counts at the EPIC value (twice the base). The prismatic chest always holds armour, so every ULTRA RARE find is a keepsake | The prismatic chest of an ULTRA RARE run (1 run in 100, as built); never under APPRENTICE | The six armour rows of § 13 | new; the prismatic chest no longer rolls a consumable | U B |
| The satchel screen | Sockets, pockets and keepsake on one page; a card, a piece or a provision is moved with one press | The mirror, from the first run | The album (§ 15) stays the collection | new | U |

A guest seat and an apprentice have no satchel. A scripted run never reads or writes one.

## 47. Heroes: class level 5

A hero's skill gains a second effect when she reaches class level 5 (`docs/classes_design.md`): about six to eight
runs with one hero at today's class XP (§ 9), so it lands near her first win. Levels 10 and 15 are not built in
stages 1 to 5.
The classes, races, skins and skills themselves are as built (§ 7 to 9); which of them a new profile may build is in
§ 44.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| NOVA, second effect (`nova`) | A foe the blast does not slay is slowed for 3 s | A MAGE at class level 5 | FROST FAN; THE TOWER | new | U B |
| PROVOKE, second effect (`provoke`) | A provoked foe takes a quarter more damage from every wizard while it is provoked | A KNIGHT at class level 5 | HEX; a table that focuses one foe | new | U B |
| VOLLEY, second effect (`volley`) | Her arrows pierce | An ARCHER at class level 5 | BONE SPEAR; JUSTICE | new | U B |
| SANCTUARY, second effect (`sanctuary`) | The fallen rise wherever they lie, not only within 80 px | A PRIEST at class level 5 | TWO OF CUPS; JUDGEMENT | new | U B |
| AEGIS, second effect (`aegis`) | When the shield ends it bursts like a nova | A PALADIN at class level 5 | THE TOWER; ACE OF SWORDS | new | U B |

## 48. Monster cards

Ten new rows, so each of the 22 enemy kinds has a card and the album has no gap that play cannot fill. How a card
drops is as built (§ 15): a card run, a Sanctum pot, a sealed deck. A boss's card drops from that boss in a card run
that names it. Sockets after the ten: ROBE 7, HAT 8, STAFF 7. Four cards carry a stat no card had (nova, XP, chest
luck, redraw). The eight Seal cards (§ 16) are as built.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| THE POWDER KEG (`bloat`, index 20) | STAFF socket; +1 nova each run; lore "DO NOT STAND SO CLOSE." | BLOAT in a card run; pots, sealed deck | monster BLOAT | new | U |
| THE LIGHT SLEEPER (`coffin`, index 21) | HAT socket; +8% XP; lore "KNOCK ONCE. IT WAS NEVER ASLEEP." | RESTLESS COFFIN in a card run; pots, sealed deck | monster RESTLESS COFFIN | new | U |
| THE SHIELD-BEARER (`guard`, index 22) | ROBE socket; 8% ward; lore "IT ONLY EVER FACED ONE WAY." | TOMB GUARD in a card run; pots, sealed deck | monster TOMB GUARD | new | U |
| THE FIRESTARTER (`cinderling`, index 23) | HAT socket; +8% speed; lore "IT RUNS BECAUSE IT BURNS." | CINDERLING in a card run; pots, sealed deck | monster CINDERLING | new (its painted card is in the repo) | U |
| THE CENSOR (`censor`, index 24) | HAT socket; -10% cooldown; lore "WHAT IT CANNOT READ, IT BURNS." | THE CENSOR in a card run; pots, sealed deck | monster THE CENSOR | new | U |
| THE PACK (`hound`, index 25) | STAFF socket; +12% damage; lore "ONE HOWLS. THE REST ARE ALREADY BEHIND YOU." | ASH HOUND in a card run; pots, sealed deck | monster ASH HOUND | new | U |
| THE FALLEN STAR (`shard`, index 26) | STAFF socket; +1 chest luck; lore "IT REMEMBERS THE SKY AND HOLDS A GRUDGE." | COMET SHARD in a card run; pots, sealed deck | monster COMET SHARD | new | U |
| THE TENTH BLADE (`ten_of_swords`, index 27) | STAFF socket; +15% damage; lore "NINE WERE ENOUGH. IT CAME ANYWAY." | TEN OF SWORDS in a card run; pots, sealed deck | monster TEN OF SWORDS | new (its painted card is in the repo) | U |
| THE CHANDELIER (`chandelier`, index 28) | ROBE socket; +3 hearts; lore "A THOUSAND CANDLES, NONE OF THEM KIND." | THE BONE CHANDELIER in a card run; pots and sealed deck at half the odds, as THE LICH | boss THE BONE CHANDELIER | new | U |
| THE GHOST WRITER (`ghostwriter`, index 29) | HAT socket; +1 redraw each run; lore "EVERY WORD OF THIS WAS ITS IDEA." | THE GHOST WRITER in a card run; pots and sealed deck at half the odds, as THE LICH | boss THE GHOST WRITER | new | U |

## 49. Boss rewards, Overtime and the Daily Draw

Every boss phase hands the table something, so a long fight has steps and a party that is losing gets one more
chance.

| Moment | What the table gets | Change | Test |
|---|---|---|---|
| THE BONE CHANDELIER turns to THE WHEEL (half health) | A potion for each wizard (none while THE HIEROPHANT holds) | new | U B |
| THE BONE CHANDELIER falls | As built: gems and coins, a potion, a PARTY TOME, a chest for each wizard, the fallen rise, a lull of 20 s. The fourth spell slot and arcana slot open, and the screen says so | as built; the words are new | U B |
| THE GHOST WRITER turns its page (half health) | A nova charge for each wizard | new | U B |
| THE GHOST WRITER falls | As built, the same as the first boss | as built | U B |
| THE ARCHLICH ascends (75% health) | As built: the field clears and every wizard heals 2 hearts | as built | U B |
| THE ARCHLICH turns THE NINTH PAGE (35% health) | A nova charge for each wizard, and the fallen rise | new | U B |
| THE ARCHLICH falls | The run is won and booked. Then Overtime is offered, once it is open | changed: Overtime | U B |

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| Overtime (`overtime`) | Offered on the victory banner; seat 1 decides. The win is booked before it starts, so a fall in Overtime loses nothing. The horde returns at the mix of act III with an elite every 20 s and no boss. Each minute plays one ladder step harder (+0.08 enemy health, +0.05 horde). It ends at +10:00 with THE TOWER HOLDS. Time and kills go on paying crystals. The best time at each step is kept on the profile and shown on that step's card | Deed THE LAST LICH (the first win) | Deed AFTER HOURS; a finished build with nothing left to fight | new | U S B C |
| The Daily Draw (`daily`) | One run a day that is the same for everyone: the date (UTC) gives the seed, the step is WIZARD, and the day's Reading is dealt, not chosen. A hero plays it as she is. The profile keeps the day's best score and its best ever. The first Daily Draw finished each day pays crystals x1.5. No leaderboard before stage 6. The date is read by the menu and handed in as the seed: the logic stays pure | Deed THE LAST LICH (the first win) | Deed CARD OF THE DAY | new | U B |

## 50. Deeds

The 54 deeds of § 27 stay as built; twenty-three of them now open something (§ 44). Eleven are new, 65 in all. Each
evolution has its deed. The new ones live in the Book of Deeds; which deeds go to Steam is stage 7's list.

| Name (code key) | What it does | Obtained / unlocked | Pairs with | Change | Test |
|---|---|---|---|---|---|
| THE FIRST PAGE (`LEVEL_5`) | "Reach party level 5 in a run." Pays 5 crystals | End of a run | Opens THE STAR | new | U |
| THE TOWER REMEMBERS (`FALLS_5`) | "Fall in five runs." Rule: 5 runs lost over all runs. Pays 10 | End of a run | Opens JUDGEMENT | new | U |
| TRUE NORTH (`EVO_LODESTAR`) | "Evolve Arcane Bolt into Lodestar." Pays 15 | End of a run | LODESTAR | new | U |
| IT BURNS ON WATER (`EVO_GREEK`) | "Evolve Fireball into Greek Fire." Pays 15 | End of a run | GREEK FIRE | new | U |
| COLD COMFORT (`EVO_VEIL`) | "Evolve Frost Fan into Winter Veil." Pays 15 | End of a run | WINTER VEIL | new | U |
| DAY OF WRATH (`EVO_DIES`) | "Evolve Chain Lightning into Dies Irae." Pays 15 | End of a run | DIES IRAE | new | U |
| THE LONG STARE (`EVO_HEX`) | "Evolve Hex into Evil Eye." Pays 15 | End of a run | EVIL EYE | new | U |
| SHALL WE DANCE (`EVO_BLADES`) | "Evolve Spirit Blades into Danse Macabre." Pays 15 | End of a run | DANSE MACABRE | new | U |
| TWO ROADS (`TWO_ROADS`) | "Evolve one spell both ways." Rule: both evolutions of one school spell taken, over all runs. Pays 25 | End of a run | The four school spells | new | U |
| AFTER HOURS (`OVERTIME`) | "Last the whole of Overtime." Rule: reached +10:00. Pays 30 | End of a run | Overtime | new | U |
| CARD OF THE DAY (`DAILY`) | "Win a Daily Draw." Pays 20 | End of a run | The Daily Draw | new | U |

## 51. Rows that go, rows that change, and part 1's open notes

- `Bosses.VISITS` goes (§ 35: two rows no code reads). Morvane's visits at 7:00 and 12:00 are not built in the first
  five stages; the idea is kept for stage 6. The moment `M_LICH` keeps its index, and the deed LICH BANE stays earned
  by the Archlich.
- The kind INSTANT keeps its number in the code and has no rows (§ 39).
- The ORBIT pickup lends SPIRIT BLADES (§ 38); its own damage source goes.
- The five floor spell tomes stay as built: off (`floor_tomes` 0).
- ARCHMAGE is locked on a new profile (§ 43). Six evolutions change partner (§ 40). Of today's rows, four classes,
  two races, three spells (BONE SPEAR, VIGIL CANDLE and the knight's CLEAVE) and four arcana (THE LOVERS, JUSTICE,
  THE TOWER, JUDGEMENT) are locked on a new profile (§ 44).
- The two painted monster cards with no row get theirs: `cinderling` is THE FIRESTARTER, `ten_of_swords` is THE
  TENTH BLADE (§ 48). The two painted Major Arcana with no row get theirs: `the_star`, `the_high_priestess` (§ 39).
- The card reader's talk lines that name pairs (§ 32) are rewritten to the chart of § 37 when the pairs are built.

## 52. What stage 3 must build that is not a row

The rows above need these mechanisms. Each is built once, with its own unit test, before the rows that use it.

| Mechanism | Rows that need it |
|---|---|
| An enemy status bit HEXED (the reserved `status` field), with who set it and how long it lasts | HEX, EVIL EYE; PROVOKE's second effect |
| The spell objects list (the reserved `"o"` of the snapshot): things that orbit an owner | SPIRIT BLADES, DANSE MACABRE, the ORBIT pickup |
| Two circle kinds beside rune and candle: FIRE (a patch that burns) and VEIL (a circle that follows its owner) | GREEK FIRE, WINTER VEIL |
| An evolution id for each spell (0 none, 1 first, 2 second) where a flag is today | The four school spells |
| An echo queue: a cast repeated after a delay at the same aim | THE HIGH PRIESTESS |
| A missile bonus and an area multiplier read by every cast | THE STAR, THE EMPRESS |
| Aim at the toughest foe in range; a damage multiplier against elites and bosses | LODESTAR, HEX |
| An execute rule: a plain foe under a share of its health dies | DIES IRAE |
| A locked-rows mask built from the profile at the start of a run and sent to every seat | § 41, 44 |
| A nova refill timer; a blast when a life is spent | THE TOWER, JUDGEMENT |
| A missing-hearts damage bonus, with its look | THE DEVIL |
| `Readings`: the sixteen rows, the deal, the vote, and the values merge after the Seal's | § 42 |
| Seal keys `omen` and `boss_fate`; Overtime's per-minute step | § 43, 49 |
| The satchel in the hero row, the keepsakes in the profile, the results screen's KEEP, provisions at run start | § 45, 46 |
| The start level: hands drawn before the first door opens | THE HEAD START |
| Card stats nova, XP, chest luck and redraw | § 48 |
| A use counter for every row in the run's record, shown on the results screen and read by the coverage robot | Every B in part 2 |
| The coverage robot: deals a named row by force, plays, and fails unless the row was credited | Stage 3's gate |
| The damage table measures a support spell beside ARCANE BOLT 3 and credits it the damage it added | HEX, VIGIL CANDLE in § 53 |
| THE SPREAD drawn from the catalog | § 41 |

## 53. The gates the rows are tested against

Stage 5 moves numbers until these hold. They are written now so that every row is built to be measured.

1. **Level 1.** A spell deals at least 3 a second to one target or 5 in a sparse crowd, so a first pick is felt.
2. **Level 5.** Each spell's dense-crowd number sits within 0.6 to 1.6 times the middle spell's (the release
   plan's stage 5 gate). A support spell is measured with the damage it adds.
3. **Evolutions.** An evolution deals at least 1.25 times its level 5 spell on the row that is the spell's job, is
   never weaker on the other row, and its dense number sits within 0.6 to 1.6 times the middle evolution's.
4. **Two roads.** Where a spell has two evolutions, robots that take each win at rates within 10 points of each other.
5. **Arcana.** In twin runs (the same seed with and without it) every arcana changes the result it is for: damage
   dealt, hearts kept, XP gained or the time to the first evolution. None decides a run alone: holding any one
   arcana moves the WIZARD win rate by no more than 15 points.
6. **Readings.** At WIZARD, the win rate with each Reading is within 15 points of the rate with none.
7. **Seals.** Each step's win rate sits between its neighbours', and a career that wins SEAL VIII has lost at every
   Seal at least once.
8. **The climb.** Half of solo robot careers reach the first win between 2 and 3 hours, and four players never in
   under 1.5 (the release plan). Something opens about every second run until that win.
9. **Speed.** Every S row holds the step budget, and the worst moment of a four-player run holds 60 frames a second
   on the Ryzen laptop.

Where the game stands against gates 1 to 3 today (measured 28 Nov 2026 at commit cae41a6a with `spell_dps --gate`;
damage a second; `one` is a single tough target):

| Spell | Level 1 one / sparse | Level 5 dense / one | Evolution | dense / one | Against the gates |
|---|---|---|---|---|---|
| ARCANE BOLT | 15.3 / 15.8 | 75.1 / 41.6 | ASTRAL LANCE | 234.1 / 43.4 | holds |
| FIREBALL | 3.0 / 5.9 | 149.7 / 9.7 | THUNDERFIRE | 220.5 / 15.1 | level 5 is over the band |
| FROST FAN | 5.0 / 6.6 | 31.9 / 15.5 | BLIZZARD | 85.6 / 15.3 | level 5 and BLIZZARD are under the band |
| CHAIN LIGHTNING | 3.7 / 8.9 | 38.5 / 8.1 | TEMPEST | 90.2 / 8.4 | TEMPEST is under the band |
| STARFALL | 6.1 / 6.6 | 25.2 / 23.1 | COMET RAIN | 154.0 / 22.9 | level 5 is under the band; COMET RAIN adds nothing on one target, its job |
| RUNE CIRCLE | 0.3 / 0.7 | 76.9 / 1.1 | SEAL OF SOLOMON | 200.7 / 2.5 | level 1 fails |
| BONE SPEAR | 3.4 / 4.5 | 46.0 / 7.7 | OSSUARY LANCE | 180.6 / 9.9 | holds |
| VIGIL CANDLE | 1.0 / 4.2 | 57.0 / 1.3 | CONSECRATION | 203.2 / 2.9 | a support: to be measured with what it adds |
| CLEAVE | 4.5 / 13.5 | 197.2 / 11.6 | WHIRLWIND | 168.5 / 25.1 | level 5 is over the band; WHIRLWIND is weaker than CLEAVE in a crowd |

The middle spell at level 5 is 57.0 in a dense crowd (band 34.2 to 91.2); the middle evolution is 180.6 (band 108
to 289).

## 54. Art and words the list asks of stages 3 and 4

Added to stage 4's list of pictures (`docs/asset_sources.md` gets a row for each when it is made):
- Major Arcana cards. Of the fourteen held arcana five are painted (THE MAGICIAN, THE HIGH PRIESTESS, THE TOWER, THE
  STAR, THE MOON) and nine are to paint; two of the nine are new to the list (THE EMPRESS, THE DEVIL). Of the eight
  fates DEATH and THE FOOL are painted.
- The sixteen Reading cards. Until they are painted a Reading is drawn from its suit's painted card (in the repo)
  with its number.
- The eight Seal cards as their arcana reversed under a red seal.
- Eight monster cards (bloat, coffin, guard, censor, hound, shard, chandelier, ghostwriter) beside THE DROPLET.
- Spell emblems for HEX, SPIRIT BLADES and the six new evolutions; the hex mark, the blades, the burning patch, the
  veil, the pale echo, the red staff of THE DEVIL.
- THE SPREAD, the satchel screen, the Reading table in the lobby, the results screen's KEEP row.

Words: the three or four words on each new card (in the tables above), sixteen Reading texts, eleven deeds, ten
card lores, the card reader's lines on pairs. All of it in the pixel font's letters (`PixelFont.GLYPHS`).

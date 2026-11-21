# Classes, races, the character sheet and the builder

Curtis, 20 Nov: "knights, archers, paladins, priests, we could have every class and race", "think secret of mana or ragnarok online mechanics", "healer class, races", "full character sheets and character builder screen", and on scope: "survival with mmo elements, not a full rpg". So: the run stays a horde-survival run; the party in it is an MMO party of saved heroes with roles.

## 1. Rules that keep it small

- A hero is saved data: name, race, class, school, look, class level, stat points, three card sockets. The run reads it once, in `World.apply_hero`, after `apply_meta`.
- Everything a hero adds lands in systems that exist: the six stats are `Loot.ST_*` (MIGHT, FOCUS, SWIFT, VIGOR, WARD, GREED, shown as FORTUNE); the class weapon is a `Spells.STATS` row with a class skin; the class skill fires on the nova button and spends nova charges.
- Every class wins alone. Roles make a party better, never required.
- Code names stay (`Wizards`, `wizard`); on-screen text says HERO. Two seats may pick the same class: the seat colour dyes the cloak, tabard or trim, so the "no two the same" rule goes.
- Remote Play is one machine: all seats pick from the host's roster of heroes, and guests' heroes level in the host's save.

## 2. Stats

One point is: MIGHT +2% damage, FOCUS +1% cast speed, SWIFT +1% move speed, VIGOR +1 heart per 4 points, WARD +1% chance to shrug a hit, FORTUNE +3% gold and +0.2 luck. A sheet value is race + class + points + cards, capped by `Loot.STAT_CAPS`; armour found in a run adds on top as today. At most 10 points in one stat.

## 3. Races (launch: four; UNDEAD and others later)

| Race | Stats | Trait | Build |
|---|---|---|---|
| HUMAN | +1 to all six | +5% class XP | medium |
| ELF | SWIFT +4, FOCUS +3 | XP flies in from 25% farther | medium, slim, long ears |
| DWARF | VIGOR +4, WARD +3 | pushed back half as far | short, wide, beard |
| ORC | MIGHT +5, VIGOR +2 | +10% damage at 2 hearts or fewer | tall, broad, tusks |

## 4. Classes (launch: five; NECROMANCER and WITCH follow with their spells)

Threat multiplies how near a hero looks to enemies when they choose a target (`WorldEnemies._nearest_player`: distance / threat). Skills spend a nova charge.

| Class | Role | Hearts | Weapon (auto) | Skill (nova button) | Threat | Passive |
|---|---|---|---|---|---|---|
| MAGE | damage | 5 | school: ARCANE BOLT, FIREBALL, FROST FAN or CHAIN LIGHTNING | NOVA, as today | 1.0 | +2 redraws |
| KNIGHT | tank | 9 | CLEAVE: new cast kind `sweep`, a 100 degree arc 34 px toward the nearest enemy, 9 to 20 damage every 0.9 to 0.7 s (levels 1 to 5), knock-back; his skin: damage x0.7, cooldown x0.85, knock-back x2.5 | PROVOKE: enemies within 100 px want him for 5 s and he takes no damage for 2 s | 2.5 | walks 6% slower; a hit leaves him unhurt 2 s (others 1.1 s, archer 1.6 s); MIGHT +30, FOCUS +10 points |
| ARCHER | ranged | 5 | LONGBOW: the BONE SPEAR row drawn as arrows, 260 px, damage x1.5, cooldown x0.5 | VOLLEY: rolls 50 px along her movement unhurt, then 12 arrows fan behind her | 0.8 | walks 8% faster |
| PRIEST | healer | 6 | HOLY LIGHT: the VIGIL CANDLE row, damage x1.3; it burns enemies and heals the most hurt hero inside 1 heart every 6 s | SANCTUARY: every standing hero heals 2 hearts and the fallen within 80 px rise | 0.7 | rituals twice as fast; MIGHT +25 points |
| PALADIN | tank and support | 6 | SMITE: the STARFALL row drawn as hammers of light, damage x1.6, cooldown x0.55 | AEGIS: heroes within 60 px take no damage for 3 s | 1.6 | heroes within 50 px get WARD +8 |

Every hero still draws any power from the level-up cards. Solo gates: each class within 10 points of the MAGE's win rate at WIZARD difficulty for casual and veteran bots; a party of knight, priest, archer, mage wins 5 to 15 points more often than four mages, not more. A priest heals herself. `sim_horde` gets a row for `sweep`.

Class level (saved, per hero): class XP at the end of a run = minutes survived x 10 + 50 per boss + 150 for a win, times the ladder's crystal multiplier. Level 1 to 20, 100 x level XP each. Each level pays 1 stat point; level 5 the skill gains a second effect, level 10 JOB CHANGE (one of two advanced jobs: a new title, a stronger skill, one passive), level 15 a second passive. Balance targets are measured at class level 1; the Seals assume levelled heroes. Job change tables are the first cut (post-launch), then level 15 passives.

## 5. Screens

**Builder** (the mirror in the Sanctum hub, and NEW HERO on a lobby seat): RACE, CLASS, SCHOOL (mage only), LOOK (4 skins, 6 hair colours, 3 hair or helm styles), NAME on the Ouija board. Left: the hero at 6x on a plinth, turning. Right: the choice list with the stat changes and one line on how it plays. Up to 8 saved heroes; hold to delete, with a confirm.

**Sheet** (hub, lobby seat, and a page of the pause GRIMOIRE): the hero at 6x, name, race, class, class level with its XP bar; the six stats with where each comes from (race, class, points, cards) and points to spend; weapon and skill with their numbers; three sockets (HEAD, BODY, WEAPON) with their cards; best ladder step, runs, wins, kills. Points are refunded for crystals at the shopkeeper.

**Lobby seat:** cycle saved heroes; the seat card shows the hero, name, class level and role icon. An apprentice seat takes a class that fills a missing role.

## 6. Contract

- `game/logic/classes.gd` (`Classes`): `ROWS` [key, name, role, hearts, weapon spell id, weapon skin, skill id, threat, stats[6]], `SKILLS`, accessors. `game/logic/races.gd` (`Races`): [key, name, stats[6], trait id, build]. Append-only; saves store keys.
- `game/logic/hero.gd` (`Hero`): name, race, cls, school, look (packed int), level, xp, points[6], sockets[3]; `stats() -> Array`, `to_dict`, `from_dict`, `add_xp`. `Profile.heroes: Array` (8 at most), VERSION 2; an old profile becomes one HUMAN MAGE of the last school played, holding the old sockets.
- Player row (reserved by the core commit): `P_RACE`, `P_CLASS`, `P_LOOK`, `P_CLASS_LEVEL`; `Player.threat`. Roster rows carry race, cls, look, cls_level.
- World: `apply_hero(p, hero: Dictionary)`; skills dispatched in `world/players.gd` where `_nova` is; cast kind `sweep` in `world/casting.gd` (after job E1's dispatch); threat in `_nearest_player`; events EV_SKILL (slot, skill id) and EV_HEAL (slot, hearts).
- Bots: `--party=knight,priest,archer,mage`; a tank bot walks to the thickest group near an ally, a healer bot keeps the most hurt ally inside the light.
- Art: a hero sprite is layers (build by race, outfit by class, weapon, dye by seat, skin and hair by look), painted per build: medium, short, tall. Plain flat-colour layers first, finished art second, judged at the store-page bar. Outlines must differ by class before any colour.

## 7. Jobs and order

| Job | What | Model | After |
|---|---|---|---|
| C1 | classes.gd, races.gd, hero.gd, Profile v2, apply_hero, threat, skills, class XP, bots, tests | Opus, 1 reviewer | core commit, E1 |
| C2 | `sweep` and the skinned weapons, HOLY LIGHT's healing | Opus (with E) | E1, VIGIL CANDLE and BONE SPEAR rows |
| C3 | builder and sheet screens, lobby seat cards, with plain layers | Sonnet | C1 |
| C4 | hero art: 3 builds x 5 classes, looks, 6x previews | Sonnet, lead judges | C3 |
| P | class and party gates of part 4 | Opus | C1, C2 |

Paid for by moving to after launch: endless mode, HEX and SPIRIT BLADES with their passives (THE DEVIL, THE EMPRESS), the WITCH, the trait table of the old wave 3 plan.

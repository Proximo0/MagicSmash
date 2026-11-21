# Wave 3 plan (v2): 5 to 15 Dec

Wave 3 fills wave 2's systems with content and changes no snapshot row (the core reserved `trait_a`, `trait_b`, enemy `status`, rune `kind`, the `"o"` list). Release candidate 15 Dec; 16 and 17 Dec are for the build and the store page only.

## What waits, and why, in order

| # | Work | Why it waits for wave 3 |
|---|---|---|
| 1 | Four new spells, 10 in all | They need E's spell core, slots and partner rules |
| 2 | Four partner passives | Each is half of a pair with a new spell |
| 3 | Ten heroes with traits: wizards, knight, archer, priest, paladin and more | Traits and skins use the new spells |
| 4 | Endless mode | It extends L's Archlich ending at P's difficulty |
| 5 | About 40 achievements | They count wizards, evolutions, Seals, fates |
| 6 | Balance pass 2 | Needs every spell, wizard and Seal in |
| 7 | Release candidate | Last |

**1. Spells.** Every spell kills alone: level 1 deals 3 a second to one target or 5 in a sparse crowd, and its `Spells.STATS` row is full before work starts. Level 5: 35 to 60 dense or 20 to 40 on one target, never both (`spell_dps.gd` prints all three). Gate before merge: a four-wizard capture at 12:00, all holding it, every wizard found within a second at 2x.

| Spell | Kind | Level 1 to 5 | Evolution |
|---|---|---|---|
| BONE SPEAR | bolt, unlimited pierce | cooldown 1.5 to 1.0 s, damage 3 to 5, a 220 px line | OSSUARY LANCE: splinters fly sideways from each hit |
| HEX | bolt with a mark | every 1.6 to 1.0 s at the toughest enemy within 160 px: 2.5 to 4.5 damage, +25 to +45% damage taken for 4 s; on death the curse jumps 70 px, 2 to 6 times | EVIL EYE: a hexed enemy explodes when it dies |
| SPIRIT BLADES | orbit (`"o"` list) | 2 to 4 blades always out at 30 px, 1.2 to 2.2 a touch, each enemy at most every 0.5 s, knock-back; the orbit pickup becomes +2 blades for 10 s | DANSE MACABRE: a second ring at 52 px |
| VIGIL CANDLE | zone (rune `kind`) | 48 px light on the densest cluster within 60 px, burns 0.8 to 1.6 per 0.5 s; wizards in it, the caster too, cast 20% faster for 2 s after leaving | CONSECRATION: the light heals a heart every 10 s |

Area spells hit on a timer, not a per-enemy cooldown; each kind adds a four-wizard `sim_horde` row.

**2. Passives.** All cast-rate bonuses add up as cast speed, and the cooldown multiplier never goes below `cast_floor` (0.35).

| Passive | Per level | Evolves |
|---|---|---|
| THE EMPRESS | area +10 / 20 / 30% | SPIRIT BLADES |
| JUSTICE | a slain enemy bursts 6 / 12 / 18% of the time for 60% of its max health within 30 px; burst kills never burst; bursts are queued | BONE SPEAR |
| THE DEVIL | +12 / 18 / 24% damage for each heart she is missing; no heart cost | HEX |
| THE LOVERS | within 60 px of an ally (an apprentice counts) cast 8 / 16 / 24% faster, alone half | VIGIL CANDLE |

**3. Heroes.** Replaced on 20 Nov by `docs/classes_design.md` (saved heroes with a race, a class, a sheet and a builder; five classes and four races at launch). Wave 3 keeps BONE SPEAR (the ARCHER's LONGBOW and the NECROMANCER) and VIGIL CANDLE (the PRIEST's HOLY LIGHT) with THE JUSTICE and THE LOVERS; HEX, SPIRIT BLADES, THE DEVIL, THE EMPRESS, the WITCH and endless mode move to after launch.

**4. Endless.** After VICTORY the party may choose KEEP FIGHTING: the horde goes on at the boss rate, the Seal values rise one step each minute, and `Profile` keeps the best time per wizard.

**5. Achievements.** One per wizard's win, evolution, Seal won and fate drawn.

**6. Balance pass 2.** Wave 2's targets hold with all content; every Seal's win rate sits between its neighbours' at 1 and 4 wizards, or it is cut.

**7. Release candidate.** Windows export with Steam on; the page shows what is built.

## Parallelism

Three workers: BONE SPEAR and HEX; SPIRIT BLADES and VIGIL CANDLE; passives and traits. Then hero art (six new looks, one worker each for martial and holy, one for the rest), endless with achievements, balance pass 2 last.

## Cut list

| Cut | Reason |
|---|---|
| FAMILIAR | A fifth of ARCANE BOLT's damage, and its own targeting |
| MOONBEAM | Readability risk; back only if the four spells pass their gates by 10 Dec |
| THE STAR, THE HIGH PRIESTESS | Luck and duration are not seen |
| The WIZARD's four-card draw | One card a run for a fourth row everywhere |
| The NECROMANCER's raised skeletons | A minion system for one trait; they read as enemies |
| Seals HASTE, FRAILTY, WRATH | A percentage nobody feels |
| Online lobbies, second stage, rebinding, daily seed, demo | Outside launch scope |

# Rules built (job R1): what `realm/core` does with rules.md sections 1 to 7 and 12

The core now runs the whole game's rules for one field: six fields, classes to level 60, ten jobs, 42 kinds, the
deck, the haul, potions and events. All the numbers are whole numbers, and every one of them is a table row or a
named constant in `realm/core/src/tables/`. The result is the same on 1 to 4 threads and through save and load, on
all six fields (`tests/core.rs`). The tests live in `realm/core/tests/`: 9 core, 14 behaviours, 35 skills and shapes,
35 cards and deck, 20 haul, potions, XP and events, 10 fields and terrain, and 7 table tests that read this
contract's own tables. That makes 130 core tests plus 3 server tests. `realm/check.sh` passes in about 36 s.

Measurement tool: `cargo run --release -p realm-core --example measure -- phases F T | killtime | kite L SEEDS MIN`.

## Tick cost: 1,000 heroes, 20,000 monsters, 30% rallied at the heart, mixed classes and jobs

Setup:
- Heroes are at the field's top level, with bench sheets and a kiting/wandering bot like the server's.
- Times are for the core only, in ms, as mean/p99, over 600 ticks after 200 ticks of warm-up.
- The machine has 4 cores. Its load average was 0.9 to 1.6 during the run, because other workers were building.

| Field | input | flow | grid | move | fight | spawn | **tick mean/p99** | max |
|---|---|---|---|---|---|---|---|---|
| 0 Fool's Road | 0.65/0.88 | 0.83/1.51 | 0.86/1.24 | 1.47/2.04 | 0.46/1.32 | 0.07/0.37 | **4.34/5.96** | 8.4 |
| 1 Hanged Wood | 0.73/1.21 | 0.92/1.60 | 0.79/1.26 | 1.43/2.72 | 0.46/0.97 | 0.10/0.27 | **4.43/6.95** | 15.7 |
| 2 Moon Marsh | 0.76/1.28 | 0.90/1.57 | 1.22/2.29 | 1.67/3.37 | 0.42/1.19 | 0.08/0.29 | **5.05/9.39** | 56.6 |
| 3 Hermit's Peaks | 0.75/1.52 | 1.05/1.85 | 2.29/3.41 | 1.75/3.96 | 0.54/1.55 | 0.09/0.33 | **6.47/10.41** | 11.5 |
| 4 The Tower | 0.74/1.24 | 0.87/1.57 | 0.91/1.28 | 1.63/3.02 | 0.48/1.32 | 0.09/0.33 | **4.71/7.53** | 8.9 |
| 5 World's Edge | 0.78/1.09 | 0.72/1.46 | 1.97/2.73 | 1.42/1.99 | 0.59/1.34 | 0.24/0.67 | **5.71/7.70** | 8.1 |
| 0, 1 thread | 0.82/1.06 | 0.78/1.22 | 0.79/1.05 | 2.86/3.35 | 0.24/1.61 | 0.06/0.37 | **5.55/7.29** | 7.5 |
| 4, 1 thread | 0.88/0.99 | 0.77/1.12 | 0.81/0.88 | 2.94/3.44 | 0.27/1.64 | 0.07/0.33 | **5.74/7.54** | 7.8 |

- Every field is within the budget of mean 12 ms and p99 25 ms. The worst is THE HERMIT'S PEAKS at 6.5/10.4.
- The grid phase is heavier on the PEAKS and the EDGE because of the aura map of howlers and wailers.
- The single 56 ms tick on the MARSH was one tick out of 600, most likely the busy machine. It is not repeatable at 1 thread.
- The server's `--bench` for the same runs, which includes bots and every protocol encode, gave a tick of 6.0 to 8.4 ms
  mean and 10.8 to 19.9 ms p99 across the six fields (taken before the last tuning, with the same cost shape).

## The walker gate: seconds for a hero of a walker's level to kill it alone

How the gate was measured:
- Kill time = walker health / the hero's measured damage a second on it, over a 20 s window.
- The hero is alone, at field level 1, with no cards.
- Gear is assumed to be the bench sheet: six UNCOMMON items at her level (lines `1 + level / 4` points x 120%), with
  points spent half on MIGHT. The first job applies from level 40.
- The walker is the field's own walker kind at that level. THE WORLD'S EDGE has none, so it uses THE TOWER's swords.
- Below class level 10 every class is a NOVICE.

| Level | Walker (field) | Health | NOVICE | KNIGHT | MAGE | ARCHER | PRIEST | PALADIN | Mean of the 5 classes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | scarecrow (0) | 45 | 1.19 | (novice) | | | | | |
| 10 | hanged man (1) | 131 | 2.21 | 0.83 | 0.92 | 0.62 | 2.04 | 0.86 | 1.05 |
| 20 | drowned (2) | 243 | 2.37 | 0.89 | 1.02 | 0.67 | 2.21 | 0.93 | 1.14 |
| 30 | goat cultist (3) | 342 | 2.25 | 0.93 | 1.05 | 0.69 | 2.06 | 0.87 | 1.12 |
| 40 | swords (4) | 401 | 1.89 | 0.70 | 0.56 | 0.52 | 1.76 | 0.75 | 0.86 |
| 50 | swords (5) | 491 | 1.68 | 0.69 | 0.52 | 0.52 | 1.58 | 0.65 | 0.79 |
| 60 | swords (5) | 581 | 1.54 | 0.55 | 0.43 | 0.41 | 1.43 | 0.59 | 0.68 |

**Level scaling change.** The contract gives no rule for how weapon damage grows with item level. The scaling used
is weapon damage x `(155 + 4 x (item level - 1))%` (`WEAPON_BASE_PCT`, `WEAPON_PCT_PER_LEVEL`).
- The first try was 100 + 15 per level. That made the mean fall from 0.85 s to 0.27 s, because MIGHT from points
  and gear also grows linearly, so damage grew quadratically while health grew linearly.
- With the chosen scaling the mean of the five classes stays between 0.68 and 1.14 s at every level, and the
  level-1 NOVICE takes 1.19 s.

**Outside the gate, because of the contract's weapon table rather than the scaling:**
- The PRIEST takes 1.4 to 2.2 s. HOLY LIGHT does 15 damage every 12 ticks, a third of the LONGBOW's damage a second.
- ARCHER and MAGE take 0.41 to 0.56 s from level 40. The jobs (ARCHMAGE second burst) and FOCUS attack speed push them there.
- A band of 0.6 to 1.2 s is a factor of 2, but the weapon table spreads damage a second over a factor of 3.2.
  Level scaling alone cannot fit every class into it. See the open questions.

## A kiting bot alone at the edge of THE FOOL'S ROAD, class level 1, 10 minutes, 10 seeds

At class level 1 all six classes are the NOVICE, so one run stands for all of them.

The bot:
- moves away from every monster within 200 px, weighted by 1/d²;
- circles the heart clockwise at 7,000 px and steps around walls;
- picks the first card offered, drinks HEALING DRAUGHT under 45%, and uses skills when more than 6 monsters are near.

| Density base | Never downed | Never fallen (PHOENIX ASH counts) | Kills a run |
|---|---|---|---|
| contract: 400 for the field | 0/10 (first down at 9 to 16 s) | 0/10 | 172 |
| 60 a hero, at most 400 (**chosen**) | 6/10 | 7/10 | 124 |
| 50 a hero | 6/10 | 7/10 | 105 |

Earlier probes with a total of 70 survived 5/5 over 5 minutes. With a weaker bot (flee from the nearest monster),
even a total of 52 downed the hero within 25 s, so the bot's skill matters as much as the density. The contract's
8 of 10 is **not yet met** and is handed to R2.

## Numbers changed from the contract, and why

- **Density base** is now `min(400, 60 x heroes) + ring weights` (`DENSITY_BASE_PER_HERO = 60`). With the
  contract's 400, a lone hero has every monster born 400 to 700 px from her and is downed in about 10 s. From 7
  heroes up, the rule is the contract's.
- **Weapon level scaling** is `155 + 4 x (level - 1)` percent. This is a new number, since the contract had none; see above.
- **Recycling** ("no hero within 64 cells") is read as both of these: more than 64 cells of walk beyond its hero's
  head start on the flow, and no hero within about 64 cells in a straight line (blocks of 8 cells). The flow
  alone recycled monsters just behind a wall.
- **DEADEYE**'s "double" is +100% in the effects group.
- **CRUSADE** makes SMITE strike 3 targets.
- **SHIELD**: the ORACLE's shield lasts 2 s.
- **DASH** gives 6 ticks unhurt.
- **RAMPART**'s effect is renewed every 11 ticks while she stands in the zone.
- **THE LOVERS** carries hundredths of a point from tick to tick. Without that, 1% of a small hit always rounded to 0.

## Not affordable or not built as written, and what was done instead

- **Hero bolts and dashes are instant.** Arrows, fireballs and dashes resolve in the tick they are fired, along a
  line that stops at walls; CHARGE and TUMBLE teleport along her last direction. Monster bolts and lobs are real
  projectiles in a pool of 4,096.
- **Auras are per cell.** Howl, wail and mend use a map of 32 px cells. Mend pulses for the whole field every
  40 ticks.
- **PROVOKE** seeds the knight's cell at 0 on the flow. That pulls the horde within about 7 cells further than
  anyone else, rather than "monsters within 200 px".
- **Flow ties** are broken toward the hero the cell leads to. Every step costs the same, so ties are common;
  without this the horde drifted north-west.
- **"Dark: sight closer"** is the client's job. The core only moves births to 250 to 450 px.
- Not built here, by the brief: tide, bosses, vaults, PvP (section 14 state is reserved: `marked`,
  `last_struck`), and loot rolls beyond coin.

## Open balance questions for R2

1. The lone kiting bot gets 7/10, not 8/10. Choose between a better bot, a lower base, or slower runners and
   rats near the gate. Hero speed is 60 px/s, rats 55, crows 70.
2. The PRIEST's weapon is about 2x outside the walker gate. One option is HOLY LIGHT at 28 damage; another is a
   per-role band in the gate.
3. ARCHER and MAGE drop below 0.6 s from level 40, through the jobs and FOCUS.
4. `CLASS_XP` (59 rows) is a placeholder curve and has not been tuned against bots.
5. The bench gear assumption (all UNCOMMON at the hero's level) should be confirmed against the loot rates of section 9.

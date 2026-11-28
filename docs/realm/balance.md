# Balance (job B1)

Bots that live careers from class level 1 to 60, and the numbers tuned by them: the class XP curve (rules 2), the
party and jobs gates (rules 13) and the coin sinks (economy). Everything here is reproduced by `realm-loadtest
balance ...` (`realm/loadtest/src/balance.rs`, `career.rs`); the short gates are `realm/loadtest/tests/balance.rs`;
the full careers are the station word `balance`.

## How a career is played

`career.rs`. A cohort is `PER` careers of each of the ten jobs (five classes, first or second job), each a
NOVICE at class level 1 with 10 coin. A round is one outing of every career followed by a visit to town; outings
of a round run in field copies on threads and are applied in career order, so a cohort is a pure function of its
seed (tested: same seed, same careers, on 2 threads).

In the field a hero is a core class bot (`realm_core::bots`): she flees what is close, kites, patrols her ring,
uses skills, ultimate and potions, picks cards, raises allies, banks at a waystone when her haul is worth
`BANK_KILLS` = 150 kills of her level, is downed and sometimes falls. Loot is rolled per credited kill with
`realm_loot::roll`. In town she books her coin, wears what is better (a weapon level is worth `WEAPON_LEVEL_WORTH`
= 6 line points), sells COMMON and UNCOMMON to the merchant and salvages RARE and better, buys a piece on the
market when hers is `MARKET_LAG` = 6 levels behind (best of `MARKET_CHOICE` = 4 listings at `MARKET_PRICE_PCT`
= 100% of `item_value`, the tax booked as a sink), sockets runes, refills her belt (`BELT_PLAN` HEALING, WHETSTONE,
PHOENIX from `PHOENIX_FROM` = 10), pays the repair and the fare, and takes every worn piece to +`SMITH_SAFE` = 5
and the weapon to +`SMITH_WEAPON_MAX` = 7 while the bank holds `SMITH_RICH_MUL` = 4 times the step.

Choices people make:
- Stats by class in twelfths of the points (`STAT_PLAN`): NOVICE 6/2/2/2/0/0, KNIGHT and PALADIN 5/1/0/4/2/0, MAGE
  6/3/1/2/0/0, ARCHER 6/3/2/1/0/0, PRIEST 4/2/0/4/2/0 (MIGHT/FOCUS/SWIFT/VIGOR/WARD/FORTUNE).
- Where: the field and ring whose monsters are her level less `RING_LEVEL_BELOW` = 1, clamped to
  `RING_MIN_PX`..`RING_MAX_PX` = 2,000..7,200 px; and of the last `STAY_LEVELS` = 5 levels the one whose place
  pays the most an hour (`best_rate`): a hero of 20 stays in THE HANGED WOOD's rim (141k an hour at 19) rather
  than THE MOON MARSH's edge (70k at 20), a hero of 40 stays in the PEAKS until the TOWER pays more.
- Alone or in a party: every career partying in `PARTY_PCT` = 50% of her outings (a seeded coin a round), parties
  of 4, 3, 6 or 8 by career index (`PARTY_SIZES`). Up to `SOLO_PER_FIELD` = 5 solo heroes share a copy (spread
  `GROUP_SPREAD_PX` = 1,500 px apart, so each meets the density R1 tuned for one).
- Time: below class level 10 every tick is played (outings of `MINUTES`); from `FAST_FROM` = 10 an outing is
  credited `FAST` times as long (XP, coin, loot rolls, potions and wear x k), so 80 hours fit in about half an hour.

## The curve (rules 2)

Method: `balance probe 3 8` measures class XP an hour for each class alone and in a party of five at the bottom,
middle and top level of every field (8 minutes, 3 seeds, the clock just after a tide). The median of the five
classes alone and in a party, combined as a harmonic mean (half of the time in each), is `MEASURED_XP_HOUR`.
A career is slower than the probe where it falls and walks, faster where it parties in bigger groups, so each
field's rate is scaled by `CAREER_PCT` = 81, 52, 180, 92, 115, 110 %, found in two steps of (the curve's hours
for the field's band) / (the median career's): run 1 (10 careers, the probe's table) had band hours 0.48, 5.42,
7.96, 17.5, 18.5, 26.9 against 0.42, 3.58, 7.68, 13.3, 22.4, 32.6 (giving 87, 66, 95, 77, 120, 121 %); run 2 (20
careers) had 0.45, 4.55, 4.04, 11.2, 23.4, 35.9. The fit predicted run 2's hours to 1 to 3% (0.44, 4.99, 20.6,
77.8 against 0.45, 5.0, 20.2, 79.5), so the model of a career by its band rates holds. `CLASS_XP` is `balance fit` of those rates: XP from L to L + 1 is the
rate at L (log-interpolated within a field, the best of the last five levels) times the hours the smooth curve
`target_hours` gives that level, to three figures. `target_hours` is a power of the level between the targets
(10: 25 min, 20: 4 h, 40: 25 h, 60: 80 h) and `EARLY_POWER` = 1.5 from level 1 to 10.

The steps follow the fields: a field that pays more an hour asks more a level (19 to 20 is 45,400 XP, 29 to 30
166,000, 30 to 31 322,000). The table the fit gives at the career rates: 0.41 h to 10, 4.00 h to 20, 25.0 h to 40,
80.0 h to 60 (tested within 3%). The table before B1 took 6.6 h to 10 and 9.9 h to 60.

### Careers (run 3 and 4, the tables as committed)

`realm-loadtest balance career 1 2 10 16 160`: 20 careers (2 of each of the ten jobs), 10-minute outings
credited 16 times from level 10, 4 threads, 31 minutes. Median credited hours to a class level:

| level | KNIGHT | MAGE | ARCHER | PRIEST | PALADIN | median | target |
|---|---|---|---|---|---|---|---|
| 10 | 0.34 | 0.41 | 0.30 | 0.43 | 0.38 | **0.38** | 0.42 |
| 20 | 2.60 | 4.21 | 5.84 | 3.10 | 3.69 | **3.69** | 4.00 |
| 30 | 12.90 | 19.27 | 18.76 | 11.61 | 12.84 | 12.90 | (11.7) |
| 40 | 29.48 | 33.62 | 33.30 | 23.02 | 21.42 | **29.48** | 25.00 |
| 50 | 47.47 | 60.83 | 64.39 | 38.83 | 36.93 | 47.47 | (47.4) |
| 60 | 70.64 | 101.98 | 106.82 | 63.53 | 67.31 | **70.64** | 80.00 |

Class XP an hour by band (percent off the band's median):

| band | KNIGHT | MAGE | ARCHER | PRIEST | PALADIN | median |
|---|---|---|---|---|---|---|
| 1-9 | 2,224 +0% | 2,234 +0% | 2,297 +3% | 1,661 -25% | 2,162 -2% | 2,224 |
| 10-19 | 174,726 +36% | 102,400 -20% | 100,031 -21% | 128,131 +0% | 135,973 +6% | 128,131 |
| 20-29 | 96,137 +0% | 82,291 -14% | 88,744 -7% | 143,241 +48% | 115,741 +20% | 96,137 |
| 30-39 | 383,710 +0% | 387,389 +0% | 311,769 -19% | 435,091 +12% | 575,814 +48% | 387,389 |
| 40-49 | 952,301 +40% | 464,734 -31% | 424,405 -37% | 788,266 +16% | 676,089 +0% | 676,089 |
| 50-59 | 1,784,337 +20% | 1,124,700 -23% | 940,904 -36% | 1,794,800 +21% | 1,479,357 +0% | 1,479,357 |

Per hour, by band: kills 1.5k, 25k, 13k, 25k, 16k, 41k; falls 6.1, 17.5, 2.0, 0.1, 0, 0.2; outings in a party
44 to 55%.

**Curve: within 8 to 10% at 10 and 20 (0.38 h, 3.7 h), 18% slow at 40 (29.5 h), 12% fast at 60 (70.6 h).** The
run-to-run spread of the median at 20 careers is about as large: run 2 with the previous table gave 0.45, 5.0,
20.2, 79.5 h where the fit predicted 0.44, 4.99, 20.6, 77.8. THE MOON MARSH step (`CAREER_PCT` 180%) overshot;
a third step, or a station run of more careers, would settle 40.
**Classes: moved, not closed (run 5, probe).** MAGE and ARCHER were slowest from 20 on. The probe (`balance probe 3 8`,
levels 10 to 60, each class's XP an hour against the median of the five, mean over levels) showed it alone, not in a
party: alone KNIGHT +24%, MAGE -15%, ARCHER -31%, PRIEST +25%, PALADIN +7%; in a party -7, +6, +17, -6, +7%. The
mechanism is the bot, not the numbers: a ranged hero looked for monsters within 200 px and fled them with weight 3
(melee: 110 to 160 px, weight 1), so alone she spent her time walking away from what she should shoot. Doubling
FIREBALL's damage moved nothing at level 40, so damage was not the lever. Now a ranged bot flees within 120 px with
weight 1 (`bots.rs`, `reach` and `flee_w` of `Role::Ranged`): alone MAGE -11%, ARCHER -15%; in a party 0 and +1%
(KNIGHT +14, PRIEST +30, PALADIN +12 alone). The probe is noisy (5 heroes, 3 seeds, and heroes of one run share a
field copy: changing one class's damage moved another's rate): the probe's slot also matters (the hero in slot 1
fell 64% at level 60 whichever class stood there), so read the means, not single levels. Left: MAGE alone at level
40 (-25 to -90% in every run, damage-insensitive, so the shots are lost, not weak: not traced) and at 30.
The careers (2 a job) need the station's run to confirm.
The jobs gate: a MAGE that stands and shoots made HEXER's own contribution 60% over ARCHMAGE's (gap 38%, bound 25; the
curse is not the cause: `CURSE_TAKEN_PCT` 100 left it unchanged), so ARCHMAGE's `second_burst_pct` went 50 to 100.

### Third step of `CAREER_PCT` (2026-11-24, from the station's cohort 1)

Station runs (20 careers): `h10=0.60 h20=4.4 h40=31.4 h60=80.7 worst_class=-30% sunk=79%` (msi/laptop, older tables) and
`h10=0.38 h20=3.7 h40=29.5 h60=70.6 worst_class=-37% sunk=91%` (run 3 above). Misses of the second: h40 +18% (target 25),
h60 -12% (target 80), worst class -37% (ARCHER 40-49 and 50-59, MAGE 20-29 and 50-59), sunk 91% (see the coin book).
Change: `CAREER_PCT` 81, 52, 180, 92, 115, 110 -> 89, 56, 150, 74, 143, 155 (each times curve band hours / run 3's band
hours, 0.38, 3.31, 9.21, 16.58, 17.99, 23.17 h), `CLASS_XP` refitted (`balance fit`): steps 30-39 about 20% lower,
40-59 about 20 to 40% higher. Class gaps were not touched: 2 careers a job cannot show which class lever works.
Local check (4 cores, `balance career 1 1 10 16 100`, 10 careers, so noisy): before `h10=0.36 h20=4.5 h40=37.6 h60=inf
worst_class=-52% sunk=97%`; after `h10=0.43 h20=5.8 h40=28.2 h60=inf worst_class=-59% sunk=95%`. h40 moved toward the
target; h60 is still beyond 100 h for the ARCHER (slowest class), so the class gap, not the median, now decides the
top. A station run of `PER` 10 is needed to confirm.

## The party gate (rules 13)

`realm-loadtest bots party 10 6000` (`realm_core::gates::party`: KNIGHT, PRIEST, ARCHER, MAGE at the field's
bottom level, bench gear, 100 ticks before a tide, 6,000 ticks, never fallen):

| field | R2 | B1 |
|---|---|---|
| THE FOOL'S ROAD | 2/10 | 5/10 |
| THE HANGED WOOD | 0/10 | 1/10 |
| THE MOON MARSH | 1/10 | 4/10 |
| THE HERMIT'S PEAKS | 10/10 | 10/10 |
| THE TOWER | 10/10 | 10/10 |
| THE WORLD'S EDGE | 10/10 | 10/10 |

**Not met on the first three fields** (8 of 10 is the gate). What moved it:
- The tide's doubling now grows with the heroes up (`tide_target_pct`): x1 up to `TIDE_FULL_FROM` = 4 heroes, x2
  from `TIDE_FULL_AT` = 40, linear between. **A rule change** (rules 5 say the tide doubles the target): R2 found
  the doubled horde on four heroes is what downs them, and a crowd still meets the double. THE FOOL'S ROAD went
  from 2 to 8/10 with it in the R2 bot.
- The bots step out of landing circles (`bots/nav.rs` `dodge`: radius + `DODGE_MARGIN` = 16 px, pushed with a
  goal's strength): the downs at THE MOON MARSH and THE HANGED WOOD came from lobbed shots, not from contact (a
  trace of the shots and monsters around each down). Bolts are not dodged (`DODGE_BOLT_PX` = 0):
  sidestepping them walked NOVICEs into the crowd.
- The patrol walks around walls (`Bot::waypoint`: a breadth-first search over 81 x 81 cells, the farthest cell of
  the way she sees straight, kept 20 ticks): careers stuck on THE TOWER's walls and THE HANGED WOOD's trees.

What still downs them in THE HANGED WOOD: at level 10 in bench gear the middle ring's lobbers and chargers come
every 10 to 60 s (first downs 11 to 69 s in 9 of 10 seeds), with or without a tide; a party of level 25 holds it.
Tried and rejected: a cap on births near a party, a density of 30 a hero, more VIGOR and WARD in the bench, a
start at the middle waystone, raising with up to 12 monsters near. Left: whether the gate's party should be the
field's bottom level against the middle ring (monsters of about 15 in the Wood), or the Wood's lobbers are too
strong for its level.

## The jobs gate (rules 13)

`realm-loadtest balance jobs 3 100 50 3000`: a crowd of 100 bot heroes at class level 50 at the heart of THE
WORLD'S EDGE through a tide, an even share of the ten jobs, 3 seeds. Two measures: **own**, each job's mean
contribution (R2's measure, `gates::job_crowd`), and **crowd**, the crowd's class XP per hero when every hero of
the class takes the one job or the other (`balance::crowd_value`, role-aware: a tank or healer is worth the kills
and falls she makes or saves for the rest).

| class | jobs | own R2 | own B1 | gap R2 | gap B1 | crowd B1 | crowd gap |
|---|---|---|---|---|---|---|---|
| KNIGHT | WARDEN / BERSERKER | 61k / 210k | 129k / 369k | 70% | 64% | 217k / 186k | 14% |
| MAGE | ARCHMAGE / HEXER | 3.73M / 3.68M | 3.68M / 3.76M | 1% | 2% | 206k / 220k | 6% |
| ARCHER | RANGER / SHARPSHOOTER | 4.99M / 1.90M | 5.38M / 1.92M | 62% | 64% | 130k / 261k | 50% |
| PRIEST | ORACLE / INQUISITOR | 0.31M / 1.18M | 0.32M / 1.34M | 73% | 75% | 208k / 214k | 2% |
| PALADIN | TEMPLAR / CRUSADER | 1.56M / 1.85M | 1.77M / 1.60M | 15% | 9% | 246k / 183k | 25% |

**Met for MAGE (both measures), PALADIN (own), KNIGHT and PRIEST (crowd); not for ARCHER on either.** Own
contribution in a crowd is bounded by how many monsters reach a hero, so zones and pierce decide shares and weapon
damage barely moves them (SHARPSHOOTER at 4 times weapon damage gained 8%); a holding job (WARDEN, ORACLE) scores
low by design. The crowd measure answers the gate's question better for tanks and healers, but it is noisy at 3
seeds (a class's value moves 10 to 20% between runs) and puts the ARCHER the other way round: the crowd does better
with SHARPSHOOTERs (reach) though RANGERs (pierce 8) score three times the contribution. RANGER pierce 3 brought
the own gap to 35% and left the crowd gap at 53%; kept at the contract's 8. The short test checks that both
measures run and each class's own gap stays within bounds a little wider than these (`JOB_GAP_REPORTED_PCT`). Left: which
measure the gate means, and the ARCHER pair.

Numbers changed for it: WARDEN 200% weapon damage (from 100), TEMPLAR 135%, BERSERKER +1% power per 3% health
missing (from 2%), and contribution counts half of the hit drawn rather than of the damage taken.

## Coin: what monsters mint and what sinks take

A kill pays its XP in coin, so a career mints about 145 million coin, nearly all of it from level 30 on. The
sinks (`realm/loot/src/sinks.rs`) are priced in hours of the income of the field an item's level belongs to
(`INCOME_PER_HOUR`), so they bite the same at every level:
- `INCOME_PER_HOUR` = 1,500, 90,000, 90,000, 1,400,000, 3,200,000, 4,600,000 coin: the price base. Run 2's
  median career minted 2.1k, 166k, 210k, 805k, 1.56M, 3.7M an hour by band. Fields 0 to 2 are held at about half
  of it, because careers fall there often (16 falls an hour in 10-19) and at the full income the repair alone took
  more than kills paid; there the sinks already took 107 to 117%. Fields 3 to 5 are 1.7, 2 and 1.25 times it:
  with the base at the income (run 2) the sinks took 76, 57 and 85% there and 78% of the career.
  Within a field the price grows like a kill's coin (`power_coin`) from the field's middle level.
- Repair: `REPAIR_BP_PER_HOUR` = 600 (6% of an hour's income per worn item per hour in the field), x
  `REPAIR_RARITY_PCT` 100/110/125/150/200 from COMMON to RELIC, +`REPAIR_PLUS_PCT` = 5% per smith step, a fall wears
  as much as `REPAIR_FALL_MINUTES` = 15 minutes, at least `REPAIR_MIN_PER_HOUR` = 10 coin. Six UNCOMMON pieces
  cost about 40% of the income an hour: the forced sink.
- Fares to a waystone: `TRAVEL_BP` = 1%, 2%, 3% of an hour's income for the edge, middle and heart ring, at least
  `TRAVEL_MIN` = 20; the gate at the south edge is free.
- Smith: a step to +s costs at least `SMITH_STEP_BP` = 1.5% of an hour's income x s^2 (`smith::upgrade_cost`, the
  old `4 x level x s^2` kept as a floor): +1 to +5 together is 0.8 hours of income. The voluntary sink that
  takes what the forced ones leave.

### The coin book (run 4)

Run 4 is run 3 replayed (same seed, same levels and hours) after one fix: a hero who cannot pay the whole repair
pays what she holds and the rest is not booked (run 3 booked it, and showed 104%). Coin per career, by band:

| band | kills | falls | potions | repair | fares | smith | sunk % |
|---|---|---|---|---|---|---|---|
| 1-9 | 1,018 | 345 | 504 | 35 | 67 | 13 | 84% |
| 10-19 | 732,962 | 155,826 | 5,979 | 133,629 | 450 | 251,875 | 74% |
| 20-29 | 1,692,466 | 57,954 | 12,970 | 555,042 | 7,830 | 921,604 | 89% |
| 30-39 | 12,003,997 | 14,309 | 19,797 | 4,917,930 | 87,500 | 6,001,990 | 91% |
| 40-49 | 32,634,854 | 0 | 27,988 | 18,203,524 | 465,600 | 9,084,900 | 85% |
| 50-59 | 113,601,462 | 178,014 | 74,183 | 72,170,491 | 1,009,700 | 32,215,038 | 92% |
| career | 160,666,761 | 406,449 | 141,425 | 95,980,655 | 1,571,147 | 48,475,422 | **91%** |

**Not quite met: the sinks remove 91% of what monsters mint over a career** (29% with the pre-B1 prices, 78%
with the base at the measured income). Repair is about two thirds and the smith a third of what is sunk. The
repair asked is more than heroes can pay at times (run 3's 104% was what was asked), so raising prices further
would not help; the last 9% is coin held between visits, behind the bot's smith reserve (`SMITH_RICH_MUL` = 4
steps in the bank) and its weapon cap (+7). A lower reserve or a higher cap would likely close it; not run. The
short test holds each band's forced sinks (falls, potions, repair, fares) to at least `FORCED_SINK_MIN_PCT` =
40% of an outing's mint. The market moved 18k coin between players.

### The trainer's job and the bank's tabs (job trial-sinks)

Two one-off coin sinks a player meets in town, numbers in `realm/loot/src/sinks.rs` (test
`the_job_and_the_bank_tabs_cost_what_balance_md_says`):
- **A job** costs `JOB_CHANGE_BP` = 5,000, half an hour of `income_per_hour` at her class level, on top of passing THE
  CLASS TRIAL: **1,447,133 coin at level 40**, 1.6 million at 45, 2.5 million at 60. Why half an hour: the job is the
  one great choice of a career and should be felt, but a career at 40-49 mints 32.6 million (the coin book above), so
  20 to 40 minutes of her own play pays it and nobody is held back from the jobs gate; priced by income, it bites the
  same whenever she takes it. Refused in words when she cannot pay ("the trainer asks ... and she carries ...").
- **Bank tabs** 2 to 8 cost `BANK_TAB_PRICE` = 3,000, 12,000, 50,000, 200,000, 800,000, 3,200,000, 12,000,000 coin
  (about four times the last each): the 2nd is two hours of THE FOOL'S ROAD (a first goal), the 8th about 2.5 hours of
  THE WORLD'S EDGE. All seven are 16.3 million, about a tenth of a career's mint, nearly all of it bought where coin
  piles up (economy.md, the glut). The account owns the tabs (not the hero), so the price follows the tab, not a level.
  The free first tab and the most (8) are the store's `FREE_BANK_TABS` and `BANK_TABS_MAX`.
Not yet in the careers' coin book (`realm-loadtest balance career`): a bot buys neither, so run 4's 91% is unchanged.

## Rule changes (numbers in `realm/core` beyond tables, each named)

1. **The tide's doubling scales with the heroes up** (`TIDE_FULL_FROM` 4, `TIDE_FULL_AT` 40, `tide.rs`).
2. **THE TOWER's kills pay 8 times the XP and coin** (`FIELD_XP_PCT`, `monster.rs`): its rooms let a hero kill a
   tenth of what the open fields give, and the curve fell eightfold at level 40.
3. **Contribution counts half of the hit drawn, before the hero's reductions** (`CONTRIB_DRAWN_PCT` 50,
   `combat.rs hurt_hero`; rules 8 say half of damage taken): a tank's mitigation no longer cuts her share.
4. **Job numbers:** WARDEN deals 200% weapon damage, TEMPLAR 135%; BERSERKER gains 1% power per 3% health missing
   (was 2%). The core test `job_passives` follows.
5. **`CLASS_XP`** refitted (above).
6. **A save keeps a hero's `hurt` flag** (`state.rs`, flags bit 3): a fix, not a balance number. The waystone
   hold reads the previous tick's `hurt`, so a copy loaded from bytes could diverge from the original by one tick
   (found by B1's save/load check after the TEMPLAR change).
7. Bots (`bots.rs`, `bots/nav.rs`): dodging landing circles and walking around walls (above).

## Open questions

1. The party gate in THE HANGED WOOD and THE MOON MARSH, and THE FOOL'S ROAD at 5/10 (above).
2. The jobs gate's measure (above).
3. Faucet scale: E1's prices (potions, the merchant, the market) are a few hundred coin while a career mints 145
   million; the sinks here are scaled to income, E1's are not. The potion price and the merchant's pay may want
   the same income scale.
4. (Settled 2026-11-22.) The gateway's `sheet_of` now sums gear with the loot crate's `gear_stats`, as careers do:
   the smith's plus, socketed cards and grade III runes at 7 count in the field.
5. Chest coin is minted both by the core (`Reward`) and by the loot roll; careers book both.
6. THE TOWER's rim (level 40) pays a tenth of its middle (probe: 58k against 456k an hour): parties there stall in
   corridors. Careers skip it (`best_rate`), but a player would not.
7. Class gaps within a band are noisy at 2 careers a job (above); a station run of `PER` 10 would settle them.

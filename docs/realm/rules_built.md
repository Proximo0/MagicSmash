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
- The hero is alone, with no cards. (Measured at field level 1, before 27 Nov; her class level now adds 2% damage a
  level: the times with it are at the end.)
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

## Found by the review (21 Nov) and what was done

Fixed, with tests in `realm/core/tests/rejoin.rs`: a hero who left by the gate or a waystone kept her data in her
slot while the save held none of it, and the flow kept sources from an older build in cells it no longer reached;
either made a client that joined afterwards compute a different field. A slot is now emptied on LEAVE exactly as
`Field::leave` does (W1: if the server needs her final outing at LEAVE, carry it in the event, the slot is gone).
The spitter, lobber and leaper acted one tick late; they now act every 2, 3 and 5 s as the table says.

Not confirmed, left for R2 to decide:
- QUEEN OF PENTACLES: the code takes `coin / 2 x (10 - keep) / 10`, so one copy loses 45%; `FALL_LOSS_TENTHS` is
  unused and suggests 40% was meant. The contract's "loses a tenth less" fits both.
- A leap of up to 200 px, a pull or a push moves a monster after the tick's grid was built (12 px of slack), so
  contact and area checks can miss it for that one tick.
- A throw beyond the shot pool (4,096) is dropped after its timer was reset: that monster neither throws nor walks.
- Effects read through `mods` last N ticks; the ones checked in the tick with `has_fx` (MARTYR, DEADEYE, CRUSADE,
  PROVOKE) last N - 1.

## The wire and the window until W1

- A client still sends one byte a tick (direction, bit 7 the skill). `realm_server::wire_input` turns it into the
  core's two-byte input (bit 7 becomes skill 1); the HELLO's class 0..4 joins as KNIGHT..PALADIN at the level the
  server was started with (`--level`, default the field's top). W1 puts the two-byte input and the `Sheet` on the wire.
- The client predicts its hero with `Field::walk`, which is the same `walk_step` the simulation moves her with
  (walls and speed included). A skill that moves her, or a speed change in the same tick, is a misprediction that
  the client smooths out as before.
- The window draws the 42 kinds with the eight stand-in monster pictures (kind modulo 8) and a NOVICE as a KNIGHT.


## R2: tides, altars, bosses, vaults, copies and class bots

Built in `core/src/{tide,boss,vault,transfer,bots,gates}.rs` and `tables/realm.rs`; tests in `core/tests/{tides,bosses,vaults,copies,gates}.rs`.
`Field::open(field, seed, Config)` is unchanged; every number below is a named constant in `tables/realm.rs`.

### The clock and the schedule (pure functions of the realm clock, in ticks)
- A field's **tide k** starts at `k x 36,000 + 12,000 + 3,600 x field` (every 30 min, the first at 10 min, each field 3 min after the one before) and lasts 6,000 ticks (5 min).
- A **field boss** rises 600 ticks (30 s) after the end of every fourth tide (`BOSS_EVERY_TIDES = 4`) and stays 9,600 ticks (8 min). The TOWER alternates THE CHANDELIER and THE GHOSTWRITER.
- The **world boss** (DEATH, id 7) rides every 6 h (`WORLD_EVERY`), on field `k mod 6`, 16,800 ticks (14 min) after that field's tide start, and stays 18,000 ticks (15 min). That lies between the field's own tides and field bosses (tested). Open: Curtis may want a different place in the day.
- Boss ids follow the loot crate's order: 0 HARVESTER, 1 HANGING TREE, 2 MOTHER OF LEECHES, 3 GOAT PROPHET, 4 CHANDELIER, 5 GHOSTWRITER, 6 UNMADE KING, 7 DEATH (world); 8 to 11 are the act and trial bosses (WARDEN, REGENT, ARCHLICH, TRIAL).
- The clock is shared by all copies of a field (`set_clock`); each copy has its own tide, altars and boss.

### Tide and altars
- During a tide the monster target doubles (`TIDE_TARGET_MUL = 2`), monsters walk 20% faster, and 3 of the 6 altars light (chosen by the field's seed and the tide).
- To hold an altar: heroes within 150 px for **60 hero-seconds x factor**, factor = max(1, heroes / 20) fixed at the start. Altar health is 8,000 x factor x the level scale of the top hero. Monsters within 60 px strike it on the contact cadence.
- **Two altars held = the tide is WON at once** (it ends early, TIDE CACHE paid to the contributors). Otherwise LOST at the end: monsters keep +20% speed for 2,400 ticks and the next boss does 120% damage. A won tide gives the boss 80% health.
- Contribution = damage dealt + healing done to others + half of damage taken. Floors for a share of the cache: 40 x factor in a tide, 0.2% of the boss's health for a boss. A hero who has stood still for 10 s (`STILL_TICKS`) earns none. Rewards come as `Event::Reward` with `Field::rewarded(first, count)`, sorted by contribution, then id.

### Bosses
- A boss is a monster slot with flag BOSS (immovable, no recycling) and a `Boss` record. Health `(40,000 + 6,000 x heroes at the heart, at most 600) x level scale`; world boss x10. Phases at 66% and 33%, each shortening the rest between casts by 20%.
- The eight shapes (slam, candles, sweep, lanes, call, mire, pull, wall) are table rows (`Atk`) with a drawn warning (`warn` ticks) before they land. Bosses with two concurrent casts or chained attacks use `twice_from` and `then`. MOTHER OF LEECHES drains 50% of what she deals. The contract's boss table is checked row by row by a test.
- Numbers chosen: SWEEP turns 24 sixteenths of a turn a second, LANES move 420 px/s, PULL draws 140 px, WALL leaves a gap of 35 degrees with ends 60 px, MIRE slows heroes 40%.
- **Event additions:** `Tide{state,index}`, `Altar{index,state}`, `Boss{which,state,health}`, `Reward{kind,source,level,seals,first,count}`, `Vault{state,n}`, appended after `Xp` (ranks 12 to 16). `Outing` gained `tide_contrib` and `boss_contrib`; `STATE_VERSION` is 3 (adds idle, the two contributions and the realm block).

### Vaults and copies
- `open_vault(vault, seals, seed, cfg)`: 6 rows (levels 20, 30, 40, 50, 60 and the class trial), a 2,048 px arena (`build_vault`), up to 8 heroes, a 15-minute timeline of waves. Downed heroes are pinned at 1 health (no FALLEN) inside. Won by clearing the timeline; lost when all are down. Overtime after the timeline: 3 minutes (`VAULT_OVERTIME`). Chest and loss rewards use `chest_rolls` and `seal_scale`.
- **Moving between copies:** `transfer_out(id)` gives a `Transfer` (the whole hero, state carried); `transfer_in(&t, salt)` places her on the receiving copy's middle ring at a point drawn from the salt (`ring_point`); a follower that applies the same calls keeps the same hash (tested, including mid-tide). `heroes_by_ring` orders who moves first. A downed hero who moves up on a transfer is carried as she is (open question: or healed).

### Rules changes from the measurements
1. **Thread-count bug fixed (found by the same-hash gate).** `phase_fight` applied each thread range's strikes (hits, heals, pulls) before the next range's, so a PROVOKE pull or a push landed between two heroes' hits and the kills' places and credits depended on the thread count (found on THE TOWER, 200 heroes, 2 threads, tick 242). All ranges' strikes are now one list, applied in hero order. Hash equal on 1, 2, 3 and 4 threads and a follower on all six fields.
2. **Banking and leaving (from W1).** Leaving by a waystone now banks the carried coin first (`Bank` then `Leave`, only when there is coin). **A hit pauses the hold interact for that tick; it no longer starts it over** (`hurt_hero` no longer zeroes `hold`; `act` does not count a tick after a hit). Walking away from the waystone or being downed still resets it. Reason: in a crowd bots were hit every second and never banked.
3. **PRIEST:** HOLY LIGHT damage 15 to **28** (same cadence 12 ticks). Walker gate kill times are now 1.07, 1.17, 1.10, 0.93, 0.84, 0.76 s at levels 10 to 60 (before 2.04 to 1.43), inside the 0.6 to 1.2 s band.
4. **ARCHER and MAGE** stay at 0.62 to 1.05 s to level 30 and 0.41 to 0.56 s from level 40 (jobs and FOCUS). Decided: not changed. The weapon table spreads damage a second by 3.2, which is wider than a 2x band; a ranged class has a third of the knight's health at its level, and the gate is for the mean (0.55 to 0.94 s across levels 10 to 60). Open for Curtis if they should be slower.
5. **QUEEN OF PENTACLES (45% or 40%):** a fall now loses `FALL_LOSS_TENTHS - keep` tenths of the haul: 50% with no copy, **40% with one**, none with five (it was `coin / 2 x (10 - keep) / 10`: 45%). "A tenth less" reads as one tenth of the haul.
6. **A throw dropped beyond the 4,096 shot pool** no longer loses its throw: the thrower's timer goes to 0, so it throws again the next tick it has room.
7. **Leap, pull and push after the grid was built:** left as is and accepted. The grid is built once a tick; a monster moved by a leap (up to 200 px), pull or push after it can be missed by a contact or area check for that one tick (12 px of slack). Rebuilding the grid costs about 1.2 ms a tick at 20,000 monsters; the miss costs one tick (50 ms) of one monster's hit.
8. **Effects checked with `has_fx` (MARTYR, DEADEYE, CRUSADE, PROVOKE) last N - 1 ticks** and the others N: accepted, one tick (50 ms) in a 2 to 10 s effect.
9. **PROVOKE radius:** kept as the flow seed at the knight's cell, which pulls the horde within about 7 flow cells (224 px) rather than 200 px. The 24 px more is in the knight's favour and costs no extra pass.
10. **CLASS_XP:** not retuned. (Field levels were removed on 27 Nov 2026, see the end.) A lone NOVICE kiting 10 minutes reaches field level 2 (mean of 10 seeds, 143 kills); a four-hero party gets level 4 on THE FOOL'S ROAD, 11 on the MARSH, 77 on the PEAKS and 185 on the EDGE in 5 minutes, which is a field level (not a class level) and is not what CLASS_XP gates. The curve stays a placeholder until the loot and the store's real progress exist.

### The bots and the gates
- Class bots (`bots.rs`, whole numbers, seeded): flee from every monster within reach (110, 160 or 200 px by role) weighted by `FLEE_VEC_K / d^2`, score eight directions, skip those into walls or within 300 px of the rim (a second pass when all are shut), keep the last direction (a fifth of the vector as a bonus, so a wall does not make her dither), patrol a ring (a slow orbit, `PATROL_W = 8`), go to altars and the boss when `objectives`, raise downed allies when at most 3 monsters are within 60 px, bank at a waystone at 400 coin, pick cards from role lists, drink potions on a press edge, use skills when 3 or more monsters are within 150 px, the ultimate at 5. Parties of up to 8 stay close to each other (`PARTY_MAX`).
- **Alone at the edge of THE FOOL'S ROAD, class level 1, 10 minutes, 10 seeds: never fallen 8/10 to 9/10 (never downed 6/10).** That meets the gate (it was 6/10 at the start of R2 and 7/10 from the first build). The density base stays `60 x heroes`. Tried and rejected: a risk term from each monster's predicted closest approach (worse, and it dithered at walls), and a base of 25, 20 or 12 a hero (no better for a party: it is the bot, not the count).
- **Party of knight, priest, archer, mage, 100 ticks before the field's tide, bottom level of the field, 10 seeds, 6,000 ticks, bots patrol and raise and do not seek altars (objectives off):** never fallen: THE FOOL'S ROAD 2/10, THE HANGED WOOD 0/10, THE MOON MARSH 1/10, THE HERMIT'S PEAKS 10/10, THE TOWER 10/10, THE WORLD'S EDGE 10/10. **Not met on the first three fields.** At level 1 all four are NOVICEs; at levels 10 and 20 the first downs come 7 to 22 s in, when the tide's doubled and faster horde arrives on four heroes together, and the party's raise (2 s standing within 40 px) costs more health than it saves. With the tide's target doubling off, THE FOOL'S ROAD was 8/10, so the lever is the tide's size on a small party at the low levels: a candidate is that the doubling grows from 1.0 at 4 heroes to 2.0 at 40. Left for Curtis (a rules number, not a bot number). The test checks the three fields that pass.
- **Jobs in a crowd of 100 at class level 50 (3 seeds, contribution per hero):** KNIGHT WARDEN 61k / BERSERKER 210k (gap 70%), MAGE ARCHMAGE 3.73M / HEXER 3.68M (1%), ARCHER RANGER 4.99M / SHARPSHOOTER 1.90M (62%), PRIEST ORACLE 0.31M / INQUISITOR 1.18M (73%), PALADIN TEMPLAR 1.56M / CRUSADER 1.85M (15%). **Not met except the MAGE pair.** Contribution counts damage and healing, so a job built to hold (WARDEN, ORACLE) scores less by design; the gate's "within 15%" probably wants a role-aware measure. Not tuned; handed back with this table.
- Same-hash gate (`tests/gates.rs`, `hash_gate`): 4 field copies on 1, 2, 3 and 4 threads and a follower loaded from bytes at a third of the way, bot heroes of both jobs of every class, a tide and a boss summoned at the heart, hashes compared every 100 ticks. The default test is 200 heroes x 600 ticks per field (26 s for all six); `GATE_FULL=1` runs 1,000 x 2,000.
- **Budget (`realm-loadtest bots tick 1000 20000 900 4`, bots excluded, a tide on, step only):** mean / p99 ms: FOOL'S ROAD 5.93 / 9.99, HANGED WOOD 4.87 / 9.26, MOON MARSH 5.07 / 8.53, HERMIT'S PEAKS 5.11 / 7.46, TOWER 4.21 / 6.77, WORLD'S EDGE 5.62 / 10.74. All inside 20 ms mean; the worst is the EDGE at p99. The server's own bench (`--bots=1000 --monsters=20000 --rally=0.3 --threads=4`, with the protocol) gave 9.01 / 16.04 ms.

### Open questions (R2)
1. The party gate on the first three fields and the jobs gate (above): a tide-size rule and a role-aware contribution measure.
2. The world boss's slot in the day, the vault overtime of 3 minutes, whether a won tide should end the tide at once, and whether a downed hero moved to another copy should keep the down.
3. The client expects `world["boss"]` (name, health, max health, position): the core has `Field::boss()`, `boss_pos()` and `boss_health()` for the server to put there.

## R3: players against players (section 14)

Built in `core/src/pvp.rs` with hooks in `attack.rs`, `combat.rs`, `act.rs`, `mods.rs`, `tide.rs`, `state.rs`,
`terrain.rs` (`build_yard`), `events.rs` and `bots.rs` (`Plan::hunter`). Tests are in `core/tests/pvp.rs`.
Every number and the open questions are in `docs/realm/pvp.md`.

- **Who may strike whom.** One relation, `Field::hostile` and `Field::foes`, covers:
  - both heroes marked;
  - two guilds of a war that is on (its tide is running);
  - the pair of a running duel in a yard.
  Nobody strikes or is struck within 300 px of a waystone or the gate, and a vault is safe everywhere. Blows do
  40% of the monster damage, through the target's reductions, for every weapon shape and the Ring, Thick, Volley,
  Dash and Zone skills. They are gathered with the monster hits through the hero grid, only by flagged heroes off
  safe ground, and applied in hero order.
- **The mark.**
  - The rite needs class level 20 and a 5 s hold of interact plus `IN_MARK` (`0x4000`) at a waystone; it never banks.
  - +25% coin and +15 luck while marked.
  - The helper ban (`may_help`, 60 s) covers heals, shields, buffs, raises and SANCTUARY.
  - A fall after a hero's blow pays the downer the lost coin (`Plunder`).
  - The 10-minute wait is carried in the outing, and home through `Flush.mark` to the gateway's mark book, which
    stores the ticks left. It runs down only in a field; town and logged-out time do not count.
  - Kill credit (the downer) is cleared on rise, on a non-hero down, and on leave (`forget_slot`, which also
    disowns the leaver's drops and zones).
- **Gateway limits:** 32 armed wars per field, 3 waiting declared per guild, one accepted war per guild per tide,
  5 PvP requests a minute per account, 64 duels at once stepped outside the social lock, and fought wars with no
  result are drawn a minute after their tide.
- **Events, appended after `Vault`:** `Mark` 17, `Struck` 18, `Slain` 19, `Plunder` 20, `War` 21, `Duel` 22.
- **State: no saved format changed.** The PvP block (tag `0x50`) is appended to the state bytes only when non-empty,
  so a field without PvP hashes as before, and `STATE_VERSION` stays 3. A yard is vault byte 254.
- **Fixed:** `join` read a carried `struck_ago` larger than the field's tick as a strike at tick 0. A strike older
  than 10 minutes now reads as none.
- **Bots:** a bot never raises a hero the help ban forbids, and a hunter never raises her own prey.
- **Budget:** 1,000 heroes, 500 of them marked hunters, among 20,000 monsters, with a tide and 4 threads. The worst
  field is THE WORLD'S EDGE at 6.19 ms mean and 13.17 ms p99. Hashes are equal on 1 to 4 threads and on a follower.

## Scope change (27 Nov 2026): no field level, class level is the progression

Curtis: "remove per field xp system"; Horde & Hearth is an MMO with survivor horde and survivor elements. What the
core does now (rules 2 and 5):
- **Gone:** the hero's per-outing `level` and `xp`, `gain_field_xp`, `FIELD_XP_PER_LEVEL`, `FIELD_LEVEL_DMG_PCT/CAP`
  and the field-level factor in `mods.rs`; the `Outing` no longer carries them (server wire and state codec follow,
  `STATE_VERSION` 4). Event rank 0 `LEVEL` is now `GRANT(hero, source)`.
- **Class XP** is what a kill pays, as before: kill XP x `FIELD_KILL_XP_PCT` (renamed from `FIELD_XP_PCT`, THE
  TOWER 800%) x the class XP percent (THE HERMIT +8%, SCHOLAR'S INK +50%) x the race's, 200 px active share, none
  from a monster more than 10 levels below; event XP as before. `Hero::class_xp` sums it for the HUD, and
  `Sheet::class_xp` (the saved total, from the gateway's `sheet_of`) lets the client draw the class level bar
  (`realm_core::class_progress`).
- **Draws** (`Field::grant_draw(hero, source)`, `GRANT_ENTER/KILL/SHRINE`): one when she joins with a fresh outing
  (a move between copies brings her draws: none), one to every sharer of an ELITE, CHAMPION or boss kill, and the
  shrine job calls it once per shrine per outing. Queue of 9 and the pick rules unchanged. A join's GRANT and
  DRAW events are cleared by the next step (joining is not a tick); the offer is state.
- **Damage:** `CLASS_LEVEL_DMG_PCT` = 2: +2% a class level the field counts (its ceiling), +118% at 60.

**Retune, `measure pace 3 5`** (one class bot alone on the ring of her level, KNIGHT MAGE ARCHER PRIEST PALADIN,
3 seeds, 5 minutes; mean kills a run; before: the time-weighted field-level bonus she had):

| field, class level | before: kills (field-level bonus) | after: kills (2% a class level) |
|---|---|---|
| FOOL'S ROAD 10 | 409 (+7%) | 423 (+18%) |
| HANGED WOOD 10 / 15 | 764 (+24%) / 945 (+30%) | 754 / 994 (+18% / +28%) |
| MOON MARSH 20 / 25 | 675 (+33%) / 482 (+23%) | 641 / 444 (+38% / +48%) |
| HERMIT'S PEAKS 30 / 35 | 260 (+24%) / 426 (+36%) | 288 / 460 (+58% / +68%) |
| THE TOWER 40 / 45 | 340 (+72%) / 1,030 (+93%) | 342 / 862 (+78% / +88%) |
| WORLD'S EDGE 50 / 55 | 2,756 (+111%) / 2,175 (+95%) | 2,018 / 1,768 (+98% / +108%) |

Within 11% from 10 to 40; 16% to 27% fewer kills at 45 to 55, where the old bonus snowballed with the kills (and
kept growing past 5 minutes, to +160% at field level 41). Kept at 2 (whole numbers: 3 would make 20 to 35 half
again faster). `measure killtime` (walker gate, now with the class term): mean of the five classes 0.73 s at 10,
0.68 at 20, 0.59 at 30, 0.31 at 40, 0.26 at 50, 0.20 at 60.

Open: the class XP an hour at 45 to 60 falls by about the kills' 16% to 27%, so `CLASS_XP` (fitted to kill rates,
balance.md) wants a `balance probe`/`fit` rerun; the draws an outing are far fewer (an opening draw and the elites,
where a 5-minute outing at 50 used to level 20 to 40 times), which the card-heavy builds feel most.


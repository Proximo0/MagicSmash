# Stage 3 brief: build the frozen list

The contract for every stage 3 job. What is built: `docs/content_list.md` part 2 (§ 36 to 54), named here as CL §.
A job reads the sections of this file its prompt names, the CL § of its rows, and nothing else of either file.

## 1. Goal and gate

Build every row of the frozen list, the screens the plan asks for (`docs/release_plan.md`, stage 3) and a speed pass.
The gate: on the owner's four PCs the coverage robot is green for every row that carries a **B** (CL § 36), and the
three shelves of rows not built yet are empty: `Upgrades.UNBUILT` (§ 4.3), `Readings.UNBUILT` (§ 4.8) and
`Profile.UNBUILT` (§ 4.9). Numbers are starting values; nobody tunes in stage 3 (that is stage 5). One pass is the
lead's: before the gate build he moves one knob at a time until groups of bot runs reach the Archlich again, so the
build the owner gets plays.

## 2. Rules for every job, on top of the preamble

1. A row is built when every letter of its Test column is green. Write the **U** test first and see it red.
2. Names, keys, pairs and effects are frozen. If a row cannot be built as written (a name too wide for its screen, a
   rule that contradicts another), stop and report: the lead changes the list, a worker never does.
3. Numbers live in `Spells.STATS`, `Spells.EVOS`, `Spells.EVOS2`, `Upgrades.CATALOG`, `Readings.ROWS`, `Seals`,
   `Profile.META`, `Cards.CARDS` or `Tuning`, with the CL starting value. No number in code.
4. Every row you build is credited where its effect lands: `w.record.use("<key>", slot)` (§ 4.4). The coverage robot
   fails a row that was dealt and never credited.
5. Every new effect is seen: an event the arena draws, or a mark on the wizard or the foe. Give the view its line in
   `game/arena/` only when your job lists the file; otherwise report the event and what should be drawn.
6. A change that must not alter play ends with `GOLDEN same`. A change that alters play says in its report which
   golden seeds moved and why.
7. Work only in the folder your prompt gives you (a copy of the repository made for your job). Other jobs run beside
   you in other folders, so keep out of their way in the files everybody meets in: a new test goes in a test file
   of your own (`tests/unit/test_<your topic>.gd`), a new `Tuning` row goes inside the group it belongs to and never
   at the end of the list, a new event's handler goes beside the handlers of its kind. Name every new file in your
   report, its `.uid` file too.
8. Shared ids are handed out in § 4.10. Take only the ids your job is given; ask the lead for a new one.
9. A row whose effect is not on main stays on its shelf (`UNBUILT`) and leaves it in the change that builds the
   effect. A card's words say only what the card does on main today: the words for an effect land with the effect.
10. A job that changes how a build comes together (what a card needs, what a slot holds, what a pick is worth)
    teaches the bots in the same change (`SmashBot`: the novice, the casual and the veteran) and measures a group
    before and after: `GD -s tools/playtest.gd -- --runs=4 --wizards=2 --persona=casual --seed=7 --minutes=17`. One
    run is not a measurement: a single seed flips between a loss at 4:00 and a win at 17:00 after any change.
11. A job that adds a spell adds its two pip colours with its data row (`Sprites.SPELL_COLORS`, `SPELL_DARK`).
12. A picture drawn mirrored gets its rect from a function with a test (`Still.figure_rect`, `Sprites.draw_at`):
    Godot mirrors a rect of negative width in place, so its corner never moves.

## 3. Order

A job starts when the jobs it needs are on main. `O` is an opus job (game rules), `S` a sonnet job (screens, tools).

**Done, on main:** the contract (#291) · the use counters (#292, § 4.4) · A1 the cast split (#293) · P1 the shop's
rows and the unlock track (#295) · U4 sound (#296) · U3 options (#297) · A2 the evolution id (#298) · T1 the
coverage robot (#299) · R1 the Readings as data (#300) · the twelve new cards' emblems (#301) · U6 the team shrine
(#302) · A3 the catalog (#304) · U1 the shared screen (#305).

**The casting chain, one after another:**

| Job | What | Needs | Owns |
|---|---|---|---|
| A4 `O` | The hooks every cast reads (§ 4.5) with THE STAR and THE EMPRESS, and the credit of the arcana of today, which empties the coverage robot's `PENDING` list (§ 4.4) | A3 | `world/cast*.gd`, `world/enemies.gd`, the list in `tests/bot/bot_cover.gd` |

**After A4, side by side (one file, one job at a time).** A job that builds a second evolution adds it to
`SmashBot.PICK_PRIORITY` and to `test_spells::test_evolution_beats_max_level`, which know only the first today.

| Job | Rows | Owns |
|---|---|---|
| C1 `O` | HEX, EVIL EYE, THE DEVIL; the HEXED bit (§ 4.6) | new `world/cast_hex.gd`, `world/enemies.gd` |
| C2 `O` | SPIRIT BLADES, DANSE MACABRE, the ORBIT pickup; spell objects (§ 4.7) | new `world/cast_blades.gd`, `world/players.gd` |
| C3 `O` | LODESTAR, THE HIGH PRIESTESS (the echo queue) | `world/cast_bolts.gd`, `world/casting.gd` |
| C4 `O` | GREEK FIRE, WINTER VEIL; circle kinds FIRE and VEIL (§ 4.7) | `world/cast_circles.gd` |
| C5 `O` | DIES IRAE, WHIRLWIND's change, THE TOWER's refill and JUDGEMENT's blast with their new words (§ 4.2) | `world/cast_chain.gd`, `world/cast_sweep.gd`, `world/players.gd` after C2 |
| V1 `S` | What C1 to C5 look and sound like; THE SPREAD, the chart of every pair (CL § 41) | `game/arena/draw_fx.gd`, `draw_enemies.gd`, `events.gd`, new `game/ui/spread.gd` |

**Beside the casting chain:**

| Job | What | Owns |
|---|---|---|
| T2 `S` | The damage table measures a support spell (CL § 52, 53) and both evolutions of a spell (`_dps` reads the first only) | `tools/spell_dps.gd` |
| L1 `O` | The shop's option rows in a run: one more redraw, one more banish, the head start (`redraw`, `banish`, `start_level` leave `Profile.UNBUILT`) | `world/levels.gd`, the rows' `EFFECTS` in `profile.gd` |
| P2 `O` | The satchel, keepsakes, provisions, KEEP on the results screen; the save becomes version 3 | `profile.gd` after L1, `loot.gd`, `world/drops.gd` |
| D1 `O` | The eleven deeds (CL § 50); the rule `evo` learns the second evolutions; needs P2 and B1 | `achievements.gd`, `profile.gd` after P2 |
| P3 `S` | The shop's three shelves and counter, the satchel screen (the shop today is `title.gd` `_draw_unlocks`) | `game/sanctum/sanctum_view.gd`, `sanctum.gd`, new `game/ui/satchel.gd` |
| R2 `O` | The fifteen Readings whose rule is new behaviour (they leave `Readings.UNBUILT`); the ladder's new numbers; Seal keys `omen` and `boss_fate` | `world/waves.gd`, `world/shrines.gd`, `world/drops.gd` after P2 |
| R3 `S` | The Reading at the table: the deal, the vote, the card on the HUD | `game/ui/title.gd` (lobby part), `game/arena/hud.gd` |
| B1 `O` | Boss rewards at each phase, Overtime, the Daily Draw | `bosses.gd`, `world/waves.gd` after R2, `results.gd` |
| B2 `O` | Class level 5 (CL § 47) | `classes.gd`, `world/players.gd` after C5 |
| B3 `S` | Ten monster cards and four card stats (CL § 48) | `cards.gd`, `loot.gd` after P2 |
| U2 `O` | A party that stays seated between runs: the hub and "play again" for two to four. The LAN join check compares every row width of the snapshot (today the version and the wizard row only) | `game/ui/title.gd` before R3, `game/sanctum/sanctum_view.gd` before P3, `arena.gd`, `net.gd` |
| U5 `S` | A first run that teaches: revive, redraw and banish, shrines, the first evolution. A tray row that completes a pair says so | `game/arena/fate_view.gd`, `game/arena/tray.gd`, new `game/logic/lessons.gd` |
| U7 `S` | Button pictures for each kind of pad | `game/input/player_input.gd`, new `game/ui/glyphs.gd` |
| U8 `O` | Bots at an altar: a bot holds her spot while she pays (today she steps in and out of the circle as she dodges, and 10 to 14 of 37 shrines get paid), and hurries to a shrine where a partner waits | the shrine part of `smash_bot.gd` |
| S1 `O` | The speed pass: the step, the snapshot, drawing a crowd (skill `measure-fix-loop`); `tools/step_profile.gd` and `tests/sim/sim_horde.gd` learn the evolution id | named when it starts |

"Before" and "after" in the Owns column are the order two jobs take one file. A job may add its own fields to
`world.gd`, `entities.gd` and `tuning.gd` and its own tests; it changes nothing else there. `smash_bot.gd` is met by
every job under rule 10: each adds its rule beside the rules of its kind and nothing else. The lead owns
`project.godot`, CI and every line a report asks for in a file the job does not own.

## 4. The shared contract

### 4.1 The evolution id (A2)

A spell has no, one or two evolutions. Where the code holds a flag `evo: bool` it holds an id `evo: int`: 0 none,
1 the evolution `Spells.EVOS` holds today, 2 the new one in `Spells.EVOS2` (same row shape, `{}` for none).

| Spell | id 1 (`EVOS`) | id 2 (`EVOS2`) |
|---|---|---|
| ARCANE BOLT | ASTRAL LANCE | LODESTAR |
| FIREBALL | THUNDERFIRE | GREEK FIRE |
| FROST FAN | BLIZZARD | WINTER VEIL |
| CHAIN LIGHTNING | TEMPEST | DIES IRAE |

- `Spells.evo_row(spell, evo) -> Dictionary` (`{}` for 0 or none). `cooldown`, `damage`, `count`, `bolt_value`,
  `level_value` and `evo_value` take `evo: int` in the place of the flag. `Spells.evolutions(spell) -> int`.
- Shots: `Spells.shot_kind(spell, evo)`, `shot_spell(kind)`, `shot_evo(kind) -> int`. The kinds of today keep their
  numbers; a second evolution's kind is `Spells.SHOT_SECOND + spell` (`SHOT_SECOND := 24`).
- `Upgrades.evo_entry(spell, evo := 1) -> int`, `Upgrades.evo_of(levels, spell) -> int`,
  `Upgrades.evo_id(idx) -> int` (which evolution a catalog row is: the first EVOLUTION row of a spell in catalog
  order is 1, the second 2). `Upgrades.evolved` stays and means `evo_of > 0`.
- `World.Shot.evo` and `World.Rune.evo` are the id. The snapshot's rune column 6 carries it. A weapon level in the
  snapshot is `Spells.MAX_LEVEL + evo` for an evolved spell. `EV_RUNE`'s b is `slot + 4 (id 2) + 8 (evolved) + 16 x
  kind`, so every value of today is unchanged.
- Taking one evolution of a spell shuts the other for the run (`Upgrades.available`).

### 4.2 The catalog (A3)

Twelve rows are appended in this order; a row's index never changes afterwards. Card words fit a tray row: a name
has at most 15 letters, the words under it at most 14 (`TarotArt.ROW_TITLE_CHARS`, `ROW_EFFECT_CHARS`).

| Index | Const | Key | Name | Words on the card | Kind | Needs |
|---|---|---|---|---|---|---|
| 32 | `PRIESTESS` | `priestess` | THE HIGH PRIESTESS | ECHOED CASTS | PASSIVE, 3 levels, weight 6 | |
| 33 | `EMPRESS` | `empress` | THE EMPRESS | WIDER AREAS | PASSIVE, 3 levels, weight 7 | |
| 34 | `DEVIL` | `devil` | THE DEVIL | PAIN IS POWER | PASSIVE, 3 levels, weight 6 | |
| 35 | `STAR` | `star` | THE STAR | MORE MISSILES | PASSIVE, 2 levels, weight 5 | |
| 36 | `W_HEX` | `w_hex` | HEX | WEAKENS A FOE | SPELL 9 | |
| 37 | `W_BLADES` | `w_blades` | SPIRIT BLADES | BLADES CIRCLE | SPELL 10 | |
| 38 | `E_LODESTAR` | `e_lodestar` | LODESTAR | HUNTS BIG PREY | EVOLUTION of 0 | ARCANE BOLT 5, THE STAR 1 |
| 39 | `E_GREEK` | `e_greek` | GREEK FIRE | BURNING GROUND | EVOLUTION of 1 | FIREBALL 5, STRENGTH 1 |
| 40 | `E_VEIL` | `e_veil` | WINTER VEIL | CLOAK OF FROST | EVOLUTION of 2 | FROST FAN 5, THE HIGH PRIESTESS 1 |
| 41 | `E_DIES` | `e_dies` | DIES IRAE | SLAYS THE WEAK | EVOLUTION of 3 | CHAIN LIGHTNING 5, JUDGEMENT 1 |
| 42 | `E_HEX` | `e_hex` | EVIL EYE | HEXED BURST | EVOLUTION of 9 | HEX 5, THE DEVIL 1 |
| 43 | `E_BLADES` | `e_blades` | DANSE MACABRE | A SECOND RING | EVOLUTION of 10 | SPIRIT BLADES 5, THE EMPRESS 1 |

- A tray row writes a name longer than 15 letters without its leading THE (`Upgrades.row_name(idx)`): HIGH PRIESTESS.
  Every other screen writes the full name.
- The partners of the nine evolutions of today change to the chart of CL § 37: `e_arcane` needs THE MAGICIAN,
  `e_fire` THE TOWER, `e_frost` TEMPERANCE, `e_storm` THE CHARIOT, `e_star` THE HERMIT, `e_rune` THE MOON; `e_bone`,
  `e_candle` and `e_cleave` stay.
- THE TOWER (`nova`, index 6) and JUDGEMENT (`life`, index 7) are PASSIVE rows that take an arcana slot: 3 levels
  with weight 5; 2 levels with weight 4. Their charge and life at the pick stay, and so do their words (`+1 NOVA
  NOW`, `+1 LIFE NOW`) until C5 builds the refill and the blast: C5 changes the words to NOVAS REFILL and +1 LIFE,
  BLAST in the same change (§ 2.9). The kind INSTANT keeps its number and has no rows.
- `Spells.COUNT` is 11. The data rows of HEX (cast kind `"hex"`) and SPIRIT BLADES (`"blades"`) and of the six new
  evolutions hold the CL numbers; the job that builds a row may add keys to its own row. `WorldCasting._cast`
  does nothing for a cast kind that has no caster yet.
- As built: every evolution's `requires` is `[[its spell, 5], [its arcana, 1]]`. `Upgrades.partner_row(spell,
  evo := 1) -> int` and `Spells.passive_partner(spell, evo := 1) -> String` name an evolution's arcana
  (`Spells.partner` is gone). `Upgrades.pairs_with(levels, idx, banned := {}) -> bool`: taking `idx` would complete a
  pair. A hand keeps the last free slot of a kind for a card that would (`_pair_wanted`), and a completing card
  weighs `PARTNER_WEIGHT` times its own weight.
- FIREBALL's first road (id 1) is THUNDERFIRE with THE TOWER, as § 4.1 fixes it; CL § 37's chart names GREEK FIRE
  first. Until C4 builds GREEK FIRE, a profile that has not earned THE TOWER (the deed EVOLVE) has no road for
  FIREBALL, and STRENGTH completes no pair.
- Bots (§ 2.10): the novice takes a card that completes a pair as its shiniest; the casual takes the arcana of a
  pair ahead of everything but an evolution once the pair's spell is at `SmashBot.PAIR_FROM_LEVEL`; the veteran
  plans only for an evolution that is built and still open (`SmashBot._plan_open`).

### 4.3 Shut rows (A3)

Three things keep a row out of a hand, and all three use the path a banish uses (`Upgrades.available`'s `banned`):

- **Banished** by the wizard for the run: `Player.banned`, as built.
- **Locked** for the table: the host's profile has not opened it (CL § 44). `World.locked` is the table's mask
  (Upgrades index -> true), set at the start of a run from `World.apply_meta`'s `"locked"` (an Array of indices;
  absent: nothing is locked, as in every scripted run). Each wizard's `banned` gets the mask without her own class
  weapon, its arcana and its evolution. `snapshot()["lk"]` carries the mask (a `PackedInt32Array`), so every seat's
  chart is the same. `Profile.bonuses()` carries `"locked"` (`Profile.locked_rows`), so every real run is dealt from
  the host's profile; scripted runs, the bots and the tools pass none, and a career (`tools/career.gd`) plays its own
  profile's locks. A wizard's own class weapon is always open with its first road (`World._open_own_rows`).
- **Unbuilt**: `Upgrades.UNBUILT`, the indices whose code is not on main yet. `available` refuses them for everyone,
  and `WorldGrants.give` (§ 4.4) is the one path past it, for tests. A3 lists all twelve new rows; each job takes its
  rows off the list in the change that builds them. The stage's gate test asserts the list is empty.

### 4.4 Use counters and the coverage robot (T1)

- `Results.use(key: String, slot: int = -1, n: int = 1)`: counts a row's use for the run and for the seat.
  `Results.used(key) -> int`. `to_dict()` carries `"uses"` (key -> count) and `"uses_by"` (slot -> key -> count).
  Never call it inside a loop over every enemy of a step; call it at the event (a cast, a proc, a pick-up, a rule
  that fires).
- Keys: a catalog row's key (`quick`, `e_greek`); a Reading's key (`r_cups_5`); `seal_<n>` for a Seal's rule when
  it changes something (1 to 8); `reward_<boss>_<phase>` for a boss reward; `cl5_<skill>` for a class level 5
  effect; `card_<key>` for a monster card's stat; `prov_<key>` for a provision; `overtime`; `daily`; `keepsake`.
- A spell or an evolution is credited by its damage (`Results.add_source`, as built); a support spell also by `use`.
- `WorldGrants.give(w, p, idx)`: gives a wizard a catalog row with everything it needs (an evolution: its spell at
  level 5 and its arcana at level 1), past locks and `UNBUILT`. For tests, tools and the coverage robot only.
- The coverage robot (as built; `docs/bots.md`, "The coverage robot"): `tests/bot/bot_cover.gd` plays one fresh run
  of the real game for a row dealt by force (`-- --cover --deal=<key>`) and fails on an engine error or a row never
  credited: `COVER <key> ok uses=N`, `COVER <key> pending` or `COVER <key> FAIL <why>`. `tests/bot/cover.sh
  [nshards=2]` runs every shard (`COVER_ALL shards= rows= ok= pending= failed= bad_shards=`; CI row `bot-cover`,
  `check_all` tasks `botcover<i>`). `GD -s tools/tool.gd -- coverage [--gate]` prints the plan without playing
  (`COVERAGE rows= cover= pending= unbuilt=`; `--gate` fails while a row is pending or unbuilt: the stage's gate).
- A family of rows is one script in `tests/bot/cover/` that extends `family.gd` (`catalog.gd`, `readings.gd`); it
  reads its rows from the data tables, so a new row is covered without a list being edited, and it plans a row on a
  shelf (`UNBUILT`) as unbuilt. The job that adds a family of rows (Seals, boss rewards, class level 5, monster
  cards, provisions) adds its script.
- `bot_cover.gd` keeps `PENDING`: rows dealt and played that nothing credits yet (the arcana of today). A4 credits
  them and empties the list; a row that is credited while it is still listed fails.

### 4.5 The hooks every cast reads (A4)

- `WorldCasting._missiles(p) -> int`: THE STAR's level. `_cast` adds it to `n` for every cast kind; a sweep widens
  its arc by a half for each; the blades gain a blade each.
- `WorldCasting._area(p) -> float`: THE EMPRESS's multiplier (1 without her). It scales a blast and its reach, a
  frost burst, a splinter's flight, a rune or candle circle, a sweep's reach, the blades' ring, the hex's jump, the
  veil and the fire patch.
- `WorldEnemies._dealt_mul(w, src: World.Player) -> float`: everything the attacker multiplies her damage by
  (STRENGTH, WANDS, the staff, fury, an apprentice's share today; THE DEVIL and THREE OF SWORDS later).
- `WorldEnemies._taken_mul(w, e: World.Enemy) -> float`: everything the foe multiplies the damage it takes by
  (1 today; HEX and PROVOKE's second effect later). `_damage_enemy` multiplies by both and nothing else.

### 4.6 Enemy status bits (C1)

`World.Enemy.status` goes to the snapshot's `E_STATUS`. Bit 0 `World.ST_HEXED`. The enemy holds `hex_t` (seconds
left), `hex_mul` (the share of extra damage), `hex_slot`, `hex_jumps` and `hex_evo`. Bits 1 to 7 are free; ask the
lead. Bits 20 and 21 are taken (cloak, turn).

### 4.7 Spell objects and circle kinds (C2, C4)

- `snapshot()["o"]`, `World.O_FLOATS` floats an object: kind, owner, x, y, a, b, t, evolved. Kind 0 `World.O_BLADE`
  (a: its angle, b: its ring's radius, evolved: the evolution id). The World keeps them in `World.objects`.
- `World.Rune.kind`: `Spells.CIRCLE_FIRE := 2` (GREEK FIRE's patch: burns, never pulls) and `Spells.CIRCLE_VEIL := 3`
  (WINTER VEIL's mist: it follows `Rune.owner` each step and slows as the fan does).

### 4.8 Readings and the ladder (R1, R2)

As built by R1 (`game/logic/readings.gd`, `docs/systems.md` "The Reading"):

- `Readings.ROWS`: `[key, name, words, party only, values]` in CL § 42's order; a key is `r_<suit>_<n>`
  (`r_wands_8`, `r_pent_10`). The words are at most `WORD_LINES` (3) lines of `WORD_WIDTH` (18) letters.
  `Readings.deal(rng, open, seats, n) -> Array[String]`, `Readings.vote(votes, seats) -> int` (seat 1 breaks a tie,
  a missing vote abstains), `Readings.values(key) -> Dictionary`, `Readings.index_of(key) -> int`.
- `World.apply_reading(key)` runs after `apply_seal`: a value both name multiplies (`Readings.MERGE_MUL`: `hp`,
  `horde`, `boss`, `speed`, `potions`) or adds (`MERGE_ADD`: `hearts`); every other key sets the World field
  `read_<key>`, which the row's rule reads. `World.reading` holds the key ("" for none), the header carries its
  index (`W_READING`, -1 for none), and `Net.reading` carries it to the guests. `tools/full_run.gd` and
  `tools/playtest.gd` take `--reading=<key>`.
- A boss is a foe: a row that says FOES names both `hp` and `boss`. A Reading is credited (`use`) where its rule
  fires, and once at the start of the run when it only changes numbers.
- `Readings.UNBUILT` is the shelf: fifteen keys, every row but ACE OF CUPS. `deal` never deals a key on it. R2 builds
  the rules and empties it. Decided for R2: EIGHT OF WANDS is one number, the run's clock (`read_pace`: `step`
  plays that many seconds for each second given), so XP, spawns and bosses all come a fifth sooner. Open for R2:
  what TEN OF PENTACLES plays at SEAL VIII, where there is no next step.
- The ladder's numbers change in `Seals` only (`ARCHMAGE`, `PER_SEAL`, `START_UNLOCKED`, the new keys `omen` and
  `boss_fate`): CL § 43.

### 4.9 The profile (P1, L1, P2)

As built by P1 (`game/logic/profile.gd`):

- `Profile.META` holds fifteen rows in CL § 45's order: the six of the stat shelf, then `redraw`, `banish`,
  `start_level`, `satchel`, `favour`, `respec`, `deck_hex`, `deck_blades`, `deck_priestess`. `Profile.GATES` holds
  the Seal win that opens a level; `level_open(key, level) -> bool`, `gate_why(key, level) -> String`,
  `closed_why(i) -> String` (MAX, NOT YET, WIN <step>).
- `Profile.UNBUILT` is the shelf of shop rows whose effect is not in the game: such a row cannot be bought and
  says NOT YET. L1 takes `redraw`, `banish` and `start_level` off it; P2 `satchel`; R3 `favour`; C1, C2 and C3 the
  deck that opens their rows; P3 `respec` (it waits for a shop row without levels).
- `Profile.OPENS` is the unlock track (CL § 44): `[kind, source, content keys]`, kind `start`, `deed` or `deck`. A
  deed that `Achievements.LIST` does not hold yet is open for everyone (D1 adds the eleven).
  `Profile.opened() -> Dictionary`: every content key open to this profile (catalog keys, Reading keys, class and
  race names, `reading`, `overtime`, `daily`), from its deeds, its decks and its saved heroes. An evolution is never
  listed: it is open when every row its `requires` names is open. `Profile.locked_rows() -> Array[int]` is the
  catalog's rest, handed to the run in `bonuses()["locked"]`. `class_open(c)`, `race_open(r)` for the builder.
- The save is version 2 until P2. P2 adds `Hero.pockets: Array` (each `{"kind": "armor" or "prov", "key", "tier"}`),
  `Hero.keepsake: String`, `Profile.keepsakes: Array` (pockets a hero has: 1 + the level of `satchel`) and makes
  the save version 3: a version 2 save opens everything its record proves (CL § 44) and loses nothing; a damaged
  or newer save is handled as today.
- The shop's screen today is the old unlock list (`game/ui/title.gd`, `_draw_unlocks`) with five pips squeezed in;
  P3 builds the real one in the Sanctum, wide enough for a name of 19 letters.

### 4.10 Ids handed out

| What | Ids |
|---|---|
| Events (`World.EV_*`) | 54 `EV_HEX` C1 · 55 `EV_ECHO` C3 · 56 `EV_REFILL` C5 · 57 `EV_EXECUTE` C5 · 58 `EV_REWARD` B1 · 59 `EV_OVERTIME` B1 · 60 `EV_READING` R1 · 61 `EV_OBJECT` C2 · 62 to 69 the lead's |
| Wizard columns (after `P_CLASS_LEVEL`) | `P_NOVA_T` (seconds to the next refill) C5 · `P_KEEP` (her keepsake's armour row, -1) P2 |
| Header (after `W_BOSS_METER`) | `W_READING` R1 · `W_OVERTIME` (whole minutes into Overtime, -1) B1 |
| Snapshot keys | `"o"` C2 · `"lk"` A3 |
| Circle kinds | 2 FIRE, 3 VEIL (C4) |
| Spell indices | 9 HEX, 10 SPIRIT BLADES |
| Input fields | none new: a vote and Overtime's choice are the menu's, not the World's |
| Shrine row | `World.SHRINE_FLOATS` is 7: the seventh float is how many wizards stand in a team shrine (U6) |
| Tuning rows | `team_cost_mul`, `team_pay_time` (U6) |

### 4.11 The shared screen (U1) and the team shrine (U6)

Both are built; their sections in `docs/systems.md` hold the detail. What later jobs build against:

- The camera frames every living human wizard, standing or fallen (apprentices only when no human lives), and
  holds every body 2 px inside the play window (`ArenaDrawWorld.PLAY_WINDOW`, `wanted_camera`, `eased_camera`).
  The leash may not exceed `ArenaDrawWorld.leash_room()` (448 x 203): `leash_x` 440, `leash_y` 200. There is no
  compact tray: a tray keeps its three or four rows and turns see-through while it covers a wizard
  (`ArenaTrayArt.tray_hides_wizard`), and the painted hand under it is not drawn where it would cover one.
- Every living wizard out of view has one steady arrow at the screen's edge in her seat's colour, tagged `P<n>` or
  `A<n>` (`ArenaHud.edge_arrows`). A new HUD piece that sits in the play window follows the same rule: it never
  hides a wizard (see-through or not drawn).
- A team shrine is paid by the whole table into one pot (`Tuning.team_cost_mul`, `team_pay_time`): every wizard
  standing in it pays her share while she stands. A bot waits `SmashBot.SHRINE_PATIENCE` s alone, gives it up, and
  comes back when a partner steps in.

## 5. What the lead does at each landing

Reads the diff and every picture (each figure's feet against her ring, facing both ways), runs the whole suite,
lint, guard and (where § 2.6 asks) golden, lands with `tools/land.sh`, reads every check row (the rows that are not
required too), merges, reads the stations' reports for the merge, and moves the job to the Done line of § 3.

- Golden in a job's folder, where the work is not committed, is `tools/golden.sh HEAD`. `GOLDEN_FIELDS=1` compares
  the fixed field list, for a change that only gave the snapshot or the record a key.
- A job's folder moves onto a newer main with a throwaway commit: commit the files, `git rebase origin/main`,
  `git reset -q origin/main`, then `FORCE_IMPORT=1 tools/import.sh`. Never a bare `git stash`.
- A bot proof that seats saved heroes runs through `tools/private_save.sh`, so it never meets a real profile.
- Balance is read from groups (§ 2.10) and from the stations' forever jobs, never from one `FULL_RUN` line. The
  pass before the gate build (§ 1) also settles which persona `tools/full_run.gd` and the stations' `boss` job play.
- A pin that moves (`SOLO_PIN`, `CLASSLESS_PIN`) is refreshed only after the one rule that moved it is named and
  shown: switch that rule off and see the old pin pass.
- Part 1 of `docs/content_list.md` is the snapshot of 28 Nov; it is written again from the code at this stage's
  gate.

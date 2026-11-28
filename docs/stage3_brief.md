# Stage 3 brief: build the frozen list

The contract for every stage 3 job. What is built: `docs/content_list.md` part 2 (§ 36 to 54), named here as CL §.
A job reads the sections of this file its prompt names, the CL § of its rows, and nothing else of either file.

## 1. Goal and gate

Build every row of the frozen list, the screens the plan asks for (`docs/release_plan.md`, stage 3) and a speed pass.
The gate: on the owner's four PCs the coverage robot is green for every row that carries a **B** (CL § 36), and
`Upgrades.UNBUILT` is empty (§ 4.3). Numbers are starting values; nobody tunes in stage 3 (that is stage 5).

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

## 3. Order

A job starts when the jobs it needs are on main. `O` is an opus job (game rules), `S` a sonnet job (screens, tools).

**The casting chain, one after another:**

| Job | What | Needs | Owns |
|---|---|---|---|
| A1 `O` | Split `game/logic/world/casting.gd` by cast kind. Nothing changes in play | none | `world/casting.gd`, new `world/cast_bolts.gd`, `cast_chain.gd`, `cast_circles.gd`, `cast_sweep.gd`, the callers |
| A2 `O` | The evolution id (§ 4.1). Nothing changes in play | A1 | `spells.gd`, `upgrades.gd`, `world/cast*.gd`, `entities.gd`, every reader of the flag |
| A3 `O` | The catalog's twelve new rows, the spell + arcana pairs, THE TOWER and JUDGEMENT as held arcana, shut rows (§ 4.2, 4.3), `party_tome_elite` | A2 | `upgrades.gd`, `spells.gd`, `world/levels.gd`, `tuning.gd`, `tarot_art.gd` |
| A4 `O` | The hooks every cast reads (§ 4.5) with THE STAR and THE EMPRESS, and the credit of the arcana of today | A3 | `world/cast*.gd`, `world/enemies.gd` |

**After A4, side by side (one file, one job at a time):**

| Job | Rows | Owns |
|---|---|---|
| C1 `O` | HEX, EVIL EYE, THE DEVIL; the HEXED bit (§ 4.6) | new `world/cast_hex.gd`, `world/enemies.gd` |
| C2 `O` | SPIRIT BLADES, DANSE MACABRE, the ORBIT pickup; spell objects (§ 4.7) | new `world/cast_blades.gd`, `world/players.gd` |
| C3 `O` | LODESTAR, THE HIGH PRIESTESS (the echo queue) | `world/cast_bolts.gd`, `world/casting.gd` |
| C4 `O` | GREEK FIRE, WINTER VEIL; circle kinds FIRE and VEIL (§ 4.7) | `world/cast_circles.gd` |
| C5 `O` | DIES IRAE, WHIRLWIND's change, THE TOWER's refill, JUDGEMENT's blast | `world/cast_chain.gd`, `world/cast_sweep.gd`, `world/players.gd` after C2 |
| V1 `S` | What C1 to C5 look and sound like; THE SPREAD (CL § 41) | `game/arena/draw_fx.gd`, `draw_enemies.gd`, `events.gd`, new `game/ui/spread.gd` |

**Beside the casting chain, from the first day:**

| Job | What | Owns |
|---|---|---|
| T1 `O` | Use counters, a row dealt by force, the coverage robot (§ 4.4) | `results.gd`, new `world/grants.gd`, `tests/bot/`, new `tools/coverage.gd`, `tools/check_all.sh` |
| T2 `S` | The damage table measures a support spell (CL § 52, 53) | `tools/spell_dps.gd` |
| P1 `O` | The profile: shop rows and their gates, the unlock track by key, save version 3 (§ 4.9) | `profile.gd`, `hero.gd` |
| P2 `O` | The satchel, keepsakes, provisions, KEEP on the results screen | `profile.gd` after P1, `loot.gd`, `world/drops.gd` |
| D1 `O` | The eleven deeds (CL § 50); needs A3, P2 and B1 | `achievements.gd`, `profile.gd` after P2 |
| P3 `S` | The shop's three shelves and counter, the satchel screen | `game/sanctum/sanctum_view.gd`, `sanctum.gd`, new `game/ui/satchel.gd` |
| R1 `O` | `Readings`: the sixteen rows, the deal, the vote, the values path (§ 4.8) | new `readings.gd`, `seals.gd`, `world.gd` (`apply_reading`) |
| R2 `O` | The Readings whose rule is new behaviour; the ladder's new numbers; Seal keys `omen` and `boss_fate` | `world/waves.gd`, `world/shrines.gd`, `world/drops.gd` after P2 |
| R3 `S` | The Reading at the table: the deal, the vote, the card on the HUD | `game/ui/title.gd` (lobby part), `game/arena/hud.gd` |
| B1 `O` | Boss rewards at each phase, Overtime, the Daily Draw | `bosses.gd`, `world/waves.gd` after R2, `results.gd` after T1 |
| B2 `O` | Class level 5 (CL § 47) | `classes.gd`, `world/players.gd` after C5 |
| B3 `S` | Ten monster cards and four card stats (CL § 48) | `cards.gd`, `loot.gd` after P2 |
| U1 `S` | Compact trays; nobody stands hidden under the HUD; a marker for every wizard off screen, fallen or apprentice | `game/arena/tray.gd`, `tray_art.gd`, `hud.gd` before R3 |
| U2 `O` | A party that stays seated between runs: the hub and "play again" for two to four | `game/ui/title.gd` before R3, `game/sanctum/sanctum_view.gd` before P3, `arena.gd`, `net.gd` |
| U3 `S` | Options: vsync and a frame cap, a flash option, fill the screen, F11 and Alt+Enter, reset the save | `settings.gd`, `game/ui/options_panel.gd`, `g.gd`, `main.gd` |
| U4 `S` | The missing sounds, audio buses with a limiter, the boss roar never stolen | `sfx.gd`, `tools/gen_audio.py`, `game/arena/events.gd` before V1 |
| U5 `S` | A first run that teaches: revive, redraw and banish, shrines, the first evolution | `game/arena/fate_view.gd`, new `game/logic/lessons.gd` |
| U6 `O` | The team shrine the whole table pays into | `gamble.gd`, `world/shrines.gd` before R2 |
| U7 `S` | Button pictures for each kind of pad | `game/input/player_input.gd`, new `game/ui/glyphs.gd` |
| S1 `O` | The speed pass: the step, the snapshot, drawing a crowd (skill `measure-fix-loop`) | named when it starts |

"Before" and "after" in the Owns column are the order two jobs take one file. A job may add its own fields to
`world.gd`, `entities.gd` and `tuning.gd` and its own tests; it changes nothing else there. The lead owns
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
- THE TOWER (`nova`, index 6) and JUDGEMENT (`life`, index 7) become PASSIVE rows that take an arcana slot: 3 levels
  with weight 5, words NOVAS REFILL; 2 levels with weight 4, words +1 LIFE, BLAST. Their charge and life at the
  pick stay; the refill and the blast are C5's. The kind INSTANT keeps its number and has no rows.
- `Spells.COUNT` is 11. A3 adds the data rows of HEX (cast kind `"hex"`) and SPIRIT BLADES (`"blades"`) and of the
  six new evolutions with the CL numbers; the job that builds a row may add keys to its own row.

### 4.3 Shut rows (A3)

Three things keep a row out of a hand, and all three use the path a banish uses (`Upgrades.available`'s `banned`):

- **Banished** by the wizard for the run: `Player.banned`, as built.
- **Locked** for the table: the host's profile has not opened it (CL § 44). `World.locked` is the table's mask
  (Upgrades index -> true), set at the start of a run from `World.apply_meta`'s `"locked"` (an Array of indices;
  absent: nothing is locked, as in every scripted run). Each wizard's `banned` gets the mask without her own class
  weapon, its arcana and its evolution. `snapshot()["lk"]` carries the mask (a `PackedInt32Array`), so every seat's
  chart is the same. P1 fills `"locked"` from the profile; until then it is absent.
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
- The coverage robot: `tools/check_all.sh` gains shards that run the real arena headless, deal one row by force
  (`--deal=<key>`), play, and fail on an engine error or a row that was never credited. One line a row:
  `COVER <key> ok uses=N` or `COVER <key> FAIL <why>`. It reads its rows from the catalog and the data tables, so a
  new row is covered without a list being edited; it skips `UNBUILT`.

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

- `Readings.ROWS`: `[key, name, words, party only, values]` in CL § 42's order. `Readings.deal(rng, open, seats, n)
  -> Array[String]`, `Readings.vote(votes, seats) -> int` (seat 1 breaks a tie, a missing vote abstains),
  `Readings.values(key) -> Dictionary`.
- `World.apply_reading(key)` runs after `apply_seal`: a value both name multiplies (`hp`, `horde`, `boss`, `speed`,
  `potions`) or adds (`hearts`); a Reading's own keys set World fields named `read_<key>`. `World.reading` holds
  the key ("" for none) and the header carries its index (`W_READING`, -1 for none).
- The ladder's numbers change in `Seals` only (`ARCHMAGE`, `PER_SEAL`, `START_UNLOCKED`, the new keys `omen` and
  `boss_fate`): CL § 43.

### 4.9 The profile (P1, P2)

- `Profile.META` gains nine rows after the six of today, in CL § 45's order: `redraw`, `banish`, `start_level`,
  `satchel`, `favour`, `respec`, `deck_hex`, `deck_blades`, `deck_priestess`. `Profile.level_open(key, level) -> bool`
  holds the Seal wins that open a level.
- `Profile.opened() -> Dictionary`: every content key open to this profile (catalog keys, Reading keys, class and
  race names, `overtime`, `daily`), from its deeds, its decks, its wins and its saved heroes.
  `Profile.locked_rows() -> Array[int]` is the catalog's rest, found by key (a key the catalog does not hold yet is
  skipped), handed to `World.apply_meta` as `"locked"`.
- `Hero.pockets: Array` (each `{"kind": "armor" or "prov", "key", "tier"}`) and `Hero.keepsake: String`;
  `Profile.keepsakes: Array`. Pockets a hero has: 1 + the level of `satchel`.
- The save is version 3. A version 2 save opens everything its record proves (CL § 44) and loses nothing; a damaged
  or newer save is handled as today.

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

## 5. What the lead does at each landing

Reads the diff and every picture, runs the job's tests, lint and (where § 2.6 asks) golden, lands with
`tools/land.sh`, reads the stations' reports for the merge, and takes the job's rows off this file's tables when a
whole table is done.

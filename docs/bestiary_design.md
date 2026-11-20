# FOUR OF WANDS: bestiary design

Numbers are starting values for `Tuning`. "Fixed" speeds are brain constants, never scaled; neither is any warning. Every warning obeys `warn >= 0.3 + (r + 4) / 71` (r = radius or half-width), checked by a unit test.

THE BONE CHANDELIER replaces Morvane's 5:00 fight and THE GHOST WRITER his 10:00 fight. He appears as MORVANE WATCHES (7:00, 12:00) and fights once, at 15:00.

## 1. Enemies

hp and speed before minute scaling. Caps +1 with 3 or 4 wizards.

| Kind | Act | Unlock | hp/spd/r/contact/xp | W I/II/III | Group | Cap | Sprite: frames |
|---|---|---|---|---|---|---|---|
| BLOAT | I | 1:30 | 6/30/7/0/2 | 1/1/1 | 1-2 | 6 | 16x16: walk 2, burst 3 |
| RESTLESS COFFIN | I | 2:00 | 10/0/8/0/4 | 1/1/0 | 1 | 3 | 14x20: shut 1, cracked 2, open 2 |
| TOMB GUARD | I | 3:30 | 10/26/7/1/3 | 1/1/0 | 2-3 | 6 | 16x20: front, side, back x2 |
| CINDERLING | II | 5:30 | 4/70/5/1/2 | 0/2/1 | 1-2 | 3 | 12x12: run 2, kindle 1 |
| THE CENSOR | II | 6:00 | 9/24/6/1/4 | 0/2/0 | 1-2 | 3 | 14x20: walk 2, throw 1, panic 1 |
| ASH HOUND | II | 7:30 | 4/70/5/1/2 | 0/1/1 | 3 | 6 | 16x11: run 2, prowl 1, howl 1 |
| COMET SHARD | III | 11:00 | 22/0/8/1/6 | 0/0/1 | 1 | 2 | 14x20: idle 2, charge 1 |
| TEN OF SWORDS | III | 12:30 | 16/36/6/1/6 | 0/0/2 | 1-3 | 4 | 16x18: walk 2, kneel 1 |

Old kinds: GOBLIN 2/1/1, BAT 1/1/1, SLIME 1/1/0, SKELETON 1/1/0, ORC 1/1/1, MAGE 1/1/1, WRAITH 0/0/2, TOME 0/2/1, PRIEST 0/1/1, GARGOYLE 0/0/1.

**BLOAT**, a bomb that hurts everyone. Walks at the nearest wizard and pops itself within 16 px. On death the body leaves the list and a BLAST disc r 30 warns 0.9 s, then deals 1 heart to wizards and 6 x the minute's hp scale and a 120 px/s shove to enemies, credited to the killer; chains. Frost-slowed: no blast. Needs: enemy-hurting BLAST, `on_death`.

**RESTLESS COFFIN**, break it or it hatches. Rises 70 to 130 px from the party's centre, 60 px from every wizard. Shut 4.0 s, rattling 2.0 s, then 3 skeletons (4 from 10:00) and it despawns. Broken: XP and a gem. Tell: rift mark, seam light, edge arrow off screen. Needs: F_ANCHORED, despawn, form RISE, F_ARROW.

**TOMB GUARD**, only its back can be hurt. Facing turns to the nearest wizard at 1.2 rad/s. A hit whose knock comes from within 70 degrees of the facing does nothing (spark); zero knock, the nova and hazards pass; piercing shots fly on. Tell: the view. Needs: `filter_damage`, facing quadrant in `state`.

**CINDERLING**, cuts the room with fire. Holds 90 to 130 px for 1.5 to 2.5 s; kindles 0.6 s, fixing a 210 px line through the point 30 px ahead of its target; runs it at 190 px/s fixed for 1.1 s. A FLAME line (half-width 5) grows behind it and burns 3.0 s more, 1 heart. Killed kindling: no fire; mid-run: fire stops. Tell: flare and MARK line. Needs: MARK, FLAME, `move_hazard`.

**THE CENSOR**, burns where you stood. Holds 100 to 150 px. Every 4.0 s, if the nearest wizard is 60 to 200 px away: 0.5 s wind-up, then a FIRE disc r 22 at that wizard's feet at release, no lead: warn 1.2 s, hot 3.0 s, 1 heart. A wizard within 60 px makes him panic: no throws, backs off at 1.5x. Needs: FIRE.

**ASH HOUND**, hunts the stray. The pack circles the party's centre at 150 px. Every 0.5 s World names the stray: the wizard farthest from their nearest ally, if over 140 px, never one within 40 px of a grave. Hounds within 260 px howl 0.7 s, then hunt at 125 px/s fixed, turning 1.6 rad/s at most, for 4 s or until the stray is within 60 px of an ally. Solo: prowl 4 s, hunt 3 s. Tell: howl, red eye over the target. Needs: the stray scan.

**COMET SHARD**, a lighthouse to walk around or break. Lands as a FALL disc r 18 (warn 1.2 s, 1 heart) 70 to 120 px from the party, 30 px from wizards, 180 px from other shards; the enemy spawns on landing. After 1.5 s a BEAM line 120 px, half-width 4, warns 1.0 s pointing at the widest wizard-free angle, then stays hot turning 0.6 rad/s (tip 72 px/s). Burns out at 30 s. Needs: FALL with SPAWN, a brain-turned row.

**TEN OF SWORDS**, its death shoots. Trudges at the nearest wizard. On death a BURST disc r 22 kneels 0.7 s (no hearts), then fires a ring of 10 ES_SWORD, 95 px/s, life 2.2 s. Needs: BURST with SHOTS, ES_SWORD.

Formations, one roll in five: POWDER TRAIN 1:30 (8 goblins, 1 bloat, rift), SHIELD WALL 3:30 (3 guards abreast, 3 skeletons, one door), FIRE DRILL 6:30 (2 cinderlings at opposite doors, 1 censor).

## 2. Bosses

Fixed attack order; two wizards aimed at, at most; death clears the field; no F_HAZARD rolls meanwhile.

**THE BONE CHANDELIER (I, 5:00)**, falls on you, then rolls. Base hp 240, r 16; 50 to 70 s casual solo. Phase 1, ALOFT: contact 0, drifts 34 px/s; 1.6 s gaps; DRIP, DROP, RAIN, DROP.
- DRIP: LANE half-width 10 through the party and 160 px past, warn 0.9 s; glides it at 90 px/s, FLAME (half-width 8) behind, hot 4 s.
- DROP: chases the wizard with most allies within 40 px at 80 px/s for 1.4 s under a following BLAST r 44, locks 1.1 s, falls: 2 hearts, 30 to enemies, 12 ES_BONE at 85 px/s. Grounded 3.5 s, contact 1, takes 1.5x.
- RAIN: 3.0 s, every 0.3 s a BLAST r 13 (warn 0.9 s, 1 heart) at a wizard's pos + vel x 0.4 and one near the party.

At 50%, THE CHAIN SNAPS: BLAST r 50, warn 1.3 s, 2 hearts. Phase 2, THE WHEEL: contact 2, 1.2 s gaps; ROLL, RAIN, ROLL, LAST CANDLE, HOP.
- ROLL: LANE half-width 18 to the wall past the farthest wizard, warn 0.8 s; three legs at 170 px/s reflecting off walls, 0.8 s squash and a new lane at each; FLAME per leg, hot 3 s; tramples enemies for 30; then dizzy 2.5 s at 1.5x.
- LAST CANDLE: a SAFE disc r 40 warns 3.5 s; everyone outside takes 2 hearts. On a downed wizard's grave if all living wizards are within 150 px of it, else 60 px from the party away from the boss; never over 150 px from any wizard.
- HOP: DROP unchained: track 0.9 s, lock 1.0 s, r 40, grounded 2.5 s.

Sprite: aloft 48x40 (sway 2, dark 1), grounded 52x30 (1), wheel 40x40 (2); aloft art draws 24 px above `pos`, 60% alpha over a wizard.

**THE GHOST WRITER (II, 10:00)**, a planchette that spells each attack first. Base hp 260, r 14; 70 to 90 s. Between words she glides (150 px/s, contact 0) to 70 to 110 px from the party. A letter every 0.32 s (0.24 s in phase 2); rows appear on the first letter, warn = spelling + 0.3 s. Header: word, `boss_t`, named slot in `boss_arg`. Phase 1: FIRE, NAME, SHELF, ERRATA, NAME.
- F-I-R-E: LANE half-width 12 through the farthest wizard, wall to wall; she glides it at 190 px/s, contact 2, FLAME behind, hot 5 s.
- NAME (in the wizard's colour): a BLAST r 30 follows them, locks 0.9 s before landing, 1 heart, leaves FIRE r 22 for 5 s.
- S-H-E-L-F: ten vertical lanes 76 px wide; odd lanes hot 0.6 s, then even lanes (warn 1.3 s) hot 0.6 s; 1 heart.
- E-R-R-A-T-A: 6 tomes (8 with 3 or 4 wizards).

Phase 2 at 50%: NAME+FIRE, SHELF+NAME (no rest), GOODBYE, ERRATA; two names with 3 or 4 wizards.
- G-O-O-D-B-Y-E: 0.5 s a letter; she stands and takes 1.5x. Deal 6% of her hp first and she stops at G-O-O-D, staggers 3 s, drops a potion once. Else three rings of 16 ES_SKULL at 80 px/s, 0.5 s apart. `boss_meter` shows the 6%.

Sprite: planchette 34x30 (idle 1, gaze 2, blink 1, stagger 1), hand 28x22 (2).

**MORVANE WATCHES (7:00, 12:00).** Not `World.boss`. His shade stays 16 s, casting the spiral (7:00) or volleys (12:00). A ward of 150 or 400 x PARTY_HP in `boss_meter`; broken, it gives an elite-luck chest and takes 6% off the final (cracks in its bar).

**THE ARCHLICH (15:00).** Base hp 676 (3,990 solo, 7x not 10x); 120 to 150 s casual duo.
1. LICH LORD, 100% to 75%: today's calm set.
2. THE ASCENSION, 3 s: field cleared, wizards heal 2. ASCENDANT, to 35%: today's enraged set; COMETFALL every third attack (3 BLAST r 30, warn 1.4 s, 2 hearts, leaving FIRE); THE DEALT HAND every 25 s: three cards turn 1.2 s apart, each acting 1.0 s later: TOWER 3 (RAIN), DEATH 3 (18 skulls), DEVIL 2 (the only elite), MOON 2 (6 wraiths), SUN 1 (heal 1), FOOL 1 (he staggers 2.5 s). `boss_arg` = c1 + 8 c2 + 64 c3.
3. THE NINTH PAGE at 35% (2.5 s turn, floor dims 40%): phase 2 plus a NAME every 4th attack and LAST CANDLE every 30 s.

## 3. Shared core

No wizard statuses: every telegraph assumes full walking speed.

**`game/logic/hazards.gd`**, a leaf (no `World`):

```gdscript
class_name Hazards
const FLOATS := 10  # "hz" row: id, kind, x, y, x2, y2, r, warn_left, warn_total, hot_left
const CAP := 48; const CAP_REGULAR := 32; const WARN_BUDGET := 6; const WARN_RANGE := 260.0
enum { MARK, BLAST, FIRE, FLAME, FALL, BEAM, BURST, LANE, SAFE }
# KINDS: [shape DISC|LINE, hearts, on_hot NONE|BLAST|SHOTS|SPAWN, foe_dmg, foe_shove, inverted, bots_avoid]
class Hazard:
	var id := 0; var kind := 0; var a := Vector2.ZERO; var b := Vector2.ZERO; var r := 12.0
	var warn := 0.8; var warn0 := 0.8; var hot := 0.15; var slot := -1; var owner := 0
	var follow := -1; var lock := 0.0; var aux := 0; var boss := false
static func min_warn(r: float) -> float
static func contains(h: Hazard, p: Vector2) -> bool
static func can_add(rows: Array[Hazard], party: Vector2, boss: bool, forced: bool) -> bool
static func tick(rows: Array[Hazard], dt: float, wizards: Dictionary) -> Array[Hazard]  # newly hot
static func pack(rows: Array[Hazard]) -> PackedFloat32Array
static func steer(hz: PackedFloat32Array, me: Vector2, speed: float, react: float) -> Vector2
static func goal(hz: PackedFloat32Array) -> Vector2  # SAFE centre or Vector2.INF
```

World gets `add_hazard(kind, a, b, r, warn, hot, slot := -1, owner := 0, forced := false) -> Hazard`, `move_hazard(h, a, b)` and `_update_hazards(dt)` between enemies and shots: hot rows `hurt_player`, on_hot runs once, an owner dying in the warning removes its row, the nova clears regular rows within 150 px. Look: bone-white dashed rim, `c0263a` fill growing to it, SAFE in gold, floor layer; 40 draw calls at most.

**`game/logic/bestiary.gd`:** ids appended and reserved in the core commit; `KINDS` `[key, hp, spd, r, score, contact, xp, heft, flags]`, flags `F_NO_SEP, F_ANCHORED, F_BOSS, F_HAZARD, F_FIXED_SPEED, F_ARROW`; `HORDE` `[type, cost, unlock_s, w1, w2, w3, gmin, gmax, extra_per_min, cap, form]`, form GROUP, RISE or WALL; `FORMATIONS` `[name, unlock_s, weight, [[type, n], ...], layout]`.

```gdscript
static func roll_group(rng: RandomNumberGenerator, t: float, act: int, alive: PackedInt32Array, wizards: int, boss_alive: bool) -> Array
```

`Enemy` gains `flags` and `cloak`; `alive` per type is rebuilt in `_build_grid`. `Brains.think(w, e, dt, tgt, dirv, dist) -> Vector2`, `on_death(w, e, slot) -> bool`, `filter_damage(w, e, dmg, knock, sure) -> float`.

**`game/logic/bosses.gd`:** any F_BOSS type can be a boss.

```gdscript
const SCHEDULE: Array = [[300.0, Bestiary.CHANDELIER, false], [600.0, Bestiary.GHOSTWRITER, false], [900.0, Bestiary.LICH, true]]
const VISITS: Array = [[420.0, 150.0], [720.0, 400.0]]  # second, ward base
const PARTY_HP: Array = [1.0, 1.6, 2.2, 2.8]
static func due(prev_t: float, t: float) -> int
static func health(type: int, wave: int, wizards: int, seal_mul: float, wounds: float) -> float
static func phase(type: int, hp_frac: float) -> int
```

One file per boss: `think` and `const ATTACKS` rows `[state, warn, hazard kind, r]`. World: `_spawn_boss(type, final)`, `_boss_died(e, slot)`, `phase_turn(e, secs)`. Header `"w"` gains `boss_type, boss_phase, boss_t, boss_arg, boss_meter`. Enemy shots cap at 300.

## 4. Build order

| Step | Items (size) |
|---|---|
| 1 Core | hash trace tool (S); Bestiary/Brains move and Lich on Bosses with identical traces (L); hazards, `"hz"`, header, drawing, fair-walk test (M); director columns, `steer`/`goal`, shot cap, placeholders, mixed `sim_horde` probe (M) |
| 2 Job K | BLOAT, COFFIN, CENSOR, SWORDS (S); CINDERLING, SHARD, HOUND, GUARD (M); act weights (S, own commit) |
| 3 Job L | CHANDELIER (L), GHOST WRITER (L), Archlich phases (M), DEALT HAND (M), WATCHES (S), schedule switch (S, last) |

Steps 2 and 3 run in parallel. Cut first, in order: TOMB GUARD, ASH HOUND, THE DEALT HAND, MORVANE WATCHES, TEN OF SWORDS, THE GHOST WRITER (the Lich keeps 10:00).

## 5. Jobs

### Job K: enemies

Goal: the 8 kinds of section 1 of `bestiary_design.md`.
Rules: numbers in `Bestiary`/`Tuning` rows; fixed speeds are brain constants. Use only `add_hazard`, `move_hazard`, `Hazards.*`, `eshot`, `damage_enemy`, `spawn_enemy`; edit no line of `world.gd` or `brains.gd`. Warnings pass `min_warn`. Build BLOAT, COFFIN, CINDERLING, CENSOR, SHARD first, then SWORDS, HOUND, GUARD.
Files: `game/logic/kinds_crypt.gd` (bloat, coffin, guard), `kinds_library.gd` (cinderling, censor, hound), `kinds_sanctum.gd` (shard, swords); your rows in `bestiary.gd`, `enemy_view.gd`, `cards.gd`; formations, act weights.
Tests (`tests/unit/test_kinds_*.gd`): bloat chain and credit; coffin hatches at 6.0 s, drops nothing; cinderling killed kindling leaves no row; censor aims at the release point, panics inside 60 px; hound never picks a reviver; shard turns 0.6 rad/s, burns out at 30 s; swords fire 10; guard blocks only from the front; caps hold; no F_HAZARD roll during a boss.

### Job L: act bosses

Goal: THE BONE CHANDELIER, THE GHOST WRITER, MORVANE WATCHES and the three-phase Archlich, per section 2 of `bestiary_design.md`.
Rules: every attack is hazard rows or enemy shots, listed in the file's `ATTACKS`; fixed order; two wizards aimed at, at most; what players must see lives in rows or the header. Use `Bosses`, `phase_turn`, `add_hazard`; do not touch `kinds_*`. Switch `SCHEDULE` last, alone. Cut DEALT HAND, then WATCHES, then the Ghost Writer.
Files: `game/logic/boss_chandelier.gd`, `boss_ghostwriter.gd`, `boss_lich.gd` (final, Watches); `bosses.gd` tables; arena boss bar and spelled words.
Tests (`tests/unit/test_bosses.gd`): `ATTACKS` pass `min_warn`; phase turns at 50%, 75%, 35%; DROP picks the tightest knot; LAST CANDLE within 150 px of every wizard; GOODBYE stops at 6%; each broken ward takes 6%; cards decode from the header; boss death clears hazards.

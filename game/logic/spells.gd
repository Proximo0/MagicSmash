class_name Spells
extends RefCounted
## Spell weapons: per-level stats and the evolutions. Pure data plus lookups; World casts with these numbers.
## A wizard's weapon level lives in their upgrades Dictionary (Upgrades.weapon_entry(spell)); an evolution is
## its own upgrade entry (Upgrades.evo_entry(spell, evo)) that needs the weapon at MAX_LEVEL plus one arcana (a
## PASSIVE row, never another spell: content list § 37). The four schools have a second evolution (EVOS2). CLEAVE
## is the knight's class weapon: only a knight holds it, so only a knight is offered WHIRLWIND.

const COUNT := 11
const MAX_LEVEL := 5

## Per spell (World.SP_* order). Arrays are per level 1..MAX_LEVEL.
## cast: how the spell is cast (WorldCasting.CASTS has one function per kind): "bolt" flies projectiles,
## "chain" strikes lightning foe to foe, "rune" inscribes circles on the floor, "candle" sets a light (a circle of
## kind CIRCLE_CANDLE) on the densest cluster near the caster, "sweep" swings an arc `arc` radians wide reaching
## `r` px. A new kind is one function in a file of its own (world/cast_<kind>.gd), named in that table, plus its
## rows here. cd: seconds between casts. dmg: damage per hit (per tick for a rune circle). n: bolts,
## fireballs, shards, chain jumps, stars or rune circles. speed px/s, r: hit radius px, life: seconds, spread:
## radians between projectiles. A rune circle's r and life are per level too (read them with level_value).
## What a "bolt" does in flight is data too (absent: it does not): jitter: radians of random aim per bolt.
## home: px within which it turns toward the nearest foe, turn: how fast (per second). blast: radius px of the
## burst when it hits or runs out, blast_reach: px over which the burst's bonus fades, blast_bonus: extra damage
## at the centre. slow: seconds a hit enemy stays slowed. pierce: enemies it passes through (PIERCE_ALL: every one).
## "hex" (HEX, unbuilt: Upgrades.UNBUILT) curses the toughest foe within `range` px: dmg on the throw; the foe takes
## `taken` (per level) more damage from every wizard for `life` s, `big_share` of that on an elite or a boss; when
## it dies the hex jumps to the nearest foe within `jump` px, up to n times. "blades" (SPIRIT BLADES, unbuilt) keeps
## n blades circling her at `r` px, one turn each `spin` s, always out: a touch deals dmg and pushes the foe back,
## and one foe is cut at most every `cd` s. speed, life and spread are 0 where a kind has no use for them.
const STATS: Array = [
	{"name": "ARCANE BOLT", "cast": "bolt", "cd": [0.16, 0.15, 0.14, 0.13, 0.12], "dmg": [2.6, 2.75, 2.8, 2.9, 3.0],
		"n": [1, 1, 2, 2, 3], "speed": 310.0, "r": 3.0, "life": 1.0, "spread": 0.12, "jitter": 0.04},
	{"name": "FIREBALL", "cast": "bolt", "cd": [1.2, 1.1, 1.0, 0.9, 0.8], "dmg": [2.2, 2.4, 2.6, 2.8, 3.0],
		"n": [1, 1, 2, 2, 2], "speed": 200.0, "r": 4.5, "life": 1.6, "spread": 0.3,
		"blast": 28.0, "blast_reach": 40.0, "blast_bonus": 1.5},
	{"name": "FROST FAN", "cast": "bolt", "cd": [1.0, 0.95, 0.9, 0.85, 0.8], "dmg": [2.4, 2.65, 2.8, 3.1, 3.5],
		"n": [3, 4, 5, 6, 7], "speed": 255.0, "r": 2.5, "life": 0.75, "spread": 0.17, "slow": 1.8},
	{"name": "CHAIN LIGHTNING", "cast": "chain", "cd": [0.9, 0.8, 0.7, 0.65, 0.6], "dmg": [3.1, 3.45, 3.8, 4.3, 5.0],
		"n": [3, 4, 5, 6, 7], "speed": 0.0, "r": 0.0, "life": 0.0, "spread": 0.0},
	{"name": "STARFALL", "cast": "bolt", "cd": [1.1, 1.0, 0.9, 0.8, 0.7], "dmg": [3.4, 3.55, 3.7, 3.9, 4.2],
		"n": [2, 2, 3, 3, 4], "speed": 175.0, "r": 3.0, "life": 2.2, "spread": 0.45, "home": 160.0, "turn": 5.5},
	{"name": "RUNE CIRCLE", "cast": "rune", "cd": [2.6, 2.4, 2.2, 2.0, 1.8], "dmg": [0.66, 0.8, 0.92, 1.08, 1.25],
		"n": [1, 1, 2, 2, 3], "speed": 0.0, "r": [14.0, 16.0, 18.0, 20.0, 22.0], "life": [2.0, 2.0, 2.25, 2.5, 2.5],
		"spread": 0.0},
	{"name": "BONE SPEAR", "cast": "bolt", "cd": [1.5, 1.4, 1.25, 1.1, 1.0], "dmg": [3.0, 3.5, 4.0, 4.5, 5.0],
		"n": [2, 2, 2, 2, 2], "speed": 275.0, "r": 3.0, "life": 0.8, "spread": 0.3, "pierce": -1},
	{"name": "VIGIL CANDLE", "cast": "candle", "cd": [2.0, 2.0, 2.0, 2.0, 2.0], "dmg": [0.8, 0.85, 0.9, 0.95, 1.0],
		"n": [1, 1, 1, 1, 1], "speed": 0.0, "r": 32.0, "life": 3.5, "spread": 0.0},
	{"name": "CLEAVE", "cast": "sweep", "cd": [0.9, 0.85, 0.8, 0.75, 0.7], "dmg": [9.0, 11.0, 13.5, 16.5, 20.0],
		"n": [1, 1, 1, 1, 1], "speed": 0.0, "r": 34.0, "life": 0.0, "spread": 0.0, "arc": 1.745},
	{"name": "HEX", "cast": "hex", "cd": [1.6, 1.45, 1.3, 1.15, 1.0], "dmg": [5.0, 5.5, 6.0, 6.5, 7.0],
		"n": [2, 3, 4, 5, 6], "speed": 0.0, "r": 0.0, "life": 4.0, "spread": 0.0, "range": 160.0,
		"taken": [0.25, 0.30, 0.35, 0.40, 0.45], "big_share": 0.5, "jump": 70.0},
	{"name": "SPIRIT BLADES", "cast": "blades", "cd": [0.5, 0.5, 0.5, 0.5, 0.5], "dmg": [1.2, 1.45, 1.7, 1.95, 2.2],
		"n": [2, 2, 3, 3, 4], "speed": 0.0, "r": 30.0, "life": 0.0, "spread": 0.0, "spin": 1.6},
]

## First evolutions (id 1), per base spell. passive: the Upgrades key of the arcana it pairs with (the catalog's
## `requires` holds the pair; content list § 37). The stats replace the level-5 numbers. pierce: extra enemies a projectile passes through. Specials (World reads them):
## chain: lightning jumps from each fireball blast. chains: separate lightning chains per cast.
## slow: seconds an enemy stays slowed. burst: radius of a frost burst where a star hits.
## r, life: a rune circle's radius and seconds. pull: px/s a circle draws enemies toward its centre.
## splinter: splinters a hit throws sideways (Ossuary Lance). heal_every: s between the hearts the light gives the
## most hurt hero inside (Consecration). r, arc: a sweep's reach px and width radians (Whirlwind: TAU, a full
## circle); most: the foes one swing strikes at most, the nearest first. EVIL EYE (unbuilt): `taken` the hex's
## damage taken, n jumps; a hexed foe bursts when it dies for `burst_share` of its full health within `burst_r` px,
## at most `burst_max`. DANSE MACABRE (unbuilt): n blades at `r` px and `n2` more at `r2` px turning the other way.
## An empty row: the spell has no evolution.
const EVOS: Array = [
	{"name": "ASTRAL LANCE", "desc": "PIERCING BOLTS", "passive": "quick",
		"cd": 0.11, "dmg": 3.0, "n": 3, "pierce": 2},
	{"name": "THUNDERFIRE", "desc": "ZAPPING BLASTS", "passive": "nova",
		"cd": 0.9, "dmg": 3.0, "n": 3, "chain": 3},
	{"name": "BLIZZARD", "desc": "A STORM OF ICE", "passive": "regen",
		"cd": 0.7, "dmg": 3.2, "n": 9, "pierce": 1, "slow": 3.5},
	{"name": "TEMPEST", "desc": "TWIN CHAINS", "passive": "swift",
		"cd": 0.5, "dmg": 4.4, "n": 9, "chains": 2},
	{"name": "COMET RAIN", "desc": "ICY STARBURSTS", "passive": "wisdom",
		"cd": 0.6, "dmg": 3.0, "n": 5, "burst": 30.0},
	{"name": "SEAL OF SOLOMON", "desc": "SIGILS PULL IN", "passive": "magnet",
		"cd": 1.4, "dmg": 1.0, "n": 3, "r": 32.0, "life": 3.5, "pull": 42.0},
	{"name": "OSSUARY LANCE", "desc": "SPLINTER HITS", "passive": "justice",
		"cd": 0.9, "dmg": 5.5, "n": 3, "splinter": 2},
	{"name": "CONSECRATION", "desc": "HEALING LIGHT", "passive": "lovers",
		"cd": 1.8, "dmg": 1.8, "n": 2, "r": 32.0, "life": 3.5, "heal_every": 10.0},
	{"name": "WHIRLWIND", "desc": "A FULL CIRCLE", "passive": "power",
		"cd": 0.55, "dmg": 36.0, "n": 1, "r": 60.0, "arc": TAU, "most": 3},
	{"name": "EVIL EYE", "desc": "HEXED BURST", "passive": "devil",
		"cd": 0.9, "dmg": 8.0, "n": 6, "taken": 0.5, "burst_share": 0.5, "burst_r": 26.0, "burst_max": 40.0},
	{"name": "DANSE MACABRE", "desc": "A SECOND RING", "passive": "empress",
		"cd": 0.5, "dmg": 3.0, "n": 4, "r": 30.0, "n2": 4, "r2": 52.0},
]

## Second evolutions, per base spell (evolution id 2; EVOS is id 1): the same row shape as EVOS, `{}` for a spell
## that has none. Read a row of either through evo_row. All four are unbuilt (Upgrades.UNBUILT). LODESTAR: bolts
## turn after the toughest foe within `hunt` px and deal `big_mul` times to elites and bosses. GREEK FIRE: each
## blast leaves a burning patch of `patch_r` px for `patch_life` s that ticks `patch_dmg` each `patch_tick` s.
## WINTER VEIL: the fan keeps its level 5 numbers (cd, dmg, n copied from STATS), and a mist of `veil_r` px stays on
## her: foes in it are slowed as by the fan and take `veil_dmg` each `veil_tick` s. DIES IRAE: jumps keep `falloff`
## of their damage (no weakening), and a plain foe a jump leaves under `slay` of its health dies.
const EVOS2: Array = [
	{"name": "LODESTAR", "desc": "HUNTS BIG PREY", "passive": "star",
		"cd": 0.12, "dmg": 3.0, "n": 3, "hunt": 160.0, "big_mul": 2.0},
	{"name": "GREEK FIRE", "desc": "BURNING GROUND", "passive": "power",
		"cd": 0.8, "dmg": 3.0, "n": 2, "patch_r": 28.0, "patch_life": 3.0, "patch_dmg": 1.2, "patch_tick": 0.5},
	{"name": "WINTER VEIL", "desc": "CLOAK OF FROST", "passive": "priestess",
		"cd": 0.8, "dmg": 3.5, "n": 7, "veil_r": 40.0, "veil_dmg": 1.6, "veil_tick": 0.5},
	{"name": "DIES IRAE", "desc": "SLAYS THE WEAK", "passive": "life",
		"cd": 0.6, "dmg": 5.0, "n": 7, "falloff": 1.0, "slay": 0.2},
	{}, {}, {}, {}, {}, {}, {},
]

## Slow applied by a frost shard that has not evolved (its row's "slow"), and by Comet Rain's burst, seconds.
const FROST_SLOW := 1.8
## The least a wizard's cast-rate bonuses (THE MAGICIAN, haste, focus) leave of a cooldown.
const CAST_FLOOR := 0.35
## Knock-back of a bolt's hit and of a blast, px/s.
const BOLT_KNOCK := 70.0
const BLAST_KNOCK := 160.0
## Range of an un-evolved chain lightning's first jump and later jumps, px; Tempest adds TEMPEST_RANGE_MUL.
const CHAIN_FIRST_RANGE := 140.0
const CHAIN_JUMP_RANGE := 70.0
const TEMPEST_RANGE_MUL := 1.5
## Share of a star's damage that Comet Rain's frost burst deals to each other enemy in its radius.
const BURST_DMG := 0.3
## Damage kept on each further chain jump.
const CHAIN_FALLOFF := 0.85
## Rune circles: seconds between damage ticks, seconds from inscription to the first tick, how far from the
## wizard (px) a circle may be inscribed, how far ahead along the aim one goes when no enemy is in range, how
## far apart (in radii) one cast's circles keep, and how far beyond its radius (as a multiple) the Seal pulls.
const RUNE_TICK := 0.5
const RUNE_ARM := 0.2
const RUNE_RANGE := 150.0
const RUNE_AIM_DIST := 48.0
const RUNE_SPACING := 1.5
const SEAL_REACH := 1.6
## A homing shot looks for its target within HOME_RING px first, then HOME_RING_GROW times as far a try up to its
## `home` reach; a ring's last HOME_RING_SLACK px do not count (WorldCastBolts._homing_target).
const HOME_RING := 48.0
const HOME_RING_GROW := 2.0
const HOME_RING_SLACK := 16.0
## A bolt row's pierce that never runs out (BONE SPEAR).
const PIERCE_ALL := -1
## Ossuary Lance: a splinter's share of its spear's damage and its seconds of flight (it flies at the spear's speed).
const SPLINTER_DMG := 0.5
const SPLINTER_LIFE := 0.3
## Circle kinds (World.Rune.kind, the snapshot's R_KIND): the rune circle and the vigil candle's light.
const CIRCLE_RUNE := 0
const CIRCLE_CANDLE := 1
## Vigil candle: how far from the caster (px) a light may be set, how far along the aim one goes when no enemy is
## that near, the cast speed a hero who stood in a light keeps (added to her other cast-speed bonuses) and for how
## many seconds after leaving it.
const CANDLE_RANGE := 60.0
const CANDLE_AIM_DIST := 30.0
const VIGIL_HASTE := 0.2
const VIGIL_AFTER := 2.0
## Cleave: knock-back of the sweep, px/s.
const SWEEP_KNOCK := 120.0
## Shot kinds (World.Shot.kind, what clients draw) come in blocks of SHOT_BLOCK spells: a block's plain kinds, then
## the same spells evolved. The first six spells' kinds are what they always were (spell, spell + 6 evolved).
## A second evolution's kind is SHOT_SECOND + spell, past every block of today.
const SHOT_BLOCK := 6
const SHOT_SECOND := 24
## An event's b that carries a caster's slot (EV_RUNE, EV_SWEEP): the slot in the low bits (EVO_SLOT_MASK), plus
## EVO_BIT_EVOLVED when evolved and EVO_BIT_SECOND more for evolution id 2 (evo_bits).
const EVO_SLOT_MASK := 3
const EVO_BIT_SECOND := 4
const EVO_BIT_EVOLVED := 8


static func spell_name(spell: int) -> String:
	return STATS[spell]["name"]


## How the spell is cast: a key of Spells.STATS "cast" (WorldCasting.CASTS; a kind with no caster yet casts nothing).
static func cast_kind(spell: int) -> String:
	return STATS[spell]["cast"]


## The row of evolution `evo` of `spell` (1: EVOS, 2: EVOS2), or `{}` for 0, an unknown id or no such evolution.
static func evo_row(spell: int, evo: int) -> Dictionary:
	match evo:
		1:
			return EVOS[spell]
		2:
			return EVOS2[spell]
	return {}


## How many evolutions `spell` has (its rows in EVOS and EVOS2 that are not empty).
static func evolutions(spell: int) -> int:
	return (1 if not EVOS[spell].is_empty() else 0) + (1 if not EVOS2[spell].is_empty() else 0)


## A bolt behaviour of the spell's row (jitter, home, turn, blast, blast_reach, blast_bonus, slow), or `none`
## when its bolts do not do that. Evolution `evo`'s own value wins when it has one.
static func bolt_value(spell: int, key: String, evo: int, none: float) -> float:
	if evo > 0:
		var row := evo_row(spell, evo)
		if row.has(key):
			return float(row[key])
	return float(STATS[spell].get(key, none))


static func _at(spell: int, key: String, level: int) -> float:
	var vals: Array = STATS[spell][key]
	return float(vals[clampi(level, 1, MAX_LEVEL) - 1])


## Seconds between casts at `level` (1..MAX_LEVEL), or evolution `evo`'s (0: none). damage and count alike.
static func cooldown(spell: int, level: int, evo: int) -> float:
	if evo > 0:
		return float(evo_row(spell, evo)["cd"])
	return _at(spell, "cd", level)


static func damage(spell: int, level: int, evo: int) -> float:
	if evo > 0:
		return float(evo_row(spell, evo)["dmg"])
	return _at(spell, "dmg", level)


static func count(spell: int, level: int, evo: int) -> int:
	if evo > 0:
		return int(evo_row(spell, evo)["n"])
	return int(_at(spell, "n", level))


## A number from STATS that does not change with level (speed, r, life, spread). Not for a rune circle's r and
## life, which change with level: use level_value.
static func stat(spell: int, key: String) -> float:
	return float(STATS[spell][key])


## A stat that may vary by level (an Array in STATS) or be one number; evolution `evo`'s own value when it has
## one.
static func level_value(spell: int, key: String, level: int, evo: int) -> float:
	if evo > 0:
		var row := evo_row(spell, evo)
		if row.has(key):
			return float(row[key])
	if STATS[spell][key] is Array:
		return _at(spell, key, level)
	return float(STATS[spell][key])


## A special of evolution `evo` (pierce, chain, chains, slow, burst), or `none` when it has no such special or
## `evo` is 0.
static func evo_value(spell: int, key: String, evo: int, none: float) -> float:
	if evo <= 0:
		return none
	return float(evo_row(spell, evo).get(key, none))


## The Upgrades key of the arcana evolution `evo` of `spell` pairs with, or "" when it has no such evolution.
static func passive_partner(spell: int, evo: int = 1) -> String:
	return str(evo_row(spell, evo).get("passive", ""))


## True if `spell` has any evolution (id 1 or 2).
static func has_evolution(spell: int) -> bool:
	return evolutions(spell) > 0


## What a shot of `spell` with evolution `evo` is drawn as (see SHOT_BLOCK, SHOT_SECOND).
static func shot_kind(spell: int, evo: int) -> int:
	if evo == 2:
		return SHOT_SECOND + spell
	return (spell / SHOT_BLOCK) * SHOT_BLOCK * 2 + spell % SHOT_BLOCK + (SHOT_BLOCK if evo > 0 else 0)


## The spell of a shot kind, and its evolution id (shot_kind backwards).
static func shot_spell(kind: int) -> int:
	if kind >= SHOT_SECOND:
		return kind - SHOT_SECOND
	return (kind / (SHOT_BLOCK * 2)) * SHOT_BLOCK + kind % SHOT_BLOCK


static func shot_evo(kind: int) -> int:
	if kind >= SHOT_SECOND:
		return 2
	return 1 if kind % (SHOT_BLOCK * 2) >= SHOT_BLOCK else 0


## The bits an event's b adds to the caster's slot for evolution `evo` (see EVO_BIT_EVOLVED), and back.
static func evo_bits(evo: int) -> int:
	if evo <= 0:
		return 0
	return EVO_BIT_EVOLVED + (EVO_BIT_SECOND if evo == 2 else 0)


static func bits_evo(b: int) -> int:
	if b & EVO_BIT_EVOLVED == 0:
		return 0
	return 2 if b & EVO_BIT_SECOND != 0 else 1

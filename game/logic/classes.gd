class_name Classes
extends RefCounted
## Hero classes (docs/classes_design.md section 4): the role, hearts, weapon, nova-button skill, threat, stats and
## passive of each. Pure data plus accessors; World.apply_hero reads them once at the start of a run. Append new
## classes at the end: a hero's save stores the KEY, the snapshot row and the seats carry the index.

const MAGE := 0
const KNIGHT := 1
const ARCHER := 2
const PRIEST := 3
const PALADIN := 4

## Roles (the lobby's role icons and the apprentice's pick will read them).
const ROLE_DAMAGE := 0
const ROLE_TANK := 1
const ROLE_RANGED := 2
const ROLE_HEALER := 3
const ROLE_SUPPORT := 4
const ROLE_NAMES := ["DAMAGE", "TANK", "RANGED", "HEALER", "TANK AND SUPPORT"]

## The weapon of a class whose weapon follows its school (the mage): Wizards.start_spell(school).
const SCHOOL_WEAPON := -1

## Column indices of ROWS.
const C_KEY := 0
const C_NAME := 1
const C_ROLE := 2
const C_HEARTS := 3
const C_WEAPON := 4 # a World.SP_* row, or SCHOOL_WEAPON
const C_SKIN := 5 # the class weapon's skin: a SKINS key (how it is named and drawn, and what it does differently)
const C_SKILL := 6 # a SKILLS index
const C_THREAT := 7 # how near a hero looks to the horde: distance / threat
const C_STATS := 8 # stat points [MIGHT, FOCUS, SWIFT, VIGOR, WARD, FORTUNE] (Loot.ST_* order)
const C_WALK := 9 # walk speed multiplier
const C_RITUAL := 10 # how fast this hero's rituals raise the fallen (x)
const C_REDRAWS := 11 # extra redraws of the hand a run
const C_AURA_R := 12 # px: heroes this near (her too) get C_AURA_WARD points of WARD; 0 = no aura
const C_AURA_WARD := 13

## [key, name, role, hearts, weapon, skin, skill, threat, stats, walk, ritual, redraws, aura radius, aura ward].
## A class weapon is a skinned entry of a spell row (job C2): the hero holds that spell's own Upgrades entry, so it
## levels and evolves like the row, and C_SKIN names how it differs (SKINS). The class stat points are a first cut
## for the balance gates (job P).
const ROWS: Array = [
	["mage", "MAGE", ROLE_DAMAGE, 5, SCHOOL_WEAPON, "staff", 0, 1.0, [0, 2, 0, 0, 0, 0], 1.0, 1.0, 2, 0.0, 0],
	["knight", "KNIGHT", ROLE_TANK, 7, World.SP_CLEAVE, "cleave", 1, 2.5, [1, 0, 0, 0, 2, 0], 0.94, 1.0, 0, 0.0, 0],
	["archer", "ARCHER", ROLE_RANGED, 4, World.SP_BONE, "longbow", 2, 0.8, [1, 1, 1, 0, 0, 0], 1.08, 1.0, 0, 0.0, 0],
	["priest", "PRIEST", ROLE_HEALER, 5, World.SP_CANDLE, "holy_light", 3, 0.7, [0, 1, 0, 0, 2, 0], 1.0, 2.0, 0, 0.0, 0],
	["paladin", "PALADIN", ROLE_SUPPORT, 6, World.SP_STAR, "smite", 4, 1.6, [1, 0, 0, 0, 1, 0], 1.0, 1.0, 0, 50.0, 8],
]

## Class weapon skins (C_SKIN), by key. name: the weapon's name on its card and the hero screens ("" or absent:
## the spell's own). range: px a bolt flies (in place of the row's speed x life). heal, heal_every: a light (a
## "candle" row) heals the most hurt hero inside it `heal` hearts every `heal_every` s. The arena draws each skin
## its own way (ArenaDrawFx, ArenaDrawWorld, Fx.swing): arrows, hammers of light, a white light with a cross, an arc.
## The mage's "staff" is no skin: her school's spell as it is.
const SKINS: Dictionary = {
	"staff": {},
	"cleave": {"name": "CLEAVE"},
	"longbow": {"name": "LONGBOW", "range": 260.0},
	"holy_light": {"name": "HOLY LIGHT", "heal": 1, "heal_every": 6.0},
	"smite": {"name": "SMITE"},
}

## Skills, fired by the nova button; each spends one nova charge.
const SK_NOVA := 0
const SK_PROVOKE := 1
const SK_VOLLEY := 2
const SK_SANCTUARY := 3
const SK_AEGIS := 4

## One dictionary per skill (SK_* order). NOVA's numbers stay in WorldPlayers._nova as they always were.
## PROVOKE: enemies within radius px want the caster for taunt s; she takes no damage for safe s.
## VOLLEY: a roll of roll px along her movement (safe s unhurt), then arrows fanned over fan radians behind her
## (the class weapon's shots at its level, speed x speed_mul).
## SANCTUARY: every standing hero heals heal hearts; the fallen within radius px rise.
## AEGIS: heroes within radius px take no damage for safe s.
const SKILLS: Array = [
	{"key": "nova", "name": "NOVA"},
	{"key": "provoke", "name": "PROVOKE", "radius": 100.0, "taunt": 5.0, "safe": 2.0},
	{"key": "volley", "name": "VOLLEY", "roll": 50.0, "safe": 0.4, "arrows": 12, "fan": 1.75, "speed_mul": 1.0},
	{"key": "sanctuary", "name": "SANCTUARY", "heal": 2, "radius": 80.0},
	{"key": "aegis", "name": "AEGIS", "radius": 60.0, "safe": 3.0},
]


static func count() -> int:
	return ROWS.size()


static func _cls_row(c: int) -> Array:
	return ROWS[clampi(c, 0, ROWS.size() - 1)]


## The class index of a saved key, -1 when unknown.
static func index_of(key: String) -> int:
	for i: int in range(ROWS.size()):
		if ROWS[i][C_KEY] == key:
			return i
	return -1


static func key(c: int) -> String:
	return _cls_row(c)[C_KEY]


static func class_name_of(c: int) -> String:
	return _cls_row(c)[C_NAME]


static func role(c: int) -> int:
	return int(_cls_row(c)[C_ROLE])


static func hearts(c: int) -> int:
	return int(_cls_row(c)[C_HEARTS])


## The World.SP_* spell the class fights with; a mage's follows her school (a Wizards index).
static func weapon(c: int, school: int = 0) -> int:
	var sp := int(_cls_row(c)[C_WEAPON])
	return Wizards.start_spell(school) if sp == SCHOOL_WEAPON else sp


static func skin(c: int) -> String:
	return _cls_row(c)[C_SKIN]


## The skin that dresses spell `sp` for class `c`: its C_SKIN when `sp` is the class's own weapon, else "" (a
## mage's school spell and every spell a hero picks up later are drawn as they are).
static func weapon_skin(c: int, sp: int) -> String:
	if int(_cls_row(c)[C_WEAPON]) == SCHOOL_WEAPON or int(_cls_row(c)[C_WEAPON]) != sp:
		return ""
	return skin(c)


## A number of skin `sk` (see SKINS), or `none` when it has none (or there is no such skin).
static func skin_value(sk: String, field: String, none: float = 0.0) -> float:
	return float((SKINS.get(sk, {}) as Dictionary).get(field, none))


## The name a level-up card of Upgrades row `idx` shows a hero of class `c`: her class weapon's skin name on its
## spell row (an archer's BONE SPEAR card reads LONGBOW), the row's own name on every other card.
static func card_name(c: int, idx: int) -> String:
	if Upgrades.is_weapon(idx):
		var nm := str((SKINS.get(weapon_skin(c, Upgrades.spell_of(idx)), {}) as Dictionary).get("name", ""))
		if nm != "":
			return nm
	return Upgrades.display_name(idx)


## The class weapon's name: the skin's name, else the spell's (a mage's: her school's spell).
static func weapon_name(c: int, school: int = 0) -> String:
	var nm := str((SKINS.get(skin(c), {}) as Dictionary).get("name", ""))
	return nm if nm != "" else Spells.spell_name(weapon(c, school))


static func skill(c: int) -> int:
	return int(_cls_row(c)[C_SKILL])


static func threat(c: int) -> float:
	return float(_cls_row(c)[C_THREAT])


## Stat points the class adds, in Loot.ST_* order.
static func stat_points(c: int) -> Array:
	return (_cls_row(c)[C_STATS] as Array).duplicate()


static func walk_mul(c: int) -> float:
	return float(_cls_row(c)[C_WALK])


static func ritual_mul(c: int) -> float:
	return float(_cls_row(c)[C_RITUAL])


static func extra_redraws(c: int) -> int:
	return int(_cls_row(c)[C_REDRAWS])


static func aura_radius(c: int) -> float:
	return float(_cls_row(c)[C_AURA_R])


static func aura_ward(c: int) -> int:
	return int(_cls_row(c)[C_AURA_WARD])


static func skill_count() -> int:
	return SKILLS.size()


static func skill_key(s: int) -> String:
	return SKILLS[clampi(s, 0, SKILLS.size() - 1)]["key"]


static func skill_name(s: int) -> String:
	return SKILLS[clampi(s, 0, SKILLS.size() - 1)]["name"]


## A number of skill `s` (see SKILLS), or `default` when it has none.
static func skill_value(s: int, field: String, default: float = 0.0) -> float:
	return float(SKILLS[clampi(s, 0, SKILLS.size() - 1)].get(field, default))

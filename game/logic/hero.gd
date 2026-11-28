class_name Hero
extends RefCounted
## A saved hero (docs/classes_design.md sections 1, 2 and 4): name, race, class, school, look, class level and
## XP, stat points and three card sockets. Pure data plus the rules: the sheet's stats, levelling and the class XP
## a run pays. Profile keeps up to Profile.MAX_HEROES of them; World.apply_hero reads one (its to_dict) at the start
## of a run. The save stores the race and class KEYS (Races, Classes), so the tables can grow.

const MAX_LEVEL := 20
## XP from level L to L + 1 is XP_PER_LEVEL x L; each level past the first pays POINTS_PER_LEVEL stat points.
const XP_PER_LEVEL := 100
const POINTS_PER_LEVEL := 1
## At most this many points in one stat.
const MAX_POINTS := 10
## Class XP a run pays: per whole minute survived, per boss slain, for a won run (before the multiplier).
const XP_PER_MINUTE := 10
const XP_PER_BOSS := 50
const XP_WIN := 150
## What one stat point is worth in Loot.ST_* armour units: MIGHT +2% damage, FOCUS +1% cast speed, SWIFT +1% move
## speed, VIGOR a quarter heart (+1 heart per 4 points), WARD +1% chance to shrug a hit, FORTUNE +3% gold.
const POINT_VALUE := [0.02, 0.01, 0.01, 0.25, 0.01, 0.03]
## FORTUNE also adds this much chest luck per point.
const LUCK_PER_FORTUNE := 0.2
## The look, packed in one int: skin + SKINS x (hair + HAIRS x style).
const SKINS := 4
const HAIRS := 6
const STYLES := 3
const NAME_MAX := 12
const DEFAULT_NAME := "HERO"

var name := DEFAULT_NAME
var race := Races.HUMAN
var cls := Classes.MAGE
var school := 0 # a Wizards index: the mage's spell (ARCANE BOLT, FIREBALL, FROST FAN, CHAIN LIGHTNING)
var look := 0
var level := 1
var xp := 0
var points: Array[int] = [0, 0, 0, 0, 0, 0] # spent stat points, Loot.ST_* order
var sockets: Array[String] = ["", "", ""] # Cards key in the HEAD, BODY and WEAPON sockets ("" for empty)


static func make(r: int, c: int, sch: int = 0, nm: String = DEFAULT_NAME) -> Hero:
	var h := Hero.new()
	h.race = clampi(r, 0, Races.count() - 1)
	h.cls = clampi(c, 0, Classes.count() - 1)
	h.school = clampi(sch, 0, Wizards.count() - 1)
	h.name = clean_name(nm)
	return h


static func clean_name(nm: String) -> String:
	var s := nm.strip_edges().to_upper().left(NAME_MAX)
	return s if not s.is_empty() else DEFAULT_NAME


static func pack_look(skin: int, hair: int, style: int) -> int:
	return clampi(skin, 0, SKINS - 1) + SKINS * (clampi(hair, 0, HAIRS - 1) + HAIRS * clampi(style, 0, STYLES - 1))


func look_skin() -> int:
	return look % SKINS


func look_hair() -> int:
	return (look / SKINS) % HAIRS


func look_style() -> int:
	return look / (SKINS * HAIRS)


## XP from `lv` to the next level.
static func xp_to_next(lv: int) -> int:
	return XP_PER_LEVEL * lv


## Adds class XP and levels up (to MAX_LEVEL; XP past it is dropped). Returns the levels gained.
func add_xp(amount: int) -> int:
	var gained := 0
	if level >= MAX_LEVEL:
		xp = 0
		return 0
	xp += maxi(0, amount)
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		gained += 1
	if level >= MAX_LEVEL:
		xp = 0
	return gained


## The class XP a run pays before any race trait: XP_PER_MINUTE per whole minute survived, XP_PER_BOSS per boss
## slain and XP_WIN for a win, times `mul` (the ladder's crystal multiplier), rounded.
static func class_xp(seconds: float, bosses: int, won: bool, mul: float = 1.0) -> int:
	var base := XP_PER_MINUTE * int(maxf(0.0, seconds) / 60.0) + XP_PER_BOSS * maxi(0, bosses) + (XP_WIN if won else 0)
	return roundi(base * maxf(0.0, mul))


## The class XP a run pays this hero: class_xp with the race's SCHOLAR trait (the HUMAN's +5%).
func run_xp(seconds: float, bosses: int, won: bool, mul: float = 1.0) -> int:
	return class_xp(seconds, bosses, won, mul * (1.0 + Races.trait_amount(race, Races.TR_SCHOLAR)))


func points_spent() -> int:
	var n := 0
	for v: int in points:
		n += v
	return n


## A CLEAN SLATE (Profile.clean_slate): every spent stat point comes back to spend again. Returns how many.
func refund_points() -> int:
	var n := points_spent()
	points.fill(0)
	return n


## Stat points earned in all: POINTS_PER_LEVEL per level past the first.
static func points_for(lv: int) -> int:
	return POINTS_PER_LEVEL * (lv - 1)


## Stat points earned and not spent yet.
func points_left() -> int:
	return maxi(0, points_for(level) - points_spent())


## Spends a point on stat `st` (Loot.ST_*). False when none is left or the stat holds MAX_POINTS.
func spend_point(st: int) -> bool:
	if st < 0 or st >= Loot.STAT_COUNT or points_left() <= 0 or points[st] >= MAX_POINTS:
		return false
	points[st] += 1
	return true


## The sheet's points per stat (Loot.ST_* order): race + class + spent points, before the cards.
func sheet_points() -> Array[int]:
	var rp: Array = Races.stat_points(race)
	var cp: Array = Classes.stat_points(cls)
	var out: Array[int] = []
	for st: int in range(Loot.STAT_COUNT):
		out.append(int(rp[st]) + int(cp[st]) + points[st])
	return out


## Card index in each socket, -1 for empty.
func socket_indices() -> Array[int]:
	var out: Array[int] = []
	for s: int in range(Cards.SOCKETS):
		out.append(Cards.index_of(sockets[s]))
	return out


## The hero's stats in Loot.empty_stats layout (armour units): the sheet points at POINT_VALUE plus the socketed
## cards, each capped by Loot.STAT_CAPS. Armour found in a run adds on top.
func stats() -> Array:
	var out := Cards.socket_stats(socket_indices())
	var pts := sheet_points()
	for st: int in range(Loot.STAT_COUNT):
		out[st] = minf(float(out[st]) + pts[st] * float(POINT_VALUE[st]), float(Loot.STAT_CAPS[st]))
	return out


## Chest luck from FORTUNE.
func luck() -> float:
	return sheet_points()[Loot.ST_GREED] * LUCK_PER_FORTUNE


## The weapon this hero fights with (World.SP_*).
func weapon() -> int:
	return Classes.weapon(cls, school)


func to_dict() -> Dictionary:
	return {"name": name, "race": Races.key(race), "cls": Classes.key(cls), "school": school, "look": look,
		"level": level, "xp": xp, "points": points.duplicate(), "sockets": sockets.duplicate()}


## A hero from saved data. Unknown race or class keys fall back to HUMAN and MAGE; levels, points and the look
## are clamped (points beyond what the level paid are dropped from the last stat back); a card in the wrong
## socket is dropped (Profile also drops cards the player does not own).
static func from_dict(d: Dictionary) -> Hero:
	var h := Hero.new()
	h.name = clean_name(str(d.get("name", DEFAULT_NAME)))
	h.race = maxi(0, Races.index_of(str(d.get("race", ""))))
	h.cls = maxi(0, Classes.index_of(str(d.get("cls", ""))))
	h.school = clampi(int(d.get("school", 0)), 0, Wizards.count() - 1)
	h.look = clampi(int(d.get("look", 0)), 0, SKINS * HAIRS * STYLES - 1)
	h.level = clampi(int(d.get("level", 1)), 1, MAX_LEVEL)
	h.xp = 0 if h.level >= MAX_LEVEL else clampi(int(d.get("xp", 0)), 0, xp_to_next(h.level) - 1)
	var pt: Variant = d.get("points", [])
	if pt is Array:
		for st: int in range(mini((pt as Array).size(), Loot.STAT_COUNT)):
			h.points[st] = clampi(int(pt[st]), 0, MAX_POINTS)
	var st_back := Loot.STAT_COUNT - 1
	while h.points_spent() > points_for(h.level) and st_back >= 0:
		if h.points[st_back] > 0:
			h.points[st_back] -= 1
		else:
			st_back -= 1
	var so: Variant = d.get("sockets", [])
	if so is Array:
		for s: int in range(mini((so as Array).size(), Cards.SOCKETS)):
			var idx: int = Cards.index_of(str(so[s]))
			if idx >= 0 and Cards.socket(idx) == s:
				h.sockets[s] = str(so[s])
	return h


## The developer flag's hero (--hero=<race>,<class>[,<school>]): keys, names or indices, any case. The school is a
## Wizards index or name (VIOLET, CRIMSON...) or its title (ARCANIST...). Null when the race or class is unknown.
static func from_flag(arg: String) -> Hero:
	var parts := arg.to_lower().split(",", false)
	if parts.size() < 2:
		return null
	var rs := parts[0].strip_edges()
	var cs := parts[1].strip_edges()
	var r := _flag_index(rs, Races.count()) if rs.is_valid_int() else Races.index_of(rs)
	var c := _flag_index(cs, Classes.count()) if cs.is_valid_int() else Classes.index_of(cs)
	if r < 0 or c < 0:
		return null
	var sch := 0
	if parts.size() > 2:
		var sk := parts[2].strip_edges()
		sch = int(sk) if sk.is_valid_int() else 0
		for wz: int in range(Wizards.count()):
			if sk == Wizards.wizard_name(wz).to_lower() or sk == Wizards.title(wz).to_lower():
				sch = wz
	return make(r, c, sch)


static func _flag_index(s: String, n: int) -> int:
	return int(s) if int(s) >= 0 and int(s) < n else -1

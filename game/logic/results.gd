class_name Results
extends RefCounted
## The record of one run for the results screen: per-wizard stats, the team's best moments and the awards.
## World notes things as they happen; `to_dict()` travels to clients with the game over event, and the arena
## draws the screen from `from_dict()`. Pure data, no clock: moments carry the run time World passes in.

## Moments: [key, text (%s is the wizard, %v the detail), weight]. Indices travel in the record, so append new
## ones at the end. Higher weights rank first on the screen; ties go to the later moment.
const M_LICH := 0
const M_ARCHLICH := 1
const M_CHEST := 2 # value = Loot tier (legendary and up are noted)
const M_BLESSING := 3
const M_CURSE := 4
const M_JACKPOT := 5
const M_COMBO := 6 # value = combo count
const M_EVOLVE := 7 # value = Upgrades index of the evolution
const M_CARD := 8 # value = Cards index
const M_ACT_BOSS := 9 # value = the act boss's Bestiary type
const MOMENTS: Array = [
	["lich", "%s SLEW THE LICH LORD", 60],
	["archlich", "%s SLEW THE ARCHLICH", 100],
	["chest", "%s FOUND %v", 50],
	["blessing", "%s BLESSED THE PARTY", 70],
	["curse", "%s CURSED THE PARTY", 75],
	["jackpot", "%s HIT THE JACKPOT", 45],
	["combo", "%s CHAINED A %v COMBO", 40],
	["evolve", "%s EVOLVED %v", 30],
	["card", "%s DREW %v", 90],
	["act_boss", "%s SLEW %v", 60],
]
## The act bosses' names on their moment (M_ACT_BOSS), by Bestiary type.
const ACT_BOSS_NAMES := {Bestiary.CHANDELIER: "THE BONE CHANDELIER", Bestiary.GHOSTWRITER: "THE GHOST WRITER"}

## Combos worth a moment, and how many moments the screen shows.
const COMBO_MOMENTS := [100, 200, 400]
const SHOWN_MOMENTS := 4

## Stat keys kept per wizard. Every one starts at 0. deaths counts lives lost; downs counts falls in a party (a
## solo wizard only dies) and revives the fallen this wizard helped raise in a ritual.
const STATS := ["damage", "kills", "elites", "best_combo", "chests", "best_tier", "gold", "bets", "deaths", "level",
	"downs", "revives"]

## Awards: [title, stat, true if the lowest value wins], best first. An award goes only to the wizard who really
## leads its stat; a wizard who leads several shows the first. In a party, anyone left without one is a TEAM PLAYER.
const AWARDS: Array = [
	["MVP", "damage", false],
	["SLAYER", "kills", false],
	["HIGH ROLLER", "bets", false],
	["LUCKY", "best_tier", false],
	["GOLD DIGGER", "gold", false],
	["UNTOUCHABLE", "falls", true],
]
const TEAM_PLAYER := "TEAM PLAYER"

var stats := {} # slot -> {stat key -> number}
var moments: Array = [] # [t, kind, slot, value]
## Damage dealt by source: a World.SP_* spell, or SRC_NOVA / SRC_ORBIT / SRC_JUSTICE. Travels in to_dict() for the results
## screen's damage by spell.
var source_damage := {}
## The same per wizard, for the results screen's damage by spell: slot -> {source -> damage}.
var slot_source_damage := {}
## slot -> true for an apprentice's column (none yet).
var ai := {}
## The party's fates in the order they landed (Gamble.TEAM_OUTCOMES ids). Data only: nothing shows it yet.
var fates: Array[int] = []
## How often each row of the content list was used this run (docs/stage3_brief.md § 4.4): key -> count for the table,
## and seat -> key -> count. World credits a row where its effect lands; the coverage robot reads the counts.
var uses := {}
var uses_by := {}

## Damage sources that are not spells (spells use their World.SP_* index).
const SRC_NOVA := 100
const SRC_ORBIT := 101
const SRC_JUSTICE := 102 # JUSTICE's bursts
## The non-spell sources' names on the damage page.
const SOURCE_NAMES := {SRC_NOVA: "NOVA", SRC_ORBIT: "ORBIT", SRC_JUSTICE: "JUSTICE"}
## The damage page's rows per wizard, and the smallest share (whole percent) worth a row.
const DAMAGE_ROWS := 6
const MIN_SHARE_PCT := 1


func _init(slots: Array = []) -> void:
	for s: int in slots:
		join(s)


## Adds a wizard (a late joiner starts from zero).
func join(slot: int) -> void:
	if stats.has(slot):
		return
	var row := {}
	for k: String in STATS:
		row[k] = 0.0
	stats[slot] = row


func add(slot: int, key: String, amount: float) -> void:
	if stats.has(slot):
		stats[slot][key] = float(stats[slot][key]) + amount


func add_source(src: int, amount: float) -> void:
	source_damage[src] = float(source_damage.get(src, 0.0)) + amount


## Adds damage `slot` dealt with source `src` (a World.SP_* spell, SRC_NOVA or SRC_ORBIT).
func add_slot_source(slot: int, src: int, amount: float) -> void:
	var row: Dictionary = slot_source_damage.get(slot, {})
	row[src] = float(row.get(src, 0.0)) + amount
	slot_source_damage[slot] = row


## Credits `n` uses of the row `key` to the run, and to seat `slot` when it names one (-1: the table's alone). Call it
## at the event (a cast, a proc, a pick-up, a rule that fires), never once an enemy inside a step's loop.
func use(key: String, slot: int = -1, n: int = 1) -> void:
	uses[key] = int(uses.get(key, 0)) + n
	if slot < 0:
		return
	var row: Dictionary = uses_by.get(slot, {})
	row[key] = int(row.get(key, 0)) + n
	uses_by[slot] = row


## Uses of the row `key` this run, by every seat and by the table.
func used(key: String) -> int:
	return int(uses.get(key, 0))


## Uses of the row `key` this run by seat `slot`.
func used_by(slot: int, key: String) -> int:
	return int((uses_by.get(slot, {}) as Dictionary).get(key, 0))


## The sources `slot` dealt damage with, most first: [source, damage, share] with the share in whole percent of her
## damage (rounded down, so the shares add up to at most 100). Ties go to the lower source index; sources under
## MIN_SHARE_PCT are left out; at most `limit` rows. A wizard who dealt no damage has none.
func damage_rows(slot: int, limit: int = DAMAGE_ROWS) -> Array:
	var row: Dictionary = slot_source_damage.get(slot, {})
	var total := 0.0
	var rows: Array = []
	for src: Variant in row:
		var dmg := float(row[src])
		if dmg > 0.0:
			total += dmg
			rows.append([int(src), dmg, 0])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) < int(b[0]) if is_equal_approx(float(a[1]), float(b[1])) else float(a[1]) > float(b[1]))
	var out: Array = []
	for r: Array in rows:
		var pct := int(floor(float(r[1]) / total * 100.0))
		if pct >= MIN_SHARE_PCT and out.size() < limit:
			out.append([int(r[0]), float(r[1]), pct])
	return out


## The name of damage source `src` for a wizard of class `cls`: her class weapon's own name (CLEAVE, LONGBOW),
## another spell's name, or a non-spell source's.
static func source_name(src: int, cls: int) -> String:
	if SOURCE_NAMES.has(src):
		return SOURCE_NAMES[src]
	if src < 0 or src >= Spells.STATS.size():
		return "OTHER"
	if Classes.weapon_skin(cls, src) != "":
		return Classes.weapon_name(cls)
	return Spells.spell_name(src)


## Keeps the larger of the stat and `value`.
func best(slot: int, key: String, value: float) -> void:
	if stats.has(slot):
		stats[slot][key] = maxf(float(stats[slot][key]), value)


func set_stat(slot: int, key: String, value: float) -> void:
	if stats.has(slot):
		stats[slot][key] = value


## A stat by key; "falls" is no stored key but lives lost plus falls in a party (deaths + downs), so a wizard who
## falls and is always raised is not UNTOUCHABLE.
func stat(slot: int, key: String) -> float:
	if key == "falls":
		return stat(slot, "deaths") + stat(slot, "downs")
	return float(stats.get(slot, {}).get(key, 0.0))


func note(t: float, kind: int, slot: int, value: int = 0) -> void:
	moments.append([t, kind, slot, value])


## The best `n` moments, best first: by weight, then the later one.
func top_moments(n: int = SHOWN_MOMENTS) -> Array:
	var out: Array = moments.duplicate()
	out.sort_custom(func(a: Array, b: Array) -> bool:
		var wa: int = MOMENTS[a[1]][2]
		var wb: int = MOMENTS[b[1]][2]
		if wa != wb:
			return wa > wb
		return float(a[0]) > float(b[0]))
	return out.slice(0, n)


## [slot, title] for each wizard, in slot order: the first award whose stat they lead (ties go to the lower
## slot). A stat nobody scored on, or a lowest-wins stat the whole party ties on, gives no award. With two or
## more wizards, one who leads nothing is a TEAM PLAYER; a solo wizard with nothing gets no title.
func awards() -> Array:
	var slots: Array = stats.keys()
	slots.sort()
	var title := {}
	for row: Array in AWARDS:
		var key: String = row[1]
		var low: bool = row[2]
		var lead: int = -1
		var spread := false
		for s: int in slots:
			var v: float = stat(s, key)
			if v != stat(slots[0], key):
				spread = true
			if lead < 0 or (v < stat(lead, key) if low else v > stat(lead, key)):
				lead = s
		if lead < 0 or title.has(lead):
			continue
		if (low and not spread) or (not low and stat(lead, key) <= 0.0):
			continue
		title[lead] = row[0]
	var out: Array = []
	for s: int in slots:
		if title.has(s):
			out.append([s, title[s]])
		elif slots.size() > 1:
			out.append([s, TEAM_PLAYER])
	return out


## The line the screen shows for a moment, with the wizard as P1..P4.
static func moment_text(m: Array) -> String:
	var kind: int = m[1]
	var detail := ""
	match kind:
		M_CHEST:
			detail = Loot.RARITY_NAMES[clampi(int(m[3]), 0, Loot.ULTRA)] + " LOOT"
		M_COMBO:
			detail = "x%d" % int(m[3])
		M_EVOLVE:
			detail = Upgrades.display_name(int(m[3]))
		M_CARD:
			detail = Cards.card_name(clampi(int(m[3]), 0, Cards.count() - 1))
		M_ACT_BOSS:
			detail = str(ACT_BOSS_NAMES.get(int(m[3]), "A BOSS"))
	var who := "P%d" % (int(m[2]) + 1)
	return String(MOMENTS[kind][1]).replace("%s", who).replace("%v", detail)


func to_dict() -> Dictionary:
	var st := {}
	for s: int in stats:
		st[s] = (stats[s] as Dictionary).duplicate()
	return {"stats": st, "moments": moments.duplicate(true), "ai": ai.duplicate(), "source_damage": source_damage.duplicate(),
		"slot_source_damage": slot_source_damage.duplicate(true), "fates": fates.duplicate(),
		"uses": uses.duplicate(), "uses_by": uses_by.duplicate(true)}


## Times `slot` fell this run, and rituals it helped finish.
func downs(slot: int) -> int:
	return int(stat(slot, "downs"))


func revives(slot: int) -> int:
	return int(stat(slot, "revives"))


## Whether `v` is a use count from_dict keeps: a whole or real number, 1 or more.
static func use_count_ok(v: Variant) -> bool:
	return (v is int or v is float) and float(v) >= 1.0


## Whether `v` names a seat: a number, or the text of a whole number (a record that went through JSON).
static func seat_key_ok(v: Variant) -> bool:
	return v is int or v is float or (v is String and (v as String).is_valid_int())


## A record from to_dict() (or from the network): unknown moment kinds are dropped.
static func from_dict(d: Dictionary) -> Results:
	var r := Results.new()
	var st: Variant = d.get("stats", {})
	if st is Dictionary:
		for s: Variant in st:
			r.join(int(s))
			var row: Variant = st[s]
			if row is Dictionary:
				for k: String in STATS:
					r.stats[int(s)][k] = float((row as Dictionary).get(k, 0.0))
	var aid: Variant = d.get("ai", {})
	if aid is Dictionary:
		for s: Variant in aid:
			if bool(aid[s]):
				r.ai[int(s)] = true
	var sd: Variant = d.get("source_damage", {})
	if sd is Dictionary:
		for k: Variant in sd:
			r.source_damage[int(k)] = float(sd[k])
	var ssd: Variant = d.get("slot_source_damage", {})
	if ssd is Dictionary:
		for s: Variant in ssd:
			var row: Variant = ssd[s]
			if row is Dictionary:
				for k: Variant in row:
					r.add_slot_source(int(s), int(k), float(row[k]))
	var fd: Variant = d.get("fates", [])
	if fd is Array:
		for f: Variant in fd:
			r.fates.append(int(f))
	var ud: Variant = d.get("uses", {})
	if ud is Dictionary:
		for k: Variant in ud:
			if k is String and use_count_ok(ud[k]):
				r.uses[k] = int(ud[k])
	var ubd: Variant = d.get("uses_by", {})
	if ubd is Dictionary:
		for s: Variant in ubd:
			var row: Variant = ubd[s]
			if not (row is Dictionary and seat_key_ok(s)):
				continue
			var kept := {}
			for k: Variant in row:
				if k is String and use_count_ok(row[k]):
					kept[k] = int(row[k])
			if not kept.is_empty():
				r.uses_by[int(s)] = kept
	var ms: Variant = d.get("moments", [])
	if ms is Array:
		for m: Variant in ms:
			if m is Array and (m as Array).size() == 4 and int(m[1]) >= 0 and int(m[1]) < MOMENTS.size():
				r.moments.append([float(m[0]), int(m[1]), int(m[2]), int(m[3])])
	return r

extends "res://tests/bot/cover/family.gd"
## The coverage family "catalog": every Upgrades.CATALOG row of kind SPELL, PASSIVE, INSTANT and EVOLUTION (never a
## Minor Arcana card), dealt by WorldGrants.give. A SPELL or EVOLUTION row is credited by the damage the dealt wizard
## does with its spell (for an evolution, while it is held); any other row by its use counter.

const KINDS: Array[int] = [Upgrades.SPELL, Upgrades.PASSIVE, Upgrades.INSTANT, Upgrades.EVOLUTION]


func family() -> String:
	return "catalog"


func keys() -> Array[String]:
	var out: Array[String] = []
	for idx: int in range(Upgrades.count()):
		if KINDS.has(Upgrades.kind(idx)):
			out.append(Upgrades.key(idx))
	return out


## Upgrades.UNBUILT once the job that adds it lands (docs/stage3_brief.md § 4.3); read so that this works before it too.
func unbuilt(key: String) -> bool:
	var shut: Variant = (Upgrades as Script).get_script_constant_map().get("UNBUILT", [])
	return shut is Array and (shut as Array).has(_index(key))


func deal(w: World, p: World.Player, key: String) -> void:
	WorldGrants.give(w, p, _index(key))
	_stage_state(w, p, _index(key))


## The state a row needs before it can be credited that a run's first CEILING seconds may never bring, staged at the
## deal in the smallest way. TEMPERANCE gives back only a heart she lacks, and the play-bot runs for a potion as soon
## as she is hurt: she lacks one heart more than a potion gives back, so the card as dealt (a heart every 18 s) still
## has one to give. THE HERMIT is credited for a gem whose XP it raised, and at its first level (x1.15) it raises none
## under 4 XP (the first minutes drop 1 and 2): she holds it at its top (x1.5, a 1 XP gem gives 2).
func _stage_state(w: World, p: World.Player, idx: int) -> void:
	match idx:
		Upgrades.REGEN:
			p.hp = maxi(1, p.max_hp - 1 - w.seal_potion_heal)
		Upgrades.WISDOM:
			_deal_to_top(w, p, idx)


func _deal_to_top(w: World, p: World.Player, idx: int) -> void:
	while Upgrades.level_of(p.upgrades, idx) < Upgrades.max_level(idx):
		WorldGrants.give(w, p, idx)


func credit(w: World, p: World.Player, key: String) -> int:
	var idx := _index(key)
	var k := Upgrades.kind(idx)
	if k != Upgrades.SPELL and k != Upgrades.EVOLUTION:
		return w.record.used(key)
	var sp := Upgrades.spell_of(idx)
	if k == Upgrades.EVOLUTION and Upgrades.level_of(p.upgrades, idx) <= 0:
		return 0 # this very evolution is not held (a spell may come to have two)
	var dmg := float((w.record.slot_source_damage.get(p.slot, {}) as Dictionary).get(sp, 0.0))
	return ceili(dmg)


static func _index(key: String) -> int:
	for idx: int in range(Upgrades.count()):
		if Upgrades.key(idx) == key:
			return idx
	return -1

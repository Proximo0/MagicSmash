class_name WorldGrants
extends RefCounted
## A catalog row given to a wizard by force (docs/stage3_brief.md § 4.4), read from the catalog alone: for tests, tools
## and the coverage robot (tests/bot/bot_cover.gd) only, never for play. It reads no class, lock, ban, slot cap or
## Upgrades.UNBUILT, and makes no pick shock.


## Gives wizard `p` catalog row `idx`: every [row, level] of its `requires` is raised to at least that level first (a
## row that requires itself, a class weapon, asks nothing more of itself), then the row gains a level with everything
## WorldLevels._pick does after its checks (a nova, a life, a heart, gold, the spell refresh, the pick event, the
## evolve moment). A row at its top level gains nothing (a Minor Arcana card has no top).
static func give(w: World, p: World.Player, idx: int) -> void:
	if idx < 0 or idx >= Upgrades.count():
		return
	var minor := Upgrades.kind(idx) == Upgrades.MINOR
	if not minor and Upgrades.level_of(p.upgrades, idx) >= Upgrades.max_level(idx):
		return
	for req: Array in Upgrades.CATALOG[idx][Upgrades.C_REQUIRES]:
		var need := int(req[0])
		if need == idx:
			continue
		while Upgrades.level_of(p.upgrades, need) < int(req[1]):
			var was := Upgrades.level_of(p.upgrades, need)
			give(w, p, need)
			if Upgrades.level_of(p.upgrades, need) == was:
				break # its top level is below the requirement: the catalog's own fault, never a hang
	p.upgrades[idx] = Upgrades.level_of(p.upgrades, idx) + 1
	_grant_effect(w, p, idx)
	WorldCasting._refresh_spell(w, p)
	w.emit(World.EV_PICK, p.pos.x, p.pos.y - 14, p.slot, idx)
	if Upgrades.is_evolution(idx):
		w.record.note(w.wave_time, Results.M_EVOLVE, p.slot, idx)


## What taking `idx` does at once beyond its level, as WorldLevels._pick (tests/unit/test_grants.gd pins the two together).
static func _grant_effect(w: World, p: World.Player, idx: int) -> void:
	match idx:
		Upgrades.NOVA, Upgrades.M_SWORDS:
			p.bombs += 1
		Upgrades.LIFE:
			p.lives += 1
		Upgrades.M_CUPS:
			if p.alive:
				p.hp = mini(p.max_hp, p.hp + 1)
		Upgrades.M_PENTACLES:
			var gold: float = Upgrades.value(p.upgrades, idx, 0.0) * (1.0 + p.armor[Loot.ST_GREED] + w.meta_gold)
			p.gold += gold
			w.record.add(p.slot, "gold", gold)
	if idx == Upgrades.NOVA or idx == Upgrades.LIFE: w.record.use(Upgrades.key(idx), p.slot)

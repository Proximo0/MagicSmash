class_name WorldDrops
extends RefCounted
## Drops for World: what kills and urns drop, pickups, magnet XP, collecting and chests. Static helpers; the first argument is the World.


## A kill may drop its monster's card (Cards.drop_chance): far likelier from an elite or a Lich.
static func _roll_card(w: World, e: World.Enemy) -> void:
	if e.final and w.seal_card >= 0: # a Seal's Archlich drops the Seal card
		_drop(w, World.PK_CARD, e.pos, Vector2(0, -60), w.tune.chest_life, w.seal_card)
	if w.rng.randf() < Cards.drop_chance(e.type, e.elite, w.tune.card_chance * w.seal_cards, w.tune.card_elite_mul, w.tune.card_boss_chance * w.seal_cards):
		_drop(w, World.PK_CARD, e.pos, Vector2(0, -50), w.tune.chest_life, e.type)


static func _roll_drop(w: World, e: World.Enemy) -> void:
	var lucky := w.rng.randf()
	if lucky < w.tune.ultra_drop_chance and w.seal_ultra:
		_drop(w, World.PK_CHEST_ULTRA, e.pos, Vector2(0, 30), w.tune.chest_life, 5)
		return
	if lucky < w.tune.ultra_drop_chance + w.tune.rare_drop_chance:
		_drop(w, World.PK_CHEST_RARE, e.pos, Vector2(0, 30), w.tune.chest_life, 2)
		return
	var r := w.rng.randf()
	var big := e.type == World.ORC or e.type == World.MAGE
	var pop := Vector2.from_angle(w.rng.randf() * TAU) * 40.0
	if big:
		_drop(w, World.PK_GEM, e.pos, pop)
		if w.rng.randf() < 0.25:
			_drop(w, World.TOMES[w.rng.randi() % World.TOMES.size()], e.pos, -pop)
		return
	if r < 0.22:
		_drop(w, World.PK_COIN, e.pos, pop)
	elif r < 0.27:
		_drop(w, World.PK_GEM, e.pos, pop)
	elif r < 0.29 + 0.02 * (w.seal_potions - 1.0): # APPRENTICE: more
		if w.no_potions > 0.0 or w.seal_hunger: return # THE HIEROPHANT, HUNGER
		_drop(w, World.PK_POTION, e.pos, pop)
	elif r < 0.315:
		_drop(w, World.TOMES[w.rng.randi() % World.TOMES.size()], e.pos, pop)
	elif r < 0.322:
		_drop(w, World.PK_BOOTS, e.pos, pop)
	elif r < 0.33:
		_drop(w, World.PK_ORBIT, e.pos, pop)


## Tops the urns back up to tune.urn_count, each in a band along a wall, clear of the wizards and of each other.
static func _refill_urns(w: World) -> void:
	var band := G.ARENA.grow(-12.0)
	var tries := 0
	while w.urns.size() < int(w.tune.urn_count) and tries < 60:
		tries += 1
		var at := Vector2(w.rng.randf_range(band.position.x, band.end.x), w.rng.randf_range(band.position.y, band.end.y))
		match w.rng.randi() % 4:
			0: at.y = band.position.y + w.rng.randf() * 8.0
			1: at.y = band.end.y - w.rng.randf() * 8.0
			2: at.x = band.position.x + w.rng.randf() * 8.0
			_: at.x = band.end.x - w.rng.randf() * 8.0
		var clear := true
		for p: World.Player in w.players.values():
			if p.pos.distance_to(at) < 40.0:
				clear = false
		for u: Vector2 in w.urns:
			if u.distance_to(at) < 18.0:
				clear = false
		if clear:
			w.urns.append(at)


## A wizard's shot or a wizard walking into an urn shatters it. Shots fly on through.
static func _update_urns(w: World) -> void:
	var i := w.urns.size() - 1
	while i >= 0:
		var u: Vector2 = w.urns[i]
		var hit := false
		for p: World.Player in w.players.values():
			if p.alive and p.pos.distance_to(u) < World.URN_R + 4.0:
				hit = true
		if not hit:
			for s: World.Shot in w.shots:
				if not s.dead and s.pos.distance_to(u + Vector2(0, -3)) < World.URN_R + s.r:
					hit = true
					break
		if hit:
			w.urns.remove_at(i)
			_break_urn(w, u)
		i -= 1


## What falls out of a broken urn: usually coins or nothing, sometimes a gem or potion, rarely a rare chest, and
## very rarely a monster card of any kind.
static func _break_urn(w: World, at: Vector2) -> void:
	var r := w.rng.randf()
	var pop := Vector2(0, 30)
	var what := World.URN_DUST
	if r < w.tune.urn_card_chance:
		what = World.URN_CARD_DROP
		_drop(w, World.PK_CARD, at, Vector2(0, -50), w.tune.chest_life, Sanctum.roll_card(w.rng) + World.URN_CARD)
	elif r < w.tune.urn_card_chance + w.tune.urn_rare_chance:
		what = World.URN_CHEST
		_drop(w, World.PK_CHEST_RARE, at, pop, w.tune.chest_life, 2)
	elif r < w.tune.urn_card_chance + w.tune.urn_rare_chance + 0.06 and w.no_potions <= 0.0: # THE HIEROPHANT: a gem instead
		what = World.URN_POTION
		_drop(w, World.PK_POTION, at, pop)
	elif r < w.tune.urn_card_chance + w.tune.urn_rare_chance + 0.24:
		what = World.URN_GEM
		_drop(w, World.PK_GEM, at, pop)
	elif r < 0.75:
		what = World.URN_COIN
		for k in 2:
			_drop(w, World.PK_COIN, at, Vector2.from_angle(w.rng.randf() * TAU) * 40.0)
	w.emit(World.EV_URN, at.x, at.y, what, 0)


## Drops an XP gem, or, with tune.xp_gem_cap gems already down, adds its XP to the nearest one (and keeps that
## one around), so a big horde cannot bury the floor in gems.
static func _drop_xp(w: World, pos: Vector2, vel: Vector2, value: int) -> void:
	var count := 0
	var near: World.Pickup = null
	var nd := INF
	for k in w.pickups:
		if k.kind != World.PK_XP:
			continue
		count += 1
		var d := k.pos.distance_squared_to(pos)
		if d < nd:
			nd = d
			near = k
	if count >= int(w.tune.xp_gem_cap) and near != null:
		near.value += value
		near.life = maxf(near.life, w.tune.xp_gem_life * 0.5)
		return
	_drop(w, World.PK_XP, pos, vel, w.tune.xp_gem_life, value)


static func _drop(w: World, kind: int, pos: Vector2, vel: Vector2, life: float = 9.0, value: int = 0) -> void:
	var k := World.Pickup.new()
	k.kind = kind
	k.value = value
	k.pos = pos
	k.vel = vel
	k.life = life
	w.pickups.append(k)


static func _update_pickups(w: World, dt: float) -> void:
	for k in w.pickups:
		k.life -= dt
		if k.kind == World.PK_XP:
			_magnet_xp(w, k)
		k.pos += k.vel * dt
		k.vel = k.vel.move_toward(Vector2.ZERO, dt * 120.0)
		k.pos.x = clampf(k.pos.x, G.ARENA.position.x + 6, G.ARENA.end.x - 6)
		k.pos.y = clampf(k.pos.y, G.ARENA.position.y + 8, G.ARENA.end.y - 4)
		for p in w.players.values():
			if p.alive and p.pos.distance_to(k.pos) < 11.0:
				_collect(w, p, k)
				k.life = -1.0
				break
	w.pickups = w.pickups.filter(func(k): return k.life > 0.0)


## An XP gem near a wizard flies to the nearest one in reach; during a lull every gem flies to the nearest one.
static func _magnet_xp(w: World, k: World.Pickup) -> void:
	var best: World.Player = null
	var bd := INF
	for p: World.Player in w.players.values():
		if not p.alive:
			continue
		var d := p.pos.distance_to(k.pos)
		if (w.lull_left > 0.0 or w.gem_rush > 0.0 or d < w.tune.xp_magnet_radius * Upgrades.magnet_mul(p.upgrades)) and d < bd:
			bd = d
			best = p
	if best:
		k.vel = (best.pos - k.pos).normalized() * w.tune.xp_magnet_speed


static func _collect(w: World, p: World.Player, k: World.Pickup) -> void:
	if k.kind == World.PK_XP:
		w.gain_xp(p, int(round(k.value * Upgrades.xp_mul(p.upgrades) * (1.0 + w.meta_xp))))
		w.emit(World.EV_PICKUP, k.pos.x, k.pos.y, k.kind, p.slot)
		return
	if k.kind == World.PK_CHEST or k.kind == World.PK_CHEST_RARE or k.kind == World.PK_CHEST_ULTRA:
		_open_chest(w, p, k)
		return
	if k.kind == World.PK_CARD:
		var idx := k.value % World.URN_CARD
		w.cards_found.append(idx)
		w.record.note(w.wave_time, Results.M_CARD, p.slot, idx)
		w.emit(World.EV_CARD, k.pos.x, k.pos.y, idx, p.slot + (8 if k.value >= World.URN_CARD else 0))
		return
	var pts := 0
	var greed: float = 1.0 + p.armor[Loot.ST_GREED] + w.meta_gold
	match k.kind:
		World.PK_COIN:
			pts = 100
			p.gold += Loot.GOLD_COIN * greed
			w.record.add(p.slot, "gold", Loot.GOLD_COIN * greed)
		World.PK_GEM:
			pts = 500
			p.gold += Loot.GOLD_GEM * greed
			w.record.add(p.slot, "gold", Loot.GOLD_GEM * greed)
		World.PK_POTION:
			p.hp = mini(p.max_hp, p.hp + w.seal_potion_heal) # FAMINE: one
		World.PK_TOME_FIRE, World.PK_TOME_FROST, World.PK_TOME_STORM, World.PK_TOME_STAR, World.PK_TOME_RUNE:
			# A tome grants or levels its spell weapon; one that is already maxed is worth points instead.
			var idx := Upgrades.weapon_entry(World.TOMES.find(k.kind) + 1)
			if Upgrades.take(p.upgrades, idx):
				WorldCasting._refresh_spell(w, p)
				w.emit(World.EV_PICK, p.pos.x, p.pos.y - 14, p.slot, idx)
			else:
				pts = 500
		World.PK_BOOTS:
			p.haste = 10.0
		World.PK_ORBIT:
			p.orbit = 12.0
	p.score += pts
	w.emit(World.EV_PICKUP, k.pos.x, k.pos.y, k.kind, p.slot)
	if pts > 0:
		w.emit(World.EV_SCORE, k.pos.x, k.pos.y - 6, pts, p.slot)


## A chest opens where it is touched: a tier (luck from the chest's value) and an item, applied at once. The
## arena plays the reel from EV_CHEST.
static func _open_chest(w: World, p: World.Player, k: World.Pickup) -> void:
	var tier := Loot.roll_rarity(w.rng, float(k.value + w.meta_luck + w.seal_luck))
	if not w.seal_ultra: tier = mini(tier, Loot.LEGENDARY) # APPRENTICE: no ULTRA RARE
	if k.kind == World.PK_CHEST_RARE:
		tier = maxi(tier, Loot.RARE)
	elif k.kind == World.PK_CHEST_ULTRA:
		tier = maxi(tier, Loot.LEGENDARY)
	var idx := Loot.roll_item(w.rng)
	w.record.add(p.slot, "chests", 1)
	w.record.best(p.slot, "best_tier", tier)
	if tier >= Loot.LEGENDARY:
		w.record.note(w.wave_time, Results.M_CHEST, p.slot, tier)
	var v := Loot.value(idx, tier)
	if Loot.kind(idx) == Loot.KIND_ARMOR:
		var before: float = p.armor[Loot.ST_VIGOR]
		Loot.add_armor(p.armor, idx, tier)
		var hearts := int(p.armor[Loot.ST_VIGOR] - before)
		p.max_hp += hearts
		p.hp += hearts
	else:
		match Loot.effect(idx):
			Loot.FX_ELIXIR:
				p.hp = p.max_hp
			Loot.FX_NOVAS:
				p.bombs += maxi(1, int(v))
			Loot.FX_TOME:
				for i in maxi(1, int(v)):
					var owned: Array[int] = []
					for sp in Spells.COUNT:
						var lv := Upgrades.weapon_level(p.upgrades, sp)
						if lv > 0 and lv < Spells.MAX_LEVEL:
							owned.append(sp)
					if owned.is_empty():
						break
					Upgrades.take(p.upgrades, Upgrades.weapon_entry(owned[w.rng.randi() % owned.size()]))
				WorldCasting._refresh_spell(w, p)
			Loot.FX_INSIGHT:
				w.gain_xp(p, maxi(1, int(round(w.xp_needed() * v))))
	w.emit(World.EV_CHEST, k.pos.x, k.pos.y, p.slot, idx * 8 + tier)

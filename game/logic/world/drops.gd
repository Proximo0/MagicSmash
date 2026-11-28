class_name WorldDrops
extends RefCounted
## Drops for World: what kills and urns drop, pickups, magnet XP, collecting and chests. Static helpers; the first argument is the World.


## Kinds that come into a run only from another kind (a slime splits into mini slimes): kind -> the kind it comes
## from. A kind here spawns in a run when the kind it comes from does (run_card_choices).
const SPAWNED_FROM := {Bestiary.MSLIME: Bestiary.SLIME}


## The card run's card (WorldDrops.card_due, run_card): the first kill that stands for it (Cards.run_card) once its
## moment has come drops it, the final boss's kill for its card. Out of a card run, once it has dropped, or when it
## waits in an urn (_card_in_urn), no kill drops a card. Every kill takes its one draw all the same.
static func _roll_card(w: World, e: World.Enemy) -> void:
	w.rng.randf() # every kill drew for a card when cards were a per-kill chance: kept so the main stream stays as it was
	if not card_due(w) or _card_in_urn(w):
		return
	var idx := Cards.run_card(e.type, e.final, w.seal_card)
	if idx < 0 or idx != run_card(w):
		return
	w.card_dropped = true
	_drop(w, World.PK_CARD, e.pos, Vector2(0, -50), w.tune.chest_life, idx)


## True when the card run's card waits in an urn (_break_urn) rather than in a kill: the run's urn draw is under
## Tuning.card_run_urn, or the run was given an urn card (apply_meta's "urn_card").
static func _card_in_urn(w: World) -> bool:
	return w.urn_card or float(w.run_loot.get("card_urn", 1.0)) < w.tune.card_run_urn


## The cards this run can give, in card order: every monster card whose kind the run's horde spawns before its final
## boss (a HORDE row unlocked by then with weight in an act, or a kind that comes from one: SPAWNED_FROM), and the
## card each of the schedule's bosses stands for (Cards.run_card: the Archlich's is the Seal's card under a Seal,
## THE LICH otherwise; the act bosses have none).
static func run_card_choices(w: World) -> Array[int]:
	var end := Bosses.final_time(w.schedule)
	var kinds := {}
	for row: Array in Bestiary.HORDE:
		var weight := 0
		for col: int in range(Bestiary.H_W1, Bestiary.H_GMIN):
			weight += int(row[col])
		if weight > 0 and float(row[Bestiary.H_UNLOCK]) < end:
			kinds[int(row[Bestiary.H_TYPE])] = true
	for kind: int in SPAWNED_FROM:
		if kinds.has(int(SPAWNED_FROM[kind])):
			kinds[kind] = true
	var out: Array[int] = []
	for kind: int in kinds:
		var idx := Cards.for_enemy(kind)
		if idx >= 0 and not out.has(idx):
			out.append(idx)
	for row: Array in w.schedule:
		var idx := Cards.run_card(int(row[1]), bool(row[2]), w.seal_card)
		if idx >= 0 and not out.has(idx):
			out.append(idx)
	out.sort()
	return out


## The card run's card: the run's kind draw (Loot.run_rolls "card_kind") picks one of run_card_choices, each as
## likely; -1 when the run can give none.
static func run_card(w: World) -> int:
	var choices := run_card_choices(w)
	if choices.is_empty():
		return -1
	var u := clampf(float(w.run_loot.get("card_kind", 0.0)), 0.0, 1.0)
	return choices[mini(int(u * choices.size()), choices.size() - 1)]


## Seconds into the run of a seeded moment (Loot.moment over the run up to the Archlich's arrival).
static func _loot_moment(w: World, u: float) -> float:
	return Loot.moment(u, w.tune.loot_moment_from, w.tune.loot_moment_to, Bosses.final_time(w.schedule))


## True while this is an ULTRA RARE run (Loot.ultra_run_chance with the run's chest luck; never under a Seal
## without ULTRA RARE loot), its moment has come and its prismatic chest has not dropped yet.
static func ultra_due(w: World) -> bool:
	if w.ultra_dropped or not w.seal_ultra or w.run_loot.is_empty():
		return false
	var chance := Loot.ultra_run_chance(w.tune.ultra_run_chance, float(w.meta_luck + w.seal_luck), w.tune.ultra_run_luck,
		w.tune.ultra_run_cap)
	return float(w.run_loot.ultra) < chance and w.wave_time >= _loot_moment(w, float(w.run_loot.ultra_at))


## True while this is a card run (Cards.card_run_chance with the Seal's card odds, or an urn card the run was
## given: World.urn_card), its moment has come and its one card has not dropped yet (from a kill, _roll_card, or an
## urn, _break_urn).
static func card_due(w: World) -> bool:
	if w.card_dropped or w.run_loot.is_empty():
		return false
	var card_run := w.urn_card or float(w.run_loot.card) < Cards.card_run_chance(w.tune.card_run_chance, w.seal_cards)
	return card_run and w.wave_time >= _loot_moment(w, float(w.run_loot.card_at))


static func _roll_drop(w: World, e: World.Enemy) -> void:
	var lucky := w.rng.randf()
	if ultra_due(w): # the ULTRA RARE run's one prismatic chest
		w.ultra_dropped = true
		_drop(w, World.PK_CHEST_ULTRA, e.pos, Vector2(0, 30), w.tune.chest_life, 5)
		return
	if lucky < w.tune.rare_drop_chance:
		_drop(w, World.PK_CHEST_RARE, e.pos, Vector2(0, 30), w.tune.chest_life, 2)
		return
	var r := w.rng.randf()
	var big := e.type == World.ORC or e.type == World.MAGE
	var pop := Vector2.from_angle(w.rng.randf() * TAU) * 40.0
	# Spell tomes fall only while tune.floor_tomes is on (otherwise the party tome replaces them).
	var tomes := w.tune.floor_tomes >= 0.5
	if big:
		_drop(w, World.PK_GEM, e.pos, pop)
		if tomes and w.rng.randf() < w.tune.big_tome_chance:
			_drop(w, World.TOMES[w.rng.randi() % World.TOMES.size()], e.pos, -pop)
		return
	var coin := w.tune.coin_drop_chance
	var potion := coin + 0.05 + w.tune.potion_drop_chance * w.seal_potions # APPRENTICE: more
	var tome := potion + w.tune.tome_drop_chance
	if r < coin:
		_drop(w, World.PK_COIN, e.pos, pop)
	elif r < coin + 0.05:
		_drop(w, World.PK_GEM, e.pos, pop)
	elif r < potion:
		if w.no_potions > 0.0: return # THE HIEROPHANT
		_drop(w, World.PK_POTION, e.pos, pop)
	elif r < tome:
		if tomes:
			_drop(w, World.TOMES[w.rng.randi() % World.TOMES.size()], e.pos, pop)
	elif r < tome + 0.007:
		_drop(w, World.PK_BOOTS, e.pos, pop)
	elif r < tome + 0.015:
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
## very rarely the card run's card (run_card), when it waits in an urn.
static func _break_urn(w: World, at: Vector2) -> void:
	w.urns_broken += 1
	var r := w.rng.randf()
	var pop := Vector2(0, 30)
	var what := World.URN_DUST
	var urn_card := run_card(w) if card_due(w) and _card_in_urn(w) else -1 # the card run's card, waiting in an urn
	if urn_card >= 0:
		what = World.URN_CARD_DROP
		w.card_dropped = true
		_drop(w, World.PK_CARD, at, Vector2(0, -50), w.tune.chest_life, urn_card + World.URN_CARD)
	elif r < w.tune.urn_rare_chance:
		what = World.URN_CHEST
		_drop(w, World.PK_CHEST_RARE, at, pop, w.tune.chest_life, 2)
	elif r < w.tune.urn_rare_chance + 0.06 and w.no_potions <= 0.0: # THE HIEROPHANT: a gem instead
		what = World.URN_POTION
		_drop(w, World.PK_POTION, at, pop)
	elif r < w.tune.urn_rare_chance + 0.24:
		what = World.URN_GEM
		_drop(w, World.PK_GEM, at, pop)
	elif r < 0.75:
		what = World.URN_COIN
		for k in 2:
			_drop(w, World.PK_COIN, at, Vector2.from_angle(w.rng.randf() * TAU) * 40.0)
	WorldLevels._drop_party_tome(w, at, w.tune.party_tome_urn)
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
	# A late floor holds hundreds of gems, so everything that is the same for each of them is worked out once a
	# tick: who is alive, how far each magnet reaches, the room's edges (sim_horde's mixed row).
	if w._plist.size() != w.players.size():
		w._plist.assign(w.players.values())
	var who: Array[World.Player] = []
	var reach := PackedFloat64Array()
	_magnets(w, who, reach)
	var n := who.size()
	var x0: float = G.ARENA.position.x + 6
	var x1: float = G.ARENA.end.x - 6
	var y0: float = G.ARENA.position.y + 8
	var y1: float = G.ARENA.end.y - 4
	var pull: float = w.tune.xp_magnet_speed
	var drag := dt * 120.0
	var gone := false
	for k: World.Pickup in w.pickups:
		k.life -= dt
		var pos: Vector2 = k.pos
		var vel: Vector2 = k.vel
		var best := -1
		if k.kind == World.PK_XP:
			# An XP gem near a wizard flies to the nearest one in reach (during a lull or a gem rush: any reach).
			var bd := INF
			for i: int in n:
				var d: float = who[i].pos.distance_to(pos)
				if d < reach[i] and d < bd:
					bd = d
					best = i
			if best >= 0 and vel.length() < pull - drag - drag and bd * Upgrades.magnet_mul(who[best].upgrades) >= reach[best]: k.moon = who[best].slot
			if best >= 0:
				vel = (who[best].pos - pos).normalized() * pull
		if vel != Vector2.ZERO:
			pos += vel * dt
			k.vel = vel.move_toward(Vector2.ZERO, drag)
		elif best >= 0:
			k.vel = vel # a gem right on its wizard: pulled nowhere
		pos.x = clampf(pos.x, x0, x1)
		pos.y = clampf(pos.y, y0, y1)
		k.pos = pos
		for p: World.Player in who:
			if p.pos.distance_to(pos) < 11.0 and WorldApprentices.may_take(w, p, k.kind):
				_collect(w, p, k)
				k.life = -1.0
				_magnets(w, who, reach) # a pick-up can change what the next gem sees
				n = who.size()
				break
		if k.life <= 0.0:
			gone = true
	if gone:
		w.pickups = w.pickups.filter(func(k): return k.life > 0.0)


## Fills `who` with the living wizards and `reach` with how far each one's magnet pulls XP gems (no limit
## during a lull or a gem rush).
static func _magnets(w: World, who: Array[World.Player], reach: PackedFloat64Array) -> void:
	who.clear()
	reach.clear()
	var all := w.lull_left > 0.0 or w.gem_rush > 0.0
	for p: World.Player in w._plist:
		if p.alive:
			who.append(p)
			reach.append(INF if all else w.tune.xp_magnet_radius * Upgrades.magnet_mul(p.upgrades) * p.reach_mul)


static func _collect(w: World, p: World.Player, k: World.Pickup) -> void:
	if k.kind == World.PK_XP:
		if k.moon == p.slot: w.record.use("magnet", p.slot)
		if int(round(k.value * Upgrades.xp_mul(p.upgrades) * (1.0 + w.meta_xp))) > int(round(k.value * (1.0 + w.meta_xp))): w.record.use("wisdom", p.slot)
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
	if k.kind == WorldLevels.PARTY_TOME:
		WorldLevels._read_party_tome(w)
		w.emit(World.EV_PICKUP, k.pos.x, k.pos.y, k.kind, p.slot)
		return
	p = WorldApprentices.payee(w, p, k.kind) # an apprentice's coin or gem goes to the nearest human
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
			# A spell tome (none fall any more) grants or levels its spell weapon if the wizard's slots allow it;
			# otherwise it is worth points instead.
			var idx := Upgrades.weapon_entry(World.TOMES.find(k.kind) + 1)
			if Upgrades.available(p.upgrades, idx, w.slot_cap(), p.banned) and Upgrades.take(p.upgrades, idx):
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
	var tier := Loot.roll_rarity(w.rng, float(k.value + w.meta_luck + w.seal_luck) + p.luck) # the opener's FORTUNE
	if k.kind == World.PK_CHEST_RARE:
		tier = maxi(tier, Loot.RARE)
	elif k.kind == World.PK_CHEST_ULTRA: # the ULTRA RARE run's chest, the only way to ULTRA RARE (APPRENTICE: none)
		tier = Loot.ULTRA if w.seal_ultra else Loot.LEGENDARY
	var idx := Loot.roll_item(w.rng, tier) # one draw; never a flat item at LEGENDARY or above
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
						if Upgrades.weapon_level(p.upgrades, sp) > 0 \
								and Upgrades.available(p.upgrades, Upgrades.weapon_entry(sp), w.slot_cap(), p.banned):
							owned.append(sp)
					if owned.is_empty():
						break
					Upgrades.take(p.upgrades, Upgrades.weapon_entry(owned[w.rng.randi() % owned.size()]))
				WorldCasting._refresh_spell(w, p)
			Loot.FX_INSIGHT:
				w.gain_xp(p, maxi(1, int(round(w.xp_needed() * v))))
	w.emit(World.EV_CHEST, k.pos.x, k.pos.y, p.slot, idx * 8 + tier)

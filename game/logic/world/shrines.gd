class_name WorldShrines
extends RefCounted
## Gamble shrines for World: placing them, paying in and resolving the reel. Static helpers; the first argument is the World.


## Shrines appear on timers. A wizard who can pay stands on one for tune.shrine_hold seconds to bet; the gold
## goes at once, the reel plays, and the outcome lands when it stops. The team shrine bets for everybody.
static func _update_shrines(w: World, dt: float) -> void:
	w.shrine_t -= dt
	if w.shrine_t <= 0.0:
		w.shrine_t += w.tune.shrine_interval
		_place_shrine(w, Gamble.SOLO)
	w.team_shrine_t -= dt
	if w.team_shrine_t <= 0.0:
		w.team_shrine_t += w.tune.team_shrine_interval
		_place_shrine(w, Gamble.TEAM)
	for sh: World.Shrine in w.shrines:
		sh.life -= dt
		var payer: World.Player = null
		for p: World.Player in w.players.values():
			if p.alive and p.gold >= sh.cost and p.pos.distance_to(sh.pos) < w.tune.shrine_radius:
				payer = p
				break
		if payer == null:
			sh.charge = maxf(0.0, sh.charge - dt * 2.0)
			continue
		if payer.slot != sh.who:
			sh.who = payer.slot
			sh.charge = 0.0
		sh.charge += dt
		if sh.charge >= w.tune.shrine_hold:
			_bet(w, sh, payer)
	w.shrines = w.shrines.filter(func(sh: World.Shrine) -> bool: return sh.life > 0.0)
	while not w._gambles.is_empty() and w._gambles[0].t <= w.wave_time:
		_resolve_gamble(w, w._gambles.pop_front())


## Shrine rows as the snapshot sends them: [kind, x, y, life, charge fraction, cost].
static func snapshot_shrines(w: World) -> Array:
	var out: Array = []
	for x: World.Shrine in w.shrines:
		out.append([x.kind, x.pos.x, x.pos.y, x.life, x.charge / w.tune.shrine_hold, x.cost])
	return out


static func _place_shrine(w: World, kind: int) -> void:
	var sh := World.Shrine.new()
	sh.kind = kind
	sh.pos = WorldWaves._spot_near_party(w, w.tune.shrine_min_dist, w.tune.shrine_min_dist + 120.0, 30.0)
	sh.life = w.tune.shrine_life * (w.tune.team_shrine_life_mul if kind == Gamble.TEAM else 1.0)
	sh.cost = Gamble.cost(kind, w.wave, w.tune.shrine_cost_base, w.tune.shrine_cost_per_min, w.tune.team_cost_mul)
	w.shrines.append(sh)
	w.emit(World.EV_SHRINE_UP, sh.pos.x, sh.pos.y, kind, sh.cost)


static func _bet(w: World, sh: World.Shrine, p: World.Player) -> void:
	sh.life = 0.0
	p.gold -= sh.cost
	w.record.add(p.slot, "bets", sh.cost)
	var outcome := Gamble.roll(w.rng, sh.kind)
	var reel := w.tune.team_reel if sh.kind == Gamble.TEAM else w.tune.shrine_reel
	w._gambles.append({"t": w.wave_time + reel, "slot": p.slot, "kind": sh.kind, "outcome": outcome, "stake": sh.cost, "pos": sh.pos})
	w._gambles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	w.emit(World.EV_SHRINE, sh.pos.x, sh.pos.y, p.slot, sh.kind * 16 + outcome)


static func _resolve_gamble(w: World, g: Dictionary) -> void:
	var p: World.Player = w.players.get(g.slot)
	var pos: Vector2 = g.pos
	if g.kind == Gamble.TEAM:
		if g.outcome == Gamble.TO_BLESSING:
			var who: World.Player = p if p != null else w.players.values()[0]
			for i in Gamble.BLESSING_LEVELS:
				w.gain_xp(who, maxi(1, w.xp_needed() - w.party_xp))
		else:
			for q: World.Player in w.players.values():
				if q.alive:
					q.hp = maxi(1, q.hp - 1)
					q.flash = 0.3
					WorldWaves._spawn_elite(w)
	elif p != null:
		match int(g.outcome):
			Gamble.SO_JACKPOT:
				WorldDrops._drop(w, World.PK_CHEST, pos, Vector2.ZERO, w.tune.chest_life, int(w.tune.boss_chest_luck))
			Gamble.SO_CHEST:
				WorldDrops._drop(w, World.PK_CHEST, pos, Vector2.ZERO, w.tune.chest_life, int(w.tune.elite_chest_luck))
			Gamble.SO_DOUBLE:
				p.gold += g.stake * 2
			Gamble.SO_CURSE:
				if p.alive:
					p.hp = maxi(1, p.hp - 1)
					p.flash = 0.3
	if g.kind == Gamble.TEAM:
		w.record.note(w.wave_time, Results.M_BLESSING if g.outcome == Gamble.TO_BLESSING else Results.M_CURSE, g.slot)
	elif g.outcome == Gamble.SO_JACKPOT:
		w.record.note(w.wave_time, Results.M_JACKPOT, g.slot)
	w.emit(World.EV_GAMBLE, pos.x, pos.y, g.slot, int(g.kind) * 16 + int(g.outcome))

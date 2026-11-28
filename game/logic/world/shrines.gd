class_name WorldShrines
extends RefCounted
## Gamble shrines for World: placing them, paying in and resolving the reel. Static helpers; the first argument is the World.

## Gold short of the price a pot may be and count as full (float sums of the steps' parts).
const POT_FULL_EPS: float = 0.0001


## Shrines appear on timers. A wizard who can pay stands on a solo shrine for tune.shrine_hold seconds to bet; the
## gold goes at once, the reel plays, and the outcome lands when it stops. A team shrine is paid by the table: the
## wizards standing in it fill its pot together (_fill_pot), and a full pot bets for everybody. One that fades
## before its pot is full gives every wizard back what she paid.
static func _update_shrines(w: World, dt: float) -> void:
	_tick_fates(w, dt)
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
		if sh.kind == Gamble.TEAM:
			if sh.life > 0.0:
				_fill_pot(w, sh, dt)
			if sh.life <= 0.0 and not sh.paid.is_empty():
				_refund_pot(w, sh)
			continue
		var payer: World.Player = null
		for p: World.Player in w.players.values():
			if p.alive and not p.ai and p.gold >= sh.cost and p.pos.distance_to(sh.pos) < w.tune.shrine_radius:
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


## Shrine rows as the snapshot sends them: [kind, x, y, life, charge fraction, cost, wizards still needed]. A team
## shrine's fraction is its pot / price; "still needed" is how many more wizards must step in before its pot may
## fill (always 0 for a solo shrine).
static func snapshot_shrines(w: World) -> Array:
	var out: Array = []
	for x: World.Shrine in w.shrines:
		if x.kind == Gamble.TEAM:
			out.append([x.kind, x.pos.x, x.pos.y, x.life, x.pot / maxf(1.0, float(x.cost)), x.cost, _pot_need(w, x)])
		else:
			out.append([x.kind, x.pos.x, x.pos.y, x.life, x.charge / w.tune.shrine_hold, x.cost, 0])
	return out


## The living human wizards of the party (an apprentice neither pays nor counts as a partner).
static func _pot_humans(w: World) -> Array[World.Player]:
	var out: Array[World.Player] = []
	for p: World.Player in w.players.values():
		if p.alive and not p.ai:
			out.append(p)
	return out


## The living humans standing in `sh`, in slot order.
static func _pot_payers(w: World, sh: World.Shrine) -> Array[World.Player]:
	var out: Array[World.Player] = []
	for p: World.Player in _pot_humans(w):
		if p.pos.distance_to(sh.pos) < w.tune.shrine_radius:
			out.append(p)
	out.sort_custom(func(a: World.Player, b: World.Player) -> bool: return a.slot < b.slot)
	return out


## How many more wizards must step into a team shrine before its pot may fill: two of the party while two or more
## humans live, one when only one does.
static func _pot_need(w: World, sh: World.Shrine) -> int:
	var need: int = mini(2, _pot_humans(w).size())
	return maxi(0, need - _pot_payers(w, sh).size())


## One step of the table paying into a team shrine: the whole price takes tune.team_pay_time seconds, split in equal
## parts among the standing wizards who still have gold; one who runs dry pays what she has and the others cover
## the rest in the same step. The pot only waits, never drains, while too few stand in it.
static func _fill_pot(w: World, sh: World.Shrine, dt: float) -> void:
	if _pot_need(w, sh) > 0:
		return
	var payers: Array[World.Player] = []
	for p: World.Player in _pot_payers(w, sh):
		if p.gold > 0.0:
			payers.append(p)
	if payers.is_empty():
		return
	# The poorest pay first, so whatever one cannot pay is shared by those after her (ties in slot order).
	payers.sort_custom(func(a: World.Player, b: World.Player) -> bool:
		return a.gold < b.gold or (a.gold == b.gold and a.slot < b.slot))
	var due: float = minf(float(sh.cost) * dt / w.tune.team_pay_time, float(sh.cost) - sh.pot)
	for i: int in range(payers.size()):
		var p: World.Player = payers[i]
		var part: float = minf(p.gold, due / float(payers.size() - i))
		p.gold -= part
		due -= part
		sh.pot += part
		sh.paid[p.slot] = float(sh.paid.get(p.slot, 0.0)) + part
	if float(sh.cost) - sh.pot <= POT_FULL_EPS:
		_bet_pot(w, sh)


## A full pot bets for the table: `who` is the wizard who paid the most (ties: the lowest slot), and each payer's
## "bets" are booked now, each her own share.
static func _bet_pot(w: World, sh: World.Shrine) -> void:
	var slots: Array = sh.paid.keys()
	slots.sort()
	var who: int = int(slots[0])
	for s: Variant in slots:
		w.record.add(int(s), "bets", float(sh.paid[s]))
		if float(sh.paid[s]) > float(sh.paid[who]):
			who = int(s)
	sh.paid.clear()
	_draw_bet(w, sh, who)


## A team shrine that fades before its pot is full gives each wizard back exactly what she paid.
static func _refund_pot(w: World, sh: World.Shrine) -> void:
	for s: Variant in sh.paid.keys():
		var p: World.Player = w.players.get(s)
		if p != null:
			p.gold += float(sh.paid[s])
	sh.paid.clear()
	sh.pot = 0.0


static func _place_shrine(w: World, kind: int) -> void:
	var sh := World.Shrine.new()
	sh.kind = kind
	sh.pos = WorldWaves._spot_near_party(w, w.tune.shrine_min_dist, w.tune.shrine_min_dist + 120.0, 30.0)
	sh.life = w.tune.shrine_life * (w.tune.team_shrine_life_mul if kind == Gamble.TEAM else 1.0)
	sh.cost = Gamble.cost(kind, w.wave, w.tune.shrine_cost_base, w.tune.shrine_cost_per_min, w.tune.team_cost_mul)
	w.shrines.append(sh)
	w.emit(World.EV_SHRINE_UP, sh.pos.x, sh.pos.y, kind, sh.cost)


## One wizard pays a shrine's whole price and bets (a solo shrine).
static func _bet(w: World, sh: World.Shrine, p: World.Player) -> void:
	p.gold -= sh.cost
	w.record.add(p.slot, "bets", sh.cost)
	_draw_bet(w, sh, p.slot)


## A paid shrine is spent: its outcome is drawn, the reel queued and shown, for `slot`.
static func _draw_bet(w: World, sh: World.Shrine, slot: int) -> void:
	sh.life = 0.0
	var outcome := _first_draw(w, sh.kind)
	var reel := w.tune.team_reel if sh.kind == Gamble.TEAM else w.tune.shrine_reel
	_queue_gamble(w, {"t": w.wave_time + reel, "slot": slot, "kind": sh.kind, "outcome": outcome, "stake": sh.cost, "pos": sh.pos})
	w.emit(World.EV_SHRINE, sh.pos.x, sh.pos.y, slot, sh.kind * 16 + outcome)


## What a shrine of `kind` turns up when paid. A party's team shrine draws from the fate deck; a solo run's team
## shrine (and every solo shrine) keeps its weighted roll, so a solo run plays as it always did.
static func _first_draw(w: World, kind: int) -> int:
	if kind == Gamble.TEAM and w.players.size() > 1:
		return Gamble.draw_fate(w.rng, w.fate_cruel)
	return Gamble.roll(w.rng, kind)


## The fates' timers run with the fight; THE WORLD's hearts reach a fallen wizard once she stands.
static func _tick_fates(w: World, dt: float) -> void:
	w.nova_sealed = maxf(0.0, w.nova_sealed - dt)
	w.no_potions = maxf(0.0, w.no_potions - dt)
	w.gem_rush = maxf(0.0, w.gem_rush - dt)
	for slot: int in w.fate_heal.keys():
		var p: World.Player = w.players.get(slot)
		if p == null:
			w.fate_heal.erase(slot)
		elif p.alive:
			p.hp = mini(p.max_hp, p.hp + int(w.fate_heal[slot]))
			w.fate_heal.erase(slot)


## After the Archlich falls the clock stops, but the fates still run out and a paid reel or a chain still lands
## (on the fight's own dt, its times moved back as if the clock ran). Just before the run ends whatever is
## still queued lands at once, so Results hold every fate drawn.
static func _tick_won(w: World, dt: float) -> void:
	_tick_fates(w, dt)
	for g: Dictionary in w._gambles:
		g.t = float(g.t) - dt
	var guard: int = 0
	while not w._gambles.is_empty() and guard < 64 and (w._gambles[0].t <= w.wave_time or w.victory_t <= dt):
		guard += 1
		_resolve_gamble(w, w._gambles.pop_front())


## THE WORLD's hearts held for the fallen, in slot order (for the state hash).
static func held_heals(w: World) -> Array:
	var out: Array = []
	var slots: Array = w.fate_heal.keys()
	slots.sort()
	for s: Variant in slots:
		out.append([int(s), int(w.fate_heal[s])])
	return out


## The fates in the snapshot, only while one is in force (so a run without them hashes as before): "f" = [novas
## sealed s, no potions s, gem rush s, 1 if THE FOOL's double is waiting].
static func snapshot_fates(w: World, snap: Dictionary) -> void:
	if w.nova_sealed > 0.0 or w.no_potions > 0.0 or w.gem_rush > 0.0 or w.fate_twice:
		snap["f"] = PackedFloat32Array([w.nova_sealed, w.no_potions, w.gem_rush, 1.0 if w.fate_twice else 0.0])


## A team fate lands: THE FOOL's double is spent on it, its effect applies, and a WHEEL OF FORTUNE draws more
## fates at once. The rest of a chain is turned one card at a time: each waits tune.fate_chain_gap after the last
## one landed (its "deal"), then spins its reel (EV_SHRINE) and lands like any team fate.
static func _land_fate(w: World, g: Dictionary) -> void:
	var fate := int(g.outcome)
	var times := 1
	if w.fate_twice:
		w.fate_twice = false
		times = 2
	_apply_fate(w, fate, times, w.players.get(g.slot), g.pos)
	w.record.fates.append(fate)
	w.record.use(Gamble.TEAM_OUTCOMES[fate][0], int(g.slot))
	if fate == Gamble.TO_BLESSING or fate == Gamble.TO_CURSE:
		w.record.note(w.wave_time, Results.M_BLESSING if fate == Gamble.TO_BLESSING else Results.M_CURSE, g.slot)
	w.emit(World.EV_FATE, g.pos.x, g.pos.y, fate, g.slot)
	var chain: Array = (g.get("chain", []) as Array).duplicate()
	if fate == Gamble.TO_WHEEL:
		for i: int in range(int(w.tune.fate_wheel_draws) * times):
			chain.append(Gamble.draw_fate(w.rng, w.fate_cruel, false))
	if chain.is_empty():
		return
	_queue_gamble(w, {"t": w.wave_time + w.tune.fate_chain_gap, "slot": g.slot, "kind": Gamble.TEAM, "outcome": chain[0],
		"stake": 0, "pos": g.pos, "chain": chain.slice(1), "deal": true})


static func _queue_gamble(w: World, g: Dictionary) -> void:
	w._gambles.append(g)
	w._gambles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)


## One fate's effect, `times` over (THE FOOL doubles the next one). Once the run is won (the victory countdown) a
## curse or THE EMPEROR does nothing: no elites walk into the banner, no hearts go through the win's invulnerability,
## no chests fall that nobody can open. It is still drawn, shown and kept in Results.
static func _apply_fate(w: World, fate: int, times: int, p: World.Player, pos: Vector2) -> void:
	if w.won and (fate == Gamble.TO_CURSE or fate == Gamble.TO_EMPEROR):
		return
	match fate:
		Gamble.TO_BLESSING:
			var who: World.Player = p if p != null else w.players.values()[0]
			for i in Gamble.BLESSING_LEVELS * times:
				w.gain_xp(who, maxi(1, w.xp_needed() - w.party_xp))
		Gamble.TO_CURSE:
			for i in times:
				for q: World.Player in w.players.values():
					if q.alive:
						q.hp = maxi(1, q.hp - 1)
						q.flash = 0.3
						WorldWaves._spawn_elite(w)
		Gamble.TO_WORLD:
			w.gem_rush = maxf(w.gem_rush, w.tune.fate_world_pull)
			var hearts := int(w.tune.fate_world_hearts) * times
			for q: World.Player in w.players.values():
				if q.alive:
					q.hp = mini(q.max_hp, q.hp + hearts)
				else:
					w.fate_heal[q.slot] = int(w.fate_heal.get(q.slot, 0)) + hearts
		Gamble.TO_EMPEROR:
			for q: World.Player in WorldApprentices.human_seats(w): # an away human too
				for i in times:
					WorldDrops._drop(w, World.PK_CHEST, q.pos, Vector2.from_angle(w.rng.randf() * TAU) * 40.0, w.tune.chest_life,
						int(w.tune.elite_chest_luck))
		Gamble.TO_FOOL:
			w.fate_twice = true
		Gamble.TO_HANGED:
			w.nova_sealed += w.tune.fate_hanged_secs * times
		Gamble.TO_HIEROPHANT:
			w.no_potions += w.tune.fate_hierophant_secs * times


static func _resolve_gamble(w: World, g: Dictionary) -> void:
	var p: World.Player = w.players.get(g.slot)
	var pos: Vector2 = g.pos
	if g.get("deal", false):
		# The next card of a chain is turned: its reel spins, then it lands.
		g.deal = false
		g.t = w.wave_time + w.tune.team_reel
		_queue_gamble(w, g)
		w.emit(World.EV_SHRINE, pos.x, pos.y, int(g.slot) + 8, Gamble.TEAM * 16 + int(g.outcome))
		return
	if g.kind == Gamble.TEAM:
		_land_fate(w, g)
	elif p != null:
		match int(g.outcome):
			Gamble.SO_JACKPOT:
				WorldDrops._drop(w, World.PK_CHEST, pos, Vector2.ZERO, w.tune.chest_life, int(w.tune.boss_chest_luck))
			Gamble.SO_CHEST:
				WorldDrops._drop(w, World.PK_CHEST, pos, Vector2.ZERO, w.tune.chest_life, int(w.tune.elite_chest_luck))
			Gamble.SO_DOUBLE:
				p.gold += g.stake * 2
			Gamble.SO_CURSE:
				if p.alive and not w.won: # like a team curse, it takes nothing once the run is won
					p.hp = maxi(1, p.hp - 1)
					p.flash = 0.3
	if g.kind == Gamble.SOLO and g.outcome == Gamble.SO_JACKPOT:
		w.record.note(w.wave_time, Results.M_JACKPOT, g.slot)
	w.emit(World.EV_GAMBLE, pos.x, pos.y, g.slot, int(g.kind) * 16 + int(g.outcome))

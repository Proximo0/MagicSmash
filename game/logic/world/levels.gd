class_name WorldLevels
extends RefCounted
## Level-ups for World: dealing upgrade cards and applying the picks. Static helpers; the first argument is the World.


## Applies level-up picks and deals cards; the world never waits for them. A wizard with no cards in hand and a
## draw queued is dealt an offer at once (one with nothing left to learn is scored for each queued draw), so cards
## are ready whenever the player wants them. Nothing picks for a player and nothing expires.
static func _update_levelups(w: World, inputs: Dictionary) -> void:
	for p: World.Player in w.players.values():
		if not p.choices.is_empty():
			var inp: PackedFloat32Array = inputs.get(p.slot, PackedFloat32Array())
			if inp.size() >= 8 and int(inp[7]) == p.offer:
				var c := int(inp[6])
				if c >= 0 and c < p.choices.size():
					_pick(w, p, p.choices[c])
					if inp.size() >= 6 and int(inp[5]) > p.last_bomb:
						p.last_bomb = int(inp[5]) # a button that confirms a card is no Nova in the same input
		while p.choices.is_empty() and p.pending > 0:
			_offer(w, p)


static func _offer(w: World, p: World.Player) -> void:
	p.pending -= 1
	p.offer += 1
	p.choices = Upgrades.roll(w.rng, p.upgrades, w.seal_hand if w.seal_hand > 0 else int(w.tune.level_choices), w.slot_cap(), p.banned) # SILENCE
	if p.choices.is_empty():
		var pts := int(w.tune.maxed_level_score)
		p.score += pts
		w.emit(World.EV_SCORE, p.pos.x, p.pos.y - 14, pts, p.slot)


static func _pick(w: World, p: World.Player, idx: int) -> void:
	p.choices = []
	if not Upgrades.take(p.upgrades, idx):
		return
	match idx:
		Upgrades.NOVA:
			p.bombs += 1
		Upgrades.LIFE:
			p.lives += 1
	WorldCasting._refresh_spell(w, p)
	w.emit(World.EV_PICK, p.pos.x, p.pos.y - 14, p.slot, idx)
	if Upgrades.is_evolution(idx):
		w.record.note(w.wave_time, Results.M_EVOLVE, p.slot, idx)
	if p.alive:
		_pick_shock(w, p)


## Taking a card pushes every enemy near the wizard away at once (no damage), so drawing mid-fight is safe.
static func _pick_shock(w: World, p: World.Player) -> void:
	var radius := w.tune.pick_shock_radius
	if radius <= 0.0:
		return
	for e: World.Enemy in w.enemies:
		if e.dead or e.entering:
			continue
		var to := e.pos - p.pos
		if to.length() <= radius:
			var dir := to.normalized() if to.length() > 0.01 else Vector2.RIGHT
			e.knock += dir * w.tune.pick_shock_push * WorldEnemies._heft(w, e)

class_name WorldLevels
extends RefCounted
## Level-ups for World: dealing upgrade cards and applying the picks, redraws and banishes, the slot cap and the
## party tome. Static helpers; the first argument is the World.

## The pickup a party tome is.
const PARTY_TOME := World.PK_TOME_PARTY
## The chance an elite drops one, and an urn holds one, is tune.party_tome_elite and tune.party_tome_urn (each
## Lich always drops one).


## Applies level-up picks, redraws and banishes, and deals cards; the world never waits for them. A wizard with no
## cards in hand and a draw queued is dealt an offer at once (one with nothing left to learn is scored for each
## queued draw), so cards are ready whenever the player wants them. Nothing picks for a human player and nothing
## expires; an apprentice (Player.ai) takes the card pick_score likes best at once.
static func _update_levelups(w: World, inputs: Dictionary) -> void:
	if w._tick == 0:
		_shop_start(w)
	_update_slots(w)
	for p: World.Player in w.players.values():
		if not p.choices.is_empty():
			var inp: PackedFloat32Array = inputs.get(p.slot, PackedFloat32Array())
			if p.ai and not p.away: # an away human keeps her draws for when she is back
				_pick(w, p, p.choices[Upgrades.best_pick(p.upgrades, p.choices)])
			elif inp.size() >= 8 and int(inp[7]) == p.offer and int(inp[6]) != -1:
				var c := int(inp[6])
				if c >= 0 and c < p.choices.size():
					_pick(w, p, p.choices[c])
					if inp.size() >= 6 and int(inp[5]) > p.last_bomb:
						p.last_bomb = int(inp[5]) # a button that confirms a card is no Nova in the same input
				elif c == Upgrades.REDRAW_INPUT:
					_redraw(w, p)
				elif c >= Upgrades.BANISH_INPUT and c - Upgrades.BANISH_INPUT < p.choices.size():
					_banish(w, p, c - Upgrades.BANISH_INPUT)
				else:
					_reissue(w, p)
		while p.choices.is_empty() and p.pending > 0:
			_offer(w, p)


## The slots every wizard has: Upgrades.SLOTS_EARLY until the first boss falls (the Bone Chandelier at 5:00), then SLOTS_LATE. The first call of
## a run (World._init, before apply_meta) also hands every wizard the run's redraws and banishes; the shop's come on
## the first step (_shop_start).
static func _update_slots(w: World) -> void:
	var cap := Upgrades.SLOTS_LATE if w.liches_slain > 0 else Upgrades.SLOTS_EARLY
	if w.slots == cap:
		return
	if w.slots == Upgrades.UNCAPPED:
		for p: World.Player in w.players.values():
			p.redraws = Upgrades.REDRAWS
			p.banishes = Upgrades.BANISHES
	w.slots = cap
	w.emit(World.EV_SLOTS, 0, 0, cap.x, cap.y)


## The run's first step hands out what the table bought in the shop (World.apply_meta came before it; every wizard
## gets the same): THE SECOND GLANCE's and THE BLACK RIBBON's redraws and banishes on top of those World._init's
## _update_slots gave, and THE HEAD START: the party starts at level 1 + meta_start_level and every wizard has that
## many hands to draw, the first dealt on this very step, while the intro holds (_intro_held). No XP, no stats; the
## lead lasts, because xp_needed does not price those levels (World.head_start_levels).
static func _shop_start(w: World) -> void:
	for p: World.Player in w.players.values():
		p.redraws += w.meta_redraws
		p.banishes += w.meta_banishes
	if w.meta_start_level <= 0:
		return
	w.party_level += w.meta_start_level
	w.head_start_levels = w.meta_start_level
	for p: World.Player in w.players.values():
		p.level = w.party_level
		p.pending += w.meta_start_level
	w.record.use("shop_start_level")


## True while THE HEAD START holds the intro (World.step): the run has one, fewer than tune.head_start_wait seconds
## have passed, and a living wizard at her seat still has a card in hand or a draw queued. A fallen wizard, an away
## human (her draws wait for her) or one who left holds nothing; whoever has not drawn when the door opens keeps
## her draws. Without a head start it is always false, so the intro is as long as ever.
static func _intro_held(w: World) -> bool:
	if w.meta_start_level <= 0 or w.time >= w.tune.head_start_wait:
		return false
	for p: World.Player in w.players.values():
		if p.alive and not p.away and (not p.choices.is_empty() or p.pending > 0):
			return true
	return false


## A new hand: up to tune.level_choices cards the wizard can learn, topped up with Minor Arcana when fewer are left.
static func _offer(w: World, p: World.Player) -> void:
	p.pending -= 1
	_deal(w, p)


static func _deal(w: World, p: World.Player) -> void:
	p.offer += 1
	var n := w.seal_hand if w.seal_hand > 0 else int(w.tune.level_choices) # SILENCE: a smaller hand
	p.choices = Upgrades.roll(w.rng, p.upgrades, n, w.slot_cap(), p.banned)
	Upgrades.minor_fill(w.rng, p.choices, n)
	if p.choices.is_empty():
		var pts := int(w.tune.maxed_level_score)
		p.score += pts
		w.emit(World.EV_SCORE, p.pos.x, p.pos.y - 14, pts, p.slot)


## The same hand again under a new offer id: the answer to an input the host refuses (a banish of a Minor
## Arcana card or with none left, a redraw with none left, a card outside the hand). A client sends one answer per
## offer, so without a new id it would wait on that offer for good; the cards stay, so it is no free redraw.
static func _reissue(_w: World, p: World.Player) -> void:
	p.offer += 1


## Swaps the hand for a new one (a new offer id), using up one of the wizard's redraws.
static func _redraw(w: World, p: World.Player) -> void:
	if p.redraws <= 0:
		_reissue(w, p)
		return
	p.redraws -= 1
	_deal(w, p)
	w.emit(World.EV_REDRAW, p.pos.x, p.pos.y - 14, p.slot, 0)


## Card `c` leaves this wizard's pool for the run, using up one banish, and the hand is redrawn for free. Minor
## Arcana are never in the pool and cannot be banished.
static func _banish(w: World, p: World.Player, c: int) -> void:
	var idx: int = p.choices[c]
	if p.banishes <= 0 or Upgrades.kind(idx) == Upgrades.MINOR:
		_reissue(w, p)
		return
	p.banishes -= 1
	p.banned[idx] = true
	_deal(w, p)
	w.emit(World.EV_BANISH, p.pos.x, p.pos.y - 14, p.slot, idx)


## Takes card `idx`. A card that is no longer learnable (a tome filled its slot or maxed its spell while it waited
## in hand) deals a fresh hand instead, keeping the level.
static func _pick(w: World, p: World.Player, idx: int) -> void:
	if Upgrades.kind(idx) != Upgrades.MINOR and not Upgrades.available(p.upgrades, idx, w.slot_cap(), p.banned):
		_deal(w, p)
		return
	p.choices = []
	if not Upgrades.take(p.upgrades, idx):
		return
	match idx:
		Upgrades.NOVA, Upgrades.M_SWORDS:
			p.bombs += 1
		Upgrades.LIFE:
			p.lives += 1
		Upgrades.M_CUPS:
			if p.alive: # a fallen wizard rises with hearts of her own; the card would be lost on her
				p.hp = mini(p.max_hp, p.hp + 1)
		Upgrades.M_PENTACLES:
			var gold: float = Upgrades.value(p.upgrades, idx, 0.0) * (1.0 + p.armor[Loot.ST_GREED] + w.meta_gold)
			p.gold += gold
			w.record.add(p.slot, "gold", gold)
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


## Drops a party tome at `at` (each Lich), or with chance `chance` (elites, urns). Nothing (and no roll) while
## tune.floor_tomes is on: spell tomes fall instead.
static func _drop_party_tome(w: World, at: Vector2, chance: float = 1.0) -> void:
	if w.tune.floor_tomes >= 0.5:
		return
	if chance < 1.0 and w.rng.randf() >= chance:
		return
	WorldDrops._drop(w, PARTY_TOME, at, Vector2(0, -40), w.tune.chest_life)


## A party tome read by anyone: every wizard (up, down or out) levels one random spell it owns that can still
## level (not maxed, not banished); a wizard with none gets nothing.
static func _read_party_tome(w: World) -> void:
	for p: World.Player in w.players.values():
		var can: Array[int] = []
		for sp: int in Spells.COUNT:
			var idx := Upgrades.weapon_entry(sp)
			if Upgrades.weapon_level(p.upgrades, sp) > 0 and Upgrades.available(p.upgrades, idx, w.slot_cap(), p.banned):
				can.append(idx)
		if can.is_empty():
			continue
		var idx: int = can[w.rng.randi() % can.size()]
		Upgrades.take(p.upgrades, idx)
		WorldCasting._refresh_spell(w, p)
		w.emit(World.EV_PICK, p.pos.x, p.pos.y - 14, p.slot, idx)

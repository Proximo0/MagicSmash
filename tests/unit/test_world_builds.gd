extends TestCase
## World builds: spell and passive slots, pairs and evolutions, redraws and banishes, the Minor Arcana, the party
## tome, and the casting fixes of job E (game/logic/upgrades.gd, game/logic/world/levels.gd, world/casting.gd).

const DT: float = 1.0 / 60.0


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _player(w: World, slot: int = 0) -> World.Player:
	return w.players[slot] as World.Player


func _pick_input(p: World.Player, card: int) -> Dictionary:
	return {p.slot: PackedFloat32Array([0, 0, 0, 0, 0, 0, card, p.offer])}


## A world one tick in (the slot cap and the run's redraws and banishes are set) with a hand dealt to slot 0.
func _dealt(seed_value: int = 3) -> World:
	var w := World.new([0], seed_value)
	w.step(DT, {})
	_player(w).pending = 1
	w.step(DT, {})
	return w


func test_catalogue_columns() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	assert_true(p.banned.is_empty())
	assert_eq(Upgrades.slots_used(p.upgrades), Vector2i(1, 0), "the starting spell takes one spell slot")
	assert_eq(Upgrades.slot_ids(p.upgrades, Upgrades.SPELL), [Upgrades.weapon_entry(Wizards.start_spell(0))] as Array[int])
	assert_eq(Upgrades.kind(Upgrades.POWER), Upgrades.PASSIVE)
	assert_eq(Upgrades.kind(Upgrades.NOVA), Upgrades.PASSIVE)
	for sp: int in Spells.COUNT:
		assert_eq(Upgrades.spell_of(Upgrades.weapon_entry(sp)), sp)
		if not Spells.has_evolution(sp):
			assert_eq(Upgrades.evo_entry(sp), -1)
			assert_eq(Upgrades.partner_row(sp), -1)
			continue
		assert_eq(Upgrades.kind(Upgrades.evo_entry(sp)), Upgrades.EVOLUTION)
		assert_eq(Upgrades.evolves(Upgrades.evo_entry(sp)), Upgrades.weapon_entry(sp))
		for evo: int in range(1, Spells.evolutions(sp) + 1):
			assert_eq(Upgrades.kind(Upgrades.partner_row(sp, evo)), Upgrades.PASSIVE)
			assert_eq(Upgrades.key(Upgrades.partner_row(sp, evo)), Spells.passive_partner(sp, evo))
	for m: int in Upgrades.MINORS:
		assert_eq(Upgrades.kind(m), Upgrades.MINOR)
	assert_eq(Upgrades.evolves(Upgrades.POWER), -1)


func test_slots_are_three_until_the_first_lich_falls_then_four() -> void:
	var w := World.new([0, 1], 3)
	w.step(DT, {})
	assert_eq(w.slot_cap(), Upgrades.SLOTS_EARLY)
	assert_eq(w.snapshot()["w"][World.W_CAP_SPELLS], float(Upgrades.SLOTS_EARLY.x))
	for p: World.Player in w.players.values():
		assert_eq(p.redraws, Upgrades.REDRAWS)
		assert_eq(p.banishes, Upgrades.BANISHES)
	w.take_events()
	w.liches_slain = 1
	w.step(DT, {})
	assert_eq(w.slot_cap(), Upgrades.SLOTS_LATE)
	var seen := false
	for ev: Array in w.take_events():
		if ev[0] == World.EV_SLOTS:
			seen = ev[3] == Upgrades.SLOTS_LATE.x and ev[4] == Upgrades.SLOTS_LATE.y
	assert_true(seen, "no EV_SLOTS with the new cap")
	assert_eq(_player(w).redraws, Upgrades.REDRAWS, "the Lich does not hand out more redraws")


func test_a_full_spell_slot_offers_no_new_spell() -> void:
	var lv := {Upgrades.W_ARCANE: 1, Upgrades.W_FIRE: 1, Upgrades.W_RUNE: 1}
	for s: int in range(40):
		for idx: int in Upgrades.roll(_rng(s), lv, 3, Upgrades.SLOTS_EARLY):
			if Upgrades.kind(idx) == Upgrades.SPELL:
				assert_true(lv.has(idx), "a fourth spell offered with three slots")
	assert_true(Upgrades.available(lv, Upgrades.W_STAR, Upgrades.SLOTS_LATE), "the fourth slot opens after the Lich")


func test_the_last_slot_is_kept_for_a_partner() -> void:
	# ARCANE BOLT's arcana is THE MAGICIAN: with FIREBALL and FROST FAN owned and THE MAGICIAN held, the third spell
	# slot takes only a spell that completes a pair (ARCANE BOLT).
	var lv := {Upgrades.W_FIRE: 1, Upgrades.W_FROST: 1, Upgrades.QUICK: 1}
	assert_true(Upgrades.pairs_with(lv, Upgrades.W_ARCANE))
	assert_false(Upgrades.pairs_with(lv, Upgrades.W_RUNE))
	assert_true(Upgrades.available(lv, Upgrades.W_ARCANE, Upgrades.SLOTS_EARLY))
	assert_false(Upgrades.available(lv, Upgrades.W_RUNE, Upgrades.SLOTS_EARLY), "a non-partner took the last slot")
	assert_true(Upgrades.available(lv, Upgrades.W_RUNE, Upgrades.SLOTS_LATE), "with two slots free any spell goes")
	# With ARCANE BOLT's evolutions banished, nothing can complete a pair and the slot is free again.
	var banned := {Upgrades.E_ARCANE: true, Upgrades.E_LODESTAR: true}
	assert_true(Upgrades.available(lv, Upgrades.W_RUNE, Upgrades.SLOTS_EARLY, banned))
	# The last arcana slot is kept the same way: FIREBALL wants THE TOWER (THUNDERFIRE).
	var pa := {Upgrades.W_FIRE: 1, Upgrades.POWER: 1, Upgrades.QUICK: 1}
	assert_true(Upgrades.available(pa, Upgrades.NOVA, Upgrades.SLOTS_EARLY))
	assert_false(Upgrades.available(pa, Upgrades.SWIFT, Upgrades.SLOTS_EARLY), "a non-partner took the last arcana slot")
	assert_true(Upgrades.available(pa, Upgrades.SWIFT, Upgrades.SLOTS_EARLY, {Upgrades.E_FIRE: true, Upgrades.E_GREEK: true}))
	assert_false(Upgrades.available(pa.merged({Upgrades.NOVA: 1}), Upgrades.REGEN, Upgrades.SLOTS_EARLY))


func test_a_partner_weighs_four_times_in_a_roll() -> void:
	var lv := {Upgrades.NOVA: 1} # THE TOWER held: FIREBALL completes THUNDERFIRE's pair
	assert_eq(Upgrades.roll_weight(lv, Upgrades.W_FIRE), Upgrades.PARTNER_WEIGHT * float(Upgrades.CATALOG[Upgrades.W_FIRE][Upgrades.C_WEIGHT]))
	assert_eq(Upgrades.roll_weight(lv, Upgrades.W_RUNE), float(Upgrades.CATALOG[Upgrades.W_RUNE][Upgrades.C_WEIGHT]))
	assert_eq(Upgrades.roll_weight({Upgrades.W_FIRE: 1}, Upgrades.NOVA), Upgrades.PARTNER_WEIGHT * float(Upgrades.CATALOG[Upgrades.NOVA][Upgrades.C_WEIGHT]))
	var fire := 0
	var rune := 0
	for s: int in range(400):
		var hand := Upgrades.roll(_rng(s), lv, 1, Upgrades.SLOTS_EARLY)
		fire += int(hand[0] == Upgrades.W_FIRE)
		rune += int(hand[0] == Upgrades.W_RUNE)
	assert_true(fire > rune * 3, "partner drawn %d times, another spell %d" % [fire, rune])


func test_redraw_swaps_the_hand_and_counts_down() -> void:
	var w := _dealt()
	var p := _player(w)
	var offer := p.offer
	var hands := {p.choices.duplicate(): true}
	for k: int in range(Upgrades.REDRAWS):
		w.step(DT, _pick_input(p, Upgrades.REDRAW_INPUT))
		assert_eq(p.offer, offer + k + 1, "a redraw deals a new offer")
		assert_eq(p.choices.size(), 3)
		hands[p.choices.duplicate()] = true
	assert_eq(p.redraws, 0)
	assert_true(hands.size() > 1, "the redraws dealt the same hand every time")
	var now := p.offer
	var last := p.choices.duplicate()
	w.step(DT, _pick_input(p, Upgrades.REDRAW_INPUT))
	assert_eq(p.offer, now + 1, "a refused redraw is re-issued under a new offer")
	assert_eq(p.choices, last, "a redraw with none left changed the hand")
	assert_eq(p.pending, 0, "a redraw used up a level")


func test_banish_removes_a_card_from_the_pool_and_redraws() -> void:
	var w := _dealt(5)
	var p := _player(w)
	var gone: int = p.choices[1]
	w.step(DT, _pick_input(p, Upgrades.BANISH_INPUT + 1))
	assert_true(p.banned.has(gone))
	assert_eq(p.banishes, Upgrades.BANISHES - 1)
	assert_eq(p.redraws, Upgrades.REDRAWS, "a banish's redraw is free")
	assert_eq(p.choices.size(), 3)
	for s: int in range(60):
		assert_false(gone in Upgrades.roll(_rng(s), p.upgrades, 3, w.slot_cap(), p.banned), "a banished card came back")
	w.step(DT, _pick_input(p, Upgrades.BANISH_INPUT + 0))
	w.step(DT, _pick_input(p, Upgrades.BANISH_INPUT + 0))
	assert_eq(p.banishes, 0)
	assert_eq(p.banned.size(), Upgrades.BANISHES, "banished past the run's banishes")


func test_minor_arcana_fill_a_short_hand() -> void:
	var w := World.new([0], 3)
	w.step(DT, {})
	var p := _player(w)
	for i: int in range(Upgrades.count()):
		if Upgrades.kind(i) != Upgrades.MINOR:
			p.upgrades[i] = Upgrades.max_level(i)
	p.upgrades[Upgrades.POWER] = Upgrades.max_level(Upgrades.POWER) - 1
	p.pending = 1
	w.step(DT, {})
	assert_eq(p.choices.size(), 3)
	assert_true(Upgrades.POWER in p.choices)
	var minors := 0
	for c: int in p.choices:
		minors += int(Upgrades.kind(c) == Upgrades.MINOR)
	assert_eq(minors, 2, "two Minor Arcana top up a hand of one")
	# Each one does its thing, as often as it is taken.
	var hp := p.hp
	p.hp = 1
	WorldLevels._pick(w, p, Upgrades.M_CUPS)
	assert_eq(p.hp, 2, "CUPS heals a heart")
	p.hp = hp
	var gold := p.gold
	WorldLevels._pick(w, p, Upgrades.M_PENTACLES)
	assert_true(p.gold > gold, "PENTACLES pays gold")
	var bombs := p.bombs
	WorldLevels._pick(w, p, Upgrades.M_SWORDS)
	WorldLevels._pick(w, p, Upgrades.M_SWORDS)
	assert_eq(p.bombs, bombs + 2, "SWORDS adds a nova charge each time")
	var before := Upgrades.damage_mul(p.upgrades)
	WorldLevels._pick(w, p, Upgrades.M_WANDS)
	assert_near(Upgrades.damage_mul(p.upgrades), before * 1.03, 0.0001, "WANDS adds 3% damage")
	assert_false(Upgrades.available(p.upgrades, Upgrades.M_WANDS), "a Minor Arcana card is never rolled")


func test_spell_tomes_obey_the_slots() -> void:
	var w := World.new([0], 3, null, {0: 0})
	w.step(DT, {})
	var p := _player(w)
	p.upgrades[Upgrades.W_FIRE] = 1
	p.upgrades[Upgrades.W_STORM] = 1
	var tome := World.Pickup.new()
	tome.kind = World.PK_TOME_FROST
	var score := p.score
	w._collect(p, tome)
	assert_eq(Upgrades.weapon_level(p.upgrades, World.SP_FROST), 0, "a tome took a fourth spell slot")
	assert_eq(p.score, score + 500, "a tome that cannot be learned is worth points")


func test_a_chest_tome_skips_banished_and_maxed_spells() -> void:
	var w := World.new([0], 3, null, {0: 0})
	w.step(DT, {})
	var p := _player(w)
	p.upgrades[Upgrades.W_FIRE] = 1
	p.banned[Upgrades.W_FIRE] = true
	p.upgrades[Upgrades.W_ARCANE] = Spells.MAX_LEVEL
	# Open many chests (some hold tomes): neither spell may rise.
	for _s: int in range(200):
		var k := World.Pickup.new()
		k.kind = World.PK_CHEST
		w._open_chest(p, k)
	assert_eq(Upgrades.weapon_level(p.upgrades, World.SP_FIRE), 1, "a chest tome levelled a banished spell")
	assert_eq(Upgrades.weapon_level(p.upgrades, World.SP_ARCANE), Spells.MAX_LEVEL)


func _tomes_tune(floor_tomes: float) -> Tuning:
	var t := Tuning.new()
	t.floor_tomes = floor_tomes
	return t


## tune.floor_tomes 1 (the old rule): spell tomes fall from kills and powerups as before, and no party tome drops
## from a Lich, an elite or an urn.
func test_floor_tomes_on_keeps_spell_tomes_and_no_party_tome() -> void:
	var w := World.new([0], 3, _tomes_tune(1.0))
	w.step(DT, {})
	for s: int in range(300):
		var e: World.Enemy = w.spawn_enemy(World.ORC if s % 2 == 0 else World.GOBLIN, 0, Vector2(120, 120))
		w._kill_enemy(e, 0)
		WorldWaves._spawn_random_powerup(w)
	var tomes := 0
	for k: World.Pickup in w.pickups:
		tomes += int(k.kind in World.TOMES)
		assert_true(k.kind != World.PK_TOME_PARTY, "a party tome fell with floor tomes on")
	assert_true(tomes > 10, "only %d spell tomes fell" % tomes)
	w.pickups.clear()
	var lich: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(120, 120))
	w._kill_enemy(lich, 0)
	for s: int in range(40):
		var el: World.Enemy = w.spawn_enemy(World.GOBLIN, 0, Vector2(120, 120))
		el.elite = true
		w._kill_enemy(el, 0)
		WorldDrops._break_urn(w, Vector2(100, 100))
	for k: World.Pickup in w.pickups:
		assert_true(k.kind != World.PK_TOME_PARTY, "a party tome dropped with floor tomes on")


## tune.floor_tomes 0 (the default): each Lich drops a party tome, and so do party_tome_elite of the elites.
func test_floor_tomes_off_a_lich_and_elites_drop_party_tomes() -> void:
	var t := _tomes_tune(0.0)
	t.party_tome_elite = 0.25 # a chance below 1, so the roll is tested
	var w := World.new([0], 3, t)
	w.step(DT, {})
	var lich: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(120, 120))
	w._kill_enemy(lich, 0)
	var n := 0
	for k: World.Pickup in w.pickups:
		n += int(k.kind == World.PK_TOME_PARTY)
	assert_eq(n, 1, "a Lich drops one party tome")
	w.pickups.clear()
	for s: int in range(200):
		var el: World.Enemy = w.spawn_enemy(World.GOBLIN, 0, Vector2(120, 120))
		el.elite = true
		w._kill_enemy(el, 0)
	n = 0
	for k: World.Pickup in w.pickups:
		n += int(k.kind == World.PK_TOME_PARTY)
	assert_true(n > 25 and n < 75, "%d party tomes from 200 elites" % n)


func test_no_spell_tomes_fall_and_a_party_tome_levels_every_wizard() -> void:
	var w := World.new([0, 1, 2], 3, _tomes_tune(0.0), {0: 0, 1: 1, 2: 2})
	w.step(DT, {})
	for s: int in range(300):
		var e: World.Enemy = w.spawn_enemy(World.ORC if s % 2 == 0 else World.GOBLIN, 0, Vector2(120, 120))
		w._kill_enemy(e, 0)
		WorldWaves._spawn_random_powerup(w)
	for k: World.Pickup in w.pickups:
		assert_false(k.kind in World.TOMES, "a spell tome fell")
	var p0 := _player(w, 0)
	var p2 := _player(w, 2)
	p2.upgrades[Upgrades.weapon_entry(Wizards.start_spell(2))] = Spells.MAX_LEVEL
	var before0 := Upgrades.weapon_level(p0.upgrades, Wizards.start_spell(0))
	w.pickups.clear()
	WorldLevels._drop_party_tome(w, Vector2(100, 100))
	assert_eq(w.pickups.size(), 1)
	w._collect(_player(w, 1), w.pickups[0])
	assert_eq(Upgrades.weapon_level(p0.upgrades, Wizards.start_spell(0)), before0 + 1, "the tome skipped a wizard")
	assert_eq(Upgrades.weapon_level(_player(w, 1).upgrades, Wizards.start_spell(1)), 2)
	assert_eq(Upgrades.weapon_level(p2.upgrades, Wizards.start_spell(2)), Spells.MAX_LEVEL, "levelled past max")
	var n := 0
	for s: int in range(400):
		w.pickups.clear()
		WorldLevels._drop_party_tome(w, Vector2(100, 100), 0.25)
		n += w.pickups.size()
	assert_true(n > 60 and n < 140, "a 25%% tome dropped %d times in 400" % n)


func test_pick_score_prefers_evolutions_then_pairs() -> void:
	var lv := {Upgrades.W_FIRE: 5, Upgrades.NOVA: 1}
	assert_true(Upgrades.pick_score(lv, Upgrades.E_FIRE) > Upgrades.pick_score(lv, Upgrades.W_FIRE))
	var lone := {Upgrades.W_FIRE: 2}
	assert_true(Upgrades.pick_score(lone, Upgrades.NOVA) > Upgrades.pick_score(lone, Upgrades.W_FIRE), "a partner beats a level")
	assert_true(Upgrades.pick_score(lone, Upgrades.W_FIRE) > Upgrades.pick_score(lone, Upgrades.W_RUNE))
	assert_true(Upgrades.pick_score(lone, Upgrades.W_RUNE) > Upgrades.pick_score(lone, Upgrades.SWIFT))
	assert_true(Upgrades.pick_score(lone, Upgrades.SWIFT) > Upgrades.pick_score(lone, Upgrades.M_WANDS))
	var hand: Array[int] = [Upgrades.SWIFT, Upgrades.NOVA, Upgrades.M_CUPS]
	assert_eq(Upgrades.best_pick(lone, hand), 1)


func test_an_apprentice_takes_its_card_at_once() -> void:
	var w := World.new([0], 3, null, {}, {0: {"ai": true}})
	w.step(DT, {})
	var p := _player(w)
	p.pending = 1
	w.step(DT, {})
	w.step(DT, {})
	assert_true(p.choices.is_empty(), "an apprentice held its cards")
	assert_true(Upgrades.slots_used(p.upgrades).x + Upgrades.slots_used(p.upgrades).y >= 1)


# ------------------------------------------------------------------ casting fixes (audit E4, E5, E6) ---

func _still(w: World, type: int, at: Vector2) -> World.Enemy:
	var e: World.Enemy = w.spawn_enemy(type, 0, at)
	e.entering = false
	e.spd = 0.0
	return e


## E4: an enemy touching the wizard, inside the staff's tip, is struck by chain lightning.
func test_chain_lightning_strikes_an_enemy_touching_the_wizard() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	p.upgrades = {Upgrades.W_STORM: 1}
	p.invuln = 99.0
	var e := _still(w, World.ORC, p.pos + Vector2(6, -7))
	var hp := e.hp
	for _i: int in range(3):
		w.step(DT, {0: PackedFloat32Array([0, 0, 1, 0, 0, 0])})
	assert_true(e.hp < hp, "chain lightning missed an enemy at the wizard's side")


## E5: auto-aim, chain lightning and homing stars ignore a faded wraith, which nothing can hurt.
func test_targeting_skips_a_faded_wraith() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	var wr := _still(w, World.WRAITH, p.pos + Vector2(30, 0))
	wr.state = 1
	assert_eq(WorldCasting._nearest_enemy(w, p.pos, 200.0), null, "auto-aim picked a faded wraith")
	var gob := _still(w, World.GOBLIN, p.pos + Vector2(60, 0))
	var hp := gob.hp
	var tip := p.pos + Vector2(9, -7)
	WorldCastChain._chain_lightning(w, 0, tip, Vector2.RIGHT, 3, 0.5, 1.0, {})
	assert_true(gob.hp < hp, "the chain stopped on a faded wraith")
	gob.dead = true
	w._build_grid()
	var s := World.Shot.new()
	s.spell = World.SP_STAR
	s.pos = p.pos + Vector2(20, 30)
	s.vel = Vector2(0, 175)
	s.life = 2.0
	w.shots.append(s)
	WorldCastBolts._update_shots(w, DT)
	assert_eq(s.vel, Vector2(0, 175), "a star turned toward a faded wraith")


## A homing star looks near first (WorldCastBolts._homing_target): in crowds thin and thick, from anywhere in the
## arena, it picks the foe one wide search of its whole reach would, and nobody when nobody is in reach.
func test_a_homing_shot_finds_the_foe_a_wide_search_would() -> void:
	var home := Spells.bolt_value(World.SP_STAR, "home", 0, 0.0)
	assert_true(home > Spells.HOME_RING, "STARFALL no longer homes past the first ring: nothing is tested")
	var rng := _rng(11)
	for crowd: int in [0, 1, 3, 12, 60, 240]:
		var w := World.new([0], 3)
		for _i: int in range(crowd):
			var e := _still(w, World.GOBLIN, Vector2(rng.randf_range(G.ARENA.position.x, G.ARENA.end.x),
				rng.randf_range(G.ARENA.position.y, G.ARENA.end.y)))
			if rng.randf() < 0.1:
				e.dead = true
		w._build_grid()
		for _i: int in range(40):
			var s := World.Shot.new()
			s.spell = World.SP_STAR
			s.pos = Vector2(rng.randf_range(G.ARENA.position.x, G.ARENA.end.x), rng.randf_range(G.ARENA.position.y, G.ARENA.end.y))
			for e: World.Enemy in w.enemies:
				if rng.randf() < 0.05:
					s.hits[e.id] = true
			var want: World.Enemy = null
			var bd := home
			for e: World.Enemy in w._query(s.pos, home):
				if s.hits.has(e.id):
					continue
				var d := e.pos.distance_to(s.pos)
				if d < bd:
					bd = d
					want = e
			assert_eq(WorldCastBolts._homing_target(w, s, home), want, "a crowd of %d: another foe than the wide search's" % crowd)


## One wizard alone for as long as a test wants: the intro never ends, so no horde, powerup or shrine comes.
func _quiet(upgrades: Dictionary, tuning: Tuning = null) -> World:
	var w := World.new([0], 3, tuning)
	w.phase_t = 1e9
	_player(w).upgrades = upgrades
	return w


func _cast_ticks(w: World, ticks: int, aim: bool) -> Array[int]:
	var out: Array[int] = []
	var inp := {0: PackedFloat32Array([0, 0, 1 if aim else 0, 0, 0, 0])}
	for i: int in range(ticks):
		w.step(DT, inp)
		for ev: Array in w.take_events():
			if ev[0] == World.EV_CAST:
				out.append(i)
	return out


## E6: a cooldown is not rounded up to whole ticks, so every level-up's shorter cooldown casts more often; the
## first cast after waiting is on time, and the one after it a full cooldown later.
func test_cooldowns_keep_their_fractions() -> void:
	var w := _quiet({Upgrades.W_ARCANE: 4})
	var cd := Spells.cooldown(World.SP_ARCANE, 4, 0)
	var n := _cast_ticks(w, 600, true).size()
	assert_true(n >= int(10.0 / cd) and n <= int(10.0 / cd) + 1, "%d casts in 10 s at a %.2f s cooldown" % [n, cd])
	assert_true(_cast_ticks(_quiet({Upgrades.W_ARCANE: 3}), 600, true).size() < n, "level 4 casts no more often than level 3")
	# Wait with no aim (the timer runs out), then aim: a cast at once, the next a full cooldown later.
	_cast_ticks(w, 60, false)
	var after := _cast_ticks(w, 30, true)
	assert_eq(after[0], 0, "the first cast after waiting is late")
	assert_eq(after[1] - after[0], ceili(cd / DT - 0.0001), "the second cast after waiting came early")


func test_cast_rate_bonuses_stop_at_the_floor() -> void:
	# The floor binds the wizard's own bonuses; the global spell_cd_mul applies on top of it.
	var t := Tuning.new()
	t.spell_cd_mul = 1.5
	var w := _quiet({Upgrades.W_FIRE: 1}, t)
	_player(w).armor[Loot.ST_FOCUS] = 0.95
	var cd := Spells.cooldown(World.SP_FIRE, 1, 0) * Spells.CAST_FLOOR * t.spell_cd_mul
	var n := _cast_ticks(w, 600, true).size()
	assert_true(n >= int(10.0 / cd), "%d casts: slower than the floor times spell_cd_mul" % n)
	assert_true(n <= int(10.0 / cd) + 1, "%d casts: below the cast floor" % n)


# ------------------------------------------------------------------ review fixes ---

## A hand of three known cards under offer `offer`.
func _hand(w: World, cards: Array[int]) -> World.Player:
	var p := _player(w)
	p.choices = cards
	return p


func _send(w: World, p: World.Player, card: int, offer: int = -99) -> void:
	w.step(DT, {p.slot: PackedFloat32Array([0, 0, 0, 0, 0, 0, card, p.offer if offer == -99 else offer])})


## A refused banish or redraw re-issues the same hand under a new offer id (never a free redraw), so a client is
## never stuck on an offer it already answered.
func test_a_refused_banish_or_redraw_reissues_the_same_hand() -> void:
	var w := _dealt()
	var hand: Array[int] = [Upgrades.M_CUPS, Upgrades.POWER, Upgrades.QUICK]
	var p := _hand(w, hand.duplicate())
	var offer := p.offer
	_send(w, p, Upgrades.BANISH_INPUT + 0) # a Minor Arcana card cannot be banished
	assert_eq(p.offer, offer + 1, "a refused banish left the wizard on the same offer")
	assert_eq(p.choices, hand, "a refused banish changed the hand")
	assert_eq(p.banishes, Upgrades.BANISHES)
	assert_eq(p.redraws, Upgrades.REDRAWS)
	p.banishes = 0
	_send(w, p, Upgrades.BANISH_INPUT + 1) # none left
	assert_eq(p.offer, offer + 2)
	assert_eq(p.choices, hand)
	assert_false(p.banned.has(Upgrades.POWER))
	p.redraws = 0
	_send(w, p, Upgrades.REDRAW_INPUT) # none left
	assert_eq(p.offer, offer + 3)
	assert_eq(p.choices, hand)
	# The card can still be taken under the new offer.
	_send(w, p, 1)
	assert_eq(Upgrades.level_of(p.upgrades, Upgrades.POWER), 1)


func test_malformed_card_fields() -> void:
	var w := _dealt()
	var hand: Array[int] = [Upgrades.POWER, Upgrades.QUICK, Upgrades.SWIFT]
	var p := _hand(w, hand.duplicate())
	var offer := p.offer
	_send(w, p, -1)
	assert_eq(p.offer, offer, "-1 (no card) did something")
	_send(w, p, 15) # a banish of card 5: outside the hand
	assert_eq(p.offer, offer + 1, "a banish outside the hand was not re-issued")
	assert_eq(p.choices, hand)
	assert_eq(p.banishes, Upgrades.BANISHES)
	_send(w, p, -3)
	assert_eq(p.offer, offer + 2, "field 6 = -3 was not re-issued")
	assert_eq(p.choices, hand)
	_send(w, p, 3)
	assert_eq(p.offer, offer + 3, "card 3 of a hand of 3 was not re-issued")
	# An old offer id does nothing at all, whatever it asks.
	for card: int in [Upgrades.REDRAW_INPUT, Upgrades.BANISH_INPUT + 0, 0, 15]:
		_send(w, p, card, p.offer - 1)
	assert_eq(p.offer, offer + 3, "a stale offer id was acted on")
	assert_eq(p.choices, hand)
	assert_eq(p.redraws, Upgrades.REDRAWS)
	assert_eq(p.banishes, Upgrades.BANISHES)
	assert_true(p.banned.is_empty())


## A card that stopped being learnable while it waited in hand (a tome filled the slot, or raised the spell to
## its max) deals a fresh hand instead of breaking the cap or losing the level.
func test_a_card_that_went_stale_deals_a_fresh_hand() -> void:
	var w := World.new([0], 3, null, {0: 0})
	w.step(DT, {})
	var p := _player(w)
	# Arcane (start) and Frost owned; Star pairs with Arcane, Rune pairs with nothing.
	p.upgrades[Upgrades.W_FROST] = 1
	var hand: Array[int] = [Upgrades.W_STAR, Upgrades.POWER, Upgrades.QUICK]
	p.choices = hand.duplicate()
	var offer := p.offer
	p.upgrades[Upgrades.W_STORM] = 1 # a tome filled the third slot while the hand waited
	_send(w, p, 0)
	assert_eq(Upgrades.slots_used(p.upgrades).x, 3, "a stale card broke the spell cap")
	assert_eq(p.offer, offer + 1, "no fresh hand")
	assert_eq(p.choices.size(), 3, "the level was lost")
	# FIREBALL 4 to 5 in hand, then a tome raises it to 5 first.
	p.upgrades[Upgrades.W_FROST] = 4
	p.choices = [Upgrades.W_FROST, Upgrades.POWER, Upgrades.QUICK] as Array[int]
	offer = p.offer
	p.upgrades[Upgrades.W_FROST] = Spells.MAX_LEVEL
	_send(w, p, 0)
	assert_eq(p.offer, offer + 1, "a maxed card was not replaced")
	assert_eq(p.choices.size(), 3, "the level was lost to a maxed card")
	assert_eq(Upgrades.level_of(p.upgrades, Upgrades.W_FROST), Spells.MAX_LEVEL)


## A pair whose owned side is banished (its spell row or its evolution) no longer keeps the last slot or weighs
## more.
func test_a_banished_pair_does_not_count() -> void:
	var lv := {Upgrades.W_ARCANE: 1, Upgrades.W_FIRE: 1}
	assert_true(Upgrades.pairs_with(lv, Upgrades.QUICK))
	for ban: int in [Upgrades.E_ARCANE, Upgrades.W_ARCANE]:
		var banned := {ban: true}
		assert_false(Upgrades.pairs_with(lv, Upgrades.QUICK, banned), "THE MAGICIAN pairs with a banished arcane")
		assert_eq(Upgrades.roll_weight(lv, Upgrades.QUICK, banned), float(Upgrades.CATALOG[Upgrades.QUICK][Upgrades.C_WEIGHT]))
	# THE TOWER still pairs with FIREBALL, so the last arcana slot stays kept against THE CHARIOT; with every pair's
	# evolution banished it is free.
	var lv2 := lv.merged({Upgrades.REGEN: 1, Upgrades.MAGNET: 1})
	assert_false(Upgrades.available(lv2, Upgrades.SWIFT, Upgrades.SLOTS_EARLY))
	var all := {Upgrades.E_ARCANE: true, Upgrades.E_FIRE: true, Upgrades.E_LODESTAR: true, Upgrades.E_GREEK: true}
	assert_true(Upgrades.available(lv2, Upgrades.SWIFT, Upgrades.SLOTS_EARLY, all), "a banished pair kept the last slot")

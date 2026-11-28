extends TestCase
## World Seals: the run's difficulty level (game/logic/world.gd apply_seal, later game/logic/seals.gd).
## Pins the neutral defaults the wave 2 core landed.


func test_seal_zero_changes_nothing() -> void:
	var a := World.new([0, 1], 7)
	var b := World.new([0, 1], 7)
	b.apply_seal(0)
	assert_eq(b.seal, 0)
	for _i: int in range(120):
		a.step(1.0 / 60.0, {})
		b.step(1.0 / 60.0, {})
	assert_eq(a.state_hash(), b.state_hash(), "Seal 0 must play exactly like no Seal")
	assert_eq(int((b.snapshot()["w"] as PackedFloat32Array)[World.W_SEAL]), 0)
	b.apply_seal(3)
	assert_eq(int((b.snapshot()["w"] as PackedFloat32Array)[World.W_SEAL]), 3, "the header carries the Seal")
	b.apply_seal(World.SEAL_EASY)
	assert_eq(int((b.snapshot()["w"] as PackedFloat32Array)[World.W_SEAL]), -1, "easy (-1) round-trips through the header")


func _world(level: int, slots: Array = [0, 1], seed_value: int = 7) -> World:
	var w := World.new(slots, seed_value, Tuning.new())
	w.apply_seal(level)
	return w


func _count(w: World, kind: int) -> int:
	var n := 0
	for k: World.Pickup in w.pickups:
		if k.kind == kind:
			n += 1
	return n


func test_seal_zero_leaves_every_field_at_its_default() -> void:
	var a := World.new([0, 1], 7)
	var b := _world(0)
	for f: String in ["seal_hp", "seal_horde", "seal_boss", "seal_speed", "seal_potions", "seal_luck", "seal_cards",
			"seal_ultra", "seal_rift", "seal_potion_heal", "seal_group", "seal_cap", "seal_elite_hp",
			"seal_escort", "seal_hand", "seal_ritual", "seal_card", "fate_cruel"]:
		assert_eq(b.get(f), a.get(f), f)
	for s: int in [0, 1]:
		assert_eq(b.players[s].max_hp, a.players[s].max_hp)
		assert_eq(b.players[s].lives, a.players[s].lives)
		assert_true(b.players[s].banned.is_empty())


func test_scalars_reach_enemies_bosses_and_hearts() -> void:
	var base := _world(0)
	var arch := _world(1)
	var g0 := WorldWaves.spawn_enemy(base, World.GOBLIN, 0)
	var g1 := WorldWaves.spawn_enemy(arch, World.GOBLIN, 0)
	var v1 := Seals.values(1)
	assert_near(g1.hp / g0.hp, float(v1.hp), 0.001, "ARCHMAGE enemy health")
	assert_near(g1.spd / g0.spd, float(v1.speed), 0.001, "ARCHMAGE enemy speed")
	var l0 := WorldWaves.spawn_enemy(base, World.LICH, 0)
	var l1 := WorldWaves.spawn_enemy(arch, World.LICH, 0)
	assert_near(l1.hp / l0.hp, float(v1.boss), 0.001, "ARCHMAGE Lich health")
	WorldBosses._make_final(base, l0)
	WorldBosses._make_final(arch, l1)
	assert_near(l1.hp / l0.hp, float(v1.boss), 0.001, "ARCHMAGE Archlich health")
	var easy := _world(-1)
	assert_eq(easy.players[0].max_hp, base.players[0].max_hp + int(Seals.APPRENTICE.hearts), "APPRENTICE: hearts more")
	assert_eq(easy.players[0].hp, easy.players[0].max_hp)
	assert_near(WorldWaves.spawn_enemy(easy, World.GOBLIN, 0).hp / g0.hp, float(Seals.APPRENTICE.hp), 0.001)
	assert_near(_world(9).seal_horde, float(Seals.values(9).horde))
	assert_near(_world(9).seal_horde, 1.0 + float(Seals.PER_SEAL.horde) * 8)


## Plain kills: 3000 drops each. HUNGER (SEAL I) thins their potions; APPRENTICE drops more of them.
func test_hunger_and_the_potion_scalar() -> void:
	var counts := {}
	for level: int in [-1, 1, 2]:
		var w := _world(level, [0], 3)
		for i: int in range(3000):
			WorldDrops._roll_drop(w, WorldWaves.spawn_enemy(w, World.GOBLIN, 0))
		counts[level] = _count(w, World.PK_POTION)
	assert_true(int(counts[1]) > 20, "ARCHMAGE kills drop potions")
	assert_true(int(counts[2]) > 0 and int(counts[2]) < int(counts[1]) * 0.8, "HUNGER: fewer potions from plain kills")
	assert_true(int(counts[-1]) > int(counts[1]), "APPRENTICE: more potions")


func test_ambush_halves_the_rift_warning() -> void:
	for level: int in [2, 3]:
		var w := _world(level)
		w.phase = World.PH_FIGHT
		w.spawn_queue.clear()
		WorldWaves._queue_rift(w, World.GOBLIN, 1)
		var want := w.tune.rift_warning * (0.5 if level >= 3 else 1.0)
		assert_near(float(w.spawn_queue[0].t) - w.wave_time, want, 0.0001, Seals.title(level))
		# A RISE group's markers (one per riser) warn as long.
		w.spawn_queue.clear()
		w.events.clear()
		WorldWaves._queue_rolled(w, [Bestiary.RISE, [[Bestiary.COFFIN, 2]]])
		assert_eq(w.spawn_queue.size(), 2)
		for q: Dictionary in w.spawn_queue:
			assert_near(float(q.t) - w.wave_time, want, 0.0001, "RISE at " + Seals.title(level))
		var rifts := w.events.filter(func(ev: Array) -> bool: return int(ev[0]) == World.EV_RIFT)
		assert_eq(rifts.size(), 2)
		for ev: Array in rifts:
			assert_near(float(ev[4]), want, 0.0001, "the RISE marker shows as long")


func test_famine_potions_heal_one_heart() -> void:
	for level: int in [3, 4]:
		var w := _world(level)
		var p: World.Player = w.players[0]
		p.hp = 1
		var k := World.Pickup.new()
		k.kind = World.PK_POTION
		WorldDrops._collect(w, p, k)
		assert_eq(p.hp, 2 if level >= 4 else 3, Seals.title(level))


func test_legion_groups_and_cap() -> void:
	var a := _world(4, [0], 11)
	var b := _world(5, [0], 11)
	a.wave_time = 600.0
	b.wave_time = 600.0
	a.wave = 11
	b.wave = 11
	for i: int in range(40):
		var ga := WorldWaves._roll_group(a)
		var gb := WorldWaves._roll_group(b)
		assert_eq(gb[0], ga[0], "same layout")
		assert_eq((gb[1] as Array).size(), (ga[1] as Array).size())
		for k: int in range((ga[1] as Array).size()):
			assert_eq(gb[1][k][0], ga[1][k][0])
			assert_eq(int(gb[1][k][1]), int(round(int(ga[1][k][1]) * 1.25)), "LEGION: a quarter more")
	assert_eq(a.seal_cap, 0)
	assert_eq(b.seal_cap, 325)
	# At its cap the horde holds its budget.
	b.phase = World.PH_FIGHT
	for i: int in range(325):
		b.spawn_queue.append({"t": 9999.0, "type": World.GOBLIN, "door": 0})
	var budget := b.horde_budget
	WorldWaves._direct_horde(b, 0.5)
	assert_eq(b.horde_budget, budget, "held at 325")
	assert_eq(b.enemy_cap(), 325)
	assert_eq(a.enemy_cap(), int(a.tune.enemy_cap))


## LEGION's cap reaches the Bone Priest: past Tuning's cap but under LEGION's, a priest still raises.
func test_legion_cap_lets_a_priest_raise() -> void:
	var w := _world(5, [0], 11)
	w.phase = World.PH_FIGHT
	for i: int in range(280):
		w.spawn_queue.append({"t": 9999.0, "type": World.GOBLIN, "door": 0})
	assert_true(280 > int(w.tune.enemy_cap), "the test sits past Tuning's cap")
	var priest := WorldWaves.spawn_enemy(w, World.PRIEST, 0, Vector2(200, 150))
	priest.timer2 = World.PRIEST_RAISE - 0.001
	w.events.clear()
	var before := w.enemies.size()
	Brains.think(w, priest, 0.01, w.players[0], Vector2.RIGHT, 80.0)
	assert_eq(w.enemies.size() - before, World.PRIEST_RAISED, "LEGION: the priest still raises at 281 fielded")


## The horde's budget grows faster up the ladder (seal_horde).
func test_seal_horde_reaches_the_budget() -> void:
	var got := {}
	for level: int in [0, 9]:
		var w := _world(level, [0], 11)
		w.phase = World.PH_FIGHT
		w.wave_time = 120.0
		w.wave = 3
		w.horde_budget = 0.0
		WorldWaves._direct_horde(w, 0.001)
		got[level] = w.horde_budget
	assert_true(float(got[0]) > 0.0)
	assert_near(float(got[9]) / float(got[0]), float(Seals.values(9).horde), 0.0001, "SEAL VIII: more budget per second")


func test_champions_elites_are_tougher_and_escorted() -> void:
	for level: int in [5, 6]:
		var w := _world(level, [0], 5)
		w.wave = 3
		w.spawn_queue.clear()
		WorldWaves._spawn_elite(w, true)
		var e: World.Enemy = w.enemies[-1]
		var plain := WorldWaves.spawn_enemy(w, e.type, 0)
		var mul := w.tune.elite_hp_mul * (1.5 if level >= 6 else 1.0)
		assert_near(e.hp / plain.hp, mul, 0.001, Seals.title(level))
		assert_eq(w.spawn_queue.size(), 4 if level >= 6 else 0, "escort")
		for s: Dictionary in w.spawn_queue:
			assert_eq(int(s.type), e.type)
			assert_true(int(s.door) >= 0)



## CHAMPIONS escorts only the horde's timed elites, and never past the enemy cap.
func test_champions_escorts_only_timed_elites_under_the_cap() -> void:
	var curse := _world(6, [0, 1], 5)
	curse.wave = 3
	WorldShrines._apply_fate(curse, Gamble.TO_CURSE, 1, null, Vector2.ZERO)
	assert_eq(curse.enemies.filter(func(e: World.Enemy) -> bool: return e.elite).size(), 2, "one elite per wizard")
	assert_eq(curse.spawn_queue.size(), 0, "a curse's elites come alone")
	var boss := _world(6, [0], 5)
	boss.wave = 15
	var lich := WorldWaves.spawn_enemy(boss, World.LICH, 0)
	WorldBosses._make_final(boss, lich)
	lich.hp = lich.maxhp * 0.1 # raging
	lich.enter_dir.y = 2.0 # its two phase turns are behind it
	lich.state = 4
	lich.timer = 1.0
	BossLich.think(boss, lich, 0.0, boss.players[0], Vector2.RIGHT, 80.0)
	assert_eq(boss.enemies.filter(func(e: World.Enemy) -> bool: return e.elite).size(), 1, "the Archlich summons an elite")
	assert_eq(boss.spawn_queue.size(), 0, "and it comes alone")
	var full := _world(6, [0], 5)
	full.wave = 3
	for i: int in range(full.enemy_cap() - 2):
		full.spawn_queue.append({"t": 9999.0, "type": World.GOBLIN, "door": 0})
	WorldWaves._spawn_elite(full, true)
	assert_eq(full.enemies.size() + full.spawn_queue.size(), full.enemy_cap(), "the escort is trimmed to the cap")
	WorldWaves._spawn_elite(full, true)
	assert_eq(full.spawn_queue.size(), full.enemy_cap() - 1, "none past the cap")


## DARKNESS: a ritual takes twice as long at SEAL VIII.
func test_darkness_rituals_take_twice_as_long() -> void:
	for level: int in [8, 9]:
		var w := _world(level, [0, 1], 3)
		w.phase_t = 1e6
		for q: World.Player in w.players.values():
			q.invuln = 0.0
		var p: World.Player = w.players[1]
		w.hurt_player(p, 99)
		assert_true(p.down, Seals.title(level))
		w.players[0].pos = p.pos
		var need := w.tune.ritual_time * (2.0 if level >= 9 else 1.0)
		for _i: int in range(roundi((need - 0.1) * 60.0)):
			w.step(1.0 / 60.0, {})
		assert_true(p.down, "still down just before %.1f s at %s" % [need, Seals.title(level)])
		for _i: int in range(12):
			w.step(1.0 / 60.0, {})
		assert_true(p.alive, "raised at %.1f s at %s" % [need, Seals.title(level)])


func test_misfortune_silence_and_darkness() -> void:
	assert_near(_world(6).fate_cruel, 0.5)
	assert_near(_world(7).fate_cruel, 0.6, 0.0001, "MISFORTUNE")
	for level: int in [8, 9]:
		var w := _world(level)
		var p: World.Player = w.players[0]
		p.pending = 1
		WorldLevels._offer(w, p)
		assert_eq(p.choices.size(), 2, "SILENCE: two cards")
	var w7 := _world(7)
	w7.players[0].pending = 1
	WorldLevels._offer(w7, w7.players[0])
	assert_eq(w7.players[0].choices.size(), int(w7.tune.level_choices))
	var party := _world(9, [0, 1])
	var solo := _world(9, [0])
	assert_eq(party.players[0].lives, 1, "DARKNESS: one life")
	assert_eq(solo.players[0].lives, 2, "a wizard with no ally keeps two")
	assert_true(party.players[1].banned.has(Upgrades.LIFE), "no JUDGEMENT")
	assert_false(_world(8).players[0].banned.has(Upgrades.LIFE))
	assert_near(party.seal_ritual, 2.0)
	assert_near(_world(8).seal_ritual, 1.0)
	for i: int in range(200):
		party.players[0].pending = 1
		party.players[0].choices.clear()
		WorldLevels._offer(party, party.players[0])
		assert_false(party.players[0].choices.has(Upgrades.LIFE), "JUDGEMENT is never dealt")


func test_luck_ultra_and_the_seal_card() -> void:
	var easy := _world(-1)
	assert_false(easy.seal_ultra)
	easy.players[0].pos = Vector2(400, 238)
	for i: int in range(60):
		var k := World.Pickup.new()
		k.kind = World.PK_CHEST_ULTRA
		k.value = 50
		easy.events.clear()
		WorldDrops._open_chest(easy, easy.players[0], k)
		var tier := int(easy.events[-1][4]) % 8
		assert_true(tier <= Loot.LEGENDARY, "APPRENTICE: no ULTRA RARE")
	assert_true(_world(0).seal_ultra, "WIZARD keeps ULTRA RARE runs")
	easy.tune.ultra_run_chance = 1.0
	easy.tune.loot_moment_from = 0.0
	easy.tune.loot_moment_to = 0.0
	assert_false(WorldDrops.ultra_due(easy), "APPRENTICE: never an ULTRA RARE run")
	var s4 := _world(5)
	assert_eq(s4.seal_luck, 5)
	assert_near(s4.seal_cards, 1.5)
	# SEAL IV's card run: its Archlich, when it is the kill, drops the Seal card; a plain Lich its own card.
	s4.tune.card_run_chance = 1.0
	s4.tune.card_run_urn = 0.0
	s4.tune.loot_moment_from = 0.0
	s4.tune.loot_moment_to = 0.0
	var choices := WorldDrops.run_card_choices(s4)
	assert_true(choices.has(Seals.card(5)), "SEAL IV's card run can give its Seal card")
	assert_false(choices.has(Cards.for_enemy(World.LICH)), "under a Seal the Archlich's card is the Seal's")
	s4.run_loot.card_kind = (choices.find(Seals.card(5)) + 0.5) / choices.size()
	assert_eq(WorldDrops.run_card(s4), Seals.card(5))
	WorldDrops._roll_card(s4, WorldWaves.spawn_enemy(s4, World.LICH, 0))
	assert_eq(_cards_on_floor(s4), [], "a plain Lich never drops a Seal card")
	var arch := WorldWaves.spawn_enemy(s4, World.LICH, 0)
	WorldBosses._make_final(s4, arch)
	WorldDrops._roll_card(s4, arch)
	assert_eq(_cards_on_floor(s4), [Seals.card(5)], "SEAL IV's Archlich drops its card in a card run")
	WorldDrops._roll_card(s4, arch)
	assert_eq(_cards_on_floor(s4).size(), 1, "a card run drops one card")
	var w1 := _world(1)
	var arch0 := WorldWaves.spawn_enemy(w1, World.LICH, 0)
	WorldBosses._make_final(w1, arch0)
	WorldDrops._roll_card(w1, arch0)
	assert_eq(_cards_on_floor(w1), [], "out of a card run the Archlich drops no card")


## The Seals' card odds raise the card run's chance (Cards.card_run_chance x seal_cards).
func test_seal_card_odds_raise_the_card_run() -> void:
	var w := _world(5)
	w.run_loot.card = 0.012
	w.tune.loot_moment_from = 0.0
	w.tune.loot_moment_to = 0.0
	assert_true(WorldDrops.card_due(w), "SEAL IV: 1.5% card runs take a draw of 1.2%")
	var w0 := _world(0)
	w0.run_loot.card = 0.012
	w0.tune.loot_moment_from = 0.0
	w0.tune.loot_moment_to = 0.0
	assert_false(WorldDrops.card_due(w0), "WIZARD: 1% does not")


func _cards_on_floor(w: World) -> Array:
	var out: Array = []
	for k: World.Pickup in w.pickups:
		if k.kind == World.PK_CARD:
			out.append(k.value)
	return out


## Bots play a few seconds at SEAL VIII without errors, and the header carries the Seal.
func test_a_seal_plays() -> void:
	var w := _world(9, [0, 1], 9)
	var bots := {}
	for s: int in [0, 1]:
		bots[s] = SmashBot.new(s + 1)
	for i: int in range(60 * 12):
		var inputs := {}
		for s: int in bots:
			var inp: PackedFloat32Array = (bots[s] as SmashBot).decide_in_world(w, s)
			var p: World.Player = w.players[s]
			if not p.choices.is_empty():
				inp = SmashBot.with_pick(inp, p.choices, p.offer)
			inputs[s] = inp
		w.step(1.0 / 60.0, inputs)
	assert_true(w.wave_time > 5.0)
	assert_eq(int((w.snapshot()["w"] as PackedFloat32Array)[World.W_SEAL]), 9)

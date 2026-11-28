extends TestCase
## WorldGrants.give (docs/stage3_brief.md § 4.4): a catalog row given by force, with everything it needs, past the
## slot cap, a ban and Upgrades.UNBUILT. For tests, tools and the coverage robot (tests/bot/bot_cover.gd).

const DT := 1.0 / 60.0
## Seconds of World.step a given spell gets to land its first damage.
const CAST_SECONDS := 4.0


## A world past its intro with one wizard, unhurtable, at a fixed spot.
func _world() -> World:
	var w := World.new([0], 5, Tuning.new())
	w.phase = World.PH_FIGHT
	var p: World.Player = w.players[0]
	p.pos = Vector2(300, 220)
	p.invuln = 999.0
	return w


## A ring of tough orcs close round the wizard, near enough for every cast kind (the sweep's short reach too).
func _ring(w: World, p: World.Player) -> void:
	for i: int in range(8):
		var e: World.Enemy = w.spawn_enemy(World.ORC, 0, p.pos + Vector2.from_angle(i * TAU / 8.0) * 16.0)
		e.entering = false
		e.hp = 100000.0
		e.maxhp = 100000.0


func _damage_by(w: World, slot: int, sp: int) -> float:
	return float((w.record.slot_source_damage.get(slot, {}) as Dictionary).get(sp, 0.0))


func _play(w: World, seconds: float) -> void:
	for _i: int in range(int(seconds / DT)):
		w.players[0].invuln = 999.0
		w.step(DT, {})


func test_a_spell_is_learnt_and_cast() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	var sp := Upgrades.spell_of(Upgrades.W_FIRE)
	assert_eq(Upgrades.level_of(p.upgrades, Upgrades.W_FIRE), 0, "the wizard starts without FIREBALL")
	WorldGrants.give(w, p, Upgrades.W_FIRE)
	assert_eq(Upgrades.level_of(p.upgrades, Upgrades.W_FIRE), 1)
	assert_eq(_codes(w.take_events(), World.EV_PICK).size(), 1, "the pick event the arena draws")
	_ring(w, p)
	_play(w, CAST_SECONDS)
	assert_true(_damage_by(w, 0, sp) > 0.0, "FIREBALL never hit")


func test_a_passive_is_learnt() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	WorldGrants.give(w, p, Upgrades.SWIFT)
	assert_eq(Upgrades.level_of(p.upgrades, Upgrades.SWIFT), 1)
	assert_near(Upgrades.move_mul(p.upgrades), float(Upgrades.CATALOG[Upgrades.SWIFT][Upgrades.C_VALUES][0]))


func test_instants_give_a_nova_and_a_life() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	var bombs := p.bombs
	var lives := p.lives
	WorldGrants.give(w, p, Upgrades.NOVA)
	WorldGrants.give(w, p, Upgrades.LIFE)
	assert_eq(p.bombs, bombs + 1)
	assert_eq(p.lives, lives + 1)


## Every evolution of the catalog, read from it: its spell at the top level and its partner at 1 first, then it is held
## (Upgrades.evolved), noted as the evolve moment, and the wizard casts it evolved into a ring of foes.
func test_every_evolution_is_held_and_cast() -> void:
	var n := 0
	for idx: int in range(Upgrades.count()):
		if Upgrades.kind(idx) != Upgrades.EVOLUTION:
			continue
		n += 1
		var key := Upgrades.key(idx)
		var w := _world()
		var p: World.Player = w.players[0]
		var sp := Upgrades.spell_of(idx)
		WorldGrants.give(w, p, idx)
		assert_true(Upgrades.evolved(p.upgrades, sp), "%s not held" % key)
		for req: Array in Upgrades.CATALOG[idx][Upgrades.C_REQUIRES]:
			assert_true(Upgrades.level_of(p.upgrades, int(req[0])) >= int(req[1]), "%s: %s below %d" % [key,
				Upgrades.key(int(req[0])), int(req[1])])
		assert_eq(Upgrades.weapon_level(p.upgrades, sp), Spells.MAX_LEVEL, key)
		assert_eq(WorldCasting._weapon_snap(w, p, sp), Spells.MAX_LEVEL + 1, "%s is not drawn evolved" % key)
		var noted := w.record.moments.filter(func(m: Array) -> bool: return int(m[1]) == Results.M_EVOLVE and int(m[3]) == idx)
		assert_eq(noted.size(), 1, "%s: the evolve moment" % key)
		_ring(w, p)
		_play(w, CAST_SECONDS)
		assert_true(Upgrades.evolved(p.upgrades, sp), "%s lost" % key)
		assert_true(_damage_by(w, 0, sp) > 0.0, "%s never hit" % key)
	assert_true(n >= 9, "the catalog has %d evolutions" % n)


## WHIRLWIND for a wizard who is no knight: CLEAVE (a class weapon that requires itself) comes with it and casts.
func test_a_class_weapon_casts_for_a_wizard_of_another_class() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	assert_true(p.cls != Classes.KNIGHT)
	WorldGrants.give(w, p, Upgrades.W_CLEAVE)
	assert_eq(Upgrades.level_of(p.upgrades, Upgrades.W_CLEAVE), 1, "a self requirement is no extra level")
	_ring(w, p)
	_play(w, CAST_SECONDS)
	assert_true(_damage_by(w, 0, World.SP_CLEAVE) > 0.0, "CLEAVE never swung")


func test_a_row_over_the_slot_cap_is_given() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	w.step(DT, {})
	var cap := w.slot_cap()
	var spells: Array[int] = []
	for idx: int in range(Upgrades.count()):
		if Upgrades.kind(idx) == Upgrades.SPELL and Upgrades.level_of(p.upgrades, idx) == 0:
			spells.append(idx)
	while Upgrades.slots_used(p.upgrades).x < cap.x:
		WorldGrants.give(w, p, spells.pop_front())
	var over: int = spells.pop_front()
	assert_false(Upgrades.available(p.upgrades, over, cap, p.banned), "the cap would refuse it")
	WorldGrants.give(w, p, over)
	assert_eq(Upgrades.level_of(p.upgrades, over), 1)
	assert_eq(Upgrades.slots_used(p.upgrades).x, cap.x + 1)


func test_a_banned_row_is_given() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	p.banned[Upgrades.POWER] = true
	WorldGrants.give(w, p, Upgrades.POWER)
	assert_eq(Upgrades.level_of(p.upgrades, Upgrades.POWER), 1)
	assert_true(p.banned.has(Upgrades.POWER), "the ban stays")


func test_a_second_give_raises_a_level_up_to_the_top() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	WorldGrants.give(w, p, Upgrades.REGEN)
	WorldGrants.give(w, p, Upgrades.REGEN)
	assert_eq(Upgrades.level_of(p.upgrades, Upgrades.REGEN), 2)
	var top := Upgrades.max_level(Upgrades.REGEN)
	for _i: int in range(top + 2):
		WorldGrants.give(w, p, Upgrades.REGEN)
	assert_eq(Upgrades.level_of(p.upgrades, Upgrades.REGEN), top)
	var e := Upgrades.E_FIRE
	WorldGrants.give(w, p, e)
	WorldGrants.give(w, p, e)
	assert_eq(Upgrades.level_of(p.upgrades, e), 1)
	assert_eq(Upgrades.weapon_level(p.upgrades, World.SP_FIRE), Spells.MAX_LEVEL)


## A guard against drift from WorldLevels._pick: for every row a fresh wizard could pick, a give leaves her as a pick
## does (levels, novas, lives, hearts, gold, the spell she shows).
func test_a_give_does_what_a_pick_does() -> void:
	for idx: int in range(Upgrades.count()):
		var a := _world()
		var pa: World.Player = a.players[0]
		if Upgrades.kind(idx) != Upgrades.MINOR and not Upgrades.available(pa.upgrades, idx, a.slot_cap(), pa.banned):
			continue
		pa.hp = maxi(1, pa.max_hp - 1)
		WorldLevels._pick(a, pa, idx)
		var b := _world()
		var pb: World.Player = b.players[0]
		pb.hp = maxi(1, pb.max_hp - 1)
		WorldGrants.give(b, pb, idx)
		var k := Upgrades.key(idx)
		assert_eq(pb.upgrades, pa.upgrades, k)
		assert_eq([pb.bombs, pb.lives, pb.hp, pb.spell], [pa.bombs, pa.lives, pa.hp, pa.spell], k)
		assert_near(pb.gold, pa.gold, 0.0001, k)


func _codes(evs: Array, code: int) -> Array:
	return evs.filter(func(ev: Array) -> bool: return int(ev[0]) == code)

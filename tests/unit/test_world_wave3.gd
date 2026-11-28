extends TestCase
## Wave 3 spells in the World (WorldCasting): BONE SPEAR and OSSUARY LANCE, VIGIL CANDLE and CONSECRATION, the
## passives JUSTICE and THE LOVERS, the knight's CLEAVE (cast kind "sweep") and WHIRLWIND, and the class weapon skins (LONGBOW,
## HOLY LIGHT) that World.apply_hero gives.

const DT := 1.0 / 60.0


## A world past its intro, wizards at fixed spots apart, no hero applied.
func _world(n: int = 1) -> World:
	var slots: Array = []
	for i: int in range(n):
		slots.append(i)
	var w := World.new(slots, 3, Tuning.new())
	w.phase = World.PH_FIGHT
	for i: int in range(n):
		var p: World.Player = w.players[i]
		p.pos = Vector2(200 + i * 150, 200)
		p.invuln = 99.0
	return w


func _orc(w: World, at: Vector2) -> World.Enemy:
	var e: World.Enemy = w.spawn_enemy(World.ORC, 0, at)
	e.entering = false
	e.hp = 1000.0
	e.maxhp = 1000.0
	return e


func _hero(w: World, slot: int, cls: int) -> World.Player:
	var p: World.Player = w.players[slot]
	w.apply_hero(p, Hero.make(Races.HUMAN, cls, 0).to_dict())
	return p


func _fly(w: World, seconds: float) -> void:
	for _i: int in range(int(seconds / DT)):
		w._build_grid()
		w._update_shots(DT)
		w.shots = w.shots.filter(func(s: World.Shot) -> bool: return not s.dead)


func _burn(w: World, seconds: float) -> void:
	for _i: int in range(int(seconds / DT)):
		w._build_grid()
		w._plist.assign(w.players.values())
		w._update_runes(DT)
		w.runes = w.runes.filter(func(c: World.Rune) -> bool: return c.age < c.life)


func _codes(evs: Array, code: int) -> Array:
	return evs.filter(func(ev: Array) -> bool: return int(ev[0]) == code)


func test_shot_kinds_keep_the_first_six() -> void:
	for sp: int in range(World.SP_RUNE + 1):
		assert_eq(Spells.shot_kind(sp, 0), sp)
		assert_eq(Spells.shot_kind(sp, 1), sp + 6, "an evolved shot of the first six is drawn as it always was")
	var seen := {}
	for sp: int in range(Spells.COUNT):
		for evo: int in [0, 1]:
			var k := Spells.shot_kind(sp, evo)
			assert_false(seen.has(k), "two shots share kind %d" % k)
			seen[k] = true
			assert_eq(Spells.shot_spell(k), sp)
			assert_eq(Spells.shot_evo(k), evo)


func test_bone_spear_pierces_every_foe_on_its_line() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	w._cast(p, World.SP_BONE, 1, false, Vector2.RIGHT)
	assert_eq(w.shots.size(), Spells.count(World.SP_BONE, 1, 0))
	var s: World.Shot = w.shots[0]
	assert_eq(s.pierce, Spells.PIERCE_ALL)
	# Five orcs on the first spear's line (an orc is hit at its chest, r * 0.8 above its feet).
	var foes: Array[World.Enemy] = []
	for i: int in range(5):
		var e := _orc(w, s.pos + s.vel.normalized() * (25.0 + i * 35.0))
		e.pos.y += e.r * 0.8
		foes.append(e)
	_fly(w, 1.0)
	for e: World.Enemy in foes:
		assert_true(e.hp < e.maxhp, "an orc at %s was not pierced" % e.pos)
	assert_true(w.shots.is_empty(), "a spear outlived its line")


func test_bone_spear_flies_its_line_and_the_longbow_further() -> void:
	var w := _world(2)
	var mage: World.Player = w.players[0]
	var archer := _hero(w, 1, Classes.ARCHER)
	assert_eq(Upgrades.weapon_level(archer.upgrades, World.SP_BONE), 1, "the archer holds the BONE SPEAR row")
	assert_eq(archer.skin, "longbow")
	assert_eq(archer.class_weapon, World.SP_BONE)
	assert_eq(mage.class_weapon, -1, "a wizard with no hero wears no skin")
	w._cast(mage, World.SP_BONE, 1, false, Vector2.RIGHT)
	var plain: World.Shot = w.shots[0]
	assert_near(plain.life * plain.vel.length(), 220.0, 0.5)
	w.shots.clear()
	w._cast(archer, World.SP_BONE, 1, false, Vector2.RIGHT)
	assert_near(w.shots[0].life * w.shots[0].vel.length(), Classes.skin_value("longbow", "range"), 0.5)
	assert_eq(w.shots[0].kind, Spells.shot_kind(World.SP_BONE, 0))


func test_ossuary_lance_splinters_sideways_once() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	var e := _orc(w, p.pos + Vector2(40, -7))
	w._build_grid()
	var s: World.Shot = WorldCastBolts._shot(w, 0, World.SP_BONE, true, p.pos + Vector2(30, -7), Vector2(275, 0), 5.0, Spells.PIERCE_ALL)
	WorldCastBolts._shot_hit(w, s, e)
	var splinters: Array = w.shots.filter(func(x: World.Shot) -> bool: return x.splinter)
	assert_eq(splinters.size(), int(Spells.evo_value(World.SP_BONE, "splinter", 1, 0.0)))
	for x: World.Shot in splinters:
		assert_near(absf(x.vel.normalized().dot(Vector2.RIGHT)), 0.0, 0.35, "a splinter flies along the spear")
		assert_near(x.dmg, 5.0 * Spells.SPLINTER_DMG)
		assert_true(x.hits.has(e.id), "a splinter may hit the foe it came from")
		var before := w.shots.size()
		WorldCastBolts._shot_hit(w, x, _orc(w, x.pos))
		assert_eq(w.shots.size(), before, "a splinter splintered")
	assert_false(s.dead, "the lance stopped at its first foe")


func test_vigil_candle_burns_on_a_timer_near_the_caster() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	var far := _orc(w, p.pos + Vector2(-100, 0))
	var pack := p.pos + Vector2(40, 10)
	var near: Array[World.Enemy] = []
	for i: int in range(3):
		near.append(_orc(w, pack + Vector2(i * 4 - 4, 0)))
	w._build_grid()
	w.take_events()
	w._cast(p, World.SP_CANDLE, 1, false, Vector2.RIGHT)
	assert_eq(w.runes.size(), 1)
	var c: World.Rune = w.runes[0]
	assert_eq(c.kind, Spells.CIRCLE_CANDLE)
	assert_near(c.r, Spells.stat(World.SP_CANDLE, "r"))
	assert_true(c.pos.distance_to(pack) < 8.0, "the light is at %s, not on the pack at %s" % [c.pos, pack])
	var snap: PackedFloat32Array = w.snapshot()["r"]
	assert_eq(int(snap[World.R_KIND]), Spells.CIRCLE_CANDLE, "the snapshot carries the light in the reserved kind")
	_burn(w, 1.0)
	var ticks := 1 + int((1.0 - Spells.RUNE_ARM) / Spells.RUNE_TICK)
	for e: World.Enemy in near:
		assert_near(e.maxhp - e.hp, ticks * Spells.damage(World.SP_CANDLE, 1, 0), 0.01)
	assert_eq(far.hp, far.maxhp, "the light reached past its radius")
	assert_true(w.record.source_damage.has(World.SP_CANDLE), "the candle's damage is not its own source")


func test_vigil_candle_hastens_who_stood_in_it_for_two_seconds() -> void:
	var w := _world(2)
	var p: World.Player = w.players[0]
	var friend: World.Player = w.players[1]
	w._build_grid()
	w._cast(p, World.SP_CANDLE, 1, false, Vector2.RIGHT)
	var c: World.Rune = w.runes[0]
	assert_true(c.pos.distance_to(p.pos + Vector2.RIGHT * Spells.CANDLE_AIM_DIST) < 0.5, "no foe near: the light goes ahead")
	friend.pos = c.pos
	p.pos = c.pos - Vector2(c.r + 20.0, 0.0) # the light is wider than CANDLE_AIM_DIST: she steps out of it
	_burn(w, 0.1)
	assert_near(friend.vigil, Spells.VIGIL_AFTER, 0.001)
	assert_near(WorldCasting._cast_speed(w, friend), Spells.VIGIL_HASTE)
	assert_eq(WorldCasting._cast_speed(w, p), 0.0, "the caster stood outside her light")
	friend.pos = c.pos + Vector2(100, 0)
	for _i: int in range(int(1.5 / DT)):
		w._update_player(friend, DT, PackedFloat32Array())
	assert_true(friend.vigil > 0.0, "the haste ended before two seconds")
	for _i: int in range(int(0.6 / DT)):
		w._update_player(friend, DT, PackedFloat32Array())
	assert_eq(friend.vigil, 0.0)


func test_the_lovers_near_an_ally_or_half_alone() -> void:
	var w := _world(2)
	var p: World.Player = w.players[0]
	var ally: World.Player = w.players[1]
	w._plist.assign(w.players.values())
	assert_eq(WorldCasting._cast_speed(w, p), 0.0)
	p.upgrades[Upgrades.LOVERS] = 3
	ally.pos = p.pos + Vector2(200, 0)
	assert_near(WorldCasting._cast_speed(w, p), 0.24 * Upgrades.LOVERS_ALONE)
	ally.pos = p.pos + Vector2(Upgrades.LOVERS_RANGE - 1.0, 0)
	ally.ai = true # an apprentice counts
	assert_near(WorldCasting._cast_speed(w, p), 0.24)
	ally.down = true
	assert_near(WorldCasting._cast_speed(w, p), 0.24 * Upgrades.LOVERS_ALONE, 0.0001, "a fallen ally does not count")


func test_cast_speed_adds_up_and_never_passes_the_floor() -> void:
	var w := _world(2)
	var p: World.Player = w.players[0]
	w._plist.assign(w.players.values())
	w.players[1].pos = p.pos + Vector2(10, 0)
	var cd := Spells.cooldown(World.SP_ARCANE, 1, 0)
	p.upgrades[Upgrades.LOVERS] = 1
	p.vigil = 1.0
	WorldCasting._auto_cast(w, p, DT, Vector2.RIGHT)
	assert_near(p.cds[World.SP_ARCANE], cd / (1.0 + 0.08 + Spells.VIGIL_HASTE) * w.tune.spell_cd_mul, 0.0001,
		"THE LOVERS and the candle add up as cast speed")
	p.upgrades[Upgrades.QUICK] = 5
	p.upgrades[Upgrades.LOVERS] = 3
	p.haste = 5.0
	p.cds[World.SP_ARCANE] = 0.0
	WorldCasting._auto_cast(w, p, DT, Vector2.RIGHT)
	assert_near(p.cds[World.SP_ARCANE], cd * Spells.CAST_FLOOR * w.tune.spell_cd_mul, 0.0001, "below the cast floor")


func test_justice_bursts_are_queued_and_never_chain() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	var victim := _orc(w, Vector2(300, 300))
	var plain := _world()
	var plain_victim := _orc(plain, Vector2(300, 300))
	plain._damage_enemy(plain_victim, 1e6, 0, Vector2.ZERO)
	assert_true(plain.bursts.is_empty(), "a wizard without JUSTICE made a burst")
	p.upgrades[Upgrades.JUSTICE] = 3
	# Slay until one bursts (18% a kill); the burst waits in the queue, nothing it would hit is hurt yet.
	var neighbour := _orc(w, Vector2(300 + Upgrades.JUSTICE_RADIUS - 2.0, 300))
	neighbour.hp = victim.maxhp * Upgrades.JUSTICE_SHARE * 0.5 # the burst slays it
	var far := _orc(w, Vector2(300 + Upgrades.JUSTICE_RADIUS + 20.0, 300))
	var tries := 0
	while w.bursts.is_empty() and tries < 200:
		var e := _orc(w, Vector2(300, 300))
		w._damage_enemy(e, 1e6, 0, Vector2.ZERO)
		tries += 1
	assert_eq(w.bursts.size(), 1, "no burst in %d kills" % tries)
	assert_true(neighbour.hp > 0.0 and not neighbour.dead, "the burst went off inside the damage call")
	w._build_grid()
	w.take_events()
	WorldCasting._update_bursts(w)
	assert_true(neighbour.dead, "the burst missed a foe within its radius")
	assert_eq(far.hp, far.maxhp, "the burst reached too far")
	assert_true(w.bursts.is_empty(), "a burst kill queued another burst")
	assert_false(w.bursting)
	assert_eq(_codes(w.take_events(), World.EV_BURST).size(), 1)
	assert_true(w.record.source_damage.has(Results.SRC_JUSTICE))


func test_cleave_sweeps_the_arc_once_and_knocks_back() -> void:
	var w := _world()
	var knight := _hero(w, 0, Classes.KNIGHT)
	assert_eq(Upgrades.weapon_level(knight.upgrades, World.SP_CLEAVE), 1, "the knight holds CLEAVE")
	assert_eq(knight.skin, "cleave")
	var from := knight.pos + Vector2(0, -4)
	var front := _orc(w, from + Vector2(25, 0))
	var side := _orc(w, from + Vector2(20, 0).rotated(0.7))
	var behind := _orc(w, from + Vector2(-25, 0))
	var beyond := _orc(w, from + Vector2(Spells.stat(World.SP_CLEAVE, "r") + 25.0, 0))
	w._build_grid()
	w.take_events()
	w._cast(knight, World.SP_CLEAVE, 1, false, Vector2.RIGHT)
	var dmg := front.maxhp - front.hp
	assert_true(dmg > 0.0, "the foe in front was not cleaved")
	assert_near(side.maxhp - side.hp, dmg, 0.001, "the foe in the arc took another share")
	assert_eq(behind.hp, behind.maxhp, "the sweep hit behind the knight")
	assert_eq(beyond.hp, beyond.maxhp, "the sweep reached too far")
	assert_true(front.knock.x > 0.0, "no knock-back")
	var sweeps := _codes(w.take_events(), World.EV_SWEEP)
	assert_eq(sweeps.size(), 1)
	assert_near((sweeps[0][3] as Vector3).x, 0.0, 0.001)
	assert_eq(int(sweeps[0][4]), 0, "a plain CLEAVE's event is the slot alone")


func test_cleave_waits_for_a_foe_it_can_reach_and_turns_to_it() -> void:
	var w := _world()
	var knight := _hero(w, 0, Classes.KNIGHT)
	var from := knight.pos + Vector2(0, -4)
	var reach := Spells.stat(World.SP_CLEAVE, "r")
	var orc := _orc(w, from + Vector2(reach + 12.0 + 8.0, 0))
	w._build_grid()
	assert_eq(WorldCastSweep._sweep_dir(w, knight, World.SP_CLEAVE, Vector2.ZERO), Vector2.ZERO,
		"it swung at a foe just out of reach")
	orc.pos = from + Vector2(-20, 0)
	w._build_grid()
	var free := WorldCastSweep._sweep_dir(w, knight, World.SP_CLEAVE, Vector2.ZERO)
	assert_near(free.x, -1.0, 0.001, "it did not turn to the foe")
	var away := WorldCastSweep._sweep_dir(w, knight, World.SP_CLEAVE, Vector2.RIGHT)
	assert_near(away.x, -1.0, 0.001, "aiming away, it swung at the air and not at the foe behind")
	var onto := WorldCastSweep._sweep_dir(w, knight, World.SP_CLEAVE, Vector2(-1, 0.5))
	assert_near(onto.angle(), Vector2(-1, 0.5).angle(), 0.001, "a foe in the aimed arc: it swings along the aim")


func test_cleave_is_only_offered_to_who_holds_it() -> void:
	assert_false(Upgrades.available({}, Upgrades.W_CLEAVE), "CLEAVE offered to a wizard without it")
	var levels := {Upgrades.W_CLEAVE: 1}
	assert_true(Upgrades.available(levels, Upgrades.W_CLEAVE), "a knight cannot level CLEAVE")
	assert_true(Upgrades.take(levels, Upgrades.W_CLEAVE))


## WHIRLWIND: CLEAVE at its top level and STRENGTH, a passive no other evolution pairs with; a wizard without CLEAVE
## is never offered it, and STRENGTH weighs as a partner only for one who holds CLEAVE.
func test_whirlwind_needs_cleave_at_its_top_and_strength() -> void:
	assert_eq(Upgrades.evo_entry(World.SP_CLEAVE), Upgrades.E_CLEAVE)
	assert_true(Spells.has_evolution(World.SP_CLEAVE))
	assert_eq(Spells.passive_partner(World.SP_CLEAVE), "power")
	assert_eq(Upgrades.partner_row(World.SP_CLEAVE), Upgrades.POWER)
	for sp: int in range(Spells.COUNT):
		if sp != World.SP_CLEAVE:
			assert_true(Upgrades.partner_row(sp) != Upgrades.POWER, "STRENGTH partners spell %d too" % sp)
	assert_false(Upgrades.available({Upgrades.POWER: 5, Upgrades.W_ARCANE: 5}, Upgrades.E_CLEAVE), "offered to a mage")
	assert_false(Upgrades.pairs_with({Upgrades.W_ARCANE: 5}, Upgrades.POWER), "STRENGTH pairs for a mage")
	assert_eq(Upgrades.roll_weight({Upgrades.W_ARCANE: 5}, Upgrades.POWER), float(Upgrades.CATALOG[Upgrades.POWER][Upgrades.C_WEIGHT]))
	assert_true(Upgrades.pairs_with({Upgrades.W_CLEAVE: 2}, Upgrades.POWER), "STRENGTH does not pair for a knight")
	assert_false(Upgrades.available({Upgrades.W_CLEAVE: 4, Upgrades.POWER: 1}, Upgrades.E_CLEAVE), "offered below the top level")
	assert_false(Upgrades.available({Upgrades.W_CLEAVE: 5}, Upgrades.E_CLEAVE), "offered without STRENGTH")
	assert_true(Upgrades.available({Upgrades.W_CLEAVE: 5, Upgrades.POWER: 1}, Upgrades.E_CLEAVE))


## WHIRLWIND strikes at most its `most` foes a swing, the nearest first; CLEAVE has no such cap.
func test_whirlwind_strikes_only_its_nearest_few() -> void:
	var w := _world()
	var knight := _hero(w, 0, Classes.KNIGHT)
	var most := int(Spells.evo_value(World.SP_CLEAVE, "most", 1, 0.0))
	assert_true(most > 0, "WHIRLWIND has no cap")
	var from := knight.pos + Vector2(0, -4)
	var orcs: Array[World.Enemy] = []
	for i: int in range(most + 2):
		orcs.append(_orc(w, from + Vector2.from_angle(i * 1.3) * (12.0 + 4.0 * i)))
	w._build_grid()
	w._cast(knight, World.SP_CLEAVE, Spells.MAX_LEVEL, true, Vector2.RIGHT)
	for i: int in range(orcs.size()):
		assert_eq(orcs[i].hp < orcs[i].maxhp, i < most, "orc %d (nearest first)" % i)
	assert_eq(Spells.evo_value(World.SP_CLEAVE, "most", 1, 0.0), float(most))
	assert_false(Spells.STATS[World.SP_CLEAVE].has("most"), "CLEAVE itself is capped")


## WHIRLWIND swings all the way round with a longer reach and its own numbers, and its event says it is evolved.
func test_whirlwind_sweeps_a_full_circle_further() -> void:
	var w := _world()
	var knight := _hero(w, 0, Classes.KNIGHT)
	knight.upgrades[Upgrades.W_CLEAVE] = Spells.MAX_LEVEL
	knight.upgrades[Upgrades.E_CLEAVE] = 1
	var from := knight.pos + Vector2(0, -4)
	var reach := Spells.level_value(World.SP_CLEAVE, "r", Spells.MAX_LEVEL, 1)
	assert_true(reach > Spells.stat(World.SP_CLEAVE, "r"), "no longer reach")
	assert_near(Spells.level_value(World.SP_CLEAVE, "arc", Spells.MAX_LEVEL, 1), TAU, 0.0001)
	var front := _orc(w, from + Vector2(25, 0))
	var behind := _orc(w, from + Vector2(-25, 0))
	var far := _orc(w, from + Vector2(0, Spells.stat(World.SP_CLEAVE, "r") + 8.0 + 2.0))
	var beyond := _orc(w, from + Vector2(reach + 25.0, 0))
	w._build_grid()
	w.take_events()
	w._cast(knight, World.SP_CLEAVE, Spells.MAX_LEVEL, true, Vector2.RIGHT)
	var want := Spells.damage(World.SP_CLEAVE, Spells.MAX_LEVEL, 1) * Classes.skin_value("cleave", "dmg_mul", 1.0)
	assert_true(front.maxhp - front.hp > 0.0, "the foe in front was not hit")
	assert_near(behind.maxhp - behind.hp, front.maxhp - front.hp, 0.001, "the foe behind was not hit alike")
	assert_true(far.hp < far.maxhp, "the longer reach did not hit")
	assert_eq(beyond.hp, beyond.maxhp, "it reached too far")
	assert_true(behind.knock.x < 0.0, "the foe behind is not knocked away")
	assert_true(want > Spells.damage(World.SP_CLEAVE, Spells.MAX_LEVEL, 0) * Classes.skin_value("cleave", "dmg_mul", 1.0))
	var sweeps := _codes(w.take_events(), World.EV_SWEEP)
	assert_eq(sweeps.size(), 1)
	assert_eq(int(sweeps[0][4]) & 7, 0, "the slot")
	assert_true(int(sweeps[0][4]) & 8 != 0, "the event does not say it is evolved")
	for e: World.Enemy in [front, far, beyond]:
		e.pos = from + Vector2(400, 0)
	behind.pos = from + Vector2(-(reach + behind.r - 2.0), 0)
	w._build_grid()
	assert_eq(WorldCastSweep._sweep_dir(w, knight, World.SP_CLEAVE, Vector2.ZERO, false), Vector2.ZERO, "CLEAVE reaches it")
	assert_near(WorldCastSweep._sweep_dir(w, knight, World.SP_CLEAVE, Vector2.ZERO, true).x, -1.0, 0.001,
		"WHIRLWIND does not turn to a foe in its reach")
	assert_eq(WorldCastSweep._sweep_dir(w, knight, World.SP_CLEAVE, Vector2.RIGHT, true), Vector2.RIGHT,
		"a full circle swings along the aim with a foe anywhere in reach")


func test_holy_light_heals_the_most_hurt_hero_inside_her_too() -> void:
	var w := _world(2)
	var priest := _hero(w, 0, Classes.PRIEST)
	var friend: World.Player = w.players[1]
	assert_eq(priest.skin, "holy_light")
	w._build_grid()
	w._cast(priest, World.SP_CANDLE, 1, false, Vector2.RIGHT)
	var c: World.Rune = w.runes[0]
	c.life = 100.0
	priest.pos = c.pos
	priest.hp = priest.max_hp - 1
	friend.pos = c.pos + Vector2(3, 0)
	friend.hp = friend.max_hp - 3
	w.take_events()
	var every := Classes.skin_value("holy_light", "heal_every")
	_burn(w, every - 0.5)
	assert_eq(friend.hp, friend.max_hp - 3, "healed before its time")
	_burn(w, 0.6)
	assert_eq(friend.hp, friend.max_hp - 2, "the most hurt hero was not healed")
	assert_eq(_codes(w.take_events(), World.EV_HEAL).size(), 1)
	friend.hp = friend.max_hp
	_burn(w, every)
	assert_eq(priest.hp, priest.max_hp, "a priest heals herself")


func test_consecration_heals_every_ten_seconds() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	p.upgrades = {Upgrades.W_CANDLE: Spells.MAX_LEVEL, Upgrades.E_CANDLE: 1}
	w._build_grid()
	w._cast(p, World.SP_CANDLE, Spells.MAX_LEVEL, true, Vector2.RIGHT)
	for c: World.Rune in w.runes:
		c.life = 100.0
	p.pos = w.runes[0].pos
	p.hp = p.max_hp - 2
	_burn(w, Spells.evo_value(World.SP_CANDLE, "heal_every", 1, 0.0) - 0.5)
	assert_eq(p.hp, p.max_hp - 2)
	_burn(w, 0.6)
	assert_eq(p.hp, p.max_hp - 1)
	var plain := _world()
	var q: World.Player = plain.players[0]
	plain._cast(q, World.SP_CANDLE, Spells.MAX_LEVEL, false, Vector2.RIGHT)
	plain.runes[0].life = 100.0
	q.pos = plain.runes[0].pos
	q.hp = q.max_hp - 2
	_burn(plain, 12.0)
	assert_eq(q.hp, q.max_hp - 2, "an unevolved candle healed")


func test_new_entries_pair_with_their_passives() -> void:
	var levels := {Upgrades.W_BONE: Spells.MAX_LEVEL}
	assert_true(Upgrades.pairs_with(levels, Upgrades.JUSTICE), "JUSTICE does not complete BONE SPEAR's pair")
	assert_false(Upgrades.available(levels, Upgrades.E_BONE))
	Upgrades.take(levels, Upgrades.JUSTICE)
	assert_true(Upgrades.available(levels, Upgrades.E_BONE))
	assert_eq(Upgrades.partner_row(World.SP_CANDLE), Upgrades.LOVERS)
	assert_near(Upgrades.justice_chance({Upgrades.JUSTICE: 2}), 0.12)
	assert_near(Upgrades.lovers_bonus({Upgrades.LOVERS: 1}, false), 0.04)


## A class skin's dmg_mul and cd_mul (Classes.SKINS) apply to her class weapon only: a paladin's SMITE hits harder
## than a mage's STARFALL, and a STARFALL or BONE SPEAR she did not start with is the row as it is.
func test_skin_numbers_scale_only_the_class_weapon() -> void:
	var w := _world(2)
	var paladin := _hero(w, 0, Classes.PALADIN)
	var mage := _hero(w, 1, Classes.MAGE)
	assert_eq(paladin.class_weapon, World.SP_STAR)
	var mul := Classes.skin_value("smite", "dmg_mul", 1.0)
	assert_true(mul > 1.0, "SMITE has a damage multiplier")
	assert_near(WorldCasting._skin_mul(paladin, World.SP_STAR, "dmg_mul"), mul)
	assert_near(WorldCasting._skin_mul(paladin, World.SP_STAR, "cd_mul"), Classes.skin_value("smite", "cd_mul", 1.0))
	assert_near(WorldCasting._skin_mul(paladin, World.SP_BONE, "dmg_mul"), 1.0, 0.0001, "a picked-up spell is plain")
	assert_near(WorldCasting._skin_mul(mage, World.SP_STAR, "dmg_mul"), 1.0, 0.0001, "the mage wears no skin")
	w._cast(paladin, World.SP_STAR, 1, false, Vector2.RIGHT)
	w._cast(mage, World.SP_STAR, 1, false, Vector2.RIGHT)
	w._cast(paladin, World.SP_BONE, 1, false, Vector2.RIGHT)
	for s: World.Shot in w.shots:
		var want := Spells.damage(s.spell, 1, 0) * (mul if s.owner == 0 and s.spell == World.SP_STAR else 1.0)
		assert_near(s.dmg, want, 0.0001, "shot of spell %d by slot %d" % [s.spell, s.owner])


## The knight's CLEAVE knocks knock_mul times as hard as a plain CLEAVE (a mage who drew the card).
func test_the_knights_cleave_knocks_further() -> void:
	var w := _world(2)
	var knight := _hero(w, 0, Classes.KNIGHT)
	var mage := _hero(w, 1, Classes.MAGE)
	mage.upgrades[Upgrades.weapon_entry(World.SP_CLEAVE)] = 1
	var a := _orc(w, knight.pos + Vector2(20, -4))
	var b := _orc(w, mage.pos + Vector2(20, -4))
	w._build_grid()
	w._cast(knight, World.SP_CLEAVE, 1, false, Vector2.RIGHT)
	w._cast(mage, World.SP_CLEAVE, 1, false, Vector2.RIGHT)
	assert_true(b.knock.x > 0.0, "the plain cleave knocks back")
	# his skin's knock-back, up to the most one blow may add (Bestiary.KNOCK_MAX, scaled like the blow by the orc's heft)
	var heft: float = b.knock.x / Spells.SWEEP_KNOCK
	var want: float = minf(b.knock.x * Classes.skin_value("cleave", "knock_mul", 1.0), Bestiary.KNOCK_MAX * heft)
	assert_near(a.knock.x, want, 0.001)
	assert_true(a.knock.x > b.knock.x * 2.0, "the knight's cleave knocks at least twice as far")


func test_a_sweep_reaches_a_wide_body_by_its_edge() -> void:
	var w := _world(1)
	var knight := _hero(w, 0, Classes.KNIGHT)
	var reach := Spells.stat(World.SP_CLEAVE, "r")
	var big := _orc(w, knight.pos)
	big.r = 30.0 # as wide as a boss: its centre lies outside the reach and half a grid cell
	big.pos = knight.pos + Vector2(0, -4) + Vector2(0, reach + big.r - 1.0) # its edge a pixel inside the reach
	w._build_grid()
	w._cast(knight, World.SP_CLEAVE, 1, false, Vector2.DOWN)
	assert_true(big.hp < big.maxhp, "the sweep missed a wide body whose edge it reaches")

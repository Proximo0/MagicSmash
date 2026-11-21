extends TestCase
## Classes: the class table and its accessors (game/logic/classes.gd), and what World.apply_hero and the nova
## button's skills do with them (World.apply_hero, WorldPlayers._skill, threat in WorldEnemies).

const STEP := 1.0 / 60.0


func _hero(r: int, c: int, sch: int = 0) -> Dictionary:
	return Hero.make(r, c, sch).to_dict()


## A world past its intro with wizards at fixed spots, `cls` per slot applied as HUMAN heroes (-1: no hero).
func _world(classes: Array, seed_value: int = 5) -> World:
	var slots: Array = []
	for i: int in range(classes.size()):
		slots.append(i)
	var w := World.new(slots, seed_value, Tuning.new())
	for i: int in range(classes.size()):
		if int(classes[i]) >= 0:
			w.apply_hero(w.players[i], _hero(Races.HUMAN, int(classes[i])))
		w.players[i].invuln = 0.0
	w.phase = World.PH_FIGHT
	return w


func test_rows_have_every_column_and_unique_keys() -> void:
	var keys := {}
	for c: int in range(Classes.count()):
		var row: Array = Classes.ROWS[c]
		assert_eq(row.size(), Classes.C_AURA_WARD + 1, Classes.key(c))
		assert_eq((row[Classes.C_STATS] as Array).size(), Loot.STAT_COUNT)
		assert_false(keys.has(Classes.key(c)), "duplicate key")
		keys[Classes.key(c)] = true
		assert_eq(Classes.index_of(Classes.key(c)), c)
		assert_true(Classes.skill(c) >= 0 and Classes.skill(c) < Classes.skill_count())
		assert_true(Classes.weapon(c) >= 0 and Classes.weapon(c) < Spells.COUNT)
		assert_true(not Classes.skin(c).is_empty())
	assert_eq(Classes.index_of("necromancer"), -1)
	assert_eq(Classes.count(), 5)


func test_launch_classes_match_the_design_table() -> void:
	var want := {
		"mage": [5, 1.0, Classes.SK_NOVA, Classes.ROLE_DAMAGE],
		"knight": [7, 2.5, Classes.SK_PROVOKE, Classes.ROLE_TANK],
		"archer": [4, 0.8, Classes.SK_VOLLEY, Classes.ROLE_RANGED],
		"priest": [5, 0.7, Classes.SK_SANCTUARY, Classes.ROLE_HEALER],
		"paladin": [6, 1.6, Classes.SK_AEGIS, Classes.ROLE_SUPPORT],
	}
	for k: String in want:
		var c := Classes.index_of(k)
		assert_eq(Classes.hearts(c), int(want[k][0]), k)
		assert_near(Classes.threat(c), float(want[k][1]))
		assert_eq(Classes.skill(c), int(want[k][2]), k)
		assert_eq(Classes.role(c), int(want[k][3]), k)
		assert_eq(Classes.class_name_of(c), k.to_upper())
	assert_eq(Classes.MAGE, 0, "row 0 is the mage: a wizard with no hero is one")
	assert_near(Classes.walk_mul(Classes.KNIGHT), 0.94)
	assert_near(Classes.walk_mul(Classes.ARCHER), 1.08)
	assert_near(Classes.ritual_mul(Classes.PRIEST), 2.0)
	assert_eq(Classes.extra_redraws(Classes.MAGE), 2)
	assert_near(Classes.aura_radius(Classes.PALADIN), 50.0)
	assert_eq(Classes.aura_ward(Classes.PALADIN), 8)
	assert_near(Classes.aura_radius(Classes.KNIGHT), 0.0)


func test_weapons_mage_school_and_stand_ins() -> void:
	for sch: int in range(Wizards.count()):
		assert_eq(Classes.weapon(Classes.MAGE, sch), Wizards.start_spell(sch))
	assert_eq(Classes.weapon(Classes.PALADIN), World.SP_STAR, "SMITE is the STARFALL row")
	assert_eq(Classes.weapon(Classes.KNIGHT), World.SP_FROST, "CLEAVE stands in as the FROST FAN until C2")
	assert_eq(Classes.weapon(Classes.ARCHER), World.SP_ARCANE, "LONGBOW stands in as the ARCANE BOLT until C2")
	assert_eq(Classes.weapon(Classes.PRIEST), World.SP_RUNE, "HOLY LIGHT stands in as the RUNE CIRCLE until C2")


func test_skills_table() -> void:
	assert_eq(Classes.skill_count(), 5)
	assert_eq(Classes.skill_key(Classes.SK_PROVOKE), "provoke")
	assert_eq(Classes.skill_name(Classes.SK_AEGIS), "AEGIS")
	assert_near(Classes.skill_value(Classes.SK_PROVOKE, "radius"), 100.0)
	assert_near(Classes.skill_value(Classes.SK_VOLLEY, "arrows"), 12.0)
	assert_near(Classes.skill_value(Classes.SK_NOVA, "radius", -1.0), -1.0, 0.0001, "a missing number is the default")


func test_a_wizard_with_no_hero_keeps_every_default() -> void:
	var w := World.new([0, 1], 3, Tuning.new(), {}, {0: {"race": 0, "cls": 0}})
	for p: World.Player in w.players.values():
		assert_eq(p.max_hp, World.BASE_HEARTS)
		assert_near(p.threat, 1.0)
		assert_eq(p.threat_k, 1.0, "exactly one")
		assert_eq(p.skill, Classes.SK_NOVA)
		assert_eq(p.walk_mul, 1.0)
		assert_eq(p.ritual_mul, 1.0)
		assert_eq(p.redraws, Upgrades.REDRAWS)
		assert_eq(p.armor, Loot.empty_stats())
	assert_eq(w.threat_spread, 1.0)


func test_apply_hero_hearts_stats_threat_and_passives_per_class() -> void:
	for c: int in range(Classes.count()):
		var w := World.new([0], 3, Tuning.new())
		var p: World.Player = w.players[0]
		var h := Hero.make(Races.DWARF, c)
		w.apply_hero(p, h.to_dict())
		var st := h.stats()
		assert_eq(p.cls, c)
		assert_eq(p.race, Races.DWARF)
		assert_eq(p.cls_level, 1)
		assert_eq(p.max_hp, Classes.hearts(c) + int(float(st[Loot.ST_VIGOR])), Classes.key(c))
		assert_eq(p.hp, p.max_hp)
		for i: int in range(Loot.STAT_COUNT):
			assert_near(float(p.armor[i]), float(st[i]))
		assert_near(p.threat, Classes.threat(c))
		assert_near(p.threat_k, 1.0 / (Classes.threat(c) * Classes.threat(c)))
		assert_eq(p.skill, Classes.skill(c))
		assert_near(p.walk_mul, Classes.walk_mul(c))
		assert_near(p.ritual_mul, Classes.ritual_mul(c))
		assert_eq(p.redraws, Upgrades.REDRAWS + Classes.extra_redraws(c))
		assert_eq(Upgrades.weapon_level(p.upgrades, Classes.weapon(c)), 1, "fights with the class weapon")
		assert_eq(p.spell, Classes.weapon(c))
		if Classes.weapon(c) != Wizards.start_spell(p.wizard):
			assert_eq(Upgrades.weapon_level(p.upgrades, Wizards.start_spell(p.wizard)), 0, "the starting spell made way")


func test_apply_hero_adds_to_the_meta_within_caps() -> void:
	var w := World.new([0], 3, Tuning.new())
	var meta := Loot.empty_stats()
	meta[Loot.ST_MIGHT] = 1.95
	meta[Loot.ST_VIGOR] = 1.0
	w.apply_meta({"hearts": 1.0, "armor": meta})
	var p: World.Player = w.players[0]
	assert_eq(p.max_hp, World.BASE_HEARTS + 2)
	var h := Hero.make(Races.ORC, Classes.KNIGHT)
	h.level = 9
	for i: int in range(8):
		h.spend_point(Loot.ST_VIGOR)
	w.apply_hero(p, h.to_dict())
	assert_near(float(p.armor[Loot.ST_MIGHT]), float(Loot.STAT_CAPS[Loot.ST_MIGHT]), 0.0001, "capped")
	# Orc VIGOR 2 + 8 points = 10 points = 2.5 hearts on top of the meta's 1.0: 3.5, so 2 more whole hearts.
	assert_eq(p.max_hp, 1 + 7 + 3)


func test_the_mage_keeps_her_school_and_gets_two_redraws() -> void:
	var w := World.new([0], 3, Tuning.new(), {0: 0})
	var p: World.Player = w.players[0]
	w.apply_hero(p, _hero(Races.HUMAN, Classes.MAGE, 3))
	assert_eq(Upgrades.weapon_level(p.upgrades, World.SP_STORM), 1, "school 3 casts chain lightning")
	assert_eq(Upgrades.weapon_level(p.upgrades, World.SP_ARCANE), 0)
	assert_eq(p.redraws, Upgrades.REDRAWS + 2)
	for i: int in range(Upgrades.REDRAWS + 2):
		p.choices = [0]
		WorldLevels._redraw(w, p)
	assert_eq(p.redraws, 0, "every redraw spent")


func test_threat_changes_the_target() -> void:
	var w := _world([Classes.MAGE, Classes.KNIGHT])
	var mage: World.Player = w.players[0]
	var knight: World.Player = w.players[1]
	mage.pos = Vector2(300, 240)
	knight.pos = Vector2(500, 240)
	var at := Vector2(370, 240) # 70 px from the mage, 130 from the knight: 130 / 2.5 = 52 < 70
	assert_eq(WorldEnemies._nearest_player(w, at), knight)
	var e := w.spawn_enemy(World.GOBLIN, 0, at)
	e.entering = false
	w._build_grid()
	WorldEnemies._sep_fill(w)
	WorldEnemies._update_enemy(w, e, STEP)
	assert_true(e.vel.x > 0.0, "walks toward the knight")
	# Every threat 1: the nearest, as ever.
	var plain := World.new([0, 1], 5, Tuning.new())
	plain.players[0].pos = mage.pos
	plain.players[1].pos = knight.pos
	assert_eq(WorldEnemies._nearest_player(plain, at), plain.players[0])


func test_skill_costs_a_charge_and_emits() -> void:
	for c: int in range(Classes.count()):
		var w := _world([c, Classes.MAGE])
		var p: World.Player = w.players[0]
		var before := p.bombs
		w.take_events()
		WorldPlayers._skill(w, p)
		assert_eq(p.bombs, before - 1, Classes.key(c))
		var codes: Array = w.take_events().map(func(ev: Array) -> int: return int(ev[0]))
		if c == Classes.MAGE:
			assert_true(codes.has(World.EV_NOVA) and not codes.has(World.EV_SKILL))
		else:
			assert_true(codes.has(World.EV_SKILL), Classes.key(c))


func test_the_nova_button_fires_the_skill_and_respects_the_seal() -> void:
	var w := _world([Classes.PALADIN])
	var p: World.Player = w.players[0]
	var inp := PackedFloat32Array([0, 0, 0, 0, 0, 0, -1, 0])
	w.step(STEP, {0: inp})
	inp[5] = 1
	w.step(STEP, {0: inp})
	assert_eq(p.bombs, 1, "one charge spent")
	assert_true(p.invuln >= Classes.skill_value(Classes.SK_AEGIS, "safe") - 0.1)
	w.nova_sealed = 5.0
	inp[5] = 2
	w.step(STEP, {0: inp})
	assert_eq(p.bombs, 1, "THE HANGED MAN seals skills too")


func test_provoke_taunts_and_shields() -> void:
	var w := _world([Classes.MAGE, Classes.KNIGHT])
	var mage: World.Player = w.players[0]
	var knight: World.Player = w.players[1]
	mage.pos = Vector2(300, 240)
	knight.pos = Vector2(390, 240)
	var near := w.spawn_enemy(World.GOBLIN, 0, Vector2(310, 240)) # 10 px from the mage, 80 from the knight
	var far := w.spawn_enemy(World.GOBLIN, 0, Vector2(600, 240))
	near.entering = false
	far.entering = false
	WorldPlayers._skill(w, knight)
	assert_eq(near.taunt, knight)
	assert_near(near.taunt_t, Classes.skill_value(Classes.SK_PROVOKE, "taunt"))
	assert_eq(far.taunt, null, "out of reach")
	assert_true(knight.invuln >= Classes.skill_value(Classes.SK_PROVOKE, "safe"))
	w._build_grid()
	WorldEnemies._sep_fill(w)
	WorldEnemies._update_enemy(w, near, STEP)
	assert_true(near.vel.x > 0.0, "it walks away from the mage beside it, to the knight")
	near.taunt_t = 0.001
	WorldEnemies._update_enemy(w, near, STEP)
	near.vel = Vector2.ZERO
	WorldEnemies._update_enemy(w, near, STEP)
	assert_true(near.vel.x < 0.0, "the taunt ran out: back to the mage")


func test_volley_rolls_and_looses_arrows_behind() -> void:
	var w := _world([Classes.ARCHER])
	var p: World.Player = w.players[0]
	p.pos = Vector2(400, 240)
	p.moving = true
	p.vel = Vector2(100, 0)
	WorldPlayers._skill(w, p)
	assert_near(p.pos.x, 400.0 + Classes.skill_value(Classes.SK_VOLLEY, "roll"))
	assert_true(p.invuln >= Classes.skill_value(Classes.SK_VOLLEY, "safe"))
	assert_eq(w.shots.size(), int(Classes.skill_value(Classes.SK_VOLLEY, "arrows")))
	for s: World.Shot in w.shots:
		assert_true(s.vel.x < 0.0, "behind her")
		assert_eq(s.owner, 0)


func test_sanctuary_heals_the_standing_and_raises_the_near_fallen() -> void:
	var w := _world([Classes.PRIEST, Classes.MAGE, Classes.MAGE])
	var priest: World.Player = w.players[0]
	priest.pos = Vector2(400, 240)
	priest.hp = 1
	w.players[1].hp = w.players[1].max_hp - 1
	w.players[1].pos = Vector2(100, 100)
	var fallen: World.Player = w.players[2]
	fallen.pos = Vector2(450, 240)
	WorldPlayers._fall(w, fallen)
	w.take_events()
	WorldPlayers._skill(w, priest)
	assert_eq(priest.hp, 3, "a priest heals herself")
	assert_eq(w.players[1].hp, w.players[1].max_hp, "never past full")
	assert_true(fallen.alive, "risen")
	assert_eq(fallen.rituals, 1, "a raise by SANCTUARY counts as a ritual")
	var heals: Array = w.take_events().filter(func(ev: Array) -> bool: return int(ev[0]) == World.EV_HEAL)
	assert_eq(heals.size(), 2)
	assert_eq([int(heals[0][3]), int(heals[0][4])], [0, 2])
	assert_eq([int(heals[1][3]), int(heals[1][4])], [1, 1])
	var far := _world([Classes.PRIEST, Classes.MAGE])
	far.players[1].pos = far.players[0].pos + Vector2(Classes.skill_value(Classes.SK_SANCTUARY, "radius") + 5.0, 0)
	WorldPlayers._fall(far, far.players[1])
	WorldPlayers._skill(far, far.players[0])
	assert_true(far.players[1].down, "too far to rise")


func test_aegis_shields_heroes_near() -> void:
	var w := _world([Classes.PALADIN, Classes.MAGE, Classes.MAGE])
	w.players[0].pos = Vector2(400, 240)
	w.players[1].pos = Vector2(440, 240)
	w.players[2].pos = Vector2(400, 330)
	WorldPlayers._skill(w, w.players[0])
	var safe := Classes.skill_value(Classes.SK_AEGIS, "safe")
	assert_true(w.players[0].invuln >= safe)
	assert_true(w.players[1].invuln >= safe)
	assert_near(w.players[2].invuln, 0.0)
	w.players[1].hp = 3
	w.hurt_player(w.players[1], 1)
	assert_eq(w.players[1].hp, 3, "no damage under the aegis")


func test_walk_speed_follows_the_class() -> void:
	var w := _world([Classes.KNIGHT, Classes.ARCHER, -1])
	var starts: Array = []
	for i: int in range(3):
		w.players[i].pos = Vector2(200 + 150 * i, 240)
		starts.append(w.players[i].pos)
	var inp := PackedFloat32Array([0, 1, 0, 0, 0, 0, -1, 0])
	w.step(STEP, {0: inp, 1: inp, 2: inp})
	var plain: float = (w.players[2].pos - starts[2]).length()
	for i: int in range(2):
		var swift := 1.0 + float(w.players[i].armor[Loot.ST_SWIFT])
		assert_near((w.players[i].pos - starts[i]).length(), plain * [0.94, 1.08][i] * swift, 0.001)


func test_priest_rituals_twice_as_fast() -> void:
	var times: Array = []
	for c: int in [Classes.MAGE, Classes.PRIEST]:
		var w := _world([c, Classes.MAGE])
		var raiser: World.Player = w.players[0]
		var fallen: World.Player = w.players[1]
		WorldPlayers._fall(w, fallen)
		raiser.pos = fallen.pos
		var t := 0
		while fallen.down and t < 600:
			WorldPlayers._update_spirit(w, fallen, STEP, PackedFloat32Array(), false)
			raiser.invuln = 1.0
			t += 1
		times.append(t)
	assert_true(int(times[1]) * 2 <= int(times[0]) + 1, "the priest's ritual takes half: %s" % str(times))


func test_paladin_aura_wards_heroes_near() -> void:
	var w := _world([Classes.PALADIN, -1])
	var mage: World.Player = w.players[1]
	w.players[0].pos = Vector2(400, 240)
	mage.pos = Vector2(430, 240)
	mage.max_hp = 999
	mage.hp = 999
	var blocked := 0
	for i: int in range(400):
		mage.invuln = 0.0
		var hp := mage.hp
		w.hurt_player(mage, 1)
		if mage.hp == hp:
			blocked += 1
	assert_true(blocked > 10 and blocked < 70, "about 8 in 100 shrugged: %d of 400" % blocked)
	mage.pos = Vector2(600, 240)
	blocked = 0
	for i: int in range(200):
		mage.invuln = 0.0
		var hp := mage.hp
		w.hurt_player(mage, 1)
		if mage.hp == hp:
			blocked += 1
	assert_eq(blocked, 0, "out of the aura, a wizard with no hero has no WARD")


func test_the_elf_pulls_gems_from_farther() -> void:
	var w := _world([Classes.MAGE, Classes.MAGE])
	var elf: World.Player = w.players[1]
	w.apply_hero(elf, _hero(Races.ELF, Classes.MAGE))
	var who: Array[World.Player] = []
	var reach := PackedFloat64Array()
	WorldDrops._magnets(w, who, reach)
	var base: float = w.tune.xp_magnet_radius
	assert_near(reach[who.find(w.players[0])], base * Upgrades.magnet_mul(w.players[0].upgrades), 0.001)
	assert_near(reach[who.find(elf)], base * Upgrades.magnet_mul(elf.upgrades) * elf.reach_mul, 0.001)
	assert_true(elf.reach_mul > 1.0)


func test_a_taunt_dies_with_a_seat_that_left() -> void:
	var w := _world([Classes.KNIGHT, Classes.MAGE])
	var knight: World.Player = w.players[0]
	var mage: World.Player = w.players[1]
	knight.pos = Vector2(200, 200)
	mage.pos = Vector2(420, 240)
	var e := w.spawn_enemy(World.GOBLIN, 0, Vector2(400, 240))
	e.taunt = knight
	e.taunt_t = 3.0
	w.players.erase(0) # as a LAN leaver
	w._plist.assign(w.players.values())
	e.entering = false
	w._build_grid()
	WorldEnemies._sep_fill(w)
	WorldEnemies._update_enemy(w, e, STEP)
	assert_true(e.vel.x > 0.0, "it walks at the mage, not at where the knight was")

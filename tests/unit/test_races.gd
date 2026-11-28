extends TestCase
## Races: the race table and its accessors (game/logic/races.gd), and the traits World.apply_hero gives.


func test_rows_and_keys() -> void:
	assert_eq(Races.count(), 4)
	var keys := {}
	for r: int in range(Races.count()):
		var row: Array = Races.ROWS[r]
		assert_eq(row.size(), Races.R_BUILD + 1)
		assert_eq((row[Races.R_STATS] as Array).size(), Loot.STAT_COUNT)
		assert_false(keys.has(Races.key(r)))
		keys[Races.key(r)] = true
		assert_eq(Races.index_of(Races.key(r)), r)
		assert_eq(Races.race_name(r), Races.key(r).to_upper())
		assert_true(Races.trait_of(r) >= 0 and Races.trait_of(r) < Races.TRAITS.size())
	assert_eq(Races.index_of("undead"), -1)
	assert_eq(Races.HUMAN, 0, "row 0 is the human: a wizard with no hero is one")


func test_launch_races_match_the_design_table() -> void:
	assert_eq(Races.stat_points(Races.HUMAN), [1, 1, 1, 1, 1, 1])
	assert_eq(Races.stat_points(Races.ELF), [0, 3, 4, 0, 0, 0])
	assert_eq(Races.stat_points(Races.DWARF), [0, 0, 0, 4, 3, 0])
	assert_eq(Races.stat_points(Races.ORC), [5, 0, 0, 2, 0, 0])
	assert_eq(Races.trait_of(Races.HUMAN), Races.TR_SCHOLAR)
	assert_eq(Races.trait_of(Races.ELF), Races.TR_FAR_SIGHT)
	assert_eq(Races.trait_of(Races.DWARF), Races.TR_STURDY)
	assert_eq(Races.trait_of(Races.ORC), Races.TR_FURY)
	assert_eq(Races.build(Races.DWARF), Races.BUILD_SHORT)
	assert_eq(Races.build(Races.ORC), Races.BUILD_TALL)
	assert_eq(Races.build(Races.ELF), Races.BUILD_MEDIUM)
	assert_near(Races.trait_amount(Races.HUMAN, Races.TR_SCHOLAR), 0.05)
	assert_near(Races.trait_amount(Races.ELF, Races.TR_SCHOLAR), 0.0)
	assert_near(Races.trait_value(Races.TR_FAR_SIGHT), 0.25)
	assert_true(not Races.trait_name(Races.TR_FURY).is_empty())
	var copy := Races.stat_points(Races.ORC)
	copy[0] = 99
	assert_eq(int(Races.stat_points(Races.ORC)[0]), 5, "the table is not handed out to be changed")


func test_apply_hero_gives_the_race_traits() -> void:
	var w := World.new([0, 1, 2, 3], 3, Tuning.new())
	for r: int in range(Races.count()):
		w.apply_hero(w.players[r], Hero.make(r, Classes.MAGE).to_dict())
	assert_near(w.players[Races.ELF].reach_mul, 1.25)
	assert_near(w.players[Races.HUMAN].reach_mul, 1.0)
	assert_near(w.players[Races.DWARF].safe_mul, 1.5)
	assert_near(w.players[Races.ORC].safe_mul, 1.0)
	assert_near(w.players[Races.ORC].fury, 0.10)
	assert_near(w.players[Races.ELF].fury, 0.0)
	assert_near(float(w.players[Races.ELF].armor[Loot.ST_SWIFT]), 4 * float(Hero.POINT_VALUE[Loot.ST_SWIFT]))
	assert_near(w.players[Races.HUMAN].luck, Hero.LUCK_PER_FORTUNE)
	assert_eq(w.players[Races.DWARF].max_hp, World.BASE_HEARTS + 1, "4 VIGOR points are a heart")


## STURDY: a hit DWARF stays unhurt 1.5 times as long as a HUMAN of the same class.
func test_a_dwarf_stays_unhurt_longer_after_a_hit() -> void:
	assert_eq(Races.trait_name(Races.TR_STURDY), "UNHURT 50% LONGER AFTER A HIT")
	for cls: int in [Classes.MAGE, Classes.KNIGHT]:
		var w := World.new([0, 1], 3, Tuning.new())
		var hu: World.Player = w.players[0]
		var dw: World.Player = w.players[1]
		w.apply_hero(hu, Hero.make(Races.HUMAN, cls).to_dict())
		w.apply_hero(dw, Hero.make(Races.DWARF, cls).to_dict())
		for p: World.Player in [hu, dw]:
			p.armor[Loot.ST_WARD] = 0.0 # no hit shrugged off
			p.invuln = 0.0
			w.hurt_player(p, 1)
		assert_near(hu.invuln, Classes.hurt_safe(cls), 0.0001, "a human's safety is her class's")
		assert_near(dw.invuln, hu.invuln * 1.5, 0.0001, "a dwarf's lasts half again as long")


func test_orc_fury_at_two_hearts_or_fewer() -> void:
	var w := World.new([0], 3, Tuning.new())
	var p: World.Player = w.players[0]
	w.apply_hero(p, Hero.make(Races.ORC, Classes.MAGE).to_dict())
	var might: float = 1.0 + float(p.armor[Loot.ST_MIGHT])
	var e: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(100, 100))
	e.hp = 1000.0
	w._damage_enemy(e, 1.0, 0, Vector2.ZERO)
	assert_near(1000.0 - e.hp, might, 0.0001, "full hearts: no fury")
	p.hp = 2
	e.hp = 1000.0
	w._damage_enemy(e, 1.0, 0, Vector2.ZERO)
	assert_near(1000.0 - e.hp, might + 0.10, 0.0001, "two hearts: +10%")


func test_elf_spirit_reaches_farther() -> void:
	var w := World.new([0, 1], 3, Tuning.new())
	w.apply_hero(w.players[1], Hero.make(Races.ELF, Classes.MAGE).to_dict())
	var reach := w.tune.xp_magnet_radius
	for s: int in [0, 1]:
		var p: World.Player = w.players[s]
		WorldPlayers._fall(w, p)
		w._drop_xp(p.pos + Vector2(reach * 1.1, 0), Vector2.ZERO, 1)
		var k: World.Pickup = w.pickups[w.pickups.size() - 1]
		WorldPlayers._spirit_xp(w, p)
		if s == 0:
			assert_eq(k.vel, Vector2.ZERO, "out of a plain magnet's reach")
		else:
			assert_true(k.vel.x < 0.0, "the elf's magnet draws it in")

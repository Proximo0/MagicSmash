extends TestCase
## Hero: a saved hero's stats, levels, points, class XP and saved form (game/logic/hero.gd).


func test_a_new_hero_is_a_level_one_human_mage() -> void:
	var h := Hero.new()
	assert_eq(h.race, Races.HUMAN)
	assert_eq(h.cls, Classes.MAGE)
	assert_eq(h.level, 1)
	assert_eq(h.xp, 0)
	assert_eq(h.points_left(), 0)
	assert_eq(h.name, Hero.DEFAULT_NAME)
	assert_eq(h.weapon(), World.SP_ARCANE)


func test_stats_add_race_class_points_and_cards_within_caps() -> void:
	var h := Hero.make(Races.ORC, Classes.KNIGHT)
	var pts := h.sheet_points()
	for st: int in range(Loot.STAT_COUNT):
		assert_eq(pts[st], int(Races.stat_points(Races.ORC)[st]) + int(Classes.stat_points(Classes.KNIGHT)[st]))
	var st0 := h.stats()
	for st: int in range(Loot.STAT_COUNT):
		assert_near(float(st0[st]), pts[st] * float(Hero.POINT_VALUE[st]))
	h.sockets[Cards.STAFF] = "orc" # THE WARCHIEF: +10% damage
	assert_near(float(h.stats()[Loot.ST_MIGHT]), float(st0[Loot.ST_MIGHT]) + 0.10)
	h.sockets[Cards.STAFF] = "seal_8" # +35%
	h.level = Hero.MAX_LEVEL
	for i: int in range(Hero.MAX_POINTS):
		assert_true(h.spend_point(Loot.ST_MIGHT))
	assert_false(h.spend_point(Loot.ST_MIGHT), "at most 10 points in one stat")
	h.sockets[Cards.ROBE] = "gargoyle"
	for i: int in range(Hero.MAX_POINTS):
		h.spend_point(Loot.ST_VIGOR)
	var capped := h.stats()
	assert_near(float(capped[Loot.ST_VIGOR]), minf(2.0 + (2 + h.points[Loot.ST_VIGOR]) * 0.25, float(Loot.STAT_CAPS[Loot.ST_VIGOR])))
	for st: int in range(Loot.STAT_COUNT):
		assert_true(float(capped[st]) <= float(Loot.STAT_CAPS[st]) + 0.00001)
	assert_near(Hero.make(Races.HUMAN, Classes.MAGE).luck(), Hero.LUCK_PER_FORTUNE)


func test_xp_levels_and_points() -> void:
	var h := Hero.new()
	assert_eq(h.add_xp(99), 0)
	assert_eq(h.add_xp(1), 1, "100 XP: level 2")
	assert_eq(h.level, 2)
	assert_eq(h.xp, 0)
	assert_eq(h.add_xp(200 + 300 + 50), 2, "200 to level 3, 300 to level 4")
	assert_eq(h.level, 4)
	assert_eq(h.xp, 50)
	assert_eq(h.points_left(), 3, "a point a level")
	assert_true(h.spend_point(Loot.ST_WARD))
	assert_eq(h.points_left(), 2)
	assert_false(h.spend_point(-1))
	assert_false(h.spend_point(Loot.STAT_COUNT))
	var total := 0
	for lv: int in range(1, Hero.MAX_LEVEL):
		total += Hero.xp_to_next(lv)
	var top := Hero.new()
	assert_eq(top.add_xp(total + 5000), Hero.MAX_LEVEL - 1)
	assert_eq(top.level, Hero.MAX_LEVEL)
	assert_eq(top.xp, 0, "nothing past the top")
	assert_eq(top.add_xp(100), 0)
	assert_eq(top.points_left(), Hero.MAX_LEVEL - 1)
	assert_eq(h.add_xp(-50), 0, "no negative XP")


func test_class_xp_a_run_pays() -> void:
	assert_eq(Hero.class_xp(0.0, 0, false), 0)
	assert_eq(Hero.class_xp(359.0, 0, false), 50, "whole minutes: 5")
	assert_eq(Hero.class_xp(900.0, 3, true), 150 + 150 + 150)
	assert_eq(Hero.class_xp(600.0, 1, false, 1.5), roundi((100 + 50) * 1.5))
	assert_eq(Hero.class_xp(600.0, 1, false, -1.0), 0)
	var human := Hero.make(Races.HUMAN, Classes.KNIGHT)
	var elf := Hero.make(Races.ELF, Classes.KNIGHT)
	assert_eq(elf.run_xp(900.0, 3, true), 450)
	assert_eq(human.run_xp(900.0, 3, true), roundi(450 * 1.05), "a human earns 5% more")
	assert_eq(human.run_xp(600.0, 0, false, 2.0), roundi(100 * 2.0 * 1.05))


func test_saved_form_round_trips_through_json() -> void:
	var h := Hero.make(Races.DWARF, Classes.PALADIN, 2, "brunhild")
	h.look = Hero.pack_look(3, 5, 2)
	h.add_xp(100 + 200 + 40)
	h.spend_point(Loot.ST_VIGOR)
	h.spend_point(Loot.ST_WARD)
	h.sockets[Cards.HAT] = "bat"
	var d: Dictionary = h.to_dict()
	assert_eq(d["race"], "dwarf", "saves store keys")
	assert_eq(d["cls"], "paladin")
	var back := Hero.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(back.name, "BRUNHILD")
	assert_eq(back.race, Races.DWARF)
	assert_eq(back.cls, Classes.PALADIN)
	assert_eq(back.school, 2)
	assert_eq([back.look_skin(), back.look_hair(), back.look_style()], [3, 5, 2])
	assert_eq(back.level, 3)
	assert_eq(back.xp, 40)
	assert_eq(back.points, h.points)
	assert_eq(back.sockets, h.sockets)
	assert_eq(back.to_dict(), h.to_dict())


func test_bad_saved_data_is_clamped() -> void:
	var h := Hero.from_dict({"name": "   ", "race": "undead", "cls": "witch", "school": 9, "look": 9999, "level": 3,
		"xp": 99999, "points": [10, 50, -4, 1], "sockets": ["orc", "bat", "orc"]})
	assert_eq(h.name, Hero.DEFAULT_NAME)
	assert_eq(h.race, Races.HUMAN, "an unknown race is a human")
	assert_eq(h.cls, Classes.MAGE, "an unknown class is a mage")
	assert_eq(h.school, Wizards.count() - 1)
	assert_eq(h.look, Hero.SKINS * Hero.HAIRS * Hero.STYLES - 1)
	assert_eq(h.xp, Hero.xp_to_next(3) - 1)
	assert_eq(h.points_spent(), 2, "no more points than the level paid")
	assert_eq(h.points, [2, 0, 0, 0, 0, 0] as Array[int])
	assert_eq(h.sockets, ["", "", "orc"] as Array[String], "a card in the wrong socket is dropped")
	assert_eq(Hero.from_dict({}).to_dict(), Hero.new().to_dict())
	assert_eq(Hero.clean_name("a very long hero name"), "A VERY LONG ")


func test_the_developer_flag() -> void:
	var h := Hero.from_flag("orc,knight")
	assert_eq([h.race, h.cls, h.school], [Races.ORC, Classes.KNIGHT, 0])
	h = Hero.from_flag("Elf,MAGE,crimson")
	assert_eq([h.race, h.cls, h.school], [Races.ELF, Classes.MAGE, 1])
	h = Hero.from_flag("1,3,2")
	assert_eq([h.race, h.cls, h.school], [Races.ELF, Classes.PRIEST, 2])
	h = Hero.from_flag("human,mage,stormcaller")
	assert_eq(h.weapon(), World.SP_STORM)
	assert_eq(Hero.from_flag("orc"), null)
	assert_eq(Hero.from_flag("gnome,knight"), null)
	assert_eq(Hero.from_flag("orc,9"), null)

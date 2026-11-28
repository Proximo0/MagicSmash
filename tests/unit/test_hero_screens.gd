extends TestCase
## The hero screens' logic: the builder's steps, the roster's actions and the sheet's point spending
## (game/ui/hero_builder.gd, hero_roster.gd, hero_sheet.gd). Drawing is not tested.


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e


func _profile(n: int) -> Profile:
	var p := Profile.new()
	p.heroes = []
	for i: int in range(n):
		p.heroes.append(Hero.make(Races.HUMAN, Classes.MAGE, 0, "H%d" % i))
	p.hero = 0
	return p


func test_the_school_step_is_only_for_a_mage() -> void:
	assert_eq(HeroBuilder.next_step(HeroBuilder.S_CLASS, Classes.MAGE), HeroBuilder.S_SCHOOL)
	assert_eq(HeroBuilder.next_step(HeroBuilder.S_CLASS, Classes.KNIGHT), HeroBuilder.S_NAME)
	assert_eq(HeroBuilder.prev_step(HeroBuilder.S_NAME, Classes.PRIEST), HeroBuilder.S_CLASS)
	assert_eq(HeroBuilder.prev_step(HeroBuilder.S_NAME, Classes.MAGE), HeroBuilder.S_SCHOOL)
	var b := HeroBuilder.new()
	b.open(_profile(1))
	b.choose(Races.ELF)
	b.choose(Classes.ARCHER)
	assert_eq(b.step, HeroBuilder.S_NAME)
	assert_false(b.retreat())
	assert_eq(b.step, HeroBuilder.S_CLASS)
	assert_eq(b.sel, Classes.ARCHER, "the cursor returns to the stored choice")


func test_confirm_adds_the_hero_and_makes_it_active() -> void:
	var p := _profile(2)
	var b := HeroBuilder.new()
	b.open(p)
	b.choose(Races.ORC)
	b.choose(Classes.MAGE)
	b.choose(2)
	assert_eq(b.step, HeroBuilder.S_NAME)
	for ch: String in ["a", "s", "h"]:
		b.ouija.type_char(ch)
	b.submit_name()
	assert_eq(b.step, HeroBuilder.S_CONFIRM)
	assert_true(b.finish())
	assert_eq(p.heroes.size(), 3)
	assert_eq(p.hero, 2)
	assert_eq(p.active_hero().name, "ASH")
	assert_eq(p.active_hero().race, Races.ORC)
	assert_eq(p.active_hero().school, 2)
	assert_true(b.made == p.active_hero())
	assert_false(b.active)


func test_back_on_the_first_step_closes_and_makes_nothing() -> void:
	var p := _profile(1)
	var b := HeroBuilder.new()
	b.open(p)
	assert_true(b.handle(_key(KEY_ESCAPE)))
	assert_false(b.active)
	assert_eq(p.heroes.size(), 1)


func test_the_stat_line_lists_only_the_non_zero_stats() -> void:
	assert_eq(HeroBuilder.stat_line([3, 0, 0, 4, 0, 0]), "MIGHT +3  VIGOR +4")


func test_the_roster_hides_new_at_eight_heroes() -> void:
	var r := HeroRoster.new()
	r.open(_profile(Profile.MAX_HEROES - 1))
	assert_true(r.actions().has(HeroRoster.A_NEW))
	r.open(_profile(Profile.MAX_HEROES))
	assert_false(r.actions().has(HeroRoster.A_NEW))


func test_the_roster_never_deletes_the_last_hero() -> void:
	var p := _profile(2)
	var r := HeroRoster.new()
	r.open(p)
	assert_true(r.delete_selected())
	assert_eq(p.heroes.size(), 1)
	assert_false(r.can_delete())
	assert_false(r.delete_selected())
	assert_eq(p.heroes.size(), 1)
	r.do_action(HeroRoster.A_DELETE)
	r.update(HeroRoster.HOLD_TIME * 2.0)
	assert_eq(p.heroes.size(), 1)


func test_holding_confirm_on_delete_fills_then_deletes() -> void:
	var p := _profile(3)
	var r := HeroRoster.new()
	r.open(p)
	r.act = HeroRoster.A_DELETE
	r.sel = 1
	r.do_action(HeroRoster.A_DELETE)
	r.update(HeroRoster.HOLD_TIME * 0.5)
	assert_near(r.hold_fraction(), 0.5)
	assert_eq(p.heroes.size(), 3)
	r.update(HeroRoster.HOLD_TIME * 0.6)
	assert_eq(p.heroes.size(), 2)
	assert_eq(p.heroes[1].name, "H2")


func test_a_short_press_does_not_delete() -> void:
	var p := _profile(3)
	var r := HeroRoster.new()
	r.open(p)
	r.act = HeroRoster.A_DELETE
	r.do_action(HeroRoster.A_DELETE)
	r.update(HeroRoster.HOLD_TIME * 0.4)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_ENTER
	up.pressed = false
	r.handle(up)
	r.update(HeroRoster.HOLD_TIME)
	assert_eq(p.heroes.size(), 3)
	assert_near(r.hold_fraction(), 0.0)


func test_picking_a_row_makes_it_active_and_closes() -> void:
	var p := _profile(3)
	var r := HeroRoster.new()
	r.open(p)
	assert_false(r.handle(_key(KEY_DOWN)))
	assert_true(r.handle(_key(KEY_ENTER)))
	assert_eq(r.picked, 1)
	assert_eq(p.hero, 1)
	r.open(p)
	assert_true(r.handle(_key(KEY_ESCAPE)))
	assert_eq(r.picked, -1)


func test_the_sheet_spends_a_point() -> void:
	var p := _profile(1)
	p.heroes[0].add_xp(Hero.xp_to_next(1))
	var s := HeroSheet.new()
	s.open(p, 0)
	var left: int = p.heroes[0].points_left()
	assert_true(left > 0)
	s.sel = Loot.ST_VIGOR
	assert_false(s.handle(_key(KEY_ENTER)))
	assert_eq(p.heroes[0].points_left(), left - 1)
	assert_eq(p.heroes[0].points[Loot.ST_VIGOR], 1)
	assert_true(s.handle(_key(KEY_ESCAPE)))


func test_the_sheet_shows_a_class_weapon_with_its_skin_numbers() -> void:
	var plain := HeroSheet.weapon_line(World.SP_BONE)
	var bow := HeroSheet.weapon_line(World.SP_BONE, Classes.ARCHER)
	var want := "DMG %s  CD %sS  SHOTS %d" % [
		HeroSheet.num_text(Spells.damage(World.SP_BONE, 1, 0) * Classes.skin_value("longbow", "dmg_mul", 1.0)),
		HeroSheet.num_text(Spells.cooldown(World.SP_BONE, 1, 0) * Classes.skin_value("longbow", "cd_mul", 1.0)),
		Spells.count(World.SP_BONE, 1, 0)]
	assert_eq(bow, want)
	assert_true(bow != plain, "the archer's LONGBOW read like a plain BONE SPEAR")
	assert_eq(HeroSheet.weapon_line(World.SP_BONE, Classes.KNIGHT), plain, "a spear in a knight's hands is the plain row")
	assert_eq(HeroSheet.weapon_line(World.SP_ARCANE, Classes.MAGE), HeroSheet.weapon_line(World.SP_ARCANE))

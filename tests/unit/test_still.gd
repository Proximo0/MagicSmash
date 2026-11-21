extends TestCase
## Still: figures from one still picture, icons and scenes (game/art/still.gd, docs/art_dropin.md). The drop-in folder
## is a scratch one under the user folder; drawing needs a canvas, so the draw paths are checked through what they
## look up (names, fallbacks, files) and through the motion function.

var _dir := ""


func _drop(files: Array) -> void:
	_dir = OS.get_user_data_dir().path_join("still_test_%d" % Time.get_ticks_usec()) + "/"
	for f: String in files:
		var p := _dir + f
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var img := Image.create(6, 9, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.2, 0.2, 1.0))
		img.save_png(p)
	Art.drop_root = _dir
	Art.drop_only = true
	Art.forget()


func _clear() -> void:
	Art.drop_root = ""
	Art.drop_only = false
	Art.forget()
	for f: Array in Art.listed(_dir):
		DirAccess.remove_absolute("%s%s/%s.png" % [_dir, f[0], f[1]])


func test_the_three_groups_are_found_and_wanted() -> void:
	for g: String in ["sprites", "icons", "scenes"]:
		assert_true(Art.GROUPS.has(g), g)
	var want := Art.wanted()
	for w: Array in [["sprites", "hero_knight"], ["sprites", "apprentice"], ["sprites", "enemy_bloat"], ["sprites", "enemy_swords"],
			["sprites", "boss_chandelier"], ["sprites", "boss_ghostwriter"], ["sprites", "hub_lectern"],
			["sprites", "hub_mirror"], ["sprites", "hub_plinth"], ["sprites", "enemy_goblin"], ["sprites", "enemy_archlich"],
			["icons", "spell_fire"], ["icons", "evo_cleave"], ["icons", "passive_lovers"], ["icons", "class_paladin"],
			["icons", "race_orc"], ["icons", "deed_win"], ["icons", "deed_secret"], ["scenes", "builder"],
			["scenes", "deeds"], ["scenes", "lobby"], ["scenes", "album"], ["scenes", "sheet"]]:
		assert_true(want.has(w), "not wanted: %s/%s" % [w[0], w[1]])
	_drop(["sprites/hero_mage.png", "icons/spell_fire.png", "scenes/deeds.png"])
	assert_true(Art.has("sprites", "hero_mage"))
	assert_true(Art.has("icons", "spell_fire"))
	assert_true(Art.has("scenes", "deeds"))
	assert_eq(Art.image("sprites", "hero_mage").get_size(), Vector2i(6, 9))
	_clear()
	assert_false(Art.has("sprites", "hero_mage"))


func test_every_stand_in_and_boss_has_a_name() -> void:
	var n := Still.names()
	for k: String in ["bloat", "coffin", "guard", "cinderling", "censor", "hound", "shard", "swords"]:
		assert_true(n.has("enemy_" + k), k)
	assert_eq(Still.enemy_key(Bestiary.CHANDELIER), "boss_chandelier")
	assert_eq(Still.enemy_key(Bestiary.GHOSTWRITER), "boss_ghostwriter")
	assert_eq(Still.enemy_key(Bestiary.GOBLIN), "enemy_goblin")
	var seen := {}
	for s: String in n:
		assert_false(seen.has(s), "duplicate " + s)
		seen[s] = true


func test_hero_falls_back_apprentice_then_class_then_code() -> void:
	_drop([])
	assert_eq(Still.hero_name(Classes.MAGE, true), "")
	assert_eq(Still.hero_name(Classes.MAGE, false), "")
	_drop(["sprites/hero_mage.png"])
	assert_eq(Still.hero_name(Classes.MAGE, false), "hero_mage")
	assert_eq(Still.hero_name(Classes.MAGE, true), "hero_mage") # no apprentice picture: its class's
	assert_eq(Still.hero_name(Classes.KNIGHT, false), "")
	_clear()
	_drop(["sprites/hero_mage.png", "sprites/apprentice.png"])
	assert_eq(Still.hero_name(Classes.MAGE, true), "apprentice")
	assert_eq(Still.hero_name(Classes.MAGE, false), "hero_mage")
	assert_eq(Still.hero_name(Classes.KNIGHT, true), "apprentice")


func test_hero_shows_her_race_and_class_picture_before_her_class_picture() -> void:
	var elf := Races.index_of("elf")
	_drop(["sprites/hero_mage.png"])
	assert_eq(Still.hero_name(Classes.MAGE, false, elf), "hero_mage")
	_drop(["sprites/hero_mage.png", "sprites/hero_elf_mage.png"])
	assert_eq(Still.hero_name(Classes.MAGE, false, elf), "hero_elf_mage")
	assert_eq(Still.hero_name(Classes.MAGE, false, Races.index_of("orc")), "hero_mage")
	assert_eq(Still.hero_name(Classes.MAGE, false), "hero_mage") # no race given
	assert_eq(Still.hero_name(Classes.MAGE, false, 99), "hero_mage") # a race the game does not know
	assert_true(Still.names().has("hero_orc_paladin"))
	_clear()


func test_enemy_name_and_archlich() -> void:
	# Kinds the project holds no picture for (the code draws them), so the drop-in folder decides.
	_drop([])
	assert_eq(Still.enemy_name(Bestiary.GOBLIN), "")
	_drop(["sprites/enemy_goblin.png", "sprites/enemy_lich.png", "sprites/boss_chandelier.png"])
	assert_eq(Still.enemy_name(Bestiary.GOBLIN), "enemy_goblin")
	assert_eq(Still.enemy_name(Bestiary.CHANDELIER), "boss_chandelier")
	assert_eq(Still.enemy_name(Bestiary.LICH, false), "enemy_lich")
	assert_eq(Still.enemy_name(Bestiary.LICH, true), "") # the Archlich has its own picture
	assert_eq(Still.enemy_name(Bestiary.SKELETON), "")
	_clear()


func test_a_missing_file_draws_nothing_and_says_so() -> void:
	var n := Node2D.new()
	assert_false(Still.draw(n, "hero_nobody", Vector2(10, 10), 1, 0.0, false))
	assert_false(Still.draw_static(n, "hub_nobody", Vector2(10, 10)))
	assert_false(Still.draw_icon(n, "spell_nobody", Rect2(0, 0, 8, 8)))
	assert_false(Still.draw_scene(n, "nobody"))
	assert_eq(Still.icon("spell_nobody", 8), null)
	assert_eq(Still.icon("", 8), null)
	for kind: int in Bestiary.count(): # any kind whose picture has not arrived yet
		if not Still.has(Still.enemy_name(kind)):
			assert_false(EnemyView.draw_still(n, {"type": kind, "elite": false, "flip": false, "t": 0.0}, Vector2.ZERO,
				false, Color.WHITE, 0.0))
			break
	n.free()


func test_icon_names_follow_the_upgrade_keys() -> void:
	assert_eq(Still.icon_of("w_fire"), "spell_fire")
	assert_eq(Still.icon_of("e_storm"), "evo_storm")
	assert_eq(Still.icon_of("swift"), "passive_swift")
	assert_eq(Still.icon_of("cups"), "")
	var names := Still.icon_names()
	for i: int in Upgrades.count():
		var k := Upgrades.key(i)
		if Upgrades.kind(i) == Upgrades.MINOR:
			assert_false(names.has(Still.icon_of(k)) and not Still.icon_of(k).is_empty())
		else:
			assert_true(names.has(Still.icon_of(k)), k)
	for c: int in Classes.count():
		assert_true(names.has("class_" + Classes.key(c)))
	for r: int in Races.count():
		assert_true(names.has("race_" + Races.key(r)))


func test_walk_motion_bobs_and_leans_toward_the_facing() -> void:
	var up := 0.0
	for k: int in 100:
		var m := Still.motion(k * 0.01, true, 1)
		var off: Vector2 = m.off
		assert_true(off.y <= 0.0 and off.y >= -Still.WALK_BOB, "bob stays in range")
		assert_eq(off.x, 0.0)
		assert_true(float(m.lean) > 0.0, "leans right when facing right")
		assert_eq(m.squash, Vector2.ONE)
		up = minf(up, off.y)
		var l := Still.motion(k * 0.01, true, -1)
		assert_near(float(l.lean), -float(m.lean), 0.00001)
		assert_eq(l.off, m.off)
	assert_true(up < -Still.WALK_BOB * 0.9, "it reaches the top of the bob")


func test_idle_motion_breathes_slowly_and_never_shrinks() -> void:
	var tall := 1.0
	for k: int in 200:
		var m := Still.motion(k * 0.05, false, 1)
		assert_eq(m.off, Vector2.ZERO)
		assert_eq(float(m.lean), 0.0)
		var sq: Vector2 = m.squash
		assert_true(sq.y >= 1.0 and sq.y <= 1.0 + Still.BREATH + 0.00001)
		assert_true(sq.x <= 1.0 and sq.x >= 1.0 - Still.BREATH)
		tall = maxf(tall, sq.y)
	assert_true(tall > 1.0 + Still.BREATH * 0.9)
	# The same inputs give the same answer.
	assert_eq(Still.motion(1.234, false, -1), Still.motion(1.234, false, -1))


func test_deed_marks_map_the_rule_kinds() -> void:
	assert_eq(Still.deed_icon("WIN_MAGE"), "deed_win")
	assert_eq(Still.deed_icon("WIN_ORC"), "deed_win")
	assert_eq(Still.deed_icon("WIN_SEAL_3"), "deed_win")
	assert_eq(Still.deed_icon("BOSS_CHANDELIER"), "deed_slay")
	assert_eq(Still.deed_icon("KILLS_1K"), "deed_slay")
	assert_eq(Still.deed_icon("FAST_WIN"), "deed_time")
	assert_eq(Still.deed_icon("ALL_SECRETS"), "deed_secret")
	assert_eq(Still.deed_icon("EVO_FIRE"), "") # an evolution keeps today's mark
	assert_eq(Still.deed_icon("REVIVE_3"), "")
	assert_eq(Still.deed_icon("NO_SUCH_DEED"), "")
	for api: String in Achievements.RULES:
		var ic := Still.deed_icon(api)
		assert_true(ic.is_empty() or Still.icon_names().has(ic), api)


func test_scene_dim_leaves_text_readable() -> void:
	assert_true(Still.SCENE_DIM.r < 0.6 and Still.SCENE_DIM.g < 0.6 and Still.SCENE_DIM.b < 0.6)

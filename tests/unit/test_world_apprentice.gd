extends TestCase
## World apprentices: computer wizards that fill a seat (game/logic/world/apprentices.gd, World.humans, pscale,
## remove_player). The seat roster itself is tests/unit/test_net_roster.gd.

const DT := 1.0 / 60.0


## Two wizards: slot 0 a human at the arena centre, slot 1 an apprentice `apart` px to her right.
func _pair(apart: float = 0.0) -> World:
	var w := World.new([0, 1], 3, null, {}, {1: {"ai": true}})
	var c := G.ARENA.get_center()
	w.players[0].pos = c
	w.players[1].pos = c + Vector2(apart, 0)
	for p: World.Player in w.players.values():
		p.invuln = 0.0
	return w


func _idle() -> PackedFloat32Array:
	return PackedFloat32Array([0, 0, 0, 0, 0, 0])


func test_every_wizard_is_human_by_default() -> void:
	var w := World.new([0, 1, 2], 3)
	assert_eq(w.humans().size(), 3)
	for p: World.Player in w.players.values():
		assert_false(p.ai)
		assert_eq(p.trait_a, 0)
		assert_eq(p.trait_b, 0)
	assert_near(w.pscale(), 1.0 + w.tune.spawn_party_scale * 2.0, 0.0001, "three full wizards")
	var pl: PackedFloat32Array = w.snapshot()["p"]
	assert_eq(pl[World.P_AI], 0.0)
	for k: int in [World.P_RACE, World.P_CLASS, World.P_LOOK, World.P_CLASS_LEVEL]:
		assert_eq(pl[k], 0.0, "races and classes are reserved at 0")
	assert_near(w.players[0].threat, 1.0)
	var seated := World.new([0], 3, null, {}, {0: {"ai": false, "race": 2, "cls": 1, "look": 5, "cls_level": 3}})
	var row: PackedFloat32Array = seated.snapshot()["p"]
	assert_eq([int(row[World.P_RACE]), int(row[World.P_CLASS]), int(row[World.P_LOOK]), int(row[World.P_CLASS_LEVEL])],
		[2, 1, 5, 3], "roster extras pass through to the row untouched")
	w.players[2].ai = true
	assert_eq(w.humans().size(), 2)
	assert_eq(G.DEV_AI, -2)
	assert_eq(G.DEV_KB2, -3)


func test_damage_and_spawn_weight_rows() -> void:
	var w := _pair()
	assert_near(w.tune.apprentice_damage, 0.7)
	assert_near(w.tune.apprentice_scale, 0.7)
	assert_near(w.pscale(), 1.0 + w.tune.spawn_party_scale * 0.7, 0.0001, "an apprentice counts 0.7")
	var base := w.tune.xp_to_next(w.party_level)
	assert_eq(w.xp_needed(), int(round(base * (1.0 + w.tune.xp_party_scale * 0.7))), "for the XP a level needs too")
	assert_true(w.record.ai.get(1, false), "the results know the apprentice's column")
	assert_eq(int(w.snapshot()["p"][World.P_FLOATS + World.P_AI]), 1)
	var at := G.ARENA.get_center() + Vector2(0, 80)
	var a := w.spawn_enemy(World.SKELETON, 0, at)
	var b := w.spawn_enemy(World.SKELETON, 0, at)
	a.entering = false
	b.entering = false
	var hp := a.hp
	w.damage_enemy(a, 1.0, 0, Vector2.ZERO, true)
	w.damage_enemy(b, 1.0, 1, Vector2.ZERO, true)
	assert_near((hp - b.hp) / (hp - a.hp), 0.7, 0.0001, "an apprentice hits for 0.7")


func test_health_counts_an_apprentice_as_part_of_a_wizard() -> void:
	var humans := World.new([0, 1, 2], 3)
	assert_eq(humans.party_weight(), 3.0)
	assert_eq(Bosses.party_share(humans), float(Bosses.party_hp_from(humans.tune)[2]), "the table row, exactly")
	var w := World.new([0, 1, 2], 3, null, {}, {1: {"ai": true}, 2: {"ai": true}})
	var k: float = w.tune.apprentice_scale
	assert_near(w.party_weight(), 1.0 + 2.0 * k, 0.0001)
	var table: Array = Bosses.party_hp_from(w.tune)
	var share := Bosses.party_share(w)
	assert_true(share > float(table[0]) and share < float(table[2]), "between solo and three wizards")
	assert_near(share, 1.0 + w.tune.boss_hp_per_player * 2.0 * k, 0.0001, "a straight line on the default table")
	var alone := World.new([0], 3, null, {}, {0: {"ai": true}})
	assert_eq(alone.party_weight(), 1.0, "never under one wizard")
	var solo := World.new([0], 3)
	var e1 := solo.spawn_enemy(World.GOBLIN, 0, Vector2(300, 200))
	var e2 := w.spawn_enemy(World.GOBLIN, 0, Vector2(300, 200))
	assert_near(e2.hp / e1.hp, 1.0 + w.tune.enemy_hp_per_player * 2.0 * k, 0.01)


func test_no_loot_for_apprentices() -> void:
	var w := _pair(300.0)
	var ap: World.Player = w.players[1]
	for kind: int in [World.PK_CHEST, World.PK_CHEST_RARE, World.PK_CHEST_ULTRA, World.PK_CARD, World.PK_TOME_FIRE,
			World.PK_TOME_RUNE]:
		w._drop(kind, ap.pos, Vector2.ZERO, 9.0, 1)
	WorldDrops._update_pickups(w, DT)
	assert_eq(w.pickups.size(), 6, "chests, cards and tomes stay on the floor")
	assert_eq(w.record.stat(1, "chests"), 0.0)
	assert_true(w.cards_found.is_empty())
	w._drop(World.PK_CHEST, w.players[0].pos, Vector2.ZERO, 9.0, 1)
	WorldDrops._update_pickups(w, DT)
	assert_eq(w.record.stat(0, "chests"), 1.0, "a human opens hers")


func test_no_bets_or_fate_cards() -> void:
	var w := _pair(300.0)
	var ap: World.Player = w.players[1]
	ap.gold = 9999.0
	for kind: int in [Gamble.SOLO, Gamble.TEAM]:
		var sh := World.Shrine.new()
		sh.kind = kind
		sh.pos = ap.pos
		sh.cost = 1
		w.shrines.append(sh)
	for i: int in range(int(w.tune.shrine_hold / DT) + 30):
		WorldShrines._update_shrines(w, DT)
	assert_near(ap.gold, 9999.0, 0.001, "an apprentice never pays a shrine")
	assert_true(w._gambles.is_empty(), "no bet or fate card is drawn")
	for sh: World.Shrine in w.shrines:
		assert_near(sh.charge, 0.0)


func test_coins_and_gems_go_to_the_nearest_human() -> void:
	var w := World.new([0, 1, 2], 3, null, {}, {1: {"ai": true}})
	var c := G.ARENA.get_center()
	w.players[0].pos = c + Vector2(-200, 0)
	w.players[1].pos = c
	w.players[2].pos = c + Vector2(60, 0)
	w._drop(World.PK_COIN, c, Vector2.ZERO, 9.0, 0)
	w._drop(World.PK_GEM, c, Vector2.ZERO, 9.0, 0)
	WorldDrops._update_pickups(w, DT)
	assert_true(w.pickups.is_empty(), "the apprentice picks them up")
	assert_near(w.players[1].gold, 0.0)
	assert_eq(w.players[1].score, 0)
	assert_true(w.players[2].gold > 0.0, "the nearest human is paid")
	assert_near(w.players[0].gold, 0.0)
	assert_eq(w.players[2].score, 600)


func test_potion_rule() -> void:
	var w := _pair(300.0)
	var ap: World.Player = w.players[1]
	var hu: World.Player = w.players[0]
	ap.hp = 3
	w._drop(World.PK_POTION, ap.pos, Vector2.ZERO, 9.0, 0)
	WorldDrops._update_pickups(w, DT)
	assert_eq(w.pickups.size(), 1, "3 hearts: no potion")
	ap.hp = 2
	hu.hp = hu.max_hp - 1
	WorldDrops._update_pickups(w, DT)
	assert_eq(w.pickups.size(), 1, "a hurt human comes first")
	hu.hp = hu.max_hp
	WorldDrops._update_pickups(w, DT)
	assert_true(w.pickups.is_empty())
	assert_eq(ap.hp, 2 + w.seal_potion_heal)


func test_a_fallen_apprentice_gets_up_by_itself() -> void:
	var w := _pair(400.0)
	var ap: World.Player = w.players[1]
	var lives := ap.lives
	w.hurt_player(ap, 99)
	assert_true(ap.down)
	for i: int in range(int(w.tune.apprentice_up_time / DT) - 2):
		WorldPlayers._update_spirit(w, ap, DT, _idle(), false)
	assert_true(ap.down, "not before apprentice_up_time")
	for i: int in range(4):
		if ap.down:
			WorldPlayers._update_spirit(w, ap, DT, _idle(), false)
	assert_true(ap.alive, "up after 6 s")
	assert_eq(ap.lives, lives, "free")
	var dark := _pair(400.0)
	dark.apply_seal(World.SEAL_MAX)
	var dp: World.Player = dark.players[1]
	dark.hurt_player(dp, 99)
	for i: int in range(int((dark.tune.apprentice_up_time + 1.0) / DT)):
		WorldPlayers._update_spirit(dark, dp, DT, _idle(), false)
	assert_true(dp.down, "never under DARKNESS")


func test_an_away_human_keeps_her_lives_and_her_cards() -> void:
	var w := World.new([0, 1], 3, null, {}, {1: {"ai": true, "away": true}})
	var c := G.ARENA.get_center()
	w.players[0].pos = c
	var gone: World.Player = w.players[1]
	gone.pos = c + Vector2(400, 0)
	assert_true(gone.ai, "the World plays her seat")
	assert_true(gone.away)
	gone.invuln = 0.0
	w.hurt_player(gone, 99)
	assert_true(gone.down)
	for i: int in range(int((w.tune.apprentice_up_time + 1.0) / DT)):
		WorldPlayers._update_spirit(w, gone, DT, _idle(), false)
		assert_false(WorldApprentices.gets_up(w, gone))
	gone.pending = 1
	WorldLevels._update_levelups(w, {})
	assert_false(gone.choices.is_empty(), "the hand is dealt")
	WorldLevels._update_levelups(w, {})
	assert_false(gone.choices.is_empty(), "and waits for her")
	assert_false(World.new([0], 3, null, {}, {0: {"away": true}}).players[0].away, "away means nothing on a played seat's own")


## An away human (her seat ai and away) keeps her loot: chests, cards and tomes she touches are hers, her coins and
## gems pay her, and an apprentice's coin goes to her when she is the nearest human.
func test_an_away_human_keeps_her_loot() -> void:
	var w := World.new([0, 1, 2], 3, null, {}, {1: {"ai": true, "away": true}, 2: {"ai": true}})
	var c := G.ARENA.get_center()
	var gone: World.Player = w.players[1]
	w.players[0].pos = c + Vector2(-200, 0)
	gone.pos = c
	w.players[2].pos = c + Vector2(200, 0)
	for kind: int in [World.PK_CHEST, World.PK_CARD, World.PK_TOME_FIRE, World.PK_COIN, World.PK_GEM]:
		w._drop(kind, gone.pos, Vector2.ZERO, 9.0, 1)
	WorldDrops._update_pickups(w, DT)
	assert_true(w.pickups.is_empty(), "she takes all of it")
	assert_eq(w.record.stat(1, "chests"), 1.0, "she opens her chest")
	assert_eq(w.cards_found, [1] as Array[int], "and keeps her card")
	assert_true(gone.gold > 0.0, "her coins pay her")
	assert_near(w.players[0].gold, 0.0)
	w.players[2].pos = c + Vector2(40, 0)
	var before := gone.gold
	w._drop(World.PK_COIN, w.players[2].pos, Vector2.ZERO, 9.0, 0)
	WorldDrops._update_pickups(w, DT)
	assert_true(gone.gold > before, "the apprentice's coin goes to the nearest human, away or not")
	assert_true(WorldApprentices.is_human_seat(gone))
	assert_false(WorldApprentices.is_human_seat(w.players[2]))
	assert_eq(WorldApprentices.human_seats(w).size(), 2)
	assert_eq(w.humans().size(), 1, "humans() keeps its meaning")


func test_the_world_plays_an_apprentice_with_no_input() -> void:
	var w := _pair(60.0)
	w.phase_t = 100.0 # the intro holds: no horde
	var start: Vector2 = w.players[1].pos
	for i: int in range(120):
		w.step(DT, {0: _idle()})
	assert_true(w.apprentice_bots.has(1), "a brain for the apprentice")
	assert_false(w.apprentice_bots.has(0), "none for the human")
	var bot: SmashBot = w.apprentice_bots[1]
	assert_true(bot.apprentice)
	assert_true(bot.thinks >= 120 / SmashBot.APPRENTICE_TICKS - 1 and bot.thinks <= 120 / SmashBot.APPRENTICE_TICKS + 1,
		"it decides every third tick")
	assert_true(w.players[1].pos.distance_to(start) > 1.0, "it walks")
	# A human seat given input is never played by the World, even when flagged.
	var given := _pair(60.0)
	given.step(DT, {0: _idle(), 1: _idle()})
	assert_false(given.apprentice_bots.has(1))


func test_it_answers_a_call() -> void:
	var w := _pair(300.0) # beyond SmashBot.RESCUE_REACH: only the call brings it
	w.phase_t = 100.0
	var hu: World.Player = w.players[0]
	w.hurt_player(hu, 99)
	assert_true(hu.down)
	w.step(DT, {0: _idle()})
	var revived := false
	for i: int in range(60 * 8):
		var inp := _idle()
		inp[5] = 1.0 # the human presses her nova once: a call
		w.step(DT, {0: inp})
		for ev: Array in w.take_events():
			if int(ev[0]) == World.EV_REVIVE and int(ev[3]) == 0 and int(ev[4]) == 1:
				revived = true
		if revived:
			break
	assert_true(revived, "the apprentice walked into her circle and raised her")


func test_the_run_ends_with_its_humans() -> void:
	var w := _pair()
	var hu: World.Player = w.players[0]
	hu.alive = false
	hu.lives = 0
	w.step(DT, {0: _idle()})
	assert_eq(w.phase, World.PH_GAMEOVER, "an apprentice alone does not play on")
	var last := _pair(300.0)
	var hu2: World.Player = last.players[0]
	hu2.lives = 1
	last.hurt_player(hu2, 99)
	assert_true(hu2.down)
	last.step(DT, {0: _idle()})
	assert_true(last.phase != World.PH_GAMEOVER, "fallen on her last life, the apprentice can still raise her")


func test_remove_player_keeps_score_and_kills() -> void:
	var w := _pair()
	w.players[1].score = 500
	w.players[1].kills = 7
	w.players[1].level = 4
	var score := w.total_score()
	var kills := w.total_kills()
	w.remove_player(1)
	assert_false(w.players.has(1))
	assert_eq(w._plist.size(), 1, "the cached list is refreshed")
	assert_eq(w.total_score(), score)
	assert_eq(w.total_kills(), kills)
	assert_eq(w.record.stat(1, "kills"), 7.0)
	assert_eq(w.record.stat(1, "level"), 4.0)
	w.step(DT, {0: _idle()})
	assert_near(w.party_center().x, w.players[0].pos.x, 0.01, "the centre is hers alone")


func test_a_nan_input_moves_nothing() -> void:
	var w := _pair()
	w.phase_t = 100.0
	w.step(DT, {0: PackedFloat32Array([NAN, NAN, INF, NAN, 0, 0]), 1: _idle()})
	var p: World.Player = w.players[0]
	assert_true(is_finite(p.pos.x) and is_finite(p.pos.y))
	assert_true(is_finite(p.aim.x) and is_finite(p.aim.y))
	assert_false(WorldPlayers.input_finite(PackedFloat32Array([0, NAN])))
	assert_true(WorldPlayers.input_finite(PackedFloat32Array([0, 1])))


func test_an_apprentice_seated_with_a_class_becomes_that_hero() -> void:
	var w := World.new([0, 1, 2], 3, null, {}, {1: {"ai": true, "cls": Classes.KNIGHT, "race": 0, "cls_level": 1},
		2: {"ai": true}})
	w.apply_meta({"hearts": 1.0})
	var knight: World.Player = w.players[1]
	assert_eq(knight.skill, Classes.SK_NOVA, "nothing before the run starts")
	w.step(DT, {0: _idle()})
	var ref := World.new([0], 3)
	ref.apply_meta({"hearts": 1.0})
	ref.apply_hero(ref.players[0], Hero.make(Races.HUMAN, Classes.KNIGHT, knight.wizard).to_dict())
	var want: World.Player = ref.players[0]
	assert_eq(knight.cls, Classes.KNIGHT)
	assert_eq(knight.skill, Classes.SK_PROVOKE)
	assert_near(knight.threat, Classes.threat(Classes.KNIGHT))
	assert_eq(knight.max_hp, want.max_hp, "applied after the meta, as Arena applies a human's hero")
	assert_eq(knight.upgrades, want.upgrades, "the class weapon")
	var plain: World.Player = w.players[2]
	assert_eq(plain.skill, Classes.SK_NOVA, "a seat with no class level stays a plain wizard")
	assert_near(plain.threat, 1.0)
	# Still an apprentice: its damage, weight and loot rules stack on the class.
	assert_true(knight.ai)
	assert_false(WorldApprentices.may_take(w, knight, World.PK_CHEST))
	# It plays the class: the brain reads the knight's skill.
	assert_true(w.apprentice_bots.has(1))


func test_an_apprentice_takes_its_class_once() -> void:
	var w := World.new([0, 1], 3, null, {}, {1: {"ai": true, "cls": Classes.KNIGHT, "race": 0, "cls_level": 1}})
	var knight: World.Player = w.players[1]
	# A tool that asks for the apprentices' inputs itself and then steps: the class is applied by the first ask only.
	WorldApprentices.with_inputs(w, {0: _idle()})
	var hearts := knight.max_hp
	var armor: Array = knight.armor.duplicate()
	w.step(DT, WorldApprentices.with_inputs(w, {0: _idle()}))
	assert_eq(knight.max_hp, hearts, "the knight's hearts were given twice")
	assert_eq(knight.armor, armor, "the knight's stats were given twice")


func test_a_classed_apprentice_answers_with_its_skill() -> void:
	# A knight apprentice beside a human with goblins on her: it provokes (casual hands, so give it a few chances).
	var w := World.new([0, 1], 4, null, {}, {1: {"ai": true, "cls": Classes.KNIGHT, "race": 0, "cls_level": 1}})
	var c := G.ARENA.get_center()
	w.players[0].pos = c
	w.players[1].pos = c + Vector2(30, 0)
	w.phase_t = 100.0
	w.step(DT, {0: _idle()})
	for i: int in range(5):
		var e: World.Enemy = w.spawn_enemy(World.GOBLIN, 0, c + Vector2.from_angle(i * 1.3) * 20.0)
		e.hp = 1e6
	var used := false
	for i: int in range(300): # casual hands forget now and then (SmashBot.FORGET_HOLD): five seconds of chances
		w.step(DT, {0: _idle()})
		for ev: Array in w.take_events():
			if int(ev[0]) == World.EV_SKILL and int(ev[3]) == 1:
				used = true
	assert_true(used, "PROVOKE when enemies are on an ally")

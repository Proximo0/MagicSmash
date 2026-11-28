extends TestCase
## Sfx: the voice rule (which player a new sound takes), the priority table and the buses (game/autoload/sfx.gd).


func _pool(prio: int, n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append(prio)
	return a


func _all(v: bool, n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append(v)
	return a


func _ages(n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append(float(n - i) * 0.01) # player 0 has played longest
	return a


func test_a_free_player_comes_first() -> void:
	var prios := _pool(1, 4)
	var playing := _all(true, 4)
	playing[2] = false
	assert_eq(Sfx.pick_voice(prios, playing, _ages(4), 0), 2)


func test_twenty_small_sounds_never_cut_a_roar() -> void:
	var prios := _pool(0, Sfx.POOL)
	var playing := _all(true, Sfx.POOL)
	var ages := _ages(Sfx.POOL)
	prios[0] = Sfx.PRIO_BOSS # the roar: it has played the longest
	ages[0] = 1.7
	for k in 40:
		var i: int = Sfx.pick_voice(prios, playing, ages, Sfx.PRIO_SMALL)
		assert_true(i > 0, "a small sound took the roar's player")
		ages[i] = 0.0 # it starts now; the others age
		for j in Sfx.POOL:
			if j != i:
				ages[j] = float(ages[j]) + 0.01


func test_a_roar_takes_a_small_sounds_player_the_lowest_and_longest() -> void:
	var prios := _pool(1, 5)
	var ages := [0.5, 0.2, 0.9, 0.3, 0.1]
	prios[1] = 0
	prios[3] = 0
	prios[2] = Sfx.PRIO_BOSS
	assert_eq(Sfx.pick_voice(prios, _all(true, 5), ages, Sfx.PRIO_BOSS), 3, "priority 0 first, then the longest played")


func test_the_longest_played_goes_among_equals() -> void:
	assert_eq(Sfx.pick_voice(_pool(1, 3), _all(true, 3), [0.1, 0.4, 0.2], 1), 1)


func test_a_pool_full_of_roars_drops_a_hit() -> void:
	assert_eq(Sfx.pick_voice(_pool(Sfx.PRIO_BOSS, Sfx.POOL), _all(true, Sfx.POOL), _ages(Sfx.POOL), 0), -1)
	assert_eq(Sfx.pick_voice(_pool(1, 3), _all(true, 3), _ages(3), 0), -1, "a hit never cuts a normal sound")


func test_a_roar_may_cut_another_roar_only_when_nothing_lower_plays() -> void:
	var prios := _pool(Sfx.PRIO_BOSS, 3)
	assert_eq(Sfx.pick_voice(prios, _all(true, 3), [0.1, 0.5, 0.2], Sfx.PRIO_BOSS), 1)


func test_priority_table() -> void:
	for n in ["boss_roar", "gong", "bell_toll", "boss_phase", "down", "revive", "victory"]:
		assert_eq(Sfx.priority_of(n), Sfx.PRIO_BOSS, n)
	for n in ["enemy_die", "hit", "enemy_die_3", "hit_2"]:
		assert_eq(Sfx.priority_of(n), Sfx.PRIO_SMALL, n)
	assert_eq(Sfx.priority_of("coin"), Sfx.PRIO_NORMAL)
	assert_eq(Sfx.priority_of("no_such_sound"), Sfx.PRIO_NORMAL)


func test_every_sound_has_a_file_and_variants_exist() -> void:
	for s: String in Sfx.SOUNDS:
		assert_true(FileAccess.file_exists("res://assets/audio/%s.wav" % s) or ResourceLoader.exists("res://assets/audio/%s.wav" % s), s)
	for base in ["enemy_die", "hit"]:
		for k in range(2, 5):
			assert_true(Sfx.SOUNDS.has("%s_%d" % [base, k]), "%s_%d" % [base, k])


func test_buses_exist_with_a_limiter_on_master() -> void:
	for b in [Sfx.BUS_MUSIC, Sfx.BUS_SFX, Sfx.BUS_UI]:
		var i := AudioServer.get_bus_index(b)
		assert_true(i > 0, b)
		assert_eq(String(AudioServer.get_bus_send(i)), "Master")
	var found := false
	for e in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, e) is AudioEffectHardLimiter:
			found = true
	assert_true(found, "Master has a hard limiter")


func test_set_volumes_sets_the_buses() -> void:
	var m := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Sfx.BUS_MUSIC))
	var s := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Sfx.BUS_SFX))
	var u := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Sfx.BUS_UI))
	Sfx.set_volumes(0.5, 0.25)
	var bm := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Sfx.BUS_MUSIC))
	var bs := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Sfx.BUS_SFX))
	var bu := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Sfx.BUS_UI))
	assert_true(absf(bm - linear_to_db(0.5)) < 0.01)
	assert_true(absf(bs - linear_to_db(0.25)) < 0.01)
	assert_true(absf(bu - linear_to_db(0.25)) < 0.01)
	Sfx.set_volumes(db_to_linear(m), db_to_linear(s)) # leave the volumes as they were
	assert_true(u != INF)

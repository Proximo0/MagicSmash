extends TestCase
## World: the authoritative simulation (game/logic/world.gd).

const DT: float = 1.0 / 60.0


func _run_bots(seed_value: int, slots: Array, ticks: int) -> World:
	var w := World.new(slots, seed_value)
	var bots: Dictionary = {}
	for s: int in slots:
		bots[s] = SmashBot.new(seed_value + s)
	for _i: int in range(ticks):
		var inputs: Dictionary = {}
		for s: int in slots:
			inputs[s] = (bots[s] as SmashBot).decide_in_world(w, s)
		w.step(DT, inputs)
	return w


func test_same_seed_same_run() -> void:
	var a: World = _run_bots(7, [0, 1], 900)
	var b: World = _run_bots(7, [0, 1], 900)
	assert_eq(a.state_hash(), b.state_hash(), "seed 7 runs diverged")


func test_different_seed_different_run() -> void:
	var a: World = _run_bots(7, [0, 1], 900)
	var b: World = _run_bots(8, [0, 1], 900)
	assert_true(a.state_hash() != b.state_hash(), "seeds 7 and 8 gave the same run")


func test_first_wave_spawns_after_intro() -> void:
	var w := World.new([0], 3)
	assert_eq(w.phase, World.PH_INTRO)
	for _i: int in range(60 * 6):
		w.step(DT, {})
	assert_eq(w.phase, World.PH_FIGHT)
	assert_true(w.enemies.size() > 0, "no enemies 6 s into wave 1")


func test_player_stays_inside_arena() -> void:
	var w := World.new([0], 3)
	var right := PackedFloat32Array([1, 0, 0, 0, 0, 0])
	for _i: int in range(60 * 5):
		w.step(DT, {0: right})
	var p: World.Player = w.players[0]
	assert_true(p.pos.x <= G.ARENA.end.x, "player left the arena: x=%.1f" % p.pos.x)


func test_nova_spends_a_bomb() -> void:
	var w := World.new([0], 3)
	var p: World.Player = w.players[0]
	var bombs: int = p.bombs
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 0])})
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 1])})
	assert_eq(p.bombs, bombs - 1)


func test_total_score_sums_players() -> void:
	var w := World.new([0, 1], 3)
	(w.players[0] as World.Player).score = 120
	(w.players[1] as World.Player).score = 30
	assert_eq(w.total_score(), 150)

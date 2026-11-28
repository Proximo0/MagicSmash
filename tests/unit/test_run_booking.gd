extends TestCase
## Ending a run books it once: game over, a confirmed QUIT TO TITLE or the window closing (World.run_so_far,
## ArenaEvents.book_run_once, the pause menu's question and who may use it).

const DT: float = 1.0 / 60.0
const IDLE := [0, 0, 0, 0, 0, 0]


func _world(seconds: float) -> World:
	var w := World.new([0], 7, Tuning.new())
	for i in int(seconds / DT):
		w.step(DT, {0: PackedFloat32Array(IDLE)})
	return w


func _pad(device: int, button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = true
	return e


func test_run_so_far_reports_a_run_not_won() -> void:
	var w := _world(20.0)
	var r: Dictionary = w.run_so_far()
	for k: String in ["score", "seconds", "kills", "liches", "won", "results"]:
		assert_true(r.has(k), "has " + k)
	assert_false(bool(r.won))
	assert_true(float(r.seconds) > 0.0)
	assert_eq(float(r.seconds), w.wave_time)
	assert_eq(int(r.score), w.total_score())
	assert_eq(int(r.kills), w.total_kills())
	assert_eq(float(r.results.stats[0].level), float(w.players[0].level))


func test_run_so_far_changes_nothing() -> void:
	var w := _world(10.0)
	var h := w.state_hash()
	var rec := var_to_str(w.record.to_dict())
	var rng := w.rng.state
	var first := var_to_str(w.run_so_far())
	assert_eq(var_to_str(w.run_so_far()), first, "twice, the same answer")
	assert_eq(w.state_hash(), h)
	assert_eq(var_to_str(w.record.to_dict()), rec, "the record is untouched")
	assert_eq(w.rng.state, rng)


func test_run_so_far_is_what_the_game_over_emits() -> void:
	var w := _world(10.0)
	w.take_events()
	var r: Dictionary = w.run_so_far()
	w._end_run()
	var evs := w.take_events()
	assert_eq(int(evs[0][0]), World.EV_RESULTS)
	assert_eq(var_to_str(evs[0][3]), var_to_str(r.results))
	assert_eq(int(evs[1][0]), World.EV_GAMEOVER)
	assert_eq(float(evs[1][1]), float(r.seconds))
	assert_eq(int(evs[1][2]), int(r.kills))
	assert_eq(int(evs[1][3]), int(r.score))
	assert_eq(int(evs[1][4]), int(r.liches))


func test_won_during_the_countdown_is_a_win() -> void:
	var w := _world(5.0)
	w.won = true
	w.victory_t = 3.0
	assert_true(bool(w.run_so_far().won))


## The arena's booking: once, whatever calls it, with the seal and act a game over would book.
func test_quit_books_the_run_once() -> void:
	var was: Profile = Save.profile
	Save.profile = Profile.new()
	var a := Arena.new()
	a.world = _world(15.0)
	a.seal = 2
	a.act = 1
	a._book_run_now()
	assert_true(a.run_booked)
	assert_eq(Save.profile.runs, 1)
	assert_eq(G.last_run.result, "loss")
	assert_eq(int(G.last_run.seal), 2)
	assert_eq(int(G.last_run.act), 1)
	var crystals := Save.profile.crystals
	var kills := Save.profile.kills_total
	assert_eq(kills, a.world.total_kills())
	a._book_run_now()
	ArenaEvents.book_run_once(a, {"score": 1, "seconds": 1.0, "kills": 1, "liches": 0, "won": false, "results": null})
	assert_eq(Save.profile.runs, 1, "a second call books nothing")
	assert_eq(Save.profile.crystals, crystals)
	assert_eq(Save.profile.kills_total, kills)
	var b := Arena.new()
	b.world = _world(5.0)
	b.world.won = true
	b.victory = true
	b.seal = 3
	b.act = 2
	b._book_run_now()
	assert_eq(G.last_run.result, "win", "quit in the victory countdown keeps the win")
	assert_eq(int(G.last_run.seal), 3)
	assert_eq(Save.profile.wins, 1)
	var c := Arena.new() # a LAN client has no World: nothing new is booked
	c._book_run_now()
	assert_eq(Save.profile.runs, 2)
	Save.profile = was
	a.free()
	b.free()
	c.free()


## QUIT TO TITLE asks first; NO is the default; who may pause, choose and end the run.
func test_pause_rules() -> void:
	var was_mode: Net.Mode = Net.mode
	var was_roster: Array = Net.roster
	Net.mode = Net.Mode.OFFLINE
	Net.roster = [{"slot": 0, "peer": Net.my_peer, "device": 0}, {"slot": 2, "peer": Net.my_peer, "device": 1}]
	var a := Arena.new()
	a._unhandled_input(_pad(5, JOY_BUTTON_START))
	assert_false(a.paused, "a pad without a seat cannot pause")
	a._unhandled_input(_pad(1, JOY_BUTTON_START))
	assert_true(a.paused)
	assert_eq(a.pause_by, 2, "P3 paused")
	a._unhandled_input(_pad(5, JOY_BUTTON_B))
	assert_true(a.paused, "a pad without a seat is not heard")
	a._pause_choose(2, 1)
	assert_false(a.pause_ask, "only P1 may end the run")
	assert_true(a.time - a.pause_note_t < 0.01, "the note shows")
	assert_true(a._pause_row_dim(2))
	a._pause_choose(2, 0)
	assert_true(a.pause_ask)
	assert_eq(a.pause_sel, 0, "NO is selected")
	a._unhandled_input(_pad(0, JOY_BUTTON_A))
	assert_false(a.pause_ask, "NO closes the question")
	assert_true(a.paused)
	a._unhandled_input(_pad(1, JOY_BUTTON_B))
	assert_false(a.paused, "back resumes")
	a.victory = true
	a._unhandled_input(_pad(0, JOY_BUTTON_START))
	assert_false(a.paused, "no manual pause in the victory countdown")
	a._auto_pause()
	assert_true(a.paused, "the automatic pause still works")
	assert_eq(a.pause_by, -1)
	Net.mode = was_mode
	Net.roster = was_roster
	a.free()

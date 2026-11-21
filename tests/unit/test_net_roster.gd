extends TestCase
## Net's seats (game/autoload/net.gd): apprentices by slot, a joining human, kept apprentices, silent seats, and
## the audit fixes that need no network (N3 join refusals, N4 input packets, L2/N1 reliable events).

var _was_roster: Array
var _was_kept: Array[int]
var _was_devices: Array[int]


func _save() -> void:
	_was_roster = Net.roster
	_was_kept = Net.kept_apprentices.duplicate()
	_was_devices = G.local_devices.duplicate()
	Net.kept_apprentices.clear()
	G.local_devices.assign([G.DEV_KBM])
	Net.start_offline()


func _restore() -> void:
	Net.roster = _was_roster
	Net.kept_apprentices.assign(_was_kept)
	G.local_devices.assign(_was_devices)
	Net.in_game = false


func _slots(rows: Array) -> Array:
	var out := []
	for r: Dictionary in rows:
		out.append(int(r.slot))
	return out


func test_apprentices_by_slot() -> void:
	_save()
	assert_eq(_slots(Net.my_slots()), [0])
	assert_eq(Net.add_apprentice(), 1)
	assert_eq(Net.add_apprentice(), 2)
	assert_eq(Net.add_apprentice(), 3)
	assert_eq(Net.add_apprentice(), -1, "the table is full")
	assert_eq(_slots(Net.ai_slots()), [1, 2, 3])
	assert_eq(_slots(Net.my_slots()), [0], "apprentices are no local seat")
	for r: Dictionary in Net.ai_slots():
		assert_eq(int(r.device), G.DEV_AI)
	assert_true(bool(Net.seat_builds()[2].ai))
	assert_false(bool(Net.seat_builds()[0].ai))
	assert_true(Net.remove_apprentice(), "the highest by default")
	assert_eq(_slots(Net.ai_slots()), [1, 2])
	assert_true(Net.remove_apprentice(1))
	assert_eq(_slots(Net.ai_slots()), [2])
	assert_false(Net.remove_apprentice(0), "a human seat is no apprentice")
	Net.in_game = true
	assert_eq(Net.add_apprentice(), -1, "not during a run")
	_restore()


func test_a_joining_human_takes_the_highest_apprentice() -> void:
	_save()
	Net.add_apprentice()
	Net.add_apprentice()
	var wiz: int = int(Net.roster[2].wizard)
	assert_eq(Net._add_to_roster(1, 0), 2, "the pad takes seat 3")
	var row: Dictionary = Net.roster[2]
	assert_false(bool(row.ai))
	assert_eq(int(row.device), 0)
	assert_eq(int(row.wizard), wiz, "keeping the wizard")
	assert_eq(_slots(Net.ai_slots()), [1])
	_restore()


func test_apprentices_are_kept_across_runs() -> void:
	_save()
	Net.add_apprentice()
	Net.add_apprentice()
	Net.cycle_wizard(G.DEV_KBM, 1)
	var wizards := []
	for r: Dictionary in Net.ai_slots():
		wizards.append(int(r.wizard))
	Net.start_offline()
	assert_eq(_slots(Net.ai_slots()), [1, 2], "seated again")
	var again := []
	for r: Dictionary in Net.ai_slots():
		again.append(int(r.wizard))
	assert_eq(again, wizards)
	Net.remove_apprentice()
	Net.remove_apprentice()
	Net.start_offline()
	assert_true(Net.ai_slots().is_empty())
	_restore()


func test_a_silent_seat_is_played_until_it_speaks() -> void:
	_save()
	Net.roster.append({"slot": 1, "peer": 99, "device": 0, "wizard": 1, "ai": false})
	Net.remote_inputs[1] = PackedFloat32Array([1, 0, 0, 0, 0, 0])
	Net._heard.erase(1)
	var t0 := 1000000
	Net.check_silence(t0, [])
	var limit := int(Tuning.shared().seat_silence * 1000.0)
	Net.check_silence(t0 + limit - 10, [])
	assert_false(Net.played_by_ai(Net.roster[1]))
	Net.check_silence(t0 + limit + 10, [])
	assert_true(Net.played_by_ai(Net.roster[1]), "silent for 5 s")
	assert_true(bool(Net.seat_builds()[1].ai))
	assert_false(Net.remote_inputs.has(1), "its stale input is dropped")
	assert_false(Net.played_by_ai(Net.roster[0]), "the keyboard always speaks")
	Net._note_heard(1)
	assert_false(Net.played_by_ai(Net.roster[1]), "back when it speaks")
	Net.remote_inputs.erase(1)
	_restore()


func test_join_refusals() -> void:
	assert_eq(Net.join_refusal(G.VERSION, World.P_FLOATS), "")
	assert_false(Net.join_refusal("0.0.1", World.P_FLOATS).is_empty(), "another version")
	assert_false(Net.join_refusal(G.VERSION, World.P_FLOATS - 1).is_empty(), "another snapshot layout")
	Net.in_game = true
	assert_false(Net.join_refusal(G.VERSION, World.P_FLOATS).is_empty(), "a run is on")
	Net.in_game = false


func test_input_packets_are_cleaned() -> void:
	assert_true(Net.clean_input(PackedFloat32Array([NAN, 0, 0, 0, 0, 0])).is_empty())
	assert_true(Net.clean_input(PackedFloat32Array([0, 0, INF, 0, 0, 0])).is_empty())
	assert_true(Net.clean_input(PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])).is_empty(), "7 numbers")
	var ok := Net.clean_input(PackedFloat32Array([3, 4, 0, 50, 1, 2, 0, 5]))
	assert_eq(ok.size(), 8)
	assert_near(ok[0], 0.6, 0.0001)
	assert_near(ok[1], 0.8, 0.0001)
	assert_near(ok[3], 1.0, 0.0001, "a mouse aim becomes a direction")
	assert_eq([ok[4], ok[5], ok[6], ok[7]], [1.0, 2.0, 0.0, 5.0])


func test_run_ending_events_leave_the_snapshot() -> void:
	var evs := [[World.EV_HIT, 0, 0, 0, 0], [World.EV_VICTORY, 0, 0, 0, 0], [World.EV_RESULTS, 0, 0, {}, 0],
		[World.EV_GAMEOVER, 0, 0, 0, 0], [World.EV_CARD, 0, 0, 0, 0], [World.EV_PICK, 0, 0, 0, 0]]
	var rest: Array = Net.send_events(evs)
	assert_eq(rest.size(), 1)
	assert_eq(int(rest[0][0]), World.EV_HIT)
	for code: int in [World.EV_VICTORY, World.EV_RESULTS, World.EV_GAMEOVER, World.EV_CARD, World.EV_CHEST, World.EV_PICK]:
		assert_true(Net.RELIABLE_EVENTS.has(code))

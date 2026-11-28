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


func _heroes_setup() -> Profile:
	var was: Profile = Save.profile
	var p := Profile.new()
	p.heroes.clear()
	p.add_hero(Hero.make(Races.index_of("elf"), Classes.KNIGHT, 0, "ONE"))
	p.add_hero(Hero.make(Races.HUMAN, Classes.PRIEST, 0, "TWO"))
	p.hero = 0
	Save.profile = p
	Net.force_heroes = true
	return was


func _heroes_teardown(was: Profile) -> void:
	Save.profile = was
	Net.force_heroes = false
	Net.seat_heroes.clear()


func test_a_seat_carries_a_cleaned_hero() -> void:
	_save()
	var was := _heroes_setup()
	Net.seat_heroes.clear()
	Net.start_offline()
	var row: Dictionary = Net.roster[0]
	var h: Hero = Save.profile.heroes[Save.profile.hero]
	assert_eq(row.hero, Hero.from_dict(h.to_dict()).to_dict())
	assert_eq(int(row.race), h.race)
	assert_eq(int(row.cls), h.cls)
	assert_eq(int(row.cls_level), h.level)
	Net.roster.append({"slot": 1, "peer": 99, "device": 0, "wizard": 1, "ai": false, "away": false, "race": 0, "cls": 0, "look": 0,
		"cls_level": 0, "hero": {}})
	Net._fill_hero(Net.roster[1], {"name": "x".repeat(50), "race": "nope", "cls": 7, "level": 999, "points": "junk", "look": -5})
	var junk: Dictionary = Net.roster[1].hero
	assert_true(String(junk.name).length() <= Hero.NAME_MAX)
	assert_eq(int(Net.roster[1].race), Races.HUMAN)
	assert_eq(int(Net.roster[1].cls), Classes.MAGE)
	assert_true(int(junk.level) <= Hero.MAX_LEVEL)
	assert_eq(Net.add_apprentice(), 2)
	assert_true((Net.roster[2].hero as Dictionary).is_empty(), "an apprentice has no hero")
	assert_eq(int(Net.roster[2].cls_level), 1, "an apprentice is a level 1 hero of the role it fills")
	assert_eq(int(Net.roster[2].race), Races.HUMAN)
	_heroes_teardown(was)
	_restore()


func test_two_local_seats_never_share_a_hero() -> void:
	_save()
	var was := _heroes_setup()
	Net.seat_heroes.clear()
	G.local_devices.assign([G.DEV_KBM, 0])
	Net.start_offline()
	assert_eq(Net.hero_of(G.DEV_KBM), 0, "seat 1 starts on the active hero")
	assert_eq(Net.hero_of(0), 1, "seat 2 the first free one")
	assert_false(Net.set_seat_hero(0, 0), "held by seat 1")
	Net.step_seat_hero(0, 1)
	assert_eq(Net.hero_of(0), 1, "nothing else to step to")
	assert_true(Net.set_seat_hero(G.DEV_KBM, -1))
	Net.step_seat_hero(0, 1)
	assert_eq(Net.hero_of(0), 0, "the freed hero")
	assert_true(Net.hero_of(0) != Net.hero_of(G.DEV_KBM))
	assert_eq(Net.played_heroes(), [0], "a guest is not played")
	_heroes_teardown(was)
	_restore()


func test_apprentices_fill_the_missing_roles_in_order() -> void:
	_save() # a solo seat with no hero: a mage
	assert_eq(Net.add_apprentice(), 1)
	assert_eq(Net.add_apprentice(), 2)
	assert_eq(Net.add_apprentice(), 3)
	var want: Array[int] = [Classes.KNIGHT, Classes.PRIEST, Classes.ARCHER]
	for i: int in range(3):
		var r: Dictionary = Net.roster[i + 1]
		assert_eq(int(r.cls), want[i], "seat %d" % (i + 1))
		assert_eq(int(r.race), Races.HUMAN)
		assert_eq(int(r.cls_level), 1)
		assert_eq(int(Net.seat_builds()[i + 1].cls), want[i], "the World is told")
	# A seat taken by a paladin already holds the tank: the next apprentice heals, then shoots, then hits.
	Net.remove_apprentice()
	Net.remove_apprentice()
	Net.remove_apprentice()
	Net.roster[0].cls = Classes.PALADIN
	assert_eq(Net.apprentice_class(), Classes.PRIEST)
	Net.add_apprentice()
	Net.add_apprentice()
	assert_eq(Net.apprentice_class(), Classes.MAGE)
	Net.roster[0].cls = Classes.MAGE
	_restore()


func test_apprentices_are_dealt_again_when_a_human_changes_class() -> void:
	_save() # a solo mage with a knight and a priest
	Net.add_apprentice()
	Net.add_apprentice()
	assert_eq(int(Net.roster[1].cls), Classes.KNIGHT)
	assert_eq(int(Net.roster[2].cls), Classes.PRIEST)
	# She picks a knight of her own: the apprentices heal and shoot, nobody doubles the tank.
	Net.roster[0].cls = Classes.KNIGHT
	Net._push_roster()
	assert_eq(int(Net.roster[1].cls), Classes.PRIEST)
	assert_eq(int(Net.roster[2].cls), Classes.ARCHER)
	assert_eq(int(Net.roster[1].cls_level), 1)
	# A run that is on keeps the classes it started with.
	Net.in_game = true
	Net.roster[0].cls = Classes.PRIEST
	Net._push_roster()
	assert_eq(int(Net.roster[1].cls), Classes.PRIEST, "an apprentice changed class in a run")
	Net.in_game = false
	Net.roster[0].cls = Classes.MAGE
	_restore()


func test_a_joining_human_drops_the_apprentices_class() -> void:
	_save()
	Net.add_apprentice()
	assert_eq(int(Net.roster[1].cls), Classes.KNIGHT)
	Net._add_to_roster(1, 0)
	assert_false(bool(Net.roster[1].ai))
	assert_eq(int(Net.roster[1].cls), Classes.MAGE, "no hero in a scripted run: a plain wizard")
	assert_eq(int(Net.roster[1].cls_level), 0)
	_restore()


func test_deleting_a_hero_keeps_every_seat_on_her_own_hero() -> void:
	_save()
	var was := _heroes_setup()
	Save.profile.add_hero(Hero.make(Races.HUMAN, Classes.MAGE, 0, "THREE"))
	Net.seat_heroes = {G.DEV_KBM: 2, 0: 1}
	assert_true(Save.profile.remove_hero(0))
	Net.hero_removed(0)
	assert_eq(Net.hero_at(Net.hero_of(G.DEV_KBM)).name, "THREE", "a seat above the deleted hero keeps her hero")
	assert_eq(Net.hero_at(Net.hero_of(0)).name, "TWO", "so does the other")
	Net.seat_heroes = {G.DEV_KBM: 0, 0: 1}
	assert_true(Save.profile.remove_hero(1))
	Net.hero_removed(1)
	assert_eq(Net.hero_at(Net.hero_of(G.DEV_KBM)).name, "TWO", "the seat below the deleted hero is untouched")
	assert_eq(Net.hero_of(0), -1, "the seat that held the deleted hero finds none free: a guest")
	_heroes_teardown(was)
	_restore()


func _four_seats() -> void:
	Net.seat_heroes.clear()
	G.local_devices.assign([G.DEV_KBM, 0, 1, 2])
	Net.start_offline()
	for d: int in [0, 1, 2]:
		Net.add_local_device(d)


func test_four_guest_seats_are_four_different_heroes() -> void:
	_save()
	var was := _heroes_setup()
	var p := Profile.new()
	Save.profile = p
	_four_seats()
	assert_eq(Net.roster.size(), 4)
	var seen := {}
	for r: Dictionary in Net.roster:
		seen["%d_%d" % [int(r.race), int(r.cls)]] = true
		assert_eq(int(r.cls_level), 1)
	assert_eq(seen.size(), 4, "four race and class pairs")
	assert_eq(Net.hero_of(G.DEV_KBM), 0, "seat 1 plays the profile's hero")
	assert_eq(int(Net.roster[1].cls), Classes.ARCHER)
	assert_eq(int(Net.roster[2].race), Races.DWARF)
	assert_eq(String(Net.roster[3].hero.name), Classes.class_name_of(Classes.PRIEST))
	assert_eq(Net.hero_of(2), -1)
	_heroes_teardown(was)
	_restore()


func test_a_seat_stepping_back_to_guest_gets_its_own_preset() -> void:
	_save()
	var was := _heroes_setup()
	Save.profile = Profile.new()
	_four_seats()
	Net.set_seat_hero(1, -1)
	assert_true(Net.set_seat_hero(0, -1))
	assert_eq(int(Net.roster[2].cls), Classes.KNIGHT)
	var row: Dictionary = Net.roster[2]
	assert_eq(row.hero, Net.guest_hero(2).to_dict())
	assert_eq(int(Net.roster[1].cls), Classes.ARCHER)
	Net.set_seat_hero(G.DEV_KBM, 0)
	assert_eq(int(Net.roster[0].cls), Classes.MAGE)
	Net.set_seat_hero(G.DEV_KBM, -1)
	assert_eq(Net.roster[0].hero, Net.guest_hero(0).to_dict(), "seat 1 back on guest is its preset again")
	_heroes_teardown(was)
	_restore()


func test_four_saved_heroes_seat_as_before() -> void:
	_save()
	var was := _heroes_setup()
	var p := Profile.new()
	p.heroes.clear()
	for c: int in [Classes.PRIEST, Classes.KNIGHT, Classes.ARCHER, Classes.MAGE]:
		p.add_hero(Hero.make(Races.ORC, c, 0, "H%d" % c))
	p.hero = 0
	Save.profile = p
	_four_seats()
	for i in 4:
		assert_eq(Net.hero_of(Net.roster[i].device), i)
		assert_eq(int(Net.roster[i].race), Races.ORC)
	assert_eq(int(Net.roster[3].cls), Classes.MAGE)
	_heroes_teardown(was)
	_restore()

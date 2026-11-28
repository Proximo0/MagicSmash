extends TestCase
## The shop's three run options (docs/content_list.md § 45, § 41): THE SECOND GLANCE (`redraw`) and THE BLACK RIBBON
## (`banish`) add redraws and banishes, THE HEAD START (`start_level`) starts the party levels up with those hands to
## draw before the first door opens (World.apply_meta, WorldLevels._shop_start and _intro_held, World.step's intro);
## the shelf that sells them (Profile.shelf, Profile.buy) and the coverage robot's family "shop".

const DT: float = 1.0 / 60.0
const SHOP_FAMILY := preload("res://tests/bot/cover/shop.gd")
const PLAYTEST_LIB := preload("res://tools/playtest_lib.gd")
## The intro of a run on main, in steps of DT (World.phase_t 2.5 s, counted down in floats: one step more than 150).
const INTRO_STEPS := 151


## A run of `n` wizards on its own Tuning (other tests change the shared one) with the table's options `meta`.
func _shop_run(n: int, meta: Dictionary, tune: Tuning = null, seats: Dictionary = {}) -> World:
	var w := World.new(range(n), 7, tune if tune != null else Tuning.new(), {}, seats)
	w.apply_meta(meta)
	return w


## Input that takes card `card` of wizard `p`'s hand.
func _take(p: World.Player, card: int = 0) -> PackedFloat32Array:
	return PackedFloat32Array([0, 0, 0, 0, 0, 0, card, p.offer])


## Steps until the intro ends (or `cap` steps); returns the steps taken.
func _steps_to_fight(w: World, cap: int = 5000) -> int:
	var n := 0
	while w.phase == World.PH_INTRO and n < cap:
		w.step(DT, {})
		n += 1
	return n


## The hands wizard `p` has still to draw: the one in hand and those queued (the snapshot's P_DRAWS).
func _hands(p: World.Player) -> int:
	return p.pending + (0 if p.choices.is_empty() else 1)


func test_bought_redraws_and_banishes_reach_every_wizard() -> void:
	var w := _shop_run(4, {"redraws": 2.0, "banishes": 1.0})
	w.step(DT, {})
	for p: World.Player in w.players.values():
		assert_eq(p.redraws, Upgrades.REDRAWS + 2, "redraws of wizard %d" % p.slot)
		assert_eq(p.banishes, Upgrades.BANISHES + 1, "banishes of wizard %d" % p.slot)
	assert_eq(Upgrades.REDRAWS + 2, 4)
	assert_eq(Upgrades.BANISHES + 1, 3)
	for _i: int in range(30):
		w.step(DT, {})
	for p: World.Player in w.players.values():
		assert_eq(p.redraws, 4, "handed out once")
		assert_eq(p.banishes, 3, "handed out once")
	for meta: Dictionary in [{}, {"hearts": 1.0, "novas": 1.0}]:
		var plain := _shop_run(4, meta)
		plain.step(DT, {})
		for p: World.Player in plain.players.values():
			assert_eq(p.redraws, Upgrades.REDRAWS)
			assert_eq(p.banishes, Upgrades.BANISHES)
			assert_eq(Upgrades.REDRAWS, 2)
			assert_eq(Upgrades.BANISHES, 2)


## The whole chain: the profile's levels, Profile.bonuses, apply_meta, apply_hero (a mage's own two redraws stack).
func test_the_profile_s_options_reach_the_run_with_a_hero() -> void:
	var prof := Profile.new()
	prof.crystals = 100000
	prof.seal_best = Seals.MAX
	for _k: int in range(2):
		assert_true(prof.buy(Profile.meta_index("redraw")))
	assert_true(prof.buy(Profile.meta_index("banish")))
	var b := prof.bonuses()
	assert_near(float(b["redraws"]), 2.0)
	assert_near(float(b["banishes"]), 1.0)
	assert_near(float(b["start_level"]), 0.0)
	var w := World.new([0, 1], 3, Tuning.new(), {0: 0, 1: 1})
	w.apply_meta(b)
	w.apply_hero(w.players[0], Hero.make(Races.HUMAN, Classes.MAGE, 0).to_dict())
	w.step(DT, {})
	assert_eq((w.players[0] as World.Player).redraws, Upgrades.REDRAWS + Classes.extra_redraws(Classes.MAGE) + 2)
	assert_eq((w.players[1] as World.Player).redraws, Upgrades.REDRAWS + 2)
	assert_eq((w.players[1] as World.Player).banishes, Upgrades.BANISHES + 1)
	assert_eq(w.party_level, 1, "no head start bought")


func test_the_head_start_levels_the_party_and_deals_its_hands() -> void:
	for n: int in [1, 2]:
		var w := _shop_run(4, {"start_level": float(n)})
		var ref := _shop_run(4, {})
		w.step(DT, {})
		ref.step(DT, {})
		assert_eq(w.party_level, 1 + n, "start_level %d" % n)
		assert_eq(w.party_xp, 0, "no XP is given")
		var scale := 1.0 + w.tune.xp_party_scale * 3.0
		assert_eq(w.xp_needed(), maxi(1, roundi(w.tune.xp_to_next(1) * scale)), "the next level costs what level 2 does")
		assert_eq(w.xp_needed(), ref.xp_needed(), "the same price as without a head start")
		assert_eq(w.head_start_levels, n)
		var snap: PackedFloat32Array = w.snapshot()["p"]
		for p: World.Player in w.players.values():
			var q: World.Player = ref.players[p.slot]
			assert_eq(p.level, 1 + n, "level of wizard %d" % p.slot)
			assert_false(p.choices.is_empty(), "a hand is offered on the first step")
			assert_eq(p.pending, n - 1)
			assert_eq(_hands(p), n, "hands to draw of wizard %d" % p.slot)
			assert_eq(p.max_hp, q.max_hp, "no stats")
			assert_eq(p.hp, q.hp)
			assert_eq(p.bombs, q.bombs)
			assert_eq(p.upgrades, q.upgrades, "no card is taken for her")
			assert_eq(p.redraws, Upgrades.REDRAWS)
			assert_eq(p.banishes, Upgrades.BANISHES)
		var at := 0
		var seen := 0
		while at + World.P_FLOATS <= snap.size():
			assert_eq(int(snap[at + World.P_DRAWS]), n, "the snapshot's draws")
			assert_eq(int(snap[at + World.P_LEVEL]), 1 + n, "the snapshot's level")
			at += World.P_FLOATS
			seen += 1
		assert_eq(seen, 4)
		assert_eq(w.phase, World.PH_INTRO)


## THE HEAD START's lead lasts: fed the same XP as a run without it, the party stays N levels up and every wizard
## has N more hands, however far the run goes (xp_needed does not price the head start's levels).
func test_the_head_start_s_lead_lasts() -> void:
	for n: int in [1, 2]:
		var w := _shop_run(2, {"start_level": float(n)})
		var ref := _shop_run(2, {})
		w.step(DT, {})
		ref.step(DT, {})
		var p: World.Player = w.players[0]
		var q: World.Player = ref.players[0]
		for k: int in range(100):
			var amount := 5 + 13 * k
			w.gain_xp(p, amount)
			ref.gain_xp(q, amount)
			assert_eq(w.party_level - ref.party_level, n, "levels ahead after gift %d of start_level %d" % [k, n])
			assert_eq(w.party_xp, ref.party_xp, "the same XP toward the next level")
			assert_eq(_hands(p) - _hands(q), n, "hands ahead after gift %d" % k)
		assert_true(ref.party_level >= 20, "the gifts reach the late levels (level %d)" % ref.party_level)
	var plain := _shop_run(2, {})
	plain.step(DT, {})
	assert_eq(plain.head_start_levels, 0, "no head start, no unpriced level")


## Each of four wizards draws her two hands; the party's level stays where the head start put it.
func test_four_wizards_draw_both_hands_of_the_head_start() -> void:
	var w := _shop_run(4, {"start_level": 2.0})
	w.step(DT, {})
	for _k: int in range(2):
		var inputs := {}
		for p: World.Player in w.players.values():
			inputs[p.slot] = _take(p)
		w.step(DT, inputs)
	for p: World.Player in w.players.values():
		assert_eq(_hands(p), 0, "wizard %d drew both" % p.slot)
		var took := 0
		for idx: int in p.upgrades:
			took += int(p.upgrades[idx])
		assert_eq(took, 3, "the starting spell and two cards")
		assert_eq(p.level, 3)
	assert_eq(w.party_level, 3)


func test_the_credit_is_once_for_the_table() -> void:
	var w := _shop_run(2, {"start_level": 1.0})
	assert_eq(w.record.used("shop_start_level"), 0, "not before the first step")
	w.step(DT, {})
	assert_eq(w.record.used("shop_start_level"), 1)
	for _i: int in range(200):
		w.step(DT, {})
	assert_eq(w.record.used("shop_start_level"), 1, "once a run")
	assert_true((w.record.to_dict()["uses_by"] as Dictionary).is_empty(), "no seat is credited")
	var plain := _shop_run(2, {"redraws": 1.0, "banishes": 1.0})
	plain.step(DT, {})
	assert_eq(plain.record.used("shop_start_level"), 0, "no head start, no credit")


## The intro holds past its 2.5 s while a hand is undrawn (no horde, no clock) and ends on the step that takes the
## last card: the fight's first tick is the step after it.
func test_the_intro_holds_until_the_last_hand_is_drawn() -> void:
	var w := _shop_run(2, {"start_level": 1.0})
	for _i: int in range(INTRO_STEPS * 2):
		w.step(DT, {})
	assert_eq(w.phase, World.PH_INTRO, "held past the intro's 2.5 s")
	assert_near(w.wave_time, 0.0)
	assert_true(w.enemies.is_empty() and w.spawn_queue.is_empty(), "no horde while held")
	var p0: World.Player = w.players[0]
	var p1: World.Player = w.players[1]
	w.step(DT, {0: _take(p0)})
	assert_eq(_hands(p0), 0)
	assert_eq(w.phase, World.PH_INTRO, "wizard 1 still holds the door")
	for _i: int in range(60):
		w.step(DT, {})
	assert_eq(w.phase, World.PH_INTRO)
	w.step(DT, {1: _take(p1)})
	assert_eq(_hands(p1), 0)
	assert_eq(w.phase, World.PH_FIGHT, "the step that takes the last card opens the door")
	assert_near(w.wave_time, 0.0)
	w.step(DT, {})
	assert_true(w.wave_time > 0.0, "the clock runs on the step after the last pick")


## Hands drawn before the intro's 2.5 s are up: the intro is as long as without a head start.
func test_a_quick_draw_keeps_the_intro_s_length() -> void:
	var w := _shop_run(2, {"start_level": 2.0})
	w.step(DT, {})
	for _k: int in range(2):
		w.step(DT, {0: _take(w.players[0]), 1: _take(w.players[1])})
	assert_eq(_steps_to_fight(w) + 3, INTRO_STEPS)


func test_the_door_opens_at_head_start_wait_and_she_keeps_her_draws() -> void:
	var tune := Tuning.new()
	assert_near(tune.head_start_wait, 12.0)
	for wait: float in [12.0, 5.0]:
		tune.set_value("head_start_wait", wait)
		var w := _shop_run(2, {"start_level": 2.0}, tune)
		w.step(DT, {})
		w.step(DT, {0: _take(w.players[0])})
		w.step(DT, {0: _take(w.players[0])})
		var before := w.time
		while w.phase == World.PH_INTRO and w.time < 60.0:
			before = w.time
			w.step(DT, {})
		assert_eq(w.phase, World.PH_FIGHT, "the door opened (wait %.0f)" % wait)
		assert_true(before < wait, "it held until %.0f s (opened after %.3f s)" % [wait, before])
		assert_true(w.time >= wait and w.time < wait + DT * 1.5, "it opened at %.0f s, not %.3f s" % [wait, w.time])
		var p1: World.Player = w.players[1]
		assert_eq(_hands(p1), 2, "an undrawn wizard keeps her draws")
		w.step(DT, {1: _take(p1)})
		assert_eq(_hands(p1), 1, "she draws in the fight as after any level-up")
		w.step(DT, {1: _take(p1)})
		assert_eq(_hands(p1), 0)


func test_a_fallen_away_or_gone_wizard_does_not_hold_the_door() -> void:
	# Fallen: wizard 1 is down with her hand; wizard 0 draws at once; the door opens at the intro's 2.5 s.
	var w := _shop_run(2, {"start_level": 1.0})
	w.step(DT, {})
	var p1: World.Player = w.players[1]
	p1.invuln = 0.0
	w.hurt_player(p1, 99)
	assert_false(p1.alive)
	w.step(DT, {0: _take(w.players[0])})
	assert_eq(_steps_to_fight(w) + 2, INTRO_STEPS, "a fallen wizard held the door")
	assert_eq(_hands(p1), 1, "she keeps her draws")
	# Away: a human whose machine went quiet (played as an apprentice that keeps her draws).
	var away := _shop_run(2, {"start_level": 1.0}, null, {1: {"ai": true, "away": true}})
	away.step(DT, {})
	away.step(DT, {0: _take(away.players[0])})
	assert_eq(_steps_to_fight(away) + 2, INTRO_STEPS, "an away wizard held the door")
	assert_eq(_hands(away.players[1]), 1)
	# Gone: her machine left the game.
	var gone := _shop_run(2, {"start_level": 1.0})
	gone.step(DT, {})
	gone.remove_player(1)
	gone.step(DT, {0: _take(gone.players[0])})
	assert_eq(_steps_to_fight(gone) + 2, INTRO_STEPS)
	# An apprentice draws by herself, a hand a step, and holds nothing up.
	var apprentice := _shop_run(2, {"start_level": 2.0}, null, {1: {"ai": true}})
	apprentice.step(DT, {})
	apprentice.step(DT, {0: _take(apprentice.players[0])})
	apprentice.step(DT, {0: _take(apprentice.players[0])})
	assert_eq(_hands(apprentice.players[1]), 0, "the apprentice drew both")
	assert_eq(_steps_to_fight(apprentice) + 3, INTRO_STEPS)


## WorldLevels._intro_held on its own: a card in hand or a draw queued holds; nothing to draw, a fallen or away
## wizard, no head start, or the wait gone by does not.
func test_what_holds_the_intro() -> void:
	var w := _shop_run(2, {"start_level": 1.0}, null, {1: {"ai": true, "away": true}})
	var p0: World.Player = w.players[0]
	var p1: World.Player = w.players[1]
	assert_false(WorldLevels._intro_held(w), "nothing to draw yet")
	p0.pending = 1
	assert_true(WorldLevels._intro_held(w), "a draw queued")
	p0.pending = 0
	p0.choices = [Upgrades.POWER]
	assert_true(WorldLevels._intro_held(w), "a card in hand")
	p0.alive = false
	assert_false(WorldLevels._intro_held(w), "she has fallen")
	p0.alive = true
	p0.choices = []
	p1.pending = 1
	assert_false(WorldLevels._intro_held(w), "an away wizard")
	p0.pending = 1
	w.time = w.tune.head_start_wait - DT
	assert_true(WorldLevels._intro_held(w))
	w.time = w.tune.head_start_wait
	assert_false(WorldLevels._intro_held(w), "the wait is up")
	w.time = 0.0
	w.meta_start_level = 0
	assert_false(WorldLevels._intro_held(w), "no head start")


## With no head start the intro is as long as on main to the step, even with a hand undrawn in it.
func test_without_a_head_start_the_intro_does_not_change() -> void:
	var expect := 0
	var left := World.new([0], 1, Tuning.new()).phase_t
	while left > 0.0:
		left -= DT
		expect += 1
	assert_eq(expect, INTRO_STEPS)
	var bare := World.new([0, 1], 7, Tuning.new())
	assert_eq(_steps_to_fight(bare), INTRO_STEPS, "no apply_meta")
	for meta: Dictionary in [{}, {"redraws": 2.0, "banishes": 2.0, "hearts": 1.0}, {"start_level": 0.0}]:
		var w := _shop_run(2, meta)
		w.step(DT, {})
		(w.players[0] as World.Player).pending = 2 # a hand undrawn holds nothing without a head start
		assert_eq(_steps_to_fight(w) + 1, INTRO_STEPS, "meta %s" % [meta])
		assert_eq(w.party_level, 1)
		assert_eq((w.players[1] as World.Player).level, 1)


func test_the_shelf_sells_the_three_options() -> void:
	var keys: Array = []
	for i: int in Profile.shelf():
		keys.append(Profile.META[i][0])
	assert_eq(keys, ["vigor", "might", "wisdom", "fortune", "novas", "luck", "redraw", "banish", "start_level"])
	var in_order: Array = []
	for row: Array in Profile.META.slice(0, 9):
		in_order.append(row[0])
	assert_eq(keys, in_order, "META's order")
	for key: String in ["redraw", "banish", "start_level"]:
		assert_false(Profile.UNBUILT.has(key), key + " is still on the shelf of unbuilt rows")
		var i := Profile.meta_index(key)
		var costs: Array = Profile.META[i][3]
		var p := Profile.new()
		p.crystals = 100000
		assert_eq(p.closed_why(i), "", key + " can be bought on a new profile")
		assert_true(p.buy(i), key + " level 1")
		assert_eq(p.level(key), 1)
		assert_eq(p.crystals, 100000 - int(costs[0]))
		var step: int = int((Profile.GATES[key] as Dictionary)[2])
		p.seal_best = step - 1
		assert_eq(p.closed_why(i), Profile.gate_why(key, 2))
		assert_false(p.buy(i), key + " level 2 before its Seal win")
		assert_eq(p.level(key), 1)
		p.seal_best = step
		assert_true(p.buy(i), key + " level 2 after its Seal win")
		assert_eq(p.level(key), 2)
		assert_eq(p.crystals, 100000 - int(costs[0]) - int(costs[1]))
		assert_eq(p.closed_why(i), Profile.WHY_MAX)
		assert_false(p.buy(i))
	assert_eq(Profile.GATES["redraw"], {2: 6})
	assert_eq(Profile.GATES["banish"], {2: 3})
	assert_eq(Profile.GATES["start_level"], {2: 8})
	for key: String in ["satchel", "favour", "respec", "deck_hex", "deck_blades", "deck_priestess"]:
		assert_true(Profile.UNBUILT.has(key), key + " stays on its shelf")


## A head start bought on the profile reaches the run through bonuses() (level 2 after the SEAL VII win).
func test_the_bought_head_start_reaches_the_run() -> void:
	var prof := Profile.new()
	prof.crystals = 100000
	prof.seal_best = int((Profile.GATES["start_level"] as Dictionary)[2])
	var i := Profile.meta_index("start_level")
	assert_true(prof.buy(i))
	assert_true(prof.buy(i))
	var w := World.new([0, 1, 2], 3, Tuning.new())
	w.apply_meta(prof.bonuses())
	w.step(DT, {})
	assert_eq(w.party_level, 3)
	for p: World.Player in w.players.values():
		assert_eq(_hands(p), 2)


## The coverage robot's family "shop": the rows whose Test letters hold a B, dealt by apply_meta before the first
## step and credited by "shop_" + key.
func test_the_robot_s_shop_family() -> void:
	var fam: RefCounted = SHOP_FAMILY.new()
	assert_eq(fam.call("family"), "shop")
	assert_eq(fam.call("keys"), ["start_level", "favour"] as Array[String])
	assert_false(bool(fam.call("unbuilt", "start_level")))
	assert_true(bool(fam.call("unbuilt", "favour")))
	var w := World.new([0, 1], 9, Tuning.new())
	var p: World.Player = w.players[0]
	assert_false(bool(fam.call("too_late", w)), "a fresh run takes the deal")
	fam.call("deal", w, p, "start_level")
	assert_eq(int(fam.call("credit", w, p, "start_level")), 0)
	w.step(DT, {})
	assert_eq(int(fam.call("credit", w, p, "start_level")), 1)
	assert_eq(w.party_level, 2, "dealt at level 1")
	assert_true(bool(fam.call("too_late", w)), "after the first step a deal would never take: deal() fails the row")


## The playtest tool's --meta (tools/playtest_lib.gd): its values reach every run's apply_meta, a second --meta adds
## to the first and the PLAYTEST line names both, and a key apply_meta does not read is refused.
func test_the_playtest_s_meta_reaches_its_runs() -> void:
	var meta := {}
	assert_eq(PLAYTEST_LIB.meta_from_arg("start_level:2", meta), "")
	assert_eq(PLAYTEST_LIB.meta_from_arg("redraws:1", meta), "", "a second --meta")
	assert_eq(meta, {"start_level": 2.0, "redraws": 1.0})
	var lib: RefCounted = PLAYTEST_LIB.new()
	var line_of_main: String = String(lib.call("_playtest_line", 1, PackedStringArray(["casual x2 win 0/6"])))
	assert_false(line_of_main.contains("meta"), "without --meta the PLAYTEST line names none: " + line_of_main)
	assert_true(bool(lib.call("_parse_args", PackedStringArray(["--meta=start_level:2", "--meta=redraws:1"]))))
	assert_eq(lib.get("_meta"), meta, "the tool's two --meta reach _meta")
	assert_eq(String(lib.call("_meta_text")), "start_level:2,redraws:1", "_meta_text names both")
	assert_eq(String(lib.call("_playtest_line", 1, PackedStringArray(["casual x2 win 0/6"]))),
		line_of_main.replace(" | ", " meta=start_level:2,redraws:1 | "),
		"the PLAYTEST line names both, between the Seal's title and the first group")
	lib.set("_minutes", 0.02) # about a second of fight after the intro
	lib.call("_play", SmashBot.CASUAL, 2, 7)
	var w: World = lib.get("_last_world")
	assert_eq(w.meta_start_level, 2, "--meta's start_level reached apply_meta")
	assert_eq(w.meta_redraws, 1, "--meta's redraws reached apply_meta")
	assert_true(w.party_level >= 3, "the party started two levels up")
	for p: World.Player in w.players.values():
		assert_eq(p.redraws, Upgrades.REDRAWS + 1, "wizard %d's redraws" % p.slot)
	var again := {"start_level": 2.0}
	assert_eq(PLAYTEST_LIB.meta_from_arg("start_level:1,banishes:1", again), "")
	assert_eq(again, {"start_level": 1.0, "banishes": 1.0}, "a key given again takes its last value")
	assert_true(PLAYTEST_LIB.meta_from_arg("start_levl:2", {}).begins_with("unknown --meta key start_levl"))
	for bad: String in ["favour:1", "locked:1", "urn_card:1", "start_level", "start_level:two", "redraws:1:2"]:
		var into := {}
		assert_true(PLAYTEST_LIB.meta_from_arg(bad, into) != "", bad + " is refused")
		assert_true(into.is_empty(), bad + " adds nothing")

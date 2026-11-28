extends TestCase
## The urn secret (Secrets "urn_card"): World counts the urns a run breaks (urns_broken, run_so_far's "urns"),
## Profile adds them up over every run, and from Profile.URN_CARD_AFTER urns on bonuses() gives each run the urn card
## until the secret is found.


## A tune with no natural card run, so only the profile's urn card can make one.
func _urn_tune() -> Tuning:
	var t := Tuning.new()
	t.card_run_chance = 0.0
	return t


func _profile_with(urns: int) -> Profile:
	var p := Profile.new()
	p.urns = urns
	return p


## Breaks one urn at the card's moment and picks up every card it drops; returns the EV_CARD events.
func _break_at_the_moment(w: World) -> Array:
	w.wave_time = WorldDrops._loot_moment(w, float(w.run_loot.card_at))
	w._break_urn(Vector2(120, 120))
	var p := w.players[0] as World.Player
	for k: World.Pickup in w.pickups.duplicate():
		if k.kind == World.PK_CARD:
			WorldDrops._collect(w, p, k)
			w.pickups.erase(k)
	var cards: Array = []
	for ev: Array in w.take_events():
		if ev[0] == World.EV_CARD:
			cards.append(ev)
	return cards


func test_the_urn_card_comes_from_urn_card_after_urns_until_the_secret_is_found() -> void:
	assert_eq(Profile.URN_CARD_AFTER, 120)
	assert_false(bool(_profile_with(Profile.URN_CARD_AFTER - 1).bonuses().get("urn_card", true)), "one urn short")
	assert_true(bool(_profile_with(Profile.URN_CARD_AFTER).bonuses().get("urn_card", false)), "enough urns")
	var found := _profile_with(Profile.URN_CARD_AFTER)
	assert_true(found.find_secret("urn_card"))
	assert_false(bool(found.bonuses().get("urn_card", true)), "the secret is found: no more urn card")
	assert_false(bool(Profile.new().bonuses().get("urn_card", true)), "a new profile")


## The whole chain: bonuses() through apply_meta makes the run's card wait in the first urn at its moment, and
## picking it up sends the EV_CARD the arena reads as the secret (ev[4] >= 8).
func test_a_profile_with_enough_urns_finds_its_card_in_an_urn() -> void:
	var w := World.new([0], 3, _urn_tune())
	w.apply_meta(_profile_with(Profile.URN_CARD_AFTER).bonuses())
	assert_true(w.urn_card, "apply_meta took no urn card")
	w._break_urn(Vector2(120, 120))
	var early := 0
	for k: World.Pickup in w.pickups:
		early += 1 if k.kind == World.PK_CARD else 0
	assert_eq(early, 0, "the card came before its moment")
	var cards := _break_at_the_moment(w)
	assert_eq(cards.size(), 1, "no card from the first urn at its moment")
	if cards.size() == 1:
		assert_true(int(cards[0][4]) >= 8, "the card was not marked as an urn's")
		assert_eq(int(cards[0][3]), WorldDrops.run_card(w))
	assert_eq(_break_at_the_moment(w).size(), 0, "a second card")
	var short := World.new([0], 3, _urn_tune())
	short.apply_meta(_profile_with(Profile.URN_CARD_AFTER - 1).bonuses())
	assert_eq(_break_at_the_moment(short).size(), 0, "one urn short and still a card")


func test_urns_broken_counts_a_walk_in_and_a_shot_once_each() -> void:
	var w := World.new([0], 3)
	var p := w.players[0] as World.Player
	assert_eq(w.urns_broken, 0)
	w.urns = [Vector2(100, 100)] as Array[Vector2]
	p.pos = Vector2(102, 100)
	w._update_urns()
	assert_eq(w.urns_broken, 1, "a wizard walking in")
	w._update_urns()
	assert_eq(w.urns_broken, 1, "counted again with no urn")
	p.pos = Vector2(300, 200)
	w.urns = [Vector2(150, 100)] as Array[Vector2]
	for i: int in range(2): # two shots on one urn break it once
		var s := World.Shot.new()
		s.pos = Vector2(150, 97)
		w.shots.append(s)
	w._update_urns()
	assert_eq(w.urns_broken, 2, "a shot")
	w.urns = [Vector2(200, 100)] as Array[Vector2]
	p.pos = Vector2(202, 100)
	var both := World.Shot.new()
	both.pos = Vector2(200, 97)
	w.shots = [both]
	w._update_urns()
	assert_eq(w.urns_broken, 3, "a wizard and a shot on one urn")
	assert_eq(int(w.run_so_far().get("urns", -1)), 3)


func test_urns_broken_stays_out_of_the_snapshot_and_the_hash() -> void:
	var a := World.new([0], 3)
	var b := World.new([0], 3)
	b.urns_broken = 7
	assert_eq(a.state_hash(), b.state_hash())
	assert_false(b.snapshot().has("urns"), "the snapshot grew an urn count")
	assert_eq(a.snapshot().keys(), b.snapshot().keys())


## A run booked with World.run_so_far adds its urns to the profile; past URN_CARD_AFTER the next run has the card.
func test_booked_runs_add_up_to_the_urn_card() -> void:
	var p := _profile_with(Profile.URN_CARD_AFTER - 2)
	var w := World.new([0], 3)
	w.urns_broken = 2
	var run := w.run_so_far()
	run["results"] = Results.from_dict(run.results)
	p.finish_run(run)
	assert_eq(p.urns, Profile.URN_CARD_AFTER)
	assert_true(bool(p.bonuses().urn_card))
	var next := World.new([0], 3, _urn_tune())
	next.apply_meta(p.bonuses())
	assert_true(next.urn_card)

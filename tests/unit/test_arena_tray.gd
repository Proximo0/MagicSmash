extends TestCase
## The level-up tray's card buttons (game/arena/tray.gd): what a press, a hold and a release send.


func _arena(choices: Array[int], banishes: int, offer: int) -> Arena:
	var a := Arena.new()
	a.time = 10.0
	a.vp[0] = {"choices": choices, "choice_lv": [1, 1, 1], "banishes": banishes, "redraws": 2, "offer": offer,
		"draws": 1, "alive": true}
	a._tray_dealt[0] = [offer, -10.0, 7, false] # face up long ago
	a._tray_open[0] = true
	return a


## Frees the arena and the nodes it made but never put in a tree (it never entered one here).
func _free(a: Arena) -> void:
	for prop: Dictionary in a.get_property_list():
		var v: Variant = a.get(prop["name"])
		if v is Node and is_instance_valid(v) and v != a and (v as Node).get_parent() == null:
			(v as Node).free()
	a.free()


## A Minor Arcana card cannot be banished, so its button takes it at once instead of starting a hold.
func test_a_minor_arcana_card_is_taken_at_once() -> void:
	var a := _arena([Upgrades.M_CUPS, Upgrades.POWER] as Array[int], 2, 5)
	ArenaTray._press_card(a, 0, 0)
	assert_eq(a._pick_sent.get(0, []), [0, 5], "a Minor Arcana press did not take the card")
	assert_eq(ArenaTray._hold_left(a, 0, 0), 0.0, "a Minor Arcana card started a banish hold")
	ArenaTray._press_card(a, 0, 1)
	_free(a)


## A hold started on one arena never banishes on the next one (holds survive in a static).
func test_a_hold_does_not_outlive_its_arena() -> void:
	var a := _arena([Upgrades.POWER, Upgrades.QUICK] as Array[int], 2, 5)
	ArenaTray._press_card(a, 0, 0)
	assert_true(ArenaTray._hold_left(a, 0, 0) >= 0.0)
	_free(a)
	var b := _arena([Upgrades.POWER, Upgrades.QUICK] as Array[int], 2, 5)
	b.time = 30.0
	ArenaTray._update_hold(b, 0)
	assert_false(b._pick_sent.has(0), "a hold from the last arena banished a card on this one")
	assert_eq(ArenaTray._hold_left(b, 0, 0), 0.0)
	_free(b)


## A card held for BANISH_HOLD seconds sends a banish for that card, once.
func test_a_held_card_sends_its_banish() -> void:
	var a := _arena([Upgrades.POWER, Upgrades.QUICK] as Array[int], 2, 5)
	ArenaTray._press_card(a, 0, 1)
	assert_false(a._pick_sent.has(0), "a press with banishes left took the card at once")
	a.time += ArenaTray.BANISH_HOLD + 0.01
	ArenaTray._update_hold(a, 0)
	assert_eq(a._pick_sent.get(0, []), [Upgrades.BANISH_INPUT + 1, 5])
	_free(a)

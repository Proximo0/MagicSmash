extends TestCase
## CreditsView: the scroll and the keys of the title's CREDITS board (game/ui/credits_view.gd).


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	return e


func _open() -> CreditsView:
	var v := CreditsView.new()
	v.open()
	return v


func test_it_opens_below_its_first_line_and_scrolls_by_itself() -> void:
	var v := _open()
	assert_eq(v.scroll_pos(), -CreditsView.LEAD_IN, "the title rises into view")
	assert_true(v.is_auto())
	assert_true(v.max_scroll() > CreditsView.VIEW_BOTTOM - CreditsView.VIEW_TOP, "the roll is longer than the screen")


func test_up_and_down_scroll_by_hand_and_stop_the_automatic_scroll() -> void:
	var v := _open()
	assert_false(v.handle(_key(KEY_DOWN)), "a scroll key does not close the board")
	assert_false(v.is_auto())
	assert_eq(v.scroll_pos(), -CreditsView.LEAD_IN + CreditsView.HAND_STEP)
	assert_false(v.handle(_key(KEY_UP)))
	assert_false(v.handle(_key(KEY_UP)))
	assert_eq(v.scroll_pos(), -CreditsView.LEAD_IN, "it does not scroll above its start")


func test_the_wheel_scrolls_too() -> void:
	var v := _open()
	assert_false(v.handle(_mouse(MOUSE_BUTTON_WHEEL_DOWN)))
	assert_eq(v.scroll_pos(), -CreditsView.LEAD_IN + CreditsView.HAND_STEP)
	assert_false(v.handle(_mouse(MOUSE_BUTTON_WHEEL_UP)))
	assert_eq(v.scroll_pos(), -CreditsView.LEAD_IN)
	assert_false(v.is_auto())


func test_the_roll_stops_at_its_end() -> void:
	var v := _open()
	v.scroll_to(1.0e9)
	assert_eq(v.scroll_pos(), v.max_scroll())
	assert_false(v.handle(_key(KEY_DOWN)))
	assert_eq(v.scroll_pos(), v.max_scroll(), "down at the end stays at the end")
	v.scroll_to(-1.0e9)
	assert_eq(v.scroll_pos(), -CreditsView.LEAD_IN)


func test_back_and_a_click_leave() -> void:
	assert_true(_open().handle(_key(KEY_ESCAPE)))
	assert_true(_open().handle(_mouse(MOUSE_BUTTON_LEFT)))
	assert_false(_open().handle(_key(KEY_ENTER)), "any other key leaves the board open")


func test_opening_again_starts_the_roll_again() -> void:
	var v := _open()
	v.scroll_to(300.0)
	v.open()
	assert_eq(v.scroll_pos(), -CreditsView.LEAD_IN)
	assert_true(v.is_auto())

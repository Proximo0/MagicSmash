extends TestCase
## Input and pause fixes: a menu press is no Nova, the results screen ignores a held key, a solo run pauses when
## control is lost, a LAN host alone can pause, the card secret reaches clients, one touch keeps mouse aiming.

const DT: float = 1.0 / 60.0


func _key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = pressed
	e.echo = echo
	return e


## N2: while muted a press adds nothing, and a button still down when the mute ends adds nothing either.
func test_muted_press_is_no_nova() -> void:
	PlayerInput.bomb_counts.erase(77)
	PlayerInput._bomb_held.erase(77)
	PlayerInput.bomb_muted = true
	PlayerInput._count_bomb(77, true)
	PlayerInput.bomb_muted = false
	PlayerInput._count_bomb(77, true) # still held after the menu closed
	assert_eq(int(PlayerInput.bomb_counts.get(77, 0)), 0)
	PlayerInput._count_bomb(77, false)
	PlayerInput._count_bomb(77, true) # a fresh press counts
	assert_eq(int(PlayerInput.bomb_counts.get(77, 0)), 1)
	PlayerInput.bomb_counts.erase(77)
	PlayerInput._bomb_held.erase(77)


func test_swallowed_button_casts_nothing_until_released() -> void:
	PlayerInput.bomb_counts.erase(78)
	PlayerInput.swallow_bomb(78)
	PlayerInput._count_bomb(78, true)
	assert_eq(int(PlayerInput.bomb_counts.get(78, 0)), 0)
	PlayerInput._count_bomb(78, false)
	PlayerInput._count_bomb(78, true)
	assert_eq(int(PlayerInput.bomb_counts.get(78, 0)), 1)
	PlayerInput.bomb_counts.erase(78)
	PlayerInput._bomb_held.erase(78)


## N2, world side: one input that picks a card and bumps the Nova counter spends no Nova.
func test_pick_and_bump_in_one_input_spends_no_nova() -> void:
	var w := World.new([0], 3, Tuning.new())
	w.phase_t = 1e6
	var p: World.Player = w.players[0]
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 0])})
	p.pending = 1
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 0])})
	assert_false(p.choices.is_empty())
	var bombs := p.bombs
	var pick := PackedFloat32Array([0, 0, 0, 0, 0, 1, 0, float(p.offer)])
	w.step(DT, {0: pick})
	assert_true(p.choices.is_empty(), "the card was taken")
	assert_eq(p.bombs, bombs + (1 if p.upgrades.has(Upgrades.NOVA) else 0), "no Nova spent")


## N5: a held arrow key repeats as echo and must not leave the results screen.
func test_held_arrow_does_not_dismiss_results() -> void:
	assert_false(PlayerInput.results_dismiss(_key(KEY_LEFT, true, true)))
	assert_true(PlayerInput.results_dismiss(_key(KEY_LEFT)))
	assert_true(PlayerInput.results_dismiss(_key(KEY_SPACE)))
	assert_false(PlayerInput.results_dismiss(_key(KEY_Q)))


## N6: Shift (Steam's overlay key) is not a Nova key.
func test_shift_is_not_a_nova_key() -> void:
	var src := FileAccess.get_file_as_string("res://game/input/player_input.gd")
	assert_false(src.contains("KEY_SHIFT"))


## N6: control lost pauses a solo run through the pause menu; not online, not after the end, not twice.
func test_losing_control_pauses_a_solo_run() -> void:
	var was: Net.Mode = Net.mode
	Net.mode = Net.Mode.OFFLINE
	var a := Arena.new()
	a._auto_pause()
	assert_true(a.paused)
	a._auto_pause()
	assert_true(a.paused, "a second loss does not resume")
	var b := Arena.new()
	b.game_over = true
	b._auto_pause()
	assert_false(b.paused)
	Net.mode = Net.Mode.HOST
	var c := Arena.new()
	c._auto_pause()
	assert_false(c.paused)
	Net.mode = was
	a.free()
	b.free()
	c.free()


func test_overlay_signal_exists_and_pauses() -> void:
	assert_true(Platform.has_signal("overlay_toggled"))
	var was: Net.Mode = Net.mode
	Net.mode = Net.Mode.OFFLINE
	var a := Arena.new()
	a._on_overlay(false)
	assert_false(a.paused)
	a._on_overlay(true)
	assert_true(a.paused)
	Net.mode = was
	a.free()


## N9: a host with only its own seats is frozen by the pause; with a remote seat the world keeps running.
func test_lan_host_alone_can_pause() -> void:
	var was_mode: Net.Mode = Net.mode
	var was_roster: Array = Net.roster
	Net.mode = Net.Mode.HOST
	Net.roster = [{"slot": 0, "peer": Net.my_peer, "device": -1}]
	var a := Arena.new()
	a.paused = true
	assert_false(Net.has_remote_players())
	assert_true(a._frozen())
	Net.roster = [{"slot": 0, "peer": Net.my_peer, "device": -1}, {"slot": 1, "peer": 99, "device": -1}]
	assert_true(Net.has_remote_players())
	assert_false(a._frozen())
	Net.mode = was_mode
	Net.roster = was_roster
	a.free()


## N8 / L6: the arena reads the urn flag without rewriting the event the clients get.
func test_card_event_keeps_its_urn_flag() -> void:
	var a := Arena.new()
	a.fx = Fx.new()
	var ev: Array = [World.EV_CARD, 10.0, 10.0, 3, 9]
	ArenaEvents._handle_events(a, [ev])
	assert_eq(int(ev[4]), 9)
	assert_eq(int(a._cards[0].slot), 1)
	a.fx.free()
	a.free()


## S3: a key after a touch hands aiming back to the mouse on a PC.
func test_key_after_touch_ends_touch_mode() -> void:
	var g: Node = load("res://game/autoload/g.gd").new()
	g.is_mobile = false
	var t := InputEventScreenTouch.new()
	t.pressed = true
	g._input(t)
	assert_true(g.touch_active)
	g._input(_key(KEY_W))
	assert_false(g.touch_active)
	g.is_mobile = true
	g.touch_active = true
	g._input(_key(KEY_W))
	assert_true(g.touch_active, "a phone stays in touch mode")
	g.free()

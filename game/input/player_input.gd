class_name PlayerInput
## Reads one device into a compact input packet:
## [move_x, move_y, aim_x, aim_y, fire(0/1), bomb_count]
## Keyboard: WASD move, arrow keys fire in 8 directions (Smash TV style),
## or mouse to aim + left click to fire. Space / right click = Nova.
## Gamepad: left stick move, right stick aim + fire, RB, RT or A = Nova. LB and LT are not read here: they open
## the level-up card tray (Arena).

static var bomb_counts := {}
static var _bomb_held := {}
static var touch: TouchControls = null
## When true, gameplay input comes from Arena's demo bot (autotest).
static var bot := false
static var bot_passive := false

static func read(device: int, player_screen_pos: Vector2, viewport: Viewport) -> PackedFloat32Array:
	var move := Vector2.ZERO
	var aim := Vector2.ZERO
	var fire := false
	var bomb := false
	if device == G.DEV_KBM:
		if Input.is_physical_key_pressed(KEY_A): move.x -= 1
		if Input.is_physical_key_pressed(KEY_D): move.x += 1
		if Input.is_physical_key_pressed(KEY_W): move.y -= 1
		if Input.is_physical_key_pressed(KEY_S): move.y += 1
		if Input.is_physical_key_pressed(KEY_LEFT): aim.x -= 1
		if Input.is_physical_key_pressed(KEY_RIGHT): aim.x += 1
		if Input.is_physical_key_pressed(KEY_UP): aim.y -= 1
		if Input.is_physical_key_pressed(KEY_DOWN): aim.y += 1
		if aim != Vector2.ZERO:
			fire = true
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not G.touch_active:
			aim = viewport.get_mouse_position() - player_screen_pos
			fire = true
		bomb = Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SHIFT) \
			or (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not G.touch_active)
		if touch and G.touch_active:
			if touch.move_vec.length() > 0.15:
				move = touch.move_vec
			if touch.aim_vec.length() > 0.2:
				aim = touch.aim_vec
				fire = true
			bomb = bomb or touch.bomb_down
	else:
		move = Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
		if move.length() < 0.25:
			move = Vector2.ZERO
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT): move.x = -1
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT): move.x = 1
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP): move.y = -1
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN): move.y = 1
		aim = Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
		if aim.length() > 0.35:
			fire = true
		else:
			aim = Vector2.ZERO
			# Face-button fire for pads without a comfortable right stick.
			if Input.is_joy_button_pressed(device, JOY_BUTTON_X):
				fire = true
		bomb = Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER) \
			or Input.is_joy_button_pressed(device, JOY_BUTTON_A) \
			or Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	if move.length() > 1.0:
		move = move.normalized()
	# Bombs are sent as a press counter so a dropped packet never loses one.
	var held: bool = _bomb_held.get(device, false)
	if bomb and not held:
		bomb_counts[device] = int(bomb_counts.get(device, 0)) + 1
	_bomb_held[device] = bomb
	return PackedFloat32Array([move.x, move.y, aim.x, aim.y, 1.0 if fire else 0.0, float(bomb_counts.get(device, 0))])

## Menu helpers ------------------------------------------------------------
## Returns a device id that just pressed "confirm", or -99.
static func confirm_device(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z]:
			return G.DEV_KBM
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START]:
			return event.device
	return -99

static func back_pressed(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		return event.physical_keycode in [KEY_ESCAPE, KEY_BACKSPACE]
	if event is InputEventJoypadButton and event.pressed:
		return event.button_index == JOY_BUTTON_B
	return false

## [device, -1 left or +1 right] for a sideways menu press, or [-99, 0]. The lobby uses it so each player
## steps through the wizards with their own keyboard or pad.
static func menu_side(event: InputEvent) -> Array:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_LEFT, KEY_A: return [G.DEV_KBM, -1]
			KEY_RIGHT, KEY_D: return [G.DEV_KBM, 1]
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_DPAD_LEFT: return [event.device, -1]
		if event.button_index == JOY_BUTTON_DPAD_RIGHT: return [event.device, 1]
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X:
		var key := "stickx%d" % event.device
		var was: float = _bomb_held.get(key, 0.0)
		_bomb_held[key] = event.axis_value
		if event.axis_value < -0.6 and was >= -0.6: return [event.device, -1]
		if event.axis_value > 0.6 and was <= 0.6: return [event.device, 1]
	return [-99, 0]

## -1 up, +1 down, 0 none.
static func menu_dir(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_UP, KEY_W: return -1
			KEY_DOWN, KEY_S: return 1
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_DPAD_UP: return -1
		if event.button_index == JOY_BUTTON_DPAD_DOWN: return 1
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y:
		# Edge-triggered stick navigation.
		var key := "stick%d" % event.device
		var was: float = _bomb_held.get(key, 0.0)
		_bomb_held[key] = event.axis_value
		if event.axis_value < -0.6 and was >= -0.6: return -1
		if event.axis_value > 0.6 and was <= 0.6: return 1
	return 0

extends SceneTree
## PLAYBOT: a player-like bot that plays the real client the way a person does (docs/realm/ops.md "Player-like bots").
## It builds the shell as main.gd does and plays it ONLY through Input.parse_input_event: key presses and releases
## (keycode and physical keycode, the keys ShellSettings binds) and the mouse moved and clicked at window coordinates
## over the buttons the screens draw. It reads state (the screens, the town, the field client's hero and monsters) to
## decide, as a player reads the screen. Title -> login (types its name) -> heroes or the builder -> town (walks,
## opens a panel or two, buys HEALING DRAUGHTS for her belt when it has none, closes them) -> the field gates -> a
## field (delves from quiet zone to quiet zone, fights on the way, rests in the nearest quiet zone when hurt, kites,
## drinks, uses skills, picks cards, banks at a waystone, leaves by the waystone, the gate or Esc) -> town again,
## until --secs runs out.
##   godot --path realm/client -s res://tests/playbot.gd -- --gateway=IP:PORT [--dev-cert=PEM] --secs=N --out=DIR
##     [--name=NAME] [--seed=N]
## Writes DIR/summary.json and screenshots (one per screen change and one a minute, at most 40) and prints one line:
## PLAYBOT ok|FAILED secs=.. screens=.. fields=.. outings=.. kills=.. deaths=.. coin=.. fps_p50=.. frame_ms_p99=..
## hitches_50ms=.. errors=.. km_walked=..  FAILED only when it never reached a field or the gateway link was lost.

const SHOT_MAX: int = 40
const SHOT_EVERY_S: float = 60.0
const HEAT_N: int = 16
## km_walked counts field and town px at 32 px a metre (a hero is about 32 px tall).
const PX_PER_M: float = 32.0
const THINK_MIN: float = 0.3
const THINK_MAX: float = 1.5
const STUCK_S: float = 3.0
const REPLAN_S: float = 0.25
const POTION_UNDER: float = 0.45
const KITE_UNDER: float = 0.5
const KITE_UNTIL: float = 0.75
const POTION_GAP_S: float = 4.0
const FIGHT_PX: float = 150.0
const STONE_PX: float = 24.0
## The delve (rules 6.1): from the entrance through the QUIET zones' shrines to the deepest and back, fighting what
## comes within ENGAGE_PX on the way; under RETREAT_UNDER health to the nearest quiet zone, resting there until
## REST_UNTIL or REST_MAX_S. HEAL_STACK is the HEALING DRAUGHT's stack kind (100 + potion 0), bought before a field.
const ENGAGE_PX: float = 260.0
const RETREAT_UNDER: float = 0.4
const REST_UNTIL: float = 0.8
const REST_MAX_S: float = 12.0
const HEAL_STACK: int = 100
const MOVES: Array[String] = ["up", "down", "left", "right"]


## Counts the engine's and the scripts' errors (Godot 4.5+ OS.add_logger); called from any thread.
class ErrorCounter extends Logger:
	var mutex: Mutex = Mutex.new()
	var errors: int = 0
	var warnings: int = 0
	var first: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		mutex.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			errors += 1
			if first.size() < 20:
				first.append("%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file.get_file(), line, function])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _log: ErrorCounter = ErrorCounter.new()
var _shell: Shell = null
var _gateway: String = "127.0.0.1:7700"
var _out: String = "user://playbot"
var _secs: float = 900.0
var _name: String = ""
var _login: String = ""
var _seed: int = 0
var _t0: int = 0
var _done: bool = false
var _failed_why: String = ""
var _link_lost: bool = false
var _reached_field: bool = false

# The person's hands: keys held and where the mouse is (window px).
var _held: Dictionary = {}
var _mouse: Vector2 = Vector2(480, 270)

# What it saw.
var _frames: PackedFloat32Array = PackedFloat32Array()
var _frame_n: int = 0
var _screen: String = ""
var _screens: Dictionary = {}
var _hitches: Array[Dictionary] = []
var _hitch50: int = 0
var _hitch100: int = 0
var _fields: int = 0
var _field_no: int = -1
var _outings: Array[Dictionary] = []
var _kills: int = 0
var _deaths: int = 0
var _coin: int = 0
var _potions: int = 0
var _picks: Array[Dictionary] = []
var _banks: int = 0
var _walked_px: float = 0.0
var _heat: Dictionary = {}
var _net: Array[Dictionary] = []
var _notes: Array[String] = []
var _dead_clicks: Array[String] = []
var _shots: int = 0
var _last_shot_s: float = 0.0
var _panels_opened: Array[String] = []
var _unsticks: int = 0
var _kites: int = 0
var _last_tick: int = -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		var v: String = kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"gateway":
				_gateway = v
			"secs":
				_secs = maxf(30.0, float(v))
			"out":
				_out = v
			"name":
				_name = v
			"seed":
				_seed = int(v)
	if _name.is_empty():
		_name = OS.get_environment("COMPUTERNAME") if OS.has_environment("COMPUTERNAME") else OS.get_environment("HOSTNAME")
	if _seed == 0:
		_seed = hash(_name + str(Time.get_unix_time_from_system()))
	_rng.seed = _seed
	_login = _login_name(_name)
	OS.add_logger(_log)
	ShellSettings.persist = false
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


## "PB" and the letters and digits of --name, 3 to 16 of them (the login's rule).
func _login_name(n: String) -> String:
	var s: String = "PB"
	for c in n.to_upper():
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			s += c
	if s.length() < 4:
		s += str(_rng.randi_range(100, 999))
	return s.left(LoginScreen.NAME_MAX)


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _over() -> bool:
	return _elapsed() >= _secs or _done


# ---- the frame clock, the screens, the shots

func _process(delta: float) -> bool:
	if _shell == null or _done:
		return false
	_frame_n += 1
	var s: String = _screen_now()
	if s != _screen:
		_screen = s
		if not _screens.has(s):
			_screens[s] = {"secs": 0.0, "inputs": 0, "visits": 0, "hitches_50ms": 0, "frames": 0}
		_screens[s]["visits"] += 1
		_shot(s)
	if _frame_n > 5:
		var ms: float = delta * 1000.0
		_frames.append(ms)
		_screens[s]["secs"] += delta
		_screens[s]["frames"] += 1
		if ms > 50.0:
			_hitch50 += 1
			_screens[s]["hitches_50ms"] += 1
			if ms > 100.0:
				_hitch100 += 1
			if _hitches.size() < 200:
				_hitches.append({"t": snappedf(_elapsed(), 0.01), "ms": snappedf(ms, 0.1), "screen": s})
	if _elapsed() - _last_shot_s >= SHOT_EVERY_S:
		_shot("minute%d" % int(_elapsed() / 60.0))
	# A run that cannot finish by itself (a screen that never lets go) still writes what it saw.
	if _elapsed() > _secs + 240.0:
		_note("overran --secs by 240 s on %s" % s)
		_finish()
	return false


func _screen_now() -> String:
	if _shell.in_field:
		return "field%d" % _field_no
	var t: UiScreen = _shell.top()
	if t == null:
		return "none"
	if t == _shell.base:
		return _shell.base_name
	return String(t.get_script().get_global_name())


func _shot(tag: String) -> void:
	_last_shot_s = _elapsed()
	if _shots >= SHOT_MAX or DisplayServer.get_name() == "headless":
		return
	_shots += 1
	var n: int = _shots
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("%s/%02d_%s.png" % [_out, n, tag.to_lower().validate_filename()])


func _note(s: String) -> void:
	if _notes.size() < 100:
		_notes.append("%.1f %s" % [_elapsed(), s])
	print("PLAYBOT_NOTE %.1f %s" % [_elapsed(), s])


func _count_input() -> void:
	if _screens.has(_screen):
		_screens[_screen]["inputs"] += 1


# ---- hands: every input is an event through Input.parse_input_event

func _key_event(code: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.physical_keycode = code as Key
	e.pressed = pressed
	if pressed:
		if code >= KEY_A and code <= KEY_Z:
			e.unicode = code + 32
		elif (code >= KEY_0 and code <= KEY_9) or code == KEY_SPACE:
			e.unicode = code
	Input.parse_input_event(e)


func _press(code: int) -> void:
	if _held.has(code):
		return
	_held[code] = true
	_key_event(code, true)
	_count_input()


func _release(code: int) -> void:
	if not _held.has(code):
		return
	_held.erase(code)
	_key_event(code, false)


func _release_all() -> void:
	for k in _held.keys():
		_release(int(k))


## One press, held as a finger holds it.
func _tap(code: int, hold_s: float = -1.0) -> void:
	_release(code)
	_press(code)
	await create_timer(hold_s if hold_s > 0.0 else _rng.randf_range(0.06, 0.14)).timeout
	_release(code)


func _tap_action(action: String) -> void:
	await _tap(ShellSettings.key(action))


func _think() -> void:
	await create_timer(_rng.randf_range(THINK_MIN, THINK_MAX)).timeout


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _until(cond: Callable, secs: float) -> bool:
	var t: int = Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t > secs * 1000.0 or _done:
			return false
		await process_frame
	return true


## The move keys held now: exactly those for a heading (dx, dy each -1, 0, 1).
func _steer(dx: int, dy: int) -> void:
	var want: Dictionary = {}
	if dy < 0:
		want[ShellSettings.key("up")] = true
	elif dy > 0:
		want[ShellSettings.key("down")] = true
	if dx < 0:
		want[ShellSettings.key("left")] = true
	elif dx > 0:
		want[ShellSettings.key("right")] = true
	for a in MOVES:
		var k: int = ShellSettings.key(a)
		if not want.has(k):
			_release(k)
	for k in want:
		_press(int(k))


func _steer_to(d: Vector2, dead: float) -> void:
	_steer(0 if absf(d.x) < dead else int(signf(d.x)), 0 if absf(d.y) < dead else int(signf(d.y)))


## Window px of a point in a screen's 960 x 540 canvas (as shell_test.gd's _mouse_reaches).
func _window_pt(s: UiScreen, p: Vector2) -> Vector2:
	return root.get_final_transform() * (s.get_global_transform_with_canvas() * p)


## The mouse glides there over a few frames, as a hand moves it.
func _mouse_to(p: Vector2) -> void:
	var from: Vector2 = _mouse
	var steps: int = _rng.randi_range(4, 9)
	for i in steps:
		var q: Vector2 = from.lerp(p, float(i + 1) / steps) + (Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2)) if i + 1 < steps else Vector2.ZERO)
		var m := InputEventMouseMotion.new()
		m.position = q
		m.global_position = q
		m.relative = q - _mouse
		_mouse = q
		Input.parse_input_event(m)
		await process_frame


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = button
	b.pressed = pressed
	b.position = _mouse
	b.global_position = _mouse
	b.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	Input.parse_input_event(b)


func _click_at(p: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await _mouse_to(p)
	await _wait(_rng.randf_range(0.04, 0.15))
	_mouse_button(button, true)
	_count_input()
	await _wait(_rng.randf_range(0.05, 0.11))
	_mouse_button(button, false)


## Clicks a button the top screen drew, somewhere inside it. False when it is not there (or disabled). A button
## another one covers (the later one wins) is clicked anyway and noted: a person would click what she sees.
func _click(id: String) -> bool:
	var s: UiScreen = _shell.top()
	if s == null:
		return false
	var h: Dictionary = s._hit_by_id(id)
	if h.is_empty() or not bool(h["enabled"]):
		return false
	var r: Rect2 = h["rect"]
	# Somewhere on it a person can see (inside the window, not under another button), near its middle first.
	var c: Vector2 = r.get_center()
	var view := Rect2(4, 4, UiKit.W - 8, UiKit.H - 8)
	for i in 16:
		var k: float = 0.25 if i < 4 else 0.48
		var q: Vector2 = r.get_center() + Vector2(_rng.randf_range(-k, k) * r.size.x, _rng.randf_range(-k, k) * r.size.y)
		var hit_q: Dictionary = s._hit_at(q)
		if view.has_point(q) and not hit_q.is_empty() and String(hit_q["id"]) == id:
			c = q
			break
	var under: Dictionary = s._hit_at(c)
	if not under.is_empty() and String(under["id"]) != id:
		var what: String = "%s:%s under %s" % [_screen, id, String(under["id"])]
		if not _dead_clicks.has(what):
			_dead_clicks.append(what)
			_note("covered button " + what)
	await _click_at(_window_pt(s, c))
	return true


## A right click where the top screen drew nothing (it goes back, as Esc does). False when it found no such spot.
func _right_click_empty() -> bool:
	var s: UiScreen = _shell.top()
	if s == null:
		return false
	for i in 40:
		var p := Vector2(_rng.randf_range(10, UiKit.W - 10), _rng.randf_range(10, UiKit.H - 10))
		if s._hit_at(p).is_empty():
			await _click_at(_window_pt(s, p), MOUSE_BUTTON_RIGHT)
			return true
	return false


## A key or the button (a coin toss, as a person mixes them).
func _key_or_click(code: int, id: String) -> void:
	if _rng.randf() < 0.5 or not await _click(id):
		await _tap(code)


# ---- the run

func _run() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_shell = Shell.new()
	_shell.set_gateway(_gateway)
	root.add_child(_shell)
	await process_frame
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(960, 540)
	_shell.link.lost.connect(func(why: String) -> void:
		_link_lost = true
		_note("gateway link lost: " + why))
	_shell.field_started.connect(func(f: int) -> void:
		_fields += 1
		_field_no = f
		_reached_field = true)
	_shell.field_ended.connect(_on_outing)
	_t0 = Time.get_ticks_msec()
	_shell.show_base(TitleScreen.new(), "title")
	if not await _to_town():
		_finish()
		return
	while not _over() and not _link_lost:
		if _shell.in_field:
			await _field()
			continue
		match _shell.base_name:
			"town":
				await _town()
			"hero_list", "hero_builder":
				await _heroes()
			_:
				_note("lost on %s, back to the start" % _shell.base_name)
				if not await _to_town():
					break
	_finish()


## Title, login, the heroes, until the town.
func _to_town() -> bool:
	if not await _until(func() -> bool: return _shell.top() != null and _shell.top().has_hit("enter"), 10.0):
		_failed_why = "no title"
		return false
	await _think()
	await _key_or_click(KEY_ENTER, "enter")
	if not await _until(func() -> bool: return _shell.base_name == "login", 5.0):
		_failed_why = "the title did not lead to the login"
		return false
	for attempt in 3:
		await _think()
		var login: LoginScreen = _shell.base as LoginScreen
		# Erase what is there, then spell the name, a key at a time.
		for i in login.board.text.length():
			await _tap(KEY_BACKSPACE, _rng.randf_range(0.03, 0.07))
			await _wait(_rng.randf_range(0.03, 0.09))
		for c in _login:
			await _tap(c.unicode_at(0))
			await _wait(_rng.randf_range(0.05, 0.22))
		await _think()
		await _key_or_click(KEY_ENTER, "go")
		if await _until(func() -> bool: return _shell.base_name in ["hero_list", "hero_builder"], 40.0):
			break
		_note("login did not get through (%s): %s" % [_shell.base_name, (_shell.top() as UiScreen).toast_text if _shell.top() != null else ""])
		if _shell.base_name != "login":
			_failed_why = "the login fell back to %s" % _shell.base_name
			return false
	if not _shell.base_name in ["hero_list", "hero_builder"]:
		_failed_why = "the login never got through"
		return false
	return await _heroes()


## The hero list (enter the first hero) or the builder (a random race and class).
func _heroes() -> bool:
	for attempt in 4:
		if _shell.base_name == "town":
			return true
		await _think()
		if _shell.base_name == "hero_builder":
			var bid: int = _shell.base.get_instance_id()
			await _click("race:%d" % _rng.randi_range(0, RealmClient.RACE_COUNT - 1))
			await _think()
			await _click("class:%d" % _rng.randi_range(1, RealmClient.CLASS_COUNT))
			if _rng.randf() < 0.5:
				await _wait(_rng.randf_range(0.2, 0.6))
				await _click("pal:1")
			if attempt > 0:
				# The name was taken: she types one of her own.
				for c in _login.substr(2).left(10):
					await _tap(c.unicode_at(0))
					await _wait(_rng.randf_range(0.05, 0.2))
				await _tap(KEY_A + _rng.randi_range(0, 25))
			await _think()
			await _key_or_click(KEY_ENTER, "create")
			await _until(func() -> bool: return _shell.base_name != "hero_builder" or not is_instance_id_valid(bid) or not (instance_from_id(bid) as HeroBuilderScreen).busy, 40.0)
			await _until(func() -> bool: return _shell.base_name != "hero_builder", 3.0)
		elif _shell.base_name == "hero_list":
			if _shell.heroes.is_empty():
				await _key_or_click(KEY_ENTER, "new")
			else:
				await _click("hero:0")
				await _think()
				await _key_or_click(KEY_ENTER, "enter")
			await _until(func() -> bool: return _shell.base_name != "hero_list", 30.0)
		else:
			return false
		await _until(func() -> bool: return _shell.base_name == "town", 15.0)
	if _shell.base_name != "town":
		_note("never reached the town from %s" % _shell.base_name)
		return false
	return true


# ---- the town

func _town() -> void:
	var town: TownScreen = _shell.base as TownScreen
	if town == null or not is_instance_valid(town):
		await _wait(0.5)
		return
	var tid: int = town.get_instance_id()
	if not await _until(func() -> bool: return not is_instance_id_valid(tid) or _town_ready(instance_from_id(tid) as TownScreen), 20.0) or not is_instance_valid(town):
		_note("the town showed no hero")
		await _wait(1.0)
		return
	# Back from a field: the outing's panel first.
	while _shell.top() != town and is_instance_valid(town):
		await _think()
		await _close_panel()
	var n: int = _rng.randi_range(1, 2)
	for i in n:
		if _over() or not is_instance_valid(town) or _shell.base != town:
			return
		var roll: float = _rng.randf()
		if roll < 0.25:
			await _think()
			await _key_or_click(ShellSettings.key("bag"), "bag")
		elif roll < 0.4:
			await _think()
			await _key_or_click(ShellSettings.key("sheet"), "sheet")
		else:
			var ids: Array[String] = ["bank", "smith", "merchants", "reader", "trainer", "market", "post", "board"]
			await _visit_station(town, ids[_rng.randi_range(0, ids.size() - 1)])
		if await _until(func() -> bool: return _top_id() != tid, 3.0):
			_panels_opened.append(_screen_now())
			await _browse()
			await _close_panel()
	if _over() or not is_instance_valid(town) or _shell.base != town:
		return
	await _stock_belt(town)
	if _over() or not is_instance_valid(town) or _shell.base != town:
		return
	await _visit_station(town, "gate")
	if not await _until(func() -> bool: return _shell.panel_of("GatePanel") != null, 5.0):
		_note("the gates did not open")
		await _close_panel()
		return
	var gates: GatePanel = _shell.panel_of("GatePanel") as GatePanel
	await _think()
	var fit: int = gates.fit_field()
	var f: int = fit if _rng.randf() < 0.6 else _rng.randi_range(0, fit)
	if f == fit and _rng.randf() < 0.5:
		await _tap(KEY_ENTER)
	else:
		await _click("field:%d" % f)
	if not await _until(func() -> bool: return _shell.in_field, 30.0):
		_note("the gates did not let her through: %s" % (_shell.top().toast_text if _shell.top() != null else ""))
		await _close_panel()


## Draughts on the belt before a field, as a person would (a new hero's belt is empty, and the playbot that never
## bought any never drank one): the merchant's BUY tab for HEALING DRAUGHTS, then his BELT tab to put them in slot 1.
## Without the coin she goes without, and says so once.
func _stock_belt(town: TownScreen) -> void:
	var belt: Array = _shell.hero.get("belt", [0, 0, 0])
	if belt.has(HEAL_STACK) and _shell.stack_count(GameNames.PLACE_BAG, HEAL_STACK) > 0:
		return
	await _visit_station(town, "merchants")
	if not await _until(func() -> bool: return _shell.panel_of("MerchantPanel") != null, 3.0):
		_note("the merchant did not open")
		return
	var mp: MerchantPanel = _shell.panel_of("MerchantPanel") as MerchantPanel
	var mid: int = mp.get_instance_id()
	await _until(func() -> bool: return not is_instance_id_valid(mid) or not (instance_from_id(mid) as MerchantPanel).offers.is_empty(), 5.0)
	if not is_instance_valid(mp):
		return
	if _shell.stack_count(GameNames.PLACE_BAG, HEAL_STACK) == 0:
		var oid: int = -1
		for o in mp.offers:
			if int(o["kind"]) != 2 and int(o["stack"]) == HEAL_STACK:
				oid = int(o["id"])
		await _think()
		var bought: bool = false
		if oid >= 0:
			bought = await _click("buy:%d:5" % oid)
			if not bought:
				bought = await _click("buy:%d:1" % oid)
		if not bought:
			_note("no healing draughts bought (coin %d)" % _shell.coin())
			await _close_panel()
			return
		await _until(func() -> bool: return _shell.stack_count(GameNames.PLACE_BAG, HEAL_STACK) > 0, 5.0)
	await _think()
	await _click("tab:3")
	await _wait(0.3)
	await _click("slot:0")
	await _wait(0.2)
	if await _click("pot:%d" % HEAL_STACK):
		_note("healing draughts on the belt")
	await _wait(0.5)
	await _close_panel()


func _top_id() -> int:
	var t: UiScreen = _shell.top()
	return t.get_instance_id() if t != null else 0


func _town_ready(town: TownScreen) -> bool:
	return town.members.has(town.me) and town.snapshots >= 2


func _joined(c: RealmClient) -> bool:
	return int(c.link.counters().get("ticks_applied", 0)) > 5 and not c._info.is_empty()


## Walks to a station with the move keys and opens it with a click on it (or F at its door).
func _visit_station(town: TownScreen, sid: String) -> void:
	var st: Dictionary = TownMap.station(sid, town.stations)
	if st.is_empty():
		return
	var goal: Vector2 = st["at"] + Vector2(_rng.randf_range(-40, 40), (-1.0 if sid == "gate" else 1.0) * _rng.randf_range(50, 90))
	var t0: float = _elapsed()
	var last: Vector2 = town.shown(town.me)
	var last_t: float = t0
	var prev: Vector2 = last
	var detour: Vector2 = Vector2.ZERO
	var detour_until: float = 0.0
	while _elapsed() - t0 < 60.0 and is_instance_valid(town) and _shell.top() == town and not _done:
		if town.typing:
			# A click went to the chat line: the move keys type there now. Esc lets go of it.
			_note("the chat line took the keys, Esc")
			_steer(0, 0)
			await _tap(KEY_ESCAPE)
			await _wait(0.3)
			continue
		var at: Vector2 = town.shown(town.me)
		_walked_px += at.distance_to(prev)
		prev = at
		var d: Vector2 = goal - at
		# Close enough to click it (where it is on screen): a person clicks once she sees the door.
		var h: Dictionary = town._hit_by_id("st:" + sid)
		if at.distance_to(st["at"]) <= TownMap.CLICK_PX * 0.8 and not h.is_empty():
			var c: Vector2 = (h["rect"] as Rect2).get_center()
			if c.x > 20 and c.x < UiKit.W - 20 and c.y > 80 and c.y < UiKit.H - 20:
				_steer(0, 0)
				await _wait(_rng.randf_range(0.15, 0.5))
				if _rng.randf() < 0.3 and town.has_hit("prompt"):
					await _tap_action("interact")
				else:
					await _click("st:" + sid)
				var tid: int = town.get_instance_id()
				await _until(func() -> bool: return _top_id() != tid, 3.0)
				return
		if d.length() < 30.0:
			_steer(0, 0)
			await _tap_action("interact")
			return
		if _elapsed() < detour_until:
			_steer_to(detour, 0.5)
		else:
			_steer_to(d, 24.0)
		if at.distance_to(last) > 10.0:
			last = at
			last_t = _elapsed()
		elif _elapsed() - last_t > STUCK_S:
			_unsticks += 1
			detour = Vector2.from_angle(_rng.randf() * TAU)
			detour_until = _elapsed() + 1.2
			last_t = _elapsed()
		await process_frame
	_steer(0, 0)
	if is_instance_valid(town) and _shell.top() == town:
		_note("walk to %s ran out of time (at %s)" % [sid, str(town.shown(town.me).round())])


## A look over the panel: the mouse wanders over its buttons for a few seconds.
func _browse() -> void:
	var t: float = _rng.randf_range(1.5, 5.0)
	var end: float = _elapsed() + t
	while _elapsed() < end and not _done:
		var s: UiScreen = _shell.top()
		if s == null or s._hits.is_empty():
			break
		var h: Dictionary = s._hits[_rng.randi_range(0, s._hits.size() - 1)]
		await _mouse_to(_window_pt(s, (h["rect"] as Rect2).get_center()))
		await _wait(_rng.randf_range(0.3, 1.0))


## Closes the top panel the way a person might: Esc, a right click on nothing, or its button.
func _close_panel() -> void:
	var p: UiScreen = _shell.top()
	if p == null or p == _shell.base:
		return
	var pid: int = p.get_instance_id()
	var roll: float = _rng.randf()
	var how: String = "esc"
	if roll < 0.35:
		await _tap(KEY_ESCAPE)
	elif roll < 0.6 and await _right_click_empty():
		how = "right click"
	elif await _click("close"):
		how = "close button"
	else:
		await _tap(KEY_ESCAPE)
	if not await _until(func() -> bool: return _top_id() != pid, 2.0):
		var what: String = "%s did not close by %s" % [_screen_now(), how]
		if not _dead_clicks.has(what):
			_dead_clicks.append(what)
		_note(what)
		await _tap(KEY_ESCAPE)
		await _until(func() -> bool: return _top_id() != pid, 2.0)


# ---- the field

func _on_outing(o: Dictionary) -> void:
	var row: Dictionary = {}
	for k in o:
		if typeof(o[k]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL]:
			row[k] = o[k]
	row["field"] = _field_no
	row["at_s"] = snappedf(_elapsed(), 0.1)
	_outings.append(row)
	_coin += int(o.get("coin", 0))
	_note("outing over in field %d: %s" % [_field_no, str(row)])


func _field() -> void:
	var c: RealmClient = _shell.field_client as RealmClient
	var f: int = _field_no
	var cid: int = c.get_instance_id()
	if not await _until(func() -> bool: return not is_instance_id_valid(cid) or _joined(instance_from_id(cid) as RealmClient), 40.0) or not is_instance_valid(c):
		_note("the field client never joined field %d" % f)
		await _until(func() -> bool: return not _shell.in_field, 30.0)
		return
	var b := Brain.new()
	b.bot = self
	b.c = c
	b.field = f
	b.side = float(RealmLink.field_size())
	b.started = _elapsed()
	b.bank_at = b.started + minf(_rng.randf_range(90.0, 200.0), maxf(20.0, _secs - _elapsed() - 70.0))
	# Out of the entrance's quiet zone along the delve: to the first intermission, fighting on the way.
	var info0: Dictionary = c._info
	b.goal = b._leg_goal()
	var key: String = str(f)
	if not _heat.has(key):
		var g := PackedInt32Array()
		g.resize(HEAT_N * HEAT_N)
		_heat[key] = g
	var net: Dictionary = {"field": f, "sim_ms_per_tick_max": 0.0, "frame_build_ms_max": 0.0, "sites": Array(c._world_info.get("sites", PackedFloat32Array())), "start": [float(info0.get("x", 0)), float(info0.get("y", 0))]}
	_net.append(net)
	var last_sample: float = 0.0
	while is_instance_valid(c) and _shell.in_field and _shell.field_client == c and not _done:
		await b.step()
		if _elapsed() - last_sample >= 0.5 and is_instance_valid(c):
			last_sample = _elapsed()
			var at: Vector2 = b.at
			var cx: int = clampi(int(at.x / b.side * HEAT_N), 0, HEAT_N - 1)
			var cy: int = clampi(int(at.y / b.side * HEAT_N), 0, HEAT_N - 1)
			var g: PackedInt32Array = _heat[key]
			g[cy * HEAT_N + cx] += 1
			_heat[key] = g
			var cn: Dictionary = c.link.counters()
			for k in cn:
				net[k] = cn[k]
			net["sim_ms_per_tick_max"] = maxf(float(net["sim_ms_per_tick_max"]), float(cn.get("sim_ms_per_tick", 0.0)))
			net["frame_build_ms_max"] = maxf(float(net["frame_build_ms_max"]), float(cn.get("frame_build_ms", 0.0)))
			net["players"] = c.link.player_count()
			net["monsters"] = c.link.monster_count()
		await process_frame
	_release_all()
	net["left_by"] = b.leaving
	if not await _until(func() -> bool: return _shell.base_name == "town" or _link_lost, 30.0):
		_note("not back in town after the field (%s)" % _shell.base_name)


## The player in the field: reads the hero, the monsters in view and the sites; holds the move keys toward a
## goal, the skill keys while fighting, taps a potion when hurt and a card key when a draw is offered.
class Brain extends RefCounted:
	var bot: Variant = null
	var c: RealmClient = null
	var field: int = 0
	var side: float = 4096.0
	var started: float = 0.0
	var bank_at: float = 0.0
	var mode: String = "hunt"
	var leaving: String = ""
	var at: Vector2 = Vector2(-1, -1)
	var goal: Vector2 = Vector2(-1, -1)
	var explore_until: float = 0.0
	var plan_t: float = -1.0
	var moved_t: float = 0.0
	var moved_at: Vector2 = Vector2.ZERO
	var detour: Vector2 = Vector2.ZERO
	var detour_until: float = 0.0
	var alive: bool = true
	var pick_at: float = -1.0
	var potion_t: float = -100.0
	var hold_t: float = -1.0
	var esc_n: int = 0
	var near_n: int = 0
	var fight_d: float = INF
	var foes: Vector2 = Vector2.ZERO
	var tapping: bool = false
	var kiting: bool = false
	var roam_until: float = -1.0
	var deaths: int = 0
	var avoid: Array[Vector2] = []
	var kite_t: float = -100.0
	## The delve: the shrine zone she walks to next (1-based, as the core's shrines), in or out, and her rest.
	var leg: int = 1
	var inward: bool = true
	var resting: bool = false
	var rest_t: float = -1.0

	func now() -> float:
		return bot._elapsed()

	func step() -> void:
		var info: Dictionary = c._info
		if info.is_empty():
			return
		var p := Vector2(float(info["x"]), float(info["y"]))
		if at.x >= 0.0 and p.distance_to(at) < 200.0:
			bot._walked_px += p.distance_to(at)
		at = p
		_events()
		var was: bool = alive
		alive = bool(info.get("alive", true))
		if was and not alive:
			bot._deaths += 1
			deaths += 1
			# She fell by a waystone: another one next time. Four deaths: enough of this field, to bank and go.
			var w: Vector2 = _nearest_stone()
			if w.x >= 0.0 and w.distance_to(at) < 400.0:
				avoid.append(w)
			if deaths >= 4 and mode == "hunt":
				bank_at = 0.0
			bot._note("died in field %d at %s" % [field, str(at.round())])
			if deaths <= 3:
				bot._shot("down%d_field%d" % [bot._deaths, field])
		if tapping:
			return
		if not alive:
			# Downed: hands off the keys, but a card on offer is still picked.
			if not bot._held.is_empty():
				bot._release_all()
			await _pick(info, now())
			return
		if not was:
			# Up again (raised or back at the start): away from where she fell, roaming for a while.
			roam_until = now() + 30.0
			goal = Vector2(bot._rng.randf_range(0.15, 0.85) * side, maxf(side * 0.1, at.y - bot._rng.randf_range(800.0, 1600.0)))
			explore_until = roam_until
		var t: float = now()
		if t - plan_t >= REPLAN_S:
			plan_t = t
			_plan(info, t)
		await _hands(info, t)

	## Her kills from this frame's events: a kill row (rank 10) names no killer, so it counts the kills within
	## 300 px of her in a frame that also gave her XP (rank 11). A frame skipped between two polls is missed.
	func _events() -> void:
		var tick: int = c.link.confirmed_tick()
		if tick == bot._last_tick:
			return
		bot._last_tick = tick
		var ev: PackedInt32Array = c.link.event_rows()
		var me: int = c.link.hero_id()
		var xp: bool = false
		var near: int = 0
		for i in range(0, ev.size() - 7, 8):
			if ev[i] == 11 and ev[i + 1] == me:
				xp = true
			elif ev[i] == 10 and Vector2(ev[i + 5], ev[i + 6]).distance_to(at) < 300.0:
				near += 1
		if xp:
			bot._kills += near

	func _sites() -> PackedFloat32Array:
		return c._world_info.get("sites", PackedFloat32Array())

	func _site(i: int) -> Vector2:
		var s: PackedFloat32Array = _sites()
		return Vector2(s[i * 2], s[i * 2 + 1]) if s.size() > i * 2 + 1 else Vector2(-1, -1)

	## The quiet zones: Vector3(x, y, radius px) a zone, with the shrine index in `shrines` (-1 a ward).
	func _quiet() -> PackedFloat32Array:
		return c._world_info.get("quiet", PackedFloat32Array())

	func _in_quiet(p: Vector2) -> bool:
		var q: PackedFloat32Array = _quiet()
		for i in range(0, q.size() - 3, 4):
			if p.distance_to(Vector2(q[i], q[i + 1])) < q[i + 2]:
				return true
		return false

	func _nearest_quiet(p: Vector2) -> Vector3:
		var q: PackedFloat32Array = _quiet()
		var best := Vector3(-1, -1, 0)
		for i in range(0, q.size() - 3, 4):
			var z := Vector2(q[i], q[i + 1])
			if best.z <= 0.0 or p.distance_to(z) < p.distance_to(Vector2(best.x, best.y)):
				best = Vector3(z.x, z.y, q[i + 2])
		return best

	## The next zone of the delve (the intermissions in shrine order, there and back); it moves on once she is well
	## inside the one she walked to. (-1, -1) when the field has none.
	func _leg_goal() -> Vector2:
		var q: PackedFloat32Array = _quiet()
		var route: Array[Vector3] = []
		for k in range(1, 8):
			for i in range(0, q.size() - 3, 4):
				if int(q[i + 3]) == k:
					route.append(Vector3(q[i], q[i + 1], q[i + 2]))
		if route.is_empty():
			return Vector2(-1, -1)
		leg = clampi(leg, 1, route.size())
		var z: Vector3 = route[leg - 1]
		if at.x >= 0.0 and at.distance_to(Vector2(z.x, z.y)) < z.z * 0.6:
			if inward and leg >= route.size():
				inward = false
			elif not inward and leg <= 1:
				inward = true
			leg = mini(leg + 1, route.size()) if inward else maxi(leg - 1, 1)
			z = route[leg - 1]
		return Vector2(z.x, z.y)

	func _nearest_stone() -> Vector2:
		var best: Vector2 = Vector2(-1, -1)
		for i in 7:
			var w: Vector2 = _site(2 + i)
			if w.x >= 0.0 and not avoid.has(w) and (best.x < 0.0 or at.distance_to(w) < at.distance_to(best)):
				best = w
		return best

	func _plan(info: Dictionary, t: float) -> void:
		# The monsters in view: the nearest, the cluster round it, how many are close.
		var buf: PackedFloat32Array = c.link.monster_buffer()
		var nearest: Vector2 = Vector2(-1, -1)
		var nd: float = INF
		near_n = 0
		var sum: Vector2 = Vector2.ZERO
		var close_n: int = 0
		for i in range(0, buf.size() - 15, 16):
			var m := Vector2(buf[i + 3], buf[i + 7])
			var d: float = m.distance_to(at)
			if d < nd:
				nd = d
				nearest = m
			if d < 220.0:
				sum += m
				close_n += 1
			if d < FIGHT_PX:
				near_n += 1
		fight_d = nd
		foes = sum / close_n if close_n > 0 else Vector2(-1, -1)
		var frac: float = float(info["health"]) / maxf(float(info["max_health"]), 1.0)
		if mode == "bank" and bot._over():
			mode = "hunt"
		if mode == "hunt":
			if bot._over():
				# Time is up: out by whichever is nearer, the gate or a waystone (held twice as long).
				var w: Vector2 = _nearest_stone()
				var g0: Vector2 = _site(0)
				mode = "stone" if w.x >= 0.0 and (g0.x < 0.0 or at.distance_to(w) < at.distance_to(g0)) else "gate"
				leaving = "waystone" if mode == "stone" else "gate"
				bot._note("field %d: time is up, out by the %s" % [field, leaving])
			elif t >= bank_at:
				mode = "bank"
				bot._note("field %d: to a waystone to bank" % field)
		if bot._elapsed() > bot._secs + 90.0 and mode != "esc":
			mode = "esc"
			bot._note("field %d: still in 90 s after time, Esc" % field)
		# Hurt: to the nearest quiet zone, where no monster follows, and rest there (a draught is tapped on the way).
		if mode == "hunt" and not resting and frac < RETREAT_UNDER:
			resting = true
			rest_t = -1.0
			kiting = false
			bot._note("field %d: hurt, back to a quiet zone" % field)
		if resting:
			var z: Vector3 = _nearest_quiet(at)
			if mode != "hunt" or z.z <= 0.0 or frac >= REST_UNTIL or (rest_t >= 0.0 and t - rest_t > REST_MAX_S):
				resting = false
			else:
				goal = Vector2(z.x, z.y)
				if rest_t < 0.0 and at.distance_to(goal) < z.z * 0.7:
					rest_t = t
				return
		# Kiting, whatever she is on her way to: hurt with monsters close, she backs off (at most 10 s at a time).
		if not kiting and frac < KITE_UNDER and foes.x >= 0.0 and mode != "esc" and t - kite_t > 4.0:
			kiting = true
			kite_t = t
			bot._kites += 1
		elif kiting and (frac > KITE_UNTIL or foes.x < 0.0 or t - kite_t > 10.0):
			kiting = false
			kite_t = t
		if kiting:
			goal = at + (at - foes).normalized() * 200.0
			var g: Vector2 = _site(0)
			if g.x >= 0.0 and goal.distance_to(g) < 300.0:
				goal = at + (at - foes).normalized().rotated(PI / 2.0 if bot._rng.randf() < 0.5 else -PI / 2.0) * 200.0 + Vector2(0, -120)
			return
		match mode:
			"hunt":
				var lg: Vector2 = _leg_goal()
				if lg.x >= 0.0 and (nearest.x < 0.0 or nd > ENGAGE_PX):
					# Nothing close: on along the delve.
					goal = lg
					return
				if t < roam_until and goal.x >= 0.0 and at.distance_to(goal) > 64.0:
					return
				if nearest.x >= 0.0:
					# Healthy: the middle of the pack round the nearest; hurt: the nearest alone.
					if frac < 0.8:
						goal = nearest
						return
					var cl: Vector2 = Vector2.ZERO
					var n: int = 0
					for i in range(0, buf.size() - 15, 16):
						var m := Vector2(buf[i + 3], buf[i + 7])
						if m.distance_to(nearest) < 100.0:
							cl += m
							n += 1
					goal = cl / n
				elif goal.x < 0.0 or t > explore_until or at.distance_to(goal) < 64.0:
					# Somewhere a walk away (she walks 60 px a second): 600 to 1 800 px off, inside the field.
					var off: Vector2 = Vector2.from_angle(bot._rng.randf() * TAU) * bot._rng.randf_range(600.0, 1800.0)
					goal = (at + off).clamp(Vector2.ONE * side * 0.05, Vector2.ONE * side * 0.95)
					explore_until = t + 40.0
			"bank", "stone":
				goal = _nearest_stone()
			"gate":
				goal = _site(0)


	## A card on offer: a moment to read it, then its key. True when it tapped one.
	func _pick(info: Dictionary, t: float) -> bool:
		var offer: PackedInt32Array = info.get("offer", PackedInt32Array())
		var slots: Array[int] = []
		for s in offer.size():
			if offer[s] > 0:
				slots.append(s)
		if slots.is_empty():
			pick_at = -1.0
		elif pick_at < 0.0:
			pick_at = t + bot._rng.randf_range(0.5, 2.0)
		elif t >= pick_at:
			var s: int = slots[bot._rng.randi_range(0, slots.size() - 1)]
			bot._picks.append({"t": snappedf(t, 0.1), "field": field, "slot": s + 1, "card": offer[s]})
			pick_at = t + 1.5
			tapping = true
			await bot._tap_action("pick%d" % (s + 1))
			tapping = false
			return true
		return false

	func _hands(info: Dictionary, t: float) -> void:
		var frac: float = float(info["health"]) / maxf(float(info["max_health"]), 1.0)
		if await _pick(info, t):
			return
		# A potion when hurt (one with charges, not resting).
		if frac < POTION_UNDER and t - potion_t > POTION_GAP_S:
			var belt: PackedInt32Array = info.get("belt", PackedInt32Array())
			for slot in 3:
				if belt.size() > slot * 3 + 2 and belt[slot * 3] >= 0 and belt[slot * 3 + 1] > 0 and belt[slot * 3 + 2] == 0:
					potion_t = t
					bot._potions += 1
					tapping = true
					await bot._tap_action("potion%d" % (slot + 1))
					tapping = false
					return
		# Skills: the first held while anything is close; the second and the ultimate when ready.
		var skills: PackedInt32Array = info.get("skills", PackedInt32Array())
		var fighting: bool = near_n > 0 and mode != "stone"
		_hold(ShellSettings.key("skill1"), fighting)
		_hold(ShellSettings.key("skill2"), fighting and skills.size() > 5 and skills[4] >= 0 and skills[5] == 0)
		_hold(ShellSettings.key("ult"), near_n >= 4 and skills.size() > 9 and skills[8] >= 0 and skills[9] == 0)
		# The legs.
		match mode:
			"bank", "stone":
				if goal.x >= 0.0 and at.distance_to(goal) <= STONE_PX:
					bot._steer(0, 0)
					if near_n > 0 and hold_t < 0.0:
						# A hit pauses the hold: clear them off first.
						return
					_rite(info, t)
					return
			"gate":
				if goal.x >= 0.0 and at.distance_to(goal) <= 40.0:
					# Out through the gate: south, through it.
					bot._steer(0, 1)
					_hold(ShellSettings.key("interact"), false)
					if hold_t < 0.0:
						hold_t = t
						leaving = "gate"
					elif t - hold_t > 20.0:
						_escape(t)
					return
			"esc":
				_escape(t)
				return
		_hold(ShellSettings.key("interact"), false)
		hold_t = -1.0
		if goal.x < 0.0:
			bot._steer(0, 0)
			return
		if resting and rest_t >= 0.0 and at.distance_to(goal) < 40.0:
			bot._steer(0, 0)
			moved_t = t
			return
		var d: Vector2 = goal - at
		# Never south near the gate unless leaving: a step south through it ends the outing.
		var g: Vector2 = _site(0)
		if g.x >= 0.0 and at.distance_to(g) < 220.0:
			d.y = minf(d.y, -40.0)
		if mode == "hunt" and not kiting and fight_d < 34.0:
			# In among them: stand and swing, a small step now and then.
			if bot._rng.randf() < 0.02:
				bot._steer(bot._rng.randi_range(-1, 1), bot._rng.randi_range(-1, 1))
			elif bot._rng.randf() < 0.1:
				bot._steer(0, 0)
			moved_t = t
			return
		if t < detour_until:
			bot._steer_to(detour, 0.5)
		else:
			bot._steer_to(d, 10.0)
		# Unstick: no headway for STUCK_S with a move key held.
		if at.distance_to(moved_at) > 8.0:
			moved_at = at
			moved_t = t
		elif t - moved_t > STUCK_S:
			bot._unsticks += 1
			detour = Vector2.from_angle(bot._rng.randf() * TAU)
			detour_until = t + 1.5
			moved_t = t
			if mode == "hunt" and fight_d > FIGHT_PX:
				goal = Vector2(-1, -1)

	func _hold(code: int, on: bool) -> void:
		if on:
			bot._press(code)
		else:
			bot._release(code)

	## At the waystone: interact held 3 s banks; held 3 s again (banked here) walks her home with what she carries.
	func _rite(info: Dictionary, t: float) -> void:
		var banked_here: bool = bool(info.get("banked", false))
		if hold_t < 0.0:
			hold_t = t
			bot._press(ShellSettings.key("interact"))
			return
		if mode == "bank" and banked_here:
			bot._release(ShellSettings.key("interact"))
			bot._banks += 1
			bot._note("banked at a waystone in field %d" % field)
			hold_t = -1.0
			var left: float = bot._secs - bot._elapsed()
			var roll: float = bot._rng.randf()
			if left > 300.0 and roll < 0.25:
				mode = "hunt"
				bank_at = t + bot._rng.randf_range(90.0, 160.0)
			elif roll < 0.6:
				mode = "stone"
				leaving = "waystone"
			elif roll < 0.85:
				mode = "gate"
			else:
				mode = "esc"
			return
		if t - hold_t > 12.0:
			# Hurt keeps pausing the hold: fight a little, then try again.
			bot._release(ShellSettings.key("interact"))
			bot._note("the hold at the waystone did not finish (%s)" % mode)
			hold_t = -1.0
			if mode == "stone":
				mode = "gate"
			else:
				mode = "hunt"
				bank_at = t + 20.0

	## Esc, then Esc again while the warning shows (the shell leaves on the second, half the haul lost).
	func _escape(t: float) -> void:
		bot._steer(0, 0)
		if hold_t < 0.0 or t - hold_t > 1.2:
			if esc_n >= 4:
				return
			hold_t = t
			esc_n += 1
			leaving = "esc"
			bot._note("Esc %d in field %d" % [esc_n, field])
			tapping = true
			await bot._tap(KEY_ESCAPE)
			tapping = false


# ---- the report

func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s: PackedFloat32Array = a.duplicate()
	s.sort()
	return s[clampi(int(q * (s.size() - 1)), 0, s.size() - 1)]


func _finish() -> void:
	if _done:
		return
	_done = true
	_release_all()
	var ok: bool = _reached_field and not _link_lost
	if not _reached_field and _failed_why.is_empty():
		_failed_why = "never reached a field"
	if _link_lost:
		_failed_why = "the gateway link was lost"
	var p50: float = _pct(_frames, 0.5)
	var p99: float = _pct(_frames, 0.99)
	var fmax: float = _pct(_frames, 1.0)
	var fps50: float = 1000.0 / p50 if p50 > 0.0 else 0.0
	var screens: Dictionary = {}
	for s in _screens:
		var r: Dictionary = _screens[s]
		screens[s] = {"secs": snappedf(float(r["secs"]), 0.1), "inputs": r["inputs"], "visits": r["visits"], "frames": r["frames"], "hitches_50ms": r["hitches_50ms"]}
	var heat: Dictionary = {}
	for k in _heat:
		var g: PackedInt32Array = _heat[k]
		var rows: Array = []
		var used: int = 0
		for y in HEAT_N:
			var row: Array = []
			for x in HEAT_N:
				row.append(g[y * HEAT_N + x])
				if g[y * HEAT_N + x] > 0:
					used += 1
			rows.append(row)
		heat[k] = {"cells_visited": used, "grid": rows}
	_log.mutex.lock()
	var errors: int = _log.errors
	var warnings: int = _log.warnings
	var first_errors: Array[String] = _log.first.duplicate()
	_log.mutex.unlock()
	var km: float = _walked_px / PX_PER_M / 1000.0
	var sum := {
		"ok": ok, "why": _failed_why, "name": _login, "seed": _seed, "gateway": _gateway, "secs": snappedf(_elapsed(), 0.1),
		"renderer": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(), "os": OS.get_name(),
		"window": "%dx%d" % [root.size.x, root.size.y],
		"frames": {"count": _frames.size(), "fps_p50": snappedf(fps50, 0.1), "ms_p50": snappedf(p50, 0.01), "ms_p99": snappedf(p99, 0.01), "ms_max": snappedf(fmax, 0.01),
			"over_50ms": _hitch50, "over_100ms": _hitch100, "hitches": _hitches},
		"screens": screens, "fields_entered": _fields, "outings": _outings, "kills": _kills, "deaths": _deaths, "coin": _coin,
		"potions": _potions, "card_picks": _picks, "banks": _banks, "km_walked": snappedf(km, 0.001), "unsticks": _unsticks, "kites": _kites,
		"panels_opened": _panels_opened, "net": _net, "heat": heat, "errors": errors, "warnings": warnings, "first_errors": first_errors,
		"dead_clicks": _dead_clicks, "notes": _notes, "shots": _shots}
	var f := FileAccess.open(_out.path_join("summary.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(sum, "\t"))
		f.close()
	print("PLAYBOT %s secs=%d screens=%d fields=%d outings=%d kills=%d deaths=%d coin=%d fps_p50=%.1f frame_ms_p99=%.1f hitches_50ms=%d errors=%d km_walked=%.2f%s" % [
		"ok" if ok else "FAILED", roundi(_elapsed()), _screens.size(), _fields, _outings.size(), _kills, _deaths, _coin, fps50, p99, _hitch50, errors, km,
		"" if ok else " why=\"%s\"" % _failed_why])
	if _shell != null and is_instance_valid(_shell):
		_shell.link.close()
	await create_timer(0.3).timeout
	quit(0 if ok else 1)

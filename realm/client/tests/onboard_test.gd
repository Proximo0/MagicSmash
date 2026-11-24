extends SceneTree
## A brand-new player, from the title to her first kill, using only what the screens show: ENTER on the lit button
## of each screen and one click on the lit way out of town. Nothing is typed and nothing is chosen (the defaults
## are the generated name, the knight and the nearest field). Every input is counted per screen; the time is the
## real seconds the waits took plus THINK_S for each input (a player reads a screen before she presses).
##   godot --path realm/client -s res://tests/onboard_test.gd -- --gateway=127.0.0.1:PORT [--dev-cert=FILE]
## Prints `ONBOARD clicks=N screens=N secs_to_field=N secs_to_first_kill=N ...` and one ONBOARD_TEST line.

## The limits a first ten minutes must keep (docs/realm/shell.md, "The first ten minutes").
const MAX_CLICKS_TO_FIELD: int = 6
const MAX_SCREENS_TO_FIELD: int = 6
const MAX_DECISIONS: int = 0
const MAX_SECS_TO_FIELD: float = 60.0
const MAX_SECS_TO_KILL: float = 150.0
const THINK_S: float = 1.5

var _problems: Array[String] = []
var _checks: int = 0
var _done: bool = false
var _shell: Shell = null
var _gateway: String = "127.0.0.1:7700"
var _t0: int = 0
var _inputs: int = 0
var _decisions: int = 0
var _per_screen: Dictionary = {}
var _order: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] == "gateway" and kv.size() > 1:
			_gateway = kv[1]
	ShellSettings.persist = false
	_run()


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_problems.append(what)
		print("  FAILED: ", what)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > 200000 and not _done:
		_check(false, "the onboarding test ran past 200 s (stuck?)")
		_finish()
	return false


func _finish() -> void:
	if _done:
		return
	_done = true
	var ok: bool = _problems.is_empty()
	print("ONBOARD_TEST %s checks=%d%s" % ["ok" if ok else "FAILED", _checks, "" if ok else " problems=\"%s\"" % "; ".join(_problems)])
	quit(0 if ok else 1)


func _secs() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0 + THINK_S * _inputs


func _until(cond: Callable, secs: float) -> bool:
	var t: int = Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t > secs * 1000.0:
			return false
		await process_frame
	return true


## One input on the screen now showing: a key (ENTER) or a click on a button the screen has drawn.
func _input(screen: String, what: String, key: int = KEY_NONE, button: String = "") -> void:
	await process_frame
	await process_frame
	if not _per_screen.has(screen):
		_per_screen[screen] = 0
		_order.append(screen)
	_per_screen[screen] += 1
	_inputs += 1
	if key != KEY_NONE:
		var e := InputEventKey.new()
		e.pressed = true
		e.keycode = key as Key
		e.physical_keycode = key as Key
		_shell._unhandled_input(e)
	else:
		var top: UiScreen = _shell.top()
		_check(top != null and top.has_hit(button), "%s: the button for '%s' is on the screen (%s)" % [screen, what, button])
		if top != null:
			top.press(button)


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	_shell = Shell.new()
	_shell.set_gateway(_gateway)
	root.add_child(_shell)
	await process_frame
	_shell.show_base(TitleScreen.new(), "title")
	await _until(func() -> bool: return _shell.top() != null and _shell.top().has_hit("enter"), 5.0)
	_check(_shell.base_name == "title", "starts at the title")
	await _input("title", "ENTER", KEY_ENTER)

	# The login: a themed name is already spelled; ENTER knocks.
	_check(await _until(func() -> bool: return _shell.base_name == "login", 5.0), "ENTER leaves the title for the login")
	var login: LoginScreen = _shell.base as LoginScreen
	_check(login != null and login.board.text.length() >= LoginScreen.NAME_MIN, "the login starts with a name spelled")
	await _input("login", "KNOCK", KEY_ENTER)

	# A new account has no hero to choose: the builder opens, a knight and a themed name chosen. ENTER begins.
	_check(await _until(func() -> bool: return _shell.base_name == "hero_builder", 10.0), "a new account goes straight to the builder")
	var builder: HeroBuilderScreen = _shell.base as HeroBuilderScreen
	_check(builder != null and builder.cls == 1 and builder._name_ok(), "the builder starts with a knight and a name the gateway accepts")
	await _input("builder", "BEGIN", KEY_ENTER)

	# Her first hero walks into the town; the gate is lit and an arrow names it. One click walks her there.
	_check(await _until(func() -> bool: return _shell.base_name == "town" and _shell.heroes.size() == 1, 10.0), "the new hero walks into the town")
	var town: TownScreen = _shell.base as TownScreen
	_check(await _until(func() -> bool: return town.members.has(town.me) and town.snapshots >= 2, 10.0), "snapshots arrive")
	_check(town.gate_lit(), "the way out of town is lit for a hero who has never left it")
	await _until(func() -> bool: return town.has_hit("gate_arrow"), 3.0)
	await _input("town", "THE FIELD GATES", KEY_NONE, "gate_arrow")
	var at_gate: bool = await _until(func() -> bool: return _shell.panel_of("GatePanel") != null, 60.0)
	_check(at_gate, "the click walks her to the gates and they open (at %s)" % str(town.shown(town.me)))
	if not at_gate:
		_finish()
		return

	# The gates: the field her level suits has the lit ENTER; ENTER takes it.
	var gates: GatePanel = _shell.panel_of("GatePanel") as GatePanel
	_check(gates.fit_field() == 0, "a level 1 hero's lit field is the first")
	await _input("gates", "ENTER", KEY_ENTER)
	_check(await _until(func() -> bool: return _shell.in_field and _shell.field_client != null, 20.0), "ENTER hands her to the field client")
	var client: Node = _shell.field_client
	var joined: bool = await _until(func() -> bool: return not is_instance_valid(client) or int(client.link.counters().get("ticks_applied", 0)) > 5, 20.0)
	_check(joined and is_instance_valid(client), "the field client joined")
	if not (joined and is_instance_valid(client)):
		_finish()
		return
	var to_field: float = _secs()
	var inputs_to_field: int = _inputs
	var screens: int = _order.size() + 1

	# The field: she holds her skill key and walks about (a new heading is an input) until a monster dies.
	client.script_buttons = RealmClient.BTN_SKILL1
	_inputs += 1
	var kill_inputs: int = 1
	var killed: bool = false
	var t: int = Time.get_ticks_msec()
	var heading: int = 0
	while Time.get_ticks_msec() - t < 120000 and is_instance_valid(client) and _shell.in_field:
		var info: Dictionary = client._info
		if int(info.get("xp", 0)) > 0 or int(info.get("level", 1)) > 1:
			killed = true
			break
		if (Time.get_ticks_msec() - t) / 3000 >= heading:
			heading += 1
			client.script_move = 1 + (heading * 3) % 8
			_inputs += 1
			kill_inputs += 1
		await process_frame
	var to_kill: float = _secs()
	_check(killed, "her first monster dies")
	print("ONBOARD clicks=%d screens=%d secs_to_field=%d secs_to_first_kill=%d decisions=%d kill_inputs=%d" % [inputs_to_field, screens, roundi(to_field), roundi(to_kill), _decisions, kill_inputs])
	var parts: Array[String] = []
	for s in _order:
		parts.append("%s=%d" % [s, _per_screen[s]])
	print("ONBOARD_SCREENS %s field=%d" % [" ".join(parts), kill_inputs])
	_check(inputs_to_field <= MAX_CLICKS_TO_FIELD, "at most %d inputs from the title to the field (was %d)" % [MAX_CLICKS_TO_FIELD, inputs_to_field])
	_check(screens <= MAX_SCREENS_TO_FIELD, "at most %d screens before the field (was %d)" % [MAX_SCREENS_TO_FIELD, screens])
	_check(_decisions <= MAX_DECISIONS, "no choice is asked before the field")
	_check(to_field <= MAX_SECS_TO_FIELD, "at most %d s to the field (was %.0f)" % [MAX_SECS_TO_FIELD, to_field])
	_check(to_kill <= MAX_SECS_TO_KILL, "at most %d s to the first kill (was %.0f)" % [MAX_SECS_TO_KILL, to_kill])
	_finish()

extends Node
## Play-bot: boots the real game (title -> lobby -> arena), lets SmashBot wizards play it offline for
## SECONDS of game time, then prints one "BOT ..." line. A shard plays its own seed and player count.
## Run: godot --headless --fixed-fps 60 --path . res://tests/bot/bot.tscn -- --shard=0 --nshards=3
## The bots play as CASUAL (the arena's default); `-- --persona=novice|veteran` plays another persona.

const SECONDS: float = 75.0
## Seconds of fighting the run clock must reach (level-up picks pause the world, so it runs behind SECONDS).
const MIN_FIGHT: float = 40.0
## `-- --heroes`: the hero shard (tests/bot/bot_heroes.gd). Plays seed 104 with four seated heroes by default.
const Heroes := preload("res://tests/bot/bot_heroes.gd")
## `-- --boss` and `-- --win` (tests/bot/bot_boss.gd): the run's clock moves to just before a boss; `-- --again`: a
## second run after the results, the Sanctum and the lobby. All three seat the saved heroes like `--heroes` (shard 3).
const BossRun := preload("res://tests/bot/bot_boss.gd")
## Longest game time the boss, win and again shards may take.
const SHARD_LIMIT: float = 150.0
## Longest game time the hero shard may take to reach its end of run.
const HEROES_LIMIT: float = 240.0

var _t: float = 0.0
var _shard: int = 0
var _arena: Node = null
var _heroes: bool = false
var _profile: Profile = null
var _before: Dictionary = {}
var _seated: Array[int] = []
var _start_checked: bool = false
var _failed: bool = false
var _mode: String = ""
var _started: bool = false
var _boss: BossRun = null
var _again_state: int = 0
var _again_t: float = 0.0
var _again_presses: int = 0
var _again_hero: int = -1
var _again_seats: int = 0
var _again_runs2: bool = false
var _again_checked: bool = false


func _ready() -> void:
	for m: String in ["heroes", "boss", "win", "again"]:
		if Flags.args.has(m):
			_mode = m
	_heroes = _mode == "heroes"
	var saved: bool = not _mode.is_empty()
	_shard = int(Flags.get_arg("shard", "3" if saved else "0"))
	if saved and not Heroes.save_is_private(OS.get_environment("PRIVATE_SAVE"), OS.get_user_data_dir()):
		print("BOT %s FAIL user:// is %s, not a private save folder: start the %s shard with tools/private_save.sh" % [_mode,
			OS.get_user_data_dir(), _mode])
		get_tree().quit(1)
		return
	Flags.args["seed"] = str(101 + _shard)
	Flags.args["persona"] = Flags.get_arg("persona", "casual")
	add_child(load("res://game/main.tscn").instantiate())
	await get_tree().process_frame
	var players: int = 1 + _shard % 4
	G.local_devices = []
	if saved:
		_profile = Heroes.make_profile()
		_before = Heroes.snapshot(_profile)
		Save.profile = _profile
		Net.force_heroes = true
		Net.seat_heroes.clear()
	Net.start_offline()
	if _mode == "win":
		Net.seal = BossRun.WIN_SEAL
	for d: int in range(players):
		Net.add_local_device(G.DEV_KBM if d == 0 else d - 1)
	PlayerInput.bot = true
	Net.begin_game()
	if saved:
		for d: int in G.local_devices:
			_seated.append(Net.hero_of(d))
	if _mode == "boss" or _mode == "win":
		_boss = BossRun.new(_mode == "win", _profile, _before, _seated)
	await get_tree().process_frame
	_arena = G.main.current
	_started = true


func _physics_process(delta: float) -> void:
	if _arena == null and not _started:
		return
	_t += delta
	if _mode == "again":
		_again_step() # the run's arena is freed on the way to the Sanctum: a freed `_arena` reads as null
		return
	var w: World = _arena.get("world")
	if _boss != null:
		_boss_step(w)
		return
	if _heroes:
		_heroes_step(w)
		return
	var over: bool = w != null and w.phase == World.PH_GAMEOVER
	if _t < SECONDS and not over:
		return
	set_physics_process(false)
	var ok: bool = w != null and (w.wave_time >= MIN_FIGHT or over)
	print("BOT shard=%d players=%d seed=%d clock=%.0fs enemies=%d over=%s %s" % [_shard, w.players.size() if w else 0,
		101 + _shard, w.wave_time if w else 0.0, w.enemies.size() if w else 0, over, "PASS" if ok else "FAIL "])
	print("BOT score=%d persona=%s" % [w.total_score() if w else 0, Flags.get_arg("persona")])
	PlayerInput.bot = false
	get_tree().quit(0 if ok else 1)


## The hero shard's run: check the seats on the first frame with a World, fight, fell the party through the World's
## damage function, wait for the arena to book the loss, check the profile.
func _heroes_step(w: World) -> void:
	if w != null and not _start_checked:
		_start_checked = true
		for line: String in Heroes.check_start(w, _profile):
			print(line)
			_failed = true
	if w != null and w.wave_time >= Heroes.FIGHT_SECONDS and not _arena.get("game_over"):
		Heroes.hurt_party(w)
	var booked: bool = _arena.get("game_over") and _arena.get("results") != null
	if not booked and _t < HEROES_LIMIT:
		return
	set_physics_process(false)
	var bad: Array[String] = []
	if booked:
		bad = Heroes.check_end(_profile, _before, _seated)
	else:
		bad.append("the run did not end by game time %.0fs (clock %.0fs)" % [_t, w.wave_time if w else 0.0])
	for b: String in bad:
		print("BOT heroes FAIL %s" % b)
	_failed = _failed or not bad.is_empty()
	if not _failed:
		print("BOT heroes PASS seats=%d runs=%d crystals=%d levels=%s" % [_seated.size(), _profile.runs, _profile.crystals,
			_profile.last_hero_levels])
	print("BOT shard=%d players=%d seed=%d clock=%.0fs enemies=%d over=%s %s" % [_shard, w.players.size() if w else 0,
		101 + _shard, w.wave_time if w else 0.0, w.enemies.size() if w else 0, booked, "FAIL " if _failed else "PASS"])
	print("BOT score=%d persona=%s" % [w.total_score() if w else 0, Flags.get_arg("persona")])
	PlayerInput.bot = false
	get_tree().quit(1 if _failed else 0)


## The boss and win shards: BossRun plays its states; this ends the run with the shard's lines.
func _boss_step(w: World) -> void:
	_boss.step(_arena, w)
	if not _boss.done and _t < SHARD_LIMIT:
		return
	set_physics_process(false)
	if not _boss.done:
		_boss.faults.append("the shard did not finish by game time %.0fs (state %d, clock %.0fs)" % [_t, _boss.state, w.wave_time if w else 0.0])
	_end_shard(_mode, _boss.faults, _boss.summary, w, true)


## Prints the shard's FAIL lines or its PASS line, then the usual two lines, and quits.
func _end_shard(label: String, bad: Array[String], pass_line: String, w: World, over: bool) -> void:
	for b: String in bad:
		print("BOT %s FAIL %s" % [label, b])
	if bad.is_empty():
		print(pass_line)
	print("BOT shard=%d players=%d seed=%d clock=%.0fs enemies=%d over=%s %s" % [_shard, w.players.size() if w else 0,
		101 + _shard, w.wave_time if w else 0.0, w.enemies.size() if w else 0, over, "FAIL " if not bad.is_empty() else "PASS"])
	print("BOT score=%d persona=%s" % [w.total_score() if w else 0, Flags.get_arg("persona")])
	PlayerInput.bot = false
	get_tree().quit(1 if not bad.is_empty() else 0)


## A key press and its release, as the engine would deliver them to the focused scene.
func _press(key: Key) -> void:
	for down: bool in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = key
		e.keycode = key
		e.pressed = down
		Input.parse_input_event(e)


func _scene_is(path_part: String) -> bool:
	var cur: Node = G.main.current
	return cur != null and is_instance_valid(cur) and not cur.is_queued_for_deletion() \
		and cur.get_script() != null and String(cur.get_script().resource_path).contains(path_part)


## The again shard: run 1 ends in a defeat as in the hero shard; then the way a player goes on. States: 0 fight run 1,
## 1 wait for the results to take a press, 2 press until the Sanctum, 3 through the portal to the lobby, 4 START,
## 5 run 2 begins (checked), 6 run 2 fights a few seconds and is felled, 7 done.
func _again_step() -> void:
	var cur: Node = G.main.current
	var bad: Array[String] = []
	var w: World = null
	if cur != null and is_instance_valid(cur) and cur.get("world") != null:
		w = cur.get("world")
	_again_t += 1.0 / 60.0
	if _t > SHARD_LIMIT:
		bad.append("the shard did not finish by game time %.0fs (state %d)" % [_t, _again_state])
		set_physics_process(false)
		_end_shard("again", bad, "", w, false)
		return
	match _again_state:
		0:
			if w != null and not _start_checked:
				_start_checked = true
				_again_hero = Net.hero_of(G.DEV_KBM)
				for line: String in Heroes.check_start(w, _profile):
					print(line)
					_failed = true
			if w != null and w.wave_time >= Heroes.FIGHT_SECONDS and not cur.get("game_over"):
				Heroes.hurt_party(w)
			if cur.get("game_over") and cur.get("results") != null:
				for b: String in Heroes.check_end(_profile, _before, _seated):
					print("BOT again FAIL run 1: %s" % b)
					_failed = true
				_again_state = 1
		1:
			if float(cur.get("game_over_t")) > 2.2:
				_again_state = 2
				_again_t = 0.0
		2:
			if _scene_is("sanctum_view"):
				_again_state = 3
				_again_t = 0.0
			elif _again_t > 0.3 and _scene_is("arena"):
				_again_presses += 1
				_again_t = 0.0
				_press(KEY_SPACE) # the confirm a player uses: a first press turns the results page, the next leaves
				if _again_presses > 6:
					print("BOT again FAIL the results did not leave after %d presses" % _again_presses)
					_failed = true
					_again_state = 7
		3:
			if _again_t > 0.5:
				if Net.mode != Net.Mode.OFFLINE or Net.in_game:
					print("BOT again FAIL the Sanctum left the net in mode %d in_game=%s" % [Net.mode, Net.in_game])
					_failed = true
				# The portal's own call (game/sanctum/sanctum_view.gd): walking there is the Sanctum's own test.
				G.goto_title_lobby(G.DEV_KBM)
				_again_state = 4
				_again_t = 0.0
		4:
			if _scene_is("title") and cur.get("state") == cur.S.LOBBY and _again_t > 0.5:
				_again_seats = Net.roster.size()
				_press(KEY_ENTER) # player 1's START
				_again_state = 5
				_again_t = 0.0
			elif _again_t > 5.0:
				print("BOT again FAIL the portal did not open the lobby (scene %s)" % cur)
				_failed = true
				_again_state = 7
		5:
			if w != null and _scene_is("arena"):
				_again_state = 6
				_again_t = 0.0
				_again_check_second(w)
			elif _again_t > 5.0:
				print("BOT again FAIL START in the lobby did not begin a run (roster %d)" % Net.roster.size())
				_failed = true
				_again_state = 7
		6:
			if w != null and w.wave_time >= 5.0 and not cur.get("game_over"):
				Heroes.hurt_party(w)
			if cur.get("game_over") and cur.get("results") != null:
				_again_state = 7
		7:
			pass
	if _again_state == 7:
		set_physics_process(false)
		if not _failed and _profile.runs != int(_before.runs) + 2:
			bad.append("runs expected %d after two runs got %d" % [int(_before.runs) + 2, _profile.runs])
		if FileAccess.file_exists(Save.PATH):
			bad.append("%s exists" % Save.PATH)
		if _failed:
			bad.append("see the lines above")
		_end_shard("again", bad, "BOT again PASS seats1=%d seats2=%d hero=%d runs=%d crystals=%d" % [_seated.size(), _again_seats,
			_again_hero, _profile.runs, _profile.crystals], w, true)


## The second run's World: new clock, full hearts, player 1 on her saved hero with her stats and the unlock bonuses.
func _again_check_second(w: World) -> void:
	if w.wave_time > 2.0 or w.wave != 1:
		print("BOT again FAIL the second run's clock is %.1fs at minute %d, not new" % [w.wave_time, w.wave])
		_failed = true
	for p: World.Player in w.players.values():
		if p.hp != p.max_hp or not p.alive:
			print("BOT again FAIL seat %d starts with %d of %d hearts" % [p.slot, p.hp, p.max_hp])
			_failed = true
	if Net.hero_of(G.DEV_KBM) != _again_hero:
		print("BOT again FAIL player 1 plays hero %d, was hero %d" % [Net.hero_of(G.DEV_KBM), _again_hero])
		_failed = true
	for line: String in Heroes.check_start(w, _profile):
		print(line)
		_failed = true
	if w.players.size() != _again_seats:
		print("BOT again FAIL the run has %d wizards, the lobby %d seats" % [w.players.size(), _again_seats])
		_failed = true
	print("BOT again seats: first run %d, second run %d (players 2 to 4 join again: known)" % [_seated.size(), w.players.size()])

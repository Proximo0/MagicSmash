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


func _ready() -> void:
	_heroes = Flags.args.has("heroes")
	_shard = int(Flags.get_arg("shard", "3" if _heroes else "0"))
	if _heroes and OS.get_environment("XDG_DATA_HOME").is_empty():
		print("BOT heroes FAIL XDG_DATA_HOME is not set: the hero shard needs a private save folder")
		get_tree().quit(1)
		return
	Flags.args["seed"] = str(101 + _shard)
	Flags.args["persona"] = Flags.get_arg("persona", "casual")
	add_child(load("res://game/main.tscn").instantiate())
	await get_tree().process_frame
	var players: int = 1 + _shard % 4
	G.local_devices = []
	if _heroes:
		_profile = Heroes.make_profile()
		_before = Heroes.snapshot(_profile)
		Save.profile = _profile
		Net.force_heroes = true
		Net.seat_heroes.clear()
	Net.start_offline()
	for d: int in range(players):
		Net.add_local_device(G.DEV_KBM if d == 0 else d - 1)
	PlayerInput.bot = true
	Net.begin_game()
	if _heroes:
		for d: int in G.local_devices:
			_seated.append(Net.hero_of(d))
	await get_tree().process_frame
	_arena = G.main.current


func _physics_process(delta: float) -> void:
	if _arena == null:
		return
	_t += delta
	var w: World = _arena.get("world")
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

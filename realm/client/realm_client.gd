class_name RealmClient
extends Node2D
## HORDE & HEARTH's realm client: a lockstep player. The native module (RealmLink, realm/godot) holds the
## socket and the whole field, simulated from every player's inputs with the server's hash checked; this
## script sends the player's input 20 times a second, draws the predicted hero at once and the horde gliding
## between the 20 ticks a second, and shows the HUD.
## The simulation runs on a worker thread inside the module: this script draws the newest finished frame, so
## a slow tick never stalls a frame. The field's pieces are in field/: FieldArt (pictures by file name, with
## stand-ins), FieldHud, FieldFx (skills and effects), FieldWorld, FieldSound.
## godot --path realm/client -- [--server=127.0.0.1:7777] [--class=0..4] [--race=0..3] [--zoom=N] [--bot]
##   [--window=1440x810] [--shots=DIR --secs=N [--zooms=1,2,4]] [--debug=0|1] [--mute] [--fake=tide,boss]
## A scripted run (--shots) plays as the bot, records each zoom (--zooms, by default 1, 2, 4 and --zoom) for
## --secs seconds, saves DIR/zoom<N>.png and DIR/stats.json, prints one CLIENT_FRAMES line and quits (exit 1
## if it never joined or a hash check failed). --zoom=8 at 1440x810 shows 3 840 x 2 160 px of the field: a
## whole rally's horde.
## Keys: arrows or WASD move; Space skill 1, E skill 2, R the ultimate (held); F interact (hold to bank);
## 4 5 6 potions; Z X C V or a click pick the offered card; 1 / 2 / 3 zoom 1 / 2 / 4; F3 the numbers; Esc quits.

const TICK_S: float = 0.05
## The HELLO's class 0..4 joins as KNIGHT..PALADIN (the core's classes 1..5; 0 is the NOVICE).
const CLASS_COUNT: int = 5
const RACE_COUNT: int = 4
## Button bits of RealmLink.send_input.
const BTN_SKILL1: int = 1
const BTN_SKILL2: int = 2
const BTN_ULT: int = 4
const BTN_INTERACT: int = 8
const BTN_POTION_SHIFT: int = 4
const KEY_ZOOMS: Array[int] = [1, 2, 4]
const MAX_ZOOM: int = 32
## The project's base size: zoom 1 shows this much of the field.
const BASE: Vector2 = Vector2(480, 270)
## The read rectangle reaches this far (px) past the screen, for figures walking in before the next tick.
const READ_MARGIN_PX: float = 96.0
## Input ticks owed after a long frame are all sent, up to this many; beyond it they are forgiven.
const INPUT_CATCH_UP: int = 4
const HUD_EVERY_S: float = 0.25
const SETTLE_S: float = 1.5
## A scripted run starts recording once this many ticks have been applied (or after JOIN_MAX_S).
const JOIN_TICKS: int = 40
const JOIN_MAX_S: float = 30.0
## A correction bigger than this (px) is a teleport (a fall, a respawn): the hero snaps instead of gliding.
const SNAP_PX: float = 48.0
const BG: Color = Color(0.055, 0.05, 0.075)
## The bot drinks the first potion under this share of health, at most every BOT_POTION_GAP_S.
const BOT_POTION_UNDER: float = 0.5
const BOT_POTION_GAP_S: float = 4.0

var link: RealmLink = RealmLink.new()

var _host: String = "127.0.0.1"
var _port: int = 7777
var _hero_class: int = 0
var _race: int = 0
var _bot: bool = false
var _zoom: int = 1
var _extra_zoom: int = 0
var _shot_zooms: Array[int] = []
var _window: Vector2i = Vector2i(1440, 810)
var _shots_dir: String = ""
var _secs: float = 6.0
var _debug: bool = true
var _mute: bool = false
var _fake: PackedStringArray = PackedStringArray()

var _world: Node2D = Node2D.new()
var _camera: Camera2D = Camera2D.new()
var _ground: RealmLayer = RealmLayer.new()
var _sites: FieldWorld = FieldWorld.new()
var _fx_under: FieldFx = FieldFx.new()
var _fx_over: FieldFx = FieldFx.new()
var _hero: RealmLayer = RealmLayer.new()
var _monsters: RealmBatch
var _players: RealmBatch
var _hud: FieldHud = FieldHud.new()
var _sound: FieldSound = FieldSound.new()
var _art: Dictionary = {}

var _t0_us: int = 0
var _input_acc: float = 0.0
var _move: int = 0
var _buttons: int = 0
## Presses that are sent once: potions (bits) and the card picked (1..4).
var _potion_latch: int = 0
var _pick_latch: int = 0
var _bot_potion_at: float = -100.0
var _hero_ready: bool = false
var _hero_from: Vector2 = Vector2.ZERO
var _hero_to: Vector2 = Vector2.ZERO
var _hero_t: float = 0.0
var _pose_version: int = -1
var _fill_t: float = 0.0
var _hud_t: float = 0.0
var _info: Dictionary = {}
var _world_info: Dictionary = {}
var _last_health: int = 0
var _hero_key: int = -1
var _debug_text: String = ""

# Per-frame measurements: poll (taking the newest frame), the drawing reads (the buffers, on frames after a
# tick), and the whole of _process.
var _poll_ms: float = 0.0
var _read_ms: float = 0.0
var _script_ms: float = 0.0
var _fps: float = 0.0
var _rec: bool = false
var _rec_frames: PackedFloat32Array = PackedFloat32Array()
var _rec_poll: PackedFloat32Array = PackedFloat32Array()
var _rec_read: PackedFloat32Array = PackedFloat32Array()
var _rec_script: PackedFloat32Array = PackedFloat32Array()
var _rec_monsters: PackedInt32Array = PackedInt32Array()
var _rec_players: PackedInt32Array = PackedInt32Array()
var _rec_fx: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	_parse_args()
	get_window().size = _window
	RenderingServer.set_default_clear_color(BG)
	_t0_us = Time.get_ticks_usec()
	add_child(_world)
	_ground.is_ground = true
	_world.add_child(_ground)
	_world.add_child(_sites)
	_fx_under.under_figures = true
	_fx_under.z_index = 0
	_world.add_child(_fx_under)
	var kinds: Array[Dictionary] = FieldArt.monster_entries()
	_monsters = RealmBatch.new(_world, kinds, 1)
	var heroes: Array[Dictionary] = FieldArt.hero_entries()
	_players = RealmBatch.new(_world, heroes, 2)
	_art = {"monsters": FieldArt.art_summary(kinds), "heroes": FieldArt.art_summary(heroes)}
	_hero.is_ground = false
	_hero.z_index = 3
	_hero.hero_entry = FieldArt.hero_entry(_hero_class + 1, _race)
	_world.add_child(_hero)
	_fx_over.z_index = 4
	_world.add_child(_fx_over)
	_world.add_child(_camera)
	_camera.make_current()
	_sound.muted = _mute
	add_child(_sound)
	_build_hud()
	if not link.connect_to_host(_host, _port, _hero_class, _race):
		push_error("cannot open %s:%d" % [_host, _port])
	_apply_zoom(_zoom)
	if not _shots_dir.is_empty():
		_scripted()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v: String = kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"server":
				var hp := v.split(":")
				_host = hp[0]
				if hp.size() > 1:
					_port = int(hp[1])
			"class":
				_hero_class = clampi(int(v), 0, CLASS_COUNT - 1)
			"race":
				_race = clampi(int(v), 0, RACE_COUNT - 1)
			"zoom":
				_zoom = clampi(int(v), 1, MAX_ZOOM)
				_extra_zoom = _zoom if not KEY_ZOOMS.has(_zoom) else 0
			"zooms":
				for z in v.split(","):
					_shot_zooms.append(clampi(int(z), 1, MAX_ZOOM))
			"bot":
				_bot = true
			"window":
				var wh := v.split("x")
				if wh.size() == 2:
					_window = Vector2i(maxi(int(wh[0]), 480), maxi(int(wh[1]), 270))
			"shots":
				_shots_dir = v
			"secs":
				_secs = maxf(float(v), 1.0)
			"debug":
				_debug = v != "0"
			"mute":
				_mute = true
			"fake":
				_fake = v.split(",")


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud.show_debug = _debug
	_hud.fake_tide = _fake.has("tide")
	_hud.fake_boss = _fake.has("boss")
	layer.add_child(_hud)


func _now() -> float:
	return (Time.get_ticks_usec() - _t0_us) / 1000000.0


func _apply_zoom(z: int) -> void:
	_zoom = z
	_camera.zoom = Vector2.ONE / float(z)
	var smooth: bool = _screen_px_per_field_px() < 1.0
	_monsters.set_smooth(smooth)
	_players.set_smooth(smooth)


func _screen_px_per_field_px() -> float:
	return get_viewport().get_final_transform().x.x / float(_zoom)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_1:
				_apply_zoom(KEY_ZOOMS[0])
			KEY_2:
				_apply_zoom(KEY_ZOOMS[1])
			KEY_3:
				_apply_zoom(KEY_ZOOMS[2])
			KEY_4:
				_potion_latch |= 1
			KEY_5:
				_potion_latch |= 2
			KEY_6:
				_potion_latch |= 4
			KEY_Z:
				_pick_latch = 1
			KEY_X:
				_pick_latch = 2
			KEY_C:
				_pick_latch = 3
			KEY_V:
				_pick_latch = 4
			KEY_F3:
				_debug = not _debug
				_hud.show_debug = _debug
			KEY_ESCAPE:
				_quit(0)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		# The HUD is drawn in the 480 x 270 canvas; the click is in the window.
		var p: Vector2 = get_viewport().get_final_transform().affine_inverse() * e.position
		var i: int = _hud.card_at(p)
		if i >= 0:
			_pick_latch = _offer_slot(i)


## The offer's slot (1..4) of the i-th card drawn (empty slots are skipped when drawing).
func _offer_slot(i: int) -> int:
	var offer: PackedInt32Array = _info.get("offer", PackedInt32Array())
	var n: int = -1
	for s in offer.size():
		if offer[s] > 0:
			n += 1
			if n == i:
				return s + 1
	return 0


func _quit(code: int) -> void:
	link.close()
	get_tree().quit(code)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var now := _now()
	var applied: int = link.poll()
	var t1 := Time.get_ticks_usec()
	_follow_pose(now)
	_send_input(now, delta)
	var t2 := Time.get_ticks_usec()
	var hero := _hero_at(now)
	_set_view(hero)
	if applied > 0:
		_on_frame()
		_fill_t = now
	var t3 := Time.get_ticks_usec()
	_poll_ms = (t1 - t0) / 1000.0
	_read_ms = (t3 - t2) / 1000.0
	var blend: float = clampf((now - _fill_t) / TICK_S, 0.0, 1.0)
	_monsters.set_blend(blend)
	_players.set_blend(blend)
	_place(hero)
	_script_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if delta > 0.0:
		_fps = lerpf(_fps, 1.0 / delta, 0.05)
	if now - _hud_t >= HUD_EVERY_S:
		_hud_t = now
		_debug_text = _debug_lines()
	_hud.set_state(_info, _world_info, _debug_text)
	if _rec:
		_rec_frames.append(delta * 1000.0)
		_rec_poll.append(_poll_ms)
		_rec_read.append(_read_ms)
		_rec_script.append(_script_ms)
		_rec_monsters.append(_monsters.count)
		_rec_players.append(_players.count)
		_rec_fx.append(_fx_over.drawn_items)


## New ticks arrived: every figure on screen from the module's frame, the effects, the events, the HUD numbers.
func _on_frame() -> void:
	_info = link.hero_view()
	_world_info = link.world()
	_monsters.fill(link.monster_buffer())
	_players.fill(link.player_buffer())
	var rows: PackedFloat32Array = link.fx_rows()
	var ev: PackedInt32Array = link.event_rows()
	_fx_under.ingest(rows)
	_fx_over.my_id = link.hero_id()
	_fx_over.ingest(rows)
	_fx_over.events(ev)
	_sound.from_events(ev, link.hero_id())
	if not _info.is_empty():
		var hp: int = int(_info["health"])
		if hp < _last_health:
			_sound.hook("hit")
		_last_health = hp
	if _fake.has("tide") and not _world_info.is_empty():
		_world_info["tide"] = true


## The rectangle the worker should build draw buffers for: the screen around the hero and a margin.
func _set_view(hero: Vector2) -> void:
	var half: Vector2 = BASE * float(_zoom) / 2.0 + Vector2.ONE * READ_MARGIN_PX
	link.set_view(Rect2i(Vector2i(hero - half), Vector2i(half * 2.0)))


## A new target for the hero's glide whenever the worker predicted another step or corrected one.
func _follow_pose(now: float) -> void:
	var v: int = link.shown_version()
	if v == _pose_version:
		return
	_pose_version = v
	if not _hero_ready:
		if not link.is_joined() or link.hero_id() < 0:
			return
		_hero_ready = true
		_hero_from = link.shown_position()
		_hero_to = _hero_from
		_hero_t = now
		return
	var cur := _hero_at(now)
	var to: Vector2 = link.shown_position()
	_hero_from = to if cur.distance_to(to) > SNAP_PX else cur
	_hero_to = to
	_hero_t = now


## Sends one input per 50 ms of play (several after a long frame, so the server never runs out of them).
func _send_input(now: float, delta: float) -> void:
	_input_acc = minf(_input_acc + delta, TICK_S * INPUT_CATCH_UP)
	if _input_acc < TICK_S:
		return
	_read_keys(now)
	while _input_acc >= TICK_S:
		_input_acc -= TICK_S
		link.send_input(_move, _buttons | (_potion_latch << BTN_POTION_SHIFT), _pick_latch)
		# A potion or a pick is one press: sent with the first input only.
		_potion_latch = 0
		_pick_latch = 0


## The hero between the last two predictions, over one input tick.
func _hero_at(now: float) -> Vector2:
	if not _hero_ready:
		return Vector2(RealmLink.field_size(), RealmLink.field_size()) / 2.0
	return _hero_from.lerp(_hero_to, clampf((now - _hero_t) / TICK_S, 0.0, 1.0))


func _read_keys(now: float) -> void:
	if _bot:
		# A slow wander: eight headings, each held a few seconds; every skill whenever it is ready, the first
		# card offered, a healing potion when hurt.
		_move = 1 + (int(now / 3.0) * 3) % 8
		_buttons = BTN_SKILL1 | BTN_SKILL2 | BTN_ULT
		_bot_choices(now)
	else:
		var dx: int = int(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)) \
			- int(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
		var dy: int = int(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)) \
			- int(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W))
		_move = _dir_code(dx, dy)
		_buttons = (BTN_SKILL1 if Input.is_physical_key_pressed(KEY_SPACE) else 0) \
			| (BTN_SKILL2 if Input.is_physical_key_pressed(KEY_E) else 0) \
			| (BTN_ULT if Input.is_physical_key_pressed(KEY_R) else 0) \
			| (BTN_INTERACT if Input.is_physical_key_pressed(KEY_F) else 0)
	if _move in [4, 5, 6]:
		_hero.hero_flip = true
	elif _move in [1, 2, 8]:
		_hero.hero_flip = false


func _bot_choices(now: float) -> void:
	if _info.is_empty():
		return
	var offer: PackedInt32Array = _info["offer"]
	for s in offer.size():
		if offer[s] > 0:
			_pick_latch = s + 1
			break
	var frac: float = float(_info["health"]) / maxf(float(_info["max_health"]), 1.0)
	if frac < BOT_POTION_UNDER and now - _bot_potion_at > BOT_POTION_GAP_S:
		var belt: PackedInt32Array = _info["belt"]
		for slot in 3:
			if belt[slot * 3] == 0 and belt[slot * 3 + 1] > 0 and belt[slot * 3 + 2] == 0:
				_potion_latch |= 1 << slot
				_bot_potion_at = now
				break


## Direction 0..8 from a step of -1, 0, 1 each way: 1 E, 2 SE, 3 S, 4 SW, 5 W, 6 NW, 7 N, 8 NE.
static func _dir_code(dx: int, dy: int) -> int:
	const TABLE: Array[int] = [6, 7, 8, 5, 0, 1, 4, 3, 2]
	return TABLE[(dy + 1) * 3 + dx + 1]


func _place(hero: Vector2) -> void:
	var s: float = _screen_px_per_field_px()
	# Whole screen pixels, so the pixel art does not shimmer as the camera glides.
	_camera.position = (hero * s).round() / s
	var half: Vector2 = BASE * float(_zoom) / 2.0
	var view := Rect2(_camera.position - half, half * 2.0)
	_ground.view = view
	_ground.px_scale = s
	_ground.queue_redraw()
	_sites.view = view
	_sites.px_scale = s
	_sites.sites = _world_info.get("sites", PackedFloat32Array())
	_sites.tide = bool(_world_info.get("tide", false))
	_sites.banked_at = int(_info.get("waystone", 7)) if bool(_info.get("banked", false)) else -1
	_sites.queue_redraw()
	_fx_under.px_scale = s
	_fx_over.px_scale = s
	_hero.hero_pos = hero
	_hero.px_scale = s
	_hero.hero_alive = bool(_info.get("alive", true))
	_hero.hero_moving = _move != 0
	if not _info.is_empty():
		var key: int = int(_info["class"]) * RACE_COUNT + int(_info["race"])
		if key != _hero_key:
			_hero_key = key
			_hero.hero_entry = FieldArt.hero_entry(int(_info["class"]), int(_info["race"]))
	_hero.visible = _hero_ready
	_hero.queue_redraw()


func _debug_lines() -> String:
	var c: Dictionary = link.counters()
	var l: Array[String] = []
	if not link.is_joined():
		l.append("%s %s:%d" % ["DOWNLOADING THE FIELD FROM" if link.is_welcomed() else "CONNECTING TO", _host, _port])
	var h: String = String.num_uint64(link.confirmed_hash(), 16).lpad(16, "0").left(8)
	l.append("TICK %d  HASH %s" % [link.confirmed_tick(), h])
	l.append("PLAYERS %d  MONSTERS %d" % [link.player_count(), link.monster_count()])
	l.append("DRAWN %d  MONSTERS DRAWN %d" % [_monsters.count + _players.count + int(_hero_ready), _monsters.count])
	l.append("NET IN %.1f KB/S  OUT %.2f KB/S" % [float(c.get("bytes_in_per_sec", 0.0)) / 1000.0, float(c.get("bytes_out_per_sec", 0.0)) / 1000.0])
	l.append("HASH CHECKS OK %d  FAILED %d" % [int(c.get("hash_checks_passed", 0)), int(c.get("hash_checks_failed", 0))])
	l.append("SIM (WORKER) %.2f MS/TICK  BUILD %.2f" % [float(c.get("sim_ms_per_tick", 0.0)), float(c.get("frame_build_ms", 0.0))])
	l.append("TAKE %.2f  READ %.2f  SCRIPT %.2f MS" % [_poll_ms, _read_ms, _script_ms])
	l.append("FPS %d  ZOOM %d" % [roundi(_fps), _zoom])
	return "\n".join(l)


# ---- the scripted run ----

func _scripted() -> void:
	_bot = true
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	var t_wait: float = _now()
	while int(link.counters().get("ticks_applied", 0)) < JOIN_TICKS and _now() - t_wait < JOIN_MAX_S:
		await get_tree().process_frame
	var out := {
		"server": "%s:%d" % [_host, _port],
		"renderer": RenderingServer.get_video_adapter_name(),
		"window": "%dx%d" % [_window.x, _window.y],
		"art": _art,
		"zooms": {},
	}
	var zooms: Array[int] = _shot_zooms.duplicate()
	if zooms.is_empty():
		zooms = KEY_ZOOMS.duplicate()
		if _extra_zoom > 0:
			zooms.append(_extra_zoom)
	var worst_p99: float = 0.0
	var mean_ms: float = 0.0
	var drawn: int = 0
	for z in zooms:
		_apply_zoom(z)
		await get_tree().create_timer(SETTLE_S).timeout
		var before: Dictionary = link.counters()
		_rec_frames.clear()
		_rec_poll.clear()
		_rec_read.clear()
		_rec_script.clear()
		_rec_monsters.clear()
		_rec_players.clear()
		_rec_fx.clear()
		var t_rec: float = _now()
		_rec = true
		await get_tree().create_timer(_secs).timeout
		_rec = false
		var dur: float = _now() - t_rec
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/zoom%d.png" % [_shots_dir, z])
		var sm: Dictionary = _summary(dur, before, link.counters())
		out["zooms"][str(z)] = sm
		worst_p99 = maxf(worst_p99, float(sm.get("frame_ms_p99", 0.0)))
		mean_ms = _mean(_rec_frames)
		drawn = int(sm.get("monsters_drawn_mean", 0))
	var c: Dictionary = link.counters()
	for k in ["join_tick", "join_bytes", "ticks_applied", "hash_checks_passed", "hash_checks_failed", "stall_ms_max", "mispredicts", "predictions_checked", "bad_datagrams"]:
		out[k] = c.get(k, 0)
	out["players_in_field"] = link.player_count()
	out["monsters_in_field"] = link.monster_count()
	out["sounds_played"] = _sound.played
	var f := FileAccess.open(_shots_dir.path_join("stats.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
	var ok: bool = link.is_joined() and int(c.get("hash_checks_failed", 1)) == 0 and int(c.get("hash_checks_passed", 0)) > 0
	print("CLIENT_FRAMES %s zooms=%s mean_ms=%.2f p99_ms=%.2f monsters_drawn=%d renderer=\"%s\"" % ["ok" if ok else "FAILED", ",".join(PackedStringArray(zooms.map(func(x: int) -> String: return str(x)))), mean_ms, worst_p99, drawn, out["renderer"]])
	_quit(0 if ok else 1)


func _summary(dur: float, before: Dictionary, after: Dictionary) -> Dictionary:
	var n: int = _rec_frames.size()
	if n == 0:
		return {"frames": 0}
	var sorted := _rec_frames.duplicate()
	sorted.sort()
	var worst: int = maxi(1, n / 100)
	var worst_sum: float = 0.0
	for i in worst:
		worst_sum += sorted[n - 1 - i]
	return {
		"frames": n,
		"seconds": snappedf(dur, 0.01),
		"fps_mean": snappedf(n / dur, 0.1),
		"fps_slowest_1pct": snappedf(1000.0 / (worst_sum / worst), 0.1),
		"frame_ms_mean": snappedf(_mean(_rec_frames), 0.01),
		"frame_ms_median": snappedf(sorted[n / 2], 0.01),
		"frame_ms_p99": snappedf(sorted[mini(n - 1, n * 99 / 100)], 0.01),
		"poll_ms_mean": snappedf(_mean(_rec_poll), 0.001),
		"read_ms_mean": snappedf(_mean(_rec_read), 0.001),
		"read_ms_p99": snappedf(_p99(_rec_read), 0.001),
		"script_ms_mean": snappedf(_mean(_rec_script), 0.001),
		"script_ms_p99": snappedf(_p99(_rec_script), 0.001),
		"monsters_drawn_mean": roundi(_mean_i(_rec_monsters)),
		"monsters_drawn_max": _max_i(_rec_monsters),
		"players_drawn_mean": roundi(_mean_i(_rec_players)),
		"effects_alive_mean": roundi(_mean_i(_rec_fx)),
		"sim_ms_per_tick": snappedf(float(after.get("sim_ms_per_tick", 0.0)), 0.01),
		"frame_build_ms": snappedf(float(after.get("frame_build_ms", 0.0)), 0.01),
		"bytes_in_per_sec": roundi(float(after.get("bytes_in_per_sec", 0.0))),
		"bytes_out_per_sec": roundi(float(after.get("bytes_out_per_sec", 0.0))),
		"ticks_applied": int(after.get("ticks_applied", 0)) - int(before.get("ticks_applied", 0)),
		"hash_checks_passed": int(after.get("hash_checks_passed", 0)) - int(before.get("hash_checks_passed", 0)),
		"hash_checks_failed": int(after.get("hash_checks_failed", 0)) - int(before.get("hash_checks_failed", 0)),
	}


func _mean(a: PackedFloat32Array) -> float:
	var s: float = 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1.0)


func _mean_i(a: PackedInt32Array) -> float:
	var s: float = 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1.0)


func _max_i(a: PackedInt32Array) -> int:
	var m: int = 0
	for v in a:
		m = maxi(m, v)
	return m


func _p99(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[mini(s.size() - 1, s.size() * 99 / 100)]

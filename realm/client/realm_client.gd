class_name RealmClient
extends Node2D
## HORDE & HEARTH's realm client: a lockstep player. The native module (RealmLink, realm/godot) holds the
## socket and the whole field, simulated here from every player's inputs with the server's hash checked;
## this script sends the player's input 20 times a second, draws the predicted hero at once and the horde
## gliding between the 20 ticks a second, and shows the counters.
## godot --path realm/client -- [--server=127.0.0.1:7777] [--class=0..4] [--race=0..3] [--zoom=N] [--bot]
##   [--window=1440x810] [--shots=DIR --secs=N [--zooms=1,2,4]]
## A scripted run (--shots) plays as the bot, records each zoom (--zooms, by default 1, 2, 4 and --zoom) for
## --secs seconds, saves DIR/zoom<N>.png and DIR/stats.json, and quits (exit 1 if it never joined or a hash
## check failed). --zoom=8 at 1440x810 shows 3 840 x 2 160 px of the field: a whole rally's horde.
## Keys: arrows or WASD move, space the skill, 1 / 2 / 3 zoom 1 / 2 / 4, Esc quits.

const TICK_S: float = 0.05
const CLASSES: Array[String] = ["knight", "mage", "archer", "priest", "paladin"]
const RACES: Array[String] = ["human", "elf", "dwarf", "orc"]
## In the module's atlas frame order (monster kind 0..7).
const KINDS: Array[String] = ["bloat", "coffin", "guard", "cinderling", "censor", "hound", "shard", "swords"]
const KEY_ZOOMS: Array[int] = [1, 2, 4]
const MAX_ZOOM: int = 32
## The project's base size: zoom 1 shows this much of the field.
const BASE: Vector2 = Vector2(480, 270)
## The read rectangle reaches this far (px) past the screen, for figures walking in before the next tick.
const READ_MARGIN_PX: float = 64.0
## Input ticks owed after a long frame are all sent, up to this many; beyond it they are forgiven.
const INPUT_CATCH_UP: int = 4
const HUD_EVERY_S: float = 0.25
const SETTLE_S: float = 1.5
## A scripted run starts recording once this many ticks have been applied (or after JOIN_MAX_S).
const JOIN_TICKS: int = 40
const JOIN_MAX_S: float = 30.0
const BG: Color = Color(0.055, 0.05, 0.075)

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

var _world: Node2D = Node2D.new()
var _camera: Camera2D = Camera2D.new()
var _ground: RealmLayer = RealmLayer.new()
var _hero: RealmLayer = RealmLayer.new()
var _monsters: RealmBatch
var _players: RealmBatch
var _hud: Label = Label.new()

var _t0_us: int = 0
var _input_acc: float = 0.0
var _move: int = 0
var _skill: bool = false
var _hero_ready: bool = false
var _hero_from: Vector2 = Vector2.ZERO
var _hero_to: Vector2 = Vector2.ZERO
var _hero_t: float = 0.0
var _fill_t: float = 0.0
var _hud_t: float = 0.0

# Per-frame measurements: poll (the socket and the simulation of every tick that arrived), the drawing reads
# (the two buffers, on frames after a tick), and the whole of _process.
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


func _ready() -> void:
	_parse_args()
	get_window().size = _window
	RenderingServer.set_default_clear_color(BG)
	_t0_us = Time.get_ticks_usec()
	add_child(_world)
	_ground.is_ground = true
	_world.add_child(_ground)
	var kinds: Array[Texture2D] = []
	for k in KINDS:
		kinds.append(_tex("enemy_" + k))
	_monsters = RealmBatch.new(_world, kinds, 1)
	var heroes: Array[Texture2D] = []
	for c in CLASSES.size():
		for r in RACES.size():
			heroes.append(_tex("hero_%s_%s" % [RACES[r], CLASSES[c]]))
	_players = RealmBatch.new(_world, heroes, 2)
	_hero.is_ground = false
	_hero.z_index = 3
	_hero.hero_tex = _tex("hero_%s_%s" % [RACES[_race], CLASSES[_hero_class]])
	_world.add_child(_hero)
	_world.add_child(_camera)
	_camera.make_current()
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
				_hero_class = clampi(int(v), 0, CLASSES.size() - 1)
			"race":
				_race = clampi(int(v), 0, RACES.size() - 1)
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


func _tex(key: String) -> Texture2D:
	return load("res://art/%s.png" % key) as Texture2D


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ls := LabelSettings.new()
	ls.font_size = 6
	ls.line_spacing = 0.0
	ls.font_color = Color(0.85, 0.95, 0.8)
	ls.outline_size = 2
	ls.outline_color = Color(0, 0, 0, 0.8)
	_hud.label_settings = ls
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0.55)
	panel.set_content_margin_all(3.0)
	_hud.add_theme_stylebox_override("normal", panel)
	_hud.position = Vector2(3, 3)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
			KEY_ESCAPE:
				_quit(0)


func _quit(code: int) -> void:
	link.close()
	get_tree().quit(code)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var now := _now()
	var applied: int = link.poll()
	var t1 := Time.get_ticks_usec()
	_send_input(now, delta)
	var t2 := Time.get_ticks_usec()
	var hero := _hero_at(now)
	if applied > 0:
		_fill(hero)
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
		_update_hud()
	if _rec:
		_rec_frames.append(delta * 1000.0)
		_rec_poll.append(_poll_ms)
		_rec_read.append(_read_ms)
		_rec_script.append(_script_ms)
		_rec_monsters.append(_monsters.count)
		_rec_players.append(_players.count)


## Sends one input per 50 ms of play (several after a long frame, so the server never runs out of them) and
## moves the hero's glide on to the new prediction.
func _send_input(now: float, delta: float) -> void:
	_input_acc = minf(_input_acc + delta, TICK_S * INPUT_CATCH_UP)
	if _input_acc < TICK_S:
		return
	var from := _hero_at(now)
	_read_keys(now)
	while _input_acc >= TICK_S:
		_input_acc -= TICK_S
		link.send_input(_move, _skill)
	if not _hero_ready and link.is_joined() and link.hero_id() >= 0:
		_hero_ready = true
		from = link.shown_position()
	_hero_from = from
	_hero_to = link.shown_position()
	_hero_t = now


## The hero between the last two predictions, over one input tick.
func _hero_at(now: float) -> Vector2:
	if not _hero_ready:
		return Vector2(RealmLink.field_size(), RealmLink.field_size()) / 2.0
	return _hero_from.lerp(_hero_to, clampf((now - _hero_t) / TICK_S, 0.0, 1.0))


func _read_keys(now: float) -> void:
	if _bot:
		# A slow wander: eight headings, each held a few seconds; the skill whenever it is ready.
		_move = 1 + (int(now / 3.0) * 3) % 8
		_skill = true
	else:
		var dx: int = int(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)) \
			- int(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
		var dy: int = int(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)) \
			- int(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W))
		_move = _dir_code(dx, dy)
		_skill = Input.is_physical_key_pressed(KEY_SPACE)
	if _move in [4, 5, 6]:
		_hero.hero_flip = true
	elif _move in [1, 2, 8]:
		_hero.hero_flip = false


## Direction 0..8 from a step of -1, 0, 1 each way: 1 E, 2 SE, 3 S, 4 SW, 5 W, 6 NW, 7 N, 8 NE.
static func _dir_code(dx: int, dy: int) -> int:
	const TABLE: Array[int] = [6, 7, 8, 5, 0, 1, 4, 3, 2]
	return TABLE[(dy + 1) * 3 + dx + 1]


## New ticks arrived: every figure on screen, from the module in two buffers.
func _fill(hero: Vector2) -> void:
	var half: Vector2 = BASE * float(_zoom) / 2.0 + Vector2.ONE * READ_MARGIN_PX
	var rect := Rect2i(Vector2i(hero - half), Vector2i(half * 2.0))
	_monsters.fill(link.monster_buffer(rect))
	_players.fill(link.player_buffer(rect))


func _place(hero: Vector2) -> void:
	var s: float = _screen_px_per_field_px()
	# Whole screen pixels, so the pixel art does not shimmer as the camera glides.
	_camera.position = (hero * s).round() / s
	var half: Vector2 = BASE * float(_zoom) / 2.0
	_ground.view = Rect2(_camera.position - half, half * 2.0)
	_ground.px_scale = s
	_ground.queue_redraw()
	_hero.hero_pos = hero
	_hero.px_scale = s
	var st: PackedInt32Array = link.hero_state()
	_hero.hero_alive = st.size() < 4 or st[3] == 1
	_hero.visible = _hero_ready
	_hero.queue_redraw()


func _update_hud() -> void:
	var c: Dictionary = link.counters()
	var l: Array[String] = []
	if not link.is_joined():
		l.append("CONNECTING TO %s:%d" % [_host, _port])
	var h: String = String.num_uint64(link.confirmed_hash(), 16).lpad(16, "0").left(8)
	l.append("TICK %d  HASH %s" % [link.confirmed_tick(), h])
	l.append("PLAYERS %d  MONSTERS %d" % [link.player_count(), link.monster_count()])
	l.append("DRAWN %d  MONSTERS DRAWN %d" % [_monsters.count + _players.count + int(_hero_ready), _monsters.count])
	l.append("NET IN %.1f KB/S  OUT %.2f KB/S" % [float(c.get("bytes_in_per_sec", 0.0)) / 1000.0, float(c.get("bytes_out_per_sec", 0.0)) / 1000.0])
	l.append("HASH CHECKS OK %d  FAILED %d" % [int(c.get("hash_checks_passed", 0)), int(c.get("hash_checks_failed", 0))])
	l.append("SIM %.2f MS/TICK  POLL %.2f  READ %.2f  SCRIPT %.2f MS" % [float(c.get("sim_ms_per_tick", 0.0)), _poll_ms, _read_ms, _script_ms])
	l.append("FPS %d  ZOOM %d" % [roundi(_fps), _zoom])
	var st: PackedInt32Array = link.hero_state()
	if st.size() == 4:
		l.append("HP %d/%d  LEVEL %d%s" % [st[0], st[1], st[2], "" if st[3] == 1 else "  DOWN"])
	_hud.text = "\n".join(l)


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
		"zooms": {},
	}
	var zooms: Array[int] = _shot_zooms.duplicate()
	if zooms.is_empty():
		zooms = KEY_ZOOMS.duplicate()
		if _extra_zoom > 0:
			zooms.append(_extra_zoom)
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
		var t_rec: float = _now()
		_rec = true
		await get_tree().create_timer(_secs).timeout
		_rec = false
		var dur: float = _now() - t_rec
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/zoom%d.png" % [_shots_dir, z])
		out["zooms"][str(z)] = _summary(dur, before, link.counters())
	var c: Dictionary = link.counters()
	for k in ["join_tick", "join_bytes", "ticks_applied", "hash_checks_passed", "hash_checks_failed", "stall_ms_max", "mispredicts", "predictions_checked", "bad_datagrams"]:
		out[k] = c.get(k, 0)
	out["players_in_field"] = link.player_count()
	out["monsters_in_field"] = link.monster_count()
	var f := FileAccess.open(_shots_dir.path_join("stats.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
	var ok: bool = link.is_joined() and int(c.get("hash_checks_failed", 1)) == 0 and int(c.get("hash_checks_passed", 0)) > 0
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
		"frame_ms_median": snappedf(sorted[n / 2], 0.01),
		"frame_ms_p99": snappedf(sorted[mini(n - 1, n * 99 / 100)], 0.01),
		"poll_ms_mean": snappedf(_mean(_rec_poll), 0.001),
		"read_ms_mean": snappedf(_mean(_rec_read), 0.001),
		"read_ms_p99": snappedf(_p99(_rec_read), 0.001),
		"script_ms_mean": snappedf(_mean(_rec_script), 0.001),
		"script_ms_p99": snappedf(_p99(_rec_script), 0.001),
		"monsters_drawn_mean": roundi(_mean_i(_rec_monsters)),
		"players_drawn_mean": roundi(_mean_i(_rec_players)),
		"sim_ms_per_tick": snappedf(float(after.get("sim_ms_per_tick", 0.0)), 0.01),
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


func _p99(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[mini(s.size() - 1, s.size() * 99 / 100)]

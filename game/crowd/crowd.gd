class_name CrowdViewer
extends Node2D
## The crowd viewer: connects to a protocol A v0 server (docs/realm/crowd_test.md), sends input 20 times a second
## and draws what comes back, a thousand figures a frame, through MultiMeshes. Positions are shown 100 ms in the
## past, blended between two snapshots.
## godot --path . game/crowd/crowd.tscn -- --server=127.0.0.1:7777 [--bot] [--class=0..4] [--race=0..3] [--zoom=1|2|4]
##   [--window=1920x1080] [--shots=DIR --secs=N]   (a scripted run: shots at each zoom, then DIR/stats.json, then quit)

const DELAY: float = 0.1
const INPUT_HZ: float = 20.0
const BASE_W: float = 1920.0
const BASE_H: float = 1080.0
const CLASSES: Array[String] = ["knight", "mage", "archer", "priest", "paladin"]
const RACES: Array[String] = ["human", "elf", "dwarf", "orc"]
const KINDS: Array[String] = ["bloat", "coffin", "guard", "cinderling", "censor", "hound", "shard", "swords"]
const ZOOMS: Array[int] = [1, 2, 4]
const JUMP_PX: float = 120.0
const CROWD_JUMP_PX: float = 24.0
const HURT_TINT: Vector3 = Vector3(1.0, 0.3, 0.3)
const ELITE_TINT: Vector3 = Vector3(1.0, 0.82, 0.3)
const ELITE_SCALE: float = 1.25
const BOB_PX: float = 1.5
const DOT_COL: Color = Color(0.65, 0.85, 1.0, 0.9)
const DOT_PX: float = 2.0
const SETTLE_S: float = 1.5
const WAIT_SNAPS: int = 20
const WAIT_MAX_S: float = 10.0

var _udp: PacketPeerUDP = PacketPeerUDP.new()
var _proto: CrowdProto = CrowdProto.new()
var _host: String = "127.0.0.1"
var _port: int = 7777
var _bot: bool = false
var _hero_class: int = 0
var _race: int = 0
var _win: Vector2 = Vector2(BASE_W, BASE_H)
var _zoom: int = 1
var _shots_dir: String = ""
var _secs: float = 6.0

var _welcomed: bool = false
var _hz: float = 20.0
var _hello_at: float = 0.0
var _input_acc: float = 0.0
var _last_tick: int = 0
var _snaps: Array[CrowdSnap] = []
var _offset: float = 0.0
var _have_offset: bool = false
var _t0_us: int = 0
var _move: int = 0
var _skill: bool = false
var _face_left: bool = false

var _world: Node2D = Node2D.new()
var _ground: CrowdLayer = CrowdLayer.new()
var _me: CrowdLayer = CrowdLayer.new()
var _hud: CrowdHud = CrowdHud.new()
var _dots: CrowdBatch
var _heroes: Array[CrowdBatch] = []
var _monsters: Array[CrowdBatch] = []
var _all: Array[CrowdBatch] = []

# measurements
var snaps_total: int = 0
var _bytes_total: int = 0
var _drawn_p: int = 0
var _drawn_c: int = 0
var _drawn_m: int = 0
var _decode_ms: float = 0.0
var _fill_ms: float = 0.0
var _rate_t: float = 0.0
var _rate_bytes: int = 0
var _rate_snaps: int = 0
var _bps: float = 0.0
var _sps: float = 0.0
var _fps: float = 0.0
var _hud_t: float = 0.0
var _rec: bool = false
var _rec_frames: PackedFloat32Array = PackedFloat32Array()
var _rec_decode: PackedFloat32Array = PackedFloat32Array()
var _rec_fill: PackedFloat32Array = PackedFloat32Array()
var _rec_bytes: int = 0
var _rec_snaps: int = 0
var _rec_t: float = 0.0
var _rec_drawn: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	_parse_args()
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	w.size = Vector2i(_win)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.set_default_clear_color(Color(0.055, 0.05, 0.075))
	_t0_us = Time.get_ticks_usec()
	add_child(_world)
	_ground.is_ground = true
	_world.add_child(_ground)
	_dots = CrowdBatch.new(_world, _white(), Vector2(DOT_PX, DOT_PX), false, 1)
	_all.append(_dots)
	for k in KINDS:
		var t := _tex("enemy_" + k)
		var b := CrowdBatch.new(_world, t, t.get_size(), true, 2)
		_monsters.append(b)
		_all.append(b)
	_heroes.resize(32)
	for c in CLASSES.size():
		for r in RACES.size():
			var t := _tex("hero_%s_%s" % [RACES[r], CLASSES[c]])
			var b := CrowdBatch.new(_world, t, t.get_size(), true, 3)
			_heroes[c | (r << 3)] = b
			_all.append(b)
	_me.is_ground = false
	_me.z_index = 4
	_me.me_tex = _tex("hero_%s_%s" % [RACES[_race], CLASSES[_hero_class]])
	_world.add_child(_me)
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud.size = _win
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	_udp.connect_to_host(_host, _port)
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
			"bot":
				_bot = true
			"class":
				_hero_class = clampi(int(v), 0, CLASSES.size() - 1)
			"race":
				_race = clampi(int(v), 0, RACES.size() - 1)
			"zoom":
				_zoom = int(v) if ZOOMS.has(int(v)) else 1
			"window":
				var wh := v.split("x")
				if wh.size() == 2:
					_win = Vector2(maxi(int(wh[0]), 320), maxi(int(wh[1]), 200))
			"shots":
				_shots_dir = v
			"secs":
				_secs = maxf(float(v), 1.0)
	_hud.px = 2 if _win.x >= 1400.0 else 1


func _tex(key: String) -> Texture2D:
	var t := Art.tex("sprites", key)
	return t if t else _white()


func _white() -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _now() -> float:
	return (Time.get_ticks_usec() - _t0_us) / 1000000.0


func _apply_zoom(z: int) -> void:
	_zoom = z
	_world.scale = Vector2.ONE * (_win.x / BASE_W) * (4.0 / z)
	_ground.px_scale = _world.scale.x
	_me.px_scale = _world.scale.x


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_1:
				_apply_zoom(1)
			KEY_2:
				_apply_zoom(2)
			KEY_3:
				_apply_zoom(4)
			KEY_ESCAPE:
				_quit()


func _quit() -> void:
	if _udp.is_socket_connected():
		_udp.put_packet(CrowdProto.bye())
	get_tree().quit()


func _process(delta: float) -> void:
	var now := _now()
	var t0 := Time.get_ticks_usec()
	_poll(now)
	var t1 := Time.get_ticks_usec()
	_send(now, delta)
	_fill(now)
	var t2 := Time.get_ticks_usec()
	_decode_ms = (t1 - t0) / 1000.0
	_fill_ms = (t2 - t1) / 1000.0
	_count(now, delta)
	if _rec:
		_rec_frames.append(delta * 1000.0)
		_rec_decode.append(_decode_ms)
		_rec_fill.append(_fill_ms)
		_rec_drawn.append(_drawn_p + _drawn_c + _drawn_m)


func _poll(now: float) -> void:
	while _udp.get_available_packet_count() > 0:
		var b := _udp.get_packet()
		_bytes_total += b.size()
		_rate_bytes += b.size()
		if _rec:
			_rec_bytes += b.size()
		if b.size() > 0 and b[0] == CrowdProto.OP_WELCOME:
			var wl := CrowdProto.decode_welcome(b)
			if not wl.is_empty():
				_welcomed = true
				_hz = maxf(float(wl["hz"]), 1.0)
			continue
		var s := _proto.feed(b, now)
		if s:
			_add_snap(s, now)


func _add_snap(s: CrowdSnap, now: float) -> void:
	snaps_total += 1
	_rate_snaps += 1
	if _rec:
		_rec_snaps += 1
	_last_tick = s.tick
	var sample: float = now - s.tick / _hz
	if not _have_offset:
		_offset = sample
		_have_offset = true
	else:
		_offset += (sample - _offset) * 0.05
	if not _snaps.is_empty():
		s.match_previous(_snaps[-1])
	_snaps.append(s)
	while _snaps.size() > 4:
		_snaps.pop_front()


func _send(now: float, delta: float) -> void:
	if not _welcomed:
		if now >= _hello_at:
			_hello_at = now + 0.5
			_udp.put_packet(CrowdProto.hello(_hero_class, _race))
		return
	_read_keys(now)
	_input_acc += delta
	var step := 1.0 / INPUT_HZ
	if _input_acc >= step:
		_input_acc = fmod(_input_acc, step)
		_udp.put_packet(CrowdProto.input(_last_tick, _move, _skill, _zoom))


func _read_keys(now: float) -> void:
	if _bot:
		# a slow wander: eight headings, each held a few seconds, a long loop around the field's middle
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
		_face_left = true
	elif _move in [1, 2, 8]:
		_face_left = false


## Direction 0..8 from a step of -1, 0, 1 each way: 1 E, 2 SE, 3 S, 4 SW, 5 W, 6 NW, 7 N, 8 NE.
static func _dir_code(dx: int, dy: int) -> int:
	const TABLE: Array[int] = [6, 7, 8, 5, 0, 1, 4, 3, 2]
	return TABLE[(dy + 1) * 3 + dx + 1]


## Draws what the snapshots say at render time (now - delay), between the two snapshots that bracket it.
func _fill(now: float) -> void:
	for b in _all:
		b.begin()
	_drawn_p = 0
	_drawn_c = 0
	_drawn_m = 0
	if _snaps.is_empty():
		_commit()
		return
	var rt: float = now - _offset - DELAY
	var i: int = _snaps.size() - 1
	while i > 0 and _snaps[i - 1].tick / _hz > rt:
		i -= 1
	var cur: CrowdSnap = _snaps[i]
	var prev: CrowdSnap = _snaps[i - 1] if i > 0 else null
	var a: float = 1.0
	if prev:
		var span: float = (cur.tick - prev.tick) / _hz
		a = clampf((rt - prev.tick / _hz) / span, 0.0, 1.0) if span > 0.0 else 1.0
	var cam := Vector2(cur.my_x, cur.my_y)
	if prev and cam.distance_to(Vector2(prev.my_x, prev.my_y)) < JUMP_PX:
		cam = Vector2(prev.my_x, prev.my_y).lerp(cam, a)
	_place_world(cam)
	var t: float = now
	_fill_players(cur, prev, a, t)
	_fill_crowd(cur, prev, a)
	_fill_monsters(cur, prev, a)
	_commit()


func _place_world(cam: Vector2) -> void:
	var s: float = _world.scale.x
	_world.position = (_win / 2.0 - cam * s).round()
	var half := _win / s / 2.0
	_ground.view = Rect2(cam - half, half * 2.0)
	_ground.queue_redraw()
	_me.me_pos = cam
	_me.me_flip = _face_left
	_me.queue_redraw()


func _fill_players(cur: CrowdSnap, prev: CrowdSnap, a: float, t: float) -> void:
	var n: int = cur.pid.size()
	for i in n:
		var x: float = cur.px[i]
		var y: float = cur.py[i]
		var j: int = cur.pprev[i] if prev else -1
		if j >= 0:
			var ox: float = prev.px[j]
			var oy: float = prev.py[j]
			if absf(x - ox) + absf(y - oy) < JUMP_PX:
				x = ox + (x - ox) * a
				y = oy + (y - oy) * a
		var fl: int = cur.pflag[i]
		if fl & 2:
			y -= absf(sin(t * 14.0 + cur.pid[i])) * BOB_PX
		var b: CrowdBatch = _heroes[cur.pkind[i] & 0x1F]
		if b == null:
			continue
		var sx: float = -1.0 if fl & 1 else 1.0
		if fl & 4:
			b.push(x, y, sx, HURT_TINT.x, HURT_TINT.y, HURT_TINT.z, 1.0)
		else:
			b.push(x, y, sx, 1.0, 1.0, 1.0, 1.0)
		_drawn_p += 1


func _fill_crowd(cur: CrowdSnap, prev: CrowdSnap, a: float) -> void:
	# The far crowd has no ids: blend by list position, and only where that pairs a dot with one close by.
	var n: int = cur.cx.size()
	var pn: int = prev.cx.size() if prev else 0
	for i in n:
		var x: float = cur.cx[i]
		var y: float = cur.cy[i]
		if i < pn:
			var ox: float = prev.cx[i]
			var oy: float = prev.cy[i]
			if absf(x - ox) + absf(y - oy) < CROWD_JUMP_PX:
				x = ox + (x - ox) * a
				y = oy + (y - oy) * a
		_dots.push(x, y, 1.0, DOT_COL.r, DOT_COL.g, DOT_COL.b, DOT_COL.a)
	_drawn_c = n


func _fill_monsters(cur: CrowdSnap, prev: CrowdSnap, a: float) -> void:
	var n: int = cur.mid.size()
	for i in n:
		var x: float = cur.mx[i]
		var y: float = cur.my[i]
		var j: int = cur.mprev[i] if prev else -1
		if j >= 0:
			var ox: float = prev.mx[j]
			var oy: float = prev.my[j]
			if absf(x - ox) + absf(y - oy) < JUMP_PX:
				x = ox + (x - ox) * a
				y = oy + (y - oy) * a
		var f: int = cur.mflag[i]
		var b: CrowdBatch = _monsters[f & 7]
		var s: float = ELITE_SCALE if f & 0x40 else 1.0
		if f & 0x80:
			b.push(x, y, s, HURT_TINT.x, HURT_TINT.y, HURT_TINT.z, 1.0)
		elif f & 0x40:
			b.push(x, y, s, ELITE_TINT.x, ELITE_TINT.y, ELITE_TINT.z, 1.0)
		else:
			b.push(x, y, 1.0, 1.0, 1.0, 1.0, 1.0)
	_drawn_m = n


func _commit() -> void:
	for b in _all:
		b.commit()


func _count(now: float, delta: float) -> void:
	if delta > 0.0:
		_fps = lerpf(_fps, 1.0 / delta, 0.05)
	if now - _rate_t >= 1.0:
		var dt: float = now - _rate_t
		_bps = _rate_bytes / dt
		_sps = _rate_snaps / dt
		_rate_t = now
		_rate_bytes = 0
		_rate_snaps = 0
	if now - _hud_t < 0.2:
		return
	_hud_t = now
	var cur: CrowdSnap = _snaps[-1] if not _snaps.is_empty() else null
	var l: Array[String] = []
	l.append("PLAYERS IN FIELD %d" % (cur.players_in_field if cur else 0))
	l.append("MONSTERS IN FIELD %d" % (cur.monsters_in_field if cur else 0))
	l.append("DRAWN %d  P %d  C %d  M %d" % [_drawn_p + _drawn_c + _drawn_m, _drawn_p, _drawn_c, _drawn_m])
	l.append("RX %.1f KB/S  %.1f SNAP/S" % [_bps / 1024.0, _sps])
	l.append("SERVER TICK %.2f MS" % (cur.tick_ms if cur else 0.0))
	l.append("FPS %d  ZOOM %d" % [roundi(_fps), _zoom])
	l.append("DECODE %.2f MS  FILL %.2f MS" % [_decode_ms, _fill_ms])
	if not _welcomed:
		l.append("CONNECTING TO %s:%d" % [_host, _port])
	_hud.lines = l
	_hud.queue_redraw()


# ---- the scripted run ----

func _scripted() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	_bot = true
	var t_wait: float = _now()
	while snaps_total < WAIT_SNAPS and _now() - t_wait < WAIT_MAX_S:
		await get_tree().process_frame
	var out := {"server": "%s:%d" % [_host, _port], "snapshots_before_start": snaps_total, "zooms": {}}
	for z in ZOOMS:
		_apply_zoom(z)
		await get_tree().create_timer(SETTLE_S).timeout
		_rec_frames.clear()
		_rec_decode.clear()
		_rec_fill.clear()
		_rec_drawn.clear()
		_rec_bytes = 0
		_rec_snaps = 0
		_rec_t = _now()
		_rec = true
		await get_tree().create_timer(_secs).timeout
		_rec = false
		var dur: float = _now() - _rec_t
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/zoom%d.png" % [_shots_dir, z])
		out["zooms"][str(z)] = _summary(dur)
	var f := FileAccess.open(_shots_dir.path_join("stats.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
	_quit()


func _summary(dur: float) -> Dictionary:
	var n: int = _rec_frames.size()
	var sorted := _rec_frames.duplicate()
	sorted.sort()
	var worst: int = maxi(1, n / 100)
	var worst_sum: float = 0.0
	for i in worst:
		worst_sum += sorted[n - 1 - i]
	var script := PackedFloat32Array()
	script.resize(n)
	for i in n:
		script[i] = _rec_decode[i] + _rec_fill[i]
	var ssorted := script.duplicate()
	ssorted.sort()
	var drawn_sum: float = 0.0
	for d in _rec_drawn:
		drawn_sum += d
	return {
		"frames": n,
		"seconds": snappedf(dur, 0.01),
		"fps_mean": snappedf(n / dur, 0.1),
		"fps_slowest_1pct": snappedf(1000.0 / (worst_sum / worst), 0.1),
		"frame_ms_p99": snappedf(sorted[mini(n - 1, n * 99 / 100)], 0.01),
		"decode_ms_mean": snappedf(_mean(_rec_decode), 0.001),
		"fill_ms_mean": snappedf(_mean(_rec_fill), 0.001),
		"script_ms_mean": snappedf(_mean(script), 0.001),
		"script_ms_p99": snappedf(ssorted[mini(n - 1, n * 99 / 100)], 0.001),
		"bytes_per_sec": roundi(_rec_bytes / dur),
		"snapshots_per_sec": snappedf(_rec_snaps / dur, 0.1),
		"figures_drawn_mean": roundi(drawn_sum / maxf(n, 1.0)),
		"dropped_parts": _proto.dropped,
	}


func _mean(a: PackedFloat32Array) -> float:
	var s: float = 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1.0)

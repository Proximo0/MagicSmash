extends SceneTree
## The monster health bars' own cost (figures_bar.gdshader), with nothing else on screen: the monsters' batch built
## exactly as the client builds it (every kind's art, RealmBatch with bars), filled with N monsters spread over a
## zoom-16 view (7,680 x 4,320 field px) on a dark ground, a share of them hurt, and drawn for a while in four modes:
## off (no bars); near (the game: the bar pass holds the hurt within RealmLink's BAR_RADIUS_PX, 480, of the view's
## centre, as draw.rs builds RealmLink.bar_buffer); pass (the first design: the bar pass over every drawn monster,
## bars on the hurt); every (a bar on every drawn monster, the worst case). Prints one line per count (medians of
## the frames; the modes take turns three times, so a busy machine's drift falls on all of them):
##   BARS_BENCH n=<N> hurt=<share> near_bars=<n> cpu_ms_per_frame off=.. near=.. pass=.. every=.. cpu_pct ...
##   frame_ms ... frame_pct ... render_gpu_ms ...
## The process's CPU a frame (every thread, so the software renderer's work too) is the cost to read on a shared
## machine; the frame times swing with its load. Needs a display (xvfb-run).
## godot --path realm/client -s res://tests/bars_bench.gd -- [--counts=10000,20000] [--hurt=0.3] [--frames=60]

const VIEW: Vector2 = Vector2(7680, 4320)
const BAR_RADIUS_PX: float = 480.0
const MODES: Array[String] = ["off", "near", "pass", "every"]
const CENTRE: Vector2 = Vector2(8192, 8192)
const WARM: int = 10
const ROUNDS: int = 3


func _initialize() -> void:
	var counts: Array[int] = [10000, 20000]
	var hurt: float = 0.3
	var frames: int = 60
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"counts":
				counts.clear()
				for c in kv[1].split(","):
					counts.append(int(c))
			"hurt":
				hurt = float(kv[1])
			"frames":
				frames = int(kv[1])
	_run(counts, hurt, frames)


func _run(counts: Array[int], hurt: float, frames: int) -> void:
	root.size = Vector2i(1440, 810)
	RenderingServer.set_default_clear_color(Color(0.1, 0.09, 0.08))
	var world := Node2D.new()
	root.add_child(world)
	var cam := Camera2D.new()
	cam.position = CENTRE
	cam.zoom = Vector2.ONE / 16.0
	world.add_child(cam)
	await process_frame
	cam.make_current()
	var kinds: Array[Dictionary] = FieldArt.monster_entries()
	var atlas: Array[Dictionary] = kinds.duplicate()
	atlas.append_array(FieldArt.boss_entries(kinds))
	var batch := RealmBatch.new(world, atlas, 1, false, true, true)
	batch.set_smooth(true)
	var vp: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for n in counts:
		var buf: PackedFloat32Array = _buffer(n, kinds.size(), hurt)
		var near: PackedFloat32Array = _near(buf)
		var res: Dictionary = {}
		for mode in MODES:
			res[mode] = [[], [], 0.0, 0]
		for round in ROUNDS:
			for mode in MODES:
				batch.set_bars(mode != "off", mode == "every")
				# Two fills so both of the batch's MultiMeshes (figures and bars) hold the buffers.
				for k in 2:
					batch.fill(buf.duplicate())
					batch.fill_bars(near.duplicate() if mode == "near" else buf.duplicate())
				var t: int = Time.get_ticks_usec()
				var c0: float = 0.0
				for i in WARM + frames:
					await process_frame
					var now: int = Time.get_ticks_usec()
					if i == WARM - 1:
						c0 = RealmClient.cpu_ms()
					if i >= WARM:
						res[mode][0].append((now - t) / 1000.0)
						res[mode][1].append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
					t = now
				res[mode][2] += RealmClient.cpu_ms() - c0
				res[mode][3] += frames
		var m: Dictionary = {}
		for mode in MODES:
			m[mode] = [_median(res[mode][0]), _median(res[mode][1]), float(res[mode][2]) / maxf(float(res[mode][3]), 1.0)]
		var pct := func(mode: String, k: int) -> float: return 100.0 * (float(m[mode][k]) - float(m["off"][k])) / float(m["off"][k])
		print("BARS_BENCH n=%d hurt=%.2f near_bars=%d cpu_ms_per_frame off=%.2f near=%.2f pass=%.2f every=%.2f cpu_pct near=%+.1f pass=%+.1f every=%+.1f frame_ms off=%.2f near=%.2f pass=%.2f every=%.2f frame_pct near=%+.1f pass=%+.1f every=%+.1f render_gpu_ms off=%.2f near=%.2f pass=%.2f every=%.2f" % [
			n, hurt, near.size() / RealmBatch.STRIDE, m["off"][2], m["near"][2], m["pass"][2], m["every"][2], pct.call("near", 2), pct.call("pass", 2), pct.call("every", 2),
			m["off"][0], m["near"][0], m["pass"][0], m["every"][0], pct.call("near", 0), pct.call("pass", 0), pct.call("every", 0),
			m["off"][1], m["near"][1], m["pass"][1], m["every"][1]])
	quit(0)


## N monsters in draw order (by y), as draw.rs writes them: transform, tint (alpha 0.5 + health / 2 for the hurt,
## 1 for the whole), and (no glide, kind, walking bob).
func _buffer(n: int, kinds: int, hurt: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pts: Array[Vector3] = []
	for i in n:
		var p: Vector2 = CENTRE + Vector2(rng.randf_range(-0.5, 0.5) * VIEW.x, rng.randf_range(-0.5, 0.5) * VIEW.y)
		pts.append(Vector3(p.x, p.y, float(i)))
	pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	var out := PackedFloat32Array()
	out.resize(n * RealmBatch.STRIDE)
	for i in n:
		var p: Vector3 = pts[i]
		var o: int = i * RealmBatch.STRIDE
		var face: float = 1.0 if rng.randf() < 0.5 else -1.0
		var vals: Array = [face, 0.0, 0.0, p.x, 0.0, 1.0, 0.0, p.y, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, float(rng.randi_range(0, kinds - 1)), float(1 + i % 31)]
		if rng.randf() < hurt:
			vals[11] = 0.5 + float(rng.randi_range(1, 255)) / 512.0
		for k in RealmBatch.STRIDE:
			out[o + k] = vals[k]
	return out


## The hurt within BAR_RADIUS_PX of the view's centre, as draw.rs picks RealmLink.bar_buffer.
func _near(buf: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in buf.size() / RealmBatch.STRIDE:
		var o: int = i * RealmBatch.STRIDE
		if buf[o + 11] < 1.0 and Vector2(buf[o + 3], buf[o + 7]).distance_to(CENTRE) <= BAR_RADIUS_PX:
			out.append_array(buf.slice(o, o + RealmBatch.STRIDE))
	return out


func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s: Array = a.duplicate()
	s.sort()
	return float(s[s.size() / 2])

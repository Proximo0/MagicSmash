extends Node2D
## Pick the hero's size on your own monitor, in the real client's own view: the game's ground grid and background,
## its 480 x 270 base, canvas_items stretch with integer scale (project.godot) and its camera zoom levels 1, 2, 4
## (RealmClient.KEY_ZOOMS). Two groups side by side, each next to a monster (enemy_guard) and a hero still
## (hero_human_knight) for scale: "A: 56 px hero" (the 56 set, scale 0.5) and "B: 112 px hero" (the 112 set, 4 texture
## px per 2 world px, drawn at 0.5 so it is twice as tall on screen as A). Row 1 walks in place, row 2 walks across.
## The pilot strips and their .json sidecars are in res://tests/size_pick/ (A_<hero>_walk.png, B_<hero>_walk.png).
## godot --path realm/client res://tests/size_pick.tscn -- [--fullscreen] [--screen=N] [--window=1920x1080] [--zoom=1|2|4]
##   [--secs=N quits after N seconds and prints SIZEPICK shown ...] [--shots=DIR saves zoom<N>.png for 1, 2, 4 and quits]
## Keys: 1 2 3 zoom 1 2 4, Space pauses, F fullscreen, S saves a screenshot to user://, Esc quits.

const DIR: String = "res://tests/size_pick"
const HEROES: Array[String] = ["hero_human_knight", "hero_human_mage", "hero_dwarf_knight"]
const ZOOMS: Array[int] = [1, 2, 4]
const BASE: Vector2 = Vector2(480, 270)
const BG: Color = Color(0.055, 0.05, 0.075)
const CENTRE: Vector2 = Vector2(2048, 2048)
## Walking across: world px a second (the same at every zoom).
const SPEED: float = 60.0
const GROUPS: Array[String] = ["A", "B", "C"]
const GROUP_TITLE: Dictionary = {"A": "A: 56 px hero", "B": "B: 112 px hero", "C": "C: 112 px art, A size"}

var _zoom: int = 1
var _time: float = 0.0
var _paused: bool = false
var _entries: Dictionary = {}
var _still_hero: Dictionary = {}
var _monster: Dictionary = {}
var _ground: RealmLayer = RealmLayer.new()
var _stage: Node2D = Node2D.new()
var _camera: Camera2D = Camera2D.new()
var _title: Label = Label.new()
var _caption: Label = Label.new()
var _secs: float = 0.0
var _shots: String = ""
var _shot_i: int = 0
var _shot_at: float = 0.0
var _elapsed: float = 0.0
var _screen: int = -1
var _last_heights: String = ""
var _used: Dictionary = {}


func _ready() -> void:
	var window := Vector2i(1440, 810)
	var fullscreen: bool = false
	for a in OS.get_cmdline_user_args():
		if a == "--fullscreen":
			fullscreen = true
		elif a.begins_with("--screen="):
			_screen = int(a.substr(9))
		elif a.begins_with("--window="):
			var p: PackedStringArray = a.substr(9).split("x")
			window = Vector2i(int(p[0]), int(p[1]))
		elif a.begins_with("--zoom="):
			_zoom = clampi(int(a.substr(7)), 1, 4)
		elif a.begins_with("--secs="):
			_secs = float(a.substr(7))
		elif a.begins_with("--shots="):
			_shots = a.substr(8)
	if _screen >= 0 and _screen < DisplayServer.get_screen_count():
		get_window().current_screen = _screen
	get_window().size = window
	if fullscreen:
		get_window().mode = Window.MODE_FULLSCREEN
	RenderingServer.set_default_clear_color(BG)
	for g in GROUPS:
		for h in HEROES:
			var e: Dictionary = FieldArt.entry_for("%s_%s" % [("B" if g == "C" else g), h], DIR)
			if g == "C":
				e["scale"] = 0.25
			if e.is_empty():
				push_error("size_pick: missing %s_%s_walk.png in %s" % [g, h, DIR])
				get_tree().quit(1)
				return
			_entries["%s_%s" % [g, h]] = e
			_used["%s_%s" % [g, h]] = _used_rows(e)
	_still_hero = FieldArt.entry_for("hero_human_knight")
	_monster = FieldArt.entry_for("enemy_guard")
	_ground.is_ground = true
	_ground.show_grid = true
	add_child(_ground)
	_stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stage.set_script(StageDraw)
	_stage.set("owner_ref", self)
	add_child(_stage)
	add_child(_camera)
	_camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	for l in [_title, _caption]:
		l.add_theme_font_size_override("font_size", 6)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 2)
		layer.add_child(l)
	_title.position = Vector2(4, 2)
	_caption.position = Vector2(4, 226)
	for gi in GROUPS.size():
		var gl := Label.new()
		gl.text = GROUP_TITLE[GROUPS[gi]]
		gl.add_theme_font_size_override("font_size", 7)
		gl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		gl.add_theme_color_override("font_outline_color", Color.BLACK)
		gl.add_theme_constant_override("outline_size", 2)
		gl.position = Vector2([4.0, 150.0, 365.0][gi], 12)
		layer.add_child(gl)
	_apply_zoom(_zoom)


## The rows of a strip that hold picture (alpha), for the real on-screen height: [top, bottom).
func _used_rows(e: Dictionary) -> Vector2i:
	var img: Image = (e["tex"] as Texture2D).get_image()
	var r: Rect2i = img.get_used_rect()
	return Vector2i(r.position.y, r.end.y)


func _apply_zoom(z: int) -> void:
	_zoom = z
	_camera.position = CENTRE
	_camera.zoom = Vector2.ONE / float(z)
	var half: Vector2 = BASE * float(z) / 2.0
	_ground.view = Rect2(CENTRE - half, half * 2.0)
	_ground.px_scale = _px_per_world()
	_ground.queue_redraw()
	var a_heights: Array[String] = []
	var b_heights: Array[String] = []
	var c_heights: Array[String] = []
	for g in GROUPS:
		for h in HEROES:
			var px: int = _screen_height(g + "_" + h)
			(a_heights if g == "A" else (b_heights if g == "B" else c_heights)).append("%s %d" % [h.replace("hero_", ""), px])
	_title.text = "ZOOM %d (key %d)   %.2f screen px per world px   window %dx%d   stretch x%d" % [_zoom, ZOOMS.find(_zoom) + 1, _px_per_world(), get_window().size.x, get_window().size.y, int(_stretch())]
	_caption.text = "A: 56 px hero (scale 0.5): %s screen px tall\nB: 112 px hero (scale 0.5, 2x A): %s screen px tall\nC: 112 px art at A's size (scale 0.25): %s screen px tall\nKeys: 1 2 3 zoom, Space pause, F fullscreen, S screenshot" % [", ".join(a_heights), ", ".join(b_heights), ", ".join(c_heights)]
	_last_heights = "A=%s B=%s C=%s" % [",".join(PackedStringArray(a_heights)).replace(" ", ":"), ",".join(PackedStringArray(b_heights)).replace(" ", ":"), ",".join(PackedStringArray(c_heights)).replace(" ", ":")]
	_stage.queue_redraw()
	print("SIZEPICK zoom=%d window=%dx%d stretch=%d px_per_world=%.3f A=[%s] B=[%s] C=[%s]" % [_zoom, get_window().size.x, get_window().size.y, int(_stretch()), _px_per_world(), ", ".join(a_heights), ", ".join(b_heights), ", ".join(c_heights)])


## The stretch factor (project.godot: canvas_items, integer): whole screen px per base px.
func _stretch() -> float:
	return get_viewport().get_final_transform().x.x


## Screen px per world px at the current zoom, as the client computes it.
func _px_per_world() -> float:
	return _stretch() / float(_zoom)


## The on-screen height in real screen px of a hero's opaque rows at the current zoom and window.
func _screen_height(key: String) -> int:
	var e: Dictionary = _entries[key]
	var rows: Vector2i = _used[key]
	return roundi(float(rows.y - rows.x) * float(e["scale"]) * _px_per_world())


func _process(delta: float) -> void:
	if not _paused:
		_time += delta
	_elapsed += delta
	_stage.queue_redraw()
	if get_window().size != _last_size:
		_last_size = get_window().size
		_apply_zoom(_zoom)
	if _secs > 0.0 and _elapsed >= _secs:
		print("SIZEPICK shown secs=%d screen=%d heights=%s" % [roundi(_elapsed), get_window().current_screen, _last_heights])
		get_tree().quit()
	if not _shots.is_empty() and _elapsed > 1.0:
		_shot_at += delta
		if _shot_at > 1.5:
			_shot_at = 0.0
			_save(_shots.path_join("zoom%d.png" % _zoom))
			_shot_i += 1
			if _shot_i >= ZOOMS.size():
				get_tree().quit()
			else:
				_apply_zoom(ZOOMS[_shot_i])


var _last_size: Vector2i = Vector2i.ZERO


func _save(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(path)
	print("SIZEPICK saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_1: _apply_zoom(1)
		KEY_2: _apply_zoom(2)
		KEY_3: _apply_zoom(4)
		KEY_SPACE: _paused = not _paused
		KEY_F:
			var w: Window = get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		KEY_S: _save("user://size_pick_zoom%d_%d.png" % [_zoom, int(Time.get_unix_time_from_system())])
		KEY_ESCAPE: get_tree().quit()


## Draws the sprites. A separate node so the ground (a RealmLayer) stays under it.
class StageDraw extends Node2D:
	var owner_ref: Node2D

	func _draw() -> void:
		var o: Node2D = owner_ref
		var z: float = float(o._zoom)
		var s: float = o._px_per_world()
		for gi in GROUPS.size():
			var g: String = GROUPS[gi]
			# Per group, in base px from the left edge of the screen: where its centre is and how far apart its walkers
			# stand (B is twice as wide as A and C). Offsets of the still hero, the monster and the first walker.
			var cb: float = [65.0, 245.0, 415.0][gi]
			var sp: float = [28.0, 48.0, 28.0][gi]
			var offs: Array = [[-50.0, -33.0, -12.0], [-72.0, -42.0, -5.0], [-50.0, -33.0, -12.0]][gi]
			var cx: float = CENTRE.x + (cb - 240.0) * z
			var row1: float = CENTRE.y - 10.0 * z
			var row2: float = CENTRE.y + 75.0 * z
			_still(o._still_hero, Vector2(cx + offs[0] * z, row1), s)
			_still(o._monster, Vector2(cx + offs[1] * z, row1), s)
			for i in HEROES.size():
				var e: Dictionary = o._entries[g + "_" + HEROES[i]]
				_walk(e, Vector2(cx + (offs[2] + sp * i) * z, row1), o._time, s)
				# Across: staggered, wrapping over the group's width.
				var width: float = (200.0 if gi == 1 else 120.0) * z
				var x: float = fmod(SPEED * o._time + width * float(i) / 3.0, width)
				_walk(e, Vector2(cx - width / 2.0 + x, row2), o._time, s)

	## Feet snapped to a whole screen px like the camera, so texels stay square.
	func _snap(p: Vector2, s: float) -> Vector2:
		return (p * s).round() / s

	func _still(e: Dictionary, feet: Vector2, s: float) -> void:
		var t: Texture2D = e["tex"]
		var n: int = int(e["anim"])
		var fw: float = float(t.get_width()) / float(n)
		var sz: Vector2 = Vector2(fw, t.get_height()) * float(e["scale"])
		draw_texture_rect_region(t, Rect2(_snap(feet, s) - Vector2(sz.x / 2.0, sz.y), sz), Rect2(0.0, 0.0, fw, t.get_height()))

	func _walk(e: Dictionary, feet: Vector2, t: float, s: float) -> void:
		var tex: Texture2D = e["tex"]
		var n: int = int(e["anim"])
		var fw: float = float(tex.get_width()) / float(n)
		var step: int = int(t * float(e["fps"])) % n
		var sz := Vector2(fw, tex.get_height()) * float(e["scale"])
		draw_texture_rect_region(tex, Rect2(_snap(feet, s) - Vector2(sz.x / 2.0, sz.y), sz), Rect2(Vector2(fw * step, 0), Vector2(fw, tex.get_height())))

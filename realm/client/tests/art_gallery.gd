extends SceneTree
## Every picture in realm/client/art at game size over each field's ground colour, with a 56 px ruler, saved as a PNG.
## A walk strip is drawn as its first frame at its scale (FieldArt.walk_params: 0.5, 2 texture px per world px, unless its .json says otherwise), a still at 1:1; the
## whole sheet is then magnified x3 so a world pixel is 3 on the PNG. One row per picture, one column per field
## (FieldArt.FIELD_COLOURS), the file name on the left. Pure Image work: needs no display. Prints
## ART_GALLERY ok sprites=<n> out=<path> and exits 1 when a picture cannot be read.
## godot --headless --path realm/client -s res://tests/art_gallery.gd -- --out=gallery.png

const ZOOM: int = 3
const RULER: int = 56
const PAD: int = 4
const LABEL_W: int = 150
const MAX_CELL: int = 128


func _initialize() -> void:
	var out: String = "art_gallery.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var names: Array[String] = []
	for f in DirAccess.get_files_at("res://art"):
		if f.ends_with(".png"):
			names.append(f)
	names.sort()
	var sprites: Array[Image] = []
	var cell: Vector2i = Vector2i(RULER, 16)
	var bad: int = 0
	for f in names:
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path("res://art/" + f))
		if img == null or img.is_empty():
			print("ART_GALLERY unreadable ", f)
			bad += 1
			continue
		img.convert(Image.FORMAT_RGBA8)
		if f.ends_with("_walk.png"):
			var p: Dictionary = FieldArt.walk_params(f.trim_suffix("_walk.png"), "res://art", img.get_width())
			var w: int = img.get_width() / int(p["anim"])
			var sc: float = float(p["scale"])
			img = img.get_region(Rect2i(0, 0, w, img.get_height()))
			img.resize(maxi(1, roundi(w * sc)), maxi(1, roundi(img.get_height() * sc)), Image.INTERPOLATE_NEAREST)
		var s: Vector2i = Vector2i(mini(img.get_width(), MAX_CELL), mini(img.get_height(), MAX_CELL))
		if s.x != img.get_width() or s.y != img.get_height():
			img.resize(s.x, s.y, Image.INTERPOLATE_NEAREST)
		sprites.append(img)
		cell = Vector2i(maxi(cell.x, s.x), maxi(cell.y, s.y))
	var cols: int = FieldArt.FIELD_COLOURS.size()
	var row_h: int = cell.y + PAD
	var col_w: int = cell.x + PAD
	var width: int = LABEL_W + cols * col_w + PAD
	var height: int = PAD * 3 + 8 + sprites.size() * row_h
	var sheet: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.12))
	# The ruler: 56 world px, tall as a hero, ticks every 8.
	sheet.fill_rect(Rect2i(PAD, PAD, RULER, 2), Color.WHITE)
	for t in range(0, RULER + 1, 8):
		sheet.fill_rect(Rect2i(PAD + mini(t, RULER - 1), PAD, 1, 6 if t % 56 == 0 else 3), Color.WHITE)
	var y: int = PAD * 3 + 8
	var k: int = 0
	for f in names:
		if k >= sprites.size():
			break
		var img: Image = sprites[k]
		k += 1
		for c in cols:
			var x: int = LABEL_W + c * col_w
			sheet.fill_rect(Rect2i(x, y, cell.x, cell.y), FieldArt.FIELD_COLOURS[c])
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(x + (cell.x - img.get_width()) / 2, y + cell.y - img.get_height()))
		sheet.fill_rect(Rect2i(PAD, y + cell.y / 2, 6, 1), Color(0.6, 0.6, 0.7))
		y += row_h
	sheet.resize(width * ZOOM, height * ZOOM, Image.INTERPOLATE_NEAREST)
	var dir: String = out.get_base_dir()
	if dir != "" and dir != ".":
		DirAccess.make_dir_recursive_absolute(dir)
	var err: int = sheet.save_png(out)
	# Names go in a text file beside the PNG: the headless build has no font to draw them with.
	var txt: FileAccess = FileAccess.open(out.get_basename() + ".txt", FileAccess.WRITE)
	if txt != null:
		txt.store_string("\n".join(names) + "\n")
	var ok: bool = err == OK and bad == 0 and not sprites.is_empty()
	print("ART_GALLERY %s sprites=%d out=%s" % ["ok" if ok else "FAILED", sprites.size(), out])
	quit(0 if ok else 1)

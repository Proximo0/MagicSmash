extends RefCounted
## Writes every sprite frame to one picture, at 1x and enlarged, on a floor-dark background with labels: the art
## loop for sprites.gd, sprites_wizards.gd and sprites_enemies.gd. Each actor's animation is one strip (a row of
## its frames in order). Built from Images, so it needs no display and takes a few seconds:
##   godot --headless --path . -s tools/tool.gd -- sprite_sheet [--out=DIR] [--only=...] [--scale=4] [--name=sheet]
## --only keeps the rows whose name starts with one of the prefixes (wiz0, goblin, fx_bolt...).
## Prints map problems (an unknown letter, ragged rows, an atlas that does not fit), then one summary line.
## Exit code 1 when there is a problem.

const BG := Color("221b2e")
const BG_ALT := Color("1c1230")
const BG_LIGHT := Color("3b3150")
const LABEL := Color("7d705c")
const TITLE := Color("e8dcc0")
const MAX_W := 470
const GAP := 3
const LABEL_H := 9
## Pickups in reading order; the rest of the sheet is found from the keys.
const PICKUPS := ["xp", "coin", "gem", "potion", "chest", "chest_rare", "chest_ultra", "tome_fire", "tome_frost", "tome_storm",
	"tome_star", "tome_rune", "tome_orbit", "boot", "card", "urn"]
const WIZ_FRAMES := ["i0", "i1", "w0", "w1", "w2", "w3", "i0c", "i1c", "w0c", "w1c", "w2c", "w3c",
	"i0d", "i1d", "w0d", "w1d", "w2d", "w3d"]


func run(args: PackedStringArray) -> int:
	var out := "build/sprites"
	var only: PackedStringArray = []
	var scale := 4
	var name := "sheet"
	for a: String in args:
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",", false)
		elif a.begins_with("--scale="):
			scale = clampi(int(a.substr(8)), 2, 12)
		elif a.begins_with("--name="):
			name = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	Sprites.build_all()
	var problems: Array = Sprites.problems.duplicate()
	if Sprites.pack_error != "":
		problems.append(Sprites.pack_error)
	var sections := _sections(only)
	var sheet := _draw_sections(sections)
	sheet.save_png("%s/%s_1x.png" % [out, name])
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * scale, sheet.get_height() * scale, Image.INTERPOLATE_NEAREST)
	big.save_png("%s/%s_%dx.png" % [out, name, scale])
	for p: String in problems:
		print("SPRITE_SHEET problem: ", p)
	var atlas: Vector2 = Sprites.atlas().get_size() if Sprites.atlas() != null else Vector2.ZERO
	print("SPRITE_SHEET sprites=%d atlas=%dx%d problems=%d sheet=%dx%d out=%s/%s_1x.png and _%dx.png" % [
		Sprites.keys().size(), int(atlas.x), int(atlas.y), problems.size(), sheet.get_width(), sheet.get_height(),
		out, name, scale])
	return 1 if not problems.is_empty() else 0


## The sheet's contents: [[title, [[row label, [keys], [frame labels]], ...]], ...].
func _sections(only: PackedStringArray) -> Array:
	var keys: Array = Sprites.keys()
	var used := {}
	var wiz: Array = []
	for w in 4:
		for dir: String in ["down", "side", "up"]:
			var ks: Array = []
			var ls: Array = []
			for f: String in WIZ_FRAMES:
				var k := "wiz%d_%s_%s" % [w, dir, f]
				if Sprites.has(k):
					ks.append(k)
					ls.append(f)
			if not ks.is_empty():
				wiz.append(["wiz%d %s" % [w, dir], ks, ls])
	for k: String in keys:
		if k.begins_with("wiz"):
			used[k] = true
	var pick: Array = []
	var pk: Array = []
	var pl: Array = []
	for k: String in PICKUPS:
		for cand: String in keys:
			# A pickup and its extra frames (coin, coin_1, coin_2...).
			if cand == k or (cand.begins_with(k + "_") and cand.substr(k.length() + 1).is_valid_int()):
				pk.append(cand)
				pl.append(cand)
				used[cand] = true
	if not pk.is_empty():
		pick.append(["pickups", pk, pl])
	var magic := {}
	var actors := {}
	for k: String in keys:
		if used.has(k):
			continue
		var cut := k.rfind("_")
		var fam := k
		var lab := ""
		if cut > 0 and k.length() - cut - 1 <= 3:
			fam = k.substr(0, cut)
			lab = k.substr(cut + 1)
		var into: Dictionary = magic if k.begins_with("fx_") or k.begins_with("_") else actors
		if not into.has(fam):
			into[fam] = [fam, [], []]
		into[fam][1].append(k)
		into[fam][2].append(lab)
	for fam: Array in magic.values() + actors.values():
		_by_number(fam)
	var out: Array = []
	for sec: Array in [["WIZARDS", wiz], ["ENEMIES", actors.values()], ["PICKUPS", pick], ["MAGIC AND EFFECTS", magic.values()]]:
		var rows: Array = (sec[1] as Array).filter(func(r: Array) -> bool:
			if only.is_empty():
				return true
			for p: String in only:
				if String(r[0]).replace(" ", "_").begins_with(p) or String(r[1][0]).begins_with(p):
					return true
			return false)
		if not rows.is_empty():
			out.append([sec[0], rows])
	return out


## Puts a row whose frames are all numbered (fx_bolt_0 .. fx_bolt_15) in number order: the keys come sorted as text.
func _by_number(row: Array) -> void:
	var labels: Array = row[2]
	for lab: String in labels:
		if not lab.is_valid_int():
			return
	var order: Array = range(labels.size())
	order.sort_custom(func(a: int, b: int) -> bool: return int(labels[a]) < int(labels[b]))
	row[1] = order.map(func(i: int) -> String: return row[1][i])
	row[2] = order.map(func(i: int) -> String: return labels[i])


func _draw_sections(sections: Array) -> Image:
	# Lay out first (cells wrap at MAX_W), then draw.
	var label_w := 0
	for sec: Array in sections:
		for row: Array in sec[1]:
			label_w = maxi(label_w, _text_w(row[0]))
	label_w += 6
	var placed: Array = [] # [key, x, y (bottom of the sprite), label]
	var texts: Array = [] # [text, x, y, color]
	var bands: Array = [] # [y0, y1, alt]
	var y := 2
	var width := 120
	for sec: Array in sections:
		texts.append([sec[0], 3, y + 1, TITLE])
		y += 11
		var alt := false
		for row: Array in sec[1]:
			var x := label_w
			var row_h := 0
			var y0 := y
			var start := placed.size()
			texts.append([row[0], 3, y + 2, LABEL])
			for i in (row[1] as Array).size():
				var key: String = row[1][i]
				var size: Vector2 = (Sprites.region(key) as Rect2).size
				var lab: String = row[2][i]
				var cell := maxi(int(size.x), _text_w(lab)) + GAP
				if x + cell > MAX_W and x > label_w:
					for p: Array in placed.slice(start):
						p[2] += row_h
					y += row_h + LABEL_H + 2
					x = label_w
					row_h = 0
					start = placed.size()
				row_h = maxi(row_h, int(size.y))
				placed.append([key, x + (cell - GAP - int(size.x)) / 2, y, lab, cell - GAP, x])
				x += cell
				width = maxi(width, x + 2)
			for p: Array in placed.slice(start):
				p[2] += row_h
			y += row_h + LABEL_H + 2
			bands.append([y0 - 1, y - 1, alt])
			alt = not alt
		y += 4
	var img := Image.create(width, y, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	for b: Array in bands:
		if b[2]:
			img.fill_rect(Rect2i(0, b[0], width, b[1] - b[0]), BG_ALT)
	for p: Array in placed:
		var spr: Image = Sprites.image(p[0])
		# A lighter slab under every sprite's feet line shows it against the brightest floor too.
		img.fill_rect(Rect2i(p[5], p[2] - 2, p[4], 3), BG_LIGHT)
		img.blend_rect(spr, Rect2i(Vector2i.ZERO, spr.get_size()), Vector2i(p[1], p[2] - spr.get_height()))
		if p[3] != "":
			_text(img, p[3], p[5] + (p[4] - _text_w(p[3])) / 2, p[2] + 2, LABEL)
	for t: Array in texts:
		_text(img, t[0], t[1], t[2], t[3])
	return img


func _text_w(s: String) -> int:
	return int(PixelFont.text_width(s.to_upper()))


func _text(img: Image, s: String, x: int, y: int, c: Color) -> void:
	s = s.to_upper()
	for i in s.length():
		for cell: Vector2 in PixelFont.cells(s[i]):
			var px := x + i * 6 + int(cell.x)
			var py := y + int(cell.y)
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, c)

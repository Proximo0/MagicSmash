class_name ArenaBg
## Bakes the arena backdrop for each act of the run into a single texture:
## Act I the Ossuary (bone-lined crypt), Act II the Burning Library (bookshelf walls, plank floor, scattered
## pages), Act III the Starless Sanctum (stained glass, black marble, a gold summoning circle under the comet).

const OSSUARY := 0
const LIBRARY := 1
const SANCTUM := 2

## [wall a, wall b, mortar, floor a, floor b, floor seam, top shadow, rune colour] per act.
const PALETTES := [
	[Color("3b3058"), Color("4a3c6b"), Color("150f24"), Color("463a5e"), Color("54476f"), Color("2a2140"), Color("1a1230"), Color("3d6b86")],
	[Color("4a2a22"), Color("5a3428"), Color("1c0e0a"), Color("6b4128"), Color("7a4c2e"), Color("3a2014"), Color("1a0c08"), Color("c8642a")],
	[Color("1e2440"), Color("262e52"), Color("0a0c1a"), Color("161a30"), Color("1c2240"), Color("0b0d1c"), Color("06070f"), Color("d8b04a")],
]

static var _cache := {}


static func build(act: int = OSSUARY) -> ImageTexture:
	act = clampi(act, 0, PALETTES.size() - 1)
	if _cache.has(act):
		return _cache[act]
	var w := int(G.WORLD.x)
	var h := int(G.WORLD.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 + act * 101
	var pal: Array = PALETTES[act]
	var a := G.ARENA
	img.fill(Color("120c1e") if act != SANCTUM else Color("05060d"))
	_walls(img, a, pal, act)
	_floor(img, a, pal, act, rng)
	match act:
		OSSUARY:
			_ossuary(img, a, rng)
		LIBRARY:
			_library(img, a, rng)
		SANCTUM:
			_sanctum(img, a, rng)
	_circle(img, a, pal[7], act)
	# Depth shading under the top wall and down the side walls.
	for y in range(int(a.position.y), int(a.position.y) + 8):
		for x in range(int(a.position.x), int(a.end.x)):
			var k := 1.0 - float(y - a.position.y) / 8.0
			img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.45 * k))
	for x0 in [int(a.position.x), int(a.end.x) - 1]:
		for y in range(int(a.position.y), int(a.end.y)):
			img.set_pixel(x0, y, img.get_pixel(x0, y).darkened(0.35))
	_pillars(img, w, h, pal, act)
	var tex := ImageTexture.create_from_image(img)
	_cache[act] = tex
	return tex


static func _walls(img: Image, a: Rect2, pal: Array, act: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(0, h):
		for x in w:
			if a.has_point(Vector2(x, y)):
				continue
			var c: Color
			if act == LIBRARY:
				c = _shelf_px(x, y, pal)
			else:
				var row := (y + 42) / 6
				var off := 6 if row % 2 == 1 else 0
				var bx := (x + off) % 12
				var by := (y + 42) % 6
				var brick_id := ((x + off) / 12) * 31 + row * 17
				var base: Color = (pal[0] as Color).lerp(pal[1], float((brick_id * 7919) % 13) / 13.0)
				c = base
				if bx == 0 or by == 5:
					c = pal[2]
				elif by == 0:
					c = base.lightened(0.18)
				elif bx == 11:
					c = base.darkened(0.2)
			if y < a.position.y:
				c = c.lerp(pal[6], clampf((a.position.y - y) / 26.0, 0.0, 1.0) * 0.55)
			img.set_pixel(x, y, c)


## Bookshelf walls: dark wood boards every 10 px with rows of coloured spines between.
static func _shelf_px(x: int, y: int, pal: Array) -> Color:
	var ry := (y + 42) % 10
	if ry >= 8:
		return Color("2a140c") if ry == 9 else Color("6a3a20")
	var book := (x * 3 + (y + 42) / 10 * 7) / 4
	var hsh := (book * 2654435761) % 1000
	if hsh < 90:
		return pal[2]
	var spines := [Color("7a2030"), Color("2a4a6a"), Color("3a5a2a"), Color("6a5020"), Color("4a2a5a"), Color("7a4020")]
	var c: Color = spines[hsh % spines.size()]
	var tall := 2 + hsh % 3
	if ry < 8 - (8 - tall) and ry < 2 and hsh % 2 == 0:
		return pal[2]
	if (x * 3 + (y + 42) / 10 * 7) % 4 == 0:
		return c.darkened(0.35)
	if ry == 3 and hsh % 3 == 0:
		return Color("d8b04a").darkened(0.2)
	return c


static func _floor(img: Image, a: Rect2, pal: Array, act: int, rng: RandomNumberGenerator) -> void:
	var tile := 20
	for y in range(int(a.position.y), int(a.end.y)):
		for x in range(int(a.position.x), int(a.end.x)):
			var lx := x - int(a.position.x)
			var ly := y - int(a.position.y)
			var c: Color
			if act == LIBRARY:
				# Planks running across the room, staggered joints and a few nail heads.
				var plank := ly / 8
				var joint := (lx + (plank * 37) % 60) % 60
				var shade := float((plank * 2654435761) % 1000) / 1000.0
				var base: Color = (pal[3] as Color).lerp(pal[4], shade)
				c = base
				if ly % 8 == 0:
					c = pal[5]
				elif joint == 0:
					c = pal[5]
				elif (lx * 7 + ly * 13) % 23 == 0:
					c = base.darkened(0.12)
				elif joint == 2 and ly % 8 == 4:
					c = Color("2a1a10")
			else:
				var row := ly / tile
				var off := (tile / 2) if row % 2 == 1 else 0
				var tx := (lx + off) % tile
				var ty := ly % tile
				var tid := ((lx + off) / tile) * 7 + row * 13
				var shade := float((tid * 2654435761) % 1000) / 1000.0
				var base: Color = (pal[3] as Color).lerp(pal[4], shade)
				var n := rng.randf()
				c = base
				if n < 0.08:
					c = base.darkened(0.08)
				elif n > 0.94:
					c = base.lightened(0.06)
				if tx == 0 or ty == 0:
					c = pal[5]
				elif tx == 1 or ty == 1:
					c = base.lightened(0.1 if act != SANCTUM else 0.16)
				elif tx == tile - 1 or ty == tile - 1:
					c = base.darkened(0.15)
				if act == SANCTUM and (tx == 10 and ty == 10):
					c = Color("d8b04a").darkened(0.3)
			img.set_pixel(x, y, c)


## Act I: cracks, moss, bone piles along the walls and skull niches in the top wall.
static func _ossuary(img: Image, a: Rect2, rng: RandomNumberGenerator) -> void:
	for i in _scaled(40, a):
		var p := Vector2i(rng.randi_range(int(a.position.x) + 4, int(a.end.x) - 4), rng.randi_range(int(a.position.y) + 4, int(a.end.y) - 4))
		var dir := Vector2i([1, -1][rng.randi() % 2], [1, -1][rng.randi() % 2])
		for k in rng.randi_range(3, 8):
			if a.has_point(Vector2(p)):
				img.set_pixelv(p, Color("2a2140"))
			p += Vector2i(dir.x if rng.randf() < 0.7 else 0, dir.y if rng.randf() < 0.7 else 0)
	for i in _scaled(70, a):
		var p := Vector2i(rng.randi_range(int(a.position.x), int(a.end.x) - 1), rng.randi_range(int(a.position.y), int(a.end.y) - 1))
		img.set_pixelv(p, Color("3f5a4a") if rng.randf() < 0.6 else Color("4f7a52"))
	# Skull niches in the top wall.
	for nx: int in range(60, int(a.end.x) - 40, 110):
		_art(img, Vector2i(nx, 22), [
			"..kkkkk..",
			".kk...kk.",
			"kk.www.kk",
			"k.wwwww.k",
			"k.wkwkw.k",
			"k.wwwww.k",
			"k..w.w..k",
			"kkkkkkkkk",
		], {"k": Color("100a1a"), "w": Color("d8ceb0")})
	# Bone piles in the floor corners.
	for c: Vector2i in [Vector2i(int(a.position.x) + 6, int(a.end.y) - 10), Vector2i(int(a.end.x) - 20, int(a.end.y) - 10),
			Vector2i(int(a.position.x) + 6, int(a.position.y) + 10), Vector2i(int(a.end.x) - 20, int(a.position.y) + 10)]:
		for k in 14:
			var p: Vector2i = c + Vector2i(rng.randi_range(0, 13), rng.randi_range(0, 6))
			var bone := Color("d8ceb0") if rng.randf() < 0.7 else Color("a89c80")
			img.fill_rect(Rect2i(p, Vector2i(rng.randi_range(2, 4), 1)), bone)
		img.fill_rect(Rect2i(c + Vector2i(5, 1), Vector2i(4, 3)), Color("e8dcc0"))
		img.set_pixelv(c + Vector2i(6, 2), Color("100a1a"))
		img.set_pixelv(c + Vector2i(8, 2), Color("100a1a"))


## Act II: torn pages and ink on the planks, a long red runner down the middle, ash.
static func _library(img: Image, a: Rect2, rng: RandomNumberGenerator) -> void:
	var cy := int(a.get_center().y)
	for y in range(cy - 14, cy + 14):
		for x in range(int(a.position.x) + 10, int(a.end.x) - 10):
			var edge := y == cy - 14 or y == cy + 13
			var trim := y == cy - 12 or y == cy + 11
			var c := Color("5a1420") if not edge else Color("2a0810")
			if trim:
				c = Color("b08a3a")
			elif not edge and (x + y) % 9 == 0:
				c = c.lightened(0.06)
			img.set_pixel(x, y, c)
	for i in _scaled(26, a):
		var p := Vector2i(rng.randi_range(int(a.position.x) + 6, int(a.end.x) - 12), rng.randi_range(int(a.position.y) + 6, int(a.end.y) - 10))
		var pw := rng.randi_range(5, 8)
		var ph := rng.randi_range(4, 6)
		img.fill_rect(Rect2i(p, Vector2i(pw, ph)), Color("e8dcc0").darkened(rng.randf() * 0.15))
		for l in range(1, ph - 1, 2):
			img.fill_rect(Rect2i(p + Vector2i(1, l), Vector2i(pw - 2, 1)), Color("8a7a60"))
		if rng.randf() < 0.4:
			img.fill_rect(Rect2i(p + Vector2i(pw - 2, 0), Vector2i(2, 2)), Color("3a2a1a"))
	for i in _scaled(18, a):
		var p := Vector2i(rng.randi_range(int(a.position.x) + 6, int(a.end.x) - 6), rng.randi_range(int(a.position.y) + 6, int(a.end.y) - 6))
		img.fill_rect(Rect2i(p, Vector2i(rng.randi_range(2, 4), rng.randi_range(1, 3))), Color("120a14"))
	for i in _scaled(160, a):
		var p := Vector2i(rng.randi_range(int(a.position.x), int(a.end.x) - 1), rng.randi_range(int(a.position.y), int(a.end.y) - 1))
		img.set_pixelv(p, Color("2a1a14") if rng.randf() < 0.7 else Color("8a4020"))


## Act III: stained-glass windows in the top wall, gold inlay and starlight through cracks in the floor.
static func _sanctum(img: Image, a: Rect2, rng: RandomNumberGenerator) -> void:
	var glass := [Color("c0263a"), Color("2a5ad8"), Color("d8b04a"), Color("7b4dff"), Color("29a06b")]
	for wx: int in range(44, int(a.end.x) - 40, 80):
		var win := Rect2i(wx, 20, 30, 17)
		img.fill_rect(win.grow(1), Color("0a0c1a"))
		for y in range(win.position.y, win.end.y):
			for x in range(win.position.x, win.end.x):
				var lx := x - win.position.x
				var ly := y - win.position.y
				var arch := ly < 6 and absf(lx - 14.5) > sqrt(maxf(0.0, 36.0 - pow(6 - ly, 2))) * 2.5
				if arch:
					continue
				var lead := lx % 6 == 0 or ly % 5 == 0 or lx == 14 or lx == 15
				var cell: int = (lx / 6) * 3 + ly / 5 + wx
				img.set_pixel(x, y, Color("0a0c1a") if lead else (glass[cell % glass.size()] as Color).darkened(0.25))
		img.fill_rect(Rect2i(wx + 13, 23, 4, 4), Color("fff6e0"))
	for i in _scaled(34, a):
		var p := Vector2i(rng.randi_range(int(a.position.x) + 4, int(a.end.x) - 4), rng.randi_range(int(a.position.y) + 4, int(a.end.y) - 4))
		var dir := Vector2i([1, -1][rng.randi() % 2], [1, -1][rng.randi() % 2])
		for k in rng.randi_range(4, 10):
			if a.has_point(Vector2(p)):
				img.set_pixelv(p, Color("05060d"))
				if rng.randf() < 0.25:
					img.set_pixelv(p, Color("9ad8ff"))
			p += Vector2i(dir.x if rng.randf() < 0.7 else 0, dir.y if rng.randf() < 0.7 else 0)


## A decoration count drawn for the original 440x220 floor, scaled to this floor's area.
static func _scaled(n: int, a: Rect2) -> int:
	return int(n * a.get_area() / (440.0 * 220.0))


## The summoning circle in the middle of the floor: two rings, a pentagram and studs; larger and gold in Act III.
static func _circle(img: Image, a: Rect2, rune: Color, act: int) -> void:
	var c := a.get_center()
	var big := 1.4 if act == SANCTUM else 1.0
	for r in [44.0 * big, 38.0 * big]:
		for i in 720:
			var ang := deg_to_rad(i * 0.5)
			var p = c + Vector2(cos(ang), sin(ang) * 0.62) * r
			img.set_pixelv(Vector2i(p.round()), rune)
	for i in 5:
		var a0 := -PI / 2 + i * TAU / 5
		var a1 := -PI / 2 + (i + 2) * TAU / 5
		var p0 := c + Vector2(cos(a0), sin(a0) * 0.62) * 38.0 * big
		var p1 := c + Vector2(cos(a1), sin(a1) * 0.62) * 38.0 * big
		for t in 90:
			var p := p0.lerp(p1, t / 89.0)
			img.set_pixelv(Vector2i(p.round()), rune.darkened(0.15))
	for i in 12:
		var ang := i * TAU / 12
		var p := c + Vector2(cos(ang), sin(ang) * 0.62) * 41.0 * big
		img.fill_rect(Rect2i(Vector2i(p.round()) - Vector2i(1, 1), Vector2i(2, 2)), rune.lightened(0.15))


static func _pillars(img: Image, w: int, h: int, pal: Array, act: int) -> void:
	var gem: Color = [Color("3d6b86"), Color("c8642a"), Color("d8b04a")][act]
	for corner in [Vector2i(4, 22), Vector2i(w - 20, 22), Vector2i(4, h - 16), Vector2i(w - 20, h - 16)]:
		img.fill_rect(Rect2i(corner, Vector2i(16, 16)), (pal[2] as Color).lightened(0.1))
		img.fill_rect(Rect2i(corner + Vector2i(1, 1), Vector2i(14, 13)), (pal[1] as Color).lightened(0.15))
		img.fill_rect(Rect2i(corner + Vector2i(1, 1), Vector2i(14, 2)), (pal[1] as Color).lightened(0.35))
		img.fill_rect(Rect2i(corner + Vector2i(5, 5), Vector2i(6, 6)), gem)
		img.set_pixelv(corner + Vector2i(6, 6), gem.lightened(0.5))


static func _art(img: Image, at: Vector2i, rows: Array, pal: Dictionary) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if pal.has(row[x]):
				img.set_pixel(at.x + x, at.y + y, pal[row[x]])

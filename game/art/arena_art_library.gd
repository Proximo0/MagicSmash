class_name ArenaArtLibrary
extends RefCounted
## Act II, the Burning Library: a reading room of the wizards' tower with the fire already in it.
##
## A floor of long dark boards with a wine-red runner from door to door, crossing in the middle; a back wall of
## bookshelves, some of them charred; scorched patches where the floor has burned through to glowing embers;
## heaps of fallen books along the walls, the ones under the shelves alight. The light is the fire's.

const LIGHT_LEVELS := 32
## Light multipliers: [light on a scale of 0 to 15, colour]. Light 4 is open floor far from every fire.
const LIGHT := [
	[0, Color(0.30, 0.21, 0.28)],
	[4, Color(0.70, 0.58, 0.60)],
	[8, Color(1.06, 0.86, 0.66)],
	[12, Color(1.50, 1.12, 0.62)],
	[15, Color(1.90, 1.38, 0.60)],
]
## Book cloth: dark, mid and light of each colour.
const CLOTH := [
	["3a0f1e", "5a1a2a", "7a2a38"],
	["16301f", "264a32", "376446"],
	["161c3c", "24305a", "364478"],
	["4a3414", "6e5022", "8e6c34"],
	["2c183a", "44285a", "5c3a76"],
	["123030", "1f4a4a", "2e6464"],
]
## Where the floor has burned: [centre, radius across].
const BURNS := [
	[Vector2(236, 150), 34.0], [Vector2(590, 322), 40.0], [Vector2(142, 368), 22.0], [Vector2(672, 114), 24.0],
	[Vector2(434, 304), 22.0], [Vector2(318, 356), 17.0],
]
## Where fallen books burn at the foot of the shelves.
const FIRES := [150, 296, 504, 650]


static func bake(scene: Dictionary, ids: PackedInt32Array = PackedInt32Array()) -> Image:
	var a := Rect2i(G.ARENA)
	var cv := ArenaArtCanvas.new(int(G.WORLD.x), int(G.WORLD.y))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2718
	var pal := _palette(cv)
	var lamps: Array = []
	scene.flames = []
	scene.fire = Color(1.0, 0.5, 0.15)
	scene.door_light = Color(1.0, 0.36, 0.12)
	_boards(cv, pal, a, rng, ids)
	_runners(cv, pal, a, rng)
	_burns(cv, pal, a)
	_shelves(cv, pal, a, rng, scene)
	ArenaArtRoom.rims(cv, pal, a, rng, scene, lamps, [108, 336], [176, 624])
	ArenaArtRoom.doors(cv, pal, a, scene, false)
	_clutter(cv, pal, a, rng, scene, lamps)
	ArenaArtRoom.lights(cv, a, lamps, scene)
	for b: Array in BURNS:
		var c: Vector2 = b[0]
		var r: float = b[1]
		cv.light_add(ArenaArtCanvas.pool(int(r * 2.2), int(r * 1.5), 0.36, 2.0), int(c.x), int(c.y), a)
		scene.glows.append([c, Vector2(r * 1.7, r * 1.1)])
	var img := cv.compose(ArenaArtCanvas.light_ramp(LIGHT, LIGHT_LEVELS))
	ArenaArtRoom.glazes(img, a, Color(0.85, 0.32, 0.1), Color(0, 0, 0, 0))
	if ids.size() == cv.w * cv.h:
		for i in ids.size():
			if not ArenaArtRoom.is_stone(pal, cv.px[i]):
				ids[i] = -1
	return img


static func _palette(cv: ArenaArtCanvas) -> Dictionary:
	var p := {}
	p.ink = cv.color(Color("0b0716"))
	# Floor boards, and the same wood a fraction darker and lighter (a block of 48, like every act's floor).
	var wood := ["0d0810", "1c1118", "2a1a22", "3a252b", "4b3236", "5e4244"]
	p.stone = cv.ramp(wood, 16)
	p.stone_dark = cv.ramp(ArenaArtRoom.shifted(wood, Color(-0.014, -0.010, -0.008)), 16)
	p.stone_light = cv.ramp(ArenaArtRoom.shifted(wood, Color(0.016, 0.010, 0.006)), 16)
	p.wall = cv.ramp(["0b0716", "170d1a", "22141f", "2f1d28", "3d2832", "4d353c"], 12)
	# Paper.
	p.bone = cv.ramp(["1f1626", "3a2f3d", "5c5148", "7d705c", "9d9078", "b7a98e", "d2c6a8", "e8dcc0"], 8)
	p.wax = cv.ramp(["6f6896", "a59cd2", "d8d0f4"], 3)
	p.iron = cv.ramp(["0b0716", "1a0f24", "2e2540", "5d5378"], 4)
	p.carpet = cv.ramp(["15070f", "270c17", "3a1220", "4d1a29", "632432", "7a3140"], 6)
	p.char = cv.ramp(["0a0610", "110a14", "1a1118", "241a1e"], 4)
	var cloth: Array[int] = []
	for c: Array in CLOTH:
		cloth.append(cv.ramp(c, 3))
	p.cloth = cloth
	p.ember = cv.ramp(["7a2f14", "c85a1e", "ff9a3c"], 3, true)
	# Firelight behind the doors: the rest of the tower is burning too.
	p.door = cv.ramp(["0b0716", "1f0a10", "3a1010", "5c1a10", "7e2a12", "a03c14"], 6, true)
	return p


# ================================================================= FLOOR ===
## Long boards laid across the room, each row broken at its own places.
static func _boards(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator, ids: PackedInt32Array) -> void:
	var style := {
		"ramps": [pal.stone, pal.stone_dark, pal.stone_light],
		"mid": 10, "joint": 4, "stray": 0.12, "dark": 0.5,
		"patch": ArenaArtFloor.patches(cv.w, cv.h, 53, 0.22, 4.0, 1),
		"patch_lo": 84, "patch_hi": 180,
		"bevel": 0.2, "chips": 0.0,
	}
	cv.rect(a.position.x, a.position.y, a.size.x, a.size.y, pal.stone + 6)
	var row_h := 10
	var next_id := 0
	for y in range(a.position.y, a.end.y, row_h):
		var row := ArenaArtFloor.pack(Rect2i(a.position.x, y, a.size.x, mini(row_h, a.end.y - y)), Vector2i(56, row_h), rng,
			[[1, 1, 4], [2, 1, 5], [3, 1, 2]], 0.42)
		ArenaArtFloor.paint(cv, row, style, rng, ids, next_id)
		var n := row.size() / ArenaArtFloor.STRIDE
		next_id += n
		# Nail heads at the board ends.
		for s in n:
			var x0 := row[s * ArenaArtFloor.STRIDE]
			var x1 := x0 + row[s * ArenaArtFloor.STRIDE + 2] - 2
			for nx: int in [x0 + 2, x1 - 2]:
				cv.shade(nx, y + 2, -2)
				cv.shade(nx, y + row_h - 4, -2)


## The runner from the top door to the bottom one and the runner across, with a medallion where they cross.
static func _runners(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator) -> void:
	var c := a.get_center()
	var hw := ArenaArtRoom.PATH_W / 2
	var hh := ArenaArtRoom.PATH_H / 2
	var worn := ArenaArtFloor.patches(cv.w, cv.h, 97, 0.07)
	_runner(cv, pal, Rect2i(c.x - hw, a.position.y + 16, hw * 2, a.size.y - 32), false, worn)
	_runner(cv, pal, Rect2i(a.position.x + 20, c.y - hh, a.size.x - 40, hh * 2), true, worn)
	# The medallion: a lozenge in a ring, woven where the two cross.
	var carpet: int = pal.carpet
	for y in range(c.y - hh + 3, c.y + hh - 3):
		for x in range(c.x - hw + 3, c.x + hw - 3):
			var dx := absf(x + 0.5 - c.x) / (hw - 4.0)
			var dy := absf(y + 0.5 - c.y) / (hh - 4.0)
			var ring := dx * dx + dy * dy
			var idx := carpet + 3
			if ring > 0.86 and ring < 1.0:
				idx = carpet + 5
			elif dx + dy < 0.62 and dx + dy > 0.5:
				idx = carpet + 4
			elif dx + dy <= 0.5:
				idx = carpet + (2 if (x + y) % 2 == 0 else 3)
			elif ring >= 1.0:
				continue
			cv.put(x, y, idx)
	# A few threadbare places.
	for i in 5:
		var p := Vector2i(c.x + rng.randi_range(-hw + 4, hw - 6), rng.randi_range(a.position.y + 30, a.end.y - 30))
		cv.shade_rect(p.x, p.y, rng.randi_range(3, 6), 1, -1)


static func _runner(cv: ArenaArtCanvas, pal: Dictionary, r: Rect2i, across: bool, worn: PackedByteArray) -> void:
	var carpet: int = pal.carpet
	var length := r.size.x if across else r.size.y
	var width := r.size.y if across else r.size.x
	for along in length:
		for over in width:
			var x := r.position.x + (along if across else over)
			var y := r.position.y + (over if across else along)
			var edge := mini(over, width - 1 - over)
			var idx := carpet + 3
			if edge == 0:
				idx = carpet + 1
			elif edge == 2 or edge == 5:
				idx = carpet + 5 if edge == 2 else carpet + 4
			elif edge > 7:
				# Lozenges down the middle.
				var u := absi((along + 9) % 18 - 9)
				var v := absi(over - width / 2)
				if u + v == 7:
					idx = carpet + 4
				elif u + v < 3:
					idx = carpet + 2
			if worn[y * cv.w + x] < 58 and edge > 0:
				idx -= 1
			cv.put(x, y, idx)
	# Fringe at both ends, and the carpet's shadow along its lower edge.
	for over in range(1, width - 1, 2):
		for end in 2:
			var along := -1 if end == 0 else length
			cv.put(r.position.x + (along if across else over), r.position.y + (over if across else along), carpet + 4)
	if across:
		cv.shade_rect(r.position.x, r.end.y, r.size.x, 1, -2)
	else:
		cv.shade_rect(r.end.x, r.position.y, 1, r.size.y, -1)


## Patches where the fire has been through the floor: charred boards, and embers still alive in the joints.
static func _burns(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i) -> void:
	var joint: int = pal.stone + 6
	for b: Array in BURNS:
		var c: Vector2 = b[0]
		var rx: float = b[1]
		var ry := rx * ArenaArtRoom.SQUASH
		for y in range(maxi(a.position.y, int(c.y - ry) - 2), mini(a.end.y, int(c.y + ry) + 3)):
			for x in range(maxi(a.position.x, int(c.x - rx) - 2), mini(a.end.x, int(c.x + rx) + 3)):
				var dx := (x + 0.5 - c.x) / rx
				var dy := (y + 0.5 - c.y) / ry
				var d := dx * dx + dy * dy + 0.2 * sin(x * 0.37 + c.x) * sin(y * 0.53 + c.y) + 0.08 * sin(x * 1.3) * sin(y * 1.7)
				if d >= 1.0:
					continue
				var cur := cv.at(x, y)
				var hot := sin(x * 0.61 + y * 0.23 + c.y) + sin(x * 0.17 - y * 0.71 + c.x)
				if d < 0.6:
					if cur == joint and hot > -0.2:
						cv.put(x, y, pal.ember + (2 if d < 0.2 and hot > 0.9 else (1 if hot > 0.5 else 0)))
					elif hot > 1.72 and d < 0.4:
						cv.put(x, y, pal.ember)
					elif d < 0.34 or ArenaArtRoom.dither((0.6 - d) * 4.0, x, y, 1) > 0:
						# Charcoal: the boards are still boards, their grain a shade apart.
						cv.put(x, y, pal.char + clampi(cur - int(pal.stone) - 8, 0, 3) if ArenaArtRoom.is_stone(pal, cur) else pal.char + 1)
					else:
						cv.shade(x, y, -4)
				elif d < 0.8 or ArenaArtRoom.dither((1.0 - d) * 5.0, x, y, 1) > 0:
					cv.shade(x, y, -2)
				else:
					cv.shade(x, y, -1)


# ============================================================== TOP WALL ===
## The back wall is bookshelves from end to end: three rows of books between uprights. Only the lowest row
## shows under the HUD. The books nearest the fires on the floor below are charred.
static func _shelves(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator, scene: Dictionary) -> void:
	var top := a.position.y
	var wall: int = pal.wall
	var door_x := int((World.DOORS[0] as Vector2).x)
	cv.rect(a.position.x, 0, a.size.x, top, wall + 1)
	cv.rect(a.position.x, 0, a.size.x, 1, pal.ink)
	cv.rect(a.position.x, 1, a.size.x, 1, wall + 8)
	cv.rect(a.position.x, 2, a.size.x, 1, wall + 6)
	cv.rect(a.position.x, 3, a.size.x, 1, wall + 3)
	var rows := [4, 15, 26]
	for y0: int in rows:
		cv.rect(a.position.x, y0 + 9, a.size.x, 1, wall + 9)
		cv.rect(a.position.x, y0 + 10, a.size.x, 1, wall + 4)
	cv.rect(a.position.x, top - 1, a.size.x, 1, wall + 3)
	var block := ArenaArtRoom.DOOR_HALF + 5 + 12
	var span := 74
	var x := a.position.x
	while x < a.end.x:
		var x1 := mini(x + span, a.end.x)
		# An upright, then books up to the next one.
		cv.rect(x, 4, 5, top - 5, wall + 7)
		cv.rect(x, 4, 1, top - 5, wall + 9)
		cv.rect(x + 4, 4, 1, top - 5, wall + 4)
		if x1 > door_x - block and x < door_x + block:
			x = x1
			continue
		var burnt := 0.0
		for fx: int in FIRES:
			burnt = maxf(burnt, 0.85 - absf(fx - (x + x1) * 0.5) / 60.0)
		for y0: int in rows:
			_books(cv, pal, x + 5, x1, y0, 9, rng, burnt if y0 == 26 else burnt * 0.5)
		x = x1
	cv.rect(a.end.x - 5, 4, 5, top - 5, wall + 7)
	cv.rect(a.end.x - 1, 4, 1, top - 5, wall + 4)
	ArenaArtRoom.masonry(cv, Rect2i(door_x - block, 4, block * 2, top - 4), wall, 6, 10, 14, 26, rng)
	ArenaArtRoom.top_door(cv, pal, door_x, top, scene, false)


## One shelf of books from x0 to x1, standing on the board under row y0 + n. `burnt` is the share that are charred.
static func _books(cv: ArenaArtCanvas, pal: Dictionary, x0: int, x1: int, y0: int, n: int, rng: RandomNumberGenerator, burnt: float) -> void:
	var cloth: Array[int] = pal.cloth
	var x := x0
	while x < x1 - 1:
		var roll := rng.randf()
		if roll < 0.06:
			x += rng.randi_range(3, 6)
			continue
		var charred := rng.randf() < burnt
		if roll < 0.13 and x + 8 <= x1:
			# A few books lying flat on top of each other.
			for j in rng.randi_range(2, 4):
				var fam: int = pal.char if charred else cloth[rng.randi() % cloth.size()]
				var wd := rng.randi_range(6, 8)
				cv.rect(x, y0 + n - 2 * (j + 1), wd, 2, fam + 1)
				cv.rect(x, y0 + n - 2 * (j + 1), wd, 1, fam + 2)
				cv.put(x + wd - 1, y0 + n - 2 * (j + 1) + 1, pal.bone + (2 if charred else 5))
			x += 9
			continue
		var bw: int = [2, 3, 3, 3, 4, 4, 5][rng.randi() % 7]
		bw = mini(bw, x1 - x)
		var bh := rng.randi_range(n - 3, n)
		var fam: int = pal.char if charred else cloth[rng.randi() % cloth.size()]
		var yb := y0 + n - bh
		cv.rect(x, yb, bw, bh, fam + 1)
		cv.rect(x, yb, 1, bh, fam + 2)
		if bw >= 3:
			cv.rect(x + bw - 1, yb, 1, bh, fam)
			if not charred and rng.randf() < 0.55:
				cv.rect(x + 1, yb + 2 + rng.randi() % 2, bw - 2, 1, pal.bone + 4)
		if charred and rng.randf() < 0.35:
			cv.put(x + rng.randi() % bw, yb + rng.randi() % bh, pal.ember + rng.randi() % 2)
		x += bw


# =============================================================== CLUTTER ===
## Fallen books along the walls and in the corners; the heaps under the shelves are burning.
static func _clutter(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator, scene: Dictionary, lamps: Array) -> void:
	var l := a.position.x
	var r := a.end.x
	var t := a.position.y
	var b := a.end.y
	for fx: int in FIRES:
		_book_pile(cv, pal, Rect2i(fx - 16, t + 1, 32, 10), 12, rng, Vector2i(0, -1), 0.8)
		scene.flames.append([Vector2(fx, t + 5), ArenaArtRoom.FIRE])
		scene.flames.append([Vector2(fx - 8, t + 4), ArenaArtRoom.CANDLE])
		scene.flames.append([Vector2(fx + 9, t + 6), ArenaArtRoom.CANDLE])
		for k in 5:
			cv.put(fx + rng.randi_range(-9, 9), t + rng.randi_range(2, 8), pal.ember + rng.randi() % 3)
		lamps.append([fx, 30, ArenaArtRoom.LAMP_SHELF])
	_book_pile(cv, pal, Rect2i(l + 1, t + 1, 44, 18), 22, rng, Vector2i(-1, -1), 0.2)
	_book_pile(cv, pal, Rect2i(r - 46, t + 1, 45, 18), 20, rng, Vector2i(1, -1), 0.5)
	_book_pile(cv, pal, Rect2i(l + 1, b - 22, 50, 21), 24, rng, Vector2i(-1, 1), 0.0)
	_book_pile(cv, pal, Rect2i(r - 40, b - 18, 39, 17), 16, rng, Vector2i(1, 1), 0.3)
	_book_pile(cv, pal, Rect2i(l + 1, 280, 14, 30), 8, rng, Vector2i(-1, 0), 0.0)
	_book_pile(cv, pal, Rect2i(r - 15, 150, 14, 34), 9, rng, Vector2i(1, 0), 0.2)
	_book_pile(cv, pal, Rect2i(250, b - 11, 40, 10), 10, rng, Vector2i(0, 1), 0.0)
	_book_pile(cv, pal, Rect2i(500, b - 11, 36, 10), 9, rng, Vector2i(0, 1), 0.4)
	ArenaArtRoom.rubble(cv, pal, Rect2i(r - 60, t + 14, 26, 12), 6, rng, false)
	ArenaArtRoom.rubble(cv, pal, Rect2i(l + 30, b - 30, 24, 10), 5, rng, false)
	ArenaArtRoom.cobweb(cv, pal, Vector2i(l, b - 1), 1, -1, 11)
	ArenaArtRoom.cobweb(cv, pal, Vector2i(r - 1, b - 1), -1, -1, 12)


## A heap of books in `r`, leaning on a wall; `charred` is the share of them that are burnt black.
static func _book_pile(cv: ArenaArtCanvas, pal: Dictionary, r: Rect2i, n: int, rng: RandomNumberGenerator, lean: Vector2i, charred: float) -> void:
	var cloth: Array[int] = pal.cloth
	var items: Array = []
	for i in n:
		var rows: Array = ArenaArtProps.BOOKS[rng.randi() % ArenaArtProps.BOOKS.size()]
		var p := ArenaArtRoom.in_heap(r, ArenaArtCanvas.rows_width(rows), rows.size(), rng, lean)
		var burnt := rng.randf() < charred
		var fam: int = pal.char if burnt else cloth[rng.randi() % cloth.size()]
		var map := {"c": fam + 2, "C": fam, "p": pal.bone + (2 if burnt else 5), "P": pal.bone + (1 if burnt else 3)}
		items.append([p.y + rows.size(), p.x, p.y, rows, map, rng.randf() < 0.5])
	items.sort_custom(func(m: Array, k: Array) -> bool: return m[0] < k[0])
	for it: Array in items:
		ArenaArtRoom.drop(cv, it[3], it[1], it[2], it[4], it[5])

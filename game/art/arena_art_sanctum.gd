class_name ArenaArtSanctum
extends RefCounted
## Act III, the Starless Sanctum: the top of the tower, open to a sky with nothing in it.
##
## A chequered floor of night-blue marble, veined, with ways of paler marble edged in gold running from the
## doors to a seal inlaid in gold; a back wall of tall windows onto the dark between pilasters; cold star-fire
## in the bowls and on the tapers; violet light behind the doors.

const LIGHT_LEVELS := 32
## Light multipliers: [light on a scale of 0 to 15, colour]. Light 4 is open floor far from every lamp.
const LIGHT := [
	[0, Color(0.22, 0.24, 0.42)],
	[4, Color(0.60, 0.63, 0.76)],
	[8, Color(0.92, 0.98, 1.12)],
	[12, Color(1.28, 1.40, 1.52)],
	[15, Color(1.58, 1.72, 1.80)],
]
## The marble squares.
const TILE := Vector2i(38, 26)


static func bake(scene: Dictionary, ids: PackedInt32Array = PackedInt32Array()) -> Image:
	var a := Rect2i(G.ARENA)
	var cv := ArenaArtCanvas.new(int(G.WORLD.x), int(G.WORLD.y))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pal := _palette(cv)
	var lamps: Array = []
	scene.flames = []
	scene.flame = [Color("4a78e8"), Color("9fd0ff"), Color("f2fbff"), Color("2a3a9a")]
	scene.fire = Color(0.4, 0.62, 1.0)
	scene.door_light = Color(0.72, 0.3, 1.0)
	scene.seal_light = Color(1.0, 0.82, 0.45)
	_floor(cv, pal, a, rng, ids)
	ArenaArtRoom.seal(cv, pal, a, scene, lamps, ids)
	_back_wall(cv, pal, a, rng, scene, lamps)
	ArenaArtRoom.rims(cv, pal, a, rng, scene, lamps, [116, 344], [200, 600])
	ArenaArtRoom.doors(cv, pal, a, scene, false)
	ArenaArtRoom.rubble(cv, pal, Rect2i(a.end.x - 52, a.position.y + 2, 50, 14), 10, rng, true)
	ArenaArtRoom.rubble(cv, pal, Rect2i(a.position.x + 2, a.end.y - 14, 44, 12), 8, rng, false)
	ArenaArtRoom.lights(cv, a, lamps, scene)
	var img := cv.compose(ArenaArtCanvas.light_ramp(LIGHT, LIGHT_LEVELS))
	ArenaArtRoom.glazes(img, a, Color(0.5, 0.2, 0.8), Color(1.0, 0.8, 0.4, 0.09))
	if ids.size() == cv.w * cv.h:
		for i in ids.size():
			if not ArenaArtRoom.is_stone(pal, cv.px[i]):
				ids[i] = -1
	return img


static func _palette(cv: ArenaArtCanvas) -> Dictionary:
	var p := {}
	p.ink = cv.color(Color("05040e"))
	# Marble, and the same marble a fraction darker and lighter (a block of 48, like every act's floor).
	var marble := ["090a16", "14172c", "1f2440", "2b3152", "384066", "49527c"]
	p.stone = cv.ramp(marble, 16)
	p.stone_dark = cv.ramp(ArenaArtRoom.shifted(marble, Color(-0.012, -0.012, -0.011)), 16)
	p.stone_light = cv.ramp(ArenaArtRoom.shifted(marble, Color(0.010, 0.010, 0.011)), 16)
	p.wall = cv.ramp(["05040e", "0e1024", "171a36", "21264a", "2c335e", "394274"], 12)
	p.bone = cv.ramp(["14142a", "2a2c48", "474c6c", "686f90", "8a93b2", "a8b2cc", "c8d2e6", "e4ecf8"], 8)
	# The tapers are shards of pale crystal.
	p.wax = cv.ramp(["4a5a8a", "8fb0e0", "e0f0ff"], 3)
	p.iron = cv.ramp(["05040e", "1a1a34", "2e3458", "6a78a8"], 4)
	p.slate = cv.ramp(["060712", "0f1124", "181b38", "23284c", "303760"], 8)
	p.gold = cv.ramp(["241c10", "3a2e18", "564422"], 3, true)
	p.ember = cv.ramp(["2a3a9a", "5a8ae0", "c0e8ff"], 3, true)
	p.door = cv.ramp(["05040e", "140a24", "24103c", "381858", "4e2278", "642c96"], 6, true)
	p.seal = cv.ramp(["4a3a1a", "8a6a2a", "e0b050"], 3, true)
	return p


# ================================================================= FLOOR ===
static func _floor(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator, ids: PackedInt32Array) -> void:
	var c := a.get_center()
	var style := {
		"ramps": [pal.stone, pal.stone_dark, pal.stone_light],
		"mid": 9, "joint": 3, "stray": 0.0, "dark": 0.0,
		"patch": ArenaArtFloor.patches(cv.w, cv.h, 29, 0.05, 1.2),
		"patch_lo": 76, "patch_hi": 186,
		"bevel": 0.15, "chips": 0.02,
	}
	cv.rect(a.position.x, a.position.y, a.size.x, a.size.y, pal.stone + 6)
	var px0 := c.x - ArenaArtRoom.PATH_W / 2
	var px1 := c.x + ArenaArtRoom.PATH_W / 2
	var py0 := c.y - ArenaArtRoom.PATH_H / 2
	var py1 := c.y + ArenaArtRoom.PATH_H / 2
	var next_id := 0
	for q in 4:
		var qx0 := a.position.x if q % 2 == 0 else px1
		var qx1 := px0 if q % 2 == 0 else a.end.x
		var qy0 := a.position.y if q < 2 else py1
		var qy1 := py0 if q < 2 else a.end.y
		var quad := Rect2i(qx0, qy0, qx1 - qx0, qy1 - qy0)
		var tiles := ArenaArtFloor.pack(quad, TILE, rng, [[1, 1, 1]], 0.0)
		# The dark squares of the chequer, counted from the middle of the room outwards.
		var ncx := maxi(1, roundi(float(quad.size.x) / TILE.x))
		for s in tiles.size() / ArenaArtFloor.STRIDE:
			var col := s % ncx if q % 2 == 1 else ncx - 1 - s % ncx
			var row := s / ncx if q >= 2 else 99 - s / ncx
			if (col + row) % 2 == 1:
				tiles[s * ArenaArtFloor.STRIDE + 4] |= ArenaArtFloor.DARKER
		ArenaArtFloor.paint(cv, tiles, style, rng, ids, next_id)
		next_id += tiles.size() / ArenaArtFloor.STRIDE
	# The ways: long slabs of the paler marble.
	var ways := PackedInt32Array()
	ArenaArtRoom.way(ways, Rect2i(px0, a.position.y, ArenaArtRoom.PATH_W, py0 - a.position.y), false, false, rng)
	ArenaArtRoom.way(ways, Rect2i(px0, py1, ArenaArtRoom.PATH_W, a.end.y - py1), false, true, rng)
	ArenaArtRoom.way(ways, Rect2i(a.position.x, py0, px0 - a.position.x, ArenaArtRoom.PATH_H), true, false, rng)
	ArenaArtRoom.way(ways, Rect2i(px1, py0, a.end.x - px1, ArenaArtRoom.PATH_H), true, true, rng)
	ways.append_array(PackedInt32Array([px0, py0, ArenaArtRoom.PATH_W, ArenaArtRoom.PATH_H, ArenaArtFloor.WORN]))
	ArenaArtFloor.paint(cv, ways, style, rng, ids, next_id)
	# A line of gold let into the marble along both edges of each way.
	var gold: int = pal.gold
	for x: int in [px0 + 3, px1 - 5]:
		cv.rect(x, a.position.y + 13, 1, py0 - a.position.y - 13, gold + 1)
		cv.rect(x, py1, 1, a.end.y - py1 - 13, gold + 1)
	for y: int in [py0 + 3, py1 - 5]:
		cv.rect(a.position.x + 13, y, px0 - a.position.x - 13, 1, gold + 1)
		cv.rect(px1, y, a.end.x - px1 - 13, 1, gold + 1)
	# Veins.
	for i in 26:
		var start := Vector2(rng.randf_range(a.position.x + 10.0, a.end.x - 10.0), rng.randf_range(a.position.y + 10.0, a.end.y - 10.0))
		_vein(cv, pal, start, rng.randf() * TAU, rng.randi_range(30, 90), rng, 1 if i % 4 != 0 else 2)


## A vein in the marble: a pale thread that wanders and now and then forks.
static func _vein(cv: ArenaArtCanvas, pal: Dictionary, start: Vector2, ang: float, length: int, rng: RandomNumberGenerator, lift: int) -> void:
	var p := start
	var dir := ang
	var last := Vector2i(-99, -99)
	for i in length:
		var q := Vector2i(roundi(p.x), roundi(p.y))
		if q != last:
			if ArenaArtRoom.is_stone(pal, cv.at(q.x, q.y)) and (cv.at(q.x, q.y) - int(pal.stone)) % 16 > 7:
				cv.shade(q.x, q.y, lift)
			last = q
		dir = lerp_angle(dir + rng.randf_range(-0.35, 0.35), ang, 0.12)
		p += Vector2(cos(dir), sin(dir) * 0.7)
		if lift > 1 and i > 8 and rng.randf() < 0.03:
			_vein(cv, pal, p, dir + (0.7 if rng.randf() < 0.5 else -0.7), length / 3, rng, 1)


# ============================================================== TOP WALL ===
## The back wall: dressed stone with a tall window onto the dark in every bay, a plinth with a line of gold
## along it, and crystal tapers standing at its foot in four of the bays.
static func _back_wall(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator, scene: Dictionary, lamps: Array) -> void:
	var top := a.position.y
	var wall: int = pal.wall
	var door_x := int((World.DOORS[0] as Vector2).x)
	ArenaArtRoom.masonry(cv, Rect2i(a.position.x, 4, a.size.x, top - 4), wall, 6, 9, 18, 34, rng)
	cv.rect(a.position.x, 0, a.size.x, 1, pal.ink)
	cv.rect(a.position.x, 1, a.size.x, 1, wall + 5)
	cv.rect(a.position.x, 2, a.size.x, 1, wall + 8)
	cv.rect(a.position.x, 3, a.size.x, 1, wall + 3)
	cv.rect(a.position.x, 30, a.size.x, top - 30, wall + 6)
	cv.rect(a.position.x, 30, a.size.x, 1, wall + 9)
	cv.rect(a.position.x, 33, a.size.x, 1, pal.gold + 2)
	cv.rect(a.position.x, top - 1, a.size.x, 1, wall + 3)
	var block := ArenaArtRoom.DOOR_HALF + 5 + 12
	var span := 76
	var lit := {1: -11, 3: 12, 6: -12, 8: 11}
	for k in a.size.x / span:
		var x0 := a.position.x + k * span
		var mid := x0 + 10 + (span - 10) / 2
		if absi(x0 + 5 - door_x) > block + 4:
			ArenaArtRoom.pilaster(cv, pal, x0, 10, top, false)
		if x0 + span <= door_x - block or x0 + 10 >= door_x + block:
			_window(cv, pal, mid, 6, 28)
			if lit.has(k):
				var rows: Array = ArenaArtProps.CANDLES
				var cx: int = mid + int(lit[k])
				var cy := top - rows.size()
				cv.stamp(rows, cx - 4, cy, {"w": pal.wax + 1, "x": pal.wax, "f": pal.wax + 2})
				for wk: Vector2i in ArenaArtProps.CANDLES_WICKS:
					scene.flames.append([Vector2(cx - 4 + wk.x, cy + wk.y), ArenaArtRoom.CANDLE])
				lamps.append([cx, 31, ArenaArtRoom.LAMP_SHELF])
	ArenaArtRoom.pilaster(cv, pal, a.end.x - 10, 10, top, false)
	ArenaArtRoom.top_door(cv, pal, door_x, top, scene, false)


## A tall pointed window with nothing behind it.
static func _window(cv: ArenaArtCanvas, pal: Dictionary, mid: int, y0: int, y1: int) -> void:
	var wall: int = pal.wall
	var half := 7.0
	var rise := 9.0
	for y in range(y0 - 1, y1 + 1):
		for x in range(mid - 9, mid + 9):
			var dx := absf(x + 0.5 - mid)
			var up := maxf(0.0, y0 + rise - y)
			# Two arcs meeting in a point.
			var inside := y < y1 and dx + up * up / (rise * rise) * half < half
			var frame := y <= y1 and dx + up * up / ((rise + 1.5) * (rise + 1.5)) * (half + 1.5) < half + 1.5
			if inside:
				cv.put(x, y, pal.ink if dx > 0.6 or y < y0 + 8 else wall + 4)
			elif frame:
				cv.put(x, y, wall + (9 if x < mid else 4))
	cv.rect(mid - 9, y1, 18, 1, wall + 9)
	cv.rect(mid - 9, y1 + 1, 18, 1, wall + 3)

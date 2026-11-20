class_name ArenaArtOssuary
extends RefCounted
## Act I, the Ossuary: the bone-lined crypt under the wizards' tower, lit by candles.
##
## Flagstones with four paved ways from the doors to the summoning seal in the middle; a back wall of skull
## shelves between pilasters; low side and front walls seen from above; four doors that are black stairwells
## with a red glow coming up them; candles on the skull shelves and fire bowls on the side walls; bones, rubble
## and cobwebs along the walls and in the corners, where the light does not reach.

## How many steps the light falls in between a candle and the darkest corner. With this many, the dither
## between two steps is too faint to read as a texture on the floor.
const LIGHT_LEVELS := 32
## Light multipliers: [light on a scale of 0 to 15, colour]. Light 4 is open floor far from every candle.
const LIGHT := [
	[0, Color(0.27, 0.25, 0.38)],
	[4, Color(0.64, 0.63, 0.68)],
	[8, Color(1.00, 0.89, 0.73)],
	[12, Color(1.48, 1.22, 0.72)],
	[15, Color(1.90, 1.52, 0.72)],
]

const MOTIF_CROSS := [
	"..#..",
	"..#..",
	"#####",
	"..#..",
	"..#..",
	"..#..",
	"..#..",
]
const MOTIF_SKULL := [
	".#####.",
	"#.....#",
	"#.#.#.#",
	"#.....#",
	".#.#.#.",
	".#####.",
	"..#.#..",
]
const MOTIF_GLASS := [
	"#####",
	"#...#",
	".#.#.",
	"..#..",
	".#.#.",
	"#...#",
	"#####",
]
const MOTIFS := [MOTIF_CROSS, MOTIF_SKULL, MOTIF_GLASS, MOTIF_CROSS]


static func bake(scene: Dictionary, ids: PackedInt32Array = PackedInt32Array()) -> Image:
	var a := Rect2i(G.ARENA)
	var cv := ArenaArtCanvas.new(int(G.WORLD.x), int(G.WORLD.y))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var pal := _palette(cv)
	# Lamps the painters leave for ArenaArtRoom.lights: [x, y, kind].
	var lamps: Array = []
	scene.flames = []
	_floor(cv, pal, a, rng, ids)
	_cracks(cv, pal, a, rng)
	ArenaArtRoom.seal(cv, pal, a, scene, lamps, ids)
	_top_wall(cv, pal, a, rng, scene, lamps)
	ArenaArtRoom.rims(cv, pal, a, rng, scene, lamps)
	ArenaArtRoom.doors(cv, pal, a, scene)
	_clutter(cv, pal, a, rng)
	ArenaArtRoom.lights(cv, a, lamps, scene)
	var img := cv.compose(ArenaArtCanvas.light_ramp(LIGHT, LIGHT_LEVELS))
	ArenaArtRoom.glazes(img, a)
	if ids.size() == cv.w * cv.h:
		for i in ids.size():
			if not ArenaArtRoom.is_stone(pal, cv.px[i]):
				ids[i] = -1
	return img


static func _palette(cv: ArenaArtCanvas) -> Dictionary:
	var p := {}
	p.ink = cv.color(Color("0b0716"))
	# Floor stone, and the same stone a fraction of a shade darker and cooler, and lighter and warmer: slabs
	# differ by less than a whole shade. The three must stay together (the stone map reads a block of 48).
	var stone := ["120a1f", "221b2e", "2e2540", "3b3150", "4a4063", "5d5378"]
	p.stone = cv.ramp(stone, 16)
	p.stone_dark = cv.ramp(ArenaArtRoom.shifted(stone, Color(-0.015, -0.012, -0.006)), 16)
	p.stone_light = cv.ramp(ArenaArtRoom.shifted(stone, Color(0.016, 0.011, 0.008)), 16)
	# The seal's own stone: a blue-black slate.
	p.slate = cv.ramp(["0e0c1c", "1a1930", "262844", "343858", "464a6e"], 8)
	p.wall = cv.ramp(["0b0716", "1a0f24", "241d34", "302a48", "3d385a", "4d486e"], 12)
	p.bone = cv.ramp(["1f1626", "3a2f3d", "5c5148", "7d705c", "9d9078", "b7a98e", "d2c6a8", "e8dcc0"], 8)
	# Wax is cut bluer than it looks: the candle light it stands in is so warm that it comes out ivory.
	p.wax = cv.ramp(["6f6896", "a59cd2", "d8d0f4"], 3)
	p.iron = cv.ramp(["0b0716", "1a0f24", "2e2540", "5d5378"], 4)
	p.moss = cv.ramp(["122a1a", "1c4a22", "2f7a2a"], 3)
	p.earth = cv.ramp(["0d0812", "1a1018", "281a20", "36242a"], 4)
	p.ember = cv.ramp(["7a2f14", "c85a1e", "ff9a3c"], 3, true)
	# The red that comes up the stairwells behind the doors, from nothing to a dull glow.
	p.door = cv.ramp(["0b0716", "1c0812", "30091a", "4a0e20", "64122a", "7a1226"], 6, true)
	# The seal's engraved lines: a groove with a little cold light at the bottom of it.
	p.seal = cv.ramp(["193844", "23505e", "3f93a3"], 3, true)
	return p


static func _floor(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator, ids: PackedInt32Array) -> void:
	var c := a.get_center()
	var style := {
		"ramps": [pal.stone, pal.stone_dark, pal.stone_light],
		"mid": 10, "joint": 5, "stray": 0.1, "dark": 0.5,
		"patch": ArenaArtFloor.patches(cv.w, cv.h, 71, 0.09),
		"patch_lo": 70, "patch_hi": 190,
		"bevel": 0.5, "chips": 0.12,
	}
	cv.rect(a.position.x, a.position.y, a.size.x, a.size.y, pal.stone + 5)
	var sizes := [[2, 2, 30], [3, 2, 22], [2, 1, 10], [1, 1, 3], [1, 2, 6], [3, 3, 9], [4, 2, 8], [2, 3, 10], [4, 3, 3]]
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
		var slabs := ArenaArtFloor.pack(Rect2i(qx0, qy0, qx1 - qx0, qy1 - qy0), Vector2i(20, 14), rng, sizes)
		_mark_use(slabs, a, c)
		ArenaArtFloor.paint(cv, slabs, style, rng, ids, next_id)
		next_id += slabs.size() / ArenaArtFloor.STRIDE
	# The paved ways: long smooth slabs, worn by feet, some of them grave slabs with their carving half gone.
	var ways := PackedInt32Array()
	ArenaArtRoom.way(ways, Rect2i(px0, a.position.y, ArenaArtRoom.PATH_W, py0 - a.position.y), false, false, rng)
	ArenaArtRoom.way(ways, Rect2i(px0, py1, ArenaArtRoom.PATH_W, a.end.y - py1), false, true, rng)
	ArenaArtRoom.way(ways, Rect2i(a.position.x, py0, px0 - a.position.x, ArenaArtRoom.PATH_H), true, false, rng)
	ArenaArtRoom.way(ways, Rect2i(px1, py0, a.end.x - px1, ArenaArtRoom.PATH_H), true, true, rng)
	ways.append_array(PackedInt32Array([px0, py0, ArenaArtRoom.PATH_W, ArenaArtRoom.PATH_H, ArenaArtFloor.WORN]))
	style.stray = 0.0
	style.chips = 0.05
	ArenaArtFloor.paint(cv, ways, style, rng, ids, next_id)
	var n_ways := ways.size() / ArenaArtFloor.STRIDE
	for s in n_ways - 1:
		var k := s * ArenaArtFloor.STRIDE
		var r := Rect2i(ways[k], ways[k + 1], ways[k + 2] - 1, ways[k + 3] - 1)
		if s % 3 == 1 and r.size.x >= 30 and r.size.y >= 26:
			_ledger(cv, r, rng)
	_moss(cv, pal, a, rng)


## Slabs near the paved ways and the seal are worn smooth; slabs by the walls are damp and dark.
static func _mark_use(slabs: PackedInt32Array, a: Rect2i, c: Vector2i) -> void:
	for s in slabs.size() / ArenaArtFloor.STRIDE:
		var k := s * ArenaArtFloor.STRIDE
		var cx := slabs[k] + slabs[k + 2] / 2
		var cy := slabs[k + 1] + slabs[k + 3] / 2
		var d_wall := mini(mini(cx - a.position.x, a.end.x - cx), mini(cy - a.position.y, a.end.y - cy))
		var ex := float(cx - c.x) / (ArenaArtRoom.SEAL_RX + 34.0)
		var ey := float(cy - c.y) / ((ArenaArtRoom.SEAL_RX + 34.0) * ArenaArtRoom.SQUASH)
		if ex * ex + ey * ey < 1.0:
			slabs[k + 4] |= ArenaArtFloor.WORN
		elif d_wall < 26:
			slabs[k + 4] |= ArenaArtFloor.DAMP


## A grave slab: a carved border, an emblem and lines of lettering nobody can read any more.
static func _ledger(cv: ArenaArtCanvas, r: Rect2i, rng: RandomNumberGenerator) -> void:
	var b := r.grow(-3)
	ArenaArtRoom.carve_h(cv, b.position.x + 1, b.position.y, b.size.x - 2)
	ArenaArtRoom.carve_h(cv, b.position.x + 1, b.end.y - 1, b.size.x - 2)
	ArenaArtRoom.carve_v(cv, b.position.x, b.position.y + 1, b.size.y - 2)
	ArenaArtRoom.carve_v(cv, b.end.x - 1, b.position.y + 1, b.size.y - 2)
	var motif: Array = MOTIFS[rng.randi() % MOTIFS.size()]
	var mw := ArenaArtCanvas.rows_width(motif)
	var wide := r.size.x > r.size.y + 8
	var mx := b.position.x + 5 if wide else b.position.x + (b.size.x - mw) / 2
	var my := b.position.y + (b.size.y - motif.size()) / 2 if wide else b.position.y + 4
	cv.stamp(motif, mx, my, {"#": -2})
	# Lettering: short strokes in rows, some rows worn away.
	var tx0 := mx + mw + 5 if wide else b.position.x + 5
	var tx1 := b.end.x - 5
	var ty := b.position.y + 5 if wide else my + motif.size() + 4
	while ty < b.end.y - 4:
		var x := tx0 + rng.randi_range(0, 3)
		while x < tx1 - 2:
			var n := rng.randi_range(2, 5)
			if rng.randf() < 0.75:
				cv.shade_rect(x, ty, mini(n, tx1 - x), 1, -2)
			x += n + rng.randi_range(1, 2)
		ty += 4


## Moss in the joints where the floor is damp, by the walls.
static func _moss(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator) -> void:
	var stone: int = pal.stone
	for i in 90:
		var along := rng.randf()
		var into := rng.randi_range(2, 34)
		var p := Vector2i.ZERO
		match rng.randi() % 4:
			0: p = Vector2i(a.position.x + int(along * a.size.x), a.position.y + into)
			1: p = Vector2i(a.position.x + int(along * a.size.x), a.end.y - into)
			2: p = Vector2i(a.position.x + into, a.position.y + int(along * a.size.y))
			_: p = Vector2i(a.end.x - into, a.position.y + int(along * a.size.y))
		for yy in range(-2, 3):
			for xx in range(-4, 5):
				var cur := cv.at(p.x + xx, p.y + yy)
				# Joints are the dark shades of the first stone ramp.
				if cur >= stone + 3 and cur <= stone + 6 and rng.randf() < 0.75:
					cv.put(p.x + xx, p.y + yy, pal.moss + (1 if rng.randf() < 0.3 else 0))


static func _cracks(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator) -> void:
	# Long cracks running in from the walls.
	var starts := [
		[Vector2(96, a.position.y + 3), 1.1, 70], [Vector2(668, a.position.y + 3), 2.0, 60],
		[Vector2(a.position.x + 3, 300), -0.3, 64], [Vector2(a.end.x - 4, 168), 2.9, 72],
		[Vector2(250, a.end.y - 4), -1.2, 56], [Vector2(560, a.end.y - 4), -1.9, 66],
		[Vector2(a.end.x - 4, 392), 3.5, 44], [Vector2(a.position.x + 3, 92), 0.5, 40],
	]
	for s: Array in starts:
		ArenaArtRoom.crack(cv, pal, s[0], s[1], s[2], rng, 0)
	# Where something heavy came down once: cracks out of one point.
	var hit := Vector2(236, 322)
	for i in 5:
		ArenaArtRoom.crack(cv, pal, hit, i * TAU / 5.0 + rng.randf_range(-0.3, 0.3), rng.randi_range(16, 34), rng, 1)
	cv.shade_rect(int(hit.x) - 1, int(hit.y) - 1, 3, 2, -3)
	var hit2 := Vector2(574, 132)
	for i in 4:
		ArenaArtRoom.crack(cv, pal, hit2, 0.4 + i * TAU / 4.0 + rng.randf_range(-0.3, 0.3), rng.randi_range(12, 26), rng, 1)
	cv.shade_rect(int(hit2.x) - 1, int(hit2.y), 2, 2, -3)


## The back wall, seen from the front: a cornice, two courses of big stones with an arched niche in each bay, a
## ledge, a long shelf of skulls just above the floor, and a plinth. Pilasters divide it into bays. Its lowest
## eleven rows are the part the HUD never covers, so the skulls and their candles live there.
static func _top_wall(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator, scene: Dictionary, lamps: Array) -> void:
	var top := a.position.y
	var wall: int = pal.wall
	var door_x := int((World.DOORS[0] as Vector2).x)
	ArenaArtRoom.masonry(cv, Rect2i(a.position.x, 4, a.size.x, 20), wall, 6, 10, 16, 30, rng)
	# Cornice.
	cv.rect(a.position.x, 0, a.size.x, 1, pal.ink)
	cv.rect(a.position.x, 1, a.size.x, 1, wall + 4)
	for x in range(a.position.x, a.end.x):
		cv.put(x, 2, wall + (7 if (x / 3) % 2 == 0 else 4))
	cv.rect(a.position.x, 3, a.size.x, 1, wall + 2)
	# Bays between pilasters, three each side of the door: [first x, last x + 1, candle offset from the middle
	# of the bay (0: no candles), what the niche above holds].
	var block := ArenaArtRoom.DOOR_HALF + 5 + 12
	var left0 := a.position.x + 10
	var span := (door_x - block - left0 - 20) / 3
	var bays: Array = []
	var pilasters: Array[int] = [a.position.x, a.end.x - 10]
	for i in 3:
		var bx0 := left0 + i * (span + 10)
		var bx1 := bx0 + span if i < 2 else door_x - block
		bays.append([bx0, bx1, [0, 10, -18][i], i])
		bays.append([2 * door_x - bx1, 2 * door_x - bx0, [0, -14, 22][i], i + 3])
		if i > 0:
			pilasters.append(bx0 - 10)
			pilasters.append(2 * door_x - bx0)
	for bay: Array in bays:
		_bay(cv, pal, top, bay[0], bay[1], bay[2], bay[3], rng, scene, lamps)
	for px: int in pilasters:
		ArenaArtRoom.pilaster(cv, pal, px, 10, top, false)
	ArenaArtRoom.top_door(cv, pal, door_x, top, scene)


## One bay of the back wall between x0 and x1.
static func _bay(cv: ArenaArtCanvas, pal: Dictionary, top: int, x0: int, x1: int, candle_at: int, kind: int,
		rng: RandomNumberGenerator, scene: Dictionary, lamps: Array) -> void:
	var wall: int = pal.wall
	var mid := (x0 + x1) / 2
	# The arched niche in the upper wall.
	var half := 11
	for y in range(7, 24):
		for x in range(mid - half - 1, mid + half + 1):
			var dx := absf(x + 0.5 - mid)
			var dy := maxf(0.0, 15.0 - y)
			var d := dx * dx / float(half * half) + dy * dy / 64.0
			if d < 1.0:
				cv.put(x, y, wall + (1 if (x + y * 3) % 7 != 0 else 2))
			elif dx * dx / float((half + 1.4) * (half + 1.4)) + dy * dy / 88.0 < 1.0:
				cv.put(x, y, wall + (9 if x < mid else 5))
	var dim := ArenaArtProps.bone_map(pal.bone, pal.ink, -1)
	match kind % 3:
		0:
			# A cobwebbed niche with one lonely skull.
			cv.stamp(ArenaArtProps.SKULL_TILT, mid - 3, 17, dim)
		1:
			# A pyramid of small skulls.
			cv.stamp(ArenaArtProps.SKULL_SMALL, mid - 8, 19, dim)
			cv.stamp(ArenaArtProps.SKULL_SMALL, mid - 2, 19, dim)
			cv.stamp(ArenaArtProps.SKULL_SMALL, mid + 4, 19, dim)
			cv.stamp(ArenaArtProps.SKULL_SMALL, mid - 5, 14, dim)
			cv.stamp(ArenaArtProps.SKULL_SMALL, mid + 1, 14, dim)
			cv.stamp(ArenaArtProps.SKULL_SMALL, mid - 2, 9, dim)
		2:
			# Stacked long bones, seen end on, with a skull set among them.
			for y in range(10, 24, 3):
				for x in range(mid - half + 2, mid + half - 1, 3):
					var dx := absf(x + 1.0 - mid)
					var dy := maxf(0.0, 15.0 - y)
					if dx * dx / float((half - 2) * (half - 2)) + dy * dy / 40.0 < 1.0:
						cv.put(x, y, pal.bone + 3)
						cv.put(x + 1, y, pal.bone + 2)
						cv.put(x, y + 1, pal.bone + 2)
						cv.put(x + 1, y + 1, pal.bone + 1)
			cv.stamp(ArenaArtProps.SKULL_FRONT, mid - 3, 15, dim)
	# Ledge, shelf recess, sill, plinth.
	cv.rect(x0, 24, x1 - x0, 1, wall + 9)
	cv.rect(x0, 25, x1 - x0, 1, wall + 3)
	cv.rect(x0, 26, x1 - x0, 9, wall + 6)
	var sx0 := x0 + 4
	var sx1 := x1 - 4
	cv.rect(sx0, 26, sx1 - sx0, 8, pal.ink)
	for x in range(sx0, sx1):
		if (x * 7 + 3) % 11 < 3:
			cv.put(x, 26 + (x * 5) % 3, wall + 1)
	cv.rect(sx0 - 1, 26, 1, 8, wall + 4)
	cv.rect(sx1, 26, 1, 8, wall + 8)
	cv.rect(x0, 34, x1 - x0, 1, wall + 9)
	cv.rect(x0, 35, x1 - x0, top - 35, wall + 6)
	cv.rect(x0, top - 1, x1 - x0, 1, wall + 4)
	var jx := x0 + rng.randi_range(8, 20)
	while jx < x1 - 4:
		cv.rect(jx, 35, 1, top - 35, wall + 3)
		jx += rng.randi_range(16, 28)
	# The skulls, with candles burning among them in the lit bays.
	var bm := ArenaArtProps.bone_map(pal.bone, pal.ink, -1)
	var x := sx0 + 1 + rng.randi_range(0, 2)
	var candle_x := mid + candle_at
	while x + 7 <= sx1 - 1:
		if candle_at != 0 and absi(x + 4 - candle_x) < 6:
			var rows: Array = ArenaArtProps.CANDLES
			cv.stamp(rows, x, 34 - rows.size(), {"w": pal.wax + 1, "x": pal.wax, "f": pal.ink})
			for wk: Vector2i in ArenaArtProps.CANDLES_WICKS:
				scene.flames.append([Vector2(x + wk.x, 34 - rows.size() + wk.y), ArenaArtRoom.CANDLE])
			# Wax running over the sill.
			cv.put(x + 1, 34, pal.wax + 1)
			cv.put(x + 1, 35, pal.wax)
			cv.put(x + 6, 34, pal.wax + 1)
			lamps.append([x + 3, 30, ArenaArtRoom.LAMP_SHELF])
			x += 9
			continue
		var r := rng.randf()
		if r < 0.1:
			# A gap: a bone or two lying where a skull was.
			cv.stamp(ArenaArtProps.BONE_SHORT, x, 32, bm)
		else:
			var rows: Array = ArenaArtProps.SKULLS[rng.randi() % ArenaArtProps.SKULLS.size()]
			cv.stamp(rows, x, 34 - rows.size(), bm, rng.randf() < 0.4)
		x += 8 + rng.randi_range(0, 1)


## Bones, rubble and cobwebs: along the walls and heaped in the corners, never out in the room.
static func _clutter(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator) -> void:
	var l := a.position.x
	var r := a.end.x
	var t := a.position.y
	var b := a.end.y
	# Corners. Top left: bones spilled from the shelf. Top right: fallen masonry. Bottom left: a broken floor.
	# Bottom right: a heap of skulls.
	var ul := Vector2i(-1, -1)
	_bone_pile(cv, pal, Rect2i(l + 1, t + 1, 54, 22), 30, 6, rng, ul, 2)
	_bone_pile(cv, pal, Rect2i(l + 1, t + 20, 16, 34), 10, 2, rng, Vector2i(-1, 0))
	ArenaArtRoom.rubble(cv, pal, Rect2i(r - 58, t - 4, 56, 18), 16, rng, true)
	ArenaArtRoom.rubble(cv, pal, Rect2i(r - 20, t + 10, 18, 34), 8, rng, false)
	_broken_floor(cv, pal, Rect2i(l + 4, b - 34, 46, 28), rng)
	ArenaArtRoom.rubble(cv, pal, Rect2i(l + 2, b - 16, 60, 14), 12, rng, false)
	_bone_pile(cv, pal, Rect2i(r - 58, b - 26, 56, 25), 34, 12, rng, Vector2i(1, 1), 5)
	_bone_pile(cv, pal, Rect2i(r - 17, b - 60, 16, 36), 10, 3, rng, Vector2i(1, 0), 1)
	# Along the walls, between the lights and clear of the doors.
	_bone_pile(cv, pal, Rect2i(588, t + 1, 44, 12), 16, 3, rng, Vector2i(0, -1), 1)
	_bone_pile(cv, pal, Rect2i(l + 1, 286, 14, 34), 10, 2, rng, Vector2i(-1, 0), 1)
	_bone_pile(cv, pal, Rect2i(r - 15, 160, 14, 30), 9, 2, rng, Vector2i(1, 0))
	_bone_pile(cv, pal, Rect2i(118, b - 13, 50, 12), 16, 3, rng, Vector2i(0, 1), 1)
	ArenaArtRoom.rubble(cv, pal, Rect2i(292, b - 10, 30, 9), 5, rng, false)
	ArenaArtRoom.rubble(cv, pal, Rect2i(l + 1, 168, 12, 22), 4, rng, false)
	_bone_pile(cv, pal, Rect2i(474, b - 12, 34, 11), 10, 2, rng, Vector2i(0, 1))
	ArenaArtRoom.rubble(cv, pal, Rect2i(222, t + 1, 26, 8), 4, rng, false)
	# Scraps along every wall.
	for i in 90:
		var along := rng.randf()
		var into := rng.randi_range(1, 13)
		var p := Vector2i.ZERO
		match rng.randi() % 4:
			0: p = Vector2i(l + int(along * a.size.x), t + into)
			1: p = Vector2i(l + int(along * a.size.x), b - into)
			2: p = Vector2i(l + into, t + int(along * a.size.y))
			_: p = Vector2i(r - into, t + int(along * a.size.y))
		if not ArenaArtRoom.is_stone(pal, cv.at(p.x, p.y)) or not ArenaArtRoom.is_stone(pal, cv.at(p.x + 1, p.y)):
			continue
		if rng.randf() < 0.45:
			cv.shade(p.x + 1, p.y + 1, -2)
			cv.put(p.x, p.y, pal.bone + 1)
			if rng.randf() < 0.5:
				cv.put(p.x + 1, p.y, pal.bone)
		else:
			cv.shade(p.x, p.y + 1, -2)
			cv.shade(p.x + 1, p.y + 1, -2)
			cv.shade(p.x, p.y, 2)
			cv.shade(p.x + 1, p.y, -1)
	ArenaArtRoom.cobweb(cv, pal, Vector2i(l, t), 1, 1, 15)
	ArenaArtRoom.cobweb(cv, pal, Vector2i(r - 1, t), -1, 1, 13)
	ArenaArtRoom.cobweb(cv, pal, Vector2i(l, b - 1), 1, -1, 11)
	ArenaArtRoom.cobweb(cv, pal, Vector2i(r - 1, b - 1), -1, -1, 12)
	ArenaArtRoom.cobweb(cv, pal, Vector2i(l + 10, 4), 1, 1, 9)
	ArenaArtRoom.cobweb(cv, pal, Vector2i(r - 11, 4), -1, 1, 10)


## A heap of bones in `r`: a dark mass of them, long bones lying every way on top of it, skulls last. `lean` is
## the wall (or corner) the heap is piled against; `heads` of the skulls are full size.
static func _bone_pile(cv: ArenaArtCanvas, pal: Dictionary, r: Rect2i, bones: int, skulls: int, rng: RandomNumberGenerator,
		lean: Vector2i = Vector2i.ZERO, heads: int = 0) -> void:
	var bm := ArenaArtProps.bone_map(pal.bone, pal.ink, -1)
	var dim := ArenaArtProps.bone_map(pal.bone, pal.ink, -2)
	_heap_mass(cv, pal, r, lean, rng)
	var items: Array = []
	var maps := [ArenaArtProps.BONE_FLAT, ArenaArtProps.BONE_SHORT, ArenaArtProps.BONE_DIAG, ArenaArtProps.BONE_SHORT,
		ArenaArtProps.BONE_FLAT, ArenaArtProps.BONE_UP, ArenaArtProps.RIBS]
	for i in bones:
		var rows: Array = maps[rng.randi() % maps.size()]
		var p := ArenaArtRoom.in_heap(r, ArenaArtCanvas.rows_width(rows), rows.size(), rng, lean)
		items.append([p.y + rows.size(), p.x, p.y, rows, dim if i % 3 == 0 else bm, rng.randf() < 0.5])
	var small := [ArenaArtProps.SKULL_SMALL, ArenaArtProps.SKULL_SMALL_SIDE, ArenaArtProps.SKULL_DOME, ArenaArtProps.SKULL_SMALL]
	var big := [ArenaArtProps.SKULL_FRONT, ArenaArtProps.SKULL_TILT, ArenaArtProps.SKULL_LEFT, ArenaArtProps.SKULL_JAWLESS]
	for i in skulls:
		var rows: Array = big[rng.randi() % big.size()] if i < heads else small[rng.randi() % small.size()]
		var p := ArenaArtRoom.in_heap(r, ArenaArtCanvas.rows_width(rows), rows.size(), rng, lean)
		items.append([p.y + rows.size() + 1, p.x, p.y, rows, bm, rng.randf() < 0.5])
	items.sort_custom(func(m: Array, n: Array) -> bool: return m[0] < n[0])
	for it: Array in items:
		ArenaArtRoom.drop(cv, it[3], it[1], it[2], it[4], it[5])


## The body of a heap: a shadow on the floor and, inside it, a dark tangle with a few pale flecks.
static func _heap_mass(cv: ArenaArtCanvas, pal: Dictionary, r: Rect2i, lean: Vector2i, rng: RandomNumberGenerator) -> void:
	var cx := r.position.x + r.size.x * (0.5 + 0.5 * lean.x)
	var cy := r.position.y + r.size.y * (0.5 + 0.5 * lean.y)
	var rx := r.size.x * (1.0 if lean.x != 0 else 0.5)
	var ry := r.size.y * (1.0 if lean.y != 0 else 0.5)
	var ph := rng.randf() * TAU
	for y in range(r.position.y - 1, r.end.y + 2):
		for x in range(r.position.x - 1, r.end.x + 2):
			var cur := cv.at(x, y)
			if not ArenaArtRoom.is_stone(pal, cur):
				continue
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d := dx * dx + dy * dy + 0.16 * sin(x * 0.9 + ph) * sin(y * 1.3 + ph * 1.7)
			if d < 0.5:
				var hsh := (x * 7 + y * 13 + (x * y) % 5) % 13
				cv.put(x, y, pal.bone + (1 if hsh < 2 else 0))
			elif d < 0.72:
				cv.shade(x, y, -3)
			elif d < 0.95:
				cv.shade(x, y, -1)


## Slabs gone from the floor: a hollow of bare earth, in shadow under the broken edge of the slabs above it and
## with their edge catching the light below it, and pieces of them lying in it.
static func _broken_floor(cv: ArenaArtCanvas, pal: Dictionary, r: Rect2i, rng: RandomNumberGenerator) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not _in_hollow(r, x, y) or not ArenaArtRoom.is_stone(pal, cv.at(x, y)):
				continue
			var e := 2 if (x * 3 + y * 5) % 7 == 0 else 1
			if not _in_hollow(r, x, y - 1) or not _in_hollow(r, x, y - 2) or not _in_hollow(r, x - 1, y):
				e = 0
			elif not _in_hollow(r, x, y - 4) or not _in_hollow(r, x - 3, y):
				e = 1
			cv.put(x, y, pal.earth + e)
	for y in range(r.position.y, r.end.y + 1):
		for x in range(r.position.x, r.end.x + 1):
			if not _in_hollow(r, x, y) and (_in_hollow(r, x, y - 1) or _in_hollow(r, x - 1, y)) and ArenaArtRoom.is_stone(pal, cv.at(x, y)):
				cv.shade(x, y, 2)
	var slab := ArenaArtProps.stone_map(pal.stone, 12)
	var pieces := [ArenaArtProps.RUBBLE_BLOCK, ArenaArtProps.RUBBLE_A, ArenaArtProps.RUBBLE_C, ArenaArtProps.RUBBLE_B,
		ArenaArtProps.RUBBLE_D, ArenaArtProps.RUBBLE_A, ArenaArtProps.RUBBLE_D]
	for i in pieces.size():
		var rows: Array = pieces[i]
		var p := ArenaArtRoom.in_heap(r.grow(-4), ArenaArtCanvas.rows_width(rows), rows.size(), rng)
		if cv.at(p.x, p.y) >= pal.earth and cv.at(p.x, p.y) < pal.earth + 4:
			ArenaArtRoom.drop(cv, rows, p.x, p.y, slab, i % 2 == 1)


static func _in_hollow(r: Rect2i, x: int, y: int) -> bool:
	var dx := (x - (r.position.x + r.size.x * 0.45)) / (r.size.x * 0.5)
	var dy := (y - (r.position.y + r.size.y * 0.55)) / (r.size.y * 0.5)
	return dx * dx + dy * dy + 0.22 * sin(x * 0.9) * sin(y * 1.3 + x * 0.4) < 0.8

class_name ArenaArtRoom
extends RefCounted
## The parts every act's arena is built from: the low side and front walls, the four doors, the summoning seal,
## fallen stone and cobwebs, and the light of the lamps along the walls. Each act (ArenaArtOssuary, ...) brings
## its own palette, floor and back wall and calls these with them.
##
## A palette is a Dictionary of first indices on the act's ArenaArtCanvas: "ink"; "stone" (three ramps of 16,
## one after the other: the floor); "wall" (12); "bone" (8); "wax" (3); "iron" (4); "slate" (8, the seal's own
## stone); and the ramps that glow: "ember" (3), "door" (6: the light behind the doors), "seal" (3).

## The summoning seal in the middle of the floor: its radius across, and how far the floor is tipped towards the
## viewer (a circle on the floor is this much flatter than it is wide).
const SEAL_RX := 66.0
const SQUASH := 0.62
## Radii of the seal's two engraved rings, of the star's points and of the small ring inside the star.
const SEAL_RINGS := [55.0, 43.0]
const SEAL_STAR := 40.0
const SEAL_EYE := 15.3
const SEAL_RUNES := 12
## The paved ways from the four doors to the seal: the width of the two that run up and down, and the height of
## the two that run across.
const PATH_W := 44
const PATH_H := 34
## Half the opening of the top and bottom doors (across) and of the side doors (up and down).
const DOOR_HALF := 22
const SIDE_DOOR_HALF := 20
## Kinds of flame the arena animates.
const CANDLE := ArenaArtLive.CANDLE
const FIRE := ArenaArtLive.FIRE
## Lamp kinds for `lights`: on the back wall's shelf, a fire bowl on the left or right wall, on the front wall,
## on the seal's kerb.
const LAMP_SHELF := 0
const LAMP_BOWL_LEFT := 1
const LAMP_BOWL_RIGHT := 2
const LAMP_FRONT := 3
const LAMP_SEAL := 4


## Ramp key colours (hex strings) moved by `by`: the same stone a fraction of a shade darker or lighter.
static func shifted(keys: Array, by: Color) -> Array:
	var out := []
	for k: String in keys:
		var c := Color(k)
		out.append(Color(maxf(0.0, c.r + by.r), maxf(0.0, c.g + by.g), maxf(0.0, c.b + by.b)))
	return out

## Is palette index `i` bare floor (any shade of the three floor ramps)?
static func is_stone(pal: Dictionary, i: int) -> bool:
	return i >= pal.stone and i < pal.stone + 48

## Ordered dither of a level in 0..top to an index.
static func dither(v: float, x: int, y: int, top: int) -> int:
	var b: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	return clampi(int(floorf(v + (b[((y & 3) << 2) | (x & 3)] + 0.5) / 16.0)), 0, top)

## Slabs along one paved way, a short threshold stone at the door end.
static func way(out: PackedInt32Array, r: Rect2i, across: bool, door_at_end: bool, rng: RandomNumberGenerator) -> void:
	var total := r.size.x if across else r.size.y
	var step := 11
	var lens: Array[int] = [step]
	var left := total - step
	var avg := 58.0 if across else 40.0
	var n := maxi(1, roundi(left / avg))
	for i in n:
		var l := left / (n - i)
		if i < n - 1:
			l += rng.randi_range(-6, 6)
		lens.append(l)
		left -= l
	if door_at_end:
		lens.reverse()
	var at := 0
	for l: int in lens:
		if across:
			out.append_array(PackedInt32Array([r.position.x + at, r.position.y, l, r.size.y, ArenaArtFloor.WORN]))
		else:
			out.append_array(PackedInt32Array([r.position.x, r.position.y + at, r.size.x, l, ArenaArtFloor.WORN]))
		at += l

## A carved line: the cut in shadow and the far edge of the cut catching the light.
static func carve_h(cv: ArenaArtCanvas, x: int, y: int, n: int) -> void:
	cv.shade_rect(x, y, n, 1, -2)
	cv.shade_rect(x, y + 1, n, 1, 1)

static func carve_v(cv: ArenaArtCanvas, x: int, y: int, n: int) -> void:
	cv.shade_rect(x, y, 1, n, -2)
	cv.shade_rect(x + 1, y, 1, n, 1)

## A crack wanders from `start` roughly along `ang` and may fork.
static func crack(cv: ArenaArtCanvas, pal: Dictionary, start: Vector2, ang: float, length: int, rng: RandomNumberGenerator, depth: int) -> void:
	var p := start
	var dir := ang
	var last := Vector2i(-99, -99)
	for i in length:
		var q := Vector2i(roundi(p.x), roundi(p.y))
		if q != last:
			if not is_stone(pal, cv.at(q.x, q.y)):
				return
			cv.shade(q.x, q.y, -4)
			if depth == 0 and i < 5:
				cv.shade(q.x + 1, q.y, -3)
			last = q
		dir = lerp_angle(dir + rng.randf_range(-0.5, 0.5), ang, 0.25)
		p += Vector2(cos(dir), sin(dir) * 0.7)
		if depth < 2 and i > 6 and rng.randf() < 0.035:
			crack(cv, pal, p, dir + (0.8 if rng.randf() < 0.5 else -0.8), int(length * 0.4), rng, depth + 1)

## The summoning seal: a kerb of wedge stones, a band of carved runes between two engraved rings, and a dark
## slate disc engraved with a five-pointed star. The grooves hold a little cold light. A candle burns on the
## kerb at each point of the star.
static func seal(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, scene: Dictionary, lamps: Array, ids: PackedInt32Array) -> void:
	var c := Vector2(a.get_center())
	var stone: int = pal.stone
	var slate: int = pal.slate
	var want_ids := ids.size() == cv.w * cv.h
	var wedges := 24
	var step := TAU / wedges
	var ry := int(ceil(SEAL_RX * SQUASH))
	for y in range(int(c.y) - ry - 1, int(c.y) + ry + 2):
		for x in range(int(c.x) - int(SEAL_RX) - 1, int(c.x) + int(SEAL_RX) + 2):
			var dx := x - c.x
			var dy := (y - c.y) / SQUASH
			var r := sqrt(dx * dx + dy * dy)
			if r > SEAL_RX:
				continue
			var k := y * cv.w + x
			var idx := 0
			var id := 9000
			if r > SEAL_RX - 1.1:
				idx = stone + 4
				id = -1
			elif r > SEAL_RINGS[0] + 0.5:
				# The kerb: wedge stones, every other one a shade apart.
				var ang := fposmod(atan2(dy, dx) + step * 0.5, TAU)
				var wedge := int(ang / step)
				var edge := minf(fposmod(ang, step), step - fposmod(ang, step)) * r
				idx = stone + 11 + wedge % 2
				id = 9001 + wedge
				if edge < 0.55:
					idx = stone + 5
					id = -1
				elif r > SEAL_RX - 2.4 and dy > 0.0:
					idx -= 1
				elif r < SEAL_RINGS[0] + 1.9 and dy < 0.0:
					idx -= 1
			elif r > SEAL_RINGS[1] + 0.5:
				idx = slate + 5
				id = -1
			else:
				idx = slate + 3
				id = -1
			cv.px[k] = idx
			if want_ids:
				ids[k] = id
	# Engraved rings.
	for ring: float in SEAL_RINGS:
		var n := int(ring * 7.0)
		for i in n:
			var ang := i * TAU / n
			groove(cv, pal, c + Vector2(cos(ang) * ring, sin(ang) * ring * SQUASH), 1)
	var n_eye := int(SEAL_EYE * 7.0)
	for i in n_eye:
		var ang := i * TAU / n_eye
		groove(cv, pal, c + Vector2(cos(ang) * SEAL_EYE, sin(ang) * SEAL_EYE * SQUASH), 0)
	# The star: five points, the first straight up.
	var pts: Array[Vector2] = []
	for i in 5:
		var ang := -PI / 2.0 + i * TAU / 5.0
		pts.append(c + Vector2(cos(ang) * SEAL_STAR, sin(ang) * SEAL_STAR * SQUASH))
	for i in 5:
		var p0 := pts[i]
		var p1 := pts[(i + 2) % 5]
		var n := int(p0.distance_to(p1) * 1.5)
		for j in n + 1:
			groove(cv, pal, p0.lerp(p1, float(j) / n), 1)
	for p in pts:
		groove(cv, pal, p, 2)
	# Runes carved in the band between the rings. They are dark here; the arena lights them in turn.
	var band := (SEAL_RINGS[0] + SEAL_RINGS[1]) / 2.0
	var runes: Array = []
	for i in SEAL_RUNES:
		var ang := (i + 0.5) * TAU / SEAL_RUNES
		var at := (c + Vector2(cos(ang) * band, sin(ang) * band * SQUASH) - Vector2(2, 3)).round()
		var seg: Array = Occult.RUNES[(i * 3 + 1) % Occult.RUNES.size()]
		var cut := {}
		for k in range(0, seg.size(), 4):
			var p0 := at + Vector2(seg[k], seg[k + 1])
			var p1 := at + Vector2(seg[k + 2], seg[k + 3])
			var n := int(maxf(absf(p1.x - p0.x), absf(p1.y - p0.y)))
			for j in n + 1:
				cut[p0.lerp(p1, float(j) / maxf(1.0, n)).round()] = true
		for q: Vector2 in cut:
			cv.shade(int(q.x), int(q.y), -4)
		runes.append(PackedVector2Array(cut.keys()))
	# A small four-pointed star in the middle: the four wands.
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		for t in 5:
			groove(cv, pal, c + Vector2(d.x * t * 1.5, d.y * t), 2 if t == 0 else 1)
	# A candle at each point of the star, out on the kerb.
	var kerb := (SEAL_RX + SEAL_RINGS[0]) / 2.0
	for i in 5:
		var ang := -PI / 2.0 + i * TAU / 5.0
		var at := (c + Vector2(cos(ang) * kerb, sin(ang) * kerb * SQUASH)).round()
		var rows: Array = ArenaArtProps.CANDLE_ONE if i % 2 == 0 else ArenaArtProps.CANDLE_STUB
		var wicks: Array = ArenaArtProps.CANDLE_ONE_WICKS if i % 2 == 0 else ArenaArtProps.CANDLE_STUB_WICKS
		var x0 := int(at.x) - 1
		var y0 := int(at.y) + 1 - rows.size()
		cv.shade_rect(x0 - 1, int(at.y) + 1, 5, 1, -2)
		cv.stamp(rows, x0, y0, {"w": pal.wax + 1, "x": pal.wax, "f": pal.ink})
		for wk: Vector2i in wicks:
			scene.flames.append([Vector2(x0 + wk.x, y0 + wk.y), CANDLE])
		lamps.append([int(at.x), int(at.y), LAMP_SEAL])
	# The grooves again as a picture of light with a soft edge: the arena lays it over them and lets it breathe.
	var bx := int(c.x - SEAL_RX) - 4
	var by := int(c.y - SEAL_RX * SQUASH) - 4
	var bw := int(SEAL_RX) * 2 + 8
	var bh := int(SEAL_RX * SQUASH) * 2 + 8
	var lines := Image.create(bw, bh, false, Image.FORMAT_RGBA8)
	lines.fill(Color(1, 1, 1, 0))
	for y in bh:
		for x in bw:
			var i := cv.at(bx + x, by + y)
			if i >= pal.seal and i <= pal.seal + 2:
				lines.set_pixel(x, y, Color(1, 1, 1, 0.55 + 0.22 * (i - int(pal.seal))))
	var halo: Image = lines.duplicate()
	halo.resize(bw / 2, bh / 2, Image.INTERPOLATE_BILINEAR)
	halo.resize(bw, bh, Image.INTERPOLATE_BILINEAR)
	halo.blend_rect(lines, Rect2i(0, 0, bw, bh), Vector2i.ZERO)
	scene.seal = {
		"c": c, "rx": SEAL_RX, "squash": SQUASH, "rings": SEAL_RINGS, "runes": runes,
		"tex": ImageTexture.create_from_image(halo), "at": Vector2(bx, by),
	}

## One pixel of an engraved line: the lit bottom of the groove, with the groove's shaded wall just above it.
static func groove(cv: ArenaArtCanvas, pal: Dictionary, p: Vector2, bright: int) -> void:
	var x := roundi(p.x)
	var y := roundi(p.y)
	var seal: int = pal.seal
	var up := cv.at(x, y - 1)
	if up < seal or up > seal + 2:
		cv.shade(x, y - 1, -3)
	var here := cv.at(x, y)
	if here >= seal and here <= seal + 2:
		cv.put(x, y, maxi(here, seal + bright))
	else:
		cv.put(x, y, seal + bright)

## Courses of big squared stones: joints a few shades down, each block a shade either way, a lit top edge.
static func masonry(cv: ArenaArtCanvas, r: Rect2i, first: int, base: int, course: int, wmin: int, wmax: int, rng: RandomNumberGenerator) -> void:
	cv.rect(r.position.x, r.position.y, r.size.x, r.size.y, first + base - 3)
	var y := r.position.y
	var row := 0
	while y < r.end.y:
		var ch := mini(course, r.end.y - y)
		var x := r.position.x - (rng.randi_range(0, wmax) if row % 2 == 1 else rng.randi_range(0, wmin / 2))
		while x < r.end.x:
			var bw := rng.randi_range(wmin, wmax)
			var x0 := maxi(x, r.position.x)
			var x1 := mini(x + bw - 1, r.end.x)
			if x1 - x0 >= 2:
				var s := base + rng.randi_range(-1, 0)
				cv.rect(x0, y, x1 - x0, ch - 1, first + s)
				cv.rect(x0, y, x1 - x0, 1, first + s + 1)
				if rng.randf() < 0.3:
					cv.rect(x0 + rng.randi_range(1, 4), y + ch - 2, rng.randi_range(3, maxi(3, x1 - x0 - 6)), 1, first + s - 1)
				if rng.randf() < 0.14 and x1 - x0 > 8:
					# A chipped corner.
					cv.put(x1 - 1, y, first + base - 3)
					cv.put(x1 - 2, y, first + s)
			x += bw
		y += ch
		row += 1

## A pilaster on the back wall, `pw` wide from x: lit on its left edge, a capital, a base, and its shadow on
## the wall to its right. With `skull` a skull is set in it just above the floor.
static func pilaster(cv: ArenaArtCanvas, pal: Dictionary, x: int, pw: int, top: int, skull: bool) -> void:
	var wall: int = pal.wall
	# Its shadow on the wall to the right.
	cv.shade_rect(x + pw, 4, 2, top - 4, -1)
	cv.rect(x, 0, pw, top, wall + 7)
	cv.rect(x, 0, 1, top, wall + 9)
	cv.rect(x + 1, 0, 1, top, wall + 8)
	cv.rect(x + pw - 2, 0, 2, top, wall + 5)
	cv.rect(x + pw - 1, 0, 1, top, wall + 4)
	# Capital.
	cv.rect(x - 1, 1, pw + 2, 4, wall + 7)
	cv.rect(x - 1, 1, pw + 2, 1, wall + 9)
	cv.rect(x - 1, 4, pw + 2, 1, wall + 4)
	cv.rect(x - 1, 0, pw + 2, 1, pal.ink)
	# Banding where the ledge crosses it, and the base.
	cv.rect(x, 24, pw, 1, wall + 9)
	cv.rect(x, 25, pw, 1, wall + 4)
	cv.rect(x - 1, 32, pw + 2, top - 32, wall + 7)
	cv.rect(x - 1, 32, pw + 2, 1, wall + 9)
	cv.rect(x - 1, 33, 1, top - 33, wall + 8)
	cv.rect(x + pw, 33, 1, top - 33, wall + 4)
	cv.rect(x - 1, top - 1, pw + 2, 1, wall + 4)
	if skull:
		cv.stamp(ArenaArtProps.SKULL_FRONT, x + (pw - 7) / 2, 25, ArenaArtProps.bone_map(pal.bone, pal.ink))
		cv.shade_rect(x + (pw - 7) / 2 + 1, 32, 6, 1, -3)

## The top door: an arch between two heavier pilasters, a black stairwell behind it with the glow of the
## palette's "door" ramp coming up. Starts `scene.doors` (one Rect2 per World.DOORS entry) with its opening.
static func top_door(cv: ArenaArtCanvas, pal: Dictionary, cx: int, top: int, scene: Dictionary, skulls: bool = true) -> void:
	var wall: int = pal.wall
	var half := DOOR_HALF
	var spring := 20
	var rise := 14.0
	cv.rect(cx - half - 5, 4, (half + 5) * 2, top - 4, wall + 6)
	for y in range(2, top):
		for x in range(cx - half - 5, cx + half + 5):
			var dx := absf(x + 0.5 - cx)
			var dy := maxf(0.0, float(spring - y))
			var inside := dx < half and dx * dx / float(half * half) + dy * dy / (rise * rise) < 1.0
			var frame := dx < half + 5 and dx * dx / float((half + 5) * (half + 5)) + dy * dy / ((rise + 4.0) * (rise + 4.0)) < 1.0
			if inside:
				# Steps going down and away, then the far wall of the stairwell lit from below.
				var depth := float(top - 1 - y)
				var g := 0.0
				if depth < 9.0:
					g = 0.45 + depth * 0.06
					if int(depth) % 3 == 2:
						g += 0.14
				else:
					g = 1.0 - (depth - 9.0) / 15.0
				g *= 1.0 - 0.45 * (dx / half) * (dx / half)
				cv.put(x, y, pal.door + dither(g * 5.0, x, y, 5))
			elif frame:
				# Arch stones: joints fan out from the opening.
				var s := wall + 8
				if y < spring:
					var ang := atan2(dy, x + 0.5 - cx)
					if absf(fposmod(ang, 0.3) - 0.15) > 0.125:
						s = wall + 4
				elif (y - spring) % 7 == 6:
					s = wall + 4
				if dx > half + 3.5 and x > cx:
					s = mini(s, wall + 6)
				cv.put(x, y, s)
	pilaster(cv, pal, cx - half - 5 - 12, 12, top, skulls)
	pilaster(cv, pal, cx + half + 5, 12, top, skulls)
	scene.doors = [Rect2(cx - half, 6, half * 2, top - 6)]

## The side walls and the front wall, seen from above: capstones with a lit lip on the room side. A fire bowl
## stands on each side wall at every y in `bowls`, candles on the front wall at every x in `candles`.
static func rims(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, rng: RandomNumberGenerator, scene: Dictionary, lamps: Array,
		bowls: Array = [124, 352], candles: Array = [214, 586]) -> void:
	var wall: int = pal.wall
	for side in 2:
		var x0 := 0 if side == 0 else a.end.x
		var rw := a.position.x if side == 0 else cv.w - a.end.x
		var lip := x0 + rw - 1 if side == 0 else x0
		var edge := x0 if side == 0 else x0 + rw - 1
		cv.rect(x0, 0, rw, cv.h, wall + 5)
		var y := -rng.randi_range(0, 12)
		while y < cv.h:
			var n := rng.randi_range(20, 34)
			var s := wall + 5 + rng.randi_range(-1, 0)
			cv.rect(x0, y, rw, n - 1, s)
			cv.rect(x0, y, rw, 1, s + 1)
			cv.rect(x0, y + n - 1, rw, 1, wall + 2)
			y += n
		cv.rect(edge, 0, 1, cv.h, pal.ink)
		cv.rect(edge + (1 if side == 0 else -1), 0, 1, cv.h, wall + 2)
		cv.rect(lip, 0, 1, cv.h, wall + 9)
		cv.rect(lip + (-1 if side == 0 else 1), 0, 1, cv.h, wall + 7)
	# The front wall.
	var y0 := a.end.y
	cv.rect(a.position.x, y0, a.size.x, cv.h - y0, wall + 5)
	var x := a.position.x - rng.randi_range(0, 12)
	while x < a.end.x:
		var n := rng.randi_range(22, 40)
		var s := wall + 5 + rng.randi_range(-1, 0)
		var xa := maxi(x, a.position.x)
		var xb := mini(x + n - 1, a.end.x)
		cv.rect(xa, y0, xb - xa, cv.h - y0, s)
		if x + n - 1 < a.end.x:
			cv.rect(x + n - 1, y0, 1, cv.h - y0, wall + 2)
		x += n
	cv.rect(a.position.x, y0, a.size.x, 1, wall + 9)
	cv.rect(a.position.x, y0 + 1, a.size.x, 1, wall + 7)
	cv.rect(a.position.x, cv.h - 1, a.size.x, 1, pal.ink)
	cv.rect(a.position.x, cv.h - 2, a.size.x, 1, wall + 2)
	# Fire bowls on the side walls, between each door and the corners.
	var im := {"I": pal.iron + 1, "i": pal.iron + 2, "l": pal.iron + 3, "e": pal.ember, "E": pal.ember + 1, "Y": pal.ember + 2}
	var bw := ArenaArtCanvas.rows_width(ArenaArtProps.BRAZIER)
	for by: int in bowls:
		for side in 2:
			var bx := (a.position.x - bw) / 2 if side == 0 else a.end.x + (cv.w - a.end.x - bw) / 2 + 1
			cv.shade_rect(bx + 1, by - 3 + ArenaArtProps.BRAZIER.size() - 1, bw - 2, 2, -2)
			cv.stamp(ArenaArtProps.BRAZIER, bx, by - 4, im)
			scene.flames.append([Vector2(bx + ArenaArtProps.BRAZIER_FIRE.x, by - 4 + ArenaArtProps.BRAZIER_FIRE.y), FIRE])
			lamps.append([bx + bw / 2, by, LAMP_BOWL_LEFT + side])
	# Candles on the front wall.
	for cx: int in candles:
		var rows: Array = ArenaArtProps.CANDLES
		var cy := y0 + 8 - rows.size()
		cv.stamp(rows, cx - 4, cy, {"w": pal.wax + 1, "x": pal.wax, "f": pal.ink})
		for wk: Vector2i in ArenaArtProps.CANDLES_WICKS:
			scene.flames.append([Vector2(cx - 4 + wk.x, cy + wk.y), CANDLE])
		lamps.append([cx, y0, LAMP_FRONT])

## The side doors and the front door are gaps in the low walls: a stair going down and out, light coming up
## it, and a post each side (with a skull on it when `skulls`). Call after `top_door`: it adds to `scene.doors`.
static func doors(cv: ArenaArtCanvas, pal: Dictionary, a: Rect2i, scene: Dictionary, skulls: bool = true) -> void:
	var wall: int = pal.wall
	var bm := ArenaArtProps.bone_map(pal.bone, pal.ink)
	# Front door.
	var fx := int((World.DOORS[1] as Vector2).x)
	var y0 := a.end.y
	for y in range(y0, cv.h):
		for x in range(fx - DOOR_HALF, fx + DOOR_HALF):
			var depth := float(y - y0)
			var u := absf(x + 0.5 - fx) / DOOR_HALF
			var g := 0.4 + depth * 0.05 + (0.14 if int(depth) % 4 == 3 else 0.0)
			g *= 1.0 - 0.4 * u * u
			cv.put(x, y, pal.door + dither(g * 5.0, x, y, 5))
	for side in 2:
		var px := fx - DOOR_HALF - 12 if side == 0 else fx + DOOR_HALF
		post(cv, pal, Rect2i(px, y0 - 2, 12, cv.h - y0 + 2))
		if skulls:
			cv.stamp(ArenaArtProps.SKULL_FRONT, px + 2, y0 + 1, bm)
	scene.doors.append(Rect2(fx - DOOR_HALF, y0, DOOR_HALF * 2, cv.h - y0))
	# Side doors.
	for side in 2:
		var d: Vector2 = World.DOORS[2 + side]
		var cy := int(d.y)
		var x0 := 0 if side == 0 else a.end.x
		var rw := a.position.x if side == 0 else cv.w - a.end.x
		for y in range(cy - SIDE_DOOR_HALF, cy + SIDE_DOOR_HALF):
			for x in range(x0, x0 + rw):
				var depth := float(a.position.x - 1 - x) if side == 0 else float(x - a.end.x)
				var u := absf(y + 0.5 - cy) / SIDE_DOOR_HALF
				var g := 0.4 + depth * 0.03 + (0.14 if int(depth) % 5 == 4 else 0.0)
				g *= 1.0 - 0.4 * u * u
				# The end of the wall above the gap shows its face.
				if y < cy - SIDE_DOOR_HALF + 5:
					cv.put(x, y, wall + (3 if y < cy - SIDE_DOOR_HALF + 4 else 1))
				else:
					cv.put(x, y, pal.door + dither(g * 5.0, x, y, 5))
		for end in 2:
			var py := cy - SIDE_DOOR_HALF - 13 if end == 0 else cy + SIDE_DOOR_HALF
			var px := x0 if side == 0 else x0 - 2
			post(cv, pal, Rect2i(px, py, rw + 2, 13))
			if skulls:
				cv.stamp(ArenaArtProps.SKULL_FRONT, x0 + (rw - 7) / 2, py + 2, bm, side == 1)
		scene.doors.append(Rect2(x0, cy - SIDE_DOOR_HALF + 5, rw, SIDE_DOOR_HALF * 2 - 5))

## The top of a door post: a squared block a little prouder than the wall it stands in.
static func post(cv: ArenaArtCanvas, pal: Dictionary, r: Rect2i) -> void:
	var wall: int = pal.wall
	cv.rect(r.position.x, r.position.y, r.size.x, r.size.y, wall + 7)
	cv.rect(r.position.x, r.position.y, r.size.x, 1, wall + 9)
	cv.rect(r.position.x, r.position.y, 1, r.size.y, wall + 8)
	cv.rect(r.end.x - 1, r.position.y, 1, r.size.y, wall + 4)
	cv.rect(r.position.x, r.end.y - 1, r.size.x, 1, wall + 3)

## Stamps a map with a little shadow under and to the right of it, so heaped things stay apart.
static func drop(cv: ArenaArtCanvas, rows: Array, x0: int, y0: int, map: Dictionary, flip: bool = false) -> void:
	for y: int in rows.size():
		var row: String = rows[y]
		var n := row.length()
		for x: int in n:
			if map.has(row[n - 1 - x] if flip else row[x]):
				cv.shade(x0 + x + 1, y0 + y + 1, -2)
	cv.stamp(rows, x0, y0, map, flip)

## A spot for a thing of w x h inside a heap: heaps are fullest in the middle of their rectangle, or against
## the side they lean on.
static func in_heap(r: Rect2i, w: int, h: int, rng: RandomNumberGenerator, lean: Vector2i = Vector2i.ZERO) -> Vector2i:
	var u := (rng.randf() + rng.randf()) * 0.5
	var v := (rng.randf() + rng.randf()) * 0.5
	if lean.x != 0:
		u = absf(u - 0.5) * 1.5
		if lean.x > 0:
			u = 1.0 - u
	if lean.y != 0:
		v = absf(v - 0.5) * 1.5
		if lean.y > 0:
			v = 1.0 - v
	return Vector2i(r.position.x + int(u * maxi(1, r.size.x - w)), r.position.y + int(v * maxi(1, r.size.y - h)))

## Fallen stone in `r`; `blocks` adds a couple of whole fallen blocks.
static func rubble(cv: ArenaArtCanvas, pal: Dictionary, r: Rect2i, n: int, rng: RandomNumberGenerator, blocks: bool) -> void:
	var sm := ArenaArtProps.stone_map(pal.wall, 8)
	var fm := ArenaArtProps.stone_map(pal.stone, 12)
	var items: Array = []
	for i in n:
		var rows: Array = ArenaArtProps.RUBBLES[rng.randi() % ArenaArtProps.RUBBLES.size()]
		var p := in_heap(r, ArenaArtCanvas.rows_width(rows), rows.size(), rng)
		items.append([p.y + rows.size(), p.x, p.y, rows, sm if i % 2 == 0 else fm, rng.randf() < 0.5])
	if blocks:
		for i in 3:
			var rows: Array = ArenaArtProps.RUBBLE_BIG if i == 0 else ArenaArtProps.RUBBLE_BLOCK
			var p := in_heap(r, ArenaArtCanvas.rows_width(rows), rows.size(), rng)
			items.append([p.y + rows.size(), p.x, p.y, rows, sm, i == 1])
	items.sort_custom(func(m: Array, k: Array) -> bool: return m[0] < k[0])
	for it: Array in items:
		drop(cv, it[3], it[1], it[2], it[4], it[5])

## A cobweb in a corner: threads out of the corner point and two sagging rounds across them. It only lightens
## what it crosses a little.
static func cobweb(cv: ArenaArtCanvas, pal: Dictionary, at: Vector2i, sx: int, sy: int, size: int) -> void:
	var bone: int = pal.bone
	var ends: Array[Vector2] = []
	for i in 5:
		var ang := i * (PI / 2.0) / 4.0
		var e := Vector2(at) + Vector2(cos(ang) * size * sx, sin(ang) * size * sy)
		ends.append(e)
		var n := size
		for k in range(1, n + 1):
			var p := Vector2(at).lerp(e, float(k) / n)
			if cv.at(roundi(p.x), roundi(p.y)) < bone or cv.at(roundi(p.x), roundi(p.y)) >= bone + 8:
				cv.shade(roundi(p.x), roundi(p.y), 2)
	for ring: float in [0.55, 0.9]:
		for i in 4:
			var p0 := Vector2(at).lerp(ends[i], ring)
			var p1 := Vector2(at).lerp(ends[i + 1], ring)
			var mid := (p0 + p1) * 0.5 + (Vector2(at) - (p0 + p1) * 0.5) * 0.18
			var n := int(p0.distance_to(p1)) + 1
			for k in n + 1:
				var u := float(k) / n
				var p := p0.lerp(mid, u).lerp(mid.lerp(p1, u), u)
				if cv.at(roundi(p.x), roundi(p.y)) < bone or cv.at(roundi(p.x), roundi(p.y)) >= bone + 8:
					cv.shade(roundi(p.x), roundi(p.y), 2)


## The light map: dim walls, a wash of light in from the walls, dark corners, shadow at the foot of every
## wall, and a pool on the floor and on the wall for each lamp in `lamps` ([x, y, kind]). Leaves `scene.glows`
## ([centre, radii] of every pool) for the arena to flicker.
static func lights(cv: ArenaArtCanvas, a: Rect2i, lamps: Array, scene: Dictionary) -> void:
	var top_wall := Rect2i(a.position.x, 0, a.size.x, a.position.y)
	var left := Rect2i(0, 0, a.position.x, cv.h)
	var right := Rect2i(a.end.x, 0, cv.w - a.end.x, cv.h)
	var front := Rect2i(a.position.x, a.end.y, a.size.x, cv.h - a.end.y)
	# The walls keep less light than the floor; the back wall is darkest up by the vault.
	cv.light_set(top_wall, 56)
	cv.light_shade(Rect2i(a.position.x, 0, a.size.x, 24), 0.55, 0.0)
	cv.light_set(left, 46)
	cv.light_set(right, 46)
	cv.light_set(front, 42)
	# A wash of warmth in from the walls where the lamps are.
	cv.light_shade(Rect2i(a.position.x, a.position.y, a.size.x, 170), 0.2, 0.0, false, true)
	cv.light_shade(Rect2i(a.position.x, a.end.y - 130, a.size.x, 130), 0.0, 0.13, false, true)
	cv.light_shade(Rect2i(a.position.x, a.position.y, 230, a.size.y), 0.2, 0.0, true, true)
	cv.light_shade(Rect2i(a.end.x - 230, a.position.y, 230, a.size.y), 0.0, 0.2, true, true)
	# The room is darkest in its corners and a little dimmer at the foot of every wall.
	var corner := ArenaArtCanvas.pool(230, 150, 0.9, 1.5, Color.BLACK)
	for p: Vector2i in [a.position, Vector2i(a.end.x, a.position.y), Vector2i(a.position.x, a.end.y), a.end]:
		cv.light_add(corner, p.x, p.y)
	cv.light_shade(Rect2i(a.position.x, a.position.y, a.size.x, 9), 0.5, 0.0)
	cv.light_shade(Rect2i(a.position.x, a.end.y - 5, a.size.x, 5), 0.0, 0.3)
	cv.light_shade(Rect2i(a.position.x, a.position.y, 7, a.size.y), 0.35, 0.0, true)
	cv.light_shade(Rect2i(a.end.x - 7, a.position.y, 7, a.size.y), 0.0, 0.35, true)
	var shelf_floor := ArenaArtCanvas.pool(150, 100, 0.88, 2.0)
	var shelf_wall := ArenaArtCanvas.pool(50, 36, 0.78, 1.5)
	var bowl_floor := ArenaArtCanvas.pool(170, 110, 0.9, 1.9)
	var bowl_wall := ArenaArtCanvas.pool(22, 46, 0.85, 1.5)
	var front_floor := ArenaArtCanvas.pool(140, 90, 0.8, 2.0)
	var front_wall := ArenaArtCanvas.pool(40, 14, 0.85, 1.5)
	var seal_floor := ArenaArtCanvas.pool(52, 34, 0.5, 1.8)
	var glows: Array = []
	for l: Array in lamps:
		var x: int = l[0]
		var y: int = l[1]
		match int(l[2]):
			LAMP_SHELF:
				cv.light_add(shelf_floor, x, a.position.y + 1, a)
				cv.light_add(shelf_wall, x, y, top_wall)
				glows.append([Vector2(x, a.position.y + 6), Vector2(84, 50)])
			LAMP_BOWL_LEFT:
				cv.light_add(bowl_floor, a.position.x + 1, y, a)
				cv.light_add(bowl_wall, x, y, left)
				glows.append([Vector2(a.position.x + 8, y), Vector2(96, 60)])
			LAMP_BOWL_RIGHT:
				cv.light_add(bowl_floor, a.end.x - 1, y, a)
				cv.light_add(bowl_wall, x, y, right)
				glows.append([Vector2(a.end.x - 8, y), Vector2(96, 60)])
			LAMP_FRONT:
				cv.light_add(front_floor, x, a.end.y - 1, a)
				cv.light_add(front_wall, x, y + 4, front)
				glows.append([Vector2(x, a.end.y - 6), Vector2(78, 46)])
			LAMP_SEAL:
				cv.light_add(seal_floor, x, y, a)
				glows.append([Vector2(x, y), Vector2(26, 16)])
	scene.glows = glows

## Coloured light laid over the finished picture: the light that spills out of each door onto the floor (`red`
## in the Ossuary) and the glow of the seal (`seal_light`, its alpha the strength; none at 0).
static func glazes(img: Image, a: Rect2i, red: Color = Color(0.78, 0.13, 0.22), seal_light: Color = Color(0.25, 0.7, 0.9, 0.14)) -> void:
	var fan := ArenaArtCanvas.pool(44, 30, 0.26, 1.5, red, 8)
	var fan_side := ArenaArtCanvas.pool(34, 30, 0.26, 1.5, red, 8)
	var d0: Vector2 = World.DOORS[0]
	var d1: Vector2 = World.DOORS[1]
	ArenaArtCanvas.glaze(img, fan, int(d0.x), a.position.y, a)
	ArenaArtCanvas.glaze(img, fan, int(d1.x), a.end.y, a)
	ArenaArtCanvas.glaze(img, fan_side, a.position.x, int((World.DOORS[2] as Vector2).y), a)
	ArenaArtCanvas.glaze(img, fan_side, a.end.x, int((World.DOORS[3] as Vector2).y), a)
	if seal_light.a <= 0.0:
		return
	var c := a.get_center()
	var cold := ArenaArtCanvas.pool(int(SEAL_RX) + 40, int((SEAL_RX + 40) * SQUASH), seal_light.a, 1.2, Color(seal_light, 1.0))
	ArenaArtCanvas.glaze(img, cold, c.x, c.y, a)

class_name TitleArt
extends RefCounted
## The FOUR OF WANDS title art, after the tarot card: night, a huge moon, the wizards' tower on its hill, four tall
## staffs planted in the foreground with a garland of flowers, ribbons and lanterns strung between them.
## Everything static is baked once into a few textures (sky, moon, land, the staffs and garland); the small
## things that move (lanterns, gems, ribbons, wizards, the ghost) are ASCII maps like Sprites uses, one
## character per pixel. Nothing is drawn scaled: a bigger thing is drawn bigger. `title.gd` draws the layers
## and animates them.

const W := 480
const H := 270

## The moon's centre and radius.
const MOON := Vector2(384, 80)
const MOON_R := 54

# ------------------------------------------------------------------ palette --
const INK := Color("0b0716")
const OUTLINE := Color("1a0f24")
const NIGHT := [Color("0b0716"), Color("120a1f"), Color("1c1230"), Color("2a1f45"), Color("3a2a5e"), Color("4b3a78"),
	Color("5c4a8e")]
const STONE := [Color("221b2e"), Color("2e2540"), Color("3b3150"), Color("4a4063"), Color("5d5378")]
const BONE := [Color("7d705c"), Color("b7a98e"), Color("e8dcc0"), Color("fff6e0")]
const BLOODMOON := [Color("4a0a18"), Color("7a1226"), Color("c0263a"), Color("e8566a")]
const CANDLE := [Color("7a2f14"), Color("c85a1e"), Color("ff9a3c"), Color("ffcf5a"), Color("fff6c0")]

static var _img: Image
static var _iw := 0
static var _ih := 0

static var _sky: ImageTexture
static var _moon: ImageTexture
static var _moon_blood: ImageTexture
static var _wisps: ImageTexture
static var _wisps_lit: ImageTexture
static var _land: ImageTexture
static var _fore: ImageTexture


static func sky() -> ImageTexture:
	if _sky == null:
		_sky = ImageTexture.create_from_image(bake_sky())
	return _sky


static func moon(blood: bool = false) -> ImageTexture:
	if _moon == null:
		_moon = ImageTexture.create_from_image(bake_moon(false))
		_moon_blood = ImageTexture.create_from_image(bake_moon(true))
	return _moon_blood if blood else _moon


static func wisps() -> ImageTexture:
	if _wisps == null:
		_wisps = ImageTexture.create_from_image(bake_wisps(false))
	return _wisps


## The same wisps as they look where they cross the moon's disc: a veil, lit from behind.
static func wisps_lit() -> ImageTexture:
	if _wisps_lit == null:
		_wisps_lit = ImageTexture.create_from_image(bake_wisps(true))
	return _wisps_lit


static func land() -> ImageTexture:
	if _land == null:
		_land = ImageTexture.create_from_image(bake_land())
	return _land


static func fore() -> ImageTexture:
	if _fore == null:
		_fore = ImageTexture.create_from_image(bake_fore())
	return _fore


## Bakes everything now, so the first frame of the title does not have to.
static func warm() -> void:
	sky()
	moon()
	wisps()
	wisps_lit()
	land()
	fore()
	logo()
	sprite("lantern")


# ================================================================ PIXELS ===
static func _begin(w: int, h: int) -> void:
	_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_iw = w
	_ih = h


static func _px(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= _iw or y >= _ih:
		return
	if c.a < 1.0:
		var under := _img.get_pixel(x, y)
		if under.a > 0.0:
			c = Color(under.lerp(Color(c, 1.0), c.a), 1.0)
	_img.set_pixel(x, y, c)


static func _at(x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= _iw or y >= _ih:
		return Color(0, 0, 0, 0)
	return _img.get_pixel(x, y)


static func _rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy: int in range(y, y + h):
		for xx: int in range(x, x + w):
			_px(xx, yy, c)


static func _disc(cx: float, cy: float, r: float, c: Color) -> void:
	for yy: int in range(int(cy - r) - 1, int(cy + r) + 2):
		for xx: int in range(int(cx - r) - 1, int(cx + r) + 2):
			if Vector2(xx + 0.5 - cx, yy + 0.5 - cy).length() <= r:
				_px(xx, yy, c)


static func _line(a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for i: int in range(n + 1):
		var p := a.lerp(b, float(i) / maxf(n, 1.0))
		_px(int(roundf(p.x)), int(roundf(p.y)), c)


## Stamps an ASCII map: one character per pixel, a key missing from `pal` is clear.
static func _stamp(rows: Array, x0: int, y0: int, pal: Dictionary, flip: bool = false) -> void:
	for y: int in range(rows.size()):
		var row: String = rows[y]
		var n := row.length()
		for x: int in range(n):
			var ch := row[n - 1 - x] if flip else row[x]
			if pal.has(ch):
				_px(x0 + x, y0 + y, pal[ch])


## An ASCII map as an image of its own.
static func _map_image(rows: Array, pal: Dictionary) -> Image:
	var w := 0
	for r: String in rows:
		w = maxi(w, r.length())
	var keep := _img
	var kw := _iw
	var kh := _ih
	_begin(w, rows.size())
	_stamp(rows, 0, 0, pal)
	var out := _img
	_img = keep
	_iw = kw
	_ih = kh
	return out


static func _hash(x: int, y: int, s: int) -> int:
	var h := (x * 374761393 + y * 668265263 + s * 982451653) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)


## A repeatable number in 0..1 for a cell.
static func _rnd(x: int, y: int, s: int) -> float:
	return float(_hash(x, y, s) % 10007) / 10007.0


const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


## The ordered-dither threshold of a pixel, 0..1.
static func _bayer(x: int, y: int) -> float:
	return (BAYER[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0


## A colour from `ramp` at level `lv` (0 = first colour). Bands are clean; only the middle `zone` of each
## step between two colours is dithered.
static func _dith(ramp: Array, lv: float, x: int, y: int, zone: float = 0.4) -> Color:
	var n := ramp.size()
	if lv <= 0.0:
		return ramp[0]
	var i := int(lv)
	if i >= n - 1:
		return ramp[n - 1]
	var f := lv - i
	var k := (f - (0.5 - zone * 0.5)) / zone
	return ramp[i + 1] if k > _bayer(x, y) else ramp[i]


## Smooth value noise, 0..1.
static func _noise(x: float, y: float, s: int) -> float:
	var xi := int(floorf(x))
	var yi := int(floorf(y))
	var fx := x - xi
	var fy := y - yi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _rnd(xi, yi, s)
	var b := _rnd(xi + 1, yi, s)
	var c := _rnd(xi, yi + 1, s)
	var d := _rnd(xi + 1, yi + 1, s)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## A ridge line: straight runs between random peaks (period `p` pixels), 0..1.
static func _ridge(x: float, p: float, s: int) -> float:
	var u := x / p
	var i := int(floorf(u))
	return lerpf(_rnd(i, 0, s), _rnd(i + 1, 0, s), u - i)


## A height from control points [[x, y], ...] sorted by x, straight between them.
static func _profile(pts: Array, x: float) -> float:
	if x <= pts[0][0]:
		return pts[0][1]
	for i: int in range(pts.size() - 1):
		if x <= pts[i + 1][0]:
			var u: float = (x - pts[i][0]) / (pts[i + 1][0] - pts[i][0])
			return lerpf(pts[i][1], pts[i + 1][1], u)
	return pts[pts.size() - 1][1]


# =================================================================== SKY ===
## The far shore of the lake: the line the land meets the sky on.
const HORIZON := 194


## How much of the Milky Way crosses a pixel, 0..1: a soft band that falls from the top of the sky, between
## the logo and the moon, to the far shore of the lake.
static func _milky(x: float, y: float) -> float:
	var d := absf((x - 206.0) * 0.825 - y * 0.565)
	return clampf(1.0 - d / 27.0, 0.0, 1.0)


## How bright the night sky is at a pixel, as a level on the NIGHT ramp: darkest overhead, lighter towards the
## horizon, a wide halo round the moon and a faint band of the Milky Way.
static func _sky_level(x: float, y: float) -> float:
	var g := 0.3 + 4.2 * pow(clampf(y / float(HORIZON), 0.0, 1.0), 1.5)
	var d := Vector2(x, y).distance_to(MOON) - MOON_R
	if d < 100.0:
		var k := 1.0 - maxf(d, 0.0) / 100.0
		g += 3.9 * pow(k, 2.3)
	var mw := _milky(x, y)
	if mw > 0.0:
		var cloud := 0.6 * _noise(x / 15.0, y / 15.0, 61) + 0.4 * _noise(x / 5.0, y / 5.0, 62)
		g += 1.5 * mw * (0.15 + cloud) * clampf(1.15 - y / 190.0, 0.0, 1.0)
	return g


static func bake_sky() -> Image:
	_begin(W, H)
	for y: int in range(H):
		for x: int in range(W):
			_img.set_pixel(x, y, _dith(NIGHT, _sky_level(x + 0.5, y + 0.5), x, y))
	_stars()
	return _img


## Where the bright stars sit, for the view to twinkle them: [position, phase, speed, colour].
static var _twinkles: Array = []


static func twinkles() -> Array:
	sky()
	return _twinkles


static func _stars() -> void:
	_twinkles.clear()
	for i: int in range(1500):
		var x := _hash(i, 1, 31) % W
		var y := _hash(i, 2, 31) % HORIZON
		# Fewer low in the sky, more along the Milky Way, none in the moon's halo.
		var want := pow(1.0 - y / float(HORIZON), 1.3) * 0.34 + 0.02 + _milky(x, y) * 0.5
		if _rnd(i, 3, 31) > want:
			continue
		var d := Vector2(x, y).distance_to(MOON) - MOON_R
		if d < 12.0:
			continue
		# None behind the logo and its tagline either: they would fret the letters' edges.
		if x > LOGO_AT.x - 4 and x < LOGO_AT.x + 170 and y < LOGO_AT.y + 94:
			continue
		var tier := _rnd(i, 4, 31)
		if d < 50.0:
			tier *= 0.5
		var lv := int(_sky_level(x, y))
		if tier < 0.6:
			_px(x, y, NIGHT[mini(NIGHT.size() - 1, lv + 2)])
		elif tier < 0.88:
			_px(x, y, STONE[4] if _rnd(i, 5, 31) < 0.6 else BONE[0])
		else:
			var c: Color = [BONE[2], Color("8fe3ff"), Color("c9a6ff"), BONE[2], BONE[1]][_hash(i, 6, 31) % 5]
			_px(x, y, c)
			if tier > 0.95:
				_twinkles.append([Vector2(x, y), _rnd(i, 7, 31) * TAU, 0.5 + _rnd(i, 8, 31) * 1.4, c])


# ================================================================== MOON ===
## The moon as its own texture, (2R+1) square: light from the upper left, seas, a few craters.
static func bake_moon(blood: bool) -> Image:
	var r := MOON_R
	var n := r * 2 + 1
	_begin(n, n)
	var ramp: Array = BLOODMOON if blood else BONE
	for y: int in range(n):
		for x: int in range(n):
			var dx := (x - r) / (r + 0.5)
			var dy := (y - r) / (r + 0.5)
			var rr := sqrt(dx * dx + dy * dy)
			if rr > 1.0:
				continue
			var lv := 2.2 - (dx * 0.5 + dy * 0.62) * 0.7
			# Seas: big soft blobs of the darker tone.
			var sea := _noise(x / 17.0 + 3.1, y / 17.0 + 1.7, 5) * 0.7 + _noise(x / 7.0, y / 7.0, 9) * 0.3
			if sea > 0.56:
				lv -= 0.95
			elif sea > 0.53:
				lv -= 0.45
			# The limb falls away into shadow on the far side.
			if rr > 0.84:
				lv -= (rr - 0.84) * 5.5 * clampf(0.55 + (dx + dy) * 0.6, 0.0, 1.0)
			_img.set_pixel(x, y, _dith(ramp, clampf(lv, 0.0, 3.0), x, y, 0.3))
	for cr: Array in [[20, 30, 5], [80, 22, 4], [88, 62, 6], [30, 80, 4], [60, 94, 5], [13, 56, 3], [94, 40, 2], [44, 13, 3]]:
		_crater(cr[0], cr[1], cr[2], ramp)
	return _img


static func _crater(cx: int, cy: int, r: int, ramp: Array) -> void:
	for y: int in range(-r - 1, r + 2):
		for x: int in range(-r - 1, r + 2):
			var d := sqrt(float(x * x + y * y))
			if _at(cx + x, cy + y).a <= 0.0:
				continue
			if d <= r - 0.5:
				# The bowl: shadowed under its upper-left wall, lit towards the lower right.
				var k := (x + y) / float(r * 2)
				_px(cx + x, cy + y, ramp[1] if k < 0.1 else ramp[2])
			elif d <= r + 0.5:
				_px(cx + x, cy + y, ramp[3] if (x + y) > 0 else ramp[0 if r > 3 else 1])


# ================================================================= WISPS ===
const WISP := Vector2i(150, 14)


## Three thin wisps of cloud stacked on one strip, each WISP in size. The view drifts them across the moon.
## Each is a few long lens-shaped streaks laid over one another, their upper edges catching the moon.
## `lit` bakes them as they look over the moon's disc.
static func bake_wisps(lit: bool = false) -> Image:
	var body: Color = BONE[0] if lit else NIGHT[3]
	var rim: Color = BONE[1] if lit else NIGHT[4]
	_begin(WISP.x, WISP.y * 3)
	for k: int in range(3):
		var y0 := k * WISP.y + 8
		for j: int in range(3):
			var cx := 34.0 + 40.0 * j + 18.0 * _rnd(k, j, 76)
			var hl := 24.0 + 20.0 * _rnd(k, j, 77)
			var oy := (j - 1) * 2.0 + roundf(2.0 * _rnd(k, j, 78) - 1.0)
			var th := 2.2 + 2.2 * _rnd(k, j, 79)
			for i: int in range(maxi(0, int(cx - hl)), mini(WISP.x, int(cx + hl) + 1)):
				var u := (i - cx) / hl
				var t := th * pow(1.0 - u * u, 0.8) * (0.7 + 0.6 * _noise(i / 7.0, k * 5.0 + j, 80))
				var top := int(roundf(y0 + oy - t * 0.7))
				var bot := int(roundf(y0 + oy + t * 0.3))
				for y: int in range(top, bot + 1):
					_px(i, y, rim if y == top else body)
	return _img


# ================================================================== LAND ===
static func bake_land() -> Image:
	_begin(W, H)
	_far_mountains()
	_lake()
	_wooded_slope()
	_tower_hill()
	_tower()
	_ground()
	return _img


## The top of the far range and of the nearer one in front of it.
static func _far_top(x: float) -> float:
	return 186.0 - 46.0 * _ridge(x + 40.0, 64.0, 3) - 16.0 * _ridge(x, 23.0, 4) - 5.0 * _ridge(x, 8.0, 5)


static func _near_top(x: float) -> float:
	return 195.0 - 22.0 * _ridge(x + 300.0, 46.0, 13) - 8.0 * _ridge(x, 16.0, 14) - 3.0 * _ridge(x, 5.0, 15)


static func _far_mountains() -> void:
	for x: int in range(W):
		var top := int(_far_top(x))
		# Moonlight catches the faces that look right, towards the moon.
		var lit := _far_top(x + 2.0) > _far_top(x) + 0.6
		@warning_ignore("integer_division")
		var band := 5 + int(4.0 * _rnd(x / 3, 0, 6))
		for y: int in range(top, HORIZON):
			var c: Color = NIGHT[3]
			if lit and y - top < band and _bayer(x, y) < 0.85 - (y - top) * 0.09:
				c = NIGHT[4]
			_px(x, y, c)
	for x: int in range(W):
		var top := int(_near_top(x))
		var lit := _near_top(x + 2.0) > _near_top(x) + 0.5
		for y: int in range(top, HORIZON):
			var c: Color = NIGHT[2]
			if lit and y - top < 4 and _bayer(x, y) < 0.75 - (y - top) * 0.12:
				c = NIGHT[3]
			_px(x, y, c)
	# Mist lying along the far shore.
	for y: int in range(HORIZON - 11, HORIZON):
		for x: int in range(W):
			var k := float(y - (HORIZON - 11)) / 11.0 * (0.4 + 0.85 * _noise(x / 31.0, y / 3.0, 17))
			if k > _bayer(x, y) * 0.8 + 0.15:
				_px(x, y, NIGHT[5] if k > 0.72 else NIGHT[4])


## The lake in the valley: the sky and the ranges upside down, darker, broken by ripples.
static func _lake() -> void:
	for y: int in range(HORIZON, 250):
		var depth := y - HORIZON
		var my := HORIZON - depth * 1.5
		for x: int in range(W):
			var wob := x + int(roundf(sin(y * 1.7 + x * 0.05) * minf(depth * 0.15, 2.0)))
			var c: Color
			if my >= _near_top(wob):
				c = NIGHT[1]
			elif my >= _far_top(wob):
				c = NIGHT[2]
			else:
				c = _dith(NIGHT, _sky_level(wob, my) - 1.0, x, y)
			_px(x, y, c)
		# Ripples: short bright dashes, fewer and longer towards the near shore.
		var x := _hash(y, 0, 51) % 23
		while x < W:
			@warning_ignore("integer_division")
			var run := 2 + _hash(x, y, 52) % (3 + depth / 5)
			if _rnd(x, y, 53) < 0.36 - depth * 0.004:
				for i: int in range(run):
					_px(x + i, y, NIGHT[5] if depth < 4 else (NIGHT[4] if depth < 22 else NIGHT[3]))
			x += run + 3 + _hash(x, y, 54) % 19
	# The far shore: one bright line where the mist meets the water.
	for x: int in range(W):
		@warning_ignore("integer_division")
		if _rnd(x / 2, 0, 55) < 0.8:
			@warning_ignore("integer_division")
			_px(x, HORIZON, NIGHT[6] if _rnd(x / 5, 1, 55) < 0.5 else NIGHT[5])


## A pine as a silhouette: tiers of branches narrowing to a tip. `base` is the foot of the trunk.
## `lit` paints the moon-side tips of the top tiers.
static func _pine(x: int, base: int, tiers: int, c: Color, lit: Color = Color(0, 0, 0, 0)) -> void:
	var y := base - 2 - tiers * 3
	_rect(x, base - 2, 1, 2, c)
	for k: int in range(tiers):
		for r: int in range(3):
			var half := k + r
			_rect(x - half, y, half * 2 + 1, 1, c)
			if lit.a > 0.0 and r == 2 and k < tiers - 1:
				_px(x + half, y, lit)
			y += 1


const SLOPE := [[0, 97], [40, 104], [80, 113], [118, 128], [146, 152], [168, 184], [184, 214], [196, 240], [204, 252]]


static func _slope_top(x: float) -> float:
	return _profile(SLOPE, x) - 2.0 * _noise(x / 15.0, 0.0, 23)


## The wooded slope on the left that the menu sits on: dark and quiet, its edge a line of pines.
static func _wooded_slope() -> void:
	# Pines standing behind the crest, in the lighter tone.
	var x := -3
	while x < 204:
		_pine(x, int(_slope_top(x)) + 2, 3 + _hash(x, 2, 24) % 3, NIGHT[2])
		x += 5 + _hash(x, 1, 24) % 7
	for sx: int in range(210):
		var top := int(_slope_top(sx))
		for y: int in range(top, H):
			_px(sx, y, NIGHT[1])
	# The crest's own pines, catching a little moon on the right.
	x = 1
	while x < 200:
		_pine(x, int(_slope_top(x)) + 5, 3 + _hash(x, 4, 24) % 4, NIGHT[1], NIGHT[2])
		x += 6 + _hash(x, 3, 24) % 8
	# Down the slope the wood goes black, its edge a scatter of nearer pines.
	for sx: int in range(210):
		var edge := int(_slope_top(sx)) + 36 + int(8.0 * _noise(sx / 22.0, 3.0, 28))
		for y: int in range(edge, H):
			_px(sx, y, INK)
	x = -2
	while x < 196:
		var edge := int(_slope_top(x)) + 36 + int(8.0 * _noise(x / 22.0, 3.0, 28))
		_pine(x, edge + 4, 4 + _hash(x, 6, 24) % 3, INK)
		x += 6 + _hash(x, 5, 24) % 9


const HILL := [[258, 252], [272, 240], [288, 229], [300, 216], [311, 199], [321, 183], [331, 167], [341, 151],
	[349, 139], [356, 131], [363, 126], [420, 126], [428, 131], [438, 141], [450, 150], [462, 162], [480, 170]]


static func _hill_top(x: float) -> float:
	var rough := 1.5 * _ridge(x, 6.0, 21) if (x < 360.0 or x > 423.0) else 0.0
	return _profile(HILL, x) - rough


static func _tower_hill() -> void:
	for x: int in range(250, W):
		var top := int(_hill_top(x))
		var near := clampf(1.0 - absf(x - 380.0) / 64.0, 0.0, 1.0)
		for y: int in range(top, H):
			var c: Color = NIGHT[1]
			# Moonlight grazes the crest near the tower.
			if y - top < 1 and near > 0.05:
				c = NIGHT[4] if near > 0.5 else NIGHT[3]
			elif y - top < 4 and near > 0.25 and _bayer(x, y) < near * 0.7 - (y - top) * 0.1:
				c = NIGHT[2]
			elif y - top > 26 + 12 * _noise(x / 20.0, 0.0, 22):
				c = INK
			_px(x, y, c)
	# Ledges of rock on the cliff face.
	for k: int in range(26):
		var lx := 286 + _hash(k, 0, 71) % 170
		var ly := int(_hill_top(lx)) + 5 + _hash(k, 1, 71) % 22
		var run := 3 + _hash(k, 2, 71) % 7
		for i: int in range(run):
			if _at(lx + i, ly) == NIGHT[1]:
				_px(lx + i, ly, NIGHT[2])
				if _at(lx + i, ly + 1) == NIGHT[1]:
					_px(lx + i, ly + 1, INK)
	# Strata: long broken seams in the rock that run with the slope.
	for k: int in range(14):
		var sx := 300 + _hash(k, 0, 72) % 150
		var sy := int(_hill_top(sx)) + 8 + _hash(k, 1, 72) % 16
		var run := 9 + _hash(k, 2, 72) % 14
		var fall := 0.55 if sx < 372 else -0.45
		for i: int in range(run):
			var px := sx - i if sx < 372 else sx + i
			var py := sy + int(i * fall)
			if _at(px, py) == NIGHT[1] and (i + k) % 5 != 0:
				_px(px, py, NIGHT[2])
	# A few pines on the lower flanks.
	for p: Array in [[292, 3], [301, 4], [283, 3], [432, 3], [444, 4], [459, 3], [470, 4], [318, 3]]:
		_pine(p[0], int(_hill_top(p[0])) + 4, p[1], NIGHT[1], NIGHT[2])
	# Where the rock gives way to the wood below, the wood's edge is a line of pines.
	var tx := 262
	while tx < W:
		var edge := int(_hill_top(tx)) + 26 + int(12.0 * _noise(tx / 20.0, 0.0, 22))
		if edge < 246:
			_pine(tx, edge + 5, 3 + _hash(tx, 7, 24) % 3, INK)
		tx += 5 + _hash(tx, 8, 24) % 8
	_path()


## The stair that winds from the tower's door down the cliff, a lantern at each turn.
const PATH := [[369, 127], [352, 137], [362, 147], [338, 160], [347, 172], [322, 187], [332, 200], [306, 215],
	[314, 228], [288, 243]]

## The tiny lanterns along the stair, for the view to make them glow.
static var _path_lights: Array[Vector2] = []


static func path_lights() -> Array[Vector2]:
	land()
	return _path_lights


static func _path() -> void:
	_path_lights.clear()
	for i: int in range(PATH.size() - 1):
		var a := Vector2(PATH[i][0], PATH[i][1])
		var b := Vector2(PATH[i + 1][0], PATH[i + 1][1])
		var n := int(a.distance_to(b))
		for k: int in range(n + 1):
			var p := a.lerp(b, float(k) / n)
			var x := int(p.x)
			var y := int(p.y)
			if _at(x, y).a > 0.0 and y > int(_hill_top(x)) + 1:
				_px(x, y, NIGHT[2] if (k + i) % 3 != 0 else NIGHT[3])
	for i: int in range(1, PATH.size() - 1):
		var x: int = PATH[i][0] + (2 if i % 2 == 1 else -2)
		var y: int = PATH[i][1]
		_px(x, y - 1, CANDLE[0])
		_px(x, y - 2, CANDLE[0])
		_px(x, y - 3, CANDLE[3])
		_px(x, y - 4, CANDLE[2])
		_px(x - 1, y - 3, CANDLE[1])
		_px(x + 1, y - 3, CANDLE[1])
		_path_lights.append(Vector2(x, y - 3))


# ----------------------------------------------------------------- tower ---
const TOWER_X := 372
const TOWER_BASE := 126

const WIN_PAL := {"O": Color("ff9a3c"), "Y": Color("ffcf5a"), "L": Color("fff6c0"), "G": Color("c85a1e"), "D": Color("7a2f14")}
const WIN_ARCH := [
	".OOO.",
	"OYYYO",
	"OYLYO",
	"OYLYO",
	"OYYYO",
	"OYYYO",
	"OYYYO",
	"GGGGG",
]
const WIN_SLIT := [
	".OO.",
	"OYYO",
	"OYLO",
	"OYLO",
	"OYYO",
	"OYYO",
	"GGGG",
]
const WIN_SMALL := [
	".O.",
	"OYO",
	"OLO",
	"OYO",
	"GGG",
]
const DOOR := [
	"..OOO..",
	".OYYYO.",
	"OYYLYYO",
	"OYLLLYO",
	"OYLLLYO",
	"OYLLLYO",
	"OYYLYYO",
	"OYYYYYO",
	"OYYYYYO",
]

## The tower's lit window the ghost lives behind (a generous rectangle to click).
const TOP_WINDOW := Rect2(367, 46, 11, 13)

## Centres of the lit windows, for the view to flicker a glow on them: [centre, radius].
static var _windows: Array = []


static func windows() -> Array:
	land()
	return _windows


## One row of a round wall: lit on the left, falling into shadow on the right.
static func _round_row(x0: int, x1: int, y: int, ramp: Array) -> void:
	var w := x1 - x0
	for x: int in range(x0, x1):
		var u := (x - x0 + 0.5) / w
		var c: Color = ramp[1]
		if x == x0:
			c = ramp[3]
		elif u < 0.36:
			c = ramp[2]
		elif u > 0.72:
			c = ramp[0]
		_px(x, y, c)


## A cone roof, its sides drawn in a little: rows of slates, lit on the left.
static func _cone(cx2: int, y0: int, rows: int, half: float, ramp: Array) -> void:
	for r: int in range(rows):
		var hw := maxf(1.0, half * pow(float(r + 1) / rows, 1.3))
		var x0 := int(floorf(cx2 / 2.0 - hw))
		var x1 := int(ceilf(cx2 / 2.0 + hw))
		for x: int in range(x0, x1):
			var u := (x - x0 + 0.5) / (x1 - x0)
			var c: Color = ramp[1]
			if u < 0.3:
				c = ramp[2]
			elif u > 0.66:
				c = ramp[0]
			if x == x0 and r > 1:
				c = ramp[3]
			# Slate courses: every third row is a shadow line, broken so it does not read as stripes.
			if r % 3 == 2 and (x + r) % 5 != 0 and c != ramp[3]:
				c = ramp[maxi(0, ramp.find(c) - 1)]
			_px(x, y0 + r, c)


static func _tower() -> void:
	_windows.clear()
	var ax := TOWER_X
	var wall := [OUTLINE, STONE[0], STONE[1], STONE[2]]
	var slate := [NIGHT[1], NIGHT[2], NIGHT[3], NIGHT[4]]
	# Shaft: 18 wide, flaring to 20 near the rock.
	for y: int in range(64, TOWER_BASE + 1):
		var hw := 9 if y < 100 else 10
		_round_row(ax - hw, ax + hw, y, wall)
	# Stone courses: a few broken joints, darker on the lit side, lighter in the shadow.
	for k: int in range(46):
		var bx := ax - 8 + _hash(k, 0, 81) % 16
		var by := 66 + (_hash(k, 1, 81) % 15) * 4
		var c := _at(bx, by)
		var run := 2 + _hash(k, 2, 81) % 2
		for i: int in range(run):
			if _at(bx + i, by) == c and bx + i < ax + 8:
				_px(bx + i, by, wall[maxi(0, wall.find(c) - 1)] if wall.find(c) > 0 else STONE[0])
	# Corbels under the gallery.
	for r: int in range(5):
		var hw := 13 - r
		_round_row(ax - hw, ax + hw, 59 + r, wall)
		if r > 0:
			for x: int in range(ax - hw + 1, ax + hw - 1, 3):
				_px(x, 59 + r, OUTLINE)
	# Gallery: the top room, three lit windows.
	for y: int in range(47, 59):
		_round_row(ax - 13, ax + 13, y, wall)
	for x: int in range(ax - 13, ax + 13):
		_px(x, 58, OUTLINE)
	# Eave.
	for x: int in range(ax - 16, ax + 16):
		_px(x, 45, NIGHT[4] if x < ax - 4 else NIGHT[2])
		_px(x, 46, NIGHT[1])
	_cone(ax * 2, 16, 29, 15.5, slate)
	# Finial and its pole.
	_rect(ax, 8, 1, 8, OUTLINE)
	_px(ax - 1, 14, NIGHT[3])
	_px(ax, 14, NIGHT[4])
	_px(ax + 1, 14, NIGHT[1])
	# The side turret on its corbels.
	var tx2 := (ax - 15) * 2 + 1
	for y: int in range(80, 97):
		_round_row(353, 363, y, wall)
	for r: int in range(5):
		_round_row(353 + r, 363, 97 + r, wall)
		_px(353 + r, 97 + r, OUTLINE)
	for x: int in range(351, 365):
		_px(x, 79, NIGHT[4] if x < 356 else NIGHT[2])
	_cone(tx2, 66, 13, 7.0, slate)
	# The annex at the foot, a lean-to with a chimney.
	for y: int in range(104, TOWER_BASE + 1):
		for x: int in range(ax + 10, ax + 26):
			_px(x, y, STONE[0] if x < ax + 20 else OUTLINE)
	for i: int in range(20):
		@warning_ignore("integer_division")
		var ry := 98 + i / 3
		_px(ax + 9 + i, ry, NIGHT[3])
		_px(ax + 9 + i, ry + 1, NIGHT[2])
		_px(ax + 9 + i, ry + 2, NIGHT[1])
	_rect(ax + 20, 90, 3, 12, STONE[0])
	_rect(ax + 22, 90, 1, 12, OUTLINE)
	_rect(ax + 19, 89, 5, 2, STONE[1])
	# Lit windows and the open door.
	_window(WIN_ARCH, ax - 9, 49)
	_window(WIN_ARCH, ax - 2, 49)
	_window(WIN_ARCH, ax + 5, 49)
	_window(WIN_SLIT, ax - 6, 70)
	_window(WIN_SLIT, ax + 1, 87)
	_window(WIN_SLIT, ax - 6, 104)
	_window(WIN_SMALL, 356, 85)
	_window(WIN_SMALL, ax + 14, 110)
	_window(DOOR, ax - 3, 118)
	# Light from the door spills down the first steps.
	for r: int in range(7):
		for x: int in range(ax - 4 - r, ax + 5):
			if _bayer(x, 127 + r) < 0.85 - r * 0.13:
				_px(x, 127 + r, CANDLE[1] if r < 2 else CANDLE[0])


static func _window(rows: Array, x: int, y: int) -> void:
	_stamp(rows, x, y, WIN_PAL)
	var w: int = (rows[0] as String).length()
	_windows.append([Vector2(x + w / 2.0, y + rows.size() / 2.0), 3.0 + w])


# ---------------------------------------------------------------- ground ---
## The meadow in front. POOLS are the pools of lantern light on the grass, [x, reach], under the two swags the
## wizards stand beneath; the left stays dark for the menu.
const POOLS := [[241, 56.0], [377, 76.0]]
const GRASS := [Color("0b0716"), Color("0f2a16"), Color("1c4a22"), Color("2f7a2a")]

## Where the four wizards stand (their feet), left to right in the wizards' order.
const WIZ_SPOTS := [Vector2(222, 254), Vector2(261, 255), Vector2(341, 255), Vector2(413, 254)]


static func _ground_top(x: int) -> int:
	return int(243.0 - 3.0 * _noise(x / 40.0, 0.0, 41) - 1.5 * _noise(x / 9.0, 0.0, 42))


## How brightly the lanterns light the grass at a pixel, as a level on GRASS.
static func _grass_level(x: int, y: int) -> float:
	var lv := 0.0
	for p: Array in POOLS:
		var dx: float = absf(x - p[0]) / p[1]
		if dx < 1.0:
			lv = maxf(lv, (1.0 - dx * dx) * (1.0 - absf(y - 252.0) / 30.0))
	return lv * 1.9 + 0.7 * _noise(x / 5.0, y / 2.5, 45) - 0.3


static func _ground() -> void:
	for x: int in range(W):
		var top := _ground_top(x)
		for y: int in range(top, H):
			_px(x, y, _dith(GRASS, _grass_level(x, y), x, y, 0.6))
		# Blades of grass standing up along the far edge, dark against the water.
		var blade := _hash(x, 0, 43) % 6
		for k: int in range(1, mini(blade, 3) + 1):
			_px(x, top - k, INK)
	# Tufts: a few blades each, a step lighter than the grass they stand in.
	for k: int in range(210):
		var tx := _hash(k, 0, 46) % W
		var ty := _ground_top(tx) + 4 + _hash(k, 1, 46) % 22
		var c: Color = GRASS[clampi(int(_grass_level(tx, ty)) + 1, 1, 3)]
		_px(tx, ty, c)
		_px(tx, ty - 1, c)
		_px(tx - 1, ty - 2, c)
		_px(tx + 1, ty - 1, c)
	# Wild flowers where the light falls.
	for k: int in range(90):
		var fx := _hash(k, 0, 47) % W
		var fy := _ground_top(fx) + 3 + _hash(k, 1, 47) % 23
		if _grass_level(fx, fy) < 0.9:
			continue
		var c: Color = [BONE[3], WIZ[0][0], WIZ[3][0], WIZ[1][0], BONE[2]][_hash(k, 2, 47) % 5]
		_px(fx, fy, c)
		if _hash(k, 3, 47) % 3 == 0:
			_px(fx + 1, fy, c)
			_px(fx, fy - 1, c)
			_px(fx + 1, fy - 1, BONE[3])
	# The wizards' shadows and the far staffs' feet.
	for p: Vector2 in WIZ_SPOTS:
		_shadow(int(p.x), int(p.y), 9)
	_shadow(STAFFS[1][0], STAFFS[1][2], 5)
	_shadow(STAFFS[2][0], STAFFS[2][2], 5)


## A flat shadow on the grass under something standing at (cx, cy).
static func _shadow(cx: int, cy: int, rx: int) -> void:
	for dy: int in range(-1, 2):
		var half := rx - absi(dy) * 3
		for dx: int in range(-half, half + 1):
			_px(cx + dx, cy + dy, INK)


# ====================================================== STAFFS AND GARLAND ===
## The four staffs, left to right in the wizards' order (violet, crimson, emerald, amber):
## [x, the gem's centre y, the y the shaft goes into the ground at, near (1) or far (0)].
## The outer two stand nearer the eye: thicker and planted lower.
const STAFFS := [[24, 96, 270, 1], [184, 108, 259, 0], [298, 116, 259, 0], [456, 100, 270, 1]]

## Wizard colours as ramps: [light, robe, shade, deep shade].
const WIZ := [
	[Color("c9a6ff"), Color("7b4dff"), Color("4b2ab8"), Color("2c1a70")],
	[Color("ff9a6b"), Color("ff3b5c"), Color("a81d3d"), Color("6a1028")],
	[Color("8bff9e"), Color("29d16b"), Color("15864a"), Color("0c5230")],
	[Color("ffe58a"), Color("ffb326"), Color("c26a0e"), Color("7a3f08")],
]

const WOOD_DEEP := Color("2a0e08")
const GOLD_PAL := {"K": Color("0b0716"), "g": Color("ffd94d"), "o": Color("c48a10"), "b": Color("7a2f14"),
	"h": Color("fff6c0"), "w": Color("c85a1e"), "n": Color("7a2f14"), "d": Color("4a1a0c")}

## Staff heads, 23 wide: gold fittings round a gem. The gem's centre is at (11, GEM_ROWS[i]); L M D W are the gem.
const GEM_ROWS := [8, 8, 8, 10]
## The Arcanist's: a crescent cradling an orb.
const HEAD_VIOLET := [
	"....h.............g....",
	"...hg.............go...",
	"..hgg.............goo..",
	"..hg.....LLLMM.....go..",
	".hgg....LLLLMMM....goo.",
	".hgg...LLWWLMMMM...goo.",
	".hggo.LLLWLLMMMMD.ggoo.",
	".hggo.LLLLLMMMMMD.ggoo.",
	".hggo.LLLLMMMMMDD.ggoo.",
	".hggo.LMMMMMMMMDD.ggoo.",
	"..hgo.MMMMMMMMDDD.goo..",
	"..hggo.MMMMMMDDD.ggoo..",
	"...hggo.MMMDDDD.ggoo...",
	"...hgggo.DDDDD.gggoo...",
	"....hggggggggoooooo....",
	".....hgggggoooooob.....",
	".......goooooobb.......",
	".........hgoob.........",
	".......hgggoooob.......",
	"........ggoooob........",
	".........hgoob.........",
]
## The Pyromancer's: a flame of ruby in a basket of claws.
const HEAD_CRIMSON := [
	"............L..........",
	"...........LM..........",
	"..h.......LLM.......g..",
	"..hg......LLMM.....go..",
	"..hgg....LLLMM....ggo..",
	"...hgo...LLWMMM..goo...",
	"....hg..LLWWMMMD.go....",
	"....hg.LLLWLMMMD.go....",
	"....hg.LLLLMMMMD.go....",
	"....hg.LLMMMMMDD.go....",
	"....hg.LMMMMMDDD.go....",
	".....hg.MMMMDDD.go.....",
	".....hgg.MDDDD.goo.....",
	"......hgggggooooo......",
	".......ggggoooob.......",
	"........ggoooob........",
	".........hgoob.........",
	".......hgggoooob.......",
	"........ggoooob........",
	".........hgoob.........",
]
## The Frostwarden's: shards of green ice in a fork.
const HEAD_EMERALD := [
	"...........L...........",
	"..........LLM..........",
	".........LLMMD.........",
	"........LLLMMDD........",
	"...L....LWLMMDD........",
	"...LL...LWLMMDD........",
	"...LLM..LWLMMDD....M...",
	"....LMM.LLLMMDD...MD...",
	"....LMD.LLLMMDD..LMD...",
	".....MD.LLLMMDD.MMD....",
	".....MD.LLMMMDD.MD.....",
	"....hgK.LLMMMDD.Kgo....",
	"....hggK.LMMDD.Kgoo....",
	".....hggK.MDD.Kgoo.....",
	"......hgggKKKgooo......",
	".......hggggooob.......",
	".........hgoob.........",
	".......hgggoooob.......",
	"........ggoooob........",
	".........hgoob.........",
]
## The Stormcaller's: a sun wheel round an amber eye.
const HEAD_AMBER := [
	"...........h...........",
	"...........g...........",
	"..........hgo..........",
	"...h.....hgggo.....o...",
	"....g..hhggggooo..o....",
	".....ghggKKKKKgooo.....",
	".....hggKLLLMMKgoo.....",
	".....hgKLLWLMMMKgo.....",
	"....hgKLLWWLMMMDKgo....",
	"...hhgKLLWLMMMMDKgoo...",
	".hgghgKLLLMMMMDDKgoooo.",
	"...ghgKLLMMMMMDDKoob...",
	"....hgKLMMMMMDDDKoo....",
	".....ggKMMMMDDDKoo.....",
	".....ggoKMDDDDKoob.....",
	".....gggoKKKKKoobb.....",
	"....g..gggooooob..b....",
	"...g.....goobb.....b...",
	".........hgoob.........",
	".......hgggoooob.......",
	"........ggoooob........",
	".........hgoob.........",
]
const HEADS := [HEAD_VIOLET, HEAD_CRIMSON, HEAD_EMERALD, HEAD_AMBER]

const LEAF_PAL := {"l": Color("6fd23c"), "m": Color("2f7a2a"), "d": Color("1c4a22"), "s": Color("0f2a16")}
## Laurel leaves in pairs along the vine, pointing right (stamped flipped on the far half of a swag).
const LEAF_UP := [
	"..ml.",
	".mll.",
	"dmm..",
]
const LEAF_DOWN := [
	"dmm..",
	".dmm.",
	"..dm.",
]
const FLOWER_BIG := [
	"..ppp..",
	".pPPPp.",
	"pPPyPPp",
	"pPyyyPp",
	"pPPyPpq",
	".pPPpq.",
	"..pqq..",
]
const FLOWER_ROSE := [
	".pPp.",
	"pPPPp",
	"PPyPp",
	"pPPpq",
	".ppq.",
]
const FLOWER_STAR := [
	"..P..",
	".PPp.",
	"PPyPp",
	".pPp.",
	"..p..",
]
const FLOWER_BUD := [
	".P.",
	"PyP",
	".p.",
]
## A bow of ribbon where the garland is tied to a staff. R r are the staff's wizard colour.
const BOW := [
	".LL...LL.",
	"LRRL.LRRr",
	"LRRRgRRRr",
	".rRRgRRr.",
	"..rr.rr..",
]

## Where the garland is tied to each staff, below the gem, and how far each of its three swags hangs.
const TIE_DROP := 16
const SAG := [5.0, 14.0, 20.0]

## Lanterns hanging from the garland, for the view to sway: [the knot on the garland, cord length, phase].
static var _lanterns: Array = []


static func lanterns() -> Array:
	fore()
	return _lanterns


static func gem_pos(i: int) -> Vector2:
	return Vector2(STAFFS[i][0], STAFFS[i][1])


static func tie_pos(i: int) -> Vector2:
	return Vector2(STAFFS[i][0], STAFFS[i][1] + TIE_DROP)


## The garland's height at x on swag `k` (between staff k and k + 1).
static func swag_y(k: int, x: float) -> float:
	var a := tie_pos(k)
	var b := tie_pos(k + 1)
	var u := clampf((x - a.x) / (b.x - a.x), 0.0, 1.0)
	return lerpf(a.y, b.y, u) + 4.0 * SAG[k] * u * (1.0 - u)


static func bake_fore() -> Image:
	_begin(W, H)
	_lanterns.clear()
	for k: int in range(3):
		_garland(k)
	for i: int in range(4):
		_staff(i)
	_ink_edges()
	return _img


## A staff: a dark wooden shaft, gold bands, a few leaves still sprouting from it, and its head.
static func _staff(i: int) -> void:
	var x: int = STAFFS[i][0]
	var gy: int = STAFFS[i][1]
	var base: int = STAFFS[i][2]
	var near: bool = STAFFS[i][3] == 1
	var head: Array = HEADS[i]
	var top: int = gy - GEM_ROWS[i] + head.size()
	var w := 5 if near else 4
	var wood: Array = [GOLD_PAL["n"], GOLD_PAL["w"], GOLD_PAL["n"], GOLD_PAL["d"], WOOD_DEEP]
	if not near:
		wood = [GOLD_PAL["n"], GOLD_PAL["w"], GOLD_PAL["d"], WOOD_DEEP]
	for y: int in range(top, base):
		for k: int in range(w):
			var c: Color = wood[k]
			# The grain: the lit line breaks, and darker flecks run in the middle of the shaft.
			@warning_ignore("integer_division")
			if k == 1 and _rnd(y / 3, i, 96) < 0.45:
				c = GOLD_PAL["n"]
			elif k == 2 and _rnd(y / 2, i, 97) < 0.2:
				c = GOLD_PAL["d"]
			elif k == 0 and _rnd(y / 4, i, 99) < 0.3:
				c = GOLD_PAL["d"]
			_px(x - 2 + k, y, c)
	# Gold bands: where the garland is tied, and two more down the shaft.
	var tie := gy + TIE_DROP
	@warning_ignore("integer_division")
	for by: int in [tie - 1, tie + 2, top + (base - top) / 2, base - 14]:
		for k: int in range(-1, w + 1):
			var u := float(k + 1) / (w + 1)
			_px(x - 2 + k, by, GOLD_PAL["h"] if u < 0.2 else (GOLD_PAL["g"] if u < 0.6 else GOLD_PAL["o"]))
			_px(x - 2 + k, by + 1, GOLD_PAL["g"] if u < 0.3 else (GOLD_PAL["o"] if u < 0.8 else GOLD_PAL["b"]))
	# Leaves still sprouting from the wood, as on the card.
	for k: int in range(3):
		var ly := top + 34 + k * 31 + _hash(i, k, 98) % 13
		if ly > base - 22 or ly > H - 8:
			continue
		var left := (k + i) % 2 == 0
		_stamp(LEAF_UP, x + (-7 if left else w - 2), ly - 2, LEAF_PAL, left)
	var pal := GOLD_PAL.duplicate()
	pal["W"] = Color("ffffff")
	pal["L"] = WIZ[i][0]
	pal["M"] = WIZ[i][1]
	pal["D"] = WIZ[i][2]
	_stamp(head, x - 11, gy - GEM_ROWS[i], pal)
	# The bow the garland is tied with.
	var bow := {"L": WIZ[i][0], "R": WIZ[i][1], "r": WIZ[i][2], "g": GOLD_PAL["g"]}
	_stamp(BOW, x - 4, tie - 1, bow)


static func _garland(k: int) -> void:
	var a := tie_pos(k)
	var b := tie_pos(k + 1)
	var x0 := int(a.x) + 4
	var x1 := int(b.x) - 3
	@warning_ignore("integer_division")
	var mid := (x0 + x1) / 2
	# The vine, then laurel leaves in pairs along it, each half pointing to the middle of the swag.
	for x: int in range(x0, x1):
		var y := int(roundf(swag_y(k, x)))
		_px(x, y, LEAF_PAL["d"])
		_px(x, y + 1, LEAF_PAL["s"])
	var x := x0
	while x < x1 - 4:
		var flip := x >= mid
		var y := int(roundf(swag_y(k, x + 2)))
		_stamp(LEAF_UP, x, y - 3, LEAF_PAL, flip)
		_stamp(LEAF_DOWN, x + (1 if flip else -1), y + 1, LEAF_PAL, flip)
		x += 4
	# Flowers along it: a big rosette in the middle, roses and stars either side, buds between.
	var cream := [Color("fff6e0"), Color("e8dcc0"), Color("ffd94d"), Color("b7a98e")]
	var cols: Array = [cream, [WIZ[1][0], WIZ[1][1], Color("ffd94d"), WIZ[1][2]],
		[WIZ[0][0], WIZ[0][1], Color("fff6c0"), WIZ[0][2]], [WIZ[3][0], WIZ[3][1], Color("fff6e0"), WIZ[3][2]]]
	var n := int((x1 - x0) / 15.0)
	for j: int in range(n + 1):
		var fx := x0 + 6 + int(j * (x1 - x0 - 12) / float(n))
		var y := int(roundf(swag_y(k, fx)))
		var col: Array = cols[(j * 3 + k) % 4]
		var pal := {"P": col[0], "p": col[1], "y": col[2], "q": col[3]}
		if absi(fx - mid) < 7:
			_stamp(FLOWER_BIG, fx - 3, y - 3, pal)
		elif j % 2 == 0:
			_stamp(FLOWER_ROSE, fx - 2, y - 2, pal)
		else:
			_stamp(FLOWER_STAR, fx - 2, y - 2, pal)
		# A bud or a berry between two flowers.
		if j < n:
			var bx := fx + int((x1 - x0 - 12) / float(n) / 2.0)
			var by := int(roundf(swag_y(k, bx)))
			var bcol: Array = cols[(j + k * 2 + 1) % 4]
			_stamp(FLOWER_BUD, bx - 1, by - 1 + (j % 2) * 2 - 1, {"P": bcol[0], "p": bcol[1], "y": bcol[2]})
	# Lanterns hang where the swag leaves room for them: the first swag keeps clear of the menu under it.
	var spots: Array = [[0.1, 0.9], [0.22, 0.5, 0.78], [0.15, 0.38, 0.62, 0.85]][k]
	for u: float in spots:
		var lx := int(lerpf(a.x, b.x, u))
		_lanterns.append([Vector2(lx, int(roundf(swag_y(k, lx))) + 3), 3 + _hash(lx, k, 91) % 4, _rnd(lx, k, 92) * TAU])


## Draws a dark outline round everything on the image so far.
static func _ink_edges(c: Color = INK) -> void:
	var edge: Array[Vector2i] = []
	for y: int in range(_ih):
		for x: int in range(_iw):
			if _img.get_pixel(x, y).a > 0.0:
				continue
			if _at(x - 1, y).a > 0.0 or _at(x + 1, y).a > 0.0 or _at(x, y - 1).a > 0.0 or _at(x, y + 1).a > 0.0:
				edge.append(Vector2i(x, y))
	for p: Vector2i in edge:
		_img.set_pixel(p.x, p.y, c)


# =============================================================== SPRITES ===
## The small things the view draws itself each frame, baked once into textures by key: the lantern (lit and
## unlit), the ghost, and the four wizards at title size, three frames each: `wiz0_a` and `wiz0_b` cheer,
## `wiz0_c` thrusts the wand up as a rocket leaves it.
static var _sprites: Dictionary = {}
## Where each wizard's wand tip is in each frame, measured from the sprite's feet: _wand_tips[wizard][frame].
static var _wand_tips: Array = []

const LANTERN := [
	"...g...",
	"..ooo..",
	".ggggg.",
	".OYLYO.",
	".OLWLO.",
	".OYLYO.",
	".OYYYO.",
	".ggggg.",
	"..obo..",
	"...b...",
]
const LANTERN_LIT := {"g": Color("ffd94d"), "o": Color("c48a10"), "b": Color("7a2f14"), "O": Color("ff9a3c"),
	"Y": Color("ffcf5a"), "L": Color("fff6c0"), "W": Color("ffffff")}
const LANTERN_DARK := {"g": Color("c48a10"), "o": Color("7a2f14"), "b": Color("4a1a0c"), "O": Color("2a1f45"),
	"Y": Color("3a2a5e"), "L": Color("4b3a78"), "W": Color("5c4a8e")}

const GHOST_A := [
	"....LLLLL....",
	"..LLLLLLLLL..",
	".LLLLLLLLLLm.",
	".LLEELLLEELm.",
	"LLLEELLLEELLm",
	"LLLLLLLLLLLmm",
	"LLLLLEEELLLmm",
	"LLLLLEEELLmmd",
	"LLLLLLLLLLmmd",
	"mLLLLLLLLmmmd",
	"mLLLLLLLmmmdd",
	".mLLmLLmmdmd.",
	".mLm.mLm.dd..",
	"..m...m...d..",
]
const GHOST_B := [
	"....LLLLL....",
	"..LLLLLLLLL..",
	".LLLLLLLLLLm.",
	".LLEELLLEELm.",
	"LLLEELLLEELLm",
	"LLLLLLLLLLLmm",
	"LLLLLEEELLLmm",
	"LLLLLEEELLmmd",
	"LLLLLLLLLLmmd",
	"mLLLLLLLLmmmd",
	"mLLLLLLLmmmdd",
	"mLLLmLLLmmdmd",
	".mL..mLm..md.",
	".m....m...d..",
]
const GHOST_PAL := {"L": Color("d8fff6"), "m": Color("32e0c4"), "d": Color("158f86"), "E": Color("0b0716")}

## The four wizards without their arms, 21 wide and 36 tall, each the same character as in the game. Shared
## letters: robe (L R r d), trim (hem and buttons Y y G), skin (S s n), eyes E, mouth M, shoes (k K), belt (U u).
## The violet one: a tall crooked hat (H h i) with a gold band and a long white beard (W B b).
const WIZ_BODY := [
	"............HH.......",
	"...........iHHh......",
	"..........iHHh.......",
	"..........iHHh.......",
	".........iHHHh.......",
	".........iHHHhh......",
	"........iHHHHhh......",
	"........iHHHHHhh.....",
	".......iHHHHHHhh.....",
	"......iiHHHHHHhhh....",
	".....YYYYGGYYYYyy....",
	".....yYYYGGYYYyyy....",
	".iiHHHHHHHHHHHHHhhhh.",
	"hhhhhhhhhhhhhhhhhhddd",
	".....sssssssssss.....",
	".....SSESSSSSESs.....",
	".....SSESSnSSESs.....",
	".....SWWWWnWWWWs.....",
	"...LRWWWWMMMWWBBrr...",
	"...LRWWWWWWWWBBbrr...",
	"...LRWWWbWWWbWBbrd...",
	"...LRRWWWWWWBBbRrd...",
	"...LRRWWbWWWBBbRrd...",
	"..LLRRRWWWWBBbRRrrd..",
	"..LLRRRWWbWBBbRRrrd..",
	"..LLRRRRWWWBbRRRrrd..",
	"..LLRRRRRWBbRRRRrrd..",
	"..LLRRRRRRBRRRRRrrd..",
	".LLRRRRRRRYRRRRRRrrd.",
	".LLRRRRrRRRRRRrRRrrd.",
	".LLRRRRrRRYRRRrRRrrd.",
	".LLRRRRrRRRRRRrRRrrd.",
	"LLLRRRRrRRYRRRrRRrrdd",
	"LLLRRRRrRRRRRRrRRrrdd",
	"GYYYYYYyYYYYYYyYYyyyy",
	".....kkkK...kkkK.....",
]
## The crimson one: a hood (i H h) crowned with tongues of flame (F f w), a black face (V) with two lit eyes (e a).
const WIZ_HOOD := [
	"..........F..........",
	".........FF..........",
	".........FFf....F....",
	"....F...fFwF....Ff...",
	"....FF..fFwFf..fFF...",
	"...fFF..FFwwF..FwFf..",
	"...fFwfifFwwFfhFwFf..",
	"....fFFiHfFFfHHfFf...",
	"...iiHHHHHHHHHHHhh...",
	"..iiHHHHHHHHHHHHHhh..",
	"..iHHHHdddddddHHHhh..",
	"..iHHHdVVVVVVVdHHhh..",
	"..iHHdVVVVVVVVVdHhh..",
	"..iHHVVeeVVVeeVVHhd..",
	"..iHHVVaaVVVaaVVHhd..",
	"..iHHVVVVVVVVVVVHhd..",
	"...iHHVVVVVVVVVHhd...",
	"...iHHHVVVVVVVHHhd...",
	"...LiHHHVVVVVHHHhr...",
	"...LRhHHHVVVHHHhrr...",
	"...LRRhhHHhHHhhRrr...",
	"...LRRRRhhhhhRRRrr...",
	"...LRRRRRRRRRRRRrr...",
	"..LLRRRRRRRRRRRRrrd..",
	"..LLRRRRRRRRRRRRrrd..",
	"..UUUUUUUUgUUUUUUuu..",
	"..LLRRRRRRRRRRRRrrd..",
	"..LLRRRRRRRRRRRRrrd..",
	".LLRRRRRRRRRRRRRRrrd.",
	".LLRRRRrRRRRRRrRRrrd.",
	".LLRRRRrRRRRRRrRRrrd.",
	".LLRRRRrRRRRRRrRRrrd.",
	"LLLRRRRrRRRRRRrRRrrdd",
	"LLLRRRRrRRRRRRrRRrrdd",
	"GYYYYYYyYYYYYYyYYyyyy",
	".....kkkK...kkkK.....",
]
## His flames as they flicker: the top six rows of the second frame.
const WIZ_FLAMES_LOW := [
	".....................",
	".........F......F....",
	"....F....FF.....F....",
	"....F...fFFf...fFf...",
	"...fFF..fFwF...FwF...",
	"...FwF..FwwFf..FwFf..",
]
## The emerald one: a pointed leaf of a hood whose tip leans over (i H h), a young pale face, frost-blue hair
## (I j) and a fur mantle (W B b).
const WIZ_LEAF := [
	"..............Hh.....",
	"............iHHh.....",
	"...........iHHHh.....",
	".........iiHHHHh.....",
	"........iHHHiHHhh....",
	".......iHHHHiHHHh....",
	"......iHHHHHiHHHhh...",
	".....iHHHHHiHHHHHh...",
	"....iHHHHHHiHHHHHhh..",
	"...iiHHHHHHHHHHHHhh..",
	"...iHHIIIIIIIIIHHhh..",
	"...iHIISSSSSSSIIHhh..",
	"...iHISSESSSESSIHhh..",
	"...iHISSESSSESSIHhh..",
	"...iHIsSSSSSSSsIHhh..",
	"...iHIISSnMnSSIIHh...",
	"....hHIIsSSSsIIHh....",
	"...WWIIWWWWWWWIIBb...",
	"...WWIjWWBWWWWIjBb...",
	"...WBIjWBWWBWBIjBb...",
	"...bRIjbRbBRbRIjbr...",
	"...LRjRRRRRRRRRjrr...",
	"...LRRRRRRRRRRRRrr...",
	"..LLRRRRRRRRRRRRrrd..",
	"..LLRRRRRRRRRRRRrrd..",
	"..UUUUUUUUgUUUUUUuu..",
	"..LLRRRRRRRRRRRRrrd..",
	"..LLRRRRRRRRRRRRrrd..",
	".LLRRRRRRRRRRRRRRrrd.",
	".LLRRRRrRRRRRRrRRrrd.",
	".LLRRRRrRRRRRRrRRrrd.",
	".LLRRRRrRRRRRRrRRrrd.",
	"LLLRRRRrRRRRRRrRRrrdd",
	"LLLRRRRrRRRRRRrRRrrdd",
	"GYYYYYYyYYYYYYyYYyyyy",
	".....kkkK...kkkK.....",
]
## The amber one: a wide straw cone (i H h D) with a cyan band (C c), a long moustache (N m) under the hat's
## shadow, an orange robe darker below its cyan sash (P p X).
const WIZ_STRAW := [
	".....................",
	".....................",
	".....................",
	".....................",
	".........DDD.........",
	"........iHHhh........",
	".......CCCCCcc.......",
	"......iiHHHHhhh......",
	".....iiHiHHHhHhh.....",
	"....iiHHiHHHhHHhh....",
	"...iiHHHiHHHHhHHhh...",
	"..iiHHHiHHHHHhHHHhh..",
	".iiHHHHiHHHHHHhHHHhh.",
	"iiHHHHiHHHHHHHHhHHHhh",
	".DDDDDDDDDDDDDDDDDDD.",
	".....sssssssssss.....",
	".....sSESSSSSESs.....",
	".....sNNNNnNNNNs.....",
	"...LRRNNSSMSSNNRrr...",
	"...LRRNNRsssRNNRrr...",
	"...LRRNmRRRRRmNRrr...",
	"...LRRNRRRRRRRNRrr...",
	"...LRRmRRRRRRRmRrr...",
	"..LLRRRRRRRRRRRRrrd..",
	"..LLRRRRRRRRRRRRrrd..",
	"..UUUUUUUUUUUUUUUuu..",
	"..RRPPPPPPPPPPPPppX..",
	"..RRPPPPPPPPPPPPppX..",
	".RRPPPPPPPPPPPPPPppX.",
	".RRPPPPpPPPPPPpPPppX.",
	".RRPPPPpPPPPPPpPPppX.",
	".RRPPPPpPPPPPPpPPppX.",
	"RRRPPPPpPPPPPPpPPppXX",
	"RRRPPPPpPPPPPPpPPppXX",
	"GYYYYYYyYYYYYYyYYyyyy",
	".....kkkK...kkkK.....",
]
const WIZ_BODIES := [WIZ_BODY, WIZ_HOOD, WIZ_LEAF, WIZ_STRAW]
## Arms. The raised ones end in a fist the wand or the cup stands in. The wrist row is the cuff (Q q z x).
const ARM_UP_L := [
	".SS.......",
	".SSs......",
	"QQqz......",
	"LRRRr.....",
	"dLRRRr....",
	".dLRRRr...",
	"..drRRRr..",
	"....rRRRr.",
	".....rRRr.",
]
const ARM_UP_R := [
	"........SS",
	".......sSS",
	"......Qqzz",
	".....LRRRr",
	"....LRRRrd",
	"...LRRRrd.",
	"..LRRRrd..",
	".LRRRr....",
	".LRRr.....",
]
const ARM_OUT_L := [
	".SS......",
	".SSs.....",
	"QQqqz....",
	"LRRRRRr..",
	".dRRRRRRr",
	"...drRRRr",
]
const ARM_HIP_L := [
	"..LR",
	".LRR",
	"LLRr",
	"LRRr",
	"LRRr",
	"LRrd",
	".Qqz",
	"..Ss",
]
const ARM_HIP_R := [
	"RR..",
	"Rrr.",
	"Rrrd",
	"Rrrd",
	"Rrrd",
	"Rrd.",
	"zx..",
	"Ss..",
]
const WAND := ["T", "T", "g", "g", "o", "g", "o"]
const CUP := [
	"MMMMM",
	"TgggO",
	"TgggO",
	".ggO.",
	"..O..",
]

## The canvas a wizard is drawn on and where the body's top left corner sits in it.
const WIZ_CANVAS := Vector2i(37, 42)
const WIZ_ORIGIN := Vector2i(8, 6)
## Each wizard's pose: [left arm, right arm, the wand's hand (0 left, 1 right)].
const WIZ_LOOKS := [["up", "up", 1], ["up", "hip", 0], ["out", "up", 1], ["up", "up", 0]]


static func sprite(key: String) -> ImageTexture:
	if _sprites.is_empty():
		_bake_sprites()
	return _sprites[key]


## Draws sprite `key` standing on `feet` (its bottom centre).
static func draw_sprite(ci: CanvasItem, key: String, feet: Vector2, modulate: Color = Color.WHITE) -> void:
	var tex := sprite(key)
	var at := Vector2(roundf(feet.x - tex.get_width() / 2.0), roundf(feet.y - tex.get_height()))
	ci.draw_texture(tex, at, modulate)


## Where wizard `i`'s wand tip is in frame `f` (0, 1 or 2), measured from his feet.
static func wand_tip(i: int, f: int) -> Vector2:
	if _sprites.is_empty():
		_bake_sprites()
	return _wand_tips[i][f]


## The sprite images by key, for previews.
static func sprite_images() -> Dictionary:
	var out := {}
	out["lantern"] = _sprite_image(LANTERN, LANTERN_LIT, INK)
	out["lantern_off"] = _sprite_image(LANTERN, LANTERN_DARK, INK)
	out["ghost_a"] = _sprite_image(GHOST_A, GHOST_PAL, Color(0, 0, 0, 0))
	out["ghost_b"] = _sprite_image(GHOST_B, GHOST_PAL, Color(0, 0, 0, 0))
	_wand_tips.clear()
	for i: int in range(4):
		_wand_tips.append([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		for f: int in range(3):
			out["wiz%d_%s" % [i, "abc"[f]]] = _wizard(i, f)
	return out


static func _bake_sprites() -> void:
	var images := sprite_images()
	for key: String in images:
		_sprites[key] = ImageTexture.create_from_image(images[key])


## An ASCII map as an image with a clear border, outlined in `edge` (clear for none).
static func _sprite_image(rows: Array, pal: Dictionary, edge: Color) -> Image:
	_begin((rows[0] as String).length() + 2, rows.size() + 2)
	_stamp(rows, 1, 1, pal)
	if edge.a > 0.0:
		_ink_edges(edge)
	return _img


static func _wizard(i: int, f: int) -> Image:
	_begin(WIZ_CANVAS.x, WIZ_CANVAS.y)
	var look: Array = WIZ_LOOKS[i]
	var pal := _title_wiz_pal(i)
	var ox := WIZ_ORIGIN.x
	var oy := WIZ_ORIGIN.y
	# In the second frame he sinks a pixel: everything above the hem moves down and one row of the robe goes.
	var bob := 1 if f == 1 else 0
	var body: Array = (WIZ_BODIES[i] as Array).duplicate()
	if i == 1 and f == 1:
		for r: int in range(WIZ_FLAMES_LOW.size()):
			body[r] = WIZ_FLAMES_LOW[r]
	_stamp(body.slice(0, 31 - bob), ox, oy + bob, pal)
	_stamp(body.slice(31), ox, oy + 31, pal)
	# Arms. A raised arm stays where it was while the body sinks, and thrusts up two pixels to cast.
	for side: int in range(2):
		var pose: String = look[side]
		var wand_here: bool = look[2] == side
		var lift := -2 if (f == 2 and wand_here) else 0
		var hand := Vector2i.ZERO
		match pose:
			"up":
				if side == 0:
					_stamp(ARM_UP_L, ox - 3, oy + 11 + lift, pal)
					hand = Vector2i(ox - 2, oy + 11 + lift)
				else:
					_stamp(ARM_UP_R, ox + 15, oy + 11 + lift, pal)
					hand = Vector2i(ox + 24, oy + 11 + lift)
			"out":
				_stamp(ARM_OUT_L, ox - 4, oy + 15 + bob, pal)
				_stamp(CUP, ox - 5, oy + 11 + bob, pal)
			"hip":
				if side == 0:
					_stamp(ARM_HIP_L, ox + 1, oy + 18 + bob, pal)
				else:
					_stamp(ARM_HIP_R, ox + 16, oy + 18 + bob, pal)
		if wand_here:
			_stamp(WAND, hand.x, hand.y - WAND.size(), pal)
			_wand_tips[i][f] = Vector2(hand.x + 0.5 - WIZ_CANVAS.x / 2.0, hand.y - WAND.size() - WIZ_CANVAS.y)
	_ink_edges(OUTLINE)
	return _img


## The colours behind wizard `i`'s map letters.
static func _title_wiz_pal(i: int) -> Dictionary:
	var ramp: Array = WIZ[i]
	var pal := {"H": ramp[1], "h": ramp[2], "i": ramp[0], "L": ramp[0], "R": ramp[1], "r": ramp[2], "d": ramp[3],
		"Q": ramp[0], "q": ramp[1], "z": ramp[2], "x": ramp[3], "U": ramp[2], "u": ramp[3],
		"Y": Color("ffd94d"), "y": Color("c48a10"), "G": Color("fff6c0"),
		"S": Color("ffd2a6"), "s": Color("c98a6b"), "n": Color("c98a6b"), "E": INK, "M": Color("7a1226"),
		"W": Color("fff6e0"), "B": Color("e8dcc0"), "b": Color("b7a98e"), "k": Color("4a1a0c"), "K": OUTLINE,
		"T": Color("fff6c0"), "g": Color("ffd94d"), "o": Color("c48a10"), "O": Color("c48a10")}
	match i:
		1:
			# Fire: the flames, the eyes in the dark of the hood, and the cuffs and hem.
			pal.merge({"F": Color("ffcf5a"), "f": Color("ff9a3c"), "w": Color("fff6c0"), "V": INK,
				"e": Color("ffcf5a"), "a": Color("ff9a3c"), "Y": Color("ff9a3c"), "y": Color("c85a1e"),
				"G": Color("ffcf5a"), "Q": Color("ffcf5a"), "q": Color("ff9a3c"), "z": Color("c85a1e"),
				"x": Color("c85a1e")}, true)
		2:
			# Frost: ice-blue hair, and fur at the collar, the cuffs and the hem.
			pal.merge({"I": Color("8fe3ff"), "j": Color("4fa3d8"), "Y": Color("e8dcc0"), "y": Color("b7a98e"),
				"G": Color("fff6e0"), "Q": Color("fff6e0"), "q": Color("e8dcc0"), "z": Color("b7a98e"),
				"x": Color("7d705c")}, true)
		3:
			# Straw and cyan: the hat, the dark moustache, the sash, cuffs and hem, and the darker skirt.
			pal.merge({"H": Color("ffe58a"), "h": Color("c48a10"), "i": Color("fff6c0"), "D": Color("7a3d0a"),
				"C": Color("4dfff0"), "c": Color("158f86"), "N": Color("4a1a0c"), "m": Color("7a2f14"),
				"P": ramp[2], "p": ramp[3], "X": Color("4f2606"), "U": Color("4dfff0"), "u": Color("158f86"),
				"Y": Color("4dfff0"), "y": Color("158f86"), "G": Color("d8fff6"), "Q": Color("4dfff0"),
				"q": Color("4dfff0"), "z": Color("158f86"), "x": Color("158f86")}, true)
	return pal
# ========================================================== LOGO LETTERS ===
## The logo's capitals as pixel maps, 33 tall: '#' is the letter. Drawn for this logo, not a font.
const LOGO_F := [
	"########################",
	"########################",
	".#######################",
	"..######################",
	"...#######..........####",
	"...#######...........###",
	"...#######...........###",
	"...#######............##",
	"...#######.............#",
	"...#######..............",
	"...#######..............",
	"...#######.........#....",
	"...#######........##....",
	"...#################....",
	"...#################....",
	"...#################....",
	"...#################....",
	"...#######........##....",
	"...#######.........#....",
	"...#######..............",
	"...#######..............",
	"...#######..............",
	"...#######..............",
	"...#######..............",
	"...#######..............",
	"...#######..............",
	"...#######..............",
	"...#######..............",
	"...########.............",
	"..##########............",
	".############...........",
	"##############..........",
	"##############..........",
]
const LOGO_O := [
	"..........#########..........",
	"........#############........",
	"......#################......",
	".....###################.....",
	"....########.....########....",
	"...########.......########...",
	"...#######.........#######...",
	"..#######...........#######..",
	"..#######...........#######..",
	".#######.............#######.",
	".#######.............#######.",
	".#######.............#######.",
	"#######...............#######",
	"#######...............#######",
	"#######...............#######",
	"#######...............#######",
	"#######...............#######",
	"#######...............#######",
	"#######...............#######",
	"#######...............#######",
	"#######...............#######",
	".#######.............#######.",
	".#######.............#######.",
	".#######.............#######.",
	"..#######...........#######..",
	"..#######...........#######..",
	"...#######.........#######...",
	"...########.......########...",
	"....########.....########....",
	".....###################.....",
	"......#################......",
	"........#############........",
	"..........#########..........",
]
const LOGO_U := [
	"#############.......###########",
	"#############.......###########",
	".###########.........#########.",
	"..#########...........#######..",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"...#######.............#####...",
	"....#######...........#####....",
	"....########.........######....",
	".....#######.........#####.....",
	".....#########.....#######.....",
	"......###################......",
	"........###############........",
	".........#############.........",
	"............#######............",
]
const LOGO_R := [
	"#####################........",
	"#######################......",
	".#######################.....",
	"..#######################....",
	"...#######.........#######...",
	"...#######..........######...",
	"...#######..........#######..",
	"...#######..........#######..",
	"...#######..........#######..",
	"...#######..........#######..",
	"...#######..........#######..",
	"...#######..........#######..",
	"...#######..........######...",
	"...#######.........#######...",
	"...######################....",
	"...#####################.....",
	"...####################......",
	"...###################.......",
	"...#######.....########......",
	"...#######......#######......",
	"...#######......########.....",
	"...#######......########.....",
	"...#######.......#######.....",
	"...#######.......########....",
	"...#######........#######....",
	"...#######........########...",
	"...#######........########...",
	"...#######.........#######...",
	"...#######.........########..",
	"..#########.........#######..",
	".###########........########.",
	"#############.......#########",
	"#############........########",
]
const LOGO_W := [
	"#############....#######......##########",
	"#############....#######......##########",
	".###########.....#######.......########.",
	"..#########......########.......######..",
	"...########......########.......#####...",
	"....#######.....#########.......####....",
	"....#######.....#########.......####....",
	"....#######.....#########......####.....",
	"....#######.....##########.....####.....",
	".....#######....##########.....####.....",
	".....#######...###########.....####.....",
	".....#######...###########....####......",
	".....#######...###########....####......",
	".....#######...####.#######...####......",
	".....#######...####.#######...####......",
	"......#######..####.#######...####......",
	"......#######.####..#######..####.......",
	"......#######.####..#######..####.......",
	"......#######.####...#######.####.......",
	"......#######.####...#######.####.......",
	".......###########...#######.####.......",
	".......##########....###########........",
	".......##########....###########........",
	".......##########.....##########........",
	".......##########.....##########........",
	".......##########.....#########.........",
	"........########......#########.........",
	"........########......#########.........",
	"........########......#########.........",
	"........########.......########.........",
	"........########.......#######..........",
	"........#######........#######..........",
	".........#######.......#######..........",
]
const LOGO_A := [
	".............########............",
	".............########............",
	"............#########............",
	"............##########...........",
	"............##########...........",
	"...........###########...........",
	"...........###########...........",
	"...........####.#######..........",
	"..........####..#######..........",
	"..........####..#######..........",
	"..........####...#######.........",
	"..........####...#######.........",
	".........####....#######.........",
	".........####....#######.........",
	".........####.....#######........",
	"........####......#######........",
	"........####......#######........",
	"........####.......#######.......",
	".......####........#######.......",
	".......####........#######.......",
	".......###################.......",
	"......#####################......",
	"......#####################......",
	"......####..........#######......",
	"......####...........#######.....",
	".....####............#######.....",
	".....####............#######.....",
	".....####............#######.....",
	"...#####..............########...",
	"..######..............#########..",
	".########............###########.",
	"##########..........#############",
	"##########..........#############",
]
const LOGO_N := [
	"###########........##########",
	"############.......##########",
	".###########........########.",
	"..###########........######..",
	"...##########.........####...",
	"...###########........####...",
	"...###########........####...",
	"...###########........####...",
	"...############.......####...",
	"...############.......####...",
	"...####.########......####...",
	"...####.########......####...",
	"...####..########.....####...",
	"...####..########.....####...",
	"...####...########....####...",
	"...####...########....####...",
	"...####...#########...####...",
	"...####....########...####...",
	"...####....########...####...",
	"...####.....########..####...",
	"...####.....########..####...",
	"...####......########.####...",
	"...####......########.####...",
	"...####.......############...",
	"...####.......############...",
	"...####........###########...",
	"...####........###########...",
	"...####........###########...",
	"...####.........##########...",
	"..######........##########...",
	".########........#########...",
	"##########.......#########...",
	"##########........########...",
]
const LOGO_D := [
	"####################..........",
	"######################........",
	".#######################......",
	"..#######################.....",
	"...#######.........#######....",
	"...#######..........#######...",
	"...#######...........######...",
	"...#######...........#######..",
	"...#######............######..",
	"...#######............#######.",
	"...#######............#######.",
	"...#######............#######.",
	"...#######.............#######",
	"...#######.............#######",
	"...#######.............#######",
	"...#######.............#######",
	"...#######.............#######",
	"...#######.............#######",
	"...#######.............#######",
	"...#######.............#######",
	"...#######.............#######",
	"...#######............#######.",
	"...#######............#######.",
	"...#######............#######.",
	"...#######............######..",
	"...#######...........#######..",
	"...#######...........######...",
	"...#######..........#######...",
	"...#######.........#######....",
	"..#######################.....",
	".#######################......",
	"######################........",
	"####################..........",
]
const LOGO_S := [
	"........######........",
	".....############.....",
	"....##############....",
	"...################...",
	"..#######....#######..",
	"..######......######..",
	".######........######.",
	".######........######.",
	".######.........#####.",
	".#######........####..",
	".########........###..",
	"..#########.......#...",
	"..############........",
	"...##############.....",
	"....###############...",
	"......###############.",
	".........############.",
	"............##########",
	"..#............#######",
	".###............######",
	".####...........######",
	"#####...........######",
	"######..........######",
	"######..........######",
	"######..........######",
	"######..........######",
	".######........######.",
	".#######......#######.",
	"..#######....#######..",
	"...################...",
	"....##############....",
	".....############.....",
	"........######........",
]
## The small OF, 19 tall.
const LOGO_SMALL_O := [
	".....######.....",
	"...##########...",
	"..####....####..",
	"..###......###..",
	".####......####.",
	".####......####.",
	"####........####",
	"####........####",
	"####........####",
	"####........####",
	"####........####",
	"####........####",
	"####........####",
	".####......####.",
	".####......####.",
	"..###......###..",
	"..####....####..",
	"...##########...",
	".....######.....",
]
const LOGO_SMALL_F := [
	"###############",
	"###############",
	".#####......###",
	"..####.......##",
	"..####........#",
	"..####.........",
	"..####.....#...",
	"..####....##...",
	"..##########...",
	"..##########...",
	"..####....##...",
	"..####.....#...",
	"..####.........",
	"..####.........",
	"..####.........",
	"..#####........",
	".#######.......",
	"#########......",
	"#########......",
]
const LOGO_CAPS := {"F": LOGO_F, "O": LOGO_O, "U": LOGO_U, "R": LOGO_R, "W": LOGO_W, "A": LOGO_A, "N": LOGO_N,
	"D": LOGO_D, "S": LOGO_S}

# ================================================================== LOGO ===
## FOUR OF WANDS as a lockup: FOUR with a small OF and four gems in the notch beside it, WANDS under them.
## The letters are the pixel maps above; the gold is worked out here: a dark outline, a short extrusion down to
## the right, and every stroke cut like an inscription, its upper and left faces catching the light.
## Where the logo's top left corner goes on the screen.
const LOGO_AT := Vector2i(24, 6)
const LOGO_CAP := 33
const LOGO_GAP := 5
const LOGO_PAD := 2
const LOGO_LINE1 := ["F", "O", "U", "R"]
const LOGO_LINE2 := ["W", "A", "N", "D", "S"]
## The space before each letter of a line, set by eye.
const LOGO_KERN1 := [0, 1, 2, 2]
const LOGO_KERN2 := [0, -4, -2, 2, 2]

const GOLD := [Color("fff6c0"), Color("ffe58a"), Color("ffd94d"), Color("ffb326"), Color("ff9a3c"), Color("c48a10"),
	Color("7a2f14")]
const GOLD_DEEP := Color("4a1a0c")
## Which gold each facet of a stroke takes (top, left, right, bottom), by how far down the letter it is: the
## upper third, the middle, the foot.
const GOLD_FACETS := [[0, 1, 3, 5], [1, 2, 3, 5], [2, 3, 5, 5]]

## The four gems of the logo, one per wizard, cut like the heads of their staffs.
const GEM_MAPS := [
	["..KKK..", ".KLLMK.", "KLWLMMK", "KLLMMDK", "KMMMDDK", ".KMDDK.", "..KKK.."],
	["...K...", "..KLK..", "..KLK..", ".KLLMK.", ".KLWMK.", "KLLMMDK", "KLMMMDK", ".KMDDK.", "..KKK.."],
	["...K...", "..KLK..", ".KLLMK.", ".KLWMK.", ".KLLMK.", ".KLMDK.", ".KMMDK.", "..KDK..", "...K..."],
	["...K...", "..KLK..", ".KLWMK.", "KLLMMDK", ".KMMDK.", "..KDK..", "...K..."],
]

static var _logo: ImageTexture
static var _logo_hot: ImageTexture
static var _logo_images: Array[Image] = []
static var _logo_letter_tex: Array = []
## The letters' boxes inside the logo, in reading order, for the intro to light them one by one.
static var _logo_letters: Array[Rect2i] = []
## The four gems' centres inside the logo.
static var _logo_gems: Array[Vector2] = []


static func logo() -> ImageTexture:
	if _logo == null:
		_bake_logo()
	return _logo


## The logo white-hot: what each letter is as it is struck in the intro, and the band of the shimmer.
static func logo_hot() -> ImageTexture:
	logo()
	return _logo_hot


## The logo as images, [plain, white-hot].
static func logo_images() -> Array[Image]:
	logo()
	return _logo_images


static func logo_letters() -> Array[Rect2i]:
	logo()
	return _logo_letters


## Letter `i` of the logo on its own, gold or white-hot. It is drawn at logo_letters()[i].position.
static func logo_letter(i: int, hot_one: bool) -> ImageTexture:
	logo()
	return _logo_letter_tex[i][1 if hot_one else 0]


static func logo_gems() -> Array[Vector2]:
	logo()
	return _logo_gems


static func _bake_logo() -> void:
	# Lay the letters out: [rows, x, y, depth of the extrusion].
	var parts: Array = []
	var x := 0
	for i: int in range(LOGO_LINE1.size()):
		var rows: Array = LOGO_CAPS[LOGO_LINE1[i]]
		x += LOGO_KERN1[i]
		parts.append([rows, x, 0, 3])
		x += (rows[0] as String).length()
	var notch := x + 6
	parts.append([LOGO_SMALL_O, notch, LOGO_CAP - LOGO_SMALL_O.size(), 2])
	var of_x: int = notch + (LOGO_SMALL_O[0] as String).length() + 2
	parts.append([LOGO_SMALL_F, of_x, LOGO_CAP - LOGO_SMALL_F.size(), 2])
	var w: int = of_x + (LOGO_SMALL_F[0] as String).length()
	x = 0
	for i: int in range(LOGO_LINE2.size()):
		var rows: Array = LOGO_CAPS[LOGO_LINE2[i]]
		x += LOGO_KERN2[i]
		parts.append([rows, x, LOGO_CAP + LOGO_GAP, 3])
		x += (rows[0] as String).length()
	w = maxi(w, x)
	var pad := LOGO_PAD
	var size := Vector2i(w + 3 + pad * 2, LOGO_CAP * 2 + LOGO_GAP + 3 + pad * 2)
	# The mask: alpha is the letter, red how far down its line a pixel is, green how deep its extrusion.
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	_logo_letters.clear()
	_logo_letter_tex.clear()
	for p: Array in parts:
		var rows: Array = p[0]
		var n := rows.size()
		var box := Rect2i(p[1], p[2], (rows[0] as String).length() + p[3] + pad * 2, n + p[3] + pad * 2)
		# Each letter is also kept on its own, for the intro to strike them one at a time.
		var alone := Image.create(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
		for ry: int in range(n):
			var row: String = rows[ry]
			for rx: int in range(row.length()):
				if row[rx] == "#":
					var c := Color(float(ry) / (n - 1), p[3] / 8.0, 0.0, 1.0)
					mask.set_pixel(pad + p[1] + rx, pad + p[2] + ry, c)
					alone.set_pixel(pad + rx, pad + ry, c)
		_logo_letters.append(box)
		var gold_one := _gold(alone)
		_logo_letter_tex.append([ImageTexture.create_from_image(gold_one),
			ImageTexture.create_from_image(_white_hot(gold_one))])
	var plain := _gold(mask)
	var hot := _white_hot(plain)
	# The gems, in a row over the small OF.
	_logo_gems.clear()
	for i: int in range(4):
		var rows: Array = GEM_MAPS[i]
		var gx := pad + notch - 1 + i * 9
		@warning_ignore("integer_division")
		var gy := pad + 6 - rows.size() / 2
		var pal := {"K": INK, "W": Color.WHITE, "L": WIZ[i][0], "M": WIZ[i][1], "D": WIZ[i][2]}
		for img: Image in [plain, hot]:
			_img = img
			_stamp(rows, gx, gy, pal)
		_logo_gems.append(Vector2(gx + 3.5, pad + 6.5))
	_logo_images = [plain, hot]
	_logo = ImageTexture.create_from_image(plain)
	_logo_hot = ImageTexture.create_from_image(hot)


static func _mask_on(m: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= m.get_width() or y >= m.get_height():
		return false
	return m.get_pixel(x, y).a > 0.5


## How many letter pixels lie beyond (x, y) in a direction before the edge, up to 8.
static func _mask_run(m: Image, x: int, y: int, dx: int, dy: int) -> int:
	var n := 0
	while n < 8 and _mask_on(m, x + dx * (n + 1), y + dy * (n + 1)):
		n += 1
	return n


## A gold image as it is white-hot: the lit facets white, the shaded ones pale, the sides glowing.
static func _white_hot(src: Image) -> Image:
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in range(src.get_height()):
		for x: int in range(src.get_width()):
			var c := src.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if c == INK:
				out.set_pixel(x, y, INK)
			elif c == GOLD[6] or c == GOLD_DEEP:
				out.set_pixel(x, y, GOLD[2])
			elif c == GOLD[0] or c == GOLD[1] or c == GOLD[2]:
				out.set_pixel(x, y, Color.WHITE)
			else:
				out.set_pixel(x, y, GOLD[0])
	return out


## Renders the mask as gold into a new image.
static func _gold(mask: Image) -> Image:
	var w := mask.get_width()
	var h := mask.get_height()
	_begin(w, h)
	# The extrusion: each letter pushed down to the right, its last step the darkest.
	for y: int in range(h):
		for x: int in range(w):
			if not _mask_on(mask, x, y):
				continue
			var depth := int(roundf(mask.get_pixel(x, y).g * 8.0))
			for d: int in range(1, depth + 1):
				if not _mask_on(mask, x + d, y + d) and _at(x + d, y + d) != GOLD[6]:
					_img.set_pixel(x + d, y + d, GOLD[6] if d < depth else GOLD_DEEP)
	# The face, cut like an inscription: which edge a pixel is nearest decides the facet it lies on
	# (0 top, 1 left, 2 right, 3 bottom).
	var facets := PackedByteArray()
	facets.resize(w * h)
	facets.fill(255)
	for y: int in range(h):
		for x: int in range(w):
			if not _mask_on(mask, x, y):
				continue
			var l := _mask_run(mask, x, y, -1, 0)
			var r := _mask_run(mask, x, y, 1, 0)
			var u := _mask_run(mask, x, y, 0, -1)
			var d := _mask_run(mask, x, y, 0, 1)
			if mini(l, r) <= mini(u, d):
				facets[y * w + x] = 1 if l <= r else 2
			else:
				facets[y * w + x] = 0 if u <= d else 3
	# Where strokes meet the nearest edge flips from pixel to pixel: a pixel most of whose neighbours lie on
	# another facet joins them, twice over, so the facets stay whole.
	for pass_no: int in range(2):
		var next := facets.duplicate()
		for y: int in range(1, h - 1):
			for x: int in range(1, w - 1):
				var mine := facets[y * w + x]
				if mine == 255:
					continue
				var count := [0, 0, 0, 0]
				for oy: int in range(-1, 2):
					for ox: int in range(-1, 2):
						var f := facets[(y + oy) * w + x + ox]
						if f != 255 and (ox != 0 or oy != 0):
							count[f] += 1
				for f: int in range(4):
					if f != mine and count[f] >= 5 and count[f] > count[mine] + 2:
						next[y * w + x] = f
		facets = next
	for y: int in range(h):
		for x: int in range(w):
			var facet := facets[y * w + x]
			if facet == 255:
				continue
			var v := mask.get_pixel(x, y).r
			var band := 0 if v < 0.36 else (1 if v < 0.76 else 2)
			_img.set_pixel(x, y, GOLD[GOLD_FACETS[band][facet]])
	# The outline: every clear pixel that touches a painted one, corners too.
	var edge: Array[Vector2i] = []
	for y: int in range(h):
		for x: int in range(w):
			if _img.get_pixel(x, y).a > 0.0:
				continue
			var touch := false
			for oy: int in range(-1, 2):
				for ox: int in range(-1, 2):
					if _at(x + ox, y + oy).a > 0.0:
						touch = true
			if touch:
				edge.append(Vector2i(x, y))
	for p: Vector2i in edge:
		_img.set_pixel(p.x, p.y, INK)
	return _img



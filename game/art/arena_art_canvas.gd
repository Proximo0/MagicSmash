class_name ArenaArtCanvas
extends RefCounted
## The picture an arena backdrop is painted on. It is index-painted, the way pixel art is made by hand: every pixel
## holds a palette entry (a material and a shade), and a separate light map says how much candle light reaches it.
## `compose` turns the two into colours through one lookup table, so the light falls in dithered steps, a stone in
## the dark and the same stone by a candle are two entries of one ramp, and the whole room keeps to a small
## palette. Painting is a few byte writes per pixel, which keeps a bake of 800x450 well under half a second.

## Light steps between the darkest corner and the foot of a candle, unless `light_ramp` is asked for more.
const LEVELS := 16
## The light level of open floor far from every candle (0..255 in the light map).
const AMBIENT := 68
const _BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

var w := 0
var h := 0
## One palette index per pixel.
var px := PackedByteArray()
## RGBA8; the red channel is the light that reaches a pixel. Lights are stamped in with `Image.blend_rect`.
var light: Image
var _albedo: Array[Color] = []
var _glow: Array[Color] = []
## For each palette entry, the first and last entry of the ramp it belongs to (`shade` stays inside it).
var _lo := PackedByteArray()
var _hi := PackedByteArray()


func _init(width: int, height: int) -> void:
	w = width
	h = height
	px.resize(w * h)
	light = Image.create(w, h, false, Image.FORMAT_RGBA8)
	light.fill(Color8(AMBIENT, AMBIENT, AMBIENT))
	_lo.resize(256)
	_hi.resize(256)


# =============================================================== PALETTE ===
## One more palette entry. `glow` is added after the light, so a flame or a lit rune keeps its colour in the dark.
func color(c: Color, glow: Color = Color(0, 0, 0)) -> int:
	var i := _albedo.size()
	assert(i < 256, "the arena palette holds 256 entries")
	_albedo.append(c)
	_glow.append(glow)
	_lo[i] = i
	_hi[i] = i
	return i


## A colour that ignores the light map.
func emissive(c: Color) -> int:
	return color(Color(0, 0, 0), c)


## `n` entries from the first key colour to the last, dark to light. Returns the first index; `shade` moves a
## pixel up and down inside the ramp. A `glowing` ramp ignores the light map.
func ramp(keys: Array, n: int, glowing: bool = false) -> int:
	var first := _albedo.size()
	for k in n:
		var t := float(k) / float(maxi(1, n - 1)) * float(keys.size() - 1)
		var a := mini(int(t), keys.size() - 2)
		var c := Color(keys[a]).lerp(Color(keys[a + 1]), t - a) if keys.size() > 1 else Color(keys[0])
		if glowing:
			emissive(c)
		else:
			color(c)
	for k in n:
		_lo[first + k] = first
		_hi[first + k] = first + n - 1
	return first


func palette_size() -> int:
	return _albedo.size()


func ramp_first(i: int) -> int:
	return _lo[i]


func ramp_last(i: int) -> int:
	return _hi[i]


# ================================================================ PIXELS ===
func put(x: int, y: int, i: int) -> void:
	if x >= 0 and y >= 0 and x < w and y < h:
		px[y * w + x] = i


func at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return 0
	return px[y * w + x]


## Moves a pixel `d` steps along its own ramp (negative: darker), whatever material it is.
func shade(x: int, y: int, d: int) -> void:
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	var k := y * w + x
	var i := px[k]
	px[k] = clampi(i + d, _lo[i], _hi[i])


func rect(x: int, y: int, rw: int, rh: int, i: int) -> void:
	var x0 := maxi(x, 0)
	var x1 := mini(x + rw, w)
	for yy in range(maxi(y, 0), mini(y + rh, h)):
		var k := yy * w + x0
		for xx in range(x0, x1):
			px[k] = i
			k += 1


func shade_rect(x: int, y: int, rw: int, rh: int, d: int) -> void:
	var x0 := maxi(x, 0)
	var x1 := mini(x + rw, w)
	for yy in range(maxi(y, 0), mini(y + rh, h)):
		var k := yy * w + x0
		for xx in range(x0, x1):
			var i := px[k]
			px[k] = clampi(i + d, _lo[i], _hi[i])
			k += 1


func hline(x: int, y: int, n: int, i: int) -> void:
	rect(x, y, n, 1, i)


func vline(x: int, y: int, n: int, i: int) -> void:
	rect(x, y, 1, n, i)


## A 1 px line. `i` < 0 shades by `i` steps instead of painting.
func line(a: Vector2, b: Vector2, i: int) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for k in n + 1:
		var p := a.lerp(b, float(k) / maxf(1.0, n))
		if i < 0:
			shade(roundi(p.x), roundi(p.y), i)
		else:
			put(roundi(p.x), roundi(p.y), i)


## An ASCII map: one character per pixel, `map` gives each character its palette index (others stay clear).
## An index below zero shades what is there by that many steps.
func stamp(rows: Array, x0: int, y0: int, map: Dictionary, flip: bool = false) -> void:
	for y: int in rows.size():
		var row: String = rows[y]
		var n := row.length()
		for x: int in n:
			var ch := row[n - 1 - x] if flip else row[x]
			if not map.has(ch):
				continue
			var i: int = map[ch]
			if i < 0:
				shade(x0 + x, y0 + y, i)
			else:
				put(x0 + x, y0 + y, i)


static func rows_width(rows: Array) -> int:
	var m := 0
	for r: String in rows:
		m = maxi(m, r.length())
	return m


# ================================================================= LIGHT ===
## A soft elliptical pool as a sprite of one colour whose alpha falls from `peak` at the middle to nothing at the
## rim. `power` shapes the fall (1.5 wide and even, 3 a tight core with a long faint skirt). White pools are
## stamped on the light map with `light_add`, black ones darken it, coloured ones glaze the finished picture.
## With `steps` the alpha falls in that many dithered bands instead of smoothly.
static func pool(rx: int, ry: int, peak: float, power: float = 2.0, tint: Color = Color.WHITE, steps: int = 0) -> Image:
	var sw := rx * 2
	var sh := ry * 2
	var data := PackedByteArray()
	data.resize(sw * sh * 4)
	var tr := int(tint.r * 255.0)
	var tg := int(tint.g * 255.0)
	var tb := int(tint.b * 255.0)
	# Greys with a smooth fall (every light and shadow) only need their alpha bytes written.
	var grey := steps == 0 and tr == tg and tg == tb
	if grey:
		data.fill(tr)
	var inv_x := 1.0 / float(rx)
	var inv_y := 1.0 / float(ry)
	for y in ry:
		var dy := (float(y) + 0.5) * inv_y
		var dy2 := dy * dy
		var top := (ry - 1 - y) * sw
		var bot := (ry + y) * sw
		for x in rx:
			var dx := (float(x) + 0.5) * inv_x
			var d2 := dx * dx + dy2
			if d2 >= 1.0:
				if grey:
					var l0 := rx - 1 - x
					var r0 := rx + x
					data[((top + l0) << 2) | 3] = 0
					data[((top + r0) << 2) | 3] = 0
					data[((bot + l0) << 2) | 3] = 0
					data[((bot + r0) << 2) | 3] = 0
				continue
			var a := peak * pow(1.0 - sqrt(d2), power)
			if grey:
				var av := int(255.0 * a)
				var l := rx - 1 - x
				var r := rx + x
				data[((top + l) << 2) | 3] = av
				data[((top + r) << 2) | 3] = av
				data[((bot + l) << 2) | 3] = av
				data[((bot + r) << 2) | 3] = av
				continue
			for q in 4:
				var qx := rx + x if q & 1 == 0 else rx - 1 - x
				var qy := ry + y if q & 2 == 0 else ry - 1 - y
				var v := a
				if steps > 0:
					v = peak * floorf(a / peak * steps + (_BAYER[((qy & 3) << 2) | (qx & 3)] + 0.5) / 16.0) / steps
				var k := (qy * sw + qx) << 2
				data[k] = tr
				data[k + 1] = tg
				data[k + 2] = tb
				data[k + 3] = int(255.0 * v)
	return Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, data)


## Blends `sprite` into `target` centred on (cx, cy), only inside `clip`.
static func glaze(target: Image, sprite: Image, cx: int, cy: int, clip: Rect2i) -> void:
	var dst := Rect2i(cx - sprite.get_width() / 2, cy - sprite.get_height() / 2, sprite.get_width(), sprite.get_height())
	var vis := dst.intersection(clip)
	if vis.size.x <= 0 or vis.size.y <= 0:
		return
	target.blend_rect(sprite, Rect2i(vis.position - dst.position, vis.size), vis.position)


## Stamps a `pool` sprite centred on (cx, cy), only inside `clip`: a candle on a wall lights the floor below it
## and the wall face around it with two different pools.
func light_add(sprite: Image, cx: int, cy: int, clip: Rect2i = Rect2i(0, 0, 0, 0)) -> void:
	glaze(light, sprite, cx, cy, Rect2i(0, 0, w, h) if clip.size == Vector2i.ZERO else clip)


## Darkens the light map in `r` towards one edge: `from` and `to` are the shadow's strength (0..1) at the
## rectangle's first and last row (or column when `across`). Ambient occlusion where floors meet walls.
## With `lighten` it brightens instead: the wash of light a row of candles throws across the room.
func light_shade(r: Rect2i, from: float, to: float, across: bool = false, lighten: bool = false) -> void:
	var n := r.size.x if across else r.size.y
	if n <= 0:
		return
	var v := 1.0 if lighten else 0.0
	var strip := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	for k in n:
		var a := lerpf(from, to, float(k) / float(maxi(1, n - 1)))
		if across:
			strip.fill_rect(Rect2i(k, 0, 1, r.size.y), Color(v, v, v, a))
		else:
			strip.fill_rect(Rect2i(0, k, r.size.x, 1), Color(v, v, v, a))
	light.blend_rect(strip, Rect2i(Vector2i.ZERO, r.size), r.position)


## Sets the light in a rectangle (for parts that keep their own level: a door's black inside).
func light_set(r: Rect2i, v: int) -> void:
	light.fill_rect(r, Color8(v, v, v))


# =============================================================== COMPOSE ===
## The finished picture. `mults` has one RGB multiplier per light level (see `light_ramp`): cool and dim at the
## bottom, warm and bright at the top. Between two levels the picture is dithered with the three patterns of a
## 2x2 ordered dither (one pixel in four, a checker, three in four); `dither` is how much of each band they
## take up (0 hard bands, 1 no flat band at all).
func compose(mults: Array[Color], dither: float = 1.0) -> Image:
	var levels := mults.size()
	var lut := PackedInt32Array()
	lut.resize(levels * 256)
	var n_pal := _albedo.size()
	for l in levels:
		var m: Color = mults[l]
		for k in n_pal:
			var a: Color = _albedo[k]
			var g: Color = _glow[k]
			var r := clampi(roundi((_shoulder(a.r * m.r) + g.r) * 255.0), 0, 255)
			var gg := clampi(roundi((_shoulder(a.g * m.g) + g.g) * 255.0), 0, 255)
			var b := clampi(roundi((_shoulder(a.b * m.b) + g.b) * 255.0), 0, 255)
			lut[(l << 8) | k] = r | (gg << 8) | (b << 16) | (255 << 24)
	# Thresholds in sixteenths of a level for the four pixels of the 2x2 cell.
	var bay := PackedInt32Array()
	bay.resize(4)
	for k in 4:
		bay[k] = clampi(roundi(8.0 + ([2, 10, 14, 6][k] - 8.0) * dither), 0, 15)
	var lb := light.get_data()
	var out := PackedInt32Array()
	out.resize(w * h)
	var scale := (levels - 1) * 16 + 1
	var i := 0
	for y in h:
		var by := (y & 1) << 1
		for x in w:
			out[i] = lut[(((((lb[i << 2] * scale) >> 8) + bay[by | (x & 1)]) >> 4) << 8) | px[i]]
			i += 1
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out.to_byte_array())


## Bright things by a candle (bone, wax) roll off towards white instead of clipping.
static func _shoulder(v: float) -> float:
	const KNEE := 0.42
	if v <= KNEE:
		return v
	return KNEE + (1.0 - KNEE) * (1.0 - exp(-(v - KNEE) / (1.0 - KNEE)))


## `levels` light multipliers for `compose` from a few key stops: [[light, Color], ...] with rising light values
## on a scale of 0 (black) to 15 (the foot of a candle). Light 4 is open floor far from every candle (AMBIENT).
static func light_ramp(stops: Array, levels: int = LEVELS) -> Array[Color]:
	var out: Array[Color] = []
	for l in levels:
		var v := l * 15.0 / float(levels - 1)
		var c: Color = stops[0][1]
		for k in stops.size() - 1:
			var l0: float = stops[k][0]
			var l1: float = stops[k + 1][0]
			if v >= l0:
				c = (stops[k][1] as Color).lerp(stops[k + 1][1], clampf((v - l0) / maxf(0.001, l1 - l0), 0.0, 1.0))
		out.append(c)
	return out

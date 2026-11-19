class_name SanctumArt
extends RefCounted
## The Sanctum's art. Bakes the static tower room once into one texture: the wall top and cornice, ashlar masonry,
## a wainscot, arched moonlit windows and a stained-glass rose, carved bookcases, banners, sconces, the plank floor,
## the rug, the stone ring under the portal, the altar, reliquary, music box, wishing well and corner clutter, then
## lights it by candle and moon with a dithered light map. The opened alcove is a second small patch drawn over the
## cracked wall. Small live sprites (pots, the floating card, the cat's eyes) are ASCII maps like Sprites uses.
## `flames()` lists every baked wick so the view can flicker a flame on it and light it.

const W := 480
const H := 270
## The part of the top wall the opened alcove replaces.
const PATCH := Rect2i(384, 0, 56, 66)

## Shared palette for every ASCII map here.
const PAL := {
	"K": Color("1a0f24"),
	"1": Color("221a35"), "2": Color("3a3150"), "3": Color("54496f"), "4": Color("74689a"), "5": Color("9a8fc0"),
	"a": Color("24120c"), "b": Color("4a2a1c"), "c": Color("6b3f24"), "d": Color("8f5a32"), "e": Color("b07a48"),
	"y": Color("8a5a10"), "Y": Color("d8a62a"), "L": Color("ffe27a"), "Z": Color("fff6c0"),
	"p": Color("2c0d4d"), "P": Color("5a1a8a"), "Q": Color("8a3ac0"), "q": Color("c070f0"), "m": Color("ff4df2"),
	"u": Color("5a2a18"), "U": Color("8a4428"), "O": Color("b8643a"), "o": Color("e0905a"),
	"w": Color("a8987a"), "W": Color("efe2c8"),
	"k": Color("0b1030"), "B": Color("1f4a7a"), "C": Color("8bdcff"),
	"r": Color("6a1020"), "R": Color("b02a3a"),
	"g": Color("1f6a3a"), "G": Color("4fd06a"), "h": Color("b8ff9a"),
	"n": Color("2a2238"), "N": Color("3a3048"), "v": Color("7a6ca0"),
	"x": Color("1c1820"), "X": Color("4a4450"), "V": Color("8a8496"),
	"t": Color("efe4c8"), "T": Color("bfae8c"),
}

const ALTAR := [
	"..tT................tT..",
	"..tT................tT..",
	"..TT................TT..",
	".KKKKKKKKKKKKKKKKKKKKKK.",
	"K5444444444444444444443K",
	"K4333333333333333333332K",
	"K2222222222222222222221K",
	".KKKKKKKKKKKKKKKKKKKKKK.",
	"....K43333333333332K....",
	"....K43111111111132K....",
	"....K43122222222132K....",
	"....K4312222Y222132K....",
	"....K431222YLY22132K....",
	"....K43122YLZLY2132K....",
	"....K431222YLY22132K....",
	"....K4312222Y222132K....",
	"....K43122222222132K....",
	"....K43133333333132K....",
	"....K43333333333332K....",
	"..KKKKKKKKKKKKKKKKKKKK..",
	".K44444444444444444443K.",
	"K5443333333333333333322K",
	"K2222222222222222222221K",
	"KKKKKKKKKKKKKKKKKKKKKKKK",
]

const CHEST := [
	"....KKKKKKKKKKKKKK....",
	"..KKYqqqqqqqqqqqqYKK..",
	".KYLQqqQQQQQQQQQQQLYK.",
	".KYQQQQQQYLLYQQQQQQYK.",
	".KYPPPPPPYLLYPPPPPPYK.",
	".KyYYYYYYYYYYYYYYYYyK.",
	".KKKKKKKKKKKKKKKKKKKK.",
	".KYPPPPPPYKKYPPPPPPYK.",
	".KYPQQPPYKLLKYPQQPPYK.",
	".KYPPPPPYKmmKYPPPPPYK.",
	".KYPPPPPYKLLKYPPPPPYK.",
	".KYpPPPPPYKKYPPPPPpYK.",
	".KYppPPPPYYYYPPPPppYK.",
	".KYppppPPPPPPPPppppYK.",
	".KyYYYYYYYYYYYYYYYYyK.",
	".KKKKKKKKKKKKKKKKKKKK.",
	"..KyyK..........KyyK..",
	"..KKKK..........KKKK..",
]

const MUSIC_BOX := [
	"..KKKKKKKKKKKKKKKKKKKK..",
	"..KedddddKKKKKKdddddcK..",
	"..KeddddKxXVVXxKddddcK..",
	"..KedddKxxxRRxxxKdddcK..",
	"..KeddddKxxxxxxKddddcK..",
	"..KedddddKKKKKKdddddcK..",
	"..KYYYYYYYYYYYYYYYYYYK..",
	"..KcccccccccccccccccbK..",
	"..KcbbbbbbbbbbbbbbbbaK..",
	"..KcbYyyyyyyyyyyyyYbaKY.",
	"..KcbybbbbbYLYbbbbybaKYL",
	"..KcbybbbbbbYbbbbbybaK.L",
	"..KcbYyyyyyyyyyyyyYbaK..",
	"..KcbbbbbbbbbbbbbbbbaK..",
	"..KyYYYYYYYYYYYYYYYYyK..",
	"..KKKKKKKKKKKKKKKKKKKK..",
	"...Kb..............bK...",
	"...KK..............KK...",
]

const CANDELABRA := [
	".t...t...t.",
	".t...t...t.",
	".T...T...T.",
	"xXx.xXx.xXx",
	".x...x...x.",
	".xxxxXxxxx.",
	".....X.....",
	".....V.....",
	"....xXx....",
	".....X.....",
	".....X.....",
	".....V.....",
	".....X.....",
	".....X.....",
	"....xXx....",
	"...xXVXx...",
	"..xx.x.xx..",
	".xx.....xx.",
]

const SCONCE := [
	"..tT..",
	"..tT..",
	"..TT..",
	".xXXx.",
	"..xx..",
	"..XV..",
	".xXVx.",
	".xXXx.",
	"..xx..",
]

const CAULDRON := [
	"......KKKKKKKKKK......",
	"...KKKXVVVVVVVVXKKK...",
	"..KxXGGhGGGGGGGGGGXxK.",
	".KxXGGGGGhGGGGhGGGGXxK",
	".KxXgGGGGGGGGGGGGGgXxK",
	"..KXXXXXXXXXXXXXXXXXK.",
	".KxXVVXXXXXXXXXXXXXxxK",
	"KxXVXXXXXXXXXXXXXXXxxK",
	"KxXVXXXXXXXXXXXXXXXxxK",
	"KxXXXXXXXXXXXXXXXXxxxK",
	".KxXXXXXXXXXXXXXXxxxK.",
	"..KxxxxxxxxxxxxxxxxK..",
	"...KxK..........KxK...",
	"...KKK..........KKK...",
]

const SKULL := [
	".WWW.",
	"WWWWw",
	"WKWKw",
	"WWWWw",
	".WwW.",
]

const POTION_SHELF := [
	".c.",
	".w.",
	"KGK",
	"GhG",
	"GGg",
	"KKK",
]

const CAT := [
	"...........K...K..",
	"..........KvK.KvK.",
	"....KKKK..KnQKQnvK",
	"..KKvvvvKKnnnnnnnK",
	".KvvnnnnvvnnnnnnnK",
	".KvnnnnnnnnnnnnnnK",
	"KvnnnnnnnnnnnnnnK.",
	"KvnnnnnnnnnnnnnnK.",
	"KnnvvvvvvvvnnnnK..",
	".KKKKKKKKKKKKKK...",
]

const URN_A := [
	"...KKK...",
	"..KoOUK..",
	"...KOK...",
	"..KOOUK..",
	".KoOOOUK.",
	"KoOOOOUuK",
	"KOuuuuuuK",
	"KOOOOOUuK",
	".KOOOUuK.",
	"..KUUuK..",
	"...KKK...",
]

const URN_B := [
	"...KKKK...",
	"..KoOOUK..",
	"..KKKKKK..",
	".KoOOOOUK.",
	"KoOOOOOUuK",
	"KOyOyOyUuK",
	"KOOOOOOUuK",
	".KOOOOUuK.",
	"..KKKKKK..",
]

const URN_C := [
	"..KKKKK..",
	".KoOOOUK.",
	"..KOOUK..",
	".KoOOOUK.",
	"KoOOOOOUK",
	"KOOOOOUuK",
	"KOyyyyyuK",
	".KOOOUuK.",
	"..KKKKK..",
]

const URN_BROKEN := [
	"...KK......",
	"..KOuK..KK.",
	".KOOUK.KOuK",
	"KOuUUK.KUK.",
	".KKKK...K..",
]

const FLOAT_CARD := [
	"KKKKKKKKKK",
	"KLYYYYYYyK",
	"KYPPPPPPyK",
	"KYPPmmPPyK",
	"KYPmqqmPyK",
	"KYPmqZmPyK",
	"KYPmqqmPyK",
	"KYPPmmPPyK",
	"KYPPPPPPyK",
	"KYPYPPYPyK",
	"KYPPYYPPyK",
	"KYPPPPPPyK",
	"KyyyyyyyyK",
	"KKKKKKKKKK",
]

const BOOK_COLS := ["7a1e2e", "1e4a7a", "2a5a2e", "6a4a1e", "4a1e6a", "8a6a2a", "2e2a3e", "7a3418", "1e5a5a", "5a1a3a"]

const BOOKCASES := [Rect2i(34, 8, 54, 52), Rect2i(116, 8, 54, 52), Rect2i(300, 8, 54, 52)]
## Props on the shelves: [bookcase, shelf, x from the left of the shelf, kind].
const SHELF_PROPS := [
	[0, 0, 30, "skull"], [0, 2, 8, "potion"], [0, 1, 40, "candle"],
	[1, 1, 18, "candle"], [1, 2, 30, "scroll"], [1, 0, 6, "potion"],
	[2, 0, 12, "potion"], [2, 1, 30, "skull"], [2, 2, 22, "candle"],
]
const WINDOWS := [Vector2i(198, 13), Vector2i(262, 13)]
const MOON := Vector2i(273, 20)
const ROSE := Vector2i(240, 27)
const SCONCES := [Vector2i(185, 26), Vector2i(290, 26), Vector2i(441, 26)]
const CANDLE_CLUSTERS := [Vector2i(9, 92), Vector2i(9, 192), Vector2i(461, 92), Vector2i(461, 192)]
const CANDELABRAS := [Vector2i(206, 80), Vector2i(274, 80)]

static var _room: ImageTexture
static var _alcove: ImageTexture
static var _spr := {}
static var _flames: Array[Vector2] = []
static var _img: Image
static var _emit := PackedByteArray()
static var _warm := PackedFloat32Array()
static var _cool := PackedFloat32Array()
static var _rng := RandomNumberGenerator.new()


## The baked room (the alcove wall still cracked).
static func room() -> ImageTexture:
	if _room == null:
		_bake()
	return _room


## The opened alcove, to draw at PATCH.position over the room.
static func alcove() -> ImageTexture:
	if _alcove == null:
		_bake()
	return _alcove


## Every candle wick in the room: the pixel just above it, where a flame goes.
static func flames() -> Array[Vector2]:
	if _room == null:
		_bake()
	return _flames


## A small live sprite drawn centred on its feet point (bottom-centre).
static func draw(ci: CanvasItem, key: String, feet: Vector2, modulate: Color = Color.WHITE) -> void:
	var tex := _sprite(key)
	if tex == null:
		return
	var p := (feet - Vector2(tex.get_width() / 2.0, tex.get_height())).round()
	ci.draw_texture(tex, p, modulate)


static func _sprite(key: String) -> ImageTexture:
	if _spr.is_empty():
		var maps := {"urn_a": URN_A, "urn_b": URN_B, "urn_c": URN_C, "urn_broken": URN_BROKEN, "card": FLOAT_CARD}
		for k: String in maps:
			var rows: Array = maps[k]
			var img := Image.create(_row_w(rows), rows.size(), false, Image.FORMAT_RGBA8)
			for y: int in range(rows.size()):
				var row: String = rows[y]
				for x: int in range(row.length()):
					if PAL.has(row[x]):
						img.set_pixel(x, y, PAL[row[x]])
			_spr[k] = ImageTexture.create_from_image(img)
	return _spr.get(key)


static func _row_w(rows: Array) -> int:
	var w := 0
	for r: String in rows:
		w = maxi(w, r.length())
	return w


# ============================================================== BAKING ===
static func _bake() -> void:
	_rng.seed = 7177
	_flames.clear()
	_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	_img.fill(Color("0b0716"))
	_emit = PackedByteArray()
	_emit.resize(W * H)
	_warm = PackedFloat32Array()
	_warm.resize(W * H)
	_cool = PackedFloat32Array()
	_cool.resize(W * H)
	_floor()
	_rug(Rect2i(166, 128, 148, 94))
	_runner(Rect2i(228, 98, 25, 31))
	_portal_ring(Vector2i(240, 82))
	_top_wall()
	for i: int in range(BOOKCASES.size()):
		_bookcase(i, BOOKCASES[i])
	_side_walls()
	_shadows()
	_floor_clutter()
	_dais(Vector2i(84, 125), 19, 7)
	_altar(Vector2i(84, 125))
	_round_rug(Vector2i(396, 124), 22, 9)
	_stamp(CHEST, 385, 107)
	_gramophone(Vector2i(70, 229))
	_flagstones(Vector2i(410, 228), 26, 13)
	_well(Vector2i(410, 216))
	_stamp(CAULDRON, 229, 234)
	for c: Vector2i in CANDELABRAS:
		_stamp(CANDELABRA, c.x - 5, c.y - 17)
		for k: int in [1, 5, 9]:
			_flame_at(c.x - 5 + k, c.y - 18)
	for c: Vector2i in CANDLE_CLUSTERS:
		_candle_cluster(c)
	_lights()
	var base := _img.get_region(PATCH)
	_crack()
	_apply_light(Rect2i(0, 0, W, H))
	_room = ImageTexture.create_from_image(_img)
	# The opened alcove: the unlit patch again, the niche drawn into it, lit the same way.
	_img.blit_rect(base, Rect2i(Vector2i.ZERO, PATCH.size), PATCH.position)
	_open_alcove()
	_apply_light(PATCH)
	_alcove = ImageTexture.create_from_image(_img.get_region(PATCH))
	_img = null


# ---------------------------------------------------------------- pixels ---
static func _hash(x: int, y: int, s: int) -> int:
	var h := (x * 374761393 + y * 668265263 + s * 982451653) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)


static func _px(x: int, y: int, c: Color, emissive: bool = false) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	if c.a < 1.0:
		c = _img.get_pixel(x, y).lerp(Color(c, 1.0), c.a)
	_img.set_pixel(x, y, c)
	_emit[y * W + x] = 1 if emissive else 0


static func _rect(x: int, y: int, w: int, h: int, c: Color, emissive: bool = false) -> void:
	for yy: int in range(y, y + h):
		for xx: int in range(x, x + w):
			_px(xx, yy, c, emissive)


static func _pixel(x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= W or y >= H:
		return Color.BLACK
	return _img.get_pixel(x, y)


static func _darken(x: int, y: int, k: float) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	_img.set_pixel(x, y, _img.get_pixel(x, y).darkened(k))


static func _stamp(rows: Array, x0: int, y0: int, emissive_keys: String = "") -> void:
	for y: int in range(rows.size()):
		var row: String = rows[y]
		for x: int in range(row.length()):
			var ch := row[x]
			if PAL.has(ch):
				_px(x0 + x, y0 + y, PAL[ch], emissive_keys.contains(ch))


static func _flame_at(x: int, y: int) -> void:
	_flames.append(Vector2(x, y))


## A stone with a bevel: lit top and left edge, shadowed bottom and right, a few speckles and now and then a chip.
static func _stone(x: int, y: int, w: int, h: int, base: Color, seed_value: int) -> void:
	for yy: int in range(h):
		for xx: int in range(w):
			var c := base
			var n := _hash(x + xx, y + yy, seed_value) % 23
			if n == 0:
				c = c.lightened(0.1)
			elif n == 1 or n == 2:
				c = c.darkened(0.12)
			if yy == 0:
				c = base.lightened(0.22)
			elif xx == 0:
				c = base.lightened(0.12)
			elif yy == h - 1:
				c = base.darkened(0.32)
			elif xx == w - 1:
				c = base.darkened(0.22)
			_px(x + xx, y + yy, c)
	# A chip or a hairline crack on some stones.
	var r := _hash(x, y, seed_value + 5) % 9
	if r == 0 and w > 6 and h > 4:
		var cx := x + 2 + _hash(x, y, 9) % (w - 4)
		for k: int in range(mini(h - 2, 4)):
			_px(cx + (k % 2), y + 1 + k, base.darkened(0.45))
	elif r == 1 and w > 5:
		_px(x + w - 2, y + 1, base.darkened(0.5))
		_px(x + w - 3, y + 1, base.darkened(0.3))
		_px(x + w - 2, y + 2, base.darkened(0.3))


# ----------------------------------------------------------------- floor ---
static func _floor() -> void:
	var tones := [Color("4a3034"), Color("553838"), Color("5e4040"), Color("462c30"), Color("503438")]
	var row := 0
	for y: int in range(60, 250, 8):
		var x := 26 - (row * 23) % 41
		var k := row * 7
		while x < 454:
			var len := 30 + (_hash(k, row, 3) % 34)
			var base: Color = tones[_hash(k, row, 11) % tones.size()]
			for yy: int in range(7):
				for xx: int in range(len - 1):
					var px := x + xx
					if px < 26 or px >= 454 or y + yy >= 250:
						continue
					var c := base
					# Grain: long thin streaks that wander a row now and then.
					var g := _hash(int((px + k * 13) / 9.0), yy, k) % 7
					if g == 0:
						c = base.darkened(0.16)
					elif g == 1 and yy > 0:
						c = base.lightened(0.07)
					if yy == 0:
						c = base.lightened(0.1)
					elif yy == 6:
						c = base.darkened(0.2)
					_px(px, y + yy, c)
			# A knot on some planks, nail heads at both ends.
			if _hash(k, row, 17) % 4 == 0 and len > 20:
				var kx := x + 6 + _hash(k, row, 19) % (len - 14)
				for d: Vector2i in [Vector2i(0, 3), Vector2i(1, 3), Vector2i(-1, 3), Vector2i(0, 2), Vector2i(0, 4)]:
					if kx + d.x >= 26 and kx + d.x < 454:
						_px(kx + d.x, y + d.y, base.darkened(0.3 if d.x == 0 and d.y == 3 else 0.18))
			for nx: int in [x + 2, x + len - 4]:
				if nx >= 26 and nx < 453 and y + 5 < 250:
					_px(nx, y + 2, Color("6a5a5a"))
					_px(nx, y + 5, Color("6a5a5a"))
			# The joint to the next plank.
			if x + len - 1 >= 26 and x + len - 1 < 454:
				for yy: int in range(7):
					if y + yy < 250:
						_px(x + len - 1, y + yy, Color("1c1220"))
			x += len
			k += 1
		for xx: int in range(26, 454):
			if y + 7 < 250:
				_px(xx, y + 7, Color("1a1020"))
		row += 1


## A woven rug: an outlined border of gold diamonds, a lattice field, a medallion with a pentagram, fringes.
static func _rug(r: Rect2i) -> void:
	var dark := Color("2a0818")
	var red := Color("6e1a2c")
	var red_d := Color("50121f")
	var field := Color("3e1230")
	var field_l := Color("4c1a3a")
	var gold := Color("c8962a")
	var gold_d := Color("8a5a18")
	var c := Vector2(r.position) + Vector2(r.size) / 2.0 - Vector2(0.5, 0.5)
	for v: int in range(r.size.y):
		for u: int in range(r.size.x):
			var d := mini(mini(u, v), mini(r.size.x - 1 - u, r.size.y - 1 - v))
			var along := u if (v < 12 or r.size.y - 1 - v < 12) else v
			var col: Color
			if d == 0:
				col = dark
			elif d <= 2:
				col = red_d
			elif d == 3 or d == 11:
				col = gold
			elif d <= 10:
				var m := absi(along % 10 - 5) + absi(d - 7)
				if m <= 1:
					col = Color("e8b840")
				elif m == 2:
					col = gold_d
				elif m == 3:
					col = dark
				else:
					col = red
			elif d == 12:
				col = dark
			else:
				col = field
				if (u + v) % 8 == 0 or (u - v + 800) % 8 == 0:
					col = field_l
				if (u + v) % 8 == 0 and (u - v + 800) % 8 == 0:
					col = gold_d
				# The medallion.
				var p := Vector2(r.position.x + u, r.position.y + v) - c
				var e := sqrt(p.x * p.x / (34.0 * 34.0) + p.y * p.y / (27.0 * 27.0))
				if e < 1.0:
					col = Color("2a0c2a") if e < 0.9 else gold
					if e >= 0.86 and e < 0.9:
						col = dark
					if e < 0.12:
						col = red
			if _hash(u, v, 41) % 9 == 0:
				col = col.darkened(0.08)
			_px(r.position.x + u, r.position.y + v, col)
	# The pentagram inside the medallion.
	var pts: Array[Vector2] = []
	for i: int in range(5):
		var a := -PI / 2.0 + i * TAU / 5.0
		pts.append(c + Vector2(cos(a) * 28.0, sin(a) * 22.0))
	for i: int in range(5):
		_line(pts[i], pts[(i + 2) % 5], Color("b88a2a"))
	for i: int in range(5):
		_rect(int(pts[i].x) - 1, int(pts[i].y) - 1, 3, 3, gold)
		_px(int(pts[i].x), int(pts[i].y), Color("ffe27a"))
	# Fringes on the short ends.
	for v: int in range(1, r.size.y - 1):
		if v % 2 == 0:
			for k: int in range(3):
				_px(r.position.x - 1 - k, r.position.y + v, Color("d8c8a0") if k < 2 else Color("a89878"))
				_px(r.end.x + k, r.position.y + v, Color("d8c8a0") if k < 2 else Color("a89878"))
	# Its shadow on the boards.
	for u: int in range(r.size.x):
		_darken(r.position.x + u, r.end.y, 0.35)


## A narrow runner from the portal down to the rug: purple, gold edges, a row of small diamonds.
static func _runner(r: Rect2i) -> void:
	for v: int in range(r.size.y):
		for u: int in range(r.size.x):
			var d := mini(u, r.size.x - 1 - u)
			var col := Color("341048")
			if d == 0:
				col = Color("1a0820")
			elif d == 2:
				col = Color("c8962a")
			elif d == 1 or d == 3:
				col = Color("24082e")
			else:
				var m := absi((v + 3) % 8 - 4) + absi(u - r.size.x / 2)
				if m <= 1:
					col = Color("e8b840")
				elif m == 2:
					col = Color("8a5a18")
				elif m == 3:
					col = Color("24082e")
			if _hash(u, v, 43) % 9 == 0:
				col = col.darkened(0.08)
			_px(r.position.x + u, r.position.y + v, col)


## A summoning circle chalked on the boards and half scuffed away: two rings, a triangle, rune ticks.
static func _chalk(c: Vector2, r: float) -> void:
	var col := Color(0.85, 0.82, 0.95, 0.28)
	for k: int in range(96):
		var a := k * TAU / 96.0
		if _hash(k, 1, 91) % 7 == 0:
			continue
		_px(int(round(c.x + cos(a) * r)), int(round(c.y + sin(a) * r * 0.75)), col)
		if k % 2 == 0:
			_px(int(round(c.x + cos(a) * (r - 3.0))), int(round(c.y + sin(a) * (r - 3.0) * 0.75)), col)
	var pts: Array[Vector2] = []
	for i: int in range(3):
		var a := -PI / 2.0 + i * TAU / 3.0
		pts.append(c + Vector2(cos(a) * (r - 3.0), sin(a) * (r - 3.0) * 0.75))
	for i: int in range(3):
		var n := int(pts[i].distance_to(pts[(i + 1) % 3]))
		for j: int in range(n):
			if _hash(i, j, 93) % 5 != 0:
				var q := pts[i].lerp(pts[(i + 1) % 3], float(j) / n)
				_px(int(round(q.x)), int(round(q.y)), col)
	for i: int in range(8):
		var a := i * TAU / 8.0 + 0.2
		var q := c + Vector2(cos(a) * (r - 1.5), sin(a) * (r - 1.5) * 0.75)
		_px(int(q.x), int(q.y), Color(0.9, 0.85, 1.0, 0.4))


static func _line(a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for i: int in range(n + 1):
		var p := a.lerp(b, float(i) / maxf(1.0, n))
		_px(int(round(p.x)), int(round(p.y)), c)


## A ring of carved floor stones under the portal, black slate inside so the portal's arcs read.
static func _portal_ring(c: Vector2i) -> void:
	for y: int in range(c.y - 26, c.y + 27):
		for x: int in range(c.x - 30, c.x + 31):
			if y < 60:
				continue
			var p := Vector2(x - c.x, (y - c.y) * 1.15)
			var r := p.length()
			if r > 27.0:
				continue
			var a := fposmod(p.angle(), TAU)
			if r > 22.0:
				var seg := int(a / (TAU / 14.0))
				var base := Color("4a405e") if seg % 2 == 0 else Color("443a58")
				var col := base
				if r > 26.0:
					col = Color("1c1428")
				elif r < 23.0:
					col = base.darkened(0.4)
				elif fmod(a, TAU / 14.0) < 0.08:
					col = Color("1c1428")
				elif r > 25.0:
					col = base.darkened(0.15)
				elif p.y < 0.0:
					col = base.lightened(0.1)
				_px(x, y, col)
			else:
				var col := Color("1a1428")
				if _hash(x, y, 77) % 11 == 0:
					col = Color("221a32")
				if absf(r - 12.0) < 0.6:
					col = Color("2e2048")
				_px(x, y, col)
	# Engraved runes on the stone ring.
	for i: int in range(14):
		var a := (i + 0.5) * TAU / 14.0
		var p := Vector2(c) + Vector2(cos(a) * 24.5, sin(a) * 24.5 / 1.15)
		if p.y < 61:
			continue
		var g := _hash(i, 3, 5) % 3
		_px(int(p.x), int(p.y), Color("8a6a2a"))
		_px(int(p.x) + (1 if g == 0 else 0), int(p.y) + (1 if g != 0 else 0), Color("6a4a1a"))


# ------------------------------------------------------------- top wall ---
static func _top_wall() -> void:
	var tones := [Color("2e2644"), Color("362d50"), Color("3d3358"), Color("332a4a"), Color("2a2240")]
	# The wall face: ashlar courses of uneven stones over dark mortar.
	_rect(26, 7, 428, 43, Color("140e1e"))
	var heights := [8, 9, 7, 9, 7]
	var y := 10
	for ri: int in range(heights.size()):
		var h: int = heights[ri]
		var x := 26 - (_hash(ri, 1, 2) % 12)
		while x < 454:
			var w := 12 + _hash(x, ri, 4) % 14
			var base: Color = tones[_hash(x, ri, 6) % tones.size()]
			var x0 := maxi(x, 26)
			var x1 := mini(x + w - 1, 454)
			if x1 - x0 >= 2:
				_stone(x0, y, x1 - x0, h - 1, base, ri * 31 + x)
			x += w
		y += h
	# The wall top seen from above (the wall's thickness) and the cornice below it.
	for x: int in range(26, 454):
		for yy: int in range(0, 6):
			var c := Color("1e182c") if ((x + (8 if yy > 2 else 0)) / 16) % 2 == 0 else Color("231c34")
			if _hash(x, yy, 13) % 13 == 0:
				c = c.lightened(0.08)
			if (x + (8 if yy > 2 else 0)) % 16 == 0 or yy == 3:
				c = Color("120c1c")
			_px(x, yy, c)
		_px(x, 6, Color("6a5f8a"))
		_px(x, 7, Color("4a4066"))
		_px(x, 8, Color("2e2644") if x % 6 != 0 else Color("1c1428"))
		_px(x, 9, Color("120c1c"))
		_darken(x, 10, 0.4)
		_darken(x, 11, 0.2)
	# The wainscot: a moulded rail, raised panels between stiles, a dark skirting.
	for x: int in range(26, 454):
		_px(x, 50, Color("1a0d08"))
		_px(x, 51, PAL["e"])
		_px(x, 52, PAL["d"])
		_px(x, 53, PAL["a"])
		var s := (x - 26) % 20
		for yy: int in range(54, 59):
			var c: Color = PAL["c"]
			if s == 0:
				c = PAL["a"]
			elif s == 1:
				c = PAL["d"]
			elif s >= 3 and s <= 18:
				c = PAL["b"]
				if yy == 54 or s == 3:
					c = Color("2e180e")
				elif yy == 58 or s == 18:
					c = PAL["c"]
				elif _hash(x, yy, 21) % 6 == 0:
					c = c.darkened(0.12)
			_px(x, yy, c)
		_px(x, 59, Color("1a0d08"))
	for wp: Vector2i in WINDOWS:
		_window(wp.x, wp.y, wp == WINDOWS[1])
	_rose(ROSE)
	_banner(Vector2i(94, 11), Color("4a1a7a"))
	_banner(Vector2i(360, 11), Color("6a1424"))
	for s: Vector2i in SCONCES:
		_stamp(SCONCE, s.x - 2, s.y)
		_flame_at(s.x, s.y - 1)
	_cobweb(26, 10, 1)
	_cobweb(453, 10, -1)


## An arched window of leaded diamond panes on a night sky, with a deep stone frame and a sill.
static func _window(x0: int, y0: int, moon: bool) -> void:
	var w := 20
	var h := 34
	var r := w / 2.0
	for v: int in range(-1, h):
		for u: int in range(-2, w + 2):
			var dy := float(v) - r
			var dx := float(u) - (w - 1) / 2.0
			var outer := (v >= r or dx * dx + dy * dy <= (r + 2.0) * (r + 2.0)) and u >= -2 and u < w + 2
			var inner := (v >= r or dx * dx + dy * dy <= (r - 1.0) * (r - 1.0)) and u >= 1 and u < w - 1
			if not outer:
				continue
			var x := x0 + u
			var y := y0 + v
			if inner:
				var c := Color("141a48").lerp(Color("0c1030"), float(v) / h)
				if moon:
					var md := Vector2(x - MOON.x, y - MOON.y).length()
					if md < 12.0:
						c = c.lerp(Color("3a4a8a"), (12.0 - md) / 12.0 * 0.6)
					var sh := Vector2(x - MOON.x - 2, y - MOON.y + 1).length()
					if md < 4.6 and sh >= 3.8:
						c = Color("fff2c8") if md < 3.7 else Color("d8cca0")
				elif _hash(x, y, 61) % 37 == 0:
					c = Color("b8c0ff")
				var on_moon := moon and Vector2(x - MOON.x, y - MOON.y).length() < 4.6
				if ((u + v) % 5 == 0 or (u - v + 100) % 5 == 0) and not on_moon:
					c = c.darkened(0.45)
				if v == int(r) + 4 or (u == w / 2 and v > int(r) + 4):
					c = Color("3a3150")
				_px(x, y, c, true)
			else:
				var c := Color("54496f")
				if dx < 0.0:
					c = Color("74689a")
				if dx < 0.0 and (v < 3 or u < 0):
					c = Color("8a7fb0")
				if dx > 0.0 and u >= w - 1:
					c = Color("3a3150")
				if v >= int(r) and (v - int(r)) % 7 == 0:
					c = Color("2a2240")
				if u == -2 or u == w + 1 or (v < r and dx * dx + dy * dy > (r + 1.2) * (r + 1.2)):
					c = Color("140e1e")
				_px(x, y, c)
	# A keystone and the sill.
	_rect(x0 + w / 2 - 2, y0 - 3, 4, 3, Color("74689a"))
	_px(x0 + w / 2 + 1, y0 - 3, Color("54496f"))
	_rect(x0 + w / 2 - 2, y0 - 4, 4, 1, Color("140e1e"))
	_rect(x0 - 3, y0 + h, w + 6, 1, Color("9a8fc0"))
	_rect(x0 - 3, y0 + h + 1, w + 6, 1, Color("54496f"))
	_rect(x0 - 3, y0 + h + 2, w + 6, 1, Color("140e1e"))


## A round stained-glass window: eight panes of purple, gold, red and blue round a golden eye.
static func _rose(c: Vector2i) -> void:
	var cols := [Color("7a2ac0"), Color("d8a020"), Color("a01e3a"), Color("2a4ab0")]
	for y: int in range(c.y - 14, c.y + 15):
		for x: int in range(c.x - 14, c.x + 15):
			var p := Vector2(x - c.x, y - c.y)
			var r := p.length()
			if r > 13.5:
				continue
			if r > 10.5:
				var col := Color("74689a") if p.x + p.y < 0.0 else Color("4a4066")
				if r > 12.6:
					col = Color("140e1e")
				elif r < 11.3:
					col = Color("2a2240")
				elif int(fposmod(p.angle(), TAU) / (TAU / 12.0)) % 2 == 0 and r > 11.8:
					col = col.lightened(0.1)
				_px(x, y, col)
				continue
			var a := fposmod(p.angle() + PI / 12.0, TAU)
			var sector := int(a / (TAU / 12.0))
			var col: Color
			if r > 5.5:
				col = [Color("6a22b0"), Color("a01e3a"), Color("2a3aa0")][sector % 3]
				# Each petal is brighter toward its middle.
				var mid := absf(fmod(a, TAU / 12.0) - TAU / 24.0) / (TAU / 24.0)
				col = col.lightened(0.25 * (1.0 - mid) * (1.0 - absf(r - 7.8) / 2.5))
			else:
				col = Color("d8a020") if sector % 2 == 0 else Color("b86a18")
			if (absf(sin(a * 6.0)) * r < 0.7 and r > 5.5) or absf(r - 5.5) < 0.6 or r > 9.6:
				col = Color("1a1228")
			if r < 2.6:
				col = Color("ffe27a") if r > 1.2 else Color("2a0c2a")
			_px(x, y, col, true)


## A hanging banner on a gold rod: folds, gold trim, a swallowtail and a crescent-and-eye sigil.
static func _banner(at: Vector2i, cloth: Color) -> void:
	var w := 16
	var h := 32
	for u: int in range(-2, w + 2):
		_px(at.x + u, at.y, PAL["Y"] if u % 3 != 0 else PAL["y"])
	_px(at.x - 3, at.y, PAL["L"])
	_px(at.x + w + 2, at.y, PAL["L"])
	for v: int in range(1, h):
		for u: int in range(w):
			var tail := v - (h - 7)
			if tail > 0 and absi(u * 2 - (w - 1)) < tail * 3:
				continue
			var fold := (u + 1) % 5
			var c := cloth
			if fold == 0:
				c = cloth.lightened(0.18)
			elif fold == 3:
				c = cloth.darkened(0.3)
			if u == 0 or u == w - 1 or v == 1:
				c = PAL["Y"] if u != w - 1 else PAL["y"]
			if v == 3 and u > 0 and u < w - 1:
				c = PAL["y"]
			_px(at.x + u, at.y + v, c)
	# The sigil: a crescent over an eye.
	var sigil := [
		"...YYY...",
		"..Y......",
		"..Y......",
		"...YYY...",
		".........",
		"..YYYYY..",
		".Y.LZL.Y.",
		"..YYYYY..",
	]
	_stamp(sigil, at.x + 4, at.y + 8)
	# Its shadow on the wall.
	for v: int in range(2, h - 2):
		_darken(at.x + w, at.y + v, 0.4)


static func _cobweb(x0: int, y0: int, dir: int) -> void:
	var c := Color(0.75, 0.72, 0.85, 0.35)
	for i: int in range(10):
		_px(x0 + dir * i, y0 + i, c)
	for i: int in range(12):
		_px(x0 + dir * (i / 3), y0 + i, c)
		_px(x0 + dir * i, y0 + (i / 3), c)
	for rr: int in [4, 7, 10]:
		for k: int in range(rr + 1):
			var a := float(k) / rr * PI / 2.0
			_px(x0 + dir * int(round(cos(a) * rr)), y0 + int(round(sin(a) * rr)), c)


# ------------------------------------------------------------- bookcase ---
static func _bookcase(idx: int, r: Rect2i) -> void:
	var x0 := r.position.x
	var y0 := r.position.y
	var w := r.size.x
	var cx := x0 + w / 2
	# A carved arch on the crown, with a gold rosette and finials at the corners.
	for dy: int in range(7):
		var hw := int(sqrt(maxf(0.0, 49.0 - float((7 - dy) * (7 - dy))))) * 2
		for x: int in range(cx - hw, cx + hw):
			var c: Color = PAL["c"]
			if x == cx - hw or dy == 0:
				c = PAL["K"]
			elif x < cx - hw + 2:
				c = PAL["e"]
			elif x >= cx + hw - 2:
				c = PAL["b"]
			_px(x, y0 - 7 + dy, c)
	_px(cx - 1, y0 - 3, PAL["Y"])
	_px(cx, y0 - 3, PAL["L"])
	_px(cx - 1, y0 - 2, PAL["y"])
	_px(cx, y0 - 2, PAL["Y"])
	for fx: int in [x0 - 1, x0 + w - 2]:
		_rect(fx, y0 - 3, 3, 3, PAL["c"])
		_px(fx, y0 - 3, PAL["e"])
		_px(fx + 1, y0 - 4, PAL["d"])
	# The crown moulding with dentils.
	for x: int in range(x0 - 2, x0 + w + 2):
		var s := (x - x0) % 4 == 0
		_px(x, y0, PAL["K"])
		_px(x, y0 + 1, PAL["e"])
		_px(x, y0 + 2, PAL["d"])
		_px(x, y0 + 3, PAL["b"] if s else PAL["c"])
		_px(x, y0 + 4, PAL["a"] if s else PAL["c"])
		_px(x, y0 + 5, PAL["a"])
	# The sides: carved pilasters, lit on the left.
	var by := 60
	for y: int in range(y0 + 6, by):
		_px(x0, y, PAL["K"])
		_px(x0 + 1, y, PAL["d"])
		_px(x0 + 2, y, PAL["c"] if y % 7 != 0 else PAL["e"])
		_px(x0 + 3, y, PAL["b"])
		_px(x0 + w - 4, y, PAL["c"])
		_px(x0 + w - 3, y, PAL["b"] if y % 7 != 0 else PAL["c"])
		_px(x0 + w - 2, y, PAL["a"])
		_px(x0 + w - 1, y, PAL["K"])
	var ix0 := x0 + 4
	var ix1 := x0 + w - 5
	# The back boards.
	for y: int in range(y0 + 6, 53):
		for x: int in range(ix0, ix1 + 1):
			var c := Color("24130c") if (x - ix0) % 9 != 0 else Color("170b06")
			_px(x, y, c)
	var tops := [14, 27, 40]
	for si: int in range(3):
		var ct: int = tops[si]
		var cb := ct + 9
		_shelf_books(idx, si, ix0, ix1, ct, cb)
		# The shadow under the shelf above.
		for x: int in range(ix0, ix1 + 1):
			_darken(x, ct, 0.5)
			_darken(x, ct + 1, 0.3)
		for y: int in range(ct, cb + 1):
			_darken(ix0, y, 0.35)
			_darken(ix1, y, 0.2)
		# The shelf board, with depth.
		for x: int in range(ix0 - 1, ix1 + 2):
			_px(x, cb + 1, PAL["e"])
			_px(x, cb + 2, PAL["c"])
			_px(x, cb + 3, PAL["a"])
		_px(x0 + 2, cb + 2, PAL["Y"])
		_px(x0 + w - 3, cb + 2, PAL["y"])
	# The plinth.
	for x: int in range(x0 - 1, x0 + w + 1):
		_px(x, 53, PAL["e"])
		_px(x, 54, PAL["d"])
		for y: int in range(55, 59):
			var inner := x > x0 + 2 and x < x0 + w - 3 and y > 55 and y < 58
			_px(x, y, PAL["b"] if inner else PAL["c"])
		_px(x, 59, PAL["K"])
	_px(x0 - 1, 53, PAL["K"])
	_px(x0 + w, 53, PAL["K"])


static func _shelf_books(idx: int, si: int, ix0: int, ix1: int, ct: int, cb: int) -> void:
	var props: Array = []
	for p: Array in SHELF_PROPS:
		if int(p[0]) == idx and int(p[1]) == si:
			props.append(p)
	var done := {}
	var x := ix0 + 1
	var k := idx * 97 + si * 13
	while x <= ix1 - 2:
		k += 1
		var placed := false
		for pi: int in range(props.size()):
			var p: Array = props[pi]
			if x >= ix0 + int(p[2]) and not done.has(pi):
				done[pi] = true
				x = _shelf_prop(String(p[3]), x, cb) + 1
				placed = true
				break
		if placed:
			continue
		var r := _hash(k, si, idx) % 100
		var room := ix1 - 1 - x
		if r < 5 and room > 6:
			x += 2 + r % 3
		elif r < 13 and room >= 7:
			x = _lean_book(x, cb, k) + 1
		elif r < 19 and room >= 11:
			x = _book_stack(x, cb, k) + 1
		else:
			var bw: int = [2, 3, 3, 3, 4, 2][_hash(k, 1, 7) % 6]
			bw = mini(bw, room + 1)
			if bw < 2:
				break
			var bh := 6 + _hash(k, 2, 7) % 4
			_book(x, cb, bw, bh, k)
			x += bw


static func _book_col(k: int) -> Color:
	return Color(BOOK_COLS[_hash(k, 5, 3) % BOOK_COLS.size()])


static func _book(x: int, cb: int, bw: int, bh: int, k: int) -> void:
	var base := _book_col(k)
	var bands := bh >= 7 and _hash(k, 8, 1) % 5 < 3
	var title := bw >= 3 and _hash(k, 9, 1) % 5 < 2
	for i: int in range(bw):
		for j: int in range(bh):
			var y := cb - j
			var c := base
			if i == 0:
				c = base.lightened(0.28)
			elif i == bw - 1:
				c = base.darkened(0.42)
			if j == bh - 1:
				c = c.lightened(0.12)
			if bands and (j == 1 or j == bh - 2):
				c = PAL["L"] if i == 0 else (PAL["y"] if i == bw - 1 else PAL["Y"])
			if title and i == bw / 2 and j == bh / 2:
				c = PAL["W"] if _hash(k, 4, 4) % 2 == 0 else PAL["L"]
			_px(x + i, y, c)


## A book leaning on the next one: a slanted spine. Returns its right edge.
static func _lean_book(x: int, cb: int, k: int) -> int:
	var base := _book_col(k)
	var bh := 7 + _hash(k, 3, 3) % 2
	var right := x
	for j: int in range(bh):
		var off := j / 2
		for i: int in range(3):
			var c := base if i == 1 else (base.lightened(0.28) if i == 0 else base.darkened(0.42))
			_px(x + off + i, cb - j, c)
			right = maxi(right, x + off + i)
	return right


## Two or three books lying flat. Returns the stack's right edge.
static func _book_stack(x: int, cb: int, k: int) -> int:
	var n := 2 + _hash(k, 6, 6) % 2
	var right := x
	for b: int in range(n):
		var base := _book_col(k + b * 3)
		var bw := 8 + _hash(k + b, 7, 7) % 3
		var sx := x + (_hash(k + b, 9, 9) % 2)
		for i: int in range(bw):
			_px(sx + i, cb - b * 2, base.darkened(0.35))
			_px(sx + i, cb - b * 2 - 1, base.lightened(0.15) if i > 0 else base)
		_px(sx + bw - 1, cb - b * 2 - 1, PAL["W"])
		_px(sx + bw - 1, cb - b * 2, PAL["w"])
		right = maxi(right, sx + bw - 1)
	return right


static func _shelf_prop(kind: String, x: int, cb: int) -> int:
	match kind:
		"skull":
			_stamp(SKULL, x, cb - 4)
			return x + 5
		"potion":
			_stamp(POTION_SHELF, x, cb - 5, "GhK")
			_px(x + 3, cb, Color("4a8a5a"))
			return x + 3
		"candle":
			_px(x, cb, PAL["X"])
			_px(x + 1, cb, PAL["V"])
			_px(x + 2, cb, PAL["X"])
			for j: int in range(1, 5):
				_px(x + 1, cb - j, PAL["t"])
			_px(x + 2, cb - 1, PAL["T"])
			_flame_at(x + 1, cb - 5)
			return x + 3
		"scroll":
			for b: int in range(3):
				var sy := cb - b * 2
				var sx := x + (b % 2)
				for i: int in range(7):
					_px(sx + i, sy, PAL["w"])
					_px(sx + i, sy - 1, PAL["W"])
				_px(sx, sy, PAL["T"])
				_px(sx + 3, sy - 1, PAL["R"])
				_px(sx + 3, sy, PAL["r"])
			return x + 8
	return x


# --------------------------------------------------------- side walls ---
## The side and bottom walls seen from above: their thick tops, with a lit lip on the room side.
static func _side_walls() -> void:
	var tones := [Color("1e182c"), Color("231c34"), Color("1a1428"), Color("262038")]
	for side: int in range(2):
		var xa := 0 if side == 0 else 454
		for y: int in range(0, 270, 14):
			var row := y / 14
			var off := 7 if row % 2 == 1 else 0
			for yy: int in range(14):
				for xx: int in range(26):
					var x := xa + xx
					var bx := (xx + off) % 13
					var bid := (xx + off) / 13 + row * 5 + side * 50
					var c: Color = tones[_hash(bid, 3, 3) % tones.size()]
					if bx == 0 or yy == 0:
						c = Color("100a18")
					elif yy == 1 or bx == 1:
						c = c.lightened(0.08)
					elif _hash(x, y + yy, 23) % 17 == 0:
						c = c.darkened(0.15)
					var near := float(xx) / 25.0 if side == 0 else 1.0 - float(xx) / 25.0
					c = c.lightened(0.12 * near)
					_px(x, y + yy, c)
		var lip := 25 if side == 0 else 454
		var lip2 := 24 if side == 0 else 455
		for y: int in range(0, 270):
			_px(lip, y, Color("6a5f8a"))
			_px(lip2, y, Color("4a4066"))
	# The bottom wall: darker so the HUD reads on it.
	for y: int in range(250, 270):
		for x: int in range(0, 480):
			var row := (y - 250) / 10
			var off := 9 if row % 2 == 1 else 0
			var bx := (x + off) % 18
			var c := Color("17111f") if ((x + off) / 18 + row) % 3 != 0 else Color("1b1426")
			if bx == 0 or (y - 250) % 10 == 0:
				c = Color("0c0814")
			_px(x, y, c)
	for x: int in range(24, 456):
		_px(x, 250, Color("6a5f8a"))
		_px(x, 251, Color("4a4066"))
		_px(x, 252, Color("2a2240"))
	# Corner posts where the walls meet.
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(450, 0), Vector2i(0, 246), Vector2i(450, 246)]:
		for yy: int in range(10):
			for xx: int in range(30):
				var c := Color("2e2644")
				if yy == 0 or xx == 0:
					c = Color("4a4066")
				elif yy == 9 or xx == 29:
					c = Color("120c1c")
				_px(corner.x + xx, corner.y + yy, c)


## Ambient occlusion where the floor meets the walls.
static func _shadows() -> void:
	for x: int in range(26, 454):
		for k: int in range(8):
			_darken(x, 60 + k, 0.55 * (1.0 - k / 8.0))
		for k: int in range(4):
			_darken(x, 249 - k, 0.3 * (1.0 - k / 4.0))
	for y: int in range(60, 250):
		for k: int in range(6):
			_darken(26 + k, y, 0.45 * (1.0 - k / 6.0))
			_darken(453 - k, y, 0.3 * (1.0 - k / 6.0))


static func _candle_cluster(c: Vector2i) -> void:
	# A puddle of old wax with three candles of different heights.
	_rect(c.x - 4, c.y + 1, 10, 2, Color("cfc0a0"))
	_rect(c.x - 3, c.y + 3, 8, 1, Color("8a7a60"))
	var hs := [6, 10, 4]
	for i: int in range(3):
		var x := c.x - 3 + i * 3
		var h: int = hs[i]
		for j: int in range(h):
			_px(x, c.y - j, PAL["t"])
			_px(x + 1, c.y - j, PAL["T"])
		_px(x + 1, c.y - h + 2, PAL["t"])
		_flame_at(x, c.y - h)


# ------------------------------------------------------------- objects ---
static func _altar(feet: Vector2i) -> void:
	var x0 := feet.x - 12
	var y0 := feet.y - ALTAR.size()
	for u: int in range(-2, 26):
		_darken(x0 + u, feet.y, 0.5)
		_darken(x0 + u, feet.y + 1, 0.3)
	_stamp(ALTAR, x0, y0, "YLZ")
	_flame_at(x0 + 2, y0 - 1)
	_flame_at(x0 + 20, y0 - 1)


## A round stone step under a thing: a lit top, a front edge in shadow.
static func _dais(c: Vector2i, rx: int, ry: int) -> void:
	for y: int in range(c.y - ry - 1, c.y + ry + 4):
		for x: int in range(c.x - rx - 1, c.x + rx + 2):
			var q := Vector2(float(x - c.x) / rx, float(y - c.y) / ry)
			var q2 := Vector2(float(x - c.x) / rx, float(y - c.y - 3) / ry)
			if q.length() <= 1.0:
				var col := Color("6a5f88") if q.x + q.y < 0.0 else Color("5a4f78")
				if q.length() > 0.88:
					col = Color("8a7fb0") if q.y < 0.0 else Color("3a3150")
				elif fmod(fposmod(atan2(q.y, q.x), TAU), TAU / 6.0) < 0.1 and q.length() > 0.4:
					col = Color("2a2240")
				_px(x, y, col)
			elif q2.length() <= 1.0 and y > c.y:
				_px(x, y, Color("2a2240") if q2.length() < 0.93 else Color("140e1e"))
	for x: int in range(c.x - rx, c.x + rx + 1):
		_darken(x, c.y + ry + 4, 0.4)


## A small round rug: deep blue, a gold ring, a star.
static func _round_rug(c: Vector2i, rx: int, ry: int) -> void:
	for y: int in range(c.y - ry, c.y + ry + 1):
		for x: int in range(c.x - rx, c.x + rx + 1):
			var q := Vector2(float(x - c.x) / rx, float(y - c.y) / ry)
			var e := q.length()
			if e > 1.0:
				continue
			var col := Color("1e1a4a")
			if e > 0.92:
				col = Color("0e0a24")
			elif e > 0.78 and e < 0.86:
				col = Color("c8962a")
			elif e > 0.86:
				col = Color("2e2a6a") if (x + y) % 3 != 0 else Color("c8962a")
			elif e < 0.5 and (absf(q.x) * 0.3 + absf(q.y) < 0.18 or absf(q.y) * 0.3 + absf(q.x) < 0.14):
				col = Color("8a6a2a")
			if _hash(x, y, 51) % 8 == 0:
				col = col.darkened(0.1)
			_px(x, y, col)
	for x: int in range(c.x - rx + 3, c.x + rx - 2):
		_darken(x, c.y + ry + 1, 0.35)


## Flagstones set into the boards round the well.
static func _flagstones(c: Vector2i, rx: int, ry: int) -> void:
	for y: int in range(c.y - ry, c.y + ry + 1):
		for x: int in range(c.x - rx, c.x + rx + 1):
			var q := Vector2(float(x - c.x) / rx, float(y - c.y) / ry)
			if q.length() > 1.0:
				continue
			var fx := (x + 50) / 9
			var fy := (y - c.y + 50 + (4 if fx % 2 == 0 else 0)) / 6
			var col: Color = [Color("4a4258"), Color("524a62"), Color("443c52")][_hash(fx, fy, 61) % 3]
			if (x + 50) % 9 == 0 or (y - c.y + 50 + (4 if fx % 2 == 0 else 0)) % 6 == 0:
				col = Color("1c1626")
			elif (y - c.y + 50 + (4 if fx % 2 == 0 else 0)) % 6 == 1:
				col = col.lightened(0.1)
			if q.length() > 0.92:
				col = Color("1c1626")
			_px(x, y, col)


## A gramophone: a cabinet with a record on top and a crank, and a great brass morning-glory horn.
static func _gramophone(feet: Vector2i) -> void:
	var bx := feet.x - 12
	var by := feet.y - MUSIC_BOX.size()
	for u: int in range(-1, 25):
		_darken(bx + u, feet.y, 0.5)
		_darken(bx + u, feet.y + 1, 0.25)
	_stamp(MUSIC_BOX, bx, by)
	# The tone arm rises from the record's edge into the throat of the horn.
	var throat := Vector2(bx + 16, by + 2)
	var mouth := Vector2(bx + 6, by - 15)
	for i: int in range(5):
		_px(bx + 15 + (i / 3), by + 1 - i, PAL["K"])
		_px(bx + 16 + (i / 3), by + 1 - i, PAL["Y"])
		_px(bx + 17 + (i / 3), by + 1 - i, PAL["y"])
	# The bell: discs that widen from the throat to the mouth, lit from the upper left.
	var steps := 40
	for k: int in range(steps + 1):
		var s := float(k) / steps
		var cpos := throat.lerp(mouth, s) + Vector2(0, -3.0 * sin(s * PI))
		var rad := 1.9 + 8.4 * s * s * s
		for y: int in range(int(cpos.y - rad) - 1, int(cpos.y + rad) + 2):
			for x: int in range(int(cpos.x - rad) - 1, int(cpos.x + rad) + 2):
				var d := Vector2(x - cpos.x, (y - cpos.y) * 1.15)
				if d.length() > rad:
					continue
				var lit := -(d.x + d.y) / maxf(rad, 0.1)
				var c: Color = PAL["Y"]
				if lit > 0.6:
					c = PAL["L"]
				elif lit < -0.5:
					c = PAL["y"]
				if d.length() > rad - 0.9:
					c = PAL["K"]
				_px(x, y, c)
	# The mouth: a bright rim, a dark throat inside and the petal seams.
	var mrx := 10.2
	var mry := 7.6
	var mc := mouth + Vector2(0, -3.0 * sin(PI))
	for y: int in range(int(mc.y - mry) - 1, int(mc.y + mry) + 2):
		for x: int in range(int(mc.x - mrx) - 1, int(mc.x + mrx) + 2):
			var q := Vector2((x - mc.x) / mrx, (y - mc.y) / mry)
			var e := q.length()
			if e > 1.0:
				continue
			var c: Color
			if e > 0.86:
				c = PAL["K"] if q.x + q.y > 0.9 else (PAL["Z"] if q.x + q.y < -0.6 else PAL["L"])
			elif e > 0.7:
				c = PAL["Y"] if q.x + q.y < 0.0 else PAL["y"]
			elif e > 0.42:
				c = PAL["y"] if q.x + q.y < 0.3 else Color("6a4410")
			else:
				c = Color("6a4410").lerp(Color("1a0c04"), clampf((0.42 - e) / 0.3, 0.0, 1.0))
			var a := fposmod(atan2(q.y, q.x), TAU)
			if e > 0.3 and e <= 0.86 and fmod(a + 0.2, TAU / 8.0) < 0.22:
				c = c.darkened(0.45)
			_px(x, y, c)


## The wishing well: a rim of stones round dark water, a coursed front wall, two posts, a shingled roof, a
## rope and bucket.
static func _well(c: Vector2i) -> void:
	var rx := 15.0
	var ry := 7.0
	# Shadow on the floor.
	for y: int in range(c.y + 10, c.y + 22):
		for x: int in range(c.x - 18, c.x + 19):
			var p := Vector2((x - c.x) / 18.0, (y - (c.y + 16)) / 6.0)
			if p.length() < 1.0:
				_darken(x, y, 0.45)
	# The front wall: courses of stone, rounded by shading.
	for x: int in range(c.x - 15, c.x + 16):
		var dx := float(x - c.x) / rx
		var edge := int(c.y + ry * sqrt(maxf(0.0, 1.0 - dx * dx)))
		for y: int in range(edge, c.y + 18):
			var course := (y - c.y) / 4
			var bw := 7
			var bx := (x - c.x + 40 + (3 if course % 2 == 1 else 0)) % bw
			var base := Color("4a4466").lerp(Color("2a2440"), clampf((dx + 0.6) / 1.6, 0.0, 1.0))
			var col := base
			if (y - c.y) % 4 == 0 or bx == 0:
				col = Color("16101e")
			elif (y - c.y) % 4 == 1:
				col = base.lightened(0.12)
			if absf(dx) > 0.93:
				col = Color("16101e")
			_px(x, y, col)
		_px(x, c.y + 18, Color("16101e"))
	# The rim and the water.
	for y: int in range(c.y - 8, c.y + 9):
		for x: int in range(c.x - 16, c.x + 17):
			var p := Vector2((x - c.x) / (rx + 1.0), (y - c.y) / (ry + 1.0))
			var d := p.length()
			if d > 1.0:
				continue
			var q := Vector2((x - c.x) / 11.0, (y - c.y) / 4.2)
			if q.length() < 1.0:
				var wc := Color("0b2040").lerp(Color("123058"), clampf(-q.y, 0.0, 1.0))
				if q.length() > 0.85 and q.y < 0.0:
					wc = Color("060a18")
				_px(x, y, wc, true)
				continue
			var a := fposmod(atan2(p.y, p.x), TAU)
			var col := Color("6a6088") if p.y < 0.2 else Color("54496f")
			if d > 0.92:
				col = Color("1a1228")
			elif int(a / (TAU / 16.0)) % 2 == 0:
				col = col.darkened(0.12)
			if fmod(a, TAU / 16.0) < 0.12:
				col = Color("2a2240")
			_px(x, y, col)
	# Posts, the crossbeam, the rope and bucket, the roof.
	for px: int in [c.x - 16, c.x + 14]:
		for y: int in range(c.y - 30, c.y + 4):
			_px(px - 1, y, PAL["K"])
			_px(px, y, PAL["e"] if px < c.x else PAL["d"])
			_px(px + 1, y, PAL["c"])
			_px(px + 2, y, PAL["a"])
			_px(px + 3, y, PAL["K"])
	for x: int in range(c.x - 17, c.x + 18):
		_px(x, c.y - 31, PAL["K"])
		_px(x, c.y - 30, PAL["e"])
		_px(x, c.y - 29, PAL["c"])
		_px(x, c.y - 28, PAL["K"])
	for y: int in range(c.y - 24, c.y - 12):
		_px(c.x, y, PAL["w"] if y % 2 == 0 else PAL["T"])
	var bucket := [
		".KKKKK.",
		"KdeddcK",
		"KXXXXXK",
		".KcccK.",
		".KbbbK.",
		"..KKK..",
	]
	_stamp(bucket, c.x - 3, c.y - 12)
	# The roof: a gable of wooden shingles in staggered rows, a ridge cap, its shadow underneath.
	for v: int in range(15):
		var hw := 3 + int(v * 1.3)
		for u: int in range(-hw, hw + 1):
			var row := v / 3
			var tile := (u + 40 + (2 if row % 2 == 1 else 0)) / 4
			var col: Color = [PAL["c"], PAL["d"], PAL["b"], PAL["c"]][_hash(tile, row, 31) % 4]
			if v % 3 == 2 or (u + 40 + (2 if row % 2 == 1 else 0)) % 4 == 0:
				col = PAL["a"]
			elif u < 0 and v % 3 == 0:
				col = col.lightened(0.15)
			if absi(u) >= hw:
				col = PAL["K"]
			if v == 14:
				col = PAL["K"] if absi(u) % 2 == 0 else PAL["a"]
			_px(c.x + u, c.y - 44 + v, col)
	_rect(c.x - 1, c.y - 46, 3, 2, PAL["e"])
	_px(c.x - 1, c.y - 46, PAL["K"])
	for u: int in range(-18, 19):
		_darken(c.x + u, c.y - 29, 0.5)
	# The winch: a drum wound with rope on the crossbeam, a crank on the right post.
	_rect(c.x - 5, c.y - 28, 11, 4, PAL["d"])
	for u: int in range(-5, 6):
		_px(c.x + u, c.y - 27, PAL["w"] if u % 2 == 0 else PAL["T"])
		_px(c.x + u, c.y - 26, PAL["T"] if u % 2 == 0 else PAL["w"])
		_px(c.x + u, c.y - 25, PAL["b"])
	_rect(c.x - 6, c.y - 28, 1, 4, PAL["K"])
	_rect(c.x + 6, c.y - 28, 1, 4, PAL["K"])
	_px(c.x + 17, c.y - 27, PAL["X"])
	_px(c.x + 18, c.y - 27, PAL["X"])
	_px(c.x + 18, c.y - 26, PAL["X"])
	_px(c.x + 18, c.y - 25, PAL["V"])
	_px(c.x + 19, c.y - 25, PAL["X"])


## Clutter in the corners and along the walls: bones, a stack of tomes, loose pages and a dropped scroll.
static func _floor_clutter() -> void:
	var bones := [
	"....KKKK...........",
	"...KWWWWK..........",
	"..KWWWWWwK.....KK..",
	"..KWKKWKwK....KWWK.",
	"..KWKKWKwK...KWwK..",
	"...KWWWwK...KWwK...",
	"KK..KWwWK..KWwK....",
	"KWKKKKKKKKKWwKKKKK.",
	".KWWWWWWWWWWWWWWwWK",
	"KWKKKKKKKKKKKKKKKK.",
	"KK.................",
]
	_stamp(bones, 28, 238)
	var tomes := [
		"..KKKKKKKKK.",
		"..KRRRRRRRWK",
		"..KrrrrrrrwK",
		".KKKKKKKKKK.",
		".KBBBBBBBBWK",
		".KkkkkkkkkwK",
		"KKKKKKKKKKK.",
		"KPPPPPPPPPWK",
		"KppppppppwwK",
		"KKKKKKKKKKK.",
	]
	_stamp(tomes, 438, 238)
	var page := [
		"..TWWW.",
		".TWwwWW",
		"TWWWWwW",
		"WwwWwWT",
		"WWWWWT.",
		".TWT...",
	]
	for at: Vector2i in [Vector2i(130, 148), Vector2i(342, 94)]:
		_stamp(page, at.x, at.y)
	var open_book := [
		".KKKKK.KKKKK.",
		"KWWWWWKWWWWWK",
		"KWwwwWKWwwWWK",
		"KWWWwWKWWwwWK",
		"KWwwWWKWwWWWK",
		"KTTTTTrTTTTTK",
		".KKKKKRKKKKK.",
		"......R......",
	]
	_stamp(open_book, 112, 140)
	_chalk(Vector2(104, 186), 15.0)
	_candle_cluster(Vector2i(33, 120))
	_candle_cluster(Vector2i(447, 112))
	var scroll := [
		".WWWWWWWW.",
		"TWwwwwwwWT",
		".TTRTTTTT.",
	]
	_stamp(scroll, 352, 186)
	# Old wax drips by the left wall and a dropped quill.
	_line(Vector2(330, 236), Vector2(336, 232), PAL["W"])
	_px(330, 237, PAL["K"])


# ------------------------------------------------------------- alcove ---
static func _crack() -> void:
	# Tired stones: two pushed proud of the wall (lit), one sunk back (dark), and a crack that runs up from the
	# floor through them, lit on its lower lip. Dust and rubble at its foot.
	for st: Array in [[Rect2i(398, 43, 12, 6), 0.18], [Rect2i(414, 27, 10, 6), 0.14], [Rect2i(418, 43, 9, 6), -0.3]]:
		var rr: Rect2i = st[0]
		for y: int in range(rr.position.y, rr.end.y):
			for x: int in range(rr.position.x, rr.end.x):
				var c := _img.get_pixel(x, y)
				_px(x, y, c.lightened(st[1]) if float(st[1]) > 0.0 else c.darkened(-float(st[1])))
		if float(st[1]) > 0.0:
			for x: int in range(rr.position.x, rr.end.x):
				_darken(x, rr.end.y, 0.5)
	var cc := Color("06040c")
	var lip := Color("7a6f9a")
	var path := [Vector2i(403, 59), Vector2i(405, 55), Vector2i(407, 52), Vector2i(408, 48), Vector2i(407, 45),
		Vector2i(410, 41), Vector2i(410, 37), Vector2i(413, 33), Vector2i(414, 29), Vector2i(417, 25)]
	for i: int in range(path.size() - 1):
		_line(Vector2(path[i]), Vector2(path[i + 1]), cc)
		_line(Vector2(path[i]) + Vector2(1, 1), Vector2(path[i + 1]) + Vector2(1, 1), lip)
	for br: Array in [[Vector2(408, 48), Vector2(414, 46), Vector2(419, 49)], [Vector2(410, 41), Vector2(405, 38)],
			[Vector2(421, 59), Vector2(419, 54), Vector2(423, 50), Vector2(422, 45)], [Vector2(413, 33), Vector2(420, 31)]]:
		for i: int in range(br.size() - 1):
			_line(br[i], br[i + 1], cc)
			_line(br[i] + Vector2(1, 1), br[i + 1] + Vector2(1, 1), lip)
	for p: Vector2i in [Vector2i(400, 61), Vector2i(402, 62), Vector2i(414, 61), Vector2i(421, 62), Vector2i(425, 61),
			Vector2i(408, 63), Vector2i(417, 64)]:
		_px(p.x, p.y, Color("8a7fb0"))
		_px(p.x + 1, p.y, Color("3a3150"))
		_px(p.x, p.y + 1, Color("1c1428"))
	for x: int in range(399, 428):
		if _hash(x, 60, 3) % 3 == 0:
			_px(x, 60, Color("5a4f6a"))


static func _open_alcove() -> void:
	var a := Rect2i(390, 30, 44, 30)
	# The niche: dark back wall, flagstone floor, inner side walls in shadow.
	for y: int in range(12, 30):
		for x: int in range(a.position.x, a.end.x):
			var ad := Vector2((x - 411.5) / 22.0, (y - 30.0) / 18.0).length()
			if ad > 1.0:
				continue
			if ad > 0.9:
				_px(x, y, Color("6a5f8a") if x < 412 else Color("4a4066"))
				continue
			var c := Color("221a32") if ((x + (5 if (y / 6) % 2 == 1 else 0)) / 10) % 2 == 0 else Color("261e38")
			if y % 6 == 0 or (x + (5 if (y / 6) % 2 == 1 else 0)) % 10 == 0:
				c = Color("120c1c")
			_px(x, y, c.darkened(0.5))
	for y: int in range(a.position.y, 62):
		for x: int in range(a.position.x, a.end.x):
			var fx := (x - a.position.x) / 11
			var fy := (y - a.position.y) / 8
			var c := Color("3a2c34") if (fx + fy) % 2 == 0 else Color("42323a")
			if (x - a.position.x) % 11 == 0 or (y - a.position.y) % 8 == 0:
				c = Color("181020")
			_px(x, y, c)
		for k: int in range(5):
			_darken(a.position.x + k, y, 0.4 * (1.0 - k / 5.0))
			_darken(a.end.x - 1 - k, y, 0.4 * (1.0 - k / 5.0))
	for x: int in range(a.position.x, a.end.x):
		for k: int in range(6):
			_darken(x, a.position.y + k, 0.5 * (1.0 - k / 6.0))
	# The wall's broken edges either side of the opening.
	for y: int in range(30, 62):
		_px(a.position.x - 1, y, Color("6a5f8a"))
		_px(a.position.x - 2, y, Color("140e1e"))
		_px(a.end.x, y, Color("2a2240"))
		_px(a.end.x + 1, y, Color("140e1e"))
	for p: Vector2i in [Vector2i(388, 58), Vector2i(389, 55), Vector2i(435, 57), Vector2i(436, 60), Vector2i(386, 61)]:
		_rect(p.x, p.y, 2, 2, Color("4a4066"))
		_px(p.x + 1, p.y + 1, Color("1c1428"))
	# A velvet cushion with gold tassels, the cat asleep on it, a candle stub, a cache of crystals and coins.
	for y: int in range(45, 53):
		for x: int in range(405, 435):
			var e := Vector2((x - 420) / 15.0, (y - 49) / 3.6).length()
			if e < 1.0:
				var c := Color("8a2ac0") if y < 48 else (Color("6a1a9a") if y < 50 else Color("4a1070"))
				if e > 0.84:
					c = Color("1c0a30")
				elif y == 46 and x < 420:
					c = Color("b050e0")
				_px(x, y, c)
	for p: Vector2i in [Vector2i(405, 49), Vector2i(434, 49)]:
		_px(p.x, p.y, PAL["L"])
		_px(p.x, p.y + 1, PAL["Y"])
		_px(p.x, p.y + 2, PAL["y"])
	_stamp(CAT, 411, 37, "nvKQ")
	var crystals := [
		"....C.......",
		"...CZB...C..",
		"..CCCB..CZB.",
		".CZCCBB.CCB.",
		".CCCCBBCCCB.",
		"KKKKKKKKKKKK",
	]
	_stamp(crystals, 392, 32, "CZB")
	var coins := [
		"...KK...",
		"..KLYK..",
		".KLYYyK.",
		"KLYYYYyK",
		"KKKKKKKK",
	]
	_stamp(coins, 394, 51)
	_rect(426, 38, 3, 1, PAL["X"])
	for j: int in range(1, 3):
		_px(427, 38 - j, PAL["t"])
	_px(428, 37, PAL["T"])
	_flame_at(427, 35)
	# A mouse hole in the back wall.
	_rect(427, 26, 3, 4, Color("06040a"))
	_px(426, 28, Color("06040a"))
	_px(430, 28, Color("06040a"))


# ------------------------------------------------------------- lighting ---
static func _add_light(at: Vector2, radius: float, strength: float, cool: bool) -> void:
	var x0 := maxi(0, int(at.x - radius))
	var x1 := mini(W - 1, int(at.x + radius))
	var y0 := maxi(0, int(at.y - radius))
	var y1 := mini(H - 1, int(at.y + radius))
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var d := Vector2(x - at.x, y - at.y).length() / radius
			if d < 1.0:
				var v := strength * (1.0 - d) * (1.0 - d)
				if cool:
					_cool[y * W + x] += v
				else:
					_warm[y * W + x] += v


static func _lights() -> void:
	for f: Vector2 in _flames:
		_add_light(f, 40.0, 0.5, false)
	for wp: Vector2i in WINDOWS:
		_add_light(Vector2(wp.x + 10, wp.y + 20), 34.0, 0.5, true)
		# Moonlight falling through each window onto the boards.
		for y: int in range(60, 118):
			var t := float(y - 60)
			for x: int in range(wp.x - 6, wp.x + 26):
				var bx := float(x - wp.x) - t * 0.35
				if bx > -2.0 and bx < 22.0:
					var k := (1.0 - t / 58.0) * 0.55
					if bx < 0.0 or bx > 20.0:
						k *= 0.5
					_cool[y * W + x] += k
	_add_light(Vector2(ROSE), 30.0, 0.35, false)
	_add_light(Vector2(240, 82), 46.0, 0.6, true)
	_add_light(Vector2(84, 98), 30.0, 0.5, false)
	_add_light(Vector2(396, 112), 30.0, 0.35, true)
	_add_light(Vector2(240, 236), 26.0, 0.35, true)
	_add_light(Vector2(410, 214), 22.0, 0.3, true)
	_add_light(Vector2(64, 200), 26.0, 0.25, false)
	_add_light(Vector2(398, 36), 16.0, 0.6, true)


## Lights the pixels in `r`: an ambient level plus warm candlelight and cool moonlight, each banded with a 4x4
## ordered dither so the light falls off in pixel-art steps instead of a smooth gradient.
static func _apply_light(r: Rect2i) -> void:
	var bayer := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	var amb := Color(0.62, 0.58, 0.72)
	var warm := Color(1.0, 0.66, 0.36)
	var cool := Color(0.55, 0.66, 1.0)
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var i := y * W + x
			if _emit[i] == 1:
				continue
			var th: float = (bayer[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0
			var wv := floorf(minf(_warm[i], 1.0) * 5.0 + th) / 5.0
			var cv := floorf(minf(_cool[i], 1.0) * 4.0 + th) / 4.0
			var c := _img.get_pixel(x, y)
			var lr := amb.r + warm.r * wv * 0.75 + cool.r * cv * 0.35
			var lg := amb.g + warm.g * wv * 0.75 + cool.g * cv * 0.35
			var lb := amb.b + warm.b * wv * 0.75 + cool.b * cv * 0.35
			_img.set_pixel(x, y, Color(minf(c.r * lr, 1.0), minf(c.g * lg, 1.0), minf(c.b * lb, 1.0)))

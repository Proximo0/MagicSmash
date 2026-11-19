class_name Sprites
## Procedural pixel-art sprites built from ASCII maps at startup.
## Each sprite also gets a pure-white "flash" twin for hit feedback.
## To change art, edit the maps below: one character per pixel, "." = clear.

static var _tex := {}
## Every sprite (and its white flash copy) packed into one texture, so a frame of hundreds of different sprites
## batches into a few draw calls instead of one per texture switch. key -> region in _atlas.
static var _atlas: ImageTexture
static var _region := {}
static var _imgs := {}
const ATLAS_W := 256
const ATLAS_PAD := 1

const OUTLINE := Color("1a0f24")
## Positions in the simulation are on the floor (where the feet stand). Anything that flies (spell shots, enemy
## shots, a staff head, orbiting orbs, an aura round a body) is drawn this many pixels above its floor position,
## so a shot crosses a body at chest height at the moment the simulation counts the hit.
const LIFT := 7.0

const PLAYER_COLORS := [
	{"name": "VIOLET", "robe": Color("7b4dff"), "shade": Color("4b2ab8"), "band": Color("ffd94d"), "fx": Color("c9a6ff")},
	{"name": "CRIMSON", "robe": Color("ff3b5c"), "shade": Color("a81d3d"), "band": Color("ffd94d"), "fx": Color("ff9a6b")},
	{"name": "EMERALD", "robe": Color("29d16b"), "shade": Color("15864a"), "band": Color("fff27a"), "fx": Color("8bff9e")},
	{"name": "AMBER", "robe": Color("ffb326"), "shade": Color("c26a0e"), "band": Color("4dfff0"), "fx": Color("ffe58a")},
]

# --- Wizard ---------------------------------------------------------------
const WIZ_DOWN_A := [
	"......KK....",
	".....KHHK...",
	".....KHhK...",
	"....KHYHhK..",
	"....KHHHhK..",
	"...KHHHHHhK.",
	".KKhhhhhhhKK",
	"..KKKKKKKKK.",
	"...KSESSESK.",
	"...KSSSSSSK.",
	"..KRBBSSBBRK",
	"..KRBBBBBBrK",
	".KRRRBBBBrrK",
	".KRRRRBBRrrK",
	".KRRRRRRRrrK",
	"..KKK..KKK..",
]
const WIZ_DOWN_B := [
	"......KK....",
	".....KHHK...",
	".....KHhK...",
	"....KHYHhK..",
	"....KHHHhK..",
	"...KHHHHHhK.",
	".KKhhhhhhhKK",
	"..KKKKKKKKK.",
	"...KSESSESK.",
	"...KSSSSSSK.",
	"..KRBBSSBBRK",
	"..KRBBBBBBrK",
	".KRRRBBBBrrK",
	".KRRRRBBRrrK",
	".KRRRRRRRrrK",
	"...KKK..KK..",
]
const WIZ_UP_A := [
	"....KK......",
	"...KHHK.....",
	"...KHHhK....",
	"..KHHYHhK...",
	"..KHHHHhK...",
	".KHHHHHHhK..",
	"KKhhhhhhhhKK",
	".KKKKKKKKKK.",
	"..KhhhhhhhK.",
	"..KRRRRRRrK.",
	".KRRRRRRRrK.",
	".KRRRRRRRrrK",
	".KRRRRRRRrrK",
	".KRRRRRRRrrK",
	".KRRRRRRRrrK",
	"..KKK..KKK..",
]
const WIZ_UP_B := [
	"....KK......",
	"...KHHK.....",
	"...KHHhK....",
	"..KHHYHhK...",
	"..KHHHHhK...",
	".KHHHHHHhK..",
	"KKhhhhhhhhKK",
	".KKKKKKKKKK.",
	"..KhhhhhhhK.",
	"..KRRRRRRrK.",
	".KRRRRRRRrK.",
	".KRRRRRRRrrK",
	".KRRRRRRRrrK",
	".KRRRRRRRrrK",
	".KRRRRRRRrrK",
	"...KK..KKK..",
]
const WIZ_SIDE_A := [
	"........KK..",
	"......KKHK..",
	".....KHHK...",
	"....KHYHHK..",
	"....KHHHhK..",
	"...KHHHHHhK.",
	"..KhhhhhhhhK",
	"...KKKKKKKK.",
	"....KSSSESK.",
	"....KSSSSSSK",
	"...KRRSBBBK.",
	"...KRRBBBBK.",
	"..KRRRRBBK..",
	"..KRRRRRRrK.",
	"..KRRRRRRrK.",
	"...KKK.KKK..",
]
const WIZ_SIDE_B := [
	"........KK..",
	"......KKHK..",
	".....KHHK...",
	"....KHYHHK..",
	"....KHHHhK..",
	"...KHHHHHhK.",
	"..KhhhhhhhhK",
	"...KKKKKKKK.",
	"....KSSSESK.",
	"....KSSSSSSK",
	"...KRRSBBBK.",
	"...KRRBBBBK.",
	"..KRRRRBBK..",
	"..KRRRRRRrK.",
	"..KRRRRRRrK.",
	"..KKK...KKK.",
]

# --- Pickups --------------------------------------------------------------
const POTION := [
	"..KKK..",
	"..KwK..",
	".KKKKK.",
	"KRLRRRK",
	"KRRRRRK",
	"KRRRRrK",
	".KRRrK.",
	"..KKK..",
]
const GEM := [
	"..KKK..",
	".KLCCK.",
	"KLCCCcK",
	"KCCCCcK",
	".KCCcK.",
	"..KcK..",
	"...K...",
]
## Experience shard dropped by every enemy (World.PK_XP).
const XP_SHARD := [
	"..K..",
	".KLK.",
	"KLGgK",
	"KGGgK",
	".KgK.",
	"..K..",
]
const COIN := [
	".KKK.",
	"KYLYK",
	"KYYyK",
	"KYYyK",
	".KKK.",
]
## Treasure chest dropped by elites and the Lich (World.PK_CHEST).
const CHEST := [
	".KKKKKKK.",
	"KWwwYwwWK",
	"KKKKYKKKK",
	"KWwYLYwWK",
	"KWwwYwwWK",
	"KWwwwwwWK",
	".KKKKKKK.",
]
const URN := [
	"..KKKK..",
	".KuuuuK.",
	"..KUUK..",
	".KUUUUK.",
	"KUULUUUK",
	"KUuuuuUK",
	"KUUUUUUK",
	".KUUUUK.",
	"..KKKK..",
]
const CARD := [
	"KKKKKKK",
	"KYYYYYK",
	"KYPPPYK",
	"KYPLPYK",
	"KYLLLYK",
	"KYPLPYK",
	"KYPPPYK",
	"KYYYYYK",
	"KKKKKKK",
]
const BOOT := [
	"..KKKK.",
	"..KBBK.",
	"..KBBK.",
	"..KBBK.",
	"KKKBBK.",
	"KBBBBbK",
	"KKKKKKK",
]
const TOME := [
	"KKKKKKKK.",
	"KCCCCCCWK",
	"KCCKKCCWK",
	"KCKCCKCWK",
	"KCKCCKCWK",
	"KCCKKCCWK",
	"KCCCCCCWK",
	"KccccccWK",
	"KKKKKKKKK",
]

static func build_all() -> void:
	if not _tex.is_empty():
		return
	for i in 4:
		var c: Dictionary = PLAYER_COLORS[i]
		var pal := {
			"K": OUTLINE, "H": c.robe, "h": c.shade, "Y": c.band,
			"R": c.robe, "r": c.shade, "S": Color("ffd2a6"), "E": Color("1a0f24"),
			"B": Color("f4f1ff"),
		}
		_add("wiz%d_down_a" % i, WIZ_DOWN_A, pal)
		_add("wiz%d_down_b" % i, WIZ_DOWN_B, pal)
		_add("wiz%d_up_a" % i, WIZ_UP_A, pal)
		_add("wiz%d_up_b" % i, WIZ_UP_B, pal)
		_add("wiz%d_side_a" % i, WIZ_SIDE_A, pal)
		_add("wiz%d_side_b" % i, WIZ_SIDE_B, pal)
	SpritesEnemies.add_all()
	_add("potion", POTION, {"K": OUTLINE, "R": Color("ff3b6b"), "r": Color("a3133c"), "L": Color("ffd0dc"), "w": Color("c8a070")})
	_add("gem", GEM, {"K": OUTLINE, "C": Color("4df0ff"), "c": Color("1a8fb8"), "L": Color("ffffff")})
	_add("xp", XP_SHARD, {"K": OUTLINE, "G": Color("5dff7a"), "g": Color("1f9e4a"), "L": Color("eaffd8")})
	_add("chest", CHEST, {"K": OUTLINE, "W": Color("8a4b22"), "w": Color("b8682f"), "Y": Color("ffd23d"), "L": Color("fff6c0")})
	_add("chest_rare", CHEST, {"K": OUTLINE, "W": Color("1c3f8a"), "w": Color("2f6fd0"), "Y": Color("8fe3ff"), "L": Color("ffffff")})
	_add("chest_ultra", CHEST, {"K": OUTLINE, "W": Color("5a1a8a"), "w": Color("b03ad0"), "Y": Color("ff8af0"), "L": Color("ffffff")})
	_add("urn", URN, {"K": OUTLINE, "U": Color("b0643a"), "u": Color("7a3f22"), "L": Color("f0b080")})
	_add("card", CARD, {"K": OUTLINE, "Y": Color("ffd94d"), "P": Color("3a1a6a"), "L": Color("ff4df2")})
	_add("coin", COIN, {"K": OUTLINE, "Y": Color("ffd23d"), "y": Color("c48a10"), "L": Color("fff6c0")})
	_add("boot", BOOT, {"K": OUTLINE, "B": Color("4dc8ff"), "b": Color("2a6fb8")})
	var tome_cols := {
		"tome_fire": [Color("ff6a2a"), Color("b83010")],
		"tome_frost": [Color("7fe0ff"), Color("3a86c8")],
		"tome_storm": [Color("ffe84d"), Color("c09a10")],
		"tome_star": [Color("ff7ae6"), Color("a83aa0")],
		"tome_rune": [Color("ff4d6d"), Color("a01a3a")],
		"tome_orbit": [Color("8bff9e"), Color("2fa04a")],
	}
	for k in tome_cols:
		_add(k, TOME, {"K": OUTLINE, "C": tome_cols[k][0], "c": tome_cols[k][1], "W": Color("fff6e0")})
	_pack()

## Shelf-packs every sprite image into one atlas texture, tallest first.
static func _pack() -> void:
	var keys: Array = _imgs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ha: int = (_imgs[a] as Image).get_height()
		var hb: int = (_imgs[b] as Image).get_height()
		return ha > hb if ha != hb else a < b)
	var x := ATLAS_PAD
	var y := ATLAS_PAD
	var shelf := 0
	var spots := {}
	for k: String in keys:
		var img: Image = _imgs[k]
		if x + img.get_width() + ATLAS_PAD > ATLAS_W:
			x = ATLAS_PAD
			y += shelf + ATLAS_PAD
			shelf = 0
		spots[k] = Vector2i(x, y)
		x += img.get_width() + ATLAS_PAD
		shelf = maxi(shelf, img.get_height())
	var h := y + shelf + ATLAS_PAD
	var atlas := Image.create(ATLAS_W, h, false, Image.FORMAT_RGBA8)
	for k: String in keys:
		var img: Image = _imgs[k]
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), spots[k])
		_region[k] = Rect2(spots[k], img.get_size())
	_atlas = ImageTexture.create_from_image(atlas)
	_imgs.clear()

static func _add(key: String, rows: Array, pal: Dictionary) -> void:
	var w := 0
	for r in rows:
		w = maxi(w, (r as String).length())
	var h := rows.size()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var white := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if ch == "." or not pal.has(ch):
				continue
			img.set_pixel(x, y, pal[ch])
			white.set_pixel(x, y, Color.WHITE)
	_tex[key] = ImageTexture.create_from_image(img)
	_tex[key + "!"] = ImageTexture.create_from_image(white)
	_imgs[key] = img
	_imgs[key + "!"] = white

static func get_tex(key: String, flash: bool = false) -> Texture2D:
	if flash:
		return _tex.get(key + "!")
	return _tex.get(key)

## Draws a sprite centred on its feet point (bottom-centre), pixel-snapped.
static func draw_at(ci: CanvasItem, key: String, feet: Vector2, flip: bool = false,
		flash: bool = false, modulate: Color = Color.WHITE, scale: float = 1.0) -> void:
	var src: Rect2 = _region.get(key + "!" if flash else key, Rect2())
	if src.size == Vector2.ZERO:
		return
	var sz := src.size * scale
	var p := (feet - Vector2(sz.x / 2.0, sz.y)).round()
	# A negative width mirrors the sprite without a transform change, which would split the batch.
	var dst := Rect2(p.x + sz.x, p.y, -sz.x, sz.y) if flip else Rect2(p, sz)
	ci.draw_texture_rect_region(_atlas, dst, src, modulate, false, false)

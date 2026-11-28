class_name Sprites
## Procedural pixel-art sprites built from ASCII maps at startup.
## Each sprite also gets a pure-white "flash" twin for hit feedback.
## To change art, edit the maps below: one character per pixel, "." = clear.
## The wizards live in SpritesWizards and the enemies in SpritesEnemies; pickups and magic are here.
## Look at any change with tools/sprite_sheet.gd before the game: it draws every sprite on one picture.

## Every sprite (and its white flash copy) packed into one texture, so a frame of hundreds of different sprites
## batches into a few draw calls instead of one per texture switch. key -> region in _atlas.
## `rect` and `line` draw from a white texel of the same atlas, so plain shapes batch with the sprites too.
static var _atlas: ImageTexture
static var _atlas_img: Image
static var _region := {}
static var _imgs := {}
static var _tex := {}
static var _alias := {}
static var _strips := {}
static var _px := Rect2()
## Why the atlas could not be packed ("" when it is fine). `_pack` also raises it as an engine error.
static var pack_error := ""
## Mistakes found in the maps while building (a letter with no colour, ragged rows). tools/sprite_sheet.gd prints them.
static var problems: Array[String] = []
## The atlas starts this wide and doubles until it is no taller than wide; it may not pass ATLAS_MAX either way.
const ATLAS_MIN := 256
const ATLAS_MAX := 2048
const ATLAS_PAD := 1

const OUTLINE := Color("1a0f24")
const INK := Color("0b0716")

## The four wizards' colours, in Wizards.ROSTER order. `fx` is the light step of the robe's ramp (magic, glows and
## the staff head), `robe` the middle and `shade` the dark one; `deep` is one step darker for folds.
const PLAYER_COLORS := [
	{"name": "VIOLET", "robe": Color("7b4dff"), "shade": Color("4b2ab8"), "band": Color("ffd94d"), "fx": Color("c9a6ff"),
		"deep": Color("2f1a7a")},
	{"name": "CRIMSON", "robe": Color("ff3b5c"), "shade": Color("a81d3d"), "band": Color("ffd94d"), "fx": Color("ff9a6b"),
		"deep": Color("6e1230")},
	{"name": "EMERALD", "robe": Color("29d16b"), "shade": Color("15864a"), "band": Color("e8dcc0"), "fx": Color("8bff9e"),
		"deep": Color("0d5236")},
	{"name": "AMBER", "robe": Color("ffb326"), "shade": Color("c26a0e"), "band": Color("4dfff0"), "fx": Color("ffe58a"),
		"deep": Color("7a3d0a")},
]

## One colour per spell (World.SP_ARCANE .. SP_BLADES): its shots, its tome and its icon. The arcane bolt is drawn
## in its caster's `fx` colour instead. No spell is red: red on the floor is always an enemy's shot.
## Wave 3 appends BONE SPEAR (bone), VIGIL CANDLE (candle flame) and CLEAVE (steel). Stage 3 appends HEX (witch
## green) and SPIRIT BLADES (spectral teal): first picks, the jobs that build the two spells may change them.
const SPELL_COLORS := [Color("c9a6ff"), Color("ff9a3c"), Color("8fe3ff"), Color("ffe58a"), Color("ff4df2"), Color("b07bff"),
	Color("e8dcc0"), Color("ffcf5a"), Color("d8e4f0"), Color("9be564"), Color("5fe0c8")]
const SPELL_DARK := [Color("7b4dff"), Color("c85a1e"), Color("4fa3d8"), Color("c48a10"), Color("a01d9a"), Color("5a2ac8"),
	Color("b7a98e"), Color("c48a10"), Color("6c7a90"), Color("3f8f2a"), Color("1f8f7a")]
## The rune shield's orbs and its tome.
const ORBIT_COLOR := Color("32e0c4")
## Experience motes.
const XP_COLOR := Color("6fd23c")
## Glow discs: fx_glow_<i> is GLOW_SIZES[i] pixels across.
const GLOW_SIZES := [7, 11, 15, 21, 29, 41, 57, 81]
## Shots are plotted in this many directions, clockwise from east (see `dir16`).
const DIRS := 16

# --- Pickups: calm on the floor, a dark outline, one small bright core ------
## Experience mote, dropped by every enemy (World.PK_XP), and its rare twinkle.
const XP_MOTE := [
	"..K..",
	".KGK.",
	"KGWgK",
	".KgK.",
	"..K..",
]
const XP_TWINKLE := [
	"..W..",
	".KGK.",
	"WGWGW",
	".KGK.",
	"..W..",
]
## A coin turning: face, three-quarter, edge, three-quarter from behind.
const COIN := [
	[
		".KKKK.",
		"KYWYyK",
		"KWYYyK",
		"KYYYyK",
		"KyyyyK",
		".KKKK.",
	],
	[
		"..KK..",
		".KWyK.",
		".KYyK.",
		".KYyK.",
		".KyyK.",
		"..KK..",
	],
	[
		"..KK..",
		"..KWK.",
		"..KYK.",
		"..KYK.",
		"..KyK.",
		"..KK..",
	],
	[
		"..KK..",
		".KyWK.",
		".KyYK.",
		".KyYK.",
		".KyyK.",
		"..KK..",
	],
]
const GEM := [
	"..KKK..",
	".KWCcK.",
	"KWCCccK",
	"KCCCcdK",
	"KCCccdK",
	".KCcdK.",
	"..KdK..",
	"...K...",
]
const POTION := [
	"..KKK..",
	"..KbK..",
	"..KGK..",
	".KKRKK.",
	"KRWRRrK",
	"KRRRRrK",
	"KRRRrrK",
	".KRrrK.",
	"..KKK..",
]
## Treasure chest (World.PK_CHEST and its two richer tiers): banded lid, lock plate, a glint on the lid.
const CHEST := [
	"..KKKKKKKKKK..",
	".KWHBBBBBBBbK.",
	"KIiHBBBBBBbIiK",
	"KIiBBBBBBBbIiK",
	"KIibbbbbbbbIiK",
	"KKKKKKYYKKKKKK",
	"KIiBBBYyBBbIiK",
	"KIiBBBByBBbIiK",
	"KIiBBBBBBBbIiK",
	"KIiBBBBBBbbIiK",
	"KIibbbbbbbbIiK",
	".KKKKKKKKKKKK.",
]
const URN := [
	"..KKKKKK..",
	".KWOOOOoK.",
	"..KiiiiK..",
	".KKOOOoKK.",
	"KOWOOOOooK",
	"KOWOOOOooK",
	"KOOOOOOooK",
	"KoOOOOoooK",
	".KoOOoooK.",
	"..KooooK..",
	"..KKKKKK..",
]
const CARD := [
	".KKKKK.",
	"KYYYYYK",
	"KYPPPYK",
	"KYPMPYK",
	"KYMWMYK",
	"KYPMPYK",
	"KYPPPYK",
	"KyyyyyK",
	".KKKKK.",
]
## The boot of haste: leather with a gold cuff and a white wing at the heel.
const BOOT := [
	"....KKKK.",
	"...KYYYK.",
	".W.KBBbK.",
	"WwWKBBbK.",
	".WwKBBBKK",
	"..KBBBBBK",
	"..KbbbbbK",
	"..KKKKKKK",
]
const TOME := [
	".KKKKKKK.",
	"KHCCCCCcK",
	"KCCCECCcK",
	"KCCEWECcK",
	"KCCCECCcK",
	"KCCCCCCcK",
	"KcccccccK",
	"KPPPPPPpK",
	"KcccccccK",
	".KKKKKKK.",
]

# --- Magic: the brightest thing on the screen, drawn on the additive layers --
## The fireball, one frame; the other three are this one turned a quarter each (it tumbles).
const FIRE := [
	"...R.....",
	"..RO..R..",
	".ROOORO..",
	".ROYYOOR.",
	"ROYWWYOR.",
	".ROYWYOR.",
	"..ROYYOR.",
	"...ROOR..",
	"....RR...",
]
const FIRE_BIG := [
	"....R........",
	"...ROR...R...",
	"..ROOR..ROR..",
	".ROOOORROOR..",
	".ROYYYOOOYOR.",
	"ROOYWWYYYYOR.",
	"ROYWWWWWYYOR.",
	".ROYWWWWYOOR.",
	".ROOYWWYYOR..",
	"..ROOYYYOR...",
	"...ROOOOR....",
	"....RRRR.....",
	".............",
]
## The mark a fallen star leaves on the floor (drawn on the additive floor layer, so it glows and fades).
const STAR_MARK := [
	".....m.....",
	"...mMMMm...",
	"mMMMWWWMMMm",
	"...mMMMm...",
	".....m.....",
]
## The rune shield's orb.
const ORB := [
	".ttt.",
	"tTWTt",
	"tTTTt",
	"ttTtt",
	".ttt.",
]
## The heads of the four staffs (violet orb, crimson flame, emerald crystal, amber ring), in the wizard's colours.
const STAFF_HEADS := [
	[
		".KKK.",
		"KWLLK",
		"KLLRK",
		"KLRRK",
		".KKK.",
	],
	[
		"..K..",
		".KLK.",
		".KLK.",
		"KLWRK",
		"KLRRK",
		".KKK.",
	],
	[
		"..K..",
		".KLK.",
		"KLWRK",
		"KLLRK",
		"KLRRK",
		".KRK.",
		"..K..",
	],
	[
		".KKK.",
		"KWLLK",
		"KLKRK",
		"KLRRK",
		".KKK.",
	],
]

# --- Enemy shots: a dark rim round a blood-red body with an orange core ------
const ENEMY_ORB := [
	[
		"..KKK..",
		".KrRrK.",
		"KrRoRrK",
		"KRoyoRK",
		"KrRoRrK",
		".KrRrK.",
		"..KKK..",
	],
	[
		"..KKK..",
		".KRRRK.",
		"KRoooRK",
		"KRoyoRK",
		"KRoooRK",
		".KRRRK.",
		"..KKK..",
	],
]
const ENEMY_SKULL := [
	[
		"..KKKKK..",
		".KRRRRRK.",
		"KRRRRRRRK",
		"KRKKRKKRK",
		"KRKoRoKRK",
		"KRRRKRRRK",
		".KRRRRRK.",
		".KRKRKRK.",
		"..KKKKK..",
	],
	[
		"..KKKKK..",
		".KRRRRRK.",
		"KRRRRRRRK",
		"KRoKRoKRK",
		"KRKKRKKRK",
		"KRRRKRRRK",
		".KRRRRRK.",
		".KRKRKRK.",
		"..KKKKK..",
	],
]


static func build_all() -> void:
	if _atlas != null:
		return
	# A block of white texels for `rect`: it is sampled away from its edge.
	var px := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	px.fill(Color.WHITE)
	add_image("_px", px)
	SpritesWizards.add_all()
	SpritesEnemies.add_all()
	_sp_pickups()
	_sp_magic()
	_pack()
	_px = Rect2((_region["_px"] as Rect2).position + Vector2.ONE, Vector2(2, 2))


static func _sp_pickups() -> void:
	var gold := {"K": OUTLINE, "Y": Color("ffd94d"), "y": Color("c48a10"), "W": Color("fff6c0")}
	_add("xp", XP_MOTE, {"K": Color("1c4a22"), "G": XP_COLOR, "g": Color("2f7a2a"), "W": Color("d8fff6")})
	_add("xp_1", XP_TWINKLE, {"K": Color("1c4a22"), "G": XP_COLOR, "W": Color("d8fff6")})
	for i in COIN.size():
		_add("coin" if i == 0 else "coin_%d" % i, COIN[i], gold)
	_add("gem", GEM, {"K": OUTLINE, "W": Color("d8fff6"), "C": Color("4dfff0"), "c": Color("32e0c4"), "d": Color("158f86")})
	_add("potion", POTION, {"K": OUTLINE, "b": Color("b7a98e"), "G": Color("d8fff6"), "W": Color("ffd2a6"),
		"R": Color("ff3b5c"), "r": Color("a81d3d")})
	_add("chest", CHEST, {"K": OUTLINE, "W": Color("fff6c0"), "H": Color("ff9a3c"), "B": Color("c85a1e"), "b": Color("7a2f14"),
		"I": Color("8a80a8"), "i": Color("4a4063"), "Y": Color("ffd94d"), "y": Color("c48a10")})
	_add("chest_rare", CHEST, {"K": OUTLINE, "W": Color.WHITE, "H": Color("8fe3ff"), "B": Color("4fa3d8"), "b": Color("2a5f9e"),
		"I": Color("e8dcc0"), "i": Color("8a80a8"), "Y": Color("fff6c0"), "y": Color("b7a98e")})
	_add("chest_ultra", CHEST, {"K": OUTLINE, "W": Color.WHITE, "H": Color("c9a6ff"), "B": Color("7b4dff"), "b": Color("4b2ab8"),
		"I": Color("ffd94d"), "i": Color("c48a10"), "Y": Color("fff6c0"), "y": Color("ff4df2")})
	_add("urn", URN, {"K": OUTLINE, "W": Color("ff9a3c"), "O": Color("c85a1e"), "o": Color("7a2f14"), "i": INK})
	_add("card", CARD, {"K": OUTLINE, "Y": Color("ffd94d"), "y": Color("c48a10"), "P": Color("3a2a5e"), "M": Color("ff4df2"),
		"W": Color.WHITE})
	_add("boot", BOOT, {"K": OUTLINE, "B": Color("c85a1e"), "b": Color("7a2f14"), "Y": Color("ffd94d"), "W": Color.WHITE,
		"w": Color("8fe3ff")})
	var tomes := {"tome_fire": 1, "tome_frost": 2, "tome_storm": 3, "tome_star": 4, "tome_rune": 5}
	for k: String in tomes:
		var sp: int = tomes[k]
		_add(k, TOME, _sp_tome_pal(SPELL_COLORS[sp], SPELL_DARK[sp]))
	_add("tome_orbit", TOME, _sp_tome_pal(ORBIT_COLOR, Color("158f86")))


static func _sp_tome_pal(cover: Color, dark: Color) -> Dictionary:
	return {"K": OUTLINE, "H": cover.lerp(Color.WHITE, 0.55), "C": cover, "c": dark, "E": Color("ffd94d"), "W": Color("fff6c0"),
		"P": Color("e8dcc0"), "p": Color("b7a98e")}


## Everything the spells, the enemy shots and the effects are drawn with. White pictures are tinted when drawn.
static func _sp_magic() -> void:
	for i in GLOW_SIZES.size():
		add_image("fx_glow_%d" % i, _sp_glow(GLOW_SIZES[i]))
	add_image("fx_ring", _sp_oval(18, 7))
	# The cores of bright things: a plus and a fatter one.
	add_image("fx_core_0", _sp_rays(3, 0, 1, 1, 0, Color.WHITE, Color.WHITE, Color.WHITE))
	add_image("fx_core_1", _sp_rays(5, 0, 2, 1, 1, Color.WHITE, Color.WHITE, Color.WHITE))
	for d in DIRS:
		var dir := Vector2.from_angle(d * TAU / DIRS)
		add_image("fx_bolt_%d" % d, _sp_comet(dir, 10, 3.0))
		add_image("fx_lance_%d" % d, _sp_comet(dir, 16, 3.4, 4.0))
		add_image("fx_shard_%d" % d, _sp_shard(dir, 8, false))
		add_image("fx_shardx_%d" % d, _sp_shard(dir, 12, true))
		add_image("fx_earrow_%d" % d, _sp_arrow(dir))
	var fire := {"W": Color("fff6c0"), "Y": Color("ffcf5a"), "O": Color("ff9a3c"), "R": Color("c85a1e")}
	var small: Array = FIRE
	var big: Array = FIRE_BIG
	for f in 4:
		add_plain("fx_fire_%d" % f, small, fire)
		add_plain("fx_firex_%d" % f, big, fire)
		small = _sp_turn(small)
		big = _sp_turn(big)
		add_image("fx_blast_%d" % f, _sp_blast(f))
	var star := SPELL_COLORS[4] as Color
	var star_dark := SPELL_DARK[4] as Color
	var twinkle := [[4, 0], [3, 2], [2, 3], [3, 2]]
	var twinkle_big := [[6, 0], [5, 3], [3, 4], [5, 3]]
	for f in 4:
		add_image("fx_star_%d" % f, _sp_rays(9, 0, twinkle[f][0], 1, twinkle[f][1], Color.WHITE, star, star_dark))
		add_image("fx_starx_%d" % f, _sp_rays(13, 0, twinkle_big[f][0], 1, twinkle_big[f][1], Color.WHITE, star, star_dark))
	# A star landing, a hit and a pickup's blink: rays that fly apart (white, tinted when drawn).
	var burst := [[0, 4, 1, 2], [2, 6, 2, 4], [5, 8, 4, 6], [8, 9, 6, 7]]
	for f in burst.size():
		add_image("fx_burst_%d" % f, _sp_rays(19, burst[f][0], burst[f][1], burst[f][2], burst[f][3], Color.WHITE, Color.WHITE,
			Color(1, 1, 1, 0.6)))
	var spark := [[0, 2, 1, 0], [1, 3, 1, 1], [3, 3, 2, 2]]
	for f in spark.size():
		add_image("fx_spark_%d" % f, _sp_rays(7, spark[f][0], spark[f][1], spark[f][2], spark[f][3], Color.WHITE, Color.WHITE,
			Color(1, 1, 1, 0.6)))
	var puff := [[1.2, 2.0, 2.3], [2.4, 2.2, 2.4], [3.6, 1.9, 0.0], [4.4, 1.3, 0.0], [5.0, 0.7, 0.0]]
	for f in puff.size():
		add_image("fx_puff_%d" % f, _sp_puff(13, puff[f][0], puff[f][1], puff[f][2]))
	add_plain("fx_mark", STAR_MARK, {"W": Color.WHITE, "M": star, "m": star_dark})
	add_plain("fx_orb", ORB, {"W": Color.WHITE, "T": Color("d8fff6"), "t": ORBIT_COLOR})
	for i in Occult.RUNES.size():
		var img := Image.create(5, 7, false, Image.FORMAT_RGBA8)
		var seg: Array = Occult.RUNES[i]
		for k in range(0, seg.size(), 4):
			for p: Vector2i in _sp_line(Vector2i(seg[k], seg[k + 1]), Vector2i(seg[k + 2], seg[k + 3])):
				img.set_pixelv(p, Color.WHITE)
		add_image("fx_rune_%d" % i, img)
	for w in STAFF_HEADS.size():
		var c: Dictionary = PLAYER_COLORS[w]
		add_plain("fx_staff_%d" % w, STAFF_HEADS[w], {"K": OUTLINE, "W": Color.WHITE, "L": c.fx, "R": c.robe})
	var danger := {"K": INK, "R": Color("c0263a"), "r": Color("7a1226"), "o": Color("ff9a3c"), "y": Color("ffcf5a")}
	for f in 2:
		add_plain("fx_eorb_%d" % f, ENEMY_ORB[f], danger)
		add_plain("fx_eskull_%d" % f, ENEMY_SKULL[f], danger)


## A soft disc for glows, in flat rings so it stays pixel art: white, tinted and faded when drawn.
static func _sp_glow(d: int) -> Image:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	var bands := clampi(d / 5, 3, 7)
	for y in d:
		for x in d:
			var k := 1.0 - Vector2(x - c, y - c).length() / (d * 0.5)
			if k <= 0.0:
				continue
			var level := ceilf(k * bands) / bands
			img.set_pixel(x, y, Color(1, 1, 1, level * level))
	return img


## The ring on the floor under a wizard: a bright rim, a faint fill.
static func _sp_oval(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			if not _sp_in_oval(x, y, w, h):
				continue
			var inner := _sp_in_oval(x - 1, y, w, h) and _sp_in_oval(x + 1, y, w, h) and _sp_in_oval(x, y - 1, w, h) \
				and _sp_in_oval(x, y + 1, w, h)
			img.set_pixel(x, y, Color(1, 1, 1, 0.16 if inner else 1.0))
	return img


static func _sp_in_oval(x: int, y: int, w: int, h: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return Vector2((x + 0.5) / w * 2.0 - 1.0, (y + 0.5) / h * 2.0 - 1.0).length_squared() <= 1.0


## A comet flying along `dir`, its head in the middle of the picture: the tail is as wide as the head for a pixel
## or two, then one pixel wide, and fades. `nose` > 0 gives it a point that far ahead of the head (a lance); with
## none the head is round.
static func _sp_comet(dir: Vector2, length: int, width: float, nose: float = 0.0) -> Image:
	var half := length + 2
	var size := half * 2 + 1
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var q := Vector2(x - half, y - half)
			var along := -q.dot(dir)
			var across := absf(q.x * dir.y - q.y * dir.x)
			var a := 0.0
			if along < 0.0:
				if nose <= 0.0:
					a = 1.0 if q.length() <= width * 0.5 + 0.2 else 0.0
				elif -along <= nose and across <= width * 0.5 * (1.0 + along / nose) + 0.45:
					a = 1.0
			elif along <= length:
				var k := 1.0 - along / float(length)
				if across <= width * 0.5 * k * k * k + 0.45:
					a = 1.0 if k > 0.7 else (0.8 if k > 0.45 else (0.55 if k > 0.2 else 0.3))
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


## Frame `f` of a fireball's blast, in fire colours: a white-hot ball, a bigger one with a ragged edge, a hollow
## ring of flame, and the ring broken into licks.
static func _sp_blast(f: int) -> Image:
	var size := 33
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	# Per frame: the outer radius, the radius of the hole, how far out it is white-hot, how far out yellow.
	var shape: Array = [[6.0, 0.0, 3.5, 5.0], [10.0, 0.0, 4.5, 7.5], [13.0, 5.5, 0.0, 9.0], [15.0, 10.5, 0.0, 0.0]][f]
	for y in size:
		for x in size:
			var q := Vector2(x - size / 2, y - size / 2)
			var r := q.length()
			var a := q.angle()
			# Seven flames round the edge; in the last frame the gaps between them are open.
			var edge: float = shape[0] + (1.5 * sin(a * 7.0 + f * 1.3) if f > 0 else 0.0)
			var hole: float = shape[1] + (sin(a * 5.0 + 0.7) if f > 1 else 0.0)
			if r > edge or r < hole or (f == 3 and sin(a * 7.0 + 2.0) < -0.1):
				continue
			var col := Color("c85a1e")
			if r <= float(shape[2]):
				col = Color("fff6c0")
			elif r <= float(shape[3]):
				col = Color("ffcf5a")
			elif f < 2 or r <= edge - 1.5:
				col = Color("ff9a3c")
			img.set_pixel(x, y, col)
	return img


## A thin shard of ice flying along `dir`: a white point, a dim tail, a little wider in the middle.
static func _sp_shard(dir: Vector2, length: int, fat: bool) -> Image:
	var half := length / 2 + 2
	var size := half * 2 + 1
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mid := Vector2(half, half)
	var pts := _sp_line(Vector2i((mid - dir * (length * 0.5)).round()), Vector2i((mid + dir * (length * 0.5)).round()))
	# The pixel beside a line pixel shares an edge with it: a diagonal neighbour turns a slanted shard into a
	# checkerboard.
	var side := Vector2i(0, 1) if absf(dir.x) >= absf(dir.y) else Vector2i(1, 0)
	var ice := SPELL_COLORS[2] as Color
	var dark := SPELL_DARK[2] as Color
	for i in pts.size():
		var k := float(i) / (pts.size() - 1)
		if k > 0.3 and k < 0.8:
			img.set_pixelv(pts[i] + side, dark)
			if fat:
				img.set_pixelv(pts[i] - side, ice)
	for i in pts.size():
		var k := float(i) / (pts.size() - 1)
		img.set_pixelv(pts[i], dark if k < 0.25 else (ice if k < 0.7 else Color.WHITE))
	return img


## An enemy's arrow flying along `dir`: blood red with a hot point, inside a dark rim.
static func _sp_arrow(dir: Vector2) -> Image:
	var img := Image.create(13, 13, false, Image.FORMAT_RGBA8)
	var mid := Vector2(6, 6)
	var pts := _sp_line(Vector2i((mid - dir * 4.0).round()), Vector2i((mid + dir * 4.0).round()))
	for i in pts.size():
		var k := float(i) / (pts.size() - 1)
		img.set_pixelv(pts[i], Color("7a1226") if k < 0.25 else (Color("c0263a") if k < 0.7 else
			(Color("ff9a3c") if i < pts.size() - 1 else Color("ffcf5a"))))
	_sp_rim(img, INK)
	return img


## Gives every clear pixel that touches a drawn one the colour `c` (a 1 px outline).
static func _sp_rim(img: Image, c: Color) -> void:
	var src := img.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			if src.get_pixel(x, y).a > 0.0:
				continue
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height() and src.get_pixelv(q).a > 0.0:
					img.set_pixel(x, y, c)
					break


## Rays about the middle of a size x size picture: the four straight ones run from r0 to r1 pixels out, the four
## diagonal ones from d0 to d1 (none when d1 < d0). The middle is `hot`, the rays `col`, their last pixel `tip`.
static func _sp_rays(size: int, r0: int, r1: int, d0: int, d1: int, hot: Color, col: Color, tip: Color) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2i(size / 2, size / 2)
	var straight: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var diagonal: Array[Vector2i] = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
	for k in 4:
		for r in range(d0, d1 + 1):
			img.set_pixelv(c + diagonal[k] * r, tip if r == d1 and d1 > d0 else col)
		for r in range(r0, r1 + 1):
			img.set_pixelv(c + straight[k] * r, hot if r <= 1 and r0 == 0 else (tip if r == r1 and r1 > r0 + 1 else col))
	return img


## A puff of smoke: a heart and five lobes `spread` pixels out, lit from the upper left. White and grey, tinted
## when drawn. The frames move the lobes out and shrink them, so the puff opens into a ring and is gone.
static func _sp_puff(size: int, spread: float, lobe: float, heart: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5 - Vector2(0.5, 0.5)
	for y in size:
		for x in size:
			var q := Vector2(x, y) - c
			var inside := q.length() <= heart
			var shade := q.x + q.y > heart * 0.7
			for i in 5:
				if inside:
					break
				var at := Vector2.from_angle(i * TAU / 5.0 + 0.5) * spread
				var r := lobe * (1.0 if i % 2 == 0 else 0.8)
				if (q - at).length() <= r:
					inside = true
					shade = (q - at).x + (q - at).y > r * 0.5
			if inside:
				img.set_pixel(x, y, Color(0.6, 0.6, 0.6) if shade else Color.WHITE)
	return img


## A map turned a quarter clockwise (maps must be square).
static func _sp_turn(rows: Array) -> Array:
	var n := rows.size()
	var out: Array = []
	for y in n:
		var line := ""
		for x in n:
			line += (rows[n - 1 - x] as String)[y]
		out.append(line)
	return out


## The pixels of a straight line from `a` to `b`, in order.
static func _sp_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := (b - a).abs()
	var s := Vector2i(1 if a.x < b.x else -1, 1 if a.y < b.y else -1)
	var err := d.x - d.y
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		var e2 := err * 2
		if e2 > -d.y:
			err -= d.y
			p.x += s.x
		if e2 < d.x:
			err += d.x
			p.y += s.y
	return out


## Shelf-packs every sprite image into one atlas texture, tallest first. A sprite that does not fit is an error:
## it is reported (`pack_error`, an engine error, and an assert in debug builds) and left out of the atlas.
static func _pack() -> void:
	var keys: Array = _imgs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ha: int = (_imgs[a] as Image).get_height()
		var hb: int = (_imgs[b] as Image).get_height()
		return ha > hb if ha != hb else a < b)
	var w := ATLAS_MIN
	var spots := {}
	var h := _shelve(keys, w, spots)
	while (h > w or spots.size() < keys.size()) and w < ATLAS_MAX:
		w *= 2
		h = _shelve(keys, w, spots)
	var lost: Array = keys.filter(func(k: String) -> bool:
		return not spots.has(k) or (spots[k] as Vector2i).y + (_imgs[k] as Image).get_height() + ATLAS_PAD > ATLAS_MAX)
	if not lost.is_empty():
		var first: Image = _imgs[lost[0]]
		pack_error = "Sprites: %d of %d sprites do not fit the %dx%d atlas; the first is '%s' (%dx%d)" % [lost.size(),
			keys.size(), ATLAS_MAX, ATLAS_MAX, lost[0], first.get_width(), first.get_height()]
		push_error(pack_error)
		for k: String in lost:
			spots.erase(k)
		h = mini(h, ATLAS_MAX)
	var atlas := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for k: String in spots:
		var img: Image = _imgs[k]
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), spots[k])
		_region[k] = Rect2(spots[k], img.get_size())
	for k: String in _alias:
		if _region.has(_alias[k]):
			_region[k] = _region[_alias[k]]
	_atlas_img = atlas
	_atlas = ImageTexture.create_from_image(atlas)
	_imgs.clear()
	assert(pack_error == "", pack_error)

## Places `keys` on shelves `w` wide, filling `spots` (key -> top left). Returns the height used. A sprite wider
## than the atlas gets no spot.
static func _shelve(keys: Array, w: int, spots: Dictionary) -> int:
	spots.clear()
	var x := ATLAS_PAD
	var y := ATLAS_PAD
	var shelf := 0
	for k: String in keys:
		var img: Image = _imgs[k]
		if img.get_width() + ATLAS_PAD * 2 > w:
			continue
		if x + img.get_width() + ATLAS_PAD > w:
			x = ATLAS_PAD
			y += shelf + ATLAS_PAD
			shelf = 0
		spots[k] = Vector2i(x, y)
		x += img.get_width() + ATLAS_PAD
		shelf = maxi(shelf, img.get_height())
	return y + shelf + ATLAS_PAD

static func _add(key: String, rows: Array, pal: Dictionary) -> void:
	if _atlas != null:
		push_error("Sprites: '%s' added after the atlas was packed" % key)
	var w := 0
	for r in rows:
		w = maxi(w, (r as String).length())
	var h := rows.size()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var white := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var unknown := ""
	for y in h:
		var row: String = rows[y]
		if row.length() != w:
			problems.append("%s: row %d is %d wide, the map is %d" % [key, y, row.length(), w])
		for x in row.length():
			var ch := row[x]
			if ch == ".":
				continue
			if not pal.has(ch):
				if not unknown.contains(ch):
					unknown += ch
				continue
			img.set_pixel(x, y, pal[ch])
			white.set_pixel(x, y, Color.WHITE)
	if unknown != "":
		problems.append("%s: no colour for the letters '%s'" % [key, unknown])
	_imgs[key] = img
	_imgs[key + "!"] = white

## A sprite from an ASCII map with no white twin (magic, glows, marks on the floor: things that are never hit).
static func add_plain(key: String, rows: Array, pal: Dictionary) -> void:
	_add(key, rows, pal)
	_imgs.erase(key + "!")

## A sprite from a ready image, with no white twin.
static func add_image(key: String, img: Image) -> void:
	if _atlas != null:
		push_error("Sprites: '%s' added after the atlas was packed" % key)
	_imgs[key] = img

## A halo for the sprite `key` as `key + "~"`, `pad` pixels bigger on every side: a white rim on the pixels just
## outside the sprite and a dark line outside that (4-neighbour, so its corners stay round). Drawn tinted under
## the sprite, the white takes the tint and the dark stays dark. Call before the atlas is packed.
static func add_halo(key: String, pad: int) -> void:
	var src: Image = _imgs[key]
	var w := src.get_width() + pad * 2
	var h := src.get_height() + pad * 2
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in src.get_height():
		for x in src.get_width():
			if src.get_pixel(x, y).a > 0.0:
				solid[(y + pad) * w + x + pad] = 1
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rims: Array[Color] = [Color.WHITE, Color(0.04, 0.03, 0.09, 0.9)]
	for ring in 2:
		var grown := solid.duplicate()
		for y in h:
			for x in w:
				if solid[y * w + x] != 0:
					continue
				var near := (x > 0 and solid[y * w + x - 1] != 0) or (x < w - 1 and solid[y * w + x + 1] != 0) \
					or (y > 0 and solid[(y - 1) * w + x] != 0) or (y < h - 1 and solid[(y + 1) * w + x] != 0)
				if near:
					grown[y * w + x] = 1
					img.set_pixel(x, y, rims[ring])
		solid = grown
	_imgs[key + "~"] = img

## Makes `key` another name for the sprite `target` (and for its white twin). Call before the atlas is packed.
static func alias(key: String, target: String) -> void:
	_alias[key] = target
	_alias[key + "!"] = target + "!"

static func has(key: String) -> bool:
	return _region.has(key)

## Every sprite key, white twins left out, sorted.
static func keys() -> Array:
	var out: Array = _region.keys().filter(func(k: String) -> bool: return not k.ends_with("!"))
	out.sort()
	return out

## The atlas, and a sprite's place in it: for drawing loops that would rather not look a key up for every item.
static func atlas() -> Texture2D:
	return _atlas

static func region(key: String) -> Rect2:
	return _region.get(key, Rect2())

## The places of `<prefix>_0` .. `<prefix>_<n - 1>` (an animation's frames, or a shot's sixteen directions), looked
## up once and kept. Draw them with `draw_mid_r`.
static func strip(prefix: String, n: int) -> Array:
	if not _strips.has(prefix):
		var out: Array = []
		for i in n:
			out.append(_region.get("%s_%d" % [prefix, i], Rect2()))
		_strips[prefix] = out
	else:
		assert((_strips[prefix] as Array).size() == n)
	return _strips[prefix]

## Which of the DIRS plotted directions is nearest to `v`.
static func dir16(v: Vector2) -> int:
	return posmod(roundi(v.angle() / (TAU / DIRS)), DIRS)

## A sprite's pixels (a copy), for tools that build pictures without a display.
static func image(key: String) -> Image:
	var r: Rect2 = _region.get(key, Rect2())
	if r.size == Vector2.ZERO:
		return null
	return _atlas_img.get_region(Rect2i(r))

## A sprite as a texture of its own (a view into the atlas), for code that draws with draw_texture_rect.
static func get_tex(key: String, flash: bool = false) -> Texture2D:
	var k := key + "!" if flash else key
	if not _tex.has(k):
		if not _region.has(k):
			return null
		var t := AtlasTexture.new()
		t.atlas = _atlas
		t.region = _region[k]
		_tex[k] = t
	return _tex[k]

## Draws a sprite centred on its feet point (bottom-centre), pixel-snapped.
static func draw_at(ci: CanvasItem, key: String, feet: Vector2, flip: bool = false,
		flash: bool = false, modulate: Color = Color.WHITE, scale: float = 1.0) -> void:
	var src: Rect2 = _region.get(key + "!" if flash else key, Rect2())
	if src.size == Vector2.ZERO:
		return
	var sz := src.size * scale
	var p := (feet - Vector2(sz.x / 2.0, sz.y)).round()
	# A negative width mirrors the sprite without a transform change, which would split the batch.
	# A negative width mirrors the sprite in place: the position stays the top-left corner.
	var dst := Rect2(p.x, p.y, -sz.x, sz.y) if flip else Rect2(p, sz)
	ci.draw_texture_rect_region(_atlas, dst, src, modulate, false, false)

## Draws a sprite with its middle on `at`, pixel-snapped: shots, glows, sparks and marks on the floor.
static func draw_mid(ci: CanvasItem, key: String, at: Vector2, modulate: Color = Color.WHITE) -> void:
	var src: Rect2 = _region.get(key, Rect2())
	if src.size == Vector2.ZERO:
		return
	ci.draw_texture_rect_region(_atlas, Rect2((at - src.size * 0.5).round(), src.size), src, modulate, false, false)

## The same from a place in the atlas (see `strip` and `region`): no key to look up.
static func draw_mid_r(ci: CanvasItem, src: Rect2, at: Vector2, modulate: Color = Color.WHITE) -> void:
	ci.draw_texture_rect_region(_atlas, Rect2((at - src.size * 0.5).round(), src.size), src, modulate, false, false)

## A soft disc of light about `radius` pixels round, in the colour `c`. On an additive layer it glows.
static func glow(ci: CanvasItem, at: Vector2, radius: float, c: Color) -> void:
	var i := 0
	while i < GLOW_SIZES.size() - 1 and GLOW_SIZES[i] < radius * 2.0:
		i += 1
	draw_mid_r(ci, strip("fx_glow", GLOW_SIZES.size())[i], at, c)

## A filled rectangle that batches with the sprites.
static func rect(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_texture_rect_region(_atlas, r, _px, c, false, false)

## A 1 px line from `a` to `b` in whole pixels, one rectangle per run, batching with the sprites. `grow` fattens it
## by that many pixels on every side (an outline under a line: grow 1, then the line itself).
static func line(ci: CanvasItem, a: Vector2, b: Vector2, c: Color, grow: int = 0) -> void:
	var p := Vector2i(a.floor())
	var q := Vector2i(b.floor())
	var d := (q - p).abs()
	var s := Vector2i(1 if p.x < q.x else -1, 1 if p.y < q.y else -1)
	var side := 1 + grow * 2
	if d.x >= d.y:
		var err := d.x / 2
		var x0 := p.x
		while true:
			var last := p.x == q.x
			err -= d.y
			if last or err < 0:
				ci.draw_texture_rect_region(_atlas, Rect2(mini(x0, p.x) - grow, p.y - grow, absi(p.x - x0) + side, side),
					_px, c, false, false)
				if last:
					return
				p.y += s.y
				err += d.x
				x0 = p.x + s.x
			p.x += s.x
	else:
		var err := d.y / 2
		var y0 := p.y
		while true:
			var last := p.y == q.y
			err -= d.x
			if last or err < 0:
				ci.draw_texture_rect_region(_atlas, Rect2(p.x - grow, mini(y0, p.y) - grow, side, absi(p.y - y0) + side),
					_px, c, false, false)
				if last:
					return
				p.x += s.x
				err += d.y
				y0 = p.y + s.y
			p.y += s.y

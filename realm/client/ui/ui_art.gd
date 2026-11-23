class_name UiArt
extends RefCounted
## The shell's pictures, loaded by file name from realm/client/art/ like the field's (field_art.gd): drop
## `ui_<name>.png` in and it replaces the flat stand-in drawn here. Names in use:
##   ui_title.png          the title's emblem               ui_card_<class>.png   a hero's tarot card face
##   ui_town_<station>.png a station's building in town (bank smith merchants reader trainer gate)
##   ui_item_<slot>_<variant>.png  an item's icon by gear slot and kind (item_weapon_mace, item_head_helm ...), 32 px;
##                         ui_item_<slot>.png is the fallback. Rebuild: tools/char3d/icons.txt
##   ui_stack_<kind>.png   a stack's icon: coin, embers, potion[_0..5], rune[_<stat>], material[_1..6], trophy, page, card, key
##   ui_ground.png         the town's ground tile
## Heroes in town use the field's hero pictures (FieldArt.hero_entry).

const DIR: String = "res://art/"
const SIZE: int = 48

static var _cache: Dictionary = {}
static var misses: Dictionary = {}
static var _heroes: Dictionary = {}


static func has_file(name: String) -> bool:
	return ResourceLoader.exists("%sui_%s.png" % [DIR, name])


## A picture by name: the file when it is there, else a flat stand-in of `size` px with a rune on it.
static func texture(name: String, size: int = SIZE, tint: Color = Color(0.5, 0.2, 0.2)) -> Texture2D:
	var key: String = "%s/%d" % [name, size]
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	if has_file(name):
		t = load("%sui_%s.png" % [DIR, name]) as Texture2D
	if t == null:
		misses[name] = true
		t = _stand_in(name, size, tint)
	_cache[key] = t
	return t


static func _stand_in(name: String, size: int, tint: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h: int = name.hash()
	var base: Color = tint
	if tint == Color(0.5, 0.2, 0.2):
		base = Color.from_hsv(float(h & 0xFF) / 255.0, 0.35, 0.42)
	img.fill(base.darkened(0.45))
	var m: int = maxi(2, size / 12)
	for x in size:
		for y in size:
			if x < m or y < m or x >= size - m or y >= size - m:
				img.set_pixel(x, y, base.lightened(0.25))
	# A rune from the name, in strokes of whole pixels.
	var r: Array = UiKit.RUNES[absi(h) % UiKit.RUNES.size()]
	for seg in r:
		var s: Array = seg
		var a := Vector2(float(s[0]), float(s[1])) * (size - 4 * m) + Vector2(2 * m, 2 * m)
		var b := Vector2(float(s[2]), float(s[3])) * (size - 4 * m) + Vector2(2 * m, 2 * m)
		var n: int = int(a.distance_to(b)) + 1
		for i in n + 1:
			var p: Vector2 = a.lerp(b, float(i) / maxf(n, 1))
			for dx in 2:
				for dy in 2:
					var px: int = clampi(int(p.x) + dx, 0, size - 1)
					var py: int = clampi(int(p.y) + dy, 0, size - 1)
					img.set_pixel(px, py, base.lightened(0.6))
	return ImageTexture.create_from_image(img)


## An icon for an item: ui_item_<slot>_<variant>.png by its base (a mace, a cleaver), else ui_item_<slot>.png, else
## the flat stand-in. The rarity frame is drawn here behind the picture, not baked into the file.
static func item_icon(gear_slot: int, rarity: int, size: int = 32, base: int = -1) -> Texture2D:
	var sl: int = clampi(gear_slot, 0, 5)
	var slot_name: String = GameNames.SLOTS[sl].to_lower()
	var names: Array[String] = []
	if base >= 0 and base / 100 == sl:
		var variants: Array = GameNames.GEAR_VARIANTS[sl]
		if base % 10 < variants.size():
			names.append("item_%s_%s" % [slot_name, String(variants[base % 10]).to_lower()])
	names.append("item_" + slot_name)
	var col: Color = GameNames.rarity_colour(rarity)
	for n in names:
		if has_file(n):
			return _icon(n, size, col, 0)
	return texture(names[names.size() - 1], size, col.darkened(0.35))


## A picture file drawn at `size` px (Lanczos from the file's 32 px), over a rarity-tinted tile with a 1 px border
## when `frame.a` is not 0; `pips` small gold squares along the bottom (a rune's grade).
static func _icon(name: String, size: int, frame: Color, pips: int) -> Texture2D:
	var key: String = "ico/%s/%d/%s/%d" % [name, size, frame.to_html(), pips]
	if _cache.has(key):
		return _cache[key]
	var img: Image = (load("%sui_%s.png" % [DIR, name]) as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	if frame.a > 0.0:
		var bg := Image.create(size, size, false, Image.FORMAT_RGBA8)
		bg.fill(frame.darkened(0.7))
		for i in size:
			for e in [0, size - 1]:
				bg.set_pixel(i, e, frame)
				bg.set_pixel(e, i, frame)
		bg.blend_rect(img, Rect2i(0, 0, size, size), Vector2i.ZERO)
		img = bg
	for i in pips:
		img.fill_rect(Rect2i(2 + i * 4, size - 4, 2, 2), UiKit.GOLD)
	var t: Texture2D = ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


## An icon for a stack kind: by kind where there is a picture (potion, field material, trophy, rune stat; a rune
## carries its grade as pips), else the group's, else the flat stand-in.
static func stack_icon(kind: int, size: int = 32) -> Texture2D:
	var n: String = "coin"
	var specific: String = ""
	var pips: int = 0
	var col: Color = UiKit.GOLD_DIM
	if kind >= 100 and kind < 200:
		n = "potion"
		specific = "potion_%d" % (kind - 100)
		col = Color(0.5, 0.15, 0.2)
	elif kind >= 1000 and kind < 2000:
		n = "embers" if kind == 1000 else "material"
		if kind >= 1001 and kind <= 1006:
			specific = "material_%d" % (kind - 1000)
		elif kind >= 1010 and kind < 1018:
			n = "trophy"
		col = Color(0.7, 0.3, 0.1)
	elif kind >= 2000 and kind < 3000:
		n = "rune"
		var stat: int = clampi((kind - 2000) / 10, 0, 5)
		specific = "rune_" + String(["might", "focus", "swift", "vigor", "ward", "fortune"][stat])
		pips = clampi((kind - 2000) % 10, 0, 3)
		col = Color(0.3, 0.4, 0.6)
	elif kind >= 3000 and kind < 4000:
		n = "key"
	elif kind >= 4000 and kind < 5000:
		n = "page"
		col = Color(0.55, 0.5, 0.35)
	elif kind >= 5000:
		n = "card"
		col = Color(0.45, 0.25, 0.5)
	for name in [specific, n]:
		if not name.is_empty() and has_file("stack_" + name):
			return _icon("stack_" + name, size, Color(0, 0, 0, 0), pips)
	return texture("stack_" + n, size, col)


## A hero's picture (the field's art by class and race): [texture, region of the first frame].
## Kept: a texture loaded and dropped inside a frame is drawn white, so the entry stays held here.
static func hero_picture(cls: int, race: int) -> Array:
	var key: int = clampi(cls, 0, 5) * 4 + clampi(race, 0, 3)
	if not _heroes.has(key):
		var e: Dictionary = FieldArt.hero_entry(clampi(cls, 0, 5), clampi(race, 0, 3))
		var tex: Texture2D = e["tex"]
		var frames: int = maxi(int(e["anim"]), 1)
		_heroes[key] = [tex, Rect2(0, 0, tex.get_width() / float(frames), tex.get_height())]
	return _heroes[key]


## Draws a hero picture centred at `at`, fitted into `box` px, tinted by the look's palette.
static func draw_hero(ci: CanvasItem, cls: int, race: int, at: Vector2, box: float, look: int = 0, flip: bool = false) -> void:
	var p: Array = hero_picture(cls, race)
	var tex: Texture2D = p[0]
	var region: Rect2 = p[1]
	var k: float = box / maxf(region.size.x, region.size.y)
	var sz: Vector2 = region.size * k
	var dst := Rect2(at - sz / 2.0, sz)
	var col: Color = GameNames.LOOK_PALETTES[GameNames.look_palette(look)]
	if flip:
		ci.draw_set_transform(Vector2(at.x * 2.0, 0), 0.0, Vector2(-1, 1))
		ci.draw_texture_rect_region(tex, dst, region, col)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_texture_rect_region(tex, dst, region, col)
	var mark: int = GameNames.look_mark(look)
	if mark == 1:
		ci.draw_line(at + Vector2(-0.12, -0.28) * box, at + Vector2(0.0, -0.1) * box, UiKit.BLOOD_BRIGHT, 1.5)
	elif mark == 2:
		UiKit.rune(ci, at + Vector2(-0.1, -0.5) * box, 2, box * 0.2, UiKit.GOLD, 1.0)
	elif mark == 3:
		var y: float = at.y - sz.y / 2.0
		ci.draw_polyline(PackedVector2Array([Vector2(at.x - 0.16 * box, y + 3), Vector2(at.x - 0.1 * box, y - 3), Vector2(at.x, y + 2), Vector2(at.x + 0.1 * box, y - 3), Vector2(at.x + 0.16 * box, y + 3)]), UiKit.GOLD, 1.5)

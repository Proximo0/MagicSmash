class_name Art
extends RefCounted
## The owner's painted pictures: monster cards, tarot cards, hero and character portraits, figures (`sprites`), `icons` and menu `scenes`. One loader for all of
## them. A picture is looked for in three places, the first hit wins: an `art/` folder beside the executable, then
## `user://art/`, then `res://assets/art/`, each with the same sub-paths (docs/art_dropin.md). The game reduces a
## picture once to the exact pixel size a screen needs (Lanczos) and draws it 1:1, never scaled at draw time.
## A picture that is not there gives null, and callers draw their own art instead.

const GROUPS: Array[String] = ["cards/monsters", "cards/tarot", "portraits/heroes", "portraits/characters", "sprites", "icons", "scenes"]
const HERO_RACES: Array[String] = ["human", "elf", "dwarf", "orc"]
const HERO_CLASSES: Array[String] = ["archer", "priest", "paladin", "knight", "mage"]
const CHARACTERS: Array[String] = ["shopkeeper", "card_reader", "bone_chandelier", "ghost_writer", "archlich", "apprentice"]
const MAJOR_ARCANA: Array[String] = ["THE FOOL", "THE MAGICIAN", "THE HIGH PRIESTESS", "THE EMPRESS", "THE EMPEROR",
	"THE HIEROPHANT", "THE LOVERS", "THE CHARIOT", "STRENGTH", "THE HERMIT", "WHEEL OF FORTUNE", "JUSTICE",
	"THE HANGED MAN", "DEATH", "TEMPERANCE", "THE DEVIL", "THE TOWER", "THE STAR", "THE MOON", "THE SUN",
	"JUDGEMENT", "THE WORLD"]
## Cards of enemies the game does not have yet: the files are kept, nothing shows them.
const NEW_MONSTERS: Array[String] = ["cinderling", "ten_of_swords"]
## Backdrops of the menus (480 x 270): the hero builder, the hero sheet, the lobby, the card album, the Book of Deeds.
## `shop`, `victory` and `defeat` are named for the shop and results screens (their owners wire them).
const SCENES: Array[String] = ["builder", "sheet", "lobby", "album", "deeds", "shop", "victory", "defeat"]
const SUITS: Array[String] = ["suit_cups", "suit_swords", "suit_wands", "suit_pentacles"]
const RES_ROOT := "res://assets/art/"
const USER_ROOT := "user://art/"

## A folder searched before every other (set by `--art=<dir>` in the autotest harness); "" for none.
static var drop_root := ""

## Where each picture was found: "group/key" -> path, or "" for none.
static var _paths := {}
## Reduced pictures: "group/key@WxH" -> Texture2D (or null), and the same pictures as images (for exact resizes).
static var _tex := {}
static var _img := {}


## The picture for `key` in `group`, or null when no file exists. With a `size` it is reduced once (Lanczos) to
## fit inside it, aspect kept, and never enlarged; ask for the size you will draw it at and draw it 1:1.
static func tex(group: String, key: String, size: Vector2i = Vector2i.ZERO) -> Texture2D:
	var ck := "%s/%s@%d,%d" % [group, key, size.x, size.y]
	if _tex.has(ck):
		return _tex[ck]
	var t: Texture2D = null
	var img := _fitted(group, key, size, ck)
	if img:
		t = ImageTexture.create_from_image(img)
	_tex[ck] = t
	return t


## True when a file exists for `key` in `group` (it does not load it).
static func has(group: String, key: String) -> bool:
	return not find(group, key).is_empty()


## The path of the file for `key`, looking beside the executable, then in user://, then in the project; "" if none.
static func find(group: String, key: String) -> String:
	var id := group + "/" + key
	if _paths.has(id):
		return _paths[id]
	var found := ""
	for root: String in roots():
		var p := "%s%s/%s.png" % [root, group, key]
		if root == RES_ROOT:
			# In an exported build the project's pictures are imported: the raw file is not in the pack but the
			# resource is, and ResourceLoader knows it.
			if FileAccess.file_exists(p) or ResourceLoader.exists(p):
				found = p
				break
		elif FileAccess.file_exists(p):
			found = p
			break
	_paths[id] = found
	return found


## The folders pictures are looked for in, best first.
static func roots() -> Array[String]:
	var exe := OS.get_executable_path().get_base_dir().path_join("art") + "/"
	if not drop_root.is_empty():
		return [drop_root, exe, USER_ROOT, RES_ROOT]
	return [exe, USER_ROOT, RES_ROOT]


## Forgets what was found and reduced (a picture dropped in while the game runs shows after this).
static func forget() -> void:
	_paths.clear()
	_tex.clear()
	_img.clear()


## Every (group, key) the game can show, as [group, key] pairs.
static func wanted() -> Array:
	var out: Array = []
	for card: Array in Cards.CARDS:
		out.append(["cards/monsters", card[0]])
	for m: String in NEW_MONSTERS:
		out.append(["cards/monsters", m])
	for title: String in MAJOR_ARCANA:
		out.append(["cards/tarot", slug(title)])
	for s: String in SUITS:
		out.append(["cards/tarot", s])
	out.append(["cards/tarot", "card_back"])
	for race: String in HERO_RACES:
		for cls: String in HERO_CLASSES:
			out.append(["portraits/heroes", "hero_%s_%s" % [race, cls]])
	for c: String in CHARACTERS:
		out.append(["portraits/characters", c])
		out.append(["portraits/characters", c + "_tall"])
	for k: String in Still.names():
		out.append(["sprites", k])
	for k: String in Still.icon_names():
		out.append(["icons", k])
	for k: String in SCENES:
		out.append(["scenes", k])
	return out


## "THE CHARIOT" -> "the_chariot".
static func slug(title: String) -> String:
	return title.to_lower().replace(" ", "_")


## The [group, key] pairs of the PNG files under `root` (one of roots()), whether the game wants them or not.
static func listed(root: String) -> Array:
	var out: Array = []
	for g: String in GROUPS:
		var d := DirAccess.open(root + g)
		if d == null:
			continue
		for f: String in d.get_files():
			if f.ends_with(".png"):
				out.append([g, f.trim_suffix(".png")])
	return out


## The full-size picture, or null. Only tools and tests need this; the game asks for reduced ones.
static func image(group: String, key: String) -> Image:
	var path := find(group, key)
	if path.is_empty():
		return null
	var img: Image = null
	if path.begins_with("res://"):
		# Imported in the project (and the only form an exported build holds): the resource gives the image.
		var t := load(path) as Texture2D if ResourceLoader.exists(path) else null
		if t:
			img = t.get_image()
		if (img == null or img.is_empty()) and FileAccess.file_exists(path):
			img = Image.new() # a picture the importer has not seen yet, or a headless run without pixels
			if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
				img = null
	else:
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Draws the picture inside `r`: fitted to it, centred, 1:1. A card turning over (a rect narrower than the
## picture at that height) squashes the picture sideways, as the turn itself would. False when there is no file.
static func draw(ci: CanvasItem, group: String, key: String, r: Rect2, tint: Color = Color.WHITE) -> bool:
	var size := Vector2i(maxi(int(r.size.x), 1), maxi(int(r.size.y), 1))
	var base := tex(group, key, Vector2i(100000, size.y))
	if base == null:
		return false
	var bw := int(base.get_width())
	if size.x >= bw:
		var fit := tex(group, key, size)
		var at := (r.position + (r.size - fit.get_size()) / 2.0).floor()
		ci.draw_texture(fit, at, tint)
		return true
	var sq := _squashed(group, key, Vector2i(size.x, int(base.get_height())))
	if sq:
		ci.draw_texture(sq, (r.position + Vector2(0, (r.size.y - sq.get_height()) / 2.0)).floor(), tint)
	return true


static func _squashed(group: String, key: String, size: Vector2i) -> Texture2D:
	var ck := "%s/%s@x%d,%d" % [group, key, size.x, size.y]
	if _tex.has(ck):
		return _tex[ck]
	var base: Image = _img.get("%s/%s@%d,%d" % [group, key, 100000, size.y])
	var t: Texture2D = null
	if base:
		var img := base.duplicate() as Image
		img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		t = ImageTexture.create_from_image(img)
	_tex[ck] = t
	return t


static func _fitted(group: String, key: String, size: Vector2i, ck: String) -> Image:
	var src := image(group, key)
	if src == null:
		return null
	var out := src
	if size != Vector2i.ZERO:
		var s := minf(float(size.x) / src.get_width(), float(size.y) / src.get_height())
		if s < 1.0:
			out.fix_alpha_edges()
			out.resize(clampi(roundi(src.get_width() * s), 1, size.x), clampi(roundi(src.get_height() * s), 1, size.y),
				Image.INTERPOLATE_LANCZOS)
	_img[ck] = out
	return out

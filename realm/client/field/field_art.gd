class_name FieldArt
extends RefCounted
## The pictures of the field, loaded from realm/client/art/ by file name, with stand-ins for what is not drawn yet.
##   enemy_<kind>.png      a monster kind: its name with spaces as underscores (enemy_plague_rat.png)
##   hero_<race>_<class>.png   a hero: race human elf dwarf orc, class novice knight mage archer priest paladin
##   <name>_walk.png       four frames side by side for that picture (a strip: 2 texture px per world px)
## A strip wins over the still picture. A monster with neither gets a flat stand-in drawn here from its field,
## its health and its behaviour; a hero with neither borrows the same race's knight.
## An entry is {tex, anim, scale, art}: `art` is "walk", "still" or "stand-in".

const CLASSES: Array[String] = ["novice", "knight", "mage", "archer", "priest", "paladin"]
const RACES: Array[String] = ["human", "elf", "dwarf", "orc"]
const WALK_FRAMES: int = 4
## A walk strip has 2 texture px per world px.
const WALK_SCALE: float = 0.5
## Ground colour of each field's stand-ins: road, wood, marsh, peaks, tower, edge.
const FIELD_COLOURS: Array[Color] = [
	Color(0.62, 0.52, 0.36), Color(0.36, 0.5, 0.34), Color(0.3, 0.52, 0.5),
	Color(0.62, 0.7, 0.8), Color(0.62, 0.4, 0.62), Color(0.72, 0.34, 0.26)]
## Behaviour bits of the core (realm/core tables/kinds.rs).
const B_SWARM: int = 1 << 1
const B_RUNNER: int = 1 << 2
const B_BRUTE: int = 1 << 3
const B_SHIELDED: int = 1 << 4
const B_BURSTER: int = 1 << 5
const B_SPITTER: int = 1 << 7
const B_LOBBER: int = 1 << 8
const B_LEAPER: int = 1 << 9
const B_CASTER: int = (1 << 10) | (1 << 11) | (1 << 12) | (1 << 13)


## The file key of a monster kind: "enemy_" and its name with underscores.
static func kind_key(name: String) -> String:
	return "enemy_" + name.replace(" ", "_")


static func _exists(key: String) -> bool:
	return ResourceLoader.exists("res://art/%s.png" % key)


static func _load(key: String) -> Texture2D:
	return load("res://art/%s.png" % key) as Texture2D


## A picture by key: its strip when there is one, else the still, else null.
static func entry_for(key: String) -> Dictionary:
	if _exists(key + "_walk"):
		return {"tex": _load(key + "_walk"), "anim": WALK_FRAMES, "scale": WALK_SCALE, "art": "walk"}
	if _exists(key):
		return {"tex": _load(key), "anim": 1, "scale": 1.0, "art": "still"}
	return {}


## The 42 monster kinds in the core's order.
static func monster_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in RealmLink.kind_count():
		var info: Dictionary = RealmLink.kind_info(i)
		var e: Dictionary = entry_for(kind_key(String(info["name"])))
		if e.is_empty():
			e = {"tex": stand_in(i, info), "anim": 1, "scale": 1.0, "art": "stand-in"}
		out.append(e)
	return out


## One hero's picture, by class (0..5) and race (0..3).
static func hero_entry(cls: int, race: int) -> Dictionary:
	var key := "hero_%s_%s" % [RACES[race], CLASSES[cls]]
	var e: Dictionary = entry_for(key)
	if e.is_empty():
		e = entry_for("hero_%s_%s" % [RACES[race], CLASSES[1]])
		e["art"] = "stand-in"
	return e


## The 24 hero entries: class * 4 + race (the order RealmLink writes in the player buffer).
static func hero_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in CLASSES.size():
		for r in RACES.size():
			out.append(hero_entry(c, r))
	return out


## How many of each kind of art is in use, for the HUD and the doc: {walk, still, stand-in}.
static func art_summary(entries: Array[Dictionary]) -> Dictionary:
	var d := {"walk": 0, "still": 0, "stand-in": 0}
	for e in entries:
		d[e["art"]] += 1
	return d


## A flat stand-in for a monster kind: a body in its field's colour, its size from its health, and a mark
## for its behaviour (bursters glow orange, spitters and lobbers have an open mouth, runners are lean,
## brutes broad, shielded ones carry a grey plate, casters wear a pale crown).
static func stand_in(kind: int, info: Dictionary) -> Texture2D:
	var health: int = int(info.get("health", 40))
	var beh: int = int(info.get("beh", 0))
	var base: Color = FIELD_COLOURS[clampi(int(info.get("field", 0)), 0, 5)]
	# A little variety inside a field, the same every run.
	var shade: float = 0.8 + 0.1 * float(kind % 4)
	var body: Color = Color(base.r * shade, base.g * shade, base.b * shade)
	var h: int = clampi(int(14.0 + sqrt(float(health)) * 1.2), 14, 32)
	var w: int = int(float(h) * 0.8)
	if beh & B_RUNNER:
		w = int(float(w) * 0.75)
	if beh & B_BRUTE:
		w = int(float(w) * 1.3)
		h = mini(h + 3, 34)
	if beh & B_SWARM:
		h = int(float(h) * 0.7)
		w = int(float(w) * 0.8)
	var img := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	var outline: Color = body.darkened(0.6)
	var cx: float = (w + 1) / 2.0
	var cy: float = (h + 1) / 2.0
	for y in img.get_height():
		for x in img.get_width():
			var dx: float = (x - cx) / (w / 2.0)
			var dy: float = (y - cy) / (h / 2.0)
			var d: float = dx * dx + dy * dy
			if d <= 1.0:
				var lit: float = 1.0 - 0.25 * clampf(dy + 0.3, 0.0, 1.0)
				img.set_pixel(x, y, outline if d > 0.72 else Color(body.r * lit, body.g * lit, body.b * lit))
	var eye_y: int = int(h * 0.32)
	for ex in [int(w * 0.32), int(w * 0.62)]:
		img.set_pixel(ex + 1, eye_y + 1, Color(0.95, 0.9, 0.5))
	if beh & B_BURSTER:
		_blob(img, int(cx), int(cy + h * 0.15), maxi(2, w / 5), Color(1.0, 0.55, 0.15))
	if beh & (B_SPITTER | B_LOBBER):
		_blob(img, int(cx), int(h * 0.62), maxi(1, w / 8), Color(0.12, 0.05, 0.08))
	if beh & B_SHIELDED:
		for y in range(int(h * 0.25), int(h * 0.85)):
			img.set_pixel(maxi(1, int(w * 0.12)), y, Color(0.75, 0.78, 0.85))
			img.set_pixel(maxi(1, int(w * 0.12)) + 1, y, Color(0.55, 0.58, 0.65))
	if beh & B_LEAPER:
		img.set_pixel(1, h, outline)
		img.set_pixel(w, h, outline)
	if beh & B_CASTER:
		for x in range(int(w * 0.3), int(w * 0.7)):
			img.set_pixel(x + 1, 1, Color(0.9, 0.9, 1.0))
	return ImageTexture.create_from_image(img)


static func _blob(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				img.set_pixel(x, y, c)

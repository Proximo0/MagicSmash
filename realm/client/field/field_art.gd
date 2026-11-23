class_name FieldArt
extends RefCounted
## The pictures of the field, loaded from realm/client/art/ by file name, with stand-ins for what is not drawn yet.
##   enemy_<kind>.png      a monster kind: its name with spaces as underscores (enemy_plague_rat.png)
##   hero_<race>_<class>.png   a hero: race human elf dwarf orc, class novice knight mage archer priest paladin
##   <name>_walk.png       four frames side by side for that picture (a strip: 2 texture px per world px)
##   <name>_walk.json      optional, next to the strip: {"frames": 8, "fps": 16, "scale": 0.25}; defaults 4, 8, 0.5
##   <name>_atk.png, <name>_hit.png, <name>_die.png: optional, same scale as the walk strip; the entry gets `atk`,
##   `hit`, `die` textures when they exist (FieldAnim plays them, else draws code fallbacks). Their frame counts
##   default to 3, 1, 3 and come from the walk sidecar's "atk_frames", "hit_frames", "die_frames" (the entry's
##   `atk_n`, `hit_n`, `die_n`).
##   The 24 heroes are tools/char3d/import_heroes.py output: 8 walk frames at 12 fps, 8 attack, 4 hit, 8 death
##   frames, one crop per hero (centre of the frame = body centre, bottom edge = feet), scale 0.4667 so a human
##   stands 28 world px tall as the old human knight did.
## A strip wins over the still picture. A monster with neither gets a flat stand-in drawn here from its field,
## its health and its behaviour; a hero with neither borrows the same race's knight.
## An entry is {tex, anim (frames), fps, scale, art}: `art` is "walk", "still" or "stand-in".

const CLASSES: Array[String] = ["novice", "knight", "mage", "archer", "priest", "paladin"]
const RACES: Array[String] = ["human", "elf", "dwarf", "orc"]
const WALK_FRAMES: int = 4
## A walk strip has 2 texture px per world px.
const WALK_SCALE: float = 0.5
## A walk strip steps this many frames a second unless its sidecar says otherwise.
const WALK_FPS: float = 8.0
## Frames of the atk, hit and die strips unless the sidecar says otherwise.
const STRIP_FRAMES: Dictionary = {"atk": 3, "hit": 1, "die": 3}
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


static func _exists(key: String, dir: String = "res://art") -> bool:
	return ResourceLoader.exists("%s/%s.png" % [dir, key])


static func _load(key: String, dir: String = "res://art") -> Texture2D:
	return load("%s/%s.png" % [dir, key]) as Texture2D


## The strip's frames, fps and scale: the sidecar <key>_walk.json when there is one, else 4, 8 and 0.5. A frame
## count that does not divide the strip's width falls back to 4.
static func walk_params(key: String, dir: String, width: int) -> Dictionary:
	var p: Dictionary = {"anim": WALK_FRAMES, "fps": WALK_FPS, "scale": WALK_SCALE}
	var path: String = "%s/%s_walk.json" % [dir, key]
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			p["anim"] = maxi(int(d.get("frames", WALK_FRAMES)), 1)
			p["fps"] = maxf(float(d.get("fps", WALK_FPS)), 0.1)
			p["scale"] = maxf(float(d.get("scale", WALK_SCALE)), 0.01)
	if width % int(p["anim"]) != 0:
		p["anim"] = WALK_FRAMES
	return p


## A picture by key: its strip when there is one, else the still, else null. `dir` is where the files are.
static func entry_for(key: String, dir: String = "res://art") -> Dictionary:
	var e: Dictionary = {}
	if _exists(key + "_walk", dir):
		var tex: Texture2D = _load(key + "_walk", dir)
		var p: Dictionary = walk_params(key, dir, tex.get_width())
		e = {"tex": tex, "anim": p["anim"], "fps": p["fps"], "scale": p["scale"], "art": "walk"}
	elif _exists(key, dir):
		e = {"tex": _load(key, dir), "anim": 1, "fps": WALK_FPS, "scale": 1.0, "art": "still"}
	else:
		return e
	var side: Dictionary = {}
	var path: String = "%s/%s_walk.json" % [dir, key]
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			side = d
	for suffix in ["atk", "hit", "die"]:
		if _exists(key + "_" + suffix, dir):
			var t: Texture2D = _load(key + "_" + suffix, dir)
			e[suffix] = t
			var n: int = maxi(int(side.get(suffix + "_frames", STRIP_FRAMES[suffix])), 1)
			e[suffix + "_n"] = n if t.get_width() % n == 0 else int(STRIP_FRAMES[suffix])
	return e


## The 42 monster kinds in the core's order.
static func monster_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in RealmLink.kind_count():
		var info: Dictionary = RealmLink.kind_info(i)
		var e: Dictionary = entry_for(kind_key(String(info["name"])))
		if e.is_empty():
			e = {"tex": stand_in(i, info), "anim": 1, "fps": WALK_FPS, "scale": 1.0, "art": "stand-in"}
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

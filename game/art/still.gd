class_name Still
extends RefCounted
## Figures made from one still picture (`sprites/<name>.png`, facing right) and the other drop-in hooks that go with
## them (icons, scenes). The picture is drawn at its own pixel size with its bottom centre on the figure's ground
## point, mirrored when the figure faces left, and moved by code so that it reads as alive (`motion`). Where there is
## no file every caller keeps its own drawing, pixel for pixel. Names: docs/art_dropin.md.

const GROUP := "sprites"
const ICONS := "icons"
const SCENES := "scenes"

## Walk: the bob's rate (rad/s of the walk cycle) and height (px), the lean forward (rad) and its sway.
const WALK_RATE := 11.0
const WALK_BOB := 2.0
const LEAN_MOVE := 0.1
const LEAN_SWAY := 0.04
## Idle: the breath's rate (rad/s) and how much taller the figure grows at the top of it (a share of its height).
const BREATH_RATE := 2.0
const BREATH := 0.05
## A lean this small is not drawn rotated.
const LEAN_MIN := 0.001
## An elite's tint (the gilded stand-in's look) and the dim a scene gets so that text reads over it.
const ELITE_TINT := Color(1.3, 1.1, 0.6)
const SCENE_DIM := Color(0.45, 0.45, 0.5)
## Where a menu's main frame holds its backdrop (inside the border).
const SCENE_INNER := Rect2(8, 8, 464, 254)
## The seat ring under a hero picture, its alpha.
const RING_ALPHA := 0.6

## The Archlich (the Lich made final) is its own picture.
const ARCHLICH := "enemy_archlich"
## Bestiary types whose names read `boss_<key>` (the act bosses).
const BOSS_TYPES: Array[int] = [Bestiary.CHANDELIER, Bestiary.GHOSTWRITER]

## Which Achievements.RULES kinds show which deed mark (`icons/deed_<mark>`); kinds not listed keep today's mark.
const DEED_MARKS := {
	"win_class": "win", "win_race": "win", "trinity": "win", "seal": "win", "apprentices": "win",
	"boss": "slay", "kills_all": "slay", "fast": "time", "secrets": "secret",
}

## The hub's three pieces and the ground each stands on, as an offset from its spot.
const HUB_LECTERN := "hub_lectern"
const HUB_MIRROR := "hub_mirror"
const HUB_PLINTH := "hub_plinth"
const HUB_GROUND := Vector2(0, 2)
const PLINTH_GROUND := Vector2(0, 3)

static var _flash := {}


## Every figure name the game can show.
static func names() -> Array[String]:
	var out: Array[String] = []
	for c: int in Classes.count():
		out.append("hero_" + Classes.key(c))
	out.append("apprentice")
	out.append_array([HUB_LECTERN, HUB_MIRROR, HUB_PLINTH])
	for t: int in Bestiary.count():
		out.append(enemy_key(t))
	out.append(ARCHLICH)
	return out


## The figure name of a Bestiary type.
static func enemy_key(type: int) -> String:
	var k: String = Bestiary.KINDS[type][0]
	return ("boss_" if BOSS_TYPES.has(type) else "enemy_") + k


## Every icon name the game can show.
static func icon_names() -> Array[String]:
	var out: Array[String] = []
	for i: int in Upgrades.count():
		var n := icon_of(Upgrades.key(i))
		if not n.is_empty():
			out.append(n)
	for c: int in Classes.count():
		out.append("class_" + Classes.key(c))
	for r: int in Races.count():
		out.append("race_" + Races.key(r))
	for m: String in ["win", "slay", "time", "secret"]:
		out.append("deed_" + m)
	return out


## The icon name of an upgrade key (`w_fire` -> `spell_fire`, `e_fire` -> `evo_fire`, `swift` -> `passive_swift`);
## "" for the Minor Arcana (they have no icon).
static func icon_of(key: String) -> String:
	if key.begins_with("w_"):
		return "spell_" + key.substr(2)
	if key.begins_with("e_"):
		return "evo_" + key.substr(2)
	for m: String in ["cups", "pentacles", "swords", "wands"]:
		if key == m:
			return ""
	return "passive_" + key


static func has(name: String) -> bool:
	return not name.is_empty() and Art.has(GROUP, name)


## The picture a hero shows: an apprentice's own, else its class's; "" when neither exists.
static func hero_name(cls: int, ai: bool) -> String:
	if ai and has("apprentice"):
		return "apprentice"
	var n := "hero_" + Classes.key(cls)
	return n if has(n) else ""


## The picture an enemy of a Bestiary type shows; "" when none exists.
static func enemy_name(type: int, final: bool = false) -> String:
	var n := ARCHLICH if final and type == Bestiary.LICH else enemy_key(type)
	return n if has(n) else ""


## The deed mark's icon name for an Achievements.RULES kind, "" for a kind that keeps today's mark.
static func deed_icon(api: String) -> String:
	var rule: Array = Achievements.RULES.get(api, [])
	if rule.is_empty():
		return ""
	var m: String = DEED_MARKS.get(String(rule[0]), "")
	return "" if m.is_empty() else "deed_" + m


## How a figure moves: {off: Vector2 (px, up is negative), lean: float (rad, positive tips toward its right),
## squash: Vector2 (scale about the bottom centre)} from the time, whether it moves and its facing (1 right, -1
## left). Moving: a bob and a lean forward that sways. Standing: a slow breath that stretches it a little.
static func motion(t: float, moving: bool, facing: int) -> Dictionary:
	var f := -1.0 if facing < 0 else 1.0
	if moving:
		var s := sin(t * WALK_RATE)
		return {"off": Vector2(0, -absf(s) * WALK_BOB), "lean": f * (LEAN_MOVE + LEAN_SWAY * s), "squash": Vector2.ONE}
	var b := 0.5 + 0.5 * sin(t * BREATH_RATE)
	return {"off": Vector2.ZERO, "lean": 0.0, "squash": Vector2(1.0 - BREATH * 0.5 * b, 1.0 + BREATH * b)}


## Draws figure `name`: bottom centre on `feet`, `facing` 1 or -1, moved by `motion`. `flash` draws it as a white
## silhouette (the hit flash). False when there is no picture.
static func draw(ci: CanvasItem, name: String, feet: Vector2, facing: int, t: float, moving: bool,
		tint: Color = Color.WHITE, flash: bool = false) -> bool:
	var tex := Art.tex(GROUP, name)
	if tex == null:
		return false
	if flash:
		tex = _white(name, tex)
	var m := motion(t, moving, facing)
	var sq: Vector2 = m.squash
	var w := roundf(tex.get_width() * sq.x)
	var h := roundf(tex.get_height() * sq.y)
	var base := (feet + (m.off as Vector2)).round()
	var lean: float = m.lean
	var at := Vector2(-floorf(w / 2.0), -h)
	var src := Rect2(Vector2.ZERO, tex.get_size())
	var dst := Rect2(at, Vector2(w, h))
	if facing < 0:
		dst = Rect2(Vector2(at.x + w, at.y), Vector2(-w, h))
	if absf(lean) < LEAN_MIN:
		dst.position += base
		ci.draw_texture_rect_region(tex, dst, src, tint)
		return true
	ci.draw_set_transform(base, lean, Vector2.ONE)
	ci.draw_texture_rect_region(tex, dst, src, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## Draws a still object (a hub piece) unmoved at its own size, bottom centre on `ground`; false when no picture.
static func draw_static(ci: CanvasItem, name: String, ground: Vector2) -> bool:
	var tex := Art.tex(GROUP, name)
	if tex == null:
		return false
	ci.draw_texture(tex, (ground - Vector2(floorf(tex.get_width() / 2.0), tex.get_height())).round())
	return true


## A white copy of a picture with its own outline (alpha) kept, for the hit flash.
static func _white(name: String, tex: Texture2D) -> Texture2D:
	if _flash.has(name):
		return _flash[name]
	var img := tex.get_image()
	var out: Texture2D = tex
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y: int in img.get_height():
			for x: int in img.get_width():
				img.set_pixel(x, y, Color(1, 1, 1, img.get_pixel(x, y).a))
		out = ImageTexture.create_from_image(img)
	_flash[name] = out
	return out


## An icon reduced to fit `size` x `size` (never enlarged), or null when there is no file.
static func icon(name: String, size: int) -> Texture2D:
	if name.is_empty():
		return null
	return Art.tex(ICONS, name, Vector2i(size, size))


## Draws an icon inside `r` (centred, 1:1 at its reduced size); false when there is no file.
static func draw_icon(ci: CanvasItem, name: String, r: Rect2, tint: Color = Color.WHITE) -> bool:
	var tex := icon(name, maxi(int(minf(r.size.x, r.size.y)), 1))
	if tex == null:
		return false
	ci.draw_texture(tex, (r.position + (r.size - tex.get_size()) / 2.0).floor(), tint)
	return true


## A backdrop (480 x 270) dimmed by SCENE_DIM; false when there is no file. With `inner` only that part of it is
## drawn (over a frame's opaque fill, inside its border).
static func draw_scene(ci: CanvasItem, name: String, inner: Rect2 = Rect2(0, 0, 480, 270)) -> bool:
	var tex := Art.tex(SCENES, name, Vector2i(480, 270))
	if tex == null:
		return false
	var k := tex.get_size() / Vector2(480, 270)
	ci.draw_texture_rect_region(tex, inner, Rect2(inner.position * k, inner.size * k), SCENE_DIM)
	return true

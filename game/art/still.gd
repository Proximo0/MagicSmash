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

## Class weapons that have a picture of their own (`icons/weapon_<skin>`); a class whose weapon is a plain spell (the
## knight's cleave, the mage's school spell) keeps its `spell_` icon.
const WEAPON_SKINS: Array[String] = ["longbow", "holy_light", "smite"]
## The six hero stats' icons, in Loot.ST_* order (MIGHT FOCUS SWIFT VIGOR WARD, then FORTUNE: the gold stat, GREED).
const STAT_ICONS: Array[String] = ["stat_might", "stat_focus", "stat_swift", "stat_vigor", "stat_ward", "stat_fortune"]
## The apprentice's own class mark, and the difficulty steps' marks below the Seals.
const APPRENTICE_ICON := "class_apprentice"
const STEP_ICONS := {-1: APPRENTICE_ICON, 0: "step_wizard", 1: "step_archmage"}
## The sanctum's crystal mark.
const HUD_ICONS: Array[String] = ["hud_crystal"]

## The hub's three pieces and the ground each stands on, as an offset from its spot.
const HUB_LECTERN := "hub_lectern"
const HUB_MIRROR := "hub_mirror"
const HUB_PLINTH := "hub_plinth"
const HUB_GROUND := Vector2(0, 2)
const PLINTH_GROUND := Vector2(0, 3)

static var _flash := {}
static var _rims := {}
## The rim of a figure lies this many px outside its alpha: the first the seat's colour, the second the dark line.
const RIM_PAD := 2
## A pixel at least this opaque is part of the figure's shape.
const RIM_ALPHA := 0.35


## Every figure name the game can show.
static func names() -> Array[String]:
	var out: Array[String] = []
	for c: int in Classes.count():
		out.append("hero_" + Classes.key(c))
		for r: int in Races.count():
			out.append("hero_%s_%s" % [Races.key(r), Classes.key(c)])
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
	for w: String in WEAPON_SKINS:
		out.append("weapon_" + w)
	for k: int in Classes.skill_count():
		out.append(skill_icon(k))
	out.append_array(STAT_ICONS)
	for lv: int in range(Seals.MIN, Seals.MAX + 1):
		out.append(step_icon(lv))
	for i: int in Loot.count():
		out.append(loot_icon(i))
	out.append_array(HUD_ICONS)
	return out


## The icon name of a class skill (`Classes.SKILLS` index): `skill_<key>` (nova provoke volley sanctuary aegis).
static func skill_icon(s: int) -> String:
	return "skill_" + Classes.skill_key(s)


## The icon name of a hero stat (a Loot.ST_* index); "" for an index that is not one.
static func stat_icon(st: int) -> String:
	return STAT_ICONS[st] if st >= 0 and st < STAT_ICONS.size() else ""


## The icon name of a difficulty step (Seals.MIN to MAX): class_apprentice, step_wizard, step_archmage, seal_1 to seal_8.
static func step_icon(level: int) -> String:
	if level < Seals.MIN or level > Seals.MAX:
		return ""
	return String(STEP_ICONS[level]) if level <= 1 else "seal_%d" % (level - 1)


## The icon name of a chest item (a Loot.ITEMS index): `loot_<key>`; "" for an index that is not one.
static func loot_icon(idx: int) -> String:
	return "loot_" + String(Loot.ITEMS[idx][0]) if idx >= 0 and idx < Loot.count() else ""


## The class weapon's own icon name for spell row `spell` in the hands of class `cls` (`weapon_longbow`...); "" when
## that class's weapon is a plain spell.
static func weapon_icon(cls: int, spell: int) -> String:
	var sk := Classes.weapon_skin(cls, spell)
	return "weapon_" + sk if WEAPON_SKINS.has(sk) else ""


## A hero's weapon picture reduced to `size`: its own (`weapon_<skin>`), else its spell's (`spell_<key>`), else null.
static func weapon_tex(cls: int, spell: int, size: int) -> Texture2D:
	var tex := icon(weapon_icon(cls, spell), size)
	if tex != null:
		return tex
	var name := icon_of(Upgrades.key(Upgrades.weapon_entry(spell)))
	return icon(name, size)



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


## The picture a hero shows: an apprentice's own, else her race and class's (`hero_<race>_<class>`, when `race` is
## given), else her class's; "" when none exists.
static func hero_name(cls: int, ai: bool, race: int = -1) -> String:
	if ai and has("apprentice"):
		return "apprentice"
	if race >= 0 and race < Races.count():
		var rn := "hero_%s_%s" % [Races.key(race), Classes.key(cls)]
		if has(rn):
			return rn
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
	_put(ci, tex, tex.get_size(), 0, feet, facing, t, moving, tint)
	return true


## Draws the rim of figure `name` with the same place, mirror, squash and lean as `draw`: a 1 px line in `rim` round
## her alpha and a 1 px line in `dark` outside it. Call it before `draw`. False when there is no picture.
static func draw_rim(ci: CanvasItem, name: String, feet: Vector2, facing: int, t: float, moving: bool, rim: Color,
		dark: Color) -> bool:
	var tex := Art.tex(GROUP, name)
	if tex == null:
		return false
	var pair := rim_textures(name, tex)
	_put(ci, pair[1], tex.get_size(), RIM_PAD, feet, facing, t, moving, dark)
	_put(ci, pair[0], tex.get_size(), RIM_PAD, feet, facing, t, moving, rim)
	return true


## Where a figure of `size` px, grown by `pad` px on every side, is drawn around its feet: bottom centre on the feet.
## Facing left its width is negative, and the corner is the same: Godot mirrors a rect of negative width in place
## (its position stays the top-left corner), so a corner moved one width over draws her beside her own feet.
static func figure_rect(size: Vector2, pad: int, facing: int) -> Rect2:
	var at := Vector2(-floorf(size.x / 2.0) - pad, -size.y - pad)
	var grown := size + Vector2.ONE * pad * 2.0
	return Rect2(at, Vector2(-grown.x if facing < 0 else grown.x, grown.y))


## Draws `tex` as the picture of size `size` would be drawn, grown by `pad` px on every side.
static func _put(ci: CanvasItem, tex: Texture2D, size: Vector2, pad: int, feet: Vector2, facing: int, t: float,
		moving: bool, tint: Color) -> void:
	var m := motion(t, moving, facing)
	var sq: Vector2 = m.squash
	var w := roundf(size.x * sq.x)
	var h := roundf(size.y * sq.y)
	var base := (feet + (m.off as Vector2)).round()
	var lean: float = m.lean
	var src := Rect2(Vector2.ZERO, tex.get_size())
	var dst := figure_rect(Vector2(w, h), pad, facing)
	if absf(lean) < LEAN_MIN:
		dst.position += base
		ci.draw_texture_rect_region(tex, dst, src, tint)
		return
	ci.draw_set_transform(base, lean, Vector2.ONE)
	ci.draw_texture_rect_region(tex, dst, src, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The two rim layers of a picture, built once from its alpha: [the pixels one step outside it (white), the pixels
## a second step out (white)], each `RIM_PAD` px bigger on every side. Tint them when drawing.
static func rim_textures(name: String, tex: Texture2D) -> Array:
	var key := "%s#%d" % [name, tex.get_instance_id()]
	if _rims.has(key):
		return _rims[key]
	var w := tex.get_width()
	var h := tex.get_height()
	var img := tex.get_image()
	var solid := PackedByteArray()
	solid.resize((w + RIM_PAD * 2) * (h + RIM_PAD * 2))
	var gw := w + RIM_PAD * 2
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y: int in h:
			for x: int in w:
				if img.get_pixel(x, y).a >= RIM_ALPHA:
					solid[(y + RIM_PAD) * gw + x + RIM_PAD] = 1
	var gh := h + RIM_PAD * 2
	var first := _grown(solid, gw, gh)
	var second := _grown(first, gw, gh)
	var a := Image.create(gw, gh, false, Image.FORMAT_RGBA8)
	var b := Image.create(gw, gh, false, Image.FORMAT_RGBA8)
	for y: int in gh:
		for x: int in gw:
			var i := y * gw + x
			if solid[i] == 1:
				continue
			if first[i] == 1:
				a.set_pixel(x, y, Color.WHITE)
			elif second[i] == 1:
				b.set_pixel(x, y, Color.WHITE)
	var out: Array = [ImageTexture.create_from_image(a), ImageTexture.create_from_image(b)]
	_rims[key] = out
	return out


## `mask` (1 = set) grown by one pixel in all eight directions.
static func _grown(mask: PackedByteArray, gw: int, gh: int) -> PackedByteArray:
	var out := mask.duplicate()
	for y: int in gh:
		for x: int in gw:
			if mask[y * gw + x] == 0:
				continue
			for dy in range(maxi(y - 1, 0), mini(y + 2, gh)):
				for dx in range(maxi(x - 1, 0), mini(x + 2, gw)):
					out[dy * gw + dx] = 1
	return out


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

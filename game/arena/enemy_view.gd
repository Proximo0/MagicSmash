class_name EnemyView
extends RefCounted
## How each enemy type looks, by Bestiary type id: its walk or hover cycle (KEYS, stepped at ANIM frames a second),
## the width of the shadow `_draw_entities` puts under it (SHADOW, 0: none there) and its name on banners.
## `_draw_enemy` swaps in the frame of a hop, a wind-up, a cast or a swoop. The reserved kinds show one stand-in
## frame each (SpritesEnemies.STAND_INS) until their own art lands.

const KEYS: Array = [["goblin_a", "goblin_c", "goblin_b", "goblin_d"], ["skeleton_a", "skeleton_c", "skeleton_b", "skeleton_d"],
	["slime_a"], ["mslime_a", "mslime_c", "mslime_a", "mslime_b"], ["bat_a", "bat_c", "bat_b", "bat_d"],
	["orc_a", "orc_c", "orc_b", "orc_c"], ["mage_a", "mage_b"], ["lich", "lich_b"], ["wraith_a", "wraith_b"],
	["tome_a", "tome_b", "tome_c", "tome_b"], ["gargoyle_b", "gargoyle_c"], ["priest_a", "priest_b"],
	["bloat_a"], ["coffin_a"], ["guard_a"], ["cinderling_a"], ["censor_a"], ["hound_a"], ["shard_a"], ["swords_a"],
	["chandelier_a"], ["ghostwriter_a"]]
## The wraith has none; the bat, the tome and the swooping gargoyle get theirs from `_draw_enemy_glows`.
const SHADOW: Array = [10, 10, 12, 8, 0, 16, 10, 26, 0, 0, 16, 10, 14, 14, 14, 10, 12, 14, 14, 12, 0, 0]
const ANIM: Array = [10.0, 7.0, 0.0, 7.0, 14.0, 5.0, 2.5, 3.0, 3.0, 10.0, 7.0, 3.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
const NAMES: Array = ["GOBLIN", "SKELETON", "SLIME", "SLIMELING", "BAT", "ORC BRUTE", "DARK MAGE", "LICH LORD", "WRAITH", "CURSED TOME",
	"GARGOYLE", "BONE PRIEST", "BLOAT", "RESTLESS COFFIN", "TOMB GUARD", "CINDERLING", "THE CENSOR", "ASH HOUND", "COMET SHARD",
	"TEN OF SWORDS", "THE BONE CHANDELIER", "THE GHOST WRITER"]

## Job K's kinds show their state with stand-in means until their own art lands (docs/art_dropin.md): a tint, a shake
## (`state_look`, before the sprite), a line or an arc over it (`draw_state`), and on the wizards' layer an arrow at
## the screen's edge for an F_ARROW kind out of sight and a red eye over the wizard the hounds hunt (`draw_marks`).
const SEAM := Color("fff2a8") # the coffin's seam light and its edge arrow
const SHIELD := Color("e8dcc0") # the guard's shield arc
const EMBER := Color("ffb347") # a cinderling kindling, the censor's wind-up
const HOWL := Color("ff3b3b") # the hounds' howl and the eye over their prey
const EDGE_INSET := 10.0 # how far inside the screen an edge arrow sits, px
const EYE_RISE := 37.0 # how far over a hunted wizard's feet the eye floats (over the pip), px


## Draws an enemy from its one still picture (`sprites/enemy_<key>.png`, `boss_<key>.png`) in place of its code
## frame: `feet` and `mod` already carry the pose (hop, shake, tint, flash colour). False when there is no picture.
static func draw_still(ci: CanvasItem, e: Dictionary, feet: Vector2, flash: bool, mod: Color, time: float) -> bool:
	var t: int = e.type
	var nm := Still.enemy_name(t, bool(e.get("final", false)))
	if nm.is_empty():
		return false
	if bool(e.get("elite", false)):
		mod = mod * Still.ELITE_TINT
	var moving: bool = float(Bestiary.KINDS[t][2]) > 0.0
	return Still.draw(ci, nm, feet, -1 if bool(e.get("flip", false)) else 1, time + float(e.get("t", 0.0)), moving, mod, flash)


## [feet, modulate] for a job K kind in its current state.
static func state_look(a: Arena, e: Dictionary, feet: Vector2, mod: Color) -> Array:
	var st: int = e.state
	var beat := int(a.time * 16.0) % 2 == 0
	match int(e.type):
		Bestiary.BLOAT:
			mod = mod * Color(1.0, 1.0 + 0.15 * sin(a.time * 6.0 + float(e.t)), 1.0)
		Bestiary.COFFIN:
			if st == KindsCrypt.ST_RATTLE:
				feet.x += 1.0 if int(a.time * 30.0) % 2 == 0 else -1.0
		Bestiary.CINDERLING:
			if st == KindsLibrary.CS_KINDLE:
				mod = mod * (Color(2.0, 1.6, 1.0) if beat else Color(1.6, 0.9, 0.5))
			elif st == KindsLibrary.CS_RUN:
				mod = mod * Color(1.7, 1.0, 0.6)
		Bestiary.CENSOR:
			if st == KindsLibrary.ZS_WIND:
				mod = mod * (Color(1.9, 1.3, 0.7) if beat else Color.WHITE)
			elif st == KindsLibrary.ZS_PANIC:
				feet.x += 1.0 if int(a.time * 24.0) % 2 == 0 else 0.0
				mod = mod * Color(1.2, 1.2, 1.5)
		Bestiary.HOUND:
			var phase := st % KindsLibrary.HOUND_SLOT_STEP
			if phase == KindsLibrary.HS_HOWL:
				mod = mod * (Color(2.6, 1.0, 1.0) if beat else Color(1.8, 0.9, 0.9))
			elif phase == KindsLibrary.HS_HUNT:
				mod = mod * Color(2.4, 1.0, 1.0)
		Bestiary.SHARD:
			if st == KindsSanctum.SS_CHARGE:
				mod = mod * (Color(2.0, 2.0, 2.2) if beat else Color(1.3, 1.3, 1.5))
			elif st == KindsSanctum.SS_BEAM:
				mod = mod * Color(1.4, 1.3, 1.6)
	return [feet, mod]


## Over the sprite: the coffin's seam, the guard's shield side, a kindling ember, the censor's raised fire, the howl.
static func draw_state(a: Arena, ci: CanvasItem, e: Dictionary, feet: Vector2) -> void:
	var st: int = e.state
	var t: int = e.type
	var top: float = SpritesEnemies.TOP[t]
	match t:
		Bestiary.COFFIN:
			var k := 0.3 if st == KindsCrypt.ST_SHUT else 0.6 + 0.4 * sin(a.time * 25.0)
			ci.draw_line(feet + Vector2(0, -top + 3), feet + Vector2(0, -3), Color(SEAM, k), 1.0)
		Bestiary.GUARD:
			var ang := TAU * float(st) / KindsCrypt.GUARD_FACINGS
			ci.draw_arc(feet + Vector2(0, -top * 0.5), top * 0.5 + 3.0, ang - KindsCrypt.GUARD_ARC, ang + KindsCrypt.GUARD_ARC,
				7, SHIELD, 1.0)
		Bestiary.CINDERLING:
			if st == KindsLibrary.CS_KINDLE:
				ci.draw_circle(feet + Vector2(0, -top - 2), 2.0 + sin(a.time * 30.0), EMBER)
		Bestiary.CENSOR:
			if st == KindsLibrary.ZS_WIND:
				ci.draw_circle(feet + Vector2(4, -top - 3), 2.5, EMBER)
		Bestiary.HOUND:
			if st % KindsLibrary.HOUND_SLOT_STEP == KindsLibrary.HS_HOWL:
				var r := 4.0 + fmod(a.time * 30.0, 10.0)
				ci.draw_arc(feet + Vector2(0, -top), r, -PI * 0.85, -PI * 0.15, 6, Color(HOWL, 1.0 - r / 14.0), 1.0)


## On the wizards' layer: an arrow at the screen's edge toward each F_ARROW kind of job K out of sight (the coffin;
## a hound only while it hunts, in the eye's red),
## and a red eye over each wizard the hounds howl at or hunt.
static func draw_marks(a: Arena, ci: CanvasItem) -> void:
	var screen := Rect2(a.cam, G.SCREEN)
	var view := screen.grow(-EDGE_INSET)
	var eyes := {}
	for e: Dictionary in a.ve.values():
		var t: int = e.type
		if not Bestiary.is_new_kind(t):
			continue
		var mid: Vector2 = (e.pos as Vector2) - Vector2(0, float(SpritesEnemies.TOP[t]) * 0.5)
		# A hound earns its arrow only while it hunts: the circling pack is no threat yet, and its arrows would be noise.
		var hunting: bool = t == Bestiary.HOUND and int(e.state) % KindsLibrary.HOUND_SLOT_STEP != KindsLibrary.HS_CIRCLE
		if Bestiary.has_flag(t, Bestiary.F_ARROW) and (t != Bestiary.HOUND or hunting) and not screen.grow(-2.0).has_point(mid):
			var at: Vector2 = mid.clamp(view.position, view.end)
			var d: Vector2 = (mid - at).normalized()
			var solid: bool = (not hunting and int(e.state) == KindsCrypt.ST_SHUT) or int(a.time * 8.0) % 2 == 0
			var col := Color(HOWL if hunting else SEAM, 1.0 if solid else 0.35)
			var tri := PackedVector2Array([at + d * 7.0, at - d * 4.0 + d.orthogonal() * 6.0, at - d * 4.0 - d.orthogonal() * 6.0])
			ci.draw_colored_polygon(tri, col)
			tri.append(tri[0])
			ci.draw_polyline(tri, Color.BLACK, 1.0)
		if hunting:
			eyes[int(e.state) / KindsLibrary.HOUND_SLOT_STEP - 1] = true
	for slot: int in eyes:
		var p: Dictionary = a.vp.get(slot, {})
		if p.is_empty() or not p.get("alive", false):
			continue
		var c: Vector2 = (p.pos as Vector2) + Vector2(0, -EYE_RISE)
		var s := 5.0 + (1.0 if int(a.time * 6.0) % 2 == 0 else 0.0)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s - 1.0, 0), c + Vector2(0, -s * 0.6 - 1.0),
			c + Vector2(s + 1.0, 0), c + Vector2(0, s * 0.6 + 1.0)]), Color.BLACK)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s, 0), c + Vector2(0, -s * 0.6), c + Vector2(s, 0),
			c + Vector2(0, s * 0.6)]), HOWL)
		ci.draw_circle(c, 1.5, Color.BLACK)

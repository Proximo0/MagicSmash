class_name ArenaLighting
extends Node
## Arena: the room's light. A small light map (half the screen's size) is painted every frame, a dark ambient per
## act with soft lights added on it: the backdrop's candles, fire bowls and lamps, the doors and the seal, each
## wizard's own glow, spells, rune circles, flashes, enemy shots and loot. The map is laid over the world with a
## multiply blend, under the particles, the shots and the wizards, so magic and players are never dimmed, and it
## is drawn smooth (filtered) so the falloff has no blocks. The HUD sits on its own canvas layer above it all.

## Per act (ArenaBg.OSSUARY .. SANCTUM): the floor's light where no lamp reaches ("amb"), the light added over the
## middle of the room that fades toward the walls ("fill"), the tint flames throw ("fire": multiplied with the
## scene's own fire colour), how much flames flicker, the vignette's darkness at the corners, and how much the
## room's fill rises and falls with fire burning out of sight (the library).
const MOODS := [
	{"amb": Color(0.42, 0.36, 0.48), "fill": Color(0.42, 0.36, 0.30), "fire": Color(1.0, 0.82, 0.62), "flicker": 0.07, "vig": 0.62, "breath": 0.0},
	{"amb": Color(0.46, 0.32, 0.30), "fill": Color(0.44, 0.34, 0.24), "fire": Color(1.0, 0.70, 0.45), "flicker": 0.13, "vig": 0.58, "breath": 0.07},
	{"amb": Color(0.30, 0.36, 0.56), "fill": Color(0.34, 0.40, 0.52), "fire": Color(0.85, 0.85, 1.0), "flicker": 0.04, "vig": 0.66, "breath": 0.0},
]
## The light map is SCALE times smaller than the screen; smooth filtering spreads it back over the pixels.
const SCALE := 2
## Light radii in world pixels.
const CANDLE_R := 46.0
const BOWL_R := 80.0
const WIZARD_R := 56.0
const SHOT_R := 18.0
const ESHOT_R := 12.0
const ENEMY_R := 13.0
const ENEMY_K := 0.3
## Caps so a screen of motes and shots costs the same as a quiet one.
const MAX_SHOTS := 70
const MAX_LOOT := 50
const MAX_FLASHES := 24
## The map holds light at half strength (0.5 leaves a pixel as painted, 1.0 doubles it), so a lamp can make the
## floor brighter than the picture and not only darker. The shader reads the world drawn so far and multiplies
## it by twice the map, with a 4x4 ordered dither under the step of one byte so dim gradients do not band.
const SHADER := """shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
void fragment() {
	ivec2 q = ivec2(FRAGCOORD.xy) % 4;
	float d = (BAYER[q.y * 4 + q.x] / 16.0 - 0.47) / 255.0 * 2.0;
	vec3 light = texture(TEXTURE, UV).rgb + d;
	vec3 world = texture(screen_tex, SCREEN_UV).rgb;
	COLOR = vec4(min(world * light * 2.0, vec3(1.0)), 1.0);
}
"""

var arena: Arena
var _vp: SubViewport
var _base: Node2D
var _lights: Node2D
var _shade: Node2D
var _sprite: Sprite2D
var _soft: ImageTexture
var _vig: GradientTexture2D
var _off := Vector2.ZERO


## Builds the light map and lays it over `a`'s world: call where the multiply belongs in the root's draw order
## (after the actors, before the particles and the wizards' own layer).
static func attach(a: Arena) -> ArenaLighting:
	var l := ArenaLighting.new()
	l.arena = a
	l.process_priority = 100 # after the arena has placed its camera and shake for this frame
	l._build()
	a.add_child(l)
	return l


func _build() -> void:
	_soft = ImageTexture.create_from_image(_falloff(64))
	_vp = SubViewport.new()
	_vp.size = Vector2i(G.SCREEN) / SCALE
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(_vp)
	_base = Node2D.new()
	_base.scale = Vector2.ONE / SCALE
	_vp.add_child(_base)
	_lights = Node2D.new()
	_lights.scale = Vector2.ONE / SCALE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lights.material = add
	_lights.self_modulate = Color(0.5, 0.5, 0.5)
	_vp.add_child(_lights)
	_shade = Node2D.new()
	_shade.scale = Vector2.ONE / SCALE
	_vp.add_child(_shade)
	_base.draw.connect(_draw_base)
	_lights.draw.connect(func() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_lights()
		PerfMeter.since("draw_light", t0))
	_shade.draw.connect(_draw_shade)
	_vig = GradientTexture2D.new()
	_vig.width = 128
	_vig.height = 72
	_vig.fill = GradientTexture2D.FILL_RADIAL
	_vig.fill_from = Vector2(0.5, 0.5)
	_vig.fill_to = Vector2(1.08, 1.08)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 1))
	g.add_point(0.45, Color(0, 0, 0, 0))
	g.add_point(0.75, Color(0, 0, 0, 0.35))
	_vig.gradient = g
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture = _vp.get_texture()
	_sprite.scale = Vector2(SCALE, SCALE)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_sprite.material = mat
	arena.root.add_child(_sprite)


## A round light, white, alpha falling smoothly to nothing at the rim: (1 - d^2)^2.
static func _falloff(d: int) -> Image:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	for y in d:
		for x in d:
			var k := clampf(1.0 - Vector2(x - c, y - c).length_squared() / (c * c), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, k * k))
	return img


func _process(_dt: float) -> void:
	# The map is laid in the root's space at the screen's top-left, so it rides the camera and the shake.
	_off = arena.root.position
	_sprite.position = -_off
	# Smoke, debris and puffs draw over the map (with the glowing fx and the words): tint them toward the room's light so they
	# do not glare in the dark. Additive fx keep their full colour.
	if arena.fx != null:
		arena.fx.shade = (_mood("amb") as Color).lerp(Color.WHITE, 0.3)
	_base.queue_redraw()
	_lights.queue_redraw()
	_shade.queue_redraw()


## The act's mood, faded between the old act's and the new one's while the backdrop changes.
func _mood(key: String) -> Variant:
	var k := ArenaDrawWorld._act_blend(arena)
	var now: Variant = (MOODS[clampi(arena.act, 0, MOODS.size() - 1)] as Dictionary)[key]
	if k >= 1.0:
		return now
	var was: Variant = (MOODS[clampi(arena._prev_act, 0, MOODS.size() - 1)] as Dictionary)[key]
	if now is Color:
		return (was as Color).lerp(now as Color, k)
	return lerpf(float(was), float(now), k)


func _draw_base() -> void:
	_base.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), (_mood("amb") as Color) * 0.5)


## One soft light: `r` world pixels round (squashed a little, as light on a floor seen from above), colour times
## strength. Off-screen lights are skipped.
func _light(at: Vector2, r: float, c: Color, k: float, squash := 0.8) -> void:
	var p := at + _off
	if p.x < -r or p.y < -r or p.x > G.SCREEN.x + r or p.y > G.SCREEN.y + r or k <= 0.0:
		return
	var h := r * squash
	_lights.draw_texture_rect(_soft, Rect2(p.x - r, p.y - h, r * 2.0, h * 2.0), false, Color(c, clampf(k, 0.0, 1.0)))


## A flame's slow breathing: two slow waves and a faster one, never a blink.
static func _flicker(t: float, i: int, amount: float) -> float:
	return 1.0 + amount * (0.55 * sin(t * 5.3 + i * 1.7) + 0.3 * sin(t * 9.1 + i * 2.9) + 0.15 * sin(t * 15.7 + i * 0.6))


func _draw_lights() -> void:
	var a := arena
	var t := a.time
	# The middle of the room catches stray light; the walls and corners keep the dark.
	var room := G.ARENA
	var fill := _mood("fill") as Color
	fill *= _flicker(t * 0.6, 7, float(_mood("breath")))
	_light(room.get_center(), room.size.x * 0.62, fill, 1.0, room.size.y / room.size.x * 1.25)
	var k := ArenaDrawWorld._act_blend(a)
	if k < 1.0:
		_scene_lights(ArenaBg.scene(a._prev_act), 1.0 - k)
	_scene_lights(ArenaBg.scene(a.act), k)
	# Rune circles and candles light the floor they cover.
	for c: Array in a.vr:
		_light(c[0], float(c[1]) * 1.3, ArenaDrawWorld._circle_color(a, c), 0.55 * ArenaDrawWorld._rune_alpha(a, c))
	# Loot glints on the floor: chests and cards strongly, motes and coins a little.
	var n := 0
	for kk: Array in a.vk:
		if n >= MAX_LOOT:
			break
		var kind: int = kk[0]
		var big := kind >= World.PK_CARD or kind == World.PK_CHEST
		if kind == World.PK_XP and n > MAX_LOOT / 2:
			continue
		_light(kk[1], 26.0 if big else 11.0, ArenaDrawFx._pickup_color(a, kind), 0.6 if big else 0.32)
		n += 1
	# Shots: the wizards' spells in their colours, the enemies' in red.
	n = 0
	for s: Array in a.vs:
		if n >= MAX_SHOTS:
			break
		_light(s[1], SHOT_R * (1.4 if s[4] else 1.0), ArenaDrawFx._spell_color(a, s[0], s[3]), 0.55)
		n += 1
	for s: Array in a.ves:
		if n >= MAX_SHOTS + 30:
			break
		_light(s[1], ESHOT_R, Color(1.0, 0.3, 0.25), 0.5)
		n += 1
	# Flashes: blasts, casts, novas. A blast's light outlives its flash a little.
	n = 0
	for f: Array in a.fx.flashes:
		if n >= MAX_FLASHES:
			break
		var life := float(f[2]) / float(f[3])
		_light(f[0], maxf(16.0, float(f[1]) * 2.2), (f[4] as Color), 0.9 * life)
		n += 1
	# Bosses and elites glow in their halo colour. Every other enemy carries a faint light of its own, close round
	# it, so the dark never swallows one: legibility before mood.
	var seen := Color(1.0, 0.95, 0.9)
	for e: Dictionary in a.ve.values():
		_light(e.pos + Vector2(0, -6), ENEMY_R, seen, ENEMY_K, 1.1)
		if e.type == World.LICH:
			_light(e.pos + Vector2(0, -8), 70.0, Color(0.6, 0.5, 1.0), 0.55)
		elif e.elite:
			_light(e.pos + Vector2(0, -4), 26.0, Color(1.0, 0.85, 0.6), 0.35)
	# Each wizard carries a small light of their own colour, and a white core so the sprite is fully lit.
	for p: Dictionary in a.vp.values():
		if not p.alive:
			continue
		var col := G.player_fx(p.slot)
		var breath := 1.0 + 0.04 * sin(t * 2.1 + float(p.slot) * 1.3)
		_light(p.pos + Vector2(0, -2), WIZARD_R * breath, col.lerp(Color.WHITE, 0.15), 0.8)
		_light(p.pos + Vector2(0, -8), 22.0, Color(1, 0.96, 0.9), 0.55)


## The lights painted into an act's backdrop: lamp pools, candles, fire bowls, doors and the seal.
func _scene_lights(scene: Dictionary, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var t := arena.time
	var tint := _mood("fire") as Color
	var fire: Color = (scene.get("fire", Color(1.0, 0.55, 0.18)) as Color).lerp(Color(1, 0.9, 0.75), 0.35) * tint
	var amount := float(_mood("flicker"))
	var glows: Array = scene.get("glows", [])
	for i in glows.size():
		var g: Array = glows[i]
		var r: Vector2 = g[1]
		_light(g[0], maxf(r.x, r.y) * 1.5, fire, 0.55 * alpha * _flicker(t, i + 31, amount), r.y / maxf(r.x, 1.0))
	var flames: Array = scene.get("flames", [])
	for i in flames.size():
		var f: Array = flames[i]
		var bowl := int(f[1]) == ArenaArtLive.FIRE
		var fl := _flicker(t, i, amount * (1.4 if bowl else 1.0))
		var p: Vector2 = f[0]
		if bowl:
			_light(p + Vector2(0, -2), BOWL_R * (0.97 + 0.03 * fl), fire, 0.85 * alpha * fl)
			_light(p + Vector2(0, -4), BOWL_R * 0.4, Color(1, 0.92, 0.75), 0.5 * alpha * fl)
		else:
			_light(p, CANDLE_R, fire, 0.75 * alpha * fl)
			_light(p, CANDLE_R * 0.35, fire, 0.4 * alpha * fl)
	var doors: Array = scene.get("doors", [])
	var dcol: Color = scene.get("door_light", Color(1.0, 0.16, 0.2))
	for i in mini(doors.size(), arena.door_anim.size()):
		var r: Rect2 = doors[i]
		var o: float = arena.door_anim[i]
		_light(r.get_center(), 30.0 + 50.0 * o, dcol, (0.1 + 0.6 * o) * alpha)
	if scene.has("seal"):
		var seal: Dictionary = scene.seal
		var sc: Color = scene.get("seal_light", Color(0.35, 0.9, 1.0))
		_light(seal.c, float(seal.rx) + 30.0, sc, (0.22 + 0.06 * sin(t * 1.3)) * alpha, float(seal.squash))


func _draw_shade() -> void:
	_shade.draw_texture_rect(_vig, Rect2(Vector2.ZERO, G.SCREEN), false, Color(1, 1, 1, float(_mood("vig"))))

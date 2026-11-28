extends Node2D
## Title screen, lobby and LAN browser, on the FOUR OF WANDS backdrop: night, a huge moon behind the wizards'
## tower, four staffs planted in the foreground with a garland strung between them, and the four wizards
## celebrating under it. `TitleArt` bakes everything that stands still; this draws the layers and what moves:
## the gems breathe, the lanterns sway, wisps cross the moon and the wizards send up fireworks.

enum S { INTRO, MAIN, LOBBY, JOIN, JOINING, HOWTO, UNLOCKS, OPTIONS, OUIJA, TALE, CARDS, CREDITS }

const MENU := ["PLAY", "UNLOCKS", "CARDS", "HOST LAN GAME", "JOIN LAN GAME", "THE TALE", "HOW TO PLAY", "OPTIONS", "CREDITS", "QUIT"]

## The menu hangs in the first bay of the garland, under the logo: its centre line, first row and row pitch.
const MENU_X := 104
const MENU_Y := 141
const MENU_STEP := 10
## The unlock list's first row and row pitch (_draw_unlocks draws a row there, _buy_unlock bursts on it).
const UNLOCK_ROW_Y := 135
const UNLOCK_ROW_STEP := 11

## The intro, in seconds: the gems light one by one, the lanterns in a wave from the left, the logo is struck
## letter by letter and cools to gold, then its own four gems are set. The menu follows at 2.6 as it always has.
const GEM_AT := 0.15
const GEM_STEP := 0.14
const LANTERN_AT := 0.5
const LANTERN_WAVE := 0.7
const LETTER_AT := 0.45
const LETTER_STEP := 0.11
const LETTER_COOL := 0.55
const LOGO_GEM_AT := 1.75
const LOGO_GEM_STEP := 0.08

## The wisps of cloud that cross the moon: [x when the screen opens, y, pixels a second].
const WISPS := [[236.0, 52, 2.0], [318.0, 98, 1.3], [282.0, 24, 2.6]]

var state := S.INTRO
var t := 0.0
var sel := 0
var join_sel := 0
var unlock_sel := 0
var fx: Fx
var glow: Node2D
var fore: Node2D
var fore_glow: Node2D
var front: Node2D
var cast_timer := 1.6
var smoke_timer := 0.0
var wiz_cast := [0.0, 0.0, 0.0, 0.0]
var message := ""
var message_t := 0.0
var options := OptionsPanel.new()
var album := CardAlbum.new()
var credits := CreditsView.new()
var hero_roster := HeroRoster.new()
var hero_roster_dev := -99 # the device whose seat the open hero list picks for
var ouija := Ouija.new()
var planchette := Vector2(240, 150)
## The prologue page on screen, when it was turned, and the menu item to carry on to after it.
var tale_page := 0
var tale_t := 0.0
var tale_then := ""
var tale_dev := 0
var menu_items: Array = []
var rng := RandomNumberGenerator.new()
## The steps of the intro that have happened, so each sounds once.
var _struck := {}
## How far the scene is dimmed behind a sub-screen's panel, 0..1.
var dim := 0.0
var eclipse := 0.0 # seconds left of the blood moon (click the moon)
var ghost_t := -1.0 # seconds since the ghost left the tower's top window (click it), -1 when none
const MOON := TitleArt.MOON
const TOP_WINDOW := TitleArt.TOP_WINDOW # the middle window of the tower's top room
const ECLIPSE_LIFE := 8.0
const GHOST_LIFE := 5.0

func _ready() -> void:
	rng.randomize()
	TitleArt.warm()
	# Back to front: the baked scene and the wizards (this node), their glow, the fireworks, the staffs and
	# garland with their own glow, then the logo, menu and panels.
	glow = _layer(true, _draw_glow)
	fx = Fx.new()
	add_child(fx)
	fore = _layer(false, _draw_fore)
	fore_glow = _layer(true, _draw_fore_glow)
	front = _layer(false, _draw_front)
	Net.roster_changed.connect(_on_roster)
	Net.connection_failed.connect(_on_conn_failed)
	Net.games_found_changed.connect(func(): pass)
	Sfx.music("music_title")
	if not G.title_message.is_empty():
		_msg(G.title_message)
		G.title_message = ""
		state = S.MAIN
		t = 4.0
	if Net.mode != Net.Mode.OFFLINE and not Net.closing: # a host on its way out closes by itself in a moment
		Net.shutdown()
	G.local_devices.clear()
	leave_ask = false
	if G.title_shop:
		# From the Sanctum's shopkeeper: straight to the unlocks; back returns to the Sanctum.
		unlock_sel = 0
		state = S.UNLOCKS
		t = 4.0
		dim = 1.0
	elif G.title_lobby_device != -99:
		# Through the Sanctum's portal: the lobby, with that wizard already in.
		G.local_devices = [G.title_lobby_device]
		G.title_lobby_device = -99
		Net.start_offline()
		_clamp_lobby_seal()
		state = S.LOBBY
		t = 4.0
		dim = 1.0
		_flash_burst()

func _layer(additive: bool, draw_fn: Callable) -> Node2D:
	var n := Node2D.new()
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		n.material = m
	add_child(n)
	n.draw.connect(draw_fn)
	return n

func _msg(s: String) -> void:
	message = s
	message_t = 3.0

# ================================================================ LOOP ===
func _process(delta: float) -> void:
	# The frame after a slow load is a long one: it must not swallow the start of the intro.
	t += minf(delta, 0.1)
	message_t = maxf(0.0, message_t - delta)
	eclipse = maxf(0.0, eclipse - delta)
	if ghost_t >= 0.0:
		ghost_t += delta
		if ghost_t > GHOST_LIFE:
			ghost_t = -1.0
	if state == S.INTRO and t > 3.2:
		state = S.MAIN
	var panel := state in [S.LOBBY, S.JOIN, S.JOINING, S.HOWTO, S.UNLOCKS, S.OPTIONS]
	dim = move_toward(dim, 1.0 if panel else 0.0, delta * 5.0)
	_intro_steps()
	# The wizards take turns sending up a rocket.
	cast_timer -= delta
	if cast_timer <= 0.0 and t > 1.0:
		cast_timer = rng.randf_range(1.2, 2.4)
		_launch(rng.randi() % 4)
	for i in 4:
		wiz_cast[i] = maxf(0.0, wiz_cast[i] - delta)
	_update_rockets(delta)
	_ambience(delta)
	queue_redraw()
	glow.queue_redraw()
	fore.queue_redraw()
	fore_glow.queue_redraw()
	front.queue_redraw()
	if hero_roster.active:
		hero_roster.update(delta)
	if state == S.OUIJA:
		planchette = planchette.lerp(_ouija_pos(ouija.row, ouija.col), minf(1.0, delta * 14.0))

## Runs `what` once as the intro passes `at`. A step skipped over (a key pressed, or the screen opened past its
## intro) is marked without it, so nothing sounds late.
func _strike(key: String, at: float, what: Callable) -> void:
	if t < at or _struck.has(key):
		return
	_struck[key] = true
	if t - at < 0.25:
		what.call()

func _intro_steps() -> void:
	for i in 4:
		_strike("gem%d" % i, GEM_AT + i * GEM_STEP, func() -> void:
			var c: Color = TitleArt.WIZ[i][0]
			var p := TitleArt.gem_pos(i)
			fx.ring(p, 2.0, 20.0, 0.5, c, 1.0)
			fx.burst(p, 10, 46.0, 0.5, 1.0, Color.WHITE, c, true, 0.0, true)
			Sfx.play("candle", -8.0, 0.85 + i * 0.12, 0.0))
	var letters := TitleArt.logo_letters()
	var at := Vector2(TitleArt.LOGO_AT)
	for i in letters.size():
		_strike("letter%d" % i, LETTER_AT + i * LETTER_STEP, func() -> void:
			var r := Rect2(letters[i])
			fx.burst(at + r.position + Vector2(r.size.x * 0.5, r.size.y - 4.0), 7, 70.0, 0.45, 1.0, Color.WHITE,
				Color("ffb326"), true, 130.0)
			Sfx.play("hit", -9.0, 0.7 + i * 0.045, 0.0)
			if i == letters.size() - 1:
				Sfx.play("explode", -7.0, 0.85, 0.0))
	for i in 4:
		_strike("logo_gem%d" % i, LOGO_GEM_AT + i * LOGO_GEM_STEP, func() -> void:
			var c: Color = TitleArt.WIZ[i][0]
			fx.burst(at + TitleArt.logo_gems()[i], 6, 34.0, 0.4, 1.0, Color.WHITE, c, true)
			Sfx.play("menu_move", -8.0, 1.3 + i * 0.16, 0.0))

## The small slow things: fireflies over the meadow and the lake, smoke from the tower's chimney.
func _ambience(delta: float) -> void:
	if rng.randf() < delta * 1.4:
		var p := Vector2(rng.randf_range(196, 472), rng.randf_range(198, 264))
		var c := Color(0.85, 1.0, 0.45)
		fx.spawn(p, Vector2(rng.randf_range(-5, 5), rng.randf_range(-6, 1)), rng.randf_range(2.0, 4.0), 1.0, c,
			Color(c, 0.0), true, 0.0)
	smoke_timer -= delta
	if smoke_timer <= 0.0:
		smoke_timer = rng.randf_range(0.5, 0.8)
		var c := Color(TitleArt.NIGHT[3], 0.55)
		fx.spawn(Vector2(TitleArt.TOWER_X + 21.5, 88), Vector2(rng.randf_range(1.0, 3.5), rng.randf_range(-6, -4)), 5.0, 1.0,
			c, Color(c, 0.0), false, 0.0, 0.0, 3.0)

var rockets: Array = [] # [pos, vel, light colour, fuse, deep colour]
var blooms: Array = [] # a burst's light on the lake: [pos, colour, seconds left]

func _launch(w: int) -> void:
	wiz_cast[w] = 0.45
	var col: Color = TitleArt.WIZ[w][0]
	var start: Vector2 = TitleArt.WIZ_SPOTS[w] + TitleArt.wand_tip(w, 2)
	# Up into the open sky between the logo and the moon.
	var target := Vector2(rng.randf_range(204, 322), rng.randf_range(22, 92))
	var speed := rng.randf_range(170, 215)
	rockets.append([start, (target - start).normalized() * speed, col, start.distance_to(target) / speed, TitleArt.WIZ[w][1]])
	fx.burst(start, 5, 30.0, 0.3, 1.0, Color.WHITE, col, true)
	Sfx.play("shoot_arcane", -18.0, rng.randf_range(0.8, 1.1), 0.1)

func _update_rockets(delta: float) -> void:
	for r in rockets:
		r[0] += r[1] * delta
		r[1].y += 40.0 * delta
		r[3] -= delta
		fx.spawn(r[0], -r[1] * 0.1, 0.35, 1.0, Color.WHITE, r[2], true, 2.0)
		if r[3] <= 0.0:
			var c: Color = r[2]
			_firework(r[0], c, r[4])
			# The lake answers a burst over it with a dim bloom of the same colour.
			if r[0].x > 200.0 and r[0].x < 262.0:
				blooms.append([Vector2(r[0].x, 214.0), c, 0.7])
			Sfx.play("explode", -20.0, rng.randf_range(1.3, 1.8), 0.15)
	rockets = rockets.filter(func(r): return r[3] > 0.0)
	for b in blooms:
		b[2] -= delta
	blooms = blooms.filter(func(b): return b[2] > 0.0)

## A rocket bursts: a flower of rays in the wizard's colour that opens, hangs and fades, and gold glitter that
## falls out of it.
func _firework(pos: Vector2, light: Color, deep: Color) -> void:
	var rays := 12 + rng.randi() % 5
	var spin := rng.randf() * TAU
	var reach := rng.randf_range(0.85, 1.2)
	for k in rays:
		var dir := Vector2.from_angle(spin + k * TAU / rays)
		for shell in 4:
			var c0: Color = [deep, deep.lerp(light, 0.5), light, Color.WHITE][shell]
			fx.spawn(pos, dir * (22.0 + shell * 19.0) * reach, 1.5 + shell * 0.15, 1.0, c0, Color(deep, 0.0), true, 1.9, 14.0,
				1.0, shell >= 2)
	for k in 12:
		var dir := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(8.0, 36.0)
		fx.spawn(pos, dir, rng.randf_range(1.6, 2.6), 1.0, Color("fff6c0"), Color(Color("ffb326"), 0.0), true, 1.2, 46.0, 1.0)
	fx.flash(pos, 5.0, light, 0.12)

# ============================================================= DRAWING ===
## How deep the moon is in the eclipse, 0..1.
func _blood() -> float:
	return clampf(minf(eclipse, ECLIPSE_LIFE - eclipse) / 1.2, 0.0, 1.0) if eclipse > 0.0 else 0.0

## Which frame wizard `i` is in: 0 and 1 cheer, 2 thrusts the wand up as a rocket leaves it.
func _wiz_frame(i: int) -> int:
	if wiz_cast[i] > 0.0:
		return 2
	return int(t * 2.2 + i * 0.6) % 2

func _draw() -> void:
	draw_texture(TitleArt.sky(), Vector2.ZERO)
	# The brightest stars twinkle: a small cross that comes and goes.
	for s: Array in TitleArt.twinkles():
		var tw := sin(t * float(s[2]) + float(s[1]))
		if tw > 0.55:
			var p: Vector2 = s[0]
			var c := Color(s[3] as Color, (tw - 0.55) / 0.45 * 0.8)
			draw_rect(Rect2(p.x - 1, p.y, 3, 1), c)
			draw_rect(Rect2(p.x, p.y - 1, 1, 3), c)
	var blood := _blood()
	_draw_moon(blood)
	_draw_wisps(blood)
	draw_texture(TitleArt.land(), Vector2.ZERO)
	if eclipse > 0.0:
		draw_rect(Rect2(0, 0, 480, 270), Color(0.5, 0.0, 0.05, 0.14 * blood))
		# Bats stream across the sky.
		for i in 14:
			var bx := fposmod(-60.0 + (ECLIPSE_LIFE - eclipse) * (70.0 + i * 9.0) + i * 37.0, 560.0) - 40.0
			var by := 26.0 + fmod(i * 23.0, 104.0) + sin(t * 3.0 + i) * 6.0
			Sprites.draw_at(self, "bat_a" if int(t * 12.0 + i) % 2 == 0 else "bat_b", Vector2(bx, by), i % 2 == 0)
	_draw_ghost()
	# Behind a sub-screen's panel the wizards fall into shadow, so a hint written under the panel stays clear.
	var shade := Color.WHITE.lerp(Color(0.2, 0.16, 0.3), dim)
	for i in 4:
		TitleArt.draw_sprite(self, "wiz%d_%s" % [i, "abc"[_wiz_frame(i)]], TitleArt.WIZ_SPOTS[i], shade)

## The moon; blood red, with the earth's shadow crossing it, while eclipsed.
func _draw_moon(blood: float) -> void:
	var r := TitleArt.MOON_R
	var at := MOON - Vector2(r, r)
	draw_texture(TitleArt.moon(), at)
	if blood > 0.0:
		draw_texture(TitleArt.moon(true), at, Color(1, 1, 1, blood))
	if eclipse <= 0.0:
		return
	# The shadow is a disc sliding over the moon's own: drawn row by row where the two overlap.
	var sx := MOON.x + lerpf(-2.1, 2.1, 1.0 - eclipse / ECLIPSE_LIFE) * r
	var sr := r - 3.0
	for dy in range(-r, r + 1):
		if absf(dy) >= sr:
			continue
		var hm := floorf(sqrt((r + 0.5) * (r + 0.5) - dy * dy))
		var hs := floorf(sqrt(sr * sr - dy * dy))
		var x0 := maxf(MOON.x - hm, floorf(sx) - hs)
		var x1 := minf(MOON.x + hm + 1.0, floorf(sx) + hs + 1.0)
		if x1 > x0:
			draw_rect(Rect2(x0, MOON.y + dy, x1 - x0, 1), Color(0.04, 0.0, 0.08, 0.6 * blood))

## Wisps of cloud drifting across the sky. Where one crosses the moon's disc it is a lit veil: the second strip,
## clipped row by row to the disc.
func _draw_wisps(blood: float) -> void:
	var tex := TitleArt.wisps()
	var lit := TitleArt.wisps_lit()
	var size := Vector2(TitleArt.WISP)
	var r := TitleArt.MOON_R + 0.5
	var tint := Color.WHITE.lerp(Color(0.8, 0.25, 0.3), blood)
	for k in WISPS.size():
		var wx := floorf(fposmod(float(WISPS[k][0]) + t * float(WISPS[k][2]) + size.x, 480.0 + size.x) - size.x)
		var wy := float(WISPS[k][1])
		draw_texture_rect_region(tex, Rect2(wx, wy, size.x, size.y), Rect2(0, k * size.y, size.x, size.y))
		for row in int(size.y):
			var dy := wy + row - MOON.y
			if absf(dy) >= r:
				continue
			var half := floorf(sqrt(r * r - dy * dy))
			var x0 := maxf(wx, MOON.x - half)
			var x1 := minf(wx + size.x, MOON.x + half + 1.0)
			if x1 > x0:
				draw_texture_rect_region(lit, Rect2(x0, wy + row, x1 - x0, 1),
					Rect2(x0 - wx, k * size.y + row, x1 - x0, 1), tint)

## The tower's ghost: it slips out of the top window, sways up over the roof and fades.
func _draw_ghost() -> void:
	if ghost_t < 0.0:
		return
	var k := ghost_t / GHOST_LIFE
	var a := clampf(minf(ghost_t * 2.0, (GHOST_LIFE - ghost_t) * 1.5), 0.0, 1.0) * 0.9
	var from := TOP_WINDOW.get_center()
	var p := Vector2(from.x - k * 50.0 + sin(ghost_t * 2.2) * 7.0, from.y + 8.0 - k * 36.0)
	TitleArt.draw_sprite(self, "ghost_a" if int(ghost_t * 5.0) % 2 == 0 else "ghost_b", p.floor(), Color(1, 1, 1, a))

func _draw_glow() -> void:
	var ci := glow
	var blood := _blood()
	# The moon's halo, redder under the eclipse.
	var halo := Color(0.72, 0.68, 1.0).lerp(Color(1.0, 0.12, 0.18), blood)
	ci.draw_circle(MOON, 82, Color(halo, 0.03 + 0.03 * blood))
	ci.draw_circle(MOON, 68, Color(halo, 0.035 + 0.03 * blood))
	# Candlelight in the tower's windows and along the stair.
	var wins := TitleArt.windows()
	for i in wins.size():
		var f := 0.75 + 0.25 * sin(t * (2.1 + i * 0.6) + i * 1.7)
		var c: Vector2 = wins[i][0]
		var r: float = wins[i][1]
		_halo(ci, c, r + 2.0, Color(1.0, 0.62, 0.22), 0.26 * f, 4)
	var lights := TitleArt.path_lights()
	for i in lights.size():
		_halo(ci, lights[i] + Vector2(0.5, 0.5), 4.5, Color(1.0, 0.62, 0.22), 0.3 + 0.1 * sin(t * 3.0 + i * 2.3), 3)
	if ghost_t >= 0.0:
		var a := clampf(minf(ghost_t * 2.0, (GHOST_LIFE - ghost_t) * 1.5), 0.0, 1.0)
		var k := ghost_t / GHOST_LIFE
		var from := TOP_WINDOW.get_center()
		_halo(ci, Vector2(from.x - k * 50.0 + sin(ghost_t * 2.2) * 7.0, from.y - k * 36.0), 13.0, Color(0.2, 0.9, 0.8), 0.22 * a, 5)
	for r in rockets:
		_halo(ci, r[0], 5.0, r[2], 0.5, 3)
	for b in blooms:
		ci.draw_set_transform(b[0], 0.0, Vector2(1.0, 0.4))
		_halo(ci, Vector2.ZERO, 22.0, b[1], 0.22 * minf(1.0, float(b[2]) / 0.4), 4)
	ci.draw_set_transform(Vector2.ZERO)

## The staffs and the garland, and what moves on them: the ribbons at the ties and the lanterns.
func _draw_fore() -> void:
	var ci := fore
	ci.draw_texture(TitleArt.fore(), Vector2.ZERO)
	for i in 4:
		var tie := TitleArt.tie_pos(i)
		var ramp: Array = TitleArt.WIZ[i]
		for side in 2:
			var n := 16 if side == 0 else 12
			for r in n:
				var u := float(r) / n
				var sway := sin(t * 1.5 - r * 0.4 + i * 2.1 + side * 1.3) * 2.0 * u
				var x := tie.x + (-4.0 if side == 0 else 2.0) + roundf(sway + (side * 2 - 1) * u * 3.0)
				var y := tie.y + 4.0 + r
				ci.draw_rect(Rect2(x - 1.0, y, 4, 2 if r == n - 1 else 1), TitleArt.INK)
				@warning_ignore("integer_division")
				ci.draw_rect(Rect2(x, y, 2, 1), ramp[1] if (r / 3) % 2 == 0 else ramp[2])
	for l: Array in TitleArt.lanterns():
		var knot: Vector2 = l[0]
		var cord: int = l[1]
		var lean := sin(t * 1.15 + float(l[2])) * 0.2
		for k in cord:
			ci.draw_rect(Rect2(knot.x + roundf(sin(lean) * k), knot.y + k, 1, 1), Color("7a2f14"))
		var tex := TitleArt.sprite("lantern" if _lantern_lit(knot) else "lantern_off")
		ci.draw_texture(tex, Vector2(knot.x + roundf(sin(lean) * (cord + 4)) - 4.0, knot.y + cord - 1.0))

## The lanterns light in a wave from the left as the screen opens.
func _lantern_lit(knot: Vector2) -> bool:
	return t > LANTERN_AT + knot.x / 480.0 * LANTERN_WAVE

func _draw_fore_glow() -> void:
	var ci := fore_glow
	# The logo's last letter lands with a breath of gold light behind the whole of it, which settles to a trace.
	var last := LETTER_AT + (TitleArt.logo_letters().size() - 1) * LETTER_STEP
	if t > last:
		var k := clampf((t - last) / 1.2, 0.0, 1.0)
		ci.draw_set_transform(Vector2(TitleArt.LOGO_AT) + Vector2(82, 40), 0.0, Vector2(1.0, 0.56))
		_halo(ci, Vector2.ZERO, 112.0 - 14.0 * k, Color(1.0, 0.62, 0.2), 0.32 - 0.22 * k, 8)
		ci.draw_set_transform(Vector2.ZERO)
	for i in 4:
		var lit := clampf((t - GEM_AT - i * GEM_STEP) / 0.3, 0.0, 1.0)
		if lit <= 0.0:
			continue
		var p := TitleArt.gem_pos(i) + Vector2(0.5, 0.5)
		var c: Color = TitleArt.WIZ[i][0]
		# The gem breathes.
		var breath := 0.5 + 0.5 * sin(t * 1.5 + i * 1.6)
		_halo(ci, p, 22.0 + 3.0 * breath, c, (0.24 + 0.1 * breath) * lit, 8)
		# A slow broken ring and three motes turn about it, as about the Sanctum's portal.
		var dir := 1.0 if i % 2 == 0 else -1.0
		for k in 2:
			var a0 := dir * t * 0.5 + k * PI + i
			ci.draw_arc(p, 15.5, a0, a0 + 1.4, 10, Color(c, 0.3 * lit), 1.0)
		for k in 3:
			var a := -dir * t * 0.8 + k * TAU / 3.0 + i
			ci.draw_rect(Rect2((p + Vector2(cos(a), sin(a)) * 19.5).floor(), Vector2(1, 1)), Color(c, 0.85 * lit))
	for l: Array in TitleArt.lanterns():
		var knot: Vector2 = l[0]
		if not _lantern_lit(knot):
			continue
		var cord: int = l[1]
		var lean := sin(t * 1.15 + float(l[2])) * 0.2
		var p := Vector2(knot.x + roundf(sin(lean) * (cord + 4)) + 0.5, knot.y + cord + 5.0)
		var f := 0.8 + 0.2 * sin(t * 5.0 + float(l[2]) * 3.0)
		_halo(ci, p, 11.0, Color(1.0, 0.66, 0.25), 0.22 * f, 5)
	# The spark at each wizard's wand tip.
	for i in 4:
		var tip: Vector2 = TitleArt.WIZ_SPOTS[i] + TitleArt.wand_tip(i, _wiz_frame(i))
		var c: Color = TitleArt.WIZ[i][0]
		var tw := 0.6 + 0.4 * sin(t * 6.0 + i * 2.0)
		ci.draw_rect(Rect2(tip.x - 1, tip.y, 3, 1), Color(c, tw))
		ci.draw_rect(Rect2(tip.x, tip.y - 1, 1, 3), Color(c, tw))
		_halo(ci, tip + Vector2(0.5, 0.5), 6.0, c, 0.2 * tw, 3)

## A soft light on an additive layer: discs laid one inside the other, none strong enough to show its edge.
func _halo(ci: CanvasItem, p: Vector2, r: float, c: Color, a: float, steps: int) -> void:
	for k in steps:
		var u := float(k) / steps
		ci.draw_circle(p, r * (1.0 - u * 0.86), Color(c, a / steps))

func _draw_front() -> void:
	var ci := front
	if dim > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.03, 0.0, 0.07, 0.55 * dim))
	if state == S.LOBBY:
		Still.draw_scene(ci, "lobby")
	_draw_logo(ci)
	match state:
		S.INTRO:
			pass
		S.MAIN:
			_draw_menu(ci)
		S.LOBBY:
			_draw_lobby(ci)
			if hero_roster.active:
				hero_roster.draw(ci, t)
		S.JOIN:
			_draw_join(ci)
		S.JOINING:
			_panel(ci, Rect2(120, 140, 240, 50))
			PixelFont.draw_centered(ci, "CONNECTING" + ".".repeat(int(t * 3) % 4), 240, 160, 1, Color.WHITE)
		S.HOWTO:
			_draw_howto(ci)
		S.UNLOCKS:
			_draw_unlocks(ci)
		S.OPTIONS:
			options.draw(ci, t)
		S.CARDS:
			album.draw(ci, t)
		S.CREDITS:
			credits.draw(ci, t)
		S.TALE:
			_draw_tale(ci)
		S.OUIJA:
			_draw_join(ci)
			_draw_ouija(ci)
	if message_t > 0.0:
		# Beside the logo, in the open sky; over the full-screen boards, in the middle.
		var mx := 240.0 if state in [S.OUIJA, S.TALE, S.CARDS, S.CREDITS] else 334.0
		PixelFont.draw_centered(ci, message, mx, 6, 1, Color("ff7a8a"), Color("0b0716"))
	if state == S.INTRO and t < 0.5:
		# The screen opens out of the dark.
		ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(TitleArt.INK, 1.0 - t / 0.5))
	# The version sits in the corner of the open title. The two boards whose frame reaches that corner go without it.
	if not state in [S.CARDS, S.CREDITS]:
		PixelFont.draw(ci, "V" + G.VERSION, Vector2(31, 262), 1, Color(1, 1, 1, 0.3))
	if Save.newer_save():
		# The save came from a newer build: it plays, but Save writes nothing back. Said on every title screen.
		ci.draw_rect(Rect2(0, 250, G.SCREEN.x, 11), Color(TitleArt.INK, 0.85))
		PixelFont.draw_centered(ci, NEWER_SAVE_LINE, 240, 252, 1, Color("ffb347"))
	if G.high_score > 0:
		var hs := "BEST %d" % G.high_score
		PixelFont.draw(ci, hs, Vector2(449 - PixelFont.text_width(hs), 262), 1, Color(1, 0.9, 0.4, 0.6))

## The logo. In the intro each letter is struck in white-hot, two pixels high, drops into place and cools to
## gold; afterwards a band of light crosses it now and then.
func _draw_logo(ci: CanvasItem) -> void:
	var at := Vector2(TitleArt.LOGO_AT)
	var tex := TitleArt.logo()
	var hot := TitleArt.logo_hot()
	var letters := TitleArt.logo_letters()
	var done := LOGO_GEM_AT + 4 * LOGO_GEM_STEP
	if t >= done:
		ci.draw_texture(tex, at)
	else:
		for i in letters.size():
			var k := (t - LETTER_AT - i * LETTER_STEP) / LETTER_COOL
			if k <= 0.0:
				continue
			var to := at + Vector2(letters[i].position) + Vector2(0, -2.0 if k < 0.1 else 0.0)
			ci.draw_texture(TitleArt.logo_letter(i, false), to)
			if k < 1.0:
				ci.draw_texture(TitleArt.logo_letter(i, true), to, Color(1, 1, 1, 1.0 - k))
		var gems := TitleArt.logo_gems()
		for i in gems.size():
			if t >= LOGO_GEM_AT + i * LOGO_GEM_STEP:
				var r := Rect2(gems[i].x - 4.5, gems[i].y - 5.5, 9, 11)
				ci.draw_texture_rect_region(tex, Rect2(at + r.position, r.size), r)
	# The shimmer: a slanted band of the white-hot logo, a row at a time.
	var sweep := fmod(t - 3.4, 7.0)
	if t > 3.4 and sweep < 1.2:
		var w := float(tex.get_width())
		var lead := lerpf(-16.0, w + 44.0, sweep / 1.2)
		for y in tex.get_height():
			var x0 := clampf(floorf(lead - y * 0.55), 0.0, w)
			var x1 := clampf(x0 + 9.0, 0.0, w)
			if x1 > x0:
				ci.draw_texture_rect_region(hot, Rect2(at.x + x0, at.y + y, x1 - x0, 1), Rect2(x0, y, x1 - x0, 1),
					Color(1, 1, 1, 0.8))
	if t > 1.7:
		var a := clampf((t - 1.7) / 0.5, 0.0, 1.0)
		var ty := at.y + tex.get_height() + 5.0
		PixelFont.draw_centered(ci, "HOLD  THE  TOWER", MENU_X, ty, 1, Color(Occult.BONE, a), Color(Occult.INK, a))
		# A short gold rule either side of it, ending in a diamond.
		for side in [-1.0, 1.0]:
			var x: float = MENU_X + side * 56.0
			ci.draw_rect(Rect2(minf(x, x + side * 10.0), ty + 3.0, 11, 1), Color(Color("c48a10"), a))
			ci.draw_rect(Rect2(x - 1.0, ty + 2.0, 3, 3), Color(Occult.GOLD, a))
			ci.draw_rect(Rect2(x, ty + 1.0, 1, 5), Color(Occult.GOLD, a))

func _panel(ci: CanvasItem, r: Rect2) -> void:
	Occult.frame(ci, r, t)

func _visible_menu() -> Array:
	var items := MENU.duplicate()
	if G.is_mobile or OS.has_feature("web"):
		items.erase("QUIT")
	return items

func _draw_menu(ci: CanvasItem) -> void:
	var items := _visible_menu()
	menu_items.clear()
	if t < 2.6:
		return
	for i in items.size():
		var y := MENU_Y + i * MENU_STEP
		var s := i == sel
		var label: String = items[i]
		# The rows come in one after another.
		var a := clampf((t - 2.6 - i * 0.03) / 0.3, 0.0, 1.0)
		menu_items.append(Rect2(MENU_X - 62, y - 2, 124, MENU_STEP))
		if s:
			_draw_menu_mark(ci, y, PixelFont.text_width(label, 1), a)
		PixelFont.draw_centered(ci, label, MENU_X, y, 1, Color(Occult.GOLD if s else Occult.DIM, a), Color(Occult.INK, a))
	var hint := "TAP TO SELECT" if G.touch_active else "ARROWS/STICK + ENTER/A"
	PixelFont.draw_centered(ci, hint, MENU_X, MENU_Y + items.size() * MENU_STEP + 6, 1,
		Color(1, 1, 1, 0.35 * clampf((t - 2.9) / 0.4, 0.0, 1.0)))

## The chosen row: a dark band ruled in gold, and a wand either side pointing at the label.
func _draw_menu_mark(ci: CanvasItem, y: float, w: float, a: float) -> void:
	var band := Rect2(MENU_X - 60, y - 2, 120, MENU_STEP - 1)
	var rule := Color("c48a10")
	ci.draw_rect(band, Color(Color("2a1f45"), 0.85 * a))
	for edge: float in [band.position.y, band.end.y - 1.0]:
		ci.draw_rect(Rect2(band.position.x + 8, edge, band.size.x - 16, 1), Color(rule, a))
		ci.draw_rect(Rect2(band.position.x + 2, edge, 4, 1), Color(rule, 0.5 * a))
		ci.draw_rect(Rect2(band.end.x - 6, edge, 4, 1), Color(rule, 0.5 * a))
	var nudge := roundf(sin(t * 5.0))
	var spark := 0.7 + 0.3 * sin(t * 9.0)
	for side: float in [-1.0, 1.0]:
		# The wand's tip is nearest the label; its shaft runs away from it.
		var tip := roundf(MENU_X + side * (w / 2.0 + 7.0 + nudge))
		ci.draw_rect(Rect2(minf(tip + side * 2.0, tip + side * 9.0), y + 3, 8, 1), Color(rule, a))
		ci.draw_rect(Rect2(tip + side * 10.0, y + 3, 1, 1), Color(Color("7a2f14"), a))
		ci.draw_rect(Rect2(tip - 1.0, y + 3, 3, 1), Color(Color("fff6c0"), a * spark))
		ci.draw_rect(Rect2(tip, y + 2, 1, 3), Color(Color("fff6c0"), a * spark))
		ci.draw_rect(Rect2(tip, y + 3, 1, 1), Color(1, 1, 1, a))

## Meta unlocks: crystals earned in runs buy permanent head starts for every run (never sold for money). Nine rows,
## 11 px apart as on HOW TO PLAY's board, under the two near staffs' heads and between their shafts (TitleArt.STAFFS):
## a name of 17 letters ends 5 px before its pips, the longest words (THE HEAD START's) 14 px before WIN SEAL VII.
func _draw_unlocks(ci: CanvasItem) -> void:
	var prof: Profile = Save.profile
	_panel(ci, Rect2(32, 116, 416, 132))
	PixelFont.draw_centered(ci, "UNLOCKS  -  %d CRYSTALS" % prof.crystals, 240, 122, 1, Color("8bdcff"))
	menu_items.clear()
	var shelf := Profile.shelf()
	for pos in shelf.size():
		var i: int = shelf[pos]
		var row: Array = Profile.META[i]
		var y := UNLOCK_ROW_Y + pos * UNLOCK_ROW_STEP
		var picked := pos == unlock_sel
		menu_items.append(Rect2(38, y - 2, 404, 11))
		if picked:
			Occult.highlight(ci, Rect2(38, y - 2, 404, 11), t)
		var lv := prof.level(row[0])
		var mx := Profile.max_level(i)
		PixelFont.draw(ci, row[1], Vector2(44, y), 1, Color("ffd94d") if picked else Color.WHITE)
		for k in mx:
			ci.draw_rect(Rect2(150 + k * 7, y + 1, 5, 5), Color("8bdcff") if k < lv else Color("3a2f55"))
		PixelFont.draw(ci, row[2], Vector2(190, y), 1, Color("b8a8d8"))
		var why := prof.closed_why(i)
		var cost := prof.next_cost(i)
		var price := why if why != "" else "%d" % cost
		var pc := Color("8bff9e") if why == Profile.WHY_MAX else (Color("b8a8d8") if why != "" else
			(Color("8bdcff") if cost <= prof.crystals else Color("ff7a8a")))
		PixelFont.draw(ci, price, Vector2(436 - PixelFont.text_width(price, 1), y), 1, pc)
	PixelFont.draw_centered(ci, "ENTER/A: BUY    ESC/B: BACK", 240, 236, 1, Color(1, 1, 1, 0.5))

## `pos` is a place on the shelf (Profile.shelf), as unlock_sel and menu_items count them.
func _buy_unlock(pos: int) -> void:
	var shelf := Profile.shelf()
	if pos < 0 or pos >= shelf.size():
		return
	var i: int = shelf[pos]
	if Save.profile.buy(i):
		Save.write()
		Sfx.play("powerup")
		fx.burst(Vector2(240, UNLOCK_ROW_Y + pos * UNLOCK_ROW_STEP), 20, 90.0, 0.5, 1.0, Color.WHITE, Color("8bdcff"), true)
	else:
		Sfx.play("hurt", -6.0)
		var why := Save.profile.closed_why(i)
		_msg("MAXED" if why == Profile.WHY_MAX else (why if why != "" else "NOT ENOUGH CRYSTALS"))

func _device_name(d: int) -> String:
	if d == G.DEV_KBM:
		return "TOUCH" if G.touch_active else "KEYBOARD"
	if d == G.DEV_KB2:
		return "KEYBOARD 2"
	return "GAMEPAD %d" % (d + 1)

## Lobby seat height and the Seal row under the seats.
const LOBBY_SEAT_H := 56
const LOBBY_PORTRAIT := Vector2(24, 32)
const LOBBY_SEAL_ROW := Rect2(34, 218, 412, 14)
## The ladder step's mark (`icons/seal_<n>`, `step_wizard`, `step_archmage`, `class_apprentice`) left of its name in
## the seal row, and an apprentice seat's class mark at the seat's foot, px.
const STEP_ICON := 12
const SEAT_ICON := 8
## Seconds an apprentice's seat shows its name before P1's hint for removing it takes the line, and back.
const SEAT_HINT_SWAP := 2.0
var leave_ask := false # the "LEAVE THE LOBBY?" question is open (only player 1's device answers)
const NEWER_SAVE_LINE := "THIS SAVE IS FROM A NEWER VERSION. NOTHING WILL BE SAVED."
var seal_focus := false # player 1 is on the Seal row (up/down), so left/right steps the ladder
var seal_view := 0 # the step the row shows; Net.seal unless player 1 has browsed onto a locked one

func _draw_lobby(ci: CanvasItem) -> void:
	var title := "LOCAL PLAY"
	if Net.mode == Net.Mode.HOST:
		title = "HOSTING LAN GAME"
	elif Net.mode == Net.Mode.CLIENT:
		title = "LAN LOBBY"
	_panel(ci, Rect2(24, 130, 432, 122))
	PixelFont.draw_centered(ci, title, 240, 135, 1, Color("ffd94d"))
	_draw_seats(ci)
	_draw_seal_row(ci)
	var foot := ""
	if Net.mode == Net.Mode.CLIENT:
		foot = "WAITING FOR HOST TO START..."
	elif G.touch_active:
		foot = "TAP HERE TO START"
	elif leave_ask:
		foot = "LEAVE THE LOBBY?  ENTER/A: YES  ESC/B: NO"
	else:
		foot = "LEFT/RIGHT: HERO  H/RB: HEROES  UP/DOWN: SEAL  ENTER/START: BEGIN  ESC/B: BACK"
	var foot_col := Color("8bff9e") if int(t * 2) % 2 == 0 else Color.WHITE
	if leave_ask:
		foot_col = Color("ffb347")
	PixelFont.draw_centered(ci, foot, 240, 236, 1, foot_col)
	if Net.mode == Net.Mode.HOST:
		var ips := Net.local_ips()
		var ip_text = "YOUR IP: " + (ips[0] if ips.size() > 0 else "?")
		PixelFont.draw_centered(ci, ip_text, 240, 258, 1, Color("c9b8ff"))

## The four seats of the lobby, LOBBY_SEAT_H tall: the seat number and wizard name on the top row, the wizard
## drawn at 1x, then the spell it starts with and who plays it.
func _draw_seats(ci: CanvasItem) -> void:
	if Platform.ready_ok and Net.mode != Net.Mode.CLIENT:
		var inv := "I/SELECT: INVITE"
		PixelFont.draw(ci, inv, Vector2(450 - PixelFont.text_width(inv, 1), 135), 1, Color("8bdcff"))
	# P1's two hints (LobbyRules): on the one empty seat the next apprentice takes, and on the apprentice a removal
	# takes. A LAN client cannot add or remove one and sees neither.
	var seated := _lobby_seated()
	var hints: bool = Net.mode != Net.Mode.CLIENT and not seated.is_empty()
	var pad: bool = hints and seated[0] != G.DEV_KBM
	var taken: Array[int] = []
	for e in Net.roster:
		taken.append(int(e.slot))
	var add_slot: int = LobbyRules.add_hint_slot(taken, G.MAX_PLAYERS) if hints else -1
	var aps: Array = Net.ai_slots()
	var remove_slot: int = int(aps[aps.size() - 1].slot) if hints and not aps.is_empty() else -1
	for slot in 4:
		var r := Rect2(34 + slot * 106, 148, 96, LOBBY_SEAT_H)
		var entry = null
		for e in Net.roster:
			if e.slot == slot:
				entry = e
		var wiz: int = int(entry.get("wizard", slot)) if entry else slot
		var col: Color = Sprites.PLAYER_COLORS[wiz].robe
		ci.draw_rect(r, Color(col.r, col.g, col.b, 0.12 if entry else 0.04))
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), col if entry else col.darkened(0.6))
		PixelFont.draw(ci, "P%d" % (slot + 1), r.position + Vector2(4, 4), 1, col)
		if entry:
			var ai := bool(entry.get("ai", false))
			if ai:
				# An apprentice: its wizard, the spell it starts with, and a dashed hem (X or - unseats it).
				var key := "wiz%d_down_%s" % [wiz, "a" if int(t * 3 + slot) % 2 == 0 else "b"]
				Sprites.draw_at(ci, key, r.position + Vector2(48, 38))
				PixelFont.draw_centered(ci, Wizards.title(wiz), r.position.x + 55, r.position.y + 4, 1,
					Sprites.PLAYER_COLORS[wiz].fx)
				for x in range(int(r.position.x) + 2, int(r.end.x) - 2, 6):
					ci.draw_rect(Rect2(x, r.end.y - 1, 3, 1), Color(col, 0.7))
				Still.draw_icon(ci, Still.APPRENTICE_ICON, Rect2(r.position.x + 4, r.end.y - 10, SEAT_ICON, SEAT_ICON))
				var spell := Upgrades.display_name(Upgrades.weapon_entry(Wizards.start_spell(wiz)))
				PixelFont.draw_centered(ci, spell, r.get_center().x, r.end.y - 16, 1, Color("c9b8ff"))
			else:
				_draw_seat_hero(ci, r, entry, wiz)
			var cx := r.get_center().x
			var who := _device_name(entry.device) if entry.peer == Net.my_peer else "LAN PLAYER"
			var who_col := Color.WHITE
			if ai:
				who = "APPRENTICE"
				who_col = Color("8bff9e")
				if slot == remove_slot and int(t / SEAT_HINT_SWAP) % 2 == 1:
					who = LobbyRules.remove_hint(pad)
					who_col = Color(0.55, 1.0, 0.62)
			elif bool(entry.get("away", false)):
				who = "AWAY"
				who_col = Color("ffb347")
			PixelFont.draw_centered(ci, who, cx, r.end.y - 8, 1, who_col)
		else:
			# An empty seat at the coven: the wizard's shadow between two candles, waiting for a player.
			var seat := r.position + Vector2(48, 38)
			Sprites.draw_at(ci, "wiz%d_down_a" % slot, seat, false, false, Color(0.12, 0.06, 0.22, 0.75))
			Occult.candle(ci, seat + Vector2(-26, 0), t, slot * 3, 7)
			Occult.candle(ci, seat + Vector2(26, 0), t, slot * 3 + 1, 9)
			var blink := 0.35 + 0.25 * sin(t * 4.0 + slot)
			PixelFont.draw_centered(ci, "A/ENTER: JOIN", r.get_center().x, r.end.y - 16, 1, Color(1, 1, 1, blink))
			if slot == add_slot:
				PixelFont.draw_centered(ci, LobbyRules.add_hint(pad), r.get_center().x, r.end.y - 8, 1, Color(0.55, 1.0, 0.62, blink))

## The hero list closed: the seats re-read their heroes (one may have been made or deleted), then the seat that
## opened it takes the one picked when no other local seat holds it.
func _hero_roster_closed() -> void:
	Net.refresh_seat_heroes()
	if hero_roster.picked >= 0:
		Net.set_seat_hero(hero_roster_dev, hero_roster.picked)
	hero_roster_dev = -99
	Sfx.play("menu_select")

## A human seat's hero: the small portrait, name, race, class, level and role. A seat whose row has no hero (a
## scripted run, a LAN client not heard from yet) shows the guest.
func _draw_seat_hero(ci: CanvasItem, r: Rect2, entry: Dictionary, wiz: int) -> void:
	var hd: Dictionary = entry.get("hero", {})
	var h := Hero.from_dict(hd) if not hd.is_empty() else Net.guest_hero(int(entry.get("slot", 0)))
	var fx: Color = Sprites.PLAYER_COLORS[wiz].fx
	PixelFont.draw_centered(ci, h.name, r.position.x + 55, r.position.y + 4, 1, fx)
	var pr := Rect2(r.position + Vector2(4, 13), LOBBY_PORTRAIT)
	ci.draw_rect(pr.grow(1), Color(fx, 0.8))
	ci.draw_rect(pr, Color("0e0a14"))
	if not Art.draw(ci, "portraits/heroes", "hero_%s_%s" % [Races.key(h.race), Classes.key(h.cls)], pr):
		DialogueBox.draw_stand_in(ci, pr, "")
	var tx := pr.end.x + 6
	PixelFont.draw(ci, Races.race_name(h.race), Vector2(tx, r.position.y + 14), 1, Color("e8dcc0"))
	PixelFont.draw(ci, Classes.class_name_of(h.cls), Vector2(tx, r.position.y + 22), 1, Color("e8dcc0"))
	PixelFont.draw(ci, "LV %d" % h.level, Vector2(tx, r.position.y + 30), 1, Color("ffd94d"))
	# The role's first word (TANK AND SUPPORT reads TANK here: the seat is narrow).
	PixelFont.draw(ci, String(Classes.ROLE_NAMES[Classes.role(h.cls)]).get_slice(" ", 0), Vector2(tx, r.position.y + 38), 1, Color("c9b8ff"))
	if entry.peer == Net.my_peer and int(t * 2) % 2 == 0:
		PixelFont.draw(ci, "<", Vector2(r.position.x + 2, r.end.y - 8), 1, Color.WHITE)
		PixelFont.draw(ci, ">", Vector2(r.end.x - 7, r.end.y - 8), 1, Color.WHITE)

## The row under the seats where player 1 picks the run's step on the difficulty ladder (Seals): its name, its
## rule, the crystal multiplier and the unclaimed first-win prize. Player 1 moves onto it with up/down and steps
## with left/right; locked steps show (dim, LOCKED) but are never picked, so the run keeps the last open one.
## A client shows the host's pick.
func _draw_seal_row(ci: CanvasItem) -> void:
	var r := LOBBY_SEAL_ROW
	var host := Net.mode != Net.Mode.CLIENT
	if not seal_focus or not host:
		seal_view = Net.seal
	var prof: Profile = Save.profile
	var open := not host or prof.seal_open(seal_view)
	var texts := Seals.row(seal_view, open, prof.prize_left(seal_view) if host else 0)
	if seal_focus and host:
		Occult.highlight(ci, r, t)
	else:
		ci.draw_rect(r, Color(1, 1, 1, 0.04))
	var y := r.position.y + 4
	var col := Color("ffb347") if seal_view > 0 else (Color("8bff9e") if seal_view < 0 else Color("ffd94d"))
	if not open:
		col = Color(col, 0.4)
	var nx := r.position.x + 4
	var step_tex := Still.icon(Still.step_icon(seal_view), STEP_ICON)
	if step_tex != null:
		ci.draw_texture(step_tex, Vector2(nx, r.position.y + 1).floor(), Color(1, 1, 1, 1.0 if open else 0.4))
		nx += STEP_ICON + 3
	PixelFont.draw(ci, texts[0], Vector2(nx, y), 1, col)
	var rw := PixelFont.text_width(texts[2], 1)
	PixelFont.draw(ci, texts[2], Vector2(r.end.x - 4 - rw, y), 1, Color("8bdcff") if open else Color(1, 1, 1, 0.4))
	var left := nx + PixelFont.text_width(texts[0], 1)
	PixelFont.draw_centered(ci, texts[1], (left + r.end.x - 4 - rw) / 2.0, y, 1, Color("e8dcc0") if open else Color(1, 1, 1, 0.4))
	if seal_focus and host and int(t * 2) % 2 == 0:
		if seal_view > Seals.MIN:
			PixelFont.draw(ci, "<", Vector2(r.position.x - 7, y), 1, Color.WHITE)
		if seal_view < Seals.MAX:
			PixelFont.draw(ci, ">", Vector2(r.end.x + 2, y), 1, Color.WHITE)


## A stale Net.seal (kept from another host's lobby as a client) can be locked on this profile: entering the lobby
## as host or offline and starting a run fall back to an open step (Profile.playable_seal). Not on a client.
func _clamp_lobby_seal() -> void:
	if Net.mode != Net.Mode.CLIENT:
		Net.set_seal(Save.profile.playable_seal(Net.seal))


## Where a lobby tap lands: -1 or 1 on the Seal row's left or right half (step the ladder), 2 below the row
## (start), 0 anywhere else.
static func lobby_tap_zone(at: Vector2) -> int:
	if LOBBY_SEAL_ROW.has_point(at):
		return -1 if at.x < LOBBY_SEAL_ROW.get_center().x else 1
	return 2 if at.y >= LOBBY_SEAL_ROW.end.y else 0


## Player 1 steps the ladder: the row shows every step, an open one becomes the run's (Net.set_seal).
func _step_seal(d: int) -> void:
	seal_view = clampi(seal_view + d, Seals.MIN, Seals.MAX)
	if Save.profile.seal_open(seal_view):
		Net.set_seal(seal_view)
	Sfx.play("menu_move")


## The local device of player 1 (the lowest seat a human on this machine sits in), or -99.
func _p1_device() -> int:
	for e in Net.roster:
		if e.peer == Net.my_peer and not bool(e.get("ai", false)):
			return int(e.device)
	return -99


## The local human devices in seat order (player 1 first), for LobbyRules.
func _lobby_seated() -> Array[int]:
	var out: Array[int] = []
	for e in Net.roster:
		if e.peer == Net.my_peer and not bool(e.get("ai", false)) and not out.has(int(e.device)):
			out.append(int(e.device))
	for d in G.local_devices:
		if not out.has(d):
			out.append(d) # asked for, the host has not answered yet
	return out


## Another human holds a seat besides player 1: a second local device, or (host / offline) a LAN client.
func _lobby_other_human() -> bool:
	var n := 0
	for e in Net.roster:
		if bool(e.get("ai", false)):
			continue
		if Net.mode != Net.Mode.CLIENT or e.peer == Net.my_peer:
			n += 1
	return n >= 2


## The device a lobby press came from. A keyboard press that is not an arrow (Esc, +, -) belongs to the first
## keyboard seated, so a keyboard 2 player 1 can still go back.
func _lobby_actor(event: InputEvent, seated: Array[int]) -> int:
	if event is InputEventKey:
		if seated.has(G.DEV_KBM):
			return G.DEV_KBM
		if seated.has(G.DEV_KB2):
			return G.DEV_KB2
	return _event_device(event)


## Player 1 leaves the lobby for the title: the party is gone, LAN closed.
func _leave_lobby() -> void:
	Sfx.play("menu_select")
	Net.shutdown()
	G.local_devices.clear()
	seal_focus = false
	leave_ask = false
	state = S.MAIN


## The device a key or pad event came from (keyboard seat 2 for its keys while it is seated), or -99.
static func _event_device(event: InputEvent) -> int:
	return PlayerInput.key_device(event)


## The lobby's own buttons: 1 adds an apprentice (Y, +), -1 removes one (X, -), 2 starts the run (START, Enter),
## 3 invites friends (SELECT, I), 4 opens the hero list (right bumper, H), 0 none.
static func lobby_button(event: InputEvent) -> int:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_Y: return 1
			JOY_BUTTON_X: return -1
			JOY_BUTTON_START: return 2
			JOY_BUTTON_BACK: return 3
			JOY_BUTTON_RIGHT_SHOULDER: return 4
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_EQUAL, KEY_KP_ADD, KEY_PLUS: return 1
			KEY_MINUS, KEY_KP_SUBTRACT: return -1
			KEY_ENTER, KEY_KP_ENTER: return 2
			KEY_I: return 3
			KEY_H: return 4
	return 0

func _draw_join(ci: CanvasItem) -> void:
	_panel(ci, Rect2(80, 140, 320, 112))
	PixelFont.draw_centered(ci, "JOIN LAN GAME", 240, 145, 1, Color("ffd94d"))
	var ips := Net.found_games.keys()
	var y := 160
	if ips.is_empty():
		PixelFont.draw_centered(ci, "SEARCHING" + ".".repeat(int(t * 3) % 4), 240, y + 4, 1, Color(1, 1, 1, 0.6))
	menu_items.clear()
	for i in ips.size():
		var g: Dictionary = Net.found_games[ips[i]]
		var s := i == join_sel
		var label := "%s  %s  %d/4" % [g.name, ips[i], g.players]
		menu_items.append(Rect2(90, y - 3, 300, 13))
		if s:
			Occult.highlight(ci, Rect2(90, y - 3, 300, 13), t)
		PixelFont.draw_centered(ci, label, 240, y, 1, Color("ffd94d") if s else Color.WHITE)
		y += 14
	var manual_sel := join_sel == ips.size()
	var my := 184
	menu_items.append(Rect2(90, my - 3, 300, 13))
	if manual_sel:
		Occult.highlight(ci, Rect2(90, my - 3, 300, 13), t)
	PixelFont.draw_centered(ci, "SPEAK AN ADDRESS ON THE BOARD", 240, my, 1, Color("ffd94d") if manual_sel else Color(1, 1, 1, 0.7))
	PixelFont.draw_centered(ci, "ESC/B: BACK", 240, 236, 1, Color(1, 1, 1, 0.5))

func _draw_howto(ci: CanvasItem) -> void:
	_panel(ci, Rect2(30, 142, 420, 112))
	var lines := [
		["MOVE", "WASD / LEFT STICK / LEFT THUMB"],
		["CAST", "ARROWS, MOUSE / RIGHT STICK / RIGHT THUMB"],
		["NOVA", "SPACE, RIGHT CLICK / RB, A / NOVA BUTTON"],
		["PAUSE", "ESC / START"],
		["", ""],
		["SPELLS", "CAST THEMSELVES. LEVEL UP: E / LB FOR CARDS"],
		["LOOT", "CHESTS FROM ELITES. CAST RUNES AT THE ALTARS"],
		["", "SURVIVE THE HORDE. SLAY THE ARCHLICH AT 15:00 TO WIN."],
		["", "EVERY RUN EARNS CRYSTALS FOR UNLOCKS."],
	]
	var y := 149
	for l in lines:
		PixelFont.draw(ci, l[0], Vector2(40, y), 1, Color("ffd94d"))
		PixelFont.draw(ci, l[1], Vector2(84, y), 1, Color.WHITE)
		y += 11
	PixelFont.draw_centered(ci, "PRESS ANY BUTTON", 240, 250, 1, Color(1, 1, 1, 0.5))

# ================================================================ INPUT ===
func _unhandled_input(event: InputEvent) -> void:
	var tap = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	var tap_pos: Vector2 = event.position if tap else Vector2.ZERO
	if event is InputEventMouseMotion and state == S.MAIN:
		for i in menu_items.size():
			if menu_items[i].has_point(event.position) and sel != i:
				sel = i
				Sfx.play("menu_move")
	var dev := PlayerInput.confirm_device(event)
	var back := PlayerInput.back_pressed(event)
	var dir := PlayerInput.menu_dir(event)
	if tap and state == S.MAIN and t >= 2.6 and _title_secret(tap_pos):
		return
	match state:
		S.INTRO:
			if dev != -99 or tap:
				state = S.MAIN
				t = maxf(t, 3.2)
		S.MAIN:
			if t < 2.6:
				return
			var items := _visible_menu()
			if dir != 0:
				sel = wrapi(sel + dir, 0, items.size())
				Sfx.play("menu_move")
			if tap:
				for i in menu_items.size():
					if menu_items[i].has_point(tap_pos):
						sel = i
						_activate(items[i], G.DEV_KBM)
						return
			if dev != -99:
				_activate(items[sel], dev)
		S.LOBBY:
			if hero_roster.active:
				if hero_roster.handle(event):
					_hero_roster_closed()
				return
			var button := lobby_button(event)
			var host := Net.mode != Net.Mode.CLIENT
			var seated := _lobby_seated()
			var rb := LobbyRules.B_NONE
			var actor := -99
			if back:
				rb = LobbyRules.B_BACK
				actor = _lobby_actor(event, seated)
			elif button == 1 or button == -1:
				rb = LobbyRules.B_ADD if button == 1 else LobbyRules.B_REMOVE
				actor = _lobby_actor(event, seated)
			elif dev != -99:
				rb = LobbyRules.B_CONFIRM
				actor = dev
				if event is InputEventKey and not seated.is_empty() and seated[0] == G.DEV_KB2 and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
					actor = G.DEV_KB2 # Enter is seat 2's key as well
			var act := LobbyRules.decide(actor, seated, _lobby_other_human(), leave_ask, rb) if rb != LobbyRules.B_NONE else LobbyRules.NONE
			if leave_ask:
				if act == LobbyRules.LEAVE:
					_leave_lobby()
				elif act == LobbyRules.CLOSE:
					leave_ask = false
					Sfx.play("menu_select")
				return
			match act:
				LobbyRules.LEAVE:
					_leave_lobby()
					return
				LobbyRules.ASK:
					leave_ask = true
					Sfx.play("menu_select")
					return
				LobbyRules.LEAVE_SEAT:
					Net.remove_local_device(actor)
					if hero_roster_dev == actor:
						hero_roster_dev = -99
					Sfx.play("menu_select")
					return
				LobbyRules.ADD_APPRENTICE:
					if host and Net.add_apprentice() >= 0:
						Sfx.play("powerup")
					return
				LobbyRules.REMOVE_APPRENTICE:
					if host and Net.remove_apprentice():
						Sfx.play("menu_select")
					return
				LobbyRules.JOIN:
					Net.add_local_device(actor)
					Sfx.play("powerup")
					return
			if rb == LobbyRules.B_BACK or rb == LobbyRules.B_ADD or rb == LobbyRules.B_REMOVE:
				return # a device that holds no seat, or a seat that may not
			if tap:
				# Touch steps the ladder on the row itself and never takes keyboard focus there.
				var zone := lobby_tap_zone(tap_pos)
				if absi(zone) == 1 and Net.mode != Net.Mode.CLIENT:
					_step_seal(zone)
				elif zone == 2 and Net.mode != Net.Mode.CLIENT:
					_begin()
				return
			if button == 3:
				Platform.invite_friends()
				return
			if button == 4:
				var hd := _event_device(event)
				if G.local_devices.has(hd):
					hero_roster_dev = hd
					hero_roster.open(Save.profile, hd)
					Sfx.play("menu_select")
				return
			# Player 1's START begins the run; a joined device's A (or any other confirm) never does.
			var presser := _event_device(event)
			if button == 2 and event is InputEventKey and _p1_device() == G.DEV_KB2:
				presser = G.DEV_KB2 # Enter is seat 2's key as well
			if button == 2 and G.local_devices.has(presser):
				if host and presser == _p1_device():
					_begin()
				return
			var side: Array = PlayerInput.menu_side(event)
			# Player 1 alone moves onto the Seal row (up/down) and steps the ladder there (left/right).
			var p1 := _p1_device()
			if Net.mode != Net.Mode.CLIENT and p1 != -99:
				if dir != 0 and _event_device(event) == p1:
					seal_focus = dir > 0
					Sfx.play("menu_move")
					return
				if seal_focus and int(side[1]) != 0 and int(side[0]) == p1:
					_step_seal(int(side[1]))
					return
			if int(side[1]) != 0 and G.local_devices.has(int(side[0])):
				Net.step_seat_hero(int(side[0]), int(side[1]))
				Sfx.play("menu_move")
				return
		S.JOIN:
			var n := Net.found_games.size() + 1
			if back:
				Net.stop_discovery()
				state = S.MAIN
				Sfx.play("menu_select")
				return
			if dir != 0:
				join_sel = wrapi(join_sel + dir, 0, n)
				Sfx.play("menu_move")
			if tap:
				for i in menu_items.size():
					if menu_items[i].has_point(tap_pos):
						join_sel = i
						if i < Net.found_games.size():
							_join(Net.found_games.keys()[i])
						else:
							_open_ouija()
				return
			if dev != -99:
				if join_sel < Net.found_games.size():
					_join(Net.found_games.keys()[join_sel])
				else:
					_open_ouija()
		S.OUIJA:
			_ouija_input(event, tap, tap_pos)
		S.OPTIONS:
			if options.handle(event):
				state = S.MAIN
		S.CARDS:
			if album.handle(event):
				state = S.MAIN
		S.CREDITS:
			if credits.handle(event):
				state = S.MAIN
		S.TALE:
			if back:
				_end_tale()
			elif dev != -99 or tap:
				_turn_page()
		S.JOINING:
			if back:
				Net.shutdown()
				state = S.MAIN
		S.HOWTO:
			if dev != -99 or back or tap:
				state = S.MAIN
				Sfx.play("menu_select")
		S.UNLOCKS:
			if back:
				Sfx.play("menu_select")
				if G.title_shop:
					G.title_shop = false
					if G.title_lobby_device != -99: # the hub's walking device, carried through the shop
						G.local_devices = [G.title_lobby_device]
						G.title_lobby_device = -99
					G.goto_sanctum()
					return
				state = S.MAIN
				return
			if dir != 0:
				unlock_sel = wrapi(unlock_sel + dir, 0, Profile.shelf().size())
				Sfx.play("menu_move")
			if tap:
				for i in menu_items.size():
					if menu_items[i].has_point(tap_pos):
						unlock_sel = i
						_buy_unlock(i)
				return
			if dev != -99:
				_buy_unlock(unlock_sel)

## Clicks on the scenery: the moon turns to blood, a ghost leaves the lit window at the top of the tower. Each is
## a secret the first time. The window lies inside the moon's disc, so it is asked first.
func _title_secret(at: Vector2) -> bool:
	var key := ""
	if TOP_WINDOW.has_point(at):
		if ghost_t >= 0.0:
			return false
		ghost_t = 0.0
		key = "ghost"
		Sfx.play("ghost")
		_msg("SOMEONE STILL LIVES IN THE TOWER")
	elif at.distance_to(MOON) < TitleArt.MOON_R and eclipse <= 0.0:
		eclipse = ECLIPSE_LIFE
		key = "eclipse"
		Sfx.play("bell_toll")
		Sfx.play("boss_roar", -14.0, 0.6)
		_msg("THE MOON BLEEDS")
	else:
		return false
	message_t = 3.0
	if Save.profile.find_secret(key):
		Save.write()
		fx.text(at + Vector2(0, -12), "SECRET FOUND", Color("8bdcff"), 2.0)
	return true


func _activate(item: String, dev: int) -> void:
	Sfx.play("menu_select")
	if item == "PLAY" and not Save.settings.seen_prologue:
		_start_tale("PLAY", dev)
		return
	match item:
		"THE TALE":
			_start_tale("", dev)
		"PLAY":
			# Play goes through the Sanctum; its portal leads on to the lobby.
			G.local_devices = [dev]
			G.goto_sanctum()
		"HOST LAN GAME":
			G.local_devices = [dev]
			if Net.host_game():
				_clamp_lobby_seal()
				state = S.LOBBY
				_flash_burst()
			else:
				G.local_devices.clear()
		"JOIN LAN GAME":
			G.local_devices = [dev]
			Net.start_discovery()
			join_sel = 0
			state = S.JOIN
		"HOW TO PLAY":
			state = S.HOWTO
		"UNLOCKS":
			unlock_sel = 0
			state = S.UNLOCKS
		"CARDS":
			album.open()
			state = S.CARDS
		"OPTIONS":
			options.open()
			state = S.OPTIONS
		"CREDITS":
			credits.open()
			state = S.CREDITS
		"QUIT":
			get_tree().quit()

func _flash_burst() -> void:
	fx.burst(Vector2(240, 190), 40, 160.0, 0.8, 1.0, Color.WHITE, Color("b07bff"), true, 0.0, true)

func _begin() -> void:
	if Net.roster.is_empty():
		return
	_clamp_lobby_seal()
	Sfx.play("wave_start")
	Net.stop_discovery()
	Net.begin_game()

func _join(ip: String) -> void:
	Net.stop_discovery()
	state = S.JOINING
	Net.join_game(ip)

func _start_tale(then: String, dev: int) -> void:
	tale_page = 0
	tale_t = t
	tale_then = then
	tale_dev = dev
	state = S.TALE
	Sfx.play("page_turn")


func _turn_page() -> void:
	if t - tale_t < 0.35:
		return
	if tale_page + 1 >= Lore.PROLOGUE.size():
		_end_tale()
		return
	tale_page += 1
	tale_t = t
	Sfx.play("page_turn")


## Leaves the prologue: back to the menu, or on to PLAY when it opened from there. It is shown once.
func _end_tale() -> void:
	Save.settings.seen_prologue = true
	Save.write_settings()
	state = S.MAIN
	if tale_then != "":
		_activate(tale_then, tale_dev)
	else:
		Sfx.play("menu_select")


## A page of the prologue: an illuminated panel with a scene, the heading and the text, typed in.
func _draw_tale(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.02, 0.0, 0.05, 0.85))
	var page: Array = Lore.PROLOGUE[tale_page]
	var r := Rect2(36, 18, 408, 228)
	Occult.frame(ci, r, t)
	var art := Rect2(r.position.x + 24, r.position.y + 30, r.size.x - 48, 136)
	_draw_tale_art(ci, art, tale_page)
	PixelFont.draw_centered(ci, "%s" % page[0], 240, r.position.y + 10, 2, Occult.GOLD, Occult.INK)
	var shown := mini(String(page[1]).length(), int((t - tale_t) * 45.0))
	TarotArt._wrap_centered(ci, String(page[1]).left(shown), 240, art.end.y + 10, r.size.x - 40, Occult.BONE)
	for i in Lore.PROLOGUE.size():
		ci.draw_rect(Rect2(240 - Lore.PROLOGUE.size() * 5 + i * 10, r.end.y - 14, 6, 2),
			Occult.GOLD if i == tale_page else Color("3a2f55"))
	PixelFont.draw_centered(ci, "ENTER/A: NEXT    ESC/B: SKIP", 240, r.end.y + 8, 1, Color(1, 1, 1, 0.45), Occult.INK)


## The scene for each prologue page, drawn into `a`.
func _draw_tale_art(ci: CanvasItem, a: Rect2, page: int) -> void:
	ci.draw_rect(a, Color("0a0618"))
	for b in 4:
		ci.draw_rect(Rect2(a.position.x, a.position.y + a.size.y * (0.4 + b * 0.15), a.size.x, a.size.y * 0.15 + 1),
			[Color("150c2a"), Color("23123a"), Color("3a1a40"), Color("4a2040")][b])
	for i in 40:
		var sx := a.position.x + fposmod(i * 53.0, a.size.x)
		var sy := a.position.y + fposmod(i * 29.0, a.size.y * 0.5)
		ci.draw_rect(Rect2(sx, sy, 1, 1), Color(1, 1, 1, 0.3 + 0.5 * absf(sin(t * 1.5 + i))))
	var ground := a.end.y - 14
	var k := t - tale_t
	match page:
		0:
			# The black comet over Aldermoor: a dark head with a burning tail, the village and its graves.
			var head := a.position + Vector2(a.size.x * 0.72 - k * 6.0, 26 + k * 2.0)
			for i in 30:
				var q := head + Vector2(i * 4.0, -i * 1.6)
				ci.draw_circle(q, 6.0 - i * 0.18, Color(1.0, 0.3 + i * 0.01, 0.6, 0.5 - i * 0.016))
			ci.draw_circle(head, 6.0, Color("1a0f24"))
			ci.draw_arc(head, 6.0, 0, TAU, 16, Color("ff4df2"), 1.0)
			for i in 9:
				var hx := a.position.x + 20 + i * 38
				var hh := 12 + (i * 7) % 10
				ci.draw_rect(Rect2(hx, ground - hh, 22, hh), Color("0b0716"))
				ci.draw_colored_polygon(PackedVector2Array([Vector2(hx - 2, ground - hh), Vector2(hx + 11, ground - hh - 8),
					Vector2(hx + 24, ground - hh)]), Color("0b0716"))
				if (i + int(t * 0.5)) % 3 != 0:
					ci.draw_rect(Rect2(hx + 8, ground - hh + 4, 3, 3), Color("ffcf5a"))
			for i in 6:
				var gx := a.position.x + 40 + i * 58
				ci.draw_rect(Rect2(gx, ground + 4, 5, 7), Color("6c6480"))
				ci.draw_rect(Rect2(gx - 1, ground + 6, 7, 2), Color("6c6480"))
		1:
			# Morvane reads the ninth page: the Lich over a burning book.
			var c := Vector2(a.get_center().x, ground + 8)
			ci.draw_circle(c + Vector2(0, -34), 34.0, Color(0.5, 0.1, 0.8, 0.12 + 0.05 * sin(t * 3.0)))
			Sprites.draw_at(ci, "lich", c, false, false, Color.WHITE, 2.0)
			var book := Rect2(c.x - 22, c.y - 10, 44, 12)
			ci.draw_rect(book.grow(1), Color("1a0f24"))
			ci.draw_rect(book, Color("e8dcc0"))
			ci.draw_rect(Rect2(book.get_center().x, book.position.y, 1, book.size.y), Color("8a7a60"))
			for l in 3:
				ci.draw_rect(Rect2(book.position.x + 3, book.position.y + 3 + l * 3, 16, 1), Color("8a1a2a"))
			for i in 6:
				var f := fposmod(t * 30.0 + i * 13.0, 40.0)
				ci.draw_rect(Rect2(book.position.x + 6 + i * 6, book.position.y - f * 0.6, 1, 2), Color(1.0, 0.6, 0.2, 1.0 - f / 40.0))
		2:
			# The tower and the horde climbing it.
			var tx := a.get_center().x
			ci.draw_rect(Rect2(tx - 22, a.position.y + 14, 44, ground - a.position.y - 14), Color("1e1830"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(tx - 28, a.position.y + 16), Vector2(tx, a.position.y - 2),
				Vector2(tx + 28, a.position.y + 16)]), Color("2a1650"))
			for wy in 4:
				ci.draw_rect(Rect2(tx - 3, a.position.y + 26 + wy * 20, 6, 8), Color("ffcf5a") if wy != int(t) % 4 else Color("ff4df2"))
			for i in 10:
				var u := fposmod(i * 0.1 + t * 0.05, 1.0)
				var side := -1.0 if i % 2 == 0 else 1.0
				var p := Vector2(tx + side * (60.0 + (1.0 - u) * 100.0), ground)
				Sprites.draw_at(ci, "skeleton_a" if int(t * 4.0 + i) % 2 == 0 else "skeleton_b", p, side > 0)
		3:
			# The last coven, with the cards drawn over their heads.
			for w in 4:
				var p := Vector2(a.position.x + a.size.x * (0.2 + w * 0.2), ground + 6)
				Sprites.draw_at(ci, "wiz%d_down_a" % w if int(t * 2.0 + w) % 2 == 0 else "wiz%d_down_b" % w, p, false, false,
					Color.WHITE, 2.0)
				var cr := Rect2(p.x - 8, a.position.y + 8 + sin(t * 2.0 + w) * 2.0, 16, 26)
				TarotArt.draw_back(ci, cr)
				ci.draw_circle(cr.get_center(), 12.0, Color(Sprites.PLAYER_COLORS[w].fx, 0.12))
	_box_px(ci, a, Color("4b2ab8"))


func _box_px(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), c)
	ci.draw_rect(Rect2(Vector2(r.position.x, r.end.y - 1), Vector2(r.size.x, 1)), c)
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), c)
	ci.draw_rect(Rect2(Vector2(r.end.x - 1, r.position.y), Vector2(1, r.size.y)), c)


func _open_ouija() -> void:
	# Letters too: the spirits answer a few words besides addresses (Secrets.WORDS).
	ouija = Ouija.new("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.")
	planchette = _ouija_pos(ouija.row, ouija.col)
	state = S.OUIJA
	Sfx.play("whisper")


func _submit_ouija() -> void:
	var ip := ouija.text.strip_edges()
	var reply: Array = Secrets.answer(ip)
	if not reply.is_empty():
		_spirits_answer(reply)
		return
	if ip.is_valid_ip_address():
		Sfx.play("powerup")
		_join(ip)
	else:
		Sfx.play("hurt", -6.0)
		_msg("THE SPIRITS CANNOT FIND THAT ADDRESS")


## The ouija board takes the planchette (arrows, stick, d-pad, mouse) and typed digits on a keyboard.
## The board answers a secret word: the reply on screen, a gust of candle sparks, and a secret (with crystals) the
## first time.
func _spirits_answer(reply: Array) -> void:
	ouija.text = ""
	_msg(String(reply[0]))
	message_t = 4.0
	Sfx.play("whisper")
	Sfx.play("candle", -2.0, 0.8)
	fx.burst(planchette, 24, 70.0, 0.8, 1.2, Occult.FLAME, Occult.BLOOD, true)
	var key: String = reply[1]
	if key != "" and Save.profile.find_secret(key):
		Save.profile.crystals += int(reply[2])
		Save.write()
		fx.text(planchette + Vector2(0, -14), "SECRET FOUND  +%d CRYSTALS" % int(reply[2]), Color("8bdcff"), 2.0)
		Sfx.play("wave_clear", -4.0, 1.3)


func _ouija_input(event: InputEvent, tap: bool, tap_pos: Vector2) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ch := String.chr(event.unicode) if event.unicode > 0 else ""
		if ouija.type_char(ch):
			Sfx.play("menu_move")
			return
		match event.physical_keycode:
			KEY_BACKSPACE:
				if ouija.erase():
					Sfx.play("menu_move")
				return
			KEY_ENTER, KEY_KP_ENTER:
				match ouija.enter():
					Ouija.TYPED, Ouija.ERASED:
						Sfx.play("menu_select")
						fx.burst(_ouija_pos(ouija.row, ouija.col), 8, 40.0, 0.4, 1.0, Occult.FLAME, Occult.BLOOD, true)
					Ouija.SUBMIT:
						_submit_ouija()
					Ouija.CANCEL:
						state = S.JOIN
						Sfx.play("menu_select")
				return
			KEY_ESCAPE:
				state = S.JOIN
				Sfx.play("menu_select")
				return
	if PlayerInput.back_pressed(event):
		state = S.JOIN
		Sfx.play("menu_select")
		return
	var dy := PlayerInput.menu_dir(event)
	var dx := int(PlayerInput.menu_side(event)[1])
	if dx != 0 or dy != 0:
		ouija.move(dx, dy)
		Sfx.play("planchette")
		return
	if event is InputEventMouseMotion:
		var hit: Vector2i = _ouija_hit(event.position)
		if hit.x >= 0 and (hit.x != ouija.row or hit.y != ouija.col) and ouija.point_at(hit.x, hit.y):
			Sfx.play("planchette", -6.0)
		return
	if tap:
		var hit: Vector2i = _ouija_hit(tap_pos)
		if hit.x < 0 or not ouija.point_at(hit.x, hit.y):
			return
	elif PlayerInput.confirm_device(event) == -99:
		return
	match ouija.choose():
		Ouija.TYPED, Ouija.ERASED:
			Sfx.play("menu_select")
			fx.burst(_ouija_pos(ouija.row, ouija.col), 8, 40.0, 0.4, 1.0, Occult.FLAME, Occult.BLOOD, true)
		Ouija.SUBMIT:
			_submit_ouija()
		Ouija.CANCEL:
			state = S.JOIN
			Sfx.play("menu_select")


## Where a mark sits on the board.
func _ouija_pos(r: int, c: int) -> Vector2:
	var n: int = Ouija.LAYOUT[r].size()
	match r:
		0:
			return Vector2(118 if c == 0 else 362, 62)
		1, 2:
			var u := float(c) / (n - 1) * 2.0 - 1.0
			var y := (100.0 if r == 1 else 126.0) - (24.0 if r == 1 else 18.0) * (1.0 - u * u)
			return Vector2(240 + u * (150.0 if r == 1 else 140.0), y)
		3:
			return Vector2(130 + c * 22.0, 152)
	return Vector2(240, 210)


## The mark under a point on screen, as (row, col), or (-1, -1).
func _ouija_hit(p: Vector2) -> Vector2i:
	for r in Ouija.LAYOUT.size():
		for c in Ouija.LAYOUT[r].size():
			var m: String = Ouija.LAYOUT[r][c]
			var half := Vector2(maxf(9.0, PixelFont.text_width(m, 2) / 2.0 + 3.0), 10.0)
			if absf(p.x - _ouija_pos(r, c).x) <= half.x and absf(p.y - _ouija_pos(r, c).y) <= half.y:
				return Vector2i(r, c)
	return Vector2i(-1, -1)


func _draw_ouija(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.02, 0.0, 0.05, 0.78))
	var board := Rect2(52, 30, 376, 214)
	# Old wood: a dark rim, a warm face and faint grain.
	ci.draw_rect(board.grow(3), Occult.INK)
	ci.draw_rect(board, Color("3b2414"))
	ci.draw_rect(board.grow(-4), Color("6b4526"))
	for k in 9:
		var gy := board.position.y + 14 + k * 23 + sin(k * 1.7) * 3.0
		ci.draw_rect(Rect2(board.position.x + 6, gy, board.size.x - 12, 1), Color(0.3, 0.17, 0.08, 0.35))
	Occult._box(ci, board.grow(-7), Color("2a170b"))
	# Sun by YES, moon by NO.
	var sun := Vector2(82, 54)
	ci.draw_circle(sun, 8, Color("2a170b"))
	for k in 8:
		var a := k * TAU / 8.0
		ci.draw_line(sun + Vector2(cos(a), sin(a)) * 10, sun + Vector2(cos(a), sin(a)) * 13, Color("2a170b"), 1.0)
	var moon := Vector2(398, 54)
	ci.draw_circle(moon, 8, Color("2a170b"))
	ci.draw_circle(moon + Vector2(4, -2), 7, Color("6b4526"))
	PixelFont.draw_centered(ci, "SPEAK THE HOST'S ADDRESS", 240, 40, 1, Color("2a170b"))
	for r in Ouija.LAYOUT.size():
		for c in Ouija.LAYOUT[r].size():
			var m: String = Ouija.LAYOUT[r][c]
			var p := _ouija_pos(r, c)
			var on := ouija.enabled(r, c)
			var col := Color("1c0f06") if on else Color(0.17, 0.09, 0.04, 0.35)
			if r == ouija.row and c == ouija.col:
				col = Color("fff0c8")
			PixelFont.draw_centered(ci, m, p.x, p.y - 7, 2, col)
	# What has been spelled so far, on a slate.
	var slate := Rect2(150, 172, 180, 16)
	ci.draw_rect(slate, Color("1c0f06"))
	var shown := ouija.text + ("_" if int(t * 2.0) % 2 == 0 else " ")
	PixelFont.draw_centered(ci, shown, 240, slate.position.y + 5, 1, Occult.BONE)
	_draw_planchette(ci, planchette)
	PixelFont.draw_centered(ci, "MOVE + ENTER/A   OR TYPE THE NUMBERS   ESC/B: BACK", 240, 250, 1, Color(1, 1, 1, 0.5), Occult.INK)


## The planchette: a heart-shaped pointer whose glass eye shows the chosen mark.
func _draw_planchette(ci: CanvasItem, eye: Vector2) -> void:
	var c := eye + Vector2(0, 8)
	var body := PackedVector2Array([c + Vector2(0, -21), c + Vector2(17, -3), c + Vector2(13, 15), c + Vector2(0, 21),
		c + Vector2(-13, 15), c + Vector2(-17, -3)])
	var shadow := PackedVector2Array()
	for v in body:
		shadow.append(v + Vector2(2, 3))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	ci.draw_colored_polygon(body, Occult.BONE)
	body.append(body[0])
	ci.draw_polyline(body, Color("5a4630"), 1.0)
	ci.draw_circle(eye, 9.0, Color("8a5a32"))
	var m := ouija.current()
	if m.length() == 1:
		PixelFont.draw_centered(ci, m, eye.x, eye.y - 7, 2, Color("1c0f06"))
	ci.draw_arc(eye, 9.5, 0.0, TAU, 24, Color("5a4630"), 1.0)
	ci.draw_rect(Rect2(eye + Vector2(-5, -6), Vector2(3, 1)), Color(1, 1, 1, 0.7))
	ci.draw_rect(Rect2(eye + Vector2(-6, -5), Vector2(1, 2)), Color(1, 1, 1, 0.5))
	if m.length() > 1:
		# A word is wider than the glass: it stays readable over the planchette.
		PixelFont.draw_centered(ci, m, eye.x, eye.y - 7, 2, Color("fff0c8"), Color("1c0f06"))

func _on_roster() -> void:
	if leave_ask and not _lobby_other_human():
		leave_ask = false # the other human left meanwhile: nobody is left to ask about
	if state == S.JOINING and Net.mode == Net.Mode.CLIENT:
		state = S.LOBBY
		Sfx.play("powerup")

func _on_conn_failed(reason: String) -> void:
	_msg(reason)
	if state == S.JOINING or state == S.LOBBY:
		state = S.MAIN

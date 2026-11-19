extends Node2D
## Title screen, lobby and LAN browser. Everything is drawn procedurally:
## a twilight sky, a castle on the hill, an animated logo and four wizards
## launching fireworks.

enum S { INTRO, MAIN, LOBBY, JOIN, JOINING, HOWTO, UNLOCKS, OPTIONS, OUIJA }

const MENU := ["PLAY", "UNLOCKS", "HOST LAN GAME", "JOIN LAN GAME", "HOW TO PLAY", "OPTIONS", "QUIT"]

var state := S.INTRO
var t := 0.0
var sel := 0
var join_sel := 0
var unlock_sel := 0
var stars: Array = []
var mountains_a := PackedFloat32Array()
var mountains_b := PackedFloat32Array()
var fx: Fx
var glow: Node2D
var front: Node2D
var lightning := 0.0
var lightning_pts := PackedVector2Array()
var cast_timer := 1.0
var wiz_cast := [0.0, 0.0, 0.0, 0.0]
var message := ""
var message_t := 0.0
var options := OptionsPanel.new()
var ouija := Ouija.new()
var planchette := Vector2(240, 150)
var menu_items: Array = []
var rng := RandomNumberGenerator.new()
var _landed := {}

const WIZ_X := [34, 74, 406, 446]

func _ready() -> void:
	rng.randomize()
	for i in 110:
		stars.append([Vector2(rng.randf_range(0, 480), rng.randf_range(0, 150)), rng.randf() * TAU, rng.randf_range(0.5, 2.5), rng.randi() % 3])
	for x in 481:
		mountains_a.append(175.0 - 40.0 * absf(sin(x * 0.011 + 1.0)) - 18.0 * absf(sin(x * 0.037)) - 6.0 * sin(x * 0.13))
		mountains_b.append(205.0 - 22.0 * absf(sin(x * 0.017 + 3.0)) - 10.0 * absf(sin(x * 0.051)) - 4.0 * sin(x * 0.21))
	glow = Node2D.new()
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = m
	add_child(glow)
	glow.draw.connect(_draw_glow)
	fx = Fx.new()
	add_child(fx)
	front = Node2D.new()
	add_child(front)
	front.draw.connect(_draw_front)
	Net.roster_changed.connect(_on_roster)
	Net.connection_failed.connect(_on_conn_failed)
	Net.games_found_changed.connect(func(): pass)
	Sfx.music("music_title")
	if not G.title_message.is_empty():
		_msg(G.title_message)
		G.title_message = ""
		state = S.MAIN
		t = 4.0
	if Net.mode != Net.Mode.OFFLINE:
		Net.shutdown()
	G.local_devices.clear()

func _msg(s: String) -> void:
	message = s
	message_t = 3.0

# ================================================================ LOOP ===
func _process(delta: float) -> void:
	t += delta
	message_t = maxf(0.0, message_t - delta)
	lightning = maxf(0.0, lightning - delta)
	if state == S.INTRO and t > 3.2:
		state = S.MAIN
	# Occasional lightning strike on the castle spire
	if rng.randf() < delta * 0.12 and lightning <= 0.0:
		lightning = 0.35
		lightning_pts = Fx.jag(Vector2(rng.randf_range(250, 330), 0), Vector2(292, 132), rng, 14.0)
	# Wizards take turns launching fireworks
	cast_timer -= delta
	if cast_timer <= 0.0 and t > 1.0:
		cast_timer = rng.randf_range(0.5, 1.1)
		var w := rng.randi() % 4
		wiz_cast[w] = 0.4
		_launch(w)
	for i in 4:
		wiz_cast[i] = maxf(0.0, wiz_cast[i] - delta)
	_update_rockets(delta)
	# Rising motes of magic
	if rng.randf() < 0.6:
		var c: Color = [Color("c9a6ff"), Color("4dfff0"), Color("ffd94d"), Color("ff7ae6")][rng.randi() % 4]
		fx.spawn(Vector2(rng.randf_range(0, 480), 272), Vector2(rng.randf_range(-6, 6), rng.randf_range(-30, -12)),
			rng.randf_range(3.0, 6.0), 1.0, c, Color(c.r, c.g, c.b, 0.0), true, 0.0)
	# Letter landing impacts
	for li in 2:
		for i in 5:
			var start := 0.15 + (li * 5 + i) * 0.12
			var key := li * 10 + i
			if not _landed.has(key) and t - start > 0.27:
				_landed[key] = true
				var sc := 6 if li == 0 else 8
				var lx := 240.0 - PixelFont.text_width("MAGIC" if li == 0 else "SMASH", sc) / 2.0 + i * 6 * sc + 2.5 * sc
				var ly := (20 if li == 0 else 68) + 7 * sc
				var col := Color("b07bff") if li == 0 else Color("ff8a2a")
				fx.burst(Vector2(lx, ly), 14, 90.0, 0.5, 1.0, Color.WHITE, col, true, 120.0)
				Sfx.play("hit", -6.0, 0.6 + li * 0.15 + i * 0.05, 0.0)
				if li == 1 and i == 4:
					Sfx.play("explode", -4.0, 0.8, 0.0)
					fx.flash(Vector2(240, 96), 120.0, Color(1.0, 0.6, 0.3), 0.25)
	# Logo sparkles
	if t > 2.4 and rng.randf() < 0.3:
		var lp := Vector2(rng.randf_range(150, 330), rng.randf_range(24, 118))
		fx.spawn(lp, Vector2.ZERO, 0.5, 1.0, Color.WHITE, Color("ffd94d"), true, 0.0)
	queue_redraw()
	glow.queue_redraw()
	front.queue_redraw()
	if state == S.OUIJA:
		planchette = planchette.lerp(_ouija_pos(ouija.row, ouija.col), minf(1.0, delta * 14.0))

var rockets: Array = [] # [pos, vel, color, fuse]

func _launch(w: int) -> void:
	var col: Color = Sprites.PLAYER_COLORS[w].fx
	var start := Vector2(WIZ_X[w] + (14 if w < 2 else -14), 210)
	var target := Vector2(rng.randf_range(60, 420), rng.randf_range(20, 110))
	var vel := (target - start).normalized() * rng.randf_range(170, 230)
	rockets.append([start, vel, col, rng.randf_range(0.5, 0.9)])
	Sfx.play("shoot_arcane", -18.0, rng.randf_range(0.8, 1.1), 0.1)

func _update_rockets(delta: float) -> void:
	for r in rockets:
		r[0] += r[1] * delta
		r[1].y += 60.0 * delta
		r[3] -= delta
		fx.spawn(r[0], -r[1] * 0.1, 0.35, 1.0, Color.WHITE, r[2], true, 2.0)
		if r[3] <= 0.0:
			var c: Color = r[2]
			fx.burst(r[0], 36, 110.0, 1.1, 1.0, Color.WHITE, c, true, 45.0, true)
			fx.ring(r[0], 2.0, 26.0, 0.4, c, 1.0)
			fx.flash(r[0], 16.0, c, 0.15)
			Sfx.play("explode", -20.0, rng.randf_range(1.3, 1.8), 0.15)
	rockets = rockets.filter(func(r): return r[3] > 0.0)

# ============================================================= DRAWING ===
func _draw() -> void:
	# Sky: dithered twilight bands
	var bands := [Color("0b0420"), Color("140832"), Color("1f0c45"), Color("2e1255"), Color("47185f"), Color("6a1f66"), Color("932a68"), Color("b8406a")]
	var bh := 24
	for i in bands.size():
		var c: Color = bands[i]
		if lightning > 0.0:
			c = c.lerp(Color("b8b0ff"), lightning * 0.6)
		draw_rect(Rect2(0, i * bh, 480, bh), c)
		if i + 1 < bands.size():
			var n: Color = bands[i + 1]
			for x in range(0, 480, 2):
				draw_rect(Rect2(x + ((i * bh + bh - 2) % 2), i * bh + bh - 2, 1, 1), n)
				draw_rect(Rect2(x + 1, i * bh + bh - 1, 1, 1), n)
	draw_rect(Rect2(0, bands.size() * bh, 480, 270), bands[-1])
	# Stars
	for s in stars:
		var tw := 0.5 + 0.5 * sin(t * s[2] + s[1])
		var c := Color(1, 1, 1, 0.3 + 0.7 * tw)
		if s[3] == 0 and tw > 0.8:
			draw_rect(Rect2(s[0] + Vector2(-1, 0), Vector2(3, 1)), Color(c.r, c.g, c.b, 0.5))
			draw_rect(Rect2(s[0] + Vector2(0, -1), Vector2(1, 3)), Color(c.r, c.g, c.b, 0.5))
		draw_rect(Rect2(s[0], Vector2(1, 1)), c)
	# Moon
	var mc := Vector2(410, 46)
	draw_circle(mc, 20, Color("ffe9c4"))
	draw_circle(mc + Vector2(5, -3), 4, Color("f0d4a8"))
	draw_circle(mc + Vector2(-7, 6), 3, Color("f0d4a8"))
	draw_circle(mc + Vector2(-2, -9), 2, Color("f0d4a8"))
	# Distant mountains
	for x in 480:
		draw_rect(Rect2(x, mountains_a[x], 1, 270 - mountains_a[x]), Color("2a1048"))
	_draw_castle()
	for x in 480:
		draw_rect(Rect2(x, mountains_b[x], 1, 270 - mountains_b[x]), Color("1a0a30"))
	# Foreground ledge
	draw_rect(Rect2(0, 240, 480, 30), Color("0d0618"))
	for x in range(0, 480, 4):
		var h := 2 + int(abs(sin(x * 0.3)) * 3)
		draw_rect(Rect2(x, 240 - h, 4, h), Color("0d0618"))
	draw_rect(Rect2(0, 240, 480, 1), Color("3a1f5a"))

func _draw_castle() -> void:
	var base := Color("150828")
	var cx := 292
	draw_rect(Rect2(cx - 50, 150, 100, 40), base)
	# Towers
	for tw in [[cx - 50, 120, 14], [cx + 36, 112, 14], [cx - 12, 92, 24]]:
		draw_rect(Rect2(tw[0], tw[1], tw[2], 190 - tw[1]), base)
		for b in range(0, tw[2], 4):
			draw_rect(Rect2(tw[0] + b, tw[1] - 3, 2, 3), base)
		# Roof spire
		for k in 12:
			var w: int = maxi(1, tw[2] - k * 2)
			draw_rect(Rect2(tw[0] + (tw[2] - w) / 2, tw[1] - 4 - k * 2, w, 2), base)
	draw_rect(Rect2(cx, 64, 1, 8), base)
	# Battlements
	for b in range(cx - 50, cx + 50, 6):
		draw_rect(Rect2(b, 146, 3, 4), base)
	# Windows with flickering light
	var wins := [Vector2(cx - 45, 130), Vector2(cx + 41, 122), Vector2(cx - 4, 104), Vector2(cx + 2, 104),
		Vector2(cx - 30, 160), Vector2(cx - 10, 165), Vector2(cx + 14, 160), Vector2(cx + 30, 168), Vector2(cx - 2, 124)]
	for i in wins.size():
		var f := 0.7 + 0.3 * sin(t * (3.0 + i) + i * 1.7)
		draw_rect(Rect2(wins[i], Vector2(2, 3)), Color(1.0, 0.75 * f, 0.3 * f))

func _draw_glow() -> void:
	var ci := glow
	ci.draw_circle(Vector2(410, 46), 34, Color(1.0, 0.85, 0.6, 0.08))
	ci.draw_circle(Vector2(410, 46), 26, Color(1.0, 0.85, 0.6, 0.08))
	ci.draw_circle(Vector2(292, 150), 70, Color(1.0, 0.5, 0.3, 0.04))
	if lightning > 0.0:
		var a := lightning / 0.35
		ci.draw_polyline(lightning_pts, Color(0.6, 0.6, 1.0, 0.4 * a), 5.0)
		ci.draw_polyline(lightning_pts, Color(1, 1, 1, a), 1.0)
	for r in rockets:
		ci.draw_circle(r[0], 4, Color(r[2].r, r[2].g, r[2].b, 0.4))
	# Logo glow
	if t > 0.5:
		var a := clampf((t - 0.5) / 1.5, 0.0, 1.0)
		var pulse := 0.8 + 0.2 * sin(t * 2.0)
		ci.draw_circle(Vector2(240, 50), 70 * pulse, Color(0.5, 0.2, 1.0, 0.07 * a))
		ci.draw_circle(Vector2(240, 98), 90 * pulse, Color(1.0, 0.4, 0.1, 0.07 * a))

func _draw_front() -> void:
	var ci := front
	_draw_logo(ci)
	_draw_wizards(ci)
	match state:
		S.INTRO:
			pass
		S.MAIN:
			_draw_menu(ci)
		S.LOBBY:
			_draw_lobby(ci)
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
		S.OUIJA:
			_draw_join(ci)
			_draw_ouija(ci)
	if message_t > 0.0:
		PixelFont.draw_centered(ci, message, 240, 128, 1, Color("ff7a8a"), Color("0b0716"))
	PixelFont.draw(ci, "V" + G.VERSION, Vector2(3, 262), 1, Color(1, 1, 1, 0.3))
	if G.high_score > 0:
		var hs := "BEST %d" % G.high_score
		PixelFont.draw(ci, hs, Vector2(477 - PixelFont.text_width(hs), 262), 1, Color(1, 0.9, 0.4, 0.6))

func _draw_logo(ci: CanvasItem) -> void:
	var lines := [["MAGIC", 6, 20, Color("ffffff"), Color("b07bff"), Color("3a0f7a")],
		["SMASH", 8, 68, Color("fff27a"), Color("ff4a2a"), Color("6a0a1a")]]
	var li := 0
	for L in lines:
		var text: String = L[0]
		var sc: int = L[1]
		var w := PixelFont.text_width(text, sc)
		var x0 := 240.0 - w / 2.0
		for i in text.length():
			# Letters drop in one by one with a bounce
			var start := 0.15 + (li * 5 + i) * 0.12
			var k := clampf((t - start) / 0.45, 0.0, 1.0)
			if k <= 0.0:
				continue
			var drop := (1.0 - _bounce(k)) * -140.0
			var wob := floorf(sin(t * 2.5 + i * 0.7 + li) * 2.0) if t > 2.2 else 0.0
			var ox := x0 + i * (PixelFont.W + 1) * sc
			var oy: float = L[2] + drop + wob
			var cells := PixelFont.cells(text[i])
			# Extruded 3D side
			for d in range(sc, 0, -1):
				for c in cells:
					ci.draw_rect(Rect2(ox + c.x * sc + d * 0.5, oy + c.y * sc + d, sc, sc), L[5].darkened(0.3 * (1.0 - float(d) / sc)))
			# Outline
			for c in cells:
				ci.draw_rect(Rect2(ox + c.x * sc - 2, oy + c.y * sc - 2, sc + 4, sc + 4), Color("0b0716"))
			# Face with gradient + moving shine
			var shine := fmod(t * 140.0, 900.0) - 200.0
			for c in cells:
				var col: Color = L[3].lerp(L[4], c.y / float(PixelFont.H - 1))
				var px := ox + c.x * sc
				var py := oy + c.y * sc
				ci.draw_rect(Rect2(px, py, sc, sc), col)
				ci.draw_rect(Rect2(px, py, sc, 1), col.lightened(0.4))
				ci.draw_rect(Rect2(px, py + sc - 1, sc, 1), col.darkened(0.2))
				var sd := px + py * 0.6 - shine
				if sd > 0.0 and sd < 22.0:
					ci.draw_rect(Rect2(px, py, sc, sc), Color(1, 1, 1, 0.55))
			# Impact flash when a letter lands
			if k > 0.5 and k < 1.0 and t - start < 0.5:
				pass
		li += 1
	if t > 2.0:
		var a := clampf((t - 2.0) / 0.5, 0.0, 1.0)
		PixelFont.draw_centered(ci, "ARCANE  ARENA  CARNAGE", 240, 132, 1, Color(0.8, 0.9, 1.0, a), Color(0.05, 0.02, 0.1, a))

func _bounce(k: float) -> float:
	if k < 0.6:
		return k / 0.6 * k / 0.6
	var b := (k - 0.8) / 0.2
	return 1.0 - 0.12 * (1.0 - b * b)

func _draw_wizards(ci: CanvasItem) -> void:
	for i in 4:
		var flip := i >= 2
		var casting: bool = wiz_cast[i] > 0.0
		var key := "wiz%d_side_%s" % [i, "b" if casting else "a"]
		var bob := 0.0 if casting else floorf(sin(t * 3.0 + i) * 1.0)
		var feet := Vector2(WIZ_X[i], 241 + bob)
		Sprites.draw_at(ci, key, feet, flip, false, Color.WHITE, 2.0)
		var hand := feet + Vector2(-6 if flip else 6, -13)
		var tip := hand + Vector2(-8 if flip else 8, -18 if casting else -14)
		ci.draw_line(hand, tip, Color("1a0f24"), 4.0)
		ci.draw_line(hand, tip, Color("b07a3a"), 2.0)
		var c: Color = Sprites.PLAYER_COLORS[i].fx
		ci.draw_rect(Rect2(tip - Vector2(2, 2), Vector2(5, 5)), c if not casting else Color.WHITE)

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
	var a := clampf((t - 2.6) / 0.4, 0.0, 1.0)
	if a <= 0.0:
		return
	for i in items.size():
		var y := 146 + i * 14
		var s := i == sel
		var label: String = items[i]
		var c := Color("ffd94d") if s else Color("b8a8d8")
		c.a = a
		var w := PixelFont.text_width(label, 1)
		menu_items.append(Rect2(240 - 70, y - 3, 140, 13))
		if s:
			Occult.highlight(ci, Rect2(240 - w / 2.0 - 18, y - 3, w + 36, 13), t)
			Occult.cursor(ci, Vector2(240 - w / 2.0 - 10, y + 3), t)
			Occult.cursor(ci, Vector2(240 + w / 2.0 + 9, y + 3), -t)
		PixelFont.draw_centered(ci, label, 240, y, 1, c, Color(0.04, 0.0, 0.1, a))
	var hint := "TAP TO SELECT" if G.touch_active else "ARROWS/STICK + ENTER/A"
	PixelFont.draw_centered(ci, hint, 240, 252, 1, Color(1, 1, 1, 0.35 * a))

## Meta unlocks: crystals earned in runs buy permanent head starts for every run (never sold for money).
func _draw_unlocks(ci: CanvasItem) -> void:
	var prof: Profile = Save.profile
	_panel(ci, Rect2(40, 144, 400, 104))
	PixelFont.draw_centered(ci, "UNLOCKS  -  %d CRYSTALS" % prof.crystals, 240, 150, 1, Color("8bdcff"))
	menu_items.clear()
	for i in Profile.META.size():
		var row: Array = Profile.META[i]
		var y := 163 + i * 12
		var picked := i == unlock_sel
		menu_items.append(Rect2(46, y - 2, 388, 11))
		if picked:
			Occult.highlight(ci, Rect2(46, y - 2, 388, 11), t)
		var lv := prof.level(row[0])
		var mx := Profile.max_level(i)
		PixelFont.draw(ci, row[1], Vector2(52, y), 1, Color("ffd94d") if picked else Color.WHITE)
		for k in mx:
			ci.draw_rect(Rect2(158 + k * 7, y + 1, 5, 5), Color("8bdcff") if k < lv else Color("3a2f55"))
		PixelFont.draw(ci, row[2], Vector2(186, y), 1, Color("b8a8d8"))
		var cost := prof.next_cost(i)
		var price := "MAX" if cost < 0 else "%d" % cost
		var pc := Color("8bff9e") if cost < 0 else (Color("8bdcff") if cost <= prof.crystals else Color("ff7a8a"))
		PixelFont.draw(ci, price, Vector2(410 - PixelFont.text_width(price, 1), y), 1, pc)
	PixelFont.draw_centered(ci, "ENTER/A: BUY    ESC/B: BACK", 240, 236, 1, Color(1, 1, 1, 0.5))

func _buy_unlock(i: int) -> void:
	if Save.profile.buy(i):
		Save.write()
		Sfx.play("powerup")
		fx.burst(Vector2(240, 163 + i * 12), 20, 90.0, 0.5, 1.0, Color.WHITE, Color("8bdcff"), true)
	else:
		Sfx.play("hurt", -6.0)
		_msg("MAXED" if Save.profile.next_cost(i) < 0 else "NOT ENOUGH CRYSTALS")

func _device_name(d: int) -> String:
	if d == G.DEV_KBM:
		return "TOUCH" if G.touch_active else "KEYBOARD"
	return "GAMEPAD %d" % (d + 1)

func _draw_lobby(ci: CanvasItem) -> void:
	var title := "LOCAL PLAY"
	if Net.mode == Net.Mode.HOST:
		title = "HOSTING LAN GAME"
	elif Net.mode == Net.Mode.CLIENT:
		title = "LAN LOBBY"
	_panel(ci, Rect2(24, 140, 432, 112))
	PixelFont.draw_centered(ci, title, 240, 145, 1, Color("ffd94d"))
	for slot in 4:
		var r := Rect2(34 + slot * 106, 158, 96, 68)
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
			var key := "wiz%d_down_%s" % [wiz, "a" if int(t * 3 + slot) % 2 == 0 else "b"]
			Sprites.draw_at(ci, key, r.position + Vector2(48, 47), false, false, Color.WHITE, 2.0)
			# The wizard picked, with arrows to step through the free ones, and the spell it starts with.
			var cx := r.get_center().x
			PixelFont.draw_centered(ci, Wizards.title(wiz), cx, r.position.y + 13, 1, Sprites.PLAYER_COLORS[wiz].fx)
			if entry.peer == Net.my_peer and int(t * 2) % 2 == 0:
				PixelFont.draw(ci, "<", Vector2(r.position.x + 4, r.position.y + 28), 1, Color.WHITE)
				PixelFont.draw(ci, ">", Vector2(r.end.x - 9, r.position.y + 28), 1, Color.WHITE)
			var spell := Upgrades.display_name(Upgrades.weapon_entry(Wizards.start_spell(wiz)))
			PixelFont.draw_centered(ci, spell, cx, r.end.y - 18, 1, Color("c9b8ff"))
			var who := _device_name(entry.device) if entry.peer == Net.my_peer else "LAN PLAYER"
			PixelFont.draw_centered(ci, who, cx, r.end.y - 9, 1, Color.WHITE)
		else:
			if int(t * 2) % 2 == 0:
				PixelFont.draw_centered(ci, "PRESS FIRE", r.get_center().x, r.position.y + 26, 1, Color(1, 1, 1, 0.5))
				PixelFont.draw_centered(ci, "TO JOIN", r.get_center().x, r.position.y + 36, 1, Color(1, 1, 1, 0.5))
	var foot := ""
	if Net.mode == Net.Mode.CLIENT:
		foot = "WAITING FOR HOST TO START..."
	elif G.touch_active:
		foot = "TAP HERE TO START"
	else:
		foot = "LEFT/RIGHT: WIZARD   ENTER/START: BEGIN   ESC/B: BACK"
	PixelFont.draw_centered(ci, foot, 240, 236, 1, Color("8bff9e") if int(t * 2) % 2 == 0 else Color.WHITE)
	if Net.mode == Net.Mode.HOST:
		var ips := Net.local_ips()
		var ip_text = "YOUR IP: " + (ips[0] if ips.size() > 0 else "?")
		PixelFont.draw_centered(ci, ip_text, 240, 258, 1, Color("c9b8ff"))

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
		["SPELLS", "CAST THEMSELVES. LEVEL UP AND TOMES ADD MORE"],
		["LOOT", "CHESTS FROM ELITES. SPEND GOLD AT SHRINES"],
		["", "SURVIVE THE HORDE. SLAY THE ARCHLICH AT 15:00 TO WIN."],
		["", "RUNS EARN CRYSTALS FOR UNLOCKS."],
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
			if back:
				Sfx.play("menu_select")
				Net.shutdown()
				G.local_devices.clear()
				state = S.MAIN
				return
			if tap:
				if tap_pos.y > 228 and Net.mode != Net.Mode.CLIENT:
					_begin()
				return
			var side: Array = PlayerInput.menu_side(event)
			if int(side[1]) != 0 and G.local_devices.has(int(side[0])):
				Net.cycle_wizard(int(side[0]), int(side[1]))
				Sfx.play("menu_move")
				return
			if dev != -99:
				if G.local_devices.has(dev):
					if Net.mode != Net.Mode.CLIENT:
						_begin()
				else:
					Net.add_local_device(dev)
					Sfx.play("powerup")
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
				state = S.MAIN
				Sfx.play("menu_select")
				return
			if dir != 0:
				unlock_sel = wrapi(unlock_sel + dir, 0, Profile.META.size())
				Sfx.play("menu_move")
			if tap:
				for i in menu_items.size():
					if menu_items[i].has_point(tap_pos):
						unlock_sel = i
						_buy_unlock(i)
				return
			if dev != -99:
				_buy_unlock(unlock_sel)

func _activate(item: String, dev: int) -> void:
	Sfx.play("menu_select")
	match item:
		"PLAY":
			G.local_devices = [dev]
			Net.start_offline()
			state = S.LOBBY
			_flash_burst()
		"HOST LAN GAME":
			G.local_devices = [dev]
			if Net.host_game():
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
		"OPTIONS":
			options.open()
			state = S.OPTIONS
		"QUIT":
			get_tree().quit()

func _flash_burst() -> void:
	fx.burst(Vector2(240, 190), 40, 160.0, 0.8, 1.0, Color.WHITE, Color("b07bff"), true, 0.0, true)

func _begin() -> void:
	if Net.roster.is_empty():
		return
	Sfx.play("wave_start")
	Net.stop_discovery()
	Net.begin_game()

func _join(ip: String) -> void:
	Net.stop_discovery()
	state = S.JOINING
	Net.join_game(ip)

func _open_ouija() -> void:
	ouija = Ouija.new()
	planchette = _ouija_pos(ouija.row, ouija.col)
	state = S.OUIJA
	Sfx.play("teleport", -6.0)


func _submit_ouija() -> void:
	var ip := ouija.text.strip_edges()
	if ip.is_valid_ip_address():
		Sfx.play("powerup")
		_join(ip)
	else:
		Sfx.play("hurt", -6.0)
		_msg("THE SPIRITS CANNOT FIND THAT ADDRESS")


## The ouija board takes the planchette (arrows, stick, d-pad, mouse) and typed digits on a keyboard.
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
				_submit_ouija()
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
		Sfx.play("menu_move", -4.0)
		return
	if event is InputEventMouseMotion:
		var hit: Vector2i = _ouija_hit(event.position)
		if hit.x >= 0 and ouija.point_at(hit.x, hit.y):
			pass
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
	if state == S.JOINING and Net.mode == Net.Mode.CLIENT:
		state = S.LOBBY
		Sfx.play("powerup")

func _on_conn_failed(reason: String) -> void:
	_msg(reason)
	if state == S.JOINING or state == S.LOBBY:
		state = S.MAIN

extends Node2D
## Match scene: runs the World on the host, mirrors it on clients, and draws
## everything (sprites, spells, particles, HUD, banners, touch controls).

const SNAP_EVERY := 2 # physics frames between snapshots sent to clients

const SPELL_COLORS := [Color("b78cff"), Color("ff7a2a"), Color("7fe8ff"), Color("ffe84d"), Color("ff7ae6")]
const ENEMY_KEYS := ["goblin", "skeleton", "slime", "mslime", "bat", "orc", "mage", "lich"]
const ENEMY_ANIM := [7.0, 5.0, 0.0, 6.0, 12.0, 4.0, 3.0, 2.0]
const PICKUP_KEYS := ["coin", "gem", "potion", "tome_fire", "tome_frost", "tome_storm", "tome_star", "boot", "tome_orbit", "xp"]
const PICKUP_NAMES := ["", "", "POTION +2", "FIREBALL!", "FROST FAN!", "CHAIN LIGHTNING!", "STARFALL!", "HASTE!", "RUNE SHIELD!", ""]
const ENEMY_NAMES := ["GOBLIN", "SKELETON", "SLIME", "SLIMELING", "BAT", "ORC BRUTE", "DARK MAGE", "LICH LORD"]

## Cosmetic randomness only (particles, shake, pitch). Gameplay randomness lives in World.rng.
var _fx_rng := RandomNumberGenerator.new()
var world: World = null
var is_host := true
var frame := 0
var pending_events: Array = []

# View state (what gets drawn), filled from snapshots on every peer.
var vp := {}  # slot -> Dictionary
var ve := {}  # id -> Dictionary
var vs: Array = []  # [spell, pos, vel, owner, evolved]
var ves: Array = [] # [kind, pos, vel]
var vk: Array = []  # [kind, pos, life]
var wave := 1
var phase := 0
var phase_t := 0.0
var boss_f := -1.0
var run_t := 0.0 # seconds of fighting, from the snapshot
var doors := [0.0, 0.0, 0.0, 0.0]
var door_anim := [0.0, 0.0, 0.0, 0.0]
var game_over := false
var game_over_t := 0.0
var final_score := 0

var shake := 0.0
var screen_flash := Color(0, 0, 0, 0)
var banner := {"text": "", "sub": "", "t": 0.0, "max": 1.0, "color": Color.WHITE}
var decals: Array = [] # [pos, color, size, life]
var paused := false
var pause_sel := 0
var time := 0.0
var torch_pos := [Vector2(110, 26), Vector2(370, 26), Vector2(10, 92), Vector2(10, 204), Vector2(470, 92), Vector2(470, 204)]
var _hitstop := 0.0
var _last_aim := {}
## Level-up pick screen, per local slot: highlighted card, and the [card, offer] confirmed and being sent.
var _pick_sel := {}
var _pick_sent := {}
const CARD_W := 140
const CARD_H := 40
const CARD_GAP := 8
const PICK_ROW_H := 52
const PICK_TOP := 44
const BOT_PICK_THINK := 0.9
var _bot_pick_wait := {}

var root := Node2D.new()
var env_add: Node2D
var bg: Sprite2D
var decal_layer: Node2D
var env_layer: Node2D
var ent_layer: Node2D
var fx: Fx
var shot_layer: Node2D
var eshot_layer: Node2D
var hud_layer: CanvasLayer
var hud: Node2D
var touch: TouchControls

func _ready() -> void:
	is_host = Net.is_host()
	add_child(root)
	bg = Sprite2D.new()
	bg.centered = false
	bg.texture = ArenaBg.build()
	root.add_child(bg)
	decal_layer = _layer(false)
	decal_layer.draw.connect(_draw_decals)
	env_layer = _layer(false)
	env_layer.draw.connect(_draw_env)
	env_add = _layer(true)
	env_add.draw.connect(_draw_env_add)
	ent_layer = _layer(false)
	ent_layer.draw.connect(_draw_entities)
	fx = Fx.new()
	root.add_child(fx)
	shot_layer = _layer(true)
	shot_layer.draw.connect(_draw_shots)
	eshot_layer = _layer(false)
	eshot_layer.draw.connect(_draw_eshots)
	var vignette := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.width = 240
	grad.height = 135
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.05, 1.05)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.02, 0.0, 0.06, 0.55))
	g.add_point(0.6, Color(0, 0, 0, 0))
	grad.gradient = g
	vignette.texture = grad
	vignette.size = G.SCREEN
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = Node2D.new()
	hud_layer.add_child(hud)
	hud.draw.connect(_draw_hud)
	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 11
	add_child(touch_layer)
	touch = TouchControls.new()
	touch_layer.add_child(touch)
	PlayerInput.touch = touch
	touch.pause_pressed.connect(_toggle_pause)

	Net.snapshot_received.connect(_on_snapshot)
	Net.roster_changed.connect(_on_roster_changed)
	if is_host:
		var slots := []
		for r in Net.roster:
			slots.append(r.slot)
		if slots.is_empty():
			slots.append(0)
		world = World.new(slots, int(Flags.get_arg("seed", "0")))
	Sfx.music("music_battle")

func _layer(additive: bool) -> Node2D:
	var n := Node2D.new()
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		n.material = m
	root.add_child(n)
	return n

func _exit_tree() -> void:
	PlayerInput.touch = null
	Engine.time_scale = 1.0

# ============================================================== LOOP ===
func _physics_process(dt: float) -> void:
	if paused and not Net.is_online():
		return
	var inputs := {}
	for r in Net.my_slots():
		var ppos: Vector2 = vp[r.slot].pos + Vector2(0, -7) + root.position if vp.has(r.slot) else G.ARENA.get_center()
		var inp := PlayerInput.read(r.device, ppos, get_viewport())
		if PlayerInput.bot:
			inp = _bot_input(r.slot)
			if PlayerInput.bot_passive:
				inp = PackedFloat32Array([0, 0, inp[2], inp[3], 1.0 if r.slot == 9 else 0.0, 0])
		if paused:
			inp = PackedFloat32Array([0, 0, 0, 0, 0, inp[5]])
		inp = _with_pick(r.slot, inp)
		inputs[r.slot] = inp
		if not is_host:
			Net.send_input(r.slot, inp)
	if is_host:
		for slot in Net.remote_inputs:
			inputs[slot] = Net.remote_inputs[slot]
		world.step(dt, inputs)
		var snap := world.snapshot()
		var evs := world.take_events()
		_apply_snapshot(snap, true)
		_handle_events(evs)
		pending_events.append_array(evs)
		frame += 1
		if frame % SNAP_EVERY == 0 and Net.is_online():
			snap["ev"] = pending_events
			Net.send_snapshot(snap)
			pending_events = []
		elif not Net.is_online():
			pending_events.clear()

func _process(dt: float) -> void:
	time += dt
	if _hitstop > 0.0:
		_hitstop -= dt / maxf(Engine.time_scale, 0.01)
		if _hitstop <= 0.0:
			Engine.time_scale = 1.0
	if not is_host:
		_smooth(dt)
	# Extrapolate shots between snapshots on clients; host positions are exact.
	if not is_host:
		for s in vs:
			s[1] += s[2] * dt
		for s in ves:
			s[1] += s[2] * dt
	_emit_trails(dt)
	for p in vp.values():
		if p.moving:
			p.walk_t += dt * 9.0
		p.ghosts.push_front(p.pos)
		if p.ghosts.size() > 8:
			p.ghosts.pop_back()
	for e in ve.values():
		e.t += dt
	for i in 4:
		door_anim[i] = move_toward(door_anim[i], 1.0 if doors[i] > 0.0 else 0.0, dt * 4.0)
	for d in decals:
		d[3] -= dt
	decals = decals.filter(func(d): return d[3] > 0.0)
	if banner.t > 0.0:
		banner.t -= dt
	screen_flash.a = maxf(0.0, screen_flash.a - dt * 3.0)
	shake = maxf(0.0, shake - dt * 18.0)
	var so := Vector2.ZERO
	if shake > 0.0:
		so = Vector2(_fx_rng.randf_range(-1, 1), _fx_rng.randf_range(-1, 1)) * shake
	root.position = so.round()
	if game_over:
		game_over_t += dt
	_torch_fx(dt)
	decal_layer.queue_redraw()
	env_layer.queue_redraw()
	ent_layer.queue_redraw()
	shot_layer.queue_redraw()
	eshot_layer.queue_redraw()
	env_add.queue_redraw()
	hud.queue_redraw()

## Adds the level-up pick fields [card, offer] (World reads input[6] and input[7]).
func _with_pick(slot: int, inp: PackedFloat32Array) -> PackedFloat32Array:
	if not vp.has(slot):
		return SmashBot.with_pick(inp, [] as Array[int], 0)
	var p: Dictionary = vp[slot]
	if PlayerInput.bot:
		# Demo bots look at the cards for a moment, so watchers and captures see the pick screen.
		if (p.choices as Array).is_empty():
			_bot_pick_wait[slot] = 0.0
		else:
			_bot_pick_wait[slot] = float(_bot_pick_wait.get(slot, 0.0)) + get_physics_process_delta_time()
		if float(_bot_pick_wait.get(slot, 0.0)) < BOT_PICK_THINK:
			return SmashBot.with_pick(inp, [] as Array[int], p.offer)
		return SmashBot.with_pick(inp, p.choices, p.offer)
	var out: PackedFloat32Array = inp.duplicate()
	var sent: Array = _pick_sent.get(slot, [-1, -1])
	if int(sent[1]) == int(p.offer) and not (p.choices as Array).is_empty():
		out.append_array([float(sent[0]), float(p.offer)])
	else:
		out.append_array([-1.0, float(p.offer)])
	return out

## Simple demo AI used by the autotest harness: kite in circles and blast
## the nearest monster.
var _bots := {}  # slot -> SmashBot
func _bot_input(slot: int) -> PackedFloat32Array:
	if not vp.has(slot):
		return PackedFloat32Array([0, 0, 0, 0, 0, 0])
	if not _bots.has(slot):
		_bots[slot] = SmashBot.new(slot + 1)
	var en: Array[Vector2] = []
	for e: Dictionary in ve.values():
		en.append(e.pos)
	var es: Array[Vector2] = []
	for s: Array in ves:
		es.append(s[1])
	var pk: Array[Vector2] = []
	for k: Array in vk:
		pk.append(k[1])
	return _bots[slot].decide(slot, vp[slot].pos, G.ARENA.get_center(), time, en, es, pk)

func _smooth(dt: float) -> void:
	var k := 1.0 - exp(-dt * 20.0)
	for p in vp.values():
		p.pos = p.pos.lerp(p.target, k)
	for e in ve.values():
		if e.pos.distance_to(e.target) > 40.0:
			e.pos = e.target # teleports
		else:
			e.pos = e.pos.lerp(e.target, k)

# ========================================================= SNAPSHOTS ===
func _on_snapshot(snap: Dictionary) -> void:
	if is_host:
		return
	_apply_snapshot(snap, false)
	if snap.has("ev"):
		_handle_events(snap.ev)

func _apply_snapshot(snap: Dictionary, instant: bool) -> void:
	var pl: PackedFloat32Array = snap.p
	var seen := {}
	var i := 0
	while i + World.PLAYER_FLOATS <= pl.size():
		var slot := int(pl[i])
		seen[slot] = true
		if not vp.has(slot):
			vp[slot] = {"slot": slot, "pos": Vector2(pl[i + 1], pl[i + 2]), "walk_t": 0.0, "ghosts": []}
		var p: Dictionary = vp[slot]
		p.target = Vector2(pl[i + 1], pl[i + 2])
		if instant:
			p.pos = p.target
		p.aim = Vector2(pl[i + 3], pl[i + 4])
		p.hp = int(pl[i + 5])
		p.lives = int(pl[i + 6])
		p.alive = pl[i + 7] > 0.5
		p.invuln = pl[i + 8]
		p.spell = int(pl[i + 9])
		p.bombs = int(pl[i + 11])
		p.score = int(pl[i + 12])
		p.combo = int(pl[i + 13])
		p.haste = pl[i + 14]
		p.orbit = pl[i + 15]
		p.orbit_ang = pl[i + 16]
		p.flash = pl[i + 17]
		p.moving = pl[i + 18] > 0.5
		p.xp = int(pl[i + 19])
		p.xp_need = maxi(1, int(pl[i + 20]))
		p.level = int(pl[i + 21])
		var offer := int(pl[i + 22])
		if offer != int(p.get("offer", -1)):
			_pick_sel[slot] = 0
		p.offer = offer
		var ch: Array[int] = []
		var lv: Array[int] = []
		for c in 3:
			var idx := int(pl[i + 23 + c * 2])
			if idx >= 0:
				ch.append(idx)
				lv.append(int(pl[i + 24 + c * 2]))
		p.choices = ch
		p.choice_lv = lv
		var wl: Array[int] = []
		for sp in Spells.COUNT:
			wl.append(int(pl[i + 29 + sp]))
		p.weapons = wl
		if not p.alive:
			p.pos = p.target
		i += World.PLAYER_FLOATS
	for s in vp.keys():
		if not seen.has(s):
			vp.erase(s)
	var en: PackedFloat32Array = snap.e
	var eseen := {}
	i = 0
	while i + World.ENEMY_FLOATS <= en.size():
		var id := int(en[i])
		eseen[id] = true
		var pos := Vector2(en[i + 2], en[i + 3])
		if not ve.has(id):
			ve[id] = {"type": int(en[i + 1]), "pos": pos, "t": _fx_rng.randf() * 5.0, "flip": false, "prev_x": pos.x}
		var e: Dictionary = ve[id]
		e.target = pos
		if instant:
			e.pos = pos
		e.flash = en[i + 4]
		e.state = int(en[i + 5])
		e.hpf = en[i + 6]
		e.slow = en[i + 7]
		e.elite = en[i + 8] > 0.5
		i += World.ENEMY_FLOATS
	for id in ve.keys():
		if not eseen.has(id):
			ve.erase(id)
	vs.clear()
	var sh: PackedFloat32Array = snap.s
	i = 0
	while i + 6 <= sh.size():
		var sk := int(sh[i])
		vs.append([sk % Spells.COUNT, Vector2(sh[i + 1], sh[i + 2]), Vector2(sh[i + 3], sh[i + 4]), int(sh[i + 5]), sk >= Spells.COUNT])
		i += 6
	ves.clear()
	var es: PackedFloat32Array = snap.es
	i = 0
	while i + 5 <= es.size():
		ves.append([int(es[i]), Vector2(es[i + 1], es[i + 2]), Vector2(es[i + 3], es[i + 4])])
		i += 5
	vk.clear()
	var pk: PackedFloat32Array = snap.k
	i = 0
	while i + 4 <= pk.size():
		vk.append([int(pk[i]), Vector2(pk[i + 1], pk[i + 2]), pk[i + 3]])
		i += 4
	var w: PackedFloat32Array = snap.w
	wave = int(w[0])
	phase = int(w[1])
	phase_t = w[2]
	boss_f = w[3]
	run_t = w[8]
	for d in 4:
		doors[d] = w[4 + d]

func _on_roster_changed() -> void:
	if not is_host or world == null:
		return
	var live := {}
	for r in Net.roster:
		live[r.slot] = true
	for s in world.players.keys():
		if not live.has(s):
			world.players.erase(s)

# ============================================================ EVENTS ===
func _handle_events(evs: Array) -> void:
	for ev in evs:
		var pos := Vector2(ev[1], ev[2])
		match int(ev[0]):
			World.EV_CAST:
				var sp := int(ev[3])
				var col := _spell_color(sp, int(ev[4]))
				fx.cast_flash(pos, col)
				match sp:
					World.SP_ARCANE: Sfx.play("shoot_arcane", -6.0, 1.0, 0.06)
					World.SP_FIRE: Sfx.play("shoot_fire", -3.0, 1.0, 0.08)
					World.SP_FROST: Sfx.play("shoot_frost", -5.0, 1.0, 0.08)
					World.SP_STAR: Sfx.play("star", -6.0, 1.0, 0.08)
			World.EV_HIT:
				fx.hit_spark(pos, Color(1, 1, 1) if int(ev[4]) < 0 else G.player_fx(int(ev[4])))
				Sfx.play("hit", -8.0, _fx_rng.randf_range(0.9, 1.2), 0.04)
			World.EV_DIE:
				var t := int(ev[3])
				fx.death(pos, t)
				Sfx.play("enemy_die", -2.0, _fx_rng.randf_range(0.85, 1.15), 0.04)
				_add_shake(1.5 if t != World.ORC else 3.0)
				var gc := [Color("2f7a2a"), Color("b7a98e"), Color("158f86"), Color("158f86"), Color("5a1a8a"), Color("4d5166"), Color("3b1f6e"), Color("4a1a7a")]
				_decal(pos + Vector2(0, 4), gc[clampi(t, 0, 7)], 4.0 if t != World.ORC else 7.0)
			World.EV_EXPLODE:
				fx.explosion(pos, float(ev[3]))
				Sfx.play("explode", -2.0, _fx_rng.randf_range(0.9, 1.1), 0.05)
				_add_shake(3.0)
				_decal(pos, Color("1a1020"), 10.0)
			World.EV_ZAP:
				var pts: PackedVector2Array = ev[3]
				fx.bolt(pts, Color("7fd8ff"))
				for pt in pts:
					fx.burst(pt, 3, 60.0, 0.2, 1.0, Color.WHITE, Color("ffe84d"), true)
				Sfx.play("zap", -5.0, _fx_rng.randf_range(0.9, 1.15), 0.07)
			World.EV_NOVA:
				var col := G.player_fx(int(ev[3]))
				fx.nova(pos, col)
				Sfx.play("nova", 0.0, 1.0, 0.1)
				_add_shake(9.0)
				screen_flash = Color(col.r, col.g, col.b, 0.55)
				_do_hitstop(0.08)
			World.EV_PICKUP:
				var k := int(ev[3])
				if k == World.PK_XP:
					Sfx.play("coin", -14.0, 1.5, 0.05)
					continue
				fx.sparkle(pos, _pickup_color(k))
				match k:
					World.PK_COIN: Sfx.play("coin", -4.0)
					World.PK_GEM: Sfx.play("pickup", -3.0)
					World.PK_POTION: Sfx.play("heal")
					_: Sfx.play("powerup")
				if PICKUP_NAMES[k] != "":
					fx.text(pos + Vector2(0, -12), PICKUP_NAMES[k], _pickup_color(k), 1.4)
			World.EV_SCORE:
				fx.text(pos, "+%d" % int(ev[3]), Color("ffe58a"), 0.7)
			World.EV_HURT:
				fx.burst(pos, 14, 110.0, 0.4, 2.0, Color.WHITE, Color("ff2a4a"), true)
				Sfx.play("hurt")
				_add_shake(4.0)
				if _is_local_slot(int(ev[3])):
					screen_flash = Color(1, 0.1, 0.2, 0.35)
			World.EV_PDIE:
				var col := G.player_color(int(ev[3]))
				fx.nova(pos, col)
				fx.burst(pos, 40, 160.0, 0.9, 2.0, Color.WHITE, col, true, 60.0, true)
				Sfx.play("player_die")
				_add_shake(7.0)
				var left := int(ev[4])
				fx.text(pos + Vector2(0, -16), "P%d DOWN!" % (int(ev[3]) + 1) if left > 0 else "P%d IS OUT!" % (int(ev[3]) + 1), col, 1.8, 1)
			World.EV_DOOR:
				Sfx.play("door", -6.0, 1.0, 0.2)
			World.EV_ESHOT:
				var k := int(ev[3])
				if k == World.ES_ARROW:
					Sfx.play("arrow", -8.0, 1.0, 0.08)
				else:
					Sfx.play("enemy_shot", -9.0, 1.0 if k == World.ES_ORB else 0.7, 0.1)
					fx.flash(pos, 6.0, Color("ff4df2") if k == World.ES_ORB else Color("4dffb0"), 0.08)
			World.EV_SPLIT:
				fx.burst(pos, 16, 80.0, 0.5, 2.0, Color("d8fff6"), Color("158f86"), false, 200.0)
				Sfx.play("slime")
			World.EV_TELE:
				fx.teleport(pos, Color("ff4df2") if int(ev[3]) == 0 else Color("4dfff0"))
				Sfx.play("teleport", -6.0, 1.0, 0.1)
			World.EV_CHARGE:
				fx.text(pos + Vector2(0, -8), "!", Color("ff3030"), 0.6, 2)
				Sfx.play("charge", -3.0)
			World.EV_WAVE:
				var w := int(ev[3])
				if int(ev[4]) == 1:
					_banner("THE LICH LORD", "AWAKENS AT MINUTE %d" % w, Color("ff4d6a"), 2.6)
					Sfx.play("wave_start")
				elif w > 1:
					_banner("MINUTE %d" % w, ["HOLD THE TOWER!", "THEY KEEP COMING!", "STAND TOGETHER!", "MORE OF THEM!"][w % 4], Color("ffd94d"), 1.6)
					Sfx.play("wave_start", -4.0)
				else:
					_banner("SURVIVE", "SMASH THEM ALL!", Color("ffd94d"), 2.4)
					Sfx.play("wave_start")
				Sfx.music("music_battle")
			World.EV_ELITE:
				fx.text(pos + Vector2(0, -16), "ELITE!", Color("ffb84d"), 1.2, 1)
				fx.ring(pos, 2.0, 24.0, 0.5, Color("ffb84d"), 2.0)
				Sfx.play("charge", -2.0, 0.8)
			World.EV_BOSS:
				Sfx.play("boss_roar")
				Sfx.music("music_boss")
				_add_shake(8.0)
				screen_flash = Color(0.3, 1.0, 0.9, 0.4)
			World.EV_COMBO:
				var col := G.player_fx(int(ev[4]))
				fx.text(pos + Vector2(0, -18), World.COMBO_CALLS.get(int(ev[3]), "COMBO!"), col, 1.6, 2)
				fx.text(pos + Vector2(0, -4), "x%d COMBO" % int(ev[3]), Color.WHITE, 1.4, 1)
				Sfx.play("powerup", -2.0, 1.2)
			World.EV_SPAWN:
				fx.teleport(pos, G.player_color(int(ev[3])))
				fx.ring(pos + Vector2(0, -6), 1.0, 30.0, 0.5, G.player_fx(int(ev[3])), 2.0)
				Sfx.play("teleport")
			World.EV_POWERUP:
				fx.sparkle(pos, _pickup_color(int(ev[3])), 16)
				Sfx.play("orbit", -6.0)
			World.EV_BOSSDIE:
				for k in 6:
					fx.explosion(pos + Vector2(_fx_rng.randf_range(-26, 26), _fx_rng.randf_range(-26, 20)), 30.0)
				fx.nova(pos, Color("4dfff0"))
				Sfx.play("nova")
				Sfx.play("explode", 0.0, 0.7)
				_add_shake(12.0)
				screen_flash = Color(1, 1, 1, 0.8)
				_do_hitstop(0.25)
				_banner("LICH LORD DESTROYED!", "+5000 x COMBO", Color("4dfff0"), 3.0)
			World.EV_GAMEOVER:
				game_over = true
				game_over_t = 0.0
				final_score = int(ev[3])
				G.submit_score(final_score)
				Sfx.music("music_gameover")
			World.EV_LEVELUP:
				var col := G.player_fx(int(ev[3]))
				fx.text(pos, "LEVEL UP!", col, 1.4, 1)
				fx.ring(pos + Vector2(0, 8), 1.0, 26.0, 0.5, col, 2.0)
				Sfx.play("powerup", -2.0, 1.1)
			World.EV_PICK:
				var col := G.player_fx(int(ev[3]))
				fx.text(pos, Upgrades.display_name(int(ev[4])) + "!", col, 1.4, 1)
				fx.sparkle(pos + Vector2(0, 10), col, 16)
				Sfx.play("wave_clear", -6.0, 1.3, 0.2)
			World.EV_FROST:
				fx.burst(pos, 6, 70.0, 0.35, 1.0, Color.WHITE, Color("7fe8ff"), true)
				if float(ev[3]) > 0.0:
					fx.ring(pos, 0.4, float(ev[3]), 0.3, Color("7fe8ff"), 2.0)

## Run time as M:SS.
static func _clock(secs: float) -> String:
	var t := int(secs)
	return "%d:%02d" % [t / 60, t % 60]

func _banner(text: String, sub: String, color: Color, dur: float) -> void:
	banner = {"text": text, "sub": sub, "t": dur, "max": dur, "color": color}

func _add_shake(v: float) -> void:
	shake = minf(14.0, maxf(shake, v))

func _do_hitstop(d: float) -> void:
	if Net.is_online():
		return
	Engine.time_scale = 0.08
	_hitstop = d

func _decal(pos: Vector2, color: Color, size: float) -> void:
	decals.append([pos, color, size, 12.0, _fx_rng.randi()])
	if decals.size() > 120:
		decals.pop_front()

func _is_local_slot(slot: int) -> bool:
	for r in Net.my_slots():
		if r.slot == slot:
			return true
	return false

func _spell_color(sp: int, slot: int) -> Color:
	if sp == World.SP_ARCANE:
		return G.player_fx(slot)
	return SPELL_COLORS[sp]

func _pickup_color(k: int) -> Color:
	match k:
		World.PK_COIN: return Color("ffd23d")
		World.PK_GEM: return Color("4df0ff")
		World.PK_POTION: return Color("ff3b6b")
		World.PK_TOME_FIRE: return SPELL_COLORS[1]
		World.PK_TOME_FROST: return SPELL_COLORS[2]
		World.PK_TOME_STORM: return SPELL_COLORS[3]
		World.PK_TOME_STAR: return SPELL_COLORS[4]
		World.PK_BOOTS: return Color("4dc8ff")
		World.PK_ORBIT: return Color("8bff9e")
		World.PK_XP: return Color("5dff7a")
	return Color.WHITE

# ======================================================== AMBIENT FX ===
func _emit_trails(dt: float) -> void:
	for s in vs:
		var col := _spell_color(s[0], s[3])
		var p: Vector2 = s[1]
		match s[0]:
			World.SP_ARCANE:
				if frame % 2 == 0 or not is_host:
					fx.spawn(p, -s[2] * 0.05, 0.18, 1.5, col.lightened(0.3), col, true, 4.0)
			World.SP_FIRE:
				fx.spawn(p + Vector2(_fx_rng.randf_range(-2, 2), _fx_rng.randf_range(-2, 2)), -s[2] * 0.15 + Vector2(0, -20),
					0.35, 2.5, Color(1, 0.9, 0.4), Color(0.8, 0.1, 0.05), true, 3.0, -20.0, 0.0, true)
				if _fx_rng.randf() < 0.3:
					fx.spawn(p, Vector2(_fx_rng.randf_range(-10, 10), -15), 0.6, 2.0, Color(0.25, 0.2, 0.25, 0.6), Color(0.1, 0.1, 0.1, 0.0), false, 1.0, -10.0, 4.0)
			World.SP_FROST:
				if _fx_rng.randf() < 0.5:
					fx.spawn(p, Vector2(_fx_rng.randf_range(-15, 15), _fx_rng.randf_range(-15, 15)), 0.3, 1.0, Color.WHITE, col, true, 2.0)
			World.SP_STAR:
				fx.spawn(p, Vector2(_fx_rng.randf_range(-20, 20), _fx_rng.randf_range(-20, 20)), 0.4, 1.0, Color.WHITE, col, true, 2.0, 30.0)
	for e in ve.values():
		if e.type == World.LICH and _fx_rng.randf() < 0.6:
			fx.spawn(e.pos + Vector2(_fx_rng.randf_range(-14, 14), _fx_rng.randf_range(-24, 0)), Vector2(0, _fx_rng.randf_range(-30, -10)),
				0.7, 1.0, Color("4dfff0"), Color("4a1a7a"), true, 1.0)
		elif e.slow > 0.0 and _fx_rng.randf() < 0.15:
			fx.spawn(e.pos + Vector2(_fx_rng.randf_range(-5, 5), -_fx_rng.randf_range(0, 10)), Vector2(0, -8), 0.4, 1.0, Color.WHITE, Color("7fe8ff"), true)
		elif e.type == World.MAGE and e.state == 1:
			fx.spawn(e.pos + Vector2(_fx_rng.randf_range(-6, 6), -8 + _fx_rng.randf_range(-4, 4)), Vector2(0, -20), 0.3, 1.0, Color.WHITE, Color("ff4df2"), true)
	for p in vp.values():
		if not p.alive:
			continue
		if p.haste > 0.0 and p.moving and _fx_rng.randf() < 0.5:
			fx.spawn(p.pos + Vector2(_fx_rng.randf_range(-3, 3), 0), Vector2(0, -10), 0.35, 1.0, Color.WHITE, Color("4dc8ff"), true)
		if p.spell != World.SP_ARCANE and _fx_rng.randf() < 0.25:
			var tip: Vector2 = p.pos + Vector2(0, -7) + p.aim * 9.0
			fx.spawn(tip, Vector2(_fx_rng.randf_range(-10, 10), _fx_rng.randf_range(-25, -5)), 0.4, 1.0, Color.WHITE, SPELL_COLORS[p.spell], true)

func _torch_fx(dt: float) -> void:
	for tp in torch_pos:
		if _fx_rng.randf() < 0.5:
			fx.spawn(tp + Vector2(_fx_rng.randf_range(-1.5, 1.5), -2), Vector2(_fx_rng.randf_range(-4, 4), _fx_rng.randf_range(-24, -12)),
				_fx_rng.randf_range(0.25, 0.45), 2.0, Color(1, 0.9, 0.4), Color(0.9, 0.15, 0.05), true, 1.0, -10.0, 0.0)

# ============================================================ DRAWING ===
func _draw_decals() -> void:
	for d in decals:
		var c: Color = d[1]
		c.a = clampf(d[3] / 4.0, 0.0, 1.0) * 0.5
		var p: Vector2 = d[0]
		var s: float = d[2]
		var seed: int = d[4]
		decal_layer.draw_set_transform(p.floor(), 0.0, Vector2(1.0, 0.55))
		decal_layer.draw_circle(Vector2.ZERO, s * 0.6, c)
		for k in 4:
			var o := Vector2(((seed >> (k * 4)) % 13) - 6, ((seed >> (k * 4 + 2)) % 9) - 4) * s * 0.18
			decal_layer.draw_circle(o, s * 0.3, c)
	decal_layer.draw_set_transform(Vector2.ZERO)

func _draw_env() -> void:
	var ci := env_layer
	# Doors: portcullis that lifts while monsters pour through.
	for i in 4:
		var dp: Vector2 = World.DOORS[i]
		var horiz := i < 2
		var sz := Vector2(36, 16) if horiz else Vector2(14, 34)
		var r := Rect2(dp - sz / 2.0, sz)
		ci.draw_rect(r.grow(2), Color("1a1230"))
		ci.draw_rect(r, Color("07040d"))
		var open: float = door_anim[i]
		# Glow from inside when open
		if open > 0.0:
			ci.draw_rect(r.grow(-2), Color(0.6, 0.1, 0.2, 0.35 * open))
		var bars := 6 if horiz else 4
		for b in bars:
			if horiz:
				var x := r.position.x + 3 + b * (sz.x - 6) / (bars - 1)
				var h := sz.y * (1.0 - open)
				ci.draw_rect(Rect2(x - 1, r.position.y, 2, h), Color("6b6280"))
			else:
				var y := r.position.y + 3 + b * (sz.y - 6) / (bars - 1)
				var w := sz.x * (1.0 - open)
				var x0 := r.position.x if i == 2 else r.end.x - w
				ci.draw_rect(Rect2(x0, y - 1, w, 2), Color("6b6280"))
		# Stone frame
		ci.draw_rect(Rect2(r.position - Vector2(3, 3), Vector2(r.size.x + 6, 2)), Color("7a68a8"))
	# Torch brackets
	for tp in torch_pos:
		ci.draw_rect(Rect2(tp + Vector2(-2, 0), Vector2(4, 5)), Color("2b1d12"))
		ci.draw_rect(Rect2(tp + Vector2(-1, 0), Vector2(2, 1)), Color("a06a2a"))

func _draw_env_add() -> void:
	var ci := env_add
	var c := G.ARENA.get_center()
	# Pulsing rune circle
	var pulse := 0.5 + 0.5 * sin(time * 2.0)
	var col := Color(0.2, 0.6, 0.9, 0.12 + 0.1 * pulse)
	for r in [44.0, 38.0]:
		var pts := PackedVector2Array()
		for i in 65:
			var a := i * TAU / 64.0
			pts.append(c + Vector2(cos(a), sin(a) * 0.62) * r)
		ci.draw_polyline(pts, col, 1.0)
	for i in 12:
		var a := i * TAU / 12 + time * 0.3
		var p := c + Vector2(cos(a), sin(a) * 0.62) * 41.0
		ci.draw_rect(Rect2(p.floor(), Vector2(1, 1)), Color(0.4, 0.9, 1.0, 0.4 + 0.4 * sin(time * 3 + i)))
	# Torch light pools
	for tp in torch_pos:
		var f := 0.85 + 0.15 * sin(time * 13.0 + tp.x) * sin(time * 7.3 + tp.y)
		ci.draw_circle(tp, 26.0 * f, Color(1.0, 0.5, 0.15, 0.06))
		ci.draw_circle(tp, 12.0 * f, Color(1.0, 0.6, 0.2, 0.1))
	# Door glow
	for i in 4:
		if door_anim[i] > 0.0:
			ci.draw_circle(World.DOORS[i], 24.0, Color(1.0, 0.2, 0.3, 0.12 * door_anim[i]))

func _shadow(ci: CanvasItem, pos: Vector2, w: float) -> void:
	var c := Color(0.05, 0.0, 0.1, 0.45)
	var h := maxf(2.0, floorf(w * 0.35))
	ci.draw_rect(Rect2((pos - Vector2(w / 2.0, h / 2.0)).floor() + Vector2(1, 0), Vector2(w - 2, h)), c)
	ci.draw_rect(Rect2((pos - Vector2(w / 2.0 - 1, h / 2.0 + 1)).floor() + Vector2(1, 0), Vector2(w - 4, h + 2)), c)

func _draw_entities() -> void:
	var ci := ent_layer
	# Pickups
	for k in vk:
		var kind: int = k[0]
		var pos: Vector2 = k[1]
		var life: float = k[2]
		if life < 3.0 and int(life * 10.0) % 2 == 0:
			continue
		var bob := floorf(sin(time * 4.0 + pos.x) * 2.0)
		_shadow(ci, pos + Vector2(0, 1), 8)
		Sprites.draw_at(ci, PICKUP_KEYS[kind], pos + Vector2(0, -2 + bob))
	# Collect drawables sorted by y
	var list := []
	for p in vp.values():
		if p.alive:
			list.append([p.pos.y, 0, p])
	for e in ve.values():
		list.append([e.pos.y, 1, e])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for it in list:
		if it[1] == 0:
			_shadow(ci, it[2].pos, 10)
		else:
			var e: Dictionary = it[2]
			if e.type != World.BAT:
				_shadow(ci, e.pos, [10, 10, 12, 8, 8, 14, 10, 26][e.type])
	for it in list:
		if it[1] == 0:
			_draw_player(ci, it[2])
		else:
			_draw_enemy(ci, it[2])

func _draw_player(ci: CanvasItem, p: Dictionary) -> void:
	var slot: int = p.slot
	if p.invuln > 0.0 and int(time * 20.0) % 2 == 0 and p.invuln < 2.4:
		return
	var aim: Vector2 = p.aim
	var dirkey := "down"
	var flip := false
	if absf(aim.y) > absf(aim.x) * 1.1:
		dirkey = "up" if aim.y < 0 else "down"
	else:
		dirkey = "side"
		flip = aim.x < 0
	var fr := "a" if not p.moving or int(p.walk_t) % 2 == 0 else "b"
	var key := "wiz%d_%s_%s" % [slot % 4, dirkey, fr]
	var feet: Vector2 = p.pos + Vector2(0, 1)
	if p.moving:
		feet.y -= float(int(p.walk_t) % 2)
	# Haste afterimages
	if p.haste > 0.0:
		for gi in range(2, p.ghosts.size(), 2):
			var gc := Color(0.3, 0.8, 1.0, 0.35 - gi * 0.035)
			Sprites.draw_at(ci, key, p.ghosts[gi] + Vector2(0, 1), flip, true, gc)
	var hand = p.pos + Vector2(3 if aim.x >= 0 else -3, -6)
	var tip: Vector2 = p.pos + Vector2(0, -7) + aim * 9.0
	if dirkey == "up":
		_draw_staff(ci, hand, tip, p.spell, slot)
	Sprites.draw_at(ci, key, feet, flip, p.flash > 0.0)
	if dirkey != "up":
		_draw_staff(ci, hand, tip, p.spell, slot)
	if vp.size() > 1 or Net.is_online():
		var col := G.player_color(slot)
		var lbl := "P%d" % (slot + 1)
		PixelFont.draw_centered(ci, lbl, p.pos.x, p.pos.y - 26 + floorf(sin(time * 5) * 1.0), 1, col, Color("0b0716"))

func _draw_staff(ci: CanvasItem, hand: Vector2, tip: Vector2, spell: int, slot: int) -> void:
	var a := hand.floor()
	var b := tip.floor()
	ci.draw_line(a + Vector2(0.5, 0.5), b + Vector2(0.5, 0.5), Color("1a0f24"), 3.0)
	ci.draw_line(a + Vector2(0.5, 0.5), b + Vector2(0.5, 0.5), Color("b07a3a"), 1.0)
	ci.draw_rect(Rect2(b - Vector2(1, 1), Vector2(3, 3)), _spell_color(spell, slot))
	ci.draw_rect(Rect2(b - Vector2(0, 0), Vector2(1, 1)), Color.WHITE)

func _draw_enemy(ci: CanvasItem, e: Dictionary) -> void:
	var t: int = e.type
	var base: String = ENEMY_KEYS[t]
	var key := base
	if t != World.LICH:
		var fr := "a"
		if t == World.SLIME:
			fr = "b" if e.state == 1 else "a"
		elif int(e.t * ENEMY_ANIM[t]) % 2 == 1:
			fr = "b"
		key = base + "_" + fr
	# Face the nearest wizard
	var near := Vector2.ZERO
	var nd := INF
	for p in vp.values():
		if p.alive:
			var d: float = p.pos.distance_squared_to(e.pos)
			if d < nd:
				nd = d
				near = p.pos
	var flip = nd < INF and near.x < e.pos.x
	var feet: Vector2 = e.pos + Vector2(0, 1)
	var mod := Color.WHITE
	if e.slow > 0.0:
		mod = Color(0.6, 0.9, 1.4)
	match t:
		World.BAT:
			feet.y -= 6.0 + floorf(sin(e.t * 8.0) * 2.0)
		World.LICH:
			feet.y -= 4.0 + floorf(sin(e.t * 2.0) * 3.0)
		World.ORC:
			if e.state == 1:
				feet.x += _fx_rng.randf_range(-1.5, 1.5)
				mod = Color(1.6, 0.6, 0.6)
			elif e.state == 2:
				mod = Color(1.4, 0.8, 0.8)
		World.MAGE:
			if e.state == 1:
				mod = Color(1.4, 0.8, 1.4)
	if e.get("elite", false):
		# Elites: a gold aura and a warmer tint so they stand out of the horde.
		ci.draw_circle(e.pos + Vector2(0, -6), 11.0 + sin(time * 6.0 + e.t) * 1.5, Color(1.0, 0.72, 0.3, 0.22))
		mod = mod * Color(1.35, 1.1, 0.8)
	var flash: bool = e.flash > 0.0 and (t != World.LICH or int(time * 40.0) % 3 == 0)
	Sprites.draw_at(ci, key, feet, flip and t != World.BAT and t != World.LICH, flash, mod)
	if (t == World.ORC or t == World.MAGE or e.get("elite", false)) and e.hpf < 1.0:
		var w := 14.0
		var bp = (e.pos + Vector2(-w / 2, 4)).floor()
		ci.draw_rect(Rect2(bp - Vector2(1, 1), Vector2(w + 2, 4)), Color("0b0716"))
		ci.draw_rect(Rect2(bp, Vector2(w * e.hpf, 2)), Color("ff3b5c"))

func _draw_shots() -> void:
	var ci := shot_layer
	for s in vs:
		var kind: int = s[0]
		var p: Vector2 = s[1]
		var v: Vector2 = s[2]
		var col := _spell_color(kind, s[3])
		if s[4]:
			# Evolved spells carry a wide pulsing halo so they read as the upgraded form.
			ci.draw_circle(p, 9.0 + sin(time * 16.0 + p.x) * 1.5, Color(col.r, col.g, col.b, 0.18))
		match kind:
			World.SP_ARCANE:
				ci.draw_circle(p, 5.0, Color(col.r, col.g, col.b, 0.25))
				var d := v.normalized()
				ci.draw_line(p - d * 5.0, p, Color(col.r, col.g, col.b, 0.8), 2.0)
				ci.draw_rect(Rect2(p.floor() - Vector2(1, 1), Vector2(2, 2)), Color.WHITE)
			World.SP_FIRE:
				var f := 1.0 + 0.2 * sin(time * 30.0 + p.x)
				ci.draw_circle(p, 9.0 * f, Color(1.0, 0.35, 0.05, 0.25))
				ci.draw_circle(p, 5.0 * f, Color(1.0, 0.6, 0.1, 0.6))
				ci.draw_circle(p, 2.5, Color(1.0, 1.0, 0.7, 1.0))
			World.SP_FROST:
				var d := v.normalized()
				ci.draw_circle(p, 4.0, Color(col.r, col.g, col.b, 0.25))
				ci.draw_line(p - d * 6.0, p + d * 1.0, col, 2.0)
				ci.draw_line(p - d * 3.0, p + d * 1.0, Color.WHITE, 1.0)
			World.SP_STAR:
				var r := 3.0 + sin(time * 20.0) * 1.0
				ci.draw_circle(p, 6.0, Color(col.r, col.g, col.b, 0.25))
				var a := time * 10.0
				for k in 4:
					var dd := Vector2.from_angle(a + k * PI / 2.0)
					ci.draw_line(p, p + dd * r, col, 1.0)
				ci.draw_rect(Rect2(p.floor() - Vector2(1, 1), Vector2(2, 2)), Color.WHITE)
	# Rune shield orbs + staff glow
	for slot in vp:
		var p: Dictionary = vp[slot]
		if not p.alive:
			continue
		var tip: Vector2 = p.pos + Vector2(0, -7) + p.aim * 9.0
		var sc := _spell_color(p.spell, slot)
		ci.draw_circle(tip, 4.0 + sin(time * 8.0), Color(sc.r, sc.g, sc.b, 0.25))
		if p.orbit > 0.0 and (p.orbit > 2.0 or int(time * 10) % 2 == 0):
			for i in 3:
				var a: float = p.orbit_ang + i * TAU / 3.0
				var op: Vector2 = p.pos + Vector2(0, -6) + Vector2(cos(a), sin(a)) * 22.0
				ci.draw_circle(op, 6.0, Color(0.5, 1.0, 0.6, 0.25))
				ci.draw_circle(op, 3.0, Color(0.6, 1.0, 0.7, 0.8))
				ci.draw_rect(Rect2(op.floor() - Vector2(1, 1), Vector2(2, 2)), Color.WHITE)
	# Boss & charging-mage aura
	for e in ve.values():
		if e.type == World.LICH:
			ci.draw_circle(e.pos + Vector2(0, -14), 22.0 + sin(time * 3.0) * 2.0, Color(0.2, 0.9, 0.9, 0.08))
		elif e.type == World.MAGE and e.state == 1:
			ci.draw_circle(e.pos + Vector2(0, -8), 7.0, Color(1.0, 0.3, 0.9, 0.35))

func _draw_eshots() -> void:
	var ci := eshot_layer
	for s in ves:
		var kind: int = s[0]
		var p: Vector2 = s[1]
		var v: Vector2 = s[2]
		match kind:
			World.ES_ARROW:
				var d := v.normalized()
				ci.draw_line(p - d * 7.0, p, Color("6b3f1f"), 1.0)
				ci.draw_line(p - d * 7.0, p - d * 5.0, Color("f2ead8"), 1.0)
				ci.draw_rect(Rect2(p.floor() - Vector2(1, 1) + d.round(), Vector2(2, 2)), Color("e8e8f0"))
			World.ES_ORB:
				var pulse := 1.0 + 0.25 * sin(time * 20.0 + p.x)
				ci.draw_circle(p, 5.0 * pulse, Color(1.0, 0.2, 0.85, 0.35))
				ci.draw_circle(p, 3.0, Color("ff4df2"))
				ci.draw_circle(p, 1.5, Color("2b0030"))
			World.ES_SKULL:
				var pulse := 1.0 + 0.2 * sin(time * 16.0 + p.y)
				ci.draw_circle(p, 6.0 * pulse, Color(0.2, 1.0, 0.7, 0.3))
				ci.draw_circle(p, 3.5, Color("4dffb0"))
				ci.draw_rect(Rect2(p.floor() + Vector2(-2, -1), Vector2(1, 1)), Color("0b2a1a"))
				ci.draw_rect(Rect2(p.floor() + Vector2(1, -1), Vector2(1, 1)), Color("0b2a1a"))
				ci.draw_rect(Rect2(p.floor() + Vector2(-1, 1), Vector2(2, 1)), Color("0b2a1a"))

# ================================================================ HUD ===
func _draw_hud() -> void:
	var ci := hud
	var dark := Color("0b0716")
	# Player panels
	for slot in 4:
		var x := slot * 120 + 4
		var col := G.player_color(slot)
		if not vp.has(slot):
			if not game_over and int(time * 2.0) % 2 == 0:
				PixelFont.draw(ci, "P%d" % (slot + 1), Vector2(x, 2), 1, col.darkened(0.5))
			continue
		var p: Dictionary = vp[slot]
		PixelFont.draw(ci, "P%d" % (slot + 1), Vector2(x, 2), 1, col, dark)
		PixelFont.draw(ci, "%07d" % p.score, Vector2(x + 18, 2), 1, Color("fff6e0"), dark)
		# Hearts
		for h in 5:
			_heart(ci, Vector2(x + h * 7, 10), h < p.hp)
		# Lives (small hats) and nova charges (stars)
		for l in mini(p.lives, 5):
			_hat(ci, Vector2(x + 38 + l * 6, 10), col)
		for b in mini(p.bombs, 4):
			_star(ci, Vector2(x + 72 + b * 7, 10))
		# Spell weapons: one pip per spell, filled by level; an evolved one glows white at the rim.
		var wl: Array = p.get("weapons", [])
		for sp in wl.size():
			var wlv: int = wl[sp]
			if wlv <= 0:
				continue
			var px := x + 64 + sp * 10
			ci.draw_rect(Rect2(px, 3, 9, 4), Color.WHITE if wlv > Spells.MAX_LEVEL else Color("3a2f55"))
			ci.draw_rect(Rect2(px + 1, 4, 7.0 * mini(wlv, Spells.MAX_LEVEL) / Spells.MAX_LEVEL, 2), SPELL_COLORS[sp])
		if p.combo >= 5:
			var cc := Color.WHITE if int(time * 8) % 2 == 0 else G.player_fx(slot)
			PixelFont.draw(ci, "x%d" % p.combo, Vector2(x + 96, 10), 1, cc, dark)
		if not p.alive and p.lives > 0:
			PixelFont.draw(ci, "...", Vector2(x + 96, 10), 1, col)
		# XP bar and level
		var xf := clampf(float(p.xp) / float(p.xp_need), 0.0, 1.0)
		PixelFont.draw(ci, "LV%d" % p.level, Vector2(x, 17), 1, Color("5dff7a"), dark)
		ci.draw_rect(Rect2(x + 24, 19, 66, 3), dark)
		ci.draw_rect(Rect2(x + 25, 20, 64 * xf, 1), Color("5dff7a"))
	# Wave label on the top wall
	var wl := _clock(run_t)
	PixelFont.draw_centered(ci, wl, 240, 22, 1, Color("c9b8ff"), dark)
	# Boss bar
	if boss_f > 0.0:
		var bw := 300.0
		var bx := 240 - bw / 2
		PixelFont.draw_centered(ci, "LICH LORD", 240, 249, 1, Color("4dfff0"), dark)
		ci.draw_rect(Rect2(bx - 2, 258, bw + 4, 8), dark)
		ci.draw_rect(Rect2(bx, 260, bw, 4), Color("2c0d4d"))
		ci.draw_rect(Rect2(bx, 260, bw * boss_f, 4), Color("4dfff0") if boss_f > 0.5 else Color("ff4d6a"))
		ci.draw_rect(Rect2(bx, 260, bw * boss_f, 1), Color.WHITE)
	# Banner
	if banner.t > 0.0:
		var k: float = 1.0 - banner.t / banner.max
		var slide := 0.0
		if k < 0.12:
			slide = (1.0 - k / 0.12) * 260.0
		elif banner.t < 0.3:
			slide = -(1.0 - banner.t / 0.3) * 260.0
		var y := 96.0
		ci.draw_rect(Rect2(0 + slide, y - 8, 480, 44), Color(0.04, 0.0, 0.1, 0.6))
		ci.draw_rect(Rect2(0 + slide, y - 8, 480, 1), banner.color)
		ci.draw_rect(Rect2(0 + slide, y + 35, 480, 1), banner.color)
		var tw := PixelFont.text_width(banner.text, 3)
		PixelFont.draw_gradient(ci, banner.text, Vector2(240 - tw / 2.0 + slide, y), 3,
			Color.WHITE, banner.color, time * 6.0, 1.5)
		PixelFont.draw_centered(ci, banner.sub, 240 + slide, y + 25, 1, Color("fff6e0"), dark)
	# Screen flash
	if screen_flash.a > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), screen_flash)
	if game_over:
		_draw_game_over(ci)
	elif _anyone_picking():
		_draw_levelup(ci)
	elif paused:
		_draw_pause(ci)

# ======================================================== LEVEL-UP PICKS ===
func _anyone_picking() -> bool:
	for p: Dictionary in vp.values():
		if not (p.get("choices", []) as Array).is_empty():
			return true
	return false

## Local slots that have an offer open, in slot order: one row of cards each.
func _local_pick_slots() -> Array[int]:
	var out: Array[int] = []
	for r in Net.my_slots():
		if vp.has(r.slot) and not (vp[r.slot].choices as Array).is_empty():
			out.append(r.slot)
	out.sort()
	return out

func _card_rect(row: int, c: int) -> Rect2:
	var x0 := (480 - (CARD_W * 3 + CARD_GAP * 2)) / 2
	return Rect2(x0 + c * (CARD_W + CARD_GAP), PICK_TOP + row * PICK_ROW_H + 9, CARD_W, CARD_H)

func _draw_levelup(ci: CanvasItem) -> void:
	var dark := Color("0b0716")
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.03, 0.0, 0.08, 0.72))
	var tw := PixelFont.text_width("LEVEL UP!", 3)
	PixelFont.draw_gradient(ci, "LEVEL UP!", Vector2(240 - tw / 2.0, 22), 3, Color.WHITE, Color("5dff7a"), time * 5.0, 1.5)
	var rows := _local_pick_slots()
	for row in rows.size():
		var slot: int = rows[row]
		var p: Dictionary = vp[slot]
		var col := G.player_color(slot)
		var sent: Array = _pick_sent.get(slot, [-1, -1])
		var done := int(sent[1]) == int(p.offer)
		var y0 := PICK_TOP + row * PICK_ROW_H
		PixelFont.draw(ci, "P%d  LV%d  %s" % [slot + 1, p.level, "WAITING FOR THE OTHERS..." if done else "CHOOSE ONE"],
			Vector2(_card_rect(row, 0).position.x, y0), 1, col, dark)
		var choices: Array = p.choices
		for c in choices.size():
			var r := _card_rect(row, c)
			var sel: bool = (int(sent[0]) == c) if done else (int(_pick_sel.get(slot, 0)) == c)
			var idx: int = choices[c]
			ci.draw_rect(r.grow(1), col if sel else Color("3a2a58"))
			ci.draw_rect(r, Color("1d1233") if not sel else Color("2c1a4d"))
			var cx := r.position.x + r.size.x / 2.0
			PixelFont.draw_centered(ci, Upgrades.display_name(idx), cx, r.position.y + 5, 1,
				Color("ffd94d") if sel else Color.WHITE, dark)
			PixelFont.draw_centered(ci, Upgrades.description(idx), cx, r.position.y + 17, 1, Color("c9b8ff"), dark)
			var lv: int = p.choice_lv[c]
			PixelFont.draw_centered(ci, "NEW" if lv == 1 else "LV %d/%d" % [lv, Upgrades.max_level(idx)], cx,
				r.position.y + 29, 1, Color("5dff7a"), dark)
	var waiting: Array[String] = []
	for s in vp.keys():
		if not rows.has(s) and not (vp[s].choices as Array).is_empty():
			waiting.append("P%d" % (s + 1))
	if not waiting.is_empty():
		PixelFont.draw_centered(ci, " ".join(waiting) + " CHOOSING...", 240, 258, 1, Color("c9b8ff"), dark)

## Routes menu input to the pick rows of local players. Returns true if the event was used.
func _pick_input(event: InputEvent) -> bool:
	var rows := _local_pick_slots()
	if rows.is_empty():
		return false
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		var pos: Vector2 = event.position
		for row in rows.size():
			for c in (vp[rows[row]].choices as Array).size():
				if _card_rect(row, c).has_point(pos):
					_confirm_pick(rows[row], c)
					return true
		return true
	for slot: int in rows:
		var dev := -99
		for r in Net.my_slots():
			if r.slot == slot:
				dev = r.device
		var mine := (dev == G.DEV_KBM and (event is InputEventKey)) or \
			(dev != G.DEV_KBM and (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device == dev)
		if not mine:
			continue
		var n: int = (vp[slot].choices as Array).size()
		var d := _pick_dir(event)
		if d != 0:
			_pick_sel[slot] = wrapi(int(_pick_sel.get(slot, 0)) + d, 0, n)
			Sfx.play("menu_move")
			return true
		if PlayerInput.confirm_device(event) != -99:
			_confirm_pick(slot, int(_pick_sel.get(slot, 0)))
			return true
	return false

func _confirm_pick(slot: int, c: int) -> void:
	var sent: Array = _pick_sent.get(slot, [-1, -1])
	if int(sent[1]) == int(vp[slot].offer):
		return
	_pick_sel[slot] = c
	_pick_sent[slot] = [c, int(vp[slot].offer)]
	Sfx.play("menu_select")

## -1 left, +1 right, 0 none (keys, d-pad, or an edge of the left stick).
func _pick_dir(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_LEFT, KEY_A: return -1
			KEY_RIGHT, KEY_D: return 1
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_DPAD_LEFT: return -1
		if event.button_index == JOY_BUTTON_DPAD_RIGHT: return 1
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X:
		var key := "pickx%d" % event.device
		var was: float = _pick_sel.get(key, 0.0)
		_pick_sel[key] = event.axis_value
		if event.axis_value < -0.6 and was >= -0.6: return -1
		if event.axis_value > 0.6 and was <= 0.6: return 1
	return 0

func _heart(ci: CanvasItem, p: Vector2, full: bool) -> void:
	var c := Color("ff3b5c") if full else Color("3a2240")
	ci.draw_rect(Rect2(p + Vector2(0, 1), Vector2(5, 2)), c)
	ci.draw_rect(Rect2(p + Vector2(1, 0), Vector2(1, 1)), c)
	ci.draw_rect(Rect2(p + Vector2(3, 0), Vector2(1, 1)), c)
	ci.draw_rect(Rect2(p + Vector2(1, 3), Vector2(3, 1)), c)
	ci.draw_rect(Rect2(p + Vector2(2, 4), Vector2(1, 1)), c)
	if full:
		ci.draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 1)), Color("ffc0cc"))

func _hat(ci: CanvasItem, p: Vector2, c: Color) -> void:
	ci.draw_rect(Rect2(p + Vector2(2, 0), Vector2(1, 1)), c)
	ci.draw_rect(Rect2(p + Vector2(1, 1), Vector2(3, 2)), c)
	ci.draw_rect(Rect2(p + Vector2(0, 3), Vector2(5, 1)), c.darkened(0.3))

func _star(ci: CanvasItem, p: Vector2) -> void:
	var c := Color("ffe84d")
	ci.draw_rect(Rect2(p + Vector2(2, 0), Vector2(1, 5)), c)
	ci.draw_rect(Rect2(p + Vector2(0, 2), Vector2(5, 1)), c)
	ci.draw_rect(Rect2(p + Vector2(1, 1), Vector2(3, 3)), c)
	ci.draw_rect(Rect2(p + Vector2(2, 2), Vector2(1, 1)), Color.WHITE)

func _draw_game_over(ci: CanvasItem) -> void:
	var a := clampf(game_over_t / 1.0, 0.0, 1.0)
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.03, 0.0, 0.08, 0.75 * a))
	if game_over_t < 0.6:
		return
	var tw := PixelFont.text_width("GAME OVER", 5)
	PixelFont.draw(ci, "GAME OVER", Vector2(240 - tw / 2.0, 46) + Vector2(3, 3), 5, Color("0b0716"))
	PixelFont.draw_gradient(ci, "GAME OVER", Vector2(240 - tw / 2.0, 46), 5, Color("ffd94d"), Color("ff3b5c"), time * 3.0, 2.0)
	var y := 100
	for slot in 4:
		if not vp.has(slot):
			continue
		var p: Dictionary = vp[slot]
		PixelFont.draw(ci, "P%d" % (slot + 1), Vector2(150, y), 1, G.player_color(slot), Color("0b0716"))
		PixelFont.draw(ci, "%07d" % p.score, Vector2(270, y), 1, Color.WHITE, Color("0b0716"))
		y += 12
	y += 6
	PixelFont.draw(ci, "TOTAL", Vector2(150, y), 1, Color("ffd94d"))
	PixelFont.draw(ci, "%07d" % final_score, Vector2(270, y), 1, Color("ffd94d"))
	y += 12
	PixelFont.draw(ci, "BEST", Vector2(150, y), 1, Color("c9b8ff"))
	PixelFont.draw(ci, "%07d" % G.high_score, Vector2(270, y), 1, Color("c9b8ff"))
	PixelFont.draw_centered(ci, "SURVIVED " + _clock(run_t), 240, y + 18, 1, Color("8bff9e"))
	if game_over_t > 2.0 and int(time * 2.5) % 2 == 0:
		var msg := "PRESS FIRE TO CONTINUE" if is_host else "WAITING FOR HOST..."
		if G.touch_active and is_host:
			msg = "TAP TO CONTINUE"
		PixelFont.draw_centered(ci, msg, 240, 236, 1, Color.WHITE, Color("0b0716"))

func _draw_pause(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.03, 0.0, 0.08, 0.7))
	var tw := PixelFont.text_width("PAUSED", 4)
	PixelFont.draw_gradient(ci, "PAUSED", Vector2(240 - tw / 2.0, 80), 4, Color.WHITE, Color("b78cff"), time * 4.0, 1.0)
	var items := ["RESUME", "QUIT TO TITLE"]
	for i in items.size():
		var sel := i == pause_sel
		var c := Color("ffd94d") if sel else Color("8a7aa8")
		PixelFont.draw_centered(ci, ("> " + items[i] + " <") if sel else items[i], 240, 130 + i * 18, 2 if sel else 1, c, Color("0b0716"))

# ============================================================== INPUT ===
func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		if game_over_t > 2.0 and is_host:
			var tapped = event is InputEventScreenTouch and event.pressed
			var clicked = event is InputEventMouseButton and event.pressed
			if PlayerInput.confirm_device(event) != -99 or tapped or clicked or \
					(event is InputEventKey and event.pressed and event.physical_keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]):
				_quit_to_title()
		return
	var start = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE, KEY_P]) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START)
	if start:
		_toggle_pause()
		return
	if not paused and _pick_input(event):
		get_viewport().set_input_as_handled()
		return
	if paused:
		var d := PlayerInput.menu_dir(event)
		if d != 0:
			pause_sel = wrapi(pause_sel + d, 0, 2)
			Sfx.play("menu_move")
		if PlayerInput.confirm_device(event) != -99:
			Sfx.play("menu_select")
			if pause_sel == 0:
				_toggle_pause()
			else:
				_quit_to_title()
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
			var y: float = event.position.y
			if y > 122 and y < 145:
				_toggle_pause()
			elif y >= 145 and y < 170:
				_quit_to_title()

func _toggle_pause() -> void:
	if game_over:
		return
	paused = not paused
	pause_sel = 0
	Sfx.play("menu_select")

func _quit_to_title() -> void:
	Engine.time_scale = 1.0
	if Net.mode == Net.Mode.HOST:
		Net.send_back_to_title()
	Net.shutdown()
	G.goto_title()

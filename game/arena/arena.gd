extends Node2D
## Match scene: runs the World on the host, mirrors it on clients, and draws
## everything (sprites, spells, particles, HUD, banners, touch controls).

const SNAP_EVERY := 2 # physics frames between snapshots sent to clients

const SPELL_COLORS := [Color("b78cff"), Color("ff7a2a"), Color("7fe8ff"), Color("ffe84d"), Color("ff7ae6")]
const ENEMY_KEYS := ["goblin", "skeleton", "slime", "mslime", "bat", "orc", "mage", "lich", "wraith", "tome", "gargoyle", "priest"]
## Shadow width under each enemy type (bats and wraiths float without one).
const ENEMY_SHADOW := [10, 10, 12, 8, 8, 14, 10, 26, 0, 10, 14, 10]
const ENEMY_ANIM := [7.0, 5.0, 0.0, 6.0, 12.0, 4.0, 3.0, 2.0, 3.0, 9.0, 6.0, 2.5]
const PICKUP_KEYS := ["coin", "gem", "potion", "tome_fire", "tome_frost", "tome_storm", "tome_star", "boot", "tome_orbit", "xp", "chest"]
const PICKUP_NAMES := ["", "", "POTION +2", "FIREBALL!", "FROST FAN!", "CHAIN LIGHTNING!", "STARFALL!", "HASTE!", "RUNE SHIELD!", "", ""]
## Loot tier colours (Loot.COMMON .. Loot.ULTRA): readable in 3 seconds with the sound off.
const RARITY_COLORS := [Color("c9c9d6"), Color("4d9bff"), Color("c04dff"), Color("ffb84d"), Color("ff4df2")]
## Seconds a chest reel spins before it shows the item, and how long the item stays up after.
const REEL_SPIN := 1.0
const REEL_SHOW := 1.6
const ENEMY_NAMES := ["GOBLIN", "SKELETON", "SLIME", "SLIMELING", "BAT", "ORC BRUTE", "DARK MAGE", "LICH LORD", "WRAITH", "CURSED TOME", "GARGOYLE", "BONE PRIEST"]

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
var vsh: Array = [] # shrine rows from the snapshot: [kind, x, y, life, charge fraction, cost]
var _bets: Array = [] # shrine reels: {slot, pos, kind, outcome, t, spin, shown}
const SHRINE_COLORS := [Color("ffd23d"), Color("ff4df2")]
## The rune a solo altar's cast lands on, per Gamble.SOLO_OUTCOMES (-1: a blank stone).
const OUTCOME_RUNES := [0, 5, 3, -1, 2]
## The fate card the team altar turns over, per Gamble.TEAM_OUTCOMES.
const FATE_CARDS := ["sun", "death"]
var wave := 1
var phase := 0
var phase_t := 0.0
var boss_f := -1.0
var boss_final := false # the boss on screen is the Archlich
var victory := false # the Archlich fell: the run is won
var run_t := 0.0 # seconds of fighting, from the snapshot
var _reveals: Array = [] # chest reels: {slot, pos, item, tier, t, shown}
var doors := [0.0, 0.0, 0.0, 0.0]
var door_anim := [0.0, 0.0, 0.0, 0.0]
var game_over := false
var game_over_t := 0.0
var final_score := 0
var crystals_earned := 0
var results: Results = null # the run record, from EV_RESULTS

var shake := 0.0
var screen_flash := Color(0, 0, 0, 0)
var banner := {"text": "", "sub": "", "t": 0.0, "max": 1.0, "color": Color.WHITE, "act": ""}
## Banners waiting for the one on screen to finish (an act card is followed by its boss).
var _banner_queue: Array = []
## The act of the tower the run is in (Lore.ACTS); the backdrop fades to the next act's.
var act := 0
var bg_next: Sprite2D
var _act_fade := -1.0
var decals: Array = [] # [pos, color, size, life]
var paused := false
var pause_sel := 0
var pause_options := false
var options := OptionsPanel.new()
const PAUSE_ITEMS := ["RESUME", "OPTIONS", "QUIT TO TITLE"]
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
## One player picking: full tarot cards.
const TAROT_W := 100
const TAROT_H := 162
const TAROT_GAP := 16
const TAROT_TOP := 52
## slot -> [offer, time it was dealt], for the deal animation.
var _pick_dealt := {}
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
	bg.texture = ArenaBg.build(ArenaBg.OSSUARY)
	root.add_child(bg)
	bg_next = Sprite2D.new()
	bg_next.centered = false
	bg_next.visible = false
	root.add_child(bg_next)
	decal_layer = _layer(false)
	decal_layer.draw.connect(_timed.bind("draw_decals", _draw_decals))
	env_layer = _layer(false)
	env_layer.draw.connect(_timed.bind("draw_env", _draw_env))
	env_add = _layer(true)
	env_add.draw.connect(_timed.bind("draw_env_add", _draw_env_add))
	ent_layer = _layer(false)
	ent_layer.draw.connect(_timed.bind("draw_entities", _draw_entities))
	fx = Fx.new()
	root.add_child(fx)
	shot_layer = _layer(true)
	shot_layer.draw.connect(_timed.bind("draw_shots", _draw_shots))
	eshot_layer = _layer(false)
	eshot_layer.draw.connect(_timed.bind("draw_eshots", _draw_eshots))
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
	hud.draw.connect(_timed.bind("draw_hud", _draw_hud))
	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 11
	add_child(touch_layer)
	touch = TouchControls.new()
	touch_layer.add_child(touch)
	PlayerInput.touch = touch
	touch.pause_pressed.connect(_toggle_pause)

	G.slot_wizard = Net.wizard_picks()
	Net.snapshot_received.connect(_on_snapshot)
	Net.roster_changed.connect(_on_roster_changed)
	if is_host:
		var slots := []
		for r in Net.roster:
			slots.append(r.slot)
		if slots.is_empty():
			slots.append(0)
		world = World.new(slots, int(Flags.get_arg("seed", "0")), null, Net.wizard_picks())
		world.apply_meta(Save.run_bonuses())
	Sfx.music(_act_music())

## Runs a draw callback and books its script time with PerfMeter (when the perf harness is on).
func _timed(label: String, fn: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	fn.call()
	PerfMeter.since(label, t0)

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
		var t0 := Time.get_ticks_usec()
		world.step(dt, inputs)
		PerfMeter.since("world_step", t0)
		t0 = Time.get_ticks_usec()
		var snap := world.snapshot()
		var evs := world.take_events()
		_apply_snapshot(snap, true)
		PerfMeter.since("snapshot", t0)
		t0 = Time.get_ticks_usec()
		_handle_events(evs)
		PerfMeter.since("events", t0)
		pending_events.append_array(evs)
		frame += 1
		if frame % SNAP_EVERY == 0 and Net.is_online():
			snap["ev"] = pending_events
			Net.send_snapshot(snap)
			pending_events = []
		elif not Net.is_online():
			pending_events.clear()

func _process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_view(dt)
	PerfMeter.since("arena_process", t0)

func _process_view(dt: float) -> void:
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
	elif not _banner_queue.is_empty():
		banner = _banner_queue.pop_front()
		if banner.act != "":
			Sfx.play("gong")
	_update_act(dt)
	_update_reveals(dt)
	_update_bets(dt)
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
	var goal := SmashBot.shrine_goal(vp[slot].pos, float(vp[slot].get("gold", 0)), vsh)
	return _bots[slot].decide(slot, vp[slot].pos, G.ARENA.get_center(), time, en, es, pk, goal)

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
		G.slot_wizard[slot] = int(pl[i + 10])
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
		p.gold = int(pl[i + 34])
		p.max_hp = int(pl[i + 35])
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
		e.elite = en[i + 8] > 0.5 and en[i + 8] < 1.5
		e.final = en[i + 8] > 1.5
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
	vsh.clear()
	var shp: PackedFloat32Array = snap.get("sh", PackedFloat32Array())
	i = 0
	while i + 6 <= shp.size():
		vsh.append([int(shp[i]), shp[i + 1], shp[i + 2], shp[i + 3], shp[i + 4], int(shp[i + 5])])
		i += 6
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
	boss_final = w.size() > 9 and w[9] > 0.5
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
				var gc := [Color("2f7a2a"), Color("b7a98e"), Color("158f86"), Color("158f86"), Color("5a1a8a"), Color("4d5166"), Color("3b1f6e"), Color("4a1a7a"), Color("4f9a94"), Color("4e0f18"), Color("57546a"), Color("2e1a12")]
				if t == World.TOME:
					fx.burst(pos + Vector2(0, -6), 10, 70.0, 0.7, 1.5, Color("efe2c0"), Color("8a1f2c"), false, 60.0)
					Sfx.play("page_turn", -4.0, _fx_rng.randf_range(0.9, 1.2), 0.1)
				elif t == World.WRAITH:
					Sfx.play("ghost", -8.0, _fx_rng.randf_range(0.9, 1.3), 0.15)
				_decal(pos + Vector2(0, 4), gc[clampi(t, 0, gc.size() - 1)], 4.0 if t != World.ORC else 7.0)
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
				if Lore.opens_act(w):
					_act_card(Lore.act_of(w))
				if int(ev[4]) == 2:
					_banner(Lore.ARCHLICH_TITLE, Lore.ARCHLICH_NAME + " DESCENDS", Color("ff4df2"), 3.2, true)
					Sfx.play("boss_roar", 0.0, 0.7)
					Sfx.play("bell_toll", -2.0)
				elif int(ev[4]) == 1:
					_banner("THE LICH LORD", Lore.LICH_NAME + " RISES", Color("ff4d6a"), 2.6, true)
					Sfx.play("portal")
				elif w > 1:
					_banner("MINUTE %d" % w, Lore.minute_line(w), Color("ffd94d"), 1.8)
					Sfx.play("wave_start", -4.0)
				else:
					_act_card(0)
					Sfx.play("wave_start")
				if int(ev[4]) == 0 and boss_f <= 0.0:
					Sfx.music(_act_music())
			World.EV_RIFT:
				# A shrinking ring and a dark core warn where the group will burst out.
				var life := float(ev[4])
				fx.ring(pos, float(ev[3]) + 10.0, 3.0, life, Color("ff4df2"), 2.0)
				fx.ring(pos, float(ev[3]) + 4.0, 1.0, life, Color("4a1a7a"), 3.0)
				fx.sparkle(pos, Color("ff4df2"), 8)
			World.EV_CHEST:
				var code := int(ev[4])
				_reveals.append({"slot": int(ev[3]), "pos": pos, "item": code / 8, "tier": code % 8, "t": 0.0, "shown": false})
				Sfx.play("door", -6.0, 1.4)
			World.EV_SHRINE_UP:
				var sk := int(ev[3])
				fx.ring(pos, 2.0, 30.0, 0.6, SHRINE_COLORS[sk], 2.0)
				fx.sparkle(pos, SHRINE_COLORS[sk], 14)
				if sk == Gamble.TEAM:
					_banner("THE FATE CARD", "ONE WIZARD DRAWS FOR THE WHOLE PARTY", SHRINE_COLORS[sk], 2.4)
					Sfx.play("portal", -4.0)
				else:
					fx.text(pos + Vector2(0, -20), "RUNE ALTAR", SHRINE_COLORS[sk], 1.2, 1)
					Sfx.play("candle", -2.0)
			World.EV_SHRINE:
				var code := int(ev[4])
				var bk := code / 16
				var spin: float = Tuning.shared().team_reel if bk == Gamble.TEAM else Tuning.shared().shrine_reel
				_bets.append({"slot": int(ev[3]), "pos": pos, "kind": bk, "outcome": code % 16, "t": 0.0, "spin": spin, "shown": false})
				Sfx.play("coin", -2.0, 0.8)
				if bk == Gamble.TEAM:
					Sfx.play("card_deal")
					Sfx.play("whisper", -2.0)
					Sfx.music("music_boss")
				else:
					Sfx.play("rune_cast")
			World.EV_GAMBLE:
				var code := int(ev[4])
				var gk := code / 16
				var good := Gamble.is_good(gk, code % 16)
				var col := Color("8bff9e") if good else Color("ff3b5c")
				if gk == Gamble.TEAM:
					for q: Dictionary in vp.values():
						fx.burst(q.pos + Vector2(0, -8), 24, 120.0, 0.8, 2.0, Color.WHITE, col, true, 40.0, true)
					screen_flash = Color(col.r, col.g, col.b, 0.35)
					_add_shake(6.0 if good else 10.0)
					Sfx.play("gong")
					Sfx.play("wave_clear" if good else "boss_roar", 0.0, 1.0)
					Sfx.music(_act_music())
				else:
					fx.burst(pos, 16, 90.0, 0.6, 1.5, Color.WHITE, col, true)
					Sfx.play("rune_good" if good else "rune_bad", -2.0)
			World.EV_WARD:
				fx.text(pos + Vector2(0, -10), "BLOCKED", Color("8bdcff"), 0.8, 1)
				fx.ring(pos, 4.0, 16.0, 0.3, Color("8bdcff"), 2.0)
				Sfx.play("orbit", -4.0, 1.3)
			World.EV_RAISE:
				fx.ring(pos, 4.0, 26.0, 0.5, Color("6dff9a"), 2.0)
				fx.burst(pos + Vector2(0, -4), 14, 60.0, 0.6, 1.5, Color("6dff9a"), Color("efe7d2"), true, -40.0)
				fx.text(pos + Vector2(0, -20), "RISE!", Color("6dff9a"), 0.8, 1)
				Sfx.play("portal", -6.0, 1.3, 0.2)
			World.EV_ELITE:
				var elite_name: String = ENEMY_NAMES[clampi(int(ev[3]), 0, ENEMY_NAMES.size() - 1)]
				fx.text(pos + Vector2(0, -24), Lore.elite_epithet(int(ev[1]) * 7 + int(ev[2])), Color("ffd23d"), 1.6, 1)
				fx.text(pos + Vector2(0, -15), "ELITE " + elite_name, Color("ffb84d"), 1.6, 1)
				fx.ring(pos, 2.0, 24.0, 0.5, Color("ffb84d"), 2.0)
				Sfx.play("charge", -2.0, 0.8)
			World.EV_BOSS:
				Sfx.play("boss_roar", 0.0, 0.7 if int(ev[3]) == 1 else 1.0)
				Sfx.music("music_boss")
				_add_shake(12.0 if int(ev[3]) == 1 else 8.0)
				screen_flash = Color(1.0, 0.3, 0.95, 0.5) if int(ev[3]) == 1 else Color(0.3, 1.0, 0.9, 0.4)
				if int(ev[3]) == 1:
					fx.nova(pos + Vector2(0, -16), Color("ff4df2"))
			World.EV_COMBO:
				var col := G.player_fx(int(ev[4]))
				# One call over the wizard who made it; big only for the rare x100 and beyond.
				var who: Vector2 = vp[int(ev[4])].pos if vp.has(int(ev[4])) else pos
				fx.text(who + Vector2(0, -22), World.COMBO_CALLS.get(int(ev[3]), "COMBO!"), col, 1.3,
					2 if int(ev[3]) >= 100 else 1)
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
				if int(ev[4]) == 1:
					_banner("ARCHLICH DESTROYED!", "+%d x COMBO" % (World.STATS[World.LICH][3] * World.FINAL_REWARD), Color("ff4df2"), 3.0)
				else:
					_banner("LICH LORD DESTROYED!", "+5000 x COMBO", Color("4dfff0"), 3.0)
					Sfx.music(_act_music())
			World.EV_VICTORY:
				victory = true
				Sfx.play("wave_clear", 0.0, 0.8)
				Sfx.music("music_title")
				for q: Dictionary in vp.values():
					fx.burst(q.pos + Vector2(0, -8), 30, 140.0, 1.0, 2.0, Color.WHITE, Color("ffd94d"), true, 40.0, true)
			World.EV_RESULTS:
				results = Results.from_dict(ev[3])
			World.EV_GAMEOVER:
				game_over = true
				game_over_t = 0.0
				final_score = int(ev[3])
				run_t = float(ev[1])
				crystals_earned = G.finish_run(final_score, float(ev[1]), int(ev[2]), int(ev[4]), victory)
				if is_host:
					Platform.finish_run(results, victory, float(ev[1]))
				if not victory:
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

## Advances chest reels; when a reel stops it plays its tier's sound and burst.
func _update_reveals(dt: float) -> void:
	for r: Dictionary in _reveals:
		var prev: float = r.t
		r.t += dt
		if vp.has(r.slot):
			r.pos = (vp[r.slot] as Dictionary).pos
		if not r.shown and r.t < REEL_SPIN and int(r.t * 14.0) != int(prev * 14.0):
			Sfx.play("menu_move", -10.0, 1.0 + r.t * 0.6)
		if not r.shown and r.t >= REEL_SPIN:
			r.shown = true
			var col: Color = RARITY_COLORS[r.tier]
			var at: Vector2 = r.pos + Vector2(0, -34)
			fx.burst(at, 10 + 8 * r.tier, 60.0 + 30.0 * r.tier, 0.6, 1.5, Color.WHITE, col, true)
			match r.tier:
				Loot.COMMON:
					Sfx.play("pickup", -4.0)
				Loot.RARE:
					Sfx.play("powerup", -4.0)
				Loot.EPIC:
					Sfx.play("powerup", -2.0, 1.2)
				_:
					Sfx.play("wave_clear", -2.0, 1.1 if r.tier == Loot.LEGENDARY else 1.3)
					fx.ring(at, 4.0, 40.0 + 20.0 * (r.tier - Loot.LEGENDARY), 0.6, col, 2.0)
					_add_shake(3.0 * (r.tier - Loot.EPIC))
	_reveals = _reveals.filter(func(r: Dictionary) -> bool: return r.t < REEL_SPIN + REEL_SHOW)

## Altars: a rune altar (solo) with three rune stones circling it, or the fate altar (team) with a tarot card
## turning over it. The price floats above and a ring fills while a wizard bets.
func _draw_shrines(ci: CanvasItem) -> void:
	var dark := Color("0b0716")
	for r: Array in vsh:
		var kind: int = r[0]
		var at := Vector2(r[1], r[2])
		var life: float = r[3]
		if life < 4.0 and int(life * 8.0) % 2 == 0:
			continue
		var col: Color = SHRINE_COLORS[kind]
		var big := 1.5 if kind == Gamble.TEAM else 1.0
		var pulse := 0.5 + 0.5 * sin(time * 4.0)
		ci.draw_circle(at, 15.0 * big, Color(col.r, col.g, col.b, 0.10 + 0.08 * pulse))
		Occult.pentagram(ci, at + Vector2(0, 2), 11.0 * big, Color(col.r, col.g, col.b, 0.35 + 0.2 * pulse), time * 0.3)
		ci.draw_arc(at + Vector2(0, 2), 12.0 * big, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.45), 1.0)
		# The altar stone with two candles.
		var w := 12.0 * big
		var top := (at + Vector2(-w / 2.0, -3)).floor()
		ci.draw_rect(Rect2(top + Vector2(0, 1), Vector2(w, 6)), Color("2a2140"))
		ci.draw_rect(Rect2(top, Vector2(w, 2)), Color("7a6aa0"))
		ci.draw_rect(Rect2(top + Vector2(2, 2), Vector2(w - 4, 4)), Color("3a2f55"))
		Occult.candle(ci, top + Vector2(1, 0), time, at.x, 4)
		Occult.candle(ci, top + Vector2(w - 1, 0), time, at.y, 4)
		if kind == Gamble.TEAM:
			var turn := absf(cos(time * 1.6))
			var cw := maxf(1.0, 14.0 * turn)
			var cr := Rect2(at.x - cw / 2.0, at.y - 30.0 - 2.0 * sin(time * 2.0), cw, 20)
			TarotArt.draw_back(ci, cr)
		else:
			for k in 3:
				var ang := time * 1.4 + k * TAU / 3.0
				var sp := at + Vector2(cos(ang) * 10.0, -13.0 + sin(ang) * 4.0)
				_rune_stone(ci, sp.floor(), (k * 3 + int(time * 0.5)) % Occult.RUNES.size(), col, 1.0)
		var charge: float = r[4]
		if charge > 0.0:
			ci.draw_arc(at, 16.0 * big, -PI / 2.0, -PI / 2.0 + TAU * clampf(charge, 0.0, 1.0), 32, Color.WHITE, 2.0)
		PixelFont.draw_centered(ci, "%dG" % int(r[5]), at.x, at.y - (32.0 if kind == Gamble.SOLO else 50.0), 1, col, dark)


## A rune stone: a pale pebble with a rune cut into it (`rune` -1 for a blank stone).
func _rune_stone(ci: CanvasItem, p: Vector2, rune: int, glow: Color, a: float) -> void:
	ci.draw_rect(Rect2(p + Vector2(-3, -4), Vector2(7, 9)), Color(0.04, 0.0, 0.1, a))
	ci.draw_rect(Rect2(p + Vector2(-2, -4), Vector2(5, 9)), Color(0.85, 0.82, 0.74, a))
	ci.draw_rect(Rect2(p + Vector2(-3, -3), Vector2(7, 7)), Color(0.85, 0.82, 0.74, a))
	ci.draw_rect(Rect2(p + Vector2(-3, 3), Vector2(7, 1)), Color(0.6, 0.56, 0.5, a))
	if rune >= 0:
		Occult.rune(ci, p + Vector2(-2, -3), rune, Color(glow.r * 0.5, glow.g * 0.3, glow.b * 0.2, a))


## The act's own battle music (Act I's until a track for the act is in).
func _act_music() -> String:
	var n: String = ["music_battle", "music_library", "music_sanctum"][clampi(act, 0, 2)]
	return n if Sfx.has_music(n) else "music_battle"

func _update_bets(dt: float) -> void:
	for b: Dictionary in _bets:
		var prev: float = b.t
		b.t += dt
		# The reel ticks slower as it runs down, like a wheel.
		var rate := 16.0 * (1.0 - 0.7 * clampf(b.t / b.spin, 0.0, 1.0))
		if b.t < b.spin and int(b.t * rate) != int(prev * rate):
			Sfx.play("menu_move", -8.0 if b.kind == Gamble.TEAM else -12.0, 0.9 + b.t / b.spin * 0.5)
		if not b.shown and b.t >= b.spin:
			b.shown = true
	_bets = _bets.filter(func(b: Dictionary) -> bool: return b.t < b.spin + REEL_SHOW)

## Altar casts: a solo cast throws three rune stones over the altar and the middle one lands on the outcome's
## rune; the team bet turns a fate card in the middle of the screen, The Sun or Death.
func _draw_bets(ci: CanvasItem, dark: Color) -> void:
	for b: Dictionary in _bets:
		var spinning: bool = b.t < b.spin
		var good: bool = Gamble.is_good(b.kind, b.outcome)
		var col := Color("8bff9e") if good else Color("ff3b5c")
		var text: String = Gamble.outcome_name(b.kind, b.outcome)
		if b.kind == Gamble.TEAM:
			_draw_fate(ci, b, spinning, col, text, dark)
			continue
		var at: Vector2 = (b.pos as Vector2) + Vector2(0, -30)
		var k := clampf(b.t / b.spin, 0.0, 1.0)
		for n in 3:
			# Each stone flies up and tumbles down; the middle one lands last, on the outcome.
			var land := 0.5 + n * 0.25 if n != 1 else 1.0
			var u := clampf(k / land, 0.0, 1.0)
			var p := at + Vector2((n - 1) * 11.0, -sin(u * PI) * 16.0)
			var rune: int = (int(b.t * 12.0) + n * 3 + int(b.slot)) % Occult.RUNES.size()
			if u >= 1.0:
				rune = OUTCOME_RUNES[b.outcome] if n == 1 else (n * 5 + int(b.slot)) % Occult.RUNES.size()
			_rune_stone(ci, p.floor(), rune, col if (u >= 1.0 and n == 1) else Color("d8b04a"), 1.0 if n == 1 or not spinning else 0.7)
		if not spinning:
			var lift := minf(1.0, (b.t - b.spin) * 6.0)
			ci.draw_circle(at, 9.0, Color(col.r, col.g, col.b, 0.25 * lift))
			PixelFont.draw_centered(ci, text, at.x, at.y - 22, 1, col, dark)


## The team bet: the bettor's fate card shuffles between The Sun and Death, then turns face up.
func _draw_fate(ci: CanvasItem, b: Dictionary, spinning: bool, col: Color, text: String, dark: Color) -> void:
	var r := Rect2(240 - 34, 40, 68, 90)
	ci.draw_rect(Rect2(0, 34, 480, 132), Color(0.02, 0.0, 0.05, 0.55))
	PixelFont.draw_centered(ci, "P%d DRAWS FOR ALL" % (int(b.slot) + 1), 240, r.position.y - 2 + 112, 1, G.player_color(b.slot), dark)
	if spinning:
		var k: float = b.t / b.spin
		var turn := absf(cos(b.t * (6.0 + 10.0 * (1.0 - k))))
		var w := r.size.x * turn
		TarotArt.draw_back(ci, Rect2(240 - w / 2.0, r.position.y, w, r.size.y))
		return
	var key: String = FATE_CARDS[b.outcome]
	var title: String = TarotArt.ARCANA[key][1]
	TarotArt.draw_card(ci, r, key, title, "", "", true, col, time)
	PixelFont.draw_centered(ci, text, 240, r.end.y + 16, 2, col, dark)


## Chest reels over the wizard who opened them: tier names spin, then the item shows in its tier's colour.
func _draw_reveals(ci: CanvasItem, dark: Color) -> void:
	for r: Dictionary in _reveals:
		var at: Vector2 = (r.pos as Vector2) + Vector2(0, -34)
		var spinning: bool = r.t < REEL_SPIN
		var tier: int = (int(r.t * 14.0) + r.slot) % RARITY_COLORS.size() if spinning else r.tier
		var col: Color = RARITY_COLORS[tier]
		if tier == Loot.ULTRA and not spinning:
			col = col.lerp(Color.WHITE, 0.5 + 0.5 * sin(time * 12.0))
		var label: String = Loot.RARITY_NAMES[tier]
		var title: String = "?????" if spinning else Loot.item_name(r.item)
		var w: float = maxf(PixelFont.text_width(label, 1), PixelFont.text_width(title, 1)) + 8.0
		var box := Rect2((at - Vector2(w / 2.0, 9)).floor(), Vector2(w, 19))
		ci.draw_rect(box, Color(0.04, 0.0, 0.1, 0.85))
		ci.draw_rect(box, col, false, 1.0)
		PixelFont.draw_centered(ci, label, at.x, box.position.y + 2, 1, col, dark)
		PixelFont.draw_centered(ci, title, at.x, box.position.y + 11, 1, Color.WHITE if spinning else col, dark)

## Shows a banner now, or after the one on screen when `wait` is set.
func _banner(text: String, sub: String, color: Color, dur: float, wait: bool = false) -> void:
	var b := {"text": text, "sub": sub, "t": dur, "max": dur, "color": color, "act": ""}
	if wait and (banner.t > 0.0 or not _banner_queue.is_empty()):
		_banner_queue.append(b)
	else:
		banner = b


## The card that opens an act: ACT II, its name and subtitle, with a gong.
func _act_card(a: int) -> void:
	var b := {"text": Lore.act_name(a), "sub": Lore.act_subtitle(a), "t": 3.4, "max": 3.4,
		"color": [Color("8bdcff"), Color("ff8a2a"), Color("ffd94d")][clampi(a, 0, 2)], "act": Lore.act_heading(a)}
	_banner_queue.clear()
	banner = b
	Sfx.play("gong")


## Fades the backdrop to the act the run minute is in.
func _update_act(dt: float) -> void:
	var want := Lore.act_of(wave)
	if want != act and _act_fade < 0.0:
		act = want
		bg_next.texture = ArenaBg.build(act)
		bg_next.modulate.a = 0.0
		bg_next.visible = true
		_act_fade = 0.0
		screen_flash = Color(1.0, 0.9, 0.7, 0.5)
	# Each act has its own air: dust in the Ossuary, embers in the Library, falling starlight in the Sanctum.
	var ar := G.ARENA
	if _fx_rng.randf() < dt * [3.0, 14.0, 9.0][act]:
		match act:
			0:
				fx.spawn(Vector2(_fx_rng.randf_range(ar.position.x, ar.end.x), _fx_rng.randf_range(ar.position.y, ar.end.y)),
					Vector2(_fx_rng.randf_range(-3, 3), _fx_rng.randf_range(-4, -1)), 4.0, 1.0, Color(0.8, 0.75, 0.9, 0.25),
					Color(0.8, 0.75, 0.9, 0.0), false, 0.0)
			1:
				var c := Color("ff8a2a") if _fx_rng.randf() < 0.7 else Color("ffd94d")
				fx.spawn(Vector2(_fx_rng.randf_range(ar.position.x, ar.end.x), ar.end.y - _fx_rng.randf_range(0, 30)),
					Vector2(_fx_rng.randf_range(-8, 8), _fx_rng.randf_range(-30, -14)), _fx_rng.randf_range(2.0, 4.0), 1.0, c,
					Color(c.r, 0.1, 0.0, 0.0), true, 0.0)
			2:
				var c := Color("9ad8ff") if _fx_rng.randf() < 0.6 else Color("ffd94d")
				fx.spawn(Vector2(_fx_rng.randf_range(ar.position.x, ar.end.x), ar.position.y),
					Vector2(_fx_rng.randf_range(-4, 4), _fx_rng.randf_range(12, 26)), _fx_rng.randf_range(3.0, 6.0), 1.0, c,
					Color(c.r, c.g, c.b, 0.0), true, 0.0)
	if _act_fade >= 0.0:
		_act_fade += dt
		bg_next.modulate.a = clampf(_act_fade / 2.0, 0.0, 1.0)
		if _act_fade >= 2.0:
			bg.texture = bg_next.texture
			bg_next.visible = false
			_act_fade = -1.0

func _add_shake(v: float) -> void:
	if not Save.settings.shake:
		return
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
		World.PK_CHEST: return Color("ffd23d")
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
		# A squashed blob of rects: rects batch into one draw call, where circles cost one call each.
		var r := s * 0.6
		var o := p.floor()
		decal_layer.draw_rect(Rect2(o.x - r, o.y - r * 0.35, r * 2.0, r * 0.7), c)
		decal_layer.draw_rect(Rect2(o.x - r * 0.7, o.y - r * 0.55, r * 1.4, r * 1.1), c)
		for k in 4:
			var q := Vector2(((seed >> (k * 4)) % 13) - 6, (((seed >> (k * 4 + 2)) % 9) - 4) * 0.55) * s * 0.18
			var dr := s * 0.3
			decal_layer.draw_rect(Rect2((o + q - Vector2(dr, dr * 0.55)).floor(), Vector2(dr * 2.0, dr * 1.1)), c)

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
	_draw_shrines(ci)
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
			if ENEMY_SHADOW[e.type] > 0 and e.type != World.BAT and not (e.type == World.GARGOYLE and e.state == 1):
				_shadow(ci, e.pos, ENEMY_SHADOW[e.type])
	# Glows under the elites and the Archlich go before the sprites, in one pass, so sprites batch together.
	for e: Dictionary in ve.values():
		if e.get("final", false):
			ci.draw_circle(e.pos + Vector2(0, -14), 20.0 + sin(time * 4.0) * 2.0, Color(1.0, 0.3, 0.95, 0.18))
			ci.draw_circle(e.pos + Vector2(0, -14), 14.0 + sin(time * 6.0) * 1.5, Color(1.0, 0.85, 0.3, 0.16))
		elif e.get("elite", false):
			ci.draw_circle(e.pos + Vector2(0, -6), 11.0 + sin(time * 6.0 + e.t) * 1.5, Color(1.0, 0.72, 0.3, 0.22))
	for it in list:
		if it[1] == 0:
			_draw_player(ci, it[2])
		else:
			_draw_enemy(ci, it[2])
	_draw_enemy_bars(ci)

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
	var key := "wiz%d_%s_%s" % [G.wizard_of(slot), dirkey, fr]
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
		elif t == World.GARGOYLE and e.state == 0:
			fr = "a"
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
		World.WRAITH:
			# Faded: a thin ghost the spells pass through.
			feet.y -= 3.0 + floorf(sin(e.t * 3.0) * 1.5)
			mod.a = 0.25 + 0.1 * sin(time * 20.0) if e.state == 1 else 0.85
		World.TOME:
			feet.y -= 4.0 + floorf(sin(e.t * 6.0) * 1.5)
			if e.state == 1:
				feet.x += _fx_rng.randf_range(-1.0, 1.0)
				mod = Color(1.5, 0.7, 0.7)
		World.GARGOYLE:
			if e.state == 0:
				mod = Color(0.75, 0.75, 0.8)
			else:
				feet.y -= 8.0
				mod = Color(1.2, 1.0, 1.0)
		World.PRIEST:
			if e.state == 1:
				mod = Color(0.9, 1.5, 1.0)
	if e.get("final", false):
		# The Archlich: a darker violet robe (its glow is drawn under the sprites in _draw_entities).
		mod = mod * Color(1.3, 0.75, 1.35)
	elif e.get("elite", false):
		# Elites: a warmer tint (and a gold glow under the sprites) so they stand out of the horde.
		mod = mod * Color(1.35, 1.1, 0.8)
	var flash: bool = e.flash > 0.0 and (t != World.LICH or int(time * 40.0) % 3 == 0)
	Sprites.draw_at(ci, key, feet, flip and t != World.BAT and t != World.LICH, flash, mod)

## Health bars for the big and elite enemies, drawn after every sprite so they do not split the sprite batch.
func _draw_enemy_bars(ci: CanvasItem) -> void:
	for e: Dictionary in ve.values():
		var t: int = e.type
		if (t == World.ORC or t == World.MAGE or e.get("elite", false)) and e.hpf < 1.0:
			var w := 14.0
			var bp: Vector2 = (e.pos + Vector2(-w / 2, 4)).floor()
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
		var mh: int = p.get("max_hp", World.BASE_HEARTS)
		var hstep := 7.0 if mh <= World.BASE_HEARTS else 35.0 / mh
		for h in mh:
			_heart(ci, Vector2(x + floorf(h * hstep), 10), h < p.hp)
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
		PixelFont.draw(ci, "%dG" % p.get("gold", 0), Vector2(x + 78, 17), 1, Color("ffd23d"), dark)
		ci.draw_rect(Rect2(x + 24, 19, 50, 3), dark)
		ci.draw_rect(Rect2(x + 25, 20, 48 * xf, 1), Color("5dff7a"))
	# Wave label on the top wall
	var wl := _clock(run_t)
	PixelFont.draw_centered(ci, wl, 240, 22, 1, Color("c9b8ff"), dark)
	# Boss bar
	if boss_f > 0.0:
		var bw := 300.0
		var bx := 240 - bw / 2
		PixelFont.draw_centered(ci, Lore.ARCHLICH_NAME if boss_final else Lore.LICH_NAME, 240, 249, 1, Color("ff4df2") if boss_final else Color("4dfff0"), dark)
		ci.draw_rect(Rect2(bx - 2, 258, bw + 4, 8), dark)
		ci.draw_rect(Rect2(bx, 260, bw, 4), Color("2c0d4d"))
		ci.draw_rect(Rect2(bx, 260, bw * boss_f, 4), Color("4dfff0") if boss_f > 0.5 else Color("ff4d6a"))
		ci.draw_rect(Rect2(bx, 260, bw * boss_f, 1), Color.WHITE)
	_draw_reveals(ci, dark)
	_draw_bets(ci, dark)
	# Banner
	if banner.t > 0.0:
		var k: float = 1.0 - banner.t / banner.max
		var slide := 0.0
		if k < 0.12:
			slide = (1.0 - k / 0.12) * 260.0
		elif banner.t < 0.3:
			slide = -(1.0 - banner.t / 0.3) * 260.0
		var y := 96.0
		if banner.act != "":
			_draw_act_card(ci, k, slide)
		else:
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

## An act card: a rune-framed band with the act's numeral, its name in large letters and its subtitle, fading in.
func _draw_act_card(ci: CanvasItem, k: float, slide: float) -> void:
	var a := clampf(k / 0.12, 0.0, 1.0) * clampf(banner.t / 0.4, 0.0, 1.0)
	var col: Color = banner.color
	var band := Rect2(40, 82, 400, 66)
	ci.draw_rect(Rect2(0, band.position.y - 6, 480, band.size.y + 12), Color(0.02, 0.0, 0.05, 0.55 * a))
	if a < 0.99:
		return
	Occult.frame(ci, band, time)
	PixelFont.draw_centered(ci, banner.act, 240, band.position.y + 8, 1, Color(col, 0.9), Occult.INK)
	var tw := PixelFont.text_width(banner.text, 3)
	PixelFont.draw_gradient(ci, banner.text, Vector2(240 - tw / 2.0 + slide * 0.0, band.position.y + 22), 3,
		Color.WHITE, col, time * 3.0, 1.0)
	PixelFont.draw_centered(ci, banner.sub, 240, band.position.y + 50, 1, Color("fff6e0"), Occult.INK)
	Occult.candle(ci, Vector2(band.position.x + 14, band.end.y - 4), time, 0.0, 9)
	Occult.candle(ci, Vector2(band.end.x - 14, band.end.y - 4), time, 3.0, 9)


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
	if _local_pick_slots().size() == 1:
		var bx := (480 - (TAROT_W * 3 + TAROT_GAP * 2)) / 2
		return Rect2(bx + c * (TAROT_W + TAROT_GAP), TAROT_TOP, TAROT_W, TAROT_H)
	var x0 := (480 - (CARD_W * 3 + CARD_GAP * 2)) / 2
	return Rect2(x0 + c * (CARD_W + CARD_GAP), PICK_TOP + row * PICK_ROW_H + 9, CARD_W, CARD_H)


## How far the dealt card `c` of `slot`'s offer has turned over: 0 face down, 1 face up.
func _deal(slot: int, c: int) -> float:
	var offer := int(vp[slot].offer)
	var seen: Array = _pick_dealt.get(slot, [-1, 0.0, 0])
	if int(seen[0]) != offer:
		seen = [offer, time, 0]
		_pick_dealt[slot] = seen
		Sfx.play("card_deal", -2.0)
	var k := clampf((time - float(seen[1]) - 0.1 * c) / 0.3, 0.0, 1.0)
	if k >= 0.5 and (int(seen[2]) & (1 << c)) == 0:
		seen[2] = int(seen[2]) | (1 << c)
		Sfx.play("card_flip", -4.0, 1.0 + c * 0.06, 0.0)
	return k

func _draw_levelup(ci: CanvasItem) -> void:
	var dark := Color("0b0716")
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.03, 0.0, 0.08, 0.72))
	var tw := PixelFont.text_width("LEVEL UP", 3)
	PixelFont.draw_gradient(ci, "LEVEL UP", Vector2(240 - tw / 2.0, 14), 3, Color.WHITE, Color("ffd94d"), time * 5.0, 1.5)
	var rows := _local_pick_slots()
	var big := rows.size() == 1
	for row in rows.size():
		var slot: int = rows[row]
		var p: Dictionary = vp[slot]
		var col := G.player_color(slot)
		var sent: Array = _pick_sent.get(slot, [-1, -1])
		var done := int(sent[1]) == int(p.offer)
		var y0 := (TAROT_TOP - 14) if big else PICK_TOP + row * PICK_ROW_H
		var line := "P%d  LEVEL %d  -  %s" % [slot + 1, p.level, "WAITING FOR THE OTHERS" if done else "DRAW A CARD"]
		if big:
			PixelFont.draw_centered(ci, line, 240, y0, 1, col, dark)
		else:
			PixelFont.draw(ci, line, Vector2(_card_rect(row, 0).position.x, y0), 1, col, dark)
		var choices: Array = p.choices
		for c in choices.size():
			var r := _card_rect(row, c)
			var sel: bool = (int(sent[0]) == c) if done else (int(_pick_sel.get(slot, 0)) == c)
			var idx: int = choices[c]
			var lv: int = p.choice_lv[c]
			var lv_text := "NEW" if lv == 1 else "LEVEL %d/%d" % [lv, Upgrades.max_level(idx)]
			var k := _deal(slot, c)
			if k < 0.5:
				var w := r.size.x * (1.0 - k * 2.0)
				TarotArt.draw_back(ci, Rect2(r.get_center().x - w / 2.0, r.position.y, w, r.size.y))
				continue
			if big and sel:
				r.position.y -= 6
			if big:
				TarotArt.draw_card(ci, r, Upgrades.key(idx), Upgrades.display_name(idx), Upgrades.description(idx),
					lv_text, sel, col, time)
				if sel:
					Occult.cursor(ci, Vector2(r.get_center().x, r.end.y + 12), time)
			else:
				TarotArt.draw_card_small(ci, r, Upgrades.key(idx), Upgrades.display_name(idx),
					Upgrades.description(idx), lv_text, sel, col, time)
			if k < 0.75:
				ci.draw_rect(r, Color(1, 1, 1, (0.75 - k) * 3.0))
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
	Sfx.play("card_pick", -2.0)

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
	var dark := Color("0b0716")
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.03, 0.0, 0.08, 0.82 * a))
	if game_over_t < 0.6:
		return
	var title := "VICTORY!" if victory else "THE TOWER FALLS"
	var tw := PixelFont.text_width(title, 4)
	PixelFont.draw(ci, title, Vector2(240 - tw / 2.0, 10) + Vector2(2, 2), 4, dark)
	PixelFont.draw_gradient(ci, title, Vector2(240 - tw / 2.0, 10), 4, Color("ffd94d"), Color("8bff9e") if victory else Color("ff3b5c"), time * 3.0, 2.0)
	var sub := ("WON AT " if victory else "SURVIVED ") + _clock(run_t) + "    TEAM SCORE %07d" % final_score
	PixelFont.draw_centered(ci, sub, 240, 44, 1, Color("8bff9e") if victory else Color("c9b8ff"), dark)
	_draw_result_columns(ci, dark, 58)
	_draw_moments(ci, dark, 150)
	var foot := "BEST %07d    +%d CRYSTALS  (%d TO SPEND)" % [G.high_score, crystals_earned, Save.profile.crystals]
	PixelFont.draw_centered(ci, Lore.ending(victory, final_score), 240, 208, 1, Color("e8dcc0"), dark)
	PixelFont.draw_centered(ci, foot, 240, 224, 1, Color("8bdcff"), dark)
	if game_over_t > 2.0 and int(time * 2.5) % 2 == 0:
		var msg := "PRESS FIRE TO CONTINUE" if is_host else "WAITING FOR HOST..."
		if G.touch_active and is_host:
			msg = "TAP TO CONTINUE"
		PixelFont.draw_centered(ci, msg, 240, 244, 1, Color.WHITE, dark)

## One column per wizard: name, award, then score, level, kills, damage and gold, revealed one by one.
func _draw_result_columns(ci: CanvasItem, dark: Color, y0: int) -> void:
	var slots: Array = []
	for slot in 4:
		if vp.has(slot):
			slots.append(slot)
	if slots.is_empty():
		return
	var titles := {}
	if results != null:
		for aw: Array in results.awards():
			titles[int(aw[0])] = aw[1]
	var colw := 112.0
	var x0 := 240.0 - colw * slots.size() / 2.0
	var rows := [["SCORE", "score"], ["LEVEL", "level"], ["KILLS", "kills"], ["DAMAGE", "damage"], ["GOLD", "gold"]]
	for i in slots.size():
		var slot: int = slots[i]
		var cx := x0 + colw * (i + 0.5)
		var show := clampf((game_over_t - 0.8 - i * 0.25) / 0.3, 0.0, 1.0)
		if show <= 0.0:
			continue
		var col := G.player_color(slot)
		ci.draw_rect(Rect2(cx - colw / 2.0 + 4, y0 - 2, colw - 8, 86), Color(col.r, col.g, col.b, 0.12 * show))
		PixelFont.draw_centered(ci, "P%d" % (slot + 1), cx, y0 + 2, 2, col, dark)
		var award: String = titles.get(slot, "")
		if award != "":
			PixelFont.draw_centered(ci, award, cx, y0 + 18, 1, Color("ffd94d"), dark)
		var y := y0 + 30
		for r: Array in rows:
			var v: float = float(vp[slot].score) if r[1] == "score" else (results.stat(slot, r[1]) if results != null else 0.0)
			PixelFont.draw(ci, r[0], Vector2(cx - 46, y), 1, Color("8a7aa8"), dark)
			var txt := "%d" % int(v)
			PixelFont.draw(ci, txt, Vector2(cx + 46 - PixelFont.text_width(txt, 1), y), 1, Color.WHITE, dark)
			y += 10

## The team's best moments, with the run time each happened at.
func _draw_moments(ci: CanvasItem, dark: Color, y0: int) -> void:
	if results == null or game_over_t < 1.8:
		return
	var top: Array = results.top_moments()
	if top.is_empty():
		return
	PixelFont.draw_centered(ci, "BEST MOMENTS", 240, y0, 1, Color("ff4df2"), dark)
	var y := y0 + 14
	for i in top.size():
		if game_over_t < 2.0 + i * 0.3:
			break
		var m: Array = top[i]
		var line := _clock(float(m[0])) + "  " + Results.moment_text(m)
		PixelFont.draw_centered(ci, line, 240, y, 1, G.player_fx(int(m[2])), dark)
		y += 12

func _draw_pause(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.03, 0.0, 0.08, 0.7))
	var tw := PixelFont.text_width("PAUSED", 4)
	PixelFont.draw_gradient(ci, "PAUSED", Vector2(240 - tw / 2.0, 60), 4, Color.WHITE, Color("b78cff"), time * 4.0, 1.0)
	if pause_options:
		options.draw(ci, time)
		return
	var panel := Rect2(170, 118, 140, 66)
	Occult.frame(ci, panel, time)
	Occult.candle(ci, Vector2(158, 184), time, 0.0, 10)
	Occult.candle(ci, Vector2(322, 184), time, 2.0, 10)
	for i in PAUSE_ITEMS.size():
		var sel := i == pause_sel
		var y := 130 + i * 16
		if sel:
			var w := PixelFont.text_width(PAUSE_ITEMS[i])
			Occult.highlight(ci, Rect2(240 - w / 2.0 - 16, y - 3, w + 32, 13), time)
			Occult.cursor(ci, Vector2(240 - w / 2.0 - 9, y + 3), time)
		PixelFont.draw_centered(ci, PAUSE_ITEMS[i], 240, y, 1, Occult.GOLD if sel else Occult.DIM, Occult.INK)

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
	if start and pause_options:
		pause_options = false
		Save.write_settings()
		Sfx.play("menu_select")
		return
	if start:
		_toggle_pause()
		return
	if not paused and _pick_input(event):
		get_viewport().set_input_as_handled()
		return
	if paused:
		if pause_options:
			if options.handle(event):
				pause_options = false
			return
		var d := PlayerInput.menu_dir(event)
		if d != 0:
			pause_sel = wrapi(pause_sel + d, 0, PAUSE_ITEMS.size())
			Sfx.play("menu_move")
		if PlayerInput.confirm_device(event) != -99:
			_pause_choose(pause_sel)
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
			var row := int(floorf((event.position.y - 127.0) / 16.0))
			if row >= 0 and row < PAUSE_ITEMS.size() and absf(event.position.x - 240.0) < 70.0:
				_pause_choose(row)


func _pause_choose(i: int) -> void:
	Sfx.play("menu_select")
	pause_sel = i
	match i:
		0:
			_toggle_pause()
		1:
			options.open()
			pause_options = true
		2:
			_quit_to_title()

func _toggle_pause() -> void:
	if game_over:
		return
	paused = not paused
	pause_sel = 0
	if pause_options:
		pause_options = false
		Save.write_settings()
	Sfx.play("menu_select")

func _quit_to_title() -> void:
	Engine.time_scale = 1.0
	if Net.mode == Net.Mode.HOST:
		Net.send_back_to_title()
	Net.shutdown()
	G.goto_title()

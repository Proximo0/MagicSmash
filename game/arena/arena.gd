class_name Arena
extends Node2D
## Match scene: runs the World on the host, mirrors it on clients, and draws
## everything (sprites, spells, particles, HUD, banners, touch controls).

const SNAP_EVERY := 2 # physics frames between snapshots sent to clients

## One colour per spell (see Sprites.SPELL_COLORS: the tomes are painted from the same table). None is red.
const SPELL_COLORS := Sprites.SPELL_COLORS
## A rune circle's glyphs and the Seal of Solomon's hexagram.
const RUNE_GOLD := Color("ffd94d")
const SEAL_WHITE := Color("fff2c0")
const SEAL_RING := Color("ffb347")
## Seconds a rune circle takes to draw itself in and to fade out.
const RUNE_DRAW_IN := 0.25
const RUNE_FADE := 0.4
## The walk or hover cycle of each enemy type, stepped at ENEMY_ANIM frames a second. `_draw_enemy` swaps in the
## frame of a hop, a wind-up, a cast or a swoop.
const ENEMY_KEYS := [["goblin_a", "goblin_c", "goblin_b", "goblin_d"], ["skeleton_a", "skeleton_c", "skeleton_b", "skeleton_d"],
	["slime_a"], ["mslime_a", "mslime_c", "mslime_a", "mslime_b"], ["bat_a", "bat_c", "bat_b", "bat_d"],
	["orc_a", "orc_c", "orc_b", "orc_c"], ["mage_a", "mage_b"], ["lich", "lich_b"], ["wraith_a", "wraith_b"],
	["tome_a", "tome_b", "tome_c", "tome_b"], ["gargoyle_b", "gargoyle_c"], ["priest_a", "priest_b"]]
## The smallest combo call written over a wizard; smaller ones only sparkle.
const COMBO_WORDS := 50
## Width of the shadow `_draw_entities` puts under each enemy type. 0: none there. The wraith has none; the bat,
## the tome and the swooping gargoyle get theirs from `_draw_enemy_glows`, further down the floor.
const ENEMY_SHADOW := [10, 10, 12, 8, 0, 16, 10, 26, 0, 0, 16, 10]
const ENEMY_ANIM := [10.0, 7.0, 0.0, 7.0, 14.0, 5.0, 2.5, 3.0, 3.0, 10.0, 7.0, 3.0]
const PICKUP_KEYS := ["coin", "gem", "potion", "tome_fire", "tome_frost", "tome_storm", "tome_star", "boot", "tome_orbit", "xp", "chest",
	"tome_rune", "card", "chest_rare", "chest_ultra"]
const PICKUP_NAMES := ["", "", "POTION +2", "FIREBALL!", "FROST FAN!", "CHAIN LIGHTNING!", "STARFALL!", "HASTE!", "RUNE SHIELD!", "", "",
	"RUNE CIRCLE!", "", "", ""]
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
var vr: Array = []  # rune circles: [pos, radius, age, life, owner, evolved]
var ves: Array = [] # [kind, pos, vel]
var vk: Array = []  # [kind, pos, life]
var vu: Array[Vector2] = [] # urns from the snapshot
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
var _cards: Array = [] # monster card reveals, one at a time: {idx, slot, t, first}
const CARD_SHOW := 4.0
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
## A fallen wizard's ghost rising from where they fell: [position, seconds, wizard].
var _ghosts: Array = []
const GHOST_LIFE := 1.8
## The controls hint on a player's first run: seconds into the fight it shows (-1: not yet), and how long.
var _hint_t := -1.0
const HINT_LIFE := 10.0
const HINT_LINES := [
	["MOVE", "WASD / LEFT STICK"],
	["AIM", "ARROWS, MOUSE / RIGHT STICK"],
	["", "YOUR SPELLS CAST THEMSELVES"],
	["NOVA", "SPACE / RB  -  DRAW CARDS: E / LB"],
]
## The act of the tower the run is in (Lore.ACTS); the backdrop fades to the next act's.
var act := 0
## The act the backdrop is fading from, so its flames and seal can fade out while the new act's fade in.
var _prev_act := 0
var bg_next: Sprite2D
var _act_fade := -1.0
var decals: Array = [] # [pos, color, size, life]
var paused := false
var pause_sel := 0
var pause_options := false
var options := OptionsPanel.new()
const PAUSE_ITEMS := ["RESUME", "OPTIONS", "QUIT TO TITLE"]
var time := 0.0
## The camera: the world point at the screen's top-left. It follows the middle of the living party and stays
## inside the arena image; CAM_EASE is how fast it catches up (per second).
var cam := Vector2.ZERO
const CAM_EASE := 6.0
var _hitstop := 0.0
var _last_aim := {}
## Level-up cards, per wizard: a tab under the HUD panel while draws wait, or the open tray. _pick_sent is the
## [card, offer] a local player took and is sending; _tray_open is whose tray is open (local wizards only);
## _tray_dealt is slot -> [offer, time its rows began to turn over, rows whose flip sound played, true if it
## turned over on screen]; _pick_t is when a slot last took a card; _tab_flash is when a wizard's draws last went
## up; _lt_held is per pad, so a pull of the left trigger toggles once.
var _pick_sent := {}
var _tray_open := {}
var _tray_dealt := {}
var _pick_t := {}
var _tab_flash := {}
var _lt_held := {}
## The party's shared level and XP pool and the lull's seconds left, from the snapshot. _lull_full is the lull's
## length (its countdown bar's full width); _lv_flash_t is when the party last levelled (for the HUD flash).
var party_level := 1
var party_xp := 0
var party_need := 1
var lull_left := 0.0
var _lull_full := 1.0
var _lv_flash_t := -10.0
var _pick_sfx_t := -10.0
## Autotest only (--pick-hold): seconds the bot in slot 0 looks at its cards before picking.
var autotest_pick_hold := 0.0
const TRAY_W := 118
const TRAY_ROW_H := 17 # a row's top pixel stays dark, between it and the row above
const TAB_H := 11
const TRAY_FLIP := 0.25 # seconds for a new hand's rows to turn over, all of them
const TRAY_READ := 0.2 # a hand that turned over on screen takes no press until it has been face up this long
const PICK_GAP := 0.3 # seconds after a take before the same wizard's next press counts
const BOT_PICK_THINK := 0.9
## slot -> [offer, seconds a demo bot has looked at it].
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
	# The bigger arena takes a moment to bake; do the later acts now, during the run's intro, not mid-fight.
	(func() -> void: ArenaBg.build(ArenaBg.LIBRARY)).call_deferred()
	(func() -> void: ArenaBg.build(ArenaBg.SANCTUM)).call_deferred()
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
	fx.calm = true
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
	var vignette_layer := CanvasLayer.new()
	vignette_layer.layer = 5
	add_child(vignette_layer)
	vignette_layer.add_child(vignette)

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
		Crash.tag("seed", str(world.rng.seed))
		Crash.tag("wizards", str(slots.size()))
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
	if _hint_t < 0.0 and run_t > 0.5 and not Save.settings.seen_tutorial and not Flags.is_scripted_run():
		_hint_t = 0.0
	elif _hint_t >= 0.0 and _hint_t < HINT_LIFE:
		_hint_t += dt
		if _hint_t >= HINT_LIFE:
			Save.settings.seen_tutorial = true
			Save.write_settings()
	for g: Array in _ghosts:
		g[1] += dt
	_ghosts = _ghosts.filter(func(g: Array) -> bool: return g[1] < GHOST_LIFE)
	_update_reveals(dt)
	_update_bets(dt)
	screen_flash.a = maxf(0.0, screen_flash.a - dt * 3.0)
	shake = maxf(0.0, shake - dt * 18.0)
	var so := Vector2.ZERO
	if shake > 0.0:
		so = Vector2(_fx_rng.randf_range(-1, 1), _fx_rng.randf_range(-1, 1)) * shake
	_follow_party(dt)
	root.position = (so - cam).round()
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

func _smooth(dt: float) -> void:
	var k := 1.0 - exp(-dt * 20.0)
	for p in vp.values():
		p.pos = p.pos.lerp(p.target, k)
	for e in ve.values():
		if e.pos.distance_to(e.target) > 40.0:
			e.pos = e.target # teleports
		else:
			e.pos = e.pos.lerp(e.target, k)

func _on_snapshot(snap: Dictionary) -> void:
	if is_host:
		return
	_apply_snapshot(snap, false)
	if snap.has("ev"):
		_handle_events(snap.ev)

func _on_roster_changed() -> void:
	if not is_host or world == null:
		return
	var live := {}
	for r in Net.roster:
		live[r.slot] = true
	for s in world.players.keys():
		if not live.has(s):
			world.players.erase(s)

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
	if not _cards.is_empty():
		_cards[0].t += dt
		if _cards[0].t >= CARD_SHOW:
			_cards.pop_front()

## The monster card a wizard just found: it flips in at the middle of the screen with its name and bonus.
func _draw_card_reveal(ci: CanvasItem, dark: Color) -> void:
	if _cards.is_empty():
		return
	var c: Dictionary = _cards[0]
	var t: float = c.t
	var fade := clampf(minf(t * 4.0, (CARD_SHOW - t) * 3.0), 0.0, 1.0)
	ci.draw_rect(Rect2(0, 0, 480, 270), Color(0.02, 0.0, 0.06, 0.55 * fade))
	# The back shows, narrows to an edge, then the face widens out: a card turning over.
	var flip := clampf(t / 0.6, 0.0, 1.0)
	var w := 76.0 * absf(1.0 - flip * 2.0)
	var h := 112.0
	var center := Vector2(240, 128 - (1.0 - fade) * 10.0)
	var r := Rect2((center - Vector2(w / 2.0, h / 2.0)).floor(), Vector2(maxf(floorf(w), 1.0), h))
	if flip < 0.5:
		TarotArt.draw_back(ci, r)
	else:
		for i: int in range(12):
			var a := time * 0.6 + i * TAU / 12.0
			ci.draw_line(center, center + Vector2.from_angle(a) * 90.0, Color(1.0, 0.3, 0.95, 0.10 * fade), 3.0)
		MonsterCard.draw(ci, r, c.idx, true, time, 1.0)
	var col := Color("ff4df2").lerp(Color.WHITE, 0.5 + 0.5 * sin(time * 10.0))
	PixelFont.draw_centered(ci, "ULTRA RARE CARD", 240, r.position.y - 22, 2, Color(col, fade), dark)
	var who := "P%d DREW %s" % [int(c.slot) + 1, Cards.card_name(c.idx)]
	PixelFont.draw_centered(ci, who, 240, r.end.y + 6, 1, Color(Color("ffd94d"), fade), dark)
	var sub := "NEW TO YOUR COLLECTION" if c.first else "SOCKET IT IN THE SANCTUM"
	PixelFont.draw_centered(ci, sub, 240, r.end.y + 16, 1, Color(Color("c9b8ff"), fade), dark)

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
		var at: Vector2 = _on_screen(b.pos as Vector2) + Vector2(0, -30)
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
		var at: Vector2 = _on_screen(r.pos as Vector2) + Vector2(0, -34)
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
	var want := Lore.act_of(wave - 1)
	if want != act and _act_fade < 0.0:
		_prev_act = act
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

## Eases the camera toward the middle of the living wizards (all of them when none is alive), keeping the view
## inside the arena image. The HUD band covers the top of the screen, so the view may rise by the band's height:
## near the top of the room the whole back wall and its door then show below the band.
func _follow_party(dt: float) -> void:
	var c := Vector2.ZERO
	var n := 0
	for p: Dictionary in vp.values():
		if p.alive:
			c += p.pos
			n += 1
	if n == 0:
		for p: Dictionary in vp.values():
			c += p.pos
			n += 1
	if n == 0:
		return
	c /= n
	var want := c - Vector2(G.SCREEN.x / 2.0, (G.SCREEN.y + G.HUD_H) / 2.0)
	want = want.clamp(Vector2(0.0, -G.HUD_H), G.WORLD - G.SCREEN)
	cam = want if cam == Vector2.ZERO and time < 0.2 else cam.lerp(want, minf(1.0, dt * CAM_EASE))

## A world position on the screen (for HUD things that point at the arena).
func _on_screen(p: Vector2) -> Vector2:
	return p - cam

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
	# A stain soaks into the floor: whatever colour the monster bled, it is no brighter than a lit flagstone.
	var stain := Color.from_hsv(color.h, minf(color.s, 0.8), minf(color.v, 0.26))
	decals.append([pos, stain, size, 12.0, _fx_rng.randi()])
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
		World.PK_COIN: return Color("ffd94d")
		World.PK_GEM: return Color("4dfff0")
		World.PK_POTION: return Color("ff3b5c")
		World.PK_TOME_FIRE: return SPELL_COLORS[1]
		World.PK_TOME_FROST: return SPELL_COLORS[2]
		World.PK_TOME_STORM: return SPELL_COLORS[3]
		World.PK_TOME_STAR: return SPELL_COLORS[4]
		World.PK_TOME_RUNE: return SPELL_COLORS[5]
		World.PK_BOOTS: return Color("8fe3ff")
		World.PK_ORBIT: return Sprites.ORBIT_COLOR
		World.PK_XP: return Sprites.XP_COLOR
		World.PK_CHEST: return Color("ffd94d")
		World.PK_CARD: return Color("ff4df2")
		World.PK_CHEST_RARE: return Color("8fe3ff")
		World.PK_CHEST_ULTRA: return Color("c9a6ff")
	return Color.WHITE

## A wizard's casting pose lasts CAST_POSE seconds and comes back no sooner than CAST_EVERY (the fast spells fire
## many times a second: the arm would never come down); the staff head flares for CAST_FLARE on every cast.
## A cast belongs to the wizard whose staff head is within CAST_NEAR pixels of it.
const CAST_POSE := 0.16
const CAST_EVERY := 0.45
const CAST_FLARE := 0.09
const CAST_NEAR := 12.0
const STAFF_WOOD := Color("c98a6b")
const STAFF_BAND := Color("ffd94d")
const SHADOW_COLOR := Color(0.04, 0.0, 0.09, 0.45)
## How far above the feet a wizard's P-tag starts, and where it goes while the rune shield's orbs circle the hat.
const TAG_UP := 31.0
const TAG_UP_ORBS := 40.0
## Last frame's starfall shots, [pos, vel, evolved]: one that is gone has landed (`_emit_trails`).
var _stars_seen: Array = []

## Once a frame: what the shots, the rune circles, the enemies and the wizards shed, and the view state that
## follows from the snapshot rather than from an event (who is casting, who took a level-up card, which star landed).
func _emit_trails(dt: float) -> void:
	var stars: Array = []
	for s in vs:
		var p: Vector2 = s[1]
		match s[0]:
			World.SP_ARCANE:
				# The comet is a sprite with its own tail; only the Astral Lance sheds motes.
				if s[4] and _fx_rng.randf() < 0.3:
					var col := G.player_fx(s[3])
					fx.spawn(p, Vector2(_fx_rng.randf_range(-12, 12), _fx_rng.randf_range(-12, 12)), 0.22, 1.0, Color.WHITE, col, true, 3.0)
			World.SP_FIRE:
				# A lick of flame left behind every frame; now and then an ember that falls, or smoke.
				fx.spawn(p + Vector2(_fx_rng.randf_range(-1.5, 1.5), _fx_rng.randf_range(-1.5, 1.5)), -s[2] * 0.12 + Vector2(0, -14),
					0.26, 3.0 if s[4] else 2.0, Color("ffcf5a"), Color("c85a1e"), true, 3.0, -20.0, 0.0, true)
				if _fx_rng.randf() < 0.25:
					fx.spawn(p, Vector2(_fx_rng.randf_range(-25, 25), _fx_rng.randf_range(-30, 0)), 0.5, 1.0, Color("fff6c0"),
						Color("c0263a"), true, 1.0, 160.0)
				if _fx_rng.randf() < 0.12:
					fx.spawn(p, Vector2(_fx_rng.randf_range(-8, 8), -12), 0.6, 2.0, Color(0.23, 0.19, 0.31, 0.6), Color(0.1, 0.06, 0.14, 0.0),
						false, 1.0, -10.0, 4.0)
			World.SP_FROST:
				if _fx_rng.randf() < 0.2:
					fx.spawn(p, Vector2(_fx_rng.randf_range(-10, 10), _fx_rng.randf_range(-10, 10)), 0.25, 1.0, Color.WHITE,
						SPELL_COLORS[World.SP_FROST], true, 2.0)
			World.SP_STAR:
				stars.append(s)
				if _fx_rng.randf() < 0.5:
					fx.spawn(p + Vector2(_fx_rng.randf_range(-2, 2), _fx_rng.randf_range(-2, 2)), Vector2(_fx_rng.randf_range(-8, 8), 10),
						0.45, 1.0, Color.WHITE, SPELL_COLORS[World.SP_STAR], true, 2.0, 30.0)
	# A star that was here a frame ago and is nowhere near now has landed: a burst, and a mark on the floor.
	var reach := maxf(24.0, 420.0 * dt)
	for old: Array in _stars_seen:
		var alive := false
		for s: Array in stars:
			if (s[1] as Vector2).distance_squared_to(old[0]) < reach * reach:
				alive = true
				break
		if not alive:
			fx.star_land((old[0] as Vector2) + (old[1] as Vector2) * dt, SPELL_COLORS[World.SP_STAR], old[2])
	_stars_seen.clear()
	for s: Array in stars:
		_stars_seen.append([s[1], s[2], s[4]])
	for c: Array in vr:
		if _fx_rng.randf() < (0.3 if c[5] else 0.18):
			var at: Vector2 = c[0] + Vector2.from_angle(_fx_rng.randf() * TAU) * float(c[1])
			fx.spawn(at, Vector2(0, _fx_rng.randf_range(-22, -8)), 0.5, 1.0, RUNE_GOLD, SPELL_COLORS[World.SP_RUNE], true, 1.0)
	for e in ve.values():
		if e.type == World.LICH and _fx_rng.randf() < 0.4:
			fx.spawn(e.pos + Vector2(_fx_rng.randf_range(-14, 14), _fx_rng.randf_range(-24, 0)), Vector2(0, _fx_rng.randf_range(-30, -10)),
				0.7, 1.0, Color("d8fff6"), Color("158f86"), true, 1.0)
		elif e.slow > 0.0 and _fx_rng.randf() < 0.1:
			fx.spawn(e.pos + Vector2(_fx_rng.randf_range(-5, 5), -_fx_rng.randf_range(0, 10)), Vector2(0, -8), 0.4, 1.0, Color.WHITE,
				SPELL_COLORS[World.SP_FROST], true)
		elif e.type == World.MAGE and e.state == 1:
			# A mage gathering its shot burns red: the colour of everything an enemy throws.
			fx.spawn(e.pos + Vector2(_fx_rng.randf_range(-6, 6), -8 + _fx_rng.randf_range(-4, 4)), Vector2(0, -20), 0.3, 1.0,
				Color("ffcf5a"), Color("c0263a"), true)
	fx.keep_clear.clear()
	var tagged := vp.size() > 1 or Net.is_online()
	for p: Dictionary in vp.values():
		if not p.alive:
			continue
		# Floating words start above the wizard (and the P-tag), never across them.
		var head := 24.0
		if tagged:
			head = (TAG_UP_ORBS if p.orbit > 0.0 else TAG_UP) + 2.0
		fx.keep_clear.append(Rect2(p.pos.x - 9.0, p.pos.y - head, 18.0, head + 2.0))
		var tip: Vector2 = (p.target as Vector2) + Vector2(0, -7) + (p.aim as Vector2) * 9.0
		for c: Array in fx.casts:
			# Matched by the caster's slot; by staff distance only when the cast did not say who cast it.
			var mine: bool = int(c[1]) == int(p.slot) if int(c[1]) >= 0 \
					else (c[0] as Vector2).distance_squared_to(tip) < CAST_NEAR * CAST_NEAR
			if mine:
				p["flare_at"] = time
				if time - float(p.get("cast_at", -9.0)) > CAST_EVERY:
					p["cast_at"] = time
				break
		# The column of light walks with its wizard.
		var pillar: Array = p.get("pillar", [])
		if not pillar.is_empty():
			if float(pillar[1]) > 0.0:
				pillar[0] = p.pos
			else:
				p.erase("pillar")
		if p.haste > 0.0 and p.moving and _fx_rng.randf() < 0.4:
			fx.spawn(p.pos + Vector2(_fx_rng.randf_range(-3, 3), 0), Vector2(0, -10), 0.35, 1.0, Color.WHITE, Color("8fe3ff"), true)
	fx.casts.clear()

func _torch_fx(dt: float) -> void:
	# Sparks rise from the fires of the backdrop that shows most: the old act's for the first half of a fade.
	var from := _prev_act if _act_fade >= 0.0 and _act_fade < 1.0 else act
	ArenaArtLive.sparks(fx, ArenaBg.scene(from), _fx_rng, dt, door_anim)

func _draw_decals() -> void:
	for d in decals:
		var c: Color = d[1]
		c.a = clampf(d[3] / 4.0, 0.0, 1.0) * 0.42
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
	# Rune circles: a dark scorched disc under the glow, so the ring reads on any floor.
	for c: Array in vr:
		var k := _rune_alpha(c)
		ci.draw_circle(c[0], float(c[1]) * _rune_grow(c) + 1.0, Color(0.06, 0.0, 0.05, 0.45 * k))
	# Flames on the backdrop's candles and fire bowls. While the backdrop fades to a new act, the old act's
	# flames fade out with its picture and the new act's fade in.
	var k := _act_blend()
	if k < 1.0:
		ArenaArtLive.draw(ci, ArenaBg.scene(_prev_act), time, 1.0 - k)
	ArenaArtLive.draw(ci, ArenaBg.scene(act), time, k)

func _draw_env_add() -> void:
	var ci := env_add
	# The light of those flames, the seal breathing, and each door's glow, flaring while monsters come through.
	var k := _act_blend()
	if k < 1.0:
		ArenaArtLive.draw_glow(ci, ArenaBg.scene(_prev_act), time, door_anim, 1.0 - k)
	ArenaArtLive.draw_glow(ci, ArenaBg.scene(act), time, door_anim, k)
	_draw_runes(ci)

## How far the backdrop has faded to the current act: 1 when no fade is running.
func _act_blend() -> float:
	return 1.0 if _act_fade < 0.0 else clampf(_act_fade / 2.0, 0.0, 1.0)

## How far a rune circle has drawn itself in (0..1), from its age.
func _rune_grow(c: Array) -> float:
	return clampf(float(c[2]) / RUNE_DRAW_IN, 0.0, 1.0)

## A rune circle's brightness: up while it draws in, down over its last RUNE_FADE seconds.
func _rune_alpha(c: Array) -> float:
	return clampf((float(c[3]) - float(c[2])) / RUNE_FADE, 0.0, 1.0) * (0.4 + 0.6 * _rune_grow(c))

## Active rune circles on the additive floor layer: a double ring with gold runes turning between, a pentagram
## inside (a hexagram for the Seal of Solomon, with motes drawn inward), flaring on every damage tick.
## The first-run controls hint: a small occult panel low on the screen that slides in and out.
func _draw_hint(ci: CanvasItem) -> void:
	if _hint_t < 0.0 or _hint_t >= HINT_LIFE:
		return
	var k := minf(1.0, minf(_hint_t, HINT_LIFE - _hint_t) * 3.0)
	var r := Rect2(96, 206 + (1.0 - k) * 70.0, 288, 46)
	Occult.frame(ci, r, time, false)
	var y := r.position.y + 4
	for l: Array in HINT_LINES:
		PixelFont.draw(ci, l[0], Vector2(r.position.x + 8, y), 1, Color("ffd94d"))
		PixelFont.draw(ci, l[1], Vector2(r.position.x + 44, y), 1, Color("fff6e0"))
		y += 10

## The additive floor layer's magic, under the actors: the marks fallen stars leave, and the active rune circles.
## A circle is a ring with two broken rings turning inside it, as on the Sanctum's portal, a slow wheel of gold
## runes between them and a pentagram in the middle (a hexagram for the Seal of Solomon, with motes drawn
## inward); all of it flares on every damage tick.
func _draw_runes(ci: CanvasItem) -> void:
	fx.draw_floor(ci)
	var runes: Array = Sprites.strip("fx_rune", Occult.RUNES.size())
	for c: Array in vr:
		var at: Vector2 = (c[0] as Vector2).floor() + Vector2(0.5, 0.5)
		var evo: bool = c[5]
		var r: float = roundf(float(c[1]) * (0.6 + 0.4 * _rune_grow(c)))
		var k := _rune_alpha(c)
		var since := fposmod(float(c[2]) - Spells.RUNE_ARM, Spells.RUNE_TICK)
		var flare := clampf(1.0 - since / (Spells.RUNE_TICK * 0.5), 0.0, 1.0) if float(c[2]) >= Spells.RUNE_ARM else 0.0
		var col: Color = SEAL_RING if evo else SPELL_COLORS[World.SP_RUNE]
		var glyph: Color = SEAL_WHITE if evo else RUNE_GOLD
		var turn := (time * 0.5 + float(c[4])) * (1.0 if int(c[4]) % 2 == 0 else -1.0)
		ci.draw_circle(at, r, Color(col, (0.05 + 0.09 * flare) * k))
		var segs := 48 if r > 24.0 else 32
		ci.draw_arc(at, r, 0.0, TAU, segs, Color(col, (0.75 + 0.25 * flare) * k), 1.0)
		ci.draw_arc(at, r - 2.0, turn * 1.6, turn * 1.6 + TAU * 0.8, segs, Color(col, (0.4 + 0.3 * flare) * k), 1.0)
		ci.draw_arc(at, r - 10.0, -turn * 2.2, -turn * 2.2 + TAU * 0.8, segs, Color(col, (0.5 + 0.3 * flare) * k), 1.0)
		var n := maxi(5, int(TAU * (r - 6.0) / 11.0))
		var gc := Color(glyph, (0.6 + 0.4 * flare) * k)
		for g in n:
			var a := turn + g * TAU / n
			Sprites.draw_mid_r(ci, runes[(g * 3 + int(c[4])) % runes.size()], at + Vector2.from_angle(a) * (r - 6.0), gc)
		var inner := r - 11.0
		if evo:
			# The Seal of Solomon: two interlaced triangles, and motes pulled toward the centre.
			for t in 2:
				var tri := PackedVector2Array()
				for v in 4:
					tri.append(at + Vector2.from_angle(-turn * 0.5 + t * PI + v * TAU / 3.0 - PI / 2.0) * inner)
				ci.draw_polyline(tri, Color(SEAL_WHITE, (0.6 + 0.4 * flare) * k), 1.0)
			var reach := float(c[1]) * Spells.SEAL_REACH
			for m in 10:
				var f := fposmod(time * 0.8 + m * 0.37, 1.0)
				var mp := at + Vector2.from_angle(m * 2.4 + turn * 0.3) * lerpf(reach, r * 0.3, f)
				Sprites.rect(ci, Rect2(mp.floor(), Vector2(1, 1)), Color(SEAL_WHITE, 0.7 * k * (1.0 - f * 0.5)))
		elif inner > 3.0:
			Occult.pentagram(ci, at, inner, Color(col, (0.3 + 0.4 * flare) * k), -turn * 0.5)

## The shadow under an actor or a pickup: a squat lozenge `w` wide, from the atlas so it batches with the sprites.
func _shadow(ci: CanvasItem, pos: Vector2, w: float) -> void:
	var h := maxf(2.0, floorf(w * 0.35))
	var at := (pos - Vector2(w / 2.0, h / 2.0)).floor()
	Sprites.rect(ci, Rect2(at.x + 1.0, at.y, w - 2.0, h), SHADOW_COLOR)
	Sprites.rect(ci, Rect2(at.x + 2.0, at.y - 1.0, w - 4.0, h + 2.0), SHADOW_COLOR)

## A pillar of light over a card or a rare chest so it is seen across a crowded arena, and a glint that comes
## and goes over it.
func _draw_treasure_glow(ci: CanvasItem, kind: int, pos: Vector2) -> void:
	var col := _pickup_color(kind)
	var pulse := 0.5 + 0.5 * sin(time * 5.0 + pos.x)
	var tall := 60.0 if kind != World.PK_CHEST_RARE else 30.0
	var at := pos.floor()
	for i: int in range(3):
		var w := 7.0 - i * 2.0
		Sprites.rect(ci, Rect2(at.x - floorf(w / 2.0), at.y - tall, w, tall), Color(col, (0.07 + 0.05 * pulse) * (i + 1)))
	if kind == World.PK_CHEST_ULTRA:
		col = Color.from_hsv(fposmod(time * 0.5, 1.0), 0.6, 1.0)
	Sprites.glow(ci, pos + Vector2(0, -4), 8.0 + 2.0 * pulse, Color(col, 0.3))
	var beat := time * 1.6 + pos.x * 0.37
	var f := int(fposmod(beat, 1.0) * 8.0)
	if f < 3:
		var spot := int(floorf(beat)) * 7
		Sprites.draw_mid_r(ci, Sprites.strip("fx_spark", 3)[f], pos + Vector2((spot % 11) - 5, -5 - (spot % 6)), col.lerp(Color.WHITE, 0.6))

func _draw_entities() -> void:
	var ci := ent_layer
	_draw_shrines(ci)
	for u: Vector2 in vu:
		_shadow(ci, u + Vector2(0, 1), 10)
		Sprites.draw_at(ci, "urn", u + Vector2(0, 1))
	# Each wizard's ring lies on the floor in their colour, under the shadows and everything that stands.
	for p: Dictionary in vp.values():
		if p.alive:
			Sprites.draw_mid(ci, "fx_ring", (p.pos as Vector2) + Vector2(0, 0.5),
				Color(G.player_fx(p.slot), 0.8 + 0.15 * sin(time * 3.0 + float(p.slot))))
	# Pickups: calm on the floor. The motes come in hundreds, so they neither bob nor cast a shadow, and each
	# twinkles for a blink every couple of seconds.
	var xp_r := Sprites.region("xp")
	var xp_twinkle := Sprites.region("xp_1")
	var coins: Array = [Sprites.region("coin"), Sprites.region("coin_1"), Sprites.region("coin_2"), Sprites.region("coin_3")]
	var glints: Array = Sprites.strip("fx_spark", 3)
	for k in vk:
		var kind: int = k[0]
		var pos: Vector2 = k[1]
		var life: float = k[2]
		if life < 3.0 and int(life * 10.0) % 2 == 0:
			continue
		if kind == World.PK_XP:
			var lit := fposmod(time * 0.45 + pos.x * 0.173 + pos.y * 0.291, 1.0) < 0.05
			Sprites.draw_mid_r(ci, xp_twinkle if lit else xp_r, pos + Vector2(0, -2))
			continue
		var bob := floorf(sin(time * 3.0 + pos.x) * 1.5)
		var chest := kind == World.PK_CHEST or kind == World.PK_CHEST_RARE or kind == World.PK_CHEST_ULTRA
		if kind >= World.PK_CARD:
			_draw_treasure_glow(ci, kind, pos)
		_shadow(ci, pos + Vector2(0, 1), 12 if chest else 8)
		if kind == World.PK_COIN:
			Sprites.draw_mid_r(ci, coins[int(time * 7.0 + pos.x * 0.31) & 3], pos + Vector2(0, -5 + bob))
		elif chest:
			# A chest sits on the floor; a glint crosses its lid now and then.
			Sprites.draw_at(ci, PICKUP_KEYS[kind], pos + Vector2(0, 2))
			var beat := time * 0.8 + pos.x * 0.21
			var f := int(fposmod(beat, 1.0) * 10.0)
			if f < 3:
				Sprites.draw_mid_r(ci, glints[f], pos + Vector2(-4 + (int(floorf(beat)) % 3) * 4, -8))
		else:
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
			_shadow(ci, it[2].pos, 12)
		else:
			var e: Dictionary = it[2]
			if ENEMY_SHADOW[e.type] > 0 and e.type != World.BAT and not (e.type == World.GARGOYLE and e.state == 1):
				_shadow(ci, e.pos, ENEMY_SHADOW[e.type])
	_draw_enemy_glows(ci)
	for it in list:
		if it[1] == 0:
			_draw_player(ci, it[2])
		else:
			_draw_enemy(ci, it[2])
	_draw_enemy_bars(ci)
	for g: Array in _ghosts:
		var k: float = g[1] / GHOST_LIFE
		var gp: Vector2 = g[0] + Vector2(sin(k * 9.0) * 3.0, -40.0 * k)
		Sprites.draw_at(ci, "wiz%d_up_i0" % g[2], gp.round(), false, false, Color(0.7, 0.9, 1.3, 0.6 * (1.0 - k)))

## One wizard: the walk cycle (or the idle breath), the casting pose for a moment after a spell leaves, the staff
## (behind the body when they face away), and the P-tag over the hat when there is a party.
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
	var casting: bool = time - float(p.get("cast_at", -9.0)) < CAST_POSE
	var key := SpritesWizards.frame_key(G.wizard_of(slot), dirkey, p.moving, int(p.walk_t), int(time * 2.0 + slot * 0.5), casting,
		aim.x >= 0.0)
	var feet: Vector2 = p.pos + Vector2(0, 1)
	# Haste afterimages
	if p.haste > 0.0:
		for gi in range(2, p.ghosts.size(), 2):
			var gc := Color(0.56, 0.89, 1.0, 0.35 - gi * 0.035)
			Sprites.draw_at(ci, key, p.ghosts[gi] + Vector2(0, 1), flip, true, gc)
	var grip: Vector2 = p.pos + SpritesWizards.grip(dirkey, aim)
	var tip: Vector2 = p.pos + Vector2(0, -7) + aim * 9.0
	if dirkey == "up":
		_draw_staff(ci, grip, tip, slot)
	Sprites.draw_at(ci, key, feet, flip, p.flash > 0.0)
	if dirkey != "up":
		_draw_staff(ci, grip, tip, slot)
	if vp.size() > 1 or Net.is_online():
		var col := G.player_color(slot)
		var lbl := "P%d" % (slot + 1)
		# The tag rides above the rune shield's orbs while they circle the hat.
		var up := TAG_UP_ORBS if p.orbit > 0.0 else TAG_UP
		PixelFont.draw_centered(ci, lbl, p.pos.x, p.pos.y - up + floorf(sin(time * 5) * 1.0), 1, col, Color("0b0716"))

## A wizard's staff: a wooden shaft through the grip with a short butt behind it and a gold band under the head,
## and the head itself where the simulation casts from (`tip`). Its glow, and the flare of a cast, are drawn with
## the shots on the additive layer.
func _draw_staff(ci: CanvasItem, grip: Vector2, tip: Vector2, slot: int) -> void:
	var along := tip - grip
	var u := along.normalized() if along.length() > 0.5 else Vector2.DOWN
	var butt := grip - u * 3.0
	Sprites.line(ci, butt, tip, Sprites.OUTLINE, 1)
	Sprites.line(ci, butt, tip, STAFF_WOOD)
	Sprites.line(ci, tip - u * 3.0, tip, STAFF_BAND)
	Sprites.draw_mid(ci, "fx_staff_%d" % G.wizard_of(slot), tip)

## Under the sprites, in one pass, so the sprites batch together: the shadows of the kinds that fly (set down the
## floor from the sprite, which stays on the body that spells hit), then the halo of each elite and of the Lich.
func _draw_enemy_glows(ci: CanvasItem) -> void:
	var halos: Array = []
	for e: Dictionary in ve.values():
		match int(e.type):
			World.BAT:
				_shadow(ci, e.pos + Vector2(0, 6), 8)
			World.TOME:
				_shadow(ci, e.pos + Vector2(0, 5), 10)
			World.GARGOYLE:
				if e.state == 1:
					_shadow(ci, e.pos + Vector2(0, 6), 14)
			World.LICH:
				halos.append(e)
		if e.elite:
			halos.append(e)
	for e: Dictionary in halos:
		if e.type == World.LICH:
			var glow := Color(1, 1, 1, 0.75 + 0.25 * sin(time * 4.0))
			Sprites.draw_at(ci, "archlich_halo" if e.final else "lich_halo", e.pos + Vector2(0, 9), false, false, glow)
		else:
			Sprites.draw_at(ci, "elite_halo", e.pos + Vector2(0, 6), false, false, Color(1, 1, 1, 0.7 + 0.3 * sin(time * 6.0 + e.t)))

## One enemy: the frame its type and state call for (see `SpritesEnemies`), anchored bottom centre on its feet.
func _draw_enemy(ci: CanvasItem, e: Dictionary) -> void:
	var t: int = e.type
	var st: int = e.state
	# A snapshot carries the state but not its age, so the view times each state: hops, wind-ups and wakes read it.
	if e.get("st", -1) != st:
		e.st = st
		e.st_t = time
	var since: float = time - float(e.st_t)
	var cyc: Array = ENEMY_KEYS[t]
	var fi := int(e.t * ENEMY_ANIM[t]) % cyc.size()
	var key: String = cyc[fi]
	# Face the nearest wizard; hold the facing while that wizard is almost straight above or below.
	var near_dx := 0.0
	var nd := INF
	for p in vp.values():
		if p.alive:
			var d: float = p.pos.distance_squared_to(e.pos)
			if d < nd:
				nd = d
				near_dx = p.pos.x - e.pos.x
	var turn := absf(near_dx) > 3.0
	var feet: Vector2 = e.pos + Vector2(0, 1)
	var mod := Color.WHITE
	if e.slow > 0.0:
		mod = Color(0.6, 0.9, 1.4)
	match t:
		World.SLIME:
			# The hop: it stretches off the floor, hangs in the air and squashes where it lands.
			if st == 1:
				var u := clampf(since / 0.5, 0.0, 1.0)
				key = "slime_c" if u < 0.2 else ("slime_d" if u < 0.85 else "slime_b")
				feet.y -= roundf(sin(u * PI) * 5.0)
			elif since < 0.12:
				key = "slime_b"
		World.MSLIME:
			if fi == 1:
				feet.y -= 2.0
		World.BAT:
			turn = false
			feet.y -= 1.0 + roundf(sin(e.t * 8.0))
		World.ORC:
			if st == 1:
				# The wind-up: the club goes up and the brute shakes with it.
				key = "orc_wind"
				feet.x += float(int(time * 30.0) % 2)
			elif st == 2:
				key = "orc_charge" if int(time * 12.0) % 2 == 0 else "orc_charge2"
		World.MAGE:
			if st == 1:
				key = "mage_cast"
		World.LICH:
			turn = false
			feet.y -= 3.0 + roundf(sin(e.t * 2.0) * 1.5)
			if st == 5:
				# About to step through the dark: its fire flares and it flickers.
				key = "lich_cast"
				mod.a = 0.6 + 0.3 * sin(time * 30.0)
			elif st >= 1 and st <= 3 and int(time * 8.0) % 3 != 0:
				key = "lich_cast"
			if e.final:
				key = "arch" + key
		World.WRAITH:
			feet.y -= 1.0 + roundf(sin(e.t * 3.0))
			if st == 1:
				# Faded: only its rim is left, and spells pass through.
				key = "wraith_fade_a" if fi == 0 else "wraith_fade_b"
				mod.a = 0.55 + 0.15 * sin(time * 20.0)
		World.TOME:
			feet.y -= 1.0 + roundf(sin(e.t * 6.0))
			if st == 1:
				key = "tome_rear"
				feet.x += float(int(time * 30.0) % 2)
			elif st == 2:
				key = "tome_dash" if int(time * 14.0) % 2 == 0 else "tome_rear"
		World.GARGOYLE:
			# It flies in from the door with its wings out and lands where it first stops. From then on it is
			# stone whenever it perches: it does not turn, and its eyes light shortly before it wakes.
			if st == 1:
				e.down = true
			elif not e.get("down", false):
				var moved: bool = e.pos.distance_squared_to(e.get("at", Vector2.INF)) > 0.04
				e.at = e.pos
				e.still = 0 if moved else int(e.get("still", 0)) + 1
				e.down = e.still >= 6
			if st == 1 or not e.down:
				feet.y -= 2.0 + float(fi)
			else:
				turn = false
				key = "gargoyle_wake" if since > World.GARGOYLE_PERCH - 0.5 else "gargoyle_a"
				mod = mod * Color(0.86, 0.86, 0.94)
		World.PRIEST:
			if st == 1:
				key = "priest_raise"
	if turn:
		e.flip = near_dx < 0.0
	var elite: bool = e.elite
	if elite:
		key = "elite_" + key
	var flash: bool = e.flash > 0.0 and (t != World.LICH or int(time * 40.0) % 3 == 0)
	Sprites.draw_at(ci, key, feet, e.flip, flash, mod)
	if elite:
		# The mark of an elite: a small crown that bobs over its head, above the health bar.
		Sprites.draw_at(ci, "elite_mark", e.pos + Vector2(0, -5.0 - SpritesEnemies.TOP[t] + roundf(sin(time * 4.0 + e.t))))

## Health bars over the big enemies and the elites, once they are hurt. Drawn after every sprite, so they do not
## split the sprite batch.
func _draw_enemy_bars(ci: CanvasItem) -> void:
	for e: Dictionary in ve.values():
		var t: int = e.type
		var elite: bool = e.elite
		if e.hpf < 1.0 and (elite or t == World.ORC or t == World.GARGOYLE):
			var w := 16.0 if elite else 12.0
			var bp: Vector2 = (e.pos + Vector2(-w / 2.0, -3.0 - SpritesEnemies.TOP[t])).floor()
			ci.draw_rect(Rect2(bp - Vector2(1, 1), Vector2(w + 2, 4)), Color("c48a10") if elite else Color("0b0716"))
			ci.draw_rect(Rect2(bp, Vector2(w, 2)), Color("2a1f45"))
			ci.draw_rect(Rect2(bp, Vector2(ceilf(w * e.hpf), 2)), Color("ff3b5c"))

## The wizards' magic, on the additive layer over the actors: every shot is a glow and one or two sprites from
## the atlas, plotted for its direction, so hundreds of them are one batch. An evolved spell is the grown form of
## the same shape. Also here: the glow of each staff head (it flares on a cast), the rune shield's orbs, a red
## halo under every enemy shot, and the auras of the Lich and of a mage gathering its shot.
func _draw_shots() -> void:
	var ci := shot_layer
	var bolts: Array = Sprites.strip("fx_bolt", Sprites.DIRS)
	var lances: Array = Sprites.strip("fx_lance", Sprites.DIRS)
	var shards: Array = Sprites.strip("fx_shard", Sprites.DIRS)
	var big_shards: Array = Sprites.strip("fx_shardx", Sprites.DIRS)
	var fires: Array = Sprites.strip("fx_fire", 4)
	var big_fires: Array = Sprites.strip("fx_firex", 4)
	var stars: Array = Sprites.strip("fx_star", 4)
	var big_stars: Array = Sprites.strip("fx_starx", 4)
	var core := Sprites.region("fx_core_0")
	var big_core := Sprites.region("fx_core_1")
	var tick := int(time * 12.0)
	var fire_glow := Color(SPELL_COLORS[World.SP_FIRE], 0.4)
	var frost_glow := Color(SPELL_COLORS[World.SP_FROST], 0.3)
	var star_col: Color = SPELL_COLORS[World.SP_STAR]
	for s in vs:
		var p: Vector2 = s[1]
		var v: Vector2 = s[2]
		var evo: bool = s[4]
		match s[0]:
			World.SP_ARCANE:
				# A small comet in its caster's colour with a white head; the Astral Lance is a long pointed one
				# with a white comet inside it.
				var col := G.player_fx(s[3])
				var d := Sprites.dir16(v)
				Sprites.glow(ci, p, 5.0 if evo else 3.5, Color(col, 0.4))
				Sprites.draw_mid_r(ci, lances[d] if evo else bolts[d], p, col)
				Sprites.draw_mid_r(ci, bolts[d] if evo else core, p)
			World.SP_FIRE:
				# A tumbling flame: four frames a quarter turn apart, each ball out of step with the next.
				var f := (tick + int(absf(v.x) * 7.0 + absf(v.y) * 3.0)) & 3
				Sprites.glow(ci, p, 13.0 if evo else 9.0, fire_glow)
				Sprites.draw_mid_r(ci, big_fires[f] if evo else fires[f], p)
			World.SP_FROST:
				var d := Sprites.dir16(v)
				Sprites.glow(ci, p, 5.0 if evo else 3.0, frost_glow)
				Sprites.draw_mid_r(ci, big_shards[d] if evo else shards[d], p)
			World.SP_STAR:
				# A falling star: a twinkling star with a comet's tail (the mark and the burst when it lands are Fx's).
				var d := Sprites.dir16(v)
				Sprites.glow(ci, p, 10.0 if evo else 7.0, Color(star_col, 0.4))
				Sprites.draw_mid_r(ci, lances[d] if evo else bolts[d], p, Color(star_col, 0.7))
				Sprites.draw_mid_r(ci, big_stars[tick & 3] if evo else stars[tick & 3], p)
	# Staff heads and the rune shield's orbs
	var orb := Sprites.region("fx_orb")
	var orb_glow := Color(Sprites.ORBIT_COLOR, 0.4)
	for slot in vp:
		var p: Dictionary = vp[slot]
		if not p.alive:
			continue
		var aim: Vector2 = p.aim
		var tip: Vector2 = p.pos + Vector2(0, -7) + aim * 9.0
		var sc := G.player_fx(slot)
		# A staff held away from the camera is behind the wizard's hat: its light is dimmer, and never white.
		var hidden := aim.y < 0.0 and absf(aim.y) > absf(aim.x) * 1.1
		if time - float(p.get("flare_at", -9.0)) < CAST_FLARE:
			Sprites.glow(ci, tip, 5.0, Color(sc, 0.5 if hidden else 0.95))
			if not hidden:
				Sprites.draw_mid_r(ci, big_core, tip)
		else:
			Sprites.glow(ci, tip, 3.5 if hidden else 5.0, Color(sc, 0.4 + 0.12 * sin(time * 6.0 + slot)))
		if p.orbit > 0.0 and (p.orbit > 2.0 or int(time * 10) % 2 == 0):
			for i in 3:
				var a: float = p.orbit_ang + i * TAU / 3.0
				var op: Vector2 = p.pos + Vector2(0, -6) + Vector2(cos(a), sin(a)) * 22.0
				Sprites.glow(ci, op, 6.0, orb_glow)
				Sprites.draw_mid_r(ci, orb, op)
	# Danger is red: a halo under each enemy shot, and round a mage that is gathering one.
	var danger := Color(0.75, 0.15, 0.23, 0.5)
	for s in ves:
		Sprites.glow(ci, s[1], 5.0, danger)
	for e in ve.values():
		if e.type == World.LICH:
			Sprites.glow(ci, e.pos + Vector2(0, -14), 28.0, Color(0.2, 0.88, 0.77, 0.1 + 0.03 * sin(time * 3.0)))
		elif e.type == World.MAGE and e.state == 1:
			Sprites.glow(ci, e.pos + Vector2(0, -8), 7.0, danger)

## Enemy shots, over everything: a dark rim round a blood-red body with an orange core, so none can be taken for
## a wizard's magic or for a pickup. Arrows are plotted for their direction; orbs and skulls pulse.
func _draw_eshots() -> void:
	var ci := eshot_layer
	var arrows: Array = Sprites.strip("fx_earrow", Sprites.DIRS)
	var orbs: Array = Sprites.strip("fx_eorb", 2)
	var skulls: Array = Sprites.strip("fx_eskull", 2)
	var beat := int(time * 8.0) & 1
	for s in ves:
		var p: Vector2 = s[1]
		match s[0]:
			World.ES_ARROW:
				var v: Vector2 = s[2]
				Sprites.draw_mid_r(ci, arrows[Sprites.dir16(v)], p - v.normalized() * 4.0)
			World.ES_ORB:
				Sprites.draw_mid_r(ci, orbs[beat], p)
			World.ES_SKULL:
				Sprites.draw_mid_r(ci, skulls[beat], p)

func _draw_hud() -> void:
	var ci := hud
	var dark := Color("0b0716")
	# The HUD band: the arena scrolls under it.
	ci.draw_rect(Rect2(0, 0, G.SCREEN.x, G.HUD_H), Color(dark, 0.92))
	ci.draw_rect(Rect2(0, G.HUD_H, G.SCREEN.x, 1), Color("2f2450"))
	_draw_offscreen(ci)
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
			var px := x + 64 + sp * 9
			ci.draw_rect(Rect2(px, 3, 8, 4), Color.WHITE if wlv > Spells.MAX_LEVEL else Color("3a2f55"))
			ci.draw_rect(Rect2(px + 1, 4, 6.0 * mini(wlv, Spells.MAX_LEVEL) / Spells.MAX_LEVEL, 2), SPELL_COLORS[sp])
		if p.combo >= 5:
			var cc := Color.WHITE if int(time * 8) % 2 == 0 else G.player_fx(slot)
			PixelFont.draw(ci, "x%d" % p.combo, Vector2(x, 17), 1, cc, dark)
		if not p.alive and p.lives > 0:
			PixelFont.draw(ci, "...", Vector2(x + 40, 17), 1, col)
		Sprites.draw_at(ci, "coin", Vector2(x + 80, 23))
		PixelFont.draw(ci, "%d" % p.get("gold", 0), Vector2(x + 85, 17), 1, Color("ffd23d"), dark)
	_draw_party_bar(ci, dark)
	# Boss bar
	if boss_f > 0.0:
		var bw := 300.0
		var bx := 240 - bw / 2
		PixelFont.draw_centered(ci, Lore.ARCHLICH_NAME if boss_final else Lore.LICH_NAME, 240, 249, 1, Color("ff4df2") if boss_final else Color("4dfff0"), dark)
		var rim := Color("ff4df2") if boss_final else Color("4dfff0")
		ci.draw_rect(Rect2(bx - 3, 257, bw + 6, 10), dark)
		ci.draw_rect(Rect2(bx - 2, 258, bw + 4, 1), rim)
		ci.draw_rect(Rect2(bx - 2, 265, bw + 4, 1), rim)
		ci.draw_rect(Rect2(bx, 260, bw, 4), Color("2c0d4d"))
		# A sigil at each end and runes either side of the name: Morvane's seal on his bar.
		Occult.sigil(ci, Vector2(bx - 8, 262), 5.0, time)
		Occult.sigil(ci, Vector2(bx + bw + 8, 262), 5.0, time)
		var nw := PixelFont.text_width(Lore.ARCHLICH_NAME if boss_final else Lore.LICH_NAME, 1)
		for k in 3:
			var glow := Color(rim, 0.55 + 0.45 * maxf(0.0, sin(time * 3.0 - k)))
			Occult.rune(ci, Vector2(240 - nw / 2.0 - 12 - k * 7, 249), k + 2, glow)
			Occult.rune(ci, Vector2(240 + nw / 2.0 + 8 + k * 7, 249), k + 5, glow)
		ci.draw_rect(Rect2(bx, 260, bw * boss_f, 4), Color("4dfff0") if boss_f > 0.5 else Color("ff4d6a"))
		ci.draw_rect(Rect2(bx, 260, bw * boss_f, 1), Color.WHITE)
	_draw_hint(ci)
	_draw_reveals(ci, dark)
	_draw_card_reveal(ci, dark)
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
	# The level-up cards go over the banners and the act card, so a banner never hides a tray's last row.
	if not game_over and not paused:
		_draw_draws(ci, dark)
	# Screen flash
	if screen_flash.a > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), screen_flash)
	if game_over:
		_draw_game_over(ci)
	elif paused:
		_draw_pause(ci)

## The party's one XP bar along the bottom edge of the HUD strip; at the foot of the screen (above the boss bar
## while a boss is up) the party level beside the run clock, and the lull's countdown next to them. The columns
## under the HUD strip belong to the wizards' card tabs and trays.
func _draw_party_bar(ci: CanvasItem, dark: Color) -> void:
	var xf := clampf(float(party_xp) / float(maxi(1, party_need)), 0.0, 1.0)
	var y := G.HUD_H - 2.0
	var flash := clampf(1.0 - (time - _lv_flash_t) / 0.6, 0.0, 1.0)
	ci.draw_rect(Rect2(0, y, G.SCREEN.x, 2), Color("1c2a24"))
	ci.draw_rect(Rect2(0, y, G.SCREEN.x * xf, 2), Color("5dff7a").lerp(Color.WHITE, flash))
	if flash > 0.0:
		ci.draw_rect(Rect2(0, y - 1, G.SCREEN.x, 3), Color(1, 1, 1, flash * 0.35))
	if game_over:
		return
	var lv := "LV %d" % party_level
	var clock := _clock(run_t)
	var gap := 6
	var lw := PixelFont.text_width(lv, 1)
	var cw := PixelFont.text_width(clock, 1)
	var pw := lw + gap + cw + 8
	# The pill stays centred on its own and the lull plate hangs off its right side at one width, so nothing
	# jumps sideways when a lull starts or ends or its count drops a digit.
	var x0 := floorf(240.0 - pw / 2.0)
	var py := 234.0 if boss_f > 0.0 else G.SCREEN.y - 13.0
	var lc := Color("5dff7a").lerp(Color.WHITE, flash)
	ci.draw_rect(Rect2(x0, py, pw, 12), Color(dark, 0.92))
	ci.draw_rect(Rect2(x0, py - 1, pw, 1), Color("2f2450"))
	PixelFont.draw(ci, lv, Vector2(x0 + 4, py + 3), 1, lc, dark)
	PixelFont.draw(ci, clock, Vector2(x0 + 4 + lw + gap, py + 3), 1, Color("c9b8ff"), dark)
	if lull_left <= 0.0:
		return
	# The lull: a gold plate counting down, its bar draining; red in the last three seconds.
	var lull := "RESPITE %d" % ceili(lull_left)
	var rw := PixelFont.text_width("RESPITE 00", 1) + 8
	var lx := x0 + pw + 4
	var urgent := lull_left <= 3.0
	var pulse := 0.5 + 0.5 * sin(time * (10.0 if urgent else 4.0))
	var gc := Color("ffd94d").lerp(Color("ff6a4d"), pulse) if urgent else Color("ffd94d")
	ci.draw_rect(Rect2(lx - 1, py - 1, rw + 2, 14), Color(gc, 0.35 + 0.35 * pulse))
	ci.draw_rect(Rect2(lx, py, rw, 12), Color(dark, 0.95))
	PixelFont.draw(ci, lull, Vector2(lx + 4, py + 3), 1, gc, dark)
	ci.draw_rect(Rect2(lx + 1, py + 11, (rw - 2) * clampf(lull_left / _lull_full, 0.0, 1.0), 1), gc)

## Arrows at the screen's edge pointing at what matters out of view: chests, cards and the Lich.
func _draw_offscreen(ci: CanvasItem) -> void:
	var view := Rect2(Vector2(6, G.HUD_H + 6), G.SCREEN - Vector2(12, G.HUD_H + 12))
	var marks: Array = []
	for k: Array in vk:
		var kind: int = k[0]
		if kind == World.PK_CHEST or kind >= World.PK_CARD:
			marks.append([k[1], _pickup_color(kind)])
	for e: Dictionary in ve.values():
		if e.type == World.LICH:
			marks.append([e.pos, Color("ff4df2") if boss_final else Color("4dfff0")])
	for m: Array in marks:
		var sp := _on_screen(m[0])
		if view.grow(4).has_point(sp):
			continue
		var center := view.get_center()
		var d: Vector2 = (sp - center)
		# Where the line from the middle to the thing leaves the view.
		var tx := (view.size.x / 2.0) / maxf(absf(d.x), 0.001)
		var ty := (view.size.y / 2.0) / maxf(absf(d.y), 0.001)
		var at := center + d * minf(tx, ty)
		var dir := d.normalized()
		var side := Vector2(-dir.y, dir.x)
		var pulse := 0.6 + 0.4 * sin(time * 6.0)
		var col: Color = m[1]
		var tip := at
		var pts := PackedVector2Array([tip, tip - dir * 7.0 + side * 4.0, tip - dir * 7.0 - side * 4.0])
		ci.draw_colored_polygon(pts, Color(col, pulse))
		ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(Occult.INK, 0.9), 1.0)

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

## True while any wizard holds cards (the autotest keys shots on it).
func _anyone_picking() -> bool:
	for p: Dictionary in vp.values():
		if not (p.get("choices", []) as Array).is_empty():
			return true
	return false

func _draws(slot: int) -> int:
	return int(vp[slot].get("draws", 0)) if vp.has(slot) else 0

## The input device of a local wizard, or -99 for a remote one.
func _slot_device(slot: int) -> int:
	for r in Net.my_slots():
		if r.slot == slot:
			return r.device
	return -99

## True while `slot`'s tray is open on this screen: a local wizard holding cards who opened it.
func _tray_shown(slot: int) -> bool:
	return bool(_tray_open.get(slot, false)) and vp.has(slot) and not (vp[slot].choices as Array).is_empty()

func _set_tray(slot: int, open: bool) -> void:
	if open != _tray_shown(slot):
		Sfx.play("card_flip" if open else "menu_move", -4.0)
	_tray_open[slot] = open

## The tab and the tray sit in the wizard's own HUD column, directly under the HUD strip.
func _tab_rect(slot: int) -> Rect2:
	return Rect2(slot * 120 + 1, G.HUD_H + 1, TRAY_W, TAB_H)

func _tray_rect(slot: int) -> Rect2:
	var n: int = (vp[slot].choices as Array).size()
	return Rect2(slot * 120 + 1, G.HUD_H + 1, TRAY_W, 1 + n * TRAY_ROW_H + 8)

func _tray_row_rect(slot: int, c: int) -> Rect2:
	return Rect2(slot * 120 + 2, G.HUD_H + 1 + c * TRAY_ROW_H, TRAY_W - 2, TRAY_ROW_H)

## How far row `c` of `slot`'s hand has turned over: 0 face down, 1 face up. A hand dealt while the tray is
## open turns over in TRAY_FLIP seconds, row by row, with the card sounds.
func _tray_turn(slot: int, c: int) -> float:
	var seen: Array = _tray_dealt.get(slot, [-1, -10.0, 7, false])
	var step := TRAY_FLIP / 5.0
	var k := clampf((time - float(seen[1]) - step * c) / (step * 3.0), 0.0, 1.0)
	if k >= 0.5 and (int(seen[2]) & (1 << c)) == 0:
		seen[2] = int(seen[2]) | (1 << c)
		Sfx.play("card_flip", -4.0, 1.0 + c * 0.06, 0.03)
	return k

## Records `slot`'s new hand `offer`: with `turn` its rows turn over from now, with the deal sound; without, it
## is face up already (a hand dealt while the tray was shut, shown when the player opens it).
func _deal_tray(slot: int, offer: int, turn: bool) -> void:
	_tray_dealt[slot] = [offer, time, 0, true] if turn else [offer, time - TRAY_FLIP, 7, false]
	if turn:
		Sfx.play("card_deal", -2.0)

## True while a monster card reveal or a fate bet fills the middle of the screen: the trays fold down to their
## tabs and the take buttons do nothing (opening and closing still work).
func _tray_covered() -> bool:
	if not _cards.is_empty():
		return true
	for b: Dictionary in _bets:
		if b.kind == Gamble.TEAM:
			return true
	return false

## The level-up cards on screen: a tab under the HUD panel of every wizard with draws waiting, or the open tray of
## a local wizard; then a marker over each living wizard with a tab, drawn last so no tray hides it.
func _draw_draws(ci: CanvasItem, dark: Color) -> void:
	var covered := _tray_covered()
	var marked: Array[int] = []
	for slot: int in vp.keys():
		if _draws(slot) <= 0:
			continue
		if _tray_shown(slot) and not covered:
			_draw_tray(ci, slot, dark)
			continue
		_draw_tab(ci, slot, dark)
		# The marker waits out the LEVEL UP call-out, which rises from the same spot.
		if vp[slot].alive and time - float(_tab_flash.get(slot, -10.0)) > 0.6:
			marked.append(slot)
	for slot: int in marked:
		_draw_draw_marker(ci, slot)

## The tab: a card back, DRAW, the number of draws past one, and the button that opens the tray.
func _draw_tab(ci: CanvasItem, slot: int, dark: Color) -> void:
	var r := _tab_rect(slot)
	var col := G.player_color(slot)
	var flash := clampf(1.0 - (time - float(_tab_flash.get(slot, -10.0))) / 0.5, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	# The border pulses in the wizard's colour and turns gold at each peak, so it stands out on any floor.
	var rim := col.lerp(Color("ffd94d"), clampf((pulse - 0.75) * 4.0, 0.0, 1.0)).lerp(Color.WHITE, flash)
	ci.draw_rect(r.grow(1), Color(rim, 0.45 + 0.45 * pulse))
	ci.draw_rect(r, dark.lerp(col, 0.12 + 0.14 * pulse))
	TarotArt.draw_back_icon(ci, Rect2(r.position + Vector2(3, 1), Vector2(7, 9)), col)
	var tc := Color("ffd94d").lerp(Color.WHITE, maxf(flash, pulse * 0.4))
	PixelFont.draw(ci, "DRAW", Vector2(r.position.x + 14, r.position.y + 2), 1, tc, dark)
	if _draws(slot) > 1:
		PixelFont.draw(ci, "x%d" % _draws(slot), Vector2(r.position.x + 43, r.position.y + 2), 1, Color.WHITE, dark)
	var dev := _slot_device(slot)
	if dev != -99:
		var label := "E" if dev == G.DEV_KBM else "LB"
		_draw_keycap(ci, Vector2(r.end.x - 3 - PixelFont.text_width(label) - 2, r.position.y + 1), label)
	if flash > 0.0:
		ci.draw_rect(r, Color(1, 1, 1, flash * 0.45))

## The open tray: one row per card, each with the button that takes it; the footer says how many draws wait
## behind this hand and which button hides the tray.
func _draw_tray(ci: CanvasItem, slot: int, dark: Color) -> void:
	var p: Dictionary = vp[slot]
	var col := G.player_color(slot)
	var r := _tray_rect(slot)
	var dev := _slot_device(slot)
	# The body and footer let a little of the arena through; the card rows are solid behind their text.
	ci.draw_rect(r.grow(1), Color(col, 0.55))
	ci.draw_rect(r, Color(dark, 0.75))
	var choices: Array = p.choices
	for c in choices.size():
		var rr := _tray_row_rect(slot, c)
		var k := _tray_turn(slot, c)
		if k < 0.5:
			var w := rr.size.x * (1.0 - k * 2.0)
			TarotArt.draw_back(ci, Rect2(rr.get_center().x - w / 2.0, rr.position.y, w, rr.size.y))
			continue
		var idx: int = choices[c]
		var lv: int = p.choice_lv[c]
		var lv_text := "NEW" if lv == 1 else "%d/%d" % [lv, Upgrades.max_level(idx)]
		TarotArt.draw_card_row(ci, rr, Upgrades.key(idx), Upgrades.display_name(idx), Upgrades.description(idx),
			lv_text, 11.0)
		_draw_pick_button(ci, rr.position + Vector2(1, 4), dev, c)
		if k < 0.75:
			ci.draw_rect(rr, Color(1, 1, 1, (0.75 - k) * 3.0))
	var fy := r.end.y - 8.0
	if _draws(slot) > 1:
		PixelFont.draw(ci, "+%d MORE" % (_draws(slot) - 1), Vector2(r.position.x + 3, fy), 1, Color("ffd94d"), dark)
	var label := "E" if dev == G.DEV_KBM else "LB"
	var hx := r.end.x - 2 - PixelFont.text_width("HIDE")
	PixelFont.draw(ci, "HIDE", Vector2(hx, fy), 1, Color("8a7aa8"), dark)
	_draw_keycap(ci, Vector2(hx - 4 - PixelFont.text_width(label) - 2, fy - 1), label, false)

## A small light keycap with a label, 9 px tall (11 with its dark outline).
func _draw_keycap(ci: CanvasItem, at: Vector2, label: String, outline: bool = true) -> void:
	var w := PixelFont.text_width(label) + 2
	if outline:
		ci.draw_rect(Rect2(at - Vector2(1, 1), Vector2(w + 2, 11)), Occult.INK)
	ci.draw_rect(Rect2(at, Vector2(w, 9)), Color("e8dcc0"))
	ci.draw_rect(Rect2(at + Vector2(0, 8), Vector2(w, 1)), Color("a89a80"))
	PixelFont.draw(ci, label, at + Vector2(1, 1), 1, Occult.INK)

## The button that takes card `c`: 1, 2, 3 on a keycap for the keyboard; for a pad, a diamond of four dots with
## the left, the top or the right one lit (pads print different letters on those buttons). `at` is the glyph's
## top-left: the keycap starts 1 px in; the diamond is 9x9 with a 1 px dark outline, 11 px in all.
func _draw_pick_button(ci: CanvasItem, at: Vector2, dev: int, c: int) -> void:
	if dev == G.DEV_KBM or dev == -99:
		_draw_keycap(ci, at + Vector2(1, 0), str(c + 1), false)
		return
	var dots := [Vector2(0, 3), Vector2(3, 0), Vector2(6, 3), Vector2(3, 6)] # left, top, right, bottom
	for d: Vector2 in dots:
		ci.draw_rect(Rect2(at + d - Vector2(1, 1), Vector2(5, 5)), Occult.INK)
	for d in dots.size():
		ci.draw_rect(Rect2(at + dots[d], Vector2(3, 3)), Color("ffd94d") if d == c else Color("8a7aa8"))
	ci.draw_rect(Rect2(at + dots[c] + Vector2(1, 1), Vector2(1, 1)), Color.WHITE)

## A card bobbing over a wizard with draws waiting, so the player sees it where they look; under the feet when
## the wizard is so near the top of the view that the tabs would cover it.
func _draw_draw_marker(ci: CanvasItem, slot: int) -> void:
	var col := G.player_color(slot)
	var feet := _on_screen(vp[slot].pos)
	var bob := floorf(sin(time * 4.0 + slot) * 1.5)
	var at := (feet + Vector2(-3, -36 + bob)).floor()
	if at.y < G.HUD_H + TAB_H + 4.0:
		at.y = floorf(feet.y + 6.0 + bob)
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	var r := Rect2(at, Vector2(7, 9))
	ci.draw_rect(r.grow(2), Color(col, 0.25 + 0.35 * pulse))
	TarotArt.draw_back_icon(ci, r, col)

## Routes the card buttons to local trays: E, LB or LT (or a click on the tab, or on the tray's footer) opens and
## closes a wizard's tray; 1 2 3 or X Y B (or a click on a row) takes a card while it is open. The mouse and touch
## work the keyboard wizard's tray. Returns true if the event was used.
func _tray_input(event: InputEvent) -> bool:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		var ks := -1
		for r in Net.my_slots():
			if r.device == G.DEV_KBM:
				ks = r.slot
		if ks < 0 or _draws(ks) <= 0:
			return false
		var pos: Vector2 = event.position
		if not _tray_shown(ks) or _tray_covered():
			if not _tab_rect(ks).has_point(pos):
				return false
			_set_tray(ks, not _tray_shown(ks))
			return true
		if not _tray_rect(ks).grow(1).has_point(pos):
			return false
		var n: int = (vp[ks].choices as Array).size()
		for c in n:
			if _tray_row_rect(ks, c).has_point(pos):
				_take_card(ks, c)
		if pos.y >= _tray_row_rect(ks, n - 1).end.y:
			_set_tray(ks, false) # the footer with HIDE
		return true
	for r in Net.my_slots():
		var slot: int = r.slot
		var dev: int = r.device
		var toggle := false
		var card := -1
		if dev == G.DEV_KBM and event is InputEventKey and event.pressed and not event.echo:
			match event.physical_keycode:
				KEY_E: toggle = true
				KEY_1, KEY_KP_1: card = 0
				KEY_2, KEY_KP_2: card = 1
				KEY_3, KEY_KP_3: card = 2
		elif dev != G.DEV_KBM and event is InputEventJoypadButton and event.pressed and event.device == dev:
			match event.button_index:
				JOY_BUTTON_LEFT_SHOULDER: toggle = true
				JOY_BUTTON_X: card = 0
				JOY_BUTTON_Y: card = 1
				JOY_BUTTON_B: card = 2
		elif dev != G.DEV_KBM and event is InputEventJoypadMotion and event.device == dev \
				and event.axis == JOY_AXIS_TRIGGER_LEFT:
			var was: bool = _lt_held.get(dev, false)
			_lt_held[dev] = event.axis_value > 0.5
			toggle = event.axis_value > 0.5 and not was
		if toggle and _draws(slot) > 0:
			_set_tray(slot, not _tray_shown(slot))
			return true
		if card >= 0 and _tray_shown(slot):
			if not _tray_covered(): # under a card reveal or a fate bet the tray is folded away
				_take_card(slot, card)
			return true
	return false

## Takes card `c` of `slot`'s hand, only if that row is there and face up. A hand that turned over on screen takes
## no press until it has been face up for TRAY_READ, and no press counts within PICK_GAP of the wizard's last take,
## so a mashed or held button cannot take the next card unseen.
func _take_card(slot: int, c: int) -> void:
	if c >= (vp[slot].choices as Array).size() or _tray_turn(slot, c) < 1.0:
		return
	var seen: Array = _tray_dealt.get(slot, [-1, -10.0, 7, false])
	if bool(seen[3]) and time - float(seen[1]) < TRAY_FLIP + TRAY_READ:
		return
	if time - float(_pick_t.get(slot, -10.0)) < PICK_GAP:
		return
	var sent: Array = _pick_sent.get(slot, [-1, -1])
	if int(sent[1]) == int(vp[slot].offer):
		return
	_pick_sent[slot] = [c, int(vp[slot].offer)]
	_pick_t[slot] = time
	Sfx.play("card_pick", -2.0)

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

## The tarot card each award is read as on the results screen (TarotArt emblem keys); no award draws The Star.
const AWARD_ARCANA := {"MVP": "power", "SLAYER": "death", "HIGH ROLLER": "magnet", "LUCKY": "sun",
	"GOLD DIGGER": "quick", "UNTOUCHABLE": "life", "TEAM PLAYER": "regen"}

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
		# Each wizard's reading: a card face with their award's arcana in the corner.
		var card := Rect2(cx - colw / 2.0 + 4, y0 - 4, colw - 8, 88)
		ci.draw_rect(card, Color(col.r * 0.25, col.g * 0.2, col.b * 0.3, 0.75 * show))
		ci.draw_rect(card, Color(Occult.GOLD, 0.7 * show), false, 1.0)
		ci.draw_rect(card.grow(-2), Color(col.r, col.g, col.b, 0.45 * show), false, 1.0)
		var award: String = titles.get(slot, "")
		var arcana: String = AWARD_ARCANA.get(award, "w_star")
		var em := Rect2(card.position + Vector2(5, 4), Vector2(24, 24))
		ci.draw_rect(em.grow(1), Color(dark, show))
		ci.draw_texture_rect(TarotArt.emblem(arcana), em, false, Color(1, 1, 1, show))
		PixelFont.draw_centered(ci, "P%d" % (slot + 1), cx + 14, y0 + 2, 2, col, dark)
		if award != "":
			PixelFont.draw_centered(ci, award, cx + 14, y0 + 18, 1, Color("ffd94d"), dark)
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

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		if game_over_t > 2.0 and is_host:
			var tapped = event is InputEventScreenTouch and event.pressed
			var clicked = event is InputEventMouseButton and event.pressed
			if PlayerInput.confirm_device(event) != -99 or tapped or clicked or \
					(event is InputEventKey and event.pressed and event.physical_keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]):
				if Net.mode == Net.Mode.OFFLINE:
					Engine.time_scale = 1.0
					Net.shutdown()
					G.goto_sanctum()
				else:
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
	if not paused and _tray_input(event):
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

# ----- Forwarders: the moved code (game/arena/*.gd) keeps these names callable on the Arena -----
func _with_pick(slot: int, inp: PackedFloat32Array) -> PackedFloat32Array: return ArenaSeats._with_pick(self, slot, inp)
func _bot_input(slot: int) -> PackedFloat32Array: return ArenaSeats._bot_input(self, slot)
func _apply_snapshot(snap: Dictionary, instant: bool) -> void: ArenaViewSync._apply_snapshot(self, snap, instant)
func _handle_events(evs: Array) -> void: ArenaEvents._handle_events(self, evs)

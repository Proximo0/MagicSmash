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
## Class weapon skins (Classes.SKINS) in their own colours: the longbow's arrows, the paladin's hammers of light,
## the priest's white light and the knight's steel arc.
const SKIN_COLORS := {"longbow": Color("c9844a"), "smite": Color("fff2c0"), "holy_light": Color("fff6e0"),
	"cleave": Color("d8e4f0")}
## Seconds a rune circle takes to draw itself in and to fade out.
const RUNE_DRAW_IN := 0.25
const RUNE_FADE := 0.4
## Enemy looks by type (EnemyView): walk cycles, their frame rates, shadows and names.
const ENEMY_KEYS := EnemyView.KEYS
## The smallest combo call written over a wizard; smaller ones only sparkle.
const COMBO_WORDS := 50
const ENEMY_SHADOW := EnemyView.SHADOW
const ENEMY_ANIM := EnemyView.ANIM
const PICKUP_KEYS := ["coin", "gem", "potion", "tome_fire", "tome_frost", "tome_storm", "tome_star", "boot", "tome_orbit", "xp", "chest",
	"tome_rune", "card", "chest_rare", "chest_ultra", "tome_star"] # the party tome wears the star tome's look
const PICKUP_NAMES := ["", "", "POTION +2", "FIREBALL!", "FROST FAN!", "CHAIN LIGHTNING!", "STARFALL!", "HASTE!", "RUNE SHIELD!", "", "",
	"RUNE CIRCLE!", "", "", "", "PARTY TOME"]
## Loot tier colours (Loot.COMMON .. Loot.ULTRA): readable in 3 seconds with the sound off.
const RARITY_COLORS := [Color("c9c9d6"), Color("4d9bff"), Color("c04dff"), Color("ffb84d"), Color("ff4df2")]
## Seconds a chest reel spins before it shows the item, and how long the item stays up after.
const REEL_SPIN := 1.0
const REEL_SHOW := 1.6
const ENEMY_NAMES := EnemyView.NAMES

## Cosmetic randomness only (particles, shake, pitch). Gameplay randomness lives in World.rng.
var _fx_rng := RandomNumberGenerator.new()
var world: World = null
var is_host := true
var frame := 0
var pending_events: Array = []

# View state (what gets drawn), filled from snapshots on every peer.
var vp := {}  # slot -> Dictionary
var ve := {}  # id -> Dictionary
var vs: Array = []  # [spell, pos, vel, owner, evolved, evolution id]
var vr: Array = []  # rune circles: [pos, radius, age, life, owner, evolved, kind, evolution id]
var vhz := PackedFloat32Array() # hazard rows, Hazards.FLOATS each (snapshot "hz")
var vo: Array = []  # spell objects, World.O_FLOATS floats each (none exist yet)
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
var vw := PackedFloat32Array() # the header, snapshot "w" (ArenaDrawBoss reads the boss rows)
var victory := false # the Archlich fell: the run is won
var run_t := 0.0 # seconds of fighting, from the snapshot
var seal := 0 # the run's Seal level, from the snapshot header
var slot_cap := Upgrades.UNCAPPED # spell and passive slots, from the snapshot header
var fates := PackedFloat32Array() # the fates in force, from the snapshot (WorldShrines.snapshot_fates); empty: none
var _reveals: Array = [] # chest reels: {slot, pos, item, tier, t, shown}
var _cards: Array = [] # monster card notices under the HUD, one at a time: {idx, slot, t, first}
const CARD_SHOW := 4.0
var doors := [0.0, 0.0, 0.0, 0.0]
var door_anim := [0.0, 0.0, 0.0, 0.0]
var game_over := false
var game_over_t := 0.0
var results_page := 0 # 0 the first page, 1 the damage page (ArenaResultsView)
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
## QUIT TO TITLE asks first (pause_sel then picks NO or YES); NO is the default.
const PAUSE_ASK_ITEMS := ["NO", "YES"]
const PAUSE_QUIT := 2
const PAUSE_ASK_YES := 1
## How long "ONLY P1 CAN END THE RUN" shows after someone else chose QUIT TO TITLE.
const PAUSE_NOTE_SECS := 1.6
## No device: an automatic pause's, and PlayerInput.confirm_device's "no confirm".
const NO_DEVICE := -99
var pause_ask := false
var pause_by := -1 # the seat that paused (its device or the keyboard); -1: an automatic pause or a seatless keyboard
var pause_dev := NO_DEVICE # the device that paused; NO_DEVICE for an automatic pause
var pause_note_t := -10.0 # when the "ONLY P1" note was last shown (time)
## The run is in the profile (ArenaEvents.book_run_once): whatever ends it books it once.
var run_booked := false
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
const TRAY_W := 118 # wider than a HUD panel: the longest effect line and its level chip need 116 px
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
var wiz_layer: Node2D
var lighting: ArenaLighting
var fx: Fx
var shot_layer: Node2D
var eshot_layer: Node2D
var hud_layer: CanvasLayer
var hud: Node2D
var touch: TouchControls

func _ready() -> void:
	is_host = Net.is_host()
	Input.joy_connection_changed.connect(_on_joy_changed)
	Platform.overlay_toggled.connect(_on_overlay)
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
	# The room's light multiplies over the floor and the enemies; particles, shots and wizards draw above it.
	lighting = ArenaLighting.attach(self)
	fx = Fx.new()
	fx.calm = true
	root.add_child(fx)
	shot_layer = _layer(true)
	shot_layer.draw.connect(_timed.bind("draw_shots", _draw_shots))
	# The wizards over their own magic and the crowd, only the enemies' shots above them.
	wiz_layer = _layer(false)
	wiz_layer.draw.connect(_timed.bind("draw_wizards", _draw_wizards))
	eshot_layer = _layer(false)
	eshot_layer.draw.connect(_timed.bind("draw_eshots", _draw_eshots))
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
	Net.events_received.connect(_on_events)
	Net.roster_changed.connect(_on_roster_changed)
	if is_host:
		var slots := []
		for r in Net.roster:
			slots.append(r.slot)
		if slots.is_empty():
			slots.append(0)
		world = World.new(slots, int(Flags.get_arg("seed", "0")), null, Net.wizard_picks(), Net.seat_builds())
		world.apply_meta(Save.run_bonuses())
		# Saved heroes from the lobby (the roster rows carry the host-cleaned dict). Scripted runs seat none.
		for r: Dictionary in Net.roster:
			var hd: Variant = r.get("hero", {})
			if hd is Dictionary and not (hd as Dictionary).is_empty() and world.players.has(r.slot):
				world.apply_hero(world.players[r.slot], hd)
		# Developer flag until the builder screens land: --hero=<race>,<class>[,<school>] gives every local seat
		# that hero (Hero.from_flag). Nothing happens without it, scripted run or not.
		if Flags.args.has("hero"):
			var flag_hero := Hero.from_flag(Flags.get_arg("hero"))
			if flag_hero == null:
				push_warning("--hero=%s: unknown race or class" % Flags.get_arg("hero"))
			else:
				for r in Net.my_slots():
					if world.players.has(r.slot):
						world.apply_hero(world.players[r.slot], flag_hero.to_dict())
		world.apply_seal(Net.seal)
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
	PlayerInput.bomb_muted = false
	PlayerInput.touch = null
	Engine.time_scale = 1.0

## True while the run stands still: paused with nobody else connected (a LAN host alone can pause too).
func _frozen() -> bool:
	return paused and not Net.has_remote_players()

func _physics_process(dt: float) -> void:
	if _frozen():
		return
	PlayerInput.bomb_muted = paused or _local_tray_open()
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
		pending_events.append_array(Net.send_events(evs) if Net.is_online() else evs) # run-ending ones go reliably
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
	wiz_layer.queue_redraw()
	shot_layer.queue_redraw()
	eshot_layer.queue_redraw()
	env_add.queue_redraw()
	hud.queue_redraw()

## Bot wizards (autotest, the bot gate): SmashBot fed from the view state, so it also works on LAN clients.
## `--persona=novice|casual|veteran` picks how well they play (casual by default).
var _bots := {}  # slot -> SmashBot
var _bot_track := {}  # enemy id -> [last seen position, estimated velocity, time seen], for the bots' senses

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
	# Second guard for the reliable events: the host's run has been over a while and no game over came.
	if phase == World.PH_GAMEOVER and not game_over and phase_t > GAMEOVER_GUARD:
		game_over = true
		game_over_t = 0.0

## Seconds a client sees the host's game over phase before it ends the run without the event.
const GAMEOVER_GUARD := 1.5

## Client: the host's run-ending and saved-data events (Net.RELIABLE_EVENTS), by reliable RPC.
func _on_events(evs: Array) -> void:
	if not is_host:
		_handle_events(evs)

func _on_roster_changed() -> void:
	if not is_host or world == null:
		return
	var live := {}
	for r in Net.roster:
		live[r.slot] = true
		if world.players.has(r.slot):
			var p: World.Player = world.players[r.slot]
			var played := Net.played_by_ai(r) # an away seat is played as an apprentice
			if played != p.ai:
				p.last_bomb = -1 # the hand and the bot count their Nova presses apart: start again from the next input
			p.ai = played
			p.away = played and bool(r.get("away", false))
	for s in world.players.keys():
		if not live.has(s):
			world.remove_player(s) # her score and kills stay in the run

## A world position on the screen (for HUD things that point at the arena).
func _on_screen(p: Vector2) -> Vector2:
	return p - cam

func _add_shake(v: float) -> void:
	if not Save.settings.shake:
		return
	shake = minf(14.0, maxf(shake, v))

func _do_hitstop(d: float) -> void:
	if Net.has_remote_players():
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

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		if game_over_t > 2.0 and PlayerInput.results_dismiss(event):
			if ArenaResultsView.next_page(self):
				return
			if not is_host:
				_quit_to_title() # a client leaves the results on its own
			elif Net.mode == Net.Mode.OFFLINE:
				Engine.time_scale = 1.0
				Net.shutdown()
				G.goto_sanctum()
			else:
				_quit_to_title()
		return
	var start = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE, KEY_P]) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START)
	var dev := _pause_device(event)
	if paused and not _pause_hears(dev):
		return
	if start and pause_options:
		pause_options = false
		Save.write_settings()
		Sfx.play("menu_select")
		return
	if start and pause_ask:
		_pause_ask_close()
		return
	if start:
		if paused:
			_toggle_pause()
		elif _pause_may_open(dev) and not victory:
			_toggle_pause(dev, _seat_of_device(PlayerInput.key_device(event) if event is InputEventKey else dev))
		return
	if not paused and _tray_input(event):
		get_viewport().set_input_as_handled()
		return
	if paused:
		if pause_options:
			if options.handle(event):
				pause_options = false
			return
		if PlayerInput.back_pressed(event):
			if pause_ask:
				_pause_ask_close()
			else:
				_toggle_pause()
			return
		var rows := _pause_rows().size()
		var d := PlayerInput.menu_dir(event)
		if d != 0:
			pause_sel = wrapi(pause_sel + d, 0, rows)
			Sfx.play("menu_move")
		if PlayerInput.confirm_device(event) != NO_DEVICE:
			_pause_choose(pause_sel, dev)
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
			var row := int(floorf((event.position.y - 127.0) / 16.0))
			if row >= 0 and row < rows and absf(event.position.x - 240.0) < 70.0:
				_pause_choose(row, dev)

## Chooses a pause row, pressed on `dev` (the keyboard, a click and a touch are G.DEV_KBM).
func _pause_choose(i: int, dev: int = G.DEV_KBM) -> void:
	Sfx.play("menu_select")
	pause_sel = i
	if pause_ask:
		if i == PAUSE_ASK_YES:
			_end_run_and_leave()
		else:
			_pause_ask_close()
		return
	match i:
		0:
			_toggle_pause()
		1:
			options.open()
			pause_options = true
		PAUSE_QUIT:
			if not _may_end_run(dev):
				pause_note_t = time
				return
			pause_ask = true
			pause_sel = 0

## The rows the pause panel shows: the menu, or the question's NO and YES.
func _pause_rows() -> Array:
	return PAUSE_ASK_ITEMS if pause_ask else PAUSE_ITEMS

## QUIT TO TITLE is dimmed when the seat that paused may not end the run.
func _pause_row_dim(i: int) -> bool:
	return not pause_ask and i == PAUSE_QUIT and pause_dev != NO_DEVICE and not _may_end_run(pause_dev)

func _pause_ask_close() -> void:
	pause_ask = false
	pause_sel = PAUSE_QUIT

## The device a press came from, for the pause rules: a pad's id, or G.DEV_KBM for any key, click or touch
## (the keyboard is the PC owner's).
static func _pause_device(event: InputEvent) -> int:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device
	return G.DEV_KBM

## The local seat played on `device`, or -1.
func _seat_of_device(device: int) -> int:
	for r in Net.my_slots():
		if int(r.device) == device:
			return int(r.slot)
	return -1

## The device of the lowest local seat (P1 on the host), or NO_DEVICE.
func _first_seat_device() -> int:
	var best := -1
	var out := NO_DEVICE
	for r in Net.my_slots():
		if best < 0 or int(r.slot) < best:
			best = int(r.slot)
			out = int(r.device)
	return out

## The lowest local seat (0 = P1), or 0 with none.
func _first_seat() -> int:
	var best := -1
	for r in Net.my_slots():
		if best < 0 or int(r.slot) < best:
			best = int(r.slot)
	return maxi(best, 0)

## Pause opens from the keyboard or from a pad that holds a seat.
func _pause_may_open(dev: int) -> bool:
	return dev == G.DEV_KBM or _seat_of_device(dev) >= 0

## While paused the menu hears the keyboard, the device that paused and the first seat's device.
func _pause_hears(dev: int) -> bool:
	return dev == G.DEV_KBM or dev == pause_dev or dev == _first_seat_device()

## Only the first seat's device or the keyboard may end the run.
func _may_end_run(dev: int) -> bool:
	return dev == G.DEV_KBM or dev == _first_seat_device()

## Opens or closes the pause menu; `dev` and `slot` say who opened it (left out: an automatic pause).
func _toggle_pause(dev: int = NO_DEVICE, slot: int = -1) -> void:
	if game_over:
		return
	paused = not paused
	pause_sel = 0
	pause_ask = false
	pause_dev = dev
	pause_by = slot
	if not paused:
		for r in Net.my_slots(): # the button that chose Resume is still down: it is no Nova
			PlayerInput.swallow_bomb(r.device)
	if pause_options:
		pause_options = false
		Save.write_settings()
	Sfx.play("menu_select")

## Pauses a solo run when the player loses control (pad unplugged, window left, Steam overlay opened).
func _auto_pause() -> void:
	if Net.mode == Net.Mode.OFFLINE and not game_over and not paused:
		_toggle_pause()

func _on_joy_changed(device: int, connected: bool) -> void:
	if connected:
		return
	for r in Net.my_slots():
		if r.device == device:
			_auto_pause()

func _on_overlay(active: bool) -> void:
	if active:
		_auto_pause()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not Flags.is_scripted_run():
		_auto_pause()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_book_run_now() # the engine quits right after; the save is written synchronously

func _local_tray_open() -> bool:
	for r in Net.my_slots():
		if ArenaTray._tray_shown(self, r.slot):
			return true
	return false

## Books the run as it stands (QUIT TO TITLE, the window closing): a win in the victory countdown, otherwise a run
## not won with what it earned so far. A game over books its own (ArenaEvents); a LAN client has no World and
## books nothing here.
func _book_run_now() -> void:
	if run_booked or game_over or world == null:
		return
	var run: Dictionary = world.run_so_far()
	run["results"] = Results.from_dict(run.results)
	ArenaEvents.book_run_once(self, run)

## The pause question's YES.
func _end_run_and_leave() -> void:
	_book_run_now()
	_quit_to_title()

func _quit_to_title() -> void:
	Engine.time_scale = 1.0
	Net.send_back_to_title() # a host closes a moment after telling the clients; anyone else at once
	G.goto_title()

# ----- Forwarders: the moved code (game/arena/*.gd) keeps these names callable on the Arena -----
func _with_pick(slot: int, inp: PackedFloat32Array) -> PackedFloat32Array: return ArenaSeats._with_pick(self, slot, inp)
func _bot_input(slot: int) -> PackedFloat32Array: return ArenaSeats._bot_input(self, slot)
func _apply_snapshot(snap: Dictionary, instant: bool) -> void: ArenaViewSync._apply_snapshot(self, snap, instant)
func _handle_events(evs: Array) -> void: ArenaEvents._handle_events(self, evs)
func _update_reveals(dt: float) -> void: ArenaFateView._update_reveals(self, dt)
func _act_music() -> String: return ArenaFateView._act_music(self)
func _update_bets(dt: float) -> void: ArenaFateView._update_bets(self, dt)
func _update_act(dt: float) -> void: ArenaFateView._update_act(self, dt)
func _follow_party(dt: float) -> void: ArenaDrawWorld._follow_party(self, dt)
func _emit_trails(dt: float) -> void: ArenaDrawFx._emit_trails(self, dt)
func _torch_fx(dt: float) -> void: ArenaDrawFx._torch_fx(self, dt)
func _draw_decals() -> void: ArenaDrawWorld._draw_decals(self)
func _draw_env() -> void: ArenaDrawWorld._draw_env(self)
func _draw_env_add() -> void: ArenaDrawWorld._draw_env_add(self)
func _draw_entities() -> void: ArenaDrawWorld._draw_entities(self)
func _draw_wizards() -> void: ArenaDrawWorld._draw_wizards(self)
func _draw_shots() -> void: ArenaDrawFx._draw_shots(self)
func _draw_eshots() -> void: ArenaDrawFx._draw_eshots(self)
func _draw_hud() -> void: ArenaHud._draw_hud(self)
func _anyone_picking() -> bool: return ArenaTray._anyone_picking(self)
func _draws(slot: int) -> int: return ArenaTray._draws(self, slot)
func _tray_shown(slot: int) -> bool: return ArenaTray._tray_shown(self, slot)
func _tray_turn(slot: int, c: int) -> float: return ArenaTray._tray_turn(self, slot, c)
func _tray_input(event: InputEvent) -> bool: return ArenaTray._tray_input(self, event)

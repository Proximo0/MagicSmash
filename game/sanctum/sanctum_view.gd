extends Node2D
## The Sanctum between runs: draws the tower room around the pure Sanctum logic and feeds it one wizard's input.
## Walk into pots to smash them, use the portal to start a run, the altar for the card album, the reliquary
## for a sealed deck (crystals buy one card), the music box to change the song and the well for a fortune.
## Somewhere a wall is tired. Books crystals, cards and secrets through Save.

const TRACKS := [["music_sanctum", "THE SANCTUM"], ["music_title", "THE TOWER AT DUSK"],
	["music_library", "THE FORBIDDEN LIBRARY"], ["music_battle", "HOLD THE TOWER"], ["music_boss", "THE ARCHLICH"],
	["music_gameover", "REQUIEM"]]
## The bottom line's crystal mark (`icons/hud_crystal`): its box, px, left of the crystal count.
const CRYSTAL_ICON := Rect2(5, 259, 10, 10)
const CAULDRON := Vector2(240, 248) # its feet, where SanctumArt bakes it

var room: Sanctum
var device := G.DEV_KBM
var t := 0.0
var fx: Fx
var glow: Node2D
var album := CardAlbum.new()
var album_open := false
var roster := HeroRoster.new()
var roster_open := false
var deeds_book := DeedsBook.new()
var deeds_open := false
var track := 0
var message := ""
var message_t := 0.0
var shake := 0.0
var _shards: Array = [] # [pos, vel, life, color]
var _deck: Dictionary = {} # a sealed deck opening: {idx, t, first}
var dlg := DialogueBox.new()
var _ran: Dictionary = {} # the run just ended (G.last_run) until each talker has remarked on it: speaker -> true
var _ran_run: Dictionary = {}
var _after_talk := "" # what the talk box opens when it closes: "shop" (the unlocks)
var _new_card := {Talk.SHOPKEEPER: false, Talk.CARD_READER: false} # a card was found since this one last spoke
var _cat_pet := 0.0
var _rng := RandomNumberGenerator.new()
var _leaving := -1.0
var _room_tex: ImageTexture
var _alcove_tex: ImageTexture
## The use prompt for the thing in reach ([text, centre]), drawn last so nothing in the room covers it.
var _prompt: Array = []


func _ready() -> void:
	_rng.randomize()
	_room_tex = SanctumArt.room()
	_alcove_tex = SanctumArt.alcove()
	if not G.local_devices.is_empty():
		device = G.local_devices[0]
	var prof: Profile = Save.profile
	room = Sanctum.new(_rng.randi(), prof.pots_mask_now(), prof.has_secret("alcove"))
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow = Node2D.new()
	glow.material = m
	glow.z_index = 1
	add_child(glow)
	glow.draw.connect(_draw_glow)
	fx = Fx.new()
	fx.z_index = 2
	add_child(fx)
	Sfx.music(TRACKS[0][0])
	_say("THE SANCTUM. REST, WIZARD." if prof.runs > 0 else "YOUR SANCTUM. THE PORTAL LEADS TO THE TOWER.")
	# Back from a run: Morvane has a word, once.
	if not G.last_run.is_empty():
		var run := G.last_run
		G.last_run = {}
		_ran_run = run
		_ran[Talk.MORVANE] = true
		_talk(Talk.MORVANE, _run_context(Talk.MORVANE))


func _say(s: String, dur: float = 3.0) -> void:
	message = s
	message_t = dur


func _process(delta: float) -> void:
	t += delta
	message_t = maxf(0.0, message_t - delta)
	shake = maxf(0.0, shake - delta * 12.0)
	_cat_pet = maxf(0.0, _cat_pet - delta)
	if _leaving >= 0.0:
		_leaving += delta
		if _leaving > 0.8:
			_go_play()
		queue_redraw()
		glow.queue_redraw()
		return
	dlg.update(delta)
	if roster_open:
		roster.update(delta)
	if deeds_open:
		deeds_book.update(delta)
	if not album_open and not roster_open and not deeds_open and _deck.is_empty() and not dlg.active:
		var inp := PlayerInput.read(device, room.pos, get_viewport())
		room.step(delta, Vector2(inp[0], inp[1]))
	if not _deck.is_empty():
		_deck.t += delta
		if _deck.t > 3.2:
			_deck = {}
	for e: Array in room.take_events():
		_on_event(e)
	for s: Array in _shards:
		s[0] += s[1] * delta
		s[1].y += 160.0 * delta
		s[2] -= delta
	_shards = _shards.filter(func(s: Array) -> bool: return s[2] > 0.0)
	# Dust trickles from the tired wall while someone leans on it.
	if room.crack_t > 0.0 and not room.crack_open and int(t * 30.0) % 3 == 0:
		fx.spawn(Vector2(_rng.randf_range(Sanctum.CRACK_X.x, Sanctum.CRACK_X.y), Sanctum.ROOM.position.y - 2),
			Vector2(_rng.randf_range(-10, 10), 20), 0.6, 1.0, Color("8a7a9a"), Color("3b2c55"))
		shake = maxf(shake, room.crack_t * 1.5)
	glow.visible = not album_open and not roster_open and not deeds_open # the room's light never shines through a full-screen page
	queue_redraw()
	glow.queue_redraw()


func _on_event(e: Array) -> void:
	var prof: Profile = Save.profile
	match int(e[0]):
		Sanctum.EV_POT:
			var at: Vector2 = Sanctum.POTS[int(e[1])]
			prof.break_pot(int(e[1]))
			for i: int in range(8):
				_shards.append([at, Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-90, -30)), 0.8,
					Color("b0643a") if i % 2 == 0 else Color("7a3f22")])
			Sfx.play("hit", -2.0, 0.7)
			var got: Array = e[2]
			match String(got[0]):
				"crystals":
					prof.crystals += int(got[1])
					fx.text(at + Vector2(0, -10), "+%d CRYSTAL%s" % [int(got[1]), "" if int(got[1]) == 1 else "S"], Color("8bdcff"), 1.2)
					fx.sparkle(at, Color("8bdcff"), 8)
					Sfx.play("coin", -4.0, 1.3)
				"card":
					_open_card(int(got[1]), "A CARD WAS HIDDEN IN THE POT!")
			Save.write()
		Sanctum.EV_CRACK:
			Sfx.play("explode", -4.0, 0.6)
			shake = 4.0
			fx.burst(Vector2((Sanctum.CRACK_X.x + Sanctum.CRACK_X.y) / 2.0, Sanctum.ROOM.position.y - 4), 24, 70.0, 0.8, 1.5,
				Color("b8a8d8"), Color("3b2c55"))
			_say("THE WALL GAVE WAY...")
		Sanctum.EV_ALCOVE:
			if prof.find_secret("alcove"):
				prof.crystals += Sanctum.ALCOVE_CRYSTALS
				Save.write()
				Sfx.play("wave_clear", -2.0, 1.2)
				fx.burst(room.pos, 30, 90.0, 0.9, 1.5, Color.WHITE, Color("ffd94d"), true)
				_say("A SECRET ROOM! +%d CRYSTALS" % Sanctum.ALCOVE_CRYSTALS, 4.0)
			else:
				_say("THE CAT'S ROOM.")
		Sanctum.EV_USE:
			_use(int(e[1]))


func _use(i: int) -> void:
	var prof: Profile = Save.profile
	match i:
		Sanctum.PORTAL:
			_leaving = 0.0
			Sfx.play("portal")
			fx.teleport(room.pos, Color("b07bff"))
		Sanctum.ALTAR:
			album.open()
			album_open = true
			Sfx.play("page_turn")
		Sanctum.RELIQUARY:
			if prof.spend(Sanctum.DECK_COST):
				Save.write()
				_open_card(Sanctum.roll_card(_rng, Sanctum.owned_cards(prof)), "THE SEALED DECK OPENS...")
			else:
				Sfx.play("hurt", -6.0)
				_say("A SEALED DECK COSTS %d CRYSTALS." % Sanctum.DECK_COST)
		Sanctum.MUSIC:
			track = (track + 1) % TRACKS.size()
			Sfx.music(TRACKS[track][0])
			Sfx.play("card_flip", -6.0, 1.4)
			_say("NOW PLAYING: " + String(TRACKS[track][1]))
			fx.text(Sanctum.THINGS[i][1] + Vector2(0, -16), Sanctum.MUSIC_NOTE, Color("ffd94d"), 1.0, 2)
		Sanctum.WELL:
			if prof.spend(1):
				var res := Sanctum.toss(prof, _rng)
				var ninth: bool = res.ninth
				var back: int = res.back
				if ninth:
					fx.text(Sanctum.THINGS[i][1] + Vector2(0, -24), "SECRET FOUND", Color("8bdcff"), 2.0)
				prof.crystals += back
				Save.write()
				Sfx.play("coin", -2.0, 0.8)
				var well: Vector2 = Sanctum.THINGS[i][1]
				fx.ring(well, 2.0, 14.0, 0.6, Color("8bdcff"), 1.0)
				if ninth:
					Sfx.play("wave_clear", -2.0, 1.2)
					fx.burst(well, 36, 90.0, 1.0, 1.5, Color.WHITE, Color("ffd94d"), true)
					_say("THE NINTH WISH IS GRANTED! +%d CRYSTALS" % back, 4.0)
				elif back > 0:
					Sfx.play("wave_clear", -4.0, 1.5)
					fx.burst(well, 20, 70.0, 0.8, 1.5, Color.WHITE, Color("8bdcff"), true)
					_say("THE WELL IS GENEROUS! +%d CRYSTALS" % back)
				else:
					_say(Sanctum.fortune(_rng), 4.0)
			else:
				Sfx.play("hurt", -6.0)
				_say("THE WELL WANTS A CRYSTAL.")
		Sanctum.SHOPKEEPER:
			_talk(Talk.SHOPKEEPER, _run_context(Talk.SHOPKEEPER))
			_after_talk = "shop"
		Sanctum.CARD_READER:
			_talk(Talk.CARD_READER, _run_context(Talk.CARD_READER))
		Sanctum.MIRROR:
			roster.open(prof, device)
			roster_open = true
			Sfx.play("page_turn")
		Sanctum.DEEDS:
			deeds_book.open(prof)
			deeds_open = true
			Sfx.play("page_turn")
		Sanctum.CAT:
			_cat_pet = 1.5
			Sfx.play("heal", -6.0, 0.7)
			fx.text(Sanctum.THINGS[i][1] + Vector2(0, -10), "PRRR", Color("ff8af0"), 1.2)
			if prof.find_secret("cat"):
				Save.write()


## The context a chat is picked in: what the run before it was, the step being played and what is new.
func talk_context(speaker: int, extra: Dictionary) -> Dictionary:
	var prof: Profile = Save.profile
	var ctx := extra.duplicate()
	var seal := int(ctx.get("seal", Net.seal))
	ctx.seal = seal
	if prof.runs == 0 and prof.first_time(Profile.first_key(speaker)):
		ctx.first = true
		Save.write() # the greeting is told once across launches (a scripted run writes nothing)
	if bool(_new_card.get(speaker, false)):
		ctx.new_card = true
		_new_card[speaker] = false
	var ap_key := "%d/apprentice" % speaker
	if seal == Seals.MIN and not G.talk_seen.has(ap_key):
		ctx.apprentice = true
		G.talk_seen[ap_key] = true
	ctx.last = int(G.talk_last.get(speaker, -1))
	return ctx


## What the run that just ended adds to a chat, the first time this speaker talks after it.
func _run_context(speaker: int) -> Dictionary:
	if _ran_run.is_empty() or _ran.has(speaker) and speaker != Talk.MORVANE:
		return {}
	_ran[speaker] = true
	return {"result": _ran_run.get("result", ""), "act": int(_ran_run.get("act", -1)), "seal": int(_ran_run.get("seal", 0))}


func _talk(speaker: int, extra: Dictionary) -> void:
	var line := Talk.pick(speaker, talk_context(speaker, extra), _rng)
	if line.is_empty():
		return
	G.talk_last[speaker] = int(line.id)
	dlg.open(line)
	Sfx.play("page_turn", -6.0, 1.2)


func _open_card(idx: int, line: String) -> void:
	var first := Save.profile.add_card(idx)
	if first:
		for k: int in _new_card:
			_new_card[k] = true
	Save.write()
	_deck = {"idx": idx, "t": 0.0, "first": first}
	Sfx.play("card_deal")
	Sfx.play("wave_clear", -4.0, 1.4)
	_say(line)


func _go_play() -> void:
	G.goto_title_lobby(device)


func _unhandled_input(event: InputEvent) -> void:
	if dlg.active:
		if dlg.handle(event) and _after_talk == "shop":
			_after_talk = ""
			G.title_shop = true
			G.title_lobby_device = device # carried through the shop; the title hands it back on its way out
			G.goto_title()
		elif not dlg.active:
			_after_talk = ""
		return
	if album_open:
		if album.handle(event):
			album_open = false
		return
	if roster_open:
		if roster.handle(event):
			roster_open = false
		return
	if deeds_open:
		if deeds_book.handle(event):
			deeds_open = false
		return
	if not _deck.is_empty():
		if _deck.t > 0.8 and (PlayerInput.confirm_device(event) != -99 or PlayerInput.back_pressed(event)):
			_deck = {}
		return
	if PlayerInput.back_pressed(event):
		# Only the device that walks the hub may leave it (Esc is the keyboard's).
		if PlayerInput.key_device(event) != device and not (event is InputEventKey and device == G.DEV_KB2):
			return
		Sfx.play("menu_select")
		G.goto_title()
		return
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if PlayerInput.confirm_device(event) != -99 or (tap and room.near_thing() >= 0):
		room.use()
	# Pads use A as the Nova in a run; here it is the use button too (confirm_device covers it).


# ============================================================== DRAWING ===
func _draw() -> void:
	var off := Vector2(_rng.randf_range(-shake, shake), _rng.randf_range(-shake, shake)).round() if shake > 0.5 else Vector2.ZERO
	draw_set_transform(off)
	_draw_room()
	_draw_things()
	_draw_cauldron()
	_draw_pots()
	_draw_wizard()
	for s: Array in _shards:
		draw_rect(Rect2((s[0] as Vector2).floor(), Vector2(2, 2)), s[3])
	# The prompt goes over everything in the room, so pots and the wizard never cover it.
	if not _prompt.is_empty():
		PixelFont.draw_centered(self, _prompt[0], _prompt[1].x, _prompt[1].y, 1, Occult.GOLD, Occult.INK)
	draw_set_transform(Vector2.ZERO)
	_draw_hud()
	if not _deck.is_empty():
		_draw_deck()
	if album_open:
		album.draw(self, t)
	if roster_open:
		roster.draw(self, t)
	if deeds_open:
		deeds_book.draw(self, t)
	dlg.draw(self, t)
	if _leaving >= 0.0:
		draw_rect(Rect2(0, 0, 480, 270), Color(0.6, 0.4, 1.0, clampf(_leaving / 0.8, 0.0, 1.0)))


func _draw_room() -> void:
	draw_texture(_room_tex, Vector2.ZERO)
	if room.crack_open:
		draw_texture(_alcove_tex, Vector2(SanctumArt.PATCH.position))
	# Candle flames on every baked wick: a flickering orange tongue round a bright core.
	for c: Vector2 in _candles():
		var fl := int(1.5 + 1.5 * sin(t * 13.0 + c.x * 1.7))
		draw_rect(Rect2(c + Vector2(0, -2 - fl), Vector2(1, 3 + fl)), Color("ff8a2a"))
		draw_rect(Rect2(c + Vector2(0, -1), Vector2(1, 2)), Color("ffe07a"))
		if fl >= 2:
			draw_rect(Rect2(c + Vector2(0, -3 - fl), Vector2(1, 1)), Color("ff8a2a", 0.5))


## Every lit wick; the one in the alcove only once the wall is open.
func _candles() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for c: Vector2 in SanctumArt.flames():
		if room.crack_open or not Sanctum.ALCOVE.has_point(c):
			out.append(c)
	return out


func _draw_things() -> void:
	_prompt = []
	var near := room.near_thing()
	for i: int in range(Sanctum.THINGS.size()):
		var p: Vector2 = Sanctum.THINGS[i][1]
		match i:
			Sanctum.PORTAL:
				for k: int in range(3):
					draw_arc(p, 14.0 - k * 4.0, t * (1.5 + k), t * (1.5 + k) + TAU * 0.8, 24, Color("b07bff", 0.8 - k * 0.2), 1.0)
				for k: int in range(8):
					var a := -t * 0.8 + k * TAU / 8.0
					Occult.rune(self, p + Vector2.from_angle(a) * 19.0 - Vector2(2, 2), k, Color("ff4df2", 0.7))
			Sanctum.ALTAR:
				# The card floats over the pedestal and turns its glow on the stone below.
				var bob := roundf(sin(t * 2.0) * 2.0)
				draw_rect(Rect2(p + Vector2(-4 + absf(bob), -13), Vector2(8 - absf(bob) * 2.0, 1)), Color(0, 0, 0, 0.35))
				SanctumArt.draw(self, "card", p + Vector2(0, -20 + bob))
				if int(t * 3.0) % 4 == 0:
					draw_rect(Rect2(p + Vector2(3, -32 + bob), Vector2(1, 1)), Color("fff6c0"))
			Sanctum.RELIQUARY:
				# A glint that runs across the gold lock.
				var g := fmod(t * 0.7, 3.0)
				if g < 0.25:
					draw_rect(Rect2(p + Vector2(-1 + int(g * 12.0) % 3, -9), Vector2(1, 1)), Color("fff6c0"))
			Sanctum.MUSIC:
				# A note drifting up out of the horn.
				var np := (p + Vector2(-2, -38 - fmod(t * 6.0, 12.0))).floor()
				var na := 1.0 - fmod(t * 6.0, 12.0) / 12.0
				draw_rect(Rect2(np, Vector2(2, 2)), Color("ffd94d", na))
				draw_rect(Rect2(np + Vector2(2, -5), Vector2(1, 6)), Color("ffd94d", na))
				draw_rect(Rect2(np + Vector2(3, -5), Vector2(2, 1)), Color("ffd94d", na))
			Sanctum.WELL:
				# Ripples on the water.
				var w := p + Vector2(0, -6)
				var rr := fmod(t * 3.0, 4.0)
				for k: int in range(16):
					var a := k * TAU / 16.0
					var q := (w + Vector2(cos(a) * (3.0 + rr * 1.6), sin(a) * (1.0 + rr * 0.6))).floor()
					draw_rect(Rect2(q, Vector2(1, 1)), Color("8bdcff", 0.5 - rr * 0.1))
				if int(t * 2.0) % 3 == 0:
					draw_rect(Rect2(w + Vector2(-5, -1), Vector2(2, 1)), Color("c8f0ff", 0.6))
			Sanctum.MIRROR:
				_draw_mirror(p)
			Sanctum.DEEDS:
				_draw_lectern(p)
			Sanctum.CAT:
				if not room.crack_open:
					continue
				# Asleep: eyes shut, a tail that twitches. Open (green) now and then, pink when petted.
				var head := Vector2(411, 37) # where SanctumArt bakes the cat
				var awake := _cat_pet > 0.0 or int(t * 0.5) % 7 == 3
				var eye := Color("ff8af0") if _cat_pet > 0.0 else Color("8bff9e")
				for ex: int in [11, 14]:
					if awake:
						draw_rect(Rect2(head + Vector2(ex + 1, 4), Vector2(1, 1)), eye)
					else:
						draw_rect(Rect2(head + Vector2(ex, 4), Vector2(2, 1)), Color("0e0a14"))
				var tail := int(roundf(sin(t * 1.6) * 1.5))
				draw_rect(Rect2(head + Vector2(-2, 7 + tail), Vector2(2, 1)), Color("1a0f24"))
				draw_rect(Rect2(head + Vector2(-3, 6 + tail * 2), Vector2(1, 2)), Color("1a0f24"))
				draw_rect(Rect2(head + Vector2(-3, 6 + tail * 2), Vector2(1, 1)), Color("5a4e74"))
				if not awake and int(t) % 4 < 2:
					var zt := fmod(t, 2.0)
					PixelFont.draw(self, "z", head + Vector2(17 + zt * 3.0, -2 - zt * 5.0), 1, Color("c9b8ff", 1.0 - zt / 2.0), Occult.INK)
		if i == Sanctum.SHOPKEEPER or i == Sanctum.CARD_READER:
			_draw_npc(i)
		if i == near and not dlg.active:
			var prompt: String = String(Sanctum.THINGS[i][2])
			if i == Sanctum.RELIQUARY:
				prompt = prompt % Sanctum.DECK_COST
			var key := "ENTER" if device == G.DEV_KBM else "A"
			var text := key + ": " + prompt
			var half := PixelFont.text_width(text) / 2.0
			var px := clampf(p.x, half + 4.0, 476.0 - half)
			var py := maxf(p.y - (44.0 if i >= Sanctum.SHOPKEEPER else 34.0), 64.0) + sin(t * 4.0)
			_prompt = [text, Vector2(px, py)]


## The lectern of the Book of Deeds: a dark wooden stand with a slanted top and a gold-edged book on it, a page
## corner that lifts now and then. A stand-in drawn with rects until its picture comes from a file.
func _draw_lectern(p: Vector2) -> void:
	if Still.draw_static(self, Still.HUB_LECTERN, p + Still.HUB_GROUND):
		return
	var wood := Color("2a1a38")
	var edge := Color("5a4e74")
	draw_rect(Rect2(p + Vector2(-7, -1), Vector2(14, 3)), Color("1a0f24")) # foot
	draw_rect(Rect2(p + Vector2(-7, -1), Vector2(14, 1)), edge)
	draw_rect(Rect2(p + Vector2(-2, -13), Vector2(4, 12)), wood) # stem
	draw_rect(Rect2(p + Vector2(-2, -13), Vector2(1, 12)), edge)
	draw_rect(Rect2(p + Vector2(-8, -18), Vector2(16, 5)), wood) # slanted top
	draw_rect(Rect2(p + Vector2(-8, -18), Vector2(16, 1)), edge)
	draw_rect(Rect2(p + Vector2(-6, -24), Vector2(12, 7)), Occult.GOLD) # the book
	draw_rect(Rect2(p + Vector2(-5, -23), Vector2(10, 5)), Color("e8dcc0"))
	draw_rect(Rect2(p + Vector2(0, -23), Vector2(1, 5)), Color("b8a8d8"))
	if int(t * 1.5) % 5 == 0:
		draw_rect(Rect2(p + Vector2(3, -25), Vector2(3, 2)), Color("e8dcc0"))


## The mirror: a tall dark oval glass in a gold frame on two feet, with a slow sheen across the glass. A stand-in
## drawn with rects until its picture comes from a file.
func _draw_mirror(p: Vector2) -> void:
	if Still.draw_static(self, Still.HUB_MIRROR, p + Still.HUB_GROUND):
		return
	var cy := p.y - 22.0
	draw_rect(Rect2(p + Vector2(-8, -2), Vector2(16, 3)), Color("1a0f24"))
	draw_rect(Rect2(p + Vector2(-8, -2), Vector2(16, 1)), Color("5a4e74"))
	for k: int in range(2):
		var half := 14.0 if k == 0 else 12.0
		var wide := 9.0 if k == 0 else 7.0
		var col := Occult.GOLD if k == 0 else Color("0a0614")
		for row: int in range(int(-half), int(half) + 1):
			var w := roundf(wide * sqrt(maxf(0.0, 1.0 - pow(float(row) / half, 2.0))))
			if k == 1 and w > 1.0:
				col = Color("1b1236").lerp(Color("4a3a8a"), clampf(0.5 + float(row) / half * 0.5, 0.0, 1.0) * 0.5)
			draw_rect(Rect2(p.x - w, cy + row, w * 2.0, 1.0), col)
	var sheen := fmod(t * 0.5, 2.0) - 0.5
	if sheen > 0.0 and sheen < 1.0:
		var sy := cy - 10.0 + sheen * 20.0
		draw_rect(Rect2(p.x - 3, sy, 1, 2), Color(1, 1, 1, 0.5))
	draw_rect(Rect2(p.x - 1, cy - 14 - 3, 2, 2), Occult.GOLD)


## A talker's spot: a small framed portrait on a plinth with the name below (a plain plate where there is no picture).
func _draw_npc(i: int) -> void:
	var p: Vector2 = Sanctum.THINGS[i][1]
	var key := String(Sanctum.THINGS[i][0])
	var frame := Rect2((p + Vector2(-13, -34)).floor(), Vector2(26, 30))
	if not Still.draw_static(self, Still.HUB_PLINTH, p + Still.PLINTH_GROUND):
		draw_rect(Rect2(p + Vector2(-9, -3), Vector2(18, 6)), Color("1a0f24"))
		draw_rect(Rect2(p + Vector2(-9, -3), Vector2(18, 1)), Color("5a4e74"))
	draw_rect(frame.grow(1), Occult.GOLD)
	draw_rect(frame, Color("0e0a14"))
	if not Art.draw(self, DialogueBox.GROUP, key, frame):
		DialogueBox.draw_stand_in(self, frame, "")
	var nm: String = Talk.SPEAKERS[Talk.SHOPKEEPER if i == Sanctum.SHOPKEEPER else Talk.CARD_READER][0]
	if not dlg.active: # the talk's portrait panel stands over the left name
		PixelFont.draw_centered(self, nm, p.x, p.y + 6, 1, Color("c9b8ff"), Occult.INK)


## The cauldron by the front wall bubbles away.
func _draw_cauldron() -> void:
	for k: int in range(3):
		var ph := fmod(t * 0.9 + k * 0.37, 1.0)
		var bx := CAULDRON.x - 6.0 + k * 5.0 + sin(t * 3.0 + k) * 1.0
		var by := CAULDRON.y - 11.0 - ph * 10.0
		draw_rect(Rect2(Vector2(bx, by).floor(), Vector2(1, 1)), Color("b8ff9a", 1.0 - ph))
	if int(t * 4.0) % 3 == 0:
		draw_rect(Rect2(CAULDRON + Vector2(2, -11), Vector2(2, 1)), Color("b8ff9a"))


func _draw_pots() -> void:
	for i: int in range(Sanctum.POTS.size()):
		var p: Vector2 = Sanctum.POTS[i]
		if room.broken[i]:
			SanctumArt.draw(self, "urn_broken", p + Vector2(0, 3))
			continue
		draw_rect(Rect2(p + Vector2(-4, 1), Vector2(9, 2)), Color(0.02, 0.0, 0.06, 0.4))
		SanctumArt.draw(self, ["urn_a", "urn_b", "urn_c"][i % 3], p + Vector2(0, 2))


func _draw_wizard() -> void:
	var f := room.facing
	var dirkey := "down"
	var flip := false
	if absf(f.y) > absf(f.x) * 1.1:
		dirkey = "up" if f.y < 0 else "down"
	else:
		dirkey = "side"
		flip = f.x < 0
	var fr := "a" if not room.moving or int(room.walk_t) % 2 == 0 else "b"
	var key := "wiz%d_%s_%s" % [G.wizard_of(0), dirkey, fr]
	var c := Color(0.05, 0.0, 0.1, 0.45)
	draw_rect(Rect2(room.pos + Vector2(-4, -1), Vector2(8, 3)), c)
	if _leaving < 0.0:
		var still := Still.hero_name(Save.profile.active_hero().cls, false, Save.profile.active_hero().race)
		if still.is_empty() or not Still.draw(self, still, room.pos + Vector2(0, 1), -1 if f.x < 0.0 else 1, t, room.moving):
			Sprites.draw_at(self, key, room.pos + Vector2(0, 1), flip)


## A soft light: stacked discs, each fainter and wider, so the edge fades instead of showing a ring.
func _light(at: Vector2, radius: float, c: Color) -> void:
	for k: int in range(5):
		glow.draw_circle(at, radius * (0.35 + 0.65 * k / 4.0), Color(c, c.a * 0.3))


func _draw_glow() -> void:
	for c: Vector2 in _candles():
		_light(c, 12.0 + 1.5 * sin(t * 9.0 + c.y), Color(1.0, 0.6, 0.2, 0.08))
	var portal: Vector2 = Sanctum.THINGS[Sanctum.PORTAL][1]
	_light(portal, 30.0 + 2.0 * sin(t * 3.0), Color(0.6, 0.3, 1.0, 0.16))
	_light(Vector2(SanctumArt.MOON), 10.0, Color(0.9, 0.9, 1.0, 0.1))
	var altar: Vector2 = Sanctum.THINGS[Sanctum.ALTAR][1]
	_light(altar + Vector2(0, -26), 14.0, Color(1.0, 0.85, 0.3, 0.12))
	var rel: Vector2 = Sanctum.THINGS[Sanctum.RELIQUARY][1]
	_light(rel + Vector2(0, -4), 16.0, Color(0.8, 0.3, 1.0, 0.12))
	var well: Vector2 = Sanctum.THINGS[Sanctum.WELL][1]
	_light(well + Vector2(0, -6), 12.0, Color(0.3, 0.7, 1.0, 0.08))
	_light(CAULDRON + Vector2(0, -12), 12.0 + sin(t * 2.3), Color(0.3, 1.0, 0.4, 0.08))


func _draw_hud() -> void:
	var prof: Profile = Save.profile
	if not Still.draw_icon(self, Still.HUD_ICONS[0], CRYSTAL_ICON):
		Sprites.draw_at(self, "gem", Vector2(14, 268))
	PixelFont.draw(self, ("%d CRYSTAL" if prof.crystals == 1 else "%d CRYSTALS") % prof.crystals, Vector2(22, 261), 1, Color("8bdcff"), Occult.INK)
	PixelFont.draw(self, "CARDS %d/%d" % [prof.cards_owned(), Cards.count()], Vector2(110, 261), 1, Occult.GOLD, Occult.INK)
	PixelFont.draw(self, "SECRETS %d/%d" % [Secrets.found(prof), Secrets.count()], Vector2(190, 261), 1, Color("ff8af0"), Occult.INK)
	var keys := "WASD WALK  ENTER USE  ESC TITLE" if device == G.DEV_KBM else "STICK WALK  A USE  B TITLE"
	PixelFont.draw(self, keys, Vector2(466 - PixelFont.text_width(keys), 261), 1, Color(1, 1, 1, 0.4), Occult.INK)
	if message_t > 0.0:
		var a := clampf(message_t * 2.0, 0.0, 1.0)
		PixelFont.draw_centered(self, message, 240, 251, 1, Color(Occult.BONE, a), Occult.INK)


func _draw_deck() -> void:
	var tt: float = _deck.t
	draw_rect(Rect2(0, 0, 480, 270), Color(0.02, 0.0, 0.06, 0.6))
	var flip := clampf(tt / 0.6, 0.0, 1.0)
	var w := 76.0 * absf(1.0 - flip * 2.0)
	var r := Rect2((Vector2(240, 128) - Vector2(w / 2.0, 56)).floor(), Vector2(maxf(floorf(w), 1.0), 112))
	if flip < 0.5:
		TarotArt.draw_back(self, r)
	else:
		MonsterCard.draw(self, r, int(_deck.idx), true, t, 1.0)
	PixelFont.draw_centered(self, Cards.card_name(int(_deck.idx)), 240, r.end.y + 6, 1, Occult.GOLD, Occult.INK)
	PixelFont.draw_centered(self, "NEW TO YOUR COLLECTION" if _deck.first else "ANOTHER FOR THE ALBUM", 240, r.end.y + 16, 1,
		Color("c9b8ff"), Occult.INK)

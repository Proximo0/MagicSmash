class_name TownScreen
extends UiScreen
## The town: the gateway's room of up to 100 heroes, 10 snapshots a second (id, x, y, direction), drawn from above
## with the camera on your hero. Walk with the move keys (the direction goes to the gateway when it changes),
## talk with Enter, use a station with F or a click when you stand at it. Stations and the plaza are TownMap's:
## the server knows only where heroes are.

## Screen px per world px: 2 on the shell's 960 x 540 canvas is the field's zoom 1 on its 480 x 270 one, so the
## town is seen from the same height as the fields (Curtis, 25 Nov: "more similar to the fields in the perspective").
const ZOOM: float = 2.0
const SNAP_S: float = 0.1
## A hero's height for names and speech above her (world px): the field's walk strips at their own scale.
const HERO_BOX: float = 40.0
## World px per px of a station's picture: the heroes' walk-strip scale in the field, so every pixel in the town is
## the same size and a building stands as tall against a hero as the art was made to.
const PIC_K: float = 0.4667
## A picture's bottom edge lies this far south of the station's point (world px); the hearth's likewise.
const PIC_BASE: float = 24.0
const HEARTH_BASE: float = 34.0
## A station name that would sit above this y (under the place title) is drawn here instead.
const TITLE_BAR_Y: float = 38.0
const CHAT_LINES: int = 7
const CHAT_SHOW_S: float = 25.0
const SAY_S: float = 6.0
const CHAT_MAX: int = 200
const STATION_PANELS: Dictionary = {
	"bank": "BankPanel", "smith": "SmithPanel", "merchants": "MerchantPanel", "reader": "ReaderPanel",
	"trainer": "TrainerPanel", "gate": "GatePanel", "market": "MarketPanel", "post": "PostPanel",
	"trade": "TradePanel", "board": "BoardPanel"}

var members: Dictionary = {}
var me: int = -1
var size_px: float = 4096.0
var chat_log: Array[Dictionary] = []
var typing: bool = false
var chat_text: String = ""
var snapshots: int = 0
var last_dir: int = -1
var cam: Vector2 = TownMap.CENTRE
## Screenshots: look at a place instead of following the hero (x < 0: off).
var look_at: Vector2 = Vector2(-1, -1)
var _clock: float = 0.0
var _prompt: Dictionary = {}
## The stations of the place she is in (TownMap's in the plaza; doors and boards elsewhere: HomeMap.stations_for).
var stations: Array[Dictionary] = []
## Which floor of her house is drawn (0 or 1).
var floor_no: int = 0
var _rest_poll: float = 0.0
## The station she was sent walking to by a click (the walk ends at its door, which opens).
var _walk_to: String = ""
## The plaza's cobbles (tools/ground/ground.py `town`), a child drawn behind this screen's own drawing.
var _soil: FieldGround = null


func opened() -> void:
	modal = false
	nav_enabled = false
	# Crisp pixels, as the field's integer-scaled canvas draws them.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Sfx.play("bell")
	var t: Dictionary = shell.town
	stations = HomeMap.stations_for(shell.place, shell.street_plots)
	size_px = float(t.get("size", 4096))
	if int(shell.place[0]) == HomeMap.PLAZA:
		_soil = FieldGround.new()
		_soil.show_behind_parent = true
		add_child(_soil)
		_soil.set_town(size_px)
		_soil.scale = Vector2(ZOOM, ZOOM)
		_soil.set_scale_px(ZOOM)
	me = int(t.get("me", -1))
	for m in t.get("members", []):
		_add_member(m)
	# Everyone starts in the middle until the first snapshot (arrivals scatter 200 px round it).
	if members.has(me):
		cam = members[me]["to"]


func _add_member(m: Dictionary) -> void:
	var id: int = int(m["id"])
	var p: Vector2 = TownMap.CENTRE
	members[id] = {"name": m["name"], "class": int(m["class"]), "race": int(m["race"]), "level": int(m["level"]), "look": int(m["look"]),
		"from": p, "to": p, "t0": _clock, "dir": 0, "say": "", "say_until": 0.0}


func shown(id: int) -> Vector2:
	var m: Dictionary = members.get(id, {})
	if m.is_empty():
		return TownMap.CENTRE
	return (m["from"] as Vector2).lerp(m["to"], clampf((_clock - float(m["t0"])) / SNAP_S, 0.0, 1.0))


## The gateway's pushes: snapshots, chat lines, arrivals and departures.
func on_push(msg: Dictionary) -> void:
	match int(msg["t"]):
		GwWire.P_TOWN_SNAPSHOT:
			snapshots += 1
			for row in msg["at"]:
				var id: int = int(row[0])
				if not members.has(id):
					continue
				var m: Dictionary = members[id]
				m["from"] = shown(id)
				m["to"] = Vector2(float(row[1]), float(row[2]))
				m["t0"] = _clock
				m["dir"] = int(row[3])
		GwWire.P_TOWN_CHAT:
			var from: int = int(msg["from"])
			chat_log.append({"name": String(msg["name"]), "text": String(msg["text"]), "at": _clock, "mine": from == me})
			if chat_log.size() > 60:
				chat_log.pop_front()
			if members.has(from):
				members[from]["say"] = String(msg["text"])
				members[from]["say_until"] = _clock + SAY_S
		GwWire.P_TOWN_ARRIVE:
			_add_member(msg["member"])
		GwWire.P_TOWN_DEPART:
			members.erase(int(msg["id"]))


func _process(delta: float) -> void:
	super(delta)
	_clock += delta
	if look_at.x >= 0.0:
		cam = look_at
	elif members.has(me):
		cam = cam.lerp(shown(me), 1.0 - exp(-delta * 12.0))
	_send_direction()
	_prompt = TownMap.near(shown(me), TownMap.USE_PX, stations) if members.has(me) else {}
	_poll_rest(delta)
	if _soil != null:
		_soil.position = w2s(Vector2.ZERO)


## True while the way out of town is lit: a hero who has not yet been out on a field and is still level 1, on the
## plaza. The gate pulses and an arrow at the screen's edge points to it; a click on either walks her there.
func gate_lit() -> bool:
	return int(shell.place[0]) == HomeMap.PLAZA and shell.last_outing.is_empty() and int(shell.hero.get("level", 1)) <= 1 and not TownMap.station("gate", stations).is_empty()


## The walk a click on a far station starts: a heading each frame toward it, until a key is held (hers wins) or
## she is at its door, where it opens.
func _walk_dir() -> int:
	var s: Dictionary = TownMap.station(_walk_to, stations)
	if s.is_empty() or not members.has(me):
		_walk_to = ""
		return 0
	var d: Vector2 = (s["at"] as Vector2) - shown(me)
	if d.length() <= TownMap.USE_PX * 0.6:
		var sid: String = _walk_to
		_walk_to = ""
		open_station(sid)
		return 0
	const DEAD: float = 24.0
	return RealmClient._dir_code(0 if absf(d.x) < DEAD else int(signf(d.x)), 0 if absf(d.y) < DEAD else int(signf(d.y)))


func _send_direction() -> void:
	var d: int = 0
	if not typing and shell.top() == self:
		var dx: int = int(ShellSettings.held("right")) - int(ShellSettings.held("left"))
		var dy: int = int(ShellSettings.held("down")) - int(ShellSettings.held("up"))
		d = RealmClient._dir_code(dx, dy)
		if d != 0:
			_walk_to = ""
		elif not _walk_to.is_empty():
			d = _walk_dir()
	elif not _walk_to.is_empty():
		_walk_to = ""
	if d != last_dir:
		last_dir = d
		shell.link.send_only(GwWire.town_input(d))


# ---- drawing

func w2s(p: Vector2) -> Vector2:
	return (p - cam) * ZOOM + Vector2(UiKit.W, UiKit.H) / 2.0


func paint() -> void:
	_ground()
	HomeDraw.props(self)
	_world()
	_station_labels()
	_hero_labels()
	_hud()
	_chat()
	_minimap()


func _hash(x: int, y: int) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663)
	return absi(h) & 0xFFFF


## True when the plaza stands on its cobble tiles (they are there and loaded); else the flat tiles below are drawn.
func _cobbled() -> bool:
	return _soil != null and _soil.field == FieldGround.TOWN and int(shell.place[0]) == HomeMap.PLAZA


func _ground() -> void:
	if _cobbled():
		# The plaza's edge over the cobbles, then the rim of the square.
		draw_arc(w2s(TownMap.CENTRE), TownMap.PLAZA_R * ZOOM, 0.0, TAU, 160, Color(0, 0, 0, 0.5), 6.0)
		draw_arc(w2s(TownMap.CENTRE), (TownMap.PLAZA_R - 5.0) * ZOOM, 0.0, TAU, 160, Color(UiKit.GOLD_DIM, 0.3), 1.5)
		draw_rect(Rect2(w2s(Vector2.ZERO), Vector2(size_px, size_px) * ZOOM), UiKit.BLOOD, false, 3.0)
		_hearth_glow()
		return
	draw_rect(Rect2(0, 0, UiKit.W, UiKit.H), Color(0.04, 0.035, 0.045))
	var half := Vector2(UiKit.W, UiKit.H) / (2.0 * ZOOM)
	var tile: int = 64
	var x0: int = int(floor((cam.x - half.x) / tile))
	var x1: int = int(ceil((cam.x + half.x) / tile))
	var y0: int = int(floor((cam.y - half.y) / tile))
	var y1: int = int(ceil((cam.y + half.y) / tile))
	var ts: float = tile * ZOOM
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var wp := Vector2(tx * tile + tile / 2.0, ty * tile + tile / 2.0)
			if wp.x < 0 or wp.y < 0 or wp.x > size_px or wp.y > size_px:
				continue
			var h: int = _hash(tx, ty)
			var tint: Variant = HomeDraw.floor_tint(shell.place, wp)
			var inside: bool = wp.distance_to(TownMap.CENTRE) < TownMap.PLAZA_R if tint == null else false
			var v: float = float(h % 100) / 100.0 * 0.03
			var col: Color = Color(0.17 + v, 0.15 + v, 0.15 + v) if inside else Color(0.08 + v, 0.075 + v, 0.07 + v)
			if tint != null:
				var tc: Color = tint
				col = Color(tc.r + v, tc.g + v, tc.b + v)
			var r := Rect2(w2s(Vector2(tx * tile, ty * tile)), Vector2(ts, ts))
			draw_rect(r, col)
			if inside:
				draw_rect(r, Color(0, 0, 0, 0.35), false, 1.0)
				var cx: float = r.position.x + ts * (0.35 + float(h % 30) / 100.0)
				var cy: float = r.position.y + ts * (0.35 + float((h / 31) % 30) / 100.0)
				draw_line(Vector2(cx, r.position.y), Vector2(cx, r.end.y), Color(0, 0, 0, 0.25), 1.0)
				draw_line(Vector2(r.position.x, cy), Vector2(r.end.x, cy), Color(0, 0, 0, 0.25), 1.0)
			elif h % 11 == 0:
				# Dead bracken and a standing stone here and there outside the plaza.
				var c: Vector2 = r.position + Vector2(h % 37, (h / 7) % 37) * ZOOM
				draw_line(c, c + Vector2(3, -12) * ZOOM, Color(0.16, 0.13, 0.1), 1.0)
				draw_line(c, c + Vector2(-4, -9) * ZOOM, Color(0.16, 0.13, 0.1), 1.0)
	# The rim of the square.
	var rim := Rect2(w2s(Vector2.ZERO), Vector2(size_px, size_px) * ZOOM)
	draw_rect(rim, UiKit.BLOOD, false, 3.0)
	# The hearth in the middle of the plaza.
	if int(shell.place[0]) != HomeMap.PLAZA:
		return
	_hearth_glow()


## The hearth's glow on the cobbles, under everything.
func _hearth_glow() -> void:
	var hc: Vector2 = w2s(TownMap.CENTRE)
	var fl: float = 0.85 + 0.15 * sin(_clock * 8.0)
	if UiArt.has_file("town_hearth"):
		draw_circle(hc, 150.0 * ZOOM * fl, Color(0.9, 0.5, 0.1, 0.05))
		draw_circle(hc, 95.0 * ZOOM * fl, Color(0.9, 0.5, 0.1, 0.06))
	else:
		draw_circle(hc, 44.0 * ZOOM * fl, Color(0.9, 0.5, 0.1, 0.07))


## The hearth itself: its picture on the plaza's middle, else a few circles.
func _hearth_pic() -> void:
	var hc: Vector2 = w2s(TownMap.CENTRE)
	var fl: float = 0.85 + 0.15 * sin(_clock * 8.0)
	if UiArt.has_file("town_hearth"):
		var tex: Texture2D = UiArt.texture("town_hearth", 96)
		var hs: Vector2 = tex.get_size() * PIC_K * ZOOM
		draw_texture_rect(tex, Rect2(Vector2(hc.x - hs.x / 2.0, hc.y + HEARTH_BASE * ZOOM - hs.y), hs), false)
		return
	draw_circle(hc, 20.0 * ZOOM, Color(0.1, 0.08, 0.08))
	draw_arc(hc, 20.0 * ZOOM, 0.0, TAU, 24, UiKit.GOLD_DIM, 1.5)
	draw_colored_polygon(PackedVector2Array([hc + Vector2(-9, 4), hc + Vector2(0, -26 * fl), hc + Vector2(9, 4)]), Color(0.85, 0.32, 0.08, 0.9))
	draw_colored_polygon(PackedVector2Array([hc + Vector2(-4, 4), hc + Vector2(0, -12 * fl), hc + Vector2(4, 4)]), Color(1.0, 0.8, 0.3))


## Stations, the hearth, the fires to sit at and the heroes in one list by ground y: whoever stands further
## north is drawn first, so a hero behind a building is hidden by it and one in front is drawn over it.
func _world() -> void:
	var plaza: bool = int(shell.place[0]) == HomeMap.PLAZA
	var items: Array = []
	for s in stations:
		var picture: bool = UiArt.has_file("town_" + String(s["id"]))
		items.append([(s["at"] as Vector2).y + (PIC_BASE if picture else 0.0), 0, s])
	if plaza:
		items.append([TownMap.CENTRE.y + HEARTH_BASE, 1, null])
	var fires: Array[Vector2] = HomeMap.fires_here(shell.place, shell.house.get("items", []))
	for f in fires:
		items.append([f.y + 8.0, 2, f])
	for th in HomeDraw.depth_things(self):
		items.append([float(th[0]), 4, th[1]])
	for id in members.keys():
		items.append([shown(id).y, 3, id])
	items.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for it in items:
		match int(it[1]):
			0:
				_station(it[2])
			1:
				_hearth_pic()
			2:
				HomeDraw.fire_picture(self, it[2])
			3:
				_hero(int(it[2]))
			4:
				HomeDraw.thing_picture(self, it[2])


func _station_rect(s: Dictionary) -> Rect2:
	var c: Vector2 = w2s(s["at"])
	if UiArt.has_file("town_" + String(s["id"])):
		var ps: Vector2 = UiArt.texture("town_" + String(s["id"]), 96).get_size() * PIC_K * ZOOM
		return Rect2(Vector2(c.x - ps.x / 2.0, c.y + PIC_BASE * ZOOM - ps.y), ps)
	var sz: Vector2 = (s["size"] as Vector2) * ZOOM
	return Rect2(c - sz / 2.0, sz)


func _station(s: Dictionary) -> void:
	var c: Vector2 = w2s(s["at"])
	if c.x < -400 or c.x > UiKit.W + 400 or c.y < -400 or c.y > UiKit.H + 400:
		return
	var r: Rect2 = _station_rect(s)
	var id: String = "st:" + String(s["id"])
	if s["id"] == "gate" and gate_lit():
		UiKit.glow(self, r, _clock)
	var near_it: bool = not _prompt.is_empty() and _prompt["id"] == s["id"]
	hit(id, r)
	if UiArt.has_file("town_" + String(s["id"])):
		# The picture at its own size (a pixel as big as a hero's), standing on the station's point.
		draw_texture_rect(UiArt.texture("town_" + String(s["id"]), 96), r, false, Color(1.3, 1.25, 1.15) if (near_it or hover_id == id) else Color.WHITE)
		return
	var col: Color = s["col"]
	draw_rect(r, col.darkened(0.55))
	draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.34)), col)
	draw_rect(r, UiKit.GOLD if (near_it or hover_id == id) else UiKit.GOLD_DIM, false, 2.0)
	UiKit.rune(self, c - Vector2(12, 14), stations.find(s) + 2, 24.0, Color(UiKit.GOLD, 0.7), 1.5)
	if s["id"] == "gate":
		for k in 6:
			var gx: float = r.position.x + (k + 0.5) * r.size.x / 6.0
			draw_rect(Rect2(gx - 9, r.end.y - 30, 18, 30), Color(0.02, 0.02, 0.03))
			draw_arc(Vector2(gx, r.end.y - 30), 9.0, PI, TAU, 10, UiKit.GOLD_DIM, 1.0)


## Names and the use prompt, over everything. A name that would fall under the title bar at the top goes below it.
func _station_labels() -> void:
	for s in stations:
		var c: Vector2 = w2s(s["at"])
		if c.x < -400 or c.x > UiKit.W + 400 or c.y < -400 or c.y > UiKit.H + 400:
			continue
		var r: Rect2 = _station_rect(s)
		var near_it: bool = not _prompt.is_empty() and _prompt["id"] == s["id"]
		var ly: float = r.position.y - 20.0
		if absf(c.x - UiKit.W / 2.0) < 150.0 and ly < TITLE_BAR_Y:
			ly = TITLE_BAR_Y
		UiKit.text(self, Vector2(c.x, ly), String(s["name"]), 14, UiKit.GOLD if near_it else UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
		if near_it:
			UiKit.text(self, Vector2(c.x, r.end.y + 6), "[%s]  %s" % [ShellSettings.key_label(ShellSettings.key("interact")), String(s["what"])], 12, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)


## The field's hero pictures (walk, attack strips) by class * 4 + race, loaded once.
var _hero_art: Dictionary = {}


func _hero_entry(cls: int, race: int) -> Dictionary:
	var k: int = cls * 4 + race
	if not _hero_art.has(k):
		_hero_art[k] = FieldArt.hero_entry(cls, race)
	return _hero_art[k]


func _hero(id: int) -> void:
	var m: Dictionary = members[id]
	var p: Vector2 = w2s(shown(id))
	if p.x < -60 or p.x > UiKit.W + 60 or p.y < -60 or p.y > UiKit.H + 100:
		return
	var mine: bool = id == me
	draw_circle(p + Vector2(0, 2), 12.0 * ZOOM * 0.8, Color(0, 0, 0, 0.4))
	if mine:
		draw_arc(p + Vector2(0, 2), 13.0 * ZOOM * 0.8, 0.0, TAU, 20, UiKit.GOLD, 1.5)
	var d: int = int(m["dir"])
	var moving: bool = (m["from"] as Vector2).distance_to(m["to"]) > 0.5
	var e: Dictionary = _hero_entry(int(m["class"]), int(m["race"]))
	if e.is_empty():
		UiArt.draw_hero(self, int(m["class"]), int(m["race"]), p + Vector2(0, -HERO_BOX * ZOOM * 0.4), HERO_BOX * ZOOM, int(m["look"]), d in [4, 5, 6])
		return
	# As in the field: the walk strip's frames while she moves, its first frame standing, mirrored facing west.
	var tex: Texture2D = e["tex"]
	var n: int = int(e["anim"])
	var fw: float = float(tex.get_width()) / n
	var f: int = (int((_clock + float(id) * 0.37) * float(e["fps"])) % n) if moving else 0
	var region := Rect2(f * fw, 0, fw, tex.get_height())
	var sz: Vector2 = region.size * float(e["scale"]) * ZOOM
	var dst := Rect2(p - Vector2(sz.x / 2.0, sz.y * 0.82), sz)
	var col: Color = GameNames.LOOK_PALETTES[GameNames.look_palette(int(m["look"]))]
	if d in [4, 5, 6]:
		draw_set_transform(Vector2(p.x * 2.0, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(tex, dst, region, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(tex, dst, region, col)


## Every hero's name and speech, over everything.
func _hero_labels() -> void:
	for id in members.keys():
		var m: Dictionary = members[id]
		var p: Vector2 = w2s(shown(id))
		if p.x < -60 or p.x > UiKit.W + 60 or p.y < -60 or p.y > UiKit.H + 100:
			continue
		var mine: bool = id == me
		var label: String = "%s  %d" % [String(m["name"]), int(m["level"])]
		UiKit.text(self, p + Vector2(0, -HERO_BOX * ZOOM * 0.95 - 16), label, 12, UiKit.GOLD if mine else UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
		if float(m["say_until"]) > _clock:
			var s: String = String(m["say"])
			var w: float = minf(UiKit.text_width(s, 12), 260.0) + 14.0
			var br := Rect2(p.x - w / 2.0, p.y - HERO_BOX * ZOOM - 52, w, 20)
			UiKit.frame(self, br, UiKit.GOLD_DIM, Color(0.05, 0.04, 0.05, 0.92))
			UiKit.text(self, br.position + Vector2(7, 3), s.left(40), 12, UiKit.BONE)


func _hud() -> void:
	var h: Dictionary = shell.hero
	var r := Rect2(10, 10, 250, 70)
	UiKit.frame(self, r)
	UiKit.text(self, r.position + Vector2(10, 6), String(h.get("name", "?")), 17, UiKit.BONE)
	UiKit.text(self, r.position + Vector2(10, 27), "LEVEL %d %s" % [int(h.get("level", 1)), GameNames.class_name_of(int(h.get("class", 0)))], 13, UiKit.GOLD)
	UiKit.text(self, r.position + Vector2(10, 48), "%s COIN   %s EMBERS" % [GameNames.commas(shell.coin()), GameNames.commas(shell.stack_count(GameNames.PLACE_BAG, GameNames.KIND_EMBERS))], 12, UiKit.BONE_DIM)
	if int(h.get("unspent", 0)) > 0:
		UiKit.text(self, Vector2(r.end.x + 8, r.position.y + 27), ("%d POINT TO SPEND" if int(h["unspent"]) == 1 else "%d POINTS TO SPEND") % int(h["unspent"]), 12, UiKit.GOOD)
	button("sheet", Rect2(UiKit.W - 330, 10, 76, 30), "SHEET", true, false, 13)
	button("bag", Rect2(UiKit.W - 250, 10, 76, 30), "BAG", true, false, 13)
	button("settings", Rect2(UiKit.W - 170, 10, 76, 30), "MENU", true, false, 13)
	button("leave", Rect2(UiKit.W - 90, 10, 80, 30), "HEROES", true, false, 13)
	# Living together (job T1): the party, the guild and the channels past say.
	button("party", Rect2(UiKit.W - 250, 44, 76, 26), "PARTY" + (" %d" % shell.party["members"].size() if not shell.party.is_empty() else ""), true, false, 12)
	button("guild", Rect2(UiKit.W - 170, 44, 76, 26), "GUILD", true, false, 12)
	button("social", Rect2(UiKit.W - 90, 44, 80, 26), "CHAT" + (" *" if not shell.invites.is_empty() else ""), true, false, 12)
	_place_hud()
	_duel_hud()
	_gate_arrow()
	if not _prompt.is_empty():
		var s: String = "[%s]  %s" % [ShellSettings.key_label(ShellSettings.key("interact")), String(_prompt["name"])]
		var w: float = UiKit.text_width(s, 18) + 30.0
		var pr := Rect2((UiKit.W - w) / 2.0, UiKit.H - 128, w, 32)
		hit("prompt", pr)
		UiKit.frame(self, pr, UiKit.GOLD, Color(0.1, 0.04, 0.04, 0.95))
		UiKit.text(self, pr.position + Vector2(w / 2.0, 6), s, 18, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)


## The lit way out: a bobbing gold arrow on the screen's edge toward the field gates (hidden once they are in view).
func _gate_arrow() -> void:
	if not gate_lit() or not _walk_to.is_empty():
		return
	var c: Vector2 = w2s(TownMap.station("gate", stations)["at"])
	if c.y < UiKit.H - 30.0 and c.y > 40.0 and c.x > 0.0 and c.x < UiKit.W:
		return
	# Clear of the minimap (bottom right) and, over the chat's column (bottom left), lifted above its lines.
	var at := Vector2(clampf(c.x, 110.0, UiKit.W - 240.0), UiKit.H - 70.0 + 6.0 * sin(_clock * 4.0))
	if at.x - 100.0 < 540.0:
		at.y -= 110.0
	if c.y < 40.0:
		at.y = 120.0
	var pr := Rect2(at - Vector2(100, 22), Vector2(200, 56))
	hit("gate_arrow", pr)
	UiKit.frame(self, pr, UiKit.GOLD, Color(0.1, 0.04, 0.04, 0.9))
	UiKit.text(self, at + Vector2(0, -16), "THE FIELD GATES", 14, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var dirn: float = -1.0 if c.y < 40.0 else 1.0
	draw_colored_polygon(PackedVector2Array([at + Vector2(-12, 6 * dirn), at + Vector2(12, 6 * dirn), at + Vector2(0, 22 * dirn)]), UiKit.GOLD)


## A duel running or a challenge waiting shows under the hero's card; a challenge is answered on THE DUEL RING's
## screen (it opens by itself; the banner is a way back to it).
func _duel_hud() -> void:
	var s: String = ""
	if not shell.duel.is_empty():
		s = "DUEL WITH %s: WALK TO FIGHT" % String(shell.duel["name"]).to_upper()
	elif not shell.duel_offer.is_empty():
		s = "%s CHALLENGES YOU: ANSWER" % String(shell.duel_offer["name"]).to_upper()
	if s.is_empty():
		return
	var w: float = UiKit.text_width(s, 14) + 24.0
	var r := Rect2(10, 86, w, 26)
	hit("duel_banner", r)
	UiKit.frame(self, r, UiKit.BAD, Color(0.14, 0.03, 0.03, 0.95))
	UiKit.text(self, r.position + Vector2(12, 4), s, 14, UiKit.BONE)


func _chat() -> void:
	var y: float = UiKit.H - 28.0
	var box := Rect2(10, y, 520, 22)
	hit("chatbox", box)
	UiKit.frame(self, box, UiKit.GOLD if typing else UiKit.GOLD_DIM, Color(0.04, 0.035, 0.045, 0.9))
	var cur: String = "_" if typing and int(time * 2.0) % 2 == 0 else ""
	UiKit.text(self, box.position + Vector2(8, 3), (chat_text + cur) if typing else "Press ENTER to speak to the town.", 12, UiKit.BONE if typing else UiKit.BONE_DIM)
	var shown_lines: Array[Dictionary] = []
	for c in chat_log:
		if _clock - float(c["at"]) < CHAT_SHOW_S or typing:
			shown_lines.append(c)
	var from: int = maxi(0, shown_lines.size() - CHAT_LINES)
	for i in range(from, shown_lines.size()):
		var c: Dictionary = shown_lines[i]
		var line: String = "%s: %s" % [c["name"], c["text"]]
		var yy: float = y - 8 - (shown_lines.size() - i) * 15.0
		draw_rect(Rect2(10, yy - 1, minf(UiKit.text_width(line, 12) + 10, 520), 15), Color(0, 0, 0, 0.45))
		UiKit.text(self, Vector2(14, yy), line, 12, UiKit.GOLD if bool(c["mine"]) else UiKit.BONE)


func _minimap() -> void:
	var r := Rect2(UiKit.W - 124, UiKit.H - 124, 114, 114)
	UiKit.frame(self, r, UiKit.GOLD_DIM, Color(0.03, 0.03, 0.04, 0.85))
	var k: float = (r.size.x - 8.0) / size_px
	var o: Vector2 = r.position + Vector2(4, 4)
	if int(shell.place[0]) == HomeMap.PLAZA:
		draw_arc(o + TownMap.CENTRE * k, TownMap.PLAZA_R * k, 0.0, TAU, 28, Color(UiKit.GOLD_DIM, 0.6), 1.0)
	for s in stations:
		draw_rect(Rect2(o + (s["at"] as Vector2) * k - Vector2(2, 2), Vector2(4, 4)), UiKit.GOLD)
	for id in members:
		var p: Vector2 = o + shown(id) * k
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), UiKit.GOOD if id == me else UiKit.BONE)


# ---- input

func on_press(id: String) -> void:
	if id.begins_with("st:"):
		var sid: String = id.trim_prefix("st:")
		var s: Dictionary = TownMap.station(sid, stations)
		if shown(me).distance_to(s["at"]) <= TownMap.CLICK_PX:
			open_station(sid)
		else:
			_walk_to = sid
		return
	match id:
		"gate_arrow":
			_walk_to = "gate"
		"prompt":
			if not _prompt.is_empty():
				open_station(String(_prompt["id"]))
		"sheet":
			open_sheet()
		"bag":
			open_bag()
		"party":
			_open_social("PartyPanel", PartyPanel)
		"guild":
			_open_social("GuildPanel", GuildPanel)
		"social":
			_open_social("ChatPanel", ChatPanel)
		"settings":
			shell.open_panel(SettingsPanel.new())
		"leave":
			shell.leave_town()
		"places":
			_open_home("PlacesPanel", PlacesPanel)
		"duel_banner":
			if shell.duel.is_empty():
				_open_home("DuelPanel", DuelPanel)
		"house":
			_open_home("HousePanel", HousePanel)
		"street":
			_open_home("StreetPanel", StreetPanel)
		"sit":
			sit_or_stand()
		"stairs":
			floor_no = 1 - floor_no
		"chatbox":
			typing = true


func _open_social(cls_name: String, cls: GDScript) -> void:
	if shell.panel_of(cls_name) == null:
		shell.open_panel(cls.new())


func open_sheet() -> void:
	if shell.panel_of("SheetPanel") == null:
		shell.open_panel(SheetPanel.new())


func open_bag() -> void:
	if shell.panel_of("BagPanel") == null:
		shell.open_panel(BagPanel.new())


## Opens a station's panel (after reading the hero's things fresh), or walks through a door.
func open_station(sid: String) -> void:
	if shell.top() != self:
		return
	var st: Dictionary = TownMap.station(sid, stations)
	if st.is_empty():
		return
	if st.has("go") and not (st["go"] as Array).is_empty():
		var go: Array = st["go"]
		await shell.go_place(int(go[0]), int(go[1]))
		return
	await shell.refresh_all()
	var p: UiScreen = null
	if st.has("open"):
		match String(st["open"]):
			"StallsPanel":
				p = StallsPanel.new()
			"YardPanel":
				p = YardPanel.new()
			"DuelPanel":
				p = DuelPanel.new()
			"GuildPanel":
				p = GuildPanel.new()
			"StreetPanel":
				var sp := StreetPanel.new()
				if st.has("plot"):
					sp.selected = int(st["plot"])
				p = sp
	else:
		match sid:
			"bank":
				p = BankPanel.new()
			"smith":
				p = SmithPanel.new()
			"merchants":
				p = MerchantPanel.new()
			"reader":
				p = ReaderPanel.new()
			"trainer":
				p = TrainerPanel.new()
			"gate":
				p = GatePanel.new()
			"market":
				p = MarketPanel.new()
			"post":
				p = PostPanel.new()
			"trade":
				p = TradePanel.new()
			"board":
				p = BoardPanel.new()
			"trial":
				p = TrialPanel.new()
	if p != null and shell.top() == self:
		shell.open_panel(p)


func _open_home(cls_name: String, cls: GDScript) -> void:
	if shell.panel_of(cls_name) == null:
		shell.open_panel(cls.new())


## The place's own buttons under the hero's box: the places list, sitting at a fire, and by place the house or
## the street.
func _place_hud() -> void:
	var kind: int = int(shell.place[0])
	UiKit.text(self, Vector2(UiKit.W / 2.0, 12), HomeMap.place_name(kind, int(shell.place[1])), 16, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	button("places", Rect2(10, 84, 86, 26), "PLACES", true, false, 12)
	var fires: Array[Vector2] = HomeMap.fires_here(shell.place, shell.house.get("items", []))
	var at_fire: bool = false
	if members.has(me):
		for f in fires:
			if shown(me).distance_to(f) <= HomeMap.FIRE_REACH:
				at_fire = true
	var sitting: bool = bool(shell.rest.get("sitting", false))
	button("sit", Rect2(102, 84, 70, 26), "STAND" if sitting else "SIT", at_fire or sitting, sitting, 12)
	if kind == HomeMap.HOUSE:
		button("house", Rect2(178, 84, 86, 26), "HOUSE", true, false, 12)
		button("stairs", Rect2(270, 84, 96, 26), "UPSTAIRS" if floor_no == 0 else "DOWNSTAIRS", true, false, 12)
	elif kind == HomeMap.STREET:
		button("street", Rect2(178, 84, 86, 26), "STREET", true, false, 12)
	if bool(shell.rest.get("sitting", false)) or int(shell.rest.get("rested_ms", 0)) > 0:
		var ms: int = int(shell.rest.get("rested_ms", 0))
		var txt: String = ("SITTING %ds  " % int(shell.rest.get("secs", 0)) if sitting else "") + ("RESTED +%d%%  %d:%02d" % [int(shell.rest.get("pct", 0)), ms / 60000, (ms / 1000) % 60] if ms > 0 else "")
		UiKit.text(self, Vector2(10, 114), txt, 12, UiKit.GOOD)


## Sits at a fire or stands up; the reply says how long and how rested she is.
func sit_or_stand() -> void:
	var sub: int = HomeWire.Q_STAND if bool(shell.rest.get("sitting", false)) else HomeWire.Q_SIT
	var r: Dictionary = await shell.act(HomeWire.hero_only(sub, shell.hero_id()))
	if int(r["t"]) == HomeWire.R_HOME and int(r.get("k", -1)) == HomeWire.K_REST:
		shell.rest = r
		_rest_poll = 0.0


## While she sits the gateway counts the minutes; ask now and then so the screen shows the rest she has earned.
func _poll_rest(delta: float) -> void:
	if not bool(shell.rest.get("sitting", false)):
		return
	_rest_poll += delta
	if _rest_poll < 5.0:
		return
	_rest_poll = 0.0
	var r: Dictionary = await shell.link.call_req(HomeWire.hero_only(HomeWire.Q_STATUS, shell.hero_id()))
	if int(r["t"]) == HomeWire.R_HOME and int(r.get("k", -1)) == HomeWire.K_REST:
		shell.rest = r


func send_chat(text: String) -> void:
	var t: String = text.strip_edges()
	if t.is_empty():
		return
	var r: Dictionary = await shell.link.call_req(GwWire.chat(t.left(CHAT_MAX)))
	if int(r["t"]) == GwWire.R_ERR:
		say("SLOW DOWN" if int(r["code"]) == GwWire.E_SLOW_DOWN else Shell.error_text(r), true)


func on_key(e: InputEventKey) -> bool:
	if typing:
		if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER:
			var t: String = chat_text
			chat_text = ""
			typing = false
			send_chat(t)
		elif e.keycode == KEY_ESCAPE:
			chat_text = ""
			typing = false
		elif e.keycode == KEY_BACKSPACE:
			chat_text = chat_text.left(maxi(0, chat_text.length() - 1))
		elif e.unicode >= 32 and e.unicode != 127 and chat_text.length() < CHAT_MAX:
			chat_text += char(e.unicode)
		return true
	if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER:
		typing = true
		return true
	if e.keycode == KEY_ESCAPE:
		shell.open_panel(SettingsPanel.new())
		return true
	if ShellSettings.matches("interact", e):
		if not _prompt.is_empty():
			open_station(String(_prompt["id"]))
		return true
	if ShellSettings.matches("sheet", e):
		open_sheet()
		return true
	if ShellSettings.matches("bag", e):
		open_bag()
		return true
	return false

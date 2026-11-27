class_name FieldHud
extends Control
## The hero's HUD, drawn in the 480 x 270 canvas: health and XP bars, the three skills with cooldowns, the
## three potions, the haul and field level, the draw on offer (the deck's picks), the tide's clock, a boss's
## bar, and the downed and raising screens. It reads the dictionary `RealmLink.hero_view()` and `world()`.
## Cards offered are picked with Z X C V or a click; skills Space (1), E (2), R (the ultimate); F holds
## interact (banking), G the BLOOD MARK's rite at a waystone (both rebindable); potions 4 5 6. A hero who carries
## the mark sees it by her health; standing at a waystone shows what holding does there.

const W: float = 480.0
const H: float = 270.0
## The faces, each at one canvas px a design px (3 screen px in the 1440 x 810 window): BODY Jersey10 (capitals
## 10 px) for every word and number, MID Jersey15 (15) for a cooldown's seconds and a potion's letter, GOTHIC_S
## Jacquard12 (12) for a boss's name, GOTHIC Jacquard24 (24) for the downed and joining words.
enum { BODY, MID, GOTHIC_S, GOTHIC }
const STYLES: Array = ["jersey10", "jersey15", "jacquard12", "jacquard24"]
## From one line of BODY text to the next.
const LINE: float = 14.0
const TICKS_PER_S: float = 20.0
## The tide's clock from the field's tick, rules section 8: one begins every 30 minutes and lasts 5. (A
## stand-in until the core's tide job gives its own clock; `world.tide` decides which side it is on.)
const TIDE_EVERY_TICKS: int = 30 * 60 * 20
const TIDE_LEN_TICKS: int = 5 * 60 * 20
const BANK_HOLD_TICKS: float = 60.0
## The BLOOD MARK's rite is held this long (realm/core pvp.rs MARK_HOLD, 5 s).
const MARK_HOLD_TICKS: float = 100.0
const MARK_RED: Color = Color(0.85, 0.08, 0.1)
const SKILL_KEYS: Array[String] = ["SPACE", "E", "R"]
const POTION_KEYS: Array[String] = ["4", "5", "6"]
const PICK_KEYS: Array[String] = ["Z", "X", "C", "V"]
const SKILL_LEVELS: Array[int] = [10, 25, 40]
const PANEL: Color = Color(0.04, 0.03, 0.06, 0.72)
const EDGE: Color = Color(0.55, 0.45, 0.3, 0.9)
const TEXT: Color = Color(0.92, 0.92, 0.85)
const DIM: Color = Color(0.6, 0.6, 0.62)
const GOOD: Color = Color(0.55, 0.85, 0.5)

var hero: Dictionary = {}
var world: Dictionary = {}
var debug_text: String = ""
## A line over the field (the shell's warning before leaving by Esc); empty draws nothing.
var notice: String = ""
## The numbers panel, a developer's view: only with F3 or --debug=1.
var show_debug: bool = false
## Screenshots and tests: show a tide or a boss the core has not made yet.
var fake_tide: bool = false
var fake_boss: bool = false
## The waystone she stands at (0..6, -1 none), and whether the rite's key is held (the hold bar is the rite's).
var near_stone: int = -1
var rite_held: bool = false
## Where the offered cards were drawn this frame (Rect2 each), for clicks.
var card_rects: Array[Rect2] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(h: Dictionary, w: Dictionary, dbg: String) -> void:
	hero = h
	world = w
	debug_text = dbg
	queue_redraw()


## The card (0..3) under a point in the canvas, or -1.
func card_at(p: Vector2) -> int:
	for i in card_rects.size():
		if card_rects[i].has_point(p):
			return i
	return -1


func _txt(p: Vector2, s: String, col: Color = TEXT, style: int = BODY) -> void:
	# `p` is the top left of the capitals. One design pixel of shadow, whole pixels only.
	var n: String = STYLES[style]
	var f: Font = UiKit.face(n)
	var fs: int = UiKit.crisp(n)
	if style >= GOTHIC_S:
		s = UiKit.title_case(s)
	var base: Vector2 = (p + Vector2(0, UiKit.cap(n))).round()
	f.draw_string(get_canvas_item(), base + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.85))
	f.draw_string(get_canvas_item(), base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _width(s: String, style: int = BODY) -> float:
	var n: String = STYLES[style]
	if style >= GOTHIC_S:
		s = UiKit.title_case(s)
	return UiKit.face(n).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.crisp(n)).x


## `s` cut short (no dots: a name is still read by its start) until it fits in `w` px.
func _fit(s: String, w: float, style: int = BODY) -> String:
	var t: String = s
	while t.length() > 1 and _width(t, style) > w:
		t = t.left(t.length() - 1)
	return t


func _ctxt(center_x: float, y: float, s: String, col: Color = TEXT, style: int = BODY) -> void:
	_txt(Vector2(roundf(center_x - _width(s, style) / 2.0), y), s, col, style)


func _rtxt(right_x: float, y: float, s: String, col: Color = TEXT, style: int = BODY) -> void:
	_txt(Vector2(right_x - _width(s, style), y), s, col, style)


func _box(r: Rect2, fill: Color = PANEL, edge: Color = EDGE) -> void:
	draw_rect(r, fill)
	draw_rect(r, edge, false, 1.0)


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(0, 0, 0, 0.7))
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * clampf(frac, 0.0, 1.0)), r.size.y)), col)
	draw_rect(r, EDGE, false, 1.0)


static func clock(ticks: int) -> String:
	var s: int = maxi(ticks, 0) / 20
	return "%d:%02d" % [s / 60, s % 60]


func _draw() -> void:
	card_rects.clear()
	if show_debug and not debug_text.is_empty():
		var lines: PackedStringArray = debug_text.split("\n")
		var dw: float = 0.0
		for l in lines:
			dw = maxf(dw, _width(l))
		_box(Rect2(2, 60, dw + 8.0, 4 + lines.size() * LINE), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0))
		for i in lines.size():
			_txt(Vector2(6, 63 + i * LINE), lines[i], Color(0.85, 0.95, 0.8))
	_draw_world_clock()
	if not notice.is_empty():
		# One line, or two split at the space nearest the middle when it is wider than the screen allows.
		var lines: PackedStringArray = [notice]
		if _width(notice) > W - 40.0 and notice.contains(" "):
			var mid: int = notice.length() / 2
			var cut: int = notice.rfind(" ", mid)
			var cut2: int = notice.find(" ", mid)
			if cut < 0 or (cut2 >= 0 and cut2 - mid < mid - cut):
				cut = cut2
			lines = [notice.left(cut), notice.substr(cut + 1)]
		var nw: float = 0.0
		for l in lines:
			nw = maxf(nw, _width(l))
		nw = minf(nw + 16.0, W - 20.0)
		_box(Rect2(roundf(W / 2.0 - nw / 2.0), 58, roundf(nw), 4 + lines.size() * LINE), Color(0.2, 0.04, 0.04, 0.88), EDGE)
		for i in lines.size():
			_ctxt(W / 2.0, 62 + i * LINE, lines[i], TEXT)
	if hero.is_empty():
		_ctxt(W / 2.0, H / 2.0 - 14, "Entering the field", TEXT, GOTHIC)
		return
	if int(hero["downed"]) > 0 or not bool(hero["alive"]):
		_draw_downed()
	_draw_vitals()
	_draw_skills()
	_draw_potions()
	_draw_haul()
	_draw_offer()
	_draw_banking()
	_draw_mark()


## Bottom left: her class or calling and its level, health, and the field level's XP, numbers inside the bars.
func _draw_vitals() -> void:
	var hp: int = int(hero["health"])
	var mx: int = maxi(int(hero["max_health"]), 1)
	var frac: float = float(hp) / float(mx)
	var job: int = int(hero["job"])
	var who: String = GameNames.job_name_of(job) if job >= 0 else String(RealmLink.class_name(int(hero["class"])))
	_box(Rect2(3, H - 55, 130, 52))
	_txt(Vector2(7, H - 52), _fit("%s %d" % [who, int(hero["class_level"])], 80.0), Color(1.0, 0.85, 0.5))
	_rtxt(129, H - 52, "LV %d" % int(hero["level"]), DIM)
	_bar(Rect2(7, H - 38, 122, 14), frac, Color(0.75, 0.15, 0.15) if frac > 0.3 else Color(0.95, 0.35, 0.1))
	_ctxt(68, H - 36, "%d / %d" % [hp, mx], TEXT)
	var need: int = maxi(int(hero["xp_need"]), 1)
	_bar(Rect2(7, H - 21, 122, 14), float(hero["xp"]) / float(need), Color(0.25, 0.4, 0.75))
	_ctxt(68, H - 19, "%d / %d" % [int(hero["xp"]), need], Color(0.85, 0.9, 1.0))


func _draw_skills() -> void:
	var skills: PackedInt32Array = hero["skills"]
	var x0: float = 137.0
	for slot in 3:
		var id: int = skills[slot * 4]
		var r := Rect2(x0 + slot * 87, H - 55, 84, 52)
		_box(r)
		var cx: float = r.position.x + 42.0
		if id < 0:
			_ctxt(cx, r.position.y + 4, "SEALED", DIM)
			_ctxt(cx, r.position.y + 19, "LEVEL %d" % SKILL_LEVELS[slot], DIM)
		else:
			var info: Dictionary = RealmLink.skill_info(id)
			var whole: String = String(info["name"])
			var word: String = whole if _width(whole) <= 80.0 else _fit(whole.split(" ")[0], 80.0)
			var rank: int = (skills[slot * 4 + 3] - 100) / 15 + 1
			var left: int = skills[slot * 4 + 1]
			var full: int = maxi(skills[slot * 4 + 2], 1)
			if left > 0:
				# Cooling: the shade falls as it readies, the seconds left large where the rank was.
				var f: float = clampf(float(left) / float(full), 0.0, 1.0)
				draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 82, roundf(50.0 * f)), Color(0, 0, 0, 0.7))
				_ctxt(cx, r.position.y + 4, word, DIM)
				_ctxt(cx, r.position.y + 17, "%d" % ceili(float(left) / TICKS_PER_S), Color(1, 0.9, 0.6), MID)
			else:
				draw_rect(r.grow(-1.0), Color(0.9, 0.8, 0.4, 0.1))
				_ctxt(cx, r.position.y + 4, word, TEXT)
				_ctxt(cx, r.position.y + 19, "RANK %d" % rank, DIM)
		_ctxt(cx, r.position.y + 37, SKILL_KEYS[slot], Color(0.75, 0.65, 0.45))


func _draw_potions() -> void:
	var belt: PackedInt32Array = hero["belt"]
	var x0: float = 399.0
	for slot in 3:
		var id: int = belt[slot * 3]
		var r := Rect2(x0 + slot * 26, H - 55, 23, 52)
		_box(r)
		var cx: float = r.position.x + 12.0
		if id < 0:
			_ctxt(cx, r.position.y + 12, "-", DIM)
		else:
			var name: String = String(RealmLink.potion_name(id))
			_ctxt(cx, r.position.y + 4, name.left(1), TEXT, MID)
			_ctxt(cx, r.position.y + 23, "x%d" % belt[slot * 3 + 1], Color(0.8, 0.9, 1.0))
			var rest: int = belt[slot * 3 + 2]
			if rest > 0:
				draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 21, roundf(50.0 * clampf(float(rest) / 200.0, 0.0, 1.0))), Color(0, 0, 0, 0.6))
		_ctxt(cx, r.position.y + 37, POTION_KEYS[slot], Color(0.75, 0.65, 0.45))


## Top right: the coin she carries and whether it is banked yet.
func _draw_haul() -> void:
	_box(Rect2(W - 122, 3, 119, 32))
	_txt(Vector2(W - 117, 6), "COIN %d" % int(hero["coin"]), Color(1.0, 0.85, 0.35))
	var banked: String = "SAFE AT STONE %d" % (int(hero["waystone"]) + 1) if bool(hero["banked"]) else "NOT YET BANKED"
	_txt(Vector2(W - 117, 20), banked, GOOD if bool(hero["banked"]) else DIM)


func _draw_offer() -> void:
	var offer: PackedInt32Array = hero["offer"]
	var n: int = 0
	for c in offer:
		if c > 0:
			n += 1
	var owed: int = int(hero["owed"])
	if n == 0:
		if owed > 0:
			_ctxt(W / 2.0, H - 72, "A DRAW AWAITS (%d)" % owed, DIM)
		return
	var copies: PackedInt32Array = hero["copies"]
	var w: float = 104.0
	var x0: float = roundf(W / 2.0 - (n * (w + 4.0) - 4.0) / 2.0)
	var y: float = H - 125.0
	_ctxt(W / 2.0, y - 15, "CHOOSE A CARD" if owed <= 1 else "CHOOSE A CARD  (%d MORE)" % (owed - 1), Color(1.0, 0.9, 0.5))
	for i in 4:
		if offer[i] <= 0:
			continue
		var r := Rect2(x0 + card_rects.size() * (w + 4.0), y, w, 62)
		card_rects.append(r)
		_box(r, Color(0.1, 0.07, 0.14, 0.9), Color(0.9, 0.75, 0.35))
		var name: String = String(RealmLink.card_name(offer[i]))
		var parts: PackedStringArray = name.split(" ", true, 2)
		var l1: String = " ".join(parts.slice(0, mini(2, parts.size())))
		var l2: String = parts[2] if parts.size() > 2 else ""
		var cx: float = r.position.x + w / 2.0
		_ctxt(cx, r.position.y + 5, _fit(l1, w - 6.0), TEXT)
		_ctxt(cx, r.position.y + 18, _fit(l2, w - 6.0), TEXT)
		_ctxt(cx, r.position.y + 33, "OWNED %d / 5" % copies[offer[i]], DIM)
		_ctxt(cx, r.position.y + 47, PICK_KEYS[i], Color(1, 0.9, 0.5))


func _draw_banking() -> void:
	var hold: int = int(hero["hold"])
	var y: float = H / 2.0 + 16.0
	if hold > 0 and rite_held:
		_ctxt(W / 2.0, y, "THE RITE OF THE BLOOD MARK", MARK_RED)
		_bar(Rect2(W / 2.0 - 40, y + 14, 80, 5), float(hold) / MARK_HOLD_TICKS, MARK_RED)
	elif hold > 0:
		_ctxt(W / 2.0, y, "BANKING THE SPOILS", Color(1.0, 0.85, 0.3))
		_bar(Rect2(W / 2.0 - 40, y + 14, 80, 5), float(hold) / BANK_HOLD_TICKS, Color(1.0, 0.85, 0.3))
	elif near_stone >= 0 and bool(hero["alive"]):
		var bank: String = "HOLD %s  BANK AND LEAVE" % _key("interact")
		var rite: String = "HOLD %s  %s THE BLOOD MARK" % [_key("mark"), "LAY DOWN" if marked() else "TAKE UP"]
		var bw: float = maxf(_width(bank), _width(rite)) + 14.0
		_box(Rect2(roundf(W / 2.0 - bw / 2.0), y - 4, roundf(bw), 32))
		_ctxt(W / 2.0, y, bank, TEXT)
		_ctxt(W / 2.0, y + 14, rite, MARK_RED if not marked() else DIM)


## Is she carrying the BLOOD MARK?
func marked() -> bool:
	return bool(hero.get("marked", false))


static func _key(action: String) -> String:
	return ShellSettings.key_label(ShellSettings.key(action))


## The mark she carries: a red seal by her health, seen at a glance.
func _draw_mark() -> void:
	if not marked():
		return
	var r := Rect2(3, H - 73, 98, 16)
	_box(r, Color(0.3, 0.02, 0.03, 0.88), MARK_RED)
	_txt(r.position + Vector2(5, 3), "BLOOD MARKED", Color(1.0, 0.75, 0.72))


func _draw_downed() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.45, 0.0, 0.0, 0.22))
	var secs: int = ceili(float(hero["downed"]) / TICKS_PER_S)
	_ctxt(W / 2.0, H / 2.0 - 76, "Struck down  %d" % secs, Color(1.0, 0.4, 0.35), GOTHIC)
	_ctxt(W / 2.0, H / 2.0 - 42, "An ally at your side can raise you", TEXT)
	_bar(Rect2(W / 2.0 - 40, H / 2.0 - 26, 80, 5), float(hero["raise_pct"]) / 100.0, Color(0.5, 1.0, 0.65))


func _draw_world_clock() -> void:
	var tick: int = int(world.get("tick", 0))
	var tide: bool = bool(world.get("tide", false)) or fake_tide
	var phase: int = tick % TIDE_EVERY_TICKS
	var s: String
	var col: Color
	if tide:
		var left: int = maxi(TIDE_LEN_TICKS - phase, 0) if not fake_tide else TIDE_LEN_TICKS * 3 / 5
		if world.has("tide_left") and not fake_tide:
			left = int(world["tide_left"])
		s = "THE TIDE  %s" % clock(left)
		col = Color(1.0, 0.45, 0.35)
		draw_rect(Rect2(0, 0, W, 3), Color(0.9, 0.15, 0.1, 0.55))
		draw_rect(Rect2(0, H - 3, W, 3), Color(0.9, 0.15, 0.1, 0.55))
		draw_rect(Rect2(0, 0, 3, H), Color(0.9, 0.15, 0.1, 0.55))
		draw_rect(Rect2(W - 3, 0, 3, H), Color(0.9, 0.15, 0.1, 0.55))
	else:
		var wait: int = int(world["tide_in"]) if world.has("tide_in") else TIDE_EVERY_TICKS - phase
		s = "TIDE IN %s" % clock(wait)
		col = DIM
	_box(Rect2(W / 2.0 - 55, 3, 110, 17), PANEL if not tide else Color(0.3, 0.04, 0.03, 0.85))
	_ctxt(W / 2.0, 6, s, col)
	var boss: Dictionary = world.get("boss", {})
	if fake_boss and boss.is_empty():
		boss = {"name": "THE HARVESTER", "health": 61000, "max_health": 80000}
	if not boss.is_empty():
		var mx: int = maxi(int(boss["max_health"]), 1)
		var frac: float = float(boss["health"]) / float(mx)
		_box(Rect2(W / 2.0 - 120, 23, 240, 32), PANEL, Color(0.8, 0.2, 0.55))
		_ctxt(W / 2.0, 26, String(boss["name"]), Color(1.0, 0.75, 0.45), GOTHIC_S)
		_bar(Rect2(W / 2.0 - 114, 44, 228, 6), frac, Color(0.8, 0.2, 0.55))

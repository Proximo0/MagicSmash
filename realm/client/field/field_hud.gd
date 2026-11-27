class_name FieldHud
extends Control
## The hero's HUD, drawn in the 480 x 270 canvas: health and XP bars, the three skills with cooldowns, the
## three potions, the haul and class level, the draw on offer (the deck's picks), the tide's clock, a boss's
## bar, and the downed and raising screens. It reads the dictionary `RealmLink.hero_view()` and `world()`.
## Cards offered are picked with Z X C V or a click; skills Space (1), E (2), R (the ultimate); F holds
## interact (banking), G the BLOOD MARK's rite at a waystone (both rebindable); potions 4 5 6. A hero who carries
## the mark sees it by her health; standing at a waystone shows what holding does there.

const W: float = 480.0
const H: float = 270.0
const FONT: int = 6
const FONT_SMALL: int = 5
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

var hero: Dictionary = {}
var world: Dictionary = {}
var debug_text: String = ""
## A line over the field (the shell's warning before leaving by Esc); empty draws nothing.
var notice: String = ""
var show_debug: bool = true
## Screenshots and tests: show a tide or a boss the core has not made yet.
var fake_tide: bool = false
var fake_boss: bool = false
## The waystone she stands at (0..6, -1 none), and whether the rite's key is held (the hold bar is the rite's).
var near_stone: int = -1
var rite_held: bool = false
## Where the offered cards were drawn this frame (Rect2 each), for clicks.
var card_rects: Array[Rect2] = []
var _font: Font = ThemeDB.fallback_font


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


func _txt(p: Vector2, s: String, col: Color = TEXT, size: int = FONT) -> void:
	# `p` is the top left of the text.
	var base: Vector2 = p + Vector2(0, size * 0.85)
	_font.draw_string(get_canvas_item(), base + Vector2(0.5, 0.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8))
	_font.draw_string(get_canvas_item(), base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _ctxt(center_x: float, y: float, s: String, col: Color = TEXT, size: int = FONT) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_txt(Vector2(center_x - w / 2.0, y), s, col, size)


func _box(r: Rect2, fill: Color = PANEL, edge: Color = EDGE) -> void:
	draw_rect(r, fill)
	draw_rect(r, edge, false, 1.0)


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(0, 0, 0, 0.7))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, EDGE, false, 1.0)


static func clock(ticks: int) -> String:
	var s: int = maxi(ticks, 0) / 20
	return "%d:%02d" % [s / 60, s % 60]


func _draw() -> void:
	card_rects.clear()
	if show_debug and not debug_text.is_empty():
		var lines: PackedStringArray = debug_text.split("\n")
		_box(Rect2(2, 2, 130, 4 + lines.size() * 7.0), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0))
		for i in lines.size():
			_txt(Vector2(5, 4 + i * 7.0), lines[i], Color(0.85, 0.95, 0.8), FONT_SMALL)
	_draw_world_clock()
	if not notice.is_empty():
		_box(Rect2(40, 40, W - 80, 14), Color(0.2, 0.04, 0.04, 0.85), EDGE)
		_ctxt(W / 2.0, 43, notice, TEXT, FONT_SMALL)
	if hero.is_empty():
		_ctxt(W / 2.0, H / 2.0, "JOINING THE FIELD", TEXT, 9)
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


func _draw_vitals() -> void:
	var hp: int = int(hero["health"])
	var mx: int = maxi(int(hero["max_health"]), 1)
	var frac: float = float(hp) / float(mx)
	var cls: String = String(RealmLink.class_name(int(hero["class"])))
	var job: int = int(hero["job"])
	var title: String = "%s %d" % [cls, int(hero["class_level"])]
	if job >= 0:
		title += "  JOB %d" % job
	_box(Rect2(3, H - 41, 126, 38))
	_txt(Vector2(7, H - 39), title, DIM, FONT_SMALL)
	_bar(Rect2(7, H - 32, 118, 8), frac, Color(0.75, 0.15, 0.15) if frac > 0.3 else Color(0.95, 0.35, 0.1))
	_ctxt(66, H - 31.5, "%d / %d" % [hp, mx], TEXT, FONT_SMALL)
	# Class level and class XP (the saved hero's, with this outing's); at 60 there is no next step.
	var need: int = int(hero["xp_need"])
	_bar(Rect2(7, H - 22, 118, 5), float(hero["xp"]) / float(need) if need > 0 else 1.0, Color(0.35, 0.55, 0.9))
	_txt(Vector2(7, H - 14), ("LEVEL %d   XP %d/%d" % [int(hero["level"]), int(hero["xp"]), need]) if need > 0 else "LEVEL %d" % int(hero["level"]), DIM, FONT_SMALL)


func _draw_skills() -> void:
	var skills: PackedInt32Array = hero["skills"]
	var x0: float = W / 2.0 - 50.0
	for slot in 3:
		var id: int = skills[slot * 4]
		var r := Rect2(x0 + slot * 33, H - 32, 30, 25)
		_box(r)
		if id < 0:
			_ctxt(r.position.x + 15.0, r.position.y + 6, "LV", DIM, FONT_SMALL)
			_ctxt(r.position.x + 15.0, r.position.y + 13, str(SKILL_LEVELS[slot]), DIM, FONT_SMALL)
		else:
			var info: Dictionary = RealmLink.skill_info(id)
			var name: String = String(info["name"])
			var words: PackedStringArray = name.split(" ")
			_ctxt(r.position.x + 15.0, r.position.y + 3, words[0].left(9), TEXT, FONT_SMALL)
			var rank: int = (skills[slot * 4 + 3] - 100) / 15 + 1
			_ctxt(r.position.x + 15.0, r.position.y + 9, "RANK %d" % rank, DIM, FONT_SMALL)
			var left: int = skills[slot * 4 + 1]
			var full: int = maxi(skills[slot * 4 + 2], 1)
			if left > 0:
				var f: float = clampf(float(left) / float(full), 0.0, 1.0)
				draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 28, 23.0 * f), Color(0, 0, 0, 0.65))
				_ctxt(r.position.x + 15.0, r.position.y + 14, "%d" % ceili(float(left) / TICKS_PER_S), Color(1, 0.9, 0.6), 8)
			else:
				draw_rect(r.grow(-1.0), Color(0.9, 0.8, 0.4, 0.1))
		_ctxt(r.position.x + 15.0, r.position.y + 26, SKILL_KEYS[slot], DIM, 4)


func _draw_potions() -> void:
	var belt: PackedInt32Array = hero["belt"]
	var x0: float = W / 2.0 + 56.0
	for slot in 3:
		var id: int = belt[slot * 3]
		var r := Rect2(x0 + slot * 19, H - 28, 16, 21)
		_box(r)
		if id < 0:
			_ctxt(r.position.x + 8, r.position.y + 6, "-", DIM, FONT_SMALL)
		else:
			var name: String = String(RealmLink.potion_name(id))
			_ctxt(r.position.x + 8, r.position.y + 2, name.left(1), TEXT, 8)
			_ctxt(r.position.x + 8, r.position.y + 12, "x%d" % belt[slot * 3 + 1], Color(0.8, 0.9, 1.0), FONT_SMALL)
			var rest: int = belt[slot * 3 + 2]
			if rest > 0:
				draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 14, 19.0 * clampf(float(rest) / 200.0, 0.0, 1.0)), Color(0, 0, 0, 0.6))
		_ctxt(r.position.x + 8, r.position.y + 22, POTION_KEYS[slot], DIM, 4)


func _draw_haul() -> void:
	_box(Rect2(W - 92, 3, 89, 20))
	_txt(Vector2(W - 88, 10), "HAUL  COIN %d" % int(hero["coin"]), Color(1.0, 0.85, 0.35), FONT_SMALL)
	var banked: String = "BANKED AT STONE %d" % (int(hero["waystone"]) + 1) if bool(hero["banked"]) else "NOT BANKED"
	_txt(Vector2(W - 88, 18), banked, DIM, FONT_SMALL)


func _draw_offer() -> void:
	var offer: PackedInt32Array = hero["offer"]
	var n: int = 0
	for c in offer:
		if c > 0:
			n += 1
	var owed: int = int(hero["owed"])
	if n == 0:
		if owed > 0:
			_ctxt(W / 2.0, H - 48, "CARD DRAW COMING (%d)" % owed, DIM, FONT_SMALL)
		return
	var copies: PackedInt32Array = hero["copies"]
	var w: float = 76.0
	var x0: float = W / 2.0 - (n * (w + 4.0) - 4.0) / 2.0
	var y: float = H - 84.0
	_ctxt(W / 2.0, y - 9, "CHOOSE A CARD (%d QUEUED)" % owed, Color(1.0, 0.9, 0.5), FONT_SMALL)
	for i in 4:
		if offer[i] <= 0:
			continue
		var r := Rect2(x0 + i * (w + 4.0), y, w, 34)
		card_rects.append(r)
		_box(r, Color(0.1, 0.07, 0.14, 0.88), Color(0.9, 0.75, 0.35))
		var name: String = String(RealmLink.card_name(offer[i]))
		var parts: PackedStringArray = name.split(" ", true, 2)
		var l1: String = " ".join(parts.slice(0, mini(2, parts.size())))
		var l2: String = parts[2] if parts.size() > 2 else ""
		_ctxt(r.position.x + w / 2.0, r.position.y + 6, l1, TEXT, FONT_SMALL)
		_ctxt(r.position.x + w / 2.0, r.position.y + 13, l2, TEXT, FONT_SMALL)
		_ctxt(r.position.x + w / 2.0, r.position.y + 22, "HAVE %d / 5" % copies[offer[i]], DIM, FONT_SMALL)
		_ctxt(r.position.x + w / 2.0, r.position.y + 30, PICK_KEYS[i], Color(1, 0.9, 0.5), FONT_SMALL)


func _draw_banking() -> void:
	var hold: int = int(hero["hold"])
	if hold > 0 and rite_held:
		_bar(Rect2(W / 2.0 - 30, H / 2.0 + 24, 60, 5), float(hold) / MARK_HOLD_TICKS, MARK_RED)
		_ctxt(W / 2.0, H / 2.0 + 17, "THE RITE OF THE BLOOD MARK", MARK_RED, FONT_SMALL)
	elif hold > 0:
		_bar(Rect2(W / 2.0 - 30, H / 2.0 + 24, 60, 5), float(hold) / BANK_HOLD_TICKS, Color(1.0, 0.85, 0.3))
		_ctxt(W / 2.0, H / 2.0 + 17, "BANKING", Color(1.0, 0.85, 0.3), FONT_SMALL)
	elif near_stone >= 0 and bool(hero["alive"]):
		var bank: String = "HOLD %s: BANK AND LEAVE" % _key("interact")
		var rite: String = "HOLD %s: %s THE BLOOD MARK" % [_key("mark"), "PUT DOWN" if marked() else "TAKE"]
		_box(Rect2(W / 2.0 - 70, H / 2.0 + 14, 140, 18))
		_ctxt(W / 2.0, H / 2.0 + 15, bank, TEXT, FONT_SMALL)
		_ctxt(W / 2.0, H / 2.0 + 23, rite, MARK_RED if not marked() else DIM, FONT_SMALL)


## Is she carrying the BLOOD MARK?
func marked() -> bool:
	return bool(hero.get("marked", false))


static func _key(action: String) -> String:
	return ShellSettings.key_label(ShellSettings.key(action))


## The mark she carries: a red seal by her health, seen at a glance.
func _draw_mark() -> void:
	if not marked():
		return
	var r := Rect2(3, H - 53, 74, 11)
	_box(r, Color(0.3, 0.02, 0.03, 0.85), MARK_RED)
	_txt(r.position + Vector2(4, 2), "BLOOD MARKED", Color(1.0, 0.75, 0.72), FONT_SMALL)


func _draw_downed() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.45, 0.0, 0.0, 0.22))
	var secs: int = ceili(float(hero["downed"]) / TICKS_PER_S)
	_ctxt(W / 2.0, H / 2.0 - 40, "DOWNED  %ds" % secs, Color(1.0, 0.4, 0.35), 12)
	_ctxt(W / 2.0, H / 2.0 - 26, "AN ALLY WITHIN 40 PX RAISES YOU", DIM, FONT_SMALL)
	_bar(Rect2(W / 2.0 - 40, H / 2.0 - 18, 80, 5), float(hero["raise_pct"]) / 100.0, Color(0.5, 1.0, 0.65))


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
		s = "TIDE  %s LEFT" % clock(left)
		col = Color(1.0, 0.45, 0.35)
		draw_rect(Rect2(0, 0, W, 3), Color(0.9, 0.15, 0.1, 0.55))
		draw_rect(Rect2(0, H - 3, W, 3), Color(0.9, 0.15, 0.1, 0.55))
		draw_rect(Rect2(0, 0, 3, H), Color(0.9, 0.15, 0.1, 0.55))
		draw_rect(Rect2(W - 3, 0, 3, H), Color(0.9, 0.15, 0.1, 0.55))
	else:
		var wait: int = int(world["tide_in"]) if world.has("tide_in") else TIDE_EVERY_TICKS - phase
		s = "NEXT TIDE %s" % clock(wait)
		col = DIM
	_box(Rect2(W / 2.0 - 45, 3, 90, 11), PANEL if not tide else Color(0.3, 0.04, 0.03, 0.85))
	_ctxt(W / 2.0, 5.5, s, col, FONT_SMALL)
	var boss: Dictionary = world.get("boss", {})
	if fake_boss and boss.is_empty():
		boss = {"name": "THE HARVESTER", "health": 61000, "max_health": 80000}
	if not boss.is_empty():
		var mx: int = maxi(int(boss["max_health"]), 1)
		_box(Rect2(W / 2.0 - 80, 17, 160, 14))
		_ctxt(W / 2.0, 18.5, String(boss["name"]), Color(1.0, 0.75, 0.45), FONT_SMALL)
		_bar(Rect2(W / 2.0 - 76, 25, 152, 4), float(boss["health"]) / float(mx), Color(0.8, 0.2, 0.55))

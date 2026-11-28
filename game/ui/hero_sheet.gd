class_name HeroSheet
extends RefCounted
## One saved hero's sheet: portrait, name, race, class, role, class level with its XP bar, hearts, the six stats with
## where each comes from (race, class, spent points, socketed cards) and the total, the points left to spend (a
## point goes on the highlighted stat), weapon and skill with their main numbers, the race trait in words, the three
## card sockets and the profile's runs and wins. Opened from the hero roster (the Sanctum's mirror). Also holds the
## few drawing helpers the roster and the builder share: portrait, hearts, wrapped text.

const GROUP := "portraits/heroes"
const STAT_LABELS := ["MIGHT", "FOCUS", "SWIFT", "VIGOR", "WARD", "FORTUNE"]
## Where each column of the stat table is centred.
const COL_RACE := 188.0
const COL_CLASS := 222.0
const COL_POINTS := 258.0
const COL_CARDS := 294.0
const COL_TOTAL := 328.0
const STAT_PANEL := Rect2(126, 60, 236, 96)
const STAT_ROW0 := 90.0
const STAT_ROW_H := 10.0
const PLUS_W := 16.0
const SOCKET_PANEL := Rect2(372, 60, 96, 96)
const PORTRAIT_PANEL := Rect2(12, 14, 104, 154)
const RECORD_PANEL := Rect2(12, 176, 104, 66)
const WEAPON_PANEL := Rect2(126, 166, 172, 76)
const TRAIT_PANEL := Rect2(306, 166, 162, 76)
## Icon sizes, px: a stat's (left of its label), the weapon's and the skill's (right end of their lines).
const STAT_ICON := 8
const GEAR_ICON := 12
const HEART_COL := Color("ff4d6d")
## The race trait said in words (Races.TR_* order).
const TRAIT_WORDS := [
	"EVERY RUN TEACHES THE HUMAN A LITTLE MORE. HE MENTIONS IT.",
	"THE ELF SEES XP COMING AND IT FLIES IN FROM FAR OFF.",
	"THE DWARF IS LOW AND HARD TO MOVE. THE HORDE SHOVES IN VAIN.",
	"THE ORC FIGHTS BEST ON THE EDGE OF DYING.",
]
## What each skill does, by Classes skill key.
const SKILL_WORDS := {
	"nova": "A BLAST ALL AROUND YOU.",
	"provoke": "THE HORDE WANTS YOU AND ONLY YOU. YOU TAKE NO DAMAGE FOR A WHILE.",
	"volley": "ROLL CLEAR, THEN FAN ARROWS BEHIND YOU.",
	"sanctuary": "HEALS EVERY STANDING HERO AND RAISES THE FALLEN NEAR YOU.",
	"aegis": "HEROES NEAR YOU TAKE NO DAMAGE FOR A WHILE.",
}
const SKILL_UNITS := {"radius": "PX", "taunt": "S", "safe": "S", "roll": "PX", "fan": "RAD", "heal": "HEARTS"}

var active := false
var sel := 0
var _prof: Profile
var _idx := 0
var _rows: Array[Rect2] = []
var _plus: Array[Rect2] = []


func open(profile: Profile, index: int) -> void:
	_prof = profile
	_idx = clampi(index, 0, profile.heroes.size() - 1)
	sel = 0
	active = true


func hero() -> Hero:
	return _prof.heroes[_idx]


## Spends one point on stat `st`, saves. False when nothing could be spent.
func spend(st: int) -> bool:
	if not hero().spend_point(st):
		Sfx.play("hurt", -8.0)
		return false
	Sfx.play("powerup", -4.0)
	save_now()
	return true


## Saves the profile, except in a scripted run (those never write player data).
static func save_now() -> void:
	if not Flags.is_scripted_run():
		Save.write()


static func tap_of(event: InputEvent) -> bool:
	return (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)


## A card-sized picture of a race and class in a thin gold border, or the plain stand-in when its file is missing.
static func draw_portrait(ci: CanvasItem, r: Rect2, race: int, cls: int, label: String = "") -> void:
	ci.draw_rect(r.grow(1), Occult.GOLD)
	ci.draw_rect(r, Color("0e0a14"))
	var key := "hero_%s_%s" % [Races.key(race), Classes.key(cls)]
	if not Art.draw(ci, GROUP, key, r):
		DialogueBox.draw_stand_in(ci, r, label)


## `n` small hearts in a row from `pos` (each 7 wide, 9 apart).
static func draw_hearts(ci: CanvasItem, pos: Vector2, n: int, col: Color = HEART_COL) -> void:
	var rows := ["0110110", "1111111", "1111111", "0111110", "0011100", "0001000"]
	for k: int in range(n):
		var o := pos + Vector2(k * 9, 0)
		for y: int in range(rows.size()):
			var row: String = rows[y]
			for x: int in range(row.length()):
				if row[x] == "1":
					ci.draw_rect(Rect2(o + Vector2(x, y), Vector2(1, 1)), col)


## Words wrapped to `width` px at font scale 1.
static func wrap_words(text: String, width: int) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	for w: String in text.split(" ", false):
		var tryl := w if line.is_empty() else line + " " + w
		if PixelFont.text_width(tryl) > width and not line.is_empty():
			out.append(line)
			line = w
		else:
			line = tryl
	if not line.is_empty():
		out.append(line)
	return out


## `text` cut to fit `width` px.
static func fit_text(text: String, width: int) -> String:
	while text.length() > 1 and PixelFont.text_width(text) > width:
		text = text.left(text.length() - 1)
	return text


## A number for the sheet: whole when it is, else one decimal.
static func num_text(v: float) -> String:
	return "%d" % int(v) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## The weapon's main numbers as a line: the spell's level 1 row, with class `cls`'s skin numbers when it is that
## class's weapon (Classes.SKINS dmg_mul, cd_mul; -1 or another spell: the row as it is).
static func weapon_line(spell: int, cls: int = -1) -> String:
	var sk := Classes.weapon_skin(cls, spell) if cls >= 0 else ""
	return "DMG %s  CD %sS  SHOTS %d" % [num_text(Spells.damage(spell, 1, 0) * Classes.skin_value(sk, "dmg_mul", 1.0)),
		num_text(Spells.cooldown(spell, 1, 0) * Classes.skin_value(sk, "cd_mul", 1.0)), Spells.count(spell, 1, 0)]


## The skill's numbers as a line (empty for the nova, which has none).
static func skill_line(s: int) -> String:
	var parts: Array[String] = []
	var row: Dictionary = Classes.SKILLS[s]
	for k: String in row.keys():
		if k == "key" or k == "name":
			continue
		parts.append("%s %s%s" % [k.to_upper(), num_text(float(row[k])), String(SKILL_UNITS.get(k, ""))])
	return "  ".join(parts)


func update(_delta: float) -> void:
	pass


## Handles one input event. Returns true when the sheet closes.
func handle(event: InputEvent) -> bool:
	if not active:
		return false
	if PlayerInput.back_pressed(event):
		active = false
		Sfx.play("menu_select")
		return true
	var d := PlayerInput.menu_dir(event)
	if d != 0:
		sel = wrapi(sel + d, 0, Loot.STAT_COUNT)
		Sfx.play("menu_move")
		return false
	if event is InputEventMouseMotion:
		for k: int in range(_rows.size()):
			if _rows[k].has_point(event.position) and sel != k:
				sel = k
				Sfx.play("menu_move")
		return false
	if tap_of(event):
		for k: int in range(_rows.size()):
			if _plus[k].has_point(event.position):
				sel = k
				spend(k)
				return false
			if _rows[k].has_point(event.position):
				sel = k
		return false
	if PlayerInput.confirm_device(event) != -99:
		spend(sel)
	return false


func draw(ci: CanvasItem, t: float) -> void:
	if not active:
		return
	var h := hero()
	if not Still.draw_scene(ci, "sheet"):
		ci.draw_rect(Rect2(0, 0, 480, 270), Color(0.02, 0.0, 0.05, 0.94))
	Occult.frame(ci, Rect2(4, 4, 472, 262), t)
	Still.draw_scene(ci, "sheet", Still.SCENE_INNER)
	# Left: the portrait and the records.
	Occult.frame(ci, PORTRAIT_PANEL, t, false)
	draw_portrait(ci, PORTRAIT_PANEL.grow(-3), h.race, h.cls, h.name)
	Occult.frame(ci, RECORD_PANEL, t, false)
	PixelFont.draw_centered(ci, "RECORD", RECORD_PANEL.get_center().x, RECORD_PANEL.position.y + 7, 1, Occult.GOLD, Occult.INK)
	PixelFont.draw(ci, "RUNS %d" % _prof.runs, RECORD_PANEL.position + Vector2(10, 23), 1, Occult.BONE, Occult.INK)
	PixelFont.draw(ci, "WINS %d" % _prof.wins, RECORD_PANEL.position + Vector2(10, 37), 1, Occult.BONE, Occult.INK)
	PixelFont.draw(ci, "CARDS %d" % _prof.cards_owned(), RECORD_PANEL.position + Vector2(10, 51), 1, Occult.DIM, Occult.INK)
	# Header: name, level, race, class and role, the XP bar and the hearts.
	PixelFont.draw(ci, h.name, Vector2(128, 16), 2, Occult.GOLD, Occult.INK)
	var lv := "LV %d" % h.level
	PixelFont.draw(ci, lv, Vector2(128 + PixelFont.text_width(h.name, 2) + 12, 16), 2, Occult.BONE, Occult.INK)
	PixelFont.draw(ci, "%s %s  -  %s" % [Races.race_name(h.race), Classes.class_name_of(h.cls),
		Classes.ROLE_NAMES[Classes.role(h.cls)]], Vector2(128, 34), 1, Occult.DIM, Occult.INK)
	var bar := Rect2(128, 46, 150, 8)
	ci.draw_rect(bar.grow(1), Occult.INK)
	ci.draw_rect(bar, Color("1a0f2e"))
	var maxed := h.level >= Hero.MAX_LEVEL
	var need := Hero.xp_to_next(h.level)
	var frac := 1.0 if maxed else clampf(float(h.xp) / float(need), 0.0, 1.0)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Occult.VIOLET)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, 1)), Color(1, 1, 1, 0.35))
	PixelFont.draw(ci, "MAX LEVEL" if maxed else "XP %d/%d" % [h.xp, need], Vector2(286, 46), 1, Occult.BONE, Occult.INK)
	PixelFont.draw(ci, "HEARTS", Vector2(380, 20), 1, Occult.GOLD, Occult.INK)
	draw_hearts(ci, Vector2(380, 32), Classes.hearts(h.cls))
	_draw_stats(ci, h, t)
	_draw_sockets(ci, h, t)
	_draw_gear(ci, h, t)
	var key := "ENTER" if G.local_devices.is_empty() or G.local_devices[0] == G.DEV_KBM else "A"
	PixelFont.draw_centered(ci, "UP/DOWN: STAT   %s: SPEND A POINT   ESC/B: BACK" % key, 240, 250, 1, Color(1, 1, 1, 0.5), Occult.INK)


func _draw_stats(ci: CanvasItem, h: Hero, t: float) -> void:
	var r := STAT_PANEL
	Occult.frame(ci, r, t, false)
	PixelFont.draw(ci, "STATS", r.position + Vector2(6, 6), 1, Occult.GOLD, Occult.INK)
	var left := h.points_left()
	var ptxt := "POINTS LEFT %d" % left
	PixelFont.draw(ci, ptxt, Vector2(r.end.x - 6 - PixelFont.text_width(ptxt), r.position.y + 6), 1,
		Color("5dff7a") if left > 0 else Occult.DIM, Occult.INK)
	var hy := r.position.y + 18
	for c: Array in [["RACE", COL_RACE], ["CLASS", COL_CLASS], ["SPENT", COL_POINTS], ["CARDS", COL_CARDS], ["TOTAL", COL_TOTAL]]:
		PixelFont.draw_centered(ci, String(c[0]), float(c[1]), hy, 1, Occult.DIM, Occult.INK)
	var rp: Array = Races.stat_points(h.race)
	var cp: Array = Classes.stat_points(h.cls)
	var card: Array = Cards.socket_stats(h.socket_indices())
	_rows.clear()
	_plus.clear()
	for st: int in range(Loot.STAT_COUNT):
		var y := STAT_ROW0 + st * STAT_ROW_H
		var row := Rect2(r.position.x + 4, y - 2, r.size.x - 8, STAT_ROW_H)
		_rows.append(row)
		var pl := Rect2(row.end.x - PLUS_W - 2, row.position.y, PLUS_W, STAT_ROW_H)
		_plus.append(pl)
		if st == sel:
			Occult.highlight(ci, row, t)
		var cards_pts := roundi(float(card[st]) / float(Hero.POINT_VALUE[st]))
		var total := int(rp[st]) + int(cp[st]) + h.points[st] + cards_pts
		var sti := Still.icon(Still.stat_icon(st), STAT_ICON)
		var lx := r.position.x + 8
		if sti != null:
			ci.draw_texture(sti, Vector2(lx, y - 1).floor())
			lx += STAT_ICON + 2
		PixelFont.draw(ci, String(STAT_LABELS[st]), Vector2(lx, y), 1, Occult.BONE, Occult.INK)
		var vals := [int(rp[st]), int(cp[st]), h.points[st], cards_pts]
		var cols := [COL_RACE, COL_CLASS, COL_POINTS, COL_CARDS]
		for k: int in range(4):
			var v: int = vals[k]
			PixelFont.draw_centered(ci, "-" if v == 0 else str(v), float(cols[k]), y, 1,
				Occult.DIM if v == 0 else Occult.BONE, Occult.INK)
		PixelFont.draw_centered(ci, str(total), COL_TOTAL, y, 1, Occult.GOLD, Occult.INK)
		var can := left > 0 and h.points[st] < Hero.MAX_POINTS
		ci.draw_rect(pl.grow(-1), Color(Color("5dff7a"), 0.25 if can else 0.06))
		PixelFont.draw_centered(ci, "+", pl.get_center().x, y, 1, Color("5dff7a") if can else Color(1, 1, 1, 0.25), Occult.INK)


func _draw_sockets(ci: CanvasItem, h: Hero, t: float) -> void:
	var r := SOCKET_PANEL
	Occult.frame(ci, r, t, false)
	PixelFont.draw_centered(ci, "CARD SOCKETS", r.get_center().x, r.position.y + 6, 1, Occult.GOLD, Occult.INK)
	var idx := h.socket_indices()
	for s: int in range(Cards.SOCKETS):
		var col: Color = MonsterCard.SOCKET_COLORS[s]
		var box := Rect2(r.position.x + 6, r.position.y + 20 + s * 25, r.size.x - 12, 22)
		ci.draw_rect(box, Color(col, 0.08))
		ci.draw_rect(box, Color(col, 0.6), false, 1.0)
		PixelFont.draw(ci, String(Cards.SOCKET_NAMES[s]), box.position + Vector2(4, 3), 1, col, Occult.INK)
		if idx[s] >= 0:
			PixelFont.draw(ci, fit_text(Cards.card_name(idx[s]).trim_prefix("THE "), int(box.size.x) - 8),
				box.position + Vector2(4, 13), 1, Color.WHITE, Occult.INK)
		else:
			PixelFont.draw(ci, "EMPTY", box.position + Vector2(4, 13), 1, Color(1, 1, 1, 0.3), Occult.INK)


func _draw_gear(ci: CanvasItem, h: Hero, t: float) -> void:
	var r := WEAPON_PANEL
	Occult.frame(ci, r, t, false)
	var w := h.weapon()
	var x := r.position.x + 6
	var wid := int(r.size.x) - 12
	PixelFont.draw(ci, "WEAPON", Vector2(x, r.position.y + 6), 1, Occult.GOLD, Occult.INK)
	var wtex := Still.weapon_tex(h.cls, w, GEAR_ICON)
	var skill_tex := Still.icon(Still.skill_icon(Classes.skill(h.cls)), GEAR_ICON)
	var name_w := wid - 44 - (GEAR_ICON + 2 if wtex != null else 0)
	PixelFont.draw(ci, fit_text(Classes.weapon_name(h.cls, h.school), name_w), Vector2(x + 44, r.position.y + 6), 1, Occult.BONE, Occult.INK)
	if wtex != null:
		ci.draw_texture(wtex, Vector2(x + wid - GEAR_ICON, r.position.y + 3).floor())
	PixelFont.draw(ci, weapon_line(w, h.cls), Vector2(x, r.position.y + 17), 1, Occult.DIM, Occult.INK)
	var s := Classes.skill(h.cls)
	var sy := r.position.y + 32
	PixelFont.draw(ci, "SKILL", Vector2(x, sy), 1, Occult.GOLD, Occult.INK)
	PixelFont.draw(ci, Classes.skill_name(s), Vector2(x + 44, sy), 1, Occult.BONE, Occult.INK)
	if skill_tex != null:
		ci.draw_texture(skill_tex, Vector2(x + wid - GEAR_ICON, sy - 3).floor())
	var y := sy + 11
	for line: String in wrap_words(String(SKILL_WORDS.get(Classes.skill_key(s), "")), wid):
		PixelFont.draw(ci, line, Vector2(x, y), 1, Occult.DIM, Occult.INK)
		y += 10
	var nums := skill_line(s)
	if not nums.is_empty():
		PixelFont.draw(ci, fit_text(nums, wid), Vector2(x, y), 1, Color("c9b8ff"), Occult.INK)
	var tr := TRAIT_PANEL
	Occult.frame(ci, tr, t, false)
	PixelFont.draw(ci, "RACE TRAIT", Vector2(tr.position.x + 6, tr.position.y + 6), 1, Occult.GOLD, Occult.INK)
	var ty := tr.position.y + 17
	var twid := int(tr.size.x) - 12
	for line: String in wrap_words(Races.trait_name(Races.trait_of(h.race)), twid):
		PixelFont.draw(ci, line, Vector2(tr.position.x + 6, ty), 1, Color("5dff7a"), Occult.INK)
		ty += 10
	ty += 4
	for line: String in wrap_words(String(TRAIT_WORDS[Races.trait_of(h.race)]), twid):
		PixelFont.draw(ci, line, Vector2(tr.position.x + 6, ty), 1, Occult.DIM, Occult.INK)
		ty += 10

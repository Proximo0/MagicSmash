class_name HeroBuilder
extends RefCounted
## The hero builder: RACE, CLASS, SCHOOL (a mage's starting spell; other classes skip it), NAME on the Ouija board,
## then a page to confirm. The painted portrait of the current race and class stands on the left, the choices on the
## right with what the highlighted one gives. Confirm adds the hero to the profile, makes it the active one and saves.
## Back steps back; back on the first step closes. Opened by the hero roster (the Sanctum's mirror).

const S_RACE := 0
const S_CLASS := 1
const S_SCHOOL := 2
const S_NAME := 3
const S_CONFIRM := 4
const TITLES := ["CHOOSE YOUR RACE", "CHOOSE YOUR CLASS", "CHOOSE YOUR SCHOOL", "NAME THE HERO", "THE MIRROR WAITS"]
const NAME_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

const PORTRAIT_PANEL := Rect2(12, 30, 108, 156)
const SO_FAR_PANEL := Rect2(12, 196, 108, 44)
const LIST_PANEL := Rect2(130, 30, 116, 206)
const DETAIL_PANEL := Rect2(254, 30, 214, 206)
const BOARD := Rect2(130, 30, 338, 206)
const ROW_H := 32.0
## The class and race icon at the right of a list row, px.
const ROW_ICON := 14.0
const ROW_TOP := 24.0
## The weapon's and the skill's icons (class step), px: at the right end of their lines; a stat's, on the confirm page.
const LINE_ICON := 10
const STAT_ICON := 8
const BACK_RECT := Rect2(12, 244, 52, 16)
const CREATE_RECT := Rect2(330, 210, 130, 20)

## How each class plays, in a line.
const PLAY_CLASS := {
	"mage": "GLASS CANNON. YOU CHOOSE THE SPELLS; THE HEARTS ARE NOT YOURS TO CHOOSE. STAND BEHIND SOMEONE BRAVE.",
	"knight": "STAND IN THE DOORWAY AND BE HIT. PROVOKE MAKES THE HORDE ADORE YOU. FRIENDS WILL SEND FLOWERS.",
	"archer": "FAST, FRAGILE, NEVER WHERE THE CLAWS ARE. THE VOLLEY ROLLS YOU CLEAR AND PAYS BACK IN ARROWS.",
	"priest": "THE HORDE IGNORES YOU, WHICH IS THE POINT. RAISES THE FALLEN TWICE AS FAST. SANCTUARY MENDS ALL.",
	"paladin": "HALF WALL, HALF LAMP. AN AURA OF WARD COVERS THE NEIGHBOURS AND AEGIS COVERS THE REST.",
}
## How each race plays, and its short tag for the list.
const PLAY_RACE := {
	"human": "ADAPTABLE, WHICH MEANS UNREMARKABLE. LEARNS A LITTLE FASTER THAN THE REST AND SAYS SO.",
	"elf": "QUICK, CLEVER AND SLIGHTLY SMUG. THE XP SEES YOU COMING AND FLIES IN FROM FAR OFF.",
	"dwarf": "LOW TO THE GROUND AND HARD TO MOVE. THE HORDE'S SHOVING BARELY COUNTS.",
	"orc": "STRONG, ANGRY, A LITTLE BEHIND ON THE READING. THE CLOSER TO DEATH, THE HARDER THE HIT.",
}
const TAG_RACE := {"human": "ALL-ROUNDER", "elf": "QUICK CASTER", "dwarf": "HARD TO MOVE", "orc": "HITS HARD"}
## How each school plays (Wizards order).
const PLAY_SCHOOL := [
	"THE HONEST CHOICE. A STRAIGHT BOLT THAT GOES WHERE YOU POINT.",
	"EVERYTHING NEAR THE TARGET REGRETS IT. THAT INCLUDES YOUR PLANS.",
	"A COLD CONE THAT SLOWS THE HORDE SO THE REST OF YOU CAN LEAVE.",
	"ONE ZAP, MANY VICTIMS. BEST WHEN THE HORDE STANDS CLOSE TOGETHER.",
]

var active := false
var made: Hero = null
var step := S_RACE
var race := Races.HUMAN
var cls := Classes.MAGE
var school := 0
var sel := 0
var ouija := Ouija.new(NAME_CHARS, Hero.NAME_MAX)
var _prof: Profile
var _device := -99
var _rows: Array[Rect2] = []
var _planchette := Vector2.ZERO
var _t := 0.0
var _y := 0.0


func open(profile: Profile, device: int = -99) -> void:
	_prof = profile
	_device = device
	made = null
	race = Races.HUMAN
	cls = Classes.MAGE
	school = 0
	step = S_RACE
	sel = 0
	ouija = Ouija.new(NAME_CHARS, Hero.NAME_MAX)
	active = true


# ============================================================== STEPS ===
## The step after `s` for class `c`: the school is only for a mage.
static func next_step(s: int, c: int) -> int:
	if s == S_CLASS and c != Classes.MAGE:
		return S_NAME
	return mini(s + 1, S_CONFIRM)


static func prev_step(s: int, c: int) -> int:
	if s == S_NAME and c != Classes.MAGE:
		return S_CLASS
	return maxi(s - 1, S_RACE)


func choice_count() -> int:
	match step:
		S_RACE:
			return Races.count()
		S_CLASS:
			return Classes.count()
		S_SCHOOL:
			return Wizards.count()
	return 0


## The stored choice of a list step (the cursor lands on it when the step is entered).
func _stored(s: int) -> int:
	match s:
		S_RACE:
			return race
		S_CLASS:
			return cls
		S_SCHOOL:
			return school
	return 0


func _go(s: int) -> void:
	step = s
	sel = _stored(s)
	if s == S_NAME:
		_planchette = _opos(ouija.row, ouija.col)


## Takes choice `i` of the current list step and moves on.
func choose(i: int) -> void:
	match step:
		S_RACE:
			race = clampi(i, 0, Races.count() - 1)
		S_CLASS:
			cls = clampi(i, 0, Classes.count() - 1)
		S_SCHOOL:
			school = clampi(i, 0, Wizards.count() - 1)
		_:
			return
	Sfx.play("menu_select")
	_go(next_step(step, cls))


## Sets the name (from the board's YES) and goes to the confirm page.
func submit_name() -> void:
	Sfx.play("powerup", -4.0)
	_go(S_CONFIRM)


## One step back. True when that closed the builder (back on the first step).
func retreat() -> bool:
	Sfx.play("menu_select")
	if step == S_RACE:
		active = false
		return true
	_go(prev_step(step, cls))
	return false


## Makes the hero, adds it to the profile as the active one, saves and closes. False when the profile is full.
func finish() -> bool:
	var h := Hero.make(race, cls, school if cls == Classes.MAGE else 0, ouija.text)
	if not _prof.add_hero(h):
		Sfx.play("hurt", -6.0)
		return false
	made = h
	HeroSheet.save_now()
	Sfx.play("wave_clear", -4.0, 1.3)
	active = false
	return true


func update(delta: float) -> void:
	_t += delta
	if active and step == S_NAME:
		_planchette = _planchette.lerp(_opos(ouija.row, ouija.col), minf(1.0, delta * 14.0))


# ============================================================== INPUT ===
## Handles one input event. Returns true when the builder closed on it (made a hero, or backed out).
func handle(event: InputEvent) -> bool:
	if not active:
		return false
	var tap := HeroSheet.tap_of(event)
	if tap and BACK_RECT.has_point(event.position):
		return retreat()
	if step == S_NAME:
		_name_input(event, tap)
		return not active
	if PlayerInput.back_pressed(event):
		return retreat()
	if step == S_CONFIRM:
		if PlayerInput.confirm_device(event) != -99 or (tap and CREATE_RECT.has_point(event.position)):
			finish()
		return not active
	var d := PlayerInput.menu_dir(event)
	if d != 0:
		sel = wrapi(sel + d, 0, choice_count())
		Sfx.play("menu_move")
		return false
	if event is InputEventMouseMotion:
		for k: int in range(_rows.size()):
			if _rows[k].has_point(event.position) and sel != k:
				sel = k
				Sfx.play("menu_move")
		return false
	if tap:
		for k: int in range(_rows.size()):
			if _rows[k].has_point(event.position):
				if sel == k:
					choose(k)
				else:
					sel = k
					Sfx.play("menu_move")
		return false
	if PlayerInput.confirm_device(event) != -99:
		choose(sel)
	return false


func _name_input(event: InputEvent, tap: bool) -> void:
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
				_name_result(ouija.enter())
				return
			KEY_ESCAPE:
				retreat()
				return
	if PlayerInput.back_pressed(event):
		retreat()
		return
	var dy := PlayerInput.menu_dir(event)
	var dx := int(PlayerInput.menu_side(event)[1])
	if dx != 0 or dy != 0:
		ouija.move(dx, dy)
		Sfx.play("planchette")
		return
	if event is InputEventMouseMotion:
		var hv := _ohit(event.position)
		if hv.x >= 0 and (hv.x != ouija.row or hv.y != ouija.col) and ouija.point_at(hv.x, hv.y):
			Sfx.play("planchette", -6.0)
		return
	if tap:
		var hit := _ohit(event.position)
		if hit.x < 0 or not ouija.point_at(hit.x, hit.y):
			return
	elif PlayerInput.confirm_device(event) == -99:
		return
	_name_result(ouija.choose())


func _name_result(r: int) -> void:
	match r:
		Ouija.TYPED, Ouija.ERASED:
			Sfx.play("menu_select")
		Ouija.SUBMIT:
			submit_name()
		Ouija.CANCEL:
			retreat()


## Where a mark of the board sits.
func _opos(r: int, c: int) -> Vector2:
	var cx := BOARD.get_center().x
	var n: int = Ouija.LAYOUT[r].size()
	match r:
		0:
			return Vector2(cx - 110.0 if c == 0 else cx + 110.0, 92)
		1, 2:
			var u := float(c) / (n - 1) * 2.0 - 1.0
			var arc := 8.0 if r == 1 else 6.0
			return Vector2(cx + u * 140.0, (118.0 if r == 1 else 144.0) - arc * (1.0 - u * u))
		3:
			return Vector2(cx - 110.0 + c * 22.0, 172)
	return Vector2(cx, 200)


func _ohit(p: Vector2) -> Vector2i:
	for r: int in range(Ouija.LAYOUT.size()):
		for c: int in range(Ouija.LAYOUT[r].size()):
			var m: String = Ouija.LAYOUT[r][c]
			var half := Vector2(maxf(9.0, PixelFont.text_width(m, 2) / 2.0 + 3.0), 10.0)
			var o := _opos(r, c)
			if absf(p.x - o.x) <= half.x and absf(p.y - o.y) <= half.y:
				return Vector2i(r, c)
	return Vector2i(-1, -1)


# ============================================================== TEXT ===
## "MIGHT +3  VIGOR +4": the non-zero stats of a six-value stat row.
static func stat_line(points: Array) -> String:
	var parts: Array[String] = []
	for st: int in range(Loot.STAT_COUNT):
		if int(points[st]) != 0:
			parts.append("%s %+d" % [HeroSheet.STAT_LABELS[st], int(points[st])])
	return "  ".join(parts) if not parts.is_empty() else "NO STAT POINTS"


## The race's and the class's stat points added up.
static func combined_points(r: int, c: int) -> Array:
	var rp: Array = Races.stat_points(r)
	var cp: Array = Classes.stat_points(c)
	var out: Array = []
	for st: int in range(Loot.STAT_COUNT):
		out.append(int(rp[st]) + int(cp[st]))
	return out


# ============================================================== DRAW ===
func draw(ci: CanvasItem, t: float) -> void:
	if not active:
		return
	if not Still.draw_scene(ci, "builder"):
		ci.draw_rect(Rect2(0, 0, 480, 270), Color(0.02, 0.0, 0.05, 0.94))
	Occult.frame(ci, Rect2(4, 4, 472, 262), t)
	Still.draw_scene(ci, "builder", Still.SCENE_INNER)
	PixelFont.draw_centered(ci, String(TITLES[step]), 240, 10, 2, Occult.GOLD, Occult.INK)
	var order: Array[int] = [S_RACE, S_CLASS, S_NAME, S_CONFIRM]
	if cls == Classes.MAGE:
		order.insert(2, S_SCHOOL)
	var pos := order.find(step) + 1
	var total := order.size()
	# Left: the portrait of the current race and class, and what is chosen so far.
	var pr := race
	var pc := cls
	if step == S_RACE:
		pr = sel
	elif step == S_CLASS:
		pc = sel
	Occult.frame(ci, PORTRAIT_PANEL, t, false)
	HeroSheet.draw_portrait(ci, PORTRAIT_PANEL.grow(-3), pr, pc, Races.race_name(pr))
	_draw_so_far(ci, t, pr, pc)
	match step:
		S_NAME:
			_draw_board(ci, t)
		S_CONFIRM:
			_draw_confirm(ci, t)
		_:
			_draw_list(ci, t)
			_draw_detail(ci, t)
	var key := "ENTER" if _device == -99 or _device == G.DEV_KBM else "A"
	var hint := "UP/DOWN: LOOK   %s: CHOOSE   ESC/B: BACK" % key
	if step == S_NAME:
		hint = "ARROWS + %s: SPELL   YES: DONE   NO: RUB OUT   ESC/B: BACK" % key
	elif step == S_CONFIRM:
		hint = "%s: CREATE THE HERO   ESC/B: BACK" % key
	PixelFont.draw_centered(ci, hint, 252, 250, 1, Color(1, 1, 1, 0.5), Occult.INK)
	PixelFont.draw(ci, "< BACK", BACK_RECT.position + Vector2(4, 5), 1, Occult.DIM, Occult.INK)
	var stp := "STEP %d/%d" % [pos, total]
	PixelFont.draw(ci, stp, Vector2(468 - PixelFont.text_width(stp), 14), 1, Occult.DIM, Occult.INK)


func _draw_so_far(ci: CanvasItem, t: float, pr: int, pc: int) -> void:
	var r := SO_FAR_PANEL
	Occult.frame(ci, r, t, false)
	PixelFont.draw(ci, Races.race_name(pr), r.position + Vector2(8, 8), 1, Occult.BONE, Occult.INK)
	PixelFont.draw(ci, Classes.class_name_of(pc), r.position + Vector2(8, 19), 1, Occult.GOLD, Occult.INK)
	if pc == Classes.MAGE and step >= S_SCHOOL:
		var sc := school if step != S_SCHOOL else sel
		PixelFont.draw(ci, Wizards.title(sc), r.position + Vector2(8, 30), 1, Occult.DIM, Occult.INK)
	elif step >= S_CONFIRM and not ouija.text.is_empty():
		PixelFont.draw(ci, HeroSheet.fit_text(ouija.text, 92), r.position + Vector2(8, 30), 1, Occult.DIM, Occult.INK)


func _draw_list(ci: CanvasItem, t: float) -> void:
	var r := LIST_PANEL
	Occult.frame(ci, r, t, false)
	var head: String = ["RACES", "CLASSES", "SCHOOLS"][step]
	PixelFont.draw_centered(ci, head, r.get_center().x, r.position.y + 8, 1, Occult.GOLD, Occult.INK)
	_rows.clear()
	for k: int in range(choice_count()):
		var row := Rect2(r.position.x + 5, r.position.y + ROW_TOP + k * ROW_H, r.size.x - 10, ROW_H - 4)
		_rows.append(row)
		if k == sel:
			Occult.highlight(ci, row, t)
			Occult.cursor(ci, Vector2(row.position.x + 7, row.get_center().y), t)
		var name_text := ""
		var sub := ""
		var icon := ""
		match step:
			S_RACE:
				icon = "race_" + Races.key(k)
				name_text = Races.race_name(k)
				sub = String(TAG_RACE[Races.key(k)])
			S_CLASS:
				icon = "class_" + Classes.key(k)
				name_text = Classes.class_name_of(k)
				sub = String(Classes.ROLE_NAMES[Classes.role(k)])
			S_SCHOOL:
				name_text = Wizards.title(k)
				sub = Spells.spell_name(Wizards.start_spell(k))
		if not icon.is_empty():
			Still.draw_icon(ci, icon, Rect2(row.end.x - ROW_ICON - 2, row.position.y + 1, ROW_ICON, ROW_ICON))
		PixelFont.draw(ci, name_text, Vector2(row.position.x + 16, row.position.y + 6), 1,
			Occult.GOLD if k == sel else Occult.BONE, Occult.INK)
		PixelFont.draw(ci, sub, Vector2(row.position.x + 16, row.position.y + 16), 1, Occult.DIM, Occult.INK)


## An icon at the right end of the line `_line` draws next (a picture shown only where it exists).
func _line_icon(ci: CanvasItem, tex: Texture2D) -> void:
	if tex != null:
		ci.draw_texture(tex, Vector2(DETAIL_PANEL.end.x - 8 - LINE_ICON, _y - 1).floor())


func _line(ci: CanvasItem, label: String, text: String, col: Color) -> void:
	var x := DETAIL_PANEL.position.x + 8
	var wid := int(DETAIL_PANEL.size.x) - 16
	var lw := 0
	if not label.is_empty():
		PixelFont.draw(ci, label, Vector2(x, _y), 1, Occult.GOLD, Occult.INK)
		lw = PixelFont.text_width(label) + 8
	var lines := HeroSheet.wrap_words(text, wid - lw)
	for k: int in range(lines.size()):
		PixelFont.draw(ci, lines[k], Vector2(x + lw, _y), 1, col, Occult.INK)
		_y += 10
	if lines.is_empty():
		_y += 10
	_y += 2


func _draw_detail(ci: CanvasItem, t: float) -> void:
	var r := DETAIL_PANEL
	Occult.frame(ci, r, t, false)
	var x := r.position.x + 8
	_y = r.position.y + 10
	match step:
		S_RACE:
			PixelFont.draw(ci, Races.race_name(sel), Vector2(x, _y), 2, Occult.GOLD, Occult.INK)
			_y += 20
			_line(ci, "GIVES", stat_line(Races.stat_points(sel)), Color("5dff7a"))
			_line(ci, "TRAIT", Races.trait_name(Races.trait_of(sel)), Occult.BONE)
			_y += 4
			_line(ci, "", String(PLAY_RACE[Races.key(sel)]), Occult.DIM)
		S_CLASS:
			PixelFont.draw(ci, Classes.class_name_of(sel), Vector2(x, _y), 2, Occult.GOLD, Occult.INK)
			_y += 20
			_line(ci, "GIVES", stat_line(Classes.stat_points(sel)), Color("5dff7a"))
			PixelFont.draw(ci, "HEARTS", Vector2(x, _y), 1, Occult.GOLD, Occult.INK)
			HeroSheet.draw_hearts(ci, Vector2(x + 42, _y), Classes.hearts(sel))
			_y += 12
			_line(ci, "ROLE", String(Classes.ROLE_NAMES[Classes.role(sel)]), Occult.BONE)
			var wp := "THE SPELL OF YOUR SCHOOL" if Classes.weapon(sel) == Classes.SCHOOL_WEAPON else \
				Classes.weapon_name(sel)
			if Classes.weapon(sel) != Classes.SCHOOL_WEAPON: # a mage's weapon is her school's spell: no icon yet
				_line_icon(ci, Still.weapon_tex(sel, Classes.weapon(sel), LINE_ICON))
			_line(ci, "WEAPON", wp, Occult.BONE)
			_line_icon(ci, Still.icon(Still.skill_icon(Classes.skill(sel)), LINE_ICON))
			_line(ci, "SKILL", Classes.skill_name(Classes.skill(sel)), Occult.BONE)
			_y += 4
			_line(ci, "", String(PLAY_CLASS[Classes.key(sel)]), Occult.DIM)
		S_SCHOOL:
			var sp := Wizards.start_spell(sel)
			PixelFont.draw(ci, Spells.spell_name(sp), Vector2(x, _y), 2, Occult.GOLD, Occult.INK)
			_y += 20
			_line(ci, "SCHOOL", Wizards.title(sel), Occult.BONE)
			_line(ci, "STATS", HeroSheet.weapon_line(sp), Color("5dff7a"))
			_y += 4
			_line(ci, "", String(PLAY_SCHOOL[sel]), Occult.DIM)


func _draw_confirm(ci: CanvasItem, t: float) -> void:
	var r := Rect2(LIST_PANEL.position.x, 30, 338, 206)
	Occult.frame(ci, r, t, false)
	var x := r.position.x + 10
	var nm := Hero.clean_name(ouija.text)
	PixelFont.draw(ci, nm, Vector2(x, 42), 3, Occult.GOLD, Occult.INK)
	var hero_line := "%s %s" % [Races.race_name(race), Classes.class_name_of(cls)]
	if cls == Classes.MAGE:
		hero_line += "  -  " + Wizards.title(school)
	PixelFont.draw(ci, hero_line, Vector2(x, 70), 1, Occult.BONE, Occult.INK)
	var pts := combined_points(race, cls)
	for st: int in range(Loot.STAT_COUNT):
		var sx := x + (st % 3) * 100
		var sy := 88.0 + (st / 3) * 12
		var sti := Still.icon(Still.stat_icon(st), STAT_ICON)
		var off := 0.0
		if sti != null:
			ci.draw_texture(sti, Vector2(sx, sy - 1).floor())
			off = STAT_ICON + 2.0
		PixelFont.draw(ci, String(HeroSheet.STAT_LABELS[st]), Vector2(sx + off, sy), 1, Occult.DIM, Occult.INK)
		PixelFont.draw(ci, str(pts[st]), Vector2(sx + 52 + off, sy), 1, Occult.BONE if int(pts[st]) > 0 else Color(1, 1, 1, 0.3), Occult.INK)
	PixelFont.draw(ci, "HEARTS", Vector2(x, 118), 1, Occult.GOLD, Occult.INK)
	HeroSheet.draw_hearts(ci, Vector2(x + 48, 117), Classes.hearts(cls))
	PixelFont.draw(ci, "WEAPON", Vector2(x, 130), 1, Occult.GOLD, Occult.INK)
	PixelFont.draw(ci, Classes.weapon_name(cls, school), Vector2(x + 48, 130), 1, Occult.BONE, Occult.INK)
	var wtex := Still.weapon_tex(cls, Classes.weapon(cls, school), LINE_ICON)
	if wtex != null:
		ci.draw_texture(wtex, Vector2(x + 48 + PixelFont.text_width(Classes.weapon_name(cls, school)) + 4, 129).floor())
	PixelFont.draw(ci, "SKILL", Vector2(x, 142), 1, Occult.GOLD, Occult.INK)
	PixelFont.draw(ci, Classes.skill_name(Classes.skill(cls)), Vector2(x + 48, 142), 1, Occult.BONE, Occult.INK)
	var ktex := Still.icon(Still.skill_icon(Classes.skill(cls)), LINE_ICON)
	if ktex != null:
		ci.draw_texture(ktex, Vector2(x + 48 + PixelFont.text_width(Classes.skill_name(Classes.skill(cls))) + 4, 141).floor())
	PixelFont.draw(ci, "TRAIT", Vector2(x, 154), 1, Occult.GOLD, Occult.INK)
	PixelFont.draw(ci, Races.trait_name(Races.trait_of(race)), Vector2(x + 48, 154), 1, Color("5dff7a"), Occult.INK)
	var y := 172.0
	for line: String in HeroSheet.wrap_words("THE MIRROR WILL KEEP THIS FACE. " + String(PLAY_CLASS[Classes.key(cls)]), 318):
		PixelFont.draw(ci, line, Vector2(x, y), 1, Occult.DIM, Occult.INK)
		y += 10
	ci.draw_rect(CREATE_RECT, Color(Occult.BLOOD, 0.35 + 0.15 * sin(t * 6.0)))
	ci.draw_rect(CREATE_RECT, Occult.BONE, false, 1.0)
	PixelFont.draw_centered(ci, "CREATE HERO", CREATE_RECT.get_center().x, CREATE_RECT.position.y + 8, 1, Occult.GOLD, Occult.INK)


func _draw_board(ci: CanvasItem, t: float) -> void:
	var board := BOARD
	var cx := board.get_center().x
	ci.draw_rect(board.grow(3), Occult.INK)
	ci.draw_rect(board, Color("3b2414"))
	ci.draw_rect(board.grow(-4), Color("6b4526"))
	for k: int in range(8):
		var gy := board.position.y + 12 + k * 25 + sin(k * 1.7) * 3.0
		ci.draw_rect(Rect2(board.position.x + 6, gy, board.size.x - 12, 1), Color(0.3, 0.17, 0.08, 0.35))
	Occult._box(ci, board.grow(-7), Color("2a170b"))
	var sun := Vector2(cx - 150, 92)
	ci.draw_circle(sun, 7, Color("2a170b"))
	for k: int in range(8):
		var a := k * TAU / 8.0
		ci.draw_line(sun + Vector2(cos(a), sin(a)) * 9, sun + Vector2(cos(a), sin(a)) * 12, Color("2a170b"), 1.0)
	var moon := Vector2(cx + 150, 92)
	ci.draw_circle(moon, 7, Color("2a170b"))
	ci.draw_circle(moon + Vector2(4, -2), 6, Color("6b4526"))
	PixelFont.draw_centered(ci, "WHAT IS THE HERO CALLED", cx, 40, 1, Color("2a170b"))
	for r: int in range(Ouija.LAYOUT.size()):
		for c: int in range(Ouija.LAYOUT[r].size()):
			var m: String = Ouija.LAYOUT[r][c]
			var p := _opos(r, c)
			var on := ouija.enabled(r, c)
			var col := Color("1c0f06") if on else Color(0.17, 0.09, 0.04, 0.35)
			if r == ouija.row and c == ouija.col:
				col = Color("fff0c8")
			PixelFont.draw_centered(ci, m, p.x, p.y - 7, 2, col)
	var slate := Rect2(cx - 80, 54, 160, 18)
	ci.draw_rect(slate, Color("1c0f06"))
	var shown := ouija.text + ("_" if int(t * 2.0) % 2 == 0 else " ")
	PixelFont.draw_centered(ci, shown, cx, slate.position.y + 5, 1, Occult.BONE)
	_draw_planchette_hb(ci, _planchette)


## The planchette: a heart-shaped pointer whose glass eye shows the chosen mark.
func _draw_planchette_hb(ci: CanvasItem, eye: Vector2) -> void:
	var c := eye + Vector2(0, 8)
	var body := PackedVector2Array([c + Vector2(0, -21), c + Vector2(17, -3), c + Vector2(13, 15), c + Vector2(0, 21),
		c + Vector2(-13, 15), c + Vector2(-17, -3)])
	var shadow := PackedVector2Array()
	for v: Vector2 in body:
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
		PixelFont.draw_centered(ci, m, eye.x, eye.y - 7, 2, Color("fff0c8"), Color("1c0f06"))

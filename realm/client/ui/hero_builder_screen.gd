class_name HeroBuilderScreen
extends UiScreen
## The hero builder: a race on the left, a class on the right, the hero between them with her look (a palette
## and a mark), her name on the ouija board. The gateway makes classes 1 to 5 (KNIGHT to PALADIN) at creation.

const NAME_MIN: int = 3
const NAME_MAX: int = 16

var board: OuijaBoard = OuijaBoard.new()
var race: int = 0
var cls: int = 1
var palette: int = 0
var mark: int = 0
var busy: bool = false


func opened() -> void:
	board.upper = true
	board.max_len = NAME_MAX
	board.entered.connect(func(_t: String) -> void: create())


func paint() -> void:
	UiKit.backdrop(self, time)
	UiKit.title(self, Vector2(UiKit.W / 2.0, 14), "A NEW HERO", 26)
	for r in 4:
		var rr := Rect2(30, 64 + r * 44, 220, 38)
		button("race:%d" % r, rr, GameNames.RACES[r], true, race == r, 16)
	UiKit.paragraph(self, Vector2(30, 244), GameNames.RACE_NOTES[race], 220.0, 12, UiKit.BONE_DIM)
	for c in 5:
		var cr := Rect2(710, 64 + c * 44, 220, 38)
		button("class:%d" % (c + 1), cr, GameNames.CLASSES[c + 1], true, cls == c + 1, 16)
	
	# The hero, on a plinth of rings.
	var c0 := Vector2(UiKit.W / 2.0, 132)
	draw_arc(c0 + Vector2(0, 50), 70.0, 0.0, TAU, 48, Color(UiKit.GOLD_DIM, 0.7), 1.0)
	draw_arc(c0 + Vector2(0, 50), 54.0, 0.0, TAU, 48, Color(UiKit.GOLD_DIM, 0.4), 1.0)
	UiArt.draw_hero(self, cls, race, c0, 120.0, GameNames.look_of(palette, mark))
	UiKit.text(self, Vector2(UiKit.W / 2.0, 200), "%s %s" % [GameNames.RACES[race], GameNames.CLASSES[cls]], 16, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	# Her look.
	button("pal:-1", Rect2(300, 232, 28, 26), "<", true, false, 14)
	UiKit.text(self, Vector2(380, 235), "SKIN  " + GameNames.LOOK_PALETTE_NAMES[palette], 13, UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
	button("pal:1", Rect2(432, 232, 28, 26), ">", true, false, 14)
	button("mark:-1", Rect2(500, 232, 28, 26), "<", true, false, 14)
	UiKit.text(self, Vector2(580, 235), "MARK  " + GameNames.LOOK_MARKS[mark], 13, UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
	button("mark:1", Rect2(632, 232, 28, 26), ">", true, false, 14)
	UiKit.text(self, Vector2(UiKit.W / 2.0, 268), "%s, %s. %s" % [GameNames.CLASS_WEAPONS[cls], GameNames.CLASS_ROLES[cls], GameNames.CLASS_NOTES[cls]], 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	board.paint(self, Rect2(130, 296, 700, 215))
	button("back", Rect2(20, UiKit.H - 52, 100, 34), "BACK")
	var ok: bool = _name_ok() and not busy
	button("create", Rect2(UiKit.W - 120, UiKit.H - 52, 110, 34), "BEGIN" if not busy else "...", ok, false, 16)


func _name_ok() -> bool:
	var s: String = board.text
	if s.length() < NAME_MIN or s.length() > NAME_MAX:
		return false
	var first: String = s[0]
	return first.to_upper() != first.to_lower()


func on_press(id: String) -> void:
	if board.press(id):
		return
	if id.begins_with("race:"):
		race = int(id.trim_prefix("race:"))
	elif id.begins_with("class:"):
		cls = int(id.trim_prefix("class:"))
	elif id.begins_with("pal:"):
		palette = posmod(palette + int(id.trim_prefix("pal:")), GameNames.LOOK_PALETTES.size())
	elif id.begins_with("mark:"):
		mark = posmod(mark + int(id.trim_prefix("mark:")), GameNames.LOOK_MARKS.size())
	elif id == "back":
		shell.show_base(HeroListScreen.new(), "hero_list")
	elif id == "create":
		create()


func on_key(e: InputEventKey) -> bool:
	if e.keycode == KEY_ESCAPE:
		shell.show_base(HeroListScreen.new(), "hero_list")
		return true
	return board.key(e)


func create() -> void:
	if busy:
		return
	if not _name_ok():
		say("A NAME IS 3 TO 16 LETTERS, DIGITS, ' AND -, FIRST A LETTER", true)
		return
	busy = true
	var err: String = await shell.create_hero(board.text, race, cls, GameNames.look_of(palette, mark))
	if not err.is_empty():
		busy = false
		say(err, true)
		return
	shell.show_base(HeroListScreen.new(), "hero_list")

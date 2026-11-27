class_name LoginScreen
extends UiScreen
## The dev login: a name spelled on the ouija board. No password (the gateway's --dev-login); Steam comes later.

const NAME_MIN: int = 3
const NAME_MAX: int = 16

var board: OuijaBoard = OuijaBoard.new()
var busy: bool = false


func opened() -> void:
	board.upper = true
	board.max_len = NAME_MAX
	board.entered.connect(_entered)
	# A themed name to start with, so ENTER at once will do.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	board.text = GameNames.themed_account(rng)
	# The last name used, so a returning player only says YES.
	var cf := ConfigFile.new()
	if cf.load("user://login.cfg") == OK and ShellSettings.persist:
		board.text = String(cf.get_value("login", "name", "")).to_upper()


func paint() -> void:
	UiKit.backdrop(self, time)
	UiKit.title(self, Vector2(UiKit.W / 2.0, 36), "WHO KNOCKS?", 30)
	UiKit.text(self, Vector2(UiKit.W / 2.0, 96), "Spell the name your account goes by.", 14, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	board.paint(self, Rect2(130, 150, 700, 215))
	button("back", Rect2(20, UiKit.H - 56, 110, 36), "BACK")
	var ready: bool = board.text.length() >= NAME_MIN and not busy
	button("go", Rect2(UiKit.W - 150, UiKit.H - 56, 130, 36), "KNOCK" if not busy else "...", ready, false, 16)
	if ready:
		UiKit.glow(self, Rect2(UiKit.W - 150, UiKit.H - 56, 130, 36), time)
	UiKit.text(self, Vector2(UiKit.W / 2.0, 384), "%d to %d letters or digits" % [NAME_MIN, NAME_MAX], 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)


func on_press(id: String) -> void:
	if board.press(id):
		return
	match id:
		"back":
			shell.show_base(TitleScreen.new(), "title")
		"go":
			_entered(board.text)


func on_key(e: InputEventKey) -> bool:
	if e.keycode == KEY_ESCAPE:
		shell.show_base(TitleScreen.new(), "title")
		return true
	return board.key(e)


func _entered(name: String) -> void:
	if busy:
		return
	if name.length() < NAME_MIN:
		say("A NAME IS AT LEAST %d LETTERS" % NAME_MIN, true)
		return
	busy = true
	var err: String = await shell.login(name)
	if err.is_empty():
		if ShellSettings.persist:
			var cf := ConfigFile.new()
			cf.set_value("login", "name", name)
			cf.save("user://login.cfg")
		return
	busy = false
	say(err, true)

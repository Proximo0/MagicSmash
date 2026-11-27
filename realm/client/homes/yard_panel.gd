class_name YardPanel
extends PanelBase
## The training yard's dummy: strike it (the button, or Space) as fast as the weapon swings, or let AUTO swing for
## her; the gateway keeps the pace and says her damage per second over the last ten seconds, and the board lists
## the best rounds.

const AUTO_S: float = 0.45

var last: Dictionary = {}
var rows: Array[Array] = []
var auto: bool = false
var _t: float = 0.0
var _flash: float = 0.0
var note: String = ""


func opened() -> void:
	title = "THE TRAINING DUMMY"
	frame_rect = Rect2(130, 50, 700, 440)
	await load_board()


func load_board() -> void:
	var r: Dictionary = await shell.link.call_req(HomeWire.hero_only(HomeWire.Q_YARD_BOARD, shell.hero_id()))
	if int(r["t"]) == HomeWire.R_HOME and int(r.get("k", -1)) == HomeWire.K_BOARD:
		rows = r["rows"]


func _process(delta: float) -> void:
	super(delta)
	_flash = maxf(0.0, _flash - delta)
	if auto and not busy:
		_t += delta
		if _t >= AUTO_S:
			_t = 0.0
			strike()


func strike() -> void:
	if busy:
		return
	busy = true
	var r: Dictionary = await shell.link.call_req(HomeWire.hero_only(HomeWire.Q_STRIKE, shell.hero_id()))
	if is_instance_valid(self):
		busy = false
		if int(r["t"]) == HomeWire.R_HOME and int(r.get("k", -1)) == HomeWire.K_STRIKE:
			last = r
			_flash = 0.15
			note = ""
			if int(r["best"]) > 0 and int(r["count"]) % 10 == 0:
				await load_board()
		elif int(r["t"]) == GwWire.R_ERR and int(r.get("code", 0)) == GwWire.E_SLOW_DOWN:
			note = "TOO FAST FOR THE WEAPON"
		elif int(r["t"]) == GwWire.R_ERR:
			note = Shell.error_text(r)


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y
	# The dummy: a post, a sack of straw, a painted target. It shudders when struck.
	var c := Vector2(x + 120, y + 150)
	var sh: float = sin(time * 60.0) * 5.0 * (_flash / 0.15) if _flash > 0.0 else 0.0
	draw_rect(Rect2(c.x - 8 + sh * 0.3, c.y - 10, 16, 150), Color(0.25, 0.17, 0.1))
	draw_rect(Rect2(c.x - 40 + sh, c.y - 90, 80, 100), Color(0.4, 0.33, 0.2))
	draw_rect(Rect2(c.x - 40 + sh, c.y - 90, 80, 100), UiKit.GOLD_DIM, false, 2.0)
	draw_arc(c + Vector2(sh, -40), 22.0, 0.0, TAU, 20, UiKit.BLOOD_BRIGHT, 3.0)
	draw_arc(c + Vector2(sh, -40), 10.0, 0.0, TAU, 14, UiKit.BLOOD_BRIGHT, 3.0)
	button("strike", Rect2(x + 40, y + 276, 160, 36), "STRIKE  [SPACE]", not busy, false, 14)
	button("auto", Rect2(x + 40, y + 318, 160, 30), "AUTO SWING: " + ("ON" if auto else "OFF"), true, auto, 13)
	UiKit.text(self, Vector2(x + 250, y), "DAMAGE A SECOND", 13, UiKit.GOLD)
	UiKit.text(self, Vector2(x + 250, y + 22), "%s" % GameNames.commas(int(last.get("dps", 0))), 44, UiKit.BONE)
	UiKit.text(self, Vector2(x + 250, y + 84), "LAST BLOW %s    BLOWS %d    TOTAL %s" % [GameNames.commas(int(last.get("damage", 0))), int(last.get("count", 0)), GameNames.commas(int(last.get("total", 0)))], 12, UiKit.BONE_DIM)
	UiKit.text(self, Vector2(x + 250, y + 104), "YOUR BEST FULL ROUND: %s" % GameNames.commas(int(last.get("best", 0))), 13, UiKit.GOOD)
	UiKit.text(self, Vector2(x + 250, y + 126), note, 12, UiKit.BAD)
	UiKit.text(self, Vector2(x + 250, y + 156), "THE BEST ROUNDS", 13, UiKit.GOLD)
	for i in mini(rows.size(), 10):
		var row: Array = rows[i]
		UiKit.text(self, Vector2(x + 250, y + 180 + i * 20.0), "%d  %s" % [i + 1, String(row[0])], 12, UiKit.BONE)
		UiKit.text(self, Vector2(x + 250 + 200, y + 180 + i * 20.0), GameNames.class_name_of(int(row[1])), 11, UiKit.BONE_DIM)
		UiKit.text(self, Vector2(inner.end.x, y + 180 + i * 20.0), GameNames.commas(int(row[2])), 12, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	if rows.is_empty():
		UiKit.text(self, Vector2(x + 250, y + 180), "No round has lasted 5 seconds yet.", 11, UiKit.BONE_DIM)


func press_body(id: String) -> void:
	match id:
		"strike":
			strike()
		"auto":
			auto = not auto


func key_body(e: InputEventKey) -> bool:
	if e.keycode == KEY_SPACE:
		strike()
		return true
	return false

class_name GatePanel
extends PanelBase
## The field gates: the six fields, their level ranges and bosses. ENTER asks the gateway for a ticket and hands
## the hero to the field client. Walking south out of a field's gate (or banking at a waystone) brings her back.

var _entering: bool = false


## The field her level suits best: the highest whose first level she has reached.
func fit_field() -> int:
	var level: int = int(shell.hero.get("level", 1))
	var best: int = 0
	for f in 6:
		if level >= GameNames.FIELD_LEVELS[f].x:
			best = f
	return best


func key_body(e: InputEventKey) -> bool:
	if (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER) and not _entering:
		press_body("field:%d" % fit_field())
		return true
	return false


func opened() -> void:
	title = "THE FIELD GATES"


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y - 6
	var level: int = int(shell.hero.get("level", 1))
	var ways: Array = shell.hero.get("waystones", [-1, -1, -1, -1, -1, -1])
	for f in 6:
		var ry: float = y + f * 62.0
		var r := Rect2(x, ry, inner.size.x, 56)
		draw_rect(r, Color(0.07, 0.058, 0.066))
		draw_rect(r, Color(UiKit.GOLD_DIM, 0.45), false, 1.0)
		UiKit.rune(self, Vector2(x + 12, ry + 14), f + 1, 28.0, UiKit.GOLD_DIM, 1.5)
		UiKit.text(self, Vector2(x + 60, ry + 6), GameNames.FIELDS[f], 18, UiKit.BONE)
		var lv: Vector2i = GameNames.FIELD_LEVELS[f]
		UiKit.text(self, Vector2(x + 60, ry + 32), "LEVELS %d TO %d    BOSS: %s" % [lv.x, lv.y, GameNames.FIELD_BOSSES[f]], 12, UiKit.BONE_DIM)
		var fit: String = "" if level >= lv.x else "A hard road for LEVEL %d" % level
		if not fit.is_empty():
			UiKit.text(self, Vector2(x + 520, ry + 20), fit, 12, UiKit.BAD)
		if int(ways[f]) >= 0:
			UiKit.text(self, Vector2(x + 520, ry + 36), "WAYSTONE %d KNOWN" % (int(ways[f]) + 1), 11, UiKit.GOOD)
		button("field:%d" % f, Rect2(r.end.x - 130, ry + 10, 118, 36), "ENTER", not _entering, false, 15)
		if f == fit_field() and not _entering:
			UiKit.glow(self, Rect2(r.end.x - 130, ry + 10, 118, 36), time)


func press_body(id: String) -> void:
	if not id.begins_with("field:"):
		return
	_entering = true
	var f: int = int(id.trim_prefix("field:"))
	var err: String = await shell.go_field(f)
	if not err.is_empty() and is_instance_valid(self):
		_entering = false
		say(err, true)

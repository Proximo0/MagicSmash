class_name OutingPanel
extends PanelBase
## What a field outing brought back, shown over the town when she walks in again: coin banked, XP, levels, potions
## drunk, and how she left (the gate, a waystone, a lost connection, a kick, a shutdown).

const LEFT: Array[String] = ["WALKED OUT OF THE GATE", "BANKED AT A WAYSTONE", "LOST THE CONNECTION: HALF THE COIN IS LOST", "WAS SENT HOME", "THE FIELD CLOSED"]

var outing: Dictionary = {}


func opened() -> void:
	title = "THE RETURN"
	frame_rect = Rect2(260, 120, 440, 280)


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y
	var left: int = int(outing.get("left", 0))
	UiKit.text(self, Vector2(inner.get_center().x, y), LEFT[left] if left < LEFT.size() else "LEFT THE FIELD", 14, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	var rows: Array = [["COIN BANKED", GameNames.commas(int(outing.get("coin", 0)))], ["XP", GameNames.commas(int(outing.get("xp", 0)))],
		["LEVELS", "+%d" % int(outing.get("levels", 0))], ["POTIONS DRUNK", str(int(outing.get("potions", 0)))]]
	for i in rows.size():
		UiKit.text(self, Vector2(x + 30, y + 40 + i * 30.0), String(rows[i][0]), 15, UiKit.BONE)
		UiKit.text(self, Vector2(inner.end.x - 30, y + 40 + i * 30.0), String(rows[i][1]), 17, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	button("close", Rect2(inner.get_center().x - 60, inner.end.y - 40, 120, 34), "ONWARD", true, false, 15)

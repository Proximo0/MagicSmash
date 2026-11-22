class_name StallsPanel
extends PanelBase
## The market square's stalls: every hero who has something listed, how many things and the cheapest price. The
## listings themselves are the market's (the merchants' screen buys); this is the square as a place.

var stalls: Array[Dictionary] = []
var loaded: bool = false


func opened() -> void:
	title = "THE STALLS"
	frame_rect = Rect2(180, 60, 600, 420)
	await reload()


func reload() -> void:
	var r: Dictionary = await shell.link.call_req(HomeWire.with_u32(HomeWire.Q_STALLS, shell.hero_id(), 0))
	if int(r["t"]) == HomeWire.R_HOME and int(r.get("k", -1)) == HomeWire.K_STALLS:
		stalls = r["stalls"]
	loaded = true


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y - 6
	UiKit.text(self, Vector2(x, y), "SELLER", 12, UiKit.GOLD)
	UiKit.text(self, Vector2(x + 300, y), "THINGS", 12, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.text(self, Vector2(inner.end.x, y), "CHEAPEST", 12, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in mini(stalls.size(), 14):
		var s: Dictionary = stalls[i]
		var r := Rect2(x, y + 22 + i * 24.0, inner.size.x, 22)
		draw_rect(r, Color(0.07, 0.06, 0.07))
		UiKit.text(self, r.position + Vector2(8, 3), String(s["seller"]), 13, UiKit.BONE)
		UiKit.text(self, Vector2(x + 300, r.position.y + 3), "%d" % int(s["listings"]), 13, UiKit.BONE, HORIZONTAL_ALIGNMENT_RIGHT)
		UiKit.text(self, Vector2(inner.end.x - 8, r.position.y + 3), "%s COIN" % GameNames.commas(int(s["cheapest"])), 13, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	if loaded and stalls.is_empty():
		UiKit.text(self, Vector2(x, y + 30), "NO ONE HAS A STALL OPEN", 13, UiKit.BONE_DIM)
	button("refresh", Rect2(x, inner.end.y - 40, 120, 30), "LOOK AGAIN", true, false, 13)


func press_body(id: String) -> void:
	if id == "refresh":
		await reload()

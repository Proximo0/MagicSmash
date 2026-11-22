class_name PlacesPanel
extends PanelBase
## The places list: the plaza, the tavern, the market square, the training yard, her guild's hall, the streets of
## houses and her own house. A click walks her there (the gateway moves her to that place's room).

var streets: Dictionary = {}


func opened() -> void:
	title = "PLACES"
	frame_rect = Rect2(210, 60, 540, 420)
	var r: Dictionary = await shell.link.call_req(HomeWire.hero_only(HomeWire.Q_STREETS, shell.hero_id()))
	if int(r["t"]) == HomeWire.R_HOME and int(r.get("k", -1)) == HomeWire.K_STREETS:
		streets = r


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y - 6
	var here: Array = shell.place
	var mine: int = int(streets.get("mine", -1))
	var rows: Array = [
		[HomeMap.PLAZA, 0, "THE PLAZA", true],
		[HomeMap.TAVERN, 0, "THE TAVERN", true],
		[HomeMap.MARKET, 0, "THE MARKET SQUARE", true],
		[HomeMap.YARD, 0, "THE TRAINING YARD", true],
		[HomeMap.GUILD_HALL, 0, "THE GUILD HALL" if not shell.guild.is_empty() else "THE GUILD HALL (NO GUILD)", not shell.guild.is_empty()],
		[HomeMap.HOUSE, mine, "MY HOUSE" if mine >= 0 else "MY HOUSE (NONE YET)", mine >= 0]]
	for i in rows.size():
		var row: Array = rows[i]
		var r := Rect2(x, y + i * 40.0, 300, 34)
		var is_here: bool = int(here[0]) == int(row[0]) and (int(row[0]) != HomeMap.HOUSE or int(here[1]) == int(row[1]))
		button("go:%d:%d" % [int(row[0]), int(row[1])], r, String(row[2]), bool(row[3]) and not is_here and not busy, is_here, 14)
	var sy: float = y + rows.size() * 40.0 + 14.0
	UiKit.text(self, Vector2(x, sy), "THE HOUSES: STREETS", 13, UiKit.GOLD)
	var open: int = int(streets.get("open", 1))
	var taken: Array = streets.get("taken", [])
	for n in range(1, mini(open, 12) + 1):
		var r2 := Rect2(x + ((n - 1) % 6) * 84.0, sy + 24 + ((n - 1) / 6) * 40.0, 78, 34)
		var count: int = int(taken[n - 1]) if n - 1 < taken.size() else 0
		var is_here2: bool = int(here[0]) == HomeMap.STREET and int(here[1]) == n
		button("go:%d:%d" % [HomeMap.STREET, n], r2, "%d  (%d/24)" % [n, count], not is_here2 and not busy, is_here2, 12)
	UiKit.text(self, Vector2(inner.end.x, y), "YOU ARE IN", 11, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.text(self, Vector2(inner.end.x, y + 16), HomeMap.place_name(int(here[0]), int(here[1])), 14, UiKit.BONE, HORIZONTAL_ALIGNMENT_RIGHT)


func press_body(id: String) -> void:
	if id.begins_with("go:"):
		var p: PackedStringArray = id.split(":")
		busy = true
		await shell.go_place(int(p[1]), int(p[2]))
		if is_instance_valid(self):
			busy = false

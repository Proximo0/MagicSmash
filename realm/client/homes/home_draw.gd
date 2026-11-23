class_name HomeDraw
extends RefCounted
## What the town screen draws for a place other than the plaza: the floor's colour, the fires, a house's furniture.
## Drawn by code in the dark frame style; every picture is a flat stand-in (`UiArt.texture("home_...")`).


## The tint of the floor tile at `wp` for a place, or null for the plaza (which the town screen draws itself).
static func floor_tint(place: Array, wp: Vector2) -> Variant:
	match int(place[0]):
		HomeMap.TAVERN:
			return Color(0.16, 0.11, 0.07)
		HomeMap.MARKET:
			return Color(0.12, 0.14, 0.11)
		HomeMap.YARD:
			return Color(0.2, 0.17, 0.11)
		HomeMap.GUILD_HALL:
			return Color(0.13, 0.1, 0.17)
		HomeMap.STREET:
			# A cobbled lane down the middle, dark ground either side.
			return Color(0.17, 0.155, 0.15) if absf(wp.y - 2048.0) < 330.0 else Color(0.07, 0.065, 0.06)
		HomeMap.HOUSE:
			var inside: bool = wp.x >= HomeMap.GRID_ORIGIN and wp.x < HomeMap.GRID_ORIGIN + HomeMap.GRID * HomeMap.CELL_PX and wp.y >= HomeMap.GRID_ORIGIN and wp.y < HomeMap.GRID_ORIGIN + HomeMap.GRID * HomeMap.CELL_PX
			return Color(0.2, 0.14, 0.09) if inside else Color(0.05, 0.045, 0.05)
	return null


## Fires, and a house's grid and furniture, over the floor and under the heroes.
static func props(t: TownScreen) -> void:
	var place: Array = t.shell.place
	var kind: int = int(place[0])
	if kind == HomeMap.HOUSE:
		_house(t)
	var items: Array = t.shell.house.get("items", []) if kind == HomeMap.HOUSE else []
	for f in HomeMap.fires_here(place, items):
		_fire(t, f)
	if kind == HomeMap.TAVERN:
		for p in [Vector2(1500, 1700), Vector2(2600, 1700), Vector2(1500, 2500), Vector2(2600, 2500)]:
			var c: Vector2 = t.w2s(p)
			t.draw_circle(c, 46.0 * TownScreen.ZOOM * 0.6, Color(0.24, 0.16, 0.09))
			t.draw_arc(c, 46.0 * TownScreen.ZOOM * 0.6, 0.0, TAU, 20, UiKit.GOLD_DIM, 1.0)


static func _fire(t: TownScreen, at: Vector2) -> void:
	var c: Vector2 = t.w2s(at)
	var fl: float = 0.85 + 0.15 * sin(t._clock * 8.0 + at.x)
	t.draw_circle(c, 40.0 * TownScreen.ZOOM * fl, Color(0.9, 0.5, 0.1, 0.07))
	if UiArt.has_file("town_brazier"):
		return
	t.draw_circle(c, 14.0 * TownScreen.ZOOM, Color(0.1, 0.08, 0.08))
	t.draw_arc(c, 14.0 * TownScreen.ZOOM, 0.0, TAU, 20, UiKit.GOLD_DIM, 1.5)
	t.draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 3), c + Vector2(0, -22 * fl), c + Vector2(8, 3)]), Color(0.85, 0.32, 0.08, 0.9))
	t.draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 3), c + Vector2(0, -10 * fl), c + Vector2(3, 3)]), Color(1.0, 0.8, 0.3))


## The brazier picture of a fire to sit at (ui_town_brazier.png, standing on the fire's point); drawn in the town's
## depth order. Without the picture `_fire` has drawn the old stand-in.
static func fire_picture(t: TownScreen, at: Vector2) -> void:
	if not UiArt.has_file("town_brazier"):
		return
	var tex: Texture2D = UiArt.texture("town_brazier", 96)
	var ps: Vector2 = tex.get_size() * TownScreen.PIC_K * TownScreen.ZOOM
	var c: Vector2 = t.w2s(at)
	t.draw_texture_rect(tex, Rect2(Vector2(c.x - ps.x / 2.0, c.y + 8.0 * TownScreen.ZOOM - ps.y), ps), false)


static func _house(t: TownScreen) -> void:
	var size: float = HomeMap.GRID * HomeMap.CELL_PX * TownScreen.ZOOM
	var o: Vector2 = t.w2s(Vector2(HomeMap.GRID_ORIGIN, HomeMap.GRID_ORIGIN))
	t.draw_rect(Rect2(o, Vector2(size, size)), UiKit.GOLD_DIM, false, 3.0)
	var cell: float = HomeMap.CELL_PX * TownScreen.ZOOM
	for i in range(1, HomeMap.GRID):
		t.draw_line(o + Vector2(i * cell, 0), o + Vector2(i * cell, size), Color(0, 0, 0, 0.18), 1.0)
		t.draw_line(o + Vector2(0, i * cell), o + Vector2(size, i * cell), Color(0, 0, 0, 0.18), 1.0)
	var floor_no: int = t.floor_no
	for it in t.shell.house.get("items", []):
		var slot: int = int(it["slot"])
		if slot / (HomeMap.GRID * HomeMap.GRID) != floor_no:
			continue
		draw_thing(t, int(it["base"]), int(it["rarity"]), t.w2s(HomeMap.cell_px(slot)), cell * 0.78)


## One piece of furniture or a plaque, centred at `c`, `s` px on a side.
static func draw_thing(ci: CanvasItem, base: int, rarity: int, c: Vector2, s: float) -> void:
	var r := Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s))
	ci.draw_texture_rect(UiArt.texture(HomeMap.thing_art(base), 48, GameNames.rarity_colour(rarity).darkened(0.35)), r, false)
	ci.draw_rect(r, GameNames.rarity_colour(rarity), false, 1.0)

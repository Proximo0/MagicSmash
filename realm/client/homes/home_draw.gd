class_name HomeDraw
extends RefCounted
## What the town screen draws for a place other than the plaza: the floor's colour, the fires, a house's furniture.
## Furniture and plaques use their rendered pictures (ui_home_*.png, see HomeMap.thing_art) and fall back to flat stand-ins
## drawn by code in the dark frame style (`UiArt.texture("home_...")`) where a file is missing.

## Picture pixels south of a cell's centre that a standing thing's bottom edge sits (its depth key too).
const THING_BASE: float = 30.0


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
	if int(t.shell.place[0]) == HomeMap.HOUSE and UiArt.has_file("home_hearth"):
		return		# a house's fire is its hearth's own picture
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
		var base: int = int(it["base"])
		if UiArt.has_file(HomeMap.thing_art(base)):
			if HomeMap.is_flat(base):
				thing_picture(t, it)
			continue		# the rest are drawn with the heroes, by depth (`depth_things`)
		draw_thing(t, base, int(it["rarity"]), t.w2s(HomeMap.cell_px(slot)), cell * 0.78)


## The house's pictured things (not rugs) on this floor as [ground y, item], for the town's depth-ordered list.
static func depth_things(t: TownScreen) -> Array:
	var out: Array = []
	if int(t.shell.place[0]) != HomeMap.HOUSE:
		return out
	for it in t.shell.house.get("items", []):
		var slot: int = int(it["slot"])
		var base: int = int(it["base"])
		if slot / (HomeMap.GRID * HomeMap.GRID) != t.floor_no or HomeMap.is_flat(base) or not UiArt.has_file(HomeMap.thing_art(base)):
			continue
		out.append([HomeMap.cell_px(slot).y + THING_BASE, it])
	return out


## A thing's picture at its own size (a pixel as big as a hero's), standing on its cell's centre, a rarity bar under it.
static func thing_picture(t: TownScreen, it: Dictionary) -> void:
	var base: int = int(it["base"])
	var tex: Texture2D = UiArt.texture(HomeMap.thing_art(base), 96)
	var ps: Vector2 = tex.get_size() * TownScreen.PIC_K * TownScreen.ZOOM
	var c: Vector2 = t.w2s(HomeMap.cell_px(int(it["slot"])))
	var bottom: float = c.y + THING_BASE * TownScreen.ZOOM
	t.draw_texture_rect(tex, Rect2(Vector2(c.x - ps.x / 2.0, bottom - ps.y), ps), false)
	t.draw_line(Vector2(c.x - ps.x / 4.0, bottom + 2.0), Vector2(c.x + ps.x / 4.0, bottom + 2.0), GameNames.rarity_colour(int(it["rarity"])), 2.0)


## One piece of furniture or a plaque, centred at `c`, fitted in `s` px (the panel's cells and list). Its picture when
## the file is there, else the flat stand-in with a rarity frame.
static func draw_thing(ci: CanvasItem, base: int, rarity: int, c: Vector2, s: float) -> void:
	var name: String = HomeMap.thing_art(base)
	if UiArt.has_file(name):
		var tex: Texture2D = UiArt.texture(name, 96)
		var k: float = minf(2.0, minf(s / tex.get_width(), s / tex.get_height()))
		var ps: Vector2 = tex.get_size() * k
		ci.draw_texture_rect(tex, Rect2(c - ps / 2.0, ps), false)
		ci.draw_line(Vector2(c.x - s / 4.0, c.y + s / 2.0 - 1.0), Vector2(c.x + s / 4.0, c.y + s / 2.0 - 1.0), GameNames.rarity_colour(rarity), 2.0)
		return
	var r := Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s))
	ci.draw_texture_rect(UiArt.texture(name, 48, GameNames.rarity_colour(rarity).darkened(0.35)), r, false)
	ci.draw_rect(r, GameNames.rarity_colour(rarity), false, 1.0)

class_name HomeMap
extends RefCounted
## The shared places and the houses as the client knows them (mirrors realm/gateway/src/homes/place.rs and
## catalogue.rs: change both together). A place is a kind and an argument; a house is 24 plots to a street, two
## 10 x 10 rooms of 128 px cells (cell = room * 100 + y * 10 + x). Every picture is a flat stand-in drawn by code
## and named for the art list (`UiArt.texture("home_<name>")`, file `ui_home_<name>.png`): `art_names()`.

const PLAZA := 0
const TAVERN := 1
const MARKET := 2
const GUILD_HALL := 3
const YARD := 4
const STREET := 5
const HOUSE := 6

const PLACE_NAMES: Array[String] = ["THE PLAZA", "THE TAVERN", "THE MARKET SQUARE", "THE GUILD HALL", "THE TRAINING YARD", "THE STREET", "A HOUSE"]
const RULE_NAMES: Array[String] = ["OPEN", "FRIENDS", "GUILD", "LOCKED"]
const STATUS_NAMES: Array[String] = ["FREE", "OWNED", "RENTED", "LAPSED"]

const PLOTS_PER_STREET := 24
const GRID := 10
const ROOMS := 2
const CELLS := 200
const CELL_PX := 128.0
const GRID_ORIGIN := 1408.0
## A hero this near a fire may sit.
const FIRE_REACH := 160.0

const FURNITURE_BASE := 9000
const TROPHY_BASE := 9100
const FURNITURE: Array[String] = [
	"CHAIR", "STRAW BED", "LINEN RUG", "PLAGUE CURTAIN",
	"TABLE", "BOOKSHELF", "CHEST", "GALLOWS CLOCK",
	"HEARTH", "CANDELABRA", "BRAZIER", "IRON BED",
	"SIGIL RUG", "ALTAR", "SCRYING BOWL", "RUNE LAMP",
	"WINDOW", "MIRROR", "LANTERN", "SAINT'S SCREEN",
	"URN", "SKULL SHELF", "BLACK MIRROR", "ASH THRONE"]
const TROPHY_CRAFT := 100
const HEARTH := 8

const FIRES: Dictionary = {
	PLAZA: [Vector2(1850, 2048), Vector2(2250, 2048)],
	TAVERN: [Vector2(2048, 2048)],
	YARD: [Vector2(2300, 2200)],
	GUILD_HALL: [Vector2(2048, 1800)]}


static func is_thing(base: int) -> bool:
	return (base >= FURNITURE_BASE and base < FURNITURE_BASE + FURNITURE.size()) or (base >= TROPHY_BASE and base < TROPHY_BASE + 8)


static func thing_name(base: int) -> String:
	if base >= TROPHY_BASE:
		return "PLAQUE OF " + GameNames.BOSSES[clampi(base - TROPHY_BASE, 0, 7)]
	return FURNITURE[clampi(base - FURNITURE_BASE, 0, FURNITURE.size() - 1)]


## Names a flat stand-in picture of a thing is filed under: furniture by its name, plaques by "plaque".
static func thing_art(base: int) -> String:
	return "home_plaque" if base >= TROPHY_BASE else "home_" + FURNITURE[clampi(base - FURNITURE_BASE, 0, FURNITURE.size() - 1)].to_lower().replace(" ", "_").replace("'", "")


static func cell_of(room: int, x: int, y: int) -> int:
	return room * GRID * GRID + y * GRID + x


## The centre of a cell in room px.
static func cell_px(cell: int) -> Vector2:
	var c: int = cell % (GRID * GRID)
	return Vector2(GRID_ORIGIN + (c % GRID) * CELL_PX + CELL_PX / 2.0, GRID_ORIGIN + (c / GRID) * CELL_PX + CELL_PX / 2.0)


static func fires_of(kind: int) -> Array:
	return FIRES.get(kind, [])


static func plot_id(street: int, index: int) -> int:
	return (street - 1) * PLOTS_PER_STREET + index


static func street_of(plot: int) -> int:
	return plot / PLOTS_PER_STREET + 1


## Where house `index` stands on its street: two rows of twelve, doors facing the middle lane.
static func door_at(index: int) -> Vector2:
	var col: int = index % 12
	var north: bool = index < 12
	return Vector2(560.0 + col * 250.0, 1560.0 if north else 2540.0)


static func place_name(kind: int, arg: int) -> String:
	if kind == STREET:
		return "STREET %d" % arg
	if kind == HOUSE:
		return "HOUSE %d" % arg
	return PLACE_NAMES[clampi(kind, 0, PLACE_NAMES.size() - 1)]


## The stations (doors, boards, fires) of a place, in the shape of TownMap.STATIONS: "go" [kind, arg] walks
## through a door, "open" names a panel.
static func stations_for(place: Array, street_plots: Array = []) -> Array[Dictionary]:
	var kind: int = int(place[0])
	var arg: int = int(place[1])
	var out: Array[Dictionary] = []
	match kind:
		PLAZA:
			for s in TownMap.STATIONS:
				out.append(s)
			out.append(_door("to_tavern", "THE TAVERN", Vector2(1300, 1250), [TAVERN, 0], "drink, sit by the fire, talk", Color(0.4, 0.26, 0.14)))
			out.append(_door("to_market", "MARKET SQUARE", Vector2(2796, 1250), [MARKET, 0], "the stalls of other heroes", Color(0.2, 0.36, 0.3)))
			out.append(_door("to_yard", "TRAINING YARD", Vector2(1100, 2048), [YARD, 0], "strike the dummy, see your damage", Color(0.36, 0.2, 0.2)))
			out.append(_door("to_hall", "GUILD HALL", Vector2(2996, 2048), [GUILD_HALL, 0], "your guild's own hall", Color(0.3, 0.22, 0.4)))
			out.append(_door("to_street", "THE HOUSES", Vector2(2048, 1100), [STREET, 1], "streets of houses to rent or buy", Color(0.26, 0.26, 0.2)))
		TAVERN:
			out.append(_door("to_plaza", "OUT TO THE PLAZA", Vector2(2048, 3000), [PLAZA, 0], "", Color(0.2, 0.2, 0.26)))
		MARKET:
			out.append(_door("to_plaza", "OUT TO THE PLAZA", Vector2(2048, 3000), [PLAZA, 0], "", Color(0.2, 0.2, 0.26)))
			out.append(_panel("stalls", "THE STALLS", Vector2(2048, 1700), "StallsPanel", "who sells what", Color(0.2, 0.36, 0.3)))
		YARD:
			out.append(_door("to_plaza", "OUT TO THE PLAZA", Vector2(2048, 3000), [PLAZA, 0], "", Color(0.2, 0.2, 0.26)))
			out.append(_panel("dummy", "THE DUMMY", Vector2(2048, 1600), "YardPanel", "strike it, read your damage a second", Color(0.4, 0.3, 0.16)))
		GUILD_HALL:
			out.append(_door("to_plaza", "OUT TO THE PLAZA", Vector2(2048, 3000), [PLAZA, 0], "", Color(0.2, 0.2, 0.26)))
			out.append(_panel("guild", "THE GUILD BOARD", Vector2(2048, 1500), "GuildPanel", "members, board, bank", Color(0.3, 0.22, 0.4)))
		STREET:
			out.append(_door("to_plaza", "BACK TO THE PLAZA", Vector2(200, 2048), [PLAZA, 0], "", Color(0.2, 0.2, 0.26)))
			out.append(_panel("board", "THE STREET BOARD", Vector2(2048, 2048), "StreetPanel", "who lives where, rent or buy a plot", Color(0.26, 0.26, 0.2)))
			for i in PLOTS_PER_STREET:
				var info: Dictionary = {}
				if i < street_plots.size():
					info = street_plots[i]
				var taken: bool = not info.is_empty() and int(info["status"]) != 0
				var nm: String = String(info.get("name", "")) if taken else "FOR SALE"
				if taken and nm.is_empty():
					nm = String(info.get("owner", ""))
				var s := _door("door:%d" % i, nm, door_at(i), [HOUSE, plot_id(arg, i)] if taken else [], "a door: F to knock" if taken else "F to see the price", Color(0.3, 0.2, 0.16) if taken else Color(0.16, 0.16, 0.16))
				s["size"] = Vector2(130, 90)
				s["plot"] = i
				if not taken:
					s["open"] = "StreetPanel"
				out.append(s)
		HOUSE:
			out.append(_door("to_street", "OUT TO THE STREET", Vector2(2048, 3000), [STREET, street_of(arg)], "", Color(0.2, 0.2, 0.26)))
	return out


static func _door(id: String, nm: String, at: Vector2, go: Array, what: String, col: Color) -> Dictionary:
	return {"id": id, "name": nm, "at": at, "size": Vector2(150, 96), "col": col, "what": what, "go": go}


static func _panel(id: String, nm: String, at: Vector2, panel: String, what: String, col: Color) -> Dictionary:
	return {"id": id, "name": nm, "at": at, "size": Vector2(150, 96), "col": col, "what": what, "open": panel}


## The fires of the place the hero is in: the fixed ones, and a house's hearths.
static func fires_here(place: Array, house_items: Array = []) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for f in fires_of(int(place[0])):
		out.append(f)
	if int(place[0]) == HOUSE:
		for it in house_items:
			if int(it["base"]) == FURNITURE_BASE + HEARTH:
				out.append(cell_px(int(it["slot"])))
	return out


## Every picture name the homes ask of `UiArt` (the art list): doors, boards, furniture and plaques.
static func art_names() -> Array[String]:
	var out: Array[String] = ["home_door", "home_door_free", "home_board", "home_plaque", "home_fire", "home_dummy"]
	for n in FURNITURE:
		out.append("home_" + n.to_lower().replace(" ", "_").replace("'", ""))
	return out

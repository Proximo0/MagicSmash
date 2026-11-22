class_name TownMap
extends RefCounted
## The town's plan, in world px of the gateway's 4096 px square (the server has no collision and no stations: a
## room is a flat square, so where things stand is this file's). The plaza is a disc round the middle, where
## heroes arrive; the stations ring it, the field gates stand on the south rim.

const CENTRE: Vector2 = Vector2(2048, 2048)
const PLAZA_R: float = 1000.0
## A hero this close to a station can use it (F, or a click on it).
const USE_PX: float = 130.0
## Where a station can be clicked from.
const CLICK_PX: float = 240.0

## id, name, position, panel, the building's size (px), colour of the stand-in.
const STATIONS: Array[Dictionary] = [
	{"id": "trainer", "name": "THE TRAINER", "at": Vector2(2048, 1420), "size": Vector2(150, 96), "col": Color(0.42, 0.2, 0.2), "what": "skills and points"},
	{"id": "bank", "name": "THE BANK", "at": Vector2(1460, 1760), "size": Vector2(150, 96), "col": Color(0.4, 0.34, 0.16), "what": "deposit and withdraw"},
	{"id": "smith", "name": "THE SMITH", "at": Vector2(2636, 1760), "size": Vector2(150, 96), "col": Color(0.46, 0.22, 0.1), "what": "salvage, upgrade, reroll, socket, fuse"},
	{"id": "merchants", "name": "THE MERCHANTS", "at": Vector2(1460, 2336), "size": Vector2(150, 96), "col": Color(0.2, 0.34, 0.3), "what": "potions, selling, the belt"},
	{"id": "reader", "name": "THE CARD READER", "at": Vector2(2636, 2336), "size": Vector2(150, 96), "col": Color(0.32, 0.2, 0.42), "what": "your deck of cards"},
	{"id": "gate", "name": "THE FIELD GATES", "at": Vector2(2048, 2780), "size": Vector2(240, 80), "col": Color(0.2, 0.2, 0.26), "what": "the six fields"}]


static func station(id: String) -> Dictionary:
	for s in STATIONS:
		if s["id"] == id:
			return s
	return {}


## The station within `px` of a point, nearest first, or {}.
static func near(p: Vector2, px: float) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = px
	for s in STATIONS:
		var d: float = p.distance_to(s["at"])
		if d <= bd:
			bd = d
			best = s
	return best

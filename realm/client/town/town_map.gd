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
	{"id": "trainer", "name": "THE TRAINER", "at": Vector2(2048, 1420), "size": Vector2(150, 96), "col": Color(0.42, 0.2, 0.2), "what": "Skills and points"},
	{"id": "bank", "name": "THE BANK", "at": Vector2(1460, 1760), "size": Vector2(150, 96), "col": Color(0.4, 0.34, 0.16), "what": "Deposit and withdraw"},
	{"id": "smith", "name": "THE SMITH", "at": Vector2(2636, 1760), "size": Vector2(150, 96), "col": Color(0.46, 0.22, 0.1), "what": "Salvage, upgrade, reroll, socket, fuse"},
	{"id": "merchants", "name": "THE MERCHANTS", "at": Vector2(1460, 2336), "size": Vector2(150, 96), "col": Color(0.2, 0.34, 0.3), "what": "Potions, embers, gear, selling, the belt"},
	{"id": "reader", "name": "THE CARD READER", "at": Vector2(2636, 2336), "size": Vector2(150, 96), "col": Color(0.32, 0.2, 0.42), "what": "Your deck of cards"},
	{"id": "market", "name": "THE MARKET", "at": Vector2(1700, 1560), "size": Vector2(150, 96), "col": Color(0.3, 0.3, 0.14), "what": "Buy and sell with other heroes"},
	{"id": "post", "name": "THE POST", "at": Vector2(2396, 1560), "size": Vector2(150, 96), "col": Color(0.22, 0.24, 0.36), "what": "Letters and what came back"},
	{"id": "trade", "name": "THE TRADE TABLE", "at": Vector2(1700, 2536), "size": Vector2(150, 96), "col": Color(0.34, 0.24, 0.2), "what": "Trade hand to hand"},
	{"id": "board", "name": "THE WORLD BOARD", "at": Vector2(2396, 2536), "size": Vector2(150, 96), "col": Color(0.26, 0.2, 0.3), "what": "Tides, bosses, the queue"},
	{"id": "trial", "name": "THE CLASS TRIAL", "at": Vector2(2340, 1290), "size": Vector2(150, 96), "col": Color(0.36, 0.14, 0.14), "what": "The trial alone, for a job at 40"},
	{"id": "gate", "name": "THE FIELD GATES", "at": Vector2(2048, 2780), "size": Vector2(240, 80), "col": Color(0.2, 0.2, 0.26), "what": "The six fields"}]


static func station(id: String, list: Array = STATIONS) -> Dictionary:
	for s in list:
		if s["id"] == id:
			return s
	return {}


## The station within `px` of a point, nearest first, or {}.
static func near(p: Vector2, px: float, list: Array = STATIONS) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = px
	for s in list:
		var d: float = p.distance_to(s["at"])
		if d <= bd:
			bd = d
			best = s
	return best

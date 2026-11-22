class_name HomeWire
extends RefCounted
## The homes' calls on the gateway wire (realm/gateway/src/homes/wire.rs, docs/realm/homes.md): one request tag
## (0x70, a sub-byte, the hero, the arguments), one reply tag (0x8C) and one push tag (0xA9), the same body in both.
## Its tags are the homes row of realm/gateway/src/proto/ranges.rs (mirrored in ui/gw_wire.gd).
## Requests return [type, body] like GwWire's; `decode_body` fills a reply Dictionary with "k" (the kind below).

const T_HOME := 0x70
const R_HOME := 0x8C
const P_HOME := 0xA9

# request sub-bytes
const Q_STREETS := 0
const Q_STREET := 1
const Q_BUY := 2
const Q_RENT := 3
const Q_RENEW := 4
const Q_RELEASE := 5
const Q_RULE := 6
const Q_NAME := 7
const Q_GO := 8
const Q_HOUSE := 9
const Q_PLACE := 10
const Q_MOVE := 11
const Q_PICKUP := 12
const Q_SIGN := 13
const Q_WIPE := 14
const Q_CRAFT := 15
const Q_CATALOGUE := 16
const Q_STRIKE := 17
const Q_YARD_BOARD := 18
const Q_SIT := 19
const Q_STAND := 20
const Q_STATUS := 21
const Q_STALLS := 22
const Q_WHERE := 23

# reply kinds
const K_OK := 0
const K_STREETS := 1
const K_STREET := 2
const K_HOUSE := 3
const K_MOVED := 4
const K_CRAFTED := 5
const K_PAID := 6
const K_STRIKE := 7
const K_BOARD := 8
const K_REST := 9
const K_STALLS := 10
const K_WHERE := 11
const K_CATALOGUE := 12
const K_BOOK := 13
const K_NOTICE := 14


static func _head(sub: int, hero: int) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u8(sub)
	b.put_u64(hero)
	return b


static func hero_only(sub: int, hero: int) -> Array:
	return [T_HOME, _head(sub, hero).data_array]


## A request with one u32 (street, offset).
static func with_u32(sub: int, hero: int, v: int) -> Array:
	var b := _head(sub, hero)
	b.put_u32(v)
	return [T_HOME, b.data_array]


## A request with one byte (renew weeks, a rule).
static func with_u8(sub: int, hero: int, v: int) -> Array:
	var b := _head(sub, hero)
	b.put_u8(v)
	return [T_HOME, b.data_array]


static func buy(hero: int, street: int, plot: int) -> Array:
	var b := _head(Q_BUY, hero)
	b.put_u32(street)
	b.put_u8(plot)
	return [T_HOME, b.data_array]


static func rent(hero: int, street: int, plot: int, weeks: int) -> Array:
	var b := _head(Q_RENT, hero)
	b.put_u32(street)
	b.put_u8(plot)
	b.put_u8(weeks)
	return [T_HOME, b.data_array]


static func name_house(hero: int, name: String) -> Array:
	var b := _head(Q_NAME, hero)
	GwWire.put_str(b, name)
	return [T_HOME, b.data_array]


static func go(hero: int, kind: int, arg: int) -> Array:
	var b := _head(Q_GO, hero)
	b.put_u8(kind)
	b.put_u32(arg)
	return [T_HOME, b.data_array]


## Place (Q_PLACE) or move (Q_MOVE) an item to a cell (room * 100 + y * 10 + x).
static func item_to(sub: int, hero: int, item: int, cell: int) -> Array:
	var b := _head(sub, hero)
	b.put_u64(item)
	b.put_u16(cell)
	return [T_HOME, b.data_array]


static func pickup(hero: int, item: int) -> Array:
	var b := _head(Q_PICKUP, hero)
	b.put_u64(item)
	return [T_HOME, b.data_array]


static func sign_book(hero: int, text: String) -> Array:
	var b := _head(Q_SIGN, hero)
	GwWire.put_str(b, text)
	return [T_HOME, b.data_array]


static func wipe(hero: int, entry: int) -> Array:
	var b := _head(Q_WIPE, hero)
	b.put_u64(entry)
	return [T_HOME, b.data_array]


static func craft(hero: int, kind: int) -> Array:
	var b := _head(Q_CRAFT, hero)
	b.put_u16(kind)
	return [T_HOME, b.data_array]


static func _entries(b: StreamPeerBuffer) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in b.get_u16():
		var e := {}
		e["id"] = b.get_u64()
		e["at"] = b.get_64()
		e["name"] = GwWire.get_str(b)
		e["text"] = GwWire.get_str(b)
		out.append(e)
	return out


## Reads a reply or push body into `d`.
static func decode_body(b: StreamPeerBuffer, d: Dictionary) -> void:
	d["k"] = b.get_u8()
	match int(d["k"]):
		K_OK:
			pass
		K_STREETS:
			d["open"] = b.get_u32()
			var taken: Array[int] = []
			for i in b.get_u16():
				taken.append(b.get_u8())
			d["taken"] = taken
			var m: int = b.get_u32()
			d["mine"] = -1 if m == 0xFFFFFFFF else m
		K_STREET:
			d["street"] = b.get_u32()
			var plots: Array[Dictionary] = []
			for i in b.get_u16():
				var p := {}
				p["index"] = b.get_u8()
				p["status"] = b.get_u8()
				p["rule"] = b.get_u8()
				p["owner"] = GwWire.get_str(b)
				p["name"] = GwWire.get_str(b)
				p["buy"] = b.get_u64()
				p["rent"] = b.get_u64()
				p["until"] = b.get_64()
				plots.append(p)
			d["plots"] = plots
		K_HOUSE:
			d["plot"] = b.get_u32()
			d["owner"] = GwWire.get_str(b)
			d["name"] = GwWire.get_str(b)
			d["rule"] = b.get_u8()
			d["status"] = b.get_u8()
			d["mine"] = b.get_u8() != 0
			d["until"] = b.get_64()
			var items: Array[Dictionary] = []
			for i in b.get_u16():
				items.append(GwWire._item(b))
			d["items"] = items
			d["book"] = _entries(b)
		K_MOVED:
			d["item"] = b.get_64()
			d["house"] = b.get_u8() != 0
			d["cell"] = b.get_u16()
		K_CRAFTED:
			d["item"] = GwWire._item(b)
		K_PAID:
			d["plot"] = b.get_u32()
			d["until"] = b.get_64()
			d["coin"] = b.get_u64()
		K_STRIKE:
			d["damage"] = b.get_u32()
			d["total"] = b.get_u64()
			d["dps"] = b.get_u32()
			d["count"] = b.get_u32()
			d["best"] = b.get_u32()
		K_BOARD:
			var rows: Array[Array] = []
			for i in b.get_u16():
				var n: String = GwWire.get_str(b)
				var c: int = b.get_u8()
				rows.append([n, c, b.get_u32()])
			d["rows"] = rows
		K_REST:
			d["sitting"] = b.get_u8() != 0
			d["secs"] = b.get_u32()
			d["rested_ms"] = b.get_u32()
			d["pct"] = b.get_u8()
		K_STALLS:
			var stalls: Array[Dictionary] = []
			for i in b.get_u16():
				var s := {}
				s["seller"] = GwWire.get_str(b)
				s["listings"] = b.get_u32()
				s["cheapest"] = b.get_u64()
				stalls.append(s)
			d["stalls"] = stalls
		K_WHERE:
			d["kind"] = b.get_u8()
			d["arg"] = b.get_u32()
		K_CATALOGUE:
			var recipes: Array[Dictionary] = []
			for i in b.get_u16():
				var r := {}
				r["kind"] = b.get_u16()
				r["material"] = b.get_u32()
				r["count"] = b.get_u64()
				r["coin"] = b.get_u64()
				recipes.append(r)
			d["recipes"] = recipes
		K_BOOK:
			d["book"] = _entries(b)
		K_NOTICE:
			d["nkind"] = b.get_u8()
			d["a"] = b.get_64()
			d["text"] = GwWire.get_str(b)

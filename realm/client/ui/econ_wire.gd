class_name EconWire
extends RefCounted
## The economy's calls on the gateway wire (realm/gateway/src/economy/wire.rs, docs/realm/economy.md part 2): one
## request tag (0x33, a sub-byte, the hero, the arguments), one reply tag (0x8B) and one push tag (0xA8), the same
## body in both. Requests return [type, body] like GwWire's; `decode_body` fills a reply Dictionary with "k".

const T_ECON := 0x33
const R_ECON := 0x8B
const P_ECON := 0xA8

# request sub-bytes
const Q_TRADE_INVITE := 0x10
const Q_TRADE_ACCEPT := 0x11
const Q_TRADE_OFFER := 0x12
const Q_TRADE_CONFIRM := 0x13
const Q_TRADE_CANCEL := 0x14
const Q_TRADE_VIEW := 0x15
const Q_MARKET_LIST := 0x20
const Q_MARKET_SEARCH := 0x21
const Q_MARKET_BUY := 0x22
const Q_MARKET_CANCEL := 0x23
const Q_MARKET_MINE := 0x24
const Q_MARKET_PRICES := 0x25
const Q_LETTER_SEND := 0x30
const Q_INBOX := 0x31
const Q_OUTBOX := 0x32
const Q_LETTER_TAKE := 0x33
const Q_LETTER_REFUSE := 0x34
const Q_LETTER_RECALL := 0x35

# reply kinds
const K_OK := 0
const K_OFFERS := 1
const K_COIN := 2
const K_BUYBACKS := 3
const K_TRADE := 4
const K_LISTED := 5
const K_LISTINGS := 6
const K_LETTERS := 7
const K_PRICES := 8
const K_NOTICE := 9

# notice kinds
const N_SOLD := 1
const N_EXPIRED := 2
const N_LETTER := 3
const N_INVITED := 4
const N_LETTER_RETURNED := 5

# trade states
const TS_INVITED := 0
const TS_OPEN := 1
const TS_DONE := 2
const TS_CANCELLED := 3

const HOURS: Array[int] = [12, 24, 48]


static func _head(sub: int, hero: int) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u8(sub)
	b.put_u64(hero)
	return b


static func hero_only(sub: int, hero: int) -> Array:
	return [T_ECON, _head(sub, hero).data_array]


## A request with one u64 (a listing, a letter, a session).
static func with_id(sub: int, hero: int, id: int) -> Array:
	var b := _head(sub, hero)
	b.put_u64(id)
	return [T_ECON, b.data_array]


static func market_prices() -> Array:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u8(Q_MARKET_PRICES)
	return [T_ECON, b.data_array]


## `q`: gear_slot (255 any), rarity_min, level_min, level_max (0 any), stack (0 any), price_max (0 any), offset.
static func market_search(hero: int, q: Dictionary) -> Array:
	var b := _head(Q_MARKET_SEARCH, hero)
	b.put_u8(int(q.get("gear_slot", 255)))
	b.put_u8(int(q.get("rarity_min", 0)))
	b.put_u16(int(q.get("level_min", 0)))
	b.put_u16(int(q.get("level_max", 0)))
	b.put_u32(int(q.get("stack", 0)))
	b.put_u64(int(q.get("price_max", 0)))
	b.put_u32(int(q.get("offset", 0)))
	return [T_ECON, b.data_array]


static func market_list(hero: int, item: int, stack_kind: int, count: int, price: int, hours: int) -> Array:
	var b := _head(Q_MARKET_LIST, hero)
	GwWire.put_thing(b, item, stack_kind, count)
	b.put_u64(price)
	b.put_u16(hours)
	return [T_ECON, b.data_array]


static func letter_send(hero: int, to_name: String, text: String, things: Array, cod: int) -> Array:
	var b := _head(Q_LETTER_SEND, hero)
	GwWire.put_str(b, to_name)
	GwWire.put_str(b, text)
	b.put_u8(things.size())
	for t in things:
		GwWire.put_thing(b, int(t[0]), int(t[1]), int(t[2]))
	b.put_u64(cod)
	return [T_ECON, b.data_array]


static func trade_invite(hero: int, name: String) -> Array:
	var b := _head(Q_TRADE_INVITE, hero)
	GwWire.put_str(b, name)
	return [T_ECON, b.data_array]


## Both offers at once: the item ids and the stacks ([kind, count]) she puts on the table.
static func trade_offer(hero: int, session: int, items: Array, stacks: Array) -> Array:
	var b := _head(Q_TRADE_OFFER, hero)
	b.put_u64(session)
	b.put_u16(items.size())
	for i in items:
		b.put_u64(int(i))
	b.put_u16(stacks.size())
	for s in stacks:
		b.put_u32(int(s[0]))
		b.put_u64(int(s[1]))
	return [T_ECON, b.data_array]


static func trade_confirm(hero: int, session: int, version: int) -> Array:
	var b := _head(Q_TRADE_CONFIRM, hero)
	b.put_u64(session)
	b.put_u32(version)
	return [T_ECON, b.data_array]


# ---- replies

static func _eitem(b: StreamPeerBuffer) -> Dictionary:
	var it: Dictionary = GwWire._item(b)
	# The economy's extra: the plus again, bound, and the rune of each of two sockets.
	it["plus"] = b.get_u8()
	it["bound"] = b.get_u8() != 0
	b.get_u32()
	b.get_u32()
	return it


static func _items(b: StreamPeerBuffer) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in b.get_u16():
		out.append(_eitem(b))
	return out


static func _stacks(b: StreamPeerBuffer) -> Array[Array]:
	var out: Array[Array] = []
	for i in b.get_u16():
		var kind: int = b.get_u32()
		out.append([kind, b.get_64()])
	return out


static func decode_body(b: StreamPeerBuffer, d: Dictionary) -> void:
	d["k"] = b.get_u8()
	match int(d["k"]):
		K_OK:
			pass
		K_COIN:
			d["coin"] = b.get_64()
		K_OFFERS:
			var offers: Array[Dictionary] = []
			for i in b.get_u16():
				var o := {"id": b.get_u16(), "kind": b.get_u8(), "stack": b.get_u32()}
				o["item"] = _eitem(b) if b.get_u8() != 0 else {}
				o["price"] = b.get_64()
				o["left"] = b.get_u32()
				offers.append(o)
			d["offers"] = offers
		K_BUYBACKS:
			var backs: Array[Dictionary] = []
			for i in b.get_u16():
				backs.append({"id": b.get_64(), "item": _eitem(b), "price": b.get_64(), "secs_left": b.get_u32()})
			d["buybacks"] = backs
		K_TRADE:
			d["session"] = b.get_64()
			d["state"] = b.get_u8()
			d["me"] = b.get_64()
			d["other"] = b.get_64()
			d["other_name"] = GwWire.get_str(b)
			d["version"] = b.get_u32()
			d["lock_ms"] = b.get_u32()
			d["my_items"] = _items(b)
			d["my_stacks"] = _stacks(b)
			d["their_items"] = _items(b)
			d["their_stacks"] = _stacks(b)
			d["my_ok"] = b.get_u8() != 0
			d["their_ok"] = b.get_u8() != 0
		K_LISTED:
			d["id"] = b.get_64()
			d["fee"] = b.get_64()
		K_LISTINGS:
			var ls: Array[Dictionary] = []
			for i in b.get_u16():
				var l := {"id": b.get_64(), "seller": GwWire.get_str(b), "price": b.get_64(), "expires": b.get_64(), "mine": b.get_u8() != 0}
				var what: int = b.get_u8()
				l["item"] = _eitem(b) if what == 1 else {}
				l["stack"] = [b.get_u32(), b.get_64()] if what == 2 else []
				ls.append(l)
			d["listings"] = ls
		K_LETTERS:
			var letters: Array[Dictionary] = []
			for i in b.get_u16():
				var l := {"id": b.get_64(), "from": GwWire.get_str(b), "to": GwWire.get_str(b), "text": GwWire.get_str(b), "cod": b.get_64(), "expires": b.get_64()}
				l["items"] = _items(b)
				l["stacks"] = _stacks(b)
				letters.append(l)
			d["letters"] = letters
		K_PRICES:
			var ps: Array[Array] = []
			for i in b.get_u16():
				ps.append([b.get_u8(), b.get_u8(), b.get_64(), b.get_u32()])
			d["prices"] = ps
		K_NOTICE:
			d["nkind"] = b.get_u8()
			d["a"] = b.get_64()
			d["b"] = b.get_64()
			d["text"] = GwWire.get_str(b)
		_:
			d["bad"] = true

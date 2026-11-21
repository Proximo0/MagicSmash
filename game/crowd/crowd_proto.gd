class_name CrowdProto
extends RefCounted
## Protocol A, version 0, client side (docs/realm/crowd_test.md): builds HELLO, INPUT and BYE, decodes WELCOME and
## SNAPSHOT parts and joins the parts of one tick. Pure bytes in, bytes out. Little-endian.

const PROTO: int = 1
const OP_HELLO: int = 0x01
const OP_INPUT: int = 0x02
const OP_BYE: int = 0x03
const OP_WELCOME: int = 0x81
const OP_SNAPSHOT: int = 0x82
const SKILL_BIT: int = 0x80
const WELCOME_SIZE: int = 19
const PART_HEAD: int = 7
const FIRST_PART_EXTRA: int = 26
const COUNTS_SIZE: int = 6

## Ticks of an incomplete snapshot kept while newer ones arrive (older ones are dropped at once).
var _pending: Dictionary = {}
var _newest_done: int = -1
## Parts or snapshots dropped (an older tick still incomplete, a stale or malformed part).
var dropped: int = 0


static func hello(hero_class: int, race: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(7)
	b[0] = OP_HELLO
	b.encode_u32(1, PROTO)
	b[5] = hero_class
	b[6] = race
	return b


static func input(last_tick: int, move: int, skill: bool, zoom: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(7)
	b[0] = OP_INPUT
	b.encode_u32(1, last_tick)
	b[5] = (move & 0x7F) | (SKILL_BIT if skill else 0)
	b[6] = zoom
	return b


static func bye() -> PackedByteArray:
	return PackedByteArray([OP_BYE])


## {id, tick, hz, width, height}, or {} when the bytes are not a WELCOME.
static func decode_welcome(b: PackedByteArray) -> Dictionary:
	if b.size() < WELCOME_SIZE or b[0] != OP_WELCOME:
		return {}
	return {"id": b.decode_u32(1), "tick": b.decode_u32(5), "hz": b.decode_u16(9),
		"width": b.decode_u32(11), "height": b.decode_u32(15)}


## Reads a LEB128 varint at `pos`; returns [value, next pos] (next pos -1 when the bytes end early).
static func read_varint(b: PackedByteArray, pos: int) -> Array:
	var v: int = 0
	var shift: int = 0
	while pos < b.size():
		var c: int = b[pos]
		pos += 1
		v |= (c & 0x7F) << shift
		if c < 0x80:
			return [v, pos]
		shift += 7
		if shift > 35:
			break
	return [0, -1]


## Decodes one SNAPSHOT datagram into {tick, part, parts, snap: CrowdSnap}; {} when malformed.
static func decode_part(b: PackedByteArray) -> Dictionary:
	if b.size() < PART_HEAD + COUNTS_SIZE or b[0] != OP_SNAPSHOT:
		return {}
	var s := CrowdSnap.new()
	s.tick = b.decode_u32(1)
	var part: int = b[5]
	var parts: int = b[6]
	if parts == 0 or part >= parts:
		return {}
	var pos: int = PART_HEAD
	if part == 0:
		if b.size() < PART_HEAD + FIRST_PART_EXTRA + COUNTS_SIZE:
			return {}
		s.origin_x = b.decode_s32(pos)
		s.origin_y = b.decode_s32(pos + 4)
		s.my_x = s.origin_x + b.decode_u16(pos + 8)
		s.my_y = s.origin_y + b.decode_u16(pos + 10)
		s.my_health = b.decode_u16(pos + 12)
		s.my_level = b.decode_u16(pos + 14)
		s.players_in_field = b.decode_u32(pos + 16)
		s.monsters_in_field = b.decode_u32(pos + 20)
		s.tick_ms = b.decode_u16(pos + 24) / 100.0
		s.has_header = true
		pos += FIRST_PART_EXTRA
	var n_players: int = b.decode_u16(pos)
	var n_crowd: int = b.decode_u16(pos + 2)
	var n_mon: int = b.decode_u16(pos + 4)
	pos += COUNTS_SIZE
	# Parts after the first have no origin of their own: positions stay relative until the join adds it.
	if pos + n_players * 8 + n_crowd * 4 > b.size():
		return {}
	s.pid.resize(n_players)
	s.px.resize(n_players)
	s.py.resize(n_players)
	s.pkind.resize(n_players)
	s.pflag.resize(n_players)
	for i in n_players:
		s.pid[i] = b.decode_u16(pos)
		s.px[i] = b.decode_u16(pos + 2)
		s.py[i] = b.decode_u16(pos + 4)
		s.pkind[i] = b[pos + 6]
		s.pflag[i] = b[pos + 7]
		pos += 8
	s.cx.resize(n_crowd)
	s.cy.resize(n_crowd)
	for i in n_crowd:
		s.cx[i] = b.decode_u16(pos)
		s.cy[i] = b.decode_u16(pos + 2)
		pos += 4
	s.mid.resize(n_mon)
	s.mx.resize(n_mon)
	s.my.resize(n_mon)
	s.mflag.resize(n_mon)
	var id: int = 0
	var n := b.size()
	for i in n_mon:
		var vr := read_varint(b, pos)
		pos = vr[1]
		if pos < 0 or pos + 4 > n:
			return {}
		id += vr[0]
		var v: int = b[pos] | (b[pos + 1] << 8) | (b[pos + 2] << 16)
		var k: int = b[pos + 3]
		s.mid[i] = id
		s.mx[i] = v & 0xFFF
		s.my[i] = (v >> 12) & 0x7FF
		s.mflag[i] = (k & 0x3F) | (0x40 if (k >> 6) & 1 else 0) | (0x80 if (v >> 23) & 1 else 0)
		pos += 4
	return {"tick": s.tick, "part": part, "parts": parts, "snap": s}


## Feeds one datagram. Returns the joined CrowdSnap when this part completed a tick, else null. A part of a tick
## older than the newest one finished or pending is dropped, and so are older pending ticks when a newer one starts.
func feed(b: PackedByteArray, now_s: float = 0.0) -> CrowdSnap:
	var d := decode_part(b)
	if d.is_empty():
		dropped += 1
		return null
	var tick: int = d["tick"]
	if tick <= _newest_done:
		dropped += 1
		return null
	for t: int in _pending.keys():
		if t < tick:
			_pending.erase(t)
			dropped += 1
	var parts: int = d["parts"]
	var entry: Dictionary = _pending.get(tick, {})
	if entry.is_empty():
		var arr: Array = []
		arr.resize(parts)
		entry = {"parts": arr, "got": 0}
		_pending[tick] = entry
	var slots: Array = entry["parts"]
	if slots.size() != parts or slots[d["part"]] != null:
		dropped += 1
		return null
	slots[d["part"]] = d["snap"]
	entry["got"] += 1
	if entry["got"] < parts:
		return null
	_pending.erase(tick)
	_newest_done = tick
	return _join(slots, now_s)


static func _join(slots: Array, now_s: float) -> CrowdSnap:
	var head: CrowdSnap = slots[0]
	# Lists in parts after the first are relative to the same origin; add it once for every part.
	for i in slots.size():
		var p: CrowdSnap = slots[i]
		_shift(p, head.origin_x, head.origin_y)
		if i > 0:
			head.append_part(p)
	head.recv_s = now_s
	return head


static func _shift(p: CrowdSnap, ox: int, oy: int) -> void:
	for i in p.px.size():
		p.px[i] += ox
		p.py[i] += oy
	for i in p.cx.size():
		p.cx[i] += ox
		p.cy[i] += oy
	for i in p.mx.size():
		p.mx[i] += ox
		p.my[i] += oy

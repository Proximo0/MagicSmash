class_name WorldWire
extends RefCounted
## The world's calls on the gateway wire (realm/gateway/src/world/wire.rs, docs/realm/world.md): request 0x60 with a
## sub-byte, reply 0x91, push 0xB1. The shell reads the BOARD (every field's tide and boss countdowns, the world
## boss's next ride, the copies and the queue) and the pushes (a queue place, a field boss or the world boss rising).

const T_WORLD := 0x60
const R_WORLD := 0x91
const P_WORLD := 0xB1

const Q_BOARD := 1

const K_BOARD := 1
const K_QUEUED := 2
const K_VAULT := 3
const K_MOVED := 4
const K_NEWS := 5


static func board() -> Array:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u8(Q_BOARD)
	return [T_WORLD, b.data_array]


static func decode_body(b: StreamPeerBuffer, d: Dictionary) -> void:
	d["k"] = b.get_u8()
	match int(d["k"]):
		K_BOARD:
			d["clock"] = b.get_64()
			var fields: Array[Dictionary] = []
			for i in b.get_u8():
				fields.append({"field": b.get_u8(), "tide_in": b.get_u32(), "tide_left": b.get_u32(), "boss": b.get_u8(), "boss_in": b.get_u32()})
			d["fields"] = fields
			d["world_field"] = b.get_u8()
			d["world_in"] = b.get_u32()
			d["queue"] = b.get_u32()
			var copies: Array[Array] = []
			for i in b.get_u16():
				copies.append([b.get_u8(), b.get_u8(), b.get_u32()])
			d["copies"] = copies
			d["vaults"] = b.get_u32()
		K_QUEUED:
			d["hero"] = b.get_64()
			d["field"] = b.get_u8()
			d["place"] = b.get_u32()
			d["of"] = b.get_u32()
		K_VAULT:
			d["code"] = b.get_64()
			d["vault"] = b.get_u8()
			d["seals"] = b.get_u8()
			d["host"] = GwWire.get_str(b)
			d["port"] = b.get_u16()
			d["ticket"] = b.get_64()
			d["key"] = b.get_data(16)[1] as PackedByteArray
		K_MOVED:
			d["hero"] = b.get_64()
			d["field"] = b.get_u8()
			d["copy"] = b.get_u8()
			d["host"] = GwWire.get_str(b)
			d["port"] = b.get_u16()
			d["ticket"] = b.get_64()
			d["key"] = b.get_data(16)[1] as PackedByteArray
		K_NEWS:
			d["nkind"] = b.get_u8()
			d["field"] = b.get_u8()
			d["boss"] = b.get_u8()
			d["in_ticks"] = b.get_u32()
		_:
			d["bad"] = true

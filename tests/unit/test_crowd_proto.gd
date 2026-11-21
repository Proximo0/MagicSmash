extends TestCase
## CrowdProto: the client side of protocol A v0 (docs/realm/crowd_test.md), checked against hand-built bytes.


func _u16(b: PackedByteArray, v: int) -> void:
	b.append(v & 255)
	b.append((v >> 8) & 255)


func _u32(b: PackedByteArray, v: int) -> void:
	_u16(b, v & 0xFFFF)
	_u16(b, (v >> 16) & 0xFFFF)


func _head(tick: int, part: int, parts: int) -> PackedByteArray:
	var b := PackedByteArray([0x82])
	_u32(b, tick)
	b.append(part)
	b.append(parts)
	return b


func _first_extra(b: PackedByteArray, ox: int, oy: int) -> void:
	_u32(b, ox)
	_u32(b, oy)
	_u16(b, 100)
	_u16(b, 50)
	_u16(b, 7)
	_u16(b, 3)
	_u32(b, 1000)
	_u32(b, 20000)
	_u16(b, 215)


func _mon(b: PackedByteArray, gap: PackedByteArray, dx: int, dy: int, hurt: int, kind: int, eighths: int, elite: int) -> void:
	b.append_array(gap)
	var v := dx | (dy << 12) | (hurt << 23)
	b.append(v & 255)
	b.append((v >> 8) & 255)
	b.append((v >> 16) & 255)
	b.append(kind | (eighths << 3) | (elite << 6))


func test_hello_input_bye_bytes() -> void:
	assert_eq(CrowdProto.hello(2, 3), PackedByteArray([1, 1, 0, 0, 0, 2, 3]))
	assert_eq(CrowdProto.input(0x01020304, 5, true, 4), PackedByteArray([2, 4, 3, 2, 1, 0x85, 4]))
	assert_eq(CrowdProto.input(9, 0, false, 1), PackedByteArray([2, 9, 0, 0, 0, 0, 1]))
	assert_eq(CrowdProto.bye(), PackedByteArray([3]))


func test_welcome() -> void:
	var b := PackedByteArray([0x81])
	_u32(b, 42)
	_u32(b, 1000)
	_u16(b, 20)
	_u32(b, 16384)
	_u32(b, 16000)
	var w := CrowdProto.decode_welcome(b)
	assert_eq(w["id"], 42)
	assert_eq(w["tick"], 1000)
	assert_eq(w["hz"], 20)
	assert_eq(w["width"], 16384)
	assert_eq(w["height"], 16000)
	assert_true(CrowdProto.decode_welcome(PackedByteArray([0x81, 1])).is_empty())
	assert_true(CrowdProto.decode_welcome(PackedByteArray([0x82])).is_empty())


func test_varint() -> void:
	assert_eq(CrowdProto.read_varint(PackedByteArray([5]), 0), [5, 1])
	assert_eq(CrowdProto.read_varint(PackedByteArray([0xAC, 0x02]), 0), [300, 2])
	assert_eq(CrowdProto.read_varint(PackedByteArray([0x80]), 0)[1], -1)


func test_single_part_snapshot() -> void:
	var b := _head(77, 0, 1)
	_first_extra(b, 1000, 2000)
	_u16(b, 1)
	_u16(b, 1)
	_u16(b, 3)
	# one player: id 9, dx 10, dy 20, class 2 race 1, faces left + hurt
	_u16(b, 9)
	_u16(b, 10)
	_u16(b, 20)
	b.append(2 | (1 << 3))
	b.append(5)
	_u16(b, 300)
	_u16(b, 400)
	# monsters with id gaps: ids 10, 13, 13 + 200 = 213 (a two byte varint)
	_mon(b, PackedByteArray([10]), 4095, 2047, 1, 7, 5, 1)
	_mon(b, PackedByteArray([3]), 0, 1, 0, 0, 7, 0)
	_mon(b, PackedByteArray([0xC8, 0x01]), 123, 456, 0, 3, 0, 0)
	var p := CrowdProto.new()
	var s := p.feed(b, 1.5)
	assert_true(s != null)
	assert_eq(s.tick, 77)
	assert_eq(s.my_x, 1000.0 + 100.0)
	assert_eq(s.my_y, 2000.0 + 50.0)
	assert_eq(s.my_health, 7)
	assert_eq(s.players_in_field, 1000)
	assert_eq(s.monsters_in_field, 20000)
	assert_near(s.tick_ms, 2.15)
	assert_eq(s.pid[0], 9)
	assert_eq(s.px[0], 1010.0)
	assert_eq(s.py[0], 2020.0)
	assert_eq(s.pkind[0], 10)
	assert_eq(s.pflag[0], 5)
	assert_eq(s.cx[0], 1300.0)
	assert_eq(s.cy[0], 2400.0)
	assert_eq(Array(s.mid), [10, 13, 213])
	assert_eq(s.mx[0], 1000.0 + 4095.0)
	assert_eq(s.my[0], 2000.0 + 2047.0)
	assert_eq(s.mflag[0], 7 | (5 << 3) | 0x40 | 0x80)
	assert_eq(s.mflag[1], 7 << 3)
	assert_eq(s.mflag[2], 3)
	assert_eq(s.mx[2], 1123.0)
	assert_eq(s.my[2], 2456.0)


func _part(tick: int, part: int, parts: int, first_id: int, with_header: bool) -> PackedByteArray:
	var b := _head(tick, part, parts)
	if with_header:
		_first_extra(b, 0, 0)
	_u16(b, 0)
	_u16(b, 0)
	_u16(b, 2)
	_mon(b, PackedByteArray([first_id]), part * 10, 5, 0, part, 1, 0)
	_mon(b, PackedByteArray([2]), part * 10 + 1, 6, 0, part, 1, 0)
	return b


func test_three_parts_out_of_order() -> void:
	var p := CrowdProto.new()
	assert_eq(p.feed(_part(8, 2, 3, 40, false)), null)
	assert_eq(p.feed(_part(8, 0, 3, 10, true)), null)
	var s := p.feed(_part(8, 1, 3, 20, false))
	assert_true(s != null)
	assert_eq(Array(s.mid), [10, 12, 20, 22, 40, 42])
	assert_eq(s.mx[2], 10.0)
	assert_eq(s.mx[4], 20.0)
	assert_eq(s.players_in_field, 1000)


func test_older_incomplete_tick_is_dropped() -> void:
	var p := CrowdProto.new()
	assert_eq(p.feed(_part(8, 0, 2, 1, true)), null)
	assert_eq(p.feed(_part(9, 0, 2, 1, true)), null)
	# the late second part of tick 8 can no longer complete it
	assert_eq(p.feed(_part(8, 1, 2, 5, false)), null)
	var s := p.feed(_part(9, 1, 2, 5, false))
	assert_true(s != null)
	assert_eq(s.tick, 9)
	# a finished tick is not delivered twice, and an older one never
	assert_eq(p.feed(_part(9, 1, 2, 5, false)), null)
	assert_eq(p.feed(_part(7, 0, 1, 1, true)), null)
	assert_true(p.dropped >= 3)


func test_malformed_is_ignored() -> void:
	var p := CrowdProto.new()
	assert_eq(p.feed(PackedByteArray([0x82, 1, 2])), null)
	assert_eq(p.feed(PackedByteArray([0x55, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])), null)
	var b := _part(3, 0, 1, 1, true)
	b.resize(b.size() - 2)
	assert_eq(p.feed(b), null)

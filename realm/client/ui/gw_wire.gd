class_name GwWire
extends RefCounted
## The gateway's TCP wire (docs/realm/wire.md, realm/gateway/src/proto/) in GDScript: every request the shell
## sends is built here as a body, every reply and push is read here into a Dictionary with a "t" (the type
## constant below) and its fields. Frames are `u32 len, u8 type, u32 tag, body`, little endian; strings are
## `u16 len, UTF-8`. A u64 is a GDScript int (a ticket above 2^63 is a negative int with the same bits).

# Who owns which type byte: the server's one table, realm/gateway/src/proto/ranges.rs (mirror it here when it changes).
#   module   job  requests      replies     pushes
#   core     W1   0x01..0x32    0x80..0x8A  0xA0..0xA7   (this file)
#   economy  E1   0x33..0x3F    0x8B        0xA8         (econ_wire.gd)
#   social   T1   0x40..0x5F    0x90        0xB0         (this file, T_SOC_*)
#   world    W2   0x60..0x6F    0x91        0xB1         (world_wire.gd)
#   homes    H1   0x70..0x73    0x8C        0xA9         (homes/home_wire.gd)
#   pvp      R3   0x74..0x77    0x8D        0xAA         (reserved)
#   steam    P1   0x78..0x7B    0x8E        0xAB         (reserved)
# 0x00 and 0xC0..0xEF belong to nobody; 0xF0..0xFF never go on the wire (R_LOST below is the client's own).

# requests
const T_LOGIN_DEV := 0x01
const T_LIST_HEROES := 0x03
const T_CREATE_HERO := 0x04
const T_DELETE_HERO := 0x05
const T_UNDELETE_HERO := 0x06
const T_ENTER_TOWN := 0x07
const T_LEAVE_TOWN := 0x08
const T_TOWN_INPUT := 0x09
const T_CHAT := 0x0A
const T_FIELD_TICKET := 0x0B
const T_INVENTORY := 0x0C
const T_BANK_DEPOSIT := 0x0D
const T_BANK_WITHDRAW := 0x0E
const T_MAIL_TAKE := 0x10
const T_SPEND_POINT := 0x11
const T_SET_DECK := 0x12
const T_SET_BELT := 0x13
const T_LEARN_PAGE := 0x14
const T_EQUIP := 0x15
const T_UNEQUIP := 0x16
const T_SOCKET := 0x17
const T_UNSOCKET := 0x18
const T_CHOOSE_JOB := 0x19
const T_PING := 0x1A
const T_RENAME_HERO := 0x1B
const T_SALVAGE := 0x1C
const T_UPGRADE := 0x1D
const T_REROLL := 0x1E
const T_FUSE := 0x1F
const T_CARDS := 0x30
const T_BUY := 0x31
const T_SELL := 0x32
# the social calls (job T1, docs/realm/social.md): tags 0x40.., one reply tag and one push tag
const T_SOC_TALK := 0x40
const T_SOC_PARTY_INVITE := 0x41
const T_SOC_PARTY_ANSWER := 0x42
const T_SOC_PARTY_LEAVE := 0x43
const T_SOC_PARTY_KICK := 0x44
const T_SOC_PARTY_LEAD := 0x45
const T_SOC_PARTY_GO := 0x46
const T_SOC_PARTY_INFO := 0x47
const T_SOC_GUILD_CREATE := 0x48
const T_SOC_GUILD_INVITE := 0x49
const T_SOC_GUILD_ANSWER := 0x4A
const T_SOC_GUILD_LEAVE := 0x4B
const T_SOC_GUILD_KICK := 0x4C
const T_SOC_GUILD_RANK := 0x4D
const T_SOC_GUILD_MOTD := 0x4F
const T_SOC_GUILD_POST := 0x50
const T_SOC_GUILD_UNPOST := 0x51
const T_SOC_GUILD_INFO := 0x54
const T_SOC_FRIEND_ADD := 0x56
const T_SOC_FRIEND_ANSWER := 0x57
const T_SOC_FRIEND_REMOVE := 0x58
const T_SOC_IGNORE := 0x59
const T_SOC_LISTS := 0x5A
const T_SOC_REPORT := 0x5B
const T_SOC_DUEL := 0x5F
const DUEL_CHALLENGE := 0
const DUEL_ACCEPT := 1
const DUEL_DECLINE := 2
# replies
const R_OK := 0x80
const R_ERR := 0x81
const R_LOGIN := 0x82
const R_HEROES := 0x83
const R_HERO_CREATED := 0x84
const R_TOWN := 0x85
const R_TICKET := 0x86
const R_INVENTORY := 0x87
const R_PONG := 0x88
const R_SMITH := 0x89
const R_CARDS := 0x8A
const R_SOCIAL := 0x90
# pushes
const P_TOWN_SNAPSHOT := 0xA0
const P_TOWN_CHAT := 0xA1
const P_TOWN_ARRIVE := 0xA2
const P_TOWN_DEPART := 0xA3
const P_OUTING := 0xA4
const P_SOCIAL := 0xB0
## Not on the wire: the link's own answer when the connection is gone or a reply never came.
const R_LOST := 0xFF

const FRAME_MAX := 1 << 20

# Error codes of R_ERR (proto/mod.rs `code`).
const E_BAD_REQUEST := 1
const E_NOT_LOGGED_IN := 2
const E_DISABLED := 3
const E_NOT_YOURS := 4
const E_FULL := 5
const E_MISSING := 6
const E_NAME_TAKEN := 7
const E_BAD_NAME := 8
const E_INSUFFICIENT := 9
const E_REFUSED := 10
const E_BUSY := 11
const E_BANNED := 12
const E_INVALID := 13
const E_SLOW_DOWN := 14
const E_INTERNAL := 15
const E_NO_FIELD := 16
const E_MUTED := 17

## Chat channels (the say channel is the older T_CHAT).
const CHAN_TOWN := 1
const CHAN_TRADE := 2
const CHAN_PARTY := 3
const CHAN_GUILD := 4
const CHAN_WHISPER := 5
const CHAN_NAMES: Array[String] = ["SAY", "TOWN", "TRADE", "PARTY", "GUILD", "WHISPER"]
const RANK_NAMES: Array[String] = ["LEADER", "OFFICER", "MEMBER", "RECRUIT"]


static func _buf() -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	return b


static func put_str(b: StreamPeerBuffer, s: String) -> void:
	var bytes: PackedByteArray = s.to_utf8_buffer()
	if bytes.size() > 65535:
		bytes = bytes.slice(0, 65535)
	b.put_u16(bytes.size())
	b.put_data(bytes)


static func get_str(b: StreamPeerBuffer) -> String:
	var n: int = b.get_u16()
	if n == 0:
		return ""
	var r: Array = b.get_data(n)
	return (r[1] as PackedByteArray).get_string_from_utf8()


## A frame ready to send.
static func frame(t: int, tag: int, body: PackedByteArray) -> PackedByteArray:
	var b := _buf()
	b.put_u32(5 + body.size())
	b.put_u8(t)
	b.put_u32(tag)
	b.put_data(body)
	return b.data_array


## A Thing: an item (item != 0) or a count of a stack kind.
static func put_thing(b: StreamPeerBuffer, item: int, stack_kind: int, count: int) -> void:
	if item != 0:
		b.put_u8(0)
		b.put_u64(item)
	else:
		b.put_u8(1)
		b.put_u32(stack_kind)
		b.put_u64(count)


# ---- requests: each returns [type, body]

static func login_dev(name: String) -> Array:
	var b := _buf()
	put_str(b, name)
	return [T_LOGIN_DEV, b.data_array]


static func plain(t: int) -> Array:
	return [t, PackedByteArray()]


static func hero_only(t: int, hero: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	return [t, b.data_array]


static func create_hero(name: String, race: int, cls: int, look: int, self_found: bool) -> Array:
	var b := _buf()
	put_str(b, name)
	b.put_u8(race)
	b.put_u8(cls)
	b.put_u8(1 if self_found else 0)
	b.put_u32(look)
	return [T_CREATE_HERO, b.data_array]


static func rename_hero(hero: int, name: String) -> Array:
	var b := _buf()
	b.put_u64(hero)
	put_str(b, name)
	return [T_RENAME_HERO, b.data_array]


static func town_input(dir: int) -> Array:
	var b := _buf()
	b.put_u8(dir)
	return [T_TOWN_INPUT, b.data_array]


static func chat(text: String) -> Array:
	var b := _buf()
	put_str(b, text)
	return [T_CHAT, b.data_array]


static func field_ticket(hero: int, field: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u8(field)
	return [T_FIELD_TICKET, b.data_array]


## Bank deposit or withdraw of an item (item != 0) or a stack.
static func bank(deposit: bool, hero: int, item: int, stack_kind: int, count: int, tab: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	put_thing(b, item, stack_kind, count)
	b.put_u32(tab)
	return [T_BANK_DEPOSIT if deposit else T_BANK_WITHDRAW, b.data_array]


static func spend_point(hero: int, stat: int, n: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u8(stat)
	b.put_u16(n)
	return [T_SPEND_POINT, b.data_array]


static func set_deck(hero: int, cards: Array) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u8(cards.size())
	for c in cards:
		b.put_u16(int(c))
	return [T_SET_DECK, b.data_array]


static func set_belt(hero: int, kinds: Array) -> Array:
	var b := _buf()
	b.put_u64(hero)
	for i in 3:
		b.put_u32(int(kinds[i]) if i < kinds.size() else 0)
	return [T_SET_BELT, b.data_array]


static func learn_page(hero: int, card: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u16(card)
	return [T_LEARN_PAGE, b.data_array]


static func hero_item(t: int, hero: int, item: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u64(item)
	return [t, b.data_array]


static func socket(hero: int, item: int, sock: int, kind: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u64(item)
	b.put_u8(sock)
	b.put_u32(kind)
	return [T_SOCKET, b.data_array]


static func unsocket(hero: int, item: int, sock: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u64(item)
	b.put_u8(sock)
	return [T_UNSOCKET, b.data_array]


static func choose_job(hero: int, job: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u8(job)
	return [T_CHOOSE_JOB, b.data_array]


static func fuse(hero: int, stat: int, grade: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u8(stat)
	b.put_u8(grade)
	return [T_FUSE, b.data_array]


## Takes an item (item != 0) or a count of a stack from her mail shelf into her bag.
static func mail_take(hero: int, item: int, stack_kind: int, count: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	put_thing(b, item, stack_kind, count)
	return [T_MAIL_TAKE, b.data_array]


static func buy(hero: int, kind: int, n: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u32(kind)
	b.put_u32(n)
	return [T_BUY, b.data_array]


static func soc_talk(hero: int, chan: int, to: String, text: String) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u8(chan)
	put_str(b, to)
	put_str(b, text)
	return [T_SOC_TALK, b.data_array]


## A social request that is only the hero (leave, info, lists).
static func soc_hero(t: int, hero: int) -> Array:
	return hero_only(t, hero)


## A hero and a name or text (invite, create, post, friend add, motd).
static func soc_str(t: int, hero: int, s: String) -> Array:
	var b := _buf()
	b.put_u64(hero)
	put_str(b, s)
	return [t, b.data_array]


## A hero and an id (party kick or lead: a hero id; guild kick: an account id).
static func soc_id(t: int, hero: int, id: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u64(id)
	return [t, b.data_array]


## A duel in the training yard: challenge the hero `name`, accept or decline her challenge (DUEL_*).
static func soc_duel(hero: int, op: int, name: String) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u8(op)
	put_str(b, name)
	return [T_SOC_DUEL, b.data_array]


## Answers an invitation: party (the inviter's hero), guild (the guild id) or friend (the account).
static func soc_answer(t: int, hero: int, id: int, accept: bool) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u64(id)
	b.put_u8(1 if accept else 0)
	return [t, b.data_array]


static func soc_guild_rank(hero: int, account: int, rank: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u64(account)
	b.put_u8(rank)
	return [T_SOC_GUILD_RANK, b.data_array]


static func soc_party_go(hero: int, field: int) -> Array:
	var b := _buf()
	b.put_u64(hero)
	b.put_u8(field)
	return [T_SOC_PARTY_GO, b.data_array]


static func soc_ignore(hero: int, name: String, on: bool) -> Array:
	var b := _buf()
	b.put_u64(hero)
	put_str(b, name)
	b.put_u8(1 if on else 0)
	return [T_SOC_IGNORE, b.data_array]


## `reason`: 0 spam, 1 abuse, 2 cheating, 3 name, 4 other.
static func soc_report(hero: int, name: String, reason: int, text: String) -> Array:
	var b := _buf()
	b.put_u64(hero)
	put_str(b, name)
	b.put_u8(reason)
	put_str(b, text)
	return [T_SOC_REPORT, b.data_array]


# ---- replies and pushes

static func _party(b: StreamPeerBuffer) -> Dictionary:
	if b.get_u8() == 0:
		return {}
	var p := {}
	p["id"] = b.get_u64()
	p["leader"] = b.get_64()
	var has_copy: int = b.get_u8()
	var field: int = b.get_u8()
	var copy: int = b.get_u8()
	p["copy"] = [field, copy] if has_copy != 0 else []
	var members: Array[Dictionary] = []
	for i in b.get_u8():
		var m := {}
		m["hero"] = b.get_64()
		m["name"] = get_str(b)
		m["class"] = b.get_u8()
		m["level"] = b.get_u16()
		m["online"] = b.get_u8() != 0
		members.append(m)
	p["members"] = members
	return p


static func _guild(b: StreamPeerBuffer) -> Dictionary:
	if b.get_u8() == 0:
		return {}
	var g := {}
	g["id"] = b.get_u64()
	g["name"] = get_str(b)
	g["motd"] = get_str(b)
	g["my_rank"] = b.get_u8()
	var perms: Array[int] = []
	for i in 4:
		perms.append(b.get_u16())
	g["perms"] = perms
	var members: Array[Dictionary] = []
	for i in b.get_u16():
		var m := {}
		m["account"] = b.get_64()
		m["name"] = get_str(b)
		m["rank"] = b.get_u8()
		m["online"] = b.get_u8() != 0
		members.append(m)
	g["members"] = members
	var board: Array[Dictionary] = []
	for i in b.get_u16():
		var p := {}
		p["id"] = b.get_u64()
		p["author"] = get_str(b)
		p["text"] = get_str(b)
		p["at"] = b.get_64()
		board.append(p)
	g["board"] = board
	return g


static func _social_reply(b: StreamPeerBuffer, d: Dictionary) -> void:
	d["k"] = b.get_u8()
	match int(d["k"]):
		0:
			d["party"] = _party(b)
		1:
			d["guild"] = _guild(b)
		2:
			d["guild_id"] = b.get_u64()
		3:
			var items: Array[Dictionary] = []
			for i in b.get_u32():
				items.append(_item(b))
			var stacks: Array[Array] = []
			for i in b.get_u32():
				var kind: int = b.get_u32()
				stacks.append([0, kind, b.get_64()])
			d["items"] = items
			d["stacks"] = stacks
		4:
			var friends: Array[Dictionary] = []
			for i in b.get_u16():
				var f := {}
				f["account"] = b.get_64()
				f["name"] = get_str(b)
				f["online"] = b.get_u8() != 0
				f["place"] = b.get_u8()
				friends.append(f)
			var pending: Array[Dictionary] = []
			for i in b.get_u16():
				var a: int = b.get_64()
				pending.append({"account": a, "name": get_str(b)})
			var ignores: Array[Dictionary] = []
			for i in b.get_u16():
				var a2: int = b.get_64()
				ignores.append({"account": a2, "name": get_str(b)})
			d["friends"] = friends
			d["pending"] = pending
			d["ignores"] = ignores
		5:
			d["report"] = b.get_u64()


static func _social_push(b: StreamPeerBuffer, d: Dictionary) -> void:
	d["k"] = b.get_u8()
	match int(d["k"]):
		0:
			d["chan"] = b.get_u8()
			d["from"] = get_str(b)
			d["to"] = get_str(b)
			d["text"] = get_str(b)
		1:
			d["inviter"] = b.get_64()
			d["name"] = get_str(b)
		2:
			d["party"] = _party(b)
		3:
			d["field"] = b.get_u8()
		4:
			d["guild"] = b.get_u64()
			d["guild_name"] = get_str(b)
			d["from"] = get_str(b)
		5:
			pass
		6:
			d["from"] = b.get_64()
			d["name"] = get_str(b)
		7:
			d["account"] = b.get_64()
			d["name"] = get_str(b)
			d["online"] = b.get_u8() != 0
			d["place"] = b.get_u8()
		8:
			d["text"] = get_str(b)
		12:
			d["from"] = b.get_64()
			d["name"] = get_str(b)
		13:
			d["name"] = get_str(b)
		14:
			d["duel"] = b.get_64()
			d["foe"] = b.get_64()
			d["name"] = get_str(b)
			d["seed"] = b.get_64()
		15:
			d["duel"] = b.get_64()
			d["winner"] = b.get_64()
			d["loser"] = b.get_64()
			d["draw"] = b.get_u8() != 0



static func _member(b: StreamPeerBuffer) -> Dictionary:
	var m := {}
	m["id"] = b.get_u16()
	m["name"] = get_str(b)
	m["class"] = b.get_u8()
	m["race"] = b.get_u8()
	m["level"] = b.get_u16()
	m["look"] = b.get_u32()
	return m


static func _hero(b: StreamPeerBuffer) -> Dictionary:
	var h := {}
	h["id"] = b.get_64()
	h["name"] = get_str(b)
	h["race"] = b.get_u8()
	h["class"] = b.get_u8()
	# The hero record says no job with core's NONE (255); the client's word for it is NO_JOB.
	var job: int = b.get_u8()
	h["job"] = job if job < GameNames.JOBS.size() else GameNames.NO_JOB
	h["self_found"] = b.get_u8() != 0
	h["deleted"] = b.get_u8() != 0
	h["look"] = b.get_u32()
	h["level"] = b.get_u16()
	h["xp"] = b.get_u64()
	h["unspent"] = b.get_u16()
	var stats: Array[int] = []
	for i in 6:
		stats.append(b.get_u16())
	h["stats"] = stats
	var deck: Array[int] = []
	var n: int = b.get_u8()
	for i in n:
		deck.append(b.get_u16())
	h["deck"] = deck
	var belt: Array[int] = []
	for i in 3:
		belt.append(b.get_u32())
	h["belt"] = belt
	var ways: Array[int] = []
	for i in 6:
		ways.append(b.get_32())
	h["waystones"] = ways
	return h


static func _item(b: StreamPeerBuffer) -> Dictionary:
	var it := {}
	it["id"] = b.get_64()
	it["base"] = b.get_u32()
	it["gear_slot"] = b.get_u8()
	it["rarity"] = b.get_u8()
	it["sockets"] = b.get_u8()
	it["place"] = b.get_u8()
	it["level"] = b.get_u16()
	it["tab"] = b.get_u32()
	it["slot"] = b.get_u32()
	var lines: Array = []
	var n: int = b.get_u8()
	for i in n:
		var stat: int = b.get_u8()
		lines.append([stat, b.get_u16()])
	it["lines"] = lines
	it["plus"] = b.get_u8()
	var socketed: Array[int] = []
	for i in int(it["sockets"]):
		socketed.append(b.get_u32())
	it["socketed"] = socketed
	return it


## Reads one reply or push body. A body that does not read cleanly gives {"t": R_ERR, "code": 0, "msg": "unreadable"}.
static func decode(t: int, body: PackedByteArray) -> Dictionary:
	var b := _buf()
	b.data_array = body
	var d := {"t": t}
	match t:
		R_OK, R_PONG:
			pass
		R_ERR:
			d["code"] = b.get_u16()
			d["msg"] = get_str(b)
		R_LOGIN:
			d["account"] = b.get_64()
		R_HEROES:
			var heroes: Array[Dictionary] = []
			for i in b.get_u16():
				heroes.append(_hero(b))
			d["heroes"] = heroes
		R_HERO_CREATED:
			d["hero"] = b.get_64()
		R_TOWN:
			d["room"] = b.get_u32()
			d["me"] = b.get_u16()
			d["size"] = b.get_u16()
			var members: Array[Dictionary] = []
			for i in b.get_u16():
				members.append(_member(b))
			d["members"] = members
		R_TICKET:
			d["host"] = get_str(b)
			d["port"] = b.get_u16()
			d["ticket"] = b.get_64()
			d["field"] = b.get_u8()
			d["copy"] = b.get_u8()
			# The ticket's secret: the field HELLO proves the ticket with it (docs/realm/wire.md).
			d["key"] = b.get_data(16)[1] as PackedByteArray
		R_INVENTORY:
			var items: Array[Dictionary] = []
			for i in b.get_u32():
				items.append(_item(b))
			var stacks: Array[Array] = []
			for i in b.get_u32():
				var place: int = b.get_u8()
				var kind: int = b.get_u32()
				stacks.append([place, kind, b.get_64()])
			d["items"] = items
			d["stacks"] = stacks
		R_SMITH:
			d["item"] = b.get_64()
			d["plus"] = b.get_u8()
			d["success"] = b.get_u8() != 0
			d["amount"] = b.get_64()
		R_CARDS:
			var cards: Array[int] = []
			for i in b.get_u16():
				cards.append(b.get_u16())
			d["cards"] = cards
		R_SOCIAL:
			_social_reply(b, d)
		HomeWire.R_HOME, HomeWire.P_HOME:
			HomeWire.decode_body(b, d)
		EconWire.R_ECON, EconWire.P_ECON:
			EconWire.decode_body(b, d)
		WorldWire.R_WORLD, WorldWire.P_WORLD:
			WorldWire.decode_body(b, d)
		P_SOCIAL:
			_social_push(b, d)
		P_TOWN_SNAPSHOT:
			d["tick"] = b.get_u32()
			var at: Array[Array] = []
			for i in b.get_u16():
				var id: int = b.get_u16()
				var x: int = b.get_u16()
				var y: int = b.get_u16()
				at.append([id, x, y, b.get_u8()])
			d["at"] = at
		P_TOWN_CHAT:
			d["from"] = b.get_u16()
			d["name"] = get_str(b)
			d["text"] = get_str(b)
		P_TOWN_ARRIVE:
			d["member"] = _member(b)
		P_TOWN_DEPART:
			d["id"] = b.get_u16()
		P_OUTING:
			d["hero"] = b.get_64()
			d["coin"] = b.get_u64()
			d["xp"] = b.get_u64()
			d["levels"] = b.get_u16()
			d["potions"] = b.get_u32()
			d["left"] = b.get_u8()
		_:
			return {"t": R_ERR, "code": 0, "msg": "unknown reply %d" % t}
	if b.get_position() != body.size():
		return {"t": R_ERR, "code": 0, "msg": "unreadable reply %d" % t}
	return d

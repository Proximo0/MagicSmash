class_name Shell
extends Node
## Everything outside the field: the title, the login, the hero list and builder, the town with its stations, the
## sheet, the bag and the settings, and the hand-off to the field client (a ticket) and back (the outing's result).
## One Shell owns the gateway connection (GwLink), what the screens share (account, heroes, the chosen hero, her
## inventory and cards, the town's roster) and the stack of screens: one base screen and the panels over it.
##   godot --path realm/client [-- --gateway=host:port] [--dev=NAME] [--dev-cert=PEM | --plain]
## The gateway connection is TLS, checked against Godot's trusted roots; a dev build (only) may trust one
## certificate file instead (--dev-cert, e.g. the gateway's DB.dev-cert.pem) or speak plain TCP (--plain, for a
## --dev-login gateway). See GwLink.
## The field is the RealmClient scene node added while a hero is out; the shell's canvas is 960 x 540, the field's
## 480 x 270, switched with the window's content scale.

signal screen_changed(name: String)
signal field_started(field: int)
signal field_ended(outing: Dictionary)
signal data_changed
## The social state changed (a chat line, a party or guild update, an invitation): panels repaint by themselves.
signal social_changed

const SHELL_SIZE: Vector2i = Vector2i(960, 540)
const FIELD_SIZE: Vector2i = Vector2i(480, 270)
const DEFAULT_GATEWAY: String = "127.0.0.1:7700"
## Leaving a field with Esc twice within this many seconds (the first press warns: it costs half the haul).
const ESC_LEAVE_S: float = 3.0

var link: GwLink = GwLink.new()
var layer: CanvasLayer = CanvasLayer.new()
var gateway_host: String = "127.0.0.1"
var gateway_port: int = 7700

var account: int = 0
var dev_name: String = ""
var heroes: Array[Dictionary] = []
var hero: Dictionary = {}
## The hero's things: {"items": [...], "stacks": [[place, kind, count], ...]}, and the deck cards she may use.
var inv: Dictionary = {"items": [], "stacks": []}
var cards: Array[int] = []
var town: Dictionary = {}
## Homes and the shared places (job H1): where she is as [kind, arg] (HomeMap: [0, 0] the plaza), the plots of the
## street she stands in, and her campfire rest ({} until asked).
var place: Array = [0, 0]
var street_plots: Array[Dictionary] = []
var rest: Dictionary = {}
## The house she stands in (the gateway's House reply: owner, rule, items by cell, guestbook), {} elsewhere.
var house: Dictionary = {}
var last_outing: Dictionary = {}
## Living together (job T1): kept up to date by the social pushes whether or not a panel is open.
const CHAT_KEEP: int = 120
var chat_lines: Array[Dictionary] = []
var party: Dictionary = {}
var guild: Dictionary = {}
var friends: Array[Dictionary] = []
var ignores: Array[Dictionary] = []
## Invitations waiting: {"kind": "party" | "guild" | "friend", "id": inviter hero / guild / account, "name": who, "what": text}.
var invites: Array[Dictionary] = []
## A field the party's leader called us to (-1: none).
var field_call: int = -1

var base: UiScreen = null
var panels: Array[UiScreen] = []
var base_name: String = ""
var field_client: Node = null
var in_field: bool = false
var _esc_at: float = -100.0
var _now: float = 0.0
## Where the field client's UDP goes when a ticket names no host: the gateway's own address.
var field_flags: Array[String] = []


func _ready() -> void:
	ShellSettings.load_file()
	ShellSettings.apply(get_window())
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		if kv[0] == "plain":
			link.plain = true
		elif kv[0] == "dev-cert" and kv.size() > 1:
			link.dev_cert = kv[1]
	add_child(link)
	layer.layer = 10
	add_child(layer)
	link.pushed.connect(_on_push)
	link.lost.connect(_on_lost)
	use_shell_canvas()
	RenderingServer.set_default_clear_color(UiKit.BLACK)


func _process(delta: float) -> void:
	_now += delta


func use_shell_canvas() -> void:
	var w: Window = get_window()
	w.content_scale_size = SHELL_SIZE
	w.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


func use_field_canvas() -> void:
	var w: Window = get_window()
	w.content_scale_size = FIELD_SIZE
	w.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER


func set_gateway(addr: String) -> void:
	var hp: PackedStringArray = addr.split(":")
	gateway_host = hp[0]
	if hp.size() > 1:
		gateway_port = int(hp[1])


# ---- screens

func top() -> UiScreen:
	return panels[panels.size() - 1] if not panels.is_empty() else base


## Replaces the base screen (and drops every panel).
func show_base(s: UiScreen, name: String) -> UiScreen:
	for p in panels:
		p.queue_free()
	panels.clear()
	if base != null:
		base.queue_free()
	base = s
	base_name = name
	s.shell = self
	layer.add_child(s)
	screen_changed.emit(name)
	return s


## Puts a panel over the base screen; it closes itself with `close()` (its `closed` signal).
func open_panel(p: UiScreen) -> UiScreen:
	p.shell = self
	panels.append(p)
	layer.add_child(p)
	p.closed.connect(_panel_closed.bind(p))
	screen_changed.emit(p.get_script().get_global_name())
	return p


func _panel_closed(p: UiScreen) -> void:
	panels.erase(p)
	p.queue_free()


func close_panels() -> void:
	for p in panels.duplicate():
		_panel_closed(p)


func panel_of(cls_name: String) -> UiScreen:
	for p in panels:
		if p.get_script().get_global_name() == cls_name:
			return p
	return null


func _unhandled_input(e: InputEvent) -> void:
	if in_field:
		if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE:
			_field_escape()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var t: UiScreen = top()
		if t != null and t.on_key(e):
			get_viewport().set_input_as_handled()


# ---- calls

## A request whose failure is shown to the player: returns the reply (R_ERR or R_LOST included).
func act(req: Array, ok_text: String = "") -> Dictionary:
	var r: Dictionary = await link.call_req(req)
	var t: UiScreen = top()
	if int(r["t"]) == GwWire.R_ERR or int(r["t"]) == GwWire.R_LOST:
		if t != null:
			t.say(error_text(r), true)
	elif not ok_text.is_empty() and t != null:
		t.say(ok_text)
	return r


static func error_text(r: Dictionary) -> String:
	var m: String = String(r.get("msg", "")).to_upper()
	if int(r["t"]) == GwWire.R_LOST:
		return "THE GATEWAY IS NOT ANSWERING"
	match int(r.get("code", 0)):
		GwWire.E_NAME_TAKEN:
			return "THAT NAME IS TAKEN"
		GwWire.E_BAD_NAME:
			return "A NAME IS 3 TO 16 LETTERS, DIGITS, ' AND -, FIRST A LETTER"
		GwWire.E_FULL:
			return "NO ROOM: " + m
		GwWire.E_INSUFFICIENT:
			return "YOU CANNOT AFFORD IT"
		GwWire.E_BUSY:
			return "SHE IS ALREADY SOMEWHERE"
		GwWire.E_DISABLED:
			return "LOGIN IS OFF ON THIS SERVER"
		GwWire.E_NO_FIELD:
			return "THAT FIELD IS CLOSED"
		GwWire.E_MUTED:
			return "YOU ARE SILENCED"
		GwWire.E_SLOW_DOWN:
			return "SLOW DOWN"
	return m if not m.is_empty() else "SOMETHING WENT WRONG"


func connect_gateway() -> bool:
	if link.connected:
		return true
	return await link.open(gateway_host, gateway_port)


## Logs in with a dev name and shows the hero list. Returns "" or the problem.
func login(name: String) -> String:
	if not await connect_gateway():
		# A refused certificate says so; it never falls back to plain text.
		if not link.last_error.is_empty():
			return link.last_error.to_upper()
		return "CANNOT REACH %s:%d" % [gateway_host, gateway_port]
	var r: Dictionary = await link.call_req(GwWire.login_dev(name))
	if int(r["t"]) != GwWire.R_LOGIN:
		return error_text(r)
	account = int(r["account"])
	dev_name = name
	var err: String = await refresh_heroes()
	if not err.is_empty():
		return err
	var s := HeroListScreen.new()
	show_base(s, "hero_list")
	return ""


func refresh_heroes() -> String:
	var r: Dictionary = await link.call_req(GwWire.plain(GwWire.T_LIST_HEROES))
	if int(r["t"]) != GwWire.R_HEROES:
		return error_text(r)
	heroes.clear()
	for h in r["heroes"]:
		heroes.append(h)
	# Keep the chosen hero's numbers fresh.
	if not hero.is_empty():
		var id: int = int(hero["id"])
		hero = {}
		for h in heroes:
			if int(h["id"]) == id:
				hero = h
	data_changed.emit()
	return ""


func refresh_inventory() -> void:
	if hero.is_empty():
		return
	var r: Dictionary = await link.call_req(GwWire.hero_only(GwWire.T_INVENTORY, int(hero["id"])))
	if int(r["t"]) == GwWire.R_INVENTORY:
		inv = {"items": r["items"], "stacks": r["stacks"]}
	var c: Dictionary = await link.call_req(GwWire.hero_only(GwWire.T_CARDS, int(hero["id"])))
	if int(c["t"]) == GwWire.R_CARDS:
		cards = c["cards"]
	data_changed.emit()


## Refreshes the hero's numbers and her things after a change.
func refresh_all() -> void:
	await refresh_heroes()
	await refresh_inventory()


func hero_id() -> int:
	return int(hero.get("id", 0))


func create_hero(name: String, race: int, cls: int, look: int) -> String:
	var r: Dictionary = await link.call_req(GwWire.create_hero(name, race, cls, look, false))
	if int(r["t"]) != GwWire.R_HERO_CREATED:
		return error_text(r)
	var err: String = await refresh_heroes()
	for h in heroes:
		if int(h["id"]) == int(r["hero"]):
			hero = h
	return err


## What the hero carries: a stack's count at a place (1 bag, 3 bank), 0 when none.
func stack_count(place: int, kind: int) -> int:
	for s in inv["stacks"]:
		if int(s[0]) == place and int(s[1]) == kind:
			return int(s[2])
	return 0


func coin() -> int:
	return stack_count(GameNames.PLACE_BAG, GameNames.KIND_COIN)


func items_at(place: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in inv["items"]:
		if int(it["place"]) == place:
			out.append(it)
	return out


func stacks_at(place: int) -> Array[Array]:
	var out: Array[Array] = []
	for s in inv["stacks"]:
		if int(s[0]) == place:
			out.append(s)
	return out


func item_by_id(id: int) -> Dictionary:
	for it in inv["items"]:
		if int(it["id"]) == id:
			return it
	return {}


# ---- the town

## Enters the town with the chosen hero and shows it.
func enter_town() -> String:
	if hero.is_empty():
		return "NO HERO CHOSEN"
	var r: Dictionary = await link.call_req(GwWire.hero_only(GwWire.T_ENTER_TOWN, hero_id()))
	if int(r["t"]) != GwWire.R_TOWN:
		return error_text(r)
	town = r
	place = [0, 0]
	street_plots = []
	rest = {}
	house = {}
	await refresh_inventory()
	await refresh_social()
	var s := TownScreen.new()
	show_base(s, "town")
	return ""


## Walks her to another place (a door, the places list): the gateway moves her to that place's room and the town
## screen is drawn again for it. Returns "" or the problem (shown on the screen too).
func go_place(kind: int, arg: int) -> String:
	var r: Dictionary = await act(HomeWire.go(hero_id(), kind, arg))
	if int(r["t"]) != GwWire.R_TOWN:
		return error_text(r)
	town = r
	place = [kind, arg]
	street_plots = []
	house = {}
	if kind == HomeMap.HOUSE:
		await refresh_house()
	if kind == HomeMap.STREET:
		var s: Dictionary = await link.call_req(HomeWire.with_u32(HomeWire.Q_STREET, hero_id(), arg))
		if int(s["t"]) == HomeWire.R_HOME and int(s.get("k", -1)) == HomeWire.K_STREET:
			street_plots = s["plots"]
	show_base(TownScreen.new(), "town")
	return ""


## Reads the house she stands in again (after a placement, a rule, a guestbook line).
func refresh_house() -> void:
	var h: Dictionary = await link.call_req(HomeWire.hero_only(HomeWire.Q_HOUSE, hero_id()))
	if int(h["t"]) == HomeWire.R_HOME and int(h.get("k", -1)) == HomeWire.K_HOUSE:
		house = h
	data_changed.emit()


## Leaves the town room (the gateway frees the hero) and returns to the hero list.
func leave_town() -> void:
	await link.call_req(GwWire.plain(GwWire.T_LEAVE_TOWN))
	town = {}
	reset_social()
	await refresh_heroes()
	show_base(HeroListScreen.new(), "hero_list")


func logout() -> void:
	link.close()
	reset_social()
	account = 0
	heroes.clear()
	hero = {}
	show_base(TitleScreen.new(), "title")


func _on_push(msg: Dictionary) -> void:
	var t: int = int(msg["t"])
	if t == GwWire.P_OUTING:
		_on_outing(msg)
		return
	if t == GwWire.P_SOCIAL:
		_on_social(msg)
		return
	if t == HomeWire.P_HOME:
		_on_home(msg)
		return
	if base is TownScreen:
		(base as TownScreen).on_push(msg)


# ---- homes

func _on_home(m: Dictionary) -> void:
	if int(m.get("k", -1)) != HomeWire.K_NOTICE:
		return
	var t: UiScreen = top()
	if t == null:
		return
	match int(m["nkind"]):
		0:
			t.say("%s CAME INTO YOUR HOUSE" % String(m["text"]).to_upper())
		1:
			t.say("%s SIGNED YOUR GUESTBOOK" % String(m["text"]).to_upper())


# ---- living together

func reset_social() -> void:
	chat_lines.clear()
	party = {}
	guild = {}
	friends.clear()
	ignores.clear()
	invites.clear()
	field_call = -1
	social_changed.emit()


## Reads her party, guild, friends and requests again.
func refresh_social() -> void:
	var h: int = hero_id()
	var p: Dictionary = await link.call_req(GwWire.soc_hero(GwWire.T_SOC_PARTY_INFO, h))
	if int(p["t"]) == GwWire.R_SOCIAL and int(p.get("k", -1)) == 0:
		party = p["party"]
	var g: Dictionary = await link.call_req(GwWire.soc_hero(GwWire.T_SOC_GUILD_INFO, h))
	if int(g["t"]) == GwWire.R_SOCIAL and int(g.get("k", -1)) == 1:
		guild = g["guild"]
	var l: Dictionary = await link.call_req(GwWire.soc_hero(GwWire.T_SOC_LISTS, h))
	if int(l["t"]) == GwWire.R_SOCIAL and int(l.get("k", -1)) == 4:
		friends = l["friends"]
		ignores = l["ignores"]
		invites = invites.filter(func(i: Dictionary) -> bool: return String(i["kind"]) != "friend")
		for q in l["pending"]:
			invites.append({"kind": "friend", "id": int(q["account"]), "name": String(q["name"]), "what": "FRIEND REQUEST"})
	social_changed.emit()


func _add_invite(kind: String, id: int, name: String, what: String) -> void:
	invites = invites.filter(func(i: Dictionary) -> bool: return not (String(i["kind"]) == kind and int(i["id"]) == id))
	invites.append({"kind": kind, "id": id, "name": name, "what": what})


func remove_invite(kind: String, id: int) -> void:
	invites = invites.filter(func(i: Dictionary) -> bool: return not (String(i["kind"]) == kind and int(i["id"]) == id))
	social_changed.emit()


func _on_social(m: Dictionary) -> void:
	match int(m.get("k", -1)):
		0:
			chat_lines.append({"chan": int(m["chan"]), "from": String(m["from"]), "to": String(m["to"]), "text": String(m["text"])})
			if chat_lines.size() > CHAT_KEEP:
				chat_lines.pop_front()
		1:
			_add_invite("party", int(m["inviter"]), String(m["name"]), "INVITES YOU TO A PARTY")
		2:
			party = m["party"]
		3:
			field_call = int(m["field"])
			var t: UiScreen = top()
			if t != null:
				t.say("YOUR PARTY GOES TO " + GameNames.FIELDS[clampi(field_call, 0, GameNames.FIELDS.size() - 1)])
		4:
			_add_invite("guild", int(m["guild"]), String(m["from"]), "INVITES YOU TO " + String(m["guild_name"]))
		5:
			refresh_social()
			return
		6:
			_add_invite("friend", int(m["from"]), String(m["name"]), "FRIEND REQUEST")
		7:
			for f in friends:
				if int(f["account"]) == int(m["account"]):
					f["online"] = bool(m["online"])
					f["place"] = int(m["place"])
			if not friends.any(func(f: Dictionary) -> bool: return int(f["account"]) == int(m["account"])):
				friends.append({"account": int(m["account"]), "name": String(m["name"]), "online": bool(m["online"]), "place": int(m["place"])})
		8:
			var t2: UiScreen = top()
			if t2 != null:
				t2.say(String(m["text"]).to_upper(), true)
	social_changed.emit()


## A social request: errors are shown, then what she sees of the social state is read again.
func social(req: Array, ok_text: String = "") -> Dictionary:
	var r: Dictionary = await act(req, ok_text)
	await refresh_social()
	return r


func _on_lost(_why: String) -> void:
	if in_field:
		_close_field()
	if base_name != "title" and base_name != "login":
		show_base(TitleScreen.new(), "title")
		(base as UiScreen).say("THE GATEWAY WENT AWAY", true)


# ---- the field

## Asks for a ticket for a field and hands over to the field client. Returns "" or the problem.
func go_field(field: int) -> String:
	var r: Dictionary = await link.call_req(GwWire.field_ticket(hero_id(), field))
	if int(r["t"]) != GwWire.R_TICKET:
		return error_text(r)
	close_panels()
	town = {}
	var host: String = String(r["host"])
	if host.is_empty():
		host = gateway_host
	_open_field(host, int(r["port"]), int(r["ticket"]), r["key"] as PackedByteArray, field)
	return ""


func _open_field(host: String, port: int, ticket: int, key: PackedByteArray, field: int) -> void:
	layer.visible = false
	if base != null:
		base.queue_free()
		base = null
	use_field_canvas()
	var c := RealmClient.new()
	c.embedded = true
	c.ticket_host = host
	c.ticket_port = port
	c.ticket = ticket
	c.ticket_key = key
	c.escaped.connect(_field_escape)
	field_client = c
	in_field = true
	add_child(c)
	field_started.emit(field)


func _field_escape() -> void:
	if _now - _esc_at < ESC_LEAVE_S:
		leave_field_now()
		return
	_esc_at = _now
	if field_client != null and field_client.has_method("warn"):
		field_client.warn("ESC AGAIN TO LEAVE: HALF THE HAUL IS LOST. WALK OUT OF THE GATE TO KEEP IT ALL")


## Disconnects from the field: the host flushes the outing (half the coin lost) and the gateway pushes the result.
func leave_field_now() -> void:
	if field_client != null:
		field_client.link.close()


func _close_field() -> void:
	if field_client != null:
		field_client.link.close()
		field_client.queue_free()
		field_client = null
	in_field = false
	use_shell_canvas()
	layer.visible = true


func _on_outing(msg: Dictionary) -> void:
	# 255: she is still there; the host banked her XP so far (every 10 s). Only another value ends the outing.
	if int(msg.get("left", 255)) == 255:
		return
	last_outing = msg
	if not in_field:
		return
	_close_field()
	field_ended.emit(msg)
	_back_from_field()


func _back_from_field() -> void:
	await refresh_heroes()
	var err: String = await enter_town()
	if not err.is_empty():
		show_base(HeroListScreen.new(), "hero_list")
		base.say(err, true)
		return
	var o: Dictionary = last_outing
	base.say("BACK FROM THE FIELD: %s COIN, %s XP%s" % [GameNames.commas(int(o["coin"])), GameNames.commas(int(o["xp"])), ", LEVEL UP!" if int(o["levels"]) > 0 else ""])
	var s := OutingPanel.new()
	s.outing = o
	open_panel(s)

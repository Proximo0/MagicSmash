extends SceneTree
## The shell against a real realm-gateway: title -> dev login -> new hero (the builder) -> town (walk, chat) -> bank
## deposit -> smith salvage (and upgrade, reroll, socket, fuse) -> merchants -> card reader -> trainer -> sheet and
## bag -> settings -> a field gate (ticket) -> the field client -> out of the gate -> back in town. Every click is a
## press of a registered button, as a mouse makes it. Needs a gateway started with --dev-login --dev-grant:
##   godot --path realm/client -s res://tests/shell_test.gd -- --gateway=127.0.0.1:PORT [--shots=DIR]
## With a display (xvfb-run is enough) every screen is saved as a PNG in DIR. Prints one SHELL_TEST line.

var _problems: Array[String] = []
var _checks: int = 0
var _shots_dir: String = ""
var _shots: int = 0
var _done: bool = false
var _shell: Shell = null
var _gateway: String = "127.0.0.1:7700"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] == "gateway" and kv.size() > 1:
			_gateway = kv[1]
		elif kv[0] == "shots" and kv.size() > 1:
			_shots_dir = kv[1]
	ShellSettings.persist = false
	_run()


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_problems.append(what)
		print("  FAILED: ", what)


## False (and the run ends with a FAILED line naming why) when the outing ended by itself: `last_outing.left` is
## 0 gate, 1 waystone, 2 disconnect (the host's 5 s silence timeout), 3 kicked, 4 shutdown, 5 vault, 6 host lost,
## 7 ticket unused; an empty last_outing with the shell back means the gateway link was lost.
## `client` is untyped: a freed node passed to a typed Node argument is a script error that hangs the test (24 Nov, a busy station).
func _field_alive(client: Variant, when: String) -> bool:
	if is_instance_valid(client) and _shell.in_field and _shell.field_client == client:
		return true
	_check(false, "the outing ended by itself %s: last_outing=%s in_field=%s base=%s" % [when, str(_shell.last_outing), str(_shell.in_field), _shell.base_name])
	_finish()
	return false


## A script error inside _run would leave the test hanging until check_client's 480 s timeout: end it sooner.
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > 470000 and not _done:
		_check(false, "the shell test ran past 470 s (stuck after an error?)")
		_finish()
	return false


func _finish() -> void:
	if _done:
		return
	_done = true
	var ok: bool = _problems.is_empty()
	print("SHELL_TEST %s checks=%d shots=%d%s" % ["ok" if ok else "FAILED", _checks, _shots, "" if ok else " problems=\"%s\"" % "; ".join(_problems)])
	quit(0 if ok else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## 30 s: the gateway answers in milliseconds on an idle PC, but a busy station (ubuntu: three lanes and the playtest
## server on four cores) has taken more than 10 s for a bank deposit, a guild founding, a house rent (24-25 Nov).
## Moves the real mouse (window coordinates, as the OS sends them) over a button of the top screen: true when the
## screen's own input saw it there.
func _mouse_reaches(id: String) -> bool:
	var t: UiScreen = _shell.top()
	for h in t._hits:
		if h["id"] == id:
			var p: Vector2 = root.get_final_transform() * (t.get_global_transform_with_canvas() * (h["rect"] as Rect2).get_center())
			var m := InputEventMouseMotion.new()
			m.position = p
			m.global_position = p
			Input.parse_input_event(m)
			await _frames(3)
			return t.hover_id == id
	return false


func _until(cond: Callable, secs: float = 30.0) -> bool:
	var t0: int = Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > secs * 1000.0:
			return false
		await process_frame
	return true


func _shot(name: String) -> void:
	if _shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(2)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_shots_dir, name])
	_shots += 1


## Presses a button of the top screen by id (waits a few frames for it to be drawn first). `sh` is the shell whose
## screen is pressed (the second player's, for the trade and the post), the main one by default.
func _press(id: String, sh: Shell = null) -> bool:
	var sc: Shell = sh if sh != null else _shell
	# One frame first: a button's enabled state is as of the last draw.
	await process_frame
	for i in 200:
		var t: UiScreen = sc.top()
		if t != null and t.get("busy") == true:
			await process_frame
			continue
		if t != null and t.has_hit(id):
			return t.press(id)
		await process_frame
	var top: UiScreen = sc.top()
	_check(false, "button %s is on the screen %s (top: %s, busy %s, has: %s)" % [id, sc.base_name, top.get_script().get_global_name() if top != null else "none", str(top.get("busy")) if top != null else "-", ",".join(top.hit_ids()) if top != null else ""])
	return false


func _type(board: OuijaBoard, word: String) -> void:
	for c in word:
		await _press("ouija:" + c)
		await process_frame


func _unit() -> void:
	# The social wire (job T1): a talk request is tag 0x40 with hero, channel, name and text; a notice push reads.
	var talk: Array = GwWire.soc_talk(5, GwWire.CHAN_TOWN, "", "hi")
	_check(int(talk[0]) == 0x40 and (talk[1] as PackedByteArray).size() == 8 + 1 + 2 + 0 + 2 + 2, "a talk request is built as the gateway reads it")
	var note: Dictionary = GwWire.decode(GwWire.P_SOCIAL, PackedByteArray([8, 1, 0, 120]))
	_check(int(note["k"]) == 8 and String(note["text"]) == "x", "a notice push is read")
	_check(int(GwWire.decode(GwWire.P_SOCIAL, PackedByteArray([8, 1, 0, 120, 9]))["t"]) == GwWire.R_ERR, "a push with a trailing byte is refused")
	# The wire: a login frame is len, type, tag, then a string.
	var req: Array = GwWire.login_dev("ann")
	var f: PackedByteArray = GwWire.frame(int(req[0]), 7, req[1])
	_check(f.size() == 4 + 5 + 2 + 3 and f.decode_u32(0) == 10 and f[4] == GwWire.T_LOGIN_DEV and f.decode_u32(5) == 7 and f.decode_u16(9) == 3, "a login frame is len, type, tag, string")
	var ok: Dictionary = GwWire.decode(GwWire.R_OK, PackedByteArray())
	_check(int(ok["t"]) == GwWire.R_OK, "an OK reply reads")
	_check(int(GwWire.decode(0x77, PackedByteArray())["t"]) == GwWire.R_ERR, "an unknown reply is refused")
	var b := StreamPeerBuffer.new()
	b.put_u16(3)
	b.put_data("abc".to_utf8_buffer())
	b.put_u16(1)
	_check(int(GwWire.decode(GwWire.P_TOWN_DEPART, PackedByteArray([1, 0, 9]))["t"]) == GwWire.R_ERR, "a trailing byte is refused")
	_check(GwWire.decode(GwWire.P_TOWN_DEPART, PackedByteArray([5, 0]))["id"] == 5, "a depart push reads")
	# The homes' wire (job H1): a Where reply reads, and the cell and plot arithmetic matches the gateway's.
	var hb := StreamPeerBuffer.new()
	hb.big_endian = false
	hb.put_u8(HomeWire.K_WHERE)
	hb.put_u8(HomeMap.HOUSE)
	hb.put_u32(9)
	var hd: Dictionary = GwWire.decode(HomeWire.R_HOME, hb.data_array)
	_check(int(hd["k"]) == HomeWire.K_WHERE and int(hd["kind"]) == HomeMap.HOUSE and int(hd["arg"]) == 9, "a homes reply decodes")
	_check(HomeWire.go(7, HomeMap.STREET, 3)[0] == HomeWire.T_HOME and (HomeWire.go(7, HomeMap.STREET, 3)[1] as PackedByteArray).size() == 1 + 8 + 1 + 4, "a Go request is sub, hero, kind, arg")
	_check(HomeMap.cell_of(1, 2, 3) == 132 and HomeMap.street_of(HomeMap.plot_id(2, 5)) == 2 and HomeMap.cell_px(0) == Vector2(1472, 1472), "cells and plots count as the gateway does")
	_check(HomeMap.FURNITURE.size() == 24 and GameNames.base_name(9000) == "CHAIR" and GameNames.base_name(9107).begins_with("PLAQUE"), "furniture and plaques have names")

	# Names and prices.
	_check(GameNames.base_name(0) == "PILGRIM'S DIRK" and GameNames.base_name(521) == "BOG RING" and GameNames.base_name(999) == "BASE 999", "a base has a name")
	_check(GameNames.stack_name(2001) == "RUNE OF MIGHT I" and GameNames.stack_name(1000) == "EMBERS" and GameNames.stack_name(1) == "COIN", "stack names")
	_check(GameNames.commas(1234567) == "1,234,567" and GameNames.commas(12) == "12", "thousands are grouped")
	var it := {"level": 30, "rarity": 0, "plus": 0}
	_check(GameNames.salvage_embers(it) == 4 and GameNames.upgrade_cost(it) == [12, 120] and GameNames.reroll_cost({"level": 30, "rarity": 4, "plus": 0})[1] == 4500, "prices match economy.md's table")
	_check(GameNames.class_skills(1, GameNames.NO_JOB, 25).size() == 3 and GameNames.skill_rank(30, 10) == 3, "skills and ranks")
	_check(GameNames.card_name(0) == "STRENGTH" and GameNames.card_name(29) == "KNIGHT OF WANDS", "card names are the core's")
	# The ouija board.
	var o := OuijaBoard.new()
	o.upper = true
	o.max_len = 5
	for c in "ab1'-xyz":
		o.type_char(c)
	_check(o.text == "AB1'-", "the board types capitals up to its length: " + o.text)
	o.erase()
	_check(o.text == "AB1'", "NO erases")
	# Settings: a key given to a second action is swapped, never shared.
	ShellSettings.load_file()
	var a1: int = ShellSettings.key("skill1")
	var a2: int = ShellSettings.key("skill2")
	ShellSettings.rebind("skill1", a2)
	_check(ShellSettings.key("skill1") == a2 and ShellSettings.key("skill2") == a1, "rebinding swaps")
	ShellSettings.reset_keys()
	_check(ShellSettings.key("skill1") == a1, "keys reset")


func _run() -> void:
	_unit()
	_shell = Shell.new()
	_shell.set_gateway(_gateway)
	root.add_child(_shell)
	await _frames(2)
	_shell.show_base(TitleScreen.new(), "title")
	await _frames(3)
	await _shot("01_title")
	_check(_shell.base_name == "title", "starts at the title")
	# A real mouse, through the window: every title button lights under the pointer (25 Nov: the screens were
	# 480 x 270 Controls drawing 960 x 540, so only the top-left quarter took clicks).
	for id in ["enter", "settings", "quit"]:
		_check(await _mouse_reaches(id), "the mouse reaches the title's '%s' button" % id)
	# The keyboard walks the same menu: Down picks the first button, Down again the one below, Enter presses it,
	# Esc goes back.
	_shell.top().hover_id = ""
	_shell._unhandled_input(_key(KEY_DOWN))
	_check(_shell.top().hover_id == "enter", "Down picks the title's first button (%s)" % _shell.top().hover_id)
	_shell._unhandled_input(_key(KEY_DOWN))
	_check(_shell.top().hover_id in ["settings", "quit"], "Down moves to a button below (%s)" % _shell.top().hover_id)
	_shell._unhandled_input(_key(KEY_LEFT))
	_check(_shell.top().hover_id == "settings", "Left moves to settings (%s)" % _shell.top().hover_id)
	_shell._unhandled_input(_key(KEY_ENTER))
	await _frames(2)
	_check(_shell.panel_of("SettingsPanel") != null, "Enter presses the picked button (settings open)")
	_shell._unhandled_input(_key(KEY_ESCAPE))
	await _frames(2)
	_check(_shell.panel_of("SettingsPanel") == null, "Esc goes back (settings close)")
	await _press("settings")
	await _frames(2)
	await _shot("02_settings")
	_check(_shell.panel_of("SettingsPanel") != null, "settings open over the title")
	await _press("key:skill1")
	_shell.top().on_key(_key(KEY_Q))
	_check(ShellSettings.key("skill1") == KEY_Q, "a key is rebound from the screen")
	ShellSettings.reset_keys()
	_check(await _mouse_reaches("close"), "the mouse reaches a panel's X (it is not under the panel's swallow)")
	await _press("close")
	await _frames(2)
	_check(_shell.panel_of("SettingsPanel") == null, "settings close")

	# Login: spell a name on the board.
	await _press("enter")
	await _frames(3)
	_check(_shell.base_name == "login", "ENTER goes to the login")
	var login: LoginScreen = _shell.base as LoginScreen
	login.board.text = ""
	await _type(login.board, "SHELLTEST")
	await _shot("03_login")
	_check(login.board.text == "SHELLTEST", "the board spelled the name")
	await _press("ouija:yes")
	_check(await _until(func() -> bool: return _shell.base_name == "hero_builder"), "a new account's login opens the builder")
	await _frames(3)
	_check(_shell.account > 0 and _shell.heroes.is_empty(), "a new account has no heroes")
	await _shot("04_heroes_empty")

	# The builder: a themed name and a knight are already chosen; ESC goes back to the empty hero list, whose empty
	# card opens it again.
	var builder: HeroBuilderScreen = _shell.base as HeroBuilderScreen
	_check(builder.board.text.length() >= 3 and builder.cls == 1 and builder.race == 0, "the builder starts with a name and a class chosen")
	builder.on_key(_key(KEY_ESCAPE))
	await _frames(3)
	_check(_shell.base_name == "hero_list", "ESC leaves the builder for the hero list")
	await _press("new")
	await _frames(3)
	_check(_shell.base_name == "hero_builder", "an empty card opens the builder")
	builder = _shell.base as HeroBuilderScreen
	await _press("race:1")
	await _press("class:1")
	await _press("pal:1")
	await _press("mark:1")
	_check(builder.race == 1 and builder.cls == 1 and builder.palette == 1 and builder.mark == 1, "race, class and look are chosen")
	builder.board.text = ""
	await _press("create")
	_check(_shell.heroes.is_empty(), "no hero without a name")
	await _type(builder.board, "MIRA")
	await _shot("05_builder")
	await _press("create")
	_check(await _until(func() -> bool: return _shell.base_name == "town" and _shell.heroes.size() == 1), "the hero is made and walks straight into town")
	await _frames(3)
	await _press("leave")
	_check(await _until(func() -> bool: return _shell.base_name == "hero_list"), "HEROES brings the hero list up")
	await _frames(3)
	_check(String(_shell.hero.get("name", "")) == "MIRA" and int(_shell.hero["race"]) == 1 and int(_shell.hero["class"]) == 1, "she is an elf knight called MIRA")
	_check(GameNames.look_palette(int(_shell.hero["look"])) == 1 and GameNames.look_mark(int(_shell.hero["look"])) == 1, "her look is kept")
	await _shot("06_heroes")

	# Into the town.
	await _press("enter")
	_check(await _until(func() -> bool: return _shell.base_name == "town"), "ENTER TOWN walks her in")
	await _frames(3)
	var town: TownScreen = _shell.base as TownScreen
	_check(town.me >= 0 and town.members.has(town.me), "she is a member of the room")
	_check(_shell.coin() == 6500 and _shell.items_at(GameNames.PLACE_BAG).size() == 3, "the dev grant gave coin and three items")
	_check(await _until(func() -> bool: return town.snapshots >= 3), "snapshots arrive")
	var p0: Vector2 = town.shown(town.me)
	_shell.link.send_only(GwWire.town_input(1))
	await _until(func() -> bool: return town.shown(town.me).x > p0.x + 20.0, 5.0)
	_shell.link.send_only(GwWire.town_input(0))
	_check(town.shown(town.me).x > p0.x + 20.0, "walking east moves her on the snapshots: %s -> %s" % [p0, town.shown(town.me)])
	await town.send_chat("hello town")
	_check(await _until(func() -> bool: return town.chat_log.size() > 0), "her chat line comes back from the room")
	_check(town.chat_log.size() > 0 and String(town.chat_log[0]["text"]) == "hello town", "the chat line is what she said")
	# Living together (job T1): the chat, party and guild panels over the town. She talks on the town channel, founds a
	# guild, posts to its board and sees an empty party.
	await _press("social")
	_check(_shell.panel_of("ChatPanel") != null, "CHAT opens over the town")
	var chat: ChatPanel = _shell.panel_of("ChatPanel") as ChatPanel
	chat.send("/t hello realm")
	_check(await _until(func() -> bool: return _shell.chat_lines.size() > 0 and String(_shell.chat_lines[0]["text"]) == "hello realm"), "her line comes back on the town channel")
	chat.send("/w NOBODYHERE hi")
	_check(await _until(func() -> bool: return _shell.top() != null and _shell.top().toast_until > _shell.top().time and _shell.top().toast_bad), "a whisper to no one is refused and shown")
	await _shot("07a_chat")
	await _press("close")
	await _press("party")
	await _frames(3)
	_check(_shell.panel_of("PartyPanel") != null and _shell.party.is_empty() and _shell.top().has_hit("invite"), "the party panel opens, empty, with an invite box")
	await _shot("07b_party")
	await _press("close")
	await _press("guild")
	var gp: GuildPanel = _shell.panel_of("GuildPanel") as GuildPanel
	_check(gp != null and _shell.guild.is_empty(), "the guild panel opens with no guild")
	gp.text = "PALE COURT"
	await _press("create")
	# 30 s: on a busy station (ubuntu 25 Nov, three lanes) the gateway took longer than 10 s to answer the create.
	_check(await _until(func() -> bool: return not _shell.guild.is_empty(), 30.0), "she founds a guild")
	_check(String(_shell.guild.get("name", "")) == "PALE COURT" and int(_shell.guild["my_rank"]) == 0, "she is its leader")
	gp.text = "who has a lantern"
	await _press("send")
	_check(await _until(func() -> bool: return not _shell.guild.is_empty() and _shell.guild["board"].size() == 1), "her post is on the board")
	await _shot("07c_guild")
	await _press("close")
	_shell.reset_social()
	_check(_shell.guild.is_empty() and _shell.chat_lines.is_empty(), "leaving clears the social state")
	await _shell.refresh_social()
	_check(not _shell.guild.is_empty(), "and the gateway still has her guild")
	# Stand her at the bank: the room is the server's, so the stations are about where she is; walk west-north-west.
	await _shot("07_town")
	for spot in [["plaza", TownMap.CENTRE + Vector2(0, 60)], ["bank", TownMap.station("bank")["at"] + Vector2(0, 30)], ["trainer", TownMap.station("trainer")["at"] + Vector2(0, 30)], ["smith", TownMap.station("smith")["at"] + Vector2(0, 40)], ["gates", TownMap.station("gate")["at"] + Vector2(0, -30)]]:
		town.look_at = spot[1]
		await _frames(3)
		await _shot("07_town_" + String(spot[0]))
	town.look_at = Vector2(-1, -1)

	# Bank: deposit coin and an item.
	await town.open_station("bank")
	await _frames(3)
	_check(_shell.panel_of("BankPanel") != null, "the bank panel opens")
	await _press("bstk:1")
	await _press("qty:10")
	await _press("move")
	_check(await _until(func() -> bool: return _shell.stack_count(GameNames.PLACE_BANK, 1) == 10), "10 coin are in the bank")
	_check(_shell.coin() == 6490, "and 6490 are in the bag")
	var bank: BankPanel = _shell.panel_of("BankPanel") as BankPanel
	var common: Dictionary = {}
	for it in _shell.items_at(GameNames.PLACE_BAG):
		if int(it["rarity"]) == 0:
			common = it
	await _press("bagit:%d" % int(common["id"]))
	await _press("move")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BANK).size() == 1), "an item is in the bank: " + _shell.top().toast_text)
	await _frames(2)
	await _shot("08_bank")
	await _press("bankit:%d" % int(_shell.items_at(GameNames.PLACE_BANK)[0]["id"]))
	await _press("move")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BANK).is_empty() and _shell.items_at(GameNames.PLACE_BAG).size() == 3), "and she can take it out again: " + _shell.top().toast_text)
	await _bank_tabs(bank, common)
	await _press("close")
	await _frames(2)

	# Homes and the shared places (job H1): the places list takes her to the first street, she rents the last plot,
	# knocks, crafts a chair from the dev kit's linen and places it on the grid; then back to the plaza.
	var coin_h: int = _shell.coin()
	await _press("places")
	_check(_shell.panel_of("PlacesPanel") != null, "PLACES opens over the town")
	await _frames(3)
	await _shot("23_places")
	await _press("go:%d:1" % HomeMap.STREET)
	_check(await _until(func() -> bool: return _shell.place == [HomeMap.STREET, 1] and _shell.base is TownScreen), "she walks to the first street")
	# The street's members reply comes from the server: on a busy box it can land a few frames after the walk.
	_check(await _until(func() -> bool: return _shell.town.has("members") and (_shell.base as TownScreen).stations.size() == 2 + HomeMap.PLOTS_PER_STREET), "the street's doors are stations")
	await _shot("24_street")
	await _press("street")
	var street: StreetPanel = _shell.panel_of("StreetPanel") as StreetPanel
	_check(street != null and await _until(func() -> bool: return street.plots.size() == 24), "the street map shows 24 plots")
	await _press("plot:23")
	await _frames(2)
	await _shot("25_street_map")
	await _press("rent:1")
	_check(await _until(func() -> bool: return _shell.coin() == coin_h - 280), "a week's rent of the back plot is 280 coin from her bag")
	_check(await _until(func() -> bool: return street.mine == HomeMap.plot_id(1, 23)), "the house is hers on the street board")
	await _press("visit")
	_check(await _until(func() -> bool: return _shell.place == [HomeMap.HOUSE, 23] and bool(_shell.house.get("mine", false))), "she walks into her house")
	await _frames(3)
	await _press("house")
	var housep: HousePanel = _shell.panel_of("HousePanel") as HousePanel
	_check(housep != null and await _until(func() -> bool: return housep.recipes.size() == 32), "the house screen has the carpenter's 32 pieces")
	await _press("craft:0")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BAG).any(func(i: Dictionary) -> bool: return int(i["base"]) == HomeMap.FURNITURE_BASE)), "the carpenter made a chair")
	var chair: int = 0
	for it in _shell.items_at(GameNames.PLACE_BAG):
		if int(it["base"]) == HomeMap.FURNITURE_BASE:
			chair = int(it["id"])
	_check(GameNames.item_name(_shell.item_by_id(chair)) == "CHAIR", "it is named a chair")
	await _press("bag:%d" % chair)
	await _press("cell:0:4:4")
	_check(await _until(func() -> bool: return _shell.house.get("items", []).size() == 1), "she placed the chair on the grid")
	var placed: Dictionary = _shell.house["items"][0]
	_check(int(placed["id"]) == chair and int(placed["slot"]) == HomeMap.cell_of(0, 4, 4) and int(placed["place"]) == 7, "the same item is now in the house, at cell 44")
	_check(_shell.item_by_id(chair).is_empty() or int(_shell.item_by_id(chair)["place"]) != GameNames.PLACE_BAG, "and it is no longer in her bag")
	await _frames(3)
	await _shot("26_house")
	await _press("pickup")
	await _press("cell:0:4:4")
	await _press("pickup")
	_check(await _until(func() -> bool: return _shell.house.get("items", []).is_empty() and _shell.items_at(GameNames.PLACE_BAG).any(func(i: Dictionary) -> bool: return int(i["id"]) == chair)), "picking it up puts the same item back in her bag")
	await _press("bag:%d" % chair)
	await _press("cell:0:2:2")
	_check(await _until(func() -> bool: return _shell.house.get("items", []).size() == 1 and _shell.items_at(GameNames.PLACE_BAG).size() == 3), "the chair stays in the house, her bag is as it was")
	await _press("close")
	await _press("places")
	await _press("go:%d:0" % HomeMap.YARD)
	_check(await _until(func() -> bool: return _shell.place == [HomeMap.YARD, 0]), "she walks to the training yard")
	await _frames(3)
	await (_shell.base as TownScreen).open_station("dummy")
	var yard: YardPanel = _shell.panel_of("YardPanel") as YardPanel
	_check(yard != null, "the dummy opens")
	await _press("strike")
	_check(await _until(func() -> bool: return int(yard.last.get("damage", 0)) > 0 and int(yard.last.get("dps", 0)) > 0), "a blow on the dummy reports damage and a rate")
	await _frames(3)
	await _shot("27_yard")
	await _press("close")
	await _press("places")
	await _press("go:%d:0" % HomeMap.PLAZA)
	_check(await _until(func() -> bool: return _shell.place == [HomeMap.PLAZA, 0] and _shell.base is TownScreen), "and back to the plaza")
	town = _shell.base as TownScreen
	await _frames(3)
	await _economy()

	# Smith.
	await town.open_station("smith")
	await _frames(3)
	var embers0: int = _shell.stack_count(GameNames.PLACE_BAG, GameNames.KIND_EMBERS)
	var smith: SmithPanel = _shell.panel_of("SmithPanel") as SmithPanel
	_check(smith != null, "the smith opens")
	var uncommon: Dictionary = {}
	var rare: Dictionary = {}
	for it in _shell.items_at(GameNames.PLACE_BAG):
		if int(it["rarity"]) == 1:
			uncommon = it
		elif int(it["rarity"]) == 2:
			rare = it
	await _press("it:%d" % int(uncommon["id"]))
	await _shot("09_smith")
	var expect: int = GameNames.salvage_embers(uncommon)
	await _press("do")
	_check(await _until(func() -> bool: return _shell.stack_count(GameNames.PLACE_BAG, GameNames.KIND_EMBERS) == embers0 + expect), "salvage gave %d embers" % expect)
	_check(_shell.items_at(GameNames.PLACE_BAG).size() == 2, "the salvaged item is gone")
	await _press("tab:1")
	await _press("it:%d" % int(rare["id"]))
	await _press("do")
	_check(await _until(func() -> bool: return smith.last_result.ends_with("NOW +1")), "an upgrade made the rare +1: " + smith.last_result)
	_check(int(_shell.item_by_id(smith.sel_item).get("plus", 0)) == 1, "the item reads +1 afterwards")
	await _press("tab:3")
	await _frames(2)
	await _press("rune:%d" % GameNames.rune_kind(0, 1))
	await _press("fill:0")
	_check(await _until(func() -> bool: return int(_shell.item_by_id(smith.sel_item)["socketed"][0]) == GameNames.rune_kind(0, 1)), "a rune is set in the socket: " + _shell.top().toast_text)
	await _shot("10_smith_socket")
	await _press("tab:4")
	await _frames(2)
	await _shot("11_smith_fuse")
	await _press("fuse:0:1")
	_check(await _until(func() -> bool: return _shell.stack_count(GameNames.PLACE_BAG, GameNames.rune_kind(0, 2)) == 1), "three runes fused into one of grade II")
	await _press("tab:2")
	await _press("do")
	_check(await _until(func() -> bool: return smith.last_result.ends_with("NEW LINES")), "a reroll gives new lines")
	await _press("close")
	await _frames(2)

	# Merchants (the economy's merchant of her field: potions, embers and gear, selling, buying back, the belt).
	await town.open_station("merchants")
	var merch: MerchantPanel = _shell.panel_of("MerchantPanel") as MerchantPanel
	_check(await _until(func() -> bool: return merch.offers.size() == 13), "the merchant lists six potions, embers and six pieces of gear")
	await _frames(3)
	var coin0: int = _shell.coin()
	var draught: int = int(merch.offers[0]["price"])
	await _press("buy:0:5")
	_check(await _until(func() -> bool: return _shell.coin() == coin0 - 5 * draught and _shell.stack_count(GameNames.PLACE_BAG, 100) == 7), "five healing draughts bought for %d" % (5 * draught))
	_check(await _until(func() -> bool: return int(merch.offers[0]["left"]) == 15), "his stock of draughts for today is 5 less")
	var embers_m: int = _shell.stack_count(GameNames.PLACE_BAG, GameNames.KIND_EMBERS)
	await _press("buy:6:1")
	_check(await _until(func() -> bool: return _shell.stack_count(GameNames.PLACE_BAG, GameNames.KIND_EMBERS) == embers_m + 1), "an ember bought")
	await _shot("12_merchants")
	await _press("tab:1")
	var sellable: Dictionary = {}
	for it in _shell.items_at(GameNames.PLACE_BAG):
		if int(it["rarity"]) == 0:
			sellable = it
	await _press("it:%d" % int(sellable["id"]))
	await _shot("13_merchants_sell")
	var coin1: int = _shell.coin()
	await _press("sell")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BAG).size() == 1), "the common item is sold")
	_check(_shell.coin() == coin1 + MerchantPanel.pays_for(sellable), "for a quarter of its value (%d)" % (_shell.coin() - coin1))
	await _press("stk:%d" % GameNames.KIND_EMBERS)
	var coin2: int = _shell.coin()
	await _press("sellstk:1")
	_check(await _until(func() -> bool: return _shell.coin() == coin2 + MerchantPanel.EMBER_SELL and _shell.stack_count(GameNames.PLACE_BAG, GameNames.KIND_EMBERS) == embers_m), "an ember sold back by the piece")
	await _press("tab:2")
	_check(await _until(func() -> bool: return merch.buybacks.size() == 1), "what she sold can be bought back")
	await _frames(2)
	await _shot("13b_merchants_buyback")
	await _press("tab:3")
	await _press("slot:1")
	await _press("pot:100")
	_check(await _until(func() -> bool: return int(_shell.hero["belt"][1]) == 100), "the belt holds the draught in slot 2")
	await _shot("14_merchants_belt")
	await _press("close")
	await _frames(2)

	# Card reader.
	await town.open_station("reader")
	await _frames(3)
	var reader: ReaderPanel = _shell.panel_of("ReaderPanel") as ReaderPanel
	var before: int = reader.deck.size()
	_check(before == 12 and _shell.cards.size() == 12, "a new hero has the novice twelve in her deck: %d" % before)
	await _press("slot:0")
	await _press("card:5")
	await _press("card:5")
	_check(reader.deck.size() == before - 1 and not reader.deck.has(0) and reader.deck.has(5), "a card is taken out by its slot, another taken out and put back by its tile")
	await _shot("15_reader")
	await _press("save")
	_check(await _until(func() -> bool: return (_shell.hero["deck"] as Array).size() == before - 1), "the deck is saved: " + _shell.top().toast_text)
	await _press("close")
	await _frames(2)

	# Trainer, sheet, bag.
	await town.open_station("trainer")
	await _frames(3)
	_check(await _until(func() -> bool: return not _shell.trial.is_empty()), "the trainer reads THE CLASS TRIAL for the job's terms")
	await _frames(2)
	await _shot("16_trainer")
	_check(_shell.panel_of("TrainerPanel") != null, "the trainer opens")
	_check(int(_shell.hero.get("job", -1)) == GameNames.NO_JOB and int(_shell.hero.get("class", 0)) != 0, "a new hero has a class and no job, so the trainer shows the job's terms: job %d class %d" % [int(_shell.hero.get("job", -1)), int(_shell.hero.get("class", 0))])
	await _press("close")
	await _frames(2)
	# THE CLASS TRIAL's station: what it asks, where she stands, and ENTER waits for class level 10.
	await town.open_station("trial")
	var trial: TrialPanel = _shell.panel_of("TrialPanel") as TrialPanel
	_check(trial != null, "the class trial's station opens")
	_check(await _until(func() -> bool: return not _shell.trial.is_empty() and not trial.busy), "it reads the trial for her")
	_check(int(_shell.trial["level"]) == 10 and not bool(_shell.trial["passed"]), "the trial asks class level 10 and she has not passed it")
	_check(trial.level_label.text == "YOU ARE LEVEL 1: COME BACK AT LEVEL 10" and trial.enter_btn.disabled, "a level-1 hero is told to come back at 10: " + trial.level_label.text)
	_check(trial.job_label.text.contains("THE TRAINER ASKS") and trial.job_label.text.contains("COIN"), "the job's price is shown: " + trial.job_label.text)
	var refused: Dictionary = await _shell.act(WorldWire.vault_open(_shell.hero_id(), WorldWire.TRIAL_VAULT, 0))
	_check(Shell.error_text(refused).contains("FROM CLASS LEVEL 10"), "the gateway refuses her in words too: " + Shell.error_text(refused))
	await _frames(2)
	await _shot("16b_trial")
	await _press("close")
	await _frames(2)
	town.open_sheet()
	await _frames(3)
	await _shot("17_sheet")
	await _press("close")
	town.open_bag()
	await _frames(3)
	var bag: BagPanel = _shell.panel_of("BagPanel") as BagPanel
	var worn_item: Dictionary = _shell.items_at(GameNames.PLACE_BAG)[0]
	await bag.equip(int(worn_item["id"]))
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_WORN).size() == 1), "an item is worn")
	await _frames(2)
	await _shot("18_bag")
	await _press("close")
	await _frames(2)
	_shell.open_panel(SettingsPanel.new())
	await _frames(3)
	await _shot("19_settings_in_town")
	await _press("resume")
	await _frames(2)

	# The field gate.
	await town.open_station("gate")
	await _frames(3)
	await _shot("20_gates")
	await _press("field:0")
	_check(await _until(func() -> bool: return _shell.in_field and _shell.field_client != null), "a ticket hands her to the field client")
	var client: Node = _shell.field_client
	# The test runs with --shots for its own screenshots: the field must not read it as the bare client's scripted bot.
	_check(not bool(client.get("_bot")) and str(client.get("_shots_dir")).is_empty(), "the shell's field is played by her keys, not the scripted bot")
	var joined: bool = await _until(func() -> bool: return not is_instance_valid(client) or int(client.link.counters().get("ticks_applied", 0)) > 40, 20.0)
	_check(joined and is_instance_valid(client), "the field client joined with the ticket and ran 40 ticks")
	# Checked right after joining, before idling: the screens are hidden while the outing lasts.
	_check(not _shell.layer.visible or not _shell.in_field, "the shell's screens are hidden in the field")
	if not _field_alive(client, "after joining"):
		return
	await _frames(20)
	if not _field_alive(client, "while idling 20 frames"):
		return
	await _shot("21_field")
	# One Esc press reaches the shell twice (the field client's `escaped` and the shell's key handler): it warns, it
	# must not leave (25 Nov, the playbot: one Esc lost half the haul).
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(esc)
	await _frames(3)
	_check(_shell.in_field and _shell.field_client == client, "one Esc in the field warns and does not leave")
	_shell._esc_at = -100.0
	if not _field_alive(client, "during the field shot"):
		return
	_check(not _shell.layer.visible, "the shell's screens are hidden in the field")
	_check(int(client.link.counters().get("hash_checks_failed", 0)) == 0, "no hash check failed in the field")
	client.script_move = 3
	_check(await _until(func() -> bool: return not _shell.in_field, 60.0), "walking out of the gate ends the outing")
	_check(int(_shell.last_outing.get("left", 9)) == 0, "she left by the gate: %s" % str(_shell.last_outing))
	_check(await _until(func() -> bool: return _shell.base_name == "town" and _shell.panel_of("OutingPanel") != null, 15.0), "she is back in town with her outing shown")
	await _frames(3)
	await _shot("22_back_in_town")
	_check(_shell.layer.visible and _shell.hero_id() != 0, "the shell is back")
	await _press("close")
	await _frames(2)
	await _press("leave")
	_check(await _until(func() -> bool: return _shell.base_name == "hero_list"), "she can go back to the hero list")
	_finish()



# ---- the bank's tabs, the market, the post, the trade table and the world board (screens built from Controls)

## A bag item of a rarity (the dev kit gives one of each of the first three).
func _bag_of(sh: Shell, rarity: int) -> Dictionary:
	for it in sh.items_at(GameNames.PLACE_BAG):
		if int(it["rarity"]) == rarity:
			return it
	return {}


## True when a control inside `panel` holds the keyboard focus (so the screen can be worked without a mouse).
func _focused_in(panel: Control) -> bool:
	var f: Control = panel.get_viewport().gui_get_focus_owner()
	return f != null and panel.is_ancestor_of(f)


func _bank_tabs(bank: BankPanel, item: Dictionary) -> void:
	_check(_focused_in(bank), "the bank has keyboard focus on a control")
	# The gateway says how many tabs the account owns: one, the other seven locked, the second for 3,000 coin.
	_check(await _until(func() -> bool: return bank.tab_price > 0), "the bank reads the account's tabs")
	_check(bank.tabs_owned == 1 and bank.tabs_max == 8 and bank.tab_bar.tab_count == 8, "one tab owned of eight: %d of %d" % [bank.tabs_owned, bank.tabs_max])
	_check(bank.tab_bar.is_tab_disabled(1) and not bank.tab_bar.is_tab_disabled(0), "tab 2 is locked")
	_check(bank.buy_btn.text == "BUY TAB 2: 3,000 COIN", "the buy button names the price: " + bank.buy_btn.text)
	await _frames(2)
	await _shot("28a_bank_tab_locked")
	var coin0: int = _shell.coin()
	await _press("buy_tab")
	_check(await _until(func() -> bool: return bank.tabs_owned == 2), "tab 2 is bought: " + bank.toast_text)
	_check(await _until(func() -> bool: return _shell.coin() == coin0 - 3000), "for 3,000 coin from her bag (%d)" % _shell.coin())
	_check(not bank.tab_bar.is_tab_disabled(1) and bank.tab_bar.is_tab_disabled(2), "tab 2 opens, tab 3 stays locked")
	_check(bank.buy_btn.text == "BUY TAB 3: 12,000 COIN", "the next tab is dearer: " + bank.buy_btn.text)
	await _press("buy_tab")
	_check(await _until(func() -> bool: return bank.toast_text.contains("COSTS 12,000 COIN")), "a tab she cannot pay for is refused in words: " + bank.toast_text)
	_check(bank.tabs_owned == 2 and _shell.coin() == coin0 - 3000, "and nothing is bought")
	await _press("tab:1")
	_check(bank.tab == 1, "tab two is chosen")
	await _press("bagit:%d" % int(item["id"]))
	await _press("move")
	_check(await _until(func() -> bool: var b: Array[Dictionary] = _shell.items_at(GameNames.PLACE_BANK); return b.size() == 1 and int(b[0]["tab"]) == 1), "an item goes into tab 2: " + bank.toast_text)
	await _press("tab:0")
	_check(bank.bank_items.item_count == 0, "tab 1 does not list it")
	await _press("tab:1")
	_check(bank.bank_items.item_count == 1, "tab 2 lists it")
	await _frames(2)
	await _shot("28_bank_tabs")
	await _press("bankit:%d" % int(item["id"]))
	await _press("move")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BANK).is_empty() and _shell.items_at(GameNames.PLACE_BAG).size() == 3), "and she takes it out of tab 2 again")


## A second player in the same town (hidden: only the first shell draws).
func _mate() -> Shell:
	var m := Shell.new()
	m.set_gateway(_gateway)
	root.add_child(m)
	await _frames(2)
	m.layer.visible = false
	var err: String = await m.login("SHELLMATE")
	if err.is_empty():
		err = await m.create_hero("MATEHERO", 1, 1, 0)
	if err.is_empty():
		err = await m.enter_town()
	if not err.is_empty():
		print("  mate: ", err)
		return null
	await _frames(3)
	return m


func _economy() -> void:
	var town: TownScreen = _shell.base as TownScreen
	var mate: Shell = await _mate()
	_check(mate != null and mate.hero_id() != 0 and mate.base is TownScreen, "a second hero stands in the same town")
	if mate == null:
		return
	var mname: String = String(mate.hero["name"])
	var pname: String = String(_shell.hero["name"])
	var mtown: TownScreen = mate.base as TownScreen

	# The market: she lists the common item; the mate buys it, lists it again; she buys it back.
	await town.open_station("market")
	await _frames(3)
	var mk: MarketPanel = _shell.panel_of("MarketPanel") as MarketPanel
	_check(mk != null, "the market opens at its station")
	_check(_focused_in(mk), "the market has keyboard focus on a control")
	var common: Dictionary = _bag_of(_shell, 0)
	var cid: int = int(common["id"])
	await _press("tab:1")
	var coin_a: int = _shell.coin()
	await _press("sellit:%d" % cid)
	mk.price_box.value = 40
	await _frames(2)
	await _shot("29_market_sell")
	await _press("list")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BAG).size() == 2), "the listed item left her bag: " + mk.toast_text)
	var fee: int = coin_a - _shell.coin()
	_check(fee >= 1 and fee < 40 and mk.sell_note.text.contains("FEE"), "the house took a fee, and the screen says so (%d)" % fee)
	await _press("tab:2")
	_check(await _until(func() -> bool: return mk.mine.size() == 1 and mk.mine_tree.get_root().get_child_count() == 1), "MINE shows her one listing")
	await _frames(2)
	await _shot("30_market_mine")
	await _press("tab:0")
	_check(await _until(func() -> bool: return mk.listings.size() == 1 and bool(mk.listings[0]["mine"])), "BROWSE shows it marked as hers")
	await _press("row:%d" % int(mk.listings[0]["id"]))
	_check(mk.buy_btn.disabled, "she may not buy her own listing")

	await mtown.open_station("market")
	await _frames(3)
	var mm: MarketPanel = mate.panel_of("MarketPanel") as MarketPanel
	_check(mm != null and await _until(func() -> bool: return mm.listings.size() == 1), "the mate sees the listing")
	var mcoin: int = mate.coin()
	await _press("row:%d" % int(mm.listings[0]["id"]), mate)
	await _press("buy", mate)
	_check(await _until(func() -> bool: return mate.coin() == mcoin - 40 and mate.items_at(GameNames.PLACE_BAG).size() == 4), "the mate paid 40 and holds the item: " + mm.toast_text)
	_check(await _until(func() -> bool: return _shell.coin() == coin_a - fee + 37), "she is paid 37, the tax of 3 is the house's (%d)" % _shell.coin())
	_check(_shell.top().toast_text.begins_with("YOUR LISTING SOLD") or mk.toast_text.begins_with("YOUR LISTING SOLD"), "she is told it sold: " + mk.toast_text)
	await _press("tab:1", mate)
	await _press("sellit:%d" % cid, mate)
	mm.price_box.value = 30
	await _press("list", mate)
	_check(await _until(func() -> bool: return mate.items_at(GameNames.PLACE_BAG).size() == 3), "the mate lists it again")
	await _press("close", mate)
	await _press("search")
	_check(await _until(func() -> bool: return mk.listings.size() == 1 and String(mk.listings[0]["seller"]) == mname), "she finds the mate's listing")
	await _frames(2)
	await _shot("31_market_browse")
	var coin_b: int = _shell.coin()
	await _press("row:%d" % int(mk.listings[0]["id"]))
	await _press("buy")
	_check(await _until(func() -> bool: return _shell.coin() == coin_b - 30 and _shell.items_at(GameNames.PLACE_BAG).size() == 3), "she buys it back for 30")
	# A thing taken down goes to the shelf at the post.
	var unc: Dictionary = _bag_of(_shell, 1)
	await _press("tab:1")
	await _press("sellit:%d" % int(unc["id"]))
	mk.price_box.value = 25
	await _press("list")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BAG).size() == 2), "she lists the uncommon one")
	mk.mine.clear()
	await _press("tab:2")
	_check(await _until(func() -> bool: return mk.mine.size() == 1), "MINE shows it")
	await _press("mine:%d" % int(mk.mine[0]["id"]))
	await _press("cancel")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_MAIL).size() == 1), "taking it down sends it to her shelf at the post")
	# A price the server refuses is said in words.
	await _press("tab:1")
	await _press("sellit:%d" % int(_bag_of(_shell, 0)["id"]))
	mk.price_box.value = 90000000
	await _press("list")
	_check(await _until(func() -> bool: return mk.toast_text.contains("MORE THAN THE MARKET ALLOWS")), "a price over the cap is refused in words: " + mk.toast_text)
	await _press("close")

	# The post: she takes the shelf, writes, the mate reads, pays cash on delivery, refuses; she recalls one.
	await town.open_station("post")
	await _frames(3)
	var po: PostPanel = _shell.panel_of("PostPanel") as PostPanel
	_check(po != null and _focused_in(po), "the post opens with keyboard focus on a control")
	await _press("tab:3")
	await _frames(2)
	await _shot("32_post_shelf")
	await _press("shelfit:%d" % int(unc["id"]))
	await _press("shelf_take")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BAG).size() == 3 and _shell.items_at(GameNames.PLACE_MAIL).is_empty()), "she takes the taken-down thing back into her bag")
	await _press("tab:1")
	po.to_edit.text = mname
	po.text_edit.text = "Take the key. The crypt did not want me."
	var rare: Dictionary = _bag_of(_shell, 2)
	await _press("att:%d" % int(rare["id"]))
	await _frames(2)
	await _shot("33_post_write")
	await _press("send")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BAG).size() == 2 and po.write_note.text.begins_with("SENT")), "the letter goes with its rare item: " + po.toast_text)
	await mtown.open_station("post")
	await _frames(3)
	var mp: PostPanel = mate.panel_of("PostPanel") as PostPanel
	_check(mp != null and await _until(func() -> bool: return mp.inbox.size() == 1), "the mate's inbox holds the letter")
	await _press("in:%d" % int(mp.inbox[0]["id"]), mate)
	_check(mp.in_text.text.contains(pname.to_upper()) and mp.in_text.text.contains("The crypt"), "the mate reads who it is from and what it says")
	await _press("take", mate)
	_check(await _until(func() -> bool: return mate.items_at(GameNames.PLACE_BAG).size() == 4 and mp.inbox.is_empty()), "the mate takes the item out of the letter: " + mp.toast_text)
	await _press("tab:1", mate)
	mp.to_edit.text = pname
	mp.text_edit.text = "Then buy it back."
	mp.cod_box.value = 10
	await _press("att:%d" % int(rare["id"]), mate)
	await _press("send", mate)
	_check(await _until(func() -> bool: return mate.items_at(GameNames.PLACE_BAG).size() == 3), "the mate sends it back asking 10 coin")
	await _press("close", mate)
	await _press("tab:0")
	_check(await _until(func() -> bool: return po.inbox.size() == 1), "her inbox holds the answer")
	await _press("in:%d" % int(po.inbox[0]["id"]))
	_check(po.in_text.text.contains("YOU PAY 10 COIN") and po.take_btn.text.contains("PAY 10"), "it says what opening it costs")
	await _frames(2)
	await _shot("34_post_inbox")
	var coin_c: int = _shell.coin()
	await _press("take")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BAG).size() == 3 and _shell.coin() == coin_c - 10), "she pays 10 and has the item back")
	# A letter refused comes back; a letter recalled too.
	await _press("tab:1")
	po.to_edit.text = mname
	po.text_edit.text = "A gift."
	await _press("att:%d" % int(_bag_of(_shell, 0)["id"]))
	await _press("send")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BAG).size() == 2), "she posts a gift")
	await mtown.open_station("post")
	await _frames(3)
	mp = mate.panel_of("PostPanel") as PostPanel
	_check(await _until(func() -> bool: return mp.inbox.size() == 1), "the gift reaches the mate")
	await _press("in:%d" % int(mp.inbox[0]["id"]), mate)
	await _press("refuse", mate)
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_MAIL).size() == 1), "the mate refuses it and it comes back to her shelf")
	await _press("close", mate)
	await _press("tab:3")
	await _press("shelfit:%d" % int(_shell.items_at(GameNames.PLACE_MAIL)[0]["id"]))
	await _press("shelf_take")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BAG).size() == 3), "she takes it from the shelf")
	await _press("tab:1")
	po.to_edit.text = mname
	po.text_edit.text = "A little coin."
	po.coin_box.value = 5
	await _press("send")
	_check(await _until(func() -> bool: return po.write_note.text.begins_with("SENT")), "a letter of coin goes")
	await _press("tab:2")
	_check(await _until(func() -> bool: return po.outbox.size() == 1), "SENT lists it")
	await _press("out:%d" % int(po.outbox[0]["id"]))
	await _press("recall")
	_check(await _until(func() -> bool: return _shell.stack_count(GameNames.PLACE_MAIL, GameNames.KIND_COIN) == 5), "she recalls it: the coin waits on her shelf")
	await _press("tab:3")
	await _press("shelfstk:%d" % GameNames.KIND_COIN)
	await _press("shelf_take")
	_check(await _until(func() -> bool: return _shell.stack_count(GameNames.PLACE_MAIL, GameNames.KIND_COIN) == 0), "and takes it")
	await _press("tab:1")
	po.to_edit.text = "NOBODYNAMEDTHIS"
	po.text_edit.text = "x"
	po.coin_box.value = 1
	await _press("send")
	_check(await _until(func() -> bool: return po.toast_text.contains("NO HERO NAMED")), "a letter to nobody is refused in words: " + po.toast_text)
	await _press("close")

	# The trade table: she invites the mate, who is shown the invitation and sits; each lays things down; both confirm.
	await town.open_station("trade")
	await _frames(3)
	var tp: TradePanel = _shell.panel_of("TradePanel") as TradePanel
	_check(tp != null and _focused_in(tp), "the trade table opens with keyboard focus on a control")
	tp.name_edit.text = mname
	await _press("invite")
	_check(await _until(func() -> bool: return _shell.trade.get("state", -1) == EconWire.TS_INVITED), "the invitation goes out: " + tp.toast_text)
	_check(await _until(func() -> bool: return mate.panel_of("TradePanel") != null and not mate.trade_invite.is_empty()), "the mate is shown the invitation at once")
	var mt: TradePanel = mate.panel_of("TradePanel") as TradePanel
	_check(mt.status.text.contains(pname.to_upper()), "it names who asks")
	await _press("accept", mate)
	_check(await _until(func() -> bool: return _shell.trade.get("state", -1) == EconWire.TS_OPEN and mate.trade.get("state", -1) == EconWire.TS_OPEN), "both sit at an open table")
	var gave: Dictionary = _bag_of(_shell, 0)
	var got: Dictionary = _bag_of(mate, 0)
	var coin_d: int = _shell.coin()
	var mcoin_d: int = mate.coin()
	await _press("bag:%d" % int(gave["id"]))
	tp.coin_box.value = 10
	await _press("offer")
	_check(await _until(func() -> bool: return (mate.trade.get("their_items", []) as Array).size() == 1), "her offer shows on the mate's side of the table")
	await _press("bag:%d" % int(got["id"]), mate)
	mt.coin_box.value = 25
	await _press("offer", mate)
	_check(await _until(func() -> bool: return (_shell.trade.get("their_items", []) as Array).size() == 1 and (_shell.trade.get("their_stacks", []) as Array).size() == 1), "and the mate's on hers")
	await _frames(2)
	await _shot("36_trade_table")
	# The server hears no confirm in the first 1.5 s after a change: say so in words. On a busy PC the press can land
	# after the 1.5 s (the panel is still busy refreshing her own offer), and then the confirm is rightly taken.
	await _press("confirm")
	_check(await _until(func() -> bool: return tp.toast_text.contains("A MOMENT AGO") or bool(_shell.trade.get("my_ok", false))), "a confirm too soon is refused in words: " + tp.toast_text)
	if not bool(_shell.trade.get("my_ok", false)):
		await create_timer(1.8).timeout
		await _press("confirm")
	_check(await _until(func() -> bool: return bool(_shell.trade.get("my_ok", false))), "she confirms the offers she sees")
	await _press("confirm", mate)
	_check(await _until(func() -> bool: return _shell.trade.get("state", -1) == EconWire.TS_DONE and mate.trade.get("state", -1) == EconWire.TS_DONE, 15.0), "the trade is done on both sides: " + mt.toast_text)
	_check(await _until(func() -> bool: return _shell.coin() == coin_d + 25 - 10 and mate.coin() == mcoin_d - 25 + 10), "the coin crossed over, 25 to her and 10 to him")
	_check(await _until(func() -> bool: return not _shell.item_by_id(int(got["id"])).is_empty() and _shell.item_by_id(int(gave["id"])).is_empty()), "she holds his item and not hers")
	_check(tp.status.text.begins_with("THE TRADE IS DONE"), "the table says it is done")
	await _press("close", mate)
	await _press("close")
	# A trade called off leaves everything where it was.
	await town.open_station("trade")
	await _frames(3)
	tp = _shell.panel_of("TradePanel") as TradePanel
	tp.name_edit.text = "NOBODYNAMEDTHIS"
	await _press("invite")
	_check(await _until(func() -> bool: return tp.toast_text.contains("NO HERO NAMED"), 30.0), "inviting no one is refused in words: " + tp.toast_text)
	await _press("close")

	# The world board.
	await town.open_station("board")
	await _frames(3)
	var bp: BoardPanel = _shell.panel_of("BoardPanel") as BoardPanel
	_check(bp != null and await _until(func() -> bool: return not bp.board.is_empty()), "the world board reads the realm's board")
	_check(bp.tree.get_root().get_child_count() == 6 and bp.world_label.text.begins_with("THE PALE RIDER COMES TO"), "six fields and the world boss's ride: " + bp.world_label.text)
	_check(_focused_in(bp), "the board has keyboard focus on a control")
	await _frames(2)
	await _shot("37_world_board")
	# Esc and the controller's B are the same action: it closes the board.
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	_check(await _until(func() -> bool: return _shell.panel_of("BoardPanel") == null, 3.0), "the cancel action closes the board")
	await _duels(mate, pname, mname)
	mate.link.close()
	mate.queue_free()
	await _frames(2)


## Duels in the training yard (pvp.md): the mate challenges her by name and she is asked at once over the town; she
## refuses and he is told. Then she challenges him from the heroes standing near her, he accepts, the duel begins for
## both (the town shows it), and his leaving the town forfeits it: both are told she won.
func _duels(mate: Shell, pname: String, mname: String) -> void:
	_check(_shell.top() is TownScreen and mate.top() is TownScreen, "both stand in the plaza with no screen open")
	mate.open_panel(DuelPanel.new())
	await _frames(2)
	var md: DuelPanel = mate.panel_of("DuelPanel") as DuelPanel
	md.name_edit.text = pname
	await _press("challenge", mate)
	_check(await _until(func() -> bool: return String(_shell.duel_offer.get("name", "")) == mname), "she is challenged: %s" % str(_shell.duel_offer))
	_check(await _until(func() -> bool: return _shell.panel_of("DuelPanel") != null), "the duel ring opens over her town with the challenge")
	var dp: DuelPanel = _shell.panel_of("DuelPanel") as DuelPanel
	_check(dp.offer_label.text == "%s CHALLENGES YOU TO A DUEL" % mname.to_upper() and not dp.accept_btn.disabled and not dp.refuse_btn.disabled, "it names him, with ACCEPT and REFUSE: " + dp.offer_label.text)
	await _frames(2)
	await _shot("38_duel_challenged")
	await _press("refuse")
	_check(await _until(func() -> bool: return md.toast_text.contains("WILL NOT DUEL YOU")), "he is told she refused: " + md.toast_text)
	_check(await _until(func() -> bool: return _shell.duel_offer.is_empty() and dp.accept_btn.disabled), "the challenge is answered")
	await _press("close", mate)
	# Her turn: from the heroes near her.
	_check(await _until(func() -> bool: return dp.has_hit("near:" + mname)), "he is in the list of heroes near her")
	await _press("near:" + mname)
	_check(await _until(func() -> bool: return String(mate.duel_offer.get("name", "")) == pname), "he is asked at once: " + str(mate.duel_offer))
	_check(await _until(func() -> bool: return mate.panel_of("DuelPanel") != null), "his duel ring opens by itself")
	await _press("accept", mate)
	_check(await _until(func() -> bool: return not _shell.duel.is_empty() and not mate.duel.is_empty()), "the duel begins for both")
	_check(String(_shell.duel["name"]) == mname and _shell.top() is TownScreen, "she fights him from the town, her screens set aside")
	await _frames(3)
	await _shot("39_duel_on")
	mate.leave_town()
	_check(await _until(func() -> bool: return not _shell.duel_result.is_empty(), 15.0), "the duel ends when he leaves the town")
	_check(bool(_shell.duel_result["won"]) and not bool(_shell.duel_result["draw"]) and _shell.duel.is_empty(), "she won: he forfeits by leaving")
	_check(Shell.duel_result_text(_shell.duel_result) == "YOU WON THE DUEL WITH %s" % mname.to_upper(), "the result in words: " + Shell.duel_result_text(_shell.duel_result))
	_check(await _until(func() -> bool: return not mate.duel_result.is_empty() and not bool(mate.duel_result["won"])), "and he is told he lost")
	_shell.open_panel(DuelPanel.new())
	await _frames(3)
	await _shot("40_duel_result")
	await _press("close")


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = code as Key
	e.physical_keycode = code as Key
	return e

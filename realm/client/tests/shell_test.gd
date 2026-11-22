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


func _finish() -> void:
	var ok: bool = _problems.is_empty()
	print("SHELL_TEST %s checks=%d shots=%d%s" % ["ok" if ok else "FAILED", _checks, _shots, "" if ok else " problems=\"%s\"" % "; ".join(_problems)])
	quit(0 if ok else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _until(cond: Callable, secs: float = 10.0) -> bool:
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


## Presses a button of the top screen by id (waits a few frames for it to be drawn first).
func _press(id: String) -> bool:
	# One frame first: a button's enabled state is as of the last draw.
	await process_frame
	for i in 200:
		var t: UiScreen = _shell.top()
		if t is PanelBase and (t as PanelBase).busy:
			await process_frame
			continue
		if t != null and t.has_hit(id):
			return t.press(id)
		await process_frame
	_check(false, "button %s is on the screen %s" % [id, _shell.base_name])
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
	await _press("settings")
	await _frames(2)
	await _shot("02_settings")
	_check(_shell.panel_of("SettingsPanel") != null, "settings open over the title")
	await _press("key:skill1")
	_shell.top().on_key(_key(KEY_Q))
	_check(ShellSettings.key("skill1") == KEY_Q, "a key is rebound from the screen")
	ShellSettings.reset_keys()
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
	_check(await _until(func() -> bool: return _shell.base_name == "hero_list"), "the login reaches the hero list")
	await _frames(3)
	_check(_shell.account > 0 and _shell.heroes.is_empty(), "a new account has no heroes")
	await _shot("04_heroes_empty")

	# The builder.
	await _press("new")
	await _frames(3)
	_check(_shell.base_name == "hero_builder", "an empty card opens the builder")
	var builder: HeroBuilderScreen = _shell.base as HeroBuilderScreen
	await _press("race:1")
	await _press("class:1")
	await _press("pal:1")
	await _press("mark:1")
	_check(builder.race == 1 and builder.cls == 1 and builder.palette == 1 and builder.mark == 1, "race, class and look are chosen")
	await _press("create")
	_check(builder.board.text.is_empty() and _shell.heroes.is_empty(), "no hero without a name")
	await _type(builder.board, "MIRA")
	await _shot("05_builder")
	await _press("create")
	_check(await _until(func() -> bool: return _shell.base_name == "hero_list" and _shell.heroes.size() == 1), "the hero is made")
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
	_check(_shell.coin() == 500 and _shell.items_at(GameNames.PLACE_BAG).size() == 3, "the dev grant gave coin and three items")
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
	_check(await _until(func() -> bool: return not _shell.guild.is_empty()), "she founds a guild")
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
	_check(_shell.coin() == 490, "and 490 are in the bag")
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
	await _press("close")
	await _frames(2)

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

	# Merchants.
	await town.open_station("merchants")
	await _frames(3)
	var coin0: int = _shell.coin()
	await _press("buy:0:5")
	_check(await _until(func() -> bool: return _shell.coin() == coin0 - 100 and _shell.stack_count(GameNames.PLACE_BAG, 100) == 7), "five healing draughts bought for 100")
	await _shot("12_merchants")
	await _press("tab:1")
	var sellable: Dictionary = {}
	for it in _shell.items_at(GameNames.PLACE_BAG):
		if int(it["rarity"]) == 0:
			sellable = it
	await _press("it:%d" % int(sellable["id"]))
	await _shot("13_merchants_sell")
	await _press("sell")
	_check(await _until(func() -> bool: return _shell.items_at(GameNames.PLACE_BAG).size() == 1), "the common item is sold")
	await _press("tab:2")
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
	await _shot("16_trainer")
	_check(_shell.panel_of("TrainerPanel") != null, "the trainer opens")
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
	var joined: bool = await _until(func() -> bool: return int(client.link.counters().get("ticks_applied", 0)) > 40, 20.0)
	_check(joined, "the field client joined with the ticket and ran 40 ticks")
	await _frames(20)
	await _shot("21_field")
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


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = code as Key
	e.physical_keycode = code as Key
	return e

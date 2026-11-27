class_name TradePanel
extends NodePanel
## Hand-to-hand trade with a hero in the same town: INVITE her by name (or ACCEPT the invitation that reached
## you), each side lays things on the table (SET OFFER), both CONFIRM the very offers they see, and the server swaps
## them in one go. The table is the server's: every change comes back as a TRADE view (a reply, or a push when the
## other side moved), and a confirm names the version seen. The shell keeps the current trade (`shell.trade`).
## Calls: TRADE_INVITE, TRADE_ACCEPT, TRADE_OFFER, TRADE_CONFIRM, TRADE_CANCEL, TRADE_VIEW (economy.md part 2).

var name_edit: LineEdit
var invite_btn: Button
var accept_btn: Button
var status: Label
var mine_list: ItemList
var theirs_list: ItemList
var bag_list: ItemList
var coin_box: SpinBox
var offer_btn: Button
var confirm_btn: Button
var cancel_btn: Button
var coin_label: Label
var note: Label
var mine_head: Label
var theirs_head: Label


func opened() -> void:
	title = "THE TRADE TABLE"
	super.opened()


func build() -> void:
	label("WHO WILL YOU TRADE WITH (SHE MUST STAND IN THIS TOWN)", Vector2(0, 0), 13, UiKit.GOLD)
	name_edit = LineEdit.new()
	name_edit.position = Vector2(0, 22)
	name_edit.size = Vector2(280, 32)
	name_edit.max_length = 16
	name_edit.focus_mode = Control.FOCUS_ALL
	name_edit.placeholder_text = "A hero's name"
	body.add_child(name_edit)
	invite_btn = add_button("INVITE", "invite", func() -> void: invite(), body, Vector2(292, 22), Vector2(120, 32))
	accept_btn = add_button("ACCEPT", "accept", func() -> void: accept(), body, Vector2(424, 22), Vector2(120, 32))
	status = label("", Vector2(0, 62), 14, UiKit.BONE, 832)
	mine_head = label("YOU LAY DOWN", Vector2(0, 90), 13, UiKit.GOLD)
	theirs_head = label("THEY LAY DOWN", Vector2(420, 90), 13, UiKit.GOLD)
	mine_list = item_list(Vector2(0, 112), Vector2(400, 110))
	theirs_list = item_list(Vector2(420, 112), Vector2(412, 110))
	label("FROM YOUR BAG (PICK WHAT TO OFFER)", Vector2(0, 232), 13, UiKit.GOLD)
	bag_list = item_list(Vector2(0, 254), Vector2(400, 100))
	bag_list.select_mode = ItemList.SELECT_MULTI
	label("COIN", Vector2(420, 232), 13, UiKit.GOLD)
	coin_box = SpinBox.new()
	coin_box.position = Vector2(420, 254)
	coin_box.size = Vector2(180, 32)
	coin_box.min_value = 0
	coin_box.max_value = 100000000
	coin_box.step = 1
	coin_box.rounded = true
	coin_box.focus_mode = Control.FOCUS_ALL
	body.add_child(coin_box)
	offer_btn = add_button("SET OFFER", "offer", func() -> void: set_offer(), body, Vector2(612, 254), Vector2(220, 32))
	confirm_btn = add_button("CONFIRM", "confirm", func() -> void: confirm(), body, Vector2(420, 300), Vector2(180, 36))
	cancel_btn = add_button("CANCEL THE TRADE", "cancel", func() -> void: cancel(), body, Vector2(612, 300), Vector2(220, 36))
	note = label("", Vector2(0, 362), 12, UiKit.BONE_DIM, 700)
	coin_label = label("", Vector2(520, 362), 12, UiKit.BONE_DIM, 312)
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shell.trade_changed.connect(refill)
	shell.data_changed.connect(refill)
	refill()


func _exit_tree() -> void:
	if shell != null:
		if shell.trade_changed.is_connected(refill):
			shell.trade_changed.disconnect(refill)
		if shell.data_changed.is_connected(refill):
			shell.data_changed.disconnect(refill)


func _session() -> int:
	return int(shell.trade.get("session", 0))


func _open() -> bool:
	return not shell.trade.is_empty() and int(shell.trade["state"]) == EconWire.TS_OPEN


func refill() -> void:
	if not is_instance_valid(bag_list):
		return
	var t: Dictionary = shell.trade
	var inv: Dictionary = shell.trade_invite
	var open: bool = _open()
	var invited: bool = not t.is_empty() and int(t["state"]) == EconWire.TS_INVITED
	var asked: bool = not inv.is_empty()
	invite_btn.disabled = open or invited or asked
	name_edit.editable = not (open or invited or asked)
	accept_btn.disabled = not asked
	offer_btn.disabled = not open
	confirm_btn.disabled = not open
	cancel_btn.disabled = t.is_empty() or int(t["state"]) > EconWire.TS_OPEN
	if asked:
		status.text = "%s ASKS YOU TO THE TABLE. ACCEPT, OR LET IT LAPSE." % String(inv["name"]).to_upper()
	elif t.is_empty():
		status.text = "NO ONE SITS ACROSS FROM YOU"
	else:
		match int(t["state"]):
			EconWire.TS_INVITED:
				status.text = "WAITING FOR %s TO SIT" % String(t["other_name"]).to_upper()
			EconWire.TS_OPEN:
				var s: String = "YOU AND %s. " % String(t["other_name"]).to_upper()
				s += "YOU HAVE CONFIRMED. " if bool(t["my_ok"]) else "YOU HAVE NOT CONFIRMED. "
				s += "THEY HAVE CONFIRMED." if bool(t["their_ok"]) else "THEY HAVE NOT."
				if int(t["lock_ms"]) > 0:
					s += "  (CONFIRM IN %.1f S)" % (float(t["lock_ms"]) / 1000.0)
				status.text = s
			EconWire.TS_DONE:
				status.text = "THE TRADE IS DONE. WHAT WAS LAID DOWN HAS CHANGED HANDS."
			_:
				status.text = "THE TRADE IS OFF. EVERYTHING STAYS WHERE IT WAS."
	var mine_items: Array = t.get("my_items", [])
	var their_items: Array = t.get("their_items", [])
	_show_side(mine_list, mine_items, t.get("my_stacks", []))
	_show_side(theirs_list, their_items, t.get("their_stacks", []))
	fill_items(bag_list, shell.items_at(GameNames.PLACE_BAG))
	unreg_prefix("bag:")
	for i in bag_list.item_count:
		reg("bag:%d" % int(bag_list.get_item_metadata(i)), bag_list, func() -> void:
			if bag_list.is_selected(i):
				bag_list.deselect(i)
			else:
				bag_list.select(i, false))
	coin_box.max_value = maxi(0, shell.coin())
	coin_label.text = "%s COIN carried" % GameNames.commas(shell.coin())


func _show_side(list: ItemList, items: Array, stacks: Array) -> void:
	fill_items(list, items)
	for s in stacks:
		var i: int = list.add_item("%s  %s" % [GameNames.stack_name(int(s[0])), GameNames.commas(int(s[1]))], UiArt.stack_icon(int(s[0]), 22))
		list.set_item_metadata(i, -int(s[0]))


# ---- requests

func _apply(r: Dictionary) -> void:
	if int(r.get("k", -1)) == EconWire.K_TRADE:
		shell.set_trade(r)


func invite() -> void:
	var r: Dictionary = await do(EconWire.trade_invite(shell.hero_id(), name_edit.text.strip_edges()), "THE INVITATION GOES OUT", false)
	if is_instance_valid(self):
		_apply(r)


func accept() -> void:
	var inv: Dictionary = shell.trade_invite
	if inv.is_empty():
		return
	var r: Dictionary = await do(EconWire.with_id(EconWire.Q_TRADE_ACCEPT, shell.hero_id(), int(inv["session"])), "YOU SIT", false)
	if is_instance_valid(self):
		shell.trade_invite = {}
		_apply(r)
		refill()


func set_offer() -> void:
	var items: Array = []
	for i in bag_list.get_selected_items():
		items.append(int(bag_list.get_item_metadata(i)))
	var stacks: Array = []
	if int(coin_box.value) > 0:
		stacks.append([GameNames.KIND_COIN, int(coin_box.value)])
	var r: Dictionary = await do(EconWire.trade_offer(shell.hero_id(), _session(), items, stacks), "THE OFFER IS LAID DOWN", false)
	if is_instance_valid(self):
		_apply(r)


func confirm() -> void:
	var r: Dictionary = await do(EconWire.trade_confirm(shell.hero_id(), _session(), int(shell.trade.get("version", 0))), "", true)
	if is_instance_valid(self):
		_apply(r)
		if not shell.trade.is_empty() and int(shell.trade["state"]) == EconWire.TS_DONE:
			say("DONE: THE TRADE IS MADE")


func cancel() -> void:
	var r: Dictionary = await do(EconWire.with_id(EconWire.Q_TRADE_CANCEL, shell.hero_id(), _session()), "THE TRADE IS CALLED OFF", false)
	if is_instance_valid(self):
		_apply(r)
		if int(r.get("k", -1)) == EconWire.K_OK or int(r["t"]) == GwWire.R_OK:
			shell.set_trade({})
		refill()

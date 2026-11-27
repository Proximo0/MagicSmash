class_name PostPanel
extends NodePanel
## The post: letters between heroes. INBOX (read, TAKE what is attached, paying the cash on delivery if the
## sender asked one, or REFUSE and it goes back), WRITE (a text of 200 characters, one to eight things, a price
## if you wish), SENT (RECALL what nobody has opened) and the SHELF (what came back to you: a listing taken down or
## run out, a refused letter). Calls: INBOX, OUTBOX, LETTER_SEND, LETTER_TAKE, LETTER_REFUSE, LETTER_RECALL and
## MAIL_TAKE (economy.md part 2).

const TEXT_MAX: int = 200

var tabs_bar: TabBar
var pages: Array[Control] = []
var inbox: Array[Dictionary] = []
var outbox: Array[Dictionary] = []
var coin_label: Label
# INBOX
var in_list: ItemList
var in_text: Label
var take_btn: Button
var refuse_btn: Button
var in_id: int = -1
# WRITE
var to_edit: LineEdit
var text_edit: LineEdit
var cod_box: SpinBox
var coin_box: SpinBox
var attach: ItemList
var send_btn: Button
var write_note: Label
# SENT
var out_list: ItemList
var out_text: Label
var recall_btn: Button
var out_id: int = -1
# SHELF
var shelf_items: ItemList
var shelf_stacks: ItemList
var shelf_btn: Button
var shelf_note: Label


func opened() -> void:
	title = "THE POST"
	super.opened()


func build() -> void:
	tabs_bar = TabBar.new()
	tabs_bar.focus_mode = Control.FOCUS_ALL
	tabs_bar.custom_minimum_size = Vector2(340, 34)
	tabs_bar.clip_tabs = false
	for n in ["INBOX", "WRITE", "SENT", "SHELF"]:
		tabs_bar.add_tab(n)
	tabs_bar.tab_changed.connect(_tab_changed)
	body.add_child(tabs_bar)
	for i in 4:
		reg("tab:%d" % i, tabs_bar, func() -> void: tabs_bar.current_tab = i)
	coin_label = label("", Vector2(520, 4), 13, UiKit.GOLD, 312)
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for i in 4:
		var p := Control.new()
		p.position = Vector2(0, 40)
		p.size = Vector2(832, 370)
		body.add_child(p)
		pages.append(p)
	_build_inbox(pages[0])
	_build_write(pages[1])
	_build_sent(pages[2])
	_build_shelf(pages[3])
	shell.data_changed.connect(_refill)
	_tab_changed(0)


func _exit_tree() -> void:
	if shell != null and shell.data_changed.is_connected(_refill):
		shell.data_changed.disconnect(_refill)


func _build_inbox(p: Control) -> void:
	in_list = item_list(Vector2(0, 0), Vector2(380, 320), p)
	in_list.item_selected.connect(func(i: int) -> void: _read_letter(inbox, in_list, i, true))
	in_text = label("", Vector2(400, 0), 14, UiKit.BONE, 430, p)
	take_btn = add_button("TAKE", "take", func() -> void: take(), p, Vector2(400, 290), Vector2(200, 34))
	refuse_btn = add_button("REFUSE", "refuse", func() -> void: refuse(), p, Vector2(616, 290), Vector2(200, 34))
	take_btn.disabled = true
	refuse_btn.disabled = true


func _build_write(p: Control) -> void:
	label("TO (A HERO'S NAME)", Vector2(0, 0), 13, UiKit.GOLD, 0, p)
	to_edit = _line(p, Vector2(0, 22), Vector2(300, 32), 16)
	label("THE LETTER", Vector2(0, 64), 13, UiKit.GOLD, 0, p)
	text_edit = _line(p, Vector2(0, 86), Vector2(420, 32), TEXT_MAX)
	label("PRICE TO OPEN IT (COIN, 0 FOR A GIFT)", Vector2(0, 130), 13, UiKit.GOLD, 0, p)
	cod_box = _spin(p, Vector2(0, 152), Vector2(200, 32), 0, 100000000000)
	label("COIN ATTACHED", Vector2(0, 196), 13, UiKit.GOLD, 0, p)
	coin_box = _spin(p, Vector2(0, 218), Vector2(200, 32), 0, 100000000)
	label("ATTACH FROM YOUR BAG (1 TO 8 THINGS IN ALL)", Vector2(440, 0), 13, UiKit.GOLD, 0, p)
	attach = item_list(Vector2(440, 22), Vector2(392, 240), p)
	attach.select_mode = ItemList.SELECT_MULTI
	send_btn = add_button("SEND", "send", func() -> void: send(), p, Vector2(0, 270), Vector2(200, 36))
	write_note = label("Postage is paid when the letter goes.", Vector2(220, 278), 12, UiKit.BONE_DIM, 600, p)


func _build_sent(p: Control) -> void:
	out_list = item_list(Vector2(0, 0), Vector2(380, 320), p)
	out_list.item_selected.connect(func(i: int) -> void: _read_letter(outbox, out_list, i, false))
	out_text = label("", Vector2(400, 0), 14, UiKit.BONE, 430, p)
	recall_btn = add_button("RECALL", "recall", func() -> void: recall(), p, Vector2(400, 290), Vector2(200, 34))
	recall_btn.disabled = true


func _build_shelf(p: Control) -> void:
	label("THINGS THAT CAME BACK TO YOU", Vector2(0, 0), 13, UiKit.GOLD, 0, p)
	shelf_items = item_list(Vector2(0, 24), Vector2(400, 220), p)
	shelf_stacks = item_list(Vector2(420, 24), Vector2(412, 220), p)
	shelf_btn = add_button("TAKE INTO THE BAG", "shelf_take", func() -> void: shelf_take(), p, Vector2(0, 256), Vector2(240, 36))
	shelf_btn.disabled = true
	shelf_note = label("", Vector2(260, 264), 13, UiKit.BONE_DIM, 570, p)
	shelf_items.item_selected.connect(func(_i: int) -> void: shelf_stacks.deselect_all(); shelf_btn.disabled = false)
	shelf_stacks.item_selected.connect(func(_i: int) -> void: shelf_items.deselect_all(); shelf_btn.disabled = false)


func _line(p: Control, at: Vector2, sz: Vector2, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.position = at
	e.size = sz
	e.max_length = max_len
	e.focus_mode = Control.FOCUS_ALL
	p.add_child(e)
	return e


func _spin(p: Control, at: Vector2, sz: Vector2, lo: float, hi: float) -> SpinBox:
	var s := SpinBox.new()
	s.position = at
	s.size = sz
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.rounded = true
	s.focus_mode = Control.FOCUS_ALL
	p.add_child(s)
	return s


func _tab_changed(t: int) -> void:
	for i in pages.size():
		pages[i].visible = i == t
	match t:
		0:
			refresh_inbox()
		2:
			refresh_outbox()
	_refill()


func _refill() -> void:
	if not is_instance_valid(attach):
		return
	coin_label.text = "%s COIN carried" % GameNames.commas(shell.coin())
	fill_items(attach, shell.items_at(GameNames.PLACE_BAG))
	unreg_prefix("att:")
	for i in attach.item_count:
		reg("att:%d" % int(attach.get_item_metadata(i)), attach, func() -> void:
			if attach.is_selected(i):
				attach.deselect(i)
			else:
				attach.select(i, false))
	coin_box.max_value = maxi(0, shell.coin())
	fill_items(shelf_items, shell.items_at(GameNames.PLACE_MAIL))
	fill_stacks(shelf_stacks, shell.stacks_at(GameNames.PLACE_MAIL))
	unreg_prefix("shelfit:")
	unreg_prefix("shelfstk:")
	for i in shelf_items.item_count:
		reg("shelfit:%d" % int(shelf_items.get_item_metadata(i)), shelf_items, func() -> void:
			shelf_items.select(i)
			shelf_items.item_selected.emit(i))
	for i in shelf_stacks.item_count:
		reg("shelfstk:%d" % int(shelf_stacks.get_item_metadata(i)), shelf_stacks, func() -> void:
			shelf_stacks.select(i)
			shelf_stacks.item_selected.emit(i))
	shelf_btn.disabled = true
	shelf_note.text = "NOTHING HAS COME BACK" if shelf_items.item_count + shelf_stacks.item_count == 0 else ""


func _things_text(l: Dictionary) -> String:
	var out: PackedStringArray = []
	for it in l["items"]:
		out.append(item_label(it))
	for s in l["stacks"]:
		out.append("%s x %s" % [GameNames.stack_name(int(s[0])), GameNames.commas(int(s[1]))])
	return ", ".join(out) if not out.is_empty() else "NOTHING"


func _letter_text(l: Dictionary, incoming: bool) -> String:
	var left: int = int((float(l["expires"]) / 1000.0) - Time.get_unix_time_from_system())
	var s: String = "%s %s\n\n\"%s\"\n\nWITH IT: %s\n" % ["FROM" if incoming else "TO", String(l["from"] if incoming else l["to"]).to_upper(), l["text"], _things_text(l)]
	if int(l["cod"]) > 0:
		s += "\nTO OPEN IT YOU PAY %s COIN\n" % GameNames.commas(int(l["cod"]))
	s += "\nIT WAITS %s MORE" % span_text(left)
	return s


func _read_letter(rows: Array, list: ItemList, i: int, incoming: bool) -> void:
	var id: int = int(list.get_item_metadata(i))
	for l in rows:
		if int(l["id"]) == id:
			if incoming:
				in_id = id
				in_text.text = _letter_text(l, true)
				take_btn.text = "PAY %s AND TAKE" % GameNames.commas(int(l["cod"])) if int(l["cod"]) > 0 else "TAKE"
				take_btn.disabled = false
				refuse_btn.disabled = false
			else:
				out_id = id
				out_text.text = _letter_text(l, false)
				recall_btn.disabled = false


func _fill_letters(list: ItemList, rows: Array, prefix: String, incoming: bool) -> void:
	list.clear()
	unreg_prefix(prefix)
	for i in rows.size():
		var l: Dictionary = rows[i]
		var snip: String = String(l["text"]).substr(0, 24)
		list.add_item("%s: %s" % [String(l["from"] if incoming else l["to"]).to_upper(), snip if not snip.is_empty() else "(a seal, no words)"])
		list.set_item_metadata(i, int(l["id"]))
		reg(prefix + str(int(l["id"])), list, func() -> void:
			list.select(i)
			_read_letter(rows, list, i, incoming))


# ---- requests

func refresh_inbox() -> void:
	var r: Dictionary = await do(EconWire.hero_only(EconWire.Q_INBOX, shell.hero_id()), "", false)
	if not is_instance_valid(self) or int(r.get("k", -1)) != EconWire.K_LETTERS:
		return
	inbox.assign(r["letters"])
	in_id = -1
	take_btn.disabled = true
	refuse_btn.disabled = true
	_fill_letters(in_list, inbox, "in:", true)
	in_text.text = "NO LETTER WAITS FOR YOU" if inbox.is_empty() else "%d LETTERS WAIT. CHOOSE ONE." % inbox.size()


func refresh_outbox() -> void:
	var r: Dictionary = await do(EconWire.hero_only(EconWire.Q_OUTBOX, shell.hero_id()), "", false)
	if not is_instance_valid(self) or int(r.get("k", -1)) != EconWire.K_LETTERS:
		return
	outbox.assign(r["letters"])
	out_id = -1
	recall_btn.disabled = true
	_fill_letters(out_list, outbox, "out:", false)
	out_text.text = "No letter of yours is on the road." if outbox.is_empty() else "%d ON THE ROAD. UNOPENED ONES MAY BE RECALLED." % outbox.size()


func take() -> void:
	if in_id < 0:
		return
	var r: Dictionary = await do(EconWire.with_id(EconWire.Q_LETTER_TAKE, shell.hero_id(), in_id), "THE SEAL IS BROKEN: IT IS IN YOUR BAG")
	if is_instance_valid(self):
		await refresh_inbox()


func refuse() -> void:
	if in_id < 0:
		return
	var r: Dictionary = await do(EconWire.with_id(EconWire.Q_LETTER_REFUSE, shell.hero_id(), in_id), "SENT BACK UNOPENED")
	if is_instance_valid(self):
		await refresh_inbox()


func recall() -> void:
	if out_id < 0:
		return
	var r: Dictionary = await do(EconWire.with_id(EconWire.Q_LETTER_RECALL, shell.hero_id(), out_id), "RECALLED: IT WAITS ON YOUR SHELF")
	if is_instance_valid(self):
		await refresh_outbox()


func send() -> void:
	var things: Array = []
	for i in attach.get_selected_items():
		things.append([int(attach.get_item_metadata(i)), 0, 0])
	if int(coin_box.value) > 0:
		things.append([0, GameNames.KIND_COIN, int(coin_box.value)])
	var r: Dictionary = await do(EconWire.letter_send(shell.hero_id(), to_edit.text.strip_edges(), text_edit.text, things, int(cod_box.value)))
	if not is_instance_valid(self):
		return
	if int(r.get("k", -1)) == EconWire.K_LISTED:
		write_note.text = "SENT. POSTAGE %s COIN." % GameNames.commas(int(r["fee"]))
		say("SENT, POSTAGE %s COIN" % GameNames.commas(int(r["fee"])))
		text_edit.text = ""
		attach.deselect_all()
		coin_box.value = 0
		_refill()


func shelf_take() -> void:
	var hero: int = shell.hero_id()
	var req: Array = []
	var what: String = ""
	var s: PackedInt32Array = shelf_items.get_selected_items()
	if s.size() > 0:
		req = GwWire.mail_take(hero, int(shelf_items.get_item_metadata(s[0])), 0, 0)
		what = shelf_items.get_item_text(s[0])
	else:
		var t: PackedInt32Array = shelf_stacks.get_selected_items()
		if t.size() == 0:
			return
		var kind: int = int(shelf_stacks.get_item_metadata(t[0]))
		req = GwWire.mail_take(hero, 0, kind, shell.stack_count(GameNames.PLACE_MAIL, kind))
		what = GameNames.stack_name(kind)
	var r: Dictionary = await do(req, "TAKEN FROM THE SHELF: " + what)
	if is_instance_valid(self):
		_refill()

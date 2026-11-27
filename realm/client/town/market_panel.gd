class_name MarketPanel
extends NodePanel
## The market: listings other heroes made (BROWSE, filter and BUY), putting a thing of her own up for a price
## (SELL), and her own open listings (MINE, CANCEL). The server decides everything: the price cap, the fee, the tax,
## who may buy. Calls: MARKET_SEARCH, MARKET_BUY, MARKET_LIST, MARKET_MINE, MARKET_CANCEL (economy.md part 2).
## Listings come as the server's rows; a cancelled or expired listing goes back to her mail shelf (the POST).

const PAGE_BROWSE: int = 0
const PAGE_SELL: int = 1
const PAGE_MINE: int = 2

var page: int = PAGE_BROWSE
var tabs_bar: TabBar
var pages: Array[Control] = []
var listings: Array[Dictionary] = []
var mine: Array[Dictionary] = []
var offset: int = 0
var sel_listing: int = -1
var sel_mine: int = -1
# BROWSE
var slot_opt: OptionButton
var rarity_opt: OptionButton
var max_price: SpinBox
var results: Tree
var buy_btn: Button
var browse_note: Label
# SELL
var sell_items: ItemList
var sell_stacks: ItemList
var price_box: SpinBox
var count_box: SpinBox
var hours_opt: OptionButton
var list_btn: Button
var sell_note: Label
var sel_item: int = 0
var sel_kind: int = -1
# MINE
var mine_tree: Tree
var cancel_btn: Button
var mine_note: Label
var coin_label: Label


func opened() -> void:
	title = "THE MARKET"
	super.opened()


func build() -> void:
	tabs_bar = TabBar.new()
	tabs_bar.position = Vector2(0, 0)
	tabs_bar.focus_mode = Control.FOCUS_ALL
	tabs_bar.custom_minimum_size = Vector2(340, 34)
	tabs_bar.clip_tabs = false
	for n in ["BROWSE", "SELL", "MINE"]:
		tabs_bar.add_tab(n)
	tabs_bar.tab_changed.connect(_tab_changed)
	body.add_child(tabs_bar)
	for i in 3:
		reg("tab:%d" % i, tabs_bar, func() -> void: tabs_bar.current_tab = i)
	coin_label = label("", Vector2(520, 4), 13, UiKit.GOLD, 312)
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for i in 3:
		var p := Control.new()
		p.position = Vector2(0, 40)
		p.size = Vector2(832, 370)
		body.add_child(p)
		pages.append(p)
	_build_browse(pages[PAGE_BROWSE])
	_build_sell(pages[PAGE_SELL])
	_build_mine(pages[PAGE_MINE])
	shell.data_changed.connect(_refill)
	_show_page(PAGE_BROWSE)
	search.call_deferred()


func _exit_tree() -> void:
	if shell != null and shell.data_changed.is_connected(_refill):
		shell.data_changed.disconnect(_refill)


func _tree(parent: Control, at: Vector2, sz: Vector2, cols: Array, widths: Array) -> Tree:
	var t := Tree.new()
	t.position = at
	t.size = sz
	t.columns = cols.size()
	t.column_titles_visible = true
	t.hide_root = true
	t.select_mode = Tree.SELECT_ROW
	t.focus_mode = Control.FOCUS_ALL
	for i in cols.size():
		t.set_column_title(i, String(cols[i]))
		t.set_column_custom_minimum_width(i, int(widths[i]))
		t.set_column_expand(i, i == 0)
	parent.add_child(t)
	return t


func _build_browse(p: Control) -> void:
	label("SLOT", Vector2(0, 6), 12, UiKit.BONE_DIM, 0, p)
	slot_opt = OptionButton.new()
	slot_opt.position = Vector2(44, 0)
	slot_opt.size = Vector2(120, 30)
	slot_opt.focus_mode = Control.FOCUS_ALL
	slot_opt.add_item("ANY", 255)
	for i in GameNames.SLOTS.size():
		slot_opt.add_item(GameNames.SLOTS[i], i)
	p.add_child(slot_opt)
	label("RARITY", Vector2(180, 6), 12, UiKit.BONE_DIM, 0, p)
	rarity_opt = OptionButton.new()
	rarity_opt.position = Vector2(236, 0)
	rarity_opt.size = Vector2(150, 30)
	rarity_opt.focus_mode = Control.FOCUS_ALL
	rarity_opt.add_item("ANY", 0)
	for i in range(1, GameNames.RARITIES.size()):
		rarity_opt.add_item(GameNames.RARITIES[i] + " UP", i)
	p.add_child(rarity_opt)
	label("COIN AT MOST", Vector2(404, 6), 12, UiKit.BONE_DIM, 0, p)
	max_price = _spin(p, Vector2(510, 0), Vector2(130, 30), 0, 100000000000)
	add_button("SEARCH", "search", func() -> void: offset = 0; search(), p, Vector2(660, 0), Vector2(80, 30))
	add_button("MORE", "more", func() -> void: offset += 40; search(), p, Vector2(748, 0), Vector2(80, 30))
	results = _tree(p, Vector2(0, 40), Vector2(832, 250), ["THING", "SELLER", "PRICE", "LEFT"], [360, 150, 150, 110])
	results.item_selected.connect(func() -> void: _picked(results, true))
	buy_btn = add_button("BUY", "buy", func() -> void: buy(), p, Vector2(0, 300), Vector2(150, 34))
	buy_btn.disabled = true
	browse_note = label("", Vector2(170, 308), 13, UiKit.BONE_DIM, 660, p)


func _build_sell(p: Control) -> void:
	label("OF YOUR BAG", Vector2(0, 0), 13, UiKit.GOLD, 0, p)
	sell_items = item_list(Vector2(0, 24), Vector2(400, 190), p)
	sell_stacks = item_list(Vector2(0, 222), Vector2(400, 100), p)
	sell_items.item_selected.connect(func(i: int) -> void: _sell_chose(sell_items, i, true))
	sell_stacks.item_selected.connect(func(i: int) -> void: _sell_chose(sell_stacks, i, false))
	label("ASKING PRICE (COIN)", Vector2(430, 0), 13, UiKit.GOLD, 0, p)
	price_box = _spin(p, Vector2(430, 24), Vector2(200, 32), 1, 100000000000)
	price_box.value = 10
	label("HOW MANY (A STACK)", Vector2(430, 70), 13, UiKit.GOLD, 0, p)
	count_box = _spin(p, Vector2(430, 94), Vector2(200, 32), 1, 1000000)
	label("FOR", Vector2(430, 140), 13, UiKit.GOLD, 0, p)
	hours_opt = OptionButton.new()
	hours_opt.position = Vector2(430, 162)
	hours_opt.size = Vector2(200, 32)
	hours_opt.focus_mode = Control.FOCUS_ALL
	for h in EconWire.HOURS:
		hours_opt.add_item("%d HOURS" % h, h)
	p.add_child(hours_opt)
	list_btn = add_button("PUT IT UP", "list", func() -> void: put_up(), p, Vector2(430, 212), Vector2(200, 36))
	list_btn.disabled = true
	sell_note = label("The house takes a fee to list it, and a tax when it sells.", Vector2(430, 262), 12, UiKit.BONE_DIM, 400, p)


func _build_mine(p: Control) -> void:
	mine_tree = _tree(p, Vector2(0, 0), Vector2(832, 290), ["THING", "SELLER", "PRICE", "LEFT"], [360, 150, 150, 110])
	mine_tree.item_selected.connect(func() -> void: _picked(mine_tree, false))
	cancel_btn = add_button("TAKE IT DOWN", "cancel", func() -> void: cancel(), p, Vector2(0, 300), Vector2(170, 34))
	cancel_btn.disabled = true
	mine_note = label("", Vector2(190, 308), 13, UiKit.BONE_DIM, 640, p)


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
	_show_page(t)
	if t == PAGE_MINE:
		refresh_mine()
	elif t == PAGE_BROWSE:
		search()


func _show_page(t: int) -> void:
	page = t
	for i in pages.size():
		pages[i].visible = i == t
	_refill()


func _refill() -> void:
	if not is_instance_valid(sell_items):
		return
	coin_label.text = "%s COIN carried" % GameNames.commas(shell.coin())
	var items: Array = shell.items_at(GameNames.PLACE_BAG)
	fill_items(sell_items, items)
	var stacks: Array = []
	for s in shell.stacks_at(GameNames.PLACE_BAG):
		if int(s[1]) != GameNames.KIND_COIN:
			stacks.append(s)
	fill_stacks(sell_stacks, stacks)
	unreg_prefix("sellit:")
	unreg_prefix("sellstk:")
	_reg_rows("sellit:", sell_items, true)
	_reg_rows("sellstk:", sell_stacks, false)
	sel_item = 0
	sel_kind = -1
	list_btn.disabled = true


func _reg_rows(prefix: String, list: ItemList, is_item: bool) -> void:
	for i in list.item_count:
		reg(prefix + str(int(list.get_item_metadata(i))), list, func() -> void:
			list.select(i)
			_sell_chose(list, i, is_item))


func _sell_chose(list: ItemList, i: int, is_item: bool) -> void:
	var id: int = int(list.get_item_metadata(i))
	sel_item = id if is_item else 0
	sel_kind = -1 if is_item else id
	(sell_stacks if is_item else sell_items).deselect_all()
	list_btn.disabled = false
	if not is_item:
		count_box.max_value = maxi(1, shell.stack_count(GameNames.PLACE_BAG, id))
		count_box.value = count_box.max_value


# ---- rows

func _fill_tree(t: Tree, rows: Array, prefix: String) -> void:
	t.clear()
	unreg_prefix(prefix)
	var root: TreeItem = t.create_item()
	var now_s: float = Time.get_unix_time_from_system()
	for l in rows:
		var ti: TreeItem = t.create_item(root)
		ti.set_metadata(0, int(l["id"]))
		if not (l["item"] as Dictionary).is_empty():
			var it: Dictionary = l["item"]
			ti.set_text(0, item_label(it))
			ti.set_icon(0, UiArt.item_icon(int(it["gear_slot"]), int(it["rarity"]), 22, int(it.get("base", -1))))
			ti.set_custom_color(0, GameNames.rarity_colour(int(it["rarity"])))
			ti.set_tooltip_text(0, item_tip_text(it))
		else:
			var st: Array = l["stack"]
			ti.set_text(0, "%s x %s" % [GameNames.stack_name(int(st[0])), GameNames.commas(int(st[1]))])
			ti.set_icon(0, UiArt.stack_icon(int(st[0]), 22))
		ti.set_text(1, String(l["seller"]) + ("  (you)" if bool(l["mine"]) else ""))
		ti.set_text(2, "%s COIN" % GameNames.commas(int(l["price"])))
		ti.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		ti.set_text(3, span_text(int((float(l["expires"]) / 1000.0) - now_s)))
		reg(prefix + str(int(l["id"])), t, func() -> void:
			ti.select(0)
			t.item_selected.emit())


func _picked(t: Tree, browsing: bool) -> void:
	var ti: TreeItem = t.get_selected()
	var id: int = int(ti.get_metadata(0)) if ti != null else -1
	if browsing:
		sel_listing = id
		buy_btn.disabled = id < 0 or _listing(listings, id).get("mine", false)
		var l: Dictionary = _listing(listings, id)
		browse_note.text = "" if l.is_empty() else ("YOUR OWN LISTING: TAKE IT DOWN UNDER MINE" if bool(l["mine"]) else "BUY FOR %s COIN" % GameNames.commas(int(l["price"])))
	else:
		sel_mine = id
		cancel_btn.disabled = id < 0


func _listing(rows: Array, id: int) -> Dictionary:
	for l in rows:
		if int(l["id"]) == id:
			return l
	return {}


# ---- requests

func search() -> void:
	var q := {"gear_slot": slot_opt.get_selected_id(), "rarity_min": rarity_opt.get_selected_id(), "price_max": int(max_price.value), "offset": offset}
	var r: Dictionary = await do(EconWire.market_search(shell.hero_id(), q), "", false)
	if not is_instance_valid(self) or int(r["t"]) != EconWire.R_ECON or int(r.get("k", -1)) != EconWire.K_LISTINGS:
		return
	listings.assign(r["listings"])
	sel_listing = -1
	buy_btn.disabled = true
	_fill_tree(results, listings, "row:")
	browse_note.text = "THE SHELVES ARE BARE" if listings.is_empty() else "%d LISTED (CHEAPEST FIRST)" % listings.size()


func buy() -> void:
	var l: Dictionary = _listing(listings, sel_listing)
	if l.is_empty():
		return
	var r: Dictionary = await do(EconWire.with_id(EconWire.Q_MARKET_BUY, shell.hero_id(), sel_listing), "BOUGHT FOR %s COIN" % GameNames.commas(int(l["price"])))
	if is_instance_valid(self):
		await search()


func put_up() -> void:
	var req: Array = []
	if sel_item != 0:
		req = EconWire.market_list(shell.hero_id(), sel_item, 0, 0, int(price_box.value), hours_opt.get_selected_id())
	elif sel_kind >= 0:
		req = EconWire.market_list(shell.hero_id(), 0, sel_kind, int(count_box.value), int(price_box.value), hours_opt.get_selected_id())
	else:
		return
	var r: Dictionary = await do(req)
	if not is_instance_valid(self):
		return
	if int(r["t"]) == EconWire.R_ECON and int(r.get("k", -1)) == EconWire.K_LISTED:
		sell_note.text = "LISTED. THE HOUSE TOOK %s COIN FOR THE FEE." % GameNames.commas(int(r["fee"]))
		say("LISTED, FEE %s COIN" % GameNames.commas(int(r["fee"])))
		_refill()


func refresh_mine() -> void:
	var r: Dictionary = await do(EconWire.hero_only(EconWire.Q_MARKET_MINE, shell.hero_id()), "", false)
	if not is_instance_valid(self) or int(r["t"]) != EconWire.R_ECON or int(r.get("k", -1)) != EconWire.K_LISTINGS:
		return
	mine.assign(r["listings"])
	sel_mine = -1
	cancel_btn.disabled = true
	_fill_tree(mine_tree, mine, "mine:")
	mine_note.text = "NOTHING OF YOURS IS LISTED" if mine.is_empty() else "%d OF YOURS ARE LISTED: A TAKEN-DOWN THING WAITS AT THE POST" % mine.size()


func cancel() -> void:
	if sel_mine < 0:
		return
	var r: Dictionary = await do(EconWire.with_id(EconWire.Q_MARKET_CANCEL, shell.hero_id(), sel_mine), "TAKEN DOWN: IT WAITS AT THE POST")
	if is_instance_valid(self):
		await refresh_mine()

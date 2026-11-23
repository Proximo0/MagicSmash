class_name BankPanel
extends NodePanel
## The bank: the account's chest, shared by every hero (100 slots a tab; the gateway's BANK_DEPOSIT and
## BANK_WITHDRAW take the tab). Choose a thing in the bag or the bank, then MOVE (or press it twice). Stacks
## (coin, embers, runes, potions) move 1, 10 or all at a time. The tab strip shows the tabs the account owns and,
## locked, the ones it may still buy (ECON BankTabs: owned, the most, the next one's price); BUY buys the next for
## coin from her bag (ECON BankTabBuy, a coin sink; the price rises with each tab, realm/loot sinks.rs).

const TAB_MAX: int = 8

var sel_item: int = 0
var sel_kind: int = -1
var sel_place: int = 0
var qty: int = 1
var tab: int = 0
var bag_items: ItemList
var bag_stacks: ItemList
var bank_items: ItemList
var bank_stacks: ItemList
var tab_bar: TabBar
var move_btn: Button
var qty_btns: Array[Button] = []
var info: Label
var coin_label: Label
var buy_btn: Button
var tab_note: Label
## The account's tabs as the gateway last said: owned (the free one counted), the most, the next one's price.
var tabs_owned: int = 1
var tabs_max: int = TAB_MAX
var tab_price: int = 0


func opened() -> void:
	title = "THE BANK"
	super.opened()


func build() -> void:
	label("YOUR BAG", Vector2(0, 0), 14, UiKit.GOLD)
	bag_items = item_list(Vector2(0, 24), Vector2(400, 150))
	bag_items.max_columns = 1
	bag_stacks = item_list(Vector2(0, 182), Vector2(400, 128))
	label("THE BANK: TAB", Vector2(420, 0), 14, UiKit.GOLD)
	tab_bar = TabBar.new()
	tab_bar.position = Vector2(540, 0)
	tab_bar.focus_mode = Control.FOCUS_ALL
	tab_bar.custom_minimum_size = Vector2(292, 34)
	tab_bar.clip_tabs = false
	tab_bar.tab_changed.connect(_tab_changed)
	# A locked tab is dark and dim, unlike the ones she owns.
	tab_bar.add_theme_color_override("font_disabled_color", Color(UiKit.BONE_DIM, 0.35))
	var locked := StyleBoxFlat.new()
	locked.bg_color = Color(0.02, 0.018, 0.022)
	locked.border_color = Color(UiKit.GOLD_DIM, 0.25)
	locked.set_border_width_all(1)
	locked.set_content_margin_all(8)
	tab_bar.add_theme_stylebox_override("tab_disabled", locked)
	body.add_child(tab_bar)
	tab_note = label("", Vector2(520, 388), 12, UiKit.BONE_DIM, 312)
	tab_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	buy_btn = add_button("BUY A TAB", "buy_tab", func() -> void: buy_tab(), body, Vector2(582, 322), Vector2(250, 32))
	bank_items = item_list(Vector2(420, 34), Vector2(412, 140))
	bank_stacks = item_list(Vector2(420, 182), Vector2(412, 128))
	bag_items.item_selected.connect(func(i: int) -> void: _chose(GameNames.PLACE_BAG, bag_items, i, true))
	bag_stacks.item_selected.connect(func(i: int) -> void: _chose(GameNames.PLACE_BAG, bag_stacks, i, false))
	bank_items.item_selected.connect(func(i: int) -> void: _chose(GameNames.PLACE_BANK, bank_items, i, true))
	bank_stacks.item_selected.connect(func(i: int) -> void: _chose(GameNames.PLACE_BANK, bank_stacks, i, false))
	for l in [bag_items, bag_stacks, bank_items, bank_stacks]:
		(l as ItemList).item_activated.connect(func(_i: int) -> void: move_selected())
	label("HOW MANY", Vector2(0, 330), 12, UiKit.BONE_DIM)
	for i in 3:
		var q: int = [1, 10, 0][i]
		var b: Button = add_button("ALL" if q == 0 else str(q), "qty:%d" % q, _set_qty.bind(q), body, Vector2(76 + i * 60, 322), Vector2(54, 32))
		b.toggle_mode = true
		qty_btns.append(b)
	move_btn = add_button("CHOOSE A THING", "move", func() -> void: move_selected(), body, Vector2(330, 322), Vector2(180, 32))
	info = label("", Vector2(0, 366), 14, UiKit.BONE, 520)
	coin_label = label("", Vector2(520, 366), 12, UiKit.BONE_DIM, 312)
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shell.data_changed.connect(refill)
	refill()
	read_tabs.call_deferred()


func _exit_tree() -> void:
	if shell != null and shell.data_changed.is_connected(refill):
		shell.data_changed.disconnect(refill)


## Asks the gateway how many tabs the account owns and what the next costs.
func read_tabs() -> void:
	var r: Dictionary = await shell.link.call_req(EconWire.hero_only(EconWire.Q_BANK_TABS, shell.hero_id()))
	if is_instance_valid(self):
		_took_tabs(r)


func _took_tabs(r: Dictionary) -> void:
	if int(r["t"]) != EconWire.R_ECON or int(r.get("k", -1)) != EconWire.K_BANK_TABS:
		return
	tabs_owned = int(r["owned"])
	tabs_max = int(r["max"])
	tab_price = int(r["price"])
	refill()


## Buys the next tab for coin. Returns the gateway's reply.
func buy_tab() -> Dictionary:
	var next: int = tabs_owned + 1
	var r: Dictionary = await do(EconWire.bank_tab_buy(shell.hero_id(), tabs_owned), "TAB %d IS YOURS: %s COIN TO THE BANK" % [next, GameNames.commas(tab_price)])
	if is_instance_valid(self):
		_took_tabs(r)
		if tabs_owned >= next:
			_set_tab(next - 1)
	return r


func refill() -> void:
	if not is_instance_valid(bag_items):
		return
	var n: int = tabs_max
	tab_bar.set_block_signals(true)
	while tab_bar.tab_count < n:
		var idx: int = tab_bar.tab_count
		reg("tab:%d" % idx, tab_bar, _set_tab.bind(idx))
		tab_bar.add_tab(str(idx + 1))
	# Owned tabs are numbers to choose; the rest are greyed (locked) until bought.
	for i in tab_bar.tab_count:
		tab_bar.set_tab_disabled(i, i >= tabs_owned)
		tab_bar.set_tab_tooltip(i, "TAB %d" % (i + 1) if i < tabs_owned else "TAB %d: NOT YET YOURS" % (i + 1))
	tab_bar.set_block_signals(false)
	tab = mini(tab, maxi(tabs_owned - 1, 0))
	if tab_bar.current_tab != tab:
		tab_bar.set_block_signals(true)
		tab_bar.current_tab = tab
		tab_bar.set_block_signals(false)
	fill_items(bag_items, shell.items_at(GameNames.PLACE_BAG))
	fill_stacks(bag_stacks, shell.stacks_at(GameNames.PLACE_BAG))
	var here: Array = []
	for it in shell.items_at(GameNames.PLACE_BANK):
		if int(it["tab"]) == tab:
			here.append(it)
	here.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
	fill_items(bank_items, here)
	fill_stacks(bank_stacks, shell.stacks_at(GameNames.PLACE_BANK))
	unreg_prefix("bagit:")
	unreg_prefix("bankit:")
	unreg_prefix("bstk:")
	unreg_prefix("kstk:")
	_reg_rows("bagit:", bag_items, GameNames.PLACE_BAG, true)
	_reg_rows("bstk:", bag_stacks, GameNames.PLACE_BAG, false)
	_reg_rows("bankit:", bank_items, GameNames.PLACE_BANK, true)
	_reg_rows("kstk:", bank_stacks, GameNames.PLACE_BANK, false)
	if sel_item != 0 and shell.item_by_id(sel_item).is_empty():
		sel_item = 0
	if sel_kind >= 0 and shell.stack_count(sel_place, sel_kind) == 0:
		sel_kind = -1
	_restore_selection()
	_update_bar()


func _reg_rows(prefix: String, list: ItemList, place: int, is_item: bool) -> void:
	for i in list.item_count:
		var id: String = prefix + str(int(list.get_item_metadata(i)))
		reg(id, list, func() -> void:
			list.select(i)
			_chose(place, list, i, is_item))


func _restore_selection() -> void:
	for l in [bag_items, bag_stacks, bank_items, bank_stacks]:
		(l as ItemList).deselect_all()
	var list: ItemList = null
	var want: int = -1
	if sel_item != 0:
		list = bag_items if sel_place == GameNames.PLACE_BAG else bank_items
		want = sel_item
	elif sel_kind >= 0:
		list = bag_stacks if sel_place == GameNames.PLACE_BAG else bank_stacks
		want = sel_kind
	if list != null:
		for i in list.item_count:
			if int(list.get_item_metadata(i)) == want:
				list.select(i)


func _chose(place: int, list: ItemList, i: int, is_item: bool) -> void:
	sel_place = place
	var id: int = int(list.get_item_metadata(i))
	sel_item = id if is_item else 0
	sel_kind = -1 if is_item else id
	for l in [bag_items, bag_stacks, bank_items, bank_stacks]:
		if l != list:
			(l as ItemList).deselect_all()
	_update_bar()


func _set_qty(q: int) -> void:
	qty = q
	_update_bar()


func _set_tab(t: int) -> void:
	tab_bar.current_tab = t


func _tab_changed(t: int) -> void:
	tab = t
	refill()


func _update_bar() -> void:
	var has_sel: bool = sel_item != 0 or sel_kind >= 0
	var dir: String = "DEPOSIT" if sel_place == GameNames.PLACE_BAG else "WITHDRAW"
	move_btn.text = dir if has_sel else "CHOOSE A THING"
	move_btn.disabled = not has_sel or busy
	for b in qty_btns:
		b.disabled = sel_kind < 0
	for i in qty_btns.size():
		qty_btns[i].button_pressed = qty == [1, 10, 0][i]
	if sel_item != 0:
		var it: Dictionary = shell.item_by_id(sel_item)
		info.text = GameNames.item_name(it) if not it.is_empty() else ""
		info.add_theme_color_override("font_color", GameNames.rarity_colour(int(it.get("rarity", 0))))
	else:
		info.text = ("%s: %s" % [GameNames.stack_name(sel_kind), "CHOOSE HOW MANY"]) if sel_kind >= 0 else "BAG ON THE LEFT, CHEST TAB %d ON THE RIGHT" % (tab + 1)
		info.add_theme_color_override("font_color", UiKit.BONE_DIM)
	coin_label.text = "%s COIN carried" % GameNames.commas(shell.coin())
	if tab_price > 0 and tabs_owned < tabs_max:
		buy_btn.text = "BUY TAB %d: %s COIN" % [tabs_owned + 1, GameNames.commas(tab_price)]
		buy_btn.disabled = busy
		tab_note.text = "YOU OWN %d OF %d TABS" % [tabs_owned, tabs_max]
	else:
		buy_btn.text = "EVERY TAB IS YOURS"
		buy_btn.disabled = true
		tab_note.text = "YOU OWN ALL %d TABS" % tabs_max


## Moves what is chosen to the other side. Returns the gateway's reply.
func move_selected() -> Dictionary:
	var hero: int = shell.hero_id()
	var deposit: bool = sel_place == GameNames.PLACE_BAG
	var req: Array = []
	var what: String = ""
	if sel_item != 0:
		req = GwWire.bank(deposit, hero, sel_item, 0, 0, tab)
		what = GameNames.item_name(shell.item_by_id(sel_item))
	elif sel_kind >= 0:
		var have: int = shell.stack_count(sel_place, sel_kind)
		var n: int = have if qty == 0 else mini(qty, have)
		if n <= 0:
			return {}
		req = GwWire.bank(deposit, hero, 0, sel_kind, n, tab)
		what = "%s %s" % [GameNames.commas(n), GameNames.stack_name(sel_kind)]
	else:
		return {}
	sel_item = 0
	var r: Dictionary = await do(req, ("%s: %s" % ["DEPOSITED" if deposit else "TAKEN OUT", what]))
	if is_instance_valid(self):
		if int(r["t"]) == GwWire.R_OK and sel_kind >= 0 and shell.stack_count(sel_place, sel_kind) == 0:
			sel_kind = -1
		refill()
	return r

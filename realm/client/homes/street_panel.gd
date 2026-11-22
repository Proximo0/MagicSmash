class_name StreetPanel
extends PanelBase
## A street of 24 plots: who lives where, what a plot costs to buy or rent a week, and the actions: buy, rent for
## one to four weeks, renew, give it up, visit. Buying and renting need her to stand in that street.

var street: int = 1
var selected: int = -1
var plots: Array[Dictionary] = []
var open_streets: int = 1
var mine: int = -1
var last_result: String = ""


func opened() -> void:
	title = "THE STREET"
	if int(shell.place[0]) == HomeMap.STREET:
		street = int(shell.place[1])
	await reload()


func reload() -> void:
	var s: Dictionary = await shell.link.call_req(HomeWire.with_u32(HomeWire.Q_STREET, shell.hero_id(), street))
	if int(s["t"]) == HomeWire.R_HOME and int(s.get("k", -1)) == HomeWire.K_STREET:
		plots = s["plots"]
		if int(shell.place[0]) == HomeMap.STREET and int(shell.place[1]) == street:
			shell.street_plots = plots
			if shell.base is TownScreen:
				(shell.base as TownScreen).stations = HomeMap.stations_for(shell.place, plots)
	var o: Dictionary = await shell.link.call_req(HomeWire.hero_only(HomeWire.Q_STREETS, shell.hero_id()))
	if int(o["t"]) == HomeWire.R_HOME and int(o.get("k", -1)) == HomeWire.K_STREETS:
		open_streets = int(o["open"])
		mine = int(o["mine"])


func _here() -> bool:
	return int(shell.place[0]) == HomeMap.STREET and int(shell.place[1]) == street


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y - 8
	UiKit.text(self, Vector2(x + 90, y + 2), "STREET %d OF %d" % [street, open_streets], 17, UiKit.BONE)
	button("prev", Rect2(x, y, 40, 28), "<", street > 1, false, 14)
	button("next", Rect2(x + 46, y, 40, 28), ">", street < open_streets, false, 14)
	UiKit.text(self, Vector2(inner.end.x, y + 4), "%s COIN" % GameNames.commas(shell.coin()), 13, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	var cw: float = 134.0
	for i in plots.size():
		var p: Dictionary = plots[i]
		var r := Rect2(x + (i % 6) * (cw + 5.0), y + 38 + (i / 6) * 66.0, cw, 62)
		var st: int = int(p["status"])
		var mine_here: bool = mine >= 0 and mine == HomeMap.plot_id(street, i)
		var fill: Color = Color(0.06, 0.055, 0.06) if st == 0 else Color(0.12, 0.08, 0.07)
		hit("plot:%d" % i, r)
		draw_rect(r, fill.lightened(0.06) if hover_id == "plot:%d" % i else fill)
		draw_rect(r, UiKit.GOLD if (i == selected or mine_here) else Color(UiKit.GOLD_DIM, 0.4), false, 2.0 if i == selected else 1.0)
		UiKit.text(self, r.position + Vector2(6, 3), "%d" % (i + 1), 12, UiKit.GOLD)
		UiKit.text(self, r.position + Vector2(cw - 6, 3), HomeMap.STATUS_NAMES[st] + (" (YOU)" if mine_here else ""), 10, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		if st == 0:
			UiKit.text(self, r.position + Vector2(6, 24), "%s" % GameNames.commas(int(p["buy"])), 12, UiKit.BONE)
			UiKit.text(self, r.position + Vector2(6, 42), "RENT %s / WEEK" % GameNames.commas(int(p["rent"])), 10, UiKit.BONE_DIM)
		else:
			UiKit.text(self, r.position + Vector2(6, 22), String(p["name"]).left(18) if not String(p["name"]).is_empty() else "A HOUSE", 12, UiKit.BONE)
			UiKit.text(self, r.position + Vector2(6, 40), String(p["owner"]).left(18) + "  " + HomeMap.RULE_NAMES[int(p["rule"])], 10, UiKit.BONE_DIM)
	_detail(Rect2(x, y + 38 + 4 * 66.0 + 4, inner.size.x, 90))


func _detail(r: Rect2) -> void:
	UiKit.text(self, r.position + Vector2(0, 0), last_result, 12, UiKit.GOLD)
	if selected < 0 or selected >= plots.size():
		UiKit.text(self, r.position + Vector2(0, 24), "CHOOSE A PLOT", 13, UiKit.BONE_DIM)
		return
	var p: Dictionary = plots[selected]
	var st: int = int(p["status"])
	var id: int = HomeMap.plot_id(street, selected)
	var is_mine: bool = mine == id
	var here: bool = _here()
	var y: float = r.position.y + 22
	if not here:
		button("walk", Rect2(r.position.x, y, 200, 30), "WALK TO THIS STREET", not busy, false, 13)
	if st == 0 and here:
		var can_buy: bool = mine < 0 and shell.coin() >= int(p["buy"]) and not busy
		button("buy", Rect2(r.position.x, y, 220, 30), "BUY  %s" % GameNames.commas(int(p["buy"])), can_buy, false, 13)
		var weeks: Array[int] = [1, 2, 4]
		for k in weeks.size():
			var cost: int = int(p["rent"]) * weeks[k]
			button("rent:%d" % weeks[k], Rect2(r.position.x + 230 + k * 100.0, y, 96, 30), "RENT %dW" % weeks[k], mine < 0 and shell.coin() >= cost and not busy, false, 12)
	if is_mine:
		if st == 2:
			button("renew", Rect2(r.position.x, y, 220, 30), "RENEW 1 WEEK  %s" % GameNames.commas(int(p["rent"])), shell.coin() >= int(p["rent"]) and not busy, false, 12)
		button("release", Rect2(r.position.x + 230, y, 160, 30), "GIVE IT UP", not busy, false, 12)
	if st != 0:
		button("visit", Rect2(r.end.x - 160, y, 160, 30), "KNOCK AND GO IN", not busy, false, 13)
	if st == 2 and int(p["until"]) > 0:
		UiKit.text(self, Vector2(r.position.x, y + 38), "RENT PAID TO DAY %d OF THE REALM" % (int(p["until"]) / 86400000), 10, UiKit.BONE_DIM)


func press_body(id: String) -> void:
	if id == "prev" or id == "next":
		street = clampi(street + (1 if id == "next" else -1), 1, open_streets)
		selected = -1
		await reload()
		return
	if id.begins_with("plot:"):
		selected = int(id.trim_prefix("plot:"))
		last_result = ""
		return
	var hero: int = shell.hero_id()
	var plot: int = maxi(selected, 0)
	var r: Dictionary = {}
	match id:
		"walk":
			busy = true
			await shell.go_place(HomeMap.STREET, street)
			if is_instance_valid(self):
				busy = false
			return
		"buy":
			r = await do(HomeWire.buy(hero, street, plot))
		"renew":
			r = await do(HomeWire.with_u8(HomeWire.Q_RENEW, hero, 1))
		"release":
			r = await do(HomeWire.hero_only(HomeWire.Q_RELEASE, hero))
		"visit":
			busy = true
			await shell.go_place(HomeMap.HOUSE, HomeMap.plot_id(street, plot))
			if is_instance_valid(self):
				busy = false
			return
		_:
			if id.begins_with("rent:"):
				r = await do(HomeWire.rent(hero, street, plot, int(id.trim_prefix("rent:"))))
	if int(r.get("t", 0)) == HomeWire.R_HOME:
		match int(r.get("k", -1)):
			HomeWire.K_PAID:
				last_result = "PAID %s COIN" % GameNames.commas(int(r["coin"]))
			HomeWire.K_OK:
				last_result = "DONE"
		await reload()

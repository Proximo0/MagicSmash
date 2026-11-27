class_name HeroListScreen
extends UiScreen
## The hero list as tarot cards: one card a hero, a card back for each free slot (click it to make a hero).
## Click a card to choose her; ENTER TOWN walks her in. A deleted hero can be raised again for a week.

const FREE_SLOTS: int = 3
const CARD_W: float = 190.0
const CARD_H: float = 300.0
const ROMAN: Array[String] = ["0", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
const TITLES: Array[String] = ["THE FOOL", "THE KNIGHT", "THE MAGUS", "THE HUNTRESS", "THE PRIESTESS", "THE PALADIN"]

var live: Array[Dictionary] = []
var gone: Array[Dictionary] = []
var _sure_until: float = 0.0
var busy: bool = false


func opened() -> void:
	_sort()
	shell.data_changed.connect(_sort)
	if live.size() > 0 and shell.hero.is_empty():
		shell.hero = live[0]


func _sort() -> void:
	live.clear()
	gone.clear()
	for h in shell.heroes:
		if bool(h["deleted"]):
			gone.append(h)
		else:
			live.append(h)


func _slots() -> int:
	return maxi(FREE_SLOTS, live.size() + 1) if live.size() < 5 else live.size()


func _card_rect(i: int, n: int) -> Rect2:
	var total: float = n * CARD_W + (n - 1) * 22.0
	return Rect2((UiKit.W - total) / 2.0 + i * (CARD_W + 22.0), 88.0, CARD_W, CARD_H)


func paint() -> void:
	UiKit.backdrop(self, time)
	UiKit.title(self, Vector2(UiKit.W / 2.0, 22), "YOUR HEROES", 28)
	var n: int = _slots()
	for i in n:
		var r: Rect2 = _card_rect(i, n)
		if i < live.size():
			_paint_hero(i, r, live[i])
		else:
			_paint_back(i, r)
	var chosen: bool = not shell.hero.is_empty() and not bool(shell.hero.get("deleted", false))
	button("enter", Rect2(UiKit.W / 2.0 - 110, 408, 220, 42), "ENTER TOWN", chosen and not busy, false, 18)
	if chosen and not busy:
		UiKit.glow(self, Rect2(UiKit.W / 2.0 - 110, 408, 220, 42), time)
	button("delete", Rect2(UiKit.W / 2.0 - 70, 458, 140, 30), "SURE?" if _sure_until > time else "DELETE", chosen, _sure_until > time, 13)
	button("back", Rect2(20, UiKit.H - 52, 120, 34), "LEAVE")
	if not gone.is_empty():
		var h: Dictionary = gone[0]
		button("restore", Rect2(UiKit.W - 280, UiKit.H - 52, 260, 34), "RAISE %s" % String(h["name"]), true, false, 13)
	UiKit.text(self, Vector2(UiKit.W - 12, 12), "SIGNED IN AS %s" % shell.dev_name, 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)


func _paint_hero(i: int, r: Rect2, h: Dictionary) -> void:
	var picked: bool = int(shell.hero.get("id", -1)) == int(h["id"])
	hit("hero:%d" % i, r)
	var up: float = -8.0 if (picked or hover_id == "hero:%d" % i) else 0.0
	r.position.y += up
	UiKit.frame(self, r, UiKit.GOLD if picked else UiKit.GOLD_DIM, Color(0.08, 0.06, 0.07, 1.0))
	UiKit.frame(self, r.grow(-9), Color(UiKit.GOLD_DIM, 0.5), Color(0.1, 0.04, 0.05, 1.0) if picked else Color(0.06, 0.05, 0.065, 1.0))
	var cls: int = int(h["class"])
	UiKit.text(self, r.position + Vector2(r.size.x / 2.0, 14), ROMAN[clampi(i + 1, 0, 10)], 16, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var pic := Rect2(r.position + Vector2(24, 40), Vector2(r.size.x - 48, 128))
	draw_rect(pic, Color(0.03, 0.025, 0.035))
	draw_arc(pic.get_center(), 54.0, 0.0, TAU, 40, Color(UiKit.GOLD_DIM, 0.6), 1.0)
	UiKit.rune(self, pic.position + Vector2(6, 6), i + cls, 12.0, UiKit.GOLD_DIM, 1.0)
	UiKit.rune(self, pic.end - Vector2(18, 18), i + cls + 3, 12.0, UiKit.GOLD_DIM, 1.0)
	UiArt.draw_hero(self, cls, int(h["race"]), pic.get_center() + Vector2(0, 4), 92.0, int(h["look"]))
	UiKit.text(self, r.position + Vector2(r.size.x / 2.0, 178), String(h["name"]), 20, UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(self, r.position + Vector2(r.size.x / 2.0, 204), "LEVEL %d %s" % [int(h["level"]), GameNames.class_name_of(cls)], 14, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var job: String = GameNames.job_name_of(int(h["job"]))
	var line: String = GameNames.race_name_of(int(h["race"])) + ("  " + job if job != "NONE" else "")
	UiKit.text(self, r.position + Vector2(r.size.x / 2.0, 224), line, 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	if int(h["unspent"]) > 0:
		UiKit.text(self, r.position + Vector2(r.size.x / 2.0, 244), "%d POINTS TO SPEND" % int(h["unspent"]), 12, UiKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(self, r.position + Vector2(r.size.x / 2.0, r.size.y - 26), TITLES[clampi(cls, 0, 5)], 12, UiKit.BLOOD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)


func _paint_back(i: int, r: Rect2) -> void:
	var id: String = "new"
	hit(id, r)
	var hot: bool = hover_id == id and i == live.size()
	UiKit.frame(self, r, UiKit.GOLD if hot else UiKit.GOLD_DIM, Color(0.07, 0.03, 0.04, 1.0))
	UiKit.frame(self, r.grow(-9), Color(UiKit.GOLD_DIM, 0.4), Color(0.05, 0.03, 0.04, 1.0))
	var c: Vector2 = r.get_center()
	for k in 3:
		draw_arc(c, 24.0 + k * 20.0, 0.0, TAU, 40, Color(UiKit.GOLD_DIM, 0.5 - k * 0.12), 1.0)
	for k in 12:
		var a: float = float(k) / 12.0 * TAU
		UiKit.rune(self, c + Vector2.from_angle(a) * 52.0 - Vector2(4, 6), k, 8.0, Color(UiKit.GOLD_DIM, 0.7), 1.0)
	if i == live.size():
		UiKit.text(self, c + Vector2(0, -16), "+", 36, UiKit.GOLD if hot else UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.text(self, c + Vector2(0, 100), "A NEW HERO", 14, UiKit.GOLD if hot else UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		UiKit.text(self, c + Vector2(0, 100), "EMPTY", 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)


func on_press(id: String) -> void:
	if id.begins_with("hero:"):
		shell.hero = live[int(id.trim_prefix("hero:"))]
		_sure_until = 0.0
		return
	match id:
		"new":
			shell.show_base(HeroBuilderScreen.new(), "hero_builder")
		"enter":
			busy = true
			var err: String = await shell.enter_town()
			if not err.is_empty() and is_instance_valid(self):
				busy = false
				say(err, true)
		"delete":
			if _sure_until > time:
				_sure_until = 0.0
				var r: Dictionary = await shell.act(GwWire.hero_only(GwWire.T_DELETE_HERO, shell.hero_id()), "She is gone. For a week, you can raise her.")
				if int(r["t"]) == GwWire.R_OK:
					shell.hero = {}
					await shell.refresh_heroes()
					_sort()
					if not live.is_empty():
						shell.hero = live[0]
			else:
				_sure_until = time + 3.0
		"restore":
			var r2: Dictionary = await shell.act(GwWire.hero_only(GwWire.T_UNDELETE_HERO, int(gone[0]["id"])), "RAISED")
			if int(r2["t"]) == GwWire.R_OK:
				await shell.refresh_heroes()
				_sort()
		"back":
			shell.logout()


func on_key(e: InputEventKey) -> bool:
	if e.keycode == KEY_ESCAPE:
		shell.logout()
		return true
	if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER:
		on_press("enter" if not shell.hero.is_empty() else "new")
		return true
	if e.keycode == KEY_LEFT or e.keycode == KEY_RIGHT:
		var idx: int = -1
		for i in live.size():
			if int(live[i]["id"]) == shell.hero_id():
				idx = i
		if not live.is_empty():
			shell.hero = live[clampi(idx + (1 if e.keycode == KEY_RIGHT else -1), 0, live.size() - 1)]
		return true
	return false

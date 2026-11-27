class_name SheetPanel
extends PanelBase
## The hero sheet: who she is, her six stats (points spent, her race's gift, what her gear and its sockets add),
## her skills and her deck and belt at a glance. Points are spent at the trainer.

func opened() -> void:
	title = "THE HERO SHEET"


## Points her gear gives per stat: each line raised 3% a plus, and what sits in the sockets.
static func gear_points(items: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0, 0, 0]
	for it in items:
		var plus: int = int(it.get("plus", 0))
		for l in it["lines"]:
			out[int(l[0])] += int(l[1]) * (100 + 3 * plus) / 100
		for k in it.get("socketed", []):
			if int(k) != 0:
				var sp: Array = GameNames.socket_points(int(k))
				out[int(sp[0])] += int(sp[1])
	return out


func paint_body(inner: Rect2) -> void:
	var h: Dictionary = shell.hero
	var x: float = inner.position.x
	var y: float = inner.position.y - 6
	var cls: int = int(h.get("class", 1))
	var race: int = int(h.get("race", 0))
	var c0 := Vector2(x + 90, y + 90)
	draw_arc(c0 + Vector2(0, 40), 60.0, 0.0, TAU, 40, Color(UiKit.GOLD_DIM, 0.6), 1.0)
	UiArt.draw_hero(self, cls, race, c0, 110.0, int(h.get("look", 0)))
	UiKit.text(self, Vector2(x + 90, y + 160), String(h.get("name", "")), 20, UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(self, Vector2(x + 90, y + 188), "LEVEL %d %s" % [int(h.get("level", 1)), GameNames.class_name_of(cls)], 14, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var job: String = GameNames.job_name_of(int(h.get("job", GameNames.NO_JOB)))
	UiKit.text(self, Vector2(x + 90, y + 208), GameNames.race_name_of(race) + ("  " + job if job != "NONE" else ""), 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(self, Vector2(x + 90, y + 228), "%s XP" % GameNames.commas(int(h.get("xp", 0))), 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(self, Vector2(x + 90, y + 252), "%d POINTS TO SPEND" % int(h.get("unspent", 0)), 12, UiKit.GOOD if int(h.get("unspent", 0)) > 0 else UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	# Stats.
	var sx: float = x + 210
	UiKit.text(self, Vector2(sx, y), "STAT", 11, UiKit.BONE_DIM)
	for col in [["SPENT", 150], ["RACE", 210], ["GEAR", 270], ["TOTAL", 340]]:
		UiKit.text(self, Vector2(sx + int(col[1]) + 40, y), String(col[0]), 11, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	var gear: Array[int] = gear_points(shell.items_at(GameNames.PLACE_WORN))
	var stats: Array = h.get("stats", [0, 0, 0, 0, 0, 0])
	for i in 6:
		var ry: float = y + 22 + i * 34.0
		var spent: int = int(stats[i])
		var bonus: int = int((GameNames.RACE_BONUS[race] as Array)[i])
		UiKit.text(self, Vector2(sx, ry), GameNames.STATS[i], 15, UiKit.BONE)
		UiKit.text(self, Vector2(sx, ry + 17), GameNames.STAT_NOTES[i], 10, UiKit.BONE_DIM)
		for col in [[spent, 150], [bonus, 210], [gear[i], 270]]:
			UiKit.text(self, Vector2(sx + int(col[1]) + 40, ry + 2), str(int(col[0])), 14, UiKit.BONE, HORIZONTAL_ALIGNMENT_RIGHT)
		UiKit.text(self, Vector2(sx + 380, ry), str(spent + bonus + gear[i]), 18, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	# Skills, deck and belt.
	var kx: float = x + 620
	UiKit.text(self, Vector2(kx, y), "SKILLS", 12, UiKit.GOLD)
	var skills: Array = GameNames.class_skills(cls, int(h.get("job", GameNames.NO_JOB)), int(h.get("level", 1)))
	for i in skills.size():
		var s: Array = skills[i]
		UiKit.text(self, Vector2(kx, y + 20 + i * 20.0), "%s  %s" % [String(s[0]), ("RANK %d" % int(s[2])) if int(s[2]) > 0 else "LEVEL %d" % int(s[1])], 12, UiKit.BONE if int(s[2]) > 0 else Color(0.45, 0.4, 0.38))
	var dy: float = y + 20 + skills.size() * 20.0 + 16
	UiKit.text(self, Vector2(kx, dy), "DECK  %d CARDS" % (h.get("deck", []) as Array).size(), 12, UiKit.GOLD)
	UiKit.text(self, Vector2(kx, dy + 26), "BELT", 12, UiKit.GOLD)
	var belt: Array = h.get("belt", [0, 0, 0])
	for i in 3:
		UiKit.text(self, Vector2(kx, dy + 46 + i * 18.0), GameNames.stack_name(int(belt[i])) if int(belt[i]) != 0 else "EMPTY", 12, UiKit.BONE if int(belt[i]) != 0 else Color(0.45, 0.4, 0.38))
	UiKit.text(self, Vector2(x, inner.end.y - 14), "Points are spent at the trainer; gear is worn from the bag.", 11, UiKit.BONE_DIM)
	button("bag", Rect2(inner.end.x - 110, inner.end.y - 34, 100, 30), "THE BAG", true, false, 12)


func press_body(id: String) -> void:
	if id == "bag":
		close()
		var t: Node = shell.base
		if t is TownScreen:
			(t as TownScreen).open_bag()

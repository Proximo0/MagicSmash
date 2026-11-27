class_name TrainerPanel
extends PanelBase
## The trainer: her skills (skill 1 at level 10, skill 2 at 25, the ultimate at 40; each rank adds 15%, one rank
## every ten levels), her stat points (one a level) and, at level 40, the choice of the class's two jobs: after
## THE CLASS TRIAL (its own station) and for coin (the gateway's price, `job_change_cost`, shown before the click).

var last_result: String = ""


func opened() -> void:
	title = "THE TRAINER"
	shell.refresh_trial()


func paint_body(inner: Rect2) -> void:
	var h: Dictionary = shell.hero
	var x: float = inner.position.x
	var y: float = inner.position.y - 6
	var level: int = int(h.get("level", 1))
	var cls: int = int(h.get("class", 1))
	var job: int = int(h.get("job", GameNames.NO_JOB))
	UiKit.text(self, Vector2(x, y), "%s  LEVEL %d %s" % [String(h.get("name", "")), level, GameNames.class_name_of(cls)], 17, UiKit.BONE)
	UiKit.text(self, Vector2(x, y + 24), "%s XP earned" % GameNames.commas(int(h.get("xp", 0))), 12, UiKit.BONE_DIM)
	# Skills.
	UiKit.text(self, Vector2(x, y + 56), "SKILLS", 13, UiKit.GOLD)
	var skills: Array = GameNames.class_skills(cls, job, level)
	for i in skills.size():
		var s: Array = skills[i]
		var ry: float = y + 78 + i * 52.0
		var r := Rect2(x, ry, 400, 46)
		draw_rect(r, Color(0.07, 0.058, 0.066))
		draw_rect(r, Color(UiKit.GOLD_DIM, 0.4), false, 1.0)
		var rank: int = int(s[2])
		UiKit.text(self, r.position + Vector2(10, 4), String(s[0]), 15, UiKit.BONE if rank > 0 else Color(0.4, 0.38, 0.34))
		UiKit.text(self, r.position + Vector2(10, 26), String(s[3]), 11, UiKit.BONE_DIM)
		if rank > 0:
			UiKit.text(self, Vector2(r.end.x - 10, r.position.y + 6), "RANK %d" % rank, 14, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
			UiKit.text(self, Vector2(r.end.x - 10, r.position.y + 26), "+%d%% power" % ((rank - 1) * 15), 11, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			UiKit.text(self, Vector2(r.end.x - 10, r.position.y + 14), "AT LEVEL %d" % int(s[1]), 13, Color(0.5, 0.35, 0.35), HORIZONTAL_ALIGNMENT_RIGHT)
	# The job.
	var jy: float = y + 78 + skills.size() * 52.0 + 8
	if cls != 0 and job == GameNames.NO_JOB:
		var t: Dictionary = shell.trial
		var passed: bool = bool(t.get("passed", false))
		var price: int = int(t.get("job_price", 0))
		var need: String = "JOB (at level %d, for good)" % GameNames.JOB_LEVEL
		if not t.is_empty():
			need = "JOB: LEVEL %d, %s, %s COIN" % [GameNames.JOB_LEVEL, "THE CLASS TRIAL PASSED" if passed else "AFTER THE CLASS TRIAL", GameNames.commas(price)]
		UiKit.text(self, Vector2(x, jy), need, 13, UiKit.GOLD)
		var jobs: Array[int] = GameNames.class_jobs(cls)
		for i in jobs.size():
			var jr := Rect2(x + i * 202.0, jy + 22, 196, 62)
			# The trainer says in words why not (the trial, the coin): the button only waits for the level.
			var can: bool = level >= GameNames.JOB_LEVEL and not busy
			button("job:%d" % jobs[i], jr, GameNames.JOBS[jobs[i]], can, false, 14)
			UiKit.paragraph(self, jr.position + Vector2(4, 64), GameNames.JOB_NOTES[jobs[i]], 190.0, 10, UiKit.BONE_DIM)
	# Points.
	var px: float = x + 450
	UiKit.text(self, Vector2(px, y + 56), "STAT POINTS", 13, UiKit.GOLD)
	var unspent: int = int(h.get("unspent", 0))
	UiKit.text(self, Vector2(inner.end.x, y + 56), "%d TO SPEND" % unspent, 13, UiKit.GOOD if unspent > 0 else UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	var stats: Array = h.get("stats", [0, 0, 0, 0, 0, 0])
	var race: int = int(h.get("race", 0))
	for i in 6:
		var ry: float = y + 78 + i * 52.0
		var spent: int = int(stats[i])
		var bonus: int = int((GameNames.RACE_BONUS[race] as Array)[i])
		UiKit.text(self, Vector2(px, ry + 2), GameNames.STATS[i], 15, UiKit.BONE)
		UiKit.text(self, Vector2(px, ry + 24), GameNames.STAT_NOTES[i], 11, UiKit.BONE_DIM)
		UiKit.text(self, Vector2(px + 200, ry + 8), "%d" % (spent + bonus), 18, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		UiKit.text(self, Vector2(px + 206, ry + 12), "(%d + race %d)" % [spent, bonus], 10, UiKit.BONE_DIM)
		button("pt:%d:1" % i, Rect2(px + 290, ry + 4, 46, 30), "+1", unspent >= 1 and not busy, false, 13)
		button("pt:%d:5" % i, Rect2(px + 342, ry + 4, 46, 30), "+5", unspent >= 5 and not busy, false, 13)
	UiKit.text(self, Vector2(x, inner.end.y - 14), last_result, 12, UiKit.GOLD)


func press_body(id: String) -> void:
	if id.begins_with("pt:"):
		var p: PackedStringArray = id.split(":")
		var r: Dictionary = await do(GwWire.spend_point(shell.hero_id(), int(p[1]), int(p[2])))
		if int(r["t"]) == GwWire.R_OK:
			last_result = "+%s %s" % [p[2], GameNames.STATS[int(p[1])]]
	elif id.begins_with("job:"):
		var j: int = int(id.trim_prefix("job:"))
		var r2: Dictionary = await do(GwWire.choose_job(shell.hero_id(), j), "SHE IS NOW A %s" % GameNames.JOBS[j])
		if int(r2["t"]) == GwWire.R_SMITH:
			last_result = "A %s, FOR GOOD: %s COIN TO THE TRAINER" % [GameNames.JOBS[j], GameNames.commas(int(r2["amount"]))]

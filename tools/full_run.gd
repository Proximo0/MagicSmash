extends SceneTree
## Bots play one whole run in the pure simulation, start to results screen, and print how it went: a line per
## minute (lives, levels, enemies), the Archlich's fight and how the run ended. For balancing the run's length
## and the final boss; too slow for check_all.
## Usage: godot --headless --path . -s tools/full_run.gd -- [--wizards=4] [--seed=7] [--persona=casual] [--tune=field:value,...]
## [--seal=N] [--reading=<key>]

const DT: float = 1.0 / 60.0
const MAX_MINUTES: float = 30.0


func _init() -> void:
	var wizards: int = 4
	var seed_value: int = 7
	var tune := Tuning.new()
	var persona: int = SmashBot.CASUAL
	var seal: int = 0
	var reading: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--wizards="):
			wizards = clampi(int(arg.get_slice("=", 1)), 1, 4)
		elif arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
		elif arg.begins_with("--persona="):
			persona = SmashBot.persona_from_name(arg.get_slice("=", 1))
			if persona < 0:
				push_error("unknown persona " + arg)
				quit(2)
				return
		elif arg.begins_with("--seal="):
			seal = int(arg.get_slice("=", 1))
		elif arg.begins_with("--reading="):
			reading = arg.get_slice("=", 1)
			if Readings.index_of(reading) < 0:
				push_error("unknown reading " + arg)
				quit(2)
				return
		elif arg.begins_with("--tune="):
			for pair: String in arg.get_slice("=", 1).split(","):
				if not tune.set_value(pair.get_slice(":", 0), float(pair.get_slice(":", 1))):
					push_error("unknown tuning field " + pair)
	var slots: Array = range(wizards)
	var w := World.new(slots, seed_value, tune)
	w.apply_seal(seal)
	w.apply_reading(reading)
	if reading != "":
		print("reading %s: hearts %s" % [Readings.ROWS[Readings.index_of(reading)][Readings.NAME], " ".join(w.players.values().map(func(p: World.Player) -> String: return str(p.max_hp)))])
	var bots: Dictionary = {}
	for s: int in slots:
		bots[s] = SmashBot.new(seed_value + s, persona)
	var minute: int = 0
	var final_at: float = -1.0
	var final_hp: float = 0.0
	var won_at: float = -1.0
	while w.phase != World.PH_GAMEOVER and w.wave_time < MAX_MINUTES * 60.0:
		var inputs: Dictionary = {}
		for s: int in slots:
			inputs[s] = (bots[s] as SmashBot).decide_in_world(w, s)
		w.step(DT, inputs)
		for ev: Array in w.take_events():
			if ev[0] == World.EV_VICTORY:
				won_at = w.wave_time
		if final_at < 0.0 and w.boss != null and w.boss.final:
			final_at = w.wave_time
			final_hp = w.boss.maxhp
		if int(w.wave_time / 60.0) > minute:
			minute = int(w.wave_time / 60.0)
			print("%2d:00 %s enemies=%d boss=%s" % [minute, _party(w), w.enemies.size(), _boss(w)])
	var how: String = "WON at %s (Archlich %.0f hp, came %s, fight %.0f s)" % [_clock(won_at), final_hp, _clock(final_at), won_at - final_at] if w.won \
		else "LOST at %s" % _clock(w.wave_time)
	if w.phase != World.PH_GAMEOVER:
		how = "UNFINISHED at %s, Archlich %s" % [_clock(w.wave_time), _boss(w)]
	print("FULL_RUN wizards=%d seed=%d persona=%s %s score=%d" % [wizards, seed_value, SmashBot.persona_name(persona), how,
		w.total_score()])
	quit()


func _party(w: World) -> String:
	var out: PackedStringArray = []
	for p: World.Player in w.players.values():
		out.append("P%d lv%d %dx%dhp" % [p.slot + 1, p.level, p.lives, p.hp])
	return " ".join(out)


func _boss(w: World) -> String:
	if w.boss == null:
		return "-"
	return "%s %.0f/%.0f" % ["ARCH" if w.boss.final else "lich", w.boss.hp, w.boss.maxhp]


func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]

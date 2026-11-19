extends RefCounted
## A golden run: four bots play one seed for a fixed stretch of game time, and the state hash is printed every
## MARK_SECONDS. Two builds that print the same line play the same game; if they differ, the first mark that differs
## says when they parted ways. The final hash also covers the run's record, awards and achievements.
## Run through tools/golden.sh, or alone:
##   godot --headless --path . -s tools/tool.gd -- golden_run [--seed=7] [--seconds=90]

const DT: float = 1.0 / 60.0
const MARK_SECONDS: float = 15.0


func run(args: PackedStringArray) -> int:
	var seed_value: int = 7
	var seconds: float = 90.0
	for a: String in args:
		if a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
	var slots: Array = [0, 1, 2, 3]
	var w := World.new(slots, seed_value)
	var bots: Dictionary = {}
	for s: int in slots:
		bots[s] = SmashBot.new(seed_value + s)
	var marks: PackedStringArray = []
	var next_mark: float = MARK_SECONDS
	var steps: int = 0
	# The step limit ends a run whose clock has stopped (a pick nobody takes), so the tool cannot hang.
	while w.phase != World.PH_GAMEOVER and w.wave_time < seconds and steps < int(seconds / DT) * 3:
		var inputs: Dictionary = {}
		for s: int in bots:
			var inp: PackedFloat32Array = (bots[s] as SmashBot).decide_in_world(w, s)
			var p: World.Player = w.players[s]
			if not p.choices.is_empty():
				inp = SmashBot.with_pick(inp, p.choices, p.offer)
			inputs[s] = inp
		w.step(DT, inputs)
		w.take_events()
		steps += 1
		if w.wave_time >= next_mark:
			marks.append(str(w.state_hash()))
			next_mark += MARK_SECONDS
	var final: int = hash([w.state_hash(), w.total_score(), w.record.to_dict(), w.record.awards(), w.record.top_moments(),
		Achievements.earned(w.record, w.won, w.wave_time)])
	print("GOLDEN seed=%d seconds=%d final=%d marks=%s" % [seed_value, int(seconds), final, ",".join(marks)])
	return 0

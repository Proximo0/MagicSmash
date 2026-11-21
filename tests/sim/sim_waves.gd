extends "res://tests/sim/sim_base.gd"
## Bot wizards play the pure simulation for a few minutes: waves must keep advancing and the run must be
## deterministic. Pure logic, so it runs far faster than real time.

const SEED: int = 7
const MINUTES: float = 4.0
const MIN_WAVE: int = 3
## The party should level up this many times in the run, and bots take their cards at once (the world never
## waits for them, so a bot sitting on cards would only be a bot playing without its upgrades).
const MIN_LEVEL: int = 5
const MAX_HOLD_TICKS: int = 2


func _play(slots: Array, ticks: int) -> Dictionary:
	var w := World.new(slots, SEED)
	var bots: Dictionary = {}
	for s: int in slots:
		bots[s] = SmashBot.new(SEED + s)
	var peak: int = 0
	var streak: int = 0
	var longest: int = 0
	var bets: int = 0
	var stalls: int = 0 # ticks on which the world's time did not advance
	var t0: int = Time.get_ticks_usec()
	for _i: int in range(ticks):
		var inputs: Dictionary = {}
		for s: int in slots:
			inputs[s] = (bots[s] as SmashBot).decide_in_world(w, s)
		var before: float = w.time
		w.step(DT, inputs)
		if w.time <= before:
			stalls += 1
		for ev: Array in w.take_events():
			if ev[0] == World.EV_SHRINE:
				bets += 1
		peak = maxi(peak, w.enemies.size())
		streak = streak + 1 if w.is_picking() else 0
		longest = maxi(longest, streak)
	var us: float = float(Time.get_ticks_usec() - t0) / ticks
	var lowest: int = w.party_level # the party levels together; every wizard's level follows it
	for p: World.Player in w.players.values():
		lowest = mini(lowest, p.level)
	return {"lowest_level": lowest, "hold_ticks": longest, "stalls": stalls, "wave": w.wave, "score": w.total_score(), "hash": w.state_hash(), "peak": peak, "us": us,
		"over": w.phase == World.PH_GAMEOVER, "bets": bets}


func run() -> Array:
	var ticks: int = int(MINUTES * 60.0 / DT)
	var a: Dictionary = _play([0, 1], ticks)
	var b: Dictionary = _play([0, 1], ticks)
	var four: Dictionary = _play([0, 1, 2, 3], ticks)
	return [
		row("waves_advance_2p", a.wave >= MIN_WAVE or a.over,
			"wave=%d score=%d over=%s" % [a.wave, a.score, a.over]),
		row("deterministic_2p", a.hash == b.hash, "hash=%d" % a.hash),
		row("waves_advance_4p", four.wave >= MIN_WAVE or four.over,
			"wave=%d score=%d over=%s" % [four.wave, four.score, four.over]),
		row("levels_up_4p", four.lowest_level >= MIN_LEVEL,
			"lowest_level=%d (need %d)" % [four.lowest_level, MIN_LEVEL]),
		row("bots_take_cards_4p", four.hold_ticks <= MAX_HOLD_TICKS,
			"longest_hold_ticks=%d (max %d)" % [four.hold_ticks, MAX_HOLD_TICKS]),
		row("world_never_waits_4p", four.stalls == 0 and a.stalls == 0,
			"ticks_without_time 2p=%d 4p=%d" % [a.stalls, four.stalls]),
		row("shrines_used_4p", four.bets >= 1, "bets=%d (bots pay shrines they can afford)" % four.bets),
		row("step_cost_4p", null, "peak_enemies=%d us_per_step=%.0f" % [four.peak, four.us]),
	]

extends "res://tests/sim/sim_base.gd"
## The horde at its peak: four bot wizards fight a full arena (Tuning.enemy_cap enemies, refilled by the horde)
## at minute 12, and World.step must stay inside its share of a 60 fps frame. Also reports when a 2-bot team
## first loses a life, which is the number balance work moves (bots dodge well, so treat it as a floor).

const SEED: int = 21
## Ticks measured at the peak, after a short settle.
const PEAK_TICKS: int = 600
const SETTLE_TICKS: int = 60
## World.step's budget, microseconds of CPU time: a quarter of a 16.7 ms frame leaves room for drawing and the network.
## CPU time, not a stopwatch: a stopwatch also counts the time other processes hold the cores, so check_all failed
## this row 4 runs in 6 with no code change. Measured on one 4-core machine: alone 3.2-3.8 ms either way; beside
## 8 busy processes 7.9-8.5 ms by the stopwatch and 3.5-3.8 ms of CPU time.
const STEP_BUDGET_US: float = 4000.0
## tools/check_all.sh sets SIM_BUDGET_SCALE=2: beside its other Godot processes even CPU time rose to 5.1 ms (shared
## caches), so there only a gross regression fails. CI's sims-horde row runs alone and holds the real budget.
static func _budget_us() -> float:
	var scale: float = OS.get_environment("SIM_BUDGET_SCALE").to_float()
	return STEP_BUDGET_US * (scale if scale > 0.0 else 1.0)


## Survival probe: bots play until game over or this many minutes.
const SURVIVE_MINUTES: float = 8.0


func _bots(slots: Array) -> Dictionary:
	var bots: Dictionary = {}
	for s: int in slots:
		bots[s] = SmashBot.new(SEED + s)
	return bots


func _inputs(w: World, bots: Dictionary) -> Dictionary:
	var inputs: Dictionary = {}
	for s: int in bots:
		var inp: PackedFloat32Array = (bots[s] as SmashBot).decide_in_world(w, s)
		var p: World.Player = w.players[s]
		if not p.choices.is_empty():
			inp = SmashBot.with_pick(inp, p.choices, p.offer)
		inputs[s] = inp
	return inputs


func _peak() -> Dictionary:
	var slots: Array = [0, 1, 2, 3]
	# Enemies that cannot die keep the arena full, so the cost measured is the cost at the cap.
	var t := Tuning.new()
	t.enemy_hp_per_min = 50.0 # past the tuning range on purpose
	var w := World.new(slots, SEED, t)
	w.phase = World.PH_FIGHT
	w.wave = 12
	w.wave_time = 11.0 * 60.0
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i: int in range(int(w.tune.enemy_cap)):
		var at := Vector2(rng.randf_range(G.ARENA.position.x + 20, G.ARENA.end.x - 20),
			rng.randf_range(G.ARENA.position.y + 20, G.ARENA.end.y - 20))
		w.spawn_enemy([World.GOBLIN, World.BAT, World.SLIME, World.SKELETON][i % 4], 0, at)
	for p: World.Player in w.players.values():
		p.invuln = 99999.0
		for sp: int in range(Spells.COUNT):
			p.upgrades[Upgrades.weapon_entry(sp)] = 3
	var bots := _bots(slots)
	for _i: int in range(SETTLE_TICKS):
		w.step(DT, _inputs(w, bots))
	var c0: int = _cpu_usec()
	var t0: int = Time.get_ticks_usec()
	var low: int = 1 << 30
	for _i: int in range(PEAK_TICKS):
		w.step(DT, _inputs(w, bots))
		w.take_events()
		low = mini(low, w.enemies.size())
	var wall: float = float(Time.get_ticks_usec() - t0) / PEAK_TICKS
	var c1: int = _cpu_usec()
	var by_cpu: bool = c0 >= 0 and c1 >= 0
	return {"us": float(c1 - c0) / PEAK_TICKS if by_cpu else wall, "wall": wall, "by_cpu": by_cpu, "low": low}


## CPU time this process has used so far, microseconds, or -1 where the OS does not say (anything but Linux; the
## budget then falls back to the stopwatch). From /proc/self/stat: fields 14 and 15 are user and system time in
## clock ticks of 10 ms, so over the 10 s measured here the reading is good to about 0.1%.
static func _cpu_usec() -> int:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return -1
	# The process name (field 2, in brackets) may hold spaces, so count fields from the bracket that ends it.
	var tail: PackedStringArray = f.get_line().rsplit(") ", true, 1)
	if tail.size() < 2:
		return -1
	var fields: PackedStringArray = tail[1].split(" ")
	if fields.size() < 13:
		return -1
	return (int(fields[11]) + int(fields[12])) * 10000


func _survive(slots: Array) -> Dictionary:
	var w := World.new(slots, SEED)
	var bots := _bots(slots)
	var lives_lost_at: float = -1.0
	var start_lives: int = 3 * slots.size()
	for _i: int in range(int(SURVIVE_MINUTES * 60.0 / DT)):
		w.step(DT, _inputs(w, bots))
		w.take_events()
		if lives_lost_at < 0.0:
			var lives: int = 0
			for p: World.Player in w.players.values():
				lives += p.lives
			if lives < start_lives:
				lives_lost_at = w.wave_time
		if w.phase == World.PH_GAMEOVER:
			break
	return {"t": w.wave_time, "first_loss": lives_lost_at, "over": w.phase == World.PH_GAMEOVER}


func run() -> Array:
	var peak := _peak()
	var cap: int = int(Tuning.shared().enemy_cap)
	var rows: Array = [
		row("horde_peak_cost_4p", peak.us <= _budget_us() and peak.low >= cap / 2,
			"us_per_step=%.0f %s (budget %.0f, stopwatch %.0f) enemies>=%d of cap %d" % [
				peak.us, "cpu" if peak.by_cpu else "stopwatch", _budget_us(), peak.wall, peak.low, cap]),
	]
	for n: int in [2]:
		var slots: Array = range(n)
		var s := _survive(slots)
		rows.append(row("survival_%dp" % n, null, "survived=%s first_life_lost=%s over=%s" % [
			_sim_clock(s.t), _sim_clock(s.first_loss) if s.first_loss >= 0.0 else "never", s.over]))
	return rows


static func _sim_clock(secs: float) -> String:
	var t: int = int(secs)
	return "%d:%02d" % [t / 60, t % 60]

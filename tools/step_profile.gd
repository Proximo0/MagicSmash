extends RefCounted
## Where a World.step goes at the enemy cap: four bot wizards among Tuning.enemy_cap enemies that cannot die (the
## horde sim's peak), each phase of the step timed apart, one line per loadout. Every wizard holds the loadout's
## spells at the top level, evolved where they can be.
##   godot --headless --path . -s tools/tool.gd -- step_profile [--sets=4/1,2,4/6,1,2,4] [--ticks=600]
## --sets: loadouts split by "/", each a list of World.SP_* numbers (default: each spell alone, then four legal
## four-spell loadouts). Columns are microseconds per step by the stopwatch, so run it on an idle box and read the
## lowest of a few runs. `hash` is the world's state hash after the run: an exact optimisation leaves it as it was.
## It repeats World.step's body: keep the two in step when the order of a step changes.

const SEED: int = 21
const DT: float = 1.0 / 60.0
const SETTLE: int = 60
const NAMES: Array = ["bots", "pre", "grid", "players", "sep", "enemies", "hazards", "shots", "runes", "bursts",
	"eshots", "pickups", "filter"]
const DEFAULT_SETS: Array = [[0], [1], [2], [3], [4], [5], [6], [7], [8], [1, 2, 3, 4], [6, 1, 2, 4], [7, 1, 2, 4],
	[4, 5, 0, 2]]


func run(args: PackedStringArray) -> int:
	var sets: Array = DEFAULT_SETS
	var ticks: int = 600
	for a: String in args:
		if a.begins_with("--sets="):
			sets = []
			for part: String in a.trim_prefix("--sets=").split("/"):
				var one: Array = []
				for x: String in part.split(","):
					one.append(int(x))
				sets.append(one)
		elif a.begins_with("--ticks="):
			ticks = maxi(1, int(a.trim_prefix("--ticks=")))
	for loadout: Array in sets:
		_profile(loadout, ticks)
	return 0


func _profile(loadout: Array, ticks: int) -> void:
	var slots: Array = [0, 1, 2, 3]
	var t := Tuning.new()
	t.enemy_hp_per_min = 50.0 # past the tuning range on purpose: nothing dies, the arena stays full
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
	var bots: Dictionary = {}
	for p: World.Player in w.players.values():
		p.invuln = 99999.0
		p.upgrades.clear()
		for sp: int in loadout:
			p.upgrades[Upgrades.weapon_entry(sp)] = Spells.MAX_LEVEL
			if Spells.has_evolution(sp):
				p.upgrades[Upgrades.evo_entry(sp)] = 1
		WorldCasting._refresh_spell(w, p)
		bots[p.slot] = SmashBot.new(SEED + p.slot)
	var acc: Array[int] = []
	acc.resize(NAMES.size())
	acc.fill(0)
	var shots_sum: int = 0
	var runes_sum: int = 0
	var hits: int = 0
	for i: int in range(SETTLE + ticks):
		var on: bool = i >= SETTLE
		var k: int = 0
		var a: int = Time.get_ticks_usec()
		var inputs: Dictionary = {}
		for s: int in bots:
			var inp: PackedFloat32Array = (bots[s] as SmashBot).decide_in_world(w, s)
			var p: World.Player = w.players[s]
			if not p.choices.is_empty():
				inp = SmashBot.with_pick(inp, p.choices, p.offer)
			inputs[s] = inp
		a = _lap(acc, k, a, on)
		k += 1
		inputs = WorldApprentices.with_inputs(w, inputs)
		WorldLevels._update_levelups(w, inputs)
		w.time += DT
		w._tick += 1
		w._fight(DT)
		a = _lap(acc, k, a, on)
		k += 1
		w._build_grid()
		w._plist.assign(w.players.values())
		a = _lap(acc, k, a, on)
		k += 1
		for p: World.Player in w.players.values():
			WorldPlayers._update_player(w, p, DT, inputs.get(p.slot, PackedFloat32Array()))
		a = _lap(acc, k, a, on)
		k += 1
		WorldEnemies._sep_fill(w)
		a = _lap(acc, k, a, on)
		k += 1
		for e: World.Enemy in w.enemies:
			if not e.dead:
				WorldEnemies._update_enemy(w, e, DT)
		a = _lap(acc, k, a, on)
		k += 1
		WorldHazards._update_hazards(w, DT)
		a = _lap(acc, k, a, on)
		k += 1
		WorldCastBolts._update_shots(w, DT)
		a = _lap(acc, k, a, on)
		k += 1
		WorldCastCircles._update_runes(w, DT)
		a = _lap(acc, k, a, on)
		k += 1
		WorldCasting._update_bursts(w)
		a = _lap(acc, k, a, on)
		k += 1
		WorldEnemies._update_eshots(w, DT)
		a = _lap(acc, k, a, on)
		k += 1
		WorldDrops._update_pickups(w, DT)
		WorldDrops._update_urns(w)
		a = _lap(acc, k, a, on)
		k += 1
		w.enemies = w.enemies.filter(func(e: World.Enemy) -> bool: return not e.dead)
		w.shots = w.shots.filter(func(s: World.Shot) -> bool: return not s.dead)
		w.runes = w.runes.filter(func(c: World.Rune) -> bool: return c.age < c.life)
		w.eshots = w.eshots.filter(func(s: World.EShot) -> bool: return not s.dead)
		var events: Array = w.take_events()
		a = _lap(acc, k, a, on)
		if on:
			shots_sum += w.shots.size()
			runes_sum += w.runes.size()
			for ev: Array in events:
				if ev[0] == World.EV_HIT:
					hits += 1
	var line: String = "STEP %s" % str(loadout)
	var step: int = 0
	for i: int in range(NAMES.size()):
		line += "  %s %d" % [NAMES[i], acc[i] / ticks]
		if i > 0:
			step += acc[i] / ticks
	print("%s | step %d (without bots)  shots %.1f circles %.1f hits %.1f  hash %d" % [
		line, step, float(shots_sum) / ticks, float(runes_sum) / ticks, float(hits) / ticks, w.state_hash()])


static func _lap(acc: Array[int], k: int, since: int, on: bool) -> int:
	var now: int = Time.get_ticks_usec()
	if on:
		acc[k] += now - since
	return now

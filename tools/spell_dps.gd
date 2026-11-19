extends SceneTree
## Balance probe: one wizard stands still with one spell at level 5 (plain and evolved) while a crowd of orcs
## (6x hp, replaced when they die) walks in. Prints damage per second per spell, averaged over 3 seeds.
## Standing still in a dense crowd flatters area spells; read it as a ranking, not as real-run numbers.
## godot --headless --path . -s tools/spell_dps.gd -- [--foes=40] [--seconds=10]

func _init() -> void:
	var foes_n: int = 40
	var seconds: float = 10.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--foes="):
			foes_n = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--seconds="):
			seconds = maxf(1.0, float(arg.get_slice("=", 1)))
	for k: int in range(Spells.COUNT * 2):
		var sp: int = k / 2
		var evo: bool = k % 2 == 1
		var total := 0.0
		for s: int in range(3):
			total += _probe(sp, evo, foes_n, seconds, s)
		var label: String = Spells.EVOS[sp]["name"] if evo else Spells.STATS[sp]["name"]
		print("%-16s dps=%.1f" % [label, total / 3.0 / seconds])
	quit()


func _probe(sp: int, evo: bool, foes_n: int, seconds: float, s: int) -> float:
	var w := World.new([0], 11 + s)
	w.tune.horde_rate_base = 0.0
	w.tune.horde_rate_per_min = 0.0
	w.tune.elite_interval = 1e9
	w.horde_budget = 0.0
	w.phase = World.PH_FIGHT
	w.phase_t = 0.0
	var p: World.Player = w.players[0]
	p.upgrades = {Upgrades.weapon_entry(sp): Spells.MAX_LEVEL, Upgrades.evo_entry(sp): int(evo)}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + s
	var foes: Array[World.Enemy] = []
	for i: int in range(foes_n):
		foes.append(_probe_orc(w, p.pos, rng, rng.randf_range(30.0, 120.0)))
	var dealt := 0.0
	for f: int in range(int(seconds * 60.0)):
		p.hp = 5
		p.invuln = 1.0
		w.step(1.0 / 60.0, {})
		for j: int in range(foes.size()):
			var e: World.Enemy = foes[j]
			if e.dead or e.hp <= 0.0 or not w.enemies.has(e):
				dealt += e.maxhp
				foes[j] = _probe_orc(w, p.pos, rng, 120.0)
	for e: World.Enemy in foes:
		dealt += e.maxhp - e.hp
	return dealt


func _probe_orc(w: World, at: Vector2, rng: RandomNumberGenerator, dist: float) -> World.Enemy:
	var a := rng.randf() * TAU
	var e: World.Enemy = w.spawn_enemy(World.ORC, 0, at + Vector2(cos(a), sin(a)) * dist)
	e.entering = false
	e.hp *= 6.0
	e.maxhp = e.hp
	return e

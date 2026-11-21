extends RefCounted
func run(args: PackedStringArray) -> int:
	var sp := int(args[0])
	var w := World.new([0], int(args[1]))
	w.tune.horde_rate_base = 0.0
	w.tune.horde_rate_per_min = 0.0
	w.tune.elite_interval = 1e9
	w.horde_budget = 0.0
	w.phase = World.PH_FIGHT
	w.phase_t = 0.0
	var p: World.Player = w.players[0]
	p.upgrades = {Upgrades.weapon_entry(sp): 1}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(args[1]) - 6
	for i: int in range(16):
		var a := rng.randf() * TAU
		var e: World.Enemy = w.spawn_enemy(World.GOBLIN, 0, p.pos + Vector2(cos(a), sin(a)) * rng.randf_range(40.0, 120.0))
		e.entering = false
	for f in range(1800):
		p.hp = p.max_hp
		p.invuln = 1.0
		w.step(1.0/60.0, {})
		w.take_events()
		if f % 120 == 0:
			var ds := []
			for e in w.enemies:
				ds.append(int(e.pos.distance_to(p.pos)))
			print(f/60, " n=", w.enemies.size(), " d=", ds, " hp=", w.enemies[0].hp if w.enemies.size() > 0 else 0)
	return 0

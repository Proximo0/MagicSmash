extends RefCounted
## Balance probe: one wizard stands still with one spell while a crowd of orcs (6x hp, replaced when they die) walks
## in, and the damage it deals per second is printed, averaged over 3 seeds. Standing still in a dense crowd
## flatters area spells; read it as a ranking, not as real-run numbers.
##   godot --headless --path . -s tools/tool.gd -- spell_dps [--foes=40] [--seconds=10] [--spell=N]
## Default: every spell at level 5, plain and evolved, among --foes orcs.
## --gate: the wave 3 spell gate (docs/wave3_plan.md), four numbers per spell: level 1 on one target and in a
## sparse crowd (GATE_SPARSE orcs), level 5 in a dense crowd (GATE_DENSE) and on one target.
## --clear: how long one wizard holding the spell at level 1 takes to slay CLEAR_KILLS of CLEAR_FOES plain orcs
## of minute 1 walking in (the class weapon check: a level 1 knight's CLEAVE against a level 1 mage's ARCANE BOLT).
## Not all of them: a foe that reaches a standing wizard's feet is under her bolts' first step, and a probe
## that waited for it would time the stall, not the spell.

const GATE_SPARSE: int = 6
const GATE_DENSE: int = 40
const CLEAR_FOES: int = 16
const CLEAR_KILLS: int = 12
const CLEAR_LIMIT: float = 60.0
const DT: float = 1.0 / 60.0


func run(args: PackedStringArray) -> int:
	var foes_n: int = GATE_DENSE
	var seconds: float = 10.0
	var only: int = -1
	var gate: bool = false
	var clear: bool = false
	for arg: String in args:
		if arg.begins_with("--foes="):
			foes_n = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--seconds="):
			seconds = maxf(1.0, float(arg.get_slice("=", 1)))
		elif arg.begins_with("--spell="):
			only = int(arg.get_slice("=", 1))
		elif arg == "--gate":
			gate = true
		elif arg == "--clear":
			clear = true
	for sp: int in range(Spells.COUNT):
		if only >= 0 and sp != only:
			continue
		var label: String = Spells.spell_name(sp)
		if clear:
			var t := 0.0
			for s: int in range(3):
				t += _clear(sp, s)
			print("%-16s clear=%.1fs (%d of %d orcs, level 1)" % [label, t / 3.0, CLEAR_KILLS, CLEAR_FOES])
		elif gate:
			print("%-16s L1 one=%.1f sparse=%.1f  L5 dense=%.1f one=%.1f" % [label, _dps(sp, 1, false, 1, seconds),
				_dps(sp, 1, false, GATE_SPARSE, seconds), _dps(sp, Spells.MAX_LEVEL, false, GATE_DENSE, seconds),
				_dps(sp, Spells.MAX_LEVEL, false, 1, seconds)])
		else:
			print("%-16s dps=%.1f" % [label, _dps(sp, Spells.MAX_LEVEL, false, foes_n, seconds)])
			if Spells.has_evolution(sp):
				print("%-16s dps=%.1f" % [str(Spells.EVOS[sp]["name"]), _dps(sp, Spells.MAX_LEVEL, true, foes_n, seconds)])
	return 0


func _dps(sp: int, lv: int, evo: bool, foes_n: int, seconds: float) -> float:
	var total := 0.0
	for s: int in range(3):
		total += _probe(sp, lv, evo, foes_n, seconds, s)
	return total / 3.0 / seconds


func _world(sp: int, lv: int, evo: bool, s: int) -> World:
	var w := World.new([0], 11 + s)
	w.tune.horde_rate_base = 0.0
	w.tune.horde_rate_per_min = 0.0
	w.tune.elite_interval = 1e9
	w.horde_budget = 0.0
	w.phase = World.PH_FIGHT
	w.phase_t = 0.0
	var p: World.Player = w.players[0]
	p.upgrades = {Upgrades.weapon_entry(sp): lv}
	if evo and Upgrades.evo_entry(sp) >= 0:
		p.upgrades[Upgrades.evo_entry(sp)] = 1
	return w


func _probe(sp: int, lv: int, evo: bool, foes_n: int, seconds: float, s: int) -> float:
	var w := _world(sp, lv, evo, s)
	var p: World.Player = w.players[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + s
	var foes: Array[World.Enemy] = []
	for i: int in range(foes_n):
		foes.append(_probe_orc(w, p.pos, rng, rng.randf_range(30.0, 120.0)))
	var dealt := 0.0
	for f: int in range(int(seconds / DT)):
		p.hp = p.max_hp
		p.invuln = 1.0
		w.step(DT, {})
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


## Seconds until CLEAR_KILLS of CLEAR_FOES orcs (plain, minute 1) placed 40 to 120 px around the wizard are dead.
func _clear(sp: int, s: int) -> float:
	var w := _world(sp, 1, false, s)
	var p: World.Player = w.players[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + s
	for i: int in range(CLEAR_FOES):
		var a := rng.randf() * TAU
		var e: World.Enemy = w.spawn_enemy(World.ORC, 0, p.pos + Vector2(cos(a), sin(a)) * rng.randf_range(40.0, 120.0))
		e.entering = false
	var t := 0.0
	while t < CLEAR_LIMIT and w.enemies.size() > CLEAR_FOES - CLEAR_KILLS:
		p.hp = p.max_hp
		p.invuln = 1.0
		w.step(DT, {})
		w.take_events()
		t += DT
	return t

extends RefCounted
## Balance probe: one wizard stands still with one spell while a crowd of orcs (6x hp, replaced when they die) walks
## in, and the damage it deals per second is printed, averaged over 3 seeds. Standing still in a dense crowd
## flatters area spells; read it as a ranking, not as real-run numbers.
##   godot --headless --path . -s tools/tool.gd -- spell_dps [--foes=40] [--seconds=10] [--spell=N] [--gate] [--clear] [--all]
## An evolution is an id (Spells.evo_row): 0 none, 1 the first, 2 the second. A wizard measured with evolution `evo`
## holds the spell at level 5 and that evolution's catalog row (Upgrades.evo_entry) and no other evolution of it, and
## not the arcana that opens it (as on main: the game never deals that state, and holding the arcana would move main's
## numbers), so an evolved line measures the evolution's spell alone.
## Default: every spell at level 5 (`NAME dps=N`), then one line for each of its built evolutions, in id order, among
## --foes orcs. An evolution that is on Upgrades.UNBUILT is left out, as an unbuilt spell is; --all adds the
## unbuilt evolutions of a built spell with the word `unbuilt` at the end of their line (their numbers come from
## their data rows, their new behaviour is not in the game yet).
## --gate: the wave 3 spell gate (docs/wave3_plan.md), four numbers per spell: level 1 on one target and in a
## sparse crowd (GATE_SPARSE orcs), level 5 in a dense crowd (GATE_DENSE) and on one target; then one line for each
## of its evolutions (WHIRLWIND too, `NAME evolved dense=N one=N`) in the dense crowd and on one target.
## A support spell (SUPPORTS: VIGIL CANDLE, HEX) is built to raise what other spells deal, so its own damage says
## nothing and it is also measured by what it adds. Each such measure is a line
##   NAME beside ARCANE BOLT 3[, cell]: base=B pair=P added=A
## where B is the damage a second of a wizard holding ARCANE BOLT at level 3 alone, P that of the same wizard (same
## seeds, same foes) also holding the support spell (at the level or evolution of the cell), and A = P - B, the damage
## a second the support spell added, its own damage included. A is the number to hold against the gates: positive
## means it makes the bolts' wizard deal more, near 0 means it adds nothing in that crowd. Measured noise of A (the
## same line on three other seed triples): about +-1 on one target or in a sparse crowd (one kill is 2.5 a second
## at 10 s), up to +-5 for an evolution in a dense crowd, so +1 or +2 there is not yet an effect. In the default
## table the line follows the `dps=` line it belongs to (the spell's, then each evolution's); with --gate the lines
## follow all of the spell's own lines, one per cell:
## L1 one, L1 sparse, L5 dense, L5 one for the spell and `evolved dense`, `evolved one` for each evolution (named
## in its own line). A support spell that is unbuilt is skipped. --spell=N, --foes= and --seconds= govern these lines too.
## --clear: how long one wizard holding the spell at level 1 takes to slay CLEAR_KILLS of CLEAR_FOES plain orcs
## of minute 1 walking in (the class weapon check: a level 1 knight's CLEAVE against a level 1 mage's ARCANE BOLT).
## Not all of them: a foe that reaches a standing wizard's feet is under her bolts' first step, and a probe
## that waited for it would time the stall, not the spell. After the spells, one line per class (a HUMAN hero of
## class level 1, World.apply_hero): its class weapon with its skin and the class's stats, the gate of job P (each
## within CLEAR_GATE of the MAGE's time).
## An argument it does not know is ignored: the default table is printed and the exit code is 0.

const GATE_SPARSE: int = 6
const GATE_DENSE: int = 40
const CLEAR_FOES: int = 16
const CLEAR_KILLS: int = 12
const CLEAR_LIMIT: float = 60.0
const CLEAR_GATE: float = 0.15
const DT: float = 1.0 / 60.0
## The support spells: what they add is measured beside BASE_SPELL at BASE_LEVEL (see the header).
const SUPPORTS: Array[int] = [World.SP_CANDLE, World.SP_HEX]
const BASE_SPELL: int = World.SP_ARCANE
const BASE_LEVEL: int = 3
const NO_MATE := Vector3i(-1, 0, 0)

## The base damage a second of a wizard holding BASE_SPELL alone, by crowd and seconds: the same wizard, seeds and
## foes every time, so it is measured once.
var _bases: Dictionary = {}


func run(args: PackedStringArray) -> int:
	var o: Dictionary = _options(args)
	for sp: int in range(Spells.COUNT):
		for line: String in _rows(sp, o):
			print(line)
	if bool(o["clear"]) and int(o["only"]) < 0:
		var mage := 0.0
		for c: int in range(Classes.count()):
			var t := 0.0
			for s: int in range(3):
				t += _clear(-1, s, c)
			t /= 3.0
			if c == Classes.MAGE:
				mage = t
			var off := t / maxf(mage, 0.01) - 1.0
			print("%-16s clear=%.1fs %s %+.0f%% of the mage's" % [Classes.class_name_of(c) + " " + Classes.weapon_name(c),
				t, "ok" if absf(off) <= CLEAR_GATE else "OFF", off * 100.0])
	return 0


## The parsed arguments: foes, seconds, only (--spell, -1 all), gate, clear, every (--all). An unknown one is ignored.
func _options(args: PackedStringArray) -> Dictionary:
	var o: Dictionary = {"foes": GATE_DENSE, "seconds": 10.0, "only": -1, "gate": false, "clear": false, "every": false}
	for arg: String in args:
		if arg.begins_with("--foes="):
			o["foes"] = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--seconds="):
			o["seconds"] = maxf(1.0, float(arg.get_slice("=", 1)))
		elif arg.begins_with("--spell="):
			o["only"] = int(arg.get_slice("=", 1))
		elif arg == "--gate":
			o["gate"] = true
		elif arg == "--clear":
			o["clear"] = true
		elif arg == "--all":
			o["every"] = true
	return o


## The lines the table prints for spell `sp` under the options `o` (see _options), in order; none for a spell that is
## not asked for or not built.
func _rows(sp: int, o: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if int(o["only"]) >= 0 and sp != int(o["only"]):
		return out
	if Upgrades.UNBUILT.has(Upgrades.weapon_entry(sp)):
		return out # it casts nothing until its job builds it
	var foes_n: int = int(o["foes"])
	var seconds: float = float(o["seconds"])
	var label: String = Spells.spell_name(sp)
	var evos: Array[int] = _evos(sp, bool(o["every"]))
	if bool(o["clear"]):
		var t := 0.0
		for s: int in range(3):
			t += _clear(sp, s)
		out.append("%-16s clear=%.1fs (%d of %d orcs, level 1)" % [label, t / 3.0, CLEAR_KILLS, CLEAR_FOES])
	elif bool(o["gate"]):
		out.append("%-16s L1 one=%.1f sparse=%.1f  L5 dense=%.1f one=%.1f" % [label, _dps(sp, 1, 0, 1, seconds),
			_dps(sp, 1, 0, GATE_SPARSE, seconds), _dps(sp, Spells.MAX_LEVEL, 0, GATE_DENSE, seconds),
			_dps(sp, Spells.MAX_LEVEL, 0, 1, seconds)])
		for evo: int in evos:
			out.append("%-16s evolved           dense=%.1f one=%.1f%s" % [_evo_name(sp, evo),
				_dps(sp, Spells.MAX_LEVEL, evo, GATE_DENSE, seconds), _dps(sp, Spells.MAX_LEVEL, evo, 1, seconds),
				_unbuilt_mark(sp, evo)])
		if SUPPORTS.has(sp):
			for cell: Array in [["L1 one", 1, 1], ["L1 sparse", 1, GATE_SPARSE], ["L5 dense", Spells.MAX_LEVEL, GATE_DENSE],
					["L5 one", Spells.MAX_LEVEL, 1]]:
				out.append(_support_line(label, str(cell[0]), _support(sp, int(cell[1]), 0, int(cell[2]), seconds)))
			for evo: int in evos:
				for cell: Array in [["evolved dense", GATE_DENSE], ["evolved one", 1]]:
					out.append(_support_line(_evo_name(sp, evo), str(cell[0]),
						_support(sp, Spells.MAX_LEVEL, evo, int(cell[1]), seconds)) + _unbuilt_mark(sp, evo))
	else:
		out.append("%-16s dps=%.1f" % [label, _dps(sp, Spells.MAX_LEVEL, 0, foes_n, seconds)])
		if SUPPORTS.has(sp):
			out.append(_support_line(label, "", _support(sp, Spells.MAX_LEVEL, 0, foes_n, seconds)))
		for evo: int in evos:
			out.append("%-16s dps=%.1f%s" % [_evo_name(sp, evo), _dps(sp, Spells.MAX_LEVEL, evo, foes_n, seconds),
				_unbuilt_mark(sp, evo)])
			if SUPPORTS.has(sp):
				out.append(_support_line(_evo_name(sp, evo), "", _support(sp, Spells.MAX_LEVEL, evo, foes_n, seconds))
					+ _unbuilt_mark(sp, evo))
	return out


## The evolution ids of `sp` to measure, in id order: the built ones, and with `every` the unbuilt ones too.
func _evos(sp: int, every: bool) -> Array[int]:
	var out: Array[int] = []
	for evo: int in range(1, Spells.evolutions(sp) + 1):
		var row: int = Upgrades.evo_entry(sp, evo)
		if row >= 0 and (every or not Upgrades.UNBUILT.has(row)):
			out.append(evo)
	return out


func _evo_name(sp: int, evo: int) -> String:
	return str(Spells.evo_row(sp, evo)["name"])


## " unbuilt" for an evolution whose row is on Upgrades.UNBUILT (only --all lists it), else "".
func _unbuilt_mark(sp: int, evo: int) -> String:
	return " unbuilt" if Upgrades.UNBUILT.has(Upgrades.evo_entry(sp, evo)) else ""


## Damage a second of a wizard holding `sp` at level `lv` with evolution `evo` (0 none), averaged over 3 seeds. A
## `mate` (spell, level, evolution) is a second spell she holds; x < 0: none.
func _dps(sp: int, lv: int, evo: int, foes_n: int, seconds: float, mate: Vector3i = NO_MATE) -> float:
	var total := 0.0
	for s: int in range(3):
		total += _probe(sp, lv, evo, foes_n, seconds, s, mate)
	return total / 3.0 / seconds


## What support spell `sp` (at level `lv`, evolution `evo`) adds beside BASE_SPELL at BASE_LEVEL: {base, pair, added}
## in damage a second, the pair measured with the same seeds and foes as the base.
func _support(sp: int, lv: int, evo: int, foes_n: int, seconds: float) -> Dictionary:
	var key := "%d:%s" % [foes_n, str(seconds)]
	if not _bases.has(key):
		_bases[key] = _dps(BASE_SPELL, BASE_LEVEL, 0, foes_n, seconds)
	var base: float = _bases[key]
	var pair: float = _dps(BASE_SPELL, BASE_LEVEL, 0, foes_n, seconds, Vector3i(sp, lv, evo))
	return {"base": base, "pair": pair, "added": pair - base}


## One support line (see the header): `name` the spell's or the evolution's, `cell` the gate cell or "".
func _support_line(name: String, cell: String, r: Dictionary) -> String:
	return "%-16s beside %s %d%s: base=%.1f pair=%.1f added=%+.1f" % [name, Spells.spell_name(BASE_SPELL), BASE_LEVEL,
		(", " + cell) if cell != "" else "", float(r["base"]), float(r["pair"]), float(r["added"])]


## Adds `sp` at level `lv` to the upgrades `up`; with evolution `evo` the weapon is at MAX_LEVEL (the game offers an
## evolution of no other) and holds that evolution's row alone.
func _hold(up: Dictionary, sp: int, lv: int, evo: int) -> void:
	var row: int = Upgrades.evo_entry(sp, evo) if evo > 0 else -1
	up[Upgrades.weapon_entry(sp)] = Spells.MAX_LEVEL if row >= 0 else lv
	if row >= 0:
		up[row] = 1


## A world of its own Tuning: the horde-off numbers below must not reach Tuning.shared(), which the other tests read.
func _world(sp: int, lv: int, evo: int, s: int, mate: Vector3i = NO_MATE) -> World:
	var w := World.new([0], 11 + s, Tuning.new())
	w.tune.horde_rate_base = 0.0
	w.tune.horde_rate_per_min = 0.0
	w.tune.elite_interval = 1e9
	w.horde_budget = 0.0
	w.phase = World.PH_FIGHT
	w.phase_t = 0.0
	var p: World.Player = w.players[0]
	p.upgrades = {}
	_hold(p.upgrades, sp, lv, evo)
	if mate.x >= 0:
		_hold(p.upgrades, mate.x, mate.y, mate.z)
	return w


## The state a probe starts from: {w: the world, rng: the foes' random draws, foes: the first `foes_n` orcs}. It
## depends on the seed `s` and the crowd, never on the spell cards held, so a base and its pair start alike.
func _start(sp: int, lv: int, evo: int, foes_n: int, s: int, mate: Vector3i = NO_MATE) -> Dictionary:
	var w := _world(sp, lv, evo, s, mate)
	var p: World.Player = w.players[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + s
	var foes: Array[World.Enemy] = []
	for i: int in range(foes_n):
		foes.append(_probe_orc(w, p.pos, rng, rng.randf_range(30.0, 120.0)))
	return {"w": w, "rng": rng, "foes": foes}


func _probe(sp: int, lv: int, evo: int, foes_n: int, seconds: float, s: int, mate: Vector3i = NO_MATE) -> float:
	var st: Dictionary = _start(sp, lv, evo, foes_n, s, mate)
	var w: World = st["w"]
	var rng: RandomNumberGenerator = st["rng"]
	var foes: Array[World.Enemy] = st["foes"]
	var p: World.Player = w.players[0]
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
## With a class `cls` (sp ignored) the wizard is a HUMAN hero of that class holding its class weapon.
func _clear(sp: int, s: int, cls: int = -1) -> float:
	var w := _world(sp if cls < 0 else Wizards.start_spell(0), 1, 0, s)
	var p: World.Player = w.players[0]
	if cls >= 0:
		w.apply_hero(p, Hero.make(Races.HUMAN, cls, p.wizard).to_dict())
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

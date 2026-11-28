class_name WorldCastSweep
extends RefCounted
## Sweep casts for World: the "sweep" caster and where a sweep swings. Static helpers; the first argument is the
## World.


## Where a sweep of `sp` swings: along the aim stick when it is held and a foe stands in that arc, else at the
## nearest foe the swing can reach (the same reach test as _cast_sweep); ZERO when it can reach none (it does not
## swing at the air). `evo`: the evolution's reach and arc (WHIRLWIND's full circle).
static func _sweep_dir(w: World, p: World.Player, sp: int, aim: Vector2, evo: bool = false) -> Vector2:
	var reach := Spells.level_value(sp, "r", Spells.MAX_LEVEL, evo)
	var half := Spells.level_value(sp, "arc", Spells.MAX_LEVEL, evo) * 0.5
	var from := p.pos + Vector2(0, -4)
	var held := aim.length() > 0.1
	var want := aim.normalized() if held else Vector2.ZERO
	var best := Vector2.ZERO
	var best_d := INF
	for e: World.Enemy in w._query(from, reach + World.CELL): # a boss is wider than half a cell
		if e.dead or e.entering or WorldEnemies._faded(w, e):
			continue
		var to := e.pos - from
		var d := to.length()
		if d - e.r > reach:
			continue
		if held and (d <= e.r or half >= PI or absf(want.angle_to(to)) <= half):
			return want
		if d < best_d:
			best_d = d
			best = to / d if d > 0.01 else Vector2.RIGHT
	return best


## "sweep": one swing of an arc `arc` radians wide reaching `r` px along `dir` (evolved: the evolution's, WHIRLWIND's
## full circle); every enemy it reaches is hit once and knocked back (EV_SWEEP draws it). An evolution with `most`
## strikes only that many of them, the nearest first (Spells.EVOS).
static func _cast_sweep(w: World, p: World.Player, sp: int, lv: int, evo: bool, dir: Vector2, _tip: Vector2, _n: int, dmg: float) -> void:
	var reach := Spells.level_value(sp, "r", lv, evo)
	var half := Spells.level_value(sp, "arc", lv, evo) * 0.5
	var most := int(Spells.evo_value(sp, "most", 0.0)) if evo else 0
	var from := p.pos + Vector2(0, -4)
	var knock := WorldCasting._skin_mul(p, sp, "knock_mul")
	var hit: Array = [] # [edge distance, enemy]
	for e: World.Enemy in w._query(from, reach + World.CELL): # a boss is wider than half a cell
		if e.dead or e.entering or WorldEnemies._faded(w, e):
			continue
		var to := e.pos - from
		var d := to.length()
		if d - e.r > reach or (d > e.r and half < PI and absf(dir.angle_to(to)) > half):
			continue
		hit.append([d - e.r, e])
	if most > 0 and hit.size() > most:
		hit.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		hit.resize(most)
	for h: Array in hit:
		var e: World.Enemy = h[1]
		var to := e.pos - from
		WorldEnemies._damage_enemy(w, e, dmg, p.slot, (to / maxf(to.length(), 0.01)) * Spells.SWEEP_KNOCK * knock)
	w.emit(World.EV_SWEEP, from.x, from.y, dir.angle(), p.slot + (8 if evo else 0))

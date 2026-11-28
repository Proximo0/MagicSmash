class_name WorldCastChain
extends RefCounted
## Chain casts for World: the "chain" caster and lightning that jumps foe to foe. Static helpers; the first
## argument is the World.


## "chain": lightning foe to foe, `n` jumps (THE STAR's missiles are more jumps of each chain); Tempest casts several
## chains with a longer reach. Returns the most foes one chain struck.
static func _cast_chain(w: World, p: World.Player, sp: int, _lv: int, evo: int, dir: Vector2, tip: Vector2, n: int, dmg: float) -> int:
	var chains := int(Spells.evo_value(sp, "chains", evo, 1.0))
	var range_mul := Spells.TEMPEST_RANGE_MUL if evo > 0 else 1.0
	var hit := {}
	var most := 0
	for c in chains:
		most = maxi(most, _chain_lightning(w, p.slot, tip, dir.rotated((c - (chains - 1) * 0.5) * 0.5), n, dmg, range_mul, hit))
	return most


## The staff's base: where a chain lightning's cone is measured from (its bolt is drawn from the tip).
static func _staff_base(tip: Vector2, dir: Vector2) -> Vector2:
	return tip - dir * WorldCasting.STAFF_REACH


## Lightning from `tip` to the nearest enemy roughly along `dir`, then `jumps - 1` jumps foe to foe. The cone
## and the range are measured from the staff's base, so an enemy touching the wizard (inside the tip) is struck.
## Enemies in `hit` and faded wraiths are skipped, so several chains of one cast find different foes. Returns the foes
## it struck (0: none in its cone).
static func _chain_lightning(w: World, slot: int, tip: Vector2, dir: Vector2, jumps: int, dmg: float, range_mul: float, hit: Dictionary) -> int:
	var best: World.Enemy = null
	var best_d := Spells.CHAIN_FIRST_RANGE * range_mul
	var base := _staff_base(tip, dir)
	for e in w.enemies:
		if e.dead or hit.has(e.id) or WorldEnemies._faded(w, e):
			continue
		var to := e.pos - base
		var d := to.length()
		if d < best_d and to.normalized().dot(dir) > 0.6:
			best_d = d
			best = e
	if best == null:
		w.emit(World.EV_ZAP, tip.x, tip.y, PackedVector2Array([tip, tip + dir * Spells.CHAIN_JUMP_RANGE * range_mul]), slot)
		return 0
	return _zap_chain(w, slot, tip, best, jumps, dmg, Spells.CHAIN_JUMP_RANGE * range_mul, hit, dir)


## Lightning from `from` through `first` and on to the nearest unhit enemy within `jump_range`, up to `jumps` foes.
## Returns the foes it struck.
static func _zap_chain(w: World, slot: int, from: Vector2, first: World.Enemy, jumps: int, dmg: float, jump_range: float, hit: Dictionary, push: Vector2) -> int:
	var pts := PackedVector2Array([from])
	var cur := first
	for i in jumps:
		pts.append(cur.pos + Vector2(0, -4))
		hit[cur.id] = true
		WorldEnemies._damage_enemy(w, cur, dmg, slot, push * 40.0)
		var nxt: World.Enemy = null
		var nd := jump_range
		for e in w._query(cur.pos, jump_range):
			if hit.has(e.id) or e.dead or WorldEnemies._faded(w, e):
				continue
			var d: float = e.pos.distance_to(cur.pos)
			if d < nd:
				nd = d
				nxt = e
		if nxt == null:
			break
		cur = nxt
		dmg *= Spells.CHAIN_FALLOFF
	w.emit(World.EV_ZAP, from.x, from.y, pts, slot)
	return pts.size() - 1

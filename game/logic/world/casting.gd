class_name WorldCasting
extends RefCounted
## Spells for World: auto-casting, the table of casters by kind (each kind lives in its own cast_*.gd), the class
## skin's multipliers, the main spell, and JUSTICE's bursts. Static helpers; the first argument is the World.


## Every owned spell weapon casts on its own cooldown: along the aim stick when it is held, otherwise at the
## nearest enemy within tune.auto_aim_range. Nothing in range and no aim: the weapons wait, ready.
static func _auto_cast(w: World, p: World.Player, dt: float, aim: Vector2) -> void:
	var dir := Vector2.ZERO
	if aim.length() > 0.1:
		dir = aim.normalized()
	else:
		var tgt := _nearest_enemy(w, p.pos, w.tune.auto_aim_range)
		if tgt:
			dir = (tgt.pos + Vector2(0, -4) - (p.pos + Vector2(0, -7))).normalized()
			p.aim = dir
	# The wizard's own cast-rate bonuses never cut a cooldown below Spells.CAST_FLOOR of itself. The cast-speed
	# bonuses (THE LOVERS, a vigil candle) add up and divide the cooldown (exactly 1 without them).
	var rate_mul: float = maxf(Spells.CAST_FLOOR, (w.tune.haste_rate_mul if p.haste > 0.0 else 1.0) * Upgrades.cast_mul(p.upgrades)
		* (1.0 - p.armor[Loot.ST_FOCUS]) / (1.0 + _cast_speed(w, p))) * w.tune.spell_cd_mul
	for sp in Spells.COUNT:
		var lv := Upgrades.weapon_level(p.upgrades, sp)
		if lv <= 0:
			continue
		# A running timer keeps the fraction of a tick it overshot, so cooldowns are not rounded up to whole
		# ticks; a weapon that waited (no target) is ready at 0 and casts on its full cooldown from then.
		var running := p.cds[sp] > 0.0
		var left: float = p.cds[sp] - dt
		if left > 0.0 or dir == Vector2.ZERO:
			p.cds[sp] = maxf(0.0, left)
			continue
		var cast_dir := dir
		var evo := Upgrades.evolved(p.upgrades, sp)
		if Spells.cast_kind(sp) == "sweep":
			# A sweep waits, ready, until a foe is within its reach, and swings at the nearest one (or along the aim).
			cast_dir = WorldCastSweep._sweep_dir(w, p, sp, aim, evo)
			if cast_dir == Vector2.ZERO:
				p.cds[sp] = 0.0
				continue
		p.cds[sp] = Spells.cooldown(sp, lv, evo) * rate_mul * _skin_mul(p, sp, "cd_mul") + (left if running else 0.0)
		_cast(w, p, sp, lv, evo, cast_dir)


## Cast speed added to a wizard's own (0 without any): THE LOVERS (near a standing ally, or half alone) plus
## Spells.VIGIL_HASTE while a vigil candle's light still hastens her.
static func _cast_speed(w: World, p: World.Player) -> float:
	var out := Spells.VIGIL_HASTE if p.vigil > 0.0 else 0.0
	if Upgrades.level_of(p.upgrades, Upgrades.LOVERS) > 0:
		var together := false
		for q: World.Player in w._plist:
			if q != p and q.alive and not q.down and q.pos.distance_to(p.pos) <= Upgrades.LOVERS_RANGE:
				together = true
				break
		out += Upgrades.lovers_bonus(p.upgrades, together)
	return out


## Nearest living enemy inside the arena within `radius` of `pos`, or null.
static func _nearest_enemy(w: World, pos: Vector2, radius: float) -> World.Enemy:
	var best: World.Enemy = null
	var bd := radius * radius
	for e in w.enemies:
		if e.dead or e.entering or WorldEnemies._faded(w, e):
			continue
		var d := e.pos.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = e
	return best


## One caster per Spells.STATS "cast" kind. Each takes (w, p, sp, lv, evo, dir, tip, n, dmg); a new kind is one
## function here plus its row in this table and in Spells.STATS.
## How far the staff's tip is from its base (the wizard's hand, 7 px above the feet) along the aim, px.
const STAFF_REACH := 9.0

static var CASTS := {
	"bolt": WorldCastBolts._cast_bolts,
	"chain": WorldCastChain._cast_chain,
	"rune": WorldCastCircles._cast_rune,
	"candle": WorldCastCircles._cast_candle,
	"sweep": WorldCastSweep._cast_sweep,
}


static func _cast(w: World, p: World.Player, sp: int, lv: int, evo: bool, dir: Vector2) -> void:
	w.stat_src = sp
	var tip := p.pos + Vector2(0, -7) + dir * STAFF_REACH
	var caster: Callable = CASTS[Spells.cast_kind(sp)]
	var dmg := Spells.damage(sp, lv, evo) * _skin_mul(p, sp, "dmg_mul")
	caster.call(w, p, sp, lv, evo, dir, tip, Spells.count(sp, lv, evo), dmg)
	w.emit(World.EV_CAST, tip.x, tip.y, sp, p.slot)


## A multiplier of wizard `p`'s class skin (Classes.SKINS: dmg_mul, cd_mul, knock_mul) for spell `sp`: the skin's
## when `sp` is her class weapon, 1 for every other spell and for a skin without it (a BONE SPEAR or a STARFALL
## picked up from a card is the row as it is).
static func _skin_mul(p: World.Player, sp: int, field: String) -> float:
	return Classes.skin_value(p.skin, field, 1.0) if sp == p.class_weapon else 1.0


## The main spell is the highest weapon (an evolved one beats any level); ties go to the later spell.
static func _refresh_spell(w: World, p: World.Player) -> void:
	var best := -1
	for sp in Spells.COUNT:
		var lv := _weapon_snap(w, p, sp)
		if lv > 0 and lv >= best:
			best = lv
			p.spell = sp


## Weapon level as sent in snapshots: 0 not owned, 1..MAX_LEVEL, MAX_LEVEL + 1 evolved.
static func _weapon_snap(w: World, p: World.Player, sp: int) -> int:
	if Upgrades.evolved(p.upgrades, sp):
		return Spells.MAX_LEVEL + 1
	return Upgrades.weapon_level(p.upgrades, sp)


## JUSTICE: a foe slain by a wizard holding it may burst (queued in w.bursts, set off by _update_bursts). Bosses
## and foes slain by a burst never burst.
static func _justice(w: World, e: World.Enemy, slot: int) -> void:
	if w.bursting or e.flags & Bestiary.F_BOSS:
		return
	var p: World.Player = w.players.get(slot)
	if p == null:
		return
	var chance := Upgrades.justice_chance(p.upgrades)
	if chance > 0.0 and w.rng.randf() < chance:
		w.bursts.append([e.pos, e.maxhp * Upgrades.JUSTICE_SHARE, slot])


## The queued JUSTICE bursts go off: every enemy within Upgrades.JUSTICE_RADIUS takes the burst's damage. Kills
## they make never burst (w.bursting), so the queue empties in one pass.
static func _update_bursts(w: World) -> void:
	if w.bursts.is_empty():
		return
	w.bursting = true
	w.stat_src = Results.SRC_JUSTICE
	var queued := w.bursts
	w.bursts = []
	for b: Array in queued:
		var at: Vector2 = b[0]
		w.emit(World.EV_BURST, at.x, at.y, Upgrades.JUSTICE_RADIUS, int(b[2]))
		for e: World.Enemy in w._query(at, Upgrades.JUSTICE_RADIUS + World.CELL * 0.5):
			if not e.dead and e.pos.distance_to(at) <= Upgrades.JUSTICE_RADIUS + e.r:
				WorldEnemies._damage_enemy(w, e, float(b[1]), int(b[2]), (e.pos - at).normalized() * Spells.BLAST_KNOCK)
	w.bursting = false

class_name SmashBot
extends RefCounted
## Play-bot brain for one wizard. Works on plain positions, so the arena (from its view state, also on LAN
## clients) and headless sims (straight from World) drive wizards with the same logic.
## Output matches PlayerInput.read: [move_x, move_y, aim_x, aim_y, fire, nova_count]; decide_in_world and
## with_pick add [pick, offer] for level-ups.

const ENEMY_DANGER_RANGE: float = 50.0
const SHOT_DANGER_RANGE: float = 30.0
const SHOT_DANGER_WEIGHT: float = 2.0
const PICKUP_RANGE: float = 80.0
const PICKUP_PULL: float = 0.8
const ORBIT_RADIUS: float = 60.0
const ORBIT_SPEED: float = 0.6
const ORBIT_PULL: float = 0.6
const NOVA_RANGE: float = 22.0
const NOVA_CHANCE: float = 0.02
## A shrine the bot can pay for pulls it from this far, and it stands still once this close.
const SHRINE_RANGE: float = 220.0
const SHRINE_STAND: float = 5.0
const SHRINE_PULL: float = 1.2

## Level-up pick policy: the first of these the offer contains. Damage and cast rate first, as a player would.
## Evolutions first, then spell weapons (area spells before the single bolt), then the stat upgrades.
const PICK_PRIORITY: Array[int] = [Upgrades.EVO_FIRST, Upgrades.EVO_FIRST + 1, Upgrades.EVO_FIRST + 2,
	Upgrades.EVO_FIRST + 3, Upgrades.EVO_FIRST + 4,
	Upgrades.W_FIRST + 1, Upgrades.W_FIRST + 3, Upgrades.W_FIRST + 4, Upgrades.W_FIRST + 2, Upgrades.W_FIRST,
	Upgrades.POWER, Upgrades.QUICK, Upgrades.SWIFT, Upgrades.MAGNET,
	Upgrades.WISDOM, Upgrades.REGEN, Upgrades.LIFE, Upgrades.NOVA]

var rng := RandomNumberGenerator.new()
var nova_count: int = 0


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value


## One tick of input. `center` is the arena centre the bot circles while it fights.
## `goal` is a shrine the bot can afford (Vector2.INF for none): it walks there and stands to bet, still dodging.
func decide(slot: int, me: Vector2, center: Vector2, time: float, enemies: Array[Vector2],
		enemy_shots: Array[Vector2], pickups: Array[Vector2], goal: Vector2 = Vector2.INF) -> PackedFloat32Array:
	var near := Vector2.ZERO
	var nd: float = INF
	var danger := Vector2.ZERO
	for e: Vector2 in enemies:
		var d: float = e.distance_to(me)
		if d < nd:
			nd = d
			near = e
		if d < ENEMY_DANGER_RANGE:
			danger += (me - e) / maxf(d, 1.0)
	for s: Vector2 in enemy_shots:
		var d: float = s.distance_to(me)
		if d < SHOT_DANGER_RANGE:
			danger += (me - s) / maxf(d, 1.0) * SHOT_DANGER_WEIGHT
	var orbit: Vector2 = Vector2.from_angle(time * ORBIT_SPEED + slot * TAU / 4.0) * ORBIT_RADIUS + center
	var mv: Vector2 = (orbit - me).normalized() * ORBIT_PULL + danger
	for k: Vector2 in pickups:
		if k.distance_to(me) < PICKUP_RANGE:
			mv += (k - me).normalized() * PICKUP_PULL
	if goal.is_finite():
		var gd: float = goal.distance_to(me)
		mv = danger * 0.5 if gd < SHRINE_STAND else (goal - me).normalized() * SHRINE_PULL + danger * 0.5
	var aim: Vector2 = (near - me) if nd < INF else Vector2.ZERO
	if nd < NOVA_RANGE and rng.randf() < NOVA_CHANCE:
		nova_count += 1
	mv = mv.limit_length(1.0)
	return PackedFloat32Array([mv.x, mv.y, aim.x, aim.y, 1.0 if aim != Vector2.ZERO else 0.0, nova_count])


## Which card to take from an offer (an index into `choices`), or -1 for an empty offer.
static func choose_pick(choices: Array[int]) -> int:
	for want: int in PICK_PRIORITY:
		var at: int = choices.find(want)
		if at >= 0:
			return at
	return 0 if not choices.is_empty() else -1


## Appends the pick fields [pick index, offer id] that World reads at input[6] and input[7].
static func with_pick(inp: PackedFloat32Array, choices: Array[int], offer: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = inp.duplicate()
	out.append(choose_pick(choices))
	out.append(offer)
	return out


## Same decision read straight from the simulation (sims, tests, headless bot runs).
func decide_in_world(world: World, slot: int) -> PackedFloat32Array:
	var p: World.Player = world.players.get(slot)
	if p == null:
		return PackedFloat32Array([0, 0, 0, 0, 0, nova_count])
	if not p.alive:
		return with_pick(PackedFloat32Array([0, 0, 0, 0, 0, nova_count]), p.choices, p.offer)
	var en: Array[Vector2] = []
	for e: World.Enemy in world.enemies:
		en.append(e.pos)
	var es: Array[Vector2] = []
	for s: World.EShot in world.eshots:
		es.append(s.pos)
	var pk: Array[Vector2] = []
	for k: World.Pickup in world.pickups:
		pk.append(k.pos)
	return with_pick(decide(slot, p.pos, G.ARENA.get_center(), world.time, en, es, pk,
		shrine_goal(p.pos, p.gold, world.snapshot_shrines())), p.choices, p.offer)


## The nearest shrine in reach that `gold` pays for, from shrine rows [kind, x, y, life, charge, cost], or INF.
static func shrine_goal(me: Vector2, gold: float, rows: Array) -> Vector2:
	var best := Vector2.INF
	var bd: float = SHRINE_RANGE
	for r: Array in rows:
		var at := Vector2(r[1], r[2])
		if gold >= float(r[5]) and at.distance_to(me) < bd:
			bd = at.distance_to(me)
			best = at
	return best

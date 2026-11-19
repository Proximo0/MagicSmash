class_name SmashBot
extends RefCounted
## Play-bot brain for one wizard. Works on plain positions, so the arena (from its view state, also on LAN
## clients) and headless sims (straight from World) drive wizards with the same logic.
## Output matches PlayerInput.read: [move_x, move_y, aim_x, aim_y, fire, nova_count].

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

var rng := RandomNumberGenerator.new()
var nova_count: int = 0


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value


## One tick of input. `center` is the arena centre the bot circles while it fights.
func decide(slot: int, me: Vector2, center: Vector2, time: float, enemies: Array[Vector2],
		enemy_shots: Array[Vector2], pickups: Array[Vector2]) -> PackedFloat32Array:
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
	var orbit: Vector2 = Vector2.from_angle(time * ORBIT_SPEED + slot * PI) * ORBIT_RADIUS + center
	var mv: Vector2 = (orbit - me).normalized() * ORBIT_PULL + danger
	for k: Vector2 in pickups:
		if k.distance_to(me) < PICKUP_RANGE:
			mv += (k - me).normalized() * PICKUP_PULL
	var aim: Vector2 = (near - me) if nd < INF else Vector2.ZERO
	if nd < NOVA_RANGE and rng.randf() < NOVA_CHANCE:
		nova_count += 1
	mv = mv.limit_length(1.0)
	return PackedFloat32Array([mv.x, mv.y, aim.x, aim.y, 1.0 if aim != Vector2.ZERO else 0.0, nova_count])


## Same decision read straight from the simulation (sims, tests, headless bot runs).
func decide_in_world(world: World, slot: int) -> PackedFloat32Array:
	var p: World.Player = world.players.get(slot)
	if p == null or not p.alive:
		return PackedFloat32Array([0, 0, 0, 0, 0, nova_count])
	var en: Array[Vector2] = []
	for e: World.Enemy in world.enemies:
		en.append(e.pos)
	var es: Array[Vector2] = []
	for s: World.EShot in world.eshots:
		es.append(s.pos)
	var pk: Array[Vector2] = []
	for k: World.Pickup in world.pickups:
		pk.append(k.pos)
	return decide(slot, p.pos, G.ARENA.get_center(), world.time, en, es, pk)

extends RefCounted
## A kind brain for test_bestiary (Brains.kind_brains): walks straight up, blocks all damage but `sure` hits and
## leaves a marker when it dies. Not a test file itself.


static func think(_w: World, e: World.Enemy, _dt: float, _tgt: World.Player, _dirv: Vector2, _dist: float) -> Vector2:
	e.state = 7
	return Vector2(0, -e.spd)


static func on_death(w: World, e: World.Enemy, _slot: int) -> bool:
	w.boss_arg = 4242
	return e.type >= 0


static func filter_damage(_w: World, _e: World.Enemy, dmg: float, _knock: Vector2, sure: bool) -> float:
	return dmg if sure else -1.0

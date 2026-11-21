class_name WorldBosses
extends RefCounted
## The Lich for World: thin callers kept for older code. The bodies live in Bosses (schedule, health, the final)
## and BossLich (the behaviour). Static helpers; the first argument is the World.


static func _make_final(w: World, e: World.Enemy) -> void:
	Bosses._make_final(w, e)


## The Lich's health multiplier this minute (party size and earlier visits).
static func _lich_hp_scale(w: World) -> float:
	return Bosses.health_in(w, World.LICH) / float(Bestiary.KINDS[World.LICH][Bestiary.K_HP])


## How many Lich visits are due by the start of `minute` (minute 1 starts at 0:00).
static func _lich_visits(w: World, minute: int) -> int:
	return Bosses.visits(World.LICH, (minute - 1) * 60.0, w.schedule)

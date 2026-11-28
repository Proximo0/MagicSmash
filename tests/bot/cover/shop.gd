extends "res://tests/bot/cover/family.gd"
## The coverage family "shop": the Profile.META rows whose Test letters (docs/content_list.md § 45) hold a B, dealt by
## World.apply_meta with the row at level 1 before the run's first step (the arena applied a scripted run's empty
## bonuses, so it is the run's one table) and credited by the use counter "shop_" + key. A row of Profile.UNBUILT is
## planned as unbuilt.

## The rows with a B. META carries no Test letters, so they are named here (the shop's rows are frozen); keys() keeps
## META's order and drops a name META does not hold.
const B_ROWS: Array[String] = ["start_level", "favour"]


func family() -> String:
	return "shop"


func keys() -> Array[String]:
	var out: Array[String] = []
	for row: Array in Profile.META:
		if B_ROWS.has(row[0]):
			out.append(row[0])
	return out


func unbuilt(key: String) -> bool:
	return Profile.UNBUILT.has(key)


## True once run `w` has taken its first step: a shop row reaches a run only through apply_meta before it
## (WorldLevels._shop_start reads it there), so a row dealt then would never take.
func too_late(w: World) -> bool:
	return w._tick > 0


## Dealt too late (too_late) is an engine error, so the row fails.
func deal(w: World, _p: World.Player, key: String) -> void:
	if too_late(w):
		push_error("the shop row %s was dealt after the run's first step" % key)
	var eff: Array = Profile.EFFECTS[key]
	w.apply_meta({eff[0]: float(eff[1])})


func credit(w: World, _p: World.Player, key: String) -> int:
	return w.record.used("shop_" + key)

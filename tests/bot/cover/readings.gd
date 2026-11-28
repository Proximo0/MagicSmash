extends "res://tests/bot/cover/family.gd"
## The coverage family "reading": every row of Readings.ROWS, dealt by World.apply_reading before the first step (the
## arena applied none, so it is the run's one Reading) and credited by its use counter: a Reading that is only merged
## numbers when it is applied, one with a rule where the rule fires. A row of Readings.UNBUILT is planned as unbuilt.


func family() -> String:
	return "reading"


func keys() -> Array[String]:
	var out: Array[String] = []
	for row: Array in Readings.ROWS:
		out.append(row[Readings.KEY])
	return out


func unbuilt(key: String) -> bool:
	return Readings.UNBUILT.has(key)


func deal(w: World, _p: World.Player, key: String) -> void:
	w.apply_reading(key)


func credit(w: World, _p: World.Player, key: String) -> int:
	return w.record.used(key)

extends RefCounted
## A family of the coverage robot (tests/bot/bot_cover.gd, docs/stage3_brief.md § 4.4): where its rows come from, how
## one is dealt and how it is credited. A new family is one new script in this folder, `extends` this file, with the
## four functions below filled in; the robot and tools/coverage.gd find it by its file, so no list is edited. Its keys
## must be unique across every family (they are the use counters' keys: `r_cups_5`, `seal_3`, `card_bat`...).


## The family's name, as `ROW <family> <key> ...` prints it.
func family() -> String:
	return ""


## Every row key of the family in a stable order, read from its data table (unbuilt rows too).
func keys() -> Array[String]:
	return []


## True for a row whose code is not on main yet: the robot plans it as `unbuilt` and does not play it.
func unbuilt(_key: String) -> bool:
	return false


## Deals row `key` to wizard `p` of the fresh run `w`, before its first step, past every lock and rule.
func deal(_w: World, _p: World.Player, _key: String) -> void:
	pass


## How much row `key` has been credited so far this run (0: not yet). A damage row returns its whole damage points, any
## other its use counter (Results.used).
func credit(_w: World, _p: World.Player, _key: String) -> int:
	return 0

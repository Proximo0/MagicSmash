class_name Wizards
extends RefCounted
## The four wizards a player can pick in the lobby. Each is one of the four robe colours
## (Sprites.PLAYER_COLORS, same order) and starts the run with its own spell weapon at level 1.
## Pure data plus the rules for picking: no two wizards in a party are the same.

## [name, title, starting spell (World.SP_*)]. Indices are what the roster and snapshots carry.
const ROSTER: Array = [
	["VIOLET", "ARCANIST", 0], # arcane bolt
	["CRIMSON", "PYROMANCER", 1], # fireball
	["EMERALD", "FROSTWARDEN", 2], # frost fan
	["AMBER", "STORMCALLER", 3], # chain lightning
]


static func count() -> int:
	return ROSTER.size()


static func wizard_name(w: int) -> String:
	return ROSTER[clampi(w, 0, count() - 1)][0]


static func title(w: int) -> String:
	return ROSTER[clampi(w, 0, count() - 1)][1]


static func start_spell(w: int) -> int:
	return int(ROSTER[clampi(w, 0, count() - 1)][2])


## The next wizard from `current` in direction `dir` (+1 or -1) that nobody in `taken` has, wrapping around.
## Returns `current` when every other wizard is taken.
static func cycle(current: int, dir: int, taken: Array) -> int:
	var w := current
	for _i in count():
		w = wrapi(w + dir, 0, count())
		if w == current or not taken.has(w):
			return w
	return current


## The first wizard nobody in `taken` has, trying `preferred` first (a new player gets their slot's colour).
static func first_free(preferred: int, taken: Array) -> int:
	if not taken.has(preferred):
		return preferred
	for w in count():
		if not taken.has(w):
			return w
	return preferred

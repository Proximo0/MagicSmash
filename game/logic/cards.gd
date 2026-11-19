class_name Cards
extends RefCounted
## Monster cards: one ultra-rare card per kind of monster, kept in the player's collection between runs (Profile)
## and socketed into the wizard's hat, robe or staff for a small lasting bonus. Earned only by play: a card drops
## from a kill (far likelier from an elite or a Lich) and is collected like any pickup. Pure data plus lookups.

## Equipment sockets. A card fits only the socket its row names.
const HAT := 0
const ROBE := 1
const STAFF := 2
const SOCKETS := 3
const SOCKET_NAMES := ["HAT", "ROBE", "STAFF"]

## One row per World enemy type, in World type order: [key, name, socket, Loot.ST_* stat, amount, bonus text,
## line of lore]. Keys are what the save file stores, so keep them when renaming.
const CARDS: Array = [
	["goblin", "THE CUTPURSE", ROBE, Loot.ST_GREED, 0.15, "+15% GOLD", "IT ALWAYS KNOWS WHICH POCKET."],
	["skeleton", "THE SENTINEL", ROBE, Loot.ST_WARD, 0.06, "6% WARD", "IT STILL GUARDS A GATE LONG GONE."],
	["slime", "THE OOZE", ROBE, Loot.ST_VIGOR, 1.0, "+1 HEART", "WHAT IT SWALLOWS, IT KEEPS."],
	["mslime", "THE DROPLET", HAT, Loot.ST_SWIFT, 0.06, "+6% SPEED", "SMALL, QUICK AND EVERYWHERE."],
	["bat", "THE NIGHT WING", HAT, Loot.ST_SWIFT, 0.10, "+10% SPEED", "IT HAS NEVER SEEN THE SUN."],
	["orc", "THE WARCHIEF", STAFF, Loot.ST_MIGHT, 0.10, "+10% DAMAGE", "HE COUNTS HIS VICTORIES IN TEETH."],
	["mage", "THE HEXER", STAFF, Loot.ST_FOCUS, 0.06, "-6% COOLDOWN", "A CURSE FOR EVERY OCCASION."],
	["lich", "THE LICH", STAFF, Loot.ST_MIGHT, 0.20, "+20% DAMAGE", "DEATH WAS ONLY A DOORWAY."],
	["wraith", "THE WRAITH", ROBE, Loot.ST_WARD, 0.10, "10% WARD", "HALF HERE. HALF ELSEWHERE."],
	["tome", "THE GRIMOIRE", HAT, Loot.ST_FOCUS, 0.08, "-8% COOLDOWN", "IT READS YOU BACK."],
	["gargoyle", "THE GARGOYLE", ROBE, Loot.ST_VIGOR, 2.0, "+2 HEARTS", "STONE BY DAY. HUNGRY BY NIGHT."],
	["priest", "THE BONE PRIEST", HAT, Loot.ST_MIGHT, 0.08, "+8% DAMAGE", "HIS SERMONS RAISE THE DEAD."],
]


static func count() -> int:
	return CARDS.size()


static func key(idx: int) -> String:
	return CARDS[idx][0]


static func card_name(idx: int) -> String:
	return CARDS[idx][1]


static func socket(idx: int) -> int:
	return CARDS[idx][2]


static func bonus_text(idx: int) -> String:
	return CARDS[idx][5]


static func lore(idx: int) -> String:
	return CARDS[idx][6]


## The card index for a save-file key, or -1.
static func index_of(k: String) -> int:
	for i: int in range(CARDS.size()):
		if CARDS[i][0] == k:
			return i
	return -1


## The chance that a kill of this enemy drops its card: `base` for a plain kill, times `elite_mul` for an elite;
## a Lich (the boss) always rolls at `boss_chance`. The numbers come from Tuning.
static func drop_chance(enemy_type: int, elite: bool, base: float, elite_mul: float, boss_chance: float) -> float:
	if enemy_type < 0 or enemy_type >= CARDS.size():
		return 0.0
	if CARDS[enemy_type][0] == "lich":
		return boss_chance
	return base * (elite_mul if elite else 1.0)


## Armor stats (Loot.empty_stats layout) that the socketed cards add. `sockets` holds one card index per
## socket, -1 for empty; a card in the wrong socket counts for nothing.
static func socket_stats(sockets: Array) -> Array:
	var stats := Loot.empty_stats()
	for s: int in range(mini(sockets.size(), SOCKETS)):
		var idx := int(sockets[s])
		if idx < 0 or idx >= CARDS.size() or socket(idx) != s:
			continue
		stats[CARDS[idx][3]] = float(stats[CARDS[idx][3]]) + float(CARDS[idx][4])
	return stats

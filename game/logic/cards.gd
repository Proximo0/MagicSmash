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

## One row per card: [key, name, socket, Loot.ST_* stat, amount, bonus text, line of lore, the Bestiary kind whose
## kills drop it (-1: none, a Seal card)]. A card's index is its place here, never an enemy type: Cards.for_enemy
## maps a kind to its card. Keys are what the save file stores, so keep them when renaming.
const CARDS: Array = [
	["goblin", "THE CUTPURSE", ROBE, Loot.ST_GREED, 0.15, "+15% GOLD", "IT ALWAYS KNOWS WHICH POCKET.", Bestiary.GOBLIN],
	["skeleton", "THE SENTINEL", ROBE, Loot.ST_WARD, 0.06, "6% WARD", "IT STILL GUARDS A GATE LONG GONE.", Bestiary.SKELETON],
	["slime", "THE OOZE", ROBE, Loot.ST_VIGOR, 1.0, "+1 HEART", "WHAT IT SWALLOWS, IT KEEPS.", Bestiary.SLIME],
	["mslime", "THE DROPLET", HAT, Loot.ST_SWIFT, 0.06, "+6% SPEED", "SMALL, QUICK AND EVERYWHERE.", Bestiary.MSLIME],
	["bat", "THE NIGHT WING", HAT, Loot.ST_SWIFT, 0.10, "+10% SPEED", "IT HAS NEVER SEEN THE SUN.", Bestiary.BAT],
	["orc", "THE WARCHIEF", STAFF, Loot.ST_MIGHT, 0.10, "+10% DAMAGE", "HE COUNTS HIS VICTORIES IN TEETH.", Bestiary.ORC],
	["mage", "THE HEXER", STAFF, Loot.ST_FOCUS, 0.06, "-6% COOLDOWN", "A CURSE FOR EVERY OCCASION.", Bestiary.MAGE],
	["lich", "THE LICH", STAFF, Loot.ST_MIGHT, 0.20, "+20% DAMAGE", "DEATH WAS ONLY A DOORWAY.", Bestiary.LICH],
	["wraith", "THE WRAITH", ROBE, Loot.ST_WARD, 0.10, "10% WARD", "HALF HERE. HALF ELSEWHERE.", Bestiary.WRAITH],
	["tome", "THE GRIMOIRE", HAT, Loot.ST_FOCUS, 0.08, "-8% COOLDOWN", "IT READS YOU BACK.", Bestiary.TOME],
	["gargoyle", "THE GARGOYLE", ROBE, Loot.ST_VIGOR, 2.0, "+2 HEARTS", "STONE BY DAY. HUNGRY BY NIGHT.", Bestiary.GARGOYLE],
	["priest", "THE BONE PRIEST", HAT, Loot.ST_MIGHT, 0.08, "+8% DAMAGE", "HIS SERMONS RAISE THE DEAD.", Bestiary.PRIEST],
	# The Seal cards (Seals.card): one per Seal, dropped only by that Seal's Archlich and paid on its first win.
	["seal_1", "THE HUNGER", ROBE, Loot.ST_VIGOR, 2.0, "+2 HEARTS", "IT ATE ITS FILL AND WAS STILL EMPTY.", -1],
	["seal_2", "THE AMBUSH", HAT, Loot.ST_SWIFT, 0.12, "+12% SPEED", "THE DOOR WAS NEVER WHERE YOU LOOKED.", -1],
	["seal_3", "THE FAMINE", ROBE, Loot.ST_GREED, 0.40, "+40% GOLD", "THE TOWER'S GRANARIES ARE DUST.", -1],
	["seal_4", "THE LEGION", STAFF, Loot.ST_MIGHT, 0.25, "+25% DAMAGE", "WE ARE MANY. WE ARE ONE.", -1],
	["seal_5", "THE CHAMPION", ROBE, Loot.ST_WARD, 0.15, "15% WARD", "IT NEVER WALKS ALONE.", -1],
	["seal_6", "MISFORTUNE", HAT, Loot.ST_FOCUS, 0.12, "-12% COOLDOWN", "THE DECK WAS MARKED BEFORE YOU SAT.", -1],
	["seal_7", "THE SILENCE", STAFF, Loot.ST_FOCUS, 0.15, "-15% COOLDOWN", "NO SPELL IS SPOKEN HERE TWICE.", -1],
	["seal_8", "THE DARKNESS", STAFF, Loot.ST_MIGHT, 0.35, "+35% DAMAGE", "BEYOND THE LAST SEAL, NOTHING.", -1],
]
const C_ENEMY := 7


static func count() -> int:
	return CARDS.size()


static func key(idx: int) -> String:
	return CARDS[idx][0]


## The Bestiary kind whose kills drop card `idx`, or -1 (a Seal card, dropped only by its Archlich).
static func enemy(idx: int) -> int:
	return int(CARDS[idx][C_ENEMY]) if idx >= 0 and idx < CARDS.size() else -1


## The card a kill of Bestiary kind `type` can drop, or -1 when the kind has none.
static func for_enemy(type: int) -> int:
	if type < 0:
		return -1
	for i: int in range(CARDS.size()):
		if int(CARDS[i][C_ENEMY]) == type:
			return i
	return -1


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


## The chance that a kill of this enemy kind drops its card (for_enemy; 0 for a kind with none): `base` for a
## plain kill, times `elite_mul` for an elite; a Lich (the boss) always rolls at `boss_chance`. Numbers from Tuning.
static func drop_chance(enemy_type: int, elite: bool, base: float, elite_mul: float, boss_chance: float) -> float:
	var idx := for_enemy(enemy_type)
	if idx < 0:
		return 0.0
	if CARDS[idx][0] == "lich":
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

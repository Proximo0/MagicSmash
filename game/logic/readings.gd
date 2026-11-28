class_name Readings
extends RefCounted
## The Reading: sixteen Minor Arcana, one of which a table keeps before a run to change that run's rules
## (docs/content_list.md § 42). Pure data plus the deal and the vote: World.apply_reading merges a row's values into
## the run after the Seal's (MERGE_MUL multiply the seal_* fields, MERGE_ADD add), and every other key sets the
## World field read_<key>, which the row's rule reads. This file is the data file for the Reading's numbers.
## A boss is a foe: a row that says FOES names both `hp` and `boss`. EIGHT OF WANDS is one number, the run's clock.

## Columns of a row.
const KEY := 0
const NAME := 1
const WORDS := 2
const PARTY := 3
const VALUES := 4
## What the card says at the table: at most WORD_LINES lines of at most WORD_WIDTH letters.
const WORD_LINES := 3
const WORD_WIDTH := 18
## Keys a Reading shares with Seals.BASE: these multiply the Seal's value (seal_<key>) ...
const MERGE_MUL := ["hp", "horde", "boss", "speed", "potions"]
## ... and these add to it (hearts every wizard starts with).
const MERGE_ADD := ["hearts"]
## Readings with a rule that is not on main yet (job R2; a key leaves the list in the change that builds its rule).
## `deal` never deals one and the coverage robot plans it as unbuilt; the stage's gate asserts the list is empty.
const UNBUILT: Array[String] = ["r_wands_1", "r_wands_4", "r_wands_8", "r_wands_10", "r_cups_2", "r_cups_5", "r_cups_9",
	"r_swords_1", "r_swords_3", "r_swords_7", "r_swords_10", "r_pent_1", "r_pent_4", "r_pent_9", "r_pent_10"]

## [key, name, words, party only, values], in § 42's order.
const ROWS: Array = [
	["r_wands_1", "ACE OF WANDS", "START WITH A\nSECOND SPELL", false,
		{"spell2": true}],
	["r_wands_4", "FOUR OF WANDS", "AN APPRENTICE\nJOINS. FULL TABLE:\n+1 HEART EACH", false,
		{"apprentice": true, "full_hearts": 1}],
	["r_wands_8", "EIGHT OF WANDS", "ALL IS A FIFTH\nFASTER, XP TOO", false,
		{"pace": 1.2}],
	["r_wands_10", "TEN OF WANDS", "5 SPELL SLOTS AND\n2 ARCANA SLOTS\nFROM THE START", false,
		{"slots": [5, 2]}],
	["r_cups_1", "ACE OF CUPS", "EVERY WIZARD HAS\n+2 HEARTS", false,
		{"hearts": 2}],
	["r_cups_2", "TWO OF CUPS", "A HIT TAKES ITS\nHEART FROM WHO\nHOLDS THE MOST", true,
		{"bond": true}],
	["r_cups_5", "FIVE OF CUPS", "NO POTIONS. BOSS\nPHASES AND DEATHS\nHEAL ALL TO FULL", false,
		{"no_potions": true, "boss_heal": true}],
	["r_cups_9", "NINE OF CUPS", "FIRST TWO HANDS\nARCANA ONLY,\nFREE REDRAWS", false,
		{"arcana_hands": 2, "free_redraws": true}],
	["r_swords_1", "ACE OF SWORDS", "+2 NOVAS, REFILLED\nWHEN A BOSS COMES", false,
		{"novas": 2, "nova_refill": true}],
	["r_swords_3", "THREE OF SWORDS", "HEARTS CAPPED AT 3\nALL DAMAGE X1.6", false,
		{"heart_cap": 3, "damage": 1.6}],
	["r_swords_7", "SEVEN OF SWORDS", "ELITES TWICE AS\nOFTEN, EACH DROPS\nA PARTY TOME", false,
		{"elite_rate": 2.0, "elite_tome": true}],
	["r_swords_10", "TEN OF SWORDS", "SWORD FOES AT 1:00\nHORDE A FIFTH MORE\nXP X1.3", false,
		{"swords_from": 60.0, "horde": 1.2, "xp": 1.3}],
	["r_pent_1", "ACE OF PENTACLES", "START WITH 150\nGOLD, A SHRINE AT\nTHE DOOR", false,
		{"gold": 150, "door_shrine": true}],
	["r_pent_4", "FOUR OF PENTACLES", "NO SHRINES. EACH\n100 GOLD PICKED UP\nHEALS A HEART", false,
		{"no_shrines": true, "gold_heal": 100}],
	["r_pent_9", "NINE OF PENTACLES", "CHESTS HOLD TWO\nITEMS. FOES HAVE\nA FIFTH MORE HP", false,
		{"chest_items": 2, "hp": 1.2, "boss": 1.2}],
	["r_pent_10", "TEN OF PENTACLES", "PLAY THE NEXT\nSTEP, FOR DOUBLE\nCRYSTALS", false,
		{"next_step": true, "crystals": 2.0}],
]


## The row's index in ROWS (the header's W_READING), -1 for "" or a key it does not hold.
static func index_of(key: String) -> int:
	if key == "":
		return -1
	for i: int in range(ROWS.size()):
		if ROWS[i][KEY] == key:
			return i
	return -1


## A copy of the row's values, {} for "" or a key it does not hold.
static func values(key: String) -> Dictionary:
	var i := index_of(key)
	if i < 0:
		return {}
	return (ROWS[i][VALUES] as Dictionary).duplicate(true)


## Whether the card is dealt only to a table of two or more seats (an apprentice counts).
static func party_only(key: String) -> bool:
	var i := index_of(key)
	return i >= 0 and bool(ROWS[i][PARTY])


## n different keys drawn with rng from the rows open (key -> true), PARTY cards only when seats >= 2, never a row
## of `unbuilt`; fewer when fewer exist. Draws from its own rng (never the World's): the same rng state and
## arguments give the same hand.
static func deal(rng: RandomNumberGenerator, open: Dictionary, seats: int, n: int,
		unbuilt: Array[String] = UNBUILT) -> Array[String]:
	var pool: Array[String] = []
	for row: Array in ROWS:
		var key: String = row[KEY]
		if not bool(open.get(key, false)) or unbuilt.has(key):
			continue
		if bool(row[PARTY]) and seats < 2:
			continue
		pool.append(key)
	var out: Array[String] = []
	for i: int in range(mini(n, pool.size())):
		var j := rng.randi_range(i, pool.size() - 1)
		var pick := pool[j]
		pool[j] = pool[i]
		pool[i] = pick
		out.append(pick)
	return out


## The hand index the table keeps: votes[i] is seat i's pick (-1 abstains). Most votes wins; a tie goes to seat 1's
## pick when it is among the tied, else to the lowest tied index; nobody voting keeps 0.
static func vote(votes: Array, seats: int) -> int:
	var counts := {}
	var best := 0
	for i: int in range(mini(seats, votes.size())):
		var v := int(votes[i])
		if v < 0:
			continue
		counts[v] = int(counts.get(v, 0)) + 1
		best = maxi(best, int(counts[v]))
	if counts.is_empty():
		return 0
	var first := int(votes[0])
	if counts.has(first) and int(counts[first]) == best:
		return first
	var low := -1
	for v: int in counts:
		if int(counts[v]) == best and (low < 0 or v < low):
			low = v
	return low

class_name GameNames
extends RefCounted
## Names and numbers the screens print, mirrored from the rules and the Rust tables (realm/core tables, realm/loot
## tables and smith). The server judges everything; these only say what a thing is called and what it will cost.
## Where a number comes from is written beside it.

const CLASSES: Array[String] = ["NOVICE", "KNIGHT", "MAGE", "ARCHER", "PRIEST", "PALADIN"]
const RACES: Array[String] = ["HUMAN", "ELF", "DWARF", "ORC"]
const RACE_NOTES: Array[String] = ["+1 to all six, +5% class XP", "SWIFT +4, FOCUS +3", "VIGOR +4, WARD +3, pushed half as far", "MIGHT +5, VIGOR +2, +10% damage under 30% health"]
const CLASS_ROLES: Array[String] = ["none", "tank", "damage", "ranged", "healer", "tank and support"]
const CLASS_WEAPONS: Array[String] = ["DIRK", "CLEAVE", "FIREBALL", "LONGBOW", "HOLY LIGHT", "SMITE"]
const CLASS_NOTES: Array[String] = [
	"Everyone starts here",
	"Pushed half as far. Cleaves in a wide arc",
	"Draws show four cards. Fireball bursts",
	"Walks 8% faster. Arrows pierce four",
	"Raises in half the time. Heals as she strikes",
	"Allies within 100 px take 8% less. Smite drops from above"]
## Stat points a race gives (rules section 2), in the order of STATS.
const RACE_BONUS: Array = [[1, 1, 1, 1, 1, 1], [0, 3, 4, 0, 0, 0], [0, 0, 0, 4, 3, 0], [5, 0, 0, 2, 0, 0]]
const STATS: Array[String] = ["MIGHT", "FOCUS", "SWIFT", "VIGOR", "WARD", "FORTUNE"]
const STAT_NOTES: Array[String] = ["+2% damage", "+1% attack speed", "+1% move speed (cap 40%)", "+2% health", "-1% damage taken (cap 60%)", "+3% coin, +1 luck"]
const RARITIES: Array[String] = ["COMMON", "UNCOMMON", "RARE", "EPIC", "RELIC"]
const SLOTS: Array[String] = ["WEAPON", "HEAD", "BODY", "HANDS", "FEET", "CHARM"]
const FIELDS: Array[String] = ["THE FOOL'S ROAD", "THE HANGED WOOD", "THE MOON MARSH", "THE HERMIT'S PEAKS", "THE TOWER", "THE WORLD'S EDGE"]
## Each field's level range (rules section 6).
const FIELD_LEVELS: Array[Vector2i] = [Vector2i(1, 10), Vector2i(10, 20), Vector2i(20, 30), Vector2i(30, 40), Vector2i(40, 50), Vector2i(50, 60)]
const FIELD_BOSSES: Array[String] = ["THE HARVESTER", "THE HANGING TREE", "MOTHER OF LEECHES", "THE GOAT PROPHET", "THE CHANDELIER AND THE GHOSTWRITER", "THE UNMADE KING"]
const BOSSES: Array[String] = ["THE HARVESTER", "THE HANGING TREE", "MOTHER OF LEECHES", "THE GOAT PROPHET", "THE CHANDELIER", "THE GHOSTWRITER", "THE UNMADE KING", "DEATH, THE PALE RIDER"]
const FIELD_MATERIALS: Array[String] = ["PLAGUE LINEN", "GALLOWS OAK", "BOG IRON", "RUNE SLATE", "STAINED GLASS", "ASH GLASS"]
const GEAR_VARIANTS: Array = [
	["DIRK", "CLEAVER", "STAFF", "LONGBOW", "CENSER", "MACE"],
	["COWL", "HELM", "CROWN"],
	["ROBE", "MAIL", "COAT"],
	["GLOVES", "GAUNTLETS", "WRAPS"],
	["BOOTS", "GREAVES", "SANDALS"],
	["TALISMAN", "RING", "AMULET"]]
const GEAR_TIERS: Array[String] = ["PILGRIM'S", "HANGED", "BOG", "HERMIT'S", "GILDED", "ASHEN"]
const POTIONS: Array[String] = ["HEALING DRAUGHT", "VEIL OF ASH", "WHETSTONE OIL", "SCHOLAR'S INK", "GAMBLER'S COIN", "PHOENIX ASH"]
const POTION_NOTES: Array[String] = ["heals 35%", "unseen for a while", "sharper blows", "more field XP", "more coin", "rise again at 30%"]
## What a merchant asks per potion (gateway.rs `potion_price`).
const POTION_PRICES: Array[int] = [20, 60, 60, 120, 120, 400]
const NO_JOB: int = 15
const JOBS: Array[String] = ["WARDEN", "BERSERKER", "ARCHMAGE", "HEXER", "RANGER", "SHARPSHOOTER", "ORACLE", "INQUISITOR", "TEMPLAR", "CRUSADER"]
const JOB_NOTES: Array[String] = [
	"tank: threat 2.6, PROVOKE pulls monsters inward", "damage: more damage as health falls",
	"damage: FIREBALL bursts a second time", "support: cursed monsters take 15% more",
	"ranged: pierce 8, 10% faster", "damage: reach +25%, +30% to elites and bosses",
	"healer: heals also shield the ally under 30%", "damage: HOLY LIGHT doubled, healing halved",
	"tank: the aura grows to 14%, 140 px", "damage: more damage near allies"]
const JOB_ULTIMATES: Array[String] = ["RAMPART", "BLOOD RAGE", "CATACLYSM", "PLAGUE", "HAIL", "DEADEYE", "BENEDICTION", "PYRE", "MARTYR", "CRUSADE"]
## Skill ids (the core's SKILLS table) of each class: skill 1, skill 2.
const CLASS_SKILLS: Array = [[0, -1], [1, 2], [3, 4], [5, 6], [7, 8], [9, 10]]
## Levels: skill 1 at 10 (the novice's at 1), skill 2 at 25, job and ultimate at 40.
const SKILL1_LEVEL: int = 10
const SKILL2_LEVEL: int = 25
const JOB_LEVEL: int = 40
const MAX_LEVEL: int = 60
const DECK_SIZE: int = 20
const DECK_CARDS: int = 30
const NOVICE_CARDS: int = 12
const MAX_COPIES: int = 5
## Card effects per copy (rules section 5), the deck card 0..29 (the core's card id is this + 1).
const CARD_TEXT: Array[String] = [
	"+10% damage", "+6% move speed", "+8% attack speed", "+10% health, heals that much", "regains 0.5% health a second",
	"+12% attack size", "+10% weapon reach", "skill cooldowns 8% shorter", "+10% coin", "+8% field XP",
	"takes 5% less damage", "returns 20% of contact damage", "every 5th attack hits twice", "+25% damage under 30% health",
	"+18% damage, takes 6% more", "5% of hits strike double", "allies within 100 px deal 3% more", "heals 1% of damage dealt",
	"+15% damage to elites and bosses", "raises allies 25% faster", "+12% damage in a tide", "+1 pierce or target, else +8% damage",
	"attacks push 6 px farther", "potions restore 20% more", "ultimate cooldown 10% shorter", "+20% damage with no ally near",
	"+4% damage per ally near", "downed: bursts 160 px for 300", "the haul loses a tenth less", "+15% move speed after a kill"]
const SOCKET_PLACES: Array[String] = ["", "BAG", "WORN", "BANK", "MAIL"]
const PLACE_BAG: int = 1
const PLACE_WORN: int = 2
const PLACE_BANK: int = 3
const PLACE_MAIL: int = 4
const BAG_SLOTS: int = 40
const BANK_SLOTS: int = 100
const KIND_COIN: int = 1
const KIND_EMBERS: int = 1000
const RUNE_GRADES: Array[String] = ["I", "II", "III"]
## Rune points per grade (loot tables `RUNE_POINTS`).
const RUNE_POINTS: Array[int] = [2, 4, 7]
const FUSE_COIN: Array[int] = [100, 400]
const FUSE_COUNT: int = 3

# The smith's price list (realm/loot tables.rs and smith.rs).
const SALVAGE_RARITY_MUL: Array[int] = [1, 2, 4, 8, 16]
const SALVAGE_LEVEL_DIV: int = 10
const SALVAGE_PLUS_PCT: int = 10
const UPGRADE_EMBER_BASE: int = 2
const UPGRADE_EMBER_LEVEL_DIV: int = 3
const UPGRADE_COIN_PER_LEVEL: int = 4
const UPGRADE_SUCCESS_PCT: Array[int] = [100, 100, 100, 100, 100, 80, 65, 50, 40, 30]
const PLUS_MAX: int = 10
const REROLL_EMBER_BASE: int = 6
const REROLL_EMBER_LEVEL_DIV: int = 2
const REROLL_COIN_PER_LEVEL: int = 30
const SOCKET_COIN_PER_LEVEL: int = 10
const UNSOCKET_COIN_PER_LEVEL: int = 25
## What a merchant pays (gateway.rs `sell_price`).
const SELL_BY_RARITY: Array[int] = [1, 2, 5, 12, 40]

const LOOK_PALETTES: Array[Color] = [
	Color(1, 1, 1), Color(0.82, 0.74, 0.7), Color(0.62, 0.7, 0.9), Color(0.78, 0.92, 0.74), Color(0.9, 0.7, 0.9), Color(0.7, 0.62, 0.52)]
const LOOK_PALETTE_NAMES: Array[String] = ["NATIVE", "ASHEN", "DUSK", "MOSS", "PLUM", "RUST"]
const LOOK_MARKS: Array[String] = ["NONE", "SCAR", "SIGIL", "CROWN"]


static func class_name_of(c: int) -> String:
	return CLASSES[clampi(c, 0, CLASSES.size() - 1)]


static func race_name_of(r: int) -> String:
	return RACES[clampi(r, 0, RACES.size() - 1)]


static func job_name_of(j: int) -> String:
	return JOBS[j] if j >= 0 and j < JOBS.size() else "NONE"


## A look is palette (bits 0..7) and mark (bits 8..15); the field draws by class and race only.
static func look_of(palette: int, mark: int) -> int:
	return (palette & 0xFF) | ((mark & 0xFF) << 8)


static func look_palette(look: int) -> int:
	return clampi(look & 0xFF, 0, LOOK_PALETTES.size() - 1)


static func look_mark(look: int) -> int:
	return clampi((look >> 8) & 0xFF, 0, LOOK_MARKS.size() - 1)


static func base_name(base: int) -> String:
	if HomeMap.is_thing(base):
		return HomeMap.thing_name(base)
	var slot: int = base / 100
	var tier: int = (base / 10) % 10
	var variant: int = base % 10
	if slot < GEAR_VARIANTS.size() and tier < GEAR_TIERS.size() and variant < (GEAR_VARIANTS[slot] as Array).size():
		return "%s %s" % [GEAR_TIERS[tier], GEAR_VARIANTS[slot][variant]]
	return "BASE %d" % base


## The core's card id (1..30) is the deck card + 1.
static func card_name(card: int) -> String:
	var s: String = RealmLink.card_name(card + 1)
	return s if not s.is_empty() else "CARD %d" % card


static func monster_card_name(n: int) -> String:
	if n < RealmLink.kind_count():
		var nm: String = String(RealmLink.kind_info(n).get("name", "?")).to_upper()
		return "CARD OF " + nm.trim_prefix("THE ")
	var b: int = n - RealmLink.kind_count()
	return "CARD OF " + (BOSSES[b] if b >= 0 and b < BOSSES.size() else str(n))


## What a stack kind is called (store.md: coin 1, potion 100+p, material 1000+m, rune 2000+stat*10+grade,
## key 3000+field, page 4000+card, monster card 5000+card).
static func stack_name(kind: int) -> String:
	if kind == KIND_COIN:
		return "COIN"
	if kind >= 100 and kind < 200:
		var p: int = kind - 100
		return POTIONS[p] if p < POTIONS.size() else "POTION %d" % p
	if kind >= 1000 and kind < 2000:
		var m: int = kind - 1000
		if m == 0:
			return "EMBERS"
		if m >= 1 and m <= 6:
			return FIELD_MATERIALS[m - 1]
		if m >= 10 and m < 18:
			return "TROPHY OF " + BOSSES[m - 10]
		return "MATERIAL %d" % m
	if kind >= 2000 and kind < 3000:
		var stat: int = (kind - 2000) / 10
		var grade: int = (kind - 2000) % 10
		return "RUNE OF %s %s" % [STATS[clampi(stat, 0, 5)], RUNE_GRADES[clampi(grade - 1, 0, 2)]]
	if kind >= 3000 and kind < 3100:
		var f: int = kind - 3000
		return "VAULT KEY (%s)" % (FIELDS[f] if f < FIELDS.size() else str(f))
	if kind >= 4000 and kind < 4100:
		return "PAGE OF " + card_name(kind - 4000).trim_prefix("THE ")
	if kind >= 5000 and kind < 10000:
		return monster_card_name(kind - 5000)
	return "STACK %d" % kind


static func rune_kind(stat: int, grade: int) -> int:
	return 2000 + stat * 10 + grade


static func is_socketable(kind: int) -> bool:
	return (kind >= 2000 and kind < 3000) or (kind >= 5000 and kind < 10000)


## One socketable's effect: [stat, points] (a rune: its grade's points; a monster card: the rules' formula).
static func socket_points(kind: int) -> Array:
	if kind >= 2000 and kind < 3000:
		var stat: int = (kind - 2000) / 10
		var grade: int = (kind - 2000) % 10
		return [stat, RUNE_POINTS[clampi(grade - 1, 0, 2)]]
	if kind >= 5000 and kind < 10000:
		# Monster cards (loot cards.rs): a kind's card 3 + 2 x field points, a boss's 16 + 4 x field.
		var n: int = kind - 5000
		var kinds: int = RealmLink.kind_count()
		if n < kinds:
			var info: Dictionary = RealmLink.kind_info(n)
			return [_card_stat(int(info.get("beh", 0))), 3 + 2 * int(info.get("field", 0))]
		var b: int = n - kinds
		const BOSS_STAT: Array[int] = [0, 3, 3, 4, 1, 2, 0, 5]
		const BOSS_FIELD: Array[int] = [0, 1, 2, 3, 4, 4, 5, 5]
		if b >= 0 and b < 8:
			return [BOSS_STAT[b], 16 + 4 * BOSS_FIELD[b]]
	return [0, 0]


## The stat a kind's card gives: the first behaviour it has, in the loot crate's order (cards.rs STAT_BY_BEHAVIOUR).
static func _card_stat(beh: int) -> int:
	const ORDER: Array[Array] = [[1 << 10, 5], [1 << 11, 3], [1 << 13, 3], [1 << 3, 3], [1 << 4, 4], [1 << 12, 4], [1 << 7, 1], [1 << 8, 1], [1 << 9, 2], [1 << 2, 2], [1 << 1, 2], [1 << 5, 0], [1 << 0, 0]]
	for row in ORDER:
		if beh & int(row[0]) != 0:
			return int(row[1])
	return 0


static func rarity_colour(r: int) -> Color:
	const C: Array[Color] = [Color(0.75, 0.72, 0.66), Color(0.5, 0.78, 0.5), Color(0.4, 0.62, 0.95), Color(0.72, 0.45, 0.92), Color(0.95, 0.55, 0.2)]
	return C[clampi(r, 0, 4)]


static func item_name(it: Dictionary) -> String:
	var s: String = base_name(int(it["base"]))
	if int(it.get("plus", 0)) > 0:
		s += " +%d" % int(it["plus"])
	return s


# ---- the smith's prices

static func salvage_embers(it: Dictionary) -> int:
	var base: int = (1 + int(it["level"]) / SALVAGE_LEVEL_DIV) * SALVAGE_RARITY_MUL[int(it["rarity"])]
	return base * (100 + SALVAGE_PLUS_PCT * int(it.get("plus", 0))) / 100


## [embers, coin] of the next step, or [] at +10.
static func upgrade_cost(it: Dictionary) -> Array:
	var plus: int = int(it.get("plus", 0))
	if plus >= PLUS_MAX:
		return []
	var s: int = plus + 1
	var l: int = int(it["level"])
	return [(UPGRADE_EMBER_BASE + l / UPGRADE_EMBER_LEVEL_DIV) * s, UPGRADE_COIN_PER_LEVEL * l * s * s]


static func upgrade_chance(it: Dictionary) -> int:
	return UPGRADE_SUCCESS_PCT[mini(int(it.get("plus", 0)), PLUS_MAX - 1)]


static func reroll_cost(it: Dictionary) -> Array:
	var l: int = int(it["level"])
	var r: int = int(it["rarity"]) + 1
	return [(REROLL_EMBER_BASE + l / REROLL_EMBER_LEVEL_DIV) * r * (10 + int(it.get("plus", 0))) / 10, REROLL_COIN_PER_LEVEL * l * r]


static func sell_price(it: Dictionary) -> int:
	return 2 * (1 + int(it["level"]) / 4) * SELL_BY_RARITY[int(it["rarity"])]


# ---- the hero

## XP to reach the next class level is a table in the core; the shell only shows the XP total.
static func skill_rank(class_level: int, skill_level: int) -> int:
	return mini(1 + (class_level - skill_level) / 10, 5)


static func skill_name(id: int) -> String:
	return String(RealmLink.skill_info(id).get("name", "?"))


## What the hero has at her class level: [name, level needed, rank (0 = locked), note].
static func class_skills(cls: int, job: int, level: int) -> Array:
	var out: Array = []
	var ids: Array = CLASS_SKILLS[clampi(cls, 0, 5)]
	var first: int = SKILL1_LEVEL if cls != 0 else 1
	if int(ids[0]) >= 0:
		out.append([skill_name(int(ids[0])), first, 0 if level < first else skill_rank(level, first), "Skill 1"])
	if int(ids[1]) >= 0:
		out.append([skill_name(int(ids[1])), SKILL2_LEVEL, 0 if level < SKILL2_LEVEL else skill_rank(level, SKILL2_LEVEL), "Skill 2"])
	if job >= 0 and job < JOBS.size():
		out.append([JOB_ULTIMATES[job], JOB_LEVEL, 0 if level < JOB_LEVEL else skill_rank(level, JOB_LEVEL), "Ultimate of the " + JOBS[job]])
	elif cls != 0:
		out.append(["ULTIMATE", JOB_LEVEL, 0, "Choose a job at %d" % JOB_LEVEL])
	return out


## The two jobs of a class (indexes into JOBS): knights 0 1, mages 2 3, archers 4 5, priests 6 7, paladins 8 9.
static func class_jobs(cls: int) -> Array[int]:
	if cls < 1 or cls > 5:
		return []
	return [(cls - 1) * 2, (cls - 1) * 2 + 1]


static func commas(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	var i: int = s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	return ("-" if n < 0 else "") + s.substr(0, i) + out


const NAME_HEADS: Array[String] = ["MOR", "GRIM", "ASH", "VEX", "KORR", "SABLE", "THORN", "NYX", "BRAN", "CRYPT", "HOLLOW", "RAVEN", "WYRD", "DUSK", "ELDR", "MALA"]
const NAME_TAILS: Array[String] = ["WEN", "HILD", "MORE", "IC", "OTH", "ANE", "WICK", "GAR", "LITH", "VEN", "MIR", "UND"]


## A themed starting name that the builder accepts (3 to 16 letters, the first a letter): "GRIMWEN". Not part of
## the sim, so any RNG will do; the caller passes its own so a test can seed it.
static func themed_name(rng: RandomNumberGenerator) -> String:
	return NAME_HEADS[rng.randi() % NAME_HEADS.size()] + NAME_TAILS[rng.randi() % NAME_TAILS.size()]


## A themed account name for the dev login: a head, a tail and four digits ("ASHWICK4821"), at most 16 characters.
static func themed_account(rng: RandomNumberGenerator) -> String:
	return themed_name(rng) + str(1000 + rng.randi() % 9000)

class_name Achievements
extends RefCounted
## The Book of Deeds: the catalogue of achievements and which ones a finished run earns. Pure data plus a rule per
## deed, read from the run's Results record and a small `party` dictionary. The Platform autoload unlocks them on
## Steam (the host's account: with Remote Play Together only the host runs the game), and Profile keeps the earned
## ones (`deeds`), pays their crystals once and shows them in the Sanctum's Book of Deeds. The API names must match
## the Steamworks admin page for the Steam ones (the first 14); the rest live in the Book alone until added there.

## [api name, display name, description, crystals paid once, secret (shows as ??? until earned; optional)].
## Append new ones at the end: the Steam names and the save file's names never change.
const LIST: Array = [
	["ARCHLICH", "THE LAST LICH", "Slay the Archlich and win a run.", 50],
	["SOLO_WIN", "LONE WIZARD", "Win a run alone.", 30],
	["PARTY_WIN", "FULL TOWER", "Win a run with four wizards.", 25],
	["FLAWLESS", "UNTOUCHED", "Win a run without any wizard losing a life.", 40],
	["LICH", "LICH BANE", "Slay the Lich Lord.", 15],
	["TEN_MINUTES", "HOLD THE TOWER", "Survive for 10 minutes.", 10],
	["BLESSED", "BLESSED BE", "Draw The Sun for the whole party at the fate card.", 5],
	["CURSED", "WORTH IT", "Draw Death for the whole party at the fate card.", 5, true],
	["JACKPOT", "JACKPOT", "Hit the jackpot at a rune altar.", 10],
	["ULTRA", "ULTRA RARE", "Find ultra rare loot in a chest.", 50],
	["EVOLVE", "EVOLUTION", "Evolve a spell.", 10],
	["COMBO_200", "TOTAL SORCERY", "Chain a 200 kill combo.", 20],
	["SEAL", "THE KEY OF SOLOMON", "Evolve Rune Circle into the Seal of Solomon.", 25, true],
	["OMENS", "OMEN-PROOF", "Survive all three omens.", 20],
	["WIN_MAGE", "THE MAGICIAN", "Win a run with a Mage among the players.", 10],
	["WIN_KNIGHT", "THE CHARIOT", "Win a run with a Knight among the players.", 10],
	["WIN_ARCHER", "THE HERMIT'S AIM", "Win a run with an Archer among the players.", 10],
	["WIN_PRIEST", "THE HIEROPHANT", "Win a run with a Priest among the players.", 10],
	["WIN_PALADIN", "STRENGTH", "Win a run with a Paladin among the players.", 10],
	["WIN_HUMAN", "ALL TOO HUMAN", "Win a run with a Human among the players.", 10],
	["WIN_ELF", "LONG IN THE TOOTH", "Win a run with an Elf among the players.", 10],
	["WIN_DWARF", "DEEP AND STUBBORN", "Win a run with a Dwarf among the players.", 10],
	["WIN_ORC", "POLITE FURY", "Win a run with an Orc among the players.", 10],
	["TRINITY", "BALANCED READING", "Win a run with a tank, a healer and a ranged hero among the players.", 20],
	["EVO_ARCANE", "STRAIGHT AND NARROW", "Evolve Arcane Bolt into Astral Lance.", 15],
	["EVO_FIRE", "FIRE AND LIGHTNING", "Evolve Fireball into Thunderfire.", 15],
	["EVO_FROST", "WHITEOUT", "Evolve Frost Fan into Blizzard.", 15],
	["EVO_STORM", "THE PERFECT STORM", "Evolve Chain Lightning into Tempest.", 15],
	["EVO_STAR", "THE STARS ALIGN", "Evolve Starfall into Comet Rain.", 15],
	["EVO_BONE", "TO THE MARROW", "Evolve Bone Spear into Ossuary Lance.", 15],
	["EVO_CANDLE", "LET THERE BE MORE LIGHT", "Evolve Vigil Candle into Consecration.", 15],
	["BOSS_CHANDELIER", "BRING DOWN THE HOUSE", "Slay the Bone Chandelier.", 15],
	["BOSS_GHOSTWRITER", "THE LAST WORD", "Slay the Ghost Writer.", 15],
	["WIN_ARCHMAGE", "THE UPPER SHELF", "Win a run at Archmage.", 20],
	["WIN_SEAL_1", "FIRST SEAL BROKEN", "Win a run at Seal I.", 25],
	["WIN_SEAL_2", "SECOND SEAL BROKEN", "Win a run at Seal II.", 30],
	["WIN_SEAL_3", "THIRD SEAL BROKEN", "Win a run at Seal III.", 30],
	["WIN_SEAL_4", "FOURTH SEAL BROKEN", "Win a run at Seal IV.", 35],
	["WIN_SEAL_5", "FIFTH SEAL BROKEN", "Win a run at Seal V.", 40],
	["WIN_SEAL_6", "SIXTH SEAL BROKEN", "Win a run at Seal VI.", 45],
	["WIN_SEAL_7", "SEVENTH SEAL BROKEN", "Win a run at Seal VII.", 50],
	["WIN_SEAL_8", "THE LAST SEAL", "Win a run at Seal VIII.", 50, true],
	["REVIVE_3", "SECOND WIND", "Raise 3 fallen allies in one run.", 10],
	["REVIVE_25", "UNIONISED DEAD", "Raise 25 fallen allies over all your runs.", 20],
	["KILLS_1K", "BODY COUNT", "Slay 1,000 foes over all your runs.", 10],
	["KILLS_10K", "MASS GRAVE", "Slay 10,000 foes over all your runs.", 25],
	["KILLS_100K", "THE LONG HARVEST", "Slay 100,000 foes over all your runs.", 50],
	["HERO_10", "JOURNEYMAN", "Raise a hero to class level 10.", 15],
	["ALL_CARDS", "THE FULL DECK", "Collect every monster card.", 40],
	["ALL_SECRETS", "NOTHING LEFT UNSAID", "Find every secret in the game.", 30, true],
	["APPRENTICES", "THE MASTER'S HAND", "Win a run with only apprentices beside you.", 20, true],
	["FAST_WIN", "ON SCHEDULE", "Win a run with four heroes before 16:30.", 30],
	["EVO_CLEAVE", "WIDDERSHINS", "Evolve Cleave into Whirlwind.", 15],
	["FIRST_CARD", "THE QUERENT", "Find your first monster card.", 25],
]

const C_API := 0
const C_NAME := 1
const C_DESC := 2
const C_CRYSTALS := 3
const C_SECRET := 4

const TEN_MINUTES := 600.0
const COMBO_DEED := 200
## The runs that count as fast: a win in under this many seconds with FAST_PARTY heroes.
const FAST_SECONDS := 990.0
const FAST_PARTY := 4
const PARTY_SIZE := 4
## Allies raised in one run for REVIVE_3.
const REVIVES_RUN := 3
## A hero's class level for HERO_10.
const HERO_LEVEL := 10

## Most lines the results screen gives the cards found and deeds earned in a run; a longer list ends in "+K MORE".
const RESULT_LINES := 3

## The rules of the deeds past the first 14: api name -> [kind, argument]. Kinds (what `earned` checks):
## win_class: won with this Classes index in the party. win_race: the same for a Races index. trinity: won with a
## tank, a healer and a ranged hero. evo: the Spells index whose evolution was taken. boss: a Bestiary type slain
## (an act boss moment). seal: won at this Seals step or above. revives_run, revives_all, kills_all, hero_level:
## at least the argument of that count. cards: every monster card found (party's monster_cards, the Seal cards left
## out; argument unused). secrets: every one found (argument unused). some_cards: at least the
## argument of monster cards found. apprentices: won with
## one human and only apprentices beside them. fast: won with at least FAST_PARTY heroes in under the argument seconds.
const RULES := {
	"WIN_MAGE": ["win_class", Classes.MAGE],
	"WIN_KNIGHT": ["win_class", Classes.KNIGHT],
	"WIN_ARCHER": ["win_class", Classes.ARCHER],
	"WIN_PRIEST": ["win_class", Classes.PRIEST],
	"WIN_PALADIN": ["win_class", Classes.PALADIN],
	"WIN_HUMAN": ["win_race", Races.HUMAN],
	"WIN_ELF": ["win_race", Races.ELF],
	"WIN_DWARF": ["win_race", Races.DWARF],
	"WIN_ORC": ["win_race", Races.ORC],
	"TRINITY": ["trinity", 0],
	"EVO_ARCANE": ["evo", World.SP_ARCANE],
	"EVO_FIRE": ["evo", World.SP_FIRE],
	"EVO_FROST": ["evo", World.SP_FROST],
	"EVO_STORM": ["evo", World.SP_STORM],
	"EVO_STAR": ["evo", World.SP_STAR],
	"EVO_BONE": ["evo", World.SP_BONE],
	"EVO_CANDLE": ["evo", World.SP_CANDLE],
	"EVO_CLEAVE": ["evo", World.SP_CLEAVE],
	"BOSS_CHANDELIER": ["boss", Bestiary.CHANDELIER],
	"BOSS_GHOSTWRITER": ["boss", Bestiary.GHOSTWRITER],
	"WIN_ARCHMAGE": ["seal", 1],
	"WIN_SEAL_1": ["seal", 2],
	"WIN_SEAL_2": ["seal", 3],
	"WIN_SEAL_3": ["seal", 4],
	"WIN_SEAL_4": ["seal", 5],
	"WIN_SEAL_5": ["seal", 6],
	"WIN_SEAL_6": ["seal", 7],
	"WIN_SEAL_7": ["seal", 8],
	"WIN_SEAL_8": ["seal", 9],
	"REVIVE_3": ["revives_run", REVIVES_RUN],
	"REVIVE_25": ["revives_all", 25],
	"KILLS_1K": ["kills_all", 1000],
	"KILLS_10K": ["kills_all", 10000],
	"KILLS_100K": ["kills_all", 100000],
	"HERO_10": ["hero_level", HERO_LEVEL],
	"ALL_CARDS": ["cards", 0],
	"FIRST_CARD": ["some_cards", 1],
	"ALL_SECRETS": ["secrets", 0],
	"APPRENTICES": ["apprentices", 0],
	"FAST_WIN": ["fast", FAST_SECONDS],
}


## Seconds into a run when the last omen's minute ends (World.OMENS lists them by wave).
static func omens_survived() -> float:
	var last := 0
	for o: Array in World.OMENS:
		last = maxi(last, int(o[0]))
	return last * 60.0


static func api_names() -> Array:
	var out: Array = []
	for row: Array in LIST:
		out.append(row[C_API])
	return out


static func count() -> int:
	return LIST.size()


## The row of an api name, [] when unknown.
static func row_of(api: String) -> Array:
	for row: Array in LIST:
		if row[C_API] == api:
			return row
	return []


static func crystals_of(api: String) -> int:
	var row := row_of(api)
	return 0 if row.is_empty() else int(row[C_CRYSTALS])


static func is_secret(api: String) -> bool:
	var row := row_of(api)
	return not row.is_empty() and row.size() > C_SECRET and bool(row[C_SECRET])


## The results screen's lines for the cards found in the run (Cards indices, "CARD FOUND: NAME" each, first) and
## the deeds it earned (Profile.last_pay.deeds, "DEED: NAME +CRYSTALS" each): at most RESULT_LINES lines in all,
## the last one "+K MORE" when they do not all fit ("+K MORE DEEDS" when only deeds are left out).
static func result_lines(api_names_earned: Array, cards: Array = []) -> Array[String]:
	var out: Array[String] = []
	for c: Variant in cards:
		out.append("CARD FOUND: %s" % Cards.card_name(int(c)))
	for api: Variant in api_names_earned:
		var row := row_of(str(api))
		out.append("DEED: %s +%d" % [str(api) if row.is_empty() else str(row[C_NAME]), crystals_of(str(api))])
	if out.size() <= RESULT_LINES:
		return out
	var left := out.size() - (RESULT_LINES - 1)
	var only_deeds := cards.size() <= RESULT_LINES - 1
	out.resize(RESULT_LINES - 1)
	out.append("+%d MORE DEEDS" % left if only_deeds else "+%d MORE" % left)
	return out


## API names of the achievements a finished run earned: from its record, whether it was won, and how long it
## lasted. `party` says who played and what the profile holds; every key is optional and a deed whose fact is
## missing is not earned: classes and races (Array of ints, one per hero a person plays: an apprentice earns no class or race deed), seal (the run's
## step), and the totals after this run: revives_total, kills_total, hero_level (the highest class level), cards
## (cards found), monster_cards (monster cards found, no Seal card: ALL_CARDS), secrets (secrets found). Who is an apprentice comes from the record (`ai`).
static func earned(record: Results, won: bool, seconds: float, party: Dictionary = {}) -> Array:
	var out: Array = []
	var size: int = record.stats.size()
	var deaths: float = 0.0
	for s: int in record.stats:
		deaths += record.stat(s, "deaths") + record.stat(s, "downs") # a fall that was raised still breaks FLAWLESS
	var kinds := {}
	var best_combo: int = 0
	var best_tier: int = 0
	var evolved := {}
	var bosses := {}
	for m: Array in record.moments:
		kinds[int(m[1])] = true
		if int(m[1]) == Results.M_EVOLVE:
			evolved[int(m[3])] = true
		if int(m[1]) == Results.M_COMBO:
			best_combo = maxi(best_combo, int(m[3]))
		if int(m[1]) == Results.M_CHEST:
			best_tier = maxi(best_tier, int(m[3]))
		if int(m[1]) == Results.M_ACT_BOSS:
			bosses[int(m[3])] = true
	if won:
		out.append("ARCHLICH")
		if size == 1:
			out.append("SOLO_WIN")
		if size >= PARTY_SIZE:
			out.append("PARTY_WIN")
		if deaths <= 0.0:
			out.append("FLAWLESS")
	if kinds.has(Results.M_LICH) or kinds.has(Results.M_ARCHLICH):
		out.append("LICH")
	if seconds >= TEN_MINUTES:
		out.append("TEN_MINUTES")
	if kinds.has(Results.M_BLESSING):
		out.append("BLESSED")
	if kinds.has(Results.M_CURSE):
		out.append("CURSED")
	if kinds.has(Results.M_JACKPOT):
		out.append("JACKPOT")
	if best_tier >= Loot.ULTRA:
		out.append("ULTRA")
	if kinds.has(Results.M_EVOLVE):
		out.append("EVOLVE")
	if best_combo >= COMBO_DEED:
		out.append("COMBO_200")
	if evolved.has(Upgrades.evo_entry(World.SP_RUNE)):
		out.append("SEAL")
	if seconds >= omens_survived():
		out.append("OMENS")
	var revives := 0
	for s: int in record.stats:
		revives += record.revives(s)
	var facts := {"won": won, "seconds": seconds, "size": size, "apprentices": record.ai.size(), "evolved": evolved,
		"bosses": bosses, "revives": revives, "party": party}
	for api: String in RULES:
		var rule: Array = RULES[api]
		if _rule_met(String(rule[0]), int(rule[1]), facts):
			out.append(api)
	return out


## Who played, for `earned`: the classes and races of the heroes people play, from the snapshot's player rows
## (`cls`, `race`, `ai`), and the run's Seal step. An apprentice earns no class, race or party deed.
static func party_of(players: Array, seal: int) -> Dictionary:
	var classes: Array = []
	var races: Array = []
	for v: Variant in players:
		var p: Dictionary = v
		if bool(p.get("ai", false)):
			continue
		classes.append(int(p.get("cls", 0)))
		races.append(int(p.get("race", 0)))
	return {"classes": classes, "races": races, "seal": seal}


## Whether one rule of RULES holds for the run's facts (see `earned`).
static func _rule_met(kind: String, arg: int, f: Dictionary) -> bool:
	var party: Dictionary = f.party
	var won: bool = f.won
	match kind:
		"win_class":
			return won and (party.get("classes", []) as Array).has(arg)
		"win_race":
			return won and (party.get("races", []) as Array).has(arg)
		"trinity":
			return won and _has_trinity(party.get("classes", []))
		"evo":
			return (f.evolved as Dictionary).has(Upgrades.evo_entry(arg))
		"boss":
			return (f.bosses as Dictionary).has(arg)
		"seal":
			return won and party.has("seal") and int(party.seal) >= arg
		"revives_run":
			return int(f.revives) >= arg
		"revives_all":
			return int(party.get("revives_total", 0)) >= arg
		"kills_all":
			return int(party.get("kills_total", 0)) >= arg
		"hero_level":
			return int(party.get("hero_level", 0)) >= arg
		"cards": # monster cards only (Profile's "monster_cards"; the Seal cards are paid by wins, not collected)
			return int(party.get("monster_cards", 0)) >= Cards.monster_count()
		"some_cards":
			return int(party.get("cards", 0)) >= arg
		"secrets":
			return int(party.get("secrets", 0)) >= Secrets.count()
		"apprentices":
			return won and int(f.size) >= 2 and int(f.apprentices) == int(f.size) - 1
		"fast":
			return won and int(f.size) >= FAST_PARTY and float(f.seconds) < float(arg)
	return false


## True when the classes cover a tank (a PALADIN's support counts as one), a healer and a ranged hero.
static func _has_trinity(classes: Array) -> bool:
	var tank := false
	var healer := false
	var ranged := false
	for c: Variant in classes:
		var role := Classes.role(int(c))
		tank = tank or role == Classes.ROLE_TANK or role == Classes.ROLE_SUPPORT
		healer = healer or role == Classes.ROLE_HEALER
		ranged = ranged or role == Classes.ROLE_RANGED
	return tank and healer and ranged

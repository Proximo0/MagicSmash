class_name Talk
extends RefCounted
## What the tower's people say, as data: the SHOPKEEPER (sells the Sanctum's unlocks), the CARD READER (fates, Seals
## and spell pairs) and MORVANE the Archlich (taunts after a run and in each lull). Every line has a speaker and a
## condition; `pick` chooses one for a context and never repeats the last line shown for that speaker when another
## fits. Pure: the caller passes the seeded RNG. Text is upper case, the pixel font's characters, at most two rows
## of TEXT_COLS characters.

const SHOPKEEPER := 0
const CARD_READER := 1
const MORVANE := 2

## [name, portrait key in Art's "portraits/characters"] per speaker.
const SPEAKERS: Array = [["SHOPKEEPER", "shopkeeper"], ["CARD READER", "card_reader"], ["MORVANE", "archlich"]]

## How many characters fit a row of the box (the box's text is TEXT_W pixels wide at the font's 6 px a character).
const TEXT_COLS := 52
const TEXT_ROWS := 2
const TEXT_W := TEXT_COLS * 6 - 1

## Conditions a speaker has lines for. "first" the first visit, "new_card" a card was just found, "loss" and "win"
## the run that just ended, "act1" to "act3" the act reached (for Morvane the act of the lull), "seal" playing on a
## Seal (SEAL I or higher), "apprentice" the first time on the APPRENTICE step, "idle" anything else.
const CONDITIONS := {
	SHOPKEEPER: ["first", "new_card", "loss", "win", "act1", "act2", "act3", "seal", "apprentice", "idle"],
	CARD_READER: ["first", "new_card", "loss", "win", "act1", "act2", "act3", "seal", "apprentice", "idle"],
	MORVANE: ["first", "loss", "win", "act1", "act2", "act3", "seal", "apprentice", "idle"],
}

## [speaker, condition, text]. A line's id is its place here.
const LINES: Array = [
	[SHOPKEEPER, "first", "WELCOME, WIZARD. CRYSTALS BUY WHAT THE TOWER WON'T GIVE. LOOK AT MY WARES."],
	[SHOPKEEPER, "new_card", "A NEW CARD. THE RELIQUARY SELLS SEALED DECKS, BUT I SELL NOTHING SO RARE."],
	[SHOPKEEPER, "loss", "THE TOWER TAKES. I BUY BACK. YOU EARNED CRYSTALS EVEN IN DEFEAT."],
	[SHOPKEEPER, "win", "YOU LIVED, AND THE BOUNTY IS HEAVY. SPEND IT WISELY."],
	[SHOPKEEPER, "act1", "THE OSSUARY AGAIN? BONES ARE CHEAP. WARDED ROBES ARE NOT, BUT THEY LAST."],
	[SHOPKEEPER, "act2", "THE LIBRARY BURNS, AND SO DO POOR ROBES. FORBIDDEN LORE SELLS WELL."],
	[SHOPKEEPER, "act3", "YOU REACHED THE STARLESS SANCTUM. I DID NOT EXPECT TO SELL YOU MORE."],
	[SHOPKEEPER, "seal", "THE HIGHER THE SEAL, THE HEAVIER THE BOUNTY. MY PRICES STAY THE SAME."],
	[SHOPKEEPER, "apprentice", "THE APPRENTICE STEP IS GENTLE. IT ALSO HIDES THE ULTRA RARE LOOT."],
	[SHOPKEEPER, "idle", "NO ONE BUYS CRYSTALS FOR MONEY. THEY ARE EARNED, AND I SELL TO THE EARNED."],
	[SHOPKEEPER, "idle", "EVERY UNLOCK STAYS FOR EVERY RUN. THAT IS WHY IT COSTS SO MUCH."],
	[SHOPKEEPER, "idle", "THE FOUR-LEAF RUNE COSTS 60 CRYSTALS. LUCK IS NEVER CHEAP."],

	[CARD_READER, "first", "SIT, WIZARD. THE CARDS SAY MUCH. THE FATE CARD SAYS MOST OF ALL."],
	[CARD_READER, "new_card", "A NEW CARD FOR THE ALBUM. SOCKET IT IN HAT, ROBE OR STAFF. IT HELPS EVERY RUN."],
	[CARD_READER, "loss", "THE TOWER LEFT YOU THIN. THE CARDS SAY YOU WILL CLIMB AGAIN."],
	[CARD_READER, "win", "I SAW YOU WIN BEFORE YOU DID. A WIN OPENS THE NEXT STEP OF THE LADDER."],
	[CARD_READER, "act1", "THE TEAM SHRINE DRAWS A FATE. THE SUN BLESSES, DEATH CURSES, SIX MORE WAIT."],
	[CARD_READER, "act2", "A SPELL AT LEVEL 5 AND ITS PARTNER WILL EVOLVE. FIRE AND STORM MAKE THUNDERFIRE."],
	[CARD_READER, "act3", "THE EMPEROR GIVES EACH WIZARD A CHEST. THE HANGED MAN SEALS THE NOVAS."],
	[CARD_READER, "seal", "THERE ARE EIGHT SEALS, EACH A NEW RULE. EACH FIRST WIN PAYS ITS SEAL CARD."],
	[CARD_READER, "apprentice", "THE APPRENTICE STEP WEAKENS THE FOES AND GIVES TWO MORE HEARTS."],
	[CARD_READER, "idle", "FROST AND ARCANE MAKE BLIZZARD. STAR AND FROST MAKE COMET RAIN."],
	[CARD_READER, "idle", "STAR AND ARCANE MAKE THE ASTRAL LANCE. IT PIERCES WHAT IT MEETS."],
	[CARD_READER, "idle", "DEATH TAKES A HEART AND SENDS AN ELITE FOR EACH WIZARD. THE SUN GIVES TWO LEVELS."],

	[MORVANE, "first", "SO THE COVEN STIRS. I READ THE NINTH PAGE. YOU WILL READ NONE OF IT."],
	[MORVANE, "loss", "THE TOWER KEEPS YOU, WIZARD. I KEEP EVERYTHING."],
	[MORVANE, "loss", "DEATH ANSWERS TO MY NAME. IT DID NOT ANSWER TO YOURS."],
	[MORVANE, "win", "YOU WIN. I HAVE DIED BEFORE, AND IT WAS NOT THE LAST TIME. NOR YOURS."],
	[MORVANE, "act1", "A CHANDELIER IS ONLY A LAMP. UPSTAIRS THE BOOKS ARE ON FIRE."],
	[MORVANE, "act1", "REST, WIZARD. THE OSSUARY WAS ONLY MY FRONT STEP."],
	[MORVANE, "act2", "MY GHOST WRITER HAS COPIED YOUR NAMES. I WILL WRITE THE ENDINGS."],
	[MORVANE, "act2", "CATCH YOUR BREATH. THE STAIR TO MY SANCTUM IS SHORT AND STEEP."],
	[MORVANE, "act3", "THE STARS HAVE GONE OUT. WHO CLIMBS SO FAR TO MEET ME? I ADMIRE IT."],
	[MORVANE, "seal", "A SEAL, WIZARD. EVERY ONE IS A WALL I BUILT FOR YOU."],
	[MORVANE, "apprentice", "THE APPRENTICE STEP. MY HORDE FEELS INSULTED."],
	[MORVANE, "idle", "THE COMET DOES NOT WAIT FOR WIZARDS. NEITHER DO I."],
]


## The line for `speaker` in `context`, or {} when the speaker has none. The context's keys (all optional):
## first (bool, a first visit), new_card (bool), result ("loss", "win" or "": the run that just ended), act (0 to 2,
## or -1: the act reached or, in a lull, the act it is in), seal (the step played, Seals.MIN to MAX),
## apprentice (bool, the first time on APPRENTICE), lull (bool, Morvane in a lull: act lines only), last (the id
## shown last for this speaker, or -1). Returns {id, speaker, name, portrait, text, rows}.
static func pick(speaker: int, context: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ids := candidates(speaker, context)
	if ids.is_empty():
		return {}
	var last := int(context.get("last", -1))
	if ids.size() > 1 and ids.has(last):
		ids.erase(last)
	var id: int = ids[rng.randi() % ids.size()]
	var text: String = LINES[id][2]
	return {"id": id, "speaker": speaker, "name": SPEAKERS[speaker][0], "portrait": SPEAKERS[speaker][1],
		"text": text, "rows": wrap_rows(text)}


## The ids of every line that fits `context`. "first" and "new_card" speak alone; otherwise the lines of the run's
## result, the act, the step and the apprentice rule pool together with "idle". A lull wants an act line,
## and "idle" fills in only when that has none.
static func candidates(speaker: int, context: Dictionary) -> Array[int]:
	var wanted: Array[String] = []
	if bool(context.get("lull", false)):
		wanted.append("act%d" % (clampi(int(context.get("act", 0)), 0, 2) + 1))
	elif bool(context.get("first", false)):
		wanted.append("first")
	elif bool(context.get("new_card", false)) and CONDITIONS[speaker].has("new_card"):
		wanted.append("new_card")
	else:
		var result := String(context.get("result", ""))
		if result == "loss" or result == "win":
			wanted.append(result)
		var act := int(context.get("act", -1))
		if act >= 0 and act <= 2 and speaker != MORVANE:
			wanted.append("act%d" % (act + 1))
		if int(context.get("seal", 0)) >= 2:
			wanted.append("seal")
		if bool(context.get("apprentice", false)):
			wanted.append("apprentice")
		wanted.append("idle")
	var out := _ids(speaker, wanted)
	if out.is_empty():
		out = _ids(speaker, ["idle"])
	return out


static func _ids(speaker: int, wanted: Array[String]) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(LINES.size()):
		if int(LINES[i][0]) == speaker and wanted.has(String(LINES[i][1])):
			out.append(i)
	return out


## Breaks `text` into rows of at most `cols` characters at spaces. A word longer than a row gets a row of its own.
static func wrap_rows(text: String, cols: int = TEXT_COLS) -> Array[String]:
	var rows: Array[String] = []
	var row := ""
	for word: String in text.split(" ", false):
		if row.is_empty():
			row = word
		elif row.length() + 1 + word.length() <= cols:
			row += " " + word
		else:
			rows.append(row)
			row = word
	if not row.is_empty():
		rows.append(row)
	return rows

class_name Achievements
extends RefCounted
## Steam achievements: the catalogue and which ones a finished run earns. Pure data plus a rule per achievement,
## read from the run's Results record. The Platform autoload unlocks them on Steam (the host's account: with
## Remote Play Together only the host runs the game). The API names must match the Steamworks admin page.

## [api name, display name, description]. Append new ones at the end.
const LIST: Array = [
	["ARCHLICH", "THE LAST LICH", "Slay the Archlich and win a run."],
	["SOLO_WIN", "LONE WIZARD", "Win a run alone."],
	["PARTY_WIN", "FULL TOWER", "Win a run with four wizards."],
	["FLAWLESS", "UNTOUCHED", "Win a run without any wizard losing a life."],
	["LICH", "LICH BANE", "Slay the Lich Lord."],
	["TEN_MINUTES", "HOLD THE TOWER", "Survive for 10 minutes."],
	["BLESSED", "BLESSED BE", "Draw The Sun for the whole party at the fate card."],
	["CURSED", "WORTH IT", "Draw Death for the whole party at the fate card."],
	["JACKPOT", "JACKPOT", "Hit the jackpot at a rune altar."],
	["ULTRA", "ULTRA RARE", "Find ultra rare loot in a chest."],
	["EVOLVE", "EVOLUTION", "Evolve a spell."],
	["COMBO_200", "TOTAL SORCERY", "Chain a 200 kill combo."],
]

const TEN_MINUTES := 600.0


static func api_names() -> Array:
	var out: Array = []
	for row: Array in LIST:
		out.append(row[0])
	return out


## API names of the achievements a finished run earned: from its record, whether it was won, and how long it
## lasted.
static func earned(record: Results, won: bool, seconds: float) -> Array:
	var out: Array = []
	var party: int = record.stats.size()
	var deaths: float = 0.0
	for s: int in record.stats:
		deaths += record.stat(s, "deaths")
	var kinds := {}
	var best_combo: int = 0
	var best_tier: int = 0
	for m: Array in record.moments:
		kinds[int(m[1])] = true
		if int(m[1]) == Results.M_COMBO:
			best_combo = maxi(best_combo, int(m[3]))
		if int(m[1]) == Results.M_CHEST:
			best_tier = maxi(best_tier, int(m[3]))
	if won:
		out.append("ARCHLICH")
		if party == 1:
			out.append("SOLO_WIN")
		if party >= 4:
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
	if best_combo >= 200:
		out.append("COMBO_200")
	return out

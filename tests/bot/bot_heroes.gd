extends RefCounted
## The hero shard's helpers (docs/bots.md, "The hero shard"): an in-memory profile with four saved heroes, the check at
## the start of the fight, the way a lost run is ended and the check of its booking. Used by bot.gd (`-- --heroes`).

## Seconds of fight the run must reach before it is ended: class XP pays per whole minute survived.
const FIGHT_SECONDS: float = 62.0
## A hurt big enough to fell a wizard whatever her hearts.
const BIG_HURT: int = 99
const META := {"vigor": 1, "might": 2}
## One row per hero: race key, class, level, stat points to spend [stat, count]..., cards (Cards keys) to socket.
const ROWS: Array = [
	["human", Classes.MAGE, 6, [[Loot.ST_MIGHT, 2], [Loot.ST_FOCUS, 3]], []],
	["elf", Classes.ARCHER, 4, [[Loot.ST_SWIFT, 2], [Loot.ST_VIGOR, 1]], ["slime"]],
	["dwarf", Classes.KNIGHT, 8, [[Loot.ST_WARD, 3], [Loot.ST_VIGOR, 4]], ["bat", "orc"]],
	["orc", Classes.PRIEST, 2, [[Loot.ST_GREED, 1]], []],
]


## True when `user_dir` (OS.get_user_data_dir()) lies inside `private_dir` (the folder tools/private_save.sh made and
## named in PRIVATE_SAVE). False for an empty private folder. Slashes and case do not matter (Windows gives both).
static func save_is_private(private_dir: String, user_dir: String) -> bool:
	var priv := private_dir.replace("\\", "/").to_lower().trim_suffix("/")
	var user := user_dir.replace("\\", "/").to_lower().trim_suffix("/")
	return not priv.is_empty() and (user + "/").begins_with(priv + "/")


## Four heroes of four races and classes, two with cards in their sockets (slime +1 heart; bat +10% speed, orc +10%
## damage), and a few unlock levels. The ELF is the active hero, as in a real profile whose player last played her.
static func make_profile() -> Profile:
	var p := Profile.new()
	p.heroes.clear()
	for row: Array in ROWS:
		var h := Hero.make(Races.index_of(row[0]), row[1], 0, String(row[0]).to_upper())
		h.level = row[2]
		for sp: Array in row[3]:
			for _i: int in range(sp[1]):
				h.spend_point(sp[0])
		p.add_hero(h)
		for k: String in row[4]:
			var ci := Cards.index_of(k)
			p.add_card(ci)
			h.sockets[Cards.socket(ci)] = k
	p.hero = 1
	p.unlocks = META.duplicate()
	return p


## One FAIL line per seat whose wizard differs from what her hero and the meta give, each socketed card counted once.
static func check_start(w: World, profile: Profile) -> Array[String]:
	var out: Array[String] = []
	var meta_hearts := 0
	for key: String in META:
		var eff: Array = Profile.EFFECTS[key]
		if eff[0] == "hearts":
			meta_hearts += int(float(eff[1]) * int(META[key]))
	for r: Dictionary in Net.roster:
		var slot: int = int(r.slot)
		var idx: int = Net.hero_of(int(r.device))
		if idx < 0 or not w.players.has(slot):
			out.append("BOT heroes seat=%d FAIL no hero or no wizard (hero=%d)" % [slot, idx])
			continue
		var h: Hero = profile.heroes[idx]
		var p: World.Player = w.players[slot]
		var st: Array = h.stats()
		var want := {"cls": h.cls, "race": h.race, "hearts": Classes.hearts(h.cls) + meta_hearts + int(float(st[Loot.ST_VIGOR]))}
		var got := {"cls": p.cls, "race": p.race, "hearts": p.max_hp}
		for i: int in range(Loot.STAT_COUNT):
			want["armor%d" % i] = snappedf(float(st[i]), 0.0001)
			got["armor%d" % i] = snappedf(float(p.armor[i]), 0.0001)
		if not is_equal_approx(w.meta_damage, 0.05 * int(META["might"])):
			want["meta_damage"] = 0.05 * int(META["might"])
			got["meta_damage"] = w.meta_damage
		var bad: Array[String] = []
		for k: String in want:
			if want[k] != got[k]:
				bad.append("%s expected %s got %s" % [k, want[k], got[k]])
		if not bad.is_empty():
			out.append("BOT heroes seat=%d hero=%s FAIL %s" % [slot, h.name, "; ".join(bad)])
	return out


## What the end check compares with: runs, crystals and each hero's level and XP before the run.
static func snapshot(profile: Profile) -> Dictionary:
	var hs: Array = []
	for h: Hero in profile.heroes:
		hs.append([h.level, h.xp])
	return {"runs": profile.runs, "crystals": profile.crystals, "heroes": hs}


## Ends the run the way a loss ends: every wizard still standing takes a hit through World.hurt_player (a wizard
## shrugging it off by WARD or inside her hurt-safe seconds takes the next one; Player.invuln is cleared so she can).
static func hurt_party(w: World) -> void:
	for p: World.Player in w.players.values():
		if p.alive:
			p.invuln = 0.0
			w.hurt_player(p, BIG_HURT)


## FAIL lines (none when the booking is right) after the arena booked the lost run through G.finish_run.
static func check_end(profile: Profile, before: Dictionary, seated: Array[int]) -> Array[String]:
	var out: Array[String] = []
	if profile.runs != int(before.runs) + 1:
		out.append("runs expected %d got %d" % [int(before.runs) + 1, profile.runs])
	if profile.crystals <= int(before.crystals):
		out.append("crystals did not grow (%d)" % profile.crystals)
	var named: Array = profile.last_hero_levels.keys()
	named.sort()
	var want: Array = seated.duplicate()
	want.sort()
	if named != want:
		out.append("last_hero_levels names %s expected %s" % [named, want])
	for i: int in seated:
		var was: Array = before.heroes[i]
		var h: Hero = profile.heroes[i]
		if h.level < int(was[0]) or (h.level == int(was[0]) and h.xp <= int(was[1])):
			out.append("hero %d XP did not grow (level %d xp %d -> level %d xp %d)" % [i, was[0], was[1], h.level, h.xp])
	if FileAccess.file_exists(Save.PATH):
		out.append("%s exists" % Save.PATH)
	return out

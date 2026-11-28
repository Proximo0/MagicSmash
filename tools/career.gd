extends RefCounted
## Career: a bot plays run after run on one in-memory Profile (never saved) from a fresh start, the way a player climbs:
## after each run the real Profile.finish_run books it (crystals, deeds, class XP), crystals buy the cheapest
## affordable META level (list order on ties) until none is affordable, and each hero spends its stat points
## alternating MIGHT and VIGOR. The next run starts with World.apply_meta(profile.bonuses()) and the heroes (their
## own sockets only through apply_hero: bonuses() has no cards, so each counts once).
## Usage: godot --headless --path . -s tools/tool.gd -- career [--careers=6] [--seed=1] [--persona=casual]
##   [--hero=mage] | [--party=casual:knight,casual:priest,apprentice:archer,...] [--seal=0] [--max-runs=40]
##   [--until=win] [--minutes=25] [--checkpoints=60,120,180 --out=DIR] [--tune=field:value,...]
## Each human seat plays its own hero on the one profile (a fresh level 1 HUMAN of its class); an apprentice seat is
## seated as the game seats it (World makes it a hero of its class). Runs are capped at --minutes of run clock (25
## leaves room past the Archlich's ~16:00 win); a run that reaches the cap is UNFINISHED (its own count and a "U"
## in ends), never a loss, though Profile.finish_run still books it as the game books any run that is not won. --checkpoints writes the profile (after that run's
## spending) as DIR/career<k>_<mark>.json the first time the career's play time passes each mark, in minutes; the
## playtest's --profile=FILE plays seeds from one. Prints one line per career and a CAREER line of medians
## ("urn": the run and minute a career found the urn_card secret, by luck or by Profile.URN_CARD_AFTER urns).
## How to read it: docs/bots.md "Careers".

const PlaytestLib := preload("res://tools/playtest_lib.gd")
## Seeds: career k's run i plays seed --seed + SEED_STRIDE x k + i.
const SEED_STRIDE := 1000
## The plain build: points go to these stats in turn (the one with fewer points first, list order on ties).
const BUILD := [Loot.ST_MIGHT, Loot.ST_VIGOR]

var _careers := 6
var _max_runs := 40
var _until_win := false
var _marks: Array[float] = []
var _out := ""


func run(args: PackedStringArray) -> int:
	var lib: PlaytestLib = PlaytestLib.new()
	lib._minutes = 25.0
	lib._heroes = [[Classes.MAGE, Races.HUMAN]]
	lib._personas = [SmashBot.CASUAL]
	if not lib._parse_args():
		return 2
	for arg: String in args:
		var v: String = arg.get_slice("=", 1)
		if arg.begins_with("--careers="):
			_careers = maxi(1, int(v))
		elif arg.begins_with("--max-runs="):
			_max_runs = maxi(1, int(v))
		elif arg.begins_with("--until="):
			_until_win = v == "win"
		elif arg.begins_with("--checkpoints="):
			for x: String in v.split(",", false):
				_marks.append(float(x))
		elif arg.begins_with("--out="):
			_out = v
	if not _marks.is_empty() and _out == "":
		push_error("--checkpoints needs --out=DIR")
		return 2
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	var party: Array[int] = lib._party.duplicate()
	var classes: Array = lib._party_heroes.duplicate()
	if party.is_empty():
		party = [lib._personas[0]]
		classes = [lib._heroes[0] if not (lib._heroes[0] as Array).is_empty() else [Classes.MAGE, Races.HUMAN]]
	var name := _group_name(party, classes)
	var rows: Array = []
	for k: int in range(_careers):
		var row := _career(lib, k, party, classes)
		rows.append(row)
		print("%s career %d: boss1 %s  arch %s  win %s  urn %s  runs %d  unfinished %d  min %.0f  crystals %d earned %d spent  level %s  ends %s" % [
			name, k + 1, _at(row, "boss"), _at(row, "arch"), _at(row, "win"), _at(row, "urn"), row.runs, row.unfinished, row.minutes,
			row.earned, row.spent, str(row.win_level) if int(row.win_level) > 0 else "-", " ".join(row.ends)])
	var summary: PackedStringArray = []
	for key: String in ["boss", "arch", "win"]:
		summary.append(_reached_text(rows, key))
	var unfinished := 0
	var played := 0
	for row: Dictionary in rows:
		unfinished += int(row.unfinished)
		played += int(row.runs)
	summary.append("unfinished %d/%d runs" % [unfinished, played])
	summary.append(_reached_text(rows, "urn")) # last: the station's INFO line keeps the line's first 180 characters
	print("CAREER %s seal=%d careers=%d | %s" % [name, lib._seal, _careers, " | ".join(summary)])
	return 0


## One career from a fresh profile; returns its row (runs and minutes to the first boss kill, the Archlich, the win
## and the urn_card secret: Profile.URN_CARD_AFTER urns over the runs bring the urn card, as in the game).
func _career(lib: PlaytestLib, k: int, party: Array[int], classes: Array) -> Dictionary:
	var prof := fresh_profile(party, classes)
	var seat_hero := {} # slot -> profile hero index (human seats only)
	var n := 0
	for s: int in range(party.size()):
		if party[s] != PlaytestLib.APPRENTICE:
			seat_hero[s] = n
			n += 1
	var row := {"runs": 0, "unfinished": 0, "minutes": 0.0, "earned": 0, "spent": 0, "win_level": 0, "ends": [],
		"boss_run": 0, "boss_min": 0.0, "arch_run": 0, "arch_min": 0.0, "win_run": 0, "win_min": 0.0, "urn_run": 0, "urn_min": 0.0}
	var marks_left: Array[float] = _marks.duplicate()
	for i: int in range(_max_runs):
		lib._bonuses = prof.bonuses()
		lib._seat_heroes = {}
		for s: int in seat_hero:
			lib._seat_heroes[s] = (prof.heroes[seat_hero[s]] as Hero).to_dict()
		var r: Dictionary = lib._play(party[0], party.size(), lib._seed + SEED_STRIDE * k + i, party, classes)
		var w: World = lib._last_world
		var before := prof.crystals
		for c: int in w.cards_found:
			prof.add_card(c)
		var players: Array = []
		for p: World.Player in w.players.values():
			players.append({"ai": p.ai, "cls": p.cls, "race": p.race})
		# The arena marks the urn_card secret when a card from an urn is picked up (ArenaEvents, EV_CARD). A run holds
		# one card, so a run that saw it fall from an urn and found a card found that one.
		if int((r.loot as Dictionary).get("card_urn", 0)) > 0 and not w.cards_found.is_empty():
			prof.find_secret("urn_card")
		prof.finish_run({"score": w.total_score(), "seconds": float(r.end), "kills": w.total_kills(),
			"liches": w.liches_slain, "won": bool(r.won), "seal": lib._seal, "results": w.record,
			"party": Achievements.party_of(players, lib._seal), "heroes": seat_hero.values(), "urns": w.urns_broken})
		row.earned = int(row.earned) + prof.crystals - before
		var bought := spend_crystals(prof)
		row.spent = _spent_total(prof)
		for h: Hero in prof.heroes:
			spend_points(h)
		row.runs = i + 1
		if bool(r.unfinished):
			row.unfinished = int(row.unfinished) + 1
		row.minutes = float(row.minutes) + float(r.end) / 60.0
		(row.ends as Array).append("%s%s/L%d%s" % [_clock(float(r.end)), "W" if bool(r.won) else ("U" if bool(r.unfinished) else ""), (prof.heroes[0] as Hero).level,
			"+" + ",".join(bought) if not bought.is_empty() else ""])
		if int(row.boss_run) == 0 and w.liches_slain > 0:
			row.boss_run = i + 1
			row.boss_min = row.minutes
		if int(row.arch_run) == 0 and float(r.arch) >= 0.0:
			row.arch_run = i + 1
			row.arch_min = row.minutes
		if int(row.win_run) == 0 and bool(r.won):
			row.win_run = i + 1
			row.win_min = row.minutes
			row.win_level = (prof.heroes[0] as Hero).level
		if int(row.urn_run) == 0 and prof.has_secret("urn_card"):
			row.urn_run = i + 1
			row.urn_min = row.minutes
		while not marks_left.is_empty() and float(row.minutes) >= marks_left[0]:
			_write_checkpoint(prof, "%s/career%d_%d.json" % [_out, k + 1, int(marks_left[0])])
			marks_left.pop_front()
		if _until_win and bool(r.won):
			break
	return row


## A fresh profile: one level 1 HUMAN hero per human seat of `party` (its class from `classes`, a MAGE's school the
## seat's own colour, as the playtest seats it), no unlocks, no crystals.
static func fresh_profile(party: Array[int], classes: Array) -> Profile:
	var prof := Profile.new()
	prof.heroes = []
	for s: int in range(party.size()):
		if party[s] == PlaytestLib.APPRENTICE:
			continue
		var c: Array = classes[s] if s < classes.size() and not (classes[s] as Array).is_empty() else [Classes.MAGE, Races.HUMAN]
		prof.heroes.append(Hero.make(int(c[1]), int(c[0]), s % Wizards.count()))
	prof.hero = 0
	return prof


## The spending policy: buys the cheapest affordable META level (list order on ties) until none is affordable.
## Returns the keys bought, in order.
static func spend_crystals(prof: Profile) -> Array[String]:
	var out: Array[String] = []
	while true:
		var best := -1
		for i: int in range(Profile.META.size()):
			var c := prof.next_cost(i)
			if c >= 0 and c <= prof.crystals and (best < 0 or c < prof.next_cost(best)):
				best = i
		if best < 0:
			return out
		prof.buy(best)
		out.append(str(Profile.META[best][0]))
	return out


## The plain build: spends every point left, each on the BUILD stat with the fewest points (list order on ties),
## skipping a stat at Hero.MAX_POINTS. Returns the points spent.
static func spend_points(h: Hero) -> int:
	var n := 0
	while h.points_left() > 0:
		var pick := -1
		for st: int in BUILD:
			if h.points[st] < Hero.MAX_POINTS and (pick < 0 or h.points[st] < h.points[pick]):
				pick = st
		if pick < 0 or not h.spend_point(pick):
			return n
		n += 1
	return n


## Crystals spent on unlocks so far (the sum of the levels' costs).
static func _spent_total(prof: Profile) -> int:
	var t := 0
	for i: int in range(Profile.META.size()):
		var costs: Array = Profile.META[i][3]
		for lv: int in range(prof.level(str(Profile.META[i][0]))):
			t += int(costs[lv])
	return t


## A checkpoint's text: the profile's saved form as JSON (Profile.from_dict of its parse gives the profile back).
static func checkpoint_text(prof: Profile) -> String:
	return JSON.stringify(prof.to_dict())


static func profile_from_text(text: String) -> Profile:
	var d: Variant = JSON.parse_string(text)
	return Profile.from_dict(d) if d is Dictionary else null


func _write_checkpoint(prof: Profile, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + path)
		return
	f.store_string(checkpoint_text(prof))


func _group_name(party: Array[int], classes: Array) -> String:
	var names: PackedStringArray = []
	for s: int in range(party.size()):
		var c: Array = classes[s] if s < classes.size() else []
		var who := "apprentice" if party[s] == PlaytestLib.APPRENTICE else SmashBot.persona_name(party[s])
		names.append(who + (":" + Classes.key(int(c[0])) if not c.is_empty() else ""))
	return ",".join(names)


func _at(row: Dictionary, key: String) -> String:
	return "r%d/%.0fm" % [row[key + "_run"], row[key + "_min"]] if int(row[key + "_run"]) > 0 else "-"


## "<key> got/all run <median> min <median>" over the careers that reached `key` (a row's <key>_run and <key>_min).
func _reached_text(rows: Array, key: String) -> String:
	var rn: Array = []
	var mn: Array = []
	for row: Dictionary in rows:
		if int(row[key + "_run"]) > 0:
			rn.append(float(row[key + "_run"]))
			mn.append(float(row[key + "_min"]))
	return "%s %d/%d run %s min %s" % [key, rn.size(), rows.size(), _med_text(rn), _med_text(mn)]


static func _median(xs: Array) -> float:
	var s := xs.duplicate()
	s.sort()
	var m := s.size()
	return (float(s[m / 2]) if m % 2 == 1 else (float(s[m / 2 - 1]) + float(s[m / 2])) / 2.0) if m > 0 else -1.0


func _med_text(xs: Array) -> String:
	return "%.0f" % _median(xs) if not xs.is_empty() else "-"


func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]

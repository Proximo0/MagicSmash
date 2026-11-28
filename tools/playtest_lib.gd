extends RefCounted
## The playtest tool's body (tools/playtest.gd loads it once the autoloads are up). Usage and reading: see
## tools/playtest.gd and docs/bots.md.

const DT: float = 1.0 / 60.0
const PRESSURE_R: float = 60.0
const DEAD_AIR_R: float = 150.0
## Pressure and dead air are sampled every this many ticks (they scan the horde).
const SAMPLE: int = 6

var _runs: int = 6
var _wizards: Array[int] = [1, 2, 4]
var _personas: Array[int] = [SmashBot.NOVICE, SmashBot.CASUAL, SmashBot.VETERAN]
var _seed: int = 1
## The run clock cap. A win on the Archlich comes at about 15:50 and later, so the cap leaves room; a run that
## reaches it is UNFINISHED (r.unfinished, its own count), never a loss.
var _minutes: float = 25.0
var _tune_pairs: PackedStringArray = []
var _seal: int = 0
var _reading: String = "" # --reading=<key>: every run plays under that Reading (World.apply_reading)
## --meta=key:value,...: Profile.bonuses keys ("start_level", "redraws", "banishes", "hearts"...) every run's
## World.apply_meta gets, over --profile's ({}: none, no apply_meta of its own), as meta_from_arg reads them (a second
## --meta adds to the first); the PLAYTEST line names them (_meta_text).
var _meta: Dictionary = {}
var _json: String = ""
## --party: one party of seats, each a SmashBot persona id or APPRENTICE (empty: the persona x wizards groups).
var _party: Array[int] = []
## Each --party seat's hero [Classes index, Races index], or [] for a seat with no class (plays as before).
var _party_heroes: Array = []
## --hero: the classes every persona x wizards group is played with, each [Classes index, Races index] or [] (none).
var _heroes: Array = [[]]
const APPRENTICE := -1
## --profile: a saved profile (a career checkpoint, tools/career.gd) every run starts from: World.apply_meta of its
## bonuses for every seat (no cards: Profile.bonuses has none), and each human seat (in seat order) plays one of its heroes (the last one again when
## there are more seats than heroes). Null: no meta, level 1 heroes as before.
var _profile: Profile = null
## Set by the career tool for each run (or by --profile): the meta bonuses applied to every seat ({}: none) and
## slot -> a saved hero's Hero.to_dict() for human seats (in place of a level 1 Hero.make of the seat's class). A
## hero's socketed cards reach the run only through apply_hero of her own dict, so they count once, as in play.
var _bonuses: Dictionary = {}
var _seat_heroes: Dictionary = {}
## The World of the last _play, for the career tool's booking (Profile.finish_run).
var _last_world: World = null


## Runs the whole playtest; returns the process exit code.
func run() -> int:
	if not _parse_args():
		return 2
	var groups: Array = []
	var summary: PackedStringArray = []
	if not _party.is_empty():
		var runs: Array = []
		for i: int in range(_runs):
			runs.append(_play(_party[0], _party.size(), _seed + i, _party, _party_heroes))
		var g: Dictionary = _aggregate(_party[0], _party.size(), runs)
		g.persona = _party_name()
		_print_group(g)
		groups.append(g)
		summary.append("%s win %d/%d unfinished %d end %s first down %s human %s lv6 %s" % [g.persona, g.wins, _runs,
			g.unfinished, _clock(g.end.med),
			_clock(float(g.first_down.get("med", -1.0))), _clock(float(g.human_down.get("med", -1.0))), _level_at(g, 6)])
	for persona: int in (_personas if _party.is_empty() else [] as Array[int]):
		for hero: Array in _heroes:
			for wz: int in _wizards:
				var runs: Array = []
				var classes: Array = []
				for _s: int in range(wz):
					classes.append(hero)
				for i: int in range(_runs):
					runs.append(_play(persona, wz, _seed + i, [] as Array[int], classes))
				var g: Dictionary = _aggregate(persona, wz, runs)
				g.persona = SmashBot.persona_name(persona) + _hero_name(hero)
				_print_group(g)
				groups.append(g)
				summary.append("%s x%d win %d/%d unfinished %d end %s arch %s first down %s lv6 %s" % [g.persona, wz,
					g.wins, _runs, g.unfinished, _clock(g.end.med), _clock(float(g.arch.med)), _clock(float(g.first_down.get("med", -1.0))),
					_level_at(g, 6)])
	if _json != "":
		var f := FileAccess.open(_json, FileAccess.WRITE)
		if f == null:
			push_error("cannot write " + _json)
		else:
			f.store_string(JSON.stringify({"args": OS.get_cmdline_user_args(), "groups": groups}, " "))
	print(_playtest_line(groups.size(), summary))
	return 0


## The last line of run(): its settings, --meta's values when given (_meta_text), then each group's summary.
func _playtest_line(groups: int, summary: PackedStringArray) -> String:
	return "PLAYTEST runs=%d minutes=%.0f seed=%d seal=%d %s%s | %s" % [_runs * groups, _minutes, _seed, _seal,
		Seals.title(_seal), " meta=" + _meta_text() if not _meta.is_empty() else "", " | ".join(summary)]


## The --meta values as the PLAYTEST line names them: key:value in the order first given ("start_level:2,redraws:1").
func _meta_text() -> String:
	var parts: PackedStringArray = []
	for key: String in _meta:
		var v: float = float(_meta[key])
		parts.append("%s:%s" % [key, str(int(v)) if v == roundf(v) else str(v)])
	return ",".join(parts)


## Adds --meta's "key:value[,key:value]" to `into` (a key given again takes its last value). A key is a number
## World.apply_meta reads: the Profile.bonuses key of a built Profile.EFFECTS row ("hearts" ... "start_level"; one
## whose row is on Profile.UNBUILT would be ignored, so it is refused too). Returns "" or what is wrong, in one line.
static func meta_from_arg(spec: String, into: Dictionary) -> String:
	var known: PackedStringArray = []
	for row: String in Profile.EFFECTS:
		if not Profile.UNBUILT.has(row):
			known.append(String((Profile.EFFECTS[row] as Array)[0]))
	for x: String in spec.split(","):
		if x.get_slice_count(":") != 2 or not x.get_slice(":", 1).is_valid_float():
			return "--meta takes key:value[,key:value] (Profile.bonuses keys), not " + x
		var key: String = x.get_slice(":", 0)
		if not known.has(key):
			return "unknown --meta key %s (one of %s)" % [key, ",".join(known)]
		into[key] = float(x.get_slice(":", 1))
	return ""


## Reads the tool's arguments (the command line's, or `args` as a test gives them) into the fields; false on a bad one.
func _parse_args(args: PackedStringArray = OS.get_cmdline_user_args()) -> bool:
	for arg: String in args:
		var v: String = arg.get_slice("=", 1)
		if arg.begins_with("--runs="):
			_runs = maxi(1, int(v))
		elif arg.begins_with("--wizards="):
			_wizards.clear()
			for x: String in v.split(","):
				_wizards.append(clampi(int(x), 1, 4))
		elif arg.begins_with("--persona="):
			_personas.clear()
			for x: String in v.split(","):
				var id: int = SmashBot.persona_from_name(x)
				if id < 0:
					push_error("unknown persona " + x)
					return false
				_personas.append(id)
		elif arg.begins_with("--seed="):
			_seed = int(v)
		elif arg.begins_with("--minutes="):
			_minutes = maxf(0.5, float(v))
		elif arg.begins_with("--tune="):
			_tune_pairs = v.split(",")
		elif arg.begins_with("--seal="):
			_seal = int(v)
		elif arg.begins_with("--reading="):
			_reading = v
			if Readings.index_of(_reading) < 0:
				push_error("unknown reading " + arg)
				return false
		elif arg.begins_with("--json="):
			_json = v
		elif arg.begins_with("--meta="):
			var why: String = meta_from_arg(v, _meta)
			if why != "":
				push_error(why)
				return false
		elif arg.begins_with("--profile="):
			_profile = load_profile(v)
			if _profile == null:
				push_error("cannot read profile " + v)
				return false
		elif arg.begins_with("--hero="):
			_heroes.clear()
			for x: String in v.split(","):
				var hero: Array = _parse_hero(x)
				if hero.is_empty():
					push_error("unknown hero " + x + " (class[:race])")
					return false
				_heroes.append(hero)
		elif arg.begins_with("--party="):
			_party.clear()
			_party_heroes.clear()
			for x: String in v.split(","):
				var who: String = x.get_slice(":", 0)
				var id: int = APPRENTICE if who == "apprentice" else SmashBot.persona_from_name(who)
				if id == -1 and who != "apprentice":
					push_error("unknown seat " + x)
					return false
				var hero: Array = _parse_hero(x.substr(who.length() + 1)) if x.contains(":") else []
				if x.contains(":") and hero.is_empty():
					push_error("unknown class or race in seat " + x + " (persona[:class[:race]])")
					return false
				_party.append(id)
				_party_heroes.append(hero)
			if _party.size() > 4 or _party.count(APPRENTICE) == _party.size():
				push_error("--party takes 1 to 4 seats and at least one persona")
				return false
	return true


## "class[:race]" (keys or indices) as [Classes index, Races index]; HUMAN when no race is given; [] when unknown.
func _parse_hero(spec: String) -> Array:
	var cs: String = spec.get_slice(":", 0).strip_edges().to_lower()
	var c: int = int(cs) if cs.is_valid_int() and int(cs) < Classes.count() else Classes.index_of(cs)
	var r: int = Races.HUMAN
	if spec.contains(":"):
		var rs: String = spec.get_slice(":", 1).strip_edges().to_lower()
		r = int(rs) if rs.is_valid_int() and int(rs) < Races.count() else Races.index_of(rs)
	if c < 0 or r < 0:
		return []
	return [c, r]


## ":knight", ":knight:orc" (a race other than HUMAN), or "" for no class.
func _hero_name(hero: Array) -> String:
	if hero.is_empty():
		return ""
	return ":" + Classes.key(int(hero[0])) + (":" + Races.key(int(hero[1])) if int(hero[1]) != Races.HUMAN else "")


## The party's name for the tables, e.g. "casual+2ap" or "casual:knight+casual:priest+ap:archer".
func _party_name() -> String:
	var names: PackedStringArray = []
	var n: int = 0
	for i: int in range(_party.size()):
		var hero: Array = _party_heroes[i] if i < _party_heroes.size() else []
		if _party[i] != APPRENTICE:
			names.append(SmashBot.persona_name(_party[i]) + _hero_name(hero))
		elif not hero.is_empty():
			names.append("ap" + _hero_name(hero))
		else:
			n += 1
	return "+".join(names) + ("+%dap" % n if n > 0 else "")


## The mean party level at minute `m`:00 ("-" when no run got that far).
func _level_at(g: Dictionary, m: int) -> String:
	var xs: Array = g.level
	return "%.1f" % float(xs[m - 1]) if xs.size() >= m else "-"


func _make_tune() -> Tuning:
	var tune := Tuning.new()
	for pair: String in _tune_pairs:
		if pair == "":
			continue
		if not tune.set_value(pair.get_slice(":", 0), float(pair.get_slice(":", 1))):
			push_error("unknown tuning field " + pair)
	return tune


## A Profile from a JSON file (Profile.to_dict, as the career tool's checkpoints write it), or null.
static func load_profile(path: String) -> Profile:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d: Variant = JSON.parse_string(f.get_as_text())
	return Profile.from_dict(d) if d is Dictionary else null


## --profile: its bonuses and, for each human seat of a run with `party` seats, one of its heroes.
func _profile_setup(wizards: int, party: Array[int]) -> void:
	if _profile == null:
		return
	_bonuses = _profile.bonuses()
	_seat_heroes = {}
	var n: int = 0
	for s: int in range(wizards):
		if s < party.size() and party[s] == APPRENTICE:
			continue
		_seat_heroes[s] = (_profile.heroes[mini(n, _profile.heroes.size() - 1)] as Hero).to_dict()
		n += 1


# ================================================================= RUN ===
## One run. `classes` holds each seat's hero [Classes index, Races index] or [] (no class: as before). A human seat
## with a class gets a level 1 Hero.make of it after World.new (where Arena would apply_meta first; the playtest
## applies no meta); an apprentice seat with one is seated with that class and the World makes it the hero. With
## _bonuses (the career tool, --profile) or --meta every seat gets World.apply_meta of them first, and a human seat in
## _seat_heroes plays that saved hero instead.
func _play(persona: int, wizards: int, seed_value: int, party: Array[int] = [], classes: Array = []) -> Dictionary:
	var slots: Array = range(wizards)
	var seats: Dictionary = {}
	for s: int in slots:
		var hero: Array = classes[s] if s < classes.size() else []
		if s < party.size() and party[s] == APPRENTICE:
			seats[s] = {"ai": true} if hero.is_empty() else {"ai": true, "cls": hero[0], "race": hero[1], "cls_level": 1}
	var w := World.new(slots, seed_value, _make_tune(), {}, seats)
	_last_world = w
	_profile_setup(wizards, party)
	if not _bonuses.is_empty() or not _meta.is_empty():
		w.apply_meta(_bonuses.merged(_meta, true))
	for s: int in slots:
		var hero: Array = classes[s] if s < classes.size() else []
		if not seats.has(s) and _seat_heroes.has(s):
			w.apply_hero(w.players[s], _seat_heroes[s])
		elif not seats.has(s) and not hero.is_empty():
			var p: World.Player = w.players[s]
			w.apply_hero(p, Hero.make(int(hero[1]), int(hero[0]), p.wizard).to_dict())
	w.apply_seal(_seal)
	w.apply_reading(_reading)
	var bots: Dictionary = {}
	for s: int in slots:
		if not seats.has(s): # an apprentice is played by the World itself
			bots[s] = SmashBot.new(seed_value * 10 + s, party[s] if s < party.size() else persona)
	var r := {
		"seed": seed_value, "won": false, "end": 0.0, "wipe": -1.0, "first_down": -1.0, "outs": [],
		"downs": 0, "hits": 0, "hits_by": {}, "level": [], "picks": [], "pressure": [], "dead_air": [],
		"offered": {}, "taken": {}, "spell_level": {}, "evolutions": [], "xp_expired": 0, "xp_expired_value": 0,
		"xp_dropped": 0, "gold": 0.0, "spent": 0.0, "bets": {}, "bosses": [], "damage": {}, "damage_total": 0.0,
		"kills": [], "shrines": 0, "arch": -1.0, "arch_slain": false, "wiz_hits": [], "wiz_pressure": [],
		"human_down": -1.0, "skills": {}, "loot": {}, "unfinished": false,
	}
	var cards_seen: Dictionary = {} # Pickup -> true, for the monster cards that dropped (by source, _card_source)
	var offers: Dictionary = {}
	for s: int in slots:
		offers[s] = 0
	var picks_min: Array[int] = []
	var press_sum: Array[float] = []
	var press_n: Array[int] = []
	var air: Array[float] = []
	var kills_min: Array[int] = []
	var wiz_hits: Array[int] = []
	var wiz_press: Array[float] = []
	var wiz_press_n: Array[int] = []
	for s: int in slots:
		wiz_hits.append(0)
		wiz_press.append(0.0)
		wiz_press_n.append(0)
	var boss_row: Dictionary = {}
	var xp_seen: Dictionary = {} # Pickup -> true, for the XP motes on the floor
	var tick: int = 0
	var cap: float = _minutes * 60.0
	while w.phase != World.PH_GAMEOVER and w.wave_time < cap:
		var minute: int = int(w.wave_time / 60.0)
		while picks_min.size() <= minute:
			picks_min.append(0)
			press_sum.append(0.0)
			press_n.append(0)
			air.append(0.0)
			kills_min.append(0)
			(r.level as Array).append(0.0)
		var inputs: Dictionary = {}
		var picking: Dictionary = {}
		for s: int in bots:
			inputs[s] = (bots[s] as SmashBot).decide_in_world(w, s)
		for s: int in slots:
			picking[s] = not (w.players[s] as World.Player).choices.is_empty()
		# XP motes about to fade: after the step, one that is gone and was not picked up (life -1) expired.
		var fading: Array[World.Pickup] = []
		for k: World.Pickup in w.pickups:
			if k.kind == World.PK_XP:
				if not xp_seen.has(k):
					xp_seen[k] = true
					r.xp_dropped += 1
				if k.life <= DT * 1.5:
					fading.append(k)
		# Enemy shots close enough to hit a wizard this step: a hit with one of them gone is a shot hit.
		var near_shots: Array = []
		for e_s: Variant in w.eshots:
			for p: World.Player in w.players.values():
				if p.alive and (e_s.pos as Vector2).distance_to(p.pos + Vector2(0, -6)) < float(e_s.r) + 12.0 + (e_s.vel as Vector2).length() * DT:
					near_shots.append(e_s)
					break
		var boss_before: World.Enemy = w.boss
		var kills_before: int = w.total_kills()
		var foes_before: Array[World.Enemy] = w.enemies.duplicate()
		w.step(DT, inputs)
		for k: World.Pickup in w.pickups:
			if k.kind == World.PK_CARD and not cards_seen.has(k):
				cards_seen[k] = true
				var src: String = "card_" + _card_source(k, foes_before)
				r.loot[src] = int(r.loot.get(src, 0)) + 1
		kills_min[minute] += w.total_kills() - kills_before
		tick += 1
		for k: World.Pickup in fading:
			if k.life > -0.5 and k.life <= 0.0:
				r.xp_expired += 1
				r.xp_expired_value += k.value
			xp_seen.erase(k)
		for ev: Array in w.take_events():
			match int(ev[0]):
				World.EV_HURT:
					r.hits += 1
					var hs: int = slots.find(int(ev[3]))
					if hs >= 0:
						wiz_hits[hs] += 1
					var by: String = _hit_cause(w, Vector2(ev[1], ev[2] + 6.0), near_shots)
					r.hits_by[by] = int(r.hits_by.get(by, 0)) + 1
				World.EV_PDIE:
					r.downs += 1
					if r.first_down < 0.0:
						r.first_down = w.wave_time
					if r.human_down < 0.0 and not seats.has(int(ev[3])):
						r.human_down = w.wave_time
					if int(ev[4]) <= 0:
						(r.outs as Array).append(w.wave_time)
					if not boss_row.is_empty():
						boss_row.downs += 1
				World.EV_PICK:
					if picking.get(int(ev[3]), false):
						var idx: int = int(ev[4])
						r.taken[Upgrades.key(idx)] = int(r.taken.get(Upgrades.key(idx), 0)) + 1
				World.EV_GAMBLE:
					var key: String = _bet_name(int(ev[4]))
					r.bets[key] = int(r.bets.get(key, 0)) + 1
					r.shrines += 1
				World.EV_VICTORY:
					r.won = true
				World.EV_SKILL:
					var sk: String = Classes.skill_key(int(ev[4]))
					r.skills[sk] = int(r.skills.get(sk, 0)) + 1
				World.EV_HEAL:
					r.skills["hearts healed"] = int(r.skills.get("hearts healed", 0)) + int(ev[4])
				World.EV_CHEST: # b = item * 8 + tier
					var tier: String = Loot.RARITY_NAMES[int(ev[4]) % 8].to_lower()
					r.loot[tier] = int(r.loot.get(tier, 0)) + 1
		for s: int in slots:
			var p: World.Player = w.players[s]
			if p.offer != offers[s]:
				offers[s] = p.offer
				picks_min[minute] += 1
				for idx: int in p.choices:
					r.offered[Upgrades.key(idx)] = int(r.offered.get(Upgrades.key(idx), 0)) + 1
		# Lich visits and the Archlich.
		if w.boss != null and boss_before == null:
			boss_row = {"at": w.wave_time, "final": w.boss.final, "fight": -1.0, "downs": 0, "kind": str(Bestiary.KINDS[w.boss.type][0])}
		if not boss_row.is_empty():
			if w.boss != null and w.boss.final:
				boss_row.final = true
			if w.boss == null or w.phase == World.PH_GAMEOVER:
				boss_row.fight = w.wave_time - float(boss_row.at)
				boss_row.slain = w.boss == null
				if boss_row.final:
					r.arch = boss_row.fight
					r.arch_slain = boss_row.slain
				(r.bosses as Array).append(boss_row)
				boss_row = {}
		if tick % SAMPLE == 0 and w.phase == World.PH_FIGHT and not w.won and not w.is_picking():
			var near: float = INF
			var crowd: int = 0
			var alive: int = 0
			for p: World.Player in w.players.values():
				if not p.alive:
					continue
				alive += 1
				var own: int = 0
				for e: World.Enemy in w.enemies:
					var d: float = e.pos.distance_to(p.pos)
					near = minf(near, d)
					if d < PRESSURE_R:
						own += 1
				crowd += own
				var ps: int = slots.find(p.slot)
				wiz_press[ps] += own
				wiz_press_n[ps] += 1
			if alive > 0:
				press_sum[minute] += float(crowd) / alive
				press_n[minute] += 1
				if near > DEAD_AIR_R:
					air[minute] += DT * SAMPLE
		var lv: float = 0.0
		for p: World.Player in w.players.values():
			lv += p.level
		r.level[minute] = lv / wizards
	if not boss_row.is_empty():
		boss_row.fight = w.wave_time - float(boss_row.at)
		boss_row.slain = false
		if boss_row.final:
			r.arch = boss_row.fight
		(r.bosses as Array).append(boss_row)
	r.end = w.wave_time
	r.won = r.won or w.won
	if w.phase == World.PH_GAMEOVER and not w.won:
		r.wipe = w.wave_time
	r.unfinished = not r.won and w.phase != World.PH_GAMEOVER
	r.picks = picks_min
	for m: int in range(press_sum.size()):
		(r.pressure as Array).append(press_sum[m] / maxi(1, press_n[m]))
	r.dead_air = air
	r.kills = kills_min
	var run_min: float = maxf(w.wave_time / 60.0, 0.01)
	for i: int in range(slots.size()):
		(r.wiz_hits as Array).append(float(wiz_hits[i]) / run_min)
		(r.wiz_pressure as Array).append(wiz_press[i] / maxi(1, wiz_press_n[i]))
	for p: World.Player in w.players.values():
		for sp: int in range(Spells.COUNT):
			var key: String = Upgrades.key(Upgrades.weapon_entry(sp))
			var lvl: int = Upgrades.weapon_level(p.upgrades, sp) + Upgrades.evo_of(p.upgrades, sp)
			r.spell_level[key] = maxi(int(r.spell_level.get(key, 0)), lvl)
		r.gold += w.record.stat(p.slot, "gold")
		r.spent += w.record.stat(p.slot, "bets")
	for m: Array in w.record.moments:
		if int(m[1]) == Results.M_EVOLVE:
			(r.evolutions as Array).append([float(m[0]), Upgrades.key(int(m[3]))])
	for src: int in w.record.source_damage:
		var amount: float = w.record.source_damage[src]
		r.damage[_source_name(src)] = amount
		r.damage_total += amount
	return r


## Where a monster card that just dropped came from: "urn", "seal" (a Seal's Archlich), else the kill that dropped
## it this step (the nearest enemy of `foes` now dead): "boss" (a Lich or the Archlich), "elite" or "kill".
func _card_source(k: World.Pickup, foes: Array[World.Enemy]) -> String:
	if k.value >= World.URN_CARD:
		return "urn"
	var best: World.Enemy = null
	for e: World.Enemy in foes:
		if e.dead and (best == null or e.pos.distance_squared_to(k.pos) < best.pos.distance_squared_to(k.pos)):
			best = e
	if best == null:
		return "kill"
	if best.final and k.value == Seals.card(_seal) and k.value >= 0:
		return "seal"
	if best.type == World.LICH or best.final:
		return "boss"
	return "elite" if best.elite else "kill"


## What hurt a wizard at `at` (its feet): a hot hazard row she stands in ("hz_fire", ...), an enemy shot near it that
## died this step, else an enemy body touching it, else `other` (a body killed in the same step).
func _hit_cause(w: World, at: Vector2, near_shots: Array) -> String:
	const ROWS := ["mark", "blast", "fire", "flame", "fall", "beam", "burst", "lane", "safe"]
	for h: Hazards.Hazard in w.hazards:
		var row: Array = Hazards.KINDS[h.kind]
		if h.warn <= 0.0 and int(row[Hazards.K_HEARTS]) > 0 and Hazards.contains(h, at) != bool(row[Hazards.K_INVERTED]):
			return "hz_" + str(ROWS[h.kind])
	for e_s: Variant in near_shots:
		if e_s.dead and (e_s.pos as Vector2).distance_to(at + Vector2(0, -6)) < float(e_s.r) + 12.0:
			const KINDS := ["arrow", "orb", "skull", "sword"]
			var kind: int = int(e_s.kind)
			return "shot:" + (KINDS[kind] if kind < KINDS.size() else str(kind)) + ("_boss" if w.boss != null else "")
	var best: String = "other"
	var bd: float = 8.0
	for e: World.Enemy in w.enemies:
		var d: float = e.pos.distance_to(at) - e.r
		if d < bd:
			bd = d
			best = _enemy_name(e)
	return best


func _enemy_name(e: World.Enemy) -> String:
	const NAMES := ["goblin", "skeleton", "slime", "mslime", "bat", "orc", "mage", "lich", "wraith", "tome",
		"gargoyle", "priest"]
	var n: String = NAMES[e.type] if e.type < NAMES.size() else "enemy%d" % e.type
	return ("arch" + n) if e.final else n


func _source_name(src: int) -> String:
	if src == Results.SRC_NOVA:
		return "nova"
	if src == Results.SRC_ORBIT:
		return "orbit"
	if src == Results.SRC_JUSTICE:
		return "justice"
	if src >= 0 and src < Spells.COUNT:
		return Upgrades.key(Upgrades.weapon_entry(src)).trim_prefix("w_")
	return "other"


func _bet_name(code: int) -> String:
	var kind: int = code / 16
	var outcome: int = code % 16
	if kind == Gamble.TEAM:
		return "team_" + String(Gamble.TEAM_OUTCOMES[outcome][0]) # team_blessing, team_curse, team_world...
	match outcome:
		Gamble.SO_JACKPOT:
			return "jackpot"
		Gamble.SO_CHEST:
			return "chest"
		Gamble.SO_DOUBLE:
			return "double"
		Gamble.SO_NOTHING:
			return "nothing"
		Gamble.SO_CURSE:
			return "curse"
	return "solo%d" % outcome


# ========================================================== AGGREGATE ===
func _stats(xs: Array) -> Dictionary:
	if xs.is_empty():
		return {"n": 0, "med": -1.0, "min": -1.0, "max": -1.0}
	var a: Array = xs.duplicate()
	a.sort()
	var n: int = a.size()
	var med: float = float(a[n / 2]) if n % 2 == 1 else (float(a[n / 2 - 1]) + float(a[n / 2])) * 0.5
	return {"n": n, "med": med, "min": float(a[0]), "max": float(a[n - 1])}


func _mean_series(runs: Array, key: String) -> Array:
	var sum: Array[float] = []
	var cnt: Array[int] = []
	for r: Dictionary in runs:
		var xs: Array = r[key]
		for i: int in range(xs.size()):
			while sum.size() <= i:
				sum.append(0.0)
				cnt.append(0)
			sum[i] += float(xs[i])
			cnt[i] += 1
	var out: Array = []
	for i: int in range(sum.size()):
		out.append(sum[i] / maxi(1, cnt[i]))
	return out


func _sum_dicts(runs: Array, key: String) -> Dictionary:
	var out: Dictionary = {}
	for r: Dictionary in runs:
		var d: Dictionary = r[key]
		for k: Variant in d:
			out[k] = float(out.get(k, 0.0)) + float(d[k])
	return out


func _aggregate(persona: int, wizards: int, runs: Array) -> Dictionary:
	var minutes: float = 0.0
	var ends: Array = []
	var wipes: Array = []
	var firsts: Array = []
	var hfirsts: Array = []
	var outs: Array = []
	var wins: int = 0
	var unfinished: int = 0
	var downs: float = 0.0
	var hits: float = 0.0
	var dmg: float = 0.0
	var picks: float = 0.0
	var evo_runs: int = 0
	var evo_t: Array = []
	var xp_exp: float = 0.0
	var xp_drop: float = 0.0
	var gold: float = 0.0
	var spent: float = 0.0
	var lv: Dictionary = {}
	var shrines: float = 0.0
	var arch: Array = []
	var arch_slain: int = 0
	var wiz_hits: Array = []
	var wiz_press: Array = []
	for i: int in range(wizards):
		wiz_hits.append(0.0)
		wiz_press.append(0.0)
	for r: Dictionary in runs:
		shrines += float(r.shrines)
		if float(r.arch) >= 0.0:
			arch.append(r.arch)
			arch_slain += 1 if r.arch_slain else 0
		for i: int in range(wizards):
			wiz_hits[i] += float(r.wiz_hits[i]) / runs.size()
			wiz_press[i] += float(r.wiz_pressure[i]) / runs.size()
		minutes += float(r.end) / 60.0
		ends.append(r.end)
		if r.won:
			wins += 1
		if r.unfinished:
			unfinished += 1
		if float(r.wipe) >= 0.0:
			wipes.append(r.wipe)
		if float(r.first_down) >= 0.0:
			firsts.append(r.first_down)
		if float(r.human_down) >= 0.0:
			hfirsts.append(r.human_down)
		for o: float in r.outs:
			outs.append(o)
		downs += r.downs
		hits += r.hits
		dmg += r.damage_total
		for p: int in r.picks:
			picks += p
		if not (r.evolutions as Array).is_empty():
			evo_runs += 1
			evo_t.append(r.evolutions[0][0])
		xp_exp += r.xp_expired
		xp_drop += r.xp_dropped
		gold += r.gold
		spent += r.spent
		for k: String in r.spell_level:
			lv[k] = float(lv.get(k, 0.0)) + float(r.spell_level[k]) / runs.size()
	var mins: float = maxf(minutes, 0.01)
	var visits: Array = []
	for i: int in range(6):
		var at: Array = []
		var fight: Array = []
		var bd: Array = []
		var slain: int = 0
		var final: bool = false
		var kind: String = "lich"
		for r: Dictionary in runs:
			if i < (r.bosses as Array).size():
				var b: Dictionary = r.bosses[i]
				at.append(b.at)
				fight.append(b.fight)
				bd.append(b.downs)
				slain += 1 if b.get("slain", false) else 0
				final = final or b.final
				kind = str(b.get("kind", kind))
		if not at.is_empty():
			visits.append({"n": at.size(), "final": final, "kind": kind, "at": _stats(at), "fight": _stats(fight),
				"downs": _stats(bd), "slain": slain})
	return {
		"persona": SmashBot.persona_name(persona), "wizards": wizards, "runs": runs, "wins": wins, "unfinished": unfinished,
		"end": _stats(ends), "wipe": _stats(wipes), "first_down": _stats(firsts), "out": _stats(outs),
		"human_down": _stats(hfirsts),
		"downs_per_min": downs / mins, "hits_per_min": hits / mins, "picks_per_min": picks / mins,
		"damage_per_min": dmg / mins, "level": _mean_series(runs, "level"), "picks": _mean_series(runs, "picks"),
		"pressure": _mean_series(runs, "pressure"), "dead_air": _mean_series(runs, "dead_air"),
		"damage": _sum_dicts(runs, "damage"), "offered": _sum_dicts(runs, "offered"), "taken": _sum_dicts(runs, "taken"),
		"hits_by": _sum_dicts(runs, "hits_by"), "bets": _sum_dicts(runs, "bets"), "spell_level": lv,
		"evo_runs": evo_runs, "first_evo": _stats(evo_t), "xp_expired": xp_exp, "xp_dropped": xp_drop,
		"gold": gold / runs.size(), "spent": spent / runs.size(), "bosses": visits,
		"kills": _mean_series(runs, "kills"), "shrines": shrines / runs.size(), "arch": _stats(arch),
		"arch_slain": arch_slain, "wiz_hits_per_min": wiz_hits, "wiz_pressure": wiz_press,
		"skills": _sum_dicts(runs, "skills"), "loot": _sum_dicts(runs, "loot"), "loot_runs": _loot_runs(runs),
	}


## How many runs had at least one of each loot count (a chest tier opened, a card source).
func _loot_runs(runs: Array) -> Dictionary:
	var out: Dictionary = {}
	for r: Dictionary in runs:
		for k: String in r.loot:
			if int(r.loot[k]) > 0:
				out[k] = int(out.get(k, 0)) + 1
	return out


# ============================================================== PRINT ===
func _print_group(g: Dictionary) -> void:
	var n: int = (g.runs as Array).size()
	print("== %s x%d: %d runs, seeds %d-%d, %s ==" % [g.persona, g.wizards, n, _seed, _seed + n - 1, Seals.title(_seal)])
	print("win %d/%d  unfinished %d  end %s  wipe %s  first down %s  human down %s  out %s" % [g.wins, n, g.unfinished, _span(g.end), _span(g.wipe),
		_span(g.first_down), _span(g.human_down), _span(g.out)])
	print("per min: downs %.2f  hits %.2f  picks %.2f  damage %.0f" % [g.downs_per_min, g.hits_per_min,
		g.picks_per_min, g.damage_per_min])
	var head := "minute "
	var rows := {"level": "level  ", "picks": "picks  ", "pressure": "press  ", "dead_air": "air s  ", "kills": "kills  "}
	var cols: int = (g.level as Array).size()
	for m: int in range(cols):
		head += "%6d" % (m + 1)
		for key: String in rows:
			var xs: Array = g[key]
			var fmt: String = "%6.0f" if key == "kills" else "%6.1f"
			rows[key] += (fmt % float(xs[m])) if m < xs.size() else "     -"
	print(head)
	for key: String in rows:
		print(rows[key])
	print("damage   " + _shares(g.damage))
	print("hits by  " + _shares(g.hits_by))
	var lv: PackedStringArray = []
	for k: String in g.spell_level:
		lv.append("%s %.1f" % [k.trim_prefix("w_"), float(g.spell_level[k])])
	print("spell lv " + "  ".join(lv))
	print("taken    " + _taken(g.offered, g.taken))
	print("evolved  %d/%d runs, first %s" % [g.evo_runs, n, _span(g.first_evo)])
	print("xp lost  %d of %d motes  gold %.0f earned %.0f spent  bets %s" % [g.xp_expired, g.xp_dropped, g.gold,
		g.spent, _counts(g.bets)])
	print("shrines %.1f per run  archlich fight %s  slain %d" % [g.shrines, _span(g.arch), g.arch_slain])
	var wl: PackedStringArray = []
	for i: int in range(int(g.wizards)):
		wl.append("w%d press %.1f hits/min %.2f" % [i + 1, float(g.wiz_pressure[i]), float(g.wiz_hits_per_min[i])])
	print("per wiz  " + "  ".join(wl))
	print("loot     %s  (runs with: %s)" % [_counts(g.loot), _counts(g.loot_runs)]) # chest tiers opened, cards dropped by source
	if not (g.skills as Dictionary).is_empty(): # class skills (EV_SKILL) and hearts they healed, summed over the runs
		print("skills   " + _counts(g.skills))
	for i: int in range((g.bosses as Array).size()):
		var b: Dictionary = g.bosses[i]
		print("boss %d %s: came %s  fight %s  downs %s  slain %d/%d" % [i + 1, "ARCH" if b.final else str(b.get("kind", "lich")),
			_span(b.at), _span(b.fight), _span_n(b.downs), b.slain, b.n])


func _span(s: Dictionary) -> String:
	if int(s.n) == 0:
		return "-"
	return "%s [%s..%s]" % [_clock(s.med), _clock(s.min), _clock(s.max)]


func _span_n(s: Dictionary) -> String:
	if int(s.n) == 0:
		return "-"
	return "%.1f [%d..%d]" % [s.med, int(s.min), int(s.max)]


func _shares(d: Dictionary) -> String:
	var total: float = 0.0
	for k: Variant in d:
		total += float(d[k])
	if total <= 0.0:
		return "-"
	var keys: Array = d.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return float(d[a]) > float(d[b]))
	var out: PackedStringArray = []
	for k: Variant in keys:
		out.append("%s %d%%" % [k, roundi(100.0 * float(d[k]) / total)])
	return "  ".join(out)


func _taken(offered: Dictionary, taken: Dictionary) -> String:
	var keys: Array = offered.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return float(taken.get(a, 0.0)) > float(taken.get(b, 0.0)))
	var out: PackedStringArray = []
	for k: Variant in keys:
		out.append("%s %d/%d" % [k, int(taken.get(k, 0.0)), int(offered[k])])
	return "  ".join(out)


func _counts(d: Dictionary) -> String:
	var out: PackedStringArray = []
	for k: Variant in d:
		out.append("%s %d" % [k, int(d[k])])
	return " ".join(out) if not out.is_empty() else "-"


func _clock(t: float) -> String:
	if t < 0.0:
		return "-"
	return "%d:%02d" % [int(t) / 60, int(t) % 60]

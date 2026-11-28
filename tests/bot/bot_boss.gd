extends RefCounted
## The boss shard and the win shard (docs/bots.md, "The boss shard" and "The win shard"): four seated saved heroes play
## a run whose clock is moved to just before a boss (the way `--autotest=<wave>` does it), fight it for FIGHT_SECONDS of
## run clock, and the boss is felled through World.damage_enemy. The boss shard stops once it has paid; the win shard
## waits for the victory countdown and the results, then checks the booking. Used by bot.gd (`-- --boss`, `-- --win`).
const Heroes := preload("res://tests/bot/bot_heroes.gd")

## Run seconds the bots fight the boss before it is felled.
const FIGHT_SECONDS: float = 20.0
## The boss comes this long after its minute mark (the spawn queue's 2.5 s) plus a few frames.
const ARRIVE_SLACK: float = 4.0
## Run seconds past the boss's minute after which a boss that never came is a fault.
const WAIT_SECONDS: float = 30.0
## Ticks the felling may take (a boss turning a phase stands untouchable for a few seconds).
const FELL_TICKS: int = 900
## Game seconds after the fall the shard goes on watching (the arena handles the events), and for the win shard the
## longest wait for the victory countdown and the results.
const AFTER_SECONDS: float = 1.0
const RESULTS_WAIT: float = 20.0
## The Seal step the win shard plays: ARCHMAGE, so a first win moves the ladder (a win at WIZARD opens no new step).
const WIN_SEAL: int = 1
## Deeds a first win of this party (HUMAN MAGE, ELF ARCHER, DWARF KNIGHT, ORC PRIEST; ARCHMAGE; over ten minutes)
## always earns. FLAWLESS and the rest depend on how the bots fared and are not asked for.
const WIN_DEEDS: Array = ["ARCHLICH", "PARTY_WIN", "LICH", "TEN_MINUTES", "WIN_MAGE", "WIN_ARCHER", "WIN_KNIGHT",
	"WIN_PRIEST", "WIN_ARCHMAGE"]

enum S { JUMP, WAIT_BOSS, FIGHT, FELL, AFTER, RESULTS, DONE }

var final: bool = false
var name: String = "boss"
var state: int = S.JUMP
var faults: Array[String] = []
var done: bool = false
var summary: String = ""
var profile: Profile = null
var before: Dictionary = {}
var seated: Array[int] = []
var seal_before: Array = []

var _row: Array = []
var _boss: World.Enemy = null
var _arrived_at: float = -1.0
var _arrived_wave: int = 0
var _maxhp: float = 0.0
var _hp_at_fell: float = 0.0
var _fell_ticks: int = 0
var _fell_t: float = 0.0
var _evs: Array = []
var _res_t: float = 0.0


func _init(is_final: bool, prof: Profile, was: Dictionary, seats: Array[int]) -> void:
	final = is_final
	name = "win" if is_final else "boss"
	profile = prof
	before = was
	seated = seats
	before["wins"] = prof.wins
	before["seal_best"] = prof.seal_best
	before["seal_unlocked"] = prof.seal_unlocked
	before["prizes"] = prof.seal_prizes.duplicate()
	before["deeds"] = prof.deeds.duplicate()


## One tick (the bot's physics step, before the arena's). `arena` is the run's Arena node.
func step(arena: Node, w: World) -> void:
	if done or w == null:
		return
	match state:
		S.JUMP:
			for line: String in Heroes.check_start(w, profile):
				faults.append(line.replace("BOT heroes ", ""))
			_row = _boss_row(w)
			# What `--autotest=<wave>` does (game/debug/autotest.gd): the run clock just before the minute mark; the
			# horde announces the minute and the schedule brings the boss itself.
			var minute: int = int(float(_row[0]) / 60.0)
			w.wave = minute
			w.wave_time = minute * 60.0 - 0.5
			state = S.WAIT_BOSS
		S.WAIT_BOSS:
			if w.phase == World.PH_GAMEOVER:
				_fail("the party fell before the boss came (clock %.1fs)" % w.wave_time)
			elif w.boss != null:
				_arrived(w)
			elif w.wave_time > float(_row[0]) + WAIT_SECONDS:
				_fail("no boss by run second %.0f (scheduled %.0f)" % [w.wave_time, float(_row[0])])
		S.FIGHT:
			if w.phase == World.PH_GAMEOVER:
				_fail("the party fell %.1fs into the boss fight, before the forced end" % (w.wave_time - _arrived_at))
			elif w.wave_time - _arrived_at >= FIGHT_SECONDS:
				_boss = w.boss
				_hp_at_fell = _boss.hp if _boss != null else 0.0
				state = S.FELL
				_fell(w)
		S.FELL:
			_fell(w)
		S.AFTER:
			_res_t += w.wave_time - _fell_t if not final else 0.0
			if w.wave_time - _fell_t >= AFTER_SECONDS:
				_finish_boss(w, arena)
		S.RESULTS:
			_res_t += 1.0 / 60.0
			var booked: bool = arena.get("game_over") and arena.get("results") != null
			if booked:
				_finish_win(w, arena)
			elif _res_t > RESULTS_WAIT:
				_fail("the results did not come %.0fs after the Archlich fell (won=%s phase=%d)" % [RESULTS_WAIT, w.won, w.phase])


func _boss_row(w: World) -> Array:
	for row: Array in w.schedule:
		if bool(row[2]) == final:
			return row
	return w.schedule[0]


func _arrived(w: World) -> void:
	_arrived_at = w.wave_time
	_arrived_wave = w.wave
	_maxhp = w.boss.maxhp
	var at: float = float(_row[0])
	if _arrived_at < at or _arrived_at > at + ARRIVE_SLACK:
		faults.append("boss came at run second %.2f, scheduled %.0f (+%.1fs allowed)" % [_arrived_at, at, ARRIVE_SLACK])
	if w.boss.type != int(_row[1]):
		faults.append("boss type %d, scheduled %d" % [w.boss.type, int(_row[1])])
	if w.boss.final != final:
		faults.append("boss final=%s, expected %s" % [w.boss.final, final])
	if _arrived_wave != int(at / 60.0) + 1:
		faults.append("minute %d when the boss came, expected %d" % [_arrived_wave, int(at / 60.0) + 1])
	state = S.FIGHT


## Fells the boss through World.damage_enemy, once per tick until it is dead (a phase turn blocks the blow). The events
## the call adds are read before the arena's step takes them.
func _fell(w: World) -> void:
	var b: World.Enemy = _boss
	var slot: int = int(w.players.keys()[0])
	if b == null or b.dead:
		_fail("the boss was gone before the forced end")
		return
	var from: int = w.events.size()
	var chests_before: int = _chests_on_the_floor(w)
	w.damage_enemy(b, b.maxhp * 8.0, slot, Vector2.ZERO, true)
	_evs.append_array(w.events.slice(from))
	_fell_ticks += 1
	if b.dead:
		_fell_t = w.wave_time
		state = S.AFTER if not final else S.RESULTS
		_check_payout(w, slot, _chests_on_the_floor(w) - chests_before)
	elif _fell_ticks > FELL_TICKS:
		_fail("the boss survived %d blows through World.damage_enemy (hp %.0f turn %.2f)" % [_fell_ticks, b.hp, b.turn])


func _count(code: int) -> int:
	var n := 0
	for ev: Array in _evs:
		if int(ev[0]) == code:
			n += 1
	return n


func _chests_on_the_floor(w: World) -> int:
	var n := 0
	for k: World.Pickup in w.pickups:
		if k.kind == World.PK_CHEST:
			n += 1
	return n


## What a boss kill pays, read the moment it dies: the events, the record, the drops (`chests`: the chests its death
## added; an act boss drops one per wizard, the final boss none, only its burst of gems and coins).
func _check_payout(w: World, slot: int, chests: int) -> void:
	if _hp_at_fell >= _maxhp - 0.01:
		faults.append("the bots did no damage to the boss in %.0fs (hp %.0f of %.0f)" % [FIGHT_SECONDS, _hp_at_fell, _maxhp])
	if _count(World.EV_BOSSDIE) != 1:
		faults.append("EV_BOSSDIE count %d, expected 1" % _count(World.EV_BOSSDIE))
	else:
		for ev: Array in _evs:
			if int(ev[0]) == World.EV_BOSSDIE and int(ev[4]) != (1 if final else 0):
				faults.append("EV_BOSSDIE final flag %d, expected %d" % [int(ev[4]), 1 if final else 0])
	if w.liches_slain != 1:
		faults.append("record boss count (liches_slain) %d, expected 1" % w.liches_slain)
	var kinds: int = Results.M_ARCHLICH if final else Results.M_ACT_BOSS
	var moments := 0
	for m: Array in w.record.moments:
		if int(m[1]) == kinds and int(m[2]) == slot:
			moments += 1
			if not final and int(m[3]) != int(_row[1]):
				faults.append("the record names act boss %d, expected %d" % [int(m[3]), int(_row[1])])
	if moments != 1:
		faults.append("record moments of kind %d by slot %d: %d, expected 1" % [kinds, slot, moments])
	var gems := 0
	for k: World.Pickup in w.pickups:
		if k.kind == World.PK_GEM or k.kind == World.PK_COIN:
			gems += 1
	var chests_due: int = 0 if final else w.players.size()
	if chests != chests_due:
		faults.append("%d chests dropped, expected %d (one per wizard from an act boss, none from the final boss)" % [chests, chests_due])
	if gems < 14:
		faults.append("%d gems and coins dropped, expected at least 14" % gems)
	if w.boss != null:
		faults.append("World.boss is still set after the boss died")
	if final:
		if _count(World.EV_VICTORY) != 1:
			faults.append("EV_VICTORY count %d, expected 1" % _count(World.EV_VICTORY))
		elif _index_of(World.EV_VICTORY) < _index_of(World.EV_BOSSDIE):
			faults.append("EV_VICTORY came before EV_BOSSDIE")
		if not w.won:
			faults.append("World.won is false after the Archlich died")
		if _count(World.EV_LULL) != 0:
			faults.append("a lull began after the Archlich")
	else:
		if _count(World.EV_VICTORY) != 0 or w.won:
			faults.append("the run was won by an act boss")
		if w.tune.lull_seconds > 0.0 and (_count(World.EV_LULL) != 1 or w.lull_left <= 0.0):
			faults.append("no lull after the act boss (EV_LULL %d, lull_left %.1f)" % [_count(World.EV_LULL), w.lull_left])


func _index_of(code: int) -> int:
	for i: int in _evs.size():
		if int(_evs[i][0]) == code:
			return i
	return -1


func _seats_ok(w: World) -> void:
	if w.players.size() != seated.size() or Net.roster.size() != seated.size():
		faults.append("seats: %d wizards in the World and %d in the roster, expected %d" % [w.players.size(), Net.roster.size(), seated.size()])


func _finish_boss(w: World, arena: Node) -> void:
	_seats_ok(w)
	if w.phase == World.PH_GAMEOVER:
		faults.append("the run ended during the boss fight")
	_done("BOT boss PASS seats=%d boss=%d came=%.1fs hp=%.0f/%.0f chests=%d" % [seated.size(), int(_row[1]), _arrived_at,
		_hp_at_fell, _maxhp, w.players.size()])


## The win shard's end: the arena booked the win (G.finish_run) in memory; check the profile against the run.
func _finish_win(w: World, arena: Node) -> void:
	_seats_ok(w)
	if not bool(arena.get("victory")):
		faults.append("the arena does not report a victory")
	var seal: int = int(arena.get("seal"))
	if seal != WIN_SEAL:
		faults.append("the run's Seal step is %d, expected %d" % [seal, WIN_SEAL])
	faults.append_array(Heroes.check_end(profile, before, seated))
	if profile.wins != int(before.wins) + 1:
		faults.append("wins expected %d got %d" % [int(before.wins) + 1, profile.wins])
	var pay: Dictionary = profile.last_pay
	var mul: float = Seals.crystal_mul(seal)
	var floor_pay: int = Profile.bounty(1, true, mul) + int(pay.get("prize", 0)) + int(pay.get("deeds_pay", 0))
	if profile.crystals - int(before.crystals) < floor_pay:
		faults.append("crystals grew by %d, a first win at step %d pays at least %d" % [profile.crystals - int(before.crystals), seal, floor_pay])
	if profile.seal_best != maxi(int(before.seal_best), seal):
		faults.append("seal_best expected %d got %d" % [maxi(int(before.seal_best), seal), profile.seal_best])
	var open: int = clampi(maxi(int(before.seal_unlocked), seal + 1), Seals.START_UNLOCKED, Seals.MAX)
	if profile.seal_unlocked != open or open <= int(before.seal_unlocked):
		faults.append("seal_unlocked expected %d (was %d) got %d" % [open, int(before.seal_unlocked), profile.seal_unlocked])
	if Seals.prize(seal) > 0:
		if not profile.prize_claimed(seal):
			faults.append("the first-win prize of step %d is not claimed" % seal)
		elif int(pay.get("prize", 0)) != Seals.prize(seal):
			faults.append("last_pay prize %d, expected %d" % [int(pay.get("prize", 0)), Seals.prize(seal)])
	for api: String in WIN_DEEDS:
		if not profile.deeds.has(api):
			faults.append("deed %s missing from the profile" % api)
	if profile.deeds.has("SOLO_WIN"):
		faults.append("deed SOLO_WIN earned by a party of four")
	_done("BOT win PASS seats=%d wins=%d runs=%d crystals=%d (+%d) seal_best=%d unlocked=%d deeds=%d levels=%s" % [seated.size(),
		profile.wins, profile.runs, profile.crystals, profile.crystals - int(before.crystals), profile.seal_best,
		profile.seal_unlocked, profile.deeds.size(), profile.last_hero_levels])


func _fail(why: String) -> void:
	faults.append(why)
	_done("")


func _done(pass_line: String) -> void:
	done = true
	summary = pass_line

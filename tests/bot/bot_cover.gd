extends Node
## The coverage robot (docs/stage3_brief.md § 4.4, the Test letter B of docs/content_list.md § 36). For each row of its
## share: a fresh run of the real game (the arena, headless, the play-bots playing), the row dealt by force to the first
## seat before the first step, play until the row is credited and AFTER_SECONDS more (so its effect is drawn), or until
## a ceiling of game time; then the next row in the same process. Rows come from the families in tests/bot/cover/.
## Run: godot --headless --fixed-fps 60 --path . res://tests/bot/bot.tscn -- --cover --shard=I --nshards=N
##      ... -- --cover --deal=<key>        one row
##      ... -- --cover --deal=<key> --unpend=<key>   the proof that a never-credited row fails (that key is not pending)
## One line a row: `COVER <key> ok uses=N t=<game s>` (N: the use counter, or the whole damage points of a damage row),
## `COVER <key> pending` or `COVER <key> FAIL <why>`; then `BOT cover ... PASS|FAIL ` for tools/check_all.sh and last
## `COVER rows=R ok=A pending=P failed=F secs=<wall s>`. Exit status 1 when F > 0.

## The folder of the families: every script in it but the contract (family.gd) is one family.
const FAMILY_DIR := "res://tests/bot/cover"
const FAMILY_BASE := "family.gd"
## Rows dealt and played but not failed for a missing credit: nothing credits them yet (a later job does). A pending row
## that is credited fails, so the list cannot rot; an engine error fails it as any row.
const PENDING: Array[String] = []
## Wizards in each run (the first seat is dealt the row; the others are play-bots as in the other shards).
const PLAYERS := 2
## The first row's seed; row n of the plan plays SEED_BASE + n.
const SEED_BASE := 301
## Game seconds a row may take to be credited (the run's intro included), and a pending row's whole play.
const CEILING := 40.0
const PENDING_SECONDS := 12.0
## Game seconds played after the credit, so the effect is drawn at least once.
const AFTER_SECONDS := 1.0


## Counts the engine's errors (warnings do not count), so each row is failed for an error it caused.
class CoverErrors extends Logger:
	var count: int = 0
	var last: String = ""
	var _lock := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		count += 1
		last = "%s (%s:%d)" % [rationale if rationale != "" else code, file, line]
		_lock.unlock()


var _errors := CoverErrors.new()
var _rows: Array = [] # [family, key] this process plays
var _pending: Array[String] = []
var _n: int = -1
var _w: World = null
var _p: World.Player = null
var _rt: float = 0.0
var _credit_t: float = -1.0
var _errors_at: int = 0
var _ok: int = 0
var _held: int = 0
var _failed: Array[String] = []
var _wall0: int = 0
var _label: String = ""


## The families, one per script of FAMILY_DIR, in file order.
static func families() -> Array:
	var out: Array = []
	var files: PackedStringArray = DirAccess.get_files_at(FAMILY_DIR)
	var names: Array[String] = []
	for f: String in files:
		var n := f.trim_suffix(".remap")
		if n.ends_with(".gd") and n != FAMILY_BASE and not names.has(n):
			names.append(n)
	names.sort()
	for n: String in names:
		out.append((load("%s/%s" % [FAMILY_DIR, n]) as GDScript).new())
	return out


## Every row of every family: [family, key, state] with state "cover", "pending" or "unbuilt".
static func plan(pending: Array[String] = PENDING) -> Array:
	var out: Array = []
	for fam: RefCounted in families():
		for key: String in fam.call("keys"):
			var state := "cover"
			if bool(fam.call("unbuilt", key)):
				state = "unbuilt"
			elif pending.has(key):
				state = "pending"
			out.append([fam, key, state])
	return out


func _ready() -> void:
	_wall0 = Time.get_ticks_msec()
	OS.add_logger(_errors)
	_pending = PENDING.duplicate()
	var unpend := Flags.get_arg("unpend")
	if not unpend.is_empty():
		_pending.erase(unpend)
	var deal := Flags.get_arg("deal")
	var shard := int(Flags.get_arg("shard", "0"))
	var nshards := maxi(1, int(Flags.get_arg("nshards", "1")))
	_label = "deal=%s" % deal if not deal.is_empty() else "shard=%d/%d" % [shard, nshards]
	var all := plan(_pending)
	var played := 0
	for i: int in range(all.size()):
		var row: Array = all[i]
		if not deal.is_empty():
			if row[1] == deal:
				_rows.append([row[0], row[1], SEED_BASE + i])
			continue
		if row[2] == "unbuilt":
			continue
		if played % nshards == shard:
			_rows.append([row[0], row[1], SEED_BASE + i])
		played += 1
	if not deal.is_empty() and _rows.is_empty():
		_failed.append(deal)
		print("COVER %s FAIL no family has this row" % deal)
	add_child(load("res://game/main.tscn").instantiate())
	await get_tree().process_frame
	G.local_devices = []
	Net.start_offline()
	for d: int in range(PLAYERS):
		Net.add_local_device(G.DEV_KBM if d == 0 else d - 1)
	PlayerInput.bot = true
	_next_row()


## Ends the last row's run by starting the next one (the arena swaps in a fresh World), or finishes.
func _next_row() -> void:
	_n += 1
	_w = null
	if _n >= _rows.size():
		_finish()
		return
	var row: Array = _rows[_n]
	Flags.args["seed"] = str(row[2])
	Flags.args["persona"] = Flags.get_arg("persona", "casual")
	Net.begin_game()
	var arena: Node = G.main.current
	_w = arena.get("world") if arena != null else null
	if _w == null:
		_end_row("FAIL the arena made no World")
		return
	var first: int = (_w.players.keys() as Array).min()
	_p = _w.players[first]
	_rt = 0.0
	_credit_t = -1.0
	_errors_at = _errors.count
	row[0].call("deal", _w, _p, row[1])


func _physics_process(delta: float) -> void:
	if _w == null:
		return
	_rt += delta
	var key: String = _rows[_n][1]
	if _errors.count > _errors_at:
		_end_row("FAIL engine error: %s" % _errors.last)
		return
	var c: int = int(_rows[_n][0].call("credit", _w, _p, key))
	if _pending.has(key):
		if c > 0:
			_end_row("FAIL credited but listed as pending")
		elif _rt >= PENDING_SECONDS:
			_end_row("pending")
		return
	if c > 0 and _credit_t < 0.0:
		_credit_t = _rt
	if _credit_t >= 0.0:
		if _rt - _credit_t >= AFTER_SECONDS:
			_end_row("ok uses=%d t=%.1f" % [c, _credit_t])
	elif _w.phase == World.PH_GAMEOVER:
		_end_row("FAIL the run ended at game time %.1fs with no credit" % _rt)
	elif _rt >= CEILING:
		_end_row("FAIL no credit by game time %.0fs" % CEILING)


func _end_row(what: String) -> void:
	var key: String = _rows[_n][1]
	print("COVER %s %s" % [key, what])
	if what.begins_with("FAIL"):
		_failed.append(key)
	elif what == "pending":
		_held += 1
	else:
		_ok += 1
	_next_row()


func _finish() -> void:
	set_physics_process(false)
	PlayerInput.bot = false
	var secs := (Time.get_ticks_msec() - _wall0) / 1000.0
	var total := maxi(_rows.size(), _failed.size())
	print("BOT cover %s rows=%d failed=%d %s" % [_label, total, _failed.size(),
		"FAIL %s" % " ".join(_failed) if not _failed.is_empty() else "PASS"])
	print("COVER rows=%d ok=%d pending=%d failed=%d secs=%.1f" % [total, _ok, _held, _failed.size(), secs])
	get_tree().quit(1 if not _failed.is_empty() else 0)

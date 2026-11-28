extends Node
## Build smoke test: `--smoke[=seconds] --smoke-out=<file>`. Works in every build. Boots through the real title,
## seats one wizard with a bot at the wheel (as a scripted run does), plays SECONDS of game time, writes one line
## `SMOKE ok ...` (or `SMOKE FAIL <why>`) to the file and exits 0 (or 1). See docs/release_build.md.

const DEFAULT_SECONDS := 20.0
const TITLE_WAIT := 1.5  ## real seconds on the title before the run starts
const START_WAIT_MSEC := 15000  ## the arena must exist this long after the title
const SLACK_MSEC := 40000  ## real time allowed beyond the game seconds
const PACK_DIRS: PackedStringArray = ["tests", "realm", "docs"]

var _seconds := DEFAULT_SECONDS
var _out := ""
var _t := 0.0
var _started := false
var _start_msec := 0
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var given: String = Flags.get_arg("smoke", "1")
	_seconds = float(given) if given != "1" and float(given) > 0.0 else DEFAULT_SECONDS
	_out = Flags.get_arg("smoke-out", "")


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var cur: Node = G.main.current if G.main else null
	if not _started:
		if _t > TITLE_WAIT and cur != null and cur.get_script() != null and cur.get_script().resource_path.ends_with("title.gd"):
			_started = true
			_start_msec = Time.get_ticks_msec()
			G.local_devices = [G.DEV_KBM]
			Net.start_offline()
			PlayerInput.bot = true
			Net.begin_game()
		elif _t > TITLE_WAIT + START_WAIT_MSEC / 1000.0:
			_finish("FAIL title did not appear")
		return
	var world: World = cur.get("world") if cur != null else null
	var waited: int = Time.get_ticks_msec() - _start_msec
	if world == null:
		if waited > START_WAIT_MSEC:
			_finish("FAIL no run started")
		return
	if world.time >= _seconds:
		var kills: int = world.total_kills()
		if kills <= 0:
			_finish("FAIL kills=0 seconds=%d" % int(world.time))
			return
		_finish("ok version=%s seconds=%d kills=%d pack_tests=%s pack_realm=%s pack_docs=%s renderer=%s" % [
			G.VERSION, int(world.time), kills, _has_dir("tests"), _has_dir("realm"), _has_dir("docs"),
			RenderingServer.get_current_rendering_method()])
	elif waited > int(_seconds * 1000.0) + SLACK_MSEC:
		_finish("FAIL run stalled at %.1f s" % world.time)


static func _has_dir(name: String) -> bool:
	return DirAccess.dir_exists_absolute("res://" + name)


func _finish(rest: String) -> void:
	_done = true
	var line := "SMOKE " + rest
	print(line)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f == null:
			printerr("smoke: cannot write %s" % _out)
		else:
			f.store_line(line)
			f.close()
	get_tree().quit(0 if rest.begins_with("ok") else 1)

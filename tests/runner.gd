extends SceneTree
## Runs every tests/unit/test_*.gd (or one file via -- --only=test_name). Prints failures only, then one summary line.
## Exit code 0 = all pass, 1 = any failure or a script that would not load.
##
## A test fails when an assert fails, and also when it proves nothing: the engine logged an error while it ran (a
## script error abandons the test function, so the asserts after it never run), or it ran no assert at all. Both
## used to count as passes. A test that takes longer than SLOW_TEST_MS fails too: one such test was 81% of this
## suite's time, so shrink it (a small Tuning.enemy_cap, a later start) or make it a sim.
##
## With -- --claims=<dir> (tools/run_tests.sh), several processes share one queue: each takes the next test method
## no one has claimed yet (mkdir is atomic), so every test runs exactly once and a slow one holds up nobody.

const SLOW_TEST_MS: int = 10000  ## env SLOW_TEST_MS overrides it (a slow station; CI keeps the default)


## Counts engine errors, so a test that crashed cannot pass. Warnings do not count.
class RunnerErrors extends Logger:
	var count: int = 0
	var last: String = ""

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		count += 1
		last = "%s (%s:%d)" % [rationale if rationale != "" else code, file, line]


var _errors := RunnerErrors.new()


## Deferred so autoload singletons (Flags, Controls) exist before test scripts compile.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var slow_env: String = OS.get_environment("SLOW_TEST_MS")
	var slow_ms: int = int(slow_env) if slow_env.is_valid_int() else SLOW_TEST_MS
	var only: String = ""
	var claims: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--claims="):
			claims = a.trim_prefix("--claims=")
	OS.add_logger(_errors)
	var passed: int = 0
	var failed: int = 0
	var dir: PackedStringArray = DirAccess.get_files_at("res://tests/unit")
	dir.sort()
	var mindex: int = -1  ## test methods seen so far, across files: the queue is by method, so one big file is not one slow process
	for f: String in dir:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		if only != "" and f.get_basename() != only:
			continue
		var script: GDScript = load("res://tests/unit/" + f)
		if script == null or not script.can_instantiate():
			# With a shared queue every process meets the broken file: only the first one reports it.
			if claims == "" or DirAccess.make_dir_absolute(claims.path_join("load_" + f.get_basename())) == OK:
				printerr("LOAD FAIL %s" % f)
				failed += 1
			continue
		for m: Dictionary in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			mindex += 1
			if claims != "" and DirAccess.make_dir_absolute(claims.path_join(str(mindex))) != OK:
				continue
			var t: TestCase = script.new()
			var errors_before: int = _errors.count
			var t0: int = Time.get_ticks_msec()
			t.call(name)
			var ms: int = Time.get_ticks_msec() - t0
			if _errors.count > errors_before:
				t.failures.append("engine error during the test: %s" % _errors.last)
			elif t.checks == 0:
				t.failures.append("ran no assert, so it proves nothing")
			if ms > slow_ms:
				t.failures.append("took %.1f s (limit %d s): shrink it or make it a sim" % [ms / 1000.0, slow_ms / 1000])
			if t.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for msg: String in t.failures:
					printerr("FAIL %s::%s  %s" % [f.get_basename(), name, msg])
	print("TESTS passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 or (passed == 0 and claims == "") else 0)  ## a queue process may find nothing left to take

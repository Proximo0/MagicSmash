extends SceneTree
## Follows a running realm server through the native module for --ticks ticks as a lockstep player and fails
## unless every hash check passed. It starts nothing itself.
## godot --headless --path realm/client -s res://tests/follow_test.gd -- [--server=127.0.0.1:7777]
##   [--ticks=400] [--timeout=60]
## Prints one line, FOLLOW_TEST ok|FAILED ..., and exits 1 on failure. Also checks, once joined, that the
## frame the worker thread finished agrees with the counts (a whole-field view draws every monster), that
## the HUD, world, effect and event reads are well formed, and that the predicted hero stays close to the
## confirmed one.

const TICK_S: float = 0.05
## The predicted hero may lead the confirmed one by the unconfirmed inputs, 3 px a tick each.
const LEAD_PX_PER_INPUT: float = 3.0

var _link: RealmLink = RealmLink.new()
var _host: String = "127.0.0.1"
var _port: int = 7777
var _ticks: int = 400
var _timeout_s: float = 60.0
var _start_us: int = 0
var _input_acc: float = 0.0
var _joined_at: int = -1
var _problems: Array[String] = []
var _checked_reads: bool = false
var _check_whole: bool = false
var _checked_whole: bool = false
var _done: bool = false
var _view_ticks: int = 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v: String = kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"server":
				var hp := v.split(":")
				_host = hp[0]
				if hp.size() > 1:
					_port = int(hp[1])
			"ticks":
				_ticks = maxi(int(v), 20)
			"timeout":
				_timeout_s = maxf(float(v), 5.0)
	# A headless loop would otherwise spin a core.
	Engine.max_fps = 120
	_start_us = Time.get_ticks_usec()
	if not _link.connect_to_host(_host, _port, 2, 1):
		_finish("cannot open %s:%d" % [_host, _port])


func _process(delta: float) -> bool:
	if _done:
		return true
	var applied_now: int = _link.poll()
	if _check_whole and not _checked_whole and applied_now > 0 and _view_ticks >= 2:
		_verify_whole()
	if _check_whole and applied_now > 0:
		_view_ticks += 1
	_input_acc += delta
	if _input_acc >= TICK_S:
		_input_acc = fmod(_input_acc, TICK_S)
		var secs: float = (Time.get_ticks_usec() - _start_us) / 1000000.0
		_link.send_input(1 + (int(secs / 2.0) * 3) % 8, 1, 0)
	var c: Dictionary = _link.counters()
	var applied: int = int(c.get("ticks_applied", 0))
	if _link.is_joined():
		if _joined_at < 0:
			_joined_at = applied
		if not _checked_reads and applied - _joined_at >= 40:
			_checked_reads = true
			_check_reads()
		_check_prediction()
	if _joined_at >= 0 and applied - _joined_at >= _ticks:
		_finish("")
	elif (Time.get_ticks_usec() - _start_us) / 1000000.0 > _timeout_s:
		_finish("timed out after %d ticks" % maxi(applied - _joined_at, 0))
	return _done


func _check_reads() -> void:
	# The draw buffers for the whole field must hold every monster and every other player, and the
	# frame's numbers must agree with the counts.
	_link.set_view(Rect2i(0, 0, RealmLink.field_size(), RealmLink.field_size()))
	_check_whole = true


## Called on the frames after the whole-field view was set: the buffers then cover everything.
func _verify_whole() -> void:
	var drawn: int = _link.monster_buffer().size() / 16
	if drawn != _link.monster_count():
		_problems.append("monster_buffer drew %d of %d" % [drawn, _link.monster_count()])
	var others: int = _link.player_buffer().size() / 16
	if others != _link.player_count() - 1:
		_problems.append("player_buffer drew %d, %d players besides me" % [others, _link.player_count() - 1])
	var h: Dictionary = _link.hero_view()
	if h.is_empty() or int(h["id"]) != _link.hero_id():
		_problems.append("hero_view is empty or not this hero")
	elif int(h["max_health"]) <= 0 or (h["skills"] as PackedInt32Array).size() != 12 or (h["belt"] as PackedInt32Array).size() != 9:
		_problems.append("hero_view is malformed")
	var w: Dictionary = _link.world()
	if (w["sites"] as PackedFloat32Array).size() != 30:
		_problems.append("world sites has %d floats" % (w["sites"] as PackedFloat32Array).size())
	if (_link.fx_rows().size() % 8) != 0 or (_link.event_rows().size() % 8) != 0:
		_problems.append("fx or event rows are not whole rows")
	_checked_whole = true


## Reads the prediction and what it was made from in one call: the frame (`hero_view`) and the counters are
## published at other moments, and after a stall a burst of late ticks or queued inputs lies between them.
func _check_prediction() -> void:
	var p: Dictionary = _link.prediction()
	if p.is_empty() or not bool(p["alive"]):
		return
	var lead: float = (p["predicted"] as Vector2).distance_to(p["confirmed"] as Vector2)
	var allowed: float = (int(p["unconfirmed"]) + 3) * LEAD_PX_PER_INPUT * 1.5
	if lead > allowed and _problems.size() < 8:
		_problems.append("predicted hero %.1f px from the confirmed one at tick %d (allowed %.1f)" % [lead, int(p["tick"]), allowed])


func _finish(error: String) -> void:
	_done = true
	if not error.is_empty():
		_problems.append(error)
	var c: Dictionary = _link.counters()
	var passed: int = int(c.get("hash_checks_passed", 0))
	var failed: int = int(c.get("hash_checks_failed", 0))
	# One check every 20 ticks: a full run of N ticks sees at least N / 20 - 1 of them.
	if passed < _ticks / 20 - 1:
		_problems.append("only %d hash checks" % passed)
	if failed > 0:
		_problems.append("%d hash checks failed" % failed)
	if int(c.get("bad_datagrams", 0)) > 0:
		_problems.append("%d datagrams did not parse" % int(c.get("bad_datagrams", 0)))
	var ok: bool = _problems.is_empty()
	print("FOLLOW_TEST %s server=%s:%d ticks=%d hash_checks passed=%d failed=%d join_kb=%.0f in_kb_s=%.1f out_kb_s=%.2f sim_ms=%.2f stall_ms_max=%.0f mispredicts=%d/%d%s" % [
		"ok" if ok else "FAILED", _host, _port, maxi(int(c.get("ticks_applied", 0)) - maxi(_joined_at, 0), 0), passed, failed,
		float(c.get("join_bytes", 0)) / 1000.0, float(c.get("bytes_in_per_sec", 0.0)) / 1000.0,
		float(c.get("bytes_out_per_sec", 0.0)) / 1000.0, float(c.get("sim_ms_per_tick", 0.0)),
		float(c.get("stall_ms_max", 0.0)), int(c.get("mispredicts", 0)), int(c.get("predictions_checked", 0)),
		"" if ok else " problems=\"%s\"" % "; ".join(_problems)])
	_link.close()
	quit(0 if ok else 1)

class_name PerfMeter
extends RefCounted
## Per-system script time for the perf harness (`--autotest=N --perf`). Off by default; when on, each timed
## system adds the microseconds it took since `t0`. Cheap enough to leave the calls in.

static var on := false
static var acc := {} # name -> total microseconds
static var frames := 0


static func since(name: String, t0: int) -> void:
	if on:
		acc[name] = int(acc.get(name, 0)) + Time.get_ticks_usec() - t0


static func reset() -> void:
	acc.clear()
	frames = 0

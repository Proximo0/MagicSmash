class_name Sfx
extends Node
## The sound effects (audio/sfx/*.wav, made by tools/sfx/sfx.py): one autoload ("SfxBus") with a pool of voices.
## `Sfx.play("hit")` from anywhere; a name is a group, and a group with numbered files (hit_1, hit_2, hit_3)
## picks one at random with a little pitch jitter. Two limits keep 20,000 dying monsters from a wall of noise:
## at most VOICES sounds at once (a request with no free voice is dropped, unless it is an important one, which
## takes the oldest voice), and per group at most `limit` plays in any RATE_WINDOW_S. The master volume is the
## settings screen's (ShellSettings.volume, on the master bus); there is no second one here.

const VOICES: int = 24
const RATE_WINDOW_S: float = 0.1
const DIR: String = "res://audio/sfx/"
const PITCH_JITTER: float = 0.06
## Group: [files, most plays per RATE_WINDOW_S, volume dB, important (may steal a voice)].
const GROUPS: Dictionary = {
	"hit": [["hit_1", "hit_2", "hit_3"], 2, -4.0, false],
	"spell": [["spell_1", "spell_2"], 2, -6.0, false],
	"crit": [["crit"], 1, -3.0, false],
	"hurt": [["hurt_1", "hurt_2"], 1, -3.0, false],
	"hero_death": [["hero_death"], 1, -2.0, true],
	"mon_small": [["mon_small_1", "mon_small_2", "mon_small_3"], 3, -9.0, false],
	"mon_big": [["mon_big_1", "mon_big_2"], 1, -4.0, false],
	"gold": [["gold"], 1, -6.0, false],
	"item": [["item"], 1, -5.0, false],
	"rare": [["rare"], 1, -4.0, true],
	"level_up": [["level_up"], 1, -2.0, true],
	"horn": [["horn"], 1, -2.0, true],
	"boss_roar": [["boss_roar"], 1, -2.0, true],
	"boss_death": [["boss_death"], 1, -2.0, true],
	"portal": [["portal"], 1, -4.0, true],
	"ui_click": [["ui_click"], 2, -8.0, false],
	"ui_open": [["ui_open"], 1, -6.0, false],
	"ui_error": [["ui_error"], 1, -6.0, false],
	"bell": [["bell"], 1, -5.0, true],
	"chest": [["chest"], 1, -5.0, false],
}

static var inst: Sfx = null
## Plays started and requests refused, by group (the tests read them).
var started: Dictionary = {}
var refused: int = 0
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _began: PackedFloat64Array = PackedFloat64Array()
var _recent: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Set by a scripted run (--mute) or a test: requests are counted and limited but nothing is played.
var silent: bool = false


func _init() -> void:
	_rng.seed = 4242
	if inst == null:
		inst = self


func _ready() -> void:
	for g in GROUPS:
		for f in GROUPS[g][0]:
			var s := load(DIR + String(f) + ".wav") as AudioStream
			if s != null:
				_streams[f] = s
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
		_began.append(-100.0)


## Every file name of every group.
static func files() -> PackedStringArray:
	var out := PackedStringArray()
	for g in GROUPS:
		out.append_array(PackedStringArray(GROUPS[g][0]))
	return out


## Starts a sound of the group `group` (`gain_db` is added). True when it was started.
static func play(group: String, gain_db: float = 0.0) -> bool:
	return inst != null and inst.request(group, gain_db)


## `at` (seconds, tests only) stands in for the clock, so a test of the rate window does not depend on how fast the
## machine runs its loop (a busy station took longer than the window for 1000 requests, 24 Nov).
func request(group: String, gain_db: float = 0.0, at: float = -1.0) -> bool:
	if not GROUPS.has(group):
		return false
	var spec: Array = GROUPS[group]
	var now: float = at if at >= 0.0 else Time.get_ticks_usec() / 1000000.0
	var recent: PackedFloat64Array = _recent.get(group, PackedFloat64Array())
	var kept := PackedFloat64Array()
	for t in recent:
		if now - t < RATE_WINDOW_S:
			kept.append(t)
	if kept.size() >= int(spec[1]):
		_recent[group] = kept
		refused += 1
		return false
	var v: int = _free_voice(now, bool(spec[3]))
	if v < 0:
		_recent[group] = kept
		refused += 1
		return false
	kept.append(now)
	_recent[group] = kept
	var files: Array = spec[0]
	var file: String = String(files[_rng.randi() % files.size()])
	started[group] = int(started.get(group, 0)) + 1
	_began[v] = now
	if silent or not _streams.has(file):
		return true
	var p: AudioStreamPlayer = _voices[v]
	p.stream = _streams[file]
	p.volume_db = float(spec[2]) + gain_db
	p.pitch_scale = 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	p.play()
	return true


## How many voices are sounding now.
func busy() -> int:
	var now: float = Time.get_ticks_usec() / 1000000.0
	var n: int = 0
	for i in _voices.size():
		if _is_busy(i, now):
			n += 1
	return n


func _is_busy(i: int, now: float) -> bool:
	if silent:
		return now - _began[i] < 0.3
	return _voices[i].playing


## An idle voice, else (for an important sound) the oldest one, else -1.
func _free_voice(now: float, important: bool) -> int:
	var oldest: int = 0
	for i in _voices.size():
		if not _is_busy(i, now):
			return i
		if _began[i] < _began[oldest]:
			oldest = i
	return oldest if important else -1

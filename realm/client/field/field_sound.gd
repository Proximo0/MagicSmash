class_name FieldSound
extends Node
## Sound hooks of the field with placeholder bleeps made here (no sound files yet). Call `hook("kill")` and
## the like; the real sounds replace `_make` later and the hooks stay. Each hook is rate limited, so ten
## thousand monsters dying do not make a roar of clicks.
## Hooks: hit, kill, skill, level, down, raise, potion, bank, pick, tide, bad.

const MIX_RATE: int = 22050
const VOICES: int = 8
## Each hook: frequency Hz (start, end), length s, volume 0..1, wave ("sine", "square", "noise"), least gap s.
const HOOKS: Dictionary = {
	"hit": [220.0, 160.0, 0.04, 0.10, "noise", 0.08],
	"kill": [420.0, 200.0, 0.06, 0.14, "square", 0.07],
	"skill": [300.0, 700.0, 0.16, 0.22, "sine", 0.1],
	"level": [440.0, 880.0, 0.35, 0.3, "sine", 0.3],
	"down": [300.0, 80.0, 0.45, 0.3, "square", 0.4],
	"raise": [300.0, 600.0, 0.3, 0.25, "sine", 0.3],
	"potion": [500.0, 350.0, 0.14, 0.22, "sine", 0.15],
	"bank": [660.0, 990.0, 0.25, 0.25, "square", 0.3],
	"pick": [520.0, 780.0, 0.1, 0.2, "square", 0.1],
	"tide": [110.0, 90.0, 0.8, 0.3, "square", 1.0],
	"bad": [150.0, 100.0, 0.12, 0.2, "square", 0.2],
}

var muted: bool = false
## Hooks played, by name (the tests read it).
var played: Dictionary = {}
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _last: Dictionary = {}


func _ready() -> void:
	for name in HOOKS:
		_streams[name] = _make(HOOKS[name])
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_voices.append(p)


func hook(name: String) -> void:
	if not HOOKS.has(name):
		return
	var now: float = Time.get_ticks_usec() / 1000000.0
	if now - float(_last.get(name, -10.0)) < float(HOOKS[name][5]):
		return
	_last[name] = now
	played[name] = int(played.get(name, 0)) + 1
	if muted or _voices.is_empty():
		return
	var v: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	v.stream = _streams[name]
	v.play()


## Plays the hooks the event rows of one frame call for. `me` is this hero's id.
func from_events(ev: PackedInt32Array, me: int) -> void:
	var kills: int = 0
	for i in ev.size() / FieldFx.EV_STRIDE:
		var o: int = i * FieldFx.EV_STRIDE
		var mine: bool = ev[o + 1] == me
		match ev[o]:
			FieldFx.EV_KILL:
				kills += 1
			FieldFx.EV_LEVEL:
				if mine:
					hook("level")
			FieldFx.EV_DOWN:
				hook("down")
			FieldFx.EV_RAISE:
				hook("raise")
			FieldFx.EV_BANK:
				if mine:
					hook("bank")
			FieldFx.EV_POTION:
				if mine:
					hook("potion")
			FieldFx.EV_PICK:
				if mine:
					hook("pick")
			FieldFx.EV_SKILL:
				if mine:
					hook("skill")
	if kills > 0:
		hook("kill")


## A short wave as a 16-bit mono stream: a sweep from one frequency to another, fading out.
func _make(spec: Array) -> AudioStreamWAV:
	var f0: float = spec[0]
	var f1: float = spec[1]
	var secs: float = spec[2]
	var vol: float = spec[3]
	var kind: String = spec[4]
	var n: int = int(secs * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t: float = float(i) / float(n)
		phase += TAU * lerpf(f0, f1, t) / float(MIX_RATE)
		var s: float
		match kind:
			"square":
				s = 1.0 if sin(phase) >= 0.0 else -1.0
			"noise":
				s = rng.randf_range(-1.0, 1.0)
			_:
				s = sin(phase)
		s *= vol * (1.0 - t) * minf(1.0, float(i) / 40.0)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w

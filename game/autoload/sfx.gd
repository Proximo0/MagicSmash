extends Node
## Sound effect pool and looping music player.

const SOUNDS := [
	"shoot_arcane", "shoot_fire", "shoot_frost", "zap", "star", "hit", "enemy_die",
	"explode", "nova", "pickup", "coin", "powerup", "heal", "hurt", "player_die",
	"door", "arrow", "enemy_shot", "slime", "menu_move", "menu_select",
	"wave_start", "wave_clear", "boss_roar", "teleport", "charge", "orbit",
	"card_deal", "card_flip", "card_pick", "planchette", "rune_cast", "rune_good",
	"rune_bad", "gong", "whisper", "candle", "page_turn", "bell_toll", "portal", "ghost",
	"down", "revive", "boss_phase", "fate", "redraw", "banish", "low_health", "level_up", "victory",
	"boss_fall", "shrine_result",
	"enemy_die_2", "enemy_die_3", "enemy_die_4", "hit_2", "hit_3", "hit_4",
]
const MUSIC := ["music_title", "music_battle", "music_library", "music_sanctum", "music_boss", "music_gameover"]
const POOL := 20

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "UI"
const UI_SOUNDS := ["menu_move", "menu_select"]

## Voice priority: a new sound takes a free player, else the lowest-priority one that has played longest, never one
## of a higher priority than its own; with none to take it is dropped (pick_voice).
const PRIO_SMALL := 0
const PRIO_NORMAL := 1
const PRIO_BOSS := 2
const PRIORITY := {
	"boss_roar": PRIO_BOSS, "gong": PRIO_BOSS, "bell_toll": PRIO_BOSS, "boss_phase": PRIO_BOSS,
	"down": PRIO_BOSS, "revive": PRIO_BOSS, "victory": PRIO_BOSS,
	"enemy_die": PRIO_SMALL, "enemy_die_2": PRIO_SMALL, "enemy_die_3": PRIO_SMALL, "enemy_die_4": PRIO_SMALL,
	"hit": PRIO_SMALL, "hit_2": PRIO_SMALL, "hit_3": PRIO_SMALL, "hit_4": PRIO_SMALL,
}
const VARIANT_OF := ["enemy_die", "hit"] ## names that also have _2 to _4 files: play() picks one at random
const VARIANTS := 4
const STEAL_FADE := 0.01 ## a stolen player ramps to silence over this many seconds before the new sound starts
const LIMITER_CEILING_DB := -1.0

## Pitch jitter only.
var _fx_rng := RandomNumberGenerator.new()
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _prio: Array[int] = []
var _started: Array[float] = [] ## when each player's sound began (seconds)
var _fades: Array = [] ## per player: the Tween fading it out, or null
var _last_play := {}
var _music: AudioStreamPlayer
var _music_name := ""
var sfx_volume := 0.8
var music_volume := 0.5

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in SOUNDS:
		var st = load("res://assets/audio/%s.wav" % s)
		if st:
			_streams[s] = st
	# Loop points for the music live in each .wav.import file (written by
	# tools/music/apply_loops.py), so tracks with an intro loop seamlessly.
	for m in MUSIC:
		var st = load("res://assets/audio/%s.wav" % m)
		if st:
			_streams[m] = st
	_make_buses()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_players.append(p)
		_prio.append(PRIO_NORMAL)
		_started.append(0.0)
		_fades.append(null)
	_music = AudioStreamPlayer.new()
	_music.bus = BUS_MUSIC
	add_child(_music)
	set_volumes(music_volume, sfx_volume)


## Music, SFX and UI under Master, and a hard limiter on Master, made here (no bus layout file).
func _make_buses() -> void:
	for b in [BUS_MUSIC, BUS_SFX, BUS_UI]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	for e in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, e) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = LIMITER_CEILING_DB
	AudioServer.add_bus_effect(0, lim)


static func priority_of(name: String) -> int:
	return int(PRIORITY.get(name, PRIO_NORMAL))


## Which player a new sound of priority `new_prio` takes: a free one (the first), else the lowest-priority one that
## has played longest, never one above `new_prio`; -1 when there is none (the sound is dropped).
## `prios[i]` is player i's sound's priority, `playing[i]` whether it plays, `ages[i]` for how long (seconds).
static func pick_voice(prios: Array, playing: Array, ages: Array, new_prio: int) -> int:
	var best := -1
	for i in prios.size():
		if not bool(playing[i]):
			return i
		var pr := int(prios[i])
		if pr > new_prio:
			continue
		if best < 0 or pr < int(prios[best]) or (pr == int(prios[best]) and float(ages[i]) > float(ages[best])):
			best = i
	return best

## Plays a sound. Repeats of the same sound within `min_gap` seconds are
## dropped so a 40-goblin pileup doesn't turn into white noise.
func play(name: String, vol_db: float = 0.0, pitch: float = 1.0, min_gap: float = 0.03) -> void:
	if not _streams.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(name, -1.0)) < min_gap:
		return
	var prio := priority_of(name)
	var prios: Array = _prio
	var playing: Array = []
	var ages: Array = []
	for i in POOL:
		playing.append(_players[i].playing)
		ages.append(now - _started[i])
	var k := pick_voice(prios, playing, ages, prio)
	if k < 0:
		return # every player holds a louder-priority sound: this one is dropped
	_last_play[name] = now
	var file := name
	if name in VARIANT_OF:
		var v := _fx_rng.randi_range(1, VARIANTS)
		if v > 1 and _streams.has("%s_%d" % [name, v]):
			file = "%s_%d" % [name, v]
	var p := _players[k]
	_prio[k] = prio
	_started[k] = now
	var db := vol_db
	var pit := pitch * _fx_rng.randf_range(0.95, 1.05)
	if _fades[k] != null:
		(_fades[k] as Tween).kill()
		_fades[k] = null
	if p.playing:
		# A stolen player ramps down for STEAL_FADE seconds, then the new sound starts: no click.
		var tw := create_tween()
		_fades[k] = tw
		tw.tween_property(p, "volume_db", -60.0, STEAL_FADE)
		tw.tween_callback(_start.bind(k, file, db, pit))
	else:
		_start(k, file, db, pit)


func _start(k: int, file: String, vol_db: float, pit: float) -> void:
	var p := _players[k]
	_fades[k] = null
	p.bus = BUS_UI if file in UI_SOUNDS else BUS_SFX
	p.stream = _streams[file]
	p.volume_db = vol_db
	p.pitch_scale = pit
	p.play()


func has_music(name: String) -> bool:
	return _streams.has(name)


func music(name: String) -> void:
	if name == _music_name and _music.playing:
		return
	_music_name = name
	if not _streams.has(name):
		_music.stop()
		return
	_music.stream = _streams[name]
	_music.play()

## Volumes from 0 to 1, on the Music bus and the SFX and UI buses. Music already playing changes at once.
func set_volumes(music_vol: float, sfx_vol: float) -> void:
	music_volume = music_vol
	sfx_volume = sfx_vol
	_set_bus(BUS_MUSIC, music_vol)
	_set_bus(BUS_SFX, sfx_vol)
	_set_bus(BUS_UI, sfx_vol)


func _set_bus(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, maxf(linear_to_db(linear), -80.0))


func stop_music() -> void:
	_music_name = ""
	_music.stop()

func _exit_tree() -> void:
	# Release active playbacks so quitting mid-sound doesn't report leaks.
	for p in _players:
		p.stop()
		p.stream = null
	_music.stop()
	_music.stream = null
	_streams.clear()

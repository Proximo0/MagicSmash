extends Node
## Sound effect pool and looping music player.

const SOUNDS := [
	"shoot_arcane", "shoot_fire", "shoot_frost", "zap", "star", "hit", "enemy_die",
	"explode", "nova", "pickup", "coin", "powerup", "heal", "hurt", "player_die",
	"door", "arrow", "enemy_shot", "slime", "menu_move", "menu_select",
	"wave_start", "wave_clear", "boss_roar", "teleport", "charge", "orbit",
	"card_deal", "card_flip", "card_pick", "planchette", "rune_cast", "rune_good",
	"rune_bad", "gong", "whisper", "candle", "page_turn", "bell_toll", "portal", "ghost",
]
const MUSIC := ["music_title", "music_battle", "music_boss", "music_gameover"]
const POOL := 20

## Pitch jitter only.
var _fx_rng := RandomNumberGenerator.new()
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
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
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)

## Plays a sound. Repeats of the same sound within `min_gap` seconds are
## dropped so a 40-goblin pileup doesn't turn into white noise.
func play(name: String, vol_db: float = 0.0, pitch: float = 1.0, min_gap: float = 0.03) -> void:
	if not _streams.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(name, -1.0)) < min_gap:
		return
	_last_play[name] = now
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[name]
	p.volume_db = vol_db + linear_to_db(sfx_volume)
	p.pitch_scale = pitch * _fx_rng.randf_range(0.95, 1.05)
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
	_music.volume_db = linear_to_db(music_volume)
	_music.play()

## Volumes from 0 to 1. Music already playing changes at once.
func set_volumes(music_vol: float, sfx_vol: float) -> void:
	music_volume = music_vol
	sfx_volume = sfx_vol
	if _music:
		_music.volume_db = linear_to_db(music_volume)


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

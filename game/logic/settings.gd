class_name Settings
extends RefCounted
## Player options: music and sound volume, the window, screen shake. Pure data plus the rules for stepping each
## row left or right, so the title's and the pause menu's options panel share one model. The Save autoload reads
## and writes it (user://settings.json) and applies it.

const VOL_MAX := 10
## DISPLAY values: a window at 2x, 3x or 4x the 480x270 screen, or fullscreen.
const DISPLAY_NAMES := ["WINDOW X2", "WINDOW X3", "WINDOW X4", "FULLSCREEN"]
const FULLSCREEN := 3

const R_MUSIC := 0
const R_SOUND := 1
const R_DISPLAY := 2
const R_SHAKE := 3
const ROWS := ["MUSIC", "SOUND", "DISPLAY", "SCREEN SHAKE"]

var music: int = 5
var sound: int = 8
var display: int = 1
var shake: bool = true
## Whether the prologue has been shown once (it then plays only from THE TALE on the title).
var seen_prologue: bool = false
## Whether the controls hint has been shown at the start of a first run.
var seen_tutorial: bool = false


static func row_count() -> int:
	return ROWS.size()


static func label(row: int) -> String:
	return ROWS[clampi(row, 0, ROWS.size() - 1)]


func value_text(row: int) -> String:
	match row:
		R_MUSIC:
			return "%d" % music
		R_SOUND:
			return "%d" % sound
		R_DISPLAY:
			return DISPLAY_NAMES[display]
		R_SHAKE:
			return "ON" if shake else "OFF"
	return ""


## The fill of a volume row (0 to 1), or -1 for a row that is not a volume.
func bar(row: int) -> float:
	if row == R_MUSIC:
		return float(music) / VOL_MAX
	if row == R_SOUND:
		return float(sound) / VOL_MAX
	return -1.0


## Steps `row` by `dir` (-1 or +1). Volumes stop at their ends; the display and shake wrap. Returns whether
## anything changed.
func adjust(row: int, dir: int) -> bool:
	match row:
		R_MUSIC:
			var m := clampi(music + dir, 0, VOL_MAX)
			var changed := m != music
			music = m
			return changed
		R_SOUND:
			var s := clampi(sound + dir, 0, VOL_MAX)
			var changed := s != sound
			sound = s
			return changed
		R_DISPLAY:
			display = wrapi(display + dir, 0, DISPLAY_NAMES.size())
			return true
		R_SHAKE:
			shake = not shake
			return true
	return false


func music_linear() -> float:
	return float(music) / VOL_MAX


func sound_linear() -> float:
	return float(sound) / VOL_MAX


func is_fullscreen() -> bool:
	return display == FULLSCREEN


## Window size multiple of the 480x270 screen (2 to 4); fullscreen keeps the last window size, 3.
func window_scale() -> int:
	return 3 if display == FULLSCREEN else display + 2


func to_dict() -> Dictionary:
	return {"music": music, "sound": sound, "display": display, "shake": shake, "seen_prologue": seen_prologue,
		"seen_tutorial": seen_tutorial}


## Settings from a saved dictionary. Missing or broken values keep their defaults; numbers are clamped.
static func from_dict(d: Dictionary) -> Settings:
	var s := Settings.new()
	s.music = clampi(int(d.get("music", s.music)), 0, VOL_MAX)
	s.sound = clampi(int(d.get("sound", s.sound)), 0, VOL_MAX)
	s.display = clampi(int(d.get("display", s.display)), 0, DISPLAY_NAMES.size() - 1)
	s.shake = bool(d.get("shake", s.shake))
	s.seen_prologue = bool(d.get("seen_prologue", false))
	s.seen_tutorial = bool(d.get("seen_tutorial", false))
	return s

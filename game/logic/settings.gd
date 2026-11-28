class_name Settings
extends RefCounted
## Player options: music and sound volume, the window, scaling, vsync, frame cap, screen shake and flash, crash reports. Pure data plus the rules for stepping each
## row left or right, so the title's and the pause menu's options panel share one model. The Save autoload reads
## and writes it (user://settings.json) and applies it.

const VOL_MAX := 10
## DISPLAY values: a window at 2x, 3x or 4x the 480x270 screen, or fullscreen.
const DISPLAY_NAMES := ["WINDOW X2", "WINDOW X3", "WINDOW X4", "FULLSCREEN"]
const FULLSCREEN := 3

const R_MUSIC := 0
const R_SOUND := 1
const R_DISPLAY := 2
const R_SCALING := 3
const R_VSYNC := 4
const R_CAP := 5
const R_SHAKE := 6
const R_FLASH := 7
const R_CRASH := 8
const R_RESET := 9
const ROWS := ["MUSIC", "SOUND", "DISPLAY", "SCALING", "VSYNC", "FRAME CAP", "SCREEN SHAKE", "SCREEN FLASH",
	"CRASH REPORTS", "RESET PROGRESS"]
## The panel's room: a label holds this many letters, a value this many (the value column is 86 px, 6 px a letter).
const LABEL_MAX := 14
const VALUE_MAX := 13

## SCALING values: whole-number steps (sharp pixels, black bars) or fractional (fills the screen).
const SCALE_NAMES := ["PIXEL PERFECT", "FILL"]
const SCALE_PIXEL := 0
const SCALE_FILL := 1
## A first run picks FILL when whole-number steps would cover less than this share (percent) of the screen's width or height.
const FILL_BELOW_PERCENT := 85
## FRAME CAP values in frames per second; 0 is no cap.
const FRAME_CAPS := [0, 60, 120, 144, 240]
## SCREEN FLASH values: every flash as designed, flashes capped at FLASH_SOFT_ALPHA, or none.
const FLASH_NAMES := ["ON", "SOFT", "OFF"]
const FLASH_ON := 0
const FLASH_SOFT := 1
const FLASH_OFF := 2
const FLASH_SOFT_ALPHA := 0.2
## Seconds RESET PROGRESS must be held before it acts.
const RESET_HOLD := 2.0

var music: int = 5
var sound: int = 8
var display: int = 1
## The window DISPLAY value the F11 / Alt+Enter key returns to from fullscreen.
var last_window: int = 1
var scaling: int = SCALE_PIXEL
var vsync: bool = true
## An index into FRAME_CAPS.
var frame_cap: int = 0
var flash: int = FLASH_ON
var shake: bool = true
## Whether crashes and script errors are reported to the developer (the Crash autoload).
var crash_reports: bool = true
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
		R_SCALING:
			return SCALE_NAMES[scaling]
		R_VSYNC:
			return "ON" if vsync else "OFF"
		R_CAP:
			return "OFF" if max_fps() == 0 else "%d" % max_fps()
		R_FLASH:
			return FLASH_NAMES[flash]
		R_RESET:
			return "HOLD 2 SEC"
		R_SHAKE:
			return "ON" if shake else "OFF"
		R_CRASH:
			return "ON" if crash_reports else "OFF"
	return ""


## The fill of a volume row (0 to 1), or -1 for a row that is not a volume.
func bar(row: int) -> float:
	if row == R_MUSIC:
		return float(music) / VOL_MAX
	if row == R_SOUND:
		return float(sound) / VOL_MAX
	return -1.0


## Steps `row` by `dir` (-1 or +1). Volumes stop at their ends; the display wraps and the switches flip. Returns whether
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
			if display != FULLSCREEN:
				last_window = display
			return true
		R_SCALING:
			scaling = wrapi(scaling + dir, 0, SCALE_NAMES.size())
			return true
		R_VSYNC:
			vsync = not vsync
			return true
		R_CAP:
			frame_cap = wrapi(frame_cap + dir, 0, FRAME_CAPS.size())
			return true
		R_FLASH:
			flash = wrapi(flash + dir, 0, FLASH_NAMES.size())
			return true
		R_SHAKE:
			shake = not shake
			return true
		R_CRASH:
			crash_reports = not crash_reports
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


## The window scale that fits the usable screen `usable` (never below 1): the chosen scale, or smaller.
func fit_scale(usable: Vector2i) -> int:
	return maxi(1, mini(window_scale(), mini(usable.x / 480, usable.y / 270)))


## Fullscreen, or back to the last window size (F11, Alt+Enter).
func toggle_fullscreen() -> void:
	if is_fullscreen():
		display = last_window
	else:
		last_window = display
		display = FULLSCREEN


func max_fps() -> int:
	return FRAME_CAPS[frame_cap]


## The root window's content_scale_stretch for the SCALING row.
func stretch_mode() -> int:
	return Window.CONTENT_SCALE_STRETCH_FRACTIONAL if scaling == SCALE_FILL else Window.CONTENT_SCALE_STRETCH_INTEGER


## A flash's alpha `a` as the SCREEN FLASH row allows it.
func flash_alpha(a: float) -> float:
	match flash:
		FLASH_SOFT:
			return minf(a, FLASH_SOFT_ALPHA)
		FLASH_OFF:
			return 0.0
	return a


## Whether the Lich's hit flash may strobe (only with SCREEN FLASH ON; otherwise it is steady).
func strobes() -> bool:
	return flash == FLASH_ON


## SCALING for a first run on a screen of `usable` pixels: FILL when whole-number scaling covers under
## FILL_BELOW_PERCENT of its width or height, else PIXEL PERFECT.
static func scaling_for(usable: Vector2i) -> int:
	var whole := mini(usable.x / 480, usable.y / 270)
	if whole < 1 or whole * 480 * 100 < FILL_BELOW_PERCENT * usable.x or whole * 270 * 100 < FILL_BELOW_PERCENT * usable.y:
		return SCALE_FILL
	return SCALE_PIXEL


## The options for a first run (no settings file): fullscreen, with SCALING chosen for `usable`. The window the
## fullscreen key returns to is the largest up to x3 that fits.
static func first_run(usable: Vector2i) -> Settings:
	var s := Settings.new()
	s.display = FULLSCREEN
	s.scaling = scaling_for(usable)
	s.last_window = clampi(mini(usable.x / 480, usable.y / 270) - 2, 0, 1)
	return s


## Saved keys read with int() (a JSON number, bool or string converts) and with bool() (only a bool or number).
const INT_KEYS := ["music", "sound", "display", "last_window", "scaling", "frame_cap", "flash"]
const BOOL_KEYS := ["vsync", "shake", "crash_reports", "seen_prologue", "seen_tutorial"]


## Whether from_dict converts every value of `d` without a script error.
static func settings_types_ok(d: Dictionary) -> bool:
	for k: String in INT_KEYS:
		if d.has(k) and not (d[k] is int or d[k] is float or d[k] is bool or d[k] is String):
			return false
	for k: String in BOOL_KEYS:
		if d.has(k) and not (d[k] is bool or d[k] is int or d[k] is float):
			return false
	return true


func to_dict() -> Dictionary:
	return {"music": music, "sound": sound, "display": display, "last_window": last_window, "scaling": scaling,
		"vsync": vsync, "frame_cap": frame_cap, "flash": flash, "shake": shake, "crash_reports": crash_reports,
		"seen_prologue": seen_prologue, "seen_tutorial": seen_tutorial}


## Settings from a saved dictionary. Missing values keep their defaults; numbers are clamped. Null when a value has
## a type its conversion cannot take (settings_types_ok): Save treats that file like unparsable text.
static func from_dict(d: Dictionary) -> Settings:
	if not settings_types_ok(d):
		return null
	var s := Settings.new()
	s.music = clampi(int(d.get("music", s.music)), 0, VOL_MAX)
	s.sound = clampi(int(d.get("sound", s.sound)), 0, VOL_MAX)
	s.display = clampi(int(d.get("display", s.display)), 0, DISPLAY_NAMES.size() - 1)
	s.last_window = clampi(int(d.get("last_window", s.last_window)), 0, FULLSCREEN - 1)
	s.scaling = clampi(int(d.get("scaling", s.scaling)), 0, SCALE_NAMES.size() - 1)
	s.vsync = bool(d.get("vsync", s.vsync))
	s.frame_cap = clampi(int(d.get("frame_cap", s.frame_cap)), 0, FRAME_CAPS.size() - 1)
	s.flash = clampi(int(d.get("flash", s.flash)), 0, FLASH_NAMES.size() - 1)
	s.shake = bool(d.get("shake", s.shake))
	s.crash_reports = bool(d.get("crash_reports", s.crash_reports))
	s.seen_prologue = bool(d.get("seen_prologue", false))
	s.seen_tutorial = bool(d.get("seen_tutorial", false))
	return s

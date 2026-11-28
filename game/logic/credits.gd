class_name Credits
extends RefCounted
## The credits roll as data: what the CREDITS screen (game/ui/credits_view.gd) shows, line by line. Pure. The two
## facts only the owner knows (MAKER, PICTURES_BY) stay empty until he gives them; an empty one leaves its whole
## section out, so nothing on screen looks unfinished. The engine's third-party list is passed in by the caller
## (Engine.get_copyright_info()), so the licence names are never typed here.

## Line kinds: a heading (drawn big, gold), a plain line, a blank gap.
const HEAD := 0
const LINE := 1
const GAP := 2

## Who made the game, and who made the pictures. Empty = not yet known: the section is left out.
const MAKER := ""
const PICTURES_BY := ""

## The widest a line may be, in pixels at its own scale: the view's frame is 472 wide, and the engine's longest
## "NAME, LICENCE" line is 437, so nothing of today's list is cut (test_credits holds that).
const MAX_PX := 448
const HEAD_SCALE := 2
const LINE_SCALE := 1
const CUT_MARK := ".."
const NOTICES_FILE := "THIRD_PARTY_NOTICES.TXT"

const TITLE := "FOUR OF WANDS"
## The engine's own row in its component list. BUILT WITH names the engine, so the licence list leaves it out.
const ENGINE_NAME := "GODOT ENGINE"
const SENTRY_LINES: Array[String] = ["SENTRY FOR GODOT, MIT", "SENTRY NATIVE, MIT", "CRASHPAD, APACHE 2.0"]


## All lines of the roll, each [kind, text]. `components` is Engine.get_copyright_info()'s array.
static func roll(maker: String, pictures_by: String, has_sentry: bool, version: String, components: Array,
		max_px: int = MAX_PX) -> Array:
	var rows: Array = []
	_add(rows, HEAD, TITLE, max_px)
	_add(rows, LINE, "VERSION " + version, max_px)
	if not clean(maker).is_empty():
		_section(rows, "A GAME BY", [maker], max_px)
	if not clean(pictures_by).is_empty():
		_section(rows, "PICTURES", [pictures_by], max_px)
	_section(rows, "MUSIC AND SOUND", ["WRITTEN IN CODE FOR THIS GAME"], max_px)
	_section(rows, "BUILT WITH", ["GODOT ENGINE, MIT LICENCE", "GODOTENGINE.ORG"], max_px)
	if has_sentry:
		_section(rows, "CRASH REPORTS", SENTRY_LINES, max_px)
	_section(rows, "LICENCES", component_lines(components, max_px), max_px)
	rows.append([GAP, ""])
	for l: String in ["THE FULL LICENCE TEXTS ARE IN", NOTICES_FILE + " NEXT TO THE GAME"]:
		_add(rows, LINE, l, max_px)
	rows.append([GAP, ""])
	_add(rows, HEAD, "THANK YOU FOR PLAYING", max_px)
	return rows


## One "NAME, LICENCE" line per component, the engine itself left out (ENGINE_NAME). A licence that several parts
## share is said once; different ones are joined with " + ".
static func component_lines(components: Array, max_px: int = MAX_PX) -> Array[String]:
	var out: Array[String] = []
	for comp: Dictionary in components:
		var name := clean(str(comp.get("name", "")))
		if name == ENGINE_NAME:
			continue
		var lics: Array[String] = []
		for part: Dictionary in comp.get("parts", []):
			var l := clean(str(part.get("license", "")))
			if not l.is_empty() and not lics.has(l):
				lics.append(l)
		if name.is_empty():
			continue
		var tail := ", " + (" + ".join(lics) if not lics.is_empty() else "SEE NOTICES")
		out.append(fit(name, max_px, LINE_SCALE, tail))
	return out


## Upper case, only glyphs the pixel font has, spaces collapsed. Anything else is dropped.
static func clean(text: String) -> String:
	var up := text.to_upper()
	var out := ""
	for ch: String in up:
		out += ch if PixelFont.GLYPHS.has(ch) else " "
	return " ".join(out.split(" ", false))


## `text` + `tail` in at most `px` pixels: the text is cut and ends in CUT_MARK when it does not fit, the tail is
## always kept whole. The rule for every long line.
static func fit(text: String, px: int, scale: int = LINE_SCALE, tail: String = "") -> String:
	if PixelFont.text_width(text + tail, scale) <= px:
		return text + tail
	var s := text
	while s.length() > 0 and PixelFont.text_width(s.strip_edges(false, true) + CUT_MARK + tail, scale) > px:
		s = s.substr(0, s.length() - 1)
	return s.strip_edges(false, true) + CUT_MARK + tail


static func _add(rows: Array, kind: int, text: String, max_px: int) -> void:
	var scale := HEAD_SCALE if kind == HEAD else LINE_SCALE
	rows.append([kind, fit(clean(text), max_px, scale)])


static func _section(rows: Array, head: String, lines: Array, max_px: int) -> void:
	rows.append([GAP, ""])
	_add(rows, HEAD, head, max_px)
	for l: String in lines:
		rows.append([LINE, fit(clean(l), max_px)])

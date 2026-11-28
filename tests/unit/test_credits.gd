extends TestCase
## Credits: the lines of the credits roll (game/logic/credits.gd).

const PARTS: Array = [
	{"name": "ENet", "parts": [{"license": "Expat", "files": ["a"], "copyright": ["x"]}]},
	{"name": "glad", "parts": [{"license": "CC0-1.0 and Apache-2.0"}, {"license": "CC0-1.0 and Apache-2.0"}]},
	{"name": "The FreeType Project", "parts": [{"license": "FTL"}, {"license": "BSD-3-clause"}]},
]


func _texts(rows: Array) -> Array[String]:
	var out: Array[String] = []
	for r: Array in rows:
		out.append(String(r[1]))
	return out


## The texts of the rows, gaps left out.
func _lines(rows: Array) -> Array[String]:
	var out: Array[String] = []
	for t: String in _texts(rows):
		if not t.is_empty():
			out.append(t)
	return out


func _roll(maker: String, pics: String, sentry: bool) -> Array:
	return Credits.roll(maker, pics, sentry, "1.2.3", PARTS)


func test_unknown_facts_leave_their_sections_out() -> void:
	var texts := _texts(_roll("", "", false))
	assert_false(texts.has("A GAME BY"), "no maker, no section")
	assert_false(texts.has("PICTURES"), "no picture credit, no section")
	assert_eq(texts[0], "FOUR OF WANDS")
	assert_eq(texts[1], "VERSION 1.2.3")
	assert_true(texts.has("MUSIC AND SOUND"))


func test_no_line_is_empty_or_unfinished() -> void:
	for sentry: bool in [false, true]:
		for pair: Array in [["", ""], ["A MAKER", "A PAINTER"]]:
			for r: Array in _roll(String(pair[0]), String(pair[1]), sentry):
				var kind: int = r[0]
				var s := String(r[1])
				if kind == Credits.GAP:
					continue
				assert_false(s.strip_edges().is_empty(), "empty line")
				for bad: String in ["TBD", "TODO", "XXX", "DEMO", "NULL", "??"]:
					assert_false(s.to_upper().contains(bad), "unfinished or banned word in " + s)


func test_facts_appear_in_place() -> void:
	var texts := _texts(_roll("A MAKER", "A PAINTER", false))
	var by := texts.find("A GAME BY")
	assert_true(by > 0)
	assert_eq(texts[by + 1], "A MAKER")
	var pic := texts.find("PICTURES")
	assert_true(pic > by)
	assert_eq(texts[pic + 1], "A PAINTER")
	assert_true(texts.find("MUSIC AND SOUND") > pic)
	assert_eq(texts[texts.find("MUSIC AND SOUND") + 1], "WRITTEN IN CODE FOR THIS GAME")
	assert_true(texts.find("BUILT WITH") > texts.find("MUSIC AND SOUND"))
	assert_true(texts.has("GODOT ENGINE, MIT LICENCE"))
	assert_true(texts.has("GODOTENGINE.ORG"))
	assert_eq(texts[texts.size() - 1], "THANK YOU FOR PLAYING")


func test_maker_alone_and_pictures_alone() -> void:
	var a := _texts(_roll("A MAKER", "", false))
	assert_true(a.has("A GAME BY"))
	assert_false(a.has("PICTURES"))
	var b := _texts(_roll("", "A PAINTER", false))
	assert_false(b.has("A GAME BY"))
	assert_true(b.has("PICTURES"))


func test_crash_reports_section_follows_the_addon() -> void:
	var off := _texts(_roll("", "", false))
	assert_false(off.has("CRASH REPORTS"))
	assert_false(off.has("CRASHPAD, APACHE 2.0"))
	var on := _texts(_roll("", "", true))
	var i := on.find("CRASH REPORTS")
	assert_true(i >= 0)
	assert_eq(on[i + 1], "SENTRY FOR GODOT, MIT")
	assert_eq(on[i + 2], "SENTRY NATIVE, MIT")
	assert_eq(on[i + 3], "CRASHPAD, APACHE 2.0")
	assert_true(i < on.find("LICENCES"), "crash reports come before the engine's licences")


func test_each_component_is_one_line_with_its_licences() -> void:
	var texts := _lines(_roll("", "", false))
	var from := texts.find("LICENCES")
	var to := texts.find("THE FULL LICENCE TEXTS ARE IN")
	assert_true(from > 0 and to > from)
	var lines := texts.slice(from + 1, to)
	assert_eq(lines.size(), PARTS.size(), "one line per component")
	assert_eq(lines[0], "ENET, EXPAT")
	assert_eq(lines[1], "GLAD, CC0-1.0 AND APACHE-2.0", "a licence named twice is said once")
	assert_eq(lines[2], "THE FREETYPE PROJECT, FTL + BSD-3-CLAUSE")
	assert_eq(texts[to + 1], "THIRD_PARTY_NOTICES.TXT NEXT TO THE GAME")


func test_no_line_is_wider_than_the_frame() -> void:
	var long_parts: Array = PARTS.duplicate(true)
	long_parts.append({"name": "A Very Long Component Name That Goes On And On And On And On And On", "parts": [{"license": "Zlib"}]})
	long_parts.append({"name": "Odd {chars} & more", "parts": [{"license": "MIT"}]})
	for components: Array in [long_parts, Engine.get_copyright_info()]:
		var rows := Credits.roll("A MAKER WITH A VERY LONG NAME INDEED, TO CHECK", "A PAINTER", true, "1.2.3", components)
		for r: Array in rows:
			var s := String(r[1])
			var scale := 2 if r[0] == Credits.HEAD else 1
			assert_true(PixelFont.text_width(s, scale) <= Credits.MAX_PX, "too wide: " + s)
			for ch: String in s:
				assert_true(PixelFont.GLYPHS.has(ch), "no glyph for '%s' in %s" % [ch, s])


func test_long_name_is_cut_by_rule_keeping_the_licence() -> void:
	var rows := Credits.roll("", "", false, "1", [{"name": "Z".repeat(80), "parts": [{"license": "Zlib"}]}])
	var texts := _texts(rows)
	var line := texts[texts.find("LICENCES") + 1]
	assert_true(line.ends_with(", ZLIB"), line)
	assert_true(line.contains(".."), "cut name is marked")


func test_a_cut_line_keeps_its_whole_licence_at_every_width() -> void:
	var parts: Array = [{"name": "Z".repeat(90), "parts": [{"license": "Zlib"}, {"license": "BSD-3-clause"}]}]
	for px: int in range(300, 461):
		var line: String = Credits.component_lines(parts, px)[0]
		assert_true(line.ends_with(".., ZLIB + BSD-3-CLAUSE"), "at %d px: %s" % [px, line])
		assert_true(PixelFont.text_width(line, Credits.LINE_SCALE) <= px, "at %d px the line is %d wide" % [px, PixelFont.text_width(line, Credits.LINE_SCALE)])
		assert_true(Credits.fit(line, px) == line, "a second pass leaves a fitted line alone")


func test_the_engines_own_list() -> void:
	var info := Engine.get_copyright_info()
	assert_true(info.size() > 10)
	var texts := _lines(Credits.roll("", "", false, "1", info))
	var from := texts.find("LICENCES")
	var to := texts.find("THE FULL LICENCE TEXTS ARE IN")
	assert_eq(to - from - 1, info.size() - 1, "every component but the engine itself gets one line")
	for line: String in texts.slice(from + 1, to):
		assert_true(line.contains(", "), "name, licence: " + line)
		assert_false(line.contains(Credits.CUT_MARK), "today's engine list fits uncut: " + line)


func test_the_engine_is_named_once() -> void:
	var parts: Array = PARTS.duplicate(true)
	parts.push_front({"name": "Godot Engine", "parts": [{"license": "Expat"}]})
	var texts := _lines(Credits.roll("", "", false, "1", parts))
	assert_true(texts.has("GODOT ENGINE, MIT LICENCE"), "BUILT WITH names the engine")
	assert_false(texts.has("GODOT ENGINE, EXPAT"), "the licence list does not name it a second time")
	assert_eq(texts[texts.find("LICENCES") + 1], "ENET, EXPAT")

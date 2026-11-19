extends TestCase
## Lore: the run's story text (game/logic/lore.gd).

const GLYPHS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,!?:-+x/'<>#*=()%_"


func _printable(s: String) -> bool:
	for ch: String in s:
		if not GLYPHS.contains(ch):
			return false
	return true


func test_every_line_uses_the_pixel_font() -> void:
	var all: Array[String] = [Lore.LICH_NAME, Lore.ARCHLICH_NAME, Lore.ARCHLICH_TITLE]
	for p: Array in Lore.PROLOGUE:
		all.append(p[0])
		all.append(p[1])
	for a: Array in Lore.ACTS:
		all.append(a[2])
		all.append(a[3])
	for m: String in Lore.MINUTES:
		all.append(m)
	for l: String in Lore.VICTORY_LINES + Lore.DEFEAT_LINES:
		all.append(l)
	for s: String in all:
		assert_true(_printable(s), "unprintable: " + s)


func test_banner_lines_fit_the_screen() -> void:
	for m in Lore.MINUTES.size():
		assert_true(PixelFont.text_width(Lore.minute_line(m), 1) <= 460, Lore.minute_line(m))
	for a in Lore.ACTS.size():
		assert_true(PixelFont.text_width(Lore.act_name(a), 3) <= 470, Lore.act_name(a))


func test_acts_follow_the_liches() -> void:
	assert_eq(Lore.act_of(0), 0)
	assert_eq(Lore.act_of(4), 0)
	assert_eq(Lore.act_of(5), 1)
	assert_eq(Lore.act_of(10), 2)
	assert_eq(Lore.act_of(16), 2)
	assert_true(Lore.opens_act(5))
	assert_true(Lore.opens_act(10))
	assert_false(Lore.opens_act(0))
	assert_false(Lore.opens_act(7))


func test_minute_lines_and_endings() -> void:
	assert_false(Lore.minute_line(1).is_empty())
	assert_eq(Lore.minute_line(5), "HOLD THE TOWER", "boss minutes have no line of their own")
	assert_eq(Lore.minute_line(40), Lore.minute_line(Lore.MINUTES.size() - 1))
	assert_true(Lore.VICTORY_LINES.has(Lore.ending(true, 7)))
	assert_true(Lore.DEFEAT_LINES.has(Lore.ending(false, -3)))


func test_elite_epithets_are_stable_and_cover_negatives() -> void:
	assert_eq(Lore.elite_epithet(3), Lore.elite_epithet(3 + Lore.ELITE_EPITHETS.size()))
	assert_true(not Lore.elite_epithet(-5).is_empty(), "a negative number still names an elite")

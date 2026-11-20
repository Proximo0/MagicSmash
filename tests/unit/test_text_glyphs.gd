extends TestCase
## Texts shown in the pixel font only use characters it can draw (game/ui/pixel_font.gd).


func _drawable(s: String) -> bool:
	for ch: String in s:
		if not PixelFont.GLYPHS.has(ch) and not PixelFont.GLYPHS.has(ch.to_upper()):
			return false
	return true


func test_a_host_name_is_cleaned_to_drawable_characters() -> void:
	var net: Script = load("res://game/autoload/net.gd")
	assert_eq(net.clean_name("zoë~müller"), "ZOMLLER")
	assert_eq(net.clean_name("日本語"), "WIZARD")
	assert_eq(net.clean_name("  "), "WIZARD")
	assert_true(_drawable(net.clean_name("a|b\nc é")))


func test_the_music_box_note_is_drawable() -> void:
	assert_true(_drawable(Sanctum.MUSIC_NOTE), "the music box popup uses a character the font cannot draw")

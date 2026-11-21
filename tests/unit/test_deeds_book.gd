extends TestCase
## DeedsBook: the Sanctum's Book of Deeds screen (game/ui/deeds_book.gd).


func _book() -> DeedsBook:
	var p := Profile.new()
	p.deeds["SOLO_WIN"] = true
	p.deeds["WIN_SEAL_8"] = true
	var b := DeedsBook.new()
	b.open(p)
	return b


func test_it_lists_every_deed() -> void:
	assert_eq(DeedsBook.count(), Achievements.LIST.size())
	var b := _book()
	assert_true(b.active)
	assert_eq(b.sel, 0)


func test_earned_locked_and_secret_rows() -> void:
	var b := _book()
	var solo := b.row_text(Achievements.api_names().find("SOLO_WIN"))
	assert_eq(solo[0], "LONE WIZARD")
	assert_true(solo[3])
	assert_eq(solo[2], "+30")
	var locked := b.row_text(Achievements.api_names().find("WIN_MAGE"))
	assert_false(locked[3])
	assert_eq(locked[0], "THE MAGICIAN", "a plain locked deed shows its name")
	var secret := b.row_text(Achievements.api_names().find("CURSED"))
	assert_eq(secret[0], DeedsBook.SECRET_NAME)
	assert_eq(secret[2], DeedsBook.SECRET_NAME)
	assert_true(secret[4])
	var shown := b.row_text(Achievements.api_names().find("WIN_SEAL_8"))
	assert_eq(shown[0], "THE LAST SEAL", "an earned secret shows itself")


func test_the_selection_scrolls_into_view_and_wraps() -> void:
	var n := DeedsBook.count()
	assert_eq(DeedsBook.scroll_for(0, 0, n), 0)
	assert_eq(DeedsBook.scroll_for(DeedsBook.VISIBLE, 0, n), 1)
	assert_eq(DeedsBook.scroll_for(n - 1, 0, n), n - DeedsBook.VISIBLE)
	assert_eq(DeedsBook.scroll_for(2, n - DeedsBook.VISIBLE, n), 2)
	var b := _book()
	b._select(-1)
	assert_eq(b.sel, n - 1, "up from the top wraps to the last")
	assert_eq(b.top, n - DeedsBook.VISIBLE)
	b._select(n)
	assert_eq(b.sel, 0)
	assert_eq(b.top, 0)


func test_a_closed_book_ignores_input() -> void:
	var b := DeedsBook.new()
	assert_false(b.active)
	assert_false(b.handle(InputEventKey.new()))

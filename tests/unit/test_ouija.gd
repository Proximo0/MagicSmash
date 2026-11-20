extends TestCase
## Ouija: the board used for text entry (game/logic/ouija.gd).


func test_spelling_an_address() -> void:
	var o := Ouija.new()
	for ch: String in "10.0.0.7":
		assert_true(o.type_char(ch))
	assert_eq(o.text, "10.0.0.7")
	assert_false(o.type_char("A"), "letters are not allowed for an address")
	assert_true(o.erase())
	assert_eq(o.text, "10.0.0.")


func test_length_limit() -> void:
	var o := Ouija.new("0123456789.", 3)
	assert_true(o.type_char("1"))
	assert_true(o.type_char("2"))
	assert_true(o.type_char("3"))
	assert_false(o.type_char("4"))
	assert_eq(o.text, "123")


func test_planchette_skips_dimmed_letters() -> void:
	var o := Ouija.new()
	assert_eq(o.row, Ouija.DIGITS_ROW)
	o.move(0, -1)
	assert_eq(o.row, 0, "the letter rows are dimmed, so up goes to YES / NO")
	o.move(0, 1)
	assert_eq(o.row, Ouija.DIGITS_ROW)
	o.move(0, 1)
	assert_eq(o.current(), Ouija.BYE)
	o.move(0, 1)
	assert_eq(o.row, 0, "down from GOOD BYE wraps to the top")


func test_moving_along_a_row_wraps() -> void:
	var o := Ouija.new()
	o.move(-1, 0)
	assert_eq(o.current(), ".")
	o.move(1, 0)
	assert_eq(o.current(), "1")


func test_letters_reachable_when_allowed() -> void:
	var o := Ouija.new("ABCDEFGHIJKLMNOPQRSTUVWXYZ", 8)
	o.move(0, -1)
	assert_eq(o.row, 2)
	assert_true(o.point_at(1, 0))
	assert_eq(o.choose(), Ouija.TYPED)
	assert_eq(o.text, "A")


func test_answers() -> void:
	var o := Ouija.new()
	assert_false(o.point_at(1, 0), "a dimmed letter can't be pointed at")
	o.point_at(0, 1)
	assert_eq(o.choose(), Ouija.NONE, "NO with nothing written does nothing")
	o.type_char("5")
	assert_eq(o.choose(), Ouija.ERASED)
	assert_eq(o.text, "")
	o.point_at(0, 0)
	assert_eq(o.choose(), Ouija.SUBMIT)
	o.point_at(4, 0)
	assert_eq(o.choose(), Ouija.CANCEL)


func test_enter_after_typing_submits() -> void:
	var o := Ouija.new()
	o.type_char("1")
	assert_eq(o.enter(), Ouija.SUBMIT)


func test_enter_after_moving_the_planchette_chooses_the_mark() -> void:
	var o := Ouija.new()
	o.type_char("1")
	o.move(1, 0)
	var mark := o.current()
	assert_eq(o.enter(), Ouija.TYPED, "ENTER sent the address instead of choosing the mark")
	assert_eq(o.text, "1" + mark)
	assert_eq(o.enter(), Ouija.SUBMIT, "after the mark is written ENTER sends")

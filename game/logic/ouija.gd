class_name Ouija
extends RefCounted
## The ouija board used for text entry (the host's address when joining a LAN game). The planchette steps
## between the board's marks with a stick or arrows; choosing a letter or number writes it, NO rubs out the last
## mark, YES is done and GOOD BYE leaves. Marks outside `allowed` are dimmed and skipped. Pure state: the title
## draws it and feeds it input.

const YES := "YES"
const NO := "NO"
const BYE := "GOOD BYE"
const LAYOUT: Array = [
	[YES, NO],
	["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"],
	["N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"],
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "."],
	[BYE],
]
const DIGITS_ROW := 3

const NONE := 0
const TYPED := 1
const ERASED := 2
const SUBMIT := 3
const CANCEL := 4

var text: String = ""
var allowed: String
var max_len: int
var row: int = DIGITS_ROW
var col: int = 0
## Whether the planchette moved since the last typed or erased character: ENTER then chooses the mark under it.
var moved := false


func _init(allowed_chars: String = "0123456789.", max_length: int = 15) -> void:
	allowed = allowed_chars
	max_len = max_length


static func mark(r: int, c: int) -> String:
	return LAYOUT[r][c]


## Whether the planchette may rest on a mark: the answers always, letters and numbers only when allowed.
func enabled(r: int, c: int) -> bool:
	var m: String = LAYOUT[r][c]
	return m.length() > 1 or allowed.contains(m)


func current() -> String:
	return LAYOUT[row][col]


## Moves the planchette: `dx` along the row (wrapping, skipping dimmed marks), `dy` to the next row that has
## an enabled mark, landing on the mark nearest the same place across the board.
func move(dx: int, dy: int) -> void:
	moved = true
	if dx != 0:
		var n: int = LAYOUT[row].size()
		var c := col
		for _i in n:
			c = wrapi(c + dx, 0, n)
			if enabled(row, c):
				col = c
				return
	if dy != 0:
		var frac := _frac(row, col)
		var r := row
		for _i in LAYOUT.size():
			r = wrapi(r + dy, 0, LAYOUT.size())
			var best := -1
			var best_d := INF
			for c in LAYOUT[r].size():
				if enabled(r, c) and absf(_frac(r, c) - frac) < best_d:
					best_d = absf(_frac(r, c) - frac)
					best = c
			if best >= 0:
				row = r
				col = best
				return


## Where a mark sits across its row, 0 (left) to 1 (right); a lone mark sits in the middle.
static func _frac(r: int, c: int) -> float:
	var n: int = LAYOUT[r].size()
	return 0.5 if n == 1 else float(c) / (n - 1)


## Puts the planchette on a mark (a click or tap). Returns false for a dimmed mark.
func point_at(r: int, c: int) -> bool:
	if r < 0 or r >= LAYOUT.size() or c < 0 or c >= LAYOUT[r].size() or not enabled(r, c):
		return false
	row = r
	col = c
	moved = true
	return true


## Chooses the mark under the planchette and returns what happened.
func choose() -> int:
	match current():
		YES:
			return SUBMIT
		NO:
			return ERASED if erase() else NONE
		BYE:
			return CANCEL
	return TYPED if type_char(current()) else NONE


## The ENTER key: sends the text when the planchette has not moved since the last character, otherwise chooses the
## mark under it (what the hint on screen says), like SPACE or A.
func enter() -> int:
	return choose() if moved else SUBMIT


## Writes one character if it is allowed and there is room.
func type_char(ch: String) -> bool:
	ch = ch.to_upper()
	if ch.length() != 1 or not allowed.contains(ch) or text.length() >= max_len:
		return false
	text += ch
	moved = false
	return true


func erase() -> bool:
	if text.is_empty():
		return false
	text = text.left(text.length() - 1)
	moved = false
	return true

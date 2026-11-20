class_name MonsterCard
extends RefCounted
## Draws a monster card face (Cards): a tarot-style frame around the monster's sprite, its name and its bonus.
## Used by the arena's card reveal and the card album. Unfound cards draw as a dark silhouette.

const ENEMY_SPRITES := ["goblin_a", "skeleton_a", "slime_a", "mslime_a", "bat_a", "orc_a", "mage_a", "lich",
	"wraith_a", "tome_a", "gargoyle_a", "priest_a"]
const SOCKET_COLORS := [Color("8bdcff"), Color("ff8af0"), Color("ffd94d")]
const INK := Color("0b0716")
const FACE := Color("1b1030")
const GOLD := Color("ffd94d")
## The least share of a sprite's width and height a card must show to draw it at twice its size.
const BUST := 0.65
## The rectangle of each sprite that holds pixels, by sprite key (read once from its texture).
static var _drawn := {}


## A card face filling `r` (best at 64x96 or larger). `found` false draws the silhouette and "?????".
## `with_bonus` false leaves the bonus line off (the album's small cards show it in the info panel instead).
static func draw(ci: CanvasItem, r: Rect2, idx: int, found: bool, t: float, shine: float = 0.0,
		with_bonus: bool = true) -> void:
	var sock: int = Cards.socket(idx)
	ci.draw_rect(r.grow(1), INK)
	ci.draw_rect(r, FACE)
	ci.draw_rect(r.grow(-1), Color(GOLD, 0.85 if found else 0.3), false, 1.0)
	ci.draw_rect(r.grow(-3), Color(SOCKET_COLORS[sock], 0.5 if found else 0.15), false, 1.0)
	var win := Rect2(r.position.x + 6, r.position.y + 12, r.size.x - 12, r.size.y * 0.5)
	ci.draw_rect(win, Color("0f0820"))
	# A slow ray burst behind a found monster.
	if found:
		var c := win.get_center()
		for i: int in range(8):
			var a := t * 0.4 + i * TAU / 8.0
			ci.draw_line(c, c + Vector2.from_angle(a) * win.size.length() * 0.5, Color(SOCKET_COLORS[sock], 0.12), 2.0)
	var tex: Texture2D = Sprites.get_tex(ENEMY_SPRITES[idx], not found)
	if tex:
		# The card frames the drawn part of the sprite (its map is padded so that it stays centred when it flips)
		# at the largest whole scale that fits the window. A monster too big for twice its size is still drawn
		# so when at least BUST of its width and height fits: what does not fit is cut from the feet up and
		# evenly from both sides, which leaves a bust of the big monsters.
		var src := _drawn_part(ENEMY_SPRITES[idx], tex)
		var room := win.size - Vector2(2, 2)
		var scale := maxf(1.0, floorf(minf(room.x / src.size.x, room.y / src.size.y)))
		if scale < 2.0 and room.x >= src.size.x * 2.0 * BUST and room.y >= src.size.y * 2.0 * BUST:
			scale = 2.0
		var seen := Vector2(minf(src.size.x, floorf(room.x / scale)), minf(src.size.y, floorf(room.y / scale)))
		src = Rect2(src.position.x + floorf((src.size.x - seen.x) / 2.0), src.position.y, seen.x, seen.y)
		var size := seen * scale
		var at := (win.get_center() - size / 2.0).floor()
		var tint := Color.WHITE if found else Color(0.12, 0.06, 0.2)
		ci.draw_texture_rect_region(tex, Rect2(at, size), src, tint)
	ci.draw_rect(win, Color(GOLD, 0.5 if found else 0.2), false, 1.0)
	var cx := r.get_center().x
	PixelFont.draw_centered(ci, Cards.SOCKET_NAMES[sock], cx, r.position.y + 4, 1,
		Color(SOCKET_COLORS[sock], 0.9 if found else 0.35), INK)
	var name_y := win.end.y + 4
	if found:
		_fit_centered(ci, Cards.card_name(idx), cx, name_y, r.size.x - 6, GOLD)
		if with_bonus:
			_fit_centered(ci, Cards.bonus_text(idx), cx, name_y + 10, r.size.x - 6, Color("5dff7a"))
	else:
		PixelFont.draw_centered(ci, "?????", cx, name_y, 1, Color(GOLD, 0.35), INK)
	if shine > 0.0:
		var sx := r.position.x + fposmod(t * 140.0, r.size.x + 40.0) - 20.0
		for k: int in range(6):
			var x := sx + k
			if x >= r.position.x and x < r.end.x:
				ci.draw_rect(Rect2(x, r.position.y, 1, r.size.y), Color(1, 1, 1, 0.18 * shine))


static func _drawn_part(key: String, tex: Texture2D) -> Rect2:
	if not _drawn.has(key):
		_drawn[key] = Rect2(tex.get_image().get_used_rect())
	return _drawn[key]


static func _fit_centered(ci: CanvasItem, text: String, cx: float, y: float, width: float, c: Color) -> void:
	if PixelFont.text_width(text, 1) <= width:
		PixelFont.draw_centered(ci, text, cx, y, 1, c, INK)
		return
	# Too wide: drop a leading "THE " before giving up.
	var short := text.trim_prefix("THE ")
	PixelFont.draw_centered(ci, short, cx, y, 1, c, INK)

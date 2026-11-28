class_name TarotArt
## The level-up cards: every passive upgrade is a Major Arcana tarot card, every spell a grimoire page and every
## evolution an ascension card. Emblems are 16x16 ASCII maps (one character per pixel, "." clear) turned into
## textures on first use. Drawing only; the card's data comes from Upgrades.

const PALETTE := {
	"k": Color("1a0f24"), "w": Color("fff6e0"), "y": Color("ffd94d"), "o": Color("ff8a2a"), "r": Color("e8364f"),
	"b": Color("4b6bff"), "c": Color("7fe8ff"), "p": Color("b07bff"), "v": Color("6a3cd6"), "g": Color("5dff7a"),
	"n": Color("8a5a32"), "s": Color("b8b0c8"), "d": Color("6c6480"), "m": Color("f2ecc8"),
}

const EMBLEMS := {
	"swift": [ # VII The Chariot: a winged wheel
		"................",
		".ww..........ww.",
		"wsww........wwsw",
		"wssww......wwssw",
		".wssww.kk.wwssw.",
		"..wwwkkyykkwww..",
		"....kynkknyk....",
		"...kyk.yy.kyk...",
		"...kyyyyyyyyk...",
		"...kyk.yy.kyk...",
		"....kynkknyk....",
		".....kkyykk.....",
		".......kk.......",
		"................",
		"..nnnnnnnnnnnn..",
		"................",
	],
	"quick": [ # I The Magician: the lemniscate over a wand
		"................",
		"..yyy......yyy..",
		".y...y....y...y.",
		".y....y..y....y.",
		".y.....yy.....y.",
		".y....y..y....y.",
		".y...y....y...y.",
		"..yyy......yyy..",
		"................",
		".......w........",
		"......wcw.......",
		".......k........",
		".......n........",
		".......n........",
		".......n........",
		"......nnn.......",
	],
	"power": [ # VIII Strength: the lion
		"................",
		"....oooooooo....",
		"..oooooooooooo..",
		".ooo.yyyyyy.ooo.",
		".oo.yyyyyyyy.oo.",
		"oo.yykyyyykyy.oo",
		"oo.yyyyyyyyyy.oo",
		"oo.yyyynnyyyy.oo",
		"oo.yyyykkyyyy.oo",
		".oo.yyykkyyy.oo.",
		".ooo.yyyyyy.ooo.",
		"..oooo.yy.oooo..",
		"...oooooooooo...",
		".....oooooo.....",
		"................",
		"................",
	],
	"regen": [ # XIV Temperance: water poured from cup to cup
		"................",
		".....cccccc.....",
		"...cc......cc...",
		"..c..........c..",
		".c............c.",
		"yyyyy......yyyyy",
		"ycccy......ycccy",
		"ycccy......ycccy",
		".yyy........yyy.",
		"..y..........y..",
		"..y..........y..",
		".yyy........yyy.",
		"................",
		"...wwwwwwwwww...",
		"................",
		"................",
	],
	"magnet": [ # XVIII The Moon: a crescent drawing the dew up
		"................",
		".....mmmmm......",
		"...mmmmm........",
		"..mmmm..........",
		".mmmm.......c...",
		".mmm.......ccc..",
		".mmm........c...",
		".mmm............",
		".mmmm.....c.....",
		"..mmmm...ccc....",
		"...mmmmm..c.....",
		".....mmmmm......",
		"................",
		"..c.........c...",
		".ccc.......ccc..",
		"..c.........c...",
	],
	"wisdom": [ # IX The Hermit: the lantern with a star inside
		"................",
		".......ss.......",
		"......s..s......",
		".......ss.......",
		".....ssssss.....",
		"....syyyyyys....",
		"....syywwyys....",
		"....sywwwwys....",
		"....syywwyys....",
		"....syyyyyys....",
		"....syoyyoys....",
		".....ssssss.....",
		"......ssss......",
		"................",
		".......n........",
		"......nnn.......",
	],
	"nova": [ # XVI The Tower: struck by lightning
		"...........yy...",
		"..........yy....",
		"....s.s.syy.....",
		"....sssssyy.....",
		"....sssss..y....",
		".....sss...y....",
		"...o.sks.o......",
		"....osssso......",
		".....sss........",
		".....sks........",
		".....sss........",
		"....sssss.......",
		"...sssssss......",
		"..nnnnnnnnnnnn..",
		"................",
		"................",
	],
	"life": [ # XX Judgement: the heart rises on wings
		"................",
		"................",
		"ww............ww",
		"www..........www",
		".www.rr..rr.www.",
		"..wwrrrrrrrrww..",
		"...wrrwrrrrrw...",
		"....rrrrrrrr....",
		".....rrrrrr.....",
		"......rrrr......",
		".......rr.......",
		"................",
		".......y........",
		"......yyy.......",
		".......y........",
		"................",
	],
	"sun": [ # XIX The Sun: the party's blessing
		"................",
		".......y........",
		"...y...y...y....",
		"....y..y..y.....",
		".....yyyyy......",
		"....yyoooyy.....",
		"yyyyyoyyyoyyyyy.",
		"....yyoooyy.....",
		".....yyyyy......",
		"....y..y..y.....",
		"...y...y...y....",
		".......y........",
		"................",
		"..g.g.g.g.g.g...",
		".ggggggggggggg..",
		"................",
	],
	"death": [ # XIII Death: the party's curse
		"................",
		".....wwwww......",
		"....wwwwwww.....",
		"...wwwwwwwww....",
		"...wkkwwwkkw....",
		"...wkkwwwkkw....",
		"...wwwwkwwww....",
		"....wwwwwww.....",
		".....wkwkw......",
		".....wwwww......",
		"................",
		"..ww.......ww...",
		"....ww...ww.....",
		"......www.......",
		"....ww...ww.....",
		"..ww.......ww...",
	],
	"w_arcane": [
		"................",
		".......p........",
		"......ppp.......",
		".....ppwpp......",
		"....pp.w.pp.....",
		"...pp..w..pp....",
		"..pp..www..pp...",
		".pp..wwpww..pp..",
		"..pp..www..pp...",
		"...pp..w..pp....",
		"....pp.w.pp.....",
		".....ppwpp......",
		"......ppp.......",
		".......p........",
		"................",
		"................",
	],
	"w_fire": [
		"................",
		".......r........",
		"......rr........",
		"......rro.......",
		".....rroo...r...",
		"....rrooo..rr...",
		"...rroooyo.rr...",
		"...rrooyyoorr...",
		"..rrooyyyyoorr..",
		"..rroyywwyyorr..",
		"..rroyywwyyorr..",
		"...rroyyyyorr...",
		"....rrooooorr...",
		"......rrrrr.....",
		"................",
		"................",
	],
	"w_frost": [
		"................",
		".......c........",
		".....c.c.c......",
		"......ccc.......",
		"..c....c....c...",
		"...c...c...c....",
		"....c..c..c.....",
		".cccccwwwccccc..",
		"....c..c..c.....",
		"...c...c...c....",
		"..c....c....c...",
		"......ccc.......",
		".....c.c.c......",
		".......c........",
		"................",
		"................",
	],
	"w_storm": [
		"........yyyy....",
		".......yyyy.....",
		"......yyyy......",
		".....yyyy.......",
		"....yyyy........",
		"...yyyyyyyy.....",
		"......yyyy......",
		".....yyyy.......",
		"....yyyw........",
		"...yyw..........",
		"..yw............",
		".w..............",
		"................",
		"................",
		"................",
		"................",
	],
	"w_star": [
		"................",
		".......y........",
		".......y........",
		"......yyy.......",
		"......ywy.......",
		"yyyyyyywyyyyyyy.",
		".yyyyywwwyyyyy..",
		"...yyywwwyyy....",
		"....yyyyyyy.....",
		"....yyy.yyy.....",
		"...yyy...yyy....",
		"...yy.....yy....",
		"..yy.......yy...",
		"................",
		"................",
		"................",
	],
	"w_rune": [ # a rune circle: a violet ring set with gold glyphs round the warding rune algiz
		"................",
		".....vvvvvv.....",
		"...vvpyppypvv...",
		"..vpp..ww..ppv..",
		"..vpy..ww..ypv..",
		".vy..y.ww.y..yv.",
		".vp...ywwy...pv.",
		".vp....ww....pv.",
		".vp....ww....pv.",
		".vy....ww....yv.",
		".vp....ww....pv.",
		"..vp...ww...pv..",
		"..vpp..rr..ppv..",
		"...vvpyppypvv...",
		".....vvvvvv.....",
		"................",
	],
	"w_bone": [ # a bone spear, point up-right (stand-in)
		"................",
		".............ww.",
		"............www.",
		"...........wwm..",
		"..........mm....",
		".........mm.....",
		"........mm......",
		".......mm.......",
		"......mm........",
		".....mm.........",
		"....mm..........",
		"...mm...........",
		"..wmm...........",
		".www............",
		"..w.............",
		"................",
	],
	"w_candle": [ # a vigil candle and its flame (stand-in)
		"................",
		".......y........",
		"......yoy.......",
		"......yoy.......",
		".......y........",
		".......k........",
		"......mmm.......",
		"......mwm.......",
		"......mwm.......",
		"......mwm.......",
		"......mwm.......",
		"......mmm.......",
		"....nnnnnnn.....",
		".....nnnnn......",
		"................",
		"................",
	],
	"w_cleave": [ # a steel sweep: an arc over a sword (stand-in)
		"................",
		"....ssssssss....",
		"..ss........ss..",
		".s............s.",
		"s......w.......s",
		".......w........",
		".......w........",
		".......w........",
		".......w........",
		".......w........",
		".......w........",
		".....nnnnn......",
		".......n........",
		".......n........",
		"................",
		"................",
	],
	"justice": [ # XI Justice: the scales (stand-in)
		"................",
		".......y........",
		"..yyyyyyyyyyy...",
		"..y....y....y...",
		".y.y...y...y.y..",
		"y...y..y..y...y.",
		"yyyyy..y..yyyyy.",
		".......y........",
		".......y........",
		".......y........",
		".......y........",
		".......y........",
		".....yyyyy......",
		"....yyyyyyy.....",
		"................",
		"................",
	],
	"lovers": [ # VI The Lovers: two hearts (stand-in)
		"................",
		"................",
		".rr.rr..........",
		"rrrrrrr.........",
		"rrrrrrr.........",
		".rrrrr..........",
		"..rrr...........",
		"...r....rr.rr...",
		".......rrrrrrr..",
		".......rrrrrrr..",
		"........rrrrr...",
		".........rrr....",
		"..........r.....",
		"................",
		"................",
		"................",
	],
	"priestess": [ # II The High Priestess: a crescent crown over a veil between two pillars
		"..w....yy....w..",
		"..ww..yyyy..ww..",
		"...ww.yyyy.ww...",
		"....wwwyywww....",
		"................",
		".wwww......wwww.",
		"..ww.vvvvvv.ww..",
		"..ww.vpvvpv.ww..",
		"..ww.vpvvpv.ww..",
		"..ww.vpvvpv.ww..",
		"..ww.vpvvpv.ww..",
		"..ww.vpvvpv.ww..",
		"..ww.vvvvvv.ww..",
		"..ww.v.vv.v.ww..",
		".wwww......wwww.",
		"................",
	],
	"empress": [ # III The Empress: a crown of gold over the sign of Venus
		"................",
		"...y..y..y..y...",
		"...y..y..y..y...",
		"...yyyyyyyyyy...",
		"...yyyyyyyyyy...",
		"................",
		".....gggggg.....",
		"....g......g....",
		"....g......g....",
		"....g......g....",
		"....g......g....",
		".....gggggg.....",
		".......gg.......",
		".....gggggg.....",
		".......gg.......",
		".......gg.......",
	],
	"devil": [ # XV The Devil: a red horned head
		"..o..........o..",
		"..oo........oo..",
		"..ooo.rrrr.ooo..",
		"..oooorrrroooo..",
		"...oorrrrrroo...",
		"....rrrrrrrr....",
		"....ryyrryyr....",
		"....rrrrrrrr....",
		".....rrrrrr.....",
		".....rrrrrr.....",
		"......rrrr......",
		"......rrrr......",
		".......rr.......",
		".......rr.......",
		"................",
		"................",
	],
	"star": [ # XVII The Star: an eight-pointed star over the water
		".......ww.......",
		".......ww.......",
		"..w....ww....w..",
		"...w...ww...w...",
		"....w.wwww.w....",
		"wwwwwwwyywwwwwww",
		"wwwwwwwyywwwwwww",
		"....w.wwww.w....",
		"...w...ww...w...",
		"..w....ww....w..",
		".......ww.......",
		".......ww.......",
		"................",
		".bbb..bbbb..bbb.",
		"b...bb....bb...b",
		"................",
	],
	"w_hex": [ # HEX: the hex mark, a violet eye with a slit pupil and three lashes under it
		"................",
		"................",
		".....pppppp.....",
		"...pppvvvvppp...",
		"..ppvvvwwvvvpp..",
		".ppvvvvwwvvvvpp.",
		".ppvvvvwwvvvvpp.",
		"..ppvvvwwvvvpp..",
		"...pppvvvvppp...",
		".....pppppp.....",
		"................",
		"...p...pp...p...",
		"..p....pp....p..",
		".......pp.......",
		"................",
		"................",
	],
	"w_blades": [ # SPIRIT BLADES: four pale swords circling a spirit light
		"....d...........",
		"..dddwwwwwww....",
		"..dddssssss..dd.",
		"....d........dd.",
		".w..........dddd",
		".ws..........sw.",
		".ws....cc....sw.",
		".ws...cwwc...sw.",
		".ws...cwwc...sw.",
		".ws....cc....sw.",
		".ws..........sw.",
		"dddd..........w.",
		".dd........d....",
		".dd..ssssssddd..",
		"....wwwwwwwddd..",
		"...........d....",
	],
	"e_lodestar": [ # LODESTAR (ARCANE BOLT evolved): a guiding star in a hunter's frame, its north point white
		"vvv..........vvv",
		"v......ww......v",
		"v......ww......v",
		".......ww.......",
		"......pwwp......",
		"......pwwp......",
		"....pppwwppp....",
		".pppppwwwwppppp.",
		".pppppwwwwppppp.",
		"....pppvvppp....",
		"......pvvp......",
		"......pvvp......",
		".......vv.......",
		"v......vv......v",
		"v......vv......v",
		"vvv..........vvv",
	],
	"e_greek": [ # GREEK FIRE (FIREBALL evolved): a clay fire pot with flame rising from its mouth
		".......rr.......",
		"......rrrr......",
		".....rroorr.....",
		".....rroorr.....",
		"....rroooorr....",
		"....rroyyorr....",
		"....rroyyorr....",
		".....rroorr.....",
		".....nnnnnn.....",
		"......nnnn......",
		"....nnnnnnnn....",
		"...nnnnnnnnnn...",
		"...noooooooon...",
		"....nnnnnnnn....",
		".....nnnnnn.....",
		"................",
	],
	"e_veil": [ # WINTER VEIL (FROST FAN evolved): a snowflake inside a ring of mist
		".....ssssss.....",
		"...ss......ss...",
		"..s....ww....s..",
		".s..c..ww..c..s.",
		".s...c.ww.c...s.",
		"s.....cwwc.....s",
		"s......cc......s",
		"s..ccccwwcccc..s",
		"s..ccccwwcccc..s",
		"s......cc......s",
		"s.....cwwc.....s",
		".s...c.ww.c...s.",
		".s..c..ww..c..s.",
		"..s....ww....s..",
		"...ss......ss...",
		".....ssssss.....",
	],
	"e_dies": [ # DIES IRAE (CHAIN LIGHTNING evolved): a bolt of lightning striking a skull
		"..........yyyy..",
		".........yyyy...",
		"........yyyy....",
		".......yyyy.....",
		"......yyyyyyyy..",
		".........yyyy...",
		"........yyyw....",
		".......yyw......",
		".......w........",
		"..mmmmmm........",
		".mmmmmmmm.......",
		".mkkmmkkm.......",
		".mkkmmkkm.......",
		".mmmkkmmm.......",
		"..mkmmkm........",
		"..mmmmmm........",
	],
	"e_hex": [ # EVIL EYE (HEX evolved): an open eye with a violet iris and rays
		"................",
		"................",
		".......pp.......",
		"..p....pp....p..",
		"...p...pp...p...",
		"................",
		"......vvvv......",
		"...vvvwwwwvvv...",
		".vvwwwppppwwwvv.",
		"vvwwwppkkppwwwvv",
		".vvwwwppppwwwvv.",
		"...vvvwwwwvvv...",
		"......vvvv......",
		"................",
		"................",
		"................",
	],
	"e_blades": [ # DANSE MACABRE (SPIRIT BLADES evolved): the ring of swords with a second, violet ring inside
		"....d...........",
		"..dddwwwwwww....",
		"..dddssssss..dd.",
		"....d........dd.",
		".w..........dddd",
		".ws...mppp...sw.",
		".ws..p....m..sw.",
		".ws..p.cc.p..sw.",
		".ws..p.cc.p..sw.",
		".ws..m....p..sw.",
		".ws...pppm...sw.",
		"dddd..........w.",
		".dd........d....",
		".dd..ssssssddd..",
		"....wwwwwwwddd..",
		"...........d....",
	],
}

## [roman numeral, card title] for the Major Arcana passives.
const ARCANA := {
	"swift": ["VII", "THE CHARIOT"], "quick": ["I", "THE MAGICIAN"], "power": ["VIII", "STRENGTH"],
	"regen": ["XIV", "TEMPERANCE"], "magnet": ["XVIII", "THE MOON"], "wisdom": ["IX", "THE HERMIT"],
	"nova": ["XVI", "THE TOWER"], "life": ["XX", "JUDGEMENT"], "sun": ["XIX", "THE SUN"], "death": ["XIII", "DEATH"],
	"world": ["XXI", "THE WORLD"], "emperor": ["IV", "THE EMPEROR"], "fool": ["0", "THE FOOL"],
	"hanged": ["XII", "THE HANGED MAN"], "hierophant": ["V", "THE HIEROPHANT"], "wheel": ["X", "WHEEL OF FORTUNE"],
	"justice": ["XI", "JUSTICE"], "lovers": ["VI", "THE LOVERS"],
	"priestess": ["II", "THE HIGH PRIESTESS"], "empress": ["III", "THE EMPRESS"], "devil": ["XV", "THE DEVIL"],
	"star": ["XVII", "THE STAR"],
}

const KIND_ARCANA := 0
const KIND_GRIMOIRE := 1
const KIND_ASCENSION := 2

const INK := Color("0b0716")
const CARD := Color("1b1030")
const GOLD := Color("ffd94d")
const GOLD_DIM := Color("a8822e")
const LEATHER := Color("4a1a22")

static var _tex := {}


static func kind(key: String) -> int:
	if key.begins_with("w_"):
		return KIND_GRIMOIRE
	if key.begins_with("e_"):
		return KIND_ASCENSION
	return KIND_ARCANA


## The emblem texture for an upgrade key, the first that exists of: the key's icon file, the key's own EMBLEMS entry
## (an evolution may have one), for an evolution its spell's icon file, then its spell's EMBLEMS entry, and STARFALL's.
## An icon file takes the place of the code emblem (`icons/spell_<key>`, `evo_<key>`, `passive_<key>`, reduced to
## EMBLEM_ICON px).
const EMBLEM_ICON := 16


static func emblem(key: String) -> Texture2D:
	var icon := Still.icon(Still.icon_of(key), EMBLEM_ICON)
	if icon != null:
		return icon
	var k := key
	if not EMBLEMS.has(k) and key.begins_with("e_"):
		icon = Still.icon("spell_" + key.substr(2), EMBLEM_ICON)
		if icon != null:
			return icon
		k = "w_" + key.substr(2)
	if not EMBLEMS.has(k):
		k = "w_star"
	if _tex.has(k):
		return _tex[k]
	var rows: Array = EMBLEMS[k]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if PALETTE.has(ch):
				img.set_pixel(x, y, PALETTE[ch])
	var tex := ImageTexture.create_from_image(img)
	_tex[k] = tex
	return tex


## The small heading over the art: the arcana's numeral, GRIMOIRE or ASCENSION.
static func heading(key: String) -> String:
	match kind(key):
		KIND_GRIMOIRE:
			return "GRIMOIRE"
		KIND_ASCENSION:
			return "ASCENSION"
	return ARCANA[key][0] if ARCANA.has(key) else ""


static func _frame_colors(key: String) -> Array:
	match kind(key):
		KIND_GRIMOIRE:
			return [LEATHER, Color("c9844a"), Color("2a0d12")]
		KIND_ASCENSION:
			return [Color("3a2a08"), Color("fff27a"), Color("1e1504")]
	return [CARD, GOLD_DIM, Color("120a22")]


## The back of a card: a dark field with a lattice and an eye, as cards are dealt.
static func draw_back(ci: CanvasItem, r: Rect2) -> void:
	if r.size.x < 2.0:
		return
	# The owner's painted back where it fits: a card shape of 20 px or more, not a wide strip.
	if r.size.x >= 20.0 and r.size.y >= r.size.x * 0.9 and Art.draw(ci, "cards/tarot", "card_back", r):
		return
	ci.draw_rect(r.grow(1), INK)
	ci.draw_rect(r, Color("2a1650"))
	ci.draw_rect(r.grow(-3), Color("1b1030"))
	var step := 8.0
	var y := r.position.y + 5
	while y < r.end.y - 5:
		ci.draw_rect(Rect2(r.position.x + 4, y, maxf(0.0, r.size.x - 8), 1), Color(0.48, 0.3, 1.0, 0.18))
		y += step
	var c := r.get_center()
	var w := minf(r.size.x * 0.35, 14.0)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-w, 0), c + Vector2(0, -w * 0.55), c + Vector2(w, 0),
		c + Vector2(0, w * 0.55)]), Color("e8dcc0"))
	ci.draw_circle(c, w * 0.35, Color("7b4dff"))
	ci.draw_circle(c, w * 0.15, INK)


## A full tarot card for one upgrade: heading, art window, title, effect and level. `lift` raises a highlighted
## card; `accent` is the picking player's colour.
static func draw_card(ci: CanvasItem, r: Rect2, key: String, title: String, effect: String, level_text: String,
		selected: bool, accent: Color, t: float) -> void:
	var cols := _frame_colors(key)
	if selected:
		ci.draw_rect(r.grow(3), Color(accent, 0.35 + 0.2 * sin(t * 6.0)))
	ci.draw_rect(r.grow(1), INK)
	ci.draw_rect(r, cols[0])
	_box(ci, r.grow(-2), cols[1])
	_box(ci, r.grow(-4), Color(cols[1], 0.45))
	var cx := r.get_center().x
	var painting := _painting(key)
	if not painting.is_empty():
		_draw_painted(ci, r, key, painting, title, effect, level_text, selected)
		return
	PixelFont.draw_centered(ci, heading(key), cx, r.position.y + 8, 1, cols[1], INK)
	# The art window: a dusk sky with a few stars, the emblem at 3x.
	var art := Rect2(r.position.x + 10, r.position.y + 19, r.size.x - 20, r.size.x - 20)
	ci.draw_rect(art, cols[2])
	var bands := [Color("2a1650"), Color("3d1d5e"), Color("5a2660")]
	for b in 3:
		ci.draw_rect(Rect2(art.position.x, art.position.y + art.size.y * (0.45 + b * 0.18), art.size.x,
			art.size.y * 0.18 + 1), bands[b])
	for s in 7:
		var sx := art.position.x + fposmod(s * 37.0 + key.length() * 11.0, art.size.x - 2)
		var sy := art.position.y + fposmod(s * 23.0 + 5.0, art.size.y * 0.4)
		var tw := 0.4 + 0.6 * absf(sin(t * 2.0 + s))
		ci.draw_rect(Rect2(sx, sy, 1, 1), Color(1, 1, 1, tw))
	var es := floorf(minf(art.size.x, art.size.y) / 16.0)
	var esz := Vector2(16, 16) * es
	var bob := floorf(sin(t * 2.5) * 1.5) if selected else 0.0
	ci.draw_texture_rect(emblem(key), Rect2(art.get_center() - esz / 2.0 + Vector2(0, bob), esz), false)
	_box(ci, art.grow(1), cols[1])
	# Title banner, effect and level.
	var ty := art.end.y + 6
	ci.draw_rect(Rect2(r.position.x + 4, ty - 3, r.size.x - 8, 13), INK)
	PixelFont.draw_centered(ci, title, cx, ty, 1, GOLD if selected else Color.WHITE, INK)
	_wrap_centered(ci, effect, cx, ty + 15, r.size.x - 10, Color("d8cff0"))
	PixelFont.draw_centered(ci, level_text, cx, r.end.y - 12, 1, Color("5dff7a"), INK)


## A compact card for crowded screens (two or more players picking at once): the emblem in a small window,
## the title beside it, the effect and level under it.
static func draw_card_small(ci: CanvasItem, r: Rect2, key: String, title: String, effect: String,
		level_text: String, selected: bool, accent: Color, t: float) -> void:
	var cols := _frame_colors(key)
	ci.draw_rect(r.grow(1), accent if selected else INK)
	ci.draw_rect(r, cols[0])
	_box(ci, r.grow(-1), Color(cols[1], 0.7 if selected else 0.4))
	var win := Rect2(r.position.x + 3, r.position.y + 3, 18, 18)
	var painting := _painting(key)
	if not painting.is_empty():
		# The painted card as a thumbnail the height of the card, its text clear of it.
		win = Rect2(r.position.x + 3, r.position.y + 3, floorf((r.size.y - 6.0) * 0.49), r.size.y - 6.0)
		ci.draw_rect(win, cols[2])
		Art.draw(ci, "cards/tarot", painting, win)
	else:
		ci.draw_rect(win, cols[2])
		ci.draw_texture_rect(emblem(key), Rect2(win.position + Vector2(1, 1), Vector2(16, 16)), false)
	var head := heading(key)
	PixelFont.draw(ci, head, Vector2(win.end.x + 4, r.position.y + 3), 1, Color(cols[1], 0.9), INK)
	PixelFont.draw(ci, title, Vector2(win.end.x + 4, r.position.y + 13), 1, GOLD if selected else Color.WHITE, INK)
	var cx := (win.end.x + r.end.x) / 2.0 if not painting.is_empty() else r.get_center().x
	PixelFont.draw_centered(ci, effect, cx, r.position.y + 24, 1, Color("c9b8ff"), INK)
	PixelFont.draw(ci, level_text, Vector2(r.end.x - 3 - PixelFont.text_width(level_text), r.position.y + 3), 1,
		Color("5dff7a"), INK)
	if selected:
		var pulse := 0.5 + 0.5 * sin(t * 6.0)
		ci.draw_rect(Rect2(r.position.x, r.end.y - 2, r.size.x, 1), Color(accent, 0.5 + 0.5 * pulse))


## The longest card title and effect text (in characters) a row of the level-up tray fits (draw_card_row in the
## arena's 116 px rows, text from 11 px in, the effect a space clear of the level); Upgrades.CATALOG keeps to them.
const ROW_TITLE_CHARS := 15
const ROW_EFFECT_CHARS := 14


## One card as a row of the level-up tray (17 px tall; its top pixel row is left dark to part it from the row
## above): the kind's colours with a stripe at the left edge, the title over the effect, the level at the right.
## The first `inset` px are left clear for the caller's button glyph.
static func draw_card_row(ci: CanvasItem, r: Rect2, key: String, title: String, effect: String, level_text: String,
		inset: float) -> void:
	var cols := _frame_colors(key)
	var fill := Rect2(r.position + Vector2(0, 1), r.size - Vector2(0, 1)) # the top pixel row stays dark
	ci.draw_rect(fill, cols[0])
	ci.draw_rect(Rect2(fill.position, Vector2(2, fill.size.y)), cols[1])
	var tx := r.position.x + inset
	PixelFont.draw(ci, title, Vector2(tx, r.position.y + 1), 1, Color.WHITE, INK)
	PixelFont.draw(ci, effect, Vector2(tx, r.position.y + 9), 1, Color("d8cff0"), INK)
	# The level sits on a dark chip of its own, so it never reads as the end of the effect text.
	var w := PixelFont.text_width(level_text)
	ci.draw_rect(Rect2(r.end.x - w - 2, r.position.y + 8, w + 2, 9), INK)
	PixelFont.draw(ci, level_text, Vector2(r.end.x - w, r.position.y + 9), 1, Color("5dff7a"), INK)


## A tiny card back for icons (about 7x9): a frame in `accent` around a dark field with an eye.
static func draw_back_icon(ci: CanvasItem, r: Rect2, accent: Color) -> void:
	ci.draw_rect(r.grow(1), INK)
	ci.draw_rect(r, accent)
	ci.draw_rect(r.grow(-1), Color("2a1650"))
	var c := (r.position + r.size / 2.0).floor()
	ci.draw_rect(Rect2(c.x - 1, c.y, 3, 1), Color("e8dcc0"))
	ci.draw_rect(Rect2(c.x, c.y - 1, 1, 3), Color("e8dcc0"))
	ci.draw_rect(Rect2(c.x, c.y, 1, 1), Color("7b4dff"))


## The file name of the painted Major Arcana card for an upgrade key (its title, as a slug), or "" when the
## upgrade has none or its file has not arrived.
static func _painting(key: String) -> String:
	if not ARCANA.has(key):
		return ""
	var slug := Art.slug(ARCANA[key][1])
	return slug if Art.has("cards/tarot", slug) else ""


## The inside of a card whose art is the owner's painting (the paintings carry no text): the picture (numeral
## painted in) fills the frame and the title, effect and level sit on a dark plate over its lower part.
static func _draw_painted(ci: CanvasItem, r: Rect2, key: String, painting: String, title: String, effect: String,
		level_text: String, selected: bool) -> void:
	var cols := _frame_colors(key)
	var inner := r.grow(-4)
	ci.draw_rect(inner, cols[2])
	Art.draw(ci, "cards/tarot", painting, inner)
	var cx := r.get_center().x
	var lines := _lines(effect, inner.size.x - 6.0)
	var plate_h := 14.0 + lines.size() * 10.0 + (11.0 if not level_text.is_empty() else 0.0)
	var plate := Rect2(inner.position.x, inner.end.y - plate_h, inner.size.x, plate_h)
	ci.draw_rect(plate, Color(INK, 0.86))
	ci.draw_rect(Rect2(plate.position, Vector2(plate.size.x, 1)), Color(cols[1], 0.7))
	var name := title if PixelFont.text_width(title) <= inner.size.x - 4.0 else title.trim_prefix("THE ")
	PixelFont.draw_centered(ci, name, cx, plate.position.y + 3, 1, GOLD if selected else Color.WHITE, INK)
	var y := plate.position.y + 14.0
	for line: String in lines:
		PixelFont.draw_centered(ci, line, cx, y, 1, Color("d8cff0"), INK)
		y += 10.0
	if not level_text.is_empty():
		PixelFont.draw_centered(ci, level_text, cx, y, 1, Color("5dff7a"), INK)


## `text` broken into lines that fit `width`.
static func _lines(text: String, width: float) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	for word: String in text.split(" "):
		var trial := word if line.is_empty() else line + " " + word
		if PixelFont.text_width(trial) > width and not line.is_empty():
			out.append(line)
			line = word
		else:
			line = trial
	if not line.is_empty():
		out.append(line)
	return out


static func _box(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), c)
	ci.draw_rect(Rect2(Vector2(r.position.x, r.end.y - 1), Vector2(r.size.x, 1)), c)
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), c)
	ci.draw_rect(Rect2(Vector2(r.end.x - 1, r.position.y), Vector2(1, r.size.y)), c)


## Centred text broken into lines that fit `width`, at 10 px a line.
static func _wrap_centered(ci: CanvasItem, text: String, cx: float, y: float, width: float, c: Color) -> void:
	var line := ""
	var yy := y
	for word: String in text.split(" "):
		var trial := word if line.is_empty() else line + " " + word
		if PixelFont.text_width(trial) > width and not line.is_empty():
			PixelFont.draw_centered(ci, line, cx, yy, 1, c, INK)
			yy += 10
			line = word
		else:
			line = trial
	if not line.is_empty():
		PixelFont.draw_centered(ci, line, cx, yy, 1, c, INK)

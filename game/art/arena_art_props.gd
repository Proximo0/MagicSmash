class_name ArenaArtProps
extends RefCounted
## Small things an arena backdrop is dressed with: skulls, bones, candles, fire bowls, rubble. ASCII maps like
## the ones in Sprites, one character per pixel, stamped on an ArenaArtCanvas. Light comes from the upper left.
##
## Bone maps: h highlight, m mid, s shade, d dark, k eye socket. Candles: w wax, x wax in shade, f wick.
## Iron: I dark, i mid, l lit edge. Embers: e deep red, E orange, Y yellow (they glow in the dark).

const SKULL_FRONT := [
	".hmmms.",
	"hhmmmms",
	"mkkmkks",
	"mkkmkks",
	"smmkmms",
	".smmms.",
	".dsdsd.",
]
const SKULL_TILT := [
	"..hmms.",
	".hmmmms",
	"hmkkmks",
	"mmkkmks",
	"smmkmms",
	".smmms.",
	"..dsd..",
]
const SKULL_LEFT := [
	".hmmm..",
	"hmmmmm.",
	"kkmkkms",
	"kkmkkms",
	"mmkmmss",
	".mmmms.",
	".dsds..",
]
const SKULL_JAWLESS := [
	".hmmms.",
	"hhmmmms",
	"mkkmkks",
	"mkkmkks",
	"smmkmms",
	".sdsds.",
]
const SKULL_CRACKED := [
	".hmdms.",
	"hhmdmms",
	"mkkmkks",
	"mkkmkks",
	"smmkmms",
	".smmms.",
	".dsdsd.",
]
const SKULL_SMALL := [
	".hmm.",
	"hmmms",
	"mkmks",
	"smmms",
	".dsd.",
]
const SKULL_SMALL_SIDE := [
	".hmm.",
	"hmmmm",
	"mmkms",
	".smd.",
]
## Seen from above, lying on its back in a pile.
const SKULL_DOME := [
	".hmm.",
	"hmmms",
	"mmmss",
	".sss.",
]
const SKULLS := [SKULL_FRONT, SKULL_FRONT, SKULL_TILT, SKULL_LEFT, SKULL_JAWLESS, SKULL_CRACKED]

const BONE_FLAT := [
	"h......h",
	"mmmmmmms",
	"s......s",
]
const BONE_SHORT := [
	"h....h",
	"mmmmms",
]
const BONE_UP := [
	"hm",
	"m.",
	"m.",
	"m.",
	"m.",
	"ms",
]
const BONE_DIAG := [
	"h.....",
	"mm....",
	"..mm..",
	"....mm",
	".....s",
]
const RIBS := [
	".mm.mm.",
	"m..m..m",
	"m..m..s",
	".m.m.s.",
]

## Three candles of different heights in a puddle of wax. Wicks sit at CANDLES_WICKS (x, y in the map).
const CANDLES := [
	"..f.....",
	"..wx.f..",
	"f.wx.wx.",
	"wxwx.wx.",
	"wxwxwwx.",
	"wwwwwwxx",
]
const CANDLES_WICKS := [Vector2i(0, 2), Vector2i(2, 0), Vector2i(5, 1)]
const CANDLE_PAIR := [
	"f...",
	"wx.f",
	"wx.w",
	"wxww",
]
const CANDLE_PAIR_WICKS := [Vector2i(0, 0), Vector2i(3, 1)]
const CANDLE_ONE := [
	"f.",
	"wx",
	"wx",
	"wx",
]
const CANDLE_ONE_WICKS := [Vector2i(0, 0)]
const CANDLE_STUB := [
	".f.",
	"wwx",
]
const CANDLE_STUB_WICKS := [Vector2i(1, 0)]

## An iron fire bowl seen from above and a little in front: a ring of iron round a bed of embers.
const BRAZIER := [
	"...IIIIIII...",
	".IIleEeEelII.",
	"IleEYEeYEEelI",
	"IleeEYEEeEelI",
	"IilleeEeelliI",
	".IiilllllliI.",
	"..IIiiiiiII..",
	"....IIIII....",
]
## Where the fire rises from, in the map.
const BRAZIER_FIRE := Vector2i(6, 2)

const RUBBLE_A := [
	".hmm.",
	"hmmms",
	"msssd",
	".ddd.",
]
const RUBBLE_B := [
	"hmm",
	"mss",
	"sdd",
]
const RUBBLE_C := [
	".hm.",
	"hmms",
	".sd.",
]
const RUBBLE_D := [
	"hm",
	"sd",
]
const RUBBLE_BLOCK := [
	".hhhhhh.",
	"hmmmmmms",
	"hmmmmmms",
	"mmmmmmss",
	"sssssssd",
	".dddddd.",
]
## A whole block out of the wall, lying on its side.
const RUBBLE_BIG := [
	"..hhhhhhhh..",
	".hhmmmmmmms.",
	"hmmmmmmmmmss",
	"hmmmmmmmmmss",
	"mmmmmmmmmsss",
	"mssssssssssd",
	".sdddddddddd",
	"..dddddddd..",
]
const RUBBLES := [RUBBLE_A, RUBBLE_B, RUBBLE_C, RUBBLE_D, RUBBLE_B, RUBBLE_D]

## Books lying where they fell. c cover, C cover in shade, p page edge, P page in shade.
const BOOK_FLAT := [
	"cccccc",
	"pppppC",
	"CCCCCC",
]
const BOOK_SMALL := [
	"cccc",
	"pppC",
]
const BOOK_OPEN := [
	"ppp.ppp",
	"pppCppp",
	"PPPCPPP",
	"CCCCCCC",
]
const BOOK_UP := [
	"cC",
	"cC",
	"cC",
	"pC",
	"cC",
]
const BOOKS := [BOOK_FLAT, BOOK_SMALL, BOOK_FLAT, BOOK_OPEN, BOOK_UP, BOOK_SMALL]


## Character map for bone things: `bone` is the first index of an 8-step bone ramp, `lift` moves every shade up
## (a skull by a candle) or down (one deep in a niche).
static func bone_map(bone: int, ink: int, lift: int = 0) -> Dictionary:
	return {
		"h": bone + clampi(5 + lift, 0, 7), "m": bone + clampi(4 + lift, 0, 7), "s": bone + clampi(3 + lift, 0, 7),
		"d": bone + clampi(2 + lift, 0, 7), "k": ink,
	}


## Character map for stone things from a 12-step or 16-step stone ramp around shade `mid`.
static func stone_map(stone: int, mid: int) -> Dictionary:
	return {"h": stone + mid + 2, "m": stone + mid, "s": stone + mid - 2, "d": stone + mid - 4}

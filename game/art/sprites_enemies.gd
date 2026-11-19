class_name SpritesEnemies
## The enemy sprites: ASCII maps (one character per pixel, "." = clear) and their palettes.
## `Sprites.build_all` calls `add_all` once, before it packs the atlas.

const GOBLIN_A := [
	"K........K",
	"GK.KKKK.KG",
	"GGKGGGGKGG",
	".KGYGGYGK.",
	"..KGggGK..",
	"..KKWWKK..",
	".KGbbbbGK.",
	".KGbbbbGK.",
	"..KbKKbK..",
	"..KK..KK..",
]
const GOBLIN_B := [
	"K........K",
	"GK.KKKK.KG",
	"GGKGGGGKGG",
	".KGYGGYGK.",
	"..KGggGK..",
	"..KKWWKK..",
	".KGbbbbGK.",
	".KGbbbbGK.",
	"..KbKKbK..",
	".KK....KK.",
]
const SKELETON_A := [
	"...KKKK...",
	"..KWWWWK..",
	".KWKWWKWK.",
	".KWKWWKWK.",
	"..KWWWWK..",
	"...KwwK...",
	"..KWWWWKb.",
	".KwKWWKwKb",
	".K.KWWK.Kb",
	"...KwwK..b",
	"...KWWK.Kb",
	"..KW..WK..",
	"..KW..WK..",
	".KK....KK.",
]
const SKELETON_B := [
	"...KKKK...",
	"..KWWWWK..",
	".KWKWWKWK.",
	".KWKWWKWK.",
	"..KWWWWK..",
	"...KwwK...",
	"..KWWWWKb.",
	".KwKWWKwKb",
	".K.KWWK.Kb",
	"...KwwK..b",
	"...KWWK.Kb",
	"...KWWK...",
	"..KW..WK..",
	"..KK..KK..",
]
const SLIME_A := [
	"............",
	"....KKKK....",
	"..KKSSSSKK..",
	".KSLLSSSSsK.",
	".KSLSSSSSsK.",
	"KSSKSSSKSSsK",
	"KSSKSSSKSSsK",
	"KSSSSSSSSSsK",
	".KsssssssssK",
	"..KKKKKKKKK.",
]
const SLIME_B := [
	"............",
	"............",
	"...KKKKKK...",
	".KKSLLSSSKK.",
	"KSSLSSSSSSsK",
	"KSSKSSSSKSsK",
	"KSSKSSSSKSsK",
	"KSSSSSSSSSsK",
	"KssssssssssK",
	".KKKKKKKKKK.",
]
const MINI_SLIME_A := [
	"..KKKK..",
	".KSLSSK.",
	"KSKSSKsK",
	"KSSSSSsK",
	".KKKKKK.",
]
const MINI_SLIME_B := [
	"........",
	".KKKKKK.",
	"KSLSSKsK",
	"KSKSSSsK",
	"KKKKKKKK",
]
const BAT_A := [
	"K...........K",
	"KK.........KK",
	"KPK..K.K..KPK",
	"KPPK.KKK.KPPK",
	".KPPKPYPKPPK.",
	"..KPPPPPPPK..",
	"...KK.K.KK...",
]
const BAT_B := [
	".............",
	".............",
	"....KK.KK....",
	"..KKKPKPKKK..",
	".KPPPKYKPPPK.",
	"KPPKKPPPKKPPK",
	"KK...K.K...KK",
]
const ORC_A := [
	"....KKKKKK....",
	"...KAAAAAAK...",
	"..KAaAAAAaAK..",
	"..KGGGGGGGGK..",
	"..KGRGGGGRGK..",
	"..KGGGGGGGGK..",
	"..KWGgggGWGK..",
	".KKKGGGGGGKKK.",
	"KAAAKAAAAKAAAK",
	"KGaAAAAAAAAaGK",
	"KGKAAAaaAAAKGK",
	"KGKAAAAAAAAKGK",
	".K.KbbbbbbK.K.",
	"...KbbKKbbK...",
	"...KGGK.KGK...",
	"..KKKK..KKKK..",
]
const ORC_B := [
	"....KKKKKK....",
	"...KAAAAAAK...",
	"..KAaAAAAaAK..",
	"..KGGGGGGGGK..",
	"..KGRGGGGRGK..",
	"..KGGGGGGGGK..",
	"..KWGgggGWGK..",
	".KKKGGGGGGKKK.",
	"KAAAKAAAAKAAAK",
	"KGaAAAAAAAAaGK",
	"KGKAAAaaAAAKGK",
	"KGKAAAAAAAAKGK",
	".K.KbbbbbbK.K.",
	"...KbbKKbbK...",
	"...KGK.KGGK...",
	"..KKKK..KKKK..",
]
const MAGE_A := [
	"....KK....",
	"...KPPK...",
	"..KPPPpK..",
	"..KPKKpK..",
	".KPKYKYKK.",
	".KPKKKKpK.",
	".KPPKKPpK.",
	"KPPPPPPPpK",
	"KPpPPPPpPK",
	"KPpPPPPpPK",
	"KPPPPPPPpK",
	"KPPPPPPPPK",
	".KpPpPpPK.",
	"..KKKKKK..",
]
const MAGE_B := [
	"....KK....",
	"...KPPK...",
	"..KPPPpK..",
	"..KPKKpK..",
	".KPKYKYKK.",
	".KPKKKKpK.",
	".KPPKKPpK.",
	"KPPPPPPPpK",
	"KPpPPPPpPK",
	"KPpPPPPpPK",
	"KPPPPPPPpK",
	"KPPPPPPPPK",
	".KPpPpPpK.",
	"..KKKKKK..",
]
const WRAITH_A := [
	"...KKKK...",
	"..KGGGGK..",
	".KGgggGGK.",
	".KgEKKEgK.",
	".KgKKKKgK.",
	"KGgKKKKgGK",
	"KGGgKKgGGK",
	"KWGGGGGGWK",
	".KWGGGGGK.",
	".KGGGGGGK.",
	"..KGgGGgK.",
	"..KGK.KgK.",
	"...K..KgK.",
	".......K..",
]
const WRAITH_B := [
	"...KKKK...",
	"..KGGGGK..",
	".KGgggGGK.",
	".KgEKKEgK.",
	".KgKKKKgK.",
	"KGgKKKKgGK",
	"KWGgKKgGWK",
	".KWGGGGGK.",
	".KGGGGGGK.",
	".KGGGGGGK.",
	".KgGGgGK..",
	".KgK.KGK..",
	".KgK..K...",
	"..K.......",
]
const TOME_A := [
	"............",
	".KKKKKKKKKK.",
	"KRRRRRRRRRRK",
	"KRYYRKKRYYRK",
	"KRRKWEEWKRRK",
	"KRRKWEEWKRRK",
	"KRRRKKKKRRRK",
	"KRWKWKWKWKRK",
	"KRKPPPPPPKRK",
	"KRWKWKWKWRRK",
	"KrrrrrrrrrrK",
	".KLLLLLLLLK.",
]
const TOME_B := [
	".KKKKKKKKKK.",
	"KRRRRRRRRRRK",
	"KRYYRKKRYYRK",
	"KRRKWEEWKRRK",
	"KRRKWEEWKRRK",
	"KRRRKKKKRRRK",
	"KRWKWKWKWKRK",
	"KRKPPPPPPKRK",
	"KRKPPPPPPKRK",
	"KRWKWKWKWRRK",
	"KrrrrrrrrrrK",
	".KLLLLLLLLK.",
]
const GARGOYLE_A := [
	"..K........K..",
	".KSK......KSK.",
	".KSSK.KK.KSSK.",
	"KSsSSKSSKSSsSK",
	"KSssSSRRSSssSK",
	"KSsKSSSSSSKsSK",
	"KSK.KSSSSK.KSK",
	"KK..KSsSsK..KK",
	"....KSSSSK....",
	"...KSsSSsSK...",
	"...KSSKKSSK...",
	"..KSsK..KsSK..",
	"..KSK....KSK..",
	"..KK......KK..",
]
const GARGOYLE_B := [
	"..............",
	"K............K",
	"KSK...KK...KSK",
	"KSSK.KSSK.KSSK",
	"KSsSKSRRSKSsSK",
	".KSsSSSSSSsSK.",
	"..KSSSSSSSSK..",
	"...KKSsSsKK...",
	"....KSSSSK....",
	"...KSsSSsSK...",
	"...KSSKKSSK...",
	"..KSsK..KsSK..",
	"..KSK....KSK..",
	"..KK......KK..",
]
const PRIEST_A := [
	"....KKK..Y",
	"...KWWWKKY",
	"..KWKWKWKb",
	"..KWWWWWKb",
	"...KWKWK.b",
	"..KPPPPPKb",
	".KPRPPPRPb",
	".KPPRPRPPb",
	".KPPPRPPPb",
	".KPpPPPpPb",
	".KPpPPPpKb",
	".KPpPPPpK.",
	".KpPpPpPK.",
	"..KKKKKK..",
]
const PRIEST_B := [
	"....KKK.Y.",
	"...KWWWKYK",
	"..KWKWKWKb",
	"..KWWWWWKb",
	"...KWKWK.b",
	"..KPPPPPKb",
	".KPRPPPRPb",
	".KPPRPRPPb",
	".KPPPRPPPb",
	".KPpPPPpPb",
	".KPpPPPpKb",
	".KPpPPPpK.",
	".KPpPpPpK.",
	"..KKKKKK..",
]
const LICH_A := [
	"......Y..Y..Y..Y........",
	"......YK.YK.YK.YK.......",
	"......YYYYYYYYYYY.......",
	"......YyYyYyYyYyY.......",
	"......KWWWWWWWWWK.......",
	".....KWWWWWWWWWWWK......",
	".....KWKKKWWWKKKWK......",
	".....KWKCCKWKCCKWK......",
	".....KWKKKWWWKKKWK......",
	"......KWWWWKWWWWK.......",
	"......KWKWKWKWKWK.......",
	".......KWWWWWWWK........",
	"....KKKKKwwwwwKKKKK.....",
	"...KPPPPPKWWWKPPPPPK....",
	"..KPPpPPPPKWKPPPPpPPK...",
	".KPPpPPPPPPKPPPPPPpPPK..",
	"KWKPpPPPYPPPPPYPPPpPKWK.",
	"KWWKPPPPPYPPPYPPPPPKWWK.",
	".KK.KPPPPPYYYPPPPPK.KK..",
	"....KPpPPPPYPPPPpPK.....",
	"....KPpPPPPPPPPPpPK.....",
	"...KPPpPPPPPPPPPpPPK....",
	"...KPPpPPPPPPPPPpPPK....",
	"..KPPPpPPPPPPPPPpPPPK...",
	"..KPPPPpPPPPPPPpPPPPK...",
	".KpPpPpPpPpPpPpPpPpPpK..",
	".KKKKKKKKKKKKKKKKKKKKK..",
	"........................",
]


static func add_all() -> void:
	var gob := {"K": Sprites.OUTLINE, "G": Color("6fd23c"), "g": Color("2f7a2a"), "Y": Color("ff3030"), "W": Color("fff6d0"), "b": Color("8a5a2b")}
	Sprites._add("goblin_a", GOBLIN_A, gob); Sprites._add("goblin_b", GOBLIN_B, gob)
	var sk := {"K": Sprites.OUTLINE, "W": Color("f2ead8"), "w": Color("b7a98e"), "b": Color("a36a2c")}
	Sprites._add("skeleton_a", SKELETON_A, sk); Sprites._add("skeleton_b", SKELETON_B, sk)
	var sl := {"K": Sprites.OUTLINE, "S": Color("32e0c4"), "s": Color("158f86"), "L": Color("d8fff6")}
	Sprites._add("slime_a", SLIME_A, sl); Sprites._add("slime_b", SLIME_B, sl)
	Sprites._add("mslime_a", MINI_SLIME_A, sl); Sprites._add("mslime_b", MINI_SLIME_B, sl)
	var bat := {"K": Sprites.OUTLINE, "P": Color("9a3bd6"), "Y": Color("ffe23d")}
	Sprites._add("bat_a", BAT_A, bat); Sprites._add("bat_b", BAT_B, bat)
	var orc := {"K": Sprites.OUTLINE, "G": Color("7f9c3a"), "g": Color("3f5a1e"), "R": Color("ff2020"), "W": Color("fffbe8"), "A": Color("8a8fa3"), "a": Color("4d5166"), "b": Color("6b3f1f")}
	Sprites._add("orc_a", ORC_A, orc); Sprites._add("orc_b", ORC_B, orc)
	var mage := {"K": Sprites.OUTLINE, "P": Color("3b1f6e"), "p": Color("25124a"), "Y": Color("ff4df2")}
	Sprites._add("mage_a", MAGE_A, mage); Sprites._add("mage_b", MAGE_B, mage)
	var lich := {"K": Sprites.OUTLINE, "Y": Color("ffd23d"), "y": Color("b8860b"), "W": Color("efe7d2"), "w": Color("a99f86"), "C": Color("4dfff0"), "P": Color("4a1a7a"), "p": Color("2c0d4d")}
	Sprites._add("lich", LICH_A, lich)
	var wraith := {"K": Sprites.OUTLINE, "G": Color("a8f0e0"), "g": Color("4f9a94"), "W": Color("f2fffb"), "E": Color("ff4d6a")}
	Sprites._add("wraith_a", WRAITH_A, wraith); Sprites._add("wraith_b", WRAITH_B, wraith)
	var tome := {"K": Sprites.OUTLINE, "R": Color("8a1f2c"), "r": Color("4e0f18"), "Y": Color("ffd23d"), "W": Color("fffbe8"), "E": Color("ff3a3a"), "P": Color("2a0510"), "L": Color("efe2c0")}
	Sprites._add("tome_a", TOME_A, tome); Sprites._add("tome_b", TOME_B, tome)
	var garg := {"K": Sprites.OUTLINE, "S": Color("8d8a9e"), "s": Color("57546a"), "R": Color("ff5a2a")}
	Sprites._add("gargoyle_a", GARGOYLE_A, garg); Sprites._add("gargoyle_b", GARGOYLE_B, garg)
	var priest := {"K": Sprites.OUTLINE, "W": Color("efe7d2"), "P": Color("2e1a12"), "p": Color("170c08"), "R": Color("c81e3a"), "Y": Color("6dff9a"), "b": Color("8a6a3a")}
	Sprites._add("priest_a", PRIEST_A, priest); Sprites._add("priest_b", PRIEST_B, priest)

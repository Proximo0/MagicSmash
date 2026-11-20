class_name SpritesEnemies
## The enemy sprites: ASCII maps (one character per pixel, "." = clear) and their palettes.
## `Sprites.build_all` calls `add_all` once, before it packs the atlas.
##
## Rules for a map:
## - It faces right; the arena mirrors it toward the nearest wizard. Keep the body centred in the map (pad the
##   empty side with "."), so a flip does not shift it. Every frame of a kind has the same width.
## - The feet stand on the bottom row. A shorter frame sits lower, which is how a walk bobs.
## - Light comes from the upper left: three shades or more per material.
## - "K" is the outline. The elite copies turn every "K" that touches a clear pixel or the map edge gold, so
##   the rim follows the silhouette; "k" is ink for sockets, mouths and other dark lines inside a body.

# --- Goblin: a four-frame scurry (a, c, b, d) ------------------------------------------------------------
const GOBLIN_A := [
	".K.............",
	"KGK.KKKKK.KK...",
	"KLGKGGGGGKGgK..",
	".KGGLLGGGGGgK..",
	".KGGgggGGgggK..",
	".KGGYgGGGgYGKK.",
	".KgGYYGGGYYGGLK",
	"..KgGkWkWkWkKK.",
	"...KKggggggKKSK",
	"..KGKBBBbKGKsK.",
	"..KgKBbbbKgbK..",
	"..KKgKKKKdKK...",
	".KGGK...KdGK...",
	"..KK.....KK....",
]
const GOBLIN_B := [
	".K.............",
	"KGK.KKKKK.KK...",
	"KLGKGGGGGKGgK..",
	".KGGLLGGGGGgK..",
	".KGGgggGGgggK..",
	".KGGYgGGGgYGKK.",
	".KgGYYGGGYYGGLK",
	"..KgGkWkWkWkKK.",
	"...KKggggggKKSK",
	"..KGKBBBbKGKsK.",
	"..KgKBbbbKgbK..",
	"..KKdKKKKgKK...",
	".KdGK...KGGK...",
	"..KK.....KK....",
]
const GOBLIN_C := [
	".K.............",
	"KGK.KKKKK.KK...",
	"KLGKGGGGGKGgK..",
	".KGGLLGGGGGgK..",
	".KGGgggGGgggK..",
	".KGGYgGGGgYGKK.",
	".KgGYYGGGYYGGLK",
	"..KgGkWkWkWkKK.",
	"...KKggggggK...",
	"..KGKBBBbKGKKK.",
	"..KgKBbbbKGKsSK",
	"...KKgKKdKgbKK.",
	"....KGKKdKKK...",
	".....K..K......",
]
const GOBLIN_D := [
	".K.............",
	"KGK.KKKKK.KK...",
	"KLGKGGGGGKGgK..",
	".KGGLLGGGGGgK..",
	".KGGgggGGgggK..",
	".KGGYgGGGgYGKK.",
	".KgGYYGGGYYGGLK",
	"..KgGkWkWkWkKK.",
	"...KKggggggK...",
	"..KGKBBBbKGKKK.",
	"..KgKBbbbKGKsSK",
	"...KKdKKgKgbKK.",
	"....KdKKGKKK...",
	".....K..K......",
]

# --- Skeleton archer: a four-frame march (a, c, b, d) ----------------------------------------------------
const SKELETON_A := [
	"...KKKKK......",
	"..KHHWWWK.....",
	".KHWWWWWwK....",
	".KWWkkWkkK....",
	".KWWkkWkkK....",
	".KwWWWkWwK....",
	"..KwWkWkWK.K..",
	"...KwwwwK.KbK.",
	"..K.KwdKKKdKbK",
	".KWKWWWWWKdKbK",
	".KwKkkWkkWWWBK",
	".KWKWWWWWKdKbK",
	"..KKkkwkkKdKbK",
	"...KwWWWK.KbK.",
	"...KWKKwKK.K..",
	"..KWWK.KwWK...",
	"...KK...KK....",
]
const SKELETON_B := [
	"...KKKKK......",
	"..KHHWWWK.....",
	".KHWWWWWwK....",
	".KWWkkWkkK....",
	".KWWkkWkkK....",
	".KwWWWkWwK....",
	"..KwWkWkWK.K..",
	"...KwwwwK.KbK.",
	"..K.KwdKKKdKbK",
	".KWKWWWWWKdKbK",
	".KwKkkWkkWWWBK",
	".KWKWWWWWKdKbK",
	"..KKkkwkkKdKbK",
	"...KwWWWK.KbK.",
	"...KwKKWKK.K..",
	"..KwwK.KWWK...",
	"...KK...KK....",
]
const SKELETON_C := [
	"...KKKKK......",
	"..KHHWWWK.....",
	".KHWWWWWwK....",
	".KWWkkWkkK....",
	".KWWkkWkkK....",
	".KwWWWkWwK....",
	"..KwWkWkWK.K..",
	"...KwwwwK.KbK.",
	"..K.KwdKKKdKbK",
	".KWKWWWWWKdKbK",
	".KwKkkWkkWWWBK",
	".KWKWWWWWKdKbK",
	"..KKkkwkkKdKbK",
	"...KwWWWK.KbK.",
	"....KWwK...K..",
	"....KWwK......",
	"...KWWwK......",
	"....KKK.......",
]
const SKELETON_D := [
	"...KKKKK......",
	"..KHHWWWK.....",
	".KHWWWWWwK....",
	".KWWkkWkkK....",
	".KWWkkWkkK....",
	".KwWWWkWwK....",
	"..KwWkWkWK.K..",
	"...KwwwwK.KbK.",
	"..K.KwdKKKdKbK",
	".KWKWWWWWKdKbK",
	".KwKkkWkkWWWBK",
	".KWKWWWWWKdKbK",
	"..KKkkwkkKdKbK",
	"...KwWWWK.KbK.",
	"....KwWK...K..",
	"....KwWK......",
	"....KwWWK.....",
	".....KKK......",
]

# --- Slime: a rest, b squash, c stretch, d in the air ----------------------------------------------------
const SLIME_A := [
	"......KKKKKK......",
	"....KKMMSSSSKK....",
	"...KMMLLMSSSSSK...",
	"..KMMLLMSSSSSSsK..",
	"..KMMMSSSkSSkSsK..",
	"..KMSSSSSkSSkssK..",
	"..KSSsSSSSSSSssK..",
	".KsSSSSSSSSsssssK.",
	".KssSSSSSssssDDsK.",
	"..KDDssssssDDDDK..",
	"...KKKKKKKKKKKK...",
]
const SLIME_B := [
	".....KKKKKKKK.....",
	"...KKMMSSSSSSKK...",
	"..KMMLLMSSSSSSsK..",
	".KMMLLMSSkSSkSSsK.",
	".KMMSSSSSkSSkSssK.",
	".KsSSsSSSSSSsssDK.",
	".KDDsssssssssDDDK.",
	"..KKKKKKKKKKKKKK..",
]
const SLIME_C := [
	".......KKKK.......",
	"......KMSSSK......",
	".....KMLLSSSK.....",
	"....KMMLLSSSsK....",
	"....KMMLSSSSsK....",
	"....KMMSSkSksK....",
	"....KMSSSkSksK....",
	"....KSSSSSSSsK....",
	"....KSSsSSSssK....",
	"....KsSSSSsssK....",
	"....KssSSsssDK....",
	".....KDssssDK.....",
	"......KKKKKK......",
]
const SLIME_D := [
	"......KKKKKK......",
	"....KKMMSSSSKK....",
	"...KMMLLMSSSSsK...",
	"..KMMLLMSSSSSSsK..",
	"..KMMMSSSkSSkSsK..",
	"..KMSSSSSkSSkssK..",
	"..KSSsSSSSSSSssK..",
	"..KsSSSSSSSSssDK..",
	"...KssSSSSsssDK...",
	"....KKDssssDKK....",
	"......KKKKKK......",
]

# --- Mini slime: a rest, b squash, c stretch -------------------------------------------------------------
const MSLIME_A := [
	"...KKKKK...",
	"..KMSSSSK..",
	".KMLLSSSsK.",
	".KMMSkSksK.",
	".KSSSSSssK.",
	".KDssssDDK.",
	"..KKKKKKK..",
]
const MSLIME_B := [
	"..KKKKKKK..",
	".KMMSSSSSK.",
	"KMLLSkSkSsK",
	"KMSSSSSSssK",
	"KDsssssDDDK",
	".KKKKKKKKK.",
]
const MSLIME_C := [
	"....KKK....",
	"...KMSSK...",
	"..KMLLSsK..",
	"..KMMkSkK..",
	"..KMSSSsK..",
	"..KSSSssK..",
	"..KDssDDK..",
	"...KKKKK...",
]

# --- Bat: a wings up, b wings down, c level, d half folded -----------------------------------------------
const BAT_A := [
	".K..............K.",
	"KLK............KLK",
	"KLLK..K....K..KLLK",
	"KMLLKKpK..KpKKLLMK",
	"KMMLLKpPKKPpKLLMMK",
	"KmMMMLPPPPPPLMMMmK",
	".KKmMMPYPPYPMMmKK.",
	"...KmMpWkkWpMmK...",
	"....KKpPPPPpKK....",
	"......KpKKpK......",
	".......K..K.......",
	"..................",
]
const BAT_B := [
	"......K....K......",
	".....KpK..KpK.....",
	".....KpPKKPpK.....",
	"....KKPPPPPPKK....",
	"..KKLLPYPPYPLLKK..",
	".KLLMMpWkkWpMMLLK.",
	"KLMMMMpPPPPpMMMMLK",
	"KMMmmKKpKKpKKmmMMK",
	"KMmKK..K..K..KKmMK",
	"KmK............KmK",
	".K..............K.",
	"..................",
]
const BAT_C := [
	"..................",
	"......K....K......",
	".....KpK..KpK.....",
	"..KKKKpPKKPpKKKK..",
	".KLLLLPPPPPPLLLLK.",
	"KLMMMMPYPPYPMMMMLK",
	"KMMmmMpWkkWpMmmMMK",
	"KmKKmKpPPPPpKmKKmK",
	".K..K.KpKKpK.K..K.",
	".......K..K.......",
	"..................",
	"..................",
]
const BAT_D := [
	"..................",
	"......K....K......",
	"...KKKpK..KpKKK...",
	"..KLLKpPKKPpKLLK..",
	".KLMMLPPPPPPLMMLK.",
	".KMMmMPYPPYPMmMMK.",
	".KmKmKpWkkWpKmKmK.",
	"..K.KKpPPPPpKK.K..",
	"......KpKKpK......",
	".......K..K.......",
	"..................",
	"..................",
]

# --- Orc brute: a, c, b, c stomp; wind is the wind-up, charge and charge2 the run ------------------------
const ORC_A := [
	"..........KKKKK...........",
	".........KGGGGGK..........",
	"........KGOOGGGgK.........",
	".......KGOGGGGGGgK........",
	"....KK.KddddGddddK.KK.....",
	"...KAAKKgEkgGEkgdKKaaK....",
	"..KAHAAKGGGGggGGgKaAAaK...",
	".KAHAAAAgWgkkkgWgaAAAAaK..",
	".KAAAAAagWWgggWWdaAAaAaK..",
	".KaAAAaaKggggggdKaaAaaaK..",
	".KGGGaaGbBGGGGGGGGgaaGGgK.",
	".KOGGgKGObBBGGgGGGgKGGGgK.",
	".KGGGgKGGGGgbBBGGggKGGGgK.",
	".KGGGgKgGGggGGGbBggKGGGgK.",
	".KBBbbKBBBBBYYBBBBbKOGGwK.",
	".KOGGgKbBBbbBBbBBbbKGGwwwK",
	".KGGgdKKGGGgKKGGGgKKgwwwWK",
	"..KKKK.KGGggKKGGGgK.KWwwwK",
	"......KsSSSsKKGGggK.KwwwWK",
	"......KSSSssKsSSSsK.KwWwwK",
	".......KKKKKKSSSSssK.KwwK.",
	".............KKKKKK...KK..",
]
const ORC_B := [
	"..........KKKKK...........",
	".........KGGGGGK..........",
	"........KGOOGGGgK.........",
	".......KGOGGGGGGgK........",
	"....KK.KddddGddddK.KK.....",
	"...KAAKKgEkgGEkgdKKaaK....",
	"..KAHAAKGGGGggGGgKaAAaK...",
	".KAHAAAAgWgkkkgWgaAAAAaK..",
	".KAAAAAagWWgggWWdaAAaAaK..",
	".KaAAAaaKggggggdKaaAaaaK..",
	".KGGGaaGbBGGGGGGGGgaaGGgK.",
	".KOGGgKGObBBGGgGGGgKGGGgK.",
	".KGGGgKGGGGgbBBGGggKGGGgK.",
	".KGGGgKgGGggGGGbBggKGGGgK.",
	".KBBbbKBBBBBYYBBBBbKOGGwK.",
	".KOGGgKbBBbbBBbBBbbKGGwwwK",
	".KGGgdKKGGGgKKGGGgKKgwwwWK",
	"..KKKK.KGGGgKKGGggK.KWwwwK",
	".......KGGggKsSSSsK.KwwwWK",
	"......KsSSSsKSSSSssKKwWwwK",
	"......KSSSssKKKKKKK..KwwK.",
	".......KKKKK..........KK..",
]
const ORC_C := [
	"..........KKKKK...........",
	".........KGGGGGK..........",
	"........KGOOGGGgK.........",
	".......KGOGGGGGGgK........",
	"....KK.KddddGddddK.KK.....",
	"...KAAKKgEkgGEkgdKKaaK....",
	"..KAHAAKGGGGggGGgKaAAaK...",
	".KAHAAAAgWgkkkgWgaAAAAaK..",
	".KAAAAAagWWgggWWdaAAaAaK..",
	".KaAAAaaKggggggdKaaAaaaK..",
	".KGGGaaGbBGGGGGGGGgaaGGgK.",
	".KOGGgKGObBBGGgGGGgKGGGgK.",
	".KGGGgKGGGGgbBBGGggKGGGgK.",
	".KGGGgKgGGggGGGbBggKGGGgK.",
	".KBBbbKBBBBBYYBBBBbKOGGwK.",
	".KOGGgKbBBbbBBbBBbbKGGwwwK",
	".KGGgdKKGGGgKKGGGgKKgwwwWK",
	"..KKKK.KGGggKKGGggK.KWwwwK",
	"......KsSSSsKsSSSsK.KwWwwK",
	"......KSSSssKSSSSssK.KwwK.",
	".......KKKKK.KKKKKK...KK..",
]
const ORC_WIND := [
	"..................KKK.....",
	".................KwWwK....",
	"................KWwwwwK...",
	"..........KKKKK.KwwwWwK...",
	".........KGGGGGKKwwwwwK...",
	"........KGOOGGGgKWwwwK....",
	".......KGOGGGGGGgKwwK.....",
	"....KK.KddddGddddKwwK.....",
	"...KAAKKgYkgGYkgdGGgK.....",
	"..KAHAAKGGGGggGGgGGGgK....",
	".KAHAAAAgWkkkkkWgAAAaK....",
	".KAAAAAagWkkkkkWdAAAaK....",
	".KaAAAaaKgWgggWdKaAaaK....",
	".KGGGaaGbBGGGGGGGGgaaK....",
	".KOGGgKGObBBGGgGGGgKK.....",
	".KGGGgKGGGGgbBBGGggK......",
	".KGGGgKgGGggGGGbBggK......",
	".KBBbbKBBBBBYYBBBBbK......",
	".KOGGgKbBBbbBBbBBbbK......",
	".KGGgdKKGGGgKKGGGgK.......",
	"..KKKK.KGGGgKKGGGgK.......",
	".......KGGggKKGGggK.......",
	"......KsSSSsKsSSSsK.......",
	"......KSSSssKSSSSssK......",
	".......KKKKK.KKKKKK.......",
]
const ORC_CHARGE := [
	"...................KKK....",
	"..................KwWwK...",
	".................KWwwwwK..",
	"...........KKKKK.KwwwWwK..",
	"..........KGGGGGKKwwwwwK..",
	".........KGOOGGGgKWwwwK...",
	"........KGOGGGGGGgKwwK....",
	".....KK.KddddGddddKwwK....",
	"....KAAKKgYkgGYkgdGGgK....",
	"...KAHAAKGGGGggGGgGGGgK...",
	"..KAHAAAAgWkkkkkWgAAAaK...",
	"..KAAAAAagWkkkkkWdAAAaK...",
	"..KaAAAaaKgWgggWdKaAaaK...",
	"..KGGGaaGbBGGGGGGGGgaaK...",
	"..KOGGgKGObBBGGgGGGgKK....",
	"..KGGGgKGGGGgbBBGGggK.....",
	"..KGGGgKgGGggGGGbBggK.....",
	"..KBBbbKBBBBBYYBBBBbK.....",
	"..KOGGgKbBBbbBBbBBbbK.....",
	"..KGGgdKKGGGgKKGGGgK......",
	"...KKKKKGGGgK.KGGGgK......",
	"......KsSSSsK.KGGggK......",
	"......KSSSssKKsSSSsK......",
	".......KKKKK.KSSSSssK.....",
	"..............KKKKKK......",
]
const ORC_CHARGE2 := [
	"...................KKK....",
	"..................KwWwK...",
	".................KWwwwwK..",
	"...........KKKKK.KwwwWwK..",
	"..........KGGGGGKKwwwwwK..",
	".........KGOOGGGgKWwwwK...",
	"........KGOGGGGGGgKwwK....",
	".....KK.KddddGddddKwwK....",
	"....KAAKKgYkgGYkgdGGgK....",
	"...KAHAAKGGGGggGGgGGGgK...",
	"..KAHAAAAgWkkkkkWgAAAaK...",
	"..KAAAAAagWkkkkkWdAAAaK...",
	"..KaAAAaaKgWgggWdKaAaaK...",
	"..KGGGaaGbBGGGGGGGGgaaK...",
	"..KOGGgKGObBBGGgGGGgKK....",
	"..KGGGgKGGGGgbBBGGggK.....",
	"..KGGGgKgGGggGGGbBggK.....",
	"..KBBbbKBBBBBYYBBBBbK.....",
	"..KOGGgKbBBbbBBbBBbbK.....",
	"..KGGgdKKGGGgKKGGGgK......",
	"...KKKK.KGGGgKKGGGgK......",
	"........KGGggKsSSSsK......",
	".......KsSSSsKSSSSssK.....",
	".......KSSSssKKKKKKK......",
	"........KKKKK.............",
]

# --- Dark mage: a and b drift, cast levels the lit staff -------------------------------------------------
const MAGE_A := [
	".......KK...............",
	"......KpPK........K.....",
	"......KPLPKK.....KFK....",
	".......KPLPPK...KFHFK...",
	".......KLLPPPK...KFK....",
	"......KLLPPPPpK..KbK....",
	"......KLPkkkkPpK.KbK....",
	"......KPkFkkFkpK.KbK....",
	"......KPkkkkkPpK.KbK....",
	"......KPPkkkPppK.KbK....",
	".....KLLPPPPPPppKsbK....",
	"....KLLPPPPPPPPPPsbK....",
	"....KLPpPPPPPPpppKbK....",
	"....KPpKLPPPPppKKKbK....",
	".....KKKLPPPPppK.KbK....",
	"......KLLPPPPPppKKbK....",
	"......KLPPPPpPppKKbK....",
	".....KLLPPPPpPPppKbK....",
	".....KTTTTTTTTTTTKbK....",
	"......KKKKKKKKKKK.K.....",
]
const MAGE_B := [
	".......KK...............",
	"......KpPK.......K.K....",
	"......KPLPKK....KFKFK...",
	".......KPLPPK....KHK....",
	".......KLLPPPK..KFKFK...",
	"......KLLPPPPpK..KbK....",
	"......KLPkkkkPpK.KbK....",
	"......KPkFkkFkpK.KbK....",
	"......KPkkkkkPpK.KbK....",
	"......KPPkkkPppK.KbK....",
	".....KLLPPPPPPppKsbK....",
	"....KLLPPPPPPPPPPsbK....",
	"....KLPpPPPPPPpppKbK....",
	"....KPpKLPPPPppKKKbK....",
	".....KKKLPPPPppK.KbK....",
	"......KLLPPPPPppKKbK....",
	".....KLLPPPPpPPpKKbK....",
	"....KLLPPPPPpPPppKbK....",
	"....KTTTTTTTTTTTTKbK....",
	".....KKKKKKKKKKKK.K.....",
]
const MAGE_CAST := [
	".......KK...............",
	"......KpPK..............",
	"......KPLPKK............",
	".......KPLPPK...........",
	".......KLLPPPK..........",
	"......KLLPPPPpK.........",
	"......KLPkkkkPpK........",
	"......KPkHkkHkpK........",
	"......KPkkkkkPpK....K...",
	"......KPPkkkPppK...KFK..",
	".....KLLPPPPPPppKKKFHFK.",
	"....KLLPPPPPPPPPsbbHHHFK",
	"....KLPpPPPPPPpppKKFHFK.",
	"....KPpKLPPPPppKK..KFK..",
	".....KKKLPPPPppK....K...",
	"......KLLPPPPPppK.......",
	".....KLLPPPPpPPppK......",
	"....KLLPPPPPpPPPppK.....",
	"....KTTTTTTTTTTTTTK.....",
	".....KKKKKKKKKKKKK......",
]

# --- Wraith: a and b hover; fade_a and fade_b are the rim that is left while it cannot be hit ------------
const WRAITH_A := [
	"......KKKKK.......",
	"....KKWWWWWKK.....",
	"...KWWLLWWWWmK....",
	"..KWWLWWWWWWmmK...",
	"..KWWWWWWWWWWmK...",
	"..KWWkkWWWkkWmK...",
	"..KWWWkkWkkWmmK...",
	"..KmWWWWkWWWmwK...",
	"..KmWWkkkkkWmwK...",
	"...KmWkkkkkmwKKK..",
	"...KmWWkkkWmwKWWK.",
	"..KWWmWWWWmmwWWmWK",
	".KWWmmmWWmmmwwmKWK",
	".KWmKmmWWmmwwKK.K.",
	".KmKKWmmWmmwK.....",
	"..K.KWmmWmmwK.....",
	"...KWWmmmwmwK.....",
	"...KWmKmmwKwK.....",
	"..KWmKKmwK.K......",
	"...KK..KK.........",
]
const WRAITH_B := [
	"......KKKKK.......",
	"....KKWWWWWKK.....",
	"...KWWLLWWWWmK....",
	"..KWWLWWWWWWmmK...",
	"..KWWWWWWWWWWmK...",
	"..KWWkkWWWkkWmK...",
	"..KWWWkkWkkWmmK...",
	"..KmWWWWkWWWmwK...",
	"..KmWWkkkkkWmwK...",
	"...KmWkkkkkmwK....",
	"...KmWWkkkWmwKKK..",
	"..KWWmWWWWmmwKWWK.",
	".KWWmmmWWmmmwWWmWK",
	".KWmKmmWWmmwwmKKWK",
	".KmKKWmmWmmwKK..K.",
	"..K.KWmmWmmwK.....",
	"...KWWmmmwmwK.....",
	"....KWmmWmKmwK....",
	"....KmKmwK.KwK....",
	".....K.KK...K.....",
]
const WRAITH_FADE_A := [
	"..................",
	"......wwwww.......",
	"....ww.....ww.....",
	"...w.........w....",
	"...w.........w....",
	"...w.dd...dd.w....",
	"...w..dd.dd..w....",
	"...w....d....w....",
	"...w..ddddd..w....",
	"....w.ddddd.w.....",
	"....w..ddd..w.ww..",
	"...w.........w.ww.",
	"..w.w........ww.w.",
	"..ww.w......w.....",
	"..w..w.....w......",
	".....w.....w......",
	"....w.w...ww......",
	"....ww.w.w.w......",
	"...ww..ww.........",
	"..................",
]
const WRAITH_FADE_B := [
	"..................",
	"......wwwww.......",
	"....ww.....ww.....",
	"...w.........w....",
	"...w.........w....",
	"...w.dd...dd.w....",
	"...w..dd.dd..w....",
	"...w....d....w....",
	"...w..ddddd..w....",
	"....w.ddddd.w.....",
	"....w..ddd..w.....",
	"...w........w.ww..",
	"..w.w........wwww.",
	"..ww.w......ww..w.",
	"..w..w.....w......",
	".....w.....w......",
	"....w.....ww......",
	".....ww..w.ww.....",
	".....w.ww...w.....",
	"..................",
]

# --- Cursed tome: a, b, c flap; rear before the dash, dash in it -----------------------------------------
const TOME_A := [
	"..................",
	".KK............KK.",
	"KRWKKK......KKKWrK",
	"KRwWWWKKKKKKWWWwrK",
	"KRWwwwWWWWWWwwwWrK",
	"KRwWWWwkkkkwWWWwrK",
	"KRWwwwkERREkwwwWrK",
	"KRRWWWwkkkkwWWWrrK",
	".KKRRRWWWWWWrrrKK.",
	"...KKKRRYYrrKKK...",
	"......KKKKKK......",
	"..................",
	"..................",
]
const TOME_B := [
	"..................",
	"..................",
	"..................",
	".KKKKKKKKKKKKKKKK.",
	"KRWWWWWWWWWWWWWWrK",
	"KRWwwwWkkkkWwwwWrK",
	"KRWWWWkERREkWWWWrK",
	"KRWwwwWkkkkWwwwWrK",
	"KRWWWWWWWWWWWWWWrK",
	"KrRRRRRRYYRRRRRrrK",
	".KKKKKKKKKKKKKKKK.",
	"..................",
	"..................",
]
const TOME_C := [
	"..................",
	"..................",
	"..................",
	"......KKKKKK......",
	"...KKKWWWWWWKKK...",
	".KKWWWwkkkkwWWWKK.",
	"KRWwwwkERREkwwwWrK",
	"KRwWWWwkkkkwWWWwrK",
	"KRWwwwWWWWWWwwwWrK",
	"KRwWWWRRYYrrWWWwrK",
	"KRWRRRKKKKKKrrrWrK",
	"KrRKKK......KKKrrK",
	".KK............KK.",
]
const TOME_REAR := [
	"..................",
	".KK............KK.",
	"KRWKKK......KKKWrK",
	"KRwWWWKKKKKKWWWwrK",
	"KRWwwwWWWWWWwwwWrK",
	"KRwWWWwTTTTwWWWwrK",
	"KRWwwwTTHHTTwwwWrK",
	"KRRWWWwTTTTwWWWrrK",
	".KKRRRWWWWWWrrrKK.",
	"...KKKRRYYrrKKK...",
	"......KKKKKK......",
	"..................",
	"..................",
]
const TOME_DASH := [
	"..................",
	"..................",
	"..................",
	"......KKKKKK......",
	"...KKKWWWWWWKKK...",
	".KKWWWwTTTTwWWWKK.",
	"KRWwwwTTHHTTwwwWrK",
	"KRwWWWwTTTTwWWWwrK",
	"KRWwwwWWWWWWwwwWrK",
	"KRwWWWRRYYrrWWWwrK",
	"KRWRRRKKKKKKrrrWrK",
	"KrRKKK......KKKrrK",
	".KK............KK.",
]

# --- Gargoyle: a statue, wake (eyes lit), b and c in flight ----------------------------------------------
const GARGOYLE_A := [
	"...........K....K...........",
	".....K....KWK..KWK....K.....",
	"....KHK...KWK..KWK...KaK....",
	"....KHAK..KwKKKKwK..KAaK....",
	"....KHAaK.KAAAAAAK.KAAaK....",
	"....KHAAaKHdAAAAdaKAAadK....",
	"....KHAAaKAkdAAdkaKaAadK....",
	"....KHAadKAAkddkAaKaAadK....",
	"....KHAaddaAAAAAaddaAadK....",
	"....KHAadddWkWWkWddaAadK....",
	"....KHadAddaAAAAdddaddsK....",
	"....KHadAddAdAadaddaddsK....",
	"....KHadAddAdAadaddaddsK....",
	"....KHadAddAdAadaddaddsK....",
	".....KadAddAdAadaddadsK.....",
	"......KKAdKAdAadaKdadK......",
	"........KHaHaKKaHaHKK.......",
	".........KKKK..KKKK.........",
]
const GARGOYLE_WAKE := [
	"...........K....K...........",
	".....K....KWK..KWK....K.....",
	"....KHK...KWK..KWK...KaK....",
	"....KHAK..KwKKKKwK..KAaK....",
	"....KHAaK.KAAAAAAK.KAAaK....",
	"....KHAAaKHdAAAAdaKAAadK....",
	"....KHAAaKAEdAAdEaKaAadK....",
	"....KHAadKAAEddEAaKaAadK....",
	"....KHAaddaAAAAAaddaAadK....",
	"....KHAadddWkWWkWddaAadK....",
	"....KHadAddaAAAAdddaddsK....",
	"....KHadAddAdAadaddaddsK....",
	"....KHadAddAdAadaddaddsK....",
	"....KHadAddAdAadaddaddsK....",
	".....KadAddAdAadaddadsK.....",
	"......KKAdKAdAadaKdadK......",
	"........KHaHaKKaHaHKK.......",
	".........KKKK..KKKK.........",
]
const GARGOYLE_B := [
	"..K........K....K........K..",
	".KHK......KWK..KWK......KaK.",
	".KHAK.....KWK..KWK.....KAaK.",
	".KHdAK....KwKKKKwK....KAdaK.",
	".KHddAK...KAAAAAAK...KAddaK.",
	".KHdddAK.KHdAAAAdaK.KAdddaK.",
	".KHddddAKKAEdAAdEaKKAddddaK.",
	".KHdAdddAKAAEddEAaKAdddadaK.",
	"..KAdAdddAaAAAAAadAdddadaK..",
	"..KAKdAddAdWkWWkWdAddadKaK..",
	"...KKdKAdAAaAAAAdaAdaKdKK...",
	".....KKAKdAAAAAAAAadKaK.....",
	".......K.KHAAAAAAadK.K......",
	".........KAAaAAaAAdK........",
	".........KAAaKKKAAdK........",
	".........KHaHK.KHaHK........",
	"..........KKK...KKK.........",
]
const GARGOYLE_C := [
	"...........K....K...........",
	"..........KWK..KWK..........",
	"..........KWK..KWK..........",
	"..........KwKKKKwK..........",
	"..........KAAAAAAK..........",
	".........KHdAAAAdaK.........",
	"....KKKKKKAEdAAdEaKKKKKK....",
	"..KKHAAAAKAAEddEAaKAAAAaKK..",
	".KHAAdddAAaAAAAAadAAdddAAaK.",
	"KHAdddAddddWkWWkWddddAdddAaK",
	"KAdddAdddAAaAAAAdaAdddAdddaK",
	"KAddKAddKdHAAAAAAadKddaKddaK",
	"KAKKKAKK.KAAaAAaAAdKKaK.KaK.",
	".K...K...KAAaKKKAAdK.K...K..",
	".........KHaHK.KHaHK........",
	"..........KKK...KKK.........",
	"............................",
]

# --- Bone priest: a and b walk; raise lifts the flame ----------------------------------------------------
const PRIEST_A := [
	"......KK.....K....",
	".....KWWK...KgK...",
	"....KWWWWK.KgGK...",
	"....KWYYwK.KGLgK..",
	"...KWWYYWwKKgGgK..",
	"...KHWWWWwK.KbK...",
	"...KWkkWkkK.KbK...",
	"...KWkGWkGK.KbK...",
	"...KwWWkWwK.KbK...",
	"...KKWkWkwKKhbK...",
	"..KRRRwwwRRrhbK...",
	".KRRRYRRRYRrrbK...",
	".KRrRYRRRYrrKbK...",
	".KhKRRYRYRrrKbK...",
	"..KKRRRYRRrrKbK...",
	"...KRRRYRrrqKbK...",
	"..KRRRRYRRrrqK....",
	"..KRRRrRRrRrqqK...",
	".KRRrRRrRRrRrqqK..",
	"..KKKKKKKKKKKKK...",
]
const PRIEST_B := [
	"......KK....K.....",
	".....KWWK..KgK....",
	"....KWWWWK.KGgK...",
	"....KWYYwK.KgLGK..",
	"...KWWYYWwKKgGgK..",
	"...KHWWWWwK.KbK...",
	"...KWkkWkkK.KbK...",
	"...KWkGWkGK.KbK...",
	"...KwWWkWwK.KbK...",
	"...KKWkWkwKKhbK...",
	"..KRRRwwwRRrhbK...",
	".KRRRYRRRYRrrbK...",
	".KRrRYRRRYrrKbK...",
	".KhKRRYRYRrrKbK...",
	"..KKRRRYRRrrKbK...",
	"...KRRRYRrrqKbK...",
	"...KRRRYRRrrqK....",
	"..KRRRRRRrRrqqK...",
	"..KRrRRrRRrRrqK...",
	"...KKKKKKKKKKK....",
]
const PRIEST_RAISE := [
	"............KK....",
	"...........KggK...",
	"..........KgGGgK..",
	"......KK..KGLLGK..",
	".....KWWKKgGLLGgK.",
	"....KWWWWKKgGGgK..",
	"....KWYYwK.KgbK...",
	"...KWWYYWwK.KbK...",
	"...KHWWWWwK.KbK...",
	".K.KWLLWLLK.KbK...",
	"KhKKWLGWLGK.KbK...",
	"KhhKwWWkWwKKhbK...",
	".KRRKWkkkWKRhbK...",
	".KRRRRwkwRRRrbK...",
	"..KRRYRRRYRrrK....",
	"...KRYRRRYrrK.....",
	"...KRRYRYRrrK.....",
	"...KRRRYRRrrK.....",
	"...KRRRYRrrqK.....",
	"..KRRRRYRRrrqK....",
	"..KRRRrRRrRrqqK...",
	".KRRrRRrRRrRrqqK..",
	"..KKKKKKKKKKKKK...",
]

# --- The Lich (the Archlich is the same maps in its own palette) -----------------------------------------
const LICH_A := [
	"................K..........K......",
	"............K..KYK..K.....KCK.....",
	"...........KYK.KYK.KYK....KCCK....",
	"...........KYYKYCYKYYK....KCFCK...",
	"...........KHYYYYYYYyK...KCFFCK...",
	"...........KyYyYyYyYyK...KYCFCYK..",
	"..........KHHWWWWWWWwK...KYYCYYK..",
	".......K.KHHWWWWWWWWWwK.K.KYYyK...",
	"......KLKKHWWkkWWWkkWwKKPK.KSK....",
	"......KLPKWWWkCkWkCkWwKPpK.KSK....",
	".....KLPpKWWWkkkWkkkwwKPPpKKSK....",
	".....KLPPpKwWWWWkWWWwKqPPpKKSK....",
	".....KLPPpKwWWWWWWWWwKqPPpKKSK....",
	".....KLPPpqKWkWkWkWwKqqPPpKKSK....",
	"....KKPPPpqKwWwWwWdKqqPPPpKKSK....",
	"...KYYYLPPpqKwwwwdKqpPpYYyKKSK....",
	"..KYLLLYLPPpqqqqqqqqqpYLPPyKSK....",
	".KLLPPPPYpPPPPYYYYYPpYPPPPpKSK....",
	".KLLPPPPPYPPPPPyCyPPYPPPPPpWWwK...",
	".KLPPPPPPpPPPPPPyPPppPPPPPpWwwK...",
	".KLPPPPPpqPPPPPPPPPPpqpPPPpqSK....",
	".KLPPPPPpqPPPPPCPPPPpqpPPpqKSK....",
	".KPPPPPPpqPPPPPCCPPPpqpPpqKKSK....",
	".KpPPPPPPpPPPPCFCPPPpqppqK.KSK....",
	".KpPPPPPPpPPPPCFFCPPpqKKK..KSK....",
	".KpPPLLLLLLYWCFFFCWPpqK....KSK....",
	".KpPPPPPPPPYwCCFCCwPPpqK...KSK....",
	"..KpPPPPPPPywWWWWWwPPpqK...KSK....",
	"...KpppppppqqdwwwdqPPPpqK..KSK....",
	"....KLPPLPPPPPPyyPPPPppqK..KSK....",
	"....KLPPLPPPPPYqqyPPPPppqK.KSK....",
	"...KLPPPLPPPPPYqqqyPPPPppqKKSK....",
	"...KLPPPLPPPPYqqqqyPPPPPppqKSK....",
	"...KLPPPLPPPPYqqpqqyPPPPppqKSK....",
	"..KLPPPPLPPPYqqqpqqqyPPPppqKSK....",
	"..KLPPPPLPPPYqqqpqqqqyPPppqKSK....",
	"..KLPPPPPLPYqqqqpqqqqyPPppqKSK....",
	"..KLPPPPPLPYqqqpqqpqqqyPppqKsK....",
	"..KPPpKpPLPyqqKpqqKqqqyPpKqKK.....",
	"...KpK.KpPpKqK.KqK.KqqKpK.K.......",
	"....K...KKK.K...K...KK.K..........",
]
const LICH_B := [
	"................K............K....",
	"............K..KYK..K.......KCK...",
	"...........KYK.KYK.KYK.....KCCK...",
	"...........KYYKYCYKYYK....KCFCK...",
	"...........KHYYYYYYYyK....KCFFCK..",
	"...........KyYyYyYyYyK...KYCFCYK..",
	"..........KHHWWWWWWWwK...KYYCYYK..",
	".......K.KHHWWWWWWWWWwK.K.KYYyK...",
	"......KLKKHWWkkWWWkkWwKKPK.KSK....",
	"......KLPKWWWkCkWkCkWwKPpK.KSK....",
	".....KLPpKWWWkkkWkkkwwKPPpKKSK....",
	".....KLPPpKwWWWWkWWWwKqPPpKKSK....",
	".....KLPPpKwWWWWWWWWwKqPPpKKSK....",
	".....KLPPpqKWkWkWkWwKqqPPpKKSK....",
	"....KKPPPpqKwWwWwWdKqqPPPpKKSK....",
	"...KYYYLPPpqKwwwwdKqpPpYYyKKSK....",
	"..KYLLLYLPPpqqqqqqqqqpYLPPyKSK....",
	".KLLPPPPYpPPPPYYYYYPpYPPPPpKSK....",
	".KLLPPPPPYPPPPPyCyPPYPPPPPpWWwK...",
	".KLPPPPPPpPPPPPPyPPppPPPPPpWwwK...",
	".KLPPPPPpqPPPPPPPPPPpqpPPPpqSK....",
	".KLPPPPPpqPPPPPPCPPPpqpPPpqKSK....",
	".KPPPPPPpqPPPPPCCPPPpqpPpqKKSK....",
	".KpPPPPPPpPPPPPCFCPPpqppqK.KSK....",
	".KpPPPPPPpPPPPCFFCPPpqKKK..KSK....",
	".KpPPLLLLLLYWCFFFCWPpqK....KSK....",
	".KpPPPPPPPPYwCCFCCwPPpqK...KSK....",
	"..KpPPPPPPPywWWWWWwPPpqK...KSK....",
	"...KpppppppqqdwwwdqPPPpqK..KSK....",
	"....KLPPLPPPPPPyyPPPPppqK..KSK....",
	"....KLPPLPPPPPYqqyPPPPppqK.KSK....",
	"...KLPPPLPPPPPYqqqyPPPPppqKKSK....",
	"...KLPPPLPPPPYqqqqyPPPPPppqKSK....",
	"...KLPPPLPPPPYqqpqqyPPPPppqKSK....",
	"..KLPPPPLPPPYqqqpqqqyPPPppqKSK....",
	"..KLPPPPLPPPYqqqpqqqqyPPppqKSK....",
	"..KLPPPPPLPYqqqqpqqqqyPPppqKSK....",
	"..KLPPPPPLPYqqqpqqpqqqyPppqKsK....",
	"..KPPKPpPLPyqKqpqqqKqqyPppqKK.....",
	"..KPKKpKKPKKqKKqKqK.KqKPpKK.......",
	"...K..K..K..K..K.K...K.KK.........",
]
const LICH_CAST := [
	"................K..........K.K....",
	"............K..KYK..K.....KCKCK...",
	"...........KYK.KYK.KYK...KCFCFCK..",
	"...........KYYKYCYKYYK...KCFFFCK..",
	"...........KHYYYYYYYyK...KCFFFCK..",
	"...........KyYyYyYyYyK...KYCFCYK..",
	"..........KHHWWWWWWWwK...KYYCYYK..",
	".......K.KHHWWWWWWWWWwK.K.KYYyK...",
	"......KLKKHWWCCWWWCCWwKKPK.KSK....",
	"......KLPKWWWCFCWCFCWwKPpK.KSK....",
	".....KLPpKWWWCCCWCCCwwKPPpKKSK....",
	".....KLPPpKwWWWWkWWWwKqPPpKKSK....",
	".....KLPPpKwWWWWWWWWwKqPPpKKSK....",
	".....KLPPpqKWkWkWkWwKqqPPpKKSK....",
	"....KKPPPpqKwkkkkkdKqqPPPpKKSK....",
	"...KYYYLPPpqKwwwwdKqpPpYYyKKSK....",
	"..KYLLLYLPPpqqqqqqqqqpYLPPyKSK....",
	".KLLPPPPYpPPPPYCYYYPpYPPPPpKSK....",
	".KLLPPPPPYPPPPPCCyPPYPPPPPpWWwK...",
	".KLPPPPPPpPPPPCFCPPppPPPPPpWwwK...",
	".KLPPPPPpqPPPPCFFCPPpqpPPPpqSK....",
	".KLPPPPPpqPPPCFFFCPPpqpPPpqKSK....",
	".KPPPPPPpqPPPCFFFFCPpqpPpqKKSK....",
	".KpPPPPPPpPPCFFFFFCPpqppqK.KSK....",
	".KpPPPPPPpPPCFFFFFCPpqKKK..KSK....",
	".KpPPLLLLLLYWCFFFCWPpqK....KSK....",
	".KpPPPPPPPPYwCCFCCwPPpqK...KSK....",
	"..KpPPPPPPPywWWWWWwPPpqK...KSK....",
	"...KpppppppqqdwwwdqPPPpqK..KSK....",
	"....KLPPLPPPPPPyyPPPPppqK..KSK....",
	"....KLPPLPPPPPYqqyPPPPppqK.KSK....",
	"...KLPPPLPPPPPYqqqyPPPPppqKKSK....",
	"...KLPPPLPPPPYqqqqyPPPPPppqKSK....",
	"...KLPPPLPPPPYqqpqqyPPPPppqKSK....",
	"..KLPPPPLPPPYqqqpqqqyPPPppqKSK....",
	"..KLPPPPLPPPYqqqpqqqqyPPppqKSK....",
	"..KLPPPPPLPYqqqqpqqqqyPPppqKSK....",
	"..KLPPPPPLPYqqqpqqpqqqyPppqKsK....",
	"..KPPpKpPLPyqqKpqqKqqqyPpKqKK.....",
	"...KpK.KpPpKqK.KqK.KqqKpK.K.......",
	"....K...KKK.K...K...KK.K..........",
]

# --- The elite mark and the floor halos (drawn under the sprites) ----------------------------------------
const ELITE_MARK := [
	"..K.K.K..",
	".KYKYKYK.",
	".KYYYYYK.",
	".KyYyYyK.",
	"..KKKKK..",
]
const ELITE_HALO := [
	"........1111111111........",
	"....111122222222221111....",
	"..1112223333333333222111..",
	".112223333333333333322211.",
	"11222333333333333333322211",
	"11222333333333333333322211",
	"11222333333333333333322211",
	".112223333333333333322211.",
	"..1112223333333333222111..",
	"....111122222222221111....",
	"........1111111111........",
]
const BOSS_HALO := [
	"...............1111111111111111...............",
	"..........11111111112222221111111111..........",
	".......11111122222222222222222222111111.......",
	"....11111222222223333333333332222222211111....",
	"...1111222222333333333333333333332222221111...",
	".11111222233333333333333333333333333222211111.",
	".11112222333333333333333333333333333322221111.",
	"1111222233333333333333333333333333333322221111",
	"1111222233333333333333333333333333333322221111",
	"1111222233333333333333333333333333333322221111",
	".11112222333333333333333333333333333322221111.",
	".11111222233333333333333333333333333222211111.",
	"...1111222222333333333333333333332222221111...",
	"....11111222222223333333333332222222211111....",
	".......11111122222222222222222222111111.......",
	"..........11111111112222221111111111..........",
	"...............1111111111111111...............",
]


## The kinds `World._spawn_elite` can pick. Each has a second copy of every frame under "elite_" + key with its
## rim gilded, so an elite keeps its size and still stands out of the horde.
const ELITE_KINDS := ["skeleton", "orc", "mage", "priest", "gargoyle"]
## Height in pixels of each kind's standing frame, by enemy type (the `World` constants): the health bar and the
## elite mark sit just above it.
const TOP := [14, 18, 11, 7, 12, 22, 20, 41, 20, 13, 18, 20]

## Every frame as [key, rows, palette], kind by kind. `add_all` registers them; sheet tools read the same list.
static func frames() -> Array:
	var out: Array = []
	var ol: Color = Sprites.OUTLINE
	var ink := Color("0b0716")
	var gob := {"K": ol, "k": ink, "G": Color("6fd23c"), "g": Color("2f7a2a"), "d": Color("1c4a22"), "L": Color("b4f07a"),
		"Y": Color("ffcf5a"), "W": Color("e8dcc0"), "B": Color("c85a1e"), "b": Color("7a2f14"), "S": Color("e8dcc0"), "s": Color("b7a98e")}
	_enemy_set(out, gob, {"goblin_a": GOBLIN_A, "goblin_b": GOBLIN_B, "goblin_c": GOBLIN_C,
		"goblin_d": GOBLIN_D})
	var sk := {"K": ol, "k": ink, "H": Color("fff6e0"), "W": Color("e8dcc0"), "w": Color("b7a98e"), "d": Color("7d705c"),
		"B": Color("c85a1e"), "b": Color("7a2f14")}
	_enemy_set(out, sk, {"skeleton_a": SKELETON_A, "skeleton_b": SKELETON_B,
		"skeleton_c": SKELETON_C, "skeleton_d": SKELETON_D})
	var sl := {"K": ol, "k": ink, "L": Color("d8fff6"), "M": Color("8ef0dc"), "S": Color("32e0c4"), "s": Color("158f86"), "D": Color("0f6468")}
	_enemy_set(out, sl, {"slime_a": SLIME_A, "slime_b": SLIME_B, "slime_c": SLIME_C,
		"slime_d": SLIME_D})
	_enemy_set(out, sl, {"mslime_a": MSLIME_A, "mslime_b": MSLIME_B, "mslime_c": MSLIME_C})
	var bat := {"K": ol, "k": ink, "P": Color("6b52a8"), "p": Color("4b3a78"), "L": Color("b9a6f0"), "M": Color("8f76d6"), "m": Color("6b52a8"),
		"Y": Color("ffcf5a"), "W": Color("e8dcc0")}
	_enemy_set(out, bat, {"bat_a": BAT_A, "bat_b": BAT_B, "bat_c": BAT_C, "bat_d": BAT_D})
	var orc := {"K": ol, "k": ink, "O": Color("6fd23c"), "G": Color("47a030"), "g": Color("2f7a2a"), "d": Color("1c4a22"),
		"H": Color("a39bbd"), "A": Color("7d7398"), "a": Color("5d5378"), "S": Color("5d5378"), "s": Color("3b3150"),
		"B": Color("c85a1e"), "b": Color("7a2f14"), "Y": Color("ffd94d"), "W": Color("e8dcc0"), "w": Color("7a2f14"), "E": Color("ff9a3c")}
	_enemy_set(out, orc, {"orc_a": ORC_A, "orc_b": ORC_B, "orc_c": ORC_C, "orc_wind": ORC_WIND,
		"orc_charge": ORC_CHARGE, "orc_charge2": ORC_CHARGE2})
	var mage := {"K": ol, "k": ink, "P": Color("4b3a78"), "p": Color("3a2a5e"), "d": Color("2a1f45"), "L": Color("6b52a8"),
		"F": Color("ff4df2"), "H": Color("ffd0fb"), "b": Color("7d705c"), "s": Color("b7a98e"), "T": Color("a02a9a")}
	_enemy_set(out, mage, {"mage_a": MAGE_A, "mage_b": MAGE_B, "mage_cast": MAGE_CAST})
	var wraith := {"K": ol, "k": ink, "W": Color("d8fff6"), "m": Color("8ef0dc"), "w": Color("32e0c4"), "L": Color("ffffff"), "d": Color("158f86")}
	_enemy_set(out, wraith, {"wraith_a": WRAITH_A, "wraith_b": WRAITH_B,
		"wraith_fade_a": WRAITH_FADE_A, "wraith_fade_b": WRAITH_FADE_B})
	var tome := {"K": ol, "k": ink, "R": Color("c0263a"), "r": Color("7a1226"), "Y": Color("ffd94d"), "W": Color("e8dcc0"), "w": Color("b7a98e"),
		"E": Color("ffcf5a"), "T": Color("ff4df2"), "H": Color("ffd0fb")}
	_enemy_set(out, tome, {"tome_a": TOME_A, "tome_b": TOME_B, "tome_c": TOME_C,
		"tome_rear": TOME_REAR, "tome_dash": TOME_DASH})
	var garg := {"K": ol, "k": ink, "H": Color("a39bbd"), "A": Color("7d7398"), "a": Color("5d5378"), "d": Color("4a4063"),
		"s": Color("3b3150"), "W": Color("e8dcc0"), "w": Color("b7a98e"), "E": Color("ff9a3c"), "Y": Color("ffcf5a")}
	_enemy_set(out, garg, {"gargoyle_a": GARGOYLE_A, "gargoyle_wake": GARGOYLE_WAKE,
		"gargoyle_b": GARGOYLE_B, "gargoyle_c": GARGOYLE_C})
	var priest := {"K": ol, "k": ink, "H": Color("fff6e0"), "W": Color("e8dcc0"), "w": Color("b7a98e"), "R": Color("c0263a"), "r": Color("7a1226"),
		"Y": Color("ffd94d"), "y": Color("c48a10"), "G": Color("29d16b"), "g": Color("15864a"), "L": Color("8bff9e"), "b": Color("7d705c"),
		"h": Color("e8dcc0"), "q": Color("4d0b1a")}
	_enemy_set(out, priest, {"priest_a": PRIEST_A, "priest_b": PRIEST_B, "priest_raise": PRIEST_RAISE})
	var lich := {"K": ol, "k": ink, "Y": Color("ffd94d"), "y": Color("c48a10"), "H": Color("fff6e0"), "W": Color("e8dcc0"), "w": Color("b7a98e"),
		"d": Color("7d705c"), "L": Color("6b52a8"), "P": Color("4b3a78"), "p": Color("3a2a5e"), "q": Color("2a1f45"),
		"C": Color("4dfff0"), "F": Color("d8fff6"), "c": Color("158f86"), "S": Color("b7a98e"), "s": Color("7d705c")}
	var lich_maps: Dictionary = {"lich": LICH_A, "lich_b": LICH_B, "lich_cast": LICH_CAST}
	_enemy_set(out, lich, lich_maps)
	# The Archlich: the same maps under their own keys ("arch" + key), in a darker robe with magenta fire.
	var arch: Dictionary = lich.duplicate()
	arch.merge({"L": Color("4b3a78"), "P": Color("3a2a5e"), "p": Color("2a1f45"), "q": Color("1c1230"),
		"C": Color("ff4df2"), "F": Color("ffd0fb"), "c": Color("a02a9a")}, true)
	for key: String in lich_maps:
		out.append(["arch" + key, lich_maps[key], arch])
	# Elites: a gilded copy of every frame of the kinds that can be one.
	var gold := {"1": Color("ffd94d"), "2": Color("c48a10")}
	for i: int in out.size():
		var f: Array = out[i]
		var key: String = f[0]
		if key.get_slice("_", 0) in ELITE_KINDS:
			var pal: Dictionary = (f[2] as Dictionary).duplicate()
			pal.merge(gold)
			out.append(["elite_" + key, _gild(f[1]), pal])
	out.append(["elite_mark", ELITE_MARK, {"K": ol, "Y": Color("ffd94d"), "y": Color("c48a10")}])
	# Floor halos: drawn under the sprites, so their colours carry their own alpha.
	out.append(["elite_halo", ELITE_HALO, {"1": Color(1.0, 0.85, 0.3, 0.6), "2": Color(1.0, 0.6, 0.24, 0.3), "3": Color(1.0, 0.6, 0.24, 0.12)}])
	out.append(["lich_halo", BOSS_HALO, {"1": Color(0.3, 1.0, 0.94, 0.5), "2": Color(0.2, 0.88, 0.77, 0.24), "3": Color(0.2, 0.88, 0.77, 0.1)}])
	out.append(["archlich_halo", BOSS_HALO, {"1": Color(1.0, 0.3, 0.95, 0.6), "2": Color(1.0, 0.85, 0.3, 0.3), "3": Color(1.0, 0.3, 0.95, 0.12)}])
	return out


static func _enemy_set(out: Array, pal: Dictionary, maps: Dictionary) -> void:
	for key: String in maps:
		out.append([key, maps[key], pal])


## A copy of a map with its rim gilded: every "K" on the map edge, or next to a clear pixel that the map edge
## reaches, turns to gold: light ("1") where it is open above, dark ("2") elsewhere. Outline inside the body,
## and round a hole in it, stays ink.
static func _gild(rows: Array) -> Array:
	var h := rows.size()
	var w := (rows[0] as String).length()
	var outside := {}
	var todo: Array[Vector2i] = []
	for y: int in h:
		for x: int in w:
			if (x == 0 or y == 0 or x == w - 1 or y == h - 1) and (rows[y] as String)[x] == ".":
				outside[Vector2i(x, y)] = true
				todo.append(Vector2i(x, y))
	while not todo.is_empty():
		var at: Vector2i = todo.pop_back()
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := at + step
			if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and not outside.has(n) and (rows[n.y] as String)[n.x] == ".":
				outside[n] = true
				todo.append(n)
	var out: Array = []
	for y: int in h:
		var row: String = rows[y]
		var line := ""
		for x: int in w:
			var ch := row[x]
			if ch == "K":
				var rim := x == 0 or y == 0 or x == w - 1 or y == h - 1
				for dy: int in [-1, 0, 1]:
					for dx: int in [-1, 0, 1]:
						if outside.has(Vector2i(x + dx, y + dy)):
							rim = true
				if rim:
					ch = "1" if y == 0 or outside.has(Vector2i(x, y - 1)) else "2"
			line += ch
		out.append(line)
	return out


static func add_all() -> void:
	for f: Array in frames():
		Sprites._add(f[0], f[1], f[2])

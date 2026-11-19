class_name Secrets
extends RefCounted
## The game's secrets and easter eggs: the list the Sanctum counts ("SECRETS 3/8") and the words the Ouija board
## answers. Found secrets are kept in Profile.secrets. Pure data.

## [key, where it is (shown once found)].
const ALL: Array = [
	["alcove", "THE TIRED WALL IN THE SANCTUM"],
	["cat", "THE CAT IN THE ALCOVE"],
	["eclipse", "THE MOON OVER THE TITLE"],
	["ghost", "A LIT WINDOW OF THE CASTLE"],
	["abracadabra", "THE OLDEST WORD"],
	["solomon", "THE KING'S NAME"],
	["urn_card", "A CARD IN AN ARENA URN"],
	["ninth", "THE NINTH WISH"],
]

## Words spelled on the Ouija board (the LAN join screen): [reply, secret key ("" for none), crystals once].
const WORDS := {
	"HELLO": ["HELLO, WIZARD. WE HAVE BEEN WAITING.", "", 0],
	"ABRACADABRA": ["THE OLD WORD STILL WORKS.", "abracadabra", 25],
	"SOLOMON": ["THE SEAL HOLDS. MOSTLY.", "solomon", 10],
	"MEOW": ["SOMEWHERE IN THE SANCTUM, A CAT LOOKS UP.", "", 0],
	"LICH": ["DO NOT SAY ITS NAME. IT HEARS.", "", 0],
	"XYZZY": ["NOTHING HAPPENS.", "", 0],
	"HERMES": ["AS ABOVE, SO BELOW.", "", 0],
	"ODIN": ["HE WATCHES WITH THE OTHER EYE.", "", 0],
	"MERLIN": ["HE LIVES BACKWARDS. HE SAYS GOODBYE.", "", 0],
	"42": ["THE ANSWER. BUT WHAT WAS THE QUESTION?", "", 0],
	"666": ["NOT THAT NUMBER. TRY 777.", "", 0],
	"777": ["LUCKY. THE SPIRITS APPROVE.", "", 0],
}
## Every this-many tosses into the Sanctum's wishing well, the well grants a real wish (the "ninth" secret).
const NINTH_WISH := 9
const NINTH_CRYSTALS := 30


static func count() -> int:
	return ALL.size()


static func index_of(k: String) -> int:
	for i: int in range(ALL.size()):
		if ALL[i][0] == k:
			return i
	return -1


## How many of the listed secrets a profile has found.
static func found(prof: Profile) -> int:
	var n := 0
	for row: Array in ALL:
		if prof.has_secret(row[0]):
			n += 1
	return n


## The Ouija board's answer to `word` ([reply, secret key, crystals]), or [] when the spirits stay quiet.
static func answer(word: String) -> Array:
	var w := word.strip_edges().to_upper()
	return WORDS.get(w, [])

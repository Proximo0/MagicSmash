class_name Sanctum
extends RefCounted
## The Sanctum: the tower room a wizard walks around between runs. Pure logic (the view in game/sanctum draws
## it and feeds it input): walking, walls, pots that shatter when walked into, the things to use (the portal,
## the card altar, the reliquary, the music box, the wishing well) and a secret alcove behind a cracked wall.
## It emits events; the view books crystals and cards in the profile and plays the effects.

## The floor a wizard can walk on, and the alcove hidden in the top wall (open once the crack gives way).
const ROOM := Rect2(26, 60, 428, 190)
const ALCOVE := Rect2(390, 30, 44, 30)
## The cracked stretch of the top wall that opens into the alcove, and how long a wizard must push on it.
const CRACK_X := Vector2(396, 428)
const CRACK_PUSH := 1.2
const SPEED := 72.0
const REACH := 20.0 # how near a thing must be to use it
const POT_R := 6.0

## Things to use: [key, position, prompt].
const PORTAL := 0
const ALTAR := 1
const RELIQUARY := 2
const MUSIC := 3
const WELL := 4
const CAT := 5
const SHOPKEEPER := 6
const CARD_READER := 7
const MIRROR := 8
const DEEDS := 9
const THINGS: Array = [
	["portal", Vector2(240, 82), "ENTER THE TOWER"],
	["altar", Vector2(84, 118), "THE CARD ALBUM"],
	["reliquary", Vector2(396, 118), "SEALED DECK  %d CRYSTALS"],
	["music", Vector2(70, 222), "MUSIC BOX"],
	["well", Vector2(410, 222), "WISHING WELL  1 CRYSTAL"],
	["cat", Vector2(420, 44), "PET THE CAT"],
	["shopkeeper", Vector2(118, 176), "TALK TO THE SHOPKEEPER"],
	["card_reader", Vector2(362, 176), "TALK TO THE CARD READER"],
	["mirror", Vector2(176, 114), "LOOK INTO THE MIRROR"],
	["deeds", Vector2(338, 112), "BOOK OF DEEDS"],
]

## Pots along the walls. Broken pots stay broken until the next run is played.
const POTS: Array = [
	Vector2(36, 70), Vector2(50, 70), Vector2(150, 68), Vector2(330, 68), Vector2(444, 70),
	Vector2(36, 160), Vector2(444, 150), Vector2(444, 164), Vector2(150, 242), Vector2(176, 242),
	Vector2(300, 242), Vector2(326, 242),
]
## Bit mask with every pot broken (bit i is POTS[i]).
const ALL_POTS := (1 << 12) - 1
## The note that drifts up from the music box (a character the pixel font can draw).
const MUSIC_NOTE := "#"
## What a pot holds: chance of a monster card (ultra rare), of a crystal cache, of one crystal.
const POT_CARD := 0.001
const POT_CACHE := 0.06
const POT_CACHE_CRYSTALS := 5
const POT_CRYSTAL := 0.35

## A sealed deck draws one card (a long saving goal: the sure way to a card), one the player lacks while any remain;
## the Lich card is half as likely as each other monster card.
const DECK_COST := 1500
const LICH_WEIGHT := 5.0
const CARD_WEIGHT := 10.0
## The wishing well: a crystal in, a fortune out, and now and then the well pays back.
const WELL_PAYOUT := 0.08
const WELL_CRYSTALS := 12
## Crystals in the alcove the first time anyone finds it.
const ALCOVE_CRYSTALS := 50

## Events: [code, a, b].
const EV_POT := 0 # a = pot index, b = [what, amount]: what is "card", "crystals" or ""
const EV_USE := 1 # a = THINGS index
const EV_CRACK := 2 # the wall gave way
const EV_ALCOVE := 3 # stepped into the alcove for the first time this visit

var pos := Vector2(240, 200)
var facing := Vector2.DOWN
var moving := false
var walk_t := 0.0
var broken: Array[bool] = []
var crack_open := false
var crack_t := 0.0
var in_alcove := false
var rng := RandomNumberGenerator.new()
var events: Array = []


## `pots_mask`: the pots that start broken (bit i is POTS[i]; the ones smashed since the last run). `alcove_found`:
## the alcove was found before, so the wall stays open.
func _init(seed_value: int = 0, pots_mask: int = 0, alcove_found: bool = false) -> void:
	rng.seed = seed_value
	for i: int in range(POTS.size()):
		broken.append((pots_mask >> i) & 1 == 1)
	crack_open = alcove_found


func take_events() -> Array:
	var e := events
	events = []
	return e


## Moves the wizard by `move` (a stick direction, length up to 1) for `dt` seconds, breaking pots it walks into.
func step(dt: float, move: Vector2) -> void:
	moving = move.length() > 0.2
	if not moving:
		crack_t = 0.0
		return
	if move.length() > 1.0:
		move = move.normalized()
	facing = move.normalized()
	walk_t += dt * 8.0
	var want := pos + move * SPEED * dt
	pos = _walk(want, move, dt)
	for i: int in range(POTS.size()):
		if not broken[i] and pos.distance_to(POTS[i]) < POT_R + 4.0:
			_break_pot(i)
	var now_in := ALCOVE.has_point(pos)
	if now_in and not in_alcove:
		events.append([EV_ALCOVE, 0, 0])
	in_alcove = now_in


## Where the wizard ends up trying to go to `want`: inside the room, or the alcove once it is open, and pushing on
## the cracked wall long enough opens it.
func _walk(want: Vector2, move: Vector2, dt: float) -> Vector2:
	if _walkable(want):
		crack_t = 0.0
		return want
	var at_crack := pos.y <= ROOM.position.y + 2.0 and pos.x >= CRACK_X.x and pos.x <= CRACK_X.y and move.y < -0.5
	if at_crack and not crack_open:
		crack_t += dt
		if crack_t >= CRACK_PUSH:
			crack_open = true
			events.append([EV_CRACK, 0, 0])
	# Slide along walls: keep whichever axis still fits.
	var slide_x := Vector2(want.x, pos.y)
	if _walkable(slide_x):
		return slide_x
	var slide_y := Vector2(pos.x, want.y)
	if _walkable(slide_y):
		return slide_y
	return pos


func _walkable(p: Vector2) -> bool:
	if ROOM.has_point(p):
		return true
	if not crack_open:
		return false
	# The alcove, and the gap in the wall between it and the room.
	if ALCOVE.has_point(p):
		return true
	return p.x >= CRACK_X.x and p.x <= CRACK_X.y and p.y >= ALCOVE.end.y - 1.0 and p.y <= ROOM.position.y + 1.0


func _break_pot(i: int) -> void:
	broken[i] = true
	var r := rng.randf()
	var what := ""
	var amount := 0
	if r < POT_CARD:
		what = "card"
		amount = roll_card(rng)
	elif r < POT_CARD + POT_CACHE:
		what = "crystals"
		amount = POT_CACHE_CRYSTALS
	elif r < POT_CARD + POT_CACHE + POT_CRYSTAL:
		what = "crystals"
		amount = 1
	events.append([EV_POT, i, [what, amount]])


## The thing within reach of the wizard (THINGS index), or -1. The cat is only within reach from the alcove.
func near_thing() -> int:
	var best := -1
	var bd := REACH
	for i: int in range(THINGS.size()):
		if i == CAT and not in_alcove:
			continue
		var d: float = pos.distance_to(THINGS[i][1])
		if d < bd:
			bd = d
			best = i
	return best


## Uses whatever is in reach. Returns its THINGS index, or -1.
func use() -> int:
	var i := near_thing()
	if i >= 0:
		events.append([EV_USE, i, 0])
	return i


## A card drawn from a sealed deck or found in a pot, with one draw: any monster card by its weight, the Lich card
## rarer. A sealed deck passes the cards the player owns (`owned`, owned_cards): it draws only from the monster
## cards not among them while any remain, by the plain weights once she owns them all. A pot passes none.
static func roll_card(r: RandomNumberGenerator, owned: Array[int] = []) -> int:
	var lacking := false
	for i: int in range(Cards.count()):
		if _card_weight(i) > 0.0 and not owned.has(i):
			lacking = true
	var total := 0.0
	for i: int in range(Cards.count()):
		total += _deck_weight(i, owned, lacking)
	var x := r.randf() * total
	var last := Cards.for_enemy(Bestiary.PRIEST)
	for i: int in range(Cards.count()):
		var wt := _deck_weight(i, owned, lacking)
		if wt <= 0.0:
			continue
		last = i
		x -= wt
		if x < 0.0:
			return i
	return last


## Card `i`'s weight in roll_card: its plain weight (_card_weight), none for an owned card while `lacking` (some
## monster card is not owned).
static func _deck_weight(i: int, owned: Array[int], lacking: bool) -> float:
	if lacking and owned.has(i):
		return 0.0
	return _card_weight(i)


## The card indices the profile owns at least one of (Profile.card_count), in card order: the sealed deck's `owned`.
static func owned_cards(prof: Profile) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(Cards.count()):
		if prof.card_count(i) > 0:
			out.append(i)
	return out


## A card's weight in roll_card: none for a Seal card (no monster drops it), the Lich card far rarer.
static func _card_weight(i: int) -> float:
	if Cards.enemy(i) < 0:
		return 0.0
	return LICH_WEIGHT if Cards.key(i) == "lich" else CARD_WEIGHT


## What toss number `wishes` (counting this one) pays: the ninth wish's 30 crystals only the first time the secret is
## found (`first_ninth`), every other toss the normal roll, so the well stays a loss over time.
static func wish_payout(wishes: int, first_ninth: bool, r: RandomNumberGenerator) -> int:
	if first_ninth and wishes % Secrets.NINTH_WISH == 0:
		return Secrets.NINTH_CRYSTALS
	return wish(r)


## One toss into the wishing well, after the crystal is paid: counts it on the profile and returns {"back": the
## crystals paid, "ninth": whether this toss found the ninth-wish secret}. The 30 crystals are paid only the first
## time (the toss that finds the secret); later ninths are ordinary tosses.
static func toss(prof: Profile, r: RandomNumberGenerator) -> Dictionary:
	prof.wishes += 1
	var ninth := prof.wishes % Secrets.NINTH_WISH == 0 and prof.find_secret("ninth")
	return {"back": wish_payout(prof.wishes, ninth, r), "ninth": ninth}


## A toss into the wishing well: the crystals it pays back (0 most of the time).
static func wish(r: RandomNumberGenerator) -> int:
	return WELL_CRYSTALS if r.randf() < WELL_PAYOUT else 0

## What the wishing well says back. Old proverbs, myth and a little tower gossip.
const FORTUNES := [
	"THE TOWER REMEMBERS EVERY WIZARD.",
	"WHAT HERMES HID, PATIENCE FINDS.",
	"THE NINTH WAVE IS THE STRONGEST.",
	"A LICH FEARS ONLY BEING FORGOTTEN.",
	"SOLOMON SEALED SEVENTY-TWO. NOT ALL.",
	"LOOK UP. SOME WALLS ARE TIRED.",
	"THE CAT KNOWS. THE CAT ALWAYS KNOWS.",
	"FORTUNE FAVOURS THE SECOND TRY.",
	"ODIN GAVE AN EYE. YOU GAVE A CRYSTAL.",
	"THE ORACLE SAYS: DODGE LEFT.",
	"WHAT IS BROKEN MAY HOLD A CARD.",
	"THE MOON IS LISTENING TONIGHT.",
]


static func fortune(r: RandomNumberGenerator) -> String:
	return FORTUNES[r.randi() % FORTUNES.size()]

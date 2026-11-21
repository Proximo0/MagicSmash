class_name BossGhostwriter
extends RefCounted
## THE GHOST WRITER (act II, 10:00): a planchette that spells each attack first. A letter every LETTER s
## (LETTER_FAST in phase 2); the attack's rows appear with the first letter and land WORD_PAD s after the last
## (warn = spelling + WORD_PAD). Between words she glides to KEEP_MIN..KEEP_MAX px from the party. Phase 1: FIRE,
## NAME, SHELF, ERRATA, NAME. At PHASE_AT she turns; phase 2: NAME+FIRE, SHELF+NAME (no rest between the pair),
## GOODBYE, ERRATA, and NAME calls two wizards in a party of 3 or 4. The header carries the word, the letters shown and
## who is named (encode/word_of/named), boss_meter GOODBYE's check. Static helpers; the first argument is the World.
## Enemy.state is the step, Enemy.count the word index (ORDER entry x 4 + the word within it), Enemy.timer the
## letter clock, Enemy.timer2 the time to the word's end (or the trail and ring clock), Enemy.dir where she glides,
## Enemy.enter_dir.x her health as GOODBYE began (then the rings fired), Enemy.enter_dir.y turns made + POTION_GIVEN
## + NAME_STEP x the wizards named so far.

enum { GLIDE, SPELL, RUN, BYE, STAGGER, RINGS }
enum { WORD_NONE, WORD_FIRE, WORD_NAME, WORD_SHELF, WORD_ERRATA, WORD_GOODBYE }
## The spelled words by id; NAME spells the named wizards' names instead.
const WORDS: Array[String] = ["", "FIRE", "NAME", "SHELF", "ERRATA", "GOODBYE"]
## Between two names.
const NAME_JOIN := "&"
## Header boss_arg = word + SLOT_MUL x (first named slot + 1) + SLOT_MUL^2 x (second + 1).
const SLOT_MUL := 8
const ORDER_1: Array = [[WORD_FIRE], [WORD_NAME], [WORD_SHELF], [WORD_ERRATA], [WORD_NAME]]
const ORDER_2: Array = [[WORD_NAME, WORD_FIRE], [WORD_SHELF, WORD_NAME], [WORD_GOODBYE], [WORD_ERRATA]]
const WORD_SLOTS := 4 # Enemy.count steps per ORDER entry
const POTION_GIVEN := 2.0
const NAME_STEP := 4.0

## Its attacks as [state, warn s, hazard kind, r]; the warn is the shortest spelling (4 letters at LETTER_FAST) plus
## WORD_PAD, or the row's own. GOODBYE is shots (kind -1) after 7 letters at BYE_LETTER.
const ATTACKS: Array = [
	[SPELL, 4 * 0.24 + 0.3, Hazards.LANE, 12.0], # F-I-R-E
	[RUN, 0.5, Hazards.FLAME, 10.0], # behind her run (laid with none: add_hazard raises it to min_warn)
	[SPELL, 4 * 0.24 + 0.3, Hazards.BLAST, 30.0], # a NAME (AMBER is the shortest), locks NAME_LOCK s before
	[SPELL, 0.67, Hazards.FIRE, 22.0], # what a NAME leaves (raised like the trail)
	[SPELL, 5 * 0.24 + 0.3, Hazards.FLAME, 38.0], # S-H-E-L-F, odd lanes
	[SPELL, 1.3, Hazards.FLAME, 38.0], # SHELF's even lanes (Bosses.SHELF_EVEN_WARN)
	[SPELL, 6 * 0.24 + 0.3, Hazards.FALL, 10.0], # E-R-R-A-T-A
	[BYE, 7 * 0.5, -1, 0.0], # G-O-O-D-B-Y-E
]

const LETTER := 0.32
const LETTER_FAST := 0.24
const BYE_LETTER := 0.5
const WORD_PAD := 0.3
const GAP_1 := 1.2
const GAP_2 := 0.9
const KEEP_MIN := 70.0
const KEEP_MAX := 110.0
const TURN_S := 2.0
const TRAIL_STEP := 0.25

const FIRE_HW := 12.0
const FIRE_SPEED := 190.0
const FIRE_FLAME_HW := 10.0
const FIRE_HOT := 5.0
const CONTACT_RUN := 2

const NAME_R := 30.0
const NAME_LOCK := 0.9
const TWO_NAMES_AT := 3 # wizards in the party

const SHELF_LANES := 10
const SHELF_HW := 38.0

const ERRATA_TOMES := 6
const ERRATA_TOMES_BIG := 8 # with TWO_NAMES_AT wizards or more
const ERRATA_R := 10.0
const ERRATA_RING := 90.0

const BYE_SHARE := 0.06 # of her health, dealt during GOODBYE, stops it
const BYE_STOP := 4 # letters left showing: G-O-O-D
const VULN := 1.5
const STAGGER_S := 3.0
const BYE_RINGS := 3
const BYE_RING_N := 16
const BYE_SPEED := 80.0
const BYE_EVERY := 0.5

const HOT_BLAST := 0.15


static func think(w: World, e: World.Enemy, dt: float, _tgt: World.Player, _dirv: Vector2, _dist: float) -> Vector2:
	if int(e.enter_dir.y) & 1 == 0 and Bosses.phase(e.type, e.hp / e.maxhp) >= 1:
		_turn(w, e)
		return Vector2.ZERO
	e.contact = CONTACT_RUN if e.state == RUN else 0
	match e.state:
		GLIDE:
			if e.dir == Vector2.ZERO:
				_pick_spot(w, e)
			Bosses.glide(e, e.dir, e.spd, dt)
			e.timer -= dt
			if e.timer <= 0.0:
				_next(w, e)
		SPELL, BYE:
			_letters(w, e, dt)
			if e.state == BYE:
				w.boss_meter = clampf((e.enter_dir.x - e.hp) / (BYE_SHARE * e.maxhp), 0.0, 1.0)
				if w.boss_meter >= 1.0:
					_stagger(w, e)
					return Vector2.ZERO
			e.timer2 -= dt
			if e.timer2 <= 0.0:
				_word_done(w, e)
		RUN:
			var to := e.dir
			var along := (to - e.pos).normalized()
			var there := Bosses.glide(e, to, FIRE_SPEED, dt)
			e.timer2 += dt
			if e.timer2 >= TRAIL_STEP or there:
				Bosses.trail(w, e, along, FIRE_SPEED, e.timer2, FIRE_FLAME_HW, FIRE_HOT)
				e.timer2 = 0.0
			if there:
				_after(w, e)
		STAGGER:
			e.timer -= dt
			if e.timer <= 0.0:
				w.boss_meter = 0.0
				_after(w, e)
		RINGS:
			e.timer2 -= dt
			if e.timer2 <= 0.0:
				Bosses.ring(w, World.ES_SKULL, e.pos, BYE_RING_N, BYE_SPEED, e.enter_dir.x * PI / BYE_RING_N)
				e.enter_dir.x += 1.0
				e.timer2 += BYE_EVERY
				if e.enter_dir.x >= BYE_RINGS:
					_after(w, e)
	return Vector2.ZERO


## GOODBYE's stand and stagger take VULN x (Brains.filter_damage, through Bestiary.BRAINS).
static func filter_damage(_w: World, e: World.Enemy, dmg: float, _knock: Vector2, _sure: bool) -> float:
	return dmg * VULN if e.state == BYE or e.state == STAGGER else dmg


static func on_death(_w: World, _e: World.Enemy, _slot: int) -> bool:
	return false


# ============================================================== HEADER ===

static func encode(word: int, s1: int = -1, s2: int = -1) -> int:
	return word + SLOT_MUL * (s1 + 1) + SLOT_MUL * SLOT_MUL * (s2 + 1)


static func word_of(arg: int) -> int:
	return arg % SLOT_MUL


## The named slots in a header arg (none, one or two).
static func named(arg: int) -> Array[int]:
	var out: Array[int] = []
	for k: int in [1, SLOT_MUL]:
		var s := (arg / SLOT_MUL / k) % SLOT_MUL - 1
		if s >= 0:
			out.append(s)
	return out


## The whole word a header arg spells; `names` maps a slot to its wizard's name (NAME spells them).
static func word_text(arg: int, names: Dictionary) -> String:
	var word := word_of(arg)
	if word != WORD_NAME:
		return WORDS[clampi(word, 0, WORDS.size() - 1)]
	var parts: Array[String] = []
	for s: int in named(arg):
		parts.append(str(names.get(s, "?")))
	return NAME_JOIN.join(parts)


## Slot -> wizard name for every wizard in World `w`.
static func names_in(w: World) -> Dictionary:
	var out := {}
	for p: World.Player in w.players.values():
		out[p.slot] = Wizards.wizard_name(p.wizard)
	return out


# ============================================================== WORDS ===

static func _letter_s(e: World.Enemy, word: int) -> float:
	if word == WORD_GOODBYE:
		return BYE_LETTER
	return LETTER_FAST if int(e.enter_dir.y) & 1 else LETTER


## Shows the next letter each letter time, up to the word's length.
static func _letters(w: World, e: World.Enemy, dt: float) -> void:
	var n := word_text(w.boss_arg, names_in(w)).length()
	e.timer -= dt
	while e.timer <= 0.0 and int(w.boss_t) < n:
		w.boss_t += 1.0
		e.timer += _letter_s(e, word_of(w.boss_arg))
	if int(w.boss_t) >= n:
		e.timer = 0.0


## The next word of the order: the next of the pair, or the next entry.
static func _next(w: World, e: World.Enemy) -> void:
	var order: Array = ORDER_2 if int(e.enter_dir.y) & 1 else ORDER_1
	var entry: Array = order[(int(e.count) / WORD_SLOTS) % order.size()]
	var sub := int(e.count) % WORD_SLOTS
	spell(w, e, int(entry[mini(sub, entry.size() - 1)]))


## After a word's action: the pair's second word at once, else glide for the gap.
static func _after(w: World, e: World.Enemy) -> void:
	var order: Array = ORDER_2 if int(e.enter_dir.y) & 1 else ORDER_1
	var entry: Array = order[(int(e.count) / WORD_SLOTS) % order.size()]
	var sub := int(e.count) % WORD_SLOTS
	if sub + 1 < entry.size():
		e.count += 1.0
		spell(w, e, int(entry[sub + 1]))
		return
	e.count = float((int(e.count) / WORD_SLOTS + 1) * WORD_SLOTS)
	w.boss_arg = 0
	w.boss_t = 0.0
	e.state = GLIDE
	e.timer = GAP_2 if int(e.enter_dir.y) & 1 else GAP_1
	_pick_spot(w, e)


## The word's letters are all out (plus WORD_PAD for FIRE and GOODBYE, whose rows or shots land then).
static func _word_done(w: World, e: World.Enemy) -> void:
	match word_of(w.boss_arg):
		WORD_FIRE:
			e.state = RUN
			e.timer2 = 0.0
		WORD_GOODBYE:
			e.state = RINGS
			e.timer2 = 0.0
			e.enter_dir.x = 0.0
		_:
			_after(w, e)


## Starts spelling `word`: the header shows its first letter and its rows go down now.
static func spell(w: World, e: World.Enemy, word: int) -> void:
	var lt := _letter_s(e, word)
	var slots: Array[int] = []
	if word == WORD_NAME:
		slots = name_targets(w, e)
		if slots.is_empty():
			_after(w, e)
			return
	w.boss_arg = encode(word, slots[0] if slots.size() > 0 else -1, slots[1] if slots.size() > 1 else -1)
	w.boss_t = 1.0
	var n := word_text(w.boss_arg, names_in(w)).length()
	var warn := n * lt + WORD_PAD
	e.state = SPELL
	e.timer = lt
	e.timer2 = n * lt
	match word:
		WORD_FIRE:
			if not _fire_lane(w, e, warn):
				_after(w, e) # the floor is full: no unwarned charge
				return
			e.timer2 = warn
		WORD_NAME:
			cast_names(w, e, slots, warn)
			e.enter_dir.y += NAME_STEP * slots.size() # the next NAME calls the next wizards
		WORD_SHELF:
			for i: int in range(0, SHELF_LANES, 2):
				var x := G.ARENA.position.x + SHELF_HW + i * Bosses.SHELF_STEP
				var h := w.add_hazard(Hazards.FLAME, Vector2(x, G.ARENA.position.y), Vector2(x, G.ARENA.end.y), SHELF_HW, warn,
					Bosses.SHELF_HOT, -1, e.id)
				if h != null:
					h.aux = Bosses.AUX_SHELF
		WORD_ERRATA:
			var n_tomes := ERRATA_TOMES_BIG if w.players.size() >= TWO_NAMES_AT else ERRATA_TOMES
			var c := w.party_center()
			var off := w.rng.randf() * TAU
			for i: int in n_tomes:
				var at := Bosses.inside(c + Vector2.from_angle(off + TAU * i / n_tomes) * ERRATA_RING)
				var h := w.add_hazard(Hazards.FALL, at, at, ERRATA_R, warn, HOT_BLAST, -1, e.id)
				if h != null:
					h.aux = World.TOME
		WORD_GOODBYE:
			e.state = BYE
			e.timer2 = warn
			e.enter_dir.x = e.hp
			w.boss_meter = 0.0


## Who NAME calls: the living wizards in slot order, taking turns (each NAME calls the next ones); two in a party of
## TWO_NAMES_AT or more in phase 2. `turn` picks whose turn it is (default: how many she has named so far).
static func name_targets(w: World, e: World.Enemy, turn: int = -1) -> Array[int]:
	var live: Array[int] = []
	for p: World.Player in w.players.values():
		if p.alive:
			live.append(p.slot)
	live.sort()
	var out: Array[int] = []
	if live.is_empty():
		return out
	var two := int(e.enter_dir.y) & 1 and w.players.size() >= TWO_NAMES_AT and live.size() >= 2
	var at := (int(e.enter_dir.y / NAME_STEP) if turn < 0 else turn) % live.size()
	out.append(live[at])
	if two:
		out.append(live[(at + 1) % live.size()])
	return out


## A BLAST over each named wizard that follows them, locks NAME_LOCK s before it lands and leaves FIRE.
static func cast_names(w: World, e: World.Enemy, slots: Array[int], warn: float) -> void:
	for s: int in slots:
		var p: World.Player = w.players.get(s)
		if p == null:
			continue
		var h := w.add_hazard(Hazards.BLAST, p.pos, p.pos, NAME_R, warn, HOT_BLAST, -1, e.id)
		if h != null:
			h.follow = s
			h.lock = NAME_LOCK
			h.aux = Bosses.AUX_FIRE


## F-I-R-E: a lane wall to wall through her and the wizard farthest from her; she runs it once it is spelled.
## False when the floor is full and the lane could not be laid.
static func _fire_lane(w: World, e: World.Enemy, warn: float) -> bool:
	var far := Bosses.farthest_from(w, e.pos)
	var dir := (far.pos - e.pos).normalized() if far != null and far.pos.distance_to(e.pos) > 1.0 else Vector2.RIGHT
	var back := Bosses.to_wall(e.pos, -dir, e.r)
	var ahead := Bosses.to_wall(e.pos, dir, e.r)
	if w.add_hazard(Hazards.LANE, back, ahead, FIRE_HW, warn, e.pos.distance_to(ahead) / FIRE_SPEED + WORD_PAD, -1, e.id) == null:
		return false
	e.dir = ahead
	return true


## Deal BYE_SHARE of her health during GOODBYE and she stops at G-O-O-D and staggers; the first time, a potion.
static func _stagger(w: World, e: World.Enemy) -> void:
	w.boss_t = BYE_STOP
	e.state = STAGGER
	e.timer = STAGGER_S
	if int(e.enter_dir.y) & int(POTION_GIVEN) == 0:
		e.enter_dir.y += POTION_GIVEN
		if w.no_potions <= 0.0: # THE HIEROPHANT
			WorldDrops._drop(w, World.PK_POTION, e.pos, Vector2(0, 40))


## Where she glides between words: KEEP_MIN..KEEP_MAX px from the party's middle, on her side.
static func _pick_spot(w: World, e: World.Enemy) -> void:
	var c := w.party_center()
	var off := (e.pos - c).normalized() if e.pos.distance_to(c) > 1.0 else Vector2.UP
	e.dir = Bosses.inside(c + off * w.rng.randf_range(KEEP_MIN, KEEP_MAX))


## Her turn at PHASE_AT: the word under way stops and she starts phase 2's order.
static func _turn(w: World, e: World.Enemy) -> void:
	Bosses.drop_warnings(w, e)
	e.enter_dir.y += 1.0
	e.count = 0.0
	w.boss_arg = 0
	w.boss_t = 0.0
	w.boss_meter = 0.0
	e.state = GLIDE
	e.timer = GAP_2
	e.contact = 0
	w.phase_turn(e, TURN_S)

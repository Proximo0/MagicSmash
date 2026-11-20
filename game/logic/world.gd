class_name World
extends RefCounted
## The authoritative game simulation. Runs on the host (or offline) only.
## It knows nothing about drawing: it emits events (for effects and sound)
## and produces compact snapshots that both the host and clients render.

# Enemy types
const GOBLIN := 0
const SKELETON := 1
const SLIME := 2
const MSLIME := 3
const BAT := 4
const ORC := 5
const MAGE := 6
const LICH := 7
## The later acts' horde (appended so snapshot type ids stay put).
const WRAITH := 8 # drifts through the crowd and phases out: spells pass through it while it is faded
const TOME := 9 # a cursed grimoire that circles a wizard and dashes through
const GARGOYLE := 10 # sits as stone (hard to hurt), then swoops
const PRIEST := 11 # the bone priest: keeps its distance and raises skeletons

# Spells
const SP_ARCANE := 0
const SP_FIRE := 1
const SP_FROST := 2
const SP_STORM := 3
const SP_STAR := 4
const SP_RUNE := 5

# Pickups
const PK_COIN := 0
const PK_GEM := 1
const PK_POTION := 2
const PK_TOME_FIRE := 3
const PK_TOME_FROST := 4
const PK_TOME_STORM := 5
const PK_TOME_STAR := 6
const PK_BOOTS := 7
const PK_ORBIT := 8
const PK_XP := 9
const PK_CHEST := 10
const PK_TOME_RUNE := 11 # after the chest, so the older pickup ids stay put
const PK_CARD := 12 # a monster card (value: Cards index), kept in the collection between runs
const PK_CHEST_RARE := 13 # a blue chest any kill can drop: opens rare or better
const PK_CHEST_ULTRA := 14 # a prismatic chest, far rarer: opens legendary or better
## Every spell tome, in World.SP_* order from the fireball (arcane has no tome).
const TOMES := [PK_TOME_FIRE, PK_TOME_FROST, PK_TOME_STORM, PK_TOME_STAR, PK_TOME_RUNE]

# Enemy shot kinds
const ES_ARROW := 0
const ES_ORB := 1
const ES_SKULL := 2

# Phases
const PH_INTRO := 0
const PH_FIGHT := 1
const PH_GAMEOVER := 3

# Events: [code, x, y, a, b]
const EV_CAST := 0
const EV_HIT := 1
const EV_DIE := 2
const EV_EXPLODE := 3
const EV_ZAP := 4
const EV_NOVA := 5
const EV_PICKUP := 6
const EV_HURT := 7
const EV_PDIE := 8
const EV_DOOR := 9
const EV_ESHOT := 10
const EV_SPLIT := 11
const EV_TELE := 12
const EV_CHARGE := 13
const EV_WAVE := 14
const EV_BOSS := 16
const EV_COMBO := 17
const EV_SPAWN := 18
const EV_POWERUP := 19
const EV_BOSSDIE := 20
const EV_GAMEOVER := 21
const EV_FROST := 22
const EV_SCORE := 23
const EV_LEVELUP := 24
const EV_PICK := 25
const EV_ELITE := 26
const EV_RIFT := 27
const EV_CHEST := 28
const EV_WARD := 29
const EV_SHRINE_UP := 30 # a shrine appeared: a = kind
const EV_SHRINE := 31 # a wizard paid a shrine: a = slot, b = kind * 16 + outcome; the reel starts
const EV_GAMBLE := 32 # the reel ended and the outcome applies: a = slot, b = kind * 16 + outcome
const EV_VICTORY := 33 # the Archlich fell and the run is won: a = slot of the wizard who slew it
const EV_RESULTS := 34 # just before EV_GAMEOVER: a = the run's Results.to_dict() for the results screen
const EV_RAISE := 35 # a bone priest raises the dead: at its position, a = how many
const EV_OMEN := 36 # a horde omen begins (Lore.OMENS): at its centre, a = omen index, b = ring radius (0: from the doors)
const EV_RUNE := 37 # a rune circle is inscribed: at its centre, a = radius, b = slot + 8 when evolved
const EV_CARD := 38 # a wizard picked up a monster card: a = Cards index, b = slot (+ 8 if it came from an urn)
const EV_URN := 39 # an urn shattered: at its position, a = what fell out (URN_* below)
const EV_LULL := 40 # a Lich fell and the lull begins: at the party's centre, a = its seconds
## Wave 2 events; nothing emits them yet.
const EV_DOWN := 41 # a wizard fell: at its position, a = slot
const EV_REVIVE := 42 # a fallen wizard is back up: at its position, a = slot, b = the reviver's slot (-1: by itself)
const EV_CALL := 43 # a wizard calls for help: at its position, a = slot
const EV_REDRAW := 44 # a wizard redrew the hand: a = slot
const EV_BANISH := 45 # a wizard banished a card: a = slot, b = Upgrades index
const EV_FATE := 46 # a fate is drawn: a = fate, b = slot
const EV_SLOTS := 47 # the slot cap changed: a = spell slots, b = passive slots
const EV_TALK := 48 # Morvane speaks: a = line
## What an urn held. A card from an urn is a PK_CARD whose value is the Cards index + URN_CARD.
const URN_DUST := 0
const URN_COIN := 1
const URN_GEM := 2
const URN_POTION := 3
const URN_CHEST := 4
const URN_CARD_DROP := 5
const URN_CARD := 100
const URN_R := 5.0

#                  hp    spd  r   score contact
const STATS := [
	[2.0,  58.0, 5.0, 50,  1],   # goblin
	[3.0,  40.0, 5.0, 100, 1],   # skeleton
	[5.0,  34.0, 6.0, 80,  1],   # slime
	[1.5,  52.0, 4.0, 20,  1],   # mini slime
	[1.0,  88.0, 5.0, 60,  1],   # bat
	[18.0, 30.0, 8.0, 300, 2],   # orc
	[6.0,  22.0, 5.0, 250, 1],   # dark mage
	[380.0, 26.0, 14.0, 5000, 2],# lich
	[4.0,  44.0, 5.0, 120, 1],   # wraith
	[3.0,  64.0, 5.0, 90,  1],   # cursed tome
	[12.0, 30.0, 7.0, 260, 1],   # gargoyle
	[9.0,  24.0, 5.0, 300, 1],   # bone priest
]

## The player row in snapshot()["p"], final for waves 2 and 3: read it only through these P_* indices.
## Choices: 3 x (offered Upgrades index or -1, the level it would reach). Spells: P_SLOTS x (SPELL row or -1,
## level; Spells.MAX_LEVEL + 1 = evolved), in the order taken. Passives: P_SLOTS x (PASSIVE row or -1, level),
## in the order taken. xp, xp needed and level are the party's (the same for every wizard); draws are queued
## level-up offers plus 1 while the wizard holds cards; down_left is s (-1 = a ritual only); race, class, look and
## class level are reserved ints, 0 until their job lands.
const P_SLOT := 0
const P_X := 1
const P_Y := 2
const P_AIM_X := 3
const P_AIM_Y := 4
const P_HP := 5
const P_LIVES := 6
const P_ALIVE := 7
const P_INVULN := 8
const P_SPELL := 9 # the main spell (colours the staff)
const P_WIZARD := 10 # the Wizards index picked
const P_BOMBS := 11
const P_SCORE := 12
const P_COMBO := 13
const P_HASTE := 14
const P_ORBIT := 15
const P_ORBIT_ANG := 16
const P_FLASH := 17
const P_MOVING := 18
const P_XP := 19
const P_XP_NEED := 20
const P_LEVEL := 21
const P_OFFER := 22
const P_CHOICES := 23
const P_CHOICE_COUNT := 3
const P_SPELLS := P_CHOICES + P_CHOICE_COUNT * 2
const P_SLOTS := 6 # every spell and passive of today; a slot cap (job E) only ever uses the first few
const P_PASSIVES := P_SPELLS + P_SLOTS * 2
const P_GOLD := P_PASSIVES + P_SLOTS * 2
const P_MAX_HP := P_GOLD + 1
const P_DRAWS := P_GOLD + 2
const P_REDRAWS := P_GOLD + 3
const P_BANISHES := P_GOLD + 4
const P_DOWN := P_GOLD + 5
const P_DOWN_LEFT := P_GOLD + 6
const P_REVIVE := P_GOLD + 7
const P_AI := P_GOLD + 8
const P_TRAIT_A := P_GOLD + 9
const P_TRAIT_B := P_GOLD + 10
const P_RACE := P_GOLD + 11 # reserved for races and classes: 0 until a later job fills them
const P_CLASS := P_GOLD + 12
const P_LOOK := P_GOLD + 13 # a packed look: skin, hair, style
const P_CLASS_LEVEL := P_GOLD + 14
const P_FLOATS := P_GOLD + 15
const BASE_HEARTS := 5

## The header, snapshot()["w"]: minute, phase, phase s, boss health fraction (-1: none), the four doors' open s,
## run s, 1 if the boss is the Archlich, lull s left, seal level, slot cap (spells, passives).
const W_WAVE := 0
const W_PHASE := 1
const W_PHASE_T := 2
const W_BOSS := 3
const W_DOORS := 4
const W_TIME := 8
const W_FINAL := 9
const W_LULL := 10
const W_SEAL := 11
const W_CAP_SPELLS := 12
const W_CAP_PASSIVES := 13
const W_FLOATS := 14

## Floats per rune circle in snapshot()["r"]: x, y, radius, age s, lifetime s, owner slot, evolved, kind.
const RUNE_FLOATS := 8
const R_KIND := 7

## Floats per enemy in snapshot()["e"]: id, type, x, y, flash, state, hp fraction, slow, rank (1 elite, 2 Archlich),
## status bits.
const E_ID := 0
const E_TYPE := 1
const E_X := 2
const E_Y := 3
const E_FLASH := 4
const E_STATE := 5
const E_HP := 6
const E_SLOW := 7
const E_RANK := 8
const E_STATUS := 9
const ENEMY_FLOATS := 10

## Floats per spell object in snapshot()["o"]: kind, owner, x, y, a, b, t, evolved. None exist yet.
const O_FLOATS := 8

## The horde: [type, budget cost, unlocks after this many seconds of fighting, weight, group min, group max,
## extra group max per minute].
const HORDE := [
	[GOBLIN,   1.0, 0.0,   2, 6, 10, 1],
	[BAT,      1.0, 0.0,   1, 4, 8,  0],
	[SLIME,    3.0, 30.0,  1, 2, 4,  0],
	[SKELETON, 3.0, 60.0,  1, 2, 5,  0],
	[ORC,      9.0, 150.0, 1, 1, 1,  0],
	[MAGE,     6.0, 210.0, 1, 1, 2,  0],
	[WRAITH,   2.0, 240.0, 1, 2, 4,  0],
	[TOME,     2.0, 300.0, 2, 3, 6,  0],
	[PRIEST,   8.0, 420.0, 1, 1, 1,  0],
	[GARGOYLE, 7.0, 600.0, 1, 1, 2,  0],
]
## How long a wraith stays solid and faded, s; how long a gargoyle sits as stone and swoops, s; and the share of
## damage stone takes.
const WRAITH_SOLID := 1.6
const WRAITH_FADED := 0.9
const GARGOYLE_PERCH := 2.2
const GARGOYLE_SWOOP := 1.1
const STONE_DAMAGE := 0.25
## Seconds between a bone priest's raisings and how many skeletons rise each time.
const PRIEST_RAISE := 6.0
const PRIEST_RAISED := 2
## Omens: one set-piece horde event in the middle of each act. [wave, enemy type, count, ring?]. A ring forms
## around the party and closes in; otherwise the group pours from every door at once.
const OMENS := [
	[4, SKELETON, 14, true],
	[9, TOME, 20, false],
	[14, WRAITH, 24, true],
]
## Seconds between an omen's warning and the horde arriving; the ring's radius around the party, px.
const OMEN_WARN := 2.0
const OMEN_RING_R := 105.0
## Seconds between enemies of one group walking through a door.
const DOOR_STAGGER := 0.1
## Elite multipliers on score and XP, and what an elite drops.
const ELITE_REWARD := 5
## Score multiplier for slaying the Archlich, and the HP fraction under which it rages (the Lich rages at half).
const FINAL_REWARD := 4
const FINAL_RAGE := 0.66
const ELITE_GEMS := 6

## XP a gem dropped by each enemy type is worth (same order as STATS).
const XP_VALUES := [1, 2, 2, 1, 1, 5, 4, 25, 2, 2, 4, 5]

## The four doors, mid-wall on each side of G.ARENA (top, bottom, left, right).
const DOORS := [Vector2(400, 30), Vector2(400, 446), Vector2(12, 238), Vector2(788, 238)]
const DOOR_DIRS := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]

const COMBO_CALLS := {10: "SMASHING!", 25: "ARCANE CARNAGE!", 50: "WIZARDLY!", 100: "TOTAL SORCERY!", 200: "LEGENDARY!"}

const Player = WorldEntities.Player
const Enemy = WorldEntities.Enemy
const Shot = WorldEntities.Shot
const Rune = WorldEntities.Rune
const EShot = WorldEntities.EShot
const Shrine = WorldEntities.Shrine
const Pickup = WorldEntities.Pickup

var players := {} # slot -> Player
var enemies: Array[Enemy] = []
var shots: Array[Shot] = []
var runes: Array[Rune] = []
var eshots: Array[EShot] = []
var pickups: Array[Pickup] = []
var cards_found: Array[int] = [] # Cards indices picked up this run, in order
var urns: Array[Vector2] = [] # breakable urns along the walls (shots or a wizard walking in break them)
var shrines: Array[Shrine] = []
var shrine_t := 0.0
var team_shrine_t := 0.0
## Meta unlock bonuses for this run (Profile.bonuses through apply_meta); all zero by default.
var meta_damage := 0.0
var meta_xp := 0.0
var meta_gold := 0.0
var meta_luck := 0
## The run's difficulty (apply_seal): SEAL_EASY (-1) easy, 0 normal, 1 hard, 2..SEAL_MAX the Seals I to VIII.
const SEAL_EASY := -1
const SEAL_MAX := 9
var seal := 0
## Slots each wizard has: (spells, passives). Upgrades.UNCAPPED until the slots job lands.
var slots := Upgrades.UNCAPPED
## The party's shared level and XP pool; every Player.level follows party_level.
var party_level := 1
var party_xp := 0
## Seconds left of the lull after a Lich falls (nothing spawns, XP flies to the party); 0 when there is none.
var lull_left := 0.0
var liches_slain := 0
## True once the Archlich has fallen; the results screen follows after victory_t runs out.
var won := false
var victory_t := 0.0
var _final_called := false
## Stats and best moments for the results screen.
var record: Results
## Statistics only: the damage source being resolved (a spell, Results.SRC_*), so record.source_damage can
## split damage by spell. Never read by gameplay and not in state_hash().
var stat_src := -1
var _gambles: Array = [] # paid shrines waiting for their reel: {t, slot, kind, outcome, stake, pos}
var events: Array = []
var rng := RandomNumberGenerator.new()
var next_id := 1
## Minute of the run, from 1. Enemy scaling and the Lich's visits follow it.
var wave := 1
var phase := PH_INTRO
var phase_t := 2.5
## Seconds of fighting so far (the run clock).
var wave_time := 0.0
var spawn_queue: Array = []
var horde_budget := 0.0
var elite_t := 0.0
var _next_group: Array = [] # [type, count] the horde is saving its budget for
var _tick := 0
var door_open := [0.0, 0.0, 0.0, 0.0]
var boss: Enemy = null
var powerup_timer := 8.0
var time := 0.0
var _grid := {}
const CELL := 32.0
const _NO_CELL: Array = []
## The wizards as a typed list, refreshed every step: `players.values()` builds a new untyped array on every call,
## and the enemy update asked for it twice per enemy (5% of a whole step at the enemy cap).
var _plist: Array[Player] = []
## How near the nearest wizard must be at the start of an enemy's update for the contact test to run at all: the
## 5 px touch distance plus far more than any enemy travels in one step (the fastest dash is 4 px).
const CONTACT_REACH := 45.0
## Gameplay numbers. Tuning.shared() unless a test or sim passes its own.
var tune: Tuning

## seed_value 0 picks a random seed (normal play); tests, sims and replays pass a fixed one. `wizards` maps a
## slot to the Wizards index its player picked in the lobby; a slot not in it plays the wizard of its own colour.
## `seats` maps a slot to its roster extras (Net.seat_builds(): ai, race, cls, look, cls_level), copied onto the
## Player untouched; nothing reads them yet.
func _init(slots: Array, seed_value: int = 0, tuning: Tuning = null, wizards: Dictionary = {}, seats: Dictionary = {}) -> void:
	tune = tuning if tuning != null else Tuning.shared()
	horde_budget = tune.horde_start_budget
	shrine_t = tune.shrine_first
	team_shrine_t = tune.team_shrine_first
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	var c := G.ARENA.get_center()
	var offs := [Vector2(-24, -14), Vector2(24, -14), Vector2(-24, 14), Vector2(24, 14)]
	for s in slots:
		var p := Player.new()
		p.slot = s
		p.pos = c + offs[s % 4]
		p.wizard = clampi(int(wizards.get(s, s % Wizards.count())), 0, Wizards.count() - 1)
		var seat: Dictionary = seats.get(s, {})
		p.ai = bool(seat.get("ai", false))
		p.race = int(seat.get("race", 0))
		p.cls = int(seat.get("cls", 0))
		p.look = int(seat.get("look", 0))
		p.cls_level = int(seat.get("cls_level", 0))
		p.cds.resize(Spells.COUNT)
		p.cds.fill(0.0)
		p.upgrades[Upgrades.weapon_entry(Wizards.start_spell(p.wizard))] = 1
		WorldCasting._refresh_spell(self, p)
		players[s] = p
	record = Results.new(slots)
	events.append([EV_WAVE, 0, 0, wave, 0])

## Starts the run with the host's meta unlocks (Save.run_bonuses()): extra hearts and novas for every wizard,
## and damage, XP, gold and chest luck bonuses. Call once, before the first step.
func apply_meta(b: Dictionary) -> void:
	meta_damage = float(b.get("damage", 0.0))
	meta_xp = float(b.get("xp", 0.0))
	meta_gold = float(b.get("gold", 0.0))
	meta_luck = int(b.get("luck", 0.0))
	var armor: Array = b.get("armor", [])
	for p: Player in players.values():
		p.max_hp += int(b.get("hearts", 0.0))
		for st: int in range(mini(armor.size(), Loot.STAT_COUNT)):
			p.armor[st] = minf(float(p.armor[st]) + float(armor[st]), float(Loot.STAT_CAPS[st]))
		p.max_hp += int(float(armor[Loot.ST_VIGOR])) if armor.size() > Loot.ST_VIGOR else 0
		p.hp = p.max_hp
		p.bombs += int(b.get("novas", 0.0))

## Starts the run at a difficulty level (Net.seal, SEAL_EASY..SEAL_MAX). Call once, after apply_meta. A stub: it
## records the level and changes nothing else yet (level 0 never will).
func apply_seal(level: int) -> void:
	seal = clampi(level, SEAL_EASY, SEAL_MAX)

func slot_cap() -> Vector2i:
	return slots

## The wizards human players control, in slot order (apprentices left out).
func humans() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in players.values():
		if not p.ai:
			out.append(p)
	return out

## The fallen waiting for a revive: [slot, x, y, revive 0..1, down_left s] each. Empty until revives land.
func graves() -> Array:
	var out: Array = []
	for p: Player in players.values():
		if p.down:
			out.append([p.slot, p.pos.x, p.pos.y, p.revive, p.down_left])
	return out

## True if a wizard who is not standing can still come back into this run (today: a life left).
func can_return(p: Player) -> bool:
	return p.lives > 0

func total_kills() -> int:
	var n := 0
	for p: Player in players.values():
		n += p.kills
	return n

## The horde's party multiplier. Each wizard counts 1, a fallen one tune.down_spawn_weight and an apprentice
## tune.apprentice_scale (both 1 by default).
func pscale() -> float:
	var n := 0.0
	for p: Player in players.values():
		n += (tune.down_spawn_weight if p.down else 1.0) * (tune.apprentice_scale if p.ai else 1.0)
	return 1.0 + tune.spawn_party_scale * (n - 1.0)

func emit(code: int, x: float = 0.0, y: float = 0.0, a: Variant = 0, b: Variant = 0) -> void:
	events.append([code, x, y, a, b])

func take_events() -> Array:
	var e := events
	events = []
	return e

# ================================================================= STEP ===
func step(dt: float, inputs: Dictionary) -> void:
	if phase != PH_GAMEOVER:
		WorldLevels._update_levelups(self, inputs)
	time += dt
	_tick += 1
	for i in 4:
		door_open[i] = maxf(0.0, door_open[i] - dt)
	match phase:
		PH_INTRO:
			phase_t -= dt
			if phase_t <= 0.0:
				phase = PH_FIGHT
				WorldDrops._refill_urns(self)
		PH_FIGHT:
			if won:
				victory_t -= dt
				if victory_t <= 0.0:
					_end_run()
				# The horde, the clock and the shrines stop once the run is won.
			else:
				_fight(dt)
		PH_GAMEOVER:
			phase_t += dt
	_build_grid()
	_plist.assign(players.values())
	for p in players.values():
		WorldPlayers._update_player(self, p, dt, inputs.get(p.slot, PackedFloat32Array()))
	for e in enemies:
		if not e.dead:
			WorldEnemies._update_enemy(self, e, dt)
	WorldCasting._update_shots(self, dt)
	WorldCasting._update_runes(self, dt)
	WorldEnemies._update_eshots(self, dt)
	WorldDrops._update_pickups(self, dt)
	WorldDrops._update_urns(self)
	enemies = enemies.filter(func(e): return not e.dead)
	shots = shots.filter(func(s): return not s.dead)
	runes = runes.filter(func(c: Rune) -> bool: return c.age < c.life)
	eshots = eshots.filter(func(s): return not s.dead)
	if phase != PH_GAMEOVER and not won:
		var any := false
		for p in players.values():
			if p.alive or can_return(p):
				any = true
		if not any:
			_end_run()

func _end_run() -> void:
	phase = PH_GAMEOVER
	phase_t = 0.0
	for p: Player in players.values():
		record.set_stat(p.slot, "level", p.level)
		record.set_stat(p.slot, "kills", p.kills)
	emit(EV_RESULTS, 0, 0, record.to_dict(), 0)
	emit(EV_GAMEOVER, wave_time, total_kills(), total_score(), liches_slain)

## One tick of the run proper: the clock, the horde, powerups and shrines. The lull counts down here; while it
## lasts the horde holds (see _direct_horde and _process_spawns) but the clock, minutes and shrines go on. Queued
## spawns slide later by the lull's time, so an omen's horde keeps its stagger and arrives after the lull ends.
func _fight(dt: float) -> void:
	wave_time += dt
	var held := minf(dt, lull_left)
	if held > 0.0:
		for s: Dictionary in spawn_queue:
			s.t += held
	lull_left = maxf(0.0, lull_left - dt)
	WorldWaves._tick_minute(self)
	WorldWaves._direct_horde(self, dt)
	WorldWaves._process_spawns(self)
	powerup_timer -= dt
	if powerup_timer <= 0.0:
		powerup_timer = rng.randf_range(9.0, 14.0)
		WorldWaves._spawn_random_powerup(self)
	WorldShrines._update_shrines(self, dt)

# ============================================================ LEVEL-UPS ===

## XP the party needs for its next level: the solo curve, grown with the party size.
func xp_needed() -> int:
	var scale := 1.0 + tune.xp_party_scale * (players.size() - 1)
	return maxi(1, int(round(tune.xp_to_next(party_level) * maxf(scale, 0.0))))

## Adds to the party's shared pool; `p` is the wizard who gets the credit (where the LEVEL UP shows).
## Each time the pool fills the party levels, and every wizard in the run gets one more offer.
func gain_xp(p: Player, amount: int) -> void:
	party_xp += amount
	var need := xp_needed()
	while party_xp >= need:
		party_xp -= need
		party_level += 1
		for q: Player in players.values():
			q.level = party_level
			q.pending += 1
		emit(EV_LEVELUP, p.pos.x, p.pos.y - 14, p.slot, party_level)
		need = xp_needed()

## True while any wizard holds cards. A plain query: the world no longer waits for picks.
func is_picking() -> bool:
	for p: Player in players.values():
		if not p.choices.is_empty():
			return true
	return false

func total_score() -> int:
	var s := 0
	for p in players.values():
		s += p.score
	return s

# =============================================================== PLAYER ===

## The middle of the living wizards, or of the arena when none is alive.
func party_center() -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for p: Player in players.values():
		if p.alive:
			c += p.pos
			n += 1
	return c / n if n > 0 else G.ARENA.get_center()

# ================================================================ GRID ===
func _build_grid() -> void:
	_grid.clear()
	for e in enemies:
		if e.dead:
			continue
		var k := Vector2i(floori(e.pos.x / CELL), floori(e.pos.y / CELL))
		if _grid.has(k):
			_grid[k].append(e)
		else:
			_grid[k] = [e]

func _query(pos: Vector2, radius: float) -> Array:
	var out := []
	var x0 := floori((pos.x - radius) / CELL)
	var x1 := floori((pos.x + radius) / CELL)
	var y0 := floori((pos.y - radius) / CELL)
	var y1 := floori((pos.y + radius) / CELL)
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var k := Vector2i(x, y)
			if _grid.has(k):
				for e in _grid[k]:
					if not e.dead:
						out.append(e)
	return out

## Summary of the whole simulation for determinism checks (same seed + same inputs = same hash).
func state_hash() -> int:
	return hash([snapshot(), wave, phase, total_score(), rng.state, horde_budget, party_level, party_xp, lull_left, players.values().map(func(p: Player) -> int: return p.pending)])

# ============================================================ SNAPSHOT ===
func _snapshot_urns() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for u: Vector2 in urns:
		out.append_array([u.x, u.y])
	return out

func snapshot() -> Dictionary:
	var pl := PackedFloat32Array()
	var row := PackedFloat32Array()
	row.resize(P_FLOATS)
	for p: Player in players.values():
		row.fill(0.0)
		row[P_SLOT] = p.slot
		row[P_X] = p.pos.x
		row[P_Y] = p.pos.y
		row[P_AIM_X] = p.aim.x
		row[P_AIM_Y] = p.aim.y
		row[P_HP] = p.hp
		row[P_LIVES] = p.lives
		row[P_ALIVE] = 1.0 if p.alive else 0.0
		row[P_INVULN] = p.invuln
		row[P_SPELL] = p.spell
		row[P_WIZARD] = p.wizard
		row[P_BOMBS] = p.bombs
		row[P_SCORE] = p.score
		row[P_COMBO] = p.combo
		row[P_HASTE] = p.haste
		row[P_ORBIT] = p.orbit
		row[P_ORBIT_ANG] = p.orbit_ang
		row[P_FLASH] = p.flash
		row[P_MOVING] = 1.0 if p.moving else 0.0
		row[P_XP] = party_xp
		row[P_XP_NEED] = xp_needed()
		row[P_LEVEL] = party_level
		row[P_OFFER] = p.offer
		for c in P_CHOICE_COUNT:
			var idx: int = p.choices[c] if c < p.choices.size() else -1
			row[P_CHOICES + c * 2] = idx
			row[P_CHOICES + c * 2 + 1] = Upgrades.level_of(p.upgrades, idx) + 1 if idx >= 0 else 0
		var owned := Upgrades.slot_ids(p.upgrades, Upgrades.SPELL)
		for k in P_SLOTS:
			var id: int = owned[k] if k < owned.size() else -1
			row[P_SPELLS + k * 2] = id
			row[P_SPELLS + k * 2 + 1] = WorldCasting._weapon_snap(self, p, Upgrades.spell_of(id)) if id >= 0 else 0
		var passives := Upgrades.slot_ids(p.upgrades, Upgrades.PASSIVE)
		for k in P_SLOTS:
			var id: int = passives[k] if k < passives.size() else -1
			row[P_PASSIVES + k * 2] = id
			row[P_PASSIVES + k * 2 + 1] = Upgrades.level_of(p.upgrades, id) if id >= 0 else 0
		row[P_GOLD] = floorf(p.gold)
		row[P_MAX_HP] = p.max_hp
		row[P_DRAWS] = p.pending + (0 if p.choices.is_empty() else 1)
		row[P_REDRAWS] = p.redraws
		row[P_BANISHES] = p.banishes
		row[P_DOWN] = 1.0 if p.down else 0.0
		row[P_DOWN_LEFT] = p.down_left
		row[P_REVIVE] = p.revive
		row[P_AI] = 1.0 if p.ai else 0.0
		row[P_TRAIT_A] = p.trait_a
		row[P_TRAIT_B] = p.trait_b
		row[P_RACE] = p.race
		row[P_CLASS] = p.cls
		row[P_LOOK] = p.look
		row[P_CLASS_LEVEL] = p.cls_level
		pl.append_array(row)
	var en := PackedFloat32Array()
	for e in enemies:
		en.append_array([e.id, e.type, e.pos.x, e.pos.y, e.flash, e.state, e.hp / e.maxhp, e.slow,
			2.0 if e.final else (1.0 if e.elite else 0.0), e.status])
	var sh := PackedFloat32Array()
	for s in shots:
		sh.append_array([s.kind, s.pos.x, s.pos.y, s.vel.x, s.vel.y, s.owner])
	var rn := PackedFloat32Array()
	for c: Rune in runes:
		rn.append_array([c.pos.x, c.pos.y, c.r, c.age, c.life, c.owner, 1.0 if c.evo else 0.0, c.kind])
	var es := PackedFloat32Array()
	for s in eshots:
		es.append_array([s.kind, s.pos.x, s.pos.y, s.vel.x, s.vel.y])
	var pk := PackedFloat32Array()
	for k in pickups:
		pk.append_array([k.kind, k.pos.x, k.pos.y, k.life])
	var bf := -1.0
	if boss and not boss.dead:
		bf = boss.hp / boss.maxhp
	var shr := PackedFloat32Array()
	for r: Array in WorldShrines.snapshot_shrines(self):
		shr.append_array(r)
	return {
		"p": pl, "e": en, "s": sh, "r": rn, "es": es, "k": pk, "sh": shr, "u": _snapshot_urns(), "o": PackedFloat32Array(),
		"w": PackedFloat32Array([wave, phase, phase_t, bf, door_open[0], door_open[1], door_open[2], door_open[3], wave_time,
			1.0 if boss != null and boss.final else 0.0, lull_left, seal, slots.x, slots.y]),
	}

# =========================================================== FORWARDERS ===
## One line each, for callers outside game/logic/world/ (tests, sims, tools, the arena, bots). The bodies live
## in the World* helpers named here; code inside World calls those helpers directly.
func _tick_minute() -> void:
	WorldWaves._tick_minute(self)

func final_minute() -> int:
	return WorldWaves.final_minute(self)

func _make_final(e: Enemy) -> void:
	WorldBosses._make_final(self, e)

func _lich_hp_scale() -> float:
	return WorldBosses._lich_hp_scale(self)

func _lich_visits(minute: int) -> int:
	return WorldBosses._lich_visits(self, minute)

func _queue_rift(type: int, n: int) -> void:
	WorldWaves._queue_rift(self, type, n)

func _spot_near_party(min_dist: float, max_dist: float, margin: float) -> Vector2:
	return WorldWaves._spot_near_party(self, min_dist, max_dist, margin)

func _process_spawns() -> void:
	WorldWaves._process_spawns(self)

func spawn_enemy(type: int, door: int, at: Variant = null) -> Enemy:
	return WorldWaves.spawn_enemy(self, type, door, at)

func _update_player(p: Player, dt: float, inp: PackedFloat32Array) -> void:
	WorldPlayers._update_player(self, p, dt, inp)

func _cast(p: Player, sp: int, lv: int, evo: bool, dir: Vector2) -> void:
	WorldCasting._cast(self, p, sp, lv, evo, dir)

func _shot(slot: int, sp: int, evo: bool, pos: Vector2, vel: Vector2, dmg: float, pierce: int) -> void:
	WorldCasting._shot(self, slot, sp, evo, pos, vel, dmg, pierce)

func _refresh_spell(p: Player) -> void:
	WorldCasting._refresh_spell(self, p)

func hurt_player(p: Player, dmg: int) -> void:
	WorldPlayers.hurt_player(self, p, dmg)

func _damage_enemy(e: Enemy, dmg: float, slot: int, knock: Vector2) -> void:
	WorldEnemies._damage_enemy(self, e, dmg, slot, knock)

func _kill_enemy(e: Enemy, slot: int) -> void:
	WorldEnemies._kill_enemy(self, e, slot)

func _refill_urns() -> void:
	WorldDrops._refill_urns(self)

func _update_urns() -> void:
	WorldDrops._update_urns(self)

func _break_urn(at: Vector2) -> void:
	WorldDrops._break_urn(self, at)

func _drop_xp(pos: Vector2, vel: Vector2, value: int) -> void:
	WorldDrops._drop_xp(self, pos, vel, value)

func _drop(kind: int, pos: Vector2, vel: Vector2, life: float = 9.0, value: int = 0) -> void:
	WorldDrops._drop(self, kind, pos, vel, life, value)

func _update_shots(dt: float) -> void:
	WorldCasting._update_shots(self, dt)

func _shot_hit(s: Shot, e: Enemy) -> void:
	WorldCasting._shot_hit(self, s, e)

func _explode(s: Shot) -> void:
	WorldCasting._explode(self, s)

func _update_runes(dt: float) -> void:
	WorldCasting._update_runes(self, dt)

func _collect(p: Player, k: Pickup) -> void:
	WorldDrops._collect(self, p, k)

func _open_chest(p: Player, k: Pickup) -> void:
	WorldDrops._open_chest(self, p, k)

func snapshot_shrines() -> Array:
	return WorldShrines.snapshot_shrines(self)

func _place_shrine(kind: int) -> void:
	WorldShrines._place_shrine(self, kind)

func _resolve_gamble(g: Dictionary) -> void:
	WorldShrines._resolve_gamble(self, g)

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

## Floats per player in snapshot()["p"]: 19 core values (index 9 is the main spell, 10 the wizard picked), then xp,
## xp needed, level, offer id, 3 x (offered upgrade index or -1, the level it would reach), the Spells.COUNT
## spell weapon levels from PLAYER_WEAPONS (0 = not owned, Spells.MAX_LEVEL + 1 = evolved), run gold and max hearts.
const PLAYER_WEAPONS := 29
const PLAYER_FLOATS := PLAYER_WEAPONS + Spells.COUNT + 2
const BASE_HEARTS := 5

## Floats per rune circle in snapshot()["r"]: x, y, radius, age s, lifetime s, owner slot, evolved.
const RUNE_FLOATS := 7

## Floats per enemy in snapshot()["e"]: id, type, x, y, flash, state, hp fraction, slow, rank (1 elite, 2 Archlich).
const ENEMY_FLOATS := 9

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

class Player:
	var slot := 0
	var wizard := 0 # Wizards index: robe colour and starting spell
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var aim := Vector2.DOWN
	var hp := 5
	var lives := 3
	var alive := true
	var respawn := 0.0
	var invuln := 2.0
	var spell := 0 # main spell: the highest weapon, which colours the staff
	var bombs := 2
	var cds: Array[float] = [] # seconds until each spell weapon casts again, per World.SP_*
	var haste := 0.0
	var orbit := 0.0
	var orbit_ang := 0.0
	var flash := 0.0
	var score := 0
	var combo := 0
	var combo_t := 0.0
	var last_bomb := -1
	var moving := false
	var kills := 0
	var xp := 0
	var level := 1
	var upgrades := {} # Upgrades index -> level
	var choices: Array[int] = [] # upgrades offered right now; the world waits while any player has some
	var offer := 0 # id of the current offer; a pick input must name it
	var pending := 0 # level-ups still to offer after the current one
	var regen_t := 0.0
	var max_hp := 5
	var gold := 0.0 # run gold; only exists inside a run
	var armor: Array = Loot.empty_stats() # Loot.ST_* totals from armor found in chests

class Enemy:
	var id := 0
	var type := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var knock := Vector2.ZERO
	var hp := 1.0
	var maxhp := 1.0
	var r := 5.0
	var spd := 40.0
	var flash := 0.0
	var slow := 0.0
	var state := 0
	var timer := 0.0
	var timer2 := 0.0
	var t := 0.0
	var dir := Vector2.ZERO
	var entering := true
	var enter_dir := Vector2.ZERO
	var orbit_cd := 0.0
	var count := 0.0
	var dead := false
	var contact := 1
	var elite := false
	var final := false # the Archlich: the run's last boss

class Shot:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var kind := 0 # spell, plus Spells.COUNT when evolved (what clients draw)
	var spell := 0
	var evo := false
	var pierce := 0 # enemies it may still pass through
	var hits := {} # enemy ids already hit by a piercing shot
	var dmg := 1.0
	var owner := 0
	var life := 1.0
	var r := 3.0
	var dead := false

## A rune circle inscribed on the floor: it hurts every enemy standing in it each Spells.RUNE_TICK, and the
## Seal of Solomon also pulls enemies toward its centre.
class Rune:
	var pos := Vector2.ZERO
	var r := 20.0
	var age := 0.0
	var life := 2.5
	var tick := 0.0 # seconds to the next damage tick
	var dmg := 1.0
	var owner := 0
	var evo := false
	var pull := 0.0

class EShot:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var kind := 0
	var life := 6.0
	var r := 3.0
	var dead := false

class Shrine:
	var kind := 0 # Gamble.SOLO or Gamble.TEAM
	var pos := Vector2.ZERO
	var life := 30.0
	var cost := 0
	var charge := 0.0 # seconds a wizard who can pay has stood on it
	var who := -1

class Pickup:
	var kind := 0
	var value := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 10.0

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
## Gameplay numbers. Tuning.shared() unless a test or sim passes its own.
var tune: Tuning

## seed_value 0 picks a random seed (normal play); tests, sims and replays pass a fixed one. `wizards` maps a
## slot to the Wizards index its player picked in the lobby; a slot not in it plays the wizard of its own colour.
func _init(slots: Array, seed_value: int = 0, tuning: Tuning = null, wizards: Dictionary = {}) -> void:
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
		p.cds.resize(Spells.COUNT)
		p.cds.fill(0.0)
		p.upgrades[Upgrades.weapon_entry(Wizards.start_spell(p.wizard))] = 1
		_refresh_spell(p)
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

func total_kills() -> int:
	var n := 0
	for p: Player in players.values():
		n += p.kills
	return n

func pscale() -> float:
	return 1.0 + tune.spawn_party_scale * (players.size() - 1)

func emit(code: int, x: float = 0.0, y: float = 0.0, a: Variant = 0, b: Variant = 0) -> void:
	events.append([code, x, y, a, b])

func take_events() -> Array:
	var e := events
	events = []
	return e

# ================================================================= STEP ===
func step(dt: float, inputs: Dictionary) -> void:
	if phase != PH_GAMEOVER and _update_levelups(inputs):
		return
	time += dt
	_tick += 1
	for i in 4:
		door_open[i] = maxf(0.0, door_open[i] - dt)
	match phase:
		PH_INTRO:
			phase_t -= dt
			if phase_t <= 0.0:
				phase = PH_FIGHT
				_refill_urns()
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
	for p in players.values():
		_update_player(p, dt, inputs.get(p.slot, PackedFloat32Array()))
	for e in enemies:
		if not e.dead:
			_update_enemy(e, dt)
	_update_shots(dt)
	_update_runes(dt)
	_update_eshots(dt)
	_update_pickups(dt)
	_update_urns()
	enemies = enemies.filter(func(e): return not e.dead)
	shots = shots.filter(func(s): return not s.dead)
	runes = runes.filter(func(c: Rune) -> bool: return c.age < c.life)
	eshots = eshots.filter(func(s): return not s.dead)
	if phase != PH_GAMEOVER and not won:
		var any := false
		for p in players.values():
			if p.alive or p.lives > 0:
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

## One tick of the run proper: the clock, the horde, powerups and shrines.
func _fight(dt: float) -> void:
	wave_time += dt
	_tick_minute()
	_direct_horde(dt)
	_process_spawns()
	powerup_timer -= dt
	if powerup_timer <= 0.0:
		powerup_timer = rng.randf_range(9.0, 14.0)
		_spawn_random_powerup()
	_update_shrines(dt)

# ============================================================ LEVEL-UPS ===
## Offers and applies level-up picks. Returns true while any player still has to pick: the whole world waits.
func _update_levelups(inputs: Dictionary) -> bool:
	var frozen := false
	for p: Player in players.values():
		if p.choices.is_empty() and p.pending > 0:
			_offer(p)
		if not p.choices.is_empty():
			var inp: PackedFloat32Array = inputs.get(p.slot, PackedFloat32Array())
			if inp.size() >= 8 and int(inp[7]) == p.offer:
				var c := int(inp[6])
				if c >= 0 and c < p.choices.size():
					_pick(p, p.choices[c])
		if not p.choices.is_empty():
			frozen = true
	if frozen:
		# Presses made while the world waits (confirming a card with Space) must not fire a nova afterwards.
		for p: Player in players.values():
			var inp: PackedFloat32Array = inputs.get(p.slot, PackedFloat32Array())
			if inp.size() >= 6:
				p.last_bomb = int(inp[5])
	return frozen

func _offer(p: Player) -> void:
	p.pending -= 1
	p.offer += 1
	p.choices = Upgrades.roll(rng, p.upgrades, int(tune.level_choices))
	if p.choices.is_empty():
		var pts := int(tune.maxed_level_score)
		p.score += pts
		emit(EV_SCORE, p.pos.x, p.pos.y - 14, pts, p.slot)

func _pick(p: Player, idx: int) -> void:
	p.choices = []
	if not Upgrades.take(p.upgrades, idx):
		return
	match idx:
		Upgrades.NOVA:
			p.bombs += 1
		Upgrades.LIFE:
			p.lives += 1
	_refresh_spell(p)
	emit(EV_PICK, p.pos.x, p.pos.y - 14, p.slot, idx)
	if Upgrades.is_evolution(idx):
		record.note(wave_time, Results.M_EVOLVE, p.slot, idx)
	if p.pending > 0:
		_offer(p)

func gain_xp(p: Player, amount: int) -> void:
	p.xp += amount
	var need := tune.xp_to_next(p.level)
	while p.xp >= need:
		p.xp -= need
		p.level += 1
		p.pending += 1
		emit(EV_LEVELUP, p.pos.x, p.pos.y - 14, p.slot, p.level)
		need = tune.xp_to_next(p.level)

## True while the world is waiting for level-up picks.
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

# ================================================================ WAVES ===
## A new minute: announce it. At every boss_every_min minute mark (5:00, 10:00, ...) the Lich comes, unless it is
## still here.
func _tick_minute() -> void:
	var minute := int(wave_time / 60.0) + 1
	if minute <= wave:
		return
	wave = minute
	_refill_urns()
	if wave >= final_minute() and not _final_called:
		_final_called = true
		emit(EV_WAVE, 0, 0, wave, 2)
		if boss != null and not boss.dead:
			_make_final(boss) # a Lich still standing ascends
		else:
			spawn_queue.append({"t": wave_time + 2.5, "type": LICH, "door": 0, "final": true})
			_sort_queue()
		return
	var boss_minute := wave < final_minute() and _lich_visits(wave) > _lich_visits(wave - 1)
	emit(EV_WAVE, 0, 0, wave, 1 if boss_minute else 0)
	for i in OMENS.size():
		if int(OMENS[i][0]) == wave:
			_queue_omen(i)
	if boss_minute and boss == null:
		spawn_queue.append({"t": wave_time + 2.5, "type": LICH, "door": 0})
		_sort_queue()

## Starts omen `i`: announces it and queues its horde OMEN_WARN seconds out.
func _queue_omen(i: int) -> void:
	var o: Array = OMENS[i]
	var type: int = o[1]
	var n: int = o[2]
	var t := wave_time + OMEN_WARN
	if not o[3]:
		emit(EV_OMEN, G.ARENA.get_center().x, G.ARENA.get_center().y, i, 0)
		for d in DOORS.size():
			_queue_group(type, n / DOORS.size(), d, t)
		_sort_queue()
		return
	var c := Vector2.ZERO
	var alive := 0
	for p: Player in players.values():
		if p.alive:
			c += p.pos
			alive += 1
	c = c / alive if alive > 0 else G.ARENA.get_center()
	emit(EV_OMEN, c.x, c.y, i, OMEN_RING_R)
	var inner := G.ARENA.grow(-10.0)
	for k in n:
		var at := c + Vector2.from_angle(TAU * k / n) * OMEN_RING_R
		at = Vector2(clampf(at.x, inner.position.x, inner.end.x), clampf(at.y, inner.position.y, inner.end.y))
		spawn_queue.append({"t": t + k * 0.02, "type": type, "door": 0, "at": at})
	_sort_queue()

## The minute the Archlich comes: the one that starts at run_minutes:00. No Lich visits after it.
func final_minute() -> int:
	return int(tune.run_minutes) + 1

## Turns a Lich into the Archlich: final_hp_mul times the HP, full health, a bigger body and a meaner pattern.
func _make_final(e: Enemy) -> void:
	e.final = true
	e.maxhp = STATS[LICH][0] * _lich_hp_scale() * tune.final_hp_mul
	e.hp = e.maxhp
	e.r += 3.0
	e.state = 0
	e.timer = 2.0
	emit(EV_BOSS, e.pos.x, e.pos.y, 1, 0)

func _lich_hp_scale() -> float:
	return (1.0 + tune.boss_hp_per_player * (players.size() - 1)) * (1.0 + tune.boss_hp_per_cycle * maxi(0, _lich_visits(wave) - 1))

## How many Lich visits are due by the start of `minute` (minute 1 starts at 0:00).
func _lich_visits(minute: int) -> int:
	return (minute - 1) / int(tune.boss_every_min)

## The horde earns spawn budget every second (more each minute, scaled by party size, less while the Lich is
## up) and spends it on the group it rolled, from a random door. At the enemy cap it holds: enemies on the field
## and enemies still queued both count, so the field never grows much past the cap.
func _direct_horde(dt: float) -> void:
	elite_t += dt
	if elite_t >= tune.elite_interval:
		elite_t -= tune.elite_interval
		_spawn_elite()
	if enemies.size() + spawn_queue.size() >= int(tune.enemy_cap):
		return
	var rate := (tune.horde_rate_base + tune.horde_rate_per_min * wave_time / 60.0) * pscale()
	if boss != null:
		rate *= tune.horde_boss_mul
	horde_budget += rate * dt
	if _next_group.is_empty():
		_next_group = _roll_group()
	var cost: float = _horde_row(_next_group[0])[1] * _next_group[1]
	if horde_budget >= cost:
		horde_budget -= cost
		if rng.randf() < tune.rift_share:
			_queue_rift(_next_group[0], _next_group[1])
		else:
			_queue_group(_next_group[0], _next_group[1], _pick_door(), wave_time)
		_sort_queue()
		_next_group = []

## A rift: a marker opens somewhere in the arena away from the wizards, and after tune.rift_warning the
## group bursts out of it in a clump, so the horde surrounds the party instead of queuing at the doors.
func _queue_rift(type: int, n: int) -> void:
	var best := _spot_near_party(tune.rift_min_dist, tune.rift_max_dist, 22.0)
	var spread := 6.0 + 3.0 * sqrt(float(n))
	emit(EV_RIFT, best.x, best.y, spread, tune.rift_warning)
	for i in n:
		var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * spread
		spawn_queue.append({"t": wave_time + tune.rift_warning + i * 0.03, "type": type, "door": 0, "at": best + off})

## A door for a group: usually the one nearest the party (the arena is bigger than the screen, and a far door
## would leave the group walking for half a minute), otherwise any door.
func _pick_door() -> int:
	if rng.randf() >= tune.door_near_share:
		return rng.randi_range(0, DOORS.size() - 1)
	var c := party_center()
	var best := 0
	for d in DOORS.size():
		if (DOORS[d] as Vector2).distance_to(c) < (DOORS[best] as Vector2).distance_to(c):
			best = d
	return best

## A point in the arena (inset by `margin`) between `min_dist` and `max_dist` from the middle of the party and at
## least `min_dist` from every living wizard: just off the edge of the screen, the way a survivors horde closes
## in. Falls back to the try farthest from the wizards.
func _spot_near_party(min_dist: float, max_dist: float, margin: float) -> Vector2:
	var area := G.ARENA.grow(-margin)
	var c := party_center()
	var best := area.get_center()
	var best_d := -1.0
	for tries in 12:
		var at := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(min_dist, maxf(min_dist, max_dist))
		at = at.clamp(area.position, area.end)
		var d := INF
		for p: Player in players.values():
			if p.alive:
				d = minf(d, p.pos.distance_to(at))
		if d > best_d:
			best_d = d
			best = at
		if d >= min_dist:
			break
	return best

## A weighted pick among the unlocked HORDE rows, with its group size: [type, count].
func _roll_group() -> Array:
	var total := 0
	for row: Array in HORDE:
		if wave_time >= row[2]:
			total += int(row[3])
	var r := rng.randi_range(1, total)
	for row: Array in HORDE:
		if wave_time < row[2]:
			continue
		r -= int(row[3])
		if r <= 0:
			return [row[0], rng.randi_range(row[4], row[5] + row[6] * (wave - 1))]
	return [GOBLIN, 1]

func _horde_row(type: int) -> Array:
	for row: Array in HORDE:
		if row[0] == type:
			return row
	return HORDE[0]

## An elite: a big, glowing, much tougher enemy that pays out in XP, gems and a tome.
func _spawn_elite() -> void:
	var type := SKELETON
	var roll := rng.randf()
	if wave >= 10:
		type = GARGOYLE if roll < 0.4 else (PRIEST if roll < 0.7 else ORC)
	elif wave >= 6:
		type = PRIEST if roll < 0.35 else (ORC if roll < 0.7 else MAGE)
	elif wave >= 4:
		type = ORC if roll < 0.6 else MAGE
	elif wave >= 2:
		type = ORC
	var e := spawn_enemy(type, _pick_door())
	e.elite = true
	e.hp *= tune.elite_hp_mul
	e.maxhp = e.hp
	e.r += 2.0
	emit(EV_ELITE, e.pos.x, e.pos.y, e.type, 0)

func _queue_group(type: int, n: int, door: int, t: float) -> void:
	for i in n:
		spawn_queue.append({"t": t + i * DOOR_STAGGER, "type": type, "door": door})

func _sort_queue() -> void:
	spawn_queue.sort_custom(func(a, b): return a.t < b.t)

func _process_spawns() -> void:
	while not spawn_queue.is_empty() and spawn_queue[0].t <= wave_time:
		var s: Dictionary = spawn_queue.pop_front()
		var e := spawn_enemy(s.type, s.door, s.get("at"))
		if s.get("final", false):
			_make_final(e)

func spawn_enemy(type: int, door: int, at: Variant = null) -> Enemy:
	var e := Enemy.new()
	e.id = next_id
	next_id += 1
	e.type = type
	var st: Array = STATS[type]
	var hp_scale := 1.0 + tune.enemy_hp_per_min * (wave - 1)
	if type == LICH:
		hp_scale = _lich_hp_scale()
	e.hp = st[0] * hp_scale
	e.maxhp = e.hp
	e.spd = st[1] * (1.0 + tune.enemy_speed_per_min * minf(wave, tune.enemy_speed_min_cap))
	e.r = st[2]
	e.contact = st[4]
	e.t = rng.randf() * 10.0
	e.timer = rng.randf_range(1.0, 2.5)
	if at != null:
		e.pos = at
		e.entering = false
	else:
		var jitter := Vector2(rng.randf_range(-14, 14), 0) if door < 2 else Vector2(0, rng.randf_range(-14, 14))
		e.pos = DOORS[door] + jitter
		e.enter_dir = DOOR_DIRS[door]
		if door_open[door] <= 0.0:
			emit(EV_DOOR, DOORS[door].x, DOORS[door].y, door, 0)
		door_open[door] = 1.2
	if type == LICH:
		boss = e
		e.state = 0
		e.timer = 2.0
		emit(EV_BOSS, e.pos.x, e.pos.y, 0, 0)
	enemies.append(e)
	return e

func _spawn_random_powerup() -> void:
	var kinds := TOMES + [PK_BOOTS, PK_ORBIT, PK_TOME_FIRE, PK_TOME_STORM]
	var k: int = kinds[rng.randi() % kinds.size()]
	var pos := Vector2.ZERO
	for tries in 12:
		pos = Vector2(rng.randf_range(G.ARENA.position.x + 30, G.ARENA.end.x - 30),
			rng.randf_range(G.ARENA.position.y + 24, G.ARENA.end.y - 24))
		var ok := true
		for p in players.values():
			if p.pos.distance_to(pos) < 50:
				ok = false
		if ok:
			break
	_drop(k, pos, Vector2.ZERO, 12.0)
	emit(EV_POWERUP, pos.x, pos.y, k, 0)

# =============================================================== PLAYER ===
func _update_player(p: Player, dt: float, inp: PackedFloat32Array) -> void:
	p.flash = maxf(0.0, p.flash - dt)
	p.invuln = maxf(0.0, p.invuln - dt)
	p.haste = maxf(0.0, p.haste - dt)
	p.orbit = maxf(0.0, p.orbit - dt)
	p.orbit_ang += dt * 5.5
	if p.combo_t > 0.0:
		p.combo_t -= dt
		if p.combo_t <= 0.0:
			p.combo = 0
	if not p.alive:
		if p.lives > 0 and phase != PH_GAMEOVER:
			p.respawn -= dt
			if p.respawn <= 0.0:
				p.alive = true
				p.hp = p.max_hp
				p.invuln = 2.5
				p.bombs = maxi(p.bombs, 2)
				# Back beside the party (the arena is bigger than the screen), or mid-arena when nobody is up.
				p.pos = party_center() + Vector2(rng.randf_range(-20, 20), rng.randf_range(-10, 10))
				p.pos = p.pos.clamp(G.ARENA.position + Vector2(5, 6), G.ARENA.end - Vector2(5, 2))
				emit(EV_SPAWN, p.pos.x, p.pos.y, p.slot, 0)
		return
	var regen := Upgrades.regen_interval(p.upgrades)
	if regen > 0.0 and p.hp < p.max_hp:
		p.regen_t += dt
		if p.regen_t >= regen:
			p.regen_t = 0.0
			p.hp += 1
	else:
		p.regen_t = 0.0
	var move := Vector2.ZERO
	var aim := Vector2.ZERO
	var bomb_count := -1
	if inp.size() >= 6:
		move = Vector2(inp[0], inp[1]).limit_length(1.0)
		aim = Vector2(inp[2], inp[3])
		bomb_count = int(inp[5])
	var speed: float = tune.player_speed * Upgrades.move_mul(p.upgrades) * (1.0 + p.armor[Loot.ST_SWIFT]) \
		* (tune.haste_speed_mul if p.haste > 0.0 else 1.0)
	p.vel = move * speed
	p.moving = move.length() > 0.1
	p.pos += p.vel * dt
	p.pos.x = clampf(p.pos.x, G.ARENA.position.x + 5, G.ARENA.end.x - 5)
	p.pos.y = clampf(p.pos.y, G.ARENA.position.y + 6, G.ARENA.end.y - 2)
	_leash(p)
	if aim.length() > 0.1:
		p.aim = aim.normalized()
	elif p.moving:
		p.aim = move.normalized()
	if phase != PH_GAMEOVER:
		_auto_cast(p, dt, aim)
	if bomb_count >= 0:
		if p.last_bomb < 0:
			p.last_bomb = bomb_count
		elif bomb_count > p.last_bomb:
			p.last_bomb = bomb_count
			if p.bombs > 0:
				_nova(p)
	if p.orbit > 0.0:
		stat_src = Results.SRC_ORBIT
		for i in 3:
			var a := p.orbit_ang + i * TAU / 3.0
			var op := p.pos + Vector2(0, -6) + Vector2(cos(a), sin(a)) * 22.0
			for e in _query(op, 14.0):
				if e.orbit_cd <= 0.0 and op.distance_to(e.pos) < e.r + 6.0:
					e.orbit_cd = 0.3
					_damage_enemy(e, 1.5, p.slot, (e.pos - p.pos).normalized() * 80.0)

## Wizards share one screen: none may get further than tune.leash_x / leash_y from any other living wizard.
func _leash(p: Player) -> void:
	for q: Player in players.values():
		if q == p or not q.alive:
			continue
		p.pos.x = clampf(p.pos.x, q.pos.x - tune.leash_x, q.pos.x + tune.leash_x)
		p.pos.y = clampf(p.pos.y, q.pos.y - tune.leash_y, q.pos.y + tune.leash_y)

## The middle of the living wizards, or of the arena when none is alive.
func party_center() -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for p: Player in players.values():
		if p.alive:
			c += p.pos
			n += 1
	return c / n if n > 0 else G.ARENA.get_center()

## Every owned spell weapon casts on its own cooldown: along the aim stick when it is held, otherwise at the
## nearest enemy within tune.auto_aim_range. Nothing in range and no aim: the weapons wait, ready.
func _auto_cast(p: Player, dt: float, aim: Vector2) -> void:
	var dir := Vector2.ZERO
	if aim.length() > 0.1:
		dir = aim.normalized()
	else:
		var tgt := _nearest_enemy(p.pos, tune.auto_aim_range)
		if tgt:
			dir = (tgt.pos + Vector2(0, -4) - (p.pos + Vector2(0, -7))).normalized()
			p.aim = dir
	var rate_mul: float = (tune.haste_rate_mul if p.haste > 0.0 else 1.0) * Upgrades.cast_mul(p.upgrades) * tune.spell_cd_mul \
		* (1.0 - p.armor[Loot.ST_FOCUS])
	for sp in Spells.COUNT:
		var lv := Upgrades.weapon_level(p.upgrades, sp)
		if lv <= 0:
			continue
		p.cds[sp] = maxf(0.0, p.cds[sp] - dt)
		if p.cds[sp] > 0.0 or dir == Vector2.ZERO:
			continue
		var evo := Upgrades.evolved(p.upgrades, sp)
		p.cds[sp] = Spells.cooldown(sp, lv, evo) * rate_mul
		_cast(p, sp, lv, evo, dir)

## Nearest living enemy inside the arena within `radius` of `pos`, or null.
func _nearest_enemy(pos: Vector2, radius: float) -> Enemy:
	var best: Enemy = null
	var bd := radius * radius
	for e in enemies:
		if e.dead or e.entering:
			continue
		var d := e.pos.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = e
	return best

func _cast(p: Player, sp: int, lv: int, evo: bool, dir: Vector2) -> void:
	stat_src = sp
	var tip := p.pos + Vector2(0, -7) + dir * 9.0
	var n := Spells.count(sp, lv, evo)
	var dmg := Spells.damage(sp, lv, evo)
	if sp == SP_RUNE:
		_inscribe_runes(p, lv, evo, dir, n, dmg)
	elif sp == SP_STORM:
		var chains := int(Spells.evo_value(sp, "chains", 1.0)) if evo else 1
		var range_mul := Spells.TEMPEST_RANGE_MUL if evo else 1.0
		var hit := {}
		for c in chains:
			_chain_lightning(p.slot, tip, dir.rotated((c - (chains - 1) * 0.5) * 0.5), n, dmg, range_mul, hit)
	else:
		var spread := Spells.stat(sp, "spread")
		var speed := Spells.stat(sp, "speed")
		var pierce := int(Spells.evo_value(sp, "pierce", 0.0)) if evo else 0
		for i in n:
			var a := (i - (n - 1) * 0.5) * spread
			if sp == SP_ARCANE:
				a += rng.randf_range(-0.04, 0.04)
			_shot(p.slot, sp, evo, tip, dir.rotated(a) * speed, dmg, pierce)
	emit(EV_CAST, tip.x, tip.y, sp, p.slot)

func _shot(slot: int, sp: int, evo: bool, pos: Vector2, vel: Vector2, dmg: float, pierce: int) -> void:
	var s := Shot.new()
	s.pos = pos
	s.vel = vel
	s.spell = sp
	s.evo = evo
	s.kind = sp + (Spells.COUNT if evo else 0)
	s.dmg = dmg
	s.owner = slot
	s.r = Spells.stat(sp, "r")
	s.life = Spells.stat(sp, "life")
	s.pierce = pierce
	shots.append(s)

## Inscribes `n` rune circles, each on the densest cluster of enemies within Spells.RUNE_RANGE of the wizard
## that no circle of this cast already covers; with no enemy in range, one circle goes ahead along `dir`.
func _inscribe_runes(p: Player, lv: int, evo: bool, dir: Vector2, n: int, dmg: float) -> void:
	var radius := Spells.level_value(SP_RUNE, "r", lv, evo)
	var near: Array[Enemy] = []
	for e: Enemy in _query(p.pos, Spells.RUNE_RANGE):
		if not e.entering and not _faded(e) and e.pos.distance_to(p.pos) <= Spells.RUNE_RANGE:
			near.append(e)
	var centres: Array[Vector2] = []
	for i in n:
		var best := Vector2.INF
		var best_n := 0
		var best_d := INF
		for e: Enemy in near:
			var covered := false
			for c: Vector2 in centres:
				if c.distance_to(e.pos) < radius * Spells.RUNE_SPACING:
					covered = true
					break
			if covered:
				continue
			var sum := Vector2.ZERO
			var cnt := 0
			for o: Enemy in _query(e.pos, radius):
				if not o.entering and o.pos.distance_to(e.pos) <= radius:
					sum += o.pos
					cnt += 1
			var d := e.pos.distance_squared_to(p.pos)
			if cnt > best_n or (cnt == best_n and d < best_d):
				best_n = cnt
				best_d = d
				best = sum / maxf(1.0, float(cnt))
		if best == Vector2.INF:
			break
		centres.append(best)
	if centres.is_empty():
		centres.append(p.pos + dir * Spells.RUNE_AIM_DIST)
	for c: Vector2 in centres:
		var rn := Rune.new()
		rn.pos = Vector2(clampf(c.x, G.ARENA.position.x + 4.0, G.ARENA.end.x - 4.0),
			clampf(c.y, G.ARENA.position.y + 4.0, G.ARENA.end.y - 4.0))
		rn.r = radius
		rn.life = Spells.level_value(SP_RUNE, "life", lv, evo)
		rn.tick = Spells.RUNE_ARM
		rn.dmg = dmg
		rn.owner = p.slot
		rn.evo = evo
		rn.pull = Spells.evo_value(SP_RUNE, "pull", 0.0) if evo else 0.0
		runes.append(rn)
		emit(EV_RUNE, rn.pos.x, rn.pos.y, rn.r, p.slot + (8 if evo else 0))

## Lightning from `tip` to the nearest enemy roughly along `dir`, then `jumps - 1` jumps foe to foe.
## Enemies in `hit` are skipped, so several chains of one cast find different foes.
func _chain_lightning(slot: int, tip: Vector2, dir: Vector2, jumps: int, dmg: float, range_mul: float, hit: Dictionary) -> void:
	var best: Enemy = null
	var best_d := Spells.CHAIN_FIRST_RANGE * range_mul
	for e in enemies:
		if e.dead or hit.has(e.id):
			continue
		var to := e.pos - tip
		var d := to.length()
		if d < best_d and to.normalized().dot(dir) > 0.6:
			best_d = d
			best = e
	if best == null:
		emit(EV_ZAP, tip.x, tip.y, PackedVector2Array([tip, tip + dir * Spells.CHAIN_JUMP_RANGE * range_mul]), slot)
		return
	_zap_chain(slot, tip, best, jumps, dmg, Spells.CHAIN_JUMP_RANGE * range_mul, hit, dir)

## Lightning from `from` through `first` and on to the nearest unhit enemy within `jump_range`, up to `jumps` foes.
func _zap_chain(slot: int, from: Vector2, first: Enemy, jumps: int, dmg: float, jump_range: float, hit: Dictionary, push: Vector2) -> void:
	var pts := PackedVector2Array([from])
	var cur := first
	for i in jumps:
		pts.append(cur.pos + Vector2(0, -4))
		hit[cur.id] = true
		_damage_enemy(cur, dmg, slot, push * 40.0)
		var nxt: Enemy = null
		var nd := jump_range
		for e in _query(cur.pos, jump_range):
			if hit.has(e.id) or e.dead:
				continue
			var d: float = e.pos.distance_to(cur.pos)
			if d < nd:
				nd = d
				nxt = e
		if nxt == null:
			break
		cur = nxt
		dmg *= Spells.CHAIN_FALLOFF
	emit(EV_ZAP, from.x, from.y, pts, slot)

## The main spell is the highest weapon (an evolved one beats any level); ties go to the later spell.
func _refresh_spell(p: Player) -> void:
	var best := -1
	for sp in Spells.COUNT:
		var lv := _weapon_snap(p, sp)
		if lv > 0 and lv >= best:
			best = lv
			p.spell = sp

## Weapon level as sent in snapshots: 0 not owned, 1..MAX_LEVEL, MAX_LEVEL + 1 evolved.
func _weapon_snap(p: Player, sp: int) -> int:
	if Upgrades.evolved(p.upgrades, sp):
		return Spells.MAX_LEVEL + 1
	return Upgrades.weapon_level(p.upgrades, sp)

func _nova(p: Player) -> void:
	stat_src = Results.SRC_NOVA
	p.bombs -= 1
	p.invuln = maxf(p.invuln, 0.8)
	emit(EV_NOVA, p.pos.x, p.pos.y - 6, p.slot, 0)
	var radius := 150.0
	for e in enemies:
		if e.dead:
			continue
		var d := e.pos.distance_to(p.pos)
		if d < radius:
			var dmg := 40.0 if e.type == LICH else 14.0
			_damage_enemy(e, dmg, p.slot, (e.pos - p.pos).normalized() * 260.0)
	for s in eshots:
		if s.pos.distance_to(p.pos) < radius + 30:
			s.dead = true

func hurt_player(p: Player, dmg: int) -> void:
	if not p.alive or p.invuln > 0.0 or phase == PH_GAMEOVER:
		return
	if p.armor[Loot.ST_WARD] > 0.0 and rng.randf() < p.armor[Loot.ST_WARD]:
		p.invuln = 0.5
		emit(EV_WARD, p.pos.x, p.pos.y - 6, p.slot, 0)
		return
	p.hp -= dmg
	p.flash = 0.15
	p.invuln = 1.1
	emit(EV_HURT, p.pos.x, p.pos.y - 6, p.slot, 0)
	if p.hp <= 0:
		p.alive = false
		p.lives -= 1
		p.respawn = 2.5
		p.haste = 0.0
		p.orbit = 0.0
		p.combo = 0
		record.add(p.slot, "deaths", 1)
		emit(EV_PDIE, p.pos.x, p.pos.y - 6, p.slot, p.lives)

# ================================================================ ENEMY ===
func _nearest_player(pos: Vector2) -> Player:
	var best: Player = null
	var bd := INF
	for p in players.values():
		if not p.alive:
			continue
		var d = p.pos.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best

func _update_enemy(e: Enemy, dt: float) -> void:
	e.t += dt
	e.flash = maxf(0.0, e.flash - dt)
	e.slow = maxf(0.0, e.slow - dt)
	e.orbit_cd = maxf(0.0, e.orbit_cd - dt)
	var sm := 0.45 if e.slow > 0.0 else 1.0
	if e.entering:
		e.pos += e.enter_dir * maxf(e.spd, 40.0) * dt
		if G.ARENA.grow(-10).has_point(e.pos):
			e.entering = false
		return
	var tgt := _nearest_player(e.pos)
	var tpos := tgt.pos if tgt else G.ARENA.get_center() + Vector2(cos(e.t * 0.5), sin(e.t * 0.7)) * 80.0
	var to := tpos - e.pos
	var dist := to.length()
	var dirv := to / maxf(dist, 0.001)
	var desired := Vector2.ZERO
	match e.type:
		GOBLIN, MSLIME:
			desired = (dirv + dirv.orthogonal() * sin(e.t * 3.0 + e.id) * 0.35).normalized() * e.spd
		BAT:
			desired = (dirv + dirv.orthogonal() * sin(e.t * 5.0 + e.id) * 1.1).normalized() * e.spd
		SLIME:
			var cyc := fmod(e.t, 1.0)
			e.state = 1 if cyc < 0.5 else 0
			desired = dirv * e.spd * 2.2 if cyc < 0.5 else Vector2.ZERO
		SKELETON:
			if dist > 125:
				desired = dirv * e.spd
			elif dist < 80:
				desired = -dirv * e.spd
			else:
				desired = dirv.orthogonal() * e.spd * (1.0 if e.id % 2 == 0 else -1.0)
			e.timer -= dt
			if e.timer <= 0.0 and tgt and dist < 240:
				e.timer = rng.randf_range(1.8, 2.8)
				var lead := tgt.pos + tgt.vel * (dist / 150.0) * 0.5
				_eshot(ES_ARROW, e.pos + Vector2(0, -7), (lead - e.pos).normalized() * 150.0, 2.5)
				emit(EV_ESHOT, e.pos.x, e.pos.y - 7, ES_ARROW, 0)
		ORC:
			match e.state:
				0:
					desired = dirv * e.spd
					e.timer -= dt
					if e.timer <= 0.0 and tgt and dist < 160:
						e.state = 1
						e.timer2 = 0.6
						e.dir = dirv
						emit(EV_CHARGE, e.pos.x, e.pos.y - 8, e.id, 0)
				1:
					e.timer2 -= dt
					desired = Vector2.ZERO
					if e.timer2 <= 0.0:
						e.state = 2
						e.timer2 = 0.6
				2:
					e.timer2 -= dt
					desired = e.dir * 240.0
					if e.timer2 <= 0.0 or not G.ARENA.grow(-9).has_point(e.pos + e.dir * 4.0):
						e.state = 0
						e.timer = rng.randf_range(2.0, 3.2)
		MAGE:
			desired = dirv.orthogonal() * e.spd * sin(e.t)
			e.timer -= dt
			if e.state == 0 and e.timer <= 0.0 and tgt:
				var old := e.pos
				var ang := rng.randf() * TAU
				var np := tgt.pos + Vector2(cos(ang), sin(ang)) * rng.randf_range(80, 130)
				np.x = clampf(np.x, G.ARENA.position.x + 14, G.ARENA.end.x - 14)
				np.y = clampf(np.y, G.ARENA.position.y + 14, G.ARENA.end.y - 6)
				e.pos = np
				emit(EV_TELE, old.x, old.y - 6, 0, 0)
				emit(EV_TELE, np.x, np.y - 6, 1, 0)
				e.state = 1
				e.timer2 = 0.55
			elif e.state == 1:
				e.timer2 -= dt
				if e.timer2 <= 0.0:
					e.state = 0
					e.timer = rng.randf_range(2.6, 3.6)
					if tgt:
						var d := (tgt.pos - e.pos).normalized()
						for a in [-0.28, 0.0, 0.28]:
							_eshot(ES_ORB, e.pos + Vector2(0, -8), d.rotated(a) * 95.0, 4.0)
						emit(EV_ESHOT, e.pos.x, e.pos.y - 8, ES_ORB, 0)
		LICH:
			desired = _update_lich(e, dt, tgt, dirv, dist)
		WRAITH:
			# Straight through the crowd, fading out (state 1) for a moment in every cycle.
			var cyc := fmod(e.t, WRAITH_SOLID + WRAITH_FADED)
			e.state = 1 if cyc >= WRAITH_SOLID else 0
			desired = (dirv + dirv.orthogonal() * sin(e.t * 2.0 + e.id) * 0.25).normalized() * e.spd
		TOME:
			match e.state:
				0:
					# Circle the wizard at a reading distance, then rear up and dash through.
					var side := 1.0 if e.id % 2 == 0 else -1.0
					var ring := dirv * (dist - 70.0) * 0.04 + dirv.orthogonal() * side
					desired = ring.normalized() * e.spd
					e.timer -= dt
					if e.timer <= 0.0 and tgt and dist < 140:
						e.state = 1
						e.timer2 = 0.4
						e.dir = dirv
				1:
					e.timer2 -= dt
					desired = -e.dir * 20.0
					if e.timer2 <= 0.0:
						e.state = 2
						e.timer2 = 0.55
				2:
					e.timer2 -= dt
					desired = e.dir * 210.0
					if e.timer2 <= 0.0:
						e.state = 0
						e.timer = rng.randf_range(2.4, 3.6)
		GARGOYLE:
			# Perched as stone (state 0), then a swoop at the wizard (state 1).
			e.timer -= dt
			if e.state == 0:
				desired = Vector2.ZERO
				if e.timer <= 0.0 and tgt:
					e.state = 1
					e.timer = GARGOYLE_SWOOP
					e.dir = dirv
					emit(EV_CHARGE, e.pos.x, e.pos.y - 10, e.id, 0)
			else:
				e.dir = e.dir.lerp(dirv, minf(1.0, dt * 2.5)).normalized()
				desired = e.dir * 150.0
				if e.timer <= 0.0:
					e.state = 0
					e.timer = GARGOYLE_PERCH
		PRIEST:
			if dist > 150:
				desired = dirv * e.spd
			elif dist < 105:
				desired = -dirv * e.spd
			else:
				desired = dirv.orthogonal() * e.spd * (1.0 if e.id % 2 == 0 else -1.0)
			e.timer2 += dt
			e.state = 1 if fmod(e.timer2, PRIEST_RAISE) > PRIEST_RAISE - 0.6 else 0
			if e.timer2 >= PRIEST_RAISE:
				e.timer2 -= PRIEST_RAISE
				var room := int(tune.enemy_cap) - enemies.size() - spawn_queue.size()
				var n := mini(PRIEST_RAISED, room)
				for k in n:
					var at := e.pos + Vector2.from_angle(rng.randf() * TAU) * 14.0
					at.x = clampf(at.x, G.ARENA.position.x + 8, G.ARENA.end.x - 8)
					at.y = clampf(at.y, G.ARENA.position.y + 8, G.ARENA.end.y - 4)
					spawn_enemy(SKELETON, 0, at)
				if n > 0:
					emit(EV_RAISE, e.pos.x, e.pos.y, n, 0)
	e.vel = e.vel.lerp(desired * sm, minf(1.0, dt * 10.0))
	e.pos += (e.vel + e.knock) * dt
	e.knock = e.knock.move_toward(Vector2.ZERO, dt * 600.0)
	# Separation so hordes spread into a crowd instead of a single blob.
	# Half the crowd separates each tick (alternating by id), at double strength: the same spread for half the cost.
	if e.type != BAT and e.type != WRAITH and (e.id + _tick) % 2 == 0:
		_separate(e)
	e.pos.x = clampf(e.pos.x, G.ARENA.position.x + e.r, G.ARENA.end.x - e.r)
	e.pos.y = clampf(e.pos.y, G.ARENA.position.y + e.r, G.ARENA.end.y - 2)
	# Contact damage
	for p in players.values():
		if p.alive and p.invuln <= 0.0 and p.pos.distance_to(e.pos) < e.r + 5.0:
			var dmg := e.contact
			if (e.type == ORC and e.state == 2) or (e.type == GARGOYLE and e.state == 1):
				dmg = 2
			hurt_player(p, dmg)

## Pushes `e` out of the enemies it overlaps, reading the grid cells directly (this runs for half the horde
## every tick, so it avoids _query's array).
func _separate(e: Enemy) -> void:
	var x0 := floori((e.pos.x - 16.0) / CELL)
	var y0 := floori((e.pos.y - 16.0) / CELL)
	for cx in range(x0, x0 + 2):
		for cy in range(y0, y0 + 2):
			var cell: Array = _grid.get(Vector2i(cx, cy), _NO_CELL)
			for o: Enemy in cell:
				if o == e or o.dead or o.type == BAT or o.entering:
					continue
				var dv: Vector2 = e.pos - o.pos
				var min_d: float = e.r + o.r
				var d2: float = dv.length_squared()
				if d2 < min_d * min_d and d2 > 0.0001:
					var dd: float = sqrt(d2)
					e.pos += dv / dd * (min_d - dd) * (0.5 if o.type != LICH else 1.0)

func _update_lich(e: Enemy, dt: float, tgt: Player, dirv: Vector2, dist: float) -> Vector2:
	var rage := e.hp / e.maxhp < (FINAL_RAGE if e.final else 0.5)
	var desired := Vector2.ZERO
	# Drift between waypoints in the upper half of the arena.
	if e.dir == Vector2.ZERO or e.pos.distance_to(e.dir) < 8.0:
		e.dir = Vector2(rng.randf_range(G.ARENA.position.x + 60, G.ARENA.end.x - 60),
			rng.randf_range(G.ARENA.position.y + 40, G.ARENA.get_center().y + 30))
	desired = (e.dir - e.pos).normalized() * e.spd * (1.5 if rage else 1.0)
	e.timer -= dt
	e.timer2 -= dt
	match e.state:
		0: # idle drift, then choose an attack
			if e.timer <= 0.0:
				var choices := [1, 2, 3, 4, 1, 2]
				if rage:
					choices.append(5)
				e.state = choices[rng.randi() % choices.size()]
				e.timer2 = 0.0
				e.count = 0.0
				e.timer = 2.4 if e.state == 3 else 0.6
		1: # radial bursts
			desired *= 0.3
			if e.timer2 <= 0.0:
				var n := 18 if rage else 14
				var off := rng.randf() * TAU
				for i in n:
					var a := off + i * TAU / n
					_eshot(ES_SKULL, e.pos + Vector2(0, -16), Vector2(cos(a), sin(a)) * 78.0, 5.0)
				emit(EV_ESHOT, e.pos.x, e.pos.y - 16, ES_SKULL, 1)
				e.timer2 = 0.55
				e.count += 1.0
				if e.count >= 3.0:
					e.state = 0
					e.timer = 1.4 if rage else 2.0
		2: # aimed volleys at every wizard
			if e.timer2 <= 0.0:
				for p in players.values():
					if p.alive:
						var d = (p.pos - e.pos).normalized()
						for a in [-0.18, 0.0, 0.18]:
							_eshot(ES_ORB, e.pos + Vector2(0, -16), d.rotated(a) * 120.0, 4.0)
				emit(EV_ESHOT, e.pos.x, e.pos.y - 16, ES_ORB, 1)
				e.timer2 = 0.35
				e.count += 1.0
				if e.count >= (5.0 if rage else 4.0):
					e.state = 0
					e.timer = 1.6
		3: # spiral
			desired = Vector2.ZERO
			if e.timer2 <= 0.0:
				e.timer2 = 0.07
				var base := e.t * 3.2
				var arms := 3 if rage else 2
				for i in arms:
					var a := base + i * TAU / arms
					_eshot(ES_SKULL, e.pos + Vector2(0, -16), Vector2(cos(a), sin(a)) * 85.0, 5.0)
				emit(EV_ESHOT, e.pos.x, e.pos.y - 16, ES_SKULL, 2)
			if e.timer <= 0.0:
				e.state = 0
				e.timer = 1.8
		4: # summon minions from every door
			var kinds := [SKELETON, GOBLIN, BAT] if rage else [GOBLIN, GOBLIN, SKELETON]
			for d in 4:
				spawn_enemy(kinds[rng.randi() % kinds.size()], d)
				spawn_enemy(GOBLIN, d)
			if e.final and rage:
				_spawn_elite()
			emit(EV_TELE, e.pos.x, e.pos.y - 16, 2, 0)
			e.state = 0
			e.timer = 2.5
		5: # teleport to the far side of the nearest wizard, then burst
			desired = Vector2.ZERO
			if e.timer <= 0.0 and tgt:
				var old := e.pos
				var c := G.ARENA.get_center()
				var np := c - (tgt.pos - c).limit_length(90.0)
				np.y = clampf(np.y, G.ARENA.position.y + 30, G.ARENA.end.y - 10)
				e.pos = np
				e.dir = Vector2.ZERO
				emit(EV_TELE, old.x, old.y - 16, 1, 0)
				emit(EV_TELE, np.x, np.y - 16, 1, 0)
				e.state = 1
				e.count = 1.0
				e.timer2 = 0.3
	return desired

func _eshot(kind: int, pos: Vector2, vel: Vector2, r: float) -> void:
	var s := EShot.new()
	s.kind = kind
	s.pos = pos
	s.vel = vel
	s.r = r
	eshots.append(s)

## A wraith phased out: shots fly through it and nothing hurts it.
func _faded(e: Enemy) -> bool:
	return e.type == WRAITH and e.state == 1

func _damage_enemy(e: Enemy, dmg: float, slot: int, knock: Vector2) -> void:
	if e.dead or _faded(e):
		return
	if e.type == GARGOYLE and e.state == 0:
		dmg *= STONE_DAMAGE
	var src: Player = players.get(slot)
	if src:
		dmg *= Upgrades.damage_mul(src.upgrades) * (1.0 + src.armor[Loot.ST_MIGHT] + meta_damage)
	record.add(slot, "damage", minf(dmg, maxf(0.0, e.hp)))
	record.add_source(stat_src, minf(dmg, maxf(0.0, e.hp)))
	e.hp -= dmg
	e.flash = 0.07
	e.knock += knock * _heft(e)
	emit(EV_HIT, e.pos.x, e.pos.y - e.r, e.type, slot)
	if e.hp <= 0.0:
		_kill_enemy(e, slot)

## How far knockback and pulls move an enemy: the Lich barely, orcs and gargoyles less than the rest.
func _heft(e: Enemy) -> float:
	return 0.15 if e.type == LICH else (0.4 if e.type == ORC or e.type == GARGOYLE else 1.0)

func _kill_enemy(e: Enemy, slot: int) -> void:
	e.dead = true
	var p: Player = players.get(slot)
	var base: int = STATS[e.type][3] * (ELITE_REWARD if e.elite else 1) * (FINAL_REWARD if e.final else 1)
	if p:
		p.combo += 1
		p.combo_t = 2.5
		p.kills += 1
		var mult := 1 + mini(p.combo / 10, 4)
		p.score += base * mult
		if COMBO_CALLS.has(p.combo):
			emit(EV_COMBO, e.pos.x, e.pos.y, p.combo, slot)
		record.best(slot, "best_combo", p.combo)
		if p.combo in Results.COMBO_MOMENTS:
			record.note(wave_time, Results.M_COMBO, slot, p.combo)
		if e.elite:
			record.add(slot, "elites", 1)
	emit(EV_DIE, e.pos.x, e.pos.y - e.r, e.type, slot)
	_drop_xp(e.pos, Vector2.from_angle(rng.randf() * TAU) * 25.0, XP_VALUES[e.type] * (ELITE_REWARD if e.elite else 1))
	_roll_card(e)
	if e.elite:
		for i in ELITE_GEMS:
			_drop(PK_GEM if i % 2 == 0 else PK_COIN, e.pos, Vector2.from_angle(i * TAU / ELITE_GEMS) * 70.0)
		_drop(PK_CHEST, e.pos, Vector2(0, 30), tune.chest_life, int(tune.elite_chest_luck))
		return
	match e.type:
		SLIME:
			for i in 2:
				var m := spawn_enemy(MSLIME, 0, e.pos + Vector2(-5 + i * 10, 0))
				m.knock = Vector2(-90 + i * 180, rng.randf_range(-40, 40))
			emit(EV_SPLIT, e.pos.x, e.pos.y - 4, 0, 0)
		LICH:
			boss = null
			liches_slain += 1
			record.note(wave_time, Results.M_ARCHLICH if e.final else Results.M_LICH, slot)
			for o in enemies:
				if not o.dead and o != e:
					o.dead = true
					emit(EV_DIE, o.pos.x, o.pos.y - o.r, o.type, -1)
			for s in eshots:
				s.dead = true
			for i in 14:
				_drop(PK_GEM if i % 2 == 0 else PK_COIN, e.pos, Vector2.from_angle(i * TAU / 14) * 90.0)
			_drop(PK_POTION, e.pos, Vector2(0, 40))
			for i in players.size():
				_drop(PK_CHEST, e.pos, Vector2.from_angle(PI * 0.5 + (i - (players.size() - 1) * 0.5) * 0.7) * 60.0,
					tune.chest_life, int(tune.boss_chest_luck))
			emit(EV_BOSSDIE, e.pos.x, e.pos.y - 14, slot, 1 if e.final else 0)
			if e.final:
				won = true
				victory_t = tune.victory_delay
				for q: Player in players.values():
					q.invuln = maxf(q.invuln, tune.victory_delay + 1.0)
				emit(EV_VICTORY, e.pos.x, e.pos.y, slot, 0)
			spawn_queue.clear()
			horde_budget = 0.0
			_next_group = []
			return
	_roll_drop(e)

## A kill may drop its monster's card (Cards.drop_chance): far likelier from an elite or a Lich.
func _roll_card(e: Enemy) -> void:
	if rng.randf() < Cards.drop_chance(e.type, e.elite, tune.card_chance, tune.card_elite_mul, tune.card_boss_chance):
		_drop(PK_CARD, e.pos, Vector2(0, -50), tune.chest_life, e.type)

func _roll_drop(e: Enemy) -> void:
	var lucky := rng.randf()
	if lucky < tune.ultra_drop_chance:
		_drop(PK_CHEST_ULTRA, e.pos, Vector2(0, 30), tune.chest_life, 5)
		return
	if lucky < tune.ultra_drop_chance + tune.rare_drop_chance:
		_drop(PK_CHEST_RARE, e.pos, Vector2(0, 30), tune.chest_life, 2)
		return
	var r := rng.randf()
	var big := e.type == ORC or e.type == MAGE
	var pop := Vector2.from_angle(rng.randf() * TAU) * 40.0
	if big:
		_drop(PK_GEM, e.pos, pop)
		if rng.randf() < 0.25:
			_drop(TOMES[rng.randi() % TOMES.size()], e.pos, -pop)
		return
	if r < 0.22:
		_drop(PK_COIN, e.pos, pop)
	elif r < 0.27:
		_drop(PK_GEM, e.pos, pop)
	elif r < 0.29:
		_drop(PK_POTION, e.pos, pop)
	elif r < 0.315:
		_drop(TOMES[rng.randi() % TOMES.size()], e.pos, pop)
	elif r < 0.322:
		_drop(PK_BOOTS, e.pos, pop)
	elif r < 0.33:
		_drop(PK_ORBIT, e.pos, pop)

# ================================================================ URNS ===
## Tops the urns back up to tune.urn_count, each in a band along a wall, clear of the wizards and of each other.
func _refill_urns() -> void:
	var band := G.ARENA.grow(-12.0)
	var tries := 0
	while urns.size() < int(tune.urn_count) and tries < 60:
		tries += 1
		var at := Vector2(rng.randf_range(band.position.x, band.end.x), rng.randf_range(band.position.y, band.end.y))
		match rng.randi() % 4:
			0: at.y = band.position.y + rng.randf() * 8.0
			1: at.y = band.end.y - rng.randf() * 8.0
			2: at.x = band.position.x + rng.randf() * 8.0
			_: at.x = band.end.x - rng.randf() * 8.0
		var clear := true
		for p: Player in players.values():
			if p.pos.distance_to(at) < 40.0:
				clear = false
		for u: Vector2 in urns:
			if u.distance_to(at) < 18.0:
				clear = false
		if clear:
			urns.append(at)


## A wizard's shot or a wizard walking into an urn shatters it. Shots fly on through.
func _update_urns() -> void:
	var i := urns.size() - 1
	while i >= 0:
		var u: Vector2 = urns[i]
		var hit := false
		for p: Player in players.values():
			if p.alive and p.pos.distance_to(u) < URN_R + 4.0:
				hit = true
		if not hit:
			for s: Shot in shots:
				if not s.dead and s.pos.distance_to(u + Vector2(0, -3)) < URN_R + s.r:
					hit = true
					break
		if hit:
			urns.remove_at(i)
			_break_urn(u)
		i -= 1


## What falls out of a broken urn: usually coins or nothing, sometimes a gem or potion, rarely a rare chest, and
## very rarely a monster card of any kind.
func _break_urn(at: Vector2) -> void:
	var r := rng.randf()
	var pop := Vector2(0, 30)
	var what := URN_DUST
	if r < tune.urn_card_chance:
		what = URN_CARD_DROP
		_drop(PK_CARD, at, Vector2(0, -50), tune.chest_life, Sanctum.roll_card(rng) + URN_CARD)
	elif r < tune.urn_card_chance + tune.urn_rare_chance:
		what = URN_CHEST
		_drop(PK_CHEST_RARE, at, pop, tune.chest_life, 2)
	elif r < tune.urn_card_chance + tune.urn_rare_chance + 0.06:
		what = URN_POTION
		_drop(PK_POTION, at, pop)
	elif r < tune.urn_card_chance + tune.urn_rare_chance + 0.24:
		what = URN_GEM
		_drop(PK_GEM, at, pop)
	elif r < 0.75:
		what = URN_COIN
		for k in 2:
			_drop(PK_COIN, at, Vector2.from_angle(rng.randf() * TAU) * 40.0)
	emit(EV_URN, at.x, at.y, what, 0)

## Drops an XP gem, or, with tune.xp_gem_cap gems already down, adds its XP to the nearest one (and keeps that
## one around), so a big horde cannot bury the floor in gems.
func _drop_xp(pos: Vector2, vel: Vector2, value: int) -> void:
	var count := 0
	var near: Pickup = null
	var nd := INF
	for k in pickups:
		if k.kind != PK_XP:
			continue
		count += 1
		var d := k.pos.distance_squared_to(pos)
		if d < nd:
			nd = d
			near = k
	if count >= int(tune.xp_gem_cap) and near != null:
		near.value += value
		near.life = maxf(near.life, tune.xp_gem_life * 0.5)
		return
	_drop(PK_XP, pos, vel, tune.xp_gem_life, value)

func _drop(kind: int, pos: Vector2, vel: Vector2, life: float = 9.0, value: int = 0) -> void:
	var k := Pickup.new()
	k.kind = kind
	k.value = value
	k.pos = pos
	k.vel = vel
	k.life = life
	pickups.append(k)

# ======================================================== SHOTS/PICKUPS ===
func _update_shots(dt: float) -> void:
	var bounds := G.ARENA.grow(4)
	for s in shots:
		if s.dead:
			continue
		stat_src = s.spell
		s.life -= dt
		if s.spell == SP_STAR:
			var best: Enemy = null
			var bd := 160.0
			for e in _query(s.pos, 160.0):
				if s.hits.has(e.id):
					continue
				var d = e.pos.distance_to(s.pos)
				if d < bd:
					bd = d
					best = e
			if best:
				var speed := Spells.stat(SP_STAR, "speed")
				var want := (best.pos + Vector2(0, -4) - s.pos).normalized() * speed
				s.vel = s.vel.lerp(want, minf(1.0, dt * 5.5)).normalized() * speed
		s.pos += s.vel * dt
		if s.life <= 0.0 or not bounds.has_point(s.pos):
			s.dead = true
			if s.spell == SP_FIRE:
				_explode(s)
			continue
		for e in _query(s.pos, 20.0):
			if e.dead or s.hits.has(e.id) or _faded(e):
				continue
			var hit_pos = e.pos + Vector2(0, -e.r * 0.8)
			if s.pos.distance_to(hit_pos) < s.r + e.r + 1.0:
				_shot_hit(s, e)
				break

func _shot_hit(s: Shot, e: Enemy) -> void:
	if s.spell == SP_FIRE:
		s.dead = true
		_explode(s)
		return
	_damage_enemy(e, s.dmg, s.owner, s.vel.normalized() * 70.0)
	if s.spell == SP_FROST:
		e.slow = Spells.evo_value(SP_FROST, "slow", Spells.FROST_SLOW) if s.evo else Spells.FROST_SLOW
		emit(EV_FROST, s.pos.x, s.pos.y, 0, 0)
	if s.evo and s.spell == SP_STAR:
		_frost_burst(s, e)
	if s.pierce > 0:
		s.pierce -= 1
		s.hits[e.id] = true
	else:
		s.dead = true

## Comet Rain: a star that hits bursts into ice, slowing and hurting every other enemy nearby.
func _frost_burst(s: Shot, center: Enemy) -> void:
	var radius := Spells.evo_value(SP_STAR, "burst", 0.0)
	emit(EV_FROST, s.pos.x, s.pos.y, radius, 0)
	for e in _query(s.pos, radius + 8.0):
		if e == center or e.dead or e.pos.distance_to(s.pos) > radius + e.r:
			continue
		e.slow = Spells.FROST_SLOW
		_damage_enemy(e, s.dmg * Spells.BURST_DMG, s.owner, (e.pos - s.pos).normalized() * 60.0)

func _explode(s: Shot) -> void:
	emit(EV_EXPLODE, s.pos.x, s.pos.y, 28, s.owner)
	for e in _query(s.pos, 40.0):
		var d = e.pos.distance_to(s.pos)
		if d < 28.0 + e.r:
			_damage_enemy(e, s.dmg + 1.5 * (1.0 - d / 40.0), s.owner, (e.pos - s.pos).normalized() * 160.0)
	if s.evo:
		# Thunderfire: lightning forks from the blast to the nearest survivor.
		var tgt := _nearest_enemy(s.pos, Spells.CHAIN_JUMP_RANGE)
		if tgt:
			var jumps := int(Spells.evo_value(SP_FIRE, "chain", 0.0))
			_zap_chain(s.owner, s.pos, tgt, jumps, s.dmg * Spells.CHAIN_FALLOFF, Spells.CHAIN_JUMP_RANGE, {}, Vector2.ZERO)

## Rune circles age, tick damage on every enemy standing in them, and (the Seal of Solomon) pull enemies in.
func _update_runes(dt: float) -> void:
	stat_src = SP_RUNE
	for c: Rune in runes:
		c.age += dt
		if c.pull > 0.0:
			var reach := c.r * Spells.SEAL_REACH
			for e: Enemy in _query(c.pos, reach):
				if e.entering or e.dead:
					continue
				var to := c.pos - e.pos
				var d := to.length()
				if d > reach or d < 1.0:
					continue
				e.pos += to / d * minf(d, c.pull * _heft(e) * dt)
		c.tick -= dt
		if c.tick > 0.0 or c.age > c.life:
			continue
		c.tick += Spells.RUNE_TICK
		for e: Enemy in _query(c.pos, c.r + CELL * 0.5):
			if e.pos.distance_to(c.pos) <= c.r + e.r * 0.5:
				_damage_enemy(e, c.dmg, c.owner, Vector2.ZERO)

func _update_eshots(dt: float) -> void:
	var bounds := G.ARENA.grow(6)
	for s in eshots:
		s.life -= dt
		s.pos += s.vel * dt
		if s.life <= 0.0 or not bounds.has_point(s.pos):
			s.dead = true
			continue
		for p in players.values():
			if p.alive and p.invuln <= 0.0 and s.pos.distance_to(p.pos + Vector2(0, -6)) < s.r + 4.0:
				s.dead = true
				hurt_player(p, 1)
				break

func _update_pickups(dt: float) -> void:
	for k in pickups:
		k.life -= dt
		if k.kind == PK_XP:
			_magnet_xp(k)
		k.pos += k.vel * dt
		k.vel = k.vel.move_toward(Vector2.ZERO, dt * 120.0)
		k.pos.x = clampf(k.pos.x, G.ARENA.position.x + 6, G.ARENA.end.x - 6)
		k.pos.y = clampf(k.pos.y, G.ARENA.position.y + 8, G.ARENA.end.y - 4)
		for p in players.values():
			if p.alive and p.pos.distance_to(k.pos) < 11.0:
				_collect(p, k)
				k.life = -1.0
				break
	pickups = pickups.filter(func(k): return k.life > 0.0)

## An XP gem near a wizard flies to the nearest one in reach.
func _magnet_xp(k: Pickup) -> void:
	var best: Player = null
	var bd := INF
	for p: Player in players.values():
		if not p.alive:
			continue
		var d := p.pos.distance_to(k.pos)
		if d < tune.xp_magnet_radius * Upgrades.magnet_mul(p.upgrades) and d < bd:
			bd = d
			best = p
	if best:
		k.vel = (best.pos - k.pos).normalized() * tune.xp_magnet_speed

func _collect(p: Player, k: Pickup) -> void:
	if k.kind == PK_XP:
		gain_xp(p, int(round(k.value * Upgrades.xp_mul(p.upgrades) * (1.0 + meta_xp))))
		emit(EV_PICKUP, k.pos.x, k.pos.y, k.kind, p.slot)
		return
	if k.kind == PK_CHEST or k.kind == PK_CHEST_RARE or k.kind == PK_CHEST_ULTRA:
		_open_chest(p, k)
		return
	if k.kind == PK_CARD:
		var idx := k.value % URN_CARD
		cards_found.append(idx)
		record.note(wave_time, Results.M_CARD, p.slot, idx)
		emit(EV_CARD, k.pos.x, k.pos.y, idx, p.slot + (8 if k.value >= URN_CARD else 0))
		return
	var pts := 0
	var greed: float = 1.0 + p.armor[Loot.ST_GREED] + meta_gold
	match k.kind:
		PK_COIN:
			pts = 100
			p.gold += Loot.GOLD_COIN * greed
			record.add(p.slot, "gold", Loot.GOLD_COIN * greed)
		PK_GEM:
			pts = 500
			p.gold += Loot.GOLD_GEM * greed
			record.add(p.slot, "gold", Loot.GOLD_GEM * greed)
		PK_POTION:
			p.hp = mini(p.max_hp, p.hp + 2)
		PK_TOME_FIRE, PK_TOME_FROST, PK_TOME_STORM, PK_TOME_STAR, PK_TOME_RUNE:
			# A tome grants or levels its spell weapon; one that is already maxed is worth points instead.
			var idx := Upgrades.weapon_entry(TOMES.find(k.kind) + 1)
			if Upgrades.take(p.upgrades, idx):
				_refresh_spell(p)
				emit(EV_PICK, p.pos.x, p.pos.y - 14, p.slot, idx)
			else:
				pts = 500
		PK_BOOTS:
			p.haste = 10.0
		PK_ORBIT:
			p.orbit = 12.0
	p.score += pts
	emit(EV_PICKUP, k.pos.x, k.pos.y, k.kind, p.slot)
	if pts > 0:
		emit(EV_SCORE, k.pos.x, k.pos.y - 6, pts, p.slot)

## A chest opens where it is touched: a tier (luck from the chest's value) and an item, applied at once. The
## arena plays the reel from EV_CHEST.
func _open_chest(p: Player, k: Pickup) -> void:
	var tier := Loot.roll_rarity(rng, float(k.value + meta_luck))
	if k.kind == PK_CHEST_RARE:
		tier = maxi(tier, Loot.RARE)
	elif k.kind == PK_CHEST_ULTRA:
		tier = maxi(tier, Loot.LEGENDARY)
	var idx := Loot.roll_item(rng)
	record.add(p.slot, "chests", 1)
	record.best(p.slot, "best_tier", tier)
	if tier >= Loot.LEGENDARY:
		record.note(wave_time, Results.M_CHEST, p.slot, tier)
	var v := Loot.value(idx, tier)
	if Loot.kind(idx) == Loot.KIND_ARMOR:
		var before: float = p.armor[Loot.ST_VIGOR]
		Loot.add_armor(p.armor, idx, tier)
		var hearts := int(p.armor[Loot.ST_VIGOR] - before)
		p.max_hp += hearts
		p.hp += hearts
	else:
		match Loot.effect(idx):
			Loot.FX_ELIXIR:
				p.hp = p.max_hp
			Loot.FX_NOVAS:
				p.bombs += maxi(1, int(v))
			Loot.FX_TOME:
				for i in maxi(1, int(v)):
					var owned: Array[int] = []
					for sp in Spells.COUNT:
						var lv := Upgrades.weapon_level(p.upgrades, sp)
						if lv > 0 and lv < Spells.MAX_LEVEL:
							owned.append(sp)
					if owned.is_empty():
						break
					Upgrades.take(p.upgrades, Upgrades.weapon_entry(owned[rng.randi() % owned.size()]))
				_refresh_spell(p)
			Loot.FX_INSIGHT:
				gain_xp(p, maxi(1, int(round(tune.xp_to_next(p.level) * v))))
	emit(EV_CHEST, k.pos.x, k.pos.y, p.slot, idx * 8 + tier)

# ============================================================= SHRINES ===
## Shrines appear on timers. A wizard who can pay stands on one for tune.shrine_hold seconds to bet; the gold
## goes at once, the reel plays, and the outcome lands when it stops. The team shrine bets for everybody.
func _update_shrines(dt: float) -> void:
	shrine_t -= dt
	if shrine_t <= 0.0:
		shrine_t += tune.shrine_interval
		_place_shrine(Gamble.SOLO)
	team_shrine_t -= dt
	if team_shrine_t <= 0.0:
		team_shrine_t += tune.team_shrine_interval
		_place_shrine(Gamble.TEAM)
	for sh: Shrine in shrines:
		sh.life -= dt
		var payer: Player = null
		for p: Player in players.values():
			if p.alive and p.gold >= sh.cost and p.pos.distance_to(sh.pos) < tune.shrine_radius:
				payer = p
				break
		if payer == null:
			sh.charge = maxf(0.0, sh.charge - dt * 2.0)
			continue
		if payer.slot != sh.who:
			sh.who = payer.slot
			sh.charge = 0.0
		sh.charge += dt
		if sh.charge >= tune.shrine_hold:
			_bet(sh, payer)
	shrines = shrines.filter(func(sh: Shrine) -> bool: return sh.life > 0.0)
	while not _gambles.is_empty() and _gambles[0].t <= wave_time:
		_resolve_gamble(_gambles.pop_front())

## Shrine rows as the snapshot sends them: [kind, x, y, life, charge fraction, cost].
func snapshot_shrines() -> Array:
	var out: Array = []
	for x: Shrine in shrines:
		out.append([x.kind, x.pos.x, x.pos.y, x.life, x.charge / tune.shrine_hold, x.cost])
	return out

func _place_shrine(kind: int) -> void:
	var sh := Shrine.new()
	sh.kind = kind
	sh.pos = _spot_near_party(tune.shrine_min_dist, tune.shrine_min_dist + 120.0, 30.0)
	sh.life = tune.shrine_life * (tune.team_shrine_life_mul if kind == Gamble.TEAM else 1.0)
	sh.cost = Gamble.cost(kind, wave, tune.shrine_cost_base, tune.shrine_cost_per_min, tune.team_cost_mul)
	shrines.append(sh)
	emit(EV_SHRINE_UP, sh.pos.x, sh.pos.y, kind, sh.cost)

func _bet(sh: Shrine, p: Player) -> void:
	sh.life = 0.0
	p.gold -= sh.cost
	record.add(p.slot, "bets", sh.cost)
	var outcome := Gamble.roll(rng, sh.kind)
	var reel := tune.team_reel if sh.kind == Gamble.TEAM else tune.shrine_reel
	_gambles.append({"t": wave_time + reel, "slot": p.slot, "kind": sh.kind, "outcome": outcome, "stake": sh.cost, "pos": sh.pos})
	_gambles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	emit(EV_SHRINE, sh.pos.x, sh.pos.y, p.slot, sh.kind * 16 + outcome)

func _resolve_gamble(g: Dictionary) -> void:
	var p: Player = players.get(g.slot)
	var pos: Vector2 = g.pos
	if g.kind == Gamble.TEAM:
		for q: Player in players.values():
			if g.outcome == Gamble.TO_BLESSING:
				for i in Gamble.BLESSING_LEVELS:
					gain_xp(q, maxi(1, tune.xp_to_next(q.level) - q.xp))
			elif q.alive:
				q.hp = maxi(1, q.hp - 1)
				q.flash = 0.3
				_spawn_elite()
	elif p != null:
		match int(g.outcome):
			Gamble.SO_JACKPOT:
				_drop(PK_CHEST, pos, Vector2.ZERO, tune.chest_life, int(tune.boss_chest_luck))
			Gamble.SO_CHEST:
				_drop(PK_CHEST, pos, Vector2.ZERO, tune.chest_life, int(tune.elite_chest_luck))
			Gamble.SO_DOUBLE:
				p.gold += g.stake * 2
			Gamble.SO_CURSE:
				if p.alive:
					p.hp = maxi(1, p.hp - 1)
					p.flash = 0.3
	if g.kind == Gamble.TEAM:
		record.note(wave_time, Results.M_BLESSING if g.outcome == Gamble.TO_BLESSING else Results.M_CURSE, g.slot)
	elif g.outcome == Gamble.SO_JACKPOT:
		record.note(wave_time, Results.M_JACKPOT, g.slot)
	emit(EV_GAMBLE, pos.x, pos.y, g.slot, int(g.kind) * 16 + int(g.outcome))

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
	return hash([snapshot(), wave, phase, total_score(), rng.state, horde_budget])

# ============================================================ SNAPSHOT ===
func _snapshot_urns() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for u: Vector2 in urns:
		out.append_array([u.x, u.y])
	return out

func snapshot() -> Dictionary:
	var pl := PackedFloat32Array()
	for p in players.values():
		pl.append_array([p.slot, p.pos.x, p.pos.y, p.aim.x, p.aim.y, p.hp, p.lives,
			1.0 if p.alive else 0.0, p.invuln, p.spell, p.wizard, p.bombs, p.score,
			p.combo, p.haste, p.orbit, p.orbit_ang, p.flash, 1.0 if p.moving else 0.0,
			p.xp, tune.xp_to_next(p.level), p.level, p.offer])
		for c in 3:
			var idx: int = p.choices[c] if c < p.choices.size() else -1
			pl.append(idx)
			pl.append(Upgrades.level_of(p.upgrades, idx) + 1 if idx >= 0 else 0)
		for sp in Spells.COUNT:
			pl.append(_weapon_snap(p, sp))
		pl.append(floorf(p.gold))
		pl.append(p.max_hp)
	var en := PackedFloat32Array()
	for e in enemies:
		en.append_array([e.id, e.type, e.pos.x, e.pos.y, e.flash, e.state, e.hp / e.maxhp, e.slow, 2.0 if e.final else (1.0 if e.elite else 0.0)])
	var sh := PackedFloat32Array()
	for s in shots:
		sh.append_array([s.kind, s.pos.x, s.pos.y, s.vel.x, s.vel.y, s.owner])
	var rn := PackedFloat32Array()
	for c: Rune in runes:
		rn.append_array([c.pos.x, c.pos.y, c.r, c.age, c.life, c.owner, 1.0 if c.evo else 0.0])
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
	for row: Array in snapshot_shrines():
		shr.append_array(row)
	return {
		"p": pl, "e": en, "s": sh, "r": rn, "es": es, "k": pk, "sh": shr, "u": _snapshot_urns(),
		"w": PackedFloat32Array([wave, phase, phase_t, bf, door_open[0], door_open[1], door_open[2], door_open[3], wave_time,
			1.0 if boss != null and boss.final else 0.0]),
	}

class_name SmashBot
extends RefCounted
## Play-bot brain for one wizard. Works on plain positions, so the arena (from its view state, also on LAN
## clients) and headless sims (straight from World) drive wizards with the same logic.
## Output matches PlayerInput.read: [move_x, move_y, aim_x, aim_y, fire, nova_count]; decide_in_world and
## with_pick add [pick, offer] for level-ups.
##
## How it decides (docs/bots.md): a few times a second it "thinks". It senses the nearest threats and shots,
## picks a goal (a pickup worth the risk, a shrine it can pay), then scores 16 headings plus standing still by
## walking each a short way ahead against where enemies and shots will be. It holds that decision until the next
## think, and a decision only reaches the hands after the persona's reaction delay. Personas (PERSONAS) set how
## well it sees, how far ahead it looks, how greedy it is, when it novas and how it picks cards.

const NOVICE := 0
const CASUAL := 1
const VETERAN := 2

## Level-up pick policies.
const PICK_SHINY := 0 # what is new and shiny
const PICK_DAMAGE := 1 # damage first
const PICK_PLAN := 2 # plan an evolution (the spell plus its partner) and finish it

## The persona table. react: seconds between sensing and acting. hz: thinks per second. look: lookahead, s.
## track / shots: how many threats and enemy shots it keeps an eye on. sense: how far it looks, px. rear: share
## of `sense` at which it still notices a shot coming from behind (0 = only what it faces). greed: how much danger
## it accepts for a pickup (0..1). xp: how much it values XP motes (a veteran knows levels are power). caution: weight on enemy danger. margin: px it keeps from an enemy's body.
## noise: random error on each heading's score. turn: fastest turn of its heading, rad/s. nova_hp: it novas when
## cornered at this many hearts or fewer. nova_forget: chance it forgets the nova in a panic. nova_save: novas to
## save a heart from a shot volley or a closing ring even above nova_hp. band: [near, far] range it keeps from a
## boss (0 = none). pick: the level-up policy.
const PERSONAS: Array = [
	{"name": "novice", "react": 0.38, "hz": 10.0, "look": 0.35, "track": 6, "shots": 6, "sense": 110.0, "rear": 0.15,
		"greed": 0.7, "xp": 1.0, "caution": 0.7, "margin": 14.0, "noise": 0.5, "turn": 9.0, "nova_hp": 1, "nova_forget": 0.6,
		"nova_save": false, "band": [0.0, 0.0], "pick": PICK_SHINY},
	{"name": "casual", "react": 0.22, "hz": 12.0, "look": 0.5, "track": 12, "shots": 12, "sense": 140.0, "rear": 0.5,
		"greed": 0.5, "xp": 1.2, "caution": 1.0, "margin": 19.0, "noise": 0.16, "turn": 14.0, "nova_hp": 2, "nova_forget": 0.2,
		"nova_save": false, "band": [60.0, 150.0], "pick": PICK_DAMAGE},
	{"name": "veteran", "react": 0.15, "hz": 15.0, "look": 0.75, "track": 16, "shots": 16, "sense": 150.0, "rear": 1.0,
		"greed": 0.6, "xp": 1.8, "caution": 1.1, "margin": 22.0, "noise": 0.05, "turn": 20.0, "nova_hp": 2, "nova_forget": 0.0,
		"nova_save": true, "band": [80.0, 160.0], "pick": PICK_PLAN},
]

## Scoring weights, shared by every persona (a persona changes what the bot sees, not what it values).
const W_DANGER: float = 5.0
const W_SHOT: float = 7.0
const W_OPEN: float = 0.6
const W_WALL: float = 3.0
const W_LEASH: float = 4.0
const W_GOAL: float = 1.6
const W_ANCHOR: float = 0.7
const W_KITE: float = 0.35
const W_MATE: float = 1.6
const W_BOSS: float = 1.0
const W_KEEP: float = 0.45
const W_HAZARD: float = 6.0 # hazard rows (Hazards.steer): leaning out of a warned or hot row, never walking into one
const W_STAND: float = 0.15 # standing still gets nothing from the keep bonus unless it was already standing
## Shapes of the scoring terms, px.
const SHOT_MARGIN: float = 9.0
## Share of the danger beyond the worst single contact that still counts.
const CROWD_SHARE: float = 0.35
const OPEN_RADIUS: float = 46.0
const WALL_MARGIN: float = 18.0
const LEASH_MARGIN: float = 24.0
const MATE_ROOM: float = 42.0
const ANCHOR_SOLO: float = 140.0 # solo: free roam this far from the arena centre
const ANCHOR_PARTY: float = 70.0 # party: free roam this far from the wizard's lane beside the party centre
const LANE: float = 46.0
const PICKUP_RISK_R: float = 42.0
const AIM_RANGE: float = 210.0
## A think whose best heading still scores this much danger means the wizard is cornered.
const CORNERED: float = 2.2
## Seconds from now at which a heading starts to count (see _think).
const REACT_STEP: float = 0.08
## The arena a wizard may stand in (World clamps to G.ARENA shrunk by these) and its default walk speed.
const WALK_SPEED: float = 102.0
const DIR_COUNT := 16
## Hit offsets in World: an enemy shot hits the chest (pos + CHEST), a body touches at e.r + BODY.
const CHEST := Vector2(0, -6)
const BODY: float = 5.0

## Pickup worth by World.PK_* (index), before distance and risk.
const PICKUP_VALUE: Array[float] = [0.5, 1.0, 0.0, 2.0, 2.0, 2.0, 2.0, 1.0, 1.5, 0.8, 3.0, 2.0, 2.5, 3.5, 4.0, 4.0]

## Level-up pick policy: the first of these the offer contains. Damage and cast rate first, as a player would.
## Evolutions first, then spell weapons (area spells before the single bolt), then the stat upgrades.
const PICK_PRIORITY: Array[int] = [Upgrades.E_ARCANE, Upgrades.E_FIRE, Upgrades.E_FROST,
	Upgrades.E_STORM, Upgrades.E_STAR, Upgrades.E_RUNE, Upgrades.E_BONE, Upgrades.E_CANDLE, Upgrades.E_CLEAVE,
	Upgrades.W_FIRE, Upgrades.W_STORM, Upgrades.W_STAR, Upgrades.W_RUNE, Upgrades.W_BONE, Upgrades.W_FROST,
	Upgrades.W_CANDLE, Upgrades.W_ARCANE,
	Upgrades.POWER, Upgrades.QUICK, Upgrades.SWIFT, Upgrades.MAGNET,
	Upgrades.WISDOM, Upgrades.REGEN, Upgrades.LIFE, Upgrades.NOVA]

## How much a seasoned player likes a passive, by catalogue key (unknown keys: 10).
## The casual takes the arcana that completes a pair ahead of everything but an evolution once the pair's spell is at
## this level: sooner, the arcana costs her the spell levels that keep her alive in the first minutes.
const PAIR_FROM_LEVEL: int = 3
## THE STAR (+1 / +2 missiles for every spell) and THE EMPRESS (10 / 20 / 30% wider areas) complete no pair yet, and an
## arcana slot filled in the first minutes is one STRENGTH or a pair's arcana cannot have: both under THE MAGICIAN.
## THE STAR before THE EMPRESS, by what each adds in a crowd of 40 (the A4 balance review: THE STAR I adds ARCANE BOLT
## +34%, FIREBALL +49%, RUNE CIRCLE +28%; THE EMPRESS I adds FIREBALL +16%, RUNE CIRCLE +13% and nothing to the
## bolts, chains and stars): THE STAR over a lone arcana, THE EMPRESS only over the weakest.
const PASSIVE_TASTE: Dictionary = {"power": 55.0, "quick": 52.0, "life": 30.0, "regen": 26.0, "swift": 24.0,
	"magnet": 20.0, "wisdom": 15.0, "nova": 14.0, "justice": 30.0, "lovers": 28.0, "star": 32.0, "empress": 22.0}

## A shrine the bot can pay for pulls it from this far.
const SHRINE_RANGE: float = 220.0
const SHRINE_VALUE: float = 2.5
## On a shrine this close (World counts tune.shrine_radius, 14 px by default) the bot stands still to bet.
const SHRINE_STAND: float = 12.0
## Seconds a bot stands in a team shrine whose pot does not grow (no partner came) before she gives it up for good.
const SHRINE_PATIENCE: float = 4.0

## Apprentices (computer wizards that fill a seat; WorldApprentices drives them inside World.step): they decide
## every APPRENTICE_TICKS ticks of 60 Hz, all of a World's apprentices on one shared sensing context
## (shared_senses), with the casual persona's eyes and hands. What an apprentice may pick up (the World enforces
## the same rule): XP, coins and gems (the gold goes to the nearest human), boots and the rune shield, and a potion
## only at the World's apprentice_potion_hp hearts or fewer while no standing human is hurt.
const APPRENTICE_TICKS := 3
const APPRENTICE_KINDS: Array[int] = [World.PK_XP, World.PK_COIN, World.PK_GEM, World.PK_BOOTS, World.PK_ORBIT, World.PK_POTION,
	World.PK_TOME_PARTY] # the party tome is everyone's: an apprentice may fetch it
## An answered call (a fallen human pressed her nova) pulls this much harder than a rescue the bot chose itself.
const CALL_VALUE: float = 4.5

## Class play (docs/bots.md "Class play"): a wizard with a hero plays its role and uses the skill on its nova button
## for what it does. A wizard with no hero, and a MAGE, play as before (NOVA, ROLE_PLAY's damage row is neutral).
## By Classes.ROLE_*: caution and margin multiply the persona's, kite the circling bonus. A tank and a healer play
## their role only beside a teammate; solo they keep the damage row (but a solo archer still keeps range, and a
## melee hero, MELEE_SPOT, plays its row solo too).
const ROLE_PLAY: Array = [
	{"caution": 1.0, "margin": 1.0, "kite": 1.0, "party_only": false}, # DAMAGE: as before
	{"caution": 0.5, "margin": 0.7, "kite": 0.0, "party_only": true}, # TANK: wades in, never kites away
	{"caution": 1.15, "margin": 1.5, "kite": 1.0, "party_only": false}, # RANGED: keeps range
	{"caution": 1.2, "margin": 1.25, "kite": 1.0, "party_only": true}, # HEALER: stays out of the front
	{"caution": 0.6, "margin": 0.8, "kite": 0.0, "party_only": true}, # TANK AND SUPPORT (paladin): a tank
]
## While a skill keeps it unhurt (Player.invuln) a classed bot minds enemy bodies this much.
const UNHURT_CAUTION: float = 0.3
## A tank guards the ally with the most enemies within GUARD_R (the weakest wins a tie: GUARD_WEAK per missing share
## of her hearts), standing GUARD_GAP px from her toward that crowd (at most at the crowd's centre); the pull is
## GUARD_VALUE (a pickup's scale).
const GUARD_R: float = 90.0
const GUARD_GAP: float = 65.0
const GUARD_WEAK: float = 2.0
const GUARD_VALUE: float = 2.2
## A healer keeps the most hurt ally within HEAL_REACH px (her light is a zone near her), on the far side of her from
## the enemies, HEAL_SPOT of the reach away; the pull is HEAL_VALUE.
const HEAL_REACH: float = 40.0
const HEAL_SPOT: float = 0.6
const HEAL_VALUE: float = 2.0
## A hero whose class weapon is a sweep (the KNIGHT's CLEAVE) fights in melee, solo too: it plays its role row
## beside a teammate or not, and when no stronger goal pulls it walks to MELEE_SPOT of the sweep's reach from the
## nearest enemy, on its own side (pull MELEE_VALUE), so the swing reaches the group instead of the air.
const MELEE_SPOT: float = 0.6
const MELEE_VALUE: float = 1.5
## A melee hero keeps the boss between MELEE_BAND x its reach (in place of the persona's band), so the sweep reaches
## it; the persona's band still says whether it minds the boss's range at all.
const MELEE_BAND := Vector2(0.6, 1.4)
## PROVOKE: at least PROVOKE_CROWD enemies within its radius that are within ALLY_NEAR px of an ally, or the boss
## within BOSS_ON_ALLY px of an ally while within the radius.
const PROVOKE_CROWD := 3
const ALLY_NEAR: float = 40.0
const BOSS_ON_ALLY: float = 40.0
## VOLLEY: at least VOLLEY_CROWD enemies within VOLLEY_R px and cornered, or cornered at the persona's nova hearts.
const VOLLEY_CROWD := 4
const VOLLEY_R: float = 40.0
## SANCTUARY: hearts it would heal (each standing hero's missing ones, up to its heal) plus RISE_WORTH per fallen ally
## in its radius, at least the heal solo and the heal + SANCTUARY_PARTY_EXTRA beside a teammate; or any hero at
## LAST_HEART hearts with a heart to gain.
const RISE_WORTH: float = 4.0
const SANCTUARY_PARTY_EXTRA: float = 1.0
const LAST_HEART := 1
## AEGIS: at least AEGIS_HEROES heroes within its radius about to be hit (an enemy body within HIT_SOON px of
## touching, or the boss within BOSS_ON_ALLY), or one at LAST_HEART hearts.
const AEGIS_HEROES := 2
const HIT_SOON: float = 10.0
## After a skill the bot leaves the button alone for the skill's taunt or safe seconds, at least SKILL_GAP, plus its
## reaction delay (it sees the effect only then).
const SKILL_GAP: float = 0.6
## A forgotten skill comes back to mind this many seconds later if the chance is still there.
const FORGET_HOLD: float = 1.0

static var _dirs: PackedVector2Array = PackedVector2Array()

var rng := RandomNumberGenerator.new()
var nova_count: int = 0
var persona: int = CASUAL

# Persona values, copied once.
var _react: float
var _interval: float
var _look: float
var _track: int
var _shots_max: int
var _sense: float
var _rear: float
var _greed: float
var _xp_love: float
var _caution: float
var _margin: float
var _noise: float
var _turn: float
var _nova_hp: int
var _nova_forget: float
var _nova_save: bool
var _band: Vector2
var _pick: int

# Senses, refilled on each think (fixed buffers: nothing is allocated while scoring).
var _tp := PackedVector2Array()
var _tv := PackedVector2Array()
var _tr := PackedFloat32Array()
var _td := PackedFloat32Array() # squared distances, to replace the farthest
var _tn: int = 0
var _tfd: float = 0.0
var _tfi: int = 0
var _sense2: float = 0.0
var _sp := PackedVector2Array()
var _sv := PackedVector2Array()
var _sr := PackedFloat32Array()
var _sd := PackedFloat32Array()
var _sn: int = 0
var _sfd: float = 0.0
var _sfi: int = 0
var _mates := PackedVector2Array()
var _near := Vector2.INF # nearest enemy
var _nd: float = INF
var _boss := Vector2.INF
var _hz := PackedFloat32Array() # hazard rows, Hazards.pack layout (empty: none)
var _goal := Vector2.INF
var _goal_stand: bool = false # a shrine: stand on it
var _shrine_quit: Array[Vector2] = [] # team shrines she gave up waiting at, until a partner stands in one (shrine_pick)
var _wait_at := Vector2.INF # the team shrine she is waiting at
var _wait_frac: float = -1.0 # its pot when it last grew
var _wait_stood: float = 0.0 # seconds stood there since it last grew
var _wait_last: float = 0.0 # the time of the last shrine_pick
var _arena := Rect2(25, 44, 750, 392) # G.ARENA shrunk to where a wizard's feet may go
var _leash := Rect2(-1e6, -1e6, 2e6, 2e6)
var _anchor := Vector2.ZERO
var _anchor_r: float = ANCHOR_SOLO
var _speed: float = WALK_SPEED
var _hp: int = 5
var _max_hp: int = 5
var _bombs: int = 0
var _facing := Vector2.DOWN

# Decisions: the one the hands carry out, and those still on their way (reaction delay).
var _dir := Vector2.ZERO
var _spin: float = 1.0
var _next_think: float = -1.0
var _out := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var _q_t: Array[float] = []
var _q_out: Array[PackedFloat32Array] = []
var _q_nova: Array[bool] = []
var _panic: bool = false # cornered on the last think (one nova decision per panic)
var _started: bool = false

## True for an apprentice's brain (make_apprentice): no shrines, its own pickup rules, it answers calls.
var apprentice: bool = false
var _human_hurt: bool = false
var _potion_hp: int = 2
var _answering: Dictionary = {} # slot -> true: fallen humans whose call this apprentice is answering

# Class play, read from the World on each think (decide_in_world, apprentice_input).
var _class_play: bool = false # a hero other than a MAGE
var _skill: int = Classes.SK_NOVA
var _role: int = Classes.ROLE_DAMAGE
var _role_row: Dictionary = ROLE_PLAY[Classes.ROLE_DAMAGE]
var _melee_r: float = 0.0 # the reach of a class weapon that is a sweep (0: none; it does not fight in melee)
var _unhurt: bool = false
var _mate_hp := PackedInt32Array() # parallel to _mates
var _mate_max := PackedInt32Array()
var _fallen_at: Array = [] # fallen allies' positions (shared_senses)
var _skill_until: float = -1.0 # the button is left alone until then
var _skill_retry: float = -1.0 # the persona forgot the skill on this chance: it may remember from then on
var _volley_dir := Vector2.ZERO # the roll's heading, set when a VOLLEY is chosen

## Read-only diagnostics of the last think (tests, tools).
var last_danger: float = 0.0
var thinks: int = 0


func _init(seed_value: int = 1, persona_id: int = CASUAL) -> void:
	rng.seed = seed_value
	persona = clampi(persona_id, NOVICE, VETERAN)
	var p: Dictionary = PERSONAS[persona]
	_react = float(p.react)
	_interval = 1.0 / float(p.hz)
	_look = float(p.look)
	_track = int(p.track)
	_shots_max = int(p.shots)
	_sense = float(p.sense)
	_rear = float(p.rear)
	_greed = float(p.greed)
	_xp_love = float(p.xp)
	_caution = float(p.caution)
	_margin = float(p.margin)
	_noise = float(p.noise)
	_turn = float(p.turn)
	_nova_hp = int(p.nova_hp)
	_nova_forget = float(p.nova_forget)
	_nova_save = bool(p.nova_save)
	_band = Vector2(float(p.band[0]), float(p.band[1]))
	_pick = int(p.pick)
	_tp.resize(_track)
	_tv.resize(_track)
	_tr.resize(_track)
	_td.resize(_track)
	_sense2 = _sense * _sense
	_sp.resize(_shots_max)
	_sv.resize(_shots_max)
	_sr.resize(_shots_max)
	_sd.resize(_shots_max)
	_spin = 1.0 if rng.randf() < 0.5 else -1.0
	if _dirs.is_empty():
		for i: int in range(DIR_COUNT):
			_dirs.append(Vector2.from_angle(i * TAU / DIR_COUNT))


static func persona_from_name(n: String) -> int:
	for i: int in range(PERSONAS.size()):
		if PERSONAS[i].name == n.to_lower():
			return i
	return -1


static func persona_name(id: int) -> String:
	return String(PERSONAS[clampi(id, 0, PERSONAS.size() - 1)].name)


## True when a decide call at `time` would think (and so read its senses); otherwise it repeats its last decision.
func wants_senses(time: float) -> bool:
	return not _started or time >= _next_think


## One tick of input. `center` is the arena centre (the solo bot roams around it). `goal` is a shrine the bot can
## afford (Vector2.INF for none): it walks there and stands to bet, still dodging. `ctx` adds what a person would
## also see (all keys optional): "hp", "max_hp", "bombs", "speed", "enemy_vel" and "enemy_r" (parallel to
## `enemies`), "shot_vel" and "shot_r" (parallel to `enemy_shots`), "pickup_kinds" (World.PK_*, parallel to
## `pickups`), "mates" (living teammates' positions), "party" (the party centre), "arena" (Rect2 the feet may
## stand in), "leash" (Rect2 the leash allows), "boss" (Vector2 or INF), "fallen" (fallen allies' positions).
func decide(slot: int, me: Vector2, center: Vector2, time: float, enemies: Array[Vector2],
		enemy_shots: Array[Vector2], pickups: Array[Vector2], goal: Vector2 = Vector2.INF,
		ctx: Dictionary = {}) -> PackedFloat32Array:
	if wants_senses(time):
		_hp = int(ctx.get("hp", 5))
		_max_hp = int(ctx.get("max_hp", maxi(_hp, 5)))
		_bombs = int(ctx.get("bombs", 2))
		_speed = float(ctx.get("speed", WALK_SPEED))
		_arena = ctx.get("arena", Rect2(center - Vector2(375, 196), Vector2(750, 392)))
		_leash = ctx.get("leash", Rect2(-1e6, -1e6, 2e6, 2e6))
		_boss = ctx.get("boss", Vector2.INF)
		_hz = ctx.get("hz", PackedFloat32Array())
		var ev: Array = ctx.get("enemy_vel", [])
		var er: Array = ctx.get("enemy_r", [])
		_begin_senses()
		for i: int in range(enemies.size()):
			_sense_enemy(me, enemies[i], ev[i] if i < ev.size() else Vector2.ZERO, float(er[i]) if i < er.size() else 5.0)
		var sv: Array = ctx.get("shot_vel", [])
		var sr: Array = ctx.get("shot_r", [])
		for i: int in range(enemy_shots.size()):
			_sense_shot(me, enemy_shots[i], sv[i] if i < sv.size() else Vector2.ZERO, float(sr[i]) if i < sr.size() else 3.0)
		_mates.clear()
		for m: Variant in ctx.get("mates", []):
			_mates.append(m)
		var party: Vector2 = ctx.get("party", me)
		_set_anchor(slot, party if not _mates.is_empty() else center)
		var kinds: Array = ctx.get("pickup_kinds", [])
		_begin_goal()
		for i: int in range(pickups.size()):
			_consider_pickup(me, pickups[i], int(kinds[i]) if i < kinds.size() else World.PK_XP)
		if goal.is_finite():
			_consider_shrine(me, goal)
		_consider_rescue(me, ctx.get("fallen", []))
		_think(me, time)
	return _held(time)


## Same decision read straight from the simulation (sims, tests, headless bot runs), with the persona's picks.
func decide_in_world(world: World, slot: int) -> PackedFloat32Array:
	var p: World.Player = world.players.get(slot)
	if p == null:
		return PackedFloat32Array([0, 0, 0, 0, 0, nova_count])
	if not p.alive:
		return _with_my_pick(_spirit_input(world, p), p)
	if wants_senses(world.time):
		_sense_world(world, p)
		_think(p.pos, world.time)
	return _with_my_pick(_held(world.time), p)


## An apprentice's brain: the casual persona, thinking every APPRENTICE_TICKS ticks.
static func make_apprentice(seed_value: int) -> SmashBot:
	var b := SmashBot.new(seed_value, CASUAL)
	b.apprentice = true
	b._interval = APPRENTICE_TICKS / 60.0
	return b


## One tick of an apprentice's input. `ctx` is the World's shared_senses on a deciding tick, empty on the others
## (the hands carry out the last decision). No pick fields: World picks for an apprentice when it deals.
func apprentice_input(w: World, p: World.Player, ctx: Dictionary) -> PackedFloat32Array:
	if not p.alive:
		return _spirit_input(w, p)
	if not ctx.is_empty():
		_sense_from(w, p, ctx)
		_think(p.pos, w.time)
	return _held(w.time)


## What every bot of a World senses alike, worked out once per deciding tick: the living wizards, hazard rows,
## the boss, shrine rows, the fallen (positions, slots and who is calling) and whether a standing human is hurt.
static func shared_senses(w: World) -> Dictionary:
	var alive: Array[World.Player] = []
	var fallen: Array = []
	var fallen_slots: Array[int] = []
	var calling: Array[int] = []
	var hurt := false
	for q: World.Player in w.players.values():
		if q.alive:
			alive.append(q)
			if not q.ai and q.hp < q.max_hp:
				hurt = true
		elif q.down:
			fallen.append(q.pos)
			fallen_slots.append(q.slot)
			if not q.ai and q.call_t > 0.0:
				calling.append(q.slot)
	return {
		"alive": alive, "fallen": fallen, "fallen_slots": fallen_slots, "calling": calling, "human_hurt": hurt,
		"hz": Hazards.pack(w.hazards) if not w.hazards.is_empty() else PackedFloat32Array(),
		"boss": w.boss.pos if w.boss != null and not w.boss.dead else Vector2.INF,
		"shrines": w.snapshot_shrines() if not w.shrines.is_empty() else [],
	}


## Which card to take from an offer (an index into `choices`), or -1 for an empty offer.
static func choose_pick(choices: Array[int]) -> int:
	for want: int in PICK_PRIORITY:
		var at: int = choices.find(want)
		if at >= 0:
			return at
	return 0 if not choices.is_empty() else -1


## Appends the pick fields [pick index, offer id] that World reads at input[6] and input[7].
static func with_pick(inp: PackedFloat32Array, choices: Array[int], offer: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = inp.duplicate()
	out.append(choose_pick(choices))
	out.append(offer)
	return out


## The persona's card from an offer, given the wizard's upgrades {index: level}; -1 for an empty offer.
func pick_card(choices: Array[int], levels: Dictionary) -> int:
	if choices.is_empty():
		return -1
	var best: int = 0
	var bs: float = -INF
	for i: int in range(choices.size()):
		var s: float = _card_score(choices[i], levels)
		if s > bs:
			bs = s
			best = i
	return best


## The nearest shrine in reach the bot may pay, from shrine rows [kind, x, y, life, charge, cost, still needed], or
## INF. A solo shrine: her `gold` pays it all. A team shrine: she has gold and the living human wizards' gold
## together (`table_gold`, hers in it) covers what the pot still lacks. Rows at a position in `skip` are left out.
static func shrine_goal(me: Vector2, gold: float, rows: Array, table_gold: float, skip: Array[Vector2] = []) -> Vector2:
	var best := Vector2.INF
	var bd: float = SHRINE_RANGE
	for r: Array in rows:
		var at := Vector2(r[1], r[2])
		var can: bool = gold >= float(r[5])
		if int(r[0]) == Gamble.TEAM:
			can = gold > 0.0 and table_gold >= float(r[5]) * (1.0 - float(r[4]))
		if can and at.distance_to(me) < bd and not skip.has(at):
			bd = at.distance_to(me)
			best = at
	return best


## shrine_goal with her patience: standing in a team shrine whose pot has not grown for SHRINE_PATIENCE seconds (of
## her standing there), she gives that shrine up, so she never waits forever for a partner. She takes it up again
## once the row says a partner stands in it (or she is the last wizard left): it needs nobody more while she stands
## there, at most one more while she is away. `time` is the clock the decisions run on (World.time, or the view's).
func shrine_pick(me: Vector2, gold: float, table_gold: float, rows: Array, time: float) -> Vector2:
	var dt: float = maxf(0.0, time - _wait_last)
	_wait_last = time
	var live: Array[Vector2] = []
	for r: Array in rows:
		var at := Vector2(r[1], r[2])
		live.append(at)
		if int(r[0]) != Gamble.TEAM:
			continue
		var standing: bool = me.distance_to(at) < SHRINE_STAND
		if _shrine_quit.has(at):
			if int(r[6]) + int(standing) > 1:
				continue
			_shrine_quit.erase(at)
			if _wait_at == at:
				_wait_at = Vector2.INF # her patience there starts over
		if not standing:
			continue
		var frac: float = r[4]
		if at != _wait_at or frac > _wait_frac:
			_wait_at = at
			_wait_frac = frac
			_wait_stood = 0.0
		else:
			_wait_stood += dt
			if _wait_stood >= SHRINE_PATIENCE:
				_shrine_quit.append(at)
	_shrine_quit.assign(_shrine_quit.filter(func(q: Vector2) -> bool: return live.has(q)))
	return shrine_goal(me, gold, rows, table_gold, _shrine_quit)


## The gold of the living human wizards together, from the view's player dictionaries (Arena.vp values).
static func table_gold_of_views(views: Array) -> float:
	var sum: float = 0.0
	for q: Dictionary in views:
		if q.get("alive", true) and not q.get("ai", false):
			sum += float(q.get("gold", 0))
	return sum


# ============================================================== SENSES ===
func _begin_senses() -> void:
	_tn = 0
	_sn = 0
	_near = Vector2.INF
	_nd = INF
	if _dir != Vector2.ZERO:
		_facing = _dir
	elif _out[2] != 0.0 or _out[3] != 0.0:
		_facing = Vector2(_out[2], _out[3]).normalized()


## Keeps the `_track` nearest enemies within `_sense`.
func _sense_enemy(me: Vector2, pos: Vector2, vel: Vector2, r: float) -> void:
	var d2: float = pos.distance_squared_to(me)
	if d2 < _nd * _nd:
		_nd = sqrt(d2)
		_near = pos
	if d2 > _sense2:
		return
	var at: int = _tn
	if _tn < _track:
		_tn += 1
	elif d2 < _tfd:
		at = _tfi
	else:
		return
	_tp[at] = pos
	_tv[at] = vel
	_tr[at] = r
	_td[at] = d2
	if _tn == _track:
		_tfd = -1.0
		for k: int in range(_tn):
			if _td[k] > _tfd:
				_tfd = _td[k]
				_tfi = k


## Keeps the `_shots_max` nearest enemy shots it can notice: those behind it only up close (persona `rear`).
func _sense_shot(me: Vector2, pos: Vector2, vel: Vector2, r: float) -> void:
	var rel: Vector2 = pos - me
	var d2: float = rel.length_squared()
	var reach: float = _sense * 0.85
	if d2 > reach * reach:
		return
	if rel.dot(_facing) < 0.0 and d2 > (reach * _rear) * (reach * _rear):
		return
	# A shot flying away from the wizard is no threat.
	if vel.dot(-rel) < 0.0 and d2 > 400.0:
		return
	var at: int = _sn
	if _sn < _shots_max:
		_sn += 1
	elif d2 < _sfd:
		at = _sfi
	else:
		return
	_sp[at] = pos
	_sv[at] = vel
	_sr[at] = r
	_sd[at] = d2
	if _sn == _shots_max:
		_sfd = -1.0
		for k: int in range(_sn):
			if _sd[k] > _sfd:
				_sfd = _sd[k]
				_sfi = k


func _set_anchor(slot: int, party: Vector2) -> void:
	if _mates.is_empty():
		_anchor = party
		_anchor_r = ANCHOR_SOLO
	else:
		# Each wizard keeps its own lane beside the party centre, so a party does not stack on one spot.
		_anchor = party + Vector2.from_angle(slot * TAU / 4.0 + PI * 0.25) * LANE
		_anchor_r = ANCHOR_PARTY


var _goal_best: float = 0.0
var _goal_prev := Vector2.INF


func _begin_goal() -> void:
	_goal_prev = _goal
	_goal = Vector2.INF
	_goal_stand = false
	_goal_best = 0.0


func _pickup_worth(kind: int) -> float:
	if apprentice and not APPRENTICE_KINDS.has(kind):
		return 0.0
	if apprentice and kind == World.PK_POTION and (_hp > _potion_hp or _human_hurt):
		return 0.0
	if kind == World.PK_POTION:
		var missing: int = _max_hp - _hp
		# A potion heals 2: a person fetches it when hurt, sooner the more hurt, and never at full health.
		return 0.0 if missing <= 0 else 1.2 + 1.4 * float(missing)
	if kind == World.PK_XP:
		return PICKUP_VALUE[kind] * _xp_love
	return PICKUP_VALUE[kind] if kind >= 0 and kind < PICKUP_VALUE.size() else 0.5


func _consider_pickup(me: Vector2, at: Vector2, kind: int) -> void:
	var worth: float = _pickup_worth(kind)
	if worth <= 0.0:
		return
	var d: float = at.distance_to(me)
	if d > _sense * 1.3:
		return
	var risk: float = 0.0
	for k: int in range(_tn):
		var e: float = _tp[k].distance_to(at)
		if e < PICKUP_RISK_R:
			risk += 1.0 - e / PICKUP_RISK_R
	var u: float = worth / (1.0 + d / 60.0) - risk * (1.0 - _greed) * 1.5
	if _goal_prev.is_finite() and at.distance_to(_goal_prev) < 6.0:
		u *= 1.3 # people finish the fetch they started
	if u > _goal_best:
		_goal_best = u
		_goal = at
		_goal_stand = false


func _consider_shrine(me: Vector2, at: Vector2) -> void:
	var risk: float = 0.0
	for k: int in range(_tn):
		var e: float = _tp[k].distance_to(at)
		if e < PICKUP_RISK_R:
			risk += 1.0 - e / PICKUP_RISK_R
	var u: float = SHRINE_VALUE / (1.0 + at.distance_to(me) / 120.0) - risk * (1.0 - _greed) * 1.5
	if _goal_prev.is_finite() and at.distance_to(_goal_prev) < 2.0:
		u *= 1.5 # a bet once started is finished
	if u > _goal_best:
		_goal_best = u
		_goal = at
		_goal_stand = true


func _sense_world(w: World, p: World.Player) -> void:
	_sense_from(w, p, shared_senses(w))


## Senses for one wizard from the World and a shared_senses context (the enemies come from World's grid).
func _sense_from(w: World, p: World.Player, ctx: Dictionary) -> void:
	var me: Vector2 = p.pos
	_hp = p.hp
	_max_hp = p.max_hp
	_bombs = p.bombs
	_speed = w.tune.player_speed * Upgrades.move_mul(p.upgrades) * (1.0 + float(p.armor[Loot.ST_SWIFT])) \
		* (w.tune.haste_speed_mul if p.haste > 0.0 else 1.0) * p.walk_mul
	_skill = p.skill
	_role = Classes.role(p.cls)
	_class_play = _skill != Classes.SK_NOVA # every class but the MAGE (and a wizard with no hero) has its own skill
	_role_row = ROLE_PLAY[_role] if _role >= 0 and _role < ROLE_PLAY.size() else ROLE_PLAY[Classes.ROLE_DAMAGE]
	_melee_r = 0.0
	if _class_play and p.class_weapon >= 0 and Spells.cast_kind(p.class_weapon) == "sweep":
		# the reach it has now: WHIRLWIND's once CLEAVE has evolved
		_melee_r = Spells.level_value(p.class_weapon, "r", Spells.MAX_LEVEL, Upgrades.evo_of(p.upgrades, p.class_weapon))
	_unhurt = p.invuln > 0.0
	_mate_hp.clear()
	_mate_max.clear()
	_fallen_at = ctx.fallen
	_arena = Rect2(G.ARENA.position + Vector2(5, 6), G.ARENA.size - Vector2(10, 8))
	_hz = ctx.hz
	_human_hurt = bool(ctx.human_hurt)
	_potion_hp = int(w.tune.apprentice_potion_hp)
	var lo := Vector2(-1e6, -1e6)
	var hi := Vector2(1e6, 1e6)
	_mates.clear()
	var party := Vector2.ZERO
	var alive: int = 0
	var table_gold: float = 0.0
	for q: World.Player in ctx.alive:
		party += q.pos
		alive += 1
		if not q.ai:
			table_gold += q.gold
		if q == p:
			continue
		_mates.append(q.pos)
		_mate_hp.append(q.hp)
		_mate_max.append(q.max_hp)
		lo = Vector2(maxf(lo.x, q.pos.x - w.tune.leash_x), maxf(lo.y, q.pos.y - w.tune.leash_y))
		hi = Vector2(minf(hi.x, q.pos.x + w.tune.leash_x), minf(hi.y, q.pos.y + w.tune.leash_y))
	_leash = Rect2(lo, hi - lo)
	_set_anchor(p.slot, party / alive if not _mates.is_empty() else G.ARENA.get_center())
	_boss = ctx.boss
	_begin_senses()
	# Read the enemies near the wizard from World's spatial grid (rebuilt every step): no scan of the whole horde.
	var c0: int = floori((me.x - _sense) / World.CELL)
	var c1: int = floori((me.x + _sense) / World.CELL)
	var r0: int = floori((me.y - _sense) / World.CELL)
	var r1: int = floori((me.y + _sense) / World.CELL)
	var grid: Dictionary = w._grid
	for cx: int in range(c0, c1 + 1):
		for cy: int in range(r0, r1 + 1):
			var cell: Array = grid.get(Vector2i(cx, cy), World._NO_CELL)
			for e: World.Enemy in cell:
				if e.dead:
					continue
				_sense_enemy(me, e.pos, _enemy_vel(e), e.r)
	# The nearest enemy for aiming may be outside the sensed square.
	if _nd == INF:
		var best: float = AIM_RANGE * AIM_RANGE
		for e: World.Enemy in w.enemies:
			var d2: float = e.pos.distance_squared_to(me)
			if d2 < best:
				best = d2
				_near = e.pos
				_nd = sqrt(d2)
	for s: World.EShot in w.eshots:
		_sense_shot(me, s.pos, s.vel, s.r)
	_begin_goal()
	for k: World.Pickup in w.pickups:
		_consider_pickup(me, k.pos, k.kind)
	if not apprentice:
		var rows: Array = ctx.shrines
		var shrine := shrine_pick(me, p.gold, table_gold, rows, w.time) if not rows.is_empty() else Vector2.INF
		if shrine.is_finite():
			_consider_shrine(me, shrine)
	_consider_rescue(me, ctx.fallen)
	if _class_play and not _mates.is_empty():
		_consider_role(me)
	if _melee_r > 0.0:
		_consider_melee(me)
	if apprentice:
		_answer_calls(me, ctx)


## An apprentice answers a fallen human's call (her nova pressed while down): it walks into her circle from
## anywhere and stays until she stands, before any pickup or a rescue it chose itself.
func _answer_calls(me: Vector2, ctx: Dictionary) -> void:
	var slots: Array[int] = ctx.fallen_slots
	for s: int in ctx.calling:
		_answering[s] = true
	for s: int in _answering.keys():
		if not slots.has(s):
			_answering.erase(s)
	var best := Vector2.INF
	for s: int in _answering:
		var at: Vector2 = ctx.fallen[slots.find(s)]
		if not best.is_finite() or at.distance_to(me) < best.distance_to(me):
			best = at
	if best.is_finite():
		_goal = best
		_goal_stand = true
		_goal_best = CALL_VALUE


## A fallen ally within RESCUE_REACH: while it is calm here, the bot walks into her ritual circle and stands there.
const RESCUE_REACH: float = 200.0
const RESCUE_CALM: float = CORNERED * 0.5
const RESCUE_VALUE: float = 3.0
const RESCUE_STEP: float = 50.0
## A fallen bot's spirit (unhurt, slow) drifts to the nearest standing ally, so her circle comes to the fight.
const SPIRIT_CLOSE: float = 10.0


func _spirit_input(w: World, p: World.Player) -> PackedFloat32Array:
	if not p.down:
		return PackedFloat32Array([0, 0, 0, 0, 0, nova_count])
	var mates: Array = []
	for q: World.Player in w.players.values():
		if q.alive and q != p:
			mates.append(q.pos)
	return spirit_input(p.pos, mates)


## A fallen bot's input (the sim and the arena share it): drift toward the nearest of `mates` (standing allies'
## positions), no aim, the nova count held so nothing calls.
func spirit_input(me: Vector2, mates: Array) -> PackedFloat32Array:
	var move := spirit_drift(me, mates)
	return PackedFloat32Array([move.x, move.y, 0, 0, 0, nova_count])


## The unit direction toward the nearest of `mates`, or zero when there is none or she is within SPIRIT_CLOSE.
static func spirit_drift(me: Vector2, mates: Array) -> Vector2:
	var best := Vector2.INF
	for m: Vector2 in mates:
		if not best.is_finite() or m.distance_to(me) < best.distance_to(me):
			best = m
	if not best.is_finite() or best.distance_to(me) <= SPIRIT_CLOSE:
		return Vector2.ZERO
	return (best - me).normalized()


func _consider_rescue(me: Vector2, fallen: Array) -> void:
	var best := Vector2.INF
	var bd: float = RESCUE_REACH
	for at: Vector2 in fallen:
		# Far off only while it is calm here; a step away, always.
		if at.distance_to(me) < bd and (last_danger <= RESCUE_CALM or at.distance_to(me) < RESCUE_STEP):
			bd = at.distance_to(me)
			best = at
	if best.is_finite():
		_goal = best
		_goal_stand = true
		_goal_best = RESCUE_VALUE


## How an enemy will move. A veteran reads the tells: an orc or a tome rearing up, a gargoyle about to swoop.
func _enemy_vel(e: World.Enemy) -> Vector2:
	var v: Vector2 = e.vel + e.knock
	if persona != VETERAN:
		return v
	if (e.type == World.ORC or e.type == World.TOME) and e.state == 1:
		return e.dir * (240.0 if e.type == World.ORC else 210.0)
	return v


# =============================================================== THINK ===
## Scores every heading and queues the decision; it reaches the hands after the reaction delay.
func _think(me: Vector2, time: float) -> void:
	thinks += 1
	_next_think = time + _interval * (0.85 + 0.3 * rng.randf())
	var look: float = _look
	var travel: float = _speed * look
	var best_i: int = DIR_COUNT
	var best_s: float = -INF
	var best_danger: float = 0.0
	var cur: Vector2 = _dir
	# Threat centroid: the kite direction (around it, with this bot's own spin).
	var away := Vector2.ZERO
	for k: int in range(_tn):
		var rel: Vector2 = me - _tp[k]
		away += rel / maxf(rel.length_squared(), 25.0)
	var tangent: Vector2 = away.normalized().orthogonal() * _spin if away != Vector2.ZERO else Vector2.ZERO
	var goal_d: float = _goal.distance_to(me) if _goal.is_finite() else 0.0
	var goal_w: float = W_GOAL * clampf(_goal_best, 0.4, 2.0)
	var anchor_d: float = me.distance_to(_anchor)
	# Class play: the role's caution, body margin and circling (neutral for a wizard with no hero).
	var caution: float = _caution
	var margin: float = _margin
	var kite_w: float = W_KITE
	if _class_play:
		if not bool(_role_row.party_only) or not _mates.is_empty() or _melee_r > 0.0:
			caution *= float(_role_row.caution)
			margin *= float(_role_row.margin)
			kite_w *= float(_role_row.kite)
		if _unhurt:
			caution *= UNHURT_CAUTION
	var band: Vector2 = _band if _melee_r <= 0.0 or _band.y <= 0.0 else MELEE_BAND * _melee_r
	# The closest approach is looked for from one reaction step on: an overlap right now is the same for every heading.
	var now: float = minf(REACT_STEP, look)
	# Hazard rows: which way to lean out of the one it stands in (zero when none threatens).
	var hz: PackedFloat32Array = Hazards.near(_hz, me, travel + Hazards.BOT_MARGIN) if not _hz.is_empty() else _hz
	var hz_push: Vector2 = Hazards.steer(hz, me, _speed, _react) if not hz.is_empty() else Vector2.ZERO
	var hz_prep: PackedFloat32Array = Hazards.prepare(hz, me, travel, _react) if not hz.is_empty() else hz
	for i: int in range(DIR_COUNT + 1):
		var d: Vector2 = _dirs[i] if i < DIR_COUNT else Vector2.ZERO
		var end: Vector2 = me + d * travel
		var score: float = 0.0
		# Walls and the leash: the feet stop at them, and a person keeps off them.
		var clamped: Vector2 = Vector2(clampf(end.x, _arena.position.x, _arena.end.x), clampf(end.y, _arena.position.y, _arena.end.y))
		score -= W_WALL * clamped.distance_to(end) / maxf(travel, 1.0)
		var edge: float = minf(minf(clamped.x - _arena.position.x, _arena.end.x - clamped.x),
			minf(clamped.y - _arena.position.y, _arena.end.y - clamped.y))
		if edge < WALL_MARGIN:
			var x: float = 1.0 - edge / WALL_MARGIN
			score -= W_WALL * x * x
		end = clamped
		var ledge: float = minf(minf(end.x - _leash.position.x, _leash.end.x - end.x),
			minf(end.y - _leash.position.y, _leash.end.y - end.y))
		if ledge < LEASH_MARGIN:
			score -= W_LEASH * (1.0 - ledge / LEASH_MARGIN)
		var vel: Vector2 = (end - me) / look
		# Enemies: closest approach along both paths, sooner is worse; and how crowded the end point is.
		var danger: float = 0.0
		var worst: float = 0.0
		var crowd: float = 0.0
		for k: int in range(_tn):
			var rel0: Vector2 = _tp[k] - me
			var rv: Vector2 = _tv[k] - vel
			var rv2: float = rv.length_squared()
			var t: float = clampf(-rel0.dot(rv) / rv2, now, look) if rv2 > 0.0001 else now
			var gap: float = (rel0 + rv * t).length() - _tr[k] - BODY
			if gap < margin:
				var x: float = 1.0 - gap / margin
				var hit: float = x * x * (2.0 - t / look)
				danger += hit
				worst = maxf(worst, hit)
			var ce: float = (rel0 + rv * look).length()
			if ce < OPEN_RADIUS:
				crowd += 1.0 - ce / OPEN_RADIUS
		# The worst contact counts in full, the rest of the crowd only in part: one body met head-on hurts more
		# than many brushed past.
		danger = (worst + CROWD_SHARE * (danger - worst)) * W_DANGER * caution
		# Enemy shots: they fly straight, so the closest approach is exact.
		var shot: float = 0.0
		var shot_worst: float = 0.0
		var chest: Vector2 = me + CHEST
		for k: int in range(_sn):
			var rel0: Vector2 = _sp[k] - chest
			var rv: Vector2 = _sv[k] - vel
			var rv2: float = rv.length_squared()
			var t: float = clampf(-rel0.dot(rv) / rv2, now, look) if rv2 > 0.0001 else now
			var gap: float = (rel0 + rv * t).length() - _sr[k] - 4.0
			if gap < SHOT_MARGIN:
				var x: float = 1.0 - gap / SHOT_MARGIN
				var sh: float = x * x * (2.0 - t / look)
				shot += sh
				shot_worst = maxf(shot_worst, sh)
		danger += (shot_worst + CROWD_SHARE * (shot - shot_worst)) * W_SHOT
		score -= danger + crowd * W_OPEN
		if not hz.is_empty():
			if hz_push != Vector2.ZERO:
				score += W_HAZARD * minf(hz_push.length(), 2.0) * (d.dot(hz_push.normalized()) - 1.0)
			score -= W_HAZARD * minf(Hazards.threat_path(hz_prep, me, end), 2.0)
		# Where it wants to be: the goal, else its roaming ground.
		if _goal.is_finite():
			# Progress to the closest point of the path, so a goal nearer than the lookahead walk still pulls.
			var seg: Vector2 = end - me
			var along: float = clampf((_goal - me).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
			var g: float = (goal_d - (me + seg * along).distance_to(_goal)) / maxf(travel, 1.0)
			if _goal_stand and goal_d < SHRINE_STAND:
				g = 1.0 if i == DIR_COUNT else -1.0
			score += goal_w * g
		if anchor_d > _anchor_r and not _goal.is_finite():
			score += W_ANCHOR * (anchor_d - end.distance_to(_anchor)) / maxf(travel, 1.0)
		if _tn > 0:
			score += kite_w * d.dot(tangent)
		for m: Vector2 in _mates:
			var md: float = end.distance_to(m)
			if md < MATE_ROOM:
				score -= W_MATE * (1.0 - md / MATE_ROOM)
		if _boss.is_finite() and band.y > 0.0:
			var bd: float = end.distance_to(_boss)
			if bd < band.x:
				score -= W_BOSS * (band.x - bd) / band.x
			elif bd > band.y:
				score -= W_BOSS * minf(1.0, (bd - band.y) / band.y)
		# People commit to a line: keep the heading they have.
		if i == DIR_COUNT:
			score += W_STAND if cur == Vector2.ZERO else 0.0
		else:
			score += W_KEEP * d.dot(cur)
		score += _noise * (rng.randf() - 0.5)
		if score > best_s:
			best_s = score
			best_i = i
			best_danger = danger
	last_danger = best_danger
	var want: Vector2 = _dirs[best_i] if best_i < DIR_COUNT else Vector2.ZERO
	# Turn no faster than the persona's hands.
	if cur != Vector2.ZERO and want != Vector2.ZERO:
		var a: float = cur.angle_to(want)
		var lim: float = _turn * _interval
		if absf(a) > lim:
			var full := want
			want = cur.rotated(signf(a) * lim)
			# A turn that swings the heading through a hazard row goes the other way round, or stops.
			if not hz_prep.is_empty():
				var wanted: float = Hazards.threat_path(hz_prep, me, me + full * travel)
				if Hazards.threat_path(hz_prep, me, me + want * travel) > wanted:
					var other: Vector2 = cur.rotated(-signf(a) * lim)
					want = other if Hazards.threat_path(hz_prep, me, me + other * travel) <= wanted else Vector2.ZERO
	_dir = want
	# When the bot is boxed in it circles the other way next time.
	if best_danger > CORNERED * 0.5 and rng.randf() < 0.1:
		_spin = -_spin
	var nova: bool = _decide_skill(me, best_danger, time) if _class_play else _decide_nova(best_danger)
	if nova and _skill == Classes.SK_VOLLEY:
		want = _volley_dir # the roll goes along her movement: away from the crowd
		_dir = want
	var aim := Vector2.ZERO
	# A melee hero aims its spells at the boss even with the boss's adds at its feet (its sweep finds those itself).
	var at_boss: bool = _nd > 60.0 or _near == _boss or _melee_r > 0.0
	if _boss.is_finite() and persona != NOVICE and at_boss and _boss.distance_to(me) < AIM_RANGE:
		aim = _boss - me
	elif _nd < AIM_RANGE:
		aim = _near - me
	var out := PackedFloat32Array([want.x, want.y, aim.x, aim.y, 1.0 if aim != Vector2.ZERO else 0.0, 0.0])
	_q_t.append(time + _react)
	_q_out.append(out)
	_q_nova.append(nova)
	if not _started:
		_started = true
		_q_t[_q_t.size() - 1] = time # the first decision acts at once


func _decide_nova(danger: float) -> bool:
	var cornered: bool = danger > CORNERED
	if not cornered:
		_panic = false
		return false
	if _panic or _bombs <= 0:
		return false
	_panic = true
	var hurt: bool = _hp <= _nova_hp
	var save: bool = _nova_save and _hp <= _max_hp - 1 and danger > CORNERED * 1.6
	if not hurt and not save:
		_panic = false
		return false
	return rng.randf() >= _nova_forget


## The decision the hands carry out at `time`.
func _held(time: float) -> PackedFloat32Array:
	while not _q_t.is_empty() and _q_t[0] <= time:
		_out = _q_out[0]
		if _q_nova[0]:
			nova_count += 1
		_q_t.pop_front()
		_q_out.pop_front()
		_q_nova.pop_front()
	_out[5] = nova_count
	return _out


func _with_my_pick(inp: PackedFloat32Array, p: World.Player) -> PackedFloat32Array:
	var out: PackedFloat32Array = inp.duplicate()
	out.append(pick_card(p.choices, p.upgrades))
	out.append(p.offer)
	return out


# ========================================================== CLASS PLAY ===
## A tank guards the ally with the most enemies near her (the weakest on a tie), between her and that crowd; a
## healer keeps the most hurt ally inside her light, on the far side from the enemies. Called with teammates only.
func _consider_role(me: Vector2) -> void:
	var at := Vector2.INF
	var worth: float = 0.0
	if _role == Classes.ROLE_TANK or _role == Classes.ROLE_SUPPORT:
		var bs: float = 0.0
		for m: int in range(_mates.size()):
			var n: int = 0
			var c := Vector2.ZERO
			for k: int in range(_tn):
				if _tp[k].distance_squared_to(_mates[m]) < GUARD_R * GUARD_R:
					n += 1
					c += _tp[k]
			if n == 0:
				continue
			var s: float = float(n) + GUARD_WEAK * (1.0 - float(_mate_hp[m]) / float(maxi(1, _mate_max[m])))
			if s > bs:
				bs = s
				var to_crowd: Vector2 = c / float(n) - _mates[m]
				at = _mates[m] + to_crowd.normalized() * minf(GUARD_GAP, to_crowd.length()) # never past the crowd
		worth = GUARD_VALUE
	elif _role == Classes.ROLE_HEALER:
		var hurt: int = -1
		var hs: float = 0.0
		for m: int in range(_mates.size()):
			var missing: float = 1.0 - float(_mate_hp[m]) / float(maxi(1, _mate_max[m]))
			if missing > hs:
				hs = missing
				hurt = m
		if hurt < 0:
			return
		var ally: Vector2 = _mates[hurt]
		var n: int = 0
		var c := Vector2.ZERO
		for k: int in range(_tn):
			if _tp[k].distance_squared_to(ally) < GUARD_R * GUARD_R:
				n += 1
				c += _tp[k]
		var side: Vector2 = (ally - c / float(n)).normalized() if n > 0 else (me - ally).normalized()
		at = ally + side * HEAL_REACH * HEAL_SPOT
		worth = HEAL_VALUE
	if at.is_finite() and worth > _goal_best:
		_goal = at
		_goal_stand = false
		_goal_best = worth


## A melee hero's goal (see MELEE_SPOT): just inside its sweep's reach of the nearest enemy, on its own side.
func _consider_melee(me: Vector2) -> void:
	if _nd == INF or MELEE_VALUE <= _goal_best:
		return
	var back: Vector2 = me - _near
	_goal = _near + (back.normalized() if back.length_squared() > 0.01 else Vector2.DOWN) * _melee_r * MELEE_SPOT
	_goal_stand = false
	_goal_best = MELEE_VALUE


## The skill on the nova button, used for what it does (see the PROVOKE..AEGIS constants). Every class also uses it
## to save itself when cornered, like the nova. The persona's nova_forget may make it forget a chance for FORGET_HOLD s.
func _decide_skill(me: Vector2, danger: float, time: float) -> bool:
	if _bombs <= 0 or time < _skill_until:
		return false
	var cornered: bool = danger > CORNERED
	var save: bool = cornered and (_hp <= _nova_hp or (_nova_save and _hp <= _max_hp - 1 and danger > CORNERED * 1.6))
	var want: bool = save
	match _skill:
		Classes.SK_PROVOKE:
			want = save or _provoke_worth(me)
		Classes.SK_VOLLEY:
			want = save or (cornered and _crowd(me, VOLLEY_R) >= VOLLEY_CROWD)
		Classes.SK_SANCTUARY:
			want = _sanctuary_worth(me)
		Classes.SK_AEGIS:
			want = save or _aegis_worth(me)
	if not want:
		_skill_retry = -1.0
		return false
	if time < _skill_retry:
		return false
	if rng.randf() < _nova_forget:
		_skill_retry = time + FORGET_HOLD
		return false
	var busy: float = Classes.skill_value(_skill, "taunt", Classes.skill_value(_skill, "safe"))
	_skill_until = time + _react + maxf(SKILL_GAP, busy)
	if _skill == Classes.SK_VOLLEY:
		_volley_dir = _roll_dir(me)
	return true


## Sensed enemies within `r` px.
func _crowd(me: Vector2, r: float) -> int:
	var n: int = 0
	for k: int in range(_tn):
		if _tp[k].distance_squared_to(me) < r * r:
			n += 1
	return n


## PROVOKE pays when several enemies in its radius are on allies, or the boss is on an ally within it.
func _provoke_worth(me: Vector2) -> bool:
	if _mates.is_empty():
		return false
	var r: float = Classes.skill_value(Classes.SK_PROVOKE, "radius")
	var n: int = 0
	for k: int in range(_tn):
		if _tp[k] == _boss or _tp[k].distance_to(me) > r:
			continue
		for m: Vector2 in _mates:
			if _tp[k].distance_to(m) < ALLY_NEAR:
				n += 1
				break
	if n >= PROVOKE_CROWD:
		return true
	if _boss.is_finite() and _boss.distance_to(me) <= r:
		for m: Vector2 in _mates:
			if _boss.distance_to(m) < BOSS_ON_ALLY:
				return true
	return false


## SANCTUARY pays when the hearts it heals (and the fallen it raises) are worth a charge, or a hero is on her last.
func _sanctuary_worth(me: Vector2) -> bool:
	var heal: float = Classes.skill_value(Classes.SK_SANCTUARY, "heal")
	var r: float = Classes.skill_value(Classes.SK_SANCTUARY, "radius")
	var gain: float = minf(heal, float(_max_hp - _hp))
	var last: bool = _hp <= LAST_HEART and _hp < _max_hp
	for m: int in range(_mates.size()):
		gain += minf(heal, float(_mate_max[m] - _mate_hp[m]))
		last = last or (_mate_hp[m] <= LAST_HEART and _mate_hp[m] < _mate_max[m])
	for at: Vector2 in _fallen_at:
		if at.distance_to(me) <= r:
			gain += RISE_WORTH
	var need: float = heal + (SANCTUARY_PARTY_EXTRA if not _mates.is_empty() else 0.0)
	return gain >= need or last


## AEGIS pays when heroes in its radius (her too) are about to be hit, or one on her last heart is.
func _aegis_worth(me: Vector2) -> bool:
	var r: float = Classes.skill_value(Classes.SK_AEGIS, "radius")
	var n: int = 0
	if _hit_soon(me):
		if _hp <= LAST_HEART:
			return true
		n += 1
	for m: int in range(_mates.size()):
		if _mates[m].distance_to(me) <= r and _hit_soon(_mates[m]):
			if _mate_hp[m] <= LAST_HEART:
				return true
			n += 1
	return n >= AEGIS_HEROES


## True when a sensed enemy body is within HIT_SOON px of touching a hero at `at`, or the boss is on her.
func _hit_soon(at: Vector2) -> bool:
	if _boss.is_finite() and _boss.distance_to(at) < BOSS_ON_ALLY:
		return true
	for k: int in range(_tn):
		if _tp[k].distance_to(at) - _tr[k] - BODY < HIT_SOON:
			return true
	return false


## A VOLLEY's roll: straight away from the sensed crowd, else the inside heading closest to that.
func _roll_dir(me: Vector2) -> Vector2:
	var c := Vector2.ZERO
	for k: int in range(_tn):
		c += _tp[k]
	var away: Vector2 = (me - c / float(_tn)).normalized() if _tn > 0 else _dir
	if away == Vector2.ZERO:
		away = _facing
	var roll: float = Classes.skill_value(Classes.SK_VOLLEY, "roll")
	if _arena.has_point(me + away * roll):
		return away
	var best := away
	var bs: float = -INF
	for d: Vector2 in _dirs:
		if _arena.has_point(me + d * roll) and d.dot(away) > bs:
			bs = d.dot(away)
			best = d
	return best


# =============================================================== PICKS ===
func _card_score(idx: int, levels: Dictionary) -> float:
	var lv: int = Upgrades.level_of(levels, idx)
	match _pick:
		PICK_SHINY:
			if Upgrades.is_evolution(idx):
				return 80.0 + rng.randf() * 10.0
			if Upgrades.pairs_with(levels, idx):
				return 72.0 + rng.randf() * 6.0 # the card that completes a pair: the shiniest new one
			return (40.0 if lv == 0 else 10.0) + rng.randf() * 30.0
		PICK_DAMAGE:
			if Upgrades.is_evolution(idx):
				return 100.0
			if Upgrades.kind(idx) == Upgrades.PASSIVE and Upgrades.pairs_with(levels, idx):
				# It opens an evolution, the most damage a card can bring, once its spell is near its top: from
				# PAIR_FROM_LEVEL it outranks STRENGTH. Before that she takes it by its own worth, below.
				var near: int = _pair_spell_level(levels, idx) - PAIR_FROM_LEVEL
				if near >= 0:
					return 62.0 + 4.0 * near
			if Upgrades.key(idx) == "power":
				return 60.0
			if Upgrades.is_weapon(idx):
				return 50.0 + lv if lv > 0 else 30.0
			return float(PASSIVE_TASTE.get(Upgrades.key(idx), 10.0)) * 0.8 + rng.randf()
	return _plan_score(idx, lv, levels)


## The level of the spell the arcana `idx` would complete a pair with (the highest, when it pairs with two she
## holds), 0 when it completes none.
static func _pair_spell_level(levels: Dictionary, idx: int) -> int:
	var best: int = 0
	for sp: int in Spells.COUNT:
		for evo: int in range(1, Upgrades.evo_rows(sp).size() + 1):
			if Upgrades.partner_row(sp, evo) == idx and Upgrades._can_evolve(levels, sp, evo, {}):
				best = maxi(best, Upgrades.weapon_level(levels, sp))
	return best


## The veteran: choose an evolution whose requirements it can still meet (most progress first), take what it
## requires, then take it. Reads the `requires` column of Upgrades.CATALOG, so new spells and passives need no code.
func _plan_score(idx: int, lv: int, levels: Dictionary) -> float:
	if Upgrades.is_evolution(idx):
		return 100.0
	var target: int = _plan_target(levels)
	if target >= 0:
		for r: Array in Upgrades.CATALOG[target][Upgrades.C_REQUIRES]:
			if int(r[0]) == idx and lv < int(r[1]):
				# The required thing furthest along first: it finishes the plan soonest.
				return 70.0 + float(lv) / float(maxi(1, int(r[1])))
	# Anything another reachable evolution needs is the next plan.
	for e: int in range(Upgrades.count()):
		if not _plan_open(levels, e):
			continue
		for r: Array in Upgrades.CATALOG[e][Upgrades.C_REQUIRES]:
			if int(r[0]) == idx and lv < int(r[1]) and lv > 0:
				return 45.0 + lv
	if Upgrades.is_weapon(idx):
		return 35.0 + lv if lv > 0 else 25.0
	return float(PASSIVE_TASTE.get(Upgrades.key(idx), 10.0))


## True if row `e` is an evolution a wizard with `levels` may still plan for: built, and no evolution of its spell
## taken (one taken shuts the other).
static func _plan_open(levels: Dictionary, e: int) -> bool:
	return Upgrades.is_evolution(e) and not Upgrades.UNBUILT.has(e) and not Upgrades.evolved(levels, Upgrades.spell_of(e))


## The evolution the veteran chases: open to her (_plan_open), every requirement reachable, most progress made.
func _plan_target(levels: Dictionary) -> int:
	var best: int = -1
	var bp: float = 0.0
	for e: int in range(Upgrades.count()):
		if not _plan_open(levels, e):
			continue
		var progress: float = 0.0
		var reachable: bool = true
		for r: Array in Upgrades.CATALOG[e][Upgrades.C_REQUIRES]:
			var need: int = int(r[1])
			# A row it can never be offered (a class weapon it does not hold: WHIRLWIND's CLEAVE) is out of reach.
			if Upgrades.max_level(int(r[0])) < need or (Upgrades.level_of(levels, int(r[0])) == 0
					and not Upgrades._requirements_met(levels, int(r[0]))):
				reachable = false
				break
			progress += minf(1.0, float(Upgrades.level_of(levels, int(r[0]))) / float(maxi(1, need)))
		if reachable and progress > bp:
			bp = progress
			best = e
	return best

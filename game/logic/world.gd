class_name World
extends RefCounted
## The authoritative game simulation. Runs on the host (or offline) only.
## It knows nothing about drawing: it emits events (for effects and sound)
## and produces compact snapshots that both the host and clients render.

# Enemy types: the ids live in Bestiary (with the reserved kinds); these are today's.
const GOBLIN := Bestiary.GOBLIN
const SKELETON := Bestiary.SKELETON
const SLIME := Bestiary.SLIME
const MSLIME := Bestiary.MSLIME
const BAT := Bestiary.BAT
const ORC := Bestiary.ORC
const MAGE := Bestiary.MAGE
const LICH := Bestiary.LICH
## The later acts' horde (appended so snapshot type ids stay put).
const WRAITH := Bestiary.WRAITH # drifts through the crowd and phases out: spells pass through it while it is faded
const TOME := Bestiary.TOME # a cursed grimoire that circles a wizard and dashes through
const GARGOYLE := Bestiary.GARGOYLE # sits as stone (hard to hurt), then swoops
const PRIEST := Bestiary.PRIEST # the bone priest: keeps its distance and raises skeletons

# Spells
const SP_ARCANE := 0
const SP_FIRE := 1
const SP_FROST := 2
const SP_STORM := 3
const SP_STAR := 4
const SP_RUNE := 5
const SP_BONE := 6 # wave 3: bone spear (and the archer's LONGBOW)
const SP_CANDLE := 7 # vigil candle (and the priest's HOLY LIGHT)
const SP_CLEAVE := 8 # the knight's class weapon
const SP_HEX := 9 # stage 3: a curse on the toughest foe (unbuilt: Upgrades.UNBUILT)
const SP_BLADES := 10 # stage 3: spirit blades circling the wizard (unbuilt)

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
const PK_TOME_PARTY := 15 # the party tome: levels a random owned spell of every wizard (WorldLevels)
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
const EV_EXPLODE := 3 # a blast: a = its radius in px as the World hit with it (THE EMPRESS widens it), b = slot
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
const EV_FROST := 22 # a frost hit: a = 0 for a shard that slowed a foe, else a frost burst's radius in px (COMET RAIN; THE EMPRESS widens it)
const EV_SCORE := 23
const EV_LEVELUP := 24
const EV_PICK := 25
const EV_ELITE := 26
const EV_RIFT := 27
const EV_CHEST := 28
const EV_WARD := 29
const EV_SHRINE_UP := 30 # a shrine appeared: a = kind
const EV_SHRINE := 31 # a wizard paid a shrine: a = slot (+ 8: a card a WHEEL OF FORTUNE dealt, no bet), b = kind * 16 + outcome; the reel starts
const EV_GAMBLE := 32 # the reel ended and the outcome applies: a = slot, b = kind * 16 + outcome
const EV_VICTORY := 33 # the Archlich fell and the run is won: a = slot of the wizard who slew it
const EV_RESULTS := 34 # just before EV_GAMEOVER: a = the run's Results.to_dict() for the results screen
const EV_RAISE := 35 # a bone priest raises the dead: at its position, a = how many
const EV_OMEN := 36 # a horde omen begins (Lore.OMENS): at its centre, a = omen index, b = ring radius (0: from the doors)
const EV_RUNE := 37 # a circle is laid: at its centre, a = radius, b = slot + Spells.evo_bits(evolution id) + 16 x Spells.CIRCLE_* kind (+ 8 evolved, + 4 more for id 2)
const EV_CARD := 38 # a wizard picked up a monster card: a = Cards index, b = slot (+ 8 if it came from an urn)
const EV_URN := 39 # an urn shattered: at its position, a = what fell out (URN_* below)
const EV_LULL := 40 # a Lich fell and the lull begins: at the party's centre, a = its seconds
## Wave 2 events. The fallen (WorldPlayers) emit EV_DOWN, EV_REVIVE and EV_CALL; nothing emits the rest yet.
const EV_DOWN := 41 # a wizard fell: at its position, a = slot
const EV_REVIVE := 42 # a fallen wizard is back up: at its position, a = slot, b = the reviver's slot (-1: by itself)
const EV_CALL := 43 # a wizard calls for help: at its position, a = slot
const EV_REDRAW := 44 # a wizard redrew the hand: a = slot
const EV_BANISH := 45 # a wizard banished a card: a = slot, b = Upgrades index
const EV_FATE := 46 # a fate is drawn: a = fate, b = slot
const EV_SLOTS := 47 # the slot cap changed: a = spell slots, b = passive slots
const EV_TALK := 48 # Morvane speaks: a = line
const EV_PHASE := 49 # a boss turns a phase (Bosses.phase_turn): at the boss, a = its type, b = the phase it turns to
const EV_SKILL := 50 # a hero's class skill (not the NOVA, which is EV_NOVA): at the hero, a = slot, b = Classes.SK_*
const EV_HEAL := 51 # a hero is healed by a skill or a light: at the hero, a = slot, b = hearts
const EV_BURST := 52 # a JUSTICE burst: at the slain foe, a = radius, b = slot
const EV_SWEEP := 53 # a CLEAVE: at the hero, a = Vector3(the arc's middle angle in rad, its reach in px, half its arc in rad) as swung (THE EMPRESS, THE STAR), b = slot + Spells.evo_bits(evolution id) (+ 8 evolved: WHIRLWIND)
## What an urn held. A card from an urn is a PK_CARD whose value is the Cards index + URN_CARD.
const URN_DUST := 0
const URN_COIN := 1
const URN_GEM := 2
const URN_POTION := 3
const URN_CHEST := 4
const URN_CARD_DROP := 5
const URN_CARD := 100
const URN_R := 5.0

## Enemy stats, XP values and the horde table live in Bestiary (KINDS, HORDE).

## The player row in snapshot()["p"], final for waves 2 and 3: read it only through these P_* indices.
## Choices: 3 x (offered Upgrades index or -1, the level it would reach). Spells: P_SLOTS x (SPELL row or -1,
## level; Spells.MAX_LEVEL + evolution id = evolved), in the order taken. Passives: P_SLOTS x (PASSIVE row or -1, level),
## in the order taken. xp, xp needed and level are the party's (the same for every wizard); draws are queued
## level-up offers plus 1 while the wizard holds cards; down_left is s (-1 = a ritual only); race, class, look and
## class level are the seat's (0: HUMAN MAGE) until World.apply_hero sets the hero's.
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
const P_RACE := P_GOLD + 11 # Races / Classes index (the seat's, or the hero's from apply_hero)
const P_CLASS := P_GOLD + 12
const P_LOOK := P_GOLD + 13 # a packed look: skin, hair, style
const P_CLASS_LEVEL := P_GOLD + 14
const P_FLOATS := P_GOLD + 15
const BASE_HEARTS := 5

## The header, snapshot()["w"]: minute, phase, phase s, boss health fraction (-1: none), the four doors' open s,
## run s, 1 if the boss is the Archlich, lull s left, seal level, slot cap (spells, passives), then the boss's
## Bestiary type (-1: none), its Bosses.phase, boss_t, boss_arg and boss_meter, then the Reading (Readings index, -1).
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
const W_BOSS_TYPE := 14
const W_BOSS_PHASE := 15
const W_BOSS_T := 16
const W_BOSS_ARG := 17
const W_BOSS_METER := 18
const W_READING := 19
const W_FLOATS := 20

## Floats per rune circle in snapshot()["r"]: x, y, radius, age s, lifetime s, owner slot, evolution id, kind.
const RUNE_FLOATS := 8
## Floats per shrine in snapshot()["sh"] (WorldShrines.snapshot_shrines): kind, x, y, life s, charge fraction (a team
## shrine: its pot / price), cost, wizards still needed.
const SHRINE_FLOATS := 7
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
## Bits World adds to E_STATUS (high, clear of the status bits to come; exact in a float32): cloaked (shots pass
## through, Enemy.cloak) and a boss turning a phase (Enemy.turn > 0).
const STATUS_CLOAK := 1 << 20
const STATUS_TURN := 1 << 21

## Floats per spell object in snapshot()["o"]: kind, owner, x, y, a, b, t, evolved. None exist yet.
const O_FLOATS := 8

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
var urns_broken := 0 # urns broken this run (run_so_far's "urns", Profile.urns); not in the snapshot or the hash
var shrines: Array[Shrine] = []
var shrine_t := 0.0
var team_shrine_t := 0.0
## Meta unlock bonuses for this run (Profile.bonuses through apply_meta); all zero by default.
var meta_damage := 0.0
var meta_xp := 0.0
var meta_gold := 0.0
var meta_luck := 0
## The shop's run options (apply_meta's "redraws", "banishes", "start_level"), handed out on the run's first step
## (WorldLevels._shop_start): redraws and banishes every wizard has on top of Upgrades.REDRAWS and BANISHES, and the
## levels THE HEAD START gives the party, each a hand to draw before the first door opens (WorldLevels._intro_held).
var meta_redraws := 0
var meta_banishes := 0
var meta_start_level := 0
## The levels THE HEAD START gave the party on the first step (WorldLevels._shop_start). xp_needed never prices them,
## so each later level costs what it would without them and the party keeps its lead for the whole run.
var head_start_levels := 0
## The table's locked rows (Upgrades index -> true): the host's profile has not opened them (apply_meta's "locked",
## Profile.locked_rows; docs/stage3_brief.md § 4.3). Each wizard's banned holds the mask, less her own class
## weapon, its arcana and its evolution (apply_hero). Empty in every scripted run. In the snapshot as "lk".
var locked: Dictionary = {}
## The run's difficulty (apply_seal): SEAL_EASY (-1) easy, 0 normal, 1 hard, 2..SEAL_MAX the Seals I to VIII.
const SEAL_EASY := -1
const SEAL_MAX := 9
var seal := 0
## What the Seal changes, copied from Seals.values in apply_seal (see Seals.BASE); neutral at WIZARD (0).
var seal_hp := 1.0 # enemy health
var seal_horde := 1.0 # horde budget rate
var seal_boss := 1.0 # Lich and Archlich health
var seal_speed := 1.0 # enemy speed
var seal_potions := 1.0 # a plain kill's potion chance
var seal_luck := 0 # chest luck
var seal_cards := 1.0 # card run odds (Cards.card_run_chance)
var seal_ultra := true # an ULTRA RARE run (its prismatic chest) can happen
var seal_rift := 1.0 # AMBUSH: rift warning
var seal_potion_heal := 2 # FAMINE: hearts a potion heals
var seal_group := 1.0 # LEGION: group size
var seal_cap := 0 # LEGION: enemy cap (0: tune.enemy_cap)
var seal_elite_hp := 1.0 # CHAMPIONS: elite health
var seal_escort := 0 # CHAMPIONS: plain enemies with each elite
var seal_hand := 0 # SILENCE: cards a level-up deals (0: tune.level_choices)
var seal_ritual := 1.0 # DARKNESS: ritual time
var seal_card := -1 # the Seal's card, which the Archlich drops when it is a card run's kill (Cards.run_card), -1 none
## The run's Reading (apply_reading, Net.reading): a Readings key, "" for none. Its hp, horde, boss, speed and
## potions multiply the seal_* fields above and its hearts are added; its own values land in the read_* fields,
## neutral without a Reading. Each comment names the rule (job R2) that will read it and credit the Reading.
var reading := ""
var read_spell2 := false # ACE OF WANDS: every wizard starts with a second open spell at level 1
var read_apprentice := false # FOUR OF WANDS: an apprentice joins the table
var read_full_hearts := 0 # FOUR OF WANDS: hearts every wizard gains when all four seats are taken
var read_pace := 1.0 # EIGHT OF WANDS: the run's clock: step() plays this many seconds for each second given
var read_xp := 1.0 # TEN OF SWORDS: XP gained, multiplied
var read_slots: Array = [] # TEN OF WANDS: [spell slots, arcana slots] from the first second; [] as built
var read_bond := false # TWO OF CUPS: a hit takes its heart from the wizard who holds the most
var read_no_potions := false # FIVE OF CUPS: no potion drops at all (elites and bosses too)
var read_boss_heal := false # FIVE OF CUPS: each boss phase and boss death heals every wizard to full
var read_arcana_hands := 0 # NINE OF CUPS: a wizard's first level-up hands that hold only arcana
var read_free_redraws := false # NINE OF CUPS: redraws cost nothing in those hands
var read_novas := 0 # ACE OF SWORDS: nova charges every wizard starts with, added
var read_nova_refill := false # ACE OF SWORDS: a boss's arrival fills charges back to the run's start
var read_heart_cap := 0 # THREE OF SWORDS: the most hearts a wizard can hold, 0 for no cap
var read_damage := 1.0 # THREE OF SWORDS: all damage the wizards deal, multiplied
var read_elite_rate := 1.0 # SEVEN OF SWORDS: how often elites come, multiplied
var read_elite_tome := false # SEVEN OF SWORDS: every elite drops a PARTY TOME
var read_swords_from := 0.0 # TEN OF SWORDS: run seconds from which TEN OF SWORDS foes join the horde, 0 never
var read_gold := 0 # ACE OF PENTACLES: gold every wizard starts with, added
var read_door_shrine := false # ACE OF PENTACLES: a gamble shrine stands at the door
var read_no_shrines := false # FOUR OF PENTACLES: no shrines appear
var read_gold_heal := 0 # FOUR OF PENTACLES: each this much gold a wizard picks up heals her a heart, 0 never
var read_chest_items := 0 # NINE OF PENTACLES: items every chest holds, 0 as built
var read_next_step := false # TEN OF PENTACLES: the run plays at the next step's numbers and rule
var read_crystals := 1.0 # TEN OF PENTACLES: crystals the run pays, multiplied
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
## JUSTICE bursts waiting for the end of the step (WorldCasting._update_bursts): [pos, damage, slot]. Queued so a
## burst never recurses inside a damage call; `bursting` is set while they go off (their kills never burst).
var bursts: Array = []
var bursting := false
var _gambles: Array = [] # paid shrines waiting for their reel: {t, slot, kind, outcome, stake, pos}
## The fate deck (WorldShrines): the chance a party's fate comes from the cruel side (the difficulty ladder sets
## it), THE FOOL's next fate counting twice, the seconds novas stay sealed, potions stop dropping and every XP gem
## flies to the party, and the hearts THE WORLD owes the fallen until they stand (slot -> hearts).
var fate_cruel := 0.5
var fate_twice := false
var nova_sealed := 0.0
var no_potions := 0.0
var gem_rush := 0.0
var fate_heal := {}
var events: Array = []
var rng := RandomNumberGenerator.new()
## The run's own loot stream (Loot.run_stream, seeded by the run's seed; rng never feeds it) and its draws taken
## once in _init (Loot.run_rolls): whether this is an ULTRA RARE run or a card run, and when each drop comes
## (WorldDrops.ultra_due, card_due).
var loot_rng: RandomNumberGenerator
var run_loot: Dictionary = {}
var ultra_dropped := false # the ULTRA RARE run's prismatic chest has dropped
var card_dropped := false # the card run's card has dropped
var urn_card := false # this run was given an urn card (apply_meta's "urn_card"): a card run whose card waits in an urn
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
var _next_group: Array = [] # [layout, [[type, count], ...]] the horde is saving its budget for (Bestiary.roll_group)
## Enemies alive per Bestiary type, rebuilt with the grid each step (horde caps read it).
var alive := PackedInt32Array()
## The bosses' timetable (Bosses): [run s, type, final] rows, from the Tuning until the act-boss switch.
var schedule: Array = []
## What the boss shows the players beyond its health (header W_BOSS_T, W_BOSS_ARG, W_BOSS_METER): the seconds into
## its current attack or word, an attack argument (a named slot, the dealt cards) and a meter (a ward, a 6% goal).
var boss_t := 0.0
var boss_arg := 0
var boss_meter := 0.0
## Hazard rows on the floor (Hazards): warned areas that turn hot.
var hazards: Array[Hazards.Hazard] = []
var next_hazard_id := 1
var _tick := 0
var door_open := [0.0, 0.0, 0.0, 0.0]
var boss: Enemy = null
var powerup_timer := 8.0
var time := 0.0
var _grid := {}
const CELL := 32.0
const _NO_CELL: Array = []
## Separation's copy of the horde, rebuilt with the grid: the grid's cells again as rows into `_sep_who`, and each
## row's position and radius in packed arrays (filled by WorldEnemies._sep_fill, kept current by _update_enemy).
## Separation tests every neighbour of half the horde each tick; reading two fields of each neighbour object for
## that was over half of the enemy update at the cap, a packed read is a fraction of it.
var _sep_cells := {}
var _sep_who: Array[Enemy] = []
var _sep_pos := PackedVector2Array()
var _sep_r := PackedFloat64Array()
var _sep_ok := false
const _NO_ROWS: PackedInt32Array = []
## The wizards as a typed list, refreshed every step: `players.values()` builds a new untyped array on every call,
## and the enemy update asked for it twice per enemy (5% of a whole step at the enemy cap).
var _plist: Array[Player] = []
## The most a threat pick can stretch past the nearest wizard: the largest threat over the smallest (apply_hero
## sets it; 1 while every wizard's threat is the same). The contact test widens its reach by it.
var threat_spread := 1.0
## The brains that play the apprentices (WorldApprentices), slot -> SmashBot; made when first needed.
var apprentice_bots: Dictionary = {}
## True once the apprentices seated with a class took it (WorldApprentices.with_inputs, the run's first step).
var classes_taken := false
## Score and kills of wizards who left the run (remove_player): total_score and total_kills keep them.
var departed_score := 0
var departed_kills := 0
## How near the nearest wizard must be at the start of an enemy's update for the contact test to run at all: the
## 5 px touch distance plus far more than any enemy travels in one step (the fastest dash is 4 px).
const CONTACT_REACH := 45.0
## Gameplay numbers. Tuning.shared() unless a test or sim passes its own.
var tune: Tuning

## seed_value 0 picks a random seed (normal play); tests, sims and replays pass a fixed one. `wizards` maps a
## slot to the Wizards index its player picked in the lobby; a slot not in it plays the wizard of its own colour.
## `seats` maps a slot to its roster extras (Net.seat_builds(): ai, race, cls, look, cls_level), copied onto the
## Player untouched; nothing else reads them (apply_hero gives a wizard a whole hero).
func _init(slots: Array, seed_value: int = 0, tuning: Tuning = null, wizards: Dictionary = {}, seats: Dictionary = {}) -> void:
	tune = tuning if tuning != null else Tuning.shared()
	schedule = Bosses.schedule_from(tune)
	alive.resize(Bestiary.count())
	horde_budget = tune.horde_start_budget
	shrine_t = tune.shrine_first
	team_shrine_t = tune.team_shrine_first
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	loot_rng = Loot.run_stream(rng.seed)
	run_loot = Loot.run_rolls(loot_rng)
	var c := G.ARENA.get_center()
	var offs := [Vector2(-24, -14), Vector2(24, -14), Vector2(-24, 14), Vector2(24, 14)]
	for s in slots:
		var p := Player.new()
		p.slot = s
		p.pos = c + offs[s % 4]
		p.wizard = clampi(int(wizards.get(s, s % Wizards.count())), 0, Wizards.count() - 1)
		var seat: Dictionary = seats.get(s, {})
		p.ai = bool(seat.get("ai", false))
		p.away = p.ai and bool(seat.get("away", false))
		p.race = int(seat.get("race", 0))
		p.cls = int(seat.get("cls", 0))
		p.look = int(seat.get("look", 0))
		p.cls_level = int(seat.get("cls_level", 0))
		p.cds.resize(Spells.COUNT)
		p.cds.fill(0.0)
		p.upgrades[Upgrades.weapon_entry(Wizards.start_spell(p.wizard))] = 1
		WorldCasting._refresh_spell(self, p)
		players[s] = p
	_plist.assign(players.values())
	WorldLevels._update_slots(self)
	record = Results.new(slots)
	for p: Player in _plist:
		if p.ai:
			record.ai[p.slot] = true
	events.append([EV_WAVE, 0, 0, wave, 0])

## Starts the run with the host's meta unlocks (Save.run_bonuses()): extra hearts and novas for every wizard,
## and damage, XP, gold and chest luck bonuses; "redraws", "banishes" and "start_level" are the shop's run options
## (meta_redraws, meta_banishes, meta_start_level), handed out on the first step; "urn_card" (bool) makes the run a
## card run whose card waits in the first urn broken at or after its moment (WorldDrops.card_due); "locked" (an Array
## of Upgrades indices) is the table's mask (World.locked), put in every wizard's banned. Call once, before the first
## step.
func apply_meta(b: Dictionary) -> void:
	urn_card = bool(b.get("urn_card", false))
	meta_damage = float(b.get("damage", 0.0))
	meta_xp = float(b.get("xp", 0.0))
	meta_gold = float(b.get("gold", 0.0))
	meta_luck = int(b.get("luck", 0.0))
	meta_redraws = int(b.get("redraws", 0.0))
	meta_banishes = int(b.get("banishes", 0.0))
	meta_start_level = int(b.get("start_level", 0.0))
	locked.clear()
	for r: Variant in b.get("locked", []):
		locked[int(r)] = true
	var armor: Array = b.get("armor", [])
	for p: Player in players.values():
		p.max_hp += int(b.get("hearts", 0.0))
		for st: int in range(mini(armor.size(), Loot.STAT_COUNT)):
			p.armor[st] = minf(float(p.armor[st]) + float(armor[st]), float(Loot.STAT_CAPS[st]))
		p.max_hp += int(float(armor[Loot.ST_VIGOR])) if armor.size() > Loot.ST_VIGOR else 0
		p.hp = p.max_hp
		p.bombs += int(b.get("novas", 0.0))
		for r: int in locked:
			p.banned[r] = true

## Gives wizard `p` a saved hero (Hero.to_dict(); docs/classes_design.md). Call after apply_meta, before the first
## step. The class's hearts replace BASE_HEARTS; the hero's stats (race, class, points and its own sockets) add to
## the armour array within Loot.STAT_CAPS; then threat, the nova button's skill, the class weapon in place of the
## starting spell (while it is still the only one, at level 1) with its skin (Player.class_weapon, Player.skin:
## Classes.SKINS), the class passive and the race trait. A wizard
## with no hero applied keeps every neutral default, so it plays exactly as before. The game sends a hero's sockets
## only here (Profile.bonuses carries none), so each card counts once and only for its hero.
func apply_hero(p: Player, hero: Dictionary) -> void:
	var h := Hero.from_dict(hero)
	p.race = h.race
	p.cls = h.cls
	p.look = h.look
	p.cls_level = h.level
	var st: Array = h.stats()
	var vigor_before := int(float(p.armor[Loot.ST_VIGOR]))
	for i: int in range(Loot.STAT_COUNT):
		p.armor[i] = minf(float(p.armor[i]) + float(st[i]), float(Loot.STAT_CAPS[i]))
	p.max_hp = maxi(1, p.max_hp + Classes.hearts(h.cls) - BASE_HEARTS + int(float(p.armor[Loot.ST_VIGOR])) - vigor_before)
	p.hp = p.max_hp
	p.threat = Classes.threat(h.cls)
	p.threat_k = 1.0 / (p.threat * p.threat)
	p.skill = Classes.skill(h.cls)
	p.walk_mul = Classes.walk_mul(h.cls)
	p.ritual_mul = Classes.ritual_mul(h.cls)
	p.redraws += Classes.extra_redraws(h.cls)
	p.aura_r = Classes.aura_radius(h.cls)
	p.aura_ward = Classes.aura_ward(h.cls) * float(Hero.POINT_VALUE[Loot.ST_WARD])
	p.fury = Races.trait_amount(h.race, Races.TR_FURY)
	p.reach_mul = 1.0 + Races.trait_amount(h.race, Races.TR_FAR_SIGHT)
	p.safe_mul = 1.0 + Races.trait_amount(h.race, Races.TR_STURDY)
	p.luck = h.luck()
	var start := Wizards.start_spell(p.wizard)
	var sp := h.weapon()
	p.skin = Classes.weapon_skin(h.cls, sp)
	p.class_weapon = sp if p.skin != "" else -1
	var start_row := Upgrades.weapon_entry(start)
	if sp != start and p.upgrades.size() == 1 and int(p.upgrades.get(start_row, 0)) == 1:
		p.upgrades.erase(start_row)
		p.upgrades[Upgrades.weapon_entry(sp)] = 1
		p.cds.fill(0.0)
	WorldCasting._refresh_spell(self, p)
	_open_own_rows(p)
	var lo := INF
	var hi := 0.0
	for q: Player in players.values():
		lo = minf(lo, q.threat)
		hi = maxf(hi, q.threat)
	threat_spread = maxf(1.0, hi / maxf(lo, 0.01))

## A hero's own class weapon (Player.class_weapon), the arcana of its evolution and that evolution are open to her
## whatever the table's mask says: they leave her banned when the mask put them there.
func _open_own_rows(p: Player) -> void:
	if p.class_weapon < 0:
		return
	for r: int in [Upgrades.weapon_entry(p.class_weapon), Upgrades.partner_row(p.class_weapon), Upgrades.evo_entry(p.class_weapon)]:
		if r >= 0 and locked.has(r):
			p.banned.erase(r)

## The live enemy cap: LEGION's seal_cap when a Seal sets one, else Tuning's enemy_cap.
func enemy_cap() -> int:
	return seal_cap if seal_cap > 0 else int(tune.enemy_cap)

## Starts the run at a difficulty level (Net.seal, SEAL_EASY..SEAL_MAX): copies Seals.values into the seal_*
## fields (never into Tuning) and sets the wizards' hearts, lives and banned cards. Call once, after apply_meta.
## Level 0 changes nothing.
func apply_seal(level: int) -> void:
	seal = clampi(level, SEAL_EASY, SEAL_MAX)
	var v := Seals.values(seal)
	seal_hp = float(v.hp)
	seal_horde = float(v.horde)
	seal_boss = float(v.boss)
	seal_speed = float(v.speed)
	seal_potions = float(v.potions)
	seal_luck = int(v.luck)
	seal_cards = 1.0 + Seals.CARD_PER_LUCK * int(v.luck)
	seal_ultra = bool(v.ultra)
	seal_rift = float(v.rift)
	seal_potion_heal = int(v.potion_heal)
	seal_group = float(v.group)
	seal_cap = int(v.cap)
	seal_elite_hp = float(v.elite_hp)
	seal_escort = int(v.escort)
	seal_hand = int(v.hand)
	seal_ritual = float(v.ritual)
	seal_card = Seals.card(seal)
	if float(v.cruel) > 0.0:
		fate_cruel = float(v.cruel)
	for p: Player in players.values():
		p.max_hp += int(v.hearts)
		p.hp += int(v.hearts)
		if int(v.lives) > 0:
			p.lives = int(v.solo_lives) if players.size() == 1 else int(v.lives)
		if not bool(v.judgement):
			p.banned[Upgrades.LIFE] = true

## Merges the run's Reading (Net.reading, a Readings key) after the Seal's: call once, after apply_seal and
## before the first step. Readings.MERGE_MUL multiply the seal_* fields, hearts are given the way apply_seal gives
## a Seal's, and every other value sets read_<key> for its rule. A Reading that is only merged numbers has landed
## here and is credited here; one with a rule is credited where the rule fires (Results.use). "" or an unknown
## key changes nothing.
func apply_reading(key: String) -> void:
	var v := Readings.values(key)
	if v.is_empty():
		return
	reading = key
	var rules := 0
	for k: String in v:
		if Readings.MERGE_MUL.has(k):
			set("seal_" + k, float(get("seal_" + k)) * float(v[k]))
		elif Readings.MERGE_ADD.has(k):
			for p: Player in players.values():
				p.max_hp += int(v[k])
				p.hp += int(v[k])
		else:
			set("read_" + k, v[k])
			rules += 1
	if rules == 0:
		record.use(key)

func slot_cap() -> Vector2i:
	return slots

## The wizards human players control, in slot order (apprentices left out).
func humans() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in players.values():
		if not p.ai:
			out.append(p)
	return out

## The fallen waiting for a revive: [slot, x, y, revive 0..1, down_left s (-1: a ritual only)] each.
func graves() -> Array:
	var out: Array = []
	for p: Player in players.values():
		if p.down:
			out.append([p.slot, p.pos.x, p.pos.y, p.revive, p.down_left])
	return out

## True if a wizard who is not standing can still come back into this run with nobody's help: a dead solo wizard
## with a life left, or a fallen one with a life to spare (one on her last life needs a ritual or a slain Lich).
func can_return(p: Player) -> bool:
	return p.lives > 1 if p.down else p.lives > 0

func total_kills() -> int:
	var n := departed_kills
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

## The party's size for health scaling (enemies and bosses): a wizard counts 1, an apprentice tune.apprentice_scale;
## never under 1. The number of wizards when every seat is human.
func party_weight() -> float:
	var n := 0.0
	for p: Player in players.values():
		n += tune.apprentice_scale if p.ai else 1.0
	return maxf(n, 1.0)

func emit(code: int, x: float = 0.0, y: float = 0.0, a: Variant = 0, b: Variant = 0) -> void:
	events.append([code, x, y, a, b])

func take_events() -> Array:
	var e := events
	events = []
	return e

# ================================================================= STEP ===
func step(dt: float, inputs: Dictionary) -> void:
	inputs = WorldApprentices.with_inputs(self, inputs)
	if phase != PH_GAMEOVER:
		WorldLevels._update_levelups(self, inputs)
	time += dt
	_tick += 1
	for i in 4:
		door_open[i] = maxf(0.0, door_open[i] - dt)
	match phase:
		PH_INTRO:
			phase_t -= dt
			if phase_t <= 0.0 and not WorldLevels._intro_held(self): # THE HEAD START's hands hold the door
				phase = PH_FIGHT
				WorldDrops._refill_urns(self)
		PH_FIGHT:
			if won:
				WorldShrines._tick_won(self, dt)
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
	WorldEnemies._sep_fill(self) # after the wizards: a ritual can push enemies
	for e in enemies:
		if not e.dead:
			WorldEnemies._update_enemy(self, e, dt)
	WorldHazards._update_hazards(self, dt)
	WorldCastBolts._update_shots(self, dt)
	WorldCastCircles._update_runes(self, dt)
	WorldCasting._update_bursts(self)
	WorldEnemies._update_eshots(self, dt)
	if phase != PH_GAMEOVER: # the run is decided: nothing on the floor is taken or broken any more
		WorldDrops._update_pickups(self, dt)
		WorldDrops._update_urns(self)
	enemies = enemies.filter(func(e): return not e.dead)
	shots = shots.filter(func(s): return not s.dead)
	runes = runes.filter(func(c: Rune) -> bool: return c.age < c.life)
	eshots = eshots.filter(func(s): return not s.dead)
	if phase != PH_GAMEOVER and not won:
		WorldPlayers._last_stand(self)
		var any := false
		# The run ends with its humans: one still in it, or fallen while anyone stands to raise her (apprentices play
		# on alone only when no seat is human).
		var seats := humans()
		var standing := false
		for p in _plist:
			standing = standing or p.alive
		for p in (seats if not seats.is_empty() else _plist):
			if p.alive or can_return(p) or (p.down and standing):
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

## The run as _end_run would report it now, for a run that ends without a game over (QUIT TO TITLE, the window
## closing): "results" is the EV_RESULTS record, the rest EV_GAMEOVER's numbers, "won" true in the victory
## countdown, "urns" the urns broken (urns_broken). Read-only: it changes no state and draws no random number.
func run_so_far() -> Dictionary:
	var rec := record.to_dict()
	var st: Dictionary = rec.stats
	for p: Player in players.values():
		if st.has(p.slot):
			st[p.slot]["level"] = float(p.level)
			st[p.slot]["kills"] = float(p.kills)
	return {"score": total_score(), "seconds": wave_time, "kills": total_kills(), "liches": liches_slain, "won": won,
		"results": rec, "urns": urns_broken}

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

## A wizard leaves the run (her machine left the game): her level and kills go to the record, her score and kills
## stay in total_score and total_kills, and she is gone from the floor.
func remove_player(slot: int) -> void:
	var p: Player = players.get(slot)
	if p == null:
		return
	record.set_stat(slot, "level", p.level)
	record.set_stat(slot, "kills", p.kills)
	departed_score += p.score
	departed_kills += p.kills
	players.erase(slot)
	apprentice_bots.erase(slot)
	_plist.assign(players.values())

# ============================================================ LEVEL-UPS ===

## XP the party needs for its next level: the solo curve, grown with the party size. THE HEAD START's levels are not
## priced (head_start_levels), so its lead lasts.
func xp_needed() -> int:
	var n := 0.0
	for p: Player in players.values():
		n += tune.apprentice_scale if p.ai else 1.0 # an apprentice counts like it does for the horde
	var scale := 1.0 + tune.xp_party_scale * (n - 1.0)
	return maxi(1, int(round(tune.xp_to_next(party_level - head_start_levels) * maxf(scale, 0.0))))

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
	var s := departed_score
	for p in players.values():
		s += p.score
	return s

# =============================================================== PLAYER ===

## The middle of the living wizards, or of the arena when none is alive.
func party_center() -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for p: Player in _plist: # not players.values(): that builds an array, and brains ask every tick
		if p.alive:
			c += p.pos
			n += 1
	return c / n if n > 0 else G.ARENA.get_center()

# ================================================================ GRID ===
func _build_grid() -> void:
	_grid.clear()
	_sep_cells.clear()
	_sep_who.assign(enemies)
	_sep_ok = false
	alive.fill(0)
	var i := -1
	for e in enemies:
		i += 1
		if e.dead:
			continue
		alive[e.type] += 1
		var at: Vector2 = e.pos
		var k := Vector2i(floori(at.x / CELL), floori(at.y / CELL))
		var cell: Variant = _grid.get(k)
		if cell != null:
			cell.append(e)
			_sep_cells[k].append(i)
		else:
			_grid[k] = [e]
			_sep_cells[k] = PackedInt32Array([i])

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
	var h := [snapshot(), wave, phase, total_score(), rng.state, horde_budget, party_level, party_xp, lull_left, players.values().map(func(p: Player) -> int: return p.pending)]
	if not fate_heal.is_empty():
		h.append(WorldShrines.held_heals(self))
	# Only when present, so a run without them hashes as it always did.
	if not hazards.is_empty():
		h.append(hazards.map(func(z: Hazards.Hazard) -> Array: return [z.owner, z.aux, z.slot, z.fired, z.follow, z.lock, z.boss]))
	if boss != null and boss.turn > 0.0:
		h.append(boss.turn)
	return hash(h)

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
			2.0 if e.final else (1.0 if e.elite else 0.0),
			e.status | (STATUS_CLOAK if e.cloak else 0) | (STATUS_TURN if e.turn > 0.0 else 0)])
	var sh := PackedFloat32Array()
	for s in shots:
		sh.append_array([s.kind, s.pos.x, s.pos.y, s.vel.x, s.vel.y, s.owner])
	var rn := PackedFloat32Array()
	for c: Rune in runes:
		rn.append_array([c.pos.x, c.pos.y, c.r, c.age, c.life, c.owner, float(c.evo), c.kind])
	var es := PackedFloat32Array()
	for s in eshots:
		es.append_array([s.kind, s.pos.x, s.pos.y, s.vel.x, s.vel.y])
	var pk := PackedFloat32Array()
	for k in pickups:
		pk.append_array([k.kind, k.pos.x, k.pos.y, k.life])
	var bf := -1.0
	var btype := -1
	var bphase := 0
	if boss and not boss.dead:
		bf = boss.hp / boss.maxhp
		btype = boss.type
		bphase = Bosses.phase(boss.type, bf, boss.final)
	var shr := PackedFloat32Array()
	for r: Array in WorldShrines.snapshot_shrines(self):
		shr.append_array(r)
	var snap := {
		"p": pl, "e": en, "s": sh, "r": rn, "es": es, "k": pk, "sh": shr, "u": _snapshot_urns(), "o": PackedFloat32Array(),
		"hz": Hazards.pack(hazards), "lk": _snapshot_locked(),
		"w": PackedFloat32Array([wave, phase, phase_t, bf, door_open[0], door_open[1], door_open[2], door_open[3], wave_time,
			1.0 if boss != null and boss.final else 0.0, lull_left, seal, slots.x, slots.y,
			btype, bphase, boss_t, boss_arg, boss_meter, Readings.index_of(reading)]),
	}
	WorldShrines.snapshot_fates(self, snap)
	return snap

## The table's locked rows (World.locked), sorted: every seat reads the same mask.
func _snapshot_locked() -> PackedInt32Array:
	var out := PackedInt32Array(locked.keys())
	out.sort()
	return out

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

func _cast(p: Player, sp: int, lv: int, evo: int, dir: Vector2) -> void:
	WorldCasting._cast(self, p, sp, lv, evo, dir)

func _shot(slot: int, sp: int, evo: int, pos: Vector2, vel: Vector2, dmg: float, pierce: int) -> void:
	WorldCastBolts._shot(self, slot, sp, evo, pos, vel, dmg, pierce)

func _refresh_spell(p: Player) -> void:
	WorldCasting._refresh_spell(self, p)

func hurt_player(p: Player, dmg: int) -> void:
	WorldPlayers.hurt_player(self, p, dmg)

func _damage_enemy(e: Enemy, dmg: float, slot: int, knock: Vector2) -> void:
	WorldEnemies._damage_enemy(self, e, dmg, slot, knock)

## Hurts an enemy as `slot` (-1: nobody's); `sure` ignores facing and shields (Brains.filter_damage).
func damage_enemy(e: Enemy, dmg: float, slot: int, knock: Vector2, sure: bool = false) -> void:
	WorldEnemies._damage_enemy(self, e, dmg, slot, knock, sure)

## An enemy shot, or null when it is dropped past Bestiary.ESHOT_CAP.
func eshot(kind: int, pos: Vector2, vel: Vector2, r: float) -> EShot:
	return WorldEnemies._eshot(self, kind, pos, vel, r)

func _spawn_boss(type: int, final: bool) -> Enemy:
	return Bosses._spawn_boss(self, type, final)

func _boss_died(e: Enemy, slot: int) -> void:
	Bosses._boss_died(self, e, slot)

func phase_turn(e: Enemy, secs: float) -> void:
	Bosses.phase_turn(self, e, secs)

## A hazard row (WorldHazards.add_hazard), or null when the floor is full.
func add_hazard(kind: int, a: Vector2, b: Vector2, r: float, warn: float, hot: float, slot: int = -1, owner: int = 0,
		forced: bool = false) -> Hazards.Hazard:
	return WorldHazards.add_hazard(self, kind, a, b, r, warn, hot, slot, owner, forced)

func move_hazard(h: Hazards.Hazard, a: Vector2, b: Vector2) -> void:
	WorldHazards.move_hazard(self, h, a, b)

func _update_hazards(dt: float) -> void:
	WorldHazards._update_hazards(self, dt)

## Removes the hazard rows: every one with `all`, else the regular ones (not a boss's).
func clear_hazards(all: bool) -> void:
	hazards = hazards.filter(func(h: Hazards.Hazard) -> bool: return h.boss and not all)

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
	WorldCastBolts._update_shots(self, dt)

func _shot_hit(s: Shot, e: Enemy) -> void:
	WorldCastBolts._shot_hit(self, s, e)

func _explode(s: Shot) -> void:
	WorldCastBolts._explode(self, s)

func _update_runes(dt: float) -> void:
	WorldCastCircles._update_runes(self, dt)

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

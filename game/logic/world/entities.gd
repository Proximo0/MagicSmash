class_name WorldEntities
extends RefCounted
## The things World simulates: wizards, enemies, shots, rune circles, enemy shots, shrines and pickups. World
## aliases each class (World.Player is WorldEntities.Player), so code names them through World.

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
	var level := 1 # follows World.party_level
	var upgrades := {} # Upgrades index -> level
	var choices: Array[int] = [] # upgrades offered right now; they wait in hand until the wizard takes one
	var offer := 0 # id of the current offer; a pick input must name it
	var pending := 0 # level-ups still to offer after the current one
	var regen_t := 0.0
	var max_hp := 5
	var gold := 0.0 # run gold; only exists inside a run
	var armor: Array = Loot.empty_stats() # Loot.ST_* totals from armor found in chests
	## Wave 2 fields, all neutral until their jobs land (snapshot row: World.P_REDRAWS onward).
	var redraws := 0 # redraws of the hand left
	var banishes := 0 # banishes left
	var banned := {} # Upgrades index -> true: rows banished from this wizard's pool
	var down := false # fallen, waiting for a revive
	var down_left := 0.0 # seconds until a fallen wizard gets up by itself; -1 = only a ritual brings them back
	var down_t := 0.0 # seconds spent down this time
	var revive := 0.0 # revive progress 0..1
	var rituals := 0 # rituals that raised this wizard (each later one takes tune.ritual_step longer)
	var call_t := 0.0 # seconds until this wizard may call for help again
	var ai := false # the World plays this seat: an apprentice (a computer wizard), or a human seat gone silent
	var away := false # with ai: a human seat gone silent (played, but still a human for the free get-up and her cards)
	var trait_a := 0 # wave 3 traits; 0 = none
	var trait_b := 0
	## Race and class (snapshot row P_RACE..P_CLASS_LEVEL): the seat's, or the hero's from World.apply_hero.
	var race := 0
	var cls := 0
	var look := 0 # packed: skin, hair, style
	var cls_level := 0
	var threat := 1.0 # how much the horde minds this wizard (Classes threat): enemies pick by distance / threat
	var threat_k := 1.0 # 1 / threat^2: what the targeting scales a squared distance by (exactly 1 at threat 1)
	## Set by World.apply_hero (docs/classes_design.md); neutral for a wizard with no hero.
	var skill := 0 # Classes.SK_*: what the nova button does
	var walk_mul := 1.0 # class passive: walk speed
	var ritual_mul := 1.0 # class passive: how much this wizard counts inside a ritual circle
	var aura_r := 0.0 # class passive: px within which heroes (her too) get aura_ward more WARD; 0 = none
	var aura_ward := 0.0
	var fury := 0.0 # race trait: damage share added at Races.FURY_HEARTS hearts or fewer
	var reach_mul := 1.0 # race trait: XP magnet reach
	var safe_mul := 1.0 # race trait (STURDY): the hurt safety after a hit x this (WorldPlayers.hurt_player)
	var luck := 0.0 # FORTUNE's chest luck (WorldDrops._open_chest)
	## The class weapon (World.apply_hero): the World.SP_* spell the hero's class skin dresses (Classes.SKINS: its
	## name, look and overrides such as range and the heal), -1 and "" for a wizard with no hero or a mage.
	var class_weapon := -1
	var skin := ""
	var vigil := 0.0 # s left of a vigil candle's cast speed (she stood in a light)
	var light_heal_t := 0.0 # s her lights have burned towards their next heal (HOLY LIGHT, CONSECRATION)
	var swift_moved := false # THE CHARIOT's credit: she moved in this game second (WorldPlayers._update_player)

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
	var status := 0 # status bits (burning, frozen and so on); none yet
	var flags := 0 # Bestiary.F_* of its kind, copied at spawn
	var cloak := false # shots fly through it and nothing hurts it (a brain sets it; see WorldEnemies._faded)
	var turn := 0.0 # s left of a boss's phase turn (Bosses.phase_turn): it holds still and takes no damage
	var gi := -1 # its row in World's separation copy this tick (World._sep_pos); -1 when it is not in it
	var taunt: Player = null # a PROVOKE: the wizard it wants while taunt_t runs, whoever is nearer
	var taunt_t := 0.0

class Shot:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var kind := 0 # Spells.shot_kind(spell, evo): what clients draw
	var spell := 0
	var evo := 0 # evolution id (Spells.evo_row): 0 none
	var pierce := 0 # enemies it may still pass through
	var hits := {} # enemy ids already hit by a piercing shot
	var dmg := 1.0
	var owner := 0
	var life := 1.0
	var r := 3.0
	var dead := false
	var splinter := false # an Ossuary Lance splinter: it never splinters again

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
	var evo := 0 # evolution id (Spells.evo_row): 0 none
	var pull := 0.0
	var kind := 0 # Spells.CIRCLE_*: the rune circle spell or a vigil candle's light

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
	var charge := 0.0 # seconds a wizard who can pay has stood on it (SOLO)
	var who := -1
	var pot := 0.0 # gold the table has paid in so far (TEAM)
	var paid: Dictionary = {} # slot -> gold she has paid into the pot (TEAM)

class Pickup:
	var kind := 0
	var value := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 10.0
	var moon := -1 # the seat whose THE MOON began this gem's pull from beyond her plain reach (the magnet credit)

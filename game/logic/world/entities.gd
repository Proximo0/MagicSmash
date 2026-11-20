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

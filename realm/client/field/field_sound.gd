class_name FieldSound
extends Node
## Sound hooks of the field: `hook("kill")` and the like play a group of the sound effects (audio/sfx.gd, the
## files made by tools/sfx/sfx.py). Each hook has its own least gap, and Sfx limits voices and plays per group
## on top, so ten thousand monsters dying are a few thumps. Kills sound only near the listener (the hero).
## Hooks: hit (own health fell), kill, bigkill, skill, ult, melee, level, down, ally_down, raise, potion, bank,
## pick, draw, tide, boss, boss_down, portal, bad.

## Each hook: the Sfx group it plays, least gap s.
const HOOKS: Dictionary = {
	"hit": ["hurt", 0.25],
	"kill": ["mon_small", 0.03],
	"bigkill": ["mon_big", 0.12],
	"melee": ["hit", 0.05],
	"skill": ["spell", 0.1],
	"ult": ["crit", 0.3],
	"level": ["level_up", 0.3],
	"down": ["hero_death", 0.4],
	"ally_down": ["hurt", 0.3],
	"raise": ["bell", 0.3],
	"potion": ["item", 0.15],
	"bank": ["gold", 0.3],
	"pick": ["item", 0.1],
	"draw": ["rare", 0.5],
	"tide": ["horn", 1.0],
	"boss": ["boss_roar", 1.0],
	"boss_down": ["boss_death", 1.0],
	"portal": ["portal", 1.0],
	"bad": ["ui_error", 0.2],
}
## Kills farther than this from the listener are silent (px).
const NEAR_PX: float = 900.0

var muted: bool = false
## Where the hero is (set by the field client each frame).
var listener: Vector2 = Vector2.ZERO
## Hooks played, by name (the tests read it).
var played: Dictionary = {}
var _last: Dictionary = {}


func hook(name: String) -> void:
	if not HOOKS.has(name):
		return
	var now: float = Time.get_ticks_usec() / 1000000.0
	if now - float(_last.get(name, -10.0)) < float(HOOKS[name][1]):
		return
	_last[name] = now
	played[name] = int(played.get(name, 0)) + 1
	if not muted:
		Sfx.play(String(HOOKS[name][0]))


## Plays the hooks the event rows of one frame call for. `me` is this hero's id.
func from_events(ev: PackedInt32Array, me: int) -> void:
	var kills: int = 0
	var big: bool = false
	for i in ev.size() / FieldFx.EV_STRIDE:
		var o: int = i * FieldFx.EV_STRIDE
		var mine: bool = ev[o + 1] == me
		match ev[o]:
			FieldFx.EV_KILL:
				if Vector2(ev[o + 5], ev[o + 6]).distance_to(listener) <= NEAR_PX:
					kills += 1
					big = big or (ev[o + 4] & (FieldFx.ELITE | FieldFx.CHAMPION)) != 0
			FieldFx.EV_GRANT:
				if mine:
					hook("level")
			FieldFx.EV_DOWN:
				hook("down" if mine else "ally_down")
			FieldFx.EV_RAISE:
				hook("raise")
			FieldFx.EV_BANK:
				if mine:
					hook("bank")
			FieldFx.EV_POTION:
				if mine:
					hook("potion")
			FieldFx.EV_PICK:
				if mine:
					hook("pick")
			FieldFx.EV_DRAW:
				if mine:
					hook("draw")
			FieldFx.EV_SKILL:
				if mine:
					match ev[o + 2]:
						1:
							hook("melee")
						3:
							hook("ult")
						_:
							hook("skill")
	if big:
		hook("bigkill")
	elif kills > 0:
		hook("kill")

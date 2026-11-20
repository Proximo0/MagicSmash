extends "res://tests/sim/sim_base.gd"
## Bot personas play solo runs in the pure simulation: a better persona must take clearly fewer hits per minute
## (VETERAN < CASUAL < NOVICE, each by MARGIN). Moved out of the unit tests because it plays whole minutes.

const SEEDS: Array[int] = [1, 2, 3]
const MINUTES: float = 0.7
## How much better each persona must be: hits/min of the better one times MARGIN stays under the worse one's.
const MARGIN: float = 1.2


## Hits per minute of run clock a persona takes playing solo over SEEDS.
func _hits_per_min(persona: int) -> float:
	var hits: int = 0
	var time: float = 0.0
	for sd: int in SEEDS:
		var w := World.new([0], sd)
		var bot := SmashBot.new(sd * 10, persona)
		while w.phase != World.PH_GAMEOVER and w.wave_time < MINUTES * 60.0:
			w.step(DT, {0: bot.decide_in_world(w, 0)})
			for ev: Array in w.take_events():
				if ev[0] == World.EV_HURT:
					hits += 1
		time += w.wave_time
	return hits / maxf(time / 60.0, 0.1)


func run() -> Array:
	var nov: float = _hits_per_min(SmashBot.NOVICE)
	var cas: float = _hits_per_min(SmashBot.CASUAL)
	var vet: float = _hits_per_min(SmashBot.VETERAN)
	return [
		row("veteran_beats_casual", vet * MARGIN < cas, "veteran %.2f casual %.2f hits/min (margin %.1fx)" % [vet, cas, MARGIN]),
		row("casual_beats_novice", cas * MARGIN < nov, "casual %.2f novice %.2f hits/min (margin %.1fx)" % [cas, nov, MARGIN]),
	]

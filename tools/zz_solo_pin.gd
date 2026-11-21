extends RefCounted
const DT := 1.0 / 60.0
func run(args: PackedStringArray) -> int:
	var ban: bool = args.has("--ban")
	var w := World.new([0], 11, Tuning.new())
	if ban and Upgrades.count() > 24:
		for i: int in range(24, Upgrades.count()):
			w.players[0].banned[i] = true
	var bot := SmashBot.new(11)
	for i: int in range(60 * 40):
		if i == 60 * 20:
			w.players[0].invuln = 0.0
			w.hurt_player(w.players[0], 99)
		var inp: PackedFloat32Array = bot.decide_in_world(w, 0)
		var p: World.Player = w.players[0]
		if not p.choices.is_empty():
			inp = SmashBot.with_pick(inp, p.choices, p.offer)
		w.step(DT, {0: inp})
		w.take_events()
	var rows: Array = [w.rng.state, w.wave, w.phase, w.total_score(), w.players[0].pos, w.players[0].hp,
		w.players[0].lives, w.players[0].upgrades, w.record.stat(0, "deaths"), w.enemies.size()]
	print("PIN ", hash(rows))
	return 0

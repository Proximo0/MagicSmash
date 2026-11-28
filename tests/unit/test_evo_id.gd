extends TestCase
## The evolution id (stage 3 brief § 4.1): 0 none, 1 the evolution Spells.EVOS holds, 2 the one in Spells.EVOS2.
## Every value the game sends today (shot kinds, snapshot levels, the rune column, EV_RUNE's b) is unchanged.

## Today's evolution rows, one per spell (World.SP_* order).
const TODAY_EVOS: Array[int] = [Upgrades.E_ARCANE, Upgrades.E_FIRE, Upgrades.E_FROST, Upgrades.E_STORM,
	Upgrades.E_STAR, Upgrades.E_RUNE, Upgrades.E_BONE, Upgrades.E_CANDLE, Upgrades.E_CLEAVE, Upgrades.E_HEX,
	Upgrades.E_BLADES]
## The second evolutions (evolution id 2), -1 for a spell with none (content list § 37).
const SECOND_EVOS: Array[int] = [Upgrades.E_LODESTAR, Upgrades.E_GREEK, Upgrades.E_VEIL, Upgrades.E_DIES, -1, -1, -1,
	-1, -1, -1, -1]
## Shot kinds as the code drew them before the id: plain, then evolved, per spell (HEX and SPIRIT BLADES by the
## same block rule).
const PLAIN_KINDS: Array[int] = [0, 1, 2, 3, 4, 5, 12, 13, 14, 15, 16]
const EVOLVED_KINDS: Array[int] = [6, 7, 8, 9, 10, 11, 18, 19, 20, 21, 22]


func _world() -> World:
	var w := World.new([0, 1], 3, Tuning.new())
	w.phase = World.PH_FIGHT
	return w


func test_evo_row_by_id() -> void:
	for sp: int in range(Spells.COUNT):
		assert_eq(Spells.evo_row(sp, 0), {}, "id 0 has no row")
		assert_eq(Spells.evo_row(sp, 1), Spells.EVOS[sp])
		assert_eq(Spells.evo_row(sp, 2), Spells.EVOS2[sp])
		assert_eq(Spells.evo_row(sp, 2).is_empty(), SECOND_EVOS[sp] < 0, "a second evolution for each school")
		assert_eq(Spells.evolutions(sp), 1 if SECOND_EVOS[sp] < 0 else 2, Spells.spell_name(sp))
	assert_eq(Spells.EVOS2.size(), Spells.COUNT)


func test_stats_read_the_row_of_the_id() -> void:
	for sp: int in range(Spells.COUNT):
		var row: Dictionary = Spells.EVOS[sp]
		assert_eq(Spells.cooldown(sp, Spells.MAX_LEVEL, 1), float(row["cd"]))
		assert_eq(Spells.damage(sp, Spells.MAX_LEVEL, 1), float(row["dmg"]))
		assert_eq(Spells.count(sp, Spells.MAX_LEVEL, 1), int(row["n"]))
		assert_eq(Spells.damage(sp, Spells.MAX_LEVEL, 0), float(Spells.STATS[sp]["dmg"][Spells.MAX_LEVEL - 1]))
	assert_eq(Spells.evo_value(World.SP_RUNE, "pull", 1, 0.0), float(Spells.EVOS[World.SP_RUNE]["pull"]))
	assert_eq(Spells.evo_value(World.SP_RUNE, "pull", 0, -1.0), -1.0, "id 0 has no specials")
	assert_eq(Spells.evo_value(World.SP_RUNE, "pull", 2, -1.0), -1.0, "id 2 never falls back to EVOS")
	assert_eq(Spells.level_value(World.SP_RUNE, "r", Spells.MAX_LEVEL, 2), Spells.level_value(World.SP_RUNE, "r", Spells.MAX_LEVEL, 0))
	assert_eq(Spells.bolt_value(World.SP_FROST, "slow", 2, 0.0), Spells.FROST_SLOW, "an empty id 2 row keeps the plain value")
	assert_eq(Spells.bolt_value(World.SP_FROST, "slow", 1, 0.0), float(Spells.EVOS[World.SP_FROST]["slow"]))


func test_shot_kinds_round_trip() -> void:
	var seen := {}
	for sp: int in range(Spells.COUNT):
		assert_eq(Spells.shot_kind(sp, 0), PLAIN_KINDS[sp])
		assert_eq(Spells.shot_kind(sp, 1), EVOLVED_KINDS[sp])
		assert_eq(Spells.shot_kind(sp, 2), Spells.SHOT_SECOND + sp)
		for evo: int in [0, 1, 2]:
			var k := Spells.shot_kind(sp, evo)
			assert_false(seen.has(k), "two shots share kind %d" % k)
			seen[k] = true
			assert_eq(Spells.shot_spell(k), sp)
			assert_eq(Spells.shot_evo(k), evo)
	assert_eq(Spells.SHOT_SECOND, 24)


func test_catalog_ids_today() -> void:
	for sp: int in range(Spells.COUNT):
		var e: int = TODAY_EVOS[sp]
		assert_eq(Upgrades.evo_entry(sp), e)
		assert_eq(Upgrades.evo_entry(sp, 1), e)
		assert_eq(Upgrades.evo_entry(sp, 2), SECOND_EVOS[sp])
		if SECOND_EVOS[sp] >= 0:
			assert_eq(Upgrades.evo_id(SECOND_EVOS[sp]), 2)
		assert_eq(Upgrades.evo_entry(sp, 0), -1)
		assert_eq(Upgrades.evo_id(e), 1)
		assert_eq(Upgrades.evo_id(Upgrades.weapon_entry(sp)), 0, "a spell row is no evolution")
		var levels := {Upgrades.weapon_entry(sp): Spells.MAX_LEVEL}
		assert_eq(Upgrades.evo_of(levels, sp), 0)
		assert_false(Upgrades.evolved(levels, sp))
		levels[e] = 1
		assert_eq(Upgrades.evo_of(levels, sp), 1)
		assert_true(Upgrades.evolved(levels, sp))
	assert_eq(Upgrades.evo_id(Upgrades.QUICK), 0)
	assert_eq(Upgrades.evo_id(-1), 0)


func test_one_evolution_shuts_the_other() -> void:
	# Two catalog rows stand in for one spell's two evolutions (the catalog has no second one yet).
	var rows: Array[int] = [Upgrades.E_ARCANE, Upgrades.E_FIRE]
	assert_false(Upgrades.evo_shut({}, Upgrades.E_FIRE, rows), "nothing taken shuts nothing")
	assert_true(Upgrades.evo_shut({Upgrades.E_ARCANE: 1}, Upgrades.E_FIRE, rows), "the second is shut by the first")
	assert_true(Upgrades.evo_shut({Upgrades.E_FIRE: 1}, Upgrades.E_ARCANE, rows), "the first is shut by the second")
	assert_false(Upgrades.evo_shut({Upgrades.E_ARCANE: 1}, Upgrades.E_FROST, rows), "a row of another spell is open")
	# Each school's two evolutions, in catalog order; a spell with one shuts nothing else.
	for sp: int in range(Spells.COUNT):
		var want: Array[int] = [TODAY_EVOS[sp]]
		if SECOND_EVOS[sp] >= 0:
			want.append(SECOND_EVOS[sp])
		assert_eq(Upgrades.evo_rows(sp), want)


func test_snapshot_weapon_level() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	p.upgrades[Upgrades.weapon_entry(World.SP_FIRE)] = Spells.MAX_LEVEL
	assert_eq(WorldCasting._weapon_snap(w, p, World.SP_FIRE), Spells.MAX_LEVEL)
	p.upgrades[Upgrades.E_FIRE] = 1
	assert_eq(WorldCasting._weapon_snap(w, p, World.SP_FIRE), Spells.MAX_LEVEL + 1)


func test_shot_and_rune_hold_the_id() -> void:
	var s := World.Shot.new()
	s.evo = 2
	assert_eq(s.evo, 2)
	var rn := World.Rune.new()
	rn.evo = 2
	assert_eq(rn.evo, 2)
	var w := _world()
	for evo: int in [0, 1, 2]:
		var shot := WorldCastBolts._shot(w, 0, World.SP_FIRE, evo, Vector2(100, 100), Vector2.RIGHT, 1.0, 0)
		assert_eq(shot.evo, evo)
		assert_eq(shot.kind, Spells.shot_kind(World.SP_FIRE, evo))


func test_rune_column_and_event_today() -> void:
	for evo: int in [0, 1]:
		for slot: int in [0, 1]:
			var w := _world()
			var p: World.Player = w.players[slot]
			p.pos = Vector2(200, 140)
			w.take_events()
			WorldCastCircles._inscribe_runes(w, p, Spells.MAX_LEVEL, evo, Vector2.RIGHT, 1, 1.0)
			assert_eq(w.runes.size(), 1)
			assert_eq(w.runes[0].evo, evo)
			var rn: PackedFloat32Array = w.snapshot()["r"]
			assert_eq(rn[6], 1.0 if evo == 1 else 0.0, "the rune column is today's value")
			var evs: Array = w.take_events().filter(func(ev: Array) -> bool: return int(ev[0]) == World.EV_RUNE)
			assert_eq(evs.size(), 1)
			assert_eq(int(evs[0][4]), slot + (8 if evo == 1 else 0) + 16 * Spells.CIRCLE_RUNE, "EV_RUNE's b is today's value")
	assert_eq(Spells.evo_bits(0), 0)
	assert_eq(Spells.evo_bits(1), 8)
	assert_eq(Spells.evo_bits(2), 12)
	for evo: int in [0, 1, 2]:
		for slot: int in [0, 1, 2, 3]:
			var b := slot + Spells.evo_bits(evo) + 16 * Spells.CIRCLE_CANDLE
			assert_eq(Spells.bits_evo(b), evo)
			assert_eq(b & Spells.EVO_SLOT_MASK, slot)
			assert_eq(b >> 4, Spells.CIRCLE_CANDLE)

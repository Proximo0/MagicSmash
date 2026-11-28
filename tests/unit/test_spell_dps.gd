extends TestCase
## The damage table's arithmetic (tools/spell_dps.gd) without playing ten seconds a row: the wizard a row measures,
## which evolutions a table lists, and what a support spell adds. Probes here last one second on one foe.

const Dps := preload("res://tools/spell_dps.gd")
const PROBE_SECONDS := 1.0
const EVO_CROWD := 6


func _held(sp: int, lv: int, evo: int, mate: Vector3i = Dps.NO_MATE) -> Dictionary:
	var w: World = Dps.new()._world(sp, lv, evo, 0, mate)
	return (w.players[0] as World.Player).upgrades


## A wizard measured with evolution 2 holds the second row and not the first (the game shuts the other road), and
## with 1 the first and not the second; with 0 neither. The weapon is at MAX_LEVEL for an evolution.
func test_a_measured_wizard_holds_the_row_of_its_evolution() -> void:
	var sp := World.SP_ARCANE
	var first: int = Upgrades.evo_entry(sp, 1)
	var second: int = Upgrades.evo_entry(sp, 2)
	assert_true(first >= 0 and second >= 0 and first != second, "arcane bolt has two evolution rows")
	var two := _held(sp, Spells.MAX_LEVEL, 2)
	assert_true(two.has(second), "evolution 2 holds the second row")
	assert_false(two.has(first), "and not the first")
	var one := _held(sp, Spells.MAX_LEVEL, 1)
	assert_true(one.has(first) and not one.has(second), "evolution 1 holds the first row alone")
	var none := _held(sp, 1, 0)
	assert_eq(none.size(), 1, "no evolution: the weapon alone")
	assert_eq(int(none[Upgrades.weapon_entry(sp)]), 1)
	assert_eq(int(two[Upgrades.weapon_entry(sp)]), Spells.MAX_LEVEL, "an evolution sits on a level 5 weapon")
	assert_eq(Upgrades.evo_of(two, sp), 2, "the game reads it as the second road")
	assert_eq(Upgrades.evo_of(one, sp), 1)


## A support spell is added beside the base spell as a second weapon; an evolution of it holds the evolution row.
func test_the_pair_holds_the_base_and_the_support_spell() -> void:
	var held := _held(Dps.BASE_SPELL, Dps.BASE_LEVEL, 0, Vector3i(World.SP_CANDLE, 2, 0))
	assert_eq(held.size(), 2)
	assert_eq(int(held[Upgrades.weapon_entry(Dps.BASE_SPELL)]), Dps.BASE_LEVEL)
	assert_eq(int(held[Upgrades.weapon_entry(World.SP_CANDLE)]), 2)
	var evolved := _held(Dps.BASE_SPELL, Dps.BASE_LEVEL, 0, Vector3i(World.SP_CANDLE, Spells.MAX_LEVEL, 1))
	assert_true(evolved.has(Upgrades.evo_entry(World.SP_CANDLE, 1)), "CONSECRATION held")
	assert_eq(Upgrades.evo_of(evolved, World.SP_CANDLE), 1)
	assert_eq(Upgrades.evo_of(evolved, Dps.BASE_SPELL), 0, "the base spell stays plain")


## Built evolutions are listed in id order; an unbuilt one only with `every`; a spell with one evolution lists one.
func test_unbuilt_evolutions_are_listed_only_with_all() -> void:
	var tool: RefCounted = Dps.new()
	for sp: int in range(Spells.COUNT):
		if Upgrades.UNBUILT.has(Upgrades.weapon_entry(sp)):
			continue
		var all: Array[int] = tool._evos(sp, true)
		var built: Array[int] = tool._evos(sp, false)
		assert_eq(all.size(), Spells.evolutions(sp), "--all lists every evolution of " + Spells.spell_name(sp))
		var want: Array[int] = []
		for evo: int in all:
			assert_eq(evo, all.find(evo) + 1, "id order")
			if not Upgrades.UNBUILT.has(Upgrades.evo_entry(sp, evo)):
				want.append(evo)
			assert_eq(tool._unbuilt_mark(sp, evo), " unbuilt" if Upgrades.UNBUILT.has(Upgrades.evo_entry(sp, evo)) else "")
		assert_eq(built, want, "the default table lists the built ones of " + Spells.spell_name(sp))
	assert_eq(tool._evos(World.SP_CLEAVE, true), [1] as Array[int], "CLEAVE has one evolution")
	assert_eq(tool._evo_name(World.SP_ARCANE, 1), "ASTRAL LANCE", "a line is named by its own evolution")
	assert_eq(tool._evo_name(World.SP_ARCANE, 2), "LODESTAR")


## `added` is pair minus base, the base is the plain bolt alone and the pair is the same wizard with the support
## spell (same seeds, same foes), and the line prints the three.
func test_added_is_pair_minus_base() -> void:
	var tool: RefCounted = Dps.new()
	var r: Dictionary = tool._support(World.SP_CANDLE, 1, 0, 1, PROBE_SECONDS)
	assert_eq(float(r["base"]), tool._dps(Dps.BASE_SPELL, Dps.BASE_LEVEL, 0, 1, PROBE_SECONDS), "base: the bolt alone")
	assert_eq(float(r["pair"]), tool._dps(Dps.BASE_SPELL, Dps.BASE_LEVEL, 0, 1, PROBE_SECONDS,
		Vector3i(World.SP_CANDLE, 1, 0)), "pair: the bolt with the candle")
	assert_eq(float(r["added"]), float(r["pair"]) - float(r["base"]))
	assert_eq(tool._support(World.SP_CANDLE, 1, 0, 1, PROBE_SECONDS), r, "the same seeds and foes give the same numbers")
	for n: int in [1, 2]:
		var q: Dictionary = tool._support(World.SP_CANDLE, 1, 0, n, PROBE_SECONDS)
		assert_eq(float(q["base"]), tool._dps(Dps.BASE_SPELL, Dps.BASE_LEVEL, 0, n, PROBE_SECONDS),
			"the base of a crowd of %d is the bolt alone in that crowd" % n)
	# the evolution is held in the pair: CONSECRATION, not the plain candle, in a crowd where they differ
	var evolved: Dictionary = tool._support(World.SP_CANDLE, Spells.MAX_LEVEL, 1, EVO_CROWD, PROBE_SECONDS)
	var plain: Dictionary = tool._support(World.SP_CANDLE, Spells.MAX_LEVEL, 0, EVO_CROWD, PROBE_SECONDS)
	assert_eq(float(evolved["pair"]), tool._dps(Dps.BASE_SPELL, Dps.BASE_LEVEL, 0, EVO_CROWD, PROBE_SECONDS,
		Vector3i(World.SP_CANDLE, Spells.MAX_LEVEL, 1)), "the pair holds the evolution")
	assert_true(float(evolved["pair"]) != float(plain["pair"]), "and it is not the plain candle's pair")
	assert_eq(float(evolved["base"]), float(plain["base"]), "the base does not depend on the support")
	assert_eq(tool._support_line("X", "L1 one", {"base": 10.0, "pair": 12.5, "added": 2.5}),
		"X                beside ARCANE BOLT 3, L1 one: base=10.0 pair=12.5 added=+2.5")
	assert_eq(tool._support_line("X", "", {"base": 1.0, "pair": 0.5, "added": -0.5}),
		"X                beside ARCANE BOLT 3: base=1.0 pair=0.5 added=-0.5")


## The support list names VIGIL CANDLE and HEX; HEX is skipped while its spell is unbuilt.
func test_the_support_list() -> void:
	assert_true(Dps.SUPPORTS.has(World.SP_CANDLE) and Dps.SUPPORTS.has(World.SP_HEX))
	assert_false(Dps.SUPPORTS.has(Dps.BASE_SPELL))
	assert_eq(Dps.BASE_LEVEL, 3)


## A base and its pair start from the same state: with the support spell's rows taken out of the pair's wizard, the
## two worlds hash alike and the foes and their random draws are the same, for every seed and crowd.
func test_the_base_and_the_pair_start_alike() -> void:
	var tool: RefCounted = Dps.new()
	for mate: Vector3i in [Vector3i(World.SP_CANDLE, 1, 0), Vector3i(World.SP_CANDLE, Spells.MAX_LEVEL, 1)]:
		for foes_n: int in [1, 6]:
			for s: int in range(3):
				var b: Dictionary = tool._start(Dps.BASE_SPELL, Dps.BASE_LEVEL, 0, foes_n, s)
				var q: Dictionary = tool._start(Dps.BASE_SPELL, Dps.BASE_LEVEL, 0, foes_n, s, mate)
				var wb: World = b["w"]
				var wq: World = q["w"]
				var pq: World.Player = wq.players[0]
				assert_true(pq.upgrades.size() > (wb.players[0] as World.Player).upgrades.size(), "the pair holds more")
				var base_only: Dictionary = {}
				for k: Variant in pq.upgrades:
					if Upgrades.spell_of(int(k)) == Dps.BASE_SPELL:
						base_only[k] = pq.upgrades[k]
				pq.upgrades = base_only
				assert_eq(wq.state_hash(), wb.state_hash(), "same world %s foes %d seed %d" % [str(mate), foes_n, s])
				assert_eq((q["rng"] as RandomNumberGenerator).state, (b["rng"] as RandomNumberGenerator).state)
				var fb: Array[World.Enemy] = b["foes"]
				var fq: Array[World.Enemy] = q["foes"]
				for i: int in range(foes_n):
					assert_eq(fq[i].pos, fb[i].pos, "same foe %d" % i)
					assert_eq(fq[i].maxhp, fb[i].maxhp)


## A measured world has its own Tuning: the horde-off numbers never reach the shared one the other tests read.
func test_a_measured_world_leaves_the_shared_tuning_alone() -> void:
	var before: Array = [Tuning.shared().horde_rate_base, Tuning.shared().horde_rate_per_min, Tuning.shared().elite_interval]
	var tool: RefCounted = Dps.new()
	tool._probe(Dps.BASE_SPELL, 1, 0, 1, PROBE_SECONDS, 0)
	var w: World = tool._world(Dps.BASE_SPELL, 1, 0, 0)
	assert_true(w.tune != Tuning.shared(), "the world's tuning is its own")
	assert_eq(w.tune.horde_rate_base, 0.0, "no horde in the world measured")
	assert_eq([Tuning.shared().horde_rate_base, Tuning.shared().horde_rate_per_min, Tuning.shared().elite_interval], before,
		"the shared tuning is as it was")


## The lines the table prints: an unbuilt evolution only with --all, with the word `unbuilt` at the end; the support
## spell's evolution line holds the evolution (not the plain candle's numbers).
func test_the_rows_of_the_table() -> void:
	var tool: RefCounted = Dps.new()
	var quick: Array = ["--seconds=1", "--foes=1"]
	var plain: Array[String] = tool._rows(World.SP_ARCANE, tool._options(PackedStringArray(["--spell=0"] + quick)))
	var all: Array[String] = tool._rows(World.SP_ARCANE, tool._options(PackedStringArray(["--spell=0", "--all"] + quick)))
	assert_eq(plain.size(), 1 + tool._evos(World.SP_ARCANE, false).size(), "the spell and its built evolutions")
	assert_eq(all.size(), 1 + Spells.evolutions(World.SP_ARCANE), "--all adds the unbuilt ones")
	var lodestar := "LODESTAR"
	var has_mark := false
	for line: String in all:
		if line.begins_with(lodestar):
			has_mark = line.ends_with(" unbuilt")
	var listed := false
	for line: String in plain:
		listed = listed or line.begins_with(lodestar)
	assert_eq(listed, not Upgrades.UNBUILT.has(Upgrades.evo_entry(World.SP_ARCANE, 2)), "LODESTAR listed as built or not")
	assert_eq(has_mark, Upgrades.UNBUILT.has(Upgrades.evo_entry(World.SP_ARCANE, 2)), "marked unbuilt in --all")
	assert_eq(all[0], plain[0], "the spell's own line is the same")
	var gate: Array[String] = tool._rows(World.SP_CANDLE, tool._options(PackedStringArray(["--spell=7", "--gate", "--seconds=1"])))
	var dense := _support_line_of(tool, World.SP_CANDLE, 1, "evolved dense")
	assert_true(gate.has(dense), "the evolution's dense support line is in the gate rows: " + dense)
	var plain_dense: String = tool._support_line("CONSECRATION", "evolved dense",
		tool._support(World.SP_CANDLE, Spells.MAX_LEVEL, 0, Dps.GATE_DENSE, PROBE_SECONDS))
	assert_false(gate.has(plain_dense), "and it is not the plain candle's numbers")
	var dflt: Array[String] = tool._rows(World.SP_CANDLE, tool._options(PackedStringArray(["--spell=7", "--seconds=1", "--foes=6"])))
	var evo_line: String = tool._support_line("CONSECRATION", "",
		tool._support(World.SP_CANDLE, Spells.MAX_LEVEL, 1, EVO_CROWD, PROBE_SECONDS))
	assert_eq(dflt.find(evo_line), 3, "the default table: the spell, its support line, the evolution, its support line")
	assert_eq(tool._rows(World.SP_ARCANE, tool._options(PackedStringArray(["--spell=7"]))).size(), 0, "--spell=N skips the others")


func _support_line_of(tool: RefCounted, sp: int, evo: int, cell: String) -> String:
	return tool._support_line(tool._evo_name(sp, evo), cell,
		tool._support(sp, Spells.MAX_LEVEL, evo, Dps.GATE_DENSE, PROBE_SECONDS)) + tool._unbuilt_mark(sp, evo)

extends TestCase
## The catalog's twelve rows of stage 3 (docs/stage3_brief.md § 4.2, § 4.3; content list § 37-41): every evolution
## is its spell at 5 plus one arcana at 1, two roads for the four schools, THE TOWER and JUDGEMENT held, and the
## three ways a row is kept out of a hand (banished, locked, unbuilt).

const DT := 1.0 / 60.0

## [index, key, name, words, kind, levels, weight, spell].
const NEW_ROWS: Array = [
	[Upgrades.PRIESTESS, "priestess", "THE HIGH PRIESTESS", "ECHOED CASTS", Upgrades.PASSIVE, 3, 6.0, -1],
	[Upgrades.EMPRESS, "empress", "THE EMPRESS", "WIDER AREAS", Upgrades.PASSIVE, 3, 7.0, -1],
	[Upgrades.DEVIL, "devil", "THE DEVIL", "PAIN IS POWER", Upgrades.PASSIVE, 3, 6.0, -1],
	[Upgrades.STAR, "star", "THE STAR", "MORE MISSILES", Upgrades.PASSIVE, 2, 5.0, -1],
	[Upgrades.W_HEX, "w_hex", "HEX", "WEAKENS A FOE", Upgrades.SPELL, 5, 9.0, World.SP_HEX],
	[Upgrades.W_BLADES, "w_blades", "SPIRIT BLADES", "BLADES CIRCLE", Upgrades.SPELL, 5, 9.0, World.SP_BLADES],
	[Upgrades.E_LODESTAR, "e_lodestar", "LODESTAR", "HUNTS BIG PREY", Upgrades.EVOLUTION, 1, 40.0, World.SP_ARCANE],
	[Upgrades.E_GREEK, "e_greek", "GREEK FIRE", "BURNING GROUND", Upgrades.EVOLUTION, 1, 40.0, World.SP_FIRE],
	[Upgrades.E_VEIL, "e_veil", "WINTER VEIL", "CLOAK OF FROST", Upgrades.EVOLUTION, 1, 40.0, World.SP_FROST],
	[Upgrades.E_DIES, "e_dies", "DIES IRAE", "SLAYS THE WEAK", Upgrades.EVOLUTION, 1, 40.0, World.SP_STORM],
	[Upgrades.E_HEX, "e_hex", "EVIL EYE", "HEXED BURST", Upgrades.EVOLUTION, 1, 40.0, World.SP_HEX],
	[Upgrades.E_BLADES, "e_blades", "DANSE MACABRE", "A SECOND RING", Upgrades.EVOLUTION, 1, 40.0, World.SP_BLADES],
]

## Content list § 37, by key: spell -> [[evolution, arcana] for evolution id 1, then id 2].
const CHART: Dictionary = {
	"w_arcane": [["e_arcane", "quick"], ["e_lodestar", "star"]],
	"w_fire": [["e_fire", "nova"], ["e_greek", "power"]],
	"w_frost": [["e_frost", "regen"], ["e_veil", "priestess"]],
	"w_storm": [["e_storm", "swift"], ["e_dies", "life"]],
	"w_star": [["e_star", "wisdom"]],
	"w_rune": [["e_rune", "magnet"]],
	"w_bone": [["e_bone", "justice"]],
	"w_candle": [["e_candle", "lovers"]],
	"w_hex": [["e_hex", "devil"]],
	"w_blades": [["e_blades", "empress"]],
	"w_cleave": [["e_cleave", "power"]],
}


func _row(key: String) -> int:
	for i: int in range(Upgrades.count()):
		if Upgrades.key(i) == key:
			return i
	return -1


func _world(n: int = 1) -> World:
	var slots: Array[int] = []
	for s: int in range(n):
		slots.append(s)
	var w := World.new(slots, 5, Tuning.new())
	w.phase = World.PH_FIGHT
	for p: World.Player in w.players.values():
		p.invuln = 999.0
	return w


func test_the_twelve_rows() -> void:
	assert_eq(Upgrades.count(), 44)
	for r: Array in NEW_ROWS:
		var idx: int = r[0]
		assert_true(idx >= 32 and idx <= 43, "row %d out of place" % idx)
		assert_eq(Upgrades.key(idx), r[1])
		assert_eq(Upgrades.display_name(idx), r[2])
		assert_eq(Upgrades.description(idx), r[3])
		assert_eq(Upgrades.kind(idx), r[4], str(r[1]))
		assert_eq(Upgrades.max_level(idx), r[5], str(r[1]))
		assert_eq(float(Upgrades.CATALOG[idx][Upgrades.C_WEIGHT]), r[6], str(r[1]))
		assert_eq(Upgrades.spell_of(idx), r[7], str(r[1]))
	assert_eq(NEW_ROWS[0][0], 32)
	assert_eq(NEW_ROWS[11][0], 43)
	for k: int in range(NEW_ROWS.size()):
		assert_eq(NEW_ROWS[k][0], 32 + k, "rows in the brief's order")


func test_the_arcana_values() -> void:
	assert_eq(Upgrades.CATALOG[Upgrades.PRIESTESS][Upgrades.C_VALUES], [4.0, 3.0, 2.0])
	assert_eq(Upgrades.CATALOG[Upgrades.EMPRESS][Upgrades.C_VALUES], [1.1, 1.2, 1.3])
	assert_eq(Upgrades.CATALOG[Upgrades.DEVIL][Upgrades.C_VALUES], [0.12, 0.18, 0.24])
	assert_eq(Upgrades.CATALOG[Upgrades.STAR][Upgrades.C_VALUES], [1.0, 2.0])


func test_spells_data_rows() -> void:
	assert_eq(Spells.COUNT, 11)
	assert_eq(World.SP_HEX, 9)
	assert_eq(World.SP_BLADES, 10)
	assert_eq(Spells.cast_kind(World.SP_HEX), "hex")
	assert_eq(Spells.cast_kind(World.SP_BLADES), "blades")
	assert_eq(Spells.spell_name(World.SP_HEX), "HEX")
	assert_eq(Spells.spell_name(World.SP_BLADES), "SPIRIT BLADES")
	assert_eq(Spells.evo_row(World.SP_HEX, 1)["name"], "EVIL EYE")
	assert_eq(Spells.evo_row(World.SP_BLADES, 1)["name"], "DANSE MACABRE")
	assert_eq(Spells.evo_row(World.SP_ARCANE, 2)["name"], "LODESTAR")
	assert_eq(Spells.evo_row(World.SP_FIRE, 2)["name"], "GREEK FIRE")
	assert_eq(Spells.evo_row(World.SP_FROST, 2)["name"], "WINTER VEIL")
	assert_eq(Spells.evo_row(World.SP_STORM, 2)["name"], "DIES IRAE")
	for sp: int in range(Spells.COUNT):
		assert_true(Spells.has_evolution(sp), Spells.spell_name(sp))
		assert_eq(Spells.evolutions(sp), 2 if sp <= World.SP_STORM else 1, Spells.spell_name(sp))
		assert_false(Spells.EVOS[sp].has("partner"), "a spell partner is gone")
	# The list's numbers, under the keys named above Spells.STATS.
	assert_eq(Spells.STATS[World.SP_HEX]["cd"], [1.6, 1.45, 1.3, 1.15, 1.0])
	assert_eq(Spells.STATS[World.SP_HEX]["dmg"], [5.0, 5.5, 6.0, 6.5, 7.0])
	assert_eq(Spells.STATS[World.SP_HEX]["n"], [2, 3, 4, 5, 6])
	assert_eq(Spells.STATS[World.SP_BLADES]["n"], [2, 2, 3, 3, 4])
	assert_eq(Spells.STATS[World.SP_BLADES]["dmg"], [1.2, 1.45, 1.7, 1.95, 2.2])
	assert_eq(Spells.cooldown(World.SP_ARCANE, Spells.MAX_LEVEL, 2), 0.12)
	assert_eq(Spells.damage(World.SP_STORM, Spells.MAX_LEVEL, 2), 5.0)
	assert_eq(Spells.count(World.SP_STORM, Spells.MAX_LEVEL, 2), 7)
	assert_eq(Spells.count(World.SP_HEX, Spells.MAX_LEVEL, 1), 6)
	assert_eq(Spells.damage(World.SP_HEX, Spells.MAX_LEVEL, 1), 8.0)
	assert_eq(Spells.damage(World.SP_BLADES, Spells.MAX_LEVEL, 1), 3.0)


## The chart of content list § 37, read from the catalog's requires and from Spells.
func test_the_chart_from_requires() -> void:
	var seen_evos := 0
	for idx: int in range(Upgrades.count()):
		if Upgrades.kind(idx) != Upgrades.EVOLUTION:
			continue
		seen_evos += 1
		var reqs: Array = Upgrades.CATALOG[idx][Upgrades.C_REQUIRES]
		assert_eq(reqs.size(), 2, Upgrades.key(idx))
		var spell_ok := false
		var arcana := 0
		for req: Array in reqs:
			var need := int(req[0])
			if need == Upgrades.weapon_entry(Upgrades.spell_of(idx)):
				spell_ok = int(req[1]) == Spells.MAX_LEVEL
			elif Upgrades.kind(need) == Upgrades.PASSIVE and int(req[1]) == 1:
				arcana += 1
		assert_true(spell_ok, Upgrades.key(idx) + ": its spell at 5")
		assert_eq(arcana, 1, Upgrades.key(idx) + ": one arcana at 1")
	assert_eq(seen_evos, 15, "fifteen evolutions")
	assert_eq(CHART.size(), Spells.COUNT)
	for sk: String in CHART:
		var sp := Upgrades.spell_of(_row(sk))
		var roads: Array = CHART[sk]
		assert_eq(Upgrades.evo_rows(sp).size(), roads.size(), sk)
		for k: int in range(roads.size()):
			var evo := k + 1
			assert_eq(Upgrades.key(Upgrades.evo_entry(sp, evo)), roads[k][0], sk)
			assert_eq(Upgrades.key(Upgrades.partner_row(sp, evo)), roads[k][1], sk)
			assert_eq(Spells.passive_partner(sp, evo), roads[k][1], sk)
			assert_eq(Spells.evo_row(sp, evo)["name"], Upgrades.display_name(Upgrades.evo_entry(sp, evo)), sk)
	assert_eq(Upgrades.partner_row(World.SP_STAR, 2), -1, "STARFALL has one road")
	assert_eq(Spells.passive_partner(World.SP_STAR, 2), "")


func test_no_row_requires_another_spell() -> void:
	for idx: int in range(Upgrades.count()):
		for req: Array in Upgrades.CATALOG[idx][Upgrades.C_REQUIRES]:
			var need := int(req[0])
			if Upgrades.kind(need) == Upgrades.SPELL:
				assert_eq(need, Upgrades.weapon_entry(Upgrades.spell_of(idx)), "%s requires %s" % [Upgrades.key(idx), Upgrades.key(need)])


func test_one_evolution_shuts_the_other() -> void:
	var lv := {Upgrades.W_FIRE: 5, Upgrades.NOVA: 1, Upgrades.POWER: 1, Upgrades.E_FIRE: 1}
	assert_true(Upgrades.evo_shut(lv, Upgrades.E_GREEK, Upgrades.evo_rows(World.SP_FIRE)))
	assert_false(Upgrades.available(lv, Upgrades.E_GREEK), "GREEK FIRE after THUNDERFIRE")
	var lv2 := {Upgrades.W_FIRE: 5, Upgrades.NOVA: 1, Upgrades.POWER: 1, Upgrades.E_GREEK: 1}
	assert_false(Upgrades.available(lv2, Upgrades.E_FIRE), "THUNDERFIRE after GREEK FIRE")
	# With FIREBALL evolved, THE TOWER no longer completes a pair for it.
	assert_false(Upgrades.pairs_with({Upgrades.W_FIRE: 5, Upgrades.E_FIRE: 1}, Upgrades.NOVA))
	assert_true(Upgrades.pairs_with({Upgrades.W_FIRE: 2}, Upgrades.NOVA))


## STRENGTH pairs with GREEK FIRE (FIREBALL) and WHIRLWIND (CLEAVE): it completes either pair.
func test_an_arcana_of_two_spells_completes_either_pair() -> void:
	assert_true(Upgrades.pairs_with({Upgrades.W_CLEAVE: 1}, Upgrades.POWER), "STRENGTH for CLEAVE")
	var greek_built := not Upgrades.UNBUILT.has(Upgrades.E_GREEK)
	assert_eq(Upgrades.pairs_with({Upgrades.W_FIRE: 1}, Upgrades.POWER), greek_built, "STRENGTH for FIREBALL")
	assert_eq(Upgrades.pairs_with({Upgrades.POWER: 1}, Upgrades.W_FIRE), greek_built, "FIREBALL for STRENGTH")
	assert_true(Upgrades.pairs_with({Upgrades.NOVA: 1}, Upgrades.W_FIRE), "FIREBALL for THE TOWER")
	assert_true(Upgrades.pairs_with({Upgrades.POWER: 1}, Upgrades.W_CLEAVE))
	# The pair taken through CLEAVE leaves STRENGTH's other road to FIREBALL.
	var knight := {Upgrades.W_CLEAVE: 5, Upgrades.POWER: 1, Upgrades.E_CLEAVE: 1}
	assert_eq(Upgrades.pairs_with(knight, Upgrades.W_FIRE), greek_built)
	assert_near(Upgrades.roll_weight({Upgrades.W_CLEAVE: 1}, Upgrades.POWER),
		float(Upgrades.CATALOG[Upgrades.POWER][Upgrades.C_WEIGHT]) * Upgrades.PARTNER_WEIGHT)
	assert_true(Upgrades.pick_score({Upgrades.W_CLEAVE: 1}, Upgrades.POWER) > Upgrades.pick_score({Upgrades.W_CLEAVE: 1}, Upgrades.SWIFT))
	# The pairs of today through the new partners.
	assert_true(Upgrades.pairs_with({Upgrades.W_ARCANE: 1}, Upgrades.QUICK))
	assert_true(Upgrades.pairs_with({Upgrades.W_FROST: 1}, Upgrades.REGEN))
	assert_true(Upgrades.pairs_with({Upgrades.W_STORM: 1}, Upgrades.SWIFT))
	assert_true(Upgrades.pairs_with({Upgrades.W_STAR: 1}, Upgrades.WISDOM))
	assert_true(Upgrades.pairs_with({Upgrades.W_RUNE: 1}, Upgrades.MAGNET))
	assert_false(Upgrades.pairs_with({Upgrades.W_RUNE: 1}, Upgrades.W_STAR), "no spell pairs a spell")


func test_unbuilt_rows_are_never_dealt() -> void:
	var want: Array[int] = []
	for i: int in range(32, 44):
		if i != Upgrades.EMPRESS and i != Upgrades.STAR: # built on the cast hooks (docs/stage3_brief.md § 4.5)
			want.append(i)
	assert_eq(Upgrades.UNBUILT, want, "the ten new rows still unbuilt")
	# Every requirement met, nothing banned, no cap: still refused.
	var all := {}
	for i: int in range(Upgrades.count()):
		if Upgrades.kind(i) == Upgrades.SPELL or Upgrades.kind(i) == Upgrades.PASSIVE:
			all[i] = 1
	for i: int in [Upgrades.W_ARCANE, Upgrades.W_FIRE, Upgrades.W_FROST, Upgrades.W_STORM]:
		all[i] = Spells.MAX_LEVEL
	for u: int in Upgrades.UNBUILT:
		all.erase(u)
		assert_false(Upgrades.available(all, u), Upgrades.key(u) + " offered")
		assert_false(Upgrades.available({}, u), Upgrades.key(u) + " offered")
		assert_false(Upgrades.pairs_with(all, u), Upgrades.key(u) + " completes a pair")
		assert_false(Upgrades.take(all, u), Upgrades.key(u) + " taken")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hands: Array[Dictionary] = [{}, {Upgrades.W_ARCANE: 5}, {Upgrades.W_FIRE: 5, Upgrades.POWER: 1},
		{Upgrades.W_FROST: 5, Upgrades.W_STORM: 5}, {Upgrades.W_CLEAVE: 5}]
	for k: int in range(1000):
		var lv: Dictionary = hands[k % hands.size()]
		for c: int in Upgrades.roll(rng, lv, 3, Upgrades.SLOTS_LATE):
			assert_false(Upgrades.UNBUILT.has(c), "rolled %s" % Upgrades.key(c))


## While LODESTAR is unbuilt, an ARCANE BOLT wizard who holds THE MAGICIAN keeps no arcana slot for THE STAR.
func test_an_unbuilt_row_keeps_no_slot() -> void:
	var lv := {Upgrades.W_ARCANE: 1, Upgrades.QUICK: 1, Upgrades.SWIFT: 1}
	assert_true(Upgrades.available(lv, Upgrades.WISDOM, Upgrades.SLOTS_EARLY), "the last arcana slot is kept for THE STAR")
	assert_true(Upgrades.available(lv, Upgrades.POWER, Upgrades.SLOTS_EARLY))


func test_an_unbuilt_spell_given_by_force_casts_nothing() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	p.pos = Vector2(300, 220)
	for u: int in Upgrades.UNBUILT:
		WorldGrants.give(w, p, u)
		assert_true(Upgrades.level_of(p.upgrades, u) >= 1, Upgrades.key(u) + " not given")
	for i: int in range(6):
		var e: World.Enemy = w.spawn_enemy(World.ORC, 0, p.pos + Vector2.from_angle(i * TAU / 6.0) * 30.0)
		e.entering = false
	for _i: int in range(300):
		p.invuln = 999.0
		w.step(DT, {})
	var by: Dictionary = w.record.slot_source_damage.get(0, {})
	assert_eq(float(by.get(World.SP_HEX, 0.0)), 0.0, "HEX cast")
	assert_eq(float(by.get(World.SP_BLADES, 0.0)), 0.0, "SPIRIT BLADES cast")


func test_the_tower_and_judgement_are_held() -> void:
	assert_eq(Upgrades.kind(Upgrades.NOVA), Upgrades.PASSIVE)
	assert_eq(Upgrades.kind(Upgrades.LIFE), Upgrades.PASSIVE)
	assert_eq(Upgrades.CATALOG[Upgrades.NOVA][Upgrades.C_VALUES], [75.0, 60.0, 45.0])
	assert_eq(Upgrades.max_level(Upgrades.LIFE), 2)
	assert_eq(float(Upgrades.CATALOG[Upgrades.NOVA][Upgrades.C_WEIGHT]), 5.0)
	assert_eq(float(Upgrades.CATALOG[Upgrades.LIFE][Upgrades.C_WEIGHT]), 4.0)
	# Each card says only what it does today: the refill and the blast, and their words, come with job C5.
	assert_eq(Upgrades.description(Upgrades.NOVA), "+1 NOVA NOW")
	assert_eq(Upgrades.description(Upgrades.LIFE), "+1 LIFE NOW")
	for i: int in range(Upgrades.count()):
		assert_true(Upgrades.kind(i) != Upgrades.INSTANT, Upgrades.key(i) + " is an instant")
	assert_eq(Upgrades.INSTANT, 1)
	var w := _world()
	var p: World.Player = w.players[0]
	var bombs := p.bombs
	var lives := p.lives
	WorldLevels._pick(w, p, Upgrades.NOVA)
	WorldLevels._pick(w, p, Upgrades.LIFE)
	assert_eq(p.bombs, bombs + 1, "THE TOWER's charge")
	assert_eq(p.lives, lives + 1, "JUDGEMENT's life")
	assert_eq(Upgrades.slots_used(p.upgrades).y, 2, "both take an arcana slot")
	var full := {Upgrades.SWIFT: 1, Upgrades.QUICK: 1, Upgrades.POWER: 1}
	assert_false(Upgrades.available(full, Upgrades.NOVA, Upgrades.SLOTS_EARLY), "no slot left for THE TOWER")
	# SEAL VIII still bans JUDGEMENT.
	var sealed := _world()
	sealed.apply_seal(World.SEAL_MAX)
	assert_true(sealed.players[0].banned.has(Upgrades.LIFE))


func test_a_locked_row_is_never_dealt_but_to_its_hero() -> void:
	var w := _world(2)
	var mask: Array = [Upgrades.W_BONE, Upgrades.JUSTICE, Upgrades.E_BONE, Upgrades.W_CANDLE, Upgrades.LOVERS, Upgrades.E_CANDLE]
	w.apply_meta({"locked": mask})
	var mage: World.Player = w.players[0]
	var archer: World.Player = w.players[1]
	w.apply_hero(archer, Hero.make(Races.HUMAN, Classes.ARCHER, 0).to_dict())
	for r: int in mask:
		assert_true(w.locked.has(r), Upgrades.key(r))
		assert_true(mage.banned.has(r), Upgrades.key(r) + " open to the mage")
	assert_false(archer.banned.has(Upgrades.W_BONE), "her class weapon")
	assert_false(archer.banned.has(Upgrades.JUSTICE), "its arcana")
	assert_false(archer.banned.has(Upgrades.E_BONE), "its evolution")
	assert_true(archer.banned.has(Upgrades.W_CANDLE), "another class's weapon")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var justice_seen := false
	for _k: int in range(1000):
		for c: int in Upgrades.roll(rng, mage.upgrades, 3, Upgrades.SLOTS_LATE, mage.banned):
			assert_false(mask.has(c), "a locked row dealt: " + Upgrades.key(c))
		for c: int in Upgrades.roll(rng, archer.upgrades, 3, Upgrades.SLOTS_LATE, archer.banned):
			assert_false(c == Upgrades.W_CANDLE or c == Upgrades.LOVERS, "the priest's row dealt to the archer")
			justice_seen = justice_seen or c == Upgrades.JUSTICE
	assert_true(justice_seen, "JUSTICE is dealt to the archer")
	var lk: PackedInt32Array = w.snapshot()["lk"]
	var sorted := mask.duplicate()
	sorted.sort()
	assert_eq(Array(lk), sorted, "the snapshot's mask")


func test_nothing_is_locked_without_a_mask() -> void:
	var w := _world(2)
	w.apply_meta({})
	assert_true(w.locked.is_empty())
	assert_eq((w.snapshot()["lk"] as PackedInt32Array).size(), 0)
	for p: World.Player in w.players.values():
		assert_true(p.banned.is_empty())


## The HUD and the shots index these by spell number: a new spell without its colours would read past the end.
func test_every_spell_has_its_colours() -> void:
	assert_eq(Sprites.SPELL_COLORS.size(), Spells.COUNT)
	assert_eq(Sprites.SPELL_DARK.size(), Spells.COUNT)


func test_row_name() -> void:
	assert_eq(Upgrades.row_name(Upgrades.PRIESTESS), "HIGH PRIESTESS")
	assert_eq(Upgrades.row_name(Upgrades.EMPRESS), "THE EMPRESS")
	assert_eq(Upgrades.row_name(Upgrades.W_FIRE), "FIREBALL")
	assert_eq(Upgrades.display_name(Upgrades.PRIESTESS), "THE HIGH PRIESTESS", "every other screen keeps the full name")
	for i: int in range(Upgrades.count()):
		assert_true(Upgrades.row_name(i).length() <= TarotArt.ROW_TITLE_CHARS, Upgrades.row_name(i))

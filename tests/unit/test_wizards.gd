extends TestCase
## Wizards: the four pickable wizards (game/logic/wizards.gd).


func test_roster_matches_the_robe_colours() -> void:
	assert_eq(Wizards.count(), Sprites.PLAYER_COLORS.size())
	for w: int in Wizards.count():
		assert_eq(Wizards.wizard_name(w), Sprites.PLAYER_COLORS[w].name)


func test_every_wizard_starts_with_a_different_spell() -> void:
	var seen := {}
	for w: int in Wizards.count():
		var sp: int = Wizards.start_spell(w)
		assert_true(sp >= 0 and sp < Spells.COUNT)
		assert_false(seen.has(sp), "two wizards start with spell %d" % sp)
		seen[sp] = true


func test_cycle_skips_taken_wizards_and_wraps() -> void:
	assert_eq(Wizards.cycle(0, 1, [1, 2]), 3)
	assert_eq(Wizards.cycle(0, -1, [3]), 2)
	assert_eq(Wizards.cycle(3, 1, []), 0)
	assert_eq(Wizards.cycle(2, 1, [0, 1, 3]), 2, "nothing free: keep the current one")


func test_first_free_prefers_the_slot_colour() -> void:
	assert_eq(Wizards.first_free(2, [0]), 2)
	assert_eq(Wizards.first_free(2, [2, 0]), 1)

extends TestCase
## Seals: the difficulty ladder's data (game/logic/seals.gd).

const SCALARS := ["hp", "horde", "boss"]


func test_wizard_is_neutral_and_matches_world_defaults() -> void:
	var v := Seals.values(0)
	assert_eq(v, Seals.BASE.merged({"crystals": 1.0, "luck": 0}, true), "WIZARD is BASE")
	var w := World.new([0], 1)
	assert_near(w.seal_hp, float(v.hp))
	assert_eq(w.seal_potion_heal, int(v.potion_heal))
	assert_eq(w.seal_hand, int(v.hand))
	assert_eq(w.seal_ultra, bool(v.ultra))


func test_titles_and_numerals() -> void:
	assert_eq(Seals.title(-1), "APPRENTICE")
	assert_eq(Seals.title(0), "WIZARD")
	assert_eq(Seals.title(1), "ARCHMAGE")
	assert_eq(Seals.title(2), "SEAL I")
	assert_eq(Seals.title(9), "SEAL VIII")
	assert_eq(Seals.title(99), "SEAL VIII", "clamped")
	assert_eq(Seals.numeral(5), "IV")
	assert_eq(Seals.numeral(1), "")
	assert_eq(Seals.MIN, World.SEAL_EASY)
	assert_eq(Seals.MAX, World.SEAL_MAX)
	assert_eq(Seals.CRYSTALS.size(), Seals.MAX - Seals.MIN + 1)
	assert_eq(Seals.LUCK.size(), Seals.MAX - Seals.MIN + 1)
	assert_eq(Seals.RULES.size(), Seals.MAX - 1)


## Each step moves its own values and only those: ARCHMAGE its four scalars, each Seal the three per-Seal
## scalars and its rule's values; crystals and luck rise every step from ARCHMAGE.
func test_each_step_moves_its_values_and_only_those() -> void:
	var easy := Seals.values(-1)
	var base := Seals.values(0)
	for k: String in base:
		var moved: bool = easy[k] != base[k]
		assert_eq(moved, Seals.APPRENTICE.has(k) or k == "crystals", "APPRENTICE moves " + k)
	var arch := Seals.values(1)
	for k: String in base:
		var moved: bool = arch[k] != base[k]
		assert_eq(moved, Seals.ARCHMAGE.has(k) or k == "crystals" or k == "luck", "ARCHMAGE moves " + k)
	for level: int in range(2, Seals.MAX + 1):
		var lo := Seals.values(level - 1)
		var hi := Seals.values(level)
		var rule: Dictionary = Seals.RULES[level - 2][2]
		for k: String in base:
			var moved: bool = hi[k] != lo[k]
			var expect: bool = SCALARS.has(k) or k == "crystals" or k == "luck" or rule.has(k)
			assert_eq(moved, expect, "%s moves %s" % [Seals.title(level), k])
		for k: String in SCALARS:
			assert_near(float(hi[k]) - float(lo[k]), float(Seals.PER_SEAL[k]), 0.0001, k)
		assert_true(float(hi.crystals) > float(lo.crystals))
		assert_true(int(hi.luck) > int(lo.luck))


func test_rules_are_cumulative() -> void:
	var top := Seals.values(Seals.MAX)
	for i: int in range(Seals.RULES.size()):
		var rule: Dictionary = Seals.RULES[i][2]
		for k: String in rule:
			assert_eq(top[k], rule[k], "SEAL VIII keeps " + k)
			assert_eq(Seals.values(i + 1)[k], Seals.BASE[k], "%s is not on below its Seal" % k)
	assert_near(float(top.hp), float(Seals.ARCHMAGE.hp) + float(Seals.PER_SEAL.hp) * 8)
	assert_eq(int(top.cap), 325)


func test_rewards() -> void:
	assert_near(Seals.crystal_mul(-1), 0.5)
	assert_near(Seals.crystal_mul(0), 1.0)
	assert_near(Seals.crystal_mul(9), 10.0)
	assert_eq(Seals.luck(1), 1)
	assert_eq(Seals.luck(9), 10)
	assert_eq(Seals.prize(-1), 0)
	assert_eq(Seals.prize(0), 0)
	assert_eq(Seals.prize(1), 50)
	assert_eq(Seals.prize(5), 50 * 25)
	assert_eq(Seals.card(1), -1)
	for level: int in range(2, Seals.MAX + 1):
		var c := Seals.card(level)
		assert_true(c >= 0 and Cards.enemy(c) == -1, Seals.title(level) + " has its own card, dropped by no monster")
		assert_eq(Seals.of_card(c), level)
	assert_eq(Seals.of_card(World.GOBLIN), Seals.MIN - 1)


func test_describe_names_the_rule() -> void:
	assert_eq(Seals.describe(2).begins_with("HUNGER"), true)
	assert_eq(Seals.describe(9).begins_with("DARKNESS"), true)
	assert_true(Seals.describe(-1) != "")


## The lobby row (title.gd LOBBY_SEAL_ROW): name at the left, the multiplier and prize at the right and the rule
## centred between, each separated by at least GAP px, for every step, open or locked, prize paid or not.
func test_the_lobby_rows_longest_text_fits_its_box() -> void:
	const GAP := 8
	var box: Rect2 = load("res://game/ui/title.gd").LOBBY_SEAL_ROW
	for level: int in range(Seals.MIN, Seals.MAX + 1):
		for open: bool in [true, false]:
			for prize: int in [0, Seals.prize(level)]:
				var t := Seals.row(level, open, prize)
				var need := 4 + PixelFont.text_width(t[0], 1) + GAP + PixelFont.text_width(t[1], 1) + GAP + PixelFont.text_width(t[2], 1) + 4
				assert_true(need <= int(box.size.x), "%s row is %d px wide" % [Seals.title(level), need])


## Lobby taps (title.gd lobby_tap_zone): the whole Seal row steps the ladder, the start zone begins below it.
func test_lobby_taps_on_the_seal_row_step_and_never_start() -> void:
	var title: GDScript = load("res://game/ui/title.gd")
	var box: Rect2 = title.LOBBY_SEAL_ROW
	for y: float in [box.position.y, box.position.y + box.size.y * 0.5, box.end.y - 0.5]:
		assert_eq(title.lobby_tap_zone(Vector2(box.position.x + 2, y)), -1, "left half at y %s" % y)
		assert_eq(title.lobby_tap_zone(Vector2(box.end.x - 2, y)), 1, "right half at y %s" % y)
	assert_eq(title.lobby_tap_zone(Vector2(240, box.end.y)), 2, "just below the row starts")
	assert_eq(title.lobby_tap_zone(Vector2(240, 236)), 2, "the TAP HERE TO START line")
	assert_eq(title.lobby_tap_zone(Vector2(240, box.position.y - 1)), 0, "the seats above do nothing")


## The results line (Seals.pay_line) fits the 480 px screen with a margin.
func test_the_results_line_fits() -> void:
	for level: int in range(Seals.MIN, Seals.MAX + 1):
		var pay := {"seal": level, "mul": Seals.crystal_mul(level), "bounty": 9999, "prize": Seals.prize(level), "card": Seals.card(level)}
		assert_true(PixelFont.text_width(Seals.pay_line(pay), 1) <= 470, Seals.pay_line(pay))
	assert_eq(Seals.pay_line({"seal": 0, "mul": 1.0, "bounty": 0, "prize": 0, "card": -1}), "WIZARD  BOUNTIES X1")

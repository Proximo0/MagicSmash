extends TestCase
## The career tool's pure parts (tools/career.gd): the crystal spending policy, the plain stat build and a
## checkpoint's round trip.

const Career := preload("res://tools/career.gd")


## The policy buys the cheapest affordable level on the shelf, list order on ties, until nothing is affordable;
## a level a Seal win holds back is not bought.
func test_spending_buys_the_cheapest_level_first() -> void:
	var p := Profile.new()
	var cheapest := -1
	for i: int in p.shelf():
		if cheapest < 0 or p.next_cost(i) < p.next_cost(cheapest):
			cheapest = i
	p.crystals = p.next_cost(cheapest)
	var bought := Career.spend_crystals(p)
	assert_eq(bought, [str(Profile.META[cheapest][0])] as Array[String], "not the cheapest (first on a tie)")
	assert_eq(p.crystals, 0)
	p.crystals = 1000000
	Career.spend_crystals(p)
	for i: int in p.shelf():
		assert_eq(p.next_cost(i), -1, "a rich profile left %s unbought" % Profile.META[i][0])
	assert_eq(p.level("might"), 3, "RUNED STAFF 4 waits for the SEAL IV win")
	for key: String in Profile.UNBUILT:
		assert_eq(p.level(key), 0, key + " is off the shelf")
	p.seal_best = Seals.MAX
	# Every Seal won: the levels they held back, cheapest first (220, 220, 300, 400, 600).
	assert_eq(Career.spend_crystals(p), ["redraw", "banish", "might", "start_level", "might"] as Array[String])


## With too few crystals for any level nothing is bought.
func test_spending_with_too_few_crystals_buys_nothing() -> void:
	var p := Profile.new()
	var least := 1 << 30
	for i: int in p.shelf():
		least = mini(least, p.next_cost(i))
	p.crystals = least - 1
	assert_eq(Career.spend_crystals(p).size(), 0)
	assert_eq(p.crystals, least - 1)


## The build alternates MIGHT and VIGOR (MIGHT first) and moves on when one is full.
func test_points_alternate_might_and_vigor() -> void:
	var h := Hero.new()
	h.level = 4
	var n := Hero.points_for(4)
	assert_eq(Career.spend_points(h), n)
	assert_eq(h.points[Loot.ST_MIGHT], (n + 1) / 2, "MIGHT first")
	assert_eq(h.points[Loot.ST_VIGOR], n / 2)
	h.points = [0, 0, 0, Hero.MAX_POINTS, 0, 0] as Array[int]
	h.level = 1
	while Hero.points_for(h.level) <= Hero.MAX_POINTS:
		h.level += 1
	var left := h.points_left()
	assert_eq(Career.spend_points(h), left, "a full VIGOR is skipped")
	assert_eq(h.points[Loot.ST_MIGHT], left)
	h.points = [Hero.MAX_POINTS, 0, 0, Hero.MAX_POINTS, 0, 0] as Array[int]
	h.level = Hero.MAX_LEVEL
	assert_eq(Career.spend_points(h), 0, "points with nowhere to go stay unspent")


## A checkpoint's text gives the same profile back: unlocks, crystals, heroes with their levels and points.
func test_a_checkpoint_round_trips() -> void:
	var p := Career.fresh_profile([SmashBot.CASUAL, -1, SmashBot.CASUAL] as Array[int],
		[[Classes.KNIGHT, Races.HUMAN], [Classes.PRIEST, Races.HUMAN], [Classes.MAGE, Races.HUMAN]])
	assert_eq(p.heroes.size(), 2, "an apprentice seat has no hero on the profile")
	p.crystals = 500
	Career.spend_crystals(p)
	(p.heroes[0] as Hero).add_xp(1000)
	Career.spend_points(p.heroes[0])
	var q := Career.profile_from_text(Career.checkpoint_text(p))
	assert_true(q != null)
	assert_eq(q.to_dict(), p.to_dict())
	assert_eq(q.bonuses(), p.bonuses())
	assert_eq((q.heroes[0] as Hero).cls, Classes.KNIGHT)
	assert_eq((q.heroes[1] as Hero).school, 2, "a mage's school is her seat's colour")

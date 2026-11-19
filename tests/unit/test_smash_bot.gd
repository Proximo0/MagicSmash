extends TestCase
## SmashBot: the shared play-bot brain (game/logic/smash_bot.gd).

const CENTER := Vector2(240, 148)


func _decide(me: Vector2, enemies: Array[Vector2], shots: Array[Vector2] = []) -> PackedFloat32Array:
	var pk: Array[Vector2] = []
	return SmashBot.new(1).decide(0, me, CENTER, 0.0, enemies, shots, pk)


func test_aims_and_fires_at_nearest_enemy() -> void:
	var en: Array[Vector2] = [CENTER + Vector2(100, 0), CENTER + Vector2(0, 30)]
	var out: PackedFloat32Array = _decide(CENTER, en)
	assert_near(out[2], 0.0, 0.001, "aim x")
	assert_true(out[3] > 0.0, "should aim down at the nearer enemy")
	assert_eq(out[4], 1.0, "fire")


func test_holds_fire_with_no_enemies() -> void:
	var en: Array[Vector2] = []
	var out: PackedFloat32Array = _decide(CENTER, en)
	assert_eq(out[4], 0.0)


func test_moves_away_from_a_close_shot() -> void:
	var en: Array[Vector2] = []
	var shots: Array[Vector2] = [CENTER + Vector2(5, 0)]
	var out: PackedFloat32Array = _decide(CENTER, en, shots)
	assert_true(out[0] < 0.0, "should step left, away from the shot")


func test_move_is_unit_length_at_most() -> void:
	var en: Array[Vector2] = [CENTER + Vector2(3, 0), CENTER + Vector2(-3, 1), CENTER + Vector2(0, 4)]
	var out: PackedFloat32Array = _decide(CENTER, en)
	assert_true(Vector2(out[0], out[1]).length() <= 1.0001)


func test_pick_policy_prefers_power() -> void:
	var offer: Array[int] = [Upgrades.NOVA, Upgrades.POWER, Upgrades.SWIFT]
	assert_eq(SmashBot.choose_pick(offer), 1)
	var none: Array[int] = []
	assert_eq(SmashBot.choose_pick(none), -1)


func test_with_pick_appends_card_and_offer() -> void:
	var offer: Array[int] = [Upgrades.SWIFT, Upgrades.LIFE]
	var out: PackedFloat32Array = SmashBot.with_pick(PackedFloat32Array([0, 0, 0, 0, 0, 3]), offer, 7)
	assert_eq(out.size(), 8)
	assert_eq(int(out[6]), 0, "swift beats second wind")
	assert_eq(int(out[7]), 7, "offer id")
	assert_eq(int(out[5]), 3, "nova count kept")

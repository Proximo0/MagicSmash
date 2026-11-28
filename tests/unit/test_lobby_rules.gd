extends TestCase
## LobbyRules (game/logic/lobby_rules.gd): what one press does in the lobby, by who pressed it.

const PAD0 := 0
const PAD1 := 1
const PAD2 := 2
const KEY := -1 # G.DEV_KBM
const SEATED: Array[int] = [KEY, PAD0, PAD1] # seat order, P1 first


func _do(dev: int, seated: Array[int], other: bool, asking: bool, button: int) -> int:
	return LobbyRules.decide(dev, seated, other, asking, button)


func test_p1_alone_back_leaves() -> void:
	assert_eq(_do(PAD0, [PAD0], false, false, LobbyRules.B_BACK), LobbyRules.LEAVE)


func test_p1_with_another_human_back_asks() -> void:
	assert_eq(_do(KEY, SEATED, true, false, LobbyRules.B_BACK), LobbyRules.ASK)


func test_open_question_p1_answers() -> void:
	assert_eq(_do(KEY, SEATED, true, true, LobbyRules.B_CONFIRM), LobbyRules.LEAVE)
	assert_eq(_do(KEY, SEATED, true, true, LobbyRules.B_BACK), LobbyRules.CLOSE)
	assert_eq(_do(KEY, SEATED, true, true, LobbyRules.B_ADD), LobbyRules.NONE, "nothing else while asking")


func test_open_question_others_do_nothing() -> void:
	for b: int in [LobbyRules.B_BACK, LobbyRules.B_CONFIRM, LobbyRules.B_ADD, LobbyRules.B_REMOVE]:
		assert_eq(_do(PAD0, SEATED, true, true, b), LobbyRules.NONE)
		assert_eq(_do(PAD2, SEATED, true, true, b), LobbyRules.NONE, "an unseated pad too")


func test_a_seated_non_p1_back_frees_only_its_seat() -> void:
	assert_eq(_do(PAD1, SEATED, true, false, LobbyRules.B_BACK), LobbyRules.LEAVE_SEAT)
	assert_eq(_do(PAD0, SEATED, true, false, LobbyRules.B_BACK), LobbyRules.LEAVE_SEAT)


func test_an_unseated_device_only_joins() -> void:
	assert_eq(_do(PAD2, SEATED, true, false, LobbyRules.B_CONFIRM), LobbyRules.JOIN)
	assert_eq(_do(PAD2, SEATED, true, false, LobbyRules.B_BACK), LobbyRules.NONE)
	assert_eq(_do(PAD2, SEATED, true, false, LobbyRules.B_ADD), LobbyRules.NONE)
	assert_eq(_do(PAD2, SEATED, true, false, LobbyRules.B_REMOVE), LobbyRules.NONE)


func test_only_p1_adds_and_removes_apprentices() -> void:
	assert_eq(_do(KEY, SEATED, true, false, LobbyRules.B_ADD), LobbyRules.ADD_APPRENTICE)
	assert_eq(_do(KEY, SEATED, true, false, LobbyRules.B_REMOVE), LobbyRules.REMOVE_APPRENTICE)
	assert_eq(_do(PAD1, SEATED, true, false, LobbyRules.B_ADD), LobbyRules.NONE)
	assert_eq(_do(PAD1, SEATED, true, false, LobbyRules.B_REMOVE), LobbyRules.NONE)


func test_a_seated_confirm_is_left_to_the_start_handling() -> void:
	assert_eq(_do(PAD0, SEATED, true, false, LobbyRules.B_CONFIRM), LobbyRules.NONE)


func test_nobody_seated_never_traps_back() -> void:
	var none: Array[int] = []
	assert_eq(_do(PAD0, none, false, false, LobbyRules.B_BACK), LobbyRules.LEAVE)
	assert_eq(_do(PAD0, none, false, false, LobbyRules.B_CONFIRM), LobbyRules.JOIN)

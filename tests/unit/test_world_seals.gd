extends TestCase
## World Seals: the run's difficulty level (game/logic/world.gd apply_seal, later game/logic/seals.gd).
## Pins the neutral defaults the wave 2 core landed.


func test_seal_zero_changes_nothing() -> void:
	var a := World.new([0, 1], 7)
	var b := World.new([0, 1], 7)
	b.apply_seal(0)
	assert_eq(b.seal, 0)
	for _i: int in range(120):
		a.step(1.0 / 60.0, {})
		b.step(1.0 / 60.0, {})
	assert_eq(a.state_hash(), b.state_hash(), "Seal 0 must play exactly like no Seal")
	assert_eq(int((b.snapshot()["w"] as PackedFloat32Array)[World.W_SEAL]), 0)
	b.apply_seal(3)
	assert_eq(int((b.snapshot()["w"] as PackedFloat32Array)[World.W_SEAL]), 3, "the header carries the Seal")
	b.apply_seal(World.SEAL_EASY)
	assert_eq(int((b.snapshot()["w"] as PackedFloat32Array)[World.W_SEAL]), -1, "easy (-1) round-trips through the header")

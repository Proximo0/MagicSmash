class_name ArenaBg
## Bakes the arena backdrop for each act of the run into a single texture, walls included: Act I the Ossuary
## (a bone-lined crypt lit by candles), Act II the Burning Library, Act III the Starless Sanctum. This is the
## entry the arena calls; the art itself is in `game/art/arena_art_*.gd`.

const OSSUARY := 0
const LIBRARY := 1
const SANCTUM := 2
const ACTS := 3

static var _cache := {}
static var _scenes := {}


static func build(act: int = OSSUARY) -> ImageTexture:
	act = clampi(act, 0, ACTS - 1)
	if not _cache.has(act):
		var info := {}
		_cache[act] = ImageTexture.create_from_image(_bake(act, info))
		_scenes[act] = info
	return _cache[act]


## What the arena draws live over an act's backdrop (see ArenaArtLive): "flames" is every wick and fire bowl as
## [position, kind], "seal" the engraved circle in the middle of the floor.
static func scene(act: int) -> Dictionary:
	act = clampi(act, 0, ACTS - 1)
	build(act)
	return _scenes[act]


## For tools: which flagstone each pixel of an act's floor belongs to (-1 for joints, walls and everything that
## is not bare stone). Bakes the act again; nothing in the game calls it.
static func stone_map(act: int) -> PackedInt32Array:
	var ids := PackedInt32Array()
	ids.resize(int(G.WORLD.x) * int(G.WORLD.y))
	ids.fill(-1)
	_bake(clampi(act, 0, ACTS - 1), {}, ids)
	return ids


static func _bake(act: int, info: Dictionary, ids: PackedInt32Array = PackedInt32Array()) -> Image:
	match act:
		LIBRARY:
			return ArenaArtLibrary.bake(info, ids)
		SANCTUM:
			return ArenaArtSanctum.bake(info, ids)
	return ArenaArtOssuary.bake(info, ids)

class_name FieldProps
extends Node2D
## Ground props scattered over the field (dead trees, rocks, graves, ruins, bones, thorns), drawn under the figures
## from art/field_prop_<kind>.png (tools/char3d prop_models.py, set=props). A kind with no file draws nothing: no
## stand-ins. Where they stand is a pure function of the field id and a grid cell (integer hash, no clock, no
## unseeded random), so every client sees the same field. Only the cells in the view are looked at.

const KINDS: Array[String] = ["dead_tree_a", "dead_tree_b", "dead_tree_c", "rock_a", "rock_b", "gravestone", "grave_cross",
	"broken_pillar", "broken_wall", "bone_pile", "thorn_bush", "stump"]
## Field px per grid cell, and out of 100 the cells that hold a prop: one prop to a few hundred px each way.
const CELL_PX: float = 160.0
const DENSITY: int = 24
## Clear radius round the gate, the heart, the waystones and the altars; round the two heart rings (half width).
const SITE_CLEAR_PX: float = 130.0
const ALTAR_CLEAR_PX: float = 200.0
const RING_CLEAR_PX: float = 90.0
const RING_RADII: Array[float] = [2500.0, 6000.0]
## Per field (0..5) weight of each kind in KINDS order: the road is rocks and stumps, the wood is trees, the marsh is thorn and
## bone, the peaks are rock, the tower is ruin and graves, the world's edge a bit of everything.
const MIX: Array = [
	[1, 0, 0, 4, 3, 1, 3, 0, 0, 2, 3, 4],
	[4, 4, 3, 1, 0, 1, 1, 0, 0, 2, 3, 4],
	[3, 2, 4, 1, 0, 1, 1, 0, 0, 4, 5, 3],
	[0, 0, 3, 6, 6, 0, 1, 0, 1, 4, 1, 1],
	[0, 0, 1, 2, 3, 4, 3, 5, 5, 4, 1, 0],
	[1, 1, 2, 3, 3, 3, 2, 3, 3, 4, 3, 1]]

var field: int = 0
var side: float = 0.0
var view: Rect2 = Rect2()
var sites: PackedFloat32Array = PackedFloat32Array()
var _tex: Array = []
var _any: bool = false
var _loaded: bool = false


## Integer mix of (field, cell, salt): the same on every machine.
static func hash3(f: int, cx: int, cy: int, salt: int) -> int:
	var h: int = (f * 73856093) ^ (cx * 19349663) ^ (cy * 83492791) ^ (salt * 2654435761)
	h = ((h >> 15) ^ h) * 2246822519 & 0x7fffffff
	h = ((h >> 13) ^ h) * 3266489917 & 0x7fffffff
	return (h >> 16) ^ h


static func kind_for(f: int, roll: int) -> int:
	var mix: Array = MIX[clampi(f, 0, MIX.size() - 1)]
	var total: int = 0
	for w in mix:
		total += int(w)
	var r: int = roll % total
	for k in mix.size():
		r -= int(mix[k])
		if r < 0:
			return k
	return 0


## True when `p` is clear of every site and ring. `sites` is the world's px pairs: gate, heart, waystones 0..6, altars 0..5.
static func is_clear(p: Vector2, sites_px: PackedFloat32Array) -> bool:
	if sites_px.size() < 30:
		return true
	for i in 15:
		var clear: float = ALTAR_CLEAR_PX if i >= 9 else SITE_CLEAR_PX
		if p.distance_to(Vector2(sites_px[i * 2], sites_px[i * 2 + 1])) < clear:
			return false
	var heart := Vector2(sites_px[2], sites_px[3])
	var d: float = p.distance_to(heart)
	for r in RING_RADII:
		if absf(d - r) < RING_CLEAR_PX:
			return false
	return true


## The props of cell (cx, cy) as [kind, position], or [] for an empty cell, an edge one or one on a site.
static func prop_in_cell(f: int, cx: int, cy: int, side_px: float, sites_px: PackedFloat32Array) -> Array:
	if hash3(f, cx, cy, 1) % 100 >= DENSITY:
		return []
	var p := Vector2((float(cx) + float(hash3(f, cx, cy, 2) % 1000) / 1000.0) * CELL_PX,
		(float(cy) + float(hash3(f, cx, cy, 3) % 1000) / 1000.0) * CELL_PX)
	if side_px > 0.0 and (p.x < 20.0 or p.y < 20.0 or p.x > side_px - 20.0 or p.y > side_px - 20.0):
		return []
	if not is_clear(p, sites_px):
		return []
	return [kind_for(f, hash3(f, cx, cy, 4)), p]


func _load() -> void:
	_loaded = true
	_tex.resize(KINDS.size())
	for k in KINDS.size():
		var path: String = "res://art/field_prop_%s.png" % KINDS[k]
		_tex[k] = load(path) as Texture2D if ResourceLoader.exists(path) else null
		_any = _any or _tex[k] != null


func _draw() -> void:
	if not _loaded:
		_load()
	if not _any:
		return
	var v: Rect2 = view.grow(80.0)
	var c0: int = floori(v.position.x / CELL_PX)
	var c1: int = floori(v.end.x / CELL_PX)
	for cy in range(floori(v.position.y / CELL_PX), floori(v.end.y / CELL_PX) + 1):
		for cx in range(c0, c1 + 1):
			var pr: Array = prop_in_cell(field, cx, cy, side, sites)
			if pr.is_empty():
				continue
			var t: Texture2D = _tex[int(pr[0])]
			if t == null:
				continue
			var at: Vector2 = pr[1]
			var sz: Vector2 = t.get_size()
			draw_texture_rect(t, Rect2(at - Vector2(sz.x * 0.5, sz.y - 2.0), sz), false)

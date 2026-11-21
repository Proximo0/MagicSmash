class_name CrowdBatch
extends RefCounted
## One picture drawn many times: a MultiMeshInstance2D whose buffer is filled in bulk (`push`, then `commit`).
## Stride 12 floats: a 2D transform (8) and a colour (4). Positions are the figure's feet; `lift` is the share of the
## picture's height that sits above that point.

const STRIDE: int = 12
const FIELD_RECT: Rect2 = Rect2(-512, -512, 17408, 17408)

var node: MultiMeshInstance2D
var mm: MultiMesh = MultiMesh.new()
var buf: PackedFloat32Array = PackedFloat32Array()
var n: int = 0
var cap: int = 0
var lift: float = 0.0


func _init(parent: Node, tex: Texture2D, size: Vector2, feet: bool, z: int) -> void:
	var q := QuadMesh.new()
	q.size = size
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = q
	_grow(64)
	node = MultiMeshInstance2D.new()
	node.multimesh = mm
	node.texture = tex
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.z_index = z
	parent.add_child(node)
	# The item's culling rectangle is not recomputed from the buffer: cover the whole field.
	RenderingServer.canvas_item_set_custom_rect(node.get_canvas_item(), true, FIELD_RECT)
	lift = size.y / 2.0 if feet else 0.0


func _grow(c: int) -> void:
	cap = c
	mm.instance_count = c
	buf.resize(c * STRIDE)


func begin() -> void:
	n = 0


func push(x: float, y: float, sx: float, r: float, g: float, b: float, a: float) -> void:
	if n >= cap:
		_grow(cap * 2)
	var sy: float = absf(sx)
	var o: int = n * STRIDE
	buf[o] = sx
	buf[o + 1] = 0.0
	buf[o + 2] = 0.0
	buf[o + 3] = x
	buf[o + 4] = 0.0
	buf[o + 5] = sy
	buf[o + 6] = 0.0
	buf[o + 7] = y - lift * sy
	buf[o + 8] = r
	buf[o + 9] = g
	buf[o + 10] = b
	buf[o + 11] = a
	n += 1


func commit() -> void:
	if n > 0:
		mm.buffer = buf
	mm.visible_instance_count = n

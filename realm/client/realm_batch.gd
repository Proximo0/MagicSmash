class_name RealmBatch
extends RefCounted
## One MultiMesh for a whole family of figures (every monster, or every other player), drawn from an atlas
## of their pictures. RealmLink fills the buffer once per tick (16 floats a figure: transform, tint, custom
## data); the shader (figures.gdshader) glides each figure from its previous position and picks its atlas
## frame. A frame costs one uniform per batch and no GDScript per figure.
## Two MultiMeshes take turns: a tick's buffer goes into the one not on screen, so the renderer never waits
## for the frame still drawing the other (a software renderer stalled up to 70 ms on that).

const STRIDE: int = 16
## Clear texels around each picture, so smoothed sampling does not bleed in a neighbour.
const PAD: int = 1
## The shader's frame table size (figures.gdshader MAX_FRAMES).
const MAX_FRAMES: int = 32
## The item's culling rectangle is not computed from the buffer: cover the whole field and beyond.
const FIELD_RECT: Rect2 = Rect2(-512, -512, 17408, 17408)
const SHADER: Shader = preload("res://figures.gdshader")

var material: ShaderMaterial = ShaderMaterial.new()
## Figures in the last buffer.
var count: int = 0
var _nodes: Array[MultiMeshInstance2D] = []
var _caps: PackedInt32Array = PackedInt32Array([0, 0])
var _front: int = 0


## `frames` are the pictures in atlas order (the frame numbers RealmLink writes); `z` the draw layer.
func _init(parent: Node, frames: Array[Texture2D], z: int) -> void:
	var cell := Vector2i.ZERO
	for t in frames:
		cell = cell.max(Vector2i(t.get_size()))
	var step: int = cell.x + 2 * PAD
	var img := Image.create(frames.size() * step, cell.y + 2 * PAD, false, Image.FORMAT_RGBA8)
	var rects := PackedVector4Array()
	rects.resize(MAX_FRAMES)
	for i in frames.size():
		var src: Image = frames[i].get_image()
		src.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(i * step + PAD, PAD)
		img.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), at)
		rects[i] = Vector4(at.x, at.y, src.get_width(), src.get_height())
	img.generate_mipmaps()
	var quad := QuadMesh.new()
	quad.size = Vector2(cell)
	# The figure's feet at the instance's position: the quad sits above it (the shader shrinks it to each picture).
	quad.center_offset = Vector3(0.0, -cell.y / 2.0, 0.0)
	material.shader = SHADER
	material.set_shader_parameter("cell", Vector2(cell))
	material.set_shader_parameter("atlas", Vector2(img.get_size()))
	material.set_shader_parameter("rects", rects)
	var tex := ImageTexture.create_from_image(img)
	for k in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = quad
		var node := MultiMeshInstance2D.new()
		node.multimesh = mm
		node.texture = tex
		node.material = material
		node.z_index = z
		node.visible = k == _front
		parent.add_child(node)
		RenderingServer.canvas_item_set_custom_rect(node.get_canvas_item(), true, FIELD_RECT)
		_nodes.append(node)


## Takes a buffer from RealmLink (`monster_buffer` or `player_buffer`).
func fill(buf: PackedFloat32Array) -> void:
	var back: int = 1 - _front
	var mm: MultiMesh = _nodes[back].multimesh
	count = buf.size() / STRIDE
	if count > _caps[back]:
		_caps[back] = maxi(count + count / 2, 256)
		mm.instance_count = _caps[back]
	if count > 0:
		buf.resize(_caps[back] * STRIDE)
		mm.buffer = buf
	mm.visible_instance_count = count
	_nodes[back].visible = true
	_nodes[_front].visible = false
	_front = back


## 0 at a tick's arrival to 1 a tick later: how far each figure has glided from its previous position.
func set_blend(a: float) -> void:
	material.set_shader_parameter("blend", a)


## Nearest texels when a picture's texel covers at least a screen pixel, smoothed (mipmaps) when smaller.
func set_smooth(smooth: bool) -> void:
	for node in _nodes:
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if smooth else CanvasItem.TEXTURE_FILTER_NEAREST

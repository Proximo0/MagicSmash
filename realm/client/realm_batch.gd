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
## The shader's entry table size (figures.gdshader MAX_FRAMES).
const MAX_FRAMES: int = 64
## A shelf of the atlas is at most this wide (a texture is at most 16,384 px a side).
const ATLAS_W: int = 4096
## The item's culling rectangle is not computed from the buffer: cover the whole field and beyond.
const FIELD_RECT: Rect2 = Rect2(-512, -512, 17408, 17408)
const SHADER: Shader = preload("res://figures.gdshader")

var material: ShaderMaterial = ShaderMaterial.new()
## Figures in the last buffer.
var count: int = 0
var _nodes: Array[MultiMeshInstance2D] = []
var _caps: PackedInt32Array = PackedInt32Array([0, 0])
var _front: int = 0


## Where each picture goes in the atlas: shelf packing, strips left to right in entry order, a new shelf (row) when
## the next strip would pass `max_w`. `sizes` are the strips' sizes in texels (without PAD); returns {at: the top
## left of each picture (inside its PAD), size: the atlas size}. A strip wider than `max_w` gets a shelf of its own.
static func layout(sizes: Array[Vector2i], max_w: int = ATLAS_W) -> Dictionary:
	var at: Array[Vector2i] = []
	var x: int = 0
	var y: int = 0
	var shelf_h: int = 0
	var width: int = 0
	for sz in sizes:
		var w: int = sz.x + 2 * PAD
		if x > 0 and x + w > max_w:
			y += shelf_h
			x = 0
			shelf_h = 0
		at.append(Vector2i(x + PAD, y + PAD))
		x += w
		shelf_h = maxi(shelf_h, sz.y + 2 * PAD)
		width = maxi(width, x)
	return {"at": at, "size": Vector2i(maxi(width, 1), maxi(y + shelf_h, 1))}


## `entries` are the pictures in atlas order (the numbers RealmLink writes), each a Dictionary: `tex` (a
## picture, or a strip of `anim` frames side by side), `anim` (frames in the strip, 1 for a still picture) and
## `scale` (the size it is drawn at: 0.5 for a strip with 2 texture px per world px), `fps` (frames a second, 8). `z` is the draw layer.
## The atlas is one texture of shelves (see `layout`), so 42 strips of 8 frames of 150 x 93 fit. `bob_stills`: a
## moving figure with a still picture bobs (the players' batch); the monsters' does not.
func _init(parent: Node, entries: Array[Dictionary], z: int, bob_stills: bool = true) -> void:
	var cell := Vector2i.ZERO
	var sizes: Array[Vector2i] = []
	for e in entries:
		var t: Texture2D = e["tex"]
		cell = cell.max(Vector2i(t.get_width() / int(e["anim"]), t.get_height()))
		sizes.append(Vector2i(t.get_width(), t.get_height()))
	var lay: Dictionary = layout(sizes)
	var atlas_size: Vector2i = lay["size"]
	var places: Array[Vector2i] = []
	places.assign(lay["at"])
	var img := Image.create(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
	var rects := PackedVector4Array()
	rects.resize(MAX_FRAMES)
	var anims := PackedFloat32Array()
	anims.resize(MAX_FRAMES)
	var scales := PackedFloat32Array()
	scales.resize(MAX_FRAMES)
	var rates := PackedFloat32Array()
	rates.resize(MAX_FRAMES)
	anims.fill(1.0)
	scales.fill(1.0)
	rates.fill(FieldArt.WALK_FPS)
	for i in entries.size():
		var src: Image = (entries[i]["tex"] as Texture2D).get_image()
		src.convert(Image.FORMAT_RGBA8)
		var at: Vector2i = places[i]
		img.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), at)
		var n: int = int(entries[i]["anim"])
		rects[i] = Vector4(at.x, at.y, src.get_width() / n, src.get_height())
		anims[i] = float(n)
		scales[i] = float(entries[i]["scale"])
		rates[i] = float(entries[i].get("fps", FieldArt.WALK_FPS))
	img.generate_mipmaps()
	var quad := QuadMesh.new()
	quad.size = Vector2(cell)
	# The figure's feet at the instance's position: the quad sits above it (the shader shrinks it to each picture).
	quad.center_offset = Vector3(0.0, -cell.y / 2.0, 0.0)
	material.shader = SHADER
	material.set_shader_parameter("bob_stills", 1.0 if bob_stills else 0.0)
	material.set_shader_parameter("cell", Vector2(cell))
	material.set_shader_parameter("atlas", Vector2(atlas_size))
	material.set_shader_parameter("rects", rects)
	material.set_shader_parameter("anims", anims)
	material.set_shader_parameter("scales", scales)
	material.set_shader_parameter("rates", rates)
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

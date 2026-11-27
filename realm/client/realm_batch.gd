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
const MAX_FRAMES: int = 256
## A shelf of the atlas is at most this wide (a texture is at most 16,384 px a side).
const ATLAS_W: int = 4096
## The largest texture side a renderer is promised.
const MAX_TEXTURE: int = 16384
## The item's culling rectangle is not computed from the buffer: cover the whole field and beyond.
const FIELD_RECT: Rect2 = Rect2(-512, -512, 17408, 17408)
const SHADER: Shader = preload("res://figures.gdshader")
const SHADOW_SHADER: Shader = preload("res://figures_shadow.gdshader")
const BAR_SHADER: Shader = preload("res://figures_bar.gdshader")

var material: ShaderMaterial = ShaderMaterial.new()
## The blob shadow's material when some entry hovers, else null (figures_shadow.gdshader); `_shadows` are its nodes.
var shadow_material: ShaderMaterial = null
var _shadows: Array[MultiMeshInstance2D] = []
## The health bars' material when the batch has bars (the monsters'), else null (figures_bar.gdshader); `_bars`
## are its nodes, drawn after the figures from their own two MultiMeshes (`fill_bars`: RealmLink.bar_buffer, the
## barred monsters near the hero only, so a full horde does not cost the bar pass every figure).
var bar_material: ShaderMaterial = null
var _bars: Array[MultiMeshInstance2D] = []
var _bar_caps: PackedInt32Array = PackedInt32Array([0, 0])
var _bar_front: int = 0
## Bars in the last bar buffer.
var bar_count: int = 0
## Figures in the last buffer.
var count: int = 0
var _nodes: Array[MultiMeshInstance2D] = []
var _caps: PackedInt32Array = PackedInt32Array([0, 0])
var _front: int = 0
var _bars_on: bool = true


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
## `scale` (the size it is drawn at: 0.5 for a strip with 2 texture px per world px), `fps` (frames a second, 8), `hover` (px a floating kind is drawn above its spot, 0). `z` is the draw layer.
## The atlas is one texture of shelves (see `layout`), so 42 strips of 8 frames of 150 x 93 fit. `bob_stills`: a
## moving figure with a still picture bobs (the players' batch); the monsters' does not.
## `strips`: also pack each entry's `atk`, `hit` and `die` strips (`atk_n` etc. frames) as extra entries after the
## main ones, entry `entries.size() + 3 * kind + (0 atk, 1 hit, 2 die)`, where the shader finds them by the
## instance's state; a missing strip is an entry of anims 0 (the shader falls back to the walk strip).
## `bars`: draw health bars over the hurt and the ranked (draw.rs `with_bar`), from the same buffers.
func _init(parent: Node, entries: Array[Dictionary], z: int, bob_stills: bool = true, strips: bool = false, bars: bool = false) -> void:
	var cell := Vector2i.ZERO
	var all: Array[Dictionary] = entries.duplicate()
	if strips:
		for e in entries:
			for suffix in ["atk", "hit", "die"]:
				if e.has(suffix):
					all.append({"tex": e[suffix], "anim": int(e[suffix + "_n"]), "scale": e["scale"], "fps": e["fps"]})
				else:
					all.append({})
	var sizes: Array[Vector2i] = []
	for e in all:
		if e.is_empty():
			sizes.append(Vector2i.ZERO)
			continue
		var t: Texture2D = e["tex"]
		cell = cell.max(Vector2i(t.get_width() / int(e["anim"]), t.get_height()))
		sizes.append(Vector2i(t.get_width(), t.get_height()))
	# Shelves 4,096 px wide unless that makes the atlas taller than a texture may be (16,384): then wider shelves.
	# (27 Nov: the bosses' strips made the monsters' atlas 5,506 x 16,789, which no renderer takes: every monster
	# was drawn as a black box.)
	var lay: Dictionary = layout(sizes)
	var shelf_w: int = ATLAS_W
	while (lay["size"] as Vector2i).y > MAX_TEXTURE and shelf_w < MAX_TEXTURE:
		shelf_w *= 2
		lay = layout(sizes, shelf_w)
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
	scales.fill(1.0)
	rates.fill(FieldArt.WALK_FPS)
	anims.fill(0.0 if strips else 1.0)
	for i in entries.size():
		anims[i] = 1.0
	for i in all.size():
		if all[i].is_empty():
			continue
		var src: Image = (all[i]["tex"] as Texture2D).get_image()
		src.convert(Image.FORMAT_RGBA8)
		var at: Vector2i = places[i]
		img.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), at)
		var n: int = int(all[i]["anim"])
		rects[i] = Vector4(at.x, at.y, src.get_width() / n, src.get_height())
		anims[i] = float(n)
		scales[i] = float(all[i]["scale"])
		rates[i] = float(all[i].get("fps", FieldArt.WALK_FPS))
	img.generate_mipmaps()
	var quad := QuadMesh.new()
	quad.size = Vector2(cell)
	# The figure's feet at the instance's position: the quad sits above it (the shader shrinks it to each picture).
	quad.center_offset = Vector3(0.0, -cell.y / 2.0, 0.0)
	material.shader = SHADER
	material.set_shader_parameter("bob_stills", 1.0 if bob_stills else 0.0)
	material.set_shader_parameter("cell", Vector2(cell))
	material.set_shader_parameter("atlas", Vector2(atlas_size))
	material.set_shader_parameter("extra_base", entries.size() if strips else 0)
	material.set_shader_parameter("rects", rects)
	# One vec4 an entry (frames, scale, fps, hover px): see figures.gdshader `info`.
	var info := PackedVector4Array()
	info.resize(MAX_FRAMES)
	for i in MAX_FRAMES:
		info[i] = Vector4(anims[i], scales[i], rates[i], float(all[i].get("hover", 0.0)) if i < all.size() else 0.0)
	material.set_shader_parameter("info", info)
	var tex := ImageTexture.create_from_image(img)
	var floats: bool = false
	for i in entries.size():
		floats = floats or float(entries[i].get("hover", 0.0)) > 0.0
	if floats:
		# The same MultiMesh buffers drawn again one layer lower by a shader that squashes the quad to a blob at the feet.
		shadow_material = ShaderMaterial.new()
		shadow_material.shader = SHADOW_SHADER
		shadow_material.set_shader_parameter("info", info)
	material.set_shader_parameter("bars", 1.0 if bars else 0.0)
	if bars:
		bar_material = ShaderMaterial.new()
		bar_material.shader = BAR_SHADER
		bar_material.set_shader_parameter("cell", Vector2(cell))
		bar_material.set_shader_parameter("rects", rects)
		bar_material.set_shader_parameter("info", info)
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
		if floats:
			var sh := MultiMeshInstance2D.new()
			sh.multimesh = mm
			sh.material = shadow_material
			sh.z_index = z - 1
			sh.visible = k == _front
			parent.add_child(sh)
			RenderingServer.canvas_item_set_custom_rect(sh.get_canvas_item(), true, FIELD_RECT)
			_shadows.append(sh)
	# The bars after both figure nodes, so every bar is drawn over every figure of the batch.
	for k in (2 if bars else 0):
		var bm := MultiMesh.new()
		bm.transform_format = MultiMesh.TRANSFORM_2D
		bm.use_colors = true
		bm.use_custom_data = true
		bm.mesh = quad
		var bn := MultiMeshInstance2D.new()
		bn.multimesh = bm
		bn.material = bar_material
		bn.z_index = z
		bn.visible = false
		parent.add_child(bn)
		RenderingServer.canvas_item_set_custom_rect(bn.get_canvas_item(), true, FIELD_RECT)
		_bars.append(bn)


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
	if not _shadows.is_empty():
		_shadows[back].visible = true
		_shadows[_front].visible = false
	_front = back


## Takes the bars' buffer (RealmLink.bar_buffer: the same 16 floats a figure as `fill`'s, only the barred ones).
func fill_bars(buf: PackedFloat32Array) -> void:
	if _bars.is_empty():
		return
	var back: int = 1 - _bar_front
	var mm: MultiMesh = _bars[back].multimesh
	bar_count = buf.size() / STRIDE
	if bar_count > _bar_caps[back]:
		_bar_caps[back] = maxi(bar_count + bar_count / 2, 64)
		mm.instance_count = _bar_caps[back]
	if bar_count > 0:
		buf.resize(_bar_caps[back] * STRIDE)
		mm.buffer = buf
	mm.visible_instance_count = bar_count
	_bars[back].visible = _bars_on
	_bars[_bar_front].visible = false
	_bar_front = back


## 0 at a tick's arrival to 1 a tick later: how far each figure has glided from its previous position.
func set_blend(a: float) -> void:
	material.set_shader_parameter("blend", a)
	if shadow_material != null:
		shadow_material.set_shader_parameter("blend", a)
	if bar_material != null:
		bar_material.set_shader_parameter("blend", a)


## Health bars on or off (a hidden node costs nothing); `every` draws one on every figure of the bar buffer, even
## a whole one (the bench feeds it the whole monster buffer for the worst case).
func set_bars(on: bool, every: bool = false) -> void:
	_bars_on = on
	if bar_material == null:
		return
	bar_material.set_shader_parameter("all_bars", 1.0 if every else 0.0)
	for k in _bars.size():
		_bars[k].visible = on and k == _bar_front


## Nearest texels when a picture's texel covers at least a screen pixel, smoothed (mipmaps) when smaller.
func set_smooth(smooth: bool) -> void:
	for node in _nodes:
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if smooth else CanvasItem.TEXTURE_FILTER_NEAREST

class_name FieldGround
extends ColorRect
## The ground under everything in a field: its tile (res://ground/ground_<field>.png, made by
## tools/ground/ground.py from seeded noise) repeated over the whole field by field/ground.gdshader.
## Until a field with a tile is set it draws nothing and the window's dark clear colour shows.

## Field px one tile covers: the tiles are 512 px, two texture px to a field px like the figures.
const TILE_PX: float = 256.0
const DIR: String = "res://ground"
## Screen px per field px at and above which the tile is drawn in full detail.
const FULL_DETAIL_SCALE: float = 1.0
const MIN_DETAIL: float = 0.3

## The field whose tile is shown, -1 for none.
var field: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0, 0, 0, 0)


## Show `f`'s ground over a field `side` px square. A field with no tile keeps what was shown.
func set_field(f: int, side: float) -> void:
	if f == field:
		return
	var path: String = "%s/ground_%d.png" % [DIR, f]
	var blotch: String = "%s/ground_blotch.png" % DIR
	if not ResourceLoader.exists(path) or not ResourceLoader.exists(blotch):
		return
	var tex: Texture2D = load(path) as Texture2D
	var m := ShaderMaterial.new()
	m.shader = load("res://field/ground.gdshader") as Shader
	m.set_shader_parameter("tile", tex)
	m.set_shader_parameter("blotch", load(blotch) as Texture2D)
	m.set_shader_parameter("tile_px", TILE_PX)
	# Headless (the tests) a texture may hand back no picture: the shader's default mean stands in.
	var small: Image = tex.get_image()
	if small != null and not small.is_empty():
		small.resize(1, 1, Image.INTERPOLATE_LANCZOS)
		var mean: Color = small.get_pixel(0, 0)
		m.set_shader_parameter("mean_colour", Vector3(mean.r, mean.g, mean.b))
	material = m
	color = Color.WHITE
	size = Vector2(side, side)
	field = f


## `px_scale`: screen px per field px (the camera's zoom).
func set_scale_px(px_scale: float) -> void:
	if material != null:
		(material as ShaderMaterial).set_shader_parameter("detail", clampf(px_scale / FULL_DETAIL_SCALE, MIN_DETAIL, 1.0))

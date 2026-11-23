class_name FieldGround
extends ColorRect
## The ground under everything in a field: its two tiles (res://ground/ground_<field>a.png and b, made by
## tools/ground/ground.py from seeded noise) repeated and mixed over the whole field by field/ground.gdshader.
## Until a field with a tile is set it draws nothing and the window's dark clear colour shows.

## Field px one tile covers: the tiles are 512 px, two texture px to a field px like the figures.
const TILE_PX: float = 256.0
const DIR: String = "res://ground"
## Screen px per field px at and above which the tile is drawn in full detail.
const FULL_DETAIL_SCALE: float = 1.0
const MIN_DETAIL: float = 0.3

## `field` while the town plaza's tiles (ground_towna.png, ground_townb.png) are shown.
const TOWN: int = -2

## The field whose tile is shown, -1 for none.
var field: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0, 0, 0, 0)


## Show `f`'s ground over a field `side` px square. A field with no tiles keeps what was shown.
func set_field(f: int, side: float) -> void:
	_set_tiles(str(f), f, side)


## Show the town plaza's cobbles over a square `side` px. Without the files it keeps what was shown (`field` stays).
func set_town(side: float) -> void:
	_set_tiles("town", TOWN, side)


func _set_tiles(tag: String, id: int, side: float) -> void:
	if id == field:
		return
	var paths: Dictionary = {
		"tile_a": "%s/ground_%sa.png" % [DIR, tag], "tile_b": "%s/ground_%sb.png" % [DIR, tag],
		"patch": "%s/ground_patch.png" % DIR, "blotch": "%s/ground_blotch.png" % DIR}
	for key in paths:
		if not ResourceLoader.exists(paths[key]):
			return
	var m := ShaderMaterial.new()
	m.shader = load("res://field/ground.gdshader") as Shader
	m.set_shader_parameter("tile_px", TILE_PX)
	for key in paths:
		var tex: Texture2D = load(paths[key]) as Texture2D
		m.set_shader_parameter(key, tex)
		if not String(key).begins_with("tile_"):
			continue
		# Headless (the tests) a texture may hand back no picture: the shader's default mean stands in.
		var small: Image = tex.get_image()
		if small != null and not small.is_empty():
			small.resize(1, 1, Image.INTERPOLATE_LANCZOS)
			var mean: Color = small.get_pixel(0, 0)
			m.set_shader_parameter(String(key).replace("tile_", "mean_"), Vector3(mean.r, mean.g, mean.b))
	material = m
	color = Color.WHITE
	size = Vector2(side, side)
	field = id


## `px_scale`: screen px per field px (the camera's zoom).
func set_scale_px(px_scale: float) -> void:
	if material != null:
		(material as ShaderMaterial).set_shader_parameter("detail", clampf(px_scale / FULL_DETAIL_SCALE, MIN_DETAIL, 1.0))

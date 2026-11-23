// The field's ground: one seamless tile (tools/ground/ground.py) repeated over the whole field, shaded by a
// soft blotch map of a much longer period so the eye finds no repeat. `world` is the fragment's place in
// field px. Zoomed far out the tile's detail is smaller than a screen pixel and would shimmer as the camera
// moves, so it fades to the tile's mean colour (`detail` 1 near, lower far).
shader_type canvas_item;

uniform sampler2D tile : repeat_enable, filter_nearest;
uniform sampler2D blotch : repeat_enable, filter_linear;
// Field px one tile and one blotch map cover.
uniform float tile_px = 256.0;
uniform float blotch_px = 1777.0;
uniform vec3 mean_colour = vec3(0.2, 0.2, 0.2);
uniform float detail = 1.0;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	vec3 c = mix(mean_colour, texture(tile, world / tile_px).rgb, detail);
	float b = texture(blotch, world / blotch_px + vec2(0.31, 0.17)).r;
	COLOR = vec4(c * mix(0.78, 1.12, b), 1.0);
}

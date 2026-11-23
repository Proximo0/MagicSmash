// The field's ground. Each field has two seamless tiles (tools/ground/ground.py): `tile_a` its common ground
// and `tile_b` the other ground that shows in patches (cobbles in the road's earth, moss, standing water, bare
// rock in the snow). Which one shows comes from `patch`, a soft map sampled at two long periods, so the patches
// never repeat with the tile; their border is ragged by the tile's own light and dark and has a dark rim.
// `blotch`, another long map, shades everything a little. `world` is the fragment's place in field px.
// Zoomed far out a tile's detail is smaller than a screen pixel and would shimmer as the camera moves, so each
// tile fades toward its mean colour (`detail` 1 near, lower far).
shader_type canvas_item;

uniform sampler2D tile_a : repeat_enable, filter_nearest;
uniform sampler2D tile_b : repeat_enable, filter_nearest;
uniform sampler2D patch : repeat_enable, filter_linear;
uniform sampler2D blotch : repeat_enable, filter_linear;
// Field px one tile covers.
uniform float tile_px = 256.0;
uniform vec3 mean_a = vec3(0.2, 0.2, 0.2);
uniform vec3 mean_b = vec3(0.2, 0.2, 0.2);
uniform float detail = 1.0;

// Field px the patch map covers at its two scales, and the shade map; none a multiple of another or of the tile.
const float PATCH_PX = 1291.0;
const float PATCH_FINE_PX = 433.0;
const float BLOTCH_PX = 1777.0;
// `tile_b` shows where the patch value passes this, over this much of it; the rim is this wide.
const float PATCH_AT = 0.56;
const float PATCH_EDGE = 0.02;
const float RIM = 0.018;
const float RIM_DARK = 0.35;
const float RAGGED = 0.35;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	vec2 uv = world / tile_px;
	vec3 a = mix(mean_a, texture(tile_a, uv).rgb, detail);
	vec3 b = mix(mean_b, texture(tile_b, uv).rgb, detail);
	float m = texture(patch, world / PATCH_PX + vec2(0.11, 0.53)).r * 0.65
		+ texture(patch, world.yx / PATCH_FINE_PX + vec2(0.7, 0.2)).r * 0.35;
	m += (dot(a, vec3(1.0 / 3.0)) - dot(mean_a, vec3(1.0 / 3.0))) * RAGGED;
	float t = smoothstep(PATCH_AT, PATCH_AT + PATCH_EDGE, m);
	float rim = 1.0 - clamp(abs(m - PATCH_AT) / RIM, 0.0, 1.0);
	vec3 c = mix(a, b, t) * (1.0 - RIM_DARK * rim);
	float shade = texture(blotch, world / BLOTCH_PX + vec2(0.31, 0.17)).r;
	COLOR = vec4(c * mix(0.78, 1.12, shade), 1.0);
}

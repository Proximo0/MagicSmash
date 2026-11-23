// The blob shadow of a floating figure (realm_batch.gd draws it from the same MultiMesh as the figures, one layer
// lower). Same instance data as figures.gdshader: custom.xy the offset back to the previous tick's spot, custom.z
// kind + STATE_STEP * state, custom.w bob + BOB_STEP * age. A kind with no hover gets a quad of no size.
// The shadow sits on the un-lifted feet, glides with `blend`, and shrinks to nothing as a ghost sinks.
shader_type canvas_item;

const int MAX_FRAMES = 256;
const float STATE_STEP = 64.0;
const float BOB_STEP = 32.0;
// The ghost's die strip length in ticks (figures.gdshader STRIP_TICKS.z).
const float DIE_TICKS = 12.0;
// The shadow's size in field px at a figure scale of 1, and its darkest alpha.
const vec2 SHADOW_PX = vec2(20.0, 9.0);
const float SHADOW_ALPHA = 0.6;

uniform float blend = 1.0;
// Same table as figures.gdshader `info` (x frames, y scale, z fps, w hover); only y and w are read.
uniform vec4 info[MAX_FRAMES];

varying float strength;

void vertex() {
	float zc = INSTANCE_CUSTOM.z + 0.5;
	float state = floor(zc / STATE_STEP);
	int e = clamp(int(zc - state * STATE_STEP), 0, MAX_FRAMES - 1);
	float age = floor((INSTANCE_CUSTOM.w + 0.5) / BOB_STEP);
	float lift = info[e].w;
	float k = lift > 0.0 ? 1.0 : 0.0;
	if (state > 2.5) {
		k *= 1.0 - clamp((age + blend) / DIE_TICKS, 0.0, 1.0);
	}
	strength = k;
	// A little bigger for a bigger figure; UV runs 0..1 over the quad, so the ellipse is centred on the feet.
	float size = 0.75 + 0.5 * clamp(info[e].y, 0.0, 1.0);
	VERTEX = (UV - vec2(0.5)) * SHADOW_PX * size * max(k, 0.001) + INSTANCE_CUSTOM.xy * (1.0 - blend);
}

void fragment() {
	float d = length((UV - vec2(0.5)) * 2.0);
	COLOR = vec4(0.0, 0.0, 0.0, SHADOW_ALPHA * strength * (1.0 - smoothstep(0.55, 1.0, d)));
}

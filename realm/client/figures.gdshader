// Figures drawn from a MultiMesh filled by RealmLink. Each instance's custom data is (offset back to the
// previous tick's position in mesh units, atlas entry, bob seed: 0 standing still). `blend` runs 0 to 1 over
// the 50 ms between ticks, so the figure glides from where it was to where it is.
// An atlas entry is a strip of `anims` frames side by side (1 for a still picture, 4 for a walk strip unless its sidecar says more) drawn
// at `scales` (a walk strip has 2 texture px per world px: 0.5). A moving figure with a strip steps through
// its frames (the bob seed is also its phase, so a crowd does not march in step); a still picture bobs instead.
// The atlas is shelves of strips: each entry's rect says where its first frame is.
// VERTEX here is in mesh space (before the instance's transform), so offsets are divided by the instance's
// scale on the CPU side and the quad is shrunk to the frame's own picture, which keeps the pixels a
// software renderer has to fill to the picture itself.
shader_type canvas_item;

const int MAX_FRAMES = 256;
const float BOB_PX = 1.5;
const float BOB_RATE = 14.0;
const float HOVER_SWAY_PX = 1.5;
const float HOVER_RATE = 2.5;
// custom.z = kind + STATE_STEP * state, custom.w = bob + BOB_STEP * age in ticks (draw.rs). States: 0 walk, 1 atk, 2 hit, 3 die.
const float STATE_STEP = 64.0;
const float BOB_STEP = 32.0;
// How many ticks each strip's frames are spread over (draw.rs HIT_TICKS, DIE_TICKS; the attack 6).
const vec3 STRIP_TICKS = vec3(6.0, 3.0, 12.0);

uniform float blend = 1.0;
// 1: a moving figure with a still picture bobs; 0: it stays put (the monsters' batch).
uniform float bob_stills = 1.0;
// The atlas size and the quad size (the largest picture), in texels.
uniform vec2 atlas = vec2(256.0, 34.0);
uniform vec2 cell = vec2(32.0, 32.0);
// Per entry: the first frame's top left in the atlas and its size, in texels.
uniform vec4 rects[MAX_FRAMES];
// Per entry: frames in the strip, and the scale it is drawn at.
// Per entry: x the frames of the strip, y the scale it is drawn at, z its frames a second, w its hover. One vec4 array, not
// three float arrays: a float in a uniform block takes 16 bytes, and three arrays of 256 with `rects` would pass
// the 16 KB a block is promised.
// w: how many px a floating kind (a crow, a wisp) is drawn above its spot; it sways there and sinks as it dies.
uniform vec4 info[MAX_FRAMES];
// Where the atk, hit, die strips of kind k start: entry extra_base + 3 * k + state - 1 (their rect width 0: none).
uniform int extra_base = 0;
// 1 in the monsters' batch, whose alpha carries the health bar.
uniform float bars = 0.0;

void vertex() {
	float zc = INSTANCE_CUSTOM.z + 0.5;
	float state = floor(zc / STATE_STEP);
	int e = clamp(int(zc - state * STATE_STEP), 0, MAX_FRAMES - 1);
	float bob = mod(INSTANCE_CUSTOM.w + 0.5, BOB_STEP) - 0.5;
	float age = floor((INSTANCE_CUSTOM.w + 0.5) / BOB_STEP);
	int s = e;
	if (state > 0.5 && extra_base > 0) {
		s = clamp(extra_base + 3 * e + int(state + 0.5) - 1, 0, MAX_FRAMES - 1);
		if (rects[s].z <= 0.0) {
			s = e;
			// A kind with no die strip leaves no corpse.
			if (state > 2.5) {
				COLOR.a = 0.0;
				s = -1;
			}
			state = 0.0;
			age = 0.0;
		}
	}
	// A hidden figure (s < 0) is a quad of no size; the shader language allows no `return` in vertex().
	float shown = s < 0 ? 0.0 : 1.0;
	s = max(s, 0);
	vec4 r = rects[s];
	float n = info[s].x;
	float step_x = 0.0;
	// The quad spans x -cell.x/2..cell.x/2 and y -cell.y..0 (feet at the origin): shrink it to the picture.
	VERTEX = VERTEX * (r.zw / cell) * info[e].y * shown + INSTANCE_CUSTOM.xy * (1.0 - blend);
	float lift = info[e].w;
	if (lift > 0.0) {
		if (state > 2.5) {
			lift *= 1.0 - clamp((age + blend) / STRIP_TICKS.z, 0.0, 1.0);
		} else {
			lift += sin(TIME * HOVER_RATE + bob) * HOVER_SWAY_PX;
		}
		VERTEX.y -= lift * shown;
	}
	if (state > 0.5) {
		// A strip of a state plays once over its ticks, then holds its last frame.
		float len = STRIP_TICKS.x;
		if (state > 2.5) {
			len = STRIP_TICKS.z;
		} else if (state > 1.5) {
			len = STRIP_TICKS.y;
		}
		step_x = floor(clamp((age + blend) / len, 0.0, 0.999) * n);
	} else if (bob > 0.0) {
		if (n > 1.5) {
			step_x = floor(mod(TIME * info[e].z + bob * 0.7, n));
		} else if (bob_stills > 0.5) {
			VERTEX.y -= abs(sin(TIME * BOB_RATE + bob)) * BOB_PX;
		}
	}
	// A QuadMesh is built for 3D (y up): in 2D its texture would stand on its head.
	UV = (r.xy + vec2(step_x * r.z, 0.0) + vec2(UV.x, 1.0 - UV.y) * r.zw) / atlas;
	// In the monsters' batch a living monster's alpha carries its health bar (figures_bar.gdshader, draw.rs
	// `with_bar`): the figure itself is opaque. A ghost's (state 3) alpha is its fade.
	if (bars > 0.5 && state < 2.5) {
		COLOR.a = 1.0;
	}
}

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

const int MAX_FRAMES = 64;
const float BOB_PX = 1.5;
const float BOB_RATE = 14.0;

uniform float blend = 1.0;
// 1: a moving figure with a still picture bobs; 0: it stays put (the monsters' batch).
uniform float bob_stills = 1.0;
// The atlas size and the quad size (the largest picture), in texels.
uniform vec2 atlas = vec2(256.0, 34.0);
uniform vec2 cell = vec2(32.0, 32.0);
// Per entry: the first frame's top left in the atlas and its size, in texels.
uniform vec4 rects[MAX_FRAMES];
// Per entry: frames in the strip, and the scale it is drawn at.
uniform float anims[MAX_FRAMES];
uniform float scales[MAX_FRAMES];
// Per entry: frames a second of a strip.
uniform float rates[MAX_FRAMES];

void vertex() {
	int e = clamp(int(INSTANCE_CUSTOM.z + 0.5), 0, MAX_FRAMES - 1);
	vec4 r = rects[e];
	float n = anims[e];
	float step_x = 0.0;
	// The quad spans x -cell.x/2..cell.x/2 and y -cell.y..0 (feet at the origin): shrink it to the picture.
	VERTEX = VERTEX * (r.zw / cell) * scales[e] + INSTANCE_CUSTOM.xy * (1.0 - blend);
	if (INSTANCE_CUSTOM.w > 0.0) {
		if (n > 1.5) {
			step_x = floor(mod(TIME * rates[e] + INSTANCE_CUSTOM.w * 0.7, n));
		} else if (bob_stills > 0.5) {
			VERTEX.y -= abs(sin(TIME * BOB_RATE + INSTANCE_CUSTOM.w)) * BOB_PX;
		}
	}
	// A QuadMesh is built for 3D (y up): in 2D its texture would stand on its head.
	UV = (r.xy + vec2(step_x * r.z, 0.0) + vec2(UV.x, 1.0 - UV.y) * r.zw) / atlas;
}

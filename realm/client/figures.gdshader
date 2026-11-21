// Figures drawn from a MultiMesh filled by RealmLink. Each instance's custom data is (offset back to the
// previous tick's position in mesh units, atlas frame, bob seed: 0 standing still). `blend` runs 0 to 1 over
// the 50 ms between ticks, so the figure glides from where it was to where it is.
// VERTEX here is in mesh space (before the instance's transform), so offsets are divided by the instance's
// scale on the CPU side and the quad is shrunk to the frame's own picture, which keeps the pixels a
// software renderer has to fill to the picture itself.
shader_type canvas_item;

const int MAX_FRAMES = 32;
const float BOB_PX = 1.5;
const float BOB_RATE = 14.0;

uniform float blend = 1.0;
// The atlas size and the quad size (the largest picture), in texels.
uniform vec2 atlas = vec2(256.0, 34.0);
uniform vec2 cell = vec2(32.0, 32.0);
// Per frame: the picture's top left in the atlas and its size, in texels.
uniform vec4 rects[MAX_FRAMES];

void vertex() {
	vec4 r = rects[clamp(int(INSTANCE_CUSTOM.z + 0.5), 0, MAX_FRAMES - 1)];
	// The quad spans x -cell.x/2..cell.x/2 and y -cell.y..0 (feet at the origin): shrink it to the picture.
	VERTEX = VERTEX * (r.zw / cell) + INSTANCE_CUSTOM.xy * (1.0 - blend);
	if (INSTANCE_CUSTOM.w > 0.0) {
		VERTEX.y -= abs(sin(TIME * BOB_RATE + INSTANCE_CUSTOM.w)) * BOB_PX;
	}
	// A QuadMesh is built for 3D (y up): in 2D its texture would stand on its head.
	UV = (r.xy + vec2(UV.x, 1.0 - UV.y) * r.zw) / atlas;
}

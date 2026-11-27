// Monster health bars, drawn from the same MultiMesh as the figures (figures.gdshader) by a second instance one
// draw later, so a bar costs no node and no GDScript: the tint's alpha carries the bar (draw.rs `with_bar`:
// exactly 1 for none, 0.5 + health / 2 for a hurt monster or an elite, a champion or a boss). A figure with no
// bar becomes a quad of no size here, so only the barred ones are filled: BAR_W x BAR_H px (a 1 px dark rim
// round a 2 px red bar), just over the figure's head, gliding with it.
shader_type canvas_item;

const int MAX_FRAMES = 256;
const float STATE_STEP = 64.0;
const float BAR_W = 14.0;
const float BAR_H = 4.0;
// The bar's bottom is this far below the top of the figure's picture (pictures carry clear space above the head).
const float HEAD_DROP = 0.3;

uniform float blend = 1.0;
uniform vec2 cell = vec2(32.0, 32.0);
uniform vec4 rects[MAX_FRAMES];
uniform vec4 info[MAX_FRAMES];
// 0 hides every bar; `all_bars` 1 draws one on every living monster (the frame bench's worst case).
uniform float bars_on = 1.0;
uniform float all_bars = 0.0;

varying vec2 local;
varying float health;

void vertex() {
	float zc = INSTANCE_CUSTOM.z + 0.5;
	float state = floor(zc / STATE_STEP);
	int e = clamp(int(zc - state * STATE_STEP), 0, MAX_FRAMES - 1);
	float has = COLOR.a < 0.999 ? 1.0 : all_bars;
	health = COLOR.a < 0.999 ? clamp((COLOR.a - 0.5) * 2.0, 0.0, 1.0) : 1.0;
	// No bar on a ghost (state 3, its alpha the fade) or when bars are off.
	float shown = has * bars_on * (state > 2.5 ? 0.0 : 1.0);
	// The instance's transform scales by the rank (1, 1.25, 1.6) and mirrors a figure facing left: undo both so
	// every bar is the same size, fills left to right, and sits on whole field px.
	vec2 sc = vec2(length(MODEL_MATRIX[0].xy), length(MODEL_MATRIX[1].xy));
	float face = MODEL_MATRIX[0].x < 0.0 ? -1.0 : 1.0;
	// The quad spans x -cell.x/2..cell.x/2 and y -cell.y..0: its corners as 0..1 (top left 0, 0).
	local = vec2(VERTEX.x / cell.x + 0.5, VERTEX.y / cell.y + 1.0);
	float head = (rects[e].w * info[e].y * (1.0 - HEAD_DROP) + info[e].w) * sc.y;
	vec2 at = vec2((local.x - 0.5) * BAR_W, -head - BAR_H + local.y * BAR_H);
	VERTEX = (at * vec2(face, 1.0) / sc) * shown + INSTANCE_CUSTOM.xy * (1.0 - blend);
}

void fragment() {
	vec2 p = local * vec2(BAR_W, BAR_H);
	vec4 col = vec4(0.06, 0.02, 0.02, 0.9);
	if (p.x > 1.0 && p.x < BAR_W - 1.0 && p.y > 1.0 && p.y < BAR_H - 1.0) {
		float f = (p.x - 1.0) / (BAR_W - 2.0);
		col = f <= health ? vec4(0.85, 0.12, 0.1, 1.0) : vec4(0.22, 0.05, 0.05, 0.95);
	}
	COLOR = col;
}

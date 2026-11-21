class_name CrowdHud
extends Control
## The counters, top left, in the project's pixel font.

var lines: Array[String] = []
var px: int = 2

const BG: Color = Color(0, 0, 0, 0.62)
const FG: Color = Color(0.85, 0.95, 0.8)


func _draw() -> void:
	var w: int = 0
	for l in lines:
		w = maxi(w, PixelFont.text_width(l, px))
	var step: int = 9 * px
	draw_rect(Rect2(4, 4, w + 12, lines.size() * step + 8), BG)
	for i in lines.size():
		PixelFont.draw(self, lines[i], Vector2(10, 8 + i * step), px, FG)

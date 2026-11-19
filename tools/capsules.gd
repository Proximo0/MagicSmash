extends SceneTree
## Draft Steam store and library art drawn from the game's own pixel art: the four wizards facing the Archlich
## and its horde under the twilight sky, with the MAGIC SMASH logo. Each image is drawn at a small logical size
## and scaled up by a whole number with no smoothing, so the pixels stay crisp, then cropped to Steam's size.
## Needs a display: xvfb-run -a godot --path . -s tools/capsules.gd -- [--out=build/capsules]

## [file, final width, final height, pixel scale, draw the logo, draw the scene]. Sizes are Steam's.
const CAPSULES: Array = [
	["header_capsule", 920, 430, 4, true, true],
	["small_capsule", 462, 174, 2, true, true],
	["main_capsule", 1232, 706, 4, true, true],
	["vertical_capsule", 748, 896, 4, true, true],
	["library_capsule", 600, 900, 3, true, true],
	["library_hero", 3840, 1240, 8, false, true],
	["library_logo", 1280, 720, 4, true, false],
]

const SKY := [Color("0b0420"), Color("140832"), Color("1f0c45"), Color("2e1255"), Color("47185f"), Color("6a1f66"),
	Color("932a68"), Color("b8406a")]
const INK := Color("0b0716")


class Canvas extends Node2D:
	var size := Vector2i(100, 100)
	var logo := true
	var scene := true
	var rng := RandomNumberGenerator.new()

	## Wide images with a logo put the logo on the left and the fight on the right; the rest stack them.
	func wide() -> bool:
		return logo and scene and size.x > size.y * 1.6

	func _draw() -> void:
		rng.seed = 7
		var w := float(size.x)
		var h := float(size.y)
		if scene:
			_sky(w, h)
			_scene(w, h)
		if logo:
			_logo(w, h)

	func _sky(w: float, h: float) -> void:
		var bh := ceilf(h / SKY.size())
		for i in SKY.size():
			draw_rect(Rect2(0, i * bh, w, bh + 1), SKY[i])
			if i + 1 < SKY.size():
				for x in range(0, int(w), 2):
					draw_rect(Rect2(x + int(i * bh + bh - 2) % 2, i * bh + bh - 2, 1, 1), SKY[i + 1])
		for _i in int(w * h / 180.0):
			var p := Vector2(rng.randi_range(0, int(w)), rng.randi_range(0, int(h * 0.55)))
			draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, rng.randf_range(0.3, 1.0)))
		var mc := Vector2(w * 0.84, h * (0.42 if h > w else 0.17))
		var mr := maxf(6.0, h * 0.07)
		draw_circle(mc, mr, Color("ffe9c4"))
		draw_circle(mc + Vector2(mr * 0.25, -mr * 0.15), mr * 0.2, Color("f0d4a8"))
		draw_circle(mc + Vector2(-mr * 0.35, mr * 0.3), mr * 0.15, Color("f0d4a8"))

	## The Archlich looms behind its horde; the four wizards stand on the ledge in front, staffs glowing.
	func _scene(w: float, h: float) -> void:
		var ground := h * (0.9 if h > w else 0.84)
		var sc := 2.0 if h > w else 1.0
		var cx := w * (0.72 if wide() else 0.5)
		var spread := w * (0.26 if wide() else 0.46)
		# Distant ridge
		for x in int(w):
			var top := h * 0.62 + sin(x * 0.05) * h * 0.03 + sin(x * 0.17) * h * 0.012
			draw_rect(Rect2(x, top, 1, h - top), Color("2a1048"))
		# The Black Comet over the tower (wide images; the tall ones keep the sky for the logo and the moon).
		if h <= w:
			var head := Vector2(w * 0.62, h * 0.1)
			var tail_dir := Vector2(-1.0, -0.42).normalized()
			for k in 40:
				var p := head + tail_dir * k * 3.0 * sc
				draw_circle(p, (6.0 - k * 0.12) * sc, Color(0.55, 0.25, 0.9, 0.16 * (1.0 - k / 40.0)))
			draw_circle(head, 5.0 * sc, Color(1.0, 0.85, 0.4, 0.35))
			draw_circle(head, 3.5 * sc, Color("12051f"))
		# The Archlich, large and centred, with its violet and gold aura, over a burning seal seen in perspective
		var lc := Vector2(cx, ground - minf(h * 0.16, 26.0 * sc))
		var seal := Vector2(cx, ground - 2.0 * sc)
		var lw := maxf(1.0, sc * 0.75)
		var squash := Vector2(1.0, 0.3)
		for ring: Array in [[46.0, Color("ffd23d")], [40.0, Color(1.0, 0.82, 0.24, 0.6)]]:
			var pts := PackedVector2Array()
			for k in 65:
				pts.append(seal + Vector2.from_angle(k * TAU / 64.0) * float(ring[0]) * sc * squash)
			draw_polyline(pts, ring[1], lw)
		var star := PackedVector2Array()
		for k in 6:
			star.append(seal + Vector2.from_angle(-PI / 2.0 + k * 2.0 * TAU / 5.0) * 38.0 * sc * squash)
		draw_polyline(star, Color(1.0, 0.82, 0.24, 0.75), lw)
		draw_circle(lc + Vector2(0, -26) * sc, 40.0 * sc, Color(1.0, 0.3, 0.95, 0.16))
		draw_circle(lc + Vector2(0, -26) * sc, 27.0 * sc, Color(1.0, 0.85, 0.3, 0.14))
		Sprites.draw_at(self, "lich", lc, false, false, Color(1.3, 0.75, 1.35), sc * 2.0)
		# Horde on both flanks
		var kinds := ["skeleton_a", "goblin_a", "orc_a", "wraith_a", "tome_a", "priest_a", "gargoyle_b", "mage_a", "bat_a"]
		for i in int(spread / (7.0 * sc)):
			var side := -1.0 if i % 2 == 0 else 1.0
			var dx := rng.randf_range(0.25, 1.0) * spread
			var feet := Vector2(cx + side * dx, ground - (8.0 + rng.randf_range(0.0, minf(h * 0.1, 16.0))) * sc)
			var k: String = kinds[rng.randi() % kinds.size()]
			if k == "bat_a" or k == "gargoyle_b":
				feet.y -= 30.0 * sc
			elif k == "tome_a" or k == "wraith_a":
				feet.y -= 8.0 * sc
			Sprites.draw_at(self, k, feet.round(), side > 0.0, false, Color(0.75, 0.7, 0.9), sc)
		# Ledge and the wizards
		draw_rect(Rect2(0, ground, w, h - ground), Color("0d0618"))
		draw_rect(Rect2(0, ground, w, 1), Color("3a1f5a"))
		var gap := minf(spread * 0.4, 26.0 * sc)
		for i in 4:
			var feet := Vector2(cx + (i - 1.5) * gap, ground)
			var flip := i >= 2
			Sprites.draw_at(self, "wiz%d_side_b" % i, feet, flip, false, Color.WHITE, sc)
			var hand := feet + Vector2(-6 if flip else 6, -13) * sc / 2.0
			var tip := hand + Vector2(-8 if flip else 8, -18) * sc / 2.0
			draw_line(hand, tip, Color("b07a3a"), maxf(1.0, sc / 2.0))
			var c: Color = Sprites.PLAYER_COLORS[i].fx
			draw_circle(tip, 3.0 * sc / 2.0 + 1.0, Color(c.r, c.g, c.b, 0.35))
			draw_rect(Rect2(tip - Vector2(1, 1), Vector2(3, 3)), Color.WHITE)
			# A bolt from each staff towards the Archlich
			var to := lc + Vector2(0, -24) * sc
			var mid := tip.lerp(to, 0.55) + Vector2(0, -6) * sc
			draw_line(tip, mid, Color(c.r, c.g, c.b, 0.8), maxf(1.0, sc / 2.0))
			draw_circle(mid, 2.0 * sc / 2.0 + 1.0, c)

	## MAGIC over SMASH in the title screen's extruded gradient letters, as big as fits.
	func _logo(w: float, h: float) -> void:
		var tall := h > w
		var top := h * (0.06 if scene else 0.12)
		var lx := w * 0.28 if wide() else w / 2.0
		var room := w * 0.52 if wide() else w
		var lines := [["MAGIC", Color("ffffff"), Color("b07bff"), Color("3a0f7a")],
			["SMASH", Color("fff27a"), Color("ff4a2a"), Color("6a0a1a")]]
		var sc := int(floorf(room * (0.86 if tall or not scene or wide() else 0.62) / (5.0 * (PixelFont.W + 1))))
		sc = int(minf(sc, floorf(h * (0.8 if wide() or not scene else 0.45) / (2.0 * (PixelFont.H + 2)))))
		if wide():
			top = floorf((h * 0.9 - 2.0 * (PixelFont.H + 2) * sc) / 2.0)
		sc = maxi(1, sc)
		var y := top
		for L: Array in lines:
			var text: String = L[0]
			var x0 := floorf(lx - PixelFont.text_width(text, sc) / 2.0)
			for i in text.length():
				var ox := x0 + i * (PixelFont.W + 1) * sc
				var cells := PixelFont.cells(text[i])
				var depth := maxi(1, sc / 2)
				for d in range(depth, 0, -1):
					for c in cells:
						draw_rect(Rect2(ox + c.x * sc + d * 0.5, y + c.y * sc + d, sc, sc), (L[3] as Color).darkened(0.3 * (1.0 - float(d) / depth)))
				for c in cells:
					draw_rect(Rect2(ox + c.x * sc - 1, y + c.y * sc - 1, sc + 2, sc + 2), INK)
				for c in cells:
					var col: Color = (L[1] as Color).lerp(L[2], c.y / float(PixelFont.H - 1))
					draw_rect(Rect2(ox + c.x * sc, y + c.y * sc, sc, sc), col)
					draw_rect(Rect2(ox + c.x * sc, y + c.y * sc, sc, 1), col.lightened(0.4))
			y += (PixelFont.H + 2) * sc


func _init() -> void:
	var out := "build/capsules"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	_render.call_deferred(out)


func _render(out: String) -> void:
	for row: Array in CAPSULES:
		var px: int = row[3]
		var logical := Vector2i(ceili(float(row[1]) / px), ceili(float(row[2]) / px))
		var vp := SubViewport.new()
		vp.size = logical
		vp.transparent_bg = not row[5]
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var c := Canvas.new()
		c.size = logical
		c.logo = row[4]
		c.scene = row[5]
		vp.add_child(c)
		root.add_child(vp)
		await process_frame
		await process_frame
		var img := vp.get_texture().get_image()
		img.resize(logical.x * px, logical.y * px, Image.INTERPOLATE_NEAREST)
		img = img.get_region(Rect2i(0, 0, row[1], row[2]))
		img.save_png("%s/%s.png" % [out, row[0]])
		vp.queue_free()
	print("CAPSULES %d written to %s" % [CAPSULES.size(), out])
	quit()

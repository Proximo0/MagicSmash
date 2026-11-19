class_name ArenaBg
## Bakes the arena backdrop (stone floor, brick walls, rune circle) into a
## single texture once per match.

static func build() -> ImageTexture:
	var w := int(G.SCREEN.x)
	var h := int(G.SCREEN.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var a := G.ARENA
	img.fill(Color("120c1e"))
	# --- Walls: brick courses all round ------------------------------------
	var mortar := Color("150f24")
	for y in range(18, h):
		for x in w:
			if a.has_point(Vector2(x, y)):
				continue
			var row := (y - 18) / 6
			var off := 6 if row % 2 == 1 else 0
			var bx := (x + off) % 12
			var by := (y - 18) % 6
			var brick_id := ((x + off) / 12) * 31 + row * 17
			var base := Color("3b3058").lerp(Color("4a3c6b"), float((brick_id * 7919) % 13) / 13.0)
			var c := base
			if bx == 0 or by == 5:
				c = mortar
			elif by == 0:
				c = base.lightened(0.18)
			elif bx == 11:
				c = base.darkened(0.2)
			# Top wall face gets a soft vertical light gradient.
			if y < a.position.y:
				c = c.lerp(Color("1a1230"), clampf((a.position.y - y) / 26.0, 0.0, 1.0) * 0.55)
			img.set_pixel(x, y, c)
	# --- Floor flagstones ----------------------------------------------------
	var tile := 20
	for y in range(int(a.position.y), int(a.end.y)):
		for x in range(int(a.position.x), int(a.end.x)):
			var lx := x - int(a.position.x)
			var ly := y - int(a.position.y)
			var row := ly / tile
			var off := (tile / 2) if row % 2 == 1 else 0
			var tx := (lx + off) % tile
			var ty := ly % tile
			var tid := ((lx + off) / tile) * 7 + row * 13
			var shade := float((tid * 2654435761) % 1000) / 1000.0
			var base := Color("463a5e").lerp(Color("54476f"), shade)
			var n := rng.randf()
			var c := base
			if n < 0.08:
				c = base.darkened(0.08)
			elif n > 0.94:
				c = base.lightened(0.06)
			if tx == 0 or ty == 0:
				c = Color("2a2140")
			elif tx == 1 or ty == 1:
				c = base.lightened(0.1)
			elif tx == tile - 1 or ty == tile - 1:
				c = base.darkened(0.15)
			img.set_pixel(x, y, c)
	# Cracks and moss
	for i in 40:
		var p := Vector2i(rng.randi_range(int(a.position.x) + 4, int(a.end.x) - 4), rng.randi_range(int(a.position.y) + 4, int(a.end.y) - 4))
		var dir := Vector2i([1, -1][rng.randi() % 2], [1, -1][rng.randi() % 2])
		for k in rng.randi_range(3, 8):
			if a.has_point(Vector2(p)):
				img.set_pixelv(p, Color("2a2140"))
			p += Vector2i(dir.x if rng.randf() < 0.7 else 0, dir.y if rng.randf() < 0.7 else 0)
	for i in 70:
		var p := Vector2i(rng.randi_range(int(a.position.x), int(a.end.x) - 1), rng.randi_range(int(a.position.y), int(a.end.y) - 1))
		img.set_pixelv(p, Color("3f5a4a") if rng.randf() < 0.6 else Color("4f7a52"))
	# --- Rune circle ---------------------------------------------------------
	var c := a.get_center()
	var rune := Color("3d6b86")
	for r in [44.0, 38.0]:
		for i in 360:
			var ang := deg_to_rad(i)
			var p = c + Vector2(cos(ang), sin(ang) * 0.62) * r
			img.set_pixelv(Vector2i(p.round()), rune)
	for i in 5:
		var a0 := -PI / 2 + i * TAU / 5
		var a1 := -PI / 2 + (i + 2) * TAU / 5
		var p0 := c + Vector2(cos(a0), sin(a0) * 0.62) * 38.0
		var p1 := c + Vector2(cos(a1), sin(a1) * 0.62) * 38.0
		for t in 60:
			var p := p0.lerp(p1, t / 59.0)
			img.set_pixelv(Vector2i(p.round()), rune.darkened(0.15))
	for i in 12:
		var ang := i * TAU / 12
		var p := c + Vector2(cos(ang), sin(ang) * 0.62) * 41.0
		img.fill_rect(Rect2i(Vector2i(p.round()) - Vector2i(1, 1), Vector2i(2, 2)), rune.lightened(0.15))
	# --- Depth shading under the top wall and corner pillars -------------------
	for y in range(int(a.position.y), int(a.position.y) + 8):
		for x in range(int(a.position.x), int(a.end.x)):
			var k := 1.0 - float(y - a.position.y) / 8.0
			img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.45 * k))
	for x0 in [int(a.position.x), int(a.end.x) - 1]:
		for y in range(int(a.position.y), int(a.end.y)):
			img.set_pixel(x0, y, img.get_pixel(x0, y).darkened(0.35))
	for corner in [Vector2i(4, 22), Vector2i(w - 20, 22), Vector2i(4, h - 16), Vector2i(w - 20, h - 16)]:
		img.fill_rect(Rect2i(corner, Vector2i(16, 16)), Color("2b2142"))
		img.fill_rect(Rect2i(corner + Vector2i(1, 1), Vector2i(14, 13)), Color("5a4a80"))
		img.fill_rect(Rect2i(corner + Vector2i(1, 1), Vector2i(14, 2)), Color("7a68a8"))
		img.fill_rect(Rect2i(corner + Vector2i(5, 5), Vector2i(6, 6)), Color("3d6b86"))
	# --- HUD band ------------------------------------------------------------
	img.fill_rect(Rect2i(0, 0, w, 18), Color("0b0716"))
	img.fill_rect(Rect2i(0, 17, w, 1), Color("2f2450"))
	return ImageTexture.create_from_image(img)

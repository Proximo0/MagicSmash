extends TestCase
## One shared screen: the camera box and fit, the leash that fits the window, one edge arrow per wizard out of view,
## trays that never share a pixel and turn see-through over a wizard (draw_world.gd, hud.gd, tray.gd, tray_art.gd).

const MARGIN := 2.0


func _p(pos: Vector2, alive: bool = true, down: bool = false, ai: bool = false, slot: int = 0) -> Dictionary:
	return {"pos": pos, "alive": alive, "down": down, "ai": ai, "slot": slot}


## The body of a wizard at `pos` on screen with camera `cam`.
func _body(pos: Vector2, cam: Vector2) -> Rect2:
	return ArenaTrayArt.wizard_body_at(pos - cam)


func _fits(pos: Array[Vector2], cam: Vector2, what: String) -> void:
	var window := ArenaDrawWorld.PLAY_WINDOW.grow(-MARGIN)
	for q: Vector2 in pos:
		var b := _body(q, cam)
		assert_true(window.grow(0.001).encloses(b), "%s: body %s outside %s (cam %s)" % [what, b, window, cam])


func test_camera_box_is_the_living_humans_standing_or_fallen() -> void:
	# A fallen wizard's view row says alive = false, down = true: she is still in the run.
	var people: Array = [_p(Vector2(100, 100)), _p(Vector2(200, 100), false, true), _p(Vector2(300, 100), true, false, true),
		_p(Vector2(900, 900), false)]
	var m := ArenaDrawWorld.camera_members(people)
	assert_eq(m.size(), 2, "a standing and a fallen human, no apprentice, no dead")
	assert_true(m.has(Vector2(200, 100)), "the fallen wizard's spirit counts")
	assert_false(m.has(Vector2(300, 100)), "an apprentice does not move the camera while a human lives")


func test_camera_box_falls_back_to_apprentices_then_everyone() -> void:
	var m := ArenaDrawWorld.camera_members([_p(Vector2(1, 1), true, false, true), _p(Vector2(2, 2), false)])
	assert_eq(m, [Vector2(1, 1)] as Array[Vector2], "only an apprentice lives: she is followed")
	m = ArenaDrawWorld.camera_members([_p(Vector2(1, 1), false), _p(Vector2(2, 2), false)])
	assert_eq(m.size(), 2, "nobody alive: everyone")
	assert_true(ArenaDrawWorld.camera_members([]).is_empty())


func test_a_lone_wizard_gets_the_plain_centred_camera() -> void:
	var pos := Vector2(400, 220)
	var cam := ArenaDrawWorld.wanted_camera([pos] as Array[Vector2])
	assert_eq(cam, pos - Vector2(G.SCREEN.x / 2.0, (G.SCREEN.y + G.HUD_H) / 2.0), "a lone wizard in the open is centred")
	_fits([pos], cam, "lone")


func test_the_leash_fits_the_window() -> void:
	var room := ArenaDrawWorld.leash_room()
	var t := Tuning.new()
	assert_true(t.leash_x <= room.x, "leash_x %s > room %s" % [t.leash_x, room.x])
	assert_true(t.leash_y <= room.y, "leash_y %s > room %s" % [t.leash_y, room.y])
	assert_eq(room, Vector2(448, 203), "window 480x243, body 28x36, 2 px margins")


## Two wizards at the leash's limit, the pair slid to every wall and the open middle.
func test_two_wizards_at_the_limit_are_both_in_view() -> void:
	var t := Tuning.new()
	var arena := G.ARENA
	var lo := arena.position + Vector2(5, 6)
	var hi := arena.end - Vector2(5, 2)
	var offs: Array[Vector2] = [Vector2(0, t.leash_y), Vector2(t.leash_x, 0), Vector2(t.leash_x, t.leash_y), Vector2(t.leash_x, -t.leash_y)]
	for off: Vector2 in offs:
		var xs: Array[float] = [lo.x, 300.0, hi.x - absf(off.x)]
		var ys: Array[float] = [lo.y, 200.0, hi.y - absf(off.y)]
		for x: float in xs:
			for y: float in ys:
				var a := Vector2(x, y + (absf(off.y) if off.y < 0.0 else 0.0))
				var b := a + off
				if not Rect2(lo, hi - lo).has_point(a) or not Rect2(lo, hi - lo).has_point(b):
					continue
				var pts: Array[Vector2] = [a, b]
				_fits(pts, ArenaDrawWorld.wanted_camera(pts), "pair %s %s" % [a, off])


## A pair at the leash's limit runs the way it is spread, faster than the camera eases: no body may leave the window
## on any frame. Without the hold the camera trails the pair by speed / CAM_EASE px and cuts the leader off.
func test_a_running_party_never_outruns_the_camera() -> void:
	var t := Tuning.new()
	var dt := 1.0 / 60.0
	# [the way they run, where the first of the pair starts]: every run stays inside the arena.
	for row: Array in [[Vector2.RIGHT, Vector2(30, 200)], [Vector2.LEFT, Vector2(330, 200)], [Vector2.DOWN, Vector2(300, 50)],
			[Vector2.UP, Vector2(300, 230)]]:
		var dir: Vector2 = row[0]
		var spread := Vector2(t.leash_x, 0.0) if dir.x != 0.0 else Vector2(0.0, t.leash_y)
		var a: Vector2 = row[1]
		var pts: Array[Vector2] = [a, a + spread]
		var cam := ArenaDrawWorld.wanted_camera(pts)
		for i in 75:
			pts = [pts[0] + dir * 140.0 * dt, pts[1] + dir * 140.0 * dt]
			cam = ArenaDrawWorld.eased_camera(cam, pts, dt * Arena.CAM_EASE)
			_fits(pts, cam, "running %s frame %d" % [dir, i])


## The hold changes nothing for one wizard: her camera eases as it always did.
func test_a_lone_wizards_camera_still_eases() -> void:
	var dt := 1.0 / 60.0
	var pos := Vector2(300, 200)
	var pts: Array[Vector2] = [pos]
	var cam := ArenaDrawWorld.wanted_camera(pts)
	for i in 60:
		pos += Vector2(140.0 * dt, 0.0)
		pts = [pos]
		var plain := cam.lerp(ArenaDrawWorld.wanted_camera(pts), dt * Arena.CAM_EASE)
		cam = ArenaDrawWorld.eased_camera(cam, pts, dt * Arena.CAM_EASE)
		assert_eq(cam, plain, "frame %d" % i)
	assert_true(ArenaDrawWorld.wanted_camera(pts).x - cam.x > 5.0, "the camera trails her, as before")


func test_edge_arrows_for_wizards_out_of_view_only() -> void:
	var cam := Vector2(100, 100)
	var people: Array = [
		_p(Vector2(300, 250), true, false, false, 0), # in view
		_p(Vector2(900, 250), true, false, true, 1), # apprentice far right
		_p(Vector2(300, 150 + 4), false, true, false, 2), # spirit, body pokes under the HUD band
		_p(Vector2(900, 900), false, false, false, 3), # dead: none
	]
	var arrows := ArenaHud.edge_arrows(people, cam)
	assert_eq(arrows.size(), 2)
	assert_eq(arrows[0].slot, 1)
	assert_eq(arrows[0].tag, "A2", "an apprentice is A<n>")
	assert_eq(arrows[1].slot, 2)
	assert_eq(arrows[1].tag, "P3")


func test_edge_arrows_do_not_sit_on_each_other() -> void:
	var view := ArenaHud.arrow_view()
	var tips: Array[Vector2] = [Vector2(view.end.x, 100), Vector2(view.end.x, 102), Vector2(view.end.x, 104)]
	var out := ArenaHud.spread_tips(tips, view)
	for i in out.size():
		assert_true(view.has_point(out[i]) or view.grow(0.01).has_point(out[i]), "tip %d left the view" % i)
		for j in range(i + 1, out.size()):
			assert_true(out[i].distance_to(out[j]) >= ArenaHud.ARROW_SPREAD - 0.01, "tips %d and %d overlap" % [i, j])


func _arena_with_choices(n: int) -> Arena:
	var a := Arena.new()
	for s in 4:
		var ch: Array[int] = []
		for i in n:
			ch.append(Upgrades.POWER)
		a.vp[s] = {"choices": ch, "alive": true}
	return a


## Frees the arena and the nodes it made but never put in a tree.
func _free(a: Arena) -> void:
	for prop: Dictionary in a.get_property_list():
		var v: Variant = a.get(prop["name"])
		if v is Node and is_instance_valid(v) and v != a and (v as Node).get_parent() == null:
			(v as Node).free()
	a.free()


func test_trays_and_tabs_never_share_a_pixel() -> void:
	for n in [3, 4]:
		var a := _arena_with_choices(n)
		for i in 4:
			var tr := ArenaTray._tray_rect(a, i).grow(1)
			var tb := ArenaTray._tab_rect(a, i).grow(1)
			assert_true(Rect2(Vector2.ZERO, G.SCREEN).encloses(tr), "tray %d leaves the screen" % i)
			assert_true(Rect2(Vector2.ZERO, G.SCREEN).encloses(tb), "tab %d leaves the screen" % i)
			for j in range(i + 1, 4):
				assert_false(tr.intersects(ArenaTray._tray_rect(a, j).grow(1)), "trays %d and %d overlap (%d cards)" % [i, j, n])
				assert_false(tb.intersects(ArenaTray._tab_rect(a, j).grow(1)), "tabs %d and %d overlap" % [i, j])
		_free(a)


func test_a_tray_is_see_through_only_while_a_body_is_under_it() -> void:
	var tray := Rect2(120, 28, 118, 60)
	var under: Array[Rect2] = [ArenaTrayArt.wizard_body_at(Vector2(180, 80))]
	var clear: Array[Rect2] = [ArenaTrayArt.wizard_body_at(Vector2(180, 200))]
	assert_true(ArenaTrayArt.tray_hides_wizard(tray, under))
	assert_false(ArenaTrayArt.tray_hides_wizard(tray, clear))
	assert_false(ArenaTrayArt.tray_hides_wizard(tray, [] as Array[Rect2]))
	# her head under the tray's foot counts, a body just beside it does not
	var head: Array[Rect2] = [ArenaTrayArt.wizard_body_at(Vector2(180, 88 + 20))]
	assert_true(ArenaTrayArt.tray_hides_wizard(tray, head))
	var beside: Array[Rect2] = [ArenaTrayArt.wizard_body_at(Vector2(238 + 16, 60))]
	assert_false(ArenaTrayArt.tray_hides_wizard(tray, beside))


func test_a_hand_is_not_drawn_over_any_wizard() -> void:
	var box := Rect2(120, 91, 97, 63).grow(1)
	var owner: Array[Rect2] = [ArenaTrayArt.wizard_body_at(Vector2(400, 200))]
	assert_false(ArenaTrayArt.hand_hides_wizard(box, owner), "nobody under it")
	var other: Array[Rect2] = [ArenaTrayArt.wizard_body_at(Vector2(400, 200)), ArenaTrayArt.wizard_body_at(Vector2(170, 130))]
	assert_true(ArenaTrayArt.hand_hides_wizard(box, other), "another wizard under it counts, not only its owner")


func test_the_tray_alpha_eases_over_the_fade_time() -> void:
	var al := ArenaTrayArt.TRAY_SOLID
	al = ArenaTrayArt.tray_alpha_toward(al, true, ArenaTrayArt.TRAY_FADE / 2.0)
	assert_true(al < ArenaTrayArt.TRAY_SOLID and al > ArenaTrayArt.TRAY_GLASS, "half way after half the fade")
	al = ArenaTrayArt.tray_alpha_toward(al, true, ArenaTrayArt.TRAY_FADE)
	assert_eq(al, ArenaTrayArt.TRAY_GLASS)
	al = ArenaTrayArt.tray_alpha_toward(al, false, 10.0)
	assert_eq(al, ArenaTrayArt.TRAY_SOLID)

class_name ArenaHud
extends RefCounted
## Arena: the HUD, the party bar, the off-screen markers and the heart, hat and star glyphs.
## Static helpers: `a` is the Arena that owns the state.

## The HUD strip: one 108 px panel per seat at PANEL_X and a 44 px column in the middle (CENTRE). Each panel's
## content starts PANEL_PAD in; the level-up tab and tray of a seat hang under its panel (ArenaTray).
const PANEL_X: Array[int] = [2, 110, 262, 370]
const PANEL_W := 108
const PANEL_PAD := 2
const CENTRE := Rect2(218, 0, 44, G.HUD_H)

static func _draw_hud(a: Arena) -> void:
	var ci := a.hud
	var dark := Color("0b0716")
	# The HUD band: the arena scrolls under it.
	ci.draw_rect(Rect2(0, 0, G.SCREEN.x, G.HUD_H), Color(dark, 0.92))
	ci.draw_rect(Rect2(0, G.HUD_H, G.SCREEN.x, 1), Color("2f2450"))
	_draw_offscreen(a, ci)
	# Player panels
	for slot in 4:
		var x: float = PANEL_X[slot] + PANEL_PAD
		var col := G.player_color(slot)
		if not a.vp.has(slot):
			if not a.game_over and int(a.time * 2.0) % 2 == 0:
				PixelFont.draw(ci, "P%d" % (slot + 1), Vector2(x, 2), 1, col.darkened(0.5))
			continue
		var p: Dictionary = a.vp[slot]
		PixelFont.draw(ci, ("A%d" if p.get("ai", false) else "P%d") % (slot + 1), Vector2(x, 2), 1, col, dark) # A: an apprentice
		PixelFont.draw(ci, "%07d" % p.score, Vector2(x + 18, 2), 1, Color("fff6e0"), dark)
		vitals(a, ci, slot, x, p, dark)
		build(a, ci, slot, x, p, dark)
		if p.combo >= 5:
			var cc := Color.WHITE if int(a.time * 8) % 2 == 0 else G.player_fx(slot)
			PixelFont.draw(ci, "x%d" % p.combo, Vector2(x, 17), 1, cc, dark)
		# Gold keeps to its own panel: four digits and more push the coin left.
		var gold_text := "%d" % p.get("gold", 0)
		var gx := minf(x + 85, x + PANEL_W - PANEL_PAD * 2 - 1 - PixelFont.text_width(gold_text))
		Sprites.draw_at(ci, "coin", Vector2(gx - 5, 23))
		PixelFont.draw(ci, gold_text, Vector2(gx, 17), 1, Color("ffd23d"), dark)
	centre(a, ci, dark)
	_draw_party_bar(a, ci, dark)
	ArenaDrawBoss.bar(a, ci, dark)
	ArenaDrawBoss.word(a, ci, dark)
	ArenaDrawWorld._draw_hint(a, ci)
	ArenaFateView._draw_reveals(a, ci, dark)
	ArenaFateView._draw_card_reveal(a, ci, dark)
	ArenaFateView._draw_bets(a, ci, dark)
	# Banner
	if a.banner.t > 0.0:
		var k: float = 1.0 - a.banner.t / a.banner.max
		var slide := 0.0
		if k < 0.12:
			slide = (1.0 - k / 0.12) * 260.0
		elif a.banner.t < 0.3:
			slide = -(1.0 - a.banner.t / 0.3) * 260.0
		var y := 96.0
		if a.banner.act != "":
			ArenaFateView._draw_act_card(a, ci, k, slide)
		else:
			ci.draw_rect(Rect2(0 + slide, y - 8, 480, 44), Color(0.04, 0.0, 0.1, 0.6))
			ci.draw_rect(Rect2(0 + slide, y - 8, 480, 1), a.banner.color)
			ci.draw_rect(Rect2(0 + slide, y + 35, 480, 1), a.banner.color)
			var tw := PixelFont.text_width(a.banner.text, 3)
			PixelFont.draw_gradient(ci, a.banner.text, Vector2(240 - tw / 2.0 + slide, y), 3,
				Color.WHITE, a.banner.color, a.time * 6.0, 1.5)
			PixelFont.draw_centered(ci, a.banner.sub, 240 + slide, y + 25, 1, Color("fff6e0"), dark)
	ArenaTalk.draw(a, ci, dark)
	# The level-up cards go over the banners and the act card, so a banner never hides a tray's last row.
	if not a.game_over and not a.paused:
		ArenaTray._draw_draws(a, ci, dark)
	# Screen flash
	var flash_a: float = Save.settings.flash_alpha(a.screen_flash.a)
	if flash_a > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(a.screen_flash, flash_a))
	if a.game_over:
		ArenaResultsView._draw_game_over(a, ci)
	elif a.paused:
		ArenaResultsView._draw_pause(a, ci)


## A seat's vitals in its panel (content from `x`): hearts, lives (small hats) and nova charges (stars) on the
## second row, and "..." on the third while the wizard waits to respawn. A fallen wizard's hearts give way to DOWN
## and the seconds until she gets up by herself (none on her last life), over a bar of the ritual's progress; her
## call's arrow at the screen's edge is drawn from here too.
static func vitals(a: Arena, ci: CanvasItem, slot: int, x: float, p: Dictionary, dark: Color) -> void:
	var col := G.player_color(slot)
	if p.get("down", false):
		var left: float = p.get("down_left", -1.0)
		var blink := int(a.time * 2.0) % 2 == 0
		# Row two is 8 px tall between the score and the third row: the 7 px text fits only without an outline.
		PixelFont.draw(ci, "DOWN", Vector2(x, 9), 1, Color("ff6a4d") if blink else Color("fff6e0"))
		if left > 0.0:
			PixelFont.draw(ci, "%d" % ceili(left), Vector2(x + 24, 9), 1, col.lerp(Color.WHITE, 0.5)) # ends 3 px before the hats at x + 38
		var prog := clampf(float(p.get("revive", 0.0)), 0.0, 1.0)
		if prog > 0.0:
			ci.draw_rect(Rect2(x, 16, 23, 1), Color(dark, 1.0).lightened(0.15))
			ci.draw_rect(Rect2(x, 16, 23 * prog, 1), col.lerp(Color.WHITE, 0.4))
		ArenaDrawFallen.call_arrow(a, ci, slot)
	else:
		var mh: int = p.get("max_hp", World.BASE_HEARTS)
		var hstep := 7.0 if mh <= World.BASE_HEARTS else 35.0 / mh
		for h in mh:
			_heart(a, ci, Vector2(x + floorf(h * hstep), 10), h < p.hp)
	for l in mini(p.lives, 5):
		_hat(a, ci, Vector2(x + 38 + l * 6, 10), col)
	var skill := Still.icon(Still.skill_icon(Classes.skill(int(p.get("cls", 0)))), SKILL_ICON)
	for b in mini(p.bombs, 4):
		if skill != null:
			ci.draw_texture(skill, Vector2(x + 72 + b * 7, 10)) # the class skill's own mark in place of the star
		else:
			_star(a, ci, Vector2(x + 72 + b * 7, 10))
	if not p.alive and not p.get("down", false) and p.lives > 0:
		PixelFont.draw(ci, "...", Vector2(x + 40, 17), 1, col)


## The slot icons (`icons/spell_<key>`, `evo_<key>`, `passive_<key>`), reduced to these sizes, px: a spell's, a passive's.
const SLOT_ICON := 8
const PASSIVE_ICON := 6
## The nova charge's mark is the class skill's icon (`icons/skill_<key>`) at this size, px.
const SKILL_ICON := 6


## An icon in a build slot; false (draw the pips) when the slot's icon file does not exist. An evolved spell shows its
## `evo_` picture, else its spell's.
static func _slot_icon(ci: CanvasItem, upgrade_key: String, evolved: bool, at: Vector2, size: int, weapon: String = "") -> bool:
	var base := Still.icon_of(upgrade_key)
	var tex: Texture2D = null
	if evolved:
		tex = Still.icon("evo_" + base.trim_prefix("spell_"), size)
	if tex == null:
		tex = Still.icon(weapon, size) # a class weapon's own picture (`weapon_<skin>`), else its spell's
	if tex == null:
		tex = Still.icon(base, size)
	if tex == null:
		return false
	ci.draw_texture(tex, at.floor())
	return true


## A seat's build in its panel (content from `x`): one pip per spell slot in the order taken, filled by level (an
## evolved one glows white at the rim), and under it a thinner pip per passive slot; a free slot is a dim outline,
## so the player sees how many are left (the cap rises after the first boss).
static func build(a: Arena, ci: CanvasItem, _slot: int, x: float, p: Dictionary, _dark: Color) -> void:
	var spells: Array = p.get("spells", [])
	var passives: Array = p.get("passives", [])
	var cap: Vector2i = a.slot_cap
	var n_sp := clampi(maxi(spells.size(), cap.x), 1, World.P_SLOTS)
	var n_pa := clampi(maxi(passives.size(), cap.y), 0, World.P_SLOTS)
	# Four pips fit at 9 px a step; a fifth and sixth squeeze them to 7 px.
	var step := 9.0 if maxi(n_sp, n_pa) <= 4 else 7.0
	for k in n_sp:
		var px := x + 64 + k * step
		var wlv: int = int(spells[k][1]) if k < spells.size() else 0
		var sp := Upgrades.spell_of(int(spells[k][0])) if k < spells.size() else -1
		if wlv <= 0 or sp < 0:
			ci.draw_rect(Rect2(px, 3, step - 1, 4), Color("2a2140")) # a free slot: a dim frame
			ci.draw_rect(Rect2(px + 1, 4, step - 3, 2), Color("0b0716"))
			continue
		# Either evolution id (level MAX_LEVEL + id): id 2 shows as id 1 until a later job gives it a look of its own.
		var evolved := wlv > Spells.MAX_LEVEL
		if _slot_icon(ci, Upgrades.key(int(spells[k][0])), evolved, Vector2(px, 1), SLOT_ICON, Still.weapon_icon(int(p.get("cls", 0)), sp)):
			# The picture over a one pixel level bar (white at the rim once evolved).
			ci.draw_rect(Rect2(px, 9, step - 1, 1), Color.WHITE if evolved else Color("3a2f55"))
			ci.draw_rect(Rect2(px, 9, (step - 1) * mini(wlv, Spells.MAX_LEVEL) / Spells.MAX_LEVEL, 1), a.SPELL_COLORS[sp])
			continue
		ci.draw_rect(Rect2(px, 3, step - 1, 4), Color.WHITE if evolved else Color("3a2f55"))
		ci.draw_rect(Rect2(px + 1, 4, (step - 3) * mini(wlv, Spells.MAX_LEVEL) / Spells.MAX_LEVEL, 2), a.SPELL_COLORS[sp])
	for k in n_pa:
		var px := x + 64 + k * step
		if k >= passives.size():
			ci.draw_rect(Rect2(px, 8, step - 1, 2), Color("2a2140"))
			continue
		var idx := int(passives[k][0])
		var top := maxi(1, Upgrades.max_level(idx))
		if _slot_icon(ci, Upgrades.key(idx), false, Vector2(px, 11), PASSIVE_ICON):
			ci.draw_rect(Rect2(px, 11 + PASSIVE_ICON, step - 1, 1), Color("3a2f55"))
			ci.draw_rect(Rect2(px, 11 + PASSIVE_ICON, (step - 1) * mini(int(passives[k][1]), top) / top, 1), Color("ffd94d"))
			continue
		ci.draw_rect(Rect2(px, 8, step - 1, 2), Color("3a2f55"))
		ci.draw_rect(Rect2(px, 8, (step - 1) * mini(int(passives[k][1]), top) / top, 2), Color("ffd94d"))


## The 44 px column in the middle of the HUD strip (CENTRE). Empty for now.
static func centre(a: Arena, ci: CanvasItem, dark: Color) -> void:
	# The run's step (any but WIZARD) on a plate left of the level-and-clock pill, the way the lull's hangs right.
	if a.game_over or a.victory:
		return
	if a.seal != 0:
		var pw := PixelFont.text_width("LV %d" % a.party_level, 1) + 6 + PixelFont.text_width(ArenaFateView._clock(a.run_t), 1) + 8
		var step := Seals.title(a.seal)
		var sw := PixelFont.text_width(step, 1) + 8
		var sy := 234.0 if a.boss_f > 0.0 else G.SCREEN.y - 13.0
		var sx := floorf(240.0 - pw / 2.0) - 3.0 - sw
		ci.draw_rect(Rect2(sx, sy, sw, 12), Color(dark, 0.92))
		ci.draw_rect(Rect2(sx, sy - 1, sw, 1), Color("2f2450"))
		PixelFont.draw(ci, step, Vector2(sx + 4, sy + 3), 1, Color("8bff9e") if a.seal < 0 else Color("ffb347"), dark)
	# The fates in force: plain tags stacked over the level-and-clock pill at the foot of the screen.
	if a.fates.size() < 2:
		return
	var tags: Array[String] = []
	if a.fates[0] > 0.0:
		tags.append("NOVAS SEALED %d" % ceili(a.fates[0]))
	if a.fates[1] > 0.0:
		tags.append("NO POTIONS %d" % ceili(a.fates[1]))
	var y := (234.0 if a.boss_f > 0.0 else G.SCREEN.y - 13.0) - 12.0
	for tag: String in tags:
		var tw := PixelFont.text_width(tag, 1) + 8
		ci.draw_rect(Rect2(floorf(240.0 - tw / 2.0), y, tw, 11), Color(dark, 0.85))
		PixelFont.draw_centered(ci, tag, 240, y + 2, 1, Color("ff8a9a"), dark)
		y -= 12.0


## The party's one XP bar along the bottom edge of the HUD strip; at the foot of the screen (above the boss bar
## while a boss is up) the party level beside the run clock, and the lull's countdown next to them. The columns
## under the HUD strip belong to the wizards' card tabs and trays.
static func _draw_party_bar(a: Arena, ci: CanvasItem, dark: Color) -> void:
	var xf := clampf(float(a.party_xp) / float(maxi(1, a.party_need)), 0.0, 1.0)
	var y := G.HUD_H - 2.0
	var flash := clampf(1.0 - (a.time - a._lv_flash_t) / 0.6, 0.0, 1.0)
	ci.draw_rect(Rect2(0, y, G.SCREEN.x, 2), Color("1c2a24"))
	ci.draw_rect(Rect2(0, y, G.SCREEN.x * xf, 2), Color("5dff7a").lerp(Color.WHITE, flash))
	if flash > 0.0:
		ci.draw_rect(Rect2(0, y - 1, G.SCREEN.x, 3), Color(1, 1, 1, flash * 0.35))
	if a.game_over:
		return
	var lv := "LV %d" % a.party_level
	var clock := ArenaFateView._clock(a.run_t)
	var gap := 6
	var lw := PixelFont.text_width(lv, 1)
	var cw := PixelFont.text_width(clock, 1)
	var pw := lw + gap + cw + 8
	# The pill stays centred on its own and the lull plate hangs off its right side at one width, so nothing
	# jumps sideways when a lull starts or ends or its count drops a digit.
	var x0 := floorf(240.0 - pw / 2.0)
	var py := 234.0 if a.boss_f > 0.0 else G.SCREEN.y - 13.0
	var lc := Color("5dff7a").lerp(Color.WHITE, flash)
	ci.draw_rect(Rect2(x0, py, pw, 12), Color(dark, 0.92))
	ci.draw_rect(Rect2(x0, py - 1, pw, 1), Color("2f2450"))
	PixelFont.draw(ci, lv, Vector2(x0 + 4, py + 3), 1, lc, dark)
	PixelFont.draw(ci, clock, Vector2(x0 + 4 + lw + gap, py + 3), 1, Color("c9b8ff"), dark)
	if a.lull_left <= 0.0:
		return
	# The lull: a gold plate counting down, its bar draining; red in the last three seconds.
	var lull := "RESPITE %d" % ceili(a.lull_left)
	var rw := PixelFont.text_width("RESPITE 00", 1) + 8
	var lx := x0 + pw + 4
	var urgent := a.lull_left <= 3.0
	var pulse := 0.5 + 0.5 * sin(a.time * (10.0 if urgent else 4.0))
	var gc := Color("ffd94d").lerp(Color("ff6a4d"), pulse) if urgent else Color("ffd94d")
	ci.draw_rect(Rect2(lx - 1, py - 1, rw + 2, 14), Color(gc, 0.35 + 0.35 * pulse))
	ci.draw_rect(Rect2(lx, py, rw, 12), Color(dark, 0.95))
	PixelFont.draw(ci, lull, Vector2(lx + 4, py + 3), 1, gc, dark)
	ci.draw_rect(Rect2(lx + 1, py + 11, (rw - 2) * clampf(a.lull_left / a._lull_full, 0.0, 1.0), 1), gc)


## Arrows at the screen's edge pointing at what matters out of view: chests, cards and the Lich.
static func _draw_offscreen(a: Arena, ci: CanvasItem) -> void:
	var view := Rect2(Vector2(6, G.HUD_H + 6), G.SCREEN - Vector2(12, G.HUD_H + 12))
	var marks: Array = []
	for k: Array in a.vk:
		var kind: int = k[0]
		if kind == World.PK_CHEST or kind >= World.PK_CARD:
			marks.append([k[1], ArenaDrawFx._pickup_color(a, kind)])
	for e: Dictionary in a.ve.values():
		if e.type == World.LICH:
			marks.append([e.pos, Color("ff4df2") if a.boss_final else Color("4dfff0")])
	for m: Array in marks:
		var sp := a._on_screen(m[0])
		if view.grow(4).has_point(sp):
			continue
		var center := view.get_center()
		var d: Vector2 = (sp - center)
		# Where the line from the middle to the thing leaves the view.
		var tx := (view.size.x / 2.0) / maxf(absf(d.x), 0.001)
		var ty := (view.size.y / 2.0) / maxf(absf(d.y), 0.001)
		var at := center + d * minf(tx, ty)
		var dir := d.normalized()
		var side := Vector2(-dir.y, dir.x)
		var pulse := 0.6 + 0.4 * sin(a.time * 6.0)
		var col: Color = m[1]
		var tip := at
		var pts := PackedVector2Array([tip, tip - dir * 7.0 + side * 4.0, tip - dir * 7.0 - side * 4.0])
		ci.draw_colored_polygon(pts, Color(col, pulse))
		ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(Occult.INK, 0.9), 1.0)


static func _heart(a: Arena, ci: CanvasItem, p: Vector2, full: bool) -> void:
	var c := Color("ff3b5c") if full else Color("3a2240")
	ci.draw_rect(Rect2(p + Vector2(0, 1), Vector2(5, 2)), c)
	ci.draw_rect(Rect2(p + Vector2(1, 0), Vector2(1, 1)), c)
	ci.draw_rect(Rect2(p + Vector2(3, 0), Vector2(1, 1)), c)
	ci.draw_rect(Rect2(p + Vector2(1, 3), Vector2(3, 1)), c)
	ci.draw_rect(Rect2(p + Vector2(2, 4), Vector2(1, 1)), c)
	if full:
		ci.draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 1)), Color("ffc0cc"))


static func _hat(a: Arena, ci: CanvasItem, p: Vector2, c: Color) -> void:
	ci.draw_rect(Rect2(p + Vector2(2, 0), Vector2(1, 1)), c)
	ci.draw_rect(Rect2(p + Vector2(1, 1), Vector2(3, 2)), c)
	ci.draw_rect(Rect2(p + Vector2(0, 3), Vector2(5, 1)), c.darkened(0.3))


static func _star(a: Arena, ci: CanvasItem, p: Vector2) -> void:
	var c := Color("ffe84d")
	ci.draw_rect(Rect2(p + Vector2(2, 0), Vector2(1, 5)), c)
	ci.draw_rect(Rect2(p + Vector2(0, 2), Vector2(5, 1)), c)
	ci.draw_rect(Rect2(p + Vector2(1, 1), Vector2(3, 3)), c)
	ci.draw_rect(Rect2(p + Vector2(2, 2), Vector2(1, 1)), Color.WHITE)

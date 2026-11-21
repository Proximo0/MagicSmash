class_name ArenaResultsView
extends RefCounted
## Arena: the game-over screen, result columns, moments and the pause screen.
## Static helpers: `a` is the Arena that owns the state.

static func _draw_game_over(a: Arena, ci: CanvasItem) -> void:
	var fade := clampf(a.game_over_t / 1.0, 0.0, 1.0)
	var dark := Color("0b0716")
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.03, 0.0, 0.08, 0.82 * fade))
	if a.game_over_t < 0.6:
		return
	var title := "VICTORY!" if a.victory else "THE TOWER FALLS"
	var tw := PixelFont.text_width(title, 4)
	PixelFont.draw(ci, title, Vector2(240 - tw / 2.0, 10) + Vector2(2, 2), 4, dark)
	PixelFont.draw_gradient(ci, title, Vector2(240 - tw / 2.0, 10), 4, Color("ffd94d"), Color("8bff9e") if a.victory else Color("ff3b5c"), a.time * 3.0, 2.0)
	var sub := ("WON AT " if a.victory else "SURVIVED ") + ArenaFateView._clock(a.run_t) + "    TEAM SCORE %07d" % a.final_score
	PixelFont.draw_centered(ci, sub, 240, 44, 1, Color("8bff9e") if a.victory else Color("c9b8ff"), dark)
	_draw_result_columns(a, ci, dark, 58)
	_draw_moments(a, ci, dark, 150)
	var foot := "BEST %07d    +%d CRYSTALS  (%d TO SPEND)" % [G.high_score, a.crystals_earned, Save.profile.crystals]
	PixelFont.draw_centered(ci, Lore.ending(a.victory, a.final_score), 240, 208, 1, Color("e8dcc0"), dark)
	PixelFont.draw_centered(ci, foot, 240, 224, 1, Color("8bdcff"), dark)
	if not Save.profile.last_pay.is_empty(): # the run's step and what it paid
		PixelFont.draw_centered(ci, Seals.pay_line(Save.profile.last_pay), 240, 234, 1, Color("ffb347"), dark)
	if a.game_over_t > 2.0 and int(a.time * 2.5) % 2 == 0:
		var msg := "PRESS FIRE TO CONTINUE" if a.is_host else "WAITING FOR HOST..."
		if G.touch_active and a.is_host:
			msg = "TAP TO CONTINUE"
		PixelFont.draw_centered(ci, msg, 240, 244, 1, Color.WHITE, dark)

## The tarot card each award is read as on the results screen (TarotArt emblem keys); no award draws The Star.
const AWARD_ARCANA := {"MVP": "power", "SLAYER": "death", "HIGH ROLLER": "magnet", "LUCKY": "sun",
	"GOLD DIGGER": "quick", "UNTOUCHABLE": "life", "TEAM PLAYER": "regen"}


## One column per wizard: name, award, then score, level, kills, damage and gold, revealed one by one. A party's
## columns add FELL/RAISED (times fallen / rituals helped finish), at 9 px a row so the card still holds them.
static func _draw_result_columns(a: Arena, ci: CanvasItem, dark: Color, y0: int) -> void:
	var slots: Array = []
	for slot in 4:
		if a.vp.has(slot):
			slots.append(slot)
	if slots.is_empty():
		return
	var titles := {}
	if a.results != null:
		for aw: Array in a.results.awards():
			titles[int(aw[0])] = aw[1]
	var colw := 112.0
	var x0 := 240.0 - colw * slots.size() / 2.0
	var rows := [["SCORE", "score"], ["LEVEL", "level"], ["KILLS", "kills"], ["DAMAGE", "damage"], ["GOLD", "gold"]]
	var party := slots.size() > 1
	if party:
		rows.append(["FELL/RAISED", "fallen"])
	for i in slots.size():
		var slot: int = slots[i]
		var cx := x0 + colw * (i + 0.5)
		var show := clampf((a.game_over_t - 0.8 - i * 0.25) / 0.3, 0.0, 1.0)
		if show <= 0.0:
			continue
		var col := G.player_color(slot)
		# Each wizard's reading: a card face with their award's arcana in the corner.
		var card := Rect2(cx - colw / 2.0 + 4, y0 - 4, colw - 8, 88)
		ci.draw_rect(card, Color(col.r * 0.25, col.g * 0.2, col.b * 0.3, 0.75 * show))
		ci.draw_rect(card, Color(Occult.GOLD, 0.7 * show), false, 1.0)
		ci.draw_rect(card.grow(-2), Color(col.r, col.g, col.b, 0.45 * show), false, 1.0)
		var award: String = titles.get(slot, "")
		var arcana: String = AWARD_ARCANA.get(award, "w_star")
		var em := Rect2(card.position + Vector2(5, 4), Vector2(24, 24))
		ci.draw_rect(em.grow(1), Color(dark, show))
		ci.draw_texture_rect(TarotArt.emblem(arcana), em, false, Color(1, 1, 1, show))
		PixelFont.draw_centered(ci, "P%d" % (slot + 1), cx + 14, y0 + 2, 2, col, dark)
		if award != "":
			PixelFont.draw_centered(ci, award, cx + 14, y0 + 18, 1, Color("ffd94d"), dark)
		var y := y0 + (28 if party else 30)
		for r: Array in rows:
			var v: float = float(a.vp[slot].score) if r[1] == "score" else (a.results.stat(slot, r[1]) if a.results != null else 0.0)
			PixelFont.draw(ci, r[0], Vector2(cx - 46, y), 1, Color("8a7aa8"), dark)
			var txt := "%d" % int(v)
			if r[1] == "fallen":
				txt = "%d/%d" % [a.results.downs(slot), a.results.revives(slot)] if a.results != null else "0/0"
			PixelFont.draw(ci, txt, Vector2(cx + 46 - PixelFont.text_width(txt, 1), y), 1, Color.WHITE, dark)
			y += 9 if party else 10


## The team's best moments, with the run time each happened at.
static func _draw_moments(a: Arena, ci: CanvasItem, dark: Color, y0: int) -> void:
	if a.results == null or a.game_over_t < 1.8:
		return
	var top: Array = a.results.top_moments()
	if top.is_empty():
		return
	PixelFont.draw_centered(ci, "BEST MOMENTS", 240, y0, 1, Color("ff4df2"), dark)
	var y := y0 + 14
	for i in top.size():
		if a.game_over_t < 2.0 + i * 0.3:
			break
		var m: Array = top[i]
		var line := ArenaFateView._clock(float(m[0])) + "  " + Results.moment_text(m)
		PixelFont.draw_centered(ci, line, 240, y, 1, G.player_fx(int(m[2])), dark)
		y += 12


static func _draw_pause(a: Arena, ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.03, 0.0, 0.08, 0.7))
	var tw := PixelFont.text_width("PAUSED", 4)
	PixelFont.draw_gradient(ci, "PAUSED", Vector2(240 - tw / 2.0, 60), 4, Color.WHITE, Color("b78cff"), a.time * 4.0, 1.0)
	if a.pause_options:
		a.options.draw(ci, a.time)
		return
	var panel := Rect2(170, 118, 140, 66)
	Occult.frame(ci, panel, a.time)
	Occult.candle(ci, Vector2(158, 184), a.time, 0.0, 10)
	Occult.candle(ci, Vector2(322, 184), a.time, 2.0, 10)
	for i in a.PAUSE_ITEMS.size():
		var sel := i == a.pause_sel
		var y := 130 + i * 16
		if sel:
			var w := PixelFont.text_width(a.PAUSE_ITEMS[i])
			Occult.highlight(ci, Rect2(240 - w / 2.0 - 16, y - 3, w + 32, 13), a.time)
			Occult.cursor(ci, Vector2(240 - w / 2.0 - 9, y + 3), a.time)
		PixelFont.draw_centered(ci, a.PAUSE_ITEMS[i], 240, y, 1, Occult.GOLD if sel else Occult.DIM, Occult.INK)

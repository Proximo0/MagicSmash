class_name ArenaResultsView
extends RefCounted
## Arena: the game-over screen, result columns, moments and the pause screen.
## Static helpers: `a` is the Arena that owns the state.

## With deeds or a found card to show the ending line gives way: the totals line moves up and those lines sit under
## the pay line (Achievements.result_lines).
const DEED_FOOT_Y := 206
const DEED_FIRST_Y := 226
const DEED_STEP := 9
const DEED_PROMPT_Y := 256
## Under the pay lines of a lost run while the profile has no win yet: the climb is long and progress carries over.
## It takes one of the deed lines' places (Achievements.RESULT_LINES in all).
const CLIMB_HINT := "THE TOWER REMEMBERS. SPEND CRYSTALS IN THE SANCTUM."


## The damage page: its card top, row step and bar height, and the hint line the first page shows when it leads there.
const DMG_Y := 70
const DMG_TITLE_Y := 56
const DMG_ROW_Y := 18
const DMG_ROW_STEP := 17
const DMG_BAR_H := 3
const DMG_BAR_W := 66.0
const DMG_PAGE := 1


## Whether any wizard has damage to show (the first page's press then leads to the damage page).
static func has_damage_page(a: Arena) -> bool:
	if a.results == null:
		return false
	for slot: int in a.vp:
		if not a.results.damage_rows(int(slot)).is_empty():
			return true
	return false


## The results press: from the first page to the damage page (true), or false when it is time to leave.
static func next_page(a: Arena) -> bool:
	if a.results_page == 0 and has_damage_page(a):
		a.results_page = DMG_PAGE
		Sfx.play("page_turn")
		return true
	return false


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
	if a.results_page == DMG_PAGE:
		_draw_damage_page(a, ci, dark)
		return
	_draw_result_columns(a, ci, dark, 58)
	_draw_moments(a, ci, dark, 150)
	var foot := "BEST %07d    +%d CRYSTALS  (%d TO SPEND)" % [G.high_score, Save.profile.run_gain(a.crystals_earned), Save.profile.crystals]
	var deeds: Array[String] = foot_lines(Save.profile.last_pay.get("deeds", []), not a.victory and Save.profile.wins == 0, _cards_found(a))
	var y_foot := 224 if deeds.is_empty() else DEED_FOOT_Y # new deeds take the ending's place
	if deeds.is_empty():
		PixelFont.draw_centered(ci, Lore.ending(a.victory, a.final_score), 240, 208, 1, Color("e8dcc0"), dark)
	PixelFont.draw_centered(ci, foot, 240, y_foot, 1, Color("8bdcff"), dark)
	if not Save.profile.last_pay.is_empty(): # the run's step and what it paid
		PixelFont.draw_centered(ci, Seals.pay_line(Save.profile.last_pay), 240, y_foot + 10, 1, Color("ffb347"), dark)
	for i: int in range(deeds.size()):
		PixelFont.draw_centered(ci, deeds[i], 240, DEED_FIRST_Y + i * DEED_STEP, 1,
			Color("c9b8ff") if deeds[i] == CLIMB_HINT else Color("ffd94d"), dark)
	if a.game_over_t > 2.0 and int(a.time * 2.5) % 2 == 0:
		var go := "TAP" if G.touch_active else "PRESS FIRE"
		var msg := go + " FOR DAMAGE" if has_damage_page(a) else go + " TO CONTINUE" # a client leaves by itself too
		PixelFont.draw_centered(ci, msg, 240, 244 if deeds.is_empty() else DEED_PROMPT_Y, 1, Color.WHITE, dark)

## The lines under the pay line: the cards found and the new deeds (Achievements.result_lines) and, with `hint` (a
## lost run on a profile with no win yet), CLIMB_HINT last, within the same Achievements.RESULT_LINES lines (fewer
## cards and deeds shown, the rest counted in "+K MORE DEEDS", or "+K MORE" when a card is among them).
static func foot_lines(deed_names: Array, hint: bool, cards: Array = []) -> Array[String]:
	var lines: Array[String] = Achievements.result_lines(deed_names, cards)
	if not hint:
		return lines
	if lines.size() >= Achievements.RESULT_LINES:
		var keep := Achievements.RESULT_LINES - 2
		var shown_cards: Array = cards.slice(0, keep)
		lines = Achievements.result_lines(deed_names.slice(0, keep - shown_cards.size()), shown_cards)
		var left: int = cards.size() + deed_names.size() - keep
		lines.append("+%d MORE DEEDS" % left if cards.size() <= keep else "+%d MORE" % left)
	lines.append(CLIMB_HINT)
	return lines


## The Cards indices found in the run, in order (the record's card moments): the results' "CARD FOUND" lines.
static func _cards_found(a: Arena) -> Array:
	var out: Array = []
	if a.results != null:
		for m: Array in a.results.moments:
			if int(m[1]) == Results.M_CARD:
				out.append(int(m[3]))
	return out


## The second page: under each wizard's card her sources by damage, most first, each as NAME and share with a bar
## in the wizard's colour. The press that leaves comes from here.
static func _draw_damage_page(a: Arena, ci: CanvasItem, dark: Color) -> void:
	PixelFont.draw_centered(ci, "DAMAGE", 240, DMG_TITLE_Y, 1, Color("ff4df2"), dark)
	var slots: Array = []
	for slot in 4:
		if a.vp.has(slot):
			slots.append(slot)
	var colw := 112.0
	var x0 := 240.0 - colw * slots.size() / 2.0
	var most := 1 # the tallest column sets every card's height
	for slot: int in slots:
		most = maxi(most, a.results.damage_rows(slot).size() if a.results != null else 0)
	for i in slots.size():
		var slot: int = slots[i]
		var cx := x0 + colw * (i + 0.5)
		var show := clampf((a.game_over_t - 0.8 - i * 0.25) / 0.3, 0.0, 1.0)
		var col := G.player_color(slot)
		var card := Rect2(cx - colw / 2.0 + 4, DMG_Y - 4, colw - 8, DMG_ROW_Y + 12 + DMG_ROW_STEP * most)
		ci.draw_rect(card, Color(col.r * 0.25, col.g * 0.2, col.b * 0.3, 0.75 * show))
		ci.draw_rect(card, Color(Occult.GOLD, 0.7 * show), false, 1.0)
		ci.draw_rect(card.grow(-2), Color(col.r, col.g, col.b, 0.45 * show), false, 1.0)
		PixelFont.draw_centered(ci, "P%d" % (slot + 1), cx, DMG_Y + 2, 2, col, dark)
		var rows: Array = a.results.damage_rows(slot) if a.results != null else []
		if rows.is_empty():
			PixelFont.draw_centered(ci, "NO DAMAGE", cx, DMG_Y + DMG_ROW_Y + 8, 1, Color("8a7aa8"), dark)
			continue
		var cls: int = int(a.vp[slot].cls)
		var y := DMG_Y + DMG_ROW_Y + 8
		for r: Array in rows:
			var pct := "%d%%" % int(r[2])
			PixelFont.draw(ci, Results.source_name(int(r[0]), cls), Vector2(cx - 46, y), 1, Color("e8dcc0"), dark)
			PixelFont.draw(ci, pct, Vector2(cx + 46 - PixelFont.text_width(pct, 1), y + 8), 1, Color.WHITE, dark)
			var bar := Rect2(cx - 46, y + 10, DMG_BAR_W, DMG_BAR_H)
			ci.draw_rect(bar, Color(0, 0, 0, 0.5 * show))
			ci.draw_rect(Rect2(bar.position, Vector2(DMG_BAR_W * float(r[2]) / 100.0, DMG_BAR_H)), Color(col, show))
			y += DMG_ROW_STEP
	if a.game_over_t > 2.0 and int(a.time * 2.5) % 2 == 0:
		PixelFont.draw_centered(ci, "TAP TO CONTINUE" if G.touch_active else "PRESS FIRE TO CONTINUE", 240, DEED_PROMPT_Y, 1, Color.WHITE, dark)


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
		y += 10


const PAUSE_HEAD_Y := 60
const PAUSE_HEAD_ASK_Y := 40

static func _draw_pause(a: Arena, ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.03, 0.0, 0.08, 0.7))
	var head := "PAUSED" if a.pause_by < 0 else "PAUSED BY P%d" % (a.pause_by + 1)
	var top := Color.WHITE if a.pause_by < 0 else G.player_color(a.pause_by).lightened(0.45)
	var low := Color("b78cff") if a.pause_by < 0 else G.player_color(a.pause_by)
	var tw := PixelFont.text_width(head, 4)
	# The heading moves up while QUIT TO TITLE's question shows under it.
	PixelFont.draw_gradient(ci, head, Vector2(240 - tw / 2.0, PAUSE_HEAD_ASK_Y if a.pause_ask else PAUSE_HEAD_Y), 4, top, low,
		a.time * 4.0, 1.0)
	if a.pause_options:
		a.options.draw(ci, a.time)
		return
	if a.pause_ask:
		PixelFont.draw_centered(ci, "END THE RUN?", 240, 80, 2, Occult.GOLD, Occult.INK)
		PixelFont.draw_centered(ci, "WHAT YOU EARNED IS KEPT", 240, 99, 1, Occult.DIM, Occult.INK)
	var rows: Array = a._pause_rows()
	var panel := Rect2(170, 118, 140, 18 + rows.size() * 16)
	Occult.frame(ci, panel, a.time)
	Occult.candle(ci, Vector2(158, panel.end.y), a.time, 0.0, 10)
	Occult.candle(ci, Vector2(322, panel.end.y), a.time, 2.0, 10)
	for i in rows.size():
		var sel := i == a.pause_sel
		var y := 130 + i * 16
		var label: String = rows[i]
		if sel:
			var w := PixelFont.text_width(label)
			Occult.highlight(ci, Rect2(240 - w / 2.0 - 16, y - 3, w + 32, 13), a.time)
			Occult.cursor(ci, Vector2(240 - w / 2.0 - 9, y + 3), a.time)
		var col := Occult.GOLD if sel else Occult.DIM
		if a._pause_row_dim(i):
			col = col.darkened(0.55)
		PixelFont.draw_centered(ci, label, 240, y, 1, col, Occult.INK)
	if a.time - a.pause_note_t < a.PAUSE_NOTE_SECS:
		PixelFont.draw_centered(ci, "ONLY P%d CAN END THE RUN" % (a._first_seat() + 1), 240, panel.end.y + 12, 1,
			Color("ff8a8a"), Occult.INK)

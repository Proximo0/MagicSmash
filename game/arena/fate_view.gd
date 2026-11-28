class_name ArenaFateView
extends RefCounted
## Arena: clock, chest and card reveals, shrines, bets and fate cards, banners and the act card.
## Static helpers: `a` is the Arena that owns the state.

## The picture of a boss that slides in at the right edge, under the banner, when he arrives (the Archlich's portrait,
## the Lich's card). The banner names him; `who` is kept for callers.
const ARRIVE_SECS := 2.5
const ARRIVE_SLIDE := 0.4
const ARRIVE_PIC := Vector2i(80, 120)
## Just under the banner band (y 88 to 132), so the banner is never covered.
const ARRIVE_Y := 134.0
## The arrival on show: {group, key, name, color, t0}, empty when none.
static var _arrive := {}


## Run time as M:SS.
static func _clock(secs: float) -> String:
	var t := int(secs)
	return "%d:%02d" % [t / 60, t % 60]


## Advances chest reels; when a reel stops it plays its tier's sound and burst.
static func _update_reveals(a: Arena, dt: float) -> void:
	for r: Dictionary in a._reveals:
		var prev: float = r.t
		r.t += dt
		if a.vp.has(r.slot):
			r.pos = (a.vp[r.slot] as Dictionary).pos
		if not r.shown and r.t < a.REEL_SPIN and int(r.t * 14.0) != int(prev * 14.0):
			Sfx.play("menu_move", -10.0, 1.0 + r.t * 0.6)
		if not r.shown and r.t >= a.REEL_SPIN:
			r.shown = true
			var col: Color = a.RARITY_COLORS[r.tier]
			var at: Vector2 = r.pos + Vector2(0, -34)
			a.fx.burst(at, 10 + 8 * r.tier, 60.0 + 30.0 * r.tier, 0.6, 1.5, Color.WHITE, col, true)
			match r.tier:
				Loot.COMMON:
					Sfx.play("pickup", -4.0)
				Loot.RARE:
					Sfx.play("powerup", -4.0)
				Loot.EPIC:
					Sfx.play("powerup", -2.0, 1.2)
				_:
					Sfx.play("wave_clear", -2.0, 1.1 if r.tier == Loot.LEGENDARY else 1.3)
					a.fx.ring(at, 4.0, 40.0 + 20.0 * (r.tier - Loot.LEGENDARY), 0.6, col, 2.0)
					a._add_shake(3.0 * (r.tier - Loot.EPIC))
	a._reveals = a._reveals.filter(func(r: Dictionary) -> bool: return r.t < a.REEL_SPIN + a.REEL_SHOW)
	if not a._cards.is_empty():
		a._cards[0].t += dt
		if a._cards[0].t >= a.CARD_SHOW:
			a._cards.pop_front()


## The monster card a wizard just found, as a small notice that keeps the fight in view: a strip at the top edge,
## under the HUD and the level-up tabs, with a small card (CARD_NOTE_PIC: the monster's sprite in a frame of its
## socket's colour; a painted card shrunk this far reads as a dark blot) and "CARD FOUND: NAME" over who found it.
## It fades in, holds for Arena.CARD_SHOW s and fades out. The full card waits for the results screen and the album.
const CARD_NOTE_PIC := Vector2(16, 24)
const CARD_NOTE_PAD := 3.0


static func _draw_card_reveal(a: Arena, ci: CanvasItem, dark: Color) -> void:
	if a._cards.is_empty() or a.game_over: # the results screen names the card itself
		return
	var c: Dictionary = a._cards[0]
	var t: float = c.t
	var fade := clampf(minf(t * 5.0, (a.CARD_SHOW - t) * 4.0), 0.0, 1.0)
	var idx: int = c.idx
	var title := "CARD FOUND: " + Cards.card_name(idx)
	var sub := "P%d  %s" % [int(c.slot) + 1, "NEW TO YOUR COLLECTION" if c.first else "ANOTHER FOR THE ALBUM"]
	var text_w := maxf(PixelFont.text_width(title), PixelFont.text_width(sub))
	var pic_w := CARD_NOTE_PIC.x + CARD_NOTE_PAD + 1.0
	var size := Vector2(pic_w + text_w + CARD_NOTE_PAD * 2.0, CARD_NOTE_PIC.y + CARD_NOTE_PAD * 2.0)
	var box := Rect2(Vector2(floorf(240.0 - size.x / 2.0), G.HUD_H + a.TAB_H + 3.0), size)
	var edge := Color("ff4df2").lerp(Color.WHITE, 0.35 + 0.35 * sin(a.time * 8.0))
	ci.draw_rect(box, Color(0.04, 0.0, 0.1, 0.85 * fade))
	ci.draw_rect(box, Color(edge, fade), false, 1.0)
	_draw_card_mini(ci, Rect2(box.position + Vector2(CARD_NOTE_PAD, CARD_NOTE_PAD), CARD_NOTE_PIC), idx, fade)
	var x := box.position.x + CARD_NOTE_PAD + pic_w
	var ty := box.position.y + CARD_NOTE_PAD + 3.0
	PixelFont.draw(ci, title, Vector2(x, ty), 1, Color(Color("ffd94d"), fade), dark)
	PixelFont.draw(ci, sub, Vector2(x, ty + 10.0), 1, Color(Color("c9b8ff"), fade), dark)


## A card small enough for the notice: the monster's sprite at its own size (cut to fit), or a Seal card's numeral,
## on the card's face inside a frame of its socket's colour.
static func _draw_card_mini(ci: CanvasItem, r: Rect2, idx: int, fade: float) -> void:
	ci.draw_rect(r.grow(1), Color(MonsterCard.INK, fade))
	ci.draw_rect(r, Color(MonsterCard.FACE, fade))
	ci.draw_rect(r, Color(MonsterCard.SOCKET_COLORS[Cards.socket(idx)], 0.9 * fade), false, 1.0)
	var kind := Cards.enemy(idx)
	if kind < 0 or kind >= MonsterCard.ENEMY_SPRITES.size():
		var num := Seals.numeral(Seals.of_card(idx))
		PixelFont.draw_centered(ci, num, r.get_center().x, r.get_center().y - 3.0, 1, Color(MonsterCard.GOLD, fade), MonsterCard.INK)
		return
	var key: String = MonsterCard.ENEMY_SPRITES[kind]
	var tex := Sprites.get_tex(key)
	if tex == null:
		return
	var src := MonsterCard._drawn_part(key, tex)
	var room := r.size - Vector2(4, 4)
	var seen := Vector2(minf(src.size.x, room.x), minf(src.size.y, room.y))
	src = Rect2(src.position.x + floorf((src.size.x - seen.x) / 2.0), src.position.y, seen.x, seen.y)
	ci.draw_texture_rect_region(tex, Rect2((r.get_center() - seen / 2.0).floor(), seen), src, Color(1, 1, 1, fade))


## Altars: a rune altar (solo) with three rune stones circling it, or the fate altar (team) with a tarot card
## turning over it. The price floats above and a ring fills while a wizard bets.
static func _draw_shrines(a: Arena, ci: CanvasItem) -> void:
	var dark := Color("0b0716")
	for r: Array in a.vsh:
		var kind: int = r[0]
		var at := Vector2(r[1], r[2])
		var life: float = r[3]
		if life < 4.0 and int(life * 8.0) % 2 == 0:
			continue
		var col: Color = a.SHRINE_COLORS[kind]
		var big := 1.5 if kind == Gamble.TEAM else 1.0
		var pulse := 0.5 + 0.5 * sin(a.time * 4.0)
		ci.draw_circle(at, 15.0 * big, Color(col.r, col.g, col.b, 0.10 + 0.08 * pulse))
		Occult.pentagram(ci, at + Vector2(0, 2), 11.0 * big, Color(col.r, col.g, col.b, 0.35 + 0.2 * pulse), a.time * 0.3)
		ci.draw_arc(at + Vector2(0, 2), 12.0 * big, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.45), 1.0)
		# The altar stone with two candles.
		var w := 12.0 * big
		var top := (at + Vector2(-w / 2.0, -3)).floor()
		ci.draw_rect(Rect2(top + Vector2(0, 1), Vector2(w, 6)), Color("2a2140"))
		ci.draw_rect(Rect2(top, Vector2(w, 2)), Color("7a6aa0"))
		ci.draw_rect(Rect2(top + Vector2(2, 2), Vector2(w - 4, 4)), Color("3a2f55"))
		Occult.candle(ci, top + Vector2(1, 0), a.time, at.x, 4)
		Occult.candle(ci, top + Vector2(w - 1, 0), a.time, at.y, 4)
		if kind == Gamble.TEAM:
			var turn := absf(cos(a.time * 1.6))
			var cw := maxf(1.0, 14.0 * turn)
			var cr := Rect2(at.x - cw / 2.0, at.y - 30.0 - 2.0 * sin(a.time * 2.0), cw, 20)
			TarotArt.draw_back(ci, cr)
		else:
			for k in 3:
				var ang := a.time * 1.4 + k * TAU / 3.0
				var sp := at + Vector2(cos(ang) * 10.0, -13.0 + sin(ang) * 4.0)
				_rune_stone(a, ci, sp.floor(), (k * 3 + int(a.time * 0.5)) % Occult.RUNES.size(), col, 1.0)
		var charge: float = r[4] # a solo shrine's hold, a team shrine's pot / price
		if charge > 0.0:
			ci.draw_arc(at, 16.0 * big, -PI / 2.0, -PI / 2.0 + TAU * clampf(charge, 0.0, 1.0), 32, Color.WHITE, 2.0)
		# The price, and over a team shrine while more wizards are needed how many; kept on the screen, clear of the HUD.
		var lines: Array[String] = ["%dG" % int(r[5])]
		var need: int = r[6]
		if kind == Gamble.TEAM and need > 0:
			lines.append("2 WIZARDS" if need >= 2 else "1 MORE")
		var gap: float = 8.0 # one line of the pixel font and its outline
		var label_top: float = at.y - (32.0 if kind == Gamble.SOLO else 50.0) - gap * (lines.size() - 1)
		label_top = clampf(label_top, a.cam.y + G.HUD_H + 2.0, a.cam.y + G.SCREEN.y - gap * lines.size() - 1.0)
		for i: int in range(lines.size()):
			var half: float = PixelFont.text_width(lines[i]) / 2.0 + 2.0
			var cx: float = clampf(at.x, a.cam.x + half, a.cam.x + G.SCREEN.x - half)
			PixelFont.draw_centered(ci, lines[i], cx, label_top + gap * (lines.size() - 1 - i), 1, col, dark)


## A rune stone: a pale pebble with a rune cut into it (`rune` -1 for a blank stone).
static func _rune_stone(a: Arena, ci: CanvasItem, p: Vector2, rune: int, glow: Color, alpha: float) -> void:
	ci.draw_rect(Rect2(p + Vector2(-3, -4), Vector2(7, 9)), Color(0.04, 0.0, 0.1, alpha))
	ci.draw_rect(Rect2(p + Vector2(-2, -4), Vector2(5, 9)), Color(0.85, 0.82, 0.74, alpha))
	ci.draw_rect(Rect2(p + Vector2(-3, -3), Vector2(7, 7)), Color(0.85, 0.82, 0.74, alpha))
	ci.draw_rect(Rect2(p + Vector2(-3, 3), Vector2(7, 1)), Color(0.6, 0.56, 0.5, alpha))
	if rune >= 0:
		Occult.rune(ci, p + Vector2(-2, -3), rune, Color(glow.r * 0.5, glow.g * 0.3, glow.b * 0.2, alpha))


## The act's own battle music (Act I's until a track for the act is in).
static func _act_music(a: Arena) -> String:
	var n: String = ["music_battle", "music_library", "music_sanctum"][clampi(a.act, 0, 2)]
	return n if Sfx.has_music(n) else "music_battle"


static func _update_bets(a: Arena, dt: float) -> void:
	for b: Dictionary in a._bets:
		var prev: float = b.t
		b.t += dt
		# The reel ticks slower as it runs down, like a wheel.
		var rate := 16.0 * (1.0 - 0.7 * clampf(b.t / b.spin, 0.0, 1.0))
		if prev >= 0.0 and b.t < b.spin and int(b.t * rate) != int(prev * rate):
			Sfx.play("menu_move", -8.0 if b.kind == Gamble.TEAM else -12.0, 0.9 + b.t / b.spin * 0.5)
		if not b.shown and b.t >= b.spin:
			b.shown = true
			# The music comes back when the last team reel in flight turns face up (the boss's while he is up).
			if b.kind == Gamble.TEAM and _last_team_reel(a._bets, b):
				Sfx.music(_after_reel_music(a.boss_f, _act_music(a)))
	a._bets = a._bets.filter(func(b: Dictionary) -> bool: return b.t < b.spin + a.REEL_SHOW)


## The t a new team reel starts at: 0 when none is on show, else minus the time until the last one queued has
## finished showing (`show` s after it turns), so team reels play one after another at the centre.
static func _team_reel_start(bets: Array, show: float) -> float:
	var wait := 0.0
	for o: Dictionary in bets:
		if o.kind == Gamble.TEAM:
			wait = maxf(wait, float(o.spin) + show - float(o.t))
	return -wait


## True when no team reel but `b` is still spinning or waiting its turn.
static func _last_team_reel(bets: Array, b: Dictionary) -> bool:
	for o: Dictionary in bets:
		if o != b and o.kind == Gamble.TEAM and float(o.t) < float(o.spin):
			return false
	return true


## Altar casts: a solo cast throws three rune stones over the altar and the middle one lands on the outcome's
## rune; the team bet turns a fate card in the middle of the screen, The Sun or Death.
static func _draw_bets(a: Arena, ci: CanvasItem, dark: Color) -> void:
	for b: Dictionary in a._bets:
		if b.t < 0.0:
			continue # a team reel waiting for the one on show
		var spinning: bool = b.t < b.spin
		var good: bool = Gamble.is_good(b.kind, b.outcome)
		var col := Color("8bff9e") if good else Color("ff3b5c")
		var text: String = Gamble.outcome_name(b.kind, b.outcome)
		if b.kind == Gamble.TEAM:
			_draw_fate(a, ci, b, spinning, col, text, dark)
			continue
		var at: Vector2 = a._on_screen(b.pos as Vector2) + Vector2(0, -30)
		var k := clampf(b.t / b.spin, 0.0, 1.0)
		for n in 3:
			# Each stone flies up and tumbles down; the middle one lands last, on the outcome.
			var land := 0.5 + n * 0.25 if n != 1 else 1.0
			var u := clampf(k / land, 0.0, 1.0)
			var p := at + Vector2((n - 1) * 11.0, -sin(u * PI) * 16.0)
			var rune: int = (int(b.t * 12.0) + n * 3 + int(b.slot)) % Occult.RUNES.size()
			if u >= 1.0:
				rune = a.OUTCOME_RUNES[b.outcome] if n == 1 else (n * 5 + int(b.slot)) % Occult.RUNES.size()
			_rune_stone(a, ci, p.floor(), rune, col if (u >= 1.0 and n == 1) else Color("d8b04a"), 1.0 if n == 1 or not spinning else 0.7)
		if not spinning:
			var lift := minf(1.0, (b.t - b.spin) * 6.0)
			ci.draw_circle(at, 9.0, Color(col.r, col.g, col.b, 0.25 * lift))
			PixelFont.draw_centered(ci, text, at.x, at.y - 22, 1, col, dark)


## The team bet: the bettor's fate card shuffles face down, then turns face up with its name and what it does
## (Gamble.TEAM_OUTCOMES). A fate with neither a painted card nor a code emblem shows the back face up with its
## title on a plate, a plain stand-in.
static func _draw_fate(a: Arena, ci: CanvasItem, b: Dictionary, spinning: bool, col: Color, text: String, dark: Color) -> void:
	var r := Rect2(240 - 34, 40, 68, 90)
	ci.draw_rect(Rect2(0, 34, 480, 142), Color(0.02, 0.0, 0.05, 0.55))
	PixelFont.draw_centered(ci, "P%d DRAWS FOR ALL" % (int(b.slot) + 1), 240, r.end.y + 33, 1, G.player_color(b.slot), dark)
	if spinning:
		var k: float = b.t / b.spin
		var turn := absf(cos(b.t * (6.0 + 10.0 * (1.0 - k))))
		var w := r.size.x * turn
		TarotArt.draw_back(ci, Rect2(240 - w / 2.0, r.position.y, w, r.size.y))
		return
	var key: String = Gamble.fate_card(b.outcome)
	var title: String = TarotArt.ARCANA[key][1]
	if TarotArt._painting(key).is_empty() and not TarotArt.EMBLEMS.has(key):
		_fate_stand_in(ci, r, title)
	else:
		TarotArt.draw_card(ci, r, key, title, "", "", true, col, a.time)
	PixelFont.draw_centered(ci, text, 240, r.end.y + 5, 2, col, dark)
	PixelFont.draw_centered(ci, Gamble.fate_text(b.outcome, Tuning.shared()), 240, r.end.y + 22, 1, Color("d8cff0"), dark)


## A fate card nobody has painted yet: the back turned face up in a card's frame, the title on a dark plate over
## its lower part (as a painted card carries it).
static func _fate_stand_in(ci: CanvasItem, r: Rect2, title: String) -> void:
	ci.draw_rect(r.grow(1), TarotArt.INK)
	ci.draw_rect(r, TarotArt.CARD)
	var inner := r.grow(-4)
	ci.draw_rect(inner, Color("120a22"))
	TarotArt.draw_back(ci, inner)
	ci.draw_rect(r.grow(-2), TarotArt.GOLD_DIM, false, 1.0)
	var lines := TarotArt._lines(title, inner.size.x - 4.0)
	var plate := Rect2(inner.position.x, inner.end.y - 4 - lines.size() * 10.0, inner.size.x, lines.size() * 10.0 + 4)
	ci.draw_rect(plate, Color(TarotArt.INK, 0.86))
	ci.draw_rect(Rect2(plate.position, Vector2(plate.size.x, 1)), TarotArt.GOLD_DIM)
	var y := plate.position.y + 3
	for line: String in lines:
		PixelFont.draw_centered(ci, line, r.get_center().x, y, 1, Color.WHITE, TarotArt.INK)
		y += 10.0


## The music once a fate reel stops: the boss's while he is on the field, else the act's (bug N10: a bet during
## a boss fight used to switch the boss music off).
static func _after_reel_music(boss_f: float, act_music: String) -> String:
	return "music_boss" if boss_f > 0.0 else act_music


## A chest item's picture on its reveal box, px (the box is 19 tall).
const LOOT_ICON := 16


## Chest reels over the wizard who opened them: tier names spin, then the item shows in its tier's colour.
static func _draw_reveals(a: Arena, ci: CanvasItem, dark: Color) -> void:
	for r: Dictionary in a._reveals:
		var at: Vector2 = a._on_screen(r.pos as Vector2) + Vector2(0, -34)
		var spinning: bool = r.t < a.REEL_SPIN
		var tier: int = (int(r.t * 14.0) + r.slot) % a.RARITY_COLORS.size() if spinning else r.tier
		var col: Color = a.RARITY_COLORS[tier]
		if tier == Loot.ULTRA and not spinning:
			col = col.lerp(Color.WHITE, 0.5 + 0.5 * sin(a.time * 12.0))
		var label: String = Loot.RARITY_NAMES[tier]
		var title: String = "?????" if spinning else Loot.item_name(r.item)
		# The item's own picture (`icons/loot_<key>`) sits at the left of the box once the reel has stopped.
		var mark: Texture2D = null if spinning else Still.icon(Still.loot_icon(int(r.item)), LOOT_ICON)
		var pad: float = LOOT_ICON + 3.0 if mark != null else 0.0
		var w: float = maxf(PixelFont.text_width(label, 1), PixelFont.text_width(title, 1)) + 8.0 + pad
		var box := Rect2((at - Vector2(w / 2.0, 9)).floor(), Vector2(w, 19))
		ci.draw_rect(box, Color(0.04, 0.0, 0.1, 0.85))
		ci.draw_rect(box, col, false, 1.0)
		if mark != null:
			ci.draw_texture(mark, box.position + Vector2(2, 1))
		var tx: float = at.x + pad / 2.0
		PixelFont.draw_centered(ci, label, tx, box.position.y + 2, 1, col, dark)
		PixelFont.draw_centered(ci, title, tx, box.position.y + 11, 1, Color.WHITE if spinning else col, dark)


## Shows a banner now, or after the one on screen when `wait` is set.
static func _banner(a: Arena, text: String, sub: String, color: Color, dur: float, wait: bool = false) -> void:
	var b := {"text": text, "sub": sub, "t": dur, "max": dur, "color": color, "act": ""}
	if wait and (a.banner.t > 0.0 or not a._banner_queue.is_empty()):
		a._banner_queue.append(b)
	else:
		a.banner = b


## The card that opens an act: ACT II, its name and subtitle, with a gong.
static func _act_card(a: Arena, n: int) -> void:
	var b := {"text": Lore.act_name(n), "sub": Lore.act_subtitle(n), "t": 3.4, "max": 3.4,
		"color": [Color("8bdcff"), Color("ff8a2a"), Color("ffd94d")][clampi(n, 0, 2)], "act": Lore.act_heading(n)}
	a._banner_queue.clear()
	a.banner = b
	Sfx.play("gong")


## Fades the backdrop to the act the run minute is in.
static func _update_act(a: Arena, dt: float) -> void:
	var want := Lore.act_of(a.wave - 1)
	if want != a.act and a._act_fade < 0.0:
		a._prev_act = a.act
		a.act = want
		a.bg_next.texture = ArenaBg.build(a.act)
		a.bg_next.modulate.a = 0.0
		a.bg_next.visible = true
		a._act_fade = 0.0
		a.screen_flash = Color(1.0, 0.9, 0.7, 0.5)
	# Each act has its own air: dust in the Ossuary, embers in the Library, falling starlight in the Sanctum.
	var ar := G.ARENA
	if a._fx_rng.randf() < dt * [3.0, 14.0, 9.0][a.act]:
		match a.act:
			0:
				a.fx.spawn(Vector2(a._fx_rng.randf_range(ar.position.x, ar.end.x), a._fx_rng.randf_range(ar.position.y, ar.end.y)),
					Vector2(a._fx_rng.randf_range(-3, 3), a._fx_rng.randf_range(-4, -1)), 4.0, 1.0, Color(0.8, 0.75, 0.9, 0.25),
					Color(0.8, 0.75, 0.9, 0.0), false, 0.0)
			1:
				var c := Color("ff8a2a") if a._fx_rng.randf() < 0.7 else Color("ffd94d")
				a.fx.spawn(Vector2(a._fx_rng.randf_range(ar.position.x, ar.end.x), ar.end.y - a._fx_rng.randf_range(0, 30)),
					Vector2(a._fx_rng.randf_range(-8, 8), a._fx_rng.randf_range(-30, -14)), a._fx_rng.randf_range(2.0, 4.0), 1.0, c,
					Color(c.r, 0.1, 0.0, 0.0), true, 0.0)
			2:
				var c := Color("9ad8ff") if a._fx_rng.randf() < 0.6 else Color("ffd94d")
				a.fx.spawn(Vector2(a._fx_rng.randf_range(ar.position.x, ar.end.x), ar.position.y),
					Vector2(a._fx_rng.randf_range(-4, 4), a._fx_rng.randf_range(12, 26)), a._fx_rng.randf_range(3.0, 6.0), 1.0, c,
					Color(c.r, c.g, c.b, 0.0), true, 0.0)
	if a._act_fade >= 0.0:
		a._act_fade += dt
		a.bg_next.modulate.a = clampf(a._act_fade / 2.0, 0.0, 1.0)
		if a._act_fade >= 2.0:
			a.bg.texture = a.bg_next.texture
			a.bg_next.visible = false
			a._act_fade = -1.0


## An act card: a rune-framed band with the act's numeral, its name in large letters and its subtitle, fading in.
static func _draw_act_card(a: Arena, ci: CanvasItem, k: float, slide: float) -> void:
	var alpha := clampf(k / 0.12, 0.0, 1.0) * clampf(a.banner.t / 0.4, 0.0, 1.0)
	var col: Color = a.banner.color
	var band := Rect2(40, 82, 400, 66)
	ci.draw_rect(Rect2(0, band.position.y - 6, 480, band.size.y + 12), Color(0.02, 0.0, 0.05, 0.55 * alpha))
	if alpha < 0.99:
		return
	Occult.frame(ci, band, a.time)
	PixelFont.draw_centered(ci, a.banner.act, 240, band.position.y + 8, 1, Color(col, 0.9), Occult.INK)
	var tw := PixelFont.text_width(a.banner.text, 3)
	PixelFont.draw_gradient(ci, a.banner.text, Vector2(240 - tw / 2.0 + slide * 0.0, band.position.y + 22), 3,
		Color.WHITE, col, a.time * 3.0, 1.0)
	PixelFont.draw_centered(ci, a.banner.sub, 240, band.position.y + 50, 1, Color("fff6e0"), Occult.INK)
	Occult.candle(ci, Vector2(band.position.x + 14, band.end.y - 4), a.time, 0.0, 9)
	Occult.candle(ci, Vector2(band.end.x - 14, band.end.y - 4), a.time, 3.0, 9)


## A boss arrives: his picture and name slide in at the right edge for ARRIVE_SECS, then out. Play never waits.
static func _arrival(a: Arena, group: String, key: String, who: String, color: Color) -> void:
	_arrive = {"group": group, "key": key, "name": who, "color": color, "t0": a.time}


## Where the arrival's panel is right now (name plate and picture), or an empty rect when none shows.
static func _arrival_rect(a: Arena) -> Rect2:
	if _arrive.is_empty():
		return Rect2()
	var k: float = a.time - float(_arrive.t0)
	if k < 0.0 or k > ARRIVE_SECS or not Art.has(_arrive.group, _arrive.key):
		return Rect2()
	var slide := 1.0
	if k < ARRIVE_SLIDE:
		slide = k / ARRIVE_SLIDE
	elif k > ARRIVE_SECS - ARRIVE_SLIDE:
		slide = (ARRIVE_SECS - k) / ARRIVE_SLIDE
	slide = 1.0 - pow(1.0 - clampf(slide, 0.0, 1.0), 3.0)
	var size := Vector2(ARRIVE_PIC.x + 2, ARRIVE_PIC.y + 2)
	return Rect2(Vector2(lerpf(480.0, 480.0 - size.x - 1.0, slide), ARRIVE_Y), size)


static func _draw_arrival(a: Arena, ci: CanvasItem, dark: Color) -> void:
	if not _arrive.is_empty() and a.banner.t > 0.0 and a.banner.act != "":
		_arrive.t0 = a.time # the act card is up: the picture waits for it to end
		return
	var box := _arrival_rect(a)
	if box.size.x <= 0.0:
		return
	var col: Color = _arrive.color
	var pic := Rect2(box.position + Vector2(1, 1), Vector2(ARRIVE_PIC))
	ci.draw_rect(box, col)
	ci.draw_rect(box.grow(-1), dark)
	Art.draw(ci, _arrive.group, _arrive.key, pic)
	ci.draw_rect(pic.grow(1), col, false, 1.0)

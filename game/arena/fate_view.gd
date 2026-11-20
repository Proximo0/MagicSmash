class_name ArenaFateView
extends RefCounted
## Arena: clock, chest and card reveals, shrines, bets and fate cards, banners and the act card.
## Static helpers: `a` is the Arena that owns the state.

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


## The monster card a wizard just found: it flips in at the middle of the screen with its name and bonus.
static func _draw_card_reveal(a: Arena, ci: CanvasItem, dark: Color) -> void:
	if a._cards.is_empty():
		return
	var c: Dictionary = a._cards[0]
	var t: float = c.t
	var fade := clampf(minf(t * 4.0, (a.CARD_SHOW - t) * 3.0), 0.0, 1.0)
	ci.draw_rect(Rect2(0, 0, 480, 270), Color(0.02, 0.0, 0.06, 0.55 * fade))
	# The back shows, narrows to an edge, then the face widens out: a card turning over.
	var flip := clampf(t / 0.6, 0.0, 1.0)
	var w := 76.0 * absf(1.0 - flip * 2.0)
	var h := 112.0
	var center := Vector2(240, 128 - (1.0 - fade) * 10.0)
	var r := Rect2((center - Vector2(w / 2.0, h / 2.0)).floor(), Vector2(maxf(floorf(w), 1.0), h))
	if flip < 0.5:
		TarotArt.draw_back(ci, r)
	else:
		for i: int in range(12):
			var ang := a.time * 0.6 + i * TAU / 12.0
			ci.draw_line(center, center + Vector2.from_angle(ang) * 90.0, Color(1.0, 0.3, 0.95, 0.10 * fade), 3.0)
		MonsterCard.draw(ci, r, c.idx, true, a.time, 1.0)
	var col := Color("ff4df2").lerp(Color.WHITE, 0.5 + 0.5 * sin(a.time * 10.0))
	PixelFont.draw_centered(ci, "ULTRA RARE CARD", 240, r.position.y - 22, 2, Color(col, fade), dark)
	var who := "P%d DREW %s" % [int(c.slot) + 1, Cards.card_name(c.idx)]
	PixelFont.draw_centered(ci, who, 240, r.end.y + 6, 1, Color(Color("ffd94d"), fade), dark)
	var sub := "NEW TO YOUR COLLECTION" if c.first else "SOCKET IT IN THE SANCTUM"
	PixelFont.draw_centered(ci, sub, 240, r.end.y + 16, 1, Color(Color("c9b8ff"), fade), dark)


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
		var charge: float = r[4]
		if charge > 0.0:
			ci.draw_arc(at, 16.0 * big, -PI / 2.0, -PI / 2.0 + TAU * clampf(charge, 0.0, 1.0), 32, Color.WHITE, 2.0)
		PixelFont.draw_centered(ci, "%dG" % int(r[5]), at.x, at.y - (32.0 if kind == Gamble.SOLO else 50.0), 1, col, dark)


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
		if b.t < b.spin and int(b.t * rate) != int(prev * rate):
			Sfx.play("menu_move", -8.0 if b.kind == Gamble.TEAM else -12.0, 0.9 + b.t / b.spin * 0.5)
		if not b.shown and b.t >= b.spin:
			b.shown = true
	a._bets = a._bets.filter(func(b: Dictionary) -> bool: return b.t < b.spin + a.REEL_SHOW)


## Altar casts: a solo cast throws three rune stones over the altar and the middle one lands on the outcome's
## rune; the team bet turns a fate card in the middle of the screen, The Sun or Death.
static func _draw_bets(a: Arena, ci: CanvasItem, dark: Color) -> void:
	for b: Dictionary in a._bets:
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


## The team bet: the bettor's fate card shuffles between The Sun and Death, then turns face up.
static func _draw_fate(a: Arena, ci: CanvasItem, b: Dictionary, spinning: bool, col: Color, text: String, dark: Color) -> void:
	var r := Rect2(240 - 34, 40, 68, 90)
	ci.draw_rect(Rect2(0, 34, 480, 132), Color(0.02, 0.0, 0.05, 0.55))
	PixelFont.draw_centered(ci, "P%d DRAWS FOR ALL" % (int(b.slot) + 1), 240, r.position.y - 2 + 112, 1, G.player_color(b.slot), dark)
	if spinning:
		var k: float = b.t / b.spin
		var turn := absf(cos(b.t * (6.0 + 10.0 * (1.0 - k))))
		var w := r.size.x * turn
		TarotArt.draw_back(ci, Rect2(240 - w / 2.0, r.position.y, w, r.size.y))
		return
	var key: String = a.FATE_CARDS[b.outcome]
	var title: String = TarotArt.ARCANA[key][1]
	TarotArt.draw_card(ci, r, key, title, "", "", true, col, a.time)
	PixelFont.draw_centered(ci, text, 240, r.end.y + 16, 2, col, dark)


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
		var w: float = maxf(PixelFont.text_width(label, 1), PixelFont.text_width(title, 1)) + 8.0
		var box := Rect2((at - Vector2(w / 2.0, 9)).floor(), Vector2(w, 19))
		ci.draw_rect(box, Color(0.04, 0.0, 0.1, 0.85))
		ci.draw_rect(box, col, false, 1.0)
		PixelFont.draw_centered(ci, label, at.x, box.position.y + 2, 1, col, dark)
		PixelFont.draw_centered(ci, title, at.x, box.position.y + 11, 1, Color.WHITE if spinning else col, dark)


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

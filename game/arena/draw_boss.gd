class_name ArenaDrawBoss
extends RefCounted
## Arena: the boss on screen beyond its sprite. The bar at the foot of the screen with the boss's name, the Ghost
## Writer's spelled word over her (the letters shown so far, NAME in the named wizards' colours, GOODBYE's meter)
## with a mark over each named wizard, and the act bosses' stand-in poses: a raised sprite over a small shadow while
## aloft, a tint and a wobble for grounded, wheel, dizzy and staggered. Real art replaces the poses later
## (docs/art_dropin.md). Static helpers: `a` is the Arena that owns the state.

const CYAN := Color("4dfff0")
const PINK := Color("ff4df2")
const BONE := Color("e8dcc0")
const RED := Color("ff4d6a")
const GOLD := Color("ffd94d")
## Each boss's bar: [name, rim colour], by Bestiary type.
const BARS: Dictionary = {
	Bestiary.CHANDELIER: ["THE BONE CHANDELIER", Color("ffb84d")],
	Bestiary.GHOSTWRITER: ["THE GHOST WRITER", Color("b9a6ff")],
}
## Banners and arrival pictures: [title, sub, colour, picture group, picture key], by Bestiary type.
const ARRIVALS: Dictionary = {
	Bestiary.CHANDELIER: ["THE BONE CHANDELIER", "THE OSSUARY'S CROWN DESCENDS", Color("ffb84d"), "portraits/characters", "bone_chandelier"],
	Bestiary.GHOSTWRITER: ["THE GHOST WRITER", "SHE SPELLS YOUR END", Color("b9a6ff"), "portraits/characters", "ghost_writer"],
}
## Aloft: how high the sprite hangs over its body, px, and the alpha over a wizard.
const ALOFT_LIFT := 24.0
const ALOFT_OVER := 0.6
const WORD_SCALE := 2
## The type of the last boss the header showed (its death banner reads it once the header has cleared).
static var last_type := -1


static func boss_type(a: Arena) -> int:
	return int(a.vw[World.W_BOSS_TYPE]) if a.vw.size() > World.W_BOSS_METER else -1


static func boss_name(a: Arena, type: int) -> String:
	if BARS.has(type):
		return BARS[type][0]
	return Lore.ARCHLICH_NAME if a.boss_final else Lore.LICH_NAME


static func boss_rim(a: Arena, type: int) -> Color:
	if BARS.has(type):
		return BARS[type][1]
	return PINK if a.boss_final else CYAN


## The boss bar: its name between runes, a sigil at each end, the health with a notch where it turns.
static func bar(a: Arena, ci: CanvasItem, dark: Color) -> void:
	if a.boss_f <= 0.0:
		return
	var type := boss_type(a)
	if type >= 0:
		last_type = type
	var label := boss_name(a, type)
	var rim := boss_rim(a, type)
	var bw := 300.0
	var bx := 240 - bw / 2
	PixelFont.draw_centered(ci, label, 240, 249, 1, rim, dark)
	ci.draw_rect(Rect2(bx - 3, 257, bw + 6, 10), dark)
	ci.draw_rect(Rect2(bx - 2, 258, bw + 4, 1), rim)
	ci.draw_rect(Rect2(bx - 2, 265, bw + 4, 1), rim)
	ci.draw_rect(Rect2(bx, 260, bw, 4), Color("2c0d4d"))
	# A sigil at each end and runes either side of the name: Morvane's seal on his bar.
	Occult.sigil(ci, Vector2(bx - 8, 262), 5.0, a.time)
	Occult.sigil(ci, Vector2(bx + bw + 8, 262), 5.0, a.time)
	var nw := PixelFont.text_width(label, 1)
	for k in 3:
		var glow := Color(rim, 0.55 + 0.45 * maxf(0.0, sin(a.time * 3.0 - k)))
		Occult.rune(ci, Vector2(240 - nw / 2.0 - 12 - k * 7, 249), k + 2, glow)
		Occult.rune(ci, Vector2(240 + nw / 2.0 + 8 + k * 7, 249), k + 5, glow)
	ci.draw_rect(Rect2(bx, 260, bw * a.boss_f, 4), CYAN if a.boss_f > 0.5 else RED)
	ci.draw_rect(Rect2(bx, 260, bw * a.boss_f, 1), Color.WHITE)
	if BARS.has(type):
		ci.draw_rect(Rect2(bx + bw * Bosses.PHASE_AT, 258, 1, 8), BONE)


## The spelled word over the Ghost Writer, large: the letters so far bright, the rest as dim dots; a NAME in the
## named wizards' colours with a pulsing mark over each of them; under GOODBYE, the meter of the share to deal.
static func word(a: Arena, ci: CanvasItem, dark: Color) -> void:
	var type := boss_type(a)
	if type != Bestiary.GHOSTWRITER and not (type == Bestiary.LICH and a.boss_final):
		return
	var arg := int(a.vw[World.W_BOSS_ARG])
	if BossGhostwriter.word_of(arg) == BossGhostwriter.WORD_NONE:
		return
	var boss := _boss_view(a, type)
	if boss.is_empty():
		return
	var names := {}
	for s: int in a.vp:
		names[s] = Wizards.wizard_name(int(G.slot_wizard.get(s, s)))
	var text := BossGhostwriter.word_text(arg, names)
	var shown := clampi(int(a.vw[World.W_BOSS_T]), 0, text.length())
	var slots := BossGhostwriter.named(arg)
	var col := GOLD
	if slots.size() == 1:
		col = G.player_color(slots[0])
	elif slots.size() > 1:
		col = Color.WHITE
	var tw := PixelFont.text_width(text, WORD_SCALE)
	var at: Vector2 = a._on_screen(boss.pos) + Vector2(0, -44)
	at.x = clampf(at.x, tw / 2.0 + 4.0, G.SCREEN.x - tw / 2.0 - 4.0)
	at.y = clampf(at.y, G.HUD_H + 4.0, G.SCREEN.y - 50.0)
	var x := at.x - tw / 2.0
	ci.draw_rect(Rect2(x - 3, at.y - 3, tw + 6, 7 * WORD_SCALE + 6), Color(dark, 0.7))
	var part := 0
	for i: int in text.length():
		var ch := text[i]
		if ch == BossGhostwriter.NAME_JOIN:
			part += 1
		var c := col if slots.size() <= 1 else G.player_color(slots[mini(part, slots.size() - 1)])
		if i < shown:
			PixelFont.draw(ci, ch, Vector2(x, at.y), WORD_SCALE, c, dark)
		else:
			ci.draw_rect(Rect2(x + 2, at.y + 5 * WORD_SCALE, 4, 2), Color(c, 0.35))
		x += PixelFont.text_width(ch, WORD_SCALE) + WORD_SCALE
	if BossGhostwriter.word_of(arg) == BossGhostwriter.WORD_GOODBYE:
		var m := clampf(a.vw[World.W_BOSS_METER], 0.0, 1.0)
		var r := Rect2(at.x - 30, at.y + 7 * WORD_SCALE + 5, 60, 4)
		ci.draw_rect(r.grow(2), dark)
		ci.draw_rect(r.grow(1), GOLD, false, 1.0)
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x * m, r.size.y)), GOLD if m < 1.0 else Color.WHITE)
		PixelFont.draw(ci, "HIT HER", Vector2(r.end.x + 5, r.position.y - 2), 1, GOLD, dark)
	for s: int in slots:
		if a.vp.has(s) and a.vp[s].alive:
			var over: Vector2 = a._on_screen(a.vp[s].pos) + Vector2(0, -30 - 2.0 * sin(a.time * 10.0))
			var pc := G.player_color(s)
			ci.draw_colored_polygon(PackedVector2Array([over + Vector2(-5, -4), over + Vector2(5, -4), over + Vector2(0, 3)]), pc)
			ci.draw_polyline(PackedVector2Array([over + Vector2(-5, -4), over + Vector2(5, -4), over + Vector2(0, 3), over + Vector2(-5, -4)]), dark, 1.0)


static func _boss_view(a: Arena, type: int) -> Dictionary:
	for e: Dictionary in a.ve.values():
		if int(e.type) == type:
			return e
	return {}


## The shadow under an act boss: small and faint while aloft, its body's width on the floor.
static func shadow(a: Arena, ci: CanvasItem, e: Dictionary) -> void:
	if int(e.type) == Bestiary.CHANDELIER:
		var up := BossChandelier.is_aloft(int(e.state))
		ArenaDrawWorld._shadow(a, ci, e.pos + Vector2(0, 2), 22.0 if up else 40.0)
	else:
		ArenaDrawWorld._shadow(a, ci, e.pos + Vector2(0, 2), 20.0)


## An act boss's stand-in pose: [offset of the sprite's feet, tint]. Aloft: raised ALOFT_LIFT and see-through over
## a wizard; grounded: dark bone; the wheel: warm, shaking while it squashes before a leg; dizzy or staggered:
## wobbling, flashing gold; turning a phase: flashing white.
static func pose(a: Arena, e: Dictionary) -> Array:
	var st := int(e.state)
	var off := Vector2.ZERO
	var tint := Color.WHITE
	if int(e.get("status", 0)) & World.STATUS_TURN:
		tint = Color(1.6, 1.6, 1.6) if int(a.time * 12.0) % 2 == 0 else Color.WHITE
	if int(e.type) == Bestiary.CHANDELIER:
		if BossChandelier.is_aloft(st):
			off.y = -ALOFT_LIFT + roundf(sin(a.time * 2.0) * 1.5)
			for p: Dictionary in a.vp.values():
				if p.alive and (p.pos as Vector2).distance_to(e.pos) < 20.0:
					tint.a = ALOFT_OVER
		elif BossChandelier.is_down(st) and st != BossChandelier.DIZZY:
			tint = tint * Color(0.7, 0.65, 0.6)
		else:
			tint = tint * Color(1.25, 0.9, 0.6)
		match st:
			BossChandelier.ROLL_WARN:
				off.x += float(int(a.time * 30.0) % 2) * 2.0 - 1.0
			BossChandelier.DIZZY:
				off.x += roundf(sin(a.time * 9.0) * 2.0)
				tint = tint * (Color(1.4, 1.3, 0.5) if int(a.time * 6.0) % 2 == 0 else Color.WHITE)
			BossChandelier.DROP_LOCK, BossChandelier.HOP_LOCK:
				off.x += float(int(a.time * 24.0) % 2)
	else:
		off.y = -4.0 + roundf(sin(a.time * 3.0) * 1.5)
		match st:
			BossGhostwriter.SPELL:
				tint = tint * Color(1.1, 1.0, 1.3)
			BossGhostwriter.RUN:
				tint = tint * Color(1.5, 0.8, 0.6)
			BossGhostwriter.BYE:
				tint = tint * Color(1.3, 0.8, 1.3)
				off.x += float(int(a.time * 20.0) % 2)
			BossGhostwriter.STAGGER:
				off.x += roundf(sin(a.time * 9.0) * 2.0)
				tint = tint * (Color(1.4, 1.3, 0.5) if int(a.time * 6.0) % 2 == 0 else Color.WHITE)
	return [off, tint]


## The arrival banner and picture of an act boss (EV_BOSS carries its type); false for the Lich (its minute's banner
## announced it).
static func arrive(a: Arena, type: int) -> bool:
	if not ARRIVALS.has(type):
		return false
	var r: Array = ARRIVALS[type]
	ArenaFateView._banner(a, r[0], r[1], r[2], 2.6, true)
	ArenaFateView._arrival(a, r[3], r[4], r[0], r[2])
	return true


## Whether these events make a boss final (the Archlich arrives as a Lich and ascends in the same step: its banner
## came with the final minute).
static func made_final(evs: Array) -> bool:
	for ev: Array in evs:
		if int(ev[0]) == World.EV_BOSS and int(ev[3]) == 1:
			return true
	return false


## The death banner's title for the boss that just died.
static func slain_title(final: bool) -> String:
	if final:
		return "ARCHLICH DESTROYED!"
	if BARS.has(last_type):
		return String(BARS[last_type][0]) + " FALLS!"
	return "LICH LORD DESTROYED!"

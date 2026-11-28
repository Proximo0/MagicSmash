class_name ArenaEvents
extends RefCounted
## Arena: turns the tick's events into sound, particles, banners and reels.
## Static helpers: `a` is the Arena that owns the state.

const HURT_PITCH := [1.0, 1.15, 0.87, 1.3] ## the hurt sound by seat: a table hears who was hit
## The scorch a plain FIREBALL's blast (Spells.STATS "blast") leaves on the floor, px; a blast THE EMPRESS widens
## leaves one as much wider (EV_EXPLODE carries the radius the World used).
const BLAST_SCORCH := 10.0

static func _handle_events(a: Arena, evs: Array) -> void:
	for ev in evs:
		var pos := Vector2(ev[1], ev[2])
		match int(ev[0]):
			World.EV_CAST:
				var sp := int(ev[3])
				var col := ArenaDrawFx._spell_color(a, sp, int(ev[4]))
				a.fx.cast_flash(pos, col, int(ev[4]))
				match sp:
					World.SP_ARCANE: Sfx.play("shoot_arcane", -6.0, 1.0, 0.06)
					World.SP_FIRE: Sfx.play("shoot_fire", -3.0, 1.0, 0.08)
					World.SP_FROST: Sfx.play("shoot_frost", -5.0, 1.0, 0.08)
					World.SP_STAR: Sfx.play("star", -6.0, 1.0, 0.08)
					World.SP_RUNE: Sfx.play("rune_cast", -5.0, a._fx_rng.randf_range(0.95, 1.1), 0.12)
					World.SP_BONE: Sfx.play("arrow", -5.0, a._fx_rng.randf_range(0.9, 1.05), 0.08)
					World.SP_CANDLE: Sfx.play("candle", -6.0, a._fx_rng.randf_range(0.95, 1.1), 0.12)
					World.SP_CLEAVE: Sfx.play("hit", -3.0, 0.7, 0.08)
			World.EV_SWEEP: # a CLEAVE: a steel arc flash toward the swing; WHIRLWIND (+8): the same flash all the way round
				# ev[3]: the arc's middle angle, its reach and half its width as the World swung it (THE EMPRESS and THE
				# STAR widen them: WorldCastSweep); id 2 flashes as id 1 until a later job gives it a look.
				var slot := int(ev[4]) & Spells.EVO_SLOT_MASK
				var sw: Vector3 = ev[3]
				a.fx.swing(pos, sw.y, sw.x, sw.z, ArenaDrawFx._spell_color(a, World.SP_CLEAVE, slot))
			World.EV_BURST: # a JUSTICE burst: a pale ring the size of its reach and bone shards
				var br := float(ev[3])
				a.fx.ring(pos, br * 0.3, br, 0.25, Color("fff6e0"), 2.0)
				a.fx.burst(pos, 8, 70.0, 0.35, 1.0, Color.WHITE, Color("ffd94d"), true)
				Sfx.play("explode", -9.0, 1.4, 0.08)
			World.EV_RUNE:
				# ev[4]: the caster's slot, + Spells.evo_bits(id), +16 x the circle's kind (a candle lights quietly).
				# Id 2 rings and sounds as id 1 until a later job gives it a look of its own.
				var evo := Spells.bits_evo(int(ev[4])) > 0
				if int(ev[4]) >> 4 == Spells.CIRCLE_CANDLE:
					a.fx.ring(pos, float(ev[3]) * 0.4, float(ev[3]), 0.3, ArenaDrawFx._spell_color(a, World.SP_CANDLE, 0), 1.0)
				else:
					var rc := ArenaDrawFx._spell_color(a, World.SP_RUNE, 0)
					a.fx.ring(pos, float(ev[3]) * 0.4, float(ev[3]), 0.3, a.SEAL_WHITE if evo else rc, 1.0)
					a.fx.burst(pos, 8, 40.0, 0.5, 1.0, a.RUNE_GOLD, rc, true, -30.0)
					if evo:
						Sfx.play("portal", -9.0, 1.4, 0.25)
			World.EV_HIT:
				a.fx.hit_spark(pos, Color(1, 1, 1) if int(ev[4]) < 0 else G.player_fx(int(ev[4])))
				Sfx.play("hit", -8.0, a._fx_rng.randf_range(0.9, 1.2), 0.04)
			World.EV_DIE:
				var t := int(ev[3])
				a.fx.death(pos, t)
				Sfx.play("enemy_die", -2.0, a._fx_rng.randf_range(0.85, 1.15), 0.04)
				a._add_shake(1.5 if t != World.ORC else 3.0)
				var gc := [Color("2f7a2a"), Color("b7a98e"), Color("158f86"), Color("158f86"), Color("5a1a8a"), Color("4d5166"), Color("3b1f6e"), Color("4a1a7a"), Color("4f9a94"), Color("4e0f18"), Color("57546a"), Color("2e1a12")]
				if t == World.TOME:
					a.fx.burst(pos + Vector2(0, -6), 10, 70.0, 0.7, 1.5, Color("efe2c0"), Color("8a1f2c"), false, 60.0)
					Sfx.play("page_turn", -4.0, a._fx_rng.randf_range(0.9, 1.2), 0.1)
				elif t == World.WRAITH:
					Sfx.play("ghost", -8.0, a._fx_rng.randf_range(0.9, 1.3), 0.15)
				a._decal(pos + Vector2(0, 4), gc[clampi(t, 0, gc.size() - 1)], 4.0 if t != World.ORC else 7.0)
			World.EV_EXPLODE: # ev[3]: the blast's radius as the World hit with it (THE EMPRESS widens it)
				a.fx.explosion(pos, float(ev[3]))
				Sfx.play("explode", -2.0, a._fx_rng.randf_range(0.9, 1.1), 0.05)
				a._add_shake(3.0)
				a._decal(pos, Color("1a1020"), BLAST_SCORCH * float(ev[3]) / Spells.stat(World.SP_FIRE, "blast"))
			World.EV_ZAP:
				var pts: PackedVector2Array = ev[3]
				a.fx.bolt(pts, a.SPELL_COLORS[World.SP_STORM])
				for pt in pts:
					a.fx.burst(pt, 3, 60.0, 0.2, 1.0, Color.WHITE, Color("ffe84d"), true)
				Sfx.play("zap", -5.0, a._fx_rng.randf_range(0.9, 1.15), 0.07)
			World.EV_NOVA:
				var col := G.player_fx(int(ev[3]))
				a.fx.nova(pos, col)
				Sfx.play("nova", 0.0, 1.0, 0.1)
				a._add_shake(9.0)
				a.screen_flash = Color(col.r, col.g, col.b, 0.55)
				a._do_hitstop(0.08)
			World.EV_PICKUP:
				var k := int(ev[3])
				if k == World.PK_XP:
					Sfx.play("coin", -14.0, 1.5, 0.05)
					continue
				a.fx.sparkle(pos, ArenaDrawFx._pickup_color(a, k))
				match k:
					World.PK_COIN: Sfx.play("coin", -4.0)
					World.PK_GEM: Sfx.play("pickup", -3.0)
					World.PK_POTION: Sfx.play("heal")
					_: Sfx.play("powerup")
				# A tome says what it is by its colour and its spell: only the other pickups write their name.
				if a.PICKUP_NAMES[k] != "" and k not in World.TOMES:
					a.fx.text(pos + Vector2(0, -12), a.PICKUP_NAMES[k], ArenaDrawFx._pickup_color(a, k), 1.4)
			World.EV_HURT:
				a.fx.burst(pos, 14, 110.0, 0.4, 2.0, Color.WHITE, Color("ff2a4a"), true)
				Sfx.play("hurt", 0.0, HURT_PITCH[posmod(int(ev[3]), HURT_PITCH.size())]) # four seats, four pitches
				a._add_shake(4.0)
				if a._is_local_slot(int(ev[3])):
					a.screen_flash = Color(1, 0.1, 0.2, 0.35)
					# The hurt that leaves one heart (hp is already this snapshot's, and a hurt only ever lowers it).
					if int(a.vp.get(int(ev[3]), {}).get("hp", 99)) == 1:
						Sfx.play("low_health", -2.0, 1.0, 1.5)
			World.EV_PDIE:
				var col := G.player_color(int(ev[3]))
				a.fx.nova(pos, col)
				a.fx.burst(pos, 40, 160.0, 0.9, 2.0, Color.WHITE, col, true, 60.0, true)
				Sfx.play("player_die")
				Sfx.play("ghost", -4.0, 0.9)
				var dead_slot := int(ev[3])
				a._ghosts.append([pos + Vector2(0, 6), 0.0, G.wizard_of(dead_slot)])
				a._add_shake(7.0)
				var left := int(ev[4])
				a.fx.text(pos + Vector2(0, -16), "P%d DOWN!" % (int(ev[3]) + 1) if left > 0 else "P%d IS OUT!" % (int(ev[3]) + 1), col, 1.8, 1)
			World.EV_DOWN:
				Sfx.play("down", -2.0, 1.0, 0.3)
			World.EV_REVIVE:
				Sfx.play("revive", -2.0, 1.0, 0.3)
			World.EV_PHASE:
				Sfx.play("boss_phase", -1.0, 1.0, 0.5)
			World.EV_FATE:
				Sfx.play("fate", -3.0, 1.0, 0.3)
			World.EV_REDRAW:
				Sfx.play("redraw", -4.0, 1.0, 0.15)
			World.EV_BANISH:
				Sfx.play("banish", -3.0, 1.0, 0.15)
			World.EV_CALL:
				ArenaDrawFallen.on_call(a, ev)
			World.EV_DOOR:
				Sfx.play("door", -6.0, 1.0, 0.2)
			World.EV_ESHOT:
				var k := int(ev[3])
				if k == World.ES_ARROW:
					Sfx.play("arrow", -8.0, 1.0, 0.08)
				else:
					Sfx.play("enemy_shot", -9.0, 1.0 if k == World.ES_ORB else 0.7, 0.1)
					a.fx.flash(pos, 6.0, Color("c0263a"), 0.08)
			World.EV_SPLIT:
				a.fx.burst(pos, 16, 80.0, 0.5, 2.0, Color("d8fff6"), Color("158f86"), false, 200.0)
				Sfx.play("slime")
			World.EV_TELE:
				a.fx.teleport(pos, Color("ff4df2") if int(ev[3]) == 0 else Color("4dfff0"))
				Sfx.play("teleport", -6.0, 1.0, 0.1)
			World.EV_CHARGE:
				a.fx.text(pos + Vector2(0, -8), "!", Color("ff3030"), 0.6, 2)
				Sfx.play("charge", -3.0)
			World.EV_WAVE:
				var w := int(ev[3])
				# World waves count from 1 (wave 1 is 0:00 to 1:00); Lore counts run minutes from 0.
				if Lore.opens_act(w - 1):
					ArenaFateView._act_card(a, Lore.act_of(w - 1))
				if int(ev[4]) == 2:
					ArenaFateView._banner(a, Lore.ARCHLICH_TITLE, Lore.ARCHLICH_NAME + " DESCENDS", Color("ff4df2"), 3.2, true)
					ArenaFateView._arrival(a, "portraits/characters", "archlich", Lore.ARCHLICH_TITLE, Color("ff4df2"))
					Sfx.play("boss_roar", 0.0, 0.7)
					Sfx.play("bell_toll", -2.0)
				elif int(ev[4]) == 1:
					# A boss minute: the boss's own banner comes with it (EV_BOSS).
					ArenaFateView._banner(a, "MINUTE %d" % w, Lore.minute_line(w - 1), Color("ffd94d"), 1.8)
					Sfx.play("portal")
				elif w > 1:
					ArenaFateView._banner(a, "MINUTE %d" % w, Lore.minute_line(w - 1), Color("ffd94d"), 1.8)
					Sfx.play("wave_start", -4.0)
				else:
					ArenaFateView._act_card(a, 0)
					Sfx.play("wave_start")
				if int(ev[4]) == 0 and a.boss_f <= 0.0:
					Sfx.music(ArenaFateView._act_music(a))
			World.EV_RIFT:
				# A shrinking ring and a dark core warn where the group will burst out.
				var life := float(ev[4])
				a.fx.ring(pos, float(ev[3]) + 10.0, 3.0, life, Color("c0263a"), 2.0)
				a.fx.ring(pos, float(ev[3]) + 4.0, 1.0, life, Color("7a1226"), 3.0)
				a.fx.sparkle(pos, Color("c0263a"), 8)
			World.EV_URN:
				for k: int in range(10):
					a.fx.spawn(pos + Vector2(0, -4), Vector2.from_angle(a._fx_rng.randf() * TAU) * a._fx_rng.randf_range(30.0, 80.0)
						+ Vector2(0, -30), 0.6, 1.5, Color("b0643a"), Color("7a3f22"), false, 1.0, 220.0)
				Sfx.play("hit", -4.0, 0.7)
				if int(ev[3]) >= World.URN_CHEST:
					a.fx.sparkle(pos, Color("ff8af0") if int(ev[3]) == World.URN_CARD_DROP else Color("8fe3ff"), 14)
					Sfx.play("powerup", -4.0, 1.3)
			World.EV_CARD:
				var cidx := int(ev[3])
				if int(ev[4]) >= 8 and Save.profile.find_secret("urn_card"):
					a.fx.text(pos + Vector2(0, -24), "SECRET FOUND", Color("8bdcff"), 2.0)
				var card_slot := int(ev[4]) % 8 # never written back: the same event goes on to the clients
				var first := Save.add_card(cidx)
				a._cards.append({"idx": cidx, "slot": card_slot, "t": 0.0, "first": first})
				a.fx.burst(pos, 30, 120.0, 0.9, 2.0, Color.WHITE, Color("ff4df2"), true)
				a.fx.ring(pos, 4.0, 60.0, 0.7, Color("ffd94d"), 2.0)
				Sfx.play("card_flip") # no shake: the notice under the HUD (ArenaFateView._draw_card_reveal) must not jolt the fight
				Sfx.play("wave_clear", -2.0, 1.4)
			World.EV_CHEST:
				var code := int(ev[4])
				a._reveals.append({"slot": int(ev[3]), "pos": pos, "item": code / 8, "tier": code % 8, "t": 0.0, "shown": false})
				Sfx.play("door", -6.0, 1.4)
			World.EV_SHRINE_UP:
				var sk := int(ev[3])
				a.fx.ring(pos, 2.0, 30.0, 0.6, a.SHRINE_COLORS[sk], 2.0)
				a.fx.sparkle(pos, a.SHRINE_COLORS[sk], 14)
				if sk == Gamble.TEAM:
					ArenaFateView._banner(a, "THE FATE CARD", "THE TABLE PAYS, ONE FATE FOR ALL", a.SHRINE_COLORS[sk], 2.4)
					Sfx.play("portal", -4.0)
				else:
					a.fx.text(pos + Vector2(0, -20), "RUNE ALTAR", a.SHRINE_COLORS[sk], 1.2, 1)
					Sfx.play("candle", -2.0)
			World.EV_SHRINE:
				var code := int(ev[4])
				var bk := code / 16
				var spin: float = Tuning.shared().team_reel if bk == Gamble.TEAM else Tuning.shared().shrine_reel
				# A team reel waits for the one on show to finish (t below 0 while it waits); a = slot, + 8 for a dealt card.
				var t0 := ArenaFateView._team_reel_start(a._bets, a.REEL_SHOW) if bk == Gamble.TEAM else 0.0
				a._bets.append({"slot": int(ev[3]) % 8, "pos": pos, "kind": bk, "outcome": code % 16, "t": t0, "spin": spin, "shown": false})
				Sfx.play("coin", -2.0, 0.8)
				if bk == Gamble.TEAM:
					Sfx.play("card_deal")
					Sfx.play("whisper", -2.0)
					Sfx.music("music_boss")
				else:
					Sfx.play("rune_cast")
			World.EV_GAMBLE:
				var code := int(ev[4])
				var gk := code / 16
				var good := Gamble.is_good(gk, code % 16)
				var col := Color("8bff9e") if good else Color("ff3b5c")
				if gk == Gamble.TEAM:
					for q: Dictionary in a.vp.values():
						a.fx.burst(q.pos + Vector2(0, -8), 24, 120.0, 0.8, 2.0, Color.WHITE, col, true, 40.0, true)
					a.screen_flash = Color(col.r, col.g, col.b, 0.35)
					a._add_shake(6.0 if good else 10.0)
					Sfx.play("gong")
					Sfx.play("shrine_result", 0.0, 1.0 if good else 0.75)
				else:
					a.fx.burst(pos, 16, 90.0, 0.6, 1.5, Color.WHITE, col, true)
					Sfx.play("rune_good" if good else "rune_bad", -2.0)
			World.EV_SKILL: # a class skill: its name over the hero, the nova's sound (art comes with the class art)
				a.fx.text(pos + Vector2(0, -10), Classes.skill_name(int(ev[4])) + "!", G.player_fx(int(ev[3])), 1.0, 1)
				Sfx.play("nova", -4.0, 1.2, 0.1)
			World.EV_HEAL:
				a.fx.text(pos + Vector2(0, -10), "+%d" % int(ev[4]), Color("8bff9e"), 0.8, 1)
				Sfx.play("powerup", -8.0, 1.3, 0.1)
			World.EV_WARD:
				a.fx.text(pos + Vector2(0, -10), "BLOCKED", Color("8bdcff"), 0.8, 1)
				a.fx.ring(pos, 4.0, 16.0, 0.3, Color("8bdcff"), 2.0)
				Sfx.play("orbit", -4.0, 1.3)
			World.EV_OMEN:
				var oi := int(ev[3])
				var rr := float(ev[4])
				ArenaFateView._banner(a, Lore.omen_name(oi), Lore.omen_subtitle(oi), Color("ff6a4d"), 2.2, true)
				Sfx.play("bell_toll", -3.0, 0.8)
				Sfx.play("whisper", -4.0)
				if rr > 0.0:
					# The ring the horde will rise on: it tightens onto its radius before they arrive.
					a.fx.ring(pos, rr + 40.0, rr, World.OMEN_WARN, Color("ff4d6a"), 2.0)
					a.fx.ring(pos, rr + 60.0, rr, World.OMEN_WARN * 0.8, Color("ffd23d"), 1.0)
				else:
					for d: Vector2 in World.DOORS:
						a.fx.flash(d, 24.0, Color("ff6a4d"), 0.6)
			World.EV_RAISE:
				a.fx.ring(pos, 4.0, 26.0, 0.5, Color("6dff9a"), 2.0)
				a.fx.burst(pos + Vector2(0, -4), 14, 60.0, 0.6, 1.5, Color("6dff9a"), Color("efe7d2"), true, -40.0)
				a.fx.text(pos + Vector2(0, -20), "RISE!", Color("6dff9a"), 0.8, 1)
				Sfx.play("portal", -6.0, 1.3, 0.2)
			World.EV_ELITE:
				var elite_name: String = a.ENEMY_NAMES[clampi(int(ev[3]), 0, a.ENEMY_NAMES.size() - 1)]
				a.fx.text(pos + Vector2(0, -20), "ELITE " + elite_name, Color("ffb84d"), 1.6, 1)
				a.fx.ring(pos, 2.0, 24.0, 0.5, Color("ffb84d"), 2.0)
				Sfx.play("charge", -2.0, 0.8)
			World.EV_BOSS:
				if int(ev[3]) == 0 and not ArenaDrawBoss.arrive(a, int(ev[4])) and not ArenaDrawBoss.made_final(evs):
					ArenaFateView._banner(a, "THE LICH LORD", Lore.LICH_NAME + " RISES", Color("ff4d6a"), 2.6, true)
					ArenaFateView._arrival(a, "cards/monsters", "lich", "THE LICH LORD", Color("ff4d6a"))
				Sfx.play("boss_roar", 0.0, 0.7 if int(ev[3]) == 1 else 1.0)
				Sfx.music("music_boss")
				a._add_shake(12.0 if int(ev[3]) == 1 else 8.0)
				a.screen_flash = Color(1.0, 0.3, 0.95, 0.5) if int(ev[3]) == 1 else Color(0.3, 1.0, 0.9, 0.4)
				if int(ev[3]) == 1:
					a.fx.nova(pos + Vector2(0, -16), Color("ff4df2"))
			World.EV_COMBO:
				var col := G.player_fx(int(ev[4]))
				# One call over the wizard who made it; big only for the rare x100 and beyond.
				var who: Vector2 = a.vp[int(ev[4])].pos if a.vp.has(int(ev[4])) else pos
				# The early calls come every few seconds in a big horde: a spark and a chime, so words stay rare.
				if int(ev[3]) < a.COMBO_WORDS:
					a.fx.sparkle(who + Vector2(0, -10), col, 8)
					Sfx.play("powerup", -8.0, 1.4)
				else:
					a.fx.text(who + Vector2(0, -22), World.COMBO_CALLS.get(int(ev[3]), "COMBO!"), col, 1.3,
						2 if int(ev[3]) >= 100 else 1)
					Sfx.play("powerup", -2.0, 1.2)
			World.EV_SPAWN:
				a.fx.teleport(pos, G.player_color(int(ev[3])))
				a.fx.ring(pos + Vector2(0, -6), 1.0, 30.0, 0.5, G.player_fx(int(ev[3])), 2.0)
				Sfx.play("teleport")
			World.EV_POWERUP:
				a.fx.sparkle(pos, ArenaDrawFx._pickup_color(a, int(ev[3])), 16)
				Sfx.play("orbit", -6.0)
			World.EV_BOSSDIE:
				for k in 6:
					a.fx.explosion(pos + Vector2(a._fx_rng.randf_range(-26, 26), a._fx_rng.randf_range(-26, 20)), 30.0)
				a.fx.nova(pos, Color("4dfff0"))
				Sfx.play("boss_fall")
				Sfx.play("explode", -3.0, 0.7)
				a._add_shake(12.0)
				a.screen_flash = Color(1, 1, 1, 0.8)
				a._do_hitstop(0.25)
				if int(ev[4]) == 1:
					ArenaFateView._banner(a, "ARCHLICH DESTROYED!", "+%d x COMBO" % (Bestiary.KINDS[World.LICH][Bestiary.K_SCORE] * World.FINAL_REWARD), Color("ff4df2"), 3.0)
				else:
					ArenaFateView._banner(a, ArenaDrawBoss.slain_title(false), "+5000 x COMBO", Color("4dfff0"), 3.0)
					Sfx.music(ArenaFateView._act_music(a))
			World.EV_VICTORY:
				a.victory = true
				Sfx.play("victory")
				Sfx.music("music_title")
				for q: Dictionary in a.vp.values():
					a.fx.burst(q.pos + Vector2(0, -8), 30, 140.0, 1.0, 2.0, Color.WHITE, Color("ffd94d"), true, 40.0, true)
			World.EV_RESULTS:
				a.results = Results.from_dict(ev[3])
			World.EV_GAMEOVER:
				a.game_over = true
				a.game_over_t = 0.0
				a.final_score = int(ev[3])
				a.run_t = float(ev[1])
				book_run_once(a, {"score": a.final_score, "seconds": float(ev[1]), "kills": int(ev[2]), "liches": int(ev[4]),
					"won": a.victory, "results": a.results})
				if not a.victory:
					Sfx.music("music_gameover")
			World.EV_LEVELUP:
				var col := G.player_fx(int(ev[3]))
				a._lv_flash_t = a.time
				a.fx.text(pos, "LEVEL UP!", col, 1.4, 1)
				a.fx.level_up(pos + Vector2(0, 8), col)
				Sfx.play("level_up", -2.0)
			World.EV_PICK:
				var col := G.player_fx(int(ev[3]))
				a.fx.text(pos, Classes.card_name(int(a.vp.get(int(ev[3]), {}).get("cls", 0)), int(ev[4])) + "!", col, 1.4, 1)
				a.fx.sparkle(pos + Vector2(0, 10), col, 16)
				if a.time - a._pick_sfx_t > 0.12:
					a._pick_sfx_t = a.time # four wizards picking at once play it once
					Sfx.play("card_pick", -6.0, 1.0, 0.2)
			World.EV_SLOTS:
				# The cap rises after the first boss (the first snapshot's cap is no news).
				if int(ev[3]) > Upgrades.SLOTS_EARLY.x:
					ArenaFateView._banner(a, "A FOURTH SLOT OPENS", "ONE MORE SPELL AND ONE MORE PASSIVE", Color("ffd94d"), 2.4, true)
			World.EV_LULL:
				a._lull_full = maxf(1.0, float(ev[3]))
				ArenaFateView._banner(a, "RESPITE", "THE HORDE REGROUPS  -  DRAW YOUR CARDS", Color("8bff9e"), 3.0, true)
				Sfx.play("wave_clear", -2.0, 0.8)
				ArenaTalk.start(a)
				for r in Net.my_slots():
					if a.vp.has(r.slot) and int(a.vp[r.slot].get("draws", 0)) > 0 and not ArenaTray._tray_shown(a, r.slot):
						a._tray_open[r.slot] = true
						if not (a.vp[r.slot].choices as Array).is_empty():
							ArenaTray._deal_tray(a, r.slot, int(a.vp[r.slot].offer), true) # opened by itself: the hand turns over
			World.EV_FROST:
				a.fx.burst(pos, 6, 70.0, 0.35, 1.0, Color.WHITE, a.SPELL_COLORS[World.SP_FROST], true)
				if float(ev[3]) > 0.0:
					a.fx.ring(pos, 0.4, float(ev[3]), 0.3, a.SPELL_COLORS[World.SP_FROST], 2.0)


## Books the run in the profile (and on Steam, on the host) with what it earned: the one path for a game over, a
## confirmed QUIT TO TITLE and the window closing (Arena._book_run_now). `run` holds score, seconds, kills,
## liches, won and results (a Results or null); the seal, act and party come from the arena, the urns broken
## (Profile.urns) from its World (a LAN client has none and books 0). Once per run: a second call does nothing.
static func book_run_once(a: Arena, run: Dictionary) -> void:
	if a.run_booked:
		return
	a.run_booked = true
	var party := Achievements.party_of(a.vp.values(), a.seal)
	var res: Variant = run.get("results")
	a.crystals_earned = G.finish_run({"score": int(run.get("score", 0)), "seconds": float(run.get("seconds", 0.0)),
		"kills": int(run.get("kills", 0)), "liches": int(run.get("liches", 0)), "won": bool(run.get("won", false)),
		"seal": a.seal, "act": a.act, "results": res, "party": party,
		"urns": a.world.urns_broken if a.world != null else 0})
	if a.is_host:
		Platform.finish_run(res as Results, bool(run.get("won", false)), float(run.get("seconds", 0.0)), party)

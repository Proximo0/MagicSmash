class_name ArenaSeats
extends RefCounted
## Arena: the demo bots' input and the level-up pick that rides on a seat's input.
## Static helpers: `a` is the Arena that owns the state.

## Adds the level-up pick fields [card, offer] (World reads input[6] and input[7]). The card field also carries
## Upgrades.REDRAW_INPUT and Upgrades.BANISH_INPUT + card (WorldLevels._update_levelups).
static func _with_pick(a: Arena, slot: int, inp: PackedFloat32Array) -> PackedFloat32Array:
	if not a.vp.has(slot):
		return SmashBot.with_pick(inp, [] as Array[int], 0)
	var p: Dictionary = a.vp[slot]
	var held := not (p.choices as Array).is_empty()
	if PlayerInput.bot:
		# Demo bots show their tray while they hold cards and take one after a moment, so watchers and captures see
		# it. With --pick-hold the slot 0 bot keeps its tray shut for the first second of the hold, or half a hold
		# shorter than two seconds (its tab shows), so it never takes a card with the tray shut.
		var wait: Array = a._bot_pick_wait.get(slot, [-1, 0.0])
		if not held:
			wait = [-1, 0.0]
		elif int(wait[0]) != int(p.offer):
			wait = [int(p.offer), 0.0]
		else:
			wait[1] = float(wait[1]) + a.get_physics_process_delta_time()
		a._bot_pick_wait[slot] = wait
		var hold := slot == 0 and a.autotest_pick_hold > 0.0
		ArenaTray._set_tray(a, slot, held and (not hold or float(wait[1]) >= minf(1.0, a.autotest_pick_hold * 0.5)))
		if float(wait[1]) < (a.autotest_pick_hold if hold else a.BOT_PICK_THINK):
			return SmashBot.with_pick(inp, [] as Array[int], p.offer)
		return SmashBot.with_pick(inp, p.choices, p.offer)
	var out: PackedFloat32Array = inp.duplicate()
	var sent: Array = a._pick_sent.get(slot, [-1, -1])
	if int(sent[1]) == int(p.offer) and held:
		out.append_array([float(sent[0]), float(p.offer)])
	else:
		out.append_array([-1.0, float(p.offer)])
	return out


static func _bot_input(a: Arena, slot: int) -> PackedFloat32Array:
	if not a.vp.has(slot):
		return PackedFloat32Array([0, 0, 0, 0, 0, 0])
	if not a._bots.has(slot):
		var persona := SmashBot.persona_from_name(Flags.get_arg("persona", "casual"))
		a._bots[slot] = SmashBot.new(slot + 1, persona if persona >= 0 else SmashBot.CASUAL)
	var bot: SmashBot = a._bots[slot]
	var me: Dictionary = a.vp[slot]
	var at: Vector2 = me.get("target", me.pos)
	var en: Array[Vector2] = []
	var es: Array[Vector2] = []
	var pk: Array[Vector2] = []
	if me.get("down", false):
		# A fallen seat's spirit drifts to the nearest standing mate (SmashBot.spirit_input, as in the sims).
		var standing: Array = []
		for q: Dictionary in a.vp.values():
			if q.slot != slot and q.get("alive", true) and not q.get("down", false):
				standing.append(q.get("target", q.pos))
		return bot.spirit_input(at, standing)
	if not bot.wants_senses(a.time):
		return bot.decide(slot, at, G.ARENA.get_center(), a.time, en, es, pk)
	var tune := Tuning.shared()
	var ev: Array = []
	var er: Array = []
	var boss := Vector2.INF
	var seen := {}
	for id: int in a.ve:
		var e: Dictionary = a.ve[id]
		var pos: Vector2 = e.get("target", e.pos)
		var tr: Array = a._bot_track.get(id, [pos, Vector2.ZERO, a.time])
		if a.time > float(tr[2]):
			tr = [pos, (pos - (tr[0] as Vector2)) / (a.time - float(tr[2])), a.time]
		a._bot_track[id] = tr
		seen[id] = true
		en.append(pos)
		ev.append(tr[1])
		er.append(Bestiary.KINDS[int(e.type)][Bestiary.K_R])
		if Bestiary.has_flag(int(e.type), Bestiary.F_BOSS):
			boss = pos
	for id: int in a._bot_track.keys():
		if not seen.has(id):
			a._bot_track.erase(id)
	var sv: Array = []
	var sr: Array = []
	for s: Array in a.ves:
		es.append(s[1])
		sv.append(s[2])
		sr.append([2.5, 4.0, 5.0][clampi(int(s[0]), 0, 2)])
	var kinds: Array = []
	for k: Array in a.vk:
		pk.append(k[1])
		kinds.append(k[0])
	var mates: Array = []
	var fallen: Array = []
	var party := Vector2.ZERO
	var lo := Vector2(-1e6, -1e6)
	var hi := Vector2(1e6, 1e6)
	for q: Dictionary in a.vp.values():
		if q.get("down", false) and q.slot != slot:
			fallen.append(q.get("target", q.pos))
		if not q.get("alive", true):
			continue
		var qp: Vector2 = q.get("target", q.pos)
		party += qp
		if q.slot == slot:
			continue
		mates.append(qp)
		lo = Vector2(maxf(lo.x, qp.x - tune.leash_x), maxf(lo.y, qp.y - tune.leash_y))
		hi = Vector2(minf(hi.x, qp.x + tune.leash_x), minf(hi.y, qp.y + tune.leash_y))
	var ctx := {
		"hp": int(me.get("hp", 5)), "max_hp": int(me.get("max_hp", 5)), "bombs": int(me.get("bombs", 0)),
		"speed": tune.player_speed * (tune.haste_speed_mul if float(me.get("haste", 0.0)) > 0.0 else 1.0),
		"enemy_vel": ev, "enemy_r": er, "shot_vel": sv, "shot_r": sr, "pickup_kinds": kinds, "mates": mates,
		"party": party / (mates.size() + 1),
		"arena": Rect2(G.ARENA.position + Vector2(5, 6), G.ARENA.size - Vector2(10, 8)),
		"leash": Rect2(lo, hi - lo), "boss": boss, "fallen": fallen, "hz": a.vhz,
	}
	var goal := bot.shrine_pick(at, float(me.get("gold", 0)), SmashBot.table_gold_of_views(a.vp.values()), a.vsh, a.time)
	return bot.decide(slot, at, G.ARENA.get_center(), a.time, en, es, pk, goal, ctx)

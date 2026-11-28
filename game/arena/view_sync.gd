class_name ArenaViewSync
extends RefCounted
## Arena: turns a snapshot into the view state (what gets drawn).
## Static helpers: `a` is the Arena that owns the state.

static func _apply_snapshot(a: Arena, snap: Dictionary, instant: bool) -> void:
	var pl: PackedFloat32Array = snap.p
	var seen := {}
	var i := 0
	while i + World.P_FLOATS <= pl.size():
		var slot := int(pl[i + World.P_SLOT])
		seen[slot] = true
		if not a.vp.has(slot):
			a.vp[slot] = {"slot": slot, "pos": Vector2(pl[i + World.P_X], pl[i + World.P_Y]), "walk_t": 0.0, "ghosts": []}
		var p: Dictionary = a.vp[slot]
		p.target = Vector2(pl[i + World.P_X], pl[i + World.P_Y])
		if instant:
			p.pos = p.target
		p.aim = Vector2(pl[i + World.P_AIM_X], pl[i + World.P_AIM_Y])
		p.hp = int(pl[i + World.P_HP])
		p.lives = int(pl[i + World.P_LIVES])
		p.alive = pl[i + World.P_ALIVE] > 0.5
		p.invuln = pl[i + World.P_INVULN]
		p.spell = int(pl[i + World.P_SPELL])
		G.slot_wizard[slot] = int(pl[i + World.P_WIZARD])
		p.bombs = int(pl[i + World.P_BOMBS])
		p.score = int(pl[i + World.P_SCORE])
		p.combo = int(pl[i + World.P_COMBO])
		p.haste = pl[i + World.P_HASTE]
		p.orbit = pl[i + World.P_ORBIT]
		p.orbit_ang = pl[i + World.P_ORBIT_ANG]
		p.flash = pl[i + World.P_FLASH]
		p.moving = pl[i + World.P_MOVING] > 0.5
		p.xp = int(pl[i + World.P_XP])
		p.xp_need = maxi(1, int(pl[i + World.P_XP_NEED]))
		p.level = int(pl[i + World.P_LEVEL])
		a.party_xp = p.xp
		a.party_need = p.xp_need
		a.party_level = p.level
		var offer := int(pl[i + World.P_OFFER])
		if offer != int(p.get("offer", -1)):
			# A new hand: its rows turn over if the tray is open (or was opened while the hand was on its way: a
			# level's hand comes a tick after its draw), and are already face up when the tray opens later.
			ArenaTray._deal_tray(a, slot, offer, bool(a._tray_open.get(slot, false)))
		p.offer = offer
		var ch: Array[int] = []
		var lv: Array[int] = []
		for c in World.P_CHOICE_COUNT:
			var idx := int(pl[i + World.P_CHOICES + c * 2])
			if idx >= 0:
				ch.append(idx)
				lv.append(int(pl[i + World.P_CHOICES + c * 2 + 1]))
		p.choices = ch
		p.choice_lv = lv
		# Spells and passives in the order taken: [Upgrades index, level] each (a spell's level above Spells.MAX_LEVEL = evolved, MAX_LEVEL + its evolution id).
		var spells: Array = []
		var passives: Array = []
		for k in World.P_SLOTS:
			var sid := int(pl[i + World.P_SPELLS + k * 2])
			if sid >= 0:
				spells.append([sid, int(pl[i + World.P_SPELLS + k * 2 + 1])])
			var pid := int(pl[i + World.P_PASSIVES + k * 2])
			if pid >= 0:
				passives.append([pid, int(pl[i + World.P_PASSIVES + k * 2 + 1])])
		p.spells = spells
		p.passives = passives
		p.gold = int(pl[i + World.P_GOLD])
		p.max_hp = int(pl[i + World.P_MAX_HP])
		p.redraws = int(pl[i + World.P_REDRAWS])
		p.banishes = int(pl[i + World.P_BANISHES])
		p.down = pl[i + World.P_DOWN] > 0.5
		p.down_left = pl[i + World.P_DOWN_LEFT]
		p.revive = pl[i + World.P_REVIVE]
		p.ai = pl[i + World.P_AI] > 0.5
		p.trait_a = int(pl[i + World.P_TRAIT_A])
		p.trait_b = int(pl[i + World.P_TRAIT_B])
		p.race = int(pl[i + World.P_RACE])
		p.cls = int(pl[i + World.P_CLASS])
		p.look = int(pl[i + World.P_LOOK])
		p.cls_level = int(pl[i + World.P_CLASS_LEVEL])
		var draws := int(pl[i + World.P_DRAWS])
		if draws > int(p.get("draws", 0)):
			a._tab_flash[slot] = a.time
			if (a.lull_left > 0.0 or a.phase == World.PH_INTRO) and int(p.get("draws", 0)) == 0 and a._is_local_slot(slot):
				a._tray_open[slot] = true # in the quiet (a lull, THE HEAD START's held intro) the cards come out by themselves
				if not ch.is_empty():
					ArenaTray._deal_tray(a, slot, offer, true) # the hand came with the draw (a merged snapshot): it turns over too
		p.draws = draws
		if draws == 0:
			a._tray_open[slot] = false # the last card is taken: the tray closes
		if not p.alive:
			p.pos = p.target
		i += World.P_FLOATS
	for s in a.vp.keys():
		if not seen.has(s):
			a.vp.erase(s)
	var en: PackedFloat32Array = snap.e
	var eseen := {}
	i = 0
	while i + World.ENEMY_FLOATS <= en.size():
		var id := int(en[i + World.E_ID])
		eseen[id] = true
		var pos := Vector2(en[i + World.E_X], en[i + World.E_Y])
		if not a.ve.has(id):
			a.ve[id] = {"type": int(en[i + World.E_TYPE]), "pos": pos, "t": a._fx_rng.randf() * 5.0, "flip": false, "prev_x": pos.x}
		var e: Dictionary = a.ve[id]
		e.target = pos
		if instant:
			e.pos = pos
		e.flash = en[i + World.E_FLASH]
		e.state = int(en[i + World.E_STATE])
		e.hpf = en[i + World.E_HP]
		e.slow = en[i + World.E_SLOW]
		var rank: float = en[i + World.E_RANK]
		e.elite = rank > 0.5 and rank < 1.5
		e.final = rank > 1.5
		e.status = int(en[i + World.E_STATUS])
		i += World.ENEMY_FLOATS
	for id in a.ve.keys():
		if not eseen.has(id):
			a.ve.erase(id)
	a.vs.clear()
	var sh: PackedFloat32Array = snap.s
	i = 0
	while i + 6 <= sh.size():
		var sk := int(sh[i])
		# [4] evolved (either id: id 2 draws as id 1 until a later job gives it a look of its own), [5] the id.
		var sk_evo := Spells.shot_evo(sk)
		a.vs.append([Spells.shot_spell(sk), Vector2(sh[i + 1], sh[i + 2]), Vector2(sh[i + 3], sh[i + 4]), int(sh[i + 5]),
			sk_evo > 0, sk_evo])
		i += 6
	a.vhz = snap.get("hz", PackedFloat32Array())
	a.vr.clear()
	var rn: PackedFloat32Array = snap.get("r", PackedFloat32Array())
	i = 0
	while i + World.RUNE_FLOATS <= rn.size():
		# [5] evolved (either id: id 2 draws as id 1 until a later job gives it a look of its own), [7] the id.
		a.vr.append([Vector2(rn[i], rn[i + 1]), rn[i + 2], rn[i + 3], rn[i + 4], int(rn[i + 5]), rn[i + 6] > 0.5,
			int(rn[i + World.R_KIND]), int(rn[i + 6])])
		i += World.RUNE_FLOATS
	a.vo.clear()
	var ob: PackedFloat32Array = snap.get("o", PackedFloat32Array())
	i = 0
	while i + World.O_FLOATS <= ob.size():
		a.vo.append(ob.slice(i, i + World.O_FLOATS))
		i += World.O_FLOATS
	a.ves.clear()
	var es: PackedFloat32Array = snap.es
	i = 0
	while i + 5 <= es.size():
		a.ves.append([int(es[i]), Vector2(es[i + 1], es[i + 2]), Vector2(es[i + 3], es[i + 4])])
		i += 5
	a.vu.clear()
	var up: PackedFloat32Array = snap.get("u", PackedFloat32Array())
	i = 0
	while i + 2 <= up.size():
		a.vu.append(Vector2(up[i], up[i + 1]))
		i += 2
	a.vsh.clear()
	var shp: PackedFloat32Array = snap.get("sh", PackedFloat32Array())
	i = 0
	while i + World.SHRINE_FLOATS <= shp.size():
		a.vsh.append([int(shp[i]), shp[i + 1], shp[i + 2], shp[i + 3], shp[i + 4], int(shp[i + 5]), int(shp[i + 6])])
		i += World.SHRINE_FLOATS
	a.vk.clear()
	var pk: PackedFloat32Array = snap.k
	i = 0
	while i + 4 <= pk.size():
		a.vk.append([int(pk[i]), Vector2(pk[i + 1], pk[i + 2]), pk[i + 3]])
		i += 4
	var w: PackedFloat32Array = snap.w
	a.wave = int(w[World.W_WAVE])
	a.phase = int(w[World.W_PHASE])
	a.phase_t = w[World.W_PHASE_T]
	a.boss_f = w[World.W_BOSS]
	a.vw = w
	a.run_t = w[World.W_TIME]
	a.boss_final = w[World.W_FINAL] > 0.5
	var was_lull := a.lull_left
	a.lull_left = w[World.W_LULL]
	a.seal = int(w[World.W_SEAL])
	a.slot_cap = Vector2i(int(w[World.W_CAP_SPELLS]), int(w[World.W_CAP_PASSIVES]))
	a.fates = snap.get("f", PackedFloat32Array())
	if was_lull > 0.0 and a.lull_left <= 0.0 and a.phase != World.PH_GAMEOVER:
		ArenaFateView._banner(a, "THE HORDE RETURNS", "", Color("ff6a4d"), 1.6, true)
		Sfx.play("gong", -2.0)
	for d in 4:
		a.doors[d] = w[World.W_DOORS + d]

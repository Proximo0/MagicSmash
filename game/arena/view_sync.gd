class_name ArenaViewSync
extends RefCounted
## Arena: turns a snapshot into the view state (what gets drawn).
## Static helpers: `a` is the Arena that owns the state.

static func _apply_snapshot(a: Arena, snap: Dictionary, instant: bool) -> void:
	var pl: PackedFloat32Array = snap.p
	var seen := {}
	var i := 0
	while i + World.PLAYER_FLOATS <= pl.size():
		var slot := int(pl[i])
		seen[slot] = true
		if not a.vp.has(slot):
			a.vp[slot] = {"slot": slot, "pos": Vector2(pl[i + 1], pl[i + 2]), "walk_t": 0.0, "ghosts": []}
		var p: Dictionary = a.vp[slot]
		p.target = Vector2(pl[i + 1], pl[i + 2])
		if instant:
			p.pos = p.target
		p.aim = Vector2(pl[i + 3], pl[i + 4])
		p.hp = int(pl[i + 5])
		p.lives = int(pl[i + 6])
		p.alive = pl[i + 7] > 0.5
		p.invuln = pl[i + 8]
		p.spell = int(pl[i + 9])
		G.slot_wizard[slot] = int(pl[i + 10])
		p.bombs = int(pl[i + 11])
		p.score = int(pl[i + 12])
		p.combo = int(pl[i + 13])
		p.haste = pl[i + 14]
		p.orbit = pl[i + 15]
		p.orbit_ang = pl[i + 16]
		p.flash = pl[i + 17]
		p.moving = pl[i + 18] > 0.5
		p.xp = int(pl[i + 19])
		p.xp_need = maxi(1, int(pl[i + 20]))
		p.level = int(pl[i + 21])
		a.party_xp = p.xp
		a.party_need = p.xp_need
		a.party_level = p.level
		var offer := int(pl[i + 22])
		if offer != int(p.get("offer", -1)):
			# A new hand: its rows turn over if the tray is open (or was opened while the hand was on its way: a
			# level's hand comes a tick after its draw), and are already face up when the tray opens later.
			a._deal_tray(slot, offer, bool(a._tray_open.get(slot, false)))
		p.offer = offer
		var ch: Array[int] = []
		var lv: Array[int] = []
		for c in 3:
			var idx := int(pl[i + 23 + c * 2])
			if idx >= 0:
				ch.append(idx)
				lv.append(int(pl[i + 24 + c * 2]))
		p.choices = ch
		p.choice_lv = lv
		var wl: Array[int] = []
		for sp in Spells.COUNT:
			wl.append(int(pl[i + World.PLAYER_WEAPONS + sp]))
		p.weapons = wl
		p.gold = int(pl[i + World.PLAYER_WEAPONS + Spells.COUNT])
		p.max_hp = int(pl[i + World.PLAYER_WEAPONS + Spells.COUNT + 1])
		var draws := int(pl[i + World.PLAYER_WEAPONS + Spells.COUNT + 2])
		if draws > int(p.get("draws", 0)):
			a._tab_flash[slot] = a.time
			if a.lull_left > 0.0 and int(p.get("draws", 0)) == 0 and a._is_local_slot(slot):
				a._tray_open[slot] = true # in the quiet the cards come out by themselves
				if not ch.is_empty():
					a._deal_tray(slot, offer, true) # the hand came with the draw (a merged snapshot): it turns over too
		p.draws = draws
		if draws == 0:
			a._tray_open[slot] = false # the last card is taken: the tray closes
		if not p.alive:
			p.pos = p.target
		i += World.PLAYER_FLOATS
	for s in a.vp.keys():
		if not seen.has(s):
			a.vp.erase(s)
	var en: PackedFloat32Array = snap.e
	var eseen := {}
	i = 0
	while i + World.ENEMY_FLOATS <= en.size():
		var id := int(en[i])
		eseen[id] = true
		var pos := Vector2(en[i + 2], en[i + 3])
		if not a.ve.has(id):
			a.ve[id] = {"type": int(en[i + 1]), "pos": pos, "t": a._fx_rng.randf() * 5.0, "flip": false, "prev_x": pos.x}
		var e: Dictionary = a.ve[id]
		e.target = pos
		if instant:
			e.pos = pos
		e.flash = en[i + 4]
		e.state = int(en[i + 5])
		e.hpf = en[i + 6]
		e.slow = en[i + 7]
		e.elite = en[i + 8] > 0.5 and en[i + 8] < 1.5
		e.final = en[i + 8] > 1.5
		i += World.ENEMY_FLOATS
	for id in a.ve.keys():
		if not eseen.has(id):
			a.ve.erase(id)
	a.vs.clear()
	var sh: PackedFloat32Array = snap.s
	i = 0
	while i + 6 <= sh.size():
		var sk := int(sh[i])
		a.vs.append([sk % Spells.COUNT, Vector2(sh[i + 1], sh[i + 2]), Vector2(sh[i + 3], sh[i + 4]), int(sh[i + 5]), sk >= Spells.COUNT])
		i += 6
	a.vr.clear()
	var rn: PackedFloat32Array = snap.get("r", PackedFloat32Array())
	i = 0
	while i + World.RUNE_FLOATS <= rn.size():
		a.vr.append([Vector2(rn[i], rn[i + 1]), rn[i + 2], rn[i + 3], rn[i + 4], int(rn[i + 5]), rn[i + 6] > 0.5])
		i += World.RUNE_FLOATS
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
	while i + 6 <= shp.size():
		a.vsh.append([int(shp[i]), shp[i + 1], shp[i + 2], shp[i + 3], shp[i + 4], int(shp[i + 5])])
		i += 6
	a.vk.clear()
	var pk: PackedFloat32Array = snap.k
	i = 0
	while i + 4 <= pk.size():
		a.vk.append([int(pk[i]), Vector2(pk[i + 1], pk[i + 2]), pk[i + 3]])
		i += 4
	var w: PackedFloat32Array = snap.w
	a.wave = int(w[0])
	a.phase = int(w[1])
	a.phase_t = w[2]
	a.boss_f = w[3]
	a.run_t = w[8]
	a.boss_final = w.size() > 9 and w[9] > 0.5
	var was_lull := a.lull_left
	a.lull_left = w[10] if w.size() > 10 else 0.0
	if was_lull > 0.0 and a.lull_left <= 0.0 and a.phase != World.PH_GAMEOVER:
		a._banner("THE HORDE RETURNS", "", Color("ff6a4d"), 1.6, true)
		Sfx.play("gong", -2.0)
	for d in 4:
		a.doors[d] = w[4 + d]

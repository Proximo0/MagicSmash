extends TestCase
## KindsCrypt: the BLOAT, the RESTLESS COFFIN and the TOMB GUARD (game/logic/kinds_crypt.gd).

const DT := 1.0 / 60.0


func _crypt_world() -> World:
	var w := World.new([0], 5)
	w.phase = World.PH_FIGHT
	return w


## Runs the enemies and the hazard rows `secs` seconds, the way World.step orders them, with no horde.
func _crypt_tick(w: World, secs: float) -> void:
	for _i: int in range(roundi(secs / DT)):
		w._build_grid()
		w._plist.assign(w.players.values())
		for e: World.Enemy in w.enemies:
			if not e.dead:
				WorldEnemies._update_enemy(w, e, DT)
		WorldHazards._update_hazards(w, DT)
		w.enemies = w.enemies.filter(func(e: World.Enemy) -> bool: return not e.dead)


func _count(w: World, type: int) -> int:
	return w.enemies.filter(func(e: World.Enemy) -> bool: return e.type == type and not e.dead).size()


func test_bloat_blast_chains_and_credits_the_killer() -> void:
	var w := _crypt_world()
	var p: World.Player = w.players[0]
	var a := w.spawn_enemy(Bestiary.BLOAT, 0, p.pos + Vector2(110, 0))
	var b := w.spawn_enemy(Bestiary.BLOAT, 0, p.pos + Vector2(130, 0))
	var c := w.spawn_enemy(Bestiary.BLOAT, 0, p.pos + Vector2(210, 0))
	for e: World.Enemy in [a, b, c]:
		e.spd = 0.0
	w.damage_enemy(a, 99.0, 0, Vector2.ZERO)
	assert_true(a.dead)
	assert_eq(w.hazards.size(), 1, "the body leaves a blast")
	var h: Hazards.Hazard = w.hazards[0]
	assert_eq(h.kind, Hazards.BLAST)
	assert_near(h.r, KindsCrypt.BLOAT_BLAST_R)
	assert_near(h.warn, KindsCrypt.BLOAT_BLAST_WARN)
	assert_eq(h.slot, 0, "credited to the killer")
	_crypt_tick(w, KindsCrypt.BLOAT_BLAST_WARN + 0.1)
	assert_true(b.dead, "the blast should pop the bloat next to it")
	assert_false(c.dead, "the far one is out of reach of the first blast")
	assert_eq(p.kills, 2, "the chained kill is the killer's")
	_crypt_tick(w, KindsCrypt.BLOAT_BLAST_WARN + 0.1)
	assert_false(c.dead, "80 px away: the chain ends")


func test_a_frosted_bloat_has_no_blast() -> void:
	var w := _crypt_world()
	var p: World.Player = w.players[0]
	var a := w.spawn_enemy(Bestiary.BLOAT, 0, p.pos + Vector2(100, 0))
	a.slow = 1.0
	w.damage_enemy(a, 99.0, 0, Vector2.ZERO)
	assert_true(a.dead)
	assert_eq(w.hazards.size(), 0, "a frost-slowed bloat dies quietly")


func test_a_bloat_pops_by_a_wizard_and_the_blast_hurts_her() -> void:
	var w := _crypt_world()
	var p: World.Player = w.players[0]
	p.invuln = 0.0
	var hp := p.hp
	var a := w.spawn_enemy(Bestiary.BLOAT, 0, p.pos + Vector2(40, 0))
	var pickups := w.pickups.size()
	_crypt_tick(w, 1.2)
	assert_true(a.dead, "it pops itself within 16 px")
	assert_eq(w.pickups.size(), pickups, "a pop pays nothing")
	_crypt_tick(w, KindsCrypt.BLOAT_BLAST_WARN)
	assert_eq(p.hp, hp - 1, "standing in the blast costs a heart")


func test_coffin_hatches_at_six_seconds_and_drops_nothing() -> void:
	var w := _crypt_world()
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.COFFIN, 0, p.pos + Vector2(100, 0))
	var pickups := w.pickups.size()
	_crypt_tick(w, KindsCrypt.COFFIN_SHUT - 0.05)
	assert_eq(e.state, KindsCrypt.ST_SHUT)
	_crypt_tick(w, 0.1)
	assert_eq(e.state, KindsCrypt.ST_RATTLE, "it rattles after 4 s")
	_crypt_tick(w, KindsCrypt.COFFIN_RATTLE - 0.1)
	assert_false(e.dead, "not yet at 5.95 s")
	_crypt_tick(w, 0.05)
	assert_true(e.dead, "hatched at 6.0 s")
	assert_eq(_count(w, World.SKELETON), 3)
	assert_eq(w.pickups.size(), pickups, "a hatch drops nothing")
	w.wave_time = KindsCrypt.COFFIN_LATE
	w.spawn_enemy(Bestiary.COFFIN, 0, p.pos + Vector2(-100, 0))
	_crypt_tick(w, 6.05)
	assert_eq(_count(w, World.SKELETON), 3 + 4, "four from 10:00")


func test_a_broken_coffin_drops_xp_and_a_gem() -> void:
	var w := _crypt_world()
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.COFFIN, 0, p.pos + Vector2(100, 0))
	w.damage_enemy(e, 99.0, 0, Vector2.ZERO)
	assert_true(e.dead)
	var gems := 0
	var xp := 0
	for k: World.Pickup in w.pickups:
		gems += 1 if k.kind == World.PK_GEM else 0
		xp += 1 if k.kind == World.PK_XP else 0
	assert_eq(gems, 1)
	assert_true(xp >= 1, "XP too")
	assert_eq(_count(w, World.SKELETON), 0)


func test_guard_blocks_only_from_the_front() -> void:
	var w := _crypt_world()
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.GUARD, 0, p.pos + Vector2(100, 0))
	e.hp = 50.0
	_crypt_tick(w, 0.1)
	assert_near(e.dir.angle_to(p.pos - e.pos), 0.0, 0.05, "it faces the wizard")
	var away := (e.pos - p.pos).normalized()
	var hp := e.hp
	w.damage_enemy(e, 1.0, 0, away * 100.0)
	assert_eq(e.hp, hp, "a shot from the front sparks off")
	w.damage_enemy(e, 1.0, 0, away.rotated(deg_to_rad(65.0)) * 100.0)
	assert_eq(e.hp, hp, "65 degrees off the facing is still the shield")
	w.damage_enemy(e, 1.0, 0, away.rotated(deg_to_rad(80.0)) * 100.0)
	assert_true(e.hp < hp, "80 degrees off the facing hits")
	hp = e.hp
	w.damage_enemy(e, 1.0, 0, -away * 100.0)
	assert_true(e.hp < hp, "a hit in the back lands")
	hp = e.hp
	w.damage_enemy(e, 1.0, 0, Vector2.ZERO)
	assert_true(e.hp < hp, "a hit with no push passes")
	hp = e.hp
	w.damage_enemy(e, 1.0, 0, away * 100.0, true)
	assert_true(e.hp < hp, "the nova and hazards pass (sure)")
	hp = e.hp
	w.add_hazard(Hazards.BLAST, e.pos + Vector2(-5, 0), e.pos + Vector2(-5, 0), 20.0, 0.0, 0.1, -1, 0, true)
	_crypt_tick(w, Hazards.min_warn(20.0) + 0.05)
	assert_true(e.hp < hp, "a blast from the front still hurts")


func test_guard_turns_at_most_its_rate() -> void:
	var w := _crypt_world()
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.GUARD, 0, p.pos + Vector2(150, 0))
	e.spd = 0.0
	_crypt_tick(w, DT)
	var a0 := e.dir.angle()
	p.pos = e.pos + Vector2(150, 0) # now behind it
	_crypt_tick(w, 1.0)
	assert_near(absf(angle_difference(a0, e.dir.angle())), KindsCrypt.GUARD_TURN, 0.05)


func test_a_coffin_touches_nobody() -> void:
	var w := _crypt_world()
	var p: World.Player = w.players[0]
	p.invuln = 0.0
	w.spawn_enemy(Bestiary.COFFIN, 0, p.pos + Vector2(3, 0))
	_crypt_tick(w, 0.5)
	assert_near(p.invuln, 0.0, 0.0001, "contact 0: no hurt, no free invulnerability")
	assert_eq(p.hp, p.max_hp)


## A bot alone with its warnings: a popping bloat's blast and a shard's fall on the spot where it stands.
func test_a_bot_walks_out_of_a_bloat_blast_and_a_falling_shard() -> void:
	for kind: int in [Hazards.BLAST, Hazards.FALL]:
		var t := Tuning.new()
		t.enemy_cap = 0.0
		t.elite_interval = 9999.0
		var w := World.new([0], 3, t)
		w.phase = World.PH_FIGHT
		w.powerup_timer = 9999.0
		var p: World.Player = w.players[0]
		p.invuln = 0.0
		var bot := SmashBot.new(4)
		var r := KindsCrypt.BLOAT_BLAST_R if kind == Hazards.BLAST else KindsSanctum.SHARD_FALL_R
		var warn := KindsCrypt.BLOAT_BLAST_WARN if kind == Hazards.BLAST else KindsSanctum.SHARD_FALL_WARN
		var at := p.pos + Vector2(10, 0)
		var h := w.add_hazard(kind, at, at, r, warn, 0.2)
		h.aux = Bestiary.SHARD
		var hp := p.hp
		for _i: int in range(120):
			w.step(DT, {0: bot.decide_in_world(w, 0)})
		assert_eq(p.hp, hp, "the bot stood in a %d row" % kind)


func test_a_coffin_brood_keeps_under_the_cap_with_the_queue() -> void:
	var w := _crypt_world()
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.COFFIN, 0, p.pos + Vector2(100, 0))
	var room := 2
	while w.enemies.size() + w.spawn_queue.size() < w.enemy_cap() - room:
		w.spawn_queue.append({"t": 999.0, "type": World.GOBLIN, "door": 0})
	_crypt_tick(w, KindsCrypt.COFFIN_SHUT + KindsCrypt.COFFIN_RATTLE + 0.05)
	assert_true(e.dead)
	assert_eq(_count(w, World.SKELETON), room, "only the room under the cap, the queue counted")


func _frost_shot(spell: int, evo: bool, from: Vector2, to: Vector2) -> World.Shot:
	var s := World.Shot.new()
	s.spell = spell
	s.evo = evo
	s.dmg = 99.0
	s.owner = 0
	s.pos = to
	s.vel = (to - from).normalized() * 200.0
	return s


func test_a_blocked_frost_bolt_does_not_slow_a_guard() -> void:
	var w := _crypt_world()
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.GUARD, 0, p.pos + Vector2(100, 0))
	e.hp = 500.0
	_crypt_tick(w, 0.1)
	WorldCastBolts._shot_hit(w, _frost_shot(World.SP_FROST, false, p.pos, e.pos), e)
	assert_eq(e.hp, 500.0, "blocked")
	assert_near(e.slow, 0.0, 0.0001, "a blocked bolt does not slow")
	WorldCastBolts._shot_hit(w, _frost_shot(World.SP_FROST, false, e.pos + Vector2(60, 0), e.pos), e)
	assert_true(e.hp < 500.0 and e.slow > 0.0, "a bolt in the back lands and slows")


func test_a_bloat_killed_by_frost_makes_no_blast() -> void:
	for evo_star: bool in [false, true]:
		var w := _crypt_world()
		var p: World.Player = w.players[0]
		var e := w.spawn_enemy(Bestiary.BLOAT, 0, p.pos + Vector2(100, 0))
		if evo_star:
			# Comet Rain: the star's burst kills the bloat beside the one it hits.
			var hit := w.spawn_enemy(World.ORC, 0, e.pos + Vector2(6, 0))
			hit.hp = 999.0
			w._build_grid()
			WorldCastBolts._shot_hit(w, _frost_shot(World.SP_STAR, true, p.pos, hit.pos), hit)
		else:
			WorldCastBolts._shot_hit(w, _frost_shot(World.SP_FROST, false, p.pos, e.pos), e)
		assert_true(e.dead, "the frost hit kills it")
		assert_eq(w.hazards.size(), 0, "frosted: no blast (star burst %s)" % str(evo_star))


func test_a_bloat_blast_spares_a_boss() -> void:
	var w := _crypt_world()
	var p: World.Player = w.players[0]
	var boss := w.spawn_enemy(World.LICH, 0, p.pos + Vector2(120, 0))
	var bloat := w.spawn_enemy(Bestiary.BLOAT, 0, boss.pos + Vector2(10, 0))
	bloat.spd = 0.0
	var hp := boss.hp
	w.damage_enemy(bloat, 99.0, -1, Vector2.ZERO)
	WorldHazards._update_hazards(w, KindsCrypt.BLOAT_BLAST_WARN + 0.01)
	WorldHazards._update_hazards(w, 0.01)
	assert_eq(boss.hp, hp, "a regular blast does no foe damage to a boss")

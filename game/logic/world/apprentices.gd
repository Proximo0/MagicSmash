class_name WorldApprentices
extends RefCounted
## Apprentices for World: computer wizards that fill a seat (Player.ai; a human seat whose device went silent is
## played the same way until it speaks again, see Net). Static helpers; the first argument is the World.
##
## The rules (numbers in Tuning's "Apprentices" rows): World plays an apprentice that has no input this step with a
## SmashBot (make_apprentice; all of them decide every SmashBot.APPRENTICE_TICKS ticks on one shared_senses), and
## takes its level-up card the moment the hand is dealt (WorldLevels, on main). Its damage is x apprentice_damage and
## it counts apprentice_scale toward the party size (World.pscale, World.xp_needed). It never takes chests, tomes, cards,
## shrine bets or fate cards; the coins and gems it touches go to the nearest human; it takes a potion only at
## apprentice_potion_hp hearts or fewer and only while no standing human is hurt. Fallen, it gets up by itself
## after apprentice_up_time seconds without losing a life, except under DARKNESS. It answers a human's call.


## `inputs` with an input for every apprentice that has none (the caller's dictionary when nothing is added).
static func with_inputs(w: World, inputs: Dictionary) -> Dictionary:
	var out := inputs
	var copied := false
	var ctx: Dictionary = {}
	var think := w._tick % SmashBot.APPRENTICE_TICKS == 0
	for p: World.Player in w._plist:
		if not p.ai or inputs.has(p.slot):
			continue
		if not copied:
			out = inputs.duplicate()
			copied = true
		var bot: SmashBot = w.apprentice_bots.get(p.slot)
		if bot == null:
			bot = SmashBot.make_apprentice(int(w.rng.seed % 100000) * 10 + p.slot + 1)
			w.apprentice_bots[p.slot] = bot
		var decide := think or bot.thinks == 0
		if decide and ctx.is_empty():
			ctx = SmashBot.shared_senses(w)
		out[p.slot] = bot.apprentice_input(w, p, ctx if decide else {})
	return out


## True if wizard `p` may pick up a pickup of `kind` (always, for a human).
static func may_take(w: World, p: World.Player, kind: int) -> bool:
	if not p.ai:
		return true
	if kind == World.PK_POTION:
		return p.hp <= int(w.tune.apprentice_potion_hp) and not human_hurt(w)
	return SmashBot.APPRENTICE_KINDS.has(kind)


## True while a standing human is missing a heart.
static func human_hurt(w: World) -> bool:
	for q: World.Player in w._plist:
		if q.alive and not q.ai and q.hp < q.max_hp:
			return true
	return false


## Who is paid for a coin or gem `p` touched: the nearest human (standing first), else `p` itself.
static func payee(w: World, p: World.Player, kind: int) -> World.Player:
	if not p.ai or (kind != World.PK_COIN and kind != World.PK_GEM):
		return p
	var best: World.Player = null
	var bd := INF
	for q: World.Player in w._plist:
		if q.ai:
			continue
		var d := q.pos.distance_to(p.pos) + (0.0 if q.alive else 1e6)
		if d < bd:
			bd = d
			best = q
	return best if best != null else p


## True when a fallen apprentice gets up by itself now (after apprentice_up_time; never under DARKNESS, whose
## rituals take longer: World.seal_ritual > 1). An away human seat never does: her lives are her own.
static func gets_up(w: World, p: World.Player) -> bool:
	return p.ai and not p.away and p.down and w.seal_ritual <= 1.0 and p.down_t >= w.tune.apprentice_up_time

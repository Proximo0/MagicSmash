class_name WorldApprentices
extends RefCounted
## Apprentices for World: computer wizards that fill a seat (Player.ai; a human seat whose device went silent is
## played the same way until it speaks again, see Net). Static helpers; the first argument is the World.
##
## The rules (numbers in Tuning's "Apprentices" rows): World plays an apprentice that has no input this step with a
## SmashBot (make_apprentice; all of them decide every SmashBot.APPRENTICE_TICKS ticks on one shared_senses), and
## takes its level-up card the moment the hand is dealt (WorldLevels, on main). Its damage is x apprentice_damage and
## it counts apprentice_scale toward the party size (World.pscale, World.xp_needed). It never takes chests, tomes, cards,
## shrine bets or fate cards; the coins and gems it touches go to the nearest human (an away human's seat keeps her
## loot: is_human_seat); it takes a potion only at
## apprentice_potion_hp hearts or fewer and only while no standing human is hurt. Fallen, it gets up by itself
## after apprentice_up_time seconds without losing a life, except under DARKNESS. It answers a human's call.
## Seated with a class (Net.add_apprentice: the party's first missing role), it becomes a level 1 hero of it on the
## run's first step (take_class) and its brain plays that class; the rules above stack on top.


## `inputs` with an input for every apprentice that has none (the caller's dictionary when nothing is added).
static func with_inputs(w: World, inputs: Dictionary) -> Dictionary:
	var out := inputs
	var copied := false
	var ctx: Dictionary = {}
	var think := w._tick % SmashBot.APPRENTICE_TICKS == 0
	if not w.classes_taken: # the run's first step: apprentices seated with a class become heroes of it, once
		w.classes_taken = true
		for p: World.Player in w._plist:
			take_class(w, p)
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


## An apprentice seated with a class (its seat's cls_level 1 or more: Net.add_apprentice) becomes a hero of that
## class and race at that level on the run's first step (with_inputs; after apply_meta, as Arena applies a human's
## hero). A seat with no class level, and an away human seat, keep what they have.
static func take_class(w: World, p: World.Player) -> void:
	if not p.ai or p.away or p.cls_level <= 0:
		return
	var h := Hero.make(p.race, p.cls, p.wizard) # a mage keeps the spell of her colour
	h.level = p.cls_level
	w.apply_hero(p, h.to_dict())


## True for a human's seat, whether she plays it or is away (her pad fell silent and an apprentice AI moves her):
## her loot stays hers. World.humans() leaves the away seats out.
static func is_human_seat(p: World.Player) -> bool:
	return not p.ai or p.away


## Every human seat, away or not, in slot order (is_human_seat): who is paid loot (THE EMPEROR's chests).
static func human_seats(w: World) -> Array[World.Player]:
	var out: Array[World.Player] = []
	for p: World.Player in w.players.values():
		if is_human_seat(p):
			out.append(p)
	return out


## True if wizard `p` may pick up a pickup of `kind` (always, for a human seat, away or not).
static func may_take(w: World, p: World.Player, kind: int) -> bool:
	if is_human_seat(p):
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


## Who is paid for a coin or gem `p` touched: `p` on a human seat (away or not); for an apprentice the nearest human
## seat (standing first), else the apprentice itself.
static func payee(w: World, p: World.Player, kind: int) -> World.Player:
	if is_human_seat(p) or (kind != World.PK_COIN and kind != World.PK_GEM):
		return p
	var best: World.Player = null
	var bd := INF
	for q: World.Player in w._plist:
		if not is_human_seat(q):
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

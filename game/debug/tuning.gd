class_name Tuning
extends RefCounted
## Template for live-tunable gameplay numbers (pattern from the skate project's PhysicsTuning).
## Game code reads `Tuning.shared().<field>` every tick instead of hard-coding numbers, so a tuning panel,
## replays, sims and presets can change the feel without touching code.
## Add a row to FIELDS and a matching `var` below; nothing else is needed.
## Presets are JSON dictionaries of {field: value}; unknown keys are ignored.

signal changed(field: String, value: float)

## [field, default, min, max, step, group, doc]. The order here is the order a tuning panel shows.
const FIELDS: Array = [
	["player_speed", 102.0, 40.0, 220.0, 2.0, "Player", "Wizard walk speed, px/s (the arena is 480x270)."],
	["haste_speed_mul", 1.45, 1.0, 2.5, 0.05, "Player", "Walk speed multiplier while Haste boots are active."],
	["haste_rate_mul", 0.72, 0.3, 1.0, 0.02, "Player", "Cast cooldown multiplier while hasted (lower casts faster)."],
	["spell_cd_mul", 1.0, 0.2, 3.0, 0.05, "Casting", "Multiplier on every spell's cooldown (Spells.STATS); lower casts faster."],
	["auto_aim_range", 200.0, 40.0, 480.0, 10.0, "Casting", "Spells auto-aim at the nearest enemy within this range, px, unless the player aims."],
	["star_sweep_arc", 0.5, 0.0, 2.0, 0.05, "Casting", "THE STAR: a sweep (CLEAVE) sends no missiles; its arc grows by this share of itself for each one instead."],
	["horde_start_budget", 0.0, 0.0, 100.0, 1.0, "Spawning", "Spawn budget the horde starts with, so the first enemies come at once."],
	["horde_rate_base", 1.5, 0.0, 40.0, 0.1, "Spawning", "Spawn budget earned per second at the start of a run (a goblin costs 1, an orc 9)."],
	["horde_rate_per_min", 5.0, 0.0, 20.0, 0.1, "Spawning", "Spawn budget per second added for each minute survived."],
	["spawn_party_scale", 1.0, 0.0, 1.5, 0.05, "Spawning", "Extra budget per extra wizard: budget x (1 + this x (players - 1))."],
	["down_spawn_weight", 1.0, 0.0, 1.0, 0.05, "Spawning", "How much a fallen wizard counts toward the party size the horde scales with (1 = a full wizard)."],
	["apprentice_scale", 0.7, 0.0, 1.0, 0.05, "Spawning", "How much an apprentice (computer wizard) counts toward the party size the horde scales with."],
	["horde_boss_mul", 0.35, 0.0, 1.0, 0.05, "Spawning", "Spawn budget multiplier while the Lich is alive."],
	["rift_share", 0.6, 0.0, 1.0, 0.05, "Spawning", "Share of horde groups that open a rift in the arena instead of coming through a door."],
	["rift_warning", 0.9, 0.2, 3.0, 0.05, "Spawning", "Seconds a rift's marker shows before its enemies appear."],
	["leash_x", 440.0, 100.0, 700.0, 10.0, "Spawning", "Furthest two wizards may be apart across, px (they share one screen)."],
	["leash_y", 200.0, 60.0, 400.0, 10.0, "Spawning", "Furthest two wizards may be apart up and down, px (the play window has room for 203 with both bodies in view)."],
	["rift_max_dist", 230.0, 60.0, 600.0, 10.0, "Spawning", "Rifts open at most this far from the middle of the party, px."],
	["door_near_share", 0.6, 0.0, 1.0, 0.05, "Spawning", "Share of door groups that use the door nearest the party (the rest pick any door)."],
	["rift_min_dist", 90.0, 30.0, 200.0, 5.0, "Spawning", "Rifts open at least this far from every wizard, px."],
	["enemy_cap", 260.0, 20.0, 600.0, 10.0, "Spawning", "Most enemies alive at once; the horde holds its budget while at the cap."],
	["elite_interval", 45.0, 5.0, 300.0, 5.0, "Spawning", "Seconds between elite spawns (a big glowing orc or mage that drops loot)."],
	["elite_hp_mul", 8.0, 1.0, 30.0, 0.5, "Spawning", "Elite HP as a multiple of a normal enemy of its type."],
	["lull_seconds", 20.0, 0.0, 60.0, 1.0, "Spawning", "Seconds of quiet after a Lich (not the Archlich) falls: nothing spawns and every XP gem flies to the party. 0 = no lull."],
	["chest_life", 40.0, 5.0, 300.0, 5.0, "Loot", "Seconds a chest stays on the floor."],
	["elite_chest_luck", 1.0, 0.0, 5.0, 1.0, "Loot", "Luck of an elite's chest (each point moves a fifth of the common odds up the tiers)."],
	["boss_chest_luck", 3.0, 0.0, 5.0, 1.0, "Loot", "Luck of the chests the Lich drops, one per wizard."],
	["rare_drop_chance", 0.0015, 0.0, 0.1, 0.0005, "Loot", "Chance any kill drops a rare chest (blue, opens rare or better)."],
	["ultra_run_chance", 0.01, 0.0, 1.0, 0.005, "Loot", "Chance a run is an ULTRA RARE run (decided once, at the start): one prismatic chest drops from a kill at its seeded moment and opens ULTRA RARE. No other chest ever does."],
	["ultra_run_luck", 0.002, 0.0, 0.02, 0.001, "Loot", "ultra_run_chance added per point of the run's chest luck (meta unlocks and the Seal's luck)."],
	["ultra_run_cap", 0.03, 0.0, 1.0, 0.005, "Loot", "Most an ULTRA RARE run's chance can reach with luck."],
	["card_run_chance", 0.01, 0.0, 1.0, 0.005, "Loot", "Chance a run is a card run (decided once, times the Seal's card odds): exactly one monster card drops, from the first kill with a card at its seeded moment. No other kill, urn or boss drops one."],
	["card_run_urn", 0.15, 0.0, 1.0, 0.05, "Loot", "Share of card runs whose card waits in the first urn broken after the moment instead (any monster's card)."],
	["loot_moment_from", 0.1, 0.0, 1.0, 0.05, "Loot", "Earliest moment of a run's ULTRA RARE chest or card, as a share of the run up to the Archlich."],
	["loot_moment_to", 0.4, 0.0, 1.0, 0.05, "Loot", "Latest moment of a run's ULTRA RARE chest or card, as a share of the run up to the Archlich."],
	["urn_count", 5.0, 0.0, 20.0, 1.0, "Loot", "Urns standing along the arena walls; broken ones are replaced each minute."],
	["urn_rare_chance", 0.03, 0.0, 0.5, 0.01, "Loot", "Chance an urn holds a rare chest."],
	["floor_tomes", 0.0, 0.0, 1.0, 1.0, "Loot", "1 = spell tomes drop on the floor as before and there is no party tome; 0 (the default) = no floor tomes, the party tome drops instead (each Lich, party_tome_elite of elites, party_tome_urn of urns)."],
	["party_tome_elite", 1.0, 0.0, 1.0, 0.05, "Loot", "Chance an elite drops a party tome (with floor_tomes 0; each Lich always drops one)."],
	["party_tome_urn", 0.02, 0.0, 1.0, 0.01, "Loot", "Chance a broken urn holds a party tome (with floor_tomes 0)."],
	["coin_drop_chance", 0.1, 0.0, 1.0, 0.01, "Loot", "Chance a kill (not an orc or a mage) drops a gold coin."],
	["tome_drop_chance", 0.005, 0.0, 0.2, 0.001, "Loot", "Chance a kill (not an orc or a mage) drops a spell tome (grants or levels that spell)."],
	["big_tome_chance", 0.15, 0.0, 1.0, 0.01, "Loot", "Chance an orc or a mage drops a spell tome beside its gem."],
	["potion_drop_chance", 0.05, 0.0, 0.5, 0.005, "Loot", "Chance a kill (not an orc or a mage) drops a healing potion."],
	["shrine_first", 40.0, 0.0, 600.0, 5.0, "Shrines", "Seconds of fighting before the first gamble shrine."],
	["shrine_interval", 25.0, 5.0, 600.0, 5.0, "Shrines", "Seconds between gamble shrines."],
	["shrine_life", 50.0, 5.0, 120.0, 1.0, "Shrines", "Seconds a shrine waits for a bet before it fades."],
	["shrine_cost_base", 60.0, 0.0, 500.0, 1.0, "Shrines", "Gold a shrine costs in minute 1."],
	["shrine_cost_per_min", 25.0, 0.0, 100.0, 1.0, "Shrines", "Gold added to shrine costs per minute of the run."],
	["shrine_hold", 1.0, 0.2, 5.0, 0.1, "Shrines", "Seconds a wizard who can pay stands on a shrine to bet."],
	["shrine_radius", 14.0, 6.0, 40.0, 1.0, "Shrines", "How close a wizard must stand to use a shrine, px."],
	["shrine_min_dist", 30.0, 0.0, 200.0, 5.0, "Shrines", "Shrines appear at least this far from every wizard, px."],
	["shrine_reel", 1.2, 0.3, 5.0, 0.1, "Shrines", "Seconds a solo shrine's reel spins before the outcome lands."],
	["team_shrine_first", 120.0, 0.0, 900.0, 5.0, "Shrines", "Seconds of fighting before the first team shrine."],
	["team_shrine_interval", 150.0, 10.0, 900.0, 5.0, "Shrines", "Seconds between team shrines."],
	["team_shrine_life_mul", 1.5, 1.0, 5.0, 0.1, "Shrines", "A team shrine waits this many times as long as a solo one."],
	["team_cost_mul", 1.5, 1.0, 10.0, 0.1, "Shrines", "A team shrine costs this many times a solo one; the table shares it, paying into one pot."],
	["team_pay_time", 2.0, 0.2, 10.0, 0.1, "Shrines", "Seconds the wizards standing in a team shrine take to pay its whole price into the pot (when they never run dry)."],
	["team_reel", 3.0, 0.5, 8.0, 0.1, "Shrines", "Seconds the team shrine's reel spins while everyone watches."],
	["boss_every_min", 5.0, 1.0, 20.0, 1.0, "Spawning", "The Lich arrives at the start of every this-many-th minute."],
	["boss_rest_mul", 1.8, 0.25, 5.0, 0.05, "Spawning", "Multiplier on the seconds the Lich and the Archlich drift between attacks."],
	["run_minutes", 15.0, 1.0, 30.0, 1.0, "Run", "Minutes of horde before the Archlich, the final boss, comes. Slaying it wins the run."],
	["final_hp_mul", 3.2, 1.0, 40.0, 0.5, "Run", "The Archlich has this many times the HP the Lich would have on that minute."],
	["victory_delay", 3.0, 0.5, 10.0, 0.5, "Run", "Seconds between the Archlich falling and the results screen."],
	["enemy_hp_per_min", 0.0, 0.0, 0.5, 0.01, "Scaling", "Enemy HP growth per minute: HP x (1 + this x (minute - 1))."],
	["enemy_speed_per_min", 0.05, 0.0, 0.1, 0.005, "Scaling", "Enemy speed growth per minute, up to enemy_speed_min_cap."],
	["enemy_speed_min_cap", 12.0, 1.0, 60.0, 1.0, "Scaling", "Minute after which enemies stop getting faster."],
	["boss_hp_per_player", 0.5, 0.0, 2.0, 0.05, "Scaling", "Lich HP growth per extra wizard."],
	["boss_hp_per_cycle", 2.0, 0.0, 2.0, 0.05, "Scaling", "Lich HP growth each time it returns."],
	["boss_hp_mul", 3.0, 0.1, 20.0, 0.1, "Scaling", "Multiplier on the Lich's (and so the Archlich's) HP."],
	["enemy_hp_per_player", 0.3, 0.0, 2.0, 0.05, "Scaling", "Horde and elite HP growth per extra wizard: HP x (1 + this x (players - 1))."],
	["enemy_shot_cd_mul", 2.0, 0.25, 5.0, 0.05, "Scaling", "Multiplier on the seconds between a skeleton's arrows and a dark mage's volleys."],
	["arrow_speed", 120.0, 40.0, 300.0, 5.0, "Scaling", "Speed of a skeleton's arrow, px/s."],
	["enemy_speed_mul", 0.85, 0.3, 3.0, 0.05, "Scaling", "Multiplier on every enemy's walk speed (the Lich's too)."],
	["mage_orb_speed", 85.0, 30.0, 300.0, 5.0, "Scaling", "Speed of a dark mage's orbs, px/s."],
	["final_hp_per_player", -0.15, -0.3, 1.0, 0.01, "Scaling", "The Archlich's HP changes by this fraction per extra wizard, on top of boss_hp_per_player."],
	["enemy_hp_growth", 1.20, 1.0, 1.5, 0.01, "Scaling", "Compound enemy HP growth per minute on top of enemy_hp_per_min: HP x this ^ (minute - 1)."],
	["enemy_hp_mul", 0.70, 0.1, 10.0, 0.05, "Scaling", "Multiplier on every horde enemy's and elite's HP (not the Lich's: boss_hp_mul)."],
	["xp_first_level", 20.0, 1.0, 200.0, 1.0, "XP", "XP needed to go from level 1 to level 2."],
	["xp_per_level", 55.0, 0.0, 200.0, 1.0, "XP", "Extra XP needed per level beyond the first (linear part)."],
	["xp_growth", 1.04, 1.0, 1.5, 0.01, "XP", "Per-level multiplier on the XP needed (exponential part)."],
	["xp_gem_life", 90.0, 5.0, 120.0, 1.0, "XP", "Seconds an XP gem stays on the floor."],
	["xp_gem_cap", 120.0, 10.0, 1000.0, 10.0, "XP", "Most XP gems on the floor; past it a new gem's XP joins the nearest gem instead."],
	["xp_magnet_radius", 44.0, 8.0, 120.0, 1.0, "XP", "XP gems within this distance fly to a wizard, px (Magnet multiplies it)."],
	["xp_magnet_speed", 170.0, 40.0, 500.0, 5.0, "XP", "Speed of an XP gem flying to a wizard, px/s."],
	["xp_party_scale", 1.0, 0.0, 2.0, 0.05, "XP", "XP a level costs grows by this fraction per extra wizard (the spawn budget grows with the party too)."],
	["pick_shock_radius", 44.0, 0.0, 120.0, 2.0, "XP", "Taking a card pushes every enemy this close to the wizard away, px (no damage). 0 = off."],
	["pick_shock_push", 220.0, 0.0, 600.0, 10.0, "XP", "Knockback of a card's shock, px/s, scaled like other knockback (the Nova's is 260)."],
	["level_choices", 3.0, 1.0, 3.0, 1.0, "XP", "Upgrades offered at each level-up (snapshots and the card tray hold 3)."],
	["head_start_wait", 12.0, 0.0, 60.0, 0.5, "XP", "THE HEAD START holds the intro (no horde, no clock) while a living wizard has a hand to draw, for at most this many seconds of intro (World.time); a wizard who has not drawn by then keeps her draws, as after any level-up."],
	["maxed_level_score", 1000.0, 0.0, 10000.0, 50.0, "XP", "Score given instead of a pick when every upgrade is maxed."],
	["spirit_speed", 45.0, 10.0, 120.0, 1.0, "Fallen", "A fallen wizard's spirit walks this fast, px/s (party of 2+)."],
	["ritual_radius", 30.0, 10.0, 80.0, 1.0, "Fallen", "Radius of the ritual circle on a spirit, px: allies inside raise her."],
	["ritual_hold_radius", 60.0, 10.0, 160.0, 2.0, "Fallen", "The ritual's progress holds while an ally stays this near, px; farther, it drains."],
	["ritual_time", 2.0, 0.25, 8.0, 0.05, "Fallen", "Seconds one ally needs to raise a fallen wizard (two allies take half)."],
	["ritual_step", 0.5, 0.0, 4.0, 0.05, "Fallen", "Seconds each later ritual on the same wizard takes longer."],
	["ritual_drain", 8.0, 0.5, 30.0, 0.5, "Fallen", "Seconds a full ritual circle takes to drain with no ally near."],
	["ritual_push", 80.0, 0.0, 200.0, 2.0, "Fallen", "Enemies this near a spirit are set down this far away when a ritual starts and ends, px."],
	["ritual_safe", 2.0, 0.0, 6.0, 0.1, "Fallen", "Seconds the risen wizard and her raisers are safe from damage."],
	["down_time", 10.0, 1.0, 60.0, 0.5, "Fallen", "Seconds a fallen wizard with more than one life stays down before getting up by herself, for a life."],
	["last_stand", 1.5, 0.0, 10.0, 0.1, "Fallen", "With nobody standing, the longest-down wizard with a life to spare gets up within this many seconds."],
	["call_gap", 2.0, 0.1, 10.0, 0.1, "Fallen", "Seconds between two calls for help (a nova pressed while down)."],
	["return_safe", 2.5, 0.0, 6.0, 0.1, "Fallen", "Seconds safe after getting up by herself."],
	["fate_world_hearts", 2.0, 0.0, 10.0, 1.0, "Fate", "Hearts THE WORLD heals each wizard (the fallen get them when they stand)."],
	["fate_world_pull", 3.0, 0.5, 15.0, 0.5, "Fate", "Seconds every XP gem on the floor flies to the party after THE WORLD."],
	["fate_hanged_secs", 60.0, 5.0, 300.0, 5.0, "Fate", "Seconds THE HANGED MAN seals every wizard's nova."],
	["fate_hierophant_secs", 90.0, 5.0, 300.0, 5.0, "Fate", "Seconds THE HIEROPHANT stops potions dropping."],
	["fate_wheel_draws", 2.0, 1.0, 4.0, 1.0, "Fate", "More fates WHEEL OF FORTUNE draws at once (never itself again in that chain)."],
	["fate_chain_gap", 1.6, 1.6, 5.0, 0.1, "Fate", "Seconds between a fate landing and the next card of its chain being turned (at least the arena's reel show, Arena.REEL_SHOW)."],
	["new_kinds", 1.0, 0.0, 3.0, 0.1, "Spawning", "Multiplier on the act weights of the eight bestiary kinds (bloat to ten of swords) and their formations; 0: they never roll and the horde is exactly the old one."],
	["apprentice_damage", 0.7, 0.0, 1.0, 0.05, "Apprentices", "Multiplier on all damage an apprentice (computer wizard) deals."],
	["apprentice_potion_hp", 2.0, 0.0, 10.0, 1.0, "Apprentices", "An apprentice takes a potion only at this many hearts or fewer, and only when no standing human is hurt."],
	["apprentice_up_time", 6.0, 0.5, 30.0, 0.5, "Apprentices", "Seconds a fallen apprentice stays down before getting up by itself, free (never under DARKNESS)."],
	["seat_silence", 5.0, 1.0, 30.0, 0.5, "Apprentices", "Seconds a human seat's device may stay silent (lobby or run) before an apprentice plays the seat."],
]

static var _shared: Tuning = null

var player_speed: float
var haste_speed_mul: float
var haste_rate_mul: float
var spell_cd_mul: float
var auto_aim_range: float
var star_sweep_arc: float
var horde_start_budget: float
var horde_rate_base: float
var horde_rate_per_min: float
var spawn_party_scale: float
var down_spawn_weight: float
var apprentice_scale: float
var apprentice_damage: float
var apprentice_potion_hp: float
var apprentice_up_time: float
var seat_silence: float
var horde_boss_mul: float
var rift_share: float
var rift_warning: float
var rift_min_dist: float
var leash_x: float
var leash_y: float
var rift_max_dist: float
var door_near_share: float
var enemy_cap: float
var elite_interval: float
var elite_hp_mul: float
var lull_seconds: float
var chest_life: float
var elite_chest_luck: float
var boss_chest_luck: float
var rare_drop_chance: float
var ultra_run_chance: float
var ultra_run_luck: float
var ultra_run_cap: float
var card_run_chance: float
var card_run_urn: float
var loot_moment_from: float
var loot_moment_to: float
var coin_drop_chance: float
var tome_drop_chance: float
var big_tome_chance: float
var potion_drop_chance: float
var urn_count: float
var urn_rare_chance: float
var floor_tomes: float
var party_tome_elite: float
var party_tome_urn: float
var shrine_first: float
var shrine_interval: float
var shrine_life: float
var shrine_cost_base: float
var shrine_cost_per_min: float
var shrine_hold: float
var shrine_radius: float
var shrine_min_dist: float
var shrine_reel: float
var team_shrine_first: float
var team_shrine_interval: float
var team_shrine_life_mul: float
var team_cost_mul: float
var team_pay_time: float
var team_reel: float
var boss_every_min: float
var boss_rest_mul: float
var run_minutes: float
var final_hp_mul: float
var victory_delay: float
var enemy_hp_per_min: float
var enemy_speed_per_min: float
var enemy_speed_min_cap: float
var boss_hp_per_player: float
var boss_hp_per_cycle: float
var boss_hp_mul: float
var enemy_hp_per_player: float
var enemy_shot_cd_mul: float
var arrow_speed: float
var enemy_speed_mul: float
var enemy_hp_growth: float
var mage_orb_speed: float
var final_hp_per_player: float
var enemy_hp_mul: float
var xp_first_level: float
var xp_per_level: float
var xp_growth: float
var xp_gem_life: float
var xp_gem_cap: float
var xp_magnet_radius: float
var xp_magnet_speed: float
var xp_party_scale: float
var pick_shock_radius: float
var pick_shock_push: float
var level_choices: float
var head_start_wait: float
var maxed_level_score: float
var spirit_speed: float
var ritual_radius: float
var ritual_hold_radius: float
var ritual_time: float
var ritual_step: float
var ritual_drain: float
var ritual_push: float
var ritual_safe: float
var down_time: float
var last_stand: float
var call_gap: float
var return_safe: float
var fate_world_hearts: float
var fate_world_pull: float
var fate_hanged_secs: float
var fate_hierophant_secs: float
var fate_wheel_draws: float
var fate_chain_gap: float
var new_kinds: float


func _init() -> void:
	reset()


## The tuning the game uses unless it is given its own. A tuning panel edits this one.
static func shared() -> Tuning:
	if _shared == null:
		_shared = Tuning.new()
	return _shared


## XP needed to go from `level` to `level + 1` (level 1 is the start of a run).
func xp_to_next(level: int) -> int:
	var l: int = maxi(level, 1) - 1
	return int(round((xp_first_level + xp_per_level * l) * pow(xp_growth, l)))


static func field_names() -> PackedStringArray:
	var out := PackedStringArray()
	for f: Array in FIELDS:
		out.append(f[0])
	return out


static func field_info(field: String) -> Dictionary:
	for f: Array in FIELDS:
		if f[0] == field:
			return {"name": f[0], "default": f[1], "min": f[2], "max": f[3], "step": f[4], "group": f[5], "doc": f[6]}
	return {}


func reset() -> void:
	for f: Array in FIELDS:
		set(f[0], float(f[1]))


## Sets one field, clamped to its range. Returns false for an unknown field.
func set_value(field: String, value: float) -> bool:
	var info: Dictionary = field_info(field)
	if info.is_empty():
		return false
	var v: float = clampf(value, float(info["min"]), float(info["max"]))
	set(field, v)
	changed.emit(field, v)
	return true


func to_dict() -> Dictionary:
	var d: Dictionary = {}
	for f: Array in FIELDS:
		d[f[0]] = get(f[0])
	return d


## Applies known keys from `d` (others are ignored). Returns the number of fields applied.
func apply_dict(d: Dictionary) -> int:
	var n: int = 0
	for key: Variant in d:
		if set_value(str(key), float(d[key])):
			n += 1
	return n


## Only the fields that differ from the defaults: what a preset needs to store.
func diff_from_defaults() -> Dictionary:
	var d: Dictionary = {}
	for f: Array in FIELDS:
		if not is_equal_approx(float(get(f[0])), float(f[1])):
			d[f[0]] = get(f[0])
	return d


func copy_from(other: Tuning) -> void:
	apply_dict(other.to_dict())


func save_json(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t", false))
	return OK


## Loads a preset file over the current values. Returns false if the file is missing or not a JSON object.
func load_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	apply_dict(parsed)
	return true

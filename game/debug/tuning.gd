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
	["horde_start_budget", 10.0, 0.0, 100.0, 1.0, "Spawning", "Spawn budget the horde starts with, so the first enemies come at once."],
	["horde_rate_base", 10.0, 0.0, 40.0, 0.1, "Spawning", "Spawn budget earned per second at the start of a run (a goblin costs 1, an orc 9)."],
	["horde_rate_per_min", 10.0, 0.0, 20.0, 0.1, "Spawning", "Spawn budget per second added for each minute survived."],
	["spawn_party_scale", 1.1, 0.0, 1.5, 0.05, "Spawning", "Extra budget per extra wizard: budget x (1 + this x (players - 1))."],
	["horde_boss_mul", 0.35, 0.0, 1.0, 0.05, "Spawning", "Spawn budget multiplier while the Lich is alive."],
	["rift_share", 0.6, 0.0, 1.0, 0.05, "Spawning", "Share of horde groups that open a rift in the arena instead of coming through a door."],
	["rift_warning", 0.9, 0.2, 3.0, 0.05, "Spawning", "Seconds a rift's marker shows before its enemies appear."],
	["rift_min_dist", 90.0, 30.0, 200.0, 5.0, "Spawning", "Rifts open at least this far from every wizard, px."],
	["enemy_cap", 260.0, 20.0, 600.0, 10.0, "Spawning", "Most enemies alive at once; the horde holds its budget while at the cap."],
	["elite_interval", 45.0, 5.0, 300.0, 5.0, "Spawning", "Seconds between elite spawns (a big glowing orc or mage that drops loot)."],
	["elite_hp_mul", 8.0, 1.0, 30.0, 0.5, "Spawning", "Elite HP as a multiple of a normal enemy of its type."],
	["chest_life", 40.0, 5.0, 300.0, 5.0, "Loot", "Seconds a chest stays on the floor."],
	["elite_chest_luck", 1.0, 0.0, 5.0, 1.0, "Loot", "Luck of an elite's chest (each point moves a fifth of the common odds up the tiers)."],
	["boss_chest_luck", 3.0, 0.0, 5.0, 1.0, "Loot", "Luck of the chests the Lich drops, one per wizard."],
	["rare_drop_chance", 0.0015, 0.0, 0.1, 0.0005, "Loot", "Chance any kill drops a rare chest (blue, opens rare or better)."],
	["ultra_drop_chance", 0.0002, 0.0, 0.01, 0.0001, "Loot", "Chance any kill drops an ultra-rare chest (prismatic, opens legendary or better)."],
	["card_chance", 0.0004, 0.0, 0.05, 0.0001, "Loot", "Chance a kill drops that monster's card (ultra rare, kept between runs)."],
	["card_elite_mul", 25.0, 1.0, 100.0, 1.0, "Loot", "An elite's card chance as a multiple of card_chance."],
	["urn_count", 5.0, 0.0, 20.0, 1.0, "Loot", "Urns standing along the arena walls; broken ones are replaced each minute."],
	["urn_card_chance", 0.004, 0.0, 0.1, 0.001, "Loot", "Chance an urn holds a monster card (any kind)."],
	["urn_rare_chance", 0.03, 0.0, 0.5, 0.01, "Loot", "Chance an urn holds a rare chest."],
	["card_boss_chance", 0.25, 0.0, 1.0, 0.05, "Loot", "Chance a slain Lich or the Archlich drops the Lich card."],
	["shrine_first", 40.0, 0.0, 600.0, 5.0, "Shrines", "Seconds of fighting before the first gamble shrine."],
	["shrine_interval", 60.0, 5.0, 600.0, 5.0, "Shrines", "Seconds between gamble shrines."],
	["shrine_life", 30.0, 5.0, 120.0, 1.0, "Shrines", "Seconds a shrine waits for a bet before it fades."],
	["shrine_cost_base", 15.0, 0.0, 500.0, 1.0, "Shrines", "Gold a shrine costs in minute 1."],
	["shrine_cost_per_min", 6.0, 0.0, 100.0, 1.0, "Shrines", "Gold added to shrine costs per minute of the run."],
	["shrine_hold", 1.0, 0.2, 5.0, 0.1, "Shrines", "Seconds a wizard who can pay stands on a shrine to bet."],
	["shrine_radius", 14.0, 6.0, 40.0, 1.0, "Shrines", "How close a wizard must stand to use a shrine, px."],
	["shrine_min_dist", 50.0, 0.0, 200.0, 5.0, "Shrines", "Shrines appear at least this far from every wizard, px."],
	["shrine_reel", 1.2, 0.3, 5.0, 0.1, "Shrines", "Seconds a solo shrine's reel spins before the outcome lands."],
	["team_shrine_first", 120.0, 0.0, 900.0, 5.0, "Shrines", "Seconds of fighting before the first team shrine."],
	["team_shrine_interval", 150.0, 10.0, 900.0, 5.0, "Shrines", "Seconds between team shrines."],
	["team_shrine_life_mul", 1.5, 1.0, 5.0, 0.1, "Shrines", "A team shrine waits this many times as long as a solo one."],
	["team_cost_mul", 2.5, 1.0, 10.0, 0.1, "Shrines", "A team shrine costs this many times a solo one; one wizard pays it all."],
	["team_reel", 3.0, 0.5, 8.0, 0.1, "Shrines", "Seconds the team shrine's reel spins while everyone watches."],
	["boss_every_min", 5.0, 1.0, 20.0, 1.0, "Spawning", "The Lich arrives at the start of every this-many-th minute."],
	["run_minutes", 15.0, 1.0, 30.0, 1.0, "Run", "Minutes of horde before the Archlich, the final boss, comes. Slaying it wins the run."],
	["final_hp_mul", 10.0, 1.0, 40.0, 0.5, "Run", "The Archlich has this many times the HP the Lich would have on that minute."],
	["victory_delay", 3.0, 0.5, 10.0, 0.5, "Run", "Seconds between the Archlich falling and the results screen."],
	["enemy_hp_per_min", 0.35, 0.0, 0.5, 0.01, "Scaling", "Enemy HP growth per minute: HP x (1 + this x (minute - 1))."],
	["enemy_speed_per_min", 0.03, 0.0, 0.1, 0.005, "Scaling", "Enemy speed growth per minute, up to enemy_speed_min_cap."],
	["enemy_speed_min_cap", 12.0, 1.0, 60.0, 1.0, "Scaling", "Minute after which enemies stop getting faster."],
	["boss_hp_per_player", 0.6, 0.0, 2.0, 0.05, "Scaling", "Lich HP growth per extra wizard."],
	["boss_hp_per_cycle", 0.25, 0.0, 2.0, 0.05, "Scaling", "Lich HP growth each time it returns."],
	["xp_first_level", 20.0, 1.0, 200.0, 1.0, "XP", "XP needed to go from level 1 to level 2."],
	["xp_per_level", 60.0, 0.0, 200.0, 1.0, "XP", "Extra XP needed per level beyond the first (linear part)."],
	["xp_growth", 1.04, 1.0, 1.5, 0.01, "XP", "Per-level multiplier on the XP needed (exponential part)."],
	["xp_gem_life", 30.0, 5.0, 120.0, 1.0, "XP", "Seconds an XP gem stays on the floor."],
	["xp_gem_cap", 120.0, 10.0, 1000.0, 10.0, "XP", "Most XP gems on the floor; past it a new gem's XP joins the nearest gem instead."],
	["xp_magnet_radius", 24.0, 8.0, 120.0, 1.0, "XP", "XP gems within this distance fly to a wizard, px (Magnet multiplies it)."],
	["xp_magnet_speed", 170.0, 40.0, 500.0, 5.0, "XP", "Speed of an XP gem flying to a wizard, px/s."],
	["level_choices", 3.0, 1.0, 3.0, 1.0, "XP", "Upgrades offered at each level-up (snapshots and the pick screen hold 3)."],
	["maxed_level_score", 1000.0, 0.0, 10000.0, 50.0, "XP", "Score given instead of a pick when every upgrade is maxed."],
]

static var _shared: Tuning = null

var player_speed: float
var haste_speed_mul: float
var haste_rate_mul: float
var spell_cd_mul: float
var auto_aim_range: float
var horde_start_budget: float
var horde_rate_base: float
var horde_rate_per_min: float
var spawn_party_scale: float
var horde_boss_mul: float
var rift_share: float
var rift_warning: float
var rift_min_dist: float
var enemy_cap: float
var elite_interval: float
var elite_hp_mul: float
var chest_life: float
var elite_chest_luck: float
var boss_chest_luck: float
var rare_drop_chance: float
var ultra_drop_chance: float
var card_chance: float
var card_elite_mul: float
var card_boss_chance: float
var urn_count: float
var urn_card_chance: float
var urn_rare_chance: float
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
var team_reel: float
var boss_every_min: float
var run_minutes: float
var final_hp_mul: float
var victory_delay: float
var enemy_hp_per_min: float
var enemy_speed_per_min: float
var enemy_speed_min_cap: float
var boss_hp_per_player: float
var boss_hp_per_cycle: float
var xp_first_level: float
var xp_per_level: float
var xp_growth: float
var xp_gem_life: float
var xp_gem_cap: float
var xp_magnet_radius: float
var xp_magnet_speed: float
var level_choices: float
var maxed_level_score: float


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

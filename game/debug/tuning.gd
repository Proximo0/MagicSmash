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
	["cast_cd_arcane", 0.11, 0.03, 1.0, 0.01, "Casting", "Seconds between Arcane Bolt casts."],
	["cast_cd_fire", 0.27, 0.05, 2.0, 0.01, "Casting", "Seconds between Fireball casts."],
	["cast_cd_frost", 0.21, 0.05, 2.0, 0.01, "Casting", "Seconds between Frost Fan casts."],
	["cast_cd_storm", 0.15, 0.05, 2.0, 0.01, "Casting", "Seconds between Chain Lightning casts."],
	["cast_cd_star", 0.2, 0.05, 2.0, 0.01, "Casting", "Seconds between Starfall casts."],
	["spawn_budget_base", 18.0, 0.0, 200.0, 1.0, "Spawning", "Spawn budget of a wave before wave and party scaling (a goblin costs 1, an orc 9)."],
	["spawn_budget_per_wave", 9.0, 0.0, 100.0, 0.5, "Spawning", "Spawn budget added per wave."],
	["spawn_party_scale", 0.55, 0.0, 1.5, 0.05, "Spawning", "Extra budget per extra wizard: budget x (1 + this x (players - 1))."],
	["spawn_gap_per_wave", 0.04, 0.0, 0.2, 0.005, "Spawning", "How much shorter the gap between spawn groups gets per wave (fraction)."],
	["spawn_gap_min", 0.5, 0.1, 1.0, 0.05, "Spawning", "Shortest spawn gap, as a fraction of the wave-1 gap."],
	["enemy_hp_per_wave", 0.07, 0.0, 0.5, 0.01, "Scaling", "Enemy HP growth per wave: HP x (1 + this x (wave - 1))."],
	["enemy_speed_per_wave", 0.02, 0.0, 0.1, 0.005, "Scaling", "Enemy speed growth per wave, up to enemy_speed_wave_cap."],
	["enemy_speed_wave_cap", 15.0, 1.0, 60.0, 1.0, "Scaling", "Wave after which enemies stop getting faster."],
	["boss_hp_per_player", 0.6, 0.0, 2.0, 0.05, "Scaling", "Lich HP growth per extra wizard."],
	["boss_hp_per_cycle", 0.25, 0.0, 2.0, 0.05, "Scaling", "Lich HP growth each time it returns (every 5th wave)."],
	["xp_first_level", 6.0, 1.0, 100.0, 1.0, "XP", "XP needed to go from level 1 to level 2."],
	["xp_per_level", 3.0, 0.0, 50.0, 0.5, "XP", "Extra XP needed per level beyond the first (linear part)."],
	["xp_growth", 1.12, 1.0, 1.5, 0.01, "XP", "Per-level multiplier on the XP needed (exponential part)."],
	["xp_gem_life", 30.0, 5.0, 120.0, 1.0, "XP", "Seconds an XP gem stays on the floor."],
	["xp_magnet_radius", 24.0, 8.0, 120.0, 1.0, "XP", "XP gems within this distance fly to a wizard, px (Magnet multiplies it)."],
	["xp_magnet_speed", 170.0, 40.0, 500.0, 5.0, "XP", "Speed of an XP gem flying to a wizard, px/s."],
	["level_choices", 3.0, 1.0, 3.0, 1.0, "XP", "Upgrades offered at each level-up (snapshots and the pick screen hold 3)."],
	["maxed_level_score", 1000.0, 0.0, 10000.0, 50.0, "XP", "Score given instead of a pick when every upgrade is maxed."],
]

static var _shared: Tuning = null

var player_speed: float
var haste_speed_mul: float
var haste_rate_mul: float
var cast_cd_arcane: float
var cast_cd_fire: float
var cast_cd_frost: float
var cast_cd_storm: float
var cast_cd_star: float
var spawn_budget_base: float
var spawn_budget_per_wave: float
var spawn_party_scale: float
var spawn_gap_per_wave: float
var spawn_gap_min: float
var enemy_hp_per_wave: float
var enemy_speed_per_wave: float
var enemy_speed_wave_cap: float
var boss_hp_per_player: float
var boss_hp_per_cycle: float
var xp_first_level: float
var xp_per_level: float
var xp_growth: float
var xp_gem_life: float
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


## Cast cooldown of a spell, by World.SP_* index (arcane, fire, frost, storm, star).
func cast_cd(spell: int) -> float:
	match spell:
		World.SP_FIRE:
			return cast_cd_fire
		World.SP_FROST:
			return cast_cd_frost
		World.SP_STORM:
			return cast_cd_storm
		World.SP_STAR:
			return cast_cd_star
	return cast_cd_arcane


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

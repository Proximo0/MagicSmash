class_name Loot
extends RefCounted
## In-run loot: rarity tiers, the chest item table and run gold values. Pure data plus seeded rolls; World opens
## chests and applies what they give. Everything here is earned in play (see docs/handoff.md, loot rules):
## nothing is bought, and run gold only exists inside a run.

const COMMON := 0
const RARE := 1
const EPIC := 2
const LEGENDARY := 3
const ULTRA := 4

const RARITY_NAMES := ["COMMON", "RARE", "EPIC", "LEGENDARY", "ULTRA RARE"]
## Chance weights per tier. A chest's luck (elites, the Lich) shifts weight up the tiers. LEGENDARY is the tier a
## lucky run sees (about 1 run in 6, solo); ULTRA RARE has no weight: it is never rolled in a chest, only given by
## the one prismatic chest of an ULTRA RARE run (run_rolls, World.ultra_run).
const RARITY_WEIGHTS := [60.0, 26.0, 10.0, 0.3, 0.0]
## How much stronger an item of each tier is than a common one.
const RARITY_MUL := [1.0, 1.5, 2.0, 3.0, 5.0]

const KIND_ARMOR := 0
const KIND_CONSUMABLE := 1

## Armor stats a wizard collects for the rest of the run (World adds them up per player).
const ST_MIGHT := 0 # damage, fraction added
const ST_FOCUS := 1 # spell cooldown, fraction removed
const ST_SWIFT := 2 # move speed, fraction added
const ST_VIGOR := 3 # max hearts added
const ST_WARD := 4 # chance to shrug off a hit
const ST_GREED := 5 # run gold, fraction added
const STAT_COUNT := 6

## Consumable effects, used the moment the chest opens.
const FX_ELIXIR := 0 # heal to full
const FX_NOVAS := 1 # + novas
const FX_TOME := 2 # levels a random owned spell weapon that is not maxed
const FX_INSIGHT := 3 # XP worth this fraction of the current level

## [key, name, kind, stat or effect, base value, weight, flat]. Indices are sent in events, so append new items at
## the end. An armor's value is base x RARITY_MUL[tier]; vigor rounds to whole hearts. `flat`: the item does the
## same at every tier (the ELIXIR heals to full), so a LEGENDARY or ULTRA RARE chest never rolls it (roll_item).
const ITEMS: Array = [
	["might", "GAUNTLETS OF TYR", KIND_ARMOR, ST_MIGHT, 0.08, 10.0, false],
	["focus", "CIRCLET OF THOTH", KIND_ARMOR, ST_FOCUS, 0.05, 10.0, false],
	["swift", "HERMES' SANDALS", KIND_ARMOR, ST_SWIFT, 0.05, 8.0, false],
	["vigor", "TROLL HIDE", KIND_ARMOR, ST_VIGOR, 1.0, 6.0, false],
	["ward", "AEGIS CLOAK", KIND_ARMOR, ST_WARD, 0.06, 7.0, false],
	["greed", "MISER'S RING", KIND_ARMOR, ST_GREED, 0.15, 6.0, false],
	["elixir", "ELIXIR", KIND_CONSUMABLE, FX_ELIXIR, 1.0, 8.0, true],
	["novas", "NOVA FLASK", KIND_CONSUMABLE, FX_NOVAS, 1.0, 7.0, false],
	["tome", "SIBYLLINE BOOK", KIND_CONSUMABLE, FX_TOME, 1.0, 7.0, false],
	["insight", "EYE OF ODIN", KIND_CONSUMABLE, FX_INSIGHT, 0.5, 6.0, false],
]
const I_WEIGHT := 5
const I_FLAT := 6

## Caps so stacked armor stays sane: [might, focus, swift, vigor, ward, greed].
const STAT_CAPS := [2.0, 0.5, 0.6, 5.0, 0.5, 3.0]

## Run gold per pickup kind.
const GOLD_COIN := 1
const GOLD_GEM := 5


static func count() -> int:
	return ITEMS.size()


static func item_name(idx: int) -> String:
	return ITEMS[idx][1]


static func kind(idx: int) -> int:
	return int(ITEMS[idx][2])


static func effect(idx: int) -> int:
	return int(ITEMS[idx][3])


## True for an item that does the same at every tier (ITEMS' flat column).
static func flat(idx: int) -> bool:
	return bool(ITEMS[idx][I_FLAT])


## The tier of a new chest, COMMON to LEGENDARY (never ULTRA). `luck` 0 is a plain chest; each point of luck
## moves a fifth of the common weight onto the tiers above it, so luck 5 never rolls common.
static func roll_rarity(rng: RandomNumberGenerator, luck: float) -> int:
	var w: Array = RARITY_WEIGHTS.slice(0, LEGENDARY + 1)
	var moved: float = float(w[COMMON]) * clampf(luck / 5.0, 0.0, 1.0)
	w[COMMON] = float(w[COMMON]) - moved
	var up: float = 0.0
	for t: int in range(RARE, LEGENDARY + 1):
		up += float(RARITY_WEIGHTS[t])
	for t: int in range(RARE, LEGENDARY + 1):
		w[t] = float(w[t]) + moved * float(RARITY_WEIGHTS[t]) / up
	var total: float = 0.0
	for v: float in w:
		total += v
	var r: float = rng.randf() * total
	for t: int in range(w.size()):
		r -= float(w[t])
		if r < 0.0:
			return t
	return LEGENDARY


## Mixed into the run's seed for its own loot stream (run_stream), so that stream never repeats the main one.
const RUN_SALT := 0x51DE_C0DE


## The run's own loot stream, seeded by the run's seed: the main stream (World.rng) never feeds it, so drawing
## from it leaves the rest of the run as it was.
static func run_stream(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value ^ RUN_SALT
	return r


## The run's loot draws, decided once when the run starts from its own stream (run_stream): "ultra" and "card"
## are uniform draws that make the run an ULTRA RARE run or a card run when below that chance (ultra_run_chance,
## Cards.card_run_chance); "ultra_at" and "card_at" are uniform draws for each one's moment (moment); "card_urn" a
## uniform draw for whether a card run's card waits in an urn (Tuning.card_run_urn); "card_kind" a uniform draw for
## which card a card run gives (WorldDrops.run_card), drawn last so every other key keeps its value for every seed.
## The same seed always gives the same draws.
static func run_rolls(r: RandomNumberGenerator) -> Dictionary:
	var ultra := r.randf()
	var ultra_at := r.randf()
	var card := r.randf()
	var card_at := r.randf()
	var card_urn := r.randf()
	return {"ultra": ultra, "ultra_at": ultra_at, "card": card, "card_at": card_at, "card_urn": card_urn,
		"card_kind": r.randf()}


## The chance a run is an ULTRA RARE run: `base`, plus `per_luck` for each point of the run's chest luck (meta
## unlocks and the Seal), never above `cap` (nor below base). Numbers from Tuning.
static func ultra_run_chance(base: float, luck: float, per_luck: float, cap: float) -> float:
	return clampf(base + per_luck * maxf(luck, 0.0), 0.0, maxf(cap, base))


## Seconds into a run of a seeded moment: the draw `u` (0..1) placed between the shares `from` and `to` of a run
## that lasts `run_seconds` up to the Archlich.
static func moment(u: float, from: float, to: float, run_seconds: float) -> float:
	return lerpf(from, to, clampf(u, 0.0, 1.0)) * run_seconds


## A chest item index for a chest of `tier`, drawn by weight with one draw. At LEGENDARY and above a flat item (the
## same at every tier) has no weight; below it every item keeps its weight, so every seed rolls what it always did.
static func roll_item(rng: RandomNumberGenerator, tier: int = COMMON) -> int:
	var total: float = 0.0
	for i: int in range(ITEMS.size()):
		total += _item_weight(i, tier)
	var r: float = rng.randf() * total
	var last := ITEMS.size() - 1
	for i: int in range(ITEMS.size()):
		var wt := _item_weight(i, tier)
		if wt <= 0.0:
			continue
		last = i
		r -= wt
		if r < 0.0:
			return i
	return last


## Item `idx`'s weight in a chest of `tier` (roll_item).
static func _item_weight(idx: int, tier: int) -> float:
	if tier >= LEGENDARY and flat(idx):
		return 0.0
	return float(ITEMS[idx][I_WEIGHT])


## The item's value at `tier`: an armor stat amount, or a consumable's strength.
static func value(idx: int, tier: int) -> float:
	var v: float = float(ITEMS[idx][4]) * float(RARITY_MUL[tier])
	if kind(idx) == KIND_ARMOR and effect(idx) == ST_VIGOR:
		return maxf(1.0, floorf(v))
	return v


## Adds an armor item to a wizard's stat totals (an Array of STAT_COUNT floats), respecting STAT_CAPS.
static func add_armor(stats: Array, idx: int, tier: int) -> void:
	var st: int = effect(idx)
	stats[st] = minf(float(STAT_CAPS[st]), float(stats[st]) + value(idx, tier))


static func empty_stats() -> Array:
	var out: Array = []
	out.resize(STAT_COUNT)
	out.fill(0.0)
	return out

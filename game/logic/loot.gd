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
## Chance weights per tier. A chest's luck (elites, the Lich) shifts weight up the tiers.
const RARITY_WEIGHTS := [60.0, 26.0, 10.0, 3.4, 0.6]
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

## [key, name, kind, stat or effect, base value, weight]. Indices are sent in events, so append new items at the
## end. An armor's value is base x RARITY_MUL[tier]; vigor rounds to whole hearts.
const ITEMS: Array = [
	["might", "GAUNTLETS OF TYR", KIND_ARMOR, ST_MIGHT, 0.08, 10.0],
	["focus", "CIRCLET OF THOTH", KIND_ARMOR, ST_FOCUS, 0.05, 10.0],
	["swift", "HERMES' SANDALS", KIND_ARMOR, ST_SWIFT, 0.05, 8.0],
	["vigor", "TROLL HIDE", KIND_ARMOR, ST_VIGOR, 1.0, 6.0],
	["ward", "AEGIS CLOAK", KIND_ARMOR, ST_WARD, 0.06, 7.0],
	["greed", "MISER'S RING", KIND_ARMOR, ST_GREED, 0.15, 6.0],
	["elixir", "ELIXIR", KIND_CONSUMABLE, FX_ELIXIR, 1.0, 8.0],
	["novas", "NOVA FLASK", KIND_CONSUMABLE, FX_NOVAS, 1.0, 7.0],
	["tome", "SIBYLLINE BOOK", KIND_CONSUMABLE, FX_TOME, 1.0, 7.0],
	["insight", "EYE OF ODIN", KIND_CONSUMABLE, FX_INSIGHT, 0.5, 6.0],
]

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


## The tier of a new chest. `luck` 0 is a plain chest; each point of luck moves a fifth of the common weight
## onto the tiers above it, so luck 5 never rolls common.
static func roll_rarity(rng: RandomNumberGenerator, luck: float) -> int:
	var w: Array = RARITY_WEIGHTS.duplicate()
	var moved: float = float(w[COMMON]) * clampf(luck / 5.0, 0.0, 1.0)
	w[COMMON] = float(w[COMMON]) - moved
	var up: float = 0.0
	for t: int in range(RARE, ULTRA + 1):
		up += float(RARITY_WEIGHTS[t])
	for t: int in range(RARE, ULTRA + 1):
		w[t] = float(w[t]) + moved * float(RARITY_WEIGHTS[t]) / up
	var total: float = 0.0
	for v: float in w:
		total += v
	var r: float = rng.randf() * total
	for t: int in range(w.size()):
		r -= float(w[t])
		if r < 0.0:
			return t
	return ULTRA


## A chest item index, drawn by weight.
static func roll_item(rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for row: Array in ITEMS:
		total += float(row[5])
	var r: float = rng.randf() * total
	for i: int in range(ITEMS.size()):
		r -= float(ITEMS[i][5])
		if r < 0.0:
			return i
	return ITEMS.size() - 1


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

class_name FieldAnim
extends RefCounted
## What a figure is doing, and how to draw it: pure statics, no allocation per call.
## State comes from the entity's flags (hurt, attacking, alive); a strip (`atk` 3 frames, `hit` 1, `die` 3 in the
## FieldArt entry) plays when the art has one, else a code fallback: a white hit flash, a death fade with a tilt.

const IDLE: int = 0
const WALK: int = 1
const ATTACK: int = 2
const HIT: int = 3
const DIE: int = 4

const ATK_FRAMES: int = 3
const DIE_FRAMES: int = 3
## Seconds the hit and attack poses last, and the death's fade and fall.
const HIT_S: float = 0.15
const ATK_S: float = 0.3
const DIE_S: float = 0.6
const DIE_TILT: float = 1.2
const FLASH: Color = Color(3.0, 3.0, 3.0, 1.0)


## The state: death wins, then a fresh hit, then an attack, then walking.
static func state_of(alive: bool, since_hit: float, since_atk: float, moving: bool) -> int:
	if not alive:
		return DIE
	if since_hit < HIT_S:
		return HIT
	if since_atk < ATK_S:
		return ATTACK
	return WALK if moving else IDLE


## The strip for a state, or null when the entry has none (the walk/still picture is used).
static func strip_for(entry: Dictionary, state: int) -> Texture2D:
	match state:
		ATTACK:
			return entry.get("atk") as Texture2D
		HIT:
			return entry.get("hit") as Texture2D
		DIE:
			return entry.get("die") as Texture2D
	return null


## Frame index inside a strip of `n` frames for `t` seconds into a pose lasting `len`; holds on the last frame.
static func frame_at(t: float, len: float, n: int) -> int:
	return clampi(int(t / len * float(n)), 0, n - 1)


## The colour to draw with: a white flash while hit and the art has no hit strip, a fade from white to `base` (the
## dead colour) when dead (with a die strip too, so a corpse reads as one), plain white otherwise.
static func tint(state: int, has_strip: bool, since_death: float, base: Color) -> Color:
	if state == HIT and not has_strip:
		return FLASH
	if state == DIE:
		return Color.WHITE.lerp(base, clampf(since_death / DIE_S, 0.0, 1.0))
	return Color.WHITE


## The tilt (radians) of a dead figure with no die strip: falls over once, then holds.
static func tilt(state: int, has_strip: bool, since_death: float, flip: bool) -> float:
	if state != DIE or has_strip:
		return 0.0
	var a: float = DIE_TILT * clampf(since_death / DIE_S, 0.0, 1.0)
	return -a if flip else a

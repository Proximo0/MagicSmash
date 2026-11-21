class_name EnemyView
extends RefCounted
## How each enemy type looks, by Bestiary type id: its walk or hover cycle (KEYS, stepped at ANIM frames a second),
## the width of the shadow `_draw_entities` puts under it (SHADOW, 0: none there) and its name on banners.
## `_draw_enemy` swaps in the frame of a hop, a wind-up, a cast or a swoop. The reserved kinds show one stand-in
## frame each (SpritesEnemies.STAND_INS) until their own art lands.

const KEYS: Array = [["goblin_a", "goblin_c", "goblin_b", "goblin_d"], ["skeleton_a", "skeleton_c", "skeleton_b", "skeleton_d"],
	["slime_a"], ["mslime_a", "mslime_c", "mslime_a", "mslime_b"], ["bat_a", "bat_c", "bat_b", "bat_d"],
	["orc_a", "orc_c", "orc_b", "orc_c"], ["mage_a", "mage_b"], ["lich", "lich_b"], ["wraith_a", "wraith_b"],
	["tome_a", "tome_b", "tome_c", "tome_b"], ["gargoyle_b", "gargoyle_c"], ["priest_a", "priest_b"],
	["bloat_a"], ["coffin_a"], ["guard_a"], ["cinderling_a"], ["censor_a"], ["hound_a"], ["shard_a"], ["swords_a"],
	["chandelier_a"], ["ghostwriter_a"]]
## The wraith has none; the bat, the tome and the swooping gargoyle get theirs from `_draw_enemy_glows`.
const SHADOW: Array = [10, 10, 12, 8, 0, 16, 10, 26, 0, 0, 16, 10, 14, 14, 14, 10, 12, 14, 14, 12, 0, 0]
const ANIM: Array = [10.0, 7.0, 0.0, 7.0, 14.0, 5.0, 2.5, 3.0, 3.0, 10.0, 7.0, 3.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
const NAMES: Array = ["GOBLIN", "SKELETON", "SLIME", "SLIMELING", "BAT", "ORC BRUTE", "DARK MAGE", "LICH LORD", "WRAITH", "CURSED TOME",
	"GARGOYLE", "BONE PRIEST", "BLOAT", "RESTLESS COFFIN", "TOMB GUARD", "CINDERLING", "THE CENSOR", "ASH HOUND", "COMET SHARD",
	"TEN OF SWORDS", "THE BONE CHANDELIER", "THE GHOST WRITER"]

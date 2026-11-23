"""Dress a generated body in script-built armour, give it the free pack's weapons and animations, render raw frames.

    python3 -I build_hero.py -- <body.glb> <anim.glb> <outdir> <kit> <Action:frames,...>

The body (MPFB, game_engine rig) is coloured by region and armour pieces are shells cut from the body by bone weights and
pushed out along the normals, so they follow the same skeleton.  Weapons come from the animation pack's glb and are
re-hung on the body's hands.  Poses are copied from the pack's rig with retarget.py.  Output is what post.py reads.
env: RES (448), ORTHO (3.57), YAW (-70), ELEV (20), SAMPLES (32), STILL=1 (one big rest-pose picture only)
"""
import json
import math
import os
import sys

import bpy
import bmesh  # noqa: E402 (after bpy)
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import retarget as rt  # noqa: E402

body_glb, anim_glb, out, kit_name, acts = sys.argv[sys.argv.index("--") + 1:]
E = os.environ.get

FINGERS = ["%s_0%d_%s" % (f, i, s) for f in ("index", "middle", "ring", "pinky", "thumb") for i in (1, 2, 3) for s in "lr"]
REGION = {
    "head": ["head"], "neck": ["neck_01"],
    "chest": ["spine_02", "spine_03", "clavicle_l", "clavicle_r"], "belly": ["spine_01"], "hips": ["pelvis"],
    "upperarm": ["upperarm_l", "upperarm_r"], "lowerarm": ["lowerarm_l", "lowerarm_r"],
    "hand": ["hand_l", "hand_r"] + FINGERS,
    "thigh": ["thigh_l", "thigh_r"], "calf": ["calf_l", "calf_r"], "foot": ["foot_l", "foot_r", "ball_l", "ball_r"],
}
STEEL, STEEL_D, STEEL_L = (0.24, 0.26, 0.31), (0.11, 0.12, 0.15), (0.42, 0.44, 0.5)
CRIMSON, LEATHER, LEATHER_D, MAIL = (0.3, 0.02, 0.03), (0.16, 0.09, 0.05), (0.06, 0.04, 0.03), (0.2, 0.2, 0.23)
PALLID, SACK, STRAW = (0.36, 0.4, 0.33), (0.42, 0.33, 0.2), (0.6, 0.48, 0.16)
GOLD, BONE = (0.72, 0.52, 0.16), (0.78, 0.74, 0.62)
RACE = E("RACE", "human")                        # race = body + skin colour + a head feature that reads at 56 px
SKIN = {"orc": (0.13, 0.25, 0.07), "elf": (0.56, 0.42, 0.35), "dwarf": (0.5, 0.3, 0.22)}.get(RACE, (0.55, 0.36, 0.27))

# kit: skin colours by region (default first), shells (regions, thickness m, colour, metallic, optional filter),
# extras built in code, weapons {object in the pack: (hand bone, scale)}
KITS = {
    "knight": dict(
        skin={"*": MAIL, "head": SKIN, "neck": SKIN, "hand": LEATHER_D},
        shells=[
            (["neck"], 0.030, STEEL_D, 1.0, None),
            (["chest", "belly"], 0.030, STEEL, 1.0, None),
            (["hips"], 0.030, STEEL_D, 1.0, None),
            (["chest", "belly"], 0.045, CRIMSON, 0.0, "tabard"),
            (["belly"], 0.058, LEATHER_D, 0.0, "belt"),
            (["upperarm"], 0.020, STEEL_D, 1.0, None),
            (["lowerarm"], 0.022, STEEL, 1.0, None),
            (["thigh"], 0.022, STEEL_D, 1.0, None),
            (["calf"], 0.026, STEEL, 1.0, None),
        ],
        extras=["pauldrons", "helm", "cape", "knees", "gauntlets", "boots", "skirt", "cross", "buckle"],
        boot=STEEL_D, gauntlet=STEEL_D, skirt=CRIMSON,
        cape=CRIMSON, pauldron=(STEEL_L, 0.115, False),
        weapons={"1H_Sword": ("hand_r", (0.42, 0.6, 0.74)), "Rectangle_Shield": ("hand_l", (0.52, 0.52, 0.56))},
    ),
    "novice": dict(
        skin={"*": (0.2, 0.2, 0.16), "head": SKIN, "neck": SKIN, "hand": SKIN, "lowerarm": SKIN},
        shells=[
            (["chest", "belly", "hips", "upperarm"], 0.022, (0.26, 0.22, 0.13), 0.0, None),
            (["belly"], 0.04, LEATHER_D, 0.0, "belt"),
            (["thigh"], 0.018, (0.1, 0.1, 0.12), 0.0, None),
            (["calf"], 0.026, LEATHER, 0.0, None),
        ],
        extras=["hair", "boots", "buckle"], boot=LEATHER, hair=(0.12, 0.07, 0.04),
        weapons={"Knife": ("hand_r", (0.5, 0.5, 0.6))},
    ),
    "mage": dict(
        skin={"*": (0.07, 0.05, 0.16), "head": SKIN, "neck": SKIN, "hand": SKIN},
        shells=[
            (["chest", "belly", "hips", "upperarm", "lowerarm"], 0.03, (0.09, 0.05, 0.22), 0.0, None),
            (["belly"], 0.05, GOLD, 1.0, "belt"),
            (["chest", "belly"], 0.045, (0.2, 0.12, 0.36), 0.0, "tabard"),
        ],
        extras=["hood", "skirt", "boots"], boot=LEATHER_D, hood=(0.09, 0.05, 0.22), skirt=(0.09, 0.05, 0.22), skirt_to=0.12,
        weapons={"2H_Staff": ("hand_r", (0.6, 0.6, 0.8))},
    ),
    "archer": dict(
        skin={"*": (0.1, 0.1, 0.1), "head": SKIN, "neck": SKIN, "hand": LEATHER_D},
        shells=[
            (["chest", "belly", "hips"], 0.026, LEATHER, 0.0, None),
            (["belly"], 0.044, LEATHER_D, 0.0, "belt"),
            (["upperarm"], 0.018, (0.1, 0.2, 0.1), 0.0, None),
            (["lowerarm"], 0.024, LEATHER_D, 0.0, None),
            (["thigh"], 0.018, (0.11, 0.13, 0.1), 0.0, None),
            (["calf"], 0.028, LEATHER_D, 0.0, None),
        ],
        extras=["hood", "cape", "boots", "quiver"], boot=LEATHER_D, hood=(0.1, 0.2, 0.1), cape=(0.1, 0.2, 0.1), cape_len=0.6,
        weapons={"2H_Crossbow": ("hand_r", (0.55, 0.55, 0.55))},
    ),
    "priest": dict(
        skin={"*": (0.5, 0.47, 0.4), "head": SKIN, "neck": SKIN, "hand": SKIN},
        shells=[
            (["chest", "belly", "hips", "upperarm", "lowerarm"], 0.03, (0.58, 0.55, 0.47), 0.0, None),
            (["chest", "belly"], 0.045, CRIMSON, 0.0, "tabard"),
            (["belly"], 0.052, GOLD, 1.0, "belt"),
        ],
        extras=["hair", "skirt", "boots", "cross"], boot=LEATHER, hair=(0.5, 0.5, 0.5), skirt=(0.58, 0.55, 0.47), skirt_to=0.12,
        weapons={"2H_Staff": ("hand_r", (0.6, 0.6, 0.8))},
    ),
    "paladin": dict(
        skin={"*": MAIL, "head": SKIN, "neck": SKIN, "hand": LEATHER_D},
        shells=[
            (["neck"], 0.030, STEEL, 1.0, None),
            (["chest", "belly"], 0.030, STEEL_L, 1.0, None),
            (["hips"], 0.030, STEEL, 1.0, None),
            (["chest", "belly"], 0.045, (0.6, 0.58, 0.5), 0.0, "tabard"),
            (["belly"], 0.058, GOLD, 1.0, "belt"),
            (["upperarm"], 0.020, STEEL, 1.0, None),
            (["lowerarm"], 0.022, STEEL_L, 1.0, None),
            (["thigh"], 0.022, STEEL, 1.0, None),
            (["calf"], 0.026, STEEL_L, 1.0, None),
        ],
        extras=["pauldrons", "helm", "cape", "knees", "gauntlets", "boots", "skirt", "cross"],
        cape=(0.08, 0.14, 0.4), pauldron=(GOLD, 0.115, False), boot=STEEL, gauntlet=STEEL, skirt=(0.6, 0.58, 0.5), crest=GOLD,
        weapons={"1H_Sword": ("hand_r", (0.6, 0.6, 0.7), "hammer"), "Round_Shield": ("hand_l", (0.5, 0.5, 0.5))},
    ),
    # ---- monsters on the same bodies (road field) ----
    "scarecrow": dict(
        skin={"*": (0.16, 0.1, 0.05), "head": SACK, "neck": SACK, "hand": STRAW, "foot": STRAW},
        shells=[
            (["chest", "belly", "hips", "upperarm"], 0.03, (0.13, 0.07, 0.04), 0.0, None),
            (["lowerarm"], 0.02, (0.2, 0.13, 0.06), 0.0, None),
            (["belly"], 0.045, (0.3, 0.24, 0.1), 0.0, "belt"),
            (["thigh", "calf"], 0.02, (0.09, 0.08, 0.07), 0.0, None),
        ],
        extras=["sack", "hat", "skirt"], hat=(0.07, 0.05, 0.04), skirt=(0.13, 0.07, 0.04),
        weapons={},
    ),
    "bloated_pilgrim": dict(
        skin={"*": PALLID, "belly": (0.4, 0.42, 0.26), "chest": (0.4, 0.42, 0.26)},
        bulk={"spine_01": 1.45},
        shells=[
            (["hips", "thigh"], 0.04, (0.17, 0.12, 0.08), 0.0, "kilt"),
            (["upperarm", "chest"], 0.03, (0.17, 0.12, 0.08), 0.0, "strap"),
            (["calf"], 0.02, (0.12, 0.09, 0.07), 0.0, None),
        ],
        extras=["hood", "skirt"], hood=(0.17, 0.12, 0.08), skirt=(0.17, 0.12, 0.08), skirt_to=0.3,
        weapons={},
    ),
    "penitent": dict(
        skin={"*": PALLID},
        shells=[
            (["hips", "thigh"], 0.03, (0.5, 0.46, 0.4), 0.0, "kilt"),
            (["belly"], 0.04, (0.3, 0.02, 0.03), 0.0, "belt"),
        ],
        extras=["capirote", "skirt"], capirote=(0.5, 0.46, 0.4), skirt=(0.5, 0.46, 0.4), skirt_to=0.2,
        weapons={"Knife": ("hand_r", (0.5, 0.5, 0.6))},
    ),
    "gravedigger": dict(
        skin={"*": (0.08, 0.08, 0.09), "head": PALLID, "neck": PALLID, "hand": PALLID},
        shells=[
            (["chest", "belly", "hips", "upperarm", "lowerarm"], 0.03, (0.1, 0.1, 0.12), 0.0, None),
            (["belly"], 0.045, LEATHER_D, 0.0, "belt"),
            (["thigh"], 0.02, (0.07, 0.07, 0.08), 0.0, None),
            (["calf"], 0.028, LEATHER_D, 0.0, None),
        ],
        extras=["hat", "boots", "skirt", "buckle"], hat=(0.05, 0.05, 0.06), boot=LEATHER_D, skirt=(0.1, 0.1, 0.12),
        weapons={"2H_Sword": ("hand_r", (0.6, 0.6, 0.7), "shovel")},
    ),
    # ---- wood, marsh and peaks monsters ----
    "hanged_man": dict(
        skin={"*": (0.3, 0.33, 0.4)},
        shells=[
            (["chest", "belly", "upperarm"], 0.025, (0.3, 0.28, 0.22), 0.0, None),
            (["hips", "thigh"], 0.025, (0.1, 0.09, 0.08), 0.0, None),
        ],
        extras=["noose"], weapons={},
    ),
    "wood_witch": dict(
        skin={"*": (0.05, 0.1, 0.06), "head": (0.42, 0.46, 0.3), "neck": (0.42, 0.46, 0.3), "hand": (0.42, 0.46, 0.3)},
        shells=[
            (["chest", "belly", "hips", "upperarm", "lowerarm"], 0.03, (0.06, 0.12, 0.07), 0.0, None),
            (["belly"], 0.05, (0.3, 0.2, 0.08), 0.0, "belt"),
        ],
        extras=["witchhat", "skirt", "hair"], hat=(0.04, 0.07, 0.05), hair=(0.5, 0.5, 0.46), skirt=(0.06, 0.12, 0.07), skirt_to=0.1,
        weapons={"2H_Staff": ("hand_r", (0.6, 0.6, 0.8))},
    ),
    "bark_wight": dict(
        skin={"*": (0.13, 0.08, 0.04), "head": (0.17, 0.11, 0.05)},
        bulk={"spine_02": 1.2},
        shells=[
            (["chest", "belly"], 0.04, (0.09, 0.06, 0.03), 0.0, "strap"),
            (["lowerarm", "calf"], 0.035, (0.08, 0.05, 0.03), 0.0, None),
            (["hips"], 0.03, (0.1, 0.16, 0.06), 0.0, None),
        ],
        extras=["pauldrons", "face"], pauldron=((0.1, 0.16, 0.06), 0.1, True),
        weapons={},
    ),
    "lumberer": dict(
        skin={"*": (0.1, 0.09, 0.08), "head": PALLID, "neck": PALLID, "hand": PALLID, "lowerarm": PALLID},
        bulk={"spine_02": 1.25},
        shells=[
            (["chest", "belly", "upperarm"], 0.03, (0.13, 0.04, 0.03), 0.0, None),
            (["belly"], 0.045, LEATHER_D, 0.0, "belt"),
            (["hips", "thigh"], 0.025, (0.1, 0.09, 0.08), 0.0, None),
            (["calf"], 0.03, LEATHER_D, 0.0, None),
        ],
        extras=["hood", "boots", "buckle"], boot=LEATHER_D, hood=(0.05, 0.04, 0.04),
        weapons={"2H_Axe": ("hand_r", (0.6, 0.6, 0.7))},
    ),
    "drowned": dict(
        skin={"*": (0.1, 0.2, 0.2), "belly": (0.16, 0.26, 0.2), "hand": (0.05, 0.1, 0.1), "foot": (0.05, 0.1, 0.1)},
        bulk={"spine_01": 1.2},
        shells=[
            (["hips", "thigh"], 0.03, (0.08, 0.12, 0.13), 0.0, "kilt"),
            (["chest"], 0.03, (0.08, 0.12, 0.13), 0.0, "strap"),
            (["lowerarm", "calf"], 0.03, (0.04, 0.1, 0.06), 0.0, None),
        ],
        extras=["hair", "face"], hair=(0.03, 0.1, 0.05), weapons={},
    ),
    "goat_cultist": dict(
        skin={"*": (0.05, 0.04, 0.05), "head": PALLID, "neck": PALLID, "hand": PALLID},
        shells=[
            (["chest", "belly", "hips", "upperarm", "lowerarm"], 0.03, (0.07, 0.05, 0.07), 0.0, None),
            (["chest", "belly"], 0.045, (0.3, 0.02, 0.03), 0.0, "tabard"),
            (["belly"], 0.055, BONE, 0.0, "belt"),
        ],
        extras=["hood", "horns", "skirt"], hood=(0.07, 0.05, 0.07), skirt=(0.07, 0.05, 0.07), skirt_to=0.12,
        weapons={"Knife": ("hand_r", (0.5, 0.5, 0.6))},
    ),
    # ---- marsh, peaks and edge humanoids ----
    "eel_knight": dict(
        skin={"*": (0.05, 0.12, 0.12), "head": (0.2, 0.36, 0.36), "neck": (0.2, 0.36, 0.36), "hand": (0.05, 0.1, 0.1)},
        shells=[
            (["chest", "belly"], 0.03, (0.1, 0.2, 0.18), 1.0, None),
            (["hips"], 0.03, (0.05, 0.1, 0.1), 1.0, None),
            (["upperarm", "thigh"], 0.02, (0.05, 0.1, 0.1), 1.0, None),
            (["lowerarm", "calf"], 0.024, (0.1, 0.2, 0.18), 1.0, None),
            (["belly"], 0.05, (0.3, 0.34, 0.1), 0.0, "belt"),
        ],
        extras=["pauldrons", "helm", "knees", "gauntlets", "boots"], pauldron=((0.1, 0.2, 0.18), 0.11, True),
        boot=(0.05, 0.1, 0.1), gauntlet=(0.05, 0.1, 0.1), crest=(0.3, 0.34, 0.1),
        weapons={"2H_Sword": ("hand_r", (0.5, 0.6, 0.74))},
    ),
    "bog_hag": dict(
        skin={"*": (0.1, 0.11, 0.05), "head": (0.3, 0.36, 0.16), "neck": (0.3, 0.36, 0.16), "hand": (0.3, 0.36, 0.16), "lowerarm": (0.3, 0.36, 0.16)},
        shells=[
            (["chest", "belly", "hips", "upperarm"], 0.03, (0.12, 0.13, 0.06), 0.0, None),
            (["belly"], 0.05, BONE, 0.0, "belt"),
        ],
        extras=["hood", "skirt", "face"], hood=(0.12, 0.13, 0.06), skirt=(0.12, 0.13, 0.06), skirt_to=0.1,
        weapons={"1H_Wand": ("hand_r", (0.7, 0.7, 0.9))},
    ),
    "flagellant": dict(
        skin={"*": PALLID, "chest": (0.42, 0.3, 0.28), "belly": (0.42, 0.3, 0.28)},
        shells=[
            (["hips", "thigh"], 0.03, (0.14, 0.1, 0.08), 0.0, "kilt"),
            (["chest"], 0.03, (0.3, 0.02, 0.03), 0.0, "strap"),
            (["belly"], 0.04, STRAW, 0.0, "belt"),
        ],
        extras=["sack", "skirt"], skirt=(0.14, 0.1, 0.08),
        weapons={"1H_Sword": ("hand_r", (0.5, 0.5, 0.6), "hammer")},
    ),
    "rune_carver": dict(
        skin={"*": (0.1, 0.12, 0.16), "head": PALLID, "neck": PALLID, "hand": PALLID},
        shells=[
            (["chest", "belly", "hips", "upperarm", "lowerarm"], 0.03, (0.13, 0.16, 0.22), 0.0, None),
            (["chest", "belly"], 0.045, (0.3, 0.6, 0.7), 0.0, "tabard"),
            (["belly"], 0.055, LEATHER_D, 0.0, "belt"),
            (["calf"], 0.03, LEATHER_D, 0.0, None),
        ],
        extras=["hood", "skirt", "boots"], hood=(0.13, 0.16, 0.22), skirt=(0.13, 0.16, 0.22), boot=LEATHER_D,
        weapons={"Knife": ("hand_r", (0.5, 0.5, 0.6))},
    ),
    "bone_piper": dict(
        skin={"*": BONE},
        shells=[
            (["chest", "belly", "hips", "upperarm"], 0.03, (0.2, 0.05, 0.12), 0.0, None),
            (["belly"], 0.05, GOLD, 1.0, "belt"),
            (["thigh"], 0.02, (0.1, 0.03, 0.06), 0.0, None),
        ],
        extras=["witchhat", "cape", "face"], hat=(0.2, 0.05, 0.12), cape=(0.2, 0.05, 0.12), cape_len=0.7,
        weapons={"1H_Wand": ("hand_r", (0.7, 0.7, 0.9))},
    ),
    "frost_revenant": dict(
        skin={"*": (0.45, 0.6, 0.7), "head": (0.6, 0.75, 0.85)},
        shells=[
            (["chest", "belly"], 0.03, (0.2, 0.3, 0.4), 1.0, None),
            (["hips", "thigh"], 0.04, (0.12, 0.18, 0.26), 0.0, "kilt"),
            (["lowerarm", "calf"], 0.026, (0.2, 0.3, 0.4), 1.0, None),
        ],
        extras=["pauldrons", "face", "cape"], pauldron=((0.7, 0.85, 0.95), 0.12, True), cape=(0.12, 0.18, 0.26), cape_len=0.8,
        weapons={"2H_Sword": ("hand_r", (0.5, 0.6, 0.74))},
    ),
    "ash_legionary": dict(
        skin={"*": (0.1, 0.1, 0.1), "head": (0.3, 0.3, 0.3), "neck": (0.3, 0.3, 0.3), "hand": (0.06, 0.06, 0.06)},
        shells=[
            (["chest", "belly"], 0.03, (0.16, 0.15, 0.15), 1.0, None),
            (["hips"], 0.03, (0.08, 0.08, 0.08), 1.0, None),
            (["chest", "belly"], 0.045, (0.5, 0.16, 0.04), 0.0, "tabard"),
            (["upperarm", "thigh"], 0.02, (0.08, 0.08, 0.08), 1.0, None),
            (["lowerarm", "calf"], 0.024, (0.16, 0.15, 0.15), 1.0, None),
        ],
        extras=["pauldrons", "helm", "knees", "gauntlets", "boots", "skirt"], pauldron=((0.16, 0.15, 0.15), 0.11, False),
        boot=(0.08, 0.08, 0.08), gauntlet=(0.08, 0.08, 0.08), skirt=(0.5, 0.16, 0.04), crest=(0.9, 0.35, 0.05),
        weapons={"1H_Sword": ("hand_r", (0.42, 0.6, 0.74)), "Spike_Shield": ("hand_l", (0.52, 0.52, 0.56))},
    ),
    "blood_priest": dict(
        skin={"*": (0.16, 0.01, 0.02), "head": PALLID, "neck": PALLID, "hand": PALLID},
        shells=[
            (["chest", "belly", "hips", "upperarm", "lowerarm"], 0.03, (0.22, 0.015, 0.02), 0.0, None),
            (["chest", "belly"], 0.045, (0.04, 0.03, 0.04), 0.0, "tabard"),
            (["belly"], 0.055, GOLD, 1.0, "belt"),
        ],
        extras=["capirote", "skirt", "cross"], capirote=(0.22, 0.015, 0.02), skirt=(0.22, 0.015, 0.02), skirt_to=0.1,
        weapons={"2H_Staff": ("hand_r", (0.6, 0.6, 0.8))},
    ),
    # ---- the last humanoids: marsh brute, peaks, world's edge ----
    "corpse_barge": dict(
        skin={"*": (0.36, 0.42, 0.3), "belly": (0.46, 0.5, 0.34), "chest": (0.42, 0.46, 0.32), "hand": (0.2, 0.26, 0.2), "foot": (0.2, 0.26, 0.2)},
        bulk={"spine_01": 1.7, "spine_02": 1.35},
        shells=[
            (["hips", "thigh"], 0.05, (0.1, 0.09, 0.07), 0.0, "kilt"),
            (["chest"], 0.035, (0.16, 0.13, 0.08), 0.0, "strap"),
            (["belly"], 0.05, STRAW, 0.0, "belt"),
        ],
        extras=["face", "noose"], weapons={},
    ),
    "cliff_harpy": dict(
        skin={"*": (0.5, 0.4, 0.38), "lowerarm": (0.2, 0.16, 0.14), "hand": (0.1, 0.08, 0.07), "calf": (0.5, 0.4, 0.12), "foot": (0.5, 0.4, 0.12)},
        shells=[
            (["chest", "belly", "hips"], 0.03, (0.24, 0.18, 0.15), 0.0, None),
            (["thigh"], 0.04, (0.2, 0.15, 0.12), 0.0, None),
        ],
        extras=["wings", "hair", "face"], wing=(0.36, 0.26, 0.2), wing_tip=(0.55, 0.47, 0.38), brow=(0.06, 0.05, 0.05), jaw=(0.5, 0.4, 0.12), hair=(0.06, 0.05, 0.05),
        weapons={},
    ),
    "stone_anchorite": dict(
        skin={"*": (0.3, 0.3, 0.28), "head": (0.38, 0.38, 0.35), "hand": (0.22, 0.22, 0.2)},
        bulk={"spine_02": 1.4, "spine_01": 1.2},
        shells=[
            (["chest", "belly", "hips", "upperarm"], 0.035, (0.2, 0.19, 0.17), 0.0, None),
            (["belly"], 0.05, STRAW, 0.0, "belt"),
            (["lowerarm", "calf"], 0.04, (0.36, 0.36, 0.33), 0.0, None),
        ],
        extras=["pauldrons", "hood", "skirt", "face"], pauldron=((0.4, 0.4, 0.37), 0.15, False), brow=(0.12, 0.12, 0.11), jaw=(0.2, 0.2, 0.18),
        hood=(0.2, 0.19, 0.17), skirt=(0.2, 0.19, 0.17), skirt_to=0.15,
        weapons={"Spike_Shield": ("hand_l", (0.6, 0.6, 0.64)), "1H_Sword": ("hand_r", (0.5, 0.5, 0.6), "hammer")},
    ),
    "hollow_angel": dict(
        skin={"*": (0.5, 0.5, 0.52), "head": (0.015, 0.015, 0.02), "neck": (0.015, 0.015, 0.02)},
        shells=[
            (["chest", "belly", "hips", "upperarm"], 0.03, (0.46, 0.45, 0.42), 0.0, None),
            (["belly"], 0.045, (0.5, 0.38, 0.1), 1.0, "belt"),
        ],
        extras=["wings", "halo", "hood", "skirt"], wing=(0.42, 0.42, 0.44), wing_tip=(0.16, 0.16, 0.18), halo=(0.75, 0.55, 0.12),
        hood=(0.46, 0.45, 0.42), skirt=(0.46, 0.45, 0.42), skirt_to=0.1,
        weapons={"1H_Sword": ("hand_r", (0.5, 0.6, 0.74))},
    ),
    "flesh_choir": dict(
        skin={"*": (0.27, 0.05, 0.055), "head": (0.5, 0.38, 0.36), "belly": (0.31, 0.07, 0.065), "hand": (0.16, 0.04, 0.04)},
        bulk={"spine_01": 1.6, "spine_02": 1.75},
        shells=[
            (["hips", "thigh"], 0.04, (0.2, 0.05, 0.06), 0.0, "kilt"),
            (["chest"], 0.03, (0.25, 0.07, 0.07), 0.0, "strap"),
        ],
        extras=["heads", "skirt"], choir=True, heads=(0.58, 0.45, 0.42), flesh=(0.12, 0.02, 0.03), flesh2=(0.1, 0.017, 0.025), skirt=(0.2, 0.05, 0.06), skirt_to=0.25,
        weapons={},
    ),
    "the_unmade": dict(
        skin={"*": (0.05, 0.03, 0.08), "head": (0.1, 0.05, 0.14), "hand": (0.45, 0.12, 0.03), "lowerarm": (0.16, 0.05, 0.1), "foot": (0.02, 0.01, 0.03)},
        bulk={"spine_02": 1.5, "spine_01": 1.15},
        shells=[
            (["chest"], 0.04, (0.45, 0.12, 0.03), 0.0, "strap"),
            (["hips", "thigh"], 0.04, (0.02, 0.01, 0.03), 0.0, "kilt"),
            (["calf"], 0.04, (0.12, 0.1, 0.12), 1.0, None),
        ],
        extras=["pauldrons", "horns", "face"], pauldron=((0.12, 0.1, 0.12), 0.16, True), brow=(0.02, 0.01, 0.03), jaw=(0.45, 0.12, 0.03),
        weapons={},
    ),
    # ---- the tower's humanoids (field 4) ----
    "bloat": dict(
        skin={"*": (0.22, 0.26, 0.18), "belly": (0.3, 0.33, 0.2), "chest": (0.26, 0.3, 0.2), "head": (0.34, 0.37, 0.27), "hand": (0.2, 0.23, 0.16)},
        bulk={"spine_01": 1.15, "spine_02": 1.4, "neck_01": 0.35, "head": 1.05},
        shells=[
            (["hips", "thigh"], 0.04, (0.1, 0.09, 0.07), 0.0, "kilt"),
            (["calf"], 0.02, (0.16, 0.18, 0.12), 0.0, None),
            (["upperarm", "lowerarm"], 0.035, (0.26, 0.3, 0.2), 0.0, None),
        ],
        extras=["belly_glow"], glow=(1.0, 0.8, 0.08), flesh=(0.3, 0.34, 0.2),
        weapons={},
    ),
    "censor": dict(
        skin={"*": (0.14, 0.045, 0.03), "head": (0.01, 0.007, 0.008), "neck": (0.01, 0.007, 0.008), "hand": (0.4, 0.34, 0.28)},
        shells=[
            (["chest", "belly", "hips", "upperarm", "lowerarm"], 0.035, (0.17, 0.055, 0.035), 0.0, None),
            (["chest", "belly"], 0.05, (0.06, 0.025, 0.02), 0.0, "tabard"),
            (["belly"], 0.058, GOLD, 1.0, "belt"),
            (["thigh", "calf"], 0.03, (0.08, 0.035, 0.03), 0.0, None),
        ],
        extras=["hood", "skirt", "boots", "censer"], hood=(0.17, 0.055, 0.035), skirt=(0.17, 0.055, 0.035), skirt_to=0.1, boot=LEATHER_D,
        pose={"upperarm_r": -50}, weapons={},
    ),
    "guard": dict(
        skin={"*": (0.2, 0.21, 0.24), "head": SKIN, "neck": (0.15, 0.16, 0.18), "hand": LEATHER_D},
        bulk={"spine_02": 1.1},
        shells=[
            (["neck"], 0.030, STEEL_D, 1.0, None),
            (["chest", "belly"], 0.032, (0.3, 0.31, 0.35), 1.0, None),
            (["hips"], 0.03, STEEL_D, 1.0, None),
            (["belly"], 0.058, LEATHER_D, 0.0, "belt"),
            (["upperarm", "thigh"], 0.022, STEEL_D, 1.0, None),
            (["lowerarm", "calf"], 0.026, (0.3, 0.31, 0.35), 1.0, None),
        ],
        extras=["pauldrons", "helm", "gauntlets", "boots"], pauldron=((0.34, 0.35, 0.4), 0.11, False), boot=STEEL_D, gauntlet=STEEL_D,
        crest=(0.3, 0.1, 0.08),
        weapons={"1H_Sword": ("hand_r", (0.42, 0.6, 0.45)), "Rectangle_Shield": ("hand_l", (1.5, 0.9, 0.72))},
    ),
    "swords": dict(
        skin={"*": (0.035, 0.04, 0.1), "head": (0.02, 0.02, 0.05), "hand": (0.03, 0.025, 0.07)},
        shells=[
            (["neck"], 0.030, (0.07, 0.06, 0.14), 1.0, None),
            (["chest", "belly"], 0.032, (0.07, 0.07, 0.17), 1.0, None),
            (["hips"], 0.03, (0.03, 0.03, 0.07), 1.0, None),
            (["upperarm", "thigh"], 0.022, (0.03, 0.03, 0.08), 1.0, None),
            (["lowerarm", "calf"], 0.026, (0.08, 0.06, 0.18), 1.0, None),
            (["belly"], 0.056, (0.3, 0.1, 0.5), 0.0, "belt"),
        ],
        extras=["pauldrons", "helm", "gauntlets", "boots", "backblades"], pauldron=((0.1, 0.08, 0.2), 0.12, True), boot=(0.03, 0.03, 0.07),
        gauntlet=(0.03, 0.03, 0.07), crest=(0.4, 0.15, 0.7), blades=(0.55, 0.57, 0.72),
        weapons={"1H_Sword": ("hand_r", (0.42, 0.6, 0.85)), "1H_Sword_Offhand": ("hand_l", (0.42, 0.6, 0.85))},
    ),
    "coffin": dict(
        skin={"*": (0.1, 0.09, 0.08), "head": (0.1, 0.09, 0.08), "hand": (0.3, 0.27, 0.22)},
        bulk={"upperarm_l": 1.3, "upperarm_r": 1.3, "thigh_l": 1.3, "thigh_r": 1.3},
        shells=[
            (["upperarm", "lowerarm"], 0.06, (0.24, 0.2, 0.16), 0.0, None),
            (["thigh", "calf"], 0.06, (0.07, 0.06, 0.05), 0.0, None),
            (["hand"], 0.03, (0.3, 0.27, 0.22), 0.0, None),
        ],
        extras=["coffin"], coffin=((0.1, 0.05, 0.025), (0.85, 0.8, 0.66)),
        armout={"upperarm_l": [("Y", -35), ("X", 80)], "upperarm_r": [("Y", 35), ("X", 80)], "lowerarm_l": [], "lowerarm_r": [], "hand_l": [], "hand_r": []},
        weapons={},
    ),
    "orc": dict(
        skin={"*": (0.1, 0.2, 0.06), "head": (0.13, 0.25, 0.07)},
        bulk={"spine_02": 1.3, "head": 1.0},
        shells=[
            (["hips", "thigh"], 0.055, (0.1, 0.055, 0.03), 0.0, "kilt"),
            (["belly"], 0.030, LEATHER_D, 0.0, "belt"),
            (["calf"], 0.045, LEATHER_D, 0.0, None),
            (["lowerarm"], 0.034, STEEL_D, 1.0, None),
            (["chest"], 0.028, LEATHER, 0.0, "strap"),
        ],
        extras=["pauldrons", "face", "tusks", "knees", "boots"],
        boot=LEATHER_D,
        pauldron=(STEEL, 0.135, True),
        weapons={"2H_Axe": ("hand_r", (0.5, 0.5, 0.58))},
    ),
}
kit = KITS[kit_name]


def material(name, col, metallic=0.0, rough=0.55):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = metallic * 0.6      # full metal goes black without an environment to reflect
    b.inputs["Roughness"].default_value = 0.42 if metallic else rough
    return m


def dominant_regions(ob):
    """per vertex: the region its heaviest bone weight belongs to."""
    of = {}
    for reg, names in REGION.items():
        for n in names:
            if n in ob.vertex_groups:
                of[ob.vertex_groups[n].index] = reg
    out = []
    for v in ob.data.vertices:
        best, bw = "chest", 0.0
        for g in v.groups:
            if g.weight > bw and g.group in of:
                best, bw = of[g.group], g.weight
        out.append(best)
    return out


def face_filter(kind, ob, poly, lo_hi):
    c = poly.center
    if kind == "tabard":        # a strip down the middle of the front and the back
        return abs(c.x) < 0.105 * lo_hi["w"]
    if kind == "kilt":          # hips and the top half of the thighs
        return c.z > lo_hi["knee"] + 0.45 * (lo_hi["hip"] - lo_hi["knee"])
    if kind == "belt":
        return c.z < lo_hi["hip"] + 0.11
    if kind == "strap":         # one diagonal band over the chest
        d = (c.x * 0.75 + (c.z - lo_hi["chest"]) * 0.66)
        return abs(d) < 0.06
    return True


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=body_glb)
dst = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
body = [o for o in bpy.data.objects if o.type == "MESH" and o.parent is dst][0]
bpy.ops.import_scene.gltf(filepath=anim_glb)
src = [o for o in bpy.data.objects if o.type == "ARMATURE" and o is not dst][0]
weap = {}
for o in list(bpy.data.objects):
    if o.type != "MESH" or o is body:
        continue
    if o.name in kit["weapons"]:
        weap[o.name] = o
    else:
        bpy.data.objects.remove(o)
vl = bpy.context.view_layer
vl.update()

# ---- colour the body by region
regs = dominant_regions(body)
mats = {}
body.data.materials.clear()
for reg in REGION:
    col = kit["skin"].get(reg, kit["skin"]["*"])
    key = tuple(col)
    if key not in mats:
        mats[key] = len(body.data.materials)
        body.data.materials.append(material("skin%d" % len(mats), col, 0.0, 0.7))
for p in body.data.polygons:
    votes = [regs[i] for i in p.vertices]
    reg = max(set(votes), key=votes.count)
    p.material_index = mats[tuple(kit["skin"].get(reg, kit["skin"]["*"]))]
    p.use_smooth = True

bw = lambda n: (dst.matrix_world @ dst.data.bones[n].matrix_local).translation  # noqa: E731
marks = {"knee": bw("calf_l").z, "hip": bw("thigh_l").z, "chest": bw("spine_03").z, "w": body.dimensions.z / 1.79}

# ---- armour shells
for n, (regions, thick, col, metal, filt) in enumerate(kit["shells"]):
    sh = body.copy()
    sh.data = body.data.copy()
    sh.name = "shell%d" % n
    bpy.context.scene.collection.objects.link(sh)
    keep = []
    for p in sh.data.polygons:
        votes = [regs[i] for i in p.vertices]
        reg = max(set(votes), key=votes.count)
        keep.append(reg in regions and face_filter(filt, sh, p, marks))
    bm = bmesh.new()
    bm.from_mesh(sh.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f, k in zip(bm.faces, keep) if not k], context="FACES")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * thick
    for _ in range(3):                           # pushed-out creases cross each other; relax them
        bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(sh.data)
    bm.free()
    sh.data.materials.clear()
    sh.data.materials.append(material("shell%d" % n, col, metal))
    so = sh.modifiers.new("rim", "SOLIDIFY")
    so.thickness = thick
    so.offset = -1


def hang(ob, bone, world):
    """parent ob to a bone of the body's rig so that it sits at `world` in the rest pose."""
    ob.parent = dst
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    vl.update()
    ob.matrix_world = world


def prim(kind, name, col, metal=0.0, **kw):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    if kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=1.0)
    elif kind == "cone":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=1.0, radius2=kw.get("r2", 0.0), depth=2.0)
    elif kind == "cube":
        bmesh.ops.create_cube(bm, size=2.0)
    elif kind == "grid":
        bmesh.ops.create_grid(bm, x_segments=4, y_segments=8, size=1.0)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(material(name, col, metal))
    return ob


def trs(loc, rot=(0, 0, 0), scale=(1, 1, 1)):
    from mathutils import Euler
    return Matrix.Translation(loc) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4() @ Matrix.Diagonal((*scale, 1))


S = marks["w"]                                   # the body's size against a 1.79 m human
ex = list(kit["extras"])
if RACE == "orc" and kit_name != "orc":           # an orc in any class kit: bald, its face and tusks when the head shows
    ex = [e for e in ex if e != "hair"] + ([] if "helm" in ex else ["face", "tusks"])
    kit = dict(kit, bulk=dict(kit.get("bulk", {}), spine_02=1.3))
if RACE == "elf" and "helm" not in ex:           # elves go bare-headed with long pale hair, so the race reads at 56 px
    ex = [e for e in ex if e != "hood"] + ([] if "hair" in ex else ["hair"])
    kit = dict(kit, hair=(0.75, 0.66, 0.38))
if "pauldrons" in ex:
    col, r, spikes = kit["pauldron"]
    for s, sg in (("l", 1), ("r", -1)):
        p = bw("upperarm_" + s)
        o = prim("sphere", "pauldron_" + s, col, 1.0)
        hang(o, "clavicle_" + s, trs(p + Vector((sg * 0.035 * S, 0, 0.035 * S)), (0, sg * -20, 0), (r * 1.2 * S, r * 1.15 * S, r * 0.85 * S)))
        if spikes:
            for k, (dx, dy) in enumerate(((0.0, 0.0), (0.05, 0.07), (0.05, -0.07))):
                c = prim("cone", "spike_%s%d" % (s, k), BONE)
                hang(c, "clavicle_" + s, trs(p + Vector((sg * (0.05 + dx) * S, dy * S, (0.17 - dx) * S)), (0, sg * 28, 0), (0.04 * S, 0.04 * S, 0.14 * S)))
if "knees" in ex:
    for s in "lr":
        p = bw("calf_" + s)
        o = prim("sphere", "knee_" + s, kit["pauldron"][0], 1.0)
        hang(o, "calf_" + s, trs(p + Vector((0, -0.055 * S, 0.0)), (0, 0, 0), (0.062 * S, 0.05 * S, 0.075 * S)))
head_top = max((body.matrix_world @ v.co).z for v in body.data.vertices)
hp = bw("head")


def bbox(regions, side=None):
    """world bounding box (min, max) of the body's vertices in these regions, optionally one side (l: x > 0)."""
    pts = [body.matrix_world @ v.co for v, r in zip(body.data.vertices, regs) if r in regions]
    if side:
        pts = [p for p in pts if (p.x > 0) == (side == "l")]
    return (Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
            Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))))


def blob(kind, name, bone, regions, side, col, metal, grow=1.12, **kw):
    lo, hi = bbox(regions, side)
    o = prim(kind, name, col, metal, **kw)
    hang(o, bone, trs((lo + hi) / 2, (0, 0, 0), tuple((hi - lo) * grow / 2)))
    return o


if "helm" in ex:                                 # a great helm: a barrel over the head, a dark eye slit, a crest
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    o = prim("cone", "helm", STEEL, 1.0, r2=0.86)
    hang(o, "head", trs(c + Vector((0, 0, 0.01 * S)), (0, 0, 0), (half.x * 1.22, half.y * 1.12, half.z * 1.1)))
    o = prim("cube", "visor", (0.015, 0.015, 0.02))
    hang(o, "head", trs(Vector((0, lo.y - half.y * 0.1, c.z + half.z * 0.12)), (0, 0, 0), (half.x * 0.95, half.y * 0.2, 0.011 * S)))
    o = prim("cube", "crest", kit.get("crest", CRIMSON))
    hang(o, "head", trs(Vector((0, c.y + 0.02 * S, hi.z + 0.04 * S)), (-10, 0, 0), (0.014 * S, half.y * 0.95, 0.05 * S)))
if "gauntlets" in ex:
    for s_ in "lr":
        blob("sphere", "gauntlet_" + s_, "hand_" + s_, ["hand"], s_, kit["gauntlet"], 1.0, grow=1.0)
if "boots" in ex:
    for s_ in "lr":
        blob("sphere", "boot_" + s_, "foot_" + s_, ["foot"], s_, kit["boot"], 1.0 if kit_name == "knight" else 0.0, grow=1.22)
if "skirt" in ex:                                # the surcoat's skirt: a flared tube from the waist to above the knee
    lo, hi = bbox(["hips", "thigh"])
    top = marks["hip"] + 0.12 * S
    bot = marks["knee"] + 0.14 * S if "skirt_to" not in kit else kit["skirt_to"] * S
    o = prim("cone", "skirt", kit["skirt"], 0.0, r2=0.72)
    hang(o, "pelvis", trs(Vector((0, (lo.y + hi.y) / 2, (top + bot) / 2)), (0, 0, 0),
                          ((hi.x - lo.x) * 0.62, (hi.y - lo.y) * 0.85, (top - bot) / 2)))
if "cross" in ex:                                # a gold cross on the chest of the surcoat
    lo, hi = bbox(["chest"])
    cz, fy = marks["chest"] - 0.02 * S, lo.y - 0.035 * S
    for nm, sx, sz in (("cross_v", 0.016, 0.085), ("cross_h", 0.05, 0.016)):
        o = prim("cube", nm, GOLD, 1.0)
        hang(o, "spine_03", trs(Vector((0, fy, cz + (0.015 * S if nm == "cross_h" else 0))), (0, 0, 0), (sx * S, 0.012 * S, sz * S)))
if "buckle" in ex:
    lo, hi = bbox(["belly"])
    o = prim("cube", "buckle", GOLD, 1.0)
    hang(o, "spine_01", trs(Vector((0, lo.y - 0.06 * S, marks["hip"] + 0.075 * S)), (0, 0, 0), (0.03 * S, 0.012 * S, 0.026 * S)))
if "face" in ex:                                 # features that survive at 8 px and read from the side: brow, lit eyes, jaw, ears
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    eye_z = c.z + half.z * 0.1
    o = prim("cube", "brow", kit.get("brow", (0.03, 0.07, 0.02)))
    hang(o, "head", trs(Vector((0, lo.y + half.y * 0.42, eye_z + half.z * 0.2)), (10, 0, 0), (half.x * 1.04, half.y * 0.5, half.z * 0.1)))
    for sg in (1, -1):
        o = prim("sphere", "eye%d" % sg, (1.0, 0.25, 0.05))
        bs = o.data.materials[0].node_tree.nodes["Principled BSDF"]
        bs.inputs["Emission Color"].default_value = (1.0, 0.3, 0.05, 1)
        bs.inputs["Emission Strength"].default_value = 6.0
        hang(o, "head", trs(Vector((sg * half.x * 0.78, lo.y + half.y * 0.5, eye_z)), (0, 0, 0), (half.x * 0.3, half.y * 0.22, half.z * 0.11)))
        e = prim("cone", "ear%d" % sg, kit["skin"].get("head", kit["skin"]["*"]))
        hang(e, "head", trs(Vector((sg * half.x * 1.1, c.y + half.y * 0.25, eye_z + half.z * 0.05)), (-55, sg * 25, 0), (half.x * 0.16, half.y * 0.1, half.z * 0.34)))
    o = prim("cube", "jaw", kit.get("jaw", (0.07, 0.15, 0.04)))
    hang(o, "head", trs(Vector((0, lo.y + half.y * 0.3, c.z - half.z * 0.5)), (0, 0, 0), (half.x * 0.8, half.y * 0.5, half.z * 0.2)))
if "tusks" in ex:
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    for sg in (1, -1):
        o = prim("cone", "tusk%d" % sg, BONE)
        hang(o, "head", trs(Vector((sg * half.x * 0.7, lo.y - half.y * 0.02, c.z - half.z * 0.2)), (-6, 0, 0), (half.x * 0.17, half.x * 0.17, half.z * 0.26)))
if RACE == "elf" and "helm" not in ex:           # long ears swept back and up, past the hood or hair
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    for sg in (1, -1):
        e = prim("cone", "elfear%d" % sg, SKIN)
        hang(e, "head", trs(Vector((sg * half.x * 1.3, c.y + half.y * 0.75, c.z + half.z * 0.45)), (-60, sg * 20, 0), (half.x * 0.22, half.y * 0.16, half.z * 0.8)))
if RACE == "dwarf":                              # a full beard down to the chest
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    o = prim("cone", "beard", (0.36, 0.13, 0.04))
    hang(o, "head", trs(Vector((0, lo.y + half.y * 0.2, c.z - half.z * 1.0)), (180 - 12, 0, 0), (half.x * 0.85, half.y * 0.5, half.z * 0.75)))
if "hair" in ex:                                 # a cap of hair over the top and back of the head
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    o = prim("sphere", "hair", kit["hair"])
    hang(o, "head", trs(c + Vector((0, half.y * 0.2, half.z * 0.3)), (-18, 0, 0), (half.x * 1.1, half.y * 1.0, half.z * 0.8)))
if "hair" in ex and RACE == "elf":                # the long part, down the back to the shoulder blades
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    o = prim("cone", "hair_long", kit["hair"], 0.0, r2=0.7)
    hang(o, "head", trs(Vector((0, hi.y - half.y * 0.1, c.z - half.z * 0.9)), (8, 0, 0), (half.x * 0.95, half.y * 0.42, half.z * 1.3)))
if "witchhat" in ex:                             # a wide brim and a tall bent point
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    o = prim("cone", "hat_brim", kit["hat"], 0.0, r2=1.0)
    hang(o, "head", trs(Vector((c.x, c.y, hi.z - half.z * 0.3)), (-6, 0, 0), (half.x * 2.5, half.y * 2.2, half.z * 0.07)))
    o = prim("cone", "hat_point", kit["hat"])
    hang(o, "head", trs(Vector((c.x, c.y + half.y * 0.25, hi.z + half.z * 0.75)), (-14, 0, 0), (half.x * 1.1, half.y * 1.0, half.z * 1.1)))
if "horns" in ex:                                # goat horns, swept back
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    for sg in (1, -1):
        o = prim("cone", "horn%d" % sg, BONE)
        hang(o, "head", trs(Vector((sg * half.x * 0.85, c.y + half.y * 0.5, hi.z + half.z * 0.45)), (-40, sg * 22, 0), (half.x * 0.24, half.y * 0.2, half.z * 0.75)))
if "noose" in ex:                                # the rope still on him: a ring at the neck and the cut end down the chest
    lo, hi = bbox(["neck"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    o = prim("cone", "noose_ring", STRAW, 0.0, r2=1.0)
    hang(o, "neck_01", trs(c, (0, 0, 0), (half.x * 1.5, half.y * 1.5, 0.03 * S)))
    o = prim("cone", "noose_end", STRAW, 0.0, r2=1.0)
    hang(o, "spine_03", trs(Vector((c.x + 0.03 * S, lo.y - 0.05 * S, c.z - 0.2 * S)), (8, 0, 0), (0.022 * S, 0.022 * S, 0.2 * S)))
if "sack" in ex:                                 # a sack over the whole head, two dark holes for eyes
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    o = prim("sphere", "sack", SACK)
    hang(o, "head", trs(c, (0, 0, 0), (half.x * 1.2, half.y * 1.15, half.z * 1.15)))
    for sg in (1, -1):
        o = prim("cube", "sackeye%d" % sg, (0.01, 0.01, 0.01))
        hang(o, "head", trs(Vector((sg * half.x * 0.62, lo.y - half.y * 0.02, c.z + half.z * 0.1)), (0, 0, 0), (half.x * 0.3, half.y * 0.3, half.z * 0.16)))
if "hat" in ex:                                  # a wide brim and a low crown
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    o = prim("cone", "hat_brim", kit["hat"], 0.0, r2=1.0)
    hang(o, "head", trs(Vector((c.x, c.y, hi.z - half.z * 0.25)), (-6, 0, 0), (half.x * 2.3, half.y * 2.0, half.z * 0.07)))
    o = prim("cone", "hat_crown", kit["hat"], 0.0, r2=0.75)
    hang(o, "head", trs(Vector((c.x, c.y, hi.z + half.z * 0.1)), (-6, 0, 0), (half.x * 1.15, half.y * 1.05, half.z * 0.4)))
if "capirote" in ex:                             # the penitent's tall pointed hood, covering the face, eye holes
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    o = prim("sphere", "cap_face", kit["capirote"])
    hang(o, "head", trs(c, (0, 0, 0), (half.x * 1.2, half.y * 1.15, half.z * 1.15)))
    o = prim("cone", "cap_cone", kit["capirote"])
    hang(o, "head", trs(Vector((c.x, c.y, hi.z + half.z * 1.0)), (0, 0, 0), (half.x * 1.05, half.y * 1.0, half.z * 1.5)))
    for sg in (1, -1):
        o = prim("cube", "capeye%d" % sg, (0.01, 0.01, 0.01))
        hang(o, "head", trs(Vector((sg * half.x * 0.62, lo.y - half.y * 0.02, c.z + half.z * 0.1)), (0, 0, 0), (half.x * 0.3, half.y * 0.3, half.z * 0.14)))
if "hood" in ex:                                 # a hood: over the top, sides and back, the face left open
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    o = prim("sphere", "hood", kit["hood"])
    hang(o, "head", trs(c + Vector((0, half.y * 0.42, half.z * 0.14)), (-12, 0, 0), (half.x * 1.3, half.y * 1.12, half.z * 1.18)))
    o = prim("cone", "hood_tip", kit["hood"])
    hang(o, "head", trs(c + Vector((0, half.y * 1.0, half.z * 0.75)), (-125, 0, 0), (half.x * 0.6, half.y * 0.5, half.z * 0.5)))
if "quiver" in ex:
    back_y = max((body.matrix_world @ v.co).y for v, r in zip(body.data.vertices, regs) if r == "chest")
    o = prim("cone", "quiver", LEATHER, 0.0, r2=0.8)
    hang(o, "spine_03", trs(Vector((-0.07 * S, back_y + 0.05 * S, marks["chest"] - 0.02 * S)), (0, 28, 0), (0.05 * S, 0.05 * S, 0.24 * S)))
    o = prim("cone", "arrows", BONE, 0.0, r2=0.9)
    hang(o, "spine_03", trs(Vector((-0.2 * S, back_y + 0.05 * S, marks["chest"] + 0.23 * S)), (0, 28, 0), (0.04 * S, 0.04 * S, 0.05 * S)))
if "wings" in ex:                               # two feathered wings from the shoulder blades, swept up and back
    back_y = max((body.matrix_world @ v.co).y for v, r in zip(body.data.vertices, regs) if r == "chest")
    top = bw("neck_01").z - 0.06 * S
    for sg in (1, -1):
        for part, col, sc, rot, off in (("wing", kit["wing"], (0.3, 0.06, 0.6), (30, sg * 40, sg * 20), (0.28, 0.16, 0.22)),
                                        ("wingtip", kit["wing_tip"], (0.2, 0.05, 0.6), (30, sg * 95, sg * 20), (0.75, 0.3, 0.02))):
            o = prim("cone", "%s%d" % (part, sg), col)
            hang(o, "spine_03", trs(Vector((sg * off[0] * S, back_y + off[1] * S, top + off[2] * S)), rot, tuple(k * S for k in sc)))
if "halo" in ex:                                # a dull gold disc standing behind the head
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    o = prim("cone", "halo", kit["halo"], 1.0, r2=1.0)
    hang(o, "head", trs(Vector((0, hi.y + half.y * 0.5, c.z + half.z * 0.5)), (90, 0, 0), (half.x * 1.9, half.x * 1.9, 0.012 * S)))
if "heads" in ex and kit.get("choir"):          # the choir: one bloated body, three pale heads on short thick necks, dark open mouths
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    PIT = (0.012, 0.0, 0.0)
    clo, chi = bbox(["chest"])
    blo, bhi = bbox(["belly"])
    ycm = (clo.y + chi.y) / 2                                # chest mid-depth (y: -front, +back)

    def mass(name, bone, centre, radii, col, rot=(0, 0, 0)):
        o = prim("sphere", name, col)
        hang(o, bone, trs(centre, rot, radii))

    # the bloated, fused body: a belly, a heavy shoulder yoke (long front to back: the necks grow out of its ends), back lumps
    belly = Vector(((blo.x + bhi.x) / 2, (blo.y + bhi.y) / 2 - 0.1 * S, (blo.z + bhi.z) / 2 + 0.01 * S))
    belly_r = (0.27 * S, 0.25 * S, 0.15 * S)
    mass("belly", "spine_01", belly, belly_r, kit["flesh"])
    yoke = Vector((0, ycm - 0.03 * S, clo.z + (chi.z - clo.z) * 0.72))
    yoke_r = (0.25 * S, 0.35 * S, 0.15 * S)
    mass("yoke", "spine_03", yoke, yoke_r, kit["flesh"])
    mass("lump", "spine_03", Vector((-0.1 * S, chi.y + 0.1 * S, clo.z + (chi.z - clo.z) * 0.45)), (0.17 * S, 0.17 * S, 0.17 * S), kit["flesh2"])
    mass("lump2", "spine_03", Vector((0.12 * S, chi.y + 0.14 * S, clo.z + (chi.z - clo.z) * 0.75)), (0.11 * S, 0.12 * S, 0.11 * S), kit["flesh"])
    for i, (bone, cen, rad, f, tilt) in enumerate((("spine_01", belly, belly_r, 1.04, -12), ("spine_01", belly - Vector((0, 0, 0.09 * S)), belly_r, 0.8, 10),
                                                    ("spine_03", yoke, yoke_r, 1.03, 8))):
        o = prim("cone", "seam%d" % i, (0.02, 0.0, 0.0), 0.0, r2=1.0)     # a dark stitched seam ringing a mass where the bodies join
        hang(o, bone, trs(cen, (tilt, 0, 0), (rad[0] * f, rad[1] * f, 0.011 * S)))

    def sing(name, bone, at, rot, size, tint, neck=False):
        """a pale head (an ellipsoid of `size`) at `at`, turned by `rot`, with a big dark open mouth and two eye pits on its face."""
        base = trs(at, rot)
        o = prim("sphere", name, tint)
        hang(o, bone, base @ Matrix.Diagonal((*size, 1)))
        hx, hy, hz = size
        o = prim("sphere", name + "_mouth", PIT)
        hang(o, bone, base @ trs(Vector((0, -hy * 0.86, -hz * 0.3)), (0, 0, 0), (hx * 0.72, hy * 0.28, hz * 0.62)))
        for sg in (1, -1):
            o = prim("sphere", "%s_eye%d" % (name, sg), PIT)
            hang(o, bone, base @ trs(Vector((sg * hx * 0.5, -hy * 0.84, hz * 0.5)), (0, 0, 0), (hx * 0.22, hy * 0.22, hz * 0.17)))
        if neck:                                   # a short, thick stump between the shoulder mass and the head
            o = prim("cone", name + "_neck", kit["flesh2"], 0.0, r2=0.85)
            hang(o, bone, trs(at + Vector((0, 0, -hz * 0.95)), (0, rot[1], 0), (hx * 0.72, hx * 0.72, hz * 0.62)))

    sing("head0", "head", c + Vector((0, half.y * 0.04, half.z * 0.1)), (-16, 0, 30), (half.x * 1.12, half.y * 1.05, half.z * 1.08), kit["heads"])
    for sg in (1, -1):
        # the camera looks from +x and a little forward, so heads spread along x alone would stack in depth: the near one
        # (x+) sits forward and the far one (x-) back on the long shoulder yoke, so the three clear each other on the screen
        px, py = sg * 0.1 * S, yoke.y - sg * 0.31 * S
        k = 1 - (px / yoke_r[0]) ** 2 - ((py - yoke.y) / yoke_r[1]) ** 2
        top = yoke.z + yoke_r[2] * math.sqrt(max(k, 0.0))      # the yoke's surface under the head
        hz_ = half.z * 1.05
        at = Vector((px, py, top + hz_ * 0.55 + hz_ * 0.95 + (0.04 * S if sg < 0 else -0.01 * S)))
        sing("head%d" % sg, "spine_03", at, (-20, sg * 18, 30), (half.x * 1.05, half.y * 1.05, hz_), (kit["heads"][0] + sg * 0.03, kit["heads"][1], kit["heads"][2]), True)
elif "heads" in ex:                               # the old choir: two more heads on the shoulders, mouths open
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    for sg in (1, -1):
        o = prim("sphere", "head%d" % sg, kit["heads"])
        at = Vector((sg * half.x * 2.3, c.y + half.y * 0.1, lo.z - half.z * 0.1))
        hang(o, "spine_03", trs(at, (0, 0, 0), (half.x * 0.8, half.y * 0.85, half.z * 0.85)))
        o = prim("sphere", "mouth%d" % sg, (0.03, 0.0, 0.0))
        hang(o, "spine_03", trs(at + Vector((0, -half.y * 0.75, -half.z * 0.25)), (0, 0, 0), (half.x * 0.32, half.y * 0.2, half.z * 0.36)))
if "cape" in ex:
    o = prim("grid", "cape", kit["cape"])
    back_y = max((body.matrix_world @ v.co).y for v, r in zip(body.data.vertices, regs) if r == "chest")
    top = bw("neck_01").z - 0.02 * S
    length = (top - marks["knee"]) * kit.get("cape_len", 1.0)
    for v in o.data.vertices:                     # a hanging sheet: wider and further from the body towards the hem
        t = (1 - v.co.y) / 2                      # 0 at the collar, 1 at the hem
        v.co = Vector((v.co.x * (0.17 + 0.12 * t) * S, 0.02 * S + 0.16 * S * t * t, -t * length))
    so = o.modifiers.new("thick", "SOLIDIFY")
    so.thickness = 0.02
    hang(o, "spine_03", trs(Vector((0, back_y + 0.03 * S, top))))

if "belly_glow" in ex:                           # the bloat: a huge swollen belly lit from inside, a bright yellow patch on the front
    lo, hi = bbox(["belly"])
    c = (lo + hi) / 2
    o = prim("sphere", "bellymass", kit["flesh"])
    hang(o, "spine_01", trs(Vector((c.x, c.y - 0.1 * S, c.z - 0.03 * S)), (0, 0, 0), (0.3 * S, 0.3 * S, 0.27 * S)))
    nlo, nhi = bbox(["neck"])
    o = prim("sphere", "collar", kit["flesh"])                     # a thick collar of flesh that swallows the neck: the head sits in the shoulders
    hang(o, "spine_03", trs(Vector((0, (nlo.y + nhi.y) / 2, nlo.z - 0.015 * S)), (0, 0, 0), (0.2 * S, 0.16 * S, 0.07 * S)))
    o = prim("sphere", "bellyglow_side", kit["glow"])              # a second patch turned toward the camera (front and +x)
    bs = o.data.materials[0].node_tree.nodes["Principled BSDF"]
    bs.inputs["Emission Color"].default_value = (*kit["glow"], 1)
    bs.inputs["Emission Strength"].default_value = 2.2
    hang(o, "spine_01", trs(Vector((c.x + 0.16 * S, c.y - 0.33 * S, c.z - 0.03 * S)), (0, 0, 30), (0.15 * S, 0.07 * S, 0.2 * S)))
    for nm, rad, dz, st in (("bellyglow", (0.2, 0.09, 0.22), 0.0, 2.2), ("bellyglow2", (0.09, 0.06, 0.1), 0.0, 3.5)):
        o = prim("sphere", nm, kit["glow"])
        bs = o.data.materials[0].node_tree.nodes["Principled BSDF"]
        bs.inputs["Emission Color"].default_value = (*kit["glow"], 1)
        bs.inputs["Emission Strength"].default_value = st
        hang(o, "spine_01", trs(Vector((c.x, c.y - (0.37 if dz == 0 and nm == "bellyglow" else 0.4) * S, c.z - 0.03 * S)), (0, 0, 0), tuple(k * S for k in rad)))
dangle = []                                      # (object, offset below the hand, scale): hung in the world, always straight down
if "censer" in ex:                               # a censer on a short rigid chain from the right hand; the arm is raised by kit["pose"]
    chain = 0.17 * S
    r_ = 0.065 * S
    for nm, col, metal, em, kind, off, sc_ in (
            ("chain", STEEL_D, 1.0, 0, "cube", -chain / 2, (0.008 * S, 0.008 * S, chain / 2)),
            ("censer_lid", STEEL, 1.0, 0, "cone", -chain - 0.01 * S, (0.07 * S, 0.07 * S, 0.035 * S)),
            ("censer_ball", (1.0, 0.4, 0.06), 0.0, 2.2, "sphere", -chain - r_ - 0.03 * S, (r_, r_, r_)),
            ("censer_base", STEEL_D, 1.0, 0, "cone", -chain - 2 * r_ - 0.04 * S, (0.04 * S, 0.04 * S, 0.02 * S))):
        o = prim(kind, nm, col, metal)
        if em:
            bs = o.data.materials[0].node_tree.nodes["Principled BSDF"]
            bs.inputs["Emission Color"].default_value = (1.0, 0.45, 0.08, 1)
            bs.inputs["Emission Strength"].default_value = em
        dangle.append((o, off, sc_))


def place_dangle():
    pb = dst.pose.bones["hand_r"]
    p0 = dst.matrix_world @ ((pb.head + pb.tail) / 2)
    for o, off, sc_ in dangle:
        o.matrix_world = Matrix.Translation(p0 + Vector((0, 0, off))) @ Matrix.Diagonal((*sc_, 1))


if "backblades" in ex:                           # blades fixed fan-like on the back, points up
    back_y = max((body.matrix_world @ v.co).y for v, r in zip(body.data.vertices, regs) if r == "chest")
    base = Vector((0, back_y + 0.05 * S, marks["chest"] - 0.3 * S))
    for k, (ax, ay, ln) in enumerate(((-0.85, -0.3, 1.3), (0.0, -0.6, 1.6), (0.85, -0.3, 1.3))):
        d = Vector((ax, ay, 1.0)).normalized()
        o = prim("cone", "backblade%d" % k, kit["blades"], 1.0, r2=0.3)
        hang(o, "spine_03", Matrix.Translation(base + d * ln * S / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4() @ Matrix.Diagonal((0.15 * S, 0.045 * S, ln * S / 2, 1)))
if "coffin" in ex:                               # the brute: the body is a tall tapered coffin that holds torso and head; legs and arms stick out
    wood, trim = kit["coffin"]
    clo, chi = bbox(["chest"])
    yc = (clo.y + chi.y) / 2 - 0.02 * S
    PHI = math.radians(48)                       # turned 48 degrees toward the camera (which sees the front only at 1/3 width)
    Rz = Matrix.Rotation(PHI, 3, "Z")
    pts = [(-0.2, 0.5), (0.2, 0.5), (0.32, 1.45), (0.22, 1.98), (-0.22, 1.98), (-0.32, 1.45)]   # front outline (x, z) in S
    dep = 0.27 * S

    def at(x, y, z):                             # local (x right, y back, z up) to the rest-pose world, turned by PHI about the box centre
        v = Rz @ Vector((x, y, 0))
        return Vector((v.x, yc + v.y, z))

    me = bpy.data.meshes.new("coffin")
    bm = bmesh.new()
    fr = [bm.verts.new(at(x * S, -dep, z * S)) for x, z in pts]
    bk = [bm.verts.new(at(x * S, dep, z * S)) for x, z in pts]
    bm.faces.new(fr[::-1])
    bm.faces.new(bk)
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((fr[i], fr[j], bk[j], bk[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("coffin", me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(material("coffin", wood))
    hang(o, "pelvis", Matrix.Identity(4))
    for nm, z_, hw in (("band0", 0.72, 0.245), ("band1", 1.08, 0.28), ("band2", 1.82, 0.235)):    # near-black iron straps round the box
        o = prim("cube", nm, (0.025, 0.025, 0.03), 1.0)
        hang(o, "pelvis", Matrix.Translation(at(0, 0, z_ * S)) @ Rz.to_4x4() @ Matrix.Diagonal(((hw + 0.012) * S, dep + 0.014 * S, 0.04 * S, 1)))
    for nm, c_, sc_ in (("cross_v", (0, 1.38), (0.06, 0.5)), ("cross_h", (0, 1.65), (0.22, 0.06))):   # a bone-pale cross on the lid
        o = prim("cube", nm, trim)
        hang(o, "pelvis", Matrix.Translation(at(c_[0] * S, -dep - 0.02 * S, c_[1] * S)) @ Rz.to_4x4() @ Matrix.Diagonal((sc_[0] * S, 0.018 * S, sc_[1] * S, 1)))

# ---- poses from the pack's rig; weapons re-hung on the body's hands
ret = rt.Retarget(src, dst, rt.KAYKIT_TO_GAME)
for m_ in {sl.material for ob in weap.values() for sl in ob.material_slots if sl.material}:
    b_ = m_.node_tree.nodes.get("Principled BSDF") if m_.use_nodes else None
    if b_ and b_.inputs["Base Color"].links:
        src_sock = b_.inputs["Base Color"].links[0].from_socket
        hs = m_.node_tree.nodes.new("ShaderNodeHueSaturation")
        hs.inputs["Saturation"].default_value = 0.9
        hs.inputs["Value"].default_value = float(E("WDARK", "0.6"))
        m_.node_tree.links.new(src_sock, hs.inputs["Color"])
        m_.node_tree.links.new(hs.outputs["Color"], b_.inputs["Base Color"])
def _hammer():
    """a war hammer along +Z, grip at the origin, in the pack sword's size (about 1.8 long before scaling)."""
    me = bpy.data.meshes.new("hammer")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.045, radius2=0.045, depth=1.5, matrix=Matrix.Translation((0, 0, 0.55)))
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0, 0, 1.25)) @ Matrix.Diagonal((0.46, 0.24, 0.26, 1)))
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material("hammer_shaft", LEATHER))
    me.materials.append(material("hammer_head", STEEL_L, 1.0))
    for p_ in me.polygons:
        p_.material_index = 1 if p_.center.z > 1.0 and abs(p_.center.z - 1.3) > 0.005 else 0
    return me


def _shovel():
    """a spade along +Z, grip at the origin."""
    me = bpy.data.meshes.new("shovel")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.04, radius2=0.04, depth=1.7, matrix=Matrix.Translation((0, 0, 0.6)))
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0, 0, 1.6)) @ Matrix.Diagonal((0.36, 0.05, 0.5, 1)))
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material("shovel_shaft", LEATHER))
    me.materials.append(material("shovel_blade", STEEL_D, 1.0))
    for p_ in me.polygons:
        p_.material_index = 1 if p_.center.z > 1.34 and abs(p_.center.z - 1.45) > 0.005 else 0
    return me


MESHES = {"hammer": _hammer, "shovel": _shovel}
held = []                                        # (the pack's weapon on its own rig, our copy, hand bone, palm point, scale)
for name, ob in weap.items():
    bone, scale = kit["weapons"][name][:2]
    cp = ob.copy()
    if len(kit["weapons"][name]) > 2:                         # our own mesh, turned by the pack's weapon
        cp.data = MESHES[kit["weapons"][name][2]]()
    cp.parent = None
    cp.name = "held_" + name
    bpy.context.scene.collection.objects.link(cp)
    ob.hide_render = True
    hb = dst.data.bones[bone]
    palm = hb.matrix_local.inverted() @ (hb.head_local + (hb.tail_local - hb.head_local) * 0.75)
    held.append((ob, cp, bone, palm, tuple(k * S for k in scale)))


def place_weapons():
    """each weapon turns exactly as the pack's animator turned it, and sits in our hand."""
    vl.update()
    for ob, cp, bone, palm, scale in held:
        m = ob.matrix_world.to_3x3().normalized().to_4x4() @ Matrix.Diagonal((*scale, 1))
        m.translation = dst.matrix_world @ dst.pose.bones[bone].matrix @ palm
        cp.matrix_world = m


# ---- camera and lights on a turntable (the rigs stay unturned so world-space pose copying stays simple)
sc = bpy.context.scene
res = int(E("RES", "576"))
sc.render.engine = "CYCLES"
sc.cycles.samples = int(E("SAMPLES", "32"))
sc.cycles.use_denoising = False
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = res
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Standard"
pivot = bpy.data.objects.new("pivot", None)
sc.collection.objects.link(pivot)
pivot.rotation_euler = (0, 0, -math.radians(float(E("YAW", "-70"))))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
cam.parent = pivot
cam.data.type = "ORTHO"
cam.data.ortho_scale = float(E("ORTHO", "4.59"))
el = math.radians(float(E("ELEV", "20")))
cz = float(E("CAMZ", "1.0"))
cam.location = (0, -12 * math.cos(el), cz + 12 * math.sin(el))
cam.rotation_euler = (math.pi / 2 - el, 0, 0)
sc.camera = cam


def sun(name, rot, power, col):
    l = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
    l.data.energy = power
    l.data.color = col
    l.data.angle = math.radians(4)
    l.rotation_euler = [math.radians(a) for a in rot]
    l.parent = pivot
    sc.collection.objects.link(l)


sun("key", (50, 0, 35), float(E("KEY", "6.0")), (1.0, 0.93, 0.85))
sun("rim", (60, 0, 200), float(E("RIM", "4.5")), (0.55, 0.65, 1.0))
w = bpy.data.worlds.new("w")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.3, 0.36, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = float(E("AMB", "0.7"))

CURL = math.radians(float(E("CURL", "55")))


def curl_fingers():
    for n in FINGERS:
        pb = dst.pose.bones.get(n)
        if pb and not n.startswith("thumb"):
            pb.matrix_basis = Matrix.Rotation(CURL * (1 if n.endswith("_l") else 1), 4, E("CURLAX", "X"))


ID_MATS = [m_ for m_ in bpy.data.materials if m_.use_nodes and m_.users]
for k_, m_ in enumerate(ID_MATS):
    nt = m_.node_tree
    outn = next(n_ for n_ in nt.nodes if n_.type == "OUTPUT_MATERIAL")
    em = nt.nodes.new("ShaderNodeEmission")
    em.name = "id_em"
    em.inputs["Color"].default_value = (((k_ + 1) * 8 % 256) / 255.0, ((k_ + 1) // 32 * 64 + 40) / 255.0, 0.5, 1)
    m_["id_surface"] = outn.inputs["Surface"].links[0].from_node.name


def id_mode(on):
    """on: every material is one flat colour (which material is where); off: the real shading."""
    for m_ in ID_MATS:
        nt = m_.node_tree
        outn = next(n_ for n_ in nt.nodes if n_.type == "OUTPUT_MATERIAL")
        node = nt.nodes["id_em"] if on else nt.nodes[m_["id_surface"]]
        nt.links.new(node.outputs[0], outn.inputs["Surface"])
    sc.cycles.samples = 1 if on else int(E("SAMPLES", "32"))
    sc.cycles.filter_width = 0.01 if on else 1.5
    sc.view_settings.view_transform = "Raw" if on else "Standard"


os.makedirs(out, exist_ok=True)
src.hide_render = True
if E("STILL"):
    place_weapons()
    sc.render.resolution_x = sc.render.resolution_y = 900
    for nm, yaw in (("front", 0), ("side", -70), ("back", 180)):
        pivot.rotation_euler = (0, 0, -math.radians(yaw))
        sc.render.filepath = os.path.join(out, "still_%s.png" % nm)
        bpy.ops.render.render(write_still=True)
    sys.exit(0)
ad = src.animation_data
meta = {}
for spec in acts.split(","):
    name, n = spec.split(":")
    n = int(n)
    a = bpy.data.actions[name]
    ad.action = a
    if getattr(a, "slots", None):
        ad.action_slot = a.slots[0]
    f0, f1 = a.frame_range
    loop = name.startswith(("Walking", "Running", "Idle"))
    for i in range(n):
        t = f0 + (f1 - f0) * (i / n if loop else i / (n - 1))
        sc.frame_set(int(t), subframe=t - int(t))
        ret.apply()
        curl_fingers()
        for bn_, deg_ in kit.get("pose", {}).items():     # an arm raised: turned about its own joint, about the world x axis
            vl.update()
            pb_ = dst.pose.bones[bn_]
            h_ = dst.matrix_world @ pb_.head
            R_ = Matrix.Translation(h_) @ Matrix.Rotation(math.radians(deg_), 4, "X") @ Matrix.Translation(-h_)
            pb_.matrix = dst.matrix_world.inverted() @ R_ @ dst.matrix_world @ pb_.matrix
        if kit.get("armout") and name.startswith(("Walking", "Idle")):    # arms held out of the box's sides, not swinging across the lid
            for bn_ in kit["armout"]:
                dst.pose.bones[bn_].matrix_basis = Matrix()
            for bn_, steps_ in kit["armout"].items():
                for ax_, deg_ in steps_:
                    vl.update()
                    pb_ = dst.pose.bones[bn_]
                    h_ = dst.matrix_world @ pb_.head
                    R_ = Matrix.Translation(h_) @ Matrix.Rotation(math.radians(deg_), 4, ax_) @ Matrix.Translation(-h_)
                    pb_.matrix = dst.matrix_world.inverted() @ R_ @ dst.matrix_world @ pb_.matrix
        for bn, k in dict(kit.get("bulk", {}), **({"spine_02": 1.2} if RACE == "dwarf" else {})).items():
            dst.pose.bones[bn].scale = (k, k, k)
        place_weapons()
        vl.update()
        place_dangle()
        sc.render.filepath = os.path.join(out, "%s_%02d.png" % (name, i))
        bpy.ops.render.render(write_still=True)
        id_mode(True)
        sc.render.filepath = os.path.join(out, "%s_%02d_id.png" % (name, i))
        bpy.ops.render.render(write_still=True)
        id_mode(False)
    meta[name] = n
json.dump(meta, open(os.path.join(out, "meta.json"), "w"))

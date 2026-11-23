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
GOLD, BONE = (0.72, 0.52, 0.16), (0.78, 0.74, 0.62)
RACE = E("RACE", "human")                        # race = body + skin colour + a head feature that reads at 56 px
SKIN = {"elf": (0.56, 0.42, 0.35), "dwarf": (0.5, 0.3, 0.22)}.get(RACE, (0.55, 0.36, 0.27))

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
    o = prim("cube", "brow", (0.03, 0.07, 0.02))
    hang(o, "head", trs(Vector((0, lo.y + half.y * 0.42, eye_z + half.z * 0.2)), (10, 0, 0), (half.x * 1.04, half.y * 0.5, half.z * 0.1)))
    for sg in (1, -1):
        o = prim("sphere", "eye%d" % sg, (1.0, 0.25, 0.05))
        bs = o.data.materials[0].node_tree.nodes["Principled BSDF"]
        bs.inputs["Emission Color"].default_value = (1.0, 0.3, 0.05, 1)
        bs.inputs["Emission Strength"].default_value = 6.0
        hang(o, "head", trs(Vector((sg * half.x * 0.78, lo.y + half.y * 0.5, eye_z)), (0, 0, 0), (half.x * 0.3, half.y * 0.22, half.z * 0.11)))
        e = prim("cone", "ear%d" % sg, kit["skin"].get("head", kit["skin"]["*"]))
        hang(e, "head", trs(Vector((sg * half.x * 1.1, c.y + half.y * 0.25, eye_z + half.z * 0.05)), (-55, sg * 25, 0), (half.x * 0.16, half.y * 0.1, half.z * 0.34)))
    o = prim("cube", "jaw", (0.07, 0.15, 0.04))
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


MESHES = {"hammer": _hammer}
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
        for bn, k in dict(kit.get("bulk", {}), **({"spine_02": 1.2} if RACE == "dwarf" else {})).items():
            dst.pose.bones[bn].scale = (k, k, k)
        place_weapons()
        vl.update()
        sc.render.filepath = os.path.join(out, "%s_%02d.png" % (name, i))
        bpy.ops.render.render(write_still=True)
        id_mode(True)
        sc.render.filepath = os.path.join(out, "%s_%02d_id.png" % (name, i))
        bpy.ops.render.render(write_still=True)
        id_mode(False)
    meta[name] = n
json.dump(meta, open(os.path.join(out, "meta.json"), "w"))

"""Four-legged beasts built from simple shapes and moved by code, rendered to the same raw frames as build_hero.py.

    python3 -I build_beast.py -- <outdir> <kind> <Action:frames,...>

No rig and no outside asset: each part hangs on a joint (an empty) and every action is a function of its phase, so the
motion is the same for every kind and right by construction (four legs, a diagonal gait, feet on the ground).
Actions: Idle, Walking_A, Attack, Hit_A, Death_A.  The beast faces -Y like the heroes; the camera, lights and the
material-ID pass match build_hero.py, so post.py reads the output unchanged.
env: RES (576), ORTHO (4.59), YAW (-70), ELEV (20), SAMPLES (24)
"""
import json
import math
import os
import sys

import bpy
import bmesh  # noqa: E402 (after bpy)
from mathutils import Euler, Matrix, Vector

out, kind_name, acts = sys.argv[sys.argv.index("--") + 1:]
E = os.environ.get

# size in metres: body length, body radius, shoulder height, head radius, snout length, ear, tail length;
# colours: coat, belly/dark, eye (lit), teeth; extras
KINDS = {
    "wood_wolf": dict(len=1.25, rad=0.24, h=0.78, head=0.2, snout=0.26, ear=0.14, tail=0.55, tail_up=-25,
                      coat=(0.16, 0.15, 0.14), dark=(0.07, 0.07, 0.08), eye=(1.0, 0.75, 0.1), mane=True),
    "hound": dict(len=1.1, rad=0.2, h=0.72, head=0.18, snout=0.24, ear=0.1, tail=0.4, tail_up=10,
                  coat=(0.1, 0.06, 0.05), dark=(0.04, 0.03, 0.03), eye=(1.0, 0.15, 0.05), ribs=True),
    "pit_hound": dict(len=1.5, rad=0.32, h=0.95, head=0.26, snout=0.3, ear=0.12, tail=0.5, tail_up=20,
                      coat=(0.05, 0.04, 0.05), dark=(0.02, 0.02, 0.02), eye=(1.0, 0.4, 0.05), spikes=True, ember=True),
    "plague_rat": dict(len=0.62, rad=0.15, h=0.26, head=0.11, snout=0.14, ear=0.07, tail=0.6, tail_up=-5,
                       coat=(0.17, 0.14, 0.11), dark=(0.3, 0.2, 0.2), eye=(0.9, 0.1, 0.1), boils=True, thin_tail=True),
    "noose_spider": dict(plan="spider", rad=0.3, h=0.42, coat=(0.06, 0.05, 0.07), dark=(0.02, 0.02, 0.03), eye=(1.0, 0.2, 0.1),
                         mark=(0.5, 0.42, 0.2)),
    "wisp": dict(plan="float", rad=0.2, h=1.0, coat=(0.3, 0.9, 0.8), dark=(0.9, 1.0, 1.0), eye=(0.02, 0.05, 0.05), glow=1.2, tails=3),
    "marsh_light": dict(plan="float", rad=0.26, h=0.8, coat=(0.5, 0.95, 0.2), dark=(0.95, 1.0, 0.6), eye=(0.03, 0.06, 0.0), glow=1.2, tails=5),
    "void_eye": dict(plan="float", rad=0.42, h=1.2, coat=(0.1, 0.04, 0.14), dark=(0.85, 0.8, 0.75), eye=(0.9, 0.05, 0.3), glow=0.0, tails=6, iris=True),
    "carrion_crow": dict(plan="bird", rad=0.17, h=0.75, coat=(0.035, 0.035, 0.05), dark=(0.012, 0.012, 0.02), eye=(1.0, 0.15, 0.05), beak=(0.5, 0.42, 0.25)),
    "leech": dict(plan="worm", rad=0.14, h=0.14, coat=(0.1, 0.03, 0.05), dark=(0.3, 0.07, 0.08), eye=(0.75, 0.6, 0.5), segs=6),
    "toadstone": dict(plan="toad", rad=0.34, h=0.3, coat=(0.2, 0.26, 0.12), dark=(0.42, 0.4, 0.3), eye=(1.0, 0.7, 0.1), cap=(0.5, 0.1, 0.08)),
}
K = KINDS[kind_name]
PLAN = K.get("plan", "quad")
BONE = (0.78, 0.74, 0.62)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col = sc.collection


def material(name, colr, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*colr, 1)
    b.inputs["Roughness"].default_value = 0.6
    if emit:
        b.inputs["Emission Color"].default_value = (*colr, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


MATS = {}


def mat(name, colr, emit=0.0):
    if name not in MATS:
        MATS[name] = material(name, colr, emit)
    return MATS[name]


def joint(name, parent, loc):
    e = bpy.data.objects.new(name, None)
    col.objects.link(e)
    e.parent = parent
    e.location = loc
    return e


def part(kind, name, parent, m, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), r2=0.0):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    if kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=1.0)
    elif kind == "cone":                         # along Z, base at -1, tip at +1
        bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=1.0, radius2=r2, depth=2.0)
    else:
        bmesh.ops.create_cube(bm, size=2.0)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    me.materials.append(m)
    ob.parent = parent
    ob.location = loc
    ob.rotation_euler = [math.radians(a) for a in rot]
    ob.scale = scale
    return ob


R, H = K["rad"], K["h"]
coat, dark = mat("coat", K["coat"], K.get("glow", 0.0)), mat("dark", K["dark"], K.get("glow", 0.0) * 1.3)
root = joint("root", None, (0, 0, 0))
body = joint("body", root, (0, 0, H))


def rx(ob, deg):
    ob.rotation_euler = Euler((math.radians(deg), 0, 0))


if PLAN == "spider":                             # eight legs in two alternating sets of four, a fat abdomen with a mark
    part("sphere", "abdomen", body, coat, (0, R * 1.3, R * 0.25), (0, 0, 0), (R * 1.1, R * 1.4, R * 1.0))
    part("sphere", "mark", body, mat("mark", K["mark"]), (0, R * 1.5, R * 1.05), (0, 0, 0), (R * 0.4, R * 0.6, R * 0.25))
    part("sphere", "thorax", body, dark, (0, -R * 0.3, 0), (0, 0, 0), (R * 0.75, R * 0.9, R * 0.6))
    for sg in (1, -1):
        part("sphere", "eye%d" % sg, body, mat("eye", K["eye"], 6.0), (sg * R * 0.25, -R * 1.1, R * 0.2), (0, 0, 0), (R * 0.14, R * 0.14, R * 0.14))
        part("cone", "fang%d" % sg, body, mat("bone", BONE), (sg * R * 0.2, -R * 1.2, -R * 0.3), (180, 0, 0), (R * 0.08, R * 0.08, R * 0.3))
    slegs = []
    for i, yaw in enumerate((40, 75, 105, 140)):
        for sg in (1, -1):
            hip = joint("hip%d%d" % (i, sg), body, (sg * R * 0.5, -R * 0.3, 0))
            base = math.radians(sg * yaw - 90 * 0)   # yaw 0 = forward (-Y); legs fan out to the side
            hip["base"] = sg * math.radians(yaw)
            seg1 = R * 2.0
            part("cone", "femur%d%d" % (i, sg), hip, dark, (0, -seg1 * 0.5, 0), (90, 0, 0), (R * 0.12, R * 0.12, seg1 * 0.52), r2=0.8)
            knee = joint("knee%d%d" % (i, sg), hip, (0, -seg1, 0))
            seg2 = R * 2.6
            part("cone", "tibia%d%d" % (i, sg), knee, coat, (0, -seg2 * 0.5, 0), (90, 0, 0), (R * 0.09, R * 0.09, seg2 * 0.52), r2=0.3)
            slegs.append((hip, knee, (i + (0 if sg > 0 else 1)) % 2))

    def pose(action, u):
        w = 2 * math.pi * u
        body.location, body.rotation_euler = (0, 0, H), Euler((0, 0, 0))
        lift_all, splay, lunge = 0.0, 0.0, 0.0
        if action == "Idle":
            body.location = (0, 0, H + 0.015 * math.sin(w))
        elif action == "Attack":
            a = math.sin(math.pi * u)
            body.location = (0, -R * 1.6 * a, H + R * 0.5 * a)
            body.rotation_euler = Euler((math.radians(22 * a), 0, 0))
            lunge = a
        elif action == "Hit_A":
            a = math.sin(math.pi * u)
            body.location = (0, R * 0.8 * a, H - R * 0.2 * a)
            body.rotation_euler = Euler((math.radians(-14 * a), 0, math.radians(8 * a)))
        elif action == "Death_A":                # flips onto its back and the legs curl in
            a = min(1.0, u * 1.5)
            body.rotation_euler = Euler((0, math.radians(180 * a), 0))
            body.location = (0, 0, H + R * 0.6 * math.sin(math.pi * a) - (H - R * 0.9) * a)
            splay = a
        for hip, knee, grp in slegs:
            sw, lift = 0.0, 0.0
            if action == "Walking_A":
                ph = w + grp * math.pi
                sw, lift = 16 * math.sin(ph), 16 * max(0.0, math.cos(ph))
            up_deg = 38 + lift + 30 * lunge * (1 if abs(hip["base"]) < 1.0 else 0) + 20 * splay
            hip.rotation_euler = Euler((math.radians(-up_deg), 0, hip["base"] + math.radians(sw) * (1 if hip["base"] > 0 else -1)), "ZXY")
            knee.rotation_euler = Euler((math.radians(100 - lift * 0.6 + 50 * splay), 0, 0))

elif PLAN == "float":                            # a drifting light or eye with trailing tails; it never touches the ground
    part("sphere", "core", body, dark, (0, 0, 0), (0, 0, 0), (R * 0.6, R * 0.6, R * 0.6))
    part("sphere", "halo", body, coat, (0, R * 0.12, 0), (0, 0, 0), (R, R, R))
    if K.get("iris"):
        part("sphere", "white", body, dark, (0, -R * 0.5, 0), (0, 0, 0), (R * 0.75, R * 0.6, R * 0.75))
        part("sphere", "iris", body, mat("eye", K["eye"], 5.0), (0, -R * 0.95, 0), (0, 0, 0), (R * 0.4, R * 0.25, R * 0.4))
        part("sphere", "pupil", body, mat("pupil", (0.0, 0.0, 0.0)), (0, -R * 1.12, 0), (0, 0, 0), (R * 0.18, R * 0.14, R * 0.22))
    else:
        for sg in (1, -1):
            part("sphere", "eye%d" % sg, body, mat("eye", K["eye"]), (sg * R * 0.3, -R * 0.75, R * 0.1), (0, 0, 0), (R * 0.14, R * 0.12, R * 0.2))
    ftails = []
    nt_ = K["tails"]
    for i in range(nt_):
        ang = 2 * math.pi * i / nt_
        tj = joint("ftail%d" % i, body, (math.cos(ang) * R * 0.55, R * 0.2 + math.sin(ang) * R * 0.3, -R * 0.6))
        part("cone", "ftail_a%d" % i, tj, coat, (0, 0, -R * 0.6), (180, 0, 0), (R * 0.2, R * 0.2, R * 0.65), r2=0.5)
        tk = joint("ftailk%d" % i, tj, (0, 0, -R * 1.2))
        part("cone", "ftail_b%d" % i, tk, coat, (0, 0, -R * 0.55), (180, 0, 0), (R * 0.1, R * 0.1, R * 0.6))
        ftails.append((tj, tk, ang))

    def pose(action, u):
        w = 2 * math.pi * u
        z, y, sc_, lean = H + 0.05 * math.sin(w), 0.0, 1.0, 0.0
        if action == "Walking_A":
            z, lean = H + 0.08 * math.sin(w), 14
        elif action == "Attack":
            a = math.sin(math.pi * u)
            y, sc_, lean = -R * 2.2 * a, 1 + 0.35 * a, 25 * a
        elif action == "Hit_A":
            a = math.sin(math.pi * u)
            y, sc_ = R * 1.2 * a, 1 - 0.25 * a
        elif action == "Death_A":                # gutters, shrinks and sinks to the ground
            a = min(1.0, u * 1.3)
            z, sc_ = H - (H - R * 0.3) * a * a, max(0.3, 1 - 0.7 * a)
        body.location = (0, y, z)
        body.scale = (sc_, sc_, sc_)
        body.rotation_euler = Euler((math.radians(-lean), 0, 0))
        for tj, tk, ang in ftails:
            tj.rotation_euler = Euler((math.radians(-lean * 1.5 + 12 * math.sin(w + ang)), math.radians(12 * math.cos(w + ang)), 0))
            tk.rotation_euler = Euler((math.radians(16 * math.sin(w + ang + 1.0)), 0, 0))

elif PLAN == "bird":                             # a crow on the wing: it never lands, the wings beat about the spine
    part("sphere", "trunk", body, coat, (0, 0, 0), (0, 0, 0), (R * 0.75, R * 1.5, R * 0.7))
    part("sphere", "bhead", body, coat, (0, -R * 1.6, R * 0.35), (0, 0, 0), (R * 0.55, R * 0.6, R * 0.55))
    part("cone", "beak", body, mat("beak", K["beak"]), (0, -R * 2.5, R * 0.25), (100, 0, 0), (R * 0.2, R * 0.2, R * 0.5))
    part("cone", "btail", body, dark, (0, R * 2.0, 0), (-80, 0, 0), (R * 0.55, R * 0.12, R * 0.8), r2=0.6)
    for sg in (1, -1):
        part("sphere", "beye%d" % sg, body, mat("eye", K["eye"], 4.0), (sg * R * 0.42, -R * 1.85, R * 0.48), (0, 0, 0), (R * 0.13, R * 0.13, R * 0.13))
    wings = []
    for sg in (1, -1):
        wj = joint("wing%d" % sg, body, (sg * R * 0.5, -R * 0.2, R * 0.35))
        part("cube", "wing_a%d" % sg, wj, coat, (sg * R * 1.0, 0, 0), (0, 0, 0), (R * 1.0, R * 0.8, R * 0.07))
        wk = joint("wingk%d" % sg, wj, (sg * R * 2.0, 0, 0))
        part("cube", "wing_b%d" % sg, wk, dark, (sg * R * 0.9, R * 0.15, 0), (0, 0, sg * -12), (R * 0.95, R * 0.6, R * 0.05))
        wings.append((wj, wk, sg))

    def pose(action, u):
        w = 2 * math.pi * u
        flap, z, y, pitch, roll = math.sin(w), H + 0.06 * math.cos(w), 0.0, 0.0, 0.0
        if action == "Walking_A":
            pitch = 10
        elif action == "Attack":                 # a stoop: wings folded back, beak first, then up again
            a = math.sin(math.pi * u)
            y, z, pitch, flap = -R * 2.5 * a, H - 0.3 * a, 40 * a, flap * (1 - a) - 0.6 * a
        elif action == "Hit_A":
            a = math.sin(math.pi * u)
            y, pitch, roll = R * 1.5 * a, -30 * a, 25 * a
        elif action == "Death_A":                # falls out of the air and lies with the wings spread
            a = min(1.0, u * 1.4)
            z, roll, flap, pitch = H - (H - R * 0.6) * a * a, 170 * a, 0.9 * (1 - a) - 0.15, 0.0
        body.location = (0, y, z)
        body.rotation_euler = Euler((math.radians(-pitch), math.radians(roll), 0))
        for wj, wk, sg in wings:
            wj.rotation_euler = Euler((0, math.radians(-sg * 42 * flap), 0))
            wk.rotation_euler = Euler((0, math.radians(-sg * (22 * flap - 14)), 0))

elif PLAN == "worm":                             # a leech: fat segments that hump along the ground, a pale ring of a mouth
    segs = []
    ns_ = K["segs"]
    for i in range(ns_):
        t = i / (ns_ - 1)
        fat = R * (0.75 + 0.5 * math.sin(math.pi * (0.15 + 0.8 * t)))
        sj = joint("seg%d" % i, root, (0, (i - (ns_ - 1) / 2) * R * 1.25, fat))
        part("sphere", "seg_m%d" % i, sj, coat if i % 2 == 0 else dark, (0, 0, 0), (0, 0, 0), (fat * 1.05, R * 0.95, fat))
        segs.append((sj, fat))
    part("sphere", "mouth", segs[0][0], mat("eye", K["eye"]), (0, -R * 0.75, 0), (0, 0, 0), (R * 0.5, R * 0.3, R * 0.5))
    part("sphere", "gullet", segs[0][0], mat("pupil", (0.05, 0.0, 0.0)), (0, -R * 0.98, 0), (0, 0, 0), (R * 0.28, R * 0.14, R * 0.28))

    def pose(action, u):
        w = 2 * math.pi * u
        for i, (sj, fat) in enumerate(segs):
            y0 = (i - (ns_ - 1) / 2) * R * 1.25
            z, y, sc_ = fat, y0, 1.0
            front = 1 - i / (ns_ - 1)
            if action == "Walking_A":
                z = fat + R * 0.75 * max(0.0, math.sin(w - i * 1.0))
                y = y0 - R * 0.25 * math.cos(w - i * 1.0)
            elif action == "Idle":
                z = fat + R * 0.12 * math.sin(w - i * 0.8)
            elif action == "Attack":             # rears up and strikes forward
                a = math.sin(math.pi * u)
                z, y = fat + R * 3.2 * a * front * front, y0 - R * 1.6 * a * front * (1.6 * u)
            elif action == "Hit_A":
                a = math.sin(math.pi * u)
                y, z = y0 + R * 0.9 * a, fat + R * 0.5 * a * (1 - front)
            elif action == "Death_A":            # bursts flat
                a = min(1.0, u * 1.3)
                z, sc_ = fat * (1 - 0.6 * a), 1 - 0.55 * a
            sj.location = (0, y, z)
            sj.scale = (1.0 + (1 - sc_) * 0.8, 1.0, sc_)

elif PLAN == "toad":                             # a squat toad with toadstools on its back; it hops and spits
    part("sphere", "trunk", body, coat, (0, R * 0.1, 0), (-12, 0, 0), (R * 1.0, R * 1.15, R * 0.75))
    part("sphere", "thead", body, coat, (0, -R * 0.85, R * 0.12), (0, 0, 0), (R * 0.8, R * 0.6, R * 0.5))
    jaw = joint("tjaw", body, (0, -R * 0.6, -R * 0.05))
    part("sphere", "tjaw_m", jaw, dark, (0, -R * 0.35, -R * 0.12), (0, 0, 0), (R * 0.72, R * 0.55, R * 0.22))
    for sg in (1, -1):
        part("sphere", "teye%d" % sg, body, mat("eye", K["eye"], 3.0), (sg * R * 0.45, -R * 0.95, R * 0.5), (0, 0, 0), (R * 0.2, R * 0.2, R * 0.2))
        part("sphere", "tpupil%d" % sg, body, mat("pupil", (0.0, 0.0, 0.0)), (sg * R * 0.5, -R * 1.1, R * 0.52), (0, 0, 0), (R * 0.07, R * 0.07, R * 0.14))
    capm = mat("cap", K["cap"])
    for cx, cy, cs in ((0.0, 0.35, 0.42), (0.45, 0.1, 0.28), (-0.4, 0.55, 0.3), (0.15, 0.85, 0.24)):
        part("cone", "stalk", body, dark, (cx * R, cy * R, R * 0.75), (0, 0, 0), (cs * R * 0.3, cs * R * 0.3, R * 0.25), r2=0.8)
        part("sphere", "cap", body, capm, (cx * R, cy * R, R * 1.0), (0, 0, 0), (cs * R, cs * R, cs * R * 0.55))
    tlegs = []
    for sg in (1, -1):
        for fr_, ly in ((True, -0.6), (False, 0.75)):
            lj = joint("tleg%d%d" % (sg, fr_), body, (sg * R * 0.8, ly * R, -R * 0.2))
            part("sphere", "tleg_m%d%d" % (sg, fr_), lj, coat, (sg * R * 0.15, 0, -R * 0.3), (0, 0, 0), (R * 0.26, R * (0.3 if fr_ else 0.5), R * 0.36))
            part("sphere", "tfoot%d%d" % (sg, fr_), lj, dark, (sg * R * 0.22, -R * 0.25, -R * 0.62), (0, 0, 0), (R * 0.24, R * 0.4, R * 0.1))
            tlegs.append((lj, fr_))

    def pose(action, u):
        w = 2 * math.pi * u
        z, y, pitch, sq, mouth, kick = H, 0.0, 0.0, 1 + 0.04 * math.sin(w), 0.0, 0.0
        if action == "Walking_A":                # one hop a cycle
            a = max(0.0, math.sin(w))
            z, pitch, kick, sq = H + R * 1.1 * a, 18 * math.cos(w) * (1 if a > 0 else 0), 55 * a, 1 - 0.12 * max(0.0, -math.sin(w))
        elif action == "Attack":                 # rears back, then spits
            a = math.sin(math.pi * u)
            pitch, mouth, y = -28 * a if u < 0.5 else 14 * a, 38 * a, -R * 0.5 * a * (1 if u > 0.5 else 0)
        elif action == "Hit_A":
            a = math.sin(math.pi * u)
            y, sq, pitch = R * 0.8 * a, 1 - 0.25 * a, -10 * a
        elif action == "Death_A":                # sags flat, mouth open
            a = min(1.0, u * 1.3)
            sq, mouth, z = 1 - 0.55 * a, 30 * a, H * (1 - 0.45 * a)
        body.location = (0, y, z)
        body.scale = (1 + (1 - sq) * 0.6, 1.0, sq)
        body.rotation_euler = Euler((math.radians(pitch), 0, 0))
        jaw.rotation_euler = Euler((math.radians(mouth), 0, 0))
        for lj, fr_ in tlegs:
            lj.rotation_euler = Euler((math.radians(-kick if not fr_ else kick * 0.4), 0, 0))

else:
    L = K["len"]
    leg_len = H - R * 0.6
    up, lo = leg_len * 0.52, leg_len * 0.5

    part("sphere", "barrel", body, coat, (0, 0, 0), (0, 0, 0), (R, L * 0.5, R))
    part("sphere", "chest", body, coat, (0, -L * 0.28, R * 0.08), (0, 0, 0), (R * 1.12, L * 0.26, R * 1.15))
    part("sphere", "haunch", body, coat, (0, L * 0.3, 0), (0, 0, 0), (R * 1.02, L * 0.22, R * 1.0))
    part("sphere", "underside", body, dark, (0, 0, -R * 0.35), (0, 0, 0), (R * 0.8, L * 0.42, R * 0.72))
    if K.get("mane"):
        part("cone", "mane", body, dark, (0, -L * 0.3, R * 0.95), (-100, 0, 0), (R * 0.5, R * 0.5, L * 0.22))
    if K.get("ribs"):
        for i in range(3):
            part("cube", "rib%d" % i, body, mat("bone", BONE), (0, -L * 0.12 + i * L * 0.11, 0), (0, 0, 0), (R * 1.03, 0.012, R * 0.8))
    if K.get("spikes"):
        for i in range(5):
            part("cone", "spike%d" % i, body, mat("bone", BONE), (0, -L * 0.36 + i * L * 0.17, R * 1.1), (-12, 0, 0), (0.05, 0.05, 0.16))
    if K.get("ember"):
        part("sphere", "ember", body, mat("ember", (1.0, 0.3, 0.05), 5.0), (0, -L * 0.05, -R * 0.55), (0, 0, 0), (R * 0.5, L * 0.3, R * 0.45))
    if K.get("boils"):
        for i, (x, y) in enumerate(((0.6, -0.1), (-0.5, 0.15), (0.2, 0.3))):
            part("sphere", "boil%d" % i, body, mat("boil", (0.5, 0.42, 0.2)), (x * R, y * L, R * 0.8), (0, 0, 0), (R * 0.3, R * 0.3, R * 0.3))

    neck = joint("neck", body, (0, -L * 0.42, R * 0.45))
    part("cone", "neck_m", neck, coat, (0, -K["head"] * 0.4, K["head"] * 0.25), (65, 0, 0), (R * 0.75, R * 0.75, K["head"] * 0.9), r2=0.7)
    head = joint("head", neck, (0, -K["head"] * 1.0, K["head"] * 0.7))
    hd = K["head"]
    part("sphere", "skull", head, coat, (0, 0, 0), (0, 0, 0), (hd * 0.85, hd, hd * 0.85))
    part("cone", "snout", head, coat, (0, -hd * 0.8 - K["snout"] * 0.4, -hd * 0.12), (90, 0, 0), (hd * 0.5, hd * 0.42, K["snout"] * 0.6), r2=0.55)
    part("sphere", "nose", head, dark, (0, -hd * 0.8 - K["snout"] * 0.98, -hd * 0.08), (0, 0, 0), (hd * 0.2, hd * 0.16, hd * 0.16))
    jaw = joint("jaw", head, (0, -hd * 0.5, -hd * 0.42))
    part("cone", "jaw_m", jaw, dark, (0, -K["snout"] * 0.55, 0), (90, 0, 0), (hd * 0.4, hd * 0.2, K["snout"] * 0.55), r2=0.5)
    for sg in (1, -1):
        part("sphere", "eye%d" % sg, head, mat("eye", K["eye"], 6.0), (sg * hd * 0.6, -hd * 0.55, hd * 0.28), (0, 0, 0), (hd * 0.2, hd * 0.2, hd * 0.16))
        part("cone", "ear%d" % sg, head, dark, (sg * hd * 0.5, hd * 0.35, hd * 0.85), (-15, sg * 18, 0), (hd * 0.26, hd * 0.14, K["ear"]))
        part("cone", "fang%d" % sg, head, mat("bone", BONE), (sg * hd * 0.26, -hd * 0.8 - K["snout"] * 0.6, -hd * 0.42), (180, 0, 0), (hd * 0.07, hd * 0.07, hd * 0.2))

    tail = []
    tparent, tl = body, K["tail"] / 3
    tw = 0.03 if K.get("thin_tail") else R * 0.36
    for i in range(3):
        tj = joint("tail%d" % i, tparent, (0, L * 0.47, R * 0.3) if i == 0 else (0, tl, 0))
        part("cone", "tail_m%d" % i, tj, mat("tail", K["dark"] if K.get("thin_tail") else K["coat"]), (0, tl * 0.5, 0), (-90, 0, 0),
             (tw * (1 - i * 0.25), tw * (1 - i * 0.25), tl * 0.55), r2=0.7 if i < 2 else 0.1)
        tail.append(tj)
        tparent = tj

    legs = {}
    for nm, y, sg in (("fl", -L * 0.3, 1), ("fr", -L * 0.3, -1), ("bl", L * 0.32, 1), ("br", L * 0.32, -1)):
        hip = joint("hip_" + nm, body, (sg * R * 0.72, y, -R * 0.35))
        part("cone", "upper_" + nm, hip, coat, (0, 0, -up * 0.5), (0, 0, 0), (R * 0.36, R * 0.42, up * 0.56), r2=1.5)
        knee = joint("knee_" + nm, hip, (0, 0, -up))
        part("cone", "lower_" + nm, knee, coat, (0, 0, -lo * 0.5), (0, 0, 0), (R * 0.2, R * 0.22, lo * 0.55), r2=1.3)
        part("sphere", "paw_" + nm, knee, dark, (0, -R * 0.12, -lo), (0, 0, 0), (R * 0.26, R * 0.36, R * 0.16))
        legs[nm] = (hip, knee)


    def pose(action, u):
        """u in 0..1: the phase of a loop, or the progress of a one-shot."""
        root.location, root.rotation_euler = (0, 0, 0), Euler((0, 0, 0))
        body.location, body.rotation_euler = (0, 0, H), Euler((0, 0, 0))
        rx(neck, 0)
        rx(head, 0)
        rx(jaw, 0)
        for i, tj in enumerate(tail):
            tj.rotation_euler = Euler((math.radians(K["tail_up"] if i == 0 else -8), 0, 0))
        swing = {k: 0.0 for k in legs}
        bend = {k: 0.0 for k in legs}
        w = 2 * math.pi * u
        if action == "Idle":
            body.location = (0, 0, H - 0.012 * (1 + math.sin(w)))
            rx(head, 4 * math.sin(w))
            tail[1].rotation_euler = Euler((math.radians(-8), 0, math.radians(14 * math.sin(w))))
        elif action == "Walking_A":                  # a trot: diagonal pairs together, the lifted foot bends at the knee
            for k, ph in (("fl", 0.0), ("br", 0.0), ("fr", math.pi), ("bl", math.pi)):
                swing[k] = 30 * math.sin(w + ph)
                bend[k] = 42 * max(0.0, math.cos(w + ph))
            body.location = (0, 0, H - 0.02 + 0.02 * abs(math.sin(w)))
            body.rotation_euler = Euler((math.radians(2.5 * math.sin(2 * w)), 0, 0))
            rx(head, 5 * math.sin(2 * w))
            tail[1].rotation_euler = Euler((math.radians(-8), 0, math.radians(18 * math.sin(w))))
        elif action == "Attack":                     # crouch back, lunge with the jaws open, land
            a = math.sin(math.pi * u)                # 0 -> 1 -> 0
            back = max(0.0, 1 - u * 5)               # the wind-up in the first fifth
            body.location = (0, 0.12 * L * back - 0.38 * L * a, H - 0.06 * back + 0.05 * a)
            body.rotation_euler = Euler((math.radians(-10 * a + 6 * back), 0, 0))
            rx(neck, -14 * a)
            rx(jaw, 38 * a)
            for k in ("fl", "fr"):
                swing[k], bend[k] = -38 * a, 30 * a
            for k in ("bl", "br"):
                swing[k] = 30 * a
        elif action == "Hit_A":                      # knocked back, head thrown up, then back to its feet
            a = math.sin(math.pi * u)
            body.location = (0, 0.14 * L * a, H - 0.05 * a)
            body.rotation_euler = Euler((math.radians(9 * a), 0, math.radians(7 * a)))
            rx(head, -22 * a)
            rx(jaw, 20 * a)
            for k in ("fl", "fr"):
                swing[k] = -16 * a
        elif action == "Death_A":                    # staggers, falls onto its side, legs go slack
            a = min(1.0, u * 1.6)
            fall = a * a
            body.rotation_euler = Euler((0, math.radians(86 * fall), 0))
            body.location = (0, 0, H - (H - R * 1.05) * fall)
            rx(head, 18 * fall)
            rx(jaw, 24 * fall)
            for k in legs:
                swing[k] = (16 if k[0] == "f" else -14) * fall
                bend[k] = 26 * fall
            tail[0].rotation_euler = Euler((math.radians(K["tail_up"] * (1 - fall) - 30 * fall), 0, 0))
        for k, (hip, knee) in legs.items():
            rx(hip, swing[k])
            rx(knee, -bend[k] if k[0] == "f" else bend[k])


# ---- camera, lights and the material-ID pass, as in build_hero.py
res = int(E("RES", "576"))
sc.render.engine = "CYCLES"
sc.cycles.samples = int(E("SAMPLES", "24"))
sc.cycles.use_denoising = False
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = res
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Standard"
pivot = bpy.data.objects.new("pivot", None)
col.objects.link(pivot)
pivot.rotation_euler = (0, 0, -math.radians(float(E("YAW", "-70"))))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
col.objects.link(cam)
cam.parent = pivot
cam.data.type = "ORTHO"
cam.data.ortho_scale = float(E("ORTHO", "4.59"))
el = math.radians(float(E("ELEV", "20")))
cz = float(E("CAMZ", "1.0"))
cam.location = (0, -12 * math.cos(el), cz + 12 * math.sin(el))
cam.rotation_euler = (math.pi / 2 - el, 0, 0)
sc.camera = cam


def sun(name, rot, power, colr):
    l = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
    l.data.energy = power
    l.data.color = colr
    l.data.angle = math.radians(4)
    l.rotation_euler = [math.radians(a) for a in rot]
    l.parent = pivot
    col.objects.link(l)


sun("key", (50, 0, 35), float(E("KEY", "6.0")), (1.0, 0.93, 0.85))
sun("rim", (60, 0, 200), float(E("RIM", "4.5")), (0.55, 0.65, 1.0))
wd = bpy.data.worlds.new("w")
sc.world = wd
wd.use_nodes = True
wd.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.3, 0.36, 1)
wd.node_tree.nodes["Background"].inputs[1].default_value = float(E("AMB", "0.7"))

ID_MATS = [m_ for m_ in bpy.data.materials if m_.use_nodes and m_.users]
for k_, m_ in enumerate(ID_MATS):
    nt = m_.node_tree
    outn = next(n_ for n_ in nt.nodes if n_.type == "OUTPUT_MATERIAL")
    em = nt.nodes.new("ShaderNodeEmission")
    em.name = "id_em"
    em.inputs["Color"].default_value = (((k_ + 1) * 8 % 256) / 255.0, ((k_ + 1) // 32 * 64 + 40) / 255.0, 0.5, 1)
    m_["id_surface"] = outn.inputs["Surface"].links[0].from_node.name


def id_mode(on):
    for m_ in ID_MATS:
        nt = m_.node_tree
        outn = next(n_ for n_ in nt.nodes if n_.type == "OUTPUT_MATERIAL")
        node = nt.nodes["id_em"] if on else nt.nodes[m_["id_surface"]]
        nt.links.new(node.outputs[0], outn.inputs["Surface"])
    sc.cycles.samples = 1 if on else int(E("SAMPLES", "24"))
    sc.cycles.filter_width = 0.01 if on else 1.5
    sc.view_settings.view_transform = "Raw" if on else "Standard"


os.makedirs(out, exist_ok=True)
meta = {}
for spec in acts.split(","):
    name, n = spec.split(":")
    n = int(n)
    loop = name.startswith(("Walking", "Idle"))
    for i in range(n):
        pose(name, i / n if loop else i / (n - 1))
        bpy.context.view_layer.update()
        sc.render.filepath = os.path.join(out, "%s_%02d.png" % (name, i))
        bpy.ops.render.render(write_still=True)
        id_mode(True)
        sc.render.filepath = os.path.join(out, "%s_%02d_id.png" % (name, i))
        bpy.ops.render.render(write_still=True)
        id_mode(False)
    meta[name] = n
json.dump(meta, open(os.path.join(out, "meta.json"), "w"))

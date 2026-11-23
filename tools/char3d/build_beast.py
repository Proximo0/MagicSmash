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
from mathutils import Euler, Matrix, Quaternion, Vector

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
    "shard": dict(plan="crystal", rad=0.2, h=0.78, coat=(0.1, 0.28, 0.9), dark=(0.28, 0.55, 1.0), eye=(0.45, 0.85, 1.0), amb=0.3),
    "cinderling": dict(plan="imp", rad=0.19, h=0.35, coat=(0.008, 0.008, 0.009), dark=(0.5, 0.4, 0.33), eye=(1.0, 0.85, 0.2), amb=0.25, key=3.0, rim=1.5),
    "carrion_crow": dict(plan="bird", rad=0.17, h=0.75, coat=(0.035, 0.035, 0.05), dark=(0.012, 0.012, 0.02), eye=(1.0, 0.15, 0.05), beak=(0.5, 0.42, 0.25)),
    "leech": dict(plan="worm", rad=0.14, h=0.14, coat=(0.1, 0.03, 0.05), dark=(0.3, 0.07, 0.08), eye=(0.75, 0.6, 0.5), segs=6),
    "hanging_tree": dict(plan="tree", rad=0.62, h=0.0, coat=(0.075, 0.052, 0.04), dark=(0.04, 0.03, 0.026), eye=(0.85, 0.95, 0.45),
                         rope=(0.5, 0.4, 0.18), flesh=(0.3, 0.34, 0.36), cloth=(0.13, 0.1, 0.09)),
    "chandelier": dict(plan="chandelier", rad=1.3, h=1.0, tilt=38, coat=(0.1, 0.1, 0.115), dark=(0.02, 0.02, 0.025), eye=(0.55, 0.9, 1.0),
                       brass=(0.5, 0.36, 0.1), wax=(0.85, 0.8, 0.62), pale=(0.72, 0.68, 0.6)),
    "ghostwriter": dict(plan="ghost", rad=0.5, h=1.55, coat=(0.3, 0.46, 0.8), dark=(0.14, 0.24, 0.52), pale=(0.82, 0.92, 1.0), eye=(0.6, 1.0, 1.0), glow=0.12),
    "death_the_pale_rider": dict(plan="rider", rad=0.5, h=0.0, coat=(0.42, 0.4, 0.36), dark=(0.13, 0.12, 0.12), bone=(0.7, 0.67, 0.56), shroud=(0.26, 0.32, 0.42),
                  shroud2=(0.5, 0.54, 0.58), eye=(0.5, 0.9, 1.0)),
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
    elif kind in ("gem", "gemU", "gemL"):         # hexagonal prism with a point: tips at +-1, rings at +-0.4; U / L = one half, flat cut
        def ring(z):
            return [bm.verts.new((math.cos(k * math.pi / 3), math.sin(k * math.pi / 3), z)) for k in range(6)]
        zs = {"gem": (-0.4, 0.4), "gemU": (0.0, 0.4), "gemL": (-0.4, 0.0)}[kind]
        ra, rb = ring(zs[0]), ring(zs[1])
        for k in range(6):
            bm.faces.new((ra[k], ra[(k + 1) % 6], rb[(k + 1) % 6], rb[k]))
        if kind != "gemL":
            tip = bm.verts.new((0, 0, 1.0))
            for k in range(6):
                bm.faces.new((rb[k], rb[(k + 1) % 6], tip))
        else:
            bm.faces.new(rb[::-1])
        if kind != "gemU":
            tip = bm.verts.new((0, 0, -1.0))
            for k in range(6):
                bm.faces.new((ra[(k + 1) % 6], ra[k], tip))
        else:
            bm.faces.new(ra)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
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

elif PLAN == "crystal":                          # a living crystal: two halves of one faceted prism, a glowing core, orbiting shards
    cm = mat("crys", K["coat"], 0.25)
    sm = mat("shd", K["dark"], 0.3)
    km = mat("core", K["eye"], 4.0)
    CL = 0.5
    halves = []
    for nm, kd, sg in (("U", "gemU", 1), ("L", "gemL", -1)):
        hj = joint("half" + nm, body, (0, 0, 0))
        part(kd and "gem" + nm, "crys" + nm, hj, cm, (0, 0, 0), (0, 0, 0), (R, R, CL))
        part("gem" + nm, "core" + nm, hj, km, (0, 0, 0), (0, 0, 0), (R * 0.45, R * 0.45, CL * 1.22))
        part("gem" + nm, "band" + nm, hj, km, (0, 0, 0), (0, 0, 0), (R * 1.12, R * 1.12, 0.1))
        halves.append((hj, sg))
    pU, pL = halves[0][0], halves[1][0]
    debris = []
    for i in range(3):
        dj = joint("deb%d" % i, body, (0, 0, 0))
        part("gem", "debm%d" % i, dj, cm, (0, 0, 0), (0, 0, 0), (0.07, 0.07, 0.16))
        dj.scale = (0, 0, 0)
        debris.append(dj)
    shards = []
    for i in range(3):
        sj = joint("sh%d" % i, body, (0, 0, 0))
        part("gem", "shm%d" % i, sj, sm, (0, 0, 0), (0, 0, 0), (0.09, 0.09, 0.22))
        shards.append((sj, 2 * math.pi * i / 3, (0.38, 0.1, -0.16)[i], (0.5, -0.1, 0.0)[i]))
    # where the small shards come to rest, and where the debris lands (body-space, body at z 0 at the end)
    rest = [((0.62, -0.32, 0.08), 70, 30), ((-0.55, -0.4, 0.07), 80, -50), ((0.1, 0.55, 0.08), 85, 100)]
    deb_rest = [((0.0, -0.3, 0.06), 80, 10), ((0.3, 0.25, 0.05), 85, -60), ((-0.25, 0.2, 0.06), 78, 130)]
    CM = [cm, sm]

    def aim(ob, d):
        ob.rotation_euler = Vector(d).normalized().to_track_quat("Z", "Y").to_euler()

    def smooth(x):
        x = max(0.0, min(1.0, x))
        return x * x * (3 - 2 * x)

    def pose(action, u):
        w = 2 * math.pi * u
        z, y, lean, flash, spread, sep = H + 0.06 * math.sin(w), 0.0, 0.0, 1.0, 1.0, 0.0
        atk = 0.0
        if action == "Walking_A":
            z, lean = H + 0.07 * math.sin(2 * w), 9
        elif action == "Attack":
            a = math.sin(math.pi * u)
            atk, lean, y, z = a, 24 * a, -0.15 * a, H - 0.05 * a
        elif action == "Hit_A":
            a = math.sin(math.pi * u)
            y, lean, flash, spread, z = 0.28 * a, -16 * a, 1 + 12 * a, 1 + 0.6 * a, H + 0.04 * a
        elif action == "Death_A":
            sep = min(1.0, u * 1.3)
            flash = 1 + 10 * math.sin(math.pi * min(1.0, u * 4)) * (1 if u < 0.25 else 0)
        for m_ in CM:
            m_.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = (0.25 if m_ is cm else 0.3) * flash * (1 - 0.75 * smooth(sep * 1.2 - 0.2))
        km.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 4.0 * (1 + flash * 0.3) * (1 - 0.85 * smooth(sep * 1.2 - 0.3))
        g = sep * sep
        body.location = (0, y, H * 0.0 + z - (z * g if action == "Death_A" else 0))
        body.rotation_euler = Euler((math.radians(lean), 0, 0))
        s_ = smooth(sep * 1.4 - 0.1)
        for hj, sg in halves:
            hj.location = (sg * 0.12 * s_ * (1 if sg > 0 else -1) * 0.0 + (0.12 if sg > 0 else -0.12) * s_, 0.04 * sg * s_, 0)
            hj.rotation_euler = Euler((0, 0, 0))
        if action == "Death_A":
            ty = smooth(sep * 1.15 - 0.1)
            pU.location = (0.16 * ty, 0.14 * ty, 0.18 * ty)
            pU.rotation_euler = Euler((0, math.radians(88 * ty), math.radians(22 * ty)))
            pL.location = (-0.16 * ty, -0.14 * ty, 0.18 * ty)
            pL.rotation_euler = Euler((0, math.radians(88 * ty), math.radians(-28 * ty)))
            for dj, (dp, dpitch, dyaw) in zip(debris, deb_rest):
                t_ = smooth(sep * 1.6 - 0.1)
                dj.scale = (t_, t_, t_)
                dj.location = (dp[0] * t_, dp[1] * t_, 0.1 + (dp[2] - 0.1) * t_ + 0.35 * math.sin(math.pi * t_) * 0.6)
                dj.rotation_euler = Euler((math.radians(dpitch * t_), 0, math.radians(dyaw * t_)))
        for i, (sj, ph, rr, hh) in enumerate(shards):
            ang = w * (1.0 if action != "Idle" else 1.0) + ph
            rr_ = rr + 0.1
            orb = Vector((math.cos(ang) * rr_ * spread * 1.0, math.sin(ang) * rr_ * spread, hh + 0.07 * math.sin(2 * w + ph) + 0.08 * (i - 1)))
            outward = Vector((math.cos(ang), math.sin(ang), 0))
            d = outward * 0.55 + Vector((0, 0, 1))
            if action == "Walking_A":
                d = outward * 0.45 + Vector((-math.sin(ang), math.cos(ang), 0)) * 0.5 + Vector((0, 0, 1))
            p = orb
            if atk > 0:
                t_ = smooth(atk * 1.7)
                fwd = Vector(((i - 1) * 0.22, -(0.38 + 0.62 * atk), -0.05 + 0.2 * (i - 1) * (1 if i != 1 else 0) + 0.1))
                p = orb.lerp(fwd, t_)
                d = d.lerp(Vector(((i - 1) * 0.2, -1, 0)), t_)
            if action == "Death_A":
                t_ = smooth(sep * 1.5 - 0.1)
                rp, rpitch, ryaw = rest[i]
                p = orb.lerp(Vector(rp), t_)
                p.z = orb.z * (1 - t_) + rp[2] * t_ - (body.location.z - 0.0) * t_ * 0.0
                if t_ > 0:
                    sj.location = p
                    sj.rotation_euler = Euler((0, math.radians(rpitch * t_), math.radians(ryaw * t_)))
                    continue
            sj.location = p
            aim(sj, d)

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

elif PLAN == "tree":                             # a dead, rooted tree with a face in the trunk and hanged bodies and nooses on its boughs
    ropec, fleshm, clothm = mat("rope", K["rope"]), mat("flesh", K["flesh"]), mat("cloth", K["cloth"])

    def limb(parent, name, m, p0, p1, r0, r1):
        """a tapering rod from p0 (radius r0) to p1 (radius r1) in the parent's frame."""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        ob = part("cone", name, parent, m, tuple((p0 + p1) / 2), (0, 0, 0), (r0, r0, d.length / 2), r2=r1 / r0)
        ob.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        return ob

    mid = joint("mid", body, (0, 0, 1.5))
    top = joint("top", mid, (0, 0, 1.3))
    limb(body, "trunk0", coat, (0, 0, 0), (0, 0, 1.5), R, R * 0.8)
    limb(mid, "trunk1", coat, (0, 0, 0), (0, 0, 1.3), R * 0.8, R * 0.62)
    limb(top, "trunk2", dark, (0, 0, 0), (0, 0.05, 1.1), R * 0.62, R * 0.12)
    for k in range(7):                           # roots splayed over the ground (they stay when the tree falls)
        ang = 2 * math.pi * (k + 0.3) / 7
        limb(root, "root%d" % k, dark, (math.cos(ang) * 0.3, math.sin(ang) * 0.3, 0.55), (math.cos(ang) * 1.5, math.sin(ang) * 1.3, 0.04), 0.2, 0.05)
    fj = joint("face", mid, (0, 0, -0.1))
    fj.scale = (1.35, 1.0, 1.35)        # the face, turned a little towards the camera
    fj.rotation_euler = Euler((0, 0, math.radians(float(E("FACE", "40")))))
    eye = mat("eye", K["eye"], 7.0)
    pit = mat("pit", (0.01, 0.005, 0.005))
    part("cube", "brow", fj, dark, (0, -R * 0.74, 0.46), (-15, 0, 0), (0.36, 0.07, 0.07))
    for sg in (1, -1):
        part("sphere", "socket%d" % sg, fj, pit, (sg * 0.17, -R * 0.74, 0.32), (0, 0, 0), (0.1, 0.07, 0.085))
        part("sphere", "eye%d" % sg, fj, eye, (sg * 0.17, -R * 0.74 - 0.04, 0.32), (0, 0, 0), (0.055, 0.04, 0.05))
    part("cone", "nose", fj, dark, (0, -R * 0.74 - 0.04, 0.12), (100, 0, 0), (0.07, 0.07, 0.16), r2=0.4)
    part("sphere", "mouth", fj, pit, (0, -R * 0.74 - 0.02, -0.14), (0, 0, 0), (0.13, 0.07, 0.24))
    for sg in (1, -1):
        part("cone", "fang%d" % sg, fj, mat("bone", BONE), (sg * 0.07, -R * 0.74 - 0.08, -0.02), (-90, 0, 0), (0.025, 0.025, 0.07), r2=0.3)

    swing = []                                   # (joint, phase, axis weights) of everything that hangs and swings

    def rope(parent, name, at, length, phase, body_on):
        rj = joint(name, parent, at)
        limb(rj, name + "_rope", ropec, (0, 0, 0), (0, 0, -length), 0.028, 0.028)
        bj = joint(name + "_end", rj, (0, 0, -length))
        bj.scale = (1.5, 1.5, 1.5)
        if body_on:                               # a hanged body: head tipped to one side, trunk, two arms, two legs
            part("sphere", name + "_head", bj, fleshm, (0.02, 0, -0.14), (0, 14, 0), (0.1, 0.1, 0.12))
            limb(bj, name + "_torso", clothm, (0, 0, -0.2), (0, 0, -0.76), 0.13, 0.1)
            for sg in (1, -1):
                limb(bj, name + "_arm%d" % sg, fleshm, (sg * 0.14, 0, -0.27), (sg * 0.2, 0, -0.74), 0.04, 0.03)
                limb(bj, name + "_leg%d" % sg, clothm, (sg * 0.06, 0, -0.74), (sg * 0.07, 0, -1.26), 0.06, 0.04)
            part("cone", name + "_noose", bj, ropec, (0.0, 0, -0.18), (0, 0, 0), (0.115, 0.115, 0.02), r2=1.0)
        else:                                     # an empty noose: a ring of knots
            for k in range(8):
                a_ = 2 * math.pi * k / 8
                part("sphere", "%s_knot%d" % (name, k), bj, ropec, (0.14 * math.cos(a_), 0.0, -0.14 + 0.14 * math.sin(a_)), (0, 0, 0), (0.035, 0.035, 0.035))
        swing.append((rj, phase))
        return rj

    def bough(name, p0, p1, p2, r0, hang_at):
        """two limbs from the crown (p0 to p1 to p2) with a twig fork at the end; returns the joints that sway."""
        b1 = joint(name, top, p0)
        limb(b1, name + "_a", dark, (0, 0, 0), tuple(Vector(p1) - Vector(p0)), r0, r0 * 0.6)
        b2 = joint(name + "_2", b1, tuple(Vector(p1) - Vector(p0)))
        e = Vector(p2) - Vector(p1)
        limb(b2, name + "_b", dark, (0, 0, 0), tuple(e), r0 * 0.6, r0 * 0.25)
        for k, (dx, dy, dz) in enumerate(((0.0, 0.5, 0.5), (0.0, 0.3, -0.45))):      # two twigs
            limb(b2, "%s_twig%d" % (name, k), dark, tuple(e * 0.6), tuple(e * 0.6 + Vector((0, math.copysign(1, e.y or 1) * dy * 0.9, dz * 0.9))), r0 * 0.25, 0.015)
        return b1, b2

    bf1, bf1b = bough("bf", (0, -0.1, 0.5), (0, -1.5, 1.2), (0, -2.6, 1.15), 0.2, None)
    bb1, bb1b = bough("bb", (0, 0.1, 0.4), (0, 1.5, 1.0), (0, 2.6, 1.3), 0.2, None)
    bu1, bu1b = bough("bu", (0, 0.0, 0.8), (0.0, -0.4, 1.4), (0.0, -0.2, 2.0), 0.14, None)
    bs1, bs1b = bough("bs", (0, 0.0, 0.9), (0.0, 0.9, 1.7), (0.0, 1.5, 2.3), 0.1, None)
    rope(bf1b, "h1", (0, -0.5, 0.0), 1.0, 0.0, True)
    rope(bf1, "h2", (0, -1.2, 0.0), 0.7, 1.6, False)
    rope(bb1b, "h3", (0, 0.9, 0.0), 1.2, 3.1, True)
    rope(bb1, "h4", (0, 0.7, 0.0), 0.8, 4.4, False)
    
    def pose(action, u):
        w = 2 * math.pi * u
        lean = fall = 0.0
        sway, amp, rp = 2.0, 1.0, 5.0
        bow = 0.0
        if action == "Walking_A":                # rooted: it sways harder in the wind
            sway, amp, rp = 4.0, 2.0, 11.0
        elif action == "Attack":                 # rears back, then lashes forward and the forward bough whips down
            back = max(0.0, 1 - u * 4)
            a = math.sin(math.pi * u) if u > 0.25 else 0.0
            lean, bow, rp = -7 * back + 14 * a, 40 * a, 9.0
        elif action == "Hit_A":
            a = math.sin(math.pi * u)
            lean, rp = -7 * a, 9 + 8 * a
        elif action == "Death_A":                # topples away from the camera and lies flat, the hanged shaken loose
            a = min(1.0, u * 1.25)
            fall = a * a
            lean, rp = 3 * math.sin(math.pi * a), 9 + 8 * a
        mid.rotation_euler = Euler((math.radians(lean * 0.4 + sway * 0.5 * math.sin(w)), 0, 0))
        top.rotation_euler = Euler((math.radians(lean * 0.6 + sway * math.sin(w + 0.8)), math.radians(amp * math.sin(w)), 0))
        bf1.rotation_euler = Euler((math.radians(bow + 4 * amp * math.sin(w + 0.3)), 0, 0))
        bf1b.rotation_euler = Euler((math.radians(bow * 0.6 + 5 * amp * math.sin(w + 1.1)), 0, 0))
        bb1.rotation_euler = Euler((math.radians(-bow * 0.3 + 4 * amp * math.sin(w + 2.0)), 0, 0))
        bb1b.rotation_euler = Euler((math.radians(5 * amp * math.sin(w + 2.5)), 0, 0))
        bu1.rotation_euler = Euler((math.radians(3 * amp * math.sin(w + 1.0)), 0, 0))
        bs1.rotation_euler = Euler((math.radians(3 * amp * math.sin(w + 3.0)), 0, 0))
        for rj, ph in swing:
            rj.rotation_euler = Euler((math.radians(rp * math.sin(w + ph)), math.radians(rp * 0.5 * math.cos(w + ph)), 0))
        keep = max(0.001, 1 - fall * 1.6)
        for rj, ph in swing:                     # the ropes, bodies and nooses vanish into the dust of the fall
            rj.scale = (keep, keep, keep)
        body.rotation_euler = Euler((0, math.radians(-90 * fall), 0))
        body.location = (0, 0, H + 0.5 * fall)

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

elif PLAN == "imp":                              # a small ember imp: coal body, glowing cracks and belly, a flame for a head
    root.rotation_euler = Euler((0, 0, math.radians(float(E("TURN", "35")))))   # three-quarter view: legs and eyes read
    cm_ = mat("coal", K["coat"])
    lm = mat("limb", K["dark"])
    em_ = mat("ember", (1.0, 0.2, 0.02), 1.5)
    fo_ = mat("flame_o", (1.0, 0.25, 0.02), 1.7)
    fi_ = mat("flame_i", (1.0, 0.7, 0.2), 3.0)
    ey_ = mat("eye", (1.0, 0.95, 0.6), 4.0)
    EMS = [(em_, 1.5), (fo_, 1.7), (fi_, 3.0), (ey_, 4.0)]
    torso = joint("torso", body, (0, 0, 0))
    part("sphere", "tbody", torso, cm_, (0, 0, 0), (0, 0, 0), (R * 1.0, R * 0.96, R * 0.96))
    part("sphere", "belly", torso, em_, (0, -R * 0.78, -R * 0.38), (0, 0, 0), (R * 0.55, R * 0.36, R * 0.4))
    for t_, zz in ((-58, 0.3), (58, 0.25), (150, 0.15), (-150, 0.3)):
        a_ = math.radians(t_)
        part("sphere", "crack", torso, em_, (math.sin(a_) * R * 0.93, -math.cos(a_) * R * 0.9, R * zz), (0, 0, t_ * 0.0 + (15 if t_ > 0 else -15)), (R * 0.15, R * 0.15, R * 0.6))
    for sg in (1, -1):
        part("cone", "horn%d" % sg, torso, lm, (sg * R * 0.55, 0, R * 0.88), (0, sg * 28, 0), (R * 0.2, R * 0.2, R * 0.32), r2=0.0)
    eyes = []
    for sg in (1, -1):
        ej = joint("eyej%d" % sg, body, (sg * R * 0.42, -R * 0.84, R * 0.36))
        part("sphere", "eye%d" % sg, ej, ey_, (0, 0, 0), (0, 0, 0), (R * 0.26, R * 0.15, R * 0.2))
        eyes.append(ej)
    fj = joint("flame", body, (0, 0, R * 0.9))
    part("sphere", "fbase", fj, fo_, (0, 0, R * 0.12), (0, 0, 0), (R * 0.4, R * 0.4, R * 0.35))
    tongues = []
    for i, (tx, ty_, th, col_) in enumerate(((0.0, 0.0, 0.15, fo_), (0.4, 0.1, 0.1, fo_), (-0.4, -0.05, 0.11, fo_), (0.0, -0.05, 0.1, fi_))):
        tj = joint("tongue%d" % i, fj, (tx * R * 0.6, ty_ * R, R * 0.12))
        part("cone", "tongue%d" % i, tj, col_, (0, 0, th), (0, 0, 0), (R * (0.4 if i < 3 else 0.26), R * (0.4 if i < 3 else 0.26), th), r2=0.0)
        tongues.append((tj, i))
    limbs = []
    for sg in (1, -1):
        sj = joint("shoulder%d" % sg, body, (sg * R * 0.98, 0, R * 0.12))
        part("cone", "arm%d" % sg, sj, lm, (0, 0, -0.08), (180, 0, 0), (0.065, 0.065, 0.09), r2=0.7)
        part("sphere", "hand%d" % sg, sj, lm, (0, 0, -0.17), (0, 0, 0), (0.06, 0.06, 0.06))
        hj = joint("hip%d" % sg, body, (sg * R * 0.9, 0, -R * 0.7))
        part("cone", "leg%d" % sg, hj, lm, (0, 0, -0.07), (180, 0, 0), (0.06, 0.06, 0.08), r2=0.7)
        part("sphere", "foot%d" % sg, hj, lm, (0, -0.04, -0.14), (0, 0, 0), (0.08, 0.13, 0.055))
        limbs.append((sj, hj, sg))

    def smooth(x):
        x = max(0.0, min(1.0, x))
        return x * x * (3 - 2 * x)

    def pose(action, u):
        w = 2 * math.pi * u
        fl = 8 * w if action in ("Walking_A", "Idle") else 5 * w + 1.7
        z, y, pitch, roll = H + 0.012 * math.sin(w), 0.0, 0.0, 0.0
        sw = 0.0          # leg swing
        arm_f, arm_o = 0.0, 0.0   # arm forward, arm out
        flash, sq, tuck, fscale, eyes_on, ground, dim = 1.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0
        if action == "Walking_A":
            sw = 48 * math.sin(w)
            z, pitch, roll = H - 0.01 + 0.035 * abs(math.sin(w)), 14, 7 * math.sin(w)
            arm_f, arm_o = 0, 75
        elif action == "Idle":
            arm_f, arm_o = 0, 75
        elif action == "Attack":
            a = math.sin(math.pi * u)
            crouch = max(0.0, 1 - u * 4)
            z, y, pitch = H - 0.07 * crouch + 0.16 * a * (1 if u > 0.2 else 0), -0.3 * a * (1 if u > 0.2 else 0), 20 * a - 12 * crouch
            arm_f, arm_o = -95 * a + 40 * crouch, 75 - 55 * a
            sw = 35 * a
            tuck = a
        elif action == "Hit_A":
            a = math.sin(math.pi * u)
            y, pitch, flash, z = 0.16 * a, -20 * a, 1 + 1.2 * a, H + 0.02 * a
            arm_f, arm_o = 30 * a, 75 + 20 * a
            sw = -20 * a
        elif action == "Death_A":
            a = min(1.0, u * 1.35)
            g = smooth(a)
            z = H - (H - R * 0.5) * g * g if a < 1 else R * 0.5
            sq, pitch = 1 - 0.5 * g, 25 * g
            fscale = max(0.0, 1 - a * 1.6)
            eyes_on = max(0.0, 1 - a * 2.5)
            ground, dim = g, 1 - 0.8 * g
        for m_, base in EMS:
            m_.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = base * flash * (dim if m_ is not ey_ else 1)
        body.location = (0, y, z)
        body.rotation_euler = Euler((math.radians(pitch), math.radians(roll), 0))
        torso.scale = (1 + (1 - sq) * 0.6, 1 + (1 - sq) * 0.6, sq)
        for ej in eyes:
            ej.scale = (eyes_on,) * 3
        fj.location = (0, 0, R * 0.9 * (sq * 0.5 + 0.5))
        fj.scale = (fscale, fscale, fscale)
        for tj, i in tongues:
            ph = fl + i * 2.1
            sc2 = 1 + 0.35 * math.sin(ph) + 0.12 * math.sin(2.3 * ph)
            tj.scale = (1 - 0.15 * math.sin(ph), 1 - 0.15 * math.sin(ph), sc2)
            tj.rotation_euler = Euler((math.radians(18 * math.sin(ph + 1.0)), math.radians(18 * math.cos(ph)), 0))
        for sj, hj, sg in limbs:
            if ground:
                gg = ground
                sj.location = (sg * R * (0.98 + 0.25 * gg), 0.0, R * 0.12 * (1 - gg) - 0.1 * gg)
                sj.rotation_euler = Euler((0, math.radians(-sg * 78 * gg), math.radians(sg * 25 * gg)))
                hj.location = (sg * R * (0.45 + 0.35 * gg), 0.0, -R * 0.75 * (1 - gg) - 0.1 * gg)
                hj.rotation_euler = Euler((0, math.radians(-sg * 80 * gg), math.radians(sg * 40 * gg)))
                continue
            sj.location = (sg * R * 0.98, 0, R * 0.12)
            hj.location = (sg * R * 0.9, 0, -R * 0.7)
            side = 1 if sg > 0 else -1
            ph = math.pi if sg > 0 else 0.0
            if action == "Walking_A":
                l_, a_ = sw * sg, -30 * math.sin(w) * sg
            else:
                l_, a_ = sw, arm_f
            hj.rotation_euler = Euler((math.radians(l_ + 25 * tuck), math.radians(-sg * 24), 0))
            sj.rotation_euler = Euler((math.radians(a_), math.radians(-sg * arm_o), 0))

elif PLAN == "chandelier":                       # a fallen iron chandelier that lives: a tilted ring of candles on clawed legs, chains trailing up, a skull hub among pale arms
    iron, brass, wax = mat("iron", K["coat"]), mat("brass", K["brass"]), mat("wax", K["wax"])
    pale, pit = mat("pale", K["pale"]), mat("pit", (0.01, 0.01, 0.015))
    fl_o, fl_i = mat("flame_o", (1.0, 0.35, 0.04), 2.6), mat("flame_i", (1.0, 0.8, 0.3), 4.0)
    eye = mat("eye", K["eye"], 6.0)
    TH = math.radians(K["tilt"])
    ringj = joint("ring", body, (0, 0, 0))
    ringj.rotation_euler = Euler((0, TH, 0))

    def rod(parent, name, m, p0, p1, r0, r1):
        """a tapering rod from p0 (radius r0) to p1 (radius r1) in the parent's frame."""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        ob = part("cone", name, parent, m, tuple((p0 + p1) / 2), (0, 0, 0), (r0, r0, d.length / 2), r2=r1 / r0)
        ob.rotation_euler = d.to_track_quat("Z", "X" if abs(d.normalized().y) > 0.95 else "Y").to_euler()
        return ob

    NR = 22
    for k in range(NR):                          # the outer ring, one iron bar per chord, and a bead at every joint
        a0, a1 = 2 * math.pi * k / NR, 2 * math.pi * (k + 1) / NR
        rod(ringj, "ring%d" % k, iron, (R * math.cos(a0), R * math.sin(a0), 0), (R * math.cos(a1), R * math.sin(a1), 0), 0.12, 0.12)
        part("sphere", "bead%d" % k, ringj, iron, (R * math.cos(a0), R * math.sin(a0), 0), (0, 0, 0), (0.16, 0.16, 0.16))
    for k in range(14):                          # the inner ring
        a0, a1 = 2 * math.pi * k / 14, 2 * math.pi * (k + 1) / 14
        rod(ringj, "in%d" % k, iron, (R * 0.5 * math.cos(a0), R * 0.5 * math.sin(a0), 0.05), (R * 0.5 * math.cos(a1), R * 0.5 * math.sin(a1), 0.05), 0.085, 0.085)
    for k in range(6):                           # spokes from the hub to the rim, rising a little
        a = 2 * math.pi * (k + 0.5) / 6
        rod(ringj, "spoke%d" % k, iron, (0, 0, 0.12), (R * math.cos(a), R * math.sin(a), 0.0), 0.07, 0.06)
    flames = []
    for k in range(10):                          # ten candles in brass cups on the rim, six shorter ones on the inner ring
        a = 2 * math.pi * (k + 0.25) / 10
        for rr, hh, tag in ((R, 0.3, "o"), (R * 0.5, 0.22, "i")):
            if tag == "i" and k % 2:
                continue
            c = (rr * math.cos(a), rr * math.sin(a))
            zz = 0.0 if tag == "o" else 0.05
            part("cone", "cup%s%d" % (tag, k), ringj, brass, (c[0], c[1], zz + 0.07), (0, 0, 0), (0.14, 0.14, 0.08), r2=1.35)
            part("cone", "cdl%s%d" % (tag, k), ringj, wax, (c[0], c[1], zz + 0.14 + hh / 2), (0, 0, 0), (0.075, 0.075, hh / 2), r2=0.9)
            fj = joint("fl%s%d" % (tag, k), ringj, (c[0], c[1], zz + 0.14 + hh))
            part("cone", "flo%s%d" % (tag, k), fj, fl_o, (0, 0, 0.13), (0, 0, 0), (0.07, 0.07, 0.12), r2=0.0)
            part("cone", "fli%s%d" % (tag, k), fj, fl_i, (0, 0, 0.07), (0, 0, 0), (0.04, 0.04, 0.07), r2=0.0)
            flames.append((fj, k * 1.7))
    # the hub: a skull on a brass boss, with pale arms rising round it
    part("cone", "boss", ringj, brass, (0, 0, 0.1), (0, 0, 0), (0.36, 0.36, 0.12), r2=0.7)
    hubj = joint("hub", ringj, (0, 0, 0.55))
    part("sphere", "skull", hubj, pale, (0, 0, 0), (0, 0, 0), (0.3, 0.32, 0.32))
    for sg in (1, -1):
        part("sphere", "sock%d" % sg, hubj, pit, (sg * 0.12, -0.24, 0.04), (0, 0, 0), (0.09, 0.07, 0.1))
        part("sphere", "eye%d" % sg, hubj, eye, (sg * 0.12, -0.28, 0.04), (0, 0, 0), (0.045, 0.03, 0.05))
    part("cone", "nasal", hubj, pit, (0, -0.31, -0.07), (100, 0, 0), (0.04, 0.04, 0.08), r2=0.3)
    jawj = joint("jaw", hubj, (0, -0.05, -0.2))
    part("cube", "jaw", jawj, pale, (0, -0.1, -0.06), (0, 0, 0), (0.17, 0.2, 0.06))
    for k in range(5):
        part("cone", "tooth%d" % k, jawj, mat("tooth", (0.85, 0.82, 0.7)), ((k - 2) * 0.07, -0.28, 0.0), (0, 0, 0), (0.02, 0.02, 0.05), r2=0.2)
    arms = []                                    # (shoulder, elbow, wrist, phase, spread angle)
    NA = 7
    for k in range(NA):
        a = 2 * math.pi * k / NA
        sj = joint("arm%d" % k, hubj, (0.18 * math.cos(a), 0.18 * math.sin(a), -0.12))
        ou = Vector((math.cos(a), math.sin(a), 0))
        up = Vector((0, 0, 1))
        d1 = (ou * 0.7 + up * 0.7).normalized() * 0.62
        rod(sj, "ua%d" % k, pale, (0, 0, 0), tuple(d1), 0.065, 0.05)
        ej = joint("elb%d" % k, sj, tuple(d1))
        d2 = (ou * 0.35 + up * 0.95).normalized() * 0.6
        rod(ej, "fa%d" % k, pale, (0, 0, 0), tuple(d2), 0.05, 0.035)
        wj = joint("wr%d" % k, ej, tuple(d2))
        part("sphere", "palm%d" % k, wj, pale, (0, 0, 0.05), (0, 0, 0), (0.07, 0.04, 0.08))
        for f in range(4):                       # four crooked fingers
            fa = (f - 1.5) * 0.5
            fd = Vector((math.sin(fa) * 0.6, 0.0, 1.0)).normalized() * 0.2
            rod(wj, "fg%d_%d" % (k, f), pale, (math.sin(fa) * 0.05, 0, 0.08), tuple(Vector((math.sin(fa) * 0.05, 0, 0.08)) + fd), 0.016, 0.008)
            rod(wj, "fh%d_%d" % (k, f), pale, tuple(Vector((math.sin(fa) * 0.05, 0, 0.08)) + fd), tuple(Vector((math.sin(fa) * 0.05, 0, 0.08)) + fd + Vector((0, -0.09 * (1 if k % 2 else -1), 0.08))), 0.01, 0.005)
        arms.append((sj, ej, wj, a))
    # four iron claw legs under the rim: hip on the rim, knee outv and up, a hooked foot on the ground
    legs = []
    cw = Vector((0, 0, H))
    Rinv = Euler((0, TH, 0)).to_matrix().inverted()
    for k, a in enumerate((0.35, 1.9, 3.5, 5.0)):
        rim = Vector((R * math.cos(a), R * math.sin(a), 0))
        pw = cw + Euler((0, TH, 0)).to_matrix() @ rim
        outv = Vector((pw.x, pw.y, 0)).normalized() if Vector((pw.x, pw.y, 0)).length > 0.05 else Vector((1, 0, 0))
        foot_w = Vector((pw.x, pw.y, 0.0)) + outv * 0.45
        knee_w = (pw + foot_w) / 2 + outv * 0.3 + Vector((0, 0, 0.1))
        hip = rim
        knee = Rinv @ (knee_w - cw)
        foot = Rinv @ (foot_w - cw)
        hj = joint("hip%d" % k, ringj, tuple(hip))
        rod(hj, "th%d" % k, iron, (0, 0, 0), tuple(knee - hip), 0.075, 0.06)
        kj = joint("knee%d" % k, hj, tuple(knee - hip))
        rod(kj, "sh%d" % k, iron, (0, 0, 0), tuple(foot - knee), 0.06, 0.04)
        part("sphere", "kn%d" % k, kj, iron, (0, 0, 0), (0, 0, 0), (0.1, 0.1, 0.1))
        fj_ = joint("ft%d" % k, kj, tuple(foot - knee))
        for t in range(3):                       # three hooked talons
            ta = (t - 1) * 0.7 + math.atan2(outv.y, outv.x)
            td = Vector((math.cos(ta), math.sin(ta), 0))
            rod(fj_, "tl%d_%d" % (k, t), iron, (0, 0, 0.02), tuple(td * 0.2 + Vector((0, 0, 0.02))), 0.04, 0.012)
        legs.append((hj, kj))
    # three chains rising from the rim, going up outv of the picture's middle and ending in a broken link
    chains = []
    for k, a in enumerate((2.3, 3.14, 4.0)):
        rim = Vector((R * math.cos(a), R * math.sin(a), 0.1))
        cj = joint("ch%d" % k, ringj, tuple(rim))
        lean = Vector((math.cos(a) * -0.2, math.sin(a) * -0.2, 0))
        segs = []
        par = cj
        for s in range(3):
            if s:
                par = joint("ch%d_%d" % (k, s), par, (0, 0, 0.75))
            for li in range(5):
                lk = part("cube", "lk%d_%d_%d" % (k, s, li), par, iron, (0, 0, 0.075 + li * 0.15), (0, 90 * (li % 2), 0), (0.11, 0.07, 0.14))
            segs.append(par)
        part("cone", "brk%d" % k, segs[-1], iron, (0, 0, 0.88), (0, 0, 0), (0.11, 0.07, 0.16), r2=0.3)
        chains.append((cj, segs, a))

    def pose(action, u):
        w = 2 * math.pi * u
        tilt, z, dy, arm_up, arm_out, flame, jaw_o, heave = K["tilt"], H, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0
        fall = 0.0
        if action == "Idle":
            z, jaw_o = H + 0.04 * math.sin(w), 6 + 5 * math.sin(w)
        elif action == "Walking_A":              # rooted: it heaves and the arms writhe harder
            z, jaw_o, tilt, arm_up = H + 0.09 * math.sin(w), 14 + 10 * math.sin(w), tilt + 4 * math.sin(w), 10
        elif action == "Attack":                 # rears the ring back, arms flung wide, then slams it forward and down
            back = max(0.0, 1 - u * 3.5)
            a = math.sin(math.pi * u) if u > 0.28 else 0.0
            tilt, z, arm_out, jaw_o, dy = tilt + 16 * back - 26 * a, H + 0.35 * back - 0.1 * a, 35 * a - 15 * back, 34 * a, -0.25 * a
            flame = 1 + 0.5 * a
        elif action == "Hit_A":
            a = math.sin(math.pi * u)
            tilt, z, jaw_o, flame, arm_out = tilt + 14 * a, H + 0.1 * a, 30 * a, 1 - 0.4 * a, -20 * a
        elif action == "Death_A":                # the flames gutter outv, the arms go limp, the claws fold and the ring settles on the ground
            fall = min(1.0, u * 1.2)
            flame = max(0.0, 1 - fall * 1.8)
            tilt = K["tilt"] * (1 - fall) + 3 * fall
            z, arm_out, jaw_o = H - (H - 0.12) * fall * fall, 88 * fall, 40 * fall
        body.location = (0, dy, z)
        ringj.rotation_euler = Euler((0, math.radians(tilt), 0))
        for fj, ph in flames:
            f_ = max(0.001, flame * (1 + 0.16 * math.sin(3 * w + ph)))
            fj.scale = (f_, f_, f_ * (1 + 0.2 * math.sin(2 * w + ph)) if flame > 0.01 else 0.001)
        hubj.rotation_euler = Euler((math.radians(4 * math.sin(w)), 0, math.radians(8 * math.sin(w + 1))))
        jawj.rotation_euler = Euler((math.radians(jaw_o), 0, 0))
        for sj, ej, wj, a in arms:
            ph = w + 2 * a
            ox, oy = math.cos(a), math.sin(a)
            amp = 16 + arm_up
            sw = math.sin(ph)
            # bend about the axis tangent to the circle: tipping outwards = +arm_out
            sj.rotation_euler = Euler((math.radians((arm_out + amp * sw) * -oy * -1), math.radians((arm_out + amp * sw) * ox), 0))
            ej.rotation_euler = Euler((math.radians((arm_out * 0.5 + amp * 0.8 * math.sin(ph + 1.0)) * -oy * -1), math.radians((arm_out * 0.5 + amp * 0.8 * math.sin(ph + 1.0)) * ox), 0))
            wj.rotation_euler = Euler((math.radians(25 * math.sin(ph + 2.0)), math.radians(25 * math.cos(ph + 2.0)), 0))
        for k, (hj, kj) in enumerate(legs):
            ph = w + k * 1.6 if action in ("Idle", "Walking_A") else 0.0
            amp = 5 if action == "Idle" else (11 if action == "Walking_A" else 0)
            hj.rotation_euler = Euler((math.radians(amp * math.sin(ph)), math.radians(amp * math.cos(ph)), 0))
            kj.rotation_euler = Euler((math.radians(fall * 35), math.radians(fall * 20), 0))
        for cj, segs, a in chains:
            if action == "Death_A":
                cj.rotation_euler = Quaternion((-math.sin(a), math.cos(a), 0), math.radians(78 * fall)).to_euler()
            else:
                cj.rotation_euler = Euler((math.radians(4 * math.sin(w + a)), math.radians(4 * math.cos(w + a * 1.3)), 0))
            for i, sg_ in enumerate(segs[1:]):
                if action == "Death_A":
                    sg_.rotation_euler = Euler((math.radians(-fall * 30 * math.cos(a)), math.radians(fall * 30 * math.sin(a)), 0)) if False else Quaternion((-math.sin(a), math.cos(a), 0), math.radians(18 * fall)).to_euler()
                else:
                    sg_.rotation_euler = Euler((math.radians(7 * math.sin(w + a + i + 1)), math.radians(7 * math.cos(w + a + i)), 0))


elif PLAN == "ghost":                            # a tall pale-blue spectre scribe hunched over a floating book, quill in a long hand, pages circling; no legs, the robe fades to mist
    robe, shade, glowc = mat("robe", K["coat"], K["glow"]), mat("shade", K["dark"], K["glow"]), mat("glow", K["pale"], 0.8)
    hand_m = mat("hand", K["pale"], 0.3)
    eye = mat("eye", K["eye"], 6.0)
    pit = mat("pit", (0.02, 0.04, 0.1), 0.3)
    ink = mat("ink", (0.05, 0.08, 0.2), 0.0)
    pg_m = mat("page", (0.9, 0.93, 0.8), 0.9)
    brass = mat("brass", (0.6, 0.45, 0.15), 0.0)

    def rod(parent, name, m, p0, p1, r0, r1):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        ob = part("cone", name, parent, m, tuple((p0 + p1) / 2), (0, 0, 0), (r0, r0, d.length / 2), r2=r1 / r0)
        ob.rotation_euler = d.to_track_quat("Z", "X" if abs(d.normalized().y) > 0.95 else "Y").to_euler()
        return ob

    # the mist: tatters of robe hanging from the waist, shortest to longest, tapering to a point
    root.scale = (1.2, 1.2, 1.2)
    waist = joint("waist", body, (0, 0, 0))
    mist = []
    for k in range(9):
        a = 2 * math.pi * k / 9
        r_ = 0.34 + 0.06 * (k % 2)
        L_ = 1.05 + 0.4 * ((k * 5) % 3) / 2
        mj = joint("mist%d" % k, waist, (r_ * math.cos(a), r_ * math.sin(a), 0.1))
        part("cone", "mt%d" % k, mj, robe if k % 2 else shade, (0, 0, -L_ / 2), (180, 0, 0), (0.24, 0.17, L_ / 2), r2=0.15)
        mist.append((mj, a))
    part("cone", "skirt", waist, robe, (0, 0, -0.35), (180, 0, 0), (0.6, 0.5, 0.55), r2=0.55)   # the solid part, tapering into the tatters
    torso = joint("torso", waist, (0, 0, 0.1))              # hunched: the whole upper body leans over the book
    part("cone", "chest", torso, robe, (0, 0, 0.55), (0, 0, 0), (0.5, 0.42, 0.62), r2=0.5)
    part("sphere", "shoulders", torso, robe, (0, 0, 1.08), (0, 0, 0), (0.5, 0.3, 0.2))
    part("sphere", "hump", torso, shade, (0, 0.22, 0.95), (0, 0, 0), (0.26, 0.22, 0.22))
    neck = joint("neck", torso, (0, -0.06, 1.12))
    part("cone", "neck", neck, shade, (0, 0, 0.08), (0, 0, 0), (0.12, 0.12, 0.15), r2=0.8)
    head = joint("head", neck, (0, 0, 0.18))
    part("sphere", "skull", head, hand_m, (0, -0.04, 0.08), (0, 0, 0), (0.17, 0.2, 0.2))
    part("sphere", "face", head, pit, (0, -0.15, 0.06), (0, 0, 0), (0.12, 0.08, 0.14))
    for sg in (1, -1):
        part("sphere", "eye%d" % sg, head, eye, (sg * 0.06, -0.21, 0.09), (0, 0, 0), (0.03, 0.02, 0.04))
    part("cone", "hood", head, shade, (0, 0.04, 0.3), (-20, 0, 0), (0.3, 0.32, 0.36), r2=0.0)          # a tall hood with a point
    part("cone", "hood_tip", head, shade, (0, 0.2, 0.5), (-60, 0, 0), (0.07, 0.07, 0.2), r2=0.0)
    part("cone", "chin", head, robe, (0, -0.1, -0.1), (180, 0, 0), (0.1, 0.1, 0.12), r2=0.0)           # a wispy beard of mist
    arms = {}
    for sg, nm in ((-1, "r"), (1, "l")):                     # the right (sg -1) holds the quill; the left bears the book up
        sh = joint("sh_" + nm, torso, (sg * 0.46, -0.05, 0.98))
        rod(sh, "ua_" + nm, robe, (0, 0, 0), (sg * 0.1, -0.2, -0.55), 0.17, 0.13)
        el_ = joint("el_" + nm, sh, (sg * 0.1, -0.2, -0.55))
        rod(el_, "fa_" + nm, robe, (0, 0, 0), (sg * 0.02, -0.42, -0.3), 0.13, 0.07)
        part("cone", "slv_" + nm, el_, shade, (sg * 0.02, -0.2, -0.45), (180, 0, 0), (0.16, 0.12, 0.35), r2=0.1)
        hd = joint("hd_" + nm, el_, (sg * 0.02, -0.42, -0.3))
        part("sphere", "palm_" + nm, hd, hand_m, (0, -0.04, 0), (0, 0, 0), (0.07, 0.1, 0.05))
        for f in range(4):                                    # the long, bony fingers
            fx = (f - 1.5) * 0.05
            rod(hd, "fg%s%d" % (nm, f), hand_m, (fx, -0.1, 0), (fx * 1.3, -0.4 + (0.03 if f in (0, 3) else 0), -0.03), 0.018, 0.008)
        arms[nm] = (sh, el_, hd)
    # the quill: a long feather held in the right hand, nib down at the page
    qj = joint("quill", arms["r"][2], (0, -0.2, 0.0))
    rod(qj, "shaft", glowc, (0, 0, -0.1), (0, -0.2, 0.55), 0.016, 0.012)
    part("cone", "vane", qj, glowc, (0, -0.1, 0.5), (-18, 0, 0), (0.02, 0.07, 0.38), r2=0.5)
    part("cone", "nib", qj, ink, (0, 0.01, -0.12), (190, 0, 0), (0.012, 0.012, 0.06), r2=0.0)
    # the book, floating open in front of the chest on a glow; a lit page
    bk = joint("book", body, (0, -0.8, 0.75))
    part("cube", "cover", bk, brass, (0, 0, -0.04), (0, 0, 0), (0.53, 0.37, 0.03))
    for sg in (1, -1):
        part("cube", "leaf%d" % sg, bk, pg_m, (sg * 0.25, 0, 0.0), (0, -sg * 14, 0), (0.25, 0.33, 0.02))
    part("cube", "spine", bk, ink, (0, 0, 0.0), (0, 0, 0), (0.025, 0.33, 0.04))
    for k in range(4):                                       # lines of script
        part("cube", "ln%d" % k, bk, ink, (-0.24, 0.0, 0.04), (0, 12, 0), (0.15, 0.012, 0.004)).location.y = 0.17 - k * 0.09
    # loose pages circling the body
    pages = []
    for k in range(8):
        pj = joint("pgj%d" % k, body, (0, 0, 0.6 + 0.35 * (k % 4)))
        part("cube", "pg%d" % k, pj, pg_m, (1.15 + 0.12 * (k % 3), 0, 0), (0, 0, 0), (0.18, 0.012, 0.13))
        for ln in range(2):
            part("cube", "pl%d_%d" % (k, ln), pj, ink, (1.15 + 0.12 * (k % 3), -0.014, 0.03 - ln * 0.06), (0, 0, 0), (0.12, 0.003, 0.008))
        pages.append((pj, 2 * math.pi * k / 8))

    def pose(action, u):
        w = 2 * math.pi * u
        z, lean, sway, orbit, rad, flare, dy, fall = H + 0.07 * math.sin(w), 12.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0
        write = 1.0
        if action == "Walking_A":                # rooted: it drifts in a wider sway
            z, lean, sway, orbit = H + 0.14 * math.sin(w), 16.0, 7.0, 2.0
        elif action == "Attack":                 # rears back, then snaps the quill forward in a stab of ink and the pages burst outward
            back = max(0.0, 1 - u * 3.5)
            a = math.sin(math.pi * u) if u > 0.28 else 0.0
            lean, dy, rad, flare, write = 12 - 10 * back + 30 * a, 0.3 * back - 0.4 * a, 1 + 0.45 * a, 1 + 1.2 * a, 4 * a
        elif action == "Hit_A":
            a = math.sin(math.pi * u)
            lean, dy, rad = 12 - 22 * a, 0.45 * a, 1 - 0.2 * a
        elif action == "Death_A":                # unwritten: it sinks into a flat pool of mist, the book shut on the ground, the pages fallen
            fall = min(1.0, u * 1.2)
            z, lean, rad = H - (H - 0.55) * fall * fall, 12 + 40 * fall, 1 + 0.2 * fall
        body.location = (0, dy, z)
        waist.scale = (1 + 0.3 * fall, 1 + 0.3 * fall, max(0.15, 1 - 0.85 * fall))
        waist.rotation_euler = Euler((math.radians(sway * math.sin(w)), math.radians(sway * 0.5 * math.cos(w)), 0))
        torso.rotation_euler = Euler((math.radians(lean + 4 * math.sin(w + 1.0)), 0, 0))
        neck.rotation_euler = Euler((math.radians(-lean * 0.7), 0, 0))
        head.rotation_euler = Euler((math.radians(-10 + 4 * math.sin(w + 2.0)), math.radians(6 * math.sin(w + 0.5)), math.radians(55)))
        # the quill hand writes small loops over the page, or stabs
        sh, el_, hd = arms["r"]
        sh.rotation_euler = Euler((math.radians(-30 - 55 * (flare - 1) - 6 * math.sin(w * 2)) + math.radians(lean * 0.8), math.radians(10 * math.sin(w * 2 + 0.7)), 0))
        el_.rotation_euler = Euler((math.radians(-35 + 12 * math.sin(w * 2 + 1.5)), 0, math.radians(-10)))
        hd.rotation_euler = Euler((math.radians(25 + 12 * math.sin(w * 2) + 30 * (flare - 1)), math.radians(12 * math.cos(w * 2)), 0))
        sh, el_, hd = arms["l"]
        sh.rotation_euler = Euler((math.radians(-25 + lean * 0.5 + 5 * math.sin(w + 0.4) + 30 * (flare - 1)), 0, 0))
        el_.rotation_euler = Euler((math.radians(-30), 0, math.radians(8)))
        hd.rotation_euler = Euler((math.radians(10), 0, 0))
        bk.location = (0, (-0.8 - 0.1 * (flare - 1)) * (1 - fall), 0.75 * (1 - fall) + (0.05 - z) * fall + (0.06 * math.sin(w + 0.9)) * (1 - fall))
        bk.rotation_euler = Euler((math.radians(-50 * (1 - fall) + 6 * math.sin(w)), 0, math.radians(35 + 8 * math.sin(w))))
        bk.scale = (1 + 0.1 * (flare - 1),) * 3
        for k, (pj, ph) in enumerate(pages):
            hk = 0.6 + 0.35 * (k % 4)
            pj.location = (0, 0, hk * (1 - fall) + (0.03 - z) * fall)
            pj.rotation_euler = Euler((math.radians(18 * math.sin(w + ph * 2) * (1 - fall) + 88 * fall), 0, ph + w * orbit * (1 - fall) + 0.8 * fall))
            pj.scale = (rad, rad, 1.0)
        for mj, a in mist:
            if action == "Death_A":
                mj.rotation_euler = Euler((math.radians(-60 * fall * math.cos(a)), math.radians(60 * fall * math.sin(a)), 0))
                mj.scale = (1, 1, max(0.08, 1 - fall * 0.95))
            else:
                mj.rotation_euler = Euler((math.radians(9 * math.sin(w + a * 2)), math.radians(9 * math.cos(w + a * 3)), 0))

elif PLAN == "rider":                            # Death: a skeletal rider in a pale shroud on a pale gaunt horse, a tattered banner on a long spear; one sprite
    hm, dk = mat("hide", K["coat"]), mat("shade", K["dark"])
    bone_m, shroud, shroud2 = mat("bone", K["bone"]), mat("shroud", K["shroud"]), mat("shroud2", K["shroud2"])
    pit = mat("pit", (0.01, 0.015, 0.025))
    eye = mat("eye", K["eye"], 6.0)
    steel = mat("steel", (0.55, 0.6, 0.66))
    gold = mat("sigil", (0.45, 0.4, 0.2))

    def rod(parent, name, m, p0, p1, r0, r1):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        ob = part("cone", name, parent, m, tuple((p0 + p1) / 2), (0, 0, 0), (r0, r0, d.length / 2), r2=r1 / r0)
        ob.rotation_euler = d.to_track_quat("Z", "X" if abs(d.normalized().y) > 0.95 else "Y").to_euler()
        return ob

    root.scale = (1.2, 1.2, 1.2)
    PY = 0.62                                    # the hind hooves: the horse pitches about this line when it rears
    hj = joint("horse", body, (0, PY, 0))
    hb = joint("hb", hj, (0, -PY, 0))            # everything of the horse is built in a frame with its hooves at y 0.62
    # barrel, chest, rump: a gaunt horse, ribs showing
    part("sphere", "barrel", hb, hm, (0, 0.05, 1.3), (0, 0, 0), (0.36, 0.82, 0.4))
    part("sphere", "chest", hb, hm, (0, -0.55, 1.4), (0, 0, 0), (0.3, 0.4, 0.42))
    part("sphere", "rump", hb, hm, (0, 0.72, 1.35), (0, 0, 0), (0.32, 0.38, 0.38))
    for sg in (1, -1):
        for k in range(6):                       # ribs: pale arcs over the flank
            y_ = -0.4 + k * 0.17
            part("cone", "rib%d_%d" % (sg, k), hb, bone_m, (sg * 0.3, y_, 1.28), (0, sg * 12, 0), (0.014, 0.014, 0.2), r2=0.6)
        part("sphere", "hip%d" % sg, hb, bone_m, (sg * 0.27, 0.78, 1.62), (0, 0, 0), (0.07, 0.09, 0.07))
    for k in range(7):                           # spine knobs
        part("sphere", "vert%d" % k, hb, bone_m, (0, -0.5 + k * 0.2, 1.7 + (0.04 if k in (0, 1) else 0)), (0, 0, 0), (0.05, 0.06, 0.05))
    neckj = joint("neck", hb, (0, -0.72, 1.6))
    rod(neckj, "neckm", hm, (0, 0, -0.12), (0, -0.4, 0.5), 0.2, 0.14)
    headj = joint("head", neckj, (0, -0.4, 0.5))
    rod(headj, "skull", bone_m, (0, 0.05, 0.08), (0, -0.55, -0.32), 0.16, 0.09)     # a long bare skull, nose down
    part("sphere", "muzzle", headj, bone_m, (0, -0.58, -0.35), (0, 0, 0), (0.09, 0.1, 0.09))
    for sg in (1, -1):
        part("sphere", "esock%d" % sg, headj, pit, (sg * 0.12, -0.06, 0.1), (0, 0, 0), (0.06, 0.07, 0.07))
        part("sphere", "eeye%d" % sg, headj, eye, (sg * 0.135, -0.09, 0.1), (0, 0, 0), (0.03, 0.03, 0.035))
        part("cone", "ear%d" % sg, headj, bone_m, (sg * 0.1, 0.1, 0.3), (-15, sg * 12, 0), (0.04, 0.03, 0.14), r2=0.1)
    jawj = joint("hjaw", headj, (0, -0.1, -0.05))
    rod(jawj, "hjaw", bone_m, (0, 0, 0), (0, -0.45, -0.28), 0.07, 0.05)
    manes = []
    for k in range(6):                           # a ragged mane
        mj = joint("mane%d" % k, neckj, (0, -0.04 - 0.07 * k, 0.1 + 0.08 * k))
        rod(mj, "mn%d" % k, dk, (0, 0, 0), (0, 0.22, -0.3), 0.07, 0.01)
        manes.append(mj)
    tail = joint("tail", hb, (0, 1.0, 1.55))
    tails = []
    for k in range(3):
        tj = joint("tl%d" % k, tail, ((k - 1) * 0.05, 0, 0))
        rod(tj, "tls%d" % k, dk, (0, 0, 0), (0, 0.2, -0.95), 0.06, 0.01)
        tails.append(tj)
    legs = {}
    for fb, y_ in (("f", -0.55), ("b", 0.75)):   # four spindly legs: a thigh, a long shin ending in a hoof
        for sg, sn in ((1, "l"), (-1, "r")):
            top = joint("hip_%s%s" % (fb, sn), hb, (sg * 0.2, y_, 1.2))
            fx = 0.0 if fb == "f" else 0.12
            rod(top, "up_%s%s" % (fb, sn), hm, (0, 0, 0), (0, fx, -0.62), 0.12 if fb == "b" else 0.1, 0.07)
            kn = joint("kn_%s%s" % (fb, sn), top, (0, fx, -0.62))
            part("sphere", "kjt_%s%s" % (fb, sn), kn, bone_m, (0, 0, 0), (0, 0, 0), (0.07, 0.07, 0.07))
            rod(kn, "lo_%s%s" % (fb, sn), bone_m, (0, 0, 0), (0, -fx * 0.5, -0.58), 0.055, 0.05)
            part("cone", "hoof_%s%s" % (fb, sn), kn, dk, (0, -fx * 0.5 - 0.02, -0.6), (180, 0, 0), (0.075, 0.09, 0.05), r2=0.7)
            legs[fb + sn] = (top, kn)
    # a tattered caparison hanging from the barrel
    flaps = []
    for k in range(5):
        fj = joint("flap%d" % k, hb, (0, -0.35 + k * 0.28, 1.55))
        for sg in (1, -1):
            part("cone", "fp%d_%d" % (k, sg), fj, shroud2, (sg * 0.45, 0, -0.35), (0, sg * 8, 0), (0.04, 0.1, 0.38), r2=0.9)
        flaps.append(fj)
    # the rider: pelvis on the saddle, a bony torso, shroud over the shoulders, a hood with a skull
    rj = joint("rider", hb, (0, 0.2, 1.65))
    rj.scale = (1.3, 1.3, 1.3)
    spine = joint("spine", rj, (0, 0, 0.05))
    part("cone", "ribs", spine, bone_m, (0, 0, 0.42), (0, 0, 0), (0.2, 0.14, 0.4), r2=1.1)
    part("cone", "pelvis", rj, bone_m, (0, 0, 0.0), (0, 0, 0), (0.2, 0.12, 0.08), r2=0.5)
    for k in range(4):
        part("cone", "rb%d" % k, spine, shroud2, (0, -0.12, 0.2 + k * 0.17), (90, 0, 0), (0.03, 0.03, 0.12), r2=0.5)
    nk = joint("rneck", spine, (0, -0.02, 0.9))
    hd = joint("rhead", nk, (0, 0, 0.12))
    part("sphere", "rskull", hd, bone_m, (0, -0.02, 0.1), (0, 0, 0), (0.13, 0.15, 0.16))
    part("sphere", "rface", hd, pit, (0, -0.12, 0.09), (0, 0, 0), (0.09, 0.06, 0.1))
    for sg in (1, -1):
        part("sphere", "reye%d" % sg, hd, eye, (sg * 0.05, -0.17, 0.12), (0, 0, 0), (0.025, 0.02, 0.03))
    part("cone", "hood", hd, shroud, (0, 0.05, 0.18), (-15, 0, 0), (0.2, 0.22, 0.24), r2=0.1)
    part("cone", "crown", hd, bone_m, (0, -0.06, 0.34), (0, 0, 0), (0.1, 0.1, 0.07), r2=0.3)
    part("cone", "mantle", spine, shroud, (0, 0.05, 0.72), (0, 0, 0), (0.42, 0.3, 0.22), r2=0.5)    # the shroud over the shoulders
    cloak = joint("cloak", spine, (0, 0.12, 0.85))
    cl = []
    for k in range(5):                           # the shroud streams behind and over the horse's rump in long tatters
        cj = joint("cl%d" % k, cloak, ((k - 2) * 0.17, 0, 0))
        rod(cj, "clr%d" % k, shroud, (0, 0, 0), (0, 0.45 + 0.1 * (k % 2), -1.0 - 0.25 * ((k + 1) % 3)), 0.14, 0.02)
        cl.append(cj)
    arms = {}
    for sg, nm in ((1, "l"), (-1, "r")):
        sh = joint("sh_" + nm, spine, (sg * 0.27, 0, 0.78))
        rod(sh, "ua_" + nm, bone_m, (0, 0, 0), (sg * 0.06, -0.05, -0.38), 0.06, 0.045)
        el_ = joint("el_" + nm, sh, (sg * 0.06, -0.05, -0.38))
        rod(el_, "fa_" + nm, bone_m, (0, 0, 0), (0, -0.34, -0.12), 0.045, 0.035)
        part("cone", "slv_" + nm, el_, shroud, (sg * 0.02, -0.12, -0.12), (180, 0, 0), (0.12, 0.1, 0.25), r2=0.2)
        wr = joint("wr_" + nm, el_, (0, -0.34, -0.12))
        part("sphere", "pm_" + nm, wr, bone_m, (0, -0.03, 0), (0, 0, 0), (0.05, 0.06, 0.04))
        for f in range(3):
            rod(wr, "fg%s%d" % (nm, f), bone_m, ((f - 1) * 0.03, -0.06, 0.0), ((f - 1) * 0.03, -0.14, -0.04), 0.012, 0.008)
        arms[nm] = (sh, el_, wr)
    for sg, sn in ((1, "l"), (-1, "r")):          # rider's legs: thigh over the saddle, shin hanging down by the ribs
        hp = joint("rhip_" + sn, rj, (sg * 0.14, 0, 0))
        rod(hp, "rth_" + sn, bone_m, (0, 0, 0), (sg * 0.2, -0.15, -0.3), 0.07, 0.055)
        rk = joint("rkn_" + sn, hp, (sg * 0.2, -0.15, -0.3))
        rod(rk, "rsh_" + sn, bone_m, (0, 0, 0), (sg * 0.06, 0.05, -0.52), 0.05, 0.035)
        part("cone", "rft_" + sn, rk, bone_m, (sg * 0.06, -0.03, -0.55), (90, 0, 0), (0.04, 0.04, 0.09), r2=0.5)
    # the banner: a long spear held in the right hand with a ragged pale banner and a skull-and-gold crest
    SPJ = joint("spear", arms["r"][2], (0, 0, 0))
    rod(SPJ, "pole", mat("pole", (0.25, 0.2, 0.15)), (0, 0, -0.9), (0, 0, 1.0), 0.03, 0.025)
    rod(SPJ, "blade", steel, (0, 0, 0.98), (0, 0, 1.4), 0.06, 0.0)
    part("cube", "bar", SPJ, gold, (0, 0, 0.85), (0, 0, 0), (0.28, 0.03, 0.03))
    flag = joint("flag", SPJ, (0, 0, 0.8))
    part("cube", "ban", flag, shroud2, (0, 0.0, -0.45), (0, 0, 0), (0.28, 0.012, 0.45))
    part("cube", "ban_s", flag, shroud, (0, 0.012, -0.35), (0, 0, 0), (0.12, 0.004, 0.12))
    for k in range(4):                           # the banner's ragged hem
        part("cone", "tat%d" % k, flag, shroud2, (-0.21 + k * 0.14, 0.0, -1.0 - 0.06 * (k % 2)), (180, 0, 0), (0.07, 0.01, 0.15), r2=0.0)

    def pose(action, u):
        w = 2 * math.pi * u
        pitch = rear = lunge = fall = 0.0
        bob, hit_ = 0.0, 0.0
        gait = 0.0
        spear_a, spear_roll = -62.0, 0.0
        atk = 0.0
        if action == "Idle":
            bob = 0.02 * math.sin(w)
        elif action == "Walking_A":              # rooted: the horse treads in place, head tossing, shroud streaming
            gait, bob = 1.0, 0.03 * math.sin(2 * w)
        elif action == "Attack":                 # rears, then the lance comes down and forward
            back = max(0.0, 1 - u * 3.0)
            a = math.sin(math.pi * u) if u > 0.33 else 0.0
            pitch = 28 * min(1.0, u * 3.0) * (1 - max(0.0, (u - 0.6) / 0.4)) if u < 1 else 0.0
            atk = a
        elif action == "Hit_A":
            a = math.sin(math.pi * u)
            hit_ = a
            pitch = -6 * a
        elif action == "Death_A":                # the horse topples onto its side, rider and banner with it, and lies flat
            fall = min(1.0, u * 1.15)
            fall = fall * fall * (3 - 2 * fall)
        hj.rotation_euler = Euler((math.radians(-pitch), math.radians(90 * fall), 0))
        hj.location = (0, PY, bob + (0.16 * fall))
        body.location = (0, 0, H)
        for k_, (top, kn) in legs.items():
            fb, sn = k_[0], k_[1]
            sw = 0.0
            if gait:
                ph = w + (0 if (fb == "f") == (sn == "l") else math.pi)
                sw = 18 * math.sin(ph)
                lift = max(0.0, math.sin(ph + math.pi / 2))
                kb = 38 * lift
            else:
                kb = 0.0
            tuck = 0.0
            if fb == "f":
                tuck = max(0.0, pitch) * 2.4
            counter = pitch if fb == "b" else 0.0
            top.rotation_euler = Euler((math.radians(sw + counter + (tuck * 0.9)), 0, math.radians((8 if sn == "l" else -8) * fall)))
            kn.rotation_euler = Euler((math.radians(-kb - tuck * (1.4 if fb == "f" else 0) + (22 * fall if fb == "f" else -18 * fall)), 0, 0))
        neckj.rotation_euler = Euler((math.radians(-pitch * 0.4 - 8 * hit_ + 4 * math.sin(w + 0.5) + (10 * math.sin(2 * w) if gait else 0)), 0, 0))
        headj.rotation_euler = Euler((math.radians(10 * hit_ + 5 * math.sin(w + 1.0) + 6 * atk), 0, 0))
        jawj.rotation_euler = Euler((math.radians(10 + 8 * math.sin(w) + 30 * atk + 20 * hit_ + 20 * fall), 0, 0))
        for k, mj in enumerate(manes):
            mj.rotation_euler = Euler((math.radians(10 * math.sin(w + k * 0.7) + 14 * pitch / 28), 0, 0))
        for k, tj in enumerate(tails):
            tj.rotation_euler = Euler((math.radians(10 * math.sin(w + k) + 15 * pitch / 28), math.radians(8 * math.cos(w + k)), 0))
        for k, fj in enumerate(flaps):
            fj.rotation_euler = Euler((0, math.radians(0), 0))
            fj.scale = (1, 1, 1 + 0.06 * math.sin(w + k))
        for k, cj in enumerate(cl):
            cj.rotation_euler = Euler((math.radians(9 * math.sin(w + k * 0.8) + 10 * pitch / 28 - 10 * atk), math.radians(4 * math.cos(w + k)), 0))
        spine.rotation_euler = Euler((math.radians(-4 * pitch / 28 + 5 * atk - 6 * hit_ + 20 * fall + 1.5 * math.sin(w)), 0, math.radians(-30 * fall)))
        hd.rotation_euler = Euler((math.radians(6 * hit_ + 4 * math.sin(w + 1.7) + 30 * fall), 0, math.radians(18)))
        # right arm carries the spear upright; on the attack the lance dips forward
        sh, el_, wr = arms["r"]
        sh.rotation_euler = Euler((math.radians(-35 - 30 * atk - 20 * pitch / 28 + 20 * hit_ + 3 * math.sin(w)), math.radians(8), 0))
        el_.rotation_euler = Euler((math.radians(-40 - 10 * atk), 0, 0))
        wr.rotation_euler = Euler((math.radians(-10), 0, 0))
        SPJ.rotation_euler = Euler((math.radians(85 + 135 * atk - 14 * pitch / 28 - 4 * math.sin(w) + 30 * fall), math.radians(-6 + 5 * math.sin(w * 0.5)), 0))
        flag.rotation_euler = Euler((math.radians(10 * math.sin(w)), math.radians(12 * math.sin(w + 1.0)), 0))
        sh, el_, wr = arms["l"]
        sh.rotation_euler = Euler((math.radians(-48 - 5 * atk + 8 * hit_), 0, math.radians(-8)))
        el_.rotation_euler = Euler((math.radians(-52 + 4 * math.sin(w)), 0, 0))

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


sun("key", (50, 0, 35), float(E("KEY", str(K.get("key", 6.0)))), (1.0, 0.93, 0.85))
sun("rim", (60, 0, 200), float(E("RIM", str(K.get("rim", 4.5)))), (0.55, 0.65, 1.0))
wd = bpy.data.worlds.new("w")
sc.world = wd
wd.use_nodes = True
wd.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.3, 0.36, 1)
wd.node_tree.nodes["Background"].inputs[1].default_value = float(E("AMB", str(K.get("amb", 0.7))))

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

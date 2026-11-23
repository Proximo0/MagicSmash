"""KayKit skeletons dressed as bosses (a Bone Regent, an Archlich): the pack's own rig and clips, props hung on its bones.

    python3 -I build_skel.py -- <Skeleton_*.glb> <outdir> <kind> <Action:frames,...>

No retargeting: the skeleton glb carries its clips.  Raw frames and the material-ID pass match build_hero.py, so post.py reads
the output unchanged.  env: RES, ORTHO, YAW (-70), ELEV (20), CAMZ, SAMPLES, plus kind settings below.
"""
import json
import math
import os
import sys

import bpy
import bmesh  # noqa: E402 (after bpy)
from mathutils import Euler, Matrix, Vector

glb, out, kind_name, acts = sys.argv[sys.argv.index("--") + 1:]
E = os.environ.get
GOLD, BONE = (0.72, 0.52, 0.16), (0.78, 0.74, 0.62)

KINDS = {
    "bone_regent": dict(size=1.35, bulk={"chest": 1.2}, drop=["Helmet", "Cloak"], mantle=(0.2, 0.05, 0.3), trim=GOLD, gem=(0.7, 0.2, 0.9), eye=(1.0, 0.75, 0.3), float=0.0),
    "archlich": dict(size=1.3, bulk={"head": 0.72, "chest": 1.15}, drop=["Hat", "LegLeft", "LegRight"], robe=(0.02, 0.06, 0.04), robe2=(0.008, 0.025, 0.018), trim=GOLD, flame=(0.3, 1.0, 0.3), eye=(0.3, 1.0, 0.35), float=0.7),
}
K = KINDS[kind_name]

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col = sc.collection
bpy.ops.import_scene.gltf(filepath=glb)
rig = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
for o in list(bpy.data.objects):
    if o.type == "MESH" and (o.name == "Icosphere" or any(o.name.endswith("_" + d) for d in K["drop"])):
        bpy.data.objects.remove(o)
vl = bpy.context.view_layer
rig.scale = (K["size"],) * 3
vl.update()
BODY = [o for o in bpy.data.objects if o.type == "MESH"]


def material(name, colr, metal=0.0, emit=0.0, rough=0.6):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*colr, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*colr, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


MATS = {}


def mat(name, colr, metal=0.0, emit=0.0):
    if name not in MATS:
        MATS[name] = material(name, colr, metal, emit)
    return MATS[name]


for o in BODY:                                   # the eyes burn
    for sl in o.material_slots:
        if sl.material and sl.material.name.startswith("Glow"):
            b = sl.material.node_tree.nodes["Principled BSDF"]
            for k in list(b.inputs["Base Color"].links):
                sl.material.node_tree.links.remove(k)
            b.inputs["Base Color"].default_value = (*K["eye"], 1)
            b.inputs["Emission Color"].default_value = (*K["eye"], 1)
            b.inputs["Emission Strength"].default_value = 8.0


def hang(ob, bone, loc, rot=(0, 0, 0), scale=(1, 1, 1)):
    """parent ob to a bone; loc/rot/scale are in the rig's rest frame: x across, y along the figure's back (it faces -y), z up, relative to the bone's head, in metres of the unscaled rig."""
    ob.parent = rig
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    vl.update()
    head = rig.matrix_world @ rig.data.bones[bone].head_local
    ob.matrix_world = Matrix.Translation(head + Vector(loc) * K["size"]) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4() @ Matrix.Diagonal((*[s * K["size"] for s in scale], 1))


def prim(kind, name, m, r2=0.0, seg=10):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    if kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=8, radius=1.0)
    elif kind == "cone":                         # along Z, base at -1, tip at +1
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=1.0, radius2=r2, depth=2.0)
    else:
        bmesh.ops.create_cube(bm, size=2.0)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    me.materials.append(m)
    return ob


def rod(name, bone, m, p0, p1, r0, r1):
    """a tapering rod between two points given in the same frame as hang()'s loc."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    ob = prim("cone", name, m, r2=r1 / r0)
    q = d.to_track_quat("Z", "X" if abs(d.normalized().y) > 0.95 else "Y")
    hang(ob, bone, (p0 + p1) / 2, tuple(math.degrees(a) for a in q.to_euler()), (r0, r0, d.length / 2))
    return ob


def tatters(prefix, bone, m, centre, rx, ry, top, n, lens, width):
    """a ragged ring of cloth strips hung from `top`, tips down, round an ellipse about `centre`."""
    for k in range(n):
        th = 2 * math.pi * (k + 0.5 * (k % 2)) / n
        ln = lens[k % len(lens)]
        o = prim("cone", "%s%d" % (prefix, k), m, r2=0.0, seg=6)
        hang(o, bone, (centre[0] + rx * math.cos(th), centre[1] + ry * math.sin(th), top - ln / 2), (180, 0, 0), (width, width * 0.5, ln / 2))


def fcurves_of(a):
    if hasattr(a, "fcurves"):
        return list(a.fcurves), a.fcurves
    out_ = []
    for ly in a.layers:
        for st in ly.strips:
            for cb in st.channelbags:
                out_.append((cb, list(cb.fcurves)))
    return out_, None


for a_ in bpy.data.actions:                      # the clips must not key scale: the boss's own proportions are set per frame below
    lst, coll = fcurves_of(a_)
    if coll is not None:
        for fc in lst:
            if fc.data_path.endswith(".scale"):
                coll.remove(fc)
    else:
        for cb, fcs in lst:
            for fc in fcs:
                if fc.data_path.endswith(".scale"):
                    cb.fcurves.remove(fc)


def pose_at(name, frac=0.0):
    a = bpy.data.actions[name]
    rig.animation_data_create()
    rig.animation_data.action = a
    if getattr(a, "slots", None):
        rig.animation_data.action_slot = a.slots[0]
    f0, f1 = a.frame_range
    t = f0 + (f1 - f0) * frac
    sc.frame_set(int(t), subframe=t - int(t))
    for bn, k in K.get("bulk", {}).items():
        rig.pose.bones[bn].scale = (k, k, k)
    vl.update()


pose_at("Idle")                                  # props are hung where the idle pose puts the hands, so the rods stand upright
if kind_name == "bone_regent":
    manm, trim, gemm = mat("mantle", K["mantle"]), mat("trim", K["trim"], 1.0), mat("gem", K["gem"], 0.0, 3.0)
    dark = mat("mantle_d", (0.09, 0.02, 0.14))
    bone_m = mat("bonec", BONE)
    # a tattered mantle: shoulder cape over the back and arms, long ragged strips behind
    cs = prim("sphere", "cape_shoulders", manm)
    hang(cs, "chest", (0, 0.04, 0.2), (0, 0, 0), (0.5, 0.3, 0.2))
    for k in range(7):
        x = (k - 3) * 0.14
        ln = 0.85 + 0.25 * ((k * 5) % 3) / 2
        o = prim("cone", "cape%d" % k, manm if k % 2 else dark, r2=0.3, seg=6)
        hang(o, "chest", (x, 0.2, 0.22 - ln / 2 - 0.05), (0, 0, 0), (0.1, 0.03, ln / 2))
        o.rotation_euler = o.rotation_euler
    for sg in (1, -1):
        o = prim("cone", "pauld%d" % sg, trim, r2=0.3)
        hang(o, "upperarm." + ("l" if sg > 0 else "r"), (sg * 0.02, 0, 0.15), (0, 0, 0), (0.13, 0.13, 0.12))
        o = prim("cone", "spk%d" % sg, bone_m)
        hang(o, "upperarm." + ("l" if sg > 0 else "r"), (sg * 0.06, 0, 0.3), (0, sg * 25, 0), (0.04, 0.04, 0.14))
    tatters("loin", "hips", manm, (0, 0, 0), 0.2, 0.15, 0.1, 9, [0.5, 0.35, 0.45], 0.08)
    o = prim("cone", "belt", trim)
    hang(o, "hips", (0, 0, 0.08), (0, 0, 0), (0.24, 0.17, 0.04))
    # the crown: a gold band and tall spikes round the skull
    cr = prim("cone", "crownband", trim, r2=1.05)
    hang(cr, "head", (0, 0.0, 0.7), (0, 0, 0), (0.56, 0.56, 0.1))
    for k in range(8):
        a = 2 * math.pi * k / 8
        sp = prim("cone", "cspike%d" % k, trim)
        hang(sp, "head", (0.56 * math.cos(a), 0.56 * math.sin(a), 0.85 + 0.05 * (k % 2)), (0, 0, 0), (0.07, 0.07, 0.2 + 0.1 * (k % 2)))
    # the sceptre in the right hand: a long rod with a jewelled head
    S0 = (0, 0, -0.4)
    rod("scep", "handslot.r", mat("scep_g", (0.5, 0.38, 0.1), 1.0), (0, -0.05, -0.3), (0, 0.1, 0.6), 0.04, 0.035)
    sg = prim("sphere", "scep_gem", gemm)
    hang(sg, "handslot.r", (0, 0.1, 0.7), (0, 0, 0), (0.12, 0.12, 0.14))
    for k in range(4):
        a = math.pi * k / 2
        sp = prim("cone", "scep_pt%d" % k, trim)
        hang(sp, "handslot.r", (0.12 * math.cos(a), 0.1 + 0.12 * math.sin(a), 0.65), (0, 0, 0), (0.03, 0.03, 0.12))
elif kind_name == "archlich":
    robe, robe2, trim = mat("robe", K["robe"]), mat("robe2", K["robe2"]), mat("trim", K["trim"], 1.0)
    flame, flame_i = mat("flame", K["flame"], 0.0, 3.0), mat("flame_i", (0.6, 1.0, 0.5), 0.0, 3.5)
    # the robe: a wide cone from the shoulders to well below the pelvis (the legs are gone), ending in ragged tongues
    o = prim("cone", "robe", robe, r2=0.42)       # one bell of cloth from the shoulders down past the (missing) feet
    hang(o, "hips", (0, 0.0, -0.3), (0, 0, 0), (0.7, 0.55, 1.1))
    o = prim("sphere", "mantle", robe2)
    hang(o, "chest", (0, 0.04, 0.2), (0, 0, 0), (0.62, 0.36, 0.26))
    tatters("tat", "hips", robe2, (0, 0, 0), 0.62, 0.5, -1.1, 13, [0.6, 0.95, 0.4, 0.75], 0.15)
    tatters("tat2", "hips", robe, (0, 0, 0), 0.42, 0.34, -1.0, 9, [0.7, 0.45, 0.6], 0.13)
    for k in range(3):                           # gold bands on the robe
        o = prim("cone", "band%d" % k, trim, r2=1.0)
        hang(o, "hips", (0, 0, -0.5 - 0.22 * k), (180, 0, 0), (0.5 + 0.07 * k, 0.4 + 0.06 * k, 0.025))
    for sg in (1, -1):                           # wide hanging sleeves
        sn = "l" if sg > 0 else "r"
        o = prim("cone", "sleeve" + sn, robe, r2=0.2)
        hang(o, "lowerarm." + sn, (0, 0, 0.1), (180, 0, 0), (0.2, 0.2, 0.42))
        o = prim("cone", "pauld" + sn, robe2)
        hang(o, "upperarm." + sn, (sg * 0.04, 0, 0.12), (0, 0, 0), (0.15, 0.15, 0.12))
    # the tall horned mitre, on the skull
    o = prim("cone", "mitre", robe, r2=0.1)
    hang(o, "head", (0, 0.0, 0.98), (0, 0, 0), (0.3, 0.26, 0.55))
    o = prim("cone", "mitre_band", trim, r2=1.0)
    hang(o, "head", (0, 0.0, 0.5), (0, 0, 0), (0.31, 0.28, 0.04))
    o = prim("sphere", "mitre_gem", mat("mgem", K["flame"], 0.0, 5.0))
    hang(o, "head", (0, -0.3, 0.3), (0, 0, 0), (0.05, 0.03, 0.06))
    for sg in (1, -1):                           # two horns curving out from the mitre's sides
        rod("horn_a%d" % sg, "head", mat("horn", (0.8, 0.76, 0.62)), (sg * 0.25, 0.0, 0.62), (sg * 0.5, 0.0, 0.7), 0.06, 0.045)
        rod("horn_b%d" % sg, "head", mat("horn", (0.8, 0.76, 0.62)), (sg * 0.5, 0.0, 0.7), (sg * 0.55, 0.0, 1.1), 0.045, 0.0)
    # the staff in the right hand: a long dark shaft, a claw head holding a green flame
    rod("staff", "handslot.r", mat("staffm", (0.12, 0.08, 0.05)), (0, -0.05, -0.55), (0, 0.1, 1.55), 0.035, 0.03)
    for k in range(4):
        a = math.pi * k / 2
        rod("claw%d" % k, "handslot.r", mat("clawm", (0.5, 0.45, 0.3), 1.0), (0.04 * math.cos(a), 0.1 + 0.04 * math.sin(a), 1.5), (0.12 * math.cos(a), 0.1 + 0.12 * math.sin(a), 1.78), 0.03, 0.01)
    fl = prim("cone", "sflame", flame, r2=0.0)
    hang(fl, "handslot.r", (0, 0.1, 1.9), (0, 0, 0), (0.16, 0.16, 0.38))
    fl = prim("cone", "sflame_i", flame_i, r2=0.0)
    hang(fl, "handslot.r", (0, 0.1, 1.8), (0, 0, 0), (0.08, 0.08, 0.22))

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
ad = rig.animation_data
meta = {}
FLOAT = K["float"] * K["size"]
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
        u = i / n if loop else i / (n - 1)
        t = f0 + (f1 - f0) * u
        sc.frame_set(int(t), subframe=t - int(t))
        for bn, k in K.get("bulk", {}).items():
            rig.pose.bones[bn].scale = (k, k, k)
        z = 0.0
        if FLOAT:                                # it hovers and bobs; at death it sinks to the ground
            z = FLOAT + 0.08 * math.sin(2 * math.pi * u) if loop else FLOAT * (1 - min(1.0, u * 1.6) ** 2 if name.startswith("Death") else 1.0)
        rig.location = (0, 0, z)
        vl.update()
        sc.render.filepath = os.path.join(out, "%s_%02d.png" % (name, i))
        bpy.ops.render.render(write_still=True)
        id_mode(True)
        sc.render.filepath = os.path.join(out, "%s_%02d_id.png" % (name, i))
        bpy.ops.render.render(write_still=True)
        id_mode(False)
    meta[name] = n
json.dump(meta, open(os.path.join(out, "meta.json"), "w"))

"""Shared helpers for build_town.py: primitives, textured and glowing materials, lights, the Boolean cutter.
Everything is in metres, z up, a building's front faces -Y (build_town.py turns the whole building to the camera).
A hero's sprite is 31.4 px per metre after post.py; buildings are rendered at the same density."""
import math
import random

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector

STATE = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    STATE.clear()
    STATE["sc"] = sc
    STATE["col"] = sc.collection
    STATE["mats"] = {}
    root = bpy.data.objects.new("bld", None)
    sc.collection.objects.link(root)
    STATE["root"] = root
    random.seed(11)
    return root


def lin(h):
    """sRGB 0..255 triple -> linear 0..1 triple."""
    return tuple((c / 255.0) ** 2.2 for c in h)


def mat(name, lo, hi=None, tex=None, emit=0.0, scale=3.0, rough=0.7, edge=0.55):
    """A material. lo/hi: sRGB triples (hi: the lightest stone/plank of a textured one). tex: None, 'stone' (3D Voronoi
    masonry with darker joints), 'plank' (the same, stretched along z), 'roof' (stretched along x)."""
    ms = STATE["mats"]
    if name in ms:
        return ms[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = rough
    b.inputs["Base Color"].default_value = (*lin(lo), 1)
    if emit:
        b.inputs["Emission Color"].default_value = (*lin(lo), 1)
        b.inputs["Emission Strength"].default_value = emit
    if tex:
        n = nt.nodes
        tc = n.new("ShaderNodeTexCoord")
        mp = n.new("ShaderNodeMapping")
        sv = {"stone": (scale, scale, scale), "plank": (scale, scale, scale * 0.22), "roof": (scale * 0.3, scale, scale)}[tex]
        mp.inputs["Scale"].default_value = sv
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        v1 = n.new("ShaderNodeTexVoronoi")
        v1.voronoi_dimensions = "3D"
        v1.feature = "F1"
        v2 = n.new("ShaderNodeTexVoronoi")
        v2.voronoi_dimensions = "3D"
        v2.feature = "DISTANCE_TO_EDGE"
        for v in (v1, v2):
            v.inputs["Scale"].default_value = 1.0
            nt.links.new(mp.outputs[0], v.inputs["Vector"])
        sep = n.new("ShaderNodeSeparateColor")
        nt.links.new(v1.outputs["Color"], sep.inputs[0])
        r1 = n.new("ShaderNodeValToRGB")
        r1.color_ramp.elements[0].color = (*lin(lo), 1)
        r1.color_ramp.elements[1].color = (*lin(hi or lo), 1)
        nt.links.new(sep.outputs[0], r1.inputs["Fac"])
        r2 = n.new("ShaderNodeValToRGB")
        r2.color_ramp.elements[0].position = 0.0
        r2.color_ramp.elements[0].color = (edge, edge, edge, 1)
        r2.color_ramp.elements[1].position = 0.1
        r2.color_ramp.elements[1].color = (1, 1, 1, 1)
        nt.links.new(v2.outputs["Distance"], r2.inputs["Fac"])
        mx = n.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        mx.blend_type = "MULTIPLY"
        mx.inputs[0].default_value = 1.0
        nt.links.new(r1.outputs["Color"], mx.inputs[6])
        nt.links.new(r2.outputs["Color"], mx.inputs[7])
        nt.links.new(mx.outputs[2], b.inputs["Base Color"])
        if emit:
            nt.links.new(mx.outputs[2], b.inputs["Emission Color"])
    ms[name] = m
    return m


def _link(ob):
    STATE["col"].objects.link(ob)
    ob.parent = STATE["root"]


def prim(kind, m, pos, dims, rot=(0, 0, 0), seg=12, r2=0.0, pre=0.0):
    """kind box (dims = w,d,h), cyl (dims = diameter x, diameter y, height; r2 = top radius / bottom radius),
    sph (diameters). pos is the centre; rot in degrees (XYZ)."""
    me = bpy.data.meshes.new("p")
    bm = bmesh.new()
    if kind == "box":
        bmesh.ops.create_cube(bm, size=1.0)
    elif kind == "cyl":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=0.5, radius2=0.5 * r2, depth=1.0)
    elif kind == "sph":
        bmesh.ops.create_uvsphere(bm, u_segments=max(seg, 8), v_segments=max(seg // 2, 6), radius=0.5)
    if pre:
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(pre), 3, "Z"), verts=bm.verts)
    bmesh.ops.scale(bm, vec=Vector(dims), verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new("p", me)
    me.materials.append(m)
    ob.location = pos
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    _link(ob)
    return ob


def box(m, x, y, z0, w, d, h, rot=(0, 0, 0)):
    return prim("box", m, (x, y, z0 + h / 2), (w, d, h), rot)


def cyl(m, x, y, z0, dia, h, top=1.0, seg=14, dia_y=None):
    return prim("cyl", m, (x, y, z0 + h / 2), (dia, dia_y or dia, h), seg=seg, r2=top)


def cone(m, x, y, z0, dia, h, seg=12, tip=0.0):
    return prim("cyl", m, (x, y, z0 + h / 2), (dia, dia, h), seg=seg, r2=tip)


def sph(m, x, y, z, dx, dy=None, dz=None, seg=10):
    return prim("sph", m, (x, y, z), (dx, dy or dx, dz or dx), seg=seg)


def pyramid(m, x, y, z0, w, d, h, tip=0.0):
    """Four-sided hip roof over w x d."""
    return prim("cyl", m, (x, y, z0 + h / 2), (w / 0.7071, d / 0.7071, h), seg=4, r2=tip, pre=45.0)


def gable(m, x, y, z0, w, d, h, ridge="x"):
    """Triangular prism: ridge along x (w long), d across, h high; ridge='y' turns it a quarter."""
    me = bpy.data.meshes.new("g")
    bm = bmesh.new()
    a, b = w / 2, d / 2
    v = [bm.verts.new(p) for p in [(-a, -b, 0), (a, -b, 0), (a, b, 0), (-a, b, 0), (-a, 0, h), (a, 0, h)]]
    for f in [(0, 3, 2, 1), (0, 1, 5, 4), (3, 4, 5, 2), (0, 4, 3), (1, 2, 5)]:
        bm.faces.new([v[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new("g", me)
    me.materials.append(m)
    ob.location = (x, y, z0)
    ob.rotation_euler = Euler((0, 0, math.radians(90 if ridge == "y" else 0)))
    _link(ob)
    return ob


def point(x, y, z, energy, colr=(1.0, 0.55, 0.2), rad=0.25):
    lt = bpy.data.objects.new("pl", bpy.data.lights.new("pl", "POINT"))
    lt.data.energy = energy
    lt.data.color = colr
    lt.data.shadow_soft_size = rad
    lt.location = (x, y, z)
    _link(lt)
    return lt


def cut(target, cutters):
    """Boolean-difference every cutter from target (applied, cutters deleted)."""
    for c in cutters:
        c.hide_render = True
        md = target.modifiers.new("b", "BOOLEAN")
        md.operation = "DIFFERENCE"
        md.object = c
        md.solver = "EXACT"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me2 = bpy.data.meshes.new_from_object(target.evaluated_get(dg))
    target.modifiers.clear()
    target.data = me2
    for p in me2.polygons:
        p.use_smooth = False
    for c in cutters:
        bpy.data.objects.remove(c, do_unlink=True)


def arch_cutter(x, y, z0, w, h, depth):
    """Round-headed opening along y: a box plus a half cylinder."""
    r = w / 2
    k = mat("cut", (0, 0, 0))
    a = prim("box", k, (x, y, z0 + (h - r) / 2), (w, depth, h - r))
    c = prim("cyl", k, (x, y, z0 + h - r), (w, w, depth * 1.1), rot=(90, 0, 0), seg=16)
    return [a, c]


def arch_wall(m, x, y, z0, w, d, h, arches, aw, ah, seg=10):
    """A wall slab w x d x h with round-headed openings (centres `arches` along x, width aw, height ah), cut through.
    Built as one extruded outline (no Boolean): along the top, then back along the bottom dipping up round each opening."""
    r = aw / 2
    pts = [(-w / 2, 0), (-w / 2, h), (w / 2, h), (w / 2, 0)]
    for ax in sorted(arches, reverse=True):
        pts.append((ax + r, 0))
        pts.append((ax + r, ah - r))
        for k in range(1, seg):
            a = math.pi * k / seg
            pts.append((ax + r * math.cos(a), ah - r + r * math.sin(a)))
        pts.append((ax - r, ah - r))
        pts.append((ax - r, 0))
    me = bpy.data.meshes.new("aw")
    bm = bmesh.new()
    vs = [bm.verts.new((px, -d / 2, pz)) for px, pz in pts]
    f = bm.faces.new(vs)
    ret = bmesh.ops.extrude_face_region(bm, geom=[f])
    top = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, d, 0), verts=top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new("aw", me)
    me.materials.append(m)
    ob.location = (x, y, z0)
    _link(ob)
    return ob


def tongue(m, x, y, z, w, h, lean, rot_y=0.0):
    """One tongue of flame: three tapering pieces bending toward `lean` (x, y metres at the tip)."""
    segs = 3
    for i in range(segs):
        t0, t1 = i / segs, (i + 1) / segs
        c = (t0 + t1) / 2
        px, py = x + lean[0] * c * c, y + lean[1] * c * c
        r0, r1 = w * (1 - t0 * 0.85), w * (1 - t1 * 0.85)
        ang = math.degrees(math.atan2(lean[0] * 2 * c, h))
        prim("cyl", m, (px, py, z + h * c), (r0, r0, h / segs * 1.15), seg=6, r2=r1 / r0, rot=(0, ang, 0))


def flame(x, y, z, s=1.0):
    """A little living fire: orange tongues, yellow inside them, a pale core."""
    mr = mat("flame_r", (214, 70, 18), emit=1.0)
    mo = mat("flame_o", (255, 128, 28), emit=1.1)
    my = mat("flame_y", (255, 196, 70), emit=1.2)
    mw = mat("flame_w", (255, 238, 170), emit=1.3)
    r = random.Random(int(x * 100 + y * 10 + z * 3))
    for dx, dy, h, w, lx in [(0, 0, 1.15, 0.62, 0.2), (0.42, 0.1, 0.8, 0.4, 0.28), (-0.4, -0.1, 0.9, 0.44, -0.3), (0.1, -0.4, 0.6, 0.34, 0.1), (-0.1, 0.4, 0.7, 0.36, -0.1)]:
        tongue(mr, x + dx * s, y + dy * s, z, w * s, h * s, (lx * s, r.uniform(-0.1, 0.1) * s))
    for dx, dy, h, w, lx in [(0, 0, 0.85, 0.42, 0.14), (0.3, 0.05, 0.55, 0.28, 0.2), (-0.28, -0.05, 0.62, 0.3, -0.2)]:
        tongue(mo, x + dx * s, y + dy * s - 0.05 * s, z, w * s, h * s, (lx * s, 0))
    for dx, h, w, lx in [(0, 0.55, 0.26, 0.1), (0.2, 0.34, 0.18, 0.1)]:
        tongue(my, x + dx * s, y - 0.1 * s, z, w * s, h * s, (lx * s, 0))
    tongue(mw, x, y - 0.15 * s, z, 0.14 * s, 0.3 * s, (0.04 * s, 0))


def lantern(x, y, z, s=1.0, energy=60):
    iron = mat("iron", (34, 36, 44), rough=0.5)
    lamp = mat("lamp", (255, 175, 70), emit=1.5)
    box(iron, x, y, z, 0.26 * s, 0.26 * s, 0.05 * s)
    box(lamp, x, y, z + 0.05 * s, 0.2 * s, 0.2 * s, 0.26 * s)
    pyramid(iron, x, y, z + 0.31 * s, 0.3 * s, 0.3 * s, 0.12 * s)
    if energy:
        point(x, y - 0.2, z + 0.2, energy, (1.0, 0.62, 0.25), 0.15)


def barrel(x, y, z0, s=1.0):
    w = mat("barrel", (84, 56, 36), (112, 78, 50), tex="plank", scale=4)
    iron = mat("iron", (34, 36, 44), rough=0.5)
    cyl(w, x, y, z0, 0.85 * s, 1.05 * s, seg=10)
    for hz in (0.18, 0.8):
        cyl(iron, x, y, z0 + hz * s, 0.9 * s, 0.07 * s, seg=10)


def crate(x, y, z0, s=1.0, rot=0.0):
    w = mat("crate", (88, 62, 40), (122, 90, 58), tex="plank", scale=3.5)
    box(w, x, y, z0, 0.9 * s, 0.9 * s, 0.8 * s, rot=(0, 0, rot))


def stone_set():
    """The shared stone materials: cold grey-blue, three kinds."""
    return (mat("stone", (62, 64, 80), (112, 116, 134), tex="stone", scale=2.2),
            mat("stone_dk", (40, 42, 54), (70, 73, 90), tex="stone", scale=2.0),
            mat("flag", (46, 48, 60), (80, 84, 100), tex="stone", scale=1.6))

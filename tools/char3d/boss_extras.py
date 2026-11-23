"""Extra parts for the redone bosses (bone regent, archlich, ghostwriter); exec'd by build_hero.py inside its globals.
Everything here uses build_hero's helpers: prim, hang, trs, seg, lit, bbox, bw, marks, S, kit, ex."""


def _glow(o, col, strength):
    bs = o.data.materials[0].node_tree.nodes["Principled BSDF"]
    bs.inputs["Emission Color"].default_value = (*col, 1)
    bs.inputs["Emission Strength"].default_value = strength


def _sceptre():
    """a heavy royal sceptre along +Z, grip at the origin: a thick dark shaft with gold bands, a gold collar and a skull-orb of bone."""
    me = bpy.data.meshes.new("sceptre")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.062, radius2=0.052, depth=1.75, matrix=Matrix.Translation((0, 0, 0.55)))
    for z_ in (0.0, 0.5, 1.4):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.085, radius2=0.085, depth=0.07, matrix=Matrix.Translation((0, 0, z_)))
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.15, radius2=0.07, depth=0.2, matrix=Matrix.Translation((0, 0, 1.5)))
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=0.17, matrix=Matrix.Translation((0, 0, 1.78)))
    for k in range(4):                                    # four gold claws holding the orb
        a_ = math.pi * k / 2 + 0.78
        bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.04, radius2=0.0, depth=0.5,
                              matrix=Matrix.Translation((0.2 * math.cos(a_), 0.2 * math.sin(a_), 1.85)) @ Matrix.Rotation(0.35, 4, Vector((-math.sin(a_), math.cos(a_), 0))))
    bm.to_mesh(me)
    bm.free()
    me.transform(Matrix.Diagonal((0.72, 0.72, 0.72, 1)))
    me.transform(Matrix.Rotation(math.radians(float(E("SC_DEG", "-90"))), 4, E("SC_AX", "X")))     # as the scythe: in the 2H sword's frame
    me.materials.append(material("sceptre_haft", (0.05, 0.04, 0.06), 1.0))
    me.materials.append(material("sceptre_gold", (0.55, 0.4, 0.12), 1.0))
    me.materials.append(material("sceptre_orb", (0.62, 0.57, 0.46), 0.0))
    for p_ in me.polygons:
        z_ = -p_.center.y / 0.72                                   # undo the turn: along the sceptre
        r_ = math.hypot(p_.center.x, p_.center.z) / 0.72
        p_.material_index = 2 if (1.6 < z_ < 1.95 and r_ < 0.18) else 1 if (abs(z_) < 0.05 or abs(z_ - 0.5) < 0.05 or abs(z_ - 1.4) < 0.05 or 1.4 < z_ < 1.62 or z_ >= 1.62) else 0
    return me


EXTRA_MESHES["sceptre"] = _sceptre

if "skull" in ex:                                # a normal-proportion skull on the human head: sockets, nose hole, cheek hollows, teeth
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    dark = (0.0, 0.0, 0.0)
    fy = lo.y + half.y * 0.2                                      # the face plane (the nose tip is lo.y)
    zf = lambda f: lo.z + (hi.z - lo.z) * f                       # a height as a fraction of the head's box  # noqa: E731
    for sg in (1, -1):
        o = prim("sphere", "sock%d" % sg, dark)
        hang(o, "head", trs(Vector((c.x + sg * half.x * 0.42, fy + half.y * 0.02, zf(0.6))), (0, 0, 0), (half.x * 0.3, half.y * 0.2, half.z * 0.2)))
        o = prim("sphere", "cheek%d" % sg, kit["bonec2"])         # the cheekbone's ridge under the socket
        hang(o, "head", trs(Vector((c.x + sg * half.x * 0.7, fy + half.y * 0.15, zf(0.46))), (0, 0, 0), (half.x * 0.2, half.y * 0.25, half.z * 0.12)))
        o = prim("sphere", "hollow%d" % sg, dark)                 # the hollow of the cheek
        hang(o, "head", trs(Vector((c.x + sg * half.x * 0.7, fy + half.y * 0.35, zf(0.33))), (0, 0, 0), (half.x * 0.14, half.y * 0.25, half.z * 0.14)))
    o = prim("cone", "nasal", dark)
    hang(o, "head", trs(Vector((c.x, fy - half.y * 0.02, zf(0.44))), (180, 0, 0), (half.x * 0.14, half.y * 0.12, half.z * 0.17)))
    o = prim("cube", "mouthvoid", dark)
    hang(o, "head", trs(Vector((c.x, fy + half.y * 0.02, zf(0.27))), (0, 0, 0), (half.x * 0.5, half.y * 0.12, half.z * 0.07)))
    for k in range(7):
        o = prim("cube", "tooth%d" % k, kit["teeth"])
        hang(o, "head", trs(Vector((c.x + (k - 3) * half.x * 0.135, fy - half.y * 0.04 + abs(k - 3) * half.y * 0.03, zf(0.27))), (0, 0, 0), (half.x * 0.055, half.y * 0.08, half.z * 0.1)))

if "ribs" in ex:                                 # the ribcage showing: curved bones across the dark chest, a sternum, a spine's knobs at the belly
    clo, chi = bbox(["chest"])
    cx_, cy_ = (clo.x + chi.x) / 2, (clo.y + chi.y) / 2
    wx, wy = (chi.x - clo.x) / 2 * kit.get("rib_w", 0.8), (chi.y - clo.y) / 2 * 1.02
    zt = marks["chest"] + 0.1 * S
    for k in range(6):
        z_ = zt - k * 0.058 * S
        sc_ = 1.0 - 0.07 * abs(k - 1.5)
        pts = [Vector((cx_ + sg_ * wx * sc_ * math.sin(math.radians(a_)), cy_ - wy * math.cos(math.radians(a_)) - 0.01 * S, z_ - 0.015 * S * (a_ / 80.0))) for sg_ in (1, -1) for a_ in (0,)]
        for sg_ in (1, -1):
            ang = [8, 30, 52, 74, 96]
            ps = [Vector((cx_ + sg_ * wx * sc_ * math.sin(math.radians(a_)), cy_ - wy * math.cos(math.radians(a_)) - 0.012 * S, z_ - 0.03 * S * (a_ / 96.0))) for a_ in ang]
            for j in range(len(ps) - 1):
                seg("rib%d_%d_%d" % (k, sg_ > 0, j), "spine_03", ps[j], ps[j + 1], 0.013 * S, 0.012 * S, kit["bonec"])
    seg("sternum", "spine_03", Vector((cx_, cy_ - wy - 0.012 * S, zt + 0.02 * S)), Vector((cx_, cy_ - wy * 0.99 - 0.012 * S, zt - 0.3 * S)), 0.02 * S, 0.012 * S, kit["bonec"])

if "mantle" in ex:                               # a long royal mantle: a wide sheet from the shoulders to the ankles, a ragged hem, a gold edge, a dark fur collar
    mc = kit["mantle"]
    back_y = max((body.matrix_world @ v.co).y for v, r in zip(body.data.vertices, regs) if r == "chest")
    top = bw("neck_01").z - 0.02 * S
    length = (top - kit.get("mantle_to", 0.1) * S)
    me = bpy.data.meshes.new("mantle")
    bm = bmesh.new()
    NX, NY = 8, 10
    vs = []
    for j in range(NY + 1):
        t = j / NY
        row = []
        for i in range(NX + 1):
            u = (i / NX) * 2 - 1
            w_ = (0.2 + 0.23 * t) * S
            z_ = -t * length
            if j == NY:                                           # the hem: torn into long and short tongues
                z_ += 0.14 * S * (1 if i % 2 else 0) + 0.07 * S * ((i * 3) % 4) / 3 - 0.2 * S
            row.append(bm.verts.new((u * w_, 0.03 * S + 0.2 * S * t * t * kit.get("mantle_flare", 1.0), z_)))
        vs.append(row)
    for j in range(NY):
        for i in range(NX):
            bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("mantle", me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(material("mantle", mc))
    so = o.modifiers.new("thick", "SOLIDIFY")
    so.thickness = 0.02
    hang(o, "spine_03", trs(Vector((0, back_y + 0.03 * S, top))))
    if kit.get("mantle_trim"):
        for sg in (1, -1):                                        # gold edging down the front edges
            seg("mtrim%d" % sg, "spine_03", Vector((sg * 0.2 * S, back_y + 0.0 * S, top)), Vector((sg * 0.43 * S, back_y + 0.2 * S, top - length + 0.1 * S)), 0.012 * S, 0.012 * S, kit["mantle_trim"], 1.0)
    nlo, nhi = bbox(["neck"])
    o = prim("sphere", "furcollar", kit.get("fur", (0.04, 0.035, 0.04)))
    hang(o, "spine_03", trs(Vector((0, (nlo.y + nhi.y) / 2 + 0.02 * S, nlo.z - 0.01 * S)), (0, 0, 0), (0.2 * S, 0.14 * S, 0.06 * S)))


def _lichstaff():
    """a lich's staff along +Z (turned like the crook): a dark shaft with gold bands, a cage of three gold claws and a dim green flame."""
    me = bpy.data.meshes.new("lichstaff")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.05, radius2=0.04, depth=2.6, matrix=Matrix.Translation((0, 0, 1.1)))
    for z_ in (0.2, 0.9, 2.3):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.075, radius2=0.075, depth=0.06, matrix=Matrix.Translation((0, 0, z_)))
    for k in range(3):                                    # three claws curling up round the flame
        a_ = 2 * math.pi * k / 3
        bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.04, radius2=0.0, depth=0.55,
                              matrix=Matrix.Translation((0.14 * math.cos(a_), 0.14 * math.sin(a_), 2.62)) @ Matrix.Rotation(-0.28, 4, Vector((-math.sin(a_), math.cos(a_), 0))))
    bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=0.1, matrix=Matrix.Translation((0, 0, 2.66)) @ Matrix.Diagonal((1, 1, 1.5, 1)))   # the flame: a teardrop with two licks
    bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.07, radius2=0.0, depth=0.3, matrix=Matrix.Translation((0, 0, 2.95)))
    bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.045, radius2=0.0, depth=0.22, matrix=Matrix.Translation((0.07, 0.03, 2.85)) @ Matrix.Rotation(-0.4, 4, "Y"))
    bm.to_mesh(me)
    bm.free()
    me.transform(Matrix.Rotation(math.radians(90), 4, "Y"))
    me.materials.append(material("lich_shaft", (0.02, 0.03, 0.03), 0.0))
    me.materials.append(material("lich_gold", (0.5, 0.38, 0.1), 1.0))
    fl = material("lich_flame", (0.04, 0.32, 0.1), 0.0)
    bs = fl.node_tree.nodes["Principled BSDF"]
    bs.inputs["Emission Color"].default_value = (0.04, 0.32, 0.1, 1)
    bs.inputs["Emission Strength"].default_value = 0.35
    me.materials.append(fl)
    for p_ in me.polygons:
        z_ = p_.center.x                                   # the turn put the staff's z on x
        r_ = math.hypot(p_.center.y, p_.center.z)
        p_.material_index = 2 if (z_ > 2.52 and r_ < 0.11) else 1 if (z_ > 2.3 or abs(z_ - 0.2) < 0.05 or abs(z_ - 0.9) < 0.05) else 0
    return me


EXTRA_MESHES["lichstaff"] = _lichstaff

if "mitre" in ex:                                # a tall pointed mitre over the hood: dark cloth, a gold band, two hanging tails
    lo, hi = bbox(["head"])
    c, half = (lo + hi) / 2, (hi - lo) / 2
    h_ = kit.get("mitre_h", 0.3) * S
    o = prim("cone", "mitre", kit["hood"], 0.0, r2=0.25)
    hang(o, "head", trs(Vector((c.x, c.y + half.y * 0.1, hi.z + h_ * 0.55)), (-4, 0, 0), (half.x * 1.2, half.y * 1.15, h_ * 0.55)))
    o = prim("cone", "mitre_band", kit["trim"], 1.0, r2=1.0)
    hang(o, "head", trs(Vector((c.x, c.y + half.y * 0.1, hi.z + 0.03 * S)), (0, 0, 0), (half.x * 1.26, half.y * 1.2, 0.03 * S)))
    o = prim("cube", "mitre_cross", kit["trim"], 1.0)
    hang(o, "head", trs(Vector((c.x, c.y - half.y * 0.95, hi.z + h_ * 0.5)), (0, 0, 0), (0.016 * S, 0.01 * S, h_ * 0.4)))
    for sg in (1, -1):
        o = prim("cone", "mitre_tail%d" % sg, kit["hood"])
        hang(o, "head", trs(Vector((c.x + sg * half.x * 0.5, c.y + half.y * 1.3, lo.z + half.z * 0.5)), (180, 0, 0), (0.04 * S, 0.012 * S, 0.22 * S)))

if "phylactery" in ex:                           # a small gold-framed green gem on a chain at the belt
    blo, bhi = bbox(["belly"])
    at = Vector((bhi.x * 0.55, blo.y - 0.015 * S, marks["hip"] + 0.08 * S))
    seg("phyl_chain", "spine_01", at + Vector((0, 0, 0.03 * S)), at + Vector((0, 0, -0.07 * S)), 0.006 * S, 0.006 * S, kit["trim"], 1.0)
    o = prim("cone", "phyl_frame", kit["trim"], 1.0, r2=0.8)
    hang(o, "spine_01", trs(at + Vector((0, -0.01 * S, -0.14 * S)), (0, 0, 0), (0.055 * S, 0.03 * S, 0.075 * S)))
    o = prim("sphere", "phyl_gem", (0.15, 0.8, 0.3))
    hang(o, "spine_01", trs(at + Vector((0, -0.035 * S, -0.14 * S)), (0, 0, 0), (0.035 * S, 0.02 * S, 0.05 * S)))
    _glow(o, (0.15, 0.8, 0.3), 1.5)

"""One builder per picture (see build_town.py). Each builds into the scene with town_lib and returns the render spec:
res (w, h) px at render (4x the picture), cz (world height the picture is centred on), turn (degrees off face-on).
Metres; z up; the front faces -Y. Light: cold from the upper left, warm from fire and lamps."""
import math
import random

import town_lib as L
from town_lib import arch_wall, box, cyl, cone, sph, prim, pyramid, gable, mat, point, flame, lantern, barrel, crate


def palette():
    P = {}
    P["st"], P["sd"], P["fl"] = L.stone_set()
    P["sl"] = mat("stone_lt", (84, 88, 106), (134, 138, 156), tex="stone", scale=2.6)
    P["wd"] = mat("wood_d", (50, 36, 28), (82, 58, 42), tex="plank", scale=3.5)
    P["wl"] = mat("wood_l", (78, 56, 40), (112, 82, 56), tex="plank", scale=3.5)
    P["slate"] = mat("slate", (34, 38, 52), (62, 68, 90), tex="roof", scale=7.0)
    P["tile"] = mat("tile", (68, 30, 34), (112, 52, 48), tex="roof", scale=7.0)
    P["iron"] = mat("iron", (34, 36, 44), rough=0.5)
    P["steel"] = mat("steel", (96, 104, 124), rough=0.45)
    P["gold"] = mat("gold", (176, 134, 54), rough=0.4)
    P["bone"] = mat("bone", (206, 196, 166))
    P["black"] = mat("black", (8, 8, 12))
    P["crim"] = mat("crim", (104, 24, 34))
    P["plum"] = mat("plum", (74, 34, 100))
    return P


def alt_faces(ob, m2, n):
    """Every other gore of an n-sided cone takes material m2."""
    ob.data.materials.append(m2)
    for p in ob.data.polygons:
        if abs(p.normal.z) > 0.95:
            continue
        a = math.atan2(p.center.y, p.center.x) % (2 * math.pi)
        p.material_index = int(a / (2 * math.pi / n)) % 2


def sparks(x, y, z, n, spread, seed=1):
    r = random.Random(seed)
    sp = mat("spark", (255, 170, 60), emit=1.5)
    for _ in range(n):
        box(sp, x + r.uniform(-spread, spread), y + r.uniform(-spread, spread), z + r.uniform(0, spread * 2.4), 0.09, 0.09, 0.09)


# ---------------------------------------------------------------- the hearth
def hearth():
    P = palette()
    cyl(P["fl"], 0, 0, 0, 6.2, 0.22, seg=10)
    cyl(P["sd"], 0, 0, 0.22, 5.0, 0.28, seg=10)
    cyl(P["st"], 0, 0, 0.5, 2.6, 1.1, top=0.8, seg=10)
    cyl(P["sd"], 0, 0, 1.6, 3.0, 0.3, seg=10)
    bowl = cyl(P["st"], 0, 0, 1.9, 2.6, 0.9, top=1.45, seg=10)
    cyl(P["sl"], 0, 0, 2.75, 4.0, 0.2, seg=10)                       # rim
    cyl(mat("embers", (170, 50, 14), emit=1.0), 0, 0, 2.95, 3.4, 0.05, seg=10)
    for k in range(8):                                               # spikes round the rim
        a = k * math.tau / 8
        cone(P["iron"], 1.95 * math.cos(a), 1.95 * math.sin(a), 2.95, 0.26, 0.5, seg=5)
    for k in range(5):                                               # carved ribs down the bowl
        a = k * math.tau / 5 + 0.3
        box(P["sl"], 1.0 * math.cos(a), 1.0 * math.sin(a), 1.95, 0.22, 0.22, 0.8, rot=(0, 0, math.degrees(a)))
    for a in (20, 110, 200):                                         # logs
        prim("box", mat("log", (50, 32, 22)), (0.6 * math.cos(math.radians(a)), 0.6 * math.sin(math.radians(a)), 3.05), (0.3, 1.9, 0.3), rot=(0, 0, a - 90))
    flame(0, 0, 3.0, 2.7)
    flame(0.9, 0.3, 3.0, 1.4)
    flame(-0.9, -0.2, 3.0, 1.5)
    sparks(0, 0, 4.6, 7, 1.0, 3)
    point(0, -1.0, 3.8, 1500, (1.0, 0.55, 0.2), 0.8)
    return dict(res=(1000, 1100), cz=2.6, turn=30, amb=0.7)


# ---------------------------------------------------------------- the field gates
GATE_GLOW = [(215, 140, 40), (70, 180, 80), (40, 160, 160), (150, 190, 245), (160, 90, 230), (235, 80, 30)]


def gate():
    P = palette()
    box(P["fl"], 0, 0, 0, 18.4, 4.8, 0.16)
    box(P["sd"], 0, -0.2, 0.16, 16.8, 3.0, 0.3)
    xs = [-6.25, -3.75, -1.25, 1.25, 3.75, 6.25]
    arch_h = 3.7
    arch_wall(P["st"], 0, 0, 0.46, 16.0, 2.2, 6.0, xs, 1.7, arch_h)
    box(P["sd"], 0, -0.1, 6.46, 16.6, 2.6, 0.34)                      # cornice
    for k in range(13):                                               # battlements
        box(P["st"], -7.2 + k * 1.2, -0.1, 6.8, 0.75, 2.2, 0.75)
    for ax, col in zip(xs, GATE_GLOW):
        g = mat("glow%d" % int(ax * 10), col, emit=0.5)
        box(g, ax, 0.5, 0.46, 1.7, 0.08, arch_h - 0.85)
        cyl(g, ax, 0.5, 0.46 + arch_h - 0.89, 1.7, 0.08, seg=16).rotation_euler = (math.pi / 2, 0, 0)
        box(P["sl"], ax, -1.15, 0.46 + arch_h - 0.1, 0.55, 0.3, 0.8)   # keystone
        sph(g, ax, -1.35, 0.46 + arch_h + 0.3, 0.3, 0.12, 0.3, seg=8)
        point(ax, -0.4, 1.8, 90, tuple(c / 255 for c in col), 0.4)
    for px in (-5.0, -2.5, 0.0, 2.5, 5.0):                            # lanterns on the piers
        box(P["iron"], px, -1.2, 4.0, 0.08, 0.35, 0.08)
        lantern(px, -1.4, 3.45, 1.0, 50)
    for sx in (-1, 1):                                                # the end towers
        cyl(P["st"], sx * 8.6, 0.0, 0.16, 3.2, 8.2, seg=12)
        cyl(P["sd"], sx * 8.6, 0.0, 8.0, 3.9, 0.4, seg=12)
        cone(P["slate"], sx * 8.6, 0.0, 8.4, 4.0, 2.8, seg=12)
        cone(P["iron"], sx * 8.6, 0.0, 11.0, 0.12, 1.2, seg=4)
        for wz in (3.6, 6.3):
            box(P["black"], sx * 8.6 - sx * 0.2, -1.56, wz, 0.4, 0.2, 0.9)
        box(P["black"], sx * 8.6, -1.55, 4.6, 0.4, 0.2, 0.9)
    return dict(res=(2640, 1760), cz=5.2, turn=14, amb=0.8, key=4.6)




# ---------------------------------------------------------------- the trainer: a fighting yard
def trainer():
    P = palette()
    sand = mat("sand", (62, 52, 46), (92, 78, 64), tex="stone", scale=1.3)
    cyl(sand, 0, 0, 0, 12.4, 0.12, seg=16, dia_y=9.6)
    # fence: front (with a gap), left, right
    for x in [-5.5, -3.7, -1.9, 1.9, 3.7, 5.5]:
        box(P["wd"], x, -4.1, 0.12, 0.24, 0.24, 1.5)
    for x0, x1 in [(-5.5, -1.9), (1.9, 5.5)]:
        for z in (0.55, 1.1):
            box(P["wd"], (x0 + x1) / 2, -4.1, z, x1 - x0, 0.12, 0.14)
    for sx in (-5.5, 5.5):
        for y in [-2.3, -0.5, 1.3]:
            box(P["wd"], sx, y, 0.12, 0.24, 0.24, 1.5)
        for z in (0.55, 1.1):
            box(P["wd"], sx, -1.4, z, 0.12, 5.4, 0.14)
    # the lean-to on the back wall, left
    box(P["wd"], -3.0, 3.9, 0.12, 5.4, 0.35, 3.7)
    for x in (-5.5, -0.5):
        box(P["wd"], x, 1.5, 0.12, 0.3, 0.3, 3.0)
    prim("box", P["slate"], (-3.0, 2.8, 3.4), (6.0, 3.0, 0.22), rot=(14, 0, 0))
    box(P["wd"], -3.0, 1.45, 3.0, 5.6, 0.25, 0.25)
    point(-3.0, 1.0, 2.2, 260, (1.0, 0.6, 0.3), 0.4)
    # a weapon rack standing in front of the back wall: two tiers, swords, spears and axes, all in the light
    rx, ry = -3.0, 2.7
    for x in (-1.8, 1.8):
        box(P["wd"], rx + x, ry, 0.12, 0.24, 0.24, 2.1)
    for z in (0.55, 1.5, 2.2):
        box(P["wd"], rx, ry, z, 3.9, 0.22, 0.16)
    bright = mat("steel_b", (176, 184, 204), rough=0.35)
    for k in range(7):
        x = rx - 1.5 + k * 0.5
        tilt = (k - 3) * 2.5
        if k % 3 == 0:                                                # spears
            box(P["wl"], x, ry - 0.15, 0.3, 0.1, 0.1, 2.3, rot=(0, tilt, 0))
            cone(bright, x - math.sin(math.radians(tilt)) * 1.1, ry - 0.15, 2.5, 0.24, 0.55, seg=4)
        elif k % 3 == 1:                                              # swords
            box(bright, x, ry - 0.15, 0.7, 0.17, 0.06, 1.4, rot=(0, tilt, 0))
            box(P["gold"], x, ry - 0.15, 0.62, 0.5, 0.09, 0.1)
            box(P["wd"], x, ry - 0.15, 0.2, 0.1, 0.1, 0.45)
        else:                                                         # axes
            box(P["wl"], x, ry - 0.15, 0.3, 0.1, 0.1, 1.7, rot=(0, tilt, 0))
            box(bright, x + 0.2, ry - 0.15, 1.55, 0.5, 0.08, 0.42)
    for x in (-4.6, -1.3):                                            # shields on the wall
        cyl(P["crim"], x, 3.65, 2.1, 1.0, 0.1, seg=10).rotation_euler = (math.pi / 2, 0, 0)
        sph(P["steel"], x, 3.6, 2.6, 0.3, 0.2, 0.3)
    box(P["crim"], -2.95, 3.68, 2.2, 0.9, 0.05, 1.5)                  # banner
    barrel(-0.2, 2.9, 0.12)
    for tx in (-0.35, -0.1, 0.15):
        box(P["wl"], tx, 2.9, 1.1, 0.07, 0.07, 1.3, rot=(0, tx * 30, 0))
    lantern(-0.5, 1.3, 2.2, 1.0, 90)
    # the training dummy, in the open
    ds, dsz = mat("straw", (150, 120, 72), (196, 160, 98), tex="stone", scale=5), 0
    box(P["wd"], 2.6, 0.6, 0.12, 1.1, 0.2, 0.16)
    box(P["wd"], 2.6, 0.6, 0.12, 0.2, 1.1, 0.16)
    cyl(P["wl"], 2.6, 0.6, 0.12, 0.3, 2.0, seg=8)
    box(P["wl"], 2.6, 0.6, 1.55, 1.5, 0.14, 0.14)
    cyl(ds, 2.6, 0.6, 0.75, 0.82, 1.15, seg=10)
    cyl(mat("ringred", (120, 26, 30)), 2.6, 0.6, 1.2, 0.88, 0.14, seg=10)
    sph(ds, 2.6, 0.6, 2.2, 0.55)
    cone(P["iron"], 2.6, 0.6, 2.35, 0.55, 0.3, seg=8)
    box(P["steel"], 2.1, 0.2, 1.4, 0.1, 0.05, 1.2, rot=(0, 0, 0))      # a sword stuck in the sack
    box(P["steel"], 2.3, 0.35, 1.05, 0.1, 0.5, 0.08, rot=(0, 0, 25))
    # an archery target and straw bales
    for lx, ly in [(-0.5, 0.3), (0.5, 0.3), (0.0, -0.4)]:
        box(P["wd"], 4.4 + lx, 2.4 + ly, 0.12, 0.16, 0.16, 1.4, rot=(lx * 10, ly * 10, 0))
    for r, m_ in [(1.5, P["bone"]), (1.1, P["crim"]), (0.7, P["bone"]), (0.3, P["crim"])]:
        cyl(m_, 4.4, 2.05, 1.5 + (1.5 - r) * 0.0 + 0.0, r, 0.1 + (1.5 - r) * 0.04, seg=14).rotation_euler = (math.pi / 2, 0, 0)
    for bx, by in [(-4.6, -2.6), (-3.4, -2.8)]:
        box(ds, bx, by, 0.12, 1.1, 0.7, 0.6)
    flame(-5.3, -3.9, 1.62, 0.5)
    rope = mat("rope", (176, 150, 100))
    for k in range(6):                                                # sparring ring
        a0, a1 = k * math.tau / 6, (k + 1) * math.tau / 6
        px0, py0 = 0.2 + 1.7 * math.cos(a0), -1.9 + 1.2 * math.sin(a0)
        px1, py1 = 0.2 + 1.7 * math.cos(a1), -1.9 + 1.2 * math.sin(a1)
        box(P["wd"], px0, py0, 0.12, 0.2, 0.2, 1.0)
        prim("box", rope, ((px0 + px1) / 2, (py0 + py1) / 2, 0.85), (math.hypot(px1 - px0, py1 - py0), 0.07, 0.07), rot=(0, 0, math.degrees(math.atan2(py1 - py0, px1 - px0))))
    return dict(res=(1700, 1000), cz=2.0, turn=32, amb=0.8)


# ---------------------------------------------------------------- the bank: a squat vault house
def bank():
    P = palette()
    box(P["fl"], 0, -0.4, 0, 8.6, 7.0, 0.14)
    box(P["sd"], 0, 0, 0.14, 7.8, 6.0, 0.4)
    wall = 4.0
    box(P["st"], 0, 0, 0.54, 7.0, 5.2, wall)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(P["sl"], sx * 3.5, sy * 2.6, 0.54, 0.7, 0.7, wall)
    box(P["sd"], 0, 0, 0.54 + wall, 7.9, 6.1, 0.4)
    pyramid(P["slate"], 0, 0, 4.94, 7.6, 5.8, 2.1, tip=0.12)
    sph(P["gold"], 0, 0, 7.15, 0.45)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cone(P["iron"], sx * 3.3, sy * 2.5, 4.9, 0.4, 0.9, seg=4)
    box(P["iron"], 0, 0, 7.0, 0.07, 0.07, 0.8)
    # door
    fy = -2.62
    box(P["sl"], 0, fy - 0.1, 0.54, 2.5, 0.3, 3.15)
    box(P["iron"], 0, fy - 0.3, 0.54, 1.9, 0.22, 2.8)
    for i in range(3):
        for j in range(5):
            sph(P["steel"], -0.65 + j * 0.325, fy - 0.45, 0.9 + i * 0.8, 0.14, 0.1, 0.14, seg=6)
    box(P["black"], 0, fy - 0.43, 0.54, 0.05, 0.05, 2.8)
    cyl(P["gold"], 0.55, fy - 0.5, 1.45, 0.5, 0.1, seg=10).rotation_euler = (math.pi / 2, 0, 0)
    for i in range(4):                                                # steps
        box(P["sd"], 0, fy - 0.8 - i * 0.5, 0.14 + 0.0, 3.4 - i * 0.2, 0.5, 0.35 - i * 0.1)
    # coin emblem over the door
    cyl(P["gold"], 0, fy - 0.15, 3.75, 0.95, 0.12, seg=14).rotation_euler = (math.pi / 2, 0, 0)
    cyl(P["black"], 0, fy - 0.22, 3.75, 0.55, 0.08, seg=14).rotation_euler = (math.pi / 2, 0, 0)
    cyl(P["gold"], 0, fy - 0.26, 3.75, 0.3, 0.08, seg=6).rotation_euler = (math.pi / 2, 0, 0)
    # barred windows front and on both sides
    def window(x, y, face):
        o = -1 if (face == "f" or x < 0) else 1
        if face == "f":
            box(P["sl"], x, y, 1.95, 1.5, 0.2, 1.6)
            box(P["black"], x, y + o * 0.1, 2.05, 1.1, 0.2, 1.4)
            for k in range(4):
                box(P["iron"], x - 0.36 + k * 0.24, y + o * 0.2, 2.05, 0.07, 0.1, 1.4)
        else:
            box(P["sl"], x, y, 1.95, 0.2, 1.5, 1.6)
            box(P["black"], x + o * 0.1, y, 2.05, 0.2, 1.1, 1.4)
            for k in range(4):
                box(P["iron"], x + o * 0.2, y - 0.36 + k * 0.24, 2.05, 0.1, 0.07, 1.4)
    fy = -2.6
    for wx in (-2.4, 2.4):
        window(wx, -2.6, "f")
    window(3.5, 0.0, "s")
    window(-3.5, 0.0, "s")
    for lx in (-1.6, 1.6):
        box(P["iron"], lx, fy - 0.1, 3.2, 0.08, 0.3, 0.08)
        lantern(lx, fy - 0.3, 2.65, 0.9, 70)
    # a strongbox by the steps
    box(P["wd"], -2.9, -3.7, 0.14, 1.3, 0.8, 0.75)
    box(P["iron"], -2.9, -3.7, 0.14, 1.36, 0.2, 0.8)
    box(P["gold"], -2.9, -4.12, 0.5, 0.16, 0.06, 0.2)
    return dict(res=(1300, 1180), cz=3.6, turn=30, amb=0.8)


# ---------------------------------------------------------------- the smith: an open forge
def smith():
    P = palette()
    cyl(P["fl"], 0, 0.2, 0, 12.4, 0.14, seg=16, dia_y=9.4)
    box(P["sd"], 0, 4.0, 0.14, 11.0, 0.6, 3.2)                        # back wall
    # forge block and chimney
    fx, fy = 2.6, 2.7
    box(P["st"], fx, fy, 0.14, 4.0, 2.4, 1.3)
    box(P["sd"], fx, fy - 1.1, 1.44, 4.2, 0.35, 0.25)
    box(mat("coal", (180, 56, 16), emit=1.0), fx, fy - 0.2, 1.44, 3.3, 1.5, 0.08)
    for cx_, cy_ in [(-1.1, -0.4), (0.0, -0.1), (1.0, -0.5), (0.5, 0.2), (-0.5, 0.3)]:
        flame(fx + cx_, fy + cy_ - 0.2, 1.5, 0.55)
    box(P["st"], fx, 3.45, 1.44, 2.2, 1.7, 2.3)                       # stack, narrowing
    box(P["st"], fx, 3.45, 3.74, 1.7, 1.4, 3.4)
    box(P["sd"], fx, 3.45, 7.14, 2.1, 1.8, 0.35)
    box(P["black"], fx, 3.45, 7.49, 1.3, 1.0, 0.12)
    # lean-to roof over the forge
    for x in (0.4, 4.9):
        box(P["wd"], x, 0.9, 0.14, 0.34, 0.34, 3.1)
    prim("box", P["tile"], (fx + 0.1, 2.5, 3.4), (5.6, 4.2, 0.24), rot=(12, 0, 0))
    box(P["wd"], fx, 0.9, 3.0, 5.2, 0.28, 0.3)
    # anvil on its stump
    ax, ay = -1.9, -0.6
    cyl(P["wl"], ax, ay, 0.14, 1.1, 0.75, seg=9)
    box(P["iron"], ax, ay, 0.89, 0.7, 0.45, 0.25)
    box(P["iron"], ax, ay, 1.14, 0.4, 0.32, 0.2)
    box(P["steel"], ax, ay, 1.34, 1.5, 0.5, 0.24)
    cone(P["steel"], ax - 1.0, ay, 1.34, 0.46, 0.7, seg=6).rotation_euler = (0, math.pi / 2, 0)
    box(mat("hotbar", (255, 120, 30), emit=1.1), ax + 0.1, ay + 0.1, 1.58, 0.9, 0.11, 0.1, rot=(0, 0, 20))
    box(P["iron"], ax + 0.5, ay - 0.1, 1.58, 0.1, 0.1, 0.5, rot=(0, 70, 0))
    box(P["wl"], ax + 0.65, ay - 0.1, 1.55, 0.5, 0.08, 0.08, rot=(0, 0, 0))
    sparks(ax, ay, 1.7, 6, 0.6, 2)
    point(ax, ay - 0.4, 1.9, 140, (1.0, 0.5, 0.2), 0.2)
    # grindstone, water barrel, tool rack, ingots, bellows
    box(P["wd"], -4.3, 0.8, 0.14, 0.15, 1.1, 1.0)
    box(P["wd"], -3.7, 0.8, 0.14, 0.15, 1.1, 1.0)
    cyl(P["sl"], -4.0, 0.8, 0.9, 1.3, 0.3, seg=14).rotation_euler = (0, math.pi / 2, 0)
    barrel(-4.5, 2.6, 0.14, 1.1)
    box(mat("water", (40, 70, 110)), -4.5, 2.6, 1.12, 0.8, 0.8, 0.05)
    for k, (tw, th) in enumerate([(0.1, 1.3), (0.35, 0.8), (0.12, 1.0), (0.3, 0.6)]):
        box(P["iron"], -2.9 + k * 0.5, 3.62, 1.5, tw, 0.1, th)
    box(P["wd"], -2.2, 3.58, 1.3, 2.4, 0.12, 0.16)
    for k in range(6):
        box(P["steel"], 0.6 + (k % 3) * 0.55, 1.0 - (k // 3) * 0.4, 0.14 + (k // 3) * 0.2, 0.5, 0.3, 0.2)
    box(P["wl"], 0.2, 2.7, 0.6, 0.5, 0.8, 0.5, rot=(0, 0, 0))
    cone(P["iron"], 0.2, 2.1, 0.7, 0.14, 0.7, seg=5).rotation_euler = (math.pi / 2, 0, 0)
    lantern(0.4, 0.65, 2.15, 1.0, 90)
    point(fx, 1.6, 2.2, 900, (1.0, 0.5, 0.18), 0.6)
    return dict(res=(1500, 1500), cz=3.8, turn=30, amb=0.75)




# ---------------------------------------------------------------- the merchants: a wagon stall
def merchants():
    P = palette()
    dirt = mat("dirt", (48, 42, 44), (74, 66, 66), tex="stone", scale=1.4)
    cyl(dirt, 0, 0, 0, 10.4, 0.1, seg=16, dia_y=7.6)
    # wagon bed, wheels, shaft
    box(P["wd"], 0, 0, 0.9, 5.0, 2.4, 0.3)
    box(P["wl"], 0, 1.15, 1.2, 5.0, 0.14, 0.6)                       # back board
    box(P["wl"], -2.45, 0, 1.2, 0.14, 2.4, 0.6)
    box(P["wl"], 2.45, 0, 1.2, 0.14, 2.4, 0.6)
    box(P["iron"], 0, 0, 0.8, 4.4, 0.16, 0.12)
    for wx in (-1.6, 1.6):
        for wy in (-1.3, 1.3):
            wh = cyl(P["wl"], wx, wy, 0.1, 1.7, 0.2, seg=14)
            wh.rotation_euler = (math.pi / 2, 0, 0)
            wh.location.z = 0.95
            hub = cyl(P["iron"], wx, wy, 0.1, 0.4, 0.34, seg=8)
            hub.rotation_euler = (math.pi / 2, 0, 0)
            hub.location.z = 0.95
            for k in range(3):
                box(P["wd"], wx, wy + (-0.12 if wy < 0 else 0.12), 0.95 - 0.06, 1.6, 0.1, 0.12, rot=(0, k * 60, 0))
            rim = cyl(P["steel"], wx, wy, 0.1, 1.84, 0.1, seg=14)
            rim.rotation_euler = (math.pi / 2, 0, 0)
            rim.location.z = 0.95
            rim.location.y = wy + (-0.12 if wy < 0 else 0.12)
    prim("box", P["wd"], (-4.3, 0, 0.55), (4.0, 0.2, 0.18), rot=(0, -9, 0))        # the draught pole
    prim("box", P["wd"], (-4.3, 0.5, 0.55), (4.0, 0.14, 0.14), rot=(0, -9, 0))
    # poles and the striped awning
    for px in (-2.3, 2.3):
        for py in (-1.0, 1.0):
            box(P["wd"], px, py, 1.5, 0.2, 0.2, 2.7)
    cloth = [mat("aw1", (92, 30, 62)), mat("aw2", (150, 138, 112))]
    for k in range(6):
        x = -2.5 + k * 0.9 + 0.45
        for side in (-1, 1):
            prim("box", cloth[k % 2], (x, side * 0.95, 4.65), (0.9, 2.2, 0.1), rot=(side * 23, 0, 0))
        box(cloth[k % 2], x, -1.88, 3.85 + 0.0, 0.45, 0.08, 0.5)
        box(cloth[k % 2], x + 0.45, -1.88, 3.7, 0.45, 0.08, 0.35) if k < 5 else None
    box(P["wd"], 0, 0, 5.1, 5.4, 0.16, 0.16)
    for lx in (-1.6, 0.2, 1.8):
        box(P["iron"], lx, -1.9, 3.35, 0.04, 0.04, 0.4)
        lantern(lx, -1.95, 2.8, 1.0, 110)
    # shelves and goods under the awning
    box(P["wd"], 0, 1.0, 1.8, 4.2, 0.2, 0.12)
    box(P["wd"], 0, 1.0, 2.7, 4.2, 0.2, 0.12)
    r = random.Random(4)
    bottle = [mat("bt1", (60, 150, 80), emit=0.5), mat("bt2", (150, 80, 190), emit=0.5), mat("bt3", (200, 150, 60), emit=0.5)]
    for k in range(9):
        x = -1.9 + k * 0.48
        cyl(bottle[k % 3], x, 0.9, 1.92, 0.22, 0.34 + r.random() * 0.1, seg=6)
        cyl(bottle[(k + 1) % 3], x + 0.1, 0.9, 2.82, 0.2, 0.3, seg=6)
    for k in range(3):
        cyl(cloth[k % 2], -1.2 + k * 1.2, -0.1, 1.2, 0.5, 1.1, seg=8).rotation_euler = (0, math.pi / 2, 0)
    # cargo around
    crate(-3.4, -2.2, 0.1, 1.0, 12)
    crate(-3.3, -2.1, 0.9, 0.8, -8)
    crate(-2.2, -2.7, 0.1, 0.9, 5)
    barrel(3.6, -2.4, 0.1, 1.0)
    barrel(4.3, -1.5, 0.1, 0.9)
    sack = mat("sack", (150, 130, 96), (190, 168, 124), tex="stone", scale=5)
    sph(sack, 3.2, -3.0, 0.45, 0.9, 0.8, 0.8)
    sph(sack, 2.4, -3.2, 0.4, 0.8, 0.7, 0.7)
    sph(sack, 4.4, -2.9, 0.4, 0.8, 0.7, 0.7)
    point(0, -0.8, 3.2, 600, (1.0, 0.62, 0.3), 0.6)
    return dict(res=(1500, 1250), cz=2.6, turn=34, amb=0.8)


# ---------------------------------------------------------------- the card reader's tent
def reader():
    P = palette()
    rug = mat("rug", (50, 22, 54), (80, 40, 84), tex="stone", scale=1.6)
    cyl(rug, 0, 0, 0, 9.0, 0.1, seg=18)
    cyl(P["gold"], 0, 0, 0.0, 9.2, 0.06, seg=18)
    cyl(rug, 0, 0, 0.06, 8.8, 0.06, seg=18)
    c1 = mat("tent1", (66, 28, 104))
    c2 = mat("tent2", (36, 20, 74))
    wall = cyl(c1, 0, 0, 0.1, 6.0, 1.9, seg=16)
    alt_faces(wall, c2, 16)
    roof = cone(c2, 0, 0, 2.0, 7.0, 3.6, seg=16, tip=0.0)
    roof.scale = (1, 1, 1)
    alt_faces(roof, c1, 16)
    cyl(P["gold"], 0, 0, 1.95, 6.15, 0.14, seg=16)                    # trim ring
    box(P["iron"], 0, 0, 5.4, 0.1, 0.1, 1.3)
    sph(P["gold"], 0, 0, 6.8, 0.38)
    box(c1, 0.4, 0, 6.2, 0.8, 0.05, 0.4)
    # door
    box(mat("inside", (60, 30, 40), emit=0.5), 0, -3.02, 0.1, 1.5, 0.1, 1.9)
    for sx in (-1, 1):
        prim("box", mat("flap", (96, 48, 138)), (sx * 1.05, -3.12, 1.05), (0.9, 0.08, 2.0), rot=(0, 0, sx * 18))
    box(P["gold"], 0, -3.14, 2.0, 2.2, 0.1, 0.1)
    point(0, -2.4, 1.2, 140, (1.0, 0.6, 0.35), 0.3)
    # banner: moon and star
    bx, by = -3.9, -2.6
    box(P["wd"], bx, by, 0.1, 0.2, 0.2, 5.4)
    box(P["wd"], bx, by, 5.1, 1.7, 0.12, 0.12)
    ban = mat("banner", (40, 26, 108))
    box(ban, bx, by - 0.02, 2.5, 1.4, 0.06, 2.6)
    cyl(P["gold"], bx - 0.1, by - 0.08, 3.9, 0.85, 0.05, seg=14).rotation_euler = (math.pi / 2, 0, 0)
    c = cyl(ban, bx + 0.12, by - 0.13, 3.9, 0.78, 0.05, seg=14)
    c.rotation_euler = (math.pi / 2, 0, 0)
    for sz_, rot_ in ((1.1, 0), (1.1, 90), (0.8, 45), (0.8, -45)):
        box(P["gold"], bx, by - 0.1, 2.9, sz_ * 0.5 if sz_ < 1 else sz_, 0.05, 0.12, rot=(0, rot_, 0))
    box(P["gold"], bx, by - 0.1, 2.0, 1.1, 0.05, 0.08)
    # candles and the crystal ball table
    rr = random.Random(9)
    wax = mat("wax", (210, 200, 176))
    flm = mat("candle_f", (255, 190, 80), emit=1.4)
    for k in range(8):
        cx_ = -1.9 - rr.random() * 1.0 if k < 4 else 1.7 + rr.random() * 1.0
        cy_ = -3.1 - rr.random() * 0.8
        h = 0.25 + rr.random() * 0.45
        cyl(wax, cx_, cy_, 0.1, 0.17, h, seg=6)
        cone(flm, cx_, cy_, 0.1 + h, 0.12, 0.2, seg=5)
    point(-2.3, -3.4, 0.7, 70, (1.0, 0.6, 0.3), 0.2)
    point(2.2, -3.5, 0.7, 70, (1.0, 0.6, 0.3), 0.2)
    cyl(mat("tbl", (30, 20, 44)), 3.0, -3.6, 0.1, 1.2, 0.8, top=0.8, seg=10)
    cyl(P["gold"], 3.0, -3.6, 0.88, 1.4, 0.08, seg=10)
    sph(mat("crystal", (150, 130, 255), emit=1.2), 3.0, -3.6, 1.28, 0.62)
    point(3.0, -3.9, 1.2, 160, (0.6, 0.5, 1.0), 0.3)
    return dict(res=(1300, 1250), cz=3.2, turn=34, amb=0.8)


# ---------------------------------------------------------------- the market: a long covered hall
def market():
    P = palette()
    box(P["fl"], 0, 0, 0, 14.4, 6.4, 0.14)
    h = 3.8
    xs = [-4.8, -2.4, 0.0, 2.4, 4.8]
    arch_wall(P["st"], 0, -2.2, 0.14, 12.8, 0.8, h, xs, 1.9, 3.2)
    box(P["sd"], 0, 2.2, 0.14, 12.8, 0.7, h)
    for sx in (-1, 1):
        box(P["st"], sx * 6.2, 0, 0.14, 0.7, 4.6, h)
    box(P["sd"], 0, 0, 0.14, 12.0, 4.2, 0.1)
    box(P["sd"], 0, -2.2, 0.14 + h, 13.4, 1.0, 0.35)
    gable(mat("tile_m", (40, 22, 30), (76, 40, 46), tex="roof", scale=7.0), 0, 0, 0.14 + h + 0.2, 14.0, 6.0, 2.2)
    box(P["sd"], 0, 0, 0.14 + h + 2.4, 14.2, 0.35, 0.22)
    # a clock turret on the ridge, a chimney and hanging signs
    box(P["st"], 0, 0, 6.55, 1.9, 1.9, 1.4)
    cyl(P["bone"], 0, -0.98, 6.9, 1.1, 0.1, seg=14).rotation_euler = (math.pi / 2, 0, 0)
    box(P["black"], 0, -1.06, 7.45, 0.08, 0.05, 0.4)
    box(P["black"], 0.2, -1.06, 7.45, 0.35, 0.05, 0.08)
    for sx in (-1, 1):
        box(P["black"], sx * 0.5, -0.9, 7.8, 0.3, 0.08, 0.5)
    pyramid(P["slate"], 0, 0, 7.95, 2.3, 2.3, 1.5)
    box(P["gold"], 0, 0, 9.4, 0.14, 0.14, 0.5)
    box(P["st"], -4.6, 0.8, 5.6, 0.9, 0.9, 1.6)
    box(P["sd"], -4.6, 0.8, 7.2, 1.2, 1.2, 0.2)
    for sx, kind in ((-3.6, "coin"), (3.6, "scale")):
        box(P["iron"], sx, -2.95, 3.55, 0.08, 0.9, 0.08)
        box(P["iron"], sx, -3.3, 3.0, 0.05, 0.05, 0.55)
        box(P["wl"], sx, -3.4, 2.1, 1.1, 0.1, 0.95)
        box(P["gold"], sx, -3.47, 2.2, 0.7, 0.05, 0.7) if kind == "coin" else box(P["bone"], sx, -3.47, 2.2, 0.7, 0.05, 0.7)
        box(P["crim"], sx, -3.52, 2.45, 0.3, 0.04, 0.3)
    for ax in xs:                                                     # keystones and stalls in the bays
        box(P["sl"], ax, -2.62, 0.14 + 3.2 + 0.1, 0.5, 0.2, 0.6)
        box(P["wd"], ax, -1.5, 0.14, 1.5, 0.7, 1.0)
        box(P["wl"], ax, -1.5, 1.14, 1.7, 0.8, 0.08)
    ca = [mat("ca1", (100, 30, 50)), mat("ca2", (170, 156, 130)), mat("ca3", (60, 60, 110))]
    for k, ax in enumerate(xs):
        lantern(ax, -1.4, 2.3, 0.9, 120)
    for k, px in enumerate([-3.6, -1.2, 1.2, 3.6]):
        box(ca[(k + 1) % 3], px, -2.68, 1.5, 0.5, 0.06, 1.6)
        box(P["gold"], px, -2.7, 1.45, 0.5, 0.08, 0.08)
    for ax in (-4.8, 0.0, 4.8):
        crate(ax - 0.3, -1.5, 1.22, 0.5, 8)
        barrel(ax + 0.4, -1.5, 1.22, 0.4)
    barrel(-6.6, -2.8, 0.14, 1.0)
    crate(6.7, -2.8, 0.14, 1.0, 10)
    win = mat("dorm", (225, 150, 60), emit=0.9)
    for dx in (-4.0, 0.0, 4.0):                                       # dormers on the front slope, lit
        box(P["wd"], dx, -1.9, 4.9, 1.3, 1.2, 1.0)
        box(win, dx, -2.52, 5.05, 0.8, 0.06, 0.6)
        gable(P["slate"], dx, -1.9, 5.9, 1.5, 1.4, 0.7)
    point(0, 0.2, 2.2, 900, (1.0, 0.62, 0.3), 1.0)
    return dict(res=(1900, 1250), cz=3.4, turn=26, amb=0.8)


# ---------------------------------------------------------------- the post: a narrow house with a raven loft
def post():
    P = palette()
    box(P["fl"], 0, -0.2, 0, 6.2, 6.2, 0.14)
    box(P["st"], 0, 0, 0.14, 4.0, 4.0, 2.3)
    plaster = mat("plaster", (78, 74, 88), (104, 98, 112), tex="stone", scale=1.3)
    box(plaster, 0, -0.1, 2.44, 4.4, 4.2, 2.3)
    for x in (-2.15, -0.7, 0.7, 2.15):
        box(P["wd"], x, -2.22, 2.44, 0.2, 0.14, 2.3)
    for z in (2.44, 3.6, 4.64):
        box(P["wd"], 0, -2.22, z, 4.5, 0.16, 0.16)
    prim("box", P["wd"], (-1.45, -2.22, 3.6), (0.14, 0.12, 1.7), rot=(0, 40, 0))
    prim("box", P["wd"], (1.45, -2.22, 3.6), (0.14, 0.12, 1.7), rot=(0, -40, 0))
    gable(P["slate"], 0, -0.1, 4.7, 4.8, 4.9, 3.2, ridge="y")
    box(P["wd"], 0, -2.5, 4.7, 0.18, 0.14, 0.18)
    # the loft: a cote on the roof
    cx, cz0 = 0.0, 7.5
    box(P["wd"], cx, 0.4, cz0, 1.6, 1.6, 1.1)
    for dx in (-0.45, 0.0, 0.45):
        box(P["black"], cx + dx, -0.42, cz0 + 0.35, 0.28, 0.1, 0.4)
    box(P["wl"], cx, -0.6, cz0 + 0.12, 1.8, 0.4, 0.08)
    pyramid(P["tile"], cx, 0.4, cz0 + 1.1, 2.1, 2.1, 1.1, tip=0.08)
    box(P["iron"], cx, 0.4, cz0 + 2.1, 0.07, 0.07, 0.7)
    rv = mat("raven", (22, 20, 34), (40, 36, 60), tex="stone", scale=7)
    beak = mat("beak", (150, 130, 80))
    eye = mat("reye", (255, 60, 40), emit=1.5)
    def raven(x, y, z, face=-1.0, s=1.0):
        sph(rv, x, y, z + 0.2 * s, 0.32 * s, 0.5 * s, 0.36 * s)
        sph(rv, x, y + face * 0.2 * s, z + 0.42 * s, 0.24 * s)
        cone(beak, x, y + face * 0.4 * s, z + 0.42 * s, 0.1 * s, 0.22 * s, seg=4).rotation_euler = (face * math.pi / 2, 0, 0)
        prim("box", rv, (x, y - face * 0.32 * s, z + 0.14 * s), (0.14 * s, 0.4 * s, 0.1 * s), rot=(-20 * face, 0, 0))
        sph(eye, x + 0.06 * s, y + face * 0.3 * s, z + 0.47 * s, 0.05 * s)
    raven(0.4, -0.6, cz0 + 0.2, -1, 1.0)
    raven(-0.7, -0.6, cz0 + 0.2, -1, 0.9)
    raven(1.6, -1.8, 6.1, -1, 1.0)
    raven(-1.2, -1.5, 6.4, -1, 0.9)
    # door, windows, letter boxes
    box(P["sl"], -0.8, -2.05, 0.14, 1.3, 0.3, 2.1)
    box(mat("door", (58, 40, 30)), -0.8, -2.2, 0.14, 1.0, 0.16, 1.9)
    sph(P["gold"], -0.55, -2.32, 1.1, 0.12)
    box(P["wd"], 1.2, -2.12, 0.9, 1.4, 0.16, 1.2)
    for i in range(3):
        for j in range(2):
            box(P["wl"], 0.8 + i * 0.4, -2.26, 0.98 + j * 0.5, 0.36, 0.12, 0.42)
            box(P["black"], 0.8 + i * 0.4, -2.34, 1.28 + j * 0.5, 0.2, 0.05, 0.05)
    win = mat("win", (255, 190, 90), emit=1.4)
    for x in (-1.0, 1.0):
        box(P["wd"], x, -2.32, 2.85, 0.9, 0.14, 1.1)
        box(win, x, -2.4, 2.95, 0.7, 0.06, 0.9)
        box(P["wd"], x, -2.44, 2.95, 0.08, 0.06, 0.9)
        box(P["wd"], x, -2.44, 3.35, 0.7, 0.06, 0.08)
    box(P["wd"], 0, -2.34, 4.9, 1.0, 0.14, 1.1)
    cyl(win, 0, -2.42, 5.0, 0.8, 0.05, seg=10).rotation_euler = (math.pi / 2, 0, 0)
    # the pillar box and the envelope sign
    cyl(P["crim"], 2.6, -3.3, 0.14, 0.8, 1.3, seg=10)
    cone(P["crim"], 2.6, -3.3, 1.44, 0.9, 0.35, seg=10, tip=0.2)
    box(P["black"], 2.6, -3.72, 1.05, 0.5, 0.06, 0.1)
    box(P["gold"], 2.6, -3.7, 0.4, 0.4, 0.06, 0.1)
    box(P["iron"], -2.1, -2.5, 4.35, 0.08, 0.7, 0.08)
    box(P["bone"], -2.1, -2.95, 3.5, 0.8, 0.05, 0.55)
    prim("box", P["bone"], (-2.1, -2.95, 4.0), (0.5, 0.05, 0.5), rot=(0, 45, 0))
    sph(P["crim"], -2.1, -3.0, 3.75, 0.14, 0.06, 0.14)
    lantern(-1.9, -2.5, 1.9, 1.0, 100)
    box(P["st"], 1.2, 1.2, 6.2, 0.8, 0.8, 1.5)                      # chimney
    return dict(res=(1100, 1560), cz=4.6, turn=30, amb=0.8)


# ---------------------------------------------------------------- the trade table
def trade():
    P = palette()
    cyl(P["fl"], 0, 0, 0, 10.0, 0.14, seg=16)
    cyl(P["sd"], 0, 0, 0.14, 2.0, 1.0, top=0.8, seg=10)
    cyl(P["sl"], 0, 0, 1.14, 4.0, 0.5, seg=14)
    cyl(P["st"], 0, 0, 1.64, 3.7, 0.12, seg=14)
    for k in range(2):
        box(P["black"], 0, 0, 1.76, 3.4, 0.08, 0.03, rot=(0, 0, 90 * k))
    cyl(P["black"], 0, 0, 1.76, 1.2, 0.03, seg=12)
    for sy in (-1, 1):
        for sx in (-1.1, 1.1):
            box(P["sd"], sx, sy * 3.0, 0.14, 0.5, 0.7, 0.45)
        box(P["st"], 0, sy * 3.0, 0.59, 3.2, 0.75, 0.2)
    for sx in (-4.0, 4.0):
        pass
    for px in (-3.3, 3.3):
        for py in (-3.3, 3.3):
            box(P["wd"], px, py, 0.14, 0.28, 0.28, 5.2)
    cl1, cl2 = mat("can1", (100, 28, 40)), mat("can2", (46, 40, 60))
    can = cone(cl1, 0, 0, 5.2, 9.8, 1.9, seg=8, tip=0.02)
    alt_faces(can, cl2, 8)
    cyl(P["gold"], 0, 0, 7.05, 0.4, 0.4, seg=8, top=0.5)
    # goods on the table
    for gx, gy in [(-1.0, -0.3), (1.0, 0.3)]:
        cyl(P["gold"], gx, gy, 1.76, 0.3, 0.35, top=1.4, seg=8)
    cyl(P["bone"], 0.0, 0.9, 1.76, 0.18, 0.4, seg=6)
    cone(mat("candle_f", (255, 190, 80), emit=1.4), 0.0, 0.9, 2.16, 0.14, 0.22, seg=5)
    for k, (cx_, cy_) in enumerate([(-0.4, -1.0), (-0.2, -1.1), (-0.3, -0.9)]):
        cyl(P["gold"], cx_, cy_, 1.76 + k * 0.05, 0.3, 0.05, seg=8)
    box(P["bone"], 0.7, -0.9, 1.76, 0.6, 0.45, 0.03, rot=(0, 0, 20))
    for lx, ly in [(-3.3, -3.3), (3.3, -3.3)]:
        box(P["iron"], lx, ly + 0.2, 4.4, 0.04, 0.04, 0.8)
        lantern(lx, ly + 0.2, 3.5, 1.0, 100)
    point(0, -0.5, 3.4, 600, (1.0, 0.65, 0.3), 0.8)
    return dict(res=(1400, 1500), cz=3.4, turn=30, amb=0.8)


# ---------------------------------------------------------------- the world board
def board():
    P = palette()
    box(P["fl"], 0, 0, 0, 8.6, 3.8, 0.14)
    for x in (-3.2, 3.2):
        box(P["sd"], x, 0, 0.14, 1.0, 1.0, 0.5)
        box(P["wd"], x, 0, 0.64, 0.5, 0.5, 5.2)
    box(P["wl"], 0, 0.05, 1.0, 6.4, 0.35, 3.6)
    for z in (1.0, 4.4):
        box(P["wd"], 0, -0.2, z, 6.7, 0.18, 0.22)
    for x in (-3.15, 3.15):
        box(P["wd"], x, -0.2, 1.0, 0.22, 0.18, 3.6)
    box(P["wd"], 0, -0.2, 2.6, 6.2, 0.1, 0.1)
    gable(P["slate"], 0, 0, 5.75, 8.2, 2.8, 1.3)
    box(P["wd"], 0, -0.9, 5.7, 7.2, 0.2, 0.2)
    r = random.Random(5)
    paper = [mat("pp1", (206, 196, 160)), mat("pp2", (170, 150, 104)), mat("pp3", (190, 176, 140)), mat("pp4", (150, 70, 60))]
    ink = mat("ink", (38, 30, 30))
    pin = mat("pin", (180, 30, 30))
    spots = [(-2.4, 3.6), (-0.8, 3.7), (0.9, 3.5), (2.5, 3.6), (-2.6, 1.9), (-1.2, 1.6), (2.0, 1.9), (3.0, 1.5), (-0.2, 1.5)]
    for k, (x, z) in enumerate(spots):
        w, h = r.uniform(0.7, 1.0), r.uniform(0.9, 1.2)
        rot = r.uniform(-7, 7)
        box(paper[k % 4], x, -0.2 - 0.04 * (k % 3), z, w, 0.03, h, rot=(0, rot, 0))
        for ln in range(3):
            box(ink, x, -0.3 - 0.04 * (k % 3), z + 0.2 + ln * 0.22, w * 0.7, 0.02, 0.07, rot=(0, rot, 0))
        sph(pin, x, -0.28, z + h - 0.12, 0.12, 0.08, 0.12, seg=6)
    box(paper[1], 0.9, -0.34, 2.3, 1.5, 0.03, 1.9, rot=(0, 2, 0))       # the big bill in the middle
    cyl(mat("bill_r", (140, 30, 34)), 0.9, -0.37, 2.75, 0.9, 0.02, seg=12).rotation_euler = (math.pi / 2, 0, 0)
    sph(P["bone"], 0.9, -0.44, 2.85, 0.42, 0.1, 0.42)
    box(P["bone"], 0.9, -0.44, 2.5, 0.3, 0.1, 0.16)
    box(P["black"], 0.78, -0.5, 2.9, 0.1, 0.05, 0.1)
    box(P["black"], 1.02, -0.5, 2.9, 0.1, 0.05, 0.1)
    box(P["iron"], 3.8, -0.1, 4.2, 0.9, 0.08, 0.08)
    lantern(4.1, -0.1, 3.55, 1.0, 100)
    barrel(4.6, -1.2, 0.14, 0.8)
    for k, dx in enumerate((-0.15, 0.0, 0.15)):
        cyl(P["bone"], 4.6 + dx, -1.2 + dx, 0.9, 0.12, 0.6, seg=6)
    prim("box", P["wd"], (-3.7, -0.9, 1.4), (0.18, 0.18, 2.6), rot=(0, 0, 0))
    point(1.0, -1.2, 2.8, 250, (1.0, 0.62, 0.3), 0.5)
    return dict(res=(1230, 1180), cz=3.2, turn=22, amb=0.8)


# ---------------------------------------------------------------- the class trial: an arena doorway
def trial():
    P = palette()
    box(P["fl"], 0, -0.3, 0, 17.0, 6.6, 0.14)
    arch_wall(P["st"], 0, 0, 0.14, 6.6, 1.8, 7.0, [0.0], 2.8, 4.6)
    box(P["sd"], 0, 0, 7.14, 7.2, 2.2, 0.4)
    for k in range(5):
        box(P["st"], -2.8 + k * 1.4, 0, 7.54, 0.9, 2.0, 0.8)
    box(P["black"], 0, 0.7, 0.14, 2.8, 0.1, 3.2)
    cyl(P["black"], 0, 0.7, 0.14 + 3.16, 2.8, 0.1, seg=16).rotation_euler = (math.pi / 2, 0, 0)
    glow = mat("redglow", (130, 22, 18), emit=0.8)
    box(glow, 0, 0.62, 0.14, 2.0, 0.06, 2.6)
    cyl(glow, 0, 0.62, 0.14 + 2.58, 2.0, 0.06, seg=14).rotation_euler = (math.pi / 2, 0, 0)
    point(0, 0.2, 1.4, 160, (1.0, 0.2, 0.1), 0.5)
    for sx in (-1, 1):
        cyl(P["st"], sx * 5.2, 0.2, 0.14, 3.4, 5.6, seg=12)
        cyl(P["sd"], sx * 5.2, 0.2, 5.5, 4.0, 0.4, seg=12)
        for k in range(8):
            a = k * math.tau / 8
            box(P["st"], sx * 5.2 + 1.65 * math.cos(a), 0.2 + 1.65 * math.sin(a), 5.9, 0.7, 0.7, 0.7, rot=(0, 0, math.degrees(a)))
        box(P["black"], sx * 5.2, -1.45, 3.0, 0.4, 0.2, 1.1)
        box(P["crim"], sx * 5.2 - sx * 0.0, -1.7, 3.6, 0.9, 0.06, 1.7)
        # outer low wall
        box(P["st"], sx * 7.4, 0.2, 0.14, 2.6, 1.6, 2.6)
        for k in range(2):
            box(P["st"], sx * (6.9 + k * 1.0) + 0.0, 0.2, 2.74, 0.7, 1.7, 0.6)
    # skull keystone
    sk = mat("skull", (214, 206, 178))
    sph(sk, 0, -1.5, 5.45, 1.2, 0.9, 1.2)
    box(sk, 0, -1.6, 4.62, 0.7, 0.55, 0.35)
    for ex in (-0.28, 0.28):
        box(mat("eyeglow", (200, 40, 24), emit=1.0), ex, -1.98, 5.5, 0.26, 0.1, 0.26)
    box(P["black"], 0, -2.0, 5.2, 0.14, 0.1, 0.2)
    for tx in (-0.22, 0.0, 0.22):
        box(P["black"], tx, -1.88, 4.7, 0.05, 0.05, 0.2)
    box(P["sl"], 0, -1.4, 5.0, 2.0, 0.3, 0.2)
    # braziers
    for sx in (-1, 1):
        bx, by = sx * 3.5, -2.7
        cyl(P["sd"], bx, by, 0.14, 1.0, 1.7, top=0.6, seg=8)
        cyl(P["iron"], bx, by, 1.84, 0.9, 0.55, top=1.9, seg=10)
        cyl(mat("embers", (170, 50, 14), emit=1.0), bx, by, 2.38, 1.5, 0.04, seg=10)
        flame(bx, by, 2.4, 1.25)
        point(bx, by - 0.3, 3.2, 500, (1.0, 0.5, 0.2), 0.4)
    for i in range(4):
        box(P["sd"], 0, -1.7 - i * 0.55, 0.14, 5.0 + i * 0.5, 0.55, 0.5 - i * 0.12)
    return dict(res=(2000, 1380), cz=3.6, turn=22, amb=0.75, key=4.4)


# ---------------------------------------------------------------- a brazier: a fire to sit at
def brazier():
    P = palette()
    cyl(P["fl"], 0, 0, 0, 2.4, 0.14, seg=10)
    for k in range(3):
        a = k * math.tau / 3 + 0.4
        prim("box", P["iron"], (0.4 * math.cos(a), 0.4 * math.sin(a), 0.4), (0.12, 0.12, 0.8), rot=(0, 0, 0))
    cyl(P["iron"], 0, 0, 0.75, 1.0, 0.4, top=1.5, seg=9)
    cyl(P["steel"], 0, 0, 1.12, 1.55, 0.07, seg=9)
    cyl(mat("embers", (170, 50, 14), emit=1.0), 0, 0, 1.1, 1.25, 0.04, seg=9)
    flame(0, 0, 1.12, 1.0)
    point(0, -0.6, 1.8, 200, (1.0, 0.5, 0.2), 0.4)
    return dict(res=(520, 560), cz=1.3, turn=30, amb=0.7)


BUILDERS = {"hearth": hearth, "gate": gate, "trainer": trainer, "bank": bank, "smith": smith, "merchants": merchants,
            "reader": reader, "market": market, "post": post, "trade": trade, "board": board, "trial": trial, "brazier": brazier}

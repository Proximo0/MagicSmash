"""One builder per home picture (see build_town.py, which renders these when run with HOME=1 or ids starting `home_`).
Furniture and plaques of a player's house, in the town_models style: worn dark wood, iron, tallow candles, bone, deep red
and purple cloth. Metres (a hero is 4.5 m tall, a cell 9 m wide); z up; the front faces -Y. Ids are the file names
`ui_<id>.png`: home_<furniture name lower, spaces to _, no '> and home_plaque_<boss 0..7>. A builder returns the render spec
(res, cz, turn) like town_models."""
import math

import town_lib as L
from town_lib import box, cyl, cone, sph, prim, mat, point, flame
from town_models import palette

FURNITURE = ["chair", "straw_bed", "linen_rug", "plague_curtain", "table", "bookshelf", "chest", "gallows_clock",
             "hearth", "candelabra", "brazier", "iron_bed", "sigil_rug", "altar", "scrying_bowl", "rune_lamp",
             "window", "mirror", "lantern", "saints_screen", "urn", "skull_shelf", "black_mirror", "ash_throne"]


def pal():
    P = palette()
    P["tal"] = mat("tallow", (196, 180, 134))
    P["lin"] = mat("linen", (150, 140, 118))
    P["straw"] = mat("straw", (126, 102, 58), (150, 124, 72), tex="plank", scale=9.0)
    P["wool"] = mat("wool", (74, 70, 78))
    P["crim"] = mat("crim", (96, 24, 34))
    P["plum"] = mat("plum", (66, 30, 90))
    P["emb"] = mat("embers", (170, 50, 14), emit=1.0)
    P["glow"] = mat("glow", (150, 90, 230), emit=1.2)
    P["glass"] = mat("glass", (60, 40, 110), emit=0.5)
    P["mir"] = mat("mirror", (110, 122, 140), rough=0.15)
    P["blk"] = mat("obsid", (14, 12, 20), rough=0.2)
    P["ash"] = mat("ash", (70, 66, 64), rough=0.9)
    P["clay"] = mat("clay", (92, 58, 44), rough=0.8)
    return P


def candle(P, x, y, z, h=0.5, fs=0.3):
    cyl(P["tal"], x, y, z, 0.17, h, seg=6)
    flame(x, y, z + h, fs)


def spec(w, h, cz, turn=30, amb=0.75):
    return dict(res=(int(w * 125), int(h * 125)), cz=cz, turn=turn, amb=amb)


def legs(m, x0, x1, y0, y1, h, t=0.28):
    for x in (x0, x1):
        for y in (y0, y1):
            box(m, x, y, 0, t, t, h)


def chair():
    P = pal()
    legs(P["wd"], -0.75, 0.75, -0.75, 0.75, 1.9)
    box(P["wl"], 0, 0, 1.9, 1.9, 1.9, 0.26)
    box(P["crim"], 0, -0.05, 2.16, 1.5, 1.5, 0.16)
    for x in (-0.75, 0.75):
        box(P["wd"], x, 0.75, 2.16, 0.28, 0.28, 2.0)
    box(P["wd"], 0, 0.75, 3.7, 1.8, 0.28, 0.4)
    for x in (-0.38, 0, 0.38):
        box(P["wd"], x, 0.75, 2.5, 0.2, 0.2, 1.2)
    cone(P["iron"], -0.75, 0.75, 4.16, 0.3, 0.3, seg=4)
    cone(P["iron"], 0.75, 0.75, 4.16, 0.3, 0.3, seg=4)
    return spec(4, 6, 2.2)


def straw_bed():
    P = pal()
    box(P["wd"], 0, 0, 0.35, 3.6, 6.6, 0.3)
    legs(P["wd"], -1.7, 1.7, -3.1, 3.1, 0.6, 0.35)
    box(P["wd"], 0, 3.25, 0.35, 3.6, 0.3, 1.5)                       # headboard
    box(P["straw"], 0, -0.1, 0.65, 3.2, 6.0, 0.55)
    box(P["lin"], 0, 2.4, 1.2, 2.2, 1.3, 0.35)                       # pillow
    box(P["wool"], 0, -0.9, 1.2, 3.3, 3.5, 0.28)                     # blanket
    box(P["crim"], 0, -2.5, 1.2, 3.3, 0.6, 0.3)
    return spec(6, 5, 0.9)


def linen_rug():
    P = pal()
    box(P["lin"], 0, 0, 0, 5.4, 7.4, 0.12)
    box(P["crim"], 0, 0, 0.12, 4.7, 6.7, 0.04)
    box(P["lin"], 0, 0, 0.16, 3.5, 5.5, 0.04)
    box(P["wool"], 0, 0, 0.2, 2.2, 4.2, 0.03)
    for y in (-3.8, 3.8):
        for k in range(10):
            box(P["lin"], -2.4 + k * 0.53, y, 0, 0.14, 0.4, 0.1)
    return spec(8, 4, 0.1)


def plague_curtain():
    P = pal()
    for x in (-2.6, 2.6):
        box(P["wd"], x, 0, 0, 0.4, 0.4, 5.6)
        sph(P["iron"], x, 0, 5.7, 0.55)
    box(P["iron"], 0, 0, 5.1, 5.4, 0.22, 0.22)
    for k in range(9):
        x = -2.2 + k * 0.55
        h = 4.7 - (0.3 if k % 2 else 0) + (0.2 if k in (3, 4, 5) else 0)
        box(P["plum"] if k % 2 else P["crim"], x, 0.08 * (-1) ** k, 5.0 - h, 0.6, 0.2, h)
    return spec(7, 8, 3.0)


def table():
    P = pal()
    legs(P["wd"], -2.3, 2.3, -1.2, 1.2, 2.2, 0.4)
    box(P["wl"], 0, 0, 2.2, 5.8, 3.2, 0.34)
    box(P["wd"], 0, 0, 1.8, 4.8, 2.4, 0.3)
    box(P["crim"], 0, 0, 2.54, 2.4, 3.3, 0.05)
    candle(P, -1.8, -0.3, 2.54, 0.7, 0.35)
    cyl(P["steel"], 0.9, 0.5, 2.54, 0.8, 0.3, top=0.8, seg=8)
    cyl(P["bone"], 1.7, -0.5, 2.54, 0.5, 0.18, seg=8)
    point(-1.8, -0.6, 3.6, 60)
    return spec(7, 5, 1.8)


def bookshelf():
    P = pal()
    box(P["wd"], 0, 0, 0, 4.4, 1.5, 6.0)
    for k, z in enumerate((0.3, 1.85, 3.4)):
        box(P["blk"], 0, -0.06, z + 0.1, 3.9, 1.4, 1.3)
    box(P["wl"], 0, -0.7, 5.4, 4.6, 1.7, 0.3)
    r = [P["crim"], P["plum"], P["lin"], P["wl"], P["iron"]]
    for row, z in enumerate((0.4, 1.95, 3.5)):
        x = -1.8
        k = row * 3
        while x < 1.7:
            w = 0.22 + 0.07 * ((k * 7) % 4)
            h = 0.85 + 0.09 * ((k * 5) % 4)
            box(r[k % 5], x + w / 2, -0.7, z, w, 0.9, h, rot=(0, 0, 0))
            x += w + 0.03
            k += 1
        if row == 1:
            sph(P["bone"], 1.4, -0.7, z + 0.2, 0.55)
    return spec(6, 8, 3.0)


def chest():
    P = pal()
    box(P["wd"], 0, 0, 0, 4.4, 2.6, 1.8)
    prim("cyl", P["wl"], (0, 0, 1.8), (2.6, 4.4, 4.4), seg=10, r2=1.0, rot=(0, 90, 0)) if False else None
    box(P["wl"], 0, 0, 1.8, 4.5, 2.7, 0.6)
    box(P["wl"], 0, 0, 2.4, 4.2, 2.3, 0.3)
    for x in (-1.5, 1.5):
        box(P["iron"], x, -0.02, 0, 0.32, 2.7, 2.7)
    box(P["iron"], 0, -1.35, 1.1, 0.7, 0.14, 1.0)
    sph(P["gold"], 0, -1.45, 1.5, 0.22)
    for x in (-2.15, 2.15):
        for y in (-1.25, 1.25):
            box(P["iron"], x, y, 0, 0.3, 0.3, 0.5)
    return spec(6, 4, 1.4)


def gallows_clock():
    P = pal()
    box(P["wd"], 0, 0, 0, 3.0, 2.2, 0.8)
    box(P["wd"], 0, 0, 0.8, 2.2, 1.6, 3.8)
    box(P["blk"], 0, -0.82, 1.2, 1.5, 0.1, 2.0)                      # pendulum window
    cyl(P["gold"], 0, -0.95, 1.2, 0.2, 0.02)
    prim("cyl", P["gold"], (0, -0.95, 1.5), (0.8, 0.8, 0.12), seg=10, rot=(90, 0, 0))
    box(P["wd"], 0, 0, 4.6, 2.8, 2.0, 0.5)
    prim("cyl", P["bone"], (0, -1.02, 5.8), (1.9, 1.9, 0.14), seg=14, rot=(90, 0, 0))
    box(P["black"], 0, -1.1, 5.8, 0.08, 0.06, 0.8)
    box(P["black"], 0.3, -1.1, 5.8, 0.6, 0.06, 0.08)
    for k in range(12):
        a = k * math.tau / 12
        box(P["black"], 0.8 * math.sin(a), -1.1, 5.8 + 0.8 * math.cos(a), 0.1, 0.05, 0.1)
    box(P["wd"], 0, 0, 6.7, 2.4, 1.8, 0.35)
    prim("cyl", P["iron"], (0, -0.2, 7.4), (0.35, 0.35, 1.2), seg=6)
    box(P["iron"], 0, 0, 7.0, 0.2, 0.2, 1.3)
    cone(P["iron"], 0, 0, 7.9, 0.5, 0.5, seg=4)
    return spec(5, 12, 4.2)


def hearth():
    P = pal()
    box(P["st"], 0, 0, 0, 5.4, 2.6, 4.4)
    box(P["blk"], 0, -0.7, 0.4, 3.0, 1.4, 2.6)
    box(P["sd"], 0, -0.7, 0.3, 3.4, 1.6, 0.25)
    box(P["sl"], 0, -0.1, 4.4, 6.0, 3.0, 0.4)
    box(P["emb"], 0, -0.7, 0.55, 2.4, 1.0, 0.1)
    for dx, h, lx in [(0, 1.1, 0.2), (-0.7, 0.8, -0.2), (0.7, 0.8, 0.2)]:
        flame(dx, -0.8, 0.6, 1.1 * h)
    box(P["wd"], -0.4, -0.9, 0.55, 1.6, 0.25, 0.25, rot=(0, 0, 20))
    box(P["wd"], 0.4, -0.7, 0.55, 1.6, 0.25, 0.25, rot=(0, 0, -15))
    candle(P, -2.1, -0.4, 4.8, 0.7, 0.3)
    sph(P["bone"], 2.0, -0.4, 5.1, 0.7)
    point(0, -1.8, 1.4, 200, (1.0, 0.5, 0.2), 0.4)
    return spec(8, 8, 2.8)


def candelabra():
    P = pal()
    cyl(P["iron"], 0, 0, 0, 1.6, 0.3, top=0.6, seg=8)
    cyl(P["iron"], 0, 0, 0.3, 0.3, 3.4, seg=6)
    cyl(P["iron"], 0, 0, 1.6, 0.6, 0.3, seg=8)
    box(P["iron"], 0, 0, 3.4, 3.2, 0.2, 0.2)
    box(P["iron"], 0, 0, 3.4, 0.2, 3.2, 0.2)
    for x, y in ((-1.5, 0), (1.5, 0), (0, -1.5), (0, 1.5), (0, 0)):
        cyl(P["iron"], x, y, 3.3, 0.5, 0.2, seg=6)
        candle(P, x, y, 3.5, 0.9 if (x, y) != (0, 0) else 1.3, 0.35)
    point(0, -1, 5.2, 120)
    return spec(5, 8, 2.8)


def brazier():
    P = pal()
    for k in range(3):
        a = k * math.tau / 3 + 0.4
        prim("box", P["iron"], (0.8 * math.cos(a), 0.8 * math.sin(a), 0.9), (0.2, 0.2, 1.8))
    cyl(P["iron"], 0, 0, 1.8, 2.0, 0.8, top=1.5, seg=9)
    cyl(P["steel"], 0, 0, 2.55, 3.0, 0.12, seg=9)
    cyl(P["emb"], 0, 0, 2.5, 2.5, 0.08, seg=9)
    flame(0, 0, 2.55, 1.6)
    point(0, -1.0, 3.5, 200, (1.0, 0.5, 0.2), 0.4)
    return spec(5, 7, 2.6)


def iron_bed():
    P = pal()
    box(P["iron"], 0, 0, 0.5, 3.6, 6.6, 0.25)
    box(P["straw"], 0, -0.1, 0.75, 3.3, 6.1, 0.35)
    box(P["crim"], 0, -0.6, 1.1, 3.4, 4.6, 0.3)
    box(P["lin"], 0, 2.4, 1.1, 2.2, 1.2, 0.35)
    for x in (-1.75, 1.75):
        for y in (-3.2, 3.2):
            box(P["iron"], x, y, 0, 0.3, 0.3, 4.0 if y > 0 else 2.4)
            sph(P["steel"], x, y, 4.1 if y > 0 else 2.5, 0.42, seg=8)
    box(P["iron"], 0, 3.2, 1.5, 3.4, 0.2, 0.2)
    box(P["iron"], 0, 3.2, 3.4, 3.4, 0.2, 0.2)
    for x in (-1.0, 0, 1.0):
        box(P["iron"], x, 3.2, 1.5, 0.14, 0.14, 2.0)
    box(P["iron"], 0, -3.2, 1.6, 3.4, 0.2, 0.2)
    return spec(7, 7, 1.8)


def sigil_rug():
    P = pal()
    cyl(P["plum"], 0, 0, 0, 6.6, 0.12, seg=24)
    cyl(P["blk"], 0, 0, 0.12, 5.6, 0.04, seg=24)
    cyl(P["crim"], 0, 0, 0.16, 5.0, 0.03, seg=24)
    cyl(P["blk"], 0, 0, 0.19, 4.5, 0.03, seg=24)
    for k in range(5):                                               # pentagram
        a0, a1 = k * math.tau / 5 + math.pi / 2, (k + 2) * math.tau / 5 + math.pi / 2
        x0, y0, x1, y1 = 2.0 * math.cos(a0), 2.0 * math.sin(a0), 2.0 * math.cos(a1), 2.0 * math.sin(a1)
        L_ = math.hypot(x1 - x0, y1 - y0)
        prim("box", P["gold"], ((x0 + x1) / 2, (y0 + y1) / 2, 0.24), (L_, 0.14, 0.04),
             rot=(0, 0, math.degrees(math.atan2(y1 - y0, x1 - x0))))
    cyl(P["crim"], 0, 0, 0.22, 0.7, 0.04, seg=12)
    return spec(8, 5, 0.1)


def altar():
    P = pal()
    box(P["sd"], 0, 0, 0, 5.0, 3.0, 0.5)
    box(P["st"], 0, 0, 0.5, 4.4, 2.5, 1.7)
    box(P["sl"], 0, 0, 2.2, 5.0, 3.0, 0.35)
    box(P["crim"], 0, 0, 2.55, 3.0, 3.1, 0.06)
    box(P["crim"], 0, -1.5, 1.4, 2.0, 0.08, 1.1)
    for x in (-2.0, 2.0):
        candle(P, x, 0.4, 2.55, 1.1, 0.4)
    sph(P["bone"], 0, -0.2, 2.9, 0.8)
    box(P["bone"], 0, -0.2, 2.6, 0.7, 0.5, 0.2)
    cyl(P["gold"], 0.9, 0.2, 2.55, 0.5, 0.35, top=1.4, seg=8)
    point(0, -1.2, 4.0, 120)
    return spec(7, 6, 2.0)


def scrying_bowl():
    P = pal()
    for k in range(3):
        a = k * math.tau / 3 + 0.5
        prim("box", P["iron"], (0.9 * math.cos(a), 0.9 * math.sin(a), 0.9), (0.25, 0.25, 1.8), rot=(0, 0, 0))
    cyl(P["iron"], 0, 0, 1.8, 1.6, 0.3, seg=10)
    cyl(P["iron"], 0, 0, 2.05, 3.0, 0.7, top=1.4, seg=12)
    cyl(P["glow"], 0, 0, 2.7, 3.7, 0.05, seg=12)
    cyl(P["steel"], 0, 0, 2.7, 4.2, 0.07, seg=12)
    cyl(P["glow"], 0, 0, 2.72, 3.5, 0.06, seg=12)
    sph(P["glow"], 0, 0, 3.3, 0.5)
    point(0, -0.5, 3.4, 90, (0.6, 0.4, 1.0), 0.3)
    return spec(5, 6, 2.2)


def rune_lamp():
    P = pal()
    cyl(P["st"], 0, 0, 0, 1.6, 0.4, seg=6)
    box(P["st"], 0, 0, 0.4, 0.9, 0.9, 3.4)
    for k in range(3):
        box(P["glow"], 0, -0.46, 0.9 + k * 0.9, 0.35, 0.05, 0.35)
    box(P["iron"], 0, 0, 3.8, 1.5, 1.5, 0.2)
    box(P["glow"], 0, 0, 4.0, 1.1, 1.1, 1.3)
    for x in (-0.6, 0.6):
        for y in (-0.6, 0.6):
            box(P["iron"], x, y, 4.0, 0.14, 0.14, 1.3)
    prim("cyl", P["iron"], (0, 0, 5.6), (1.7, 1.7, 0.5), seg=4, r2=0.1, pre=45)
    point(0, -0.8, 4.6, 150, (0.6, 0.4, 1.0), 0.3)
    return spec(4, 8, 3.0)


def window():
    P = pal()
    box(P["st"], 0, 0, 0, 5.4, 1.2, 0.5)
    for x in (-2.2, 2.2):
        box(P["st"], x, 0, 0.5, 1.0, 1.2, 5.6)
    box(P["st"], 0, 0, 6.1, 5.4, 1.2, 0.5)
    box(P["glass"], 0, 0.1, 0.5, 3.5, 0.4, 5.6)
    box(P["iron"], 0, -0.15, 0.5, 0.18, 0.2, 5.6)
    for z in (2.0, 3.6):
        box(P["iron"], 0, -0.15, z, 3.5, 0.2, 0.18)
    for x in (-1.2, 1.2):
        box(P["glow"], x, 0.0, 1.0, 0.8, 0.2, 1.0)
    box(P["crim"], -2.0, -0.7, 2.6, 0.9, 0.2, 3.3)
    box(P["crim"], 2.0, -0.7, 2.6, 0.9, 0.2, 3.3)
    return spec(7, 9, 3.2)


def mirror():
    P = pal()
    box(P["wd"], 0, 0.3, 0, 3.6, 0.5, 0.35)
    for x in (-1.6, 1.6):
        box(P["wd"], x, 0.3, 0.35, 0.4, 0.45, 6.2)
    box(P["wl"], 0, 0.3, 6.5, 3.6, 0.45, 0.4)
    box(P["mir"], 0, 0.04, 0.9, 2.8, 0.1, 5.4)
    box(P["gold"], 0, 0.0, 0.8, 3.0, 0.1, 0.12)
    box(P["gold"], 0, 0.0, 6.2, 3.0, 0.1, 0.12)
    box(P["gold"], -1.45, 0.0, 0.8, 0.12, 0.1, 5.6)
    box(P["gold"], 1.45, 0.0, 0.8, 0.12, 0.1, 5.6)
    box(P["bone"], 0, -0.1, 6.9, 0.6, 0.3, 0.6)
    return spec(5, 9, 3.6)


def lantern():
    P = pal()
    box(P["iron"], 0, 0, 0, 1.4, 1.4, 0.3)
    cyl(P["iron"], 0, 0, 0.3, 0.3, 3.8, seg=6)
    box(P["iron"], 0, 0, 3.4, 1.8, 0.2, 0.2)
    box(P["iron"], 0.8, 0, 2.2, 0.2, 0.2, 1.3)
    box(P["iron"], 0.7, 0, 2.0, 1.0, 1.0, 0.2)
    box(P["glow" if False else "emb"], 0.7, 0, 2.2, 0.8, 0.8, 0.9) if False else None
    lamp = mat("lamp", (255, 175, 70), emit=1.5)
    box(lamp, 0.7, 0, 2.2, 0.8, 0.8, 0.9)
    prim("cyl", P["iron"], (0.7, 0, 3.4), (1.3, 1.3, 0.5), seg=4, r2=0.2, pre=45)
    for x in (0.3, 1.1):
        for y in (-0.4, 0.4):
            box(P["iron"], x, y, 2.2, 0.1, 0.1, 0.9)
    point(0.7, -0.8, 2.6, 120, (1.0, 0.6, 0.25), 0.2)
    return spec(5, 8, 2.2)


def saints_screen():
    P = pal()
    for k in range(3):
        x = (k - 1) * 2.1
        box(P["wd"], x, 0, 0, 2.1, 0.35, 5.4)
        box(P["blk"], x, -0.12, 0.4, 1.7, 0.2, 4.2)
        box(P["wl"], x, 0, 5.4, 2.1, 0.35, 0.3)
        cyl(P["gold"], x, -0.25, 3.7, 0.9, 0.08, seg=10) if False else None
        prim("cyl", P["gold"], (x, -0.25, 3.7), (0.9, 0.9, 0.06), seg=10, rot=(90, 0, 0))
        box([P["crim"], P["plum"], P["crim"]][k], x, -0.25, 1.0, 1.0, 0.08, 2.2)
        sph(P["bone"], x, -0.28, 3.7, 0.5)
    return spec(8, 8, 2.8, turn=20)


def urn():
    P = pal()
    cyl(P["clay"], 0, 0, 0, 1.2, 0.3, seg=10)
    cyl(P["clay"], 0, 0, 0.3, 1.2, 1.6, top=2.2, seg=12)
    cyl(P["clay"], 0, 0, 1.9, 2.6, 1.2, top=0.45, seg=12)
    cyl(P["clay"], 0, 0, 3.1, 1.2, 0.4, top=1.2, seg=12)
    cyl(P["crim"], 0, 0, 2.0, 2.65, 0.14, seg=12)
    cyl(P["gold"], 0, 0, 2.4, 2.4, 0.08, seg=12)
    for s in (-1, 1):
        prim("box", P["clay"], (s * 1.45, 0, 2.4), (0.3, 0.3, 1.0), rot=(0, 0, 0))
    return spec(5, 6, 1.9)


def skull_shelf():
    P = pal()
    box(P["wd"], 0, 0.3, 0, 4.6, 1.2, 0.3)
    for x in (-2.0, 2.0):
        box(P["wd"], x, 0.5, 0.3, 0.4, 0.6, 4.8)
    box(P["wd"], 0, 0.6, 0.3, 4.4, 0.4, 4.8)
    for z in (1.3, 2.9, 4.5):
        box(P["wl"], 0, 0.0, z, 4.6, 1.4, 0.3)
    for z, n in ((1.6, 4), (3.2, 3), (4.8, 4)):
        for k in range(n):
            x = -1.6 + k * (3.2 / max(n - 1, 1)) + (0.2 if z == 3.2 else 0)
            sph(P["bone"], x, -0.1, z + 0.42, 0.8, 0.7, 0.8, seg=8)
            box(P["blk"], x - 0.17, -0.45, z + 0.45, 0.2, 0.1, 0.2)
            box(P["blk"], x + 0.17, -0.45, z + 0.45, 0.2, 0.1, 0.2)
            box(P["bone"], x, -0.1, z + 0.02, 0.5, 0.4, 0.2)
    candle(P, 2.0, -0.2, 4.8, 0.6, 0.3)
    return spec(6, 8, 2.8)


def black_mirror():
    P = pal()
    box(P["iron"], 0, 0.3, 0, 3.4, 0.9, 0.35)
    for x in (-1.5, 1.5):
        box(P["iron"], x, 0.3, 0.35, 0.4, 0.5, 1.0)
    box(P["iron"], 0, 0.2, 1.3, 3.6, 0.45, 0.4)
    for x in (-1.5, 1.5):
        box(P["iron"], x, 0.2, 1.7, 0.6, 0.45, 5.0)
    box(P["iron"], 0, 0.2, 6.7, 3.6, 0.45, 0.4)
    box(P["blk"], 0, 0.0, 1.7, 2.4, 0.3, 5.0)
    box(P["glow"], 0, -0.16, 1.9, 0.12, 0.04, 4.6)
    box(P["glow"], 0, -0.16, 1.9, 2.0, 0.04, 0.1)
    box(P["glow"], 0, -0.16, 6.4, 2.0, 0.04, 0.1)
    box(P["glow"], -1.0, -0.16, 1.9, 0.1, 0.04, 4.6)
    box(P["glow"], 1.0, -0.16, 1.9, 0.1, 0.04, 4.6)
    for x in (-1.5, 1.5):
        cone(P["steel"], x, 0.2, 7.1, 0.5, 0.8, seg=4)
    point(0, -1.2, 4.0, 60, (0.6, 0.4, 1.0), 0.3)
    return spec(5, 9, 3.6)


def ash_throne():
    P = pal()
    box(P["ash"], 0, 0, 0, 4.6, 3.8, 0.7)
    box(P["ash"], 0, 0, 0.7, 3.6, 3.0, 1.2)
    box(P["crim"], 0, -0.15, 1.9, 3.1, 2.6, 0.25)
    box(P["ash"], 0, 1.4, 1.9, 4.0, 0.9, 5.0)
    for x in (-1.9, 1.9):
        box(P["ash"], x, 0, 1.9, 0.6, 3.0, 1.2)
    for k, x in enumerate((-1.6, -0.8, 0, 0.8, 1.6)):
        cone(P["ash"], x, 1.4, 6.9, 0.8, 1.5 - abs(x) * 0.3, seg=5)
    box(P["blk"], 0, 0.9, 3.0, 2.2, 0.15, 2.4)
    sph(P["bone"], 0, 0.8, 5.6, 0.8)
    sph(P["bone"], -1.9, -1.4, 3.2, 0.5)
    sph(P["bone"], 1.9, -1.4, 3.2, 0.5)
    candle(P, -1.9, 0.6, 3.1, 0.5, 0.25)
    return spec(7, 11, 3.6)


# ---------------------------------------------------------------- plaques: one board, one emblem per boss
def plaque(n):
    P = pal()
    box(P["wd"], 0, 0.3, 0, 2.6, 1.0, 0.3)
    box(P["wd"], 0, 0.4, 0.3, 0.5, 0.5, 1.2)                         # post
    box(P["wl"], 0, 0.0, 1.5, 3.8, 0.5, 4.2)
    box(P["blk"], 0, -0.27, 1.8, 3.2, 0.1, 3.6)
    for x in (-1.9, 1.9):
        for z in (1.5, 5.7):
            box(P["iron"], x, -0.05, z - 0.1, 0.35, 0.6, 0.35)
    m = P["bone"]
    g = P["gold"]
    y = -0.4
    if n == 0:        # harvester: scythe
        box(P["wl"], 0.4, y, 2.0, 0.16, 0.12, 3.2, rot=(0, 25, 0))
        prim("box", m, (-0.5, y, 5.05), (1.6, 0.12, 0.22), rot=(0, 0, 0))
        prim("box", m, (-1.2, y, 4.7), (1.1, 0.12, 0.2), rot=(0, 55, 0))
    elif n == 1:      # hanging tree: tree and rope
        box(P["wl"], 0, y, 2.0, 0.35, 0.12, 2.4)
        box(P["wl"], 0.6, y, 4.0, 1.6, 0.12, 0.22, rot=(0, 20, 0))
        box(P["wl"], -0.6, y, 3.6, 1.4, 0.12, 0.22, rot=(0, -25, 0))
        box(m, 0.9, y, 3.0, 0.07, 0.07, 1.0)
        prim("cyl", m, (0.9, y, 2.9), (0.5, 0.5, 0.08), seg=8, rot=(90, 0, 0))
    elif n == 2:      # mother of leeches: coiled worm
        for k in range(5):
            sph(P["crim"], -1.0 + k * 0.5, y, 3.6 + 0.5 * math.sin(k * 1.3), 0.6, 0.3, 0.6, seg=8)
        sph(P["crim"], 1.2, y, 4.6, 0.7, 0.3, 0.7, seg=8)
        sph(P["bone"], 1.3, y - 0.1, 4.6, 0.3, 0.2, 0.3, seg=6)
    elif n == 3:      # goat prophet: horned skull
        sph(m, 0, y, 3.4, 1.2, 0.5, 1.4, seg=8)
        for s in (-1, 1):
            box(m, s * 0.9, y, 4.0, 0.25, 0.2, 1.3, rot=(0, s * -25, 0))
            box(m, s * 1.3, y, 4.9, 0.25, 0.2, 0.7, rot=(0, s * -60, 0))
            box(P["blk"], s * 0.3, y - 0.2, 3.5, 0.3, 0.1, 0.3)
    elif n == 4:      # chandelier
        cyl(g, 0, y, 3.0, 2.6, 0.12, top=0.5, seg=10)
        for k in range(5):
            candle(P, -1.0 + k * 0.5, y, 3.05, 0.3, 0.12)
        box(g, 0, y, 3.1, 0.1, 0.1, 2.0)
    elif n == 5:      # ghostwriter: quill and page
        box(P["lin"], -0.5, y, 2.2, 1.6, 0.08, 2.0)
        box(m, 0.7, y, 3.0, 0.14, 0.1, 2.6, rot=(0, 25, 0))
        box(m, 1.15, y, 4.9, 0.5, 0.1, 0.9, rot=(0, 25, 0))
    elif n == 6:      # unmade king: broken crown
        box(g, 0, y, 3.2, 2.4, 0.14, 0.5)
        for k, h in enumerate((0.9, 0.5, 1.2, 0.0, 0.8)):
            if h:
                cone(g, -1.0 + k * 0.5, y, 3.7, 0.45, h, seg=4)
        sph(P["crim"], 0, y - 0.05, 3.45, 0.4)
    else:             # death: skull and hourglass
        sph(m, 0, y, 4.5, 1.2, 0.5, 1.3, seg=8)
        box(m, 0, y, 3.7, 0.7, 0.4, 0.4)
        for s in (-1, 1):
            box(P["blk"], s * 0.28, y - 0.2, 4.55, 0.32, 0.1, 0.32)
        cone(g, 0, y, 2.85, 0.9, 0.5, seg=4)                         # hourglass
        cone(g, 0, y, 2.35, 0.9, 0.5, seg=4, tip=1.0) if False else None
        prim("cyl", g, (0, y, 2.35), (0.9, 0.12, 0.5), seg=4, r2=0.2)
        box(g, 0, y, 3.35, 1.0, 0.14, 0.1)
        box(g, 0, y, 1.95, 1.0, 0.14, 0.1)
    return spec(6, 8, 3.4)


# The models are drawn in "hero metres" (a hero 4.5 tall) at a roomy size; each is shrunk by its own factor so it stands
# right beside a hero (a chair's seat at the hero's knee, a bookshelf a head above him).
SCALE = {"chair": 0.5, "bookshelf": 0.5, "gallows_clock": 0.5, "table": 0.55, "straw_bed": 0.55, "iron_bed": 0.55,
         "linen_rug": 0.6, "sigil_rug": 0.6, "hearth": 0.5, "altar": 0.5, "window": 0.5, "saints_screen": 0.5,
         "plague_curtain": 0.5, "ash_throne": 0.5, "mirror": 0.5, "black_mirror": 0.5, "skull_shelf": 0.5}


def _scaled(fn, k):
    def build():
        sp = fn()
        L.STATE["root"].scale = (k, k, k)
        sp["cz"] = sp["cz"] * k
        return sp
    return build


BUILDERS = {"home_" + n: _scaled(globals()[n], SCALE.get(n, 0.55)) for n in FURNITURE}
for _k in range(8):
    BUILDERS["home_plaque_%d" % _k] = _scaled(lambda k=_k: plaque(k), 0.5)

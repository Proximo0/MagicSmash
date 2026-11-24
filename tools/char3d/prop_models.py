"""Ground props scattered over the fields (builders for build_town.py, ids field_prop_*, env PROPS=1 = all; set=props in
render.sh). Same camera, lighting, palette and pixel scale as the field sites (field_models.py). Metres; z up; the front
faces -Y; the picture's bottom centre is the prop's ground point. Props are small (0.5 to 3 m) so they never hide a monster."""
import math

from town_lib import box, cyl, cone, sph, pyramid, mat
from town_models import palette
from field_models import black_stone, skull

BARK = ((30, 24, 24), (56, 46, 44))


def _bark(n=""):
    return mat("bark" + n, BARK[0], BARK[1], tex="plank", scale=3.0)


def _spec(w=2.4, cz=0.8, amb=0.7, key=4.2):
    return dict(res=(int(w * 220) // 8 * 8 or 8, 480), cz=cz, turn=20, amb=amb, key=key)


def _limb(m, x, y, z, a, tilt, ln, d, n=4):
    seg = ln / n
    for k in range(n):
        cone(m, x, y, z, d * (1 - k / (n + 1.0)), seg * 1.15, seg=5, tip=0.7)
        x += math.sin(tilt) * math.cos(a) * seg
        y += math.sin(tilt) * math.sin(a) * seg
        z += math.cos(tilt) * seg
        tilt += 0.18


def dead_tree(variant):
    bark = _bark()
    h = (3.4, 2.6, 4.4)[variant]
    cone(bark, 0, 0, 0, 0.55, h, seg=7, tip=0.35)
    cone(bark, 0, 0, 0, 0.8, 0.5, seg=7, tip=0.7)                       # root flare
    for k in range(3 + variant):
        a = k * 2.2 + variant
        _limb(bark, 0.05 * math.cos(a), 0.05 * math.sin(a), h * (0.45 + 0.13 * k), a, 0.9 - 0.1 * k, 1.1 + 0.2 * variant, 0.2)
    if variant == 1:                                                    # broken top and a hanging noose of rope
        box(mat("rope", (60, 48, 36), rough=0.9), 0.5, 0, 1.6, 0.05, 0.05, 0.9)
    if variant == 2:
        skull(palette(), 0.1, -0.3, 1.1, 0.5)                           # a skull wedged in the trunk
    return _spec(3.0, h * 0.45)


def dead_tree_a():
    return dead_tree(0)


def dead_tree_b():
    return dead_tree(1)


def dead_tree_c():
    return dead_tree(2)


def _rock(variant):
    st, sd = black_stone()
    if variant == 0:
        sph(sd, 0, 0, 0.35, 1.3, 1.0, 0.8, seg=7)
        sph(st, 0.7, -0.2, 0.25, 0.7, 0.6, 0.5, seg=6)
        sph(st, -0.5, 0.3, 0.2, 0.5, 0.45, 0.4, seg=6)
    else:
        box(sd, 0, 0, 0, 1.0, 0.8, 1.7, rot=(0.08, 0.12, 0.4))          # a leaning shard
        box(st, 0.7, -0.2, 0, 0.8, 0.7, 0.8, rot=(0, 0.1, 1.0))
        pyramid(st, -0.6, 0.2, 0, 0.7, 0.6, 0.5)
    return _spec(2.2, 0.6)


def rock_a():
    return _rock(0)


def rock_b():
    return _rock(1)


def gravestone():
    st, sd = black_stone()
    box(sd, 0, 0, 0, 0.9, 0.5, 0.2)                                      # base
    box(st, 0, 0, 0.2, 0.7, 0.2, 0.9, rot=(0.05, 0.08, 0.1))             # slab, leaning
    cyl(st, 0, 0, 1.1, 0.7, 0.2, seg=10, dia_y=0.2)                      # rounded top
    box(mat("rune_off", (30, 30, 44), rough=0.6), 0, -0.11, 0.6, 0.3, 0.03, 0.06)
    box(mat("rune_off", (30, 30, 44), rough=0.6), 0, -0.11, 0.8, 0.06, 0.03, 0.3)
    box(sd, 0.1, -0.5, 0, 0.9, 0.5, 0.12)                                # grave mound edge
    return _spec(1.4, 0.55)


def grave_cross():
    P = palette()
    st, sd = black_stone()
    box(sd, 0, 0, 0, 0.8, 0.8, 0.15)
    box(P["wd"], 0, 0, 0.15, 0.14, 0.14, 1.4, rot=(0, 0.1, 0))
    box(P["wd"], 0, -0.02, 1.0, 0.7, 0.12, 0.13, rot=(0, 0.1, 0.05))
    box(P["iron"], 0, -0.1, 1.0, 0.16, 0.04, 0.16)
    return _spec(1.2, 0.7)


def broken_pillar():
    st, sd = black_stone()
    box(sd, 0, 0, 0, 1.5, 1.5, 0.3)
    cyl(st, 0, 0, 0.3, 1.0, 2.0, seg=10)
    cyl(sd, 0, 0, 2.3, 1.0, 0.25, top=0.8, seg=10)                       # jagged break
    box(sd, 0.2, 0, 2.5, 0.5, 0.5, 0.4, rot=(0, 0, 0.6))
    cyl(st, 1.3, -0.9, 0.0, 0.9, 1.0, seg=10)                            # a fallen drum
    box(sd, -1.2, -0.7, 0, 0.8, 0.6, 0.35, rot=(0, 0, 0.5))
    return _spec(3.4, 1.2)


def broken_wall():
    st, sd = black_stone()
    box(sd, 0, 0, 0, 3.0, 0.7, 1.1)
    box(st, -0.8, 0, 1.1, 1.2, 0.7, 0.7)
    box(st, 0.9, 0, 1.1, 0.7, 0.7, 0.35, rot=(0, 0, 0.15))
    box(st, 1.9, -0.6, 0, 0.7, 0.5, 0.4, rot=(0, 0, 0.6))
    return _spec(4.0, 0.8)


def bone_pile():
    P = palette()
    b = P["bone"]
    sph(mat("earth", (28, 22, 20), rough=0.9), 0, 0, 0.1, 1.6, 1.2, 0.3, seg=8)
    for k in range(9):
        a = k * 0.9
        box(b, 0.5 * math.cos(a), 0.4 * math.sin(a), 0.12 + 0.04 * (k % 3), 0.9, 0.09, 0.09, rot=(0, 0.3 * (k % 3 - 1), a * 2))
    skull(P, 0.2, -0.3, 0.35, 0.9)
    skull(P, -0.5, 0.15, 0.3, 0.6)
    cone(b, 0.6, 0.1, 0.1, 0.12, 0.7, seg=4)
    return _spec(2.2, 0.35)


def thorn_bush():
    P = palette()
    twig = mat("thorn", (22, 20, 24), (46, 40, 52))
    for k in range(11):
        a = k * 2.4
        _limb(twig, 0.1 * math.cos(a), 0.1 * math.sin(a), 0.0, a, 0.55 + 0.12 * (k % 4), 1.3 + 0.15 * (k % 3), 0.1, n=3)
    for k in range(8):
        a = k * 0.8 + 0.3
        cone(P["bone"], 0.5 * math.cos(a), 0.5 * math.sin(a), 0.5 + 0.1 * (k % 3), 0.06, 0.28, seg=3)
    return _spec(2.4, 0.6)


def stump():
    bark = _bark("s")
    cyl(bark, 0, 0, 0, 0.9, 0.7, top=0.8, seg=8)
    cyl(mat("cut", (70, 56, 46), rough=0.9), 0, 0, 0.7, 0.7, 0.04, seg=8)
    for k in range(4):
        cone(bark, 0.5 * math.cos(k * 1.6), 0.5 * math.sin(k * 1.6), 0, 0.3, 0.3, seg=4)
    return _spec(1.6, 0.35)


BUILDERS = {"field_prop_" + f.__name__: f for f in (
    dead_tree_a, dead_tree_b, dead_tree_c, rock_a, rock_b, gravestone, grave_cross, broken_pillar, broken_wall,
    bone_pile, thorn_bush, stump)}

"""The field's fixed features, one builder per picture (rendered by build_town.py, ids field_*; see town_models.py for the
spec dict). Metres; z up; the front faces -Y. Heroes are 1.8 m (56 px) so: a waystone ~2.9 m, an altar ~3.6 m, the gate ~9 m
wide, the heart a ritual centrepiece ~8 m across. Weathered black stone, iron, bone, faint violet / cold-blue rune light.
The picture's bottom centre is the site's ground point."""
import math

from town_lib import box, cyl, cone, sph, pyramid, mat, point
from town_models import palette

VIOLET = (150, 90, 255)
COLD = (90, 170, 255)
ORANGE = (255, 130, 50)


def black_stone():
    """Darker, colder stone than the town's: weathered black."""
    return (mat("bstone", (22, 22, 30), (50, 52, 66), tex="stone", scale=2.8),
            mat("bstone_d", (12, 12, 18), (30, 30, 40), tex="stone", scale=2.8))


def rune(col, on=True):
    """A rune light: bright when on, a dead dark inlay when off."""
    if on:
        return mat("rune_%d_%d_%d" % col, col, emit=0.9)
    return mat("rune_off", (30, 30, 44), rough=0.6)


def runes_ring(m, r, z, n, w, h, rot0=0.0):
    """n small rune slabs round a pillar of radius r, facing outward."""
    for k in range(n):
        a = rot0 + k * math.tau / n
        box(m, r * math.cos(a), r * math.sin(a), z, w, 0.05, h, rot=(0, 0, a + math.pi / 2))


def skull(P, x, y, z, s):
    sph(P["bone"], x, y, z, 0.3 * s, 0.26 * s, 0.3 * s, seg=8)
    box(P["bone"], x, y - 0.1 * s, z - 0.28 * s, 0.2 * s, 0.14 * s, 0.14 * s)
    for sx in (-1, 1):
        box(P["black"], x + sx * 0.1 * s, y - 0.2 * s, z + 0.0, 0.08 * s, 0.05 * s, 0.09 * s)


# ---------------------------------------------------------------- the field gate: a broken black arch, ~9 m wide
def field_gate():
    P = palette()
    st, sd = black_stone()
    g = rune(VIOLET)
    box(sd, 0, 0, 0, 9.6, 2.6, 0.22)                                   # sill
    for sx in (-1, 1):
        x = sx * 3.7
        box(st, x, 0, 0.22, 1.5, 1.5, 0.6)                              # plinth
        box(sd, x, 0, 0.82, 1.2, 1.2, 4.0)                              # pier
        box(st, x, 0, 4.82, 1.5, 1.5, 0.35)                             # capital
        box(P["iron"], x, -0.62, 1.4, 1.26, 0.06, 0.12)                 # iron bands
        box(P["iron"], x, -0.62, 3.4, 1.26, 0.06, 0.12)
        box(g, x, -0.63, 1.8, 0.14, 0.04, 1.4)                          # rune slot
        pyramid(st, x, 0, 5.17, 1.2, 1.2, 0.9)
        skull(P, x, -0.82, 4.2, 1.0)
        box(P["iron"], x, -0.9, 5.0, 0.06, 0.06, 0.9)                   # spike
    box(st, 0, 0, 5.17, 8.2, 1.3, 0.55)                                # lintel
    box(sd, 0, -0.1, 5.72, 6.2, 1.1, 0.4)
    box(g, 0, -0.66, 5.3, 5.4, 0.04, 0.12)                              # rune band under the lintel
    for k in range(9):
        box(P["iron"], -2.8 + k * 0.7, -0.4, 4.45, 0.07, 0.07, 0.7)     # hanging chains / spikes from the lintel
        if k % 2 == 0:
            skull(P, -2.8 + k * 0.7, -0.5, 4.2, 0.35)
    for sx in (-1, 1):                                                  # fallen blocks
        box(sd, sx * 2.3, -1.6, 0.22, 0.9, 0.7, 0.5, rot=(0, 0, 0.5 * sx))
    point(0, -1.2, 3.0, 120, tuple(c / 255 for c in VIOLET), 0.4)
    return dict(res=(1280, 960), cz=2.6, turn=14, amb=0.7, key=4.2)


# ---------------------------------------------------------------- the heart: a ritual centrepiece, ~8 m across
def field_heart():
    P = palette()
    st, sd = black_stone()
    g = rune(VIOLET)
    c = rune(COLD)
    cyl(sd, 0, 0, 0, 8.2, 0.2, seg=24)                                  # dais
    cyl(st, 0, 0, 0.2, 6.6, 0.25, seg=24)
    cyl(g, 0, 0, 0.45, 5.6, 0.04, seg=24)                               # glowing ring inlay
    cyl(st, 0, 0, 0.49, 5.2, 0.2, seg=24)
    for k in range(8):                                                  # standing stones round the dais
        a = k * math.tau / 8 + 0.2
        x, y = 3.3 * math.cos(a), 3.3 * math.sin(a)
        h = 2.0 + 0.5 * (k % 3)
        box(sd, x, y, 0.2, 0.7, 0.55, h, rot=(0, 0, a))
        box(c if k % 2 else g, x - 0.3 * math.cos(a), y - 0.3 * math.sin(a), 0.7, 0.1, 0.05, 0.9, rot=(0, 0, a))
        if k % 2 == 0:
            cone(P["bone"], x, y, 0.2 + h, 0.3, 0.7, seg=5)
    for k in range(5):                                                  # iron braces binding the heart
        a = k * math.tau / 5
        box(P["iron"], 1.2 * math.cos(a), 1.2 * math.sin(a), 0.7, 0.14, 0.14, 1.4, rot=(0, 0.35, a))
    core = mat("heartcore", (190, 120, 255), emit=1.6)
    cyl(sd, 0, 0, 0.69, 2.2, 0.5, top=0.7, seg=12)
    sph(core, 0, 0, 2.2, 1.5, 1.5, 1.9, seg=14)                         # the heart itself
    sph(mat("heartveil", (120, 70, 200), emit=0.8), 0, 0, 2.2, 1.9, 1.9, 2.3, seg=12)
    for k in range(6):                                                  # bone thorns
        a = k * math.tau / 6 + 0.5
        cone(P["bone"], 1.0 * math.cos(a), 1.0 * math.sin(a), 0.7, 0.3, 1.3, seg=5)
    point(0, -0.8, 2.4, 400, tuple(c_ / 255 for c_ in VIOLET), 0.8)
    return dict(res=(1280, 960), cz=2.1, turn=20, amb=0.7, key=4.0)


# ---------------------------------------------------------------- a waystone: a rune obelisk where heroes bank
def _waystone(lit):
    P = palette()
    st, sd = black_stone()
    g = rune(COLD, lit)
    cyl(sd, 0, 0, 0, 2.6, 0.18, seg=8)
    box(st, 0, 0, 0.18, 1.5, 1.5, 0.45)
    box(sd, 0, 0, 0.63, 1.0, 1.0, 1.6, rot=(0, 0, 0.1))                 # shaft
    pyramid(st, 0, 0, 2.23, 1.0, 1.0, 0.7)
    for z in (0.95, 1.45, 1.95):
        box(g, 0, -0.51, z, 0.5, 0.04, 0.12)                            # rune notches down the front
    box(g, 0, -0.52, 1.2, 0.1, 0.04, 0.5)
    box(P["iron"], 0, -0.53, 0.75, 1.06, 0.08, 0.1)
    sph(mat("wsorb_on", (130, 200, 255), emit=1.6) if lit else mat("wsorb_off", (40, 44, 60)), 0, 0, 3.1, 0.5, 0.5, 0.5, seg=10)
    cone(P["bone"], 0.9, -0.3, 0.18, 0.2, 0.55, seg=5)                  # a bone at the foot
    if lit:
        point(0, -0.8, 2.0, 140, tuple(c / 255 for c in COLD), 0.5)
    return dict(res=(400, 480), cz=1.55, turn=20, amb=0.7, key=4.2)


def field_waystone():
    return _waystone(False)


def field_waystone_lit():
    return _waystone(True)


# ---------------------------------------------------------------- a war altar: a stone table with a brazier bowl
def _altar(lit):
    P = palette()
    st, sd = black_stone()
    cyl(sd, 0, 0, 0, 3.4, 0.2, seg=8)
    box(st, 0, 0, 0.2, 2.4, 1.6, 0.9)                                   # table
    box(sd, 0, 0, 1.1, 2.8, 1.9, 0.25)                                  # slab
    box(P["iron"], 0, -0.96, 1.15, 2.8, 0.06, 0.12)
    for sx in (-1, 1):
        box(sd, sx * 1.3, 0.5, 1.35, 0.35, 0.35, 1.6)                   # horns
        cone(P["iron"], sx * 1.3, 0.5, 2.95, 0.35, 0.7, seg=4)
        skull(P, sx * 0.7, -0.5, 1.7, 0.9)
    bowl = mat("altar_em", (255, 120, 40), emit=1.6) if lit else mat("altar_cold", (36, 30, 34))
    cyl(P["iron"], 0, 0.1, 1.35, 1.1, 0.3, top=1.5, seg=10)
    cyl(bowl, 0, 0.1, 1.62, 0.95, 0.05, seg=10)
    if lit:
        cone(mat("altar_flame", (255, 150, 60), emit=1.8), 0, 0.1, 1.65, 0.6, 1.5, seg=7)
        point(0, -0.6, 2.3, 220, tuple(c / 255 for c in ORANGE), 0.5)
    box(rune(ORANGE, lit), 0, -0.97, 0.5, 1.2, 0.04, 0.15)
    return dict(res=(720, 640), cz=1.7, turn=20, amb=0.7, key=4.2)


def field_altar():
    return _altar(False)


def field_altar_lit():
    return _altar(True)


BUILDERS = {"field_gate": field_gate, "field_heart": field_heart, "field_waystone": field_waystone,
            "field_waystone_lit": field_waystone_lit, "field_altar": field_altar, "field_altar_lit": field_altar_lit}

"""Monsters: layouts, cut into parts, move cycles.  Rules are in monster_checks.py, mannequins and the
spec files in monster_example.py.  One mechanism for every plan: a creature is a tree of PARTS
(a part = the pixels nearest to its bones); a pose is, per part, an angle about its pivot, a
shift and a scale; a frame is the parts drawn in z order with the pose's affine map (nearest
neighbour, so a baked frame holds only the still's colours).  Legs are two-bone IK on gait foot
targets (stance foot moves back exactly as fast as the body travels), flaps and bobs are whole
harmonics of the cycle (frame N equals frame 0), squash keeps area (sx * sy = 1).
Coordinates: still pixels, x right (the creature faces right), y down, canvas 512 x 512."""
import json
import math
import os
from dataclasses import dataclass, field

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CANVAS = 512
FORMAT = "monster"
SIZES = (112, 56)              # the hero scales; a kind's size_px is at 112
TOL_PX = 1                     # as the hero rules: 1 px at 56, so 2 at 112
STYLES = {"biped": ["shamble", "stomp"], "quadruped": ["trot", "scurry"],
          "crawler": ["skitter", "undulate", "squash"], "flyer": ["flap", "orbit"],
          "floater": ["sway"], "construct": ["hop", "rock"]}
LAYOUT_OF = {("biped", "shamble"): "biped", ("biped", "stomp"): "biped",
             ("quadruped", "trot"): "quadruped", ("quadruped", "scurry"): "quadruped",
             ("crawler", "skitter"): "crawler_skitter", ("crawler", "undulate"): "crawler_undulate",
             ("crawler", "squash"): "crawler_squash", ("flyer", "flap"): "flyer_flap",
             ("flyer", "orbit"): "flyer_orbit", ("floater", "sway"): "floater",
             ("construct", "hop"): "construct", ("construct", "rock"): "construct"}
# per style: half stride (share of leg length), bob, foot lift, swings; tol = silhouette area tolerance (M6)
PARAMS = {
    "shamble": dict(A=0.22, bob=0.03, lift=0.10, arm=0.30, tol=0.12),
    "stomp": dict(A=0.17, bob=0.05, lift=0.08, arm=0.22, tol=0.12),
    "trot": dict(A=0.20, bob=0.025, lift=0.12, tail=0.35, tol=0.12),
    "scurry": dict(A=0.14, bob=0.035, lift=0.10, tail=0.45, tol=0.12),
    "skitter": dict(A=0.12, bob=0.012, lift=0.10, tol=0.12),
    "undulate": dict(wave=0.42, tol=0.10),
    "squash": dict(squash=0.18, hop=0.10, tol=0.10),
    "flap": dict(wing=0.62, bob=0.05, tol=0.26),
    "orbit": dict(bob=0.04, tol=0.12),
    "sway": dict(bob=0.04, sway=0.07, tol=0.12),
    "hop": dict(hop=0.12, tilt=0.07, tol=0.10),
    "rock": dict(rock=0.10, tol=0.10),
}


# ---------------------------------------------------------------- the 42 kinds
def load_table():
    with open(os.path.join(HERE, "monsters.json")) as f:
        return json.load(f)


def kind_row(kind):
    for r in load_table():
        if r["kind"] == kind:
            return r
    return None


def table_md():
    """monsters.md is this text (a test compares them)."""
    rows = load_table()
    cnt = {}
    for r in rows:
        cnt[r["plan"]] = cnt.get(r["plan"], 0) + 1
    out = ["# Monster kinds: body plan, size, move style", "",
           "Generated from `monsters.json` (`python3 -m tools.animator monsters --table`); the 42 kinds are the table",
           "`realm/core/src/tables/kinds.rs`. `size_px` is the longest side of the creature at the 112 px hero scale",
           "(a hero is 112 tall); the 56 px bake is half. Plans and their recipes: `STILL_SPEC.md`, part Monsters;",
           "rules M1-M12: `RULES.md`. AWKWARD kinds are the ones a plan fits badly (the note says what to draw).", "",
           "Kinds per plan: " + ", ".join(f"{p} {cnt[p]}" for p in STYLES) + ".", "",
           "| # | kind | field | behaviour | speed px/s | plan | move style | size px | note |",
           "|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        note = ("AWKWARD: " if r["awkward"] else "") + r["note"]
        out.append(f"| {r['id']} | {r['kind']} | {r['field']} | {r['behaviour']} | {r['speed']} | {r['plan']} | "
                   f"{r['style']} | {r['size_px']} | {note} |")
    out += ["", "Move styles: biped `shamble` (hunched walk, arms swing against the legs), `stomp` (short heavy steps, big bob);",
            "quadruped `trot` (diagonal pairs), `scurry` (short quick steps, bigger bob); crawler `skitter` (eight legs, alternate",
            "tetrapod), `undulate` (a wave runs down five segments), `squash` (hop with squash and stretch, area kept);",
            "flyer `flap` (two wings, two segments each, body bobs against the stroke), `orbit` (a core that bobs, parts that circle it);",
            "floater `sway` (bob and sway, a hem of three segments trails); construct `hop` (rigid hop with a tilt), `rock`",
            "(rocks about its base, base kept on the ground). Every cycle is 8 frames (also 4) and loops exactly.", ""]
    return "\n".join(out)


# ---------------------------------------------------------------- layouts
@dataclass
class Part:
    name: str
    bones: list                  # [(joint a, joint b)], a part owns the pixels nearest to them
    r: float                     # radius (px of the 512 canvas): the pixel score is distance - r
    parent: str = None
    pivot: str = None            # joint the part turns about
    z: float = 5.0
    role: str = "body"
    dup: float = 0.0             # x r: pixels this close to the pivot are also kept in the parent (a hip, not a hole)
    colour: tuple = (150, 150, 150)
    far: bool = False


@dataclass
class Leg:
    name: str
    top: str
    mid: str
    foot: str
    upper: str
    lower: str
    footpart: str = None
    toe: str = None
    phase: float = 0.0
    pair: str = "all"


@dataclass
class Layout:
    name: str
    plan: str
    joints: dict
    parts: list
    legs: list = field(default_factory=list)
    groups: dict = field(default_factory=dict)     # limb group -> its parts (legs, wings, arms)
    head_part: str = None
    eye: str = None
    orbit: list = field(default_factory=list)
    ground_y: float = 471              # the row edge under the soles (the lowest drawn row is 470)
    sentence: str = ""
    separation: str = ""
    eye_r: float = 20.0                # mannequin eye (white) radius, px of the canvas

    def part(self, name):
        return next(p for p in self.parts if p.name == name)


def two_bone(top, foot, l1, l2, pick):
    top, foot = np.array(top, float), np.array(foot, float)
    d = float(np.linalg.norm(foot - top))
    u = (foot - top) / d
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(l1 * l1 - a * a, 0))
    base = top + a * u
    perp = np.array([-u[1], u[0]]) * h
    c = [base + perp, base - perp]
    key = {"fwd": lambda q: -q[0], "back": lambda q: q[0], "up": lambda q: q[1]}[pick]
    return [round(float(v), 1) for v in min(c, key=key)]


def _shade(c, k):
    return tuple(min(255, int(v * k)) for v in c)


GB_OFF = 4                    # 1 row edge + 3 px of mannequin outline: fill bottom = ground - GB_OFF


class _LB:
    def __init__(self, name, plan, ground=471):
        self.lay = Layout(name, plan, {}, [], ground_y=ground)

    def joint(self, n, xy):
        self.lay.joints[n] = [float(xy[0]), float(xy[1])]

    def part(self, name, bones, r, parent=None, pivot=None, z=5.0, role="body", dup=0.0, colour=(150, 150, 150), far=False):
        self.lay.parts.append(Part(name, bones, r, parent, pivot, z, role, dup, colour, far))

    def leg(self, name, top, foot_dx_from_top, l1, l2, pick, r1, r2, z, phase, pair, ground, col, far, toe_dx=None, rf=9):
        top = list(top)
        foot = [top[0] + foot_dx_from_top, ground - GB_OFF - r2]
        mid = two_bone(top, foot, l1, l2, pick)
        for k, v in (("top", top), ("mid", mid), ("foot", foot)):
            self.joint(f"{name}_{k}", v)
        toe = None
        if toe_dx is not None:
            toe = [foot[0] + toe_dx, ground - GB_OFF - rf]
            self.joint(f"{name}_toe", toe)
        shade = _shade(col, 0.72 if far else 1.0)
        self.part(f"{name}_u", [(f"{name}_top", f"{name}_mid")], r1, "body", f"{name}_top", z, "leg_u", 1.0, shade, far)
        self.part(f"{name}_l", [(f"{name}_mid", f"{name}_foot")], r2, f"{name}_u", f"{name}_mid", z, "leg_l", 1.0, shade, far)
        fp = None
        if toe:
            fp = f"{name}_f"
            self.part(fp, [(f"{name}_foot", f"{name}_toe")], rf, f"{name}_l", f"{name}_foot", z, "foot", 1.0, shade, far)
        self.lay.legs.append(Leg(name, f"{name}_top", f"{name}_mid", f"{name}_foot", f"{name}_u", f"{name}_l", fp,
                                 f"{name}_toe" if toe else None, phase, pair))
        self.lay.groups[name] = [f"{name}_u", f"{name}_l"] + ([fp] if fp else [])


def layout_biped():
    b = _LB("biped", "biped")
    L = b.lay
    skin, cloth, dark = (156, 128, 96), (120, 84, 70), (98, 72, 60)
    for n, xy in dict(pelvis=(225, 300), neck=(285, 200), head=(325, 158), eye=(336, 152)).items():
        b.joint(n, xy)
    b.part("body", [("pelvis", "neck")], 54, None, None, 5, "body", 0, cloth)
    b.part("head", [("neck", "head")], 40, "body", "neck", 6, "head", 1.0, skin)
    L.head_part, L.eye = "head", "eye"
    arms = {"near": dict(sh=(292, 228), el=(312, 318), wr=(338, 398), hd=(346, 424), z=9, far=False),
            "far": dict(sh=(300, 232), el=(376, 300), wr=(404, 376), hd=(412, 402), z=1, far=True)}
    for s, a in arms.items():
        for k, v in (("shoulder", a["sh"]), ("elbow", a["el"]), ("wrist", a["wr"]), ("hand", a["hd"])):
            b.joint(f"{s}_{k}", v)
        col = _shade(skin, 0.75 if a["far"] else 1.0)
        b.part(f"{s}_arm_u", [(f"{s}_shoulder", f"{s}_elbow")], 17, "body", f"{s}_shoulder", a["z"], "arm_u", 1.0, col, a["far"])
        b.part(f"{s}_arm_f", [(f"{s}_elbow", f"{s}_wrist"), (f"{s}_wrist", f"{s}_hand")], 14, f"{s}_arm_u", f"{s}_elbow",
               a["z"], "arm_f", 1.0, col, a["far"])
        L.groups[f"{s}_arm"] = [f"{s}_arm_u", f"{s}_arm_f"]
    b.leg("near_leg", (240, 318), 30, 86, 80, "fwd", 22, 13, 8, 0.0, "all", 471, dark, False, toe_dx=48)
    b.leg("far_leg", (216, 318), -30, 86, 80, "fwd", 22, 13, 2, 0.5, "all", 471, dark, True, toe_dx=48)
    L.sentence = ("a hunched two-legged creature: a heavy torso leaning forward, the head low and forward with a clear eye, "
                  "long arms hanging to the knees, two legs, a foot with toes pointing right on each")
    L.separation = ("both arms hang clear of the torso with background between hand and body; the far arm and far leg are "
                    "drawn a little behind the near ones and not touching them; legs apart; feet flat on one ground line")
    return L


def layout_quadruped():
    b = _LB("quadruped", "quadruped")
    L = b.lay
    fur, dark = (150, 112, 80), (118, 88, 64)
    for n, xy in dict(rump=(165, 235), chest=(320, 235), neck=(355, 205), head=(400, 195), nose=(450, 212), eye=(416, 194),
                      tail_base=(112, 218), tail_mid=(62, 190), tail_tip=(26, 196)).items():
        b.joint(n, xy)
    b.part("body", [("rump", "chest")], 62, None, None, 5, "body", 0, fur)
    b.part("head", [("neck", "head"), ("head", "nose")], 34, "body", "neck", 6, "head", 1.0, _shade(fur, 1.1))
    b.part("tail_a", [("tail_base", "tail_mid")], 14, "body", "tail_base", 4, "tail", 1.0, dark)
    b.part("tail_b", [("tail_mid", "tail_tip")], 10, "tail_a", "tail_mid", 4, "tail", 1.0, dark)
    L.head_part, L.eye = "head", "eye"
    for name, x, pick, z, far, phase, pair in (("front_near", 322, "back", 9, False, 0.0, "front"),
                                               ("front_far", 288, "back", 2, True, 0.5, "front"),
                                               ("back_near", 152, "fwd", 9, False, 0.5, "back"),
                                               ("back_far", 190, "fwd", 2, True, 0.0, "back")):
        dx = 12 if not far else -12
        b.leg(name, (x, 268), dx, 112, 106, pick, 22, 15, z, phase, pair, 471, dark if far else fur, far)
    L.sentence = ("a four-legged animal: body, head with a clear eye, a tail, four legs with the two far legs drawn "
                  "slightly apart from the two near legs")
    L.separation = ("four legs visible, the near and far leg of each end standing apart so no leg hides another; "
                    "tail clear of the legs; head clear of the front legs")
    return L


def layout_crawler_skitter():
    b = _LB("crawler_skitter", "crawler")
    L = b.lay
    col = (96, 70, 96)
    for n, xy in dict(rump=(185, 215), chest=(280, 232), head=(345, 238), eye=(350, 230)).items():
        b.joint(n, xy)
    b.part("body", [("rump", "chest")], 68, None, None, 5, "body", 0, col)
    b.part("head", [("chest", "head")], 36, "body", "chest", 6, "head", 1.0, _shade(col, 1.2))
    L.head_part, L.eye = "head", "eye"
    L.eye_r = 15
    feet = [80, 165, 365, 445]
    for side, far in (("near", False), ("far", True)):
        for i in range(4):
            top = (240 + i * 30 + (10 if far else 0), 268)
            fx = feet[i] + (22 if far else 0)
            phase = 0.0 if (i + far) % 2 == 0 else 0.5
            b.leg(f"{side}{i}", top, fx - top[0], 115, 205, "up", 10, 8, 9 if not far else 2, phase, "all", 471, col, far)
    L.sentence = ("a spider: a round body, a small head with a clear eye, eight thin legs (four near, four far) that "
                  "bend up at the knee and stand on one ground line")
    L.separation = ("the four near legs fan out front and back and do not cross; the four far legs are drawn a little behind "
                    "and shifted so each shows between two near legs")
    return L


def layout_crawler_undulate():
    b = _LB("crawler_undulate", "crawler")
    L = b.lay
    rad = [46, 50, 48, 42, 32]
    col = (120, 100, 70)
    for i in range(5):
        b.joint(f"seg{i}", (405 - 72 * i, 467 - rad[i]))
    b.joint("eye", (427, 467 - rad[0] - 2))
    derive_joints(L.name, L.joints)
    for i in range(5):
        piv = f"bnd{i + 1}" if i < 2 else (f"bnd{i}" if i > 2 else None)
        par = None if i == 2 else (f"seg{i + 1}" if i < 2 else f"seg{i - 1}")
        b.part(f"seg{i}", [(f"bnd{i}", f"bnd{i + 1}")], rad[i], par, piv, 5 + (0.1 if i == 0 else 0), "head" if i == 0 else "seg",
               0.6, _shade(col, 1.0 + 0.08 * (2 - i)))
    L.head_part, L.eye = "seg0", "eye"
    L.sentence = ("a worm-like creature lying along the ground: five round segments in a row, head at the right with a clear "
                  "eye, tail tapering at the left, no legs")
    L.separation = "segments touch but each shows as a separate ring or bulge; nothing sticks out below the belly line"
    return L


def layout_crawler_squash():
    b = _LB("crawler_squash", "crawler")
    L = b.lay
    for n, xy in dict(base=(256, 471), lo=(256, 375), hi=(256, 295), eye=(296, 313)).items():
        b.joint(n, xy)
    b.part("body", [("lo", "hi")], 92, None, "base", 5, "body", 0, (110, 150, 90))
    L.head_part, L.eye = "body", "eye"
    L.sentence = ("a single soft blob creature sitting on the ground: dome-shaped, wider than tall, one clear eye on the right "
                  "side, no limbs")
    L.separation = "one solid mass, nothing detached, flat base on the ground line"
    return L


def layout_flyer_flap():
    b = _LB("flyer_flap", "flyer")
    L = b.lay
    fur = (80, 70, 90)
    for n, xy in dict(rump=(190, 280), chest=(268, 268), head=(330, 244), beak=(390, 256), eye=(344, 244), tail_tip=(105, 310),
                      wing_root=(250, 232), wing_mid=(205, 136), wing_tip=(145, 74),
                      far_wing_root=(272, 228), far_wing_mid=(252, 132), far_wing_tip=(205, 66)).items():
        b.joint(n, xy)
    b.part("body", [("rump", "chest")], 46, None, None, 5, "body", 0, fur)
    b.part("head", [("chest", "head"), ("head", "beak")], 30, "body", "chest", 6, "head", 1.0, _shade(fur, 1.25))
    b.part("tail", [("rump", "tail_tip")], 18, "body", "rump", 4, "tail", 1.0, _shade(fur, 0.9))
    for s, pre, z, far in (("near", "", 9, False), ("far", "far_", 2, True)):
        col = _shade((110, 96, 130), 0.78 if far else 1.0)
        b.part(f"{s}_wing_in", [(f"{pre}wing_root", f"{pre}wing_mid")], 28, "body", f"{pre}wing_root", z, "wing_in", 1.0, col, far)
        b.part(f"{s}_wing_out", [(f"{pre}wing_mid", f"{pre}wing_tip")], 22, f"{s}_wing_in", f"{pre}wing_mid", z, "wing_out", 1.0, col, far)
        L.groups[f"{s}_wing"] = [f"{s}_wing_in", f"{s}_wing_out"]
    L.head_part, L.eye = "head", "eye"
    L.eye_r = 13
    L.sentence = ("a flying creature seen from the side, wings raised up and back: a body, a head with a clear eye and a beak "
                  "or snout, a tail, two wings (the far wing a little behind and ahead of the near one), no legs shown")
    L.separation = "the near wing and the far wing are two separate shapes, the far one shifted forward; wings clear of the head"
    return L


def layout_flyer_orbit():
    b = _LB("flyer_orbit", "flyer")
    L = b.lay
    for n, xy in dict(core_a=(256, 250), core_b=(256, 272), eye=(288, 246)).items():
        b.joint(n, xy)
    b.part("body", [("core_a", "core_b")], 70, None, None, 5, "body", 0, (200, 200, 120))
    for i in range(3):
        a = 2 * math.pi * i / 3
        b.joint(f"orb{i}", (256 + 190 * math.cos(a), 261 + 80 * math.sin(a)))
        b.part(f"orbit{i}", [(f"orb{i}", f"orb{i}")], 24, None, None, 6, "orbit", 0, (230, 170, 80))
        L.orbit.append(f"orbit{i}")
    L.head_part, L.eye = "body", "eye"
    L.sentence = ("a glowing core with one clear eye and three small separate pieces (flames, motes or crystal shards) floating "
                  "around it at different distances, no limbs")
    L.separation = "the three pieces float apart from the core and from each other, none touching the core"
    return L


def layout_floater():
    b = _LB("floater", "floater")
    L = b.lay
    col = (170, 180, 200)
    for n, xy in dict(top=(256, 190), bot=(256, 290), eye=(292, 186), p0=(256, 330), p1=(256, 384), p2=(256, 424)).items():
        b.joint(n, xy)
    for i, (y0, y1) in enumerate([(340, 366), (394, 410), (432, 442)]):
        b.joint(f"h{i}a", (256, y0))
        b.joint(f"h{i}b", (256, y1))
    b.part("body", [("top", "bot")], 82, None, "p0", 5, "body", 0, col)
    for i, r in enumerate([76, 62, 46]):
        b.part(f"hem{i}", [(f"h{i}a", f"h{i}b")], r, "body" if i == 0 else f"hem{i - 1}", f"p{i}", 4.5 - 0.1 * i, "hem", 0.9,
               _shade(col, 0.95 - 0.05 * i))
    L.head_part, L.eye = "body", "eye"
    L.sentence = ("a floating creature with no legs: a rounded head and body in one piece with one clear eye, and a ragged "
                  "hem or tail that tapers downwards below it, in three steps getting narrower")
    L.separation = "the hem is one solid tapering piece (the tool cuts it in three); nothing detached; arms, if any, held close"
    return L


def layout_construct():
    b = _LB("construct", "construct")
    L = b.lay
    for n, xy in dict(base=(256, 471), a=(256, 220), b=(256, 393), lid_a=(256, 142), lid_b=(256, 156), hinge=(190, 160)).items():
        b.joint(n, xy)
    b.part("body", [("a", "b")], 74, None, "base", 5, "body", 0, (140, 100, 70))
    b.part("lid", [("lid_a", "lid_b")], 56, "body", "hinge", 6, "aux", 0.5, (160, 120, 84))
    L.sentence = ("a rigid object standing on the ground (a coffin, a boat, a cluster of swords, a stone statue): one solid "
                  "body and one smaller part on top of it (lid, mast, hilt), no limbs, no head")
    L.separation = "the top part rests on the body with a visible seam; nothing detached; flat base on the ground line"
    return L


LAYOUTS = {"biped": layout_biped, "quadruped": layout_quadruped, "crawler_skitter": layout_crawler_skitter,
           "crawler_undulate": layout_crawler_undulate, "crawler_squash": layout_crawler_squash,
           "flyer_flap": layout_flyer_flap, "flyer_orbit": layout_flyer_orbit, "floater": layout_floater,
           "construct": layout_construct}
DERIVED = {"crawler_undulate": {f"bnd{i}" for i in range(6)}}


def derive_joints(layout_name, joints):
    """Joints the tool computes itself (undulate: the seams between segments)."""
    if layout_name == "crawler_undulate":
        s = [np.array(joints[f"seg{i}"], float) for i in range(5)]
        for i in range(1, 5):
            joints[f"bnd{i}"] = [float(v) for v in (s[i - 1] + s[i]) / 2]
        joints["bnd0"] = [float(v) for v in 2 * s[0] - np.array(joints["bnd1"])]
        joints["bnd5"] = [float(v) for v in 2 * s[4] - np.array(joints["bnd4"])]
    return joints


def make_layout(plan, style):
    return LAYOUTS[LAYOUT_OF[(plan, style)]]()


def user_joints(lay):
    """The joints the art PC supplies (derived ones left out)."""
    skip = DERIVED.get(lay.name, set())
    return {k: v for k, v in lay.joints.items() if k not in skip}


# ---------------------------------------------------------------- the still, cut
def key_out(rgba):
    """Accept a still with its background keyed out, or on flat key colour: RGBA with hard alpha, fringe cleaned."""
    from .intake import clean_key, key_mask
    a = rgba.copy()
    if (a[..., 3] > 0).all():
        from .imgops import components
        lab, sizes = components(key_mask(a, loose=True))
        border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
        for k in border:
            a[lab == k] = 0
    a, _ = clean_key(a)
    return a


def load_still(path):
    return key_out(np.array(Image.open(path).convert("RGBA")))


def _scaled(rgba, s):
    h, w = rgba.shape[:2]
    nw, nh = max(1, round(w * s)), max(1, round(h * s))
    f = rgba.astype(np.float32)
    pm = f[..., :3] * (f[..., 3:4] / 255.0)
    chans = np.dstack([pm, f[..., 3:4]]).astype(np.float32)
    out = np.zeros((nh, nw, 4), np.float32)
    for c in range(4):
        out[..., c] = np.array(Image.fromarray(chans[..., c], "F").resize((nw, nh), Image.BOX))
    al = out[..., 3]
    rgb = np.where(al[..., None] > 0, out[..., :3] / np.maximum(al[..., None], 1e-6) * 255.0, 0)
    res = np.zeros((nh, nw, 4), np.uint8)
    keep = al >= 128
    res[..., :3][keep] = np.clip(rgb[keep], 0, 255).astype(np.uint8)
    res[..., 3][keep] = 255
    return res, nw / w, nh / h


def bbox_long(rgba):
    ys, xs = np.nonzero(rgba[..., 3] > 0)
    return int(max(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1))


def _seg_d(P, a, b):
    a, b = np.array(a, float), np.array(b, float)
    ab = b - a
    n = float(ab @ ab)
    if n < 1e-9:
        return np.hypot(P[:, 0] - a[0], P[:, 1] - a[1])
    t = np.clip(((P - a) @ ab) / n, 0, 1)
    q = a + t[:, None] * ab
    return np.hypot(P[:, 0] - q[:, 0], P[:, 1] - q[:, 1])


def cut_labels(rgba, lay, J, rs, rmul=None):
    """(HxW int label: index into lay.parts, -1 = transparent).  Each opaque pixel goes to the part whose bone it is
    nearest to, measured as distance minus the part's radius (a thick body keeps the belly, a thin leg keeps its own)."""
    ys, xs = np.nonzero(rgba[..., 3] > 0)
    P = np.stack([xs + 0.5, ys + 0.5], 1).astype(float)
    best = np.full(len(P), 1e9)
    who = np.zeros(len(P), int)
    for i, p in enumerate(lay.parts):
        r = p.r * rs * (rmul or {}).get(p.name, 1.0)
        for a, b in p.bones:
            sc = _seg_d(P, J[a], J[b]) - r
            m = sc < best
            best[m], who[m] = sc[m], i
    lab = np.full(rgba.shape[:2], -1, int)
    lab[ys, xs] = who
    return lab


def make_part_images(rgba, lab, lay, J, rs, pad):
    """Per part an RGBA image on the padded work canvas (+ pixels around a pivot are also kept in the parent)."""
    h, w = rgba.shape[:2]
    masks = {p.name: lab == i for i, p in enumerate(lay.parts)}
    yy, xx = np.mgrid[0:h, 0:w]
    for p in lay.parts:
        if p.dup and p.parent and p.pivot:
            px, py = J[p.pivot]
            near = masks[p.name] & (np.hypot(xx + 0.5 - px, yy + 0.5 - py) <= p.dup * p.r * rs)
            masks[p.parent] = masks[p.parent] | near
    imgs = {}
    for p in lay.parts:
        a = np.zeros((h + 2 * pad, w + 2 * pad, 4), np.uint8)
        m = masks[p.name]
        a[pad:pad + h, pad:pad + w][m] = rgba[m]
        imgs[p.name] = Image.fromarray(a, "RGBA")
    return imgs, {k: int(v.sum()) for k, v in masks.items()}


# ---------------------------------------------------------------- the pose engine
def Mt(x, y):
    return np.array([[1, 0, x], [0, 1, y], [0, 0, 1.0]])


def Mr(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1.0]])


def Ms(sx, sy):
    return np.diag([sx, sy, 1.0])


def local(pivot, ang=0.0, dx=0.0, dy=0.0, sx=1.0, sy=1.0):
    return Mt(dx, dy) @ Mt(*pivot) @ Mr(ang) @ Ms(sx, sy) @ Mt(-pivot[0], -pivot[1])


def _ang(v):
    return math.atan2(v[1], v[0])


def gait(p, A, lift, duty=0.5):
    """(foot x offset, foot lift) at phase p: the stance foot runs back linearly, 2A in `duty` of the cycle."""
    p = p % 1.0
    if p < duty:
        return A - 2 * A * (p / duty), 0.0
    u = (p - duty) / (1 - duty)
    return -A + 2 * A * u, lift * math.sin(math.pi * u)


class Geo:
    """A layout at one scale: scaled joints plus the numbers that make the walk correct by construction."""

    def __init__(self, lay, style, J, rs, size):
        self.lay, self.style, self.J, self.rs, self.size = lay, style, J, rs, size
        self.P = PARAMS[style]
        self.A = self.bob = self.lift = self.stride = 0.0
        self.neutral = {}
        if lay.legs:
            self._legs()

    def _legs(self):
        J, P, lay = self.J, self.P, self.lay
        pair_dx = {}
        for g in lay.legs:
            pair_dx.setdefault(g.pair, []).append(J[g.foot][0] - J[g.top][0])
        for g in lay.legs:
            self.neutral[g.name] = J[g.top][0] + float(np.mean(pair_dx[g.pair]))
        Ls = []
        for g in lay.legs:
            l1 = float(np.hypot(*(np.array(J[g.mid]) - J[g.top])))
            l2 = float(np.hypot(*(np.array(J[g.foot]) - J[g.mid])))
            Ls.append(l1 + l2)
        Lm = float(np.mean(Ls))
        self.bob = P["bob"] * Lm
        self.lift = P["lift"] * Lm
        a_max = 1e9
        for g, L_ in zip(lay.legs, Ls):
            dx0 = abs(self.neutral[g.name] - J[g.top][0])
            dy = J[g.foot][1] - J[g.top][1] + self.bob
            room = math.sqrt(max((0.97 * L_) ** 2 - dy * dy, 0)) - dx0
            a_max = min(a_max, room)
        self.A = max(min(P["A"] * Lm, a_max), 0.0)
        self.stride = 4 * self.A                      # travel per cycle (duty 1/2)


def _legs_pose(geo, bodyM, p, pose, feet):
    J, lay = geo.J, geo.lay
    for g in lay.legs:
        ph = (p + g.phase) % 1.0
        gx, up = gait(ph, geo.A, geo.lift)
        top, mid, foot = (np.array(J[g.top]), np.array(J[g.mid]), np.array(J[g.foot]))
        l1, l2 = float(np.linalg.norm(mid - top)), float(np.linalg.norm(foot - mid))
        cross = (mid - top)[0] * (foot - top)[1] - (mid - top)[1] * (foot - top)[0]
        bend = -1.0 if cross > 0 else 1.0
        H = (bodyM @ np.array([top[0], top[1], 1.0]))[:2]
        T = np.array([geo.neutral[g.name] + gx, foot[1] - up])
        d = float(np.linalg.norm(T - H))
        dc = min(max(d, abs(l1 - l2) + 1e-6), l1 + l2 - 1e-6)
        u = (T - H) / max(d, 1e-9)
        alpha = math.acos(max(-1, min(1, (l1 * l1 + dc * dc - l2 * l2) / (2 * l1 * dc)))) * bend
        c, s = u
        ku = np.array([c * math.cos(alpha) - s * math.sin(alpha), s * math.cos(alpha) + c * math.sin(alpha)])
        K = H + ku * l1
        F = H + u * dc                                  # the foot reached (T unless out of reach)
        phi_u, phi_u0 = _ang(K - H), _ang(mid - top)
        a_u = (phi_u - phi_u0) - _ang(bodyM[:2, 0])
        pose[g.upper] = (a_u, 0, 0, 1, 1, None)
        phi_l, phi_l0 = _ang(F - K), _ang(foot - mid)
        pose[g.lower] = ((phi_l - phi_l0) - (phi_u - phi_u0), 0, 0, 1, 1, None)
        if g.footpart:
            pitch = -0.35 * math.sin(math.pi * ((ph - 0.5) / 0.5)) if ph >= 0.5 else 0.0
            pose[g.footpart] = (pitch - (phi_l - phi_l0), 0, 0, 1, 1, None)
        feet[g.name] = (float(F[0]), float(F[1]), bool(up < 1e-9 and d <= l1 + l2 + 1e-6))


TAU = 2 * math.pi


def pose_for(lay, geo, p):
    """-> (pose: part -> (angle, dx, dy, sx, sy, z or None), feet: leg -> (x, y, planted), snap to ground)"""
    P, J, size, st = geo.P, geo.J, geo.size, geo.style
    pose, feet = {}, {}
    snap = False
    if lay.name in ("biped", "quadruped", "crawler_skitter"):
        bob = -geo.bob * (1 - math.cos(2 * TAU * p)) / 2
        pose["body"] = (0, 0, bob, 1, 1, None)
        _legs_pose(geo, Mt(0, bob), p, pose, feet)
        if lay.name == "biped":
            pose["head"] = (0.05 * math.sin(2 * TAU * p), 0, 0, 1, 1, None)
            for s, ph in (("near", 0.0), ("far", 0.5)):
                pose[f"{s}_arm_u"] = (P["arm"] * math.cos(TAU * (p + ph)), 0, 0, 1, 1, None)
                pose[f"{s}_arm_f"] = (-(0.22 + 0.2 * math.sin(TAU * (p + ph) - 1.0)), 0, 0, 1, 1, None)
        elif lay.name == "quadruped":
            pose["head"] = (0.07 * math.sin(2 * TAU * p + 0.8), 0, 0, 1, 1, None)
            pose["tail_a"] = (P["tail"] * 0.6 * math.sin(TAU * p), 0, 0, 1, 1, None)
            pose["tail_b"] = (P["tail"] * 0.7 * math.sin(TAU * p - 1.1), 0, 0, 1, 1, None)
        else:
            pose["head"] = (0.04 * math.sin(2 * TAU * p), 0, 0, 1, 1, None)
    elif lay.name == "crawler_undulate":
        for i in range(5):
            if i != 2:
                pose[f"seg{i}"] = (P["wave"] * math.sin(TAU * p - 0.95 * (2 - i)), 0, 0, 1, 1, None)
        snap = True
    elif lay.name == "crawler_squash":
        sy = 1 - P["squash"] * math.cos(TAU * p)
        pose["body"] = (0, 0, -P["hop"] * size * math.sin(math.pi * p), 1 / sy, sy, None)
    elif lay.name == "flyer_flap":
        a = P["wing"]
        pose["body"] = (0, 0, -size * P["bob"] * math.sin(TAU * p), 1, 1, None)
        for s, lag in (("near", 0.0), ("far", 0.25)):
            pose[f"{s}_wing_in"] = (a * math.sin(TAU * p - lag), 0, 0, 1, 1, None)
            pose[f"{s}_wing_out"] = (0.8 * a * math.sin(TAU * p - lag - 0.9), 0, 0, 1, 1, None)
        pose["head"] = (0.08 * math.sin(TAU * p + 0.6), 0, 0, 1, 1, None)
        pose["tail"] = (0.18 * math.sin(TAU * p - 1.3), 0, 0, 1, 1, None)
    elif lay.name == "flyer_orbit":
        bob = size * P["bob"] * math.sin(TAU * p)
        pose["body"] = (0, 0, bob, 1, 1, None)
        cx, cy = J["core_a"][0], (J["core_a"][1] + J["core_b"][1]) / 2
        for i, nm in enumerate(lay.orbit):
            rx, ry = J[f"orb{i}"][0] - cx, J[f"orb{i}"][1] - cy
            ratio = 80.0 / 190.0
            rho = math.hypot(rx, ry / ratio)
            ang = math.atan2(ry / ratio, rx) + TAU * p
            nx, ny = rho * math.cos(ang), rho * ratio * math.sin(ang)
            pose[nm] = (0, nx - rx, ny - ry + bob, 1, 1, 3.0 if math.sin(ang) < 0 else 7.0)
    elif lay.name == "floater":
        sw = P["sway"]
        pose["body"] = (sw * math.sin(TAU * p), 0, -size * P["bob"] * math.sin(TAU * p + 0.5), 1, 1, None)
        for i in range(3):
            pose[f"hem{i}"] = (0.9 * sw * math.sin(TAU * p - 1.0 * (i + 1)), 0, 0, 1, 1, None)
    elif lay.name == "construct":
        if st == "hop":
            pose["body"] = (P["tilt"] * math.sin(TAU * p), 0, -P["hop"] * size * 4 * p * (1 - p), 1, 1, None)
        else:
            pose["body"] = (P["rock"] * math.sin(TAU * p), 0, 0, 1, 1, None)
            snap = True
        pose["lid"] = (0.14 * (1 - math.cos(TAU * p)) / 2 * (1 if st == "hop" else 0.5), 0, 0, 1, 1, None)
    return pose, feet, snap


def world_matrices(lay, J, pose):
    M = {}
    parts = {p.name: p for p in lay.parts}

    def get(n):
        if n in M:
            return M[n]
        p = parts[n]
        ang, dx, dy, sx, sy, _ = pose.get(n, (0, 0, 0, 1, 1, None))
        piv = J[p.pivot] if p.pivot else J[p.bones[0][0]]
        base = get(p.parent) if p.parent else np.eye(3)
        M[n] = base @ local(piv, ang, dx, dy, sx, sy)
        return M[n]
    for p in lay.parts:
        get(p.name)
    return M


# ---------------------------------------------------------------- the bake
@dataclass
class Baked:
    n: int
    size: int
    frames: list              # n dicts: rgba, label, meta
    closing: dict             # the frame after the last (must equal frames[0])
    meta: dict


def render(lay, imgs, J, pose, wsize):
    M = world_matrices(lay, J, pose)
    W, H = wsize
    out = np.zeros((H, W, 4), np.uint8)
    lab = np.full((H, W), -1, int)
    order = sorted(range(len(lay.parts)), key=lambda i: ((pose.get(lay.parts[i].name) or (0,) * 6)[5] or lay.parts[i].z, i))
    own, bottom = {}, {}
    for i in order:
        p = lay.parts[i]
        inv = np.linalg.inv(M[p.name])
        a = np.array(imgs[p.name].transform((W, H), Image.AFFINE, tuple(inv[:2].flatten()), resample=Image.NEAREST))
        m = a[..., 3] > 0
        own[p.name] = int(m.sum())
        rows = np.nonzero(m.any(1))[0]
        bottom[p.name] = int(rows.max()) if len(rows) else None
        out[m] = a[m]
        lab[m] = i
    return out, lab, own, bottom


def bake_set(lay, style, rgba, data, size_px, speed, scale_key, ns=(8, 4)):
    """Bake one still at one hero scale (112 or 56): {n: Baked}."""
    target = size_px * scale_key / 112.0
    img, fx, fy = _scaled(rgba, target / bbox_long(rgba))
    rs = (fx + fy) / 2
    J = {k: [v[0] * fx, v[1] * fy] for k, v in data["joints"].items()}
    derive_joints(lay.name, J)
    names = [p.name for p in lay.parts]
    rmul = {k: v / lay.part(k).r for k, v in (data.get("radius") or {}).items() if k in names}
    lab = cut_labels(img, lay, J, rs, rmul)
    pad = int(0.6 * target) + 4
    imgs, areas = make_part_images(img, lab, lay, J, rs, pad)
    Jp = {k: [v[0] + pad, v[1] + pad] for k, v in J.items()}
    wsize = (img.shape[1] + 2 * pad, img.shape[0] + 2 * pad)
    geo = Geo(lay, style, Jp, rs, target)
    ground = data["ground_y"] * fy + pad
    raw = {}
    for n in ns:
        fr = []
        for k in range(n + 1):
            pose, feet, snap = pose_for(lay, geo, k / n)
            out, lb, own, bottom = render(lay, imgs, Jp, pose, wsize)
            dy = 0
            if snap:
                rows = np.nonzero((out[..., 3] > 0).any(1))[0]
                dy = int(round(ground - 1 - rows.max())) if len(rows) else 0
                if dy:
                    out, lb = np.roll(out, dy, 0), np.roll(lb, dy, 0)
                    bottom = {a: (b + dy if b is not None else None) for a, b in bottom.items()}
            fr.append(dict(rgba=out, label=lb, own=own, bottom=bottom,
                           feet={a: (x, y + dy, pl) for a, (x, y, pl) in feet.items()}))
        raw[n] = fr
    al = np.zeros(wsize[::-1], bool)
    for n in ns:
        for f in raw[n]:
            al |= f["rgba"][..., 3] > 0
    ys, xs = np.nonzero(al)
    x0, x1 = max(xs.min() - 2, 0), min(xs.max() + 3, wsize[0])
    y0, y1 = max(ys.min() - 2, 0), min(ys.max() + 3, wsize[1])
    anchor = [float(np.median([Jp[g.foot][0] for g in lay.legs]) - x0) if lay.legs else float(256 + pad - x0),
              float(ground - y0)]
    res = {}
    for n in ns:
        frames = []
        for f in raw[n]:
            lb_c = f["label"][y0:y1, x0:x1]
            meta = dict(labels=names, area=f["own"], visible={nm: int((lb_c == i).sum()) for i, nm in enumerate(names)},
                        bottom={a: (b - y0 if b is not None else None) for a, b in f["bottom"].items()},
                        feet={a: (x - x0, y - y0, pl) for a, (x, y, pl) in f["feet"].items()})
            frames.append(dict(rgba=f["rgba"][y0:y1, x0:x1].copy(), label=lb_c.copy(), meta=meta))
        stride = float(geo.stride)
        bm = dict(plan=lay.plan, layout=lay.name, style=style, size=scale_key, n=n, frame_w=int(x1 - x0), frame_h=int(y1 - y0),
                  ground_row=float(ground - y0), anchor=anchor, size_x=scale_key / 56.0, size_px=size_px,
                  target=float(target), stride_px=stride, travel_per_frame=stride / n, speed_px_s=speed,
                  cycles_per_s=(speed / (stride * 112.0 / scale_key) if stride else None),
                  parts=names, area_tol=geo.P["tol"], has_legs=bool(lay.legs), head_part=lay.head_part,
                  limb_groups=lay.groups, orbit=lay.orbit, legs=[g.name for g in lay.legs],
                  leg_parts={g.name: lay.groups[g.name] for g in lay.legs}, eye_joint=lay.eye, part_areas=areas,
                  half_stride=float(geo.A))
        res[n] = Baked(n, scale_key, frames[:n], frames[n], bm)
    return res


def resolve(data):
    """-> ((layout, style, size_px, speed) or None, [error strings]) for a joints JSON."""
    errs = []
    plan, style = data.get("plan"), data.get("style")
    if data.get("format") != FORMAT:
        errs.append('"format" must be "monster"')
    if plan not in STYLES:
        errs.append(f'"plan" must be one of {sorted(STYLES)}')
        return None, errs
    style = style or STYLES[plan][0]
    if style not in STYLES[plan]:
        errs.append(f'"style" for {plan} must be one of {STYLES[plan]}')
        return None, errs
    row = kind_row(data.get("kind", ""))
    size = data.get("size_px") or (row["size_px"] if row else None)
    speed = data.get("speed") or (row["speed"] if row else 40)
    if not size:
        errs.append('"kind" is not one of the 42 and no "size_px" given')
        return None, errs
    return (make_layout(plan, style), style, size, speed), errs


def bake_monster(png, js):
    """-> ({(n, size): Baked}, still gate fails [(rule, text)], still rgba, data).  A failed still is not baked."""
    from . import monster_checks as mc
    with open(js) as f:
        data = json.load(f)
    rgba = load_still(png)
    r, errs = resolve(data)
    if r is None:
        return {}, [("M12", e) for e in errs], rgba, data
    lay, style, size, speed = r
    fails = mc.gate_still(rgba, data, lay)
    if fails:
        return {}, fails, rgba, data
    out = {}
    for sc in SIZES:
        for n, b in bake_set(lay, style, rgba, data, size, speed, sc).items():
            out[(n, sc)] = b
    return out, [], rgba, data

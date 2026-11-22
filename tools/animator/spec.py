"""The pose a still must be drawn in (STILL_SPEC.md), as data.

    python3 -m tools.animator spec --build human|elf|dwarf|orc --out DIR

writes, per build:
  <build>_pose.png        the pose layout picture: coloured limb skeleton on black, the kind an
                          image model's pose control reads (one colour per bone, dots on joints)
  <build>_joints.json     the same joints in the layout format the batch reads next to a still
                          (samples/stills/*.json), plus the canvas, ground line and limb widths
  <build>_reference.png   a flat-colour mannequin drawn exactly on the spec (what "fits the
                          rig" looks like; tests/test_spec.py checks it passes every G rule)

Every number is a fraction of the body height BH (ground line to the top of the head), measured
up from the ground line (y) and forward from the pelvis (x, + = the facing side, right).
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

CANVAS = (384, 448)       # px, every build; the figure stands on GROUND_Y, pelvis on PELVIS_X
GROUND_Y = 428
PELVIS_X = 176
STEP = 0.26               # heel to heel, x BH: the walk's stride is fitted to twice this

# per build: body height in px on the canvas, joint heights (x BH above the ground), bone
# lengths, foot length and limb half-widths (x BH).  The foot is 0.29-0.31 of the leg (hip to
# ankle) for human, elf and orc and 0.58 for the dwarf (full-size boots under short legs); in
# every build it is longer than the shin is wide by a clear margin, which is what rule R6 needs.  Humans from Drillis & Contini 1966 segment lengths,
# rounded to the chunky proportions of the game's sprites (head 0.19 BH); elf = longer legs,
# smaller head, thinner limbs; dwarf = big head, long trunk, short thick legs; orc = human
# heights with heavier limbs and a deeper chest.
BUILDS = {
    "human": {"foot": 0.120, "bh": 390, "neck": 0.81, "shoulder": 0.76, "pelvis": 0.47, "hip": 0.45, "ankle": 0.055,
              "upper": 0.165, "fore": 0.145, "hand": 0.055,
              "r_thigh": 0.050, "r_shin": 0.036, "r_arm": 0.034, "r_fore": 0.030,
              "chest": (0.085, 0.085), "head": (0.085, 0.095)},
    "elf": {"foot": 0.115, "bh": 400, "neck": 0.83, "shoulder": 0.785, "pelvis": 0.50, "hip": 0.48, "ankle": 0.055,
            "upper": 0.165, "fore": 0.150, "hand": 0.055,
            "r_thigh": 0.042, "r_shin": 0.030, "r_arm": 0.028, "r_fore": 0.025,
            "chest": (0.070, 0.070), "head": (0.075, 0.085)},
    # dwarf: 6 of 6 stills drawn on the first layout (foot 0.150, shin half-width 0.048, hip 0.38)
    # were refused by G9, boot shorter than the shin is wide: the image model draws shins about
    # 1.4 x as thick and boots about 0.8 x as long as asked.  The layout now asks for a boot of
    # 0.200 BH under a slimmer shin (0.040) on a slightly longer leg (hip 0.41), so the toe is
    # 0.120 BH ahead of the shin's front edge on the layout (0.054 before) and the boot still
    # passes G9 when the model thickens the shin and shortens the boot by those factors
    # (tests/test_intake.py::TestBoots).
    # 22 Nov, later: with the 0.200 boot (0.58 of the leg, the top of what G9 allows) and "long
    # boots" in the prompt the model overshot to 0.71-0.77 and was refused the other way.  The
    # boot is now the middle of what G9 allows for this layout's shin (boot_range: 0.335-0.60 of
    # the leg): 0.46 of the leg = 0.160 BH, about as long as the shin is tall.  It still passes
    # with the shin drawn 1.4 x as thick, and with the boot drawn up to 1.29 x as long.
    "dwarf": {"foot": 0.160, "bh": 310, "neck": 0.74, "shoulder": 0.685, "pelvis": 0.43, "hip": 0.41, "ankle": 0.065,
              "upper": 0.165, "fore": 0.140, "hand": 0.060,
              "r_thigh": 0.058, "r_shin": 0.040, "r_arm": 0.042, "r_fore": 0.038,
              "chest": (0.115, 0.115), "head": (0.110, 0.130)},
    "orc": {"foot": 0.135, "bh": 420, "neck": 0.81, "shoulder": 0.755, "pelvis": 0.46, "hip": 0.44, "ankle": 0.058,
            "upper": 0.175, "fore": 0.155, "hand": 0.060,
            "r_thigh": 0.058, "r_shin": 0.042, "r_arm": 0.042, "r_fore": 0.036,
            "chest": (0.105, 0.100), "head": (0.085, 0.095)},
}

# the pose, the same for every build (degrees from straight down, + = forward)
NEAR_THIGH, NEAR_KNEE = 22.0, 10.0      # near (front) leg: forward, knee slightly bent back
FAR_THIGH, FAR_KNEE = -12.0, 10.0       # far (back) leg: behind, knee slightly bent back
NEAR_UPPER, NEAR_ELBOW = 34.0, 18.0     # near arm: hanging forward of the chest, elbow a little bent
ARM_GAP = 0.012                         # x BH of clear background between the forearm and the body

BONE_COLOURS = {      # pose picture: one colour per bone (OpenPose-style)
    "head": (255, 0, 85), "spine": (255, 0, 0), "near_upper": (255, 170, 0), "near_fore": (255, 255, 0),
    "near_hand": (170, 255, 0), "near_thigh": (0, 255, 0), "near_shin": (0, 255, 170),
    "near_foot": (0, 255, 255), "far_thigh": (0, 85, 255), "far_shin": (0, 0, 255),
    "far_foot": (85, 0, 255), "far_upper": (170, 0, 255), "far_fore": (255, 0, 255),
}


def _dir(deg):
    r = math.radians(deg)
    return np.array([math.sin(r), math.cos(r)])


def joints(build):
    """Joint positions on the canvas for one build: dict name -> [x, y] px."""
    b = BUILDS[build]
    bh = b["bh"]
    P = lambda fx, fy: np.array([PELVIS_X + fx * bh, GROUND_Y - fy * bh])
    J = {"head_top": P(0.0, 1.0), "neck": P(0.0, b["neck"]), "pelvis": P(0.0, b["pelvis"]),
         "near_shoulder": P(-0.01, b["shoulder"]), "near_hip": P(0.0, b["hip"]),
         "far_hip": P(-0.02, b["hip"])}
    J["head"] = (J["head_top"] + J["neck"]) / 2
    leg = (b["hip"] - b["ankle"]) * bh
    # legs: thigh and shin lengths that put the ankle exactly ankle-height above the ground
    for side, th, kn in (("near", NEAR_THIGH, NEAR_KNEE), ("far", FAR_THIGH, FAR_KNEE)):
        a, c = math.cos(math.radians(th)), math.cos(math.radians(th - kn))
        seg = leg / (a + c)                      # thigh = shin
        J[side + "_knee"] = J[side + "_hip"] + seg * _dir(th)
        J[side + "_ankle"] = J[side + "_knee"] + seg * _dir(th - kn)
        flen = b["foot"] * bh
        back = b["r_shin"] * bh
        J[side + "_heel"] = np.array([J[side + "_ankle"][0] - back, GROUND_Y])
        J[side + "_toe"] = J[side + "_heel"] + [flen, 0.0]
    # the far foot is moved so that heel to heel is exactly STEP (the stride the walk copies)
    shift = J["near_heel"][0] - STEP * bh - J["far_heel"][0]
    for k in ("far_ankle", "far_heel", "far_toe"):
        J[k] = J[k] + [shift, 0.0]
    seg_t = float(np.hypot(*(J["far_knee"] - J["far_hip"])))
    d = J["far_ankle"] - J["far_hip"]
    L = float(np.hypot(*d))
    seg = max(seg_t, L / 2 + 1e-6)               # equal thigh and shin reaching that ankle
    mid = J["far_hip"] + d / 2
    off = math.sqrt(max(seg * seg - (L / 2) ** 2, 0.0))
    nrm = np.array([d[1], -d[0]]) / L            # knee on the forward side: bends back only
    J["far_knee"] = mid + nrm * off * (1 if nrm[0] > 0 else -1)
    # near arm
    J["near_elbow"] = J["near_shoulder"] + b["upper"] * bh * _dir(NEAR_UPPER)
    J["near_wrist"] = J["near_elbow"] + b["fore"] * bh * _dir(NEAR_UPPER + NEAR_ELBOW)
    J["near_hand_tip"] = J["near_wrist"] + b["hand"] * bh * _dir(NEAR_UPPER + NEAR_ELBOW)
    # far arm: hidden behind the torso, hanging straight down (never drawn)
    J["far_shoulder"] = J["near_shoulder"] + [-0.025 * bh, 0.0]
    J["far_elbow"] = J["far_shoulder"] + b["upper"] * bh * _dir(0.0)
    J["far_wrist"] = J["far_elbow"] + b["fore"] * bh * _dir(8.0)
    return {k: [round(float(v[0]), 1), round(float(v[1]), 1)] for k, v in J.items()}


def fractions(build):
    """The same joints as fractions of BH: x forward of the pelvis, y above the ground."""
    b = BUILDS[build]
    return {k: [round((v[0] - PELVIS_X) / b["bh"], 3), round((GROUND_Y - v[1]) / b["bh"], 3)]
            for k, v in joints(build).items()}


def layout(build):
    """The joints JSON that goes next to a still drawn on this spec (batch layout format)."""
    b = BUILDS[build]
    J = joints(build)
    keys = ["head", "neck", "pelvis"] + [s + "_" + k for s in ("near", "far")
                                         for k in ("shoulder", "elbow", "wrist", "hip", "knee", "ankle", "toe")]
    return {
        "id": "SPEC_" + build, "name": "spec_" + build, "build": build, "facing": "right",
        "ground_y": GROUND_Y, "size": list(CANVAS), "body_height": b["bh"],
        "stride_px": round(2 * STEP * b["bh"], 1),
        "joints": {k: J[k] for k in keys},
        "extra_joints": {k: J[k] for k in ("head_top", "near_hand_tip", "near_heel", "far_heel")},
        "fractions_of_body_height": fractions(build),
        "foot": foot_numbers(build),
        "half_widths_px": {k[2:]: round(b[k] * b["bh"], 1) for k in ("r_thigh", "r_shin", "r_arm", "r_fore")},
        "far_arm": "hidden",
        "format": "body",       # the still is the bare body; gear comes as <id>_gear/*.png + .json
        "chest_px": [round(b["chest"][0] * b["bh"], 1), round(b["chest"][1] * b["bh"], 1)],
        "note": "drawn from tools/animator/spec.py: joints are known, not detected (STILL_SPEC.md)",
    }


def _bones(J):
    return [("far_upper", "far_shoulder", "far_elbow"), ("far_fore", "far_elbow", "far_wrist"),
            ("far_thigh", "far_hip", "far_knee"), ("far_shin", "far_knee", "far_ankle"),
            ("far_foot", "far_heel", "far_toe"), ("spine", "pelvis", "neck"), ("head", "neck", "head_top"),
            ("near_thigh", "near_hip", "near_knee"), ("near_shin", "near_knee", "near_ankle"),
            ("near_foot", "near_heel", "near_toe"), ("near_upper", "near_shoulder", "near_elbow"),
            ("near_fore", "near_elbow", "near_wrist"), ("near_hand", "near_wrist", "near_hand_tip")]


def pose_picture(build):
    """Coloured limb skeleton on black (RGB)."""
    J = joints(build)
    im = Image.new("RGB", CANVAS, (0, 0, 0))
    d = ImageDraw.Draw(im)
    w = max(4, int(0.012 * BUILDS[build]["bh"]))
    for name, a, c in _bones(J):
        d.line([tuple(J[a]), tuple(J[c])], fill=BONE_COLOURS[name], width=w)
    for name, a, c in _bones(J):
        for p in (J[a], J[c]):
            d.ellipse([p[0] - w * 0.7, p[1] - w * 0.7, p[0] + w * 0.7, p[1] + w * 0.7], fill=(255, 255, 255))
    d.line([(0, GROUND_Y), (CANVAS[0], GROUND_Y)], fill=(90, 90, 90), width=1)
    return im


def _capsule(d, a, c, r, fill, outline=(16, 14, 14, 255), ow=2):
    for rr, col in ((r + ow, outline), (r, fill)):
        d.line([tuple(a), tuple(c)], fill=col, width=int(round(2 * rr)))
        for p in (a, c):
            d.ellipse([p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr], fill=col)


def reference(build):
    """A flat-colour mannequin drawn exactly on the spec (RGBA, transparent ground)."""
    b = BUILDS[build]
    bh = b["bh"]
    J = {k: np.array(v) for k, v in joints(build).items()}
    im = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    ink = (16, 14, 14, 255)
    cloth, cloth_far = (112, 62, 48, 255), (70, 40, 34, 255)
    trouser, trouser_far = (72, 78, 104, 255), (46, 50, 68, 255)
    boot, boot_far = (120, 78, 44, 255), (78, 50, 30, 255)
    skin = (226, 172, 132, 255)
    sleeve = (150, 150, 160, 255)

    def boot_shape(side, col):
        heel, toe, ank = J[side + "_heel"], J[side + "_toe"], J[side + "_ankle"]
        r = b["r_shin"] * bh
        top = ank[1] - 0.2 * r
        pts = [(heel[0], GROUND_Y), (toe[0], GROUND_Y), (toe[0], GROUND_Y - 0.55 * (GROUND_Y - top)),
               (ank[0] + r, top), (heel[0], top)]
        d.polygon(pts, fill=col, outline=ink)
        d.line(pts + [pts[0]], fill=ink, width=2)

    # far leg (behind everything)
    _capsule(d, J["far_hip"], J["far_knee"], b["r_thigh"] * bh, trouser_far)
    _capsule(d, J["far_knee"], J["far_ankle"], b["r_shin"] * bh, trouser_far)
    boot_shape("far", boot_far)
    # near leg
    _capsule(d, J["near_hip"], J["near_knee"], b["r_thigh"] * bh, trouser)
    _capsule(d, J["near_knee"], J["near_ankle"], b["r_shin"] * bh, trouser)
    boot_shape("near", boot)
    # torso: straight front and back lines from the shoulders to just below the hips
    fx, bx = b["chest"][0] * bh, b["chest"][1] * bh
    top, bot = J["neck"][1] - 0.012 * bh, J["near_hip"][1] + 0.045 * bh
    px = J["pelvis"][0]
    tor = [(px - bx, top + 0.03 * bh), (px - 0.6 * bx, top), (px + 0.6 * fx, top), (px + fx, top + 0.03 * bh),
           (px + fx, bot), (px - bx, bot)]
    d.polygon(tor, fill=cloth)
    d.line(tor + [tor[0]], fill=ink, width=3)
    d.rectangle([px - bx, J["near_hip"][1] - 0.012 * bh, px + fx, J["near_hip"][1] + 0.012 * bh], fill=cloth_far)
    # head (no hair or beard past the neck line)
    hx, hy = b["head"][0] * bh, (J["neck"][1] - J["head_top"][1]) / 2
    c = (J["head_top"] + J["neck"]) / 2 + [0.01 * bh, 0]
    d.ellipse([c[0] - hx - 2, c[1] - hy, c[0] + hx + 2, c[1] + hy + 2], fill=ink)
    d.ellipse([c[0] - hx, c[1] - hy + 2, c[0] + hx, c[1] + hy], fill=skin)
    d.pieslice([c[0] - hx, c[1] - hy + 2, c[0] + hx, c[1] + hy], 150, 300, fill=(70, 50, 40, 255))
    # near arm: sleeve, then the bare hand, clear of the chest's front line
    _capsule(d, J["near_shoulder"], J["near_elbow"], b["r_arm"] * bh, sleeve)
    _capsule(d, J["near_elbow"], J["near_wrist"], b["r_fore"] * bh, sleeve)
    _capsule(d, J["near_wrist"], J["near_hand_tip"], b["r_fore"] * bh * 0.95, skin)
    return im


BOOT_RANGE = (0.24, 0.60)   # boot length / leg length (hip to ankle) that G9 accepts (foot.FOOT_LEG[0],
                            # foot.FOOT_LEG_STOCKY), the same for every build


def boot_range(build, shin=1.0):
    """Boot length / leg length that G9 accepts for this build's layout: from the shortest boot
    that is still long enough for the layout's shin width (drawn `shin` x as thick) at every
    ankle angle of the walk, to BOOT_RANGE[1]."""
    from . import foot
    from .motion import STANCE_DORSI_MAX, SWING_ANKLE
    b = BUILDS[build]
    bh = b["bh"]
    leg, ah, half = (b["hip"] - b["ankle"]) * bh, b["ankle"] * bh, shin * b["r_shin"] * bh
    flex = (-min(-SWING_ANKLE[0], foot.plantar_limit(half, ah, 5.5)), STANCE_DORSI_MAX)
    r = BOOT_RANGE[0]
    while r < BOOT_RANGE[1] and foot.foot_faults(r * leg, leg, half, half, ah, flex):
        r += 0.005
    return (round(r, 3), BOOT_RANGE[1])

# what to write in the prompt about the boots, per build: the target stated plainly
BOOT_WORDS = {
    "human": "ordinary ankle boots; each foot about a third as long as the whole leg and clearly "
             "longer than the lower leg is wide",
    "elf": "slim ordinary ankle boots; each foot a little under a third as long as the whole leg and "
           "almost twice as long as the lower leg is wide",
    "dwarf": "ordinary ankle boots, not oversized and not long; each foot about as long as the shin is "
             "tall and twice as long as the lower leg is wide",
    "orc": "ordinary heavy ankle boots; each foot about a third as long as the whole leg and clearly "
           "longer than the lower leg is wide",
}
BOOT_WORDS_ALL = ("the heel of each boot ends straight under the back of the leg, no heel sticking out "
                  "behind; flat soles on the ground line, toes not curled up; boot shafts as narrow as "
                  "the lower leg, no fur cuffs")


def foot_numbers(build):
    """What the layout asks of the boot, for STILL_SPEC.md and the tests: foot length and shin
    width (x BH and px), foot / leg (hip to ankle), and how far the toe is ahead of the shin's
    front edge (x BH and px).  G9 needs the boot at least 0.24 of the leg and longer than the
    shin is wide."""
    b = BUILDS[build]
    leg = b["hip"] - b["ankle"]
    ahead = b["foot"] - 2 * b["r_shin"]
    return {"foot_per_leg_allowed": list(boot_range(build)),
            "foot": b["foot"], "foot_px": round(b["foot"] * b["bh"], 1),
            "shin_width": round(2 * b["r_shin"], 3), "shin_width_px": round(2 * b["r_shin"] * b["bh"], 1),
            "foot_per_leg": round(b["foot"] / leg, 2), "foot_per_shin_width": round(b["foot"] / (2 * b["r_shin"]), 2),
            "toe_ahead": round(ahead, 3), "toe_ahead_px": round(ahead * b["bh"], 1)}


def arm_gap(build):
    """px of clear background between the near forearm (at the wrist) and the torso's front
    line: the spec asks for at least ARM_GAP x BH."""
    b = BUILDS[build]
    J = joints(build)
    front = PELVIS_X + b["chest"][0] * b["bh"]
    return J["near_wrist"][0] - b["r_fore"] * b["bh"] - 2 - front


# ------------------------------------------------------------------ gear layout guides
# kind -> picture size, the box the gear is drawn in (x0, y0, x1, y1), the anchor, and the JSON
# that goes with a gear drawn on the guide.  The gear is drawn upright (up = picture up), alone.
GEAR_GUIDES = {
    "shield": {"size": (256, 320), "box": (28, 20, 228, 300), "anchor": (128, 160),
               "json": {"slot": "back", "anchor": [128, 160], "up": [0, -1], "size": 0.36},
               "words": "a shield seen face-on, upright, filling the box; the anchor is its middle. A shield "
                        "that goes on the back is drawn FACE-ON too: the painted face of the shield with its "
                        "emblem, never its edge or its inside as a dark frame round a hollow middle (it reads "
                        "as a crate)"},
    "one_hand_weapon": {"size": (160, 384), "box": (30, 16, 130, 368), "anchor": (80, 316),
                        "json": {"slot": "near_hand", "anchor": [80, 316], "up": [0, -1], "size": 0.34,
                                 "angle": 110, "in_front": False},
                        "words": "a hammer, sword, axe or mace standing upright, head or point at the top, "
                                 "grip at the bottom; the anchor is the middle of the grip"},
    "two_hand_weapon": {"size": (192, 448), "box": (26, 12, 166, 436), "anchor": (96, 330),
                        "json": {"slot": "near_hand", "anchor": [96, 330], "up": [0, -1], "size": 0.62,
                                 "angle": 115, "in_front": False},
                        "words": "a greatsword, great axe or maul standing upright, head or point at the "
                                 "top; the anchor is where the leading hand grips, a quarter up the haft"},
    # the staff is carried, not planted: gripped a quarter up, so its foot ends above the knees
    # and never crosses a shin (R25)
    "staff": {"size": (128, 448), "box": (34, 8, 94, 440), "anchor": (64, 330),
              "json": {"slot": "near_hand", "anchor": [64, 330], "up": [0, -1], "size": 0.90,
                       "angle": 112, "in_front": False},
              "words": "a staff or spear standing upright, head at the top, at least as thick as the "
                       "marked shaft width; the anchor is the grip, a quarter of the way up"},
    # the bow is carried, not drawn: unstrung, gripped at its middle, held upright; the lower limb
    # ends above the knees (R25)
    "bow": {"size": (128, 448), "box": (24, 8, 104, 440), "anchor": (64, 256),
            "json": {"slot": "near_hand", "anchor": [64, 256], "up": [0, -1], "size": 0.40,
                     "angle": 112, "in_front": False},
            "words": "an unstrung recurve bow or longbow seen side-on, standing upright, one smooth curved "
                     "limb, at least as thick as the marked width (thin limbs break up at 56 px); the anchor is the "
                     "grip, a little below the middle of the bow"},
    "quiver": {"size": (128, 320), "box": (28, 16, 100, 304), "anchor": (64, 130),
               "json": {"slot": "back", "anchor": [64, 130], "up": [0, -1], "size": 0.30, "at": [0.5, 0.10]},
               "words": "a quiver seen from the side, standing upright, wider at the top with a few arrow "
                        "feathers poking out of the top; the anchor is the middle of the strap, where it "
                        "pins to the spine"},
    # ---- pass 10 ----
    # a crossbow is carried level at the hip, muzzle forward and a little down (carry pose "level")
    "crossbow": {"size": (224, 320), "box": (16, 16, 208, 304), "anchor": (112, 232),
                 "json": {"slot": "near_hand", "anchor": [112, 232], "up": [0, -1], "size": 0.30,
                          "angle": 0, "in_front": False, "guide": "crossbow"},
                 "words": "a crossbow seen from the side, drawn upright: the muzzle (the bolt's end) at the top, the "
                          "stock below, the bow across the top third; the anchor is the grip under the stock. In "
                          "the game it is carried level at the hip, muzzle forward and a little down"},
    # a censer hangs on its chain straight down from the hand in every frame, whatever the forearm does
    "censer": {"size": (128, 320), "box": (28, 12, 100, 308), "anchor": (64, 20),
               "json": {"slot": "near_hand", "anchor": [64, 20], "up": [0, -1], "size": 0.30,
                        "angle": 0, "in_front": False, "guide": "censer"},
               "words": "a censer on a chain, hanging: the top of the chain at the top of the box (the anchor, "
                        "where the fingers hold it), a thin chain, the round perforated censer at the bottom. "
                        "In the game it always hangs straight down from the hand"},
    # a book is held closed against the chest, the forearm bent up (carry pose "chest")
    "book": {"size": (192, 224), "box": (24, 16, 168, 208), "anchor": (96, 112),
             "json": {"slot": "near_hand", "anchor": [96, 112], "up": [0, -1], "size": 0.13,
                      "angle": 0, "in_front": True, "guide": "book"},
             "words": "a closed book seen from the side with its spine to the left, standing upright; the anchor "
                      "is the middle of the cover, under the fingers. In the game it is held against the chest, "
                      "the forearm bent up"},
    "scroll": {"size": (96, 288), "box": (16, 16, 80, 272), "anchor": (48, 144),
               "json": {"slot": "near_hand", "anchor": [48, 144], "up": [0, -1], "size": 0.22,
                        "angle": 110, "in_front": False, "guide": "scroll"},
               "words": "a rolled scroll seen from the side, upright, a little thicker than the marked width; "
                        "the anchor is the middle of the roll, where the hand grips it"},
    # a banner on a pole is long gear: carried upright; the cloth stays above head height
    "banner": {"size": (256, 576), "box": (20, 8, 236, 568), "anchor": (64, 456),
               "json": {"slot": "near_hand", "anchor": [64, 456], "up": [0, -1], "size": 1.30,
                        "angle": 112, "in_front": False, "guide": "banner"},
               "words": "a banner on a pole, standing upright: a straight pole, thick as the marked width, with the "
                        "cloth hanging from a crossbar in the top third of the box, facing forward (right); the anchor "
                        "is the grip, a fifth of the way up the pole. The cloth stays above the head in the game"},
    # a halo is pinned above the head, bobs with it, and is drawn behind the head
    "halo": {"size": (256, 96), "box": (16, 8, 240, 88), "anchor": (128, 48),
             "json": {"slot": "head", "anchor": [128, 48], "up": [0, -1], "size": 0.06,
                      "angle": 0, "at": [0.0, 0.02], "guide": "halo"},
             "words": "a halo: a flat glowing ring seen from the side as an ellipse, wider than tall, at least as "
                      "thick as the marked width; the anchor is the middle of the ring. It is drawn behind the head, "
                      "its lower edge hidden by the head, and bobs with it"},
    # a weapon in the far hand: shown in front of the body at hip height, behind the near arm
    "offhand_weapon": {"size": (160, 384), "box": (30, 16, 130, 368), "anchor": (80, 316),
                       "json": {"slot": "far_hand", "anchor": [80, 316], "up": [0, -1], "size": 0.30,
                                "angle": 110, "in_front": True, "guide": "offhand_weapon"},
                       "words": "an off-hand axe, sword or dagger standing upright, head or point at the top, grip "
                                "at the bottom; the anchor is the middle of the grip. In the game it shows in front "
                                "of the body at hip height; only the weapon shows, the far arm stays hidden"},
    "cape": {"size": (224, 384), "box": (24, 16, 200, 368), "anchor": (176, 28),
             "json": {"slot": "cape", "anchor": [176, 28], "up": [0, -1], "size": 0.52},
             "words": "a cape seen from the side, hanging flat and straight down from the shoulder; the "
                      "anchor is its top front corner, where it sits on the shoulder"},
}


def gear_guide(kind):
    """The layout guide for one kind of gear: black picture, the box outlined, the anchor marked
    with a cross and a ring, the up direction with an arrow (RGB)."""
    g = GEAR_GUIDES[kind]
    im = Image.new("RGB", g["size"], (0, 0, 0))
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = g["box"]
    d.rectangle([x0, y0, x1, y1], outline=(0, 255, 255), width=2)
    ax, ay = g["anchor"]
    d.line([(ax - 12, ay), (ax + 12, ay)], fill=(255, 255, 0), width=2)
    d.line([(ax, ay - 12), (ax, ay + 12)], fill=(255, 255, 0), width=2)
    d.ellipse([ax - 7, ay - 7, ax + 7, ay + 7], outline=(255, 0, 0), width=2)
    d.line([(x1 - 10, y0 + 46), (x1 - 10, y0 + 10)], fill=(0, 255, 0), width=2)       # up arrow
    d.polygon([(x1 - 10, y0 + 4), (x1 - 16, y0 + 16), (x1 - 4, y0 + 16)], fill=(0, 255, 0))
    if kind in ("staff", "bow"):                                                     # shaft / limb width
        h = 7 if kind == "staff" else 15
        x = ax if kind == "staff" else x1 - 6
        d.line([(x - h, y1 - 30), (x - h, y1 - 6)], fill=(90, 90, 90), width=1)
        d.line([(x + h, y1 - 30), (x + h, y1 - 6)], fill=(90, 90, 90), width=1)
    return im


def write_gear(out_dir):
    """`spec --gear`: <kind>_guide.png and <kind>.json (the JSON to save beside a gear picture
    drawn on that guide, as <id>_gear/<name>.json) for every kind in GEAR_GUIDES."""
    os.makedirs(out_dir, exist_ok=True)
    paths = {}
    for kind, g in GEAR_GUIDES.items():
        p = os.path.join(out_dir, "gear_" + kind + "_guide.png")
        gear_guide(kind).save(p)
        j = os.path.join(out_dir, "gear_" + kind + ".json")
        with open(j, "w") as f:
            json.dump(dict(g["json"], guide=kind, note=g["words"]), f, indent=1)
        paths[kind] = (p, j)
    return paths


def example_gear(kind):
    """A flat synthetic gear picture drawn on its guide (RGBA): shield, one_hand_weapon (a
    hammer), staff, bow, quiver or cape.  For the tests and the worked example in STILL_SPEC.md."""
    g = GEAR_GUIDES[kind]
    im = Image.new("RGBA", g["size"], (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    ink = (16, 14, 14, 255)
    x0, y0, x1, y1 = g["box"]
    ax, ay = g["anchor"]
    if kind == "shield":
        pts = [(x0, y0), (x1, y0), (x1, y0 + 150), (ax, y1), (x0, y0 + 150)]
        d.polygon(pts, fill=(196, 150, 40, 255))
        d.line(pts + [pts[0]], fill=ink, width=8)
        inner = [(x0 + 22, y0 + 22), (x1 - 22, y0 + 22), (x1 - 22, y0 + 140), (ax, y1 - 34), (x0 + 22, y0 + 140)]
        d.polygon(inner, fill=(36, 44, 110, 255))
        d.ellipse([ax - 26, ay - 46, ax + 26, ay + 6], fill=(230, 200, 70, 255))
    elif kind in ("one_hand_weapon", "two_hand_weapon"):
        d.rectangle([ax - 9, y0 + 40, ax + 9, y1], fill=ink)                 # haft
        d.rectangle([ax - 5, y0 + 40, ax + 5, y1 - 4], fill=(122, 84, 48, 255))
        d.rectangle([x0, y0, x1, y0 + 78], fill=ink)                          # head
        d.rectangle([x0 + 6, y0 + 6, x1 - 6, y0 + 72], fill=(150, 154, 166, 255))
        d.rectangle([x0 + 6, y0 + 6, x1 - 6, y0 + 22], fill=(200, 204, 214, 255))
    elif kind == "staff":
        d.rectangle([ax - 9, y0 + 30, ax + 9, y1], fill=ink)
        d.rectangle([ax - 5, y0 + 30, ax + 5, y1 - 4], fill=(122, 84, 48, 255))
        d.ellipse([ax - 24, y0, ax + 24, y0 + 48], fill=ink)
        d.ellipse([ax - 18, y0 + 6, ax + 18, y0 + 42], fill=(90, 190, 220, 255))
    elif kind == "bow":
        wood, hi = (122, 84, 48, 255), (170, 124, 76, 255)
        for col, w in ((ink, 30), (wood, 20), (hi, 5)):
            pts = []
            for k in range(41):
                t = k / 40
                y = y0 + 8 + t * (y1 - y0 - 16)
                x = x1 - 6 - (1 - (2 * t - 1) ** 2) * 34           # the belly of the bow is at the grip
                pts.append((x if col is not hi else x - 1, y))
            d.line(pts, fill=col, width=w, joint="curve")
        d.rectangle([ax - 18, ay - 26, ax + 18, ay + 26], fill=ink)         # grip wrap
        d.rectangle([ax - 14, ay - 22, ax + 14, ay + 22], fill=(70, 50, 36, 255))
    elif kind == "quiver":
        for i, (dx, c) in enumerate(((-12, (200, 60, 50, 255)), (0, (230, 230, 220, 255)), (12, (200, 60, 50, 255)))):
            d.rectangle([ax + dx - 5, y0, ax + dx + 5, y0 + 40], fill=ink)
            d.rectangle([ax + dx - 3, y0 + 2, ax + dx + 3, y0 + 40], fill=c)
        d.polygon([(x0 + 6, y0 + 36), (x1 - 6, y0 + 36), (x1 - 18, y1), (x0 + 18, y1)], fill=ink)
        d.polygon([(x0 + 12, y0 + 42), (x1 - 12, y0 + 42), (x1 - 24, y1 - 8), (x0 + 24, y1 - 8)], fill=(104, 66, 40, 255))
        d.rectangle([x0 + 8, y0 + 100, x1 - 8, y0 + 114], fill=(190, 150, 60, 255))
    elif kind == "crossbow":
        d.rectangle([ax - 10, y0 + 30, ax + 10, y1], fill=ink)                 # stock
        d.rectangle([ax - 6, y0 + 30, ax + 6, y1 - 4], fill=(122, 84, 48, 255))
        d.rectangle([x0, y0 + 60, x1, y0 + 92], fill=ink)                       # prod (the bow)
        d.rectangle([x0 + 6, y0 + 66, x1 - 6, y0 + 86], fill=(150, 154, 166, 255))
        d.rectangle([ax - 3, y0, ax + 3, y0 + 60], fill=(200, 204, 214, 255))   # bolt
    elif kind == "censer":
        d.line([(ax, ay), (ax, y1 - 90)], fill=ink, width=14)                   # chain
        d.line([(ax, ay), (ax, y1 - 90)], fill=(190, 150, 60, 255), width=6)
        d.ellipse([x0, y1 - 96, x1, y1], fill=ink)
        d.ellipse([x0 + 8, y1 - 88, x1 - 8, y1 - 8], fill=(190, 150, 60, 255))
        d.ellipse([ax - 10, y1 - 60, ax + 10, y1 - 38], fill=ink)
    elif kind == "book":
        d.rectangle([x0, y0, x1, y1], fill=ink)
        d.rectangle([x0 + 8, y0 + 8, x1 - 8, y1 - 8], fill=(120, 40, 50, 255))
        d.rectangle([x0 + 8, y0 + 8, x0 + 30, y1 - 8], fill=(86, 28, 36, 255))
        d.rectangle([ax - 20, ay - 30, ax + 30, ay + 30], fill=(214, 176, 70, 255))
    elif kind == "scroll":
        d.rectangle([x0, y0, x1, y1], fill=ink)
        d.rectangle([x0 + 8, y0 + 8, x1 - 8, y1 - 8], fill=(226, 212, 168, 255))
        d.rectangle([x0 - 2, y0 + 20, x1 + 2, y0 + 40], fill=(122, 84, 48, 255))
        d.rectangle([x0 - 2, y1 - 40, x1 + 2, y1 - 20], fill=(122, 84, 48, 255))
    elif kind == "banner":
        d.rectangle([ax - 9, y0 + 20, ax + 9, y1], fill=ink)
        d.rectangle([ax - 5, y0 + 20, ax + 5, y1 - 4], fill=(122, 84, 48, 255))
        d.rectangle([ax - 9, y0 + 20, x1, y0 + 40], fill=ink)                   # crossbar
        d.polygon([(ax + 6, y0 + 40), (x1 - 8, y0 + 40), (x1 - 8, y0 + 190), (ax + 70, y0 + 160), (ax + 6, y0 + 190)],
                  fill=(170, 30, 40, 255))
        d.line([(ax + 6, y0 + 40), (x1 - 8, y0 + 40), (x1 - 8, y0 + 190), (ax + 70, y0 + 160), (ax + 6, y0 + 190),
                (ax + 6, y0 + 40)], fill=ink, width=5)
        d.ellipse([ax - 16, y0, ax + 16, y0 + 32], fill=(214, 176, 70, 255))
    elif kind == "halo":
        d.ellipse([x0, y0, x1, y1], fill=ink)
        d.ellipse([x0 + 4, y0 + 4, x1 - 4, y1 - 4], fill=(250, 226, 110, 255))
        d.ellipse([x0 + 24, y0 + 22, x1 - 24, y1 - 22], fill=ink)
        d.ellipse([x0 + 28, y0 + 26, x1 - 28, y1 - 26], fill=(0, 0, 0, 0))
    elif kind == "offhand_weapon":
        d.rectangle([ax - 9, y0 + 40, ax + 9, y1], fill=ink)
        d.rectangle([ax - 5, y0 + 40, ax + 5, y1 - 4], fill=(122, 84, 48, 255))
        d.polygon([(ax - 6, y0 + 60), (x1, y0 + 20), (x1, y0 + 120), (ax - 6, y0 + 96)], fill=ink)
        d.polygon([(ax - 2, y0 + 64), (x1 - 8, y0 + 32), (x1 - 8, y0 + 110), (ax - 2, y0 + 92)], fill=(150, 154, 166, 255))
    elif kind == "cape":
        pts = [(ax, ay - 8), (ax - 60, ay), (x0, y1), (x0 + 110, y1), (ax, ay + 60)]
        d.polygon(pts, fill=(120, 30, 40, 255))
        d.line(pts + [pts[0]], fill=ink, width=6)
    return im


def write_example(out_dir, cid="PAL_SYN", build="human", gear=(("shield", "shield"), ("hammer", "one_hand_weapon"))):
    """The worked example of STILL_SPEC.md as files: the mannequin of `build` as the bare body
    (<cid>.png, <cid>.json) with synthetic gear pictures in <cid>_gear/ (name, guide kind)."""
    os.makedirs(os.path.join(out_dir, cid + "_gear"), exist_ok=True)
    png = os.path.join(out_dir, cid + ".png")
    reference(build).save(png)
    with open(os.path.join(out_dir, cid + ".json"), "w") as f:
        json.dump(dict(layout(build), id=cid, name=cid), f, indent=1)
    for name, kind in gear:
        example_gear(kind).save(os.path.join(out_dir, cid + "_gear", name + ".png"))
        with open(os.path.join(out_dir, cid + "_gear", name + ".json"), "w") as f:
            json.dump(GEAR_GUIDES[kind]["json"], f, indent=1)
    return png


def write(build, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    paths = {"pose": os.path.join(out_dir, build + "_pose.png"),
             "joints": os.path.join(out_dir, build + "_joints.json"),
             "reference": os.path.join(out_dir, build + "_reference.png")}
    pose_picture(build).save(paths["pose"])
    with open(paths["joints"], "w") as f:
        json.dump(layout(build), f, indent=1)
    reference(build).save(paths["reference"])
    return paths

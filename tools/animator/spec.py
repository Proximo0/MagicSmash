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
# ankle) for human, elf and orc and 0.48 for the dwarf (full-size boots under short legs); in
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
    "dwarf": {"foot": 0.150, "bh": 310, "neck": 0.74, "shoulder": 0.685, "pelvis": 0.40, "hip": 0.38, "ankle": 0.065,
              "upper": 0.165, "fore": 0.140, "hand": 0.060,
              "r_thigh": 0.062, "r_shin": 0.048, "r_arm": 0.042, "r_fore": 0.038,
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
        "half_widths_px": {k[2:]: round(b[k] * b["bh"], 1) for k in ("r_thigh", "r_shin", "r_arm", "r_fore")},
        "far_arm": "hidden",
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


def arm_gap(build):
    """px of clear background between the near forearm (at the wrist) and the torso's front
    line: the spec asks for at least ARM_GAP x BH."""
    b = BUILDS[build]
    J = joints(build)
    front = PELVIS_X + b["chest"][0] * b["bh"]
    return J["near_wrist"][0] - b["r_fore"] * b["bh"] - 2 - front


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

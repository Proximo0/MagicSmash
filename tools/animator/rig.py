"""Side-view humanoid skeleton: bones, joint limits, forward kinematics, JSON I/O.

Coordinates are image pixels, x right, y DOWN. The character faces +x (right).

Angle conventions (degrees), all "absolute" angles are measured in the picture:
  * limb angle  a: direction of a hanging bone (shoulder->elbow, hip->knee, ...);
    0 = straight down, positive = swung FORWARD (toward +x).  dir = (sin a, cos a).
  * lean        l: trunk pelvis->neck; 0 = upright, positive = leaning forward.
    dir = (sin l, -cos l).
  * foot pitch  p: heel->toe line; 0 = sole flat, positive = toe up.
    dir = (cos p, -sin p).
Anatomical joint angles derived from those:
  hip flexion      = thigh + lean            (thigh forward of the trunk line)
  knee flexion     = thigh - shin            (shin folds BACK only)
  ankle dorsiflex  = pitch - shin            (0 = foot square to the shin)
  shoulder flexion = upper + lean
  elbow flexion    = fore - upper            (forearm folds FORWARD only)
"""
import json
import math
import os

import numpy as np

# Joint limits, degrees. Normal adult active range of motion (AAOS / Greene & Heckman,
# "The Clinical Measurement of Joint Motion", 1994), rounded outward by a few degrees so
# that pixel rounding of a pose that is anatomically fine never trips the gate.
JOINT_LIMITS = {
    "spine": (-30.0, 90.0),     # trunk extension 30 .. flexion 90 (lumbar + hip tilt)
    "neck": (-40.0, 40.0),      # head is rigid with the torso part; listed for completeness
    "hip": (-30.0, 125.0),      # extension 30 .. flexion 125
    "knee": (0.0, 150.0),       # backwards only (brief): 0 .. 150
    "ankle": (-50.0, 30.0),     # plantarflexion 50 .. dorsiflexion 30
    "shoulder": (-60.0, 180.0), # extension 60 .. flexion 180
    "elbow": (0.0, 150.0),      # forwards only: 0 .. 150
    "wrist": (-70.0, 80.0),     # rigid with the forearm in v1 (always 0)
}

SIDES = ("near", "far")
ARM_BONES = ("upper", "fore")          # fore part includes the hand (wrist rigid)
LEG_BONES = ("thigh", "shin", "foot")

# Joints the JSON gives in the still (near side; "far" block optional, used only to erase
# the far limbs from the still because they are re-drawn as darkened copies of the near ones).
TRUNK_JOINTS = ("head_top", "neck", "pelvis")
ARM_JOINTS = ("shoulder", "elbow", "wrist", "hand_tip")
LEG_JOINTS = ("hip", "knee", "ankle", "heel", "toe")

DEFAULT_DRAW_ORDER = [
    "far_upper", "far_fore", "far_thigh", "far_shin", "far_foot",
    "back", "torso",
    "near_thigh", "near_shin", "near_foot",
    "near_upper", "near_fore", "gear",
]


def limb_dir(a):
    r = math.radians(a)
    return np.array([math.sin(r), math.cos(r)])


def lean_dir(l):
    r = math.radians(l)
    return np.array([math.sin(r), -math.cos(r)])


def foot_dir(p):
    r = math.radians(p)
    return np.array([math.cos(r), -math.sin(r)])


def limb_angle(v):
    """Inverse of limb_dir for any vector."""
    return math.degrees(math.atan2(v[0], v[1]))


def lean_angle(v):
    return math.degrees(math.atan2(v[0], -v[1]))


def foot_angle(v):
    return math.degrees(math.atan2(-v[1], v[0]))


def rot(v, deg):
    """Rotate v in image coordinates by deg (positive = clockwise on screen, y down)."""
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([c * v[0] - s * v[1], s * v[0] + c * v[1]])


def screen_angle(v):
    return math.degrees(math.atan2(v[1], v[0]))


def wrap180(a):
    return (a + 180.0) % 360.0 - 180.0


class Rig:
    """A character's skeleton measured once from its still."""

    def __init__(self, data):
        self.data = data
        j = {k: np.array(v, float) for k, v in data["joints"].items()}
        self.j = j
        self.name = data.get("name", "char")
        self.ground_y = float(data["ground_y"])
        self.far_shoulder_offset = np.array(data.get("far_shoulder_offset", [-2.0, 0.0]), float)
        self.far_hip_offset = np.array(data.get("far_hip_offset", [-2.0, 0.0]), float)
        self.draw_order = list(data.get("draw_order", DEFAULT_DRAW_ORDER))
        L = {}
        L["spine"] = _d(j["pelvis"], j["neck"])
        L["head"] = _d(j["neck"], j["head_top"])
        L["upper"] = _d(j["shoulder"], j["elbow"])
        L["fore"] = _d(j["elbow"], j["wrist"])
        L["hand"] = _d(j["wrist"], j["hand_tip"])
        L["thigh"] = _d(j["hip"], j["knee"])
        L["shin"] = _d(j["knee"], j["ankle"])
        L["foot"] = _d(j["heel"], j["toe"])
        self.lengths = L
        # rest (still) angles
        self.rest = {
            "lean": lean_angle(j["neck"] - j["pelvis"]),
            "upper": limb_angle(j["elbow"] - j["shoulder"]),
            "fore": limb_angle(j["wrist"] - j["elbow"]),
            "thigh": limb_angle(j["knee"] - j["hip"]),
            "shin": limb_angle(j["ankle"] - j["knee"]),
            "pitch": foot_angle(j["toe"] - j["heel"]),
        }
        # Rigid offsets expressed in the part's own frame (so FK can place them).
        # Torso frame: origin pelvis, rotated so that the trunk is upright.
        self.torso_local = {}
        for name in ("neck", "head_top", "shoulder", "hip"):
            self.torso_local[name] = rot(j[name] - j["pelvis"], -self.rest["lean"])
        # Foot frame: origin heel, sole along +x.
        p = self.rest["pitch"]
        self.foot_local = {n: rot(j[n] - j["heel"], p) for n in ("ankle", "toe", "heel")}
        # hand: rigid continuation of the forearm
        self.hand_offset_deg = wrap180(limb_angle(j["hand_tip"] - j["wrist"]) - self.rest["fore"])
        self.body_height = self.ground_y - j["head_top"][1]
        self.leg_length = L["thigh"] + L["shin"]

    # ----------------------------------------------------------------- I/O
    @classmethod
    def load(cls, path):
        with open(path) as f:
            return cls(json.load(f))

    def save(self, path):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "w") as f:
            json.dump(self.data, f, indent=1)

    @property
    def parts(self):
        return list(self.draw_order)

    # ----------------------------------------------------------------- FK
    def ankle_from_foot(self, heel, pitch):
        """Ankle position for a foot whose heel is at `heel` with sole pitch `pitch`."""
        return heel + rot(self.foot_local["ankle"], -pitch)

    def foot_points(self, ankle, pitch):
        """heel, toe given the ankle position and pitch."""
        heel = ankle - rot(self.foot_local["ankle"], -pitch)
        toe = heel + rot(self.foot_local["toe"], -pitch)
        return heel, toe

    def fk(self, pose):
        """pose: dict with pelvis (x,y), lean, and per side thigh, shin, pitch, upper, fore.
        Returns dict of joint name -> np.array point.  Names are e.g. 'near.knee'."""
        L = self.lengths
        out = {}
        pel = np.array(pose["pelvis"], float)
        lean = pose["lean"]
        out["pelvis"] = pel
        tor = lambda v: rot(v, lean)  # torso local -> image (upright frame rotated by lean)
        out["neck"] = pel + tor(self.torso_local["neck"])
        out["head_top"] = pel + tor(self.torso_local["head_top"])
        for side in SIDES:
            sh = pel + tor(self.torso_local["shoulder"])
            hp = pel + tor(self.torso_local["hip"])
            if side == "far":
                sh = sh + tor(self.far_shoulder_offset)
                hp = hp + tor(self.far_hip_offset)
            s = pose[side]
            el = sh + L["upper"] * limb_dir(s["upper"])
            wr = el + L["fore"] * limb_dir(s["fore"])
            ht = wr + L["hand"] * limb_dir(s["fore"] + self.hand_offset_deg)
            kn = hp + L["thigh"] * limb_dir(s["thigh"])
            an = kn + L["shin"] * limb_dir(s["shin"])
            heel, toe = self.foot_points(an, s["pitch"])
            for n, v in (("shoulder", sh), ("elbow", el), ("wrist", wr), ("hand_tip", ht),
                         ("hip", hp), ("knee", kn), ("ankle", an), ("heel", heel), ("toe", toe)):
                out[side + "." + n] = v
        return out

    def rest_pose(self):
        r = self.rest
        side = {"upper": r["upper"], "fore": r["fore"], "thigh": r["thigh"],
                "shin": r["shin"], "pitch": r["pitch"]}
        return {"pelvis": self.j["pelvis"].copy(), "lean": r["lean"],
                "near": dict(side), "far": dict(side)}

    def bone_pairs(self):
        """(name, joint_a, joint_b, rest length) for every bone checked by the gate."""
        L = self.lengths
        pairs = [("spine", "pelvis", "neck", L["spine"]), ("head", "neck", "head_top", L["head"])]
        for s in SIDES:
            pairs += [
                (s + ".upper", s + ".shoulder", s + ".elbow", L["upper"]),
                (s + ".fore", s + ".elbow", s + ".wrist", L["fore"]),
                (s + ".hand", s + ".wrist", s + ".hand_tip", L["hand"]),
                (s + ".thigh", s + ".hip", s + ".knee", L["thigh"]),
                (s + ".shin", s + ".knee", s + ".ankle", L["shin"]),
                (s + ".foot", s + ".heel", s + ".toe", L["foot"]),
            ]
        return pairs


def joint_angles(J, rest_lean=0.0):
    """Anatomical angles from posed joint positions (dict as returned by Rig.fk, any scale).
    rest_lean is the still's own trunk lean: the drawn torso counts as upright."""
    lean = lean_angle(J["neck"] - J["pelvis"])
    out = {"spine": wrap180(lean - rest_lean)}
    for s in SIDES:
        up = limb_angle(J[s + ".elbow"] - J[s + ".shoulder"])
        fo = limb_angle(J[s + ".wrist"] - J[s + ".elbow"])
        th = limb_angle(J[s + ".knee"] - J[s + ".hip"])
        sh = limb_angle(J[s + ".ankle"] - J[s + ".knee"])
        pi = foot_angle(J[s + ".toe"] - J[s + ".heel"])
        out[s + ".shoulder"] = wrap180(up + lean)
        out[s + ".elbow"] = wrap180(fo - up)
        out[s + ".hip"] = wrap180(th + lean)
        out[s + ".knee"] = wrap180(th - sh)
        out[s + ".ankle"] = wrap180(pi - sh)
    return out


def ik2(hip, target, l1, l2, forward=1.0):
    """Two-bone IK in the picture plane. The middle joint (knee) is placed FORWARD of the
    hip->target line (forward=+1 => toward +x), so the knee bends backwards only.
    Returns (knee, reached_target_point)."""
    hip = np.asarray(hip, float)
    target = np.asarray(target, float)
    v = target - hip
    d = float(np.hypot(*v))
    dmin, dmax = abs(l1 - l2) + 1e-6, l1 + l2 - 1e-6
    if d < 1e-9:
        v, d = np.array([0.0, 1.0]), dmin
    dc = min(max(d, dmin), dmax)
    u = v / max(d, 1e-9)
    end = hip + u * dc
    cos_a = (l1 * l1 + dc * dc - l2 * l2) / (2 * l1 * dc)
    a = math.degrees(math.acos(max(-1.0, min(1.0, cos_a))))
    # perpendicular pointing forward
    perp = np.array([u[1], -u[0]])
    if perp[0] * forward < 0:
        perp = -perp
    ar = math.radians(a)
    knee = hip + l1 * (u * math.cos(ar) + perp * math.sin(ar))
    return knee, end


def _d(a, b):
    return float(np.hypot(*(np.asarray(b, float) - np.asarray(a, float))))

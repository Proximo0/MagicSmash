"""Gear as attachments: a character is one bare BODY still plus zero or more GEAR pictures.

Files, for a character <id> (STILL_SPEC.md):
    <id>.png                 the bare body still
    <id>.json                its joints (a copy of <build>_joints.json from `spec`)
    <id>_gear/<name>.png     one gear picture, drawn alone on a transparent background
    <id>_gear/<name>.json    {"slot": "back" | "near_hand" | "far_hand" | "cape",
                              "anchor": [x, y],   grip / pin point, px in the gear picture
                              "up": [0, -1],      the gear's up direction in the picture
                              "size": 0.36,       its length along `up`, x the body height
                              "in_front": false,  hand slots: drawn over the hand (default: behind it)
                              "angle": 110,       optional, degrees (see below)
                              "at": [0.5, 0.1]}   optional, back / cape: where on the spine

Gear pixels are never cut from the body and never merged into it.  Each gear is turned and
scaled ONCE per angle from its own picture into a game-size sprite (`sprite`), and the sprite
is laid over the baked body frame at whole game pixels (`composite`), in front of the body
parts below its layer and behind those above it:

  back        pinned to the spine: `at` = [share of the way from pelvis to neck, x body height
              behind the spine].  Its angle is the still's and never changes, so its pixels are
              the same in every frame; only its place moves, by whole pixels.  Drawn behind the
              torso, both legs' near parts and the near arm, in front of the far arm and far leg.
  near_hand   grip on the middle of the hand (measured on the still, fit `hand_centre`); the gear's `up` is the
  far_hand    forearm's direction (elbow to wrist) turned by `angle` degrees towards the facing
              side (0 = hanging on along the forearm, 90 = straight out ahead, 180 = pointing
              back up the arm), fixed for the whole walk.  Drawn behind the hand unless in_front.
  cape        hung from `at` on the spine; turns about that point by the torso's lean plus the
              cloth pendulum (cloth.ClothSim.cape_angle).  Drawn behind the torso, behind `back`.

Angles are rounded to ANGLE_STEP so that the same pose always gives the same sprite.
"""
import glob
import hashlib
import json
import math
import os

import numpy as np
from PIL import Image

from .colour import quantize
from .imgops import components
from .intake import clean_key, key_mask

SLOTS = ("back", "near_hand", "far_hand", "cape")
GEAR_PALETTE = 24        # colours per gear picture
GEAR_SS = 6              # supersample of the sprite
GEAR_COVER = 0.34        # a sprite pixel is opaque when this share of it is covered (a handle
                         # two thirds of a pixel thick stays one unbroken line)
ANGLE_STEP = 0.5         # deg
SIZE_RANGE = (0.05, 1.40)    # x body height
LOOSE_MIN = 9            # px: a second piece this big in a gear picture is refused
MIN_PX = 24              # px: a gear picture shorter than this along `up` is too small to scale
DEFAULT_ANGLE = {"near_hand": 110.0, "far_hand": 110.0, "back": 0.0, "cape": 0.0}
DEFAULT_AT = {"back": (0.50, 0.10), "cape": (0.93, 0.07)}


class Gear:
    def __init__(self, name, img, spec):
        self.name = name
        self.label = "gear:" + name
        self.spec = spec
        self.slot = spec.get("slot")
        a = np.array(img)
        a[a[..., 3] < 128] = 0
        a[a[..., 3] >= 128, 3] = 255
        a = clean_key(a)[0]
        self.key_px = int(key_mask(a).sum())
        self.img, self.palette = quantize(a, GEAR_PALETTE)
        self.mask = self.img[..., 3] > 0
        self.anchor = np.array(spec.get("anchor", [0, 0]), float)
        up = np.array(spec.get("up", [0, -1]), float)
        n = float(np.hypot(*up))
        self.up = up / n if n > 0 else np.array([0.0, -1.0])
        self.size = float(spec.get("size", 0))
        self.in_front = bool(spec.get("in_front", False))
        self.angle = float(spec.get("angle", DEFAULT_ANGLE.get(self.slot, 0.0)))
        self.at = tuple(spec.get("at", DEFAULT_AT.get(self.slot, (0.5, 0.1))))
        # length along `up` and how far it reaches past the anchor, in picture px
        ys, xs = np.where(self.mask)
        if len(ys):
            t = (xs + 0.5 - self.anchor[0]) * self.up[0] + (ys + 0.5 - self.anchor[1]) * self.up[1]
            self.extent = float(t.max() - t.min()) + 1.0
            self.reach_px = float(np.hypot(xs + 0.5 - self.anchor[0], ys + 0.5 - self.anchor[1]).max())
        else:
            self.extent, self.reach_px = 0.0, 0.0
        self._sprites = {}

    def digest(self):
        return hashlib.sha1(self.img.tobytes()).hexdigest()[:16]

    @property
    def reach(self):
        """How far the gear reaches from its anchor, x body height."""
        return self.size * self.reach_px / max(self.extent, 1.0)

    def sprite(self, scale, phi):
        """The gear turned by phi degrees (ANGLE_STEP grid) at `scale` game px per picture px:
        (rgba HxWx4, (ox, oy)), where (ox, oy) is the sprite's top-left corner relative to the
        game pixel that holds the anchor.  The anchor sits on the centre of that pixel."""
        key = (round(scale, 6), round(phi / ANGLE_STEP))
        if key in self._sprites:
            return self._sprites[key]
        from .bake import reduce
        r = math.radians(key[1] * ANGLE_STEP)
        c, s = math.cos(r), math.sin(r)
        H, W = self.mask.shape
        cor = np.array([[0, 0], [W, 0], [0, H], [W, H]], float) - self.anchor
        g = np.stack([c * cor[:, 0] - s * cor[:, 1], s * cor[:, 0] + c * cor[:, 1]], 1) * scale + 0.5
        x0, y0 = int(math.floor(g[:, 0].min())) - 1, int(math.floor(g[:, 1].min())) - 1
        x1, y1 = int(math.ceil(g[:, 0].max())) + 1, int(math.ceil(g[:, 1].max())) + 1
        SS = GEAR_SS
        qy, qx = np.mgrid[0:(y1 - y0) * SS, 0:(x1 - x0) * SS]
        gx = x0 + (qx + 0.5) / SS - 0.5
        gy = y0 + (qy + 0.5) / SS - 0.5
        sx = (c * gx + s * gy) / scale + self.anchor[0]
        sy = (-s * gx + c * gy) / scale + self.anchor[1]
        ix, iy = np.floor(sx).astype(int), np.floor(sy).astype(int)
        ok = (ix >= 0) & (iy >= 0) & (ix < W) & (iy < H)
        src = self.img[np.clip(iy, 0, H - 1), np.clip(ix, 0, W - 1)]
        src[~ok] = 0
        rgba, _ = reduce(src, (src[..., 3] > 0).astype(np.int16), SS, cover=GEAR_COVER)
        out = (rgba, (x0, y0))
        self._sprites[key] = out
        return out


def gear_dir(still_png):
    return still_png[:-4] + "_gear"


def load_gear(still_png):
    """Every <id>_gear/<name>.json with its picture, sorted by name."""
    out = []
    for js in sorted(glob.glob(os.path.join(gear_dir(still_png), "*.json"))):
        with open(js) as f:
            spec = json.load(f)
        png = js[:-5] + ".png"
        name = os.path.basename(js)[:-5]
        if not os.path.exists(png):
            g = Gear(name, np.zeros((1, 1, 4), np.uint8), spec)
            g.missing = True
        else:
            g = Gear(name, Image.open(png).convert("RGBA"), spec)
        out.append(g)
    return out


def gate_gear(gears):
    """Input rule G14 for every gear picture: [(text, [])] failures."""
    out = []
    seen = {}
    for g in gears:
        bad = []
        if getattr(g, "missing", False):
            bad.append("the picture %s.png is missing" % g.name)
        if g.slot not in SLOTS:
            bad.append("slot %r is not one of %s" % (g.slot, ", ".join(SLOTS)))
        elif g.slot in seen:
            bad.append("slot %s is already taken by %s (one gear per slot)" % (g.slot, seen[g.slot]))
        else:
            seen[g.slot] = g.name
        if not SIZE_RANGE[0] <= g.size <= SIZE_RANGE[1]:
            bad.append("size %.2f is outside %.2f-%.2f of the body height" % (g.size, *SIZE_RANGE))
        if g.mask.any():
            H, W = g.mask.shape
            if g.extent < MIN_PX:
                bad.append("the picture is only %d px long along its up direction (at least %d)"
                           % (g.extent, MIN_PX))
            ax, ay = int(math.floor(g.anchor[0])), int(math.floor(g.anchor[1]))
            if not (0 <= ax < W and 0 <= ay < H):
                bad.append("the anchor %d,%d is outside the picture" % (ax, ay))
            elif g.slot in ("near_hand", "far_hand") and not g.mask[max(0, ay - 2):ay + 3, max(0, ax - 2):ax + 3].any():
                bad.append("the grip %d,%d is not on the gear (a hand cannot hold it there)" % (ax, ay))
            lab, sizes = components(g.mask)
            main = max(sizes.values())
            loose = sorted(s for s in sizes.values() if s >= LOOSE_MIN)[:-1]
            if loose:
                bad.append("the picture has %d loose piece%s (%d px; the gear itself %d px): one gear, "
                           "one connected shape" % (len(loose), "" if len(loose) == 1 else "s", sum(loose), main))
            if g.key_px:
                bad.append("%d px of the background key's colour left in the picture" % g.key_px)
        elif not getattr(g, "missing", False):
            bad.append("the picture is empty")
        for b in bad:
            out.append(("G14: gear_picture: %s: %s" % (g.name, b), []))
    return out


def _ang(v):
    return math.degrees(math.atan2(v[1], v[0]))


def _turn(v, deg):
    """v turned by deg towards the facing side (down -> forward -> up), screen coordinates."""
    r = math.radians(-deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([c * v[0] - s * v[1], s * v[0] + c * v[1]])


def _unit(v):
    return v / max(float(np.hypot(*v)), 1e-9)


def layer_rank(g, names):
    """Where the gear sits among the body's draw order (`names`, index 0 = background): body
    parts with an index below the rank are behind it."""
    idx = {n: i for i, n in enumerate(names)}
    top = len(names)
    if g.slot == "back":
        return idx.get("torso", 1) - 0.3
    if g.slot == "cape":
        return idx.get("torso", 1) - 0.6
    side = "near" if g.slot == "near_hand" else "far"
    if g.in_front:
        return idx.get(side + "_fore", top) + 0.5
    return idx.get(side + "_upper", top) - 0.5


def hand_local(rig):
    """The middle of the drawn hand in the forearm's frame: (px along the forearm past the
    wrist, px across it).  fit.py measures it on the still (`hand_centre`); without that it is
    half-way from the wrist to the hand tip."""
    e, w = rig.j["elbow"], rig.j["wrist"]
    c = np.array(rig.data.get("hand_centre", (w + rig.j["hand_tip"]) / 2), float)
    f = _unit(w - e)
    return float((c - w) @ f), float((c - w) @ np.array([-f[1], f[0]]))


def hand_point(elbow, wrist, local):
    """The hand's middle for a posed forearm (any px scale; `local` in the same scale)."""
    f = _unit(np.asarray(wrist, float) - np.asarray(elbow, float))
    return np.asarray(wrist, float) + local[0] * f + local[1] * np.array([-f[1], f[0]])


def place(ch, g, J, cloth=None, phase=0.0):
    """Pin point (still px) and turn (deg, rounded) of gear g for posed joints J."""
    rig = ch.rig
    BH = rig.body_height
    if g.slot in ("near_hand", "far_hand"):
        s = g.slot[:-5]
        pin = hand_point(J[s + ".elbow"], J[s + ".wrist"], hand_local(rig))
        t = _turn(_unit(J[s + ".wrist"] - J[s + ".elbow"]), g.angle)
    else:
        spine = J["neck"] - J["pelvis"]
        pin = J["pelvis"] + g.at[0] * spine - np.array([g.at[1] * BH, 0.0])
        if g.slot == "cape":
            sway = cloth.cape_angle(phase) if cloth is not None else 0.0
            t = _turn(_unit(spine), g.angle - sway)
        else:                       # back: the still's own spine, the same in every frame
            t = _turn(_unit(rig.j["neck"] - rig.j["pelvis"]), g.angle)
    phi = _ang(t) - _ang(g.up)
    phi = round(((phi + 180.0) % 360.0 - 180.0) / ANGLE_STEP) * ANGLE_STEP
    return pin, phi


def scale_of(ch, g):
    """Game px per gear-picture px."""
    return g.size * ch.rig.body_height * ch.k / max(g.extent, 1.0)


def composite(ch, rgba, lab, names, J, cloth=None, phase=0.0):
    """Lay every gear of ch over a baked body frame.  Returns (rgba, label, names, layers):
    names gets one label per gear; layers[label] = {"rgba": sprite, "at": [x, y] of its top-left
    canvas pixel, "grip": the anchor as drawn (game px), "phi": deg, "slot", "rank"}."""
    out, lab2 = rgba.copy(), lab.copy()
    names2 = list(names)
    H, W = lab.shape
    layers = {}
    for g in sorted(ch.gear, key=lambda g_: layer_rank(g_, names)):
        rank = layer_rank(g, names)
        pin, phi = place(ch, g, J, cloth, phase)
        spr, (ox, oy) = g.sprite(scale_of(ch, g), phi)
        G = ch.to_game(pin)
        px, py = int(math.floor(G[0])), int(math.floor(G[1]))
        x0, y0 = px + ox, py + oy
        names2.append(g.label)
        li = len(names2) - 1
        layers[g.label] = {"rgba": spr, "at": [x0, y0], "grip": [px + 0.5, py + 0.5], "phi": phi,
                           "slot": g.slot, "rank": rank}
        h, w = spr.shape[:2]
        cx0, cy0, cx1, cy1 = max(x0, 0), max(y0, 0), min(x0 + w, W), min(y0 + h, H)
        if cx1 <= cx0 or cy1 <= cy0:
            continue
        sub = spr[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
        under = lab[cy0:cy1, cx0:cx1]           # the body alone decides what hides the gear
        show = (sub[..., 3] > 0) & ((under == 0) | (under < rank))
        out[cy0:cy1, cx0:cx1][show] = sub[show]
        lab2[cy0:cy1, cx0:cx1][show] = li
    return out, lab2, names2, layers


def export(ch, out_dir):
    """Each gear picture (as quantised) and its JSON into <out_dir>; returns the records."""
    os.makedirs(out_dir, exist_ok=True)
    recs = {}
    for g in ch.gear:
        fn = "gear_" + g.name + ".png"
        Image.fromarray(g.img, "RGBA").save(os.path.join(out_dir, fn))
        recs[g.label] = dict(g.spec, png=fn, sha1=g.digest(), game_scale=scale_of(ch, g),
                             parent={"back": "torso", "cape": "torso", "near_hand": "near_fore",
                                     "far_hand": "far_fore"}.get(g.slot))
    return recs

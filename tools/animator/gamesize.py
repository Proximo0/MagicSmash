"""PILOT: a walk baked AT GAME SIZE (a redesign of bake.py, which it leaves untouched).

Old bake: every frame re-samples the 384x448 drawing; parts are rotated by fractions of a degree,
the hand prop is rebuilt from its big picture for every angle, 56 px and 112 px are baked apart.
Here:
  1. the still (and every part, and the prop) is reduced ONCE to game size on one grid: dominant
     colour per block, outline colours weighted up, one shared palette per hero (<= PALETTE_N),
     alpha is 0 or 255;
  2. each part (head, torso, robe/cloth, upper/lower arm, thigh, shin, foot, per side, prop) is one
     small fixed sprite cut at game size from the rig's part masks;
  3. a frame = the sprites at WHOLE-pixel origins.  A limb turns only in steps of STEP degrees
     (0, +-22.5, +-45 ...); each (part, step) sprite is made once (nearest-neighbour rotation at
     8x, dominant-colour reduction) and reused in every frame.  Head, torso, robe never turn: they
     translate with the bob, whole pixels;
  4. the held prop is one rigid sprite per carry angle (at most 3), glued to the hand sprite at a
     whole-pixel anchor;
  5. the second size is derived from the finished master frames: 112 = exact 2x nearest of 56;
     56 = 2:1 dominant-colour of 112 when every part origin is even (`even=True`).

Rendered frames carry a label map and every part's origin, so `measure` can report, per part, how
many of its pixels change between frames after shifting by its known offset.

Palette reduction: written here (dominant-colour block reduction to an exact size + median-cut
palette whose entries are real source colours).  `unfake` (MIT, pip) installs but takes a file
path and finds its own grid, so it cannot give an exact size on one grid shared by every part.
"""
import math
import time

import numpy as np

from .bake import AUTO_DRAW_ORDER, REF_BH
from .rig import screen_angle, wrap180

STEP = 22.5            # degrees between the rotations a limb may take
MAX_STEP = 4           # +-90 degrees
PALETTE_N = 24
BASE_CANVAS = (96, 80)  # at 56 px (the old canvas); the pelvis column and the ground row below
BASE_FOOT, BASE_PELVIS = 74, 46
DARK_LUMA = 60         # colours darker than this are outline colours ...
DARK_BONUS = 1.6       # ... and win a block with this many times their votes
COVER = 0.5
UP = 8                 # rotation sub-sampling
LIMBS = ("near_upper", "near_fore", "near_thigh", "near_shin", "near_foot",
         "far_upper", "far_fore", "far_thigh", "far_shin", "far_foot")
RIGID_PROPS = ("back", "cape", "head")
NFRAMES = 8


# ------------------------------------------------------------------ palette
def _luma(c):
    c = np.asarray(c, float)
    return 0.3 * c[..., 0] + 0.59 * c[..., 1] + 0.11 * c[..., 2]


def build_palette(sources, n=PALETTE_N):
    """sources: [(rgba HxWx4 uint8, weight per pixel)].  Median cut on the colours weighted by
    pixel count; each entry is the member colour nearest the box mean (always a real colour)."""
    acc = {}
    for img, w in sources:
        a = img[..., 3] > 0
        if not a.any():
            continue
        cols, cnt = np.unique(img[a][:, :3], axis=0, return_counts=True)
        for c, k in zip(map(tuple, cols.tolist()), cnt):
            acc[c] = acc.get(c, 0.0) + k * w
    cols = np.array(list(acc.keys()), float)
    wt = np.array(list(acc.values()), float) ** 0.6
    boxes = [(np.arange(len(cols)))]
    while len(boxes) < n:
        best, bi = -1, -1
        for i, b in enumerate(boxes):
            if len(b) < 2:
                continue
            sc = (cols[b].max(0) - cols[b].min(0)).max() * wt[b].sum() ** 0.5
            if sc > best:
                best, bi = sc, i
        if bi < 0:
            break
        b = boxes.pop(bi)
        ch = int(np.argmax(cols[b].max(0) - cols[b].min(0)))
        o = b[np.argsort(cols[b][:, ch], kind="stable")]
        cw = np.cumsum(wt[o])
        cut = int(np.searchsorted(cw, cw[-1] / 2.0)) + 1
        cut = min(max(cut, 1), len(o) - 1)
        boxes += [o[:cut], o[cut:]]
    pal = []
    for b in boxes:
        m = (cols[b] * wt[b][:, None]).sum(0) / wt[b].sum()
        pal.append(cols[b][np.argmin(((cols[b] - m) ** 2).sum(1))])
    pal = np.array(pal, np.uint8)
    order = np.argsort(_luma(pal), kind="stable")
    return pal[order]


def to_index(rgba, pal):
    """Palette index of every opaque pixel (nearest colour, luma-weighted), -1 where transparent."""
    out = np.full(rgba.shape[:2], -1, np.int16)
    a = rgba[..., 3] > 0
    if not a.any():
        return out
    cols, inv = np.unique(rgba[a][:, :3], axis=0, return_inverse=True)
    d = (((cols[:, None, :].astype(int) - pal[None].astype(int)) ** 2) * np.array([3, 4, 2])).sum(-1)
    out[a] = np.argmin(d, 1)[inv.reshape(-1)]
    return out


def to_rgba(idx, pal):
    out = np.zeros(idx.shape + (4,), np.uint8)
    m = idx >= 0
    out[m, :3] = pal[idx[m]]
    out[m, 3] = 255
    return out


# ------------------------------------------------------------------ reduction onto the game grid
class Grid:
    """Still px -> game px: game = (still - (pelvis_x, ground_y)) * k + (PX, FY); block = floor."""

    def __init__(self, shape, pelvis_x, ground_y, k, canvas, pel_game, foot_game):
        H, W = shape
        self.k, self.canvas = k, canvas
        self.org = np.array([pelvis_x, ground_y], float)
        self.off = np.array([pel_game, foot_game], float)
        xs = np.floor(((np.arange(W) + 0.5 - pelvis_x) * k + pel_game)).astype(int)
        ys = np.floor(((np.arange(H) + 0.5 - ground_y) * k + foot_game)).astype(int)
        bx = np.broadcast_to(xs[None, :], (H, W))
        by = np.broadcast_to(ys[:, None], (H, W))
        ok = (bx >= 0) & (bx < canvas[0]) & (by >= 0) & (by < canvas[1])
        self.blk = np.where(ok, by * canvas[0] + bx, -1)
        v = self.blk[ok]
        self.total = np.bincount(v, minlength=canvas[0] * canvas[1]).astype(float)

    def G(self, p):
        return (np.asarray(p, float) - self.org) * self.k + self.off

    def reduce(self, idx, K, dark):
        """idx (HxW, -1 = clear) -> (dominant idx per block, coverage per block), both canvas-shaped."""
        W, H = self.canvas
        n = W * H
        ok = (self.blk >= 0) & (idx >= 0)
        b, c = self.blk[ok], idx[ok].astype(int)
        w = np.where(dark[c], DARK_BONUS, 1.0)
        cnt = np.bincount(b * K + c, weights=w, minlength=n * K).reshape(n, K)
        cov = np.bincount(b, minlength=n) / np.maximum(self.total, 1.0)
        dom = np.where(cnt.sum(1) > 0, cnt.argmax(1), -1).astype(np.int16)
        return dom.reshape(H, W), cov.reshape(H, W)


def rotate_idx(sp, piv, deg, K, dark):
    """sp: idx image (-1 clear); piv: integer pivot (x, y) in sp's pixel grid.  Turn by `deg`
    (screen convention of bake.render: x' = c x - s y, y' = s x + c y) about the pivot: nearest
    neighbour sampled at UP x resolution then dominant-reduced UP:1.  Returns (idx, ox, oy) with
    (ox, oy) the output's top-left relative to the pivot."""
    h, w = sp.shape
    if deg == 0:
        return sp, -piv[0], -piv[1]
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    ys, xs = np.nonzero(sp >= 0)
    if len(xs) == 0:
        return sp, -piv[0], -piv[1]
    rad = int(math.ceil(max(np.hypot(xs - piv[0], ys - piv[1]).max(),
                            np.hypot(xs + 1 - piv[0], ys + 1 - piv[1]).max()))) + 1
    n = 2 * rad
    q = (np.arange(n * UP) + 0.5) / UP - rad
    gx, gy = np.meshgrid(q, q)
    sx = np.floor(c * gx + s * gy + piv[0]).astype(int)
    sy = np.floor(-s * gx + c * gy + piv[1]).astype(int)
    ok = (sx >= 0) & (sy >= 0) & (sx < w) & (sy < h)
    src = np.where(ok, sp[np.clip(sy, 0, h - 1), np.clip(sx, 0, w - 1)], -1)
    blocks = src.reshape(n, UP, n, UP).transpose(0, 2, 1, 3).reshape(n, n, UP * UP)
    cov = (blocks >= 0).sum(-1) / float(UP * UP)
    wgt = np.where(blocks >= 0, np.where(dark[np.clip(blocks, 0, K - 1)], DARK_BONUS, 1.0), 0.0)
    cnt = np.zeros((n, n, K))
    for k_ in range(K):
        cnt[..., k_] = np.where(blocks == k_, wgt, 0.0).sum(-1)
    out = np.where(cov >= COVER, cnt.argmax(-1), -1).astype(np.int16)
    return out, -rad, -rad


def trim(sp, ox, oy, even):
    """Crop to the opaque box (aligned to even coordinates when `even`); origin follows."""
    ys, xs = np.nonzero(sp >= 0)
    if len(xs) == 0:
        return np.full((1, 1), -1, np.int16), ox, oy
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    if even:
        x0 -= (ox + x0) % 2
        y0 -= (oy + y0) % 2
        x1 += (x1 - x0) % 2
        y1 += (y1 - y0) % 2
        pad = np.full((y1 - y0, x1 - x0), -1, np.int16)
        sx0, sy0 = max(x0, 0), max(y0, 0)
        sx1, sy1 = min(x1, sp.shape[1]), min(y1, sp.shape[0])
        pad[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = sp[sy0:sy1, sx0:sx1]
        return pad, ox + x0, oy + y0
    return sp[y0:y1, x0:x1].copy(), ox + x0, oy + y0


def rnd(v, q):
    return int(math.floor(v / q + 0.5)) * q


def rot2(v, deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([c * v[0] - s * v[1], s * v[0] + c * v[1]])


# ------------------------------------------------------------------ the hero
class Hero:
    """Everything a bake needs for one master size: grid, palette, sprites, rig, poses."""

    def __init__(self, png, joints, master=56, even=False, fitted=None, gears=None, chars=None):
        from .bake import Character
        from .fit import fit_still
        from .gear import load_gear
        self.master, self.even = master, even
        self.q = 2 if even else 1
        m = master / 56.0
        self.m = m
        self.png = png
        fitted = fitted or fit_still(png, joints)
        gears = gears if gears is not None else load_gear(png)
        ch = Character.from_still(png, joints, fitted=fitted, body_h=master, gear=gears)
        self.ch, self.fitted, self.gears = ch, fitted, gears
        self.name = ch.name
        self.canvas = (int(round(BASE_CANVAS[0] * m)), int(round(BASE_CANVAS[1] * m)))
        self.foot_y = int(round(BASE_FOOT * m))
        self.pel_x = int(round(BASE_PELVIS * m))
        rig = ch.rig
        self.rig = rig
        self.k = master / REF_BH
        H, W = ch.still.shape[:2]
        self.grid = Grid((H, W), float(rig.j["pelvis"][0]), rig.ground_y, self.k, self.canvas,
                         self.pel_x, self.foot_y)
        self._palette_and_parts()
        self._poses()

    # -- 1 + 2: one reduction, one palette, small sprites
    def _palette_and_parts(self):
        ch, g, rig = self.ch, self.grid, self.rig
        srcs = [(p.img, self.k ** 2) for p in ch.parts.values()]
        # the still itself is the union of the near parts; far parts are darker copies
        from .gear import scale_of
        for ge in self.gears:
            srcs.append((ge.img, scale_of(ch, ge) ** 2))
        self.palette = build_palette(srcs, PALETTE_N)
        pal = self.palette
        self.K = len(pal)
        self.dark = _luma(pal) < DARK_LUMA
        # a reference reduction of the whole near body: gaps between sprites are closed against it
        near_all = np.zeros(ch.still.shape[:2], bool)
        for nm, p in ch.parts.items():
            if not nm.startswith("far_"):
                near_all |= p.mask
        full = {}
        for nm, p in ch.parts.items():
            full[nm] = g.reduce(to_index(p.img, pal), self.K, self.dark)
        ref_cov = g.reduce(np.where(near_all, 0, -1).astype(np.int16), 1, np.zeros(1, bool))[1]
        owned = np.zeros(self.canvas[::-1], bool)
        best = np.zeros(self.canvas[::-1])
        owner = np.full(self.canvas[::-1], "", object)
        for nm, (dom, cov) in full.items():
            if nm.startswith("far_"):
                continue
            owned |= cov >= COVER
            better = cov > best
            best = np.where(better, cov, best)
            owner = np.where(better, nm, owner)
        gaps = (ref_cov >= COVER) & ~owned
        self.gap_blocks = int(gaps.sum())
        self.sprites = {}
        self.pivot = {}
        neck_row = int(math.ceil(g.G(rig.j["neck"])[1]))
        for nm, (dom, cov) in full.items():
            keep = cov >= COVER
            if nm in owner and not nm.startswith("far_"):
                keep |= gaps & (owner == nm)
            idx = np.where(keep, dom, -1).astype(np.int16)
            if nm == "torso":
                head = idx.copy()
                head[neck_row:] = -1
                torso = idx.copy()
                torso[:neck_row] = -1
                self.sprites["head"] = self._crop(head)
                self.sprites["torso"] = self._crop(torso)
            else:
                self.sprites[nm] = self._crop(idx)
        self.body_parts = [n for n in self.sprites if n not in LIMBS]
        # pivots (integer, canvas coords) of the limb parts
        for nm in LIMBS:
            if nm in ch.parts:
                p = ch.parts[nm]
                self.pivot[nm] = tuple(int(rnd(v, self.q)) for v in g.G(rig.j[p.pivot]))
        self._rot = {}

    def _crop(self, idx):
        sp, ox, oy = trim(idx, 0, 0, self.even)
        return sp, ox, oy       # origin in canvas coordinates

    def variant(self, nm, step):
        """The sprite of limb `nm` turned by `step` steps: (idx, ox, oy) with the origin
        relative to the part's integer pivot.  Computed once."""
        key = (nm, step)
        if key not in self._rot:
            full = np.full(self.canvas[::-1], -1, np.int16)
            sp, ox, oy = self.sprites[nm]
            full[oy:oy + sp.shape[0], ox:ox + sp.shape[1]] = sp
            out, rx, ry = rotate_idx(full, self.pivot[nm], step * STEP, self.K, self.dark)
            if step == 0:
                out, rx, ry = sp, ox - self.pivot[nm][0], oy - self.pivot[nm][1]
            else:
                out, rx, ry = trim(out, rx, ry, self.even)
            self._rot[key] = (out, rx, ry)
        return self._rot[key]

    # -- poses: the old walk's angles, quantised
    def _poses(self):
        from .motion import Gait
        from .bake import BACK_SLOTS
        ch, rig = self.ch, self.rig
        motion = ch.walk_motion()
        gait = Gait(rig, motion)
        if any(ge.slot in BACK_SLOTS for ge in self.gears):
            from . import bake as _b
            gait.solve_far_tuck(margin=-(_b.FAR_HAND_CLEAR * rig.body_height + ch.info["radius"]["fore"]))
        self.Jrest = rig.fk(rig.rest_pose())
        self.J = []
        for i in range(NFRAMES):
            pose, contact = gait.pose(i / NFRAMES)
            self.J.append(rig.fk(pose))
        self.hand_local = None

    def step_of(self, J, nm):
        side = nm[:3] if nm[:3] in ("far",) else "near"
        side = "far" if nm.startswith("far_") else "near"
        a, b = {"upper": ("shoulder", "elbow"), "fore": ("elbow", "wrist"), "thigh": ("hip", "knee"),
                "shin": ("knee", "ankle"), "foot": ("heel", "toe")}[nm.split("_")[1]]
        ra, rb = self.rig.j[a], self.rig.j[b]
        d = screen_angle(J[side + "." + b] - J[side + "." + a]) - screen_angle(rb - ra)
        return int(max(-MAX_STEP, min(MAX_STEP, round(wrap180(d) / STEP))))

    # -- 3 + 4: one frame
    def frame(self, i):
        from .gear import hand_local, hand_point, place, scale_of
        ch, rig, q, g = self.ch, self.rig, self.q, self.grid
        J, Jr, k = self.J[i], self.Jrest, self.k
        steps = {nm: self.step_of(J, nm) for nm in LIMBS if nm in ch.parts}
        target, origin = {}, {}
        for side in ("near", "far"):
            sh = g.G(Jr[side + ".shoulder"])
            hp = g.G(Jr[side + ".hip"])
            chain = [("upper", sh, "shoulder", "elbow"), ("fore", None, "elbow", "wrist"),
                     ("thigh", hp, "hip", "knee"), ("shin", None, "knee", "ankle"), ("foot", None, "ankle", None)]
            pos = {}
            for bone, start, ja, jb in chain:
                nm = side + "_" + bone
                if nm not in steps:
                    continue
                if start is None:
                    start = pos[ja]
                pos[ja] = start
                target[nm] = start
                if jb is not None and bone != "foot":
                    vec = (Jr[side + "." + jb] - Jr[side + "." + ja]) * k
                    pos[jb] = start + rot2(vec, steps[nm] * STEP)
        # whole-pixel origins (before the bob)
        pivrel = {}
        for nm in steps:
            sp, rx, ry = self.variant(nm, steps[nm])
            T = np.array([rnd(target[nm][0], q), rnd(target[nm][1], q)])
            origin[nm] = np.array([T[0] + rx, T[1] + ry])
            if nm.startswith("near_") and nm.endswith("_fore"):
                pivrel[nm] = T
        # the bob puts the lowest sole on the ground row
        low = -10 ** 9
        for nm in ("near_foot", "far_foot"):
            if nm in steps:
                sp, rx, ry = self.variant(nm, steps[nm])
                rows = np.nonzero((sp >= 0).any(1))[0]
                if len(rows):
                    low = max(low, origin[nm][1] + rows[-1])
        gap = self.foot_y - 1 - low
        bob = (gap - gap % q) if low > -10 ** 8 else 0   # never below the ground row
        body_off = {}
        for nm in self.body_parts:
            sp, ox, oy = self.sprites[nm]
            body_off[nm] = np.array([ox, oy])
        for nm in list(origin):
            origin[nm] = origin[nm] + [0, bob]
        for nm in body_off:
            origin[nm] = body_off[nm] + [0, bob]
        # props
        props = {}
        for ge in self.gears:
            sc = scale_of(ch, ge)
            if ge.slot == "near_hand":
                _, phi0 = place(ch, ge, self.Jrest)
                _, phi = place(ch, ge, J)
                c = int(max(-1, min(1, round(wrap180(phi - phi0) / STEP))))
                sp, (ox, oy) = ge.sprite(sc, phi0 + c * STEP, int(ch.body_h / 56.0))
                s_ = steps["near_fore"]
                hl = hand_local(rig)
                pin0 = hand_point(Jr["near.elbow"], Jr["near.wrist"], hl)
                v0 = (pin0 - Jr["near.elbow"]) * k
                P = pivrel["near_fore"] + np.floor(rot2(v0, s_ * STEP) + 0.0).astype(int)
                org = P + [ox, oy] + [0, bob]
                if self.even:
                    org = np.array([rnd(org[0], 2), rnd(org[1], 2)])
                props["gear:" + ge.name] = (self._gear_idx(sp), org, c)
            elif ge.slot in RIGID_PROPS or ge.slot == "cape":
                pin, phi = place(ch, ge, self.Jrest, None, 0.0)
                sp, (ox, oy) = ge.sprite(sc, phi, 0)
                P = np.floor(g.G(pin)).astype(int)
                org = P + [ox, oy] + [0, bob]
                if self.even:
                    org = np.array([rnd(org[0], 2), rnd(org[1], 2)])
                props["gear:" + ge.name] = (self._gear_idx(sp), org, 0)
        return steps, origin, props, bob

    def _gear_idx(self, rgba):
        return to_index(rgba, self.palette)

    def draw_order(self):
        order = [n for n in AUTO_DRAW_ORDER if n in self.sprites or n == "torso"]
        out = []
        for n in order:
            if n == "torso":
                out += ["torso", "head"]
            else:
                out.append(n)
        # gear: back/cape slots behind the torso, hand gear behind the near forearm
        for ge in self.gears:
            lab = "gear:" + ge.name
            if ge.slot in ("back", "cape"):
                out.insert(out.index("torso"), lab)
            elif ge.slot == "head":
                out.append(lab)
            elif ge.slot == "near_hand":
                if ge.in_front:
                    out.append(lab)
                else:
                    out.insert(out.index("near_fore") if "near_fore" in out else len(out), lab)
        return out

    def bake(self):
        """8 frames at the master size: list of dicts (idx, label, origin, step, ...) + names."""
        order = self.draw_order()
        names = ["bg"] + order
        frames = []
        for i in range(NFRAMES):
            steps, origin, props, bob = self.frame(i)
            W, H = self.canvas
            idx = np.full((H, W), -1, np.int16)
            lab = np.zeros((H, W), np.int16)
            offs, variant = {}, {}
            for li, nm in enumerate(order, 1):
                if nm in props:
                    sp, org, c = props[nm]
                    variant[nm] = ("carry", c)
                elif nm in steps:
                    sp = self.variant(nm, steps[nm])[0]
                    org = origin[nm]
                    variant[nm] = ("step", steps[nm])
                else:
                    sp = self.sprites[nm][0]
                    org = origin[nm]
                    variant[nm] = ("rigid", 0)
                offs[nm] = (int(org[0]), int(org[1]))
                _paste(idx, lab, sp, org, li)
            frames.append({"idx": idx, "label": lab, "offset": offs, "variant": variant, "bob": bob})
        return FrameSet(frames, names, self.palette, self.master, self.foot_y, self.pel_x)


def _paste(idx, lab, sp, org, li):
    h, w = sp.shape
    x0, y0 = int(org[0]), int(org[1])
    H, W = idx.shape
    xa, ya, xb, yb = max(x0, 0), max(y0, 0), min(x0 + w, W), min(y0 + h, H)
    if xb <= xa or yb <= ya:
        return
    s = sp[ya - y0:yb - y0, xa - x0:xb - x0]
    m = s >= 0
    idx[ya:yb, xa:xb][m] = s[m]
    lab[ya:yb, xa:xb][m] = li


# ------------------------------------------------------------------ frame sets and the two sizes
class FrameSet:
    def __init__(self, frames, names, palette, master, foot_y, pel_x):
        self.frames, self.names, self.palette = frames, names, palette
        self.master, self.foot_y, self.pel_x = master, foot_y, pel_x

    def rgba(self, i):
        return to_rgba(self.frames[i]["idx"], self.palette)

    def up2(self):
        """Exact 2x nearest: the 112 px frames of a 56 px master."""
        out = []
        for f in self.frames:
            out.append({"idx": f["idx"].repeat(2, 0).repeat(2, 1), "label": f["label"].repeat(2, 0).repeat(2, 1),
                        "offset": {n: (2 * x, 2 * y) for n, (x, y) in f["offset"].items()},
                        "variant": f["variant"], "bob": 2 * f["bob"]})
        return FrameSet(out, self.names, self.palette, self.master * 2, self.foot_y * 2, self.pel_x * 2)

    def down2(self):
        """2:1 dominant colour: the 56 px frames of a 112 px master.  Only when every part origin
        (and the bob) is even, so a part lands on the same pixels in every frame."""
        for f in self.frames:
            if any(x % 2 or y % 2 for x, y in f["offset"].values()) or f["bob"] % 2:
                raise ValueError("2:1 needs even part origins")
        K = len(self.palette)
        dark = _luma(self.palette) < DARK_LUMA
        out = []
        for f in self.frames:
            H, W = f["idx"].shape
            b = f["idx"].reshape(H // 2, 2, W // 2, 2).transpose(0, 2, 1, 3).reshape(H // 2, W // 2, 4)
            lb = f["label"].reshape(H // 2, 2, W // 2, 2).transpose(0, 2, 1, 3).reshape(H // 2, W // 2, 4)
            cnt = np.zeros((H // 2, W // 2, K))
            for k_ in range(K):
                cnt[..., k_] = np.where(b == k_, DARK_BONUS if dark[k_] else 1.0, 0.0).sum(-1)
            opaque = (b >= 0).sum(-1) >= 2
            idx = np.where(opaque, cnt.argmax(-1), -1).astype(np.int16)
            nl = len(self.names) + 1
            lc = np.zeros((H // 2, W // 2, nl))
            for l_ in range(1, nl):
                lc[..., l_] = ((lb == l_) & (b >= 0)).sum(-1)
            label = np.where(idx >= 0, lc.argmax(-1), 0).astype(np.int16)
            out.append({"idx": idx, "label": label,
                        "offset": {n: (x // 2, y // 2) for n, (x, y) in f["offset"].items()},
                        "variant": f["variant"], "bob": f["bob"] // 2})
        return FrameSet(out, self.names, self.palette, self.master // 2, self.foot_y // 2, self.pel_x // 2)


# ------------------------------------------------------------------ measurement on rendered frames
def regions(fs, i):
    """label name -> bool mask for rendered frame i.  Head and torso are separate sprites."""
    f = fs.frames[i]
    return {n: f["label"] == li for li, n in enumerate(fs.names) if li > 0}


def pair_change(ma, mb, ia, ib, ca, cb, shift):
    """ma/mb: a part's visible mask in frames A/B; ia/ib colours (rgb arrays); ca/cb: 'covered by
    any other part' masks.  B is shifted by -shift (the part's own offset change) before comparing.
    Returns (changed, total): pixels of the part in A or shifted B whose colour or presence differs,
    pixels hidden by another part in the other frame are not counted."""
    dx, dy = shift
    H, W = ma.shape

    def back(a, fill):
        p = np.pad(a, ((abs(dy), abs(dy)), (abs(dx), abs(dx))) + ((0, 0),) * (a.ndim - 2), constant_values=fill)
        return p[abs(dy) + dy:abs(dy) + dy + H, abs(dx) + dx:abs(dx) + dx + W]
    mb2, cb2, ib2 = back(mb, False), back(cb, False), back(ib, 0)
    both = ma & mb2
    diff = both & (ia != ib2).any(-1) if ia.ndim == 3 else both & (ia != ib2)
    only_a = ma & ~mb2 & ~cb2
    only_b = mb2 & ~ma & ~ca
    changed = int(diff.sum() + only_a.sum() + only_b.sum())
    total = int((ma | mb2).sum() - (ma & ~mb2 & cb2).sum() - (mb2 & ~ma & ca).sum())
    return changed, total


def _search(ma, mb, ia, ib, ca, cb, rad=3):
    best = None
    for dy in range(-rad, rad + 1):
        for dx in range(-rad, rad + 1):
            c, t = pair_change(ma, mb, ia, ib, ca, cb, (dx, dy))
            r = c / max(t, 1)
            if best is None or r < best[0]:
                best = (r, c, t)
    return best


def measure(fs, known=True, head_row=None):
    """Per part: mean/max percentage of its pixels that change between consecutive frames (loop),
    after shifting by its known offset (`known`) or the best whole-pixel shift (old frames).
    For limbs two figures: all pairs, and pairs whose sprite variant (rotation step) is unchanged.
    Returns {part: {"all": (mean, max), "same": (mean, max) or None, "n_same": int}}."""
    n = len(fs.frames)
    rgb = [to_rgba(f["idx"], fs.palette)[..., :3] for f in fs.frames]
    reg = [regions(fs, i) for i in range(n)]
    anyp = [(f["label"] > 0) for f in fs.frames]
    out = {}
    for nm in fs.names[1:]:
        allv, samev = [], []
        for i in range(n):
            j = (i + 1) % n
            ma, mb = reg[i][nm], reg[j][nm]
            ca, cb = anyp[i] & ~ma, anyp[j] & ~mb
            if known:
                oa, ob = fs.frames[i]["offset"][nm], fs.frames[j]["offset"][nm]
                c, t = pair_change(ma, mb, rgb[i], rgb[j], ca, cb, (ob[0] - oa[0], ob[1] - oa[1]))
                r = c / max(t, 1)
            else:
                r = _search(ma, mb, rgb[i], rgb[j], ca, cb)[0]
            allv.append(100 * r)
            if known and fs.frames[i]["variant"][nm] == fs.frames[j]["variant"][nm]:
                samev.append(100 * r)
        out[nm] = {"all": (float(np.mean(allv)), float(np.max(allv))),
                   "same": (float(np.mean(samev)), float(np.max(samev))) if samev else None,
                   "n_same": len(samev)}
    return out


# ------------------------------------------------------------------ whole bake
def bake_hero(png, joints, even_master=True):
    """Both masters of one hero.  Returns dict with FrameSets and timings.
    A: 56 master, 112 = 2x nearest.  B: 112 master with even origins, 56 = 2:1 of it."""
    from .fit import fit_still
    from .gear import load_gear
    t0 = time.time()
    fitted = fit_still(png, joints)
    gears = load_gear(png)
    t1 = time.time()
    ha = Hero(png, joints, 56, False, fitted, gears)
    A56 = ha.bake()
    A112 = A56.up2()
    t2 = time.time()
    hb = Hero(png, joints, 112, True, fitted, gears)
    B112 = hb.bake()
    B56 = B112.down2()
    t3 = time.time()
    return {"A56": A56, "A112": A112, "B112": B112, "B56": B56, "heroA": ha, "heroB": hb,
            "seconds": {"fit": t1 - t0, "master56_and_2x": t2 - t1, "master112_and_2to1": t3 - t2,
                        "total": t3 - t0}}

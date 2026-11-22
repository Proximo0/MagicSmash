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

STEP = 11.25           # degrees between the rotations a limb may take
MAX_STEP = 8           # +-90 degrees
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
MAX_STANCE_BEND = 15.0  # degrees of knee bend a stance leg may have
MAX_SWING_BEND = 50.0   # ... and a swing leg
NB = 8                 # bins along a leg segment for its width and colour profile


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


# ------------------------------------------------------------------ outline, joints, holes
def fill_disc(arr, c, r, dark, near=2.0):
    """Close holes (-1) within r of c with the commonest non-outline colour among the opaque pixels
    within `near` px (any colour when only outline is there): a rounded joint cap with no dark ring."""
    h, w = arr.shape
    ys, xs = np.mgrid[0:h, 0:w]
    hole = (np.hypot(xs + 0.5 - c[0], ys + 0.5 - c[1]) <= r) & (arr < 0)
    if not hole.any():
        return arr
    out = arr.copy()
    K = len(dark)
    for y, x in np.argwhere(hole):
        win = arr[max(0, int(y - near)):int(y + near) + 1, max(0, int(x - near)):int(x + near) + 1]
        win = win[win >= 0]
        if len(win) == 0:
            continue
        lit = win[~dark[win]]
        out[y, x] = np.bincount(lit if len(lit) else win, minlength=K).argmax()
    return out


def tidy_sprite(sp, min_px=4):
    """Fill 1 px slits and pinholes inside a sprite (colour of the left / upper neighbour) and drop
    loose bits of fewer than min_px pixels, so a turned part is one clean shape."""
    a = sp.copy()
    for _ in range(2):
        p = np.pad(a, 1, constant_values=-1)
        lr = (a < 0) & (p[1:-1, :-2] >= 0) & (p[1:-1, 2:] >= 0)
        a = np.where(lr, p[1:-1, :-2], a)
        p = np.pad(a, 1, constant_values=-1)
        ud = (a < 0) & (p[:-2, 1:-1] >= 0) & (p[2:, 1:-1] >= 0)
        a = np.where(ud, p[:-2, 1:-1], a)
    op = a >= 0
    seen = np.zeros(op.shape, bool)
    for y, x in np.argwhere(op):
        if seen[y, x]:
            continue
        comp, todo = [(y, x)], [(y, x)]
        seen[y, x] = True
        while todo:
            cy, cx = todo.pop()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (cy + dy, cx + dx)
                if 0 <= q[0] < op.shape[0] and 0 <= q[1] < op.shape[1] and op[q] and not seen[q]:
                    seen[q] = True
                    todo.append(q)
                    comp.append(q)
        if len(comp) < min_px:
            for q in comp:
                a[q] = -1
    return a


def _ring(op):
    p = np.pad(op, 1, constant_values=False)
    inner = p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    return op & ~inner


def clean_outline(idxs, dark, K):
    """Despeckle on the reduced parts BEFORE they are cut into sprites.  Per side (near parts,
    far parts): the silhouette ring of the parts' union.  When most of the ring is outline colour
    the whole ring becomes one continuous 1 px outline in the commonest outline colour; otherwise
    the ring has no outline and its dark dots are replaced by the colour next to them."""
    for far in (False, True):
        names = [n for n in idxs if n.startswith("far_") == far]
        if not names:
            continue
        union = np.zeros(idxs[names[0]].shape, bool)
        for n in names:
            union |= idxs[n] >= 0
        ring = _ring(union)
        cols = np.concatenate([idxs[n][ring & (idxs[n] >= 0)] for n in names]).astype(int)
        if len(cols) == 0:
            continue
        isd = dark[cols]
        if isd.mean() >= 0.5:
            oc = int(np.bincount(cols[isd], minlength=K).argmax())
            for n in names:
                m = ring & (idxs[n] >= 0)
                idxs[n][m] = oc
        else:
            for n in names:
                a = idxs[n]
                for y, x in np.argwhere(ring & (a >= 0) & dark[np.clip(a, 0, K - 1)]):
                    win = a[max(0, y - 1):y + 2, max(0, x - 1):x + 2].ravel()
                    win = win[(win >= 0) & ~dark[np.clip(win, 0, K - 1)]]
                    if len(win):
                        a[y, x] = np.bincount(win, minlength=K).argmax()
    return idxs


def _placed(sp, org, shape):
    m = np.zeros(shape, bool)
    h, w = sp.shape
    x0, y0 = int(org[0]), int(org[1])
    xa, ya, xb, yb = max(x0, 0), max(y0, 0), min(x0 + w, shape[1]), min(y0 + h, shape[0])
    if xb > xa and yb > ya:
        m[ya:yb, xa:xb] = sp[ya - y0:yb - y0, xa - x0:xb - x0] >= 0
    return m


def joint_holes(parent, child, joint, rr):
    """Background pixels that show between two parts at their joint: a 1 px slit (opaque on both
    sides, left-right or up-down) within rr of the joint, plus 1 when the two parts are not even
    4-connected.  parent/child: bool masks of the placed sprites."""
    U = parent | child
    p = np.pad(U, 1, constant_values=False)
    slit = ~U & ((p[1:-1, :-2] & p[1:-1, 2:]) | (p[:-2, 1:-1] & p[2:, 1:-1]))
    ys, xs = np.mgrid[0:U.shape[0], 0:U.shape[1]]
    near = (np.abs(xs + 0.5 - joint[0]) <= rr) & (np.abs(ys + 0.5 - joint[1]) <= rr)
    n = int((slit & near).sum())
    pts = np.argwhere(U)
    if len(pts):
        seen = {tuple(pts[0])}
        todo = [tuple(pts[0])]
        while todo:
            y, x = todo.pop()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (y + dy, x + dx)
                if 0 <= q[0] < U.shape[0] and 0 <= q[1] < U.shape[1] and U[q] and q not in seen:
                    seen.add(q)
                    todo.append(q)
        if len(seen) < len(pts):
            n += 1
    return n


def prop_clear_of_face(frame_set, limit=0.02):
    """Gate: the prop's pixels inside the head's bounding box, as a share of the head's pixels,
    must be <= limit (2%) in every frame.  Returns (ok, worst share)."""
    worst = 0.0
    for f in frame_set.frames:
        if f.get("prop") is None:
            continue
        x0, y0, m = f["prop"]
        hx0, hy0, hx1, hy1 = f["head_box"]
        sub = m[max(0, hy0 - y0):max(0, hy1 - y0), max(0, hx0 - x0):max(0, hx1 - x0)]
        # the prop's pixels that fall inside the box
        inside = 0
        ys, xs = np.nonzero(m)
        gx, gy = xs + x0, ys + y0
        inside = int(((gx >= hx0) & (gx < hx1) & (gy >= hy0) & (gy < hy1)).sum())
        worst = max(worst, inside / max(f["head_n"], 1))
    return worst <= limit, worst


def count_hole_frames(frame_set):
    """Number of (frame, leg, joint) cases with a hole between thigh and shin or shin and foot."""
    return sum(1 for f in frame_set.frames for v in f.get("holes", {}).values() if v > 0)


def enclosed_holes(mask):
    """Background pixels fully enclosed by `mask` (not reachable from the border): a hole inside a leg."""
    p = np.pad(~mask, 1, constant_values=True)
    reach = np.zeros_like(p)
    reach[0, :] = reach[-1, :] = reach[:, 0] = reach[:, -1] = True
    reach &= p
    while True:
        n = reach.copy()
        n[1:, :] |= reach[:-1, :]
        n[:-1, :] |= reach[1:, :]
        n[:, 1:] |= reach[:, :-1]
        n[:, :-1] |= reach[:, 1:]
        n &= p
        if (n == reach).all():
            break
        reach = n
    return int((p & ~reach).sum())


def leg_gates(fs, tol_deg=4.0, width_tol=0.12):
    """Gates on the drawn legs of a master FrameSet.  Returns {name: number of failing cases}:
      leg_width: a segment's area per unit length differs by more than width_tol between frames
                 (the width profile is the still's and fixed; this checks the raster);
      leg_hole: background pixels enclosed by a leg;
      knee_backwards: the shin turned the wrong way past the thigh by more than tol_deg;
      planted_sole: a planted foot whose lowest pixel is not on the ground row;
      two_feet: one foot not visible although it is not fully behind the other."""
    bad = {"leg_width": 0, "leg_hole": 0, "knee_backwards": 0, "planted_sole": 0, "two_feet": 0}
    for side in ("near", "far"):
        for seg in (0, 1):
            a = np.array([f["legs"][side]["area"][seg] for f in fs.frames])
            bad["leg_width"] += int((np.abs(a - a.mean()) > width_tol * a.mean()).sum())
    for f in fs.frames:
        for side in ("near", "far"):
            lg = f["legs"][side]
            bad["leg_hole"] += int(f["holes"][side] > 0)
            bad["knee_backwards"] += int(lg["flex"] < -tol_deg)
            if lg["planted"] and lg["sole"] != fs.foot_y - 1:
                bad["planted_sole"] += 1
        fn, ff = f["feet"].get("near"), f["feet"].get("far")
        if fn is not None and ff is not None:
            lab = f["label"]
            li = {n: k for k, n in enumerate(fs.names)}
            seen_far = int((lab == li["far_foot"]).sum()) > 0
            hidden = bool((ff & ~fn).sum() == 0)
            if not seen_far and not hidden:
                bad["two_feet"] += 1
    return bad


def prop_clear_of_legs(fs, limit=0.02):
    """Gate: prop pixels on leg pixels, as a share of the prop's pixels, <= limit in every frame.  (ok, worst)."""
    worst = 0.0
    for f in fs.frames:
        if f.get("prop") is None:
            continue
        x0, y0, m = f["prop"]
        ys, xs = np.nonzero(m)
        gx, gy = xs + x0, ys + y0
        H, W = f["legmask"].shape
        ok = (gx >= 0) & (gx < W) & (gy >= 0) & (gy < H)
        worst = max(worst, float(f["legmask"][gy[ok], gx[ok]].sum()) / max(len(xs), 1))
    return worst <= limit, worst


def prop_upright(fs, tol=10.0):
    """Gate: a prop longer than the torso is within tol degrees of vertical and in front of the body
    (its pixels' centre ahead of the pelvis column).  Returns True when it holds (or the prop is short)."""
    pi = fs.prop_info
    if not pi or not pi["long"]:
        return True
    if abs(pi["tilt"]) > tol:
        return False
    for f in fs.frames:
        x0, y0, m = f["prop"]
        if np.nonzero(m)[1].mean() + x0 < fs.pel_x:
            return False
    return True


def walk_gates(fs, bend=15.0, swing=50.0, pelvis=0.95):
    """Gates on the solved walk of a master FrameSet.  Returns (failing cases per gate, stats):
      stance_bend: a planted leg's knee bent more than `bend`; swing_bend: a swinging leg's more than `swing`;
      swing_lift: a swing foot higher than 4 x m px (8 at 112) or a foot never lifted 2 x m px (4 at 112)
                  (a short-legged hero may be given less; see stats);
      pelvis_height: hip height above the flat ankle row (without the bob) < pelvis x leg length;
      trunk_lean: the trunk's lean is not 0 to 6 degrees forward;
      foot_slide: a planted foot's contact point does not move back by exactly the step between two frames."""
    w = fs.walk
    m = w["m"]
    bad = dict.fromkeys(("stance_bend", "swing_bend", "swing_lift", "pelvis_height", "trunk_lean", "foot_slide"), 0)
    stats = {"stride": w["stride"], "max_stance_bend": 0.0, "max_swing_bend": 0.0, "min_pelvis_ratio": 9.0,
             "lean": w["lean"], "peak_lift": 0, "foot_slide_px": 0}
    for side in ("near", "far"):
        lifts = []
        for i, f in enumerate(fs.frames):
            lg = f["legs"][side]
            if lg["planted"]:
                stats["max_stance_bend"] = max(stats["max_stance_bend"], lg["flex"])
                bad["stance_bend"] += int(lg["flex"] > bend + 0.5)
            else:
                stats["max_swing_bend"] = max(stats["max_swing_bend"], lg["flex"])
                bad["swing_bend"] += int(lg["flex"] > swing + 0.5)
                lifts.append(lg["lift"])
                bad["swing_lift"] += int(lg["lift"] > 4 * m)
            ratio = lg["hdy"] / w["L"]
            stats["min_pelvis_ratio"] = min(stats["min_pelvis_ratio"], ratio)
            bad["pelvis_height"] += int(ratio < pelvis)
            g = fs.frames[(i + 1) % len(fs.frames)]["legs"][side]
            if lg["planted"] and g["planted"]:
                err = abs((g["cx"] - lg["cx"]) + w["step"])
                stats["foot_slide_px"] = max(stats["foot_slide_px"], err)
                bad["foot_slide"] += int(err > 0)
        stats["peak_lift"] = max(stats["peak_lift"], max(lifts) if lifts else 0)
    bad["swing_lift"] += int(stats["peak_lift"] < 2 * m)
    bad["trunk_lean"] += int(not (0.0 <= w["lean"] <= 6.0))
    return bad, stats


def no_skin_below_belt(fs):
    """Gate: far-arm pixels in a skin colour below the belt row (a hand on the legs).  Returns the count."""
    li = {n: k for k, n in enumerate(fs.names)}
    n = 0
    for f in fs.frames:
        for nm in ("far_upper", "far_fore"):
            if nm not in li:
                continue
            ys, xs = np.nonzero(f["label"] == li[nm])
            n += int((ys > f["belt"]).sum()) if False else int(
                sum(1 for y, x in zip(ys, xs) if y > f["belt"] and int(f["idx"][y, x]) in fs.skin))
    return n


# ------------------------------------------------------------------ the hero
CLOTH = ("robe", "cape")


class Hero:
    """Everything a bake needs for one master size: grid, palette, sprites, rig, poses."""

    def __init__(self, png, joints, master=56, even=False, fitted=None, gears=None):
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
        self._choose_carry()

    # -- 1 + 2: one reduction, one palette, small sprites
    def _palette_and_parts(self):
        ch, g, rig = self.ch, self.grid, self.rig
        srcs = [(p.img, self.k ** 2) for p in ch.parts.values()]
        from .gear import scale_of
        for ge in self.gears:
            srcs.append((ge.img, scale_of(ch, ge) ** 2))
        self.palette = build_palette(srcs, PALETTE_N)
        pal = self.palette
        self.K = len(pal)
        self.dark = _luma(pal) < DARK_LUMA
        near_all = np.zeros(ch.still.shape[:2], bool)
        for nm, p in ch.parts.items():
            if not nm.startswith("far_"):
                near_all |= p.mask
        full = {nm: g.reduce(to_index(p.img, pal), self.K, self.dark) for nm, p in ch.parts.items()}
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
        idxs = {}
        for nm, (dom, cov) in full.items():
            keep = cov >= COVER
            if not nm.startswith("far_"):
                keep |= gaps & (owner == nm)
            idxs[nm] = np.where(keep, dom, -1).astype(np.int16)
        clean_outline(idxs, self.dark, self.K)          # despeckle BEFORE cutting the sprites
        self.sprites, self.pivot = {}, {}
        neck_row = int(math.ceil(g.G(rig.j["neck"])[1]))
        for nm, idx in idxs.items():
            if nm == "torso":
                head, torso = idx.copy(), idx.copy()
                head[neck_row:] = -1
                torso[:neck_row] = -1
                self.sprites["head"] = trim(head, 0, 0, self.even)
                self.sprites["torso"] = trim(torso, 0, 0, self.even)
            else:
                self.sprites[nm] = trim(idx, 0, 0, self.even)
        self._lean_shear()
        self.cloth = [n for n, p in ch.parts.items() if getattr(p, "kind", "rigid") in CLOTH]
        self.body_parts = [n for n in self.sprites if n not in LIMBS]
        for nm in LIMBS:
            if nm in ch.parts:
                self.pivot[nm] = tuple(int(rnd(v, self.q)) for v in g.G(rig.j[ch.parts[nm].pivot]))
        self._rot = {}
        self._cloth = {}
        self._leg_look()
        ff = self.variant("far_fore", 0)[0] if "far_fore" in self.sprites else None
        self.skin = set()
        self.walk = None
        self.prop_info = None
        if ff is not None and (ff >= 0).any():
            rows = np.nonzero((ff >= 0).any(1))[0]
            low = ff[rows[int(len(rows) * 0.7):]]
            cols, cnt = np.unique(low[low >= 0], return_counts=True)
            self.skin = {int(c) for c in cols if not self.dark[c] and self.palette[c][0] > self.palette[c][2]
                         and self.palette[c][1] >= 70 and self.palette[c][0] >= 150}
            if not self.skin and len(cols):
                self.skin = {int(cols[np.argmax(cnt)])}

    def variant(self, nm, step):
        """The sprite of limb `nm` turned by `step` steps of STEP degrees: (idx, ox, oy), origin
        relative to the part's integer pivot.  Computed once; the two ends of the bone get a
        rounded joint cap (fill_disc) so neighbouring parts always overlap."""
        key = (nm, step)
        if key not in self._rot:
            full = np.full(self.canvas[::-1], -1, np.int16)
            sp, ox, oy = self.sprites[nm]
            full[oy:oy + sp.shape[0], ox:ox + sp.shape[1]] = sp
            piv = self.pivot[nm]
            out, rx, ry = rotate_idx(full, piv, step * STEP, self.K, self.dark)
            bone = nm.split("_")[1]
            rad = self.ch.info["radius"].get(bone)
            if rad and bone in CHILD:
                r = 0.9 * rad * self.k
                a, b = CHILD[bone]
                vec = (self.rig.j[b] - self.rig.j[a]) * self.k
                for pt in ((0.0, 0.0), tuple(rot2(vec, step * STEP))):
                    out = fill_disc(out, (pt[0] - rx, pt[1] - ry), r, self.dark)
            out = tidy_sprite(out)
            out, rx, ry = trim(out, rx, ry, self.even)
            self._rot[key] = (out, rx, ry)
        return self._rot[key]

    def cloth_variant(self, nm, state):
        """Two states of a skirt / robe / cape: state 1 has the bottom rows shifted back by 2 px at
        112 (1 px at 56).  Both made once."""
        key = (nm, state)
        if key not in self._cloth:
            sp, ox, oy = self.sprites[nm]
            if state == 0:
                self._cloth[key] = (sp, ox, oy)
            else:
                sh = int(2 * self.m)
                h, w = sp.shape
                out = np.full((h, w + sh), -1, np.int16)
                r0 = int(h * 0.55)
                r0 -= r0 % 2
                out[:r0, sh:] = sp[:r0]
                out[r0:, :w] = sp[r0:]
                self._cloth[key] = (out, ox - sh, oy)
        return self._cloth[key]

    # -- poses: the old walk's angles, quantised
    def _poses(self):
        from .motion import Gait, fit_walk, walk
        from .bake import BODY_H, STRIDE_QUANT
        ch, rig = self.ch, self.rig
        motion = ch.walk_motion()
        gait = Gait(rig, motion)
        self.Jrest = rig.fk(rig.rest_pose())
        # the far arm swings freely (opposite the near leg) even when the near hand carries a prop
        if not ch.step_px or ch.step_px <= 0:
            free = walk()
        else:
            q = STRIDE_QUANT * (ch.body_h / BODY_H) / ch.k
            target = max(q, round(2 * ch.step_px * 0.95 / q) * q)
            free = fit_walk(rig, target / 2.0 / 0.95, exact=target, quantum=q, arm=1.0)
        gait2 = Gait(rig, free)
        self.J, self.J2, self.contact = [], [], []
        for i in range(NFRAMES):
            pose, contact = gait.pose(i / NFRAMES)
            self.contact.append(contact)
            self.J.append(rig.fk(pose))
            self.J2.append(rig.fk(gait2.pose(i / NFRAMES)[0]))
        ph = np.array([J["pelvis"][1] for J in self.J])
        self.bob_up = np.zeros(NFRAMES, bool)
        self.bob_up[np.argsort(ph, kind="stable")[:NFRAMES // 2]] = True    # (old gait; unused by the solved walk)
        self._solve_walk()

    def step_of(self, J, nm):
        side = "far" if nm.startswith("far_") else "near"
        a, b = {"upper": ("shoulder", "elbow"), "fore": ("elbow", "wrist"), "thigh": ("hip", "knee"),
                "shin": ("knee", "ankle"), "foot": ("heel", "toe")}[nm.split("_")[1]]
        ra, rb = self.rig.j[a], self.rig.j[b]
        d = screen_angle(J[side + "." + b] - J[side + "." + a]) - screen_angle(rb - ra)
        return int(max(-MAX_STEP, min(MAX_STEP, round(wrap180(d) / STEP))))

    # -- legs are DRAWN: tapered capsules + knee disc, coloured from the still; boots are 3-angle sprites
    def _lean_shear(self):
        """The trunk is the still's, never resampled.  If the still leans back, the rows of head and torso above the
        pelvis are shifted forward by whole pixels (a staircase, made once) to a 1.5 degree forward lean."""
        g, rig, q = self.grid, self.rig, self.q
        rest = float(rig.rest["lean"])
        self.lean_eff = rest
        self.shear_rows = None
        if 0.0 <= rest <= 6.0:
            return
        want = math.tan(math.radians(1.5 - rest))
        pel = float(g.G(rig.j["pelvis"])[1])
        self._pel_row = pel
        self._shear_tan = want
        for nm in ("head", "torso"):
            sp, ox, oy = self.sprites[nm]
            h, w = sp.shape
            sh = [rnd(max(0.0, pel - (oy + r + 0.5)) * want, q) for r in range(h)]
            out = np.full((h, w + max(sh) + (max(sh) % q)), -1, np.int16)
            for r in range(h):
                out[r, sh[r]:sh[r] + w] = sp[r]
            self.sprites[nm] = (out, ox, oy)
        neck = float(g.G(rig.j["neck"])[1])
        top = float(g.G(rig.j["head_top"])[1])
        self.lean_eff = rest + math.degrees(math.atan2(rnd(max(0.0, pel - neck) * want, q), pel - neck))
        self.shear_rows = True

    def _shear_at(self, y):
        """Forward shift (whole px) of the trunk at canvas row y."""
        if not getattr(self, "shear_rows", None):
            return 0
        return rnd(max(0.0, self._pel_row - y) * self._shear_tan, self.q)

    def _leg_look(self):
        ch, rig, k, pal = self.ch, self.rig, self.k, self.palette
        K = self.K
        pidx = {nm: to_index(ch.parts[nm].img, pal) for nm in ch.parts if nm.endswith(("thigh", "shin"))}
        allc = np.concatenate([to_index(p.img, pal)[p.mask] for nm, p in ch.parts.items() if not nm.startswith("far_")])
        dk = allc[self.dark[allc]]
        self.outline = int(np.bincount(dk, minlength=K).argmax()) if len(dk) else int(np.argmin(_luma(pal)))
        self.look = {}
        for side in ("near", "far"):
            for seg, (a, b) in (("thigh", ("hip", "knee")), ("shin", ("knee", "ankle"))):
                nm = side + "_" + seg
                m = pidx[nm]
                ys, xs = np.nonzero(m >= 0)
                A, B = rig.j[a], rig.j[b]
                d = B - A
                L = float(np.hypot(*d))
                u = d / L
                t = ((xs + 0.5 - A[0]) * u[0] + (ys + 0.5 - A[1]) * u[1]) / L
                ok = (t >= 0) & (t < 1)
                bi = np.floor(t * NB).astype(int)
                cols = m[ys, xs]
                w = np.bincount(bi[ok], minlength=NB) / (L / NB) * k
                w = np.convolve(np.pad(w, 1, mode="edge"), [0.25, 0.5, 0.25], "valid")
                w = np.maximum(w, 3.0 * self.m)
                cp = []
                for b_ in range(NB):
                    c = cols[ok & (bi == b_)]
                    lit = c[~self.dark[c]] if len(c) else c
                    c = lit if len(lit) else c
                    cp.append(int(np.bincount(c, minlength=K).argmax()) if len(c) else -1)
                for b_ in range(NB):
                    if cp[b_] < 0:
                        cp[b_] = next((cp[j] for j in sorted(range(NB), key=lambda j: abs(j - b_)) if cp[j] >= 0), 0)
                self.look[nm] = {"w": w, "c": np.array(cp), "L": L}
        for seg in ("thigh", "shin"):
            nr, fr = self.look["near_" + seg], self.look["far_" + seg]
            fr["c"] = np.array([self._shade(c) if c == n else c for c, n in zip(fr["c"], nr["c"])])
        for lk in self.look.values():
            lk["s"] = np.array([self._shade(c) for c in lk["c"]])

    def _shade(self, c):
        """The palette colour nearest to 0.72 x colour c (one shade darker), never c itself."""
        pal = self.palette.astype(float)
        want = pal[c] * 0.72
        d = ((pal - want) ** 2 * np.array([3, 4, 2])).sum(1)
        d[c] = 1e18
        return int(np.argmin(d))

    def _capsule(self, p0, p1, lk, hip_row=None):
        W, H = self.canvas
        w, cp, sp = lk["w"], lk["c"], lk["s"]
        pad = int(w.max() / 2) + 3
        x0, x1 = max(0, int(min(p0[0], p1[0])) - pad), min(W, int(max(p0[0], p1[0])) + pad + 1)
        y0, y1 = max(0, int(min(p0[1], p1[1])) - pad), min(H, int(max(p0[1], p1[1])) + pad + 1)
        ys, xs = np.mgrid[y0:y1, x0:x1]
        cx, cy = xs + 0.5, ys + 0.5
        dx, dy = float(p1[0] - p0[0]), float(p1[1] - p0[1])
        L = max(math.hypot(dx, dy), 1e-6)
        t = np.clip(((cx - p0[0]) * dx + (cy - p0[1]) * dy) / (L * L), 0, 1)
        qx, qy = cx - p0[0] - t * dx, cy - p0[1] - t * dy
        h = np.interp(t, (np.arange(NB) + 0.5) / NB, w) / 2
        inside = np.hypot(qx, qy) <= h
        if hip_row is not None:
            inside &= cy >= hip_row
        bi = np.clip((t * NB).astype(int), 0, NB - 1)
        nx, ny = -dy / L, dx / L
        if nx * -1.0 + ny * 0.5 < 0:
            nx, ny = -nx, -ny
        s = (qx * nx + qy * ny) / np.maximum(h, 1e-6)
        col = np.where(s > 0.35, sp[bi], cp[bi]).astype(np.int16)
        full = np.zeros((H, W), bool)
        colf = np.full((H, W), -1, np.int16)
        full[y0:y1, x0:x1] = inside
        colf[y0:y1, x0:x1] = col
        return full, colf, L

    def _disc(self, c, r, colour):
        W, H = self.canvas
        ys, xs = np.mgrid[0:H, 0:W]
        m = np.hypot(xs + 0.5 - c[0], ys + 0.5 - c[1]) <= r
        return m, np.full((H, W), colour, np.int16)

    def draw_leg(self, side, hip, knee, ankle):
        """One leg as pixels: (colour HxW, owner HxW: 0 none, 1 thigh, 2 shin, area/length of each segment).
        Widths, colours and bands are the still's, the same in every frame; one 1 px outline round the union."""
        W, H = self.canvas
        th, sh = self.look[side + "_thigh"], self.look[side + "_shin"]
        mt, ct, Lt = self._capsule(hip, knee, th, hip_row=hip[1])
        ms, cs, Ls = self._capsule(knee, ankle, sh)
        mk, ck = self._disc(knee, max(th["w"][-1], sh["w"][0]) / 2, int(th["c"][-1]))
        ma, ca = self._disc(ankle, sh["w"][-1] / 2, int(sh["c"][-1]))
        area = (float(mt.sum()) / max(Lt, 1.0), float(ms.sum()) / max(Ls, 1.0))
        own = np.zeros((H, W), np.int8)
        col = np.full((H, W), -1, np.int16)
        for m, c, o in ((mt, ct, 1), (ms, cs, 2), (mk, ck, 2), (ma, ca, 2)):
            own[m] = o
            col[m] = c[m]
        ring = _ring(own > 0)
        ring[:int(hip[1]) + 1] = False
        col[ring] = self.outline
        return col, own, area

    def _arm_chain(self, steps, side):
        g, Jr, k, q = self.grid, self.Jrest, self.k, self.q
        sh = g.G(Jr[side + ".shoulder"])
        sh = sh + [self._shear_at(sh[1]), 0]
        out, pos = {}, {"shoulder": sh}
        for bone, ja, jb in (("upper", "shoulder", "elbow"), ("fore", "elbow", "wrist")):
            nm = side + "_" + bone
            if nm not in steps:
                continue
            sp, rx, ry = self.variant(nm, steps[nm])
            t = np.array([rnd(pos[ja][0], q), rnd(pos[ja][1], q)])
            out[nm] = (t, np.array([t[0] + rx, t[1] + ry]))
            pos[jb] = pos[ja] + rot2((Jr[side + "." + jb] - Jr[side + "." + ja]) * self.k, steps[nm] * STEP)
        return out

    def _foot_step(self, J, side, planted):
        if planted:
            return 0
        d = wrap180(screen_angle(J[side + ".toe"] - J[side + ".heel"]) - screen_angle(self.rig.j["toe"] - self.rig.j["heel"]))
        return 0 if abs(d) < STEP else (2 if d > 0 else -2)

    def _ankle_ground_y(self, side, step=0):
        """Ankle row that puts the lowest pixel of the foot (turned by `step`) on the ground row."""
        sp, rx, ry = self.variant(side + "_foot", step)
        rows = np.nonzero((sp >= 0).any(1))[0]
        return self.foot_y - 1 - ry - int(rows[-1])

    @staticmethod
    def _flex(hip, knee, ank):
        b1, b2 = knee - hip, ank - knee
        return math.degrees(math.atan2(b1[0] * b2[1] - b1[1] * b2[0], b1 @ b2))

    def _walk_try(self, Hdy, step, peak, i0, gy, hip_x):
        """The 8 frames of a walk with the pelvis Hdy above the flat ankle row (2 px bob at 112: lower at
        the two double-support frames), stance feet moving back `step` px a frame (stride = 4 x step),
        swing feet lifted (0.6, 1, 0.6) x peak.  Returns (legs per frame, metrics)."""
        from .rig import ik2
        rig, k, q, m = self.rig, self.k, self.q, int(self.m)
        l1, l2 = rig.lengths["thigh"] * k, rig.lengths["shin"] * k
        out, st, sw, viol = [], 0.0, 0.0, 0.0
        for i in range(NFRAMES):
            s_n, s_f = (i - i0) % 8, (i - i0 - 4) % 8
            low = s_n in (0, 4)
            hip_y = gy["near"] - Hdy + (m if low else 0)
            legs = {}
            for side, s in (("near", s_n), ("far", s_f)):
                planted = s <= 4
                if planted:
                    x_off, lift = 2 * step - s * step, 0
                else:
                    w = s - 5
                    x_off, lift = -step + (w + 1) * step, rnd((0.6, 1.0, 0.6)[w] * peak, q)
                fs_ = 0          # boots stay flat in this walk (the 3-angle set is kept for later)
                ank = np.array([hip_x[side] + x_off, min(gy[side] - lift, self._ankle_ground_y(side, fs_) - 0)], float)
                if not planted:
                    ank[1] = min(gy[side] - lift, self._ankle_ground_y(side, fs_))
                else:
                    ank[1] = gy[side]
                hip = np.array([hip_x[side], hip_y], float)
                knee, _ = ik2(hip, ank, l1, l2, 1.0)
                knee = np.array([rnd(knee[0], q), rnd(knee[1], q)], float)
                for _ in range(4):
                    if self._flex(hip, knee, ank) >= -3.0:
                        break
                    knee = knee + [q, 0]
                f = self._flex(hip, knee, ank)
                if planted:
                    st = max(st, f)
                else:
                    sw = max(sw, f)
                viol = max(viol, float(np.hypot(*(ank - hip))) - (l1 + l2))
                legs[side] = {"hip": hip, "knee": knee, "ankle": ank, "planted": planted, "foot_step": fs_,
                              "short": max(0.0, float(np.hypot(*(ank - hip))) - (l1 + l2))}
            out.append((legs, low))
        return out, {"stance": st, "swing": sw, "viol": viol}

    def _solve_walk(self):
        """Walk solved from an upright pelvis: fixed height above the ankle row, planted feet placed ahead of /
        under / behind the hip by the stride, swing feet lifted, hip-knee-ankle by 2-bone IK.  The longest
        stride (even px steps) for which every stance knee is bent <= MAX_STANCE_BEND and every swing knee
        <= MAX_SWING_BEND is used; a short-legged hero simply gets a shorter stride."""
        g, rig, k, q, m = self.grid, self.rig, self.k, self.q, int(self.m)
        Jr = self.Jrest
        c = [bool(self.contact[i]["near"]) for i in range(NFRAMES)]
        i0 = next((i for i in range(NFRAMES) if c[i] and not c[i - 1]), 0)
        gy = {s: self._ankle_ground_y(s) for s in ("near", "far")}
        hip_x = {s: rnd(g.G(Jr[s + ".hip"])[0], q) for s in ("near", "far")}
        L = (rig.lengths["thigh"] + rig.lengths["shin"]) * k
        cands = []
        for step in range(q, q * 9, q):
            for Hdy in range(-(-int(math.ceil(L)) // q) * q, int(0.90 * L), -q):
                for peak in (m, 2 * m, 3 * m, 4 * m):
                    fr, met = self._walk_try(Hdy, step, peak, i0, gy, hip_x)
                    pen = (max(met["stance"] - MAX_STANCE_BEND, 0) * 2 + max(met["swing"] - MAX_SWING_BEND, 0)
                           + max(met["viol"] - 0.8, 0) * 20)
                    cands.append(((pen > 0.0, peak < 2 * m, pen if pen > 0 else 0.0, -step, -Hdy, peak), fr, met, step, Hdy, peak))
        best = min(cands, key=lambda c_: c_[0])
        _, fr, met, step, Hdy, peak = best
        rest_y = rnd(g.G(Jr["near.hip"])[1], q)
        self.sched = [(legs, int(legs["near"]["hip"][1] - rest_y), low) for legs, low in fr]
        self.walk = {"step": step, "stride": 4 * step, "Hdy": Hdy, "L": L, "peak": peak, "i0": i0, "gy": gy,
                     "stance_bend": met["stance"], "swing_bend": met["swing"], "feasible": not best[0][0],
                     "lean": self.lean_eff, "m": m}

    # -- one frame, body, arms, legs (the prop is added by `props`)
    def base_frame(self, i):
        ch, rig, q, g = self.ch, self.rig, self.q, self.grid
        steps, origin, T = {}, {}, {}
        for nm in ("near_upper", "near_fore", "far_upper", "far_fore"):
            if nm in ch.parts:
                steps[nm] = self.step_of(self.J2[i] if nm.startswith("far_") else self.J[i], nm)
        legs, bob, low = self.sched[i]
        belt = int(round(g.G(self.Jrest["pelvis"])[1])) + bob       # the belt row
        # the far hand never hangs below the belt (no skin on the legs): the nearest far-arm pose to the gait's
        # (|dupper| + |dfore| steps) whose hand ends above the belt row
        hide_far = False
        if "far_fore" in ch.parts and self.skin:
            hide_far = True
            u0, f0 = steps["far_upper"], steps["far_fore"]
            cands = sorted(((abs(u - u0) + abs(f - f0), u, f) for u in range(-2, 7) for f in range(0, MAX_STEP + 1)))
            for _, u, f in cands:
                trial = dict(steps, far_upper=u, far_fore=f)
                sp = self.variant("far_fore", f)[0]
                org = self._arm_chain(trial, "far")["far_fore"][1]
                rows = np.nonzero(np.isin(sp, list(self.skin)).any(1))[0]
                if len(rows) == 0 or org[1] + bob + rows[-1] <= belt - q:
                    steps["far_upper"], steps["far_fore"] = u, f
                    hide_far = False
                    break
        for side in ("near", "far"):
            for nm, (t, o) in self._arm_chain(steps, side).items():
                T[nm] = t + [0, bob]
                origin[nm] = o + [0, bob]
        H_, W_ = self.canvas[::-1]
        for side in ("near", "far"):
            pa, pb = side + "_upper", side + "_fore"
            if pa not in steps or pb not in steps:
                continue
            ma = _placed(self.variant(pa, steps[pa])[0], origin[pa], (H_, W_))
            spb = self.variant(pb, steps[pb])[0]
            rr = 1.1 * self.ch.info["radius"].get("fore", 5.0) * self.k + 2
            best = None
            for dx, dy in ((0, 0), (0, q), (0, -q), (q, 0), (-q, 0), (q, q), (-q, q), (q, -q), (-q, -q)):
                mb = _placed(spb, origin[pb] + [dx, dy], (H_, W_))
                n = joint_holes(ma, mb, T[pb] + [dx, dy], rr)
                if best is None or n < best[0]:
                    best = (n, dx, dy)
                if n == 0:
                    break
            origin[pb] = origin[pb] + [best[1], best[2]]
            T[pb] = T[pb] + [best[1], best[2]]
        # feet: rigid sprites at the ankle, at most 3 angles
        for side in ("near", "far"):
            lg = legs[side]
            nm = side + "_foot"
            steps[nm] = lg["foot_step"]
            sp, rx, ry = self.variant(nm, lg["foot_step"])
            origin[nm] = np.array([lg["ankle"][0] + rx, lg["ankle"][1] + ry])
        for nm in self.body_parts:
            if nm.endswith(("thigh", "shin", "foot")):
                continue
            sp, ox, oy = self.sprites[nm]
            if nm in self.cloth:
                sp, ox, oy = self.cloth_variant(nm, (i // 4) % 2)
            origin[nm] = np.array([ox, oy + bob])
        return {"steps": steps, "origin": origin, "T": T, "bob": bob, "leg_dy": 0, "legs": legs, "belt": belt, "hide_far": hide_far, "low": low}

    # -- the prop: one sprite, one carry angle for the whole walk
    def _legpx_for(self, i, side):
        key = (i, side)
        if key not in self._lp:
            lg = self.fd[i]["legs"][side]
            self._lp[key] = self.draw_leg(side, lg["hip"], lg["knee"], lg["ankle"])
        return self._lp[key]

    def _leg_mask(self, i):
        fd, (W, H) = self.fd[i], self.canvas
        m = np.zeros((H, W), bool)
        for side in ("near", "far"):
            m |= self._legpx_for(i, side)[1] > 0
            nm = side + "_foot"
            m |= _placed(self.variant(nm, fd["steps"][nm])[0], fd["origin"][nm], (H, W))
        return m

    def _choose_carry(self):
        """Pick the carry angle (and a small forward grip shift) closest to the drawn carry for which the prop stays clear
        of the head's bounding box AND of the legs (<= 1% of its pixels) in all 8 frames.  A prop longer than the torso is
        carried within 10 degrees of vertical."""
        from .gear import place, scale_of
        self._lp = {}
        self.fd = [self.base_frame(i) for i in range(NFRAMES)]
        self.legmask = [self._leg_mask(i) for i in range(NFRAMES)]
        self.carry, self.carry_dphi, self.carry_overlap, self.carry_info = {}, {}, {}, {}
        rig, k, m = self.rig, self.k, int(self.m)
        torso_len = float(np.hypot(*(rig.j["neck"] - rig.j["pelvis"]))) * k
        for ge in self.gears:
            if ge.slot != "near_hand":
                continue
            _, phi0 = place(self.ch, ge, self.Jrest)
            long_ = ge.extent * scale_of(self.ch, ge) > torso_len
            cands = []
            if long_:
                for phi in np.arange(-10.0, 10.01, 2.5):
                    for gx in range(0, 5):
                        cands.append((abs(phi - phi0) + 6.0 * gx, float(phi), gx))
            else:
                for dphi in (0, 11.25, -11.25, 22.5, -22.5, 33.75, -33.75, 45, -45, 56.25, -56.25, 67.5, -67.5):
                    for gx in (0, 1, 2, 3, 4):
                        cands.append((abs(dphi) + 8.0 * gx, phi0 + dphi, gx))
            cands.sort()
            best = None
            for cost, phi, gx in cands:
                cfg = (phi, gx * m)
                ho = max(self._face_overlap(ge, cfg, i) for i in range(NFRAMES))
                lo = max(self._leg_overlap(ge, cfg, i) for i in range(NFRAMES))
                score = max(ho, lo) / 0.02
                if best is None or score < best[0] - 1e-9:
                    best = (score, cfg, phi - phi0, ho, lo)
                if ho <= 0.0 and lo <= 0.01:
                    break
            self.carry[ge.name] = best[1]
            self.carry_dphi[ge.name] = best[2]
            self.carry_overlap[ge.name] = best[3]
            self.carry_info[ge.name] = {"tilt": best[1][0], "long": bool(long_), "legs": best[4]}

    def _leg_overlap(self, ge, cfg, i):
        sp, org = self._prop_org(ge, cfg, i)
        ys, xs = np.nonzero(sp[..., 3] > 0)
        gx, gy = xs + int(org[0]), ys + int(org[1])
        H, W = self.legmask[i].shape
        ok = (gx >= 0) & (gx < W) & (gy >= 0) & (gy < H)
        return float(self.legmask[i][gy[ok], gx[ok]].sum()) / max(len(xs), 1)

    def _prop_org(self, ge, cfg, i):
        from .gear import hand_local, hand_point, scale_of
        fd, rig, Jr, k = self.fd[i], self.rig, self.Jrest, self.k
        phi, gx = cfg
        sp, (ox, oy) = ge.sprite(scale_of(self.ch, ge), phi, int(self.ch.body_h / 56.0))
        pin0 = hand_point(Jr["near.elbow"], Jr["near.wrist"], hand_local(rig))
        v0 = (pin0 - Jr["near.elbow"]) * k
        P = fd["T"]["near_fore"] + np.floor(rot2(v0, fd["steps"]["near_fore"] * STEP)).astype(int)
        org = P + [ox + gx, oy]
        if self.even:
            org = np.array([rnd(org[0], 2), rnd(org[1], 2)])
        return sp, org

    def _face_overlap(self, ge, cfg, i):
        sp, org = self._prop_org(ge, cfg, i)
        hsp, hx, hy = self.sprites["head"]
        h0 = self.fd[i]["origin"]["head"]
        n = int((hsp >= 0).sum())
        ys, xs = np.nonzero(sp[..., 3] > 0)
        gx, gy = xs + org[0], ys + org[1]
        inside = ((gx >= h0[0]) & (gx < h0[0] + hsp.shape[1]) & (gy >= h0[1]) & (gy < h0[1] + hsp.shape[0])).sum()
        return inside / max(n, 1)

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

    def props(self, i):
        from .gear import place, scale_of
        out = {}
        fd = self.fd[i]
        for ge in self.gears:
            lab = "gear:" + ge.name
            if ge.slot == "near_hand":
                sp, org = self._prop_org(ge, self.carry[ge.name], i)
                out[lab] = (self._gear_idx(sp), org, ("carry", 0))
            elif ge.slot in RIGID_PROPS:
                pin, phi = place(self.ch, ge, self.Jrest, None, 0.0)
                sp, (ox, oy) = ge.sprite(scale_of(self.ch, ge), phi, 0)
                P = np.floor(self.grid.G(pin)).astype(int)
                org = P + [ox, oy] + [0, fd["bob"]]
                if self.even:
                    org = np.array([rnd(org[0], 2), rnd(org[1], 2)])
                out[lab] = (self._gear_idx(sp), org, ("rigid", 0))
        return out

    def bake(self):
        """8 frames at the master size: list of dicts (idx, label, offsets ...) + names."""
        order = self.draw_order()
        names = ["bg"] + order
        W, H = self.canvas
        frames = []
        for i in range(NFRAMES):
            fd = self.fd[i]
            props = self.props(i)
            legpx = {s_: self._legpx_for(i, s_) for s_ in ("near", "far")}
            idx = np.full((H, W), -1, np.int16)
            lab = np.zeros((H, W), np.int16)
            offs, variant = {}, {}
            pm = None
            feet = {}
            for li, nm in enumerate(order, 1):
                side = "far" if nm.startswith("far_") else "near"
                if nm in props:
                    sp, org, var = props[nm]
                    variant[nm] = var
                    if nm.startswith("gear:") and nm != "gear:shield" and pm is None:
                        pm = (int(org[0]), int(org[1]), sp >= 0)
                elif nm.endswith(("_thigh", "_shin")) and nm in self.look:
                    lg = fd["legs"][side]
                    col, own, area = legpx[side]
                    m = own == (1 if nm.endswith("thigh") else 2)
                    idx[m] = col[m]
                    lab[m] = li
                    a, b = (lg["hip"], lg["knee"]) if nm.endswith("thigh") else (lg["knee"], lg["ankle"])
                    offs[nm] = (int(a[0]), int(a[1]))
                    variant[nm] = ("drawn", (int(b[0] - a[0]), int(b[1] - a[1])))
                    continue
                elif nm in fd["steps"]:
                    sp = self.variant(nm, fd["steps"][nm])[0]
                    org = fd["origin"][nm]
                    variant[nm] = ("step", fd["steps"][nm])
                    if fd["hide_far"] and nm in ("far_upper", "far_fore"):
                        offs[nm] = (int(org[0]), int(org[1]))        # the far arm would put a hand below the belt
                        continue
                    if nm.endswith("_foot"):
                        feet[side] = _placed(sp, org, (H, W))
                elif nm in self.cloth:
                    st = (i // 4) % 2
                    sp = self.cloth_variant(nm, st)[0]
                    org = fd["origin"][nm]
                    variant[nm] = ("cloth", st)
                else:
                    sp = self.sprites[nm][0]
                    org = fd["origin"][nm]
                    variant[nm] = ("rigid", 0)
                offs[nm] = (int(org[0]), int(org[1]))
                _paste(idx, lab, sp, org, li)
            hs = self.sprites["head"][0]
            ho = fd["origin"]["head"]
            holes, legs = {}, {}
            for side in ("near", "far"):
                col, own, area = legpx[side]
                lg = fd["legs"][side]
                holes[side] = enclosed_holes((own > 0) | feet[side]) if side in feet else enclosed_holes(own > 0)
                a, b, c = lg["hip"], lg["knee"], lg["ankle"]
                cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
                ang = math.degrees(math.atan2(cross, (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1])))
                rows = np.nonzero(feet[side].any(1))[0] if side in feet else []
                cx = int(np.nonzero(feet[side][rows[-1]])[0].min()) if len(rows) else -1
                legs[side] = {"planted": lg["planted"], "flex": ang, "area": area, "hip": tuple(a), "knee": tuple(b),
                              "ankle": tuple(c), "sole": int(rows[-1]) if len(rows) else -1,
                              "lift": (self.foot_y - 1 - int(rows[-1])) if len(rows) else 0, "cx": cx,
                              "hdy": float(self.walk["gy"][side] - a[1] + (int(self.m) if fd["low"] else 0))}
            frames.append({"idx": idx, "label": lab, "offset": offs, "variant": variant, "bob": fd["bob"],
                           "leg_dy": 0, "holes": holes, "prop": pm, "legs": legs, "feet": feet, "belt": fd["belt"],
                           "head_box": (int(ho[0]), int(ho[1]), int(ho[0]) + hs.shape[1], int(ho[1]) + hs.shape[0]),
                           "head_n": int((hs >= 0).sum()), "legmask": self.legmask[i]})
        fs = FrameSet(frames, names, self.palette, self.master, self.foot_y, self.pel_x)
        fs.skin = set(self.skin)
        fs.walk = dict(self.walk)
        fs.prop_info = next(iter(self.carry_info.values()), None)
        return fs


CHILD = {"upper": ("shoulder", "elbow"), "thigh": ("hip", "knee"), "shin": ("knee", "ankle")}


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


def _half_prop(p):
    x0, y0, m = p
    if x0 % 2 or y0 % 2:
        raise ValueError("2:1 needs an even prop origin")
    h, w = m.shape
    m = np.pad(m, ((0, h % 2), (0, w % 2)))
    return x0 // 2, y0 // 2, m.reshape(m.shape[0] // 2, 2, m.shape[1] // 2, 2).any((1, 3))


# ------------------------------------------------------------------ frame sets and the two sizes
class FrameSet:
    def __init__(self, frames, names, palette, master, foot_y, pel_x):
        self.frames, self.names, self.palette = frames, names, palette
        self.master, self.foot_y, self.pel_x = master, foot_y, pel_x
        self.skin = set()

    def rgba(self, i):
        return to_rgba(self.frames[i]["idx"], self.palette)

    def up2(self):
        """Exact 2x nearest: the 112 px frames of a 56 px master."""
        out = []
        for f in self.frames:
            out.append({"idx": f["idx"].repeat(2, 0).repeat(2, 1), "label": f["label"].repeat(2, 0).repeat(2, 1),
                        "offset": {n: (2 * x, 2 * y) for n, (x, y) in f["offset"].items()},
                        "variant": f["variant"], "bob": 2 * f["bob"], "leg_dy": 2 * f["leg_dy"], "holes": f.get("holes", {}), "belt": 2 * f["belt"],
                        "head_box": tuple(2 * v for v in f["head_box"]), "head_n": 4 * f["head_n"],
                        "legmask": f["legmask"].repeat(2, 0).repeat(2, 1),
                        "prop": None if f["prop"] is None else (2 * f["prop"][0], 2 * f["prop"][1],
                                                                f["prop"][2].repeat(2, 0).repeat(2, 1))})
        r = FrameSet(out, self.names, self.palette, self.master * 2, self.foot_y * 2, self.pel_x * 2)
        r.skin = self.skin
        r.prop_info = self.prop_info
        return r

    def down2(self):
        """2:1 dominant colour: the 56 px frames of a 112 px master.  Only when every part origin
        (and the bob) is even, so a part lands on the same pixels in every frame."""
        for f in self.frames:
            if any(x % 2 or y % 2 for x, y in f["offset"].values()) or f["bob"] % 2 or f["leg_dy"] % 2:
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
                        "variant": f["variant"], "bob": f["bob"] // 2, "leg_dy": f["leg_dy"] // 2, "holes": f.get("holes", {}), "belt": f["belt"] // 2,
                        "head_box": tuple(v // 2 for v in f["head_box"]), "head_n": f["head_n"] // 4,
                        "legmask": f["legmask"].reshape(f["legmask"].shape[0] // 2, 2, f["legmask"].shape[1] // 2, 2).any((1, 3)),
                        "prop": None if f["prop"] is None else _half_prop(f["prop"])})
        r = FrameSet(out, self.names, self.palette, self.master // 2, self.foot_y // 2, self.pel_x // 2)
        r.skin = self.skin
        r.prop_info = self.prop_info
        return r


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
        if sum(int(reg[i][nm].sum()) for i in range(n)) < 6 * n:
            out[nm] = {"all": (float("nan"), float("nan")), "same": None, "n_same": 0}
            continue
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

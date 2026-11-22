"""Intake of a still before anything is fitted: background-key cleaning and the native grid.

Key colour (rule G10 on the still, R19 on every baked frame).  The art PC draws on magenta and
keys it out; where the key was soft, a 1-px rim of half-keyed magenta (about 130, 10, 130)
stays around legs and boots and shows as purple pixels in every frame.
  * `key_mask` is the rule's definition of "a key-colour pixel": opaque, red and blue both at
    least KEY_MIN, green at most KEY_GREEN x the smaller of them, red and blue within KEY_BAL
    of each other.  No such pixel may be left in a still or in a baked frame.
  * `clean_key` is our own fix at the source: every pixel of the wider fringe definition
    (`fringe_mask`) within KEY_DEPTH px of the background
    takes the colour of the nearest inside (non-fringe) pixel; alpha stays hard.  Key colour
    deeper than that is not a fringe but an unkeyed patch of background: it is left alone and
    G10 refuses the still.

Native grid (README "Native grid").  The stills are fake pixel art: drawn large and built of
flat blocks a few still px across.  `detect_grid` measures that block size per axis;
`native` makes the native picture, one pixel per block in the block's mode colour, palette
locked; the joints and the cut then live in native px (`scale_layout`).
"""
import numpy as np

from .imgops import dilate, fill

KEY_MIN = 60          # red and blue of a key-colour pixel are at least this
KEY_GREEN = 0.35      # ... green at most this x min(red, blue)
KEY_BAL = 0.20        # ... |red - blue| at most this x max(red, blue)
FRINGE_OVER = 30      # fringe (wider): min(red, blue) - green at least this ...
FRINGE_BAL = 0.35     # ... and |red - blue| at most this x max(red, blue)
KEY_DEPTH = 3         # px: a fringe is at most this deep from the background


def key_mask(rgba):
    """Rule G10 / R19: opaque pixels of the background key's colour (magenta, pure or shaded)."""
    a = rgba.astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lo, hi = np.minimum(r, b), np.maximum(r, b)
    return (a[..., 3] > 0) & (lo >= KEY_MIN) & (g <= KEY_GREEN * lo) & (np.abs(r - b) <= KEY_BAL * hi)


def fringe_mask(rgba):
    """Anything a half-keyed magenta rim can look like (wider than `key_mask`)."""
    a = rgba.astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lo, hi = np.minimum(r, b), np.maximum(r, b)
    return (a[..., 3] > 0) & (lo - g >= FRINGE_OVER) & (np.abs(r - b) <= FRINGE_BAL * hi)


def clean_key(rgba, depth=KEY_DEPTH):
    """Defringe: (cleaned rgba, number of pixels recoloured).  Hard alpha in, hard alpha out."""
    out = rgba.copy()
    out[out[..., 3] < 128] = 0
    out[out[..., 3] >= 128, 3] = 255
    opaque = out[..., 3] > 0
    fr = fringe_mask(out)
    if not fr.any():
        return out, 0
    rim = fr & dilate(~opaque, depth)      # fringe within `depth` px of the background
    if not rim.any():
        return out, 0
    inside = opaque & ~rim
    if not inside.any():          # the whole picture is key colour: nothing to copy from
        return out, 0
    out = fill(out, inside, rim, max_iter=depth + 2)
    out[..., 3] = np.where(opaque, 255, 0)
    return out, int(rim.sum())


# ------------------------------------------------------------------ gear blobs (rule G11)
GEAR_COLOURS = 16     # the still is reduced to this many colours to find rims
GEAR_LIT = 70         # a rim colour's brightest channel is at least this (not an outline)
GEAR_AB = 0.04        # OKLab a,b distance within which palette colours are one rim colour ...
GEAR_L = 0.25         # ... and lightness distance (a rim is shaded round its loop)
GEAR_CLOSE = 2        # px: gaps in a rim this wide are bridged
GEAR_MIN = 0.006      # x body height squared: a smaller enclosed patch is a buckle or a badge
GEAR_FRONT_MAX = 0.25  # share of a gear blob that may lie ahead of the trunk axis in the arm rows


def rimmed_blobs(rgba, body, BH):
    """Large shapes closed in by a rim of one lit colour (a shield's metal edge round its
    field): list of (mask, rim rgb).  Method: the picture is cut to GEAR_COLOURS colours; for
    every lit colour, the pixels of it and of its shades (GEAR_AB, GEAR_L) are closed by
    GEAR_CLOSE px, and every patch of the body they wall in completely that is at least
    GEAR_MIN x BH^2 is a blob (the rim included).  Plain clothing is not walled in by a rim of
    another colour; a shield, buckler or framed pack is."""
    from .colour import quantize, to_oklab
    from .imgops import components
    img = rgba.copy()
    img[~body] = 0
    q, pal = quantize(img, GEAR_COLOURS)
    if not len(pal):
        return []
    lab = to_oklab(pal.astype(float))
    lit = pal.max(1) >= GEAR_LIT
    code = lambda a: (a[..., 0].astype(np.int32) << 16) | (a[..., 1].astype(np.int32) << 8) | a[..., 2]
    qi, pi = code(q), code(pal)
    ys, xs = np.where(body)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    qi, bd = qi[y0:y1, x0:x1], body[y0:y1, x0:x1]
    out, seen = [], set()
    for i in np.flatnonzero(lit):
        fam = lit & (np.hypot(lab[:, 1] - lab[i, 1], lab[:, 2] - lab[i, 2]) < GEAR_AB) & \
            (np.abs(lab[:, 0] - lab[i, 0]) < GEAR_L)
        key = tuple(np.flatnonzero(fam))
        if key in seen:
            continue
        seen.add(key)
        rim = bd & np.isin(qi, pi[fam])
        if rim.sum() < 0.1 * GEAR_MIN * BH * BH:
            continue
        wall = dilate(rim, GEAR_CLOSE)
        cl, cs = components(np.pad(~wall, 1, constant_values=True))
        outside = cl[0, 0]
        for k, s in cs.items():
            if k == outside or s < GEAR_MIN * BH * BH:
                continue
            hole = (cl == k)[1:-1, 1:-1]
            if (hole & bd).sum() < 0.9 * s:
                continue                      # mostly background: a gap between limbs
            blob = dilate(hole, GEAR_CLOSE + 1) & (hole | wall) & bd
            if any((blob & o[0][y0:y1, x0:x1]).sum() > 0.7 * min(blob.sum(), o[0].sum()) for o in out):
                continue                      # the same shield found through another rim shade
            full = np.zeros_like(body)
            full[y0:y1, x0:x1] = blob
            out.append((full, [int(v) for v in pal[i]]))
    return out


def gear_census(rgba, body, BH, axis_x, row0, row1):
    """Rule G11's measurement: every rimmed blob with its area (x BH^2) and the share of it that
    lies ahead of the trunk axis (`axis_x(y)`: the neck-pelvis line) between rows row0 and row1
    (shoulder to just under the hip), i.e. over the torso's front and the near arm."""
    H, W = body.shape
    yy, xx = np.mgrid[0:H, 0:W]
    front = (xx + 0.5 > axis_x(yy + 0.5)) & (yy >= row0) & (yy <= row1)
    out = []
    for m, rgb in rimmed_blobs(rgba, body, BH):
        ys, xs = np.where(m)
        out.append({"at": [round(float(xs.mean()), 1), round(float(ys.mean()), 1)],
                    "area": round(float(m.sum()) / (BH * BH), 4),
                    "front": round(float((m & front).sum()) / float(m.sum()), 2),
                    "box": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())], "rim": rgb})
    return out


# ------------------------------------------------------------------ native grid
GRID_RANGE = (3.0, 12.0)   # still px: block sizes looked for (under 3 px a block cannot be told
                           # from the resampling blur of the still)
GRID_STEP = 0.02
GRID_SCORE = 1.4           # colour steps on the grid lines are this much stronger than average
GRID_NEAR_BEST = 0.9       # the smallest period scoring this share of the best one is the block
                           # (2 and 3 blocks score as well as 1)
TEXEL_EDGE = 30            # sum of |dRGB| between neighbours that counts as a colour step
OUTLINE_LUMA = 55          # colours darker than this are outline colours
SNAP_OUTLINE = 0.34        # share of a silhouette block an outline colour needs to win it
SNAP_DETAIL = 0.34         # share of a block a dark line needs to win it (a line a third of a
SNAP_DELTA = 45            # block wide survives), being this much darker than the block's mean


def _edge_profile(rgba, axis):
    a = rgba.astype(np.int32)
    op = a[..., 3] > 0
    d = np.abs(np.diff(a[..., :3], axis=axis)).sum(-1)
    both = (op[:, 1:] & op[:, :-1]) if axis == 1 else (op[1:] & op[:-1])
    return (d * both).sum(0 if axis == 1 else 1).astype(float)


def _comb(e):
    """Best (score, period, phase) of a comb laid on the edge profile e: mean edge strength on
    the comb's teeth over the mean everywhere (1 = no grid)."""
    nz = np.flatnonzero(e > 0)
    if len(nz) < 8:
        return []
    lo, hi = nz[0], nz[-1]
    mean = e[lo:hi + 1].mean()
    out = []
    for p in np.arange(GRID_RANGE[0], GRID_RANGE[1] + 1e-9, GRID_STEP):
        best = (0.0, 0.0)
        for ph in np.arange(0.0, p, 0.25):
            b = np.round(ph + np.arange(0, (len(e) - ph) / p) * p).astype(int)
            b = b[(b >= lo) & (b <= hi)]
            if len(b) >= 4:
                s = float(e[b].mean() / mean)
                if s > best[0]:
                    best = (s, ph)
        out.append((best[0], float(p), best[1]))
    return out


def texel_size(rgba):
    """Median distance (still px) between neighbouring colour steps along rows and columns:
    how big the picture's flat patches are when it has no rigid grid."""
    a = rgba.astype(np.int32)
    op = a[..., 3] > 0
    gaps = []
    for axis in (1, 0):
        d = np.abs(np.diff(a[..., :3], axis=axis)).sum(-1)
        both = (op[:, 1:] & op[:, :-1]) if axis == 1 else (op[1:] & op[:-1])
        d = d * both
        if axis == 0:
            d = d.T
        pk = (d[:, 1:-1] > TEXEL_EDGE) & (d[:, 1:-1] >= d[:, :-2]) & (d[:, 1:-1] > d[:, 2:])
        for row in pk:
            x = np.flatnonzero(row)
            if len(x) > 1:
                gaps.append(np.diff(x))
    if not gaps:
        return 0.0
    g = np.concatenate(gaps)
    return float(np.median(g[g <= 16])) if (g <= 16).any() else 0.0


def detect_grid(rgba):
    """The still's native pixel grid: {"found", "cell" (x, y still px per block), "phase" (x, y
    of a grid line), "score" (x, y), "texel"}.  Found = on both axes the colour steps sit on
    the lines of one grid (comb score >= GRID_SCORE) with square blocks.  Real pixel art
    enlarged by a whole factor scores 1.5-1.8 (HR3.1: 6.05 px blocks, 64 native px tall); the
    image model's fake pixel art has blocks of 2-3 px that do not sit on one grid and scores
    about 1.2, which is what random edges score: no grid is reported for it."""
    res = {"found": False, "cell": (0.0, 0.0), "phase": (0.0, 0.0), "score": (0.0, 0.0),
           "texel": texel_size(rgba)}
    best = []
    for axis in (1, 0):
        c = _comb(_edge_profile(rgba, axis))
        if not c:
            return res
        top = max(c)[0]
        best.append(next(x for x in c if x[0] >= GRID_NEAR_BEST * top))   # the smallest period
    (sx, cx, px), (sy, cy, py) = best
    res.update(cell=(cx, cy), phase=(px + 1.0, py + 1.0), score=(round(sx, 2), round(sy, 2)))
    res["found"] = bool(min(sx, sy) >= GRID_SCORE and abs(cx - cy) <= 0.1 * max(cx, cy))
    return res


def _luma(c):
    return (((c >> 16) & 255) * 3 + ((c >> 8) & 255) * 4 + (c & 255) * 2) / 9.0


def snap_to_grid(rgba, cell, origin, cover=None):
    """The picture rebuilt from flat blocks: every block of the grid (cell = (x, y) still px,
    a grid line through `origin`) becomes one colour, the picture keeps its size.  A block is
    opaque when at least half of it is; its colour is the mode of its opaque pixels (so only
    colours of the picture appear), except that a dark line through it (SNAP_DELTA darker than
    the block, at least SNAP_DETAIL of it) and, on the silhouette, an outline colour
    (SNAP_OUTLINE of it) win, so outlines stay closed.  `cover`: bool mask of where the part
    is allowed to be opaque at all (None = anywhere)."""
    H, W = rgba.shape[:2]
    cx = np.floor((np.arange(W) + 0.5 - origin[0]) / cell[0]).astype(np.int64)
    cy = np.floor((np.arange(H) + 0.5 - origin[1]) / cell[1]).astype(np.int64)
    cx -= cx.min()
    cy -= cy.min()
    ncx, ncy = int(cx.max()) + 1, int(cy.max()) + 1
    cid = cy[:, None] * ncx + cx[None, :]
    op = rgba[..., 3] > 0
    out = np.zeros_like(rgba)
    if not op.any():
        return out
    size = np.bincount(cid.ravel(), minlength=ncx * ncy)
    n_op = np.bincount(cid[op], minlength=ncx * ncy)
    on = (n_op * 2 >= size) & (n_op > 0)
    col = (rgba[..., 0].astype(np.int64) << 16) | (rgba[..., 1].astype(np.int64) << 8) | rgba[..., 2]
    key = cid[op] * (1 << 24) + col[op]
    uk, cnt = np.unique(key, return_counts=True)
    ucell, ucol = uk >> 24, uk & 0xFFFFFF
    lum = _luma(ucol)
    share = cnt / np.maximum(n_op[ucell], 1)
    mean = np.bincount(ucell, weights=lum * cnt, minlength=ncx * ncy) / np.maximum(n_op, 1)
    # silhouette blocks: an opaque block with a transparent 4-neighbour
    g = on.reshape(ncy, ncx)
    p = np.pad(g, 1)
    edge = (g & ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])).ravel()
    votes = cnt.astype(float)
    votes = np.where((lum < mean[ucell] - SNAP_DELTA) & (share >= SNAP_DETAIL), votes + n_op[ucell], votes)
    votes = np.where(edge[ucell] & (lum < OUTLINE_LUMA) & (share >= SNAP_OUTLINE),
                     votes + 2 * n_op[ucell], votes)
    order = np.lexsort((votes, ucell))
    last = np.r_[ucell[order][1:] != ucell[order][:-1], True]
    win = np.full(ncx * ncy, -1, np.int64)
    win[ucell[order][last]] = ucol[order][last]
    c = win[cid]
    m = on[cid] & (c >= 0)
    if cover is not None:
        m &= cover
    out[..., 0] = (c >> 16) & 255
    out[..., 1] = (c >> 8) & 255
    out[..., 2] = c & 255
    out[..., 3] = 255
    out[~m] = 0
    return out

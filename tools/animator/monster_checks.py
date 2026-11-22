"""Monster rules M1-M12 (RULES.md).  M10-M12 gate the still before anything is baked (`gate_still`); M1-M9 run on the
baked frames of every set (8 and 4 frames, 56 and 112 px) (`check_all`).  A baked set is `monster.Baked`: frames
(dicts: rgba, label = part index per pixel, meta), the closing frame, meta.  Each check returns a list of strings."""
import math

import numpy as np

from . import monster as mo
from .imgops import components, dilate

DARK_LUMA = 90
EYE_RING_LUMA = 160           # an eye is a dark spot ringed by light (the white of the eye): half its ring at least this bright
MIN_EYE_TARGET = 48            # px: a creature smaller than this at its scale is too small to draw an eye (M8 skipped)
SIZE_BAND = (0.6, 1.3)
FIT_MIN = 0.8
LIMB_ROLES = ('leg_u', 'leg_l', 'foot', 'arm_u', 'arm_f', 'wing_in', 'wing_out')
MIN_LIMB_PX = 1.5
MARGIN = 4


def _all(b):
    return list(b.frames) + [b.closing]


def _tol(b):
    return mo.TOL_PX * b.meta["size_x"]


def _min_px(b):
    return 3 * b.meta["size_x"] ** 2


def luma(a):
    return 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]


# ---------------------------------------------------------------- M1..M9: baked frames
def limb_count(b):
    """M1: the plan's limbs are all there and never more.  Every limb group (leg, arm, wing) has pixels of its own
    in every frame; at most half of the groups of a kind (legs, arms, wings) are hidden behind their partners at once (the
    documented occlusion: a far leg behind the near one, so two legs where the pairs cross); in the ground band of a legged plan the runs of pixels (one per standing leg) never exceed the legs."""
    out = []
    m = b.meta
    for i, f in enumerate(_all(b)):
        fm = f["meta"]
        hidden = {}
        fam_n = {}
        for g, parts in m["limb_groups"].items():
            fam = "leg" if g in m["legs"] else g.split("_")[-1]
            fam_n[fam] = fam_n.get(fam, 0) + 1
            own = sum(fm["area"][p] for p in parts)
            vis = sum(fm["visible"][p] for p in parts)
            if own < _min_px(b):
                out.append(f"frame {i}: limb_count: {g} has no pixels of its own ({own})")
            elif vis < _min_px(b):
                hidden.setdefault(fam, []).append(g)
        for fam, gs in hidden.items():
            if len(gs) > max(1, fam_n[fam] // 2):
                out.append(f"frame {i}: limb_count: {len(gs)} of {fam_n[fam]} {fam}s hidden ({', '.join(gs)}); at most half may hide behind their partners")
        if m["has_legs"]:
            H = f["rgba"].shape[0]
            g = int(round(m["ground_row"]))
            k = max(2, int(round(2 * m["size_x"])))
            band = (f["rgba"][max(0, g - k):g, :, 3] > 0).any(0)
            n = len(_runs(band))
            if n > len(m["legs"]):
                out.append(f"frame {i}: limb_count: {n} legs stand on the ground, the plan has {len(m['legs'])}")
    return out


def _runs(row):
    from .imgops import runs
    return runs(row)


def detached(b):
    """M2: the creature is one connected shape in every frame (8-connected).  Any other piece is refused, except the
    documented orbiting parts of an `orbit` flyer (a piece made mostly of orbit-part pixels)."""
    out = []
    m = b.meta
    orb = {m["parts"].index(p) for p in m["orbit"]}
    for i, f in enumerate(_all(b)):
        lab, sizes = components(f["rgba"][..., 3] > 0)
        if len(sizes) <= 1:
            continue
        main = max(sizes, key=sizes.get)
        for k, s in sizes.items():
            if k == main:
                continue
            ys, xs = np.nonzero(lab == k)
            pl = f["label"][ys, xs]
            if orb and np.isin(pl, list(orb)).mean() >= 0.5:
                continue
            nm = m["parts"][int(np.bincount(pl).argmax())]
            out.append(f"frame {i}: detached: {s} px of {nm} at {int(xs.mean())},{int(ys.mean())} are not connected to the creature")
    return out


def canvas(b):
    """M3: no part leaves the canvas: every frame has the one frame size and no opaque pixel on its outer ring."""
    out = []
    shapes = {f["rgba"].shape for f in _all(b)}
    if len(shapes) != 1:
        out.append(f"canvas: frames differ in size: {sorted(shapes)}")
    for i, f in enumerate(_all(b)):
        a = f["rgba"][..., 3] > 0
        n = int(a[0].sum() + a[-1].sum() + a[:, 0].sum() + a[:, -1].sum())
        if n:
            out.append(f"frame {i}: canvas: {n} opaque px on the edge of the canvas (a part left the frame)")
    return out


def loop_closes(b):
    """M4: the frame after the last is the first, pixel for pixel."""
    f0, fn = b.frames[0]["rgba"], b.closing["rgba"]
    if f0.shape != fn.shape or not np.array_equal(f0, fn):
        d = int((f0 != fn).any(-1).sum()) if f0.shape == fn.shape else -1
        return [f"loop: frame {b.n} differs from frame 0 ({d} px): the cycle does not close"]
    return []


def foot_slide(b):
    """M5 (legged plans): a planted foot does not slide: between two consecutive frames in which the foot is planted
    its move on the canvas plus the body's travel per frame (stride / frames) is within 1 px of the 56 px sprite; a
    planted foot stays on the ground row (its lowest pixel row is the ground row +-1 px); every foot is planted in
    about half the frames; and the stride at the kind's speed gives the cycles per second the game plays it at."""
    m = b.meta
    if not m["has_legs"]:
        return []
    out, tol = [], _tol(b)
    fr = _all(b)
    for leg in m["legs"]:
        planted = [f["meta"]["feet"][leg][2] for f in fr[:-1]]
        if not (0.3 * b.n <= sum(planted) <= 0.7 * b.n + 1):
            out.append(f"{leg}: foot_slide: planted in {sum(planted)} of {b.n} frames")
        for k in range(b.n):
            (x0, y0, p0), (x1, y1, p1) = fr[k]["meta"]["feet"][leg], fr[k + 1]["meta"]["feet"][leg]
            if p0 and p1:
                slide = (x1 - x0) + m["travel_per_frame"]
                if abs(slide) > tol:
                    out.append(f"{leg}: foot_slide: frames {k}-{k + 1}: the planted foot slides {slide:+.2f} px (limit {tol:.0f})")
        for k, f in enumerate(fr):
            x, y, p = f["meta"]["feet"][leg]
            if p:
                low = max(f["meta"]["bottom"][q] or 0 for q in m["leg_parts"][leg]) + 1
                if abs(low - m["ground_row"]) > tol:
                    out.append(f"{leg}: foot_slide: frame {k}: the planted foot is {low - m['ground_row']:+.1f} px off the ground row")
    if m["cycles_per_s"]:
        world_stride = m["stride_px"] * 112.0 / m["size"]
        if abs(m["cycles_per_s"] * world_stride - m["speed_px_s"]) > 0.01 * m["speed_px_s"]:
            out.append("foot_slide: stride x cycles per second is not the kind's speed")
    return out


def area_stable(b):
    """M6: the silhouette's area stays within the plan's tolerance of its median over the cycle (a lost part or a squash
    that grows shows here)."""
    ar = np.array([(f["rgba"][..., 3] > 0).sum() for f in _all(b)], float)
    med = float(np.median(ar))
    tol = b.meta["area_tol"]
    return [f"frame {i}: area: {a:.0f} px is {a / med - 1:+.0%} of the median {med:.0f} (limit {tol:.0%})"
            for i, a in enumerate(ar) if abs(a / med - 1) > tol]


def key_colour(b):
    """M7: no pixel of the background key's colour in any frame: R19's check on monster frames."""
    from . import checks
    return checks.key_colour(_all(b), {})


def head_eye(b):
    """M8: a readable head: in every frame the head part holds an eye, a small dark spot (luma under 90) of at most
    15 % of the head's pixels with at most 30 % of its ring open to the background and at least half of its ring lit (luma 160 or more: the white
    of the eye; a stretch of outline or a seam is long, lies on the edge or is ringed by body colour).  Skipped
    for plans without a head and for a creature under 48 px at that scale."""
    m = b.meta
    if not m["head_part"] or m["target"] < MIN_EYE_TARGET:
        return []
    hi = m["parts"].index(m["head_part"])
    out = []
    for i, f in enumerate(_all(b)):
        a = f["rgba"]
        op = a[..., 3] > 0
        dark = op & (luma(a) < DARK_LUMA)
        lab, sizes = components(dark & (f["label"] == hi))
        cap = max(4, int(0.15 * (f["label"] == hi).sum()))
        ok = False
        for k, s in sizes.items():
            if s > cap:
                continue
            comp = lab == k
            ring = dilate(comp, 1) & ~comp
            lit = ring & op
            if lit.sum() >= 3 and (~op[ring]).mean() <= 0.3 and (luma(a)[lit] >= EYE_RING_LUMA).mean() >= 0.5:
                ok = True
                break
        if not ok:
            out.append(f"frame {i}: head_eye: no readable eye in the {m['head_part']} (a dark spot of 1 to {cap} px ringed by light)")
    return out


def size_band(b):
    """M9: the creature's size is the kind's: the median over the cycle of its longest side is within 0.6 to 1.3 of
    size_px at that scale (112 px for the table's size, half of it at 56)."""
    m = b.meta
    ls = []
    for f in _all(b):
        ys, xs = np.nonzero(f["rgba"][..., 3] > 0)
        ls.append(max(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1))
    r = float(np.median(ls)) / m["target"]
    return [] if SIZE_BAND[0] <= r <= SIZE_BAND[1] else [f"size: the creature is {np.median(ls):.0f} px long, the kind's size is {m['target']:.0f} px"]


BAKED_RULES = [("M1", limb_count), ("M2", detached), ("M3", canvas), ("M4", loop_closes), ("M5", foot_slide),
               ("M6", area_stable), ("M7", key_colour), ("M8", head_eye), ("M9", size_band)]


def check_all(b, still_rgba=None):
    out = []
    for rid, fn in BAKED_RULES:
        out += [(rid, t) for t in fn(b)]
    return out


# ---------------------------------------------------------------- M10..M12: the still
FACING = {"biped": ("pelvis", "head"), "quadruped": ("rump", "nose"), "crawler_skitter": ("rump", "head"),
          "crawler_undulate": ("seg4", "seg0"), "flyer_flap": ("rump", "beak")}


def joints_ok(rgba, data, lay):
    """M12: the joints JSON is complete and sane: format and plan, every joint of the layout given, finite, inside the
    canvas, the ground row inside the picture, a creature that faces right (head or nose ahead of the rump)."""
    out = []
    h, w = rgba.shape[:2]
    J = data.get("joints") or {}
    need = mo.user_joints(lay)
    miss = [k for k in need if k not in J]
    if miss:
        out.append(f"joints missing for plan {lay.plan}/{lay.name}: {', '.join(miss)}")
    for k in need:
        if k in J:
            v = J[k]
            if (not isinstance(v, (list, tuple)) or len(v) != 2 or not all(isinstance(t, (int, float)) and math.isfinite(t) for t in v)):
                out.append(f"joint {k} is not a finite [x, y]")
            elif not (0 <= v[0] < w and 0 <= v[1] < h):
                out.append(f"joint {k} {v} is outside the picture")
    gy = data.get("ground_y")
    if not isinstance(gy, (int, float)) or not (0 < gy <= h):
        out.append('"ground_y" (the row edge under the soles) missing or outside the picture')
    if not miss and lay.name in FACING and not out:
        a, b_ = FACING[lay.name]
        if J[b_][0] <= J[a][0]:
            out.append(f"the creature must face right: {b_} must be ahead of {a} (x {J[b_][0]} <= {J[a][0]})")
    return out


def skeleton_fit(rgba, data, lay):
    """M10: the skeleton lies in the drawing: along every bone of every part (orbit parts: at their joint) at least 80 % of
    the sample points are on the creature's pixels; the creature is inside the picture with 4 px to spare and at least
    160 px long (smaller stills lose the detail the bake needs); every leg, arm and wing is at least 1.5 px wide at the 56 px
    size (a hairline limb breaks into loose pieces when it turns; the width is the part's half width: layout radius or the
    JSON's "radius" for that part)."""
    out = []
    op = rgba[..., 3] > 0
    h, w = op.shape
    ys, xs = np.nonzero(op)
    if not len(xs):
        return ["the still is empty"]
    if xs.min() < MARGIN or ys.min() < MARGIN or xs.max() >= w - MARGIN or ys.max() >= h - MARGIN:
        out.append(f"the creature touches the edge of the picture (needs {MARGIN} px of background all round)")
    if mo.bbox_long(rgba) < 160:
        out.append(f"the creature is {mo.bbox_long(rgba)} px long in the still, at least 160 px needed")
    J = dict(data["joints"])
    mo.derive_joints(lay.name, J)
    r_, _e = mo.resolve(data)
    if r_:
        s56 = r_[2] / 2.0 / mo.bbox_long(rgba)
        for p in lay.parts:
            if p.role in LIMB_ROLES:
                lw = 2 * (data.get("radius") or {}).get(p.name, p.r) * s56
                if lw < MIN_LIMB_PX:
                    out.append(f"{p.name} is {lw:.1f} px wide at the 56 px size, at least {MIN_LIMB_PX} needed: draw it thicker "
                               f"and give its half width in the JSON (\"radius\": {{\"{p.name}\": ...}}) for a creature this small")
    d1 = dilate(op, 1)
    for p in lay.parts:
        hit = n = 0
        for a, b_ in p.bones:
            for t in np.linspace(0, 1, 9):
                x = J[a][0] + t * (J[b_][0] - J[a][0])
                y = J[a][1] + t * (J[b_][1] - J[a][1])
                xi, yi = int(round(x)), int(round(y))
                n += 1
                hit += int(0 <= xi < w and 0 <= yi < h and d1[yi, xi])
        if n and hit / n < FIT_MIN:
            out.append(f"the skeleton of {p.name} lies {1 - hit / n:.0%} outside the drawing (joints {[a for a, _ in p.bones][:1]}..): move the joints onto the creature")
    return out


def limbs_in_still(rgba, data, lay):
    """M11: the still has the plan's limbs and no extra piece: in the ground band (7 rows above the ground row) every run
    of pixels holds a foot joint (a run without one is an extra leg) and every foot joint is on a run (a missing leg); the
    creature is one connected shape (pieces under 9 px are keying dust; a plan with orbit parts may have that many
    pieces more); no key-colour pixel is left after the intake cleaning."""
    from .intake import key_mask
    out = []
    op = rgba[..., 3] > 0
    J = data["joints"]
    if lay.legs:
        g = int(round(data["ground_y"]))
        band = op[max(0, g - 7):g].any(0)
        feet = [J[l.foot][0] for l in lay.legs] + [J[l.toe][0] for l in lay.legs if l.toe]
        runs = [r for r in _runs(band) if r[1] - r[0] >= 1]
        for r in runs:
            if not any(r[0] - 6 <= x <= r[1] + 6 for x in feet):
                out.append(f"an extra leg: pixels on the ground at x {r[0]}-{r[1]} belong to no leg joint")
        for l in lay.legs:
            x = J[l.foot][0]
            if not any(r[0] - 6 <= x <= r[1] + 6 for r in runs):
                out.append(f"leg {l.name} has no foot on the ground at its joint (x {x:.0f})")
    lab, sizes = components(op)
    big = sorted((s for s in sizes.values() if s >= 9), reverse=True)
    if len(big) > 1 + len(lay.orbit):
        out.append(f"{len(big)} separate pieces in the still, at most {1 + len(lay.orbit)} allowed (loose pieces)")
    elif lay.orbit and len(big) < 1 + len(lay.orbit):
        out.append(f"the plan needs {len(lay.orbit)} separate floating pieces, found {len(big) - 1}")
    n = int(key_mask(rgba).sum())
    if n:
        out.append(f"{n} px of the background key's colour left in the still")
    return out


def gate_still(rgba, data, lay):
    """-> [(rule, text)] ; empty = the still may be baked."""
    out = [("M12", t) for t in joints_ok(rgba, data, lay)]
    if out:
        return out
    out += [("M10", t) for t in skeleton_fit(rgba, data, lay)]
    out += [("M11", t) for t in limbs_in_still(rgba, data, lay)]
    return out

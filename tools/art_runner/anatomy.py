"""Anatomy gate for walk sheets: legs and feet checked per frame against the drawn pose skeleton (walk.pose).
check(img, e) -> (ok, notes, per_frame). img: keyed RGB walk sheet (magenta background), e: queue entry."""
import math
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
import walk as W

N = 4
BAND = (0.60, 0.92)     # leg band, fraction of the figure height from its top (below the hips, above the feet/shadow)
LEG_W = 0.045           # expected leg width, fraction of the figure height
LEG_MIN = 0.055          # a blob on a scan row counts as a leg if at least this wide (weapon shafts, strings are thinner)
STRAY_H = 0.4           # a stray-leg blob spans at least 40% of the leg band's height
SHADOW_H = 0.03         # bottom 3% of the figure is ground shadow, ignored for the feet
RUN = 3                 # 3+ leg blobs on this many consecutive scan rows (2.5% of the height apart) = an extra leg
BONE_TOL = 0.08         # a leg-sized blob must lie within this many figure-heights of a skeleton leg bone
FOOT_H = 0.09           # feet: bottom 9% of the figure
SHIN_H = 0.12           # trace the shin this far up from the foot to get its line
FOOT_DELTA = 0.8        # foot backwards: its forward score (-1..1) is this much below the layout's worst foot


NON_BIPED = ("rat", "crow", "spider", "wolf", "wisp", "leech", "light", "toad", "hound", "eye", "barge", "harpy", "bat", "snake", "worm")


def applies(e):
    """The gate is for two-legged walkers drawn over the human pose skeleton (runner.Gen skips the skeleton below 0.6)."""
    hgt = e.get("scale") or e.get("height")
    if e.get("kind") != "walk" or (isinstance(hgt, dict) and float(hgt.get("height") or 1) < 0.6): return False
    return not any(k in (e.get("name") or "") for k in NON_BIPED)


def skel_params(e):
    """fill/leg used for this entry's layout, matching runner.Gen (race height scales the skeleton)."""
    hgt = e.get("scale") or e.get("height")
    hh = hgt if isinstance(hgt, (int, float)) and hgt > 0 else 56
    if isinstance(hgt, dict): hh = round(56 * float(hgt.get("height") or 1.0))
    return min(0.66, 0.56 * hh / 56), (0.47 if hh >= 48 else 0.42)


def bones(w, h, e):
    """Per frame: [(hip, knee, ankle) x2] in pixel coords of a w x h sheet, plus figure top/bottom y."""
    fill, leg = skel_params(e)
    fh = h * fill; top = h * 0.79 - fh; slot = w / N; out = []
    for fr in range(N):
        p = W.pose(fr, slot * fr + slot / 2, top, fh, leg)
        out.append(([(p[8], p[9], p[10]), (p[11], p[12], p[13])], top, top + fh))
    return out


def _fg(img):
    a = np.asarray(img.convert("RGB"))
    return ~((a[..., 0] > 240) & (a[..., 1] < 20) & (a[..., 2] > 240))


def _run(seq, v):
    best = cur = 0
    for c in seq:
        cur = cur + 1 if c >= v else 0; best = max(best, cur)
    return best


def _span(m):
    ys = np.nonzero(m.any(1))[0]
    return (int(ys.min()), int(ys.max())) if len(ys) else (0, 0)


def _feet(f, ft, fb):
    """Per foot blob: (ahead - behind) / total of its sole pixels relative to its traced shin line, -1..1 (+ = forward)."""
    fhh = fb - ft
    if fhh < 20: return []
    leg_w = max(3, int(LEG_W * fhh)); ys1 = int(fb - SHADOW_H * fhh); fy0 = int(fb - FOOT_H * fhh)
    lab, n = ndimage.label(f[fy0:ys1 + 1]); out = []
    for j in range(1, n + 1):
        m = lab == j
        if m.sum() < leg_w * leg_w: continue
        cols = np.nonzero(m[0])[0]
        if len(cols) == 0: continue
        lo, hi = cols.min(), cols.max(); pts = []
        for y in range(fy0, max(ft, fy0 - int(SHIN_H * fhh)), -1):
            r = f[y]; lab_r, _ = ndimage.label(r); ids = set(lab_r[lo:hi + 1][r[lo:hi + 1]]) - {0}
            if not ids: break
            xs = np.nonzero(np.isin(lab_r, list(ids)))[0]
            if xs.max() - xs.min() > 3 * leg_w: break
            lo, hi = xs.min(), xs.max(); pts.append((y, (lo + hi) / 2))
        if len(pts) < 5: continue
        py, px = np.array(pts).T; k_, c_ = np.polyfit(py, px, 1)
        cut = int(len(m) * 2 / 3); sole = np.nonzero(m[cut:]); line = k_ * (sole[0] + fy0 + cut) + c_
        ah, be = (sole[1] > line).sum(), (sole[1] < line).sum()
        if ah + be: out.append((ah - be) / (ah + be))
    return out


def check(img, e, layout=None):
    """layout: the pose layout image this sheet was drawn over (PIL), for the feet check; None skips that check."""
    lay = ndimage.binary_opening(_fg(layout.convert("RGB").resize(img.size)), iterations=1) if layout is not None else None
    w, h = img.size; fg = ndimage.binary_opening(_fg(img), iterations=1); per = []
    for fr, (legs, _top, _bot) in enumerate(bones(w, h, e)):
        x0, x1 = int(w * fr / N), int(w * (fr + 1) / N)
        f = fg[:, x0:x1]; ys = np.nonzero(f.any(1))[0]
        if len(ys) == 0: per.append("empty"); continue
        ft, fb = int(ys.min()), int(ys.max()); fhh = fb - ft; leg_w = max(3, int(LEG_W * fhh))
        fail = []
        # 1) leg count: blobs per scan row through the leg band; 3+ blobs over RUN consecutive rows = an extra leg
        step = max(1, int(fhh * 0.025)); counts = []
        for y in range(int(ft + BAND[0] * fhh), int(ft + BAND[1] * fhh), step):
            lab, n = ndimage.label(f[y]); counts.append(sum((lab == j).sum() >= LEG_MIN * fhh for j in range(1, n + 1)))
        if _run(counts, 3) >= RUN: fail.append("3 legs")
        # 2) stray leg: a leg-sized blob in the band with no skeleton leg bone near it
        bm = Image.new("L", (x1 - x0, h), 0); d = ImageDraw.Draw(bm); tol = BONE_TOL * fhh
        # fit the skeleton to the drawn figure: its height to the figure's, its hips onto the figure's hip-row centre
        sy = fhh / max(1.0, _bot - _top); hy = ft + (legs[0][0][1] - _top) * sy
        hx = np.nonzero(f[int(hy)])[0]; dx = (hx.mean() if len(hx) else legs[0][0][0] - x0) - (legs[0][0][0] - x0)
        for hip, knee, ank in legs:
            pts = [(x - x0 + dx, ft + (y - _top) * sy) for x, y in (hip, knee, ank)]; d.line(pts, fill=255, width=max(3, int(2 * tol)))
        bm = np.asarray(bm) > 0
        band = np.zeros_like(f); y0, y1 = int(ft + BAND[0] * fhh), int(ft + BAND[1] * fhh); band[y0:y1] = f[y0:y1]
        lab, n = ndimage.label(band)
        for j in range(1, n + 1):
            m = lab == j; rows = m.any(1).sum()
            if rows < STRAY_H * (y1 - y0) or m.sum() / max(1, rows) < LEG_MIN * fhh: continue  # small or thin (weapon shaft)
            if not (m & bm).any(): fail.append("stray leg"); break
        # 3) feet: compare each frame's worst foot with the same frame of the pose layout (the layout's feet point the
        #    walking direction). A foot far more "backwards" than the layout's = foot pointing the wrong way.
        if lay is not None:
            fo, fl = _feet(f, ft, fb), _feet(lay[:, x0:x1], *_span(lay[:, x0:x1]))
            if fo and fl and min(fo) < min(fl) - FOOT_DELTA: fail.append("foot backwards")
        per.append(",".join(fail) or "ok")
    ok = all(p == "ok" for p in per)
    return ok, "anatomy " + "/".join(per), per

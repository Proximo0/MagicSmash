"""Foot model from the drawn foot pixels.

Owner, 22 Nov: "the heel is connected to the back of the leg, there shouldnt be anything behind
it".  So the heel is the bottom of the shin's BACK edge: the Achilles line runs straight down into
the heel, nothing of the foot sticks out behind the leg, and the whole foot extends forward from
there to the toe.

`fit_foot` measures the foot from the picture (hand or layout joints put the heel under the
ankle or the toe mid-boot):
  * leg pixels around the lower shin and foot, in the shin's frame (axis knee -> ankle);
  * shin back edge = the furthest-back leg pixel from mid-shin down to the sole (a boot's heel
    block counts as part of that back line); shin front edge = furthest-forward pixel of the
    lower shin above the ankle;
  * sole angle = the rotation that puts the most foot pixels on one bottom row (a sole is
    flat), searched over -60..60 deg (positive = toe up, as drawn at heel strike);
  * ankle = slid along the shin axis to an anatomical height above the sole (ANKLE_H);
  * heel  = where the back edge line meets the sole; toe = the front end of the sole.
The renderer clips foot pixels behind the posed back edge line (`behind_back_edge`), so a
dorsiflexed foot never shows its heel behind the leg.
"""
import math

import numpy as np

ANKLE_H = (0.22, 0.40)      # ankle height above the sole, fraction of foot length (adult foot:
                            # lateral malleolus ~6-7 cm over a ~25 cm foot, boots a bit more)
SOLE_BAND = 2.5             # px above the lowest rotated row that count as sole
BEHIND_MAX_PX = 1           # checks: foot pixels behind the shin's back edge, per row, game px


def _rot(pts, deg, about):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    q = pts - about
    return np.stack([c * q[:, 0] - s * q[:, 1], s * q[:, 0] + c * q[:, 1]], 1) + about


def forward_normal(knee, ankle, facing=1.0):
    """Unit vector across the shin axis pointing the facing direction."""
    u = np.asarray(ankle, float) - np.asarray(knee, float)
    u = u / max(float(np.hypot(*u)), 1e-9)
    n = np.array([u[1], -u[0]])
    return n if n[0] * facing >= 0 else -n


def fit_foot(leg_mask, knee, ankle, shin_r):
    """leg_mask: bool HxW of the (near) leg pixels around the foot.  Returns dict with heel,
    toe, ankle (np arrays, still px), pitch (deg, toe up +), length, back / front (shin edge
    offsets from the axis, still px), or None."""
    knee = np.asarray(knee, float)
    ankle = np.asarray(ankle, float)
    u = ankle - knee
    Ls = float(np.hypot(*u))
    if Ls < 1e-6:
        return None
    u = u / Ls
    n = forward_normal(knee, ankle)
    ys, xs = np.where(leg_mask)
    P = np.stack([xs + 0.5, ys + 0.5], 1).astype(float)
    t = (P - ankle) @ u                     # along the shin, + = past the ankle
    c = (P - ankle) @ n                     # across, + = forward
    near_axis = np.abs(c) < 6.0 * shin_r + 0.6 * Ls
    foot = P[(t >= -1.2 * shin_r) & near_axis]
    if len(foot) < 8:
        return None
    best = None
    for deg in range(-60, 61, 2):
        # rotate by +deg (clockwise on screen): a toe-up foot (pitch deg) becomes flat
        R = _rot(foot, deg, ankle)
        bot = R[:, 1].max()
        band = R[R[:, 1] >= bot - SOLE_BAND]
        w = band[:, 0].max() - band[:, 0].min()
        score = w + 0.25 * len(band) - 0.02 * abs(deg)
        if best is None or score > best[0]:
            best = (score, deg, R, bot)
    _, deg, R, bot = best
    band = R[R[:, 1] >= bot - SOLE_BAND]
    tx = band[:, 0].max()
    low = R[R[:, 1] >= bot - 0.5 * (bot - ankle[1])]
    if len(low):
        tx = max(tx, low[:, 0].max())      # most forward pixel of the lower foot
    # shin edges: back = furthest back from mid-shin down (heel block included); front =
    # furthest forward on the lower shin above the ankle
    back, front = _shin_edges(t, c, Ls, shin_r)
    # ankle: slide along the shin axis to an anatomical height above the sole
    uf = _rot(np.stack([ankle + u]), deg, ankle)[0] - ankle
    nf = _rot(np.stack([ankle + n]), deg, ankle)[0] - ankle
    h0 = bot - ankle[1]
    flen0 = max(tx - (ankle[0] - back), 2.0)
    h = min(max(h0, ANKLE_H[0] * flen0), ANKLE_H[1] * flen0)
    s = (h0 - h) / uf[1] if abs(uf[1]) > 0.2 else 0.0
    a2 = ankle + s * uf
    # heel: the back edge line (a2 - back * nf + k uf) meets the sole y = bot
    e0 = a2 - back * nf
    k = (bot - e0[1]) / uf[1] if abs(uf[1]) > 0.2 else 0.0
    hx = e0[0] + k * uf[0]
    flen = tx - hx
    if flen < 2:
        return None
    back_pts = _rot(np.stack([np.array([hx, bot]), np.array([tx, bot]), a2]), -deg, ankle)
    return {"heel": back_pts[0], "toe": back_pts[1], "ankle": back_pts[2], "pitch": float(deg),
            "length": float(flen), "back": back, "front": front}


def _shin_edges(t, c, Ls, shin_r):
    """Back / front edge offsets of the lower shin from its axis: per 1-px slice across the
    shin (from 0.4 shin lengths above the ankle down to just above it), the furthest pixel on
    each side within 2.5 radii of the axis; the 75th percentile over the slices."""
    sel = (t >= -0.4 * Ls) & (t < -0.3 * shin_r) & (np.abs(c) <= 2.5 * shin_r)
    if sel.sum() < 6:
        return shin_r, shin_r
    tb = np.floor(t[sel]).astype(int)
    cs = c[sel]
    bk, fr = [], []
    for v in np.unique(tb):
        m = tb == v
        bk.append(max(-cs[m].min(), 0.0))
        fr.append(max(cs[m].max(), 0.0))
    back = max(float(np.percentile(bk, 75)) + 0.5, 0.5 * shin_r)
    front = max(float(np.percentile(fr, 75)) + 0.5, 0.5 * shin_r)
    return back, front


def behind_back_edge(P, knee, ankle, back, facing=1.0):
    """Signed distance of points P (...,2) behind the shin's back edge line (> 0 = behind)."""
    n = forward_normal(knee, ankle, facing)
    a = np.asarray(ankle, float)
    return -((P[..., 0] - a[0]) * n[0] + (P[..., 1] - a[1]) * n[1]) - back


def ahead_of_front_edge(P, knee, ankle, front, facing=1.0):
    n = forward_normal(knee, ankle, facing)
    a = np.asarray(ankle, float)
    return (P[..., 0] - a[0]) * n[0] + (P[..., 1] - a[1]) * n[1] - front

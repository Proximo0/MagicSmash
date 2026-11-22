"""Foot model from the drawn foot pixels.

Owner, 22 Nov: "the heel is connected to the back of the leg, there shouldnt be anything behind
it".  So the heel is the bottom of the shin's BACK edge: the Achilles line runs straight down into
the heel, nothing of the foot sticks out behind the leg, and the whole foot extends forward from
there to the toe.

`fit_foot` measures the foot from the picture (hand or layout joints put the heel under the
ankle or the toe mid-boot):
  * shin edges: back = the furthest-back leg pixel of the lower shin, front = the furthest
    forward one (75th percentile over 1-px slices), as offsets from the shin axis;
  * sole = the longest near-level edge of the lower convex hull of the pixels below the ankle;
  * foot = everything below the ankle line (parallel to the sole at ankle height); length =
    the drawn boot from its rearmost to its foremost low pixel, measured along the sole;
  * ankle = on the shin axis at an anatomical height above the sole (ANKLE_H);
  * the foot is re-seated (shifted along the sole, whole pixels) so that its heel's rear end
    is `back` behind the ankle joint: flush with the shin's back edge when the ankle is neutral.
`foot_faults` says, before anything is baked, whether such a foot can keep rule R6 in every
frame; a boot drawn shorter than a human foot is the still's fault and is refused, never
stretched.  The renderer still clips any foot pixel behind the posed back edge line
(`behind_back_edge`): after re-seating that is at most the fraction of a pixel a flexed ankle
swings the heel back.
"""
import math

import numpy as np

ANKLE_H = (0.22, 0.40)      # ankle height above the sole, fraction of foot length (adult foot:
                            # lateral malleolus ~6-7 cm over a ~25 cm foot, boots a bit more)
SOLE_BAND = 2.5             # px above the sole line that always count as sole
SOLE_PITCH = (-25.0, 60.0)  # deg, toe up +: a drawn sole lies in this range (the stills draw the
                            # front foot up to ~45 deg toe-up at heel strike; a steeper edge
                            # running down-forward is the back of the leg, not a sole)
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


def _sole_line(foot):
    """Sole direction of the foot pixels: the longest edge of their lower convex hull that is
    within SOLE_PITCH (a sole is flat; the lower hull ignores the laces and the shaft).
    Returns the unit vector along the sole pointing the facing way (+x)."""
    xs = np.floor(foot[:, 0]).astype(int)
    lo = {}
    for x, y in zip(xs, foot[:, 1]):
        if y > lo.get(x, -1e9):
            lo[x] = y
    pts = sorted((x + 0.5, y + 0.5) for x, y in lo.items())
    hull = []
    for p in pts:                      # chain with the largest y (screen-down) per turn
        while len(hull) >= 2:
            (x1, y1), (x2, y2) = hull[-2], hull[-1]
            if (x2 - x1) * (p[1] - y1) - (y2 - y1) * (p[0] - x1) >= 0:
                hull.pop()
            else:
                break
        hull.append(p)
    best, e = 0.0, np.array([1.0, 0.0])
    for (x1, y1), (x2, y2) in zip(hull, hull[1:]):
        L = math.hypot(x2 - x1, y2 - y1)
        pitch = -math.degrees(math.atan2(y2 - y1, x2 - x1))       # toe up +
        if L > best and SOLE_PITCH[0] <= pitch <= SOLE_PITCH[1]:
            best, e = L, np.array([x2 - x1, y2 - y1]) / L
    return e


def fit_foot(leg_mask, knee, ankle, shin_r):
    """leg_mask: bool HxW of the (near) leg pixels around the foot.  Returns dict with heel,
    toe, ankle (np arrays, still px), pitch (deg, toe up +), length, back / front (shin edge
    offsets from the axis, still px), seat (integer px shift of the foot part), cut (ankle
    line: point and downward normal), or None.

    The foot is everything of the leg below the ankle line (parallel to the sole, at ankle
    height).  Its length is the drawn boot's, heel block included.  It is RE-SEATED: in the
    foot's own frame the ankle joint sits `back` (the shin's back-edge offset) ahead of the
    heel's rear end and ankle-height above the sole, so with the ankle at neutral the heel's
    rear is exactly the bottom of the shin's back edge and the whole foot runs forward from
    there; the foot part's pixels are shifted along the sole (`seat`) so that this point lies
    on the shin's own axis.  No pixel is stretched or dropped."""
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
    # below the ankle along the shin, plus what lies ahead of the shin near the ankle's
    # height (the toe of a foot drawn toe-up at heel strike is above the ankle line)
    dist = np.hypot(*(P - ankle).T)
    ahead = (c > 0) & (P[:, 1] >= ankle[1] - 0.25 * Ls) & (dist <= 0.6 * Ls)
    foot = P[((t >= -0.5 * shin_r) | ahead) & near_axis]
    if len(foot) < 8:
        return None
    e = _sole_line(foot)                    # along the sole, forward
    d = np.array([-e[1], e[0]])             # sole normal, pointing down
    if d[1] < 0:
        d = -d
    if abs(float(u @ d)) < 0.3:             # shin lying along the sole: not a standing leg
        return None
    sole = float((foot @ d).max()) + 0.5    # the sole line: P.d = sole
    h0 = sole - float(ankle @ d)            # the tracked ankle may sit low in the boot
    band = max(0.6 * h0, 2 * SOLE_BAND)
    for _ in range(2):                      # length from the low pixels, ankle height from it
        low = foot[(foot @ d) >= sole - band]
        heel_e = float((low @ e).min()) - 0.5
        toe_e = float((low @ e).max()) + 0.5
        flen = toe_e - heel_e
        if flen < 2:
            return None
        h = min(max(h0, ANKLE_H[0] * flen), ANKLE_H[1] * flen)
        band = max(0.6 * h, SOLE_BAND)
    back, front = _shin_edges(t, c, Ls, shin_r)
    a2 = ankle + (sole - h - float(ankle @ d)) / float(u @ d) * u     # on the shin axis
    # re-seat: the foot frame's ankle point (heel rear + back along the sole, h above it)
    # must be a2; shift the foot along the sole by the difference (whole pixels)
    s = float(a2 @ e) - (heel_e + back)
    seat = np.round(s * e).astype(int)
    heel = e * heel_e + d * sole + seat
    toe = e * toe_e + d * sole + seat
    pitch = math.degrees(math.atan2(-e[1], e[0]))
    return {"heel": heel, "toe": toe, "ankle": a2, "pitch": float(pitch),
            "length": float(flen), "back": back, "front": front,
            "seat": [int(seat[0]), int(seat[1])], "seat_px": float(s),
            "cut": [float(a2[0]), float(a2[1]), float(d[0]), float(d[1])]}


def below_ankle(P, cut):
    """True where points P (...,2) lie on the foot side of the ankle line `cut`."""
    return (P[..., 0] - cut[0]) * cut[2] + (P[..., 1] - cut[1]) * cut[3] >= 0


def reseat(img, seat):
    """The foot part's image shifted by `seat` = (dx, dy) whole pixels."""
    dx, dy = int(seat[0]), int(seat[1])
    out = np.zeros_like(img)
    H, W = img.shape[:2]
    out[max(dy, 0):H + min(dy, 0), max(dx, 0):W + min(dx, 0)] = \
        img[max(-dy, 0):H + min(-dy, 0), max(-dx, 0):W + min(-dx, 0)]
    return out


FOOT_LEG = (0.24, 0.30)     # human foot length / leg length (hip to ankle): about 0.26-0.29
                            # (Drillis & Contini 1966: foot 0.152, thigh + shank 0.491 of stature
                            # -> 0.31 to the floor, a little less with a boot's shaft drawn in)
FOOT_LEG_STOCKY = 0.60      # dwarf builds draw short legs under full-size boots
TOE_MARGIN = 3.5            # still px (half a game pixel at 7:1) the toe must clear the line by
                            # before baking; rule R6 then judges the baked pixels themselves


def plantar_limit(back, ankle_h, tol):
    """Largest plantarflexion (deg) at which the heel's rear end is at most `tol` px behind
    the shin's back edge line.  Foot frame as in toe_clearance: turning the foot toe-down by
    f about the ankle swings the heel back by ankle_h sin f - back (1 - cos f)."""
    lim = 0.0
    for f in np.arange(0.0, 50.5, 0.5):
        r = math.radians(f)
        if ankle_h * math.sin(r) - back * (1 - math.cos(r)) > tol:
            break
        lim = float(f)
    return lim


def toe_clearance(length, back, front, ankle_h, flex):
    """How far (still px) the toe is ahead of the shin's front edge line with the ankle flexed
    by `flex` degrees (+ = dorsiflexed, shin leaning forward over the foot).  Foot frame: heel
    rear at 0, ankle joint `back` ahead of it and ankle_h above the sole, toe at `length`."""
    r = math.radians(flex)
    return (length - back) * math.cos(r) + ankle_h * math.sin(r) - front


def foot_faults(length, leg, back, front, ankle_h, flex_range, margin=TOE_MARGIN):
    """Why a measured foot cannot satisfy rule R6 in every frame (list of texts, empty = it
    can).  R6 needs the toe ahead of the shin's front edge line at every ankle angle of the
    walk (flex_range: most plantarflexed, most dorsiflexed, degrees); with the heel seated on
    the shin's back edge that is a statement about the drawn boot's length against the
    shin's width, so it is known before anything is baked."""
    out = []
    r = length / max(leg, 1e-6)
    if r < FOOT_LEG[0]:
        out.append("the drawn boot is %.0f px, %.2f of the leg length as drawn (%.0f px); a human "
                   "foot is %.2f-%.2f: the still's boot is too short (it is not stretched)"
                   % (length, r, leg, FOOT_LEG[0], FOOT_LEG[1]))
    elif r > FOOT_LEG_STOCKY:
        out.append("the drawn boot is %.0f px, %.2f of the leg length as drawn (%.0f px): longer "
                   "than any build allows (%.2f)" % (length, r, leg, FOOT_LEG_STOCKY))
    worst = min(toe_clearance(length, back, front, ankle_h, f) for f in flex_range)
    if worst < margin:
        out.append("the boot (%.0f px) is too short for the shin's width at the ankle (back %.0f + "
                   "front %.0f px): with the ankle flexed the toe is only %+.0f px ahead of the "
                   "shin's front line (needs %.1f)" % (length, back, front, worst, margin))
    return out


def _shin_edges(t, c, Ls, shin_r):
    """Back / front edge offsets of the shin from its axis, measured on the shin itself and
    not on the boot: per 1-px slice across the shin from 0.55 to 0.2 shin lengths above the
    ankle, the furthest pixel on each side within 2.5 radii of the axis; the median over the
    slices (the old model measured down to the ankle and so took the boot's heel block and
    instep for the shin's edges, which made every shin look as wide as its boot)."""
    sel = (t >= -0.55 * Ls) & (t < -0.2 * Ls) & (np.abs(c) <= 2.5 * shin_r)
    if sel.sum() < 6:
        return shin_r, shin_r
    tb = np.floor(t[sel]).astype(int)
    cs = c[sel]
    bk, fr = [], []
    for v in np.unique(tb):
        m = tb == v
        bk.append(max(-cs[m].min(), 0.0))
        fr.append(max(cs[m].max(), 0.0))
    back = max(float(np.median(bk)) + 0.5, 0.5 * shin_r)
    front = max(float(np.median(fr)) + 0.5, 0.5 * shin_r)
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

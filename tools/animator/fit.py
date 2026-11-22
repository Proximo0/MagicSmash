"""Fit the pose-layout joints of a full-size still to the picture (no hand-placed joints).

Input: samples/stills/<id>.png (RGBA, facing right, widest-stride walk frame) + <id>.json
(`joints` from the pose layout: head, neck, pelvis, near_/far_ shoulder, elbow, wrist, hip,
knee, ankle, toe; `ground_y`).  The layout skeleton was scaled to the picture's bounding box
(staffs, hats and ground plates included), so legs are close, arms and head are not.

Steps (`fit_still`):
  1. hard alpha; the largest 8-connected piece is the body; pieces under DUST_FRAC of it are
     dropped; bigger loose pieces (a staff standing beside a dwarf) are kept as `detached`.
  2. ground plates / shadows: in the bottom band, runs of consecutive columns whose bottom
     opaque run is thin (< PLATE_T of the height) over at least PLATE_W of the height are a
     plate, and are erased.  ground_y = 1 + the lowest remaining body row.
  3. head top = the highest body pixel over the layout head's columns; body height BH =
     ground - head top.  The layout is registered to the body: scale s = BH / layout height,
     anchored on the ground line and the layout pelvis column.
  4. legs: from just above the ground, the leftmost and rightmost foot-wide runs are the back
     and front foot; each is followed upward row by row (run overlapping the one below) until
     the two meet (crotch, or the hem of a robe) or a run widens past 2.2 x the leg width.
     Knee and hip column are fitted to that medial axis (two-segment least squares, knee kept
     in front of the hip-ankle line, pulled toward the registered layout knee).  Hip height =
     the registered pelvis row, but at most 0.6 thigh widths above a real crotch.
  5. feet: `foot.fit_foot` on the front leg (heel flush with the shin's back edge).
  6. trunk: neck = registered layout neck, centred on the silhouette run; shoulder =
     registered layout shoulder pulled onto the trunk axis.
  7. arms: the torso's front and back lines (20th percentile of the silhouette's reach from
     the trunk axis between shoulder and hip).  The biggest blob ahead of the front line is the
     front hand (and anything it holds): wrist = its pixels at ~0.92 arm reach from the
     shoulder; elbow by two-bone IK with the elbow bending forward only.  A small blob behind
     the back line is the other hand, erased (the far arm is a darkened copy of the near one).
  8. score: 1 minus penalties (legs not found, few axis points, poor axis fit, knee pulled far
     from the layout, no hand found, joints moved more than MOVE_FLAG x BH, detached pieces);
     below SCORE_OK the hero is flagged and not baked by default.
The near (drawn-in-front) leg and arm in our rig are the FRONT ones in the still.
"""
import json
import math
import os

import numpy as np
from PIL import Image

from .colour import to_oklab
from .foot import fit_foot
from .imgops import components, dilate, runs, seg_dist
from .intake import GEAR_FRONT_MAX, clean_key, gear_census, key_mask
from .rig import ik2

ALPHA_T = 128
DUST_FRAC = 0.004     # loose pieces smaller than this x the body are dust
PLATE_T = 0.10        # plate: bottom runs starting within this x body height of the bottom ...
PLATE_W = 0.07        # ... over at least this x body height of consecutive columns
PLATE_TOP_MAX = 45    # a plate column's top pixel is not near-black outline (max channel)
PLATE_DE = 30         # colour distance (sum of |dR|+|dG|+|dB|) that grows the plate
MOVE_FLAG = 0.12      # a joint moved more than this x body height from the layout: suspicious
SCORE_OK = 0.7
INNER_HAND_SWITCH = False   # cut the arm drawn over the body instead of the protruding one:
                            # right on HR1.1, wrong on 5 others in testing, so only a flag
INNER_AB = 0.045      # OKLab chroma distance: an inner blob of the hand's colour ...
BACK_ARM_REACH = 0.07  # silhouette this far (x body height) behind the back line at hand
                       # height = the back arm is visible, so no arm is drawn over the body
INNER_L = 0.08        # ... and lightness distance

LAYOUT_TOP_MARGIN = 12   # the layout was fitted to the picture's bounding box


HAND_ROWS = (0.12, 0.08)   # hands are looked for from this far (x body height) below the
                           # shoulder to this far below the hip
HAND_HUE = 30.0            # deg of OKLab hue from the front hand's colour: the other hand is
HAND_CHROMA = (0.45, 1.9)  # shaded (HR1.1: far hand redder and darker, near one lighter), so
HAND_L = (-0.10, 0.35)     # hue, chroma ratio and lightness each get their own window
HAND_GREY = 0.03           # OKLab chroma under which the hand is grey (glove, gauntlet)
HAND_AREA = (0.50, 20.0)   # x the front hand's lit area (bigger and not limb-shaped: clothing)
ARM_BLOB_MIN = 0.05        # x the front hand's lit area: smaller specks of its colour are not counted
ARM_OVERLAP_MAX = 0.15     # G8: hand-coloured area drawn over the body, x the front hand's lit area,
                           # from which the still is refused (v1 needed one blob of 0.50: a fist half
                           # hidden behind a shield passed)
HAND_SIZE = (0.02, 0.12)   # x body height: a hand blob's width and height
HAND_FILL = 0.4            # a fist fills at least this much of its bounding box
HAND_REACH = (0.55, 1.3)   # x arm length from the shoulder
LIMB_W = 0.07              # x body height: a bare forearm is at most this wide ...
LIMB_H = 0.10              # ... and at least this long
OUTLINE_DARK = 70          # brightest channel of an outline pixel
EDGE = 0.03                # x body height: a blob this close to the silhouette's edge is clear of the body


def hand_census(lab_img, body, exclude, hand_blob, shoulder, sh_y, hip_y, BH, arm_len, hand_at=None):
    """Every other hand (or bare forearm) of the still besides the front hand: list of dicts
    with centre, area (x the front hand's lit area), size and zone (`back` = behind the torso's
    back line, `front` = ahead of its front line, `inside` = drawn over the body).  A hand is a
    compact blob of the front hand's colour (shading allowed: HAND_AB, HAND_L), hand-sized, at
    arm's reach from the shoulder; a bare forearm is a longer blob of that colour, arm-wide.
    `exclude` = the near arm's own pixels.  `hand_at` = where the hand is when the layout says so
    (a still on spec); otherwise the blob's point furthest from the shoulder, which is the tip
    of a held weapon when there is one (HR6.4 on spec: the hammer's grey was taken for the
    hand's colour and the green fist on the shield was not seen)."""
    if not hand_blob.any():
        return []
    H, W = body.shape
    yy, xx = np.mgrid[0:H, 0:W]
    by_, bx_ = np.where(hand_blob)
    dd_ = np.hypot(bx_ + 0.5 - shoulder[0], by_ + 0.5 - shoulder[1])
    tip = np.array([bx_[np.argmax(dd_)] + 0.5, by_[np.argmax(dd_)] + 0.5])
    if hand_at is not None:
        tip = np.asarray(hand_at, float)
    hb = hand_blob & (np.hypot(xx + 0.5 - tip[0], yy + 0.5 - tip[1]) < 0.045 * BH)
    if hb.sum() < 6:
        return []
    # the hand's own colour: its lit pixels (outline and held gear are darker or rarer)
    px = lab_img[hb]
    lit = px[px[:, 0] > np.percentile(px[:, 0], 35)]
    ref = np.median(lit if len(lit) >= 4 else px, 0)
    dab = np.hypot(*(lab_img - ref)[..., 1:].transpose(2, 0, 1))
    dl = lab_img[..., 0] - ref[0]
    tip_area = float((hb & (dab < INNER_AB) & (np.abs(dl) < INNER_L)).sum())
    if tip_area < 4:
        return []
    # same hue as the hand (shading moves lightness and chroma far more than hue)
    c_ref = float(np.hypot(ref[1], ref[2]))
    chroma = np.hypot(lab_img[..., 1], lab_img[..., 2])
    if c_ref >= HAND_GREY:
        hue = np.degrees(np.arctan2(lab_img[..., 2], lab_img[..., 1]) - math.atan2(ref[2], ref[1]))
        hue = np.abs((hue + 180.0) % 360.0 - 180.0)
        same = (hue < HAND_HUE) & (chroma > HAND_CHROMA[0] * c_ref) & (chroma < HAND_CHROMA[1] * c_ref)
    else:               # a grey glove or gauntlet: no hue to speak of
        same = dab < HAND_GREY
    same &= (dl > HAND_L[0]) & (dl < HAND_L[1])
    zone = body & same & ~dilate(exclude, max(2, int(0.012 * BH))) & \
        (yy >= sh_y + HAND_ROWS[0] * BH) & (yy <= hip_y + HAND_ROWS[1] * BH)
    out = []
    if not zone.any():
        return out
    cl, cs = components(zone)
    for kk, sz in sorted(cs.items(), key=lambda kv: -kv[1]):
        if sz < ARM_BLOB_MIN * tip_area:
            break
        m = cl == kk
        ys, xs = np.where(m)
        w, h = int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)
        c = np.array([xs.mean() + 0.5, ys.mean() + 0.5])
        dd = np.hypot(xs + 0.5 - shoulder[0], ys + 0.5 - shoulder[1]) / arm_len
        d = float(np.hypot(*(c - shoulder))) / arm_len
        if not ((dd >= HAND_REACH[0]) & (dd <= HAND_REACH[1])).any():
            continue
        row_w = float(np.median(m.sum(1)[m.any(1)]))
        limb = h >= LIMB_H * BH and row_w <= LIMB_W * BH
        if sz > HAND_AREA[1] * tip_area and not limb:
            continue      # clothing or bare body of the hand's colour, not a limb
        fist = not limb
        # zone: a blob at the silhouette's own back (or front) edge is clear of the body; one
        # with body on both sides of it is drawn over the body
        rows_ = np.unique(ys)
        left = np.array([xs[ys == r].min() - np.argmax(body[r]) for r in rows_])
        right = np.array([(W - 1 - np.argmax(body[r, ::-1])) - xs[ys == r].max() for r in rows_])
        z = "back" if np.median(left) <= EDGE * BH else "front" if np.median(right) <= EDGE * BH else "inside"
        out.append({"at": [round(float(c[0]), 1), round(float(c[1]), 1)],
                    "area": round(sz / tip_area, 2), "zone": z, "w": w, "h": h,
                    "kind": "hand" if fist else "forearm", "reach": round(d, 2), "mask": m})
    return out


LOOSE_MIN = 9              # px: an opaque blob this big that is not connected to the body is a loose
                           # piece (G13); smaller ones are keying dust and are dropped
HELD_MAX = 0.11            # x body height: an empty hand's blob ends this close to the hand's middle
BACK_CLOTH_MARGIN = 0.05   # x body height behind the layout's back line before cloth is counted ...
BACK_CLOTH_MAX = 0.010     # ... and x body height squared of it that a bare body may have (long hair)
LEG_SKIN_TOP = 0.05        # x body height under the hips where the leg region starts (a tunic's hem)
LEG_SKIN_SHIN = 0.5        # share of the shin, from the knee down, that counts as leg (not boot)
LEG_SKIN_MAX = 0.25        # G15: share of the lit leg pixels that may have the hand's colour


LEG_SKIN_SHIN_FULL = 0.9   # G16: share of each shin (knee to ankle) that counts: bare shins under shorts
FAR_BLOB_MAX = 1.5         # x the near hand blob: a bigger 'far hand' behind the back of a body still is clothes
LEG_SKIN_DE = 22.0         # G16: Lab distance to the hand's colour that still counts as skin
LEG_SKIN_SHIN_MAX = 0.25   # G16: share of a shin that may have the hand's colour


def leg_skin(lab_img, img, body, hand_blob, hand_at, shoulder, BH, bones, r, top_y,
             shin_t=LEG_SKIN_SHIN, thighs=True, tight=None):
    """Share of the pixels of the thighs and the upper LEG_SKIN_SHIN of the shins (boot shafts
    and leg wraps are below that) that have the front hand's colour, by the same colour test as the hand census
    (hue within HAND_HUE, chroma and lightness windows).  None when there is no hand."""
    if not hand_blob.any():
        return None
    H, W = body.shape
    yy, xx = np.mgrid[0:H, 0:W]
    if hand_at is None:
        by_, bx_ = np.where(hand_blob)
        i = int(np.argmax(np.hypot(bx_ + 0.5 - shoulder[0], by_ + 0.5 - shoulder[1])))
        hand_at = np.array([bx_[i] + 0.5, by_[i] + 0.5])
    hb = hand_blob & (np.hypot(xx + 0.5 - hand_at[0], yy + 0.5 - hand_at[1]) < 0.045 * BH)
    if hb.sum() < 6:
        return None
    px = lab_img[hb]
    lit = px[px[:, 0] > np.percentile(px[:, 0], 35)]
    ref = np.median(lit if len(lit) >= 4 else px, 0)
    dl = lab_img[..., 0] - ref[0]
    c_ref = float(np.hypot(ref[1], ref[2]))
    if c_ref >= HAND_GREY:
        chroma = np.hypot(lab_img[..., 1], lab_img[..., 2])
        hue = np.degrees(np.arctan2(lab_img[..., 2], lab_img[..., 1]) - math.atan2(ref[2], ref[1]))
        hue = np.abs((hue + 180.0) % 360.0 - 180.0)
        same = (hue < HAND_HUE) & (chroma > HAND_CHROMA[0] * c_ref) & (chroma < HAND_CHROMA[1] * c_ref)
    else:
        same = np.hypot(*(lab_img - ref)[..., 1:].transpose(2, 0, 1)) < HAND_GREY
    same &= (dl > HAND_L[0]) & (dl < HAND_L[1])
    if tight is not None:          # G16: within this Lab distance of the hand's own colour
        same &= np.sqrt(((lab_img - ref) ** 2).sum(-1)) < tight
    P = np.stack([xx + 0.5, yy + 0.5], -1).astype(float)
    legs = np.zeros_like(body)
    for i, (a, b) in enumerate(bones):      # thigh, shin, thigh, shin
        d, t = seg_dist(P, np.asarray(a, float), np.asarray(b, float))
        legs |= (d <= r) & (t >= 0) & ((t <= shin_t) if i % 2 else thighs)
    legs &= body & (yy >= top_y)
    n = int(legs.sum())
    return round(float((legs & same).sum()) / n, 3) if n else None


def load_single(path):
    """The still with hard alpha and the background key's fringe cleaned (intake.clean_key)."""
    a = np.array(Image.open(path).convert("RGBA"))
    a[a[..., 3] < ALPHA_T] = 0
    a[a[..., 3] >= ALPHA_T, 3] = 255
    return clean_key(a)[0]


def _bbox_top(mask):
    return int(np.flatnonzero(mask.any(1))[0])


def remove_plates(body, BH_guess, rgb=None):
    """Erase ground plates, shadows and puddles.  Seeds: spans of at least PLATE_W x BH
    consecutive columns whose bottom opaque run starts within the bottom PLATE_T x BH (the
    gap between and around the feet, where nothing stands on the plate).  The plate is then
    grown from the seeds through 4-connected pixels of the bottom band whose colour is within
    PLATE_DE of a seed colour, so it is also removed under the boots (a boot is darker and
    outlined, so the growth stops at it).  Returns (mask, erased)."""
    H, W = body.shape
    rows = np.flatnonzero(body.any(1))
    bot = int(rows[-1])
    t = PLATE_T * BH_guess
    band0 = max(0, int(bot - 1.6 * t))
    thin = np.zeros(W, bool)
    ytop = np.full(W, -1)
    for x in range(W):
        col = np.flatnonzero(body[band0:bot + 1, x])
        if not len(col):
            continue
        yb = band0 + col[-1]
        if yb < bot - 0.25 * t:
            continue
        y = yb
        while y - 1 >= 0 and body[y - 1, x]:
            y -= 1
        ytop[x] = y
        # a plate has no dark outline on top (shadows, puddles); a boot does
        topc = rgb[y, x].astype(int) if rgb is not None else np.array([255, 255, 255])
        thin[x] = (yb - y + 1) <= t and topc.max() >= PLATE_TOP_MAX
    seed = np.zeros_like(body)
    x = 0
    minw = PLATE_W * BH_guess
    while x < W:
        if thin[x]:
            x0 = x
            while x < W and thin[x]:
                x += 1
            if x - x0 >= minw:
                m = int(0.2 * (x - x0))
                for xx in range(x0 + m, x - m):
                    seed[ytop[xx]:bot + 1, xx] = body[ytop[xx]:bot + 1, xx]
        else:
            x += 1
    if not seed.any():
        return body.copy(), np.zeros_like(body)
    erased = seed.copy()
    if rgb is not None:
        c = rgb.astype(np.int32)
        sc = np.unique((c[seed] // 6) * 6, axis=0)
        if len(sc) > 400:
            sc = sc[np.linspace(0, len(sc) - 1, 400).astype(int)]
        ok = np.zeros_like(body)
        ys, xs = np.where(body)
        sel = ys >= band0
        cc = c[ys[sel], xs[sel]]
        dmin = np.full(len(cc), 1e9)
        for i in range(0, len(sc), 50):
            d = np.abs(cc[:, None, :] - sc[None, i:i + 50, :]).sum(-1).min(1)
            dmin = np.minimum(dmin, d)
        ok[ys[sel], xs[sel]] = dmin <= PLATE_DE
        ptop = int(np.flatnonzero(seed.any(1))[0])
        ok[:max(0, ptop - 1)] = False          # the plate never rises above its own top
        for _ in range(int(3 * t) + 10):
            g = erased.copy()
            g[1:] |= erased[:-1]
            g[:-1] |= erased[1:]
            g[:, 1:] |= erased[:, :-1]
            g[:, :-1] |= erased[:, 1:]
            g &= ok
            if np.array_equal(g, erased):
                break
            erased = g
    return body & ~erased, erased


def _track(mask, y_start, x_run, y_stop, other=None):
    """Follow one leg run upward. Returns list of (y, x0, x1)."""
    out = [(y_start, x_run[0], x_run[1])]
    prev = x_run
    widths = [x_run[1] - x_run[0] + 1]
    for y in range(y_start - 1, y_stop - 1, -1):
        rr = runs(mask[y], 2)
        best, ov = None, 0
        for r in rr:
            o = min(r[1], prev[1]) - max(r[0], prev[0]) + 1
            if o > ov:
                best, ov = r, o
        if best is None:
            break
        w = best[1] - best[0] + 1
        med = float(np.median(widths[-30:]))
        if len(widths) > 8 and w > 2.2 * med:
            break
        out.append((y, best[0], best[1]))
        widths.append(w)
        prev = best
    return out


def _fit_knee(pts, hip_y, hip_x0, ankle, knee_prior, BH, hx_range):
    """Least-squares knee (and hip column) for a medial axis.  Returns hip, knee, rms."""
    P = np.asarray(pts, float)
    best = None
    span = 0.10 * BH
    ks = np.arange(-span, span + 0.1, 2.0)
    KX, KY = np.meshgrid(knee_prior[0] + ks, knee_prior[1] + ks)
    K = np.stack([KX.ravel(), KY.ravel()], 1)
    for dx in hx_range:
        hip = np.array([hip_x0 + dx, hip_y])
        # knee must be in front of the hip-ankle line (knee bends backwards only)
        v = ankle - hip
        cross = (K[:, 0] - hip[0]) * v[1] - (K[:, 1] - hip[1]) * v[0]
        ok = cross > -1e-6
        ok &= (K[:, 1] > hip[1] + 0.05 * BH) & (K[:, 1] < ankle[1] - 0.05 * BH)
        if not ok.any():
            continue
        Kc = K[ok]
        # distance of every point to both segments, for every candidate knee
        d1 = _pt_seg(P[None], hip[None, None], Kc[:, None])
        d2 = _pt_seg(P[None], Kc[:, None], ankle[None, None])
        d = np.minimum(d1, d2)
        cost = (d ** 2).mean(1) + 40.0 * (np.hypot(*(Kc - knee_prior).T) / BH) ** 2 * BH
        i = int(np.argmin(cost))
        if best is None or cost[i] < best[0]:
            best = (float(cost[i]), hip, Kc[i], float(np.sqrt((d[i] ** 2).mean())))
    if best is None:
        return np.array([hip_x0, hip_y]), np.asarray(knee_prior, float), 99.0
    return best[1], best[2], best[3]


def _pt_seg(P, A, B):
    AB = B - A
    L2 = np.maximum((AB ** 2).sum(-1), 1e-9)
    t = np.clip(((P - A) * AB).sum(-1) / L2, 0, 1)
    Q = A + t[..., None] * AB
    return np.hypot(*(P - Q).transpose(2, 0, 1)) if P.ndim == 3 else np.hypot(*(P - Q).T)


def _elbow_by_colour(lab_img, body, S, Wr, E0, ref, BH):
    """Elbow that puts the shoulder-elbow-wrist polyline on pixels of the arm's colour."""
    H, W = body.shape
    best = None
    t = np.linspace(0.08, 0.92, 14)
    for dy in np.arange(-0.12 * BH, 0.12 * BH + 0.1, 0.012 * BH):
        for dx in np.arange(-0.12 * BH, 0.12 * BH + 0.1, 0.012 * BH):
            E = E0 + [dx, dy]
            lu, lf = float(np.hypot(*(E - S))), float(np.hypot(*(Wr - E)))
            if not (0.11 * BH <= lu <= 0.25 * BH and 0.09 * BH <= lf <= 0.24 * BH):
                continue
            # elbow bends forward only: forearm turned forward of the upper arm
            ua = math.degrees(math.atan2(E[0] - S[0], E[1] - S[1]))
            fa = math.degrees(math.atan2(Wr[0] - E[0], Wr[1] - E[1]))
            if (fa - ua + 180) % 360 - 180 < -3:
                continue
            pts = np.concatenate([S + (E - S) * t[:, None], E + (Wr - E) * t[:, None]])
            ix = np.clip(pts[:, 0].astype(int), 0, W - 1)
            iy = np.clip(pts[:, 1].astype(int), 0, H - 1)
            on = body[iy, ix]
            d = np.hypot(*(lab_img[iy, ix] - ref).T)
            cost = float(np.where(on, np.minimum(d, 0.25), 0.4).mean())
            cost += 0.25 * float(np.hypot(dx, dy)) / BH
            if best is None or cost < best[0]:
                best = (cost, E, lu, lf)
    if best is None:
        return E0, Wr, float(np.hypot(*(E0 - S))), float(np.hypot(*(Wr - E0))), 1.0
    return best[1], Wr, best[2], best[3], best[0]


def fit_still(png, layout_json):
    with open(layout_json) as f:
        lay = json.load(f)
    img = load_single(png)
    H, W = img.shape[:2]
    A = img[..., 3] > 0
    report = {"id": lay.get("id", os.path.basename(png)), "flags": [], "penalties": {}}
    on_spec = "build" in lay          # written by `spec`: the still was drawn on our pose layout
    report["on_spec"] = on_spec
    km = key_mask(img)
    report["key_px"] = int(km.sum())
    report["key_at"] = [[int(x), int(y)] for y, x in zip(*np.where(km))][:8]
    lab, sizes = components(A)
    main = max(sizes, key=sizes.get)
    body = lab == main
    detached = np.zeros_like(A)
    loose = []
    for k, s in sizes.items():
        if k != main and s >= DUST_FRAC * sizes[main]:
            detached |= lab == k
        if k != main and s >= LOOSE_MIN:
            ys_, xs_ = np.where(lab == k)
            loose.append((k, {"at": [int(xs_.mean()), int(ys_.mean())], "px": int(s)}))
    # a still that is the bare body only (STILL_SPEC.md): written so by `spec`, or it has gear
    # pictures beside it
    body_only = lay.get("format") == "body" or os.path.isdir(png[:-4] + "_gear")
    report["body_only"] = bool(body_only)
    if detached.any():
        report["flags"].append(f"detached piece(s) {int(detached.sum())} px kept as gear")
    LJ = {k: np.array(v, float) for k, v in lay["joints"].items()}
    BH0 = float(np.flatnonzero(body.any(1))[-1] - _bbox_top(body))
    body, plate = remove_plates(body, BH0, img[..., :3])
    detached &= ~plate
    if plate.any():
        report["flags"].append(f"ground plate erased ({int(plate.sum())} px)")
    # G13: opaque blobs not connected to the body (a ground plate found above is not one)
    report["loose"] = [rec for k, rec in loose if not (plate & (lab == k)).any()]
    rows = np.flatnonzero(body.any(1))
    ground = int(rows[-1]) + 1
    hx = int(LJ["head"][0])
    band = body[:, max(0, hx - int(0.12 * W)):min(W, hx + int(0.12 * W))]
    top = int(np.flatnonzero(band.any(1))[0])
    BH = float(ground - top)
    top_x = float(np.flatnonzero(body[top])[0] + np.flatnonzero(body[top])[-1] + 1) / 2
    # ---- register the layout to the body
    lay_top = float(np.flatnonzero(A.any(1))[0]) if A.any() else LAYOUT_TOP_MARGIN
    lay_ground = float(lay["ground_y"])
    s = BH / max(lay_ground - lay_top, 1.0)
    px0 = LJ["pelvis"][0]

    def reg(p):
        return np.array([px0 + (p[0] - px0) * s, ground + (p[1] - lay_ground) * s])

    R = {k: reg(v) for k, v in LJ.items()}
    # the layout's near/far are not always front/back in the picture: name the priors by
    # position (front = the more forward knee / wrist)
    leg_swap = R["near_knee"][0] < R["far_knee"][0]
    arm_swap = R["near_wrist"][0] < R["far_wrist"][0]
    for part, sw in ((("hip", "knee", "ankle", "toe"), leg_swap),
                     (("shoulder", "elbow", "wrist"), arm_swap)):
        for k in part:
            f_, b_ = (R["far_" + k], R["near_" + k]) if sw else (R["near_" + k], R["far_" + k])
            R["front_" + k], R["back_" + k] = f_, b_
            lf, lb = (LJ["far_" + k], LJ["near_" + k]) if sw else (LJ["near_" + k], LJ["far_" + k])
            LJ["front_" + k], LJ["back_" + k] = lf, lb
    report["layout_scale"] = round(s, 3)
    pen = report["penalties"]

    # ---- legs
    # feet: over the bottom rows (a lifted front foot ends a few rows higher), the most
    # forward and the most backward foot-wide runs
    cand = []
    for y in range(ground - 1 - int(0.05 * BH), ground - 1):
        for r in runs(body[y], 2):
            if r[1] - r[0] + 1 >= 0.025 * BH:
                cand.append((y, r))
    legs_ok = False
    if cand:
        yf, front_r = max(cand, key=lambda c: (c[1][1], -c[0]))
        yk, back_r = min(cand, key=lambda c: (c[1][0], -c[0]))
        legs_ok = front_r[0] > back_r[1] + 2
    if not legs_ok:
        pen["legs"] = 0.5
        report["flags"].append("two feet not found at the ground")
        c = (R["front_ankle"][0] + R["back_ankle"][0]) / 2
        yf = yk = ground - 2
        back_r = front_r = (int(c) - 5, int(c) + 5)
    hip_y_prior = R["pelvis"][1]
    stop = int(hip_y_prior)
    tf = _track(body, yf, front_r, stop)
    tb = _track(body, yk, back_r, stop)
    # where do they meet?
    merge_y = max(tf[-1][0], tb[-1][0])
    tracks = {}
    for name, tr in (("front", tf), ("back", tb)):
        arr = np.array([t for t in tr if t[0] >= merge_y], float).reshape(-1, 3)
        tracks[name] = arr
    widths = {n: (t[:, 2] - t[:, 1] + 1) for n, t in tracks.items()}
    upper_rows = {n: t[:, 0] < ground - 0.10 * BH for n, t in tracks.items()}
    wl = []
    for n in tracks:
        w = widths[n][upper_rows[n]]
        if len(w):
            wl.append(float(np.median(w)))
    leg_w = float(np.median(wl)) if wl else 0.1 * BH
    leg_w = min(max(leg_w, 0.05 * BH), 0.16 * BH)
    # crotch vs robe hem: the merged run just above the merge row
    crotch_w = 0
    if merge_y - 1 >= 0:
        xs = [r for r in runs(body[merge_y - 1], 2)]
        mid = (tf[-1][1] + tb[-1][2]) / 2
        for r in xs:
            if r[0] - 2 <= mid <= r[1] + 2:
                crotch_w = r[1] - r[0] + 1
    robe = (merge_y - hip_y_prior) > 0.12 * BH or crotch_w > 3.2 * leg_w
    report["robe"] = bool(robe)
    hip_y = hip_y_prior
    if not robe:
        hip_y = max(hip_y, merge_y - 0.6 * leg_w)
    fit = {}
    # how far the hip may be moved off the layout's column: a still on spec was drawn on it (a
    # tunic over the thighs gives the leg's axis nothing to hold on to, HR6.1: 20 px off)
    hx_w = 0.015 if on_spec else 0.05
    for name, lj in (("front", "front"), ("back", "back")):
        t = tracks[name]
        if len(t) < 4:
            pen["legs"] = max(pen.get("legs", 0), 0.4)
            fit[name] = None
            continue
        w = widths[name]
        # ankle: from the top of the foot (where the run stops being foot-wide) upward
        shin_w = float(np.median(w[upper_rows[name]])) if upper_rows[name].any() else leg_w
        foot_rows = (t[:, 0] >= ground - 0.12 * BH) & (w > 1.45 * shin_w)
        if foot_rows.any():
            ay = float(t[foot_rows, 0].min()) - 0.5
        else:
            ay = ground - 0.07 * BH
        ai = int(np.argmin(np.abs(t[:, 0] - ay)))
        ankle = np.array([(t[ai, 1] + t[ai, 2] + 1) / 2, ay])
        # the run at the top of the foot already widens into the instep, which pulled the ankle
        # forward (HR6.1 on spec: 18 px, and the shin's "back edge" 34 px behind its axis): the
        # ankle lies on the shin's own centre line, carried down from the shin's rows
        srow = (t[:, 0] < ay - 0.03 * BH) & (t[:, 0] > ay - 0.20 * BH) & (w <= 1.25 * shin_w)
        ankle_run = ankle.copy()                     # G2 compares the legs on this point
        if name == "front" and srow.sum() >= 8:      # (the back leg is only erased)
            cx_ = (t[srow, 1] + t[srow, 2] + 1) / 2
            ca, cb = np.polyfit(t[srow, 0] + 0.5, cx_, 1)
            ax_ = float(ca * ay + cb)
            if abs(ax_ - ankle[0]) <= 0.6 * shin_w:  # a wild line (few shin rows) is not used
                report["ankle_moved_px"] = round(ax_ - float(ankle[0]), 1)
                ankle[0] = ax_
        sel = (t[:, 0] < ay - 0.01 * BH)
        pts = np.stack([(t[sel, 1] + t[sel, 2] + 1) / 2, t[sel, 0] + 0.5], 1)
        hx0 = R[lj + "_hip"][0]
        hip, knee, rms = _fit_knee(pts, hip_y, hx0, ankle, R[lj + "_knee"], BH,
                                   np.arange(-hx_w * BH, hx_w * BH + 0.1, 0.005 * BH))
        fit[name] = {"hip": hip, "knee": knee, "ankle": ankle, "ankle_run": ankle_run, "rms": rms, "n": int(len(pts)),
                     "shin_w": shin_w, "track": t}
        if len(pts) < 0.08 * BH:
            pen["axis_" + name] = 0.15 if not robe else 0.05
        if rms > 0.35 * leg_w:
            pen["axis_fit_" + name] = min(0.3, (rms / leg_w - 0.35))
        kmove = float(np.hypot(*(knee - R[lj + "_knee"]))) / BH
        if kmove > 0.08:
            pen["knee_" + name] = 0.1
    if fit.get("front") is None or fit.get("back") is None:
        report["flags"].append("leg axis not found")
        fr = fit.get("front") or fit.get("back")
        if fr is None:
            fr = {"hip": np.array([R["front_hip"][0], hip_y]), "knee": R["front_knee"],
                  "ankle": R["front_ankle"], "rms": 99, "n": 0, "shin_w": leg_w, "track": None}
        fit["front"] = fit.get("front") or fr
        fit["back"] = fit.get("back") or fr
    F, B = fit["front"], fit["back"]
    hipx = (F["hip"][0] + B["hip"][0]) / 2
    hip = np.array([hipx, hip_y])
    pelvis = np.array([hipx, hip_y - 0.02 * BH])
    # ---- front foot
    front_mask = body.copy()
    front_mask[: int(F["knee"][1])] = False
    xmid = (F["ankle"][0] + B["ankle"][0]) / 2
    front_mask[:, : int(xmid)] = False
    # only the front leg's own piece: the toe of a long back boot can reach past the middle
    # between the ankles (dwarf layout) and would be measured as part of the front boot
    if front_mask.any():
        fl_, fs_ = components(front_mask)
        ay_, ax_ = int(np.clip(F["ankle"][1], 0, H - 1)), int(np.clip(F["ankle"][0], 0, W - 1))
        near_ank = fl_[max(0, ay_ - 4):ay_ + 5, max(0, ax_ - 4):ax_ + 5]
        ids = near_ank[near_ank > 0]
        if len(ids):
            front_mask = fl_ == np.bincount(ids).argmax()
    ff = fit_foot(front_mask, F["knee"], F["ankle"], F["shin_w"] / 2)
    if ff is None:
        pen["foot"] = 0.3
        report["flags"].append("front foot not measured")
        ff = {"heel": F["ankle"] + [-0.02 * BH, 0.07 * BH], "toe": F["ankle"] + [0.1 * BH, 0.07 * BH],
              "ankle": F["ankle"], "pitch": 0.0, "length": 0.12 * BH, "back": leg_w / 2,
              "front": leg_w / 2}
    # back foot (only used to erase it): toe = most forward pixel of its lowest rows
    bm = body.copy()
    bm[: int(B["ankle"][1])] = False
    bm[:, int(xmid):] = False
    if bm.any():                       # the foot itself, not specks of a plate beside it
        bl_, bs_ = components(bm)
        bm = bl_ == max(bs_, key=bs_.get)
    ys, xs = np.where(bm)
    if len(xs):
        lowm = ys >= ys.max() - 2
        btoe = np.array([xs[lowm].max() + 1.0, ys.max() + 1.0])
        bheel = np.array([xs.min() + 0.0, float(np.median(ys))])
    else:
        btoe, bheel = B["ankle"] + [0.1 * BH, 0.07 * BH], B["ankle"] + [-0.02 * BH, 0.05 * BH]
    # ---- trunk
    neck = R["neck"].copy()
    ny = int(round(neck[1]))
    rr = runs(body[ny], 2)
    for r in rr:
        if r[0] - 0.05 * BH <= neck[0] <= r[1] + 0.05 * BH:
            c = (r[0] + r[1] + 1) / 2
            neck[0] = min(max(c, neck[0] - 0.04 * BH), neck[0] + 0.04 * BH)
            break
    if neck[1] - top < 0.12 * BH:      # head drawn larger than the layout's
        neck[1] = top + 0.16 * BH
    head_top = np.array([top_x, float(top)])
    axis = lambda y: pelvis[0] + (neck[0] - pelvis[0]) * (y - pelvis[1]) / (neck[1] - pelvis[1])
    sh_y = neck[1] + 0.05 * BH
    shoulder = np.array([axis(sh_y) - 0.01 * BH, sh_y])
    # torso lines
    fe, be = [], []
    for y in range(int(sh_y + 0.04 * BH), int(hip_y)):
        ax = axis(y)
        for r in runs(body[y], 2):
            if r[0] - 1 <= ax <= r[1] + 1:
                fe.append(r[1] + 1 - ax)
                be.append(ax - r[0])
                break
    f20 = float(np.percentile(fe, 50)) if fe else 0.12 * BH
    b20 = float(np.percentile(be, 30)) if be else 0.12 * BH
    # ---- arms
    Lu = float(np.hypot(*(LJ["front_elbow"] - LJ["front_shoulder"]))) * s
    Lf = float(np.hypot(*(LJ["front_wrist"] - LJ["front_elbow"]))) * s
    Lu = min(max(Lu, 0.13 * BH), 0.2 * BH)
    Lf = min(max(Lf, 0.12 * BH), 0.2 * BH)
    yy, xx = np.mgrid[0:H, 0:W]
    axx = pelvis[0] + (neck[0] - pelvis[0]) * (yy - pelvis[1]) / (neck[1] - pelvis[1])
    zone = (yy >= sh_y + 0.04 * BH) & (yy <= hip_y + 0.06 * BH)
    margin = 0.015 * BH
    front_zone = body & zone & (xx > axx + f20 + margin)
    back_zone = body & zone & (xx < axx - b20 - margin)
    wrist = None
    hand_blob = np.zeros_like(body)
    if front_zone.any():
        fl, fs = components(front_zone)
        k = max(fs, key=fs.get)
        if fs[k] >= (0.035 * BH) ** 2:
            hand_blob = fl == k
            by, bx = np.where(hand_blob)
            P = np.stack([bx + 0.5, by + 0.5], 1)
            D = np.hypot(*(P - shoulder).T)
            reach = 0.92 * (Lu + Lf)
            cand = np.abs(D - reach) < 0.05 * BH
            if cand.sum() >= 4:
                wrist = P[cand].mean(0)
            else:
                far = P[np.argmax(D)]
                v = (far - shoulder) / max(D.max(), 1e-9)
                wrist = far - v * 0.04 * BH
    if wrist is None:
        pen["arm"] = 0.25
        report["flags"].append("front hand not found, layout arm used")
        wrist = R["front_wrist"]
    # a still drawn on the pose layout (STILL_SPEC.md): the near arm is where the layout put
    # it, so the wrist and elbow are known and not searched (a held hammer's head is further
    # from the shoulder than the hand and used to be taken for it)
    spec_arm = False
    if on_spec and hand_blob.any():
        lw = R["front_wrist"]
        if (hand_blob & (np.hypot(xx + 0.5 - lw[0], yy + 0.5 - lw[1]) < 0.05 * BH)).sum() >= 6:
            wrist = lw.copy()
            spec_arm = True
    report["arm_from_layout"] = spec_arm
    # (b) a second hand of the same colour inside the torso band (a hand on the belt): then
    # the arm drawn over the body is the near arm, and the protruding hand is the far one
    lab_img = to_oklab(img[..., :3].astype(float))
    inner_hand = False
    # the other hand behind the back: a blob of the front hand's colour in the back zone at
    # arm's reach from the shoulder (the far arm is redrawn, so this hand is erased)
    back_hand = np.zeros_like(body)
    if hand_blob.any() and back_zone.any():
        by_, bx_ = np.where(hand_blob)
        dd_ = np.hypot(bx_ + 0.5 - shoulder[0], by_ + 0.5 - shoulder[1])
        tip = np.array([bx_[np.argmax(dd_)] + 0.5, by_[np.argmax(dd_)] + 0.5])
        hb = hand_blob & (np.hypot(xx + 0.5 - tip[0], yy + 0.5 - tip[1]) < 0.045 * BH)
        if hb.sum() >= 6:
            ref = np.median(lab_img[hb], 0)
            close = back_zone & (np.hypot(*(lab_img - ref)[..., 1:].transpose(2, 0, 1)) < INNER_AB) & \
                (np.abs(lab_img[..., 0] - ref[0]) < INNER_L)
            if close.any():
                cl, cs = components(close)
                for kk, sz in sorted(cs.items(), key=lambda kv: -kv[1]):
                    if sz < 0.3 * hb.sum():
                        break
                    m = cl == kk
                    ys4, xs4 = np.where(m)
                    dd = float(np.hypot(xs4.mean() - shoulder[0], ys4.mean() - shoulder[1]))
                    if sz <= 6 * hb.sum() and 0.5 * (Lu + Lf) <= dd <= 1.25 * (Lu + Lf) \
                            and ys4.min() > sh_y + 0.1 * BH:
                        # take the hand's outline and the sleeve end with it
                        r = int(0.03 * BH)
                        grown = m.copy()
                        for _ in range(r):
                            g2 = grown.copy()
                            g2[1:] |= grown[:-1]
                            g2[:-1] |= grown[1:]
                            g2[:, 1:] |= grown[:, :-1]
                            g2[:, :-1] |= grown[:, 1:]
                            grown = g2 & back_zone
                        back_hand = grown
                        report["flags"].append("back hand found at %d,%d (erased)" % (xs4.mean(), ys4.mean()))
                        break
    # how far the silhouette reaches behind the torso's back line at hand height (a back arm
    # swung behind the body shows here; hair and capes end higher or reach less)
    hand_rows = (yy >= sh_y + 0.6 * (Lu + Lf)) & (yy <= hip_y + 0.06 * BH)
    bz = back_zone & hand_rows
    report["back_reach"] = round(float(((axx - b20) - xx)[bz].max()) / BH, 3) if bz.any() else 0.0
    # a hand-coloured blob on the body is only a second arm when the back arm is not
    # visibly swung out behind the body (elves HR1.2 / HR5.2 / HR6.2: reach 0.09-0.15)
    if hand_blob.any() and not back_hand.any() and report["back_reach"] < BACK_ARM_REACH:
        by_, bx_ = np.where(hand_blob)
        dd_ = np.hypot(bx_ + 0.5 - shoulder[0], by_ + 0.5 - shoulder[1])
        tip = np.array([bx_[np.argmax(dd_)] + 0.5, by_[np.argmax(dd_)] + 0.5])
        Pg = np.stack([xx + 0.5, yy + 0.5], -1).astype(float)
        on_thigh = np.zeros_like(body)
        for L_ in (F, B):
            dth, _ = seg_dist(Pg, L_["hip"], L_["knee"])
            on_thigh |= dth < 0.6 * leg_w
        inside = body & (xx > axx - b20) & (xx < axx + f20) & \
            (yy > sh_y + 0.22 * BH) & (yy < hip_y + 0.12 * BH) & ~on_thigh
        for centre, rad in ((tip, 0.045), (wrist, 0.06)):
            hb = hand_blob & (np.hypot(xx + 0.5 - centre[0], yy + 0.5 - centre[1]) < rad * BH)
            if hb.sum() < 6 or inner_hand:
                continue
            ref = np.median(lab_img[hb], 0)
            tip_area = float(hb.sum())
            close = inside & (np.hypot(*(lab_img - ref)[..., 1:].transpose(2, 0, 1)) < INNER_AB) & \
                (np.abs(lab_img[..., 0] - ref[0]) < INNER_L)
            if not close.any():
                continue
            il, isz = components(close)
            kk = max(isz, key=isz.get)
            m = il == kk
            ys3, xs3 = np.where(m)
            compact = (ys3.max() - ys3.min()) < 0.26 * BH and (xs3.max() - xs3.min()) < 0.12 * BH
            low_end = ys3.max() > sh_y + 0.75 * (Lu + Lf)
            # the same colour over the whole body (bare skin, a skirt) must not be bigger
            # than an arm; and a front hand holding gear is never the one erased
            whole = body & (np.hypot(*(lab_img - ref)[..., 1:].transpose(2, 0, 1)) < INNER_AB) & \
                (np.abs(lab_img[..., 0] - ref[0]) < INNER_L)
            wl, ws = components(whole)
            wk = np.bincount(wl[m]).argmax()
            arm_sized = ws.get(int(wk), 0) <= 8.0 * tip_area
            no_gear = hand_blob.sum() <= 3.5 * tip_area
            if 0.4 * tip_area <= isz[kk] <= 6.0 * tip_area and compact and low_end \
                    and arm_sized and no_gear:
                pen["arm_over_body"] = 0.1
                report["flags"].append("possible arm drawn over the body (hand-coloured blob at "
                                       "%d,%d): it would stay painted on the torso" % (xs3.mean(), ys3.mean()))
                if INNER_HAND_SWITCH:
                    inner_hand = True
                    far_extra = hand_blob.copy()
                    hand_blob = m
                    lowm = ys3 >= ys3.max() - 0.03 * BH
                    tip3 = np.array([xs3[lowm].mean() + 0.5, ys3.max() + 1.0])
                    wrist = tip3 - [0.0, 0.07 * BH]
                else:
                    break
    report["inner_hand"] = inner_hand
    d = float(np.hypot(*(wrist - shoulder)))
    if d > 0.98 * (Lu + Lf):
        g = d / (0.98 * (Lu + Lf))
        Lu, Lf = Lu * g, Lf * g
    if d < 0.35 * (Lu + Lf):
        pen["arm_short"] = 0.15
        report["flags"].append("hand very close to the shoulder")
    elbow, wr2 = ik2(shoulder, wrist, Lu, Lf, forward=-1.0)
    if spec_arm:
        elbow, wr2 = R["front_elbow"].copy(), wrist
        shoulder = R["front_shoulder"].copy()
        Lu, Lf = float(np.hypot(*(elbow - shoulder))), float(np.hypot(*(wr2 - elbow)))
    # (a) elbow by colour: the drawn arm has the colour of the sleeve (or skin) where it
    # leaves the torso / near the hand; search elbows around the IK one
    if hand_blob.any() and not spec_arm:
        root = hand_blob & (np.hypot(xx + 0.5 - wrist[0], yy + 0.5 - wrist[1]) < 0.10 * BH) & \
            (np.hypot(xx + 0.5 - wrist[0], yy + 0.5 - wrist[1]) > 0.03 * BH)
        if root.sum() >= 6:
            ref = np.median(lab_img[root], 0)
            elbow, wr2, Lu, Lf, arm_cost = _elbow_by_colour(lab_img, body, shoulder, wrist, elbow,
                                                            ref, BH)
            report["arm_colour_cost"] = round(arm_cost, 3)
    fdir = (wr2 - elbow) / max(float(np.hypot(*(wr2 - elbow))), 1e-9)
    hand_tip = wr2 + fdir * 0.06 * BH
    # every other hand or bare forearm in the picture (the near arm's own pixels excluded)
    Pg_ = np.stack([xx + 0.5, yy + 0.5], -1).astype(float)
    r_arm = 1.5 * 0.045 * BH
    own_arm = (seg_dist(Pg_, shoulder, elbow)[0] < r_arm) | (seg_dist(Pg_, elbow, hand_tip)[0] < r_arm)
    census = hand_census(lab_img, body, hand_blob | (own_arm & body), hand_blob, shoulder, sh_y,
                         hip_y, BH, Lu + Lf, hand_at=(wr2 + hand_tip) / 2 if spec_arm else None)
    # a blob beside one at the back edge is the same hand; what is left inside is an arm
    # drawn over the body
    # blobs under HAND_AREA of a hand are only counted as overlap (G8), never cut as a far hand
    small = [c for c in census if c["area"] < HAND_AREA[0]]
    census = [c for c in census if c["area"] >= HAND_AREA[0]]
    back_any = np.zeros_like(body)
    for c in census:
        if c["zone"] == "back":
            back_any |= c["mask"]
    if back_any.any():
        near_back = dilate(back_any, max(2, int(0.025 * BH)))
        for c in census:
            if c["zone"] == "inside" and (c["mask"] & near_back).any():
                c["zone"] = "back"
                back_any |= c["mask"]
    near_back = dilate(back_any, max(2, int(0.025 * BH))) if back_any.any() else back_any
    small = [c for c in small if c["zone"] == "inside" and not (c["mask"] & near_back).any()]
    report["hands"] = [{k: v for k, v in c.items() if k != "mask"} for c in census + small]
    # G8 score: hand-coloured area over the body, x the front hand's own lit area
    report["arm_overlap"] = round(sum(c["area"] for c in census + small if c["zone"] == "inside"), 2)
    dark = img[..., :3].max(-1) < OUTLINE_DARK
    census_back = back_any | (dilate(back_any, 3) & body & dark & ~own_arm) if back_any.any() else back_any
    # back hand (to erase): a compact blob behind the back line, at arm's reach below the
    # shoulder (a cape or hood behind the back is bigger, or starts higher)
    far_blob = back_hand | census_back
    if inner_hand:
        far_blob |= far_extra
    elif back_zone.any() and not far_blob.any() and not body_only:   # a bare body's far arm is hidden;
        # what sticks out behind its back without the hand's colour is clothing, not a hand
        bl, bs = components(back_zone)
        reach = Lu + Lf
        for k2, sz in sorted(bs.items(), key=lambda kv: -kv[1]):
            if sz < (0.03 * BH) ** 2:
                break
            m = bl == k2
            ys2, xs2 = np.where(m)
            c = np.array([xs2.mean(), ys2.mean()])
            dd = float(np.hypot(*(c - shoulder)))
            compact = sz <= (0.10 * BH) ** 2 and (ys2.max() - ys2.min()) < 0.14 * BH
            if compact and 0.6 * reach <= dd <= 1.15 * reach and ys2.min() > sh_y + 0.12 * BH:
                far_blob |= m
                break
    # ---- gear blobs (G11): rimmed shapes and how much of each lies over the torso front
    report["gear_blobs"] = gear_census(img, body, BH, axis, sh_y, hip_y + 0.08 * BH)
    # ---- a bare body still (G12): nothing rigid and thin, nothing in the hand, no cloth behind
    # the back
    if body_only:
        from .intake import thin_objects
        report["thin_objects"] = [{k: v for k, v in t.items() if k != "mask"} for t in thin_objects(body, BH)]
        hc = (wr2 + hand_tip) / 2
        dh = np.hypot(xx + 0.5 - hc[0], yy + 0.5 - hc[1])
        along = (xx + 0.5 - wr2[0]) * fdir[0] + (yy + 0.5 - wr2[1]) * fdir[1]
        past = hand_blob & (along > -0.03 * BH)
        report["hand_reach"] = round(float(dh[past].max()) / BH, 3) if past.any() else 0.0
        chest_back = lay.get("chest_px", [None, None])[1] or b20
        cloth_ = body & (xx + 0.5 < axis(yy + 0.5) - chest_back - BACK_CLOTH_MARGIN * BH) & \
            (yy > neck[1]) & (yy <= hip_y) & ~far_blob
        report["back_cloth"] = round(float(cloth_.sum()) / (BH * BH), 4)
    # ---- where the hand really is (gear is gripped there): the middle of the hand-coloured
    # pixels near the layout's hand; the image model draws the fist a few px off the layout
    hand_c = (wr2 + hand_tip) / 2
    if hand_blob.any():
        near_ = hand_blob & (np.hypot(xx + 0.5 - hand_c[0], yy + 0.5 - hand_c[1]) < 0.045 * BH)
        if near_.sum() >= 6:
            px_ = lab_img[near_]
            lit_ = px_[px_[:, 0] > np.percentile(px_[:, 0], 35)]
            ref_ = np.median(lit_ if len(lit_) >= 4 else px_, 0)
            skin_ = hand_blob & (np.hypot(*(lab_img - ref_)[..., 1:].transpose(2, 0, 1)) < INNER_AB) & \
                (np.abs(lab_img[..., 0] - ref_[0]) < INNER_L) & \
                (np.hypot(xx + 0.5 - hand_c[0], yy + 0.5 - hand_c[1]) < 0.09 * BH)
            if skin_.sum() >= 6:
                ys_, xs_ = np.where(skin_)
                hand_c = np.array([xs_.mean() + 0.5, ys_.mean() + 0.5])
    # ---- G15: skin colour on the legs (the hand would vanish against the thigh)
    report["leg_skin"] = leg_skin(lab_img, img, body, hand_blob, (wr2 + hand_tip) / 2 if spec_arm else None,
                                  shoulder, BH,
                                  [(F["hip"] * [1, 0] + [0, hip_y], F["knee"]), (F["knee"], ff["ankle"]),
                                   (B["hip"] * [1, 0] + [0, hip_y], B["knee"]), (B["knee"], B["ankle"])],
                                  max(F["shin_w"] / 2, 0.025 * BH), hip_y + LEG_SKIN_TOP * BH)
    # ---- G16: a bare NEAR shin (shorts, a short robe: the lower leg is skin) reads as a bare leg, and its
    # shaded copy for the far leg cannot keep the skin's shade in the palette (HR3.2: one pale
    # pink leg, one grey): the share of EACH shin, knee to ankle, that has the hand's colour
    shin_sk = []
    # the NEAR leg only: the far leg is a shaded copy of it (HR6.3's drawn back calf is bare but
    # the cut never uses it; its near leg is a tall boot)
    for hip_, knee_, ank_ in ((F["hip"] * [1, 0] + [0, hip_y], F["knee"], ff["ankle"]),):
        v_ = leg_skin(lab_img, img, body, hand_blob, (wr2 + hand_tip) / 2 if spec_arm else None,
                      shoulder, BH, [(hip_, knee_), (knee_, ank_)], max(F["shin_w"] / 2, 0.025 * BH),
                      hip_y + LEG_SKIN_TOP * BH, shin_t=LEG_SKIN_SHIN_FULL, thighs=False, tight=LEG_SKIN_DE)
        if v_ is not None:
            shin_sk.append(v_)
    report["shin_skin"] = max(shin_sk) if shin_sk else None
    # ---- radii
    radius = {"thigh": max(0.55 * leg_w, 0.03 * BH), "shin": max(F["shin_w"] / 2, 0.025 * BH),
              "foot": max(0.4 * F["shin_w"], 0.02 * BH), "upper": 0.045 * BH, "fore": 0.042 * BH}
    if hand_blob.any():
        # sleeve width where the arm leaves the torso: median run height of the blob columns
        cols = hand_blob.sum(0)
        cols = cols[cols > 0]
        radius["fore"] = float(min(max(np.median(cols) / 2, 0.03 * BH), 0.06 * BH))
        radius["upper"] = radius["fore"] * 1.08
    # ---- joints out
    J = {"head_top": head_top, "neck": neck, "pelvis": pelvis, "shoulder": shoulder,
         "elbow": elbow, "wrist": wr2, "hand_tip": hand_tip, "hip": F["hip"] * [1, 0] + [0, hip_y],
         "knee": F["knee"], "ankle": ff["ankle"], "heel": ff["heel"], "toe": ff["toe"]}
    far = {"hip": B["hip"] * [1, 0] + [0, hip_y], "knee": B["knee"], "ankle": B["ankle"],
           "heel": bheel, "toe": btoe, "shoulder": R["back_shoulder"], "elbow": R["back_elbow"],
           "wrist": R["back_wrist"]}
    rnd = lambda v: [round(float(v[0]), 2), round(float(v[1]), 2)]
    # ---- how far joints moved from the (registered and raw) layout
    pairs = {"head_top": "head", "neck": "neck", "pelvis": "pelvis", "shoulder": "front_shoulder",
             "elbow": "front_elbow", "wrist": "front_wrist", "hip": "front_hip", "knee": "front_knee",
             "ankle": "front_ankle", "toe": "front_toe"}
    moved = {k: round(float(np.hypot(*(J[k] - LJ[v]))), 1) for k, v in pairs.items()}
    moved.update({"far_" + k: round(float(np.hypot(*(far[k] - LJ["back_" + k]))), 1)
                  for k in ("knee", "ankle")})
    report["layout_swapped"] = {"legs": bool(leg_swap), "arms": bool(arm_swap)}
    report["moved_px"] = moved
    big = [k for k, v in moved.items() if v > MOVE_FLAG * BH and k not in ("head_top",)]
    # arms are expected to move; legs and trunk moving a lot means the layout or the fit is off
    big_body = [k for k in big if k not in ("elbow", "wrist", "shoulder")]
    if big_body:
        pen["moved"] = min(0.3, 0.1 * len(big_body))
        report["flags"].append("moved > %.0f%% BH: %s" % (100 * MOVE_FLAG, ", ".join(big_body)))
    if detached.any():
        pen["detached"] = 0.1
    report["score"] = round(max(0.0, 1.0 - sum(pen.values())), 2)
    report["ok"] = report["score"] >= SCORE_OK
    report["body_height"] = BH
    report["leg_width"] = round(leg_w, 1)
    data = {
        "name": lay.get("id", "char"), "single": True, "auto": True, "ground_y": float(ground),
        "joints": {k: rnd(v) for k, v in J.items()},
        "far": {k: rnd(v) for k, v in far.items()},
        "radius": {k: round(float(v), 2) for k, v in radius.items()},
        "far_shoulder_offset": [round(-0.025 * BH, 2), 0.0],
        "far_hip_offset": [round(float(B["hip"][0] - F["hip"][0]), 2) if robe else round(-0.02 * BH, 2), 0.0],
        "foot_fit": {"pitch": ff["pitch"], "length": round(float(ff["length"]), 2),
                     "back": round(float(ff["back"]), 2), "front": round(float(ff["front"]), 2),
                     "seat": ff.get("seat", [0, 0]), "cut": ff.get("cut")},
        "torso_lines": {"front": round(f20, 2), "back": round(b20, 2)},
        "robe": bool(robe), "merge_y": int(merge_y),
        "stride_still": round(float(ff["heel"][0] - (btoe[0] - ff["length"])), 2),
        "track_ankle": rnd(F.get("ankle_run", F["ankle"])),
        "hand_centre": rnd(hand_c),
        "fit": report,
    }
    if body_only and far_blob.any() and float(far_blob.sum()) > FAR_BLOB_MAX * max(float(hand_blob.sum()), 1.0):
        # pass 7: a hand-coloured blob behind the back of a bare body still that is bigger than
        # FAR_BLOB_MAX x the near arm's own is clothes, not a far arm (HR6.2's white tunic skirt:
        # 2.6 x; HR4.2's real far arm: 0.66 x).  Cut out as "the real far arm" it took the skirt off
        # the torso (a gap at the hips) and swung as an arm, its forearm 4220 px against the near's
        # 1589.  The far arm is then the shaded copy of the near one.
        report["far_blob_dropped"] = int(far_blob.sum())
        far_blob = np.zeros_like(far_blob)
    if far_blob.any():
        # make the far hand solid: close gaps and holes up to 7 % of the body height across (the
        # shaded middle of a hand, the line between hand and cuff), never onto the near arm
        r_ = max(2, int(0.035 * BH))
        grown = dilate(far_blob, r_)
        far_blob = (far_blob | (~dilate(~grown, r_) & body)) & ~hand_blob
    masks = {"body": body, "detached": detached, "plate": plate, "hand": hand_blob,
             "far_hand": far_blob}
    # the far arm: visible in the still (cut out as the real far arm) or hidden (a shaded
    # copy of the near arm is drawn instead); never both
    report["far_arm"] = "visible" if far_blob.any() else "hidden"
    data["far_arm"] = report["far_arm"]
    return img, data, masks


# ------------------------------------------------------------------------- input gate
# Body proportions a fitted still must have before it is animated (fractions of the body
# height, head top to ground).  Adult human: thigh ~0.245, shin ~0.246, upper arm ~0.186,
# forearm ~0.146 of stature (Drillis & Contini 1966); the chunky sprites have bigger heads
# and shorter limbs, dwarves shorter still, so the ranges are wide.
PROPORTIONS = {"thigh": (0.10, 0.34), "shin": (0.09, 0.34), "upper": (0.10, 0.27),
               "fore": (0.08, 0.26)}
LR_SIMILAR = 0.35      # front and back leg segment lengths within 35 % of each other


def gate_still(data):
    """Input gate (RULES.md G1-G6, G8, G9).  Returns a list of "G#: rule: detail" failures and the
    joints to mark on the picture: [(text, [joint names])]."""
    J = {k: np.array(v, float) for k, v in data["joints"].items()}
    F = {k: np.array(v, float) for k, v in data["far"].items()}
    rep = data["fit"]
    BH = rep["body_height"]
    out = []
    flags = " | ".join(rep["flags"])
    # G1 limb count from the silhouette
    if "two feet not found" in flags or "leg axis not found" in flags:
        out.append(("G1: limb_count: two separate legs not found in the silhouette", ["hip", "knee", "ankle"]))
    if "front hand not found" in flags:
        out.append(("G1: limb_count: no hand found outside the torso", ["wrist"]))
    # G2 proportions
    L = {"thigh": np.hypot(*(J["knee"] - J["hip"])), "shin": np.hypot(*(J["ankle"] - J["knee"])),
         "upper": np.hypot(*(J["elbow"] - J["shoulder"])), "fore": np.hypot(*(J["wrist"] - J["elbow"]))}
    names = {"thigh": ["hip", "knee"], "shin": ["knee", "ankle"], "upper": ["shoulder", "elbow"],
             "fore": ["elbow", "wrist"]}
    for k, (lo, hi) in PROPORTIONS.items():
        r = L[k] / BH
        if not lo <= r <= hi:
            out.append((f"G2: proportions: {k} is {r:.2f} of the body height (human {lo:.2f}-{hi:.2f})", names[k]))
    # front vs back leg: both measured to the top of the foot (the foot model moves the
    # front ankle down to anatomical height, the back one is not refitted)
    Lc = dict(L)
    if "track_ankle" in data:
        Lc["shin"] = np.hypot(*(np.array(data["track_ankle"]) - J["knee"]))
    for k, a, b in (("thigh", "hip", "knee"), ("shin", "knee", "ankle")):
        lb = np.hypot(*(F[b] - F[a]))
        if abs(lb / max(Lc[k], 1e-6) - 1) > LR_SIMILAR:
            out.append((f"G2: proportions: front {k} {Lc[k]:.0f}px vs back {k} {lb:.0f}px", ["far_" + a, "far_" + b]))
    # G3 knee and elbow angles in the still
    def ang(v):
        return math.degrees(math.atan2(v[0], v[1]))
    for side, S in (("front", J), ("back", F)):
        kf = (ang(S["knee"] - S["hip"]) - ang(S["ankle"] - S["knee"]) + 180) % 360 - 180
        if not -5.0 <= kf <= 150.0:
            out.append((f"G3: joint_angle: {side} knee flexion {kf:.0f} deg (knee bends back only, 0..150)",
                        ["knee"] if side == "front" else ["far_knee"]))
    ef = (ang(J["wrist"] - J["elbow"]) - ang(J["elbow"] - J["shoulder"]) + 180) % 360 - 180
    if not -5.0 <= ef <= 150.0:
        out.append((f"G3: joint_angle: elbow flexion {ef:.0f} deg (elbow bends forward only, 0..150)", ["elbow"]))
    # G4 feet point the facing way
    if J["toe"][0] <= J["heel"][0]:
        out.append(("G4: feet_facing: front foot points backwards", ["heel", "toe"]))
    if F["toe"][0] <= F["ankle"][0] - 0.02 * BH:
        out.append(("G4: feet_facing: back foot points backwards", ["far_ankle", "far_toe"]))
    # G5 fit score
    if rep["score"] < SCORE_OK:
        out.append((f"G5: fit_score: {rep['score']:.2f} < {SCORE_OK} ({flags})", []))
    # G6 a second arm may be painted on the torso
    if "arm drawn over the body" in flags:
        out.append(("G6: two_arms: a hand-coloured blob on the body looks like an arm drawn over "
                    "the torso; it would stay painted on while the cut arm swings", ["shoulder"]))
    # G9 the drawn foot can keep rule R6 (heel on the shin's back edge, toe ahead of its
    # front edge) in every frame of the walk; a boot too short for the leg is the still's fault
    ffit = data.get("foot_fit")
    if ffit and "front foot not measured" not in flags:
        from .foot import foot_faults
        from .motion import STANCE_DORSI_MAX, SWING_ANKLE
        leg = float(L["thigh"] + L["shin"])
        ah = float(np.hypot(*(J["ankle"] - J["heel"]))) if "cut" not in ffit or not ffit["cut"] else \
            abs(float((J["heel"] - J["ankle"]) @ np.array(ffit["cut"][2:])))
        from .foot import plantar_limit
        tol = data.get("heel_tol_px", 5.5)
        flex = (-min(-SWING_ANKLE[0], plantar_limit(ffit["back"], ah, tol)), STANCE_DORSI_MAX)
        for t in foot_faults(ffit["length"], leg, ffit["back"], ffit["front"], ah, flex):
            out.append(("G9: foot_length: " + t, ["heel", "toe"]))
    # G10 nothing of the background key's colour is left (intake.clean_key removes the rim; a
    # patch it could not remove is unkeyed background)
    if rep.get("key_px", 0) > 0:
        out.append(("G10: key_colour: %d pixel%s of the background key's colour (magenta) left in the "
                    "still after cleaning its rim: the background is not keyed out there"
                    % (rep["key_px"], "" if rep["key_px"] == 1 else "s"),
                    [tuple(p) for p in rep.get("key_at", [])]))
    # G11 a shield (any rimmed gear blob) over the torso's front or the near arm hides the arm
    for g in rep.get("gear_blobs", []):
        if g["front"] > GEAR_FRONT_MAX:
            out.append(("G11: gear_on_near_side: a rimmed gear blob (a shield?) of %.3f body heights "
                        "squared at %d,%d lies %.0f %% ahead of the trunk axis (limit %.0f %%): it "
                        "covers the torso's front and the near arm; a shield belongs on the back, "
                        "wholly behind the torso" % (g["area"], g["at"][0], g["at"][1],
                                                     100 * g["front"], 100 * GEAR_FRONT_MAX),
                        [tuple(g["at"])]))
    # G12 a body still is the bare body: gear is drawn separately (gear.py) and never in it
    if rep.get("body_only"):
        for g in rep.get("gear_blobs", []):
            out.append(("G12: gear_in_body: a rimmed blob (a shield?) of %.3f body heights squared at "
                        "%d,%d is drawn into the body still; gear is drawn as its own picture"
                        % (g["area"], g["at"][0], g["at"][1]), [tuple(g["at"])]))
        for t in rep.get("thin_objects", []):
            out.append(("G12: gear_in_body: a long thin rigid object (%.2f body heights long, a weapon "
                        "or staff?) at %d,%d is drawn into the body still; gear is drawn as its own "
                        "picture" % (t["length"], t["at"][0], t["at"][1]), [tuple(t["at"])]))
        if rep.get("hand_reach", 0) > HELD_MAX:
            out.append(("G12: gear_in_body: the near hand's shape reaches %.2f body heights from the "
                        "hand's middle (an empty open hand: at most %.2f): something is held; the "
                        "body still has empty hands" % (rep["hand_reach"], HELD_MAX), ["wrist"]))
        if rep.get("back_cloth", 0) > BACK_CLOTH_MAX:
            out.append(("G12: gear_in_body: %.3f body heights squared of the still hang behind the back "
                        "line (limit %.3f): a cape, cloak or pack is drawn into the body still"
                        % (rep["back_cloth"], BACK_CLOTH_MAX), ["neck"]))
    # G13 nothing loose: every opaque blob is connected to the body
    for b in rep.get("loose", []):
        out.append(("G13: loose_blob: %d px at %d,%d are not connected to the body (a loose piece "
                    "would float beside the walk)" % (b["px"], b["at"][0], b["at"][1]), [tuple(b["at"])]))
    # G15 the legs do not have the hand's colour (bare legs: the hand vanishes against the thigh
    # and cannot be counted)
    if rep.get("leg_skin") is not None and rep["leg_skin"] > LEG_SKIN_MAX:
        out.append(("G15: bare_legs: %.0f %% of the legs have the hand's (skin) colour (limit %.0f %%): "
                    "the hand vanishes against the thigh; trousers or greaves in a colour different "
                    "from the skin" % (100 * rep["leg_skin"], 100 * LEG_SKIN_MAX), ["hip", "knee"]))
    # G16 no bare near shin: the near leg's shin (knee to ankle) is at most 25 % the hand's colour
    if rep.get("shin_skin") is not None and rep["shin_skin"] > LEG_SKIN_SHIN_MAX:
        out.append(("G16: bare_shin: %.0f %% of the near shin has the hand's (skin) colour (limit %.0f %%): "
                    "a bare lower leg under shorts or a short robe; the far leg's shaded copy cannot "
                    "keep a skin shade in the palette and comes out grey beside the pale near leg; "
                    "greaves, boots or long trousers in a colour different from the skin"
                    % (100 * rep["shin_skin"], 100 * LEG_SKIN_SHIN_MAX), ["knee", "ankle"]))
    # G8 every arm in the still belongs to exactly one arm part: a hand or bare forearm drawn
    # over the body cannot be cut from the torso and would stay painted on it (a third arm)
    inside = [h for h in rep.get("hands", []) if h["zone"] == "inside"]
    overlap = sum(h["area"] for h in inside)
    if inside and overlap >= ARM_OVERLAP_MAX:
        h = max(inside, key=lambda c: c["area"])
        out.append(("G8: arm_on_body: a %s is drawn over the body at %d,%d (%d blob%s of the hand's "
                    "colour, %.2f of a hand in all, limit %.2f): it cannot be cut from the torso and "
                    "would stay painted on while the arms swing; draw the near arm clear of the "
                    "torso and the far arm hidden or clear behind the back"
                    % (h["kind"], h["at"][0], h["at"][1], len(inside), "" if len(inside) == 1 else "s",
                       overlap, ARM_OVERLAP_MAX),
                    [tuple(c["at"]) for c in inside]))
    return out


def gate_picture(img, data, fails, path):
    """The still with the fitted skeleton, failed joints ringed red and the rules written."""
    from PIL import ImageDraw
    a = Image.new("RGBA", (img.shape[1], img.shape[0]), (200, 200, 200, 255))
    a.alpha_composite(Image.fromarray(img))
    W = max(img.shape[1], 420)
    can = Image.new("RGBA", (W, img.shape[0] + 16 + 12 * len(fails)), (235, 235, 235, 255))
    can.paste(a, (0, 0))
    d = ImageDraw.Draw(can)
    J = {k: tuple(v) for k, v in data["joints"].items()}
    F = {"far_" + k: tuple(v) for k, v in data["far"].items()}
    for chain, src, col in ((["hip", "knee", "ankle", "heel", "toe"], J, (200, 0, 0)),
                            (["shoulder", "elbow", "wrist", "hand_tip"], J, (230, 120, 0)),
                            (["head_top", "neck", "pelvis"], J, (0, 150, 0)),
                            (["far_hip", "far_knee", "far_ankle"], F, (0, 120, 200))):
        d.line([src[k] for k in chain], fill=col, width=2)
    allj = dict(J)
    allj.update(F)
    y = img.shape[0] + 4
    for text, joints in fails:
        for jn in joints:
            if jn in allj or isinstance(jn, tuple):
                x0, y0 = jn if isinstance(jn, tuple) else allj[jn]
                d.ellipse([x0 - 8, y0 - 8, x0 + 8, y0 + 8], outline=(255, 0, 0), width=3)
        d.text((4, y), text[:110], fill=(160, 0, 0))
        y += 12
    can.save(path)
    return path

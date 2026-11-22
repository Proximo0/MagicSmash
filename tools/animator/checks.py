"""The body-physics gate.  Every rule looks at baked frames (pixels, label map and the posed
joints the frame was drawn from) and returns failures as "frame i: rule: detail".

frames: list of {"rgba", "label", "meta"}; meta has joints (game px), contact, draw_order,
labels, digests.  ctx (from bake.context) has lengths, limits, ground, speed, ...
"""
import numpy as np

from .foot import BEHIND_MAX_PX, ahead_of_front_edge, behind_back_edge
from .rig import JOINT_LIMITS, joint_angles, SIDES

TOL_PX = 1.0       # brief: 1 px at game size, i.e. one pixel of the 56 px sprite (the size the
                   # rules were written for).  A sprite baked at 112 px shows the same still twice
                   # as big, so the same length is 2 of its pixels: every pixel tolerance is
                   # TOL_PX x ctx["size_x"] (1 at 56 px, 2 at 112 px).  A walk that passes at 56 px
                   # passes at 112 px with exactly the same geometry, and never with a worse one.
TOL_DEG = 0.5      # angles are recomputed from float joints; this only absorbs float noise


def _tol(ctx):
    return TOL_PX * float(ctx.get("size_x", 1))


def _J(meta):
    return {k: np.asarray(v, float) for k, v in meta["joints"].items()}


def bone_lengths(frames, ctx):
    out = []
    for i, f in enumerate(frames):
        J = _J(f["meta"])
        for b, a, c in ctx["bones"]:
            d = float(np.hypot(*(J[c] - J[a])))
            if abs(d - ctx["lengths"][b]) > _tol(ctx):
                out.append(f"frame {i}: bone_length: {b} is {d:.1f}px, rig {ctx['lengths'][b]:.1f}px")
    return out


def joint_limits(frames, ctx):
    out = []
    for i, f in enumerate(frames):
        ang = joint_angles(_J(f["meta"]), ctx.get("rest_lean", 0.0))
        for name, v in ang.items():
            lo, hi = JOINT_LIMITS[name.split(".")[-1]]
            if v < lo - TOL_DEG or v > hi + TOL_DEG:
                out.append(f"frame {i}: joint_limit: {name} {v:.1f} deg outside {lo:.0f}..{hi:.0f}")
    return out


def _anchor(J, s, foot_len):
    """Ground anchor of a foot: the lower of heel/toe, as a footprint heel x."""
    heel, toe = J[s + ".heel"], J[s + ".toe"]
    if toe[1] > heel[1] + 1e-6:   # heel lifted: pivoting on the toe
        return toe[0] - foot_len, toe[1]
    return heel[0], heel[1]


def stance_foot(frames, ctx):
    """Planted foot moves back at exactly the forward speed (1 px), and sits on the ground."""
    out = []
    n = len(frames)
    step = -ctx["speed"] / n
    fl = ctx["foot_len"]
    g = ctx["ground"]
    for s in SIDES:
        for i in range(n):
            a, b = frames[i]["meta"], frames[(i + 1) % n]["meta"]
            if a["contact"][s]:
                x0, y0 = _anchor(_J(a), s, fl)
                if abs(y0 - g) > _tol(ctx):
                    what = "sinks below" if y0 > g else "floats above"
                    out.append(f"frame {i}: stance_ground: {s} foot {what} the ground line by {abs(y0 - g):.1f}px")
                if b["contact"][s] and _same_step(ctx, s, a["phase"], i + 1 == n):
                    x1, _ = _anchor(_J(b), s, fl)
                    if abs((x1 - x0) - step) > _tol(ctx):
                        out.append(f"frame {i}: foot_slide: {s} foot moved {x1 - x0:+.1f}px, body speed needs {step:+.1f}px")
    for i, f in enumerate(frames):
        J = _J(f["meta"])
        for s in SIDES:
            low = max(J[s + ".heel"][1], J[s + ".toe"][1])
            if low > g + _tol(ctx):
                out.append(f"frame {i}: foot_sink: {s} foot {low - g:.1f}px below the ground line")
    return out


def _same_step(ctx, s, phase, wraps):
    """Two consecutive stance frames belong to the same footfall (no swing between)."""
    st, du = ctx["stance"][s]
    if du >= 1.0:
        return True
    q = (phase - st) % 1.0
    q1 = q + 1.0 / ctx["n"]
    return q1 < du + 1e-9


def feet_facing(frames, ctx):
    out = []
    for i, f in enumerate(frames):
        J = _J(f["meta"])
        for s in SIDES:
            dx = (J[s + ".toe"][0] - J[s + ".heel"][0]) * ctx["facing"]
            if dx <= 0:
                out.append(f"frame {i}: foot_direction: {s} foot points backwards (toe {dx:+.1f}px from heel)")
    return out


def heel_flush(frames, ctx):
    """The heel is the bottom of the shin's back edge (owner, 22 Nov): for each foot in each
    frame, foot pixels behind the shin's back edge line (extended down to the ground) are at
    most BEHIND_MAX_PX wide in any row, and the foot reaches ahead of the shin's front edge.
    Measured on the baked pixels (label map) and on the posed rig (heel within 1 px of the
    back line, toe ahead of the front line)."""
    out = []
    back, front = ctx["shin_back"], ctx["shin_front"]
    for i, f in enumerate(frames):
        J = _J(f["meta"])
        names = f["meta"]["labels"]
        lab = f["label"]
        for s in SIDES:
            kn, an = J[s + ".knee"], J[s + ".ankle"]
            hb = float(behind_back_edge(J[s + ".heel"], kn, an, back, ctx["facing"]))
            ta = float(ahead_of_front_edge(J[s + ".toe"], kn, an, front, ctx["facing"]))
            if hb > _tol(ctx) or ta <= 0:
                out.append(f"frame {i}: heel_flush: {s} rig heel {hb:+.1f}px behind the shin's back "
                           f"edge, toe {ta:+.1f}px ahead of its front edge")
                continue
            if s + "_foot" not in names:
                continue
            ys, xs = np.where(lab == names.index(s + "_foot"))
            if len(ys) < max(3, 0.5 * ctx.get("foot_px", 0)):
                continue   # mostly hidden behind the other leg
            P = np.stack([xs + 0.5, ys + 0.5], 1)
            beh = behind_back_edge(P, kn, an, back, ctx["facing"]) > 0
            if beh.any():
                w = np.bincount(ys[beh]).max()
                if w > BEHIND_MAX_PX * ctx.get("size_x", 1):
                    out.append(f"frame {i}: heel_flush: {s} foot sticks out {w}px behind the shin's back edge")
            if ahead_of_front_edge(P, kn, an, front, ctx["facing"]).max() <= 0:
                out.append(f"frame {i}: heel_flush: {s} foot does not reach ahead of the shin")
    return out


def draw_order(frames, ctx):
    out = []
    ref = None
    for i, f in enumerate(frames):
        order = f["meta"]["draw_order"]
        idx = {n: k for k, n in enumerate(order)}
        far = [idx[n] for n in order if n.startswith("far_")]
        near = [idx[n] for n in order if n.startswith("near_")]
        t = idx.get("torso")
        if far and t is not None and max(far) > t:
            out.append(f"frame {i}: draw_order: a far limb is drawn over the torso")
        if near and t is not None and min(near) < t:
            out.append(f"frame {i}: draw_order: a near limb is drawn behind the torso")
        for a, b in (("far_thigh", "near_thigh"), ("far_shin", "near_shin"), ("far_foot", "near_foot"),
                     ("far_upper", "near_upper"), ("far_fore", "near_fore")):
            if a in idx and b in idx and idx[a] > idx[b]:
                out.append(f"frame {i}: draw_order: {a} drawn over {b} (near and far swapped)")
        if ref is not None and order != ref:
            out.append(f"frame {i}: draw_order: order changed from frame 0")
        ref = ref or order
    return out


def _runs(row, min_w):
    xs = np.where(row)[0]
    if not len(xs):
        return []
    runs, s = [], xs[0]
    for p, q in zip(xs[:-1], xs[1:]):
        if q != p + 1:
            runs.append((s, p))
            s = q
    runs.append((s, xs[-1]))
    return [r for r in runs if r[1] - r[0] + 1 >= min_w]


def two_legs(frames, ctx):
    """Count leg-wide runs of opaque pixels across the leg rows of each baked frame.
    Leg rows: from the higher knee down to the ground, skipping rows where the torso (cape,
    robe) hangs.  Pixels of arms/gear in front of a leg are bridged, not counted."""
    out = []
    lw = max(2, int(round(ctx["leg_width"] * 0.6)))   # a leg-wide run: 60 % of a shin
    for i, f in enumerate(frames):
        rgba, lab, names = f["rgba"], f["label"], f["meta"]["labels"]
        J = _J(f["meta"])
        bad = np.isin(lab, [k for k, n in enumerate(names) if n in ("torso", "back")])
        bridge = np.isin(lab, [k for k, n in enumerate(names)
                               if n in ("near_upper", "near_fore", "far_upper", "far_fore") or n.startswith("gear:")])
        y0 = int(np.ceil(min(J["near.knee"][1], J["far.knee"][1])))
        y1 = int(ctx["ground"]) - 1
        opaque = rgba[..., 3] > 0
        leg = opaque & ~bad & ~bridge
        best = 0
        checked = 0
        for y in range(max(0, y0), min(y1, rgba.shape[0] - 1) + 1):
            if bad[y].any():
                continue
            checked += 1
            row = leg[y] | bridge[y]
            row = row | (np.roll(row, 1) & np.roll(row, -1))   # 1-px slits do not split a leg
            runs = [r for r in _runs(row, 1) if leg[y, r[0]:r[1] + 1].sum() >= lw]
            # the raised toe of a long boot at heel strike is cut off from its own shin in the
            # rows above the instep: a run made only of one leg's foot pixels, in a row where
            # that leg has another run, is that leg's toe and not another leg
            for side in SIDES:
                if side + "_foot" not in names:
                    continue
                fi = names.index(side + "_foot")
                own = [k for k, n in enumerate(names) if n.startswith(side + "_") and
                       n.split("_")[1] in ("thigh", "shin", "foot")]
                toe = [r for r in runs if (lab[y, r[0]:r[1] + 1][leg[y, r[0]:r[1] + 1]] == fi).all()]
                rest = [r for r in runs if r not in toe and np.isin(lab[y, r[0]:r[1] + 1], own).any()]
                if toe and rest:
                    runs = [r for r in runs if r not in toe]
            if len(runs) > 2:
                out.append(f"frame {i}: two_legs: row {y} has {len(runs)} leg-wide runs (a third leg?)")
                break
            best = max(best, len(runs))
        apart = abs(J["near.ankle"][0] - J["far.ankle"][0]) > 2 * ctx["leg_width"] + 2
        if checked and apart and best < 2:
            out.append(f"frame {i}: two_legs: feet are apart but only {best} leg run found")
    return out


def rigid_parts(frames, ctx):
    out = []
    for i, f in enumerate(frames):
        for nm in ctx["rigid"]:
            d = f["meta"]["digests"].get(nm)
            if d is not None and d != ctx["cut_digests"][nm]:
                out.append(f"frame {i}: rigid_part: {nm} pixels differ from the cut part")
    return out


def cycle_closes(frames, ctx):
    out = []
    c = ctx.get("closing")
    if c is None:
        return ["frame -: cycle_closes: no closing frame"]
    J0, Jc = _J(frames[0]["meta"]), _J(c)
    worst = max(float(np.hypot(*(J0[k] - Jc[k]))) for k in J0)
    if worst > _tol(ctx):
        out.append(f"frame {len(frames) - 1}: cycle_closes: last frame does not lead into frame 0 "
                   f"(joint off by {worst:.1f}px)")
    if c["contact"] != frames[0]["meta"]["contact"]:
        out.append(f"frame {len(frames) - 1}: cycle_closes: foot contacts differ at the loop point")
    cr = ctx.get("closing_rgba")
    if cr is not None and not np.array_equal(cr, frames[0]["rgba"]):
        diff = int((cr != frames[0]["rgba"]).any(-1).sum())
        out.append(f"frame {len(frames) - 1}: cycle_closes: the frame after the last differs from "
                   f"frame 0 in {diff} pixels (cloth or parts do not loop)")
    return out


def mirror_timing(frames, ctx):
    out = []
    (sn, dn), (sf, df) = ctx["stance"]["near"], ctx["stance"]["far"]
    if abs(dn - df) > 1e-6:
        out.append(f"frame -: mirror_timing: near stance {dn:.2f} vs far stance {df:.2f} of the cycle")
    if ctx["travels"] and abs(((sf - sn) % 1.0) - 0.5) > 1e-6:
        out.append(f"frame -: mirror_timing: far step starts {((sf - sn) % 1.0):.2f} cycle after near, not 0.50")
    n = len(frames)
    if ctx["travels"] and n % 2 == 0:
        near = [f["meta"]["contact"]["near"] for f in frames]
        far = [f["meta"]["contact"]["far"] for f in frames]
        if near != far[n // 2:] + far[:n // 2]:
            out.append(f"frame -: mirror_timing: per-frame contacts not mirror-equal: near {near} far {far}")
    return out


def palette(frames, ctx):
    pal = {tuple(int(v) for v in c) for c in ctx["palette"]}
    out = []
    for i, f in enumerate(frames):
        a = f["rgba"]
        al = a[..., 3]
        if not np.isin(al, (0, 255)).all():
            out.append(f"frame {i}: palette: soft alpha")
        cols = {tuple(int(v) for v in c) for c in np.unique(a[al > 0][:, :3], axis=0)}
        new = cols - pal
        if new:
            out.append(f"frame {i}: palette: {len(new)} colours not in the still")
    return out


def key_colour(frames, ctx):
    """R19: no pixel of the background key's colour (magenta, intake.key_mask) in any frame."""
    from .intake import key_mask
    out = []
    for i, f in enumerate(frames):
        n = int(key_mask(f["rgba"]).sum())
        if n:
            out.append(f"frame {i}: key_colour: {n} px of the background key's colour (magenta fringe)")
    return out


def foot_jitter(frames, ctx):
    """The shrunk stance foot jitters at most 1 px frame to frame: between consecutive stance
    frames of the same footfall, the baked foot's ground end (heel end while the heel is down,
    toe end once it rises) keeps its offset to the float footprint within TOL_PX, and its
    lowest row stays on the ground row (FOOT_Y - 1, 1 px slack)."""
    out = []
    n = len(frames)
    g = ctx["ground"]

    def anchor(f, s):
        names = f["meta"]["labels"]
        if s + "_foot" not in names:
            return None
        ys, xs = np.where(f["label"] == names.index(s + "_foot"))
        if len(ys) < max(3, 0.5 * ctx.get("foot_px", 0)):
            return None
        J = _J(f["meta"])
        heel, toe = J[s + ".heel"], J[s + ".toe"]
        # the ground end is read from the same slice of the boot at every baked size: its
        # bottom 2 rows at 56 px, 4 rows at 112 px (the tolerance stays 1 px at any size)
        low = ys >= ys.max() - (2 * int(round(ctx.get("size_x", 1))) - 1)
        if heel[1] >= toe[1] - 0.5:
            return "heel", float(xs[low].min()) - float(heel[0]), int(ys.max())
        return "toe", float(xs[low].max() + 1) - float(toe[0]), int(ys.max())

    for s in SIDES:
        for i in range(n):
            a, b = frames[i], frames[(i + 1) % n]
            if not (a["meta"]["contact"][s] and b["meta"]["contact"][s]):
                continue
            if not _same_step(ctx, s, a["meta"]["phase"], i + 1 == n):
                continue
            pa, pb = anchor(a, s), anchor(b, s)
            if pa is None or pb is None:
                continue
            for k, p in ((i, pa), ((i + 1) % n, pb)):
                if not (g - 2 <= p[2] <= g):
                    out.append(f"frame {k}: foot_jitter: {s} stance foot's lowest row {p[2]}, ground row {g - 1}")
            if pa[0] == pb[0] and abs(pb[1] - pa[1]) > _tol(ctx) + 1e-6:
                out.append(f"frame {i}: foot_jitter: {s} stance foot jumps {pb[1] - pa[1]:+.1f}px "
                           f"against its footprint")
    return sorted(set(out), key=out.index)


def two_arms(frames, ctx):
    """Exactly two arms: one near and one far upper arm + forearm in every frame, each
    forearm hanging off its own upper arm (the hand is where the elbow and forearm put it)."""
    out = []
    for i, f in enumerate(frames):
        order = f["meta"]["draw_order"]
        ups = [n for n in order if n.endswith("_upper")]
        fos = [n for n in order if n.endswith("_fore")]
        if sorted(ups) != ["far_upper", "near_upper"] or sorted(fos) != ["far_fore", "near_fore"]:
            out.append(f"frame {i}: two_arms: arm parts {ups + fos}, need one near and one far arm")
        J = _J(f["meta"])
        for s in SIDES:
            d = float(np.hypot(*(J[s + ".wrist"] - J[s + ".elbow"])))
            if abs(d - ctx["lengths"][s + ".fore"]) > _tol(ctx):
                out.append(f"frame {i}: two_arms: {s} hand is not on its forearm ({d:.1f}px)")
    return out


def loose_blobs(frames, ctx):
    """R24: the baked figure is one connected shape (8-connected); any other opaque blob is a
    loose piece (a stick floating behind the heels, gear that left its hand)."""
    from .imgops import components
    out = []
    for i, f in enumerate(frames):
        lab, sizes = components(f["rgba"][..., 3] > 0)
        if len(sizes) <= 1:
            continue
        main = max(sizes, key=sizes.get)
        for k, s in sizes.items():
            if k == main:
                continue
            ys, xs = np.where(lab == k)
            nm = f["meta"]["labels"][int(np.bincount(f["label"][ys, xs]).argmax())]
            out.append(f"frame {i}: loose_blob: {s} px of {nm} at {int(xs.mean())},{int(ys.mean())} "
                       "are not connected to the body")
    return out


def _gear_layers(f):
    return f["meta"].get("gear", {})


def gear_rigid(frames, ctx):
    """R20: every gear's drawn pixels are its own picture under that frame's rigid move.  The
    sprite is made again from the picture (turn, scale) and compared by hash with what the frame
    holds; every pixel the frame shows of the gear must be that sprite's pixel at that place;
    a gear whose angle does not change (back) has one hash in all frames."""
    import hashlib
    out = []
    first = {}
    for i, f in enumerate(frames):
        names = f["meta"]["labels"]
        for nm, L in _gear_layers(f).items():
            g = ctx["gear"][nm]
            want, _ = g.sprite(ctx["gear_scale"][nm], L["phi"])
            h = hashlib.sha1(np.ascontiguousarray(L["rgba"]).tobytes()).hexdigest()
            if L["rgba"].shape != want.shape or h != hashlib.sha1(np.ascontiguousarray(want).tobytes()).hexdigest():
                out.append(f"frame {i}: gear_rigid: {nm} is not its picture turned {L['phi']:.1f} deg "
                           "(pixels changed)")
                continue
            if L["slot"] == "back":
                if first.setdefault(nm, h) != h:
                    out.append(f"frame {i}: gear_rigid: {nm} (back) differs from frame 0")
            ys, xs = np.where(f["label"] == names.index(nm))
            if not len(ys):
                continue
            sy, sx = ys - L["at"][1], xs - L["at"][0]
            ok = (sy >= 0) & (sx >= 0) & (sy < want.shape[0]) & (sx < want.shape[1])
            same = np.zeros(len(ys), bool)
            same[ok] = (want[sy[ok], sx[ok]] == f["rgba"][ys[ok], xs[ok]]).all(-1) & (want[sy[ok], sx[ok], 3] > 0)
            if not same.all():
                j = int(np.flatnonzero(~same)[0])
                out.append(f"frame {i}: gear_rigid: {int((~same).sum())} px of {nm} in the frame are not "
                           f"its picture's (first at {int(xs[j])},{int(ys[j])})")
    return out


def gear_grip(frames, ctx):
    """R21: a hand-slot gear's grip is within 1 px of the middle of its hand in every frame."""
    from .gear import hand_point
    out = []
    tol = _tol(ctx)
    for i, f in enumerate(frames):
        J = f["meta"]["joints"]
        for nm, L in _gear_layers(f).items():
            if L["slot"] not in ("near_hand", "far_hand"):
                continue
            s = L["slot"][:-5]
            hand = hand_point(J[s + ".elbow"], J[s + ".wrist"], ctx["hand_local"])
            d = float(np.hypot(*(np.array(L["grip"], float) - hand)))
            if d > tol:
                out.append(f"frame {i}: gear_grip: {nm} grip is {d:.1f} px from the {s} hand (max {tol:.0f})")
    return out


def gear_back(frames, ctx):
    """R22: back gear never draws over the near arm (it is behind the torso and the near arm,
    in front of the far arm)."""
    out = []
    for i, f in enumerate(frames):
        body = f.get("body")
        if body is None:
            continue
        names = f["meta"]["labels"]
        arm = np.isin(body["label"], [names.index(n) for n in ("near_upper", "near_fore") if n in names])
        for nm, L in _gear_layers(f).items():
            if L["slot"] not in ("back", "cape"):
                continue
            n = int((arm & (f["label"] == names.index(nm))).sum())
            if n:
                out.append(f"frame {i}: gear_back: {nm} covers {n} px of the near arm")
            t = names.index("torso") if "torso" in names else None
            if t is not None and L["rank"] > t:
                out.append(f"frame {i}: gear_back: {nm} is layered in front of the torso")
    return out


def gear_head(frames, ctx):
    """R23: gear never covers the head (the body's pixels above the neck joint's row)."""
    out = []
    for i, f in enumerate(frames):
        body = f.get("body")
        if body is None:
            continue
        names = f["meta"]["labels"]
        neck = int(np.floor(f["meta"]["joints"]["neck"][1]))
        head = body["label"] > 0
        head[neck:] = False
        for nm in _gear_layers(f):
            n = int((head & (f["label"] == names.index(nm))).sum())
            if n:
                out.append(f"frame {i}: gear_head: {nm} covers {n} px of the head")
    return out


def gear_legs(frames, ctx):
    """R25: gear held in a hand never crosses the legs below the knees (shins and feet)."""
    out = []
    for i, f in enumerate(frames):
        body = f.get("body")
        if body is None:
            continue
        names = f["meta"]["labels"]
        low = np.isin(body["label"], [names.index(n) for n in names if n.endswith("_shin") or n.endswith("_foot")])
        for nm, L in _gear_layers(f).items():
            if L["slot"] not in ("near_hand", "far_hand"):
                continue
            x0, y0 = L["at"]
            h, w = L["rgba"].shape[:2]
            H, W = low.shape
            cx0, cy0, cx1, cy1 = max(x0, 0), max(y0, 0), min(x0 + w, W), min(y0 + h, H)
            if cx1 <= cx0 or cy1 <= cy0:
                continue
            n = int((low[cy0:cy1, cx0:cx1] & (L["rgba"][cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0, 3] > 0)).sum())
            if n:
                out.append(f"frame {i}: gear_legs: {nm} crosses {n} px of a shin or foot")
    return out


HAND_SHARE = 0.6     # the hand's commonest lit colours covering this share of it are "hand colours"
HAND_COMMON = 3.0    # see hand_colours
HAND_BLOB = 0.4      # a blob of them off the forearms, this big x a hand (min 3 px), is another hand
ARM_ROWS = 0.08      # arm rows run from the shoulders to this far (x body height) below the hips


def hand_colours(part_img, wrist, tip, lit=70, other=None):
    """The colours a hand is made of: the commonest lit colours of a forearm part's pixels
    around the hand (between wrist and tip), up to HAND_SHARE of them.  A colour that the
    rest of the body (`other`: images of the non-arm parts) uses HAND_COMMON times more than
    the hand does is cloth the cuff shares with the clothes, not a hand colour.  Returns
    (set of (r,g,b), number of hand pixels in still px)."""
    wrist = np.asarray(wrist, float)
    tip = np.asarray(tip, float)
    mid = (wrist + tip) / 2
    r = max(float(np.hypot(*(tip - wrist))) * 0.75, 2.0)
    ys, xs = np.where(part_img[..., 3] > 0)
    if not len(ys):
        return set(), 0
    near = np.hypot(xs + 0.5 - mid[0], ys + 0.5 - mid[1]) <= r
    px = part_img[ys[near], xs[near], :3]
    n_hand = len(px)
    px = px[px.max(1) >= lit]
    if not len(px):
        return set(), n_hand
    cols, cnt = np.unique(px, axis=0, return_counts=True)
    if other:
        key = lambda a: a[:, 0].astype(np.int64) * 65536 + a[:, 1].astype(np.int64) * 256 + a[:, 2]
        ok = np.concatenate([o[o[..., 3] > 0][:, :3] for o in other])
        if len(ok):
            ks, kc = np.unique(key(ok), return_counts=True)
            elsewhere = dict(zip(ks.tolist(), kc.tolist()))
            keep = np.array([elsewhere.get(int(k_), 0) <= HAND_COMMON * c_ for k_, c_ in zip(key(cols), cnt)])
            cols, cnt = cols[keep], cnt[keep]
            if not len(cols):
                return set(), n_hand
    order = np.argsort(-cnt)
    out, acc = set(), 0
    for i in order:
        out.add(tuple(int(v) for v in cols[i]))
        acc += cnt[i]
        if acc >= HAND_SHARE * cnt.sum():
            break
    return out, n_hand


def _blobs(mask):
    """4-connected blobs of a small bool image: list of (size, y, x of its centre)."""
    seen = np.zeros_like(mask)
    out = []
    H, W = mask.shape
    for y, x in zip(*np.where(mask)):
        if seen[y, x]:
            continue
        stack, pts = [(y, x)], []
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            pts.append((cy, cx))
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        a = np.array(pts)
        out.append((len(pts), float(a[:, 0].mean()), float(a[:, 1].mean())))
    return out


def arm_count(frames, ctx):
    """At most two arms and two hands in any frame (owner, 22 Nov: "there is three arms
    there"), measured on the baked pixels and not on the rig: in the arm rows (shoulders to
    just below the hips) every blob of the hands' colours that is as big as a hand must lie
    on a forearm part, at the end of that forearm (around its wrist and hand tip), and there
    are at most two such blobs.  A hand painted on the torso, cape, robe or a leg fails."""
    out = []
    cols = ctx.get("hand_colours")
    if not cols:
        return out
    k = ctx["k"]
    min_px = max(3.0, HAND_BLOB * ctx.get("hand_px", 0) * k * k)
    lut = np.array(sorted(cols), np.int32)
    keys = lut[:, 0] * 65536 + lut[:, 1] * 256 + lut[:, 2]
    reach = ctx["lengths"]["near.hand"] * 1.5 + 2.0
    for i, f in enumerate(frames):
        J = _J(f["meta"])
        names = f["meta"]["labels"]
        rgba, lab = f["rgba"], f["label"]
        y0 = int(min(J["near.shoulder"][1], J["far.shoulder"][1]))
        y1 = int(max(J["near.hip"][1], J["far.hip"][1]) + ARM_ROWS * ctx["body_h"]) + 1
        code = rgba[..., 0].astype(np.int32) * 65536 + rgba[..., 1].astype(np.int32) * 256 + rgba[..., 2]
        hand = np.isin(code, keys) & (rgba[..., 3] > 0)
        hand[:max(y0, 0)] = False
        hand[y1:] = False
        arm_ids = [names.index(n) for n in names
                   if n.endswith("_upper") or n.endswith("_fore") or n.startswith("gear:")]
        fore = {s: names.index(s + "_fore") for s in SIDES if s + "_fore" in names}
        off = hand & ~np.isin(lab, arm_ids)
        for sz, cy, cx in _blobs(off):
            if sz >= min_px:
                out.append(f"frame {i}: arm_count: a hand-coloured blob of {sz}px at {cx:.0f},{cy:.0f} is not "
                           f"on a forearm (a third hand or arm painted on the body)")
        n_hands = 0
        for s, li in fore.items():
            on_bone = 0
            for sz, cy, cx in _blobs(hand & (lab == li)):
                if sz < min_px:
                    continue
                seg = _seg_d(np.array([cx + 0.5, cy + 0.5]), J[s + ".elbow"], J[s + ".hand_tip"])
                if seg > reach:
                    out.append(f"frame {i}: arm_count: {s} hand is {seg:.1f}px off the end of its forearm")
                # skin along one forearm's own bone is that one arm (a bare forearm and its hand
                # parted by a wristband are two blobs); a blob beside the bone is another hand
                if seg <= ctx.get("fore_r", 0.0) + 0.5:
                    on_bone = 1
                else:
                    n_hands += 1
            n_hands += on_bone
        if n_hands > 2:
            out.append(f"frame {i}: arm_count: {n_hands} hand-sized blobs on the forearms (at most two hands)")
    return out


def _seg_d(p, a, b):
    ab = b - a
    t = min(1.0, max(0.0, float((p - a) @ ab) / max(float(ab @ ab), 1e-9)))
    return float(np.hypot(*(p - (a + t * ab))))


ARM_HANG = 0.45      # mid-stance (nearest baked frame, up to 1/16 cycle off): wrist within this
                     # x arm length sideways of its shoulder (an arm at 25 deg is 0.42)
ARM_FWD = 32.0       # deg: a free upper arm is never further than this from hanging down
ARM_MEAN = 12.0      # deg: ... and over the cycle it is centred on hanging within this
ARM_MIN_SWING = 20.0  # deg: peak to peak; less is a stiff arm
LEGS_APART = 0.3     # x thigh length between the two feet's reach: above this the walk has steps


def _vert(v):
    """Angle of a limb from straight down, + = forward (the facing way), degrees."""
    return float(np.degrees(np.arctan2(v[0], v[1])))


def arm_swing(frames, ctx):
    """Arms swing opposite to the legs and hang near the body at mid-stance (owner brief,
    22 Nov: "the near arm is held stretched out in front ... the walk reads stiff").  For
    each free arm (an arm carrying long gear is held steady and is exempt, ctx steady_arms):
    when a foot is furthest ahead (its heel strike) the arm on that side is behind the other
    arm, and over the cycle arms and feet move against each other; in the frame where the feet pass each other the wrist is within ARM_HANG arm lengths
    of the line straight down from the shoulder; the upper arm never leaves hanging by more
    than ARM_FWD, is centred on hanging over the cycle, and swings at least ARM_MIN_SWING."""
    out = []
    f_ = ctx.get("facing", 1)
    steady = set(ctx.get("steady_arms", ()))
    A = {s: [] for s in SIDES}
    T = {s: [] for s in SIDES}
    for f in frames:
        J = _J(f["meta"])
        for s in SIDES:
            A[s].append(_vert((J[s + ".elbow"] - J[s + ".shoulder"]) * [f_, 1]))
            T[s].append(float(J[s + ".ankle"][0] - J[s + ".hip"][0]) * f_)   # foot ahead of its hip
    if not ctx.get("travels", True) or len(frames) < 2:
        return out
    free = [s for s in SIDES if s not in steady]
    dt = np.array(T["near"]) - np.array(T["far"])
    da = np.array(A["near"]) - np.array(A["far"])
    if len(free) == 2 and dt.max() - dt.min() > LEGS_APART * ctx["lengths"]["near.thigh"]:
        # opposite phase: with the near foot furthest ahead the near arm is the one behind,
        # and the other way round; over the whole cycle the two differences move against
        # each other (the arms trail the legs by a few frames, so not every frame is tested)
        for i, lead in ((int(np.argmax(dt)), "near"), (int(np.argmin(dt)), "far")):
            if da[i] * dt[i] >= 0:
                out.append(f"frame {i}: arm_swing: {lead} leg and {lead} arm are both forward "
                           f"(arms must swing opposite to the legs)")
        if float(np.sum((da - da.mean()) * (dt - dt.mean()))) >= 0:
            out.append("frame 0: arm_swing: over the cycle the arms swing with the legs, not against them")
    for i in range(len(frames)):
        for s in free:
            if abs(A[s][i]) > ARM_FWD:
                out.append(f"frame {i}: arm_swing: {s} upper arm is {A[s][i]:+.0f} deg from hanging "
                           f"(held out, limit {ARM_FWD:.0f})")
    # mid-stance: the frame where the swinging foot passes the planted one
    mid = int(np.argmin([abs(float(_J(f["meta"])["near.ankle"][0] - _J(f["meta"])["far.ankle"][0]))
                         for f in frames]))
    Jm = _J(frames[mid]["meta"])
    arm_len = ctx["lengths"]["near.upper"] + ctx["lengths"]["near.fore"]
    for s in free:
        dx = abs(float(Jm[s + ".wrist"][0] - Jm[s + ".shoulder"][0]))
        if dx > ARM_HANG * arm_len or Jm[s + ".wrist"][1] <= Jm[s + ".shoulder"][1]:
            out.append(f"frame {mid}: arm_swing: at mid-stance the {s} hand is {dx:.1f}px from the line "
                       f"under its shoulder (arm must hang near the body, limit {ARM_HANG * arm_len:.1f})")
        if abs(float(np.mean(A[s]))) > ARM_MEAN:
            out.append(f"frame 0: arm_swing: {s} arm swings about {np.mean(A[s]):+.0f} deg, not about hanging")
        if max(A[s]) - min(A[s]) < ARM_MIN_SWING:
            out.append(f"frame 0: arm_swing: {s} arm swings only {max(A[s]) - min(A[s]):.0f} deg (stiff)")
    return out


RULES = [arm_count, arm_swing, bone_lengths, joint_limits, stance_foot, feet_facing, heel_flush, draw_order, two_legs,
         rigid_parts, cycle_closes, mirror_timing, palette, foot_jitter, two_arms, key_colour,
         gear_rigid, gear_grip, gear_back, gear_head, gear_legs, loose_blobs]


def run_all(frames, ctx):
    out = []
    for r in RULES:
        out += r(frames, ctx)
    return out


# RULES.md numbers of the rule words used in failure messages ("frame i: <word>: ...")
RULE_IDS = {"two_legs": "R1", "two_arms": "R2", "joint_limit:knee": "R3", "joint_limit:elbow": "R4",
            "foot_direction": "R5", "heel_flush": "R6", "foot_slide": "R7", "stance_ground": "R8",
            "foot_sink": "R8", "bone_length": "R9", "joint_limit": "R10", "draw_order": "R11",
            "rigid_part": "R12", "cycle_closes": "R13", "mirror_timing": "R14", "palette": "R15",
            "foot_jitter": "R16", "arm_count": "R17", "arm_swing": "R18", "key_colour": "R19",
            "gear_rigid": "R20", "gear_grip": "R21", "gear_back": "R22", "gear_head": "R23",
            "loose_blob": "R24", "gear_legs": "R25"}


def rule_id(failure):
    """RULES.md number of a failure string."""
    parts = [p.strip() for p in failure.split(":")]
    word = parts[1] if len(parts) > 1 else ""
    if word == "joint_limit" and len(parts) > 2:
        j = parts[2].split()[0].split(".")[-1]
        return RULE_IDS.get("joint_limit:" + j, "R10")
    return RULE_IDS.get(word, "R?")

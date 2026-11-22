"""The body-physics gate.  Every rule looks at baked frames (pixels, label map and the posed
joints the frame was drawn from) and returns failures as "frame i: rule: detail".

frames: list of {"rgba", "label", "meta"}; meta has joints (game px), contact, draw_order,
labels, digests.  ctx (from bake.context) has lengths, limits, ground, speed, ...
"""
import numpy as np

from .rig import JOINT_LIMITS, joint_angles, SIDES

TOL_PX = 1.0       # brief: 1 px at game size
TOL_DEG = 0.5      # angles are recomputed from float joints; this only absorbs float noise


def _J(meta):
    return {k: np.asarray(v, float) for k, v in meta["joints"].items()}


def bone_lengths(frames, ctx):
    out = []
    for i, f in enumerate(frames):
        J = _J(f["meta"])
        for b, a, c in ctx["bones"]:
            d = float(np.hypot(*(J[c] - J[a])))
            if abs(d - ctx["lengths"][b]) > TOL_PX:
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
                if abs(y0 - g) > TOL_PX:
                    what = "sinks below" if y0 > g else "floats above"
                    out.append(f"frame {i}: stance_ground: {s} foot {what} the ground line by {abs(y0 - g):.1f}px")
                if b["contact"][s] and _same_step(ctx, s, a["phase"], i + 1 == n):
                    x1, _ = _anchor(_J(b), s, fl)
                    if abs((x1 - x0) - step) > TOL_PX:
                        out.append(f"frame {i}: foot_slide: {s} foot moved {x1 - x0:+.1f}px, body speed needs {step:+.1f}px")
    for i, f in enumerate(frames):
        J = _J(f["meta"])
        for s in SIDES:
            low = max(J[s + ".heel"][1], J[s + ".toe"][1])
            if low > g + TOL_PX:
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
    if worst > TOL_PX:
        out.append(f"frame {len(frames) - 1}: cycle_closes: last frame does not lead into frame 0 "
                   f"(joint off by {worst:.1f}px)")
    if c["contact"] != frames[0]["meta"]["contact"]:
        out.append(f"frame {len(frames) - 1}: cycle_closes: foot contacts differ at the loop point")
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


RULES = [bone_lengths, joint_limits, stance_foot, feet_facing, draw_order, two_legs,
         rigid_parts, cycle_closes, mirror_timing, palette]


def run_all(frames, ctx):
    out = []
    for r in RULES:
        out += r(frames, ctx)
    return out

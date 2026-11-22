"""Cut a fitted full-size still into parts with NO hand-written shapes.

Labels, first match wins (all from the fitted joints and the fit masks):
  1. hand blob (the front hand and anything it holds, from fit) + near arm capsules -> arm;
     a detached piece (a staff standing beside the hand) within DETACH_REACH of the hand -> arm
  2. back-hand blob (fit) -> erased (the far arm is redrawn as a shaded copy of the near one)
  3. legs below the hip: front leg capsules -> near leg; back leg capsules -> erased.  Under a
     robe (fit: the legs only part at the hem) the legs only claim rows below the hem
  4. cloth, marked automatically:
       cape  = above the hip, below the neck, BEHIND the torso's back line (fit), not arm;
       robe  = below the hip and not leg (skirts, robes, loin cloths, tunic flaps, pouches)
  5. the rest -> torso (head included)
Holes where the near arm / erased limbs covered the torso, cape or robe are refilled from the
part's own pixels (row sweep from the facing side, then onion peel).  Legs hidden under a robe
are extended up to the hip with their own colours, so a leg swinging out under the hem never
shows a gap.  Overlap caps at shoulder, hip, elbow, knee and ankle as in cut.py.
"""
import numpy as np

from .colour import darken, quantize
from .cut import Part, FAR_OF, NEAR_ARM, NEAR_LEG
from .foot import below_ankle, reseat
from .imgops import dilate, fill, seg_dist, components

DETACH_REACH = 0.25   # x body height: a loose piece this close to the hand is held gear
CAPE_MARGIN = 0.02    # x body height behind the torso's back line before cloth starts
LEG_R = 1.15          # leg capsule reach (x measured radius) below the hip


def _sweep_front(img, own, holes):
    """Row by row, fill holes from the facing (+x) side: the cloth in front continues behind
    the arm.  Vectorized per column from right to left."""
    img = img.copy()
    own = own.copy()
    todo = holes & ~own
    H, W = own.shape
    cols = np.flatnonzero(todo.any(0))
    for x in sorted(cols, reverse=True):
        if x + 1 >= W:
            continue
        m = todo[:, x] & own[:, x + 1]
        img[m, x] = img[m, x + 1]
        own[m, x] = True
    return img


def _row_hull(mask):
    H, W = mask.shape
    out = np.zeros_like(mask)
    any_ = mask.any(1)
    first = np.argmax(mask, 1)
    last = W - 1 - np.argmax(mask[:, ::-1], 1)
    xs = np.arange(W)
    out = (xs[None, :] >= first[:, None]) & (xs[None, :] <= last[:, None]) & any_[:, None]
    return out


def cut_auto(still, rig, masks):
    data = rig.data
    j = rig.j
    far = {k: np.array(v, float) for k, v in data["far"].items()}
    body = masks["body"]
    det = masks["detached"]
    img = still.copy()
    img[~(body | det)] = 0
    img, pal = quantize(img)
    A = img[..., 3] > 0
    H, W = A.shape
    BH = rig.body_height
    R = {k: float(v) for k, v in data["radius"].items()}
    yy, xx = np.mgrid[0:H, 0:W]
    P = np.stack([xx + 0.5, yy + 0.5], -1).astype(float)

    def cap(a, b, r, gate=None):
        d, t = seg_dist(P, a, b)
        n = d / r
        if gate is not None:
            n = np.where(t >= gate, n, np.inf)
        return n

    def foot_n(J):
        ds = [seg_dist(P, J["heel"], J["toe"])[0], seg_dist(P, J["ankle"], J["heel"])[0],
              seg_dist(P, J["ankle"], J["toe"])[0]]
        return np.minimum.reduce(ds) / R["foot"]

    # the foot where it is DRAWN: the rig's heel and toe are already re-seated (foot.py)
    seat0 = np.array((data.get("foot_fit") or {}).get("seat") or [0, 0], float)
    drawn_foot = {"heel": j["heel"] - seat0, "toe": j["toe"] - seat0, "ankle": j["ankle"]}
    arm_n = {"near_upper": cap(j["shoulder"], j["elbow"], R["upper"], gate=-0.1),
             "near_fore": np.minimum(cap(j["elbow"], j["wrist"], R["fore"], gate=0.0),
                                     cap(j["wrist"], j["hand_tip"], R["fore"] * 1.2))}
    leg_n = {"near_thigh": cap(j["hip"], j["knee"], R["thigh"], gate=0.0),
             "near_shin": cap(j["knee"], j["ankle"], R["shin"], gate=0.0),
             "near_foot": foot_n(drawn_foot)}
    bfoot = {"heel": far["heel"], "toe": far["toe"], "ankle": far["ankle"]}
    back_leg = np.minimum.reduce([cap(far["hip"], far["knee"], R["thigh"], gate=0.0),
                                  cap(far["knee"], far["ankle"], R["shin"], gate=0.0),
                                  foot_n(bfoot) * 0.9])
    names = ["bg", "torso", "cape", "robe", *NEAR_ARM, *NEAR_LEG, "far_erased"]
    code = {n: i for i, n in enumerate(names)}
    lab = np.zeros((H, W), np.int16)
    free = A.copy()

    def take(m, name):
        m = m & free
        lab[m] = code[name]
        free[m] = False

    hip_y = float(j["hip"][1])
    robe_mode = bool(data.get("robe"))
    merge_y = float(data.get("merge_y", hip_y))
    # 1. arm: hand blob (+ held gear), then capsules
    hand = masks["hand"] & A
    if det.any():
        dl, ds = components(det)
        for k in ds:
            m = dl == k
            ys, xs = np.where(m)
            d = np.hypot(xs - j["hand_tip"][0], ys - j["hand_tip"][1]).min()
            if d <= DETACH_REACH * BH:
                hand |= m
            else:
                img[m] = 0
                A[m] = False
                free[m] = False
    # held gear continues past the hand blob's rows: grow the blob through pixels that are
    # outside the torso band and not leg (a staff reaching the ground)
    axis_x = lambda y: j["pelvis"][0] + (j["neck"][0] - j["pelvis"][0]) * (y - j["pelvis"][1]) / (j["neck"][1] - j["pelvis"][1])
    front_line = axis_x(yy + 0.5) + data["torso_lines"]["front"] + 0.015 * BH
    legs_any = np.minimum.reduce(list(leg_n.values()) + [back_leg]) <= LEG_R
    outside = A & (xx + 0.5 > front_line) & ~legs_any
    if hand.any():
        for _ in range(int(0.6 * BH)):
            g = dilate(hand, 1) & outside
            g |= hand
            if np.array_equal(g, hand):
                break
            hand = g
    arm_st = np.stack([arm_n[n] for n in NEAR_ARM])
    arm_best = np.argmin(arm_st, 0)
    in_arm = arm_st.min(0) <= 1.0
    take(hand & (arm_best == 0) & (arm_n["near_upper"] <= 1.0), "near_upper")
    take(hand, "near_fore")
    for i, n in enumerate(NEAR_ARM):
        take(in_arm & (arm_best == i), n)
    # 2. back hand -> erased
    # (with a 3 px rim, so no fringe of the hand is left for the hole fill to smear)
    far_hand = masks["far_hand"]
    if far_hand.any():
        far_hand = far_hand | (dilate(far_hand, 3) & A)
    take(far_hand, "far_erased")
    # 3. legs
    below = P[..., 1] > hip_y
    leg_rows = (P[..., 1] >= merge_y - 0.01 * BH) if robe_mode else below
    lst = np.stack([leg_n[n] for n in NEAR_LEG] + [back_leg])
    lbest = np.argmin(lst, 0)
    in_leg = (lst.min(0) <= LEG_R) & leg_rows
    lnames = [*NEAR_LEG, "far_erased"]
    # the foot is everything of the front leg below the ankle line (foot.fit_foot)
    cut_line = (data.get("foot_fit") or {}).get("cut")
    if cut_line:
        low = below_ankle(P, cut_line)
        near_lower = in_leg & ((lbest == 1) | (lbest == 2))
        lbest = np.where(near_lower, np.where(low, 2, 1), lbest)
    for i, n in enumerate(lnames):
        take(in_leg & (lbest == i), n)
    # 4. cloth
    back_line = axis_x(yy + 0.5) - data["torso_lines"]["back"] - CAPE_MARGIN * BH
    cape = (xx + 0.5 < back_line) & (P[..., 1] > j["neck"][1]) & ~below
    take(cape, "cape")
    take(below & (P[..., 1] > hip_y + 0.02 * BH), "robe")
    # 5. torso
    take(A, "torso")
    # small islands of a cloth label that do not touch the rest of it go to the torso
    for nm in ("cape", "robe"):
        m = lab == code[nm]
        if m.any():
            cl, cs = components(m)
            biggest = max(cs, key=cs.get)
            for k, sz in cs.items():
                if k != biggest and sz < 0.15 * cs[biggest]:
                    lab[cl == k] = code["torso"]

    # scraps of the body cut off by the near arm (a trinket in the hand, the outline of a
    # sleeve ahead of the coat) belong to the arm: left on the torso they stretch its row hull
    # past the arm, and the hole under the arm is then filled with their colour in streaks
    tm = lab == code["torso"]
    if tm.any():
        cl, cs = components(tm)
        biggest = max(cs, key=cs.get)
        arm_near = {n: dilate(lab == code[n], 2) for n in NEAR_ARM}
        for k, sz in cs.items():
            if k == biggest or sz > (0.06 * BH) ** 2:
                continue
            m = cl == k
            touch = {n: int((m & arm_near[n]).sum()) for n in NEAR_ARM}
            n_ = max(touch, key=touch.get)
            if touch[n_]:
                lab[m] = code[n_]

    # trousers: what is left below the hips and does not hang from the torso is not a flap of
    # cloth but a scrap of a leg's outline outside its capsule: it goes to the nearest leg
    # (as a "robe" it stayed behind while the leg walked away: a loose black line in the frames)
    if not robe_mode and (lab == code["robe"]).any():
        cl, cs = components(lab == code["robe"])
        hang = dilate(lab == code["torso"], 2)
        for k in cs:
            m = cl == k
            if not (m & hang).any():
                lab[m] = np.array([code[n] for n in lnames])[lbest[m]]

    # scraps cut off the body by the erased far hand (a sliver of its outline behind the
    # back) go with it
    if far_hand.any():
        rim = dilate(lab == code["far_erased"], 2)
        for nm in ("torso", "cape", "robe"):
            m = lab == code[nm]
            if not m.any():
                continue
            cl, cs = components(m)
            biggest = max(cs, key=cs.get)
            for k, sz in cs.items():
                if k != biggest and sz < (0.04 * BH) ** 2 and (rim & (cl == k)).any():
                    lab[cl == k] = code["far_erased"]

    def part_img(name):
        m = lab == code[name]
        out = np.zeros_like(img)
        out[m] = img[m]
        return out

    imgs = {n: part_img(n) for n in ["torso", "cape", "robe", *NEAR_ARM, *NEAR_LEG]}
    arm_pix = np.isin(lab, [code[n] for n in NEAR_ARM])
    far_pix = lab == code["far_erased"]
    leg_pix = np.isin(lab, [code[n] for n in NEAR_LEG])
    # holes: torso / cape / robe under the arm and the erased limbs
    for nm, extra in (("torso", np.zeros_like(A)), ("cape", np.zeros_like(A)), ("robe", leg_pix)):
        own = lab == code[nm]
        if not own.any():
            continue
        hull = _row_hull(own)
        holes = (arm_pix | far_pix | extra) & hull
        if nm == "robe" and not robe_mode:
            holes &= ~leg_pix     # trousers: the robe part is only flaps, legs stay legs
        if nm == "torso":
            holes &= ~below | (P[..., 1] < hip_y + 0.04 * BH)
        if holes.any():
            imgs[nm][holes] = 0
            imgs[nm] = fill(_sweep_front(imgs[nm], own, holes), own, holes)
    # legs: fill slits and, under a robe, extend the leg up to the hip with its own colours
    for n in NEAR_LEG:
        own = lab == code[n]
        if not own.any():
            continue
        core = leg_n[n] <= 0.8
        if n == "near_thigh":
            core &= P[..., 1] > hip_y + 0.5 * R["thigh"]
        holes = core & ~own & (~A | far_pix | arm_pix | (lab == code["robe"]) | (lab == code["torso"]))
        if not robe_mode:
            holes &= ~A | far_pix | arm_pix
        if n == "near_foot":
            holes &= A            # never invent pixels around a foot (they hang below the sole)
        holes &= P[..., 1] < rig.ground_y
        if holes.any():
            imgs[n] = fill(imgs[n], own | (imgs[n][..., 3] > 0), holes)
    if robe_mode and not (lab == code["near_thigh"]).any():
        # nothing of the thigh is visible: grow the shin's top up the thigh capsule
        src = imgs["near_shin"]
        own = src[..., 3] > 0
        holes = (leg_n["near_thigh"] <= 0.8) & (P[..., 1] > hip_y + 0.5 * R["thigh"])
        if own.any() and holes.any():
            grown = fill(src, own, holes | own)
            imgs["near_thigh"][holes] = grown[holes]
    # re-seat the foot: its heel's rear end onto the shin's back edge (whole-pixel shift)
    seat = (data.get("foot_fit") or {}).get("seat") or [0, 0]
    if any(seat):
        imgs["near_foot"] = reseat(imgs["near_foot"], seat)
    # overlap caps: the part behind at a joint takes the front part's pixels in a disc
    def disc(pt, r):
        return np.hypot(P[..., 0] - pt[0], P[..., 1] - pt[1]) <= r

    caps = [("torso", "near_upper", "shoulder", R["upper"]),
            ("torso", "near_thigh", "hip", R["thigh"]),
            ("near_upper", "near_fore", "elbow", R["fore"] * 0.9),
            ("near_thigh", "near_shin", "knee", R["shin"] * 0.9),
            ("near_shin", "near_foot", "ankle", R["shin"] * 0.8)]
    for behind, front, jn, r in caps:
        d = disc(j[jn], r)
        src = imgs[front]
        m = d & (src[..., 3] > 0) & (imgs[behind][..., 3] == 0)
        imgs[behind][m] = src[m]

    parts = {"torso": Part("torso", imgs["torso"], "pelvis", ("pelvis", "neck"))}
    bones = {"near_upper": ("shoulder", "elbow"), "near_fore": ("elbow", "wrist"),
             "near_thigh": ("hip", "knee"), "near_shin": ("knee", "ankle"),
             "near_foot": ("heel", "toe")}
    pivots = {"near_upper": "shoulder", "near_fore": "elbow", "near_thigh": "hip",
              "near_shin": "knee", "near_foot": "ankle"}
    for n in [*NEAR_ARM, *NEAR_LEG]:
        parts[n] = Part(n, imgs[n], pivots[n], bones[n])
    # held gear: how far the forearm part reaches past the hand (staff, sword, crossbow)
    fm = imgs["near_fore"][..., 3] > 0
    gear_reach = 0.0
    if fm.any():
        gy, gx = np.where(fm)
        gear_reach = float(np.hypot(gx + 0.5 - j["wrist"][0], gy + 0.5 - j["wrist"][1]).max()) / BH
    arm_only = {"near_upper": arm_n["near_upper"] <= 1.25,
                "near_fore": arm_n["near_fore"] <= 1.25}
    # ... and nothing past the hand's tip: the stub of a shaft sticking out of the fist would
    # give the far hand a small weapon of its own
    t_hand = seg_dist(P, j["wrist"], j["hand_tip"])[1]
    arm_only["near_fore"] &= t_hand <= 1.0
    # held gear: area of the forearm part outside the arm itself (a shield is wide, not long)
    gear_area = float((fm & ~arm_only["near_fore"]).sum()) / (BH * BH)
    # the far arm.  Hidden in the still: a shaded copy of the near arm.  Visible in the still
    # (fit found its hand behind the back): its own pixels are the far hand and forearm, never
    # a copy as well; only the stretch the body hides is completed with the near sleeve.
    far_real = far_hand & (lab == code["far_erased"]) if data.get("far_arm") == "visible" else None
    if far_real is not None and far_real.sum() < 6:
        far_real = None
    for fn, nn in FAR_OF.items():
        src = imgs[nn].copy()
        if nn in arm_only:        # the far arm is the arm only: never a second weapon
            src[~arm_only[nn]] = 0
        m = src[..., 3] > 0
        out = np.zeros_like(src)
        if m.any():
            cols, inv = np.unique(src[m][:, :3], axis=0, return_inverse=True)
            out[m, :3] = darken(cols, pal)[inv.ravel()]
            out[m, 3] = 255
        if fn == "far_fore" and far_real is not None:
            out = _real_far_fore(out, img, far_real, rig, R)
        parts[fn] = Part(fn, out, pivots[nn], bones[nn])
    cloth = {}
    for nm in ("cape", "robe"):
        m = imgs[nm][..., 3] > 0
        if m.sum() < (0.03 * BH) ** 2:
            if m.any():   # too small to swing: back into the torso
                parts["torso"].img[m] = imgs[nm][m]
            continue
        p = Part(nm, imgs[nm], "pelvis", ("pelvis", "neck"))
        p.kind = nm
        ys, xs = np.where(m)
        if nm == "cape":
            top = ys.min()
            row = xs[ys <= top + 0.02 * BH]
            p.anchor = np.array([float(row.max()) + 0.5, float(top) + 0.5])
        else:
            p.anchor = np.array([float(j["hip"][0]), hip_y])
        p.extent = (int(ys.min()), int(ys.max()) + 1)
        parts[nm] = p
        cloth[nm] = p
    # scraps left in the torso below the hips that do not touch it (slivers of the erased far
    # leg's outline, a too-small "robe" merged back) would hang in the air behind the legs
    # while the walk moves on (rule R24): they are dropped, the far leg is redrawn anyway
    tm = parts["torso"].img[..., 3] > 0
    if tm.any():
        cl, cs = components(tm)
        biggest = max(cs, key=cs.get)
        for k in cs:
            if k != biggest:
                ys_ = np.flatnonzero((cl == k).any(1))
                if ys_.min() > hip_y:
                    parts["torso"].img[cl == k] = 0
    info = {"labels": lab, "codes": code, "palette": pal, "radius": R, "image": img,
            "far_arm": "own pixels" if far_real is not None else "copy of the near arm",
            "cloth": list(cloth), "robe_mode": robe_mode, "gear_reach": gear_reach,
            "gear_area": gear_area,
            "gear_cut": gear_cut(still, parts["near_fore"].mask, parts["torso"].mask,
                                 j["elbow"], R["fore"])}
    return parts, lab, info


def _real_far_fore(copy, img, far_real, rig, R):
    """The far forearm part when the still shows the far hand.  The far arm's own geometry in
    the still: shoulder = near shoulder + far offset, hand tip = the blob's furthest pixel,
    elbow by two-bone IK with the rig's bone lengths.  Its pixels are turned rigidly (nearest
    neighbour) into the near forearm's frame, where every part of this rig lives, with the
    blob's tip on the rig's hand tip.  From where the real pixels start (along the forearm)
    to the tip only they are drawn; the shaded copy of the near sleeve is kept only above
    that, where the body hid the far arm.  So the far arm never has two hands."""
    from .rig import ik2
    j = rig.j
    L = rig.lengths
    H, W = far_real.shape
    S = j["shoulder"] + rig.far_shoulder_offset
    ys, xs = np.where(far_real)
    P = np.stack([xs + 0.5, ys + 0.5], 1)
    D = np.hypot(*(P - S).T)
    T = P[np.argmax(D)]
    reach = L["upper"] + L["fore"]
    d = min(max(float(D.max()) - L["hand"], 0.4 * reach), 0.98 * reach)
    Wf = S + (T - S) / max(float(D.max()), 1e-9) * d
    Ef, Wf = ik2(S, Wf, L["upper"], L["fore"], forward=-1.0)
    uf = (Wf - Ef) / max(float(np.hypot(*(Wf - Ef))), 1e-9)
    nf = np.array([-uf[1], uf[0]])
    un = (j["wrist"] - j["elbow"]) / max(float(np.hypot(*(j["wrist"] - j["elbow"]))), 1e-9)
    nn = np.array([-un[1], un[0]])
    # near-frame pixel -> (t along the forearm from the elbow, c across) -> far-frame pixel,
    # anchored so the blob's tip (its t in the far frame) lands at t_tip = fore + hand
    t_tip_far = float((T - Ef) @ uf)
    shift_t = t_tip_far - (L["fore"] + L["hand"])
    yy, xx = np.mgrid[0:H, 0:W]
    Q = np.stack([xx + 0.5, yy + 0.5], -1) - j["elbow"]
    t = Q @ un
    c = Q @ nn
    src = Ef + (t + shift_t)[..., None] * uf + c[..., None] * nf
    ix = np.floor(src[..., 0]).astype(int)
    iy = np.floor(src[..., 1]).astype(int)
    ok = (ix >= 0) & (iy >= 0) & (ix < W) & (iy < H)
    real = np.zeros((H, W), bool)
    real[ok] = far_real[iy[ok], ix[ok]]
    if not real.any():
        return copy
    t0 = float(t[real].min())
    out = copy.copy()
    out[t >= t0 - 0.5] = 0
    out[real] = img[np.clip(iy, 0, H - 1), np.clip(ix, 0, W - 1)][real]
    return out


GEAR_CUT_MAX = 1.7     # lit (non-outline) px on the forearm/torso seam, x forearm radius


def gear_cut(still, fore, torso, elbow, r_fore):
    """How much the forearm/torso seam runs through drawn colour instead of along an outline.
    A clean arm cut follows the arm's dark outline except at the elbow; a seam through lit
    pixels means held gear (a strapped shield) was sliced between the arm and the torso, and
    the two halves would come apart when the arm swings.  Returns lit seam px / forearm radius."""
    fo, to = fore & ~torso, torso & ~fore
    H, W = fo.shape
    yy, xx = np.mgrid[0:H, 0:W]
    near_el = np.hypot(xx + 0.5 - elbow[0], yy + 0.5 - elbow[1]) < 1.5 * r_fore
    nb = np.zeros_like(fo)
    nb[1:] |= to[:-1]
    nb[:-1] |= to[1:]
    nb[:, 1:] |= to[:, :-1]
    nb[:, :-1] |= to[:, 1:]
    luma = still[..., :3].astype(float) @ np.array([0.299, 0.587, 0.114])
    lit = fo & nb & ~near_el & (luma > 55)
    return float(lit.sum()) / max(r_fore, 1.0)


def gate_cut(info):
    """Input gate on the cut (RULES.md G7): held gear must not be sliced between the arm and
    the body.  Returns [(text, joints)] like fit.gate_still."""
    if info.get("gear_cut", 0.0) > GEAR_CUT_MAX:
        return [(f"G7: gear_cut: the forearm's seam with the body runs {info['gear_cut']:.1f} radii "
                 f"through drawn colour (> {GEAR_CUT_MAX}): held gear (a shield?) would be cut in two",
                 ["elbow", "wrist"])]
    return []

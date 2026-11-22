"""Cut a still into rigid parts on its skeleton.

Pipeline (cut_still):
  1. hard alpha (>= 128), erase polygons (ground plates, stray marks);
  2. label every opaque pixel: gear polygons > near arm capsules > torso-keep polygons >
     near leg capsules > torso/head capsules > far limb capsules > nearest bone (distance
     divided by the bone's radius).  A limb capsule only claims pixels past its proximal joint
     (the joint-aware boundary), so a thigh never eats the belt above the hip;
  3. fill holes: where a moving part (near arm, gear, the erased far limbs) covered the torso or
     a leg bone, that part's pixels are re-grown from its own neighbouring pixels;
  4. overlap caps: the part drawn BEHIND at a joint also gets the front part's pixels inside a
     disc at that joint, so when the front part turns, the disc shows instead of a gap;
  5. far arm / far leg = copies of the near ones, value x0.7, snapped back to the still's palette.
"""
import hashlib
import math

import numpy as np
from PIL import Image, ImageDraw

from .rig import Rig

ALPHA_T = 128
FAR_VALUE = 0.70
CORE = 0.75      # x bone radius: transparent pixels this deep inside a limb are filled
HEM_REACH = 1.8   # x bone radius: how far below the hips a leg reclaims torso pixels

NEAR_ARM = ("near_upper", "near_fore")
NEAR_LEG = ("near_thigh", "near_shin", "near_foot")
FAR_OF = {"far_upper": "near_upper", "far_fore": "near_fore", "far_thigh": "near_thigh",
          "far_shin": "near_shin", "far_foot": "near_foot"}

# Default capsule radii as a fraction of body height (head top to ground). Measured on the
# six samples: a sleeve is ~9-10 % of body height wide, a trouser leg ~11-12 %.
DEFAULT_RADIUS = {"upper": 0.045, "fore": 0.042, "thigh": 0.062, "shin": 0.05, "foot": 0.035,
                  "torso": 0.17, "head": 0.13}

# --------------------------------------------------------------------------- strips


def load_rgba(path):
    return np.array(Image.open(path).convert("RGBA"))


def split_strip(img, n=4):
    """Split a horizontal strip into frames at empty columns; a segment that holds two
    touching frames is split at its thinnest column near the middle.  Returns list of
    (x0, x1)."""
    a = img[:, :, 3] >= ALPHA_T
    col = a.sum(0)
    segs, s = [], None
    for x in range(len(col) + 1):
        on = x < len(col) and col[x] > 0
        if on and s is None:
            s = x
        if not on and s is not None:
            segs.append([s, x])
            s = None
    segs = [g for g in segs if g[1] - g[0] >= 4]  # dust
    while len(segs) < n and segs:
        i = max(range(len(segs)), key=lambda k: segs[k][1] - segs[k][0])
        s0, s1 = segs[i]
        w = s1 - s0
        lo, hi = s0 + w // 3, s1 - w // 3
        cut = lo + int(np.argmin(col[lo:hi]))
        segs[i:i + 1] = [[s0, cut], [cut, s1]]
    return [tuple(g) for g in segs[:n]]


def frame_of(img, seg):
    x0, x1 = seg
    f = img[:, x0:x1].copy()
    f[f[:, :, 3] < ALPHA_T] = 0
    f[f[:, :, 3] >= ALPHA_T, 3] = 255
    return _drop_edge_dust(f)


def _drop_edge_dust(f, max_px=40):
    """Remove small pieces touching the left/right crop edge (bits of the next frame)."""
    a = f[:, :, 3] > 0
    lab = _components(a)
    H, W = a.shape
    for c in np.unique(lab):
        if c == 0:
            continue
        m = lab == c
        if m.sum() <= max_px and (m[:, 0].any() or m[:, W - 1].any()):
            f[m] = 0
    return f


def _components(mask):
    """8-connected component labels (numpy only, union by iterative min-propagation)."""
    H, W = mask.shape
    lab = np.where(mask, np.arange(1, H * W + 1).reshape(H, W), 0)
    big = H * W + 10
    while True:
        cur = np.where(mask, lab, big)
        p = np.pad(cur, 1, constant_values=big)
        m = cur.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                m = np.minimum(m, p[1 + dy:1 + dy + H, 1 + dx:1 + dx + W])
        m = np.where(mask, m, 0)
        if np.array_equal(m, lab):
            return lab
        lab = m


def stride_width(frame):
    a = frame[:, :, 3] > 0
    rows = np.where(a.any(1))[0]
    y0, y1 = rows.min(), rows.max()
    band = a[y1 - int(0.15 * (y1 - y0)):y1 + 1]
    cols = np.where(band.any(0))[0]
    return int(cols.max() - cols.min() + 1)


def pick_still(frames):
    """The widest stride frame (feet furthest apart); ties go to the earlier frame."""
    w = [stride_width(f) for f in frames]
    return int(np.argmax(w))


def load_still(path, rig_data=None):
    img = load_rgba(path)
    segs = split_strip(img)
    frames = [frame_of(img, s) for s in segs]
    idx = rig_data.get("frame") if rig_data else None
    if idx is None:
        idx = pick_still(frames)
    return frames[idx], frames, idx


# --------------------------------------------------------------------------- geometry


def poly_mask(shape, poly):
    im = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(im).polygon([tuple(map(float, p)) for p in poly], fill=1, outline=1)
    return np.array(im, bool)


def seg_dist(P, a, b):
    """distance from pixel centres P (H,W,2) to segment a-b, and the projection t."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ab = b - a
    L2 = max(float(ab @ ab), 1e-9)
    t = ((P - a) @ ab) / L2
    tc = np.clip(t, 0, 1)
    q = a + tc[..., None] * ab
    return np.hypot(*(P - q).transpose(2, 0, 1)), t


def radii(rig):
    H = rig.body_height
    r = {k: v * H for k, v in DEFAULT_RADIUS.items()}
    for k, v in rig.data.get("radius", {}).items():
        r[k] = float(v)
    return r


# --------------------------------------------------------------------------- cutting


class Part:
    def __init__(self, name, img, pivot, bone, attach=None):
        self.name = name
        self.img = img            # H,W,4 uint8 in still coordinates
        self.pivot = pivot        # joint name in the rig the part turns about
        self.bone = bone          # (joint_a, joint_b): the part turns with this bone
        self.attach = attach

    @property
    def mask(self):
        return self.img[:, :, 3] > 0

    def digest(self):
        return hashlib.sha1(self.img.tobytes()).hexdigest()[:16]


def palette_of(img):
    a = img[:, :, 3] > 0
    cols = np.unique(img[a][:, :3], axis=0)
    return cols


def snap_to_palette(rgb, pal):
    """nearest palette colour (RGB, weighted 3:4:2 for luma) for each row of rgb."""
    rgb = rgb.astype(np.int32)
    p = pal.astype(np.int32)
    w = np.array([3, 4, 2])
    out = np.empty_like(rgb)
    for i in range(0, len(rgb), 4096):
        c = rgb[i:i + 4096]
        d = (((c[:, None, :] - p[None, :, :]) ** 2) * w).sum(-1)
        out[i:i + 4096] = p[np.argmin(d, 1)]
    return out.astype(np.uint8)


def _fill(img, own, holes, max_iter=200):
    """Grow `own` pixels of img into `holes`, one ring at a time (onion peel).  Each new
    pixel copies the most common colour among its filled 8-neighbours (edge neighbours count
    double), so fills are made only of colours already in the part."""
    img = img.copy()
    filled = own.copy()
    todo = holes & ~own
    H, W = own.shape
    nbrs = [(-1, 0, 2), (1, 0, 2), (0, -1, 2), (0, 1, 2), (-1, -1, 1), (-1, 1, 1), (1, -1, 1), (1, 1, 1)]
    for _ in range(max_iter):
        if not todo.any():
            break
        fp = np.pad(filled, 1)
        ip = np.pad(img, ((1, 1), (1, 1), (0, 0)))
        new = []
        for y, x in zip(*np.where(todo)):
            votes = {}
            for dy, dx, w in nbrs:
                if fp[y + 1 + dy, x + 1 + dx]:
                    c = tuple(ip[y + 1 + dy, x + 1 + dx])
                    votes[c] = votes.get(c, 0) + w
            if votes:
                new.append((y, x, max(votes.items(), key=lambda kv: kv[1])[0]))
        if not new:
            break
        for y, x, c in new:
            img[y, x] = c
            filled[y, x] = True
            todo[y, x] = False
    return img


def _sweep(img, own, holes):
    """Fill torso holes row by row from the FRONT (facing side): the body under an arm is
    the same cloth as the body in front of it, so belts and seams continue around."""
    img = img.copy()
    H, W = own.shape
    own = own.copy()
    for y in range(H):
        xs = np.where(holes[y] & ~own[y])[0]
        if not len(xs):
            continue
        for x in sorted(xs, reverse=True):
            xr = x + 1
            if xr < W and own[y, xr]:
                img[y, x] = img[y, xr]
                own[y, x] = True
    return img


def _row_hull(mask):
    """Pixels between the leftmost and rightmost pixel of mask in each row."""
    H, W = mask.shape
    rows = np.zeros_like(mask)
    for y in range(H):
        xs = np.where(mask[y])[0]
        if len(xs):
            rows[y, xs.min():xs.max() + 1] = True
    return rows


def _ortho_hull(mask):
    """Pixels inside both the row span and the column span of mask."""
    H, W = mask.shape
    rows = np.zeros_like(mask)
    cols = np.zeros_like(mask)
    for y in range(H):
        xs = np.where(mask[y])[0]
        if len(xs):
            rows[y, xs.min():xs.max() + 1] = True
    for x in range(W):
        ys = np.where(mask[:, x])[0]
        if len(ys):
            cols[ys.min():ys.max() + 1, x] = True
    return rows & cols


def cut_still(still, rig):
    """Returns (parts dict name->Part, labels array, info dict)."""
    data = rig.data
    img = still.copy()
    img[img[:, :, 3] < ALPHA_T] = 0
    img[img[:, :, 3] >= ALPHA_T, 3] = 255
    H, W = img.shape[:2]
    for poly in data.get("erase", []):
        img[poly_mask((H, W), poly)] = 0
    A = img[:, :, 3] > 0
    pal = palette_of(img)

    yy, xx = np.mgrid[0:H, 0:W]
    P = np.stack([xx + 0.5, yy + 0.5], -1).astype(float)
    j = rig.j
    far = {k: np.array(v, float) for k, v in data.get("far", {}).items()}
    R = radii(rig)

    def cap(a, b, r, gate=None):
        d, t = seg_dist(P, j[a] if isinstance(a, str) else a, j[b] if isinstance(b, str) else b)
        n = d / r
        if gate is not None:
            n = np.where(t >= gate, n, np.inf)
        return n

    def foot_norm(jj):
        r = R["foot"]
        ds = [seg_dist(P, jj["heel"], jj["toe"])[0], seg_dist(P, jj["ankle"], jj["heel"])[0],
              seg_dist(P, jj["ankle"], jj["toe"])[0]]
        return np.minimum.reduce(ds) / r

    near_n = {
        "near_upper": cap("shoulder", "elbow", R["upper"], gate=-0.1),
        "near_fore": np.minimum(cap("elbow", "wrist", R["fore"], gate=0.0),
                                cap("wrist", "hand_tip", R["fore"] * 1.15)),
        "near_thigh": cap("hip", "knee", R["thigh"], gate=0.0),
        "near_shin": cap("knee", "ankle", R["shin"], gate=0.0),
        "near_foot": foot_norm(j),
    }
    torso_n = np.minimum(cap("pelvis", "neck", R["torso"]), cap("neck", "head_top", R["head"]))
    far_n = []
    if {"shoulder", "elbow", "wrist"} <= far.keys():
        far_n.append(np.minimum(cap(far["shoulder"], far["elbow"], R["upper"]),
                                cap(far["elbow"], far.get("hand_tip", far["wrist"]), R["fore"])))
    if {"hip", "knee", "ankle"} <= far.keys():
        fj = dict(far)
        fj.setdefault("heel", far["ankle"])
        fj.setdefault("toe", far["ankle"])
        far_n.append(np.minimum.reduce([cap(far["hip"], far["knee"], R["thigh"], gate=0.0),
                                        cap(far["knee"], far["ankle"], R["shin"]),
                                        foot_norm(fj)]))
    far_any = np.minimum.reduce(far_n) if far_n else np.full((H, W), np.inf)

    names = ["bg", "torso", "back", *NEAR_ARM, *NEAR_LEG, "far_erased"]
    gear_defs = data.get("gear", [])
    for g in gear_defs:
        names.append("gear:" + g["name"])
    code = {n: i for i, n in enumerate(names)}
    lab = np.zeros((H, W), np.int16)
    free = A.copy()

    def take(m, name):
        m = m & free
        lab[m] = code[name]
        free[m] = False

    for g in gear_defs:
        take(poly_mask((H, W), g["poly"]), "gear:" + g["name"])
    if "back" in data:
        take(poly_mask((H, W), data["back"]["poly"]), "back")
    for poly in data.get("far_poly", []):
        take(poly_mask((H, W), poly), "far_erased")
    arm_stack = np.stack([near_n[n] for n in NEAR_ARM])
    arm_best = np.argmin(arm_stack, 0)
    in_arm = arm_stack.min(0) <= 1.0
    for poly in data.get("arm_poly", []):
        pm = poly_mask((H, W), poly)
        in_arm |= pm
    for i, n in enumerate(NEAR_ARM):
        take(in_arm & (arm_best == i), n)
    for poly in data.get("torso_keep", []):
        take(poly_mask((H, W), poly), "torso")
    leg_stack = np.stack([near_n[n] for n in NEAR_LEG])
    leg_best = np.argmin(leg_stack, 0)
    in_leg = leg_stack.min(0) <= 1.0
    for i, n in enumerate(NEAR_LEG):
        take(in_leg & (leg_best == i), n)
    take(torso_n <= 1.0, "torso")
    take(far_any <= 1.0, "far_erased")
    # leftovers: nearest bone by normalized distance
    allst = np.stack([torso_n, *[near_n[n] for n in NEAR_ARM], *[near_n[n] for n in NEAR_LEG],
                      far_any])
    order = ["torso", *NEAR_ARM, *NEAR_LEG, "far_erased"]
    best = np.argmin(allst, 0)
    for i, n in enumerate(order):
        take(best == i, n)
    # Joint-aware hem: torso pixels below the hips that hug a leg belong to that leg (or to
    # the erased far leg), so no dark scraps of thigh hang between the legs as a third leg.
    # Capes and robes that must stay rigid are protected by "torso_keep" polygons.
    keep = np.zeros((H, W), bool)
    for poly in data.get("torso_keep", []):
        keep |= poly_mask((H, W), poly)
    hip_y = min(j["hip"][1], far.get("hip", j["hip"])[1])
    tor = (lab == code["torso"]) & (P[..., 1] > hip_y) & ~keep
    legs = {n: near_n[n] for n in NEAR_LEG}
    if far_n:
        legs["far_erased"] = far_n[-1] if {"hip", "knee", "ankle"} <= far.keys() else far_any
    names_l = list(legs)
    st = np.stack([legs[n] for n in names_l])
    nb = np.argmin(st, 0)
    close = st.min(0) <= HEM_REACH
    for i, n in enumerate(names_l):
        m = tor & close & (nb == i)
        lab[m] = code[n]

    # ------------------------------------------------------------- per part images
    def part_img(name):
        m = lab == code[name]
        out = np.zeros_like(img)
        out[m] = img[m]
        return out

    imgs = {n: part_img(n) for n in ["torso", "back", *NEAR_ARM, *NEAR_LEG]}
    gear_imgs = {g["name"]: part_img("gear:" + g["name"]) for g in gear_defs}

    hand_gear = np.zeros((H, W), bool)
    for g in gear_defs:
        if g.get("attach", "hand") == "hand":
            hand_gear |= lab == code["gear:" + g["name"]]
    arm_pix = np.isin(lab, [code[n] for n in NEAR_ARM])
    far_pix = lab == code["far_erased"]

    # holes in the torso
    tm = lab == code["torso"]
    hull = _row_hull(tm)
    for poly in data.get("body_poly", []):   # hidden body under an arm, drawn by hand
        hull |= poly_mask((H, W), poly)
    holes = arm_pix | far_pix | hand_gear
    # the moving part's own outline often stays behind as a 1-px line: re-grow it too
    hp = np.pad(holes, 1)
    holes = holes | (tm & (hp[:-2, 1:-1] | hp[2:, 1:-1] | hp[1:-1, :-2] | hp[1:-1, 2:]))
    holes &= hull
    tm = tm & ~holes
    imgs["torso"][holes] = 0
    imgs["torso"] = _fill(_sweep(imgs["torso"], tm, holes), tm, holes)
    # holes in the near leg bones (where the erased far arm / held gear hung over them)
    for n in NEAR_LEG:
        own = lab == code[n]
        holes = (near_n[n] <= 1.0) & (far_pix | hand_gear | arm_pix) & ~own
        # see-through slits drawn inside a limb (gaps between boot and trouser) are closed,
        # otherwise a turned limb shows a hole that reads as two legs
        holes |= (near_n[n] <= CORE) & ~A & (np.argmin(leg_stack, 0) == NEAR_LEG.index(n))
        if n == "near_thigh":
            holes &= ~hull  # the torso already covers the hip
        if holes.any():
            imgs[n] = _fill(imgs[n], own, holes)
    for n in NEAR_ARM:
        own = lab == code[n]
        holes = (near_n[n] <= 1.0) & hand_gear & ~own
        if holes.any():
            imgs[n] = _fill(imgs[n], own, holes)

    # overlap caps: the part BEHIND at each joint takes the front part's pixels in a disc
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
        m = d & (src[:, :, 3] > 0) & (imgs[behind][:, :, 3] == 0)
        imgs[behind][m] = src[m]

    parts = {}
    parts["torso"] = Part("torso", imgs["torso"], "pelvis", ("pelvis", "neck"))
    if imgs["back"][:, :, 3].any():
        parts["back"] = Part("back", imgs["back"], "pelvis", ("pelvis", "neck"))
    bones = {"near_upper": ("shoulder", "elbow"), "near_fore": ("elbow", "wrist"),
             "near_thigh": ("hip", "knee"), "near_shin": ("knee", "ankle"),
             "near_foot": ("heel", "toe")}
    pivots = {"near_upper": "shoulder", "near_fore": "elbow", "near_thigh": "hip",
              "near_shin": "knee", "near_foot": "ankle"}
    for n in [*NEAR_ARM, *NEAR_LEG]:
        parts[n] = Part(n, imgs[n], pivots[n], bones[n])
    for fn, nn in FAR_OF.items():
        src = imgs[nn]
        m = src[:, :, 3] > 0
        out = np.zeros_like(src)
        if m.any():
            dark = np.clip(src[m][:, :3].astype(float) * FAR_VALUE, 0, 255)
            out[m, :3] = snap_to_palette(dark, pal)
            out[m, 3] = 255
        parts[fn] = Part(fn, out, pivots[nn], bones[nn])
    for g in gear_defs:
        att = g.get("attach", "hand")
        if att == "hand":
            parts["gear:" + g["name"]] = Part("gear:" + g["name"], gear_imgs[g["name"]], "wrist",
                                              ("elbow", "wrist"), attach="hand")
        else:
            parts["gear:" + g["name"]] = Part("gear:" + g["name"], gear_imgs[g["name"]], "pelvis",
                                              ("pelvis", "neck"), attach="spine")
    info = {"labels": lab, "codes": code, "palette": pal, "radius": R, "image": img}
    return parts, lab, info


# --------------------------------------------------------------------------- auto joints


def auto_joints(still):
    """Estimate the rig joints of a right-facing side-view walker from its silhouette and
    standard proportions.  Good enough to start a JSON by hand; see README for accuracy."""
    a = still[:, :, 3] > 0
    H, W = a.shape
    rows = np.where(a.any(1))[0]
    top, bot = int(rows.min()), int(rows.max())
    h = bot + 1 - top

    def runs(y):
        xs = np.where(a[y])[0]
        if not len(xs):
            return []
        out, s = [], xs[0]
        for p, q in zip(xs[:-1], xs[1:]):
            if q != p + 1:
                out.append((s, p))
                s = q
        out.append((s, xs[-1]))
        return out

    # feet: lowest rows; back foot = leftmost run, front foot = rightmost run
    foot_rows = range(bot - max(2, h // 25), bot + 1)
    fr = [r for y in foot_rows for r in runs(y)]
    xs_all = [x for r in fr for x in r]
    fx0, fx1 = min(xs_all), max(xs_all)
    # crotch: scan up from the feet until the leg runs merge into one
    crotch = None
    for y in range(bot - h // 10, top + h // 3, -1):
        rr = [r for r in runs(y) if r[1] - r[0] >= 2]
        if len(rr) == 1:
            crotch = (y, (rr[0][0] + rr[0][1]) / 2)
            break
    if crotch is None:
        crotch = (bot - 0.45 * h, (fx0 + fx1) / 2)
    cy, cx = crotch
    hip = np.array([cx + 0.5, cy - 0.04 * h])
    foot_len = 0.13 * h
    ground = bot + 1
    toe = np.array([fx1 + 1.0, ground])
    heel = toe - [foot_len, 0]
    ankle = heel + [0.3 * foot_len, -0.06 * h]
    knee = (hip + ankle) / 2 + [0.02 * h, 0]
    # back leg (far)
    btoe = np.array([fx0 + foot_len, ground])
    bheel = np.array([fx0 + 0.0, ground - 0.03 * h])
    bankle = bheel + [0.3 * foot_len, -0.06 * h]
    bknee = (hip + bankle) / 2 + [0.02 * h, 0]
    # trunk: head ~ 1/5.5 of height for these chunky sprites
    head_top = np.array([_mid(a, top + 2) , float(top)])
    neck = np.array([_mid(a, int(top + 0.22 * h)), top + 0.22 * h])
    pelvis = np.array([hip[0], hip[1] - 0.02 * h])
    shoulder = neck + [0.0, 0.07 * h]
    # front arm: forward-most pixel between shoulder and hip rows
    band = a[int(shoulder[1]):int(hip[1])]
    xs = np.where(band.any(0))[0]
    fxm = xs.max()
    ys = np.where(band[:, fxm])[0] + int(shoulder[1])
    hand_tip = np.array([fxm + 1.0, ys.mean()])
    upper = 0.19 * h
    v = hand_tip - shoulder
    dist = np.hypot(*v)
    elbow = shoulder + v / dist * min(upper, dist * 0.5) + [0, 0.03 * h]
    wrist = hand_tip - v / dist * 0.05 * h
    J = {"head_top": head_top, "neck": neck, "pelvis": pelvis, "shoulder": shoulder,
         "elbow": elbow, "wrist": wrist, "hand_tip": hand_tip, "hip": hip, "knee": knee,
         "ankle": ankle, "heel": heel, "toe": toe}
    J = {k: [round(float(v[0]), 1), round(float(v[1]), 1)] for k, v in J.items()}
    far = {"hip": J["hip"], "knee": _r(bknee), "ankle": _r(bankle), "heel": _r(bheel), "toe": _r(btoe)}
    return {"ground_y": float(ground), "joints": J, "far": far}


def _r(v):
    return [round(float(v[0]), 1), round(float(v[1]), 1)]


def _mid(a, y):
    xs = np.where(a[int(y)])[0]
    return float((xs.min() + xs.max() + 1) / 2) if len(xs) else a.shape[1] / 2

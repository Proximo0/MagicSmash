"""Walk-sheet helpers: OpenPose skeletons for a side-view walk (T2I-Adapter input) and a quality check."""
import math
import numpy as np
from PIL import Image, ImageDraw

# OpenPose (COCO-18) limb list and colours, as used by controlnet_aux draw_bodypose.
LIMBS = [[2, 3], [2, 6], [3, 4], [4, 5], [6, 7], [7, 8], [2, 9], [9, 10], [10, 11], [2, 12], [12, 13], [13, 14],
         [2, 1], [1, 15], [15, 17], [1, 16], [16, 18]]
COLORS = [[255, 0, 0], [255, 85, 0], [255, 170, 0], [255, 255, 0], [170, 255, 0], [85, 255, 0], [0, 255, 0],
          [0, 255, 85], [0, 255, 170], [0, 255, 255], [0, 170, 255], [0, 85, 255], [0, 0, 255], [85, 0, 255],
          [170, 0, 255], [255, 0, 255], [255, 0, 170], [255, 0, 85]]
# 0 nose 1 neck 2 Rsho 3 Relb 4 Rwri 5 Lsho 6 Lelb 7 Lwri 8 Rhip 9 Rknee 10 Rank 11 Lhip 12 Lknee 13 Lank
# 14 Reye 15 Leye 16 Rear 17 Lear.  Facing right shows the figure's right side, so only the right eye/ear are drawn.

SPLIT = math.radians(35)


def _leg_split(hip, L, fwd):
    """Wide stride: one straight leg forward, one back with a slightly bent knee. Returns (knee, ankle) for fwd/back."""
    fa = (hip[0] + L * math.sin(SPLIT), hip[1] + L * math.cos(SPLIT))
    fk = ((hip[0] + fa[0]) / 2 + 0.01 * L, (hip[1] + fa[1]) / 2)
    ba = (hip[0] - L * math.sin(SPLIT), hip[1] + L * math.cos(SPLIT))
    bk = ((hip[0] + ba[0]) / 2 + 0.06 * L, (hip[1] + ba[1]) / 2 + 0.02 * L)
    return (fk, fa), (bk, ba)


def _leg_pass(hip, L):
    """Passing pose: stance leg straight down, swing leg with knee forward and foot lifted behind it (legs cross)."""
    sa = (hip[0] - 0.02 * L, hip[1] + L * math.cos(SPLIT))
    sk = ((hip[0] + sa[0]) / 2, (hip[1] + sa[1]) / 2)
    wk = (hip[0] + 0.30 * L, hip[1] + 0.42 * L)
    wa = (hip[0] - 0.08 * L, hip[1] + 0.72 * L)
    return (sk, sa), (wk, wa)


def pose(frame, cx, top, fh, leg=0.47):
    """Keypoints for frame 0..3 of a walk to the right. 0: left leg fwd, 1: pass, 2: right leg fwd, 3: pass."""
    L = fh * leg
    ground = top + fh
    hip_y = ground - L * math.cos(SPLIT)
    nose = (cx + fh * 0.07, top + fh * 0.07)
    neck = (cx + fh * 0.01, top + fh * 0.17)
    rs, ls = (cx + fh * 0.01, top + fh * 0.20), (cx - fh * 0.02, top + fh * 0.20)
    rh, lh = (cx, hip_y), (cx - fh * 0.02, hip_y)
    if frame in (0, 2):
        f, b = _leg_split(rh, L, True)
        (lk, la), (rk, ra) = (f, b) if frame == 0 else (b, f)
    else:
        st, sw = _leg_pass(rh, L)
        (rk, ra), (lk, la) = (st, sw) if frame == 1 else (sw, st)
    A = fh * 0.34
    arm = {0: 1, 1: 0, 2: -1, 3: 0}[frame]  # right arm swings opposite the right leg
    ang = math.radians(28) * arm
    re = (rs[0] + A / 2 * math.sin(ang), rs[1] + A / 2 * math.cos(ang))
    rw = (re[0] + A / 2 * math.sin(ang * 1.3), re[1] + A / 2 * math.cos(ang * 1.3))
    le = (ls[0] - A / 2 * math.sin(ang), ls[1] + A / 2 * math.cos(ang))
    lw = (le[0] - A / 2 * math.sin(ang * 1.3), le[1] + A / 2 * math.cos(ang * 1.3))
    reye = (nose[0] - fh * 0.025, nose[1] - fh * 0.02)
    rear = (cx - fh * 0.025, top + fh * 0.06)
    return [nose, neck, rs, re, rw, ls, le, lw, rh, rk, ra, lh, lk, la, reye, None, rear, None]


# Action poses, side view facing right. Normalised coords: x right, y down, unit = figure height, x=0 at the hips,
# y=0 top of head, y=1 feet. Order = OpenPose keypoints 0..17 (None = hidden).
def _P(nose, neck, rs, re, rw, ls, le, lw, rh, rk, ra, lh, lk, la):
    reye = (nose[0] - 0.025, nose[1] - 0.02); rear = (neck[0] - 0.035, nose[1] - 0.01)
    return [nose, neck, rs, re, rw, ls, le, lw, rh, rk, ra, lh, lk, la, reye, None, rear, None]


ACTIONS = {
    "attack_3f": [
        # wind-up: weapon arm drawn back at the hip, other arm raised forward, feet apart
        _P((0.05, 0.07), (0.0, 0.17), (0.0, 0.20), (-0.13, 0.33), (-0.20, 0.46), (-0.02, 0.20), (0.10, 0.26), (0.18, 0.20),
           (0.0, 0.58), (0.10, 0.79), (0.14, 1.0), (-0.02, 0.58), (-0.10, 0.79), (-0.16, 1.0)),
        # strike: lunge, front knee bent, weapon arm fully forward at shoulder height
        _P((0.13, 0.12), (0.08, 0.21), (0.08, 0.24), (0.24, 0.25), (0.40, 0.25), (0.05, 0.24), (-0.05, 0.36), (-0.12, 0.45),
           (0.0, 0.60), (0.20, 0.76), (0.24, 1.0), (-0.02, 0.60), (-0.16, 0.80), (-0.30, 1.0)),
        # follow-through: body leaning far forward, arm extended low across
        _P((0.20, 0.17), (0.13, 0.25), (0.13, 0.28), (0.28, 0.36), (0.42, 0.44), (0.10, 0.28), (0.02, 0.40), (-0.06, 0.48),
           (0.0, 0.62), (0.22, 0.78), (0.26, 1.0), (-0.02, 0.62), (-0.18, 0.80), (-0.32, 1.0)),
    ],
    "recoil_1f": [
        # hit: head thrown back, torso leaning away (to the left), arms flung out
        _P((-0.06, 0.08), (-0.08, 0.19), (-0.08, 0.22), (0.04, 0.12), (0.14, 0.04), (-0.10, 0.22), (-0.22, 0.14), (-0.32, 0.08),
           (0.0, 0.60), (0.06, 0.80), (0.10, 1.0), (-0.02, 0.60), (-0.10, 0.80), (-0.12, 1.0)),
    ],
    "die_3f": [
        # stagger back, hand clutching the chest
        _P((-0.04, 0.08), (-0.05, 0.18), (-0.05, 0.21), (0.03, 0.30), (0.02, 0.24), (-0.07, 0.21), (-0.18, 0.30), (-0.26, 0.40),
           (0.0, 0.60), (0.08, 0.80), (0.12, 1.0), (-0.02, 0.60), (-0.12, 0.80), (-0.10, 1.0)),
        # fall to the knees, torso slumped forward, arms hanging
        _P((0.10, 0.40), (0.04, 0.48), (0.04, 0.51), (0.08, 0.66), (0.12, 0.80), (0.01, 0.51), (0.04, 0.66), (0.07, 0.80),
           (0.0, 0.78), (0.14, 0.98), (-0.10, 1.0), (-0.02, 0.78), (0.12, 0.98), (-0.12, 1.0)),
        # lying flat on the back, head to the left, feet to the right
        _P((-0.44, 0.93), (-0.32, 0.95), (-0.30, 0.94), (-0.18, 0.92), (-0.06, 0.95), (-0.30, 0.97), (-0.18, 0.99), (-0.06, 1.0),
           (0.06, 0.95), (0.24, 0.95), (0.42, 0.95), (0.06, 0.97), (0.24, 0.98), (0.42, 0.99)),
    ],
}


def action_sheet(w, h, pose_name, fill=0.62):
    """OpenPose sheet for an action row: one frame per pose in ACTIONS[pose_name], side by side."""
    frames = ACTIONS[pose_name]; n = len(frames)
    img = Image.new("RGB", (w, h), (0, 0, 0)); d = ImageDraw.Draw(img)
    slot = w / n; fh = h * fill; top = h * 0.82 - fh; sw = max(4.0, fh * 0.014)
    for fr, rel in enumerate(frames):
        cx = slot * fr + slot / 2
        pts = [None if p is None else (cx + p[0] * fh, top + p[1] * fh) for p in rel]
        _draw(d, pts, sw)
    return img


def _draw(d, pts, sw):
    for i, (a, b) in enumerate(LIMBS):
        p, q = pts[a - 1], pts[b - 1]
        if p is None or q is None: continue
        mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        ln = math.hypot(q[0] - p[0], q[1] - p[1]) / 2; an = math.atan2(q[1] - p[1], q[0] - p[0])
        poly = [(mx + ln * math.cos(t) * math.cos(an) - sw * math.sin(t) * math.sin(an),
                 my + ln * math.cos(t) * math.sin(an) + sw * math.sin(t) * math.cos(an))
                for t in np.linspace(0, 2 * math.pi, 36)]
        d.polygon(poly, fill=tuple(int(c * 0.6) for c in COLORS[i]))
    for i, p in enumerate(pts):
        if p is None: continue
        d.ellipse([p[0] - sw, p[1] - sw, p[0] + sw, p[1] + sw], fill=tuple(COLORS[i]))


def check_frames(img, n):
    """Action rows: every frame slot holds a figure. Score = smallest figure area share."""
    a = np.asarray(img.convert("RGB")).astype(np.int16)
    fg = ~((a[..., 0] > 240) & (a[..., 1] < 20) & (a[..., 2] > 240))
    w = fg.shape[1]; shares = []
    for i in range(n):
        s = fg[:, int(w * i / n):int(w * (i + 1) / n)]
        shares.append(s.mean())
    ok = min(shares) > 0.01
    return ok, float(min(shares)), "frames " + "/".join(f"{x:.2f}" for x in shares)


def skeleton_sheet(w, h, n=4, fill=0.58, leg=0.47):
    img = Image.new("RGB", (w, h), (0, 0, 0)); d = ImageDraw.Draw(img)
    slot = w / n; fh = h * fill; top = h * 0.79 - fh
    sw = max(4.0, fh * 0.014)
    for fr in range(n):
        pts = pose(fr, slot * fr + slot / 2, top, fh, leg)
        for i, (a, b) in enumerate(LIMBS):
            p, q = pts[a - 1], pts[b - 1]
            if p is None or q is None: continue
            mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
            ln = math.hypot(q[0] - p[0], q[1] - p[1]) / 2; an = math.atan2(q[1] - p[1], q[0] - p[0])
            poly = [(mx + ln * math.cos(t) * math.cos(an) - sw * math.sin(t) * math.sin(an),
                     my + ln * math.cos(t) * math.sin(an) + sw * math.sin(t) * math.cos(an))
                    for t in np.linspace(0, 2 * math.pi, 36)]
            d.polygon(poly, fill=tuple(int(c * 0.6) for c in COLORS[i]))
        for i, p in enumerate(pts):
            if p is None: continue
            d.ellipse([p[0] - sw, p[1] - sw, p[0] + sw, p[1] + sw], fill=tuple(COLORS[i]))
    return img


def _crop(mask):
    ys, xs = np.nonzero(mask)
    if len(ys) < 200: return None
    return mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def _resize(m, size=(48, 64)):
    return np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize(size, Image.NEAREST)) > 127


def _iou(a, b):
    u = (a | b).sum()
    return (a & b).sum() / u if u else 1.0


def check_single(img, min_rel=0.12):
    """One-off sprite: exactly one big figure (other blobs < min_rel of the biggest), not touching the picture edge."""
    from scipy import ndimage
    a = np.asarray(img.convert("RGB")).astype(np.int16)
    fg = ~((a[..., 0] > 240) & (a[..., 1] < 20) & (a[..., 2] > 240))
    lab, n = ndimage.label(ndimage.binary_closing(fg, iterations=3))
    if n == 0: return False, -1.0, "empty"
    sizes = np.sort(ndimage.sum(fg, lab, range(1, n + 1)))[::-1]
    extra = int((sizes[1:] > min_rel * sizes[0]).sum())
    edge = bool(fg[0].any() or fg[-1].any() or fg[:, 0].any() or fg[:, -1].any())
    cover = sizes[0] / fg.size
    ok = extra == 0 and not edge and cover > 0.06
    notes = f"figures {1 + extra} cover {cover:.2f} edge {edge}"
    return ok, cover - extra * 0.2 - (0.1 if edge else 0), notes


def check_sheet(img, n=4, min_leg_diff=0.18, max_sym=0.90):
    """Return (ok, score, notes). img is magenta-keyed. Legs = bottom 40% of each figure's box."""
    a = np.asarray(img.convert("RGB")).astype(np.int16)
    fg = ~((a[..., 0] > 240) & (a[..., 1] < 20) & (a[..., 2] > 240))
    w = fg.shape[1]; slots = []
    for i in range(n):
        m = _crop(fg[:, int(w * i / n):int(w * (i + 1) / n)])
        if m is None: return False, 0.0, f"frame {i+1} empty"
        slots.append(m)
    legs = [_resize(m[int(m.shape[0] * 0.6):]) for m in slots]
    d1, d3 = 1 - _iou(legs[0], legs[1]), 1 - _iou(legs[2], legs[1])
    sym = [_iou(_resize(m), _resize(m)[:, ::-1]) for m in slots]
    hs = [m.shape[0] for m in slots]
    notes = f"legdiff {d1:.2f}/{d3:.2f} sym {'/'.join(f'{s:.2f}' for s in sym)} h {min(hs)}-{max(hs)}"
    ok = d1 >= min_leg_diff and d3 >= min_leg_diff and max(sym) <= max_sym and min(hs) > 0.75 * max(hs)
    score = min(d1, d3) - max(0, max(sym) - max_sym) - (0 if min(hs) > 0.75 * max(hs) else 0.3)
    return ok, score, notes

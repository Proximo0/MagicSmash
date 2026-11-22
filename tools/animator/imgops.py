"""Small numpy-only image helpers used by fit / autocut (no scipy)."""
import numpy as np

N8 = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
N4 = [(-1, 0), (1, 0), (0, -1), (0, 1)]


def shift(a, dy, dx, fill=0):
    """a shifted so that out[y, x] = a[y + dy, x + dx] (outside = fill)."""
    H, W = a.shape[:2]
    out = np.full_like(a, fill)
    ys0, ys1 = max(0, -dy), min(H, H - dy)
    xs0, xs1 = max(0, -dx), min(W, W - dx)
    out[ys0:ys1, xs0:xs1] = a[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx]
    return out


def components(mask):
    """8-connected labels: (lab HxW int32 with 0 = background, sizes dict label -> count).
    Min-label propagation with pointer jumping, so it converges in a few dozen passes."""
    H, W = mask.shape
    N = H * W
    big = N
    flat = mask.ravel()
    lab = np.where(flat, np.arange(N), big)
    while True:
        L = lab.reshape(H, W)
        m = L.copy()
        for dy, dx in N8:
            m = np.minimum(m, shift(L, dy, dx, big))
        m = np.where(mask, m, big).ravel()
        for _ in range(4):
            ok = m < big
            m[ok] = m[m[ok]]
        if np.array_equal(m, lab):
            break
        lab = m
    lab = lab.reshape(H, W)
    ids, inv, cnt = np.unique(lab, return_inverse=True, return_counts=True)
    out = np.zeros((H, W), np.int32)
    sizes = {}
    k = 0
    for i, (v, c) in enumerate(zip(ids, cnt)):
        if v == big:
            continue
        k += 1
        sizes[k] = int(c)
    remap = np.zeros(len(ids), np.int32)
    k = 0
    for i, v in enumerate(ids):
        if v != big:
            k += 1
            remap[i] = k
    out = remap[inv.reshape(H, W)]
    return out, sizes


def dilate(mask, r=1):
    out = mask.copy()
    for _ in range(r):
        m = out.copy()
        for dy, dx in N8:
            m |= shift(out, dy, dx, False)
        out = m
    return out


def fill(img, own, holes, max_iter=400):
    """Grow the `own` pixels of img into `holes`, one ring at a time (onion peel).  Each new
    pixel copies a 4-neighbour already filled (left/right first, then up/down), so the fill is
    made only of the part's own colours and continues stripes along rows.  Vectorized."""
    img = img.copy()
    filled = own.copy()
    todo = holes & ~own
    for _ in range(max_iter):
        if not todo.any():
            break
        got = np.zeros_like(todo)
        for dy, dx in ((0, 1), (0, -1), (-1, 0), (1, 0), (-1, 1), (-1, -1), (1, 1), (1, -1)):
            src_ok = shift(filled, dy, dx, False)
            take = todo & ~got & src_ok
            if take.any():
                img[take] = shift(img, dy, dx, 0)[take]
                got |= take
        if not got.any():
            break
        filled |= got
        todo &= ~got
    return img


def runs(row, min_w=1):
    """Runs of True in a 1-D bool array: list of (x0, x1) inclusive."""
    xs = np.flatnonzero(row)
    if not len(xs):
        return []
    br = np.flatnonzero(np.diff(xs) > 1)
    starts = np.r_[xs[0], xs[br + 1]]
    ends = np.r_[xs[br], xs[-1]]
    return [(int(s), int(e)) for s, e in zip(starts, ends) if e - s + 1 >= min_w]


def seg_dist(P, a, b):
    """Distance from points P (...,2) to segment a-b, and the projection parameter t."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ab = b - a
    L2 = max(float(ab @ ab), 1e-9)
    t = ((P[..., 0] - a[0]) * ab[0] + (P[..., 1] - a[1]) * ab[1]) / L2
    tc = np.clip(t, 0, 1)
    qx = a[0] + tc * ab[0]
    qy = a[1] + tc * ab[1]
    return np.hypot(P[..., 0] - qx, P[..., 1] - qy), t

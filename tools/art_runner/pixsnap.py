"""Pixel-perfect clean-up of AI "pixel art" (fake, blurry, off-grid big pixels on flat #FF00FF magenta).
usage: pixsnap.py IN.png OUT.png [--scale S] [--target-height H] [--palette FILE.hex] [--colors K] [--no-trim] [--quiet]
 OUT.png is the native sprite (1 image px = 1 art px, transparent background).
 With --target-height H and a native height != H, OUT_h<H>.png is the nearest-neighbour rescale to H px tall.
Also importable: snap(rgb_array, scale=None, ...) -> (rgba uint8 native, info dict)."""
import argparse, os, re, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from scipy.cluster.vq import kmeans2

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PALETTE = os.path.join(HERE, "realm_palette.hex")
LEAD = 0.05            # a colour wins a block when it leads the runner-up by more than 5 % of the block
SHADOW_BAND = 0.15      # bottom share of the figure box searched for the cast shadow
FRAG = 0.02             # loose pieces smaller than this share of the main figure are dropped
MIN_P, MAX_P = 3.0, 48.0


def magenta_mask(a):
    """Flat key colour, its blends with dark/light edges and shadows: strongly red+blue over green."""
    r, g, b = (a[..., i].astype(np.int16) for i in range(3))
    return (np.minimum(r, b) - g > 60) & (np.abs(r - b) < 80) & (np.minimum(r, b) > 90)


def _profiles(a):
    f = a.astype(np.float32)
    gx = np.abs(np.diff(f, axis=1)).sum(axis=2)   # (h, w-1) edge between x and x+1
    gy = np.abs(np.diff(f, axis=0)).sum(axis=2)
    gx = np.minimum(gx, 120.0); gy = np.minimum(gy, 120.0)   # clip so a few harsh edges do not dominate
    return gx.sum(axis=0), gy.sum(axis=1)


def _fold(prof, p, nb=64):
    x = np.arange(len(prof)) + 1.0                 # edge sits at boundary index x
    ph = np.mod(x, p) / p
    return np.bincount((ph * nb).astype(int) % nb, weights=prof, minlength=nb)


def _comb(profs, p, nb=64):
    """Fraction of edge mass in the best phase window (+-1.5 px) minus the chance level."""
    tot = sum(pr.sum() for pr in profs) + 1e-9
    h = _fold(profs[0], p, nb) + (_fold(profs[1], p, nb) if len(profs) > 1 else 0)
    k = max(1, int(round(1.5 / p * nb)))
    hh = np.concatenate([h, h[:2 * k]])
    win = np.convolve(hh, np.ones(2 * k + 1), mode="valid")[:nb]
    return win.max() / tot - (2 * k + 1) / nb


def detect_scale(a):
    px, py = _profiles(a)
    ps = np.arange(MIN_P, MAX_P, 0.05)
    sc = np.array([_comb([px, py], p) for p in ps])
    best = sc.max()
    # largest period that is nearly as good as the best: sub-multiples tie, multiples score lower
    ok = np.where(sc >= 0.85 * best)[0]
    # take local maxima among ok, pick the largest p
    cand = [i for i in ok if sc[i] >= sc[max(0, i - 3):i + 4].max() - 1e-12]
    i = max(cand, key=lambda i: ps[i])
    return float(ps[i]), float(sc[i] / max(best, 1e-9)), float(best)


def detect_offset(prof, p):
    """Boundary phase (0..p): peak of the folded edge profile, refined by the weighted centre of its flanks."""
    nb = 64
    h = _fold(prof, p, nb)
    k = max(1, int(round(1.5 / p * nb)))
    hh = np.concatenate([h, h[:2 * k]])
    win = np.convolve(hh, np.ones(2 * k + 1), mode="valid")[:nb]
    j = int(win.argmax()) + k                                    # window centre bin
    idx = np.arange(j - nb // 8, j + nb // 8 + 1)
    w = h[idx % nb]
    c = (idx * w).sum() / max(w.sum(), 1e-9)
    return float(c + 0.5) / nb * p % p


def quantize(a, k, seed=1):
    """Light k-means of the whole picture (non-key pixels only); returns indexed image and the centres."""
    key = magenta_mask(a)
    pix = a[~key].astype(np.float32)
    if len(pix) < k:
        return np.zeros(a.shape[:2], np.int32), pix[:1], key
    rng = np.random.RandomState(seed)
    sub = pix[rng.choice(len(pix), min(len(pix), 40000), replace=False)]
    init = sub[rng.choice(len(sub), k, replace=False)]
    cen, _ = kmeans2(sub, init, iter=12, minit="matrix")
    cen = cen[~np.isnan(cen).any(axis=1)]
    d = ((a.reshape(-1, 1, 3).astype(np.float32) - cen[None]) ** 2).sum(axis=2) if a.size < 3_000_000 else None
    if d is None:
        lab = np.concatenate([((a.reshape(-1, 3)[i:i + 200000, None].astype(np.float32) - cen[None]) ** 2).sum(2).argmin(1)
                              for i in range(0, a.shape[0] * a.shape[1], 200000)])
    else:
        lab = d.argmin(1)
    return lab.reshape(a.shape[:2]).astype(np.int32), cen, key


def _edges(n, p, o):
    e = list(np.arange(o - p * np.ceil(o / p), n + p, p))   # boundaries incl. the one at/below 0
    e = [int(round(max(0, min(n, v)))) for v in e]
    out = [e[0]]
    for v in e[1:]:
        if v > out[-1]: out.append(v)
    if out[-1] < n: out.append(n)
    return out


def snap(a, scale=None, colors=24, palette=None, trim=True):
    a = a[..., :3].astype(np.uint8)
    info = {}
    if scale is None:
        p, rel, strength = detect_scale(a)
        info.update(scale=p, conf=strength)
        if strength < 0.05:
            info["warn"] = "weak grid"
    else:
        p = float(scale); info.update(scale=p, given=True)
    px, py = _profiles(a)
    ox, oy = detect_offset(px, p), detect_offset(py, p)
    info.update(ox=ox, oy=oy)
    lab, cen, key = quantize(a, colors)
    ex, ey = _edges(a.shape[1], p, ox), _edges(a.shape[0], p, oy)
    H, W = len(ey) - 1, len(ex) - 1
    rgb = np.zeros((H, W, 3), np.float32); alpha = np.zeros((H, W), bool)
    dark = np.zeros((H, W), np.float32)
    lum = cen @ np.array([0.3, 0.59, 0.11], np.float32)
    darkest = int(np.argmin(lum))
    for j in range(H):
        for i in range(W):
            kb = key[ey[j]:ey[j + 1], ex[i]:ex[i + 1]]
            if kb.mean() > 0.5: continue
            lb = lab[ey[j]:ey[j + 1], ex[i]:ex[i + 1]][~kb]
            cnt = np.bincount(lb, minlength=len(cen)).astype(np.float32)
            n = cnt.sum(); order = np.argsort(-cnt)
            if cnt[order[0]] - (cnt[order[1]] if len(order) > 1 else 0) > LEAD * n:
                rgb[j, i] = cen[order[0]]
            else:
                rgb[j, i] = a[ey[j]:ey[j + 1], ex[i]:ex[i + 1]][~kb].mean(axis=0)
            alpha[j, i] = True
            dark[j, i] = (lum[lb] < 45).mean()
    # a block on the silhouette edge with a good share of near-black keeps the outline
    near = ndi.binary_dilation(~alpha, structure=ndi.generate_binary_structure(2, 2)) & alpha
    force = near & (dark > 0.35)
    rgb[force] = cen[darkest]
    # silhouette-edge blocks still tinted by the key colour are fringe, not art
    r_, g_, b_ = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    tint = (np.minimum(r_, b_) - g_ > 28) & (np.abs(r_ - b_) < 70) & (np.minimum(r_, b_) > 70)
    alpha &= ~(near & tint & ~force)
    if alpha.any():
        # cast ground shadow: flat, low-saturation grey/lavender in the bottom 12% of the figure's box
        ys_ = np.where(alpha.any(axis=1))[0]
        y0_, y1_ = ys_.min(), ys_.max() + 1
        band = np.zeros_like(alpha); band[int(y1_ - max(1, round((y1_ - y0_) * SHADOW_BAND))):y1_] = True
        mx, mn = rgb.max(axis=2), rgb.min(axis=2)
        shade = (mx - mn < 48) & (b_ >= g_ - 1) & (r_ >= g_ - 8) & (mx > 55) & (mx < 235)
        alpha &= ~(band & shade & ~force)
        # loose fragments: keep components touching the main figure or bigger than 2% of it
        lbl, m = ndi.label(alpha, structure=np.ones((3, 3)))
        if m:
            sizes = ndi.sum(alpha, lbl, range(1, m + 1))
            main = int(np.argmax(sizes)) + 1
            near_main = ndi.binary_dilation(lbl == main, structure=np.ones((3, 3)), iterations=1) & alpha
            for q in range(1, m + 1):
                if q != main and sizes[q - 1] < FRAG * sizes[main - 1] and not (near_main & (lbl == q)).any():
                    alpha[lbl == q] = False
    rgba = np.zeros((H, W, 4), np.uint8)
    rgba[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8); rgba[..., 3] = alpha * 255
    if palette is not None:
        rgba = apply_palette(rgba, palette)
    if trim and alpha.any():
        ys, xs = np.where(alpha)
        rgba = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    info["native"] = (rgba.shape[1], rgba.shape[0])
    return rgba, info


def load_palette(path):
    cols = []
    for ln in open(path):
        ln = ln.split(";")[0].strip().lstrip("#")
        if re.fullmatch(r"[0-9a-fA-F]{6}", ln):
            cols.append([int(ln[i:i + 2], 16) for i in (0, 2, 4)])
    return np.array(cols, np.float32)


def apply_palette(rgba, pal):
    if isinstance(pal, str): pal = load_palette(pal)
    out = rgba.copy()
    m = out[..., 3] > 0
    px = out[m][:, :3].astype(np.float32)
    # weighted RGB distance (redmean-ish) is close enough for dark palettes
    d = (((px[:, None] - pal[None]) * np.array([0.30, 0.59, 0.11], np.float32) ** 0.5) ** 2).sum(axis=2)
    out[m, :3] = pal[d.argmin(1)].astype(np.uint8)
    return out


def int_scale(native_h, target):
    """Integer upscale k nearest to target/native_h and the height it gives; (k, h, clean) where clean means
    the result is within 2 px of target (pad/crop at the top), else the caller keeps the native size (k=1)."""
    k = max(1, round(target / native_h))
    if native_h * k >= target - 2 and native_h * k <= target + 2 and target / native_h >= 0.75:
        return k, target, True
    return 1, native_h, False


def rescale(rgba, height):
    """Nearest-neighbour to the game height with an integer factor only; None when that is not possible."""
    k, h, clean = int_scale(rgba.shape[0], height)
    if not clean:
        return None
    up = np.repeat(np.repeat(rgba, k, axis=0), k, axis=1)
    out = np.zeros((height, up.shape[1], 4), np.uint8)
    d = up.shape[0] - height                       # >0 crop top rows, <0 pad on top
    if d >= 0: out[:] = up[d:]
    else: out[-d:] = up
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst")
    ap.add_argument("--scale", type=float, default=None, help="fake pixel size; default: detect")
    ap.add_argument("--target-height", type=int, default=0)
    ap.add_argument("--palette", default=None, help="FILE.hex (one RRGGBB per line)")
    ap.add_argument("--colors", type=int, default=24)
    ap.add_argument("--no-trim", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    o = ap.parse_args(argv)
    a = np.asarray(Image.open(o.src).convert("RGB"))
    rgba, info = snap(a, o.scale, o.colors, o.palette, not o.no_trim)
    Image.fromarray(rgba, "RGBA").save(o.dst)
    msg = f"pixsnap {os.path.basename(o.src)} scale={info['scale']:.2f} native={info['native'][0]}x{info['native'][1]}"
    if o.target_height and rgba.shape[0] != o.target_height:
        base, ext = os.path.splitext(o.dst)
        r = rescale(rgba, o.target_height)
        if r is None:
            msg += f" NO integer fit for h{o.target_height}: keep native {rgba.shape[1]}x{rgba.shape[0]}, draw it at its own scale"
        else:
            Image.fromarray(r, "RGBA").save(f"{base}_h{o.target_height}{ext}")
            msg += f" -> h{o.target_height}"
    if info.get("warn"): msg += " WARN " + info["warn"]
    if not o.quiet: print(msg)
    return info


if __name__ == "__main__":
    main()

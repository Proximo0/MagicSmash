"""Turn raw SDXL pixel-art pictures into game-ready sprites: find the pixel grid, shrink to true pixel size,
reduce the palette, magenta -> transparent. CPU only, so it can run beside the GPU runner.
Usage: clean.py [src_dir] [dst_dir]   (defaults raw -> clean; skips files already cleaned)"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

MAG = np.array([255, 0, 255])


def grid_size(a, lo=3, hi=16):
    """Pixel-art block size: edges between colour runs line up on a lattice of period s."""
    best = []
    for axis in (0, 1):
        d = np.abs(np.diff(a.astype(np.int16), axis=axis)).sum(-1) > 40
        pos = np.nonzero(d.any(axis=1 - axis) if False else d)[axis] + 1
        if len(pos) < 50: continue
        sc = {}
        for s in range(lo, hi + 1):
            h = np.bincount(pos % s, minlength=s)
            sc[s] = h.max() / len(pos) * s  # concentration vs uniform
        m = max(sc.values())
        best.append(min(s for s, v in sc.items() if v >= 0.85 * m))
        best[-1] = (best[-1], int(np.argmax(np.bincount(pos % best[-1], minlength=best[-1]))))
    if not best: return 1, (0, 0)
    s = int(round(np.median([b[0] for b in best])))
    offs = tuple(b[1] % s for b in best) + (0,) * (2 - len(best))
    return s, offs


def shrink(a, s, oy, ox):
    a = a[oy:, ox:]
    H, W = a.shape[0] // s, a.shape[1] // s
    b = a[:H * s, :W * s].reshape(H, s, W, s, 3)
    c = b[:, s // 4: s - s // 4, :, s // 4: s - s // 4]  # centre of each block, avoids blended edges
    return np.median(c.reshape(H, c.shape[1], W, c.shape[3], 3).transpose(0, 2, 1, 3, 4).reshape(H, W, -1, 3),
                     axis=2).astype(np.uint8)


PALETTE_FILE = Path(r"D:\projects\hh_art\realm_palette.hex")
_PAL = None


def _lab(rgb):
    c = rgb.astype(np.float64) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    xyz = c @ np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]]).T
    xyz /= np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def to_palette(rgb):
    """Map every pixel to the nearest shared-palette colour in Lab space (no dithering)."""
    global _PAL
    if _PAL is None:
        cols = [l.split(";")[0].strip() for l in PALETTE_FILE.read_text().splitlines()]
        pal = np.array([[int(h[i:i + 2], 16) for i in (0, 2, 4)] for h in cols if len(h) == 6], dtype=np.uint8)
        _PAL = (pal, _lab(pal))
    pal, plab = _PAL
    flat = rgb.reshape(-1, 3)
    uniq, inv = np.unique(flat, axis=0, return_inverse=True)
    d = ((_lab(uniq)[:, None, :] - plab[None]) ** 2).sum(-1)
    return pal[d.argmin(1)][inv.reshape(-1)].reshape(rgb.shape)


def clean(src, dst, colors=32, tile=False):
    a = np.asarray(Image.open(src).convert("RGB"))
    if not tile:  # sprites: the lead's tools/art/pixsnap.py (grid snap, shadow band + loose fragment removal, palette)
        import pixsnap as PS
        global _PSPAL
        if "_PSPAL" not in globals(): _PSPAL = PS.load_palette(str(PALETTE_FILE))
        rgba, info = PS.snap(a, palette=_PSPAL)
        Image.fromarray(rgba, "RGBA").save(dst)
        return info.get("scale"), rgba.shape[1], rgba.shape[0]
    s, (oy, ox) = grid_size(a)
    small = shrink(a, s, oy, ox) if s > 1 else a
    from scipy import ndimage
    x = small.astype(np.int16)
    bg = (np.abs(x - MAG).sum(-1) < 90)
    # magenta-tinted pixels (keying fringe, shadows blended with the backdrop) that touch the background go too
    tint = (x[..., 0] - x[..., 1] > 35) & (x[..., 2] - x[..., 1] > 35) & (np.abs(x[..., 0] - x[..., 2]) < 70)
    lab, _ = ndimage.label(bg | tint)
    bg = np.isin(lab, np.unique(lab[bg])) & (lab > 0)
    q = to_palette(small)
    out = np.dstack([q,np.where(bg & (not tile), 0, 255).astype(np.uint8)])
    Image.fromarray(out, "RGBA").save(dst)
    return s, small.shape[1], small.shape[0]


if __name__ == "__main__":
    src = Path(sys.argv[1] if len(sys.argv) > 1 else r"D:\projects\hh_art\raw")
    dst = Path(sys.argv[2] if len(sys.argv) > 2 else r"D:\projects\hh_art\clean"); dst.mkdir(exist_ok=True)
    for f in sorted(src.glob("*.png")):
        t = dst / f.name
        if t.exists(): continue
        s, w, h = clean(f, t, tile=f.name.startswith("TL"))
        print(f.name, "grid", s, "->", w, "x", h)

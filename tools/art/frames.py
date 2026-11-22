"""Cut a walk-cycle sheet (N frames in a row on magenta) into aligned frames and a preview GIF.
usage: frames.py SHEET OUTDIR NAME N HEIGHT [nosnap]
Each frame goes through pixsnap (detect the fake pixel grid, one px per art px, optional shared palette) before the
nearest-neighbour rescale to HEIGHT. Off: 6th argument "nosnap" or env PIXSNAP=0. Palette: env PIXSNAP_PALETTE=file.hex."""
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixsnap
SNAP = os.environ.get("PIXSNAP", "1") != "0" and "nosnap" not in sys.argv[6:]
PAL = os.environ.get("PIXSNAP_PALETTE") or None
src, out, name, n, height = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
a = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
h, w, _ = a.shape
r, g, b = a[..., 0], a[..., 1], a[..., 2]
key = (r > g * 1.5 + 8) & (b > g * 1.2 + 6) & (r > b * 0.85)        # any magenta: the flat background and its shadows
c = 44                                                               # the site's hover buttons sit in the corners
for ys, xs in [(slice(0, c), slice(0, c)), (slice(0, c), slice(w - c, w)), (slice(h - c, h), slice(0, c)), (slice(h - c, h), slice(w - c, w))]:
    key[ys, xs] = True
lab, _ = ndi.label(key)
border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
back = np.isin(lab, border[border > 0])
labp, _ = ndi.label(key & ~back)
for i, sl in enumerate(ndi.find_objects(labp), 1):                   # pockets between arms and legs
    part = labp[sl] == i
    if part.sum() >= 30: back[sl] |= part
keep = ndi.binary_opening(~back, iterations=1)
lab, m = ndi.label(keep)
sizes = ndi.sum(keep, lab, range(1, m + 1))
keep &= np.isin(lab, [i + 1 for i in range(m) if sizes[i] >= 40])  # drop specks
# Split by columns, not by blobs: a figure can fall apart into pieces (dark armour keyed), and pieces of
# neighbours can touch. Cut at the n-1 widest runs of empty columns; if too few, at the emptiest columns.
col = keep.sum(axis=0)
xs_on = np.where(col > 0)[0]
lo, hi = xs_on.min(), xs_on.max() + 1
runs, x = [], lo
while x < hi:
    if col[x] == 0:
        x2 = x
        while x2 < hi and col[x2] == 0: x2 += 1
        runs.append((x2 - x, (x + x2) // 2)); x = x2
    else: x += 1
runs.sort(reverse=True)
cuts = sorted(c for _, c in runs[:n - 1])
if True:  # always: near each expected cut, the emptiest column (gaps alone mislead)
    sm = np.convolve(col, np.ones(9) / 9, mode="same")
    cuts = []
    for k in range(1, n):
        c0 = lo + (hi - lo) * k // n; span = int((hi - lo) / (2.5 * n))
        cuts.append(c0 - span + int(np.argmin(sm[c0 - span:c0 + span])))
edges = [lo] + cuts + [hi]
print("figures", n, "cuts", cuts, "gaps", len(runs))
frames = []
snap_scale = pixsnap.detect_scale(a.astype(np.uint8))[0] if SNAP else None   # one fake-pixel size for the whole sheet
for k in range(n):
    part = np.zeros_like(keep); part[:, edges[k]:edges[k + 1]] = keep[:, edges[k]:edges[k + 1]]
    yy, xx = np.where(part)
    y0, y1, x0, x1 = yy.min(), yy.max() + 1, xx.min(), xx.max() + 1
    rgba = np.dstack([a[y0:y1, x0:x1], part[y0:y1, x0:x1] * 255]).astype(np.uint8)
    if SNAP:
        rgb = np.where(part[y0:y1, x0:x1, None], a[y0:y1, x0:x1], 255 * np.array([1, 0, 1])).astype(np.uint8)
        rgba, info = pixsnap.snap(rgb, scale=snap_scale, palette=PAL)
        print("pixsnap frame", k, "scale %.2f" % info["scale"], "native %dx%d" % info["native"])
    frames.append(Image.fromarray(rgba, "RGBA"))
tall = max(f.height for f in frames)
if SNAP:   # integer factor only; if none lands within 2 px of HEIGHT the native size is kept (cells are then taller)
    s, ch, clean = pixsnap.int_scale(tall, height)
    if not clean: print("pixsnap: no integer fit for height", height, "- native frame height", tall)
    height = ch
else:
    s = height / tall
cw = int(max(f.width for f in frames) * s) + 4
os.makedirs(out, exist_ok=True)
cells = []
for k, f in enumerate(frames):
    f2 = f.resize((max(1, round(f.width * s)), max(1, round(f.height * s))), Image.NEAREST if SNAP else Image.LANCZOS)
    al = np.asarray(f2).copy(); al[..., 3] = np.where(al[..., 3] > 110, 255, 0); f2 = Image.fromarray(al, "RGBA")
    cell = Image.new("RGBA", (cw, height), (0, 0, 0, 0))
    cell.paste(f2, ((cw - f2.width) // 2, height - f2.height))   # a frame up to 2 px too tall loses its top rows
    cell.save(f"{out}/{name}_walk{k}.png"); cells.append(cell)
strip = Image.new("RGBA", (cw * len(cells), height), (0, 0, 0, 0))
for k, cimg in enumerate(cells): strip.paste(cimg, (k * cw, 0))
strip.save(f"{out}/{name}_walk.png")
z = 4
gif = []
for cimg in cells:
    bgim = Image.new("RGBA", (cw * z + 40, height * z + 40), (38, 34, 40, 255))
    big_ = cimg.resize((cw * z, height * z), Image.NEAREST)
    bgim.alpha_composite(big_, (20, 20)); gif.append(bgim.convert("P", palette=Image.ADAPTIVE))
gif[0].save(f"{out}/{name}_walk.gif", save_all=True, append_images=gif[1:], duration=160, loop=0)
sheet = Image.new("RGBA", (cw * z * len(cells), height * z), (38, 34, 40, 255))
for k, cimg in enumerate(cells): sheet.alpha_composite(cimg.resize((cw * z, height * z), Image.NEAREST), (k * cw * z, 0))
sheet.save(f"{out}/{name}_walk_4x.png")

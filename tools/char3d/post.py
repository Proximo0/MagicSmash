"""4x renders -> game-size sprite rows: box downscale, hard alpha, shared palette, 1 px dark outline."""
import sys, json, os
import numpy as np
from PIL import Image
src, out, name = sys.argv[1:4]
meta = json.load(open(os.path.join(src, "meta.json")))
# Crisp shrink, by material: the render comes with a second picture per frame that says which material each pixel is.
# Each material gets TONES flat tones (shadow, mid, light) taken from all its pixels in all frames; each 4x4 block takes
# the material most of its covered pixels have and that material's most common tone; a darker pixel is drawn where two
# materials meet. No averaging anywhere, so nothing is blurred into its neighbour.
TONES = int(os.environ.get("TONES", "3"))    # for a plain material; a textured one (several hues) gets twice as many
TMAX = TONES * 2
LINE = float(os.environ.get("LINE", "0.62"))
FL = -1 if os.environ.get("FLIP") else 1
def load(a, i, suffix=""):
    return np.asarray(Image.open(os.path.join(src, "%s_%02d%s.png" % (a, i, suffix))).convert("RGBA"))[:, ::FL]
def ids_of(im):
    k = np.rint(im[..., 0] / 8.0).astype(np.int64) + 32 * np.rint((im[..., 1].astype(np.float32) - 40) / 64.0).astype(np.int64)
    return np.where(im[..., 3] > 127, k, 0)                           # 0 = empty
raw = {a: [(load(a, i), ids_of(load(a, i, "_id"))) for i in range(n)] for a, n in meta.items()}
NID = max(k.max() for fr in raw.values() for _, k in fr) + 1
tones = np.zeros((NID, TMAX, 3), np.uint8)
for m in range(1, NID):
    px = [im[(k == m) & (im[..., 3] > 127)][:, :3][::5] for fr in raw.values() for im, k in fr]
    px = np.concatenate(px) if px else np.zeros((0, 3), np.uint8)
    if len(px) == 0:
        continue
    f = px.astype(np.float32)
    chroma = (f - f.mean(1, keepdims=True)).std(0).max()             # how much the hue itself varies inside the material
    T = TMAX if chroma > 14 else TONES
    q = Image.fromarray(px[None], "RGB").quantize(T, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    got = np.array(q.getpalette()[:T * 3], np.uint8).reshape(-1, 3)
    used = np.unique(np.asarray(q))
    pal = np.repeat(got[used[:1]], TMAX, 0)                          # unused places repeat the first tone
    pal[:len(used)] = got[used]
    tones[m] = pal
OUT = np.array([18, 13, 20], np.uint8)
def finish(im, k):
    h, w = k.shape
    kb = k.reshape(h // 4, 4, w // 4, 4).transpose(0, 2, 1, 3).reshape(h // 4, w // 4, 16)
    cb = im[..., :3].reshape(h // 4, 4, w // 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(h // 4, w // 4, 16, 3).astype(np.int32)
    counts = (kb[..., None] == np.arange(NID)).sum(2)
    m = counts[..., 0] < 8
    mid = counts[..., 1:].argmax(2) + 1                              # the block's material
    t = tones[mid].astype(np.int32)                                  # (H, W, TONES, 3)
    d = ((cb[:, :, :, None, :] - t[:, :, None, :, :]) ** 2).sum(-1)  # each pixel against each tone
    near = d.argmin(-1)
    mine = kb == mid[..., None]
    votes = ((near[..., None] == np.arange(TMAX)) & mine[..., None]).sum(2)
    col = np.take_along_axis(t, votes.argmax(-1)[..., None, None], 2)[:, :, 0, :]
    o = np.zeros((h // 4, w // 4, 4), np.uint8)
    o[m, :3] = col[m]; o[m, 3] = 255
    seam = np.zeros_like(m)                                          # one dark pixel where two materials meet
    seam[:, :-1] |= (mid[:, :-1] != mid[:, 1:]) & m[:, :-1] & m[:, 1:]
    seam[:-1, :] |= (mid[:-1, :] != mid[1:, :]) & m[:-1, :] & m[1:, :]
    o[seam, :3] = (o[seam, :3] * LINE).astype(np.uint8)
    p = np.pad(m, 1)
    edge = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]) & ~m
    o[edge, :3] = OUT; o[edge, 3] = 255
    return o
rows = raw
os.makedirs(out, exist_ok=True)
info = {}
for a, fr in rows.items():
    fs = [finish(*f) for f in fr]
    strip = np.concatenate(fs, 1)
    Image.fromarray(strip).save(os.path.join(out, "%s_%s.png" % (name, a.lower())))
    info[a] = {"frames": len(fs), "frame_px": list(fs[0].shape[:2][::-1]), "colours": len(np.unique(strip.reshape(-1, 4), axis=0))}
json.dump(info, open(os.path.join(out, name + ".json"), "w"), indent=1)
if os.environ.get("NOSHEET"):                                        # build_town.py: one still, not square, no sheet
    sys.exit(0)
sc = 6
strips = {a: np.asarray(Image.open(os.path.join(out, "%s_%s.png" % (name, a.lower())))) for a in info}
fw = next(iter(info.values()))["frame_px"][0]
allm = np.any([st[..., 3].reshape(fw, -1, fw).any(1) for st in strips.values()], 0)  # columns used within a frame
ys = np.any([st[..., 3].any(1) for st in strips.values()], 0)
x0, x1 = np.nonzero(allm)[0][[0, -1]]; y0, y1 = np.nonzero(ys)[0][[0, -1]]
x0 = max(x0 - 2, 0); x1 = min(x1 + 3, fw); y0 = max(y0 - 2, 0); y1 = min(y1 + 3, fw)
cw, ch = x1 - x0, y1 - y0
from PIL import ImageDraw
W = max(v["frames"] for v in info.values()) * cw
sheet = Image.new("RGBA", (W * sc + 150, len(info) * (ch * sc + 6)), (58, 66, 58, 255))
d = ImageDraw.Draw(sheet)
for r, (a, st) in enumerate(strips.items()):
    d.text((6, r * (ch * sc + 6) + ch * sc // 2), a.replace("_", " ").lower(), fill=(230, 230, 230, 255))
    for f in range(info[a]["frames"]):
        t = Image.fromarray(st[y0:y1, f * fw + x0:f * fw + x1])
        sheet.alpha_composite(t.resize((cw * sc, ch * sc), Image.NEAREST), (150 + f * cw * sc, r * (ch * sc + 6)))
sheet.convert("RGB").save(os.path.join(out, name + "_sheet_6x.png"))
print(info, cw, ch)

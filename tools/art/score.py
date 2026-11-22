"""Score and rank the raw tries (<id>_<n>.png, n=1..4, flat #FF00FF) of each queue id; write ranks.json and contact sheets.
usage: score.py RAWDIR [--queue queue_sd.json] [--out local] [--ids HR1.1,HR1.2] [--batch HR1] [--clip]
 RAWDIR is searched recursively for files whose name ends <id>_<n>.png (a test_c_ prefix is fine).
 Checks per try (0..1 each): bg (magenta border), figs (walk sheet 4 similar heights, others 1), edge (nothing touches
 the edge), fill (figure size sensible). Tiles: no magenta, seams match, not flat. CLIP only with --clip and a model
 already on disk (open_clip + weights in the cache or CLIP_CKPT=path); never downloads.
 Out: OUT/ranks.json, OUT/contact/<batch>.png (a batch is the id's letters+number: HR1.2 -> HR1)."""
import argparse, json, os, re, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
NAME_RE = re.compile(r"(?:^|[_ ])([A-Z]{2}\d+\.\d+)_(\d)\.png$")
W = {"bg": 0.25, "figs": 0.3, "edge": 0.2, "fill": 0.25}


def key_mask(a):
    """Flat magenta and its shadows/blends (same rule as tools/frames.py)."""
    r, g, b = (a[..., i].astype(np.float32) for i in range(3))
    k = (r > g * 1.5 + 8) & (b > g * 1.2 + 6) & (r > b * 0.85)
    return k


def groups(fg, gap):
    """Figures as runs of occupied columns, runs closer than gap merged (figures fall into pieces, neighbours touch)."""
    h, w = fg.shape
    col = fg.sum(axis=0)
    on = col > max(1, h * 0.002)
    runs, i = [], 0
    while i < w:
        if on[i]:
            j = i
            while j < w and on[j]:
                j += 1
            runs.append([i, j]); i = j
        else:
            i += 1
    merged = []
    for r in runs:
        if merged and r[0] - merged[-1][1] < gap:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    out = []
    for x0, x1 in merged:
        ys = np.where(fg[:, x0:x1].any(axis=1))[0]
        if fg[:, x0:x1].sum() >= 0.0015 * fg.size:
            out.append((x0, ys.min(), x1, ys.max() + 1))
    return out


def tri(x, lo0, lo1, hi1, hi0):
    """0 below lo0, ramps to 1 at lo1, 1 until hi1, ramps to 0 at hi0."""
    if x <= lo0 or x >= hi0: return 0.0
    if x < lo1: return (x - lo0) / (lo1 - lo0)
    if x > hi1: return (hi0 - x) / (hi0 - hi1)
    return 1.0


def analyse(path, e):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im)
    h, w, _ = a.shape
    kind = e.get("kind", "one") if e else "one"
    notes, parts = [], {}
    k = key_mask(a)
    ring = max(3, int(min(h, w) * 0.01))
    border = np.concatenate([k[:ring].ravel(), k[-ring:].ravel(), k[:, :ring].ravel(), k[:, -ring:].ravel()])
    keyfrac = float(border.mean())
    info = {"size": [w, h]}
    if kind == "tile":
        free = 1.0 - float(k.mean())
        parts["bg"] = tri(free, 0.9, 0.99, 1, 1.01)           # tile must not contain magenta
        f = a.astype(np.float32)
        seam = (np.abs(f[:, 0] - f[:, -1]).mean() + np.abs(f[0] - f[-1]).mean()) / 2
        inner = (np.abs(np.diff(f, axis=1)).mean() + np.abs(np.diff(f, axis=0)).mean()) / 2 + 1e-3
        parts["edge"] = float(np.clip(1.2 - 0.5 * seam / inner, 0, 1))   # seam as smooth as the inside
        sd = float(f.std())
        parts["fill"] = tri(sd, 3, 12, 80, 120)                # not flat
        parts["figs"] = 1.0
        info.update(seam_ratio=round(float(seam / inner), 2), std=round(sd, 1))
        if parts["edge"] < 0.5: notes.append("seam visible")
        if parts["bg"] < 0.9: notes.append("magenta in tile")
        return parts, notes, info, None
    parts["bg"] = tri(keyfrac, 0.55, 0.97, 1, 1.01)
    if keyfrac < 0.9: notes.append("border %.0f%% magenta" % (keyfrac * 100))
    c = 44 if min(h, w) >= 600 else 0          # the site's hover buttons sit in the corners (frames.py)
    kk = k.copy()
    if c:
        for ys, xs in [(slice(0, c), slice(0, c)), (slice(0, c), slice(w - c, w)), (slice(h - c, h), slice(0, c)), (slice(h - c, h), slice(w - c, w))]:
            kk[ys, xs] = True
    fg = ~kk
    fg = ndi.binary_opening(fg, iterations=1)
    lab, m = ndi.label(fg)
    if m:
        sizes = ndi.sum(fg, lab, range(1, m + 1))
        fg &= np.isin(lab, [i + 1 for i in range(m) if sizes[i] >= 40])
    want = 4 if kind == "walk" else 1
    gs = groups(fg, gap=max(6, int(w * 0.03)))
    info["figures"] = len(gs)
    if not gs:
        parts.update(figs=0.0, edge=0.0, fill=0.0); notes.append("no figure")
        return parts, notes, info, None
    hs = np.array([g[3] - g[1] for g in gs], np.float32)
    if kind == "walk":
        n = len(gs)
        cs = 1.0 if n == 4 else (0.4 if n in (3, 5) else 0.0)
        spread = float(hs.max() / max(hs.min(), 1)) if n else 9
        cs *= tri(spread, 0.9, 1.0, 1.15, 1.6)
        if n != 4: notes.append("%d figures, want 4" % n)
        elif spread > 1.2: notes.append("heights vary x%.2f" % spread)
        if n >= 2:      # one character: the mean colour of each figure should agree
            mc = np.array([a[g[1]:g[3], g[0]:g[2]][fg[g[1]:g[3], g[0]:g[2]]].mean(axis=0) for g in gs])
            dist = float(np.abs(mc - np.median(mc, axis=0)).sum(axis=1).max())
            info["colour_spread"] = round(dist, 1)
            cs *= tri(dist, -1, 0, 25, 80)
            if dist > 40: notes.append("figures differ in colour")
    else:
        n = len(gs)
        big = hs.max()
        # several pieces are fine when one dominates; count only pieces over 25% of the biggest
        n = int((hs > 0.25 * big).sum())
        cs = 1.0 if n == 1 else (0.5 if n == 2 else 0.0)
        if n != 1: notes.append("%d figures, want 1" % n)
    parts["figs"] = cs
    ys, xs = np.where(fg)
    touch = bool(fg[0].any() or fg[-1].any() or fg[:, 0].any() or fg[:, -1].any())
    near = fg[:ring].sum() + fg[-ring:].sum() + fg[:, :ring].sum() + fg[:, -ring:].sum()
    parts["edge"] = 0.0 if touch else (0.7 if near else 1.0)
    if touch: notes.append("touches edge")
    bb_h = (ys.max() + 1 - ys.min()) / h
    bb_w = (xs.max() + 1 - xs.min()) / w
    if kind == "walk":
        fh = float(hs.mean()) / h
        parts["fill"] = min(tri(fh, 0.15, 0.4, 0.8, 0.97), tri(bb_w, 0.3, 0.55, 0.92, 1.0))
        if fh < 0.4: notes.append("figures small (%.0f%% high)" % (fh * 100))
    else:
        side = max(bb_h, bb_w * w / h)
        parts["fill"] = tri(side, 0.2, 0.45, 0.88, 0.99)
        if side < 0.45: notes.append("small (%.0f%%)" % (side * 100))
    info["bbox"] = [int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)]
    info["groups"] = [[int(v) for v in g] for g in gs]
    return parts, notes, info, fg


_clip = None
def clip_score(path, must):
    """Mean cosine of the picture to each must trait, 0..1-ish, or None when no model is on disk."""
    global _clip
    if _clip is None:
        try:
            import open_clip, torch
            ck = os.environ.get("CLIP_CKPT")
            if not ck: _clip = False; return None
            m, _, pre = open_clip.create_model_and_transforms(os.environ.get("CLIP_ARCH", "ViT-B-32"), pretrained=ck)
            _clip = (m.eval(), pre, open_clip.get_tokenizer(os.environ.get("CLIP_ARCH", "ViT-B-32")), torch)
        except Exception:
            _clip = False
    if not _clip or not must: return None
    m, pre, tok, torch = _clip
    with torch.no_grad():
        im = m.encode_image(pre(Image.open(path).convert("RGB")).unsqueeze(0))
        tx = m.encode_text(tok(["pixel art of " + t for t in must]))
        im /= im.norm(dim=-1, keepdim=True); tx /= tx.norm(dim=-1, keepdim=True)
        return float((im @ tx.T).mean())


def font(sz):
    try: return ImageFont.load_default(size=sz)
    except TypeError: return ImageFont.load_default()


def sprite_crop(path, info, e, fg):
    """The top try cut to game size: figure(s) bbox, background gone, scaled so the tallest figure is H px."""
    im = Image.open(path).convert("RGB")
    kind = e.get("kind", "one") if e else "one"
    if fg is None:
        t = 64
        return im.resize((t, t), Image.BOX), t
    x0, y0, x1, y1 = info["bbox"]
    H = e.get("height") if e else 0
    H = H if isinstance(H, int) and H > 0 else (48 if kind == "icon" else 56)
    if kind == "walk":
        th = max(g[3] - g[1] for g in info["groups"])
        s = H / th
    else:
        s = H / (y1 - y0)
        if kind != "walk" and (x1 - x0) * s > 240: s = 240 / (x1 - x0)
    rgba = np.dstack([np.asarray(im), (fg * 255).astype(np.uint8)])
    c = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
    nw, nh = max(1, round(c.width * s)), max(1, round(c.height * s))
    bg = Image.new("RGBA", c.size, (46, 44, 52, 255)); bg.alpha_composite(c)
    return bg.convert("RGB").resize((nw, nh), Image.BOX), H


def contact(batch, rows, outdir):
    TH, TW = 150, 260
    f, fb = font(13), font(22)
    LW = 150
    rowh = TH + 8
    crops = [t["crop"][0] for r in rows for t in r["tries"] if t["rank"] == 1 and t.get("crop") is not None]
    cw = max([3 * c.width + 12 for c in crops] + [200])
    sheet_w = LW + 4 * (TW + 6) + 12 + cw + 10
    img = Image.new("RGB", (sheet_w, rowh * len(rows) + 28), (30, 30, 36))
    d = ImageDraw.Draw(img)
    d.text((6, 6), "batch %s   (rank 1 = best; right: top try at game size, then 2x)" % batch, fill=(220, 220, 220), font=f)
    for ri, row in enumerate(rows):
        y0 = 28 + ri * rowh
        e = row["entry"]
        d.text((6, y0 + 4), row["id"], fill=(255, 220, 120), font=f)
        d.text((6, y0 + 22), (e or {}).get("name", "?")[:20], fill=(200, 200, 200), font=f)
        d.text((6, y0 + 40), "%s h=%s" % ((e or {}).get("kind", "?"), (e or {}).get("height", "?")), fill=(150, 150, 160), font=f)
        for t in row["tries"]:
            x0 = LW + (t["try"] - 1) * (TW + 6)
            th = Image.open(t["path"]).convert("RGB")
            th.thumbnail((TW, TH), Image.BOX)
            img.paste(th, (x0, y0))
            col = {1: (90, 255, 120), 2: (230, 230, 90)}.get(t["rank"], (255, 140, 120))
            d.rectangle([x0, y0, x0 + 30, y0 + 28], fill=(0, 0, 0))
            d.text((x0 + 7, y0 + 2), str(t["rank"]), fill=col, font=fb)
            d.text((x0 + 36, y0 + 4), "%.2f" % t["score"], fill=col, font=f)
            if t["notes"]:
                d.text((x0 + 2, y0 + TH - 15), "; ".join(t["notes"])[:44], fill=(255, 120, 120), font=f)
        top = [t for t in row["tries"] if t["rank"] == 1][0]
        if top.get("crop") is not None:
            c, H = top["crop"]
            xg = LW + 4 * (TW + 6) + 12
            img.paste(c, (xg, y0 + 4))
            c2 = c.resize((c.width * 2, c.height * 2), Image.NEAREST)
            img.paste(c2, (xg + c.width + 12, y0 + 4))
    os.makedirs(outdir, exist_ok=True)
    p = os.path.join(outdir, batch + ".png")
    img.save(p)
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("--queue", default=os.path.join(HERE, "queue_sd.json"))
    ap.add_argument("--out", default=os.path.join(HERE, "local"))
    ap.add_argument("--ids"); ap.add_argument("--batch"); ap.add_argument("--clip", action="store_true")
    a = ap.parse_args()
    q = {e["id"]: e for e in json.load(open(a.queue))}
    found = {}
    for root, _, files in os.walk(a.raw):
        for fn in files:
            m = NAME_RE.search(fn)
            if m: found.setdefault(fn[:m.start(2) - 1].lstrip("_ "), {})[int(m.group(2))] = os.path.join(root, fn)
    # a key is the file name without _<n>.png: the bare id for real tries, test_e_HR1.1 for a sample set
    idof = lambda k: NAME_RE.search(k + "_1.png").group(1)
    ids = sorted(found, key=lambda k: (re.match(r"[A-Z]+", idof(k)).group(), [int(x) for x in re.findall(r"\d+", idof(k))], k))
    if a.ids: ids = [i for i in ids if idof(i) in a.ids.split(",")]
    if a.batch: ids = [i for i in ids if idof(i).split(".")[0] == a.batch]
    ranks, batches = {}, {}
    for i in ids:
        e = q.get(idof(i))
        if e is None: print("note: %s is not in the queue" % i, file=sys.stderr)
        tries = []
        for n, p in sorted(found[i].items()):
            parts, notes, info, fg = analyse(p, e)
            s = sum(W[k] * parts[k] for k in W)
            lo = min(parts.values())
            if lo == 0.0: s *= 0.5          # a hard fail on any check halves it
            cs = clip_score(p, (e or {}).get("must")) if a.clip else None
            if cs is not None: s = 0.8 * s + 0.2 * float(np.clip((cs - 0.15) / 0.15, 0, 1))
            tries.append({"try": n, "path": p, "score": round(float(s), 3), "parts": {k: round(float(v), 2) for k, v in parts.items()},
                          "notes": notes, "info": info, "clip": cs, "fg": fg})
        order = sorted(tries, key=lambda t: -t["score"])
        for r, t in enumerate(order, 1): t["rank"] = r
        tries = order
        top = tries[0]
        top["crop"] = sprite_crop(top["path"], top["info"], e or {}, top["fg"]) if top["score"] > 0 else None
        ranks[i] = {"name": (e or {}).get("name"), "kind": (e or {}).get("kind"), "best": top["try"],
                    "ranking": [{k: v for k, v in t.items() if k not in ("fg", "crop", "path")} for t in tries]}
        batches.setdefault(idof(i).split(".")[0], []).append({"id": i, "entry": e, "tries": sorted(tries, key=lambda t: t["try"])})
        print("%-7s %-26s best=%d  %s" % (i, (e or {}).get("name", "?"), top["try"],
              " ".join("%d:%.2f" % (t["try"], t["score"]) for t in tries)))
    for b, rows in batches.items():
        contact(b, rows, os.path.join(a.out, "contact"))
    os.makedirs(a.out, exist_ok=True)
    json.dump(ranks, open(os.path.join(a.out, "ranks.json"), "w"), indent=1)
    print("SCORE ids=%d batches=%d -> %s" % (len(ids), len(batches), os.path.join(a.out, "ranks.json")))


if __name__ == "__main__":
    main()

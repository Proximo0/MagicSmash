#!/usr/bin/env python3
"""A look at the town without Godot: the plaza's cobbles, the hearth, every station at its TownMap place and one hero
for scale, composed the way town_screen.gd draws them (a picture pixel = HERO_BOX / 142 world px, bottom edge PIC_BASE
south of the station's point; ground tiles 512 px over 256 world px, the shader's a/b patches).

    python3 town_preview.py [out dir]      writes town_preview.png (whole plaza) and town_preview_smith.png
                                           (1440 x 810 round the smith at the game's town zoom, 1.5 x 1.5)
Run from anywhere; reads realm/client/art, realm/client/ground and realm/client/town/town_map.gd."""
import math
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "realm/client/art"
GROUND = ROOT / "realm/client/ground"
HERO_BOX = 64.0
PIC_K = HERO_BOX / 142.0
PIC_BASE, HEARTH_BASE = 24.0, 34.0
ZOOM = 1.5
CENTRE = (2048.0, 2048.0)
PLAZA_R = 1000.0


def stations():
    src = (ROOT / "realm/client/town/town_map.gd").read_text()
    out = []
    for m in re.finditer(r'\{"id": "(\w+)", "name": "([^"]+)", "at": Vector2\((\d+), (\d+)\)', src):
        out.append((m.group(1), m.group(2), float(m.group(3)), float(m.group(4))))
    return out


def ground(x0, y0, w, h, scale):
    """The plaza ground over world x0.. y0.., w x h preview px at `scale` px per world px (ground.gdshader in numpy)."""
    a = np.asarray(Image.open(GROUND / "ground_towna.png").convert("RGB"))
    b = np.asarray(Image.open(GROUND / "ground_townb.png").convert("RGB"))
    patch = np.asarray(Image.open(GROUND / "ground_patch.png").convert("L")).astype(np.float32) / 255.0
    blotch = np.asarray(Image.open(GROUND / "ground_blotch.png").convert("L")).astype(np.float32) / 255.0
    wx = x0 + (np.arange(w) + 0.5) / scale
    wy = y0 + (np.arange(h) + 0.5) / scale
    X, Y = np.meshgrid(wx, wy)
    ti = ((X / 256.0 % 1.0) * 512).astype(int)
    tj = ((Y / 256.0 % 1.0) * 512).astype(int)
    pa, pb = a[tj, ti].astype(np.float32), b[tj, ti].astype(np.float32)

    def samp(img, u, v):
        n = img.shape[0]
        return img[(v % 1.0 * n).astype(int) % n, (u % 1.0 * n).astype(int) % n]
    m = samp(patch, X / 1291.0 + 0.11, Y / 1291.0 + 0.53) * 0.65 + samp(patch, Y / 433.0 + 0.7, X / 433.0 + 0.2) * 0.35
    m = m + (pa.mean(2) / 255.0 - a.mean() / 255.0) * 0.35
    t = (m > 0.56)[..., None]
    rim = 1.0 - np.clip(np.abs(m - 0.56) / 0.018, 0, 1)
    c = np.where(t, pb, pa) * (1.0 - 0.35 * rim[..., None])
    c = c * (0.78 + 0.34 * samp(blotch, X / 1777.0 + 0.31, Y / 1777.0 + 0.17))[..., None]
    return Image.fromarray(np.clip(c, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def hero():
    strip = Image.open(ART / "hero_human_knight_walk.png").convert("RGBA")
    return strip.crop((0, 0, strip.width // 8, strip.height))


def pic(name, k):
    im = Image.open(ART / ("ui_town_%s.png" % name)).convert("RGBA")
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.NEAREST)


def compose(x0, y0, w, h, scale, labels=True, heroes=()):
    """w x h in preview px."""
    img = ground(x0, y0, w, h, scale)
    d = ImageDraw.Draw(img, "RGBA")

    def to(p):
        return ((p[0] - x0) * scale, (p[1] - y0) * scale)
    cx, cy = to(CENTRE)
    r = PLAZA_R * scale
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(0, 0, 0, 128), width=max(2, round(4 * scale)))
    items = []
    for sid, name, ax, ay in stations():
        if (ART / ("ui_town_%s.png" % sid)).exists():
            items.append((ay + PIC_BASE, sid, name, ax))
    items.append((CENTRE[1] + HEARTH_BASE, "hearth", "", CENTRE[0]))
    items.sort()
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for rr, al in ((150, 14), (95, 16)):
        gd.ellipse((cx - rr * scale, cy - rr * scale, cx + rr * scale, cy + rr * scale), fill=(230, 128, 26, al))
    img.alpha_composite(glow)
    for base, sid, name, ax in items:
        im = pic(sid, PIC_K * scale)
        px, py = to((ax, base))
        img.alpha_composite(im, (round(px - im.width / 2), round(py - im.height)))
        if labels and sid != "hearth":
            d.text((px - 4 * len(name), py - im.height - 14), name, fill=(214, 190, 120, 255))
    hs = hero()
    hk = HERO_BOX / 142.0 * scale
    hi = hs.resize((round(hs.width * hk), round(hs.height * hk)), Image.NEAREST)
    for hx, hy in heroes:
        px, py = to((hx, hy))
        img.alpha_composite(hi, (round(px - hi.width / 2), round(py - hi.height + 3 * scale)))
    return img


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "work_review"
    out.mkdir(parents=True, exist_ok=True)
    sm = [s for s in stations() if s[0] == "smith"][0]
    tr = [s for s in stations() if s[0] == "trainer"][0]
    whole = compose(1000, 1100, 1050, 900, 0.5, heroes=[(sm[2] - 90, sm[3] + 110), (tr[2] + 140, tr[3] + 120)])
    whole.convert("RGB").save(out / "town_preview.png")
    s = ZOOM * 1.5
    w, h = 1440, 810
    x0, y0 = sm[2] - w / s / 2, sm[3] - h / s / 2 - 20
    crop = compose(x0, y0, w, h, s, heroes=[(sm[2] - 70, sm[3] + 95), (sm[2] + 30, sm[3] + 120)])
    crop.convert("RGB").save(out / "town_preview_smith.png")
    print("ok", out)


if __name__ == "__main__":
    main()

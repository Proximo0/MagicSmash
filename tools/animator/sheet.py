"""Contact sheet: per sample, the old 4-frame strip above and the new 8-frame walk below
(2x), with the gate result; written to out/contact.png."""
import os

import numpy as np
from PIL import Image, ImageDraw

from .bake import BODY_H, CANVAS_H, CANVAS_W, FOOT_Y, SS
from .cut import load_rgba, split_strip, frame_of

BG = (52, 70, 52)


def _on_bg(a, scale):
    im = Image.new("RGBA", (a.shape[1], a.shape[0]), BG + (255,))
    im.alpha_composite(Image.fromarray(a, "RGBA"))
    return im.resize((a.shape[1] * scale, a.shape[0] * scale), Image.NEAREST)


def contact_sheet(entries, path, scale=2):
    """entries: list of (name, still_png_path, frames(list of rgba), result text)."""
    rows = []
    for name, src, frames, text in entries:
        img = load_rgba(src)
        old = [frame_of(img, s) for s in split_strip(img)]
        h = max(f.shape[0] for f in old)
        oldstrip = np.zeros((h, sum(f.shape[1] + 8 for f in old), 4), np.uint8)
        x = 0
        for f in old:
            oldstrip[h - f.shape[0]:, x:x + f.shape[1]] = f
            x += f.shape[1] + 8
        new = np.concatenate([f["rgba"] for f in frames], 1)
        a = _on_bg(oldstrip, 1)
        b = _on_bg(new, scale)
        d = ImageDraw.Draw(b)
        for i in range(1, len(frames)):
            d.line([(i * CANVAS_W * scale, 0), (i * CANVAS_W * scale, b.height)], fill=(40, 56, 40))
        d.line([(0, FOOT_Y * scale), (b.width, FOOT_Y * scale)], fill=(90, 60, 60))
        W = max(a.width, b.width)
        row = Image.new("RGBA", (W, 18 + a.height + 4 + b.height + 10), (24, 24, 24, 255))
        ImageDraw.Draw(row).text((4, 3), f"{name}: {text}", fill=(230, 230, 230)
                                 if text.startswith("checks ok") else (255, 120, 120))
        row.paste(a, (0, 18))
        row.paste(b, (0, 18 + a.height + 4))
        rows.append(row)
    W = max(r.width for r in rows)
    sheet = Image.new("RGBA", (W, sum(r.height for r in rows)), (24, 24, 24, 255))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    sheet.save(path)
    return path

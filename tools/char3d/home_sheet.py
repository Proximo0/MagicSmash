#!/usr/bin/env python3
"""Every home picture (ui_home_*.png) at 2x on the house floor's colour, with a hero for scale and a 128 px cell (the
size a cell has in the world, in picture pixels) outlined under each.
    python3 -I home_sheet.py <art dir> <out png>"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

art, out = Path(sys.argv[1]), Path(sys.argv[2])
FLOOR = (51, 36, 23)
CELL = round(128 / (64.0 / 142.0))     # a cell in picture px (PIC_K = HERO_BOX / 142)
names = sorted(p.stem[3:] for p in art.glob("ui_home_*.png"))
strip = Path(__file__).resolve().parents[2] / "realm/client/art/hero_human_knight_walk.png"
hero = None
if strip.exists():
    sp = Image.open(strip).convert("RGBA")
    hero = sp.crop((0, 0, sp.width // 8, sp.height))
S, COLS, CW, CH = 2, 5, 230, 270
rows = (len(names) + 1 + COLS - 1) // COLS
sheet = Image.new("RGB", (COLS * CW, rows * CH), FLOOR)
d = ImageDraw.Draw(sheet)
items = [("hero", hero)] + [(n, Image.open(art / ("ui_%s.png" % n)).convert("RGBA")) for n in names]
for i, (n, im) in enumerate(items):
    cx, cy = (i % COLS) * CW + CW // 2, (i // COLS) * CH + CH - 20
    d.rectangle([cx - CELL * S // 2, cy - CELL * S // 4, cx + CELL * S // 2, cy + CELL * S // 4], outline=(90, 66, 40))
    if im is not None:
        im = im.resize((im.width * S, im.height * S), Image.NEAREST)
        sheet.paste(im, (cx - im.width // 2, cy - im.height), im)
    d.text((cx - CW // 2 + 6, cy + 14), n, fill=(210, 200, 170))
sheet.save(out)
print(out, sheet.size)

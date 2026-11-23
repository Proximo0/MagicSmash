#!/usr/bin/env python3
"""Generic 2x contact sheet: every png given, nearest-neighbour, one row per file, on the game's grey-green.
    python3 -I strips_sheet.py <out png> <png> [png ...]      (a strip is shown whole; wider than 4096 px is cut at 2x)
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

out, files = sys.argv[1], [Path(f) for f in sys.argv[2:]]
BG, S, GAP, LAB = (74, 80, 74, 255), 2, 4, 14
ims = [Image.open(f).convert("RGBA") for f in files]
if not ims:
    sys.exit("no pictures")
W = min(max(i.width for i in ims) * S, 4096)
sheet = Image.new("RGBA", (W, sum(i.height * S + LAB + GAP for i in ims)), BG)
d = ImageDraw.Draw(sheet)
y = 0
for f, im in zip(files, ims):
    d.text((2, y), f.stem, fill=(230, 230, 230, 255))
    sheet.alpha_composite(im.resize((im.width * S, im.height * S), Image.NEAREST).crop((0, 0, W, im.height * S)), (0, y + LAB))
    y += im.height * S + LAB + GAP
sheet.convert("RGB").save(out)
print("sheet", len(ims), "pictures", sheet.size)

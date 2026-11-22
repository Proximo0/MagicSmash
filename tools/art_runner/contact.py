"""Contact sheet of finished ids: one row per id (its 4 pictures), labelled. Usage: contact.py out.png [first_n] [skip]"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw
R = Path(r"D:\projects\hh_art")
ids = (R / "done.txt").read_text(encoding="utf-8").split()
skip = int(sys.argv[3]) if len(sys.argv) > 3 else 0
n = int(sys.argv[2]) if len(sys.argv) > 2 else len(ids)
ids = ids[skip:skip + n]
TW, TH, LB = 300, 172, 120
sheet = Image.new("RGB", (LB + 4 * TW, len(ids) * TH), (30, 30, 30)); d = ImageDraw.Draw(sheet)
for r, i in enumerate(ids):
    d.text((6, r * TH + 6), i, fill="white")
    for k in range(1, 5):
        f = R / "raw" / f"{i}_{k}.png"
        if not f.exists(): continue
        im = Image.open(f); im.thumbnail((TW - 4, TH - 4), Image.NEAREST)
        sheet.paste(im, (LB + (k - 1) * TW + 2, r * TH + 2))
sheet.save(sys.argv[1]); print(len(ids), "ids")

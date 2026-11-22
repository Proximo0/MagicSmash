"""Hand-made fixtures: the accepted paladin still HR6.1 split into a bare body + gear pictures.

HR6.1 (samples/stills_spec) was drawn with its shield on the back and a hammer in the near
hand.  `split_hr61` cuts both out with the hand-placed masks below and writes the character in
the body + gear format (STILL_SPEC.md):
    <out>/HR6.1_SPLIT.png, HR6.1_SPLIT.json, HR6.1_SPLIT_gear/{shield,hammer}.{png,json}
The body keeps its closed fist (the hammer's haft ran through it); the part of the shield that
the body hid is missing from the shield picture and stays hidden behind the torso; the haft
inside the fist is drawn in (a straight bar in the haft's own colours).
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw

from helpers import ROOT

SRC = os.path.join(ROOT, "tools", "animator", "samples", "stills_spec", "HR6.1")
# the shield's side of its edge against the body (outer edge of its outline), then round the
# background
SHIELD = [(126, 99), (150, 119), (183, 147), (181, 160), (169, 197), (154, 233), (141, 262),
          (129, 285), (122, 302), (58, 302), (58, 99)]
SHIELD_CENTRE = (135, 195)
HAMMER = [(282, 190), (345, 190), (345, 268), (282, 268)]      # head and haft ahead of the fist
POMMEL = [(232, 234), (249, 234), (249, 251), (232, 251)]      # the haft's end behind the fist
GRIP = (265, 238)                                              # middle of the fist
HAFT = ((247, 241.5), (284, 234.5))                            # the haft's axis through the fist
HAFT_COLOURS = ((10, 8, 8, 255), (96, 40, 18, 255))            # outline, wood (read off the haft)


def _mask(size, poly):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    return np.array(m) > 0


def split_hr61(out_dir, cid="HR6.1_SPLIT"):
    from tools.animator.fit import load_single
    img = load_single(SRC + ".png")
    H, W = img.shape[:2]
    op = img[..., 3] > 0
    sh = _mask((W, H), SHIELD) & op
    hm = _mask((W, H), HAMMER) & op
    pm = _mask((W, H), POMMEL) & op
    body = img.copy()
    body[sh | hm | pm] = 0
    gdir = os.path.join(out_dir, cid + "_gear")
    os.makedirs(gdir, exist_ok=True)
    Image.fromarray(body, "RGBA").save(os.path.join(out_dir, cid + ".png"))
    with open(SRC + ".json") as f:
        lay = json.load(f)
    lay.update(id=cid, name=cid, format="body")
    with open(os.path.join(out_dir, cid + ".json"), "w") as f:
        json.dump(lay, f, indent=1)

    def crop(mask, src):
        ys, xs = np.where(mask)
        x0, y0 = int(xs.min()) - 2, int(ys.min()) - 2
        out = np.zeros((int(ys.max()) + 3 - y0, int(xs.max()) + 3 - x0, 4), np.uint8)
        sub = src[y0:y0 + out.shape[0], x0:x0 + out.shape[1]]
        m = mask[y0:y0 + out.shape[0], x0:x0 + out.shape[1]]
        out[m] = sub[m]
        return out, (x0, y0)

    bh = float(lay["body_height"])
    # shield: kept at the angle it was drawn (up = picture up), pinned where it was
    pic, (x0, y0) = crop(sh, img)
    Image.fromarray(pic, "RGBA").save(os.path.join(gdir, "shield.png"))
    ys = np.flatnonzero(sh.any(1))
    with open(os.path.join(gdir, "shield.json"), "w") as f:
        json.dump({"slot": "back", "anchor": [SHIELD_CENTRE[0] - x0, SHIELD_CENTRE[1] - y0], "up": [0, -1],
                   "size": round((ys.max() - ys.min() + 1) / bh, 3), "at": [0.40, 0.105]}, f, indent=1)
    # hammer: head + haft, the haft drawn through where the fist was, the pommel put back
    full = np.zeros_like(img)
    bar = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(bar)
    d.line(HAFT, fill=HAFT_COLOURS[0], width=12)
    d.line(HAFT, fill=HAFT_COLOURS[1], width=7)
    bar = np.array(bar)
    full[bar[..., 3] > 0] = bar[bar[..., 3] > 0]
    full[hm | pm] = img[hm | pm]
    pic, (x0, y0) = crop(full[..., 3] > 0, full)
    Image.fromarray(pic, "RGBA").save(os.path.join(gdir, "hammer.png"))
    up = np.array(HAFT[1]) - np.array(HAFT[0])
    up = up / np.hypot(*up)
    ys, xs = np.where(full[..., 3] > 0)
    t = (xs - GRIP[0]) * up[0] + (ys - GRIP[1]) * up[1]
    with open(os.path.join(gdir, "hammer.json"), "w") as f:
        json.dump({"slot": "near_hand", "anchor": [GRIP[0] - x0, GRIP[1] - y0],
                   "up": [round(float(up[0]), 4), round(float(up[1]), 4)],
                   "size": round(float(t.max() - t.min() + 1) / bh, 3), "angle": 49.0, "in_front": False},
                  f, indent=1)
    return os.path.join(out_dir, cid + ".png")


if __name__ == "__main__":
    import sys
    print(split_hr61(sys.argv[1]))

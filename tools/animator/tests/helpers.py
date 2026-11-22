"""A synthetic side-view character (with a shield in the hand) for fast tests."""
import json
import os
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

JOINTS = {
    "head_top": [40, 2], "neck": [40, 28], "pelvis": [40, 80],
    "shoulder": [40, 40], "elbow": [44, 58], "wrist": [54, 68], "hand_tip": [58, 71],
    "hip": [40, 84], "knee": [50, 102], "ankle": [60, 116], "heel": [58, 125], "toe": [74, 122],
}
FAR = {"hip": [33, 84], "knee": [22, 102], "ankle": [10, 115], "heel": [4, 118], "toe": [16, 125]}
SHIELD = [[52, 60], [66, 60], [66, 76], [59, 84], [52, 76]]


def make_still():
    im = Image.new("RGBA", (84, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    J = JOINTS
    line = lambda a, b, w, c: d.line([tuple(a), tuple(b)], fill=c, width=w)
    # far leg (will be erased and redrawn as a dark copy)
    line(FAR["hip"], FAR["knee"], 11, (40, 40, 60, 255))
    line(FAR["knee"], FAR["ankle"], 9, (40, 40, 60, 255))
    line(FAR["heel"], FAR["toe"], 6, (90, 50, 30, 255))
    # torso + head
    d.polygon([(28, 30), (52, 30), (54, 84), (26, 84)], fill=(120, 30, 30, 255))
    d.ellipse([28, 2, 52, 28], fill=(220, 170, 130, 255))
    # near leg
    line(J["hip"], J["knee"], 11, (60, 60, 90, 255))
    line(J["knee"], J["ankle"], 9, (60, 60, 90, 255))
    line(J["heel"], J["toe"], 6, (120, 70, 40, 255))
    # near arm
    line(J["shoulder"], J["elbow"], 8, (150, 150, 160, 255))
    line(J["elbow"], J["wrist"], 7, (230, 180, 140, 255))
    d.polygon([tuple(p) for p in SHIELD], fill=(200, 170, 40, 255), outline=(20, 20, 20, 255))
    a = np.array(im)
    strip = np.zeros((128, 84 * 4 + 30, 4), np.uint8)
    for i in range(4):
        strip[:, i * (84 + 10):i * (84 + 10) + 84] = a
    return strip


def make_files(tmp=None):
    tmp = tmp or tempfile.mkdtemp(prefix="anim_test_")
    png = os.path.join(tmp, "SYN.png")
    Image.fromarray(make_still(), "RGBA").save(png)
    data = {"name": "SYN", "frame": 0, "ground_y": 127, "joints": JOINTS, "far": FAR,
            "gear": [{"name": "shield", "attach": "hand", "poly": SHIELD}],
            "radius": {"upper": 4.5, "fore": 4.0, "thigh": 6.0, "shin": 5.0, "foot": 4.0}}
    js = os.path.join(tmp, "SYN.json")
    with open(js, "w") as f:
        json.dump(data, f)
    return png, js, tmp

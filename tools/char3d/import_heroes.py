#!/usr/bin/env python3
"""Import the 24 char3d hero strips into the client's art folder.

usage: import_heroes.py <heroes24 dir> <realm/client/art dir>

Per hero one crop box is shared by every frame of every action: symmetric about the body centre (so the client,
which centres a frame on x, keeps the body under the hero's position) and ending 1 px under the lowest opaque
pixel (the client puts the frame's bottom edge on the feet). Nearest-neighbour only: it is a plain crop.
Writes <key>_walk.png/.json, _atk.png, _hit.png, _die.png and a still <key>.png (first idle frame).
"""
import json
import sys
from pathlib import Path

from PIL import Image

RACES = ["human", "elf", "dwarf", "orc"]
CLASSES = ["novice", "knight", "mage", "archer", "priest", "paladin"]
FRAME = 144
SKIP = {"idle", "walking_a", "hit_a", "death_a", "block_hit"}
# The old human knight was drawn 28 world px tall (56 texture px at scale 0.5): a human is this many opaque
# px tall in the new sets (measured from hero_human_knight idle), so scale = 28 / that.
OLD_WORLD_H = 28.0
PAD = 1


def frames_of(img: Image.Image):
    n = img.width // FRAME
    return [img.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(n)]


def load_hero(src: Path, key: str):
    acts = {}
    for p in src.glob(key + "_*.png"):
        acts[p.stem[len(key) + 1:]] = frames_of(Image.open(p).convert("RGBA"))
    atk = [a for a in acts if a not in SKIP]
    if len(atk) != 1:
        raise SystemExit("%s: expected one attack action, found %s" % (key, atk))
    return acts, atk[0]


def box_of(acts, keep):
    """(x0, x1, y0, y1) shared by all frames; the body centre is the middle of the walk and idle frames' extents."""
    mids = []
    for a in ("idle", "walking_a"):
        for f in acts[a]:
            b = f.getchannel("A").getbbox()
            if b:
                mids.append((b[0] + b[2]) / 2.0)
    centre = sorted(mids)[len(mids) // 2]
    half, bottom, top = 0.0, 0, FRAME
    for a in keep:
        for f in acts[a]:
            b = f.getchannel("A").getbbox()
            if b:
                half = max(half, centre - b[0], b[2] - centre)
                bottom = max(bottom, b[3])
                top = min(top, b[1])
    half = int(half + 0.999) + PAD
    c = int(round(centre))
    return c - half, c + half, max(top - PAD, 0), min(bottom + PAD, FRAME)


def strip(frames, x0, x1, y0, y1):
    out = Image.new("RGBA", ((x1 - x0) * len(frames), y1 - y0))
    for i, f in enumerate(frames):
        out.paste(f.crop((x0, y0, x1, y1)), (i * (x1 - x0), 0))
    return out


def height(src: Path, key: str) -> int:
    f = Image.open(src / (key + "_idle.png")).convert("RGBA").crop((0, 0, FRAME, FRAME))
    b = f.getchannel("A").getbbox()
    return b[3] - b[1]


def main(argv):
    src, dst = Path(argv[1]), Path(argv[2])
    scale = round(OLD_WORLD_H / height(src, "hero_human_knight"), 4)
    print("scale %s (human knight idle is %d px tall)" % (scale, height(src, "hero_human_knight")))
    for race in RACES:
        for cls in CLASSES:
            key = "hero_%s_%s" % (race, cls)
            acts, atk = load_hero(src, key)
            keep = ["idle", "walking_a", atk, "hit_a", "death_a"]
            x0, x1, y0, y1 = box_of(acts, keep)
            out = {"walk": "walking_a", "atk": atk, "hit": "hit_a", "die": "death_a"}
            for name, act in out.items():
                strip(acts[act], x0, x1, y0, y1).save(dst / ("%s_%s.png" % (key, name)))
            strip(acts["idle"][:1], x0, x1, y0, y1).save(dst / (key + ".png"))
            side = {"frames": len(acts["walking_a"]), "fps": 12, "scale": scale,
                    "atk_frames": len(acts[atk]), "hit_frames": len(acts["hit_a"]), "die_frames": len(acts["death_a"])}
            (dst / (key + "_walk.json")).write_text(json.dumps(side) + "\n")
            print(key, "frame %dx%d" % (x1 - x0, y1 - y0), atk)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv)

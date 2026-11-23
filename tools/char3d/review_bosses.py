#!/usr/bin/env python3
"""2x contact sheets and edge checks of the imported boss strips.

usage: review_bosses.py <realm/client/art dir> <out dir> [slug ...]
Writes boss_<slug>_{walk,atk,hit,die}_2x.png and bosses_walk_2x.png; prints, per boss and strip, the frame size, any
opaque pixel on a frame's border, and for the die strip the last frame's size (it must lie flat on the ground).
"""
import json
import sys
from pathlib import Path

from PIL import Image

SLUGS = ["harvester", "hanging_tree", "mother_of_leeches", "goat_prophet"]
BG = (74, 80, 74, 255)


def frames(path: Path, n: int):
    im = Image.open(path).convert("RGBA")
    w = im.width // n
    return [im.crop((i * w, 0, (i + 1) * w, im.height)) for i in range(n)]


def sheet(fr, scale=2, gap=2):
    w, h = fr[0].size
    out = Image.new("RGBA", (len(fr) * (w * scale + gap), h * scale), BG)
    for i, f in enumerate(fr):
        out.alpha_composite(f.resize((w * scale, h * scale), Image.NEAREST), (i * (w * scale + gap), 0))
    return out


def main(argv):
    art, out = Path(argv[1]), Path(argv[2])
    out.mkdir(parents=True, exist_ok=True)
    slugs = argv[3:] or SLUGS
    walks = []
    for slug in slugs:
        key = "boss_" + slug
        side = json.loads((art / (key + "_walk.json")).read_text())
        for act in ("walk", "atk", "hit", "die"):
            n = side["frames"] if act == "walk" else side[act + "_frames"]
            fr = frames(art / ("%s_%s.png" % (key, act)), n)
            sheet(fr).convert("RGB").save(out / ("%s_%s_2x.png" % (key, act)))
            bad = [i for i, f in enumerate(fr) if any(
                f.getchannel("A").crop(b).getbbox() for b in ((0, 0, f.width, 1), (0, f.height - 1, f.width, f.height), (0, 0, 1, f.height), (f.width - 1, 0, f.width, f.height)))]
            msg = "%s %s: %d frames of %dx%d, border pixels in frames %s" % (key, act, n, fr[0].width, fr[0].height, bad or "none")
            if act == "die":
                bb = fr[-1].getchannel("A").getbbox()
                msg += "; last frame %dx%d (bottom %d of %d)" % (bb[2] - bb[0], bb[3] - bb[1], bb[3], fr[-1].height)
            print(msg)
            if act == "walk":
                walks.append(sheet(fr))
    if walks:
        wd = max(s.width for s in walks)
        allw = Image.new("RGBA", (wd, sum(s.height for s in walks)), BG)
        y = 0
        for s in walks:
            allw.alpha_composite(s, (0, y))
            y += s.height
        allw.convert("RGB").save(out / "bosses_walk_2x.png")


if __name__ == "__main__":
    main(sys.argv)

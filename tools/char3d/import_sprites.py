#!/usr/bin/env python3
"""Import char3d sprite sets (24 heroes or 10 monsters) into the client's art folder.

usage: import_sprites.py heroes   <heroes24 dir>  <realm/client/art dir>
       import_sprites.py monsters <monsters dir>  <realm/client/art dir>

Monsters are enemy_<name>_<action>.png: the walk action is any walking_*, the attack the one action that is not idle,
walking_*, hit_a or death_*, the death any death_*. A key listed in <art dir>/locked.txt is skipped.

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
MONSTER_SCALE = 0.4667  # rendered at the heroes' px per metre
# The old human knight was drawn 28 world px tall (56 texture px at scale 0.5): a human is this many opaque
# px tall in the new sets (measured from hero_human_knight idle), so scale = 28 / that.
OLD_WORLD_H = 28.0
PAD = 1


def frames_of(img: Image.Image):
    n = img.width // FRAME
    return [img.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(n)]


def load_actions(src: Path, key: str):
    """({action: frames}, {"walk": .., "atk": .., "hit": "hit_a", "die": ..}) for one character."""
    acts = {}
    for p in src.glob(key + "_*.png"):
        acts[p.stem[len(key) + 1:].lower()] = frames_of(Image.open(p).convert("RGBA"))
    walk = [a for a in acts if a.startswith("walking_")]
    die = [a for a in acts if a.startswith("death_")]
    atk = [a for a in acts if a not in ("idle", "hit_a", "block_hit") and a not in walk and a not in die]
    if len(atk) != 1 or len(walk) != 1 or len(die) != 1 or "idle" not in acts or "hit_a" not in acts:
        raise SystemExit("%s: need idle, hit_a, one walking_*, one death_*, one attack; found %s" % (key, sorted(acts)))
    return acts, {"walk": walk[0], "atk": atk[0], "hit": "hit_a", "die": die[0]}


def locked(dst: Path):
    f = dst / "locked.txt"
    if not f.exists():
        return set()
    return {l.strip() for l in f.read_text().splitlines() if l.strip() and not l.startswith("#")}


def box_of(acts, keep, walk):
    """(x0, x1, y0, y1) shared by all frames; the body centre is the middle of the walk and idle frames' extents."""
    mids = []
    for a in ("idle", walk):
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


# Kinds that float: world px they are drawn above their spot (the shader sways them there, figures.gdshader).
HOVER = {"enemy_carrion_crow": 12, "enemy_cliff_harpy": 10, "enemy_hollow_angel": 8, "enemy_marsh_light": 8,
         "enemy_void_eye": 10, "enemy_wisp": 8}


def import_one(src: Path, dst: Path, key: str, scale: float):
    acts, out = load_actions(src, key)
    x0, x1, y0, y1 = box_of(acts, ["idle", out["walk"], out["atk"], out["hit"], out["die"]], out["walk"])
    for name, act in out.items():
        strip(acts[act], x0, x1, y0, y1).save(dst / ("%s_%s.png" % (key, name)))
    strip(acts["idle"][:1], x0, x1, y0, y1).save(dst / (key + ".png"))
    side = {"frames": len(acts[out["walk"]]), "fps": 12, "scale": scale, "atk_frames": len(acts[out["atk"]]),
            "hit_frames": len(acts[out["hit"]]), "die_frames": len(acts[out["die"]])}
    if key in HOVER:
        side["hover"] = HOVER[key]
    (dst / (key + "_walk.json")).write_text(json.dumps(side) + "\n")
    print(key, "frame %dx%d" % (x1 - x0, y1 - y0), out["atk"], "walk strip %d px" % ((x1 - x0) * side["frames"]))


def main(argv):
    if len(argv) != 4 or argv[1] not in ("heroes", "monsters"):
        raise SystemExit(__doc__)
    src, dst = Path(argv[2]), Path(argv[3])
    lock = locked(dst)
    if argv[1] == "heroes":
        scale = round(OLD_WORLD_H / height(src, "hero_human_knight"), 4)
        print("scale %s (human knight idle is %d px tall)" % (scale, height(src, "hero_human_knight")))
        keys = ["hero_%s_%s" % (r, c) for r in RACES for c in CLASSES]
    else:
        scale = MONSTER_SCALE
        keys = sorted(p.stem for p in src.glob("enemy_*.json"))  # every monster in the folder
    for key in keys:
        if key in lock:
            print(key, "locked: skipped")
        else:
            import_one(src, dst, key, scale)


if __name__ == "__main__":
    main(sys.argv)

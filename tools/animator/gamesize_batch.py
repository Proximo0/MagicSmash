"""Game-size walk batch: every hero fixture in a directory through the whole gate, client files for the accepted.

    python3 -m tools.animator.gamesize_batch --stills <dir> --out <dir> [--only HR2.1,HR3.2]

Fixture format (what tools/animator/samples/round5/ and art-raw stills_gear/round7/ use):
    <ID>.png            the still, magenta already keyed (transparent), facing right
    <ID>.json           joints and metadata; "build" is the race (human|elf|dwarf|orc)
    <ID>_gear/          optional: one <name>.png + <name>.json per gear piece (dirk, greatsword, mage_staff, candle_staff,
                        bow, quiver, hammer, shield ...)
Written to --out:
    client/hero_<race>_<class>_walk.png   8 frames of 56 px side by side, each W x H, centre = pelvis column,
    client/hero_<race>_<class>_walk.json  last row = ground row   {"frames": 8, "fps": 16, "scale": 0.5}
    sheets/<id>_<race>_<class>.png        per-hero contact sheet, 8 frames at 4x (accepted and refused alike)
    overview.png                          every hero, frame 0 and frame 4 at 4x
    results.json                          per hero: pass/fail, every gate value, seconds, names and where they came from
A refused hero gets a sheet (to see why) and a line in results.json, never client files.

Race and class names: race = the fixture json's "build"; class = the json's "class" if it has one, else the class
named by its gear (dirk novice, greatsword knight, mage_staff mage, candle_staff priest, bow archer, hammer paladin;
the gear list in STILL_SPEC.md), else the row of an `HR<row>.<column>` id (1 novice, 2 knight, 3 mage, 4 archer,
5 priest, 6 paladin; the row is the class on every fixture set, the column the race: 1 human, 2 elf, 3 dwarf, 4 orc).
A json "name" of the form hero_<race>_<class> wins over all of these.
"""
import argparse
import glob
import json
import os
import re
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

from . import gamesize as gs

RACES = ("human", "elf", "dwarf", "orc")
COLUMN_RACE = {1: "human", 2: "elf", 3: "dwarf", 4: "orc"}
# rows 7 to 16 are the jobs, as the art runner's queue names them (tools/art_runner/queue.json, branch art-pipeline)
ROW_CLASS = {1: "novice", 2: "knight", 3: "mage", 4: "archer", 5: "priest", 6: "paladin", 7: "warden", 8: "berserker",
             9: "archmage", 10: "hexer", 11: "ranger", 12: "sharpshooter", 13: "oracle", 14: "inquisitor", 15: "templar",
             16: "crusader"}
GEAR_CLASS = (("hammer", "paladin"), ("candle_staff", "priest"), ("mage_staff", "mage"), ("bow", "archer"),
              ("greatsword", "knight"), ("dirk", "novice"))
BG = (90, 110, 90, 255)
FPS, SCALE = 16, 0.5


def find_heroes(stills):
    """[(id, png, json)] for every <ID>.png with an <ID>.json next to it, sorted by id."""
    out = []
    for png in sorted(glob.glob(os.path.join(stills, "*.png"))):
        js = png[:-4] + ".json"
        if os.path.exists(js):
            out.append((os.path.basename(png)[:-4], png, js))
    return out


def hero_names(hid, png, js):
    """(race, class, where the two names came from)."""
    with open(js) as f:
        meta = json.load(f)
    race = cls = None
    src = []
    m = re.match(r"^hero_([a-z]+)_([a-z]+)$", str(meta.get("name", "")))
    if m and m.group(1) in RACES:
        race, cls = m.group(1), m.group(2)
        src = ["json name"]
    if race is None and meta.get("build") in RACES:
        race = meta["build"]
        src.append("json build")
    row = col = None
    m = re.match(r"^HR(\d+)\.(\d+)", hid)
    if m:
        row, col = int(m.group(1)), int(m.group(2))
    if race is None and col in COLUMN_RACE:
        race = COLUMN_RACE[col]
        src.append("id column")
    if cls is None and meta.get("class"):
        cls = str(meta["class"])
        src.append("json class")
    if cls is None:
        gear = os.path.join(os.path.dirname(png), hid + "_gear")
        have = {os.path.basename(p)[:-4] for p in glob.glob(os.path.join(gear, "*.png"))}
        for g_, c_ in GEAR_CLASS:
            if g_ in have:
                cls = c_
                src.append("gear " + g_)
                break
    if cls is None and row in ROW_CLASS:
        cls = ROW_CLASS[row]
        src.append("id row")
    return race or "unknown", cls or "unknown", " + ".join(src) or "none"


def client_strip(fs, frames=range(8)):
    """RGBA strip of the frames, each w x h: centre column = the pelvis column, last row = the ground row, one crop for all."""
    fr = [fs.frames[i]["idx"] for i in frames]
    m = np.any([f >= 0 for f in fr], 0)
    ys, xs = np.nonzero(m)
    half = max(fs.pel_x - xs.min(), xs.max() + 1 - fs.pel_x)
    w, top = 2 * half, ys.min()
    h = fs.foot_y - top
    strip = np.zeros((h, w * len(fr), 4), np.uint8)
    for n, i in enumerate(frames):
        strip[:, n * w:(n + 1) * w] = fs.rgba(i)[top:fs.foot_y, fs.pel_x - half:fs.pel_x + half]
    return strip, w, h


def _tile(rgba, scale):
    im = Image.new("RGBA", (rgba.shape[1], rgba.shape[0]), BG)
    im.alpha_composite(Image.fromarray(rgba))
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)


def contact_sheet(fs, label, path, scale=4):
    strip, w, h = client_strip(fs)
    tiles = [_tile(strip[:, i * w:(i + 1) * w], scale) for i in range(8)]
    sheet = Image.new("RGB", (tiles[0].width * 8 + 4 * 7, tiles[0].height + 14), (30, 30, 30))
    for i, t in enumerate(tiles):
        sheet.paste(t.convert("RGB"), (i * (t.width + 4), 14))
    ImageDraw.Draw(sheet).text((4, 1), label, fill=(255, 255, 255))
    sheet.save(path)


def overview(items, path, cols=4, scale=4):
    """items: [(label, FrameSet)] -> one sheet, frame 0 and frame 4 of each at 4x."""
    cells = []
    for label, fs in items:
        strip, w, h = client_strip(fs)
        cells.append((label, [_tile(strip[:, i * w:(i + 1) * w], scale).convert("RGB") for i in (0, 4)]))
    cw = max(sum(t.width for t in ts) + 4 for _, ts in cells)
    ch = max(t.height for _, ts in cells for t in ts) + 14
    rows = -(-len(cells) // cols)
    sheet = Image.new("RGB", (cols * (cw + 6), rows * (ch + 6)), (30, 30, 30))
    d = ImageDraw.Draw(sheet)
    for n, (label, ts) in enumerate(cells):
        x0, y0 = (n % cols) * (cw + 6), (n // cols) * (ch + 6)
        d.text((x0 + 2, y0), label, fill=(255, 255, 255))
        x = x0
        for t in ts:
            sheet.paste(t, (x, y0 + 14))
            x += t.width + 4
    sheet.save(path)


def _plain(v):
    return v.item() if isinstance(v, (np.integer, np.floating)) else str(v)


def run_one(hid, png, js, out):
    """Bake and gate one hero; write its sheet and, when accepted, its client files.  Returns (result dict, FrameSet or None)."""
    race, cls, src = hero_names(hid, png, js)
    res = {"id": hid, "race": race, "class": cls, "names_from": src, "name": "hero_%s_%s" % (race, cls)}
    t0 = time.time()
    fs = None
    try:
        fs, hero, _ = gs.bake_game_size(png, js)
        gates = gs.run_gates(fs)
        res["gates"] = {k: {"ok": bool(v[0]), "value": v[1] if not isinstance(v[1], (np.integer, np.floating)) else v[1].item()}
                        for k, v in gates.items()}
        res["refused_by"] = [k for k, v in gates.items() if not v[0]]
        res["walk"] = {"stride_px": fs.walk["stride"], "arms_expected": fs.still_arms, "carry": fs.prop_info}
        if race == "unknown" or cls == "unknown":
            res["refused_by"].append("names (no race or class could be read)")
    except Exception as e:                      # a still the fit cannot read is a refusal, with the reason
        res["refused_by"] = ["bake_error: %s: %s" % (type(e).__name__, str(e)[:160])]
    res["seconds"] = round(time.time() - t0, 2)
    res["pass"] = not res["refused_by"]
    if fs is not None:
        os.makedirs(os.path.join(out, "sheets"), exist_ok=True)
        tag = "OK" if res["pass"] else "REFUSED"
        contact_sheet(fs, "%s %s_%s %s %s" % (hid, race, cls, tag, ",".join(res["refused_by"])),
                      os.path.join(out, "sheets", "%s_%s_%s.png" % (hid, race, cls)))
    return res, fs


def run(stills, out, only=None):
    heroes = find_heroes(stills)
    if only:
        heroes = [h for h in heroes if h[0] in only]
    os.makedirs(os.path.join(out, "client"), exist_ok=True)
    results, overview_items, taken = [], [], {}
    t_all = time.time()
    for hid, png, js in heroes:
        res, fs = run_one(hid, png, js, out)
        if res["pass"]:
            name = res["name"]
            if name in taken:                       # never overwrite another hero's client files
                res["pass"] = False
                res["refused_by"].append("name_collision with %s" % taken[name])
            else:
                taken[name] = hid
                strip, w, h = client_strip(fs)
                Image.fromarray(strip).save(os.path.join(out, "client", name + "_walk.png"))
                with open(os.path.join(out, "client", name + "_walk.json"), "w") as f:
                    json.dump({"frames": 8, "fps": FPS, "scale": SCALE}, f)
                res["client"] = {"png": "client/%s_walk.png" % name, "frame_px": [w, h]}
        if fs is not None:
            overview_items.append(("%s %s %s%s" % (hid, res["race"], res["class"], "" if res["pass"] else " REFUSED"), fs))
        results.append(res)
        print("%-8s %-14s %-8s %5.1fs %s" % (hid, res["race"] + "_" + res["class"], "ok" if res["pass"] else "REFUSED",
                                            res["seconds"], ", ".join(res["refused_by"])), flush=True)
    if overview_items:
        overview(overview_items, os.path.join(out, "overview.png"))
    ok = [r for r in results if r["pass"]]
    refused = {}
    for r in results:
        for g in r["refused_by"]:
            refused.setdefault(g.split(":")[0], []).append(r["id"])
    summary = {"stills": os.path.abspath(stills), "heroes": len(results), "accepted": len(ok), "refused": len(results) - len(ok),
               "refused_by_gate": refused, "seconds_total": round(time.time() - t_all, 1),
               "seconds_per_hero": round((time.time() - t_all) / max(len(results), 1), 2)}
    with open(os.path.join(out, "results.json"), "w") as f:
        json.dump({"summary": summary, "heroes": results}, f, indent=1, default=_plain)
    print(json.dumps(summary))
    return results


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--stills", required=True, help="directory of <ID>.png + <ID>.json (+ <ID>_gear/)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="", help="comma separated ids")
    a = ap.parse_args(argv)
    run(a.stills, a.out, set(filter(None, a.only.split(","))))


if __name__ == "__main__":
    main(sys.argv[1:])

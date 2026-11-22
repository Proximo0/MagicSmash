"""Runs the game-size pilot (gamesize.py) on three fixture heroes, measures old vs new on rendered
frames and writes contact sheets, GIFs and client-layout strips.

    python3 -m tools.animator.gamesize_pilot [out_dir]
"""
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

from . import gamesize as gs

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = "/mnt/project-files/magic-smash-rework/art/realm/animator/gamesize_pilot"
# fixture -> (name the client would load: hero_<race>_<class>, what it carries)
HEROES = {
    "HR6.3": ("dwarf_knight", "hammer, shield on back"),
    "HR3.2": ("human_mage", "staff (carried upright)"),
    "HR2.1": ("human_knight", "greatsword"),
}
ROWS = ("hammer", "staff", "sword")
BG = (90, 110, 90, 255)


def old_frames(png, joints):
    """The old pipeline's 8-frame walk at 56 and 112, as FrameSets without offsets; and its time."""
    from .bake import Character, bake_all
    from .fit import fit_still
    from .gear import load_gear, solve_gear
    t0 = time.time()
    img, data, masks = fit_still(png, joints)
    gears = load_gear(png)
    chs = {bh: Character.from_still(png, joints, fitted=(img, data, masks), body_h=bh, gear=gears)
           for bh in (56, 112)}
    solve_gear(list(chs.values()))
    out = {}
    for bh, ch in chs.items():
        frames, ctx, fails = bake_all(ch, (8,))[8]
        out[bh] = (frames, ch)
    sec = time.time() - t0
    return {bh: _as_set(fr, ch) for bh, (fr, ch) in out.items()}, sec


def _as_set(frames, ch):
    cols = np.unique(np.concatenate([f["rgba"][f["rgba"][..., 3] > 0][:, :3] for f in frames]), axis=0)
    pal = cols.astype(np.uint8)
    names = list(frames[0]["meta"]["labels"])
    names.append("head")
    hi = len(names)       # label id of the head
    out = []
    for f in frames:
        rgba = f["rgba"]
        idx = gs.to_index(np.where(rgba[..., 3:4] >= 128, rgba, 0).astype(np.uint8), pal)
        lab = f["label"].astype(np.int16).copy()
        ti = names.index("torso")
        neck = int(round(f["meta"]["joints"]["neck"][1]))
        m = (lab == ti)
        m[neck:] = False
        lab[m] = hi - 1 + 0       # head label = last name
        idx[lab == 0] = -1
        out.append({"idx": idx, "label": lab, "offset": {}, "variant": {}, "bob": 0})
    return gs.FrameSet(out, names, pal, ch.body_h, ch.foot_y, ch.pelvis_x)


def _prop(fs):
    for n in fs.names:
        if n.startswith("gear:") and n not in ("gear:shield", "gear:quiver", "gear:cape"):
            return n
    return None


def table(rows, cols):
    lines = []
    w = max(len(r[0]) for r in rows) + 2
    lines.append("part".ljust(w) + "".join(c.rjust(13) for c in cols))
    for name, vals in rows:
        lines.append(name.ljust(w) + "".join(v.rjust(13) for v in vals))
    return "\n".join(lines)


def measure_rows(sets, prop):
    """sets: {label: (FrameSet, known)} -> table rows of 'mean %' (limbs: all pairs / same-step pairs)."""
    res = {k: gs.measure(fs, known=kn) for k, (fs, kn) in sets.items()}
    parts = [("head", "head"), ("torso", "torso"), ("prop", prop), ("near_upper", "near_upper"),
             ("near_fore", "near_fore"), ("near_thigh", "near_thigh"), ("near_shin", "near_shin"),
             ("near_foot", "near_foot"), ("far_thigh", "far_thigh"), ("far_foot", "far_foot")]
    rows = []
    for title, nm in parts:
        vals = []
        for k, (fs, kn) in sets.items():
            r = res[k].get(nm)
            if r is None:
                vals.append("-")
            elif kn and title not in ("head", "torso"):
                s = r["same"]
                vals.append("%.0f / %s" % (r["all"][0], "%.0f" % s[0] if s else "-"))
            else:
                vals.append("%.1f" % r["all"][0])
        rows.append((title, vals))
    return rows, res


def sheet_row(fs, crop, scale, label):
    x0, x1, y0, y1 = crop
    ims = []
    for i in range(len(fs.frames)):
        im = Image.new("RGBA", (x1 - x0, y1 - y0), BG)
        im.alpha_composite(Image.fromarray(fs.rgba(i)[y0:y1, x0:x1]))
        ims.append(im.resize(((x1 - x0) * scale, (y1 - y0) * scale), Image.NEAREST))
    w, h = ims[0].size
    row = Image.new("RGBA", (w * len(ims) + 4 * (len(ims) - 1), h), (30, 30, 30, 255))
    for i, im in enumerate(ims):
        row.paste(im, (i * (w + 4), 0))
    ImageDraw.Draw(row).text((4, 2), label, fill=(255, 255, 255, 255))
    return row


def crop_of(sets):
    """Shared crop box in 56 px units over every set."""
    b = [1e9, -1, 1e9, -1]
    for fs in sets:
        s = 56.0 / fs.master
        m = np.any([f["idx"] >= 0 for f in fs.frames], 0)
        ys, xs = np.nonzero(m)
        b = [min(b[0], xs.min() * s), max(b[1], (xs.max() + 1) * s), min(b[2], ys.min() * s), max(b[3], (ys.max() + 1) * s)]
    return int(b[0]) - 1, int(b[1]) + 2, int(b[2]) - 1, int(b[3]) + 2


def contact_sheet(old, new, path):
    """Rows: old 56 (4x), old 112 (2x), A 56, A 112, B 56 (2:1 of B112), B 112 (all shown at the same size)."""
    box = crop_of([old[56], old[112], new["A56"], new["B112"]])
    rows = []
    for fs, lab in ((old[56], "OLD pipeline 56"), (old[112], "OLD pipeline 112"),
                    (new["A56"], "NEW A: 56 master"), (new["A112"], "NEW A: 112 = 2x nearest of 56"),
                    (new["B56"], "NEW B: 56 = 2:1 of the 112 master"), (new["B112"], "NEW B: 112 master (even offsets)")):
        s = 56.0 / fs.master
        x0, x1, y0, y1 = [int(round(v / s)) for v in box]
        rows.append(sheet_row(fs, (x0, x1, y0, y1), 4 if fs.master == 56 else 2, lab))
    w = rows[0].width
    h = sum(r.height + 4 for r in rows)
    sh = Image.new("RGBA", (w, h), (30, 30, 30, 255))
    y = 0
    for r in rows:
        sh.paste(r, (0, y))
        y += r.height + 4
    sh.convert("RGB").save(path)


def gif(fs, path, scale):
    box = crop_of([fs])
    s = 56.0 / fs.master
    x0, x1, y0, y1 = [int(round(v / s)) for v in box]
    ims = []
    for i in range(len(fs.frames)):
        im = Image.new("RGBA", (x1 - x0, y1 - y0), BG)
        im.alpha_composite(Image.fromarray(fs.rgba(i)[y0:y1, x0:x1]))
        ims.append(im.resize(((x1 - x0) * scale, (y1 - y0) * scale), Image.NEAREST).convert("RGB"))
    ims[0].save(path, save_all=True, append_images=ims[1:], duration=125, loop=0)


def client_strip(fs, path, picks=(0, 2, 4, 6)):
    """The strip field_art.gd loads: <name>_walk.png, 4 equal frames side by side, each W x H texture px,
    drawn bottom-centred on the hero's feet (frame centre = pelvis column, last row = ground row),
    facing right, 2 texture px per world px.  Transparent background."""
    fr = [fs.frames[i]["idx"] for i in picks]
    m = np.any([f >= 0 for f in fr], 0)
    ys, xs = np.nonzero(m)
    half = max(fs.pel_x - xs.min(), xs.max() + 1 - fs.pel_x)
    w = 2 * half
    top = ys.min()
    h = fs.foot_y - top
    strip = np.zeros((h, w * len(fr), 4), np.uint8)
    for n, i in enumerate(picks):
        rgba = fs.rgba(i)
        strip[:, n * w:(n + 1) * w] = rgba[top:fs.foot_y, fs.pel_x - half:fs.pel_x + half]
    Image.fromarray(strip).save(path)
    return w, h


def run(out_dir=OUT):
    from .gamesize import bake_hero
    os.makedirs(out_dir, exist_ok=True)
    for sub in ("client", "client_B56"):
        os.makedirs(os.path.join(out_dir, sub), exist_ok=True)
    report = []
    for (hid, (cname, what)) in HEROES.items():
        png = os.path.join(HERE, "samples", "round5", hid + ".png")
        js = png[:-4] + ".json"
        res = bake_hero(png, js)
        old, osec = old_frames(png, js)
        prop = _prop(res["A56"])
        report.append("== %s  (%s, %s)  new bake %.1f s (fit %.1f, 56 master+2x %.1f, 112 master+2:1 %.1f); old bake %.1f s; palette %d colours"
                      % (hid, cname, what, res["seconds"]["total"], res["seconds"]["fit"], res["seconds"]["master56_and_2x"],
                         res["seconds"]["master112_and_2to1"], osec, len(res["A56"].palette)))
        bobs = [f["bob"] for f in res["A56"].frames]
        report.append("   A56 bob per frame %s  B112 bob %s" % (bobs, [f["bob"] for f in res["B112"].frames]))
        for size in (56, 112):
            sets = {"old": (old[size], False), "new A": (res["A%d" % size], True), "new B": (res["B%d" % size], True)}
            rows, _ = measure_rows(sets, prop)
            report.append("   %d px: mean %% of a part's pixels changing frame to frame (limbs: all pairs / same-step pairs)" % size)
            report.append("\n".join("   " + l for l in table(rows, list(sets)).split("\n")))
        contact_sheet(old, res, os.path.join(out_dir, "%s_%s_contact.png" % (hid, cname)))
        for key, sc in (("A56", 4), ("A112", 2), ("B56", 4), ("B112", 2)):
            gif(res[key], os.path.join(out_dir, "%s_%s_%s.gif" % (hid, cname, key)), sc)
        w, h = client_strip(res["A56"], os.path.join(out_dir, "client", "hero_%s_walk.png" % cname))
        w2, h2 = client_strip(res["B56"], os.path.join(out_dir, "client_B56", "hero_%s_walk.png" % cname))
        report.append("   client strip A: %dx%d (4 frames of %dx%d); B: %dx%d" % (4 * w, h, w, h, 4 * w2, h2))
    txt = "\n".join(report)
    with open(os.path.join(out_dir, "measurements.txt"), "w") as f:
        f.write(txt + "\n")
    print(txt)


if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else OUT)

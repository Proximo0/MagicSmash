"""Batch: every still in a folder -> fit -> input gate -> bake -> body-physics gate.

    python3 -m tools.animator batch samples/stills --out out/batch

Every still is baked at each body height in bake.BODY_SIZES (56 and 112 game px for a human).
Per character: accepted -> out/batch/accepted/<id>/ (56 px: strips, GIFs, parts, rig.json,
.skf) and out/batch/accepted/<id>/h112/ (the same at 112 px); rejected (any failed rule, input
or output, at either size) -> out/batch/needs_attention/<id>.png with the failed rules marked,
and nothing written to accepted/.  out/batch/contact.png: per character the still, then its
8-frame walk at 56 px (shown x4) above the same walk at 112 px (shown x2), so the two sizes
are compared at one size on screen (rejected ones in red, their rule numbers listed).  Prints seconds
per character and the accepted / rejected lists with rule numbers; exit code 1 when any
character was rejected.
"""
import glob
import json
import os
import shutil
import time

import numpy as np
from PIL import Image, ImageDraw

from . import checks
from .bake import BODY_H, BODY_SIZES, CANVAS_H, CANVAS_W, FOOT_Y, Character, bake_all, write_outputs
from .autocut import gate_cut
from .fit import fit_still, gate_still, gate_picture

BG = (52, 70, 52)


def _strip_img(frames, scale, bad_frames=()):
    """Frames side by side on the sheet's background; the canvas size is read from the frames,
    so a 112 px strip at scale 2 is as big as a 56 px strip at scale 4."""
    m = frames[0]["rgba"].shape[0] / CANVAS_H
    CANVAS_W, FOOT_Y = int(round(globals()["CANVAS_W"] * m)), int(round(globals()["FOOT_Y"] * m))
    st = np.concatenate([f["rgba"] for f in frames], 1)
    im = Image.new("RGBA", (st.shape[1], st.shape[0]), BG + (255,))
    im.alpha_composite(Image.fromarray(st))
    im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    d = ImageDraw.Draw(im)
    for i in range(1, len(frames)):
        d.line([(i * CANVAS_W * scale, 0), (i * CANVAS_W * scale, im.height)], fill=(40, 56, 40))
    d.line([(0, FOOT_Y * scale), (im.width, FOOT_Y * scale)], fill=(90, 60, 60))
    for i in bad_frames:
        d.rectangle([i * CANVAS_W * scale, 0, (i + 1) * CANVAS_W * scale - 1, im.height - 1],
                    outline=(255, 40, 40), width=2)
    return im


def _fail_frames(fails):
    out = set()
    for f in fails:
        w = f.split(":")[0].split()
        if len(w) == 2 and w[1].isdigit():
            out.add(int(w[1]))
    return sorted(out)


def run(still_dir, out_dir, counts=(4, 8), skf=True, log=print, sizes=BODY_SIZES):
    pngs = sorted(p for p in glob.glob(os.path.join(still_dir, "*.png"))
                  if os.path.exists(p[:-4] + ".json"))
    acc_dir = os.path.join(out_dir, "accepted")
    na_dir = os.path.join(out_dir, "needs_attention")
    for d in (acc_dir, na_dir):
        if os.path.isdir(d):
            shutil.rmtree(d)
        os.makedirs(d)
    rows, accepted, rejected, times = [], [], [], []
    summary = {}
    for png in pngs:
        cid = os.path.basename(png)[:-4]
        t0 = time.time()
        img, data, masks = fit_still(png, png[:-4] + ".json")
        gate = gate_still(data)
        rec = {"fit_score": data["fit"]["score"], "moved_px": data["fit"]["moved_px"],
               "flags": data["fit"]["flags"]}
        frames8 = {}
        chs = {}
        if not gate:
            for bh in sizes:
                chs[bh] = Character.from_still(png, png[:-4] + ".json", fitted=(img, data, masks), body_h=bh)
            ch = chs[sizes[0]]
            gate = gate_cut(ch.info)
            rec["gear_cut"] = round(ch.info["gear_cut"], 2)
            rec["native_grid"] = {k: v for k, v in ch.grid.items() if k != "used_cell"}
        if gate:
            ids = sorted({g[0].split(":")[0] for g in gate}, key=lambda r: int(r[1:]))
            gate_picture(img, data, gate, os.path.join(na_dir, cid + ".png"))
            rec.update(status="rejected", rules=ids, failures=[g[0] for g in gate])
        else:
            baked, fails, bad = {}, [], {}
            for bh in sizes:
                baked[bh] = bake_all(chs[bh], counts)
                f_ = [f for n in counts for f in baked[bh][n][2]]
                fails += [f"{bh}px {f}" for f in f_]
                bad[bh] = _fail_frames(baked[bh][max(counts)][2])
                frames8[bh] = baked[bh][max(counts)][0]
            top = baked[sizes[0]][max(counts)][1]
            rec["gain"] = round(top["gain"], 2)
            rec["speed_px_per_cycle"] = {bh: round(baked[bh][max(counts)][1]["speed"], 1) for bh in sizes}
            if fails:
                rid = lambda f: checks.rule_id(f.split(" ", 1)[1])
                ids = sorted({rid(f) for f in fails}, key=lambda r: int(r[1:]) if r[1:].isdigit() else 99)
                ims = [_strip_img(frames8[bh], max(1, int(round(2 * BODY_H * 2 / bh)) // 2), bad[bh]) for bh in sizes]
                wid = max(i.width for i in ims)
                hgt = sum(i.height for i in ims)
                can = Image.new("RGBA", (wid, hgt + 14 * min(len(fails), 12) + 6), (235, 235, 235, 255))
                y = 0
                for i in ims:
                    can.paste(i, (0, y))
                    y += i.height
                d = ImageDraw.Draw(can)
                for i, f in enumerate(fails[:12]):
                    d.text((4, hgt + 3 + 14 * i), f"{rid(f)} {f}"[:170], fill=(160, 0, 0))
                can.save(os.path.join(na_dir, cid + ".png"))
                rec.update(status="rejected", rules=ids, failures=fails[:40])
            else:
                out = os.path.join(acc_dir, cid)
                for bh in sizes:
                    o = out if bh == sizes[0] else os.path.join(out, f"h{bh}")
                    write_outputs(chs[bh], baked[bh], o)
                if skf:
                    from .skf import write_skf
                    write_skf(ch, baked[sizes[0]][max(counts)][0], top, os.path.join(out, cid + ".skf"))
                rec.update(status="accepted", rules=[])
        dt = time.time() - t0
        times.append(dt)
        rec["seconds"] = round(dt, 2)
        summary[cid] = rec
        (accepted if rec["status"] == "accepted" else rejected).append((cid, rec["rules"]))
        log(f"{cid}: {rec['status']:8s} {dt:4.1f}s  fit {rec['fit_score']:.2f}"
            + (f"  rules {','.join(rec['rules'])}" if rec["rules"] else ""))
        rows.append((cid, rec, frames8, img, data, gate))
    sheet = contact(rows, os.path.join(out_dir, "contact.png"))
    with open(os.path.join(out_dir, "summary.json"), "w") as f:
        json.dump(summary, f, indent=1, default=float)
    log(f"seconds per character: mean {np.mean(times):.2f}, max {np.max(times):.2f}")
    log(f"accepted ({len(accepted)}): " + " ".join(c for c, _ in accepted))
    log(f"rejected ({len(rejected)}): " + "; ".join(f"{c} [{','.join(r)}]" for c, r in rejected))
    log("contact sheet: " + sheet)
    return accepted, rejected


def contact(rows, path, scale=4):
    """scale: zoom of the 56 px row; bigger sizes are shown smaller so every row is as tall."""
    left = 190
    W = CANVAS_W * 8 * scale + left
    ims = []
    for cid, rec, frames, img, data, gate in rows:
        h = CANVAS_H * scale
        n_rows = max(1, len(frames))
        row = Image.new("RGBA", (W, h * n_rows + 16), (24, 24, 24, 255))
        ok = rec["status"] == "accepted"
        d = ImageDraw.Draw(row)
        for i, (bh, fr) in enumerate(sorted(frames.items())):
            z = max(1, int(round(scale * BODY_H / bh)))
            row.paste(_strip_img(fr, z), (left, 16 + i * h))
            d.text((left + 4, 18 + i * h), f"{bh} px body, shown x{z}", fill=(230, 230, 160))
        # the still, at the left, as tall as one row
        a = Image.new("RGBA", (img.shape[1], img.shape[0]), BG + (255,))
        a.alpha_composite(Image.fromarray(img))
        tw = min(left - 4, int(img.shape[1] * h / img.shape[0]))
        th = a.resize((tw, int(img.shape[0] * tw / img.shape[1])), Image.LANCZOS)
        row.paste(th, (0, 16))
        txt = f"{cid}: {rec['status']}  fit {rec['fit_score']:.2f}"
        if "gain" in rec:
            txt += f"  stride gain {rec['gain']}  {rec['speed_px_per_cycle']} px/cycle"
        if rec["rules"]:
            txt += "  rules " + ",".join(rec["rules"]) + ": " + (rec["failures"][0][:150] if rec.get("failures") else "")
        d.text((4, 2), txt, fill=(230, 230, 230) if ok else (255, 110, 110))
        ims.append(row)
    sheet = Image.new("RGBA", (W, sum(r.height for r in ims)), (24, 24, 24, 255))
    y = 0
    for r in ims:
        sheet.paste(r, (0, y))
        y += r.height
    sheet.save(path)
    return path

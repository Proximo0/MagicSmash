"""Batch: every still in a folder -> fit -> input gate -> bake -> body-physics gate.

    python3 -m tools.animator batch samples/stills --out out/batch

Per character: accepted -> out/batch/accepted/<id>/ (strips, GIFs, parts, rig.json, .skf);
rejected (any failed rule, input or output) -> out/batch/needs_attention/<id>.png with the
failed rules marked, and nothing written to accepted/.  out/batch/contact.png: one 8-frame
row per character at 2x (rejected ones in red, their rule numbers listed).  Prints seconds
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
from .bake import CANVAS_H, CANVAS_W, FOOT_Y, Character, bake_all, write_outputs
from .autocut import gate_cut
from .fit import fit_still, gate_still, gate_picture

BG = (52, 70, 52)


def _strip_img(frames, scale, bad_frames=()):
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


def run(still_dir, out_dir, counts=(4, 8), skf=True, log=print):
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
        frames8 = None
        ch = None
        if not gate:
            ch = Character.from_still(png, png[:-4] + ".json", fitted=(img, data, masks))
            gate = gate_cut(ch.info)
            rec["gear_cut"] = round(ch.info["gear_cut"], 2)
        if gate:
            ids = sorted({g[0].split(":")[0] for g in gate})
            gate_picture(img, data, gate, os.path.join(na_dir, cid + ".png"))
            rec.update(status="rejected", rules=ids, failures=[g[0] for g in gate])
        else:
            baked = bake_all(ch, counts)
            fails = [f for n in counts for f in baked[n][2]]
            frames8 = baked[max(counts)][0]
            rec["gain"] = round(baked[max(counts)][1]["gain"], 2)
            rec["speed_px_per_cycle"] = round(baked[max(counts)][1]["speed"], 1)
            if fails:
                ids = sorted({checks.rule_id(f) for f in fails}, key=lambda r: int(r[1:]) if r[1:].isdigit() else 99)
                im = _strip_img(frames8, 2, _fail_frames(baked[max(counts)][2]))
                can = Image.new("RGBA", (im.width, im.height + 14 * min(len(fails), 12) + 6), (235, 235, 235, 255))
                can.paste(im, (0, 0))
                d = ImageDraw.Draw(can)
                for i, f in enumerate(fails[:12]):
                    d.text((4, im.height + 3 + 14 * i), f"{checks.rule_id(f)} {f}"[:150], fill=(160, 0, 0))
                can.save(os.path.join(na_dir, cid + ".png"))
                rec.update(status="rejected", rules=ids, failures=fails[:40])
            else:
                out = os.path.join(acc_dir, cid)
                write_outputs(ch, baked, out)
                if skf:
                    from .skf import write_skf
                    write_skf(ch, baked[max(counts)][0], baked[max(counts)][1], os.path.join(out, cid + ".skf"))
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


def contact(rows, path, scale=2):
    W = CANVAS_W * 8 * scale + 150
    ims = []
    for cid, rec, frames, img, data, gate in rows:
        h = CANVAS_H * scale
        row = Image.new("RGBA", (W, h + 16), (24, 24, 24, 255))
        ok = rec["status"] == "accepted"
        if frames is not None:
            row.paste(_strip_img(frames, scale), (150, 16))
        # the still, small, at the left
        a = Image.new("RGBA", (img.shape[1], img.shape[0]), BG + (255,))
        a.alpha_composite(Image.fromarray(img))
        th = a.resize((int(img.shape[1] * h / img.shape[0]), h), Image.NEAREST)
        row.paste(th, (0, 16))
        txt = f"{cid}: {rec['status']}  fit {rec['fit_score']:.2f}"
        if "gain" in rec:
            txt += f"  stride gain {rec['gain']}  {rec['speed_px_per_cycle']} px/cycle"
        if rec["rules"]:
            txt += "  rules " + ",".join(rec["rules"]) + ": " + (rec["failures"][0][:90] if rec.get("failures") else "")
        ImageDraw.Draw(row).text((4, 2), txt, fill=(230, 230, 230) if ok else (255, 110, 110))
        ims.append(row)
    sheet = Image.new("RGBA", (W, sum(r.height for r in ims)), (24, 24, 24, 255))
    y = 0
    for r in ims:
        sheet.paste(r, (0, y))
        y += r.height
    sheet.save(path)
    return path

"""Monsters: the mannequin (flat synthetic creature drawn from a layout), the spec files the art PC draws over,
the worked examples, and the folder runner (`python3 -m tools.animator monsters <folder> --out DIR`)."""
import json
import os
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from . import monster as mo
from . import monster_checks as mc

OUTLINE = (24, 20, 28, 255)
EXAMPLES = {   # example name -> (plan, style, size_px, speed px/s)
    "ex_biped": ("biped", "shamble", 112, 40),
    "ex_quadruped": ("quadruped", "trot", 80, 70),
    "ex_crawler_skitter": ("crawler", "skitter", 112, 60),
    "ex_crawler_undulate": ("crawler", "undulate", 72, 60),
    "ex_crawler_squash": ("crawler", "squash", 64, 30),
    "ex_flyer_flap": ("flyer", "flap", 80, 70),
    "ex_flyer_orbit": ("flyer", "orbit", 64, 65),
    "ex_floater": ("floater", "sway", 96, 40),
    "ex_construct_hop": ("construct", "hop", 88, 20),
    "ex_construct_rock": ("construct", "rock", 88, 20),
}
PROMPT = ("Pixel-art game monster, full body, strict side view facing right, on a flat pure magenta background. The "
          "creature only: {sentence}. {separation}. The whole creature inside the frame with empty space all round it. "
          "{one} no ground, no shadow. Dark outline around every form.")


def prompt(lay):
    one = ("One connected figure except the three floating pieces:" if lay.orbit else "One connected figure, no loose pieces:")
    return PROMPT.format(sentence=lay.sentence, separation=lay.separation[0].upper() + lay.separation[1:], one=one)


def _cap(d, a, b, r, fill):
    (ax, ay), (bx, by) = a, b
    d.ellipse([ax - r, ay - r, ax + r, ay + r], fill=fill)
    d.ellipse([bx - r, by - r, bx + r, by + r], fill=fill)
    dx, dy = bx - ax, by - ay
    n = (dx * dx + dy * dy) ** 0.5
    if n > 1e-6:
        nx, ny = -dy / n * r, dx / n * r
        d.polygon([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)], fill=fill)


def draw_creature(lay, joints=None, eye=True, thick=None):
    """The mannequin: every part a flat capsule with an outline, an eye of white and a dark pupil. RGBA, transparent ground."""
    J = dict(joints or lay.joints)
    mo.derive_joints(lay.name, J)
    thick = thick or {}
    im = Image.new("RGBA", (mo.CANVAS, mo.CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for p in sorted(lay.parts, key=lambda p: p.z):
        for a, b in p.bones:
            _cap(d, J[a], J[b], thick.get(p.name, p.r) + 3, OUTLINE)
    for p in sorted(lay.parts, key=lambda p: p.z):          # fill after every outline: one outline round the figure,
        for a, b in p.bones:                                 # and thin seams between parts of different colour
            _cap(d, J[a], J[b], thick.get(p.name, p.r), tuple(p.colour) + (255,))
    if eye and lay.eye:
        ex, ey = J[lay.eye]
        er = lay.eye_r
        d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=(250, 250, 250, 255))
        d.ellipse([ex - 0.25 * er, ey - 0.65 * er, ex + 0.75 * er, ey + 0.65 * er], fill=(10, 10, 14, 255))
    return np.array(im)


def joints_json(lay, plan, style, kind="", size=None, speed=None, note=True):
    d = {"format": "monster", "plan": plan, "style": style, "kind": kind}
    if size:
        d["size_px"] = size
    if speed:
        d["speed"] = speed
    d["ground_y"] = lay.ground_y
    d["joints"] = {k: [round(v[0], 1), round(v[1], 1)] for k, v in mo.user_joints(lay).items()}
    if note:
        d["_note"] = (f"{lay.name}: set kind to the monster's name (its size and speed come from monsters.json) or give size_px; "
                      f"style options for this plan: {mo.STYLES[plan]}; keep joints inside the drawn parts; joints in px of a "
                      f"{mo.CANVAS} x {mo.CANVAS} still, y down, facing right")
    return d


def pose_picture(lay):
    im = Image.new("RGBA", (mo.CANVAS, mo.CANVAS), (0, 0, 0, 255))
    d = ImageDraw.Draw(im)
    J = dict(lay.joints)
    mo.derive_joints(lay.name, J)
    for y in (lay.ground_y,):
        d.line([(0, y), (mo.CANVAS, y)], fill=(70, 70, 70, 255), width=1)
    pal = [(0, 200, 255), (255, 200, 0), (120, 255, 120), (255, 120, 200), (200, 160, 255), (255, 140, 60)]
    for i, p in enumerate(lay.parts):
        c = pal[i % len(pal)] + (255,)
        for a, b in p.bones:
            d.line([tuple(J[a]), tuple(J[b])], fill=c, width=3)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    for k, v in mo.user_joints(lay).items():
        x, y = v
        ring = (255, 0, 0, 255) if k == lay.eye else (255, 255, 255, 255)
        d.ellipse([x - 5, y - 5, x + 5, y + 5], outline=ring, width=2)
        d.text((x + 7, y - 5), k, fill=(190, 190, 190, 255), font=font)
    return np.array(im)


def layouts_for(plan):
    seen, out = set(), []
    for style in mo.STYLES[plan]:
        name = mo.LAYOUT_OF[(plan, style)]
        if name not in seen:
            seen.add(name)
            out.append((style, mo.make_layout(plan, style)))
    return out


def write_spec(plan, out):
    """`spec --monster <plan>|all`: per layout the pose picture, the joints JSON, a passing mannequin and the prompt."""
    os.makedirs(out, exist_ok=True)
    files = {}
    for pl in (list(mo.STYLES) if plan == "all" else [plan]):
        for style, lay in layouts_for(pl):
            base = os.path.join(out, lay.name)
            Image.fromarray(pose_picture(lay)).save(base + "_pose.png")
            Image.fromarray(draw_creature(lay)).save(base + "_reference.png")
            with open(base + "_joints.json", "w") as f:
                json.dump(joints_json(lay, pl, style), f, indent=1)
            with open(base + "_prompt.txt", "w") as f:
                f.write(prompt(lay) + "\n")
            files[lay.name] = base
    return files


def write_strip(frames, path, gap=2, bg=None):
    w, h = frames[0]["rgba"].shape[1], frames[0]["rgba"].shape[0]
    sheet = np.zeros((h, len(frames) * (w + gap) - gap, 4), np.uint8)
    if bg:
        sheet[..., :3] = bg
        sheet[..., 3] = 255
    for i, f in enumerate(frames):
        a = f["rgba"]
        m = a[..., 3] > 0
        sl = sheet[:, i * (w + gap):i * (w + gap) + w]
        sl[m] = a[m]
    Image.fromarray(sheet, "RGBA").save(path)
    return sheet


def write_bake(name, baked, out):
    """The files of an accepted monster: strips at both sizes and cycle lengths and the meta (anchor, stride, speed)."""
    os.makedirs(out, exist_ok=True)
    meta = {}
    for (n, sc), b in sorted(baked.items()):
        write_strip(b.frames, os.path.join(out, f"{name}_move{n}_{sc}.png"))
        m = dict(b.meta)
        for k in ("part_areas",):
            m.pop(k, None)
        meta[f"move{n}_{sc}"] = {k: m[k] for k in ("frame_w", "frame_h", "anchor", "ground_row", "stride_px", "travel_per_frame",
                                                  "speed_px_s", "cycles_per_s", "half_stride", "plan", "style")}
    with open(os.path.join(out, f"{name}.meta.json"), "w") as f:
        json.dump(meta, f, indent=1)


def write_examples(out):
    """`spec --monster-example`: for every plan a synthetic creature (still + joints), baked and gated.
    Returns {name: (baked, fails)}."""
    inp = os.path.join(out, "stills")
    os.makedirs(inp, exist_ok=True)
    res = {}
    for name, (plan, style, size, speed) in EXAMPLES.items():
        lay = mo.make_layout(plan, style)
        Image.fromarray(draw_creature(lay)).save(os.path.join(inp, name + ".png"))
        with open(os.path.join(inp, name + ".json"), "w") as f:
            json.dump(joints_json(lay, plan, style, kind="", size=size, speed=speed, note=False) | {"name": name}, f, indent=1)
    acc, rej = run_folder(inp, out)
    return acc, rej


def check_baked(baked, still, data, lay):
    """Run M1-M9 on every baked set: {(n, size): [fail strings]}"""
    return {k: mc.check_all(b, still_rgba=still) for k, b in baked.items()}


def run_folder(folder, out):
    """Bake every `<kind>.png` + `<kind>.json` of a folder, gate and check; accepted ones go to out/accepted/<kind>/, the
    others to out/needs_attention/<kind>.txt (+ png).  Returns (accepted names, rejected names)."""
    acc, rej = [], []
    for fn in sorted(os.listdir(folder)):
        if not fn.endswith(".png"):
            continue
        name = fn[:-4]
        js = os.path.join(folder, name + ".json")
        if not os.path.exists(js):
            continue
        baked, fails, still, data = mo.bake_monster(os.path.join(folder, fn), js)
        report = [f"{r}: {t}" for r, t in fails]
        if baked:
            for (n, sc), b in sorted(baked.items()):
                for r, t in mc.check_all(b, still_rgba=still):
                    report.append(f"{r} (move{n} at {sc}): {t}")
        if report:
            d = os.path.join(out, "needs_attention")
            os.makedirs(d, exist_ok=True)
            shutil.copy(os.path.join(folder, fn), os.path.join(d, fn))
            with open(os.path.join(d, name + ".txt"), "w") as f:
                f.write("\n".join(report) + "\n")
            print(f"{name}: REFUSED {len(report)} ({report[0]})")
            rej.append(name)
        else:
            write_bake(name, baked, os.path.join(out, "accepted", name))
            print(f"{name}: accepted M1-M12 at 56 and 112, 8 and 4 frames")
            acc.append(name)
    return acc, rej

"""Pose the cut parts with a solved motion and bake game-size sprite strips.

Every frame is rendered at SS x game size by inverse-mapping each canvas sub-pixel back into
the still (nearest neighbour, so only still colours ever appear), parts in draw order with
hard alpha.  It is then reduced SS x SS -> 1 by majority: a game pixel is opaque when at
least half its sub-pixels are, and takes the most common colour among them (dark outline
colours get a small bonus so 1-px outlines survive the 2:1 reduction).
"""
import json
import math
import os

import numpy as np
from PIL import Image

from . import checks
from .cut import cut_still, load_still, palette_of, snap_to_palette
from .motion import MOTIONS, Gait
from .rig import Rig, screen_angle, SIDES

BODY_H = 56          # game px from the ground line to the top of the head
SS = 4               # supersample factor
CANVAS_W, CANVAS_H = 96, 80
FOOT_Y = 74          # ground line row on every canvas: soles stand on y = FOOT_Y
PELVIS_X = 46        # pelvis column on every canvas (walk in place)
OUTLINE_LUMA = 60    # colours darker than this count as outline for the reducer
OUTLINE_BONUS = 1.5  # extra sub-pixel votes for an outline colour in a block

NON_LEG = ("torso", "back", "near_upper", "near_fore", "far_upper", "far_fore")


class Character:
    def __init__(self, still_path, joints_path):
        self.rig = Rig.load(joints_path)
        self.still, self.frames, self.frame_index = load_still(still_path, self.rig.data)
        self.parts, self.labels, self.info = cut_still(self.still, self.rig)
        self.palette = self.info["palette"]
        self.k = BODY_H / self.rig.body_height
        self.name = self.rig.name

    def to_game(self, P):
        return (np.asarray(P, float) - [self.rig.j["pelvis"][0], self.rig.ground_y]) * self.k + [PELVIS_X, FOOT_Y]

    def order(self):
        out = []
        for n in self.rig.draw_order:
            if n == "gear":
                out += [g for g in self.parts if g.startswith("gear:")]
            elif n in self.parts:
                out.append(n)
        return out


def _rest_point(rig, name):
    return rig.j[name]


def render(ch, J, order=None):
    """J: posed joints in still px (Rig.fk names). Returns (rgba HxWx4, label HxW, names)."""
    rig, k = ch.rig, ch.k
    order = order or ch.order()
    H4, W4 = CANVAS_H * SS, CANVAS_W * SS
    rgba = np.zeros((H4, W4, 4), np.uint8)
    lab = np.zeros((H4, W4), np.int16)
    names = ["bg"] + order
    for li, name in enumerate(order, start=1):
        part = ch.parts[name]
        side = "far" if name.startswith("far_") else "near"
        a, b = part.bone
        if a == "pelvis":
            pa, pb = J["pelvis"], J["neck"]
            piv_posed = J["pelvis"]
        else:
            pa, pb = J[side + "." + a], J[side + "." + b]
            piv_posed = J[side + "." + part.pivot]
        ra, rb = rig.j[a], rig.j[b]
        delta = math.radians(screen_angle(pb - pa) - screen_angle(rb - ra))
        piv_src = rig.j[part.pivot]
        img = part.img
        m = img[:, :, 3] > 0
        if not m.any():
            continue
        ys, xs = np.where(m)
        c, s = math.cos(delta), math.sin(delta)
        # dest bbox
        corners = np.array([[xs.min(), ys.min()], [xs.max() + 1, ys.min()],
                            [xs.min(), ys.max() + 1], [xs.max() + 1, ys.max() + 1]], float) - piv_src
        dc = np.stack([c * corners[:, 0] - s * corners[:, 1], s * corners[:, 0] + c * corners[:, 1]], 1)
        dg = ch.to_game(piv_posed) + dc * k
        x0 = max(0, int(math.floor(dg[:, 0].min() * SS)) - 1)
        x1 = min(W4, int(math.ceil(dg[:, 0].max() * SS)) + 1)
        y0 = max(0, int(math.floor(dg[:, 1].min() * SS)) - 1)
        y1 = min(H4, int(math.ceil(dg[:, 1].max() * SS)) + 1)
        if x1 <= x0 or y1 <= y0:
            continue
        qy, qx = np.mgrid[y0:y1, x0:x1]
        g = np.stack([(qx + 0.5) / SS, (qy + 0.5) / SS], -1) - ch.to_game(piv_posed)
        g = g / k
        sx = c * g[..., 0] + s * g[..., 1] + piv_src[0]
        sy = -s * g[..., 0] + c * g[..., 1] + piv_src[1]
        ix = np.floor(sx).astype(int)
        iy = np.floor(sy).astype(int)
        ok = (ix >= 0) & (iy >= 0) & (ix < img.shape[1]) & (iy < img.shape[0])
        ixc, iyc = np.clip(ix, 0, img.shape[1] - 1), np.clip(iy, 0, img.shape[0] - 1)
        src = img[iyc, ixc]
        hit = ok & (src[..., 3] > 0)
        sub = rgba[y0:y1, x0:x1]
        sub[hit] = src[hit]
        lab[y0:y1, x0:x1][hit] = li
    return rgba, lab, names


def reduce(rgba, lab):
    H4, W4 = lab.shape
    H, W = H4 // SS, W4 // SS
    col = (rgba[..., 0].astype(np.int64) << 16) | (rgba[..., 1].astype(np.int64) << 8) | rgba[..., 2]
    col = np.where(rgba[..., 3] > 0, col, -1)
    blk = col.reshape(H, SS, W, SS).transpose(0, 2, 1, 3).reshape(H, W, SS * SS)
    lb = lab.reshape(H, SS, W, SS).transpose(0, 2, 1, 3).reshape(H, W, SS * SS)
    opaque = (blk >= 0).sum(-1)
    eq = blk[..., :, None] == blk[..., None, :]
    cnt = eq.sum(-1).astype(float)
    r, g, b = (blk >> 16) & 255, (blk >> 8) & 255, blk & 255
    luma = (r * 3 + g * 4 + b * 2) / 9.0
    cnt = cnt + np.where(luma < OUTLINE_LUMA, OUTLINE_BONUS, 0.0)
    cnt = np.where(blk >= 0, cnt, -1)
    best = np.argmax(cnt, -1)
    c = np.take_along_axis(blk, best[..., None], -1)[..., 0]
    l = np.take_along_axis(lb, best[..., None], -1)[..., 0]
    on = opaque * 2 >= SS * SS
    out = np.zeros((H, W, 4), np.uint8)
    out[..., 0] = (c >> 16) & 255
    out[..., 1] = (c >> 8) & 255
    out[..., 2] = c & 255
    out[..., 3] = 255
    out[~on] = 0
    l = np.where(on, l, 0).astype(np.int16)
    return cleanup(out, l)


def cleanup(out, l):
    """One pass of pixel-art tidying after the reduction: close 1-px slits and pinholes
    (a transparent pixel with opaque pixels on both sides along a row or column takes its
    neighbours' colour) and drop lone specks (an opaque pixel with at most one opaque
    8-neighbour).  Colours are only ever copied, never mixed."""
    H, W = l.shape
    a = out[..., 3] > 0
    p = np.pad(a, 1)
    lt, rt, up, dn = p[1:-1, :-2], p[1:-1, 2:], p[:-2, 1:-1], p[2:, 1:-1]
    hole = ~a & ((lt & rt) | (up & dn))
    po = np.pad(out, ((1, 1), (1, 1), (0, 0)))
    pl = np.pad(l, 1)
    res, rl = out.copy(), l.copy()
    for (dy, dx), m in (((0, -1), lt), ((0, 1), rt), ((-1, 0), up), ((1, 0), dn)):
        take = hole & m & (res[..., 3] == 0)
        res[take] = po[1 + dy:1 + dy + H, 1 + dx:1 + dx + W][take]
        rl[take] = pl[1 + dy:1 + dy + H, 1 + dx:1 + dx + W][take]
    a2 = res[..., 3] > 0
    p2 = np.pad(a2, 1)
    nb = sum(p2[1 + dy:1 + dy + H, 1 + dx:1 + dx + W] for dy in (-1, 0, 1) for dx in (-1, 0, 1)
             if dy or dx)
    speck = a2 & (nb <= 1)
    res[speck] = 0
    rl[speck] = 0
    return res, rl


def bake_motion(ch, motion, n=None, gait=None):
    n = n or motion.frames
    gait = gait or Gait(ch.rig, motion)
    frames = []
    for i in range(n + 1):           # frame n is the closing frame (phase 1.0), not output
        p = i / n
        pose, contact = gait.pose(p)
        J = ch.rig.fk(pose)
        rgba4, lab4, names = render(ch, J)
        rgba, lab = reduce(rgba4, lab4)
        Jg = {k: ch.to_game(v) for k, v in J.items()}
        meta = {"phase": p, "joints": Jg, "contact": contact,
                "draw_order": names[1:], "labels": names,
                "digests": {nm: ch.parts[nm].digest() for nm in names[1:]},
                "pose": pose}
        frames.append({"rgba": rgba, "label": lab, "meta": meta})
    closing = frames.pop()
    ctx = context(ch, motion, gait, n)
    ctx["closing"] = closing["meta"]
    return frames, ctx


def context(ch, motion, gait, n):
    k = ch.k
    return {
        "name": ch.name, "motion": motion.name, "n": n, "k": k,
        "lengths": {b: L * k for b, _, _, L in ch.rig.bone_pairs()},
        "bones": [(b, a, c) for b, a, c, _ in ch.rig.bone_pairs()],
        "rest_lean": ch.rig.rest["lean"],
        "ground": FOOT_Y, "facing": 1,
        "speed": gait.stride * k,                  # game px per cycle
        "travels": motion.travels,
        "stance": dict(motion.stance),
        "foot_len": float(np.hypot(*ch.rig.foot_local["toe"])) * k,
        "leg_width": 2 * ch.info["radius"]["shin"] * k,
        "palette": ch.palette,
        "cut_digests": {nm: p.digest() for nm, p in ch.parts.items()},
        "rigid": [nm for nm in ch.parts if nm in ("torso", "back") or nm.startswith("gear:")],
    }


def strip(frames, flip=False):
    imgs = [f["rgba"][:, ::-1] if flip else f["rgba"] for f in frames]
    return np.concatenate(imgs, 1)


def save_png(arr, path, scale=1):
    im = Image.fromarray(arr, "RGBA")
    if scale != 1:
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    im.save(path)


def save_gif(frames, path, scale=4, ms=125, bg=(48, 64, 48)):
    ims = []
    for f in frames:
        a = f["rgba"]
        base = np.zeros_like(a)
        base[..., :3] = bg
        base[..., 3] = 255
        m = a[..., 3] > 0
        base[m] = a[m]
        im = Image.fromarray(base[..., :3], "RGB").resize((a.shape[1] * scale, a.shape[0] * scale), Image.NEAREST)
        ims.append(im.convert("P", palette=Image.ADAPTIVE, colors=255))
    ims[0].save(path, save_all=True, append_images=ims[1:], duration=ms, loop=0, disposal=2)


def bake_character(still_path, joints_path, out_dir, motions=("walk",)):
    """Bake every motion; walk at 4 and 8 frames. Returns dict of results."""
    ch = Character(still_path, joints_path)
    os.makedirs(out_dir, exist_ok=True)
    results = {}
    meta_out = {"name": ch.name, "still_frame": ch.frame_index, "canvas": [CANVAS_W, CANVAS_H],
                "foot_y": FOOT_Y, "body_height": BODY_H, "scale": ch.k, "motions": {}}
    for mname in motions:
        motion = MOTIONS[mname]()
        counts = (4, 8) if mname == "walk" else (motion.frames,)
        for n in counts:
            frames, ctx = bake_motion(ch, motion, n)
            fails = checks.run_all(frames, ctx)
            tag = f"{ch.name}_{mname}{n}"
            save_png(strip(frames), os.path.join(out_dir, tag + "_r.png"))
            save_png(strip(frames, flip=True), os.path.join(out_dir, tag + "_l.png"))
            save_png(strip(frames), os.path.join(out_dir, tag + "_r_x4.png"), scale=4)
            ms = int(round(1000 * (1.0 if mname != "run" else 0.7) / n))
            if mname == "idle":
                ms = 300
            save_gif(frames, os.path.join(out_dir, tag + ".gif"), ms=ms)
            results[(mname, n)] = {"frames": frames, "ctx": ctx, "fails": fails}
            meta_out["motions"][f"{mname}{n}"] = {
                "frames": n, "speed_px_per_cycle": round(ctx["speed"], 3),
                "ms_per_frame": ms, "checks": "ok" if not fails else fails}
    with open(os.path.join(out_dir, ch.name + ".json"), "w") as f:
        json.dump(meta_out, f, indent=1)
    return ch, results

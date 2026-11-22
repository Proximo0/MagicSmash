"""Pose the cut parts with a solved motion and bake game-size sprite strips.

Every frame is rendered at SS x game size by inverse-mapping each canvas sub-pixel back into
the still (nearest neighbour, so only palette colours ever appear), parts in draw order with
hard alpha.  Rigid parts turn with their bone; cloth parts (autocut) use cloth.ClothSim: the
cape turns about its top anchor, the robe is sheared row by row between the legs.

Reduction SS x SS -> 1 (`reduce`, pixel-art safe):
  * a game pixel is opaque when at least half of its sub-pixels are;
  * its colour is the block's mode (palette colours only, so "palette locked"), where a colour
    much darker than the block (DETAIL_DELTA luma below the block mean) covering at least
    DETAIL_MIN of the block gets DETAIL_BONUS x votes: 1-px outlines, eyes, mouths and belt
    lines survive a 7:1 shrink instead of being voted away by the fill around them;
  * silhouette pixels take the block's outline colour (luma < OUTLINE_LUMA) when one covers
    at least OUTLINE_MIN of the block, so the 1-px outline stays closed;
  * tidy: 1-px slits and pinholes closed, lone specks dropped (colours copied, never mixed).
"""
import json
import math
import os

import numpy as np
from PIL import Image

from . import checks
from .cut import cut_still, load_still
from .foot import behind_back_edge, fit_foot, reseat
from . import gear as gear_mod
from .gear import hand_local as _hand_local, min_of as _gear_min
from .imgops import shift
from .motion import MOTIONS, Gait, fit_walk, walk
from .rig import Rig, screen_angle, SIDES

BODY_H = 56          # game px from the ground line to the top of the head (legacy samples)
REF_BH = 390.0       # still px of a human hero's head-top-to-ground in samples/stills; all
                     # stills share one scale, so dwarves stay short and orcs tall
SS = 6               # supersample factor (one sub-pixel ~ one still pixel at 7:1)
CANVAS_W, CANVAS_H = 96, 80
FOOT_Y = 74          # ground line row on every canvas: soles stand on y = FOOT_Y
PELVIS_X = 46        # pelvis column on every canvas (walk in place)
OUTLINE_LUMA = 55    # colours darker than this are outline colours
OUTLINE_MIN = 0.12   # share of a silhouette block an outline colour needs to win it
DETAIL_DELTA = 45    # a detail colour is this much darker than its block's mean luma ...
DETAIL_MIN = 0.12    # ... and covers at least this share of the block ...
DETAIL_BONUS = 2.5   # ... and then counts this many times
HEEL_TOL = 0.8       # game px the posed heel may swing behind the shin's back edge (rule R6: 1)
STRIDE_QUANT = 8     # game px: stride per cycle is a multiple of this, so at 8 (and 4)
                     # frames the stance foot moves a whole number of px per frame

SEAT_MAX = 1.5       # game px at 56 px body height: how far a planted foot's pixels may be moved
                     # to stand on the ground row (render)
BACK_SLOTS = ("back", "cape", "far_hand", "near_hand")   # gear that should hide the far hand (R26)
FAR_HAND_CLEAR = 0.01  # x body height: the far hand ends this far above the hip line
GEAR_LONG = 0.30     # x body height: held gear reaching this far past the wrist is "long" ...
CARRY_BOB = 0.15     # pass 8: arm swing of the carry pose (long hand gear), x the walk's
GEAR_ARM = 0.40      # ... and that arm swings only this much (a staff is carried steady)

BODY_SIZES = (56, 112)   # game px body height of a human hero: every still is baked at both
ARM_OUTLINE = True         # pass 10: a darker edge on a near arm the colour of the torso (outline_near_arm)
TIDY_CLOTH = True          # pass 9: final cloth-silhouette clean-up (tidy_cloth_edge)
DROP_DARK_BLOCKS = True    # pass 9: lone outline blocks on light cloth are repainted (intake.drop_dark_blocks)
NATIVE_SS = 3            # supersample when the parts are flat blocks of the native grid: a turned
                         # block is re-sampled 3 x 3 and the mode taken, nothing is mixed

AUTO_DRAW_ORDER = ["far_upper", "far_fore", "far_thigh", "far_shin", "far_foot", "cape",
                   "torso", "near_thigh", "near_shin", "near_foot", "robe",
                   "near_upper", "near_fore"]


def refit_foot(rig, parts, radius):
    """Re-measure heel, toe and ankle from the cut near shin + foot pixels (foot.fit_foot).
    Returns a new Rig, or the old one when the foot cannot be measured."""
    m = parts["near_shin"].mask | parts["near_foot"].mask
    f = fit_foot(m, rig.j["knee"], rig.j["ankle"], radius["shin"])
    if f is None:
        return rig, None
    data = json.loads(json.dumps(rig.data))
    for k in ("heel", "toe", "ankle"):
        data["joints"][k] = [round(float(f[k][0]), 2), round(float(f[k][1]), 2)]
    data["foot_fit"] = {"pitch": f["pitch"], "length": round(f["length"], 2),
                        "back": round(f["back"], 2), "front": round(f["front"], 2),
                        "seat": f["seat"], "cut": f["cut"]}
    return Rig(data), f


class Character:
    """A cut character.  Character(png, joints_json) = legacy hand joints on a 4-frame strip;
    Character.from_still(png, layout_json) = full-size still fitted by fit.py (no shapes)."""

    # geometry of the baked canvas; from_still() scales it with the body height
    body_h, ss = BODY_H, SS
    canvas = (CANVAS_W, CANVAS_H)
    foot_y, pelvis_x = FOOT_Y, PELVIS_X
    native = False            # parts are flat blocks of a native grid (see from_still)
    grid = None
    gear = ()                 # gear.Gear attachments (from_still: <id>_gear/*.json)

    def __init__(self, still_path=None, joints_path=None):
        self.auto = False
        self.fit = None
        if still_path is None:
            return
        self.rig = Rig.load(joints_path)
        self.still, self.frames, self.frame_index = load_still(still_path, self.rig.data)
        self.parts, self.labels, self.info = cut_still(self.still, self.rig)
        self.rig, self.foot = refit_foot(self.rig, self.parts, self.info["radius"])
        if self.foot is not None:   # cut again so the whole boot (heel included) is the foot
            drawn = json.loads(json.dumps(self.rig.data))      # the foot where it is drawn
            for k_ in ("heel", "toe"):
                drawn["joints"][k_] = [drawn["joints"][k_][i] - self.foot["seat"][i] for i in (0, 1)]
            self.parts, self.labels, self.info = cut_still(self.still, Rig(drawn))
            for nm in ("near_foot", "far_foot"):      # heel's rear end onto the shin's back edge
                self.parts[nm].img = reseat(self.parts[nm].img, self.foot["seat"])
        self.palette = self.info["palette"]
        self.k = BODY_H / self.rig.body_height
        self.rig.data["heel_tol_px"] = HEEL_TOL / self.k
        self.name = self.rig.name
        far = self.rig.data.get("far", {})
        self.step_px = float(self.rig.j["heel"][0] - far["heel"][0]) if "heel" in far else None

    @classmethod
    def from_still(cls, png, layout_json, fitted=None, body_h=BODY_H, native=True, gear=None):
        """body_h: game px of a REF_BH still (56 or 112); the canvas scales with it.
        native: rebuild every cut part from flat blocks of the still's native grid before it is
        posed (intake.detect_grid; when the still has no rigid grid, the blocks are the output
        pixels of this size, anchored on the pelvis column and the ground line), so an unturned
        part comes out as one output pixel per block and a turned one moves whole blocks."""
        from .autocut import cut_auto
        from .fit import fit_still
        from .intake import detect_grid, drop_dark_blocks, snap_to_grid
        ch = cls()
        ch.auto = True
        img, data, masks = fitted or fit_still(png, layout_json)
        data = json.loads(json.dumps(data, default=float))
        data["draw_order"] = AUTO_DRAW_ORDER
        # the far limbs hang a whole number of 56 px game pixels behind the near ones, so both
        # feet meet the pixel grid alike (a far foot 0.3 px off jittered 2 px at 112 px)
        q = REF_BH / BODY_H
        for key in ("far_hip_offset", "far_shoulder_offset"):
            if key in data and not data.get("robe"):
                v = data[key][0]
                data[key] = [round(v / q) * q if abs(v) >= q / 2 else (-q if v < 0 else q), data[key][1]]
        ch.fit = data["fit"]
        ch.rig = Rig(data)
        ch.still, ch.frames, ch.frame_index = img, [img], 0
        ch.masks = masks
        ch.parts, ch.labels, ch.info = cut_auto(img, ch.rig, masks)
        ch.palette = ch.info["palette"]
        m = body_h / BODY_H
        ch.body_h = body_h
        ch.canvas = (int(round(CANVAS_W * m)), int(round(CANVAS_H * m)))
        ch.foot_y, ch.pelvis_x = int(round(FOOT_Y * m)), int(round(PELVIS_X * m))
        ch.k = body_h / REF_BH
        if native:
            g = detect_grid(img)
            if g["found"]:
                cell, origin = g["cell"], g["phase"]
            else:                 # no rigid grid: one block per output pixel of this size
                cell = (1.0 / ch.k, 1.0 / ch.k)
                origin = (float(ch.rig.j["pelvis"][0]), float(ch.rig.ground_y))
            for p in ch.parts.values():
                p.img = snap_to_grid(p.img, cell, origin)
                if DROP_DARK_BLOCKS:
                    p.img, _ = drop_dark_blocks(p.img, cell, origin, ch.rig.j["neck"][1] + 0.015 * ch.rig.body_height)
            ch.native, ch.ss = True, NATIVE_SS
            ch.grid = dict(g, used_cell=[float(cell[0]), float(cell[1])])
        # the walk is the same at every size: the ankle's plantarflexion limit is set in still
        # px from the 56 px scale the rules are written for (checks.TOL_PX)
        ch.rig.data["heel_tol_px"] = HEEL_TOL / (BODY_H / REF_BH)
        ch.name = ch.rig.name
        ch.step_px = float(data["stride_still"])
        if gear is None:
            from .gear import load_gear
            gear = load_gear(png)
        ch.gear = list(gear)
        tall = max([g.size for g in ch.gear if g.slot == "near_hand"] + [0.0])
        if tall > 1.0:        # pass 10: a banner reaches above the usual headroom: the canvas grows upwards
            extra = int(round(0.40 * ch.body_h))
            ch.canvas = (ch.canvas[0], ch.canvas[1] + extra)
            ch.foot_y += extra
        if ch.gear:               # colours of the gear pictures join the palette (R15)
            ch.palette = np.unique(np.concatenate([ch.palette] + [g.palette for g in ch.gear]), axis=0)
            # a near hand that holds gear is a carried arm: it keeps the still's pose and swings at
            # GEAR_ARM, so the weapon stays where its angle put it (ahead of the body, off the legs)
            if any(g.slot == "near_hand" for g in ch.gear):
                ch.info["gear_reach"] = max(ch.info.get("gear_reach", 0), 2 * GEAR_LONG)
        return ch

    def to_game(self, P):
        return (np.asarray(P, float) - [self.rig.j["pelvis"][0], self.rig.ground_y]) * self.k + [self.pelvis_x, self.foot_y]

    def from_game(self, G):
        return (np.asarray(G, float) - [self.pelvis_x, self.foot_y]) / self.k + [self.rig.j["pelvis"][0], self.rig.ground_y]

    def order(self):
        out = []
        for n in self.rig.draw_order:
            if n == "gear":
                out += [g for g in self.parts if g.startswith("gear:")]
            elif n in self.parts:
                out.append(n)
        return out

    def walk_motion(self):
        """The walk retargeted to this still's stride, quantized to STRIDE_QUANT game px."""
        if not self.step_px or self.step_px <= 0:
            return walk()
        q = STRIDE_QUANT * (self.body_h / BODY_H) / self.k    # still px per quantum (the same
                                                              # stride at every baked size)
        stride = 2 * self.step_px
        target = max(q, round(stride * 0.95 / q) * q)
        arm = GEAR_ARM if self.info.get("gear_reach", 0) > GEAR_LONG else 1.0
        poses = [g.carry for g in self.gear if g.slot == "near_hand" and g.carry]
        carry = ("upright" if "upright" in poses else poses[0]) if poses else False
        if carry:                  # long gear (upright) or a crossbow / censer (level) or a book (chest): carry pose,
            arm = CARRY_BOB        # arm swing a small bob
        m = fit_walk(self.rig, target / 2.0 / 0.95, exact=target, quantum=q, arm=arm)
        m.carry = carry
        m.far_hold = any(g.slot == "far_hand" and g.in_front for g in self.gear)
        return m


def _bbox_map(ch, piv_src, piv_posed, delta, img):
    """Destination sub-pixel window for a part turned by delta about its pivot."""
    m = img[:, :, 3] > 0
    ys, xs = np.where(m)
    c, s = math.cos(delta), math.sin(delta)
    corners = np.array([[xs.min(), ys.min()], [xs.max() + 1, ys.min()],
                        [xs.min(), ys.max() + 1], [xs.max() + 1, ys.max() + 1]], float) - piv_src
    dc = np.stack([c * corners[:, 0] - s * corners[:, 1], s * corners[:, 0] + c * corners[:, 1]], 1)
    return ch.to_game(piv_posed) + dc * ch.k


def render(ch, J, order=None, cloth=None, phase=0.0, contact=None):
    """J: posed joints in still px (Rig.fk names). Returns (rgba HxWx4, label HxW, names).
    contact: {"near": bool, "far": bool}; a planted foot's pixels are seated on the ground row
    (moved whole sub-pixel rows, at most SEAT_MAX): the rig rocks on the heel and toe points of
    the sole line, a drawn boot has a rounded heel and a sprung toe that end a little above it."""
    rig, k = ch.rig, ch.k
    SS = ch.ss
    order = order or ch.order()
    H4, W4 = ch.canvas[1] * SS, ch.canvas[0] * SS
    rgba = np.zeros((H4, W4, 4), np.uint8)
    lab = np.zeros((H4, W4), np.int16)
    names = ["bg"] + order
    for li, name in enumerate(order, start=1):
        part = ch.parts[name]
        img = part.img
        if not (img[:, :, 3] > 0).any():
            continue
        kind = getattr(part, "kind", "rigid")
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
        slack = 0.0
        if kind == "cape" and cloth is not None:
            delta += math.radians(cloth.cape_angle(phase))
            slack = 0.0
        if kind == "robe":
            xs_ = np.flatnonzero(part.mask.any(0))
            slack = 0.5 * (xs_.max() - xs_.min() + 1)
        dg = _bbox_map(ch, piv_src, piv_posed, delta, img)
        pad = abs(slack) * k + 2
        x0 = max(0, int(math.floor((dg[:, 0].min() - pad) * SS)) - 1)
        x1 = min(W4, int(math.ceil((dg[:, 0].max() + pad) * SS)) + 1)
        y0 = max(0, int(math.floor(dg[:, 1].min() * SS)) - 1)
        y1 = min(H4, int(math.ceil(dg[:, 1].max() * SS)) + 1)
        seat_lim = int(round(SEAT_MAX * ch.body_h / BODY_H * SS)) if name.endswith("_foot") else 0
        y1 = min(H4, y1 + seat_lim)
        if x1 <= x0 or y1 <= y0:
            continue
        qy, qx = np.mgrid[y0:y1, x0:x1]
        Q = ch.from_game(np.stack([(qx + 0.5) / SS, (qy + 0.5) / SS], -1))
        if kind == "cape" and cloth is not None:
            # torso transform, then the pendulum turn about the cape's top anchor
            Qr = cloth.torso_inv(J, Q)
            th = math.radians(-cloth.cape_angle(phase))
            c, s = math.cos(th), math.sin(th)
            d = Qr - part.anchor
            sx = c * d[..., 0] - s * d[..., 1] + part.anchor[0]
            sy = s * d[..., 0] + c * d[..., 1] + part.anchor[1]
        elif kind == "robe" and cloth is not None:
            Qr = cloth.torso_inv(J, Q)
            sy = Qr[..., 1]
            rows, prm = cloth.robe_rows(J, phase)
            iy = np.clip(np.floor(sy).astype(int) - cloth.r0, 0, len(rows) - 1)
            w, dB, g, lag = (prm[iy, i] for i in range(4))
            xl = cloth.xl[np.clip(np.floor(sy).astype(int), 0, img.shape[0] - 1)]
            # x' = x + w (dB + (x - xl) g) + lag   ->   x = (x' - w dB + w g xl - lag) / (1 + w g)
            sx = (Qr[..., 0] - w * dB + w * g * xl - lag) / (1 + w * g)
        else:
            c, s = math.cos(delta), math.sin(delta)
            g_ = Q - piv_posed
            sx = c * g_[..., 0] + s * g_[..., 1] + piv_src[0]
            sy = -s * g_[..., 0] + c * g_[..., 1] + piv_src[1]
        ix = np.floor(sx).astype(int)
        iy = np.floor(sy).astype(int)
        ok = (ix >= 0) & (iy >= 0) & (ix < img.shape[1]) & (iy < img.shape[0])
        ixc, iyc = np.clip(ix, 0, img.shape[1] - 1), np.clip(iy, 0, img.shape[0] - 1)
        src = img[iyc, ixc]
        hit = ok & (src[..., 3] > 0)
        if name.endswith("_foot") and "foot_fit" in rig.data:
            # nothing of the foot behind the shin's back edge (the heel is flush with it)
            kn, an = ch.to_game(J[side + ".knee"]), ch.to_game(J[side + ".ankle"])
            Pq = np.stack([(qx + 0.5) / SS, (qy + 0.5) / SS], -1)
            hit &= behind_back_edge(Pq, kn, an, rig.data["foot_fit"]["back"] * k) <= 0
        if seat_lim and contact and contact.get(side) and hit.any():
            low = int(np.flatnonzero(hit.any(1))[-1]) + y0
            down = ch.foot_y * SS - 1 - low
            if down and abs(down) <= seat_lim:
                hit = shift(hit, -down, 0, False)
                src = shift(src, -down, 0, 0)
        sub = rgba[y0:y1, x0:x1]
        sub[hit] = src[hit]
        lab[y0:y1, x0:x1][hit] = li
    return rgba, lab, names


def _luma(c):
    r, g, b = (c >> 16) & 255, (c >> 8) & 255, c & 255
    return (r * 3 + g * 4 + b * 2) / 9.0


def reduce(rgba, lab, SS=SS, native=False, cover=0.5):
    """cover: share of a block that must be opaque for the game pixel to be (gear sprites use
    less than half so thin handles stay whole).
    native: the sub-pixels are flat native blocks, so the plain mode is the picture; only
    the silhouette keeps its outline rule (a third of the block), no bonus for dark detail."""
    detail_bonus, outline_min = (1.0, 0.3) if native else (DETAIL_BONUS, OUTLINE_MIN)
    H4, W4 = lab.shape
    H, W = H4 // SS, W4 // SS
    N = SS * SS
    col = (rgba[..., 0].astype(np.int64) << 16) | (rgba[..., 1].astype(np.int64) << 8) | rgba[..., 2]
    col = np.where(rgba[..., 3] > 0, col, -1)
    blk = col.reshape(H, SS, W, SS).transpose(0, 2, 1, 3).reshape(H, W, N)
    lb = lab.reshape(H, SS, W, SS).transpose(0, 2, 1, 3).reshape(H, W, N)
    opaque = (blk >= 0).sum(-1)
    on = opaque >= cover * N
    out = np.zeros((H, W, 4), np.uint8)
    l = np.zeros((H, W), np.int16)
    ys, xs = np.where(on)
    if not len(ys):
        return out, l
    B = blk[ys, xs]                     # (M, N) only the opaque blocks
    LB = lb[ys, xs]
    valid = B >= 0
    eq = (B[:, :, None] == B[:, None, :]) & valid[:, None, :]
    cnt = eq.sum(-1).astype(float)
    lum = _luma(np.where(valid, B, 0))
    mean = (lum * valid).sum(1) / np.maximum(valid.sum(1), 1)
    share = cnt / N
    detail = valid & (lum < mean[:, None] - DETAIL_DELTA) & (share >= DETAIL_MIN)
    votes = np.where(valid, cnt * np.where(detail, detail_bonus, 1.0), -1.0)
    best = np.argmax(votes, 1)
    # silhouette pixels keep an outline colour
    onp = np.pad(on, 1)
    edge = ~(onp[:-2, 1:-1] & onp[2:, 1:-1] & onp[1:-1, :-2] & onp[1:-1, 2:])[ys, xs]
    outl = valid & (lum < OUTLINE_LUMA) & (share >= outline_min)
    ov = np.where(outl, cnt, -1.0)
    has = outl.any(1) & edge
    best = np.where(has, np.argmax(ov, 1), best)
    c = B[np.arange(len(B)), best]
    out[ys, xs, 0] = (c >> 16) & 255
    out[ys, xs, 1] = (c >> 8) & 255
    out[ys, xs, 2] = c & 255
    out[ys, xs, 3] = 255
    l[ys, xs] = LB[np.arange(len(B)), best]
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


def paint_far_hand(rgba, lab, names, hand_xy, r, colour):
    """Pass 10: with an off-hand weapon the far arm stays hidden behind the body as usual, and only the far
    hand is drawn, a small disc of the far hand's colour (from the cut far forearm) in front of the body at the
    weapon's grip, labelled as the far forearm.  The near arm and the head keep their pixels."""
    if "far_fore" not in names:
        return rgba, lab
    keep = np.isin(lab, [names.index(n) for n in ("near_upper", "near_fore") if n in names])
    yy, xx = np.mgrid[0:lab.shape[0], 0:lab.shape[1]]
    disc = (np.hypot(xx + 0.5 - hand_xy[0], yy + 0.5 - hand_xy[1]) <= r) & ~keep
    rgba[disc] = (*colour, 255)
    lab[disc] = names.index("far_fore")
    return rgba, lab


def hide_far_behind_torso(rgba, lab, names, hide_all=False):
    """One treatment of the far arm for every character (pass 7, fault C): it shows only where it
    swings out FORWARD of the torso, an arm joined to the body, shaded.  Its pixels behind the
    torso's back edge (row by row, checks.far_edge) are not drawn: that is the arm hidden by the
    body, and nothing of it is left to hang as a grey flap behind the back hip or as a sliver
    along the back with the torso's outline missing.  A piece of the far arm left touching
    neither the torso, the robe nor the near arm is hidden too (a detached arm)."""
    from .imgops import components
    if "torso" not in names:
        return rgba, lab
    far = np.isin(lab, [names.index(n) for n in ("far_upper", "far_fore") if n in names])
    tm = lab == names.index("torso")
    if not far.any() or not tm.any():
        return rgba, lab
    H, W = lab.shape
    hide = far & (np.arange(W)[None, :] < checks.far_edge(tm)[:, None])
    if hide_all:          # pass 10: an off-hand weapon is shown in front of the body; the far arm behind it is not
        hide = far.copy()
    rgba[hide] = 0
    lab[hide] = 0
    far &= ~hide
    if far.any():
        host = np.isin(lab, [names.index(n) for n in ("torso", "robe", "near_upper", "near_fore")
                             if n in names])
        touch = host.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                touch |= np.roll(np.roll(host, dy, 0), dx, 1)
        cl, sizes = components(far)
        for k in sizes:
            if not (touch & (cl == k)).any():
                rgba[cl == k] = 0
                lab[cl == k] = 0
    return rgba, lab


ARM_CLOSE = 40.0      # pass 10: an arm edge pixel this close (RGB distance) to the torso colour beside it vanishes


edge_pairs = checks.edge_pairs


def outline_near_arm(rgba, lab, names, palette, thick=1):
    """Pass 10: a sleeve the colour of the coat made the near arm vanish (HR12.1, 12.2, 13.1, 13.3).  Where the near
    arm's edge pixels lie over the torso or robe in a colour within ARM_CLOSE of the pixel beside them, they are
    drawn as a darker shade of the sleeve's own colour (a lighter one for a very dark sleeve), taken from the
    palette and at least ARM_CLOSE from the torso colour: an outline, not black.  `thick` px deep."""
    edge, ny, nx = edge_pairs(lab, names)
    if not edge.any():
        return rgba, lab
    out = rgba.copy()
    pal = np.asarray(palette, float).reshape(-1, 3)
    ys, xs = np.where(edge)
    todo = []
    for y, x in zip(ys, xs):
        a = rgba[y, x, :3].astype(float)
        h = rgba[ny[y, x], nx[y, x], :3].astype(float)
        if np.sqrt(((a - h) ** 2).sum()) < ARM_CLOSE:
            todo.append((y, x, a, h))
    arm = np.isin(lab, [names.index(n) for n in ("near_upper", "near_fore") if n in names])
    for y, x, a, h in todo:
        lum = a @ np.array([0.299, 0.587, 0.114])
        want = a * 0.62 if lum >= 70 else np.minimum(a * 1.5 + 30, 255)
        d_h = np.sqrt(((pal - h) ** 2).sum(1))
        cand = d_h >= ARM_CLOSE
        if not cand.any():
            cand = d_h >= d_h.max() - 1e-6
        d_w = np.sqrt(((pal - want) ** 2).sum(1))
        d_w[~cand] = 1e9
        c = pal[int(np.argmin(d_w))].astype(np.uint8)
        out[y, x, :3] = c
        for k in range(1, thick):          # deeper into the arm: its pixels next to this one that are arm
            for dy, dx in ((0, -1), (-1, 0), (0, 1), (1, 0)):
                y2, x2 = y + dy * k, x + dx * k
                if 0 <= y2 < lab.shape[0] and 0 <= x2 < lab.shape[1] and arm[y2, x2] and not edge[y2, x2]:
                    out[y2, x2, :3] = c
    return out, lab


def tidy_cloth_edge(rgba, lab, names, neck_y):
    """Pass 9: the silhouette of the cloth parts (robe, cape, the torso below the neck) loses its 1 px spurs
    and gets its 1 px notches filled.  Only cloth is touched: the head (rows above the neck), weapons and
    every limb keep their pixels, so a face, a blade's point or a corner of a shield is not rounded.
    A spur: a cloth pixel with at most one opaque neighbour of the 8 (the end of a 1 px tail, which cannot disconnect anything).  A notch: a transparent pixel with at least
    three opaque 4-neighbours, two of them cloth and facing each other or the third; it takes the commonest
    colour of its cloth neighbours.  One pass of each, scanned in raster order on a copy: deterministic."""
    cloth_ids = [names.index(n) for n in ("robe", "cape", "torso") if n in names]
    if not cloth_ids:
        return rgba, lab
    H, W = lab.shape
    op = rgba[..., 3] > 0
    cl = np.isin(lab, cloth_ids)
    cl[:int(np.ceil(neck_y)) + 2] &= (lab[:int(np.ceil(neck_y)) + 2] != names.index("torso")) if "torso" in names else True
    pad = np.pad(op, 1)
    n4 = (pad[:-2, 1:-1].astype(int) + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:])
    out, lo = rgba.copy(), lab.copy()
    n8 = sum(pad[1 + dy:1 + dy + H, 1 + dx:1 + dx + W].astype(int) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)
    spur = cl & (n8 <= 1)
    out[spur] = 0
    lo[spur] = 0
    notch = ~op & (n4 >= 3)
    ys, xs = np.where(notch)
    for y, x in zip(ys, xs):
        if y == 0 or x == 0 or y >= H - 1 or x >= W - 1:
            continue
        nb = [(y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)]
        cn = [(a, b) for a, b in nb if cl[a, b] and not spur[a, b]]
        if len(cn) < 2:
            continue
        cols, cnt = np.unique(np.array([rgba[a, b] for a, b in cn]), axis=0, return_counts=True)
        out[y, x] = cols[np.argmax(cnt)]
        la = [lab[a, b] for a, b in cn]
        lo[y, x] = max(set(la), key=la.count)
    return out, lo


SPECK_MAX = 4              # px: a piece of the body this small and apart from the figure is dust


def drop_specks(rgba, lab, size=SPECK_MAX):
    """Pieces of the baked body of at most `size` px that touch nothing else (a hem's outline pixels
    the cloth left behind) are erased; a cleanup that only caught single pixels left 2-4 px
    crumbs (R24).  The biggest piece is never touched."""
    from .imgops import components
    cl, sizes = components(rgba[..., 3] > 0)
    if len(sizes) <= 1:
        return rgba, lab
    main = max(sizes, key=sizes.get)
    for k, n in sizes.items():
        if k != main and n <= size:
            rgba[cl == k] = 0
            lab[cl == k] = 0
    return rgba, lab


FAR_REFINE_PHASES = 16     # phases whose far forearm is measured on the pixels
FAR_REFINE_STEP = 5.0      # deg of elbow flexion added per round
FAR_REFINE_ROUNDS = 30


def refine_far_tuck(ch, gait, cloth):
    """Pixel-exact R27: render the walk's phases with the gear laid over, find the far forearm's
    pixels that show below the far hip's row and fold that phase's far elbow FAR_REFINE_STEP more,
    until none shows.  Neighbouring samples of the profile are lifted to the mean of their sides
    so the arm does not jerk.  Returns the rounds used."""
    from .gear import composite
    tol = checks.TOL_PX * ch.body_h / BODY_H
    m = len(gait.far_tucks)
    step = m // FAR_REFINE_PHASES
    for rnd in range(FAR_REFINE_ROUNDS):
        hit = []
        for i in range(FAR_REFINE_PHASES):
            p = i / FAR_REFINE_PHASES
            pose, contact = gait.pose(p)
            J = ch.rig.fk(pose)
            rgba4, lab4, names = render(ch, J, cloth=cloth, phase=p, contact=contact)
            rgba, lab = reduce(rgba4, lab4, ch.ss, ch.native)
            rgba, lab, names, _ = composite(ch, rgba, lab, names, J, cloth, p)
            ys, _ = np.where(lab == names.index("far_fore")) if "far_fore" in names else ([], [])
            row = float(ch.to_game(J["far.hip"])[1]) + 0.5 * tol
            if len(ys) and ys.max() > row:
                hit.append(i)
        if not hit:
            return rnd
        for i in hit:
            gait.far_tucks[i * step] += FAR_REFINE_STEP
        for i in hit:
            for d in range(1, step):
                for j in (i * step - d, i * step + d):
                    gait.far_tucks[j % m] = max(gait.far_tucks[j % m],
                                                gait.far_tucks[i * step] * (1 - d / step))
    return FAR_REFINE_ROUNDS


def bake_motion(ch, motion, n=None, gait=None):
    n = n or motion.frames
    gait = gait or Gait(ch.rig, motion)
    far_cover = any(g.slot in BACK_SLOTS for g in ch.gear)
    cloth = None
    if any(getattr(p, "kind", "rigid") != "rigid" for p in ch.parts.values()) or \
            any(g.slot == "cape" for g in ch.gear):
        from .cloth import ClothSim
        cloth = ClothSim(ch, gait)
    if far_cover and not hasattr(gait, "_tucked"):
        # R27: first from the joints (the wrist and the hand tip a forearm's thickness above the
        # hip line), then on the pixels: any phase whose far forearm still shows under the hip
        # line is folded 5 deg more until none does (refine_far_tuck)
        gait.solve_far_tuck(margin=-(FAR_HAND_CLEAR * ch.rig.body_height + ch.info["radius"]["fore"]))
        gait._tucked = True
        refine_far_tuck(ch, gait, cloth)
    frames = []
    for i in range(n + 1):           # frame n is the closing frame (phase 1.0), not output
        p = i / n
        pose, contact = gait.pose(p)
        J = ch.rig.fk(pose)
        rgba4, lab4, names = render(ch, J, cloth=cloth, phase=p, contact=contact)
        rgba, lab = reduce(rgba4, lab4, ch.ss, ch.native)
        rgba, lab = hide_far_behind_torso(rgba, lab, names)
        if getattr(motion, "far_hold", False):
            hp = ch.to_game(gear_mod.hand_point(J["far.elbow"], J["far.wrist"], gear_mod.hand_local(ch.rig)))
            rgba, lab = paint_far_hand(rgba, lab, names, hp, 1.0 * ch.info["radius"]["fore"] * ch.k, _far_hand_colour(ch))
        rgba, lab = drop_specks(rgba, lab)
        if TIDY_CLOTH:
            rgba, lab = tidy_cloth_edge(rgba, lab, names, ch.to_game(J["neck"])[1])
        if ARM_OUTLINE:
            rgba, lab = outline_near_arm(rgba, lab, names, ch.palette, max(1, int(round(ch.body_h / 56.0))))
        Jg = {k: ch.to_game(v) for k, v in J.items()}
        meta = {"phase": p, "joints": Jg, "contact": contact,
                "draw_order": names[1:], "labels": names,
                "digests": {nm: ch.parts[nm].digest() for nm in names[1:]},
                "pose": pose}
        body = None
        if ch.gear:               # gear is laid over the finished body frame, never mixed into it
            from .gear import composite
            body = {"rgba": rgba, "label": lab}
            rgba, lab, names, layers = composite(ch, rgba, lab, names, J, cloth, p)
            meta["labels"] = names
            meta["gear"] = layers
            meta["digests"].update({g.label: g.digest() for g in ch.gear})
        if cloth is not None:
            meta["cloth"] = {"cape_deg": cloth.cape_angle(p)}
        frames.append({"rgba": rgba, "label": lab, "meta": meta})
        if body is not None:
            frames[-1]["body"] = body
    closing = frames.pop()
    ctx = context(ch, motion, gait, n)
    ctx["closing"] = closing["meta"]
    ctx["closing_rgba"] = closing["rgba"]
    return frames, ctx


def _has_colours(img, cols):
    code = img[..., 0].astype(np.int64) * 65536 + img[..., 1].astype(np.int64) * 256 + img[..., 2]
    keys = np.asarray(cols, np.int64)
    keys = keys[:, 0] * 65536 + keys[:, 1] * 256 + keys[:, 2]
    return bool((np.isin(code, keys) & (img[..., 3] > 0)).any())


def _far_hand_colour(ch):
    """The far hand's colour: the commonest colour of the cut far forearm's pixels around the still's hand."""
    img = ch.parts["far_fore"].img
    a = img[..., 3] > 0
    j = ch.rig.j
    mid = (np.asarray(j["wrist"], float) + np.asarray(j["hand_tip"], float)) / 2
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    near = a & (np.hypot(xx + 0.5 - mid[0], yy + 0.5 - mid[1]) < 0.05 * ch.rig.body_height)
    px = img[near][:, :3] if near.any() else img[a][:, :3]
    cols, cnt = np.unique(px, axis=0, return_counts=True)
    lit = cols.sum(1) > 90
    if lit.any():
        cols, cnt = cols[lit], cnt[lit]
    return tuple(int(v) for v in cols[np.argmax(cnt)])


def _still_specks(ch):
    """R29: the number of isolated dark specks on light cloth that the still itself has (the same test as
    checks.speck_list, on the still, with the speck size of the bake scaled back to still px)."""
    img = ch.still
    a = img[..., 3] > 0
    if not a.any():
        return 0
    f = ch.body_h / ch.rig.body_height
    sk = ch.info.get("skin")
    keys = checks._colour_keys(sk) if sk is not None and len(sk) else None
    neck = ch.rig.j["neck"][1] + 0.02 * ch.rig.body_height
    n = len(checks.speck_list(img, a, int(neck), checks.SPECK_PX * (ch.body_h / 56.0 / 2.0) ** 2 / (f * f), keys))
    return n


def _sleeve_colours(ch):
    """The near upper arm's main colours (each at least 10 % of its pixels) that are not near any
    main colour of the torso (each at least 3 % of it): the sleeve's own (R28)."""
    def main(img, share):
        m = img[..., 3] > 0
        if not m.any():
            return np.zeros((0, 3))
        c, k = np.unique(img[m][:, :3], axis=0, return_counts=True)
        return c[k >= share * k.sum()].astype(float)
    if "near_upper" not in ch.parts or "torso" not in ch.parts:
        return []
    sl, to = main(ch.parts["near_upper"].img, 0.10), main(ch.parts["torso"].img, 0.03)
    keep = [tuple(int(v) for v in c) for c in sl
            if not len(to) or float(np.sqrt(((to - c) ** 2).sum(1)).min()) > SLEEVE_NEAR]
    return keep


SLEEVE_NEAR = 18.0       # RGB distance: a colour this close to one of the torso's is not the sleeve's


def context(ch, motion, gait, n):
    k = ch.k
    ff = ch.rig.data.get("foot_fit", {})
    # the hands' own colours, read from the two forearm parts (checks.arm_count)
    hc, hpx = set(), 0
    neck_y = int(ch.rig.j["neck"][1])
    body_imgs = [p.img[neck_y:] for nm, p in ch.parts.items()
                 if not (nm.endswith("_upper") or nm.endswith("_fore") or nm.startswith("gear:"))]
    for nm in ("near_fore", "far_fore"):
        if nm in ch.parts:
            c_, n_ = checks.hand_colours(ch.parts[nm].img, ch.rig.j["wrist"], ch.rig.j["hand_tip"],
                                         other=body_imgs,
                                         common=0.0 if nm == "far_fore" else None)
            hc |= c_
            hpx = max(hpx, n_)
    return {
        "hand_colours": hc, "hand_px": hpx, "body_h": ch.rig.body_height * k,
        "name": ch.name, "motion": motion.name, "n": n, "k": k,
        "lengths": {b: L * k for b, _, _, L in ch.rig.bone_pairs()},
        "bones": [(b, a, c) for b, a, c, _ in ch.rig.bone_pairs()],
        "rest_lean": ch.rig.rest["lean"],
        "ground": ch.foot_y, "facing": 1,
        "speed": gait.stride * k,                  # game px per cycle
        "travels": motion.travels,
        "stance": dict(motion.stance),
        "foot_len": float(np.hypot(*ch.rig.foot_local["toe"])) * k,
        "foot_px": float(ch.parts["near_foot"].mask.sum()) * k * k,
        "leg_width": 2 * ch.info["radius"]["shin"] * k,
        "fore_r": ch.info["radius"]["fore"] * k,
        "size_x": ch.body_h / BODY_H,
        "shin_back": ff.get("back", ch.info["radius"]["shin"]) * k,
        "shin_front": ff.get("front", ch.info["radius"]["shin"]) * k,
        "palette": ch.palette,
        "cut_digests": dict({nm: p.digest() for nm, p in ch.parts.items()},
                            **{g.label: g.digest() for g in ch.gear}),
        "rigid": [nm for nm in ch.parts if nm in ("torso", "back") or nm.startswith("gear:")]
        + [g.label for g in ch.gear],
        "gear": {g.label: g for g in ch.gear},
        "skin": ch.info.get("skin"),
        "sleeve_colours": _sleeve_colours(ch),
        "skinless_legs": [nm for nm in ("near_thigh", "near_shin", "near_foot", "far_thigh", "far_shin", "far_foot")
                          if nm in ch.parts and ch.info.get("skin") is not None and len(ch.info["skin"])
                          and not _has_colours(ch.parts[nm].img, ch.info["skin"])],
        "hand_local": [v * k for v in _hand_local(ch.rig)]
        if ch.gear else [0.0, 0.0],
        "still_specks": _still_specks(ch),
        "gear_min": {g.label: _gear_min(ch, g) for g in ch.gear},
        "gear_scale": {g.label: g.size * ch.rig.body_height * k / max(g.extent, 1.0) for g in ch.gear},
        "cloth": [nm for nm, p in ch.parts.items() if getattr(p, "kind", "rigid") != "rigid"],
        "gain": getattr(motion, "gain", 1.0),
        # arms exempt from the hang rule: a near arm carrying long gear is held steady
        "steady_arms": (["near"] if getattr(motion, "arm", 1.0) < 1.0 else []) + (["far"] if getattr(motion, "far_hold", False) else []),
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


def bake_all(ch, counts=(4, 8)):
    """Bake the walk at each frame count and gate it. Returns {n: (frames, ctx, fails)}."""
    motion = ch.walk_motion()
    gait = Gait(ch.rig, motion)
    out = {}
    for n in counts:
        frames, ctx = bake_motion(ch, motion, n, gait=gait)
        out[n] = (frames, ctx, checks.run_all(frames, ctx))
    return out


def write_outputs(ch, baked, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    meta_out = {"name": ch.name, "still_frame": ch.frame_index, "canvas": list(ch.canvas),
                "foot_y": ch.foot_y, "body_height_px": ch.body_h, "scale": ch.k, "motions": {}}
    if ch.grid is not None:
        meta_out["native_grid"] = ch.grid
    if ch.fit is not None:
        meta_out["fit"] = ch.fit
    for n, (frames, ctx, fails) in baked.items():
        tag = f"{ch.name}_walk{n}"
        save_png(strip(frames), os.path.join(out_dir, tag + "_r.png"))
        save_png(strip(frames, flip=True), os.path.join(out_dir, tag + "_l.png"))
        save_png(strip(frames), os.path.join(out_dir, tag + "_r_x4.png"), scale=4)
        ms = int(round(1000 / n))
        save_gif(frames, os.path.join(out_dir, tag + ".gif"), ms=ms)
        meta_out["motions"][f"walk{n}"] = {
            "frames": n, "speed_px_per_cycle": round(ctx["speed"], 3), "gain": round(ctx["gain"], 3),
            "ms_per_frame": ms, "checks": "ok" if not fails else fails}
    with open(os.path.join(out_dir, ch.name + ".json"), "w") as f:
        json.dump(meta_out, f, indent=1, default=float)
    export_parts(ch, out_dir)


def bake_character(still_path, joints_path, out_dir, motions=("walk",)):
    """Legacy entry (hand joints): bake the walk at 4 and 8 frames. Returns (ch, results)."""
    ch = Character(still_path, joints_path)
    baked = bake_all(ch)
    write_outputs(ch, baked, out_dir)
    results = {("walk", n): {"frames": fr, "ctx": ctx, "fails": fails}
               for n, (fr, ctx, fails) in baked.items()}
    return ch, results


PARENT = {"torso": None, "back": "torso", "cape": "torso", "robe": "torso",
          "near_upper": "torso", "near_fore": "near_upper",
          "near_thigh": "torso", "near_shin": "near_thigh", "near_foot": "near_shin",
          "far_upper": "torso", "far_fore": "far_upper", "far_thigh": "torso",
          "far_shin": "far_thigh", "far_foot": "far_shin"}


def export_parts(ch, out_dir):
    """Plain-file rig: one PNG per part (cropped) + rig.json with pivot, parent bone, draw
    order and bone lengths, so the parts can be packed into another runtime later."""
    d = os.path.join(out_dir, ch.name + "_parts")
    os.makedirs(d, exist_ok=True)
    rig = ch.rig
    parts = {}
    for i, name in enumerate(ch.order()):
        p = ch.parts[name]
        m = p.mask
        if not m.any():
            continue
        ys, xs = np.where(m)
        x0, y0 = int(xs.min()), int(ys.min())
        crop = p.img[y0:ys.max() + 1, x0:xs.max() + 1]
        fn = name.replace(":", "_") + ".png"
        Image.fromarray(crop, "RGBA").save(os.path.join(d, fn))
        side = "far" if name.startswith("far_") else "near"
        piv = rig.j[p.pivot].copy()
        parent = PARENT.get(name, side + "_fore" if p.attach == "hand" else "torso")
        parts[name] = {
            "png": fn, "draw": i, "origin_in_still": [x0, y0],
            "pivot_joint": p.pivot, "pivot_in_png": [float(piv[0] - x0), float(piv[1] - y0)],
            "bone": list(p.bone), "parent": parent, "sha1": p.digest(),
            "kind": getattr(p, "kind", "rigid"),
            "far_copy_of": name.replace("far_", "near_") if side == "far" else None,
        }
    if ch.gear:
        from .gear import export
        parts.update(export(ch, d))
    out = {"name": ch.name, "still_frame": ch.frame_index, "joints": rig.data["joints"],
           "ground_y": rig.ground_y, "lengths": rig.lengths,
           "far_shoulder_offset": rig.far_shoulder_offset.tolist(),
           "far_hip_offset": rig.far_hip_offset.tolist(),
           "rest_angles": rig.rest, "game_scale": ch.k, "parts": parts}
    with open(os.path.join(d, "rig.json"), "w") as f:
        json.dump(out, f, indent=1)
    return d

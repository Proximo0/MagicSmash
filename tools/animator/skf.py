"""Write a cut character as a SkelForm .skf (spec as far as public: SKF_SPEC.md).

UNVERIFIED: the public v0.9 spec does not state rotation units, the y axis direction, whether
a Vec2 is {x, y} or [x, y], the version string, keyframe element names, or how a texture sits
on its bone.  Each guess is a named constant below so it can be flipped after the file has been
opened once in the SkelForm editor (v0.9) on a PC and compared with one exported there.

Layout of the armature:
  root (pelvis, no texture)
   +- <part>_j : joint bone at the part's pivot (torso: pelvis; arm: shoulder / elbow; leg: hip /
   |             knee / ankle; cape: its top anchor), keyed with PosX/PosY/Rot per frame
   |   +- <part> : texture bone, a fixed offset from the joint to the texture's centre
   |              (TEX_ANCHOR = "center"), so the texture turns about the joint
Hierarchy follows the body: torso -> upper -> fore, torso -> thigh -> shin -> foot, torso ->
cape / robe.  The robe's row shear between the legs cannot be expressed as bones: it is
exported rigid with the torso (a mesh deform would be needed).  Positions are in still pixels
x EXPORT_SCALE; textures are the cut parts at still resolution (the game-size bake is done by
bake.py, not by the runtime).
"""
import io
import json
import math
import zipfile

import numpy as np
from PIL import Image

from .rig import screen_angle

SKF_VERSION = "0.9.0"      # NOT STATED: version string format
ROT_RADIANS = True         # NOT STATED: rot units (radians assumed, as most runtimes)
Y_UP = True                # NOT STATED: y axis; True = y up (y values negated from pixels)
VEC2_AS_DICT = True        # NOT STATED: {"x":..,"y":..} (True) or [x, y] (False)
EL_POSX, EL_POSY, EL_ROT = "PosX", "PosY", "Rot"   # only "PosX" is shown in the spec
TEX_ANCHOR = "center"      # NOT STATED: where a texture sits on its bone
EXPORT_SCALE = 1.0         # still px -> skf units
ATLAS_W = 1024             # atlas width (shelf packing)
PAD = 2                    # px between atlas entries

PARENT = {"torso": None, "cape": "torso", "robe": "torso",
          "near_upper": "torso", "near_fore": "near_upper",
          "near_thigh": "torso", "near_shin": "near_thigh", "near_foot": "near_shin",
          "far_upper": "torso", "far_fore": "far_upper", "far_thigh": "torso",
          "far_shin": "far_thigh", "far_foot": "far_shin"}


def _v(x, y):
    y = -y if Y_UP else y
    x, y = float(x) * EXPORT_SCALE, float(y) * EXPORT_SCALE
    return {"x": round(x, 3), "y": round(y, 3)} if VEC2_AS_DICT else [round(x, 3), round(y, 3)]


def _rot(deg):
    r = -deg if Y_UP else deg            # screen clockwise (y down) -> counter-clockwise (y up)
    return round(math.radians(r) if ROT_RADIANS else r, 5)


def _pack(images):
    """Shelf packing. images: name -> HxWx4. Returns (atlas array, name -> (x, y, w, h))."""
    order = sorted(images, key=lambda n: -images[n].shape[0])
    x = y = shelf = 0
    pos = {}
    for n in order:
        h, w = images[n].shape[:2]
        if x + w > ATLAS_W:
            x, y, shelf = 0, y + shelf + PAD, 0
        pos[n] = (x, y, w, h)
        x += w + PAD
        shelf = max(shelf, h)
    H = y + shelf
    atlas = np.zeros((max(H, 1), ATLAS_W, 4), np.uint8)
    for n, (x0, y0, w, h) in pos.items():
        atlas[y0:y0 + h, x0:x0 + w] = images[n]
    return atlas, pos


def _part_pose(ch, J, name, cape_deg=0.0):
    """(pivot in still px, rotation delta deg) of a part in posed still joints J."""
    rig = ch.rig
    p = ch.parts[name]
    side = "far" if name.startswith("far_") else "near"
    a, b = p.bone
    if a == "pelvis":
        pa, pb, piv = J["pelvis"], J["neck"], J["pelvis"]
    else:
        pa, pb, piv = J[side + "." + a], J[side + "." + b], J[side + "." + p.pivot]
    delta = screen_angle(pb - pa) - screen_angle(rig.j[b] - rig.j[a])
    src_piv = rig.j[p.pivot]
    if getattr(p, "kind", "rigid") == "cape":
        # the cape turns about its anchor: express the anchor in posed coords
        r = math.radians(delta)
        d = p.anchor - rig.j["pelvis"]
        piv = J["pelvis"] + np.array([math.cos(r) * d[0] - math.sin(r) * d[1],
                                      math.sin(r) * d[0] + math.cos(r) * d[1]])
        src_piv = p.anchor
        delta += cape_deg
    return np.asarray(piv, float), float(delta), np.asarray(src_piv, float)


def build(ch, frames, ctx):
    """Returns (armature dict, atlas RGBA array)."""
    names = [n for n in ch.order() if ch.parts[n].mask.any()]
    crops, boxes = {}, {}
    for n in names:
        m = ch.parts[n].mask
        ys, xs = np.where(m)
        x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
        crops[n] = ch.parts[n].img[y0:y1, x0:x1]
        boxes[n] = (x0, y0, x1, y1)
    atlas, pos = _pack(crops)
    one = {"x": 1.0, "y": 1.0} if VEC2_AS_DICT else [1.0, 1.0]
    bones = [{"id": 0, "name": "root", "pos": _v(0, 0), "rot": 0.0, "scale": one,
              "parent_id": -1, "tex": "", "zindex": 0, "hidden": False, "tint": [255, 255, 255, 255],
              "inverse_kinematics_id": -1, "visuals_id": -1, "physics_id": -1}]
    ids = {"root": 0}
    rest = {}
    rest_pose_J = {k: v for k, v in ch.rig.fk(ch.rig.rest_pose()).items()}
    for n in names:
        piv, _, src = _part_pose(ch, rest_pose_J, n)
        rest[n] = src
    # joint bones first (parents before children), then texture bones
    def depth(n):
        d, p = 0, PARENT.get(n)
        while p is not None:
            d, p = d + 1, PARENT.get(p)
        return d
    for n in sorted(names, key=depth):
        par = PARENT.get(n)
        while par is not None and par not in names:
            par = PARENT.get(par)
        pid = ids[par + "_j"] if par else 0
        ppos = rest[par] if par else ch.rig.j["pelvis"]
        lp = rest[n] - ppos
        ids[n + "_j"] = len(bones)
        bones.append({"id": len(bones), "name": n + "_j", "pos": _v(*lp), "rot": 0.0,
                      "scale": {"x": 1.0, "y": 1.0} if VEC2_AS_DICT else [1.0, 1.0],
                      "parent_id": pid, "tex": "", "zindex": 0, "hidden": False,
                      "tint": [255, 255, 255, 255], "inverse_kinematics_id": -1,
                      "visuals_id": -1, "physics_id": -1})
    for z, n in enumerate(names):
        x0, y0, x1, y1 = boxes[n]
        centre = np.array([(x0 + x1) / 2.0, (y0 + y1) / 2.0])
        off = centre - rest[n] if TEX_ANCHOR == "center" else np.array([x0, y0]) - rest[n]
        ids[n] = len(bones)
        bones.append({"id": len(bones), "name": n, "pos": _v(*off), "rot": 0.0,
                      "scale": {"x": 1.0, "y": 1.0} if VEC2_AS_DICT else [1.0, 1.0],
                      "parent_id": ids[n + "_j"], "tex": n, "zindex": z, "hidden": False,
                      "tint": [255, 255, 255, 255], "inverse_kinematics_id": -1,
                      "visuals_id": -1, "physics_id": -1})
    # atlas offsets are image pixels (top-left, y down) whatever Y_UP says
    textures = [{"name": n, "offset": {"x": pos[n][0], "y": pos[n][1]} if VEC2_AS_DICT else [pos[n][0], pos[n][1]],
                 "size": {"x": pos[n][2], "y": pos[n][3]} if VEC2_AS_DICT else [pos[n][2], pos[n][3]],
                 "atlas_idx": 0} for n in names]
    # keyframes: local pos / rot of every joint bone per frame
    kfs = []
    for fi, f in enumerate(frames):
        Jg = f["meta"]["joints"]
        J = {k: ch.from_game(v) for k, v in Jg.items()}
        cape = f["meta"].get("cloth", {}).get("cape_deg", 0.0)
        world = {n: _part_pose(ch, J, n, cape) for n in names}
        for n in names:
            piv, d, _ = world[n]
            par = PARENT.get(n)
            while par is not None and par not in names:
                par = PARENT.get(par)
            if par:
                ppiv, pd, _ = world[par]
                r = math.radians(-pd)
                q = piv - ppiv
                lp = np.array([math.cos(r) * q[0] - math.sin(r) * q[1],
                               math.sin(r) * q[0] + math.cos(r) * q[1]])
                ld = d - pd
            else:
                lp = piv - ch.rig.j["pelvis"]
                ld = d
            v = _v(*lp)
            vx, vy = (v["x"], v["y"]) if VEC2_AS_DICT else v
            for el, val in ((EL_POSX, vx), (EL_POSY, vy), (EL_ROT, _rot(ld))):
                kfs.append({"frame": fi, "bone_name": n + "_j", "element": el, "value": val,
                            "next_kf": -1, "start_handle": 0.333, "end_handle": 0.666})
    arm = {
        "version": SKF_VERSION, "baked_ik": False, "img_format": "PNG",
        "clear_color": [0, 0, 0, 0],
        "bones": bones,
        "animations": [{"id": "walk", "name": "walk", "fps": len(frames), "keyframes": kfs}],
        "atlases": [{"filename": "atlas0.png",
                     "size": {"x": atlas.shape[1], "y": atlas.shape[0]} if VEC2_AS_DICT
                     else [atlas.shape[1], atlas.shape[0]]}],
        "styles": [{"id": 0, "name": "default", "textures": textures}],
        "inverse_kinematics": [], "visuals": [], "physics": [],
    }
    return arm, atlas


def write_skf(ch, frames, ctx, path):
    arm, atlas = build(ch, frames, ctx)
    buf = io.BytesIO()
    Image.fromarray(atlas, "RGBA").save(buf, "PNG")
    readme = ("Written by tools/animator/skf.py from %s. UNVERIFIED against the SkelForm editor: "
              "rot units, y axis, Vec2 form, version string, element names and texture anchor are "
              "guesses (constants at the top of skf.py). The robe shear is exported rigid.\n" % ch.name)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("armature.json", json.dumps(arm, indent=1))
        z.writestr("atlas0.png", buf.getvalue())
        z.writestr("readme.md", readme)
    return path

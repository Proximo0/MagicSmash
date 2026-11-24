"""The town's buildings, modelled from primitives and rendered as ONE still each, like the sprites.

    python3 -I build_town.py -- <outdir> <art dir> [id ...]      (ids: hearth trainer bank smith merchants reader market
                                                               post trade board trial gate; none = all)

Same camera as build_hero.py / build_beast.py (orthographic, ELEV 20, 125.5 px per metre at render, 4x shrink by post.py
= 31.4 px per metre, the heroes' density), same material-ID pass and post.py. Each building is turned toward the camera
by its own `turn` (degrees off face-on). The picture is cropped to the building, symmetric about the building's centre
(that column is the ground point), the bottom edge is the lowest pixel, 2 px of clear border all round.
Home furniture and plaques (home_models.py) take their ids too (home_chair ... home_plaque_7; env HOME=1 = all of
them) and are written as <art dir>/ui_<id>.png, same camera and density.
The field's fixed features (field_models.py: field_gate field_heart field_waystone[_lit] field_altar[_lit]; env FIELD=1 = all)
are written as <art dir>/<id>.png (prop_models.py: field_prop_* ground props, env PROPS=1 = all), no ui_ prefix (the field loads them as art/field_<name>.png).
Writes <art dir>/ui_town_<id>.png.  env: SAMPLES (48), KEY, AMB
"""
import math
import os
import subprocess
import sys

import bpy
import numpy as np
if os.environ.get("RENDER_PYLIB"):  # Pillow for Blender's python (Blender ignores PYTHONPATH); render.sh installs it there
    sys.path.append(os.environ["RENDER_PYLIB"])
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import town_lib as L  # noqa: E402
import town_models as M  # noqa: E402
import home_models as H  # noqa: E402
import field_models as F  # noqa: E402
import prop_models as PM  # noqa: E402

E = os.environ.get
HERE = os.path.dirname(os.path.abspath(__file__))
PX_PER_M = 576 / 4.59       # the heroes' render density


def render(spec, raw):
    sc = L.STATE["sc"]
    root = L.STATE["root"]
    rx, ry = [(v + 7) // 8 * 8 for v in spec["res"]]
    root.rotation_euler = (0, 0, math.radians(70 - spec.get("turn", 35)))
    sc.render.engine = "CYCLES"
    sc.cycles.samples = int(E("SAMPLES", "48"))
    sc.cycles.use_denoising = False
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    col = sc.collection
    pivot = bpy.data.objects.new("pivot", None)
    col.objects.link(pivot)
    pivot.rotation_euler = (0, 0, math.radians(70))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    col.objects.link(cam)
    cam.parent = pivot
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(rx, ry) / PX_PER_M
    el = math.radians(20)
    cz = spec.get("cz", 3.0)
    cam.location = (0, -30 * math.cos(el), cz + 30 * math.sin(el))
    cam.rotation_euler = (math.pi / 2 - el, 0, 0)
    cam.data.clip_end = 200
    sc.camera = cam

    def sun(name, rot, power, colr):
        s = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        s.data.energy = power
        s.data.color = colr
        s.data.angle = math.radians(4)
        s.rotation_euler = [math.radians(a) for a in rot]
        s.parent = pivot
        col.objects.link(s)

    sun("key", (50, 0, 35), float(E("KEY", str(spec.get("key", 4.2)))), (0.82, 0.88, 1.0))
    sun("rim", (60, 0, 200), spec.get("rim", 2.0), (0.5, 0.6, 1.0))
    wd = bpy.data.worlds.new("w")
    sc.world = wd
    wd.use_nodes = True
    wd.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.32, 0.45, 1)
    wd.node_tree.nodes["Background"].inputs[1].default_value = float(E("AMB", str(spec.get("amb", 0.75))))

    mats = [m for m in bpy.data.materials if m.use_nodes and m.users]
    for k, m in enumerate(mats):
        nt = m.node_tree
        outn = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        em = nt.nodes.new("ShaderNodeEmission")
        em.name = "id_em"
        em.inputs["Color"].default_value = (((k + 1) * 8 % 256) / 255.0, ((k + 1) // 32 * 64 + 40) / 255.0, 0.5, 1)
        m["id_surface"] = outn.inputs["Surface"].links[0].from_node.name

    def id_mode(on):
        for m in mats:
            nt = m.node_tree
            outn = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
            nt.links.new((nt.nodes["id_em"] if on else nt.nodes[m["id_surface"]]).outputs[0], outn.inputs["Surface"])
        sc.cycles.samples = 1 if on else int(E("SAMPLES", "48"))
        sc.cycles.filter_width = 0.01 if on else 1.5
        sc.view_settings.view_transform = "Raw" if on else "Standard"

    os.makedirs(raw, exist_ok=True)
    sc.render.filepath = os.path.join(raw, "Still_00.png")
    bpy.ops.render.render(write_still=True)
    id_mode(True)
    sc.render.filepath = os.path.join(raw, "Still_00_id.png")
    bpy.ops.render.render(write_still=True)
    import json
    json.dump({"Still": 1}, open(os.path.join(raw, "meta.json"), "w"))


def finish(spec, bid, outdir, art):
    raw = os.path.join(outdir, "raw_" + bid)
    name = bid if bid.startswith(("home_", "field_")) else "town_" + bid
    subprocess.run([sys.executable, os.path.join(HERE, "post.py"), raw, os.path.join(outdir, name), name], check=True,
                   stdout=subprocess.DEVNULL, env=dict(os.environ, NOSHEET="1"))
    a = np.asarray(Image.open(os.path.join(outdir, name, name + "_still.png")).convert("RGBA"))
    ys, xs = np.nonzero(a[..., 3] > 0)
    cx = ((spec["res"][0] + 7) // 8 * 8) // 8
    half = max(cx - xs.min(), xs.max() + 1 - cx)
    box = (cx - half - 2, ys.min() - 2, cx + half + 2, ys.max() + 3)
    pad = np.zeros((a.shape[0] + 8, a.shape[1] + 8, 4), np.uint8)
    pad[4:-4, 4:-4] = a
    im = Image.fromarray(pad).crop((box[0] + 4, box[1] + 4, box[2] + 4, box[3] + 4))
    im.save(os.path.join(art, ("%s.png" if name.startswith("field_") else "ui_%s.png") % name))
    print(bid, im.size)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    outdir, art, ids = argv[0], argv[1], argv[2:] or list(M.BUILDERS)
    builders = dict(M.BUILDERS, **H.BUILDERS, **F.BUILDERS, **PM.BUILDERS)
    if not argv[2:] and E("HOME") == "1":   # HOME is also the home directory: only the literal 1 means furniture
        ids = list(H.BUILDERS)
    if not argv[2:] and E("FIELD"):
        ids = list(F.BUILDERS)
    if not argv[2:] and E("PROPS"):
        ids = list(PM.BUILDERS)
    for bid in ids:
        L.reset()
        spec = builders[bid]()
        raw = os.path.join(outdir, "raw_" + bid)
        render(spec, raw)
        finish(spec, bid, outdir, art)


main()

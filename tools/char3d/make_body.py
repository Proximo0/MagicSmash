"""Make one rigged body per race with MPFB (GPL code, CC0 body data) and export it as <race>.glb.

Run by Blender on a station (tools/station/jobs/charbody.sh):
    blender -b --factory-startup --python tools/char3d/make_body.py -- <mpfb_src> <out_dir> <race>[,<race>...]
The body is the generator's base mesh shaped by its sliders (and a few face/ear targets), shapes baked in, helper
geometry masked away, on the generator's "game_engine" rig. No skin, hair or clothes: gear and colour are added by the
bake. Prints one line per race: BODY race=.. verts=.. bones=.. bytes=..
"""
import os
import sys

import bpy

mpfb_src, out_dir, races = sys.argv[sys.argv.index("--") + 1:][:3]
sys.path.insert(0, mpfb_src)

# sliders 0..1 as the generator names them; extra = (target file under data/targets, weight)
RACES = {
    "human": dict(macro=dict(gender=1.0, age=0.5, muscle=0.7, weight=0.5, height=0.55, proportions=0.65), extra=[]),
    "elf": dict(macro=dict(gender=0.8, age=0.45, muscle=0.55, weight=0.35, height=0.75, proportions=0.8),
                extra=[("ears/l-ear-shape-pointed", 1.0), ("ears/r-ear-shape-pointed", 1.0),
                       ("ears/l-ear-scale-vert-incr", 0.8), ("ears/r-ear-scale-vert-incr", 0.8)]),
    "dwarf": dict(macro=dict(gender=1.0, age=0.6, muscle=0.9, weight=0.8, height=0.15, proportions=0.4),
                  extra=[("head/head-square", 0.5)]),
    "orc": dict(macro=dict(gender=1.0, age=0.5, muscle=1.0, weight=0.75, height=0.75, proportions=0.3),
                extra=[("chin/chin-prognathism-incr", 0.9), ("chin/chin-width-incr", 0.9), ("head/head-square", 0.7),
                       ("ears/l-ear-shape-pointed", 0.6), ("ears/r-ear-shape-pointed", 0.6)]),
}


def make(race):
    from mpfb.services.humanservice import HumanService
    from mpfb.services.targetservice import TargetService
    spec = RACES[race]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    macro = TargetService.get_default_macro_info_dict()
    macro.update(spec["macro"])
    body = HumanService.create_human(macro_detail_dict=macro)
    troot = os.path.join(mpfb_src, "mpfb", "data", "targets")
    for name, w in spec["extra"]:
        path = os.path.join(troot, name + ".target.gz")
        try:
            TargetService.load_target(body, path, weight=w)
        except Exception as e:  # a missing face target must not lose the body
            print("NOTE race=%s target %s not applied: %s" % (race, name, str(e)[:120]))
    TargetService.bake_targets(body)
    rig = HumanService.add_builtin_rig(body, "game_engine")
    body.name = "body_" + race
    out = os.path.join(out_dir, race + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True, export_animations=False,
                              export_morph=False, export_materials="NONE", export_texcoords=False, export_yup=True)
    print("BODY race=%s verts=%d bones=%d height=%.3f bytes=%d modifiers=%s" % (
        race, len(body.data.vertices), len(rig.data.bones), body.dimensions.z, os.path.getsize(out),
        ",".join(m.type for m in body.modifiers)))
    print("BONES race=%s %s" % (race, " ".join(b.name for b in rig.data.bones)))


import mpfb  # noqa: E402

mpfb.register()
os.makedirs(out_dir, exist_ok=True)
for r in races.split(","):
    if r not in RACES:
        print("NOTE unknown race " + r)
        continue
    try:
        make(r)
    except Exception as e:
        import traceback
        traceback.print_exc()
        print("BODYFAIL race=%s %s: %s" % (r, type(e).__name__, str(e)[:200]))

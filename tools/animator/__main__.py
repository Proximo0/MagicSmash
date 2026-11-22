"""CLI.
  python3 -m tools.animator bake samples/HR6.1_1.png --joints samples/HR6.1_1.json --out out/
  python3 -m tools.animator all [--out out/]          bake every sample with a JSON + contact sheet
  python3 -m tools.animator auto samples/HR6.1_1.png  print estimated joints JSON
  python3 -m tools.animator batch samples/stills --out out/batch   fit + gate + bake all stills
  python3 -m tools.animator spec --build human|elf|dwarf|orc --out DIR   pose layout picture,
                                   joints JSON and reference mannequin for a build (STILL_SPEC.md)
  python3 -m tools.animator spec --gear --out DIR     gear layout guides (box, anchor, up) + JSON
                                   for shield, one-hand weapon, two-hand weapon, staff, cape
  python3 -m tools.animator spec --example --out DIR  the worked example: synthetic body + gear
  python3 -m tools.animator spec --monster biped|quadruped|crawler|flyer|floater|construct|all --out DIR
                                   pose picture, joints JSON, reference mannequin and prompt per monster layout
  python3 -m tools.animator spec --monster-example --out DIR   synthetic creatures for every plan, baked and gated
  python3 -m tools.animator monsters <folder> --out DIR   bake and gate <kind>.png + <kind>.json (monsters.md, M1-M12)
  python3 -m tools.animator monsters --table          print monsters.md from monsters.json
Relative paths that do not exist from the current directory are taken from tools/animator/.
"""
import argparse
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def _in(p):
    return p if os.path.exists(p) or os.path.isabs(p) else os.path.join(HERE, p)


def _out(p):
    if os.path.isabs(p):
        return p
    if os.path.isdir(os.path.dirname(os.path.normpath(p)) or ".") and os.path.basename(os.getcwd()) == "animator":
        return os.path.abspath(p)
    ab = os.path.abspath(p)
    if ab.startswith(HERE + os.sep):       # already a path into tools/animator (from the repo root)
        return ab
    return os.path.join(HERE, p)


def _summary(ch, results):
    parts = []
    for (m, n), r in sorted(results.items()):
        parts.append(f"{m}{n} {'ok' if not r['fails'] else str(len(r['fails'])) + ' FAIL'}")
    return "checks " + ("ok" if all(not r["fails"] for r in results.values()) else "FAIL") + ": " + ", ".join(parts)


def main(argv=None):
    from .bake import bake_character
    from .sheet import contact_sheet
    ap = argparse.ArgumentParser(prog="tools.animator")
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("bake")
    b.add_argument("still")
    b.add_argument("--joints", required=True)
    b.add_argument("--out", default="out/")
    a = sub.add_parser("all")
    a.add_argument("--out", default="out/")
    au = sub.add_parser("auto")
    au.add_argument("still")
    bt = sub.add_parser("batch")
    bt.add_argument("stills", nargs="?", default="samples/stills")
    bt.add_argument("--out", default="out/batch")
    bt.add_argument("--no-skf", action="store_true")
    sp = sub.add_parser("spec")
    sp.add_argument("--build", choices=["human", "elf", "dwarf", "orc", "all"], default="all")
    sp.add_argument("--out", default="out/spec")
    sp.add_argument("--gear", action="store_true", help="write the gear layout guides instead")
    sp.add_argument("--example", action="store_true",
                    help="write the worked example (synthetic body + shield + hammer) into --out")
    sp.add_argument("--monster", choices=["biped", "quadruped", "crawler", "flyer", "floater", "construct", "all"],
                    help="write the monster pose layouts of a body plan instead")
    sp.add_argument("--monster-example", action="store_true",
                    help="write, bake and gate one synthetic creature per plan into --out")
    mn = sub.add_parser("monsters")
    mn.add_argument("stills", nargs="?")
    mn.add_argument("--out", default="out/monsters")
    mn.add_argument("--table", action="store_true")
    args = ap.parse_args(argv)
    if args.cmd == "monsters":
        from . import monster, monster_example
        if args.table:
            print(monster.table_md())
            return 0
        acc, rej = monster_example.run_folder(_in(args.stills), _out(args.out))
        return 1 if rej else 0
    if args.cmd == "spec" and (args.monster or args.monster_example):
        from . import monster_example
        if args.monster:
            for k, p in monster_example.write_spec(args.monster, _out(args.out)).items():
                print(f"monster {k}: {p}_pose.png _joints.json _reference.png _prompt.txt")
            return 0
        acc, rej = monster_example.write_examples(_out(args.out))
        print("examples accepted:", ", ".join(acc), "| refused:", ", ".join(rej) or "none")
        return 1 if rej else 0
    if args.cmd == "spec":
        from . import spec
        if args.gear:
            for kind, (p, j) in spec.write_gear(_out(args.out)).items():
                print(f"gear {kind}: {p} {j}")
            return 0
        if args.example:
            print("example:", spec.write_example(_out(args.out)))
            return 0
        for b in (list(spec.BUILDS) if args.build == "all" else [args.build]):
            for kind, p in spec.write(b, _out(args.out)).items():
                print(f"{b} {kind}: {p}")
        return 0
    if args.cmd == "batch":
        from .batch import run
        acc, rej = run(_in(args.stills), _out(args.out), skf=not args.no_skf)
        return 1 if rej else 0
    if args.cmd == "auto":
        from .cut import auto_joints, load_still
        still, _, _ = load_still(_in(args.still))
        print(json.dumps(auto_joints(still), indent=1))
        return 0
    jobs = []
    if args.cmd == "bake":
        jobs = [(_in(args.still), _in(args.joints))]
    else:
        for j in sorted(glob.glob(os.path.join(HERE, "samples", "*.json"))):
            png = j[:-5] + ".png"
            if os.path.exists(png):
                jobs.append((png, j))
    out = _out(args.out)
    entries, bad = [], 0
    for png, js in jobs:
        t = time.time()
        ch, res = bake_character(png, js, out)
        s = _summary(ch, res)
        print(f"{ch.name}: {s} ({time.time() - t:.1f}s)")
        for r in res.values():
            for f in r["fails"][:20]:
                print("   ", f)
        bad += any(r["fails"] for r in res.values())
        entries.append((ch.name, png, res[("walk", 8)]["frames"], s))
    if args.cmd == "all":
        print("contact sheet:", contact_sheet(entries, os.path.join(out, "contact.png")))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

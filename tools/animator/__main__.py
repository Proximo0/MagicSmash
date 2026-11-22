"""CLI.
  python3 -m tools.animator bake samples/HR6.1_1.png --joints samples/HR6.1_1.json --out out/
  python3 -m tools.animator all [--out out/]          bake every sample with a JSON + contact sheet
  python3 -m tools.animator auto samples/HR6.1_1.png  print estimated joints JSON
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
    args = ap.parse_args(argv)
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

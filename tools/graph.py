#!/usr/bin/env python3
"""Code graph: which script names which class or autoload. Usage: tools/graph.sh [Name ...]
No argument: one line per class or autoload, most-used first:  Name path <-users: a b c
With names: for each, what it uses and who uses it. Find the files a change touches without reading them.
A name counts as used when it appears as a whole word outside comments and strings; inner classes and
dynamic calls are not followed."""
import os, re, sys

def scripts():
    for top in ("game", "tools", "tests"):
        for d, _dirs, files in os.walk(top):
            for f in sorted(files):
                if f.endswith(".gd"):
                    yield os.path.join(d, f)

def strip(src):
    src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    src = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", src)
    return re.sub(r"#[^\n]*", "", src)

def main():
    owner = {}  # name -> path
    for line in open("project.godot", encoding="utf-8"):
        m = re.match(r'(\w+)="\*?res://(.+\.gd)"', line)
        if m:
            owner[m.group(1)] = m.group(2)
    body = {}
    for p in scripts():
        raw = open(p, encoding="utf-8").read()
        m = re.search(r"^class_name\s+(\w+)", raw, re.M)
        if m:
            owner[m.group(1)] = p
        body[p] = set(re.findall(r"\b[A-Z]\w*\b", strip(raw)))
    name_of = {p: n for n, p in owner.items()}
    uses = {p: sorted(n for n in words if n in owner and owner[n] != p) for p, words in body.items()}
    users = {n: [] for n in owner}
    for p, ns in uses.items():
        for n in ns:
            users[n].append(name_of.get(p, os.path.basename(p)[:-3]))
    want = sys.argv[1:]
    if not want:
        for n in sorted(owner, key=lambda k: (-len(users[k]), k)):
            print("%s %s <-%d: %s" % (n, owner[n], len(users[n]), " ".join(sorted(users[n]))))
        print("GRAPH names=%d scripts=%d" % (len(owner), len(body)))
        return 0
    rc = 0
    for n in want:
        if n not in owner:
            print("graph: no class or autoload named %s" % n, file=sys.stderr)
            rc = 2
            continue
        print("%s %s" % (n, owner[n]))
        print("  uses: %s" % " ".join(uses.get(owner[n], [])))
        print("  used by: %s" % " ".join(sorted(users[n])))
    return rc

sys.exit(main())

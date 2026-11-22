"""Import art from an art-raw checkout into realm/client/art/ under the client's file names.
usage: import.py ARTRAW_DIR [--out realm/client/art] [--min-score 0.6] [--commit SHA] [--dry-run]
ARTRAW_DIR holds clean/<id>_<n>.png (or clean/<id>.png), scores.json (ranks per id; see best_try for the shapes taken)
and best/ + sheets/ (not read). Per id of game_names.tsv that the client loads: the top-ranked clean sprite is
checked (RGBA, size, walk strips 4 cells at 45/56/62 px by race) and written as <game_name>.png. A walk sheet that
clean/ holds uncut is cut into 4 frames by frames.py. Skipped and listed: no sprite, score under the threshold, bad
size. Never overwritten: ids or game names listed in OUT/locked.txt (one per line, # comments). Writes OUT/IMPORTED.md.
python3 + numpy/PIL/scipy only."""
import argparse, json, os, re, subprocess, sys, tempfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
HEIGHTS = {"human": 56, "elf": 56, "dwarf": 45, "orc": 62}
MAX_SIDE = 256


def load_names():
    rows = {}
    for ln in open(os.path.join(HERE, "game_names.tsv")):
        p = ln.rstrip("\n").split("\t")
        if len(p) == 4 and p[3] == "yes":
            rows[p[0]] = p[2]
    return rows


def load_locked(out):
    p = os.path.join(out, "locked.txt")
    s = set()
    if os.path.exists(p):
        for ln in open(p):
            ln = ln.split("#")[0].strip()
            if ln:
                s.add(ln)
    return s


def tries_of(v):
    """{try: score} from the shapes scores.json may take: {"1": 0.8}, {"best": n, "ranking": [{try, score}]}, [{try, score}], a number."""
    out = {}
    if isinstance(v, dict):
        rk = v.get("ranking") or v.get("tries") or v.get("scores")
        if rk is not None:
            return tries_of(rk)
        for k, s in v.items():
            if isinstance(s, (int, float)) and str(k).isdigit():
                out[int(k)] = float(s)
            elif isinstance(s, dict) and "score" in s and str(k).isdigit():
                out[int(k)] = float(s["score"])
    elif isinstance(v, list):
        for t in v:
            if isinstance(t, dict) and "score" in t:
                out[int(t.get("try", t.get("n", 0)))] = float(t["score"])
    elif isinstance(v, (int, float)):
        out[1] = float(v)
    return out


def read_scores(path):
    raw = json.load(open(path))
    res = {}
    for k, v in raw.items():
        m = re.match(r"^(.+)_(\d)(?:\.png)?$", k)   # flat "<id>_<n>": score
        if m and isinstance(v, (int, float, dict)) and not (isinstance(v, dict) and "ranking" in v):
            res.setdefault(m.group(1), {}).update(tries_of({m.group(2): v}))
        else:
            res.setdefault(k, {}).update(tries_of(v))
    return res


def find_clean(clean, id_, n):
    for fn in (f"{id_}_{n}.png", f"{id_}.png"):
        p = os.path.join(clean, fn)
        if os.path.exists(p):
            return p
    return None


def race_height(game):
    m = re.match(r"hero_([a-z]+)_", game)
    return HEIGHTS.get(m.group(1), 56) if m else 56


def prepare_walk(src, game, tmp, h):
    """The 4-cell strip: the sprite itself when it already is one, else cut with frames.py."""
    im = Image.open(src)
    if im.mode == "RGBA" and im.height == h and im.width % 4 == 0 and im.getchannel("A").getextrema()[0] == 0:
        return src, None
    base = game[:-5]
    env = dict(os.environ, PIXSNAP_PALETTE=os.path.join(HERE, "realm_palette.hex"))
    r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "frames.py"), src, tmp, base, "4", str(h)],
                       capture_output=True, text=True, env=env)
    f = os.path.join(tmp, base + "_walk.png")
    if r.returncode != 0 or not os.path.exists(f):
        return None, "frames.py failed: " + (r.stderr.strip().splitlines() or ["?"])[-1]
    return f, None


def check(path, game, h):
    im = Image.open(path)
    if im.mode != "RGBA":
        return "not RGBA"
    w, ht = im.size
    if w > MAX_SIDE * 4 or ht > MAX_SIDE or w < 4 or ht < 4:
        return f"odd size {w}x{ht}"
    if im.getchannel("A").getextrema()[0] == 255:
        return "no transparency"
    if game.endswith("_walk") and (ht != h or w % 4):
        return f"strip {w}x{ht}, want 4 cells x {h} tall"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("--out", default=os.path.join(HERE, "..", "..", "realm", "client", "art"))
    ap.add_argument("--min-score", type=float, default=0.6)
    ap.add_argument("--commit", default="")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    clean = os.path.join(a.raw, "clean")
    sp = os.path.join(a.raw, "scores.json")
    if not os.path.isdir(clean) or not os.path.exists(sp):
        print("IMPORT nothing: no clean/ or scores.json in", a.raw)
        return 0
    commit = a.commit or subprocess.run(["git", "-C", a.raw, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip() or "unknown"
    names, scores, locked = load_names(), read_scores(sp), load_locked(a.out)
    done, skipped = [], []
    os.makedirs(a.out, exist_ok=True)
    for id_, game in sorted(names.items()):
        t = scores.get(id_)
        if not t:
            continue
        if id_ in locked or game in locked or game.replace("_walk", "") in locked:
            skipped.append((id_, game, "locked"))
            continue
        for n in sorted(t, key=lambda k: -t[k]):    # top-ranked try that has a clean file
            src = find_clean(clean, id_, n)
            if src:
                break
        else:
            skipped.append((id_, game, "no clean file"))
            continue
        score = t[n]
        if score < a.min_score:
            skipped.append((id_, game, f"score {score:.2f} < {a.min_score}"))
            continue
        h = race_height(game)
        with tempfile.TemporaryDirectory() as tmp:
            f, err = (prepare_walk(src, game, tmp, h) if game.endswith("_walk") else (src, None))
            err = err or (check(f, game, h) if f else "no file")
            if err:
                skipped.append((id_, game, err))
                continue
            dst = os.path.join(a.out, game + ".png")
            data = open(f, "rb").read()
            if not a.dry_run and not (os.path.exists(dst) and open(dst, "rb").read() == data):
                open(dst, "wb").write(data)
        done.append((id_, game, score, n))
    if not a.dry_run:
        # keep earlier rows of ids not seen this time (their files are still there)
        old = {}
        mp = os.path.join(a.out, "IMPORTED.md")
        if os.path.exists(mp):
            for ln in open(mp):
                c = [x.strip() for x in ln.strip().strip("|").split("|")]
                if len(c) == 4 and c[0] not in ("id", "---") and not c[0].startswith("-"):
                    old[c[0]] = c
        for i, g, s, n in done:
            old[i] = [i, g, f"{s:.2f}", commit]
        with open(mp, "w") as fh:
            fh.write("# Imported art\n\nWritten by tools/art/import.py from the art-raw branch. Do not edit; list ids in locked.txt to keep a hand-approved file.\n\n")
            fh.write("| id | game name | score | source commit |\n| --- | --- | --- | --- |\n")
            for k in sorted(old):
                fh.write("| " + " | ".join(old[k]) + " |\n")
    for i, g, why in skipped:
        print(f"skip {i} {g}: {why}")
    print(f"IMPORT written={len(done)} skipped={len(skipped)} min_score={a.min_score} commit={commit}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

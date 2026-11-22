"""Two-phase art runner.
Phase A (SDXL + pixel LoRA + OpenPose adapter): a pose-guided layout sheet for every walk/action id -> layouts/<id>.png.
Phase B (FLUX.2-klein-4B, 4-bit, no LoRA): every id in queue order -> raw/<id>_<n>.png
  walk/action: Klein redraws the layout (keeps poses, adds the detailed character); one/icon/tile/painted: Klein direct.
Then the same keying, checks, must-trait scoring, scores.json, done.txt and pushes as runner.py.
Restartable at any point; layouts and finished ids are skipped. Stop: STOP file (stop_runner.ps1)."""
import gc, json, os, sys, time, traceback, zlib
from pathlib import Path
sys.path.insert(0, r"D:\projects\hh_art")
import runner as R   # shared: paths, queue, log/status, push, record_score, key/check helpers, SDXL Gen
import numpy as np
from PIL import Image

ROOT = R.ROOT
LAYOUTS = ROOT / "layouts"
KLEIN_SIZES = {"walk": (1024, 576), "one": (768, 768), "icon": (512, 512), "tile": (512, 512)}
BONUS = 2   # walk/action: up to 2 extra tries when none of the normal tries passed (else the drifting sheet is kept)
TRIES = {"walk": 3, "action": 3, "one": 3, "icon": 2, "tile": 1, "painted": 2}
CONSIST_MAX = 0.14   # calibrated: consistent sheets 0.03-0.10, a frame with a red cloak 0.16


# ---------- keying: sampled border colour, hue/chroma distance (Klein's magenta is a gradient) ----------
def key_border(img, hue_tol=28.0):
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    mx, mn = a.max(-1), a.min(-1); c = mx - mn
    hue = np.zeros_like(mx)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    nz = c > 1e-6
    hr = nz & (mx == r); hg = nz & (mx == g) & ~hr; hb = nz & ~hr & ~hg
    hue[hr] = ((g - b)[hr] / c[hr]) % 6; hue[hg] = (b - r)[hg] / c[hg] + 2; hue[hb] = (r - g)[hb] / c[hb] + 4
    hue *= 60.0
    border = np.concatenate([hue[0], hue[-1], hue[:, 0], hue[:, -1]])
    bc = np.concatenate([c[0], c[-1], c[:, 0], c[:, -1]])
    h0 = float(np.median(border)); c0 = float(np.median(bc))
    dh = np.abs(((hue - h0) + 180) % 360 - 180)
    near = (dh < hue_tol) & (c > max(0.12, 0.45 * c0))
    from scipy import ndimage
    lab, _ = ndimage.label(near)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    m = np.isin(lab, list(edge))
    lab2, k2 = ndimage.label(near & ~m)  # enclosed magenta pockets (between legs, under arms) the border flood misses
    if k2:
        sizes = np.bincount(lab2.ravel())[1:]
        m |= np.isin(lab2, 1 + np.nonzero(sizes >= 12)[0])
    m = ndimage.binary_dilation(m, iterations=1) & (near | (c > 0.5 * c0) & (dh < hue_tol * 1.5))  # eat the fringe
    ring = ndimage.binary_dilation(m, iterations=2) & ~m  # despill: pull magenta tint out of the 2 px next to the key
    spill = np.clip(np.minimum(a[..., 0], a[..., 2]) - a[..., 1], 0, None) * ring
    a = a.copy(); a[..., 0] -= spill; a[..., 2] -= spill
    out = (np.clip(a, 0, 1) * 255).astype(np.uint8); out[m] = (255, 0, 255)
    return Image.fromarray(out), float(m.mean())


def frame_consistency(img, n):
    """Max L1 distance (0..1) between each frame's figure colour histogram and the median histogram."""
    a = np.asarray(img.convert("RGB"))
    fg = ~((a[..., 0] > 240) & (a[..., 1] < 20) & (a[..., 2] > 240))
    w = a.shape[1]; hs = []
    for i in range(n):
        s = a[:, int(w * i / n):int(w * (i + 1) / n)][fg[:, int(w * i / n):int(w * (i + 1) / n)]]
        if len(s) < 50: return 1.0
        q = (s // 64).astype(int); idx = q[:, 0] * 16 + q[:, 1] * 4 + q[:, 2]
        h = np.bincount(idx, minlength=64).astype(np.float32); hs.append(h / h.sum())
    med = np.median(np.stack(hs), 0); med /= med.sum()
    return float(max(np.abs(h - med).sum() / 2 for h in hs))


# ---------- prompts for Klein (natural language; queue_sd sd_prompt with weights stripped) ----------
def klein_prompt(e):
    import ab_klein as K
    s = K.subject(e); k = e.get("kind")
    bg = "on a flat solid bright magenta (#FF00FF) background"
    if e.get("style") == "painted": return s
    if k == "walk":
        return (f"Redraw this pixel art walk-cycle sprite sheet keeping exactly the same four poses, positions and sizes, "
                f"{bg}, as: {s}. The same character with the same outfit and colours in all four frames, detailed 16-bit pixel art.")
    if k == "action":
        n = len(__import__("walk").ACTIONS[e["pose"]])
        return (f"Redraw this pixel art sprite row keeping exactly the same {n} pose{'s' if n > 1 else ''}, positions and sizes, "
                f"{bg}, as: {s}. The same character with the same outfit and colours in every frame, detailed 16-bit pixel art.")
    if k == "icon": return f"pixel art game item icon: {s}. One single object, whole, centred, large, {bg}."
    if k == "tile": return f"pixel art seamless top-down ground texture filling the whole picture edge to edge: {s}."
    return f"pixel art game sprite: {s}. One single figure, whole, centred, filling most of the picture, {bg}."


def klein_size(e):
    if e.get("style") == "painted" or e.get("kind") == "action":
        w, h = e.get("size") or (1024, 1024)
        k = min(1.0, (1024 * 1024 / (w * h)) ** 0.5) if e.get("style") == "painted" else max(1.0, (512 * 512 * 2 / (w * h)) ** 0.5)
        return int(w * k) // 16 * 16, int(h * k) // 16 * 16
    return KLEIN_SIZES.get(e.get("kind"), (768, 768))


# ---------- phase A ----------
LAYOUT_TRIES = 4
REPLACED = ROOT / "replaced"
LAYOUT_REDO = ROOT / "layout_redo.txt"   # walk/action ids whose Klein pictures all failed: layout redrawn once


def redo_layouts(eids):
    """Move each id's layout and pictures aside (replaced/), mark its tries stale, un-done it; phase A then redraws the layout."""
    (REPLACED / "layouts").mkdir(parents=True, exist_ok=True); (REPLACED / "orig").mkdir(exist_ok=True)
    sp = ROOT / "scores.json"; sc = json.loads(sp.read_text(encoding="utf-8")) if sp.exists() else {}
    for eid in eids:
        lp = LAYOUTS / f"{eid}.png"
        if lp.exists(): lp.replace(REPLACED / "layouts" / lp.name)
        for ts in sc.get(eid, {}).values():
            for t in ts: t["stale"] = True
        for f in list(R.RAW.glob(f"{eid}_*.png")) + list((R.RAW / "orig").glob(f"{eid}_*.png")):
            f.replace((REPLACED / "orig" if f.parent.name == "orig" else REPLACED) / f.name)
    sp.write_text(json.dumps(sc, indent=0), encoding="utf-8")
    for p in (R.DONE, R.FAILED):
        if p.exists(): p.write_text("".join(i + "\n" for i in p.read_text(encoding="utf-8").split() if i not in eids), encoding="utf-8")
    R.log(f"layouts to redraw: {sorted(eids)}")


def phase_a(q):
    need = [e for e in q if e.get("kind") in ("walk", "action") and not (LAYOUTS / f"{e['id']}.png").exists()]
    if not need: return
    R.log(f"phase A: {len(need)} pose layouts to make (SDXL)")
    LAYOUTS.mkdir(exist_ok=True)
    gen = R.Gen(1.0, 8, 1.0, True)
    import walk as W
    for e in need:
        if R.STOP.exists(): return
        eid = e["id"]; best = None
        t0 = 2 if (REPLACED / "layouts" / f"{eid}.png").exists() else 0  # a redrawn layout starts with new seeds
        for t in range(t0, t0 + LAYOUT_TRIES):
            try:
                pose = e.get("pose") if e["kind"] == "action" else None
                img = gen(R.sd_prompt(e), e.get("shape", "s"), walk=e["kind"] == "walk", height=e.get("scale") or e.get("height"),
                          strong=True, negative=e.get("negative"), seed=zlib.crc32(f"L/{eid}/{t}".encode()), action=pose, size=e.get("size"))
                img, frac = R.key_magenta(img)
                ok, sc, notes = W.check_sheet(img) if not pose else W.check_frames(img, len(W.ACTIONS[pose]))
                if not pose:  # walk layout: the figure must stay the same in all 4 frames, or Klein copies the drift
                    cd = frame_consistency(img, 4)
                    if cd > CONSIST_MAX: ok, sc = False, sc - (cd - CONSIST_MAX) * 2
                if best is None or sc > best[0]: best = (sc, img)
                if ok: break
            except Exception as ex:
                R.log(f"layout {eid} error: {ex}"); gen.torch.cuda.empty_cache()
        if best: best[1].save(LAYOUTS / f"{eid}.png"); R.log(f"layout {eid} ok")
    del gen; gc.collect()
    import torch; torch.cuda.empty_cache()


# ---------- phase B ----------
def phase_b(q, count=4, push_every=20):
    import torch, walk as W, score as S, ab_klein as K
    os.environ["AB_NOLORA"] = "1"
    pipe = K.load("sprite"); R.log("phase B: Klein loaded")
    done = R.read_set(R.DONE) | R.read_set(R.FAILED)
    todo = [e for e in q if e["id"] not in done]
    since, n_ids = 0, 0
    try: prior = json.loads((ROOT / "scores.json").read_text(encoding="utf-8"))
    except Exception: prior = {}
    for e in todo:
        if R.STOP.exists(): R.log("STOP file found, stopping"); break
        eid, kind = e["id"], e.get("kind"); t0 = time.time(); ok_all = True
        painted = e.get("style") == "painted"; keyed = kind != "tile" and not painted
        layout = None
        if kind in ("walk", "action"):
            lp = LAYOUTS / f"{eid}.png"
            if not lp.exists(): R.log(f"{eid}: no layout yet, skipped this pass"); continue
            layout = Image.open(lp).convert("RGB")
        w, h = klein_size(e) if kind != "walk" else KLEIN_SIZES["walk"]
        prompt = klein_prompt(e); must = e.get("must") or []
        nfr = 4 if kind == "walk" else (len(W.ACTIONS[e["pose"]]) if kind == "action" else 1)
        for n in range(1, count + 1):
            f = R.RAW / f"{eid}_{n}.png"
            if f.exists(): continue
            best = None
            t_start = len(prior.get(eid, {}).get(str(n), []))  # a redraw continues with new seeds
            n_tries = TRIES.get(kind, 2) + (BONUS if kind in ("walk", "action") else 0)
            for t in range(t_start, t_start + n_tries):
                if t - t_start >= TRIES.get(kind, 2) and best is not None and best[3]: break
                try:
                    g = torch.Generator("cuda").manual_seed(zlib.crc32(f"K/{eid}/{n}/{t}".encode()))
                    kw = dict(prompt=prompt, width=w, height=h, num_inference_steps=4, guidance_scale=1.0, generator=g)
                    if layout is not None: kw["image"] = layout.resize((w, h))
                    orig = pipe(**kw).images[0]; img, frac = (key_border(orig) if keyed else (orig, 1.0))
                    if kind == "walk": good, sc, notes = W.check_sheet(img, min_leg_diff=0.12)
                    elif kind == "action": good, sc, notes = W.check_frames(img, nfr)
                    elif kind == "one": good, sc, notes = W.check_single(img)
                    else: good, sc, notes = True, 0.0, ""
                    if keyed:
                        a = np.asarray(img); bd = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
                        edge = float(((bd[:, 0] > 240) & (bd[:, 1] < 20) & (bd[:, 2] > 240)).mean())
                        if edge < 0.93: good, sc, notes = False, sc - 0.6, notes + f" edge-magenta {edge:.0%}"
                    if nfr > 1:
                        cd = frame_consistency(img, nfr); notes += f" consist {cd:.2f}"
                        if cd > CONSIST_MAX: good, sc = False, sc - (cd - CONSIST_MAX) * 2
                    ts = {}
                    if must and kind != "tile":
                        ts = S.trait_scores(orig, must, "walk" if nfr > 1 else "one"); miss = S.misses(ts)
                        sc += sum(ts.values()) / max(1, len(ts))
                        if len(miss) > max(1, len(ts) // 2): good = False
                        if miss: notes += f" missing {miss}"
                    R.record_score(eid, n, t + 1, good, sc, ts, notes)
                    R.log(f"{eid}_{n} try {t+1}: {'ok' if good else 'reject'}{notes}")
                    if best is None or (good, sc) > (best[3], best[0]): best = (sc, img, orig, good)
                    if good: break
                except Exception as ex:
                    R.log(f"{eid}_{n} error: {type(ex).__name__}: {str(ex)[:200]}"); torch.cuda.empty_cache(); time.sleep(5)
            if best is None: ok_all = False; continue
            if keyed: (R.RAW / "orig").mkdir(exist_ok=True); best[2].save(R.RAW / "orig" / f.name)
            best[1].save(f)
        dt = time.time() - t0
        if kind in ("walk", "action") and not any(t.get("ok") for ts in json.loads((ROOT / "scores.json").read_text(encoding="utf-8")).get(eid, {}).values() for t in ts if not t.get("stale")) \
                and not (REPLACED / "layouts" / f"{eid}.png").exists():
            with open(LAYOUT_REDO, "a", encoding="utf-8") as fh: fh.write(eid + "\n")  # every picture failed: the layout is suspect
        with open(R.DONE if ok_all else R.FAILED, "a", encoding="utf-8") as fh: fh.write(eid + "\n")
        n_ids += 1; since += 1
        R.log(f"{eid} {'done' if ok_all else 'FAILED'} in {dt:.0f}s ({dt / count:.1f}s/picture) [{e.get('name', '')}]")
        R.status(f"RUNNING pid={os.getpid()} last={eid} {len(todo) - n_ids} ids left, {dt / count:.1f}s/picture")
        if since >= push_every: R.push(f"through {eid}"); since = 0
    return n_ids


# Every model repo this runner loads; the start refuses unless licences.json clears all of them.
LOADS = ["stabilityai/stable-diffusion-xl-base-1.0", "madebyollin/sdxl-vae-fp16-fix", "nerijs/pixel-art-xl",
         "latent-consistency/lcm-lora-sdxl", "TencentARC/t2i-adapter-openpose-sdxl-1.0",
         "black-forest-labs/FLUX.2-klein-4B", "google/siglip-base-patch16-224"]


def main():
    __import__("licence_check").check_all(LOADS)
    q = R.load_queue()
    R.log(f"runner2 start: {len(q)} ids in queue, pid={os.getpid()}")
    R.status(f"RUNNING pid={os.getpid()} phase A")
    phase_a(q)
    if R.STOP.exists():
        R.status("STOPPED during phase A"); R.push("stop"); return
    phase_b(q)
    redo = R.read_set(LAYOUT_REDO) if LAYOUT_REDO.exists() else set()
    if redo and not R.STOP.exists():  # one more round for ids whose pictures all failed: new layout, then Klein again
        import torch; gc.collect(); torch.cuda.empty_cache()
        redo_layouts(redo); LAYOUT_REDO.unlink()
        phase_a(q)
        if not R.STOP.exists(): phase_b(q)
    left = [x for x in R.load_queue() if x["id"] not in R.read_set(R.DONE) | R.read_set(R.FAILED)]
    R.status(("FINISHED" if not left else "STOPPED") + f" {len(left)} ids left")
    R.push("final" if not left else "stop"); R.log("exit")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        R.log("FATAL " + traceback.format_exc()); R.status("CRASHED, see runner.log"); raise

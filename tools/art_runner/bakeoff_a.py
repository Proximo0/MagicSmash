"""Bake-off lane A: whole walk sheet in ONE call from one reference picture, for HR6.1/HR6.2, 10 seeds each.
v1: FLUX.2-klein-base-4B + svntax pixel_spritesheet_4walk LoRA (4x4 grid, row 3 = 3 walk frames facing right), 28 steps.
v2: FLUX.2-klein-4B (distilled), no LoRA, edit mode: a 4-frame side walk strip, 4 steps.
Finishing (fixed): corner flood-fill key, grid slice, common foot line, palette locked to the reference; then the anatomy gate.
Out: ab_out/bakeoff_A/<v>/<id>_<seed>_{raw,fin}.png and results.json. Usage: bakeoff_a.py v1|v2"""
import json, os, sys, time, zlib
from pathlib import Path
sys.path.insert(0, r"D:\projects\hh_art")
os.environ.setdefault("HF_HOME", r"D:\projects\hh_art\hf")
import numpy as np, torch
from PIL import Image
from scipy import ndimage
import runner as R, anatomy as A

ROOT = R.ROOT; OUT = ROOT / "ab_out" / "bakeoff_A"; IDS = ["HR6.1", "HR6.2"]; SEEDS = 10
MAG = (255, 0, 255)
P1 = ("Create a pixel art spritesheet of the character in the image. The spritesheet is a 4 by 4 grid of four rows of frames - "
      "first row is 3 walking frames facing down and 1 frame both arms raised, second row is 3 walking frames facing left and "
      "1 frame jumping left, third row is 3 walking frames facing right and 1 frame jumping right, fourth row is 3 walking "
      "frames back view facing up and 1 frame lying on floor. Flat solid bright magenta background.")
P2 = ("Create a pixel art walk-cycle sprite strip of the character in the image: the same character drawn four times side by "
      "side in one row, far apart, side view facing right, as the four frames of a walk cycle: left leg forward, legs passing, "
      "right leg forward, legs passing. Exactly two legs, both feet pointing the walking direction. The same outfit, shield and "
      "cape in every frame, exactly as in the image. Flat solid bright magenta (#FF00FF) background, detailed 16-bit pixel art.")


def reference(eid):
    n, _ = R.best_pick(eid); im = Image.open(R.RAW / f"{eid}_{n}.png").convert("RGB"); w, h = im.size
    fr = im.crop((0, 0, w // 4, h)); a = np.asarray(fr); fg = ~((a[..., 0] > 240) & (a[..., 1] < 20) & (a[..., 2] > 240))
    ys, xs = np.nonzero(fg); fr = fr.crop((max(0, xs.min() - 8), max(0, ys.min() - 8), xs.max() + 8, ys.max() + 8))
    side = max(fr.size) + 32; ref = Image.new("RGB", (side, side), MAG); ref.paste(fr, ((side - fr.width) // 2, (side - fr.height) // 2))
    return ref.resize((512, 512), Image.NEAREST), n


def key(img):
    """Corner flood fill: background = pixels connected to the 4 corners within a colour distance of the corner colour."""
    a = np.asarray(img.convert("RGB")).astype(int); h, w, _ = a.shape
    bg = np.zeros((h, w), bool)
    for cy, cx in ((0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)):
        near = np.abs(a - a[cy, cx]).sum(-1) < 90
        lab, _ = ndimage.label(near); bg |= lab == lab[cy, cx]
    out = a.astype(np.uint8).copy(); out[bg] = MAG
    return Image.fromarray(out), ~bg


def finish(img, cells, ref):
    """cells: list of (x0,y0,x1,y1) frames. Key, slice, put every frame on one foot line, lock the palette to the reference."""
    keyed, fg = key(img); frames = []
    for x0, y0, x1, y1 in cells:
        f = fg[y0:y1, x0:x1]; ys, xs = np.nonzero(f)
        if len(ys) == 0: frames.append(None); continue
        frames.append((keyed.crop((x0, y0, x1, y1)), int(ys.max()), int(ys.min()), int(xs.min()), int(xs.max())))
    good = [f for f in frames if f]
    if not good: return None
    fh = max(f[1] - f[2] for f in good) + 1; cw = max(f[4] - f[3] for f in good) + 1
    W, H = int(cw * 1.25) + 8, int(fh * 1.1) + 8; base = H - 4
    sheet = Image.new("RGB", (W * len(frames), H), MAG)
    for i, f in enumerate(frames):
        if not f: continue
        im, bot, top, l, r = f; c = im.crop((l, top, r + 1, bot + 1))
        sheet.paste(c, (i * W + (W - c.width) // 2, base - c.height))
    pal = ref.quantize(colors=48, method=Image.Quantize.MEDIANCUT)  # palette lock: map onto the reference's 48 colours
    a = np.asarray(sheet); bgm = (a[..., 0] > 240) & (a[..., 1] < 20) & (a[..., 2] > 240)
    q = np.asarray(sheet.quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")).copy(); q[bgm] = MAG
    return Image.fromarray(q)


def main(v):
    import ab_klein as K
    if v == "v2": os.environ["AB_NOLORA"] = "1"
    pipe = K.load("walk" if v == "v1" else "sprite")
    od = OUT / v; od.mkdir(parents=True, exist_ok=True); q = {e["id"]: e for e in R.load_queue()}; res = []
    torch.cuda.reset_peak_memory_stats()
    for eid in IDS:
        ref, refn = reference(eid); ref.save(od / f"{eid}_ref.png")
        for s in range(SEEDS):
            g = torch.Generator("cuda").manual_seed(zlib.crc32(f"BA/{v}/{eid}/{s}".encode()))
            t = time.time()
            if v == "v1":
                img = pipe(prompt=P1, image=ref, width=512, height=512, num_inference_steps=28, guidance_scale=4.0, generator=g).images[0]
                cells = [(c * 128, 256, (c + 1) * 128, 384) for c in range(3)]  # row 3: walking right, 3 frames
            else:
                img = pipe(prompt=P2, image=ref, width=1024, height=576, num_inference_steps=4, guidance_scale=1.0, generator=g).images[0]
                cells = [(c * 256, 0, (c + 1) * 256, 576) for c in range(4)]
            dt = time.time() - t; img.save(od / f"{eid}_{s}_raw.png")
            fin = finish(img, cells, ref)
            if fin is None: res.append(dict(id=eid, seed=s, sec=round(dt, 1), anatomy="empty", ok=False)); continue
            fin.save(od / f"{eid}_{s}_fin.png")
            A.N = len(cells)
            try: ok, notes, _ = A.check(fin, q[eid], None)
            finally: A.N = 4
            res.append(dict(id=eid, seed=s, sec=round(dt, 1), anatomy=notes, ok=ok))
            print(eid, s, f"{dt:.1f}s", notes, flush=True)
    json.dump(dict(variant=v, peak_vram_gb=round(torch.cuda.max_memory_allocated() / 2**30, 2), ref_picture=None, runs=res),
              open(od / "results.json", "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1])

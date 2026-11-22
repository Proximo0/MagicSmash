"""Unattended local art runner: queue.json -> SDXL + pixel-art LoRA -> raw/<id>_<n>.png -> branch art-raw.

Restartable: ids listed in done.txt are skipped. Stop: create STOP file in this folder (finishes current id,
pushes, exits) or kill the pythonw process.
"""
import argparse, json, os, re, shutil, subprocess, sys, time, traceback, zlib
from pathlib import Path

ROOT = Path(r"D:\projects\hh_art")
os.environ.setdefault("HF_HOME", str(ROOT / "hf"))
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
RAW, DONE, FAILED, STATUS, LOG, STOP = (ROOT / "raw", ROOT / "done.txt", ROOT / "failed.txt",
                                        ROOT / "status.txt", ROOT / "runner.log", ROOT / "STOP")
REPO = ROOT / "art-raw"
SIZES = {"l": (1344, 768), "s": (1024, 1024), "p": (768, 1344)}
NEG = ("magenta clothing, pink skin, purple tint, blurry, smooth shading, soft focus, 3d render, photo, realistic photo, text, letters, watermark, signature, "
       "frame, border, gradient background, scenery, landscape background, floor, ground shadow, cropped, cut off, "
       "jpeg artifacts, deformed, extra limbs")


def log(msg):
    line = time.strftime("%Y-%m-%d %H:%M:%S ") + msg
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    if sys.stdout:
        try: print(line, flush=True)
        except Exception: pass


def status(msg):
    STATUS.write_text(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n", encoding="utf-8")


def snap(repo):
    __import__("licence_check").allow(repo)
    d = ROOT / "hf" / "hub" / ("models--" + repo.replace("/", "--")) / "snapshots"
    return str(next(d.iterdir()))


def record_score(eid, n, t, good, score, traits, notes):
    """scores.json next to raw/: every try with its check result and must-trait scores (lead uses it to pick)."""
    p = ROOT / "scores.json"
    try: d = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
    except Exception: d = {}
    d.setdefault(eid, {}).setdefault(str(n), []).append(
        {"try": t, "ok": bool(good), "score": round(float(score), 3), "traits": {k: float(v) for k, v in traits.items()}, "notes": str(notes)})
    p.write_text(json.dumps(d, indent=0), encoding="utf-8")


def natkey(s):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", s)]


def load_queue():
    """queue_sd.json first (stage 0), then queue_sd2.json (stage 1: action sheets, painted); each by pri, then id."""
    stages = [ROOT / "queue_sd.json" if (ROOT / "queue_sd.json").exists() else ROOT / "queue.json", ROOT / "queue_sd2.json"]
    q = []
    for st, qf in enumerate(stages):
        if qf.exists():
            q += [dict(e, _stage=st) for e in json.loads(qf.read_text(encoding="utf-8-sig"))]
    return sorted(q, key=lambda e: (e["_stage"], e.get("pri", 9), natkey(e["id"])))


def painted_ids():
    return {e["id"] for e in load_queue() if e.get("style") == "painted"}


def read_set(p):
    return set(p.read_text(encoding="utf-8").split()) if p.exists() else set()


def git(*a, check=True):
    return subprocess.run(["git", "-C", str(REPO), *a], capture_output=True, text=True, check=check,
                          creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


def best_pick(eid):
    """(n, score) of the top-ranked picture of an id from scores.json (each picture's best try), or (1, None)."""
    try: d = json.loads((ROOT / "scores.json").read_text(encoding="utf-8")).get(eid, {})
    except Exception: d = {}
    cands = [(max(t["score"] for t in tries), int(n)) for n, tries in d.items() if tries]
    if not cands: return 1, None
    s, n = max(cands); return n, s


def export_best_and_sheet():
    """best/<id>_<n>.jpg for each done id not exported yet, plus sheets/<first>-<last>.jpg of those ids."""
    from PIL import Image, ImageDraw
    bd = REPO / "best"; bd.mkdir(exist_ok=True); sd = REPO / "sheets"; sd.mkdir(exist_ok=True)
    have = {p.stem.rsplit("_", 1)[0] for p in bd.glob("*.jpg")}
    new = [i for i in (DONE.read_text(encoding="utf-8").split() if DONE.exists() else []) if i not in have]
    pids = painted_ids()
    for i in new:
        n, _ = best_pick(i); f = RAW / f"{i}_{n}.png"
        if f.exists(): Image.open(f).convert("RGB").save(bd / f"{i}_{n}.jpg", quality=90)
        if f.exists() and i in pids: (REPO / "painted").mkdir(exist_ok=True); shutil.copy2(f, REPO / "painted" / f.name)
    if new:
        TW, TH, LB = 300, 172, 110
        sheet = Image.new("RGB", (LB + 4 * TW, len(new) * TH), (30, 30, 30)); d = ImageDraw.Draw(sheet)
        for r, i in enumerate(new):
            bn, _ = best_pick(i); d.text((6, r * TH + 6), f"{i}\nbest {bn}", fill="white")
            for k in range(1, 5):
                f = RAW / f"{i}_{k}.png"
                if not f.exists(): continue
                im = Image.open(f).convert("RGB"); im.thumbnail((TW - 4, TH - 4))
                sheet.paste(im, (LB + (k - 1) * TW + 2, r * TH + 2))
        sheet.save(sd / f"{new[0]}-{new[-1]}.jpg", quality=85)
    return len(new)


def push(reason):
    """Push clean/ (game-ready), best/<id>_<n>.jpg (top-ranked raw try per id), a JPEG contact sheet and scores.json.
    Full raw PNGs stay on this disk only (they would bloat the repo). Never raises."""
    try:
        n = 0
        if (REPO / "raw").exists():
            git("rm", "-r", "-q", "--cached", "--ignore-unmatch", "raw"); shutil.rmtree(REPO / "raw", ignore_errors=True)
        n += export_best_and_sheet()
        try:  # game-ready versions: true pixel size, small palette, transparent background
            import clean as C
            cd = REPO / "clean"; cd.mkdir(exist_ok=True)
            skip = painted_ids()
            for f in RAW.glob("*.png"):
                if f.stem.rsplit("_", 1)[0] in skip: continue  # painted art: no grid snap or palette
                t = cd / f.name
                if t.exists() and t.stat().st_mtime >= f.stat().st_mtime: continue  # re-clean regenerated art
                try:
                    C.clean(f, t, tile=f.name.startswith("TL")); n += 1
                except Exception as e:
                    log(f"clean error {f.name}: {e}")
        except Exception as e:
            log(f"clean error: {e}")
        shutil.copy2(DONE, REPO / "done.txt") if DONE.exists() else None
        shutil.copy2(ROOT / "scores.json", REPO / "scores.json") if (ROOT / "scores.json").exists() else None
        shutil.copy2(STATUS, REPO / "status.txt") if STATUS.exists() else None
        git("add", "-A")
        if git("diff", "--cached", "--quiet", check=False).returncode == 0:
            log(f"push({reason}): nothing new"); return True
        git("commit", "-q", "-m", f"raw art: {reason} (+{n} files)\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")
        for i in range(4):
            r = git("push", "-q", "-u", "origin", "art-raw", check=False)
            if r.returncode == 0:
                log(f"push({reason}): ok, +{n} files"); return True
            log(f"push try {i+1} failed: {r.stderr.strip()[:300]}"); time.sleep(5 * 2 ** i)
    except Exception as e:
        log(f"push({reason}) error: {e}")
    return False


BG = "solid flat magenta background, plain #ff00ff background, simple background"
STYLE = "16-bit pixel art, dark gothic action rpg, hard dark outlines, desaturated iron grey, bone, dried blood red, tallow yellow"


def esc(s):
    return s.replace("(", r"\(").replace(")", r"\)")


def between(text, a, b):
    i = text.find(a)
    if i < 0: return None
    i += len(a); j = text.find(b, i)
    return esc(text[i:j if j > 0 else None].strip().rstrip("."))


def sd_prompt(e):
    if e.get("sd_prompt"):  # hand-written SDXL prompt from queue_sd.json
        if e.get("kind") == "walk":
            return "sprite sheet, four frames of the same character walking to the right, walk cycle, " + e["sd_prompt"]
        return e["sd_prompt"]
    """Queue prompts are written for a chat-style generator; SDXL does better with a short tag-style prompt."""
    p, k = e["prompt"], e.get("kind")
    if k == "walk":
        s = between(p, "The character is:", " The plain")
        if s: return (f"({s})1.15, pixel art sprite sheet, four frames of the same character walking to the right, "
                      f"side view profile, walk cycle, {BG}, {STYLE}")
    if k == "one":
        s = between(p, "It is:", " The plain")
        if s: return f"({s})1.15, pixel art, one single huge game sprite alone, full body, facing right, centered, filling most of the picture, {BG}, {STYLE}"
    if k == "icon":
        s = between(p, "It is:", " The plain")
        if s: return f"pixel art, game item icon, one single object, centered, large, {s}, {BG}, {STYLE}, one bright accent"
    if k == "tile":
        s = between(p, "straight above:", ". The same")
        if s: return (f"pixel art, seamless tileable texture, top-down view, flat close-up, {s}, uniform pattern filling the "
                      f"whole image, no border, 16-bit, dark muted colours, flat even light, low contrast")
    return "pixel art, " + esc(p)


def key_magenta(img, tol=30):
    """Replace the (near-flat) background connected to the picture edge with pure #FF00FF."""
    import numpy as np
    from scipy import ndimage
    a = np.asarray(img.convert("RGB")).astype(np.int16)
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(border, axis=0)
    near = np.sqrt(((a - bg) ** 2).sum(-1)) < tol
    lab, _ = ndimage.label(near)
    edge_labels = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    m = np.isin(lab, list(edge_labels))
    out = a.astype(np.uint8).copy(); out[m] = (255, 0, 255)
    from PIL import Image
    return Image.fromarray(out), float(m.mean())


WALK_TRIES = 3
CFG_STRONG = 2.0
ADAPTER_SCALE = 0.9


class Gen:
    def __init__(self, lora_w, steps, cfg, lcm, offload=True):
        import torch
        from diffusers import StableDiffusionXLPipeline, AutoencoderKL, LCMScheduler
        from huggingface_hub import snapshot_download, hf_hub_download
        from compel import CompelForSDXL
        self.torch = torch
        base = snap("stabilityai/stable-diffusion-xl-base-1.0")
        vae = AutoencoderKL.from_pretrained(snap("madebyollin/sdxl-vae-fp16-fix"),
                                            torch_dtype=torch.float16)
        pipe = StableDiffusionXLPipeline.from_pretrained(base, vae=vae, torch_dtype=torch.float16, variant="fp16",
                                                         use_safetensors=True)
        pipe.load_lora_weights(hf_hub_download(__import__("licence_check").allow("nerijs/pixel-art-xl"), "pixel-art-xl.safetensors", local_files_only=True),
                               adapter_name="pixel")
        names, weights = ["pixel"], [lora_w]
        if lcm:
            pipe.load_lora_weights(hf_hub_download(__import__("licence_check").allow("latent-consistency/lcm-lora-sdxl"), "pytorch_lora_weights.safetensors",
                                                   local_files_only=True), adapter_name="lcm")
            names.append("lcm"); weights.append(1.0)
            pipe.scheduler = LCMScheduler.from_config(pipe.scheduler.config)
        pipe.set_adapters(names, adapter_weights=weights)
        if offload:  # unet+vae stay on the GPU, the two text encoders visit it only to encode the prompt
            pipe.unet.to("cuda"); pipe.vae.to("cuda")
        else:
            pipe.to("cuda")
        self.offload = offload; self.i2i = None
        pipe.vae.enable_tiling()
        self.pipe, self.steps, self.cfg, self.lora_w = pipe, steps, cfg, lora_w
        self.compel = CompelForSDXL(pipe, device="cuda")
        self.convs = [m for mod in (pipe.unet, pipe.vae) for m in mod.modules() if isinstance(m, torch.nn.Conv2d)]

    def __call__(self, prompt, shape, seed, tile=False, walk=False, height=56, strong=False, negative=None,
                 action=None, size=None, painted=False):
        torch = self.torch
        want = "painted" if painted else "pixel"
        if getattr(self, "style", "pixel") != want:  # painted art: no pixel-art LoRA
            names = ["pixel"] + (["lcm"] if "lcm" in self.pipe.get_list_adapters().get("unet", []) else [])
            ws = [0.0 if painted else self.lora_w] + ([1.0] if len(names) > 1 else [])
            self.pipe.set_adapters(names, adapter_weights=ws); self.style = want
        for m in self.convs:  # circular padding makes ground tiles seamless
            m.padding_mode = "circular" if tile else "zeros"
        self.pipe.vae.disable_tiling() if tile else self.pipe.vae.enable_tiling()
        text = prompt
        neg = negative if negative else NEG if not tile else "blurry, text, watermark, border, frame, vignette, single object, perspective, 3d render"
        if self.offload:
            self.pipe.text_encoder.to("cuda"); self.pipe.text_encoder_2.to("cuda")
        with torch.no_grad():
            c = self.compel(text, negative_prompt=neg)
        if self.offload:
            self.pipe.text_encoder.to("cpu"); self.pipe.text_encoder_2.to("cpu"); torch.cuda.empty_cache()
        w, h = SIZES.get(shape, SIZES["s"])
        if size:  # SDXL is poor below ~1 MP: scale small requests up (same aspect); the cleaner shrinks them anyway
            k = max(1.0, (1024 * 1024 / (size[0] * size[1])) ** 0.5)
            w, h = (int(size[0] * k) // 64 * 64, int(size[1] * k) // 64 * 64)  # adapter needs /64
        g = torch.Generator("cuda").manual_seed(seed)
        kw = dict(prompt_embeds=c.embeds, pooled_prompt_embeds=c.pooled_embeds,
                  negative_prompt_embeds=c.negative_embeds, negative_pooled_prompt_embeds=c.negative_pooled_embeds,
                  guidance_scale=max(self.cfg, CFG_STRONG) if strong else self.cfg, generator=g)
        if walk and isinstance(height, dict) and float(height.get("height") or 1) < 0.6:
            walk = False  # small beasts (rats, bats...): a human pose guide would be wrong; plain generation
        if walk or action:
            if self.i2i is None:
                import inspect
                from diffusers import StableDiffusionXLAdapterPipeline, T2IAdapter
                ad = T2IAdapter.from_pretrained(snap("TencentARC/t2i-adapter-openpose-sdxl-1.0"), torch_dtype=torch.float16).to("cuda")
                ok = inspect.signature(StableDiffusionXLAdapterPipeline.__init__).parameters
                self.i2i = StableDiffusionXLAdapterPipeline(adapter=ad, **{k: v for k, v in self.pipe.components.items() if k in ok})
                self.skel = {}
            import walk as W
            if action:  # attack / recoil / die rows: drawn pose guides, scaled like the walk
                sc = float(height.get("height") or 1.0) if isinstance(height, dict) else 1.0
                key = (action, w, h, round(sc, 2))
                if key not in self.skel:
                    self.skel[key] = W.action_sheet(w, h, action, fill=min(0.70, 0.62 * sc))
                return self.i2i(image=self.skel[key], adapter_conditioning_scale=ADAPTER_SCALE, width=w, height=h,
                                num_inference_steps=self.steps, **kw).images[0]
            hh = height if isinstance(height, (int, float)) and height > 0 else 56
            if isinstance(height, dict):  # queue_sd scale {height,width} relative to a human
                hh = round(56 * float(height.get("height") or 1.0))
            if hh not in self.skel:  # races differ: dwarf (45) short with short legs, orc (62) tall
                self.skel[hh] = W.skeleton_sheet(w, h, fill=min(0.66, 0.56 * hh / 56), leg=0.47 if hh >= 48 else 0.42)
            return self.i2i(image=self.skel[hh], adapter_conditioning_scale=ADAPTER_SCALE, width=w, height=h,
                            num_inference_steps=self.steps, **kw).images[0]
        return self.pipe(width=w, height=h, num_inference_steps=self.steps, **kw).images[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="stop after this many ids (0 = whole queue)")
    ap.add_argument("--only", default="", help="comma list of ids (test mode, ignores done.txt)")
    ap.add_argument("--out", default=str(RAW))
    ap.add_argument("--steps", type=int, default=8)
    ap.add_argument("--cfg", type=float, default=1.0)
    ap.add_argument("--lora", type=float, default=1.0)
    ap.add_argument("--no-lcm", dest="lcm", action="store_false")
    ap.add_argument("--no-offload", action="store_true")
    ap.add_argument("--no-key", action="store_true")
    ap.add_argument("--count", type=int, default=4)
    ap.add_argument("--push-every", type=int, default=20)
    ap.add_argument("--no-push", action="store_true")
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    test = bool(a.only)
    q = load_queue()
    if test:
        want = a.only.split(","); q = [e for e in q if e["id"] in want]
    else:
        done = read_set(DONE) | read_set(FAILED); q = [e for e in q if e["id"] not in done]
    log(f"start: {len(q)} ids to do, steps={a.steps} cfg={a.cfg} lora={a.lora} lcm={a.lcm} pid={os.getpid()}")
    status(f"RUNNING pid={os.getpid()} {len(q)} ids left")
    gen = Gen(a.lora, a.steps, a.cfg, a.lcm, offload=not a.no_offload)
    since_push, n_ids = 0, 0
    for e in q:
        if STOP.exists():
            log("STOP file found, stopping"); break
        eid = e["id"]; t0 = time.time(); ok = True
        for n in range(1, a.count + 1):
            f = out / f"{eid}_{n}.png"
            if f.exists() and not test: continue
            for attempt in range(3):
                try:
                    kind = e.get("kind"); best = None; must = e.get("must") or []
                    painted = e.get("style") == "painted"; pose = e.get("pose") if kind == "action" else None
                    keyed = kind not in ("tile", "painted") and not painted and not a.no_key
                    tries = WALK_TRIES if kind in ("walk", "one", "action") else (2 if must and kind != "tile" else 1)
                    for t in range(tries):
                        img = gen(sd_prompt(e), e.get("shape", "s"), tile=kind == "tile", walk=kind == "walk", height=e.get("scale") or e.get("height"), strong=kind in ("walk", "one", "action"), negative=e.get("negative"),
                                  seed=zlib.crc32(f"{eid}/{n}/{attempt}/{t}".encode()), action=pose, size=e.get("size"), painted=painted)
                        orig = img; frac = 1.0
                        if keyed:
                            img, frac = key_magenta(img)
                            if frac < 0.25: log(f"{eid}_{n}: only {frac:.0%} background keyed")
                        import walk as W
                        if kind == "walk":  # short races (dwarves) take smaller steps
                            sc = (e.get("scale") or {}).get("height", 1.0) if isinstance(e.get("scale"), dict) else 1.0
                            good, score, notes = W.check_sheet(img, min_leg_diff=0.12 if float(sc or 1) < 0.85 else 0.18)
                        elif kind == "one": good, score, notes = W.check_single(img)
                        elif pose: good, score, notes = W.check_frames(img, len(W.ACTIONS[pose]))
                        else: good, score, notes = True, 0.0, ""
                        if keyed and kind != "icon":  # leftover backdrop bands along the picture edge (grey floor strips)
                            import numpy as _np
                            _a = _np.asarray(img.convert("RGB"))
                            _b = _np.concatenate([_a[0], _a[-1], _a[:, 0], _a[:, -1]])
                            edge = float(((_b[:, 0] > 240) & (_b[:, 1] < 20) & (_b[:, 2] > 240)).mean())
                            if edge < 0.93:
                                good, score, notes = False, score - 0.6, notes + f" edge-magenta {edge:.0%}"
                        if kind in ("walk", "one", "action") and keyed and frac < 0.3:  # background not flat: keying failed
                            good, score, notes = False, score - 1, notes + f" keyed {frac:.0%}"
                        ts = {}
                        if must and kind != "tile":  # image-text check of the must traits
                            try:
                                import score as S
                                ts = S.trait_scores(orig, must, kind); miss = S.misses(ts)
                                score += sum(ts.values()) / len(ts)
                                if len(miss) > max(1, len(ts) // 2): good = False  # tiny sprites hide small traits (ears): gate on most traits missing
                                if miss: notes += f" missing {miss}"
                            except Exception as ex:
                                log(f"trait score error: {ex}")
                        record_score(eid, n, t + 1, good, score, ts, notes)
                        log(f"{eid}_{n} try {t+1}: {'ok' if good else 'reject'} {notes} traits {ts}")
                        if best is None or score > best[0]: best = (score, img, orig)
                        if good: break
                    if keyed:
                        (out / "orig").mkdir(exist_ok=True); best[2].save(out / "orig" / f.name)
                    best[1].save(f); break
                except Exception as ex:
                    log(f"{eid}_{n} attempt {attempt+1} error: {type(ex).__name__}: {str(ex)[:300]}")
                    try: gen.torch.cuda.empty_cache()
                    except Exception: pass
                    time.sleep(10)
            else:
                ok = False
        dt = time.time() - t0
        if test:
            log(f"{eid}: {dt:.0f}s ({dt / a.count:.1f}s/picture)"); continue
        with open(DONE if ok else FAILED, "a", encoding="utf-8") as fh:
            fh.write(eid + "\n")
        n_ids += 1; since_push += 1
        log(f"{eid} {'done' if ok else 'FAILED'} in {dt:.0f}s ({dt / a.count:.1f}s/picture) [{e.get('name','')}]")
        status(f"RUNNING pid={os.getpid()} last={eid} {len(q) - n_ids} ids left, {dt / a.count:.1f}s/picture")
        if since_push >= a.push_every and not a.no_push:
            push(f"through {eid}"); since_push = 0
        if a.limit and n_ids >= a.limit:
            break
        time.sleep(2)
    if not test:
        left = len([x for x in load_queue() if x["id"] not in read_set(DONE) | read_set(FAILED)])
        status(("FINISHED" if left == 0 else "STOPPED") + f" {left} ids left")
        if not a.no_push: push("final" if left == 0 else "stop")
    log("exit")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log("FATAL " + traceback.format_exc())
        status("CRASHED, see runner.log")
        raise

"""A/B: FLUX.2-klein-4B (+ pixel-art LoRA) and klein-base-4B (+ 4-walk spritesheet LoRA) on the same ids as SDXL.
Usage: ab_klein.py sprite|walk   -> ab_out/<mode>/<id>_<n>.png and timings in ab_out/<mode>/times.json"""
import json, os, re, sys, time
from pathlib import Path
ROOT = Path(r"D:\projects\hh_art")
os.environ.setdefault("HF_HOME", str(ROOT / "hf"))
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
import torch
from PIL import Image

IDS = os.environ.get("AB_IDS", "HR1.1,HR1.3,HR1.4,MN1.1,BS1.1,IC1.1,TL1.1,PR1.1").split(",")
WALK_IDS = ["HR1.1", "HR1.3", "HR1.4", "MN1.1"]


def snap(repo):
    __import__("licence_check").allow(repo)
    d = ROOT / "hf" / "hub" / ("models--" + repo.replace("/", "--")) / "snapshots"
    return str(next(d.iterdir()))


def subject(e):
    s = e.get("sd_prompt") or e["prompt"]
    s = re.sub(r"\(([^()]*)\)\d*\.?\d+", r"\1", s)               # (a, b)1.2 -> a, b
    s = s.replace("flat magenta background (#FF00FF)", "").replace("pixel art,", "")
    s = re.sub(r"\s*,\s*,", ",", s).strip(" ,")
    return s


def load(mode):
    from diffusers import Flux2KleinPipeline, PipelineQuantizationConfig
    from transformers import Qwen3ForCausalLM as AutoModel, BitsAndBytesConfig
    bnb = dict(load_in_4bit=True, bnb_4bit_quant_type="nf4", bnb_4bit_compute_dtype=torch.bfloat16)
    te = AutoModel.from_pretrained(snap("black-forest-labs/FLUX.2-klein-4B"), subfolder="text_encoder",
                                   quantization_config=BitsAndBytesConfig(**bnb), torch_dtype=torch.bfloat16)
    qc = PipelineQuantizationConfig(quant_backend="bitsandbytes_4bit", quant_kwargs=bnb, components_to_quantize=["transformer"])
    base = "black-forest-labs/FLUX.2-klein-4B" if mode == "sprite" else "black-forest-labs/FLUX.2-klein-base-4B"
    pipe = Flux2KleinPipeline.from_pretrained(snap(base), text_encoder=te, quantization_config=qc, torch_dtype=torch.bfloat16)
    if os.environ.get("AB_NOLORA"):
        pass
    elif mode == "sprite":
        pipe.load_lora_weights(snap("limbicnation/pixel-art-lora"), weight_name="pytorch_lora_weights.safetensors", adapter_name="px")
        pipe.set_adapters(["px"], [1.1])
    else:
        pipe.load_lora_weights(snap("svntax-dev/pixel_spritesheet_4walk_small_lora_v1"),
                               weight_name="pixel_4walk_small_flux2_klein_base_4b_v1.safetensors", adapter_name="walk")
        pipe.set_adapters(["walk"], [1.0])
    pipe.vae.to("cuda")
    return pipe


def walk_row(img):
    """4x4 sheet (512): row 3 = three walk frames facing right (+ a jump). Make a 4-frame row: f1 f2 f3 f2."""
    w, h = img.size; cw, ch = w // 4, h // 4
    f = [img.crop((i * cw, 2 * ch, (i + 1) * cw, 3 * ch)) for i in range(3)]
    row = Image.new("RGB", (cw * 4, ch))
    for i, k in enumerate([0, 1, 2, 1]): row.paste(f[k], (i * cw, 0))
    return row


def main():
    mode = sys.argv[1]
    q = {e["id"]: e for e in json.loads((ROOT / "queue_sd.json").read_text(encoding="utf-8-sig"))}
    out = ROOT / "ab_out" / mode; out.mkdir(parents=True, exist_ok=True)
    t0 = time.time(); pipe = load(mode); print("loaded", round(time.time() - t0), "s", flush=True)
    torch.cuda.reset_peak_memory_stats(); times = {}
    for i in (IDS if mode == "sprite" else WALK_IDS):
        e = q[i]; s = subject(e); k = e["kind"]
        if mode == "walk":
            p = (f"A pixel art spritesheet of {s}. The spritesheet is a 4 by 4 grid of four rows of frames - first row is 3 "
                 f"walking frames facing down and 1 frame both arms raised, second row is 3 walking frames facing left and 1 "
                 f"frame jumping left, third row is 3 walking frames facing right and 1 frame jumping right, fourth row is 3 "
                 f"walking frames back view facing up and 1 frame lying on floor.")
            kw = dict(width=512, height=512, num_inference_steps=28, guidance_scale=4.0)
        else:
            if k == "tile":
                p = f"pixel art, seamless top-down ground texture, {s}"
            elif k == "walk":
                p = f"pixel art sprite sheet, four frames of the same character walking to the right in one row, side view, {s}, game asset, transparent background"
            else:
                p = f"pixel art sprite, {s}, game asset, transparent background"
            wh = (1024, 512) if k == "walk" else (512, 512)
            kw = dict(width=wh[0], height=wh[1], num_inference_steps=4, guidance_scale=1.0)
        ts = []
        for n in range(1, 5):
            g = torch.Generator("cuda").manual_seed(1000 + n)
            t = time.time(); img = pipe(prompt=p, generator=g, **kw).images[0]; ts.append(time.time() - t)
            img.save(out / f"{i}_{n}_full.png")
            if mode == "walk": img = walk_row(img)
            img.save(out / f"{i}_{n}.png")
        times[i] = round(sum(ts[1:]) / max(1, len(ts) - 1), 1)
        print(i, times[i], "s/picture", flush=True)
    times["vram_peak_gb"] = round(torch.cuda.max_memory_allocated() / 2**30, 2)
    (out / "times.json").write_text(json.dumps(times, indent=1))
    print(times)


if __name__ == "__main__":
    main()

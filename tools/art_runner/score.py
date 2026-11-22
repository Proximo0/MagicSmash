"""Must-trait scoring with SigLIP: how well does a picture show each listed trait? Probabilities 0..1 per trait."""
import os, re
from pathlib import Path
os.environ.setdefault("HF_HOME", r"D:\projects\hh_art\hf")
import torch

MODEL = "google/siglip-base-patch16-224"
THRESH = 0.10   # calibrated 2026-11-21: unrelated traits score 0.00-0.09, present traits mostly 0.3-1.0
_m = None


def _load():
    global _m
    if _m is None:
        from transformers import AutoModel, AutoProcessor
        __import__("licence_check").allow(MODEL)
        model = AutoModel.from_pretrained(MODEL, torch_dtype=torch.float16).to("cuda").eval()
        _m = (model, AutoProcessor.from_pretrained(MODEL))
    return _m


@torch.no_grad()
def trait_scores(img, traits, kind="one"):
    """img: PIL. For walk sheets the first frame is scored (one figure, larger)."""
    traits = [t for t in traits if not re.search(r"each frame|every frame|same figure|seamless|no border", t)]  # not single-picture visual traits
    if not traits: return {}
    model, proc = _load()
    im = img.convert("RGB")
    if kind == "walk":
        w, h = im.size; im = im.crop((0, 0, w // 4, h))
    texts = [f"pixel art of a figure with {t}" for t in traits]
    inp = proc(text=texts, images=im, padding="max_length", return_tensors="pt").to("cuda")
    inp["pixel_values"] = inp["pixel_values"].half()
    out = model(**inp)
    p = torch.sigmoid(out.logits_per_image[0].float()).tolist()
    return {t: round(v, 4) for t, v in zip(traits, p)}


def misses(scores, thresh=THRESH):
    return [t for t, v in scores.items() if v < thresh]


if __name__ == "__main__":  # calibrate: print scores for raw pictures with their must traits and a few wrong traits
    import json, sys
    from PIL import Image
    q = {e["id"]: e for e in json.loads(Path(r"D:\projects\hh_art\queue_sd.json").read_text(encoding="utf-8-sig"))}
    for f in sys.argv[1:]:
        i = Path(f).stem.rsplit("_", 1)[0]; e = q[i]
        wrong = ["a pink unicorn", "a blue sports car", "a laptop computer"]
        print(Path(f).name, trait_scores(Image.open(f), e.get("must", []) + wrong, e["kind"]))

# Art runner (Horde & Hearth stand-in art, generated locally on the MSI)

The runner lives on the MSI at `D:\projects\hh_art` (not in this repo) and runs unattended on its own GPU
(RTX 5050, 8 GB). No website, sign-in or bot check is involved, so it cannot stall on one.

## What it does
- Input: `queue_sd.json` (365 ids: `sd_prompt` in compel weight syntax, `negative`, `must` traits, `scale`, `kind`
  walk/one/icon/tile, `shape` l/s/p). Order: `pri`, then id. `queue_sd2.json` (action sheets, painted) comes after.
- Model: SDXL base fp16 + fp16-fix VAE + `nerijs/pixel-art-xl` LoRA + LCM LoRA (8 steps; cfg 1.0, 2.0 for walk/one).
  Long prompts are chunked with compel. Sizes: l 1344x768, s 1024x1024, p 768x1344. (FLUX.2-klein A/B pending.)
- Walk sheets: an OpenPose skeleton sheet (4 side-view frames facing right: wide stride on 1 and 3, legs crossing on
  2 and 4), scaled per race from `scale.height`, drives the `TencentARC/t2i-adapter-openpose-sdxl-1.0` adapter.
  Small beasts (`scale.height` < 0.6) get no human pose guide.
- Background: generated flat, then everything connected to the picture edge is keyed to pure #FF00FF.
- Checks per try (up to 3 tries for walk/one, 2 for icons with `must`):
  walk = leg region of frames 1/3 differs from frame 2 by >= 0.18, no front/back view (symmetry <= 0.90), even heights;
  one = a single figure, not touching the edge; all = background keyed >= 30%;
  must traits = SigLIP (`google/siglip-base-patch16-224`) probability >= 0.10 for each trait.
  The best-scoring try is kept if none passes, so the runner never stalls. Every try is logged in `scores.json`.
- 4 pictures per id: `raw/<id>_<n>.png` on the MSI disk (plus `raw/orig/` before keying). Done ids in `done.txt`,
  failures in `failed.txt`; restartable at any time.

## What it pushes (branch `art-raw`, orphan, every 20 ids and at stop)
- `clean/<id>_<n>.png`: game-ready: pixel grid detected and snapped to true pixel size, colours mapped to
  `realm_palette.hex` (Lab nearest, no dithering), background transparent.
- `best/<id>_<n>.jpg`: the top-ranked raw picture per id (q90). `sheets/<first>-<last>.jpg`: contact sheet of the batch.
- `scores.json`, `done.txt`, `status.txt`. Full raw PNGs are NOT pushed (they stay on the MSI).

## Operate (on the MSI)
- Start detached (survives closing the console): `D:\projects\hh_art\start_runner.ps1`
- Stop gracefully (finishes the current id, pushes, exits): `D:\projects\hh_art\stop_runner.ps1`
- Log: `D:\projects\hh_art\runner.log`; one-line state: `D:\projects\hh_art\status.txt` (RUNNING / STOPPED / FINISHED / CRASHED)
- Test without touching the queue state: `venv\Scripts\python.exe runner.py --only HR1.1,BS1.1 --count 2 --out test_x --no-push`
- Never put the game's, the repository's or a person's name in a prompt.

## Licence gate
`licences.json` lists every model repo the runner may load, with its licence and `commercial_ok`. `licence_check.py` enforces it: `runner2.main()` calls `check_all(LOADS)` and refuses to start unless every repo is listed and cleared, and every load site (`snap()` in runner.py and ab_klein.py, the two LoRA `hf_hub_download` calls, the SigLIP scorer) calls `allow(repo)` first, so a new model cannot be loaded until it is added here. Pose guides are drawn in code (walk.py); no OpenPose detector weights are used.

## Runner code (copied from D:\projects\hh_art)
runner2.py (two-phase runner: SDXL layouts, then FLUX.2-klein-4B), runner.py (shared helpers + SDXL Gen), walk.py (drawn pose skeletons and sheet checks), ab_klein.py (Klein loader), score.py (SigLIP must-trait scores), clean.py / pixsnap.py (keying, pixel snapping), contact.py (contact sheets), licence_check.py + licences.json (licence gate), supervise.py + start_runner.ps1 / stop_runner.ps1 (supervisor). Paths assume D:\projects\hh_art with its venv; no weights or outputs are kept here.

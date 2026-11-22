"""Export, for each accepted hero walk (HR1.x-HR6.x): the widest-stride frame of its best picture as stills/<id>.png
(transparent background) and stills/<id>.json with that frame's pose-layout joints in still pixel coordinates.
Joints come from the drawn pose skeleton (walk.pose) the layout was made with, fitted to the figure as anatomy.py does
(figure height and hip-row centre); toe = ankle moved forward along the ground. No generation."""
import json, re, sys
sys.path.insert(0, r"D:\projects\hh_art")
import numpy as np
from PIL import Image
import runner as R, anatomy as A, walk as W

OUT = R.REPO / "stills"; OUT.mkdir(exist_ok=True)
q = {e["id"]: e for e in R.load_queue()}
n_out = 0
for eid in sorted(R.read_set(R.DONE), key=R.natkey):
    e = q.get(eid)
    if not e or e.get("kind") != "walk" or not re.match(r"HR[1-6]\.\d+$", eid): continue
    n, _ = R.best_pick(eid); f = R.RAW / f"{eid}_{n}.png"
    if not f.exists(): continue
    img = Image.open(f).convert("RGB"); w, h = img.size; a = np.asarray(img)
    fg = ~((a[..., 0] > 240) & (a[..., 1] < 20) & (a[..., 2] > 240))
    best = None
    for fr in (0, 2):  # stride frames; pick the one whose feet are furthest apart
        x0, x1 = int(w * fr / 4), int(w * (fr + 1) / 4); m = fg[:, x0:x1]; ys = np.nonzero(m.any(1))[0]
        ft, fb = int(ys.min()), int(ys.max()); xs = np.nonzero(m[int(fb - 0.1 * (fb - ft)):fb + 1].any(0))[0]
        spread = int(xs.max() - xs.min())
        if best is None or spread > best[0]: best = (spread, fr, x0, x1, ft, fb)
    spread, fr, x0, x1, ft, fb = best
    fill, leg = A.skel_params(e); fh = h * fill; top = h * 0.79 - fh
    p = W.pose(fr, w / 4 * fr + w / 8, top, fh, leg)  # nose, neck, rs, re, rw, ls, le, lw, rh, rk, ra, lh, lk, la, reye, -, rear, -
    sy = (fb - ft) / fh; hip_y = ft + (p[8][1] - top) * sy
    row = np.nonzero(fg[int(hip_y), x0:x1])[0]; dx = (x0 + row.mean() if len(row) else p[8][0]) - p[8][0]
    # crop the still around the figure with a margin; joints are given in the still's pixels
    from scipy import ndimage  # the figure = the largest blob in the frame (drops bits of the neighbouring frames)
    lab, k = ndimage.label(ndimage.binary_dilation(fg[:, x0:x1], iterations=3))
    big = lab == (1 + int(np.argmax(np.bincount(lab.ravel())[1:])))
    m = big & fg[:, x0:x1]; xs = np.nonzero(m.any(0))[0]; pad = 12
    cx0, cy0 = max(0, x0 + int(xs.min()) - pad), max(0, ft - pad); cx1, cy1 = min(w, x0 + int(xs.max()) + pad + 1), min(h, fb + pad + 1)
    hx = p[8][0]  # scale x by the same factor around the hip, so the skeleton keeps its proportions
    J = lambda pt: [round(hx + dx + (pt[0] - hx) * sy - cx0, 1), round(ft + (pt[1] - top) * sy - cy0, 1)]
    nose, neck, rs, re_, rw, ls, le, lw, rh, rk, ra, lh, lk, la = p[:14]; rear = p[16]
    ground = fb - cy0; toe_len = 0.11 * (fb - ft)
    toe = lambda ank: [J(ank)[0] + toe_len, ground]
    joints = {"head": J(((nose[0] + rear[0]) / 2, (nose[1] + rear[1]) / 2)), "neck": J(neck),
              "pelvis": J(((rh[0] + lh[0]) / 2, (rh[1] + lh[1]) / 2)),
              # facing right, the viewer sees the figure's left side: near = left, far = right
              "near_shoulder": J(ls), "near_elbow": J(le), "near_wrist": J(lw), "near_hip": J(lh), "near_knee": J(lk),
              "near_ankle": J(la), "near_toe": toe(la),
              "far_shoulder": J(rs), "far_elbow": J(re_), "far_wrist": J(rw), "far_hip": J(rh), "far_knee": J(rk),
              "far_ankle": J(ra), "far_toe": toe(ra)}
    crop = img.crop((cx0, cy0, cx1, cy1)); ca = np.asarray(crop); alpha = np.zeros(ca.shape[:2], bool); mx0 = x0 - cx0
    alpha[:, max(0, mx0):mx0 + m.shape[1]] = m[cy0:cy1, max(0, -mx0):max(0, -mx0) + ca.shape[1] - max(0, mx0)][:, :ca.shape[1] - max(0, mx0)]
    rgba = np.dstack([ca, (alpha * 255).astype(np.uint8)]); Image.fromarray(rgba, "RGBA").save(OUT / f"{eid}.png")
    json.dump({"id": eid, "name": e.get("name"), "source_picture": f"{eid}_{n}.png", "frame": fr + 1, "stride_px": spread,
               "facing": "right", "ground_y": ground, "size": [cx1 - cx0, cy1 - cy0], "joints": joints,
               "note": "joints from the pose-layout skeleton (walk.pose) fitted to the figure's height and hip row; "
                       "approximate (a few % of the height), not detected from the picture; toes placed on the ground line"},
              open(OUT / f"{eid}.json", "w"), indent=1)
    n_out += 1
print(n_out, "stills exported to", OUT)

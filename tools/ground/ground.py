#!/usr/bin/env python3
"""Seamless ground tiles for the six fields, made from seeded noise only (no model, no outside art).
ground.py OUT_DIR  ->  ground_0a.png, ground_0b.png .. ground_5b.png and ground_towna/b.png (the town plaza) (512 x 512, each wraps on both axes) and the
two long-period maps ground_blotch.png (shade) and ground_patch.png (which of a and b shows)."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

N = 512


def lattice(rng, cells):
    return rng.random((cells, cells))


def value_noise(rng, cells):
    """Periodic value noise: `cells` lattice points across the tile, smooth between them."""
    g = lattice(rng, cells)
    t = np.arange(N) * cells / N
    i = t.astype(int)
    f = t - i
    f = f * f * (3 - 2 * f)
    i1 = (i + 1) % cells
    a = g[np.ix_(i, i)] * (1 - f)[None, :] + g[np.ix_(i, i1)] * f[None, :]
    b = g[np.ix_(i1, i)] * (1 - f)[None, :] + g[np.ix_(i1, i1)] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def fbm(rng, cells, octaves=5):
    out = np.zeros((N, N))
    amp, tot = 1.0, 0.0
    for _ in range(octaves):
        out += amp * value_noise(rng, cells)
        tot += amp
        amp *= 0.5
        cells = min(cells * 2, N)
    return out / tot


def cells_map(rng, count, grid=False):
    """Periodic Voronoi: distance to the nearest point (f1), to the second (f2) and the nearest point's id.
    grid: `count` is a square and the points are a jittered grid, so the cells come out even in size."""
    if grid:
        k = int(round(count ** 0.5))
        gy, gx = np.mgrid[0:k, 0:k]
        pts = (np.stack([gx.ravel(), gy.ravel()], 1) + 0.5 + rng.uniform(-0.3, 0.3, (k * k, 2))) * (N / k)
        count = k * k
    else:
        pts = rng.random((count, 2)) * N
    y, x = np.mgrid[0:N, 0:N]
    f1 = np.full((N, N), 1e9)
    f2 = np.full((N, N), 1e9)
    ident = np.zeros((N, N), int)
    for k, (px, py) in enumerate(pts):
        dx = np.abs(x - px)
        dx = np.minimum(dx, N - dx)
        dy = np.abs(y - py)
        dy = np.minimum(dy, N - dy)
        d = np.hypot(dx, dy)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        ident = np.where(closer, k, ident)
        f1 = np.where(closer, d, f1)
    return f1, f2, ident


def ramp(v, stops):
    """v in 0..1 through colour stops [(at, (r, g, b)), ...]."""
    v = np.clip(v, 0, 1)
    out = np.zeros(v.shape + (3,))
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        m = (v >= a) & (v <= b)
        t = ((v - a) / max(b - a, 1e-6))[..., None]
        out = np.where(m[..., None], np.array(ca) * (1 - t) + np.array(cb) * t, out)
    return out


def norm(a):
    return (a - a.min()) / (a.max() - a.min())


def speckle(rng, density, lo, hi):
    return np.where(rng.random((N, N)) < density, rng.uniform(lo, hi, (N, N)), 0.0)


def stones(rng, count, gap):
    """Flat stones with dark joints: 1 on a stone, 0 in a joint, and a shade per stone."""
    f1, f2, ident = cells_map(rng, count)
    joint = np.clip((f2 - f1) / gap, 0, 1)
    shade = rng.uniform(-1, 1, count)[ident]
    return joint, shade


def emboss(h, strength):
    """Light from the upper left on a height map (wraps): about -1..1."""
    gx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    gy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    return np.clip(-(gx + gy) * strength, -1, 1)


def blobs(rng, count, rmin, rmax, keep=1.0):
    """Hard-edged rounded lumps: a height 0..1 inside each (domed), 0 outside, and a shade per lump."""
    f1, _, ident = cells_map(rng, count)
    r = rng.uniform(rmin, rmax, count)[ident]
    on = (rng.random(count) < keep)[ident]
    dome = np.sqrt(np.clip(1 - (f1 / r) ** 2, 0, 1)) * on
    return dome, rng.uniform(-1, 1, count)[ident]


def lit(img, h, strength, amount=38.0):
    return img + emboss(h, strength)[..., None] * amount


# Each field is two tiles: `a` its common ground and `b` the other ground that shows in patches. The shader
# (realm/client/field/ground.gdshader) chooses between them with a map of a much longer period, so the patches
# never repeat with the tile.


def road(rng):  # THE FOOL'S ROAD: packed earth with pebbles; old cobbles
    base = fbm(rng, 4)
    fine = fbm(rng, 64, 2)
    earth = ramp(norm(0.6 * base + 0.4 * fine), [(0, (34, 27, 20)), (0.5, (54, 43, 31)), (1, (74, 60, 43))])
    earth = lit(earth, fine, 6.0, 14)
    dome, sh = blobs(rng, 300, 1.5, 4.0, 0.5)
    peb = ramp(np.clip(0.5 + 0.4 * sh, 0, 1), [(0, (70, 64, 56)), (1, (112, 104, 92))])
    m = (dome > 0)[..., None]
    a = earth * (1 - m) + lit(peb, dome, 2.5, 30) * m
    joint, shade = stones(rng, 420, 2.2)
    cob = ramp(np.clip(0.5 + 0.3 * shade + 0.4 * (fine - 0.5), 0, 1), [(0, (52, 50, 48)), (1, (96, 90, 80))])
    b = lit(cob * (0.45 + 0.55 * joint[..., None]), np.clip(joint * 1.4, 0, 1), 1.6, 26)
    return a, b


def leaves(img, seeds):
    for seed, count, cols in seeds:
        r2 = np.random.default_rng(7300 + seed)
        dome, sh = blobs(r2, count, 2.0, 4.2, 0.6)
        leaf = ramp(np.clip(0.5 + 0.5 * sh, 0, 1), cols)
        m = (dome > 0)[..., None]
        img = img * (1 - m) + lit(leaf, dome, 2.0, 26) * m
    return img


def wood(rng):  # THE HANGING WOOD: fallen leaves over dark soil; moss
    base = fbm(rng, 4)
    fine = fbm(rng, 64, 2)
    soil = ramp(norm(0.6 * base + 0.4 * fine), [(0, (18, 20, 14)), (1, (40, 36, 24))])
    a = leaves(lit(soil, fine, 6.0, 10), [(1, 520, [(0, (58, 38, 16)), (1, (104, 66, 22))]), (2, 380, [(0, (70, 30, 14)), (1, (128, 84, 26))])])
    green = ramp(norm(fbm(rng, 48, 2)), [(0, (20, 40, 22)), (0.6, (34, 58, 28)), (1, (56, 80, 36))])
    b = leaves(lit(green, fine, 8.0, 16), [(3, 160, [(0, (58, 38, 16)), (1, (104, 66, 22))])])
    return a, b


def marsh(rng):  # THE DROWNED MARSH: mud banks with reeds; standing water
    h = fbm(rng, 5)
    fine = fbm(rng, 64, 2)
    mud = ramp(norm(0.6 * h + 0.4 * fine), [(0, (26, 34, 30)), (0.6, (44, 52, 40)), (1, (64, 66, 46))])
    a = lit(mud, fine, 6.0, 12)
    dome, sh = blobs(rng, 420, 1.2, 2.6, 0.22)
    reed = (dome > 0)[..., None]
    a = np.where(reed, lit(ramp(np.clip(0.5 + 0.5 * sh, 0, 1), [(0, (40, 62, 30)), (1, (86, 104, 44))]), dome, 2.0, 22), a)
    depth = norm(fbm(rng, 4, 4))
    b = ramp(depth, [(0, (8, 22, 30)), (0.6, (16, 40, 48)), (1, (24, 54, 58))])
    glint = (rng.random((N, N)) < 0.004)[..., None]
    b = np.where(glint, b + 34, b)
    return a, b


def peaks(rng):  # THE PALE PEAKS: snow drifts; bare rock
    h = fbm(rng, 4)
    fine = fbm(rng, 64, 2)
    drift = fbm(rng, 12, 3)
    snow = ramp(norm(0.6 * h + 0.4 * drift), [(0, (74, 88, 108)), (0.6, (106, 120, 140)), (1, (136, 148, 166))])
    a = lit(snow, drift, 5.0, 16)
    joint, shade = stones(rng, 150, 2.5)
    rock = ramp(np.clip(0.5 + 0.3 * shade + 0.5 * (fine - 0.5), 0, 1), [(0, (36, 40, 50)), (1, (78, 84, 96))])
    b = lit(rock * (0.4 + 0.6 * joint[..., None]), np.clip(joint * 1.4, 0, 1), 1.6, 24)
    return a, b


def flags(rng, count, cols, crack_seed):
    joint, shade = stones(rng, count, 3.0)
    fine = fbm(rng, 64, 2)
    v = 0.5 + 0.25 * shade + 0.5 * (fine - 0.5)
    img = ramp(np.clip(v, 0, 1), cols)
    img = lit(img * (0.3 + 0.7 * joint[..., None]), np.clip(joint * 1.3, 0, 1), 1.4, 30)
    f1, f2, _ = cells_map(rng, crack_seed)
    crack = np.clip(1 - (f2 - f1) / 1.2, 0, 1) * np.clip((fbm(rng, 4) - 0.5) * 8, 0, 1)
    return lit(img * (1 - 0.6 * crack[..., None]), fine, 5.0, 8)


def tower(rng):  # THE TOWER: worn flagstones; smaller, darker broken paving
    a = flags(rng, 60, [(0, (36, 30, 46)), (0.5, (58, 48, 68)), (1, (84, 72, 94))], 26)
    b = flags(rng, 190, [(0, (26, 22, 34)), (0.5, (42, 36, 52)), (1, (62, 54, 72))], 40)
    return a, b


def plates(rng, count, heat):
    f1, f2, ident = cells_map(rng, count)
    gap = f2 - f1
    crack = np.clip(1 - gap / 2.4, 0, 1)
    fine = fbm(rng, 64, 2)
    shade = rng.uniform(-1, 1, count)[ident]
    ash = ramp(np.clip(0.5 + 0.25 * shade + 0.5 * (fine - 0.5), 0, 1), [(0, (34, 22, 22)), (0.6, (60, 38, 32)), (1, (84, 54, 44))])
    ash = lit(ash, np.clip(gap / 6.0, 0, 1), 1.6, 26)
    img = ash * (1 - 0.8 * crack[..., None])
    if heat > 0:
        img += (crack * heat)[..., None] * np.array([190.0, 70.0, 16.0])
        img += (np.clip(1 - gap / 7.0, 0, 1) * heat * 0.25)[..., None] * np.array([120.0, 30.0, 6.0])
    return img


def edge(rng):  # THE EDGE: cracked ash plates; plates with embers in the cracks
    return plates(rng, 90, 0.0), plates(rng, 90, 1.0)


def cobbles(rng, count, puddle):
    """Dark wet cobbles for the town plaza: domed stones, grimy joints, a cold sheen on the upper left of each.
    puddle > 0 floods the low places with still, dark water (the `b` tile)."""
    f1, f2, ident = cells_map(rng, count, grid=True)
    count = ident.max() + 1
    gap = f2 - f1
    joint = np.clip(gap / 2.8, 0, 1)
    dome = np.clip(gap / 9.0, 0, 1) ** 0.7
    shade = rng.uniform(-1, 1, count)[ident]
    fine = fbm(rng, 64, 2)
    v = 0.5 + 0.22 * shade + 0.3 * (fine - 0.5)
    img = ramp(np.clip(v, 0, 1), [(0, (33, 36, 47)), (0.5, (47, 51, 65)), (1, (65, 70, 87))])
    img = lit(img, dome, 2.2, 15)
    sheen = np.clip(emboss(dome, 4.0) - 0.55, 0, 1)
    img = img + sheen[..., None] * np.array([12.0, 16.0, 26.0])
    grime = ramp(norm(fbm(rng, 24, 3)), [(0, (24, 26, 32)), (1, (32, 38, 38))])
    img = img * (0.35 + 0.65 * joint[..., None]) + grime * (1 - joint[..., None]) * 0.65
    if puddle > 0:
        depth = norm(fbm(rng, 3, 3))
        w = np.clip((depth - (1 - puddle)) * 9, 0, 1)[..., None]
        water = ramp(np.clip(0.35 + 0.3 * (fine - 0.5) + 0.5 * dome, 0, 1), [(0, (12, 16, 26)), (1, (34, 46, 68))])
        glint = (rng.random((N, N)) < 0.003)[..., None]
        water = np.where(glint, water + 40, water)
        img = img * (1 - w) + (water * 0.85 + img * 0.15) * w
    return lit(img, fine, 5.0, 6)


def town(rng):  # THE PLAZA: wet dark cobbles; cobbles with standing water between
    return cobbles(rng, 400, 0.0), cobbles(rng, 400, 0.4)


def save(img, path, colours=40):
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
    im = im.quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    im.save(path, optimize=True)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for k, f in enumerate([road, wood, marsh, peaks, tower, edge]):
        a, b = f(np.random.default_rng(7100 + k))
        save(a, out / ("ground_%da.png" % k))
        save(b, out / ("ground_%db.png" % k))
    a, b = town(np.random.default_rng(7106))
    save(a, out / "ground_towna.png", 48)
    save(b, out / "ground_townb.png", 48)
    rng = np.random.default_rng(7199)
    for name in ["ground_blotch.png", "ground_patch.png"]:
        m = fbm(rng, 4, 4)
        Image.fromarray((norm(m) * 255).astype(np.uint8), "L").resize((128, 128), Image.BILINEAR).save(out / name, optimize=True)


if __name__ == "__main__":
    main()

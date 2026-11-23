"""Item and stack icons, 32x32, transparent, one dark gothic palette, 1 px outline (like post.py's sprites).

  python3 tools/char3d/build_icons.py <out dir> [KayKit adventurers gltf Assets dir] [name ...]

Needs only Pillow and numpy (no Blender). Three ways to make a picture, listed per icon in icons.txt:
  gltf  a KayKit CC0 weapon mesh drawn by the small z-buffer renderer below (flat 3-tone light, textures sampled)
  draw  a primitive model: shapes drawn at 4x with a light rim and a shadow rim, shrunk with palette snap
  every picture is then shrunk 4x -> 1x by block average snapped to PAL, and outlined.
The rarity frame is NOT in the files: realm/client/ui/ui_art.gd draws it behind the picture.
"""
import sys, os, json, math, struct
import numpy as np
from PIL import Image, ImageDraw, ImageChops

N = 32          # final size
S = 4           # supersample
W = N * S
OUT = (16, 11, 18)

# ---- colour ramps: (shadow, mid, light)
R = {
    "steel": ((52, 56, 70), (112, 120, 136), (186, 192, 204)),
    "iron": ((30, 30, 38), (66, 68, 80), (108, 112, 126)),
    "wood": ((48, 30, 20), (92, 60, 38), (140, 98, 62)),
    "leather": ((44, 28, 24), (88, 58, 44), (132, 92, 66)),
    "bone": ((92, 84, 66), (162, 152, 124), (220, 212, 182)),
    "blood": ((58, 12, 18), (116, 24, 28), (178, 50, 42)),
    "plum": ((38, 22, 54), (78, 48, 102), (122, 84, 148)),
    "gold": ((82, 58, 16), (172, 132, 46), (240, 200, 100)),
    "ember": ((96, 28, 10), (210, 90, 24), (255, 176, 70)),
    "ash": ((50, 48, 54), (110, 106, 112), (176, 172, 176)),
    "moss": ((24, 44, 30), (52, 88, 54), (98, 140, 90)),
    "slate": ((30, 38, 54), (62, 78, 108), (112, 138, 176)),
    "glass": ((30, 70, 78), (64, 140, 150), (150, 214, 214)),
    "red": ((70, 10, 22), (150, 28, 40), (224, 80, 76)),
    "cream": ((110, 98, 74), (190, 176, 140), (238, 228, 196)),
    "ink": ((10, 10, 22), (26, 26, 50), (58, 58, 98)),
    "amber": ((90, 52, 8), (190, 120, 24), (246, 190, 80)),
    "white": ((150, 150, 160), (214, 214, 222), (252, 252, 255)),
    "violet": ((48, 20, 70), (112, 52, 150), (176, 110, 214)),
}
PAL = np.array([c for r in R.values() for c in r] + [OUT], np.uint8)


class Canvas:
    def __init__(self):
        self.im = Image.new("RGBA", (W, W), (0, 0, 0, 0))

    def _mask(self, fn):
        m = Image.new("L", (W, W), 0)
        fn(ImageDraw.Draw(m))
        return m

    def shape(self, fn, ramp, bevel=1.4, flat=False):
        """fn(draw) draws white shapes in 32-unit coordinates through `u`; filled with a ramp, rimmed light and dark."""
        r = R[ramp] if isinstance(ramp, str) else ramp
        m = self._mask(fn)
        b = max(1, int(bevel * S / 2))
        self.im.paste(Image.new("RGBA", (W, W), r[1] + (255,)), (0, 0), m)
        if not flat:
            lit = ImageChops.subtract(m, ImageChops.offset(m, b, b))
            dk = ImageChops.subtract(m, ImageChops.offset(m, -b, -b))
            self.im.paste(Image.new("RGBA", (W, W), r[2] + (255,)), (0, 0), lit)
            self.im.paste(Image.new("RGBA", (W, W), r[0] + (255,)), (0, 0), dk)

    def line(self, pts, col, w=1.0):
        d = ImageDraw.Draw(self.im)
        p = [(x * S, y * S) for x, y in pts]
        d.line(p, fill=col + (255,), width=max(1, int(w * S)), joint="curve")

    def dots(self, pts, col, r=0.6):
        d = ImageDraw.Draw(self.im)
        for x, y in pts:
            d.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=col + (255,))


def u(pts):
    return [(x * S, y * S) for x, y in pts]


def poly(pts):
    return lambda d: d.polygon(u(pts), fill=255)


def ell(cx, cy, rx, ry=None):
    ry = rx if ry is None else ry
    return lambda d: d.ellipse([(cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S], fill=255)


def rect(x0, y0, x1, y1):
    return lambda d: d.rectangle([x0 * S, y0 * S, x1 * S, y1 * S], fill=255)


def many(*fns):
    return lambda d: [f(d) for f in fns]


def stroke(pts, w):
    """A thick polyline as a shape."""
    def f(d):
        d.line(u(pts), fill=255, width=max(1, int(w * S)), joint="curve")
        for x, y in pts:
            d.ellipse([(x - w / 2) * S, (y - w / 2) * S, (x + w / 2) * S, (y + w / 2) * S], fill=255)
    return f


def arc(cx, cy, rx, ry, a0, a1, w):
    def f(d):
        pts = [(cx + rx * math.cos(math.radians(a)), cy + ry * math.sin(math.radians(a))) for a in np.linspace(a0, a1, 24)]
        stroke(pts, w)(d)
    return f


# ---------------------------------------------------------------- shrink
def finish(cv):
    a = np.asarray(cv.im).astype(np.float32).reshape(N, S, N, S, 4)
    cov = a[..., 3].mean((1, 3)) / 255.0
    rgb = (a[..., :3] * a[..., 3:4]).sum((1, 3)) / np.maximum(a[..., 3].sum((1, 3))[..., None], 1)
    d = ((rgb[:, :, None, :] - PAL[None, None, :, :].astype(np.float32)) ** 2).sum(-1)
    snap = PAL[d.argmin(-1)]
    solid = cov >= 0.5
    img = np.zeros((N, N, 4), np.uint8)
    img[solid, :3] = snap[solid]
    img[solid, 3] = 255
    # 1 px outline round the shape
    pad = np.pad(solid, 1)
    nb = pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
    edge = nb & ~solid
    img[edge] = OUT + (255,)
    return Image.fromarray(img, "RGBA")


# ---------------------------------------------------------------- KayKit glTF (CC0) through a tiny z-buffer
def load_gltf(path):
    g = json.load(open(path))
    buf = open(os.path.join(os.path.dirname(path), g["buffers"][0]["uri"]), "rb").read()

    def acc(i):
        a = g["accessors"][i]
        bv = g["bufferViews"][a["bufferView"]]
        ct = {5126: ("f4", 4), 5123: ("u2", 1), 5125: ("u4", 1)}[a["componentType"]]
        nc = {"VEC3": 3, "VEC2": 2, "SCALAR": 1}[a["type"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        arr = np.frombuffer(buf, ct[0], a["count"] * nc, off).reshape(a["count"], nc)
        return arr.astype(np.float32 if ct[0] == "f4" else np.int64)
    p = g["meshes"][0]["primitives"][0]
    pos, uv, idx = acc(p["attributes"]["POSITION"]), acc(p["attributes"]["TEXCOORD_0"]), acc(p["indices"]).ravel()
    tex = np.asarray(Image.open(os.path.join(os.path.dirname(path), g["images"][0]["uri"])).convert("RGB"))
    return pos, uv, idx.reshape(-1, 3), tex


def render_gltf(path, deg=-45, flip=False, scale=0.72, light=(-0.4, 0.6, 0.7)):
    pos, uv, tri, tex = load_gltf(path)
    p = pos[:, :2].copy()
    z = pos[:, 2].copy()
    if flip:
        p[:, 0] *= -1
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    p = np.stack([p[:, 0] * c - p[:, 1] * s, p[:, 0] * s + p[:, 1] * c], 1)
    lo, hi = p.min(0), p.max(0)
    k = scale * W / max(hi - lo)
    p = (p - (lo + hi) / 2) * k + W / 2
    p[:, 1] = W - p[:, 1]
    zb = np.full((W, W), -1e9, np.float32)
    col = np.zeros((W, W, 3), np.float32)
    have = np.zeros((W, W), bool)
    L = np.array(light, np.float32)
    L /= np.linalg.norm(L)
    th, tw = tex.shape[:2]
    for t in tri:
        a, b, cc = p[t[0]], p[t[1]], p[t[2]]
        x0, x1 = int(max(min(a[0], b[0], cc[0]), 0)), int(min(max(a[0], b[0], cc[0]) + 1, W - 1))
        y0, y1 = int(max(min(a[1], b[1], cc[1]), 0)), int(min(max(a[1], b[1], cc[1]) + 1, W - 1))
        if x1 <= x0 or y1 <= y0:
            continue
        den = (b[1] - cc[1]) * (a[0] - cc[0]) + (cc[0] - b[0]) * (a[1] - cc[1])
        if abs(den) < 1e-9:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        w0 = ((b[1] - cc[1]) * (X - cc[0]) + (cc[0] - b[0]) * (Y - cc[1])) / den
        w1 = ((cc[1] - a[1]) * (X - cc[0]) + (a[0] - cc[0]) * (Y - cc[1])) / den
        w2 = 1 - w0 - w1
        m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not m.any():
            continue
        zz = w0 * z[t[0]] + w1 * z[t[1]] + w2 * z[t[2]]
        m &= zz > zb[y0:y1, x0:x1]
        if not m.any():
            continue
        # flat normal from the 3D triangle (z is depth, y is flipped in screen space, undo for light)
        v0 = np.array([a[0], -a[1], z[t[0]] * k]); v1 = np.array([b[0], -b[1], z[t[1]] * k]); v2 = np.array([cc[0], -cc[1], z[t[2]] * k])
        n = np.cross(v1 - v0, v2 - v0)
        n = n / (np.linalg.norm(n) + 1e-9)
        if n[2] < 0:
            n = -n
        shade = 0.55 + 0.6 * max(float(n @ L), 0.0)
        u_ = w0 * uv[t[0], 0] + w1 * uv[t[1], 0] + w2 * uv[t[2], 0]
        v_ = w0 * uv[t[0], 1] + w1 * uv[t[1], 1] + w2 * uv[t[2], 1]
        tc = tex[np.clip((v_ * th).astype(int), 0, th - 1), np.clip((u_ * tw).astype(int), 0, tw - 1)].astype(np.float32)
        sub = (slice(y0, y1), slice(x0, x1))
        zb[sub] = np.where(m, zz, zb[sub])
        col[sub] = np.where(m[..., None], tc * shade, col[sub])
        have[sub] |= m
    out = np.zeros((W, W, 4), np.uint8)
    out[..., :3] = np.clip(col * [0.95, 0.9, 0.92], 0, 255)
    out[..., 3] = have * 255
    cv = Canvas()
    cv.im = Image.fromarray(out, "RGBA")
    return cv


# ---------------------------------------------------------------- the pictures
ICONS = {}


def icon(name, how):
    def deco(f):
        ICONS[name] = (how, f)
        return f
    return deco


KK = {}


def kk(name, **kw):
    return render_gltf(os.path.join(KK["dir"], name + ".gltf"), **kw)


# ---- weapons
@icon("item_weapon_dirk", "gltf dagger.gltf")
def _():
    return kk("dagger", deg=-45)


@icon("item_weapon_cleaver", "gltf axe_1handed.gltf, mirrored")
def _():
    return kk("axe_1handed", deg=-40, flip=True)


@icon("item_weapon_staff", "gltf staff.gltf")
def _():
    return kk("staff", deg=-45, scale=0.8)


@icon("item_weapon_longbow", "draw: wood limb arc, string, nocked arrow")
def _():
    c = Canvas()
    c.shape(arc(11, 16, 10, 13, -75, 75, 2.4), "wood")
    c.line([(11 + 10 * math.cos(math.radians(-75)), 16 + 13 * math.sin(math.radians(-75))), (11 + 10 * math.cos(math.radians(75)), 16 + 13 * math.sin(math.radians(75)))], R["bone"][1], 0.7)
    c.shape(stroke([(11, 16), (29, 16)], 1.0), "wood", flat=True)
    c.shape(poly([(29, 16), (25.5, 14), (25.5, 18)]), "steel", flat=True)
    c.shape(poly([(11, 16), (8.5, 14), (13, 16), (8.5, 18)]), "blood", flat=True)
    return c


@icon("item_weapon_censer", "draw: three chains, gold bowl with lid and holes, smoke")
def _():
    c = Canvas()
    c.line([(16, 1), (16, 8)], R["iron"][2], 0.9)
    c.line([(16, 2), (7, 13)], R["iron"][2], 0.7)
    c.line([(16, 2), (25, 13)], R["iron"][2], 0.7)
    c.shape(poly([(8, 13), (24, 13), (22, 17), (10, 17)]), "gold")
    c.shape(poly([(7, 17), (25, 17), (22, 26), (10, 26)]), "gold")
    c.shape(rect(12, 26, 20, 29), "gold")
    c.dots([(12, 21), (16, 21), (20, 21)], R["gold"][0], 1.1)
    c.shape(stroke([(14, 11), (12, 8), (15, 5)], 1.3), "ash", flat=True)
    return c


@icon("item_weapon_mace", "draw: wood haft, flanged iron head")
def _():
    c = Canvas()
    c.shape(stroke([(8, 26), (20, 14)], 2.4), "wood")
    c.shape(stroke([(7, 27), (9, 25)], 3.2), "leather", flat=True)
    c.shape(many(ell(22, 10, 6.5), poly([(22, 1.5), (24, 5), (20, 5)]), poly([(30, 10), (26.5, 8), (26.5, 12)]), poly([(22, 18.5), (24, 15), (20, 15)]), poly([(14, 10), (17.5, 8), (17.5, 12)])), "steel")
    c.dots([(21, 9)], R["steel"][2], 1.0)
    return c


# ---- head
@icon("item_head_cowl", "draw: plum hood with dark face opening")
def _():
    c = Canvas()
    c.shape(poly([(16, 3), (24, 8), (27, 22), (22, 27), (10, 27), (5, 22), (8, 8)]), "plum")
    c.shape(ell(16, 17, 5.2, 6.5), "ink", flat=True)
    c.dots([(14, 16), (18, 16)], R["red"][2], 0.7)
    return c


@icon("item_head_helm", "draw: steel helm, visor slit, crest")
def _():
    c = Canvas()
    c.shape(many(poly([(7, 28), (7, 14), (10, 7), (16, 4), (22, 7), (25, 14), (25, 28)])), "steel")
    c.shape(rect(7, 14, 25, 16.5), "iron", flat=True)
    c.shape(rect(15, 5, 17, 28), "iron", flat=True)
    c.shape(rect(9, 19.5, 23, 21), "ink", flat=True)
    c.shape(poly([(16, 4), (14, 1), (18, 1)]), "blood", flat=True)
    return c


@icon("item_head_crown", "draw: gold circlet, three points, red gem")
def _():
    c = Canvas()
    c.shape(poly([(5, 24), (4, 9), (10, 15), (16, 5), (22, 15), (28, 9), (27, 24)]), "gold")
    c.shape(rect(5, 21, 27, 25), "gold")
    c.shape(ell(16, 17, 2.2, 2.8), "red")
    c.dots([(7, 18), (25, 18)], R["gold"][0], 1.0)
    return c


# ---- body
@icon("item_body_robe", "draw: long plum robe, gold sash, wide sleeves")
def _():
    c = Canvas()
    c.shape(poly([(12, 4), (20, 4), (23, 8), (28, 22), (24, 26), (22, 15), (24, 29), (8, 29), (10, 15), (8, 26), (4, 22), (9, 8)]), "plum")
    c.shape(poly([(12, 4), (16, 11), (20, 4)]), "ink", flat=True)
    c.shape(rect(10, 15, 22, 18), "gold")
    c.shape(rect(15, 18, 17, 28), "gold", flat=True)
    return c


@icon("item_body_mail", "draw: steel hauberk, ring rows, belt")
def _():
    c = Canvas()
    c.shape(poly([(11, 4), (21, 4), (26, 7), (29, 14), (24, 15), (23, 28), (9, 28), (8, 15), (3, 14), (6, 7)]), "steel")
    c.shape(poly([(12, 4), (16, 9), (20, 4)]), "iron", flat=True)
    for y in (13, 18, 23):
        c.line([(9, y), (23, y)], R["iron"][0], 0.6)
    c.shape(rect(8.5, 20, 23.5, 22.5), "leather")
    c.shape(rect(14.5, 19.5, 17.5, 23), "gold", flat=True)
    return c


@icon("item_body_coat", "draw: long leather coat, open front, buttons")
def _():
    c = Canvas()
    c.shape(poly([(11, 3), (21, 3), (26, 7), (28, 22), (24, 28), (18, 29), (17, 12), (15, 12), (14, 29), (8, 28), (4, 22), (6, 7)]), "leather")
    c.shape(poly([(15, 12), (17, 12), (18, 29), (14, 29)]), "ink", flat=True)
    c.dots([(11, 12), (11, 17), (11, 22), (21, 12), (21, 17), (21, 22)], R["gold"][2], 0.7)
    c.shape(poly([(11, 3), (16, 8), (21, 3), (19, 3), (16, 6), (13, 3)]), "bone", flat=True)
    return c


# ---- hands
def _hand(c, ramp, cuff):
    c.shape(many(rect(9, 7, 22, 24), rect(8, 14, 12, 18), poly([(8, 14), (4, 10), (6, 8), (10, 12)]), rect(9, 3, 11.4, 11), rect(12, 2, 14.4, 11), rect(15, 2, 17.4, 11), rect(18, 3, 20.4, 11)), ramp)
    c.shape(rect(8, 22, 24, 29), cuff)


@icon("item_hands_gloves", "draw: leather glove, four fingers, thumb, cuff")
def _():
    c = Canvas()
    _hand(c, "leather", "bone")
    return c


@icon("item_hands_gauntlets", "draw: steel gauntlet, knuckle plates, flared cuff")
def _():
    c = Canvas()
    _hand(c, "steel", "iron")
    c.line([(9, 11), (21, 11)], R["iron"][0], 0.6)
    c.dots([(10.2, 6), (13.2, 6), (16.2, 6), (19.2, 6)], R["steel"][2], 0.5)
    return c


@icon("item_hands_wraps", "draw: pale cloth wraps, diagonal bands, trailing end")
def _():
    c = Canvas()
    c.shape(many(rect(9, 7, 22, 24), poly([(8, 14), (4, 10), (6, 8), (10, 12)]), rect(9, 3, 20.4, 9)), "bone")
    for y in (10, 14, 18, 22):
        c.line([(9, y + 2), (22, y - 2)], R["bone"][0], 0.9)
    c.shape(poly([(20, 24), (23, 28), (21, 30), (18, 25)]), "bone", flat=True)
    c.dots([(11, 5), (14, 5), (17, 5)], R["bone"][0], 0.4)
    return c


# ---- feet
@icon("item_feet_boots", "draw: leather boot, tall shaft, sole, cuff")
def _():
    c = Canvas()
    c.shape(poly([(9, 4), (19, 4), (19, 20), (27, 23), (28, 28), (8, 28)]), "leather")
    c.shape(rect(8, 3, 20, 7), "bone")
    c.shape(rect(8, 27, 28, 29.5), "iron", flat=True)
    c.line([(9, 15), (19, 15)], R["leather"][0], 0.6)
    return c


@icon("item_feet_greaves", "draw: steel greave over shin, knee plate, foot")
def _():
    c = Canvas()
    c.shape(poly([(10, 2), (20, 2), (20, 19), (27, 23), (28, 28), (8, 28), (9, 19)]), "steel")
    c.shape(ell(15, 6, 6.5, 4.5), "iron")
    c.line([(15, 10), (15, 25)], R["iron"][0], 0.7)
    c.shape(rect(8, 27, 28, 29.5), "iron", flat=True)
    return c


@icon("item_feet_sandals", "draw: bare sole, straps, tied round the ankle")
def _():
    c = Canvas()
    c.shape(poly([(5, 27), (6, 22), (14, 19), (24, 21), (28, 25), (26, 29), (8, 29)]), "wood")
    for x in (12, 16, 20):
        c.line([(x, 21), (x + 2, 27)], R["leather"][2], 1.0)
    c.shape(poly([(8, 9), (14, 9), (14, 20), (9, 22)]), "bone", flat=True)
    c.line([(8, 13), (14, 13)], R["leather"][1], 1.0)
    c.line([(8, 17), (14, 17)], R["leather"][1], 1.0)
    return c


# ---- charms
@icon("item_charm_talisman", "draw: bone disc on cord, red eye rune")
def _():
    c = Canvas()
    c.line([(8, 2), (16, 9), (24, 2)], R["leather"][1], 1.0)
    c.shape(ell(16, 19, 9.5), "bone")
    c.shape(ell(16, 19, 6.5), "ink", flat=True)
    c.line([(16, 14), (16, 24)], R["red"][2], 1.2)
    c.line([(16, 17), (20, 14)], R["red"][2], 1.0)
    c.line([(16, 20), (20, 17)], R["red"][2], 1.0)
    return c


@icon("item_charm_ring", "draw: gold band seen at an angle, cut gem")
def _():
    c = Canvas()
    c.shape(many(ell(16, 20, 9.5, 8.5)), "gold")
    c.im.paste(Image.new("RGBA", (W, W), (0, 0, 0, 0)), (0, 0), c._mask(ell(16, 21, 5.4, 4.4)))
    c.shape(poly([(16, 4), (21, 9), (16, 14), (11, 9)]), "red")
    c.shape(poly([(14, 13), (18, 13), (17, 15), (15, 15)]), "gold", flat=True)
    return c


@icon("item_charm_amulet", "draw: gold chain, teardrop pendant with violet stone")
def _():
    c = Canvas()
    c.line([(5, 3), (10, 11), (16, 15), (22, 11), (27, 3)], R["gold"][1], 0.9)
    c.shape(poly([(16, 14), (23, 21), (16, 30), (9, 21)]), "gold")
    c.shape(poly([(16, 17), (20, 21), (16, 26), (12, 21)]), "violet")
    return c


# ---- stacks
@icon("stack_coin", "draw: stack of three gold coins, one leaning")
def _():
    c = Canvas()
    for i, y in enumerate((24, 19, 14)):
        c.shape(many(rect(6, y, 26, y + 4.5), ell(16, y, 10, 3.6), ell(16, y + 4.5, 10, 3.6)), "gold")
        c.shape(ell(16, y, 6.5, 2.2), (R["gold"][1], R["gold"][1], R["gold"][0]), flat=True)
        c.line([(6, y + 4.5), (16, y + 8.1), (26, y + 4.5)], R["gold"][0], 0.7)
    return c


@icon("stack_embers", "draw: three glowing coals with flame tips")
def _():
    c = Canvas()
    c.shape(many(ell(10, 24, 6, 4.5), ell(22, 24, 6, 4.5), ell(16, 20, 6, 5)), "ash")
    c.shape(poly([(16, 4), (21, 12), (19, 19), (13, 19), (11, 12)]), "ember")
    c.shape(poly([(16, 10), (18.5, 15), (17, 19), (14.5, 19), (13.5, 15)]), (R["ember"][2], R["ember"][2], R["gold"][2]), flat=True)
    c.dots([(9, 22), (23, 23)], R["ember"][1], 1.2)
    return c


def flask(c, ramp, body="round", fill=None):
    c.shape(rect(13, 3, 19, 6), "wood")
    c.shape(rect(14, 6, 18, 12), "glass", flat=True)
    if body == "round":
        c.shape(many(ell(16, 20, 9.5, 9), rect(14, 9, 18, 14)), "glass")
        c.shape(ell(16, 21, 7.5, 7), fill or ramp)
    else:
        c.shape(poly([(14, 9), (18, 9), (18, 14), (25, 27), (7, 27), (14, 14)]), "glass")
        c.shape(poly([(12, 19), (20, 19), (23, 26), (9, 26)]), fill or ramp)


@icon("stack_potion_0", "draw: round flask of red draught")
def _():
    c = Canvas(); flask(c, "red"); return c


@icon("stack_potion_1", "draw: triangle flask of grey smoke, a wisp")
def _():
    c = Canvas(); flask(c, "ash", "tri"); c.shape(stroke([(17, 1), (19, 3)], 1.0), "ash", flat=True); return c


@icon("stack_potion_2", "draw: round flask of amber oil with a whetstone")
def _():
    c = Canvas(); flask(c, "amber"); c.shape(poly([(21, 26), (28, 20), (30, 22), (23, 29)]), "slate"); return c


@icon("stack_potion_3", "draw: inkwell with a quill")
def _():
    c = Canvas()
    c.shape(many(ell(14, 22, 9, 6), rect(5, 14, 23, 22)), "ink")
    c.shape(ell(14, 14, 9, 3.5), "iron")
    c.shape(ell(14, 14, 5.5, 2), "ink", flat=True)
    c.shape(poly([(18, 14), (28, 2), (29, 4), (21, 15)]), "white")
    c.line([(18, 14), (28, 2)], R["white"][0], 0.5)
    return c


@icon("stack_potion_4", "draw: gold coin with a red die")
def _():
    c = Canvas()
    c.shape(ell(13, 17, 10), "gold")
    c.shape(ell(13, 17, 6.5), (R["gold"][1], R["gold"][1], R["gold"][0]), flat=True)
    c.shape(rect(17, 15, 28, 26), "bone")
    c.dots([(20, 18), (25, 18), (22.5, 20.5), (20, 23), (25, 23)], R["red"][1], 0.9)
    return c


@icon("stack_potion_5", "draw: ash urn with a flame and a feather")
def _():
    c = Canvas()
    c.shape(poly([(10, 14), (22, 14), (25, 22), (21, 29), (11, 29), (7, 22)]), "ash")
    c.shape(rect(9, 12, 23, 15), "iron")
    c.shape(poly([(16, 1), (21, 8), (19, 12), (13, 12), (11, 8)]), "ember")
    c.shape(poly([(16, 5), (18, 9), (17, 12), (15, 12), (14, 9)]), (R["ember"][2], R["ember"][2], R["gold"][2]), flat=True)
    return c


@icon("stack_potion", "draw: alias of stack_potion_0 (any other potion)")
def _():
    return ICONS["stack_potion_0"][1]()


@icon("stack_material_1", "draw: plague linen, a rolled cloth with stained end")
def _():
    c = Canvas()
    c.shape(many(rect(6, 11, 26, 23), ell(6, 17, 3, 6), ell(26, 17, 3, 6)), "cream")
    c.shape(ell(26, 17, 3, 6), "bone")
    c.line([(12, 11), (12, 23)], R["cream"][0], 0.7)
    c.line([(18, 11), (18, 23)], R["cream"][0], 0.7)
    c.dots([(9, 14), (22, 20)], R["moss"][1], 1.6)
    c.shape(poly([(26, 18), (30, 24), (24, 22)]), "cream", flat=True)
    return c


@icon("stack_material_2", "draw: gallows oak, two crossed logs with a rope")
def _():
    c = Canvas()
    c.shape(stroke([(5, 24), (27, 10)], 6), "wood")
    c.shape(stroke([(5, 10), (27, 24)], 6), "wood")
    c.dots([(5, 24), (27, 10), (5, 10), (27, 24)], R["bone"][1], 1.7)
    c.line([(12, 15), (21, 19)], R["bone"][1], 1.2)
    return c


@icon("stack_material_3", "draw: bog iron, a dark pitted ingot with green slime")
def _():
    c = Canvas()
    c.shape(poly([(4, 22), (9, 10), (25, 10), (29, 22), (26, 25), (7, 25)]), "iron")
    c.shape(poly([(9, 10), (25, 10), (27, 15), (6, 15)]), "slate")
    c.dots([(12, 19), (19, 21), (23, 18)], R["moss"][2], 1.1)
    return c


@icon("stack_material_4", "draw: rune slate, tablet with carved glyph")
def _():
    c = Canvas()
    c.shape(poly([(8, 28), (6, 8), (12, 3), (24, 4), (26, 26)]), "slate")
    c.line([(16, 9), (16, 24)], R["glass"][2], 1.2)
    c.line([(16, 12), (21, 17)], R["glass"][2], 1.2)
    c.line([(16, 17), (11, 22)], R["glass"][2], 1.2)
    return c


@icon("stack_material_5", "draw: stained glass shards, red blue gold")
def _():
    c = Canvas()
    c.shape(poly([(4, 14), (14, 4), (17, 18), (7, 24)]), "red")
    c.shape(poly([(16, 6), (28, 10), (22, 22), (16, 20)]), "slate")
    c.shape(poly([(12, 22), (22, 24), (17, 30), (9, 28)]), "gold")
    return c


@icon("stack_material_6", "draw: ash glass, pale shards with a black core")
def _():
    c = Canvas()
    c.shape(poly([(16, 2), (24, 14), (20, 28), (12, 28), (8, 14)]), "ash")
    c.shape(poly([(16, 8), (19, 15), (16, 24), (13, 15)]), "ink", flat=True)
    c.line([(16, 2), (16, 28)], R["ash"][2], 0.5)
    return c


@icon("stack_material", "draw: alias of stack_material_3 (any other material)")
def _():
    return ICONS["stack_material_3"][1]()


@icon("stack_trophy", "draw: horned boss skull on gold plate")
def _():
    c = Canvas()
    c.shape(ell(16, 28, 11, 2.5), "gold")
    c.shape(poly([(8, 14), (3, 7), (7, 4), (10, 10)]), "bone")
    c.shape(poly([(24, 14), (29, 7), (25, 4), (22, 10)]), "bone")
    c.shape(many(ell(16, 14, 8.5, 8), rect(11, 18, 21, 25)), "bone")
    c.shape(many(ell(12.5, 14, 2.4, 2.8), ell(19.5, 14, 2.4, 2.8)), "ink", flat=True)
    c.shape(poly([(16, 17), (17.5, 20), (14.5, 20)]), "ink", flat=True)
    c.line([(13, 23), (13, 25)], R["bone"][0], 0.6)
    c.line([(16, 23), (16, 25)], R["bone"][0], 0.6)
    c.line([(19, 23), (19, 25)], R["bone"][0], 0.6)
    return c


RUNE_STATS = [("might", "red", [[(16, 5), (16, 27)], [(16, 8), (23, 14)], [(16, 14), (23, 20)]]),
              ("focus", "slate", [[(11, 5), (11, 27)], [(11, 5), (22, 11)], [(22, 11), (11, 17)]]),
              ("swift", "moss", [[(9, 7), (23, 25)], [(23, 7), (9, 25)], [(16, 4), (16, 28)]]),
              ("vigor", "ember", [[(16, 5), (8, 16)], [(8, 16), (16, 27)], [(16, 27), (24, 16)], [(24, 16), (16, 5)]]),
              ("ward", "violet", [[(10, 5), (10, 27)], [(22, 5), (22, 27)], [(10, 16), (22, 16)]]),
              ("fortune", "gold", [[(16, 4), (16, 28)], [(16, 9), (8, 5)], [(16, 9), (24, 5)], [(9, 20), (23, 20)]])]


def rune_stone(stat):
    _, ramp, glyph = RUNE_STATS[stat]
    c = Canvas()
    c.shape(poly([(8, 28), (5, 12), (11, 4), (22, 4), (27, 12), (24, 28)]), "iron")
    for seg in glyph:
        c.line(seg, R[ramp][2], 1.5)
    return c


for _i, (_n, _r, _g) in enumerate(RUNE_STATS):
    icon("stack_rune_" + _n, "draw: dark stone, %s glyph in %s" % (_n, _r))((lambda i: lambda: rune_stone(i))(_i))
icon("stack_rune", "draw: alias of stack_rune_might (fallback)")(lambda: rune_stone(0))


@icon("stack_key", "draw: iron vault key, ring bow, toothed bit")
def _():
    c = Canvas()
    c.shape(arc(9, 9, 5.2, 5.2, 0, 360, 3.0), "gold")
    c.shape(stroke([(12, 12), (26, 26)], 2.6), "gold")
    c.shape(many(rect(21, 23, 24, 29), rect(24, 21, 28, 24)), "gold")
    return c


@icon("stack_page", "draw: torn page with text lines and a seal")
def _():
    c = Canvas()
    c.shape(poly([(7, 3), (22, 3), (26, 8), (25, 29), (10, 28), (8, 24), (6, 18)]), "cream")
    for y in (9, 13, 17):
        c.line([(10, y), (22, y)], R["cream"][0], 0.9)
    c.shape(ell(19, 23, 3.4), "red")
    return c


@icon("stack_card", "draw: tarot-style monster card, plum back with gold sigil")
def _():
    c = Canvas()
    c.shape(poly([(7, 3), (25, 3), (25, 29), (7, 29)]), "plum")
    c.line([(9, 5), (23, 5), (23, 27), (9, 27), (9, 5)], R["gold"][1], 0.7)
    c.shape(poly([(16, 9), (20, 16), (16, 23), (12, 16)]), "gold")
    c.shape(ell(16, 16, 1.8), "ink", flat=True)
    return c


def main():
    a = sys.argv[1:]
    out = a[0]
    KK["dir"] = a[1] if len(a) > 1 else "/home/claude/kaykit-game-assets/kaykit-character-pack-adventures-1.0/addons/kaykit_character_pack_adventures/Assets/gltf"
    want = a[2:] or list(ICONS)
    os.makedirs(out, exist_ok=True)
    for n in want:
        finish(ICONS[n][1]()).save(os.path.join(out, "ui_%s.png" % n))
    print("icons", len(want), "->", out)


if __name__ == "__main__":
    main()

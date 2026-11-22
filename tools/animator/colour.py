"""Colour: OKLab (Ottosson 2020), the still's palette, and the far-limb shade.

* `quantize(img, n)`: the full-size stills are painted, not palette art (14k-31k colours), so
  every still is reduced once to PALETTE_N colours (PIL median cut, no dithering); from then on
  every baked pixel is one of those colours ("palette locked").
* `darken(rgb, pal)`: the far arm / far leg shade.  v1 multiplied RGB by 0.7 and snapped to the
  palette by weighted RGB distance, which turned skin red-brown and read too dark.  Now: in
  OKLab keep hue (a:b ratio), lower lightness by FAR_L (25 %) and chroma by FAR_C, then snap to
  the palette with hue/chroma weighted above lightness (SNAP_W), so a shaded skin stays skin.
"""
import numpy as np
from PIL import Image

PALETTE_N = 48     # colours per character: enough for skin/cloth/metal ramps at 56 px
FAR_L = 0.75       # far limb lightness factor (owner: "too dark"; v1 was 0.7 of RGB value)
FAR_C = 0.90       # far limb chroma factor (a touch greyer, as in shadow)
SNAP_W = (1.0, 2.0, 2.0)   # L, a, b weights for the palette snap of shaded colours


def _lin(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _gam(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055) * 255.0


def to_oklab(rgb):
    r, g, b = [_lin(np.asarray(rgb, float)[..., i]) for i in range(3)]
    l = np.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = np.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = np.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return np.stack([0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s], -1)


def from_oklab(lab):
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return np.stack([_gam(r), _gam(g), _gam(bb)], -1)


def quantize(img, n=PALETTE_N):
    """Opaque pixels -> n colours (median cut, no dither). Returns (img, palette (k,3))."""
    a = img[..., 3] > 0
    if not a.any():
        return img.copy(), np.zeros((0, 3), np.uint8)
    px = img[a][:, :3]
    side = int(np.ceil(np.sqrt(len(px))))
    buf = np.zeros((side * side, 3), np.uint8)
    buf[:len(px)] = px
    buf[len(px):] = px[0]
    q = Image.fromarray(buf.reshape(side, side, 3), "RGB").quantize(
        colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = np.array(q.getpalette()[:3 * n], np.uint8).reshape(-1, 3)
    idx = np.array(q).ravel()[:len(px)]
    out = img.copy()
    out[a, :3] = pal[idx]
    used = np.unique(idx)
    return out, pal[used]


def snap(rgb, pal, w=(1.0, 1.0, 1.0)):
    """Nearest palette colour in OKLab with per-axis weights."""
    if len(rgb) == 0:
        return np.zeros((0, 3), np.uint8)
    L1 = to_oklab(np.asarray(rgb, float)) * w
    L2 = to_oklab(pal.astype(float)) * w
    d = ((L1[:, None, :] - L2[None, :, :]) ** 2).sum(-1)
    return pal[np.argmin(d, 1)].astype(np.uint8)


def darken(rgb, pal, light=FAR_L, chroma=FAR_C):
    """Shade colours: OKLab lightness x light, chroma x chroma, hue kept, snapped to pal."""
    lab = to_oklab(np.asarray(rgb, float))
    lab[..., 0] *= light
    lab[..., 1:] *= chroma
    target = from_oklab(lab)
    return snap(target, pal, SNAP_W)


SKIN_MIN_SHARE = 0.01     # share of the hand's pixels a palette colour needs to count as skin
SKIN_MIN_CHROMA = 0.04    # OKLab chroma under which a colour is outline / grey, never skin
SKIN_HUE = 40.0           # deg from the hand's median hue
FALSE_SKIN_AB = 0.03      # OKLab ab distance between a pixel as drawn and its palette colour


def skin_palette(img, hand_mask, pal=None):
    """The palette colours (k,3) that are the body's skin: the quantized colours of the hand's
    pixels that have chroma and the hand's hue (outline black and grey are not skin)."""
    m = hand_mask & (img[..., 3] > 0)
    if m.sum() < 6:
        return np.zeros((0, 3), np.uint8)
    cols, n = np.unique(img[m][:, :3], axis=0, return_counts=True)
    lab = to_oklab(cols.astype(float))
    ch = np.hypot(lab[:, 1], lab[:, 2])
    ok = (n >= SKIN_MIN_SHARE * m.sum()) & (ch >= SKIN_MIN_CHROMA)
    if not ok.any():
        return np.zeros((0, 3), np.uint8)
    w = n * ok
    ref = np.arctan2(*(lab[ok][np.argmax(w[ok])][[2, 1]]))
    hue = np.degrees(np.abs((np.arctan2(lab[:, 2], lab[:, 1]) - ref + np.pi) % (2 * np.pi) - np.pi))
    return cols[ok & (hue < SKIN_HUE)]


def repair_false_skin(quant, raw, region, skin, pal):
    """Median cut spends too few colours on a rare grey or gold and may give such a pixel (a
    knee-guard's rim, a buckle) the nearest skin shade: a skin speck on the trousers.  Every pixel of
    `region` whose quantized colour is skin but whose drawn colour was not takes the nearest palette
    colour that is not skin.  Returns a copy of quant."""
    out = quant.copy()
    if not len(skin) or not region.any():
        return out
    ys, xs = np.where(region & (quant[..., 3] > 0))
    if not len(ys):
        return out
    q = quant[ys, xs, :3]
    is_skin = (q[:, None, :] == skin[None, :, :]).all(-1).any(1)
    lab_raw = to_oklab(raw[ys, xs, :3].astype(float))
    lab_q = to_oklab(q.astype(float))
    far = np.hypot(*(lab_raw - lab_q)[:, 1:].T) > FALSE_SKIN_AB
    bad = is_skin & far
    if not bad.any():
        return out
    keep = pal[~(pal[:, None, :] == skin[None, :, :]).all(-1).any(1)]
    if not len(keep):
        return out
    out[ys[bad], xs[bad], :3] = snap(raw[ys[bad], xs[bad], :3], keep, SNAP_W)
    return out

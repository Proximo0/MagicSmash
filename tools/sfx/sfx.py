#!/usr/bin/env python3
"""HORDE & HEARTH sound effects, synthesised from noise, oscillators, envelopes and filters. Python 3 + numpy only.

REGENERATE
    python3 tools/sfx/sfx.py            # writes realm/client/audio/sfx/<name>.wav (16-bit mono 44.1 kHz)
    python3 tools/sfx/sfx.py --list     # prints the sound names
    python3 tools/sfx/sfx.py hit_1 bell # only these
    python3 tools/sfx/sfx.py --seed=7 --out=DIR
The same seed gives byte-identical files (each sound seeds its own generator from the seed and its name).
After adding or changing a sound, open the Godot project once so the .import file of a new WAV is made, and add the
name to FieldSound / the hook table in realm/client/field/field_sound.gd. Tone: dark, occult, gritty.
"""
import os
import sys
import wave
import zlib

import numpy as np

SR = 44100
SEED = 1337
MAX_SECS = 2.4


# ---------------------------------------------------------------- building blocks
class Ctx:
    def __init__(self, seed, name):
        self.rng = np.random.default_rng([seed, zlib.crc32(name.encode())])

    def noise(self, secs):
        return self.rng.uniform(-1.0, 1.0, int(secs * SR))


def tt(secs):
    return np.arange(int(secs * SR)) / SR


def env(n, attack=0.002, decay=0.1, curve=3.0):
    """Linear attack, then exponential-ish decay over the rest (decay is the time to fall by e^-curve)."""
    t = np.arange(n) / SR
    a = np.minimum(1.0, t / max(attack, 1e-4))
    return a * np.exp(-curve * t / max(decay, 1e-3))


def sweep(f0, f1, secs, power=1.0):
    """Frequency track from f0 to f1 (power > 1 bends it late)."""
    n = int(secs * SR)
    u = (np.arange(n) / max(n - 1, 1)) ** power
    return f0 + (f1 - f0) * u


def osc(freq, kind="sine", phase0=0.0):
    freq = np.asarray(freq, dtype=float)
    ph = phase0 + 2 * np.pi * np.cumsum(freq) / SR
    if kind == "sine":
        return np.sin(ph)
    if kind == "square":
        return np.sign(np.sin(ph) + 1e-9)
    if kind == "saw":
        return 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    if kind == "tri":
        return 2.0 * np.abs(2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0) - 1.0
    raise ValueError(kind)


def biquad(x, kind, f, q=0.707):
    """RBJ biquad: lp, hp, bp. f may be a number (cutoff Hz)."""
    w = 2 * np.pi * min(f, SR * 0.45) / SR
    al = np.sin(w) / (2 * q)
    c = np.cos(w)
    if kind == "lp":
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    else:
        b0, b1, b2 = al, 0.0, -al
    a0, a1, a2 = 1 + al, -2 * c, 1 - al
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.zeros(len(x))
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x.tolist()):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return y


def onepole(x, f):
    a = 1 - np.exp(-2 * np.pi * f / SR)
    y = np.zeros(len(x))
    s = 0.0
    for i, v in enumerate(x.tolist()):
        s += a * (v - s)
        y[i] = s
    return y


def lp_sweep(x, f0, f1, q=1.0, steps=16):
    """Low-pass whose cutoff moves f0 -> f1 (done in blocks, state carried by overlap-free processing)."""
    n = len(x)
    out = np.zeros(n)
    edges = np.linspace(0, n, steps + 1).astype(int)
    for k in range(steps):
        f = f0 * (f1 / f0) ** (k / max(steps - 1, 1))
        a, b = edges[k], edges[k + 1]
        lo = max(0, a - 256)
        out[a:b] = biquad(x[lo:b], "lp", f, q)[a - lo:]
    return out


def drive(x, amt=3.0):
    return np.tanh(x * amt) / np.tanh(amt)


def crush(x, bits=8):
    s = 2 ** (bits - 1)
    return np.round(x * s) / s


def delay_shift(x, secs):
    d = int(secs * SR)
    return np.concatenate([np.zeros(d), x])


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def at(x, secs, total):
    out = np.zeros(total)
    d = int(secs * SR)
    m = max(0, min(len(x), total - d))
    out[d:d + m] = x[:m]
    return out


def reverb(x, mixamt=0.25, size=1.0, tail=0.4):
    """Light Schroeder reverb: four combs into two allpasses."""
    n = len(x) + int(tail * SR)
    xp = np.concatenate([x, np.zeros(n - len(x))])
    acc = np.zeros(n)
    for d_ms, g in ((29.7, 0.77), (37.1, 0.75), (41.1, 0.73), (43.7, 0.71)):
        d = int(d_ms * size * SR / 1000)
        y = xp.copy()
        for s in range(d, n, d):
            e = min(s + d, n)
            y[s:e] += g * y[s - d:e - d]
        acc += y / 4
    for d_ms, g in ((5.0, 0.7), (1.7, 0.7)):
        d = int(d_ms * SR / 1000)
        y = acc.copy()
        for i in range(d, n):
            y[i] = -g * acc[i] + acc[i - d] + g * y[i - d]
        acc = y
    return xp * (1 - mixamt) + acc * mixamt * 2.0


def thump(freq0=140, freq1=45, secs=0.25, decay=0.08):
    f = sweep(freq0, freq1, secs, 0.5)
    return osc(f) * env(len(f), 0.001, decay, 4.0)


def metal(ctx, base, secs, decay, parts=(1.0, 2.76, 5.4, 8.93, 11.34)):
    """Inharmonic ring: a clang or a bell."""
    n = int(secs * SR)
    out = np.zeros(n)
    for k, r in enumerate(parts):
        ph = ctx.rng.uniform(0, 6.28)
        out += np.sin(2 * np.pi * base * r * tt(secs) + ph) * np.exp(-tt(secs) / (decay / (1 + 0.6 * k))) / (1 + 0.5 * k)
    return out


def choir(freq, secs, voices=5, detune=0.012, ctx=None, vib=5.0):
    """A dark drone: detuned saws through a low-pass, with a slow vibrato."""
    t = tt(secs)
    out = np.zeros(len(t))
    for k in range(voices):
        det = 1 + detune * (k - (voices - 1) / 2) / max(voices - 1, 1) * 2
        f = freq * det * (1 + 0.004 * np.sin(2 * np.pi * (vib + 0.3 * k) * t + k))
        out += osc(f, "saw", ctx.rng.uniform(0, 6) if ctx else 0)
    return out / voices


def norm(x, peak=0.8):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 1e-9 else x


def finish(x, peak=0.8, fade=0.01):
    x = norm(x, peak)
    f = int(fade * SR)
    if f and len(x) > f:
        x[-f:] *= np.linspace(1, 0, f)
    x[:8] *= np.linspace(0, 1, 8)
    return x


# ---------------------------------------------------------------- the sounds
def hit(ctx, v):
    """Hero melee hit: a steel slap over a body thump."""
    n = [0.16, 0.18, 0.2][v]
    s = ctx.noise(n)
    slap = biquad(s, "bp", [2400, 1900, 3000][v], 1.2) * env(len(s), 0.0005, 0.03)
    body = thump([170, 140, 120][v], 55, n, 0.07)
    ring = metal(ctx, [620, 540, 700][v], n, 0.05, (1.0, 2.76)) * 0.25
    return finish(drive(slap * 0.9 + body * 0.9 + ring, 2.0))


def spell(ctx, v):
    n = 0.5
    f = sweep([180, 260][v], [900, 520][v], n, 2.0)
    a = osc(f, "saw") * env(int(n * SR), 0.05, 0.25, 3.0)
    a = lp_sweep(a, 400, 3500, 2.0, 12)
    sh = biquad(ctx.noise(n), "bp", [3000, 1800][v], 2.0) * env(int(n * SR), 0.08, 0.2) * 0.6
    return finish(reverb(a * 0.7 + sh, 0.2, 0.8, 0.15))


def crit(ctx, v):
    n = 0.4
    s = ctx.noise(n)
    crack = biquad(s, "hp", 3500) * env(len(s), 0.0003, 0.025) * 1.2
    clang = metal(ctx, 880, n, 0.16)
    body = thump(220, 50, n, 0.12)
    return finish(drive(crack + clang * 0.7 + body * 1.1, 2.5))


def hurt(ctx, v):
    n = 0.35
    f = sweep([210, 170][v], [110, 80][v], n)
    vo = osc(f * (1 + 0.03 * np.sin(2 * np.pi * 30 * tt(n))), "saw")
    vo = biquad(vo, "bp", [900, 700][v], 2.5) * env(int(n * SR), 0.01, 0.12)
    sn = biquad(ctx.noise(0.15), "lp", 1500) * env(int(0.15 * SR), 0.001, 0.04)
    return finish(drive(mix(vo * 1.1, sn * 0.9, thump(120, 50, 0.2, 0.06) * 0.8), 2.0))


def hero_death(ctx, v):
    n = 1.2
    f = sweep(190, 45, n, 0.6)
    vo = osc(f, "saw") * env(int(n * SR), 0.02, 0.5, 3.0)
    vo = lp_sweep(vo, 1400, 150, 2.0, 16)
    low = thump(90, 30, 0.6, 0.25)
    return finish(reverb(drive(mix(vo, at(low, 0.5, int(n * SR))), 1.8), 0.3, 1.2, 0.5))


def mon_small(ctx, v):
    n = 0.35
    sq = osc(sweep([380, 300, 450][v], [90, 70, 110][v], n, 0.7), "square") * env(int(n * SR), 0.002, 0.1)
    sq = crush(biquad(sq, "lp", 1800), 6)
    wet = biquad(ctx.noise(n), "bp", [900, 1300, 700][v], 0.9)
    wet = wet * env(len(wet), 0.001, 0.07) * (0.6 + 0.4 * np.sin(2 * np.pi * 38 * tt(n)))
    return finish(drive(sq * 0.5 + wet * 1.0 + thump(130, 50, n, 0.07) * 0.5, 2.0))


def mon_big(ctx, v):
    n = 0.9
    f = sweep([110, 85][v], [30, 24][v], n, 0.5)
    roar = drive(osc(f, "saw"), 3) * env(int(n * SR), 0.01, 0.35, 3.0)
    roar = lp_sweep(roar, 1200, 120, 1.5, 14)
    wet = biquad(ctx.noise(n), "bp", 600, 0.7) * env(int(n * SR), 0.005, 0.15) * 1.4
    thud = at(thump(90, 28, 0.5, 0.2), 0.12, int(n * SR))
    return finish(reverb(drive(roar + wet + thud * 1.3, 1.6), 0.18, 1.0, 0.3))


def gold(ctx, v):
    n = 0.3
    a = metal(ctx, 2100, n, 0.07, (1.0, 1.5, 2.4))
    b = at(metal(ctx, 2800, n, 0.08, (1.0, 1.5, 2.4)), 0.05, int(n * SR))
    t = biquad(ctx.noise(0.02), "hp", 5000)
    return finish(mix(a * 0.6, b * 0.6, at(t, 0, int(n * SR)) * 0.4), 0.6)


def item(ctx, v):
    n = 0.25
    s = biquad(ctx.noise(n), "bp", 1100, 1.0) * env(int(n * SR), 0.003, 0.04) * 0.8
    k = osc(sweep(300, 160, n), "tri") * env(int(n * SR), 0.002, 0.06)
    return finish(drive(s + k + thump(110, 60, n, 0.04) * 0.5, 1.5), 0.7)


def rare(ctx, v):
    n = 1.4
    out = np.zeros(int(n * SR))
    for k, (fr, d) in enumerate(((660, 0), (990, 0.12), (1320, 0.24), (1760, 0.36))):
        out += at(metal(ctx, fr, 1.0, 0.45, (1.0, 2.0, 3.01)), d, len(out)) * (0.8 - 0.12 * k)
    return finish(reverb(out, 0.3, 1.3, 0.5), 0.7)


def levelup(ctx, v):
    n = 1.4
    notes = (220.0, 261.63, 329.63, 440.0)
    out = np.zeros(int(n * SR))
    for k, fr in enumerate(notes):
        d = 0.0 + k * 0.1
        c = choir(fr, 1.0, 4, 0.01, ctx) * env(int(1.0 * SR), 0.05, 0.6, 3.0)
        out += at(lp_sweep(c, 3000, 900, 1.0, 6), d, len(out)) * 0.5
    out += at(metal(ctx, 880, 1.2, 0.5, (1.0, 2.0, 3.0)), 0.3, len(out)) * 0.5
    return finish(reverb(out, 0.3, 1.3, 0.6), 0.75)


def horn(ctx, v):
    n = 2.3
    t = tt(n)
    f = 58 * (1 + 0.012 * np.sin(2 * np.pi * 4.5 * t)) * (1 + 0.05 * np.minimum(1, t / 0.5))
    h = osc(f, "saw") + 0.6 * osc(f * 2.003, "saw") + 0.4 * osc(f * 3.01, "square")
    e = np.minimum(1, t / 0.35) * np.minimum(1, (n - t) / 0.7)
    h = lp_sweep(h * e, 250, 1100, 2.0, 14)
    return finish(reverb(drive(h, 2.0), 0.3, 1.5, 0.4), 0.85, 0.05)


def boss_roar(ctx, v):
    n = 2.2
    t = tt(n)
    f = sweep(95, 38, n, 0.7) * (1 + 0.08 * np.sin(2 * np.pi * 22 * t))
    r = drive(osc(f, "saw") + 0.5 * osc(f * 1.5, "square"), 4)
    e = np.minimum(1, t / 0.12) * np.exp(-0.9 * t) * np.minimum(1, (n - t) / 0.5)
    r = lp_sweep(r * e, 1600, 160, 2.0, 18)
    g = biquad(ctx.noise(n), "bp", 500, 0.8) * e * 0.9 * (0.6 + 0.4 * np.sin(2 * np.pi * 17 * t))
    return finish(reverb(drive(r + g, 1.6), 0.25, 1.4, 0.5), 0.9, 0.08)


def boss_death(ctx, v):
    n = 2.4
    t = tt(n)
    r = osc(sweep(80, 20, n, 0.6), "saw") * np.exp(-1.1 * t)
    r = lp_sweep(drive(r, 3), 900, 80, 1.5, 16)
    boom = at(thump(110, 24, 1.0, 0.4), 0.1, int(n * SR))
    deb = biquad(ctx.noise(n), "lp", 2000) * np.exp(-3 * t) * 0.7
    deb *= 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 14 * t * (1 + t)))
    bell = at(metal(ctx, 110, 2.0, 0.9, (1.0, 2.4, 3.9)), 0.6, int(n * SR)) * 0.35
    return finish(reverb(drive(r + boom * 1.2 + deb, 1.8) + bell, 0.3, 1.5, 0.6), 0.9, 0.08)


def portal(ctx, v):
    n = 1.0
    t = tt(n)
    w = osc(sweep(110, 660, n, 2.0), "saw") * np.sin(np.pi * np.minimum(1, t / n)) ** 1.5
    w = lp_sweep(w, 300, 3000, 2.5, 14)
    sh = biquad(ctx.noise(n), "bp", 2500, 3.0) * np.sin(np.pi * t / n) * 0.5
    c = choir(220, n, 3, 0.02, ctx) * np.sin(np.pi * t / n) * 0.3
    return finish(reverb(w * 0.8 + sh + c, 0.35, 1.3, 0.5), 0.75)


def ui_click(ctx, v):
    n = 0.07
    k = osc(sweep(900, 400, n), "tri") * env(int(n * SR), 0.0005, 0.02)
    s = biquad(ctx.noise(n), "bp", 2200, 1.5) * env(int(n * SR), 0.0003, 0.012)
    return finish(k * 0.6 + s * 0.6, 0.5, 0.005)


def ui_open(ctx, v):
    n = 0.4
    s = biquad(ctx.noise(n), "bp", 3200, 0.8)
    f = np.sin(np.pi * np.minimum(1, tt(n) / 0.25)) ** 2 * np.exp(-3 * tt(n))
    s = s * f
    flap = at(biquad(ctx.noise(0.05), "lp", 900) * env(int(0.05 * SR), 0.001, 0.015), 0.19, int(n * SR))
    return finish(s * 0.8 + flap * 1.5, 0.55)


def ui_error(ctx, v):
    n = 0.22
    a = osc(np.full(int(n * SR), 130.0), "square") * env(int(n * SR), 0.002, 0.12)
    b = osc(np.full(int(n * SR), 137.0), "square") * env(int(n * SR), 0.002, 0.12)
    return finish(biquad(a + b, "lp", 900) * 0.8, 0.55)


def bell(ctx, v):
    n = 2.2
    b = metal(ctx, 196, n, 1.1, (1.0, 2.0, 2.4, 3.0, 4.07, 5.43))
    st = biquad(ctx.noise(0.02), "lp", 3000) * 0.5
    return finish(reverb(b + at(st, 0, len(b)), 0.25, 1.4, 0.5), 0.8, 0.1)


def chest(ctx, v):
    n = 0.6
    cr = osc(sweep(170, 130, 0.35) * (1 + 0.15 * np.sin(2 * np.pi * 40 * tt(0.35))), "saw")
    cr = biquad(cr, "bp", 600, 3.0) * env(int(0.35 * SR), 0.01, 0.15)
    th = at(thump(120, 45, 0.3, 0.09), 0.3, int(n * SR))
    ch = at(metal(ctx, 1500, 0.25, 0.06, (1.0, 1.5, 2.7)), 0.34, int(n * SR)) * 0.4
    return finish(reverb(mix(cr * 0.9, th, ch), 0.15, 0.8, 0.2), 0.75)


# name -> (function, variants, seed-independent note)
SOUNDS = [
    ("hit", hit, 3), ("spell", spell, 2), ("crit", crit, 1), ("hurt", hurt, 2), ("hero_death", hero_death, 1),
    ("mon_small", mon_small, 3), ("mon_big", mon_big, 2), ("gold", gold, 1), ("item", item, 1),
    ("rare", rare, 1), ("level_up", levelup, 1), ("horn", horn, 1), ("boss_roar", boss_roar, 1),
    ("boss_death", boss_death, 1), ("portal", portal, 1), ("ui_click", ui_click, 1), ("ui_open", ui_open, 1),
    ("ui_error", ui_error, 1), ("bell", bell, 1), ("chest", chest, 1),
]


def names():
    out = []
    for name, _fn, count in SOUNDS:
        out += [name] if count == 1 else ["%s_%d" % (name, i + 1) for i in range(count)]
    return out


def render(name, seed):
    for base, fn, count in SOUNDS:
        if count == 1 and name == base:
            return fn(Ctx(seed, name), 0)
        if count > 1 and name.startswith(base + "_") and name[len(base) + 1:].isdigit():
            return fn(Ctx(seed, name), int(name[len(base) + 1:]) - 1)
    raise SystemExit("unknown sound " + name)


def write_wav(path, x):
    cap = int(MAX_SECS * SR)
    if len(x) > cap:  # a reverb tail that runs long is cut with a fade
        x = x[:cap].copy()
        x[-int(0.2 * SR):] *= np.linspace(1, 0, int(0.2 * SR))
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main(argv):
    seed = SEED
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "realm", "client", "audio", "sfx")
    want = []
    for a in argv:
        if a == "--list":
            print("\n".join(names()))
            return
        elif a.startswith("--seed="):
            seed = int(a[7:])
        elif a.startswith("--out="):
            out = a[6:]
        else:
            want.append(a)
    os.makedirs(out, exist_ok=True)
    total = 0
    for name in want or names():
        x = render(name, seed)
        p = os.path.join(out, name + ".wav")
        write_wav(p, x)
        total += os.path.getsize(p)
    print("sfx: %d files, %d bytes in %s" % (len(want or names()), total, os.path.normpath(out)))


if __name__ == "__main__":
    main(sys.argv[1:])

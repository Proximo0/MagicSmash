#!/usr/bin/env python3
"""Generates all Magic Smash sound effects as .wav files.

The music is made separately by tools/music (see tools/music/SOUNDTRACK.md).

Run from the project root:  python3 tools/gen_audio.py
Everything is synthesised (square/triangle/noise voices, like a 16-bit
console, plus filtered noise, pitch envelopes, short reverb tails and soft
clipping), so there are no licensing questions and it is easy to tweak.
Output: 22050 Hz mono 16-bit wav in assets/audio.
"""
import os
import wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)


# ------------------------------------------------------------ helpers ----
def n_of(dur):
    return int(SR * dur)


def t_of(dur):
    return np.arange(n_of(dur)) / SR


def phase_of(freq, n=None):
    """freq may be a scalar (needs n) or an array (sweeps)."""
    if n is not None and np.isscalar(freq):
        freq = np.full(n, float(freq))
    freq = np.asarray(freq, dtype=np.float64)
    return np.cumsum(freq) / SR


def sine(freq, n=None, ph0=0.0):
    return np.sin(2 * np.pi * (phase_of(freq, n) + ph0))


def square(freq, duty=0.5, n=None):
    ph = phase_of(freq, n) % 1.0
    return np.where(ph < duty, 1.0, -1.0)


def triangle(freq, n=None):
    ph = phase_of(freq, n) % 1.0
    return 4 * np.abs(ph - 0.5) - 1


def saw(freq, n=None):
    ph = phase_of(freq, n) % 1.0
    return 2 * ph - 1


def noise(n, hold=1):
    v = rng.uniform(-1, 1, n // hold + 1)
    return np.repeat(v, hold)[:n]


def sweep(f0, f1, dur, curve=1.0):
    t = np.linspace(0, 1, n_of(dur)) ** curve
    return f0 + (f1 - f0) * t


def expsweep(f0, f1, dur):
    """Exponential (musical) pitch glide."""
    t = np.linspace(0, 1, n_of(dur))
    return f0 * (f1 / f0) ** t


def env(n, attack=0.002, decay_pow=1.0):
    t = np.linspace(0, 1, n)
    a = max(1, int(attack * SR))
    e = (1 - t) ** decay_pow
    e[:a] *= np.linspace(0, 1, a)
    return e


def edecay(n, tau, attack=0.001):
    """Exponential decay with time constant tau seconds and a linear attack."""
    e = np.exp(-np.arange(n) / SR / tau)
    a = min(n, max(1, int(attack * SR)))
    e[:a] *= np.linspace(0, 1, a)
    return e


def swell(n, rise, fall_pow=1.5):
    """Slow rise to a peak at `rise` (0..1 of length) then a fall."""
    t = np.linspace(0, 1, n)
    up = np.clip(t / max(rise, 1e-4), 0, 1)
    down = np.clip((1 - t) / max(1 - rise, 1e-4), 0, 1) ** fall_pow
    return np.sin(up * np.pi / 2) * down


def _k_of(cut):
    cut = np.asarray(cut, dtype=np.float64)
    return 1 - np.exp(-2 * np.pi * np.clip(cut, 10, SR * 0.45) / SR)


def lp(x, cut):
    """One-pole low-pass; `cut` (Hz) may be an array for filter sweeps."""
    k = _k_of(cut)
    k = np.broadcast_to(k, x.shape)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(x.size):
        acc += k[i] * (x[i] - acc)
        y[i] = acc
    return y


def lp2(x, cut):
    return lp(lp(x, cut), cut)


def hp(x, cut):
    return x - lp(x, cut)


def bp(x, freq, q=4.0):
    """Biquad band-pass (constant peak gain); freq may be an array."""
    freq = np.broadcast_to(np.asarray(freq, dtype=np.float64), x.shape)
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(x.size):
        w0 = 2 * np.pi * min(freq[i], SR * 0.45) / SR
        alpha = np.sin(w0) / (2 * q)
        cw = np.cos(w0)
        a0 = 1 + alpha
        v = (alpha * x[i] - alpha * x2 + 2 * cw * y1 - (1 - alpha) * y2) / a0
        x2, x1 = x1, x[i]
        y2, y1 = y1, v
        y[i] = v
    return y


def softclip(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def pad(x, dur):
    return np.concatenate([x, np.zeros(n_of(dur))])


def mix(*parts):
    """Sums arrays of different lengths (each starts at 0). Tuples (x, at_sec) are offset."""
    items = []
    for p in parts:
        if isinstance(p, tuple):
            items.append((np.asarray(p[0]), int(p[1] * SR)))
        else:
            items.append((np.asarray(p), 0))
    n = max(x.size + o for x, o in items)
    out = np.zeros(n)
    for x, o in items:
        out[o:o + x.size] += x
    return out


def reverb(x, tail=0.25, mix_amt=0.25, tone=3000.0, predelay=0.006):
    """Convolution with a decaying, filtered noise burst. Adds `tail` seconds."""
    n_ir = n_of(tail)
    ir = rng.normal(0, 1, n_ir) * np.exp(-np.arange(n_ir) / SR / (tail / 5.0))
    ir = lp(ir, tone)
    ir = np.concatenate([np.zeros(n_of(predelay)), ir])
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    xs = pad(x, tail + predelay)
    m = xs.size + ir.size
    nfft = 1 << int(np.ceil(np.log2(m)))
    wet = np.fft.irfft(np.fft.rfft(xs, nfft) * np.fft.rfft(ir, nfft), nfft)[: xs.size]
    wet *= np.max(np.abs(x)) / (np.max(np.abs(wet)) + 1e-9)
    return xs * (1 - mix_amt * 0.5) + wet * mix_amt


def bell(f0, n, partials, decay=1.0, bright=1.0):
    """Inharmonic struck partials: list of (ratio, amp, decay_scale)."""
    out = np.zeros(n)
    for r, a, dsc in partials:
        f = f0 * r
        if f > SR * 0.42:
            continue
        out += sine(f, n, rng.uniform()) * a * (bright if r > 2 else 1.0) * edecay(n, decay * dsc, 0.002)
    return out


CHURCH = [(0.5, 0.9, 1.6), (1.0, 1.0, 1.0), (1.19, 0.6, 0.8), (1.5, 0.45, 0.7), (2.0, 0.7, 0.55),
          (2.51, 0.3, 0.35), (2.66, 0.25, 0.3), (3.01, 0.2, 0.25), (4.1, 0.1, 0.15)]
CHIME = [(1.0, 1.0, 1.0), (2.76, 0.35, 0.45), (5.4, 0.12, 0.2)]


def finish(name, x, vol=0.9, drive=1.2, max_dur=None, fade=0.01):
    x = np.asarray(x, dtype=np.float64)
    x = x - np.mean(x)  # no DC
    if max_dur is not None and x.size > n_of(max_dur):
        x = x[: n_of(max_dur)]
        fade = max(fade, max_dur * 0.25)  # trimmed reverb tail: fade it out
    f = min(x.size, n_of(fade))
    if f > 1:
        x[-f:] *= np.linspace(1, 0, f)
    x[: min(x.size, 16)] *= np.linspace(0, 1, min(x.size, 16))
    x = x / (np.max(np.abs(x)) or 1.0)
    x = softclip(x, drive)
    write(name, x, vol)


def write(name, data, vol=0.9):
    if ONLY is not None and name not in ONLY:
        return
    data = np.asarray(data, dtype=np.float64)
    peak = np.max(np.abs(data)) or 1.0
    data = data / peak * vol
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def arp(notes, step, duty=0.25, decay=1.5, warm=5000.0, sub=0.0):
    """Arpeggio of soft square blips; each note rings a little into the next."""
    out = np.zeros(n_of(step * len(notes) + step * 1.5))
    for i, f in enumerate(notes):
        nn = n_of(step * 2.2)
        tone = square(f, duty, nn) * 0.7 + triangle(f * 2, nn) * 0.2
        if sub:
            tone += triangle(f / 2, nn) * sub
        blip = lp(tone, warm) * env(nn, 0.002, decay * 2.2)
        o = n_of(step * i)
        out[o:o + nn] += blip[: out.size - o]
    return out


def thump(n, f0, f1, tau):
    """Pitch-dropping sine kick for body."""
    f = f0 * (f1 / f0) ** np.linspace(0, 1, n)
    return sine(f) * edecay(n, tau)


def click(n_ms=4, cut=4000):
    n = n_of(n_ms / 1000)
    return lp(noise(n), cut) * np.linspace(1, 0, n) ** 2


def choir(f, n, vowel=(700, 1150), detune=(0.996, 1.0, 1.004, 2.003), cut=2500):
    """Detuned saw stack through two formant band-passes: an 'aah' pad."""
    src = np.zeros(n)
    for d in detune:
        vib = 1 + 0.004 * np.sin(2 * np.pi * (5.2 + d) * np.arange(n) / SR)
        src += saw(f * d * vib) * (0.5 if d > 1.5 else 1.0)
    src = lp(src, cut)
    return bp(src, vowel[0], 5) * 1.0 + bp(src, vowel[1], 6) * 0.6 + src * 0.08


# ---------------------------------------------------------------- SFX ----
def sfx_combat():
    # Arcane bolt: pulse zap with a quick downward pitch envelope, a sine
    # sub for weight and a whisper of sparkle.
    d = 0.11
    n = n_of(d)
    body = lp(square(expsweep(1500, 420, d), 0.25), 4500) * env(n, 0.001, 2.2)
    sub = sine(expsweep(700, 220, d)) * edecay(n, 0.035) * 0.6
    air = bp(noise(n), 3200, 3) * edecay(n, 0.015) * 0.5
    finish("shoot_arcane", reverb(body + sub + air, 0.08, 0.18, 2500), 0.55, max_dur=0.19)

    # Fireball: breathy whoosh (noise through a falling band-pass) over a
    # dropping square growl.
    d = 0.2
    n = n_of(d)
    whoosh = bp(noise(n), expsweep(2400, 500, d), 1.5) * env(n, 0.004, 1.4) * 1.3
    growl = lp(square(expsweep(260, 80, d), 0.5), 1500) * env(n, 0.002, 1.6) * 0.45
    pop = thump(n_of(0.06), 180, 60, 0.02)
    finish("shoot_fire", reverb(mix(whoosh, growl, pop * 0.7), 0.05, 0.15, 2000), 0.6, 1.6, max_dur=0.24)

    # Frost shard: glassy two-tone with a crystalline ping.
    d = 0.14
    n = n_of(d)
    glass = triangle(expsweep(2100, 1250, d)) * env(n, 0.001, 2) * 0.8
    ping = sine(3150, n) * edecay(n, 0.04) * 0.35 + sine(4400, n) * edecay(n, 0.02) * 0.15
    crack = hp(noise(n_of(0.012)), 2500) * np.linspace(1, 0, n_of(0.012)) * 0.4
    finish("shoot_frost", reverb(mix(glass, ping, crack), 0.08, 0.25, 4000), 0.5, max_dur=0.2)

    # Lightning zap: buzzing noise gated by a low square, plus a crackling
    # pitch-jittered lead.
    d = 0.18
    n = n_of(d)
    buzz = lp2(noise(n), 2600) * square(expsweep(110, 45, d), 0.5) * 0.7
    lead = lp2(square(expsweep(1600, 700, d) + rng.uniform(-260, 260, n), 0.5), 3000) * 0.35
    snap = click(5, 5000) * 1.2
    finish("zap", mix(snap, (buzz + lead) * env(n, 0.001, 1.3)), 0.55, 1.6)

    # Star: sparkling rising chirp with a ringing chime on top.
    d = 0.2
    n = n_of(d)
    chirp = lp(square(expsweep(800, 2200, d), 0.25), 5000) * env(n, 0.002, 1.6) * 0.5
    chime = bell(1760, n, CHIME, 0.08) * 0.45
    finish("star", reverb(chirp + chime, 0.12, 0.25, 4000), 0.45, max_dur=0.26)

    # Hit: tight thud + mid-band crunch. Short and soft on the ear.
    d = 0.07
    n = n_of(d)
    thud = thump(n, 320, 110, 0.022)
    crunch = bp(noise(n, 2), 1200, 1.4) * edecay(n, 0.012) * 0.8
    tick = lp(square(expsweep(700, 300, d), 0.5), 2500) * edecay(n, 0.01) * 0.25
    finish("hit", thud + crunch + tick, 0.5, 1.8, max_dur=0.08)

    # Enemy death: bony crunch, falling growl and a little dust puff.
    d = 0.2
    n = n_of(d)
    crunch = bp(noise(n, 3), 900, 1.2) * edecay(n, 0.03) * 0.9
    fall = lp(square(expsweep(520, 70, d), 0.5), 2200) * env(n, 0.002, 1.5) * 0.5
    body = thump(n, 200, 50, 0.05) * 0.8
    dust = lp(noise(n), 1200) * swell(n, 0.25, 2) * 0.25
    finish("enemy_die", reverb(crunch + fall + body + dust, 0.04, 0.12, 1800), 0.65, 1.7, max_dur=0.23)

    # Explosion: kick + layered filtered noise with a darkening sweep and a
    # rumbling tail.
    d = 0.6
    n = n_of(d)
    kick = thump(n, 150, 32, 0.12) * 1.2
    blast = lp(noise(n), expsweep(5000, 300, d)) * edecay(n, 0.15) * 1.1
    rumble = lp(noise(n, 4), 400) * edecay(n, 0.3) * 0.9
    crackle = bp(noise(n) * (rng.uniform(0, 1, n) > 0.985), 2000, 1) * edecay(n, 0.12) * 1.5
    finish("explode", reverb(kick + blast + rumble + crackle, 0.3, 0.3, 1500), 0.85, 2.0, max_dur=0.75)

    # Nova: charge-up rise, a huge boom, and a descending shimmer ring.
    d = 1.4
    n = n_of(d)
    rise_d = 0.3
    rise = lp(square(expsweep(80, 900, rise_d), 0.5), 3000) * env(n_of(rise_d), 0.02, 0.4) * 0.35
    rise += bp(noise(n_of(rise_d)), expsweep(300, 3000, rise_d), 2) * np.linspace(0, 1, n_of(rise_d)) * 0.5
    bn = n_of(d - 0.25)
    boom = thump(bn, 120, 30, 0.25) * 1.2 + lp(noise(bn, 2), expsweep(3500, 200, (d - 0.25))) * edecay(bn, 0.35)
    shimmer = (triangle(expsweep(2000, 500, d - 0.25)) * 0.5 + sine(expsweep(3000, 750, d - 0.25)) * 0.3) * edecay(bn, 0.3) * 0.4
    finish("nova", reverb(mix(rise, (boom + shimmer, 0.25)), 0.4, 0.3, 2000), 0.95, 1.8, max_dur=1.75)

    # Hurt: punchy crunch and a downward wince.
    d = 0.32
    n = n_of(d)
    wince = lp(square(expsweep(440, 90, d), 0.5), 2500) * env(n, 0.002, 1.3) * 0.7
    crunch = bp(noise(n, 3), 800, 1.2) * edecay(n, 0.04)
    thud = thump(n, 220, 60, 0.06)
    finish("hurt", reverb(wince + crunch + thud, 0.08, 0.15, 2000), 0.7, 1.8, max_dur=0.38)

    # Player death: long falling wail, a final thud and a hollow reverb.
    d = 1.2
    n = n_of(d)
    vib = 1 + 0.03 * np.sin(2 * np.pi * 6 * np.arange(n) / SR)
    wail = lp(square(expsweep(820, 55, d) * vib, 0.5), 2400) * env(n, 0.01, 1.0) * 0.6
    wail += triangle(expsweep(410, 28, d) * vib) * env(n, 0.01, 1.0) * 0.4
    dust = lp(noise(n, 2), expsweep(3000, 300, d)) * env(n, 0.002, 1.2) * 0.35
    thud = thump(n_of(0.3), 120, 35, 0.08)
    finish("player_die", reverb(mix(wail + dust, (thud, 0.0)), 0.4, 0.35, 1800), 0.75, 1.5, max_dur=1.5)

    # Archer arrow: airy whistle and a twang.
    d = 0.14
    n = n_of(d)
    air = bp(noise(n), expsweep(3000, 1500, d), 3) * env(n, 0.01, 1.8) * 0.8
    twang = triangle(expsweep(1100, 650, d)) * edecay(n, 0.03) * 0.5
    finish("arrow", air + twang, 0.4, max_dur=0.16)

    # Enemy bolt: wobbling rising blob, distinct from the player spells.
    d = 0.22
    n = n_of(d)
    wob = 1 + 0.08 * np.sin(2 * np.pi * 28 * np.arange(n) / SR)
    blob = lp(square(expsweep(260, 680, d) * wob, 0.5), 2000) * 0.5 + triangle(expsweep(140, 340, d) * wob) * 0.6
    finish("enemy_shot", reverb(blob * env(n, 0.004, 1.5), 0.06, 0.15, 2000), 0.45, max_dur=0.26)

    # Slime: wet squelch, a rising resonant bubble.
    d = 0.25
    n = n_of(d)
    bub = triangle(expsweep(140, 620, d) * (1 + 0.15 * np.sin(2 * np.pi * 35 * np.arange(n) / SR))) * 0.8
    wet = bp(noise(n, 2), expsweep(300, 1200, d), 3) * 0.6
    finish("slime", (bub + wet) * env(n, 0.005, 1.5), 0.55)

    # Boss roar: tremolo noise growl over a detuned saw stack, with reverb.
    d = 1.4
    n = n_of(d)
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * 13 * np.arange(n) / SR)
    growl = lp(noise(n, 3) * trem, expsweep(1800, 500, d)) * 1.2
    f = expsweep(95, 42, d)
    saws = lp(saw(f) + saw(f * 1.012) + saw(f * 0.5) * 0.7, 900) * 0.45
    finish("boss_roar", reverb((growl + saws) * swell(n, 0.12, 1.0), 0.45, 0.3, 1500), 0.9, 2.2, max_dur=1.7)

    # Charge (enemy wind-up): rising saw grind with a building noise bed.
    d = 0.5
    n = n_of(d)
    grind = lp(saw(expsweep(55, 170, d)) + saw(expsweep(55.5, 172, d)), expsweep(500, 2500, d)) * 0.5
    bed = bp(noise(n), expsweep(400, 2000, d), 2) * np.linspace(0.2, 1, n) * 0.5
    finish("charge", (grind + bed) * env(n, 0.05, 0.6), 0.6, 1.6)

    # Orbiting orb: soft whoosh-ping.
    d = 0.18
    n = n_of(d)
    ping = triangle(expsweep(600, 1150, d)) * env(n, 0.003, 2) * 0.8
    air = bp(noise(n), expsweep(800, 2200, d), 4) * swell(n, 0.4) * 0.4
    finish("orbit", reverb(ping + air, 0.06, 0.2, 3000), 0.35, max_dur=0.22)


def sfx_pickups_ui():
    # Pickups: bright arpeggio blips with a sine sparkle, short and soft.
    p = arp([988, 1319, 1976], 0.042, 0.25, 1.8, 4500)
    p = mix(p, (sine(2637, n_of(0.08)) * edecay(n_of(0.08), 0.03) * 0.25, 0.084))
    finish("pickup", reverb(p, 0.06, 0.15, 3500), 0.45, max_dur=0.2)
    c = arp([1568, 2093], 0.05, 0.5, 1.5, 4000)
    c += bell(2093, c.size, CHIME, 0.05) * 0.3
    finish("coin", c, 0.4, max_dur=0.17)
    pw = arp([523, 659, 784, 1047, 1319, 1568, 2093], 0.045, 0.25, 1.0, 5000, sub=0.3)
    pw = mix(pw, (bell(2093, n_of(0.4), CHIME, 0.15) * 0.35, 0.27))
    finish("powerup", reverb(pw, 0.25, 0.25, 4000), 0.5, max_dur=0.6)
    h = arp([659, 784, 988, 1319], 0.07, 0.5, 1.0, 3500, sub=0.2)
    h += choir(659, h.size, (750, 1200)) * swell(h.size, 0.4) * 0.25
    finish("heal", reverb(h, 0.2, 0.3, 3500), 0.45, max_dur=0.5)
    mm = square(1760, 0.25, n_of(0.035)) * env(n_of(0.035), 0.001, 2)
    finish("menu_move", mix(lp(mm, 4000), click(3, 3000) * 0.4), 0.3)
    finish("menu_select", reverb(arp([880, 1319, 1760], 0.055, 0.5, 1.0, 4000, sub=0.3), 0.1, 0.2, 3500), 0.45, max_dur=0.3)

    # Wave fanfares: arpeggio with a bass pulse and a reverb tail.
    notes = [392, 523, 659, 784, 659, 784, 1047]
    ws = arp(notes, 0.08, 0.5, 0.8, 3500)
    bass = np.concatenate([lp(square(f / 4, 0.5, n_of(0.08)), 800) * env(n_of(0.08), 0.002, 1.5) for f in notes])
    ws = mix(ws, bass * 0.4, (thump(n_of(0.2), 150, 50, 0.06), 0.0))
    finish("wave_start", reverb(ws, 0.3, 0.25, 3000), 0.55, max_dur=0.85)
    notes = [523, 659, 784, 1047, 784, 1047, 1319, 1568]
    wc = arp(notes, 0.07, 0.25, 0.8, 4000, sub=0.25)
    wc = mix(wc, (bell(1568, n_of(0.6), CHIME, 0.25) * 0.4, 0.49))
    finish("wave_clear", reverb(wc, 0.3, 0.28, 3500), 0.55, max_dur=1.1)


def sfx_world():
    # Door: heavy stone grind and a low thunk.
    d = 0.5
    n = n_of(d)
    grind = lp(noise(n, 10), 900) * (0.7 + 0.3 * np.sin(2 * np.pi * 17 * np.arange(n) / SR)) * env(n, 0.04, 1.0)
    hum = lp(square(55, 0.5, n), 400) * env(n, 0.05, 1.0) * 0.3
    thunk = thump(n_of(0.25), 110, 40, 0.06)
    finish("door", reverb(mix(grind + hum, (thunk, d - 0.2)), 0.25, 0.3, 1200), 0.55, max_dur=0.7)

    # Teleport: twin opposing sweeps with phaser-ish shimmer.
    d = 0.3
    n = n_of(d)
    up = lp(square(expsweep(200, 2000, d), 0.5), 3500) * 0.4
    down = triangle(expsweep(2000, 200, d)) * 0.5
    sh = bp(noise(n), expsweep(600, 4000, d), 6) * 0.4
    finish("teleport", reverb((up + down + sh) * env(n, 0.005, 1.0), 0.15, 0.3, 3500), 0.4, max_dur=0.4)


# ---------------------------------------------------------- occult SFX ----
def sfx_occult():
    # card_deal: a card sliding off the deck. Band-passed noise swish with
    # a brief paper flutter.
    d = 0.15
    n = n_of(d)
    flutter = 1 + 0.35 * np.sin(2 * np.pi * 70 * np.arange(n) / SR)
    swish = bp(noise(n), expsweep(1800, 3600, d), 1.8) * swell(n, 0.35, 1.8) * flutter
    body = lp(noise(n), 900) * swell(n, 0.3, 2) * 0.4
    finish("card_deal", swish + body, 0.45, 1.2)

    # card_flip: crisp snap, then a faint mystic shimmer.
    d = 0.25
    n = n_of(d)
    snap = hp(noise(n_of(0.01)), 1500) * np.linspace(1, 0, n_of(0.01)) ** 1.5
    knock = thump(n_of(0.04), 900, 400, 0.008) * 0.5
    sh = np.zeros(n)
    for i, f in enumerate([1568, 2093, 2637]):
        sh += sine(f * (1 + 0.003 * i), n) * edecay(n, 0.09) * (0.3 - i * 0.06)
    sh *= swell(n, 0.15, 1.2)
    finish("card_flip", reverb(mix(snap, knock, (sh, 0.01)), 0.12, 0.25, 4500), 0.5, max_dur=0.3)

    # card_pick: low bell struck over a choir-ish pad.
    d = 0.8
    n = n_of(d)
    b = bell(220, n, CHURCH, 0.45, 0.7)
    pad_ = (choir(220, n) + choir(277.2, n) * 0.7 + choir(329.6, n) * 0.6) * swell(n, 0.3, 1.4) * 0.5
    hit_ = thump(n_of(0.1), 300, 120, 0.02) * 0.4
    finish("card_pick", reverb(b + pad_ + mix(hit_, np.zeros(n)), 0.45, 0.35, 3000), 0.6, 1.3, max_dur=1.0)

    # planchette: wood gliding on a board. Low band-passed grain with a
    # woody resonance.
    d = 0.12
    n = n_of(d)
    grain = bp(noise(n, 2), 650, 2.5) * (0.75 + 0.25 * rng.uniform(-1, 1, n))
    res = bp(noise(n), 260, 8) * 0.8
    finish("planchette", (grain + res) * swell(n, 0.3, 1.3), 0.4, 1.4)

    # rune_cast: a handful of stones/bones clacking on a table, then a low
    # resonant hum.
    d = 0.9
    n = n_of(d)
    out = np.zeros(n)
    times = np.sort(rng.uniform(0.0, 0.22, 7))
    times[0] = 0.0
    for i, at in enumerate(times):
        cn = n_of(0.05)
        f = rng.uniform(1100, 2400)
        clack = (sine(f, cn) * 0.6 + sine(f * 1.53, cn) * 0.3) * edecay(cn, 0.008)
        clack += bp(noise(cn), f, 3) * edecay(cn, 0.004) * 0.8
        clack += thump(cn, 260, 140, 0.01) * 0.4
        o = n_of(at)
        out[o:o + cn] += clack * (1.0 - i * 0.07)
    hn = n_of(0.75)
    hum = (sine(73.4, hn) + sine(110, hn) * 0.5 + sine(146.8 * 1.003, hn) * 0.25) * (1 + 0.25 * np.sin(2 * np.pi * 4 * np.arange(hn) / SR))
    hum += lp(saw(73.4, hn), 600) * 0.2
    hum *= swell(hn, 0.35, 1.3) * 0.6
    out = mix(out, (hum, 0.15))
    finish("rune_cast", reverb(out, 0.35, 0.3, 2500), 0.65, 1.3, max_dur=1.0)

    # rune_good: bright rising chime (major arpeggio of bells).
    d = 0.7
    n = n_of(d)
    out = np.zeros(n)
    for i, f in enumerate([784, 988, 1175, 1568]):
        o = n_of(0.07 * i)
        out[o:] += bell(f, n - o, CHIME, 0.25) * (0.8 + 0.1 * i)
    out += sine(expsweep(400, 1600, d), None) * swell(n, 0.3, 2) * 0.15
    finish("rune_good", reverb(out, 0.3, 0.3, 4500), 0.55, max_dur=0.85)

    # rune_bad: dark falling detuned drone.
    d = 0.8
    n = n_of(d)
    f = expsweep(155, 92, d)
    drone = saw(f) + saw(f * 1.017) + saw(f * 0.5 * 0.991) * 0.8 + square(f * 1.5 * 0.985, 0.5, None) * 0.3
    drone = lp(drone, expsweep(1600, 350, d)) * swell(n, 0.12, 1.2)
    sting = thump(n_of(0.3), 90, 40, 0.1)
    finish("rune_bad", reverb(mix(drone * 0.6, sting), 0.35, 0.3, 1500), 0.65, 1.8, max_dur=0.95)

    # gong: deep ritual gong, mallet thump, slow-blooming shimmer.
    d = 1.6
    n = n_of(d)
    f0 = 82.0
    drop = expsweep(1.0, 0.985, d)
    g = np.zeros(n)
    for r, a, tau in [(1.0, 1.0, 0.9), (1.52, 0.6, 0.7), (2.0, 0.35, 0.6), (2.41, 0.4, 0.55), (2.93, 0.25, 0.45),
                      (3.6, 0.2, 0.4), (4.25, 0.15, 0.35), (5.3, 0.1, 0.3)]:
        beat = 1 + 0.15 * np.sin(2 * np.pi * rng.uniform(0.7, 2.5) * np.arange(n) / SR)
        g += sine(f0 * r * drop, None, rng.uniform()) * a * edecay(n, tau, 0.004) * beat
    bloom = bp(noise(n), 900, 2) * swell(n, 0.25, 1.5) * 0.25
    mallet = mix(thump(n_of(0.15), 140, 60, 0.04) * 0.9, lp(noise(n_of(0.02)), 1500) * np.linspace(1, 0, n_of(0.02)) * 0.5)
    finish("gong", reverb(mix(g + bloom, mallet), 0.6, 0.3, 2000), 0.85, 1.4, max_dur=1.7)

    # whisper: breathy filtered noise moving through vowel formants in
    # syllable-like puffs. Quiet.
    d = 1.0
    n = n_of(d)
    br = hp(noise(n), 500)
    f1 = 500 + 250 * np.sin(2 * np.pi * 2.3 * np.arange(n) / SR)
    f2 = 1500 + 600 * np.sin(2 * np.pi * 1.7 * np.arange(n) / SR + 1.0)
    voc = bp(br, f1, 6) * 0.8 + bp(br, f2, 7) * 0.7 + bp(br, 3800, 4) * 0.12
    syl = np.zeros(n)
    for at, ln in [(0.0, 0.22), (0.24, 0.16), (0.42, 0.3), (0.74, 0.24)]:
        s = n_of(ln)
        o = n_of(at)
        syl[o:o + s] += swell(s, 0.3, 1.5)[: n - o]
    finish("whisper", reverb(voc * syl, 0.2, 0.35, 3000), 0.35, 1.0, max_dur=1.1)

    # candle: a candle flaring. Soft fwoomp of low noise and a flicker.
    d = 0.3
    n = n_of(d)
    flick = 1 + 0.4 * lp(rng.uniform(-1, 1, n), 30) * 4
    fw = lp(noise(n), expsweep(600, 2200, d)) * swell(n, 0.15, 1.6) * flick
    pop = thump(n_of(0.05), 160, 90, 0.015) * 0.5
    hiss = bp(noise(n), 2500, 2) * edecay(n, 0.05) * 0.15
    finish("candle", mix(fw, pop, hiss), 0.45, 1.3)

    # page_turn: old book page. Papery crinkle swish, with a soft flap.
    d = 0.3
    n = n_of(d)
    crk = noise(n) * (rng.uniform(0, 1, n) > 0.6)
    swish = bp(noise(n), expsweep(1200, 2800, d) * (1 - 0.3 * np.linspace(0, 1, n) ** 2), 1.5) * swell(n, 0.55, 1.5)
    crinkle = bp(crk, 2200, 1.5) * swell(n, 0.5, 1.2) * 0.35
    flap = lp(noise(n_of(0.05)), 700) * swell(n_of(0.05), 0.3) * 0.8
    finish("page_turn", mix(swish + crinkle, (flap, 0.22)), 0.45, 1.2)

    # bell_toll: distant church bell. Strike + long hum partial, darkened
    # and drowned in reverb.
    d = 2.0
    n = n_of(d)
    b = bell(196, n, CHURCH, 0.9, 0.6)
    b = lp(b, 2200)
    strike = lp(noise(n_of(0.01)), 1500) * 0.3
    finish("bell_toll", reverb(mix(b, strike), 0.7, 0.55, 1800, 0.03), 0.6, 1.2, max_dur=2.2, fade=0.1)

    # portal: swirling summoning vortex. Swept resonant noise, phasing
    # detuned saws and a sub swell.
    d = 1.0
    n = n_of(d)
    tt = np.arange(n) / SR
    swirl = 900 + 700 * np.sin(2 * np.pi * (3 + 6 * tt) * tt)
    vort = bp(noise(n), swirl, 5) * 0.9
    f = expsweep(70, 140, d)
    saws = lp(saw(f) + saw(f * 1.01) + saw(f * 1.5 * 0.995) * 0.5, expsweep(300, 1800, d)) * 0.35
    sub = sine(expsweep(45, 60, d)) * 0.5
    sparkle = sine(1760 * (1 + 0.02 * np.sin(2 * np.pi * 9 * tt)), n) * 0.06
    whole = (vort + saws + sub + sparkle) * swell(n, 0.65, 1.3)
    finish("portal", reverb(whole, 0.4, 0.3, 2500), 0.7, 1.5, max_dur=1.15)

    # ghost: wraith's wail. Vibrato sine/triangle voice gliding up then
    # down, a breathy layer and a choir formant.
    d = 0.7
    n = n_of(d)
    tt = np.linspace(0, 1, n)
    contour = 330 * 2 ** ((np.sin(np.pi * tt) * 7 - tt * 5) / 12)
    vib = 1 + 0.02 * np.sin(2 * np.pi * 6.5 * tt * d)
    voice = sine(contour * vib) * 0.7 + triangle(contour * vib * 1.005) * 0.3
    voice += bp(saw(contour * vib), 900, 4) * 0.4
    breath = bp(noise(n), contour * 3, 3) * 0.3
    finish("ghost", reverb((voice + breath) * swell(n, 0.25, 1.4), 0.35, 0.4, 2500), 0.5, 1.2, max_dur=0.9)


def sfx_new():
    """The voices the arena events lacked, and the enemy_die / hit variants. Own rng seed, so these files are the same
    whether the whole set is written or only these (`--only`); the older sounds never depend on this function."""
    global rng
    rng = np.random.default_rng(1207)

    # Down: a wizard falls. Low, final: a sinking sine and square, a dull thud, a hollow short tail.
    d = 0.6
    n = n_of(d)
    sink = sine(expsweep(220, 45, d)) * env(n, 0.004, 1.2) * 0.8
    sink += lp(square(expsweep(330, 60, d), 0.5), 900) * env(n, 0.004, 1.6) * 0.35
    dust = lp(noise(n, 2), expsweep(1800, 150, d)) * edecay(n, 0.12) * 0.3
    finish("down", reverb(mix(sink + dust, (thump(n_of(0.25), 140, 38, 0.07) * 0.9, 0.0)), 0.2, 0.3, 1500), 0.72, 1.6, max_dur=0.75)

    # Revive: a warm rising arpeggio under a soft choir swell.
    notes = [262, 330, 392, 523, 659]
    rv = arp(notes, 0.09, 0.5, 0.9, 2600, sub=0.35)
    rv += choir(392, rv.size, (700, 1150)) * swell(rv.size, 0.55, 1.2) * 0.35
    rv = mix(rv, (bell(1047, n_of(0.5), CHIME, 0.2) * 0.25, 0.3))
    finish("revive", reverb(rv, 0.3, 0.3, 2800), 0.55, max_dur=1.0)

    # Boss phase: a hit of dread. Deep boom, a detuned low drone with a falling groan, a cracking noise burst.
    d = 1.0
    n = n_of(d)
    boom = thump(n, 90, 28, 0.2) * 1.2
    groan = lp(saw(expsweep(110, 48, d)) + saw(expsweep(116, 50, d)), 700) * swell(n, 0.06, 1.1) * 0.45
    crack = bp(noise(n, 2), expsweep(2500, 300, d), 1.5) * edecay(n, 0.1) * 0.7
    finish("boss_phase", reverb(boom + groan + crack, 0.4, 0.3, 1400), 0.85, 2.0, max_dur=1.2)

    # Fate: a card's weight. A low bell stroke and a papery slap, then a thin whispering shimmer.
    d = 0.8
    n = n_of(d)
    stroke = bell(147, n, CHURCH, 0.35) * 0.5
    slap = bp(noise(n_of(0.1), 2), 1500, 1.2) * edecay(n_of(0.1), 0.02) * 0.7
    fa = mix(stroke, (slap, 0.0), (bell(1175, n_of(0.5), CHIME, 0.2) * 0.2, 0.08))
    finish("fate", reverb(fa, 0.3, 0.3, 2500), 0.6, max_dur=0.9)

    # Redraw: a quick shuffle, five short paper flicks that rise a little.
    sh = np.zeros(n_of(0.3))
    for i in range(5):
        m = n_of(0.045)
        flick = bp(noise(m, 2), 2200 + 250 * i, 1.0) * edecay(m, 0.012) * (0.6 + 0.08 * i)
        o = n_of(0.04 * i)
        sh[o:o + m] += flick
    finish("redraw", sh, 0.45, 1.4, max_dur=0.3)

    # Banish: a card torn or burnt. A rip (noise sliding up) with a crackle and a fading ember hiss.
    d = 0.5
    n = n_of(d)
    rip = bp(noise(n), expsweep(900, 3500, d), 1.2) * env(n, 0.005, 0.8) * 0.8
    crackle = np.zeros(n)
    for _ in range(14):
        m = n_of(0.012)
        o = int(rng.uniform(0, n - m))
        crackle[o:o + m] += click(12, 5000)[:m] * rng.uniform(0.3, 0.9)
    ember = lp(noise(n), 1800) * swell(n, 0.2, 2.0) * 0.25
    finish("banish", reverb(rip + crackle * 0.7 + ember, 0.12, 0.2, 3000), 0.55, 1.6, max_dur=0.55)

    # Low health: two heartbeats, lub-dub, low and soft.
    beat = thump(n_of(0.18), 95, 42, 0.05) * 1.0 + lp(noise(n_of(0.18), 2), 400) * edecay(n_of(0.18), 0.03) * 0.25
    hb = mix(beat, (beat * 0.75, 0.2), (beat * 0.95, 0.62), (beat * 0.7, 0.82))
    finish("low_health", reverb(hb, 0.15, 0.15, 900), 0.7, 1.4, max_dur=1.1)

    # Level up: a quick bright climb on pulse blips with a bell on top.
    lu = arp([392, 523, 659, 784, 1047, 1319], 0.05, 0.25, 1.0, 5000, sub=0.3)
    lu = mix(lu, (bell(1568, n_of(0.5), CHIME, 0.2) * 0.4, 0.22))
    finish("level_up", reverb(lu, 0.25, 0.25, 4000), 0.5, max_dur=0.8)

    # Victory: a fanfare that resolves on a held major chord with a choir.
    notes = [392, 523, 659, 784, 1047, 784, 1047, 1319]
    vf = arp(notes, 0.11, 0.5, 0.7, 3800, sub=0.3)
    cn = n_of(1.0)
    chord = sum(choir(f, cn, (700, 1150)) for f in (262, 330, 392)) * swell(cn, 0.3, 1.3) * 0.22
    vf = mix(vf, (chord, 0.7), (bell(1047, n_of(1.0), CHIME, 0.4) * 0.35, 0.9), (thump(n_of(0.25), 150, 45, 0.07), 0.0))
    finish("victory", reverb(vf, 0.4, 0.3, 3200), 0.7, 1.8, max_dur=1.95)

    # Boss fall: the boss's death throes. A long falling growl, rumbling boom and a collapsing noise wash.
    d = 1.4
    n = n_of(d)
    gr = lp(saw(expsweep(180, 38, d)) + square(expsweep(95, 30, d), 0.5), 1000) * env(n, 0.02, 0.9) * 0.55
    bm = thump(n_of(0.6), 110, 26, 0.18) * 1.2
    wash = lp(noise(n, 2), expsweep(3500, 150, d)) * edecay(n, 0.4) * 0.5
    finish("boss_fall", reverb(mix(gr + wash, (bm, 0.0), (bm * 0.7, 0.55)), 0.4, 0.3, 1500), 0.85, 1.8, max_dur=1.8)

    # Shrine result: a chime and a low sigh, a mystical resolve that neither cheers nor mourns.
    sr = bell(659, n_of(0.9), CHIME, 0.3) * 0.5 + bell(988, n_of(0.9), CHIME, 0.25) * 0.3
    sr = mix(sr, (choir(330, n_of(0.8), (600, 1000)) * swell(n_of(0.8), 0.4, 1.4) * 0.3, 0.05))
    finish("shrine_result", reverb(sr, 0.35, 0.3, 3000), 0.5, 2.5, max_dur=1.1)

    # enemy_die variants: the same bony crunch, a different pitch and texture each, so a swarm does not machine-gun.
    for k, (f0, f1, hold, cutf, tone) in enumerate([(430, 60, 2, 1100, 0.3), (620, 85, 4, 800, 0.5), (360, 55, 3, 1500, 0.2)], 2):
        d = 0.2
        n = n_of(d)
        crunch = bp(noise(n, hold), 900 * f0 / 520, 1.2) * edecay(n, 0.028 + 0.004 * k) * 0.9
        fall = lp(square(expsweep(f0, f1, d), 0.5 if k != 3 else 0.25), 2200) * env(n, 0.002, 1.5) * 0.5
        body = thump(n, 160 + 25 * k, 48, 0.05) * 0.8
        dust = lp(noise(n), cutf) * swell(n, 0.25, 2) * tone * 0.8
        finish("enemy_die_%d" % k, reverb(crunch + fall + body + dust, 0.04, 0.12, 1800), 0.65, 1.7, max_dur=0.23)

    # hit variants: tight thud and crunch, each with its own centre frequency.
    for k, (t0, t1, cf, tf) in enumerate([(280, 100, 1000, 650), (360, 125, 1400, 800), (300, 90, 1700, 550)], 2):
        d = 0.07
        n = n_of(d)
        thud = thump(n, t0, t1, 0.022)
        crunch = bp(noise(n, 2), cf, 1.4) * edecay(n, 0.012) * 0.8
        tick = lp(square(expsweep(tf, tf * 0.43, d), 0.5), 2500) * edecay(n, 0.01) * 0.25
        finish("hit_%d" % k, thud + crunch + tick, 0.5, 1.8, max_dur=0.08)


NEW_SOUNDS = ["down", "revive", "boss_phase", "fate", "redraw", "banish", "low_health", "level_up", "victory",
              "boss_fall", "shrine_result", "enemy_die_2", "enemy_die_3", "enemy_die_4", "hit_2", "hit_3", "hit_4"]
ONLY = None  # set by --only: write() writes just these names


def sfx():
    if ONLY is not None and all(n in NEW_SOUNDS for n in ONLY):
        sfx_new() # the older sounds take minutes to render and are not wanted
        return
    sfx_combat()
    sfx_pickups_ui()
    sfx_world()
    sfx_occult()
    sfx_new()


if __name__ == "__main__":
    import sys
    # `gen_audio.py --only=down,revive` writes only the named sounds (the others stay byte for byte as they are).
    for arg in sys.argv[1:]:
        if arg.startswith("--only="):
            ONLY = [x for x in arg[7:].split(",") if x]
    os.makedirs(OUT, exist_ok=True)
    sfx()
    print("sound effects written to", os.path.abspath(OUT))

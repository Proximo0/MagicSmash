#!/usr/bin/env python3
"""Generates all Magic Smash sound effects as .wav files.

The music is made separately by tools/music (see tools/music/SOUNDTRACK.md).

Run from the project root:  python3 tools/gen_audio.py
Everything is synthesised (square/triangle/noise voices, like an 8/16-bit
console), so there are no licensing questions and it is easy to tweak.
"""
import os
import wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)


def write(name, data, vol=0.9):
    data = np.asarray(data, dtype=np.float64)
    peak = np.max(np.abs(data)) or 1.0
    data = data / peak * vol
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def t_of(dur):
    return np.arange(int(SR * dur)) / SR


def phase_of(freq):
    """freq may be an array (sweeps)."""
    freq = np.asarray(freq, dtype=np.float64)
    return np.cumsum(freq) / SR


def square(freq, duty=0.5):
    ph = phase_of(freq) % 1.0
    return np.where(ph < duty, 1.0, -1.0)


def triangle(freq):
    ph = phase_of(freq) % 1.0
    return 4 * np.abs(ph - 0.5) - 1


def saw(freq):
    ph = phase_of(freq) % 1.0
    return 2 * ph - 1


def noise(n, hold=1):
    v = rng.uniform(-1, 1, n // hold + 1)
    return np.repeat(v, hold)[:n]


def env(n, attack=0.002, decay_pow=1.0):
    t = np.linspace(0, 1, n)
    a = max(1, int(attack * SR))
    e = (1 - t) ** decay_pow
    e[:a] *= np.linspace(0, 1, a)
    return e


def lowpass(x, k=0.3):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += k * (v - acc)
        y[i] = acc
    return y


def sweep(f0, f1, dur, curve=1.0):
    t = np.linspace(0, 1, int(SR * dur)) ** curve
    return f0 + (f1 - f0) * t


# ---------------------------------------------------------------- SFX ----
def sfx():
    d = 0.12
    write("shoot_arcane", square(sweep(1400, 500, d), 0.25) * env(int(SR * d), decay_pow=2) * 0.6, 0.55)
    d = 0.28
    n = int(SR * d)
    write("shoot_fire", (noise(n, 3) * 0.7 + square(sweep(300, 90, d), 0.5) * 0.5) * env(n, decay_pow=1.5), 0.6)
    d = 0.16
    n = int(SR * d)
    write("shoot_frost", (triangle(sweep(2200, 1200, d)) + square(sweep(3300, 1800, d), 0.125) * 0.3) * env(n, decay_pow=2), 0.5)
    d = 0.18
    n = int(SR * d)
    write("zap", (noise(n, 1) * square(sweep(90, 40, d), 0.5) * 0.8 + square(sweep(1800, 900, d) + rng.uniform(-300, 300, n), 0.5) * 0.4) * env(n, decay_pow=1.2), 0.55)
    d = 0.2
    n = int(SR * d)
    write("star", (square(sweep(800, 2400, d, 0.5), 0.25) * 0.6 + triangle(sweep(1600, 4800, d, 0.5)) * 0.4) * env(n, decay_pow=1.5), 0.45)
    d = 0.06
    n = int(SR * d)
    write("hit", (noise(n, 2) * 0.6 + square(sweep(500, 200, d), 0.5) * 0.4) * env(n, decay_pow=2), 0.5)
    d = 0.3
    n = int(SR * d)
    write("enemy_die", (noise(n, 4) * 0.6 + square(sweep(600, 60, d, 0.6), 0.5) * 0.6) * env(n, decay_pow=1.4), 0.7)
    d = 0.6
    n = int(SR * d)
    write("explode", lowpass(noise(n, 2), 0.35) * env(n, 0.001, 1.8) + square(sweep(120, 30, d), 0.5) * env(n, decay_pow=3) * 0.6, 0.85)
    d = 1.6
    n = int(SR * d)
    boom = lowpass(noise(n, 3), 0.25) * env(n, 0.001, 1.4)
    rise = square(sweep(80, 900, 0.35), 0.5) * env(int(SR * 0.35), decay_pow=0.5) * 0.5
    boom[: rise.size] += rise
    shimmer = triangle(sweep(2000, 400, d)) * env(n, decay_pow=2.5) * 0.3
    write("nova", boom + shimmer, 0.95)
    # Pickups: bright arpeggio blips
    def arp(notes, step, duty=0.25, decay=1.5):
        out = []
        for f in notes:
            nn = int(SR * step)
            out.append(square(np.full(nn, f), duty) * env(nn, decay_pow=decay))
        return np.concatenate(out)
    write("pickup", arp([988, 1319, 1976], 0.05), 0.45)
    write("coin", arp([1568, 2093], 0.055, 0.5), 0.4)
    write("powerup", arp([523, 659, 784, 1047, 1319, 1568, 2093], 0.045, 0.25, 1.0), 0.5)
    write("heal", arp([659, 784, 988, 1319], 0.07, 0.5, 1.0), 0.45)
    d = 0.35
    n = int(SR * d)
    write("hurt", (square(sweep(400, 80, d), 0.5) * 0.7 + noise(n, 6) * 0.4) * env(n, decay_pow=1.2), 0.7)
    d = 1.2
    n = int(SR * d)
    write("player_die", (square(sweep(800, 50, d, 0.7), 0.5) * 0.6 + noise(n, 8) * 0.4) * env(n, decay_pow=1.0), 0.75)
    d = 0.5
    n = int(SR * d)
    write("door", (lowpass(noise(n, 12), 0.2) * 0.8 + square(np.full(n, 55.0), 0.5) * 0.3) * env(n, 0.05, 1.0), 0.55)
    d = 0.14
    n = int(SR * d)
    write("arrow", noise(n, 1) * env(n, 0.01, 2.0) * 0.5 + triangle(sweep(1200, 700, d)) * env(n, decay_pow=3) * 0.4, 0.4)
    d = 0.22
    n = int(SR * d)
    write("enemy_shot", (square(sweep(300, 700, d), 0.5) * 0.5 + triangle(sweep(150, 350, d)) * 0.5) * env(n, decay_pow=1.5), 0.45)
    d = 0.25
    n = int(SR * d)
    write("slime", (triangle(sweep(150, 600, d, 0.5)) * 0.8 + noise(n, 20) * 0.2) * env(n, decay_pow=1.5), 0.55)
    write("menu_move", square(np.full(int(SR * 0.04), 1760.0), 0.25) * env(int(SR * 0.04)), 0.3)
    write("menu_select", arp([880, 1319, 1760], 0.06, 0.5, 1.0), 0.45)
    write("wave_start", arp([392, 523, 659, 784, 659, 784, 1047], 0.08, 0.5, 0.8), 0.55)
    write("wave_clear", arp([523, 659, 784, 1047, 784, 1047, 1319, 1568], 0.07, 0.25, 0.8), 0.55)
    d = 1.4
    n = int(SR * d)
    roar = lowpass(noise(n, 5) * (0.6 + 0.4 * np.sin(np.arange(n) / SR * 2 * np.pi * 13)), 0.3)
    roar += saw(sweep(90, 45, d)) * 0.6
    write("boss_roar", roar * env(n, 0.15, 1.0), 0.9)
    d = 0.3
    n = int(SR * d)
    write("teleport", (square(sweep(200, 2000, d, 2), 0.5) * 0.5 + triangle(sweep(2000, 200, d)) * 0.5) * env(n, decay_pow=1), 0.4)
    d = 0.5
    n = int(SR * d)
    write("charge", (saw(sweep(60, 160, d)) * 0.7 + noise(n, 10) * 0.3) * env(n, 0.05, 0.6), 0.6)
    d = 0.18
    n = int(SR * d)
    write("orbit", triangle(sweep(600, 1200, d)) * env(n, decay_pow=2), 0.35)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sfx()
    print("sound effects written to", os.path.abspath(OUT))

"""Magic Smash music engine: a small offline synthesiser + sequencer.

Songs are Python files that build a `Song`, add tracks, write notes with a
compact tracker-style notation and call `song.render(...)`. Rendering gives
44.1 kHz stereo audio with band-limited oscillators, filters, envelopes,
reverb, tempo-synced delay, sidechain ducking, bus compression, a limiter
and a seamless loop seam (reverb/delay tails wrap back to the loop start).

Nobody can "listen" inside the build pipeline, so `render()` also writes an
analysis report (levels, frequency balance, per-track loudness, note clashes,
non-chord tones on strong beats, loop seam check) and a piano-roll PNG.

Quick reference
---------------
    from engine import *
    song = Song("music_battle", bpm=156, bars=32)
    song.chords(0, "Em C D B7", per=1)           # harmony map (for analysis + helpers)
    lead = song.track("lead", lead_pulse(), vol=-8, pan=0.15, reverb=0.18, delay=0.12)
    lead.seq(0, "E5:2 B4 E5 G5:3 F#5 E5:2 | D5:4 -:4", unit=0.5)
    bass = song.track("bass", bass_fm(), vol=-6, duck=0.3)
    bass.seq(0, "E2 E2 E3 E2 ...", unit=0.5)
    pad = song.track("pad", strings(), vol=-14, reverb=0.4)
    pad.chord(0, chord_tones("Em", 4), beats=4)
    drums = song.drums("drums", vol=-6)
    drums.pat(0, {"kick": "x...x...x...x...", "snare": "....x.......x..."}, bars=1)
    song.loop(0)          # loop the whole song (default); loop(4) = 4-bar intro then loop
    song.render()         # -> ../../assets/audio/<name>.wav + reports in out/

Notation for Track.seq
----------------------
Tokens are separated by spaces; "|" is an optional bar-line marker (ignored).
    E5          note, 1 unit long        E5:3     note, 3 units long
    -  / -:2    rest                     ~ / ~:2  extend (tie) previous note
    [C4 E4 G4]:4  chord                  E5^      accent (vel 1.0)
    E5_         soft (vel 0.55)          E5.      staccato (half length)
    E5>         slide into the next note (glide even if the instrument has none)
Durations are in units; `unit` is in beats (0.5 = eighth notes in 4/4).
"""
from __future__ import annotations

import json
import math
import os
import re
import wave
from dataclasses import dataclass, field, replace

import numpy as np
from scipy import signal
from scipy.ndimage import maximum_filter1d

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO_OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "audio"))
REPORT_OUT = os.path.join(HERE, "out")

# ----------------------------------------------------------------- pitch ---
_NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name) -> int:
    """'C4' -> 60, 'F#3', 'Bb5', 'Cb4'. Ints pass through."""
    if isinstance(name, (int, np.integer)):
        return int(name)
    m = re.fullmatch(r"([A-Ga-g])([#b]*)(-?\d+)", name.strip())
    if not m:
        raise ValueError(f"bad note name {name!r}")
    p = _NOTE[m.group(1).upper()] + m.group(2).count("#") - m.group(2).count("b")
    return 12 * (int(m.group(3)) + 1) + p


def hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


NOTE_NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


def name_of(m: int) -> str:
    return f"{NOTE_NAMES[m % 12]}{m // 12 - 1}"


_QUAL = {
    "": [0, 4, 7], "maj": [0, 4, 7], "m": [0, 3, 7], "min": [0, 3, 7],
    "5": [0, 7], "dim": [0, 3, 6], "aug": [0, 4, 8], "+": [0, 4, 8],
    "sus2": [0, 2, 7], "sus4": [0, 5, 7], "sus": [0, 5, 7],
    "7": [0, 4, 7, 10], "maj7": [0, 4, 7, 11], "M7": [0, 4, 7, 11],
    "m7": [0, 3, 7, 10], "mMaj7": [0, 3, 7, 11], "dim7": [0, 3, 6, 9],
    "m7b5": [0, 3, 6, 10], "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9],
    "9": [0, 4, 7, 10, 14], "m9": [0, 3, 7, 10, 14], "maj9": [0, 4, 7, 11, 14],
    "add9": [0, 4, 7, 14], "madd9": [0, 3, 7, 14], "7sus4": [0, 5, 7, 10],
    "7b9": [0, 4, 7, 10, 13], "aug7": [0, 4, 8, 10],
}


def parse_chord(sym: str):
    """'F#m7/C#' -> (root_pc, intervals, bass_pc or None)."""
    sym = sym.strip()
    bass = None
    if "/" in sym:
        sym, b = sym.split("/")
        bass = (_NOTE[b[0].upper()] + b[1:].count("#") - b[1:].count("b")) % 12
    m = re.fullmatch(r"([A-G])([#b]?)(.*)", sym)
    if not m:
        raise ValueError(f"bad chord {sym!r}")
    root = (_NOTE[m.group(1)] + (1 if m.group(2) == "#" else -1 if m.group(2) == "b" else 0)) % 12
    q = m.group(3)
    if q not in _QUAL:
        raise ValueError(f"unknown chord quality {q!r} in {sym!r}; known: {sorted(_QUAL)}")
    return root, _QUAL[q], bass


def chord_tones(sym: str, octave: int = 4, inversion: int = 0) -> list[int]:
    """Close-position chord as midi numbers with the root in `octave`."""
    root, iv, bass = parse_chord(sym)
    base = 12 * (octave + 1) + root
    notes = [base + i for i in iv]
    for _ in range(inversion):
        notes = notes[1:] + [notes[0] + 12]
    if bass is not None:
        b = 12 * (octave + 1) + bass
        while b >= notes[0]:
            b -= 12
        notes = [b] + notes
    return notes


def chord_pcs(sym: str) -> set[int]:
    root, iv, bass = parse_chord(sym)
    s = {(root + i) % 12 for i in iv}
    if bass is not None:
        s.add(bass)
    return s


def scale(root: str, mode: str = "minor", octave: int = 4) -> list[int]:
    modes = {
        "major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10],
        "harmonic": [0, 2, 3, 5, 7, 8, 11], "dorian": [0, 2, 3, 5, 7, 9, 10],
        "phrygian": [0, 1, 3, 5, 7, 8, 10], "lydian": [0, 2, 4, 6, 7, 9, 11],
        "mixolydian": [0, 2, 4, 5, 7, 9, 10], "phrygian_dominant": [0, 1, 4, 5, 7, 8, 10],
    }
    r = midi(f"{root}{octave}")
    return [r + i for i in modes[mode]]


def db(x: float) -> float:
    return 10 ** (x / 20.0)


# ----------------------------------------------------------- oscillators ---
def _polyblep(t, dt):
    y = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    y[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    x = (t[m] - 1.0) / dt[m]
    y[m] = x * x + x + x + 1.0
    return y


def osc_saw(phase, dt):
    t = phase % 1.0
    return 2.0 * t - 1.0 - _polyblep(t, dt)


def osc_pulse(phase, dt, duty):
    t = phase % 1.0
    duty = np.broadcast_to(duty, t.shape)
    y = np.where(t < duty, 1.0, -1.0)
    y += _polyblep(t, dt)
    y -= _polyblep((t - duty) % 1.0, dt)
    # remove DC from asymmetric duty so narrow pulses don't thump
    return y - (2.0 * duty - 1.0)


def osc_tri(phase, dt):
    t = phase % 1.0
    return 4.0 * np.abs(t - 0.5) - 1.0


def osc_nestri(phase, dt):
    """4-bit stepped triangle like the NES/2A03 bass channel."""
    t = phase % 1.0
    tri = 4.0 * np.abs(t - 0.5) - 1.0
    return np.round(tri * 7.5) / 7.5


def osc_sine(phase, dt):
    return np.sin(2 * np.pi * phase)


_rng = np.random.default_rng(1234)


def lfsr_noise(n, period=1, short=False):
    """NES-style LFSR noise; `period` holds each value for N samples."""
    reg = 1
    tap = 6 if short else 1
    vals = np.empty(n // period + 2)
    for i in range(vals.size):
        bit = (reg ^ (reg >> tap)) & 1
        reg = (reg >> 1) | (bit << 14)
        vals[i] = 1.0 if reg & 1 else -1.0
    return np.repeat(vals, period)[:n]


# ------------------------------------------------------------- filters ---
def biquad_coeffs(kind, f, q, gain_db=0.0):
    f = min(max(f, 10.0), SR * 0.45)
    w = 2 * np.pi * f / SR
    cw, sw = np.cos(w), np.sin(w)
    a = sw / (2 * q)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        aa = [1 + a, -2 * cw, 1 - a]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        aa = [1 + a, -2 * cw, 1 - a]
    elif kind == "bp":
        b = [a, 0, -a]
        aa = [1 + a, -2 * cw, 1 - a]
    elif kind == "peak":
        A = 10 ** (gain_db / 40)
        b = [1 + a * A, -2 * cw, 1 - a * A]
        aa = [1 + a / A, -2 * cw, 1 - a / A]
    elif kind == "lowshelf":
        A = 10 ** (gain_db / 40)
        sq = 2 * np.sqrt(A) * a
        b = [A * ((A + 1) - (A - 1) * cw + sq), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - sq)]
        aa = [(A + 1) + (A - 1) * cw + sq, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sq]
    elif kind == "highshelf":
        A = 10 ** (gain_db / 40)
        sq = 2 * np.sqrt(A) * a
        b = [A * ((A + 1) + (A - 1) * cw + sq), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sq)]
        aa = [(A + 1) - (A - 1) * cw + sq, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sq]
    else:
        raise ValueError(kind)
    b = np.array(b) / aa[0]
    aa = np.array(aa) / aa[0]
    return b, aa


def filt(x, kind, f, q=0.707, gain_db=0.0):
    b, a = biquad_coeffs(kind, f, q, gain_db)
    return signal.lfilter(b, a, x, axis=-1)


def filt_sweep(x, kind, cutoff_curve, q=0.707, block=128):
    """Time-varying biquad: cutoff_curve has one value per sample."""
    y = np.empty_like(x)
    zi = np.zeros(2)
    for s in range(0, x.size, block):
        e = min(x.size, s + block)
        b, a = biquad_coeffs(kind, float(cutoff_curve[s]), q)
        y[s:e], zi = signal.lfilter(b, a, x[s:e], zi=zi)
    return y


# --------------------------------------------------------- instruments ---
@dataclass
class Inst:
    osc: str = "pulse"          # pulse saw tri nestri sine fm supersaw pluck choir organ noise
    duty: float = 0.5
    pwm_rate: float = 0.0       # Hz
    pwm_depth: float = 0.0
    unison: int = 1
    detune: float = 0.0         # cents spread across unison voices
    spread: float = 0.0         # stereo width of unison 0..1
    sub: float = 0.0            # sine one octave below, level
    octave_layer: float = 0.0   # same osc one octave up, level
    a: float = 0.005
    d: float = 0.15
    s: float = 0.7
    r: float = 0.12
    cutoff: float | None = None  # lowpass Hz
    q: float = 0.707
    fenv: float = 0.0           # octaves added to cutoff at note start
    fdecay: float = 0.2
    key_track: float = 0.0      # cutoff follows pitch (0..1)
    vib_rate: float = 5.5
    vib_depth: float = 0.0      # semitones
    vib_delay: float = 0.25
    glide: float = 0.0          # seconds for legato portamento
    pitch_env: float = 0.0      # semitones at onset
    pitch_decay: float = 0.03
    fm_ratio: float = 1.0
    fm_index: float = 0.0
    fm_decay: float = 0.3
    fm_sustain: float = 0.2     # fraction of index kept after decay
    fm_feedback: float = 0.0
    drive: float = 0.0
    gain: float = 1.0
    formants: tuple = ()        # for choir: ((f, q, gain), ...)
    pluck_damp: float = 0.5
    retrig_phase: bool = True


# Presets ---------------------------------------------------------------
def lead_pulse(duty=0.25, **kw):
    """Bright chip lead with delayed vibrato (NES/SNES hero melody)."""
    return replace(Inst(osc="pulse", duty=duty, a=0.004, d=0.18, s=0.75, r=0.09, cutoff=6500, q=0.8,
                        fenv=0.8, fdecay=0.15, vib_depth=0.18, vib_rate=5.6, vib_delay=0.18, gain=0.55), **kw)


def lead_pwm(**kw):
    return replace(Inst(osc="pulse", duty=0.35, pwm_rate=0.6, pwm_depth=0.12, a=0.006, d=0.2, s=0.8, r=0.12,
                        cutoff=5200, fenv=1.0, fdecay=0.2, vib_depth=0.2, vib_delay=0.22, gain=0.55), **kw)


def lead_saw(**kw):
    """Fat detuned saw lead (16-bit rock / Streets of Rage)."""
    return replace(Inst(osc="saw", unison=3, detune=14, spread=0.35, a=0.005, d=0.25, s=0.75, r=0.12,
                        cutoff=4200, q=1.0, fenv=1.2, fdecay=0.18, vib_depth=0.15, vib_delay=0.2, drive=0.3,
                        gain=0.42), **kw)


def lead_fm(**kw):
    """Genesis-style FM lead: bright attack mellowing out."""
    return replace(Inst(osc="fm", fm_ratio=1.0, fm_index=3.2, fm_decay=0.25, fm_sustain=0.35, fm_feedback=0.2,
                        a=0.003, d=0.3, s=0.75, r=0.12, vib_depth=0.16, vib_delay=0.2, gain=0.6), **kw)


def flute(**kw):
    """Soft fantasy flute/ocarina: sine + breath."""
    return replace(Inst(osc="tri", a=0.05, d=0.2, s=0.85, r=0.18, cutoff=3500, sub=0.0, octave_layer=0.12,
                        vib_depth=0.14, vib_rate=5.0, vib_delay=0.3, gain=0.7), **kw)


def bell(**kw):
    """FM bell / celesta for sparkle and arpeggios."""
    return replace(Inst(osc="fm", fm_ratio=3.5, fm_index=4.0, fm_decay=0.25, fm_sustain=0.05,
                        a=0.001, d=1.2, s=0.0, r=0.8, gain=0.45), **kw)


def harp(**kw):
    """Plucked string (Karplus-Strong) for fantasy arpeggios."""
    return replace(Inst(osc="pluck", pluck_damp=0.45, a=0.001, d=2.0, s=0.0, r=0.4, cutoff=7000, gain=0.8), **kw)


def strings(**kw):
    """Lush supersaw string pad, slow attack."""
    return replace(Inst(osc="supersaw", unison=5, detune=18, spread=0.8, a=0.25, d=0.4, s=0.85, r=0.6,
                        cutoff=2600, q=0.6, vib_depth=0.04, vib_delay=0.4, gain=0.32), **kw)


def brass(**kw):
    """Synth brass stab/swell (filter opens on attack)."""
    return replace(Inst(osc="saw", unison=2, detune=8, spread=0.3, a=0.03, d=0.25, s=0.75, r=0.15,
                        cutoff=1100, q=1.2, fenv=1.8, fdecay=0.22, key_track=0.5, drive=0.2, gain=0.45), **kw)


def choir(vowel="ah", **kw):
    """Formant 'aah' choir for epic moments."""
    f = {"ah": ((800, 6, 1.0), (1150, 7, 0.6), (2900, 9, 0.25)),
         "oo": ((350, 6, 1.0), (600, 7, 0.5), (2400, 9, 0.15)),
         "eh": ((530, 6, 1.0), (1840, 8, 0.5), (2480, 9, 0.3))}[vowel]
    return replace(Inst(osc="choir", unison=5, detune=16, spread=0.7, a=0.3, d=0.3, s=0.9, r=0.7,
                        vib_depth=0.1, vib_rate=4.8, vib_delay=0.3, formants=f, gain=1.6), **kw)


def organ(**kw):
    return replace(Inst(osc="organ", a=0.01, d=0.1, s=0.9, r=0.15, vib_depth=0.05, vib_rate=6.5, vib_delay=0.0,
                        gain=0.35), **kw)


def bass_nes(**kw):
    """Stepped triangle bass with a sine sub: classic chip bass."""
    return replace(Inst(osc="nestri", sub=0.35, a=0.002, d=0.1, s=0.9, r=0.05, cutoff=3000, gain=0.85), **kw)


def bass_fm(**kw):
    """Punchy FM slap bass (Genesis)."""
    return replace(Inst(osc="fm", fm_ratio=1.0, fm_index=2.6, fm_decay=0.08, fm_sustain=0.15, fm_feedback=0.25,
                        a=0.002, d=0.25, s=0.55, r=0.06, sub=0.25, gain=0.75), **kw)


def bass_pulse(**kw):
    return replace(Inst(osc="pulse", duty=0.5, sub=0.4, a=0.002, d=0.12, s=0.7, r=0.05, cutoff=1400, fenv=1.2,
                        fdecay=0.08, gain=0.55), **kw)


def bass_saw(**kw):
    """Gritty filtered saw bass for the boss."""
    return replace(Inst(osc="saw", unison=2, detune=6, sub=0.5, a=0.002, d=0.15, s=0.6, r=0.05, cutoff=700, q=1.4,
                        fenv=2.2, fdecay=0.09, drive=0.5, gain=0.5), **kw)


def arp_pulse(**kw):
    """Short 12.5% pulse blips for fast arpeggios."""
    return replace(Inst(osc="pulse", duty=0.125, a=0.001, d=0.08, s=0.25, r=0.04, cutoff=7000, gain=0.38), **kw)


def pluck_synth(**kw):
    return replace(Inst(osc="saw", unison=2, detune=10, spread=0.5, a=0.001, d=0.18, s=0.0, r=0.1, cutoff=900,
                        q=1.0, fenv=3.0, fdecay=0.06, gain=0.45), **kw)


def timpani_inst(**kw):
    return replace(Inst(osc="sine", a=0.002, d=0.9, s=0.0, r=0.5, pitch_env=4.0, pitch_decay=0.04,
                        sub=0.0, octave_layer=0.25, gain=1.2), **kw)


PRESETS = {k: v for k, v in globals().items() if callable(v) and k in (
    "lead_pulse lead_pwm lead_saw lead_fm flute bell harp strings brass choir organ bass_nes bass_fm "
    "bass_pulse bass_saw arp_pulse pluck_synth timpani_inst").split()}


def _adsr(inst: Inst, gate: float, n_total: int) -> np.ndarray:
    a = max(1, int(inst.a * SR))
    d = max(1, int(inst.d * SR))
    g = max(1, int(gate * SR))
    env = np.empty(n_total)
    t = np.arange(n_total)
    # attack / decay curves (exponential-ish feel)
    att = np.clip(t / a, 0, 1)
    dec_t = np.clip((t - a) / d, 0, 1)
    dec = inst.s + (1.0 - inst.s) * (1.0 - dec_t) ** 2.2
    env = np.where(t < a, att, dec)
    # release from the level at gate time
    lvl = env[min(g, n_total - 1)] if g < n_total else env[-1]
    rel_n = max(1, n_total - g)
    if g < n_total:
        rt = np.arange(rel_n) / max(1, int(inst.r * SR))
        env[g:] = lvl * np.exp(-5.0 * rt)
    return env


def _pluck(freq0: float, n: int, damp: float) -> np.ndarray:
    """Karplus-Strong plucked string, computed one period-block at a time."""
    period = max(2, int(round(SR / freq0)))
    total = n + period + 1
    out = np.zeros(total)
    init = signal.lfilter([0.5, 0.5], [1], _rng.uniform(-1, 1, period + 1))
    out[:period + 1] = init
    pos = period + 1
    k = 0.5 * (0.997 - 0.006 * damp)
    while pos < total:
        e = min(pos + period, total)
        out[pos:e] = k * (out[pos - period:e - period] + out[pos - period - 1:e - period - 1])
        pos = e
    return out[period + 1:period + 1 + n]


def render_note(inst: Inst, m: float, gate: float, vel: float, prev_m: float | None = None,
                glide: float = 0.0) -> np.ndarray:
    """Returns stereo array (2, n) for one note."""
    n = int((gate + inst.r * 1.6 + 0.01) * SR)
    if inst.osc in ("pluck",) or inst.s == 0.0:
        n = int((min(gate + inst.r, inst.d * 1.5 + inst.r) + 0.02) * SR) if inst.osc != "pluck" else int((max(gate, 0.3) + inst.d) * SR)
        n = max(n, int(0.05 * SR))
    t = np.arange(n) / SR
    semis = np.full(n, float(m))
    g = glide or inst.glide
    if prev_m is not None and g > 0:
        gl = np.clip(t / g, 0, 1)
        semis = prev_m + (m - prev_m) * (1 - (1 - gl) ** 2)
    if inst.pitch_env:
        semis = semis + inst.pitch_env * np.exp(-t / max(inst.pitch_decay, 1e-4))
    if inst.vib_depth:
        ramp = np.clip((t - inst.vib_delay) / 0.25, 0, 1)
        semis = semis + inst.vib_depth * ramp * np.sin(2 * np.pi * inst.vib_rate * t)
    f = 440.0 * 2.0 ** ((semis - 69) / 12.0)
    env = _adsr(inst, gate, n)
    voices = max(1, inst.unison)
    left = np.zeros(n)
    right = np.zeros(n)
    for v in range(voices):
        if voices > 1:
            off = (v / (voices - 1) - 0.5) * 2.0
            cents = off * inst.detune
            pan = off * inst.spread
        else:
            cents, pan = 0.0, 0.0
        fv = f * 2 ** (cents / 1200.0)
        dt = fv / SR
        ph0 = 0.0 if (inst.retrig_phase and voices == 1) else _rng.random()
        phase = ph0 + np.cumsum(dt)
        o = inst.osc
        if o == "pulse":
            duty = inst.duty + inst.pwm_depth * np.sin(2 * np.pi * inst.pwm_rate * t) if inst.pwm_depth else inst.duty
            y = osc_pulse(phase, dt, duty)
        elif o in ("saw", "supersaw", "choir"):
            y = osc_saw(phase, dt)
        elif o == "tri":
            y = osc_tri(phase, dt)
        elif o == "nestri":
            y = osc_nestri(phase, dt)
        elif o == "sine":
            y = osc_sine(phase, dt)
        elif o == "organ":
            y = (np.sin(2 * np.pi * phase) + 0.6 * np.sin(4 * np.pi * phase) + 0.35 * np.sin(6 * np.pi * phase)
                 + 0.25 * np.sin(8 * np.pi * phase) + 0.2 * np.sin(2 * np.pi * phase * 0.5))
        elif o == "fm":
            idx = inst.fm_index * (inst.fm_sustain + (1 - inst.fm_sustain) * np.exp(-t / max(inst.fm_decay, 1e-3)))
            mod = np.sin(2 * np.pi * phase * inst.fm_ratio)
            if inst.fm_feedback:
                mod = np.sin(2 * np.pi * phase * inst.fm_ratio + inst.fm_feedback * mod)
            y = np.sin(2 * np.pi * phase + idx * mod)
        elif o == "pluck":
            y = _pluck(float(f[0]), n, inst.pluck_damp)
        elif o == "noise":
            y = _rng.uniform(-1, 1, n)
        else:
            raise ValueError(o)
        if inst.octave_layer:
            if o == "pulse":
                y2 = osc_pulse(phase * 2, dt * 2, inst.duty)
            elif o in ("saw", "supersaw", "choir"):
                y2 = osc_saw(phase * 2, dt * 2)
            elif o == "sine":
                y2 = osc_sine(phase * 2, dt * 2)
            else:
                y2 = osc_tri(phase * 2, dt * 2)
            y = y + inst.octave_layer * y2
        if voices > 1:
            pl = np.cos((pan + 1) * np.pi / 4)
            pr = np.sin((pan + 1) * np.pi / 4)
            left += y * pl
            right += y * pr
        else:
            left += y
    if voices > 1:
        left /= np.sqrt(voices)
        right /= np.sqrt(voices)
        mono = False
    else:
        mono = True
    chans = [left] if mono else [left, right]
    out = []
    for y in chans:
        if inst.sub:
            y = y + inst.sub * np.sin(2 * np.pi * np.cumsum(f / 2) / SR)
        if inst.osc == "choir":
            acc = np.zeros_like(y)
            for (ff, fq, fg) in inst.formants:
                acc += fg * filt(y, "bp", ff, fq)
            y = acc
        if inst.cutoff:
            base = inst.cutoff * (2 ** (inst.key_track * (m - 60) / 12.0))
            if inst.fenv:
                curve = base * 2 ** (inst.fenv * np.exp(-t / max(inst.fdecay, 1e-3)))
                y = filt_sweep(y, "lp", curve, inst.q)
            else:
                y = filt(y, "lp", base, inst.q)
        if inst.drive:
            k = 1 + inst.drive * 6
            y = np.tanh(y * k) / np.tanh(k)
        out.append(y * env * vel * inst.gain)
    if mono:
        return np.vstack([out[0], out[0]]) * 0.7071
    return np.vstack(out)


# ----------------------------------------------------------------- drums ---
def _env(n, decay, attack=0.0005):
    t = np.arange(n) / SR
    e = np.exp(-t / decay)
    a = max(1, int(attack * SR))
    e[:a] *= np.linspace(0, 1, a)
    return e


def _sweep_sine(f0, f1, dur, curve=0.05):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t / curve)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def make_drum(voice: str) -> np.ndarray:
    """Synthesise one drum hit (mono)."""
    if voice in ("kick", "kick_hard"):
        d = 0.42
        n = int(d * SR)
        body = _sweep_sine(170 if voice == "kick" else 220, 46, d, 0.035) * _env(n, 0.16)
        click = filt(_rng.uniform(-1, 1, n), "hp", 2500) * _env(n, 0.004) * 0.5
        y = body + click
        if voice == "kick_hard":
            y = np.tanh(y * 2.2) / np.tanh(2.2)
        return y * 1.0
    if voice == "kick_chip":
        d = 0.25
        n = int(d * SR)
        t = np.arange(n) / SR
        f = 45 + 160 * np.exp(-t / 0.03)
        y = osc_nestri(np.cumsum(f) / SR, f / SR) * _env(n, 0.09)
        return y
    if voice in ("snare", "snare_tight"):
        d = 0.3 if voice == "snare" else 0.18
        n = int(d * SR)
        tone = (_sweep_sine(260, 185, d, 0.02) * 0.7 + _sweep_sine(400, 330, d, 0.02) * 0.3) * _env(n, 0.06)
        nz = filt(filt(_rng.uniform(-1, 1, n), "hp", 1200), "lp", 9000) * _env(n, 0.12 if voice == "snare" else 0.06)
        return (tone * 0.55 + nz * 0.8)
    if voice == "snare_chip":
        d = 0.2
        n = int(d * SR)
        nz = lfsr_noise(n, 2) * _env(n, 0.07)
        tone = osc_nestri(np.cumsum(np.full(n, 220.0)) / SR, np.full(n, 220 / SR)) * _env(n, 0.03)
        return filt(nz * 0.8 + tone * 0.4, "lp", 9000)
    if voice == "clap":
        d = 0.3
        n = int(d * SR)
        nz = filt(_rng.uniform(-1, 1, n), "bp", 1300, 1.2)
        e = np.zeros(n)
        for k, off in enumerate((0, 0.01, 0.021)):
            o = int(off * SR)
            e[o:] += _env(n - o, 0.008 if k < 2 else 0.11)
        return nz * e * 1.6
    if voice in ("hat", "hat_chip", "ohat"):
        d = {"hat": 0.06, "hat_chip": 0.05, "ohat": 0.35}[voice]
        n = int(d * SR)
        if voice == "hat_chip":
            src = lfsr_noise(n, 1, short=True)
        else:
            src = _rng.uniform(-1, 1, n)
            # metallic partials
            t = np.arange(n) / SR
            for fr in (3150, 4280, 5370, 6830, 8120):
                src += 0.25 * np.sign(np.sin(2 * np.pi * fr * t))
        y = filt(src, "hp", 7000 if voice != "ohat" else 6000) * _env(n, d / 3.2)
        return y * 0.55
    if voice == "shaker":
        d = 0.08
        n = int(d * SR)
        return filt(_rng.uniform(-1, 1, n), "hp", 5000) * _env(n, 0.02, 0.01) * 0.4
    if voice in ("crash", "ride"):
        d = 2.2 if voice == "crash" else 1.0
        n = int(d * SR)
        t = np.arange(n) / SR
        src = _rng.uniform(-1, 1, n)
        for fr in (420, 610, 853, 1170, 1630, 2210, 3360):
            src += 0.15 * np.sin(2 * np.pi * fr * t + 3 * np.sin(2 * np.pi * fr * 1.41 * t))
        y = filt(src, "hp", 4000 if voice == "crash" else 6000) * _env(n, 0.55 if voice == "crash" else 0.25, 0.002)
        return y * (0.5 if voice == "crash" else 0.3)
    if voice.startswith("tom"):
        f0 = {"tom_hi": 220, "tom_mid": 160, "tom_lo": 110}[voice]
        d = 0.5
        n = int(d * SR)
        y = _sweep_sine(f0 * 1.6, f0, d, 0.05) * _env(n, 0.18)
        y += filt(_rng.uniform(-1, 1, n), "bp", f0 * 3, 1.0) * _env(n, 0.02) * 0.4
        return y * 0.9
    if voice.startswith("timp"):
        f0 = {"timp_lo": 73.4, "timp": 98.0, "timp_hi": 110.0}[voice]  # D2, G2, A2
        d = 1.6
        n = int(d * SR)
        t = np.arange(n) / SR
        f = f0 * (1 + 0.06 * np.exp(-t / 0.05))
        ph = np.cumsum(f) / SR
        y = (np.sin(2 * np.pi * ph) + 0.5 * np.sin(2 * np.pi * ph * 1.5) * np.exp(-t / 0.3)
             + 0.3 * np.sin(2 * np.pi * ph * 1.98) * np.exp(-t / 0.2))
        y = y * _env(n, 0.5) + filt(_rng.uniform(-1, 1, n), "lp", 800) * _env(n, 0.03) * 0.6
        return y * 0.9
    if voice == "gong":
        d = 4.0
        n = int(d * SR)
        t = np.arange(n) / SR
        y = np.zeros(n)
        for fr, a in ((110, 1.0), (163, 0.7), (227, 0.5), (311, 0.4), (412, 0.3), (589, 0.2)):
            y += a * np.sin(2 * np.pi * fr * t + 2 * np.sin(2 * np.pi * fr * 0.5 * t) * np.exp(-t))
        swell = 1 - np.exp(-t / 0.15)
        return y * swell * np.exp(-t / 1.4) * 0.35
    if voice == "riser":
        d = 2.0
        n = int(d * SR)
        t = np.arange(n) / SR
        nz = _rng.uniform(-1, 1, n)
        curve = 500 * 2 ** (t / d * 4.5)
        return filt_sweep(nz, "bp", curve, 2.0) * (t / d) ** 2 * 0.6
    if voice == "reverse_cymbal":
        y = make_drum("crash")[: int(1.5 * SR)][::-1]
        return y * np.linspace(0, 1, y.size) ** 2
    raise ValueError(f"unknown drum voice {voice!r}")


DRUM_VOICES = ["kick", "kick_hard", "kick_chip", "snare", "snare_tight", "snare_chip", "clap", "hat", "hat_chip",
               "ohat", "shaker", "crash", "ride", "tom_hi", "tom_mid", "tom_lo", "timp_lo", "timp", "timp_hi",
               "gong", "riser", "reverse_cymbal"]
DRUM_PAN = {"hat": 0.3, "hat_chip": 0.3, "ohat": 0.3, "shaker": -0.35, "ride": -0.3, "crash": -0.15,
            "tom_hi": 0.35, "tom_mid": 0.0, "tom_lo": -0.35}
_drum_cache: dict[str, np.ndarray] = {}


def drum(voice):
    if voice not in _drum_cache:
        _drum_cache[voice] = make_drum(voice)
    return _drum_cache[voice]


# ---------------------------------------------------------------- tracks ---
@dataclass
class Note:
    beat: float
    m: float
    beats: float
    vel: float = 0.8
    slide: bool = False


class Track:
    def __init__(self, song, name, inst: Inst, vol=-10.0, pan=0.0, reverb=0.15, delay=0.0,
                 duck=0.0, hp=None, lp=None, eq=(), width=1.0):
        self.song, self.name, self.inst = song, name, inst
        self.vol, self.pan, self.reverb, self.delay = vol, pan, reverb, delay
        self.duck, self.hp, self.lp, self.eq, self.width = duck, hp, lp, eq, width
        self.notes: list[Note] = []
        self.automation: list[tuple[float, float]] = []  # (beat, gain dB) points

    # -- writing --
    def note(self, beat, m, beats, vel=0.8, slide=False):
        self.notes.append(Note(float(beat), float(midi(m)), float(beats), float(vel), slide))
        return self

    def chord(self, bar, notes, beats=None, vel=0.7, at=0.0, strum=0.0):
        """Block chord at bar (+ `at` beats). `notes` = list of names/midis or a chord symbol string."""
        if isinstance(notes, str):
            notes = chord_tones(notes, 4)
        beats = beats if beats is not None else self.song.beats_per_bar
        b0 = self.song.bar_beat(bar) + at
        for i, n in enumerate(notes):
            self.note(b0 + i * strum, n, beats - i * strum, vel)
        return self

    def seq(self, bar, text, unit=0.5, vel=0.8, transpose=0, at=0.0):
        """Write tracker notation starting at `bar` (+ `at` beats). Returns the next free beat."""
        beat = self.song.bar_beat(bar) + at
        last: list[Note] = []
        for tok in text.replace("|", " ").split():
            dur = 1.0
            if ":" in tok:
                tok, d = tok.rsplit(":", 1)
                dur = float(eval(d, {}, {})) if "/" in d else float(d)
            v = vel
            stacc = slide = False
            while tok and tok[-1] in "^_.>":
                c = tok[-1]
                tok = tok[:-1]
                if c == "^":
                    v = min(1.0, vel * 1.25 + 0.05)
                elif c == "_":
                    v = vel * 0.6
                elif c == ".":
                    stacc = True
                elif c == ">":
                    slide = True
            length = dur * unit
            if tok == "-":
                last = []
            elif tok == "~":
                for nn in last:
                    nn.beats += length
            else:
                names = tok[1:-1].split() if tok.startswith("[") else [tok]
                if tok.startswith("["):
                    pass
                last = []
                for nm in names:
                    nt = Note(beat, float(midi(nm) + transpose), length * (0.5 if stacc else 1.0), v, slide)
                    self.notes.append(nt)
                    last.append(nt)
            beat += length
        return beat

    def arp(self, bar, notes, pattern="0 1 2 1", unit=0.25, beats=None, vel=0.7, gate=0.9, at=0.0):
        """Repeat an index pattern over `notes` (list or chord symbol) for `beats` beats."""
        if isinstance(notes, str):
            notes = chord_tones(notes, 4)
        notes = [midi(n) for n in notes]
        idx = [int(i) for i in pattern.split()]
        beats = beats if beats is not None else self.song.beats_per_bar
        b0 = self.song.bar_beat(bar) + at
        steps = int(round(beats / unit))
        for s in range(steps):
            k = idx[s % len(idx)]
            octv, k = divmod(k, len(notes))
            self.note(b0 + s * unit, notes[k] + 12 * octv, unit * gate, vel * (1.0 if s % 4 == 0 else 0.85))
        return self

    def fade(self, bar_from, bar_to, db_from, db_to):
        self.automation.append((self.song.bar_beat(bar_from), db_from))
        self.automation.append((self.song.bar_beat(bar_to), db_to))
        return self

    def copy_bars(self, src_bar, n_bars, dst_bar, transpose=0):
        """Duplicate notes of bars [src, src+n) to dst."""
        s0, s1 = self.song.bar_beat(src_bar), self.song.bar_beat(src_bar + n_bars)
        d = self.song.bar_beat(dst_bar) - s0
        for nt in [x for x in self.notes if s0 <= x.beat < s1]:
            self.notes.append(Note(nt.beat + d, nt.m + transpose, nt.beats, nt.vel, nt.slide))
        return self

    # -- rendering --
    def render(self, total_n):
        song = self.song
        out = np.zeros((2, total_n))
        notes = sorted(self.notes, key=lambda x: x.beat)
        prev_end = -1.0
        prev_m = None
        prev_slide = False
        for nt in notes:
            start = song.beat_sec(nt.beat)
            gate = song.beat_sec(nt.beat + nt.beats) - start
            legato = prev_m is not None and (abs(nt.beat - prev_end) < 1e-3 or nt.beat < prev_end)
            glide = 0.0
            pm = None
            if (self.inst.glide > 0 and legato) or prev_slide:
                pm = prev_m
                glide = self.inst.glide if self.inst.glide > 0 else min(0.08, gate * 0.5)
            y = render_note(self.inst, nt.m, max(gate, 0.005), nt.vel, pm, glide)
            s = int(start * SR)
            e = min(total_n, s + y.shape[1])
            if s < total_n:
                out[:, s:e] += y[:, : e - s]
            prev_end = nt.beat + nt.beats
            prev_m = nt.m
            prev_slide = nt.slide
        return out


class DrumTrack:
    def __init__(self, song, name, vol=-6.0, reverb=0.08, delay=0.0, hp=None, lp=None, eq=()):
        self.song, self.name = song, name
        self.vol, self.reverb, self.delay, self.hp, self.lp, self.eq = vol, reverb, delay, hp, lp, eq
        self.pan, self.duck, self.width = 0.0, 0.0, 1.0
        self.hits: list[tuple[float, str, float]] = []
        self.automation = []
        self.inst = None

    def hit(self, beat, voice, vel=0.9):
        if voice not in DRUM_VOICES:
            raise ValueError(f"unknown drum voice {voice!r}; known: {DRUM_VOICES}")
        self.hits.append((float(beat), voice, float(vel)))
        return self

    def pat(self, bar, voices: dict, unit=0.25, bars=1, at=0.0, swing=0.0):
        """Step patterns: 'x' hit, 'X' accent, 'o' ghost, '.'/'-' rest. A pattern
        shorter than the span repeats. `swing` delays every odd step by that fraction of a step."""
        b0 = self.song.bar_beat(bar) + at
        span = bars * self.song.beats_per_bar
        for voice, p in voices.items():
            p = p.replace(" ", "").replace("|", "")
            steps = int(round(span / unit))
            for s in range(steps):
                c = p[s % len(p)]
                if c in ".-":
                    continue
                v = {"x": 0.85, "X": 1.0, "o": 0.45}.get(c, 0.85)
                sw = swing * unit if s % 2 == 1 else 0.0
                self.hit(b0 + s * unit + sw, voice, v)
        return self

    def fill(self, bar, text, unit=0.25, at=0.0):
        """Sequence of voices: 'tom_hi tom_hi tom_mid tom_lo snare snare crash' ('-' rest)."""
        b = self.song.bar_beat(bar) + at
        for tok in text.split():
            vel = 0.9
            if tok.endswith("^"):
                tok, vel = tok[:-1], 1.0
            if tok.endswith("_"):
                tok, vel = tok[:-1], 0.5
            if tok != "-":
                self.hit(b, tok, vel)
            b += unit
        return self

    def render(self, total_n):
        out = np.zeros((2, total_n))
        for beat, voice, vel in self.hits:
            y = drum(voice)
            s = int(self.song.beat_sec(beat) * SR)
            if s >= total_n:
                continue
            e = min(total_n, s + y.size)
            p = DRUM_PAN.get(voice, 0.0)
            out[0, s:e] += y[: e - s] * vel * np.cos((p + 1) * np.pi / 4)
            out[1, s:e] += y[: e - s] * vel * np.sin((p + 1) * np.pi / 4)
        return out


# ------------------------------------------------------------------ song ---
def _reverb_ir(seconds=2.0, damp=0.5, predelay=0.02, seed=7):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = np.zeros((2, n + int(predelay * SR)))
    for ch in range(2):
        nz = rng.standard_normal(n) * np.exp(-6.9 * t / seconds)
        # darker tail: progressive lowpass by blending with a smoothed copy
        smooth = filt(nz, "lp", 2500 + 6000 * (1 - damp))
        mix = np.clip(t / seconds * 1.5, 0, 1)
        y = nz * (1 - mix) + smooth * mix
        # early reflections
        for k in range(8):
            d = int(rng.uniform(0.005, 0.06) * SR)
            if d < n:
                y[d] += rng.uniform(-0.6, 0.6)
        ir[ch, int(predelay * SR):] = y
    ir /= np.sqrt(np.sum(ir ** 2) / 2)
    return ir


class Song:
    def __init__(self, name, bpm=140, bars=16, beats_per_bar=4, reverb_seconds=2.0, reverb_damp=0.5,
                 delay_beats=0.75, delay_feedback=0.35, master_gain=0.0):
        self.name, self.bpm, self.bars, self.beats_per_bar = name, bpm, bars, beats_per_bar
        self.tracks: list = []
        self.reverb_seconds, self.reverb_damp = reverb_seconds, reverb_damp
        self.delay_beats, self.delay_feedback = delay_beats, delay_feedback
        self.loop_bar = 0
        self.looping = True
        self.harmony: list[tuple[float, float, str]] = []  # (beat_from, beat_to, chord)
        self.sections: list[tuple[int, str]] = []
        self.tempo_map: list[tuple[float, float]] = []    # optional (beat, bpm) changes
        self.master_gain = master_gain
        self.tail_seconds = 3.0

    # -- timing --
    def bar_beat(self, bar):
        return float(bar) * self.beats_per_bar

    def beat_sec(self, beat):
        return beat * 60.0 / self.bpm

    @property
    def length_beats(self):
        return self.bars * self.beats_per_bar

    # -- structure --
    def track(self, name, inst: Inst, **kw) -> Track:
        t = Track(self, name, inst, **kw)
        self.tracks.append(t)
        return t

    def drums(self, name="drums", **kw) -> DrumTrack:
        t = DrumTrack(self, name, **kw)
        self.tracks.append(t)
        return t

    def chords(self, bar, text, per=1.0):
        """Declare harmony: 'Am F C G' each lasting `per` bars from `bar`. Use 'Am:2' for 2x length."""
        b = self.bar_beat(bar)
        for tok in text.split():
            mult = 1.0
            if ":" in tok:
                tok, mm = tok.split(":")
                mult = float(mm)
            length = per * mult * self.beats_per_bar
            self.harmony.append((b, b + length, tok))
            b += length
        return self

    def chord_at(self, beat):
        for b0, b1, c in self.harmony:
            if b0 <= beat < b1:
                return c
        return None

    def section(self, bar, label):
        self.sections.append((bar, label))
        return self

    def loop(self, bar=0):
        self.loop_bar = bar
        self.looping = True
        return self

    def no_loop(self, tail=2.5):
        self.looping = False
        self.tail_seconds = tail
        return self

    # -- render --
    def render(self, out_dir=None, report=True, stems_report=True):
        out_dir = out_dir or AUDIO_OUT
        os.makedirs(out_dir, exist_ok=True)
        os.makedirs(REPORT_OUT, exist_ok=True)
        body_n = int(round(self.beat_sec(self.length_beats) * SR))
        total_n = body_n + int(self.tail_seconds * SR) + int(self.reverb_seconds * SR)
        dry = np.zeros((2, total_n))
        rev_bus = np.zeros((2, total_n))
        dly_bus = np.zeros((2, total_n))
        stems = {}
        # sidechain envelope from kicks of all drum tracks
        kick_env = np.zeros(total_n)
        for tr in self.tracks:
            if isinstance(tr, DrumTrack):
                for beat, voice, vel in tr.hits:
                    if voice.startswith("kick"):
                        s = int(self.beat_sec(beat) * SR)
                        n = min(total_n - s, int(0.25 * SR))
                        if n > 0:
                            kick_env[s:s + n] = np.maximum(kick_env[s:s + n], vel * np.exp(-np.arange(n) / (0.07 * SR)))
        for tr in self.tracks:
            y = tr.render(total_n)
            if tr.hp:
                y = filt(y, "hp", tr.hp)
            if tr.lp:
                y = filt(y, "lp", tr.lp)
            for (kind, f, gdb, q) in tr.eq:
                y = filt(y, kind, f, q, gdb)
            if tr.width != 1.0:
                mid = (y[0] + y[1]) / 2
                side = (y[0] - y[1]) / 2 * tr.width
                y = np.vstack([mid + side, mid - side])
            p = tr.pan
            y = y * np.array([[np.cos((p + 1) * np.pi / 4) * 1.4142], [np.sin((p + 1) * np.pi / 4) * 1.4142]])
            g = db(tr.vol)
            if tr.automation:
                pts = sorted(tr.automation)
                xs = [int(self.beat_sec(b) * SR) for b, _ in pts]
                ys = [d for _, d in pts]
                curve = db(np.interp(np.arange(total_n), xs, ys))
                y = y * curve
            y = y * g
            if tr.duck:
                y = y * (1.0 - tr.duck * kick_env)
            stems[tr.name] = y
            dry += y
            if tr.reverb:
                rev_bus += y * tr.reverb
            if tr.delay:
                dly_bus += y * tr.delay
        wet = np.zeros_like(dry)
        if np.any(rev_bus):
            ir = _reverb_ir(self.reverb_seconds, self.reverb_damp)
            rb = filt(rev_bus, "hp", 250)
            for ch in range(2):
                wet[ch] += signal.fftconvolve(rb[ch], ir[ch])[:total_n]
        if np.any(dly_bus):
            d = int(self.beat_sec(self.delay_beats) * SR)
            fb = self.delay_feedback
            db_ = filt(filt(dly_bus, "hp", 300), "lp", 5000)
            acc = np.zeros_like(db_)
            src = db_.copy()
            for k in range(1, 8):
                sh = d * k
                if sh >= total_n:
                    break
                gain = fb ** (k - 1)
                ch_from = (k + 1) % 2  # ping-pong
                acc[ch_from, sh:] += src[0, :total_n - sh] * gain * 0.5 + src[1, :total_n - sh] * gain * 0.5
            wet += acc
        mix = dry + wet
        # loop seam: wrap the tail into the loop start
        if self.looping:
            loop_start = int(round(self.beat_sec(self.bar_beat(self.loop_bar)) * SR))
            tail = mix[:, body_n:]
            room = body_n - loop_start
            tl = min(tail.shape[1], room)
            mix = mix[:, :body_n].copy()
            mix[:, loop_start:loop_start + tl] += tail[:, :tl]
            for k in stems:
                st = stems[k][:, :body_n].copy()
                st[:, loop_start:loop_start + tl] += stems[k][:, body_n:body_n + tl]
                stems[k] = st
        else:
            loop_start = None
            end = body_n + int(self.tail_seconds * SR)
            mix = mix[:, :end]
            fade = int(0.3 * SR)
            mix[:, -fade:] *= np.linspace(1, 0, fade)
        mix = master_chain(mix, self.master_gain, wrap=self.looping, loop_start=loop_start or 0)
        path = os.path.join(out_dir, self.name + ".wav")
        write_wav(path, mix)
        meta = {"name": self.name, "samples": int(mix.shape[1]), "sample_rate": SR,
                "loop": bool(self.looping), "loop_begin": int(loop_start or 0),
                "loop_end": int(mix.shape[1]), "bpm": self.bpm, "bars": self.bars}
        with open(os.path.join(REPORT_OUT, self.name + ".loop.json"), "w") as f:
            json.dump(meta, f, indent=1)
        rep = None
        if report:
            rep = analyse(self, mix, stems if stems_report else {}, loop_start)
            with open(os.path.join(REPORT_OUT, self.name + ".report.txt"), "w") as f:
                f.write(rep)
            piano_roll(self, os.path.join(REPORT_OUT, self.name + ".roll.png"))
            print(rep)
        print(f"wrote {path} ({mix.shape[1] / SR:.1f}s)")
        return meta


def master_chain(x, gain_db=0.0, wrap=True, loop_start=0, target_rms_db=-15.0, ceiling_db=-1.0):
    x = x * db(gain_db)
    # For a loop that restarts at sample 0, warm the filter, compressor and
    # limiter state with the last second of the body so the processing is
    # continuous across the seam instead of starting from silence.
    warm = min(SR, x.shape[1] // 4) if wrap and loop_start == 0 else 0
    if warm:
        x = np.concatenate([x[:, -warm:], x], axis=1)
    x = filt(x, "hp", 28)
    # glue compressor (RMS, 2.2:1 above threshold, 30 ms attack / 250 ms release)
    lvl = np.sqrt(signal.lfilter([1 - np.exp(-1 / (0.03 * SR))], [1, -np.exp(-1 / (0.03 * SR))],
                                 (x[0] ** 2 + x[1] ** 2) / 2) + 1e-12)
    rms_now = np.sqrt(np.mean(x[:, warm:] ** 2)) + 1e-12
    thr = rms_now * 1.3
    over = np.maximum(lvl / thr, 1.0)
    gr = over ** (1 / 2.2 - 1)
    gr = signal.lfilter([1 - np.exp(-1 / (0.25 * SR))], [1, -np.exp(-1 / (0.25 * SR))], gr - 1) + 1
    x = x * gr
    # normalise loudness
    rms = np.sqrt(np.mean(x[:, warm:] ** 2)) + 1e-12
    x = x * (db(target_rms_db) / rms)
    # brickwall-ish limiter with 3 ms lookahead
    ceil = db(ceiling_db)
    pk = np.maximum(np.abs(x[0]), np.abs(x[1]))
    la = int(0.003 * SR)
    env = maximum_filter1d(pk, size=2 * la + 1)
    g = np.minimum(1.0, ceil / (env + 1e-9))
    g = signal.lfilter([1 - np.exp(-1 / (0.06 * SR))], [1, -np.exp(-1 / (0.06 * SR))], g - 1) + 1
    g = np.minimum(g, np.minimum(1.0, ceil / (env + 1e-9)))
    x = x * g
    x = np.tanh(x / ceil * 0.95) * ceil / np.tanh(0.95)
    return np.clip(x[:, warm:], -0.999, 0.999)


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").T.copy()
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(path, "rb") as w:
        n = w.getnframes()
        ch = w.getnchannels()
        data = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float64) / 32768
    return data.reshape(-1, ch).T


# -------------------------------------------------------------- analysis ---
def _dbfs(v):
    return 20 * np.log10(max(v, 1e-9))


def analyse(song: Song, mix, stems, loop_start):
    L = []
    dur = mix.shape[1] / SR
    peak = np.max(np.abs(mix))
    rms = np.sqrt(np.mean(mix ** 2))
    L.append(f"== {song.name}: {dur:.1f}s, {song.bpm} bpm, {song.bars} bars, loop from bar {song.loop_bar if song.looping else '-'}")
    L.append(f"peak {_dbfs(peak):.1f} dBFS | rms {_dbfs(rms):.1f} dBFS | crest {_dbfs(peak) - _dbfs(rms):.1f} dB | "
             f"clipped samples {int(np.sum(np.abs(mix) > 0.995))}")
    corr = np.corrcoef(mix[0], mix[1])[0, 1]
    L.append(f"stereo L/R correlation {corr:.2f} (1 = mono, <0.3 very wide)")
    mono = (mix[0] + mix[1]) / 2
    spec = np.abs(np.fft.rfft(mono[: min(mono.size, SR * 30)])) ** 2
    freqs = np.fft.rfftfreq(min(mono.size, SR * 30), 1 / SR)
    bands = [("sub <60", 0, 60), ("bass 60-250", 60, 250), ("lowmid 250-800", 250, 800),
             ("mid 800-3k", 800, 3000), ("presence 3k-8k", 3000, 8000), ("air >8k", 8000, 22050)]
    tot = spec.sum() + 1e-12
    L.append("spectrum share: " + "  ".join(f"{n} {100 * spec[(freqs >= a) & (freqs < b)].sum() / tot:.0f}%"
                                             for n, a, b in bands))
    L.append("(reference for bright chiptune/16-bit mixes: bass+sub ~35-55%, mid ~15-30%, presence ~5-15%)")
    if stems:
        L.append("per-track level (rms dBFS before master; share of summed energy):")
        es = {k: float(np.mean(v ** 2)) for k, v in stems.items()}
        te = sum(es.values()) + 1e-12
        for k, v in sorted(es.items(), key=lambda kv: -kv[1]):
            L.append(f"   {k:<14} {_dbfs(np.sqrt(v)):6.1f} dB  {100 * v / te:5.1f}%")
    # Sections and density
    for tr in song.tracks:
        if isinstance(tr, Track) and tr.notes:
            ms = [n.m for n in tr.notes]
            leaps = [abs(b.m - a.m) for a, b in zip(sorted(tr.notes, key=lambda n: n.beat)[:-1],
                                                     sorted(tr.notes, key=lambda n: n.beat)[1:])]
            L.append(f"track {tr.name}: {len(tr.notes)} notes, range {name_of(int(min(ms)))}-{name_of(int(max(ms)))}, "
                     f"max leap {int(max(leaps) if leaps else 0)} st, mean {np.mean(leaps) if leaps else 0:.1f} st")
    # Harmony checks
    if song.harmony:
        for tr in song.tracks:
            if not isinstance(tr, Track) or not tr.notes:
                continue
            strong = [n for n in tr.notes if abs(n.beat % 1.0) < 1e-6 and n.beats >= 0.5]
            bad = []
            for n in strong:
                c = song.chord_at(n.beat)
                if c and int(n.m) % 12 not in chord_pcs(c):
                    bad.append(n)
            if strong:
                pct = 100 * len(bad) / len(strong)
                ex = ", ".join(f"bar {int(n.beat // song.beats_per_bar) + 1}.{n.beat % song.beats_per_bar + 1:g} "
                               f"{name_of(int(n.m))} over {song.chord_at(n.beat)}" for n in bad[:6])
                L.append(f"non-chord tones on beats (>=8th long) in {tr.name}: {len(bad)}/{len(strong)} ({pct:.0f}%)"
                         + (f" e.g. {ex}" if bad else ""))
    # Clashes between pitched tracks (minor 2nds / major 7ths / minor 9ths held together)
    pitched = [t for t in song.tracks if isinstance(t, Track) and t.notes]
    arrs = []
    for t in pitched:
        st = np.array([n.beat for n in t.notes])
        en = st + np.array([n.beats for n in t.notes])
        mm = np.array([int(n.m) for n in t.notes])
        arrs.append((st, en, mm))
    clashes = []
    for i in range(len(pitched)):
        for j in range(i, len(pitched)):
            sa, ea, ma = arrs[i]
            sb, eb, mb = arrs[j]
            for k in range(sa.size):
                ov = np.minimum(ea[k], eb) - np.maximum(sa[k], sb)
                iv = np.abs(ma[k] - mb)
                mask = (ov >= 0.5) & np.isin(iv % 12, (1, 11)) & (iv < 24)
                if i == j:
                    mask &= np.arange(sb.size) > k
                for q in np.nonzero(mask)[0]:
                    clashes.append((max(sa[k], sb[q]), pitched[i].name, name_of(int(ma[k])),
                                    pitched[j].name, name_of(int(mb[q])), float(ov[q])))
    clashes.sort()
    L.append(f"semitone clashes held >= 1/2 beat: {len(clashes)}" +
             ("" if not clashes else "; first: " + "; ".join(
                 f"bar {int(c[0] // song.beats_per_bar) + 1}.{c[0] % song.beats_per_bar + 1:g} {c[1]}:{c[2]} vs {c[3]}:{c[4]}"
                 for c in clashes[:8])))
    # Loop seam
    if loop_start is not None:
        w = int(0.05 * SR)
        end_rms = np.sqrt(np.mean(mix[:, -w:] ** 2))
        st_rms = np.sqrt(np.mean(mix[:, loop_start:loop_start + w] ** 2))
        jump = np.max(np.abs(mix[:, -1] - mix[:, loop_start]))
        L.append(f"loop seam: last 50ms {_dbfs(end_rms):.1f} dB -> loop start 50ms {_dbfs(st_rms):.1f} dB, "
                 f"sample jump {jump:.3f} (under ~0.1 is click-free)")
    if song.sections:
        L.append("sections: " + ", ".join(f"bar {b + 1} {lbl}" for b, lbl in song.sections))
    # loudness over time (per 2 bars)
    seg = int(round(song.beat_sec(song.beats_per_bar * 2) * SR))
    lv = [_dbfs(np.sqrt(np.mean(mix[:, s:s + seg] ** 2))) for s in range(0, mix.shape[1] - seg + 1, seg)]
    L.append("loudness per 2 bars (dB): " + " ".join(f"{v:.0f}" for v in lv))
    return "\n".join(L) + "\n"


def piano_roll(song: Song, path, px_per_beat=12, px_per_semi=4):
    from PIL import Image, ImageDraw
    pitched = [t for t in song.tracks if isinstance(t, Track) and t.notes]
    drums = [t for t in song.tracks if isinstance(t, DrumTrack)]
    lo, hi = 24, 96
    W = int(song.length_beats * px_per_beat) + 120
    H = (hi - lo) * px_per_semi + 60 + 14 * len(DRUM_VOICES)
    im = Image.new("RGB", (W, H), (18, 14, 28))
    d = ImageDraw.Draw(im)
    cols = [(255, 110, 90), (90, 200, 255), (130, 255, 140), (255, 220, 90), (220, 130, 255),
            (255, 160, 220), (120, 255, 230), (255, 170, 60), (180, 180, 255)]
    for b in range(song.bars + 1):
        x = 110 + b * song.beats_per_bar * px_per_beat
        d.line([(x, 0), (x, H)], fill=(60, 50, 80) if b % 4 else (110, 90, 140))
        if b < song.bars:
            d.text((x + 2, 2), str(b + 1), fill=(150, 140, 170))
    for bar, lbl in song.sections:
        d.text((110 + bar * song.beats_per_bar * px_per_beat + 2, 14), lbl, fill=(255, 255, 255))
    for octv in range(lo // 12, hi // 12 + 1):
        y = 40 + (hi - octv * 12) * px_per_semi
        d.line([(110, y), (W, y)], fill=(40, 35, 55))
        d.text((2, y - 6), f"C{octv - 1}", fill=(150, 140, 170))
    for i, tr in enumerate(pitched):
        c = cols[i % len(cols)]
        d.text((2, 40 + i * 12 + (hi - lo) * px_per_semi - 12 * len(pitched)), tr.name, fill=c)
        for n in tr.notes:
            x0 = 110 + n.beat * px_per_beat
            x1 = x0 + max(1, n.beats * px_per_beat - 1)
            y = 40 + (hi - n.m) * px_per_semi
            if lo <= n.m <= hi:
                d.rectangle([x0, y - px_per_semi / 2, x1, y + px_per_semi / 2 - 1], fill=c)
    base = 50 + (hi - lo) * px_per_semi
    used = sorted({v for t in drums for _, v, _ in t.hits}, key=DRUM_VOICES.index)
    for k, v in enumerate(used):
        y = base + k * 12
        d.text((2, y - 2), v, fill=(200, 200, 200))
        for t in drums:
            for beat, voice, vel in t.hits:
                if voice == v:
                    x = 110 + beat * px_per_beat
                    d.rectangle([x, y, x + 3, y + 8], fill=(int(120 + 135 * vel), 120, 120))
    im.save(path)

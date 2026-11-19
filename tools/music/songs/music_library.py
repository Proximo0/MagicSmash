"""Magic Smash - ACT II: THE BURNING LIBRARY (minutes 5-10).

F minor, 168 bpm, 64 bars = 91.4 s, loop(0).  The battle theme a minor 2nd up from
Act I (E minor) and a touch faster: the shelves are on fire and the run is speeding up.

Colour: a baroque "grimoire" band.  A two-choir harpsichord (detuned saw + octave,
fast pluck envelope) spins 16th-note bariolage and Alberti figures under everything,
a church organ doubles the tune and answers it like a fugue, and the hero pulse
carries every first statement of the "Ma-gic SMASH!" theme.  Harmony leans on the
baroque circle of fifths (Fm Bbm Eb Ab Db Gm7b5 C7) and the flat-6 wink.

Form (bars, 1-based)
  1-4    Toccata    harpsichord bariolage on Fm Fm Db C7, organ + brass state x
                    (C C F) like a chapel stab, bar 4 a falling harmonic-minor run
  5-12   Verse      the hero spins a circle-of-fifths sequence built from x (rising 4th
                    onto beat 2, running tail), the wink over Gm7b5-C7; harpsichord
                    Alberti 16ths; organ in 3rds from bar 9
  13-16  Fugato     the harpsichord states the motif as a fugue subject (Fm), the organ
                    answers at the dominant (C minor) over harpsichord running 16ths
  17-20  Calls      hero x calls up the scale (Ab Bb C) answered by harpsichord winks,
                    band stab on C7, toccata run down into the hook (G4 -> C5: the 4th)
  21-28  Hook       theme x2 on the hero; 2nd time HARM on the FM counter, clap, ohat
  29-36  Pages      half time, whispering: the organ sings the motif in augmentation
                    over page-flutter harpsichord and ember crackle; 2nd half the bell
                    doubles it and the hero murmurs the harmony
  37-40  Build      organ toccata arpeggios climbing Db Eb C7sus4 C7, snare roll, riser
  41-48  Climax     theme x2: hero with the organ an octave below, HARM, brass stabs
  49-56  Inferno    double-time kit, harpsichord bariolage at full tilt; the hero holds
                    long burning lines above it and x climbs to the F6 peak
  57-64  Tag        x calls tossed between hero and harpsichord/organ (Db Eb), the wink,
                    then the C7 toccata run and toms hand back to the intro
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403
from engine import Note  # noqa: E402

U = 0.25
BAR = 4.0

# ---------------------------------------------------------------- theme ---
# The bible's theme +3 semitones (D minor -> F minor). Range C5-F6.
MOTIF = ("C5:3 C5:1 F5^:4 Ab5:3 G5:1 C6^:4 | "
         "Db6^:3 C6:1 Bb5:2 Ab5:2 G5:2 Ab5:1 G5:1 E5:2 C5:2")
ANSWER = ("Ab5:3 Ab5:1 Db6^:4 Bb5:3 Bb5:1 Eb6^:4 | "
          "F6^:3 Eb6:1 C6:2 G5:1 E5:1 F5:8")
HARM = ("Ab4:3 Ab4:1 C5:4 F5:3 F5:1 Ab5:4 | Bb5:3 Ab5:1 F5:2 F5:2 E5:4 C5:2 G4:2 | "
        "F5:3 F5:1 Ab5:4 G5:3 G5:1 Bb5:4 | C6:3 C6:1 Ab5:2 E5:1 C5:1 Ab4:8")
THEME_CHORDS = "Fm Bbm:0.5 C:0.5 Db:0.5 Eb:0.5 Fm"

# Verse: circle of fifths, x's rhythm and rising 4th at the head of each bar
VERSE = ("C5:3 C5:1 F5:4 Ab5:2 G5:2 F5:2 Eb5:2 | "                 # Fm
         "Db5:2 F5:2 Bb5:4 Ab5:1 Bb5:1 Ab5:1 G5:1 F5:2 Db5:2 | "    # Bbm
         "Bb4:3 Bb4:1 Eb5:4 G5:2 F5:2 Eb5:2 Db5:2 | "               # Eb
         "C5:2 Eb5:2 Ab5:4 G5:1 Ab5:1 G5:1 F5:1 Eb5:2 C5:2 | "      # Ab
         "Ab4:3 Ab4:1 Db5:4 F5:2 Ab5:2 Db6:2 C6:2 | "               # Db
         "Db6:3 C6:1 Bb5:2 Ab5:2 G5:2 Ab5:1 G5:1 E5:2 C5:2 | "      # Gm7b5 C7 (the wink)
         "C6:3 Bb5:1 Ab5:2 F5:2 Ab5:3 G5:1 F5:4 | "                 # Fm Db
         "E5:3 F5:1 G5:4 -:8")                                      # C7 (breath)
VERSE_CHORDS = "Fm Bbm Eb Ab Db Gm7b5:0.5 C7:0.5 Fm:0.5 Db:0.5 C7"

# Fugato: subject (motif) in F minor, answer at the dominant (C minor)
SUBJECT = MOTIF
ANSWER_DOM = ("G4:3 G4:1 C5^:4 Eb5:3 D5:1 G5^:4 | "
              "Ab5^:3 G5:1 F5:2 Eb5:2 D5:2 Eb5:1 D5:1 B4:2 G4:2")

# Calls (bars 17-20): hero x up the scale, harpsichord winks back (5 6 5 3 1)
CALLS = [("Eb5:3 Eb5:1 Ab5^:4", "Eb5:2 F5:1 Eb5:1 C5:2 Ab4:2"),      # Ab
         ("F5:3 F5:1 Bb5^:4", "F5:2 Gb5:1 F5:1 Db5:2 Bb4:2"),        # Bbm
         ("C5:3 C5:1 F5^:4", "G5:2 Ab5:1 G5:1 F5:2 C5:2")]          # C7sus4
STAB = "G5:3 G5:1 C6^:4"
RUN_DOWN = "E6:1 C6:1 Bb5:1 G5:1 E5:1 C5:1 Bb4:1 G4:1"              # C7, lands on the hook's C5

# Inferno (bars 49-56): long burning lines over the 16th storm; x climbs to F6
INFERNO = ("C6:6 Ab5:2 F5:4 C6:4 | "                                # Fm
           "Db6:6 C6:2 Ab5:4 F5:4 | "                               # Db
           "Bb5:6 Ab5:2 F5:4 Db6:4 | "                              # Bbm
           "C6:6 Bb5:2 G5:4 E5:4 | "                                # C7
           "C5:3 C5:1 F5^:4 Ab5:3 Ab5:1 C6^:4 | "                   # Fm  x climbs
           "Ab5:3 Ab5:1 Db6^:4 F6:4 Db6:4 | "                       # Db
           "F5:3 F5:1 Bb5^:4 G5:3 G5:1 C6^:4 | "                    # Bbm C7
           "F6^:6 Eb6:2 C6:4 Ab5:4")                                # Fm  peak
INFERNO_CHORDS = "Fm Db Bbm C7 Fm Db Bbm:0.5 C7:0.5 Fm"

# Tag (57-64)
TAG = ("Ab4:3 Ab4:1 Db5^:4 -:8 | "                                  # Db  call
       "Bb4:3 Bb4:1 Eb5^:4 -:8 | "                                  # Eb  call
       "Db6^:3 C6:1 Bb5:2 Ab5:2 G5:2 Ab5:1 G5:1 E5:2 C5:2 | "       # Bbm C  wink
       "F5:3 F5:1 C6^:4 Ab5:4 F5:4 | "                              # Fm
       "Ab5:3 Ab5:1 Db6^:4 -:8 | "                                  # Db  calls an octave up
       "Bb5:3 Bb5:1 Eb6^:4 -:8 | "                                  # Eb
       "Db6^:3 C6:1 Bb5:2 Ab5:2 G5:2 Ab5:1 G5:1 E5:2 C5:2 | "       # Bbm C7
       "-:16")                                                      # C7: the run
TAG_ANS = [(56, "Db5:2 Eb5:1 Db5:1 Ab4:2 F4:2"), (57, "Eb5:2 F5:1 Eb5:1 Bb4:2 G4:2"),
           (60, "Ab5:2 Bb5:1 Ab5:1 F5:2 Db5:2"), (61, "Bb5:2 C6:1 Bb5:1 G5:2 Eb5:2")]
TAG_CHORDS = "Db Eb Bbm:0.5 C:0.5 Fm Db Eb Bbm:0.5 C7:0.5 C7"

KEY_FM = [5, 7, 8, 10, 0, 1, 3]

# --------------------------------------------------------------- song ---
song = Song("music_library", bpm=168, bars=64, reverb_seconds=1.8)
song.loop(0)
for bar, text in [(0, "Fm Fm Db C7"), (4, VERSE_CHORDS),
                  (12, "Fm Bbm:0.5 C:0.5 Cm Fm:0.5 G:0.5"), (16, "Ab Bbm C7sus4 C7"),
                  (20, THEME_CHORDS), (24, THEME_CHORDS),
                  (28, "Fm Fm Bbm C Fm Fm Bbm C7"), (36, "Db Eb C7sus4 C7"),
                  (40, THEME_CHORDS), (44, THEME_CHORDS),
                  (48, INFERNO_CHORDS), (56, TAG_CHORDS)]:
    song.chords(bar, text)
for bar, lbl in [(0, "toccata"), (4, "verse"), (12, "fugato"), (16, "calls"), (20, "hook"),
                 (28, "pages (half time)"), (36, "build"), (40, "climax"), (48, "inferno"), (56, "tag")]:
    song.section(bar, lbl)


# --------------------------------------------------------------- helpers ---
def chords_in(b0, b1):
    return [(s, e, c) for (s, e, c) in song.harmony if b0 * BAR <= s < b1 * BAR]


def levels(tr, pts):
    """Step-wise section gain (dB): pts = [(bar, dB), ...] in order."""
    pts = list(pts) + [(song.bars, pts[-1][1])]
    for (b0, g), (b1, _) in zip(pts[:-1], pts[1:]):
        tr.automation.append((b0 * BAR, g))
        tr.automation.append((b1 * BAR - 0.02, g))


def voicing(c, lo=52, hi=67):
    """Close triad/7th inside [lo, hi]; drops a tone a semitone from another one."""
    root, iv, _ = parse_chord(c)
    pcs = sorted(chord_pcs(c))
    core = {root, (root + iv[1]) % 12, (root + 7) % 12} if len(iv) > 2 else set(pcs)
    pcs = [p for p in pcs if p in core or not ({(p + 1) % 12, (p - 1) % 12} & set(pcs))]
    out = []
    for p in pcs:
        m = lo + ((p - lo) % 12)
        if m > hi:
            m -= 12
        out.append(m)
    return sorted(out)


def scale_for(chord, key):
    sc = list(key)
    for p in chord_pcs(chord):
        if p not in sc:
            for want in (1, 11):
                hit = [i for i, s in enumerate(sc) if (p - s) % 12 == want]
                if hit:
                    sc[hit[0]] = p
                    break
    return set(sc)


def step_below(m, steps, sc):
    x = m
    k = 0
    while k < steps:
        x -= 1
        if x % 12 in sc:
            k += 1
    return x


def harmonize(src, b0, b1, dst, vel=0.85, octave=0):
    """Diatonic 3rds below `src` in bars [b0, b1); 6ths/4ths where a strong 3rd would
    be a non-chord tone."""
    prev = None
    mode = 2
    for n in sorted([x for x in src.notes if b0 * BAR <= x.beat < b1 * BAR], key=lambda x: x.beat):
        c = song.chord_at(n.beat)
        sc = scale_for(c, KEY_FM)
        cps = chord_pcs(c)
        m = int(n.m)
        strong = abs(n.beat % 1.0) < 1e-6 or n.beats >= 1.0
        if strong:
            cands = [(s, step_below(m, s, sc)) for s in (2, 5, 3)]
            good = [(s, x) for s, x in cands if x % 12 in cps and m - x != 6]
            if good:
                if prev is None:
                    s, x = good[0]
                else:
                    s, x = min(good, key=lambda sx: abs(sx[1] - prev) + {2: 0.0, 5: 1.5, 3: 3.5}[sx[0]])
            else:
                s, x = 2, step_below(m, 2, sc)
            mode = s
        else:
            x = step_below(m, mode if mode != 3 else 2, sc)
        dst.notes.append(Note(n.beat, float(x + octave), n.beats, n.vel * vel, n.slide))
        prev = x


# ----------------------------------------------------------- instruments ---
# Two-choir harpsichord: bright saw pair + 4' octave, plucked envelope, quill click via fenv.
HARPSI = Inst(osc="saw", unison=2, detune=7, spread=0.35, octave_layer=0.35, a=0.001, d=0.45, s=0.0, r=0.07,
              cutoff=3200, q=0.9, fenv=1.6, fdecay=0.035, key_track=0.5, gain=0.42)

lead = song.track("lead", lead_pulse(cutoff=8000), vol=-7.0, pan=0.0, reverb=0.15, delay=0.1, hp=180)
organ_ld = song.track("organ_lead", organ(vib_depth=0.08), vol=-12, pan=-0.2, reverb=0.3, delay=0.08, hp=200)
harpsi = song.track("harpsi", HARPSI, vol=-11.5, pan=0.32, reverb=0.25, delay=0.08, hp=300, duck=0.15)
harpsi_ld = song.track("harpsi_lead", HARPSI, vol=-9, pan=0.2, reverb=0.22, delay=0.1, hp=250)
counter = song.track("counter", lead_fm(), vol=-11, pan=-0.25, reverb=0.15, hp=180)
bell_t = song.track("bell", bell(), vol=-11, pan=-0.3, reverb=0.35, delay=0.2, hp=300)
brass_t = song.track("brass", brass(), vol=-12.5, pan=-0.2, reverb=0.2, hp=150)
org_pad = song.track("organ_pad", organ(vib_depth=0.03, a=0.06, r=0.25), vol=-20, reverb=0.45, duck=0.35, hp=200)
pad = song.track("pad", strings(), vol=-11, reverb=0.45, duck=0.35, hp=200)
bass = song.track("bass", bass_fm(sub=0.12), vol=-7.3, duck=0.3, hp=32)
dr = song.drums("drums", vol=-7.2, reverb=0.1)
embers = song.drums("embers", vol=-17, reverb=0.3)

# dynamics: verse under the hook, pages well under, climax and inferno on top
levels(dr, [(0, -1.0), (4, -2.0), (8, -1.5), (12, -1.5), (20, 0), (28, -4.0), (36, -1.0), (40, 0.5),
            (48, 0.5), (56, 0)])
levels(bass, [(0, -0.5), (4, -2.0), (12, -1.0), (20, 0), (28, -3.0), (36, -0.5), (40, 0.5), (56, 0)])
levels(lead, [(0, 0), (4, -1.0), (16, 0), (40, 0.3), (48, -0.5), (56, 0)])
levels(harpsi, [(0, 1.5), (4, 0), (12, 1.0), (20, 0), (28, 1.0), (36, 0), (48, 2.0), (56, 0)])

# ---------------------------------------------------------------- melody ---
lead.seq(4, VERSE, unit=U)
harmonize(lead, 8, 11, organ_ld, vel=0.75)

# fugato: harpsichord subject, organ answer at the dominant
harpsi_ld.seq(12, SUBJECT, unit=U, vel=0.9)
organ_ld.seq(14, ANSWER_DOM, unit=U, vel=0.85)

# calls: hero x up the scale, harpsichord winks back; band stab; toccata run
for i, (call, wink) in enumerate(CALLS):
    lead.seq(16 + i, call, unit=U)
    harpsi_ld.seq(16 + i, wink, unit=U, at=2.0, vel=0.85)
harmonize(lead, 16, 19, organ_ld, vel=0.7)
lead.seq(19, STAB, unit=U)
organ_ld.seq(19, "E5:3 E5:1 G5:4", unit=U, vel=0.8)
harpsi_ld.seq(19, RUN_DOWN, unit=U, at=2.0, vel=0.9)
organ_ld.seq(19, RUN_DOWN, unit=U, at=2.0, transpose=-12, vel=0.7)

# hook: theme x2, HARM on the FM counter the second time
for b in (20, 24):
    lead.seq(b, MOTIF + " | " + ANSWER, unit=U)
counter.seq(24, HARM, unit=U)

# pages: organ sings the motif in augmentation (2x), bell doubles the 2nd pass an
# octave up and the hero murmurs HARM's first half in augmentation underneath
organ_ld.seq(28, MOTIF, unit=0.5, vel=0.8)
organ_ld.seq(32, MOTIF, unit=0.5, vel=0.8)
bell_t.seq(32, MOTIF, unit=0.5, transpose=12, vel=0.45)
lead.seq(32, "Ab4:3 Ab4:1 C5:4 F5:3 F5:1 Ab5:4 | Bb5:3 Ab5:1 F5:2 F5:2 E5:4 C5:2 G4:2", unit=0.5, vel=0.55)

# climax: theme x2, hero + organ an octave below, HARM on the counter both times
for b in (40, 44):
    lead.seq(b, MOTIF + " | " + ANSWER, unit=U)
    organ_ld.seq(b, MOTIF + " | " + ANSWER, unit=U, transpose=-12, vel=0.7)
    counter.seq(b, HARM, unit=U, vel=0.9)

# inferno
lead.seq(48, INFERNO, unit=U)
harmonize(lead, 52, 56, organ_ld, vel=0.7)

# tag
lead.seq(56, TAG, unit=U)
for bar, w in TAG_ANS:
    (harpsi_ld if bar < 60 else organ_ld).seq(bar, w, unit=U, at=2.0, vel=0.85)
harpsi_ld.seq(63, RUN_DOWN, unit=U, at=2.0, vel=0.9)
organ_ld.seq(63, "C5:3 C5:1 E5:4", unit=U, vel=0.75)

# ----------------------------------------------------------- harpsichord ---
# intro / turnaround bariolage: the top note is a ringing pedal between chord tones
BARIO = "0 3 2 3 1 3 2 3"
ALBERTI = "0 2 1 2"
RISING = "0 1 2 3 4 5 4 3"
for b0, b1, c in chords_in(0, 4):
    harpsi.arp(b0 / BAR, voicing(c, 60, 72), BARIO, unit=U, beats=b1 - b0, vel=0.8)
for b0, b1, c in chords_in(4, 12):
    harpsi.arp(b0 / BAR, voicing(c, 53, 66), ALBERTI, unit=U, beats=b1 - b0, vel=0.7)
for b0, b1, c in chords_in(14, 16):   # countersubject under the organ answer
    harpsi.arp(b0 / BAR, voicing(c, 60, 72), "0 1 2 3 2 1 0 1", unit=U, beats=b1 - b0, vel=0.7)
for b0, b1, c in chords_in(20, 28):
    harpsi.arp(b0 / BAR, voicing(c, 53, 66), "0 1 2 3 2 1", unit=U, beats=b1 - b0, vel=0.6)
for b0, b1, c in chords_in(28, 36):   # page flutter
    harpsi.arp(b0 / BAR, voicing(c, 53, 65), "0 1 2 1", unit=U, beats=b1 - b0, vel=0.45)
for b0, b1, c in chords_in(36, 40):   # build: climbing
    harpsi.arp(b0 / BAR, voicing(c, 53, 65), RISING, unit=U, beats=b1 - b0, vel=0.75)
for b0, b1, c in chords_in(40, 48):
    harpsi.arp(b0 / BAR, voicing(c, 53, 66), "0 1 2 3 2 1", unit=U, beats=b1 - b0, vel=0.6)
for b0, b1, c in chords_in(48, 56):   # inferno: bariolage storm
    harpsi.arp(b0 / BAR, voicing(c, 55, 68), BARIO, unit=U, beats=b1 - b0, vel=0.85)
for b0, b1, c in chords_in(58, 60):
    harpsi.arp(b0 / BAR, voicing(c, 53, 66), ALBERTI, unit=U, beats=b1 - b0, vel=0.6)
for b0, b1, c in chords_in(62, 63):
    harpsi.arp(b0 / BAR, voicing(c, 53, 66), ALBERTI, unit=U, beats=b1 - b0, vel=0.6)
# intro bar 4: the toccata run (C7, harmonic minor) on harpsichord + organ
harpsi_ld.seq(3, "C6:1 Bb5:1 G5:1 E5:1 Db5:1 C5:1 Bb4:1 G4:1 E4:1 G4:1 Bb4:1 C5:1 E5:2 G4:2", unit=U, vel=0.8)

# --------------------------------------------------------------- organ ---
# x stabs in the toccata (like a chapel organ: C C F, then the Db colour)
organ_ld.seq(0, "C5:3 C5:1 F5^:4 -:8", unit=U, vel=0.85)
organ_ld.seq(2, "Ab4:3 Ab4:1 Db5^:4 -:8", unit=U, vel=0.85)   # the Db colour
# build: toccata arpeggios climbing on the organ
for b0, b1, c in chords_in(36, 40):
    organ_ld.arp(b0 / BAR, voicing(c, 60, 72), "0 1 2 3 4 5 6 5", unit=U, beats=b1 - b0, vel=0.55)

# ----------------------------------------------------------------- brass ---
def power(root, octv):
    r = midi(f"{root}{octv}")
    return [r, r + 7, r + 12]


def stab_x(bar, half, notes, vel=0.85):
    b0 = bar * BAR + half * 2.0
    for off, ln, v in ((0.0, 0.5, vel), (0.75, 0.2, vel * 0.8), (1.0, 0.8, min(1.0, vel * 1.15))):
        for m in notes:
            brass_t.note(b0 + off, m, ln, v)


stab_x(0, 0, power("F", 3), 0.8)
stab_x(2, 0, power("Db", 3), 0.8)
stab_x(19, 0, power("C", 3), 0.95)
stab_x(39, 0, power("C", 3), 0.9)
stab_x(39, 1, power("C", 3), 0.95)


def stabs(bar0, bar1, vel=0.7, length=0.45):
    for s, e, c in chords_in(bar0, bar1):
        root = parse_chord(c)[0]
        o = 2 if root >= 9 else 3
        brass_t.chord(s / BAR, power(NOTE_NAMES[root], o), beats=length, vel=vel)


stabs(40, 48, 0.7)
stabs(48, 56, 0.6)

# ------------------------------------------------------------------ bell ---
for bar, a, b in ((44, "F6", "C7"), (46, "Db7", "Eb7")):
    bell_t.note(bar * BAR + 1.0, a, 1.0, 0.35)
    bell_t.note(bar * BAR + 3.0, b, 1.0, 0.35)

# ------------------------------------------------------------------ bass ---
CEIL = midi("Eb3")


def oct8(root, n=8, lo_first=True):
    """8th-note octave bass (baroque 'drum bass'): root and the octave above."""
    r = midi(root)
    up = r + 12 if r + 12 <= CEIL else r - 12
    seq = [r, up] if lo_first else [up, r]
    return " ".join(name_of(seq[i % 2]) for i in range(n))


def drive16(root, end=None):
    """16ths: r r o r | r r o r | r r o r | r o (end)."""
    r = midi(root)
    o = r + 12 if r + 12 <= CEIL else r - 12
    cells = [r, r, o, r] * 4
    if end:
        cells[-2:] = [midi(x) for x in end]
    for m in cells:
        assert m <= CEIL
    return " ".join(name_of(m) for m in cells)


ROOT = {"Fm": "F1", "Bbm": "Bb1", "Eb": "Eb2", "Ab": "Ab1", "Db": "Db2", "Gm7b5": "G1", "C7": "C2",
        "C": "C2", "Cm": "C2", "G": "G1", "C7sus4": "C2"}


def bass_bars(b0, b1, style):
    for s, e, c in chords_in(b0, b1):
        beats = e - s
        if style == "oct8":
            bass.seq(s / BAR, oct8(ROOT[c], int(beats * 2)), unit=0.5)
        elif style == "drive":
            n = int(beats * 4)
            r = midi(ROOT[c])
            o = r + 12 if r + 12 <= CEIL else r - 12
            bass.seq(s / BAR, " ".join(name_of([r, r, o, r][i % 4]) for i in range(n)), unit=U)
        elif style == "half":
            r = midi(ROOT[c])
            bass.note(s, r, 1.9, 0.9)
            bass.note(s + 2.0, r + 12 if r + 12 <= CEIL else r, 0.9, 0.6)
            bass.note(s + 3.0, r, 0.9, 0.7)


# intro: 8th octaves, the C7 bar walks up chromatically to F
bass.seq(0, oct8("F1") + " | " + oct8("F1"), unit=0.5)
bass.seq(2, oct8("Db2"), unit=0.5)
bass.seq(3, "C2 C3 C2 C3 C2 Db2 D2 E2", unit=0.5)
bass_bars(4, 12, "oct8")
bass_bars(12, 16, "oct8")
bass_bars(16, 19, "drive")
bass.seq(19, "C2:3 C2:1 C3:4 C2:2 C2:2 Bb1:2 G1:2", unit=U)
THEME_BASS = ("F1 F2 F1 F2 F1 F2 Eb2 C2 | Bb1 Bb2 Bb1 Bb2 C2 C3 C2 C3 | "
              "Db2 Db3 Ab1 Db2 Eb2 Eb3 Bb1 G1 | F1 F2 Ab1 F2 F1 F2 C2 E2")
bass.seq(20, THEME_BASS, unit=0.5)
bass.seq(24, THEME_BASS, unit=0.5)
bass_bars(28, 36, "half")
bass_bars(36, 38, "oct8")
bass.seq(38, drive16("C2") + " | " + drive16("C2", end=("D2", "E2")), unit=U)
for b in (40, 44):   # climax: the theme bass in driving 16ths
    bass.seq(b, " | ".join([
        drive16("F1"),
        "Bb1 Bb1 Bb2 Bb1 Bb1 Bb1 Bb2 Bb1 C2 C2 C3 C2 C2 C2 C3 C2",
        "Db2 Db2 Db3 Db2 Db2 Db2 Db3 Db2 Eb2 Eb2 Eb3 Eb2 Eb2 Eb2 D2 Eb2",
        drive16("F1", end=("C2", "E2")),
    ]), unit=U)
for s, e, c in chords_in(48, 56):     # inferno: driving 16ths
    r = midi(ROOT[c])
    o = r + 12 if r + 12 <= CEIL else r - 12
    n = int((e - s) * 4)
    bass.seq(s / BAR, " ".join(name_of([r, r, o, r][i % 4]) for i in range(n)), unit=U)
bass_bars(56, 63, "oct8")
bass.seq(63, "C2:2 C3:2 C2:2 C3:2 C2:1 C2:1 Db2:1 D2:1 Eb2:1 E2:1 -:2", unit=U)

# harmony notes that would rub a semitone against the bass are dropped
def drop_clashes(tr, against):
    keep = []
    for n in tr.notes:
        bad = any(o.beat < n.beat + n.beats and n.beat < o.beat + o.beats
                  and min(n.beat + n.beats, o.beat + o.beats) - max(n.beat, o.beat) >= 0.5
                  and abs(int(n.m) - int(o.m)) % 12 in (1, 11) and abs(int(n.m) - int(o.m)) < 24
                  for t in against for o in t.notes)
        if not bad:
            keep.append(n)
    tr.notes[:] = keep


drop_clashes(organ_ld, [bass])

# ----------------------------------------------------------------- pads ---
melodic = [lead, organ_ld, harpsi_ld, counter, bell_t, brass_t, bass]


def place_pad(tr, b0, b1, c, vel, lo=53, hi=67):
    for p in voicing(c, lo, hi):
        ok = True
        for t in melodic:
            for n in t.notes:
                if n.beats < 0.5 or n.beat >= b1 or n.beat + n.beats <= b0:
                    continue
                iv = abs(int(n.m) - p)
                if iv % 12 in (1, 11) and iv < 24:
                    ok = False
                    break
            if not ok:
                break
        if ok:
            tr.note(b0, p, b1 - b0 - 0.08, vel)


for s0, s1, v in [(0, 4, 0.5), (4, 12, 0.55), (12, 20, 0.6), (20, 28, 0.55), (28, 36, 0.7),
                  (36, 40, 0.6), (40, 56, 0.6), (56, 64, 0.55)]:
    for b0, b1, c in chords_in(s0, s1):
        place_pad(org_pad, b0, b1, c, v)
for s0, s1 in [(24, 28), (40, 48)]:
    for b0, b1, c in chords_in(s0, s1):
        place_pad(pad, b0, b1, c, 0.6)

# ---------------------------------------------------------------- drums ---
K_DRIVE = "x.....x.x.....x."
K_FOUR = "x...x...x...x..."
K_INF = "x.x.x.x.x.x.x.x."
SN = "....x.......x..."
HAT16 = "xoxoxoxoxoxoxoxo"
HAT8 = "x.x.x.x.x.x.x.x."
OHAT = "..x...x...x...x."
OHAT_UP = "..X...X...X...X."


def groove(bar, n=1, kick=K_DRIVE, hat=HAT16, ohat=None, clap=False, snare=SN, ride=None):
    v = {"kick": kick, "snare": snare, "hat": hat}
    if ohat:
        v["ohat"] = ohat
    if clap:
        v["clap"] = SN
    if ride:
        v["ride"] = ride
    dr.pat(bar, v, bars=n)


def small_fill(bar):
    dr.fill(bar, "snare_ snare tom_hi tom_lo", at=3.0)


# toccata intro: four on the floor + 16th hats, toms on the C7 run
dr.pat(0, {"kick": K_FOUR, "hat": HAT16, "snare": "............x..."}, bars=3)
dr.hit(0, "crash", 0.85)
dr.pat(3, {"kick": "x.......x.......", "hat": HAT8})
dr.fill(3, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare snare", at=2.0)
# verse
groove(4, 3, hat=HAT8)
groove(7, 1, hat=HAT8)
small_fill(7)
groove(8, 3, hat=HAT16)
groove(11, 1, hat=HAT16, snare="....x.......x.xx")
for b in (4, 8):
    dr.hit(b * BAR, "crash", 0.75)
# fugato: lighter (ride + rim feel), kick drive
for b in range(12, 16):
    dr.pat(b, {"kick": "x.......x.x.....", "snare": SN, "ride": "x.x.x.x.x.x.x.x.", "hat": "..o...o...o...o."})
dr.hit(12 * BAR, "crash", 0.7)
small_fill(15)
# calls: four on the floor, ohats, stop-time on the stab
groove(16, 3, kick=K_FOUR, hat=HAT16, ohat=OHAT)
dr.hit(16 * BAR, "crash", 0.75)
for off in (0.0, 0.75, 1.0):
    dr.hit(19 * BAR + off, "kick", 1.0)
    dr.hit(19 * BAR + off, "snare", 0.8 if off else 0.6)
dr.hit(19 * BAR, "crash", 0.9)
dr.fill(19, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=2.0)
# hook
groove(20, 3, ohat=OHAT_UP)
groove(23, 1, ohat=OHAT_UP)
small_fill(23)
groove(24, 3, ohat=OHAT_UP, clap=True)
groove(27, 1, ohat=OHAT_UP, clap=True)
dr.fill(27, "snare snare_ snare snare tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=1.0)
for b in (20, 24):
    dr.hit(b * BAR, "crash", 0.9)
# pages: half time, shaker flutter
dr.pat(28, {"kick": "x.........x.....", "snare": "........x.......", "shaker": "xoxoxoxoxoxoxoxo"}, bars=4)
dr.pat(32, {"kick": "x.........x.....", "snare": "........x.......", "shaker": "xoxoxoxoxoxoxoxo",
            "hat": "..o...o...o...o."}, bars=3)
dr.pat(35, {"kick": "x.........x.....", "snare": "........x.x.xxxx", "shaker": "xoxoxoxoxoxoxoxo"})
dr.hit(28 * BAR, "crash", 0.6)
# build: snare 8ths then 16ths, riser
dr.pat(36, {"kick": K_FOUR, "snare": "x.x.x.x.x.x.x.x.", "hat": HAT8}, bars=2)
dr.pat(38, {"kick": K_FOUR, "snare": "xxxxxxxxxxxxxxxx", "hat": HAT8})
dr.pat(39, {"kick": "x..xx...........", "snare": "x..xx..........."})
dr.hit(36 * BAR, "crash", 0.7)
dr.hit(39 * BAR, "crash", 0.85)
dr.hit(40 * BAR - 2.0 * 168 / 60, "riser", 0.9)
dr.fill(39, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=2.0)
# climax
groove(40, 3, ohat=OHAT_UP, clap=True)
groove(43, 1, ohat=OHAT_UP, clap=True)
small_fill(43)
groove(44, 3, ohat=OHAT_UP, clap=True)
groove(47, 1, ohat=OHAT_UP, clap=True)
dr.fill(47, "snare snare snare snare tom_hi tom_mid tom_lo snare^", at=2.0)
for b in (40, 44):
    dr.hit(b * BAR, "crash", 0.9)
# inferno: 8th kicks, 16th hats, ride bell on the beats
for b in range(48, 56):
    groove(b, 1, kick=K_INF, ohat=OHAT, clap=True, ride="x...x...x...x...")
small_fill(51)
dr.fill(55, "snare snare snare snare tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=1.0)
for b in (48, 52):
    dr.hit(b * BAR, "crash", 0.9)
# tag
groove(56, 3, ohat=OHAT)
groove(59, 1, ohat=OHAT)
small_fill(59)
groove(60, 3, ohat=OHAT)
dr.hit(56 * BAR, "crash", 0.85)
dr.hit(60 * BAR, "crash", 0.75)
dr.pat(63, {"kick": "x.......x.......", "hat": "x.x.x.x........."})
dr.fill(63, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ -", at=2.0)

# embers: sparse, seeded crackle (short chip-noise ticks) under the quiet parts
rng = np.random.default_rng(1666)
for s0, s1, dens in [(0, 4, 0.12), (28, 36, 0.22), (60, 64, 0.08)]:
    for step in range(int(s0 * 16), int(s1 * 16)):
        if rng.random() < dens:
            embers.hit(step * U + rng.uniform(0, 0.12), "hat_chip", float(rng.uniform(0.25, 0.7)))

if __name__ == "__main__":
    song.render()

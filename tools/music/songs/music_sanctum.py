"""Magic Smash - ACT III: THE STARLESS SANCTUM (minutes 10-15).

B minor, 150 bpm, 60 bars = 96 s, loop(0).  The grandest of the battle loops: stained
glass, black marble, the black comet overhead and Morvane ascending.  It sits a half
step under the boss key (C minor), and its last bars actually slide up into C minor
and hand the Lich's own tritone call to the brass: the run is being pulled toward
the Archlich.  (Key plan of a run: E minor -> F minor -> B minor -> C minor; Act II
to Act III is a tritone, the Lich's interval.)

Colour: church organ, a formant choir (sustained "ah"/"oo" pads and a staccato
choir that chants the x rhythm), tolling FM bells, timpani, gong, harp "stained glass"
ripples and O Fortuna style pumping string 8ths that keep the battle energy under
the slow augmented theme.  The hero pulse plays every first statement.

Form (bars, 1-based)
  1-4    Vigil       bell tolls, organ pedal, choir "oo", heartbeat kick; the choir chants
                     x (Ma-gic SMASH) on F#7, snare swell
  5-12   Procession  the theme in AUGMENTATION (unit 1/8, 8 bars) on the hero, the organ an
                     octave below; pumping strings, processional half-time kit -> backbeat
  13-20  Hymn        a stained-glass chorale in D major built from x (rising 4ths), harp
                     ripples, brass in 3rds, bell on the landings
  21-28  Hook        the theme at written speed x2; 2nd time brass HARM + choir chant
  29-32  Eclipse     lament bass B A# A G# G F#, drums drop to toms/timpani, the bell
                     tolls x inverted, choir "oo"
  33-40  Ascending   the hero's x (rising 4th) and Morvane's x (tritone, brass + organ +
                     staccato choir) fight bar by bar, climbing to the Neapolitan C and the
                     wink; snare roll and riser
  41-48  Ascension   the augmented theme on choir + organ + brass (octave below), gong, a
                     bell toll every bar; the hero soars a descant of x cells above it
  49-52  Black comet the theme at speed with the Neapolitan (C) in place of iv
  53-56  The pull    the whole band slips a half step into C MINOR (the boss key) for the theme
  57-60  Turnaround  brass + organ state Morvane's call (G G Db over Gdim/Db - the boss
                     motif), G7 (German 6th of B minor), the hero's x slides down to F#7,
                     tolls and toms hand back to the vigil
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403
from engine import Note  # noqa: E402

U = 0.25
BAR = 4.0

# ---------------------------------------------------------------- theme ---
# The bible's theme -3 semitones (D minor -> B minor). Range F#4-B5.
MOTIF = ("F#4:3 F#4:1 B4^:4 D5:3 C#5:1 F#5^:4 | "
         "G5^:3 F#5:1 E5:2 D5:2 C#5:2 D5:1 C#5:1 A#4:2 F#4:2")
ANSWER = ("D5:3 D5:1 G5^:4 E5:3 E5:1 A5^:4 | "
          "B5^:3 A5:1 F#5:2 C#5:1 A#4:1 B4:8")
THEME = MOTIF + " | " + ANSWER
HARM = ("D4:3 D4:1 F#4:4 B4:3 B4:1 D5:4 | E5:3 D5:1 B4:2 B4:2 A#4:4 F#4:2 C#4:2 | "
        "B4:3 B4:1 D5:4 C#5:3 C#5:1 E5:4 | F#5:3 F#5:1 D5:2 A#4:1 F#4:1 D4:8")
THEME_CHORDS = "Bm Em:0.5 F#:0.5 G:0.5 A:0.5 Bm"
AUG_CHORDS = "Bm Bm Em7 F# G A Bm:0.75 F#:0.25 Bm"

# Hymn (bars 13-20): chorale in D major, x's rising 4th at the head of each phrase
HYMN = ("A4:3 A4:1 D5^:4 F#5:4 A5:4 | "         # D
        "A5:6 G5:2 E5:4 C#5:4 | "               # A
        "D5:3 D5:1 F#5^:4 B5:6 A5:2 | "         # Bm
        "A5:4 F#5:4 C#5:8 | "                   # F#m
        "D5:3 D5:1 G5^:4 B5:4 D6:4 | "          # G
        "D6^:6 C#6:2 A5:4 F#5:4 | "             # D
        "G5:6 F#5:2 E5:4 B4:4 | "               # Em
        "C#5:3 D5:1 E5:4 C#5:4 A#4:4")          # F#7
HYMN_CHORDS = "D A Bm F#m G D Em F#7"

# Ascending (33-40): hero x (rising 4th) vs Morvane's x (tritone)
HERO_X = {32: "F#4:3 F#4:1 B4^:4 D5:3 C#5:1 F#5^:4",            # Bm
          34: "B4:3 B4:1 E5^:4 G5:3 F#5:1 B5^:4",               # Em
          36: "D5:3 D5:1 G5^:4 E5:3 E5:1 A5^:4",                # G A
          38: "B5^:3 A5:1 G5:2 E5:2 C#5:2 D5:1 C#5:1 A#4:2 F#4:2",   # Em F#: the wink
          39: "C#5:3 C#5:1 F#5^:4 -:8"}                         # F#7
LICH_X = {33: "F#4:3 F#4:1 C5^:4 D5:3 D5:1 F#5^:4",             # F#dim/C Bm
          35: "B4:3 B4:1 F5^:4 G5:3 G5:1 B5^:4",                # Bdim/F Em
          37: "C5:3 C5:1 F#5^:4 G5:3 G5:1 C6^:4"}               # F#dim/C C (Neapolitan)

# Ascension (41-48): hero descant above the augmented theme
DESCANT = ("D5:3 D5:1 F#5^:4 B5:3 A5:1 F#5:4 | "      # Bm
           "F#5:3 F#5:1 B5^:4 D6:3 C#6:1 B5:4 | "     # Bm
           "B5:3 B5:1 E6^:4 G5:4 B5:4 | "             # Em7
           "A#5:4 F#5:4 C#6^:4 A#5:4 | "              # F#
           "B5:3 B5:1 D6^:4 G5:3 A5:1 B5:4 | "        # G
           "C#6:3 C#6:1 E6^:4 A5:3 B5:1 C#6:4 | "     # A
           "D6^:3 C#6:1 B5:4 D6:4 C#6:2 A#5:2 | "     # Bm F#
           "B5:4 F#5:2 B5:2 D6:8")                    # Bm

# The pull (53-56): the hero's theme in C minor (bible -2), Neapolitan Db in bar 2
THEME_CM = ("G4:3 G4:1 C5^:4 Eb5:3 D5:1 G5^:4 | "
            "Ab5^:3 G5:1 F5:2 Eb5:2 D5:2 Eb5:1 D5:1 B4:2 G4:2 | "
            "Eb5:3 Eb5:1 Ab5^:4 F5:3 F5:1 Bb5^:4 | "
            "C6^:3 Bb5:1 G5:2 D5:1 B4:1 C5:8")

# --------------------------------------------------------------- song ---
song = Song("music_sanctum", bpm=150, bars=60, reverb_seconds=2.4)
song.loop(0)
for bar, text in [(0, "Bm Bm G F#7"), (4, AUG_CHORDS), (12, HYMN_CHORDS),
                  (20, THEME_CHORDS), (24, THEME_CHORDS),
                  (28, "Bm:0.5 Bm/A#:0.5 Bm/A:0.5 G#m7b5:0.5 G:0.5 Em/G:0.5 F#7"),
                  (32, "Bm F#dim/C:0.5 Bm:0.5 Em Bdim/F:0.5 Em:0.5 G:0.5 A:0.5 F#dim/C:0.5 C:0.5 "
                       "Em:0.5 F#:0.5 F#7"),
                  (40, AUG_CHORDS),
                  (48, "Bm C:0.5 F#:0.5 G:0.5 A:0.5 Bm"),
                  (52, "Cm Db:0.5 G:0.5 Ab:0.5 Bb:0.5 Cm"),
                  (56, "Gdim/Db:0.5 Cm:0.5 G7 F#7 F#7")]:
    song.chords(bar, text)
for bar, lbl in [(0, "vigil"), (4, "procession (augmented)"), (12, "hymn"), (20, "hook"), (28, "eclipse"),
                 (32, "ascending (hero vs lich)"), (40, "ascension"), (48, "black comet"),
                 (52, "the pull (C minor)"), (56, "turnaround")]:
    song.section(bar, lbl)

KEY_BM = [11, 1, 2, 4, 6, 7, 9]


# --------------------------------------------------------------- helpers ---
def chords_in(b0, b1):
    return [(s, e, c) for (s, e, c) in song.harmony if b0 * BAR <= s < b1 * BAR]


def levels(tr, pts):
    pts = list(pts) + [(song.bars, pts[-1][1])]
    for (b0, g), (b1, _) in zip(pts[:-1], pts[1:]):
        tr.automation.append((b0 * BAR, g))
        tr.automation.append((b1 * BAR - 0.02, g))


def voicing(c, lo=50, hi=64):
    """Close voicing inside [lo, hi]; drops a tone a semitone from another one."""
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
    return sorted(set(out))


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


def harmonize(src, b0, b1, dst, vel=0.85, octave=0, key=KEY_BM):
    """Diatonic 3rds below `src` in bars [b0, b1); 6ths/4ths where a strong 3rd would clash."""
    prev = None
    mode = 2
    for n in sorted([x for x in src.notes if b0 * BAR <= x.beat < b1 * BAR], key=lambda x: x.beat):
        c = song.chord_at(n.beat)
        sc = scale_for(c, key)
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


def drop_clashes(tr, against):
    """Drop notes of `tr` that would rub a semitone (or maj 7th) against `against` for >= 1/2 beat."""
    keep = []
    for n in tr.notes:
        bad = any(o is not n and o.beat < n.beat + n.beats and n.beat < o.beat + o.beats
                  and min(n.beat + n.beats, o.beat + o.beats) - max(n.beat, o.beat) >= 0.5
                  and abs(int(n.m) - int(o.m)) % 12 in (1, 11) and abs(int(n.m) - int(o.m)) < 24
                  for t in against for o in t.notes)
        if not bad:
            keep.append(n)
    tr.notes[:] = keep


# ----------------------------------------------------------- instruments ---
TOLL = bell(fm_ratio=2.76, fm_index=3.2, fm_decay=0.5, fm_sustain=0.12, d=3.2, r=2.0, gain=0.5)
STAC = strings(a=0.006, d=0.12, s=0.35, r=0.09, cutoff=3000, vib_depth=0.0, gain=0.4)
CHANT = choir("ah", a=0.02, d=0.25, s=0.75, r=0.22, vib_depth=0.05)

lead = song.track("lead", lead_pulse(cutoff=8000), vol=-7.0, pan=0.0, reverb=0.18, delay=0.1, hp=180)
organ_ld = song.track("organ_lead", organ(vib_depth=0.06), vol=-12, pan=-0.15, reverb=0.4, delay=0.08, hp=160)
brass_t = song.track("brass", brass(), vol=-13, pan=-0.2, reverb=0.25, hp=150)
choir_ld = song.track("choir_lead", choir("ah"), vol=-13, pan=0.1, reverb=0.5, hp=200)
chant = song.track("chant", CHANT, vol=-14, pan=0.12, reverb=0.4, hp=200)
toll = song.track("toll", TOLL, vol=-12, pan=-0.3, reverb=0.5, delay=0.12, hp=120)
bell_t = song.track("bell", bell(), vol=-12, pan=-0.3, reverb=0.4, delay=0.2, hp=300)
harp_t = song.track("harp", harp(r=0.5), vol=-6.5, pan=0.38, reverb=0.4, delay=0.12, hp=250)
stac = song.track("strings_stac", STAC, vol=-10, pan=0.25, reverb=0.25, duck=0.25, hp=200)
choir_pad = song.track("choir", choir("ah"), vol=-19, reverb=0.5, duck=0.35, hp=200)
choir_oo = song.track("choir_oo", choir("oo"), vol=-17, reverb=0.55, hp=200)
org_pad = song.track("organ_pad", organ(vib_depth=0.03, a=0.08, r=0.3), vol=-19, reverb=0.45, duck=0.35, hp=110)
bass = song.track("bass", bass_pulse(sub=0.3), vol=-9, duck=0.3, hp=32)
dr = song.drums("drums", vol=-7.5, reverb=0.12)
fx = song.drums("fx", vol=-11, reverb=0.3)

levels(dr, [(0, -3.5), (4, -2.0), (8, -1.0), (12, -0.5), (20, 0), (28, -4.0), (32, -1.5), (36, -0.5),
            (40, 0.5), (48, 0.5), (56, -1.0)])
levels(bass, [(0, -2.0), (4, -1.0), (12, -0.5), (20, 0), (28, -2.5), (32, -0.5), (40, 0.5), (56, 0)])
levels(lead, [(0, 0), (4, 0.5), (12, -0.5), (20, 0), (40, -0.5), (48, 0.3), (56, 0)])

# ---------------------------------------------------------------- melody ---
# procession: the augmented theme, hero + organ an octave below
lead.seq(4, THEME, unit=0.5)
organ_ld.seq(4, THEME, unit=0.5, transpose=-12, vel=0.75)
# hymn
lead.seq(12, HYMN, unit=U)
harmonize(lead, 16, 20, brass_t, vel=0.85, key=[2, 4, 6, 7, 9, 11, 1])
# hook x2
for b in (20, 24):
    lead.seq(b, THEME, unit=U)
brass_t.seq(24, HARM, unit=U, vel=0.95)
# eclipse: the bell tolls x inverted (falls a 5th) over the lament bass
bell_t.seq(28, "B5:6 B5:2 F#5:8 | E5:6 D5:2 G#4:8 | D5:6 D5:2 B4:8 | C#5:6 E5:2 A#4:8", unit=U, vel=0.8)
organ_ld.seq(28, "B4:8 A#4:8 | A4:8 G#4:8 | G4:8 G4:8 | F#4:16", unit=U, vel=0.6)
# ascending: hero x vs Morvane's x
for bar, txt in HERO_X.items():
    lead.seq(bar, txt, unit=U)
for bar, txt in LICH_X.items():
    brass_t.seq(bar, txt, unit=U, transpose=-12, vel=0.95)
    organ_ld.seq(bar, txt, unit=U, vel=0.85)
harmonize(lead, 38, 40, organ_ld, vel=0.7)
# ascension: augmented theme on choir + organ, brass an octave below; hero descant
choir_ld.seq(40, THEME, unit=0.5, vel=0.8)
organ_ld.seq(40, THEME, unit=0.5, vel=0.7)
brass_t.seq(40, THEME, unit=0.5, transpose=-12, vel=0.8)
lead.seq(40, DESCANT, unit=U)
# black comet: the theme at speed, Neapolitan C in bar 2
lead.seq(48, THEME, unit=U)
brass_t.seq(48, HARM.replace("B4:2 B4:2 A#4:4", "C5:2 B4:2 A#4:4", 1), unit=U, vel=0.9)
# the pull: C minor
lead.seq(52, THEME_CM, unit=U)
organ_ld.seq(52, THEME_CM, unit=U, transpose=-12, vel=0.65)
# turnaround: Morvane's call, the hero's x slides down a half step
brass_t.seq(56, "G3:3 G3:1 Db4^:4 Eb4:3 Eb4:1 G4^:4", unit=U, vel=1.0)
organ_ld.seq(56, "G4:3 G4:1 Db5^:4 Eb5:3 Eb5:1 G5^:4", unit=U, vel=0.9)
lead.seq(57, "D5:3 D5:1 G5^:4 F5:4 D5:4 | C#5:3 C#5:1 F#5^:4 E5:4 C#5:4 | A#4:8 -:8", unit=U)
bell_t.seq(59, "F#5:2 G5:1 F#5:1 E5:2 C#5:2 A#4:2 F#4:2 -:4", unit=U, vel=0.7)

# --------------------------------------------------------- staccato choir ---
def chant_x(bar, half, notes, vel=0.8):
    """The choir chants 'Ma-gic SMASH' (x rhythm) on a chord."""
    b0 = bar * BAR + half * 2.0
    for off, ln, v in ((0.0, 0.6, vel), (0.75, 0.22, vel * 0.8), (1.0, 0.9, min(1.0, vel * 1.15))):
        for m in notes:
            chant.note(b0 + off, m, ln, v)


chant_x(3, 0, ["C#4", "F#4", "A#4"], 0.75)
chant_x(3, 1, ["C#4", "F#4", "A#4"], 0.9)
chant_x(24, 0, ["B3", "D4", "F#4"], 0.7)
chant_x(26, 0, ["G3", "B3", "D4"], 0.7)
chant_x(25, 1, ["F#3", "A#3", "C#4"], 0.7)
chant_x(27, 0, ["B3", "D4", "F#4"], 0.75)
for bar, notes in ((33, ["F#3", "A3", "C4"]), (35, ["F3", "B3", "D4"]), (37, ["F#3", "A3", "C4"])):
    chant_x(bar, 0, notes, 0.85)
chant_x(39, 0, ["C#4", "F#4", "A#4"], 0.9)
chant_x(39, 1, ["C#4", "F#4", "A#4"], 1.0)
chant_x(56, 0, ["G3", "Bb3", "Db4"], 0.9)
chant_x(56, 1, ["G3", "C4", "Eb4"], 0.9)

# ---------------------------------------------------------------- tolls ---
TOLL_NOTE = {"Bm": "B3", "G": "G3", "F#7": "F#3", "F#": "F#3", "Em7": "E3", "A": "A3", "Em": "E3",
             "Bm/A#": "B3", "Bm/A": "B3", "G#m7b5": "D4", "Em/G": "G3", "Gdim/Db": "G3", "G7": "G3",
             "D": "D4", "Cm": "C4", "C": "C4"}


def toll_at(bar, vel=0.8):
    s0, s1, c = next(h for h in song.harmony if h[0] <= bar * BAR < h[1])
    toll.note(bar * BAR, TOLL_NOTE[c], min(3.5, s1 - s0 - 0.1), vel)


for b in range(0, 4):
    toll_at(b, 0.85)
for b in (4, 6, 8, 10):
    toll_at(b, 0.65)
for b in range(28, 32):
    toll_at(b, 0.8)
for b in range(40, 48):
    toll_at(b, 0.7)
for b in (56, 57, 58):
    toll_at(b, 0.85)

# ------------------------------------------------------------------ harp ---
for s0, s1 in [(12, 20), (44, 48)]:
    for b0, b1, c in chords_in(s0, s1):
        harp_t.arp(b0 / BAR, voicing(c, 62, 76), "0 1 2 3 4 5 4 3", unit=U, beats=b1 - b0, vel=0.55)
# bell sparkle on the hymn landings
for bar, a, b in ((12, "D6", "A6"), (16, "G6", "D7")):
    bell_t.note(bar * BAR + 1.0, a, 1.0, 0.35)
    bell_t.note(bar * BAR + 3.0, b, 1.0, 0.35)

# ----------------------------------------------------- pumping strings ---
for s0, s1, v in [(4, 12, 0.6), (20, 28, 0.55), (32, 40, 0.65), (40, 56, 0.6)]:
    for b0, b1, c in chords_in(s0, s1):
        notes = voicing(c, 54, 66)
        t = b0
        k = 0
        while t < b1 - 1e-6:
            for m in notes:
                stac.note(t, m, 0.32, v * (1.0 if k % 2 == 0 else 0.75))
            t += 0.5
            k += 1

# ----------------------------------------------------------------- bass ---
CEIL = midi("E3")
ROOT = {"Bm": "B1", "Em": "E2", "Em7": "E2", "F#": "F#1", "F#7": "F#1", "G": "G1", "A": "A1", "D": "D2",
        "F#m": "F#1", "Bm/A#": "A#1", "Bm/A": "A1", "G#m7b5": "G#1", "Em/G": "G1", "F#dim/C": "C2",
        "Bdim/F": "F1", "C": "C2", "Cm": "C2", "Db": "Db2", "Ab": "Ab1", "Bb": "Bb1", "Gdim/Db": "Db2",
        "G7": "G1"}


def bass_bars(b0, b1, style, vel=1.0):
    for s, e, c in chords_in(b0, b1):
        r = midi(ROOT[c])
        o = r + 12 if r + 12 <= CEIL else r
        if style == "pulse8":
            t = s
            while t < e - 1e-6:
                bass.note(t, r, 0.4, 0.8 * vel)
                t += 0.5
        elif style == "oct8":
            pat = [r, r, o, r]
            for i in range(int((e - s) * 2)):
                bass.note(s + i * 0.5, pat[i % 4], 0.42, (0.95 if i % 2 == 0 else 0.75) * vel)
        elif style == "drive":
            pat = [r, r, o, r]
            for i in range(int((e - s) * 4)):
                bass.note(s + i * U, pat[i % 4], 0.2, (1.0 if i % 4 == 0 else 0.7) * vel)
        elif style == "long":
            bass.note(s, r, e - s - 0.1, 0.85 * vel)


bass_bars(0, 4, "pulse8", 0.8)
bass_bars(4, 8, "oct8")
bass_bars(8, 12, "drive")
bass_bars(12, 20, "oct8")
bass_bars(20, 28, "drive")
bass_bars(28, 32, "long")
bass_bars(32, 36, "oct8")
bass_bars(36, 40, "drive")
bass_bars(40, 59, "drive")
bass.seq(59, "F#1:2 F#1:1 F#1:1 F#2:2 F#1:2 F#1:2 F#1:1 F#1:1 C#2:2 A#1:1 -:1", unit=U)

# ----------------------------------------------------------------- pads ---
melodic = [lead, organ_ld, brass_t, choir_ld, chant, bell_t, bass]
for tr in (organ_ld, brass_t):
    drop_clashes(tr, [bass])


def place_pad(tr, b0, b1, c, vel, lo=50, hi=64):
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


for b0, b1, c in chords_in(0, 60):
    bar = b0 / BAR
    if bar < 4 or 28 <= bar < 32:
        place_pad(choir_oo, b0, b1, c, 0.75, 54, 66)
    else:
        place_pad(choir_pad, b0, b1, c, 0.6, 54, 66)
    place_pad(org_pad, b0, b1, c, 0.6 if (bar < 4 or 28 <= bar < 32) else 0.45, 47, 62)

# ---------------------------------------------------------------- drums ---
K_DRIVE = "x.....x.x.....x."
K_PROC = "x.......x.x....."
K_8 = "x.x.x.x.x.x.x.x."
SN = "....x.......x..."
HAT16 = "x.xox.xox.xox.xo"
HAT8 = "x.x.x.x.x.x.x.x."
OHAT = "..x...x...x...x."


def groove(bar, n=1, kick=K_DRIVE, hat=HAT16, snare=SN, ohat=None, clap=False, ride=None):
    v = {"kick": kick, "snare": snare, "hat": hat}
    if ohat:
        v["ohat"] = ohat
    if clap:
        v["clap"] = snare
    if ride:
        v["ride"] = ride
    dr.pat(bar, v, bars=n)


TIMP = {"Bm": "timp_lo", "G": "timp_lo", "D": "timp_lo", "A": "timp_hi", "F#m": "timp_hi", "Em7": "timp_lo",
        "Bm/A": "timp_hi", "G#m7b5": "timp_lo", "Em/G": "timp", "Em": "timp", "C": "timp", "Cm": "timp",
        "G7": "timp", "Gdim/Db": "timp"}

# vigil: heartbeat kick, ticking hats, gong; snare swell into the procession
dr.pat(0, {"kick": "x..x............", "hat": "..o...o...o...o."}, bars=3)
dr.pat(3, {"kick": "x..x....x.x.x.x.", "hat": HAT8})
dr.fill(3, "snare_ snare_ snare_ snare_ snare snare snare snare snare^ snare^ snare^ snare^", at=1.0)
fx.hit(0, "gong", 0.8)
fx.hit(3 * BAR + 2.5, "reverse_cymbal", 0.8)
# procession: half-time processional kit, then the backbeat
for b in range(4, 8):
    dr.pat(b, {"kick": K_PROC, "snare": "........x.......", "hat": HAT16})
    dr.hit(b * BAR, TIMP.get(song.chord_at(b * BAR), "timp_lo"), 0.75)
dr.fill(7, "tom_hi tom_mid tom_lo tom_lo", at=3.0)
groove(8, 3)
groove(11, 1)
dr.fill(11, "snare snare tom_hi tom_hi tom_mid tom_lo tom_lo tom_lo", at=2.0)
for b in (4, 8):
    dr.hit(b * BAR, "crash", 0.85)
# hymn: ride, open feel
groove(12, 7, hat=HAT8, ride="x.x.x.x.x.x.x.x.")
groove(19, 1, hat=HAT8)
dr.fill(15, "snare_ snare tom_hi tom_lo", at=3.0)
dr.fill(19, "snare snare snare snare tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=1.0)
for b in (12, 16):
    dr.hit(b * BAR, "crash", 0.75)
# hook
groove(20, 4, ohat=OHAT)
dr.fill(23, "snare_ snare tom_hi tom_lo", at=3.0)
groove(24, 4, ohat="..X...X...X...X.", clap=True)
dr.fill(27, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=2.0)
for b in (20, 24):
    dr.hit(b * BAR, "crash", 0.9)
fx.hit(20 * BAR, "gong", 0.6)
# eclipse: toms + timpani, kick on 1
for b in range(28, 32):
    dr.pat(b, {"kick": "x.........x.....", "tom_lo": "....x.......x...", "tom_mid": ".......x........",
               "shaker": "x.x.x.x.x.x.x.x."})
    dr.hit(b * BAR, TIMP.get(song.chord_at(b * BAR), "timp"), 0.8)
dr.fill(31, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo tom_lo tom_lo", at=2.0)
# ascending: kick 8ths, the snare grows into a roll, riser
groove(32, 4, kick=K_8, hat=HAT16)
groove(36, 2, kick=K_8, hat=HAT16, snare="....x.......x.x.")
dr.pat(38, {"kick": K_8, "snare": "x.x.x.x.x.x.x.x.", "hat": HAT8})
dr.pat(39, {"kick": K_8, "snare": "xxxxxxxxxxxxxxxx", "hat": HAT8})
for b in (32, 36):
    dr.hit(b * BAR, "crash", 0.8)
fx.hit(40 * BAR - 2.0 * 150 / 60, "riser", 0.9)
# ascension: full kit + gong + timpani on every bar
groove(40, 7, ohat=OHAT, clap=True)
groove(47, 1, ohat=OHAT, clap=True)
dr.fill(47, "snare snare snare snare tom_hi tom_mid tom_lo snare^", at=2.0)
for b in range(40, 48):
    dr.hit(b * BAR, TIMP.get(song.chord_at(b * BAR), "timp_lo"), 0.7)
fx.hit(40 * BAR, "gong", 0.9)
for b in (40, 44):
    dr.hit(b * BAR, "crash", 0.9)
# black comet + the pull: driving, ride bell, crash on the key change
groove(48, 3, kick=K_8, ohat=OHAT, clap=True, ride="x...x...x...x...")
groove(51, 1, kick=K_8, ohat=OHAT, clap=True)
dr.fill(51, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=2.0)
groove(52, 4, kick=K_8, ohat="..X...X...X...X.", clap=True, ride="x...x...x...x...")
dr.fill(55, "snare snare snare snare tom_hi tom_mid tom_lo snare^", at=2.0)
for b in (48, 52):
    dr.hit(b * BAR, "crash", 0.95)
fx.hit(52 * BAR, "gong", 0.7)
# turnaround: Morvane's call, tolls, toms; last 16th quiet for a clean seam
dr.pat(56, {"kick": "x..xx.....x.....", "snare": "...x............", "hat": HAT8})
dr.hit(56 * BAR, "crash", 0.9)
groove(57, 2, hat=HAT8)
dr.pat(59, {"kick": "x.......x.......", "hat": "x.x.x.x........."})
dr.fill(59, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ -", at=2.0)
fx.hit(56 * BAR, "gong", 0.8)

if __name__ == "__main__":
    song.render()

"""Magic Smash - main battle loop, angle B: "heroic chiptune action".

E minor, 160 bpm, 64 bars (96 s), loops from bar 0.
Twin pulse leads in 3rds/6ths, galloping FM bass, chip arps, chip drums layered
under a punchy real kit, and a lyrical relative-major bridge that quotes the
"Ma-gic SMASH!" leitmotif in augmentation (see ../SOUNDTRACK.md).

Form (bars, 1-based)
  1-4    Intro      the bass states the whole 2-bar motif three octaves down
  5-12   Verse A1   new tune from x's rhythm (3-1-4) and the rising 4th; Em D C B7
  13-20  Verse A2   pre-chorus: bass climbs C D E F# G A B, twin leads broaden,
                    ends with an x "stab" on B7 and a stop-time drum fill
  21-28  Hook B     MOTIF+ANSWER twice (2nd time: lead_fm harmony, clap, open hats)
  29-36  Bridge     lyrical: x / x' / peak / wink augmented, C Am G D | C Em Am B7
  37-44  Breakdown  half-time chip kit; bell calls x inverted, chip pulse answers with the wink
  45-48  Build      x chanted up the scale on lead + brass, snare 8ths -> 16ths, riser
  49-56  Climax B'  the theme twice, twin pulses on HARM, gallop bass; 2nd time the bell
                    echoes the lead an octave up
  57-60  Lift       the theme a step up in F# minor (truck-driver change via C#7)
  61-64  Tag        x + x' in major over D E, C, then the wink on B7 + tom fill -> loop
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403
from engine import Note  # noqa: E402

# ---------------------------------------------------------------- theme ---
# Reference key D minor (bible); transpose=+2 gives E minor, +4 gives F# minor.
# The bible's strings, with accents (^) on the "SMASH" landings that hit with the snare.
MOTIF = ("A4:3 A4:1 D5^:4 F5:3 E5:1 A5^:4 | "
         "Bb5^:3 A5:1 G5:2 F5:2 E5:2 F5:1 E5:1 C#5:2 A4:2")
ANSWER = ("F5:3 F5:1 Bb5^:4 G5:3 G5:1 C6^:4 | "
          "D6^:3 C6:1 A5:2 E5:1 C#5:1 D5:8")
# climax ending: release the final D on beat 4 and pick up into the key change
ANSWER_LIFT = ("F5:3 F5:1 Bb5^:4 G5:3 G5:1 C6^:4 | "
               "D6^:3 C6:1 A5:2 E5:1 C#5:1 D5:4 F#4:2 A4:2")
HARM = ("F4:3 F4:1 A4:4 D5:3 D5:1 F5:4 | G5:3 F5:1 D5:2 D5:2 C#5:4 A4:2 E4:2 | "
        "D5:3 D5:1 F5:4 E5:3 E5:1 G5:4 | A5:3 A5:1 F5:2 C#5:1 A4:1 F4:8")
HARM_LIFT = ("F4:3 F4:1 A4:4 D5:3 D5:1 F5:4 | G5:3 F5:1 D5:2 D5:2 C#5:4 A4:2 E4:2 | "
             "D5:3 D5:1 F5:4 E5:3 E5:1 G5:4 | A5:3 A5:1 F5:2 C#5:1 A4:1 F4:4 D#4:4")
THEME_CHORDS = "Em Am:0.5 B:0.5 C:0.5 D:0.5 Em"

# Intro riff: the 2-bar motif in E minor, three octaves down (bass), x2
INTRO_BASS = ("B1:3 B1:1 E2:4 G2:3 F#2:1 B2:4 | "
              "C3:3 B2:1 A2:2 G2:2 F#2:2 G2:1 F#2:1 D#2:2 B1:2")

KEY_EM = [4, 6, 7, 9, 11, 0, 2]
KEY_FSM = [6, 8, 9, 11, 1, 2, 4]

# ------------------------------------------------------------ new tunes ---
# Verse A1 (unit 1/16). Bars 1-4 ask (end on B7), bars 5-8 answer (end on Em).
#  b1 rising arpeggio from the rising 4th B-E, syncopated peak, stepwise fall
#  b2 x's rhythm falling down the D triad, then a turn down to A
#  b3 = b1 sequenced a 3rd lower (G-C is the rising 4th), chromatic D->D# hook
#  b4 x's rhythm climbing to the leading tone + rising 4th F#->B, 7th A hangs
#  b5-b7 falling sequence of x's rhythm (G F# E / F# E D / E D C), each with a
#         rising-4th pickup; b7 turns up D# E F# into the cadence
#  b8 cadence on E, the low B pickup launches the pre-chorus
VERSE = ("B4:2 E5:2 G5:2 B5:4 A5:2 G5:2 F#5:2 | "
         "A5:3 F#5:1 D5:4 F#5:2 E5:2 D5:2 A4:2 | "
         "G4:2 C5:2 E5:2 G5:4 E5:2 C5:2 D5:2 | "
         "D#5:3 E5:1 F#5:4 B5:6 A5:2 | "
         "G5:3 F#5:1 E5:4 B4:2 E5:2 G5:2 F#5:2 | "
         "F#5:3 E5:1 D5:4 A4:2 D5:2 F#5:2 E5:2 | "
         "E5:3 D5:1 C5:4 D#5:3 E5:1 F#5:4 | "
         "G5:6 F#5:2 E5:4 -:2 B4:2")
VERSE_CHORDS = "Em D C B7 Em D C:0.5 B7:0.5 Em"

# Verse A2 / pre-chorus: broad dotted rhythm (6-2-4-4) climbing by step with the
# bass, a break on D/F#, a falling answer over G Am, then the launch: B E F# A
# up the sus4 chord and the x "stab" (F# F# B) on B7 with the band stopping.
PRE = ("E5:6 D5:2 E5:4 G5:4 | "
       "F#5:6 E5:2 F#5:4 A5:4 | "
       "G5:6 F#5:2 G5:4 B5:4 | "
       "A5:8 F#5:4 D5:4 | "
       "B5:6 A5:2 G5:4 D5:4 | "
       "C6:6 B5:2 A5:4 E5:4 | "
       "B4:4 E5:4 F#5:4 A5:4 | "
       "F#5:3 F#5:1 B5:4 -:8")
PRE_CHORDS = "C D Em D/F# G Am B7sus4 B7"

# Bridge: the motif's construction re-told in augmentation (x2) with the
# half-time feel. Phrase 1 (relative major, open on D):
#   x on C (G G C), x' on Am (C B E: half-step dip + rising 4th), climb on G,
#   wink augmented on D (A B A F# D).
# Phrase 2 (back to minor): x, x' on Em (G F# B), the peak on the flat 6th C6,
#   then the theme's own wink augmented on B7 -> deceptive move to C.
BRIDGE = ("G4:6 G4:2 C5:8 | "
          "C5:6 B4:2 E5:8 | "
          "G5:6 F#5:2 G5:4 B5:4 | "
          "A5:4 B5:2 A5:2 F#5:4 D5:4 | "
          "G4:6 G4:2 C5:4 E5:4 | "
          "G5:6 F#5:2 B5:8 | "
          "C6:6 B5:2 A5:4 E5:4 | "
          "F#5:4 G5:2 F#5:2 D#5:4 B4:4")
BRIDGE_CHORDS = "C Am G D C Em Am B7"

BREAK_CHORDS = "C G D Em C G Am B7"
BUILD_CHORDS = "C D B7sus4 B7"
# Build: x chanted up the scale (G G C, A A D, B B E over the sus4), then the stab
BUILD = ("G4:3 G4:1 C5:4 G4:3 G4:1 C5:4 | "
         "A4:3 A4:1 D5:4 A4:3 A4:1 D5:4 | "
         "B4:3 B4:1 E5:4 B4:3 B4:1 E5:4 | "
         "F#5:3 F#5:1 B5:4 D#5:2 F#5:2 A5:2 F#5:2")

# Tag: x + x' in MAJOR over D and E (the heroes win a round), C, then the wink on
# B7 with the low B on the "and" of 4 handing over to the bass riff at bar 1.
TAG = ("A4:3 A4:1 D5:4 F#5:3 E5:1 A5:4 | "
       "B4:3 B4:1 E5:4 G#5:3 F#5:1 B5:4 | "
       "G5:3 G5:1 C6:4 G5:2 E5:2 C5:2 E5:2 | "
       "B5:8 F#5:2 G5:1 F#5:1 D#5:2 B4:2")
TAG_CHORDS = "D E C B7"

# --------------------------------------------------------------- song ---
song = Song("music_battle__B", bpm=160, bars=64, reverb_seconds=1.6)
song.loop(0)
for bar, text in [(0, "Em Am:0.5 B:0.5 Em Am:0.5 B:0.5"), (4, VERSE_CHORDS), (12, PRE_CHORDS),
                  (20, THEME_CHORDS), (24, THEME_CHORDS), (28, BRIDGE_CHORDS), (36, BREAK_CHORDS),
                  (44, BUILD_CHORDS), (48, THEME_CHORDS),
                  (52, "Em Am:0.5 B:0.5 C:0.5 D:0.5 Em:0.75 C#7:0.25"),
                  (56, "F#m Bm:0.5 C#:0.5 D:0.5 E:0.5 F#m"), (60, TAG_CHORDS)]:
    song.chords(bar, text)
for bar, lbl in [(0, "intro"), (4, "verse A1"), (12, "A2 pre"), (20, "hook B"), (28, "bridge"),
                 (36, "breakdown"), (44, "build"), (48, "climax B'"), (56, "lift F#m"), (60, "tag")]:
    song.section(bar, lbl)

BAR = 4.0


def key_for(beat):
    return KEY_FSM if 56 * BAR <= beat < 60 * BAR else KEY_EM


def scale_for(chord, key):
    """Key scale with the chord's chromatic tones swapped in (raised tones replace the
    scale step a semitone below, e.g. D# replaces D over B7)."""
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


def harmonize(src, b0, b1, dst, vel=0.85):
    """Twin-lead harmony under the notes of `src` in bars [b0, b1): diatonic 3rds,
    with 6ths/4ths where the 3rd would be a non-chord tone on a strong note."""
    prev = None
    mode = 2  # scale steps below (2 = 3rd, 5 = 6th, 3 = 4th)
    for n in sorted([x for x in src.notes if b0 * BAR <= x.beat < b1 * BAR], key=lambda x: x.beat):
        c = song.chord_at(n.beat)
        sc = scale_for(c, key_for(n.beat))
        cps = chord_pcs(c)
        m = int(n.m)
        strong = abs(n.beat % 1.0) < 1e-6 or n.beats >= 1.0
        if strong:
            cands = [(s, step_below(m, s, sc)) for s in (2, 5, 3)]
            good = [(s, x) for s, x in cands if x % 12 in cps and m - x != 6]
            if good:
                if prev is None:
                    s, x = good[0]
                else:  # keep the harmony line smooth, prefer 3rds on ties
                    s, x = min(good, key=lambda sx: abs(sx[1] - prev) + {2: 0.0, 5: 1.5, 3: 3.5}[sx[0]])
            else:
                s, x = 2, step_below(m, 2, sc)
            mode = s
        else:
            x = step_below(m, mode if mode != 3 else 2, sc)
        dst.notes.append(Note(n.beat, float(x), n.beats, n.vel * vel, n.slide))
        prev = x


def chords_in(b0, b1):
    return [(s, e, c) for (s, e, c) in song.harmony if b0 * BAR <= s < b1 * BAR]


def voicing(c, lo=52, hi=67):
    out = []
    for p in sorted(chord_pcs(c)):
        m = lo + ((p - lo) % 12)
        if m > hi:
            m -= 12
        out.append(m)
    return sorted(out)


# ---------------------------------------------------------- instruments ---
lead = song.track("lead", lead_pulse(cutoff=8000), vol=-7.5, pan=0.0, reverb=0.15, delay=0.1, hp=180)
lead2 = song.track("lead2", lead_pulse(duty=0.5, cutoff=4500, vib_depth=0.14, gain=0.5),
                   vol=-12, pan=-0.15, reverb=0.15, delay=0.06, hp=180)
counter = song.track("counter", lead_fm(), vol=-13, pan=-0.22, reverb=0.15, hp=180)
chip = song.track("chip", arp_pulse(s=0.55, d=0.15, r=0.08, vib_depth=0.12, vib_delay=0.15),
                  vol=-5, pan=0.3, reverb=0.2, delay=0.2, hp=400)
bell_t = song.track("bell", bell(), vol=-9, pan=-0.3, reverb=0.35, delay=0.18, hp=300)
brass_t = song.track("brass", brass(), vol=-12, pan=-0.2, reverb=0.2, hp=150)
arp = song.track("arp", arp_pulse(), vol=-10, pan=0.35, reverb=0.1, delay=0.15, hp=400, duck=0.2)
pad = song.track("pad", strings(), vol=-10.5, reverb=0.45, duck=0.35, hp=200)
bass = song.track("bass", bass_fm(sub=0.12), vol=-7.3, duck=0.3, hp=32)
bass_chip = song.track("bass_chip", bass_nes(), vol=-16, duck=0.2)
dr = song.drums("drums", vol=-7.2, reverb=0.07)

U = 0.25  # 16ths

def levels(tr, pts):
    """Step-wise section gain (dB) for a track: pts = [(bar, dB), ...] in order."""
    pts = list(pts) + [(song.bars, pts[-1][1])]
    for (b0, g), (b1, _) in zip(pts[:-1], pts[1:]):
        tr.automation.append((b0 * BAR, g))
        tr.automation.append((b1 * BAR - 0.02, g))


# dynamics: verse sits under the hook, bridge a little under, climax on top
levels(dr, [(0, 0), (4, -2.5), (12, -1.5), (16, -0.5), (20, 0), (28, -1.5), (36, 0), (48, 0.5), (60, 0)])
levels(bass, [(0, 0), (4, -2.0), (12, -1.0), (16, -0.5), (20, 0), (28, -1.0), (36, 0), (48, 0.5), (60, 0)])
levels(lead, [(0, 0), (4, -1.0), (12, -0.5), (20, 0)])
levels(lead2, [(0, 0), (4, -1.0), (12, -0.5), (20, 0)])


# ---------------------------------------------------------------- lead ---
lead.seq(4, VERSE, unit=U)
lead.seq(12, PRE, unit=U)
for b in (20, 24, 48):
    lead.seq(b, MOTIF + " | " + ANSWER, unit=U, transpose=2)
lead.seq(28, BRIDGE, unit=U)
lead.seq(44, BUILD, unit=U, vel=0.72)
lead.seq(52, MOTIF + " | " + ANSWER_LIFT, unit=U, transpose=2)
lead.seq(56, MOTIF + " | " + ANSWER, unit=U, transpose=4)
lead.seq(60, TAG, unit=U)

# ---------------------------------------------------- twin lead / counter ---
harmonize(lead, 8, 20, lead2)          # joins for the verse answer and the pre-chorus
harmonize(lead, 28, 36, lead2)         # lyrical bridge in 3rds/6ths
harmonize(lead, 60, 64, lead2)         # tag
lead2.seq(48, HARM, unit=U, transpose=2, vel=0.8)
lead2.seq(52, HARM_LIFT, unit=U, transpose=2, vel=0.8)
lead2.seq(56, HARM, unit=U, transpose=4, vel=0.8)
counter.seq(24, HARM, unit=U, transpose=2)
# intro bars 3-4: the square doubles the bass riff two octaves up (a unison riff)
lead2.seq(2, INTRO_BASS, unit=U, transpose=24, vel=0.7)

# brass: x chant in the build (doubles the lead a 3rd/6th below), stabs in the lift
harmonize(lead, 44, 48, brass_t, vel=0.9)
for b0, b1, c in chords_in(55, 60):
    if b0 >= 55 * BAR + 3 or b0 >= 56 * BAR:  # the C#7 pivot and the lift
        for m in voicing(c, 55, 70):
            brass_t.note(b0, m, 0.75, 0.75)

# bell: octave-up echo of the lead in the 2nd climax statement and the lift
for n in [x for x in lead.notes if 52 * BAR <= x.beat < 56 * BAR]:
    bell_t.notes.append(Note(n.beat, n.m + 12, n.beats, 0.3))

# ------------------------------------------------------------ breakdown ---
# bell calls with x inverted (falls a 5th), the chip pulse answers with the wink
# (5 6 5 3 1 over each chord); 2nd half the answers move up and the lead2 doubles.
CALLS = ["G5:3 G5:1 C5:4", "D5:3 D5:1 G4:4", "A5:3 A5:1 D5:4", "B5:3 B5:1 E5:4",
         "G5:3 G5:1 C5:4", "D5:3 D5:1 G4:4", "E5:3 E5:1 A4:4", "F#5:3 F#5:1 B4:4"]
WINKS = ["G5:2 A5:1 G5:1 E5:2 C5:2", "D5:2 E5:1 D5:1 B4:2 G4:2", "A5:2 B5:1 A5:1 F#5:2 D5:2",
         "B5:2 C6:1 B5:1 G5:2 E5:2", "G5:2 A5:1 G5:1 E5:2 C5:2", "D5:2 E5:1 D5:1 B4:2 G4:2",
         "E5:2 F#5:1 E5:1 C5:2 A4:2", "F#5:2 G5:1 F#5:1 D#5:2 B4:2"]
for i in range(8):
    bell_t.seq(36 + i, CALLS[i], unit=U, vel=0.75)
    chip.seq(36 + i, WINKS[i], unit=U, at=2.0, vel=0.8)
harmonize(chip, 40, 44, lead2, vel=0.6)   # the twin pulse sneaks back in under the winks

# ---------------------------------------------------------------- bass ---
bass.seq(0, INTRO_BASS + " | " + INTRO_BASS, unit=U)


def gallop(bar, root, walk=None, fifth=False):
    """NES gallop: 8th + two 16ths per beat, upper octave on beats 2/4.
    fifth=True puts the 5th on beat 2 instead (where the lead lands its x on the
    root, so lead and bass don't double the same line in octaves).
    walk = two notes replacing the last two 16ths of the bar (approach tones)."""
    r = midi(root)
    toks = []
    for b in range(4):
        top = (r + 7 if fifth else r + 12) if b == 1 else (r + 12 if b == 3 else r)
        toks += [(top, 2), (r, 1), (r, 1)]
    if walk:
        toks[-2] = (midi(walk[0]), 1)
        toks[-1] = (midi(walk[1]), 1)
    bass.seq(bar, " ".join(f"{name_of(m)}:{d}" for m, d in toks), unit=U)


def gallop_half(bar, r1, r2, walk=None):
    a, b = midi(r1), midi(r2)
    toks = [(a, 2), (a, 1), (a, 1), (a + 7, 2), (a, 1), (a, 1),
            (b, 2), (b, 1), (b, 1), (b + 12, 2), (b, 1), (b, 1)]
    if walk:
        toks[-2] = (midi(walk[0]), 1)
        toks[-1] = (midi(walk[1]), 1)
    bass.seq(bar, " ".join(f"{name_of(m)}:{d}" for m, d in toks), unit=U)


# verse A1
gallop(4, "E2")
gallop(5, "D2", fifth=True)
gallop(6, "C2")
gallop(7, "B1", walk=("C#2", "D#2"))
gallop(8, "E2", fifth=True)
gallop(9, "D2", fifth=True)
gallop_half(10, "C2", "B1", walk=("C#2", "D#2"))
gallop(11, "E2", walk=("D2", "C#2"))
# pre-chorus: pumping 8ths climbing C D E F# G A B
for i, r in enumerate(["C2", "D2", "E2", "F#2", "G2", "A2"]):
    m = midi(r)
    bass.seq(12 + i, " ".join(name_of(x) for x in [m, m, m + 12, m, m, m, m + 12, m]), unit=0.5)
bass.seq(18, "B1 B2 B1 B2 B1 B2 B1 B2", unit=0.5)
bass.seq(19, "B1:3 B1:1 B2:4 -:8", unit=U)
# hook: the bible's tested line (5ths on beats 2 and 4 of bar 3)
# (bar 4 beat 2 changed A2 -> F2 so lead and bass don't both fall 5->1 in octaves)
THEME_BASS = ("D2 D3 D2 D3 D2 D3 C3 A2 | G2 G3 G2 G3 A2 A3 A2 A3 | "
              "Bb1 Bb2 F2 Bb2 C2 C3 G2 E2 | D2 D3 F2 D3 D2 D3 A2 A1")
bass.seq(20, THEME_BASS, unit=0.5, transpose=2)
bass.seq(24, THEME_BASS, unit=0.5, transpose=2)
# bridge: lyrical bass in the bridge's own 6-2-4-4 rhythm
for bar, (r, f, t) in zip(range(28, 36), [("C2", "G2", "C3"), ("A1", "E2", "A2"), ("G1", "D2", "G2"),
                                          ("D2", "A2", "D3"), ("C2", "G2", "C3"), ("E2", "B2", "E3"),
                                          ("A1", "E2", "A2"), ("B1", "F#2", "A2")]):
    bass.seq(bar, f"{r}:6 {r}:2 {f}:4 {t}:4", unit=U)
# breakdown: chip triangle bass, octave bounces
for bar, r in zip(range(36, 44), ["C2", "G1", "D2", "E2", "C2", "G1", "A1", "B1"]):
    m = midi(r)
    bass_chip.seq(bar, " ".join(name_of(x) for x in [m, m + 12] * 4), unit=0.5)
# build: pumping 8ths, 16ths on the last bar
bass.seq(44, "C2 C2 C2 C2 C2 C2 C2 C2", unit=0.5)
bass.seq(45, "D2 D2 D2 D2 D2 D2 A1 A1", unit=0.5)
bass.seq(46, "B1 B1 B1 B1 B1 B1 B1 B1", unit=0.5)
bass.seq(47, " ".join(["B1", "B1", "B2", "B1"] * 4), unit=U)
# climax: galloping version of the tested theme bass


def theme_gallop(bar, t, lift=False):
    def nm(s):
        return name_of(midi(s) + t)
    bass.seq(bar, f"{nm('D2')}:2 {nm('D2')}:1 {nm('D2')}:1 {nm('A2')}:2 {nm('D2')}:1 {nm('D2')}:1 "
                  f"{nm('D2')}:2 {nm('D2')}:1 {nm('D2')}:1 {nm('C3')}:2 {nm('A2')}:1 {nm('A2')}:1", unit=U)
    bass.seq(bar + 1, f"{nm('G2')}:2 {nm('G2')}:1 {nm('G2')}:1 {nm('G3')}:2 {nm('G2')}:1 {nm('G2')}:1 "
                      f"{nm('A2')}:2 {nm('A2')}:1 {nm('A2')}:1 {nm('A3')}:2 {nm('A2')}:1 {nm('A2')}:1", unit=U)
    bass.seq(bar + 2, f"{nm('Bb1')}:2 {nm('Bb1')}:1 {nm('Bb1')}:1 {nm('F2')}:2 {nm('Bb1')}:1 {nm('Bb1')}:1 "
                      f"{nm('C2')}:2 {nm('C2')}:1 {nm('C2')}:1 {nm('G2')}:2 {nm('G2')}:1 {nm('E2')}:1", unit=U)
    if lift:  # last beat: C#7 (V of F# minor)
        bass.seq(bar + 3, f"{nm('D2')}:2 {nm('D2')}:1 {nm('D2')}:1 {nm('F2')}:2 {nm('F2')}:1 {nm('F2')}:1 "
                          f"{nm('D2')}:2 {nm('D2')}:1 {nm('D2')}:1 C#2:2 C#3:1 G#2:1", unit=U)
    else:
        bass.seq(bar + 3, f"{nm('D2')}:2 {nm('D2')}:1 {nm('D2')}:1 {nm('F2')}:2 {nm('F2')}:1 {nm('F2')}:1 "
                          f"{nm('D2')}:2 {nm('D2')}:1 {nm('D2')}:1 {nm('A2')}:2 {nm('A1')}:1 {nm('A1')}:1", unit=U)


theme_gallop(48, 2)
theme_gallop(52, 2, lift=True)
theme_gallop(56, 4)
# tag
gallop(60, "D2", fifth=True)
gallop(61, "E2", fifth=True)
gallop(62, "C2", fifth=True)
bass.seq(63, "B1:2 B1:1 B1:1 B2:2 B1:1 B1:1 B1:2 B1:1 B1:1 A2:2 F#2:1 D#2:1", unit=U)

# ----------------------------------------------------------------- arps ---
ARP_SECTIONS = [(2, 4), (12, 19), (24, 28), (36, 44), (44, 48), (48, 64)]
for s0, s1 in ARP_SECTIONS:
    for b0, b1, c in chords_in(s0, s1):
        tones = voicing(c, 60, 74)
        arp.arp(b0 / BAR, tones, "0 1 2 3 2 1",
                unit=U, beats=b1 - b0, vel=0.7)
for b0, b1, c in chords_in(8, 12):  # verse answer: the arp creeps in quietly
    arp.arp(b0 / BAR, voicing(c, 60, 74), "0 1 2 3 2 1", unit=U, beats=b1 - b0, vel=0.45)

# ----------------------------------------------------------------- pads ---
PAD_SECTIONS = [(12, 19), (20, 24), (24, 28), (28, 36), (40, 44), (44, 48), (48, 64)]
melodic = [lead, lead2, counter, chip, bass, bass_chip, brass_t]


def place_pad(b0, b1, c):
    notes = voicing(c)
    for p in notes:
        q = p
        for tr in melodic:
            for n in tr.notes:
                if n.beats < 0.5 or n.beat >= b1 or n.beat + n.beats <= b0:
                    continue
                iv = abs(int(n.m) - q)
                if iv % 12 in (1, 11) and iv < 24:
                    q = None
                    break
            if q is None:
                break
        if q is not None:
            pad.note(b0, q, b1 - b0 - 0.08, 0.6)


for s0, s1 in PAD_SECTIONS:
    for b0, b1, c in chords_in(s0, s1):
        place_pad(b0, b1, c)

# --------------------------------------------------------------- drums ---
K_DRIVE = "x.....x.x.....x."
K_FOUR = "x...x...x...x..."
SN = "....x.......x..."
HAT8 = "x.x.x.x.x.x.x.x."
HATG = "x.xox.xox.xox.xo"
OHAT = "..x...x...x...x."
CHIP_HAT = ".o.o.o.o.o.o.o.o"


def groove(bar, n=1, kick=K_DRIVE, hat=HATG, ohat=None, clap=False, chip_layer=True, snare=SN):
    v = {"kick": kick, "snare": snare, "hat": hat}
    if ohat:
        v["ohat"] = ohat
    if clap:
        v["clap"] = SN
    if chip_layer:
        v["snare_chip"] = snare.replace("x", "o")
        v["hat_chip"] = CHIP_HAT
    dr.pat(bar, v, bars=n)


def small_fill(bar):
    dr.fill(bar, "snare_ snare tom_hi tom_lo", at=3.0)


def big_fill(bar):
    dr.fill(bar, "snare snare_ snare snare tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=1.0)


# intro: kick + chip hats, then the real kit
dr.pat(0, {"kick": "x.....x.x.......", "hat_chip": "x.x.x.x.x.x.x.x.", "kick_chip": "x.......x......."}, bars=2)
dr.fill(1, "snare_ snare_ snare snare", at=3.0)
groove(2, 2, hat=HAT8)
dr.fill(3, "tom_hi tom_hi tom_mid tom_lo", at=3.0)
dr.hit(0, "crash", 0.8)
# verse A1
dr.pat(4, {"shaker": ".o.x.o.x.o.x.o.x"}, bars=8)
dr.pat(28, {"shaker": ".o.x.o.x.o.x.o.x"}, bars=8)
groove(4, 3, hat=HAT8)
groove(7, 1, hat=HAT8)
small_fill(7)
groove(8, 4, hat=HATG)
small_fill(11)
for b in (4, 8):
    dr.hit(b * BAR, "crash", 0.75)
# pre-chorus: four on the floor, open hats
groove(12, 6, kick=K_FOUR, hat=HAT8, ohat=OHAT)
small_fill(15)
dr.hit(12 * BAR, "crash", 0.8)
dr.hit(16 * BAR, "crash", 0.7)
groove(18, 1, kick=K_FOUR, hat="xxxxxxxxxxxxxxxx", ohat=OHAT, snare="....x.......x.x.")
# bar 20 of the score (index 19): stop-time stab with the x rhythm, then the fill
for off in (0.0, 0.75, 1.0):
    dr.hit(19 * BAR + off, "kick", 1.0)
    dr.hit(19 * BAR + off, "snare", 0.8 if off else 0.6)
dr.hit(19 * BAR, "crash", 0.9)
dr.fill(19, "snare_ snare_ snare snare snare snare tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo", at=1.0)
# hook B
groove(20, 3, hat=HAT8, ohat=OHAT)
groove(23, 1, hat=HAT8, ohat=OHAT)
small_fill(23)
groove(24, 3, hat=HATG, ohat=OHAT, clap=True)
groove(27, 1, hat=HATG, ohat=OHAT, clap=True)
big_fill(27)
for b in (20, 24):
    dr.hit(b * BAR, "crash", 0.9)
# bridge: ride, lighter kick, snare 2 & 4
for b in range(28, 36):
    dr.pat(b, {"kick": "x.......x.x.....", "snare": SN, "ride": "x...x...x...x...", "hat": "..o...o...o...o."})
small_fill(31)
dr.fill(35, "snare snare tom_hi tom_hi tom_mid tom_lo tom_lo tom_lo", at=2.0)
dr.hit(28 * BAR, "crash", 0.8)
dr.hit(32 * BAR, "crash", 0.7)
# breakdown: half-time chip kit
dr.pat(36, {"kick_chip": "x.........x.....", "snare_chip": "........x.......", "hat_chip": "x.x.x.x.x.x.x.x."},
       bars=4)
dr.pat(40, {"kick_chip": "x.........x.....", "snare_chip": "........x.......", "hat_chip": "xxxxxxxxxxxxxxxx",
            "kick": "x...............", }, bars=3)
dr.pat(43, {"kick_chip": "x.......", "snare_chip": "........x.x.xxxx", "hat_chip": "xxxxxxxxxxxxxxxx"})
# build: snare 8ths then 16ths, riser into the climax
dr.pat(44, {"kick": K_FOUR, "snare": "x.x.x.x.x.x.x.x.", "hat": HAT8}, bars=2)
dr.pat(46, {"kick": K_FOUR, "snare": "xxxxxxxxxxxxxxxx", "hat": HAT8}, bars=2)
dr.hit(44 * BAR, "crash", 0.7)
dr.hit(48 * BAR - 2.0 * 160 / 60, "riser", 0.9)
dr.fill(47, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=2.0)
# climax + lift
groove(48, 3, hat=HATG, ohat=OHAT, clap=True)
groove(51, 1, hat=HATG, ohat=OHAT, clap=True)
small_fill(51)
groove(52, 3, hat=HATG, ohat=OHAT, clap=True)
groove(55, 1, hat=HATG, ohat=OHAT, clap=True)
dr.fill(55, "snare snare snare snare tom_hi tom_mid tom_lo snare^", unit=0.25, at=2.0)
groove(56, 3, hat=HATG, ohat=OHAT, clap=True)
groove(59, 1, hat=HATG, ohat=OHAT, clap=True)
small_fill(59)
for b in (48, 52, 56, 60):
    dr.hit(b * BAR, "crash", 0.9)
# tag
groove(60, 3, hat=HAT8, ohat=OHAT)
groove(63, 1, hat=HAT8, ohat=OHAT)
dr.fill(63, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare snare", at=2.0)

if __name__ == "__main__":
    song.render(out_dir=os.path.join(HERE, "out", "candidates"))

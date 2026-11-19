"""Magic Smash - MAIN BATTLE LOOP (final arrangement).

E minor, 160 bpm, 64 bars = 96 s, loop(0). Built from the winning candidate
(music_battle__B: twin pulse leads, galloping FM bass, chip-layered kit) with
grafts from candidate A (saw lead, power-chord stabs and chugs, falling-fifths
way home) and a rework of form, voicing and mix.

Two lead voices hold a conversation through the loop: the hero pulse (every
first statement of the "Ma-gic SMASH!" theme) and a warmer detuned saw (the
partner). Handing the tune back and forth gives the ear and the game's
spell SFX regular breathing room.

Form (bars, 1-based)
  1-4    Intro      bass states the motif 3 octaves down; bars 3-4 + square double,
                    brass "SMASH" stabs on beats 2/4 and a crash (loop restart)
  5-12   Verse      hero pulse, 8-bar period (ask on B7, answer to Em) with breaths
                    in bars 8 and 12; lighter kit, then shaker/chip layer and the
                    second pulse in parallel 6ths from bar 9
  13-20  Pre        the SAW takes over: climbing 6-2-4-4 sequence with the bass
                    C D E F# G A B, lead2 in 3rds/5ths, L/R power-chord chugs,
                    four on the floor, x stab on B7 with the whole band + stop fill
  21-28  Hook       theme x2 on the hero pulse (2nd time FM counter on HARM, clap)
  29-36  Bridge     augmented motif as a dialogue: saw calls low (29-30, 33-34),
                    hero answers high in 6ths with lead2 (31-32, 35-36); ride
  37-44  Breakdown  half-time chip kit; bell calls x inverted, chip pulse winks
  45-48  Build      x chanted up the scale by lead2 + brass, hero joins at 47
  49-52  Climax 1   theme as call and response: the hero shouts each x cell, saw +
                    brass answer with the second cell; lead2 on HARM throughout
  53-56  Climax 2   full theme, reharmonised to start on Cmaj7, brass power stabs
                    on every chord change, bell rings only the "SMASH" landings
  57-60  Lift       the theme a step up in F# minor (pivot C#7), slightly pulled back
  61-64  Tag        x in major down the circle of fifths Bm7 E7 Am7 -> B7, wink, low B
                    and a tom fill hand over to the intro riff
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403
from engine import Note  # noqa: E402

# ---------------------------------------------------------------- theme ---
# Reference key D minor (bible); transpose=+2 gives E minor, +4 gives F# minor.
MOTIF = ("A4:3 A4:1 D5^:4 F5:3 E5:1 A5^:4 | "
         "Bb5^:3 A5:1 G5:2 F5:2 E5:2 F5:1 E5:1 C#5:2 A4:2")
ANSWER = ("F5:3 F5:1 Bb5^:4 G5:3 G5:1 C6^:4 | "
          "D6^:3 C6:1 A5:2 E5:1 C#5:1 D5:8")
# climax ending: release the final D on beat 3 and pick up into the key change
ANSWER_LIFT = ("F5:3 F5:1 Bb5^:4 G5:3 G5:1 C6^:4 | "
               "D6^:3 C6:1 A5:2 E5:1 C#5:1 D5:4 F#4:2 A4:2")
# call-and-response version: the hero shouts each x on the downbeat, the band
# (saw + brass) answers with the second cell of bars 1 and 3
HERO_CALLS = ("A4:3 A4:1 D5^:4 -:8 | "
              "Bb5^:3 A5:1 G5:2 F5:2 E5:2 F5:1 E5:1 C#5:2 A4:2 | "
              "F5:3 F5:1 Bb5^:4 -:8 | "
              "D6^:3 C6:1 A5:2 E5:1 C#5:1 D5:8")
BAND_ANS = "-:8 F5:3 E5:1 A5^:4 | -:16 | -:8 G5:3 G5:1 C6^:4 | -:16"
HARM = ("F4:3 F4:1 A4:4 D5:3 D5:1 F5:4 | G5:3 F5:1 D5:2 D5:2 C#5:4 A4:2 E4:2 | "
        "D5:3 D5:1 F5:4 E5:3 E5:1 G5:4 | A5:3 A5:1 F5:2 C#5:1 A4:1 F4:8")
HARM_LIFT = ("F4:3 F4:1 A4:4 D5:3 D5:1 F5:4 | G5:3 F5:1 D5:2 D5:2 C#5:4 A4:2 E4:2 | "
             "D5:3 D5:1 F5:4 E5:3 E5:1 G5:4 | A5:3 A5:1 F5:2 C#5:1 A4:1 F4:4 D#4:4")
THEME_CHORDS = "Em Am:0.5 B:0.5 C:0.5 D:0.5 Em"

# Intro riff: the 2-bar motif in E minor, three octaves down (bass), x2
INTRO_BASS = ("B1:3 B1:1 E2:4 G2:3 F#2:1 B2:4 | "
              "C3:3 B2:1 A2:2 G2:2 F#2:2 G2:1 F#2:1 D#2:2 B1:2")

# ------------------------------------------------------------ new tunes ---
# Verse (unit 1/16). Bars 1-4 ask (end on B7), bars 5-8 answer (end on Em).
#  b1 rising arpeggio from the rising 4th B-E, syncopated peak, stepwise fall
#  b2 x's rhythm falling down the D triad, then a turn down to A
#  b3 = b1 sequenced a 3rd lower (G-C is the rising 4th)
#  b4 x's rhythm climbing to the leading tone, then a breath; the 7th (A) picks
#     up into the answer
#  b5-b7 falling sequence of x's rhythm (G F# E / F# E D / E D C), b7 turns up
#     D# E F# into the cadence
#  b8 broadened cadence on E, a beat of air before the saw takes the pre-chorus
VERSE = ("B4:2 E5:2 G5:2 B5:4 A5:2 G5:2 F#5:2 | "
         "A5:3 F#5:1 D5:4 F#5:2 E5:2 D5:2 A4:2 | "
         "G4:2 C5:2 E5:2 G5:4 E5:2 C5:2 D5:2 | "
         "D#5:3 E5:1 F#5:4 -:6 A5:2 | "
         "G5:3 F#5:1 E5:4 B4:2 E5:2 G5:2 F#5:2 | "
         "F#5:3 E5:1 D5:4 A4:2 D5:2 F#5:2 E5:2 | "
         "E5:3 D5:1 C5:4 D#5:3 E5:1 F#5:4 | "
         "G5:6 F#5:2 E5:4 -:4")
# second pulse in parallel 6ths under the answer (hand-written, rhythm simplified)
VERSE_HARM = ("B4:3 A4:1 G4:4 G4:4 B4:4 | "
              "A4:3 G4:1 F#4:4 F#4:4 A4:4 | "
              "G4:4 E4:4 F#4:3 G4:1 A4:4 | "
              "B4:6 A4:2 G4:4 -:4")
VERSE_CHORDS = "Em D C B7 Em D C:0.5 B7:0.5 Em"

# Pre-chorus on the saw: broad dotted rhythm climbing by step with the bass, a
# breath on D/F# with an F#->B rising-4th pickup, a falling answer over G Am,
# then the launch up the sus4 chord and the x stab (F# F# B) on B7.
PRE = ("E5:6 D5:2 E5:4 G5:4 | "
       "F#5:6 E5:2 F#5:4 A5:4 | "
       "G5:6 F#5:2 G5:4 B5:4 | "
       "A5:8 -:4 F#5:4 | "
       "B5:6 A5:2 G5:4 D5:4 | "
       "C6:6 B5:2 A5:4 E5:4 | "
       "B4:4 E5:4 F#5:4 A5:4")
# lead2 under the saw: 3rds with the motif's rising 4th as a lower neighbour figure,
# then an oblique pedal under the falling answer, quartal under the sus4
PRE_HARM = ("C5:6 G4:2 C5:4 E5:4 | "
            "D5:6 A4:2 D5:4 F#5:4 | "
            "E5:6 B4:2 E5:4 G5:4 | "
            "F#5:8 -:4 D5:4 | "
            "D5:12 B4:4 | "
            "E5:12 C5:4 | "
            "F#4:4 B4:4 B4:4 E5:4")
STAB = "F#5:3 F#5:1 B5^:4 -:8"
STAB_HARM = "D#5:3 D#5:1 F#5:4 -:8"
PRE_CHORDS = "C D Em D/F# G Am B7sus4 B7"

# Bridge: the motif's construction in augmentation (x2) as a dialogue.
BRIDGE_CALL1 = "G4:6 G4:2 C5:8 | C5:6 B4:2 E5:8"            # saw, low: x on C, x' on Am
BRIDGE_ANS1 = "G5:6 F#5:2 G5:4 B5:4 | A5:4 B5:2 A5:2 F#5:4 D5:4"   # hero: climb, wink on D
BRIDGE_CALL2 = "G4:6 G4:2 C5:4 E5:4 | G5:6 F#5:2 B5:8"      # saw: x on C, x' on Em
BRIDGE_ANS2 = "C6:6 B5:2 A5:4 E5:4 | F#5:4 G5:2 F#5:2 D#5:4 B4:4"  # hero: flat-6 peak, wink on B7
BRIDGE_HARM1 = "B4:6 A4:2 B4:4 D5:4 | F#5:8 D5:4 A4:4"
BRIDGE_HARM2 = "A5:6 G5:2 E5:4 C5:4 | D#5:8 B4:4 F#4:4"
BRIDGE_CHORDS = "C Am G D C Em Am B7"

BREAK_CHORDS = "C G D Em C G Am B7"
BUILD_CHORDS = "C D B7sus4 B7"
# Build: x chanted up the scale (G G C, A A D, B B E over the sus4), then the stab
BUILD12 = ("G4:3 G4:1 C5:4 G4:3 G4:1 C5:4 | "
           "A4:3 A4:1 D5:4 A4:3 A4:1 D5:4")
BUILD34 = ("B4:3 B4:1 E5:4 B4:3 B4:1 E5:4 | "
           "F#5:3 F#5:1 B5:4 D#5:2 F#5:2 A5:2 F#5:2")
BUILD34_HARM = ("F#4:3 F#4:1 B4:4 F#4:3 F#4:1 B4:4 | "
                "D#5:3 D#5:1 F#5:4 B4:2 D#5:2 F#5:2 D#5:2")

# Tag: x + x' in major falling down the circle of fifths (Bm7 E7 Am7) to B7;
# the wink's low B on the "and" of 4 hands over to the bass riff at bar 1.
TAG = ("A4:3 A4:1 D5:4 F#5:3 E5:1 A5:4 | "
       "B4:3 B4:1 E5:4 G#5:3 F#5:1 B5:4 | "
       "G5:3 G5:1 C6:4 -:8 | "
       "B5:8 F#5:2 G5:1 F#5:1 D#5:2 B4:2")
TAG_HARM = ("F#4:3 F#4:1 B4:4 D5:3 C#5:1 F#5:4 | "
            "G#4:3 G#4:1 B4:4 E5:3 D5:1 G#5:4 | "
            "E5:3 E5:1 A5:4 -:8 | "
            "D#5:8 D#5:2 E5:1 D#5:1 B4:2 F#4:2")
TAG_CHORDS = "Bm7 E7 Am7 B7"

KEY_EM = [4, 6, 7, 9, 11, 0, 2]

# --------------------------------------------------------------- song ---
song = Song("music_battle", bpm=160, bars=64, reverb_seconds=1.6)
song.loop(0)
for bar, text in [(0, "Em Am:0.5 B:0.5 Em Am:0.5 B:0.5"), (4, VERSE_CHORDS), (12, PRE_CHORDS),
                  (20, THEME_CHORDS), (24, THEME_CHORDS), (28, BRIDGE_CHORDS), (36, BREAK_CHORDS),
                  (44, BUILD_CHORDS), (48, THEME_CHORDS),
                  (52, "Cmaj7 Am:0.5 B:0.5 C:0.5 D:0.5 Em:0.75 C#7:0.25"),
                  (56, "F#m Bm:0.5 C#:0.5 D:0.5 E:0.5 F#m"), (60, TAG_CHORDS)]:
    song.chords(bar, text)
for bar, lbl in [(0, "intro"), (4, "verse"), (12, "pre (saw)"), (20, "hook"), (28, "bridge"),
                 (36, "breakdown"), (44, "build"), (48, "climax 1"), (52, "climax 2"), (56, "lift F#m"),
                 (60, "tag")]:
    song.section(bar, lbl)

BAR = 4.0
U = 0.25  # 16ths


def scale_for(chord, key):
    """Key scale with the chord's chromatic tones swapped in."""
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
    """Diatonic 3rds below `src` in bars [b0, b1), 6ths/4ths where the 3rd would be a
    non-chord tone on a strong note (used only for short chant/answer figures)."""
    prev = None
    mode = 2
    for n in sorted([x for x in src.notes if b0 * BAR <= x.beat < b1 * BAR], key=lambda x: x.beat):
        c = song.chord_at(n.beat)
        sc = scale_for(c, KEY_EM)
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
        dst.notes.append(Note(n.beat, float(x), n.beats, n.vel * vel, n.slide))
        prev = x


def chords_in(b0, b1):
    return [(s, e, c) for (s, e, c) in song.harmony if b0 * BAR <= s < b1 * BAR]


def voicing(c, lo=52, hi=67):
    """Close voicing inside [lo, hi]; drops a chord tone that would sit a semitone
    from another one (maj7 chords lose the 7th; the melody carries it)."""
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


def power(root, octv):
    r = midi(f"{root}{octv}")
    return [r, r + 7, r + 12]


# ---------------------------------------------------------- instruments ---
lead = song.track("lead", lead_pulse(cutoff=8000), vol=-7.0, pan=0.0, reverb=0.15, delay=0.1, hp=180)
saw = song.track("saw", lead_saw(cutoff=5000), vol=-6.5, pan=0.0, reverb=0.15, delay=0.1, hp=180)
lead2 = song.track("lead2", lead_pulse(duty=0.5, cutoff=4500, vib_depth=0.14, gain=0.5),
                   vol=-12, pan=-0.25, reverb=0.15, delay=0.06, hp=180)
counter = song.track("counter", lead_fm(), vol=-11, pan=-0.25, reverb=0.15, hp=180)
chip = song.track("chip", arp_pulse(s=0.55, d=0.15, r=0.08, vib_depth=0.12, vib_delay=0.15),
                  vol=-5, pan=0.4, reverb=0.2, delay=0.2, hp=400)
bell_t = song.track("bell", bell(), vol=-9, pan=-0.3, reverb=0.35, delay=0.18, hp=300)
brass_t = song.track("brass", brass(), vol=-12, pan=-0.25, reverb=0.2, hp=150)
GTR = Inst(osc="saw", unison=2, detune=12, spread=0.4, a=0.002, d=0.12, s=0.35, r=0.05,
           q=1.1, fenv=1.6, fdecay=0.05, drive=0.7, gain=0.4, cutoff=2800)
gtr = song.track("gtr", GTR, vol=-10, pan=0.35, reverb=0.08, hp=120, duck=0.2)
gtrL = song.track("gtrL", replace(GTR, detune=9), vol=-10, pan=-0.35, reverb=0.08, hp=120, duck=0.2)
arp = song.track("arp", arp_pulse(), vol=-10, pan=0.4, reverb=0.1, delay=0.15, hp=400, duck=0.2)
pad = song.track("pad", strings(), vol=-9.5, reverb=0.45, duck=0.35, hp=200)
bass = song.track("bass", bass_fm(sub=0.12), vol=-7.3, duck=0.3, hp=32)
bass_chip = song.track("bass_chip", bass_nes(), vol=-16, duck=0.2)
dr = song.drums("drums", vol=-7.2, reverb=0.1)


def levels(tr, pts):
    """Step-wise section gain (dB) for a track: pts = [(bar, dB), ...] in order."""
    pts = list(pts) + [(song.bars, pts[-1][1])]
    for (b0, g), (b1, _) in zip(pts[:-1], pts[1:]):
        tr.automation.append((b0 * BAR, g))
        tr.automation.append((b1 * BAR - 0.02, g))


# dynamics: verse ~2-3 dB under the hook, bridge a little under, breakdown well under,
# climax on top; the lift is pulled back a touch so the F#6 peak doesn't shriek
levels(dr, [(0, 0), (4, -3.0), (8, -2.5), (12, -1.5), (16, -0.5), (20, 0), (28, -1.5), (36, 0), (48, 0.5),
            (60, 0)])
levels(bass, [(0, 0), (4, -2.5), (12, -1.0), (16, -0.5), (20, 0), (28, -1.0), (36, 0), (48, 0.5), (60, 0)])
levels(lead, [(0, 0), (4, -1.5), (12, -0.5), (20, 0), (56, -1.5), (60, 0)])
levels(lead2, [(0, 0), (4, -1.5), (12, -0.5), (20, 0), (44, 2.5), (46, 0), (56, -1.5), (60, 0)])
levels(saw, [(0, 0), (28, -1.0), (48, 0.5)])

# ---------------------------------------------------------------- melody ---
lead.seq(4, VERSE, unit=U)
lead2.seq(8, VERSE_HARM, unit=U, vel=0.8)

saw.seq(12, PRE, unit=U)
lead2.seq(12, PRE_HARM, unit=U, vel=0.8)
for tr in (saw, lead):                       # the hero joins the x stab: hook incoming
    tr.seq(19, STAB, unit=U, vel=0.85)
lead2.seq(19, STAB_HARM, unit=U, vel=0.8)

for b in (20, 24):
    lead.seq(b, MOTIF + " | " + ANSWER, unit=U, transpose=2)
counter.seq(24, HARM, unit=U, transpose=2)

saw.seq(28, BRIDGE_CALL1, unit=U)
lead.seq(30, BRIDGE_ANS1, unit=U)
lead2.seq(30, BRIDGE_HARM1, unit=U, vel=0.8)
saw.seq(32, BRIDGE_CALL2, unit=U)
lead.seq(34, BRIDGE_ANS2, unit=U)
lead2.seq(34, BRIDGE_HARM2, unit=U, vel=0.8)

# build: lead2 + brass chant alone, the hero joins for the last two bars
lead2.seq(44, BUILD12, unit=U, vel=0.85)
harmonize(lead2, 44, 46, brass_t, vel=0.9)
lead.seq(46, BUILD34, unit=U, vel=0.8)
lead2.seq(46, BUILD34_HARM, unit=U, vel=0.75)

# climax 1: the hero shouts each x, the saw (brass an octave below) answers
lead.seq(48, HERO_CALLS, unit=U, transpose=2)
saw.seq(48, BAND_ANS, unit=U, transpose=2, vel=0.9)
brass_t.seq(48, BAND_ANS, unit=U, transpose=2 - 12, vel=0.95)
lead2.seq(48, HARM, unit=U, transpose=2, vel=0.8)
# climax 2: everyone on the full theme
lead.seq(52, MOTIF + " | " + ANSWER_LIFT, unit=U, transpose=2)
lead2.seq(52, HARM_LIFT, unit=U, transpose=2, vel=0.8)
# lift
lead.seq(56, MOTIF + " | " + ANSWER, unit=U, transpose=4)
lead2.seq(56, HARM, unit=U, transpose=4, vel=0.8)
# tag
lead.seq(60, TAG, unit=U)
lead2.seq(60, TAG_HARM, unit=U, vel=0.8)

# intro bars 3-4: the square doubles the bass riff two octaves up (a unison riff)
lead2.seq(2, INTRO_BASS, unit=U, transpose=24, vel=0.7)

# ----------------------------------------------------------------- brass ---
# intro: power-chord "SMASH" stabs on beats 2 and 4 (where the riff lands)
for bar, (c1, o1, c2, o2) in ((2, ("E", 3, "B", 2)), (3, ("A", 2, "B", 2))):
    brass_t.chord(bar, power(c1, o1), beats=0.45, vel=0.85, at=1.0)
    brass_t.chord(bar, power(c2, o2), beats=0.45, vel=0.85, at=3.0)
# pre-chorus x stab with the band
for off, ln in ((0.0, 0.6), (0.75, 0.2), (1.0, 0.8)):
    brass_t.chord(19, power("B", 2), beats=ln, vel=0.9, at=off)
# build bars 47-48: x rhythm power stabs on B under the hero
for bar in (46, 47):
    for half in ((0.0, 2.0) if bar == 46 else (0.0,)):
        for off, ln, v in ((0.0, 0.6, 0.85), (0.75, 0.2, 0.7), (1.0, 0.8, 0.95)):
            brass_t.chord(bar, power("B", 2), beats=ln, vel=v, at=half + off)


def stabs(bar0, bar1, vel=0.75, length=0.45):
    """Power-chord stab on every chord change (roots kept between A2 and G#3)."""
    for s, e, c in chords_in(bar0, bar1):
        root, iv, _ = parse_chord(c)
        o = 2 if root >= 9 else 3
        notes = power(NOTE_NAMES[root], o)
        if 11 in iv:                     # maj7: root-5th-3rd, so the melody's 7th isn't
            notes[2] += 4                # a major 7th above the stab's top root
        brass_t.chord(s / BAR, notes, beats=length, vel=vel)


stabs(52, 56, 0.75)
stabs(56, 60, 0.65)

# ------------------------------------------------------------------ bell ---
# climax 2: octave-up bell only on the quarter-note "SMASH" landings (beats 2 and 4)
for bar, a, b in ((52, "E6", "B6"), (54, "C7", "D7")):
    bell_t.note(bar * BAR + 1.0, a, 1.0, 0.4)
    bell_t.note(bar * BAR + 3.0, b, 1.0, 0.4)

# ------------------------------------------------------------ breakdown ---
# bell calls with x inverted (falls a 5th), the chip pulse answers with the wink
# (5 6 5 3 1 over each chord); 2nd half the twin pulse sneaks in under the winks.
CALLS = ["G5:3 G5:1 C5:4", "D5:3 D5:1 G4:4", "A5:3 A5:1 D5:4", "B5:3 B5:1 E5:4",
         "G5:3 G5:1 C5:4", "D5:3 D5:1 G4:4", "E5:3 E5:1 A4:4", "F#5:3 F#5:1 B4:4"]
WINKS = ["G5:2 A5:1 G5:1 E5:2 C5:2", "D5:2 E5:1 D5:1 B4:2 G4:2", "A5:2 B5:1 A5:1 F#5:2 D5:2",
         "B5:2 C6:1 B5:1 G5:2 E5:2", "G5:2 A5:1 G5:1 E5:2 C5:2", "D5:2 E5:1 D5:1 B4:2 G4:2",
         "E5:2 F#5:1 E5:1 C5:2 A4:2", "F#5:2 G5:1 F#5:1 D#5:2 B4:2"]
for i in range(8):
    bell_t.seq(36 + i, CALLS[i], unit=U, vel=0.75)
    chip.seq(36 + i, WINKS[i], unit=U, at=2.0, vel=0.8)
harmonize(chip, 40, 44, lead2, vel=0.6)

# ---------------------------------------------------------------- bass ---
E3_CEIL = midi("E3")


def gal(root, top2, top4, end=None, root2=None, mid2=None):
    """One bar of NES gallop (8th + two 16ths per beat). Beats 2 and 4 open on a
    'top' note (octave, 3rd, 5th or 7th); `end` replaces the last two 16ths
    (walk into the next chord); `root2` is the root for beats 3-4."""
    r2 = root2 or root
    m2 = mid2 or root
    e = end or (r2, r2)
    toks = [(root, 2), (root, 1), (root, 1), (top2, 2), (m2, 1), (m2, 1),
            (r2, 2), (r2, 1), (r2, 1), (top4, 2), (e[0], 1), (e[1], 1)]
    for n, _ in toks:
        assert midi(n) <= E3_CEIL, f"bass above E3: {n}"
    return " ".join(f"{n}:{d}" for n, d in toks)


bass.seq(0, INTRO_BASS + " | " + INTRO_BASS, unit=U)
# verse: gallop, roots fall E D C B (i-VII-VI-V) with chromatic walks between
bass.seq(4, " | ".join([
    gal("E2", "E3", "E3", end=("E2", "D#2")),
    gal("D2", "A2", "D3", end=("D2", "C#2")),
    gal("C2", "C3", "C3"),
    gal("B1", "B2", "B2", end=("C#2", "D#2")),
    gal("E2", "B2", "B2"),
    gal("D2", "A2", "A2", end=("D2", "C#2")),
    gal("C2", "G2", "B2", root2="B1", end=("C#2", "D#2")),
    gal("E2", "B2", "E3", end=("D2", "C#2")),
]), unit=U)
# pre-chorus: pumping 8ths climbing C D E F# G A, then B
for i, r in enumerate(["C2", "D2", "E2", "F#2", "G2", "A2"]):
    m = midi(r)
    o = m + 12 if m + 12 <= E3_CEIL else m - 12      # G and A bounce down, not up
    bass.seq(12 + i, " ".join(name_of(x) for x in [m, m, o, m, m, m, o, m]), unit=0.5)
bass.seq(18, "B1 B2 B1 B2 B1 B2 B1 B2", unit=0.5)
bass.seq(19, "B1:3 B1:1 B2:4 -:8", unit=U)
# hook: the bible's tested line (5ths on beats 2 and 4 of bar 3); bar 2 an octave
# lower to stay under E3; bar 4 beat 2 = 3rd so lead and bass don't fall 5->1 together
THEME_BASS = ("D2 D3 D2 D3 D2 D3 C3 A2 | G1 G2 G1 G2 A1 A2 A1 A2 | "
              "Bb1 Bb2 F2 Bb2 C2 C3 G2 E2 | D2 D3 F2 D3 D2 D3 A2 A1")
bass.seq(20, THEME_BASS, unit=0.5, transpose=2)
bass.seq(24, THEME_BASS, unit=0.5, transpose=2)
# bridge: lyrical bass in the bridge's own rhythm
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
bass.seq(47, " ".join(["B1", "B1", "B2", "B1"] * 3 + ["B1", "B1", "C#2", "D#2"]), unit=U)  # walk-up into E
# climax 1 (E minor): galloping version of the theme bass. Bar 1 beat 2 opens on
# the 3rd (G2), not the 5th, so it can't move in octaves with lead2's B4->E5.
bass.seq(48, " | ".join([
    gal("E2", "G2", "E3", end=("D2", "B1")),
    gal("A1", "A2", "B2", root2="B1"),
    gal("C2", "G2", "A2", root2="D2", end=("A2", "F#2")),
    gal("E2", "G2", "B2", mid2="G2", end=("B1", "B1")),
]), unit=U)
# climax 2: the bass drops to C under the returning theme (Cmaj7 reharmonisation)
bass.seq(52, " | ".join([
    gal("C2", "G2", "E3", end=("C2", "B1")),
    gal("A1", "A2", "B2", root2="B1"),
    gal("C2", "G2", "A2", root2="D2", end=("A2", "F#2")),
    "E2:2 E2:1 E2:1 G2:2 G2:1 G2:1 E2:2 E2:1 E2:1 C#2:2 C#3:1 G#2:1",
]), unit=U)
# lift (F# minor)
bass.seq(56, " | ".join([
    gal("F#2", "A2", "E3", end=("D2", "C#2")),
    gal("B1", "B2", "C#3", root2="C#2"),
    gal("D2", "A2", "B2", root2="E2", end=("B2", "G#2")),
    gal("F#2", "A2", "C#3", mid2="A2", end=("C#2", "C#2")),
]), unit=U)
# tag: down the circle of fifths, chromatic walk-up into B7, wink walk into the riff
bass.seq(60, " | ".join([
    gal("B1", "F#2", "A2", end=("B1", "D2")),
    gal("E2", "B2", "D3", end=("B1", "G#1")),
    gal("A1", "E2", "G2", end=("A1", "A#1")),
    "B1:2 B1:1 B1:1 B2:2 B1:1 B1:1 B1:2 B1:1 B1:1 A2:2 F#2:1 D#2:1",
]), unit=U)

# ------------------------------------------------------- rhythm guitar ---
def power_in(ch, lo="B2"):
    root = parse_chord(ch)[0]
    r = midi(lo) + (root - midi(lo)) % 12
    return [r, r + 7, r + 12]


# pre-chorus: palm-muted power chords on the off-beat 8ths, double-tracked L/R
for s_, e_, c in chords_in(12, 18):
    for off, vv in ((0.5, 0.8), (1.5, 1.0), (2.5, 0.8), (3.5, 1.0)):
        pc = power_in(c)
        for m in pc[:2]:
            gtrL.note(s_ + off, m, 0.22, 0.5 * vv)
        for m in pc[1:]:
            gtr.note(s_ + off, m, 0.22, 0.5 * vv)

# ----------------------------------------------------------------- arps ---
ARP_SECTIONS = [(2, 4), (16, 19), (24, 28), (36, 44), (44, 48), (48, 64)]
for s0, s1 in ARP_SECTIONS:
    for b0, b1, c in chords_in(s0, s1):
        arp.arp(b0 / BAR, voicing(c, 60, 74), "0 1 2 3 2 1", unit=U, beats=b1 - b0, vel=0.7)
for b0, b1, c in chords_in(8, 12):  # verse answer: the arp creeps in quietly
    arp.arp(b0 / BAR, voicing(c, 60, 74), "0 1 2 3 2 1", unit=U, beats=b1 - b0, vel=0.45)

# ----------------------------------------------------------------- pads ---
PAD_SECTIONS = [(8, 12), (12, 19), (20, 24), (24, 28), (28, 36), (40, 44), (44, 48), (48, 64)]
melodic = [lead, saw, lead2, counter, chip, bass, bass_chip, brass_t, bell_t]


def place_pad(b0, b1, c):
    for p in voicing(c):
        ok = True
        for tr in melodic:
            for n in tr.notes:
                if n.beats < 0.5 or n.beat >= b1 or n.beat + n.beats <= b0:
                    continue
                iv = abs(int(n.m) - p)
                if iv % 12 in (1, 11) and iv < 24:
                    ok = False
                    break
            if not ok:
                break
        if ok:
            pad.note(b0, p, b1 - b0 - 0.08, 0.6)


for s0, s1 in PAD_SECTIONS:
    for b0, b1, c in chords_in(s0, s1):
        place_pad(b0, b1, c)

# --------------------------------------------------------------- drums ---
K_DRIVE = "x.....x.x.....x."
K_X = "x..x..x.x.....x."      # adds the x rhythm's 16th ("Ma-GIC") under the calls
K_FOUR = "x...x...x...x..."
SN = "....x.......x..."
HAT8 = "x.x.x.x.x.x.x.x."
HATG = "x.xox.xox.xox.xo"
OHAT = "..x...x...x...x."
OHAT_UP = "..X...X...X...X."      # hook/climax: a touch louder for presence
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


# intro: kick + chip hats (the breather), then the real kit with a crash
dr.pat(0, {"kick": "x.....x.x.......", "hat_chip": "x.x.x.x.x.x.x.x.", "kick_chip": "x.......x......."}, bars=2)
dr.fill(1, "snare_ snare_ snare snare", at=3.0)
groove(2, 2, hat=HAT8)
dr.hit(2 * BAR, "crash", 0.85)
dr.fill(3, "tom_hi tom_hi tom_mid tom_lo", at=3.0)
dr.hit(0, "crash", 0.8)
# verse: no shaker at first; shaker joins with the second pulse at bar 9
groove(4, 3, hat=HAT8)
groove(7, 1, hat=HAT8)
small_fill(7)
groove(8, 4, hat=HATG)
small_fill(11)
dr.pat(8, {"shaker": ".o.x.o.x.o.x.o.x"}, bars=4)
dr.pat(28, {"shaker": ".o.x.o.x.o.x.o.x"}, bars=8)
for b in (4, 8):
    dr.hit(b * BAR, "crash", 0.75)
# pre-chorus: four on the floor, open hats
groove(12, 6, kick=K_FOUR, hat=HAT8, ohat=OHAT)
small_fill(15)
dr.hit(12 * BAR, "crash", 0.8)
dr.hit(16 * BAR, "crash", 0.7)
groove(18, 1, kick=K_FOUR, hat="xxxxxxxxxxxxxxxx", ohat=OHAT, snare="....x.......x.x.")
# bar 20: stop-time stab with the x rhythm, then the fill
for off in (0.0, 0.75, 1.0):
    dr.hit(19 * BAR + off, "kick", 1.0)
    dr.hit(19 * BAR + off, "snare", 0.8 if off else 0.6)
dr.hit(19 * BAR, "crash", 0.9)
dr.fill(19, "snare_ snare_ snare snare snare snare tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo", at=1.0)
# hook
groove(20, 3, hat=HAT8, ohat=OHAT_UP)
groove(23, 1, hat=HAT8, ohat=OHAT_UP)
small_fill(23)
groove(24, 3, hat=HATG, ohat=OHAT_UP, clap=True)
groove(27, 1, hat=HATG, ohat=OHAT_UP, clap=True)
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
            "kick": "x..............."}, bars=3)
dr.pat(43, {"kick_chip": "x.......", "snare_chip": "........x.x.xxxx", "hat_chip": "xxxxxxxxxxxxxxxx"})
# build: snare 8ths then 16ths, riser into the climax
dr.pat(44, {"kick": K_FOUR, "snare": "x.x.x.x.x.x.x.x.", "hat": HAT8}, bars=2)
dr.pat(46, {"kick": K_FOUR, "snare": "xxxxxxxxxxxxxxxx", "hat": HAT8}, bars=2)
dr.hit(44 * BAR, "crash", 0.7)
dr.hit(48 * BAR - 2.0 * 160 / 60, "riser", 0.9)
dr.fill(47, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=2.0)
# climax 1: kick doubles the x rhythm under the saw/brass calls
for b in (48, 50):
    groove(b, 1, kick=K_X, hat=HATG, ohat=OHAT_UP, clap=True)
groove(49, 1, hat=HATG, ohat=OHAT_UP, clap=True)
groove(51, 1, hat=HATG, ohat=OHAT_UP, clap=True)
small_fill(51)
# climax 2 + lift
groove(52, 3, hat=HATG, ohat=OHAT_UP, clap=True)
groove(55, 1, hat=HATG, ohat=OHAT_UP, clap=True)
dr.fill(55, "snare snare snare snare tom_hi tom_mid tom_lo snare^", unit=0.25, at=2.0)
groove(56, 3, hat=HATG, ohat=OHAT, clap=True)
groove(59, 1, hat=HATG, ohat=OHAT, clap=True)
small_fill(59)
for b in (48, 52, 56, 60):
    dr.hit(b * BAR, "crash", 0.9)
# tag
groove(60, 3, hat=HAT8, ohat=OHAT)
groove(63, 1, hat="x.x.x.x.x.x.x...", ohat="..x...x...x.....")
dr.fill(63, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ -", at=2.0)   # last 16th left quiet: clean seam

if __name__ == "__main__":
    song.render()

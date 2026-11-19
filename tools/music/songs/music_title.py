"""Magic Smash -- TITLE SCREEN / attract mode ("fantasy overture").

Final arrangement, built on candidate A with grafts from candidate B.
D minor, 108 bpm, 40 bars. song.loop(8): the 8-bar night-sky intro plays once,
then bars 9-40 (71 s) loop. The game reads loop_begin from the .wav.import
(tools/music/apply_loops.py).

Form (bars are 1-based, as in the report and piano roll)
  1-8    NIGHT SKY   Dmadd9 Bbmaj7 Gm6 A7sus4 A7. Harp ripples, two-voice choir
                     "oo" on common tones (D-A held while the chord changes under
                     it), bell rings cell x slowly (A A D) and then x' (F E A, the
                     E a Lydian #11 over Bbmaj7). The flute sighs down from the
                     flat 6 and plays the wink; timpani roll + reverse cymbal.
  9-16   HERALD      the full 4-bar theme augmented (8 bars) on the hero pulse
                     lead, brass in 3rds/6ths (HARM), lament bass D-C-Bb-A.
                     Gong on the downbeat. Question phrase: timpani + soft shaker;
                     answer phrase: snare march joins.
  17-24  ROYAL ROAD  lyrical B tune over Bb C7 Am Dm | Gm C F A7, built from x
                     (sequenced down a step, then breaks up to an E6 peak, ends
                     with the wink). Harp 8ths, horn counter in half notes.
  25-32  TUTTI       the theme at its written rhythm, twice. Snare accents land on
                     2 and 4 with the x leap. Second pass is new: lead scoops
                     into the leaps, HARM moves to an FM counter, brass hits
                     "Ma-gic SMASH" stabs with the bass on the x rhythm, open hats,
                     glockenspiel on the accents, tom fill into...
  33-36  FANFARE     x call and response: Bb, then C, then the whole band on
                     A A D6 with the gong; the held D6 fades into...
  37-40  NIGHT FALLS mystery colour again, bell x / x', flute wink over A7,
                     timpani roll + reverse cymbal back into bar 9.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403

INTRO, HERO, ROAD, TUTTI, CODA, NIGHT, END = 0, 8, 16, 24, 32, 36, 40

song = Song("music_title", bpm=108, bars=END, reverb_seconds=2.8, delay_feedback=0.38)
song.loop(HERO)

# ------------------------------------------------------------------ harmony --
song.chords(INTRO, "Dmadd9:2 Bbmaj7:2 Gm6:2 A7sus4 A7")
song.chords(HERO, "Dm Dm/C Gm7/Bb A Bb C Dm:0.75 A:0.25 Dm:0.5 Dm/C:0.5")
song.chords(ROAD, "Bb C7 Am Dm Gm C F A7")
song.chords(TUTTI, "Dm Gm:0.5 A:0.5 Bb:0.5 C:0.5 Dm " * 2)
song.chords(CODA, "Bb C Dm Dm")
song.chords(NIGHT, "Dmadd9 Bbmaj7 Gm6 A7sus4:0.5 A7:0.5")

song.section(INTRO, "night sky")
song.section(HERO, "herald (theme x0.5)")
song.section(ROAD, "royal road B")
song.section(TUTTI, "tutti theme")
song.section(TUTTI + 4, "tutti 2")
song.section(CODA, "fanfare x")
song.section(NIGHT, "night falls")

# ------------------------------------------------------------------- themes --
MOTIF = ("A4:3 A4:1 D5:4 F5:3 E5:1 A5:4 | "
         "Bb5:3 A5:1 G5:2 F5:2 E5:2 F5:1 E5:1 C#5:2 A4:2")
ANSWER = ("F5:3 F5:1 Bb5:4 G5:3 G5:1 C6:4 | "
          "D6:3 C6:1 A5:2 E5:1 C#5:1 D5:8")
# second tutti pass: the same tune, the hero scoops up into each rising 4th
MOTIF_SCOOP = ("A4:3 A4>:1 D5:4 F5:3 E5>:1 A5:4 | "
               "Bb5:3 A5:1 G5:2 F5:2 E5:2 F5:1 E5:1 C#5:2 A4:2")
ANSWER_SCOOP = ("F5:3 F5>:1 Bb5:4 G5:3 G5>:1 C6:4 | "
                "D6:3 C6:1 A5:2 E5:1 C#5:1 D5:8")
HARM = ("F4:3 F4:1 A4:4 D5:3 D5:1 F5:4 | "
        "G5:3 F5:1 D5:2 D5:2 C#5:4 A4:2 E4:2 | "
        "D5:3 D5:1 F5:4 E5:3 E5:1 G5:4 | "
        "A5:3 A5:1 F5:2 C#5:1 A4:1 F4:8")

# B tune, 16ths. Two-bar cell = x rising a 4th + a falling arpeggio, stated over
# Bb-C, sequenced a step down over Am-Dm, started again over Gm and then broken
# upward to the E6 peak; F major "sunrise", and the wink over A7.
ROAD_MEL = ("F5:3 F5:1 Bb5:4 D6:6 C6:2 | Bb5:4 G5:4 E5:6 C5:2 | "      # Bb  C7
            "E5:3 E5:1 A5:4 C6:6 Bb5:2 | A5:4 F5:4 D5:6 A4:2 | "      # Am  Dm
            "D5:3 D5:1 G5:4 Bb5:6 A5:2 | C6:6 D6:2 E6:8 | "           # Gm  C
            "C6:6 A5:2 F5:8 | E5:4 F5:2 E5:2 C#5:4 A4:4")             # F   A7
# horn counter-line under the B tune (moves only where the tune holds)
ROAD_CTR = ("D4:8 F4:8 | E4:8 G4:4 Bb4:4 | E4:8 C4:8 | D4:8 F4:4 E4:2 D4:2 | "
            "D4:8 G4:8 | E4:8 G4:4 C5:4 | A4:8 C5:8 | G4:8 E4:8")

# ---------------------------------------------------------------- voicings --
# strings: pads avoid the note a semitone from the slow theme's passing tones
# (Dm = D-A-D under the F-E dip, A = A-C#-A under the wink, Gm without Bb)
PAD = {
    "Dmadd9": "F3 A3 D4", "Bbmaj7": "D4 F4 A4", "Gm6": "G3 D4 E4",
    "A7sus4": "A3 D4 G4", "A7": "A3 C#4 G4",
    "Dm": "D3 A3 D4", "Dm/C": "C3 A3 D4", "Gm7/Bb": "G3 D4 G4", "Gm": "G3 D4 G4",
    "A": "A3 C#4 A4", "Bb": "Bb3 D4 F4", "C": "G3 C4 E4", "C7": "G3 C4 E4",
    "Am": "A3 C4 E4", "F": "F3 A3 C4",
}
# choir: two upper voices only (keeps the low-mids clear). In the mystery
# progression D4 stays put and A4 -> G4 moves by step, so the chords change
# colour underneath a still choir; sus4 D resolves to C# on A7.
CHOIR = {
    "Dmadd9": "D4 A4", "Bbmaj7": "D4 A4", "Gm6": "D4 G4", "A7sus4": "D4 G4", "A7": "C#4 G4",
    "Dm": "D4 A4", "Gm": "D4 G4", "A": "C#4 E4", "Bb": "D4 F4", "C": "E4 G4",
}
TIMP = {  # timpani are fixed at D2 (timp_lo), G2 (timp), A2 (timp_hi): always a chord tone
    "Dmadd9": ("timp_lo", "timp_hi"), "Bbmaj7": ("timp_lo", "timp_lo"), "Gm6": ("timp", "timp_lo"),
    "A7sus4": ("timp_hi", "timp_lo"), "A7": ("timp_hi", "timp_hi"),
    "Dm": ("timp_lo", "timp_hi"), "Dm/C": ("timp_hi", "timp_hi"), "Gm7/Bb": ("timp", "timp_lo"),
    "Gm": ("timp", "timp_lo"), "A": ("timp_hi", "timp_hi"), "Bb": ("timp_lo", "timp_lo"),
    "C": ("timp", "timp"), "C7": ("timp", "timp"), "Am": ("timp_hi", "timp_hi"), "F": ("timp_hi", "timp_hi"),
}


def chords_in(bar0, bar1):
    b0, b1 = song.bar_beat(bar0), song.bar_beat(bar1)
    return [(s, e, c) for s, e, c in song.harmony if b0 <= s < b1]


def bb(bar, beat=0.0):
    return song.bar_beat(bar) + beat


# ------------------------------------------------------------------- tracks --
lead = song.track("lead", lead_pulse(cutoff=8000), vol=-9, pan=0.05, reverb=0.28, delay=0.12, hp=180)
counter = song.track("counter", lead_fm(), vol=-14, pan=-0.2, reverb=0.15, hp=180)
brass_t = song.track("brass", brass(), vol=-14.5, pan=-0.18, reverb=0.3, hp=150)
bell_t = song.track("bell", bell(), vol=-7, pan=-0.3, reverb=0.4, delay=0.3)
spark = song.track("sparkle", bell(), vol=-12, pan=-0.3, reverb=0.35, delay=0.15, hp=400)
flute_t = song.track("flute", flute(), vol=-10, pan=-0.08, reverb=0.4, delay=0.1, hp=200)
harp_t = song.track("harp", harp(r=0.5), vol=-4.6, pan=0.35, reverb=0.35, hp=150)   # sparkle cap: <= 2% share
strings_t = song.track("strings", strings(), vol=-12, reverb=0.45, hp=200)
choir_t = song.track("choir", choir("oo"), vol=-18, reverb=0.5, hp=250)
bass = song.track("bass", bass_nes(), vol=-12.5, hp=35)   # hp: the sub-octave of F1-Bb1 would sit at 22-29 Hz
timp = song.drums("timpani", vol=-12.5, reverb=0.2)
perc = song.drums("perc", vol=-10, reverb=0.2)
shim = song.drums("shimmer", vol=-7, reverb=0.15)


def steps(tr, points):
    """Step automation: [(bar, dB), ...]; each value holds until the next bar."""
    for i, (bar, d) in enumerate(points):
        b = song.bar_beat(bar)
        if i:
            tr.automation.append((b - 0.05, points[i - 1][1]))
        tr.automation.append((b, d))


def roll(tr, beat, beats, voice, v0, v1, rate=0.25):
    n = int(round(beats / rate))
    for i in range(n):
        tr.hit(beat + i * rate, voice, v0 + (v1 - v0) * i / max(1, n - 1))


def rev_cymbal(end_beat, vel=0.8):
    perc.hit(end_beat - 1.5 * song.bpm / 60.0, "reverse_cymbal", vel)


def ripple(beat, notes, step=0.25, vel=0.55, gate=0.45):
    for i, n in enumerate(notes):
        harp_t.note(beat + i * step, n, gate, vel * (1.0 if i == 0 else 0.85))


def harp_bar(bar, text, vel):
    """One bar of harp written in 16th units ('A5:2' = an 8th). Must total 4 beats."""
    beat = bb(bar)
    for tok in text.split():
        nm, d = (tok.split(":") + ["1"])[:2]
        d = float(d) * 0.25
        harp_t.note(beat, nm, min(0.45, d * 0.9), vel)
        beat += d
    assert abs(beat - bb(bar + 1)) < 1e-6, (bar, text)


def soft_8ths(tr, bar0, bar1, voice, vel):
    for i in range(int((bar1 - bar0) * 8)):
        tr.hit(bb(bar0) + 0.5 * i, voice, vel * (1.15 if i % 2 == 0 else 1.0))


X_HITS = ((0.0, 0.62), (0.75, 0.2), (1.0, 0.9))   # cell x rhythm: (offset beats, length)


def stab_x(bar, at, voicing, vel=0.8):
    """Brass chord stabs on the x rhythm ("Ma-gic SMASH!")."""
    for off, ln in X_HITS:
        for n in voicing.split():
            brass_t.note(bb(bar, at + off), n, ln, vel * (0.8 if off == 0.75 else 1.0))


# Harp ripples, one bar each: a 16th sweep up, settling back in 8ths. The add9
# and maj7 colour notes sit a 7th/9th away from their neighbours (never a
# ringing minor 2nd), and the sweeps step around the bell's and flute's
# passing notes.
HARP = {
    "Dmadd9": "D3 A3 F4 A4 D5 E5 A5 D6 A5:2 E5:2 D5:2 A4:2",
    "Bbmaj7": "Bb2 F3 Bb3 D4 F4 A4 D5 A5 D6:2 A5:2 F5:2 D5:2",
    "Bbmaj7b": "Bb2 F3 Bb3 D4 F4 A4 D5 A5 F5:2 D5:2 A4:2 F4:2",
    "Gm6": "G2 D3 G3 Bb3 D4 E4 G4 D5 D5:2 Bb4:2 G4:2 E4:2",
    "A7sus4": "A2 E3 A3 D4 E4 G4 A4 D5 E5:2 D5:2 A4:2 G4:2",
}

# ====================================================== 1-8 NIGHT SKY (once) ==
# choir "oo" on still common tones + bass pedal; intro notes stop short of
# bar 9 so their tails are not baked into the loop start
for s, e, c in chords_in(INTRO, HERO):
    last = e == bb(HERO)
    for m in CHOIR[c].split():
        choir_t.note(s, m, 2.5 if last else e - s - 0.1, 0.45)
bass.seq(INTRO, "D2:16 | Bb1:16 | G1:16 | A1:8 A1:6", unit=0.5, vel=0.4)
strings_t.fade(INTRO, INTRO + 4, -9, 0)
for s, e, c in chords_in(INTRO + 4, HERO):
    last = e == bb(HERO)
    for m in PAD[c].split():
        strings_t.note(s, m, 3.0 if last else e - s - 0.1, 0.4)

for bar, key, v in ((0, "Dmadd9", 0.5), (1, "Dmadd9", 0.4), (2, "Bbmaj7", 0.5), (3, "Bbmaj7b", 0.4),
                    (4, "Gm6", 0.5), (5, "Gm6", 0.4), (6, "A7sus4", 0.45)):
    harp_bar(bar, HARP[key], v)
ripple(bb(7), ["A2", "E3", "A3", "C#4"], 0.25, 0.4)   # A7 bar: let the flute's wink speak

# bell: cell x slowly (its delay answers it), then x' over Bbmaj7 (E = #11)
bell_t.seq(INTRO, "A5:3 A5:1 D6:4 -:8", unit=0.5, vel=0.75)
bell_t.seq(INTRO + 1, "-:4 E6:3 D6:1", unit=0.5, vel=0.45)          # add9 twinkle
bell_t.seq(INTRO + 2, "F5:3 E5:1 A5:4 -:4 D6:3 C6:1", unit=0.5, vel=0.7)
# flute: sighs down from the flat 6 and then the wink, slowly
flute_t.seq(INTRO + 4, "Bb5:3 A5:1 G5:2 D5:2 | E5:6 -:2 | D5:3 E5:1 G5:4 | E5:2 F5:1 E5:1 C#5:2 A4:1 -:1",
            unit=0.5, vel=0.7)

# timpani: distant thunder
roll(timp, bb(0), 4, "timp_lo", 0.15, 0.45)
timp.hit(bb(1), "timp_lo", 0.4)
timp.hit(bb(2), "timp_lo", 0.5)
timp.hit(bb(4), "timp", 0.5)
timp.hit(bb(6), "timp_hi", 0.55)
roll(timp, bb(7), 2.5, "timp_hi", 0.2, 0.75)   # stops a beat early: its ring must not sit on the loop point
perc.fill(7, "snare_ snare_ snare_ snare snare snare^", at=2.5)          # snare roll carries it to the gong
rev_cymbal(bb(HERO), 0.8)

# ============================================== 9-16 HERALD: theme augmented ==
lead.seq(HERO, MOTIF + " | " + ANSWER, unit=0.5, vel=0.76)
brass_t.seq(HERO, HARM, unit=0.5, vel=0.72)
for s, e, c in chords_in(HERO, ROAD):
    for m in PAD[c].split():
        strings_t.note(s, m, e - s - 0.08, 0.6)
# lament bass D C Bb A, then Bb C D; quarter-note pulse. Bars 13-15 move in
# contrary motion to the brass and lead (no parallel octaves or 5ths), and bar
# 15 lands on A1 for a proper V-i into bar 16.
bass.seq(HERO, "D2 A2 F2 A2 | C2 A2 C3 A2 | Bb1 D2 G2 D2 | A1 A2 E2 C#2 | "
               "Bb1 F2 D2 F2 | C2 G2 E2 G2 | D2 F2 A2 A1 | D2 A2 C3 C2", unit=1.0, vel=0.8)
# harp flourishes under the lead's long notes (beat 3 of the x bars)
ripple(bb(HERO, 2.0), ["D3", "F3", "A3", "D4", "F4", "A4"], 0.25, 0.5)
ripple(bb(HERO + 1, 2.0), ["C3", "F3", "A3", "D4", "F4", "A4"], 0.25, 0.5)
ripple(bb(HERO + 4, 2.0), ["Bb2", "D3", "F3", "Bb3", "D4", "F4"], 0.25, 0.5)
ripple(bb(HERO + 5, 2.0), ["C3", "E3", "G3", "C4", "E4", "G4"], 0.25, 0.5)
ripple(bb(HERO + 7, 1.0), ["D3", "F3", "A3", "D4", "F4", "A4", "D5", "F5"], 0.25, 0.55)
# drums: gong + crash on arrival, timpani on chord tones
timp.hit(bb(HERO), "gong", 0.85)
perc.hit(bb(HERO), "crash", 0.8)
for s, e, c in chords_in(HERO, ROAD):
    a, b2 = TIMP[c]
    timp.hit(s, a, 0.85)
    if e - s >= 4:
        timp.hit(s + 2, b2, 0.55)
# question phrase: timpani + a soft shaker pulse; the snare march joins for the answer
soft_8ths(shim, HERO, HERO + 4, "shaker", 0.3)
perc.fill(HERO + 3, "snare_ snare_ snare_ snare_ snare snare snare^ snare^", at=2.0)
rev_cymbal(bb(HERO + 4), 0.4)
perc.hit(bb(HERO + 4), "crash", 0.55)
MARCH_A = "X..ox.ooX..ox.xo"
MARCH_B = "X..ox.ooX..oxxxx"
for bar in range(HERO + 4, ROAD):
    perc.pat(bar, {"snare": MARCH_A if bar % 2 == 0 else MARCH_B})
shim.pat(HERO + 4, {"shaker": "o.o.o.o.o.o.o.o."}, bars=4)
roll(timp, bb(ROAD - 1, 2), 2, "timp_hi", 0.3, 0.8)    # A2 sits in Dm/C (D2 rubbed on C)

# ========================================================= 17-24 ROYAL ROAD ==
lead.seq(ROAD, ROAD_MEL, unit=0.25, vel=0.62)
brass_t.seq(ROAD, ROAD_CTR, unit=0.25, vel=0.62)
for s, e, c in chords_in(ROAD, TUTTI):
    for m in PAD[c].split():
        strings_t.note(s, m, e - s - 0.08, 0.5)
# bass: roots on the beat, but it walks: C7 drops by step into Am, Gm and C
# move against the horn line, F walks down F-C-A-G into A7, C# leads to D.
bass.seq(ROAD, "Bb1:4 F2:4 Bb2:4 F2:4 | C2:4 G2:4 C3:4 Bb2:4 | A2:4 E2:4 A1:4 E2:4 | D2:4 A2:4 F2:4 D2:4 | "
               "G1:4 D2:4 Bb1:4 D2:4 | C2:4 G2:4 C3:4 G2:2 E2:2 | F2:4 C2:4 A1:4 G1:4 | "
               "A1:4 A2:4 G2:4 E2:2 C#2:2", unit=0.25, vel=0.62)
ROAD_HARP = {"Bb": "Bb2 F3 Bb3 D4 F4 D4 Bb3 F3", "C7": "C3 G3 Bb3 E4 G4 E4 Bb3 G3",
             "Am": "A2 E3 A3 C4 E4 C4 A3 E3", "Dm": "D3 A3 D4 F4 A4 F4 D4 A3",
             "Gm": "G2 D3 G3 Bb3 D4 Bb3 G3 D3", "C": "C3 G3 C4 E4 G4 E4 C4 G3",
             "F": "F2 C3 F3 A3 C4 A3 F3 C3", "A7": "A2 E3 G3 C#4 E4 C#4 G3 E3"}
for s, e, c in chords_in(ROAD, TUTTI):
    for i, n in enumerate(ROAD_HARP[c].split()):
        harp_t.note(s + i * 0.5, n, 0.45, 0.5 if i % 4 == 0 else 0.4)
for s, e, c in chords_in(ROAD, TUTTI):
    a, b2 = TIMP[c]
    timp.hit(s, a, 0.6)
perc.hit(bb(ROAD), "crash", 0.55)
shim.pat(ROAD, {"shaker": "o.x.o.x.o.x.o.xo"}, bars=7)
# phrase join at bar 20 -> 21: soft snare pickup + timpani D -> G
perc.fill(ROAD + 3, "snare_ snare_ snare_ snare", at=3.0)
timp.hit(bb(ROAD + 3, 3.5), "timp_lo", 0.45)
timp.hit(bb(ROAD + 3, 3.75), "timp_lo", 0.55)
perc.fill(TUTTI - 1, "snare_ snare_ snare_ snare_ snare_ snare_ snare snare snare snare snare snare snare^ snare^ snare^ snare^")
roll(timp, bb(TUTTI - 1, 2), 2, "timp_hi", 0.4, 0.9)
rev_cymbal(bb(TUTTI), 0.7)

# ============================================================ 25-32 TUTTI ==
# snare march: the accents (X) land on beats 2 and 4, with the x leap; the
# ghost note before beat 2 echoes the x pickup
MARCH_T = "x..oX.o.x..oX.xo"
TUTTI_BASS = ("D2 D3 D2 D3 D2 D3 C3 A2 | G2 G3 G2 G3 A2 A3 A2 A3 | "
              "Bb1 Bb2 F2 Bb2 C2 C3 G2 E2 | D2 D3 A2 D3 D2 D3 A2 A1")
# pass 2: bass joins the brass on the x rhythm (5ths on beat 2 / beat 4 under
# the lead's Bb and C, as in the bible, so no parallel octaves)
TUTTI_BASS_2 = ("D2:3 D2:1 A2:2 D3:2 D2:3 D2:1 C3:2 A2:2 | G2:2 G3:2 G2:2 G3:2 A2:2 A3:2 A2:2 A3:2 | "
                "Bb1:3 Bb1:1 F2:2 Bb2:2 C2:3 C2:1 G2:2 E2:2 | D2:2 D3:2 A2:2 D3:2 D2:2 D3:2 C3:2 C2:2")

# pass 1: theme + HARM on brass
lead.seq(TUTTI, MOTIF + " | " + ANSWER, unit=0.25, vel=0.85)
brass_t.seq(TUTTI, HARM, unit=0.25, vel=0.85)
bass.seq(TUTTI, TUTTI_BASS, unit=0.5, vel=0.8)
# pass 2: scooped theme, HARM on the FM counter, brass x-stabs
lead.seq(TUTTI + 4, MOTIF_SCOOP + " | " + ANSWER_SCOOP, unit=0.25, vel=0.86)
counter.seq(TUTTI + 4, HARM, unit=0.25, vel=0.8)
bass.seq(TUTTI + 4, TUTTI_BASS_2, unit=0.25, vel=0.8)
stab_x(TUTTI + 4, 0.0, "F3 A3 D4", 0.8)
stab_x(TUTTI + 4, 2.0, "F3 A3 D4", 0.75)
stab_x(TUTTI + 6, 0.0, "F3 Bb3 D4", 0.8)
stab_x(TUTTI + 6, 2.0, "G3 C4 E4", 0.85)
for n in "F3 A3 D4".split():                      # landing on the cadence D
    brass_t.note(bb(TUTTI + 7, 2.0), n, 1.4, 0.75)
# glockenspiel an octave up, only on the accents (the arrival notes of x)
spark.seq(TUTTI + 4, "-:4 D6:4 -:4 A6:3 -:1 | Bb6:3 -:13 | -:4 Bb6:4 -:4 C7:4 | D7:3 -:5 D6:8",
          unit=0.25, vel=0.7)

for s, e, c in chords_in(TUTTI, CODA):
    for m in PAD[c].split():
        strings_t.note(s, m, e - s - 0.08, 0.6)
    for m in CHOIR[c].split():
        choir_t.note(s, m, e - s - 0.08, 0.45 if s < bb(TUTTI + 4) else 0.6)
for s, e, c in chords_in(TUTTI, CODA):
    a, b2 = TIMP[c]
    timp.hit(s, a, 0.85)
    timp.hit(s + 1.5 if e - s >= 4 else s + 1, b2, 0.4)
for k in range(2):
    b = TUTTI + 4 * k
    perc.hit(bb(b), "crash", 0.85)
    for bar in range(b, b + 4):
        perc.pat(bar, {"snare": MARCH_T})
        if k == 0:
            shim.pat(bar, {"shaker": "xoxoxoxoxoxoxoxo", "hat": "..o...o...o...o."})
        else:
            shim.pat(bar, {"shaker": "xoxoxoxoxoxoxoxo", "ohat": "..x...x...x...x."})
perc.hits = [h for h in perc.hits if not (bb(TUTTI + 3, 3.0) <= h[0] < bb(TUTTI + 4) and h[1] == "snare")]
perc.fill(TUTTI + 3, "snare_ snare snare snare^", at=3.0)
# into the fanfare: tom fill over a timpani roll (no snare march under it)
perc.hits = [h for h in perc.hits if not (bb(CODA - 1, 2.0) <= h[0] < bb(CODA) and h[1] == "snare")]
perc.fill(CODA - 1, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=2.0)
roll(timp, bb(CODA - 1, 2), 2, "timp_lo", 0.4, 0.95)

# ========================================================= 33-36 FANFARE x ==
# lead calls x, brass+bass echo it, sequence Bb -> C -> everyone on Dm
lead.seq(CODA, "F5:3 F5:1 Bb5:4 -:8 | G5:3 G5:1 C6:4 -:8 | A5:3 A5:1 D6:28", unit=0.25, vel=0.9)
brass_t.seq(CODA, "D5:3 D5:1 F5:4 F4:3 F4:1 Bb4:4 | E5:3 E5:1 G5:4 G4:3 G4:1 C5:4 | F5:3 F5:1 F5:12",
            unit=0.25, vel=0.85)
brass_t.seq(CODA, "-:8 D4:3 D4:1 F4:4 | -:8 E4:3 E4:1 G4:4 | D5:3 D5:1 A4:12", unit=0.25, vel=0.7)
bass.seq(CODA, "Bb1:3 Bb1:1 Bb1:4 F1:3 F1:1 Bb1:4 | C2:3 C2:1 C2:4 G1:3 G1:1 C2:4 | D2:3 D2:1 D2:12",
         unit=0.25, vel=0.85)
bass.seq(CODA + 3, "D2:16", unit=0.25, vel=0.6)    # relaxes with the held D6
for s, e, c in chords_in(CODA, NIGHT):
    for m in PAD[c].split():
        strings_t.note(s, m, e - s - 0.08, 0.65)
    for m in CHOIR[c].split():
        choir_t.note(s, m, e - s - 0.08, 0.6 if c != "Dm" or s < bb(CODA + 3) else 0.45)
for bar, v in ((CODA, "timp_lo"), (CODA + 1, "timp")):
    for off, vel in ((0, 0.75), (1.0, 0.8), (2.0, 0.45), (2.75, 0.4), (3.0, 0.6)):
        timp.hit(bb(bar, off), v, vel)
    perc.pat(bar, {"snare": "X..xX...x..xX..."})
    shim.pat(bar, {"shaker": "xoxoxoxoxoxoxoxo"})
perc.hit(bb(CODA), "crash", 0.8)
timp.hit(bb(CODA + 2), "timp_lo", 0.8)
timp.hit(bb(CODA + 2, 0.75), "timp_lo", 0.6)
timp.hit(bb(CODA + 2, 1.0), "timp_lo", 0.9)
timp.hit(bb(CODA + 2, 1.0), "gong", 0.85)
perc.hit(bb(CODA + 2, 1.0), "crash", 0.95)
roll(timp, bb(CODA + 2, 2), 6, "timp_lo", 0.45, 0.1)
ripple(bb(CODA + 3), ["D6", "A5", "F5", "D5", "A4", "F4", "D4", "A3", "F3", "D3"], 0.25, 0.5)
# the held D6 relaxes over bar 36 so the night can fall
lead.automation += [(bb(CODA + 3), 0.0), (bb(NIGHT) - 0.02, -6.0), (bb(NIGHT), 0.0)]

# ====================================================== 37-40 NIGHT FALLS ==
for s, e, c in chords_in(NIGHT, END):
    last = e == bb(END)
    for m in CHOIR[c].split():
        choir_t.note(s, m, 1.5 if last else e - s - 0.1, 0.45)
    for m in ("D4 A4" if c == "Bbmaj7" else PAD[c]).split():   # no F under the bell's E5
        strings_t.note(s, m, 1.5 if last else e - s - 0.1, 0.35)
bass.seq(NIGHT, "D2:16 | Bb1:16 | G1:16 | A1:16", unit=0.25, vel=0.42)
harp_bar(NIGHT, HARP["Dmadd9"], 0.45)
harp_bar(NIGHT + 1, HARP["Bbmaj7"], 0.45)
harp_bar(NIGHT + 2, HARP["Gm6"], 0.45)
ripple(bb(NIGHT + 3), ["A2", "E3", "A3", "D4", "E4", "G4", "A4"], 0.25, 0.4)   # sus4 D stays low, gone before A7
bell_t.seq(NIGHT, "A5:3 A5:1 D6:4", unit=0.5, vel=0.7)
bell_t.seq(NIGHT + 1, "F5:3 E5:1 A5:4", unit=0.5, vel=0.6)
flute_t.seq(NIGHT + 2, "Bb5:3 A5:1 G5:2 D5:2", unit=0.5, vel=0.7)
flute_t.seq(NIGHT + 3, "G5:4 D5:4 E5:2 F5:1 E5:1 C#5:2 A4:2", unit=0.25, vel=0.75)
timp.hit(bb(NIGHT), "timp_lo", 0.45)
timp.hit(bb(NIGHT + 2), "timp", 0.45)
roll(timp, bb(NIGHT + 3), 4, "timp_hi", 0.15, 0.85)
rev_cymbal(bb(END) - 0.08, 0.8)   # peaks a hair before the seam so the loop point is quiet

# ----------------------------------------------------------- dynamics ---
steps(brass_t, [(INTRO, 0.0), (CODA, 1.5), (NIGHT, 0.0)])     # brass leads only in the fanfare
steps(harp_t, [(INTRO, 0.0), (HERO, -5.0), (ROAD, -4.0), (TUTTI, -6.0), (CODA + 3, 0.0)])
# the bloom: the herald's question phrase holds back, the answer and the tutti
# open up, and the second tutti pass is the loudest part of the loop
steps(bass, [(INTRO, 0.0), (HERO, -1.5), (HERO + 4, -0.5), (ROAD, -1.0), (TUTTI, 0.0), (TUTTI + 4, 0.5),
             (CODA, 0.0)])
steps(timp, [(INTRO, 0.0), (HERO, -1.5), (HERO + 4, -0.5), (ROAD, 0.0), (TUTTI + 4, 0.5), (NIGHT, 0.0)])
steps(perc, [(INTRO, 0.0), (HERO + 4, 1.0), (ROAD, 0.0), (TUTTI, 1.5), (NIGHT, 0.0)])

if __name__ == "__main__":
    song.render()

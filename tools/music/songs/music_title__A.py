"""Magic Smash -- TITLE SCREEN, angle A: "fantasy overture".

D minor, 108 bpm, 40 bars. song.loop(8): the 8-bar night-sky intro plays once,
then bars 9-40 (71 s) loop.

Form (bars are 1-based, as in the report and piano roll)
  1-8    NIGHT SKY   Dmadd9 Bbmaj7 Gm6 A7sus4 A7. Harp ripples, choir "oo",
                     bell rings cell x slowly (A A D, then F F Bb), the flute
                     sighs down from the flat 6 and plays the wink. Timpani roll +
                     reverse cymbal into...
  9-16   HERALD      the full 4-bar theme augmented (8 bars) on the hero pulse
                     lead, brass in 3rds/6ths (HARM), strings, snare march,
                     timpani, lament bass D-C-Bb-A. Gong on the downbeat.
  17-24  ROYAL ROAD  new lyrical B tune in the relative-major colour over the
                     JRPG "royal road" Bb C Am Dm | Gm C F A7. Built from x: x
                     rises a 4th, an arpeggio falls; the pair is sequenced down a
                     step, the third time it breaks upward to an E6 peak, then
                     the wink hands back to the theme. Harp 8ths, horn counter.
  25-32  TUTTI       the theme at its written (battle) rhythm, twice; second time
                     with bell octave-up, chip arps and choir.
  33-36  FANFARE     "Ma-gic SMASH!" call and response: x stabs on Bb, C, then
                     the whole band on A A D6 with the gong.
  37-40  NIGHT FALLS mystery colour again in 1-bar chords, bell x, the wink at
                     its original speed over A7, timpani roll + reverse cymbal
                     back into bar 9.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403

OUT = os.path.join(HERE, "out", "candidates")

INTRO, HERO, ROAD, TUTTI, CODA, NIGHT, END = 0, 8, 16, 24, 32, 36, 40

song = Song("music_title__A", bpm=108, bars=END, reverb_seconds=2.8, delay_feedback=0.38)
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
song.section(CODA, "fanfare x")
song.section(NIGHT, "night falls")

# ------------------------------------------------------------------- themes --
MOTIF = ("A4:3 A4:1 D5:4 F5:3 E5:1 A5:4 | "
         "Bb5:3 A5:1 G5:2 F5:2 E5:2 F5:1 E5:1 C#5:2 A4:2")
ANSWER = ("F5:3 F5:1 Bb5:4 G5:3 G5:1 C6:4 | "
          "D6:3 C6:1 A5:2 E5:1 C#5:1 D5:8")
HARM = ("F4:3 F4:1 A4:4 D5:3 D5:1 F5:4 | "
        "G5:3 F5:1 D5:2 D5:2 C#5:4 A4:2 E4:2 | "
        "D5:3 D5:1 F5:4 E5:3 E5:1 G5:4 | "
        "A5:3 A5:1 F5:2 C#5:1 A4:1 F4:8")

# B tune, 16ths. Two-bar cell = x rising a 4th + a falling arpeggio, stated over
# Bb-C, sequenced a step down over Am-Dm, started again over Gm and then broken
# upward to the E6 peak; F major arpeggio "sunrise", and the wink over A7.
ROAD_MEL = ("F5:3 F5:1 Bb5:4 D6:6 C6:2 | Bb5:4 G5:4 E5:6 C5:2 | "      # Bb  C7
            "E5:3 E5:1 A5:4 C6:6 Bb5:2 | A5:4 F5:4 D5:6 A4:2 | "      # Am  Dm
            "D5:3 D5:1 G5:4 Bb5:6 A5:2 | C6:6 D6:2 E6:8 | "           # Gm  C
            "C6:6 A5:2 F5:8 | E5:4 F5:2 E5:2 C#5:4 A4:4")             # F   A7
# horn counter-line under the B tune (half notes, contrary motion)
# (it moves only where the tune holds a long note)
ROAD_CTR = ("D4:8 F4:8 | E4:8 G4:4 Bb4:4 | E4:8 C4:8 | D4:8 F4:4 E4:2 D4:2 | "
            "D4:8 G4:8 | E4:8 G4:4 C5:4 | A4:8 C5:8 | G4:8 E4:8")

# ---------------------------------------------------------------- voicings --
# pads avoid the note a semitone from the slow theme's passing tones
# (Dm = D-A-D under the F-E dip, A = A-C#-A under the wink, Gm without Bb)
PAD = {
    "Dmadd9": "F3 A3 D4", "Bbmaj7": "D4 F4 A4", "Gm6": "G3 D4 E4",
    "A7sus4": "A3 D4 G4", "A7": "A3 C#4 G4",
    "Dm": "D3 A3 D4", "Dm/C": "C3 A3 D4", "Gm7/Bb": "G3 D4 G4", "Gm": "G3 D4 G4",
    "A": "A3 C#4 A4", "Bb": "Bb3 D4 F4", "C": "G3 C4 E4", "C7": "G3 C4 E4",
    "Am": "A3 C4 E4", "F": "F3 A3 C4",
}
TIMP = {  # timpani are fixed at D2 (timp_lo), G2 (timp), A2 (timp_hi)
    "Dmadd9": ("timp_lo", "timp_hi"), "Bbmaj7": ("timp_lo", "timp_lo"), "Gm6": ("timp", "timp_lo"),
    "A7sus4": ("timp_hi", "timp_lo"), "A7": ("timp_hi", "timp_hi"),
    "Dm": ("timp_lo", "timp_hi"), "Dm/C": ("timp_lo", "timp_hi"), "Gm7/Bb": ("timp", "timp_lo"),
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
brass_t = song.track("brass", brass(), vol=-13, pan=-0.18, reverb=0.3, hp=150)
bell_t = song.track("bell", bell(), vol=-7, pan=-0.3, reverb=0.4, delay=0.3)
spark = song.track("sparkle", bell(), vol=-12, pan=-0.3, reverb=0.35, delay=0.15, hp=400)
flute_t = song.track("flute", flute(), vol=-10, pan=-0.08, reverb=0.4, delay=0.12, hp=200)
harp_t = song.track("harp", harp(r=0.9), vol=-4, pan=0.35, reverb=0.35, hp=150)
arp = song.track("arp", arp_pulse(), vol=-3, pan=0.35, delay=0.18, hp=400)
strings_t = song.track("strings", strings(), vol=-12, reverb=0.45, hp=200)
choir_t = song.track("choir", choir("oo"), vol=-16, reverb=0.5, hp=200)
bass = song.track("bass", bass_nes(), vol=-13)
timp = song.drums("timpani", vol=-11, reverb=0.2)
perc = song.drums("perc", vol=-10, reverb=0.2)
shim = song.drums("shimmer", vol=-7, reverb=0.15)


def auto(tr, points):
    """Step automation: [(bar, dB), ...]; each value holds until the next bar."""
    for i, (bar, d) in enumerate(points):
        b = song.bar_beat(bar)
        if i:
            tr.automation.append((b - 0.05, points[i - 1][1]))
        tr.automation.append((b, d))


auto(harp_t, [(INTRO, 0), (HERO, -5), (ROAD, -3), (TUTTI, -6), (CODA + 3, 0)])


def roll(tr, beat, beats, voice, v0, v1, rate=0.25):
    n = int(round(beats / rate))
    for i in range(n):
        tr.hit(beat + i * rate, voice, v0 + (v1 - v0) * i / max(1, n - 1))


def rev_cymbal(end_beat, vel=0.8):
    perc.hit(end_beat - 1.5 * song.bpm / 60.0, "reverse_cymbal", vel)


def ripple(beat, notes, step=0.25, vel=0.55, gate=0.45):
    for i, n in enumerate(notes):
        harp_t.note(beat + i * step, n, gate, vel * (1.0 if i == 0 else 0.85))


# ====================================================== 1-8 NIGHT SKY (once) ==
# choir "oo" + bass pedal; pads breathe in
for s, e, c in chords_in(INTRO, HERO):
    for m in PAD[c].split():
        choir_t.note(s, m, e - s - (0.9 if e == bb(HERO) else 0.1), 0.4)
# intro notes stop just short of bar 9 so their releases are not baked into the
# loop start (the body's own ending tail is wrapped there instead)
bass.seq(INTRO, "D2:16 | Bb1:16 | G1:16 | A1:8 A1:6", unit=0.5, vel=0.4)
strings_t.fade(INTRO, INTRO + 4, -9, 0)
for s, e, c in chords_in(INTRO + 4, HERO):
    for m in PAD[c].split():
        strings_t.note(s, m, e - s - (0.9 if e == bb(HERO) else 0.1), 0.4)

# harp ripples: up a 16th sweep, settle back in 8ths (madd9 / maj7 colour notes
# live only in the harp and bell, the sustained parts keep plain triads)
HARP_INTRO = {
    "Dmadd9": "D3 A3 E4 F4 A4 D5 E5 F5 | A5:2 E5:2 D5:2 A4:2 F4:2 E4:2 D4:4",
    "Bbmaj7": "Bb2 F3 A3 D4 F4 A4 Bb4 D5 | F5:2 D5:2 A4:2 F4:2 D4:2 A3:2 F3:4",
    "Gm6": "G2 D3 G3 Bb3 D4 E4 G4 Bb4 | D5:2 Bb4:2 G4:2 E4:2 D4:2 Bb3:2 G3:4",
    "A7sus4": "A2 E3 A3 D4 E4 G4 A4 D5 | E5:2 D5:2 A4:2 G4:2 E4:2 D4:2 A3:4",
}
for bar, c in ((0, "Dmadd9"), (2, "Bbmaj7"), (4, "Gm6"), (6, "A7sus4")):
    for k in range(2):
        b = bb(bar + k)
        if bar == 6 and k == 1:   # A7 bar: let the flute's wink speak; harp only a soft sweep
            ripple(b, ["A2", "E3", "A3", "C#4", "E4", "G4"], 0.25, 0.4)
            continue
        txt = HARP_INTRO[c]
        beat = b
        for tok in txt.replace("|", " ").split():
            nm, d = (tok.split(":") + ["1"])[:2]
            d = float(d) * 0.25
            harp_t.note(beat, nm, min(0.45, d * 0.9), 0.5 if k == 0 else 0.4)
            beat += d

# bell: cell x, slowed down, and its delay answers it
bell_t.seq(INTRO, "A5:3 A5:1 D6:4 -:8", unit=0.5, vel=0.75)
bell_t.seq(INTRO + 1, "-:4 E6:3 D6:1", unit=0.5, vel=0.45)          # add9 twinkle
bell_t.seq(INTRO + 2, "A5:3 A5:1 D6:4 -:4 D6:3 C6:1", unit=0.5, vel=0.7)  # same x, now the A is a maj7
# flute: sighs down from the flat 6 and then the wink, slowly
flute_t.seq(INTRO + 4, "Bb5:3 A5:1 G5:2 D5:2 | E5:6 -:2 | D5:3 E5:1 G5:4 | E5:2 F5:1 E5:1 C#5:2 A4:1 -:1",
            unit=0.5, vel=0.7)

# timpani: distant thunder
roll(timp, bb(0), 4, "timp_lo", 0.15, 0.45)
timp.hit(bb(1), "timp_lo", 0.4)
timp.hit(bb(2), "timp_lo", 0.5)
timp.hit(bb(4), "timp", 0.5)
timp.hit(bb(6), "timp_hi", 0.55)
roll(timp, bb(7), 3, "timp_hi", 0.2, 0.8)
rev_cymbal(bb(HERO), 0.8)

# ============================================== 9-16 HERALD: theme augmented ==
lead.seq(HERO, MOTIF + " | " + ANSWER, unit=0.5, vel=0.76)
brass_t.seq(HERO, HARM, unit=0.5, vel=0.7)
for s, e, c in chords_in(HERO, ROAD):
    for m in PAD[c].split():
        strings_t.note(s, m, e - s - 0.08, 0.6)
# lament bass D C Bb A, then Bb C D; quarter-note pulse with walk-ups
bass.seq(HERO, "D2 A2 F2 A2 | C2 A2 C3 A2 | Bb1 D2 G2 D2 | A1 A2 E2 C#2 | "
               "Bb1 D2 F2 D2 | C2 E2 G2 E2 | D2 A2 F2 A1 | D2 A2 C3 C2", unit=1.0, vel=0.8)
# harp flourishes where the lead holds a long note (kept below the lead)
ripple(bb(HERO, 2.5), ["D3", "F3", "A3", "D4", "F4", "A4"], 0.25, 0.5)
ripple(bb(HERO + 1, 2.5), ["F3", "A3", "D4", "F4", "A4", "D5"], 0.25, 0.5)
ripple(bb(HERO + 4, 2.5), ["Bb2", "D3", "F3", "Bb3", "D4", "F4"], 0.25, 0.5)
ripple(bb(HERO + 5, 2.5), ["C3", "E3", "G3", "C4", "E4", "G4"], 0.25, 0.5)
ripple(bb(HERO + 7, 1.0), ["D3", "F3", "A3", "D4", "F4", "A4", "D5", "F5"], 0.25, 0.55)
# drums: gong + crash on arrival, timpani on chord tones, snare march
timp.hit(bb(HERO), "gong", 0.75)
perc.hit(bb(HERO), "crash", 0.8)
for s, e, c in chords_in(HERO, ROAD):
    a, b2 = TIMP[c]
    timp.hit(s, a, 0.85)
    if e - s >= 4:
        timp.hit(s + 2, b2, 0.6)
MARCH = "X..ox.ooX..ox.xo"
# question phrase: timpani only; the snare march joins for the answer phrase
perc.fill(HERO + 3, "snare_ snare_ snare_ snare_ snare snare snare^ snare^", at=2.0)
for bar in range(HERO + 4, ROAD):
    perc.pat(bar, {"snare": MARCH if bar % 2 == 0 else "X..ox.ooX..oxxxx"})
shim.pat(HERO + 4, {"shaker": "o.o.o.o.o.o.o.o."}, bars=4)
roll(timp, bb(ROAD - 1, 2), 2, "timp_lo", 0.3, 0.8)

# ========================================================= 17-24 ROYAL ROAD ==
lead.seq(ROAD, ROAD_MEL, unit=0.25, vel=0.68)
brass_t.seq(ROAD, ROAD_CTR, unit=0.25, vel=0.62)
for s, e, c in chords_in(ROAD, TUTTI):
    for m in PAD[c].split():
        strings_t.note(s, m, e - s - 0.08, 0.7)
bass.seq(ROAD, "Bb1:4 F2:4 Bb2:4 F2:4 | C2:4 G2:4 C3:4 Bb2:4 | A1:4 E2:4 A2:4 E2:4 | D2:4 A2:4 D3:4 A2:4 | "
               "G1:4 D2:4 G2:4 D2:4 | C2:4 G2:4 C3:4 G2:2 E2:2 | F2:4 C2:4 A1:4 G1:4 | "
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
perc.pat(ROAD + 4, {"snare": "............o.o."})
perc.fill(TUTTI - 1, "snare_ snare_ snare_ snare_ snare_ snare_ snare snare snare snare snare snare snare^ snare^ snare^ snare^")
roll(timp, bb(TUTTI - 1, 2), 2, "timp_hi", 0.4, 0.9)
rev_cymbal(bb(TUTTI), 0.7)

# ============================================================ 25-32 TUTTI ==
for k in range(2):
    b = TUTTI + 4 * k
    lead.seq(b, MOTIF + " | " + ANSWER, unit=0.25, vel=0.85)
    brass_t.seq(b, HARM, unit=0.25, vel=0.85)
    bass.seq(b, "D2 D3 D2 D3 D2 D3 C3 A2 | G2 G3 G2 G3 A2 A3 A2 A3 | "
                "Bb1 Bb2 F2 Bb2 C2 C3 G2 E2 | D2 D3 A2 D3 D2 D3 " + ("A2 A1" if k == 0 else "C3 C2"),
             unit=0.5, vel=0.8)
    perc.hit(bb(b), "crash", 0.85)
    for bar in range(b, b + 4):
        perc.pat(bar, {"snare": MARCH})
        shim.pat(bar, {"shaker": "xoxoxoxoxoxoxoxo", "hat": "..o...o...o...o." if k == 0 else "..x...x...x...x."})
spark.seq(TUTTI + 4, MOTIF + " | " + ANSWER, unit=0.25, transpose=12, vel=0.7)
for s, e, c in chords_in(TUTTI, CODA):
    for m in PAD[c].split():
        strings_t.note(s, m, e - s - 0.08, 0.75)
for s, e, c in chords_in(TUTTI, CODA):
    for m in PAD[c].split():
        choir_t.note(s, m, e - s - 0.08, 0.45 if s < bb(TUTTI + 4) else 0.55)
for s, e, c in chords_in(TUTTI + 4, CODA):
    arp.arp(s / 4, chord_tones(c, 4), "0 1 2 3 2 1", unit=0.25, beats=e - s, vel=0.6)
for s, e, c in chords_in(TUTTI, CODA):
    a, b2 = TIMP[c]
    timp.hit(s, a, 0.85)
    timp.hit(s + 1.5 if e - s >= 4 else s + 1, b2, 0.5)
perc.fill(TUTTI + 3, "snare_ snare snare snare^", at=3.0)
perc.fill(CODA - 1, "snare snare snare snare snare^ snare^ snare^ snare^", at=2.0)
roll(timp, bb(CODA - 1, 2), 2, "timp_lo", 0.4, 0.95)

# ========================================================= 33-36 FANFARE x ==
# lead calls x, brass+bass echo it, sequence Bb -> C -> everyone on Dm
lead.seq(CODA, "F5:3 F5:1 Bb5:4 -:8 | G5:3 G5:1 C6:4 -:8 | A5:3 A5:1 D6:28", unit=0.25, vel=0.9)
brass_t.seq(CODA, "D5:3 D5:1 F5:4 F4:3 F4:1 Bb4:4 | E5:3 E5:1 G5:4 G4:3 G4:1 C5:4 | F5:3 F5:1 F5:12",
            unit=0.25, vel=0.85)
brass_t.seq(CODA, "-:8 D4:3 D4:1 F4:4 | -:8 E4:3 E4:1 G4:4 | D5:3 D5:1 A4:12", unit=0.25, vel=0.7)
bass.seq(CODA, "Bb1:3 Bb1:1 Bb1:4 F1:3 F1:1 Bb1:4 | C2:3 C2:1 C2:4 G1:3 G1:1 C2:4 | D2:3 D2:1 D2:12 | D2:16",
         unit=0.25, vel=0.85)
for s, e, c in chords_in(CODA, NIGHT):
    for m in PAD[c].split():
        strings_t.note(s, m, e - s - 0.08, 0.65)
    for m in PAD[c].split():
        choir_t.note(s, m, e - s - 0.08, 0.5 if c != "Dm" or s < bb(CODA + 3) else 0.4)
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

# ====================================================== 37-40 NIGHT FALLS ==
for s, e, c in chords_in(NIGHT, END):
    for m in PAD[c].split():
        choir_t.note(s, m, e - s - 0.1, 0.42)
        strings_t.note(s, m, e - s - 0.1, 0.35)
bass.seq(NIGHT, "D2:16 | Bb1:16 | G1:16 | A1:16", unit=0.25, vel=0.42)
for bar, c in ((NIGHT, "Dmadd9"), (NIGHT + 1, "Bbmaj7"), (NIGHT + 2, "Gm6")):
    beat = bb(bar)
    for tok in HARP_INTRO[c].replace("|", " ").split():
        nm, d = (tok.split(":") + ["1"])[:2]
        d = float(d) * 0.25
        harp_t.note(beat, nm, min(0.45, d * 0.9), 0.45)
        beat += d
ripple(bb(NIGHT + 3), ["A2", "E3", "A3", "D4", "E4", "G4", "A4", "D5"], 0.25, 0.4)
bell_t.seq(NIGHT, "A5:3 A5:1 D6:4", unit=0.5, vel=0.7)
bell_t.seq(NIGHT + 1, "A5:3 A5:1 D6:4", unit=0.5, vel=0.6)
flute_t.seq(NIGHT + 2, "Bb5:3 A5:1 G5:2 D5:2", unit=0.5, vel=0.7)
flute_t.seq(NIGHT + 3, "G5:4 D5:4 E5:2 F5:1 E5:1 C#5:2 A4:2", unit=0.25, vel=0.75)
timp.hit(bb(NIGHT), "timp_lo", 0.45)
timp.hit(bb(NIGHT + 2), "timp", 0.45)
roll(timp, bb(NIGHT + 3), 4, "timp_hi", 0.15, 0.85)
rev_cymbal(bb(END) - 0.08, 0.8)   # peaks a hair before the seam so the loop point is quiet

if __name__ == "__main__":
    song.render(out_dir=OUT)

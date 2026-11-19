"""Magic Smash -- MAIN BATTLE LOOP, angle A: "Genesis FM rock".

E minor (theme transpose +2), 160 bpm, 64 bars = 96 s, loop(0) (whole song loops,
the intro riff is the "reset" after the climax).

Form (bars 1-based, as in the report / piano roll)
  1-4    INTRO RIFF   bass_fm states cell x three octaves down (B B E, G F# B),
                      double-tracked overdriven "guitar" in octaves above it (2nd
                      time + a chip-pulse double), brass power-chord stabs on the
                      "SMASH" beats, riff-locked kick.
  5-12   VERSE A      new tune on the fat saw lead. Every bar = cell x turned
                      downward ("da-da DUM": G G E) + a rising-4th pickup that lands
                      on the snare (D->G). Question: descending sequence over
                      Em7 D C, half cadence on B7. Answer: x' (half-step dip + 4th)
                      climbs by step over Am7 D G, peak B5, falling line on B7.
                      Palm-muted power-chord chugs on the off-beat 8ths.
  13-20  VERSE A2     same tune (pickups now slide up), FM counter harmonises the x-cells in 3rds/6ths
                      (tutti "da-da DUM", solo pickup), 16th hats, arps, pads.
                      Last bar climbs the B7 arpeggio, big tom fill.
  21-28  HOOK B       "Ma-gic SMASH!" theme x2 on the hero pulse lead. Off-beat
                      open hats; 2nd time + HARM on lead_fm, clap, brass, arps.
  29-36  CIRCLE C     twin-lead (saw + FM a 3rd below) plays x AUGMENTED down the
                      circle of 5ths Am7 D7 G C F#m7b5 B7 Em7: odd bars x rises
                      7th->3rd by a 4th, even bars fall through the chord (guide
                      tones). Ride cymbal. Ends on B7 with a stop.
  37-44  BREAKDOWN    deceptive cadence to C. Half-time chip kit + NES bass in the
                      relative-major colour C G D Em. Chip pulse plays x inverted
                      (falls a 5th), bell and arp trade the wink (5-6-5-3-1).
                      Bars 43-44: the hero's x rises again (motif bar 1).
  45-48  BUILD        C D E C#7: brass x stabs climb, kick 4/4, snare 8ths -> 16ths,
                      riser, lead run down C#7 into...
  49-56  CLIMAX B'    theme x2 lifted to F# minor: pulse + saw unison, HARM, bell
                      sparkle on the landing notes, brass stabs, clap.
  57-64  CIRCLE C'    the circle again in F# minor, hero lead on top; it keeps
                      falling in 5ths F#m7 -> B7 -> (loop) Em, tom fill turnaround.

Mix notes: lead/saw/chip are the melody voices (~28% of energy together), bass_fm
~20%, drums ~35%; pads, arps and bell stay at 0.5-2%. Pads are pruned automatically
where they would rub a semitone against a sustained melody/bass note. Section level
automation keeps the verse ~2.5 dB and the breakdown ~5 dB under the hook. The last
8th of the loop is left quiet (fill ends early) so the seam is click-free.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403

OUT = os.path.join(HERE, "out", "candidates")

INTRO, A1, A2, B, C, BRK, BUILD, B2, C2, END = 0, 4, 12, 20, 28, 36, 44, 48, 56, 64

song = Song("music_battle__A", bpm=160, bars=END, reverb_seconds=1.6, delay_feedback=0.3)
song.loop(0)


def bb(bar, beat=0.0):
    return song.bar_beat(bar) + beat


# ------------------------------------------------------------------ harmony --
VERSE_CH = "Em7 D C B7 Am7 D G B7"
THEME_E = "Em Am:0.5 B:0.5 C:0.5 D:0.5 Em"
THEME_FS = "F#m Bm:0.5 C#:0.5 D:0.5 E:0.5 F#m"
song.chords(INTRO, "Em C:0.5 D:0.5 Em C:0.5 B7:0.5")
song.chords(A1, VERSE_CH)
song.chords(A2, VERSE_CH)
song.chords(B, THEME_E + " " + THEME_E)
song.chords(C, "Am7 D7 G C F#m7b5 B7 Em7 B7")
song.chords(BRK, "C G D Em C G D Em")
song.chords(BUILD, "C D E C#7sus4:0.5 C#7:0.5")
song.chords(B2, THEME_FS + " " + THEME_FS)
song.chords(C2, "Bm7 E7 A D G#m7b5 C#7 F#m7 B7")

song.section(INTRO, "intro riff")
song.section(A1, "verse A")
song.section(A2, "verse A2")
song.section(B, "hook B")
song.section(C, "circle C")
song.section(BRK, "chip breakdown")
song.section(BUILD, "build")
song.section(B2, "climax F#m")
song.section(C2, "circle C' >B7")


def chords_in(bar0, bar1):
    b0, b1 = bb(bar0), bb(bar1)
    return [(s, e, c) for s, e, c in song.harmony if b0 <= s < b1]


# ------------------------------------------------------------------- themes --
# leitmotif from SOUNDTRACK.md, reference key D minor (transpose +2 = E, +4 = F#)
MOTIF = ("A4:3 A4:1 D5:4 F5:3 E5:1 A5:4 | "
         "Bb5:3 A5:1 G5:2 F5:2 E5:2 F5:1 E5:1 C#5:2 A4:2")
ANSWER = ("F5:3 F5:1 Bb5:4 G5:3 G5:1 C6:4 | "
          "D6:3 C6:1 A5:2 E5:1 C#5:1 D5:8")
HARM = ("F4:3 F4:1 A4:4 D5:3 D5:1 F5:4 | "
        "G5:3 F5:1 D5:2 D5:2 C#5:4 A4:2 E4:2 | "
        "D5:3 D5:1 F5:4 E5:3 E5:1 G5:4 | "
        "A5:3 A5:1 F5:2 C#5:1 A4:1 F4:8")
THEME = MOTIF + " | " + ANSWER

# VERSE (16ths). x turned downward + rising-4th pickup onto the snare.
VERSE_Q = ("G5:3 G5:1 E5:4 -:2 D5:2 G5:4 | "          # Em7  G G E . D-G
           "F#5:3 F#5:1 D5:4 -:2 E5:2 A5:4 | "        # D    sequence a step down
           "E5:3 E5:1 C5:4 -:2 D5:2 G5:4 | "          # C    and again
           "D#5:3 E5:1 F#5:4 A5:3 G5:1 F#5:4")        # B7   half cadence (question)
VERSE_A = ("C5:3 B4:1 E5:4 -:2 G5:2 E5:4 | "          # Am7  x' : dip + 4th
           "D5:3 C#5:1 F#5:4 -:2 E5:2 A5:4 | "        # D    x' a step higher
           "G5:3 F#5:1 B5:4 B5:3 A5:1 G5:4")          # G    peak, then x falling
VERSE_END1 = "F#5:3 E5:1 D#5:2 B4:2 C5:1 B4:1 A4:2 F#4:4"   # B7 settles low
VERSE_END2 = "D#5:3 D#5:1 F#5:4 A5:3 A5:1 B5:2 -:2"         # B7 climbs into the hook
# FM counter for verse A2: harmonises the x-cells (3rds/6ths), leaves the pickups solo
VCTR_Q = ("E5:3 E5:1 B4:4 -:8 | D5:3 D5:1 A4:4 -:8 | C5:3 C5:1 G4:4 -:8 | "
          "B4:3 C5:1 D#5:4 F#5:3 E5:1 D#5:4")
VCTR_A = ("A4:3 G4:1 C5:4 -:8 | F#4:3 E4:1 A4:4 -:8 | B4:3 A4:1 D5:4 G5:3 F#5:1 D5:4 | "
          "B4:3 B4:1 D#5:4 F#5:3 F#5:1 D#5:2 -:2")

# CIRCLE (8ths): x augmented. Odd bars rise 7th -> 3rd by a 4th, even bars fall
# from the held-over common tone through the chord. Harmony a 3rd below.
CIRC = ("G5:3 G5:1 C6:4 | C6:3 A5:1 F#5:4 | F#5:3 F#5:1 B5:4 | B5:3 G5:1 E5:4 | "
        "E5:3 E5:1 A5:4 | A5:3 F#5:1 D#5:4 | D5:3 D5:1 G5:4")
CIRC_H = ("E5:3 E5:1 A5:4 | A5:3 F#5:1 D5:4 | D5:3 D5:1 G5:4 | G5:3 E5:1 C5:4 | "
          "C5:3 C5:1 F#5:4 | F#5:3 D#5:1 B4:4 | B4:3 B4:1 E5:4")

# ------------------------------------------------------------------- tracks --
lead = song.track("lead", lead_pulse(cutoff=8000), vol=-7, pan=0.0, reverb=0.15, delay=0.1, hp=180)
saw = song.track("saw", lead_saw(cutoff=7000), vol=-7.5, pan=0.05, reverb=0.15, delay=0.1, hp=180)
chip = song.track("chip", lead_pulse(duty=0.125, vib_depth=0.12), vol=-8, pan=0.0, reverb=0.2,
                  delay=0.15, hp=180)
ctr = song.track("counter", lead_fm(), vol=-12, pan=-0.2, reverb=0.15, hp=180)
brs = song.track("brass", brass(cutoff=1500), vol=-13, pan=-0.15, reverb=0.12, hp=120)
# "rhythm guitar": overdriven 2-voice saw, short and palm-muted (riff doubling + offbeat chugs)
GTR = Inst(osc="saw", unison=2, detune=12, spread=0.4, a=0.002, d=0.12, s=0.35, r=0.05,
           q=1.1, fenv=1.6, fdecay=0.05, drive=0.7, gain=0.4, cutoff=2800)
gtr = song.track("gtr", GTR, vol=-7, pan=0.35, reverb=0.08, hp=120, duck=0.2)
gtrL = song.track("gtrL", replace(GTR, detune=9), vol=-7, pan=-0.35, reverb=0.08, hp=120, duck=0.2)   # double-track
bass = song.track("bass", bass_fm(sub=0.15), vol=-7, duck=0.3, hp=35)
cbass = song.track("chipbass", bass_nes(sub=0.2), vol=-16, duck=0.2, hp=35)
pad = song.track("pad", strings(), vol=-12, reverb=0.45, duck=0.35, hp=200)
arp = song.track("arp", arp_pulse(), vol=-6, pan=0.35, delay=0.15, hp=400, duck=0.2)
bel = song.track("bell", bell(), vol=-11, pan=-0.3, reverb=0.35, delay=0.2, hp=300)
dr = song.drums("drums", vol=-6.5, reverb=0.07, eq=(("lowshelf", 70, -3.0, 0.7),))

# =============================================================== MELODIES ==
# verse A on the fat saw
saw.seq(A1, VERSE_Q + " | " + VERSE_A + " | " + VERSE_END1, unit=0.25)
# 2nd time the pickups slide up into the snare note like a guitar
VERSE_Q2 = VERSE_Q.replace("-:2 D5:2", "-:2 D5>:2").replace("-:2 E5:2", "-:2 E5>:2")
VERSE_A2 = VERSE_A.replace("-:2 E5:2", "-:2 E5>:2")
saw.seq(A2, VERSE_Q2 + " | " + VERSE_A2 + " | " + VERSE_END2, unit=0.25)
ctr.seq(A2, VCTR_Q + " | " + VCTR_A, unit=0.25, vel=0.75)

# hook B: hero pulse, theme twice; HARM on the 2nd pass
lead.seq(B, THEME, unit=0.25, transpose=2)
lead.seq(B + 4, THEME, unit=0.25, transpose=2)
ctr.seq(B + 4, HARM, unit=0.25, transpose=2, vel=0.8)

# circle C: twin lead
saw.seq(C, CIRC + " | F#5:3 D#5:1 B4:4", unit=0.5)
ctr.seq(C, CIRC_H + " | D#5:3 B4:1 F#4:4", unit=0.5, vel=0.8)

# breakdown: chip pulse, x inverted (falls a 5th); bars 43-44 the hero x rises again
BRK_LEAD = ["G5:3 G5:1 C5:4 -:8", "D6:3 D6:1 G5:4 -:8", "A5:3 A5:1 D5:4 -:8", "B5:3 B5:1 E5:4 -:8",
            "G5:3 G5:1 C5:4 -:8", "D6:3 D6:1 G5:4 -:8",
            "A4:3 A4:1 D5:4 F#5:3 E5:1 A5:4", "B4:3 B4:1 E5:4 G5:3 F#5:1 B5:4"]
for k, txt in enumerate(BRK_LEAD):
    chip.seq(BRK + k, txt, unit=0.25, vel=0.8)
# the wink (5-6-5-3-1 of each chord) traded between bell and arp on beats 3-4
WINK = {"C": "G5:2 A5:1 G5:1 E5:2 C5:2", "G": "D6:2 E6:1 D6:1 B5:2 G5:2",
        "D": "A5:2 B5:1 A5:1 F#5:2 D5:2", "Em": "B5:2 C6:1 B5:1 G5:2 E5:2"}
for k, c in enumerate("C G D Em C G".split()):
    (bel if k % 2 == 0 else arp).seq(BRK + k, WINK[c], unit=0.25, at=2.0, vel=0.95)
# bars 43-44: bell rings the landing notes of the returning hero x
bel.seq(BRK + 6, "-:4 D6:4 -:4 A6:4", unit=0.25, vel=0.6)
bel.seq(BRK + 7, "-:4 E6:4 -:4 B6:4", unit=0.25, vel=0.6)

# build: lead run down the C#7 into the climax (ends G#4 -> C#5, the rising 4th)
lead.seq(BUILD + 3, "C#6:1 B5:1 G#5:1 E#5:1 C#5:1 B4:1 G#4:2", unit=0.25, at=2.0, vel=0.85)

# climax: theme in F# minor, pulse + saw unison, HARM both times
for k in (0, 4):
    lead.seq(B2 + k, THEME, unit=0.25, transpose=4)
    saw.seq(B2 + k, THEME, unit=0.25, transpose=4, vel=0.55)
    ctr.seq(B2 + k, HARM, unit=0.25, transpose=4, vel=0.8)
# bell: octave-up sparkle on the quarter-note landings ("SMASH")
for k in (0, 4):
    bel.seq(B2 + k, "-:4 F#6:4 -:4 C#7:4 | -:16 | -:4 D7:4 -:4 E7:4", unit=0.25, vel=0.55)

# circle C' in F# minor: hero lead on top, saw unison, FM a 3rd below
lead.seq(C2, CIRC + " | -:8", unit=0.5, transpose=2)
lead.seq(C2 + 7, "A5:3 F#5:1 D#5:3", unit=0.5)            # B7: back towards E minor
saw.seq(C2, CIRC + " | -:8", unit=0.5, transpose=2, vel=0.55)
saw.seq(C2 + 7, "A5:3 F#5:1 D#5:3", unit=0.5, vel=0.55)
ctr.seq(C2, CIRC_H, unit=0.5, transpose=2, vel=0.8)
ctr.seq(C2 + 7, "F#5:3 D#5:1 B4:3", unit=0.5, vel=0.8)

# bell winks in the half-note gaps of the falling bars of both circles (octave 6)
C_WINK = {"D7": "A6:2 B6:1 A6:1 F#6:2 D6:2", "C": "G6:2 A6:1 G6:1 E6:2 C6:2",
          "B7": "F#6:2 G6:1 F#6:1 D#6:2 B5:2",
          "E7": "B6:2 C#7:1 B6:1 G#6:2 E6:2", "D": "A6:2 B6:1 A6:1 F#6:2 D6:2",
          "C#7": "G#6:2 A6:1 G#6:1 E#6:2 C#6:2"}
for bar, c in ((C + 1, "D7"), (C + 3, "C"), (C + 5, "B7"),
               (C2 + 1, "E7"), (C2 + 3, "D"), (C2 + 5, "C#7")):
    bel.seq(bar, C_WINK[c], unit=0.25, at=2.0, vel=0.7)

# ================================================================ BASS ==
# intro riff: x three octaves down
bass.seq(INTRO, "B1:3 B1:1 E2:4 G2:3 F#2:1 B2:4 | G1:3 G1:1 C2:4 A1:3 A1:1 D2:4 | "
                "B1:3 B1:1 E2:4 G2:3 F#2:1 B2:4 | G1:3 G1:1 C2:4 F#2:3 F#2:1 B2:2 A2:2", unit=0.25)

# verse: "Ma-gic" in the bass too, octave bounce, chord-tone approach notes
VB = {
    "Em7": "E2:3 E2:1 E3:2 E2:2 -:2 E2:2 E3:2 D3:2",
    "D": "D2:3 D2:1 D3:2 D2:2 -:2 D2:2 D3:2 C3:2",
    "C": "C2:3 C2:1 C3:2 C2:2 -:2 C2:2 C3:2 G2:2",
    "B7": "B1:3 B1:1 B2:2 B1:2 -:2 B1:2 A2:2 F#2:2",
    "Am7": "A1:3 A1:1 A2:2 A1:2 -:2 A1:2 A2:2 E2:2",
    "D2": "D2:3 D2:1 D3:2 D2:2 -:2 D2:2 D3:2 A2:2",
    "G": "G1:3 G1:1 G2:2 G1:2 -:2 G1:2 G2:2 A2:2",
    "B7end": "B1:3 B1:1 B2:2 B1:2 B1:2 C#2:2 D#2:2 F#2:2",   # walk-up into E
}
for base in (A1, A2):
    for k, key in enumerate(["Em7", "D", "C", "B7", "Am7", "D2", "G", "B7end"]):
        bass.seq(base + k, VB[key], unit=0.25)

# hook: 16th slap with ghosts; 5ths on beats 2 and 4 in bar 3 (no octaves vs lead)
HOOK_BASS = ("E2:2 E3:1 E2_:1 E3:2 E2:1 E2_:1 E3:2 E2:2 G2:2 B2:2 | "
             "A1:2 A2:1 A1_:1 A2:2 E2:2 B1:2 B2:1 B1_:1 B2:2 F#2:2 | "
             "C2:2 C3:1 C2_:1 G2:2 C3:2 D2:2 D3:1 D2_:1 A2:2 F#2:2 | "
             "E2:2 E3:1 E2_:1 E3:2 E2:1 E2_:1 B2:2 E3:2 B2:2 B1:2")
bass.seq(B, HOOK_BASS, unit=0.25)
bass.seq(B + 4, HOOK_BASS, unit=0.25)

# circle: slap + chord-tone walk into each next root
CB = ["A1:2 A2:1 A1_:1 A2:2 E2:2 A1:2 A2:1 A1_:1 G2:2 E2:2",        # Am7 -> D
      "D2:2 D3:1 D2_:1 D3:2 A2:2 D2:2 D3:1 D2_:1 C3:2 A2:2",        # D7  -> G
      "G1:2 G1:1 G1_:1 D2:2 B1:2 G1:2 G2:1 G1_:1 B1:2 D2:2",        # G   (no G2 under the F#)
      "C2:2 C3:1 C2_:1 C3:2 G2:2 C2:2 C3:1 C2_:1 E2:2 G2:2",        # C   -> F#
      "F#1:2 F#2:1 F#1_:1 F#2:2 C2:2 F#1:2 F#2:1 F#1_:1 E2:2 A1:2",  # F#m7b5 -> B
      "B1:2 B2:1 B1_:1 B2:2 F#2:2 B1:2 B2:1 B1_:1 A2:2 F#2:2",      # B7
      "E2:2 E3:1 E2_:1 E3:2 B2:2 E2:2 E3:1 E2_:1 D3:2 B2:2"]        # Em7
for k, txt in enumerate(CB):
    bass.seq(C + k, txt, unit=0.25)
bass.seq(C + 7, "B1:2 B2:1 B1_:1 B2:2 F#2:2 B1:2 -:6", unit=0.25)  # stop

# breakdown: NES triangle, half-time, x rhythm stretched
cbass.seq(BRK, "C2:3 C2:1 C3:2 G2:2 | G1:3 G1:1 G2:2 D2:2 | D2:3 D2:1 D3:2 A2:2 | E2:3 E2:1 E3:2 B2:2 | "
               "C2:3 C2:1 C3:2 G2:2 | G1:3 G1:1 G2:2 D2:2 | D2:3 D2:1 D3:2 A2:2 | E2:3 E2:1 E3:2 B1:2",
           unit=0.5, vel=0.85)

# build: pumping 8ths, then 16ths
bass.seq(BUILD, "C2 C2 C3 C2 C2 C2 C3 C2 | D2 D2 D3 D2 D2 D2 D3 D2", unit=0.5)
bass.seq(BUILD + 2, " ".join(["E2", "E2", "E3", "E2"] * 4), unit=0.25)
bass.seq(BUILD + 3, " ".join(["C#2", "C#2", "C#3", "C#2"] * 2) + " C#2:2 G#2:2 B2:2 G#2:2", unit=0.25)

# climax + circle C' (F#)
bass.seq(B2, HOOK_BASS, unit=0.25, transpose=2)
bass.seq(B2 + 4, HOOK_BASS, unit=0.25, transpose=2)
for k, txt in enumerate(CB):
    bass.seq(C2 + k, txt, unit=0.25, transpose=2)
bass.seq(C2 + 7, "B1:2 B2:1 B1_:1 B2:2 A2:2 B1:4 -:4", unit=0.25)   # B7 turnaround

# ============================================================ RHYTHM GTR ==
# intro: the riff doubled one and two octaves above the bass
RIFF = ("B1:3 B1:1 E2:4 G2:3 F#2:1 B2:4 | G1:3 G1:1 C2:4 A1:3 A1:1 D2:4 | "
        "B1:3 B1:1 E2:4 G2:3 F#2:1 B2:4 | G1:3 G1:1 C2:4 F#2:3 F#2:1 B2:2 A2:2")
gtrL.seq(INTRO, RIFF, unit=0.25, transpose=12, vel=0.5)
gtrL.seq(INTRO, RIFF, unit=0.25, transpose=24, vel=0.45)
gtr.seq(INTRO, RIFF, unit=0.25, transpose=24, vel=0.8)
# second time round the riff also gets a chip-pulse double three octaves up (arcade flourish)
chip.seq(INTRO + 2, RIFF.split("|", 2)[2], unit=0.25, transpose=36, vel=0.5)


def power_in(ch, lo="B2"):
    root, iv, _ = parse_chord(ch)
    r = midi(lo) + (root - midi(lo)) % 12
    return [r, r + 7, r + 12]


# verses: palm-muted power chords on the off-beat 8ths, accent before the snare
for bar0, bar1, v in ((A1, A2, 0.5), (A2, B, 0.6)):
    for s_, e_, c in chords_in(bar0, bar1):
        for off, vv in ((0.5, 0.8), (1.5, 1.0), (2.5, 0.8), (3.5, 1.0)):
            if s_ + off < e_ and not (e_ == bb(B) and off > 2):      # leave the hook fill clear
                pc = power_in(c)
                for m in pc[:2]:
                    gtrL.note(s_ + off, m, 0.22, v * vv * 0.85)
                for m in pc[1:]:
                    gtr.note(s_ + off, m, 0.22, v * vv * 0.85)

# build: gtr doubles the brass x stabs, 16th chugs in the last bar
for k, ch in enumerate(["C", "D", "E"]):
    pc = power_in(ch)
    for half in (0.0, 2.0):
        for off, ln, vv in ((0.0, 0.5, 0.9), (0.75, 0.2, 0.7), (1.0, 0.6, 1.0)):
            for m in pc:
                gtr.note(bb(BUILD + k, half + off), m, ln, vv * 0.5)
                gtrL.note(bb(BUILD + k, half + off), m, ln, vv * 0.5)
for i in range(8):
    for m in power_in("C#7sus4"):
        gtr.note(bb(BUILD + 3, i * 0.25), m, 0.18, 0.45 + 0.04 * i)

# ================================================================ BRASS ==
def power(root, octv=3):
    r = midi(f"{root}{octv}")
    return [r, r + 7, r + 12]


# intro: power-chord "SMASH" stabs on beats 2 and 4
for bar, (c1, c2) in zip(range(INTRO, INTRO + 4), [("E", "B"), ("C", "D"), ("E", "B"), ("C", "B")]):
    o2 = 2 if c2 == "B" else 3
    brs.chord(bar, power(c1, 4), beats=0.45, vel=0.85, at=1.0)
    brs.chord(bar, power(c2, o2 + 1), beats=0.45, vel=0.85, at=3.0)

# build: x as power stabs (5th, 5th, root+octave), twice a bar, climbing
for k, root in enumerate(["C", "D", "E"]):
    r = midi(f"{root}4")
    for half in (0.0, 2.0):
        brs.note(bb(BUILD + k, half), r, 0.6, 0.85).note(bb(BUILD + k, half), r + 7, 0.6, 0.85)
        brs.note(bb(BUILD + k, half + 0.75), r, 0.2, 0.7).note(bb(BUILD + k, half + 0.75), r + 7, 0.2, 0.7)
        for m in (r, r + 7, r + 12):
            brs.note(bb(BUILD + k, half + 1.0), m, 0.8, 0.95)
r = midi("C#4")
brs.note(bb(BUILD + 3), r, 0.6, 0.9).note(bb(BUILD + 3), r + 7, 0.6, 0.9)
brs.note(bb(BUILD + 3, 0.75), r, 0.2, 0.75).note(bb(BUILD + 3, 0.75), r + 7, 0.2, 0.75)
for m in ("C#4", "F#4", "C#5"):
    brs.note(bb(BUILD + 3, 1.0), m, 0.8, 1.0)
for m in ("C#4", "E#4", "B4"):
    brs.note(bb(BUILD + 3, 2.0), m, 0.45, 1.0)


def stabs(bar0, bar1, vel=0.75, length=0.45):
    """power-chord stab on every chord change"""
    for s, e, c in chords_in(bar0, bar1):
        root, iv, _ = parse_chord(c)
        nm = NOTE_NAMES[root]
        o = 2 if root >= 9 else 3     # keep stabs between A2 and G#3 roots
        brs.chord(s / 4, power(nm, o), beats=length, vel=vel)


stabs(B + 4, B + 8, 0.6)
stabs(B2, C2, 0.75)
stabs(C2, END - 1, 0.6)
brs.chord(END - 1, power("B", 2), beats=0.45, vel=0.8)

# ============================================================ PADS / ARPS ==
def voicing(ch, lo=52, hi=67):
    root, iv, _ = parse_chord(ch)
    return sorted({lo + (((root + i) % 12) - lo) % 12 for i in iv})


for bar0, bar1 in ((A2, B), (B, C), (C, BRK), (BRK, BUILD), (BUILD, B2), (B2, END)):
    for s, e, c in chords_in(bar0, bar1):
        for m in voicing(c):
            pad.note(s, m, e - s - 0.1, 0.6)
pad.fade(INTRO, A2 - 1, -6, -6).fade(A2, BRK - 0.1, 0, 0).fade(BRK, BUILD, 1, 1).fade(BUILD + 0.01, END, 0, 0)

ARP_SECTIONS = ((A2, B, "0 1 2 1"), (B + 4, C, "0 1 2 3 2 1"), (C, BRK - 1, "0 1 2 3"),
                (BRK + 4, BUILD, "0 1 2 1"), (B2, C2, "0 1 2 3 2 1"), (C2, END - 1, "0 1 2 3"))
for bar0, bar1, pat in ARP_SECTIONS:
    for s, e, c in chords_in(bar0, bar1):
        arp.arp(s / 4, chord_tones(c, 4), pat, unit=0.25, beats=e - s, vel=0.4)


# ---------------------------------------------------------- clash pruning --
def prune(track, against, min_ov=0.5):
    """drop sustained pad notes a semitone away from melody/bass notes (as the report counts them)"""
    keep = []
    others = [n for t in against for n in t.notes]
    for n in track.notes:
        bad = False
        for o in others:
            ov = min(n.beat + n.beats, o.beat + o.beats) - max(n.beat, o.beat)
            iv = abs(int(n.m) - int(o.m))
            if ov >= min_ov and iv % 12 in (1, 11) and iv < 24:
                bad = True
                break
        if not bad:
            keep.append(n)
    track.notes = keep


prune(pad, [lead, saw, chip, ctr, bass, cbass, brs, gtr, gtrL])

# ================================================================= DRUMS ==
def groove(bar, n, pats, **kw):
    # patterns shorter than a bar are padded with rests (not repeated)
    pats = {v: p.replace(" ", "").ljust(16, ".") for v, p in pats.items()}
    dr.pat(bar, pats, bars=n, **kw)


def crash(bar, vel=0.8):
    dr.hit(bb(bar), "crash", vel)


ROCK = {"kick": "x.....x.x.....x.", "snare": "....x.......x...",
        "hat": "x..ox..ox..ox..o", "ohat": "..x...x...x...x."}
BIG_FILL = "snare snare tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo"

# intro: riff-locked kick
groove(INTRO, 3, {"kick": "x..x....x..x....", "snare": "....X.......X...", "hat": "x.x.x.x.x.x.x.x.",
                   "shaker": ".ooo.ooo.ooo.ooo"})
groove(INTRO + 3, 1, {"kick": "x..x....x.......", "snare": "....X...........", "hat": "x.x.x.x.x.x....."})
dr.fill(INTRO + 3, "snare_ snare tom_mid tom_lo snare snare^ tom_lo^ -", at=2.0)
crash(INTRO, 0.9)

# verse A1
V1 = {"kick": "x..x......x.....", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x.", "shaker": ".o.o.o.o.o.o.o.o"}
groove(A1, 3, V1)
groove(A1 + 3, 1, {"kick": "x..x......x.....", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x..."})
dr.fill(A1 + 3, "snare_ snare", at=3.5)
groove(A1 + 4, 3, V1)
groove(A1 + 7, 1, {"kick": "x..x....", "snare": "....x...", "hat": "x.x.x.x."}, )
dr.fill(A1 + 7, BIG_FILL, at=2.0)
crash(A1, 0.75)

# verse A2: 16th hats, ghost snares, open hat on the 'and' of 4
V2 = {"kick": "x..x......x...x.", "snare": "....x..o....x..o", "hat": "x.xox.xox.xox.x.",
      "ohat": "..............x.", "shaker": ".o.o.o.o.o.o.o.o"}
groove(A2, 3, V2)
groove(A2 + 3, 1, {"kick": "x..x......x.....", "snare": "....x..o....x...", "hat": "x.xox.xox.xo...."})
dr.fill(A2 + 3, "snare_ snare snare tom_lo", at=3.0)
groove(A2 + 4, 3, V2)
groove(A2 + 7, 1, {"kick": "x..x", "hat": "x.xo"})
dr.fill(A2 + 7, "snare_ snare_ snare snare tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=1.0)
crash(A2, 0.8)

# hook B
groove(B, 3, ROCK)
groove(B + 3, 1, {"kick": "x.....x.x.......", "snare": "....x.......", "hat": "x..ox..ox..o", "ohat": "..x...x...x."})
dr.fill(B + 3, "snare snare tom_hi tom_lo", at=3.0)
groove(B + 4, 3, dict(ROCK, clap="....x.......x..."))
groove(B + 7, 1, {"kick": "x.....x.", "snare": "....x...", "clap": "....x...", "hat": "x..ox..o", "ohat": "..x...x."})
dr.fill(B + 7, BIG_FILL, at=2.0)
crash(B, 0.9)
crash(B + 4, 0.8)

# circle C: ride
RIDE = {"kick": "x.....x.x.......", "snare": "....x.......x...", "ride": "x.x.x.x.x.x.x.x.",
        "hat": "..o...o...o...o."}
groove(C, 3, RIDE)
groove(C + 3, 1, {"kick": "x.....x.x.......", "snare": "....x.......x...", "ride": "x.x.x.x.x.x....."})
dr.fill(C + 3, "snare_ snare", at=3.5)
groove(C + 4, 3, RIDE)
# B7 stop: hits on 1, 2, 3 then silence before the breakdown
dr.hit(bb(C + 7), "kick", 0.9).hit(bb(C + 7, 1), "snare", 0.9).hit(bb(C + 7, 1.5), "snare", 0.6)
dr.hit(bb(C + 7, 2), "kick", 1.0).hit(bb(C + 7, 2), "crash", 0.9).hit(bb(C + 7, 2), "snare", 1.0)
crash(C, 0.85)

# breakdown: chip kit, half time, building back to full time
groove(BRK, 4, {"kick_chip": "x.........x.....", "snare_chip": "........x.......", "hat_chip": "x.x.x.x.x.x.x.x."})
groove(BRK + 4, 2, {"kick_chip": "x.........x.....", "snare_chip": "........x......o",
                    "hat_chip": "x.xxx.xxx.xxx.xx"})
groove(BRK + 6, 2, {"kick_chip": "x.....x.x.....x.", "snare_chip": "....x.......x...",
                    "hat_chip": "x.xxx.xxx.xxx.xx"})
dr.fill(BRK + 7, "snare_chip snare_chip snare_chip snare_chip", at=3.0)

# build: four on the floor, snare 8ths -> 16ths, riser
for k in range(4):
    dr.pat(BUILD + k, {"kick": "x...x...x...x..."})
dr.pat(BUILD, {"snare": "o.o.o.o.o.o.o.o."})
dr.pat(BUILD + 1, {"snare": "x.x.x.x.x.x.x.x."})
dr.pat(BUILD + 2, {"snare": "xxxxxxxxxxxxxxxx"})
for i in range(8):
    dr.hit(bb(BUILD + 3, i * 0.25), "snare", 0.75 + 0.03 * i)
dr.fill(BUILD + 3, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", at=2.0)
dr.hit(bb(B2) - 2.0 * song.bpm / 60.0, "riser", 0.55)
crash(BUILD, 0.75)

# climax
groove(B2, 3, dict(ROCK, clap="....x.......x..."))
groove(B2 + 3, 1, {"kick": "x.....x.x.......", "snare": "....x.......", "clap": "....x.......",
                   "hat": "x..ox..ox..o", "ohat": "..x...x...x."})
dr.fill(B2 + 3, "snare snare tom_hi tom_lo", at=3.0)
groove(B2 + 4, 3, dict(ROCK, clap="....x.......x..."))
groove(B2 + 7, 1, {"kick": "x.....x.", "snare": "....x...", "clap": "....x...", "hat": "x..ox..o", "ohat": "..x...x."})
dr.fill(B2 + 7, BIG_FILL, at=2.0)
crash(B2, 1.0)
crash(B2 + 4, 0.85)

# circle C': ride + clap
RIDE2 = dict(RIDE, clap="....x.......x...", ohat="..............x.")
groove(C2, 3, RIDE2)
groove(C2 + 3, 1, {"kick": "x.....x.x.......", "snare": "....x.......x...", "clap": "....x.......x...",
                   "ride": "x.x.x.x.x.x....."})
dr.fill(C2 + 3, "snare_ snare", at=3.5)
groove(C2 + 4, 3, RIDE2)
groove(C2 + 7, 1, {"kick": "x.....x.", "snare": "....x...", "clap": "....x...", "ride": "x.x.x.x."})
dr.fill(C2 + 7, "tom_hi tom_mid tom_lo tom_lo snare^ snare^ - -", at=2.0)   # quiet last 8th = clean seam
crash(C2, 0.9)

# ============================================================ DYNAMICS ==
def auto(tr, points):
    """step automation [(bar, dB), ...]; each value holds until the next point"""
    for i, (bar, d) in enumerate(points):
        b = bb(bar)
        if i:
            tr.automation.append((b - 0.05, points[i - 1][1]))
        tr.automation.append((b, d))


# verse sits 2-3 dB under the hook, breakdown 4-6 dB under
auto(dr, [(INTRO, 0), (A1, -2.0), (A2, -1.0), (B, 0), (C, -0.5), (BRK, -2.5), (BUILD, -2.5), (BUILD + 2, -1.5),
          (B2, 0.5), (C2, 0)])
auto(saw, [(INTRO, -1.0), (C, 0), (B2, 0)])
auto(bass, [(INTRO, -2.0), (A1, -2.0), (A2, -1.0), (B, 0)])

if __name__ == "__main__":
    song.render(out_dir=OUT)

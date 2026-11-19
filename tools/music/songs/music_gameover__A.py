"""Magic Smash -- GAME OVER jingle, angle A: "the last spell fizzles".

D minor (home key), 88 bpm, 2 bars + 2.5 s ring-out, no loop (7.95 s).
(88 rather than the bible's 84 so that 2 bars + the required 2.5 s tail stay
under 8 s.)

Two bars, one story
  bar 1  "Ma-gic smash" turned upside down. Cell x falls a 5th (A A D) over Dm,
         and its rhythm now sings "GAME o-ver". The bass begins the lament
         descent D-C-Bb. Cell x' (F E) also falls a 5th and lands on A, the
         major 7th of Bbmaj9 (the bittersweet chord). The pad's top voice rises
         A->C here, so the colour comes from the melody with no held clash.
  bar 2  The motif's own bar 2, an octave down and squeezed into two beats.
         First the flat-6 sigh Bb->A ("pianto") over Gm6, then the wink E F E C#
         over A7 (the F is the b9). Bass and timpani play cell x's rhythm
         (A. A | D) into the cadence: the bass rises a 4th (the hero's x) and the
         timpani falls a 5th (the game-over x). A faint reverse cymbal gathers
         into beat 3. The lead lands on a low D and the chord turns MAJOR
         (Picardy third: "try again").
         The flute doubles bar 1 an octave up, then peels off into a descant.
         It mirrors the wink upward (E F E G), so the A7 tritone resolves in
         contrary motion in the outer voices (lead C#->D, flute G->F#). That
         leaves the Picardy F# on top.
  ring   Over the final chord, the bell whispers the hero's ORIGINAL rising x
         (A A D6) as one last spell. On the "and" of 4 it sputters out as a
         4-note chirping arp_pulse fizzle (D6 A5 F#5 D5) that dies away in
         the delay.

Harmony  | Dm   Dm7/C  Bbmaj9      | Gm6  A7(b9)    D (Picardy) |
Bass     | D2   C2     Bb1         | G1   A1. A1    D2          |  lament line
Strings  voice-led: D3-E3-C#3-D3 / F3-G3-F#3 / A3-C4-Bb3-A3
Drums    timp_lo + soft gong on the downbeat; timp A. A | D (x rhythm) into
         the cadence; reverse cymbal swell
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403

OUT = os.path.join(HERE, "out", "candidates")

song = Song("music_gameover__A", bpm=88, bars=2, reverb_seconds=2.6, reverb_damp=0.45,
            delay_feedback=0.38)
song.no_loop(tail=2.5)

# one chord per beat, except Bbmaj9 and the final D (two beats each)
song.chords(0, "Dm Dm7/C Bbmaj9:2 Gm6 A7 D:2", per=0.25)
song.section(0, "x falls")
song.section(1, "sigh, wink, Picardy, fizzle")

END = 8.0          # body length in beats; anything after rings into the tail


def line(track, beat, spec, unit=0.25, transpose=0):
    """spec: list of (note, units, velocity); '-' is a rest."""
    for nm, u, v in spec:
        if nm != "-":
            track.note(beat, midi(nm) + transpose, u * unit, v)
        beat += u * unit
    return beat


# ------------------------------------------------------------------ melody --
# unit = 16th note. Bar 1: x and x' fall a 5th. Bar 2: sigh + wink -> low D.
MELODY = [
    ("A5", 3, 0.82), ("A5", 1, 0.55), ("D5", 4, 0.70),     # Ma-gic smash...  (falls a 5th)
    ("F5", 3, 0.72), ("E5", 1, 0.50), ("A4", 4, 0.62),     # ...x' falls too, A = maj7 of Bb(maj9)
    ("Bb4", 3, 0.80), ("A4", 1, 0.50),                     # flat-6 sigh (pianto)
    ("E4", 1, 0.60), ("F4", 1, 0.52), ("E4", 1, 0.55), ("C#4", 1, 0.58),  # the wink, F = b9
    ("D4", 15, 0.72),                                      # low D, rings past the barline
]

lead = song.track("lead", lead_pulse(duty=0.5, vib_depth=0.22, vib_delay=0.22, cutoff=8000, a=0.008, r=0.12),
                  vol=-9, pan=0.0, reverb=0.35, delay=0.12, hp=180,
                  eq=(("highshelf", 3000, 6.0, 0.7),))
line(lead, 0, MELODY)
lead.fade(1.6, 2.45, 0, -15)       # the low D sinks under the bell + fizzle

# Flute: bar 1 doubles the lead an octave up; bar 2 peels off into a descant.
# Over A7 it mirrors the wink upward (E F E G) so the dominant's tritone
# resolves in contrary motion in the outer voices: lead C#->D, flute G->F#.
# The flute's F#5 is the Picardy third on top ("try again").
FLUTE = [(n, u, v * 0.85) for n, u, v in MELODY[:6]] + [
    ("Bb4", 3, 0.66), ("A4", 1, 0.45),
    ("E4", 1, 0.50), ("F4", 1, 0.45), ("E4", 1, 0.48), ("G4", 1, 0.55),
    ("F#4", 16, 0.62),
]
flute_t = song.track("flute", flute(), vol=-12, pan=-0.2, reverb=0.4, delay=0.08, hp=400)
line(flute_t, 0, FLUTE, transpose=12)
flute_t.fade(1.75, 2.5, 0, -12)

# -------------------------------------------------------------------- bass --
bass = song.track("bass", bass_nes(), vol=-14, pan=0.0, reverb=0.0)
line(bass, 0, [("D2", 4, 0.8), ("C2", 4, 0.75), ("Bb1", 8, 0.8),
               ("G1", 4, 0.8), ("A1", 3, 0.8), ("A1", 1, 0.6), ("D2", 14, 0.85)])
bass.fade(1.75, 2.4, 0, -10)

# ----------------------------------------------------------------- strings --
pad = song.track("strings", strings(), vol=-12, reverb=0.5, hp=200)
VOICES = [
    [("D3", 0, 4), ("E3", 4, 5), ("C#3", 5, 6), ("D3", 6, 10.5)],
    [("F3", 0, 4), ("G3", 4, 6), ("F#3", 6, 10.5)],
    [("A3", 0, 2), ("C4", 2, 4), ("Bb3", 4, 5), ("A3", 5, 10.5)],
]
for v in VOICES:
    for nm, b0, b1 in v:
        pad.note(b0, nm, b1 - b0, 0.6)
pad.fade(1.75, 2.6, 0, -9)

# -------------------------------------------------------------------- harp --
# a falling broken-chord line under the held melody notes, then a rising strum
harp_t = song.track("harp", harp(), vol=-10, pan=0.35, reverb=0.4)
line(harp_t, 0, [("F5", 1, 0.7), ("D5", 1, 0.6), ("A4", 1, 0.65), ("F4", 1, 0.55),
                 ("D5", 1, 0.65), ("A4", 1, 0.55), ("F4", 1, 0.6), ("D4", 1, 0.5),
                 ("G4", 1, 0.6), ("E4", 1, 0.5)], unit=0.5)
harp_t.chord(1, ["D3", "A3", "D4", "F#4", "A4", "D5"], beats=3.0, vel=0.6, at=2.0, strum=0.05)

# ------------------------------------------------------------ magic sparkle --
# the hero's original x, rising, one last time -- then it fizzles
bell_t = song.track("bell", bell(), vol=-12, pan=-0.3, reverb=0.35, delay=0.2, hp=300)
line(bell_t, 6.0, [("A5", 3, 0.55), ("A5", 1, 0.45), ("D6", 4, 0.7)])

# each blip chirps down from 4 semitones above: a spell sputtering, not a melody
fizz = song.track("fizzle", arp_pulse(pitch_env=4.0, pitch_decay=0.02), vol=-5, pan=0.35, reverb=0.3, delay=0.3, hp=400)
line(fizz, 7.5, [("D6", 1, 0.6), ("A5", 1, 0.5), ("F#5", 1, 0.42), ("D5", 1, 0.34)], unit=0.125)

# ------------------------------------------------------------------- drums --
dr = song.drums("drums", vol=-10, reverb=0.3)
dr.hit(0.0, "timp_lo", 0.8)        # the "game over" thud
dr.hit(0.0, "gong", 0.25)
# a faint reverse cymbal gathers the last bit of magic into the final chord
dr.hit(6.0 - (1.5 / song.beat_sec(1)), "reverse_cymbal", 0.4)
dr.hit(5.0, "timp_hi", 0.5)        # cell x rhythm on the dominant: A. A | D
dr.hit(5.75, "timp_hi", 0.6)
dr.hit(6.0, "timp_lo", 0.9)

if __name__ == "__main__":
    song.render(out_dir=OUT)

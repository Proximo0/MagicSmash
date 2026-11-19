"""Magic Smash -- GAME OVER jingle: "the last spell fizzles".

Final arrangement, built on candidate A (music_gameover__A.py).
D minor (home key), 88 bpm, 2 bars + 2.5 s ring-out, no loop (7.95 s).
(88 rather than the bible's 84 so that 2 bars + the required 2.5 s tail stay
under 8 s.)

Two bars, one story
  bar 1  "Ma-gic smash" turned upside down. Cell x falls a 5th (A A D) over Dm,
         and its rhythm now sings "GAME o-ver". The bass begins the lament
         descent D-C-Bb. Cell x' (F E) also falls a 5th and lands on A, the
         major 7th of Bbmaj9 (the bittersweet chord). The pad's top voice rises
         A->C here, so the colour comes from the melody with no held clash.
         The harp falls in 8ths underneath, a 3rd below each of the lead's
         accents (D5 under F5, F4 under A4, G4 under Bb4).
  bar 2  The motif's own bar 2, an octave down and squeezed into two beats.
         First the flat-6 sigh Bb->A ("pianto") over Gm6 -- the A anticipates
         the A7 -- then the wink E F E C# over A7 (the F is the b13, a cheeky
         upper neighbour). Bass and timpani play cell x's rhythm (A. A | D)
         into the cadence: the bass rises a 4th (the hero's x) while the
         timpani falls a 5th (the game-over x). A reverse cymbal gathers into
         beat 3. The lead lands on a low D and the chord turns MAJOR (Picardy
         third: "try again"); a soft choir "oo" (the title's night-sky voice)
         blooms on F#-A, so the run ends where it started.
         The flute doubles bar 1 an octave up, then peels off into a descant.
         It mirrors the wink upward (E F E G), so the A7 tritone resolves in
         contrary motion in the outer voices (lead C#->D, flute G->F#). That
         leaves the Picardy F# on top.
  ring   Over the final chord, the bell plays the hero's ORIGINAL rising x
         (A A D6) as one last spell. On the "and" of 4 it sputters out as a
         4-note chirping arp_pulse fizzle (D6 A5 F#5 D5) that pings across the
         stereo field in the delay.

Harmony  | Dm   Dm7/C  Bbmaj9      | Gm6  A7        D (Picardy) |
Bass     | D2   C2     Bb1         | G1   A1. A1    D2          |  lament line
Strings  voice-led: D3-E3-C#3-D3 / F3-G3-F#3 / A3-C4-Bb3-A3, swelling into the
         cadence
Drums    timp_lo + soft gong on the downbeat; timp A. A | D (x rhythm) into
         the cadence; reverse cymbal swell

Dynamics: the jingle starts under the loud player_die SFX (1.2 s, 250-800 Hz),
so bar 1 starts a little held back and the whole band swells into the
cadence, which is the loudest moment.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403

song = Song("music_gameover", bpm=88, bars=2, reverb_seconds=2.6, reverb_damp=0.45,
            delay_feedback=0.38)
song.no_loop(tail=2.5)

# one chord per beat, except Bbmaj9 and the final D (two beats each)
song.chords(0, "Dm Dm7/C Bbmaj9:2 Gm6 A7 D:2", per=0.25)
song.section(0, "x falls")
song.section(1, "sigh, wink, Picardy, fizzle")

CAD = 6.0          # beat of the final cadence (bar 2, beat 3)


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
    ("A5", 3, 0.74), ("A5", 1, 0.52), ("D5", 4, 0.72),     # Ma-gic smash...  (falls a 5th)
    ("F5", 3, 0.74), ("E5", 1, 0.50), ("A4", 4, 0.64),     # ...x' falls too, A = maj7 of Bb(maj9)
    ("Bb4", 3, 0.84), ("A4", 1, 0.52),                     # flat-6 sigh (pianto), A anticipates A7
    ("E4", 1, 0.62), ("F4", 1, 0.54), ("E4", 1, 0.56), ("C#4", 1, 0.62),  # the wink, F = b13
    ("D4", 12, 0.82),                                      # low D: home
]

lead = song.track("lead", lead_pulse(duty=0.5, vib_depth=0.22, vib_delay=0.22, cutoff=8000, a=0.008, r=0.25),
                  vol=-9, pan=0.0, reverb=0.35, delay=0.10, hp=180,
                  eq=(("highshelf", 3000, 6.0, 0.7),))
line(lead, 0, MELODY)
# the low D sounds in full for a beat, then sinks under the bell and fizzle
lead.fade(1.75, 2.4, 0, -12)

# Flute: bar 1 doubles the lead an octave up; bar 2 peels off into a descant.
# Over A7 it mirrors the wink upward (E F E G) so the dominant's tritone
# resolves in contrary motion in the outer voices: lead C#->D, flute G->F#.
# The flute's F#5 is the Picardy third on top ("try again").
FLUTE = [(n, u, v * 0.85) for n, u, v in MELODY[:6]] + [
    ("Bb4", 3, 0.68), ("A4", 1, 0.45),
    ("E4", 1, 0.50), ("F4", 1, 0.45), ("E4", 1, 0.48), ("G4", 1, 0.58),
    ("F#4", 14, 0.64),
]
flute_t = song.track("flute", flute(), vol=-12, pan=-0.25, reverb=0.4, delay=0.0, hp=400)
line(flute_t, 0, FLUTE, transpose=12)
flute_t.fade(1.75, 2.5, 0, -12)

# -------------------------------------------------------------------- bass --
# G1/A1/Bb1 on a soft triangle are almost pure sub fundamentals that TVs and
# phones can't reproduce, so the bass carries a quiet octave layer (G2, A2...)
# and only a little of the preset's sine sub (which would sit at 24-29 Hz).
bass = song.track("bass", bass_nes(sub=0.1, octave_layer=0.4), vol=-13, pan=0.0, reverb=0.0)
line(bass, 0, [("D2", 4, 0.78), ("C2", 4, 0.74), ("Bb1", 8, 0.80),
               ("G1", 4, 0.82), ("A1", 3, 0.84), ("A1", 1, 0.62), ("D2", 12, 0.95)])
bass.fade(1.75, 2.4, 0, -10)

# ----------------------------------------------------------------- strings --
pad = song.track("strings", strings(), vol=-12, reverb=0.5, hp=200, width=1.3)
VOICES = [
    [("D3", 0, 4), ("E3", 4, 5), ("C#3", 5, 6), ("D3", 6, 10)],
    [("F3", 0, 4), ("G3", 4, 6), ("F#3", 6, 10)],
    [("A3", 0, 2), ("C4", 2, 4), ("Bb3", 4, 5), ("A3", 5, 10)],
]
for v in VOICES:
    for nm, b0, b1 in v:
        pad.note(b0, nm, b1 - b0, 0.6)
pad.fade(0, 1.4, -4, 0)           # swell into the cadence...
pad.fade(1.75, 2.6, 0, -9)        # ...then let the final chord breathe out

# ------------------------------------------------------------- choir bloom --
# the title's night-sky "oo" returns on the Picardy chord (two upper voices,
# F#-A, between the lead's low D and the flute's F#5)
ch = song.track("choir", choir("oo"), vol=-15, pan=0.0, reverb=0.5, hp=250, width=1.3)
ch.note(CAD, "F#4", 3.0, 0.5)
ch.note(CAD, "A4", 3.0, 0.45)
ch.fade(1.6, 2.5, 0, -8)

# -------------------------------------------------------------------- harp --
# falling broken chords, a 3rd under each accent of the lead, then a rolled
# D-major chord on the cadence
harp_t = song.track("harp", harp(), vol=-10, pan=0.4, reverb=0.4)
line(harp_t, 0, [("F5", 1, 0.62), ("D5", 1, 0.55), ("A4", 1, 0.62), ("F4", 1, 0.52),
                 ("D5", 1, 0.64), ("A4", 1, 0.55), ("F4", 1, 0.62), ("D4", 1, 0.52),
                 ("G4", 1, 0.64), ("E4", 1, 0.55)], unit=0.5)
harp_t.chord(1, ["D3", "A3", "D4", "F#4", "A4", "D5"], beats=3.0, vel=0.78, at=2.0, strum=0.05)

# ------------------------------------------------------------ magic sparkle --
# the hero's original x, rising, one last time -- then it fizzles
bell_t = song.track("bell", bell(), vol=-9, pan=-0.35, reverb=0.35, delay=0.2, hp=300)
line(bell_t, CAD, [("A5", 3, 0.5), ("A5", 1, 0.45), ("D6", 4, 0.72)])

# each blip chirps down from 4 semitones above: a spell sputtering, not a melody
fizz = song.track("fizzle", arp_pulse(pitch_env=4.0, pitch_decay=0.02), vol=-1, pan=0.4, reverb=0.3, delay=0.3, hp=400)
line(fizz, 7.5, [("D6", 1, 0.6), ("A5", 1, 0.5), ("F#5", 1, 0.42), ("D5", 1, 0.34)], unit=0.125)

# ------------------------------------------------------------------- drums --
dr = song.drums("drums", vol=-10, reverb=0.3)
dr.hit(0.0, "timp_lo", 0.6)        # the "game over" thud (under the player_die SFX)
dr.hit(0.0, "gong", 0.2)
# a reverse cymbal gathers the last bit of magic into the final chord
dr.hit(CAD - (1.5 / song.beat_sec(1)), "reverse_cymbal", 0.45)
dr.hit(5.0, "timp_hi", 0.55)       # cell x rhythm on the dominant: A. A | D
dr.hit(5.75, "timp_hi", 0.65)
dr.hit(CAD, "timp_lo", 1.0)        # the cadence is the loudest moment

if __name__ == "__main__":
    song.render()

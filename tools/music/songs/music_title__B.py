"""Magic Smash - title screen, angle B: "arcade anthem".

D minor, 120 bpm, 44 bars = 88 s (8 s intro that plays once + 80 s loop from bar 5).

Form (bar numbers 1-based as in the report / piano roll)
  1-4    intro      bell sings cell x augmented over Dmadd9-Bbmaj7-Gm6-A7sus4, harp ripples,
                    choir "oo"; snare roll + reverse cymbal; the lead's "wink" is the pickup.
  5-8    fanfare    LOOP START. Brass+bell stab x ("Ma-gic SMASH!") rising by step
                    Dm-Bb-C-A7, the chip lead answers each stab with a 16th run; wink turnaround.
  9-16   verse      new tune in the x rhythm over Dorian Dm-F-C-G | Dm-F-Bb-A7, lower register,
                    phrase pairs a-b a-b' (x rhythm bar, displaced-x syncopated bar).
  17-24  chorus     the full theme twice (MOTIF+ANSWER); 2nd time + lead_fm harmony, clap, arps.
  25-32  bridge     breakdown: chip kit half time, FM melody = x augmented and turned upside
                    down, sequenced F-C | G-D | A-E (climbing); bell and chip arp trade the
                    wink; Am7-B7 pivots up a whole step; the lead's wink in E minor is the pickup.
  33-40  chorus Em  climax: the theme lifted to E minor with everything in (harmony, brass
                    x-stabs, bell an octave up, choir).
  41-44  tag        x stabs falling by step C-Bb-A7sus4 (mirror of the fanfare) with lead runs
                    falling, A7 + tom fill + wink pickup -> loops back to bar 5 (Dm).
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403

song = Song("music_title__B", bpm=120, bars=44, reverb_seconds=2.4, reverb_damp=0.55)

# ------------------------------------------------------------------ harmony ---
THEME_CH = "Dm Gm:0.5 A:0.5 Bb:0.5 C:0.5 Dm"
THEME_CH_E = "Em Am:0.5 B:0.5 C:0.5 D:0.5 Em"
song.chords(0, "Dmadd9 Bbmaj7 Gm6 A7sus4:0.5 A7:0.5")         # intro
song.chords(4, "Dm Bb C A7")                                    # fanfare
song.chords(8, "Dm F C G Dm F Bb A7")                           # verse
song.chords(16, THEME_CH + " " + THEME_CH)                      # chorus (D minor)
song.chords(24, "Bbadd9 Cadd9 Am7 Dm7 Bbadd9 Cadd9 Am7 B7")     # bridge
song.chords(32, THEME_CH_E + " " + THEME_CH_E)                  # chorus (E minor)
song.chords(40, "C Bb A7sus4 A7")                               # tag / turnaround

for b, lbl in ((0, "intro"), (4, "fanfare"), (8, "verse"), (16, "chorus"), (24, "bridge"),
               (32, "chorus Em"), (40, "tag")):
    song.section(b, lbl)
song.loop(4)

# pad voicings: octave 3-4, no semitone pairs (maj7 / add9 kept out of the pad where the
# bass or the melody would rub against them)
VOICE = {
    "Dmadd9": "D3 A3 E4", "Bbmaj7": "D4 F4 A4", "Gm6": "G3 Bb3 D4 E4", "A7sus4": "A3 D4 E4",
    "A7": "A3 C#4 E4 G4", "Dm": "F3 A3 D4", "Bb": "F3 Bb3 D4", "C": "G3 C4 E4", "F": "F3 A3 C4",
    "G": "G3 B3 D4", "Gm": "G3 Bb3 D4", "A": "A3 C#4 E4", "Bbadd9": "D3 F3 Bb3 C4",
    "Cadd9": "E3 G3 C4 D4", "Am7": "E3 G3 A3 C4", "Dm7": "D3 F3 A3 C4", "B7": "D#3 F#3 A3 B3",
    "Em": "G3 B3 E4", "Am": "A3 C4 E4", "B": "B3 D#4 F#4", "D": "A3 D4 F#4",
}


def harmony_between(bar0, bar1):
    b0, b1 = song.bar_beat(bar0), song.bar_beat(bar1)
    return [(s, e, c) for s, e, c in song.harmony if s >= b0 and s < b1]


def pad_part(track, bar0, bar1, vel=0.6, voicing=VOICE, gap=0.06):
    for s, e, c in harmony_between(bar0, bar1):
        for n in voicing[c].split():
            track.note(s, n, e - s - gap, vel)


# ------------------------------------------------------------------- tracks ---
lead = song.track("lead", lead_pulse(cutoff=8000), vol=-7, pan=0.05, reverb=0.2, delay=0.1, hp=180)
fm_lead = song.track("fm_lead", lead_fm(), vol=-8, pan=-0.05, reverb=0.3, delay=0.15, hp=180)
counter = song.track("counter", lead_fm(), vol=-14, pan=-0.2, reverb=0.15, hp=180)
brass_t = song.track("brass", brass(), vol=-13, pan=-0.15, reverb=0.2, hp=150)
bell_t = song.track("bell", bell(), vol=-8, pan=-0.3, reverb=0.35, delay=0.2)      # intro melody, bridge winks
spark = song.track("sparkle", bell(), vol=-13, pan=-0.3, reverb=0.35, delay=0.2)   # octave-up echoes of the lead
harp_t = song.track("harp", harp(), vol=-10, pan=0.35, reverb=0.35)
arp = song.track("arp", arp_pulse(), vol=-7, pan=0.35, delay=0.15, hp=400, duck=0.2)
pad = song.track("strings", strings(), vol=-11, reverb=0.45, duck=0.35, hp=200)
choir_t = song.track("choir", choir("oo"), vol=-18, reverb=0.5, hp=200)
bass = song.track("bass", bass_fm(sub=0.12), vol=-7.5, duck=0.3, hp=35, reverb=0.0)
drums = song.drums("drums", vol=-6, reverb=0.1)

# ------------------------------------------------------------------- motifs ---
# The leitmotif (SOUNDTRACK.md), D minor, unit = 0.25
MOTIF = ("A4:3 A4:1 D5:4 F5:3 E5:1 A5:4 | "
         "Bb5:3 A5:1 G5:2 F5:2 E5:2 F5:1 E5:1 C#5:2 A4:2")
ANSWER = ("F5:3 F5:1 Bb5:4 G5:3 G5:1 C6:4 | "
          "D6:3 C6:1 A5:2 E5:1 C#5:1 D5:8")
HARM = ("F4:3 F4:1 A4:4 D5:3 D5:1 F5:4 | G5:3 F5:1 D5:2 D5:2 C#5:4 A4:2 E4:2 | "
        "D5:3 D5:1 F5:4 E5:3 E5:1 G5:4 | A5:3 A5:1 F5:2 C#5:1 A4:1 F4:8")
THEME_BASS = ("D2 D3 D2 D3 D2 D3 C3 A2 | G2 G3 G2 G3 A2 A3 A2 A3 | "
              "Bb1 Bb2 F2 Bb2 C2 C3 G2 E2 | D2 D3 A2 D3 D2 D3 A2 A1")
WINK = "-:8 E5:2 F5:1 E5:1 C#5:2 A4:1 -:1"      # beats 3-4 of an A7 bar: pickup into Dm
X_HITS = ((0.0, 0.62), (0.75, 0.2), (1.0, 0.9))   # cell x rhythm: (offset beats, length)


def stab_x(track, bar, chords, vel=0.8, at=0.0):
    """Chord stabs on the x rhythm. chords = (first, second, landing) voicings."""
    b0 = song.bar_beat(bar) + at
    for (off, ln), ch in zip(X_HITS, chords):
        for n in ch.split():
            track.note(b0 + off, n, ln, vel * (1.0 if off != 0.75 else 0.8))


# =================================================================== INTRO ====
# bell: cell x augmented, x' over Bbmaj7 (E = Lydian #11), peak Bb over Gm6, D sus4
bell_t.seq(0, "A5:6 A5:2 D6:8 | F5:7 E5:1 A5:8 | Bb5:7 A5:1 G5:4 E5:4 | D5:8", unit=0.25, vel=0.85)
lead.seq(3, WINK, unit=0.25, vel=0.8)
harp_t.arp(0, ["D3", "A3", "E4", "F4"], "0 1 2 3 4 5 6 7 6 5 4 3 2 1 2 3", unit=0.25, beats=4, vel=0.6)
harp_t.arp(1, ["Bb2", "F3", "A3", "D4"], "0 1 2 3 4 5 6 7 6 5 4 3 2 1 2 3", unit=0.25, beats=4, vel=0.6)
harp_t.arp(2, ["G2", "D3", "E3", "Bb3"], "0 1 2 3 4 5 6 7 6 5 4 3 2 1 2 3", unit=0.25, beats=4, vel=0.6)
harp_t.arp(3, ["A2", "E3", "G3", "D4"], "0 1 2 3 4 5 6 7", unit=0.25, beats=2, vel=0.6)
pad_part(pad, 0, 3, vel=0.5)
for n in VOICE["A7sus4"].split():
    pad.note(12, n, 1.94, 0.5)
for n in VOICE["A7"].split():
    pad.note(14, n, 1.0, 0.5)          # ends a beat early so no pad tail crosses the loop point
for beat, ln, ch in ((0, 3.9, "D4 A4"), (4, 3.9, "D4 F4"), (8, 3.9, "D4 E4"), (12, 1.9, "D4 E4"), (14, 1.0, "C#4 E4")):
    for n in ch.split():
        choir_t.note(beat, n, ln, 0.6)
bass.seq(0, "D2:16 | Bb1:16 | G1:16 | A1:8 A1:2 G2:2 E2:2 C#3:1 -:1", unit=0.25, vel=0.4)
drums.hit(0, "timp_lo", 0.6)
drums.hit(0, "gong", 0.22)
drums.hit(4, "timp_lo", 0.45)
drums.hit(8, "timp", 0.5)
drums.hit(12, "timp_hi", 0.55)
drums.pat(2, {"shaker": "o.o.x.o.o.o.x.o."}, bars=2)
drums.hit(13.0, "reverse_cymbal", 0.8)
drums.fill(3, "snare_ snare_ snare_ snare_ snare snare", unit=0.25, at=2.0)

# ================================================================= FANFARE ====
STABS_UP = [
    (4, ("D4 F4 A4", "D4 F4 A4", "F4 A4 D5"), "A5:3 A5:1 D6:4"),
    (5, ("Bb3 D4 F4", "Bb3 D4 F4", "D4 F4 Bb4"), "F5:3 F5:1 Bb5:4"),
    (6, ("C4 E4 G4", "C4 E4 G4", "E4 G4 C5"), "G5:3 G5:1 C6:4"),
    (7, ("A3 C#4 E4", "A3 C#4 E4", "C#4 E4 G4 A4"), "E5:3 E5:1 A5:4"),
]


def fanfare(bars_stabs, runs, bass_txt, bell_vel=0.8):
    for (bar, chords, bell_x), run in zip(bars_stabs, runs):
        stab_x(brass_t, bar, chords, vel=0.85)
        spark.seq(bar, bell_x, unit=0.25, vel=bell_vel)
        lead.seq(bar, run, unit=0.25)
    bass.seq(bars_stabs[0][0], bass_txt, unit=0.25)


fanfare(STABS_UP,
        ["-:10 D5:1 E5:1 F5:2 A5:2", "-:10 Bb4:1 C5:1 D5:2 F5:2", "-:10 C5:1 D5:1 E5:2 G5:2", WINK],
        "D2:3 D2:1 D3:4 A2:2 F2:2 A2:2 C3:2 | Bb1:3 Bb1:1 Bb2:4 F2:2 D2:2 F2:2 B1:2 | "
        "C2:3 C2:1 C3:4 G2:2 E2:2 C2:2 B1:2 | A1:3 A1:1 A2:4 G2:2 E2:2 A2:2 C#3:1 -:1")
pad_part(pad, 4, 8, vel=0.45)
FANFARE_KIT = {"kick": "x..x....x.x.....", "snare": "....x.......x...", "clap": "....x...........",
               "hat": "x...x...x...x...", "ohat": "..x...x...x...x."}
drums.pat(4, FANFARE_KIT, bars=3)
drums.pat(7, {"kick": "x..x....x.......", "snare": "....x...........", "clap": "....x...........",
              "hat": "..x.x.x........."})
drums.fill(7, "snare_ snare tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo", unit=0.25, at=2.0)
drums.hit(16, "crash", 0.85)

# =================================================================== VERSE ====
# a  = x rhythm + 8th-note turn;  b = x displaced (16th pickup after a rest), syncopated
VERSE = ("D5:3 D5:1 A5:4 F5:2 G5:2 A5:2 F5:2 | "      # Dm   a : rises a 5th, turns
         "-:3 E5:1 F5:4 -:2 C5:2 A4:4 | "              # F    b : answers, falls
         "C5:3 C5:1 G5:4 E5:2 F5:1 E5:1 G5:2 E5:2 | "  # C    a': a step lower, with the wink's wiggle
         "-:2 A4:2 B4:4 -:2 D5:2 G5:4 | "              # G    b': Dorian B, ends up on G (open)
         "D5:3 D5:1 A5:4 F5:2 G5:2 A5:2 F5:2 | "      # Dm   a
         "-:3 E5:1 F5:4 -:2 G5:2 A5:4 | "              # F    b'': now rises
         "D5:3 D5:1 F5:4 Bb5:7 A5:1 | "                # Bb   climax on the flat 6th
         "A5:3 G5:1 E5:2 C#5:2 E5:4 -:4")              # A7   half cadence, drum fill
_vb = VERSE.split("|")
lead.seq(8, "|".join(_vb[:4]), unit=0.25, vel=0.7)     # verse sits under the chorus
lead.seq(12, "|".join(_vb[4:]), unit=0.25, vel=0.76)
# second half: lead_fm guide-tone line underneath (3rds/6ths/4ths below the tune)
counter.seq(12, "A4:16 | A4:8 C5:8 | Bb4:8 D5:8 | C#5:8 -:8", unit=0.25, vel=0.7)
bass.seq(8, "D2 D3 D2 D3 D2 D3 D2 E2 | F2 F3 F2 F3 F2 F3 A2 G2 | C2 C3 C2 C3 C2 C3 B1 A1 | "
            "G1 G2 G1 G2 G1 A1 B1 C#2 | D2 D3 D2 D3 D2 D3 D2 E2 | F2 F3 F2 F3 F2 F3 C3 A2 | "
            "Bb1 Bb2 Bb1 Bb2 Bb1 Bb2 F2 D2 | A1 A2 A1 A2 E2 G2 B2 C#3", unit=0.5, vel=0.72)
pad_part(pad, 8, 16, vel=0.5)
for bar in range(12, 16):
    s, e, c = harmony_between(bar, bar + 1)[0]
    tones = [midi(n) + 12 for n in VOICE[c].split()][:3]
    arp.arp(bar, tones, "0 1 2 3 2 1 0 1", unit=0.25, beats=4, vel=0.55)
VERSE_KIT = {"kick": "x.....x.x.......", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x.",
             "shaker": ".o.o.o.o.o.o.o.o"}
VERSE_KIT2 = {"kick": "x.....x.x.....x.", "snare": "....x.......x...", "hat": "x.o.x.o.x.o.x.o.",
              "ohat": "..x...x...x...x."}
drums.pat(8, VERSE_KIT, bars=3)
drums.pat(11, {"kick": "x.....x.x.......", "snare": "....x.......x.x.", "hat": "x.x.x.x.x.x....."})
drums.pat(12, VERSE_KIT2, bars=3)
drums.pat(15, {"kick": "x...x...x...x...", "snare": "....x...x.x.xxxx", "hat": "x.x.x.x........."})
drums.fill(15, "tom_hi tom_mid tom_lo tom_lo", unit=0.25, at=3.0)
drums.hit(64, "crash", 0.9)

# ================================================================== CHORUS ====
CHORUS_KIT = {"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "xo.oxo.oxo.oxo.o",
              "ohat": "..x...x...x...x."}


def chorus(bar0, transpose, big):
    lead.seq(bar0, MOTIF + " | " + ANSWER, unit=0.25, transpose=transpose)
    lead.seq(bar0 + 4, MOTIF + " | " + ANSWER, unit=0.25, transpose=transpose)
    for b in (bar0, bar0 + 4):
        bass.seq(b, THEME_BASS, unit=0.5, transpose=transpose)
    pad_part(pad, bar0, bar0 + 8, vel=0.55)
    counter.seq(bar0 + (0 if big else 4), HARM, unit=0.25, transpose=transpose, vel=0.8)
    if big:
        counter.seq(bar0 + 4, HARM, unit=0.25, transpose=transpose, vel=0.85)
    # chip arps: second half (or all of the big chorus)
    for s, e, c in harmony_between(bar0 + (0 if big else 4), bar0 + 8):
        tones = [midi(n) + 12 for n in VOICE[c].split()][:3]
        arp.arp(s / 4, tones, "0 1 2 1", unit=0.25, beats=e - s, vel=0.5)
    for b in range(bar0, bar0 + 8, 4):
        drums.pat(b, CHORUS_KIT, bars=3)
        drums.pat(b + 3, {"kick": "x...x...x...x...", "snare": "....x.......x...",
                          "hat": "xo.oxo.oxo.o....", "ohat": "..x...x...x....."})
        drums.hit(song.bar_beat(b), "crash", 0.85)
    drums.fill(bar0 + 3, "snare_ snare snare tom_hi", unit=0.25, at=3.0)
    drums.pat(bar0, {"clap": "....x.......x..."}, bars=8)
    # brass x-stabs under every x of the theme (only the 2nd statement in chorus 1)
    v = {"Em": "G3 B3 E4", "C": "G3 C4 E4", "D": "A3 D4 F#4", "Dm": "F3 A3 D4", "Bb": "F3 Bb3 D4"}
    for b in ((bar0, bar0 + 4) if big else (bar0 + 4,)):
        for bb, at in ((b, 0.0), (b, 2.0), (b + 2, 0.0), (b + 2, 2.0)):
            c = song.chord_at(song.bar_beat(bb) + at)
            stab_x(brass_t, bb, (v[c],) * 3, vel=0.6 if big else 0.5, at=at)


chorus(16, 0, big=False)
drums.fill(23, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare snare", unit=0.25, at=2.0)
# bell sparkles on the last theme cadence of chorus 1
spark.seq(23, "D6:3 C6:1 A5:2 -:2 D6:8", unit=0.25, vel=0.8)

# ================================================================== BRIDGE ====
# x augmented and turned upside down (repeat, then fall a 4th), sequenced up by step;
# second time it breaks the pattern and climbs A-B-C to hand over to the E minor chorus.
fm_lead.seq(24, "F5:6 F5:2 C5:8 | G5:6 G5:2 D5:8 | A5:6 A5:2 E5:8 | D5:6 C5:2 A4:8 | "
                "F5:6 F5:2 C5:8 | G5:6 G5:2 D5:8 | A5:7 B5:1 C6:8 | B5:8", unit=0.25, vel=0.85)
# the wink, traded between chip arp (bars 25, 27, 29) and bell (26, 28, 30)
arp.seq(24, "F5:2 G5:1 F5:1 D5:2 Bb4:2", unit=0.25, at=2.0, vel=0.75)
bell_t.seq(25, "G6:2 A6:1 G6:1 E6:2 C6:2", unit=0.25, at=2.0, vel=0.45)
arp.seq(26, "C6:2 D6:1 C6:1 A5:2 E5:2", unit=0.25, at=2.0, vel=0.75)
bell_t.seq(27, "F6:2 G6:1 F6:1 D6:2 A5:2", unit=0.25, at=2.0, vel=0.45)
arp.seq(28, "F5:2 G5:1 F5:1 D5:2 Bb4:2", unit=0.25, at=2.0, vel=0.75)
bell_t.seq(29, "G6:2 A6:1 G6:1 E6:2 C6:2", unit=0.25, at=2.0, vel=0.45)
# the hero comes back with the wink in E minor as the pickup
lead.seq(31, "-:8 F#5:2 G5:1 F#5:1 D#5:2 B4:2", unit=0.25)
brass_t.chord(31, ["B3", "D#4", "F#4", "A4"], beats=1.5, vel=0.8)
harp_rip = {"Bbadd9": ["Bb2", "F3", "C4", "D4"], "Cadd9": ["C3", "G3", "D4", "E4"],
            "Am7": ["A2", "E3", "G3", "C4"], "Dm7": ["D3", "A3", "C4", "F4"]}
for bar in range(24, 30):
    c = harmony_between(bar, bar + 1)[0][2]
    harp_t.arp(bar, harp_rip[c], "0 1 2 3 4 5 6 7", unit=0.25, beats=2, vel=0.55)
pad_part(pad, 24, 32, vel=0.6)
for bar in range(24, 31):
    c = harmony_between(bar, bar + 1)[0][2]
    for n in VOICE[c].split()[1:3]:
        choir_t.note(song.bar_beat(bar), n, 3.9, 0.55)
bass.seq(24, "Bb1:6 Bb2:2 F2:8 | C2:6 C3:2 G2:4 B1:4 | A1:6 A2:2 E2:4 C2:4 | D2:6 D3:2 A2:4 C3:4 | "
             "Bb1:6 Bb2:2 F2:8 | C2:6 C3:2 G2:4 B1:4 | A1:6 A2:2 E2:4 G2:2 A2:2 | "
             "B1:2 B2:2 B1:2 B2:2 B1:2 B2:2 F#2:2 D#2:2", unit=0.25, vel=0.6)
CHIP_KIT = {"kick_chip": "x.........x.....", "snare_chip": "........x.......", "hat_chip": "x.o.x.o.x.o.x.o."}
drums.pat(24, CHIP_KIT, bars=5)
drums.pat(29, {"kick_chip": "x.........x.....", "snare_chip": "........x...x.xx", "hat_chip": "x.o.x.o.x.o....."})
drums.pat(30, {"kick": "x.......x.......", "snare": "o.o.o.o.x.x.x.x.", "hat": "x.x.x.x.x.x.x.x."})
drums.pat(31, {"kick": "x...x...........", "snare": "oxoxxxxX........"}, bars=1)
drums.fill(31, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^", unit=0.25, at=2.0)
drums.hit(31 * 4, "riser", 0.7)
drums.hit(31 * 4 + 1.0, "reverse_cymbal", 0.7)

# =============================================================== CHORUS Em ====
chorus(32, 2, big=True)
# bell an octave above the lead on the second statement
spark.seq(36, MOTIF + " | " + ANSWER, unit=0.25, transpose=14, vel=0.6)
for bar in range(32, 40):
    for s, e, c in harmony_between(bar, bar + 1):
        for n in VOICE[c].split()[1:3]:
            choir_t.note(s, n, e - s - 0.06, 0.5)
drums.fill(39, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare snare", unit=0.25, at=2.0)

# ===================================================================== TAG ====
STABS_DOWN = [
    (40, ("C4 E4 G4", "C4 E4 G4", "E4 G4 C5"), "G5:3 G5:1 C6:4"),
    (41, ("Bb3 D4 F4", "Bb3 D4 F4", "D4 F4 Bb4"), "F5:3 F5:1 Bb5:4"),
    (42, ("A3 D4 E4", "A3 D4 E4", "D4 E4 A4"), "E5:3 E5:1 A5:4"),
]
fanfare(STABS_DOWN,
        ["-:8 G5:1 F5:1 E5:2 C5:2 E5:2", "-:8 F5:1 E5:1 D5:2 Bb4:2 D5:2", "-:8 E5:1 D5:1 A4:2 D5:2 E5:2"],
        "C2:3 C2:1 C3:4 C2:2 G2:2 E2:2 C2:2 | Bb1:3 Bb1:1 Bb2:4 Bb1:2 F2:2 D2:2 Bb1:2 | "
        "A1:3 A1:1 A2:4 A1:2 E2:2 A2:2 E2:2", bell_vel=0.7)
brass_t.chord(43, ["A3", "C#4", "E4", "G4"], beats=1.5, vel=0.85)
lead.seq(43, WINK, unit=0.25)
bass.seq(43, "A1:3 A1:1 A2:4 G2:2 E2:2 A2:2 C#3:2", unit=0.25)
pad_part(pad, 40, 44, vel=0.5)
drums.pat(40, FANFARE_KIT, bars=3)
drums.pat(43, {"kick": "x..x............", "clap": "....x...........", "hat": "..x.x..........."}, bars=1)
drums.hit(160, "crash", 0.8)
drums.hit(43 * 4, "timp_hi", 0.8)
drums.fill(43, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare snare", unit=0.25, at=2.0)

# ------------------------------------------------------------- dynamics ---
def gain_steps(track, pts):
    """Step automation: pts = [(bar, dB), ...], each level held until the next point."""
    for bar, g in pts:
        b = song.bar_beat(bar)
        track.automation.append((max(0.0, b - 0.02), track.automation[-1][1] if track.automation else g))
        track.automation.append((b, g))


# verse 2.5-3 dB under the hook, breakdown lower still (chip kit), climax a touch hotter
gain_steps(drums, [(0, 0.0), (8, -3.0), (12, -1.5), (15, -0.5), (16, 0.0), (24, -1.0), (30, 0.0), (32, 0.5), (40, 0.0)])
gain_steps(bass, [(0, 0.0), (8, -1.5), (12, -1.0), (16, 0.0), (24, -1.0), (32, 0.5), (40, 0.0)])

if __name__ == "__main__":
    song.render(out_dir=os.path.join(HERE, "out", "candidates"))

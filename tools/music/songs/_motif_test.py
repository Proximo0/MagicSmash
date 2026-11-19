"""Scratch test for the Magic Smash leitmotif (see ../SOUNDTRACK.md).

Renders four short candidates into out/candidates:
  motif_fast      theme statement at battle speed (160 bpm) with counter in 3rds/6ths
  motif_title     same theme augmented (unit 0.5) at title tempo (108 bpm)
  motif_boss      the tritone / harmonic-minor distortion in C minor (176 bpm)
  motif_gameover  the falling inversion as a 2-bar jingle (84 bpm, no loop)
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403

CAND = os.path.join(HERE, "out", "candidates")

# ---- the theme, reference key D minor, unit = 0.25 (16ths) ----------------
MOTIF = ("A4:3 A4:1 D5:4 F5:3 E5:1 A5:4 | "              # bar 1  Dm      call x + x'
         "Bb5:3 A5:1 G5:2 F5:2 E5:2 F5:1 E5:1 C#5:2 A4:2")  # bar 2  Gm A    peak + wink
ANSWER = ("F5:3 F5:1 Bb5:4 G5:3 G5:1 C6:4 | "             # bar 3  Bb C    x climbs by step
          "D6:3 C6:1 A5:2 E5:1 C#5:1 D5:8")                # bar 4  Dm      cadence
HARM = ("F4:3 F4:1 A4:4 D5:3 D5:1 F5:4 | "
        "G5:3 F5:1 D5:2 D5:2 C#5:4 A4:2 E4:2 | "
        "D5:3 D5:1 F5:4 E5:3 E5:1 G5:4 | "
        "A5:3 A5:1 F5:2 C#5:1 A4:1 F4:8")
CHORDS = "Dm Gm:0.5 A:0.5 Bb:0.5 C:0.5 Dm"


def fast():
    s = Song("motif_fast", bpm=160, bars=8, reverb_seconds=1.6)
    s.chords(0, CHORDS + " " + CHORDS)
    s.section(0, "theme").section(4, "theme+harmony")
    lead = s.track("lead", lead_pulse(cutoff=8000), vol=-8, pan=0.08, reverb=0.15, delay=0.1, hp=180)
    for b in (0, 4):
        lead.seq(b, MOTIF + " | " + ANSWER, unit=0.25)
    arp = s.track("arp", arp_pulse(), vol=-13, pan=0.35, delay=0.15, hp=400, duck=0.2)
    for b0, b1, c in s.harmony[len(s.harmony) // 2:]:
        arp.arp(b0 / 4, chord_tones(c, 4), "0 1 2 3 2 1", unit=0.25, beats=b1 - b0)
    ctr = s.track("counter", lead_fm(), vol=-14, pan=-0.25, reverb=0.15, hp=180)
    ctr.seq(4, HARM, unit=0.25)
    bass = s.track("bass", bass_fm(), vol=-7, duck=0.3)
    bl = ("D2 D3 D2 D3 D2 D3 C3 A2 | G2 G3 G2 G3 A2 A3 A2 A3 | "
          "Bb1 Bb2 F2 Bb2 C2 C3 G2 E2 | D2 D3 A2 D3 D2 D3 A2 A1")
    for b in (0, 4):
        bass.seq(b, bl, unit=0.5)
    pad = s.track("pad", strings(), vol=-11, reverb=0.4, duck=0.35, hp=200)
    for b0, b1, c in s.harmony:
        for m in chord_tones(c, 3):
            pad.note(b0, m, b1 - b0 - 0.1, 0.6)
    d = s.drums(vol=-6, reverb=0.06)
    for b in (0, 4):
        d.pat(b, {"kick": "x.....x.x.....x.", "snare": "....x.......x...",
                  "hat": "x.x.x.x.x.x.x.x." if b == 0 else "x.xox.xox.xox.xo",
                  "ohat": "................" if b == 0 else "..x...x...x...x."}, bars=3)
        d.pat(b + 3, {"kick": "x.....x.x.......", "snare": "....x.......x...", "hat": "x.x.x.x.x.x....."})
        d.fill(b + 3, "snare_ snare tom_hi tom_lo", at=3.0)
        d.hit(s.bar_beat(b), "crash", 0.8)
    s.render(out_dir=CAND)


def title():
    s = Song("motif_title", bpm=108, bars=8, reverb_seconds=2.8)
    s.chords(0, "Dm:2 Gm A Bb C Dm:0.75 A:0.25 Dm")
    s.section(0, "theme x2 augmented")
    lead = s.track("lead", lead_pulse(), vol=-8, pan=0.05, reverb=0.28, delay=0.12, hp=180)
    lead.seq(0, MOTIF + " | " + ANSWER, unit=0.5)
    br = s.track("brass", brass(), vol=-13, pan=-0.15, reverb=0.3, hp=150)
    br.seq(0, HARM, unit=0.5)
    bass = s.track("bass", bass_nes(), vol=-11)
    bass.seq(0, "D2:8 | D2:4 A1:4 | G1:8 | A1:8 | Bb1:8 | C2:8 | D2:6 A1:2 | D2:8", unit=0.5)
    pad = s.track("strings", strings(), vol=-17, reverb=0.45, hp=200)
    voicing = {"Dm": "D3 A3 D4", "Gm": "G3 D4 G4", "A": "A3 C#4 A4", "Bb": "Bb3 F4 D4", "C": "C4 G4 E4"}
    for b0, b1, c in s.harmony:
        for m in voicing[c].split():
            pad.note(b0, m, b1 - b0 - 0.1, 0.6)
    d = s.drums(vol=-8, reverb=0.2)
    # timp voices are fixed pitches: timp_lo=D2, timp=G2, timp_hi=A2 -> pick the one in the chord
    timp_for = {"Dm": "timp_lo", "Gm": "timp", "A": "timp_hi", "Bb": "timp_lo", "C": "timp"}
    for b0, b1, c in s.harmony:
        d.hit(b0, timp_for[c], 0.8)
    d.fill(7, "timp_hi timp_hi timp_hi timp_hi timp_hi^ timp_hi^ timp_lo^ -", unit=0.25, at=2.0)
    d.hit(0, "crash", 0.7)
    s.render(out_dir=CAND)


BOSS = ("G4:3 G4:1 Db5:4 Eb5:3 Eb5:1 G5:4 | "             # Gdim/Db Cm : tritone call
        "Ab5:3 G5:1 F5:2 Eb5:2 D5:2 Eb5:1 D5:1 B4:2 G4:2 | "  # Fm G   : harmonic-minor wink
        "Eb5:3 Eb5:1 Ab5:4 B4:3 B4:1 F5:4 | "             # Ab G7    : x falls instead of climbing
        "Eb5:3 D5:1 C5:2 G4:1 B4:1 C5:8")                 # Cm
BOSS_CHORDS = "Gdim/Db:0.5 Cm:0.5 Fm:0.5 G:0.5 Ab:0.5 G7:0.5 Cm"


def boss():
    s = Song("motif_boss", bpm=176, bars=4, reverb_seconds=2.2)
    s.chords(0, BOSS_CHORDS)
    s.section(0, "boss motif")
    lead = s.track("lead", lead_saw(cutoff=5500), vol=-7, pan=0.05, reverb=0.15, delay=0.1, hp=180)
    lead.seq(0, BOSS, unit=0.25)
    bass = s.track("bass", bass_saw(sub=0.25), vol=-8, duck=0.3, hp=40)
    bass.seq(0, "Db2 Db2 Db3 Db2 C2 C3 C2 C3 | F1 F2 F1 F2 G1 G2 G1 G2 | "
                "Ab1 Ab2 Ab1 Ab2 G1 G2 G1 G2 | C2 C3 C2 C3 C2 C3 G1 B1", unit=0.5)
    org = s.track("organ", organ(), vol=-19, reverb=0.35, hp=200)
    for b0, b1, c in s.harmony:
        for m in chord_tones(c, 3)[-3:]:
            org.note(b0, m, b1 - b0 - 0.1, 0.6)
    d = s.drums(vol=-11, reverb=0.08)
    d.pat(0, {"kick_hard": "x.x...x.x.x...x.", "snare_tight": "....x.......x...",
              "hat": "xoxoxoxoxoxoxoxo"}, bars=4)
    d.hit(0, "gong", 0.7)
    s.render(out_dir=CAND)


def gameover():
    s = Song("motif_gameover", bpm=84, bars=2, reverb_seconds=2.6)
    s.chords(0, "Dm:0.5 Bb:0.5 Gm:0.5 A:0.25 Dm:0.25")
    s.section(0, "jingle")
    s.no_loop(tail=2.0)
    go_line = "A5:3 A5:1 D5:4 F5:3 E5:1 Bb4:4 | Bb4:3 A4:1 G4:2 F4:2 E4:1 F4:1 E4:1 C#4:1 D4:12"
    lead = s.track("lead", lead_pulse(duty=0.5, vib_depth=0.25), vol=-9, reverb=0.35, delay=0.12, hp=180)
    lead.seq(0, go_line, unit=0.25, vel=0.7)
    fl = s.track("flute", flute(), vol=-13, pan=-0.2, reverb=0.4)
    fl.seq(0, go_line, unit=0.25, transpose=12, vel=0.6)
    bass = s.track("bass", bass_nes(), vol=-13)
    bass.seq(0, "D2:2 Bb1:2 | G1:2 A1 D2:3", unit=1.0)
    pad = s.track("strings", strings(), vol=-16, reverb=0.5, hp=200)
    for b0, b1, c in s.harmony:
        for m in chord_tones(c, 3):
            pad.note(b0, m, (b1 - b0 - 0.1) if b1 < 8 else 3.0, 0.55)
    harp_t = s.track("harp", harp(), vol=-15, pan=0.35, reverb=0.4)
    harp_t.seq(0, "D5 A4 F4 D4 Bb4 F4 D4 Bb3 | G4 D4 Bb3 G3 A3 E4", unit=0.5)
    harp_t.chord(1, ["D4", "F4", "A4"], beats=2, at=3.0, strum=0.06)
    fz = s.track("fizzle", arp_pulse(), vol=-10, pan=-0.3, delay=0.25)
    fz.seq(1, "D6_ A5_ F5_ D5_", unit=0.125, at=3.5)
    d = s.drums(vol=-9, reverb=0.3)
    d.hit(s.bar_beat(1) + 3, "timp_lo", 0.9)
    s.render(out_dir=CAND)


if __name__ == "__main__":
    which = sys.argv[1:] or ["fast", "title", "boss", "gameover"]
    for w in which:
        globals()[w]()

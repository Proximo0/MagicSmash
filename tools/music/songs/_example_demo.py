import os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *
t0=time.time()
song = Song("demo", bpm=152, bars=8)
song.chords(0, "Em C D B7 Em C D B7")
song.section(0, "A")
lead = song.track("lead", lead_pulse(), vol=-9, pan=0.1, reverb=0.2, delay=0.15)
lead.seq(0, "E5:2 B4 E5 G5:3 F#5 | E5:2 D5:2 B4:4 | C5:2 E5 G5 C6:3 B5 | A5:2 F#5:2 D5:4 | E5:2 B4 E5 G5:3 A5 | B5:3 A5 G5:2 F#5:2 | E5:2 G5 C6 B5:2 A5:2 | B5:6 -:2")
bass = song.track("bass", bass_fm(), vol=-7, duck=0.25)
for b, c in enumerate("E2 C2 D2 B1 E2 C2 D2 B1".split()):
    r = midi(c)
    bass.seq(b, " ".join([name_of(r), name_of(r), name_of(r+12), name_of(r)]*2), unit=0.5)
pad = song.track("pad", strings(), vol=-15, reverb=0.4)
for b, c in enumerate("Em C D B7 Em C D B7".split()):
    pad.chord(b, chord_tones(c, 4))
arp = song.track("arp", arp_pulse(), vol=-17, pan=-0.3, delay=0.2)
for b, c in enumerate("Em C D B7 Em C D B7".split()):
    arp.arp(b, chord_tones(c, 5), "0 1 2 1", unit=0.25)
harpt = song.track("harp", harp(), vol=-14, pan=0.35, reverb=0.3)
harpt.arp(0, chord_tones("Em", 4), "0 1 2 3 2 1", unit=0.25, beats=8)
choirt = song.track("choir", choir(), vol=-16, reverb=0.5)
choirt.chord(4, chord_tones("Em",4), beats=16)
d = song.drums(vol=-5)
d.pat(0, {"kick":"x.......x.x.....", "snare":"....x.......x...", "hat":"x.x.x.x.x.x.x.xo"}, bars=8)
d.fill(7, "- - - - - - - - tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare^ snare^")
d.hit(0, "crash")
song.render(out_dir=os.path.join(HERE, "out", "candidates"))
print("time", time.time()-t0)

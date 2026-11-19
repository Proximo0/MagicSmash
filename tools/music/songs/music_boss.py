"""Magic Smash - BOSS FIGHT vs the Lich Lord.  Final arrangement (from candidate B, "frantic chip-metal",
with grafts from candidate A).

C minor (harmonic minor + Phrygian Db), 176 bpm, 60 bars (81.8 s), loops from bar 0.

Three voices fight over one leitmotif (see ../SOUNDTRACK.md):
  lead   lead_saw     the Lich: the tritone version of "Ma-gic SMASH!" (G G Db)
  shred  pulse 12.5%  chip shredder: diminished sweeps and twin-lead harmonies
  hero   lead_pulse   the hero voice: the ORIGINAL rising-4th theme breaks through, and gets the last word

Form (bars, 1-based)
  1-4    Intro      Lich chord stabs in x rhythm, audible CmMaj7 chip arp ("villain chord"), Neapolitan Db,
                    then bar 4: brass + bass state the Lich's x in unison through the dim7 (B-F, D-Ab) with toms
  5-12   A1         call (tritone x) / answer (sweep), call / Neapolitan answer over N6 (Db/F) -> G7b9,
                    x climbs the diminished chord in minor 3rds (B-F, D-Ab, F-B, Ab-D),
                    peak on Eb6, x + the wink close onto the low G (leads into the call).  Verse level.
  13-20  A2         same tune, the chip shredder answers each call; the dim climb is a
                    twin-lead harmony a minor 3rd apart; open hats + clap
  21-28  B          the full distorted theme twice (the loudest so far): brass x stabs, then brass harmony,
                    choir "ah", ride, 8th octave bass -> 16ths, timpani + gong on the downbeat
  29-36  Bridge     lament bass C B Bb A Ab Db; the lead rises against it in long notes; skank beat;
                    diminished shred cascade written as a ritardando (16ths -> 8ths -> 4th)
  37-44  Break      half time: the theme slowed to half speed, shared between organ (calls)
                    and bell (the wink - "the Lich laughs"); the bass plays x in augmentation
                    (tritone Db-G); timpani roll + snare roll + riser into the climax
  45-48  Climax 1   theme on the saw with the brass imitating it one bar behind (free canon, organ out);
                    the brass ends on the hero's G-G-C and the hero's snare rallies on beat 4
  49-52  Hero       the players fight back: the hero's own theme (G G C - rising 4th) on the
                    pulse lead, gallop bass, brass HARM, ending on a C MAJOR chord (Picardy)
  53-58  FINAL FORM the Lich answers a half step higher, in C# minor: G#dim/D crushes the hero's C major
                    (G->G#, C->B, E->D); call, Neapolitan, twin dim climb, E6 peak, close; dense double kick
  59-60  Turnaround G#7 = German augmented 6th of C minor -> Cm/G (cadential 6/4): the hero replies with
                    his x (G G C), the band hits "SMASH", then G7b9: shred sweep + toms + riser -> loop

Voice-leading notes: the Neapolitan sits in first inversion (Db/F) and the Ab under the peak is
Ab/C, so the saw lead never moves in parallel 5ths/8ves with the bass; in the hero answer the bass
takes the 5th (F) under the lead's Bb, as in the bible's tested bass.
Mix: section level arc via step automation (verse -> hook +2-3 dB, break -4/-5 dB, final form on top);
bass_saw sub 0.15 + low shelf (the 0.25 sub swamped the kick_hard kit); organ out under the canon.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403

U = 0.25          # one 16th in beats
BAR = 4.0

song = Song("music_boss", bpm=176, bars=60, reverb_seconds=2.2, delay_feedback=0.3)
song.loop(0)

# ------------------------------------------------------------------ harmony ---
HARMONY = [
    # 1-4 intro
    "Cm", "Cm", "Db", "G7b9",
    # 5-12 A1
    "Gdim/Db:0.5 Cm:0.5", "Ab:0.5 G7b9:0.5", "Gdim/Db:0.5 Cm:0.5", "Db/F:0.5 G7b9:0.5",
    "G7b9", "G7b9", "Cm:0.5 Ab/C:0.5", "Fm:0.5 G7b9:0.5",
    # 13-20 A2
    "Gdim/Db:0.5 Cm:0.5", "Ab:0.5 G7b9:0.5", "Gdim/Db:0.5 Cm:0.5", "Db/F:0.5 G7b9:0.5",
    "G7b9", "G7b9", "Cm:0.5 Ab/C:0.5", "Fm:0.5 G7b9:0.5",
    # 21-28 B (theme x2)
    "Gdim/Db:0.5 Cm:0.5", "Fm:0.5 G:0.5", "Ab:0.5 G7:0.5", "Cm",
    "Gdim/Db:0.5 Cm:0.5", "Fm:0.5 G:0.5", "Ab:0.5 G7:0.5", "Cm",
    # 29-36 bridge (lament bass)
    "Cm", "G/B", "Cm7/Bb", "Adim7", "Fm/Ab", "Db", "G7b9", "G7b9",
    # 37-44 break (half time)
    "Gdim/Db", "Cm", "Fm7", "G7b9", "Ab", "G7", "Cm", "G7b9",
    # 45-48 climax 1
    "Gdim/Db:0.5 Cm:0.5", "Fm:0.5 G:0.5", "Ab:0.5 G7:0.5", "Cm",
    # 49-52 hero
    "Cm", "Fm:0.5 G:0.5", "Ab:0.5 Bb:0.5", "C",
    # 53-58 FINAL FORM (written in C minor here, lifted a half step to C# minor below) + 59-60 turnaround
    "Gdim/Db:0.5 Cm:0.5", "Db/F:0.5 G7b9:0.5", "G7b9", "G7b9",
    "Cm:0.5 Ab/C:0.5", "Fm:0.5 G7b9:0.5",
    "Cm/G", "G7b9",          # G#7 (= Ger+6 of C minor) -> Cm/G cadential 6/4 -> G7b9 -> loop
]
assert len(HARMONY) == 60

FF = 1                       # final form: +1 semitone (C# minor)
FF_BARS = range(52, 58)
SHARPS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def tsym(sym, n):
    """Transpose a chord symbol ('Gdim/Db' +1 -> 'G#dim/D')."""
    r, q, b = re.fullmatch(r"([A-G][#b]?)([^/]*)(?:/([A-G][#b]?))?", sym).groups()
    tn = lambda x: SHARPS[(midi(x + "4") + n) % 12]
    return tn(r) + q + ("/" + tn(b) if b else "")


def tharm(text, n):
    return " ".join(tsym(t.split(":")[0], n) + (":" + t.split(":")[1] if ":" in t else "") for t in text.split())


FF_SRC = {}                  # transposed symbol -> C-minor source symbol
for b in FF_BARS:
    for tok in HARMONY[b].split():
        FF_SRC[tsym(tok.split(":")[0], FF)] = tok.split(":")[0]
    HARMONY[b] = tharm(HARMONY[b], FF)
for i, h in enumerate(HARMONY):
    song.chords(i, h)

for bar, label in [(0, "intro"), (4, "A1 call/answer"), (12, "A2 +shredder"), (20, "B theme"),
                   (28, "bridge"), (36, "break (half time)"), (44, "climax canon"), (48, "HERO"),
                   (52, "FINAL FORM C#m"), (58, "turnaround")]:
    song.section(bar, label)


def segs(bar_from, bar_to):
    """Harmony segments (beat0, beat1, chord) inside [bar_from, bar_to)."""
    a, b = bar_from * BAR, bar_to * BAR
    return [(b0, b1, c) for b0, b1, c in song.harmony if a <= b0 < b]


# -------------------------------------------------------------- melodies ---
# Boss theme (bible), unit 1/16. Accents on the "SMASH" landings.
BOSS1 = "G4:3 G4:1 Db5^:4 Eb5:3 Eb5:1 G5^:4"                       # Gdim/Db Cm  tritone call
BOSS2 = "Ab5^:3 G5:1 F5:2 Eb5:2 D5:2 Eb5:1 D5:1 B4:2 G4:2"          # Fm G        harmonic-minor wink
BOSS3 = "Eb5:3 Eb5:1 Ab5^:4 B4:3 B4:1 F5^:4"                        # Ab G7       x falls
BOSS4 = "Eb5^:3 D5:1 C5:2 G4:1 B4:1 C5:8"                           # Cm
BOSS = " | ".join([BOSS1, BOSS2, BOSS3, BOSS4])
# harmony line in 3rds/6ths (parallel tritones under the call)
BOSS_HARM = ("Db4:3 Db4:1 G4:4 C5:3 C5:1 Eb5:4 | F5:3 Eb5:1 C5:4 B4:4 G4:2 D4:2 | "
             "C5:3 C5:1 Eb5:4 G4:3 G4:1 D5:4 | C5:3 B4:1 G4:2 Eb4:1 D4:1 Eb4:8")

# Section A tune (8 bars). Each bar is 16 sixteenths.
CALL = BOSS1
SWEEP = "Ab4:1 C5:1 Eb5:1 Ab5:1 C6^:4 B5^:3 Ab5:1 F5:2 D5:1 B4:1"   # Ab sweep up -> scream; x falls down Bdim7
NEAP = "Ab5:3 Ab5:1 Db6^:4 B5:1 C6:1 B5:1 Ab5:1 G5^:4"             # rising 4th inside the Neapolitan, Db -> B
CLIMB1 = "B4:3 B4:1 F5^:4 D5:3 D5:1 Ab5^:4"                         # x climbs the dim7 in minor 3rds
CLIMB2 = "F5:3 F5:1 B5^:4 Ab5:3 Ab5:1 D6^:4"
PEAK = "Eb6^:4 D6:1 C6:1 B5:1 C6:1 Ab5^:3 G5:1 Eb5:4"              # resolution D6 -> Eb6, wink-turn
CLOSE = "C5:3 C5:1 F5^:4 D5:2 Eb5:1 D5:1 B4:2 G4:2"                # x on iv + the wink, drop to low G
# shredder (pulse 12.5%) answers + twin harmonies a minor 3rd below
SWEEP2 = "C6:1 Ab5:1 Eb5:1 C5:1 Eb5:1 Ab5:1 C6:1 Eb6:1 D6^:2 B5:1 Ab5:1 F5:1 D5:1 B4:1 Ab4:1"
NEAP2 = "Db5:1 F5:1 Ab5:1 Db6:1 C6:1 Ab5:1 F5:1 Db5:1 B4:1 D5:1 F5:1 Ab5:1 B5^:2 G5:2"
CLIMB1_LO = "Ab4:3 Ab4:1 D5:4 B4:3 B4:1 F5:4"
CLIMB2_LO = "D5:3 D5:1 Ab5:4 F5:3 F5:1 B5:4"
PEAK_LO = "C6:4 B5:1 Ab5:1 G5:1 Ab5:1 Eb5:3 Eb5:1 C5:4"

# Bridge: long note + turn / x falling, rising against the lament bass
BRIDGE = ("C5^:12 D5:1 C5:1 B4:1 C5:1 | D5:3 D5:1 G4^:4 B4:8 | "
          "Eb5^:12 F5:1 Eb5:1 D5:1 Eb5:1 | Gb5:3 Gb5:1 C5^:4 Eb5:8 | "
          "F5^:12 G5:1 F5:1 E5:1 F5:1 | Ab5:3 Ab5:1 Db5^:4 F5:8")
DIM_SHRED = ("B4:1 D5:1 F5:1 Ab5:1 B5:1 D6:1 B5:1 Ab5:1 F5:1 D5:1 B4:1 Ab4:1 B4:1 D5:1 F5:1 Ab5:1 | "
             "B5^:4 Ab5:2 F5:2 D5:2 B4:2 G4^:4")                    # 16ths -> 8ths -> quarter
RISE = ("G4:1 B4:1 D5:1 F5:1 Ab4:1 B4:1 D5:1 F5:1 B4:1 D5:1 F5:1 Ab5:1 D5:1 F5:1 Ab5:1 B5:1")
TURN = ("G4:1 B4:1 D5:1 F5:1 Ab5:1 F5:1 D5:1 B4:1 D5:1 F5:1 Ab5:1 B5:1 D6^:2 B5:1 B4.:1")   # last note short: clean seam

# The hero's own theme, transposed from D minor to C minor (bible MOTIF + ANSWER, -2)
HERO = ("G4:3 G4:1 C5^:4 Eb5:3 D5:1 G5^:4 | Ab5^:3 G5:1 F5:2 Eb5:2 D5:2 Eb5:1 D5:1 B4:2 G4:2 | "
        "Eb5:3 Eb5:1 Ab5^:4 F5:3 F5:1 Bb5^:4 | C6^:3 Bb5:1 G5:2 D5:1 B4:1 C5:8")
HERO_HARM = ("Eb4:3 Eb4:1 G4:4 C5:3 C5:1 Eb5:4 | F5:3 Eb5:1 C5:4 B4:4 G4:2 D4:2 | "
             "C5:3 C5:1 Eb5:4 D5:3 D5:1 F5:4 | G5:3 G5:1 E5:2 B4:1 G4:1 E4:8")   # E natural: Picardy

# -------------------------------------------------------------- instruments ---
lead = song.track("lead", lead_saw(cutoff=5500), vol=-7, pan=0.0, reverb=0.15, delay=0.1, hp=180)
shred = song.track("shred", lead_pulse(duty=0.125, cutoff=6500), vol=-6.5, pan=0.08, reverb=0.12,
                   delay=0.1, hp=180)
hero = song.track("hero", lead_pulse(cutoff=8000), vol=-6, pan=0.0, reverb=0.18, delay=0.12, hp=180)
brass_t = song.track("brass", brass(), vol=-13, pan=-0.2, reverb=0.15, hp=150)
bass = song.track("bass", bass_saw(sub=0.15), vol=-8, duck=0.3, hp=40, eq=(("lowshelf", 80, -2.0, 0.707),))
organ_t = song.track("organ", organ(), vol=-19, reverb=0.35, hp=200)
organ_ld = song.track("organ_lead", organ(), vol=-9.5, pan=-0.1, reverb=0.4, delay=0.12, hp=200)   # break melody
choir_t = song.track("choir", choir("ah"), vol=-17, reverb=0.45, duck=0.35, hp=200)
bell_t = song.track("bell", bell(), vol=-10, pan=-0.3, reverb=0.35, delay=0.2)
arp = song.track("arp", arp_pulse(), vol=-10, pan=0.35, reverb=0.1, delay=0.15, hp=400, duck=0.2)
drums = song.drums("drums", vol=-12.5, reverb=0.08, eq=[("lowshelf", 90, -2.5, 0.7)])
cym = song.drums("cymbals", vol=-8, reverb=0.08)     # hats / ride on their own fader (presence)
CYM = ("hat", "ohat", "ride", "hat_chip", "shaker")
fx = song.drums("fx", vol=-12, reverb=0.25)

# --- saw lead (the Lich)
for bar, part in [(4, CALL), (5, SWEEP), (6, CALL), (7, NEAP), (8, CLIMB1), (9, CLIMB2), (10, PEAK), (11, CLOSE),
                  (12, CALL), (14, CALL), (16, CLIMB1), (17, CLIMB2), (18, PEAK), (19, CLOSE),
                  (20, BOSS), (24, BOSS), (28, BRIDGE),
                  (44, BOSS)]:
    lead.seq(bar, part, unit=U)
# final form: the whole A tune a half step up (C# minor); peak E6
for bar, part in [(52, CALL), (53, NEAP), (54, CLIMB1), (55, CLIMB2), (56, PEAK), (57, CLOSE)]:
    lead.seq(bar, part, unit=U, transpose=FF)

# --- shredder
for bar, part in [(13, SWEEP2), (15, NEAP2), (34, DIM_SHRED), (43, RISE), (59, TURN)]:
    shred.seq(bar, part, unit=U, vel=0.85)          # answers / solo runs: level with the saw calls
for bar, part in [(16, CLIMB1_LO), (17, CLIMB2_LO), (18, PEAK_LO)]:
    shred.seq(bar, part, unit=U, vel=0.6)           # twin harmony a minor 3rd under the saw
for bar, part in [(54, CLIMB1_LO), (55, CLIMB2_LO), (56, PEAK_LO)]:
    shred.seq(bar, part, unit=U, vel=0.65, transpose=FF)

# --- hero breaks through, and replies once more in the turnaround (x over the cadential 6/4)
hero.seq(48, HERO, unit=U)
hero.seq(58, "G4:3 G4:1 C5^:4", unit=U, vel=0.9)

# ------------------------------------------------------------------ voicings ---
VOICE = {
    "Cm": ["G3", "C4", "Eb4"], "Db": ["Ab3", "Db4", "F4"], "G7b9": ["B3", "D4", "F4"],
    "Gdim/Db": ["G3", "Bb3", "Db4"], "Ab": ["Ab3", "C4", "Eb4"], "Fm": ["F3", "Ab3", "C4"],
    "G": ["G3", "B3", "D4"], "G7": ["G3", "B3", "D4", "F4"], "G/B": ["G3", "B3", "D4"],
    "Cm7/Bb": ["G3", "Bb3", "C4", "Eb4"], "Adim7": ["A3", "C4", "Eb4", "Gb4"],
    "Fm/Ab": ["F3", "Ab3", "C4"], "Fm7": ["F3", "Ab3", "C4", "Eb4"], "Bb": ["F3", "Bb3", "D4"],
    "C": ["G3", "C4", "E4"], "Db/F": ["Ab3", "Db4", "F4"], "Ab/C": ["Ab3", "C4", "Eb4"],
    "Cm/G": ["C4", "Eb4", "G4"],      # G#7 (Ger+6) -> 6/4: C stays, D# = Eb stays, F# -> G
}


def tnotes(notes, n):
    return [name_of(midi(x) + n) for x in notes]


for t, s in FF_SRC.items():          # final-form voicings: the C-minor voicings a half step up
    VOICE[t] = tnotes(VOICE[s], FF)


def pad(track, bar_from, bar_to, vel=0.6, voicing=None):
    for b0, b1, c in segs(bar_from, bar_to):
        notes = (voicing or {}).get(c, VOICE[c])
        for m in notes:
            track.note(b0, m, b1 - b0 - 0.08, vel)


# organ: intro + A sections + hero/final form, softer under the B theme; OUT under the canon (45-48)
pad(organ_t, 0, 20, 0.6)
pad(organ_t, 20, 36, 0.4)
pad(organ_t, 48, 60, 0.5)
# break: the theme at half speed, organ takes the calls (melody) over choir chords
organ_ld.seq(36, "G4:3 G4:1 Db5^:4 Eb5:3 Eb5:1 G5^:4", unit=0.5, vel=0.8)     # bars 37-38
organ_ld.seq(40, "Eb5:3 Eb5:1 Ab5^:4 B4:3 B4:1 F5^:4", unit=0.5, vel=0.8)     # bars 41-42
pad(organ_t, 36, 44, 0.45, {"G7b9": ["G3", "B3", "F4"]})

# choir "ah": B, bridge, break, climax
pad(choir_t, 20, 36, 0.6)
pad(choir_t, 36, 44, 0.7, {"G7b9": ["G3", "B3", "F4"]})
pad(choir_t, 48, 60, 0.65)        # out for the canon (45-48) so the brass imitation is clear

# bell: the wink at half speed in the break ("the Lich laughs"); passing notes kept short
bell_t.seq(38, "Ab5:3 G5:0.9 -:0.1 F5:2 Eb5:2 | D5:2 Eb5:0.9 -:0.1 D5:0.9 -:0.1 B4:2 G4:2", unit=0.5, vel=1.0)
bell_t.seq(42, "Eb5:3 D5:0.9 -:0.1 C5:2 G4:1 B4:0.9 -:0.1", unit=0.5, vel=1.0)
# bell sparkle: octave-up echo of the hero theme
bell_t.seq(48, HERO, unit=U, transpose=12, vel=0.4)

# ------------------------------------------------------------------ brass ---
def stab_x(bar, half, voicing, vel=0.85):
    """Chord stabs in the x rhythm (dotted 8th, 16th, quarter) on half `half` of `bar`."""
    b0 = bar * BAR + half * 2.0
    for off, ln, v in ((0.0, 0.5, vel), (0.75, 0.2, vel * 0.8), (1.0, 0.8, min(1.0, vel * 1.15))):
        for m in voicing:
            brass_t.note(b0 + off, m, ln, v)


# intro: "Ma-gic SMASH" stabs on the tonic, then the Neapolitan
for bar, c in [(0, "Cm"), (1, "Cm"), (2, "Db")]:
    stab_x(bar, 0, VOICE[c])
    stab_x(bar, 1, VOICE[c], 0.75)
# bar 4: the Lich's x in unison with the bass, through the dim7 (B-F tritone, D-Ab tritone)
brass_t.seq(3, "B3:3 B3:1 F4^:4 D4:3 D4:1 Ab4^:4", unit=U, vel=0.9)
# B1: stabs under the x bars of the theme
for bar in (20, 44):
    stab_x(bar, 0, VOICE["Gdim/Db"]); stab_x(bar, 1, VOICE["Cm"])
stab_x(52, 0, VOICE[tsym("Gdim/Db", FF)], 0.95); stab_x(52, 1, VOICE[tsym("Cm", FF)], 0.95)
for bar in (22,):
    stab_x(bar, 0, VOICE["Ab"]); stab_x(bar, 1, ["G3", "B3", "F4"])
# B2: harmony line in 3rds/6ths
brass_t.seq(24, BOSS_HARM, unit=U, vel=1.0)
# bridge: soft swells under the long notes
for bar in (28, 30, 32):
    for m in VOICE[HARMONY[bar]]:
        brass_t.note(bar * BAR, m, 3.0, 0.5)
# climax: free canon - brass imitates the theme one bar behind, pitches bent to the chords
# ...and in bar 48 the brass rallies on the HERO's rising 4th (G G C, Eb Eb G) to set up his entry
brass_t.seq(45, "C4:3 C4:1 F4:4 B3:3 B3:1 D4:4 | "
                "Ab4:3 G4:1 Eb4:2 C4:2 D4:2 Eb4:1 D4:1 B3:2 G3:2 | "
                "G3:3 G3:1 C4^:4 Eb4:3 Eb4:1 G4^:4", unit=U, vel=0.9)
# hero: brass sings the bible HARM line (Picardy E natural at the end)
brass_t.seq(48, HERO_HARM, unit=U, vel=1.0)
# turnaround: the whole band hits "Ma-gic SMASH" on C minor
stab_x(58, 1, ["G3", "C4", "Eb4", "G4"], 1.0)

# ------------------------------------------------------------------- bass ---
BASS_ROOT = {"Cm": "C2", "Db": "Db2", "G7b9": "G1", "Gdim/Db": "Db2", "Ab": "Ab1", "Fm": "F1", "G": "G1",
             "G7": "G1", "G/B": "B1", "Cm7/Bb": "Bb1", "Adim7": "A1", "Fm/Ab": "Ab1", "Fm7": "F1", "Bb": "Bb1",
             "C": "C2", "Db/F": "F1", "Ab/C": "C2",   # N6 and Ab/C keep the bass out of 5ths/8ves with the lead
             "Cm/G": "G1"}                            # cadential 6/4: G pedal for the last two bars
for t, s in FF_SRC.items():
    BASS_ROOT[t] = name_of(midi(BASS_ROOT[s]) + FF)
# per-beat cells: (offset, length, semitones above root, velocity)
CELLS = {
    "drive": [(0, .22, 0, 1.0), (.25, .2, 0, .55), (.5, .22, 12, .85), (.75, .2, 0, .6)],
    "chug": [(0, .22, 0, 1.0), (.25, .2, 0, .6), (.5, .22, 0, .8), (.75, .2, 0, .6)],
    "gallop": [(0, .42, 0, 1.0), (.5, .2, 0, .7), (.75, .2, 12, .8)],
    "oct8": [(0, .45, 0, .95), (.5, .42, 12, .8)],
    "half8": [(0, .9, 0, .9), (1.0, .45, 12, .55), (1.5, .45, 0, .6)],     # 2-beat cell
}


def bass_seg(b0, b1, root, style, approach=None, vel=1.0):
    """Fill [b0, b1) with `style` cells on `root`; `approach` = notes (16ths) replacing the end."""
    r = midi(root)
    cell = CELLS[style]
    clen = 2.0 if style == "half8" else 1.0
    end_cut = b1 - (len(approach) * U if approach else 0)
    t = b0
    while t < b1 - 1e-6:
        for off, ln, semi, v in cell:
            if t + off < end_cut - 1e-6:
                bass.note(t + off, r + semi, min(ln, end_cut - (t + off)), v * vel)
        t += clen
    if approach:
        for k, nm in enumerate(approach):
            bass.note(end_cut + k * U, nm, 0.22, 0.85 * vel)


STYLE = {}
for b in range(0, 4): STYLE[b] = "drive"
for b in range(4, 12): STYLE[b] = "gallop"
for b in range(12, 20): STYLE[b] = "drive"
for b in range(20, 24): STYLE[b] = "oct8"
for b in range(24, 28): STYLE[b] = "drive"
for b in range(28, 34): STYLE[b] = "gallop"
for b in range(34, 36): STYLE[b] = "chug"
for b in range(36, 43): STYLE[b] = "half8"
STYLE[43] = "chug"
for b in range(44, 48): STYLE[b] = "drive"
for b in range(48, 52): STYLE[b] = "gallop"
for b in range(52, 58): STYLE[b] = "drive"
STYLE[58] = "chug"
STYLE[59] = "chug"

# walk-ups into chord changes (last 16ths of a segment), keyed by the segment's start beat
APPROACH = {
    3 * BAR: ["B1", "C2"],                     # G7b9 -> Db (A1 call)
    11 * BAR + 2.0: ["B1", "C2"],              # A1 -> A2
    19 * BAR + 2.0: ["Ab1", "B1", "C2"],       # A2 -> B
    23 * BAR: ["C2", "Eb2", "D2", "C2"],       # B1 bar 4 (Cm) -> Db: run
    27 * BAR: ["Eb2", "D2", "C2", "B1"],       # B2 -> bridge (C2 again)
    35 * BAR: ["Ab1", "A1", "B1", "C2"],       # into the break (Db)
    42 * BAR: ["D2", "C2", "B1", "A1"],        # Cm -> G7b9 build
    43 * BAR: ["Ab1", "A1", "B1", "C2"],       # build -> climax (Db)
    47 * BAR: ["Eb2", "D2", "C2", "B1"],       # canon -> hero (C)
    51 * BAR: ["A1", "B1", "C2", "C#2"],       # C major -> D (G#dim/D: the final form crushes the Picardy)
    59 * BAR: ["Ab1", "A1", "Bb1", "B1"],      # turnaround -> C (loop)
}
DIM_WALK = {8: ["G1", "B1"], 9: ["D2", "F2"], 16: ["G1", "B1"], 17: ["D2", "F2"],
            54: ["G#1", "C2"], 55: ["D#2", "F#2"]}         # final form: the same climb a half step up
# bars written by hand below (not by the cell styles)
CUSTOM = {3} | set(range(36, 42))

for b0, b1, c in song.harmony:
    bar = int(b0 // BAR)
    if bar in CUSTOM:
        continue
    style = STYLE[bar]
    if bar in DIM_WALK:      # bass climbs the diminished chord with the lead's x
        for k, root in enumerate(DIM_WALK[bar]):
            bass_seg(b0 + 2 * k, b0 + 2 * k + 2, root, "drive")
        continue
    vel = 0.7 if 36 <= bar < 43 else 1.0
    bass_seg(b0, b1, BASS_ROOT[c], style, APPROACH.get(b0), vel)
# hero bar 3: F (the 5th) under the lead's Bb so Bb -> C is not doubled in octaves (as in the bible bass)
bass.notes = [n for n in bass.notes if not (50 * BAR + 3.0 <= n.beat < 51 * BAR)]
bass_seg(50 * BAR + 3.0, 51 * BAR, "F2", "gallop")
# bar 4 (intro): the Lich's x in unison with the brass, through the dim7; Ab2 falls a 5th into Db2
bass.seq(3, "B1:3 B1:1 F2^:4 D2:3 D2:1 Ab2^:4", unit=U, vel=0.95)
# break (bars 37-42): x in augmentation - the tritone Db-G in the bass, then the plain 4th/5th shapes
bass.seq(36, "Db2:3 Db2:1 G2:4 | C2:3 C2:1 C3:4 | F1:3 F1:1 C2:4 | G1:3 G1:1 G2:4 | "
             "Ab1:3 Ab1:1 Eb2:4 | G1:3 G1:1 D2:4", unit=0.5, vel=0.7)
# bar 59: G pedal (cadential 6/4) under the hero's reply, then the "SMASH" x with the band
bass.notes = [n for n in bass.notes if not (58 * BAR <= n.beat < 59 * BAR)]
bass.seq(58, "G1:8 G1:3 G1:1 G2^:4", unit=U)

# -------------------------------------------------------------------- arps ---
def arp_bars(bar_from, bar_to, octave=5, pattern="0 1 2 3 2 1", vel=0.6, tones=None, shift=-12):
    for b0, b1, c in segs(bar_from, bar_to):
        notes = [midi(n) + shift for n in ((tones or {}).get(c) or chord_tones(c.split("/")[0], octave)[:4])]
        arp.arp(0, notes, pattern, unit=U, beats=b1 - b0, vel=vel, gate=0.8, at=b0)


arp.arp(0, ["C5", "Eb5", "G5", "B5"], "0 1 2 3 4 3 2 1", unit=U, beats=8, vel=0.75)   # CmMaj7: the villain chord
arp.arp(2, ["Db5", "F5", "Ab5"], "0 1 2 3 2 1 0 1", unit=U, beats=4, vel=0.75)
arp.arp(3, ["B4", "D5", "F5", "Ab5"], "0 1 2 3 4 5 6 7", unit=U, beats=4, vel=0.8)
DIM = {"G7b9": ["B4", "D5", "F5", "Ab5"], "Gdim/Db": ["G4", "Bb4", "Db5"], "Cm": ["C5", "Eb5", "G5"],
       "Ab": ["Ab4", "C5", "Eb5"], "Db": ["Ab4", "Db5", "F5"], "Fm": ["F4", "Ab4", "C5"],
       "G/B": ["G4", "B4", "D5"], "Cm7/Bb": ["G4", "Bb4", "C5", "Eb5"], "Adim7": ["A4", "C5", "Eb5", "Gb5"],
       "Fm/Ab": ["F4", "Ab4", "C5"], "G": ["G4", "B4", "D5"], "G7": ["G4", "B4", "D5", "F5"],
       "Bb": ["F4", "Bb4", "D5"], "C": ["G4", "C5", "E5"], "Db/F": ["F4", "Ab4", "Db5"],
       "Ab/C": ["Ab4", "C5", "Eb5"]}
# (the octave-3 arps under A2 / bridge / climax were inaudible mud under the 400 Hz high-pass: removed)
arp.arp(43, ["B4", "D5", "F5", "Ab5"], "0 1 2 3 4 5 6 7", unit=U, beats=4, vel=0.7)

# ------------------------------------------------------------------- drums ---
G = {
    "intro": {"kick_hard": "X...x...X...x...", "snare_tight": "....X.......X...", "hat": "x.x.x.x.x.x.x.x."},
    "intro2": {"kick_hard": "X.x.x.x.X.x.x.xx", "snare_tight": "....X.......X...", "clap": "....x.......x...",
               "hat": "xoxoxoxoxoxoxoxo"},
    # A: the kick plays cell x (dotted 8th, 16th, quarter) and lands with the snare
    "A": {"kick_hard": "X..xX...X..xX...", "snare_tight": "....X.......X...", "hat": "x.x.x.x.x.x.x.x."},
    # A2: same x kick (the busy double kick masked the call/answer), 16th hats, off-beat open hat, clap
    "A2": {"kick_hard": "X..xX...X..xX.x.", "snare_tight": "....X.......X...", "clap": "....x.......x...",
           "hat": "xoxoxoxoxoxoxoxo", "ohat": "..x...x...x...x."},
    # final form: the dense double kick is saved for the last climax
    "FF": {"kick_hard": "X.xxX.x.X.xxX.x.", "snare_tight": "....X.......X...", "clap": "....x.......x...",
           "hat": "xoxoxoxoxoxoxoxo", "ohat": "..x...x...x...x."},
    "B": {"kick_hard": "X.x.X.x.X.x.X.x.", "snare_tight": "....X.......X...", "clap": "....X.......X...",
          "ride": "x.x.x.x.x.x.x.x.", "ohat": "..x...x...x...x."},
    "skank": {"kick_hard": "X...x...x...x...", "snare_tight": "..x...x...x...x.", "ride": "x...x...x...x...",
              "hat": "x.x.x.x.x.x.x.x."},
    "half": {"kick_hard": "X.........x.....", "snare_tight": "........X.......", "hat": "x.o.x.o.x.o.x.o."},
    "half2": {"kick_hard": "X.....x...x.....", "snare_tight": "........X.......", "hat": "xoxoxoxoxoxoxoxo",
              "ride": "x...x...x...x..."},
    "hero": {"kick_hard": "X.x.X.x.X.x.X.x.", "snare_tight": "....X.......X...", "clap": "....x.......x...",
             "hat": "x.x.x.x.x.x.x.x.", "ohat": "..x...x...x...x."},
}


def groove(bar, name, beats=4):
    """Pattern for the first `beats` beats of `bar` (lets a fill take the rest)."""
    n = int(beats * 4)
    pats = {v: p[:n] + "." * (16 - n) for v, p in G[name].items()}
    drums.pat(bar, {v: p for v, p in pats.items() if v not in CYM})
    cym.pat(bar, {v: p for v, p in pats.items() if v in CYM})


def fill(bar, text, at=0.0):
    drums.fill(bar, text, unit=U, at=at)


FILL_BEAT4 = "tom_hi tom_mid tom_lo tom_lo"
FILL_X = "tom_hi^ - - tom_hi tom_mid^ - - - tom_lo^ - - tom_lo snare_tight^ - - -"   # "Ma-gic SMASH" x2

# intro
groove(0, "intro"); groove(1, "intro", 3); fill(1, "kick_hard kick_hard kick_hard kick_hard", at=3.0)
groove(2, "intro2")
cym.pat(1, {"ohat": "..x...x...x....."}); cym.pat(2, {"ohat": "..x...x...x...x."})   # presence builds in
fill(3, "tom_hi^ - - tom_hi tom_mid^ - - - tom_lo^ - - tom_lo snare_tight_ snare_tight snare_tight snare_tight^")
drums.pat(3, {"kick_hard": "X..xX...X..xX..."}); cym.pat(3, {"hat": "x.x.x.x.x.x....."})
# A1 / A2
for b in range(4, 19):                   # bar 20 (b = 19) is written below with its long fill
    name = "A" if b < 12 else "A2"
    if b % 4 == 3:                       # phrase ends: tom fill on beat 4
        groove(b, name, 3); fill(b, FILL_BEAT4, at=3.0)
    else:
        groove(b, name)
groove(19, "A2", 1); fill(19, "snare_tight snare_tight snare_tight snare_tight tom_hi tom_hi tom_mid tom_mid "
                          "tom_lo tom_lo snare_tight^ snare_tight^", at=1.0)
# B (theme x2)
for b in range(20, 28):
    if b in (23, 27):
        groove(b, "B", 3); fill(b, FILL_BEAT4, at=3.0)
    else:
        groove(b, "B")
# bridge: skank beat (double time), then double-kick 16ths under the dim cascade
for b in range(28, 34):
    groove(b, "skank")
for b in (34, 35):
    drums.pat(b, {"kick_hard": "xoxoxoxoxoxoxoxo", "snare_tight": "....X.......X..."})
    cym.pat(b, {"ride": "x.x.x.x.x.x.x.x.", "ohat": "..x...x...x...x."})
drums.fill(35, "tom_hi tom_hi tom_mid tom_mid", unit=U, at=3.0)
# break: half time, building
for b in range(36, 40):
    groove(b, "half")
for b in range(40, 43):
    groove(b, "half2")
drums.pat(43, {"kick_hard": "X...X...X.X.XXXX", "snare_tight": "ooooxxxxxxxxXXXX"}); cym.pat(43, {"hat": "x.x.x.x........."})
# climax canon: B groove with ride; hero: heroic rock beat with open hats
for b in range(44, 48):
    groove(b, "B") if b != 47 else (groove(b, "B", 3), fill(b, FILL_BEAT4, at=3.0))
fill(47, "snare snare snare snare^", at=3.0)      # the hero's (battle-kit) snare rallies into bar 49
for b in range(48, 52):
    groove(b, "hero") if b != 51 else (groove(b, "hero", 3), fill(b, "snare_tight snare_tight tom_hi tom_lo", at=3.0))
for b in range(52, 58):
    name = "FF"
    groove(b, name) if b not in (53, 57) else (groove(b, name, 3), fill(b, FILL_BEAT4, at=3.0))
# turnaround: the hero's x (beats 1-2) and the band's "SMASH" x (beats 3-4) both land with the snare
drums.pat(58, {"kick_hard": "X..xX...X..xX...", "snare_tight": "....x.......X...", "clap": "............X..."})
cym.pat(58, {"hat": "x.x.x.x........."})
# (the last 8th is a breath before the downbeat slam: it also lets the master compressor recover,
#  which keeps the loop seam click-free)
fill(59, "- snare_tight snare_tight snare_tight tom_hi tom_hi tom_hi tom_mid "
         "tom_mid tom_mid tom_lo tom_lo snare_tight^ - snare_tight^ -")
drums.pat(59, {"kick_hard": "X...X...X..x...."})   # no kick in the last 8th: its sub tail made the master HP click at the seam

# fx: gongs on section downbeats, crashes on phrase starts, risers before climaxes
for b in (0, 20, 36, 44, 52):
    fx.hit(b * BAR, "gong", 0.8)
# timpani (fixed at G2): single hits with the gongs where G is in the chord, a crescendo roll under bar 44
for b in (0, 20, 36, 44):
    fx.hit(b * BAR, "timp", 0.9)
for i in range(16):
    fx.hit(43 * BAR + i * U, "timp", 0.35 + 0.035 * i)
for b in (0, 4, 12, 20, 24, 28, 32, 44, 48, 52, 56):
    fx.hit(b * BAR, "crash", 0.85)
fx.hit(58 * BAR + 3.0, "crash", 0.8)


def riser_into(bar, vel=0.7, early=0.0):
    dur_beats = 2.0 * song.bpm / 60.0       # the riser sample is 2 s long
    fx.hit(bar * BAR - dur_beats - early, "riser", vel)


riser_into(44)
riser_into(20, 0.5)
riser_into(60, 0.6, early=0.5)     # into the loop start; ends under the last snare hits


# -------------------------------------------------------------- dynamics ---
def auto(tr, points):
    """Step automation [(bar, dB), ...]; each value holds until the next point."""
    for i, (bar, d) in enumerate(points):
        b = bar * BAR
        if i:
            tr.automation.append((b - 0.05, points[i - 1][1]))
        tr.automation.append((b, d))


# verse under the hook, A2 building, hook on top, break 4-5 dB down, final form at the top
auto(drums, [(0, -1.5), (4, -2.0), (12, -1.0), (20, 0), (36, -3.5), (40, -2.5), (43, -1.0), (44, 0)])
auto(cym, [(0, 1.0), (4, -1.5), (12, -0.5), (20, 0)])
auto(bass, [(0, -2.5), (4, -2.0), (12, -1.0), (20, 0), (36, -2.5), (43, 0)])
auto(lead, [(0, 0), (4, -1.0), (12, 0), (52, 1.0), (58, 0)])   # final form: the lead rides over the double kick
auto(arp, [(0, 6.0), (4, 0), (43, 4.0), (44, 0)])     # the intro's villain arp is the high colour of the restart
auto(brass_t, [(0, 1.5), (4, 0), (44, 2.0), (48, 0)])  # intro stabs/riff and the canon must read

if __name__ == "__main__":
    song.render()

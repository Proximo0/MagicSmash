"""Magic Smash - BOSS FIGHT vs the Lich Lord.  Angle A: "dark epic".

C minor (harmonic minor + Phrygian Db), 176 bpm, 60 bars = 81.8 s, loop(0).
Castlevania-meets-Final-Fantasy: gritty 16th saw bass, kick_hard kit, organ +
choir "ah", brass, timpani/toms/gong, a detuned-saw lead that sings the
*corrupted* leitmotif, and one bar-48 moment where the hero's own theme
(lead_pulse, battle drum kit, bass_fm) breaks through.

Motif logic (see ../SOUNDTRACK.md):
  hero x   = G G C     (dotted 8th, 16th, quarter, rising 4th onto the snare)
  Lich x   = G G Db    (same rhythm, the 4th bent into a TRITONE) ... then a
             falling half-step "sigh" Db->C (Phrygian b2-1).  Dominants keep
             resolving "wrongly" into the Lich chord Gdim/Db before the tonic.

Form (bars, 1-based)
  1-4    Summoning     Cm hit + gong; theme bars 1-3 as a low brass/bass unison riff
  5-12   A  call       lead: Lich x + sigh, answered up a 4th; dim-7 tritone climb + run
  13-20  A' call       same tune, choir + brass counter-line, climb goes higher (D6)
  21-24  B  theme      the corrupted 4-bar theme, ride kit, brass "x" stabs
  25-28  B  theme'     + brass counter-line in contrary motion
  29-32  B  rise       x sequenced up by step Db-Eb-Fm, brass in 10ths, collapses on G7b9
  33-36  B  theme''    full, bell octave echo, final brass x stabs
  37-42  break         half time; theme in augmentation: pipe organ x, bell "wink" (the Lich laughs)
  43-44  build         dim-7 climb, snare roll, riser
  45-48  climax        theme + brass imitating each x one bar later (free canon)
  49-52  hero!         the hero's original theme (lead_pulse + battle kit) fights back
  53-56  final form    the Lich answers a 4th higher, in F minor
  57-60  coda          Lich call / hero reply / dim climb / G7b9 turnaround with toms + riser
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import *  # noqa: E402,F403

NAME = "music_boss__A"
OUT = os.path.join(HERE, "out", "candidates")

song = Song(NAME, bpm=176, bars=60, reverb_seconds=2.2, reverb_damp=0.55)
song.loop(0)

INTRO, A1, A2, B1, B2, B3, B4, BRK, BUILD, C1, C2, C3, C4 = 0, 4, 12, 20, 24, 28, 32, 36, 42, 44, 48, 52, 56
for b, lbl in ((INTRO, "summoning"), (A1, "A call"), (A2, "A' call+choir"), (B1, "B theme"),
               (B2, "B theme'"), (B3, "B rise"), (B4, "B theme''"), (BRK, "break (laugh)"),
               (BUILD, "build"), (C1, "climax canon"), (C2, "hero fights back"), (C3, "final form Fm"),
               (C4, "coda >G7b9")):
    song.section(b, lbl)


def bb(bar, beat=0.0):
    return song.bar_beat(bar) + beat


# ================================================================ HARMONY ==
H = {}
H[0] = "Cm"
H[1] = "Gdim/Db:0.5 Cm:0.5"
H[2] = "Fm:0.5 G:0.5"
H[3] = "Ab:0.5 G7:0.5"
for b in (A1, A2):
    H[b + 0] = "Gdim/Db:0.5 Cm:0.5"
    H[b + 1] = "Ab:0.5 G:0.5"
    H[b + 2] = "Gdim/Db:0.5 Cm:0.5"
    H[b + 3] = "Db:0.5 G7:0.5"
    H[b + 4] = "Gdim/Db:0.5 Cm:0.5"
    H[b + 5] = "Ab:0.5 G:0.5"
    H[b + 6] = "Bdim7"
    H[b + 7] = "G7b9"
THEME_H = ["Gdim/Db:0.5 Cm:0.5", "Fm:0.5 G:0.5", "Ab:0.5 G7:0.5", "Cm"]
for b in (B1, B2, B4, C1):
    for i in range(4):
        H[b + i] = THEME_H[i]
H[C1 + 1] = "Fm:0.5 G7:0.5"          # brass canon adds the 7th here
for b in (B1 + 3, B2 + 3, B4 + 3):
    H[b] = "Cm:0.75 Cm7:0.25"        # bass walks Bb-C-Db into the next bar
H[B3 + 0], H[B3 + 1], H[B3 + 2], H[B3 + 3] = "Db", "Eb", "Fm", "G7b9"
for i, c in enumerate(["Gdim/Db", "Cm", "Fm7", "G", "Ab", "G7", "Bdim7", "G7b9"]):
    H[BRK + i] = c
H[C2 + 0], H[C2 + 1], H[C2 + 2], H[C2 + 3] = "Cm:0.75 Cm7:0.25", "Fm:0.5 G:0.5", "Ab:0.5 Bb:0.5", "Cm"
H[C3 + 0], H[C3 + 1], H[C3 + 2], H[C3 + 3] = "Cdim/Gb:0.5 Fm:0.5", "Bbm:0.5 C:0.5", "Db:0.5 C7:0.5", "Fm:0.75 Fm7:0.25"
H[C4 + 0], H[C4 + 1], H[C4 + 2], H[C4 + 3] = "Gdim/Db:0.5 Cm:0.5", "Cm", "Bdim7", "G7b9"
assert sorted(H) == list(range(60))
for b in range(60):
    song.chords(b, H[b])


def chords_in(bar0, bar1):
    return [(b0, b1, c) for b0, b1, c in song.harmony if bb(bar0) <= b0 < bb(bar1)]


# close voicings in octave 3-4 (pads never above G4)
VOX = {"Cm": "G3 C4 Eb4", "Gdim/Db": "G3 Bb3 Db4", "Fm": "F3 Ab3 C4", "Fm7": "F3 Ab3 C4", "G": "G3 B3 D4",
       "G7": "F3 B3 D4", "G7b9": "Ab3 B3 D4 F4", "Ab": "Ab3 C4 Eb4", "Db": "Ab3 Db4 F4",
       "Bdim7": "Ab3 B3 D4 F4", "Eb": "G3 Bb3 Eb4", "Bb": "F3 Bb3 D4", "Cdim/Gb": "Gb3 C4 Eb4",
       "Bbm": "F3 Bb3 Db4", "C": "G3 C4 E4", "C7": "G3 Bb3 E4"}

# ============================================================== MATERIAL ==
# (unit = 16th note; every bar string sums to 16)
# --- the corrupted theme (SOUNDTRACK.md "BOSS") ---------------------------
THEME = ["G4:3 G4:1 Db5:4 Eb5:3 Eb5:1 G5:4",                 # Gdim/Db Cm : tritone call, rising 3rd
         "Ab5:3 G5:1 F5:2 Eb5:2 D5:2 Eb5:1 D5:1 B4:2 G4:2",   # Fm G       : b6 peak + harmonic-minor wink
         "Eb5:3 Eb5:1 Ab5:4 B4:3 B4:1 F5:4",                  # Ab G7      : the answer DROPS (Ab -> B)
         "Eb5:3 D5:1 C5:2 G4:1 B4:1 C5:8"]                    # Cm         : cadence
# --- the hero's original (SOUNDTRACK.md MOTIF+ANSWER, transposed -2 to C minor)
HERO = ["G4:3 G4:1 C5:4 Eb5:3 D5:1 G5:4",
        "Ab5:3 G5:1 F5:2 Eb5:2 D5:2 Eb5:1 D5:1 B4:2 G4:2",
        "Eb5:3 Eb5:1 Ab5:4 F5:3 F5:1 Bb5:4",
        "C6:3 Bb5:1 G5:2 D5:1 B4:1 C5:8"]
HERO_HARM = ["Eb4:3 Eb4:1 G4:4 C5:3 C5:1 Eb5:4",
             "F5:3 Eb5:1 C5:2 C5:2 B4:4 G4:2 D4:2",
             "C5:3 C5:1 Eb5:4 D5:3 D5:1 F5:4",
             "G5:3 G5:1 Eb5:2 B4:1 G4:1 Eb4:8"]
HERO_BASS = ("C2 C3 C2 C3 C2 C3 Bb2 G2 | F2 F3 F2 F3 G2 G3 G2 G3 | "
             "Ab1 Ab2 Eb2 Ab2 Bb1 Bb2 F2 D2 | C2 C3 G2 C3 C2 C3 G2 G1")   # unit 0.5
# --- section A: the Lich's call --------------------------------------------
CALL_SIGH = "G4:3 G4:1 Db5:4 C5:8"                 # x bent to a tritone, then sighs down a half step
CALL_SIGH2 = "G4:3 G4:1 Db5:4 C5:4 Eb5:2 D5:2"     # 2nd time: a pickup fills the hold (D -> Eb next bar)
RESP_SIGH = "Eb5:3 Eb5:1 Ab5:4 G5:8"               # answer a 4th up (b6 -> 5 sigh)
CALL_CLIMB = "G4:3 G4:1 Db5:4 Eb5:3 Eb5:1 G5:4"    # this time it keeps climbing (= theme bar 1)
TURN = "Ab5:3 G5:1 F5:2 Ab5:2 G5:2 F5:1 D5:1 B4:4"  # Db -> G7, hangs on the leading tone
DIM1 = "B4:3 B4:1 F5:4 D5:3 D5:1 Ab5:4"           # x through the diminished 7th: B-F, D-Ab
DIM_RUN = "F5:3 F5:1 B5:4 Ab5 G5 F5 Eb5 D5 C5 B4 Ab4"   # F-B, then a harmonic-minor scale run; Ab4 -> G4 next bar
DIM2 = "D5:3 D5:1 Ab5:4 F5:3 F5:1 B5:4"           # the climb starts a step higher...
DIM_PEAK = "Ab5:3 Ab5:1 D6:4 B5:2 Ab5:2 F5:2 D5:2"   # ...and peaks on D6, falling down the dim-7
# --- B3: x climbs by step (bII - bIII - iv) and collapses on V ---------------
RISE = ["Ab4:3 Ab4:1 Db5:4 F5:3 F5:1 Ab5:4",
        "Bb4:3 Bb4:1 Eb5:4 G5:3 G5:1 Bb5:4",
        "C5:3 C5:1 F5:4 Ab5:3 Ab5:1 C6:4",
        "D6:3 D6:1 Ab5:4 F5:2 D5:2 B4:2 Ab4:2"]   # tritone falls instead of a 4th rising
RISE_HARM = ["F3:3 F3:1 Ab3:4 Db4:3 Db4:1 F4:4",   # chord tone below the lead, an octave down (10ths)
             "G3:3 G3:1 Bb3:4 Eb4:3 Eb4:1 G4:4",
             "Ab3:3 Ab3:1 C4:4 F4:3 F4:1 Ab4:4",
             "B4:3 B4:1 F4:4 D4:2 B3:2 Ab3:2 F3:2"]
# brass counter-line in contrary motion to the theme (rises while the theme falls)
CONTRA = ["Bb3:8 C4:8", "Ab3:8 B3:8", "C4:8 D4:8", "Eb4:16"]
# brass "free canon": each bar imitates the lead's previous bar, bent to the new chord
CANON = ["-:16",
         "C4:3 C4:1 F4:4 B3:3 B3:1 F4:4",
         "Eb4:3 Db4:1 C4:2 Bb3:2 B3:2 C4:1 B3:1 G3:2 F3:2",
         "G3:3 G3:1 C4:4 Eb4:3 Eb4:1 G4:4"]           # ...the HERO's G-G-C: the brass rallies the hero


def seq_bars(tr, bar, bars, unit=0.25, vel=0.8, transpose=0):
    for i, txt in enumerate(bars):
        tr.seq(bar + i, txt, unit=unit, vel=vel, transpose=transpose)


# ============================================================ INSTRUMENTS ==
lead = song.track("lead", lead_saw(cutoff=5500), vol=-7, pan=0.05, reverb=0.15, delay=0.1, hp=180,
                  eq=(("peak", 2800, 2.0, 0.8), ("peak", 4800, 2.5, 1.0)))
hero = song.track("hero", lead_pulse(cutoff=8000), vol=-8, pan=0.05, reverb=0.15, delay=0.1, hp=180)
brs = song.track("brass", brass(), vol=-12.5, pan=-0.2, reverb=0.18, hp=150)
riff = song.track("riff", brass(cutoff=1700, fenv=2.0), vol=-9.5, pan=-0.1, reverb=0.18, hp=150)  # intro riff
pipe = song.track("pipe", organ(vib_depth=0.1, vib_delay=0.2), vol=-12, pan=-0.1, reverb=0.45, delay=0.12, hp=180)
org = song.track("organ", organ(), vol=-17, pan=0.15, reverb=0.4, hp=200, duck=0.35)
cho = song.track("choir", choir("ah"), vol=-13, reverb=0.5, hp=200, duck=0.35)
bel = song.track("bell", bell(), vol=-18, pan=-0.3, reverb=0.35, delay=0.2, hp=400)
bass = song.track("bass", bass_saw(sub=0.15), vol=-8, hp=40, duck=0.3, eq=(("lowshelf", 80, -2.0, 0.707),))
bassh = song.track("bass_hero", bass_fm(), vol=-9, duck=0.3)
dr = song.drums("drums", vol=-11, reverb=0.08, eq=(("lowshelf", 90, -3.0, 0.707),))
cym = song.drums("cymbals", vol=-6.5, reverb=0.1)     # hats/ride/crash on their own bus = presence control
perc = song.drums("perc", vol=-12, reverb=0.3)

# ================================================================== LEAD ==
seq_bars(lead, A1, [CALL_SIGH, RESP_SIGH, CALL_CLIMB, TURN, CALL_SIGH2, RESP_SIGH, DIM1, DIM_RUN])
seq_bars(lead, A2, [CALL_SIGH, RESP_SIGH, CALL_CLIMB, TURN, CALL_SIGH2, RESP_SIGH, DIM2, DIM_PEAK])
seq_bars(lead, B1, THEME)
seq_bars(lead, B2, THEME)
seq_bars(lead, B3, RISE)
seq_bars(lead, B4, THEME, vel=0.85)
seq_bars(lead, BUILD, [DIM1, DIM_RUN])
seq_bars(lead, C1, THEME, vel=0.85)
seq_bars(lead, C3, THEME, vel=0.85, transpose=5)          # the Lich's final form: F minor
seq_bars(lead, C4, [CALL_SIGH, "-:16", DIM1, "F5:3 F5:1 B5:4 Ab5:2 F5:2 D5:2 B4:2"], vel=0.85)

# hero breaks through (and answers the Lich once more in the coda)
seq_bars(hero, C2, HERO, vel=0.85)
hero.seq(C4 + 1, "G4:3 G4:1 C5:4 Eb5:3 D5:1 G5:4", unit=0.25, vel=0.85)

# ================================================================= BRASS ==
# intro: theme bars 1-3 as a unison riff (brass two octaves above the bass)
seq_bars(riff, 1, THEME[:3], transpose=-12, vel=0.85)
riff.chord(0, VOX["Cm"].split(), beats=1.5, vel=0.9)
seq_bars(pipe, 1, THEME[:3], vel=0.7)


def stab(bar, at, chord, length=0.45, vel=0.8):
    brs.chord(bar, VOX[chord].split(), beats=length, vel=vel, at=at)


def x_stabs(bar, chord, at=2.0, vel=0.85):
    """the x rhythm as brass chord hits: dotted 8th, 16th, quarter"""
    stab(bar, at, chord, 0.6, vel)
    stab(bar, at + 0.75, chord, 0.2, vel * 0.8)
    stab(bar, at + 1.0, chord, 0.9, vel)


# A': slow chromatic counter-line (Bb-C / C-B / Bb-C / Db-D) then joins the dim climb in parallel
seq_bars(brs, A2, ["Bb3:8 C4:8", "C4:8 B3:8", "Bb3:8 C4:8", "Db4:8 D4:8",
                   "Bb3:8 C4:8", "C4:8 B3:8", "B3:3 B3:1 F4:4 D4:3 D4:1 Ab4:4",
                   "F4:3 F4:1 B4:4 Ab4:2 F4:2 D4:2 B3:2"], vel=0.7)
# B: downbeat hits, x stabs in the cadence gap
for b, c in ((B1, "Gdim/Db"), (B1 + 1, "Fm"), (B1 + 2, "Ab")):
    stab(b, 0.0, c, 0.45, 0.8)
x_stabs(B1 + 3, "Cm")
seq_bars(brs, B2, CONTRA, vel=0.72)
seq_bars(brs, B3, RISE_HARM, vel=0.75)
seq_bars(brs, B4, CONTRA[:3], vel=0.75)
x_stabs(B4 + 3, "Cm", vel=0.95)
# break: silent until the build
seq_bars(brs, BUILD, ["Ab3:3 Ab3:1 D4:4 B3:3 B3:1 F4:4", "D4:3 D4:1 Ab4:4 F4:4 D4:2 B3:2"], vel=0.75)
# climax
stab(C1, 0.0, "Gdim/Db", 0.5, 0.9)
seq_bars(brs, C1, CANON, vel=0.78)
seq_bars(brs, C2, HERO_HARM, vel=0.72)
seq_bars(brs, C3, CONTRA, vel=0.75, transpose=5)
stab(C4, 0.0, "Gdim/Db", 0.5, 0.85)
stab(C4, 2.0, "Cm", 0.5, 0.85)
brs.seq(C4 + 1, HERO_HARM[0], unit=0.25, vel=0.7)
seq_bars(brs, C4 + 2, ["Ab3:3 Ab3:1 D4:4 B3:3 B3:1 F4:4", "D4:3 D4:1 Ab4:4 F4:4 D4:2 B3:2"], vel=0.8)

# ============================================================ BREAK MELODY ==
# theme in augmentation: the pipe organ intones x, the bell laughs the wink
pipe.seq(BRK, THEME[0], unit=0.5, vel=0.75)
bel.seq(BRK + 2, THEME[1], unit=0.5, vel=0.8)
pipe.seq(BRK + 4, THEME[2], unit=0.5, vel=0.75)
# bell: octave-up sparkle on the strongest theme statements
seq_bars(bel, B4, THEME, transpose=12, vel=0.5)
seq_bars(bel, C2, HERO, transpose=12, vel=0.45)

# ================================================================== PADS ==
SAME = {"Cm7": "Cm", "Fm7": "Fm"}


def pad(tr, bar0, bar1, vel=0.6, vox=None):
    segs = []
    for b0, b1, c in chords_in(bar0, bar1):
        if segs and SAME.get(c) == segs[-1][2] and abs(segs[-1][1] - b0) < 1e-6:
            segs[-1][1] = b1
        else:
            segs.append([b0, b1, c])
    for b0, b1, c in segs:
        for m in (vox or VOX)[c].split():
            tr.note(b0, m, b1 - b0 - 0.1, vel)


pad(org, 0, 4, 0.6)
pad(org, A1, B1, 0.55)
pad(org, B4, B4 + 4, 0.5)
pad(org, C1, C2, 0.55)
pad(org, C3, 60, 0.55)
pad(cho, 0, 4, 0.55)
pad(cho, A2, BRK, 0.55)
# break: low, dark male choir; G voiced G-B-G so the bell's Eb-D wink can't rub against D
BRK_VOX = dict(VOX, **{"Gdim/Db": "Db3 G3 Bb3", "Cm": "C3 G3 Eb4", "Fm7": "F3 C4 Eb4", "G": "G3 B3 G4",
                       "Ab": "Ab2 Eb3 C4", "G7": "G3 B3 F4"})
pad(cho, BRK, 60, 0.6, BRK_VOX)

# ================================================================== BASS ==
def chug(bar, roots):
    """16th ostinato: one root per beat, 'R R R+12 R'"""
    for i, r in enumerate(roots):
        m = midi(r)
        for k, d in enumerate((0, 0, 12, 0)):
            bass.note(bb(bar, i + k * 0.25), m + d, 0.25, 0.85 if k == 0 else 0.7)


def gallop(bar, roots, last=None):
    """per half bar: 8th, 16th, 16th, octave 8th, 8th"""
    txt = []
    for r in roots:
        o = name_of(midi(r) + 12)
        txt.append(f"{r}:2 {r}:1 {r}:1 {o}:2 {r}:2")
    if last:
        txt[-1] = last
    bass.seq(bar, " ".join(txt), unit=0.25)


# intro: hit, walk down C-Bb-Ab into the riff, riff in unison with brass
bass.seq(0, "C2:6 -:2 C2 C2 C3 C2 Bb1 Bb1 Bb2 Ab1", unit=0.25)
seq_bars(bass, 1, THEME[:3], transpose=-36)
A_ROOTS = [["Db2", "Db2", "C2", "C2"], ["Ab1", "Ab1", "G1", "G1"], ["Db2", "Db2", "C2", "C2"],
           ["Db2", "Db2", "G1", "G1"], ["Db2", "Db2", "C2", "C2"], ["Ab1", "Ab1", "G1", "G1"],
           ["B1", "B1", "D2", "F2"], ["G1", "G1", "G1", "D2"]]
for b in (A1, A2):
    for i, roots in enumerate(A_ROOTS):
        chug(b + i, roots)


def theme_bass(bar, transpose=0, cadence="C2:2 C2:1 C2:1 Bb1:2 C2:2"):
    t = lambda n: name_of(midi(n) + transpose)
    gallop(bar, [t("Db2"), t("C2")])
    gallop(bar + 1, [t("F1"), t("G1")])
    gallop(bar + 2, [t("Ab1"), t("G1")], last=f"{t('G1')}:2 {t('G1')}:1 {t('G1')}:1 {t('G2')}:2 {t('B1')}:2")
    gallop(bar + 3, [t("C2"), t("C2")], last=cadence)


theme_bass(B1)
theme_bass(B2)
bass.seq(B3, "Db2 Db3 Db2 Db3 Db2 Db3 Db2 D2 | Eb2 Eb3 Eb2 Eb3 Eb2 Eb3 Eb2 E2 | "
             "F2 F3 F2 F3 F2 F3 F2 F#2", unit=0.5)
chug(B3 + 3, ["G1", "G1", "G1", "D2"])
theme_bass(B4)
# break: the x rhythm augmented in the bass (dotted quarter, 8th, half)
bass.seq(BRK, "Db2:3 Db2:1 G2:4 | C2:3 C2:1 G2:4 | F1:3 F1:1 C2:4 | G1:3 G1:1 G2:4 | "
              "Ab1:3 Ab1:1 Eb2:4 | G1:3 G1:1 D2:4", unit=0.5)
bass.seq(BUILD, "B1 B2 B1 B2 D2 D3 D2 D3", unit=0.5)
chug(BUILD + 1, ["G1", "G1", "G1", "D2"])
# climax
for i, roots in enumerate([["Db2", "Db2", "C2", "C2"], ["F1", "F1", "G1", "G1"],
                           ["Ab1", "Ab1", "G1", "G1"], ["C2", "C2", "C2", "C2"]]):
    chug(C1 + i, roots)
bassh.seq(C2, HERO_BASS, unit=0.5)
theme_bass(C3, 5, cadence="F1:2 F1:1 F1:1 Eb2:2 D2:2")
chug(C4, ["Db2", "Db2", "C2", "C2"])
chug(C4 + 1, ["C2", "C2", "C2", "C2"])
chug(C4 + 2, ["B1", "B1", "D2", "F2"])
chug(C4 + 3, ["G1", "G1", "G1", "G1"])

# ================================================================= DRUMS ==
GA = {"kick_hard": "x.x...x.x.x...x.", "snare_tight": "....x.......x...", "hat": "xoxoxoxoxoxoxoxo"}
GA2 = dict(GA, clap="....x.......x...")
GB = {"kick_hard": "x.x...x.x.x...x.", "snare_tight": "....x.......x...", "clap": "....x.......x...",
      "ride": "x.x.x.x.x.x.x.x.", "hat": ".o.o.o.o.o.o.o.o"}
GB3 = {"kick_hard": "x.x.x.x.x.x.x.x.", "snare_tight": "....x.......x...", "clap": "....x.......x...",
       "ride": "x...x...x...x...", "hat": "xoxoxoxoxoxoxoxo"}
GBRK = {"kick_hard": "x.........x.....", "snare_tight": "........x.......", "ride": "x...x...x...x..."}
GHERO = {"kick_hard": "x.....x.x.....x.", "snare": "....x.......x...", "clap": "....x.......x...",
         "hat": "x.x.x.x.x.x.x.x.", "ohat": "..x...x...x...x."}
GC = dict(GB3, ride="x.x.x.x.x.x.x.x.", ohat="..x...x...x...x.")
GBO = dict(GB, ohat="..x...x...x...x.")

F_SN = "snare_tight_ snare_tight snare_tight snare_tight^"
F_TOM = "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo snare_tight^ snare_tight^"
F_TOM1 = "tom_hi tom_mid tom_lo tom_lo"


CYM = ("hat", "ohat", "ride", "crash")


def P(bar, pat):
    """drum pattern, split between the drum bus and the cymbal bus"""
    d = {v: p for v, p in pat.items() if v not in CYM}
    c = {v: p for v, p in pat.items() if v in CYM}
    if d:
        dr.pat(bar, d)
    if c:
        cym.pat(bar, c)


def groove(bar, n, pat, fill=None, fill_at=3.0):
    for k in range(n):
        p = pat
        if fill and k == n - 1:
            cut = int(fill_at * 4)
            p = {v: (s * 2)[:cut] + "." * (16 - cut) for v, s in pat.items()}
        P(bar + k, p)
    if fill:
        dr.fill(bar + n - 1, fill, at=fill_at)


def crash(bar, vel=0.85, at=0.0):
    cym.hit(bb(bar, at), "crash", vel)


# intro: hit, toms pick up; then the riff is punched by kick/snare
dr.hit(bb(0), "kick_hard", 1.0)
crash(0, 0.9)
dr.fill(0, "tom_lo tom_lo tom_mid tom_mid tom_hi tom_hi tom_hi tom_hi", at=2.0)
for b in (1, 2):
    P(b, {"kick_hard": "x..xx...x.x...x.", "snare_tight": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."})
P(3, {"kick_hard": "x..xx...x..xx...", "snare_tight": "....x.......x...", "hat": "x.x.x.x.x.x....."})
dr.fill(3, "snare_tight snare_tight tom_hi tom_lo", at=3.0)
# A / A'
groove(A1, 4, GA, F_SN)
groove(A1 + 4, 4, GA, F_TOM, 2.0)
groove(A2, 4, GA2, F_SN)
groove(A2 + 4, 4, GA2, F_TOM, 2.0)
for b in (A1, A2):
    crash(b)
# B
groove(B1, 3, GB)
P(B1 + 3, {"kick_hard": "x.x...x.x..x....", "snare_tight": "....x.......x...", "ride": "x.x.x..........."})
cym.hit(bb(B1 + 3, 3.0), "crash", 0.7)
groove(B2, 4, GBO, F_TOM1)
groove(B3, 4, GB3, F_TOM, 2.0)
groove(B4, 3, GBO)
P(B4 + 3, {"kick_hard": "x.x...x.x..x....", "snare_tight": "....x.......x...", "ride": "x.x.x..........."})
cym.hit(bb(B4 + 3, 3.0), "crash", 0.9)
for b in (B1, B2, B3, B4):
    crash(b)
# break: half time, then the build
groove(BRK, 4, GBRK)
groove(BRK + 4, 2, dict(GBRK, hat="..x...x...x...x."), F_TOM1)
for i in range(8):
    dr.hit(bb(BUILD, i * 0.5), "snare_tight", 0.45 + 0.05 * i)
dr.pat(BUILD, {"kick_hard": "x...x...x...x..."})
dr.pat(BUILD + 1, {"kick_hard": "x...x...x...x...", "snare_tight": "xxxxxxxx........"})
dr.fill(BUILD + 1, F_TOM, at=2.0)
# climax
groove(C1, 4, GC, F_SN)
dr.fill(C1 + 3, "snare snare snare snare^", at=3.0)       # the hero's snare rallies
groove(C2, 4, GHERO, "snare snare tom_hi tom_lo")
groove(C3, 4, GC, F_TOM1)
groove(C4, 3, GA2)
P(C4 + 3, {"kick_hard": "x.x.x.x.........", "snare_tight": "....x...........", "hat": "xoxoxoxo........"})
dr.fill(C4 + 3, "tom_hi tom_hi tom_mid tom_mid tom_lo tom_lo kick_hard tom_lo", at=2.0)
for b in (C1, C2, C3, C4):
    crash(b, 0.9)

# perc: gong, timpani (G2 = "timp", D2 = "timp_lo"), risers
for b, v in ((0, 0.8), (B1, 0.6), (BRK, 0.9), (C1, 0.8), (C3, 0.7)):
    perc.hit(bb(b), "gong", v)
for b in (0, B1, B4, C1):
    perc.hit(bb(b), "timp", 0.9)
for k, at in enumerate((0.0, 0.75)):                # timp doubles "Ma-gic" of the intro riff
    perc.hit(bb(1, at), "timp", 0.7 + 0.1 * k)
for b, v in ((BRK, "timp"), (BRK + 1, "timp"), (BRK + 3, "timp"), (BRK + 5, "timp_lo")):
    perc.hit(bb(b), v, 0.6)
for i in range(16):                                 # timpani roll under the build
    perc.hit(bb(BUILD + 1, i * 0.25), "timp", 0.35 + 0.035 * i)
RISER_BEATS = 2.0 * song.bpm / 60.0
perc.hit(bb(C1) - RISER_BEATS, "riser", 0.6)
perc.hit(bb(60) - RISER_BEATS - 0.5, "riser", 0.5)

# ============================================================== DYNAMICS ==
def auto(tr, points):
    """step automation [(bar, dB), ...]; each value holds until the next point"""
    for i, (bar, d) in enumerate(points):
        b = bb(bar)
        if i:
            tr.automation.append((b - 0.05, points[i - 1][1]))
        tr.automation.append((b, d))


auto(dr, [(0, 0), (A1, -3.0), (A2, -1.5), (B1, 0), (BRK, -3), (BUILD, -1), (C1, 0.5), (C2, 0), (C3, 0.5), (C4, 0)])
auto(bass, [(0, 0), (A1, -2.0), (A2, -1.0), (B1, 0), (BRK, -5.0), (BUILD, 0)])
auto(cym, [(0, 0), (A1, -2.0), (A2, -1.0), (B1, 0), (BRK, -2), (BUILD, 0)])
auto(lead, [(0, 0), (A1, -1.0), (B1, 0)])
auto(pipe, [(0, 0), (BRK, 3), (BUILD, 0)])
auto(bel, [(0, 0), (BRK, 7), (BUILD, 0)])          # the bell carries the "laugh" in the break

if __name__ == "__main__":
    song.render(out_dir=OUT)

# Magic Smash soundtrack bible

Six tracks, one game. They share one leitmotif (the "Magic Smash theme"), one hero voice (`lead_pulse`), and one set of mix rules.
The motif test lives in `songs/_motif_test.py`. It renders fast, title, boss and game-over versions to `out/candidates/`.
All four have 0 semitone clashes. At battle speed, 0 of the lead's 30 notes on the beat are non-chord tones.

## 1. The theme: "Ma-gic SMASH!"

Reference key D minor, `unit=0.25` (16ths). Copy these strings and use `seq(..., transpose=n)`.

```python
# 2-bar motif. Chords: | Dm | Gm  A |   (question, ends open on the dominant)
MOTIF  = "A4:3 A4:1 D5:4 F5:3 E5:1 A5:4 | Bb5:3 A5:1 G5:2 F5:2 E5:2 F5:1 E5:1 C#5:2 A4:2"
# 2-bar answer, giving a 4-bar theme. Chords: | Bb  C | Dm |   (bVI-bVII-i climb to the D6 climax)
ANSWER = "F5:3 F5:1 Bb5:4 G5:3 G5:1 C6:4 | D6:3 C6:1 A5:2 E5:1 C#5:1 D5:8"
# harmony line in 3rds/6ths that holds still under the wink (lead_fm or brass)
HARM   = "F4:3 F4:1 A4:4 D5:3 D5:1 F5:4 | G5:3 F5:1 D5:2 D5:2 C#5:4 A4:2 E4:2 | D5:3 D5:1 F5:4 E5:3 E5:1 G5:4 | A5:3 A5:1 F5:2 C#5:1 A4:1 F4:8"
# tested bass (unit=0.5). Bar 3 puts 5ths on beats 2 and 4 to avoid parallel octaves with the lead's Bb->C.
BASS   = "D2 D3 D2 D3 D2 D3 C3 A2 | G2 G3 G2 G3 A2 A3 A2 A3 | Bb1 Bb2 F2 Bb2 C2 C3 G2 E2 | D2 D3 A2 D3 D2 D3 A2 A1"
# chords for all 4 bars: song.chords(bar, "Dm Gm:0.5 A:0.5 Bb:0.5 C:0.5 Dm")
```

**How it is built**
- **Cell x, "Ma-gic SMASH":** a dotted 8th, a 16th, then a quarter. The note repeats, then the line leaps up a perfect 4th onto beat 2 or beat 4, so the accent lands with the snare. The rising 4th is the signature interval. This is the heroic part.
- **Cell x′:** the same rhythm with a cheeky half-step dip (F E → A).
- **The wink:** the line peaks on Bb (the flat 6th), then wriggles down E F E C# and drops to a low A on the "and" of beat 4. That low A also leads into the repeat. The dip, the wink and the off-beat drop make it mischievous.
- **Ways to develop it:**
  - Cell x on its own works as a stab, a bass riff or a drum-fill rhythm.
  - The answer moves x up by step.
  - Inversion: x falls a 5th.
  - Augmentation: `unit=0.5` for grand statements.
  - The wink on its own works as a phrase-end fill.
- **Range:** A4–D6, so the pulse lead stays clearly on top.

## 2. Track plan (all loops use `loop(0)`, see section 5)

| Track | Key | BPM | Length | Form (bars) | Last bar / turnaround |
|---|---|---|---|---|---|
| `music_title` | D minor | 108 | 36–40 bars, 80–89 s | Mystery 12, heroic 16, coda 8–12 | A7sus4 → A7, timpani roll |
| `music_battle` | E minor (`transpose=+2`) | 160 | 64 bars, 96 s | Intro riff 4, verse A 16, hook B 16, breakdown 8, build 4, climax B′ 16 | B7 with a tom fill |
| `music_library` (Act II) | F minor (`transpose=+3`) | 168 | 64 bars, 91.4 s | Toccata 4, verse 8, fugato 4, calls 4, hook 8, pages 8, build 4, climax 8, inferno 8, tag 8 | C7 toccata run and toms |
| `music_sanctum` (Act III) | B minor (`transpose=-3`), slides to C minor | 150 | 60 bars, 96 s | Vigil 4, procession 8, hymn 8, hook 8, eclipse 4, ascending 8, ascension 8, black comet 4, C minor pull 4, turnaround 4 | Gdim/Db Cm, G7 (Ger+6), F#7, tolls and toms |
| `music_boss` | C minor (harmonic minor plus a Phrygian Db) | 176 | 56–60 bars, 76–82 s | Intro 4, A 16, B 16, half-time break 8, climax 12–16 | G7b9, toms and a riser |
| `music_gameover` | D minor | 84 | 2 bars plus `no_loop(tail=2.0)`, about 7.7 s | One phrase | Final low D |

Why these keys:
- The title and game over share the home key, D minor. A run starts and ends there.
- The battle lifts a whole step to E minor, which is brighter and gives a punchy E1/E2 bass.
- The boss falls to C minor, below home, with the Db/G tritone.
- The acts climb toward it: E minor (Act I) → F minor (Act II, a half step up) → B minor (Act III, a tritone away, Morvane's interval) → C minor (boss, a half step up again). The Sanctum's last bars already slide into C minor.

## 3. Palette and production

**Signature voices.** Every track uses at least the hero lead plus one sparkle voice.

| Role | Voice |
|---|---|
| Hero lead | `lead_pulse(cutoff=8000)`. It plays every first statement of the theme. The boss lead is `lead_saw(cutoff=5500)`. Game over uses `lead_pulse(duty=0.5, vib_depth=0.25)` played soft. |
| Harmony / counter-melody | `lead_fm` in battle. `brass` for the title tutti and boss stabs. |
| Magic sparkle | `bell` echoes the lead an octave up, `harp` plays ripples, `arp_pulse` plays chip 16ths. |
| Pads | `strings` everywhere. `choir("oo")` for the title mystery, `choir("ah")` plus `organ` for the Lich Lord. |
| Bass | `bass_fm` in battle, `bass_nes` for title and game over. Boss uses `bass_saw(sub=0.25)` with `hp=40`, because the preset sub swamps the mix. |

**Drum kits**
- **Battle:**
  - Core: kick, snare, and 8th-note hats.
  - Hook: add ohat on the off-beats and a clap layer on beats 2 and 4.
  - Accents: crash on each 8-bar downbeat, tom fills at phrase ends.
  - Breakdown only: the chip kit (`kick_chip`, `snare_chip`, `hat_chip`) as an arcade throwback.
- **Title:**
  - `timp_lo`, `timp` and `timp_hi` are fixed at D2, G2 and A2, so pick the one that is in the current chord.
  - Snare march rolls.
  - `reverse_cymbal` plus a gong into the heroic section.
- **Boss:**
  - Core: `kick_hard`, `snare_tight` plus clap, and 16th hats with ghost notes.
  - Section B: ride.
  - Accents: gong on section downbeats, a riser before the climax.
- **Game over:** `timp_lo` on the final D only.

**Mix rules**

| Setting | Values |
|---|---|
| Song `reverb_seconds` | title 2.8, battle 1.6, boss 2.2, game over 2.6 |
| Reverb sends | lead 0.15 (0.28 on the title), counter 0.15, pads 0.4–0.5, bell/harp 0.35, drums 0.06–0.1 (0.2 on the title), bass 0 |
| Delay | lead 0.10–0.12, bell/arp 0.15–0.25, at the default 0.75 beat (dotted 8th) |
| Pan | Kick, snare, bass and lead in the centre (lead at most +0.1). Counter and brass at −0.15 to −0.25. Arp and harp at +0.3 to +0.4, opposite the counter. Bell at −0.3. Pads stay wide via the preset spread. |
| Filters | hp 180 on leads, 200 on pads, choir and organ, 400 on arps |
| Sidechain duck | pads 0.35, bass 0.3, arps 0.2 |
| Register | Lead A4–E6. Counter a 3rd or 6th below. Pads in octaves 3–4 (no higher than G4). Bass E1–D3. |

**Level targets** (the report's "share" column). Starting `vol` values were calibrated in the test.

| Part | Target share | Starting `vol` |
|---|---|---|
| Drums | 40–50 % | −6, or −10/−11 for the `kick_hard` kit |
| Lead | 20–30 % | `lead_pulse` −8, `lead_saw` −7 |
| Bass | 18–28 % | `bass_fm` −7, `bass_saw` −8, `bass_nes` −11 on held notes |
| Counter / brass | 2–8 % | `lead_fm` −14, `brass` −13 |
| Pad | 1–4 % | `strings` −11 (it is a quiet preset: at −18 it measured 0.4 %) |
| Sparkle | ≤ 2 % | `arp_pulse` −12 |

- The lead must always have the largest share after drums and bass.
- The game's spell and hit sounds sit at 1–5 kHz, so no sparkle part should get louder than its target.
- Get presence (5 %+) from the off-beat ohat or shaker and the bright lead, not from loud arps.
- Dynamics: the verse sits 2–3 dB under the hook and the breakdown 4–6 dB under it. Nothing drops below about −20 dB per 2 bars.

## 4. How each track uses the motif

**Title (D minor)**
- **Mystery:** never the full theme.
  - The bell plays only cell x, slowed down (A A D at `unit=0.5`), and its delay answers it.
  - The flute sighs the wink slowly.
  - Harp ripples over `Dmadd9 Bbmaj7 Gm6 A7sus4`, with a choir "oo" and `timp_lo` rolls.
- **Heroic:**
  - The full 4-bar theme at `unit=0.5` (8 bars), on `lead_pulse` with `HARM` on brass, timpani on a chord tone (D for Dm and Bb, G for Gm and C, A for A) and a snare march.
  - Then once at the written rhythm as a full tutti, with the bell an octave up.
- **Coda:** brass stabs of x over Bb–C–Dm, then thin back out to the mystery colour.
- **Watch the pads when the theme is slowed down:** voice Dm as D-A-D under the x′ dip, and A as A-C#-A under the wink. The test confirmed this gives 0 clashes. The two remaining lead non-chord tones are intended: a passing F, and the flat-6 appoggiatura of the wink.

**Battle (E minor, `transpose=+2`)**
- **Intro riff:** the bass states x three octaves down (B1:3 B1:1 E2:4 G2:3 F#2:1 B2:4).
- **Verse A:** a new 8-bar tune built from x's rhythm and the rising 4th, over `Em D C B7`. Save the hook for later.
- **Hook B:** `MOTIF+ANSWER` twice. The second time adds `HARM` on `lead_fm` and the clap layer.
- **Breakdown:**
  - Half time, chip kit, relative-major colour (`C G D Em`).
  - `arp_pulse` and bell trade the wink back and forth, with x inverted.
- **Build:** snare 8ths, then 16ths, plus a riser and brass stabs of x.
- **Climax B′:** the theme with the bell an octave up (or lifted to F# minor), and every part in.

**Boss (C minor).** Same rhythm, distorted pitches:
- Cell x leaps a tritone over the "Lich chord" `Gdim/Db`.
- The wink takes on harmonic-minor colour (B natural).
- The answer drops away instead of climbing.

```python
BOSS = "G4:3 G4:1 Db5:4 Eb5:3 Eb5:1 G5:4 | Ab5:3 G5:1 F5:2 Eb5:2 D5:2 Eb5:1 D5:1 B4:2 G4:2 | Eb5:3 Eb5:1 Ab5:4 B4:3 B4:1 F5:4 | Eb5:3 D5:1 C5:2 G4:1 B4:1 C5:8"
BOSS_CHORDS = "Gdim/Db:0.5 Cm:0.5 Fm:0.5 G:0.5 Ab:0.5 G7:0.5 Cm"
```

- **Section A:** the tritone x repeats as a call over a 16th-note `bass_saw` ostinato with organ.
- **Section B:** the full distorted theme, with choir "ah" and brass x stabs.
- **Break:** half time. The bell plays the wink slowly ("the Lich laughs").
- **Climax:** lead and brass play in canon, one bar apart. Once, the hero's original x (G G C on `lead_pulse`) breaks through, as the players fight back.

**Game over (D minor, 84 bpm)**
- Bar 1: x and x′ turned upside down, so they fall a 5th.
- Bar 2: the motif's own bar 2, an octave down, ending on a low D.
- After that, a 4-note `arp_pulse` "fizzle" in 32nds (D6 A5 F5 D5): the spell sputters out.

```python
GAMEOVER = "A5:3 A5:1 D5:4 F5:3 E5:1 Bb4:4 | Bb4:3 A4:1 G4:2 F4:2 E4:1 F4:1 E4:1 C#4:1 D4:12"   # chords "Dm:0.5 Bb:0.5 Gm:0.5 A:0.25 Dm:0.25"
```

Instruments: soft `lead_pulse` with a flute an octave up, a falling harp line, strings, and `timp_lo` on the last note.

**Act tracks.** The run is three 5-minute acts: Act I THE OSSUARY keeps `music_battle`, Act II THE BURNING LIBRARY plays `music_library`, Act III THE STARLESS SANCTUM plays `music_sanctum`. Both new loops share the hero pulse, the mix rules and the level targets, and both measured 0 semitone clashes; the only flagged non-chord tones are the wink's flat-6 appoggiatura and the lament's suspensions.

**Library (F minor, 168 bpm, `songs/music_library.py`).** A burning baroque grimoire.
- Signature voice: a two-choir harpsichord (`HARPSI`: detuned saw pair plus a 4' octave, plucked envelope, quill click from the filter envelope). It spins bariolage (`0 3 2 3 1 3 2 3`, a ringing top pedal) in the toccata and the inferno, Alberti 16ths in the verse.
- The organ (`organ()` as a melody voice) doubles and answers: it states x like a chapel stab, answers the harpsichord's fugue subject at the dominant (C minor), and sings the motif in augmentation in the half-time "pages" section.
- Verse: a circle-of-fifths sequence (Fm Bbm Eb Ab Db Gm7b5 C7), x's rising 4th at the head of every bar, the wink over Gm7b5-C7. Calls: hero x up the scale, the harpsichord answers with winks (5 6 5 3 1).
- The theme plays four times (hook x2, climax x2 with the organ an octave below and `HARM` on `lead_fm`). The inferno puts long burning hero lines over a double-time kit and full-tilt bariolage; x climbs to the F6 peak.
- Ember crackle: seeded, sparse `hat_chip` ticks on their own quiet drum track in the intro and the pages section.

**Sanctum (B minor, 150 bpm, `songs/music_sanctum.py`).** The grandest loop, building dread toward the Archlich.
- Voices: church organ (melody doubling and low pads), formant choir pads ("oo" in the vigil and the eclipse, "ah" elsewhere), a staccato choir (`CHANT`) that chants the x rhythm on chords, an inharmonic FM toll bell (`TOLL`, `fm_ratio=2.76`), timpani on chord tones, gong, harp "stained glass" ripples, and O Fortuna style pumping `strings` 8ths (`STAC`) that keep battle energy under the slow theme.
- The first statement is the theme in augmentation (`unit=0.5`, 8 bars) on the hero with the organ an octave below; chords `Bm Bm Em7 F# G A Bm:0.75 F#:0.25 Bm`. In the ascension the augmented theme moves to choir + organ + brass and the hero soars a descant of x cells above it.
- Hymn: a D major chorale from x, harp ripples, brass in 3rds. Eclipse: lament bass B A# A G# G F#, the bell tolls x inverted.
- Ascending: the hero's x (rising 4th) and Morvane's x (tritone, brass + organ + chant: F# F# C over F#dim/C, B B F over Bdim/F, C C F# over F#dim/C) trade bars, climbing to the Neapolitan C.
- Black comet: the theme with the Neapolitan C in place of iv. The pull: the band slips a half step into C minor, the boss key. Turnaround: brass + organ state the boss call (G G Db over Gdim/Db), G7 works as the German 6th of B minor, the hero's x slides a half step down onto F#7 and the tolls hand back to the vigil.

## 5. Engine and integration gotchas

**Engine**
- `seq` chord tokens such as `[C4 E4 G4]:4` do not parse, because tokens are split on spaces. Use `track.chord()` or `note()`.
- There are no tempo changes (`tempo_map` is unused), so each song has one bpm. Show "mysterious then heroic" through density, not tempo.
- The analysis flags any passing 8th that sits against a held pad note. At the written speed the theme is clean. When it is slowed down, voice the pads as described for the title.

**Godot** (`scripts/sfx.gd`)
- `scripts/sfx.gd` sets `loop_begin = 0` and `loop_end = data.size()/2`. That was only right for the old mono files. The engine writes 16-bit stereo, so `loop_end` must be `data.size()/4`. Better: `int(st.get_length() * st.mix_rate)`.
- `song.loop(n>0)` only works if sfx.gd also reads `loop_begin` from `out/<name>.loop.json`. Until then, loop from bar 0.
- Stereo audio at 44.1 kHz is about 10.6 MB per minute. Consider IMA-ADPCM import compression for web and Android builds.

# The field in the client (job C1)

What `realm/client` shows of rules sections 1 to 8, how it is built, every number chosen, and what waits for other
jobs. Checks: `realm/check_client.sh` (one line), `cargo test` in `realm/godot` (11 tests), `tests/field_test.gd`
(112 checks, no server).

## Build

```
server (UDP) -> worker thread (realm/godot/src/worker.rs)          main thread (realm_client.gd)
                 socket + LockstepClient: receive, apply every     RealmLink.poll(): take the newest frame
                 tick (the core's whole step), predict the hero,    fill the two MultiMeshes, effects, HUD
                 build a Frame (frame.rs) after each batch  ---->   send_input() 20 times a second
                 frame slot (newest wins), pose, counters  <----    set_view(rect), commands on a channel
```

- **Off the main thread.** `connect_to_host` starts the worker, which owns the socket and the whole follower field.
  A game frame never waits for a tick: `poll()` takes the newest finished frame and returns how many ticks it
  applied (0: keep drawing the last one). The worker sleeps 1 ms when idle, so a tick is applied within a millisecond
  of its datagram. Measured on the build machine (software rendering, 4 shared cores): the worker spends 4 to 12 ms a
  tick on the 300x8,000 to 1,500x30,000 fields; the main thread's `poll` takes 0.01 ms, its reads 0.2 to 0.8 ms and
  its whole script 0.3 to 0.6 ms a frame.
- **Prediction and smoothing for the own hero.** The worker calls `LockstepClient::input`, which predicts the hero
  at once, and publishes the shown and the predicted position with a version number. The main thread glides from the
  old target to the new one over one input tick (50 ms); a correction over 48 px (`SNAP_PX`, a fall or a respawn)
  snaps instead of gliding. The camera rounds to whole screen pixels. The horde glides between the 20 ticks a second
  in the shader (`blend`), as before.
- **The view.** The main thread tells the worker the rectangle to build draw buffers for (the screen at the current
  zoom plus 96 px, `READ_MARGIN_PX`), every frame, in four atomics. A zoom change reaches the next tick's frame.
- **Events.** `LockstepClient::apply` runs every waiting tick inside one call, so the frame carries the events of
  the last tick of a batch. The worker polls every millisecond, so a batch is normally one tick; after a stall a few
  bursts of specks and words are lost, never a state (zones, drops, statuses are drawn from state, not events).

## What is on screen

- **10,000 monsters.** One MultiMesh per family (monsters, other players), filled once a tick, 16 floats a figure,
  no GDScript per figure. Elites are 1.25x and gold, champions 1.6x and purple; hurt is red, stunned blue, slowed
  cyan, cursed violet. Measured drawn at once: 5,300 (1,000 bots, 20,000 monsters, zoom 8), 8,500 (the same, zoom
  16), 13,500 to 14,800 (1,200 to 1,500 bots, 25,000 to 30,000 monsters, rally 0.5, zoom 16, the `frames` job's setup).
- **The 42 kinds, by name.** `FieldArt` loads `enemy_<kind>.png` (the core's name with underscores:
  `enemy_plague_rat.png`), `hero_<race>_<class>.png` (class: novice knight mage archer priest paladin) and
  `<name>_walk.png` (four frames side by side, drawn at 0.5, 2 texture px per world px) from `realm/client/art/`,
  strips first, then stills, then stand-ins. In this commit: the Tower's 8 monster stills; all 24 heroes are the char3d sprite sets (`tools/char3d/import_heroes.py`: 8 walk frames at 12 fps, `_atk` 8, `_hit` 4, `_die` 8, a still; scale 0.4667 in the sidecar, so a human is 28 world px tall as before; the frame is centred on the body and its bottom edge is the feet, as `RealmLayer._draw_hero` draws it). Ten monsters (scarecrow, bloated pilgrim, penitent, gravedigger, hanged man, wood witch, bark wight, lumberer, drowned, goat cultist) are the same kind of sets (`tools/char3d/import_sprites.py monsters`, scale 0.4667, frames 94 to 150 px wide; the atlas is one texture of shelves (`RealmBatch.layout`, shelves up to 4,096 px wide, entry order), so 42 strips of 8 frames of 150 x 93 take 3,606 x 1,330 px against the 16,384 limit; when the atlas would be taller than 16,384 the shelves are widened to 8,192 or 16,384 (27 Nov: with the bosses and the action strips the monsters' atlas had grown to 5,506 x 16,789, which no renderer takes, and every monster was drawn as a black box; it is 8,184 x 9,559 now); a moving monster steps its walk frames at the sidecar fps, out of step by its slot (`draw.rs`: bob seed `1 + id % 31` when it moved since the last call), a standing one shows frame 0, and monster stills never bob; monster atk, hit and die strips are packed after the main atlas entries (`RealmBatch` `strips`) and drawn: `draw.rs` encodes state and age in the instance floats (z = kind + 64 * state, w = bob + 32 * age ticks; hit for 3 ticks after the core's `hurt`, attack while within 24 px of a living hero, or for a spitter or lobber standing still in the last 9 ticks of its throw timer so the strip ends as it lets go, die as a ghost kept 20 ticks for a monster drawn last call and dead now; the core keeps no attack or death clock, so the draw buffer does; a sidecar's `hover` draws a floating kind that many px above its spot, swaying, and sinking as it dies). A batch with any hovering kind also draws a blob shadow (`figures_shadow.gdshader`: a soft black ellipse about 20 x 9 px, alpha 0.6 at the centre) at the figure's un-lifted feet, from a second MultiMeshInstance2D that shares each MultiMesh and sits one z layer lower, so it costs no GDScript per figure; it glides with `blend` and shrinks away as a ghost sinks, and a kind with no hover gets a zero-size quad there, and the shader plays the strip once and holds its last frame; a kind without a strip keeps the walk look, and without a die strip leaves no corpse). The sidecar `<name>_walk.json` may also say `atk_frames`, `hit_frames`, `die_frames` (defaults 3, 1, 3, so monsters are unchanged); 24 monster kinds are stand-ins. A monster stand-in is flat, drawn in code: its
  field's colour, its size from its health (14 to 34 px, `sqrt(health) * 1.2 + 14`), and a mark per behaviour
  (bursters orange belly, spitters and lobbers an open mouth, runners lean, brutes broad, shielded ones a grey plate,
  casters a pale crown). A hero with no picture borrows her race's knight. Dropping a
  file with the right name into `art/` is all a new picture needs. The shader takes a per-entry frame count and scale
  (`figures.gdshader`): a moving figure with a strip steps through four frames at 8 a second, a still one bobs.
- **Skills and effects for every class** (`FieldFx`, from effect rows the worker builds, `frame.rs`): the weapon of
  each class (CLEAVE and DIRK arcs, FIREBALL and LONGBOW lines with a burst circle, HOLY LIGHT ring, SMITE's drop
  circle), every skill and ultimate by its act (rings for NOVA, HAMMERFALL, SANCTUARY and the group effects, fans of
  arrows for VOLLEY, dash streaks for CHARGE and TUMBLE, METEOR and CATACLYSM as drop circles that fill as they land,
  zones for TUMBLE, CONSECRATE, RAMPART, HAIL and PYRE), 16 status halos for the hero effects, monster bolts and lobbed
  circles (thin outlines at alpha 0.65, fills 0.05 to 0.12, set by the constants at the top of `field_fx.gd`), bursts when something dies, "LEVEL n", "DOWN", "RAISED", "FALLEN", "BANKED n" and the potion's name as
  floating words. One-tick swings and bolts are kept 0.22 s (`LIFE_S`) and fade. Aim is the nearest monster in the
  weapon's reach by the monster grid (`MAX_AIMED` 300 heroes a view get aimed effects; beyond that they use their
  facing). Effect rows are capped at 6,000 a frame, transient effects at 900 alive.
- **HUD** (`FieldHud`, drawn in the 480 x 270 canvas, 3 screen px a canvas px at 1440 x 810; faces under "Type"):
  bottom left the vitals (the job, or the class, and "LV n"; health and XP bars with their numbers), the three skills
  (the name, "RANK n" or "SEALED" and "LEVEL n", a cooldown sweep and seconds, the key) and the three potions with
  their charges; top right the haul ("COIN n", then "SAFE AT STONE n" or "NOT YET BANKED"); the draw on offer as
  cards (key and copies owned; "A DRAW AWAITS (n)" when one is queued), the banking and blood-mark rite bars, a
  notice line (wrapped to two lines) for the shell's warnings. The numbers panel (frame, ticks, counts) is a
  developer's view and is off in normal play: F3 (or `--debug=1`) shows it together with the ground's 64 px grid
  (`RealmLayer.show_grid`); the field's edge line is always drawn.
- **Monster health bars** (27 Nov). Over a hurt monster, and over every elite, champion and boss, near the hero: a
  14 x 4 px bar (a 1 px dark rim round a 2 px red fill, the empty part dark red) just over the picture's head,
  gliding with it. No node and no GDScript per bar. `draw.rs` writes the bar into the tint's alpha (`with_bar`:
  exactly 1 for none, else 0.5 + b / 512 with b = ceil(health * 255 / max) in 1..255; an instance colour over 1 is
  not safe, so the bar is kept under it; `figures.gdshader` sets the figure's alpha back to 1) and copies the 16
  floats of each barred monster within 480 px (`BAR_RADIUS_PX`) of the view's centre, which is the hero, into a
  second buffer (`Frame.bar_buf`, `RealmLink.bar_buffer()`). `RealmBatch.fill_bars` puts it in the batch's own bar
  MultiMesh (double buffered like the figures), drawn after the figures by `figures_bar.gdshader`, which undoes the
  rank scale and the mirror so every bar is the same size and fills left to right, and hides it on a ghost. A boss
  keeps the big HUD bar as well. `--bars=0` hides the bars, `--bars=all` puts one on every drawn monster (the worst
  case, for benches). Why only near the hero: "Health bars" under "Proof and numbers".
- **Downed and raising.** A downed hero shows a red wash, "Struck down n" (seconds) over "An ally at your side can
  raise you" and the raise bar from the core's progress; every downed hero in view shows the 40 px raise circle with
  its seconds and progress (`FX_RAISE`), and the figure is faded.
- **The field:** the gate, the heart and its two rings (2,500 and 6,000 px), seven waystones with their 48 px banking
  circle, six war altars (`FieldWorld`, from the terrain).
- **Tides and bosses.** "THE TIDE m:ss" top centre with a red border round the screen, the altars lit and their
  150 px rings while `Field::tide()` is on; "TIDE IN m:ss" otherwise; under it the boss box (its name in Jacquard12
  and its bar) from `world().boss`. See "Waiting for R2".
- **Sound hooks** (`FieldSound`): hit (own health fell), kill, skill, level, down, raise, potion, bank, pick, tide, bad,
  each rate limited per hook (0.07 to 1 s), plus boss roar and death and the field portal. They play WAVs from
  `realm/client/audio/sfx/` (27 sounds, made by our own seeded generator `tools/sfx/sfx.py`, numpy only; rerun it to
  change them) through the `SfxBus` autoload (`audio/sfx.gd`): 24 voices, 1 to 3 plays per group per 100 ms, random
  variant and +-6% pitch; important sounds take the oldest voice. UI: click, panel open, bank chest, town bell.

## Controls

Arrows or WASD move; Space skill 1, E skill 2, R the ultimate (held); F interact (hold 3 s at a waystone); 4 5 6
potions; Z X C V or a click pick the offered card; 1 2 3 zoom 1 2 4; F3 the numbers; Esc quits. Flags: `--server`,
`--class=0..4`, `--race=0..3`, `--zoom=N` (to 32), `--bot`, `--window=WxH`, `--debug=0|1`, `--mute`, `--fake=tide,boss`,
`--shots=DIR --secs=N [--zooms=1,2,4]`. The bot wanders, holds all three skills, picks the first card and drinks
HEALING DRAUGHT under half health.

## The API between the module and GDScript

`RealmLink`: `connect_to_host`, `close`, `poll`, `send_input(direction, buttons, pick)` (buttons: 1 skill 1, 2 skill 2, 4
ultimate, 8 interact, 16 32 64 potion slots 1 to 3), `set_view(rect)`, `hero_view()` (a Dictionary), `monster_buffer`,
`player_buffer`, `fx_rows`, `event_rows`, `world()`, counters, and static lookups (`kind_info`, `skill_info`,
`card_name`, `potion_name`, `class_name`). The old `monsters_in` and `players_in` plain reads are gone from the module
(they remain as test helpers in `draw.rs`). All of it reads the server's `client.rs` through `LockstepClient`'s public
functions only (`hello`, `receive`, `apply`, `input`, `field`, `hero`, `hero_player`, `predictor`, `stats`).

### For the merge with W1 (the two-byte input)

The only place that knows the wire is `worker::wire_byte(input: u16) -> u8`, used once in `worker.rs`. Today it keeps
the direction and skill 1 (bit 7) and drops skill 2, the ultimate, interact, potions and the pick, so those keys are
sent and predicted by nothing yet. When `LockstepClient::input` takes the two bytes, `wire_byte` is replaced by passing
`realm_core::input(b0, b1)`'s bytes through; `core_input` in `lib.rs` already builds exactly the core's two-byte
input from the GDScript form, with a test.

### Waiting for R2 (tides and bosses)

The core today has `Field::tide() -> bool` and no boss. The client draws the tide from it, with a clock counted from
the field's tick by the contract's numbers (a tide every 30 minutes, lasting 5: `TIDE_EVERY_TICKS`, `TIDE_LEN_TICKS` in
`field_hud.gd`), and the six altars always, lit during a tide. When R2 adds its events or state: add the variants to
`event_row` in `frame.rs` (it has a wildcard arm so a new variant compiles), put the tide clock, the lit altars and the
boss (`name`, `health`, `max_health`, position) into `World` and the dictionary in `lib.rs`, and delete the two clock
constants. `FieldHud` already draws a boss bar from `world["boss"]` and the altars from `FieldWorld.tide`;
`--fake=tide,boss` shows them for screenshots.

## Proof and numbers

The ground (`field/field_ground.gd`, `field/ground.gdshader`): each field has two seamless 512 px tiles in
`realm/client/ground/`, two texture px to a field px: `a` its common ground and `b` the ground that shows in
patches (road: earth with pebbles, cobbles; wood: leaf litter, moss; marsh: mud with reeds, standing water; peaks:
snow, bare rock; tower: flagstones, broken paving; edge: ash plates, plates with embers in the cracks). The
shader repeats both and picks between them with a soft map sampled at periods of 1291 and 433 px, shades all of it
with another of 1777 px, so no repeat shows, and gives the patches a ragged, dark-rimmed border; zoomed out
past one screen px per field px the tiles fade toward their mean colours so they do not shimmer. The pictures are
made by `tools/ground/ground.py OUT_DIR` from seeded noise alone (numpy and Pillow; no model and no outside art,
so nothing to license): the same seeds give the same files. The field number comes from `RealmLink.world().field`.

`realm/check_client.sh` prints `REALM_CLIENT ok field_test_checks=112 shots: zoom 1/2/4 ... | server 300x8000
direct: hashes passed=20 failed=0 ... | relay 5% loss 80+-20 ms: hashes passed=20 failed=0 ...`. Screenshots at zoom
1, 2 and 4 (software rendering, Mesa llvmpipe in xvfb, 1440 x 810): `/home/claude/c1_shots` (an archer, `--fake=tide,boss`).
Frames, software rendering on the 4-core build machine at a load of about 3.5 (other jobs running), 1440 x 810:

| setup | zoom | monsters drawn | frame mean / p99 ms | worker ms a tick |
|---|---|---|---|---|
| 300 bots, 8,000 monsters | 1, 2, 4 | 80 to 980 | 55 / 104 to 118 | 4 to 11 |
| 1,000 bots, 20,000 monsters, rally 0.3 | 8 | 5,300 | 102 / 145 | 8 |
| the same | 16 | 8,500 | 104 / 145 | 8 |
| 1,200 bots, 25,000 monsters, rally 0.5 (the `frames` job) | 16 | 13,500 | 132 / 150 | 9 |

Almost all of the frame is the software rasteriser filling figures (the script is under 1 ms); on a card the frame
is the card's. Curtis's number comes from the Windows export and the stations' `frames` job.

## Stations, export and CI

- `tools/station/station.sh frames` builds the server and the module, starts a server (1,200 bots, 25,000 monsters,
  rally 0.5), runs the client as the bot at zoom 16 for 60 s (`STATION_FRAMES_SECS`, `STATION_FRAMES_ZOOM`) and prints
  one line: `JOB frames INFO zooms=16 mean_ms=.. p99_ms=.. monsters_drawn=.. renderer=".."`. It uses `xvfb-run` when
  there is no display. INFO unless a limit is set (`--p95=<ms>` in `roles.txt` or `STATION_FRAME_P99_MS`, applied to
  the 99th percentile). It runs when a merge touched `realm/`. This replaces the old `frames` job, which tested Four of
  Wands (stopped). `roles.txt`: `msi: realm frames deep`, `laptop: realm frames deep`, `heatherspc: realm frames deep`
  (record only); `deep` and `--watch` are untouched.
- `realm/client/export_presets.cfg` is a "Windows Desktop" preset (x86_64, pck embedded, `tests/*` left out). The
  `client-windows` job in `.github/workflows/realm.yml` takes the `realm-godot-windows` artifact (the module's dll),
  downloads Godot 4.7.2 and its Windows templates, imports, exports and uploads `realm-client-windows`
  (`HordeAndHearth.exe`, the console wrapper, and `realm_godot.dll`). Run `HordeAndHearth.exe --server=<host>:7777
  --zoom=16` for the frame rate with a full screen; add `--shots=DIR --secs=60 --zooms=16` for the numbers.
  Verified here up to the export packing the game (the Windows dll cannot be built on this machine, so the full export
  is first exercised by CI).

## Open questions

1. Wire: until W1's two-byte input lands, skill 2, the ultimate, interact (banking), potions and card picks are not
   sent. The HUD shows them and the keys are mapped.
2. Tide and boss: the clock and the lit altars are placeholders (above).
3. Events lost in a catch-up batch (above): if a stall must still show every kill, `LockstepClient::apply` would need
   a per-tick callback; that is W1's file.
4. Frame numbers on real cards are not measured yet (the Windows export and the stations do that).
5. Draw order: figures are sorted by y per batch; monsters (layer 1) are always under players (layer 2), so a hero
   walking "behind" a monster is still drawn over it.
6. Stand-ins are flat; the 34 kinds' pictures and the 2 hero slots arrive as files named as above.

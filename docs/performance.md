# Performance: how to measure

The method that took Sandblood (a gore-heavy physics fighter) from 726 to about 250-340 draw calls and its worst-case
effects script time from 67 ms to 34 ms at high quality, without guessing. Numbers here are examples; each project
keeps its own table at the bottom of this file.

Target: 60 fps on a mid PC and on mid Android phones (Compatibility / GLES3).

## The harness: `tools/perf.sh` + `tests/perf/perf.tscn`

Build one per project once there is a level and a bot. Shape that worked:

`tools/perf.sh [--quality=0|1|2|all] [--seed=S] [--measure=FRAMES] [--heavy] [--hide=part1,part2,...]`

1. **A presented, deterministic scene.** One bot-vs-bot match (or a bot run of a level) with full presentation (level,
   crowd, effects, HUD) in a real window: xvfb on Linux, a tiny resolution (320x180) so the software rasteriser does
   not dominate. Fixed seed so runs compare.
2. **Fast-forward to a state, not a time.** Run at a high time scale until an observed condition holds (for example
   `decals >= 60 and tick >= 600`, or the match ends), with a tick fallback. Then measure N frames (300) at 1x.
3. **A scripted worst case (`--heavy`).** When the measured window starts, inject the most expensive events at once
   (every gore effect on both fighters, every particle burst). Budgets are set against this, not the average.
4. **Toggle parts off (`--hide=`).** Switch one part off during the measured window (crowd, HUD, shadows, effects,
   characters, props); whole scene minus that run is that part's cost in draw calls and triangles.
5. **One row per quality level** (`--quality=all`), printed in a quiet table.

## What to report, and what not to trust

| column | meaning |
| --- | --- |
| frame ms p50 / p95 / max | real frames: `Time.get_ticks_usec()` between frames in a lowest-priority node, after a warm-up |
| script ms per system | each heavy system's own script time, timed apart from the renderer (the number to trust for CPU) |
| phys ms | physics time per frame |
| draw calls | per frame, including shadow passes and the HUD |
| MultiMesh triangles | instances shown x mesh triangles, counted by the harness itself |
| peaks | the counts that grow with play: decals, particles, pooled objects |
| VRAM, nodes | `Performance` monitors, once at the end |

- **Software GL frame time says nothing about a phone or a GPU.** On the cloud box (llvmpipe) engine process time is
  the renderer. Read script ms, draw calls and triangles there; profile frame time on real hardware (the owner's PC
  via Remote Control).
- **Never average `Performance.TIME_PROCESS`.** It updates about once a second with the slowest frame; averaging it
  reported 36 ms for a real 5.2 ms.
- **Godot's primitive counter counts a MultiMesh's mesh once per draw, not once per instance.** Count MultiMesh
  triangles yourself.
- **Warm up.** The first run after `--import` was 4x slower (shader compiles). Rerun a gap twice before hunting it.
  With `--fixed-fps` and vsync off, game time runs faster than wall time: report both.
- **Per-script cost without the editor profiler:** in the measured window call `set_process(false)` on scripted nodes
  and call each `_process` from one timing node, summing by script path.
- CPU ms are noisy under a shared box: read ratios, run heavy jobs one at a time on one machine.

## Budgets

Write budgets per quality level from the worst-case table, and keep low Android-safe. Example shape (Sandblood,
software GL, so treat CPU ms as 3-5x a desktop):

| budget | low | medium | high |
| --- | --- | --- | --- |
| worst-case effects script ms per frame | <= 8 | <= 15 | <= 35 (desktop) |
| draw calls, whole scene | <= 250 | <= 320 | <= 400 |
| MultiMesh triangles incl. crowd | <= 100k | <= 300k | <= 1.6M |
| VRAM | <= 32 MB | <= 48 MB | <= 64 MB |

CI can gate draw calls, triangles and script ms (they are stable under xvfb); GPU frame time stays on real hardware.

## Quality setting

One `GfxQuality.level` (0 low, 1 medium, 2 high) chosen before the scene is built (low on `OS.has_feature("mobile")`,
high on desktop), one Options picker for it, and a `--quality=N` run argument that overrides it. Every expensive
system reads it: crowd density and mesh LOD, shadow splits and distance, MSAA, effect caps, simulation rates and
texture resolution, mesh detail of instanced particles.

## Rules for new effects (each one came from a measured defect)

- Pool and cap everything per quality; never let a count grow with match length.
- A MultiMesh draws its first `visible_instance_count` instances: sort and cut instead of hiding in a shader. Do not
  hide geometry by scaling to zero in the vertex shader; the vertices are still processed.
- Gate repeated work on a changed input (a pool repainting unchanged texels cost 25 ms); hoist per-texel trig into a
  table; budget per-frame work by cost (area, bytes), not by count.
- Only big shapes cast shadows; thin decorative and small limb parts do not, at least on low.
- Many small `draw_*` calls in a HUD add up: cache segment lists and draw them with one `draw_multiline`; hide idle
  banners with `visible = false`.
- Visibility ranges (HLOD) work on `MultiMeshInstance3D`; use decimated meshes or impostors at distance (a MultiMesh
  cannot use engine mesh LOD).
- Pre-warm every effect, material and pool once off-screen during the intro: Godot 4.4+ ubershaders precompile only
  what is loaded, so first use hitches (one was 596 ms).
- Re-run `tools/perf.sh --quality=all` after adding an effect and put the new row in this file.

## Soak

Before a release, run 50+ back-to-back bot matches on real hardware and track the worst frame per match. It finds
per-match hitches (a slow match start, a first-use shader compile) that a single run never shows.

## This project's numbers
<!-- One table per pass: before/after per quality level, the scripted worst case, and what was changed. -->

### Pass 1, 19 Nov 2026: the horde at 12:00

`xvfb-run -a godot --path . -- --autotest=12 --seed=5 --perf` waits for 180+ enemies, then times 300 frames per
system (`PerfMeter`) and counts draw calls. `--perf-hide=decal_layer` (or `ent_layer`, `hud`, `fx`...) hides one
layer to read its share. Cloud box, llvmpipe, so read draw calls and script ms, not frame ms.

| | before | after |
| --- | --- | --- |
| enemies at peak (cap 260) | 392 | 267 to 275 |
| draw calls per frame | 1005 | 235 to 274 |
| frame ms p50 / p95 (software GL) | 38.5 / 68.6 | 18.7 / 33.5 |
| world step ms | 5.9 | 2.0 to 2.4 |
| entities draw ms | 2.2 | 1.5 to 1.6 |
| decals draw ms | 1.8 | 0.1 |

What changed:
- The enemy cap counts queued enemies too, so the field stops near the cap instead of 1.5x it.
- Every sprite is packed in one atlas (`Sprites._pack`), and flips use a negative width rather than a transform,
  so the whole horde is one texture and batches.
- Blood decals are rect blobs, not circles (each circle was its own draw call).
- Elite glows and health bars are drawn in their own passes before and after the sprites.


### Pass 2, 21 Nov 2026: the world step at the enemy cap

`tools/run_sims.sh sim_horde` (4 bots, the cap of 260 enemies; the mixed row adds the eight new kinds, 48 hazard
rows and a floor of gems). The mixed row went over its 4000 us budget on slow CI runners once the eight kinds
were merged. Cloud box, µs of CPU per step:

| | before | after |
| --- | --- | --- |
| `horde_peak_cost_4p` | 3100 | 2550 to 2750 |
| `horde_mixed_cost_4p` | 3650 to 3900 (4450 to 4570 on CI) | 3100 to 3350 |
| enemy update, per enemy | 6.8 | 5.1 |
| separation, per call (55 neighbours) | 8.0 | 4.4 |
| a new kind's brain, per call | 4.5 to 10.4 | 1.3 to 3.5 |
| 156 gems on the floor, per step | 350 | 90 |

What changed (all of it exact: the pinned solo run is unchanged):
- `Brains.think` calls the stock kinds' brains directly; before, each enemy fell through the old kinds' `match`
  and was then looked up and called by name.
- Separation reads a packed copy of the horde (`World._sep_cells`, `_sep_pos`, `_sep_r`), not two fields of every
  neighbour object, and tests the distance before anything else.
- `_update_enemy` finds the nearest wizard in place, leaves stopped timers alone and reads each field once.
- `_update_pickups` works out the living wizards, their magnet reach and the room's edges once a tick, not once
  a gem.
- `World.party_center` uses the cached wizard list.

How to find the next one: time the phases of `World.step` separately, then the pieces of the slowest phase. Take
the lowest of several runs; the box is noisy. Since pass 3 that is a tool:
`godot --headless --path . -s tools/tool.gd -- step_profile [--sets=4/1,2,3,4]` (one line per loadout, every phase
in us, and the state hash, which an exact change leaves alone).

### Pass 3, 21 Nov 2026: homing stars, and a steadier horde row

The wave 3 spell rows of `sim_horde` went over the budget on a slow CI runner (bone spear 4133, vigil candle 4200,
with the old rows at 3533 and 3967). `step_profile` showed the cost was not in the new spells: a STARFALL star
looked for its target with one `World._query` of its whole 160 px reach every step, about 200 enemies a star at
the cap, 230 us a star a step. `WorldCasting._homing_target` now looks within 48 px first and widens only when
nobody is near (the same answer: the state hashes of five loadouts are unchanged, and a unit test compares it
with the wide search). Cloud box, us per step without the bots, every wizard holding the loadout evolved:

| loadout | before | after |
| --- | --- | --- |
| STARFALL alone | 2480 to 2640 | 2180 to 2370 |
| FIREBALL, FROST FAN, STARFALL | 3790 to 3820 | 2540 to 3100 |
| the four above with CHAIN LIGHTNING | 4700 to 5130 | 3540 to 3860 |
| VIGIL CANDLE, FIREBALL, FROST FAN, STARFALL | 5020 to 5400 | 2930 to 3530 |

The peak rows of `sim_horde` hold six unevolved spells a wizard, which no run can (four spell slots) and which
costs less than four evolved ones: the table above is the truer late game. Known and left: four wizards all
holding the SEAL OF SOLOMON cost 4600 to 5100 (28 circles each pulling about 35 enemies a step, and the packed
crowd costs more to separate); a shot in flight costs about 35 us a step (its `_query` and the checks on what it
returns).

`sim_horde` now times its peak in three windows and takes the cheapest (`PEAK_WINDOWS`): the same code measured
2483 to 3217 us on one idle machine with one 600-tick average, and 2500 both times with the windows.

### Pass 4, 27 Nov 2026: real frame times on the two slow PCs (measured; nothing changed yet)

Station job `wandsframes` (`tools/station/jobs/wandsframes.sh`): the real game in a window on the PC's own graphics,
`--autotest=<wave> --players=<n> --perf`, 300 frames. Frame time in ms, p50 / p95.

| scene | Celeron N4100, UHD 600 (Heatherspc) | Ryzen laptop, Radeon 610M |
| --- | --- | --- |
| Archlich (wave 15), 4 players | 133.6 / 217.5 | 18.4 / 28.1 |
| Archlich, 2 players | 115.0 / 211.3 | 17.8 / 27.2 |
| Archlich, 1 player | 72.4 / 170.8 | 16.6 / 18.6 |
| wave 10, 4 players | 126.4 / 186.8 | 17.5 / 23.4 |
| wave 5, 4 players | 67.2 / 152.3 | not run yet |

Script time a frame at the Archlich with 4 players, in ms (`PERF` lines; about 280 enemies, about 100 draw calls):

| section | Celeron | Ryzen laptop |
| --- | --- | --- |
| world_step | 66.86 | 3.55 |
| snapshot | 22.82 | 1.37 |
| draw_entities | 15.38 | 4.64 |
| draw_hud | 4.49 | 1.54 |
| total_script | 119.00 | 14.19 |

What the numbers say, for the speed pass (stage 3 of `docs/release_plan.md`, skill `measure-fix-loop`):

- The game is script-bound on both PCs.
- `Arena._physics_process` runs `world.step`, `world.snapshot` and `_apply_snapshot` once a physics tick, 60 a
  second. A frame slower than 16.7 ms runs several ticks (the engine's cap of 8 a frame is not changed in
  `project.godot`), so the Celeron pays for about 8 steps and 8 snapshots a frame: about 8.4 ms a step and 2.9 ms a
  snapshot, against about 3.2 and 1.2 on the laptop. Only the last snapshot of a frame is drawn. Read a section's
  cost per tick (section / ticks a frame) before comparing two machines.
- Candidates, in the order to measure them: apply the snapshot once a drawn frame when offline (the network keeps
  its own rate); a lower cap on ticks a frame, so a slow PC slows down instead of spiralling; the step at the enemy
  cap; `draw_entities`; `draw_hud` (4 to 5 ms on the Celeron for a mostly still picture).
- The gate (stage 5): the worst moment of a four-player run holds 60 frames a second on the Ryzen laptop. Today its
  script cost alone is 14.2 ms of the 16.7.

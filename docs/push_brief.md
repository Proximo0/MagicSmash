# The big push, wave 1: brief for workers

Read `CLAUDE.md`, `docs/agent_brief.md` (the hard rules) and `docs/lessons_learned.md` first. "Launch scope and
the big push" in `docs/handoff.md` says where the game is going. This file adds the rules and contracts for the
five workers of wave 1. Workers code against it at the same time; nobody changes a contract here without the lead.

## Rules on top of `docs/agent_brief.md`

- You work in your own git worktree. Do not run git. The lead commits your files from your worktree, so your final
  report lists every file you created or changed.
- Four CPUs are shared by five workers. Run one engine at a time, keep runs short, and never start
  `tools/check_all.sh` or the whole sim suite (the lead runs them). Run your own unit test file
  (`tools/run_tests.sh test_<name>`), `tools/lint.sh`, and a named sim only when you changed code it covers
  (`tools/run_sims.sh sim_waves`). `sim_horde` asserts a time budget and fails on a busy box: leave it to the lead.
- `arena.gd` and `world.gd` are shared. Edit only the functions the table gives you, with small anchored edits,
  and re-read the lines around an edit just before you make it. New code goes into new files where it can.
- The `addons/sentry` folder is not in your worktree. Nothing needs it.
- Screenshots of the real game: `xvfb-run -a godot --path . -- --autotest[=minute] --players=N --seed=S
  --quit=SECONDS --out=DIR`. The run takes shots at 7, 12, 16, 22, 28, 36, 44, 52 and 58 s, plus state-keyed ones
  (`levelup.png`, `chest.png`...); `--quit` stops it early. View every image you make at 2x
  (`convert in.png -filter point -resize 200% out.png`) and fix what looks wrong before you report.
- Faster art loops: a throwaway `-s` script in `/tmp/<your task>/` that draws your sprites or your floor to a PNG
  in a few seconds (rules for `-s` scripts are in `docs/agent_brief.md`).
- Art follows Curtis's rule: either a plain placeholder nobody would take for finished, or fully finished art.
  Nothing in between. Wave 1 art is finished art; it merges only after Curtis has seen the screenshots.

## Who owns what

| Worker | Goal | Owns |
|---|---|---|
| A, shared XP | The party levels together and picks on one screen | `world.gd`: `gain_xp`, `_offer`, `_pick`, `_update_levelups`, `is_picking`, the XP lines of `_collect`, the blessing in `_resolve_gamble`, the level and XP fields of `snapshot`. `arena.gd`: `_draw_hud`, `_draw_levelup`, `_pick_input`, `_confirm_pick`, `_pick_dir`, `_card_rect`, `_deal`, `_anyone_picking`, `_local_pick_slots`, `_with_pick`, and the level and XP fields of `_apply_snapshot`. `tuning.gd` (new XP rows), `tests/unit/test_world.gd`, `tests/unit/test_tuning.gd`, `tests/sim/sim_waves.gd` |
| B, bots | Human-like play-testers and a playtest report | `game/logic/smash_bot.gd`, `tests/unit/test_smash_bot.gd`, `tools/full_run.gd`, new `tools/playtest.gd`, `tests/bot/bot.gd`, new `docs/bots.md`, `arena.gd`: `_bot_input` only. In `world.gd` and `results.gd`: lines that record statistics only (no change to behaviour or to `state_hash`) |
| C1, actors | Finished wizards, enemies, pickups and spell shots at the new scale | `game/art/sprites.gd`, new `game/art/sprites_*.gd`, new `tools/sprite_sheet.gd`, `game/arena/fx.gd`, `arena.gd`: `_draw_entities`, `_draw_player`, `_draw_staff`, `_draw_enemy`, `_draw_enemy_bars`, `_draw_shots`, `_draw_eshots`, `_shadow`, `_draw_treasure_glow`, `_emit_trails`, `_spell_color`, `_pickup_color` |
| C2, Act I floor | A finished Ossuary: floor, walls, doors, light | `game/arena/arena_bg.gd`, new `game/art/arena_art_*.gd`, `arena.gd`: `_draw_decals`, `_draw_env`, `_draw_env_add`, `_torch_fx`, `_decal` |
| D, title | The FOUR OF WANDS title screen and logo | `game/ui/title.gd`: the backdrop, the logo and the menu's look; new `game/art/title_art.gd` |

Everything else is the lead's: `project.godot`, autoloads, `autotest.gd`, `docs/handoff.md`, `CLAUDE.md`. If you
need a change there, give the exact lines in your report.

## Contract: shared XP (worker A provides; B and the HUD read it)

- `World.party_level: int` (from 1) and `World.party_xp: int`. `World.xp_needed() -> int` is the XP the party
  needs for its next level. `Player.level` always equals `party_level`; `Player.xp` is no longer used for levelling.
- `World.gain_xp(p, amount)` keeps its signature and adds to the party's pool. When the pool fills, every wizard in
  the run gets one more pending offer, whether alive or down.
- Offers stay per wizard: `Player.choices`, `Player.offer`, `Player.pending`, and input fields 6 and 7
  `[card, offer id]` work as before, so `SmashBot.with_pick` does not change.
- `World.pick_left: float` is the seconds left on the party's pick clock (0 when nobody is picking or when the clock
  is off). The clock runs only with two or more wizards. Snapshots carry it.

## Contract: bots (worker B provides; the arena, sims and tools read it)

- `SmashBot.new(seed_value: int = 1, persona: int = SmashBot.CASUAL)`. Personas: `NOVICE`, `CASUAL`, `VETERAN`.
- These keep their signatures: `decide(slot, me, center, time, enemies, enemy_shots, pickups, goal)`,
  `decide_in_world(world, slot)`, `static choose_pick(choices)`, `static with_pick(inp, choices, offer)`,
  `static shrine_goal(me, gold, rows)`. Extra arguments are optional and go at the end.
- The output stays `[move_x, move_y, aim_x, aim_y, fire, nova_count]`, plus `[pick, offer]` from `with_pick`.

## Contract: art (workers C1, C2 and D share it)

**The look: candlelit occult pixel art.** At a squint the picture has three layers of value: a dark, quiet floor;
mid-to-bright actors with a clean dark outline; magic as the brightest thing on screen.

- The screen stays 480x270 and the camera does not zoom. Hit radii and positions belong to the simulation and do
  not change; a sprite may be bigger than its hit circle.
- **Floors and walls** stay dark and low in contrast: average brightness under about 22%, and neighbouring tiles
  within a few percent of each other. No bright mortar grid. Detail comes from large shapes: worn paths, cracks,
  engraved circles, rugs, rubble, bones along the walls.
- **Actors** get a 1 px outline in `Sprites.OUTLINE` (`#1a0f24`), a drop shadow, light from the upper left, and
  at least three shades per material. Anchor: the feet, bottom centre.
- **Sizes** (width x height, give or take 2 px): wizard 16x22 with the hat; goblin 14x14; bat 16x11; slime 14x11;
  mini slime 9x7; skeleton 12x18; orc 20x22; an elite is its sprite at 1.5x; XP mote 5x5; coin 6x6; gem 7x8;
  potion 7x9; chest 14x12; tome 9x10.
- **Animation:** a wizard has idle (2 frames) and walk (4 frames) facing down, up and side (side is mirrored for
  left), plus a cast frame. An enemy has 2 to 4 frames. Timing lives in the drawing code, not in `World`.
- **Every wizard stands on a floor ring** in their colour (an ellipse about 18x7, soft, under the shadow), so a
  player finds themselves at once. The `P1` tag stays for parties.
- **Palette.** Use these colours; add only a lighter or darker step of a ramp that is already here.
  - Ink and outline: `0b0716`, `1a0f24`
  - Night purples: `120a1f`, `1c1230`, `2a1f45`, `3a2a5e`, `4b3a78`
  - Stone: `221b2e`, `2e2540`, `3b3150`, `4a4063`, `5d5378`
  - Candle light: `ffcf5a`, `ff9a3c`, `c85a1e`, `7a2f14`
  - Bone: `e8dcc0`, `b7a98e`, `7d705c`. Gold: `ffd94d`, `c48a10`. Blood: `c0263a`, `7a1226`
  - Wizards (light, robe, shade): violet `c9a6ff` `7b4dff` `4b2ab8`; crimson `ff9a6b` `ff3b5c` `a81d3d`;
    emerald `8bff9e` `29d16b` `15864a`; amber `ffe58a` `ffb326` `c26a0e`
  - Goblin and moss greens: `6fd23c`, `2f7a2a`, `1c4a22`. Slime and spirit teals: `d8fff6`, `32e0c4`, `158f86`
  - Magic: magenta `ff4df2`, cyan `4dfff0`, ice `8fe3ff`. Skin: `ffd2a6`, `c98a6b`
- Curtis likes the Sanctum's rune portal: slow turning rings, runes that orbit, a soft glow. Magic in the arena and
  on the title should feel like it.

## Contract: the title (worker D)

- The game is now called FOUR OF WANDS. The tarot card shows four staffs planted in the ground with a garland
  strung between them, a castle behind, people celebrating. Our four staffs belong to the four wizards (violet,
  crimson, emerald, amber) and the castle is their tower.
- The title screen keeps working exactly as it does: the menu and its rows, the two secrets (clicking the moon,
  clicking the lit castle window), the version and best-score text, every sub-screen. Only the look changes.

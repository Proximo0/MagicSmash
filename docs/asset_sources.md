# Asset sources

Date: 28 Nov 2026 · Commit: 64306bc0 · Game: Four of Wands (Horde & Hearth folders skipped, see the end)

What this is: for every picture, sound, music track and font the game ships, who or what made it, the evidence, and
the licence as far as the evidence goes. Written from the repo and the owner's upload log, nothing guessed.

How to read it:
- "files" counts real assets. Godot makes one `.import` file next to each picture and sound; `.uid` files sit next to
  scripts. Those are not counted (the proof lines in the report give both numbers).
- Made by: `drawn in code by <script>`; `made by <tool>` only where a commit, doc or log names it; `uploaded by the
  owner, batch <id> on <date>, tool not recorded`; `unknown`. A picture's look was never used as evidence.
- Evidence tags: `inputs.md:N` = `/mnt/project-files/.notes/inputs.md` line N; `sheets.md:N` =
  `/mnt/project-files/magic-smash-rework/art/sheets.md` line N (both outside the repo); `manifest.tsv` =
  `/mnt/project-files/magic-smash-rework/art/tools/manifest.tsv`. Repo files are given as `file:line`.
- Git history is short: the oldest commit in this tree is fb84a4db (23 Nov 2026), which already holds every asset. So no
  commit says who made a picture; the upload log does. Pixel comparison (below) ties the repo files to the log's copies.
- "Batch" ids: sheets 1 to 5 are the numbers the log gives them; A1 to C2 are the art-list codes the log gives them.
- Licence column: for owner uploads the log records no licence and no tool. So the licence is `not recorded`: whether the
  owner may ship them depends on where each picture came from, which is an open question below.

## How the owner's pictures were matched to the repo

The log (inputs.md) says each uploaded sheet was cut by the lead into `.../game/<name>.png` copies. Each repo
picture was compared to its log copy, pixel by pixel (the folder `/mnt/project-files/magic-smash-rework/art/`):

| Repo folder | Compared with | Result |
|---|---|---|
| `assets/art/portraits/heroes` | `portraits/heroes/game/` | 20 of 20 byte-identical |
| `assets/art/portraits/characters` (6 plain) | `portraits/characters/game/` | 6 of 6 byte-identical |
| `assets/art/portraits/characters` (6 `_tall`) | `portraits/characters/tall/` | 6 of 6 byte-identical |
| `assets/art/cards/monsters` | `cards/monsters/game/` | 13 of 13 byte-identical |
| `assets/art/cards/tarot` | `cards/tarot/game/` | 12 of 12 byte-identical |
| `assets/art/sprites` | `sprites/game/` | 34 of 34 same pixels (PNG recompressed: different bytes, same RGBA) |
| `assets/art/icons` | `icons/game/` | 12 of 12 same pixels (3 byte-identical, 9 recompressed) |

## Pictures the owner uploaded (cut by the lead)

| Path or glob | Files | Made by | Evidence | Licence of the result | Confidence |
|---|---|---|---|---|---|
| `assets/art/portraits/heroes/hero_<race>_<class>.png` (160x240) | 20 | uploaded by the owner, batch hero sheet 2 on 20 Nov 2026, tool not recorded; cut by the lead | inputs.md:15-20 (sheet, 23:36 UTC, 20 cards 5x4); byte match above | not recorded | sure (source), unknown (tool) |
| `assets/art/portraits/characters/<name>.png` (160x240) and `<name>_tall.png` (130x270): shopkeeper, card_reader, bone_chandelier, ghost_writer, archlich, apprentice | 12 | uploaded by the owner, batch character sheet 3 on 20 Nov 2026, tool not recorded; cut by the lead | inputs.md:22-26; byte match above | not recorded | sure (source), unknown (tool) |
| `assets/art/cards/monsters/*.png` (13 monster cards: bat cinderling gargoyle goblin lich mage orc priest skeleton slime ten_of_swords tome wraith) | 13 | uploaded by the owner, batch monster card sheet 4 on 20 Nov 2026, tool not recorded; cut by the lead | inputs.md:28-33; byte match above | not recorded | sure (source), unknown (tool) |
| `assets/art/cards/tarot/*.png` (the_fool, the_magician, the_high_priestess, death, the_tower, the_star, the_moon, suit_cups, suit_swords, suit_wands, suit_pentacles, card_back) | 12 | uploaded by the owner, batch tarot sheet 5 on 20 Nov 2026, tool not recorded; cut by the lead | inputs.md:35-40; byte match above | not recorded | sure (source), unknown (tool) |
| `assets/art/sprites/hero_<race>_<class>.png` (20) and `apprentice.png` (1) | 21 | uploaded by the owner, batches A1 to A5 on 21 Nov 2026, tool not recorded; cut by the lead with `art/tools/cut.py` | inputs.md:42-47; sheets.md:9-13 and 58-62; manifest.tsv rows A1-A5; pixel match | not recorded | sure (source), unknown (tool) |
| `assets/art/sprites/enemy_bloat coffin guard cinderling censor hound.png` | 6 | uploaded by the owner, batch B1 on 21 Nov 2026, tool not recorded; cut by the lead | same log entry; sheets.md:16; manifest.tsv row B1; pixel match | not recorded | sure (source), unknown (tool) |
| `assets/art/sprites/enemy_shard enemy_swords hub_lectern hub_mirror hub_plinth.png` | 5 | uploaded by the owner, batch B2 on 21 Nov 2026, tool not recorded; cut by the lead | same log entry; sheets.md:17; manifest.tsv row B2; pixel match | not recorded | sure (source), unknown (tool) |
| `assets/art/sprites/boss_chandelier.png`, `boss_ghostwriter.png` | 2 | uploaded by the owner, batch B3 on 21 Nov 2026, tool not recorded; cut by the lead | same log entry; sheets.md:18; manifest.tsv row B3; pixel match | not recorded | sure (source), unknown (tool) |
| `assets/art/icons/spell_arcane fire frost storm star rune.png` (32x32) | 6 | uploaded by the owner, batch C1 on 21 Nov 2026, tool not recorded; cut by the lead | inputs.md:42-47 (C1), sheets.md:21; pixel match | not recorded | sure (source), unknown (tool) |
| `assets/art/icons/spell_bone spell_candle spell_cleave weapon_longbow weapon_holy_light weapon_smite.png` | 6 | uploaded by the owner, batch C2 on 21 Nov 2026, tool not recorded; cut by the lead | sheets.md:22 lists these six as C2; pixel match with `icons/game/`; the log (inputs.md:47, sheets.md:62) says the three `weapon_` ones were not yet in the repo then, they are now | not recorded | likely (art-list rows name them as C2 and the pixels match; the upload entry's own C2 line was not read in full) |

Sprites by the numbers: 21 + 6 + 5 + 2 = 34. Icons: 6 + 6 = 12.

Notes the log gives that matter for licensing:
- Nothing in the log for these batches names a tool (no "made with ..."). The only tools the log names are for
  Horde & Hearth pictures: Perchance (HR6 paladin candidates, inputs.md:60) and Tripo free tier (inputs.md:62-64, "licence
  of free-tier output NOT confirmed"). Neither is used by Four of Wands files, so far as the log shows.
- The log (inputs.md:3-7) records one example the owner supplied for the Morvane portrait ("lich pixel.png", source
  not stated: "his own, commissioned, generated"). No repo file is recorded as built on it.
- The sprite sheets' own "pixels" are not clean (inputs.md:44: "about 5 px cells ... anti-aliased"), so the repo
  sprites are reductions of larger pictures, by area average, with a 1 px dark outline added by the cut tool.

## Pictures drawn in code

All of these are scripts in `game/art/` (17 scripts; 34 files with their `.uid` files). No image file is behind them.
They are the project's own code, so the licence follows the repo's own (the repo has no licence file: see open questions).

| Path or glob | Files | Made by | Evidence | Licence of the result | Confidence |
|---|---|---|---|---|---|
| Sprites of the four wizards, enemies and fx: `game/art/sprites.gd`, `sprites_wizards.gd`, `sprites_enemies.gd` | 3 | drawn in code by those scripts (ASCII maps, one character per pixel) | `game/art/sprites.gd:2-4`; `sprites_wizards.gd:2`; `sprites_enemies.gd:2` | the repo's own code | sure |
| Floors and backdrops of the arena: `game/art/arena_art_floor.gd`, `_canvas.gd`, `_room.gd`, `_props.gd`, `_live.gd`, `_ossuary.gd`, `_library.gd`, `_sanctum.gd` | 8 | drawn in code by those scripts (index-painted canvas, paving, props, candle light) | `game/art/arena_art_canvas.gd:3-4`; `arena_art_floor.gd:3`; `arena_art_props.gd:3`; `arena_art_ossuary.gd:3` | the repo's own code | sure |
| The hub (the Sanctum tower room): `game/art/sanctum_art.gd` | 1 | drawn in code by `sanctum_art.gd` | `game/art/sanctum_art.gd:3-4` | the repo's own code | sure |
| Title screen picture: `game/art/title_art.gd` | 1 | drawn in code by `title_art.gd` | `game/art/title_art.gd:3` | the repo's own code | sure |
| Tarot emblems of level-up cards (16x16 ASCII maps): `game/art/tarot_art.gd` | 1 | drawn in code by `tarot_art.gd` | `game/art/tarot_art.gd:2-4` | the repo's own code | sure |
| Monster card frame: `game/art/monster_card.gd` | 1 | drawn in code by `monster_card.gd` (frame only; the monster is a sprite) | `game/art/monster_card.gd:3` | the repo's own code | sure |
| Loaders, not pictures: `game/art/art.gd`, `still.gd` | 2 | not assets; they load the uploaded files above and fall back to the drawing | `game/art/art.gd:3`; `still.gd:3` | n/a | sure |

Total 17 scripts = 3 + 8 + 1 + 1 + 1 + 1 + 2.

## UI pieces

| Path or glob | Files | Made by | Evidence | Licence of the result | Confidence |
|---|---|---|---|---|---|
| Menus, HUD, dialogue box, panels: `game/ui/*.gd` and the arena's `hud`, `tray`, `results_view` | 11 scripts in `game/ui`, 20 in `game/arena` | drawn in code by those scripts (rects, polygons, textures from the families above); no UI image files exist in the repo | `git ls-files` finds no UI picture; 11 of 11 `game/ui` scripts call `draw_rect`, `draw_polygon` or `draw_texture` | the repo's own code | likely (I did not read each script) |
| The five scene backdrops the drop-in folder allows (`scenes/builder`, `lobby`, ...) | 0 | not shipped: no file exists; `docs/art_dropin.md` says a missing file leaves the code drawing | `docs/art_dropin.md` (Scenes row, last line of the figures section); `git ls-files assets/art` shows no `scenes` | n/a | sure |

## Fonts

| Path or glob | Files | Made by | Evidence | Licence of the result | Confidence |
|---|---|---|---|---|---|
| The game's text: `game/ui/pixel_font.gd` (5x7 glyph tables drawn with rects) | 1 script | drawn in code by `pixel_font.gd` | `game/ui/pixel_font.gd:1-3`: "Hand-made 5x7 bitmap font drawn with rects" | the repo's own code | sure |
| Debug frame stamp text (`game/debug/frame_stamp.gd` uses `ThemeDB.fallback_font`) | 0 files in repo | Godot's built-in fallback font, inside the engine | `game/debug/frame_stamp.gd:57,82` | Godot's, covered by the engine's licence data that `tools/notices.gd` writes | likely |
| Font files (`*.ttf`, `*.otf`) in the Four of Wands tree | 0 | none exist | `git ls-files` finds font files only under `realm/` (Horde & Hearth) | n/a | sure |

## Music

| Path or glob | Files | Made by | Evidence | Licence of the result | Confidence |
|---|---|---|---|---|---|
| `assets/audio/music_title.wav` (88.9 s, 108 bpm) | 1 | made by `tools/music/engine.py` (offline synth in the repo) from `tools/music/songs/music_title.py` | `tools/music/out/music_title.render.log:44` ("wrote .../assets/audio/music_title.wav"); `tools/music/SOUNDTRACK.md:3`; `engine.py:1-8` | the repo's own work; no sample or outside material named | sure |
| `assets/audio/music_battle.wav` (96.0 s) | 1 | same, from `songs/music_battle.py` | `tools/music/out/music_battle.render.log`; `music_battle.report.txt:1` | same | sure |
| `assets/audio/music_boss.wav` (81.8 s) | 1 | same, from `songs/music_boss.py` | `tools/music/out/music_boss.render.log`; `music_boss.report.txt:1` | same | sure |
| `assets/audio/music_gameover.wav` (8.0 s) | 1 | same, from `songs/music_gameover.py` | `tools/music/out/music_gameover.render.log`; `music_gameover.report.txt:1` | same | sure |
| `assets/audio/music_library.wav` (91.4 s) | 1 | same, from `songs/music_library.py` | `tools/music/out/music_library.report.txt:1` (no render log, report and loop file present) | same | likely |
| `assets/audio/music_sanctum.wav` (96.0 s) | 1 | same, from `songs/music_sanctum.py` | `tools/music/out/music_sanctum.report.txt:1` (no render log) | same | likely |

The engine has no version number. No commit records who wrote the song files (the oldest commit is already a snapshot).
I did not render the songs again to compare bytes.

## Sound effects

| Path or glob | Files | Made by | Evidence | Licence of the result | Confidence |
|---|---|---|---|---|---|
| `assets/audio/*.wav` except the six `music_*` (arrow, bell_toll, boss_roar, candle, card_deal, card_flip, card_pick, charge, coin, door, enemy_die, enemy_shot, explode, ghost, gong, heal, hit, hurt, menu_move, menu_select, nova, orbit, page_turn, pickup, planchette, player_die, portal, powerup, rune_bad, rune_cast, rune_good, shoot_arcane, shoot_fire, shoot_frost, slime, star, teleport, wave_clear, wave_start, whisper, zap) | 41 | made by `tools/gen_audio.py` (numpy synth: square, triangle, noise, filters) | `tools/gen_audio.py:2-8` ("Generates all Magic Smash sound effects ... Everything is synthesised ... no licensing questions"); the 41 `finish("<name>")` calls match the 41 file names exactly (checked by script) | the repo's own work; the script says nothing outside is used | sure (names match; bytes not regenerated) |
| `assets/audio/*.wav` added 28 Nov 2026 (banish, boss_fall, boss_phase, down, enemy_die_2, enemy_die_3, enemy_die_4, fate, hit_2, hit_3, hit_4, level_up, low_health, redraw, revive, shrine_result, victory) | 17 | made by `tools/gen_audio.py` `sfx_new()` (the same numpy synth, its own seed) | the 17 `finish("<name>")` calls of `sfx_new()` match `NEW_SOUNDS` and the 17 file names; `tools/gen_audio.py --only=<the 17 names>` wrote the same bytes again on 28 Nov (md5 compared) | the repo's own work; nothing outside is used | sure (bytes regenerated) |

`docs/systems.md` says "58 SFX" since 28 Nov (41 older ones and these 17).

## Store capsules and achievement icons

| Path or glob | Files | Made by | Evidence | Licence of the result | Confidence |
|---|---|---|---|---|---|
| `docs/achievements/<API name>.png` and `<API name>_locked.png` (14 achievements, 64x64) | 28 | drawn in code by `tools/achievement_icons.gd`, from the tarot emblems of `game/art/tarot_art.gd` | `tools/achievement_icons.gd:2-4`; `docs/steam.md:100-102` | the repo's own work | sure (script says it; files not regenerated) |
| Steam capsules (header, small, main, vertical, library capsule, library hero, library logo) | 0 in the repo | drawn in code by `tools/capsules.gd` into `build/capsules` (not committed); a draft | `tools/capsules.gd:2-4`; `docs/steam.md:19-23` | the repo's own work; a hand-made key art pass is named as to come | sure (script), no files to count |
| `docs/screenshots/*.png` (boss, chain-lightning, horde, lan-host-and-client, title) | 5 | unknown: not in a script; `docs/systems.md:19` calls them "xvfb screenshots" of the game | `docs/systems.md:18-19` | the game's own art | likely (taken from the game; who or when not recorded) |

## The exe icon

| Path or glob | Files | Made by | Evidence | Licence of the result | Confidence |
|---|---|---|---|---|---|
| `tools/windows/icon.ico` (16 to 256 px) | 1 | made by `tools/make_icon.py` (Pillow), cropped from `assets/art/portraits/heroes/hero_human_mage.png`; a stand-in | `tools/make_icon.py:2-4`; `docs/release_build.md:15` | follows the hero portrait it is cut from: not recorded | sure (script), unknown (licence) |
| `icon.svg` (project and editor icon, 128x128) | 1 | unknown: 16x16 vector rectangles; no script, doc or log names a maker | `icon.svg` itself (563 bytes); `project.godot:12` | not recorded | unknown |

`tools/windows/Send-Test-Crash-Report.bat` is a script, not an asset.

## Third-party things that ship

| Thing | Kind | Licence | Where its licence text sits | Evidence |
|---|---|---|---|---|
| Godot Engine 4.7.2 (the game runs on it; the export holds its runtime) | engine code | MIT, plus the licences of its own bundled parts (for example its default font) | not in the repo; `tools/notices.gd` writes `THIRD_PARTY_NOTICES.txt` from the engine's own data. No such file is committed: `missing` until the notices step is run at export | `tools/notices.gd:2-4`; `docs/release_build.md:20` |
| Sentry for Godot addon 2.5.1 (crash reports; Windows builds only; absent in CI) | code and native libraries | MIT (the addon's own files; Crashpad and sentry-native notices are named as not yet in the notices file) | inside the downloaded `addons/sentry` (git-ignored, not in the repo); `missing` in the repo | `docs/sentry.md:12-15`; `docs/release_build.md:20-22` |
| GodotSteam extension (Steam; planned) | native extension | not recorded | not in the repo; the extension is not installed yet | `docs/steam.md:9,15`; `game/autoload/platform.gd:2` |
| Pillow, numpy, scipy (used by the build and art tools, not shipped in the game) | tool libraries | not recorded here | not in the repo | `tools/make_icon.py:5`; `tools/gen_audio.py:14` |
| The owner's painted and pixel pictures (the 103 files above) | pictures from outside the code | not recorded; the source of each sheet is an open question | n/a | inputs.md (no licence line for any of the batches) |
| Fonts, sounds, music | none from outside | n/a | n/a | no font file and no sample in the Four of Wands tree; sounds and music are generated by the repo's scripts |

The repo has no `LICENSE`, `NOTICE` or `THIRD_PARTY_NOTICES` file (checked with `git ls-files`).

## Folders skipped, and why

- `realm/`, `docs/realm/`, `game/crowd/`: Horde & Hearth (job text). Not read. `git ls-files` shows font files there only
  (`realm/client/ui/fonts/`: two fonts and two licence files); they do not ship with Four of Wands, whose export
  filters out `realm` (`docs/systems.md`, "Release builds and debug flags"). The file names were seen, nothing was read.
- `tools/animator/` and its `out/` and `samples/` pictures, `tools/art/` (`import.py`, `pixsnap.py`, `frames.py`,
  `game_names.tsv`, `realm_palette.hex`), `tools/sfx/sfx.py` (writes to `realm/client/audio/`), `tools/char3d/`,
  `tools/ground/`: Horde & Hearth tools and their pictures (hero codes HR1 to HR6, `realm` output paths); the export
  excludes `tools`. Not Four of Wands assets.
- `tests/`, `.github/`, `docs/` pictures not listed above: none exist besides `docs/achievements` and `docs/screenshots`.
- `tools/music/out/*.roll.png` (18 files): piano-roll pictures made by the music engine for checking; not shipped.

## Open questions for the owner

1. Where does each of the five painted sheets (hero 2, character 3, monster card 4, tarot 5) come from: your own
   painting, a commissioned artist, or a generator? Nothing in the repo or the logs names a tool or a licence.
2. Same question for the ten pixel sheets A1 to A5, B1 to B3, C1, C2 (sprites and icons).
3. Does the owner hold the right to ship the pictures in question 1 and 2 commercially on Steam (the store asks)?
4. Is `lich pixel.png` (inputs.md:3-7, the Morvane example) your own work, and is any shipped picture built on it?
5. Who made `icon.svg`?
6. Who took the five `docs/screenshots` pictures, and may they be shown on the store page?
7. Which licence should the repo's own code, music and sounds carry (there is no licence file), and what name goes in the credits?
8. The `docs/art_dropin.md` list names pictures the game wants and nobody has made (`evo_*`, `passive_*`, `class_*`,
   `race_*`, `stat_*`, `skill_*`, `loot_*`, `seal_*`, scenes): are any more files coming from the owner, and from what tool?

## The lead's notes on the open questions (28 Nov 2026)

- 1 to 3 are asked of the owner (28 Nov). The art list he worked from gave prompts, at most six pictures a prompt,
  so the sheets are most likely from a picture generator (the lead's guess: no log says so); which tool and which plan
  is written nowhere. Until he answers, the 103 pictures count as "source not confirmed": they stay in the game, and
  the credits screen and stage 7's store forms (Steam asks about generated content) wait for the answer.
- 4 stays open. No shipped picture is recorded as built on that example.
- 5: `icon.svg` has no known maker. It is the project's window icon; the exe icon is `tools/windows/icon.ico`. Both
  are stand-ins, replaced in stage 4 by a picture made for the purpose with its tool on record.
- 6: the five screenshots are scripted captures of the game (`docs/systems.md:18-19`), so they show only the game's
  own pictures. The store page gets new ones in stage 7.
- 7: the game is sold, not open source: its code, music and sounds are the owner's and carry no open licence. The
  name for the credits, the copyright line and the exe's properties is asked of the owner with 1 to 3.
- 8: by the owner's decision of 20 Nov the lead makes new pictures itself on the MSI with FLUX.2 klein 4B (Apache
  2.0; never the 9B model, which is non-commercial), each recorded with its tool and licence. The drop-in names
  nobody has made yet are stage 4's list.

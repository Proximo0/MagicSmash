# char3d: heroes from rigged 3D bodies, rendered to game-size sprites

Route approved by Curtis on 23 Nov 2026. Motion and anatomy are right by construction: one skeleton, one set of
animations, every hero is the same body dressed differently.

1. **Body** (`make_body.py`, `mpfb_ext.py`): MPFB2 (code GPL, assets CC0) makes a body per race on a station PC:
   queue job `script=charbody race=<race>`, result `work/<id>/art/<machine>-<race>.glb` on `station-results`.
2. **Dress, animate, render** (`build_hero.py`, `retarget.py`): colours the body by region, cuts armour shells from the
   body by bone weights, hangs simple pieces (helm, pauldrons, boots, hood, cape) on bones, copies poses and weapons
   from the KayKit Adventurers pack (CC0, github.com/KayKit-Game-Assets), renders each frame plus a material-ID pass
   with Cycles on the CPU. A kit in `KITS` is a class; `RACE` sets skin colour and the race's head feature.
3. **Shrink** (`post.py`): 4x4 blocks take the majority material and one of its three flat tones, a dark pixel where
   two materials meet, a 1 px outline. Output: one strip per action (144 px frames, a human is about 56 px tall), a
   json and a 6x sheet.

`build_all.sh <bodies> <KayKit gltf dir> <out>` runs every line of `classes.txt` (kit, pack file, actions) for each
race. About 20 s a hero on a cloud CPU. Never name a script `inspect.py` next to bpy.

Before showing or importing: zoom in and count arms, hands, legs and feet in every strip.

**Import into the game**: `python3 tools/char3d/import_sprites.py heroes|monsters <source dir> realm/client/art`
(`import_heroes.py <dir> <art>` still works) crops every frame of a character with one shared box (symmetric about the
body centre, bottom edge 1 px under the feet, no resampling) and writes `<key>_walk|atk|hit|die.png`, a still and
`_walk.json` (frame counts, 12 fps, scale 0.4667). Heroes are `hero_<race>_<class>`; monsters `enemy_<name>` from
`enemy_<name>_<action>.png` (walk = any `walking_*`, death = any `death_*`, attack = the remaining action). Keys in
`art/locked.txt` are skipped. Godot makes the `.import` files the first time the editor opens the folder.

## Field and act bosses (bosses.txt)

`build_bosses.sh <human body glb> <KayKit adventurers gltf dir> <out dir> [name ...]` renders every line of `bosses.txt`
(name, pack, actions, env) at 2.2x the monsters' pixels (RES = 276 x ORTHO, a multiple of 4), then
`python3 tools/char3d/import_sprites.py monsters <out dir>/strips realm/client/art`. Three ways to build one:
- pack `-`: a plan of `build_beast.py` (`tree`, `chandelier`, `ghost`, `rider`), all shapes moved by code;
- a KayKit adventurers pack name: the human body in a `build_hero.py` kit (`boss_*`), re-posed from the pack's clips;
- `skel:Skeleton_Warrior` (set `SKELS` to the KayKit Skeletons `Characters/gltf` dir): `build_skel.py`, the skeleton's own rig and
  clips. It is a big-skulled chibi and reads cute: no boss uses it any more.
- Robed tall figures (`boss_bone_regent`, `boss_archlich`): the human body in a `build_hero.py` kit with the parts of
  `boss_extras.py` (exec'd inside build_hero: `skull`, `ribs`, `mantle`, `mitre`, `phylactery`, held `sceptre` and `lichstaff`
  meshes). Kit keys `nolegs` (no legs under the robe), `float` (m, lifted, not in Death), `bulk` values may be a per-axis tuple.
  View: bone regent YAW=-15 (the skull face shows; at -70 the head is a tube in profile).
The rider plan's horse is built by `build_beast.py` itself (no downloaded model; Quaternius's licence also bars their files from a public repo):
four legs of three bones each (upper, lower, pastern+hoof) joined end to end, angles solved per frame by two-bone IK from where the hoof must be,
diagonal-pair trot (fl+br, fr+bl, 58% stance) so a planted hoof is exactly on the ground; ribs, skull face, teeth, barding scraps, rider seated on the body.
`boss_death_the_pale_rider` is not in `bosses.txt` yet (add `boss_death_the_pale_rider - Idle:4,Walking_A:8,Attack:8,Hit_A:4,Death_A:8 ...` once its framing is chosen).
A rooted boss lists `Idle` and `Walking_A` (a sway) and no legs move; its walk strip is the sway. `review_bosses.py` makes the contact sheets.

## Home furniture and plaques (`home_models.py`)
One 3D model per piece in the town_models style, rendered by `build_town.py` (same camera and pixel density as the town
pictures; each model is shrunk by `SCALE` so it stands right beside a hero). Files: `realm/client/art/ui_home_<name>.png`,
`<name>` = the furniture's name lower-cased, spaces to `_`, no `'` (`home_chair`, `home_saints_screen` ...), and
`home_plaque_0..7` by boss. Rebuild: `HOME=1 python3 -I build_town.py -- <scratch dir> realm/client/art [home_chair ...]`
(bpy as a python module; about 3 s a picture). Contact sheet at 2x on the house floor with a hero: `home_sheet.py <art> <png>`.
The client (`HomeDraw.draw_thing` / `thing_picture`, `HomeMap.thing_art`) uses a file when it exists and the flat stand-in
when it does not; pictured things are drawn in the town's depth order (rugs under everything).

## Field ground props (`prop_models.py`)
Twelve dead-gothic ground props (3 dead trees, 2 rocks, gravestone, grave cross, broken pillar, broken wall, bone pile, thorn bush,
stump) in the field sites' style and pixel scale: ids `field_prop_<kind>`, written as `art/field_prop_<kind>.png`. Render on a
station with `script=render set=props` (or `PROPS=1 python3 -I build_town.py -- <scratch> <art dir> [id ...]`). The client
(`field/field_props.gd`) scatters them by a field-and-cell hash, off the sites and rings, and draws nothing for a kind without a file.

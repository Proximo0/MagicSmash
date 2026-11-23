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

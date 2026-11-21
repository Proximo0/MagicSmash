# Painted art: the drop-in folder

The game shows your paintings when it finds them. Where there is no file, it draws its own art instead.

## Where files go

The game looks in three places, in this order. The first file it finds wins:

1. an `art` folder next to the game program (next to `MagicSmash.exe`),
2. an `art` folder in the game's user folder (`user://art`),
3. `assets/art` inside the project (this one is built into the game).

So you can replace a picture without a new build: put the new file in the `art` folder next to the program.
Restart the game to see it.

Inside each of these, the pictures live in seven folders:

| Folder | Files | Named |
|---|---|---|
| `cards/monsters` | one painted monster card each | the monster key: `goblin`, `skeleton`, `slime`, `mslime`, `bat`, `orc`, `mage`, `lich`, `wraith`, `tome`, `gargoyle`, `priest` (also `cinderling`, `ten_of_swords`, kept for later) |
| `cards/tarot` | tarot cards without text | the card name in lower case, spaces as `_`: `the_magician`, `the_high_priestess`, `wheel_of_fortune`... all 22 Major Arcana; also `suit_cups`, `suit_swords`, `suit_wands`, `suit_pentacles` and `card_back` |
| `portraits/heroes` | hero portraits | `hero_<race>_<class>`: races `human elf dwarf orc`, classes `archer priest paladin knight mage` |
| `portraits/characters` | people of the tower | `shopkeeper`, `card_reader`, `bone_chandelier`, `ghost_writer`, `archlich`, `apprentice`; the tall version of each has `_tall` added |

| `sprites` | one still picture per figure or hub piece, **facing right** | heroes `hero_<race>_<class>` (races `human elf dwarf orc`, classes `knight mage archer priest paladin`), then `hero_<class>` for any race without its own, and `apprentice` (an apprentice shows its own picture, else its race and class's); monsters `enemy_<key>` for `goblin skeleton slime mslime bat orc mage lich wraith tome gargoyle priest bloat coffin guard cinderling censor hound shard swords` and `enemy_archlich`; bosses `boss_chandelier`, `boss_ghostwriter`; hub `hub_lectern`, `hub_mirror`, `hub_plinth` |
| `icons` | small marks, transparent | `spell_<key>`, `evo_<key>` for `arcane fire frost storm star rune bone candle cleave`; `passive_<key>` for `swift quick power regen magnet wisdom nova life justice lovers`; `class_<key>` (`mage knight archer priest paladin`); `race_<key>` (`human elf dwarf orc`); `deed_win`, `deed_slay`, `deed_time`, `deed_secret` |
| `scenes` | 480 x 270 backdrops | `builder`, `sheet`, `lobby`, `album`, `deeds` (also named for the shop and results screens: `shop`, `victory`, `defeat`) |

Files are PNG, for example `art/cards/monsters/goblin.png`.

### Figures, icons and scenes

- **Figures** are drawn at the picture's own pixel size, bottom centre on the figure's ground point, mirrored when it
  faces left, and moved by code: a small bob and lean while it walks, a slow breath when it stands. The hit flash
  (a white copy of the picture), an elite's gold tint and a boss's poses (shakes, tints, lift) all stay. Draw it
  facing right, feet at the bottom edge of the picture, no shadow. For the size, the pictures in `assets/art/sprites/`
  are the guide: a hero about 22 x 28, a small monster 14 x 18, a large one 20 x 27, the bosses 44 x 76 and 33 x 57. A hero keeps her seat's pip and ring.
- **Icons** are reduced (never enlarged) to the size a place shows them: 8 px in a fight HUD spell slot, 6 px for a
  passive, 16 px on a level-up card, 14 px in the builder's lists, 12 px for a deed mark. Paint them 16 x 16.
  An evolved spell shows `evo_<key>`, else its spell's picture.
- **Scenes** are dimmed (`Still.SCENE_DIM`) so the text over them reads; keep the middle quiet.
- A missing file leaves today's drawing exactly as it is.

## Size

Any size works. The game reduces each picture once, to the size it needs on screen, and draws it without
scaling. Paint large and clean; do not paint for the screen size.

## See what is there

Run this from the project folder:

    godot --headless --path . -s tools/art_list.gd

It prints every picture the game can show as `PRESENT` (with its size) or `MISSING`, and any file in the art
folders that no key wants (`STRAY`), which is usually a typo in a file name.

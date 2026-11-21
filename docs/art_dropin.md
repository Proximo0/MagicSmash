# Painted art: the drop-in folder

The game shows your paintings when it finds them. Where there is no file, it draws its own art instead.

## Where files go

The game looks in three places, in this order. The first file it finds wins:

1. an `art` folder next to the game program (next to `MagicSmash.exe`),
2. an `art` folder in the game's user folder (`user://art`),
3. `assets/art` inside the project (this one is built into the game).

So you can replace a picture without a new build: put the new file in the `art` folder next to the program.
Restart the game to see it.

Inside each of these, the pictures live in four folders:

| Folder | Files | Named |
|---|---|---|
| `cards/monsters` | one painted monster card each | the monster key: `goblin`, `skeleton`, `slime`, `mslime`, `bat`, `orc`, `mage`, `lich`, `wraith`, `tome`, `gargoyle`, `priest` (also `cinderling`, `ten_of_swords`, kept for later) |
| `cards/tarot` | tarot cards without text | the card name in lower case, spaces as `_`: `the_magician`, `the_high_priestess`, `wheel_of_fortune`... all 22 Major Arcana; also `suit_cups`, `suit_swords`, `suit_wands`, `suit_pentacles` and `card_back` |
| `portraits/heroes` | hero portraits | `hero_<race>_<class>`: races `human elf dwarf orc`, classes `archer priest paladin knight mage` |
| `portraits/characters` | people of the tower | `shopkeeper`, `card_reader`, `bone_chandelier`, `ghost_writer`, `archlich`, `apprentice`; the tall version of each has `_tall` added |

Files are PNG, for example `art/cards/monsters/goblin.png`.

## Size

Any size works. The game reduces each picture once, to the size it needs on screen, and draws it without
scaling. Paint large and clean; do not paint for the screen size.

## See what is there

Run this from the project folder:

    godot --headless --path . -s tools/art_list.gd

It prints every picture the game can show as `PRESENT` (with its size) or `MISSING`, and any file in the art
folders that no key wants (`STRAY`), which is usually a typo in a file name.

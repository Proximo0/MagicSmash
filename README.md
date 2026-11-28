# Four of Wands

The repository, the class names and the save folder keep the working title, Magic Smash.

**Hold the wizards' tower against Morvane's horde.** A co-op survivors-like for 1 to 4 wizards, on one
machine or over LAN (and Steam Remote Play Together). Built with **Godot 4.7.2** (GDScript, Compatibility
renderer) for a Steam release. There is no date yet: the game is finished first (`docs/release_plan.md`).

> When the Black Comet split the sky above Aldermoor, the dead stopped sleeping. Morvane the scholar read the
> ninth page of the Ashen Grimoire, and now his horde climbs the wizards' tower for the book that will make him
> a god. Four wizards remain. The cards are drawn. Hold the tower until the comet falls.

## A run

- **Fifteen minutes, three acts.** I: The Ossuary. II: The Burning Library. III: The Starless Sanctum. Each act
  has its own floor, light, ambient particles and music, and an act card when it begins.
- **The horde never stops.** Goblins, skeleton archers, slimes, bats, orc brutes and dark mages, then wraiths that
  phase out of reach, cursed tomes that dash, bone priests that raise the dead and gargoyles that sit as stone
  and swoop. Elites glow gold and pay out in chests.
- **Spells cast themselves.** Arcane Bolt, Fireball, Frost Fan, Chain Lightning and Starfall, each up to level 5
  and each with an evolution (Astral Lance, Thunderfire, Blizzard, Tempest, Comet Rain).
- **Level up by drawing a tarot card.** Grimoires (spells) and the Major Arcana (The Chariot, The Magician,
  Strength, Temperance, The Moon, The Hermit, The Tower, Judgement).
- **Gamble with run gold.** Rune altars cast three stones for one wizard; the fate card draws The Sun or Death
  for the whole party.
- **Morvane** rises as the Lich Lord on minutes 5 and 10 and descends as the Archlich at 15:00. Slay him to win.
- **Between runs**: crystals buy unlocks; loot found in a run is earned in play, never bought.

The title has the prologue (THE TALE), options (music, sound, window, screen shake) and a ouija board for
typing names and addresses.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Move | WASD | Left stick / D-pad | Left half of the screen |
| Cast | Arrow keys (8-way), or hold left mouse | Right stick (or X) | Right half of the screen |
| Nova bomb | Space / Shift / right mouse | RB, LB, RT or A | NOVA button |
| Pause | Esc / P | Start | Pause icon (top centre) |

In the lobby, any extra gamepad presses **A** to drop in as the next wizard.

## LAN play

1. One player picks **HOST LAN GAME**. The lobby shows their IP address.
2. Others pick **JOIN LAN GAME**. Hosts on the same network show up automatically
   (UDP broadcast on port 24681). If one doesn't appear, type the host's IP.
3. The host presses Enter/Start. Ports used: 24680 (game, UDP) and 24681 (discovery).
   Allow both through the firewall on the host.

The host runs the simulation; clients send input and render snapshots, so
every screen shows the same fight.

## Project layout

See `CLAUDE.md` for the commands and the code layout, and `docs/handoff.md` for the plan and the decisions
already made.

- `game/logic/`: the pure simulation (`World`, spells, upgrades, loot, gambling, the story in `Lore`), unit tested.
- `game/arena/`: renders snapshots of the world, effects and sound cues. `game/ui/`: title, lobby, options.
- `game/art/`: pixel art drawn from ASCII maps (`sprites.gd`, tarot cards in `tarot_art.gd`).
- `assets/audio/`: generated sound effects (`tools/gen_audio.py`) and music (`tools/music`, style guide in
  `tools/music/SOUNDTRACK.md`).

To change a track, edit `tools/music/songs/music_<name>.py`, render it with
`cd tools/music/songs && python3 music_<name>.py` (needs numpy and scipy), then run
`python3 tools/music/apply_loops.py` from the project root to refresh the loop points.

## Exporting

`tools/export_windows.sh` builds the Windows zip in `build/` (Godot 4.7.2 export templates needed). Steam
packaging is described in `docs/steam.md`.

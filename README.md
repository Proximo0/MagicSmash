# Magic Smash

A Smash TV style twin-stick arena shooter with wizards. Up to 4 players on one
machine (keyboard + gamepads) or over LAN. Built with **Godot 4.7.2** (GDScript),
so the same project exports to Windows, macOS, Linux, Android, iOS and Web.

## Play it

| Platform | File | Notes |
|---|---|---|
| Windows | `magic-smash-builds/MagicSmash-Windows.zip` | Unzip, run `MagicSmash.exe`. Windows SmartScreen may warn because the exe is unsigned. |
| Linux | `magic-smash-builds/MagicSmash-Linux.tar.gz` | Extract, `./MagicSmash.x86_64` |
| Android | `magic-smash-builds/MagicSmash-Android.apk` | Test build signed with a debug key, for sideloading on Android 7+. |

To edit: install Godot 4.7.2 (standard build, not .NET), choose *Import*, and pick
`project.godot` in this folder.

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

## What's in the slice

- **Spells**: Arcane Bolt (default, coloured per player), Fireball (splash),
  Frost Fan (5-way, slows), Chain Lightning (jumps between 5 enemies),
  Starfall (homing). Tomes grant a spell for 15 seconds. Also Haste boots,
  Rune Shield orbs, potions, coins and gems.
- **Nova**: a screen-shaking area blast, 2 per life.
- **Enemies**: Goblins (swarms), Bats (erratic), Slimes (split in two),
  Skeleton archers (keep distance, lead their shots), Orc brutes (wind up,
  then charge), Dark mages (teleport, then fire triple orbs).
- **Boss**: the Lich Lord every 5th wave, with radial bursts, spirals,
  aimed volleys, summons and a rage-phase teleport.
- **Scoring**: kill combos multiply score up to x5, with calls like "ARCANE CARNAGE!".
  The best score is saved.
- **Presentation**: animated title with drop-in logo, fireworks and lightning;
  additive-blended spell glow, particles, screen shake, hit flashes, hit-stop,
  decals, torch lighting, door portcullises, wave banners.
- **Soundtrack** (v0.2): four original pieces built on one shared "Ma-gic SMASH!"
  theme, rendered at 44.1 kHz stereo by the synth in `tools/music`.
  - Title: D minor, 108 bpm overture. An 8-bar night-sky intro plays once, then the rest loops.
  - Battle: E minor, 160 bpm. A pulse lead and a saw lead trade the tune over a galloping FM bass, power-chord guitars and a chip-layered kit.
  - Boss: C minor, 176 bpm "chip-metal" for the Lich Lord, with a choir and organ and a final key lift.
  - Game over: an 8-second jingle that turns the theme upside down.

  Every loop is seamless, because loop points are stored in each `.wav.import`.
  Sound effects are chiptune made by `tools/gen_audio.py`.

## Project layout

```
scripts/
  world.gd          game rules: players, spells, enemies, waves, boss (host only)
  arena.gd          match scene: rendering, effects, HUD, events, snapshots
  title.gd          title screen, lobby, LAN browser, how-to-play
  net.gd            ENet host/client, discovery, roster, input + snapshot RPCs
  fx.gd             particle, ring, lightning and popup-text system
  sprites.gd        pixel art as ASCII maps (edit these to change the art)
  pixel_font.gd     5x7 bitmap font
  arena_bg.gd       bakes the floor/wall backdrop
  player_input.gd   keyboard/mouse/gamepad/touch reading
  touch_controls.gd on-screen twin sticks
  autotest.gd       dev harness: `godot --path . -- --autotest[=wave]` plays with a bot and saves screenshots
assets/audio/       generated .wav files
tools/gen_audio.py  regenerates the sound effects (needs Python 3 + numpy)
tools/music/        the music synth (engine.py), one script per track in songs/,
                    the style guide SOUNDTRACK.md, and analysis reports in out/
```

To change a track, edit `tools/music/songs/music_<name>.py`. Re-render it with
`cd tools/music/songs && python3 music_<name>.py` (needs numpy and scipy).
Then run `python3 tools/music/apply_loops.py` from the project root to refresh the loop points.
Each render also writes a report and a piano-roll image to `tools/music/out/`.
Files ending in `__A`/`__B` are the competing drafts each final track was built from.

## Exporting

`export_presets.cfg` has Windows, Linux and Android presets. Install the 4.3
export templates (Editor > Manage Export Templates) and use Project > Export.
For a Play Store release, create your own release keystore and set
`package/signed=true` with it in the Android preset. Android LAN auto-discovery
can be blocked by some phones' Wi-Fi power saving, so joining by IP is the
fallback.

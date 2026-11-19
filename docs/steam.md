# Steam

What the game does with Steam, and what has to happen in Steamworks. Store actions, payments and uploads
are done by Curtis (or with his explicit go-ahead), never by an agent on its own.

## In the code

- `game/autoload/platform.gd` (`Platform`) is the only code that talks to Steam. It is a no-op unless:
  - the GodotSteam GDExtension is installed (the `Steam` singleton exists),
  - `config/steam.cfg` holds the App ID (`[steam]` then `app_id=1234560`), and
  - the run is not scripted (`Flags.is_scripted_run()`).
- With Remote Play Together only the host runs the game, so achievements go to the host's account.
- `game/logic/achievements.gd` (`Achievements`) holds the catalogue. `Achievements.earned` reads the run's
  `Results` record when the run ends; the arena calls `Platform.finish_run` on the host.
- Not in yet: the GodotSteam extension itself (needs the App ID to test).

## Store and library art

`xvfb-run -a godot --path . -s tools/capsules.gd -- --out=build/capsules` draws draft capsules at Steam's sizes
from the game's own sprites: header 920x430, small 462x174, main 1232x706, vertical 748x896, library capsule
600x900, library hero 3840x1240 (no logo, as Steam asks) and the transparent library logo 1280x720. Each is drawn
small and scaled up by a whole number, so the pixels stay crisp. They are drafts: a hand-made key art pass
would beat them, but they are usable as they are.

## Achievements for the Steamworks admin page

The API names must match exactly.

| API name | Name | Description |
| --- | --- | --- |
| ARCHLICH | THE LAST LICH | Slay the Archlich and win a run. |
| SOLO_WIN | LONE WIZARD | Win a run alone. |
| PARTY_WIN | FULL TOWER | Win a run with four wizards. |
| FLAWLESS | UNTOUCHED | Win a run without any wizard losing a life. |
| LICH | LICH BANE | Slay the Lich Lord. |
| TEN_MINUTES | HOLD THE TOWER | Survive for 10 minutes. |
| BLESSED | BLESSED BE | Bless the whole party at a team shrine. |
| CURSED | WORTH IT | Curse the whole party at a team shrine. |
| JACKPOT | JACKPOT | Hit the jackpot at a gamble shrine. |
| ULTRA | ULTRA RARE | Find ultra rare loot in a chest. |
| EVOLVE | EVOLUTION | Evolve a spell. |
| COMBO_200 | TOTAL SORCERY | Chain a 200 kill combo. |

## Steamworks checklist (Curtis)

1. The app: pay the Steam Direct fee and create the app. Steam asks for the fee at least 30 days before
   release; for Friday 18 Dec 2026 that was 18 Nov 2026, so check what Steam says for the date.
2. Send the App ID; it goes in `config/steam.cfg` and the GodotSteam setup follows.
3. Turn on Remote Play Together (and Remote Play on TV if wanted) in the app's Steamworks settings.
4. Add the achievements above, with icons.
5. The store page: description, tags, price ($4.99 to $6.99), screenshots, trailer, capsule art. It must be
   live at least 2 weeks before release (by 4 Dec 2026).
6. The build: a Windows depot from `tools/export_windows.sh`, uploaded with SteamPipe.

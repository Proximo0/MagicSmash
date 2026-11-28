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
| BLESSED | BLESSED BE | Draw The Sun for the whole party at the fate card. |
| CURSED | WORTH IT | Draw Death for the whole party at the fate card. |
| JACKPOT | JACKPOT | Hit the jackpot at a rune altar. |
| ULTRA | ULTRA RARE | Find ultra rare loot in a chest. |
| EVOLVE | EVOLUTION | Evolve a spell. |
| COMBO_200 | TOTAL SORCERY | Chain a 200 kill combo. |
| SEAL | THE KEY OF SOLOMON | Evolve Rune Circle into the Seal of Solomon. |
| OMENS | OMEN-PROOF | Survive all three omens. |

The first 14 rows are the Steam list. The Book of Deeds (the Sanctum's lectern) adds the rows below to the same
catalogue (`Achievements.LIST`, 53 in all): `Platform.finish_run` sends every earned name, and Steam ignores a name
the admin page does not have, so add these there only if they should be Steam achievements too. A secret deed shows
as ??? in the Book until earned (and should be a hidden achievement on Steam). Crystals are paid once in the game.

| API name | Name | Description | Crystals | Secret |
| --- | --- | --- | --- | --- |
| WIN_MAGE | THE MAGICIAN | Win a run with a Mage among the players. | 10 |  |
| WIN_KNIGHT | THE CHARIOT | Win a run with a Knight among the players. | 10 |  |
| WIN_ARCHER | THE HERMIT'S AIM | Win a run with an Archer among the players. | 10 |  |
| WIN_PRIEST | THE HIEROPHANT | Win a run with a Priest among the players. | 10 |  |
| WIN_PALADIN | STRENGTH | Win a run with a Paladin among the players. | 10 |  |
| WIN_HUMAN | ALL TOO HUMAN | Win a run with a Human among the players. | 10 |  |
| WIN_ELF | LONG IN THE TOOTH | Win a run with an Elf among the players. | 10 |  |
| WIN_DWARF | DEEP AND STUBBORN | Win a run with a Dwarf among the players. | 10 |  |
| WIN_ORC | POLITE FURY | Win a run with an Orc among the players. | 10 |  |
| TRINITY | BALANCED READING | Win a run with a tank, a healer and a ranged hero among the players. | 20 |  |
| EVO_ARCANE | STRAIGHT AND NARROW | Evolve Arcane Bolt into Astral Lance. | 15 |  |
| EVO_FIRE | FIRE AND LIGHTNING | Evolve Fireball into Thunderfire. | 15 |  |
| EVO_FROST | WHITEOUT | Evolve Frost Fan into Blizzard. | 15 |  |
| EVO_STORM | THE PERFECT STORM | Evolve Chain Lightning into Tempest. | 15 |  |
| EVO_STAR | THE STARS ALIGN | Evolve Starfall into Comet Rain. | 15 |  |
| EVO_BONE | TO THE MARROW | Evolve Bone Spear into Ossuary Lance. | 15 |  |
| EVO_CANDLE | LET THERE BE MORE LIGHT | Evolve Vigil Candle into Consecration. | 15 |  |
| BOSS_CHANDELIER | BRING DOWN THE HOUSE | Slay the Bone Chandelier. | 15 |  |
| BOSS_GHOSTWRITER | THE LAST WORD | Slay the Ghost Writer. | 15 |  |
| WIN_ARCHMAGE | THE UPPER SHELF | Win a run at Archmage. | 20 |  |
| WIN_SEAL_1 | FIRST SEAL BROKEN | Win a run at Seal I. | 25 |  |
| WIN_SEAL_2 | SECOND SEAL BROKEN | Win a run at Seal II. | 30 |  |
| WIN_SEAL_3 | THIRD SEAL BROKEN | Win a run at Seal III. | 30 |  |
| WIN_SEAL_4 | FOURTH SEAL BROKEN | Win a run at Seal IV. | 35 |  |
| WIN_SEAL_5 | FIFTH SEAL BROKEN | Win a run at Seal V. | 40 |  |
| WIN_SEAL_6 | SIXTH SEAL BROKEN | Win a run at Seal VI. | 45 |  |
| WIN_SEAL_7 | SEVENTH SEAL BROKEN | Win a run at Seal VII. | 50 |  |
| WIN_SEAL_8 | THE LAST SEAL | Win a run at Seal VIII. | 50 | yes |
| REVIVE_3 | SECOND WIND | Raise 3 fallen allies in one run. | 10 |  |
| REVIVE_25 | UNIONISED DEAD | Raise 25 fallen allies over all your runs. | 20 |  |
| KILLS_1K | BODY COUNT | Slay 1,000 foes over all your runs. | 10 |  |
| KILLS_10K | MASS GRAVE | Slay 10,000 foes over all your runs. | 25 |  |
| KILLS_100K | THE LONG HARVEST | Slay 100,000 foes over all your runs. | 50 |  |
| HERO_10 | JOURNEYMAN | Raise a hero to class level 10. | 15 |  |
| ALL_CARDS | THE FULL DECK | Collect every monster card. | 40 |  |
| ALL_SECRETS | NOTHING LEFT UNSAID | Find every secret in the game. | 30 | yes |
| APPRENTICES | THE MASTER'S HAND | Win a run with only apprentices beside you. | 20 | yes |
| FAST_WIN | ON SCHEDULE | Win a run with four heroes before 16:30. | 30 |  |
| EVO_CLEAVE | WIDDERSHINS | Evolve Cleave into Whirlwind. | 15 |  |
| FIRST_CARD | THE QUERENT | Find your first monster card. | 25 |  |

## Steamworks checklist (Curtis)

1. The app: pay the Steam Direct fee and create the app. Steam asks for the fee at least 30 days before
   release. Nothing is due now: Steam is stage 7 of `docs/release_plan.md`, and there is no release date yet.
2. Send the App ID; it goes in `config/steam.cfg` and the GodotSteam setup follows.
3. Turn on Remote Play Together (and Remote Play on TV if wanted) in the app's Steamworks settings.
4. Add the achievements above, with icons: `docs/achievements/<api name>.png` (achieved) and
   `<api name>_locked.png` (unachieved), 64x64, drawn from the tarot emblems by
   `godot --headless --path . -s tools/achievement_icons.gd`.
5. The store page: description, tags, price ($4.99 to $6.99), screenshots, trailer, capsule art. It must be
   live at least 2 weeks before release.
6. The build: a Windows depot from `tools/export_windows.sh`, uploaded with SteamPipe.

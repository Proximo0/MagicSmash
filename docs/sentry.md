# Crash reports (Sentry)

The game reports crashes and script errors to Sentry, so a bug on a player's machine arrives with its stack trace.
Sentry's own guide for the engine: https://docs.sentry.io/platforms/godot/

## In the code

- `game/autoload/crash.gd` (`Crash`) is the only code that talks to Sentry. It is a no-op unless:
  - the sentry-godot addon is installed (the `SentrySDK` singleton exists),
  - `config/sentry_credentials.cfg` holds the DSN,
  - the run is not scripted (`Flags.is_scripted_run()`) and not in the editor, and
  - the player has CRASH REPORTS on in the options (on by default; `Settings.crash_reports`).
- The addon is not in git (87 MB of native libraries). `tools/fetch_sentry.sh` downloads the pinned version
  (2.5.1, checksum checked) into the git-ignored `addons/sentry`. `tools/export_windows.sh` runs it, so every
  Windows build has it; the summary line ends `sentry=yes`. CI has no addon and no DSN, so nothing starts there.
- `project.godot` turns the addon's auto-start off (`[sentry] options/auto_init=false`): `Crash` starts it by hand,
  so the DSN can stay out of `project.godot` and the options can switch it off.

## The DSN

It names the Sentry project and ships inside builds, but it never goes into git, docs or memory. Keep it in the
git-ignored `config/sentry_credentials.cfg`:

```
[sentry]
dsn="https://<key>@<org>.ingest.us.sentry.io/<project>"
```

The game looks in `res://config/`, then next to the executable, then `user://`. The export script copies the file
next to the exe.

## What a report holds

- The game version (`magic-smash@<G.VERSION>`), `production` or `debug`, the platform and its hardware.
- The GDScript stack trace of a script error, or the native crash dump, and the game's log file.
- The run's `seed` and `wizards` tags, so `godot --path . -- --seed=<seed> --players=<wizards>` replays the spawns.
- No name and no IP address (`send_default_pii` stays off).

## Checking a build

Run `Send-Test-Crash-Report.bat` next to the exe (or start the game with `-- --sentry-test`). One message,
"Magic Smash <version>: test report", shows up under Issues in Sentry within a minute.

## Before the store page goes live

- Say in the store page or the privacy note that the game sends anonymous crash reports and that the options turn
  them off.
- Godot's stock export templates have no debug symbols, so a native engine crash shows addresses, not function
  names. Script errors, which are nearly all of our bugs, show full traces.

# Stations: spare computers as a relay

A station runs `tools/station/station.sh` with no Claude on it. On every new commit on main it runs its jobs and
pushes a few lines to the branch `station-results` (`<machine>.txt`). `tools/station/read.sh` prints them all and
ends with `STATIONS n= failed= stale=`; a session reads that instead of running the jobs.

## Who runs what
`tools/station/roles.txt` holds one line per machine (jobs, optional `--after=<station>` to wait for another station's
PASS, optional `--p95=<ms>` frame limit). Stations run side by side and restart themselves when that file changes, so
a new role is a commit. Start every station as `station.sh --watch <any job>`; the file wins.

| Machine | Job | Why |
|---|---|---|
| Ubuntu HP ENVY | `realm` | Horde & Hearth: core, server and store checks, the crash fuzz |
| MSI (fast, RTX 5050) | `realm` | the same on Windows; later the field client's frame time and the test host |
| DESKTOP-BENMA68 laptop (Radeon 610M) | `realm` | the same checks; later the field client's frame test (low end) |
| Heatherspc (Celeron N4100, UHD 600) | `realm` | the same checks on the slowest processor; later the frame test below minimum spec, recorded only |

Four of Wands is stopped (21 Nov 2026), so no station runs `boss`, `checks`, `frames` or `golden`; the jobs remain for
the day they are wanted. A job is skipped for a merge that changed nothing it tests (`realm` tests `realm/`; the Godot
jobs test everything except `realm/`, `docs/`, `.github/` and the stations), so the stations do no work for docs or art.

`realm` needs Rust on the station (`cargo` on PATH, from rustup; on Windows also the Visual Studio C++ build tools,
which the store's bundled SQLite needs). A station without it reports `JOB realm FAIL cargo is not installed` (a failure, not a pass). `deep` between merges runs a store crash fuzz, a field bench and a time-boxed soak (STATION_DEEP_SOAK_SECS, default 900), and the nightly ops rehearsal. Merge checks come first: between deep steps, and every STATION_DEEP_POLL seconds (default 60) inside a step, the station fetches origin/main, and when a new commit changed something its jobs test it kills the step, abandons the pass (local line "interrupted", never a FAIL, never published) and runs the merge jobs, so a merge waits at most about a minute plus its build. A deep result is published to `<machine>-deep.txt` only when it fails, when it is the first after a merge, or at most once an hour (that line carries `passes=`, `interrupted=` and `seeds=` counted since the last publish); a deep FAIL also appends to `<machine>-failures.txt` at once. A machine with no cargo sleeps STATION_POLL seconds between tries and publishes a SKIP line at most hourly. A report older than 6 hours is STALE.

## Set up a station
1. Git with a shell (Linux: any; Windows: full Git for Windows, whose Git Bash runs these scripts) and Godot 4.7.2;
   set `GODOT` if it is not on PATH.
2. A clone used by the station only. Push access through a deploy key for this repository (Settings > Deploy keys,
   allow write), never a personal sign-in.
   On Windows a portable Git works (PortableGit from git-for-windows, no admin); the Startup folder can start it.
3. Start the command above at boot or logon (Linux: a systemd user service or `@reboot` in crontab; Windows: Task
   Scheduler, "at log on", running Git Bash). `STATION_NAME` overrides the host name.

## When a stage fails
The fix happens on the machine that failed, where the failure reproduces: start one helper there with the failed
report as its whole brief (agent type `worker`), let it push a branch, then stop it. One helper at a time.
`STATION_ON_FAIL` can run a command with the report on stdin; leave it unset unless the owner asks for automatic wake-ups.

Crowd screenshots: once in 20 hours the `frames` job also saves the battle at zoom 16, 4 and 2 and pushes them to
the results branch as `shots/<machine>-zoom<N>.png` (newest only). `STATION_SHOTS=0` turns it off.

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
| Ubuntu HP ENVY | `checks golden` | full check_all, did the game change |
| MSI (fast, RTX 5050) | `boss frames` | five bot runs to the Archlich, frame time on real graphics |
| DESKTOP-BENMA68 laptop (Radeon 610M) | `frames` | low-end frame time |
| Heatherspc (Celeron N4100, UHD 600) | `frames --p95=0` | below minimum spec (p95 81 ms): recorded, never fails |

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

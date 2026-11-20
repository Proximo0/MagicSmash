# Stations: spare computers as a relay

A station runs `tools/station/station.sh` with no Claude on it. On every new commit on main it runs its jobs and
pushes a few lines to the branch `station-results` (`<machine>.txt`). `tools/station/read.sh` prints them all and
ends with `STATIONS n= failed= stale=`; a session reads that instead of running the jobs.

## The relay (each stage waits for the one before it to PASS the same commit)
| Stage | Machine | Command |
|---|---|---|
| 1 | Ubuntu HP ENVY | `station.sh --watch checks golden` |
| 2 | Heatherspc | `station.sh --watch --after=<stage 1 name> boss` |
| 3 | DESKTOP-BENMA68 laptop | `station.sh --watch --after=<stage 2 name> frames` |
| 4 | MSI | `station.sh --watch --after=<stage 3 name> frames` |

A failed stage stops the line: later stages report `STATION HELD`.

## Set up a station
1. Git with a shell (Linux: any; Windows: full Git for Windows, whose Git Bash runs these scripts) and Godot 4.7.2;
   set `GODOT` if it is not on PATH.
2. A clone used by the station only. Push access through a deploy key for this repository (Settings > Deploy keys,
   allow write), never a personal sign-in.
3. Start the command above at boot or logon (Linux: a systemd user service or `@reboot` in crontab; Windows: Task
   Scheduler, "at log on", running Git Bash). `STATION_NAME` overrides the host name.

## When a stage fails
The fix happens on the machine that failed, where the failure reproduces: start one helper there with the failed
report as its whole brief (agent type `worker`), let it push a branch, then stop it. One helper at a time.
`STATION_ON_FAIL` can run a command with the report on stdin; leave it unset unless the owner asks for automatic wake-ups.

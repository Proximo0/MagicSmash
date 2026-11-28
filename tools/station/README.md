# Stations: spare computers as a relay

A station runs `tools/station/station.sh` with no Claude on it. On every new commit on main it runs its jobs and
pushes a few lines to the branch `station-results` (`<machine>.txt`). `tools/station/read.sh` prints them all and
ends with `STATIONS n= failed= stale=`; a session reads that instead of running the jobs.

To watch every PC live, run `tools/station/monitor.sh` (on Windows double-click `tools\station\monitor.cmd`): per PC
it shows OK/LATE/DOWN, lanes, free RAM, the last skip reason and the jobs held, then recent failures. Read-only.

## Who runs what
`tools/station/roles.txt` holds one line per machine (jobs, optional `--after=<station>` to wait for another station's
PASS, optional `--p95=<ms>` frame limit). Stations run side by side and restart themselves when that file changes, so
a new role is a commit. Start every station as `station.sh --watch <any job>`; the file wins.

| Machine | Jobs | Why |
|---|---|---|
| Ubuntu HP ENVY | `checks boss golden queue` | Four of Wands on Linux: every check, five bot runs to the Archlich, and whether a merge changed how the game plays |
| MSI (fast, RTX 5050) | `checks boss queue` | the same on Windows with cores to spare; ten lanes of queue jobs, and the art generation |
| DESKTOP-BENMA68 laptop (Radeon 610M) | `checks queue` | the checks on a low-end graphics card |
| Heatherspc (Celeron N4100, UHD 600) | `checks queue` | the checks on the slowest processor, below minimum spec |

Four of Wands is the game in work again (27 Nov 2026). Horde & Hearth is shelved (`docs/realm/SHELVED.md`), so no station
runs `realm`, `frames`, `deep`, `soak`, `world`, `economy`, `ops` or `balance`; those jobs remain for the day they are wanted. The `world` merge job is a short soak (STATION_WORLD_SECS, default 600); the 7200 s proof is the queue's shell job `script=worldlong` (`secs=` sets the length), so a merge never holds a station for hours. A station that was busy while several merges landed tests only the newest main once (it fetches `origin/main`, diffs against the last commit it tested, and so covers every merge in between); a running merge job is not cut short by a newer commit, which is why none runs for hours. A job is skipped for a merge that changed nothing it tests (`realm` tests `realm/`; the Godot
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
   Linux launcher: `tools/station/start_station.sh` (one copy by flock, restarts the station 60 s after it exits, log
   `~/station_restarts.log`; name from `STATION_NAME` or `~/.station_name`). The queue job `script=stationstart` adds its
   `@reboot` crontab line (Windows: `start_station.cmd`); `frames` at boot has no desktop, so it runs under xvfb-run.

## Four of Wands jobs
Queue `shell` jobs that test the Four of Wands game (repo root), so the PCs have work between merges. They run Godot from "the tree", never
from the work tree a merge is about to change: `<git dir>/station_wands/<key>/`, an imported copy of `git archive HEAD` of the game's paths
(`project.godot export_presets.cfg icon.svg* game assets tools tests`, and `addons` once it exists; `tools/station/` left out). The key is 12 hex digits of
their content, so a commit that only changes docs, `realm/`, `.github/` or `tools/station/` keeps the tree. A new key builds a new tree (one
builder at a time, a `mkdir` lock; others wait up to 20 min; a lock over 45 min old is taken over; about a minute to import, about 130 MB a
tree). Trees of other keys unused for 5 hours go (the longest job is 4). Helper: `wands_lib.sh` (`wands_key`, `wands_tree`, `wands_env` =
private user data, never the PC's save; on Windows the graphics driver's own shader folder stays the PC's). The jobs start only Godot (each
carries the line `# station-sac: ok`), so the Smart App Control laptop runs them and a queue of only these builds nothing (`q_build_all`).
A merge no longer empties the lanes: `merge_job` keeps them filled while the merge's own jobs run. Quick test, no Godot:
`bash tools/station/wands_test.sh` (`WANDS ok`).
- `wandsrun runs=N wizards=1..4 seal=N persona=NAME limit=SECS`: N whole bot runs (`tools/full_run.gd`), seed `$STATION_JOB_SEED`+i, wizards `1 + seed % 4`
  unless given. INFO with won/lost; FAIL on no `FULL_RUN` line, an engine script error or UNFINISHED. Rows in `wandsrun.csv`.
- `wandscareer careers=N party=a.knight,b.mage hero=NAME maxruns=N minutes=N limit=SECS`: `tools/tool.gd career --until=win`; write `.` for `:` in a party.
  Output in `career_<seed>.txt`; FAIL without a `CAREER` line. Its own `limit` (default 3000 s) must stay under the job's `timeout_s`.
  Always give `minutes=25`: the tool's own 18-minute cap ends a run inside the Archlich fight and books a win as a loss (second read, 27 Nov 2026).
- `wandsframes wave=N players=1..4 limit=SECS`: the real game drawn (`--autotest=N --players=P --perf`, under `xvfb-run` on Linux without a display):
  GPU name and the `PERF frames=` fields; PERF lines in `frames_<seed>.txt`. A game window opens on that PC for about half a minute, and the
  numbers are taken under whatever else the PC is doing, so name the PC (`needs=laptop`) and read them as an upper bound.
```
tools/station/queue.sh add kind=shell args="script=wandsrun runs=2" repeat=forever timeout_s=5400 priority=5 max_lanes=16 max_per_machine=8 needs_free_mb=600
tools/station/queue.sh add kind=shell args="script=wandscareer careers=2 minutes=25 limit=6900" repeat=forever timeout_s=7200 priority=5 max_lanes=8 max_per_machine=3 needs_free_mb=600
tools/station/queue.sh add kind=shell args="script=wandsframes wave=15 players=4" needs=laptop repeat=forever every_s=21600 timeout_s=1800 priority=6 needs_free_mb=1500 needs_gpu_idle=1
```
A new kind of job goes in once first (`repeat=once`), is read, and only then goes in as `forever`. Never `queue.sh fill-week`: it loads Horde & Hearth's jobs.

## Taking a machine out of work
A line in `roles.txt` that starts with `stopped:` and then names machines (or `all`) ends those stations: each ends the jobs still running
in its lanes, publishes `STATION STOPPED`, ends its launcher (every `cmd.exe` whose command line holds `start_station` or `run_station`) and
exits. To bring a machine back: take its name off that line (or delete the line), merge, then start its launcher once on the PC, or restart
the PC. A started station whose checkout still has the line asks origin/main on every start and runs when main no longer names it (until
27 Nov 2026 it asked only when its last stop was 30 minutes old, and three PCs started minutes after their last stop stopped again). A
station started while main still names it ends itself and its launcher, so a helper that waits for the merge must not have `start_station`
or `run_station` in its name or command line, and it must match the line only at the start of a line (`^stopped:`), never inside a comment.

## When a stage fails
The fix happens on the machine that failed, where the failure reproduces: start one helper there with the failed
report as its whole brief (agent type `worker`), let it push a branch, then stop it. One helper at a time.
`STATION_ON_FAIL` can run a command with the report on stdin; leave it unset unless the owner asks for automatic wake-ups.

Crowd screenshots: once in 20 hours the `frames` job also saves the battle at zoom 16, 4 and 2 and pushes them to
the results branch as `shots/<machine>-zoom<N>.png` (newest only). `STATION_SHOTS=0` turns it off.

## The work queue: the machines work after the lead is switched off
Between merges a station used to repeat the same `deep` pass. With the role word `queue` (all four machines) it first takes
the next job from a queue the lead loaded in advance, and runs `deep` only when the queue has nothing for it. A merge still
comes first, but a merge no longer throws away a long job: a queue job with `timeout_s` above `STATION_QUEUE_KILL_MAX_S` (default 900)
runs to its end and the station takes the new commit afterwards (audit 22 Nov: kills cost 21% of machine hours); a short job is cut by a
merge, its claim released, and picked up again later. Kinds that repeat with fresh seeds (fuzz, soak, bench, balance, economy, shell
wirefuzz) are stopped by a merge at any length: one INFO line `stopped for a merge after N s`, no done record, the job runs again.
A claim a machine left itself (crash, reboot) never blocks that machine.

Watch (`q_watch` in `queue_lib.sh`): a job whose output has not grown for `silent_s` seconds (job field; 0 = off; default 900, balance and
fuzz 1800, a shell script that builds 3600, render/blender/godot scripts, package and frames off) is stopped and FAILs `silent for N s`
with its last 3 lines. `queue.sh stop <id>` writes `stop/<id>` naming the runs live now; their lanes, on any machine, stop them within
about a minute (INFO `stopped by the lead`), the job stays queued (`cancel` removes it and the stop file). Circuit breaker: 3 FAILs in a
row of one job on one commit (all machines, from the done records) give `SKIP queue job <id>: paused: 3 failures on <commit>` until main moves.

Resource gate: before a job starts the station needs free RAM (job field `needs_free_mb`, default by kind: fuzz 512, soak/balance/package 1024,
bench/economy 2048, frames 3072, shell 256; `0` = no check; the test override is `STATION_FREE_MB`) and, for `frames` and `needs=gpu` jobs
(`needs_gpu_idle=1`), no art generation RUNNING (`HH_ART_STATUS`, default `D:\projects\hh_art\status.txt`). A short job prints
`SKIP queue job <id>: ...` (once per half hour) and the station takes another job or falls to `deep` (which has the same RAM gate,
`STATION_DEEP_FREE_MB`, default 2048). A GPU job is stopped, claim released, when art starts. `queue.sh add ... needs_free_mb=4096 needs_gpu_idle=1`.

Reports: a failed job keeps up to 1500 characters of its last lines; a failed `deep` build keeps the last 40 lines of the build; a job that
prints nothing reports its exit code, stderr and last output. A finished report whose push fails is kept (`station_last.unpushed` in `.git`)
and only the push is retried every poll; the jobs are not run again.

Lanes (24 Nov 2026: "all four at max"): a watching station runs several queue jobs at once, one per lane. Lanes per machine: the line
`lanes: <machine> N` in `roles.txt` (msi 10, laptop 4, heatherspc 3, ubuntu 3), else `STATION_LANES`, else cores/2 capped at RAM/1.5 GB.
`simscale: <machine> N` in `roles.txt` widens the horde sims' time budget in that machine's `checks` (default 4; heatherspc 20: a Windows
station times a step with a stopwatch beside its queue jobs). `checks` runs inside `tools/private_save.sh`, so no robot run reads the PC's own save.
The station loop stays free while lanes work: it tests each merge as it lands, then builds the commit ONCE (realm and the store, the same
command as the merge jobs) and copies the programs to `.git/station_bin/<commit>/`; lanes run from that copy (`STATION_BIN` for shell
scripts), so no lane builds and no build replaces a program a lane runs; while the build runs no job that needs our programs starts.
A lane claims `claims/<id>.<machine>-<lane>`; a lane claim is live while that lane's process runs (else this machine retakes it) and for
others until 2 x timeout_s. A forever job runs in at most `max_lanes` lanes at once (all machines; default 1) and `max_per_machine` on one;
a once job runs once. Every job gets its own TMPDIR inside its work dir; `wirefuzz` builds in `~/station-targets/wirefuzz`. A lane whose job
FAILs within a minute rests STATION_QUEUE_FAIL_SLEEP. RAM gate per lane: free RAM less what lanes started in the last 5 minutes asked for.
`deep` runs only when every lane is idle. Heartbeat: `lanes_busy=B/N`; hours: `busy_h` (any lane busy), `lane_h` (lane-hours), `lanes=N`.
Smart App Control: a Windows PC where it is On (read only, `Get-MpComputerStatus`; or the build's test start is refused, 126) skips every
job that runs programs built here (all built-in kinds, `frames` for realm-server and the realm_godot DLL, and shell scripts that name
`cargo`, `realm/target` or `STATION_BIN` unless marked `# station-sac: ok`) with one SKIP line per half hour, never a FAIL; merge jobs
SKIP too. Its lanes take shell jobs that run signed programs (Blender, Godot, Python). No security setting is touched.

LAN rehearsal: players wait up to 900 s for a FRESH host file (the host rewrites `lan/host.txt` with `updated_epoch` every 90 s and writes
`state=ended` when killed); a host that served and saw no login reports `FAIL lanhost: no player connected`. A host job is long, so a merge no longer kills it.

CI overlap: CI (`realm.yml`) already runs `realm/check.sh`, the store check and the client on every push. The role flag `--ci-covered`
(`msi: realm queue deep --ci-covered`) makes the `realm` job SKIP unless the merge changed a path CI does not cover on Windows
(`STATION_REALM_OWN_PATHS`, an extended regex; default `.ps1`, `.cmd`, `.bat`, `realm/ops/host/`, `start_station`). No machine has it yet:
the owner decides which one.

How it is stored (git branch `station-queue`, written and read without a work tree, like `publish`; never main):
`queue/<id>.job` (one job: `kind args needs priority repeat timeout_s added`, optional `every_s` = at least that many seconds
between two runs of a forever job, `max_lanes`, `max_per_machine`, `own_bin`), `claims/<id>.<machine>-<lane>` and `done/<id>.<machine>`. A station claims a job by pushing the
claim file in a commit; the push is the lock, and a rejected push means somebody else won: refetch and pick again. A claim with
no done after `timeout_s` x 2 is stale and may be taken over. Results go to `station-results` as `work/<id>/<machine>.txt`
(one line a pass; `repeat=forever` jobs never run out, take a fresh seed every pass and append a line) plus artifacts
(`work/<id>/art/<machine>-<name>`, CSV and the like, at most 2 MB a job), then the done record is written. Order: finite
(`once`) jobs first by priority 9 down to 0; then the forever jobs, the one run longest ago first, a higher priority counting as
an hour of age, so no sweep starves another. `needs` is `any`, `gpu` (Windows, or a desktop session), `linux`, `windows` or a
machine name. Each station also appends `<busy hours> <idle hours>` per day to `<machine>-hours.txt` (idleness is measurable).

Kinds and args (a job file never carries a command: args are `name=value` words of letters, digits, `, . - _` only, checked on
`add` and again by the station; anything else is refused with a line; an unknown kind is skipped with a line):

| kind | runs | args |
|---|---|---|
| `fuzz` | `realm-store fuzz` | `seeds=A-B` (once: every seed; forever: one random in the range) `ops= kills=` |
| `soak` | `realm-soak` | `secs= bots= seeds=` |
| `bench` | `realm-server --bench`, one CSV row per field x threads x size | `fields=0,1 threads=1,2 monsters=5000,20000 bots= ticks= seeds=` |
| `balance` | `realm-loadtest balance career` (INFO) | `seeds=N` (cohorts) `per= minutes= fast= hours=` |
| `economy` | `realm-economy` per seed (INFO) | `seeds=A-B days= bots=` |
| `frames` | the `frames` job's client frame test | `zooms=16,4 secs=` (needs a GPU or desktop) |
| `package` | server and client into `~/station-packages/<date>-<target>-<commit>` with `HASH.txt` | `target=linux\|windows` |
| `shell` | `tools/station/jobs/<name>.sh` | `script=<name>` and words passed to it |

Shell jobs shipped: `selftest`, `power`, `worldlong` (the 7200 s world soak, `secs=`) and `wirefuzz` (the wire decoder fuzz tests with a fresh seed and `iters=` iterations, default 2,000,000; queue it forever with
`queue.sh add kind=shell args="script=wirefuzz iters=2000000" repeat=forever every_s=21600 timeout_s=7200 priority=3`).

Add a kind: for a script, nothing in `station.sh`: commit `tools/station/jobs/<name>.sh` (see `jobs/selftest.sh`: last line is
the summary starting PASS, FAIL or INFO, exit non-zero is FAIL, files written to `$STATION_JOB_ART` are published, `$STATION_JOB_SEED`
is a fresh seed) and queue `kind=shell args=script=<name>`. A job whose script is not on the station's checkout is skipped
with a line. For a built-in kind write a `qk_<kind>` function in `queue_lib.sh` and add the name to `Q_KINDS` and `q_exec`.

The lead's tool, `tools/station/queue.sh` (run from any clone): `add kind=.. args=".." [needs=..] [priority=..] [repeat=..]
[timeout_s=..] [every_s=..] [max_lanes=..] [max_per_machine=..] [silent_s=..]`, `list`, `cancel <id>`, `stop <id>`, `fill-week` or `fill-month` (the same: forever
jobs run until cancelled. Per machine with its own seed ranges: economy 7 (2 lanes), soak 6 (3), worldlong 6, bench 5, fuzz 4 (4 lanes),
wirefuzz 4; one balance sweep 7, a daily Linux and Windows package 8, frames on the GPU machines every 12 hours 8; priorities 9 = once-off
lead jobs, 3 = lan play. Safe to repeat: existing jobs get the current priority and lane limits),
`step` (run one job here now) and `digest [--since=DAYS]`.

**The owner or whoever returns reads one command: `tools/station/queue.sh digest`** (add `--since=3`). It prints jobs done per machine,
hours busy versus idle (and up-time from heartbeats), every FAIL with its seed and detail, the newest artifacts, and ends with
`DIGEST jobs= fail= busy_h= idle_h=`. Load the week with `tools/station/queue.sh fill-week` before the lead stops.

Test: `bash tools/station/queue_test.sh` (two machines, a bare repository, stubbed jobs; prints `QUEUE ok`).
Known limits: `balance` has no class or job filter and `balance`/`economy` print tables, not CSV, so their artifact is the sweep's own summary/CSV
row; a `balance` pass cannot take a seed offset, only a cohort count.

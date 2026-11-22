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

## The work queue: the machines work after the lead is switched off
Between merges a station used to repeat the same `deep` pass. With the role word `queue` (all four machines) it first takes
the next job from a queue the lead loaded in advance, and runs `deep` only when the queue has nothing for it. A merge still
comes first: a long job is killed when a merge lands, its claim is released, and the job is picked up again later.

How it is stored (git branch `station-queue`, written and read without a work tree, like `publish`; never main):
`queue/<id>.job` (one job: `kind args needs priority repeat timeout_s added`, optional `every_s` = at least that many seconds
between two runs of a forever job), `claims/<id>.<machine>` and `done/<id>.<machine>`. A station claims a job by pushing the
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

Add a kind: for a script, nothing in `station.sh`: commit `tools/station/jobs/<name>.sh` (see `jobs/selftest.sh`: last line is
the summary starting PASS, FAIL or INFO, exit non-zero is FAIL, files written to `$STATION_JOB_ART` are published, `$STATION_JOB_SEED`
is a fresh seed) and queue `kind=shell args=script=<name>`. A job whose script is not on the station's checkout is skipped
with a line. For a built-in kind write a `qk_<kind>` function in `queue_lib.sh` and add the name to `Q_KINDS` and `q_exec`.

The lead's tool, `tools/station/queue.sh` (run from any clone): `add kind=.. args=".." [needs=..] [priority=..] [repeat=..]
[timeout_s=..] [every_s=..]`, `list`, `cancel <id>`, `fill-week` (forever fuzz, soak, bench, economy per machine with their own
seed ranges, one balance sweep, a daily Linux and Windows package, frames on the GPU machines every 12 hours; safe to repeat),
`step` (run one job here now) and `digest [--since=DAYS]`.

**The owner or whoever returns reads one command: `tools/station/queue.sh digest`** (add `--since=3`). It prints jobs done per machine,
hours busy versus idle (and up-time from heartbeats), every FAIL with its seed and detail, the newest artifacts, and ends with
`DIGEST jobs= fail= busy_h= idle_h=`. Load the week with `tools/station/queue.sh fill-week` before the lead stops.

Test: `bash tools/station/queue_test.sh` (two machines, a bare repository, stubbed jobs; prints `QUEUE ok`).
Known limits: `balance` has no class or job filter and `balance`/`economy` print tables, not CSV, so their artifact is the sweep's own summary/CSV
row; a `balance` pass cannot take a seed offset, only a cohort count.

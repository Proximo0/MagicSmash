# Running the realm (job O1)

What exists: `realm/ops/` (crate `realm-ops`: the hooks the gateway and hosts call, the watchers, and the `realm-ops`
program), `realm/ops/host/` (scripts and the systemd unit that go in the host package), small hooks in
`realm/gateway` and `realm/server`, the station word `ops`, and a Windows CI step. Every setting is in
`realm/ops/src/config.rs` (`SETTINGS`, with its default and its explanation); `realm-ops config-template` prints the file,
and the package ships it as `ops.conf`. This page is the why and the how.

## The host package (one folder)

```
ops.conf              every setting, documented       start.cmd/.ps1 stop.cmd/.ps1 restart.cmd ops.cmd/.ps1 install-task.ps1
releases/V/           realm-gateway realm-server realm-ops realm-store release.txt (version=, schema=)
current  previous     text files naming a release     realm.service (systemd)  start.sh ops.sh drill.sh/.ps1  README.txt
data/ backups/ logs/  the store and its side files; backups; realm.log (rotated), supervisor.log, console.log
```
`realm-ops package --bins=DIR --out=DIR --version=V --host=realm/ops/host` makes it (CI's Windows job does, as an artifact);
without `--host` it makes just a release folder to `install` on a running host. The programs are the same on both
systems; only the scripts differ. The supervisor (`realm-ops run`, started by `start.cmd`, `start.ps1`, `start.sh` or
systemd) reads `ops.conf`, starts `releases/<current>/realm-gateway` with the matching flags and `--ops-conf`, restarts
it when it dies (1 s, doubling to 30 s, reset after a minute of life) and raises `host-death`. `running` holds its pid;
`stop` and `restart` are files the CLI drops, so every launcher works the same way. On either, the supervisor asks the
gateway to stop by dropping `gateway.stop` in the host folder (std has no graceful signal; the gateway watches the file
beside its `--ops-conf`, or `--stop-file=PATH`, and with neither watches nothing; a request left from before is cleared
when it starts): it banks every hero in a field with her whole haul and her class XP
(`Leave::Shutdown`, as `Gateway::shutdown`), ends its hosts and exits 0, logging `realm_stopping` and `realm_stopped`.
A gateway still running after 20 s (`supervise::STOP_GRACE`) is killed (`gateway_stop_forced`). `realm-ops stop` returns
once the supervisor has ended (at most 25 s; realm.service's `TimeoutStopSec` is 40), and exits non-zero saying so when
the gateway had to be killed (the supervisor leaves `stopped` = `clean` or `forced` in the host folder). Measured: 1,000
host-played heroes in a field are banked and stopped in about 0.5 s (`gateway/tests/world.rs`
`a_stop_banks_every_hero_in_the_fields_in_time`), so the grace is a constant, not a setting. A kill (SIGKILL, a crash, a forced
stop) still loses only the unbanked hauls: everything banked is already in the store (`gateway/tests/kill.rs`, both tests).
`install-task.ps1` registers a logon task so Curtis's PC brings the realm back after a reboot.

## Logs, metrics, alarms

- Logs: `TIMESTAMP LEVEL event key=value ...` (`log.rs`), to `logs/realm.log`, rotated at `log_max_mb` (10) keeping
  `log_keep` (10) files: 110 MB at most. The supervisor has its own file so two processes never rotate one.
- Metrics on `127.0.0.1:metrics_port` (7790), loopback only (the server also refuses non-loopback peers):
  `/metrics` (Prometheus-style lines), `/status` (the page: uptime, players, per field copy heroes and tick p50/p99,
  store write p50/p99 and in flight, errors, refusals, backups, kill switches), `/health`. `realm-ops status` prints it.
  Tick time is the field host's whole tick (simulate + encode + send), per field kind; store write latency is timed
  around every gateway command through the writer thread (`metrics::store_call`); queue is the store requests in flight.
  Series are the last 2 048 samples (102 s of ticks), so p50/p99 describe now, not the whole uptime. "Players" counts
  heroes in fields (town rooms are the gateway's).
- Alarms (`alarm.rs`, once a second): `tick-budget` when the p99 of a field's last 200 ticks is over `tick_budget_ms`
  (50 = the 20 Hz period; needs 100 samples), `host-stall` when a field host has not finished a tick for `stall_secs`
  (10), `store-errors` at `store_error_limit` (5) failed store commands in a minute, `backup-failed`, and the supervisor's
  `host-death`. Each is a log line (`ERROR ALARM kind=... msg=...`) every time and a run of `alarm_hook` (arguments
  kind, message; `ALARM_KIND`, `ALARM_MSG`; `.ps1`, `.cmd` and executables) at most once per kind per
  `alarm_cooldown_secs` (300). Samples of both hooks are in `host/`.

## Backups and the restore drill

`backup_every_mins` (60) backs up with SQLite's online backup (play goes on), to `realm-YYYYMMDD-HHMMSS.part`, then
opens the copy fresh and runs the store's full `verify` (every invariant, the ledger replayed) before renaming it; a copy that does not verify
is deleted and is an alarm, never kept. Every side file in `realm_ops::sides::SIDES` is copied beside it: `.secret`,
`.admin`, `.social`, `.bosskills`, `.switches`, `.homes` (who owns every house), `.epoch` (the realm clock's start: every
tide) and `.social.words`; restore copies them back. The writers name these files through `sides::side`, and
`ops/tests/sides.rs` fails on a `<db>.x` path built anywhere else, so a new kept file cannot miss the backup.
Kept: the newest `backup_keep` (48 = two days hourly) plus the first backup of each of the last `backup_daily_keep` (14) days.
The first backup after a start is due by the clock's own schedule (a restart does not skip an interval), at least a minute in.
`realm-ops restore [file]` (realm stopped: refused while `running` exists) verifies the backup, moves the live store and
its WAL aside as `realm.db.before-restore-STAMP` (never deleted: undoing a restore is a rename), copies the backup in and
verifies the digest of items and stacks equals the backup's. The side files end exactly as the backup has them: each
live one is moved aside as `realm.db.before-restore-STAMP.<ext>`, then the backup's is copied in; one the backup lacks
is not left live and the restore says so (`NOTE the backup has no .homes ...`: a backup made before houses were backed
up restores with every house unowned, the old registry kept aside). `realm-ops drill` restores the newest backup to a scratch
file and verifies it while the realm runs; `drill.sh`/`drill.ps1` are for cron or Task Scheduler (weekly).
A store one schema behind this build (a pre-switch backup) cannot use the newest-tables verify: it gets SQLite's
`quick_check`, and the older release's own `realm-store verify` is the full check (`backup::check`).

## Kill switches

From the admin console (`kill WHAT`, `revive WHAT`, `switches`; WHAT = `login`, `trade`, `market`, `field N`, `all`), or
`realm-ops kill login` from the host (it talks to the loopback admin port with the token in `data/realm.db.admin`).
Login closed: new logins get `DISABLED`; players already in stay. Trade frozen: invite, accept, offer and confirm are
refused (cancel and view still work, so an open trade can be undone). Market frozen: listing and buying are refused (cancel
and browse still work). Field N stopped: no new tickets (`NO_FIELD`); heroes inside finish and bank. `all` throws every
switch and all six fields. They are atomics (`switches.rs`) saved to `<db>.switches`, so a restart in an incident does not
quietly reopen what was closed, and every change is in the moderators' admin log.

## Pulling the rug (bot and farm accounts, by hand only)

Curtis's tool for farms: trace, lock, shadow, claw back, ban waves. Nothing in the realm runs these on its own; there
are no automatic bans. `realm-ops` (code `realm/ops/src/rug.rs`) uses the store's own operations as the server
(`trace`, `trace_forward`, `clawback_plan`, `clawback`, `apply_flags`), so every change leaves its ledger rows (CLAWBACK
rows with `clawback #A by OP: REASON`, one FLAGS row per account with `rug ACTION by OP: REASON`). Every change is a
dry run that prints what it would do until you add `--yes`.

How it reaches the store. The store has one writer, the running gateway (it keeps the ledger's next seq in memory),
so another process must never write a live store. While the realm runs, `realm-ops` sends the line to the gateway's
admin console over the loopback admin port (`admin_port` in ops.conf, token in `data/realm.db.admin`, as `kill` does);
the console runs it as `rug ...`, writes it to the moderators' admin log, and throws a banned account's heroes out.
Files (a plan file, a wave file) are read by `realm-ops` and sent inline. With `--db=FILE` it opens that store itself:
a stopped realm, or a backup copy to look at in peace (`realm-ops` refuses `--db` on the live store while `running`
exists). From the console itself: `rug trace 12`, `rug plan 12 --since=7d`, and so on (`--key=value` form, reason last).

```
realm-ops trace 12                     # account 12 (or #12): items it minted and who holds them, per stack kind
                                       # minted/spent/held, received from and sent to whom, items it holds that
                                       # were minted for others, onward moves (--depth 3); --json for a tool
realm-ops trace hero:Farmer            # the hero's account;  trace item:5  one item's owner and path
realm-ops plan 12 --since 7d           # what a clawback would take (items, stacks, totals); changes nothing
realm-ops plan 40 --origin 12          # only the part of farm 12's plan that buyer 40 holds now
realm-ops plan 12 > farm12.plan        # the output is a plan file: edit out lines you do not want taken
realm-ops clawback 12 --plan-file farm12.plan --reason "gold farm, ticket 88"          # dry run
realm-ops clawback 12 --plan-file farm12.plan --reason "gold farm, ticket 88" --yes    # removed, missing, shortfall
realm-ops flag 12 lock --reason "gold farm" --yes      # lock | shadow | ban (forever) | clear (flags and ban)
realm-ops wave ring.txt ban --reason "farm ring" --yes # one account per line (12, #12 or a hero name); one line
                                                       # per account, bad lines named, a total; one transaction
```

`--since` takes `seq:N`, a UTC date (`2026-11-20`, `2026-11-20T18:00`), unix ms, or a span back from now (`7d`,
`12h`, `30m`); it becomes the last ledger seq before that time (`read::seq_before`). The order that works: `trace`
the farm, `wave FILE lock` the farm and its buyers (value stops moving), `plan` and keep the file, `clawback` it,
then `wave FILE ban` or `clear` on review. A plan reaches one hop for coin (see store.md); widen it by hand from
`trace --depth`. `realm-gateway admin --db=...` has the older moderator words (`flag NAME FLAGS`, `banwave FLAG SPAN`).
Proof: `realm/ops/tests/rug.rs` (a farm mints and trades to a buyer who banks some: trace, plan, dry run digest
unchanged, clawback with ledger rows, flags set and cleared, a wave of three with one bad line) and the console test
`rug_through_the_console` in `realm/gateway/src/social/admin.rs`.

## Release and rollback

`install DIR` copies a release folder to `releases/V` (a version is never overwritten). `switch V` writes the two pointer
files and nothing else: the store is never touched. It refuses a release whose `schema` is older than the store's
(the newer program may have migrated it; an old program cannot read it), and takes a verified pre-switch backup of the store into
`backups/pre-switch/` first (nothing switches if that fails). Then `restart` runs it. `rollback` is `switch previous`.
When the store has moved to a newer schema, a plain rollback is refused with the way out: stop the realm and
`rollback --restore-pre-switch`, which restores the backup taken before the switch that migrated it (play since is lost, which is the
price; the message says so). `release.txt` is written by `package` from the store crate's `schema::STEPS`.

## Flood protection

`flood.rs`, per IP, fixed windows of `flood_window_secs` (10): gateway TCP `flood_conn_per_ip` simultaneous connections,
`flood_conn_rate` new connections a window, `flood_pkt_rate` requests a second (averaged over the window, so a burst of one
window passes); field UDP `flood_udp_rate` datagrams a second. Over a limit the IP is refused entirely for `flood_ban_secs`
(60) and the line `flood_ban` is logged. All are 0 (off) by default and `flood_exempt` (127.0.0.1, ::1) is never limited, so the
soak and tests, whose bots are all one address, are untouched. Suggested public values (in each setting's text): 20, 10, 100, 400.
Why 400 UDP/s: a client sends 20 a second per hero, so a household of a few passes; a flood does not.

## Playtest on the home PCs

Curtis plays against the same LAN host (`lanhost` on ubuntu). Code: `realm/playtest/` (`play.ps1`, `play.sh`,
`README.txt`, `Play.cmd`) and the station job `tools/station/jobs/playkit.sh`.
- The launcher reads `lan/host.txt` from `station-results` (public raw URL), waits for `state=live` with 10+ minutes
  left, saves the published certificate and starts the client with `--gateway=IP:7700 --dev-cert=PEM`. Only a debug
  build honours `--dev-cert` (`gw_link.gd`), so the release export cannot be used for this.
- **On a station PC:** `queue.sh add kind=shell args=script=playkit needs=<machine> priority=9` builds the native module,
  copies the client to `~/HordeAndHearthPlay/client`, imports it and puts "Play Horde and Hearth" on the desktop (a
  `.cmd` on Windows, a `.desktop` on Linux) that runs the station's own Godot editor binary. Re-run it to update.
- **Anywhere else:** the CI artifact `realm-playtest-windows-<ver>` (a debug export plus `Play.cmd`).
- **The server:** `queue.sh add kind=shell args=script=playhost needs=ubuntu priority=9` (`jobs/playhost.sh`) runs the
  gateway detached from the queue under `realm/playtest/serve.sh`, on a KEPT store `~/HordeAndHearthServer/realm.db`
  (heroes stay), restarts it if it exits, and publishes `lan/host.txt` every 300 s with `end_epoch` a day ahead (same
  format as lanhost, so the lanplay bots use it too). Re-run playhost to update the server to a new commit (it stops the
  old one cleanly first). `touch ~/HordeAndHearthServer/stop` stops it for good. It replaced the forever lanhost job on
  ubuntu (same ports); a lanhost rehearsal must not run on that PC while playhost serves.

## Player-like bots (playbot)

Bots that play the REAL client the way Curtis does, for realistic data (frame times, stutters, errors, screens, flows).
Code: `realm/client/tests/playbot.gd`, station job `tools/station/jobs/playbot.sh`.
- **Input path:** the shell is built as `main.gd` builds it, and every input is an event through
  `Input.parse_input_event`: keys (keycode and physical keycode, pressed then released, the keys `ShellSettings` binds,
  so a station's own key settings are used) and the mouse moved over and clicked on the buttons the screens draw, at
  window coordinates. It never calls `press()`, `on_press`, `_unhandled_input` or the field client's `script_move`. It
  READS state (the screens' `_hits`, the town, the field client's `_info`, monsters in view, sites) to decide.
- **The flow:** title, login (Backspace the offered name, type `PB<name>`, Enter or KNOCK), the first hero or the builder
  (random race and class by clicks), town (walks with the move keys to a station and clicks it or presses F; the bag or
  sheet by key or button; closes by Esc, a right click on nothing or the X), the gates (clicks a field it fits, or
  Enter), the field, back, again until `--secs`. A 0.3 to 1.5 s pause before each menu input; seeded RNG (`--seed`).
- **The field brain (keys only):** out from the gate, then hunts the nearest pack (the nearest monster alone when hurt),
  explores 600 to 1 800 px off when nothing is in view, kites away under 50 % health and taps a potion under 45 %,
  holds skill 1 while anything is within 150 px and skill 2 / the ultimate when ready, picks an offered card with its
  key after a moment, roams off after being downed. After 90 to 200 s (or four downs) it walks to the nearest waystone,
  clears it, holds F 3 s to bank, then leaves by holding F again, by the gate (south through it) or by Esc. When `--secs`
  is up it leaves by the nearer of gate and waystone; 90 s later by Esc. Unstick: no headway for 3 s with a move key
  held, a random heading for 1.5 s. Never steps south near the gate unless leaving (that ends the outing).
- **Data** (`--out`): `summary.json` (per-screen secs, inputs, visits, frames and hitches; FPS and frame ms p50/p99/max;
  frames over 50 and 100 ms with the screen and time; engine and script errors counted by an `OS.add_logger` Logger,
  the first 20 kept; the field client's net and sim counters per outing with the field's sites; a 16 x 16 heat grid per
  field; card picks, potions, banks, downs, outings as the gateway reported them, km walked at 32 px a metre; buttons
  another button covers and panels that did not close by the way tried) and PNGs (each screen change, each of the first
  three downs, one a minute, at most 40). One stdout line:
  `PLAYBOT ok|FAILED secs= screens= fields= outings= kills= deaths= coin= fps_p50= frame_ms_p99= hitches_50ms= errors= km_walked=`.
  FAILED only when it never reached a field or the gateway link was lost. Kills are counted from the frame's kill rows
  near her in frames that gave her XP (a kill row names no killer): a lower bound.
- **On a station:** `queue.sh add kind=shell args="script=playbot secs=900 bots=2" needs=<machine> timeout_s=2400`
  (needs `playkit` run there first: it uses `~/HordeAndHearthPlay/client`, copying the checkout's `playbot.gd` in).
  It waits (`wait=`, 300 s) for the live host `play.sh` finds (fresh: rewritten in the last 15 minutes), runs K windows
  a few seconds apart with their own names and seeds, on Linux on the real DISPLAY when set (Curtis watches) else under
  `xvfb-run`; the window is 960 x 540 and asks not to take focus. Art: `botN/summary.json`, `botN/*.png`, `botN.log`.
  Last line `PASS playbot ...`, `INFO playbot: no live host` or `FAIL playbot ...`.
- **Locally:** a gateway with `--dev-cert --dev-login --dev-grant --fields=0`, then
  `xvfb-run -a godot --path realm/client -s res://tests/playbot.gd -- --gateway=127.0.0.1:PORT --dev-cert=PEM --secs=240 --out=DIR`.

## LAN rehearsal

Proof that the game works between the home PCs over a real network with TLS: one PC hosts, the others play. Code:
`tools/station/jobs/lanhost.sh`, `jobs/lanplay.sh`, `lan_lib.sh`, `lan_test.sh`, the bot `realm-lanplay`
(`gateway/src/lanplay_bin.rs`).

- **Queue it** (host first; players wait up to `wait=180` s for a live host, so the order is forgiving):
  `queue.sh add kind=shell args="script=lanhost secs=1800" needs=ubuntu timeout_s=3600`, then on the others
  `queue.sh add kind=shell args="script=lanplay secs=600 bots=4" needs=msi timeout_s=1800` (and `needs=laptop`,
  `needs=heatherspc`). Each player machine uses its own bot numbers, so heroes do not collide.
- **Host:** builds the release binaries, starts `realm-gateway --dev-login --dev-cert --public-host=<LAN IP>` on a fresh
  temp store (fields 0 and 1, one copy each), and publishes `lan/host.txt` on `station-results` at once (the queue
  publishes a job's art only when the job ends, too late for players); `lanhost.txt` is also the art. The file holds
  the LAN IP, TCP port (7700), UDP ports (7800-7801), start and end time, and the PUBLIC dev certificate (never a key).
  At the end it stops the gateway (heroes banked), marks the file `state=ended`, and reports logins, field tickets,
  peak heroes in fields, errors. Words: `secs`, `port`, `fieldport`.
- **LAN IP:** `lan_ip` in `lan_lib.sh`: on Linux the source address of the route to the internet (`ip route get`, else
  `hostname -I`); on Windows (Git Bash) PowerShell's adapter with a default gateway, else the first private address in
  `ipconfig`. `STATION_LAN_IP=` overrides.
- **Certificate:** `--dev-cert` makes a self-signed certificate whose names are localhost, 127.0.0.1, ::1 and the
  `--public-host`, so the LAN IP is a subjectAltName IP entry (the host passes it; it is made again when it changes).
  The player runs `realm-lanplay --addr=IP:7700 --ca=<published PEM>`: it trusts exactly that file and checks the IP
  against it. No `--insecure-dev`. The field ticket names the same IP, and its UDP admission key travels over that TLS.
- **Player:** `lanplay.sh secs=N bots=K` finds the live host (else last line `INFO lanplay: no live host`), runs K
  bots: login, hero, town, field ticket, field play over UDP, bank, again and again for N s. **PASS** = no handshake
  or auth failure, no state mismatch, at least one login and outing; the line has logins_ok, cycles_failed,
  outings, banked, rtt_mean_ms and rtt_p99_ms (gateway calls over TLS), refused_datagrams (client side), hash_bad.
  **FAIL lanplay: host unreachable (firewall?) IP:PORT** when the TCP port does not answer in 8 s.
  The tools change no firewall setting: the host PC must let TCP 7700 and UDP 7800-7801 in (Windows asks the first time
  a program listens; answer yes for private networks), and a router must not isolate Wi-Fi clients.
- **Whole rehearsal passes** when the host ends `PASS lanhost` with logins and tickets from each player machine and
  every player job ends `PASS lanplay`. `tools/station/lan_test.sh` (`LAN ok`, about 45 s; also run by `queue_test.sh`
  when the release binaries exist) proves the pair on one machine, on this machine's real LAN address when it has one.
- **Not covered:** real Windows hosting, a firewall that drops UDP only, packet loss on Wi-Fi; the clock of the PCs
  decides when a host file counts as live (a few seconds of skew is fine); vault copies use random UDP ports.

## Proof

`ops/tests/e2e.rs` runs the real `realm-ops` on a temp folder: package, backup, install, switch, play, rollback, the
downgrade refusal, a newer schema allowed, a wrecked store restored (refused while running), the drill, the migrated-store rollback with
`--restore-pre-switch` (a store built at the older schema by hand), and on Unix the supervisor restarting a dying gateway and
calling the hook. `gateway/tests/ops.rs`: kill switches through real sockets, flood limits, the metrics endpoint, and a real
`realm-gateway --ops-conf` logging, serving metrics and keeping a switch across a restart. Unit tests cover the rules (rotation,
percentiles, the window and ban arithmetic with a fake clock, retention, the config template). CI: Linux runs all of it in
`cargo test`; the Windows job runs it too, parses every `.ps1` with PowerShell's parser, runs `realm-ops rehearse` and uploads the
host package. Station word `ops` (Ubuntu): `realm-ops rehearse` per realm merge and nightly inside `deep`. The rehearsal
also writes a house to `.homes` and an epoch to `.epoch` before the backup, loses both with the wrecked disk and checks the
restore brings them back (`gateway/tests/ops.rs` does the same with the real plot registry and clock).
`gateway/tests/kill.rs` stops a realm run with `--ops-conf` through `gateway.stop` while a hero fights unbanked: it exits 0
within the bound, her whole haul is banked, and the restarted realm loads it. On Unix the e2e supervisor's stop asks its
stand-in gateway to stop rather than killing it.

## Open questions

- Windows has not been run by me: the `.cmd`/`.ps1` are checked for syntax by CI only; the first real try is Curtis's PC.
- `realm-store` binary: the package takes it from `realm/store/target/release` when present (the Windows job copies it); the Linux job
  does not build a package artifact yet.
- UDP limits are per IP, not per ticket; two clients behind one NAT share a budget.
- Alarms have no clear message ("recovered"); the hook sees only the raising.

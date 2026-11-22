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
`stop` and `restart` are files the CLI drops, so every launcher works the same way. Stopping is a kill: everything
banked is already in the store (the kill test, `gateway/tests/kill.rs`), and std has no graceful signal.
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
is deleted and is an alarm, never kept. `.secret`, `.admin`, `.social`, `.bosskills`, `.switches` are copied beside it.
Kept: the newest `backup_keep` (48 = two days hourly) plus the first backup of each of the last `backup_daily_keep` (14) days.
The first backup after a start is due by the clock's own schedule (a restart does not skip an interval), at least a minute in.
`realm-ops restore [file]` (realm stopped: refused while `running` exists) verifies the backup, moves the live store and
its WAL aside as `realm.db.before-restore-STAMP` (never deleted: undoing a restore is a rename), copies the backup in and
verifies the digest of items and stacks equals the backup's. `realm-ops drill` restores the newest backup to a scratch
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
host package. Station word `ops` (Ubuntu): `realm-ops rehearse` per realm merge and nightly inside `deep`.

## Open questions

- Windows has not been run by me: the `.cmd`/`.ps1` are checked for syntax by CI only; the first real try is Curtis's PC.
- `realm-store` binary: the package takes it from `realm/store/target/release` when present (the Windows job copies it); the Linux job
  does not build a package artifact yet.
- A graceful stop (bank everyone, then exit) needs a gateway command; today stop is a kill, safe by the store's design.
- UDP limits are per IP, not per ticket; two clients behind one NAT share a budget.
- Alarms have no clear message ("recovered"); the hook sees only the raising.

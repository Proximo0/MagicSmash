# realm: the crowd test's server side

**Shelved on 27 Nov 2026 (the owner's decision; saved for later in the year). Nothing here is in work and no PC
runs it: see `docs/realm/SHELVED.md`.**

The contract is `docs/realm/crowd_test.md`. Rust, std only (no crates, so cargo never needs the network),
except `godot/`, the Godot native module, which is its own cargo workspace with one crates.io dependency.

- `core/`: the simulation. Whole numbers only (positions `i32` in 1/256 px, time in ticks); struct-of-arrays
  monsters; a counting-sort grid; a flow field refreshed in slices; bulk fighting; spawning out of every view.
  `Field::new(seed, Config { monsters, threads })`, `join`, `leave`, `step(&inputs)`, `hash()`,
  `to_bytes()` / `from_bytes()`. The result is the same for any thread count.
- `server/`: the 20 Hz UDP server (protocol A v0 and v1, protocol B), bots, and `--bench`.
- `gateway/`: `realm-gateway` (accounts, heroes, towns, field tickets and a field host per copy, on one store file) and `realm-soak` (bots through all of it, one `SOAK ok` line). Wire and numbers: `docs/realm/wire.md`.
  The world (the realm clock, copies that open and merge, the queue, vaults, boss news) and `realm-world` (a
  compressed week of bot play, one `WORLD ok` line): `docs/realm/world.md`.
- `loadtest/`: real UDP clients, protocol B followers and lockstep players, and a lossy UDP relay.
- `godot/`: the native module (a GDExtension `cdylib`, gdext `godot` 0.5.5, Godot API 4.7): the class
  `RealmLink`, a lockstep player inside Godot. Its own workspace and `Cargo.lock`.
- `store/`: the store (accounts, heroes, items, stacks, entitlements and the ledger), its own cargo workspace with
  `rusqlite` (bundled SQLite); `store/check.sh`; see `docs/realm/store.md`.
- `client/`: HORDE & HEARTH's realm client, a separate Godot 4.7 project that plays through `RealmLink` (the
  simulation on a worker thread inside the module). The field's scripts are in `client/field/`; see
  `docs/realm/client.md`.
- The lockstep client logic is `server/src/client.rs` (socket-free: the load test and the module both drive
  it) and `server/src/predict.rs` (the hero's prediction and smoothing).

## Build and check

```sh
cd realm
cargo build --release -j3
./check.sh          # cargo test --release, then a 10 s bench with a follower; one summary line
./check_client.sh   # the native module, then the Godot client test against a server, direct and through
                    # a lossy relay (needs godot 4.7 on PATH or GODOT=...); one summary line
```

The native module: `cd godot && cargo build --release`, then copy `godot/target/release/librealm_godot.so`
(Windows: `realm_godot.dll`) into `client/bin/`, where `client/realm.gdextension` points. `check_client.sh`
does both. Godot finds the module through `client/.godot/extension_list.cfg`, which the editor or
`godot --headless --path client --import` writes on the first import.

## Run

```sh
# A server with 1 000 bots and 20 000 monsters; the Godot viewer (or any client) joins beside them.
./target/release/realm-server --bots=1000 --monsters=20000 --rally=0.3 --threads=2

# Real clients: 200 protocol A v0 players, and 50 v1 players plus a protocol B follower.
./target/release/realm-loadtest --clients=200 --proto=a0 --secs=15
./target/release/realm-loadtest --clients=50 --proto=a1 --follow --secs=15

# Lockstep players (they join, their inputs enter the stream, they follow the whole field and predict
# their hero) and a follower, through a relay that drops 5% and delays 80 +- 20 ms each way.
./target/release/realm-loadtest --relay=7778 --to=127.0.0.1:7777 --loss=0.05 --delay-ms=80 --jitter-ms=20 &
./target/release/realm-loadtest --server=127.0.0.1:7778 --players=4 --follow --secs=20

# The game window: arrows or WASD move, Space/E/R the skills, F banks, 4/5/6 potions, Z X C V pick a card,
# 1/2/3 zoom 1/2/4, F3 the numbers (docs/realm/client.md).
godot --path client -- --server=127.0.0.1:7777
# Scripted: a screenshot and numbers per zoom, then stats.json; --zoom=8 shows a whole rally's horde.
godot --path client -- --server=127.0.0.1:7777 --bot --shots=/tmp/shots --secs=5
godot --path client -- --server=127.0.0.1:7777 --shots=/tmp/horde --secs=5 --zooms=8

# No sockets: simulate and encode A v0, A v1 and B for every bot as if each were connected.
./target/release/realm-server --bench --bots=1000 --monsters=20000 --rally=0.3 --threads=1 --ticks=300 --follow
```

### Server flags

| flag | default | meaning |
|---|---|---|
| `--port=P` | 7777 | UDP port |
| `--seed=S` | 1 | field and bot seed |
| `--bots=N` | 0 | bot players, joined at tick 1 |
| `--monsters=M` | 20000 | the monster count spawning keeps |
| `--rally=0.3` | 0.3 | share of bots that join near and stay around the centre (the dense fight) |
| `--threads=T` | 1 | worker threads for move, fight and the bench encoders (never changes the hash) |
| `--report=secs` | 5 | a table row every this many seconds of game time |
| `--ticks=N` | bench 600, server forever | stop after N ticks |
| `--bench` | | no sockets: as fast as possible, every bot measured as a client |
| `--follow` | | bench only: an in-process protocol B follower joins after warmup and checks hashes |
| `--zoom=Z` | 1 | bench only: the zoom every bot asks for (1, 2 or 4) |
| `--warmup=N` | 100 | bench only: ticks left out of the numbers (the first spawn burst) |

### Load test flags

`--server=127.0.0.1:7777`, `--clients=N`, `--proto=a0|a1`, `--follow`, `--players=N` (lockstep players,
HELLO proto 4), `--secs=10`, `--threads=1` (each follower's), `--zoom=1`. It exits 1 if a snapshot fails to
decode or check, or a protocol B client saw a hash differ, no hash at all, or a datagram that did not parse.
Each B client prints one line: bytes a second in (whole seconds after the join download) and out, CPU a
tick, `stall_ms max` (the longest wait between two applied ticks) and, for a player, `mispredicts` (confirmed
ticks where the hero was not where it had been predicted, out of those checked).

Relay mode: `--relay=PORT --to=HOST:PORT [--loss=0.05] [--delay-ms=80] [--jitter-ms=20] [--seed=1]
[--secs=N]`. Each client gets its own upstream socket; every datagram either way is dropped with chance
`loss` or delivered after `delay-ms` plus or minus up to `jitter-ms` (one way). It runs until stopped (or
`--secs`) and prints what it forwarded and dropped every 10 s.

## Reading the table

One row per report window. Times are milliseconds per tick, `mean/p99`:

- `tick`: the whole server tick (bots + simulation + every encoder). The budget at 20 Hz is 50 ms.
- `flow move grid fight spawn input`: the core's phases. `bots`: deciding the bots' inputs.
- `encA0`: building every client's view and coding it as A v0 (on snapshot ticks only, 10 a second, so the
  mean is half the snapshot-tick cost). `encA1`: coding the same views as v1. `encB`: the B record and packing.
- `A0 A1 B B/s`: payload bytes per second per client (`mean/p99` over clients and seconds; add 28 bytes of IP
  and UDP header per datagram for the wire). The bench codes v1 against the snapshot before last (a client
  acknowledging about 200 ms late) and sends each B tick twice (an ack one tick behind).
- `mon view`, `ply view`: monsters and players (near + crowd) in a client's view.
- `join B`: bytes a protocol B client downloads to join. `follow ms`: the follower's CPU per tick (1 thread).
  `hash`: `ok n` when the follower matched the server on all n hashes (one every 20 ticks).

The last line, `BENCH ...`, carries the final hash: the same command with a different `--threads` must
print the same hash.

## Choices the contract left open

All numbers are in `core/src/tables.rs` and the constants at the top of `core/src/lib.rs`.

- Monsters: speed 20 to 70 px/s, health 20 to 120 (elite one in 50, health x4, XP x3); contact radius
  20 px, damage every 10 ticks; a hit staggers 2 ticks. A monster more than 64 flow cells (2 048 px) from
  every player is recycled so spawning puts it back near someone.
- Classes: area radius 48 to 120 px, cooldown 10 to 16 ticks, bolt reach 160 to 400 px. Level adds 5 %
  damage up to x3. The skill bit: a double-radius, triple-damage area hit, 5 s cooldown.
- Movement: an 8-neighbour breadth-first search, 32 768 cells a tick (a full refresh every 8 ticks); within
  2 cells of its player a monster steers straight at it; a cell holding more than 6 counts against a
  neighbour like half a step uphill per extra monster.
- Spawning: 16 tries per monster, at most 1 024 failures a tick; the view kept clear is 480 x 270 (zoom 1).
- Joins: a joining player gives its position (bots spread over the field, rally bots near the centre,
  network players within 200 px of it). The respawn point is the centre.
- HELLO `proto`: 1 is A v0 (the contract), 2 is A v1, 3 is a B follower (no player), 4 is a B lockstep
  player. Packing of v1 and B: see the top of `server/src/snap.rs` and `server/src/lockstep.rs`.
- Lockstep players: each INPUT carries a seq and repeats the 3 moves before it; the server queues them (at
  most 3 waiting) and uses one a tick, so jitter does not make it skip or double an input. Every B send to a
  player starts with the seqs in force at the unacknowledged ticks (`0x92`), which is what the prediction
  replays from. The shown hero closes a prediction error at 1 px a tick beyond its own step and jumps only
  for an error over 64 px (a respawn).
- Loss: nothing extra. Every B datagram already repeats every tick the client has not acknowledged, so a
  lost one costs one tick (50 ms) of waiting: the next datagram brings it.
- The module draws through two bulk buffers (`monster_buffer`, `player_buffer`: a MultiMesh's floats with
  the offset back to the previous call per figure) so the shader glides every figure between ticks with no
  GDScript per figure; `monsters_in` and `players_in` are the plain sorted reads. No cap on either.

## Hosting on a Windows PC

The CI (`.github/workflows/realm.yml`) builds `realm-server.exe` and `realm-loadtest.exe` for Windows and
uploads them with `run_server.bat` as the artifact `realm-server-windows`. Unzip it anywhere and double-click
`run_server.bat`: a server on UDP port 7777 with 200 bots and 8 000 monsters, a report line every 10 seconds,
and the window stays open when it stops. Extra flags pass through (`run_server.bat --bots=500 --threads=4`).

- **Firewall**: the first start asks Windows Defender Firewall about `realm-server.exe`; allow it on private
  networks. Without the prompt, add an inbound rule for **UDP port 7777** (Windows Security, Firewall,
  Advanced settings, Inbound Rules, New Rule, Port, UDP, 7777).
- **Players on the same network** (the same router) connect to this PC's local address, shown by
  `ipconfig` as the IPv4 address (for example `192.168.1.20`): `--server=192.168.1.20:7777`.
- **Friends outside the house** connect to the router's public address (any "what is my IP" page), and the
  router must forward **UDP port 7777** to this PC's local address (the router's settings page, "port
  forwarding" or "virtual server"). Give the PC a fixed local address (a DHCP reservation in the router) so
  the forward keeps pointing at it. A connection through a carrier-grade NAT (some mobile and fibre
  providers) cannot be forwarded; then a rented server is the way.
- Only UDP 7777 is used; nothing else needs opening. Change it with `--port=P` (and forward that instead).

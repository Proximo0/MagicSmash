# realm: the crowd test's server side

The contract is `docs/realm/crowd_test.md`. Rust, std only (no crates, so cargo never needs the network).

- `core/`: the simulation. Whole numbers only (positions `i32` in 1/256 px, time in ticks); struct-of-arrays
  monsters; a counting-sort grid; a flow field refreshed in slices; bulk fighting; spawning out of every view.
  `Field::new(seed, Config { monsters, threads })`, `join`, `leave`, `step(&inputs)`, `hash()`,
  `to_bytes()` / `from_bytes()`. The result is the same for any thread count.
- `server/`: the 20 Hz UDP server (protocol A v0 and v1, protocol B), bots, and `--bench`.
- `loadtest/`: real UDP clients and the protocol B follower.

## Build and check

```sh
cd realm
cargo build --release -j3
./check.sh          # cargo test --release, then a 10 s bench with a follower; one summary line
```

## Run

```sh
# A server with 1 000 bots and 20 000 monsters; the Godot viewer (or any client) joins beside them.
./target/release/realm-server --bots=1000 --monsters=20000 --rally=0.3 --threads=2

# Real clients: 200 protocol A v0 players, and 50 v1 players plus a protocol B follower.
./target/release/realm-loadtest --clients=200 --proto=a0 --secs=15
./target/release/realm-loadtest --clients=50 --proto=a1 --follow --secs=15

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

`--server=127.0.0.1:7777`, `--clients=N`, `--proto=a0|a1`, `--follow`, `--secs=10`, `--threads=1` (the
follower's), `--zoom=1`. It exits 1 if a snapshot fails to decode or check, or a hash differs.

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
- HELLO `proto`: 1 is A v0 (the contract), 2 is A v1, 3 is a B follower (no player). Packing of v1 and B:
  see the top of `server/src/snap.rs` and `server/src/lockstep.rs`.

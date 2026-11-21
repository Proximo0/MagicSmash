# The crowd test: can one field hold a thousand players and tens of thousands of monsters?

A side test beside the current game (the owner, 21 Nov 2026: "run this as a side test to our current project for
now and we will see how the test turns out"). He is weighing an MMO with a survivor feel, and its hardest part is
hundreds to thousands of players and thousands to tens of thousands of monsters in one place. This test builds the
smallest thing that answers that with numbers. Nothing here is the final game and nothing in `game/` depends on it;
the measurements decide whether, and how, the MMO goes ahead.

## The questions
1. **Server load**: how many players and monsters can one field simulate at 20 ticks a second on one core, and on
   four?
2. **Data per player**, two ways:
   - **A, snapshots**: the server sends each player the monsters and players near their screen.
   - **B, lockstep**: every client runs the same deterministic simulation of the whole field; the server sends only
     every player's inputs and a state hash.
3. **Client load**: frames per second of a Godot window drawing what protocol A sends, and the CPU a native client
   needs to follow protocol B.

Targets: 1 000 players with 20 000 monsters is the pass line; 2 000 with 50 000 and 5 000 with 100 000 are measured
to find where it breaks.

## Parts and owners
- `realm/` (Rust workspace, std only, no crates): `realm/core` (the simulation), `realm/server` (UDP server, bots,
  metrics), `realm/loadtest` (headless clients). Owner: the core job.
- `game/crowd/`, `tests/crowd/` and `tests/unit/test_crowd_*.gd` (GDScript): the viewer, a standalone scene run by
  path (`godot --path . game/crowd/crowd.tscn -- --server=127.0.0.1:7777`). Owner: the viewer job.
- This file is the contract. A job that needs it changed reports the change; it does not edit the other job's files.

## The simulation (`realm/core`)
- **Whole numbers only.** No floating point anywhere in `core`: positions are `i32` in 1/256 px, time is ticks.
  Same inputs, same state, on every machine. A 64-bit state hash (positions, health, counters, the RNG) is the proof.
- **The field**: 16 384 x 16 384 px, wrapped at no edge (a wall). Tick 20 Hz.
- **Monsters** live in flat arrays (x, y, health, kind, stagger). Eight kinds (0 bloat, 1 coffin, 2 guard,
  3 cinderling, 4 censor, 5 hound, 6 shard, 7 swords) with a speed and health each, numbers in one table.
- **Movement**: a flow field over 32 px cells (512 x 512), a breadth-first distance from every player's cell,
  refreshed in slices so no tick pays for all of it. A monster steps down the field; a crowded cell pushes it to a
  less crowded neighbour (no pairwise checks).
- **A grid of cells** rebuilt each tick by counting sort gives "what is near here" for hits and for the snapshots.
- **Players**: position, class (0 knight, 1 mage, 2 archer, 3 priest, 4 paladin), race (0 human, 1 elf, 2 dwarf,
  3 orc), health, level, XP. Input per tick: a direction 0..8 (0 none, 1 E, 2 SE, 3 S, 4 SW, 5 W, 6 NW, 7 N, 8 NE)
  and a skill bit. Speed 60 px/s.
- **Fighting, in bulk**: every player auto-attacks on a cooldown: an area hit (a radius by class) on every monster
  in range through the grid, and one bolt at the nearest monster. A monster in contact hurts the player; a player at
  0 health respawns at the field's centre after 3 s. A kill gives XP to players within 200 px.
- **Spawning** keeps the monster count at its target: new monsters appear 400 to 700 px from a player, never inside
  anyone's 480 x 270 view, from the core's own integer RNG.
- The core is a library: `Field::new(seed, config)`, `field.step(&inputs)`, `field.hash()`, and read access for the
  server's encoders. It takes no clock and does no I/O.

## Protocol A, version 0 (UDP, little-endian), port 7777 by default
Client to server:
- `HELLO`: `0x01, u32 proto = 1, u8 class, u8 race`
- `INPUT` (20 a second): `0x02, u32 last snapshot tick seen, u8 move (0..8, bit 7 = skill), u8 zoom (1, 2 or 4)`
- `BYE`: `0x03`

Server to client:
- `WELCOME`: `0x81, u32 player id, u32 tick, u16 tick hz, u32 field width px, u32 field height px`
- `SNAPSHOT` (10 a second), split into parts of at most 1 200 bytes:
  `0x82, u32 tick, u8 part, u8 parts`, then in part 0 only:
  `i32 origin x px, i32 origin y px` (top left of the interest box: the view 480 x 270 times zoom, plus a 64 px
  margin on every side, centred on the player and clamped to the field),
  `u16 my x - origin, u16 my y - origin, u16 my health, u16 my level, u32 players in the field,
  u32 monsters in the field, u16 server tick time in 1/100 ms`,
  then in every part: `u16 n players, u16 n crowd, u16 n monsters` and the three lists:
  - **players** (the nearest 200, never me): `u16 id, u16 dx, u16 dy, u8 class | race << 3,
    u8 flags (bit 0 faces left, bit 1 moving, bit 2 hurt this tick)`: 8 bytes;
  - **crowd** (players beyond the nearest 200, at most 1 000): `u16 dx, u16 dy`: 4 bytes;
  - **monsters** (the nearest 1 500, sorted by id): a varint id gap from the previous monster in this part (the
    first is its id), then 3 bytes: `dx` 12 bits, `dy` 11 bits, hurt 1 bit packed low to high, and a 4th byte
    `kind` 3 bits | health in eighths 3 bits | elite 1 bit | spare.
  `dx`, `dy` are whole px from the origin.
- The core job also builds **version 1** (positions sent as changes against the last snapshot the client
  acknowledged) and reports bytes for both; the viewer needs only version 0.

## Protocol B (lockstep), measured with `realm/loadtest`
- The server sends, each tick, every player's input for that tick (packed), joins, leaves and a hash every 20 ticks.
  Lost packets are covered by repeating the last ticks until acknowledged.
- A client that joins receives the full state once (measure its size), then follows.
- `loadtest` runs a real follower: it applies the stream to its own `Field` and compares hashes. It reports bytes
  per second per client, the follower's CPU per tick, and that the hashes never differ.

## Bots
The server can fill the field with bot players (`--bots=N`): each walks toward the nearest thin spot in the horde,
kites when crowded, and clusters now and then so there are dense fights (set a share that gathers in one place:
`--rally=0.3`). Their inputs come from a seeded integer RNG outside `core`, so protocol B carries them like any
player's.

## Measurements to print (`--report=secs`), as one table
Per setting (players x monsters): tick time mean and 99th percentile, split by phase (flow, move, grid, fight,
spawn, encode A, encode B); threads used; bytes per second per client for A v0, A v1 and B (mean and 99th
percentile, with the monsters and players in view); join size for B; follower CPU per tick; hash agreement.

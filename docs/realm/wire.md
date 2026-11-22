# Wire and gateway (job W1)

What goes between a player and the realm, every number chosen and why. Code: `realm/server` (field wire, hosts) and
`realm/gateway` (accounts, towns, tickets, the bridge to the store and the loot rules).

## Field wire (UDP, lockstep protocol B)

- INPUT is `0x02, u32 ack, u8 b0, u8 zoom, u8 b1, [u32 seq, u8 n, n x u16]`. The word is `b0 | b1<<8`: the core's two input
  bytes (`IN_DIR`, `IN_SKILL1/2`, `IN_ULT`, `IN_INTERACT` in byte 0; picks and potions in byte 1). The core edge-detects
  picks and potions, so a held word is safe to repeat. Why two bytes: the old one-byte shortcut lost skill 2, the ult,
  interact and every pick, which a hero needs to bank and leave. Cost: one byte a datagram.
- HELLO appends `u64 ticket`. A ticket is how a hero reaches a field: no ticket, no join. The `Join` record carries the whole
  `Sheet` (class, level, stats, deck, belt, job) and `Outing` (what the hero carries in), so every client builds the same
  hero; `wire::put_sheet/read_sheet` are the only codec.
- Repeating a tick (from Job G): inputs are repeated `INPUT_REPEAT` = 3 times; server records are sent at once when new and
  resent only after `rtt + 1` ticks (`RESEND_SLACK` = 1) without an ack. The RTT is learned from acks as a smoothed value in
  quarter ticks (`srtt4`; whole ticks rounded to a standstill); it starts at `RTT_START` = 4. Measured on a lossy link in the
  `lockstep.rs` tests: 57,776 B against 330,456 B, worst stall 4 ticks against 13.
- `HASH_EVERY` 20 ticks (1 s) keeps desyncs visible. `MAX_DATAGRAM` 1200 stays under any common MTU. `TIMEOUT` 5 s of silence
  drops a client (a disconnect, below).

## Field hosts

- One host per field copy: its own UDP socket and thread group (`--copies`, `--fields`). It runs the 20 Hz loop.
  Joining needs a ticket the gateway issued (`HostCmd::Admit`); a ticket lives `TICKET_TTL` 30 s unused, and an unused one is
  handed back (`HostMsg::Unused`) so the hero is free again.
- A hero enters at the gate (`GATE_ENTRY_PX` 120 from it) or at her waystone for that field, with a scatter of
  `ENTRY_SCATTER_PX` 30. Each hero has tallies fed from core events (coin, xp, potions, kills).
- Result flush: when a hero leaves (gate, waystone), falls, is kicked, disconnects or the host stops, and every
  `XP_FLUSH_TICKS` 200 (10 s) for xp, the host sends a `Flush{ticket, seq, coin, xp, potions, banked, fell, left}` to the
  gateway. The applier applies it with request id `ticket<<64 | seq | attempt<<40`, so a retry is idempotent. Why the 10 s xp
  flush: a killed server loses at most 10 s of xp and nothing banked.

## Gateway (TCP)

- Frame: `u32 len, u8 type, u32 tag, body`, `FRAME_MAX` 1 MiB. `tag` pairs a reply with its request; pushes have tag 0. Thread
  per connection (reader and writer); std only.
- Login: dev (name only, `--dev-login`); Steam answers DISABLED until the Steam job. Character list, create, rename, delete and
  undelete heroes (the store's rules: name 3 to 16 letters, digits, `'` `-`, first a letter).
- Town: rooms of `ROOM_MAX` 100 heroes, `STEP_HZ` 10 steps a second with a snapshot to every member (id, x, y in whole px,
  direction). Town is `TOWN_PX` 4096 square, walking at the field speed. Chat: `CHAT_MAX` 200 chars, a burst of
  `CHAT_BURST` 5 lines, one back a second. A hero is in exactly one place, Town or Field, tracked by the gateway.
- Field ticket: only for a hero who is in no field; a ticket locks the hero (BUSY until her result is applied).
- Store calls (bank, mail, spends, smith) all go through `ops::who_may` as the account (`Who::Owner`). Mail to another
  player's hero is sent as the server after checking the sender owns the sending hero.
- Loot: kills roll in the applier thread with a server secret (kept in `DB.secret`) and `RollKey{field_seed, tick, index,
  slot}`, so the client cannot influence a roll. Kept drops go through `deliver`; common items and materials wait in the
  ticket's `Haul`, banked with the coin at a bank flush, halved by a fall. First boss kills are remembered per hero in
  `DB.bosskills` (one `hero boss` line, fsync'd), because the store has no such record.
- Disconnect: half the haul's coin is lost (`coin/2`) and the rest banked. Gate, waystone, kick and stop bank everything.

- Type bytes are owned per module in one table, `gateway/src/proto/ranges.rs` (core W1, economy E1, social T1, world W2,
  homes H1, reserved pvp R3 and steam P1; a test fails on an overlap or a tag outside its module's span). The core's
  messages are `proto/base.rs`; each other module's `Req`/`Resp` variants are thin wrappers coded and served by its own
  `gate.rs` (`proto::WireModule`), registered with one line in `proto::MODULES`. Decoders refuse what they cannot read
  whole, cap every count at the bytes left, accept flags only as 0 or 1, and re-encode to the same bytes:
  `proto/fuzz.rs` checks it with 200 000 seeded cases a test run (`REALM_FUZZ_CASES`, `REALM_FUZZ_SEED` for more).
- Social calls (job T1): requests 0x40..0x5B, reply 0x90, push 0xB0, error `MUTED` 17; see `social.md`. A connection's writer
  ends on an empty frame (the moderators' "end this session").

## Proof

- `gateway/tests/gateway.rs`: login, names, towns, chat, snapshots, tickets, bank, mail, spends, smith.
- `gateway/tests/kill.rs`: the real binary; a hero banks; a second outing is running; SIGKILL; reopen the store: nothing
  banked is gone, `verify` is clean, a restarted server logs her in. About 90 s.
- `realm-soak --bots=40 --secs=7200 --fast`: bots through the whole stack, one `SOAK ok ...` line. The station word is `soak`
  (role in `tools/station/roles.txt`, `ubuntu`).

## Open questions

- Leaving by waystone in the core discards the coin carried (no Bank event). That is a core (R2) question.
- Bots with a crowd of monsters on a waystone cannot hold interact to leave (every hit breaks the hold); they bank and then
  disconnect. Is that the intended pressure on a waystone?
- Town speed equals field speed; no town collision or zones yet.
- `FRAME_MAX` and the chat limits are guesses; no crowd has played them.

# The world (job W2)

The realm's one clock, copies of every field that open and merge, the queue, vault instances, boss news and the
chests the hosts' REWARD events pay (rules sections 8, 10 and 11). Code: `realm/server` (`realm_clock.rs`,
`world.rs`, `driver.rs`, `host.rs`, `lockstep.rs`) and `realm/gateway/src/world/` (`mod.rs`, `copies.rs`, `wire.rs`,
`week.rs`), the binary `realm-world`. Tests: `gateway/tests/world.rs`, unit tests in each file.

## The realm clock

- One clock in ticks (`RealmClock`), owned by the gateway. A live realm runs it from an epoch kept beside the store
  (`realm.db.epoch`, unix ms written the first time), so a restart does not move a tide. `--clock-speed=N` (dev) runs
  it N times faster; tests use a manual clock or a fast one.
- Every field host reads it each tick. When its field's clock is more than `CLOCK_SLACK` = **10 ticks** (0.5 s) off,
  the host puts the realm's value into that tick's record (`TickRec::clock`, flag bit 1 of the record's last byte),
  so the host and every lockstep follower set it at the same tick and the hash stays equal (tested: a follower
  through a clock jump into a tide and to a boss). Why 10: a host that sleeps a little long catches up by itself,
  and most records carry no clock. A vault keeps its own clock (its timeline is its own).
- Tides, altars, the eight field bosses and DEATH run in the core from the clock (R2), so every copy of a field
  surges together and the world boss rides in every copy of its field.

## What a player sees

- `realm_server::world::world_view(&Field)`: clock, tide running, ticks to the next tide and left of this one, the
  six altars (state, held, health), quick, the boss up now (row, name, health, max health, place in px, world,
  ticks until it leaves), the next field boss and when it rises, the world boss's next field and when. The game
  window's `world` dictionary has them all (`world["boss"]` with `name`, `health`, `max_health`, `x`, `y`, `world`,
  `leaves_in`; `tide_in`, `tide_left`, `altars`, `next_boss`, `next_boss_in`, `world_field`, `world_in`, `clock`),
  read from the follower's own field (`realm/godot`, a small addition). The HUD's tide countdown now reads
  `tide_in`/`tide_left` (it counted `tick % 30 min`, which is not the realm's schedule).
- `realm_board(clock)` and `WReq::Board`: every field's tide and boss countdowns, the world boss's next ride, the
  copies with their heroes, the queue's length and vaults open (for town).
- News to every logged-in connection (`WResp::News`): a field boss **10 minutes** before it rises
  (`BOSS_ANNOUNCE`), the world boss **30 minutes** before it rides (`WORLD_ANNOUNCE`), once each.

## Copies of a field (rules section 11)

`copies.rs` is a pure planner the world thread asks every `WORLD_STEP_MS` = **250 ms** (a queue moves and a copy
opens within a quarter second).

| Number | Value | Why |
|---|---|---|
| `cap` | 1,000 | rules |
| `open_at` | 800 | rules: a new copy opens when **every** open copy has passed it |
| `merge_under` | 500 | rules: the two emptiest copies together |
| `max_copies` | 4 a field | one box carries about 4,000 heroes (`realm_cap`); a fifth copy would only queue |
| `merge_grace_ms` | 60 s | a dip that refills does not close a copy |

- Load is counted in **tickets** (heroes in the copy and on their way), not the host's last count, so a burst of
  arrivals cannot overfill a copy. Arrivals and parties go to the emptiest open copy with room for all of them.
- A merge closes the emptier copy (ties: the newer) into the other, only while no tide runs and no boss is up in
  either ("at the end of its tide": altars and a boss fight are not cut off). One merge at a time per field.
- Moving a hero: `HostCmd::MoveOut` takes her out through the tick record's leave (followers do the same); her
  flush so far goes to the store; `HostMsg::Moved` carries her `Transfer` (sheet, outing state with the haul's coin,
  ring) and her ticket's last flush number. The gateway admits her to the other copy with the **same ticket**
  (her haul and roll gate stay keyed to it) and the flush numbers going on (so the store's request ids never
  repeat), arriving at `Field::ring_point` of the same ring. `transfer_of` + a join at `ring_point` are tested to
  equal the core's `transfer_out` / `transfer_in` (same outing, same hash).
- Her client gets `WResp::Moved` (field, copy, port, ticket) and sends HELLO there with the same ticket
  (`bot.rs` does; tested over UDP with a lockstep follower). If she never arrives (30 s, the ticket's life), she is
  banked as a disconnect: half the haul's coin. A closing copy whose heroes are all gone is stopped cleanly.
- Every copy of a field shares the field's seed (the same map: waystones and the gate where players know them);
  the loot rolls mix the host's id into the roll key so two copies never roll alike.

## The queue

- `realm_cap` = **4,000** tickets (fields and vaults) for one box (the gate of rules 13 is 1,000 heroes a field on
  4 cores; four busy fields is what one box carries). When the realm is full, or every copy of her field is full and
  the field has its `max_copies`, a ticket request answers `WResp::Queued { place, of }` and she leaves town for the
  queue. Places are pushed as they change; the ticket comes as a `Resp::Ticket` push. First come, first served; a
  waiter for a full field lets the next one by. `WReq::LeaveQueue`, or closing the connection, leaves it.

## Vaults (rules section 10)

- `WReq::VaultOpen { hero, vault, seals }`: the leader pays one VAULT KEY of the vault's field (row `field`: keys of
  THE MOON MARSH open THE MIRE CRYPT, and so on), debited by the server with a ledger row. The class trial (row 5)
  needs no key and is from class level 10. A vault host opens (its own seed, `vault_monsters` = **4,000**, one
  thread) and she gets `WResp::Vault { code, ticket, port }`. The party joins with `WReq::VaultJoin { code }` while
  the run goes on and there is room (`party_max`, 8); the code is the invitation (T1's parties will send it).
- At most `vault_max` = **64** open at once (64 x 8 = 512 heroes, about an eighth of the box).
- Time limit and clean close: the core runs the timeline (15 minutes, 3 of overtime). The host closes **30 s**
  (`VAULT_LINGER_TICKS` 600: the chest is shown) after the run is WON or LOST, at once when every hero has left,
  after **60 s** (`VAULT_EMPTY_TICKS`) when nobody came, and **2 minutes** past timeline and overtime as a guard
  (`VAULT_GUARD_TICKS`). Closing banks everyone (`Leave::Vault`, Outing `left` 5) and stops the host; the gateway
  removes it. A vault nobody entered refunds its key.
- The chest (`R_VAULT_CHEST`): the loot crate has no vault source, so a vault chest is THE ARCHLICH's boss chest
  (rolls from RARE, the card and trophy rolls) once for each two of `chest_rolls(seals)` (2 and one a seal): 1 to 5
  rounds. The first round carries the Archlich's first kill. A lost vault pays its coin in the field (the haul).

## Chests

The host turns each REWARD event into `HostMsg::Reward` with the ticketed heroes past the floor (and the boss
killed that tick, for a boss chest's first kill); the gateway rolls each one's chest (`Gateway::reward`): TIDE
CACHE, BOSS CHEST, the world boss's RELIC (best hundred) and EPIC, the vault chest. Everything is written at once
(chests are not part of the haul); the coin part was paid in the field and is banked with the haul.

## Heroes the host plays (dev bots)

`WReq::BotTicket { hero, field, ticks }` (only with `--dev-login --dev-bots`): a real hero from the store with a real
ticket, played by the core's class bot on the host (`driver.rs`): she fights for `ticks`, walks to the nearest
waystone and holds interact until she banks and leaves; if she is not out `DRIVE_HOME_TICKS` = **1,200** (60 s)
later she is recalled (banked, as a kick). She patrols the middle ring (`DRIVE_RING_PX` 4,200) with objectives
on. A vault's `drive_ticks` does the same in a vault. Her inputs go into the tick record like a player's. Why: a
realm of hundreds of bots then costs no follower simulations, which is what lets a week be lived in a test.
`WReq::Recall` takes such a hero out; a connection that ends recalls its own.

## Outing codes (the Outing push's `left`)

0 gate, 1 waystone, 2 disconnect, 3 kicked or recalled, 4 shutdown, **5 her vault closed**, **6 her field's host died**
(what was banked is kept, the haul is lost, she is free at once), **7 the ticket was never used**, 255 still there.

## A host that dies

A host whose thread ends without `Closed` (a crash; `HostCmd::Abort` in tests) is taken for dead after
`DEAD_GRACE` = **1 s** (its last messages are applied first). Its tickets are dropped: banked coin, XP and kept
drops are already in the store; the haul is lost, as when the whole server is killed (W1's rule). The planner opens
a new copy at once when the field has none.

## Wire

`T_WORLD` 0x60 (a sub-byte after it), `R_WORLD` 0x91, push `P_WORLD` 0xB1 (T1's social has 0x40..0x5F, 0x90, 0xB0) (tag 0). Requests: 1 Board, 2 LeaveQueue
(u64 hero), 3 BotTicket (u64 hero, u8 field, u32 ticks), 4 Recall (u64 hero), 5 VaultOpen (u64 hero, u8 vault, u8
seals, u32 drive_ticks), 6 VaultJoin (u64 hero, u64 code, u32 drive_ticks). Replies and pushes: 1 Board (u64 clock,
u8 n, n x (u8 field, u32 tide_in, u32 tide_left, u8 boss, u32 boss_in), u8 world_field, u32 world_in, u32 queue,
u16 m, m x (u8 field, u8 copy, u32 heroes), u32 vaults), 2 Queued (u64 hero, u8 field, u32 place, u32 of), 3 Vault
(u64 code, u8 vault, u8 seals, str host, u16 port, u64 ticket), 4 Moved (u64 hero, u8 field, u8 copy, str host, u16
port, u64 ticket), 5 News (u8 kind 1 field boss 2 world boss, u8 field, u8 boss, u32 in_ticks). A tick record's
last byte is now flags (bit 0 hash, bit 1 clock) followed by the hash and the clock.

`realm-gateway` flags: `--realm-cap --copy-cap --open-at --merge-under --max-copies --vault-max --vault-monsters
--dev-bots --clock-speed`. New copies the world opens take free ports (the client is told the port).

## Heroes play as their class (the NOVICE question)

The gateway already carried the whole `Sheet` (class, class level, job, gear, deck, belt) into the field (W1).
What a player sees as "made a class, plays a NOVICE" is the core's rule of rules section 3: below class level 10
every class is a NOVICE (`core/src/hero.rs`, `Hero::enter`), and a new hero is level 1. Tested end to end
(`heroes_play_their_own_class_level_job_and_gear`): a PRIEST of class level 45 with a job and worn gear is a PRIEST
of level 45 with that job and those gear points in a lockstep follower's field; a new PRIEST is a NOVICE of level 1.
A field also caps a hero at its top level + 2 (rules section 6), so a level 45 hero on THE FOOL'S ROAD plays at 12.
Changing either is a rules decision (open question 1).

## The proof

`a_compressed_week_of_bot_play_loses_and_doubles_nothing` (`gateway/tests/world.rs`, `run_week`): six fields and
vaults, 32 bots through the gateway's TCP wire (log in, make a hero, town, queue, a host-played outing or a vault
by key and code, bank the coin, log out, a pause longer in the realm's night), the realm clock at a week in 30 s
but never more than 4.5 realm minutes ahead of the slowest field copy (`CLOCK_LEAD`, under a tide's length: every
copy steps inside every tide, field boss and world boss window however loaded the box, so their counts follow the
clock, not the box; an idle box keeps the 30 s), field hosts at 250 Hz and vaults at 4 kHz, copy rules scaled (cap 8, open 6, merge under 4, three copies, grace
0.5 s), realm cap 24, and the busiest field copy killed halfway. A watcher samples every 20 ms that no hero is in
two hosts. At the end: every hero is nowhere and no ticket is left; each hero's coin in the store (bag and bank)
equals the coin the gateway reported banked for her outings, the killed host included; nobody's coin went down
across the kill; the store verifies; copies opened and at least one merge finished, the queue held and admitted
heroes, a vault closed, and the world boss rode about every six hours. (Heroes moved by a merge are counted,
not required: a merge often closes a copy its heroes have already left; the move itself is proven over the wire
by `a_player_in_a_closing_copy_is_moved_over_the_wire_with_her_haul`.) One run:

```
WORLD ok days=7.00 secs=36 heroes=32 cycles=182 outings=182 vault_runs=5 vault_joins=4 queued=161 queue_max=15
admitted=154 copies_opened=8 merges=7 moved=3 peak_copies=10 peak_heroes=25 tides=894 bosses=434 world_bosses=39
news=82 keys=5 vaults_closed=5 host_killed=1 tickets_lost=6 lost_outings=6 doubled=0/1471 coin_mismatch=0
kill_losses=0 left_placed=0 errors=0 verify=ok items=215 stacks=204 ledger_rows=2472
```

At this speed a five-minute tide lasts a few host ticks, so no tide is won and no field boss is killed in the
week; the chests are proven on their own (`a_reward_rolls_a_chest_for_each_hero_with_a_ticket`, and the host's
`a_reward_event_names_its_ticketed_heroes...` with a lost vault). The long version is the station word `world`
(Ubuntu, after each realm merge): `realm-world --bots=200 --days=7 --secs=7200` with hosts at 20 Hz, 2,000
monsters a field, copy rules cap 60 / open 45 / merge 30 / grace 60 s, realm cap 150, eight vaults, five-minute
outings, where tides last 3.5 s of real time. A three-minute smoke of those settings (100 bots, cap 30) gave
`WORLD days=7.00 outings=236 vault_runs=3 queue_max=34 copies_opened=2 merges=1 moved=0 tides=3793 bosses=997
world_bosses=53 host_killed=1 tickets_lost=18 doubled=0/8904 coin_mismatch=0 kill_losses=0 verify=ok`.

## Open questions

1. **NOVICE below level 10.** Heroes are made as a class (the shell's builder) but rules section 3 makes them NOVICEs
   until 10, and the class trial vault is built (row 5, keyless) but no call turns its win into anything. Either the
   core drops the NOVICE rule for heroes made as a class, or the builder makes NOVICEs and the trial's win sets the
   class. Not changed here (the core is not this job's).
2. **The Godot client and `WResp::Moved`.** The realm client (C1/C2) does not yet follow a move: until it does, a
   player whose copy closes is banked as a disconnect after 30 s. `bot.rs` shows the handling (HELLO the new port with
   the same ticket).
3. A tide is never won in the compressed week; the station's week at 20 Hz is where won tides and killed bosses with
   real chests show. The world boss rides in every copy of its field (each copy's own DEATH and chest): intended by
   "every copy surges together", but it multiplies RELIC rolls by the copies.
4. A vault's party is anyone with the code until T1's parties send it. Seals are chosen by the leader with no
   unlock rule.
5. `realm_cap` 4,000 and `vault_max` 64 are guesses for one 4-core box; the load test should set them.

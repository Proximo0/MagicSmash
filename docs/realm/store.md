# Horde & Hearth: the store (`realm/store`)

The store keeps everything that lasts: accounts, heroes, items, stacks (coin, potions, materials, runes, keys, pages,
monster cards), entitlements and the ledger. The owner's rule is that everything is kept: no item or coin is lost or
copied, whatever crashes. The gateway is the only caller. The crate is its own cargo workspace (`realm/store/Cargo.toml`,
`Cargo.lock`), std plus `rusqlite =0.37.0` with `bundled`, `backup` and `hooks` (all of these are features of the one
crate). `realm/store/check.sh` builds it, runs the tests and a short crash fuzz, and prints one line.

## How it works

- **SQLite** with WAL, `synchronous=FULL`, foreign keys on. One writer thread owns the write connection. Callers send
  commands through a channel and wait for the reply. A second, read-only connection serves reads. A reader sees
  every change whose reply has already been returned.
- **A savepoint that fails.** If a command's savepoint cannot be rolled back or released, the writer rolls back
  the whole batch and answers every command in it with `Db`, which is not recorded, so each one can be retried.
- **Group commit.** The writer starts a transaction with whatever commands are queued (up to 512) and gives each one
  its own savepoint, so a command that fails rolls back alone. It commits once, and only then sends every reply.
  `Options::group_window` can make it wait for more commands after the first (the design said 20 ms). The default
  is 0: commands that arrive during a commit join the next batch. See *Measurements* for why.
- **Idempotency.** Every request carries an id (`u128`). The `requests` table keeps each id with a hash of its
  arguments (actor and command), its reply and the range of ledger rows it wrote, in the same transaction as the
  change. A repeated id gets the first reply back and changes nothing. A repeated id with different arguments gets
  `RequestMismatch`. Domain errors (Full, Missing and the rest) are replies too: they are kept, and a repeat returns
  the same error even if conditions have changed since. A caller that wants a new attempt uses a new id. `Db` and
  `Closed` are not kept, so that request may be retried with the same id.
- **Ledger.** Every change writes ledger rows in the same transaction. A row has seq, the caller's time, the
  request id, the actor, op, the item or stack kind, from (kind, owner, tab, slot) and from account, to (the same)
  and to account, count, `minted`, reason and data. A MINT row's data is the item's full spec, so replaying the
  ledger from empty rebuilds every item and stack exactly.
- **Crash points** (`src/crash.rs`) are inert unless the fuzz arms them through `REALM_STORE_CRASH=site:n`.

## Schema (version 2)

`schema_version(version)`. Migrations run at open, one transaction per step (`src/schema.rs`). Version 1 is the
first design. Version 2 is the lead's addition: item origins, account flags and ledger parties, backfilled from the
ledger. `tests/schema.rs` builds a version 1 database with data, opens it, and checks the backfill and `verify`.

| Table | Columns | Rules |
|---|---|---|
| accounts | id, steam_id UNIQUE, dev_name UNIQUE, created, banned_until, flags, drops_percent | a steam id or a dev name |
| entitlements | (account, kind) PK, count | kind 1 bank tab, 2 hero slot, 3 look |
| purchases | purchase PK, account, kind, count, time | one grant per purchase id |
| heroes | id, account, name, name_key, name_held, race, class, job, look, class_level 1..60, class_xp, stats "6 numbers", unspent, deck, belt, waystones, self_found, created, deleted_at | UNIQUE(name_key) WHERE name_held: names are unique without regard to case |
| owned_cards | (account, card) PK | deck cards learned from pages |
| items | id AUTOINCREMENT (never reused), base, gear_slot 0..5, item_level, rarity 0..4, lines "stat:pts,...", sockets 0..2, sock0, sock1, plus, bound, place_kind, place_owner, place_tab, place_slot, minted, origin_account, origin_hero, mint_seq | UNIQUE(place): a place holds one item; the place columns are NOT NULL: an item has exactly one place |
| stacks | (owner_kind, owner, kind) PK, count CHECK >= 0 | a stack at 0 is deleted |
| ledger | seq PK, time, request, actor, op, item, stack_kind, from_kind/owner/tab/slot, to_kind/owner/tab/slot, count, reason, data, from_acct, to_acct, minted | indexes on request, item, from_acct, to_acct, guild source |
| requests | id PK (16 bytes), args, op, reply, ledger_first, ledger_last, time | |

**Places** (kind, owner, tab, slot): BAG 1 (hero, 40 slots), WORN 2 (hero, slot = gear slot, 6), BANK 3 (account,
tab, 100 a tab; 1 tab free, more by entitlement), MAIL 4 (hero, no limit: where a haul overflows), MARKET 5
(listing, 1), TRADE 6 (session, 16; session 0 is the trade commit's staging and is always empty between
transactions), HOUSE 7 (account, 200), GUILD 8 (guild, 8 tabs of 100). Limits are in `types::limits`.

**Stack kinds** (`StackKind(u32)`): coin 1; potion 100+p; material 1000+m; rune 2000+stat*10+grade (grade 1..3);
vault key 3000+field; page 4000+card; monster card 5000+card. In a bag, potions, runes, keys, pages and monster cards
take one slot per kind. Coin and materials take none, and no stack takes a slot outside the bag. Stack owners are
containers (kind, owner); bank stacks belong to the account, not to a tab.

## The trait

`Store` (`src/lib.rs`): `submit(Request) -> Result<Reply>` and `submit_batch(Vec<Request>) -> Vec<Result<Reply>>`
for changes, the reads below, and a typed method for each command. `Meta { id, actor, now }`: actor 0 is the server.
For any other actor, the store checks that the account exists and is not banned (`Banned`).

### Who may run what

The rule: an account actor may only do what a player could do with its own things. Everything that creates value,
removes someone else's, or changes standing belongs to the server (actor 0). The rule is one table,
`ops::who_may(&Cmd) -> Who`, which has no wildcard, so a new command does not compile until it has a row. `apply`
refuses a server-only command from an account with `NotYours` before doing anything else.

| Who | Commands | What an account may touch |
|---|---|---|
| server only | account_by_steam, account_by_dev_name, apply_flags, clawback, grant_entitlement, mint, stack_credit, stack_debit, apply_outing, sell_item (the price is the server's), trade_commit (the gateway commits after both players confirm; the store cannot see consent) | nothing |
| server, or the owner on its own things | hero_create, hero_rename, hero_delete, hero_undelete, hero_save, learn_page (its own page stack), move_item, socket, unsocket, stack_transfer | its own heroes; its own bags, worn gear, bank, house, and mail to its own heroes. Guild banks, market listings and trade sessions are the server's (membership lives in the gateway; job T1 will pass it in). In hero_save an account may not raise class_level or class_xp; it may respend points, choose a job, and set the deck and belt within the rules |

`tests/auth.rs` walks every command three ways: as a player against another account's things (refused with
NotYours, state unchanged), as the server (works), and as the owner on its own things (works exactly for the
Owner rows). The test fails to compile if a command has no case. It also reproduces the four holes the review
found: a one-sided trade, clawback, self-unlocking or banning with apply_flags, and self-granted entitlements.
Each is now refused.

| Operation | Signature | Errors besides Banned / NotYours / RequestMismatch / Db |
|---|---|---|
| get or create by Steam | `account_by_steam(m, steam_id) -> AccountId` | |
| get or create dev account | `account_by_dev_name(m, name) -> AccountId` | BadName |
| ban wave | `apply_flags(m, Vec<FlagChange{account, flags, drops_percent, banned_until}>, reason)` | Missing (no change applied), Invalid (unknown bit, percent > 100) |
| hero create | `hero_create(m, account, name, race, class, look, self_found) -> HeroId` | Full (slots), NameTaken, BadName (3 to 16 ASCII letters, digits, ' or -, starting with a letter), Invalid, Missing |
| rename | `hero_rename(m, hero, name)` | NameTaken, BadName, Deleted, Missing |
| delete (soft) | `hero_delete(m, hero)` | Deleted, Missing |
| undelete | `hero_undelete(m, hero)` | Expired (after 7 days), Full (slots), NameTaken, Invalid (not deleted) |
| save progress | `hero_save(m, hero, Progress{job, class_level, class_xp, stats[6], unspent, deck, belt[3], waystones[6]})` | Invalid (level or xp going down, stat points not equal to level - 1, deck over 20, duplicate or out-of-range card, belt not potions), Missing (card not owned), Deleted |
| learn a page | `learn_page(m, hero, card)` | Insufficient (no page), Invalid (owned already, or not a page card) |
| mint | `mint(m, Dest, ItemSpec, reason) -> (ItemId, Place)` reason drop, cache, chest, merchant, grant, haul | Full, SlotTaken, LevelTooLow (worn), Invalid (spec, reason, market or trade), Missing |
| move | `move_item(m, item, Dest) -> Place` among bag, worn, bank, mail, house, guild | Full, SlotTaken, LevelTooLow, Invalid (wrong worn slot, already there, market or trade), Deleted, Refused, Missing |
| sell | `sell_item(m, hero, item, price) -> coin after` destroys a bag item and credits coin, all in one transaction | NotYours (not in this hero's bag), Missing |
| socket | `socket(m, hero, item, socket, kind)` one rune or card from the bag into an empty socket of a carried item | Insufficient, Missing (socket), Invalid (full, not socketable) |
| unsocket | `unsocket(m, hero, item, socket)` back into the bag | Missing (empty), Full (no bag slot for a new kind) |
| credit | `stack_credit(m, Owner, kind, count, minted, reason) -> balance` | Full (new kind in a full bag), Invalid, Missing |
| debit | `stack_debit(m, Owner, kind, count, reason) -> balance` | Insufficient |
| transfer | `stack_transfer(m, from, to, kind, count) -> source balance` | Insufficient, Full, Refused, Invalid |
| outing delta | `apply_outing(m, hero, OutingDelta{coin, xp, levels, items, stacks, potions_used, waystone}) -> Vec<(ItemId, Place)>` uses up potions first, then banks coin, stacks and items (bag first, overflow to the hero's mail: nothing banked is dropped), then adds xp, levels and unspent points | Insufficient (potions: nothing applied), Invalid, Deleted |
| trade commit | `trade_commit(m, TradeSide{hero, items, stacks}, TradeSide)` bag to bag both ways at once; `m.id = trade_request_id(a, b, session)`, a hash of both lists that is the same from either side | Bound, NotYours (item not in the giver's bag), Insufficient, Full, Refused, Invalid |
| entitlement | `grant_entitlement(m, account, kind, count, purchase) -> (granted_now, total)` once per purchase id; a second grant of the same purchase returns (false, total) | Invalid (same purchase, other terms) |
| clawback | `clawback(m, ClawbackPlan{items, stacks}, reason) -> (removed, missing, shortfall)` | Invalid |
| reads | `account`, `hero`, `heroes(account, include_deleted)`, `item`, `items_at(kind, owner)`, `stack(owner, kind)`, `stacks(owner)`, `entitlements`, `trace`, `trace_forward`, `clawback_plan`, `verify`, `backup(path)`, `stats` | |

## Bots and farms: origin, flags, trace, clawback

- **Origin.** Every item keeps `origin_account`, `origin_hero` (who it was minted for) and `mint_seq` forever,
  through moves and trades. Every credit has a `minted` flag: drops, hauls, grants and merchant coin for a sold
  item mint new value; a bought potion or an unsocketed rune does not. Each ledger row names the account on each
  side (`from_acct`, `to_acct`), so you can sum per account what it minted and what it sent to whom.
- **Flags** (`flags::*`, set by `apply_flags` with a reason, one ledger row FLAGS per account): TRADE_LOCKED: no
  value moves between the account and any other party, in either direction. That covers trade commit, moves and
  stack transfers to or from other accounts' bags, mail, banks and houses, and guild bank deposits and withdrawals.
  All of these refuse with `Error::Refused`, which says nothing more. The account still plays inside itself (bag,
  bank, house, mail between its own heroes, sell, outings). SHADOWED and DROPS_REDUCED (with `drops_percent`) are
  only recorded, for the gateway and the loot service. WATCHED is a marker. A ban is `banned_until`.
  `apply_flags` takes a list and applies it in one transaction (a ban wave).
- **trace(account)**: every item it ever minted, with its current place and holder (None once sold or clawed); per
  stack kind: minted, spent (debited out of the game), sent to each party, received from each party, held now.
- **trace_forward(account, depth)**: depth 1 is every move of value from the account to another party. Each next
  depth follows only what the receivers got from the level before: items by id, and stack kinds after the seq they
  arrived. Parties are accounts, guild banks, market listings and trade sessions, so a guild deposit and a
  withdrawal are two hops.
- **clawback** (op CLAWBACK): removes the listed items wherever they are, socket contents included, and debits the
  listed stacks to zero at most. If a rune or card stack falls short, it takes from sockets of items in that
  container. Missing items and the shortfall are reported. **clawback_plan(account, since_seq)**: the account's
  minted items that still exist, plus per stack kind up to the amount it minted, taken from its own holdings first
  and then from each party it sent that kind to (up to what was sent). Coin is fungible, so the plan takes coin a
  buyer held whatever its source, and a one-hop plan does not reach value passed on to a second hop (use
  `trace_forward` to build a wider list).
- Tests: `tests/flags.rs`. A farm mints, trades to three buyers who pass value on (one through a guild bank).
  Trace finds all of it; `trace_forward` finds it at depth 2 and 3 and does not follow a buyer's own item. The
  clawback removes exactly the farm's items, and `verify` passes. A TRADE_LOCKED account is refused on all 16
  paths that move value between parties, and nothing changes. A ban wave with one bad entry applies nothing.

## Invariants (`Store::verify`, `realm-store verify`)

Within one read transaction:
1. `quick_check` and `foreign_key_check`.
2. Each place holds at most one item, and the trade staging place is empty.
3. Slot limits: bag slots below 40, and per hero items plus slot-taking stack kinds at most 40. Worn items sit in
   their gear slot and are no higher than the hero's level. Bank slots below 100 and tabs open by entitlement.
   House below 200, guild below 100 in 8 tabs. Hero and account owners exist. Each account has no more live heroes
   than its slots.
4. No stack below zero and none on worn gear; sockets hold only runes and cards within the item's socket count.
5. **Replay**: the whole ledger, applied in seq order to an empty state, gives exactly the current items (place,
   spec, sockets, origin, mint seq) and the nonzero stacks. During replay, every move starts from the item's
   current place and no stack goes below zero.
6. **Applied once**: each request's ledger rows fill exactly the range its record names, contiguously. Every ledger
   row's request is recorded, and every recorded reply decodes.

## Backup and restore

- `realm-store backup <db> <file>` (or `Store::backup`) uses SQLite's backup API in one step from a read-only
  connection. That reads one WAL snapshot, so writers keep committing, and the copy is that snapshot. The copy is
  then verified (replay included).
- `realm-store restore <file> <db>`, with the server stopped: verifies the backup and refuses one that fails, copies
  it over the database with the backup API, opens it (running any migrations), and verifies again.
- `realm-store stats <db>` prints counts and a digest of items and stacks, to compare two databases.
- `realm-store trace <db> <account> [depth]` prints a trace and its onward hops.

## Proof

**Unit tests** (30, `cargo test`, 7 of them in `tests/auth.rs`): every operation and each of its errors, idempotency of each (a repeat returns
the first reply and changes nothing; the same id with other arguments is refused; a failed request keeps its
error), batches where one command fails alone, group commit from 12 threads, backup while writes continue and
restore, migration from version 1 with data, and `verify` catching a coin from nowhere, an unledgered move and a
request applied twice.

**Crash fuzz** (`realm-store fuzz --seed=N --ops=N --kills=N`). A seeded stream: 60 accounts, 20 hero-slot
purchases, 200 heroes, then random outing deltas, mints, moves, sells, sockets, unsockets, stack credits, debits
and transfers, trades, saves, renames, deletes and undeletes, entitlements, flag waves, clawbacks (some from
`clawback_plan`), learned pages, players acting on things that are not theirs, and repeats of old request ids (4%). Server-only
commands go as actor 0, except 3% of them, which go as a random player and must come back NotYours (or Banned).
It runs in batches of 1 to 8 requests per transaction through child processes. Each child is armed to `abort()` at
the Nth pass of one site: between statements, inside a statement (progress handler), inside the commit (commit
hook, before the WAL write), before COMMIT, or after COMMIT before the reply. The parent learns each site's rate
per op from the children and aims for the requested number of kills. The child prints each batch before submitting
it and each reply after. After every child the parent reopens the database, runs `verify`, and checks that every
reply it was told is recorded unchanged (all the new ones, plus 200 old ones at random; all of them at the end). It
then resubmits the batch that was in flight with the same ids, as a real caller retries. A repeat of an old id must
return the first reply. The stream is a function of the seed and the database state, and the kills are counted
passes, so a run repeats exactly.

| Run | Result |
|---|---|
| seed 2026, 100,000 ops, 300 kills | ok in 128 s: kills by site stmt 87, progress 71, commit 41, aftercommit 47, beforecommit 54; 302 children, 302 verifies; 95,974 distinct requests acknowledged (24,027 of them domain errors); 300 batches resubmitted, 287 requests of them already committed before the kill and answered from the record; final 21,926 items, 7,829 stacks, 163,302 ledger rows |
| the same again | identical: digest 2d7dcb4316164c56 both times |
| check.sh: seed 7, 5,000 ops, 20 kills | ok in about 2 s (the whole check about 15 s) |
| after the authorization fix: seed 2026, 20,000 ops, 60 kills | ok in 11 s, 19,228 requests acknowledged, 45 resubmitted requests already committed |

The fuzz found nothing in the final code. To show it can catch a crash bug, a mutant that commits each change
before writing its request record was caught on the first kill: "ledger rows of request ... with no request
record". The unit tests found two bugs while the code was being written. A stack clawback took only one socket of
an item that held the kind in both. A bag move with no slot named slipped past "already there".

## Measurements

This box: 4 cores shared with two other Rust builds (load about 2), a virtio disk. `realm-store bench`: 60
accounts and 200 heroes, N callers each owning its heroes, 5 s a phase, `synchronous=FULL`. Outing delta: coin, xp,
one material, an item 12% of the time. Move: one item bag to bank and back. The backup phases run
`backup` plus a full `verify` of the copy in a loop beside the writers.

| Callers | Window | Outing deltas/s | Moves/s | Outing/s with backup | Moves/s with backup | p50 / p99 latency (moves alone) |
|---|---|---|---|---|---|---|
| 1 | 0 | 3,514 | 3,241 | 2,875 | 2,724 | 0.3 / 1.8 ms |
| 16 | 0 | 7,669 | 7,240 | 5,652 | 5,434 | 1.8 / 7.0 ms |
| 64 | 0 | 10,178 | 10,248 | 8,085 | 7,209 | 5.0 / 12.3 ms |
| 200 | 0 | 10,279 | 10,729 | 8,035 | 8,232 | 17.3 / 33.9 ms |
| 64 | 20 ms | 2,445 | 2,509 | 2,253 | 2,227 | 25.1 / 31.1 ms |
| 200 | 20 ms | 5,280 | 5,440 | 4,560 | 4,680 | 35.9 / 51.6 ms |

The target was 2,000 operations a second. It is met by one caller, and 64 or more callers give about 10,000.
**What limits it:** with group commit the fsync is shared, so the ceiling is the writer thread's CPU: about 100 µs
of SQL a command (the request lookup and record, the checks, the row changes, the ledger rows). A backup costs about
20%, mostly the verify of each copy competing for the cores. A fixed 20 ms window caps throughput at callers / 20 ms
and adds 20 ms to every reply, so the default window is 0. On a disk where fsync takes milliseconds (a consumer SSD
or a spinning disk), one caller drops to 1/fsync a second, but many callers still share each fsync. This VM's fsync
is fast (0.3 ms for a whole command at one caller), so measure again on the host PC with `realm-store bench`.

## Open questions

- A failed request keeps its error: retrying with the same id after making room still says Full. That is the
  design ("a repeated id returns the first reply"); the gateway must take a new id for a new attempt.
- Mail between a TRADE_LOCKED account's own heroes is allowed (it moves no value to another account); the lead's
  list said "mail with attachments" refuses. One line in `check_flow` changes that.
- An equip onto an occupied worn slot is `SlotTaken`; the client unequips first (two requests) or the gateway may
  want a swap operation.
- Market listings and trade sessions exist as places, but nothing moves items into them yet (job E1). Guild
  membership is not in the store, so guild bank moves are server-only until T1 passes membership in.
- Deleted heroes keep their items forever. A name frees 7 days after deletion, when another hero claims it.
- The deck rule is ambiguous (rules section 5: "each even class level to 24 adds one" against section 9: "cards 13
  to 30 are found as pages"). The store owns cards 0 to 11, unlocks 12 to 23 at even levels 2 to 24, and owns any
  card learned from a page.

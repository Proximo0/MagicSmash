# Horde & Hearth: homes and the shared places (job H1)

Code: `realm/gateway/src/homes/` (`place.rs` places and numbers, `plots.rs` who holds what, `catalogue.rs` the carpenter,
`yard.rs`, `rest.rs`, `wire.rs`, `mod.rs` the calls), `realm/client/homes/` (the screens), small hooks named at the end.
Proof: `realm/gateway/tests/homes.rs` (24 houses, 200 bots, store verify) and the shell test's walk into a house.

## What a hero can do

She walks between **places**; each is a town room (`Towns::enter_at`, rooms are tagged with the place). The plaza is
where she arrives (the room every hero already had). From the plaza: the tavern, the market square, the training yard,
her guild's hall, and the street of houses. A house is entered from its street.

| place | kind | rooms | cap | what is there |
|---|---|---|---|---|
| plaza | 0 | opens another when full | 100 | the stations (bank, smith ...), 2 campfires, the doors to the other places |
| tavern | 1 | opens another | 60 | a hearth (a campfire), talk |
| market square | 2 | opens another | 100 | the stalls: every hero with something listed, how many, the cheapest (E1's market) |
| guild hall | 3 | one per guild | 100 | members only; the guild board (T1's guild panel); a campfire |
| training yard | 4 | opens another | 40 | the dummy; a campfire |
| street n | 5 | one per street | 100 | 24 doors, the street board |
| house (plot) | 6 | one per house | 16 | the owner's furniture |

Why those caps: the plaza and the guild hall are the town's existing 100 and the guild's 100 accounts; 60 for a pub is
a crowd; 40 in the yard keeps the dummy readable; 16 in a house (owner included) is a party plus guests.

## Streets and plots

- A street holds **24 plots** (`PLOTS_PER_STREET`). Plot ids count from 0: street 1 is 0..23. Street n+1 **opens when street n
  has 18 plots taken** (`STREET_OPENS_AT`, three in four) so a new account finds a free door on a living street.
- One house to an account (the gateway's registry is by account, like the store's HOUSE place).
- **Price** in coin, by the plot's place on the street (`tier_pct`): doors 1 to 6 (the plaza end) 200%, 7 to 18 100%, 19 to 24
  (the back lane) 70%. **Buy 60,000** at 100% (`BUY_BASE`): a third of what a hero has hauled by day 60 (economy.md: 180k), once;
  it is the house sink economy.md's open question asked for. **Rent 400 a week** at 100% (`RENT_WEEK`), one to four weeks
  ahead (`RENT_WEEKS_MAX`): 150 weeks of rent equal a purchase, so renting is how a new hero starts and buying is for the
  one who stays. Rent opens only the downstairs room; a bought house has both.
- The coin is `StackDebit` from the hero's bag by the server (reasons "house plot", "house rent"): a ledger row, coin
  destroyed. If the registry then refuses (a race), the coin is credited back ("refund", not minted).
- Rent ends: the holder has **14 days of grace** (`GRACE_MS`) to renew; the door is shut to visitors meanwhile. After that the plot
  is free to anyone; **her things stay in the store's HOUSE place** and she can pick them up from anywhere in town (the pick-up
  never needs a plot); she gets them back on the grid when she holds a house again. Giving up a house refunds nothing.
- Upgrading a rented house to bought: buy the same plot, full price (the rent already paid is not credited).
- The registry (plots, rules, names, guestbooks) is the gateway's own small file `<db>.homes` (tab-separated lines, replayed at
  start; in memory when no file; a last line cut mid-append, by a crash or a backup copy, is dropped from the file at
  start so the next write begins a whole line). It is backed up with the store (`realm_ops::sides::HOMES`). The **items
  and coin are the store's**; the registry owns no value.

## Furniture, trophies and the grid

- A house is **two 10 x 10 rooms** (downstairs cells 0..99, upstairs 100..199): `cell = room * 100 + y * 10 + x`. The cell is the
  item's **slot in the store's HOUSE place** (200 slots: the store's own limit). One thing to a cell; a piece fills one cell.
  Drawn in the 4096 px room with 128 px cells, the grid centred (origin 1408).
- Furniture and plaques are **items**: a CHARM-slot item, level 1, one line of zero points (wearing it changes nothing), base
  9000 + kind (24 pieces) or 9100 + boss (8 plaques). **Placing is `MoveItem` bag to house, picking up is `MoveItem` house to
  bag**, by the account as actor so the store judges ownership; nothing is minted or destroyed. The house takes only these
  (the gateway checks `is_house_thing`).
- **The carpenter** (`Craft`) makes them from the field materials and trophies that drops already give: each field's own
  material (1 to 6) makes four pieces for 4, 6, 8, 10 pieces of it and `60 x field x piece` coin; a boss trophy (material 10 to 17)
  and 500 coin make that boss's plaque. Materials and coin are debited, the item minted into the bag (reason "merchant"); if the
  mint fails both are credited back. A full bag refuses first.
- Pieces: 0 CHAIR, 1 STRAW BED, 2 LINEN RUG, 3 PLAGUE CURTAIN | 4 TABLE, 5 BOOKSHELF, 6 CHEST, 7 GALLOWS CLOCK | 8 HEARTH, 9 CANDELABRA,
  10 BRAZIER, 11 IRON BED | 12 SIGIL RUG, 13 ALTAR, 14 SCRYING BOWL, 15 RUNE LAMP | 16 WINDOW, 17 MIRROR, 18 LANTERN, 19 SAINT'S SCREEN |
  20 URN, 21 SKULL SHELF, 22 BLACK MIRROR, 23 ASH THRONE. A HEARTH placed in a house is a campfire in its cell.

## Visiting

The owner sets the door (`Rule`): **0 open, 1 friends** (she is in the owner's friends list), **2 guild** (same guild as the owner),
**3 locked**. The owner always enters. Whatever the rule, an owner who **ignores** the visitor shuts the door on her. A house with
lapsed rent is shut. The house holds 16 at once; the 17th is refused "full". A visit pushes a notice to the owner if she is on
(`Notice` kind 0). Visitors see the house's items and guestbook (`House`).

**Guestbook**: the last 50 lines (`BOOK_MAX`), at most 80 characters, control characters stripped, through the chat's word filter
and flood limit (`Social::gate`); one account signs one book once every 10 minutes (`SIGN_GAP_MS`) so a book is not one visitor's
wall. The owner cannot sign her own, and can wipe any line. The owner is pushed a notice (kind 1).

## The training yard

`Strike` in the yard hits the dummy. Damage a blow = `weapon damage x weapon level % x (100 + MIGHT% x MIGHT points) / 10,000`,
the same factors as the field's `power()` (the core's `CLASSES[..].weapon`, `weapon_pct`, `MIGHT_PCT`; MIGHT points are her
spent points plus her gear's). No cards or effects, no crit: it is the weapon the sheet shows. The gateway keeps the pace: a blow
sooner than 90% of the weapon's interval (`every` ticks at 20 Hz) is refused (slow down). **Damage per second** = damage in the
last 10 seconds over (round age plus one swing), at least 1 and at most 10 seconds. A round ends after 5 idle seconds. The best
round of **5 seconds or more** goes on the board (top 20, one row a hero; one lucky blow is no record). Held in memory.

## Campfires

A fire is at a fixed point of the plaza (two), tavern, yard, guild hall, and in each house at a HEARTH. She may **sit** within 160 px
of one. Seated and still (within 40 px) for **60 seconds** she is **RESTED**: +10% class XP on what the gateway banks from a field
flush while it lasts (`RESTED_XP_PCT`; the outing's xp is raised before levels are counted); each further minute adds 30 minutes,
at most 60 minutes at once. Walking off or leaving ends the sit but keeps what was earned. Rest is in memory (a restart ends it).
The sit is settled when she asks (`Status`, `Sit`, `Stand`) and when she leaves, from her last position.

## Wire (tag 0x70 requests, 0x8C replies, 0xA9 pushes; sub-byte first, then the hero u64)

Requests (sub): 0 Streets, 1 Street{street u32}, 2 Buy{street u32, plot u8}, 3 Rent{street, plot, weeks u8}, 4 Renew{weeks}, 5 Release,
6 Rule{u8}, 7 Name{str}, 8 Go{kind u8, arg u32}, 9 House, 10 Place{item u64, cell u16}, 11 Move{item, cell}, 12 Pickup{item},
13 Sign{str}, 14 Wipe{entry u64}, 15 Craft{kind u16: 0..23 furniture, 100..107 plaque}, 16 Catalogue, 17 Strike, 18 YardBoard, 19 Sit,
20 Stand, 21 Status, 22 Stalls{offset u32}, 23 Where. `Go` answers with the ordinary `Town` reply of the new room.
Replies (first byte): 0 Ok, 1 Streets{open, taken[u8], mine}, 2 Street{plots: index, status, rule, owner, name, buy, rent, until},
3 House{plot, owner, name, rule, status, mine, until, items (ItemInfo, slot = cell), book}, 4 Moved, 5 Crafted, 6 Paid, 7 Strike, 8 Board,
9 Rest, 10 Stalls, 11 Where, 12 Catalogue, 13 Book, 14 Notice (push). Home requests need the hero to be in the town on this connection;
a hero may make 40 in a burst and 8 a second after (`LIMIT_*`).

## The client (`realm/client/homes`)

`HomeWire` (codec, hooked into `GwWire.decode`), `HomeMap` (places, doors, fires, grid, names: mirrors `place.rs` and
`catalogue.rs`), `HomeDraw` (floors, fires, furniture), panels `PlacesPanel`, `StreetPanel`, `HousePanel`, `YardPanel`,
`StallsPanel`. The town screen draws the place she is in (`TownScreen.stations`); doors are stations with a `go`. All pictures are flat
stand-ins drawn by code, filed for the art list as `UiArt.texture(name)` = `art/ui_<name>.png`: `home_door`, `home_door_free`,
`home_board`, `home_plaque`, `home_fire`, `home_dummy`, and one per piece (`home_chair`, `home_straw_bed`, `home_linen_rug`, ... `home_ash_throne`:
`HomeMap.art_names()`).

## Hooks outside the module (small)

`town.rs`: rooms carry a place (`enter_at`, `position`, `members_of`, `broadcast`); the old `enter` is the plaza. `gateway.rs`: a `homes`
field, `Req::Home` dispatch, `homes.depart` when she leaves the town, the dev kit's 8 linen (`homes::DEV_KIT`), and the rested bonus on
a flush's xp. `proto.rs`: `Req::Home`, `Resp::Home`, `Resp::HomePush`. `main.rs`: `gw.homes.persist("<db>.homes")`. Client: `gw_wire.gd` (one
match arm), `shell.gd` (place, house, rest, `go_place`, home pushes), `town_screen.gd`, `town_map.gd` (station lists as a parameter), `game_names.gd` (names of
furniture), `shell_test.gd`.

## Numbers of the proof

`cargo test -p realm-gateway --test homes`: 24 owners (12 rent, 12 buy) each craft a chair, a table and a plaque, place them,
pick one up and place it again; then 200 bots (own accounts, own connections, in threads) walk to street 1, knock at house `k % 24`,
read it, sign its book and leave. Doors: houses 0..15 open (the 136 bots that knocked there got in), 16..19 friends only and 20..23 locked
(64 refused). Every guestbook holds exactly its visitors' lines; the 72 things are in 72 distinct places, each exactly where it was
put; `store.verify()` has no problems.

## Open questions

- A plot registry in the gateway's file is not in the store: a second gateway or a lost file loses who owns a house (the items stay). Move
  it into the store (a table and ledger rows for plots) when the store's owner can.
- Furniture is a CHARM item with zero points: it can be worn, salvaged, sold to a merchant for a coin or two, and listed on the market
  (which is wanted: furniture trades). The cost of making one is always above its sale price.
- Only the owner may place; no co-decorators, no gifts into another's house. One cell a piece (no wide beds).
- The tavern has no function beyond being a warm room and a fire (a bar for buffs would be a new coin sink); the guild hall is the guild
  panel in a room; no guild-wide house.
- Rested XP applies to the xp of any flush while it lasts, including a flush that ends an outing that began before the rest.
- Rent is not pushed as a warning when it nears its end (the street board shows the date); a sweeper could push it.

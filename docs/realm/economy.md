# Horde & Hearth: the economy, part 1 (job L1: loot on the server)

Built in `realm/loot` (crate `realm-loot`, depends on `realm-core` for kinds and fields and on `realm-store` for every
write). Contract: rules.md sections 4, 5 and 9; store.md. Part 2 (merchants, trade, the market, mail; job E1) is
written by its job. Every number below is a constant in `realm/loot/src/tables.rs` (cards and bosses in
`cards.rs`). The tables in this file are printed by `cargo run --release -p realm-loot --example tables`; the
measured rates by `--example million`.

## How a drop happens

1. The field host reads a `KILL` event (or a `REWARD`) and, for each credited hero, calls
   `roll(secret, &RollKey, &Credit, &Source, &mut RollGate)`. `RollKey` = the field's seed, the tick, the event's
   index in that tick and the hero's slot; `secret` is a server-only number, so a client cannot predict a drop and a
   replay of the same field with the same secret gives the same drops. Each hero rolls alone (law 3).
2. The result is a list of `Found { what, kept, reason }`. `Haul::take` keeps the ones with `kept == false`
   (COMMON and UNCOMMON items, EMBERS and field materials, in the haul until banked, half lost to a fall with
   `Haul::fall`, banked with `Haul::into_delta` into `apply_outing` which mints them as `haul`). The rest
   (`kept == true`: RARE and better, cards, pages, runes, keys, every cache and chest) go to `deliver`, which writes
   them to the store at once as the server: one transaction, a request id per part (`sub_id`), overflow into the
   hero's mail when the bag is full, and a repeated call repeats nothing.
3. The store gives every item an origin (account, hero) and a `MINT` ledger row; every stack credit is a `CREDIT`
   row with `minted = true`. This crate has no other way to make value. Tests: `tests/store.rs`
   (`nothing_mints_without_a_ledger_row_and_an_origin`).

## Rates (the contract, and a million kills)

| Roll | Contract (rules 9) | Built |
|---|---|---|
| item roll, monster | 1 in 400 | 1 in 400 |
| item roll, ELITE | 1 in 20 | 1 in 20 |
| item roll, CHAMPION | always, from UNCOMMON | always, from UNCOMMON |
| luck | each point +1%, relative | chance x (100 + luck)%; luck is given by the caller (FORTUNE points, GAMBLER'S COIN +20) |
| cap | 12 non-boss item rolls a minute | `RollGate`: the 12th-last roll must be 1,200 ticks old; only a roll that hit uses a place |
| rarity | 60 / 30 / 8.5 / 1.4 / 0.1 % | the same, in thousandths; a floor cuts the lower tiers and renormalises |
| lines | 1, 2, 3, 4, 4 | the same, different stats; each `1 + level / 4` points x 100/120/150/190/240% |
| sockets | RARE+ one, RELIC two | the same |
| monster card | 1 in 20,000 of its kind; CHAMPION 1 in 200; boss 1 in 100 | the same, no luck |
| rune | ELITE 1 in 30 grade I; bosses grade II | the same; every boss chest holds one grade II (random stat) |
| page | ELITE 1 in 300; each boss's first kill | ELITE 1 in 300, one of the 18 pages at random; the first kill gives the boss's page |
| vault key | ELITE 1 in 150, field top level 20+ | the same (fields 2 to 6 of the table: HANGED WOOD to WORLD'S EDGE) |
| EMBERS | "from every field" | below |
| field material | ELITES | ELITE 1 in 2, one piece (x level scale) |

Measured over 1,000,000 kills (`tests/drops.rs::a_million_kills_match_the_contract`, every rate within 5 sigma;
one run of `--example million` with a seed of its own):

| tier | kills | items | embers | runes | pages | keys | cards | field material |
|---|---|---|---|---|---|---|---|---|
| monster | 979,562 | 2,435 (1 in 402) | 123,064 (1 in 8) | 0 | 0 | 0 | 47 (1 in 20,842) | 0 |
| ELITE | 19,954 | 963 (1 in 21) | 19,954 (every one) | 660 (1 in 30) | 67 (1 in 298) | 102 (1 in 196 over all fields; 1 in 150 where they drop) | 1 | 9,978 (1 in 2) |
| CHAMPION | 484 | 484 (every one) | 484 | 0 | 0 | 0 | 2 (1 in 242) | 484 |

Items by rarity in that run: 2,080 / 1,337 / 398 / 66 / 1 (COMMON to RELIC). Other tests: 4,000,000 rarity draws
(each share within 5 sigma, and from UNCOMMON up for a champion); every one of the 42 kinds gets its own card at
1 in 20,000 over 300,000 kills each, and the 12.6 million together are within 5 sigma; a champion's card 1 in 200
and a boss's 1 in 100 over 400,000 rolls each; luck 25, luck 100 and a 40% account all scale an item roll as
specified; the cap gives 24 items in two minutes of a champion a tick; a replay gives equal drops and another secret
does not. All 9 in 0.5 s.

**Cards "about one in a hundred outings".** A kill gives its kind's card 1 in 20,000, so a hero who gets K credited
kills in an outing meets a card in about K / 20,000 of outings: 1% at K = 200. R1's lone kiting bot makes 124 to 172
kills in 10 minutes, so a solo outing is 0.6% to 0.9%, and a rally of 100 heroes (each credited on the same kills)
more. Ultra-rare, as Curtis asked; the number to move is `CARD_KIND_ONE_IN`.

## Gear

- Six slots; a base id is `slot x 100 + tier x 10 + variant`: the tier is the field the monster lives in (six
  tiers of name: PILGRIM'S, HANGED, BOG, HERMIT'S, GILDED, ASHEN) and the variants are weapon (DIRK, CLEAVER,
  STAFF, LONGBOW, CENSER, MACE: the six classes' own), cowl/helm/crown, robe/mail/coat, gloves/gauntlets/wraps,
  boots/greaves/sandals, talisman/ring/amulet. Slots and variants are drawn evenly. Item level is the monster's
  level (the store allows 1 to 60). The contract's "tiers 1 to 5" are read as the five rarities.
- Line points of a fresh item by level and rarity: COMMON 1+L/4 (1, 3, 6, 8, 11, 13, 16 at levels 1, 10, 20 ... 60),
  UNCOMMON 1, 3, 7, 9, 13, 15, 19; RARE 1, 4, 9, 12, 16, 19, 24; EPIC 1, 5, 11, 15, 20, 24, 30; RELIC 2, 7, 14, 19,
  26, 31, 38. This is the same `1 + level / 4` the core's bench sheet assumes (a test pins them equal); R1's open
  question 5 (bench = six UNCOMMON items of the hero's level) therefore reads: UNCOMMON is 30% of rolls, so the
  bench is better than the average dropped item; B1 should weigh that.
- `plus` (+1 to +10, from the smith) adds 3% to each line a step. The stored lines never change; `item_hundredths`
  and `gear_stats` (the `Sheet.gear` array) multiply by `(100 + 3 x plus)%` and sum in hundredths over the worn items,
  and rounding is done once at the end, so +3% on a 1-point line is not lost.
- Sockets hold a rune (2, 4 or 7 points of its stat for grades I to III) or a monster card (below).

## Monster cards (42 kinds and 8 bosses)

One card per kind and per boss; stack kind `card(id)` with id 0 to 41 for the kinds in the order of the monster
table and 42 to 49 for the bosses. A socketed card gives points of one stat, like one more line, and has a percent
against its own kind that the core does not read yet (R2/B1: damage to it, damage from it).
- Kind: the stat is the kind's first behaviour in this order: HOWLER fortune; MENDER, DRAINER, BRUTE vigor; SHIELDED,
  WAILER ward; SPITTER, LOBBER focus; LEAPER, RUNNER, SWARM swift; BURSTER, WALKER might. Points `3 + 2 x field`
  (3 to 13, a level-30 line is 8 to 15); own-kind percent 10.
- Boss: points `16 + 4 x field` (16 to 36), own-kind percent 15; stats might, vigor, vigor, ward, focus, swift, might,
  fortune for the eight in table order.

| card | name | stat | points |
|---|---|---|---|
| 0 to 5 | FOOL'S ROAD kinds | swift, swift, might, might, focus, vigor | 3 |
| 6 to 12 | HANGED WOOD kinds | might, swift, swift, might, focus, ward, vigor | 5 |
| 13 to 19 | MOON MARSH kinds | might, vigor, swift, ward, focus, vigor, vigor | 7 |
| 20 to 26 | HERMIT'S PEAKS kinds | might, swift, focus, swift, fortune, ward, vigor | 9 |
| 27 to 34 | TOWER kinds | might, swift, swift, might, focus, ward, might, vigor | 11 |
| 35 to 41 | WORLD'S EDGE kinds | ward, swift, swift, focus, fortune, vigor, vigor | 13 |
| 42 THE HARVESTER | might | | 16 |
| 43 THE HANGING TREE | vigor | | 20 |
| 44 MOTHER OF LEECHES | vigor | | 24 |
| 45 THE GOAT PROPHET | ward | | 28 |
| 46 THE CHANDELIER | focus | | 32 |
| 47 THE GHOSTWRITER | swift | | 32 |
| 48 THE UNMADE KING | might | | 36 |
| 49 DEATH, THE PALE RIDER | fortune | | 36 |

(The full per-card list, with names, is the first table of `--example tables`.) A card's points are about one
extra line from its own field and a good part of a second from a boss, so a card is a sidegrade at its field's level
and strong below it; a boss's is a line and a half at the field's top.

## Bosses, caches and chests

The core has no boss table yet (R2). This crate holds the tier list in `cards.rs` (`BOSSES`, 0 to 7 in the contract's
order, 7 the world boss) and the page of each first kill; when R2's table exists, the index must be the same.

| Source | Contents |
|---|---|
| TIDE CACHE | 3 item rolls from UNCOMMON; 10 to 20 EMBERS; 3 field material; coin `60 x power%` (`100 + 12 x (level - 1)`) |
| BOSS CHEST | 2 item rolls from RARE; the boss's card 1 in 100; one grade II rune; the trophy (`material(10 + boss)`) 1 in 4; the page on the hero's first kill of that boss; 30 to 50 EMBERS; 10 field material; coin `400 x power%` |
| WORLD CHEST | one RELIC item (top 100 contributions) or one EPIC or better (everyone past the floor); DEATH's card 1 in 100; trophy 1 in 4; 100 to 150 EMBERS; coin `4,000 x power%` |

Pages by boss (deck card, the contract's numbering): HARVESTER 14 DEATH, HANGING TREE 20 THE HANGED MAN, MOTHER OF
LEECHES 18 THE LOVERS, GOAT PROPHET 15 THE DEVIL, CHANDELIER 13 THE TOWER, GHOSTWRITER 16 THE MOON, UNMADE KING 19 THE
EMPEROR, DEATH 21 JUDGEMENT. Their stack kind is `page(card - 1)` (the store counts cards from 0).
Chest and cache items are kept at once (they are not in the haul), at the level given by the caller. EMBERS and field
materials from a chest or cache scale with level like a kill's.

## Materials

`material(0)` EMBERS (smith), `material(1 to 6)` a field's own (PLAGUE LINEN, GALLOWS OAK, BOG IRON, RUNE SLATE,
STAINED GLASS, ASH GLASS; furniture and trophies for houses), `material(10 to 17)` boss trophies. EMBERS: a monster
1 in 8, one piece; an ELITE 2 to 4; a CHAMPION 8 to 12 and 3 field material. All scaled by `100 + 6 x (level - 1)`%
(half the monsters' own 12 a level, so the smith gets cheaper in kills as a hero climbs only slowly). Embers per
1,000 kills at each field's top level: 209, 373, 416, 580, 603, 768.

## The smith (`Smith::new(store, secret)`)

Every cost is checked, debited in one transaction and refunded if a later part fails. Items must be in the bag
(not worn). Prices (e = EMBERS, c = coin), `L` the item level:

| Operation | Cost | Result |
|---|---|---|
| salvage | none | destroys the item; sockets come back to the bag; `(1 + L/10) x (1, 2, 4, 8, 16)` embers by rarity, x `(100 + 10 x plus)%` |
| upgrade to +s | `(2 + L/3) x s` e and `4 x L x s^2` c | +1..+5 never fail; +6 80%, +7 65%, +8 50%, +9 40%, +10 30%; a failure costs the embers only, never the item or the coin |
| reroll | `(6 + L/2) x (rarity+1) x (10+plus)/10` e, `30 x L x (rarity+1)` c | draws the lines again (rarity, level, base, plus, sockets kept) |
| socket | `10 x L` c | a card or rune from the bag into an empty socket |
| unsocket | `25 x L` c | the card or rune goes back to the bag (the store never destroys it) |
| fuse | 3 runes of grade I (II) and 100 (400) c | one rune of the next grade; the runes are destroyed (value is lost, never gained) |

| item level | salvage COMMON / RARE / RELIC | step +1 | step +5 | step +10 | all ten steps | reroll COMMON / RELIC |
|---|---|---|---|---|---|---|
| 10 | 2 / 8 / 32 | 5e 40c | 25e 1,000c | 50e 4,000c | 275e 15,400c | 11e 300c / 55e 1,500c |
| 30 | 4 / 16 / 64 | 12e 120c | 60e 3,000c | 120e 12,000c | 660e 46,200c | 21e 900c / 105e 4,500c |
| 60 | 7 / 28 / 112 | 22e 240c | 110e 6,000c | 220e 24,000c | 1,210e 92,400c | 36e 1,800c / 180e 9,000c |

A hero at level 30 earns about 416 embers per 1,000 kills, so +10 on one item is about 1,600 kills of embers (and
the coin: a kill at level 30 pays about 10 coin, so about 4,600 kills of it; coin is the binding cost, and E1's
merchants must not pay more than that). Expected embers to reach +10 on a level-30 item including failures: a step costs `12 x s` embers and is tried
`1 / chance` times on average, so steps 6 to 10 cost 72 x 1.25 + 84 x 1.54 + 96 x 2 + 108 x 2.5 + 120 x 3.33 = 1,081,
plus 180 for steps 1 to 5: about 1,260 embers, 1.9 times the sure price of 660.

**Conserve or destroy, never copy** (`tests/store.rs::smith_operations_conserve_or_destroy_never_copy` runs 400
seeded operations and checks after each that items, cards and runes never grow, that three runes make one, and that
the store's ledger replay holds). Upgrade and reroll are by necessity "destroy the old item, mint the new one in the
same slot" in one transaction (a new item id), because the store cannot rewrite an item; see open questions.

## Sinks and faucets

| Faucet (value in) | Sink (value out) |
|---|---|
| kills: items, EMBERS, materials, runes, pages, cards, keys (the roll tables above) | salvage destroys items; upgrade, reroll and fuse destroy embers, coin and runes |
| caches and chests (tide, boss, world) | a failed upgrade destroys embers |
| coin: kills pay their XP in coin (the core); chests pay coin | socket and unsocket coin; the smith's coin |
| the account's drop percent (DROPS_REDUCED) cuts every roll | a fall loses half the haul (items and materials) |

Gold sinks at the smith are the main coin sink (46k to 92k a fully upgraded item at the top). The faucet that can run
away is the item roll rate: capped at 12 non-boss rolls a minute a hero, so at most 720 an hour; E1's 90-day bot
simulation must measure what the markets do with 4 to 20 an hour typical (1 in 400 of 150 to 1,500 kills an hour).

## What is not here, and open questions

- **Store call missing**: `ItemRewrite { hero, item, spec }` that changes an item's `plus` or `lines` in place keeping
  `origin_account`, `origin_hero` and `mint_seq`, with a ledger row `REWRITE`. Without it the smith destroys and mints
  (a `MINT` row with reason `grant`, a new id) and refuses upgrade and reroll for items whose origin account is not
  the hero's own (else upgrading would rewrite a traded item's origin and defeat clawback by origin). So a bought item
  can be salvaged, socketed and unsocketed but not upgraded or rerolled until the call exists.
- **First kill of a boss** needs a kept record per account or hero (`boss_kills`). `Source::BossChest.first_kill`
  is passed by the caller; W1 or the store must remember it, or heroes get the page every time they ask.
- **Boss tiers**: this crate defines them (above); R2 should keep the order or give a table to replace `BOSSES`.
- **Pages**: the store unlocks cards 12 to 23 (0-based) at even class levels 2 to 24 and a page is also accepted for
  them; a page for a card the account already owns is refused by `LearnPage`. Elite pages are drawn from all 18
  pages evenly, so below level 24 about two thirds are already (or soon) owned. A better draw would skip owned
  cards; it needs the account's cards passed in (`Credit`). Left as the contract says.
- **A CHAMPION** gets embers and field material but none of an ELITE's rune, page or key rolls (the contract lists
  them for ELITES only).
- **Gear slot weights** are even and line stats uniform; slot or class bias (a weapon leaning to MIGHT) is a table
  change, as is a base's own numbers. The core does not yet scale the weapon by a base, only by item level.
- **Fall**: half the haul's items and half of each material, rounded down, which the server picks (`Haul::fall`).
- **Replays**: the seed uses the hero's field slot. Slots are reused after a leave, which is harmless (the tick and
  event index differ), but a gateway that replays a field must replay joins in the same order.
- **Coin of a kill** is the core's (the haul); this crate only gives the coin of caches and chests.
- Not built: potions as drops (merchants, E1), vault rewards (section 10 is another job), houses' use of materials.


---

# Horde & Hearth: the economy, part 2 (job E1: trade between players)

Code: `realm/gateway/src/economy/` (`prices.rs` holds every number; `merchant.rs`, `trade.rs`, `market.rs`, `letters.rs`,
`wire.rs`, `sim.rs`), the store's `parcels` (schema v3), the `realm-economy` binary and `gateway/tests/economy*.rs`.
Nothing in the logic is a literal: change a number in `prices.rs`, run the sim.

## The door

`Req::Econ(EReq)` (tag 0x30) answers `Resp::Econ(EResp)` (0x8A); the server also pushes `Resp::EconPush` (0xA8, request
tag 0) to a hero in town: a trade changed, a listing sold, a letter came. Every request carries the hero; the account must own
her. A hero may make `LIMIT_BURST = 30` requests in a burst and earns `LIMIT_REFILL_PER_S = 3` per second back (a bot
cannot sweep the market faster than a person could, and the store's single writer is not starved). Over the limit: a `SLOW`
error, nothing done.

## Merchants

- Value of an item: `(5 + 3 x level) x RARITY_VALUE_MUL[rarity] x (100 + 25 x plus) / 100`. A COMMON is about nine kills of
  coin at any level (a kill pays about `3 + L/3`), so the bottom rung is always minutes of play. The rarity multiples
  `1 2 5 14 50` are shorter than the drop odds (60 / 30 / 8.5 / 1.4 / 0.1 percent): the market, not the table, makes
  rare things dear. Each `+` adds 25% (the smith charges more, so upgrading is for oneself, not for resale).
- A merchant pays 25% of value (`NPC_BUY_PCT`): the floor of every price, nobody sells below it. He sells gear at 12 x
  value (`NPC_GEAR_MUL`): dear, so the market beats him for anyone who can wait. Potions `(8 + top level of her field) x
  [1 3 3 5 8 20]`; embers `4 + top / 2`. He buys embers (2), field material (3) and boss trophies (150).
- Daily caps per hero (restock at dawn): 20 potions, 100 embers, 2 gear pieces. Caps are in memory and reset on a server
  restart (open question).
- Buyback: a sold item can be bought back at 110% of what he paid for 30 minutes, the last 12 sales. It is in memory and
  re-mints the item with a new id (open question); a sold item with filled sockets is refused (the rune would be lost).
- Buying is a store DEBIT then a MINT/CREDIT, refunded if the second step fails.

## Trade (hand to hand)

Invite (60 s unanswered), accept, each side offers items, stacks and coin, then both confirm. A confirm names the version
of both offers, so a change after you looked cannot be confirmed by mistake; a confirm is accepted only 1.5 s after the last
change of either offer (`CONFIRM_DELAY_MS`: no swap at the last click); an open trade idles out after 10 minutes. When both
have confirmed the same version the store does it in one transaction (`Store::trade`); nothing moves on a half confirm, and
a failure (a full bag, an item gone) cancels with a reason and leaves everything where it was. Origin is kept through the move.

## The market

- List: item or stack, a price, 12 / 24 / 48 hours. The item leaves her bag into escrow (a `parcels` row, items in place
  Market). Fee `1%` of the price per 12 hours, rounded up, at least 1, destroyed at once and not refunded: churn costs, and a
  listing nobody wants for 48 hours costs 4%. At most 25 open listings per hero.
- Price cap: at most `PRICE_CAP_MUL = 10` x the item's value (stacks: `stack_ref` x count x 10). It is the guard against
  two ways to abuse a market: it cannot run away upward, and an account cannot move a large sum to another by listing a
  trash item at a huge price for an accomplice to buy. The cap is a few hundred coin for gear a newcomer meets.
- Buy: the price goes buyer to seller; the tax (`6%`, rounded up) is destroyed with the sale and is the market's main coin
  sink; the item goes to the buyer's bag (`Full` if no room, nothing moves). You cannot buy your own account's listing.
- Cancel (seller only) and expiry both return the thing to the seller's mail, by the sweeper (`Economy::sweep`).
- Search: filters on slot, rarity, level range, stack kind, price ceiling; cheapest first, pages of 40. The row keeps the
  entry's slot, level, rarity and stack kind as columns with partial indexes, so a search is an index walk (it was a scan
  of every open listing and made the 2,000-bot run superlinear).

## Letters and mail

A letter carries a text (200), up to 8 things and coin, to a hero of any account; postage 2 coin plus 1 per thing, destroyed.
Cash on delivery: the sender names a price, the addressee pays it to take the attachments (refuse sends them back, so does
30 days, `LETTER_DAYS`; the sender may recall). 50 letters waiting per addressee. The sender's own letters block her hero's
deletion while they are out. The older `mail_send` of the store bypasses consent and is left for the town's use (open question).

## Self-found heroes and botter guards

A self-found hero (the hero flag from creation) may not give or receive an item or stack by trade, market, letter or
`MoveItem` / `StackTransfer` across heroes; the store refuses it (`Error::Refused`) in `ops.rs` through one gate, so no door
can forget it. Trade-locked accounts (the botter farms of store.md) are refused the same way. Origin (`origin_account`,
`origin_hero`, `mint_seq`) is kept through every move, so a stolen drop is traceable to the account that found it. The sim
proves the refusals (the `refused_ok` counter) and that no item hopped onward from a locked farm.

## Store additions (all additive, `realm/store/check.sh` is green)

Schema v3: `parcels` (escrow for a listing or a letter; indexes by sender, addressee, expiry, search). Commands
`ParcelPut`, `ParcelTake`, `ParcelReturn` (Server only; rows in `who_may`, `tests/auth.rs`, the codec). Reads `parcel`,
`parcels_from`, `parcels_to`, `parcels_due`, `listings`, `coin_flows`. `verify` now checks that every parcel holds
something and every market-place item has a parcel. `Options.durable` (default true; false is `synchronous=OFF` for the
sim only). A 64 MB page cache on both connections (the request-id table is keyed by random ids and a 2 MB cache turned
each insert into a file read once the store was big).

## The proof: `realm-economy` and `gateway/tests/economy_sim.rs`

`realm-economy --bots=2000 --days=90 [--seed --farms --db --quiet]`; the test runs seed 1 (about 6 minutes in release on
one core: the store writer is two thirds of the time). Bots play outings (the real loot generator, the smith, the merchant)
in batches, then visit town twice a day: sell junk to the merchant, list what is worth 60 coin or more, search and buy upgrades
at the right price, send letters (some cash on delivery), trade, upgrade at the smith. 5% are self-found, 10% flippers, 20 are
trade-locked farm accounts. Rounds are whole numbers and a seeded RNG; day is a 24 h game clock moved by the sim.

Judged by `failures()`: (1) store `verify` clean (no item copied, every stack and the origin equal the ledger replay);
(2) the coin the ledger says exists equals the coin held; (3) per item class (rarity x 10-level band), the median sale
price as a percent of item value per 30-day window stays inside `30..=400` (`BAND_LO_PCT`, `BAND_HI_PCT`) for a window of at
least `MIN_SALES = 30` sales (fewer is noise), and a window median is at most 2x the one before (upward only); (4) the guards.
Why this band: the floor of any sale is the merchant's 25%, the cap's ceiling is 1000%; a median below 30% means the
market is worse than selling to the merchant, above 400% means a few buyers are bidding up past any sane need. Inside it the
price may find its own level.

Seed 1, 2,000 bots, 90 days: 137,619 listings, 28,931 sold for 10,422,565 coin, 108,688 expired; tax 639,587, fees
4,419,005; 803 trades; 1,148 letters; 97,510 items live; 2,295,758 ledger rows; verify clean. Medians run 40 to 190% of value
in the classes with 30 or more sales (rarer classes at the top, `UNCOMMON` L11-20 settling at 39 to 62%), none above 400.

Coin supply (every 5 days): day 5 13k per bot; 30: 84k; 60: 180k; 90: 283k per bot. **It grows without bound, about
linearly**: hauls (kill coin) mint 732M over the 90 days against 195M sunk, of which 179M is the smith, 11M merchant
purchases, 4.4M listing fees, 0.64M sale tax. See the open questions.

## Open questions

- **Coin glut.** The faucet is about 3.8x the sinks; the market's tax (0.6M) and fees (4.4M) are small beside the smith.
  Prices are flat (they drift down to the merchant's floor on common stuff, since gear is oversupplied) while coin piles
  up: the market does not run away because the cap bounds it, not because coin is scarce. Needed: a bigger sink (rising
  smith cost, repair, house, listing fees that grow with the number of open listings), or less haul coin at high levels. The
  sim's bots do not hoard for a purpose a player has, so the real glut may be smaller; measure on the station (`economy` job).
- Prices fall to the 40 to 60% band on oversupplied classes; 79% of listings expire unsold. Is a larger fee on a relist wanted?
- `stack_ref` (the cap reference of potions, runes, keys, pages, cards) is a guess: the merchant has a price for only some.
- Self-found heroes and the shared bank: a self-found hero may still reach the account's bank by a path other than trade
  (store.md); settle with the bank's rules.
- Buyback and the daily caps are in memory (lost on restart; buyback re-mints under a new id). Move them to the store when
  a restart matters.
- Letter and COD flows are one-way spam for a rich account: postage is cheap on purpose (2 coin) and the 50-letter cap
  per addressee is the only brake; add a block list in the client job.
- Bots do not trade or write letters like people; `trades` (803) and the pair-guard (no pair 5+ times) are proof that the
  guard fires, not of the real rate.

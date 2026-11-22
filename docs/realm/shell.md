# The shell: everything outside the field (job C2)

Code: `realm/client/ui/` (the shell, the screens, the codec) and `realm/client/town/` (the town and its stations).
Entry: `realm/client/main.gd` (`main.tscn`). Check: `realm/check_client.sh` runs `tests/shell_test.gd` against a real
`realm-gateway` (66 checks, 27 screenshots; the last run's pictures are in `/home/claude/c2_shots`).

## How a player goes through it

title (ENTER) -> login (a name spelled on a ouija board) -> hero list (tarot cards; a card back makes a new hero)
-> hero builder (race, class, skin, mark, name on the board) -> hero list -> ENTER TOWN -> the town (walk, talk,
stations) -> a field gate -> the field client -> out of the gate (south) -> the town again with her outing shown.
No screen needs a help text: every button says what it does, the town names a station when you stand at it
("[F] THE BANK") and shows what it is for.

`godot --path realm/client -- [--gateway=127.0.0.1:7700]` is the shell. The old flags (`--server`, `--shots`,
`--bot`, `--fake`, `--zooms`) still start the bare field client, so the lockstep checks and the frame-rate station are
untouched (`Main` decides).

## Build

- **Canvas.** The shell draws in 960 x 540 (the project's 480 x 270 doubled) with fractional scaling; handing over to
  the field switches the window's content scale to 480 x 270 with integer scaling, and back (`Shell.use_*_canvas`).
  Why: text at 12 to 26 px reads, the field's pixel art stays whole pixels.
- **Immediate-mode screens.** `UiScreen` is a Control whose `paint()` runs each frame and registers clickable
  rectangles (`button`, `hit`); a click is `on_press(id)`. The tests press the same ids (`press(id)`), so a test click
  is a mouse click. `PanelBase` is a framed panel over the town (a dim backdrop, a title, a close button, an item
  grid, a stack list, an item tooltip). Right-click is `on_alt_press` (the bank moves at once).
- **Look** (`UiKit`): black ground, bone text, dried-blood red for what is chosen, tallow gold for frames and
  numbers; thin double frames with notched corners; eight rune glyphs drawn from line segments; candles; drifting
  motes. Text is a serif from the system (`SystemFont`: Georgia, Palatino, DejaVu Serif, Liberation Serif ...) with
  the engine's font as the fall-back.
- **Pictures** (`UiArt`): every picture is loaded by file name from `realm/client/art/` and has a flat stand-in drawn
  in code: `ui_title.png`, `ui_card_<class>.png`, `ui_town_<station>.png` (bank smith merchants reader trainer gate),
  `ui_item_<slot>.png`, `ui_stack_<coin|embers|potion|rune|page|card|key|material>.png`. Heroes in town and on the
  cards use the field's hero pictures (`FieldArt.hero_entry`) tinted by her look. Stand-ins: a rune on a plate, its
  colour from the name (items: by rarity). Lesson kept in `UiArt.hero_picture`: a texture loaded and dropped inside
  one frame draws white, so the shell holds the entries.
- **The gateway** (`GwWire`, `GwLink`): the TCP protocol of `docs/realm/wire.md` in GDScript (`StreamPeerTCP`, frames
  `u32 len, u8 type, u32 tag, body`), replies paired by tag and awaited (`await link.call_req(...)`), pushes as a
  signal. `Shell.act` runs a request and shows an error in words. A reply that never comes answers `R_LOST` after 30 s.
- **Town** (`TownScreen`, `TownMap`): the room's snapshots (10 a second: id, x, y, direction) become each hero's
  glide from where she was shown to the new place over 0.1 s (`SNAP_S`), so the picture is always one snapshot
  behind the server, with no prediction. The own hero is followed by a camera that eases (`exp(-12 dt)`). Zoom is
  1.5 (a screen shows 640 x 360 of the 4,096 px square); a hero is drawn 40 px tall. The direction goes to the
  gateway only when it changes (`TOWN_INPUT`), held keys through `ShellSettings`. Chat: Enter opens the line, Enter
  sends (200 characters, the gateway's burst of five and one a second answers "SLOW DOWN"), the last seven lines show
  for 25 s and a bubble over the speaker for 6 s. A minimap shows the plaza, the stations and the room.
- **The plan of the town is the client's** (the server has no stations): a plaza of 1,000 px radius round the
  middle (heroes arrive within 200 px of it), the trainer north (2048, 1420), the bank and the smith at the upper
  left and right (1460 and 2636, 1760), the merchants and the card reader below them (y 2336), the field gates on the
  south rim (2048, 2780). A hero within 130 px (`USE_PX`) of a station is offered it (F, the Interact key, or the
  prompt); a click works within 240 px (`CLICK_PX`), else "WALK CLOSER". Stations are flat rectangles in the town's
  colours until `ui_town_<station>.png` arrives.
- **Hand-off to the field** (`Shell.go_field`, `_open_field`): FIELD_TICKET, then `RealmClient` is added as a child
  with `embedded = true`, the ticket and the host (the gateway's address when the ticket names none; the port is the
  ticket's) and `RealmLink.connect_with_ticket`. Embedded, the field client does not size the window and Esc emits
  `escaped` instead of quitting: the first Esc shows "ESC AGAIN TO LEAVE: HALF THE HAUL IS LOST" on the HUD, a second
  within 3 s closes the link (the host flushes: coin halved), walking out of the gate banks it all. The way back is the
  gateway's `P_OUTING` push whose `left` is not 255 (255 is the host's XP flush every 10 s; ignoring it was a bug the
  test caught under a slow renderer): the shell closes the field, reads the hero again, enters the town again and shows
  `OutingPanel` (coin, XP, levels, potions, how she left). A lost gateway connection returns to the title.
- **Settings** (`ShellSettings`, `user://settings.cfg`): 17 rebindable keys (move x4, skill 1, skill 2, ultimate,
  interact, potions 4 5 6, card picks Z X C V, sheet H, bag I; the arrows always walk), volume (0 to 1 in steps of
  0.05, the master bus), window size (960x540 to 1920x1080) or fullscreen. A key given to a second action swaps, so two
  never share. `realm_client.gd` reads its keys from here (the potions and picks too) and the town does.

## The stations (what each calls)

| Station | What it shows | Gateway calls |
|---|---|---|
| Bank | her bag (40 slots), the account's bank (100 slots a tab, 2 pages of 50 shown), stacks; deposit, withdraw, 1/10/all | `BANK_DEPOSIT`, `BANK_WITHDRAW` |
| Smith | SALVAGE, UPGRADE, REROLL, SOCKET (set in, take out), FUSE; the price before the click | `SALVAGE`, `UPGRADE`, `REROLL`, `SOCKET`, `UNSOCKET`, `FUSE` |
| Merchants | BUY potions, SELL items, the BELT (three slots) | `BUY`, `SELL` (new), `SET_BELT` |
| Card reader | the 30 cards (owned or not, why), the deck of up to 20 as a row of cards, learn a page | `CARDS` (new), `SET_DECK`, `LEARN_PAGE` |
| Trainer | skills with ranks, stat points (+1, +5), the job at level 40 | `SPEND_POINT`, `CHOOSE_JOB` |
| Gates | six fields with levels and bosses | `FIELD_TICKET` |
| Sheet (H) | portrait, stats (spent, race, gear, total), skills, deck, belt | none (reads) |
| Bag (I) | bag, stacks, six worn slots; wear (the worn one goes to the bag first) and take off | `EQUIP`, `UNEQUIP` |

The smith's prices are the loot crate's (`GameNames` mirrors `realm/loot` tables and `smith.rs`; the test checks
three of them against `economy.md`'s table). Salvage embers = `(1 + level/10) x (1,2,4,8,16)[rarity] x (100 + 10 plus)%`,
upgrade `+s` costs `(2 + level/3) x s` embers and `4 x level x s^2` coin with chances `100 x5, 80, 65, 50, 40, 30`,
reroll `(6 + level/2) x (rarity+1) x (10+plus)/10` embers and `30 x level x (rarity+1)` coin, a socket `10 x level` and
taking out `25 x level`, fusing 100 (II) or 400 (III) coin. The server charges; a stale number here is only a wrong
label.

## What I added to the gateway (small, additive; E1 and W1 files)

- `ItemInfo` carries `plus` and `socketed` (a stack kind per socket, 0 empty): the smith screen needs them. Appended to
  the item's encoding (after its lines).
- `Req::Cards{hero}` (0x30) -> `Resp::Cards` (0x8A): the deck cards she may use (the novice twelve, a card each even
  level to 24 as the store's `card_owned` says, and the pages she learned). Uses a new store read,
  `Store::owned_cards(account)` (realm/store: `read.rs`, `sqlite.rs`, the trait).
- `Req::Buy{hero,kind,n}` (0x31), `Req::Sell{hero,item}` (0x32), both answered `Resp::Smith { amount }`. Buy: a potion
  (stack kind 100 to 105) at 20, 60, 60, 120, 120, 400 coin, 1 to 99 at a time: coin debited then the potion credited,
  the coin given back if the credit fails. Sell: an item in her bag pays `2 x (1 + level/4) x (1, 2, 5, 12, 40)[rarity]`
  (`SellItem`, minted coin), far under what a salvage plus a smith's work costs, so selling is a way to be rid of
  gear. Why these numbers: potions priced to the coin a kill pays (about 10 at level 30) against the draught's 35%;
  items so low that coin stays the smith's binding cost (`economy.md`, sinks). E1 owns merchants: replace these two
  calls and the client's `GwWire.buy`/`T_SELL` follow.
- `--dev-grant` (with `--dev-login`): a new hero gets 500 coin, 30 embers, 4 runes of MIGHT I, 2 healing draughts and a
  rare, an uncommon and a common item of level 1, so a day-one player can try every station. Test:
  `gateway/tests/gateway.rs::the_shells_calls_cards_merchants_and_the_dev_kit`.

## Proof

`realm/check_client.sh` prints `REALM_CLIENT ok field_test_checks=112 shell_test_checks=66 shell_shots=27 shots: ...`.
`tests/shell_test.gd` (with a display or `xvfb-run`; headless it runs the same checks and takes no pictures): unit
checks (wire frames, names, prices against `economy.md`, the ouija board, key swapping) then the whole walk: title,
settings and a rebound key, the login on the board, the empty list, the builder (a name is required), the made hero
(elf knight MIRA, her look kept), the town (snapshots arrive, walking east moves her, her chat line comes back), the
bank (10 coin in, an item in and out), the smith (salvage gives the table's embers, an upgrade makes +1, a rune set in
a socket, three runes fused to grade II, a reroll), the merchants (5 draughts for 100, a sale, the belt), the card
reader (a card out and one out and in, the deck saved), the trainer, the sheet, the bag (an item worn), the settings,
a field gate (the ticket, the field client joins and runs 40 ticks with no hash failure), walking out of the gate (the
outing's `left` is 0) and back in town with the outing panel. Screenshots (1440 x 810, software rendering):
`/home/claude/c2_shots/` (01 title, 02 settings, 03 login, 04 empty list, 05 builder, 06 list, 07 town (and 07_town_*
plaza, bank, trainer, smith, gates), 08 bank, 09 to 11 smith, 12 to 14 merchants, 15 reader, 16 trainer, 17 sheet, 18
bag, 19 settings in town, 20 gates, 21 the field, 22 back in town; `zoom*.png` are the field client's).

## Open questions

1. **Classes at creation.** The gateway makes heroes of classes 1 to 5 (rules section 3 says everyone starts a NOVICE and
   chooses a class at level 10 after a trial). The builder offers the five; no call changes a class later and the
   trial vault is not built. The field shows her as a NOVICE (the sheet's class below some level, W1's), the shell as
   the class she was made.
2. **A deck card is held once** (the store refuses duplicates); the "5 copies" of the rules come from picks in the field.
   The reader shows each card once.
3. **Offsets of the town.** No collision or zones: a hero can stand on a station; the town is flat. H1's houses and the
   plaza belong to the town room.
4. **Stand-ins everywhere** (the art list above). The portraits are the field's tiny sprites scaled; a real card face
   per class (`ui_card_<class>.png`) is the first picture to ask for.
5. **Not built here**: mail and trade screens, the market (E1), parties and guilds (T1/H1), Steam login (the gateway
   answers DISABLED), hero rename and the bank's extra tabs (the calls exist).
6. **Sound.** The shell has no sounds yet (`FieldSound` has the hooks for the field only); volume and mute are wired
   to the master bus.

# Horde & Hearth: who builds what (the full build)

**SHELVED, 27 Nov 2026 (Curtis: "do a full stop"; saved for later in the year). No job below is in work. Read
`docs/realm/SHELVED.md` first: what was stopped, where the work stands and how to start again.**

Curtis, 21 Nov 2026: "i want you to build a plan that is a complete project ready to ship, beside the art. perfect
coding everywhere else and placeholders where you need for everything", "no demos thats a waste of tokens", "edit
the plan for a full build", "wait on renting a server until last minute. use one of my computers for test host".
The plan he reads is https://claude.ai/artifact/9vWAXVd1ktk8Lo1cneN8d1. This file is the lead's working order:
jobs, the files each owns, and the proof that ends each one. No job builds a sample of its system; each builds it
for the whole game.

## Decisions that shape the code

- **One simulation** (`realm/core`, Rust, std only) run by the server, the client's native module, bots and tests.
  Fields run in lockstep with the server as clock and judge (`crowd_results.md`); the town and other places with no
  monsters use the snapshot protocol.
- **One server program**, `realm-server`, with roles in one process by default and separable later: the gateway
  (accounts, characters, town, chat, parties, guilds, market, the event clock) and field hosts (one thread group
  per field copy or vault). It ships as a Windows and a Linux download; until the game opens it runs on Curtis's PC.
- **The store** is SQLite in WAL mode behind a `Store` trait, with one writer thread, every change a transaction
  and a ledger row. It needs no install on the host. A second implementation is written only if one realm outgrows
  one machine. The `realm/store` crate may depend on `rusqlite` (bundled), pinned; `realm/godot` on `godot`; the
  gateway on one pinned HTTPS client for Steam's ticket check. Everything else is std only.
- **The client** is the Godot project `realm/client/` with the core as a native module. Screens are drawn by code in
  the dark occult frame style; every picture has a flat stand-in and drops in by file name (`Art`, as Four of Wands).
- Steam, payments, rented machines, accounts on outside services and anything public wait for Curtis's own word.

## Jobs

| Job | What | Owns | Model | After | Ends with |
|---|---|---|---|---|---|
| G | the core inside the game window; lockstep player; internet relay; Windows binaries | `realm/godot`, `realm/client`, `realm/server` (lockstep), `realm/loadtest` (relay), CI | Opus | crowd test | a player walks the lockstep field in the client under loss and delay; Windows module and server built in CI |
| R1 | rules sections 1 to 7 and 12: sheets, classes, skills, jobs, effects, 42 monster kinds and 14 behaviours, deck, six terrain maps, haul, falling, potions, events | `realm/core` only | Opus, 1 reviewer | crowd test | gates of section 13 that need no tide or boss |
| S1 | the store: accounts, characters, items, wallets, bag, bank, entitlements, ledger, backup and restore, crash-fuzz; the botter tools (origin on every mint, account flags, trace, clawback, ban waves). Built: `store.md` | `realm/store` | Opus, 1 reviewer | none | 100,000 random operations with injected crashes never create or lose an item; ledger replay equals state |
| R2 | rules 8, 10, 11: tides, altars, eight bosses, the world boss, vaults, moving heroes between copies; class bots | `realm/core`, `realm/loadtest` (bots) | Opus, 1 reviewer | R1 | all gates of section 13 |
| W1 | wiring: the two-byte input and `Sheet` on the wire; gateway (dev login, character list, town rooms, field tickets); field hosts; outing results applied to the store | `realm/server`, `realm/gateway` | Opus | G, R1, S1 | bots log in, make heroes, fight, bank, log out and back in; a server killed mid-outing loses nothing banked |
| L1 | loot on the server: rolls, gear, cards, runes, pages, materials, the smith; `economy.md` part 1 | `realm/loot` | Opus, 1 reviewer | S1, R1 | drop tables measured over a million kills match the contract; nothing mints without a ledger row |
| C1 | the field in the client: prediction, HUD, draws, skills, downed and raising, tides, bosses, effects, sound, 10,000 drawn | `realm/client/field` | Sonnet | G, R1 | the lead plays every class; drawing numbers on software rendering and on Curtis's card |
| C2 | the shell: login, hero builder and list, town and its stations, sheet, deck, bag, bank, smith, merchants, settings | `realm/client/ui`, `realm/client/town` | Sonnet | W1 | a new player gets from the title to the field with no help text |
| E1 | merchants, hand-to-hand trade, the market with its tax, mail, self-found heroes; `economy.md` part 2 | `realm/gateway/economy`, client screens | Opus, 1 reviewer | W1, L1 | a simulated economy of 2,000 bots runs 90 game days with no runaway price and no copied item |
| T1 | parties of eight, guilds of 100 with bank and board, friends, chat channels, mute, report, moderator tools; `social.md` | `realm/gateway/social`, client screens | Sonnet | W1 | flood and abuse tests; a moderator can silence and ban from a console |
| H1 | houses and streets, furniture and trophies, the plaza, tavern, market square, guild hall, training yard, campfires | `realm/gateway/homes`, `realm/client/homes` | Sonnet | T1, E1 | 24 houses on a street visited by 200 bots |
| W2 | the world: field copies that open and merge, realm clock for tides and bosses in every field, vault instances, queues | `realm/server`, `realm/gateway` | Opus | R2, W1 | a realm of six fields and vaults stays up a week of bot play with no manual care |
| P1 | Steam: login tickets, the shop for bank tabs, hero slots and looks, achievements | `realm/gateway/steam`, client `Platform` | Sonnet | W1, Curtis's Steamworks app | a purchase grants once and only once; no client can grant itself |
| O1 | running it: host package for Windows and Linux, logs, metrics, alarms, backups on a clock, restore drill, kill switches, release and rollback, flood protection | `realm/ops`, CI | Sonnet | W1 | a release, a rollback and a restore rehearsed on Curtis's PC |
| B1 | bots that play like people and the balance tables: careers 1 to 60, every class and job, alone and in crowds | `realm/loadtest`, `docs/realm/balance.md` | Opus | R2, L1 | the curve targets of rules section 2; no class left behind |
| R3 | players against players (rules section 14): the Blood Mark, guild altar wars, duels, marked realms | `realm/core`, `realm/gateway/social` | Opus, 1 reviewer | W2, T1, B1 | marked bots fight in a crowd of 1,000 inside the budget; no unmarked hero can be struck or robbed |
| A1 | the picture and sound list for this game, in sheets of six, dark and occult | the art list doc | lead | rules | every stand-in has a name, a size and a prompt; 64 new hero figures (race x novice, class, job) |

Three heavy jobs run at once on this box (4 cores). The lead commits, reviews, merges and runs the checks; workers
never run git, never message Curtis, never install packages beyond the crates named above.

## Ideas from the first playtest (Curtis, 25 Nov; not scheduled, no order)
- A choice of manual or automatic basic attack (today every hero attacks on a cooldown by herself).
- Better maps: obstacles that block, water, plants, more detail in each field, atmosphere (fog, weather, light).
  Today a field is the procedural ground with patches and a few props.
- UI fonts and frames in a pixel gothic style, not modern and slim (today a system serif).
Done from the same playtest: menus take the mouse everywhere and the keyboard (arrows or Tab, Enter, Esc or a
right click back); the town is seen at the fields' zoom with crisp pixels and the fields' walk animations.

## Scope change and second playtest (Curtis, 27 Nov)
Curtis: "change scope from survivor mmo cross to mmo with survivor horde, survivor elements". The saved hero's class
level (1 to 60) is the progression; the per-outing field level and field XP are removed. The deck stays as the
survivor element: draws come from entering a field, from ELITE, CHAMPION and boss kills, and from shrines.

| Job | What | Owns | After | Ends with |
|---|---|---|---|---|
| X1 | remove field level and field XP; new draw sources; retune damage without the field-level term | `realm/core` (deck, mods, combat), rules 2 and 5 | none | REALM ok; measure.rs pace per field within 15% of before |
| Q1 | quiet zones at each entrance and 3 to 5 deep in each field (no spawns, monsters kept out, a shrine each); more complex fields (walls, ruins, water, corridors); monster routing through tight passages; bots push deep instead of waiting at the gate | `realm/core` (terrain, spawn, flow, monster, bots), `realm/client/tests/playbot.gd` | none | every walkable cell reachable on many seeds; fewer stuck monsters in a corridor test; crowd bench inside the budget |
| U1 | our own pixel gothic bitmap font (display and body), text rework on every screen, debug text off by default (F3), enemy health bars inside the monster batch, measured at 10,000 and 20,000 | `realm/client`, `tools/font` | none | check_client green; bar cost measured |
| D1 | a full debug menu with cheats (spawn, heal, god mode, teleport to zone, grant items and levels, time of tide), dev builds only, every cheat checked by the server and refused on a release server | `realm/client/ui`, `realm/gateway` (dev role) | U1 | a release server refuses every cheat |
| K1 | better abilities and their animations: each skill and ultimate gets a readable effect (wind-up, hit, after-image), new skill ideas per class | `realm/core` (skills), `realm/client/field/field_fx.gd` | X1 | the lead plays every class |
| V1 | dungeons and indoor areas: hand-shaped interiors (crypts, cathedral, mine) with rooms and doors, entered from fields and town, using the same lockstep field host | `realm/core`, `realm/server`, client | Q1 | a party clears a dungeon with bots |
| F2 | flow and pacing: no levelling by standing at a region's entrance. Class XP scales with depth and risk (more deep, little or none in and beside the entrance zone), falls off for monsters far below the hero's level, and stops when a hero has not moved or acted for a few minutes; spawns near the gate stay light; the field gives goals deeper in (shrines, elites, chests, events) | `realm/core` (xp, spawn), rules 2 | X1, Q1 | a bot parked at an entrance for 8 game hours gains under one level; a bot that pushes deep levels at the measured pace |
| G2 | gathering skills, as in RuneScape but in our world: mining, fishing, woodcutting, herb picking first, each with its own level 1 to 99 and tools; gathering grounds inside fields with light, sparse monsters you clear first, dangerous but not a constant flogging; nodes deplete and regrow; materials feed the smith and potions. Nodes are static cells, so they cost nothing against monster count | `realm/core` (skills, nodes), `realm/loot`, rules new section, client | Q1, L1 | bots train each skill 1 to 30 on the curve; nodes add no measurable tick cost at 20,000 monsters |
| G3 | more life skills after G2 (cooking, smithing from ore, alchemy, runecraft, hunting), each fed by G2 materials | as G2 | G2 | each has a use in the economy |
| S2 | voices: memorable NPC lines spoken by a free local text-to-speech model whose voices allow commercial use (licence checked before use), made offline on the stations, shipped as audio files | `tools/voice`, `realm/client/audio` | none | every named NPC has lines; licence list updated |

Curtis, 27 Nov 21:13 UTC: "the leveling felt to linear i could literally just wait at the entrance ... and gain ten
levels" and "we need other things to do beside combat, fishing, mining, etc kind of like runescape" (F2, G2, G3).

Side idea, not scheduled: AI chat for a few NPCs (a small local model or none). It must never block the game and
would need its own cost and licence check first.

Libraries: the simulation stays std only (determinism across Linux and Windows). Tools and the client may use
pinned libraries where they save real work: cargo for Rust, uv/pip for Python tools, Godot addons by pinned file
copy with their licence listed.

## The stations (Curtis's four computers)

His four computers test every merge with no Claude and no tokens (`tools/station/`, results on the branch
`station-results`, read with `tools/station/read.sh`; never rerun in a session what a station already ran).
Four of Wands is stopped (Curtis, 21 Nov: "stop four of wands and work entirely on this title"), so from 21 Nov the
stations run this game only and skip merges that changed nothing they test.

| Station | Now | Added by |
|---|---|---|
| Ubuntu HP ENVY | `realm`: core, server and store checks with the crash fuzz | W1: a long soak (bots through the wire server for hours), O1: backup and restore drill |
| MSI (RTX 5050) | `realm` on Windows | C1: the field client's frame time with 10,000 on screen on a real card; the **test host** for the closed test |
| Ryzen laptop (Radeon 610M) | `realm` (the same checks, once Rust is on it) | C1: the same frame test at the low end, the number that sets minimum spec |
| Heatherspc (Celeron) | `realm` (the same checks, once Rust is on it) | C1: the frame test below minimum spec, recorded only |

Each job that adds a station test adds its word to `station.sh` and its line to `roles.txt` in the same PR. Ubuntu
and MSI need Rust installed once (README there).

## Proofs in order

1. Crowd test: passed 21 Nov (`crowd_results.md`).
2. G, R1, S1: the real rules at 1,000 x 20,000 inside the budget; the core inside the window; a store that cannot
   copy or lose.
3. W1, L1, R2, C1: a hero's whole loop against a server on Curtis's PC, over the internet, with friends.
4. C2, E1, T1, H1, W2: the whole world and living together.
5. P1, O1, B1: Steam, operations rehearsed, balance tables; then a closed test, an open test with a cap, launch.

## Dates

Steam Next Fest runs 22 Feb to 1 Mar 2027; registration closes 10 Jan; the build and store page go to Valve by
18 Jan for the press preview and by 1 Feb at the latest. Next Fest takes a playable build only: ours is this game
as it stands, behind a level cap that is one switch. Four of Wands is stopped (21 Nov); its code stays on `main`, untouched.

# Handoff: the plan and the decisions

For whoever plans the next step. The plan and its gates: `docs/release_plan.md`. How each system works:
`docs/systems.md` (one section per system).

**The game:** FOUR OF WANDS (working title Magic Smash), a tarot-dealt co-op survivors-like. One to four wizards
hold their tower, level up together, and bet the whole party's fate on a card. Pillars: co-op first (shared party
XP, one pick screen, revives, a readable shared screen, AI apprentices for empty seats); fate (tarot draws, gamble
shrines, the party's fate card); a tower worth exploring (the Sanctum, secrets, monster cards).

## Where things stand (28 Nov 2026)

- Four of Wands is the only game in work (owner, 27 Nov). Horde & Hearth in `realm/` is saved for later in the year:
  leave it buildable, do not work on it.
- There is no date (owner, 27 Nov): "just focus on the project keep nextfest in mind as marketing later". The
  February 2027 Next Fest is not ours, and the older launch date of 18 Dec 2026 is gone. The work is the finished,
  professional, full game, built in seven stages that close on gates (`docs/release_plan.md`).
- The wave plans (`docs/push_brief.md`, `docs/wave2_brief.md`, `docs/wave3_plan.md`) and the eight rework steps
  that stood here are history: every step is built except Steam, which is stage 7. Read the wave briefs for how a
  system was specified, never for dates or scope.
- The audit of 27 Nov walked every system, measured it and had every finding read a second time. Its document:
  https://claude.ai/artifact/BkrNpGpjuPZYjWeb5V7x7o. Its confirmed bugs are stage 1; the list with PR numbers is in
  the release plan.
- Stage 1 is merged (14 lines, `docs/release_plan.md`). Stage 3 has begun: its contract, the order of its jobs and
  who owns which file are in `docs/stage3_brief.md`. Stage 2's frozen content list is written: part 2 of
  `docs/content_list.md` (§ 36 to 54). Part 1 of that file and the tables in the code (`Spells`, `Upgrades`,
  `Cards`, `Achievements`, `Tuning`) say what is built today; part 2 says what stage 3 builds. A row of part 2 is
  added, dropped or re-paired only with a line under "The frozen list" below.

## Decisions already made by the owner

- **Genre (19 Nov):** a co-op survivors-like (auto-ish fighting, level-up picks, growing hordes, short runs) built
  on Magic Smash's wizards, spells, enemies, Lich boss, art and music.
- **Who decides (19 and 27 Nov):** the lead makes the design calls and has full creative control over scope and
  vision; no decision cards for design forks. Green PRs merge without asking.
- **Never a cut-down slice (21 to 22 Nov):** every build the owner or the public gets is the whole game as it
  stands. How that meets a fest's rules is a stage 7 question.
- **Price:** cheap and paid, $4.99 to $6.99.
- **Friends:** Steam Remote Play Together, so friends without the game join free. Online play with Steam invites
  is in stage 6.
- **Platform:** desktop, Steam first. No web build.
- **Four seats on one screen (27 Nov):** they exist and stay; they are not the focus.
- **Art (19 and 20 Nov):** no half-finished art. Plain placeholders first, then finished art that holds up on a
  store page beside shipped games. The lead judges it from screenshots at 2x.
- **Tools (22 Nov):** free first, never a paid service; research the best option and confirm a commercial-use
  licence before adopting any tool or model. The 27 Nov orders add: use, and look for, every skill, connector,
  MCP server and tool that helps.
- **Collectibles and gambling are wanted:** gacha-style collection, ultra-rare armors, consumables, loot boxes and
  gambling moments, under the rules below. Paid cosmetic boxes are not in the seven stages (the lead's call).
- **Title:** FOUR OF WANDS is the tarot card of four staffs raised before a castle: four wizards, their home, a
  celebration. A web search found no game of that name; the check on Steam itself is the owner's.
- **Steam:** only the owner acts there. Ask before any store action, payment or upload.

## The frozen list: the lead's decisions (28 Nov)

The list is `docs/content_list.md` part 2. Why it is shaped the way it is:

- **One tarot deck, every card with a job** (§ 37). The 22 Major Arcana are the 14 arcana a wizard holds and the 8
  fates of the team shrine; 16 Minor Arcana are the Reading; a reversed arcana is a Seal. Tarot is the game's one
  idea, so every system is dealt from it and nothing needs a second vocabulary.
- **Spell + arcana, never spell + spell** (§ 37, 40). Six evolutions asked for a second spell, which cost a spell
  slot and made two pairs fight for the same slots. Every arcana now has a pair, so no card is a dead pick, and the
  six spells and six arcana of a new profile pair one to one.
- **Two roads for the four mage schools** (§ 40): a crowd road and a second road each. A build is a choice, and a
  mage is not solved after one win.
- **Fewer free spell levels** (§ 41): an elite's tome 0.35 of the time, where every elite dropped one and up to
  twenty free levels a run chose the build for the player.
- **Locks teach the game** (§ 44). A new profile holds six spells, six arcana, one class and two races; the rest
  opens by deeds a player earns by playing further, about one every second run until the first win. Guest seats
  play preset heroes of four classes, so a first night of co-op is not poorer for it.
- **Crystals buy options** (§ 45): redraws, banishes, a head start, the Reading dealt again, three decks, satchel
  pockets, provisions. The stat shelf stays and costs more.
- **The satchel is built** (§ 46). The 27 Nov scope draft left the owner's inventory bag out ("nothing in the loop
  needs it yet"). It is in: one pocket carries a piece of armour or a provision into the next run, and an ULTRA
  RARE piece is a keepsake for good, so the rarest find is always worth having.
- **Seals with teeth** (§ 43): each Seal adds about twice what it added (nearly three times the enemy health), and
  two rules gain a second half. Stage 5 tunes them until each step's win rate sits between its neighbours'.
- **Morvane's two visits are not built** (§ 51): `Bosses.VISITS` goes. Three bosses, three acts.
- **Numbers are not frozen.** Stage 5 tunes them against the gates of § 53, which are written before the rows are
  built so that every row is built to be measured.
- **Card words shortened (28 Nov, before anything was built).** A row of the level-up tray holds a name of 15
  letters and 14 letters of words. Five new evolutions' words were longer (LODESTAR now says HUNTS BIG PREY, GREEK
  FIRE BURNING GROUND, WINTER VEIL CLOAK OF FROST, DIES IRAE SLAYS THE WEAK, EVIL EYE HEXED BURST), and the tray
  writes THE HIGH PRIESTESS without her THE. No row, pair or effect changed. Three shop names are wider than
  today's shop row (THE SECOND GLANCE, THE READER'S FAVOUR, THE DUELLIST'S DECK): the new shop screen is built to
  hold 19 letters, the names stay.

## Loot and gambling rules (from the CursedPawn gacha / lawsuit research)

Research doc: https://claude.ai/artifact/HeWHGkv8j31YYkXppPvAsR

1. **Everything that changes a run is earned in play, never bought.** Stat armor, consumables and run gold drop or
   come from in-run chests and shrines.
2. **Paid boxes are cosmetic only** (robes, staff skins, spell colours, nova effects): account-locked, with no
   trading, no Steam Market and no cash-out; real-money prices with the odds shown and tested; off in Belgium;
   gated for under-16s; every purchase confirmed; accounts never locked over refunds.
3. **In-run gambling uses run currency only.** Chests open with a slot-style reveal. Shrines take run gold.
   **Team gamble shrine:** one player bets for the whole party (double the party's level-up or curse everyone) and
   everybody watches the reel. That is the clip moment.
4. **Rarity tiers** (common, rare, epic, legendary, ultra-rare) show by colour and sound, readable in 3 seconds
   with the sound off.

## How the work runs

- One lead at a time. Workers get a brief with owned files and never use git; the lead reviews each diff and its
  pictures, then lands it with `tools/land.sh` (guard, tests, lint, golden on request, commit by file name, pull
  request, auto-merge; `docs/agent/land.md`; `CLAUDE.md`, skill `agent-fanout-playbook`). A fix lands with a test
  that was red before it.
- The owner's four PCs run every merge and take queue jobs between merges (`tools/station/README.md`). Robot runs,
  robot careers and frame timing are queue jobs `wandsrun`, `wandscareer` and `wandsframes`. Never `fill-week`:
  that loads Horde & Hearth's work.
- Numbers come from robots before opinions: `docs/bots.md` for the personas, `docs/performance.md` for frame
  times (pass 4 holds the slow PCs' numbers).

## Checks and tools

- `tools/check_all.sh`: unit, sims, lint, three bot shards and the four saved-heroes shards (heroes, boss, win,
  again). CI (`.github/workflows/checks.yml`) runs them as separate rows on every push and PR, and the whole script
  once more on Windows (row `checks-windows`), the way the three Windows stations run it. `tools/map.sh` maps every
  script; `tools/outline.sh <file>` maps one.
- After every merge read `tools/station/read.sh`: a station's `checks` can fail where CI passed (28 Nov: the
  Windows PCs failed for a day and nobody read it).
- Watch it play: `xvfb-run -a godot --path . -- --autotest --out=/tmp/shots` (`--autotest=5` starts at the Lich,
  `--autotest=15` at the Archlich; `--players=N`, `--perf`).
- Music: `tools/music`; SFX: `tools/gen_audio.py`. A whole bot run:
  `godot --headless --path . -s tools/full_run.gd -- --wizards=4 --seed=7` (add `--tune=f:v`).

## Known gaps (beyond the stage 1 list)

- Ending the process with SIGTERM skips Godot 4.7's window-close request, so a run ended that way is not booked.
  What the Steam Deck's "Exit game" sends is not checked.
- A LAN guest's run is not booked when the host quits (goes with online play, stage 6).
- Slow hardware: the game is script-bound. A Celeron N4100 runs four players at 7 to 15 frames a second; the Ryzen
  laptop holds 60 alone and slips to about 54 with four at the Archlich (`docs/performance.md`, pass 4).
- The `bot-heroes`, `bot-boss`, `bot-win` and `bot-again` CI rows are not in the repository's required checks (the
  owner's setting): read their result before a merge.
- The tool and licence behind the owner's 103 uploaded pictures are on no record (`docs/asset_sources.md`, open
  questions 1 to 3; asked of the owner on 28 Nov). The credits roll leaves its A GAME BY and PICTURES sections out
  until he answers (`Credits.MAKER`, `Credits.PICTURES_BY`); the exe's company and copyright fields and the store
  forms wait for the same answer.
- The notices file carries Sentry for Godot, sentry-native and Crashpad. What those two carry inside them in turn
  (Crashpad builds on mini_chromium, for one) has not been walked: walk it before the public release (stage 7).
- The `tools` CI row (self-tests of `tools/land.sh` and the versions rule) and the `checks-windows` row are not
  required checks either.
- The kit's frame stamp and render toggles are sized for a 1080p 3D game, so they are not in the 480x270 main
  scene. Scale them down before use.
- On 20 Nov most of `arena.gd`, `title.gd` and `net.gd` were untyped (only `game/logic` is strict in spirit);
  lint passes because its rules are narrow. Type things as you touch them.

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
- Stages 1 and 2 are closed (14 fixes, `docs/release_plan.md`; the frozen content list, part 2 of
  `docs/content_list.md`, § 36 to 54). Stage 3 is running: its contract, the order of its jobs, who owns which
  file and what is done are in `docs/stage3_brief.md` (§ 3 holds the Done line). Part 1 of the content list is the
  snapshot of 28 Nov and is written again from the code at stage 3's gate; until then the tables in the code
  (`Spells`, `Upgrades`, `Readings`, `Profile`, `Cards`, `Achievements`, `Tuning`) say what is built, and their
  `UNBUILT` shelves say what is not. A row of part 2 is added, dropped or re-paired only with a line under "The
  frozen list" below.

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

## Stage 3: what the lead decided while building (28 Nov)

- **The tome cut waits for stage 5.** The list cuts an elite's party tome to 0.35 of the time (§ 41). With the cut
  in, bots that know the new pairs won 2 of 6 runs where they win 4 of 6 without it, and every loss came before the
  first boss: the free levels are the early game's power today, and what replaces them is built later in stage 3.
  `party_tome_elite` stays 1.0 until stage 5's first tune job applies the cut with the numbers that go with it.
- **A build is harder to bring together, and that is the point.** Since every evolution asks for an arcana, a
  wizard's three arcana slots (four after the first boss) choose her evolutions. Two casual bots evolved in every
  run before; a group of four runs now tells how many do (`tools/playtest.gd`). The lead's coarse pass before the
  stage's gate build moves one knob until groups reach the Archlich again; stage 5 does the real tuning.
- **Bots are taught every rule a card adds.** They lost every run with the new pairs until `SmashBot` knew them,
  and lost again when the casual took a pair's arcana too early. Every job that changes how a build comes together
  owns the bots' side and measures a group before and after (brief § 2.10).
- **A card's words wait for its effect.** THE TOWER and JUDGEMENT take an arcana slot and keep the words `+1 NOVA
  NOW` and `+1 LIFE NOW` until job C5 builds the refill and the blast.
- **Locks are on.** Since the catalog job every real run is dealt from the host's profile (§ 44): a new profile
  holds six spells and six arcana, and a deed opens each further row. A wizard's own class weapon is always open
  with its first road. Until GREEK FIRE is built, a profile without THE TOWER has no road for FIREBALL.
- **One screen, no compact tray.** The plan asked for compact trays. Built in their place: a tray keeps its rows
  and turns see-through while it covers a wizard; the painted hand under it is not drawn over one; the camera
  holds every living human's body in the window, and the leash is 440 x 200 so that it can; every wizard out of
  view has an arrow at the edge in her seat's colour.
- **The team shrine is one pot.** Every wizard standing in it pays her share while she stands, so the table bets
  together and nobody pays for the rest. Bots wait a few seconds alone, leave, and come back for a partner.
- **A boss is a foe, and EIGHT OF WANDS is the clock.** A Reading that says FOES changes bosses too; EIGHT OF
  WANDS speeds the run's one clock, so XP, spawns and bosses all come a fifth sooner (built in job R2).

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
  times (pass 4 holds the slow PCs' numbers). Balance is read from groups: `tools/playtest.gd -- --runs=4
  --wizards=2 --persona=casual --seed=7 --minutes=17` before and after a change, and the stations' forever jobs.
  One `FULL_RUN` line is not a measurement: a single seed flips between a loss at 4:00 and a win at 17:00.
- A picture review checks every figure's feet against her ring, facing both ways: painted figures facing left
  stood a body width beside their feet for five days and no review saw it (`docs/lessons_learned.md`).

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
- Seven CI rows are not in the repository's required checks (the owner's setting, asked of him on 28 Nov):
  `bot-heroes`, `bot-boss`, `bot-win`, `bot-again`, `bot-cover`, `tools` and `checks-windows`. Read their result
  before a merge.
- The tool and licence behind the owner's 103 uploaded pictures are on no record (`docs/asset_sources.md`, open
  questions 1 to 3; asked of the owner on 28 Nov). The credits roll leaves its A GAME BY and PICTURES sections out
  until he answers (`Credits.MAKER`, `Credits.PICTURES_BY`); the exe's company and copyright fields and the store
  forms wait for the same answer.
- The notices file carries Sentry for Godot, sentry-native and Crashpad. What those two carry inside them in turn
  (Crashpad builds on mini_chromium, for one) has not been walked: walk it before the public release (stage 7).
- The kit's frame stamp and render toggles are sized for a 1080p 3D game, so they are not in the 480x270 main
  scene. Scale them down before use.
- Bots at a shrine step in and out of its circle as they dodge, so few shrines get paid (10 to 14 of 37 in a run);
  job U8 of the brief. The LAN join check compares the version and the wizard row's width only; job U2.
- The Archlich's fight is long for bots since the pairs (about two minutes for one or two wizards); stage 5.
- `docs/bots.md` has no section on careers (`tools/career.gd`, the station job `wandscareer`).
- The name HIGH PRIESTESS is 4 px wider than the plate of a 68 px painted card; job V1 of the brief. The exe's icon
  is a stand-in (`docs/release_build.md`), and part 1 of `docs/content_list.md` marks every card that has no
  painted card yet (`(!) no painted card`); both are stage 4's.
- On 20 Nov most of `arena.gd`, `title.gd` and `net.gd` were untyped (only `game/logic` is strict in spirit);
  lint passes because its rules are narrow. Type things as you touch them.

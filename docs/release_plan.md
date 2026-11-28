# Release plan · Four of Wands

Status 28 Nov 2026. The owner's word (27 Nov): "we are planning for the next next fest not the one in february. so
just focus on the project keep nextfest in mind as marketing later". Nothing here has a date, and no Valve deadline
drives the work. The audit, the scope and the reasons are in the lead's audit document (linked from the lead thread).

## Seven stages, each closed by a gate
A stage ends when its gate is proven, and the owner gets a build to play at each gate. Work that fails its gate does
not move on. Nothing is cut to hit a date. Sizes are the lead's rough estimates at the pace of late November.

| Stage | What happens | The gate that closes it | Rough size |
|---|---|---|---|
| 1 Fix and trust | Every confirmed bug of the 27 Nov audit. Checks that see saved heroes, four players, a boss, a win and a second run. A robot-built Windows build with a smoke test. Licences, credits, a record of which tool made which picture. | Every serious bug has a test that was red before its fix. The new robot runs are in every merge. A robot-built build passes its smoke test. | about a week |
| 2 Freeze the content list | Spells, passives, evolutions, Readings, Seals, unlocks and shop rows as tables in `docs/content_list.md`, before any of it is built. | Committed, and every row says what it pairs with and how it is tested. | a few days, overlapping 1 |
| 3 Build it | The content. Compact trays, markers for anyone off screen, a party that stays seated between runs, a team shrine everyone pays into, rewards at each boss phase, a first run that teaches, the options players expect, the missing sounds. A speed pass on the simulation step, the snapshot and drawing crowds. | Robots finish runs that use every spell, passive and Reading. | 3 to 4 weeks |
| 4 One look | Alongside 2 and 3, on the MSI's graphics card: one palette and lighting rule over every sprite, the enemies in one style, a real Archlich, art for every card in play, menu backdrops, icons. | The palette checker passes on every sprite, no listed picture is missing, screenshots hold up at store-page size. | alongside |
| 5 Tune | Only after the content exists: the climb to the first win, the spread between spells, scaling from one to four players, the Seals, the prices. Robot careers on the four PCs measure. | Half of solo robot careers reach their first win between 2 and 3 hours of play, and four players never in under 1.5. Every spell's level 5 damage sits within 0.6 to 1.6 times the middle spell. The worst moment of a four-player run holds 60 frames a second on the Ryzen laptop. The owner and friends play an hour on the couch with nothing blocking. | about 2 weeks |
| 6 More game | A second tower, online play with Steam invites, key remapping, more languages, leaderboards for the Daily Draw. Order by what the stage 5 playtests ask for most. | Each piece passes the kind of gate the first tower did. | 6 to 8 weeks |
| 7 Steam and the public face | The Steam build (achievements, cloud saves, Remote Play Together), the store page, capsule art, the trailer, the wishlist plan, the Next Fest after February 2027, release. | Starts when the owner says the marketing starts. The Steam code is built earlier against Valve's free test app. | the owner's call |

Never released without: the confirmed bug fixes, the 2 to 3 hour climb, one look, achievements and cloud saves,
credits and licences, a first run that teaches, a release built and smoke-tested by a robot.
Stays out: paid boxes, a telemetry service, new hub minigames, any cut-down slice of the game.

## What "finished" means (stages 1 to 5)
- The run: one tower, three acts, three bosses, about 15 minutes; every boss phase hands out a reward.
- Builds: 10 spells and 14 passives that all pair into evolutions, every evolution worth taking, a chart of them in
  the game; fewer free spell levels, so choosing matters.
- The Reading: before each run the table draws three tarot cards and keeps one; each changes that run's rules. It
  unlocks at the first boss kill.
- The climb: 2 to 3 hours to the first win (about run 8 to 12 alone, 5 to 8 as a pair), an unlock about every second
  run, a shop of 10 or more rows where crystals buy options, not only numbers.
- After the first win: reversed Seals I to VIII with real teeth, Overtime (up to 10 more minutes after the Archlich),
  the Daily Draw (the same seeded run for everyone that day, against your own best).
- Keepsakes: every monster card can drop, the album can be completed, an ultra rare is always worth having, a small
  satchel screen.
- Co-op: wizards told apart at a glance, a party that stays seated between runs, a team shrine the table pays into.
- One look: one palette and outline rule, a real final boss, art for every card in play.
- A product: a first run that teaches, options, a quit that asks first and keeps rewards, credits and licences,
  button pictures per pad, a sound for every co-op moment.
- Four local seats on one screen stay; they are not the focus (owner, 27 Nov).

## Stage 1 list (28 Nov)
- [x] A socketed card counts once (#273). [x] Damaged and newer saves are safe, and the title says so (#273, #274).
- [x] Every monster card can drop, ALL_CARDS can be earned, no plain heal in a LEGENDARY chest, the DWARF's trait
  works, an away player keeps her loot (#276). [x] The balance tools stop booking wins as losses (#273).
- [x] Four seats look like four heroes (#272). [x] A robot run with saved heroes; bot runs fail on engine errors (#275).
- [x] One pad's B no longer empties the lobby; a pad player can walk the hub after the shop (#274).
- [x] Quitting asks first and books the run; closing the window books it too (#277).
- [x] Frame times on the two slow PCs for one, two and four players (station job `wandsframes`).
- [ ] The second boss always comes; bosses stay on screen; nothing happens after the run is decided.
- [ ] Robot runs with four players, to a boss, to a win and into a second run.
- [ ] A robot-built Windows build with a smoke test, test files out of the pack, licence notices.
- [ ] ALL_SECRETS can be earned (the profile counts urns and sends `"urn_card"`).
- [ ] Credits in the game; a record of which tool made each picture.

## Steam facts for later
Read on Valve's own pages on 27 Nov 2026 for the February 2027 fest and quoted word for word. They are not our
dates. Re-read Valve's pages before planning stage 7: the later fest's dates were not checked, and Valve changes
pages without a revision date. Only the owner acts on Steam; ask before any store action, payment or upload.

Next Fest (partner.steamgames.com/doc/marketing/upcoming_events/nextfest): registration closed about six weeks
before the February fest and needed a public store page; the build and page went into review about five weeks before.
Eligibility, same page: "Associated with a Steamworks developer account in good standing" · "Store page must be
published and public" · "Is not a prologue, chapter 1, or otherwise 'demo' version of existing content available to
customers" · "Includes a publicly playable demo by the time the festival begins" · "Released any time after the
conclusion of the fest on March 1, 2027". "A game may only appear once in Steam Next Fest."

## Steam onboarding (only the owner can do these)
Sources: partner.steamgames.com/doc/gettingstarted/onboarding · partner.steamgames.com/steamdirect ·
partner.steamgames.com/doc/store/application/demos

- Fee: "$100 USD (or equivalent) fee for each product"; not refundable, recouped after US$1,000 adjusted gross revenue.
- "A 30-day waiting period between when you paid the app fee and when you can release your game."
- "put up a publicly-visible 'coming soon' page for at least two weeks."
- Tax check: "This process may take 2-7 business days, and you may be asked to provide additional documentation."
- Store page and build review: "This takes between 1-5 days." (Valve's review page advises 7 business days of margin.)
- A demo is "a separate App ID that is associated with your full game's App ID", with its own depots and builds; a
  separate demo store page is optional. Whether the 30 days and the two weeks also bind a demo is not stated: plan as
  if they do.

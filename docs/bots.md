# Bots and the playtest tool

**The baseline at the bottom was measured on 19 Nov 2026, before shared XP landed** (wave 1, worker A is changing
levelling at the same time). Re-measure after that merge before acting on the level and pick numbers.

`SmashBot` (`game/logic/smash_bot.gd`) is one brain used everywhere: the arena's bot mode (autotest, the bot gate,
LAN clients, from the view state), the sims and tools (straight from `World`), and, in wave 2, the AI apprentices
that fill empty seats. `tools/playtest.gd` lets its three personas play whole runs and reports where the game is
too hard, too easy, dull or unfair.

## How the brain decides

1. **Think, then hold.** A bot thinks 10 to 15 times a second (persona `hz`, with a little jitter) and repeats its
   last decision in between. A decision reaches the hands only after the persona's reaction delay (`react`): the
   bot acts on what it sensed that long ago, like a person. The first decision of a run acts at once.
2. **Senses** (once per think). The `track` nearest enemies within `sense` px, with their velocity and radius (from
   `World`'s spatial grid, never a scan of the whole horde), and the `shots` nearest enemy shots that fly toward it.
   A shot from behind is seen only within `rear` x the sense range. A veteran also reads tells: an orc or a tome
   rearing up is treated as already charging. It also senses its hearts, novas, speed, teammates, the leash box,
   the arena and the boss.
3. **A goal.** Each pickup in reach is worth `PICKUP_VALUE` (chests and tomes most, XP motes a little; a potion
   only when hurt, more the more hurt, nothing at full health), divided by distance and minus the danger round it
   times `1 - greed`. A shrine it can pay is a goal too (it stands on it to bet). It finishes a fetch it started.
4. **Steering by candidates.** It scores 16 headings and standing still. Each heading is walked `look` seconds
   ahead (clamped at the walls) and scored on:
   - enemies: the closest approach of the wizard's path and each enemy's own path (both straight), minus their
     bodies, against the persona's `margin`; sooner is worse. Times `caution`.
   - enemy shots: the same, exact (shots fly straight), against the chest point where `World` counts a hit.
   - the way out: how crowded the end point will be. Together with the path term this makes it slip out of a
     closing ring through the widest gap, and kite a horde round in a loop.
   - walls (penalty for running into them and for ending within 18 px) and the leash (within 24 px of its edge).
   - the goal (progress toward it), else its roaming ground: solo, within 140 px of the arena centre; in a party,
     its own lane 32 px beside the party centre (so four bots never stack), free within 70 px.
   - a small bonus for circling the threats (each bot has its own spin, flipped now and then when boxed in).
   - room from teammates (30 px) and a range band from a boss (`band`).
   - keeping the current heading (people commit to a line), and score noise (`noise`: the persona's mistakes).
   The chosen heading may turn no faster than `turn` rad/s.
5. **Nova.** When even the best heading is still dangerous (cornered), it novas if it is down to `nova_hp` hearts,
   unless it forgets (`nova_forget`, rolled once per panic). A veteran (`nova_save`) also novas to save a heart from
   a ring or volley it cannot dodge.
6. **Aim.** At the nearest enemy within 210 px; a casual or veteran aims at a boss when nothing is close.
7. **Class play** (a wizard with a hero other than a MAGE; see below). A wizard with no hero, and a MAGE, play as
   above.
8. **Picks.** `SmashBot.choose_pick` (static, a fixed priority list) stays the default for the arena's demo bots.
   `pick_card(choices, levels)` is the persona policy and `decide_in_world` uses it: a novice takes what is new and
   shiny (an evolution, else something it does not own, at random); a casual takes damage first (evolution, power,
   its spells, cast rate); a veteran chooses an evolution whose requirements it can still meet (most progress
   first, read from the `requires` column of `Upgrades.CATALOG`; a row it can never be offered, CLEAVE for anyone but
   a knight, puts that evolution out of reach), takes what it needs, then takes it. `PICK_PRIORITY` lists every
   evolution, WHIRLWIND (`E_CLEAVE`) last.

Determinism: each bot has its own `RandomNumberGenerator` seeded by its constructor and uses the simulation's clock
(`World.time`), never the wall clock. The same seed and persona give the same inputs.

## Class play

A bot reads its wizard's class from the World (`Player.skill`, `Player.cls`) on every think, in `decide_in_world`
and `apprentice_input` (the arena's view-state `decide` has no hero data and plays as before). `Player.skill` other
than NOVA switches it on, so a seat with no class presses exactly what it pressed before (pinned by
`test_a_seat_with_no_class_plays_as_before`). The numbers are `SmashBot` constants (`ROLE_PLAY` and the rows under
it); the personas' reaction delay, noise and forgetting are untouched.

- **Movement by role** (`ROLE_PLAY`, multiplying the persona's caution and body margin and the circling bonus):
  - tank (KNIGHT, and the PALADIN as tank and support), beside a teammate: caution x0.5 (paladin x0.6), margin
    x0.7 (x0.8), no circling. Its goal (`_consider_role`, worth `GUARD_VALUE` against pickups) is the ally with the
    most sensed enemies within `GUARD_R` 90 px (the weakest on a tie), at `GUARD_GAP` 65 px from her toward that
    crowd (at most at the crowd's centre): between them, pulling the crowd off her. Solo the paladin plays the
    damage row.
  - melee (a hero whose class weapon is a sweep: the KNIGHT's CLEAVE), solo too: its role row always, and when no
    stronger goal pulls it (`_consider_melee`, worth `MELEE_VALUE` 1.5) it walks to `MELEE_SPOT` 0.6 of the sweep's
    reach from the nearest enemy, on its own side. With a boss up it keeps the boss within `MELEE_BAND` 0.6 to 1.4
    of its reach (in place of the persona's band) and aims its other spells at the boss even with adds at its feet.
  - healer (PRIEST), beside a teammate: caution x1.2, margin x1.25. Its goal is the most hurt ally, `HEAL_SPOT` x
    `HEAL_REACH` (24 of 40 px) from her on the far side from the enemies near her: her light (a zone near her)
    covers the ally and she stays out of the front. Solo it plays the damage row.
  - ranged (ARCHER), always: caution x1.15, margin x1.5 (keeps range).
  - while a skill keeps it unhurt (`Player.invuln`) a classed bot minds bodies x0.3 (`UNHURT_CAUTION`).
- **The skill on the nova button** (`_decide_skill`; a forget roll at the persona's `nova_forget` per chance, a
  forgotten chance comes back to mind after `FORGET_HOLD` 1 s if it is still there, and the button is left alone for the skill's taunt or safe seconds, at least `SKILL_GAP`, plus the reaction delay).
  Every class also uses it to save itself when cornered, as the nova rule above (PROVOKE and AEGIS make her unhurt,
  VOLLEY rolls her out).
  - PROVOKE: `PROVOKE_CROWD` (3) enemies in its radius within `ALLY_NEAR` 40 px of an ally, or the boss within
    `BOSS_ON_ALLY` 40 px of an ally while in its radius. Never solo unless cornered.
  - VOLLEY: cornered with `VOLLEY_CROWD` (4) enemies within `VOLLEY_R` 40 px. The move of that same decision is the
    roll: straight away from the sensed crowd, else the heading nearest to that whose roll stays in the arena.
  - SANCTUARY: the hearts it heals (each standing hero's missing ones up to its heal) plus `RISE_WORTH` 4 per fallen
    ally in its radius reach the heal (2) solo or the heal + 1 beside a teammate, or a hero is on her last heart.
  - AEGIS: `AEGIS_HEROES` (2) heroes in its radius (her too) about to be hit (a sensed body within `HIT_SOON` 10 px
    of touching, or the boss within 40 px), or one such hero on her last heart.

The playtest prints `skills` (EV_SKILL by skill, and the hearts SANCTUARY healed, summed over the runs) for a group
that used any.

## Personas

All numbers live in `SmashBot.PERSONAS`.

| | NOVICE | CASUAL | VETERAN |
|---|---|---|---|
| reaction delay (`react`) | 0.38 s | 0.22 s | 0.15 s |
| thinks per second (`hz`) | 10 | 12 | 15 |
| lookahead (`look`) | 0.35 s | 0.5 s | 0.75 s |
| threats / shots tracked | 6 / 6 within 110 px | 12 / 12 within 140 px | 16 / 16 within 150 px |
| shots from behind (`rear`) | only within 14 px | within half range | all |
| reads charge tells | no | no | yes |
| greed (danger accepted for a pickup) | 0.7 | 0.5 | 0.6 |
| XP appetite (`xp`) | 1.0 | 1.2 | 1.8 |
| caution / body margin | 0.7 / 14 px | 1.0 / 19 px | 1.1 / 22 px |
| score noise (mistakes) | 0.5 | 0.16 | 0.05 |
| fastest turn | 9 rad/s | 14 rad/s | 20 rad/s |
| nova | cornered at 1 heart, forgets 60% | cornered at 2 hearts, forgets 20% | cornered at 2 hearts, or to save a heart |
| boss range band | none | 60-150 px | 80-160 px |
| picks | new and shiny | damage first | plans an evolution and finishes it |

Measured on seeds 1-6, solo, 4 minutes: novice 18.6 hits/min (5 of 6
out, median about 2 minutes), casual 9.9 (none out), veteran 6.5 (2 of 6 out). The unit test
`tests/sim/sim_bots.gd` checks this order with a 1.2x margin (3 seeds, 42 s of run clock each, about 30 s of CPU).

The gate (`tests/bot/bot.gd`), the autotest and the sims use **CASUAL** (the constructor's default). Pass
`--persona=novice|veteran` to the game (`godot --path . -- --autotest --persona=veteran`) to watch another.

## Cost

A probe script: 4 bots in a 4-wizard World with 300 immortal enemies spread over the arena, 600 ticks, timing
only `decide_in_world` (19 Nov, on the shared 4-CPU box with other workers running):

| persona | us per decide (mean) | us per world tick, 4 bots | us per think |
|---|---|---|---|
| NOVICE | 37 to 43 | 149 to 172 | 241 to 278 |
| CASUAL | 53 to 65 | 211 to 259 | 291 to 358 |
| VETERAN | 81 to 93 | 323 to 370 | 363 to 416 |

(The higher number of each pair was taken at a load average of 5.8 on 4 CPUs.)

Class play (21 Nov, the same probe, three repeats each, load average 2 to 3 on 4 CPUs with a playtest beside it; "classes" gives the four
wizards a knight, a priest, an archer and a paladin):

| persona | before, no class | after, no class | after, classes |
|---|---|---|---|
| CASUAL, us per decide / per tick of 4 | 49 to 58 / 198 to 232 | 52 to 56 / 208 to 224 | 59 to 62 / 234 to 249 |
| VETERAN, us per decide / per tick of 4 | 70 to 79 / 279 to 316 | 71 to 80 / 286 to 320 | 77 to 87 / 309 to 348 |

Budget: 400 us per tick for four bots. A think reads only the enemies in the spatial-grid cells round the wizard,
keeps the nearest few in fixed buffers, and allocates nothing while scoring. Between thinks a decide returns the
held decision. In `sim_waves`' 4-wizard scenario the casual bots cost 342 us per step against 325 for the old
orbit bot (which copied every enemy every tick), measured side by side.

## Apprentices

An apprentice is a computer wizard in a seat (`Net.add_apprentice`, `World.Player.ai`). The World plays it itself
(`WorldApprentices.with_inputs`, called first in `World.step`) for any apprentice the caller gave no input, so the
arena, the sims and the playtest need no code for it. Its brain is `SmashBot.make_apprentice`: the casual persona's
eyes and hands, deciding every `SmashBot.APPRENTICE_TICKS` (3) ticks. All of a World's apprentices decide on the
same tick from one `SmashBot.shared_senses(w)` (the living wizards, hazard rows, boss, shrine rows, the fallen and
who is calling, whether a standing human is hurt); each still reads its own enemies from World's grid. Between
decisions the hands repeat the last one. An apprentice values only what it may take (`APPRENTICE_KINDS`: XP, coins
and gems, which pay the nearest human, boots, the rune shield, a potion at `apprentice_potion_hp` hearts or fewer
while no standing human is hurt), never walks to a shrine, and answers a call: once a fallen human presses her nova
it walks into her circle from anywhere (`CALL_VALUE`) until she stands. Its cards are taken by the World when they
are dealt (`WorldLevels`, `Upgrades.best_pick`), so it never holds a hand.

**Classes.** `Net.add_apprentice()` seats the apprentice with the class that fills the party's first missing role
in `Net.APPRENTICE_ROLES` order: tank (KNIGHT; a PALADIN seat counts as the tank), healer (PRIEST), ranged
(ARCHER), damage (MAGE). A solo mage's apprentices are a KNIGHT, a PRIEST and an ARCHER. The classes are dealt
again on every roster change outside a run (`Net._fill_apprentice_roles`), humans counted first. Its roster row carries
`cls`, `race` 0 and `cls_level` 1 (`hero` stays `{}`), which `Net.seat_builds()` already hands to `World.new`; on
the run's first step (`WorldApprentices.take_class`, from the first `with_inputs`, so after `apply_meta`; once,
`World.classes_taken`) the
World applies a level 1 HUMAN hero of that class (a MAGE keeps her colour's spell). A seat with `cls_level` 0 (an
old caller, the playtest's plain `apprentice`) stays a plain wizard. A human who takes an apprentice's seat drops
its class. The apprentice plays its class (Class play above) with the cheaper apprentice thinking, and still deals
`apprentice_damage`, counts `apprentice_scale` and takes no loot.

Cost (21 Nov, the shared box with a playtest running beside it): a 4-wizard World with 300 enemies, 600 steps,
three apprentices against three idle humans: 2.8 to 3.0 ms per step either way; the difference is inside the noise
(about 0.1 ms). Shots: `--autotest --seats` (one human, two apprentices).

## The playtest tool

```
godot --headless --path . -s tools/playtest.gd -- --runs=6 --wizards=1,2,4 \
  --persona=novice,casual,veteran --seed=1 --minutes=16 --tune=field:value,... --json=/tmp/out.json
godot --headless --path . -s tools/playtest.gd -- --runs=3 --party=casual,apprentice,apprentice --seed=1 --minutes=18
godot --headless --path . -s tools/playtest.gd -- --runs=6 --wizards=1 --persona=casual --hero=knight,archer:elf --minutes=18
godot --headless --path . -s tools/playtest.gd -- --runs=3 --party=casual:knight,casual:priest,apprentice:archer,casual:mage
```

Classes: a `--party` seat is `persona[:class[:race]]` (`apprentice` too), and `--hero=class[:race],...` plays every
persona x wizards group once per listed class, every seat that hero. Keys or indices; HUMAN unless a race is given.
A human seat with a class gets `World.apply_hero` of a level 1 `Hero.make` (school: its wizard, so a mage keeps her
spell) right after `World.new` (the playtest applies no meta); an apprentice seat with one is seated with the class
and the World makes it the hero. Without a class a seat plays exactly as before. Headers name the classes:
`casual:knight x1`, `casual:knight+casual:priest+ap:archer+casual:mage x4` (a plain apprentice still counts in
`+Nap`).

`--party` plays one party instead of the persona x wizards groups: each seat a persona name (a human bot) or
`apprentice` (the World plays it). Its table is headed like `casual+2ap`, `human down` is the first down of a seat
that is no apprentice, and the `PLAYTEST` line gives wins, the median end, first down, human down and the party
level at 6:00 (`lv6`).

Each persona and party size plays `--runs` whole runs on seeds `--seed..seed+runs-1` (the same seeds for every
group, so groups compare), up to `--minutes` of run clock (16 covers the Archlich at 15:00). `--tune` applies
`Tuning` fields to every run. A 16-minute solo run takes about 5 minutes of wall time on the shared box and 4 wizards take longer: run one
process at a time, and use few seeds. `--json` writes every number, per run and per group.

Reading a group's table:

- `win`, `end`, `wipe`, `first down`, `out`: wins, and the run clock (median [min..max]) at the end, at a wipe, at
  the first down and at each wizard going out for good.
- `per min`: downs, hits taken, picks (level-up cards dealt to the party: how often someone has a choice to make)
  and damage dealt.
- The minute table: mean party level, picks, pressure (enemies within 60 px of a wizard, averaged) and dead air
  (seconds of the minute with no enemy within 150 px of anyone). Samples are taken every 6 ticks while the run
  clock moves and nobody holds cards.
- `damage`: share of damage by spell (plus nova and the orbit powerup).
- `hits by`: what hit the wizards (the enemy touching them, else `shot`).
- `spell lv`: the mean of the highest level each spell reached (6 = evolved).
- `taken`: each upgrade taken / offered.
- `evolved`: runs with an evolution, and when the first came.
- `xp lost`: XP motes that faded on the floor, of all that dropped; gold earned and spent; shrine bets by outcome.
- `boss n`: each Lich visit and the Archlich: arrival, fight length, downs during it, slain.
- `kills` (per minute, in the minute table), `shrines` used per run with the Archlich fight time and slain count
  (also in the `PLAYTEST` line), and `per wiz`: each wizard's pressure and hits per minute, for party parity.
- `hits by` splits shots by kind: `shot:arrow`, `shot:orb`, `shot:skull`, with `_boss` while a Lich is up; `other`
  is a hit from a body that died in the same step.
- Use `--minutes=18` when the Archlich matters: his fight runs 90 to 150 s from 15:00, and a 16-minute cap counts
  an unfinished fight as a loss.

The last line starts `PLAYTEST` and sums every group: wins and the median end.

The tool reads `Spells.COUNT`, `Upgrades.CATALOG` and the `World` event stream, so new spells, passives and
evolutions show up without changes. It names enemies from a 12-entry list (`_enemy_name`; a 13th kind prints as
`enemy12`) and shrine outcomes from `Gamble`'s constants.

## Win rates: two 100-run arms

A group of four is a record of lines, not a win rate. On main `9ea2f5b6` the stations' runs (28 Nov, 1,315 runs
in every version of `wandsrun.csv` on `station-results`) gave the casual 17/24 solo, 16/27 with two wizards (0.59,
95% 0.41 to 0.75), 25/26 with three and 22/23 with four; the veteran 0.73 to 0.82; the novice 1/254. With 0.59, a
change with no effect fails "3 of its 4 runs" about half the time, and moving only the random stream (a placebo of
twelve draws at the first step) took the seed 7 group from 7/8 to 3/8 wins.

A win rate is two arms of 100 runs on the same seeds, the change and the commit it sits on:

```
git push origin <commit>:refs/heads/try/<name>          # no workflow fires on try/ branches
gh workflow run balance.yml -f ref=try/<name> -f label=<name> [-f runs=100] [-f seed0=1] [-f wizards=2]
    [-f persona=casual] [-f words="--meta=start_level:2"]
python3 tools/balance_compare.py <run id A> <run id B>    # A the base, B the change
```

`.github/workflows/balance.yml` plays `runs`/5 jobs of five seeds each (`tools/playtest.gd` from the ref's own tree,
`--minutes=30`, at most 12 jobs at once) and its job `sum` prints `BALANCE ... runs= won= rate= lo= hi=
unfinished= missing= broken_jobs=` and one `BALROW` line a job. `tools/balance_compare.py` reads those lines through
the GitHub API (no artifact download) and prints `COMPARE a= b= seeds= a_won= b_won= diff= lo= hi=
verdict=lower|same|higher`, from Newcombe's 95% interval of the difference on the seeds both arms played. An arm of
100 runs tells apart a difference of about 0.14 or more (at a rate near 0.6); `same` is not proof of no effect. Its self-test is
`tools/balance_compare_test.py` (CI row `tools`).

## Baseline (19 Nov 2026, before shared XP)

Command: `--runs=2 --wizards=1,4 --persona=novice,casual,veteran --seed=1 --minutes=6` (seeds 1 and 2; short runs that
cover the first Lich, because the box was shared by five workers; a 16-minute solo run took about 5 minutes of
wall time). Full output: rerun the command; `--json` keeps every number.

| group | out / wipe | first down | hits/min | downs/min | picks/min | pressure m1 / m6 | level at 6:00 | XP motes lost | gold earned / spent | Lich 5:02 fight |
|---|---|---|---|---|---|---|---|---|---|---|
| novice x1 | 1 of 2 out at 1:06 | 1:00 [0:22..1:39] | 16.2 | 0.70 | 2.7 | 12.0 / 1.4 | 16 | 16% | 746 / 0 | 0:27 |
| novice x4 | none | 0:15 | 30.7 | 0.58 | 10.3 | 6.9 / 0.7 | 16.4 | 14% | 6613 / 0 | 0:19 |
| casual x1 | 1 of 2 out at 5:29 | 1:23 | 8.5 | 0.43 | 2.3 | 13.2 / 0.8 | 14 | 30% | 1101 / 82 | 0:11 |
| casual x4 | none | 0:31 | 16.9 | 0.08 | 9.9 | 7.8 / 0.4 | 15.9 | 16% | 6197 / 178 | 0:03..0:18 |
| veteran x1 | none | 1:36 | 4.5 | 0.17 | 2.2 | 5.6 / 0.6 | 14 | 31% | 968 / 248 | 0:08 |
| veteran x4 | none, no downs | - | 12.3 | 0.00 | 9.9 | 6.3 / 0.5 | 15.9 | 20% | 6771 / 328 | 0:03 |

(Gold is per run. Hits and picks are per minute for the whole party.)

What else the tables show:
- Hits come from enemy shots (29 to 48%), goblins (20 to 39%) and bats (7 to 18%).
- Damage: chain lightning and starfall lead (19 to 33% each); the arcane bolt deals 1 to 12% and is the card
  taken least often by casual and veteran parties. By 6:00 nearly every spell is at level 5 or evolved; the first
  evolution comes at 0:46 to 2:03.
- An earlier 16-minute solo run with a previous version of the novice (3 seeds): pressure stayed at about 1 from
  minute 3 to 16, the Lich fell in 7 to 26 s at 5:02 and in 4 to 5 s at 10:02, and the novice beat the Archlich
  (15:02, 34 to 57 s fight) in 1 of 3 runs.

Findings for the designer:
1. The first minute is the hardest of the run: 12 to 13 enemies within 60 px of a solo novice or casual in minute 1,
   about 1 from minute 3 on. Solo novices go down at 0:22 to 1:39, one was out at 1:06, and nobody who survives
   minute 2 is in danger again before the Lich.
2. After minute 2 the game is too easy and too generous: pressure under 1, every wizard at level 14 to 16 by 6:00,
   nearly every spell maxed or evolved by then, and the first evolution before 2:03 in every group.
3. The Lich is not a fight: it dies 3 to 27 s after it arrives at 5:02, with no downs in solo runs and one down in
   six 4-wizard runs.
4. 4-wizard parties get about 10 cards a minute (14 to 17.5 in minute 1), so somebody always has a choice to make;
   solo it is 2 to 4 a minute.
5. A lot of XP rots on the floor (14 to 31% of motes fade) and gold piles up unspent (solo 750 to 1100 gold earned
   per 6-minute run, 0 to 248 spent): shrines appear too rarely, too far away or too briefly to matter.

## The hero shard

Every headless run is scripted, so the shards 0 to 2, the sims and golden seat no heroes and use no unlock bonuses.
`res://tests/bot/bot.tscn -- --heroes` (CI row `bot-heroes`, `check_all` task `botheroes`) plays seed 104 with four
local seats on saved heroes, so a bug in heroes, cards, unlock bonuses or run booking can turn a check red.

- **Setup** (`tests/bot/bot_heroes.gd`): an in-memory `Profile` (never written: `Save.write` still refuses in a scripted
  run) with HUMAN MAGE, ELF ARCHER, DWARF KNIGHT and ORC PRIEST at different levels with spent points, the elf holding THE
  OOZE (+1 heart), the dwarf THE NIGHT WING and THE WARCHIEF, the unlocks vigor 1 and might 2. `Net.force_heroes` is set
  before the seats join. It is the only switch: `G.finish_run` books `run_heroes` and `Save.run_bonuses()` returns the
  profile's bonuses when it is set, even in a scripted run.
- **Private save folder**: start the shard with `tools/private_save.sh <command>` (CI and `check_all` do). It makes a
  folder, points the engine's `user://` into it (`XDG_DATA_HOME` on Linux, `APPDATA` on Windows, which is the only
  place Godot reads there) and names it in `PRIVATE_SAVE`. The shard refuses to start unless `user://` lies inside
  that folder (`save_is_private` in `tests/bot/bot_heroes.gd`, `test_private_save`), and fails if
  `user://profile.json` exists at the end.
- **At the start of the fight** each seat's class, race, hearts and every armour stat must equal what her hero gives
  (`Hero.stats()`, the class's hearts) plus the meta, each socketed card counted once. Mismatch: one
  `BOT heroes seat=n hero=NAME FAIL ... expected ... got ...` line per seat.
- **The end**: at 62 s of fight (class XP pays per whole minute) the bot hurts every standing wizard through
  `World.hurt_player` until the party is down; the World ends the run, the arena books it through `G.finish_run`, and
  the bot checks the profile: one run counted, crystals earned, `last_hero_levels` names the four seated heroes, each
  hero's class XP grew. It prints `BOT heroes PASS ...` or a ` FAIL ` line, then the usual `BOT shard=3 ...` and
  `BOT score=...` lines. About 30 s.
- **Every bot row fails on an engine error**: `tests/bot/no_engine_errors.sh <log>` fails a run whose output has a
  `SCRIPT ERROR:` or `ERROR:` line (the rule of `tools/run_tests.sh`: any engine error but a warning), except the
  engine's own exit report `ERROR: n resources still in use at exit`, printed after the game has quit.

## The boss, win and again shards

Three more shards of `tests/bot/bot.tscn` (shard 3's seed 104 and four seats, the hero shard's four saved heroes, the
hero shard's refusal to start outside a private save folder). CI rows `bot-boss`, `bot-win`, `bot-again`; `check_all` tasks
`botboss`, `botwin`, `botagain`. Each prints `BOT <name> PASS ...` or one `BOT <name> FAIL <why>` line per fault, then
the usual `BOT shard=...` and `BOT score=...` lines. Where the shard forces something it says so below.

- **`-- --boss`** (`tests/bot/bot_boss.gd`, about 16 s). The run's clock is moved to 0.5 s before the first act boss's
  minute with the two assignments `--autotest=<wave>` makes (`World.wave`, `World.wave_time`), then the bots play.
  Checks: the boss came between its scheduled second and 4 s later (the spawn queue's 2.5 s), at the scheduled
  minute, of the scheduled type; its health fell in 20 s of fight; at 20 s the shard fells it through
  `World.damage_enemy` and reads the events that call adds: one `EV_BOSSDIE` (final flag 0), one `EV_LULL`, no
  `EV_VICTORY`, `liches_slain` 1, one `M_ACT_BOSS` moment naming the type, one chest per wizard and 14 or more gems and
  coins on the floor, `World.boss` cleared; four wizards still in the World and the roster; the hero shard's start
  check on every seat. Cannot prove: `EV_BOSS` (the arrival event; the arena takes it before the shard can look, the
  shard sees `World.boss` instead), anything about how the boss fight is won (the kill is forced), the second act boss.
- **`-- --win`** (about 20 s). The same, with the clock moved to just before the Archlich's minute and the run played at
  the ARCHMAGE step (`Net.seal = 1`, a lobby choice: a first win at WIZARD opens no new step). After the forced kill:
  `EV_BOSSDIE` (final flag 1) before `EV_VICTORY`, no lull, `World.won`, and its death adds no chest (the final boss
  pays only its burst of gems and coins; both shards count the chests the death itself added); then the shard waits
  through the victory countdown for the arena's results. Checks on the profile in memory: the arena reports a
  victory; runs +1, wins +1; crystals up by at least the win bounty, the step's first-win prize and the deeds' pay;
  `seal_best` and
  `seal_unlocked` moved, the prize is claimed; the deeds ARCHLICH, PARTY_WIN, LICH, TEN_MINUTES, WIN_MAGE, WIN_ARCHER,
  WIN_KNIGHT, WIN_PRIEST and WIN_ARCHMAGE are in `Profile.deeds` and SOLO_WIN is not; each seated hero gained class
  XP, `last_hero_levels` names them; `user://profile.json` does not exist. Cannot prove: a won run that was played to
  the end (the clock is moved 14 minutes, the party has no upgrades from those minutes), FLAWLESS and the deeds that
  depend on how the bots fared.
- **`-- --again`** (in `bot.gd`, about 30 s). Run 1 ends in a defeat as in the hero shard (hurt at 62 s). Then, as a
  player: the results screen takes the confirm key (SPACE; the first press turns the results page, the next leaves),
  the scene is the Sanctum, the net is offline; the shard calls `G.goto_title_lobby(G.DEV_KBM)` (what the portal
  calls: walking to it is the Sanctum's own business) and, once the title shows its lobby, presses ENTER (player 1's
  START). Checks: the second run's World has a new clock (under 2 s, minute 1), every wizard at full hearts, player 1 on
  the same saved hero, the hero shard's start check (stats, hearts incl. the unlock bonuses, `meta_damage`), as many
  wizards as the lobby seated; then run 2 is felled at 5 s and the profile's `runs` must be the start value + 2; no
  profile file. It prints the seats of both runs: players 2 to 4 join again after a run (known, not a fault).
  Cannot prove: the Sanctum's walking and portal, a party that stays seated, LAN.
- **A shard that frees the arena** must not guard on `_arena == null`: a freed node reads as null, so the again shard
  runs off `G.main.current` (the first version of it stalled silently at the results screen for that reason).

## The coverage robot

Stage 3's gate: robots finish runs that use every row of the content list (`docs/stage3_brief.md` § 1, § 4.4; the Test
letter B of `docs/content_list.md` § 36). `tests/bot/bot_cover.gd` plays one fresh run of the real game per row
(headless, two seats, the play-bots playing), deals the row by force to the first seat before the first step
(`WorldGrants.give`: past every lock, ban, slot cap and `Upgrades.UNBUILT`, with what the row requires), and plays
until the row is **credited** and a second more, or until 40 s of game time.

- Run every shard: `tests/bot/cover.sh [nshards=2]` (`COVER_ALL shards= rows= ok= pending= failed= bad_shards=`; CI row
  `bot-cover`, `check_all` tasks `botcover<i>`). One row: `godot --headless --fixed-fps 60 --path .
  res://tests/bot/bot.tscn -- --cover --deal=<key>`. The plan without playing: `godot --headless --path . -s
  tools/tool.gd -- coverage [--gate]` (`COVERAGE rows= cover= pending= unbuilt=`; `--gate` exits 1 unless pending and
  unbuilt are both 0: the stage 3 gate).
- Lines: `COVER <key> ok uses=N t=<game s>`, `COVER <key> pending`, `COVER <key> FAIL <why>`; a row also fails on an
  engine error it caused. About 1.6 s of wall time a row plus 5 s to start a shard: keep a shard under about 18 rows.
- Credit: a SPELL or EVOLUTION row by the damage the dealt seat does with it (an evolution only while that very row is
  held); every other row by its use counter, `w.record.use("<key>", slot)` where its effect lands (`Results.used`).
- `PENDING` in the robot lists the rows nothing credits yet. A pending row is played for 12 s and not failed for the
  missing credit, but it **fails when it is credited**, so the list cannot rot: the job that credits a row takes its key
  off the list.
- Families: `catalog.gd` (the level-up catalog), `readings.gd` (the sixteen Readings, dealt by
  `World.apply_reading`, unbuilt while in `Readings.UNBUILT`) and `shop.gd` (the shop rows whose Test letters hold a B,
  `start_level` and `favour`: dealt by `World.apply_meta` with the row at level 1 before the first step, a deal after
  it is an engine error; credited by `shop_<key>`; unbuilt while in `Profile.UNBUILT`). A new family of rows (Seals,
  monster cards, provisions) is one script in `tests/bot/cover/` that extends `family.gd`: `family()`, `keys()`,
  `unbuilt(key)`, `deal(w, p, key)`, `credit(w, p, key)`. The robot and the plan find it by its file. Keys are unique
  across families.
- Cannot prove: that a row's effect is the right size or looks right (the damage table, the unit tests and the
  pictures do that), or that a human would ever be offered it (the catalog's own tests).

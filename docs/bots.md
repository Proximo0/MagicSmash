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
7. **Picks.** `SmashBot.choose_pick` (static, a fixed priority list) stays the default for the arena's demo bots.
   `pick_card(choices, levels)` is the persona policy and `decide_in_world` uses it: a novice takes what is new and
   shiny (an evolution, else something it does not own, at random); a casual takes damage first (evolution, power,
   its spells, cast rate); a veteran chooses an evolution whose requirements it can still meet (most progress
   first, read from the `requires` column of `Upgrades.CATALOG`), takes what it needs, then takes it.

Determinism: each bot has its own `RandomNumberGenerator` seeded by its constructor and uses the simulation's clock
(`World.time`), never the wall clock. The same seed and persona give the same inputs.

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

Cost (21 Nov, the shared box with a playtest running beside it): a 4-wizard World with 300 enemies, 600 steps,
three apprentices against three idle humans: 2.8 to 3.0 ms per step either way; the difference is inside the noise
(about 0.1 ms). Shots: `--autotest --seats` (one human, two apprentices).

## The playtest tool

```
godot --headless --path . -s tools/playtest.gd -- --runs=6 --wizards=1,2,4 \
  --persona=novice,casual,veteran --seed=1 --minutes=16 --tune=field:value,... --json=/tmp/out.json
godot --headless --path . -s tools/playtest.gd -- --runs=3 --party=casual,apprentice,apprentice --seed=1 --minutes=18
```

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

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
| greed (danger accepted for a pickup) | 0.85 | 0.5 | 0.6 |
| XP appetite (`xp`) | 1.0 | 1.2 | 1.8 |
| caution / body margin | 0.65 / 14 px | 1.0 / 19 px | 1.1 / 22 px |
| score noise (mistakes) | 0.5 | 0.16 | 0.05 |
| fastest turn | 9 rad/s | 14 rad/s | 20 rad/s |
| nova | cornered at 1 heart, forgets 60% | cornered at 2 hearts, forgets 20% | cornered at 2 hearts, or to save a heart |
| boss range band | none | 60-150 px | 80-160 px |
| picks | new and shiny | damage first | plans an evolution and finishes it |

Measured on 6 seeds, solo, 4 minutes: novice 16.2 hits/min (3 of 6 wiped), casual 7.9, veteran 5.8.

The gate (`tests/bot/bot.gd`), the autotest and the sims use **CASUAL** (the constructor's default). Pass
`--persona=novice|veteran` to the game (`godot --path . -- --autotest --persona=veteran`) to watch another.

## Cost

A probe script: 4 bots in a 4-wizard World with 300 immortal enemies spread over the arena, 600 ticks, timing
only `decide_in_world` (19 Nov, on the shared 4-CPU box with other workers running):

| persona | us per decide (mean) | us per world tick, 4 bots | us per think |
|---|---|---|---|
| NOVICE | 37 | 149 | 241 |
| CASUAL | 53 | 211 | 291 |
| VETERAN | 81 | 323 | 363 |

Budget: 400 us per tick for four bots. A think reads only the enemies in the spatial-grid cells round the wizard,
keeps the nearest few in fixed buffers, and allocates nothing while scoring. Between thinks a decide returns the
held decision. In `sim_waves`' 4-wizard scenario the casual bots cost 302 us per step (the old orbit bot, which
copied every enemy every tick, cost 277).

## The playtest tool

```
godot --headless --path . -s tools/playtest.gd -- --runs=6 --wizards=1,2,4 \
  --persona=novice,casual,veteran --seed=1 --minutes=16 --tune=field:value,... --json=/tmp/out.json
```

Each persona and party size plays `--runs` whole runs on seeds `--seed..seed+runs-1` (the same seeds for every
group, so groups compare), up to `--minutes` of run clock (16 covers the Archlich at 15:00). `--tune` applies
`Tuning` fields to every run. A 16-minute run takes about 1 to 3 minutes of wall time (4 wizards cost most): run one
process at a time. `--json` writes every number, per run and per group.

Reading a group's table:

- `win`, `end`, `wipe`, `first down`, `out`: wins, and the run clock (median [min..max]) at the end, at a wipe, at
  the first down and at each wizard going out for good.
- `per min`: downs, hits taken, picks (level-up offers: how often the game stops for cards) and damage dealt.
- The minute table: mean party level, picks, pressure (enemies within 60 px of a wizard, averaged) and dead air
  (seconds of the minute with no enemy within 150 px of anyone).
- `damage`: share of damage by spell (plus nova and the orbit powerup).
- `hits by`: what hit the wizards (the enemy touching them, else `shot`).
- `spell lv`: the mean of the highest level each spell reached (6 = evolved).
- `taken`: each upgrade taken / offered.
- `evolved`: runs with an evolution, and when the first came.
- `xp lost`: XP motes that faded on the floor, of all that dropped; gold earned and spent; shrine bets by outcome.
- `boss n`: each Lich visit and the Archlich: arrival, fight length, downs during it, slain.

The last line starts `PLAYTEST` and sums every group: wins and the median end.

The tool reads `Spells.COUNT`, `Upgrades.CATALOG` and the `World` event stream, so new spells, passives and
evolutions show up without changes. It names enemies from a 12-entry list (`_enemy_name`; a 13th kind prints as
`enemy12`) and shrine outcomes from `Gamble`'s constants.

## Baseline (19 Nov 2026, before shared XP)

BASELINE

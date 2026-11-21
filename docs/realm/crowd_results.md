# The crowd test: results (21 Nov 2026)

Measured on a 4-core, 15 GB cloud machine with `realm/` at this commit. The contract is `crowd_test.md`; how to
rerun is in `realm/README.md`. The budget is 50 ms a tick (20 ticks a second).

## The answer
- **1 000 players with 20 000 monsters passes with room to spare**: 4.4 ms mean, 8.2 ms slowest-1% tick on 4 cores
  with 30% of the players rallied into one fight (6.3 / 13.0 ms on one core).
- **2 000 with 50 000 holds**: 10.5 / 22.8 ms on 4 cores.
- **5 000 with 100 000 breaks**: 47 / 101 ms on 4 cores. The simulation is only about 6.5 ms of that; building
  snapshots for 5 000 clients is 31 ms. Known fixes: stagger snapshots over ticks, encode each grid cell once.
- **Data per player, snapshots (A)**: spread out 1.5 kB/s (v0) or 1.0 kB/s (v1); in a 300-player rally 6.0 kB/s mean
  and 27 kB/s slowest 1% (v1: 2.5 / 13); all 1 000 players on one spot over real sockets 34 kB/s mean, 89 kB/s
  slowest 1%. A zoomed-out window (zoom 4) took 98 kB/s.
- **Data per player, lockstep (B)**: 6.2 to 7.5 kB/s at 1 000 players wherever they stand, for the whole field
  (12 kB/s at 2 000, 25 kB/s at 5 000). Joining downloads 277 kB. A follower needs 2.8 ms of CPU a tick. Hashes
  agreed on every check, in the bench and over real UDP (20 of 20).
- **The game window** (software rendering, no graphics card, so a lower bound): 117 / 99 / 63 frames a second at
  zoom 1 / 2 / 4 against the real server, with 1 834 figures drawn at zoom 4; decode plus fill 0.4 / 1.0 / 2.6 ms.
- **The same state on any core count**: 1, 2, 3 and 4 threads give the same hash.

## What it does not show yet
- The rules are a test bench's: bulk hits, simple monsters, no projectiles, loot or saves. Real rules cost more.
- One machine, no real internet: no packet loss, no latency, no second computer checking the hashes.
- No graphics card and no Windows build of the window.
- A screen shows at most the nearest 1 500 monsters and 200 players in detail (the protocol's caps).

## The lead's rerun (quiet machine, `--rally=0.3`, 300 ticks, 100 warm-up)
```
   1000x20000   1 |  6.26/12.99 ms | encA0 2.82/8.18 | A0 6.0k/27k  A1 2.5k/13k  B 6.2k/6.3k | hash=82ba59b0b4f75321
   1000x20000   4 |   4.37/8.24 ms | encA0 1.61/4.67 | same bytes                            | hash=82ba59b0b4f75321
   2000x50000   4 | 10.49/22.79 ms | encA0 5.40/15.32| A0 9.7k/53k  A1 4.5k/25k  B 12k        | hash=417c0ead81df9ca8
  5000x100000   4 | 47.22/101.10 ms| encA0 31.34/74.08| A0 18k/102k A1 11k/56k   B 25k        | hash=d712457169953142
```

## The worker's full table (raw output of the bench)
Columns: players x monsters, threads, ticks | tick ms mean/p99 | flow, move, grid, fight, spawn, input, bots,
encode A v0, encode A v1, encode B (ms mean/p99) | bytes a second per client A v0, A v1, B (mean/p99) | monsters
and players in view (mean/p99) | join bytes for B | follower ms | hash agreement.
```
### bots=1000 monsters=20000 rally=0 threads=1
   1000x20000   1    300 |     4.75/8.26 |   0.64/1.07   1.37/2.04   0.61/0.88   0.08/0.42   0.02/0.14   0.01/0.02   0.05/0.08   1.62/4.56   0.33/1.03   0.01/0.11 |     1.5k/2.8k      995/1.7k     7.5k/7.7k |     18/42       0/2 |    277k |   2.82/4.60 | ok 10
BENCH 1000x20000 threads=1 ticks=300 wall=2.0s kills=27726 spawns=47726 deaths=26 recycled=0 hash=31603981bf482d05
### bots=1000 monsters=20000 rally=0 threads=2
   1000x20000   2    300 |     4.52/8.43 |   0.77/1.11   1.23/1.57   0.73/0.96   0.22/0.61   0.02/0.14   0.01/0.02   0.05/0.11   1.01/2.93   0.44/1.41   0.01/0.12 |     1.5k/2.8k      995/1.7k     7.5k/7.7k |     18/42       0/2 |    277k |           - | -
BENCH 1000x20000 threads=2 ticks=300 wall=1.3s kills=27726 spawns=47726 deaths=26 recycled=0 hash=31603981bf482d05
### bots=1000 monsters=20000 rally=0 threads=4
   1000x20000   4    300 |     3.46/7.78 |   0.63/0.98   0.80/1.50   0.65/0.91   0.25/0.66   0.02/0.16   0.01/0.01   0.04/0.07   0.66/1.88   0.36/0.86   0.01/0.11 |     1.5k/2.8k      995/1.7k     7.5k/7.7k |     18/42       0/2 |    277k |           - | -
BENCH 1000x20000 threads=4 ticks=300 wall=1.1s kills=27726 spawns=47726 deaths=26 recycled=0 hash=31603981bf482d05
### bots=1000 monsters=20000 rally=0.3 threads=1
   1000x20000   1    300 |    7.26/14.65 |   0.71/1.20   1.46/2.19   0.65/1.19   0.09/0.55   0.02/0.17   0.01/0.02   0.04/0.07   3.36/9.12   0.87/2.48   0.01/0.12 |      6.0k/27k      2.5k/13k     6.2k/6.3k |    43/387    40/193 |    277k |   2.97/5.11 | ok 10
BENCH 1000x20000 threads=1 ticks=300 wall=2.7s kills=23416 spawns=43416 deaths=15 recycled=0 hash=82ba59b0b4f75321
### bots=1000 monsters=20000 rally=0.3 threads=2
   1000x20000   2    300 |    6.20/12.64 |   0.70/1.15   1.26/2.77   0.67/1.06   0.24/0.69   0.02/0.18   0.01/0.03   0.04/0.07   2.39/6.55   0.84/3.05   0.01/0.12 |      6.0k/27k      2.5k/13k     6.2k/6.3k |    43/387    40/193 |    277k |           - | -
BENCH 1000x20000 threads=2 ticks=300 wall=1.9s kills=23416 spawns=43416 deaths=15 recycled=0 hash=82ba59b0b4f75321
### bots=1000 monsters=20000 rally=0.3 threads=4
   1000x20000   4    300 |     4.74/9.66 |   0.65/1.08   0.75/1.17   0.66/0.90   0.25/0.47   0.02/0.17   0.01/0.02   0.04/0.08   1.73/4.91   0.60/2.10   0.01/0.11 |      6.0k/27k      2.5k/13k     6.2k/6.3k |    43/387    40/193 |    277k |           - | -
BENCH 1000x20000 threads=4 ticks=300 wall=1.5s kills=23416 spawns=43416 deaths=15 recycled=0 hash=82ba59b0b4f75321
### bots=2000 monsters=50000 rally=0 threads=1
   2000x50000   1    300 |   12.65/24.70 |   0.82/1.26   3.77/5.35   0.91/1.29   0.18/1.13   0.11/0.83   0.02/0.04   0.09/0.14  5.59/15.43   1.09/2.97   0.02/0.27 |     2.6k/6.4k     1.6k/3.5k       14k/14k |    35/103       1/4 |    674k |   5.81/8.64 | ok 10
BENCH 2000x50000 threads=1 ticks=300 wall=4.8s kills=76882 spawns=126882 deaths=65 recycled=0 hash=0e9ecf91b64a6d2f
### bots=2000 monsters=50000 rally=0 threads=2
   2000x50000   2    300 |    8.68/15.28 |   0.80/1.25   2.47/3.21   0.97/1.35   0.34/1.07   0.12/0.83   0.02/0.04   0.09/0.15   2.92/7.99   0.91/2.94   0.02/0.28 |     2.6k/6.4k     1.6k/3.5k       14k/14k |    35/103       1/4 |    674k |           - | -
BENCH 2000x50000 threads=2 ticks=300 wall=2.6s kills=76882 spawns=126882 deaths=65 recycled=0 hash=0e9ecf91b64a6d2f
### bots=2000 monsters=50000 rally=0 threads=4
   2000x50000   4    300 |    6.34/12.62 |   0.70/1.08   1.54/3.03   0.92/1.59   0.35/1.09   0.11/0.73   0.02/0.03   0.08/0.11   1.85/5.15   0.72/3.02   0.02/0.27 |     2.6k/6.4k     1.6k/3.5k       14k/14k |    35/103       1/4 |    674k |           - | -
BENCH 2000x50000 threads=4 ticks=300 wall=1.9s kills=76882 spawns=126882 deaths=65 recycled=0 hash=0e9ecf91b64a6d2f
### bots=2000 monsters=50000 rally=0.3 threads=1
   2000x50000   1    300 |   19.54/45.49 |   0.82/1.32   3.73/6.16   0.94/1.46   0.22/1.31   0.13/0.90   0.02/0.05   0.08/0.13 10.62/31.01   2.93/9.31   0.02/0.26 |      9.7k/53k      4.5k/25k       12k/12k |    66/736    81/399 |    674k |   5.92/9.10 | ok 10
BENCH 2000x50000 threads=1 ticks=300 wall=6.8s kills=64698 spawns=114698 deaths=65 recycled=0 hash=417c0ead81df9ca8
### bots=2000 monsters=50000 rally=0.3 threads=2
   2000x50000   2    300 |   14.63/35.00 |   0.74/1.22   2.36/5.17   0.91/1.35   0.33/1.20   0.13/0.69   0.02/0.04   0.07/0.11  7.79/23.02   2.24/6.82   0.02/0.29 |      9.7k/53k      4.5k/25k       12k/12k |    66/736    81/399 |    674k |           - | -
BENCH 2000x50000 threads=2 ticks=300 wall=4.3s kills=64698 spawns=114698 deaths=65 recycled=0 hash=417c0ead81df9ca8
### bots=2000 monsters=50000 rally=0.3 threads=4
   2000x50000   4    300 |   10.43/22.40 |   0.67/0.94   1.31/2.19   0.87/1.10   0.33/1.02   0.12/0.77   0.02/0.05   0.07/0.10  5.33/14.02   1.65/5.40   0.02/0.29 |      9.7k/53k      4.5k/25k       12k/12k |    66/736    81/399 |    674k |           - | -
BENCH 2000x50000 threads=4 ticks=300 wall=3.1s kills=64698 spawns=114698 deaths=65 recycled=0 hash=417c0ead81df9ca8
### bots=5000 monsters=100000 rally=0 threads=1
   5000x58565   1    300 |   22.73/48.87 |   0.88/1.24   3.33/4.27   0.91/1.19   0.40/2.81   1.57/1.87   0.05/0.08   0.17/0.24 12.87/34.94   2.45/7.39   0.03/0.43 |      2.3k/13k     1.4k/7.1k       24k/25k |    27/220       4/9 |   1136k |  7.25/11.22 | ok 10
BENCH 5000x58565 threads=1 ticks=300 wall=7.7s kills=101357 spawns=159922 deaths=21 recycled=0 hash=d76ebea57f21651f
### bots=5000 monsters=100000 rally=0 threads=2
   5000x58565   2    300 |   17.19/36.16 |   0.84/1.38   3.58/5.11   0.97/1.48   0.55/2.93   1.64/2.21   0.05/0.11   0.19/0.38  7.36/20.41   1.92/7.44   0.03/0.45 |      2.3k/13k     1.4k/7.1k       24k/25k |    27/220       4/9 |   1136k |           - | -
BENCH 5000x58565 threads=2 ticks=300 wall=5.0s kills=101357 spawns=159922 deaths=21 recycled=0 hash=d76ebea57f21651f
### bots=5000 monsters=100000 rally=0 threads=4
   5000x58565   4    300 |   12.12/21.60 |   0.77/1.15   2.18/2.94   0.89/1.32   0.44/1.58   1.58/2.09   0.05/0.07   0.17/0.30  4.41/11.11   1.58/3.99   0.03/0.42 |      2.3k/13k     1.4k/7.1k       24k/25k |    27/220       4/9 |   1136k |           - | -
BENCH 5000x58565 threads=4 ticks=300 wall=3.6s kills=101357 spawns=159922 deaths=21 recycled=0 hash=d76ebea57f21651f
### bots=5000 monsters=100000 rally=0.3 threads=1
  5000x100000   1    300 |  76.13/168.44 |   0.94/1.42  7.01/10.26   1.51/2.54   0.62/3.98   1.17/6.74   0.04/0.07   0.20/0.34 50.55/125.64 13.96/37.08   0.04/0.55 |      18k/102k       11k/56k       25k/25k |  124/1500  205/1015 |   1385k | 11.72/19.54 | ok 10
BENCH 5000x100000 threads=1 ticks=300 wall=24.3s kills=160690 spawns=260690 deaths=67 recycled=0 hash=d712457169953142
### bots=5000 monsters=100000 rally=0.3 threads=2
  5000x100000   2    300 |  61.36/133.55 |   0.89/1.34   4.03/5.80   1.42/2.03   0.69/3.61   1.14/6.52   0.04/0.07   0.17/0.24 40.96/99.41 11.90/31.47   0.04/0.56 |      18k/102k       11k/56k       25k/25k |  124/1500  205/1015 |   1385k |           - | -
BENCH 5000x100000 threads=2 ticks=300 wall=17.9s kills=160690 spawns=260690 deaths=67 recycled=0 hash=d712457169953142
### bots=5000 monsters=100000 rally=0.3 threads=4
  5000x100000   4    300 |  47.58/111.03 |   0.90/1.35   2.37/4.76   1.48/2.51   0.58/2.31   1.15/6.40   0.05/0.08   0.21/0.34 31.52/83.64  9.21/24.36   0.04/0.58 |      18k/102k       11k/56k       25k/25k |  124/1500  205/1015 |   1385k |           - | -
BENCH 5000x100000 threads=4 ticks=300 wall=13.9s kills=160690 spawns=260690 deaths=67 recycled=0 hash=d712457169953142
```

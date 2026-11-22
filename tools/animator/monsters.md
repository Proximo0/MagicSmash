# Monster kinds: body plan, size, move style

Generated from `monsters.json` (`python3 -m tools.animator monsters --table`); the 42 kinds are the table
`realm/core/src/tables/kinds.rs`. `size_px` is the longest side of the creature at the 112 px hero scale
(a hero is 112 tall); the 56 px bake is half. Plans and their recipes: `STILL_SPEC.md`, part Monsters;
rules M1-M12: `RULES.md`. AWKWARD kinds are the ones a plan fits badly (the note says what to draw).

Kinds per plan: biped 19, quadruped 4, crawler 5, flyer 6, floater 4, construct 4.

| # | kind | field | behaviour | speed px/s | plan | move style | size px | note |
|---|---|---|---|---|---|---|---|---|
| 0 | plague rat | Fool's Road | swarm | 55 | quadruped | scurry | 30 |  |
| 1 | carrion crow | Fool's Road | runner | 70 | flyer | flap | 44 | a crow walks as often as it flies; drawn in flight, wings up |
| 2 | scarecrow | Fool's Road | walker | 40 | biped | shamble | 120 |  |
| 3 | bloated pilgrim | Fool's Road | burster | 30 | biped | shamble | 104 | very wide belly: keep arms clear of it |
| 4 | penitent | Fool's Road | spitter | 40 | biped | shamble | 108 |  |
| 5 | gravedigger | Fool's Road | brute | 25 | biped | stomp | 144 |  |
| 6 | hanged man | Hanged Wood | walker | 40 | floater | sway | 112 | AWKWARD: feet off the ground, rope above; swings like a pendulum, no legs |
| 7 | noose spider | Hanged Wood | leaper | 60 | crawler | skitter | 48 | eight legs: the many-legged crawler, the only one that plants feet |
| 8 | wood wolf | Hanged Wood | runner | 75 | quadruped | trot | 60 |  |
| 9 | wisp | Hanged Wood | burster | 65 | flyer | orbit | 30 |  |
| 10 | wood witch | Hanged Wood | lobber | 35 | biped | shamble | 104 |  |
| 11 | bark wight | Hanged Wood | shielded | 35 | biped | shamble | 124 | bark plates must stay on the torso, not on the limbs |
| 12 | lumberer | Hanged Wood | brute+splitter | 22 | biped | stomp | 152 | huge axe or log arm: draw empty hands, the weapon is part of the arm |
| 13 | drowned | Moon Marsh | walker | 45 | biped | shamble | 108 |  |
| 14 | leech | Moon Marsh | swarm+drainer | 60 | crawler | undulate | 34 |  |
| 15 | eel knight | Moon Marsh | runner | 80 | biped | shamble | 112 | AWKWARD: eel-bodied; drawn as an armoured humanoid with an eel head, no tail |
| 16 | marsh light | Moon Marsh | wailer | 50 | flyer | orbit | 32 |  |
| 17 | toadstone | Moon Marsh | lobber | 30 | construct | hop | 60 | AWKWARD: a toad of stone; hops as one rigid piece, legs are not animated |
| 18 | bog hag | Moon Marsh | mender | 35 | biped | shamble | 100 | hunched, long arms |
| 19 | corpse barge | Moon Marsh | brute+splitter | 20 | construct | rock | 176 | AWKWARD: a boat, 176 px wide; rocks, nothing walks |
| 20 | goat cultist | Hermit's Peaks | walker | 45 | biped | shamble | 112 | horns stay on the head |
| 21 | flagellant | Hermit's Peaks | runner | 85 | biped | shamble | 108 | the whip is part of the arm: draw it hanging, not swinging |
| 22 | rune carver | Hermit's Peaks | spitter | 40 | biped | shamble | 108 |  |
| 23 | cliff harpy | Hermit's Peaks | leaper | 70 | flyer | flap | 72 | AWKWARD: humanoid torso with wings: a flyer body with a head, no legs shown |
| 24 | bone piper | Hermit's Peaks | howler | 40 | biped | shamble | 112 | the pipe is part of the hand: draw it held down |
| 25 | frost revenant | Hermit's Peaks | wailer | 40 | biped | shamble | 120 |  |
| 26 | stone anchorite | Hermit's Peaks | brute+shielded | 20 | biped | stomp | 150 | carries a slab shield: draw it on the back (a flat slab on the torso) |
| 27 | shard | The Tower | walker | 50 | flyer | orbit | 40 | crystal shards orbit a core; no head, only a glint |
| 28 | cinderling | The Tower | swarm | 55 | crawler | squash | 36 | an ember blob; squashes and hops |
| 29 | hound | The Tower | runner | 70 | quadruped | trot | 64 |  |
| 30 | bloat | The Tower | burster | 30 | floater | sway | 84 |  |
| 31 | censor | The Tower | spitter | 40 | floater | sway | 110 | robed, the censer hangs from the hand: draw it as part of the robe |
| 32 | guard | The Tower | shielded | 35 | biped | shamble | 120 | the shield is part of the arm: draw it small and flat |
| 33 | swords | The Tower | walker | 45 | construct | hop | 76 | AWKWARD: a cluster of swords, no body, no head; one rigid piece |
| 34 | coffin | The Tower | brute+splitter | 20 | construct | hop | 112 | a coffin with a lid that opens a crack while it hops |
| 35 | ash legionary | World's Edge | shielded | 45 | biped | shamble | 124 |  |
| 36 | pit hound | World's Edge | runner | 90 | quadruped | trot | 68 |  |
| 37 | hollow angel | World's Edge | leaper | 70 | flyer | flap | 124 | AWKWARD: large, four wings or two huge ones; draw two |
| 38 | void eye | World's Edge | spitter | 40 | floater | sway | 64 | one eye, no head: the eye is the head |
| 39 | blood priest | World's Edge | howler+mender | 40 | biped | shamble | 116 | robe to the ground hides the legs: draw it knee-length |
| 40 | flesh choir | World's Edge | wailer+drainer | 35 | crawler | squash | 132 | AWKWARD: a mass of mouths; one squashing mass, no limbs |
| 41 | the unmade | World's Edge | brute+splitter | 22 | crawler | squash | 176 | AWKWARD: amorphous; one squashing mass, the biggest sprite |

Move styles: biped `shamble` (hunched walk, arms swing against the legs), `stomp` (short heavy steps, big bob);
quadruped `trot` (diagonal pairs), `scurry` (short quick steps, bigger bob); crawler `skitter` (eight legs, alternate
tetrapod), `undulate` (a wave runs down five segments), `squash` (hop with squash and stretch, area kept);
flyer `flap` (two wings, two segments each, body bobs against the stroke), `orbit` (a core that bobs, parts that circle it);
floater `sway` (bob and sway, a hem of three segments trails); construct `hop` (rigid hop with a tilt), `rock`
(rocks about its base, base kept on the ground). Every cycle is 8 frames (also 4) and loops exactly.

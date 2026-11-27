# Horde & Hearth: the rules of the fields (contract)

Curtis, 21 Nov 2026: "an mmo with a survivor feel and mob style", "hundred or thousands of players and thousands or
tens of thousands of enemies on the same screen", "horde and hearth, because we arent focused entirely on magic
anymore", "we still want dark and occult themes, diablo is a great example", "our game should eclipse diablos
numbers", "no demos ... edit the plan for a full build". The build plan is
https://claude.ai/artifact/9vWAXVd1ktk8Lo1cneN8d1; `build_plan.md` says who builds what.

This file is the contract for everything that happens in a field or a vault: the whole game's, not a sample's.
Every number is a starting value in a table (`realm/core/src/tables.rs` or a file beside it), never a literal in
logic; a job may change a number if it reports the old value, the new one and the measurement that moved it. Words
in CAPITALS are on-screen names. The town, the bank, trade, the market, guilds and houses are in `economy.md` and
`social.md` (written with their jobs).

## 0. Laws

1. **The horde comes first.** 1,000 heroes and 20,000 monsters in one field stay inside the tick budget (section
   13), and 10,000 monsters on one screen is the drawing target. A rule that cannot be afforded at that size is
   changed, not the size.
2. **One simulation.** `realm/core` is whole numbers only: no clock, no floats, no containers with random order, no
   thread-dependent result. The server, the client, the bots and the tests run the same code; a field's hash after
   tick N is the same everywhere.
3. **What is public is simulated; what is secret is not.** Movement, fights, health, field levels, card draws,
   coin, tides and bosses are in the simulation, so every client computes them. Item drops are rolled by the
   server from a stream no client holds and are sent only to their owner.
4. **Nothing kept is decided by a client.** The saved hero, the bag and the bank change only on the server, from
   simulation events and its own rolls, each change written to the ledger.
5. The world never pauses for anyone: no level-up, card draw, bag or chat stops the field.
6. Content is data. A field, a monster, a boss, a class, a skill, a card and an item are table rows over a small
   set of behaviours the core implements once. Adding a seventh field must need no new logic.

## 1. Time, space, input

- 20 ticks a second. Positions are 1/256 px. A field is 16,384 px square, 512 x 512 cells of 32 px; a vault is
  2,048 px square. The screen shows 480 x 270.
- Input is two bytes a tick per hero. Byte 0: direction 0..8 in bits 0..3, bit 4 skill 1, bit 5 skill 2, bit 6 the
  job's ultimate, bit 7 interact (hold). Byte 1: card pick 0 (none) or 1..4 in bits 0..2, bit 3 potion slot 1,
  bit 4 potion slot 2, bit 5 potion slot 3; bits 6 and 7 zero.
- The simulation returns a list of **events** each tick (section 12). Events are output, not state.

## 2. The saved hero and the field hero

The server keeps a hero's sheet and turns it into the numbers the field needs when she enters (`Sheet`, passed to
`Field::join`; built by the gateway's `sheet_of` for every field, vault, duel and home, its gear the loot crate's
`gear_stats`: item lines raised 3% a smith step, plus the runes and monster cards in their sockets): class, job, race, class level, the six stats after race, points, gear, cards and runes, the deck
(card ids), the belt (three potion ids with counts), the look. The field keeps what lasts one outing: health, field
level and XP, drawn cards, the haul's coin, cooldowns, effects. `join` also takes that outing state, so a hero moved
between two copies of a field (section 11) arrives as she left.

**Six stats.** One point is: MIGHT +2% damage; FOCUS +1% attack speed; SWIFT +1% move speed (cap +40%); VIGOR +2%
health; WARD 1% less damage taken (cap 60%); FORTUNE +3% coin and +1 luck (section 9).

**Races.** HUMAN +1 to all six, +5% class XP. ELF SWIFT +4, FOCUS +3. DWARF VIGOR +4, WARD +3, pushed half as far.
ORC MIGHT +5, VIGOR +2, +10% damage under 30% health.

**Class level** (kept for good): 1 to 60. Class XP is the field XP a hero earns, counted by the server as it is
earned and never lost. XP to the next level is a table; targets to tune with bots: level 10 after about 25
minutes of field play, 20 after 4 hours, 40 after 25 hours, 60 after 80 hours. Each level pays one stat point.

**Field level** (one outing): starts at 1 on entering a field or a vault and is gone on leaving it. XP to the next:
`50 x level`. Each field level adds 4% damage (cap +160% at 41) and queues one **draw** (section 5). XP for a kill
is shared in full by every living hero within 200 px who is **active** (dealt damage, healed or was hit in the last
10 seconds). A monster more than 10 levels below a hero's class level pays her no class XP.

## 3. Classes, skills and jobs

Everyone starts a NOVICE. At class level 10 the trainer in town offers the five classes after a short trial (a
solo vault of three minutes). Skill 1 comes with the class, skill 2 at 25. At 40 she chooses one of the class's two
**jobs**, which changes a passive and gives an ultimate. A skill's rank is `1 + (class level - its level) / 10`
(at most 5); each rank adds 15% to its damage, healing or length.

Attack shapes the core implements once: `arc` (a cone toward the nearest monster), `ring` (a circle on the hero),
`bolt` (flies to the nearest monster in reach, may pierce or burst, stops at walls), `drop` (a circle at a point in
reach, after a delay), `zone` (a circle on the ground that lasts and acts every 10 ticks; one pool of 2,048),
`dash` (the hero moves along a line, unhurt). Hero effects are timed rows: damage, attack speed, move speed and
damage taken in percent, unhurt, cannot fall. Monster effects are three small timers: stunned, slowed, cursed.

| Class | Role | Health (level 1, +per level) | Weapon | Threat | Passive |
|---|---|---|---|---|---|
| NOVICE | none | 200, +20 | DIRK: arc 90 deg, 48 px, 14 damage, 12 ticks | 1.0 | none |
| KNIGHT | tank | 360, +36 | CLEAVE: arc 110 deg, 72 px, 30 damage, 10 ticks, pushes back 12 px | 2.0 | pushed half as far |
| MAGE | damage | 180, +18 | FIREBALL: bolt, reach 320 px, bursts 60 px for 40 damage, 16 ticks | 0.8 | draws show four cards |
| ARCHER | ranged | 200, +20 | LONGBOW: bolt, reach 400 px, 40 damage, pierces 4, 10 ticks | 0.8 | walks 8% faster |
| PRIEST | healer | 220, +22 | HOLY LIGHT: ring 96 px, 15 damage, 12 ticks; each attack also heals the most hurt ally within 160 px for 3% of her health | 0.7 | raises in half the time |
| PALADIN | tank and support | 300, +30 | SMITE: drop, reach 200 px, 60 px circle, 36 damage, 12 ticks, lands after 6 ticks | 1.6 | allies within 100 px take 8% less |

| Class | Skill 1 (cooldown) | Skill 2, level 25 (cooldown) |
|---|---|---|
| NOVICE | SECOND WIND: heals 30% (30 s) | none |
| KNIGHT | PROVOKE: for 5 s monsters within 200 px come for him and he takes half damage (20 s) | CHARGE: dash 200 px, 80 damage and 1 s stun along it (14 s) |
| MAGE | NOVA: ring 200 px, 160 damage (25 s) | METEOR: drop on the thickest cell within 400 px, 140 px, 400 damage, lands after 30 ticks (30 s) |
| ARCHER | VOLLEY: 12 arrows in a 120 degree fan, each as LONGBOW (15 s) | TUMBLE: dash 120 px along her movement, leaves a zone 60 px that slows 50% for 4 s (10 s) |
| PRIEST | SANCTUARY: allies within 200 px heal 40%, the downed among them rise (40 s) | CONSECRATE: zone 140 px for 8 s, allies in it regain 4% a second, monsters take 20 a second (25 s) |
| PALADIN | AEGIS: allies within 120 px take no damage for 3 s (45 s) | HAMMERFALL: ring 100 px, 120 damage, 1.5 s stun (18 s) |

| Job (class) | Role | Passive | Ultimate (cooldown) |
|---|---|---|---|
| WARDEN (knight) | tank | threat 2.6; PROVOKE also pulls monsters 40 px inward | RAMPART: zone 160 px for 8 s, allies in it take 40% less (90 s) |
| BERSERKER (knight) | damage | +1% damage per 2% health missing; threat 1.4 | BLOOD RAGE: 10 s of +60% attack speed, each kill heals 1% (90 s) |
| ARCHMAGE (mage) | damage | FIREBALL bursts a second time for half | CATACLYSM: five METEORS over 5 s on the five thickest cells within 500 px (120 s) |
| HEXER (mage) | support | cursed monsters take 15% more from everyone | PLAGUE: curses monsters within 300 px for 10 s; a cursed monster that dies curses those within 60 px (90 s) |
| RANGER (archer) | ranged | LONGBOW pierces 8; +10% move speed | HAIL: zone 300 px at the thickest cell within 400 px, 8 s, 60 a second (100 s) |
| SHARPSHOOTER (archer) | damage | reach +25%; +30% damage to ELITES, CHAMPIONS and bosses | DEADEYE: 8 s in which arrows pierce everything and deal double (90 s) |
| ORACLE (priest) | healer | her heals also shield for 2 s (unhurt) the ally under 30% health | BENEDICTION: allies within 300 px deal 25% more and attack 25% faster for 10 s (120 s) |
| INQUISITOR (priest) | damage | HOLY LIGHT damage x2, its healing halved | PYRE: zone 180 px for 10 s, 90 a second (90 s) |
| TEMPLAR (paladin) | tank | his aura's 8% becomes 14% and reaches 140 px | MARTYR: for 8 s allies within 200 px cannot fall below 1 health (120 s) |
| CRUSADER (paladin) | damage | +2% damage per ally within 100 px, at most 20% | CRUSADE: 10 s in which SMITE strikes three targets and he moves 30% faster (90 s) |

Damage dealt = weapon damage x (100 + 2 x MIGHT)% x field level bonus x cards x effects. Group effects (auras,
BENEDICTION, THE SUN) do not stack with themselves: the strongest counts.

**Threat.** Monsters follow one flow field toward the heroes (as in the crowd test). A hero's cell is seeded with a
head start of `(2.6 - threat) x 2` cells, so with a KNIGHT and a MAGE equally near, the horde bends to the knight.
Inside two cells a monster walks straight at the hero with the highest `threat / distance`.

## 4. Monsters

A monster is a row: kind, field, behaviour, and four numbers at level 1. Its `level` comes from the ring it is
born in (section 6): health x (100 + 18 x (level - 1))%; damage, XP and coin x (100 + 12 x (level - 1))%. The
tuning gate that keeps 60 levels honest: a hero of the monster's level, in gear of that level, kills a walker in
0.6 to 1.2 seconds, alone.

**Behaviours** (each implemented once):

| Behaviour | Rule |
|---|---|
| walker | follows the flow field; hits on contact |
| swarm | a walker born in clutches of 8 |
| runner | sprints at double speed for 1 s when within 160 px, then rests 2 s |
| brute | cannot be pushed, stunned or slowed |
| shielded | takes 30% less from the front |
| burster | on death bursts 40 px for double its damage, after 10 ticks |
| splitter | on death opens into 4 of a smaller kind (named in its row) |
| spitter | stops at 150 px and throws a slow bolt (90 px/s, lives 3 s) every 2 s |
| lobber | stops at 250 px and lobs a 50 px circle that lands after 1 s, every 3 s |
| leaper | when within 200 px, jumps over the front rank onto the hero with the lowest threat there, every 5 s |
| howler | monsters within 100 px move 20% faster (does not stack) |
| mender | every 2 s heals monsters within 100 px for 4% (does not stack; never bosses) |
| wailer | heroes within 80 px move 20% slower (does not stack) |
| drainer | heals itself for the damage it deals |

- Contact: a monster within 20 px of its hero hits every 10 ticks. Monster bolts and lobbed circles live in one
  pool of 4,096; when it is full a spitter or lobber walks instead.
- ELITE, 1 in 50: health x4, XP and coin x3, drawn larger. CHAMPION, 1 in 2,000 (heart ring 1 in 800): health x25,
  damage x2, XP x20, always an item roll for every credited hero, announced to heroes within 600 px.
- Density. A field's target count = `min(cap, 400 + sum over heroes of ring weight)`, ring weight 12 at the edge,
  20 in the middle, 32 at the heart; cap 20,000 (50,000 proven). Monsters are born 400 to 700 px from a hero
  (250 to 450 in the dark), never on a wall or in a QUIET zone (6.1), and one that has had no hero within 64 cells
  is recycled.
- Routing. Monsters walk the flow field, which treats walls and quiet zones as closed and never cuts a corner. A
  monster steps only to a neighbouring cell that is no farther along the flow (a crowd in a corridor waits its turn
  instead of swaying back), it goes straight at a hero within two cells only when no wall stands on the line, and
  its centre keeps 8 px (its body) from every closed cell beside it, so a horde streams through a passage one cell
  wide and round its corners without rubbing into the walls. A monster that finds itself in a quiet zone walks
  straight out from its centre (at least 6 px a tick); hero pushes and pulls and splitters' children never put one
  in.

**The kinds** (speed px/s, health, damage, XP at level 1). THE TOWER's eight are drawn with the pictures Curtis has
made; every other kind has a flat stand-in until its picture arrives.

| Field | Kind | Behaviour | Speed | Health | Damage | XP |
|---|---|---|---|---|---|---|
| Fool's Road | plague rat | swarm | 55 | 18 | 3 | 1 |
| Fool's Road | carrion crow | runner | 70 | 22 | 4 | 1 |
| Fool's Road | scarecrow | walker | 40 | 45 | 6 | 2 |
| Fool's Road | bloated pilgrim | burster | 30 | 60 | 6 | 3 |
| Fool's Road | penitent | spitter | 40 | 35 | 5 | 2 |
| Fool's Road | gravedigger | brute | 25 | 140 | 10 | 5 |
| Hanged Wood | hanged man | walker | 40 | 50 | 7 | 2 |
| Hanged Wood | noose spider | leaper | 60 | 30 | 6 | 2 |
| Hanged Wood | wood wolf | runner, clutches of 4 | 75 | 30 | 6 | 2 |
| Hanged Wood | wisp | burster | 65 | 15 | 8 | 1 |
| Hanged Wood | wood witch | lobber | 35 | 40 | 9 | 3 |
| Hanged Wood | bark wight | shielded | 35 | 90 | 8 | 4 |
| Hanged Wood | lumberer | brute, splitter into hanged men | 22 | 180 | 12 | 6 |
| Moon Marsh | drowned | walker | 45 | 55 | 7 | 2 |
| Moon Marsh | leech | swarm, drainer | 60 | 16 | 3 | 1 |
| Moon Marsh | eel knight | runner | 80 | 45 | 8 | 3 |
| Moon Marsh | marsh light | wailer | 50 | 30 | 4 | 2 |
| Moon Marsh | toadstone | lobber | 30 | 60 | 10 | 3 |
| Moon Marsh | bog hag | mender | 35 | 70 | 6 | 4 |
| Moon Marsh | corpse barge | brute, splitter into drowned | 20 | 220 | 12 | 7 |
| Hermit's Peaks | goat cultist | walker | 45 | 55 | 8 | 2 |
| Hermit's Peaks | flagellant | runner | 85 | 25 | 11 | 2 |
| Hermit's Peaks | rune carver | spitter | 40 | 45 | 8 | 3 |
| Hermit's Peaks | cliff harpy | leaper | 70 | 35 | 8 | 3 |
| Hermit's Peaks | bone piper | howler | 40 | 60 | 5 | 4 |
| Hermit's Peaks | frost revenant | wailer | 40 | 80 | 8 | 4 |
| Hermit's Peaks | stone anchorite | brute, shielded | 20 | 240 | 13 | 7 |
| The Tower | shard | walker | 50 | 25 | 4 | 1 |
| The Tower | cinderling | swarm | 55 | 20 | 4 | 1 |
| The Tower | hound | runner | 70 | 30 | 6 | 2 |
| The Tower | bloat | burster | 30 | 60 | 6 | 3 |
| The Tower | censor | spitter | 40 | 40 | 5 | 2 |
| The Tower | guard | shielded | 35 | 80 | 8 | 4 |
| The Tower | swords | walker, hits twice as often | 45 | 50 | 7 | 3 |
| The Tower | coffin | brute, splitter into cinderlings | 20 | 120 | 10 | 5 |
| World's Edge | ash legionary | shielded | 45 | 90 | 9 | 4 |
| World's Edge | pit hound | runner, clutches of 4 | 90 | 35 | 8 | 2 |
| World's Edge | hollow angel | leaper | 70 | 50 | 10 | 4 |
| World's Edge | void eye | spitter | 40 | 45 | 10 | 3 |
| World's Edge | blood priest | howler, mender | 40 | 70 | 6 | 5 |
| World's Edge | flesh choir | wailer, drainer | 35 | 110 | 8 | 5 |
| World's Edge | the unmade | brute, splitter into ash legionaries | 22 | 260 | 14 | 8 |

## 5. Field levels and the deck

A draw offers three cards (the MAGE four) from the hero's deck, never one already at five copies, chosen with the
field's seed, the hero's id and her draw count. Draws queue (at most 9); the hero picks with byte 1 while she
fights; an unpicked draw is never lost and never picked for her. A deck holds 20 cards chosen in town from the
cards she owns. A NOVICE owns the first 12; each even class level to 24 adds one; later cards are found as pages
(section 9). Each copy adds the card's effect again (5 copies at most).

| # | Card | Effect per copy |
|---|---|---|
| 1 | STRENGTH | +10% damage |
| 2 | THE CHARIOT | +6% move speed |
| 3 | THE MAGICIAN | +8% attack speed |
| 4 | THE EMPRESS | +10% health, and heals that much at once |
| 5 | TEMPERANCE | regains 0.5% health a second |
| 6 | THE WORLD | +12% attack size |
| 7 | THE STAR | +10% weapon reach |
| 8 | THE HIGH PRIESTESS | skill cooldowns 8% shorter |
| 9 | WHEEL OF FORTUNE | +10% coin |
| 10 | THE HERMIT | +8% field XP |
| 11 | THE HIEROPHANT | takes 5% less damage |
| 12 | JUSTICE | returns 20% of contact damage to the attacker |
| 13 | THE TOWER | every 5th attack hits twice |
| 14 | DEATH | +25% damage to monsters under 30% health |
| 15 | THE DEVIL | +18% damage, takes 6% more |
| 16 | THE MOON | 5% of hits strike for double |
| 17 | THE SUN | allies within 100 px deal 3% more |
| 18 | THE LOVERS | heals 1% of damage dealt, at most 2% of health a second |
| 19 | THE EMPEROR | +15% damage to ELITES, CHAMPIONS and bosses |
| 20 | THE HANGED MAN | raises allies 25% faster; rises with 15% more health |
| 21 | JUDGEMENT | +12% damage during a tide |
| 22 | THE FOOL | +1 pierce or +1 target (LONGBOW, FIREBALL, SMITE); other weapons +8% damage |
| 23 | NINE OF SWORDS | attacks push 6 px farther |
| 24 | THREE OF CUPS | potions restore 20% more and hold one more charge this outing |
| 25 | ACE OF WANDS | the ultimate's cooldown 10% shorter (no job: +6% damage) |
| 26 | FIVE OF PENTACLES | +20% damage while no ally is within 150 px |
| 27 | SIX OF CUPS | +4% damage per ally within 150 px, at most 20% |
| 28 | TEN OF SWORDS | on being downed, bursts 160 px for 300 damage |
| 29 | QUEEN OF PENTACLES | the haul loses a tenth less on a fall |
| 30 | KNIGHT OF WANDS | +15% move speed for 3 s after a kill |

Random effects (THE MOON) use the field's seeded stream, so every client agrees.

## 6. The six fields

Each field is one map of 512 x 512 cells with three rings by distance from its heart (the centre): EDGE beyond
6,000 px, MIDDLE 2,500 to 6,000 px, HEART inside 2,500 px. A field's level range is spread evenly from its rim to
its centre. The gate from town is at the south edge. Seven WAYSTONES: three in the edge ring, three in the middle,
one on the heart's rim. Six WAR ALTAR sites in the middle ring. Sites are a table per field.

| Field | Levels | Ground | Terrain rule | Boss |
|---|---|---|---|---|
| THE FOOL'S ROAD | 1 to 10 | blighted farms, a plague road, a burnt chapel | open; hedges and ruins; heroes walk 10% faster on the road | THE HARVESTER |
| THE HANGED WOOD | 10 to 20 | black forest, gibbets | tree walls with paths 6 to 10 cells wide that funnel the horde | THE HANGING TREE |
| THE MOON MARSH | 20 to 30 | fog, drowned villages | mire slows heroes 30%, not monsters; dark: sight and births closer | MOTHER OF LEECHES |
| THE HERMIT'S PEAKS | 30 to 40 | snow, cliff monasteries | ridges with passes 6 cells wide; spitters hold the high side | THE GOAT PROPHET |
| THE TOWER | 40 to 50 | ruined halls, libraries | rooms and corridors, doors 6 cells wide | THE CHANDELIER and THE GHOSTWRITER, in turn |
| THE WORLD'S EDGE | 50 to 60 | ash, broken ground over a void | islands joined by bridges 8 cells wide; all terrain rules at once | THE UNMADE KING |

**Terrain** is one byte a cell: WALL (nobody passes, bolts stop), MIRE, ROAD, DARK, QUIET (6.1). Deep WATER is a
wall with the mire bit (it blocks like rock and is drawn as water). A field's map is made from its seed by a
generator per terrain rule, then checked: every site and quiet zone reachable from the gate, no passage under 6
cells, and ground nobody can reach from the gate is made wall, so every walkable cell is reachable. Every generator
lays blocking ground as well as its own rule, keeping 14 cells from the sites, in the field's own character: THE
FOOL'S ROAD field walls with gates between the farms, rock outcrops, copses and ponds (no mire); THE HANGED WOOD
thickets, black pools and fallen trunks that pinch its paths; THE MOON MARSH deep pools ringed with mire, with
causeways between, and reed thickets; THE HERMIT'S PEAKS crags and spurs off the ridges that make corridors; THE
TOWER pillars and rows of library shelves in its rooms; THE WORLD'S EDGE rock spires on its islands. Every wall run
has gaps of 6 to 9 cells: the tight passages between open ground. The flow field treats walls and quiet zones as
closed. The map is part of the field's state hash.

### 6.1 Quiet zones and shrines

Every field has QUIET zones, placed by its map generator from the seed (so every client agrees) and drawn on the map:
- the ENTRANCE, 10 cells round a point 6 cells north of the gate (the gate is inside it);
- 3 to 5 INTERMISSIONS, 8 cells in radius, spread evenly in depth from 6,400 px to 2,900 px from the heart; the
  first within 30 degrees of the line from the gate to the heart, each next within 30 degrees of the one before and
  within 70 of that line, at least 30 cells from the sites and from each other: a winding way from the gate inward;
- a WARD of 4 cells round every waystone, so banking is done on quiet ground.
Each zone is cleared of walls 6 cells beyond its edge, so monsters walk round it. Inside a zone nothing is born, no
monster walks in (its edge is a wall to monsters and to the flow field; a hero inside is not chased), no monster
strikes a hero inside it (contact, bolts, lobbed and bursting circles), and a monster found inside walks out.
The entrance and each intermission have a SHRINE at their centre: a hero up who comes within 28 px of one is given
one card draw, once a shrine an outing (the touched shrines go with her to another copy of the field). The draw goes
through the same queue as a level's draw (`grant_draw` in the core). Waystone wards have no shrine.

**Level ceiling.** In a field, a hero counts as at most its top level + 2: class level for stat points and skill
ranks, and gear above the ceiling scales down likewise, so a veteran helps without erasing the field.

## 7. The haul, falling and rising

- **The haul** is what a hero carries and has not banked: coin (in the simulation) and common and uncommon items
  and materials (on the server). RARE and better items, cards, pages, keys and class XP are never part of the
  haul: they are kept the moment they drop.
- **Banking.** Standing within 48 px of a waystone and holding interact for 3 seconds, unhurt, banks the whole
  haul (event BANK) and marks that waystone as hers. A second hold of 3 seconds returns her to town. Walking out of
  the gate also banks.
- **Downed.** At 0 health a hero is DOWNED for 15 seconds: she cannot act and monsters ignore her. An ally standing
  within 40 px for 2 seconds (a PRIEST 1 second), or SANCTUARY, raises her with 30% health and 2 seconds unhurt.
- **Fallen.** Not raised in time, she loses half her haul's coin (rounded down) and half her haul's items (the
  server picks which), and wakes at her waystone, or the gate, with full health and her field level.
- **Potions** (belt of three slots, filled from the bag when entering; charges leave the bag as they are drunk):

| Potion | Effect | Charges carried | Rest between uses |
|---|---|---|---|
| HEALING DRAUGHT | restores 35% | 3 | 10 s |
| VEIL OF ASH | unhurt for 3 s | 2 | 30 s |
| WHETSTONE OIL | +20% damage for 30 s | 2 | 30 s |
| SCHOLAR'S INK | +50% field XP for 2 minutes | 1 | none |
| GAMBLER'S COIN | +20 luck for 2 minutes | 1 | none |
| PHOENIX ASH | not drunk: when she would be FALLEN she rises instead with 30% health | 1 | once an outing |

## 8. Tides, bosses and the world boss

- **The clock.** A tide begins every 30 minutes of a field's time and lasts 5. Everyone in the field and in town
  sees every field's countdown.
- **During a tide** the target count doubles (to the cap), monsters move 20% faster, and three WAR ALTARS light
  (three of the six sites, by the field's seed). An altar is HELD by hero-seconds within 150 px:
  `60 x max(1, heroes in the field / 20)` of them; monsters within 60 px strike it (health `8,000 x` the same
  factor x the field's level scale). The tide is WON when two altars are held before it ends and LOST otherwise.
- **Won:** every hero whose tide contribution passes the floor gets a TIDE CACHE (three item rolls starting at
  UNCOMMON, coin). **Lost:** the horde stays quick for 2 minutes.
- **The field boss** rises at the heart 30 seconds after every fourth tide (every two hours), announced in town
  ten minutes before. If that tide was won it rises with 20% less health; if lost it deals 20% more. Health
  `(40,000 + 6,000 x heroes within the heart when it rises, at most 600 counted) x` the field's level scale, fixed
  at that moment. After 8 minutes it leaves. Killed: every hero past the floor gets a BOSS CHEST (two item rolls
  starting at RARE, the card roll, a trophy roll, coin).
- **Boss attacks** are rows over shapes the core implements once, each drawn on the ground before it lands:
  `slam` (ring on the boss), `candles` (circles on random heroes in reach), `sweep` (a beam that turns), `lanes`
  (the boss rides a line across its ground), `call` (a clutch of a named kind), `mire` (zones that slow), `pull`
  (heroes within reach dragged inward), `wall` (a ring of fire that closes).

| Boss | Field | Moves | Attacks |
|---|---|---|---|
| THE HARVESTER | Fool's Road | walks slowly | sweep 220 px; call 30 carrion crows; slam |
| THE HANGING TREE | Hanged Wood | rooted | pull 300 px then slam; candles (roots); call 20 hanged men |
| MOTHER OF LEECHES | Moon Marsh | walks slowly | mire; call 60 leeches; slam; she is a drainer |
| THE GOAT PROPHET | Hermit's Peaks | rooted | two sweeps turning opposite ways; candles (falling rock); call 12 goat cultists and a bone piper |
| THE CHANDELIER | The Tower | rooted | slam 180 px; candles 12 x 60 px; call 40 cinderlings |
| THE GHOSTWRITER | The Tower | lanes | lanes; candles (ink); wall |
| THE UNMADE KING | World's Edge | walks, lanes at half health | every attack above, two at a time under half health |
| DEATH, THE PALE RIDER (world boss) | any | lanes across the whole middle ring | lanes; call a tide's worth of the field's kinds; wall |

- **The world boss** rides every six hours in one field, chosen in turn and announced to the whole realm thirty
  minutes before. Its level is the field's top level; health ten times a field boss's; it stays 15 minutes. Its
  chest holds a RELIC roll for the hundred highest contributions and an EPIC roll for everyone past the floor.
- **Contribution** = damage dealt + healing done + half the damage taken, counted per hero per tide and per boss.
  The floor is 0.2% of a boss's health (for a tide: 40 x the heroes-in-field factor). Standing still earns nothing.

## 9. Loot (server only)

- **Credit.** For every kill the simulation names the credited heroes (the same set that shares the XP). The
  server gives each of them her own roll; nobody sees or takes another's drop.
- **Chance of an item roll** per credited kill: monster 1 in 400, ELITE 1 in 20, CHAMPION and bosses always; each
  point of luck adds 1%, relative. A hero gets at most 12 non-boss item rolls a minute.
- **Rarity** of a roll: COMMON 60%, UNCOMMON 30%, RARE 8.5%, EPIC 1.4%, RELIC 0.1%; a CHAMPION starts at UNCOMMON,
  a boss at RARE.
- **Gear**: six slots (WEAPON, HEAD, BODY, HANDS, FEET, CHARM). An item is a base, an item level (the monster's),
  a rarity and 1 to 4 lines (COMMON 1 ... EPIC and RELIC 4) drawn from the six stats, each `1 + item level / 4`
  points x (rarity step 100%, 120%, 150%, 190%, 240%); RARE and better have one socket, RELIC two. A hero wears
  gear up to her class level. The smith raises an item from +1 to +10 for EMBERS and coin, +3% to its lines a
  step; a failed step above +5 costs the materials, never the item.
- **Monster cards**: one per kind (42) and one per boss, socketed in gear, each a small rule of its own (a table
  in `economy.md`). A card drops 1 in 20,000 kills of its kind, 1 in 200 from a CHAMPION and one roll in 100 from
  its boss: about one card in a hundred outings, as Curtis asked.
- **Runes**: six kinds, one per stat, grades I to III (2, 4 and 7 points); a socket holds a card or a rune; three
  of a kind and grade fuse into the next. Dropped by ELITES 1 in 30 (grade I) and bosses (grade II).
- **Pages**: cards 13 to 30 of the deck are found as pages, 1 in 300 from an ELITE, one from each boss's first kill.
- **Materials**: EMBERS from every field (the smith), a field's own material from its ELITES (furniture and
  trophies for houses), VAULT KEYS 1 in 150 from an ELITE of a field whose top level is 20 or more.
- **Coin**: a kill pays its XP in coin to each credited hero, x FORTUNE.
- Every item has an id minted by the server; minting, moving, selling and destroying are ledger rows.

## 10. Vaults

A vault is the Four of Wands run for a party of up to eight, on the same core with a `Vault` row instead of a
field's: an arena of 2,048 px, 15 minutes, a timeline of what is born each minute, an act boss at minutes 5 and 10
and THE ARCHLICH at 15. Entering costs the party leader a VAULT KEY. Five vaults by level (20, 30, 40, 50, 60), each
with SEALS I to VIII: every seal adds 25% monster health and damage and one more reward roll. Heroes enter at
field level 1 with their decks. There are no waystones: the downed are raised or the party fails when all eight are
down. A win pays each hero a VAULT CHEST (rolls starting at RARE, the Archlich's card roll, a trophy roll); a loss
pays coin for the minutes survived. The class trial is a vault row for one hero.

## 11. Copies of a field

A field copy holds at most 1,000 heroes. The server opens a second copy when one passes 800, sends new arrivals
and whole parties to the emptier one, and when two copies of a field together hold under 500 it closes one at the
end of its tide: its heroes are moved, with their outing state, to the same ring of the other. Tide and boss clocks
are per field, not per copy, so every copy surges together.

## 12. Events (output of a tick, in order)

`LEVEL(hero, field level)`, `DRAW(hero, cards)`, `PICK(hero, card, copies)`, `SKILL(hero, which)`, `POTION(hero,
slot, left)`, `DOWN(hero)`, `RAISE(hero, by)`, `FALLEN(hero, coin lost)`, `BANK(hero, coin, waystone)`,
`LEAVE(hero)`, `KILL(kind, level, flags, x, y, credited heroes)`, `XP(hero, amount)` summed per tick, `TIDE(state)`,
`ALTAR(index, state)`, `BOSS(which, state, health)`, `REWARD(kind, heroes past the floor, their contributions)`,
`VAULT(state)`. The server turns `KILL`, `BANK`, `FALLEN`, `XP`, `POTION` and `REWARD` into saved changes; clients
turn events into sound, text and effects.

## 13. Gates

- `realm/check.sh` green; a field's hash equal on 1, 2, 3 and 4 threads and on a lockstep follower for 2,000 ticks
  of 1,000 bot heroes of mixed classes and jobs using skills, picks, potions and waystones, through a tide and a
  boss, in each of the six fields.
- State save and load mid-tide and mid-boss gives the same hash 200 ticks later.
- Budget on the 4-core box, 4 threads, 1,000 heroes and 20,000 monsters, rallied (`--rally=0.3`): mean tick at most
  12 ms, p99 at most 25 ms (the bare crowd test was 4.4 and 8.2); in a tide at the cap: mean at most 20 ms. Worst
  field (walls, spitters, zones) reported separately.
- Every table row has a unit test of its rule; every behaviour, attack shape and boss attack has a test; every
  event has a test that it fires once and only once.
- Bots: each class alone at the edge of The Fool's Road at class level 1 survives 10 minutes in 8 of 10 seeds; a
  party of knight, priest, archer, mage at a field's bottom level, in gear of that level, holds its middle ring in
  8 of 10, for all six fields; every job within 15% of its class's other job in a crowd of 100.

## 14. Players against players (built after the rest works)

Curtis, 21 Nov: "yes to pvp, but it is a second thought ... special servers, events, or ... a pvp mode that you
switch on for extra risks and rewards but cant switch off if youve attacked someone".

- **THE BLOOD MARK.** A hero of class level 20 or more takes the mark by holding interact at a waystone for 5
  seconds; it is part of her outing state (`marked`) and shows on her to everyone. Marked heroes' attacks and
  skills also strike other marked heroes, for 40% of their damage to monsters; group effects, heals and raises
  between marked and unmarked heroes work as usual, except that an unmarked hero cannot heal, shield or raise a
  marked hero who struck a hero in the last 60 seconds.
- **Reward:** +25% coin and +15 luck while marked. **Risk:** a marked hero downed by a hero's blow and not raised
  is FALLEN as usual, and what she loses from her haul goes to the hero who downed her.
- **No way back at once:** after striking a hero she cannot put the mark down (interact at a waystone) until ten
  minutes have passed without striking one. Leaving the field does not clear the wait.
- **Safe ground:** within 300 px of a waystone or the gate, and in town, no hero can be struck by a hero.
- The level ceiling of section 6 applies, so a field's fights are near its level.
- **Events:** during a tide two guilds that declared for a field fight for its altars (held time counts per
  guild; their members are marked against each other only, for the tide); duels in the town's training yard.
- **Marked realms:** a realm flag marks everyone past level 20 for good. Same rules.
- State from the first day: `marked` and the last-struck tick are in the outing state and the hash, so adding the
  fights later changes no saved format.

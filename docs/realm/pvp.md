# Players against players (job R3, rules section 14)

What R3 built: the BLOOD MARK, guild altar wars, duels in the training yard and marked realms. It covers every field,
class, skill and shape. Code: `realm/core/src/pvp.rs` holds the rules and state, and `attack.rs`, `combat.rs`, `act.rs`,
`mods.rs`, `tide.rs`, `state.rs`, `terrain.rs`, `events.rs` and `bots.rs` call into it. On the gateway the code is
`realm/gateway/src/social/pvp.rs` with its wire in `social/wire.rs`. Tests: `realm/core/tests/pvp.rs` (20) and
`realm/gateway/tests/pvp.rs` (4).

## Who may strike whom

All of it is one relation, `Field::hostile(a, b)`, plus where the two stand (`Field::foes(a, b)`):

- **Blood mark.** Both heroes carry the BLOOD MARK (`Hero::marked`).
- **Altar war.** Both are members of the two guilds of a war that is on, one on each side. A war is on while its
  tide runs, and members are marked against each other only. A member who also carries the blood mark is open to
  other marked heroes too, since the two relations add up.
- **Duel.** The two heroes of a running duel, in a yard. In a yard nothing else counts, not even the blood mark.
- **Never on safe ground.** Nobody strikes or is struck within **300 px** of a waystone or the gate. Both the striker
  and the target are checked.
  - Why both: a target-only rule would let a marked hero shoot from the waystone at heroes just outside, with no
    answer possible.
  - A yard has no safe ground.
  - A vault is safe everywhere: it is a party's run against a timeline.

A hero who can strike anyone is *flagged* (`Field::flagged`). Only flagged heroes off safe ground gather blows on
heroes, so a field of unmarked heroes does no extra work.

## The blow

- **40% of the blow on a monster** (`PVP_DAMAGE_PCT`), taken before the monster-only multipliers (elite, curse,
  shield facing). The target's own reductions then apply as for any hit: WARD, cards, unhurt, MARTYR, cannot-fall.
- THE MOON's crit rolls on its own stream (`STREAM_MOON_PVP`). Monster hits roll exactly as before, so a marked
  hero's kills are not changed by the heroes around her.
- **Shapes that strike heroes:**
  - weapon arcs, rings and bolts (pierce counts heroes on their own), bursts and second bursts;
  - drops: the foes in the circle when it lands, with the thrower's relation checked then;
  - hero zones: each act;
  - skills: Ring, Thick (drops), Volley, Dash and Zone.
- **Aim.** A weapon or skill aims at a foe instead of the nearest monster when the foe is nearer, or when there is no
  monster in reach.
- **Monsters only, by choice:** curses, PROVOKE's pull, stuns, slows and pushes on heroes, JUSTICE's reflection, and
  the death burst card. Stuns and pushes on heroes would be a control game the rules do not ask for.
- Blows are gathered in parallel with the monster hits and applied in hero order, right after the monster hits.
  Each blow is checked again when applied, because an earlier blow may already have downed the target. The result is
  the same on any thread count.
- Hero-on-hero hit tests use the hero grid of 64 px cells (`foes_in_circle`, `foes_on_line`, `nearest_foe`), the same
  grid the raise and altar checks use.
- A hero's damage to heroes does not count as contribution, nor for THE LOVERS. Taking a blow counts half as
  "drawn", like any hit (`hurt_hero`). See open question 4.

## The BLOOD MARK

| Number | Value | Why |
|---|---|---|
| Class level to take it | 20 (her own level, not the counted one) | The contract. |
| The rite | hold interact with `IN_MARK` (input byte 1, bit 6, `0x4000`) for **5 s** within 48 px of a waystone | A plain hold banks at 3 s and leaves at 3 s more, so the rite needs its own bit. Banking never happens during the rite, and switching between the two starts the hold over. A hit pauses the hold, as it does for banking. |
| Reward | +25% coin from kills (`coin_pct`), +15 luck | The contract. Duels and wars give no reward, because only the mark does. |
| Helper ban | 60 s after her last strike on a hero | The contract. |
| No way back | 10 min (12,000 ticks) after her last strike | The contract. The rite answers `MARK_WAIT` until then. |
| Safe ground | 300 px | The contract. |

- **Events.** `Mark{hero, state}` with the states TAKEN, PUT_DOWN, LOW_LEVEL, WAIT, FOR_GOOD (a marked realm) and
  REALM (a marked realm marked her).
- **The level ceiling** of section 6 applies with no new code: `class_level` is already counted at the field's
  top + 2 for skill ranks, stats and weapon level. A test shows a level-60 knight on THE FOOL'S ROAD strikes exactly
  as hard as one at the ceiling.
- **The helper ban** (`Field::may_help`). The ban applies when the target is flagged and struck a hero less than 60 s
  ago, and the helper is not flagged. A banned helper cannot:
  - heal her (HOLY LIGHT picks only allies it may help);
  - shield her;
  - give her a group or zone effect;
  - raise her by standing near, or with SANCTUARY.
  "Unmarked" is read as "not flagged": a war member or duellist is marked for that fight and may help.
- **The haul.** A hero downed by a hero's blow is recorded (`downed_by`, cleared when she is up), and the event
  `Slain{hero, by}` goes out with the `Down`.
  - If she then FALLS, the coin her haul loses goes to that hero's haul, with the event `Plunder{hero, by, coin}`
    (coin 0 if he has left).
  - The server must move the haul's lost items by the same event (open question 1).
  - Monster downs, duels and vaults never plunder.
- **Across leaving.** The core carries the mark and `struck_ago` in the outing. That already crossed copies;
  the host now also carries it home:
  - `Flush.mark` holds her mark and the ticks since her last strike. It is sent when either changes and always on
    leaving.
  - The gateway writes it to the mark book (`Social::note_mark`, kept through the social log as `mark` lines).
  - The book stores the **ticks of wait left** (10 min less `struck_ago`), not a time. The next ticket's outing
    reads it back (`Social::outing_mark`). The wait runs down **only while she is in a field**: time in town or
    logged out does not count.
- **Kill credit is cleared.** The downer is wiped when she rises, when a non-hero blow downs her, and when a hero
  leaves: `Field::forget_slot` clears every downer that names the leaver, her drops' claim and her zones, so a hero
  who reuses the slot inherits none of them.
- **Fixed on the way:** `Field::join` read a carried `struck_ago` that was longer than the field's age as a strike at
  tick 0, so a fresh copy saw an old strike as a new one. A strike older than 10 minutes now reads as none.

## Altar wars

- **In the core:**
  - `Field::set_guild(id, guild)` tags a hero as she joins.
  - `Field::declare_war(id, guild a, guild b, tide)` arms a war for a tide index of this field. It is refused if
    either guild already fights in that tide, or when 32 wars are armed (`WARS_MAX`), so the count fits its byte.
  - The war goes on with the tide (`War{BEGIN}`) and ends with it, won early or lost (`War{END, winner, held}`).
- **Held altar time:** every tick, each lit or held altar with members of one side within its 150 px circle and none
  of the other adds one tick to that side. More ticks wins, and equal is a draw (`WAR_DRAW`). Held altars count too,
  because the fight goes on after an altar is held.
- **At the gateway** (`SReq` 0x5C..0x5F):
  - Declare, accept, list and call off, by the leader or an officer only (rank 0 or 1).
  - A war is for the field's first tide that starts at least **2 minutes** after the declaration
    (`WAR_LEAD_TICKS`), so the other guild has time to answer and gather.
  - At most **3** wars waiting per guild, counted on the declaring side only (`WARS_PER_GUILD`), so a third guild
    cannot fill a victim's quota. One accepted war per guild per field tide: a declaration or an accept is refused
    when either guild already has one.
  - Declare, decline, call off and duel challenges share a burst limit of **5 a minute per account**
    (`PVP_BURST`, `SLOW_DOWN`).
  - Only the declared-on guild accepts. Either guild may call a war off until it is being fought.
  - A war unanswered when its tide starts is off (`WarOff`). An accepted war with no `war_result` one minute after
    its tide ends (`WAR_RESULT_GRACE_TICKS`) is ended as a draw (`wend`, winner 0), so guilds are not locked out.
  - Kept in the social log (`wdecl`, `wacc`, `woff`, `wend`).
  - `Social::wars_for(field, tide)` and `guild_of_account` are what a field copy needs. `Social::war_result` takes
    the core's END: both guilds hear `WarResult`, and a second copy's report is ignored.

## Duels

- **In the core:** `Field::open_duel(seed, cfg)` is the training yard.
  - A 640 px open square with walls round, no monsters, no tides, no safe ground, and the class cap (60) as its top.
  - Its state bytes use vault byte 254 (`YARD`).
  - `start_duel(a, b)` starts the duel, and the next tick sends `Duel{BEGIN}`. Only the two strike each other.
  - It ends at a down: the other wins, or both downed is a draw. Otherwise it ends at **3 minutes**: more health in
    thousandths wins, and equal is a draw.
  - Both rise whole. Nobody falls and no haul is lost.
- **At the gateway:**
  - Challenge, accept or decline by name. Both must be in town and not in a duel; a challenge lives **30 s**, and an
    ignoring player refuses challenges.
  - On accept, the gateway builds a yard with both heroes' real sheets, starts it, and pushes `DuelStart` (foe,
    seed) to both.
  - At most **64** duels run at once (`DUELS_MAX`); an accept beyond that answers BUSY.
  - The town ticker steps every yard **2 core ticks per town step** (10 Hz town, 20 Hz core), outside the social
    lock: the yards are taken out, stepped, and put back. Town input (direction)
    steers, and weapons fire on their own.
  - A duellist who leaves town forfeits.
  - Both get `DuelResult`, and a `duel` line goes to the log as a record.

## Marked realms

`Field::set_marked_realm(true)` marks every present hero past class level **20** for good, and every hero who joins
later. "Past level 20" is read as 21 or more, so a level-20 hero can still take the mark by the rite as anywhere.
The rite answers `MARK_FOR_GOOD` to a realm-marked hero. The flag is in the state bytes.

## State, events, wire

- **No saved format changed.** The hero bytes keep `marked` and `last_struck` as before, and `STATE_VERSION` stays 3.
- The rest is one block appended after the realm block, written only when something is in it. A field without PvP
  therefore has the same bytes and hash as before R3 (tested):
  - tag `0x50`;
  - the realm flag;
  - the wars;
  - the duel;
  - non-zero guild tags;
  - who downed whom.
- A yard is the vault byte 254, which no saved field used.
- **Events** are appended after `Vault`, keeping section 12's order: `Mark` 17, `Struck{hero, by, raw, amount}` 18,
  `Slain` 19, `Plunder` 20, `War` 21, `Duel` 22.
- **Wire:**
  - The social span's last free requests: `0x5C` WarDeclare(foe, field), `0x5D` WarAnswer(war, accept),
    `0x5E` WarList, `0x5F` Duel(op 0 challenge, 1 accept, 2 decline; other values refused, name).
  - Replies 6 `Wars` and 7 `WarDeclared`. Pushes 9 to 15.
  - The span reserved for PvP in `proto/ranges.rs` (0x74..0x77, 0x8D, 0xAA) is left free for later.
- **Interface additions in other owners' files (small):**
  - `server/src/host.rs`: `Flush.mark`, and the tally reads `Mark` and `Struck`.
  - `gateway/src/gateway.rs`: the duel step in the town ticker, town input to the duel, the outing reads the mark
    book, and an applied flush writes it.
  - `gateway/src/world/mod.rs`: `mark: None` on two flushes.
  - `docs/realm/social.md`: the new tags.

## Bots

- `Plan::hunter(rally)` is a crowd bot with `hunt`. When it is flagged, it walks to the nearest foe within **900 px**
  who is off safe ground. It keeps 24 px (melee), 120 px (healer) or 160 px (ranged), and backs away under **30%**
  health.
- No bot raises a hero the help ban forbids it to raise.
- A hunter does not raise a hero she is marked against. Without that, killers raised their own prey and nobody ever
  fell.

## Proof

| Proof | Result |
|---|---|
| Bench (`bench_1000_heroes_half_marked_among_20000_monsters_inside_the_budget`, `PVP_BENCH_ALL=1`): 1,000 heroes at their field's bottom level (at least 20), 500 of them marked hunters, 20,000 monsters, a tide, 4 threads, 900 ticks, the last 600 measured | See the table below. |
| `property_no_unmarked_hero_is_struck_or_robbed_and_nobody_on_safe_ground`: 18 seeds, all six fields, 60 heroes (marked hunters, two warring guilds, a third guild, unmarked; a seventh placed by the waystones), 500 ticks each | 86,556 blows and 1,259 downs by heroes. No blow on an unmarked hero, from or onto safe ground, or onto a third party of the war; no plunder of an unmarked hero. |
| `property_the_haul_goes_only_to_the_hero_who_downed_her`: 10 seeds, isolated pairs of marked hunters, 1,500 ticks | Every fall after a hero's blow pays exactly that hero what the fall lost. 6 seeds gave 21 plunders and 30,479 coin. |
| `property_a_duel_never_strikes_a_third_party`: 18 seeds, 2 duellists and 3 bystanders, 2 of them marked | Every duel ends; no blow outside the pair, no fall, no plunder. |
| `same_hash_with_hunters_and_a_war_on_1_to_4_threads_and_a_follower`: THE MOON MARSH and THE TOWER, 200 heroes, 600 ticks | Hashes equal every 50 ticks on 1, 2, 3 and 4 threads and on a follower loaded from bytes at tick 200. The existing `hash_gate` still passes. |

Bench, tick in ms (CPU with 4 cores, load average about 0.6):

| Field | mean | p99 | blows | downs by heroes |
|---|---|---|---|---|
| THE FOOL'S ROAD | 4.86 | 8.13 | 401,335 | 4,106 |
| THE HANGED WOOD | 5.21 | 8.86 | 371,098 | 4,010 |
| THE MOON MARSH | 4.99 | 8.69 | 366,352 | 4,092 |
| THE HERMIT'S PEAKS | 5.68 | 9.25 | 672,943 | 3,706 |
| THE TOWER | 5.01 | 9.28 | 667,908 | 2,743 |
| THE WORLD'S EDGE | 6.19 | 13.17 | 788,841 | 2,043 |

Every field is well inside the 50 ms budget, and within about 1 ms of R2's crowd bench without PvP.

## Open questions

1. **Items of a plundered haul.** The core moves the coin; the server should move the lost items to `by` on
   `Plunder` (`host.rs` and the loot job's `Haul::fall`).
2. **Wars in the field hosts.** Wars need a bridge that the host and the lockstep wire do not yet carry. The gateway
   and the core are ready on both ends. The bridge must:
   - tag heroes at admit with `Field::set_guild` (`Social::guild_of_account`);
   - arm `declare_war` on every copy of the field before the tide (`Social::wars_for`);
   - send `War{END}` back (`Social::war_result`).
   Followers must apply the same calls for the hash, so the Join record needs the guild and a WAR record is needed:
   a W1 protocol change.
3. **Duels are run in the gateway with town input only** (direction; the weapon fires on its own, with no skills or
   potions), and clients see only the start and the result.
   - A real yard view needs either a host per duel or yard snapshots in the town push.
   - The town has no yard zone yet (`wire.md`: no town zones), so a challenge may be made anywhere in town.
4. Should **being struck by a hero** count as tide contribution ("half of damage taken")? Today it does, as any hit.
5. **Stuns, slows and pushes** on heroes are left out; say if marked fights should have them.

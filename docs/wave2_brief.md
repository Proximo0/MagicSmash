# Wave 2 brief (v2): 21 Nov to 4 Dec. A worker gets the preamble and one section.

**Preamble (paste first).** Read `CLAUDE.md`, `docs/agent_brief.md`, the rules atop `docs/push_brief.md`. Own worktree, no git; touch only files you own. Use `tools/map.sh` and `tools/outline.sh` before opening files. End with `tools/check_all.sh` green. New Tuning rows stay neutral unless your job owns them. Report files, checks, numbers.

## 0. Step 0: split the giant scripts (after A3 merges; two workers)

Each new file is `class_name X extends RefCounted`: static functions whose first argument is the owner (`w: World`, `a: Arena`); bodies change `foo` to `w.foo` only. The owner keeps its fields, and one-line forwarders for functions called from other files (`grep -rn 'w\._'`), so no test changes. Call order and rng draws stay.

**S1: world.gd into game/logic/world/.** First, make `tools/golden_run.gd` hash fields both trees have (rng state, wave, phase, score, wizards' pos, hp, lives, upgrades, enemies' pos and hp), not `state_hash()`, so a row change reads as same.
- world.gd, the public face (about 15 KB): constants, EV codes, fields, _init, apply_meta, step, _fight, _end_run, events, pscale, party_center, totals, is_picking, gain_xp, grid, hash, snapshot, forwarders.
- entities.gd: classes Player, Enemy, Shot, Rune, EShot, Shrine, Pickup, aliased in world.gd (`const Player = WorldEntities.Player`); if lint refuses the alias as a type, they stay.
- levels.gd: _update_levelups, _offer, _pick.
- waves.gd: _tick_minute to _spawn_random_powerup, less the Lich functions.
- players.gd: _update_player, _leash, _nova, hurt_player.
- casting.gd: _auto_cast to _weapon_snap, and _update_shots to _update_runes.
- enemies.gd: _nearest_player, _update_enemy, _separate, _eshot, _faded, _damage_enemy, _heft, _kill_enemy, _update_eshots.
- bosses.gd: _update_lich, _make_final, _lich_hp_scale, _lich_visits.
- drops.gd: _roll_card, _roll_drop, the urns, _drop_xp, _drop, _update_pickups, _magnet_xp, _collect, _open_chest.
- shrines.gd: _update_shrines, snapshot_shrines, _place_shrine, _bet, _resolve_gamble.

Proof: `tools/golden.sh` prints `GOLDEN same`; sim_horde within 5% of before.

**S2: arena.gd into game/arena/.** Add `class_name Arena`.
- arena.gd (about 15 KB): _ready, _exit_tree, _timed, _layer, the loops, _smooth, _on_snapshot, _on_roster_changed, _on_screen, shake, hitstop, decal, _is_local_slot, input, pause.
- view_sync.gd: _apply_snapshot. seats.gd: _with_pick, _bot_input. events.gd: _handle_events.
- fate_view.gd: _clock, reveals, shrines, _rune_stone, bets, fate, _banner, act card, _update_act, _act_music.
- draw_world.gd: _follow_party, decals, env, hint, runes, _shadow, treasure glow, entities, player, staff.
- draw_fx.gd: trails, torches, spell and pickup colours, shots, enemy shots. draw_enemies.gd: enemy glows, enemies, bars.
- hud.gd: _draw_hud, _draw_offscreen, _heart, _hat, _star. tray.gd: A3's tab, marker and tray. results_view.gd: game over, result columns, moments, pause.

Proof: `GOLDEN same`; autotest captures (seed 3, 1 and 4 wizards) pixel-identical outside the frame stamp.

## 1. Core commit (one worker, after Step 0; GOLDEN same)

- **Player row, final for waves 2 and 3**, read only through `World.P_*`. The per-spell block goes. New: `P_SPELLS` 4 x (catalogue id or -1, level; 6 = evolved), `P_PASSIVES` 4 x (id or -1, level), in the order taken; redraws, banishes, down (0/1), down_left (s; -1 = ritual only), revive (0..1), ai, trait_a, trait_b (0 until wave 3). Offers stay 3 cards. Header: seal, slot_cap. Enemy row: status bits. Rune row: kind. Snapshot key "o" for spell objects `[kind, owner, x, y, a, b, t, evo]`, empty.
- `World.Player`: those fields plus banned (Dictionary), down_t, rituals, call_t.
- **Catalogue append-only:** rows get `kind` (PASSIVE, INSTANT, SPELL, EVOLUTION, MINOR) and `spell`; today's ids stay; W_FIRST and EVO_FIRST go. Land `Upgrades.kind(i) -> int`, `spell_of(i) -> int`, `evolves(i) -> int`, `slots_used(levels: Dictionary) -> Vector2i`, `slot_ids(levels: Dictionary, kind: int) -> Array[int]`, `available(levels: Dictionary, i: int, cap: Vector2i, banned: Dictionary) -> bool`, `pick_score(levels: Dictionary, i: int) -> float`, `Spells.partner(sp: int) -> int`.
- **World:** `graves() -> Array` of `[slot, x, y, revive, down_left]`, `can_return(p: Player) -> bool`, `humans() -> Array[Player]`, `slot_cap() -> Vector2i`, `apply_seal(level: int)` (stub, after apply_meta; `--seal=N` in tools). Events after EV_LULL: EV_DOWN, EV_REVIVE, EV_CALL, EV_REDRAW, EV_BANISH, EV_FATE, EV_SLOTS, EV_TALK. pscale reads `down_spawn_weight`, `apprentice_scale`.
- **Net:** `G.DEV_AI = -2`, `G.DEV_KB2 = -3`; roster rows carry `ai`; `Net.my_slots()` humans only, `Net.ai_slots()`, `Net.seal` and `set_seal()` synced with the roster. `G.finish_run(run: Dictionary)`, and Save and Profile likewise. `Results.to_dict` carries ai, source_damage, downs, revives.
- **Layout and empty stubs:** HUD panels 108 px at x 2, 110, 262, 370, a 44 px centre column; `ArenaHud.vitals` (F, row 1), `build` (E, row 3: 8 pips, 9 px, from x+16), `centre` (H). `ArenaTalk.draw` (M). Lobby seats 56 px tall, seal row `Rect2(34, 218, 412, 14)`, `_draw_seats` (G), `_draw_seal_row` (H). Camera centres on the bounding box of standing humans.
- Test files test_world_builds, _fallen, _seals, _apprentice, test_fate, one passing test each.

## 2. Decisions

| Fork | Decision: reason |
|---|---|
| Revive | A spirit tethered to the party, ritual circle on it: the fallen keeps playing, the circle stays on screen. |
| Slots | 3 + 3 until the first act boss falls (the Bone Chandelier once job L lands), then 4 + 4: Act II gets a build choice. Tomes and chests obey `available` too. |
| Floor tomes | Spell tomes leave the floor for one party tome (in E), so picks shape builds. |
| Evolutions | One partner, weighed x4, last passive slot kept for partners: lock-out 68% to about 33%. |
| HEX | Wave 3, a curse bolt that damages and marks: a spell must kill alone. |
| Seals | HASTE, FRAILTY, WRATH go; FAMINE, LEGION, CHAMPIONS are rewritten (list in H): each Seal must change how a run plays. |
| Seal rewards | Crystals multiplied on boss and win bounties only, so losing fast pays nothing; best Seal per wizard shown. |
| Catalogue | Append-only, dense, kind column: nothing saved holds an id. |
| Fate | 8 fates from effects the world has: it is the hook. |
| Intermission | The 20 s lull after each Lich; Morvane speaks. No scene. |
| HUD, lobby layout | The core worker; jobs fill stubs. |
| Apprentices | Yes, helpers that take no loot or bets. |
| Banish, evolution chart, damage by spell | Yes (E, J, J). |
| Endless mode | Wave 3. |

## 3. Balance targets (tools/playtest.gd, 6 seeds a row)

| Finding | Now | Target |
|---|---|---|
| Minute 1 solo | 12-13 foes within 60 px; novice down by 0:22-1:39 | 6 or fewer; novice down after 2:00 in 4 of 6 |
| After minute 2 | pressure 0.4-1.4 at m6; level 14-16 at 6:00; evolution 0:46-2:03 | pressure 3-6; level 10-12; veteran evolves 4:00-6:30 |
| Lich | dies in 3-27 s | 40-70 s; Archlich 90-150 s; wins novice 10-30%, casual 40-60%, veteran 80%+ |
| XP fades | 14-31% | 10% or less |
| Gold | 0-25% spent | casual spends 50%+ |
| Enemy shots | 29-48% of hits | 15-25% |
| Arcane bolt | 1-12% of damage | 15%+ of holder's; spell_dps within 20% of median |
| Party level | 4 wizards +16% | within 1 level of solo |

## 4. Jobs

### E: builds
E1: spells dispatch on the `cast` kind of `Spells.STATS`; projectile behaviour is data on Shot; GOLDEN same. E2: slots (3 early, 4 after the Lich); partner weight 4 and the kept slot; redraws 2 (input field 6 = -2, or R / D-pad down); banishes 2 (field 6 = 10 + card, or hold the card's button 1 s: it leaves this wizard's pool, then redraw); Minor Arcana fill a short hand (CUPS a heart, PENTACLES gold, SWORDS a nova, WANDS +3% damage); spell tomes leave the floor, one party tome (each Lich, 25% of elites, rare urns) levels a random owned spell of every wizard; pick_score; damage per spell per wizard. Bugs E4, E5, E6 (cooldowns keep fractions; `cast_floor` 0.35).
Owns: spells.gd, upgrades.gd, tests, spell_dps.gd, world/casting.gd, world/levels.gd, _collect, _open_chest, _roll_drop, _spawn_random_powerup, ArenaHud.build, arena/tray.gd.
Tests (test_world_builds): caps around the Lich; tomes obey slots; redraw; banish; partner weight; Minor Arcana.

### F: the fallen and the ritual
Party of 2+: at 0 hearts a wizard falls (EV_DOWN) as a spirit: 45 px/s, leashed to the standing, unhurt, no casting, gathers XP. Circle 30 px on the spirit; each ally inside adds dt / 2.0 s; holds with an ally within 60 px, else drains over 8 s. Push enemies 80 px when the first ally enters and at the end; both get 2 s safe; risen with ceil(max/2) hearts, novas kept. Each later ritual on her takes 0.5 s more. Down 10 s with lives > 1: lose one, return by the party; lives == 1: wait; the clock stops while an ally is in. Nobody standing: the longest-down with lives > 1 returns after 1.5 s. A slain Lich raises all. Nova while down: EV_CALL, 2 s apart. `deaths` = lives lost; new `downs`, `revives`. Bugs E2, L4, L8.
Owns: world/players.gd, graves, can_return, the wipe in step, ArenaHud.vitals, spirit and circle drawing, results.gd.
Tests (test_world_fallen): solo GOLDEN same; each rule once.

### G: apprentices and seats
`Net.add_apprentice() -> int`, `remove_apprentice(slot := -1)`, kept across runs; a joining human takes the highest; a seat silent 5 s becomes one until its device speaks. World picks for ai wizards at once (pick_score). Damage x0.7, spawn weight 0.7; potions only at 2 hearts or fewer with no human hurt; no chests, tomes, cards, shrines, fate; coins and gems go to humans; up after 6 s down, free (not in DARKNESS); answer a call. Decide every third tick on one shared context. Keyboard seat 2: arrows, right Ctrl. Lobby: Y or + adds, X or - removes, P1's START begins, A never starts; INVITE calls `Platform.invite_friends()`. Bugs L2/N1 (run-ending events by reliable RPC), L3, N3, N4, N7.
Owns: smash_bot.gd, playtest tools, docs/bots.md, net.gd, platform.gd, player_input.gd, arena/seats.gd, _draw_seats and lobby input in title.gd.
Tests (test_world_apprentice): roster by slot; no loot or bets; `--party=casual,apprentice`.

### H: Seals
New seals.gd: COUNT, `values(level) -> Dictionary` (cumulative), title, describe; apply_seal sets World fields, never Tuning. I HUNGER enemy health +25%; II AMBUSH rifts warn half as long; III FAMINE no horde potions (urns, elites, bosses still drop); IV LEGION groups +25%, cap 325 if sim_horde holds; V CHAMPIONS elites +50% health with an escort; VI MISFORTUNE `fate_cruel` 0.6; VII SILENCE 2-card draws; VIII DARKNESS lives 1, no JUDGEMENT, rituals x2, a wizard with no ally keeps 2. Profile: seal_unlocked, seal_best per wizard, kills_total, revives_total; a win at the top Seal opens the next; crystals x(1 + 0.5 x seal) on boss and win bounties only. Lobby row, HUD numeral, results line. `playtest --seal=N` prints win rates; a Seal not placed between its neighbours is cut.
Owns: seals.gd, profile.gd, save.gd, tests, ArenaHud.centre, _draw_seal_row, seal lines in world/waves.gd and drops.gd.
Tests (test_world_seals): seal 0 GOLDEN same; each Seal moves one value; old profiles load.

### I: acts II and III
Burning Library, then Starless Sanctum, to the Ossuary's standard; each a new place in a thumbnail. Owns arena_art_library.gd, arena_art_sanctum.gd, palettes, props.

### J: UI art
Fate reel (8 fates) and tray cards first; results (party level, damage by spell, fates drawn); GRIMOIRE pause page (slots, partners, evolutions); HUD art in the core's rects. Owns tarot_art.gd, fate_view.gd, results_view.gd, hud.gd outside the stubs. Tests: longest text fits; GRIMOIRE lists every pair.

### K: enemies
See bestiary_design.md. Bugs E3, E7.

### L: act bosses
See bestiary_design.md. Bugs E1, E8, L7.

### M: hub and portraits
The Sanctum is the hub. Three NPCs, each with a full-height portrait (about 200x270, the test portrait of Morvane sets the standard; Curtis may supply example art to match): the shopkeeper sells META, the card reader explains fates, Seals and pairs, Morvane taunts after runs and in each lull (EV_TALK, never blocks play). Box: portrait, name, two lines; confirm skips. Lines are data keyed by condition (first visit, loss, win, Seal, act).
Owns: new logic/talk.gd, ui/dialogue_box.gd, art/portrait_art.gd, arena/talk_view.gd; sanctum.gd, sanctum_view.gd, test_talk. Tests: every line fits; every condition has one.

### N: the fate deck
TEAM_OUTCOMES 2 to 8, appended. Kind: THE SUN (today), THE WORLD (gems fly in, all heal 2), THE EMPEROR (a chest per human), THE FOOL (next card counts twice). Cruel: DEATH (today), HANGED MAN (novas sealed 60 s), HIEROPHANT (no potions 90 s), WHEEL OF FORTUNE (two more fates). 50/50 by side, `fate_cruel` for MISFORTUNE. EV_FATE carries the id. Bug N10. Owns gamble.gd, world/shrines.gd, test_gamble, test_fate. Draws nothing.

### P: balance
Hit the targets of part 3 (paste it with this job). Add kills per minute, shrine uses, Archlich time to the report. Owns Tuning defaults, Spells.STATS numbers, horde tables, seal values. Show 6 seeds before and after each change.

### Q1: save and shell fixes
L1/S1, L5, S2, L9/S8, S5, S6, S9, S10. Owns save.gd, profile.gd, sanctum.gd, settings.gd, platform.gd, ouija.gd, export presets. A test per bug.

### Q2: input and pause fixes
N2, N5, N6, N8/L6, N9, S3. Owns arena input and pause, arena/events.gd. A test per bug where possible.

## 5. Order

| Days | 1 | 2 | 3 |
|---|---|---|---|
| 21-22 Nov | S1 | S2 | Q1 |
| 23 | Core | I | - |
| 24-26 | E | F | N |
| 27-29 | G | H | J |
| 30 Nov-2 Dec | K | L | M |
| 3-4 Dec | P | Q2 | M |

E and F share drops.gd; K and L share enemies.gd (L draws in a new draw_bosses.gd). G needs E and F; H needs F and N; J needs E and N; Q1 before H and M; Q2 after J; P last. Merge with git, never by copying; golden.sh and check_all after each. Store shots 2 Dec: fate reel, a ritual, the tray, four at the Lich, the hub.

## 6. Added 20 Nov after Curtis's art verdict (the bar: holds up on a Steam store page beside shipped games)

Lead's re-judgement of merged wave 1 art. Holds up: logo, title backdrop, Act I floor. Falls short, in order: the fight HUD (plain text and lines), wizards too small and lost in a busy fight, no lighting or mood in the room, flat lobby seat cards, plain menu text and tiny title wizards.

### R: readability and polish (runs with the core, before E; one art worker, lead judges at 2x and 4x)
R1 HUD art in the core's rects (framed panels, heart and level art, icons, a designed font treatment). R2 wizards: larger sprites or a stronger outline and floor ring so each is found within a second in a 4-player Lich frame (measure on captures). R3 room lighting: torch light pools, vignette, darker edges, spell light on the floor, within the frame budget. R4 lobby seat cards with large wizard art. R5 menu text styling and bigger title wizards. Job J keeps the fate reel, tray, results and GRIMOIRE.

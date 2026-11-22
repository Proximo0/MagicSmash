//! Players against players (rules section 14, job R3): the BLOOD MARK, safe ground, the helper ban, the haul to
//! the hero who downed her, the ten-minute wait, guild altar wars, duels, marked realms, the hunters' crowd budget
//! and the same hash on every thread count.

mod common;
use common::*;
use realm_core::bots::{Bot, Plan};
use realm_core::pvp::*;
use realm_core::{tide_start, Event};

fn marked() -> Outing {
    Outing { marked: true, ..Outing::new() }
}

/// An open spot of `f` off safe ground (sub units).
fn open_spot(f: &Field) -> (i32, i32) {
    let (x, y) = spot(f, 24);
    for k in 0..64 {
        let (cx, cy) = (x + (k % 8 - 4) * px(400), y + (k / 8 - 4) * px(400));
        if !f.safe_ground(cx, cy) && !f.terrain().wall(cx, cy) && !f.terrain().wall(cx + px(40), cy) && !f.terrain().wall(cx - px(40), cy) {
            return (cx, cy);
        }
    }
    panic!("no open spot off safe ground");
}

/// Two heroes 20 px apart off safe ground, with the outings given.
fn pair(field: u8, class: u8, level: u8, oa: &Outing, ob: &Outing) -> (Field, u16, u16) {
    let mut f = quiet(field);
    let (x, y) = open_spot(&f);
    let a = f.join(&bare(class, level), oa, x, y);
    let b = f.join(&bare(class, level), ob, x + px(20), y);
    (f, a, b)
}

/// Every `Struck` of the last tick as (victim, attacker, raw, taken).
fn struck(f: &Field) -> Vec<(u16, u16, u32, u32)> {
    f.events().iter().filter_map(|e| if let Event::Struck { hero, by, raw, amount } = *e { Some((hero, by, raw, amount)) } else { None }).collect()
}

fn marks(f: &Field) -> Vec<(u16, u8)> {
    f.events().iter().filter_map(|e| if let Event::Mark { hero, state } = *e { Some((hero, state)) } else { None }).collect()
}

fn run_until<T>(f: &mut Field, inputs: &[u16], max: u32, mut found: impl FnMut(&Field) -> Option<T>) -> Option<(u32, T)> {
    for t in 0..max {
        f.step(inputs);
        if let Some(v) = found(f) {
            return Some((t + 1, v));
        }
    }
    None
}

#[test]
fn marked_heroes_strike_each_other_for_40_percent_of_a_monster_blow() {
    let (mut f, a, b) = pair(3, KNIGHT, 30, &marked(), &marked());
    let (_, hits) = run_until(&mut f, &[], 200, |f| Some(struck(f)).filter(|v| !v.is_empty())).expect("marked knights strike each other");
    let raw = hits.iter().find(|h| h.1 == a).expect("a struck b").2;
    assert!(hits.iter().all(|h| (h.0 == a && h.1 == b) || (h.0 == b && h.1 == a)));
    // The same knight's blow on a plain monster where b stood.
    let mut g = quiet(3);
    let (x, y) = open_spot(&g);
    let a2 = g.join(&bare(KNIGHT, 30), &marked(), x, y);
    let m = mon(&mut g, 0, 30, x + px(20), y);
    g.monsters_mut().hp[m as usize] = 1_000_000;
    let (_, loss) = run_until(&mut g, &[], 200, |g| Some(1_000_000 - g.monsters().hp[m as usize]).filter(|&d| d > 0)).expect("she strikes the monster");
    assert_eq!(a2, a);
    assert_eq!(raw, (loss as u64 * PVP_DAMAGE_PCT / 100) as u32, "a blow on a hero is 40% of the blow on a monster");
    // The struck hero lost what the event says, through her own reductions.
    assert!(f.heroes()[b as usize].health < f.heroes()[b as usize].max_health);
    assert!(f.heroes()[a as usize].last_struck != NEVER, "the striker's last-struck tick is kept");
}

#[test]
fn an_unmarked_hero_is_never_struck_and_never_strikes() {
    for (oa, ob) in [(marked(), Outing::new()), (Outing::new(), marked()), (Outing::new(), Outing::new())] {
        let (mut f, a, b) = pair(3, KNIGHT, 30, &oa, &ob);
        for _ in 0..400 {
            f.step::<u16>(&[]);
            assert!(struck(&f).is_empty());
        }
        for id in [a, b] {
            let h = &f.heroes()[id as usize];
            assert_eq!(h.health, h.max_health);
            assert_eq!(h.last_struck, NEVER);
        }
    }
}

#[test]
fn nobody_is_struck_on_safe_ground() {
    let mut f = quiet(3);
    let sites: Vec<(i32, i32)> = f.terrain().waystones.iter().copied().chain([f.terrain().gate]).collect();
    for (k, &(wx, wy)) in sites.iter().enumerate() {
        let a = f.join(&bare(KNIGHT, 30), &marked(), wx + px(150), wy);
        let b = f.join(&bare(KNIGHT, 30), &marked(), wx + px(170), wy);
        let (ax, ay, bx, by) = (f.heroes()[a as usize].x, f.heroes()[a as usize].y, f.heroes()[b as usize].x, f.heroes()[b as usize].y);
        if !(f.safe_ground(ax, ay) && f.safe_ground(bx, by)) {
            f.leave(a);
            f.leave(b);
            continue;
        }
        for _ in 0..200 {
            f.step::<u16>(&[]);
            assert!(struck(&f).is_empty(), "site {k}: struck on safe ground");
        }
        f.leave(a);
        f.leave(b);
    }
    // The edge: one of them on safe ground is enough to stop the blows both ways.
    let (x, y) = sites[0];
    let a = f.join(&bare(KNIGHT, 30), &marked(), x + px(SAFE_PX - 10), y);
    f.join(&bare(KNIGHT, 30), &marked(), x + px(SAFE_PX + 10), y);
    if f.safe_ground(f.heroes()[a as usize].x, f.heroes()[a as usize].y) && !f.terrain().wall(x + px(SAFE_PX), y) {
        for _ in 0..200 {
            f.step::<u16>(&[]);
            assert!(struck(&f).is_empty());
        }
    }
    assert!(!f.safe_ground(open_spot(&f).0, open_spot(&f).1));
}

#[test]
fn the_mark_is_taken_by_a_five_second_rite_at_level_20() {
    let rite = IN_INTERACT | IN_MARK;
    for (level, want) in [(19u8, MARK_LOW_LEVEL), (20, MARK_TAKEN), (45, MARK_TAKEN)] {
        let mut f = quiet(0);
        let (wx, wy) = f.terrain().waystones[0];
        let a = f.join(&bare(KNIGHT, level), &Outing::new(), wx, wy);
        f.hero_mut(a).coin = 50;
        let h = &f.heroes()[a as usize];
        assert!(dist(h.x, h.y, wx, wy) <= px(WAYSTONE_PX) as i64);
        let (t, m) = run_until(&mut f, &[rite], 400, |f| marks(f).first().copied()).expect("the rite ends");
        assert_eq!(t, MARK_HOLD as u32, "five seconds of holding");
        assert_eq!(m, (a, want));
        assert_eq!(f.heroes()[a as usize].marked, want == MARK_TAKEN);
        assert_eq!(f.heroes()[a as usize].coin, 50, "the rite never banks");
        // The coin and the luck of the mark.
        if want == MARK_TAKEN {
            let mut g = quiet(0);
            let u = g.join(&bare(KNIGHT, level), &Outing::new(), wx, wy);
            g.step::<u16>(&[]);
            f.step::<u16>(&[]);
            assert_eq!(f.mods(a).unwrap().coin_pct, g.mods(u).unwrap().coin_pct + MARK_COIN_PCT);
            assert_eq!(f.luck(a), g.luck(u) + MARK_LUCK);
        }
    }
    // Plain interact still banks at 3 s.
    let mut f = quiet(0);
    let (wx, wy) = f.terrain().waystones[0];
    let a = f.join(&bare(KNIGHT, 20), &Outing::new(), wx, wy);
    f.hero_mut(a).coin = 50;
    let (t, _) = run_until(&mut f, &[IN_INTERACT], 200, |f| (count(f, BANK) > 0).then_some(())).expect("banks");
    assert_eq!(t, BANK_HOLD as u32);
}

#[test]
fn the_mark_waits_ten_minutes_after_a_strike_even_across_leaving() {
    let rite = IN_INTERACT | IN_MARK;
    let mut f = quiet(0);
    let (wx, wy) = f.terrain().waystones[0];
    let a = f.join(&bare(KNIGHT, 25), &marked(), wx, wy);
    f.step::<u16>(&[]);
    f.hero_mut(a).last_struck = f.tick();
    // She leaves and comes back: the wait came with her.
    let o = f.outing(a).unwrap();
    assert!(o.marked && o.struck_ago < 5);
    f.leave(a);
    idle(&mut f, 30);
    let a = f.join(&bare(KNIGHT, 25), &o, wx, wy);
    let (_, m) = run_until(&mut f, &[rite], 400, |f| marks(f).first().copied()).unwrap();
    assert_eq!(m, (a, MARK_WAIT));
    assert!(f.heroes()[a as usize].marked);
    // Ten minutes after her last strike (counted in the field) she can put it down.
    f.hero_mut(a).last_struck = f.tick();
    idle(&mut f, MARK_WAIT_TICKS - MARK_HOLD as u32 - 1);
    let (_, m) = run_until(&mut f, &[rite], 400, |f| marks(f).first().copied()).unwrap();
    assert_eq!(m, (a, MARK_WAIT), "one tick short");
    let (_, m) = run_until(&mut f, &[rite], 400, |f| marks(f).first().copied()).unwrap();
    assert_eq!(m, (a, MARK_PUT_DOWN));
    assert!(!f.heroes()[a as usize].marked);
    // Carried in from another outing ten minutes old: down at once.
    let o = Outing { marked: true, struck_ago: MARK_WAIT_TICKS, ..f.outing(a).unwrap() };
    f.leave(a);
    let a = f.join(&bare(KNIGHT, 25), &o, wx, wy);
    let (_, m) = run_until(&mut f, &[rite], 400, |f| marks(f).first().copied()).unwrap();
    assert_eq!(m, (a, MARK_PUT_DOWN));
    // Never struck: down at once.
    let mut g = quiet(0);
    let b = g.join(&bare(KNIGHT, 25), &marked(), wx, wy);
    let (_, m) = run_until(&mut g, &[rite], 400, |g| marks(g).first().copied()).unwrap();
    assert_eq!(m, (b, MARK_PUT_DOWN));
}

#[test]
fn an_unmarked_helper_cannot_heal_shield_or_raise_a_marked_hero_who_struck() {
    let mut f = quiet(3);
    let (x, y) = open_spot(&f);
    let a = f.join(&bare(KNIGHT, 30), &marked(), x, y);
    let u = f.join(&bare(PRIEST, 30), &Outing::new(), x + px(10), y);
    let m = f.join(&bare(PRIEST, 30), &marked(), x + px(4_000), y + px(4_000));
    f.step::<u16>(&[]);
    let (a, u, m) = (a as usize, u as usize, m as usize);
    assert!(f.may_help(u, a), "she struck nobody: anyone helps her");
    f.hero_mut(a as u16).last_struck = f.tick();
    assert!(!f.may_help(u, a) && f.may_help(m, a) && f.may_help(a, a));
    // Downed: the unmarked priest beside her does not raise her.
    {
        let h = f.hero_mut(a as u16);
        h.health = 0;
        h.downed = DOWNED_TICKS;
    }
    for _ in 0..100 {
        f.step::<u16>(&[]);
        assert_eq!(count(&f, RAISE), 0);
    }
    // A marked priest does.
    let (hx, hy) = (f.heroes()[a].x, f.heroes()[a].y);
    {
        let h = f.hero_mut(m as u16);
        h.x = hx + px(15);
        h.y = hy;
    }
    let (_, by) = run_until(&mut f, &[], 100, |f| f.events().iter().find_map(|e| if let Event::Raise { by, .. } = *e { Some(by) } else { None })).expect("raised");
    assert_eq!(by as usize, m);
    // A minute after the strike, the unmarked may help again.
    f.hero_mut(m as u16).marked = false;
    f.hero_mut(a as u16).last_struck = f.tick();
    idle(&mut f, HELP_BAN_TICKS - 1);
    assert!(!f.may_help(u, a));
    idle(&mut f, 1);
    assert!(f.may_help(u, a));
}

#[test]
fn a_hero_downed_by_a_hero_who_falls_loses_her_haul_to_him() {
    let (mut f, a, b) = pair(3, KNIGHT, 30, &marked(), &marked());
    f.hero_mut(b).coin = 500;
    f.hero_mut(b).health = 1;
    guard(&mut f, a);
    let (_, by) = run_until(&mut f, &[], 200, |f| f.events().iter().find_map(|e| if let Event::Slain { hero, by } = *e { (hero == b).then_some(by) } else { None }))
        .expect("downed by a blow");
    assert_eq!(by, a);
    assert_eq!(f.downed_by(b), a);
    // He walks off (or he would raise her: he is marked too).
    let (bx, by_) = (f.heroes()[b as usize].x, f.heroes()[b as usize].y);
    {
        let h = f.hero_mut(a);
        h.x = bx + px(300);
        h.y = by_;
    }
    let (_, (lost, plunder)) = run_until(&mut f, &[], DOWNED_TICKS as u32 + 5, |f| {
        let lost = f.events().iter().find_map(|e| if let Event::Fallen { hero, coin } = *e { (hero == b).then_some(coin) } else { None })?;
        let p = f.events().iter().find_map(|e| if let Event::Plunder { hero, by, coin } = *e { Some((hero, by, coin)) } else { None });
        Some((lost, p))
    })
    .expect("she falls");
    assert_eq!(lost, 250);
    assert_eq!(plunder, Some((b, a, 250)));
    assert_eq!(f.heroes()[a as usize].coin, 250);
    assert_eq!(f.heroes()[b as usize].coin, 250);
    assert_eq!(f.downed_by(b), NOBODY);
}

#[test]
fn a_monster_down_gives_nobody_her_haul() {
    let mut f = quiet(3);
    let (x, y) = open_spot(&f);
    let b = f.join(&bare(NOVICE, 1), &marked(), x, y);
    f.hero_mut(b).coin = 100;
    for k in 0..12 {
        mon(&mut f, 0, 30, x + px(10 + k), y);
    }
    let (_, _) = run_until(&mut f, &[], 2_000, |f| (count(f, FALLEN) > 0).then_some(())).expect("falls to monsters");
    assert!(!f.events().iter().any(|e| matches!(e, Event::Plunder { .. })));
}

#[test]
fn the_level_ceiling_holds_in_a_fight() {
    // THE FOOL'S ROAD: a level-60 knight counts as its top + 2, so his blow is that of a hero at that level.
    let top = FIELDS[0].top;
    let blow = |level: u8| {
        let (mut f, a, _) = pair(0, KNIGHT, level, &marked(), &marked());
        let (_, h) = run_until(&mut f, &[], 200, |f| struck(f).into_iter().find(|h| h.1 == a)).unwrap();
        (f.heroes()[a as usize].class_level, h.2)
    };
    let (l60, b60) = blow(60);
    let (lt, bt) = blow(top + CEILING_ABOVE_TOP);
    assert_eq!(l60, top + CEILING_ABOVE_TOP);
    assert_eq!((l60, b60), (lt, bt));
}

/// Guild ids of the war tests.
const G1: u64 = 11;
const G2: u64 = 22;
const G3: u64 = 33;

#[test]
fn an_altar_war_marks_two_guilds_against_each_other_only_for_the_tide() {
    let field = 3;
    let mut f = quiet(field);
    f.set_clock(tide_start(field, 0) - 10);
    assert!(f.declare_war(7, G1, G2, 0));
    assert!(!f.declare_war(8, G1, G3, 0), "a guild fights one war a tide");
    let (x, y) = open_spot(&f);
    let sheet = bare(KNIGHT, 30);
    let a = f.join(&sheet, &Outing::new(), x, y);
    let b = f.join(&sheet, &Outing::new(), x + px(20), y);
    let c = f.join(&sheet, &Outing::new(), x + px(10), y + px(15));
    let d = f.join(&sheet, &marked(), x + px(10), y - px(15));
    let e = f.join(&sheet, &marked(), x + px(30), y - px(15));
    for (id, g) in [(a, G1), (b, G2), (c, G3), (d, G1)] {
        f.set_guild(id, g);
    }
    for (id, h) in [(a, true), (b, true), (c, false), (d, true), (e, true)] {
        guard(&mut f, id);
        let _ = h;
    }
    // Before the tide: the war is not on; only the blood-marked d and e fight.
    for _ in 0..8 {
        f.step::<u16>(&[]);
        for (v, by, _, _) in struck(&f) {
            assert!([(d, e), (e, d)].contains(&(v, by)), "{by} struck {v} before the tide");
        }
    }
    let (_, ev) = run_until(&mut f, &[], 20, |f| f.events().iter().find_map(|e| if let Event::War { war, state, .. } = *e { Some((war, state)) } else { None })).expect("war begins");
    assert_eq!(ev, (7, WAR_BEGIN));
    let allowed = [(a, b), (b, a), (b, d), (d, b), (d, e), (e, d)];
    let mut seen = Vec::new();
    for _ in 0..200 {
        f.step::<u16>(&[]);
        for (v, by, _, _) in struck(&f) {
            assert!(allowed.contains(&(v, by)), "{by} struck {v}: not at war");
            seen.push((v, by));
        }
    }
    // Each guild strikes the other (b's arc may go to d, the nearer of the two).
    assert!(seen.contains(&(b, a)) && seen.iter().any(|&(v, by)| by == b && (v == a || v == d)), "the two guilds fight: {seen:?}");
    assert!(!seen.iter().any(|&(v, by)| v == c || by == c), "a third guild is never struck");
    // a holds a lit altar alone; b stays away: held time is a's guild's.
    let lit = (0..6).find(|&k| f.altars()[k].state == ALTAR_LIT).unwrap();
    let (ax, ay) = f.terrain().altars[lit];
    let h = f.hero_mut(a);
    h.x = ax;
    h.y = ay;
    let (_, end) = run_until(&mut f, &[], TIDE_LEN + 10, |f| f.events().iter().find_map(|e| if let Event::War { war, state: WAR_END, winner, held } = *e { Some((war, winner, held)) } else { None }))
        .expect("the war ends with the tide");
    assert_eq!(end.0, 7);
    assert_eq!(end.1, 0, "the guild that held the altar wins");
    assert!(end.2[0] > 1_000 && end.2[1] == 0, "{:?}", end.2);
    assert!(f.wars().is_empty());
    // After the tide nobody of the guilds strikes the other.
    for _ in 0..50 {
        f.step::<u16>(&[]);
        assert!(struck(&f).iter().all(|&(v, by, _, _)| [(d, e), (e, d)].contains(&(v, by))));
    }
}

#[test]
fn a_duel_in_the_yard_ends_at_a_down_with_no_haul_lost_and_touches_nobody_else() {
    let mut f = Field::open_duel(5, Config { monsters: 4096, threads: 1 });
    assert!(f.is_yard());
    let [s0, s1] = f.yard_spots();
    let a = f.join(&bare(KNIGHT, 30), &marked(), s0.0, s0.1);
    let b = f.join(&bare(ARCHER, 30), &Outing::new(), s1.0, s1.1);
    let c = f.join(&bare(KNIGHT, 30), &marked(), s0.0, s0.1 + px(20));
    for id in [a, b, c] {
        f.hero_mut(id).coin = 100;
    }
    // Before the duel nobody strikes, marked or not.
    for _ in 0..40 {
        f.step::<u16>(&[]);
        assert!(struck(&f).is_empty());
    }
    assert!(f.start_duel(a, b));
    assert!(!f.start_duel(a, c));
    f.step::<u16>(&[]);
    assert!(f.events().iter().any(|e| matches!(e, Event::Duel { state: DUEL_BEGIN, .. })));
    // A walks to B (input: east) and fights.
    let east = 3u16;
    let (_, (state, winner, loser)) = run_until(&mut f, &[east, 0, 0], DUEL_TICKS + 5, |f| {
        assert!(struck(f).iter().all(|&(v, by, _, _)| (v, by) == (a, b) || (v, by) == (b, a)), "a third party struck");
        assert_eq!(count(f, FALLEN), 0);
        f.events().iter().find_map(|e| if let Event::Duel { state, winner, loser } = *e { (state != DUEL_BEGIN).then_some((state, winner, loser)) } else { None })
    })
    .expect("the duel ends");
    assert!(state == DUEL_WON || state == DUEL_DRAW);
    assert!([a, b].contains(&winner) && [a, b].contains(&loser) && winner != loser);
    for id in [a, b, c] {
        let h = &f.heroes()[id as usize];
        assert_eq!(h.coin, 100, "a duel costs no haul");
        assert!(h.alive());
    }
    assert_eq!(f.heroes()[a as usize].health, f.heroes()[a as usize].max_health);
    // Over: nobody strikes any more.
    for _ in 0..40 {
        f.step(&[east, 0, 0]);
        assert!(struck(&f).is_empty());
    }
}

#[test]
fn a_duel_ends_after_three_minutes_and_survives_the_bytes() {
    let mut f = Field::open_duel(9, Config { monsters: 4096, threads: 2 });
    let [s0, s1] = f.yard_spots();
    let a = f.join(&bare(PRIEST, 30), &Outing::new(), s0.0, s0.1);
    let b = f.join(&bare(PRIEST, 30), &Outing::new(), s1.0, s1.1);
    guard(&mut f, a);
    guard(&mut f, b);
    for id in [a, b] {
        f.hero_mut(id).fx[FX_AEGIS as usize] = u16::MAX;
    }
    assert!(f.start_duel(a, b));
    idle(&mut f, 100);
    let mut g = Field::from_bytes(&f.to_bytes(), 1).expect("a yard loads");
    assert!(g.is_yard() && g.duel() == f.duel());
    assert_eq!(g.hash(), f.hash());
    let mut end = None;
    for t in 0..DUEL_TICKS + 10 {
        f.step::<u16>(&[]);
        g.step::<u16>(&[]);
        assert_eq!(f.hash(), g.hash());
        if let Some(e) = f.events().iter().find_map(|e| if let Event::Duel { state, .. } = *e { Some(state) } else { None }) {
            end = Some((t, e));
            break;
        }
    }
    let (t, state) = end.expect("ends at three minutes");
    assert_eq!(state, DUEL_DRAW, "both whole: a draw");
    assert_eq!(t + 100, DUEL_TICKS);
}

#[test]
fn a_marked_realm_marks_everyone_past_level_20_for_good() {
    let mut f = quiet(3);
    f.set_marked_realm(true);
    let (x, y) = open_spot(&f);
    let a = f.join(&bare(KNIGHT, 21), &Outing::new(), x, y);
    let b = f.join(&bare(KNIGHT, 20), &Outing::new(), x + px(20), y);
    assert!(f.heroes()[a as usize].marked && !f.heroes()[b as usize].marked);
    f.step::<u16>(&[]);
    // A level-20 hero takes it by the rite as anywhere else; a level-21 one cannot put it down.
    let (wx, wy) = f.terrain().waystones[0];
    {
        let h = f.hero_mut(a);
        h.x = wx;
        h.y = wy;
    }
    let (_, m) = run_until(&mut f, &[IN_INTERACT | IN_MARK], 400, |f| marks(f).first().copied()).unwrap();
    assert_eq!(m, (a, MARK_FOR_GOOD));
    // The flag survives the bytes.
    let g = Field::from_bytes(&f.to_bytes(), 1).unwrap();
    assert!(g.marked_realm());
    assert_eq!(g.hash(), f.hash());
}

#[test]
fn no_pvp_keeps_the_bytes_of_before() {
    // A field without any section-14 state writes no PvP block, so its bytes and hash are those of before R3.
    let mut f = quiet(2);
    let (x, y) = open_spot(&f);
    f.join(&bare(KNIGHT, 25), &Outing::new(), x, y);
    idle(&mut f, 20);
    let b = f.to_bytes();
    f.set_guild(0, 5);
    assert!(f.to_bytes().len() > b.len());
    f.set_guild(0, 0);
    assert_eq!(f.to_bytes(), b);
}

// ---- the crowd: properties over seeds, the same hash, the budget

struct Crowd {
    f: Field,
    bots: Vec<Bot>,
    /// Which heroes are marked, and their guild (0 none).
    marked: Vec<bool>,
    guild: Vec<u64>,
}

/// `heroes` bots on `field` (at its bottom level, at least 20), every third marked hunter, others in two warring
/// guilds and a third guild, some placed near the waystones; a tide begins after `lead` ticks.
fn crowd(field: u8, seed: u64, heroes: u32, monsters: u32, threads: usize, lead: u32) -> Crowd {
    let mut f = Field::open(field, 700 + seed, Config { monsters, threads });
    f.set_clock(tide_start(field, 0) - lead as u64);
    f.declare_war(seed, G1, G2, 0);
    let level = FIELDS[field as usize].bottom.max(MARK_LEVEL);
    let mut c = Crowd { f, bots: Vec::new(), marked: Vec::new(), guild: Vec::new() };
    let ways = c.f.terrain().waystones;
    for i in 0..heroes {
        let class = 1 + ((i + seed as u32) % 5) as u8;
        let sheet = Sheet::bench(class, (i % 4) as u8, level);
        let n = i as i32;
        let (x, y) = if i % 7 == 3 {
            let (wx, wy) = ways[(i as usize / 7) % ways.len()];
            (wx + (n % 5 - 2) * 40 * SUB, wy + (n % 3 - 1) * 40 * SUB)
        } else {
            (FIELD / 2 + (n % 40 - 20) * 20 * SUB, FIELD / 2 + (n / 40 - 12) * 20 * SUB)
        };
        let m = i % 3 == 0;
        let id = c.f.join(&sheet, &Outing { marked: m, ..Outing::new() }, x, y);
        let g = match i % 6 {
            1 => G1,
            2 => G2,
            4 => G3,
            _ => 0,
        };
        c.f.set_guild(id, g);
        let mut plan = if m || g == G1 || g == G2 { Plan::hunter(500) } else { Plan::crowd(500) };
        plan.every = 8;
        c.bots.push(Bot::new(id, seed, plan));
        c.marked.push(m);
        c.guild.push(g);
    }
    c
}

impl Crowd {
    fn step(&mut self) {
        let inputs: Vec<u16> = self.bots.iter_mut().map(|b| b.act(&self.f)).collect();
        self.f.step(&inputs);
    }
    /// Section 14's laws over the last tick's events.
    fn check(&self, what: &str) {
        let f = &self.f;
        let war_on = f.wars().iter().any(|w| w.on);
        let side = |i: usize| war_on && (self.guild[i] == G1 || self.guild[i] == G2);
        for e in f.events() {
            match *e {
                Event::Struck { hero, by, .. } => {
                    let (v, a) = (hero as usize, by as usize);
                    assert!(self.marked[v] || side(v), "{what}: unmarked hero {v} struck by {a}");
                    assert!(f.hostile(a, v), "{what}: {a} struck {v}, not marked against her");
                    let h = &f.heroes()[v];
                    assert!(!f.safe_ground(h.x, h.y), "{what}: {v} struck on safe ground");
                    let g = &f.heroes()[a];
                    assert!(!f.safe_ground(g.x, g.y), "{what}: {a} struck from safe ground");
                    if !(self.marked[v] && self.marked[a]) {
                        // Only the war: the two guilds, nobody else.
                        assert!(self.guild[v] != self.guild[a] && side(v) && side(a), "{what}: a third party in the war: {a} on {v}");
                    }
                }
                Event::Plunder { hero, .. } => {
                    let v = hero as usize;
                    assert!(self.marked[v] || self.guild[v] == G1 || self.guild[v] == G2, "{what}: unmarked hero {v} lost her haul to a hero");
                }
                Event::Slain { hero, .. } => {
                    let v = hero as usize;
                    assert!(self.marked[v] || side(v), "{what}: unmarked hero {v} downed by a hero");
                }
                _ => {}
            }
        }
    }
}

#[test]
fn property_no_unmarked_hero_is_struck_or_robbed_and_nobody_on_safe_ground() {
    let seeds: u64 = std::env::var("PVP_SEEDS").ok().and_then(|s| s.parse().ok()).unwrap_or(18);
    let ticks: u32 = std::env::var("PVP_TICKS").ok().and_then(|s| s.parse().ok()).unwrap_or(500);
    let mut strikes = 0u64;
    let mut slain = 0u64;
    let mut plunder = 0u64;
    let (mut falls, mut pvp_falls) = (0u64, 0u64);
    for seed in 0..seeds {
        let field = (seed % 6) as u8;
        let mut c = crowd(field, seed, 60, 3_000, 1, 40);
        for t in 0..ticks {
            let downer: Vec<u16> = (0..c.f.heroes().len() as u16).map(|i| c.f.downed_by(i)).collect();
            c.step();
            for e in c.f.events() {
                if let Event::Fallen { hero, .. } = *e {
                    falls += 1;
                    pvp_falls += (downer[hero as usize] != NOBODY) as u64;
                }
            }
            c.check(&format!("field {field} seed {seed} tick {t}"));
            for e in c.f.events() {
                match e {
                    Event::Struck { .. } => strikes += 1,
                    Event::Slain { .. } => slain += 1,
                    Event::Plunder { .. } => plunder += 1,
                    _ => {}
                }
            }
        }
    }
    println!("pvp property: {seeds} seeds, {strikes} blows, {slain} downed by heroes, {falls} falls ({pvp_falls} after a hero's blow), {plunder} plundered");
    assert_eq!(pvp_falls, plunder, "every fall after a hero's blow pays the hero");
    assert!(strikes > 1_000 && slain > 0, "the hunters fight ({strikes} blows, {slain} downs)");
}

#[test]
fn property_the_haul_goes_only_to_the_hero_who_downed_her() {
    // Pairs of marked hunters far apart on the ring (nobody near to raise the loser) and an unmarked hero beside
    // each pair: every fall after a hero's blow pays exactly that hero, and no unmarked hero ever pays one.
    let seeds: u64 = std::env::var("PVP_SEEDS").ok().and_then(|s| s.parse().ok()).unwrap_or(10);
    let (mut plunders, mut paid) = (0u64, 0u64);
    for seed in 0..seeds {
        let field = (seed % 6) as u8;
        let mut f = Field::open(field, 300 + seed, Config { monsters: 600, threads: 1 });
        let level = FIELDS[field as usize].bottom.max(MARK_LEVEL);
        let mut bots = Vec::new();
        let mut marked_of = Vec::new();
        for k in 0..8i32 {
            let (cx, cy) = (FIELD / 2 + ((k % 4) - 2) * px(1_800) + px(900), FIELD / 2 + (k / 4 * 2 - 1) * px(2_400));
            for j in 0..3i32 {
                let m = j < 2;
                let class = 1 + ((k * 3 + j) as u64 + seed) as u8 % 5;
                let id = f.join(&Sheet::bench(class, 0, level), &Outing { marked: m, ..Outing::new() }, cx + j * px(30), cy);
                f.hero_mut(id).coin = 200;
                bots.push(Bot::new(id, seed, Plan { every: 2, ..Plan::hunter(0) }));
                marked_of.push(m);
            }
        }
        for t in 0..1_500 {
            let downer: Vec<u16> = (0..f.heroes().len() as u16).map(|i| f.downed_by(i)).collect();
            let coin: Vec<u32> = f.heroes().iter().map(|h| h.coin).collect();
            let inputs: Vec<u16> = bots.iter_mut().map(|b| b.act(&f)).collect();
            f.step(&inputs);
            for e in f.events() {
                match *e {
                    Event::Fallen { hero, coin: lost } if downer[hero as usize] != NOBODY => {
                        let by = downer[hero as usize];
                        let p = f.events().iter().find_map(|e| if let Event::Plunder { hero: h, by, coin } = *e { (h == hero).then_some((by, coin)) } else { None });
                        assert_eq!(p, Some((by, lost)), "seed {seed} tick {t}: the fall of {hero} pays {by}");
                        assert!(f.heroes()[by as usize].coin >= coin[by as usize] + lost);
                        paid += lost as u64;
                    }
                    Event::Plunder { hero, .. } => {
                        plunders += 1;
                        assert!(marked_of[hero as usize], "seed {seed} tick {t}: unmarked {hero} lost her haul to a hero");
                    }
                    Event::Struck { hero, .. } | Event::Slain { hero, .. } => assert!(marked_of[hero as usize], "seed {seed}: unmarked {hero} struck"),
                    _ => {}
                }
            }
        }
    }
    println!("pvp haul property: {seeds} seeds, {plunders} plundered, {paid} coin to the heroes who downed them");
    assert!(plunders > 0, "some fall after a hero's blow");
}

#[test]
fn property_a_duel_never_strikes_a_third_party() {
    let seeds: u64 = std::env::var("PVP_SEEDS").ok().and_then(|s| s.parse().ok()).unwrap_or(18);
    let mut ended = 0;
    for seed in 0..seeds {
        let mut f = Field::open_duel(seed, Config { monsters: 64, threads: 1 });
        let [s0, s1] = f.yard_spots();
        let mut bots = Vec::new();
        let mut ids = Vec::new();
        for k in 0..5u32 {
            let class = 1 + ((k + seed as u32) % 5) as u8;
            let o = Outing { marked: k != 4, ..Outing::new() };
            let (x, y) = if k % 2 == 0 { s0 } else { s1 };
            let id = f.join(&Sheet::bench(class, 0, 30), &o, x, y + (k as i32 - 2) * px(30));
            ids.push(id);
            bots.push(Bot::new(id, seed, Plan { every: 2, ..Plan::hunter(0) }));
        }
        assert!(f.start_duel(ids[0], ids[1]));
        for t in 0..DUEL_TICKS + 5 {
            let inputs: Vec<u16> = bots.iter_mut().map(|b| b.act(&f)).collect();
            f.step(&inputs);
            for e in f.events() {
                if let Event::Struck { hero, by, .. } = *e {
                    let pair = [ids[0], ids[1]];
                    assert!(pair.contains(&hero) && pair.contains(&by), "seed {seed} tick {t}: {by} struck {hero} outside the duel");
                }
                assert!(!matches!(e, Event::Fallen { .. } | Event::Plunder { .. }), "seed {seed}: a duel costs no haul");
            }
            if f.duel().is_some_and(|d| d.state == DUEL_OVER) {
                ended += 1;
                break;
            }
        }
    }
    assert_eq!(ended, seeds, "every duel ends");
}

#[test]
fn same_hash_with_hunters_and_a_war_on_1_to_4_threads_and_a_follower() {
    for field in [2u8, 4] {
        let mut runs: Vec<Crowd> = (1..=4).map(|t| crowd(field, 3, 200, 6_000, t, 60)).collect();
        let mut follower: Option<Field> = None;
        let mut blows = 0;
        for t in 0..600 {
            let r0 = &mut runs[0];
            let inputs: Vec<u16> = r0.bots.iter_mut().map(|b| b.act(&r0.f)).collect();
            for r in runs.iter_mut() {
                r.f.step(&inputs);
            }
            if let Some(fl) = follower.as_mut() {
                fl.step(&inputs);
            }
            blows += runs[0].f.events().iter().filter(|e| matches!(e, Event::Struck { .. })).count();
            if t == 200 {
                follower = Some(Field::from_bytes(&runs[0].f.to_bytes(), 1).expect("loads"));
            }
            if t % 50 == 49 {
                let h = runs[0].f.hash();
                for (k, r) in runs.iter().enumerate().skip(1) {
                    assert_eq!(r.f.hash(), h, "field {field}: {} threads differ at tick {t}", k + 1);
                }
                if let Some(fl) = &follower {
                    assert_eq!(fl.hash(), h, "field {field}: the follower differs at tick {t}");
                }
            }
        }
        assert!(blows > 100, "field {field}: only {blows} blows");
    }
}

/// The budget: `heroes` bots, half of them marked hunters, among `monsters`, a tide on, `threads` threads; tick
/// mean and p99 (ms) over the last two thirds of `ticks`, the blows and the downs by heroes.
fn bench(field: u8, heroes: u32, monsters: u32, ticks: u32, threads: usize) -> (f64, f64, u64, u64, u32) {
    let mut f = Field::open(field, 900 + field as u64, Config { monsters, threads });
    f.set_clock(tide_start(field, 0) - 20);
    let level = FIELDS[field as usize].bottom.max(MARK_LEVEL);
    let mut bots = Vec::new();
    for i in 0..heroes {
        let class = 1 + (i % 5) as u8;
        let sheet = Sheet::bench(class, (i % 4) as u8, level);
        let n = i as i32;
        let (x, y) = (FIELD / 2 + (n % 40 - 20) * 20 * SUB, FIELD / 2 + (n / 40 - 12) * 20 * SUB);
        let m = i % 2 == 0;
        let id = f.join(&sheet, &Outing { marked: m, ..Outing::new() }, x, y);
        let mut plan = if m { Plan::hunter(500) } else { Plan::crowd(500) };
        plan.every = 8;
        bots.push(Bot::new(id, field as u64, plan));
    }
    let mut ms = Vec::new();
    let (mut blows, mut downs) = (0u64, 0u64);
    for t in 0..ticks {
        let inputs: Vec<u16> = bots.iter_mut().map(|b| b.act(&f)).collect();
        let at = std::time::Instant::now();
        f.step(&inputs);
        let el = at.elapsed().as_secs_f64() * 1000.0;
        if t >= ticks / 3 {
            ms.push(el);
        }
        for e in f.events() {
            match e {
                Event::Struck { .. } => blows += 1,
                Event::Slain { .. } => downs += 1,
                _ => {}
            }
        }
    }
    ms.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mean = ms.iter().sum::<f64>() / ms.len() as f64;
    (mean, ms[ms.len() * 99 / 100], blows, downs, f.monster_count())
}

/// The proof's bench: 1,000 heroes, half marked hunters, among 20,000 monsters, 4 threads, a tide on. The default
/// run is THE MOON MARSH (900 ticks); `PVP_BENCH_ALL=1` runs all six fields, `PVP_BENCH_TICKS` sets the length.
#[test]
fn bench_1000_heroes_half_marked_among_20000_monsters_inside_the_budget() {
    let ticks = std::env::var("PVP_BENCH_TICKS").ok().and_then(|s| s.parse().ok()).unwrap_or(900);
    let fields: Vec<u8> = if std::env::var("PVP_BENCH_ALL").is_ok() { (0..6).collect() } else { vec![2] };
    for field in fields {
        let (mean, p99, blows, downs, alive) = bench(field, 1_000, 20_000, ticks, 4);
        println!(
            "PVP bench {:<18} 1000x20000 (500 marked) 4 threads, tide: tick {mean:.2} ms mean, {p99:.2} ms p99, {blows} blows, {downs} downed by heroes, {alive} monsters at the end",
            FIELDS[field as usize].name
        );
        assert!(mean < 50.0 && p99 < 50.0, "over the 50 ms budget: {mean:.2} / {p99:.2}");
        assert!(blows > 1_000, "the marked fight: {blows} blows");
    }
}

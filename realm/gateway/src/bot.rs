//! A bot that plays through the wire like a client: gateway login, a hero, the town, a field ticket, the
//! lockstep field (its own copy of the simulation), banking at a waystone, and out again. `realm-soak` and
//! the proof test drive it.

use crate::client::GatewayClient;
use crate::proto::*;
use realm_core::tables::WAYSTONE_PX;
use realm_core::{Field, IN_INTERACT, SUB};
use realm_server::bots::{dir_toward, Bot};
use realm_server::client::LockstepClient;
use realm_server::MSG_BYE;
use std::net::UdpSocket;
use std::time::{Duration, Instant};

/// What a bot does in a field.
#[derive(Clone, Debug)]
pub struct PlayOpts {
    /// Ticks spent fighting before heading for a waystone.
    pub fight_ticks: u32,
    /// Give up (and just disconnect) after this many ticks.
    pub max_ticks: u32,
    /// Bank at the nearest waystone and leave by it. False: fight until `max_ticks`, then disconnect.
    pub bank: bool,
    /// After the first bank, stay and fight this many more ticks before leaving (0: leave at once).
    pub linger_ticks: u32,
    /// Disconnect abruptly (no BYE) once she has been banked, on the next tick.
    pub drop_after_bank: bool,
    pub seed: u64,
    /// When set, the bot disconnects as soon as it is true (the soak is ending).
    pub stop: Option<std::sync::Arc<std::sync::atomic::AtomicBool>>,
}

impl Default for PlayOpts {
    fn default() -> Self {
        PlayOpts { fight_ticks: 400, max_ticks: 20 * 240, bank: true, linger_ticks: 0, drop_after_bank: false, seed: 1, stop: None }
    }
}

/// What one outing came to, as the gateway told the bot (its Outing pushes, summed).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Outcome {
    pub coin: u64,
    pub xp: u64,
    pub levels: u16,
    pub potions: u32,
    /// Why the hero left (the Outing push's code), 255 if she was still there when the bot stopped.
    pub left: u8,
    pub ticks: u32,
    pub banked: bool,
    pub joined: bool,
    /// Times her copy closed and she was moved to another.
    pub moves: u32,
}

fn nearest_waystone(f: &Field, x: i32, y: i32) -> (i32, i32) {
    let t = f.terrain();
    t.waystones.iter().copied().min_by_key(|&(wx, wy)| (wx as i64 - x as i64).pow(2) + (wy as i64 - y as i64).pow(2)).unwrap_or(t.gate)
}

/// Plays one outing with a ticket the gateway gave. `gw` is the same connection that asked for the ticket (its
/// Outing pushes are read here).
pub fn play_field(gw: &mut GatewayClient, host: &str, port: u16, ticket: u64, opts: &PlayOpts) -> Result<Outcome, String> {
    let host = if host.is_empty() { gw.peer_ip.clone() } else { host.to_string() };
    let open = |port: u16| -> Result<UdpSocket, String> {
        let sock = UdpSocket::bind("0.0.0.0:0").map_err(|e| e.to_string())?;
        sock.connect((host.as_str(), port)).map_err(|e| e.to_string())?;
        sock.set_nonblocking(true).map_err(|e| e.to_string())?;
        Ok(sock)
    };
    let mut sock = open(port)?;
    let mut c = LockstepClient::with_ticket(ticket, 1);
    let mut moves = 0u32;
    let mut out = Outcome { left: 255, ..Outcome::default() };
    let mut bot: Option<Bot> = None;
    let start = Instant::now();
    let period = Duration::from_millis(50);
    let mut next = start;
    let mut buf = [0u8; 2048];
    let (mut joined_at, mut banked_at, mut last_pos, mut still, mut wiggle) = (0u32, None::<u32>, (0, 0), 0u32, 0u32);
    let mut round = 0u64;
    let mut held_since: Option<u32> = None;
    // A host that stops sending ticks (gone without a word) ends the outing instead of hanging here.
    let (mut seen_tick, mut seen_at) = (u32::MAX, Instant::now());
    let result = loop {
        let now = Instant::now();
        if now < next {
            std::thread::sleep((next - now).min(Duration::from_millis(5)));
            continue;
        }
        next += period;
        round += 1;
        if !c.welcomed() && round % 20 == 1 {
            let _ = sock.send(&c.hello());
        }
        while let Ok(n) = sock.recv(&mut buf) {
            c.receive(&buf[..n]);
        }
        c.apply();
        let mut word = 0u16;
        let mut go: Option<u16> = None;
        if let (Some(f), Some(id)) = (c.field(), c.hero()) {
            let tick = f.tick();
            if tick != seen_tick {
                (seen_tick, seen_at) = (tick, Instant::now());
            } else if gw.pushes.iter().any(|r| matches!(r, Resp::Outing { left, .. } if *left != 255)) {
                // The gateway ended her outing (the host dropped her, or her copy died): what she has is told below.
                break Ok(());
            } else if seen_at.elapsed() > STALL && !gw.pushes.iter().any(|r| moved_port(r, ticket).is_some()) {
                break Err(format!("the field stopped at tick {tick} (moves {moves}, joined {}, port {}, {:?})", out.joined, sock.peer_addr().map_or(0, |a| a.port()), c.stats));
            }
            if !out.joined && c.hero_player().is_some() {
                out.joined = true;
                joined_at = tick;
                bot = Some(Bot::new(id, false, opts.seed));
            }
            match c.hero_player() {
                Some(p) => {
                    let age = tick - joined_at;
                    out.ticks = age;
                    let go_bank = opts.bank && (age >= opts.fight_ticks || banked_at.is_some());
                    if go_bank {
                        let (wx, wy) = nearest_waystone(f, p.x, p.y);
                        let (dx, dy) = (wx - p.x, wy - p.y);
                        let near = (dx as i64).pow(2) + (dy as i64).pow(2) <= ((WAYSTONE_PX - 12) as i64 * SUB as i64).pow(2);
                        if let Some(b) = banked_at {
                            // Lingering after the bank: fight on, then hold interact again to leave.
                            if tick - b < opts.linger_ticks {
                                if let Some(bt) = bot.as_mut() {
                                    bt.decide(f);
                                    word = bt.input;
                                }
                            } else {
                                word = if near { hold(&mut bot, f) } else { dir_toward(dx, dy) as u16 };
                            }
                        } else if near {
                            word = hold(&mut bot, f);
                            held_since.get_or_insert(tick);
                        } else {
                            word = dir_toward(dx, dy) as u16;
                            if (p.x, p.y) == last_pos {
                                still += 1;
                            } else {
                                still = 0;
                            }
                            if still > 30 {
                                wiggle = 20;
                                still = 0;
                            }
                            if wiggle > 0 {
                                wiggle -= 1;
                                word = ((tick / 5) % 8 + 1) as u16;
                            }
                        }
                        last_pos = (p.x, p.y);
                        if banked_at.is_none() && p.banked {
                            banked_at = Some(tick);
                        }
                    } else if let Some(bt) = bot.as_mut() {
                        bt.decide(f);
                        word = bt.input;
                    }
                    if opts.drop_after_bank && p.banked {
                        break Ok(());
                    }
                }
                None if out.joined => {
                    // She is gone from the field: through the gate or a waystone, or her copy is closing and she
                    // is moved to another (the gateway says where: HELLO there with the same ticket).
                    match wait_moved(gw, ticket)? {
                        Some(p) => go = Some(p),
                        None => break Ok(()),
                    }
                }
                None => {}
            }
            if age_over(tick, joined_at, out.joined, opts.max_ticks) {
                break Ok(());
            }
        }
        if c.welcomed() {
            let d = c.input_word(word);
            let _ = sock.send(&d);
        }
        if opts.stop.as_ref().is_some_and(|s| s.load(std::sync::atomic::Ordering::Relaxed)) {
            break Ok(());
        }
        if round > 20 * 60 && !out.joined {
            break Err("never joined the field".to_string());
        }
        let _ = gw.poll(Duration::from_millis(0));
        // The Moved push can come before the last ticks of the old copy do (or instead of them, when it closes at
        // once): she is out of it either way.
        if go.is_none() {
            if let Some(i) = gw.pushes.iter().position(|r| moved_port(r, ticket).is_some()) {
                go = gw.pushes.remove(i).and_then(|r| moved_port(&r, ticket));
            }
        }
        if let Some(p) = go {
            let _ = sock.send(&[MSG_BYE]);
            sock = open(p)?;
            c = LockstepClient::with_ticket(ticket, 1);
            seen_at = Instant::now();
            out.joined = false;
            bot = None;
            moves += 1;
            round = 0;
        }
    };
    let abrupt = opts.drop_after_bank && out.joined;
    if !abrupt {
        let _ = sock.send(&[MSG_BYE]);
    }
    drop(sock);
    out.moves = moves;
    result?;
    // The result of the outing arrives from the gateway once the store has it.
    let wait = if abrupt { Duration::from_secs(12) } else { Duration::from_secs(8) };
    let end = Instant::now() + wait;
    loop {
        let mut done = false;
        while let Some(i) = gw.pushes.iter().position(|r| matches!(r, Resp::Outing { .. })) {
            if let Some(Resp::Outing { coin, xp, levels, potions, left, .. }) = gw.pushes.remove(i) {
                out.coin = coin;
                out.xp = xp;
                out.levels = levels;
                out.potions = potions;
                out.left = left;
                out.banked |= coin > 0 || banked_at.is_some();
                done |= left != 255;
            }
        }
        if done || Instant::now() > end {
            break;
        }
        gw.poll(Duration::from_millis(100)).map_err(|e| e.to_string())?;
    }
    Ok(out)
}

/// Standing at a waystone holding interact: any hit breaks the hold, so she fights where she stands (skills and
/// potions from the bot's own choice, no walking).
fn hold(bot: &mut Option<Bot>, f: &Field) -> u16 {
    match bot.as_mut() {
        Some(b) => {
            b.decide(f);
            (b.input & !realm_core::IN_DIR) | IN_INTERACT | realm_core::IN_SKILL1 | realm_core::IN_SKILL2
        }
        None => IN_INTERACT,
    }
}

/// A `Moved` push for this ticket, waiting a little for it: the new copy's port.
fn wait_moved(gw: &mut GatewayClient, ticket: u64) -> Result<Option<u16>, String> {
    gw.wait_push(Duration::from_millis(1_500), |r| moved_port(r, ticket)).map_err(|e| e.to_string())
}

fn moved_port(r: &Resp, ticket: u64) -> Option<u16> {
    match r {
        Resp::WorldPush(crate::world::wire::WResp::Moved { ticket: t, port, .. }) if *t == ticket => Some(*port),
        _ => None,
    }
}

/// How long a field may go without a tick before the bot gives up on it.
const STALL: Duration = Duration::from_secs(15);

fn age_over(tick: u32, joined_at: u32, joined: bool, max: u32) -> bool {
    joined && tick - joined_at > max
}

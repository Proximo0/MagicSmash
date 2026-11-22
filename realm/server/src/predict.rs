//! The lockstep player's own hero, predicted so movement feels instant.
//!
//! Every input the player sends gets a seq and moves the predicted hero one tick at once. When the server's
//! ticks arrive the follower knows where the hero really is at the confirmed tick and which seq was in force
//! there; the prediction is that position with every later input replayed on top. The caller hands in the
//! walking step (`Field::walk` of its follower field: the core's own movement, walls and speed included), so
//! the replay is exact unless the server used the inputs differently (one arrived late, two in one tick),
//! the hero's speed changed since the confirmed tick, a skill moved her, or she went down or left.
//!
//! The hero is drawn at `shown`, which follows the prediction: each tick it takes the newest input's own step
//! plus at most `CORRECTION_PER_TICK` of any remaining error, so a misprediction fades out over a few ticks
//! instead of jumping. An error larger than `SNAP_PX` (a respawn) is taken at once.

use realm_core::SUB;
use std::collections::VecDeque;

/// The most the shown hero moves beyond its own step in one tick to close a prediction error (1 px).
pub const CORRECTION_PER_TICK: i32 = SUB;
/// An error farther than this (px) is not smoothed: the shown hero jumps (a respawn, a long stall).
pub const SNAP_PX: i32 = 64;
/// Inputs kept while unconfirmed (12.8 s at 20 a second); older ones are dropped as the server ignores them.
const PENDING_MAX: usize = 256;

/// `(dx, dy)` shortened to at most `max` long (sub units, whole numbers).
fn clamp_len(dx: i32, dy: i32, max: i32) -> (i32, i32) {
    let len = ((dx as i64 * dx as i64 + dy as i64 * dy as i64) as u64).isqrt() as i64;
    if len <= max as i64 {
        (dx, dy)
    } else {
        ((dx as i64 * max as i64 / len) as i32, (dy as i64 * max as i64 / len) as i32)
    }
}

/// An input sent and not yet confirmed, with where it was predicted to put the hero.
#[derive(Clone, Copy, Debug)]
struct Pending {
    seq: u32,
    input: u16,
    x: i32,
    y: i32,
}

#[derive(Debug, Default)]
pub struct Predictor {
    pending: VecDeque<Pending>,
    last_seq: u32,
    /// The prediction: the confirmed hero with the pending inputs replayed (none before the first confirm).
    raw: Option<(i32, i32)>,
    /// Where the hero is drawn after the latest input.
    shown: Option<(i32, i32)>,
    /// Whether the hero was alive at the last confirmed tick (a dead hero does not move).
    alive: bool,
    /// Confirmed ticks whose hero position differed from what had been predicted for that seq.
    pub mispredicts: u64,
    /// Confirmed ticks compared with a prediction.
    pub confirms: u64,
}

impl Predictor {
    /// The player sends `input` for its next tick: returns its seq and moves the prediction one step.
    /// `step(x, y, input)` is one tick of the hero's walking.
    pub fn push(&mut self, input: u16, step: impl Fn(i32, i32, u16) -> (i32, i32)) -> u32 {
        self.last_seq += 1;
        let seq = self.last_seq;
        let Some((rx, ry)) = self.raw else {
            return seq;
        };
        let (nx, ny) = if self.alive { step(rx, ry, input) } else { (rx, ry) };
        self.raw = Some((nx, ny));
        self.pending.push_back(Pending { seq, input, x: nx, y: ny });
        while self.pending.len() > PENDING_MAX {
            self.pending.pop_front();
        }
        self.shown = Some(match self.shown {
            Some((sx, sy)) => {
                let (ax, ay) = if self.alive { step(sx, sy, input) } else { (sx, sy) };
                follow(ax, ay, nx, ny)
            }
            None => (nx, ny),
        });
        seq
    }

    /// The follower reached a tick where the hero is at `(x, y)` (`alive` or not) and the input with `seq`
    /// was in force: drops the inputs the server has used and replays the rest from there with `step`.
    pub fn confirm(&mut self, x: i32, y: i32, alive: bool, seq: u32, step: impl Fn(i32, i32, u16) -> (i32, i32)) {
        while self.pending.front().is_some_and(|p| p.seq < seq) {
            self.pending.pop_front();
        }
        if let Some(p) = self.pending.front().filter(|p| p.seq == seq) {
            self.confirms += 1;
            if (p.x, p.y) != (x, y) {
                self.mispredicts += 1;
            }
            self.pending.pop_front();
        }
        self.alive = alive;
        let (mut px, mut py) = (x, y);
        if alive {
            for p in &mut self.pending {
                (px, py) = step(px, py, p.input);
                (p.x, p.y) = (px, py);
            }
        } else {
            for p in &mut self.pending {
                (p.x, p.y) = (x, y);
            }
        }
        self.raw = Some((px, py));
        if self.shown.is_none() {
            self.shown = self.raw;
        }
    }

    /// The prediction (sub units), once the hero has been confirmed.
    pub fn predicted(&self) -> Option<(i32, i32)> {
        self.raw
    }

    /// Where to draw the hero after the latest input (sub units).
    pub fn shown(&self) -> Option<(i32, i32)> {
        self.shown
    }

    /// Inputs sent that the server has not confirmed yet.
    pub fn unconfirmed(&self) -> usize {
        self.pending.len()
    }
}

/// The shown hero after its own step (`ax`, `ay`) moved toward the prediction (`tx`, `ty`).
fn follow(ax: i32, ay: i32, tx: i32, ty: i32) -> (i32, i32) {
    let (ex, ey) = (tx - ax, ty - ay);
    let far = SNAP_PX * SUB;
    if (ex as i64).pow(2) + (ey as i64).pow(2) > (far as i64).pow(2) {
        return (tx, ty);
    }
    let (cx, cy) = clamp_len(ex, ey, CORRECTION_PER_TICK);
    (ax + cx, ay + cy)
}

#[cfg(test)]
mod tests {
    use super::*;
    use realm_core::IN_SKILL1;
    use realm_core::{Config, Field, Outing, Sheet, FIELD};

    /// A field with no monsters, so nothing but inputs moves or hurts the hero.
    fn quiet_field() -> (Field, u16) {
        let mut f = Field::new(3, Config { monsters: 0, threads: 1 });
        let id = f.join(&Sheet::bench(1, 0, 1), &Outing::new(), FIELD / 2, FIELD / 2);
        // A tick derives her speed, as the first tick a client applies does.
        f.step::<u16>(&[]);
        (f, id)
    }

    fn walk(t: u32) -> u16 {
        let dir = 1 + (t / 7 % 8) as u16;
        if t % 50 == 0 { dir | IN_SKILL1 } else { dir }
    }

    /// The walking step the client hands the predictor.
    fn step_of(f: &Field, id: u16) -> impl Fn(i32, i32, u16) -> (i32, i32) + '_ {
        move |x, y, input| f.walk(id, x, y, input)
    }

    fn inputs_for(id: u16, input: u16) -> Vec<u16> {
        let mut inputs = vec![0u16; id as usize + 1];
        inputs[id as usize] = input;
        inputs
    }

    /// The server uses each input `lag` ticks after it was sent; returns the hero at every confirm.
    fn run(lag: usize, ticks: u32, late: Option<u32>) -> (Predictor, Vec<((i32, i32), (i32, i32))>) {
        let (mut f, id) = quiet_field();
        let mut pred = Predictor::default();
        let mut sent: VecDeque<(u32, u16)> = VecDeque::new();
        let mut in_force = (0u32, 0u16);
        let mut trail = Vec::new();
        pred.confirm(f.players()[id as usize].x, f.players()[id as usize].y, true, 0, step_of(&f, id));
        for t in 1..=ticks {
            let input = walk(t);
            let seq = pred.push(input, step_of(&f, id));
            sent.push_back((seq, input));
            // The input `late` reaches the server one tick after the next one: the server skips it.
            if sent.len() > lag && Some(sent[0].0) != late {
                in_force = sent.pop_front().unwrap_or(in_force);
            } else if sent.len() > lag {
                sent.pop_front();
            }
            f.step(&inputs_for(id, in_force.1));
            let p = &f.players()[id as usize];
            let before = pred.shown().unwrap_or_default();
            pred.confirm(p.x, p.y, p.alive(), in_force.0, step_of(&f, id));
            trail.push((before, pred.shown().unwrap_or_default()));
        }
        (pred, trail)
    }

    #[test]
    fn the_step_matches_the_core() {
        let (mut f, id) = quiet_field();
        let (mut x, mut y) = (f.players()[id as usize].x, f.players()[id as usize].y);
        for t in 0..400 {
            let input = walk(t);
            (x, y) = f.walk(id, x, y, input);
            f.step(&inputs_for(id, input));
            assert_eq!((x, y), (f.players()[id as usize].x, f.players()[id as usize].y), "tick {t}");
        }
    }

    #[test]
    fn the_step_never_enters_a_wall() {
        let (f, id) = quiet_field();
        for dir in 1..=8u16 {
            let (mut x, mut y) = (f.players()[id as usize].x, f.players()[id as usize].y);
            for _ in 0..4000 {
                (x, y) = f.walk(id, x, y, dir);
                assert!((0..FIELD).contains(&x) && (0..FIELD).contains(&y) && !f.terrain().wall(x, y), "dir {dir}: ({x}, {y})");
            }
        }
    }

    #[test]
    fn prediction_equals_the_confirmed_result_when_nothing_interferes() {
        for lag in [0, 1, 4, 9] {
            let (pred, trail) = run(lag, 300, None);
            assert_eq!(pred.mispredicts, 0, "lag {lag}");
            assert!(pred.confirms >= 290 - lag as u64, "lag {lag}: {} confirms", pred.confirms);
            // With nothing to correct the shown hero is the prediction every tick.
            assert_eq!(pred.shown(), pred.predicted());
            assert!(trail.iter().all(|(a, b)| a == b), "lag {lag}: a confirm moved the shown hero");
            assert_eq!(pred.unconfirmed(), lag);
        }
    }

    #[test]
    fn a_correction_converges_without_a_visible_jump() {
        // One input the server never uses: the prediction is a step off until the shown hero catches up.
        let lag = 4;
        let (mut f, id) = quiet_field();
        let mut pred = Predictor::default();
        pred.confirm(f.players()[id as usize].x, f.players()[id as usize].y, true, 0, step_of(&f, id));
        let mut sent: VecDeque<(u32, u16)> = VecDeque::new();
        let mut in_force = (0u32, 0u16);
        let mut shown = pred.shown().unwrap_or_default();
        let mut wrong_since: Option<u32> = None;
        let mut longest = 0;
        for t in 1..=200u32 {
            let input = walk(t);
            let seq = pred.push(input, step_of(&f, id));
            // The shown hero moved by its own step plus at most the correction.
            let now = pred.shown().unwrap_or_default();
            let own = step_of(&f, id)(shown.0, shown.1, input);
            let extra = ((now.0 - own.0) as i64).pow(2) + ((now.1 - own.1) as i64).pow(2);
            assert!(extra <= (CORRECTION_PER_TICK as i64).pow(2), "tick {t}: jumped {extra}");
            sent.push_back((seq, input));
            if sent.len() > lag {
                let s = sent.pop_front().unwrap_or(in_force);
                if s.0 != 60 {
                    in_force = s;
                }
            }
            f.step(&inputs_for(id, in_force.1));
            let p = &f.players()[id as usize];
            pred.confirm(p.x, p.y, true, in_force.0, step_of(&f, id));
            shown = pred.shown().unwrap_or_default();
            if shown != pred.predicted().unwrap_or_default() {
                let since = *wrong_since.get_or_insert(t);
                longest = longest.max(t - since + 1);
            } else {
                wrong_since = None;
            }
        }
        assert!(pred.mispredicts >= 1, "the skipped input was not noticed");
        assert_eq!(pred.shown(), pred.predicted(), "never converged");
        // One step of error is 3 px; at 1 px a tick it is gone in a few ticks.
        assert!(longest >= 1 && longest <= 6, "converged in {longest} ticks");
    }

    #[test]
    fn a_far_correction_jumps_at_once() {
        let mut pred = Predictor::default();
        let east = |x: i32, y: i32, input: u16| (x + 3 * SUB * (input != 0) as i32, y);
        pred.confirm(FIELD / 2, FIELD / 2, true, 0, east);
        pred.push(1, east);
        pred.confirm(FIELD / 4, FIELD / 4, true, 1, east);
        pred.push(0, east);
        assert_eq!(pred.shown(), Some((FIELD / 4, FIELD / 4)));
    }

    #[test]
    fn a_dead_hero_is_not_moved_by_inputs() {
        let mut pred = Predictor::default();
        let east = |x: i32, y: i32, _: u16| (x + 3 * SUB, y);
        pred.confirm(FIELD / 2, FIELD / 2, false, 0, east);
        for _ in 0..5 {
            pred.push(3, east);
        }
        assert_eq!(pred.predicted(), Some((FIELD / 2, FIELD / 2)));
        assert_eq!(pred.shown(), Some((FIELD / 2, FIELD / 2)));
    }

    #[test]
    fn a_late_input_is_a_misprediction_that_heals() {
        let (pred, _) = run(3, 120, Some(40));
        assert!(pred.mispredicts >= 1);
        assert_eq!(pred.shown(), pred.predicted());
    }
}

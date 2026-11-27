//! The deck (rules section 5): draws from the field's seed, the hero's id and her draw count; a queue of
//! nine offers; picks by input; and what the copies she picked add up to.

use crate::{Field, SUB};
use crate::events::Event;
use crate::tables::*;
use crate::util::{mix, pct};

/// Sums one number over the copies of every card.
pub fn card_sum(copies: &[u8; NCARDS + 1], f: impl Fn(CardFx) -> i64) -> i64 {
    let mut s = 0;
    for (id, &n) in copies.iter().enumerate().skip(1) {
        if n > 0 {
            s += f(CARDS[id].fx) * n as i64;
        }
    }
    s
}

/// What the picked cards add up to.
#[derive(Clone, Copy, Debug, Default)]
pub struct CardMods {
    pub dmg_pct: i32,
    pub as_pct: i32,
    pub move_pct: i32,
    pub regen: u32,
    pub size_pct: u32,
    pub reach_pct: u32,
    pub cdr_pct: u32,
    pub ult_cdr_pct: u32,
    pub coin_pct: u32,
    pub xp_pct: u32,
    pub taken_pct: i32,
    pub reflect: u32,
    pub every_nth: u32,
    pub nth_extra: u32,
    pub execute_pct: u32,
    pub execute_under: u32,
    pub crit: u32,
    pub lifesteal: u32,
    pub lifesteal_cap: u32,
    pub elite_pct: u32,
    pub raise_pct: u32,
    pub rise_pct: u32,
    pub fool: u8,
    pub push_px: i32,
    pub cups: u32,
    pub alone_pct: i32,
    pub company_pct: i32,
    pub company_max: i32,
    pub company_copies: i32,
    pub burst_px: i32,
    pub burst_dmg: u32,
    pub keep: u32,
}

/// Weapons THE FOOL gives a pierce or a target to; any other weapon gets its damage.
pub fn fool_targets(shape: Shape) -> bool {
    matches!(shape, Shape::Bolt { .. } | Shape::Drop { .. })
}

pub fn card_mods(copies: &[u8; NCARDS + 1], weapon: Shape, has_job: bool, tide: bool) -> CardMods {
    let mut m = CardMods::default();
    for (id, &n) in copies.iter().enumerate().skip(1) {
        if n == 0 {
            continue;
        }
        let (n32, ni) = (n as u32, n as i32);
        match CARDS[id].fx {
            CardFx::Damage(p) => m.dmg_pct += p * ni,
            CardFx::Move(p) => m.move_pct += p * ni,
            CardFx::AttackSpeed(p) => m.as_pct += p * ni,
            CardFx::Health(_) => {}
            CardFx::Regen(t) => m.regen += t * n32,
            CardFx::Size(p) => m.size_pct += p * n32,
            CardFx::Reach(p) => m.reach_pct += p * n32,
            CardFx::Cooldown(p) => m.cdr_pct += p * n32,
            CardFx::Coin(p) => m.coin_pct += p * n32,
            CardFx::Xp(p) => m.xp_pct += p * n32,
            CardFx::Taken(p) => m.taken_pct += p * ni,
            CardFx::Reflect(p) => m.reflect += p * n32,
            CardFx::EveryNth(k) => {
                m.every_nth = k;
                m.nth_extra += n32;
            }
            CardFx::Execute { pct, under } => {
                m.execute_pct += pct * n32;
                m.execute_under = under;
            }
            CardFx::Devil { dmg, taken } => {
                m.dmg_pct += dmg * ni;
                m.taken_pct += taken * ni;
            }
            CardFx::Crit(p) => m.crit += p * n32,
            // THE SUN is a group effect, read from the allies around her in `mods_of`.
            CardFx::Sun { .. } => {}
            CardFx::Lifesteal { pct, cap } => {
                m.lifesteal += pct * n32;
                m.lifesteal_cap += cap * n32;
            }
            CardFx::Elite(p) => m.elite_pct += p * n32,
            CardFx::Raiser { raise, rise } => {
                m.raise_pct += raise * n32;
                m.rise_pct += rise * n32;
            }
            CardFx::Tide(p) => {
                if tide {
                    m.dmg_pct += p * ni;
                }
            }
            CardFx::Fool(p) => {
                if fool_targets(weapon) {
                    m.fool += n;
                } else {
                    m.dmg_pct += p * ni;
                }
            }
            CardFx::Push(p) => m.push_px += p * ni,
            CardFx::Cups(p) => m.cups += p * n32,
            CardFx::Wands { cdr, dmg } => {
                if has_job {
                    m.ult_cdr_pct += cdr * n32;
                } else {
                    m.dmg_pct += dmg * ni;
                }
            }
            CardFx::Alone { pct, .. } => m.alone_pct += pct * ni,
            CardFx::Company { pct, max, .. } => {
                m.company_pct = pct;
                m.company_max = max;
                m.company_copies = ni;
            }
            CardFx::Burst { px, dmg } => {
                m.burst_px = px;
                m.burst_dmg += dmg * n32;
            }
            CardFx::Keep(t) => m.keep += t * n32,
            CardFx::KillRush => {}
        }
    }
    m
}

/// Rolls one offer: up to `size` different deck cards not yet at five copies, from the field's seed,
/// the hero's id and her draw count.
pub fn roll(seed: u64, hero: u16, draw: u32, deck: &[u8], copies: &[u8; NCARDS + 1], size: u8) -> ([u8; DRAW_MAX as usize], u8) {
    let mut pool: Vec<u8> = Vec::with_capacity(DECK_SIZE);
    for &c in deck.iter().take(DECK_SIZE) {
        if (1..=NCARDS as u8).contains(&c) && copies[c as usize] < MAX_COPIES && !pool.contains(&c) {
            pool.push(c);
        }
    }
    let mut out = [0u8; DRAW_MAX as usize];
    let n = (size.min(DRAW_MAX) as usize).min(pool.len());
    for k in 0..n {
        let r = mix(seed, hero as u64, draw as u64, k as u64);
        let j = k + (r % (pool.len() - k) as u64) as usize;
        pool.swap(k, j);
        out[k] = pool[k];
    }
    (out, n as u8)
}

impl Field {
    /// Rolls owed draws into the queue while it has room (an unpicked draw is never lost).
    pub(crate) fn fill_offers(&mut self, i: usize) {
        let seed = self.seed;
        let h = &mut self.heroes[i];
        let size = match h.class_row().passive.draw_size {
            0 => DRAW_SIZE,
            n => n,
        };
        while h.owed > 0 && h.offers.len() < DRAW_QUEUE {
            h.owed -= 1;
            let (cards, n) = roll(seed, i as u16, h.draws, &h.sheet.deck, &h.copies, size);
            h.draws += 1;
            if n == 0 {
                // Every deck card is at five copies: nothing to offer.
                continue;
            }
            h.offers.push(cards);
            self.events.push(Event::Draw { hero: i as u16, cards, n });
        }
    }

    /// One draw for hero `i`, through the queue as a level's draw goes (owed, then rolled while the queue has
    /// room). The one door for draws that do not come from field XP: shrines (rules 6, quiet zones) and any later source.
    pub(crate) fn grant_draw(&mut self, i: usize) {
        let h = &mut self.heroes[i];
        if !h.present {
            return;
        }
        h.owed = h.owed.saturating_add(1);
        self.fill_offers(i);
    }

    /// A shrine within `SHRINE_PX` of an up hero in a quiet zone that she has not touched this outing: one draw.
    pub(crate) fn touch_shrines(&mut self, i: usize) {
        let h = &self.heroes[i];
        if !h.alive() || self.terrain.at(h.x, h.y) & QUIET == 0 {
            return;
        }
        let r = (SHRINE_PX * SUB) as i64;
        let (x, y, done) = (h.x, h.y, h.shrines);
        let hit = self.terrain.shrines().find(|&(k, (sx, sy))| (k as usize) < SHRINES_MAX && done & (1 << k) == 0 && crate::util::d2(x, y, sx, sy) <= r * r);
        if let Some((k, _)) = hit {
            self.heroes[i].shrines |= 1 << k;
            self.grant_draw(i);
        }
    }

    /// Field XP: levels up (LEVEL) and queues a draw per level (DRAW).
    pub(crate) fn gain_field_xp(&mut self, i: usize, xp: u32) {
        let h = &mut self.heroes[i];
        h.xp += xp;
        let mut up = false;
        while h.xp >= FIELD_XP_PER_LEVEL * h.level as u32 {
            h.xp -= FIELD_XP_PER_LEVEL * h.level as u32;
            h.level += 1;
            h.owed += 1;
            up = true;
        }
        if up {
            let level = h.level;
            self.events.push(Event::Level { hero: i as u16, level });
            self.fill_offers(i);
        }
    }
}

/// Takes card `k` (1-based) of the oldest offer.
pub fn pick(f: &mut Field, i: usize, k: u8) {
    let h = &mut f.heroes[i];
    let Some(offer) = h.offers.first().copied() else {
        return;
    };
    if k == 0 || k > DRAW_MAX {
        return;
    }
    let card = offer[(k - 1) as usize];
    if card == 0 || h.copies[card as usize] >= MAX_COPIES {
        return;
    }
    h.offers.remove(0);
    h.copies[card as usize] += 1;
    let copies = h.copies[card as usize];
    if let CardFx::Health(p) = CARDS[card as usize].fx {
        let old = h.max_health;
        h.max_health = h.compute_max_health();
        let gain = pct(old, p as i64).max(h.max_health.saturating_sub(old));
        h.health = (h.health + gain).min(h.max_health);
    }
    if let CardFx::Cups(_) = CARDS[card as usize].fx {
        for slot in h.belt.iter_mut() {
            if slot.0 != P_NONE && slot.0 != P_PHOENIX {
                slot.1 = slot.1.saturating_add(1);
            }
        }
    }
    f.events.push(Event::Pick { hero: i as u16, card, copies });
    f.fill_offers(i);
}

//! A saved hero turned into the `Sheet` the field needs (rules section 2), and class XP into class levels.

use realm_core::tables::{BELT, CLASS_XP, CLASS_LEVEL_MAX, DECK_SIZE, NONE, P_NONE, POTIONS, CLASSES, RACES};
use realm_core::Sheet;
use realm_store::{Hero, Owner, PlaceKind, Result, StackClass, StackKind, Store};

/// A rune's stat points by grade 1..3 when socketed (gear lines carry their own points).
pub const RUNE_POINTS: [u16; 4] = [0, 2, 4, 6];
/// The store numbers deck cards from 0 and the core from 1 (THE FOOL, card 0 of the store, is id 1 of the core's
/// table of 30): a store card `c` is the core's `c + CARD_BASE`.
pub const CARD_BASE: u8 = 1;

/// The sheet of a hero: class, job, race and level from her row, spent points as points, gear from what she
/// wears (the six stats from item lines, plus a socketed rune's points by grade), the weapon level from her
/// best worn item, her deck, and her belt filled from her bag (a slot is empty when the bag holds none).
pub fn sheet_of(store: &dyn Store, h: &Hero) -> Result<Sheet> {
    let p = &h.progress;
    let mut gear = [0u16; 6];
    let mut gear_level = 0u16;
    for it in store.items_at(PlaceKind::Worn, h.id)? {
        gear_level = gear_level.max(it.spec.item_level);
        for &(stat, pts) in &it.spec.lines {
            if let Some(g) = gear.get_mut(stat as usize) {
                *g = g.saturating_add(pts);
            }
        }
        for s in it.socketed.iter().flatten() {
            if s.class() == Some(StackClass::Rune) {
                let (stat, grade) = ((s.0 - 2000) / 10, (s.0 - 2000) % 10);
                if let (Some(g), Some(&pts)) = (gear.get_mut(stat as usize), RUNE_POINTS.get(grade as usize)) {
                    *g = g.saturating_add(pts);
                }
            }
        }
    }
    let mut points = [0u16; 6];
    points.copy_from_slice(&p.stats);
    let bag = store.stacks(Owner::bag(h.id))?;
    let mut belt = [(P_NONE, 0u8); BELT];
    for (slot, &kind) in p.belt.iter().enumerate() {
        let k = StackKind(kind);
        if kind == 0 || k.class() != Some(StackClass::Potion) {
            continue;
        }
        let pid = (kind - 100) as usize;
        let Some(row) = POTIONS.get(pid) else { continue };
        let have = bag.iter().find(|(sk, _)| *sk == k).map_or(0, |(_, n)| *n);
        let charges = have.min(row.carried as u64) as u8;
        if charges > 0 {
            belt[slot] = (pid as u8, charges);
        }
    }
    let level = p.class_level.clamp(1, CLASS_LEVEL_MAX as u16) as u8;
    Ok(Sheet {
        class: h.class.min(CLASSES.len() as u8 - 1),
        job: if (p.job as usize) < realm_core::tables::JOBS.len() { p.job } else { NONE },
        race: h.race % RACES.len() as u8,
        class_level: level,
        points,
        gear,
        gear_level: gear_level.clamp(1, CLASS_LEVEL_MAX as u16) as u8,
        deck: p.deck.iter().map(|&c| (c as u8).saturating_add(CARD_BASE)).take(DECK_SIZE).collect(),
        belt,
        look: h.look,
    })
}

/// Total class XP needed to reach `level` (1 needs none). `CLASS_XP[L - 1]` is the step from L to L + 1.
pub fn xp_to_reach(level: u16) -> u64 {
    CLASS_XP.iter().take(level.saturating_sub(1) as usize).map(|&x| x as u64).sum()
}

/// The class level a total of class XP is worth (at most 60).
pub fn level_for_xp(total: u64) -> u16 {
    let mut level = 1u16;
    let mut need = 0u64;
    while (level as usize) <= CLASS_XP.len() && level < CLASS_LEVEL_MAX as u16 {
        need += CLASS_XP[level as usize - 1] as u64;
        if total < need {
            break;
        }
        level += 1;
    }
    level
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn class_levels_follow_the_xp_table() {
        assert_eq!(level_for_xp(0), 1);
        assert_eq!(level_for_xp(CLASS_XP[0] as u64 - 1), 1);
        assert_eq!(level_for_xp(CLASS_XP[0] as u64), 2);
        for l in 1..=60u16 {
            assert_eq!(level_for_xp(xp_to_reach(l)), l, "level {l}");
            if l > 1 {
                assert_eq!(level_for_xp(xp_to_reach(l) - 1), l - 1);
            }
        }
        assert_eq!(level_for_xp(u64::MAX / 2), 60, "level 60 is the top");
    }
}

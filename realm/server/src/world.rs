//! What a player sees of the realm's clock and of the field she stands in: the tide (countdown, altars), the
//! boss up now (name, health, place), the next field boss and the world boss's next ride. All of it is read from
//! the simulation (the lockstep follower has the same field) or from the realm clock with the core's schedule
//! functions, so the server, the game window and the town show the same numbers. The game window fills its
//! `world` dictionary from `world_view` (`world["boss"]`, `world["tide_left"]` ...).

use realm_core::tables::{field_boss_of, BOSSES, BOSS_EVERY_TIDES, FIELDS};
use realm_core::{next_field_boss, next_world_boss, tide_countdown, Field, SUB};

/// A boss on the ground now.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BossView {
    /// Row in `BOSSES`.
    pub which: u8,
    pub name: &'static str,
    pub health: u32,
    pub max_health: u32,
    /// Where it stands, px.
    pub x: i32,
    pub y: i32,
    /// DEATH, THE PALE RIDER.
    pub world: bool,
    /// Ticks until it leaves (0 in a vault: a vault's boss stays).
    pub leaves_in: u64,
}

/// The realm as one field (or vault) shows it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct WorldView {
    pub clock: u64,
    pub tide: bool,
    /// Ticks to the next tide (0 while one runs) and left of the running one.
    pub tide_in: u64,
    pub tide_left: u64,
    /// The six altars: (`ALTAR_*` state, hero-ticks held, health).
    pub altars: [(u8, u32, u32); 6],
    /// The monsters are quick (a tide, or two minutes after a lost one).
    pub quick: bool,
    pub boss: Option<BossView>,
    /// The next field boss of this field: its row and ticks until it rises (0 while it is up).
    pub next_boss: (u8, u64),
    /// The world boss's next (or running) ride: its field and ticks until it arrives (0 while it rides).
    pub world_field: u8,
    pub world_in: u64,
    /// A vault: (`RUN_*` state, ticks of the run, seals).
    pub vault: Option<(u8, u32, u8)>,
}

/// One field's line of the realm board (town shows every field's countdowns).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FieldClock {
    pub field: u8,
    pub tide_in: u64,
    pub tide_left: u64,
    pub boss: u8,
    pub boss_in: u64,
}

/// Every field's countdowns and the world boss's next ride at a realm clock.
pub fn realm_board(clock: u64) -> (Vec<FieldClock>, u8, u64) {
    let fields = (0..FIELDS.len() as u8)
        .map(|f| {
            let (tide_in, tide_left) = tide_countdown(clock, f);
            let (n, rise) = next_field_boss(clock, f);
            FieldClock { field: f, tide_in, tide_left, boss: field_boss_of(f, n / BOSS_EVERY_TIDES), boss_in: rise.saturating_sub(clock) }
        })
        .collect();
    let (_, wf, start) = next_world_boss(clock);
    (fields, wf, start.saturating_sub(clock))
}

/// The world of a field or vault as its players see it.
pub fn world_view(f: &Field) -> WorldView {
    let clock = f.clock();
    let boss = f.boss().zip(f.boss_pos()).zip(f.boss_health()).map(|((b, (x, y)), (hp, max))| BossView {
        which: b.which,
        name: BOSSES.get(b.which as usize).map_or("", |r| r.name),
        health: hp,
        max_health: max,
        x: x / SUB,
        y: y / SUB,
        world: b.world,
        leaves_in: if f.vault().is_some() { 0 } else { b.leaves.saturating_sub(clock) },
    });
    let mut altars = [(0u8, 0u32, 0u32); 6];
    for (o, a) in altars.iter_mut().zip(f.altars().iter()) {
        *o = (a.state, a.progress, a.hp);
    }
    let vault = f.vault().map(|v| (v.state, f.vault_ticks(), v.seals));
    if vault.is_some() {
        return WorldView { clock, boss, altars, vault, ..WorldView::default() };
    }
    let field = f.field_id();
    let (tide_in, tide_left) = tide_countdown(clock, field);
    let (n, rise) = next_field_boss(clock, field);
    let (_, wf, start) = next_world_boss(clock);
    WorldView {
        clock,
        tide: f.tide(),
        tide_in,
        tide_left,
        altars,
        quick: f.quick(),
        boss,
        next_boss: (field_boss_of(field, n / BOSS_EVERY_TIDES), rise.saturating_sub(clock)),
        world_field: wf,
        world_in: start.saturating_sub(clock),
        vault,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use realm_core::tables::{B_DEATH, B_HARVESTER, BOSS_RISE_AFTER, TIDE_LEN};
    use realm_core::{field_boss_window, tide_start, world_ride, Config};

    fn stepped_to(clock: u64) -> Field {
        let mut f = Field::open(0, 3, Config { monsters: 200, threads: 1 });
        f.set_clock(clock - 1);
        f.step::<u16>(&[]);
        f
    }

    #[test]
    fn a_tide_shows_its_time_left_and_between_tides_the_time_to_the_next() {
        let t0 = tide_start(0, 2);
        let before = world_view(&stepped_to(t0 - 100));
        assert!(!before.tide);
        assert_eq!((before.tide_in, before.tide_left), (100, 0));
        let during = world_view(&stepped_to(t0 + 10));
        assert!(during.tide && during.quick);
        assert_eq!((during.tide_in, during.tide_left), (0, TIDE_LEN as u64 - 10));
        assert_eq!(during.altars.iter().filter(|a| a.0 == realm_core::tables::ALTAR_LIT).count(), 3);
    }

    #[test]
    fn the_field_boss_is_shown_with_its_name_health_and_place_while_it_is_up() {
        let (rise, leave) = field_boss_window(0, 3);
        let early = world_view(&stepped_to(rise - 50));
        assert!(early.boss.is_none());
        assert_eq!(early.next_boss, (B_HARVESTER, 50));
        let f = stepped_to(rise + 5);
        let v = world_view(&f);
        let b = v.boss.expect("the boss is up");
        assert_eq!((b.which, b.name, b.world), (B_HARVESTER, "THE HARVESTER", false));
        assert!(b.health > 0 && b.health <= b.max_health);
        assert_eq!(b.leaves_in, leave - (rise + 5));
        assert_eq!(v.next_boss.1, 0, "the boss is up now");
        assert!(rise > tide_start(0, 3) + TIDE_LEN as u64 + BOSS_RISE_AFTER as u64 - 1);
    }

    #[test]
    fn the_world_boss_is_named_in_its_field_and_counted_down_everywhere() {
        let (wf, start, _) = world_ride(0);
        assert_eq!(wf, 0);
        let v = world_view(&stepped_to(start + 3));
        assert_eq!(v.boss.as_ref().map(|b| (b.which, b.world)), Some((B_DEATH, true)));
        let (board, f, wait) = realm_board(start - 600);
        assert_eq!((f, wait), (0, 600));
        assert_eq!(board.len(), 6);
        for c in &board {
            assert_eq!((c.tide_in, c.tide_left), tide_countdown(start - 600, c.field));
        }
    }
}

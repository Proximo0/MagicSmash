//! The 30 cards of the deck (rules section 5) and the six potions (section 7).

use super::secs;

/// What one copy of a card does. Implemented once in `deck::card_mods` and the combat code.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CardFx {
    Damage(i32),
    Move(i32),
    AttackSpeed(i32),
    /// +% health, healed at once.
    Health(u32),
    /// Regains this many 1/10 % of health a second.
    Regen(u32),
    Size(u32),
    Reach(u32),
    Cooldown(u32),
    Coin(u32),
    Xp(u32),
    Taken(i32),
    /// Returns this % of contact damage to the attacker.
    Reflect(u32),
    /// Every `n`th attack hits twice.
    EveryNth(u32),
    /// +% damage to monsters under `under`% health.
    Execute {
        pct: u32,
        under: u32,
    },
    /// +dmg%, takes +taken% more.
    Devil {
        dmg: i32,
        taken: i32,
    },
    /// `chance`% of hits strike for double.
    Crit(u32),
    /// Allies within px deal % more (group effect: the strongest counts).
    Sun {
        pct: u32,
        px: i32,
    },
    /// Heals % of damage dealt, at most `cap`% of health a second.
    Lifesteal {
        pct: u32,
        cap: u32,
    },
    /// +% damage to ELITES, CHAMPIONS and bosses.
    Elite(u32),
    /// Raises allies % faster; rises with % more health.
    Raiser {
        raise: u32,
        rise: u32,
    },
    /// +% damage during a tide.
    Tide(i32),
    /// +1 pierce or target (LONGBOW, FIREBALL, SMITE); other weapons +% damage.
    Fool(i32),
    Push(i32),
    /// Potions restore % more and hold one more charge this outing.
    Cups(u32),
    /// The ultimate's cooldown % shorter (no job: +% damage).
    Wands {
        cdr: u32,
        dmg: i32,
    },
    /// +% damage while no ally is within px.
    Alone {
        pct: i32,
        px: i32,
    },
    /// +% per ally within px, at most max.
    Company {
        pct: i32,
        max: i32,
        px: i32,
    },
    /// On being downed, bursts px for damage.
    Burst {
        px: i32,
        dmg: u32,
    },
    /// The haul loses this many tenths less on a fall.
    Keep(u32),
    /// +% move speed for 3 s after a kill (the KNIGHT OF WANDS effect).
    KillRush,
}

#[derive(Clone, Copy, Debug)]
pub struct Card {
    pub name: &'static str,
    pub fx: CardFx,
}

/// Card ids are 1..30; index 0 is unused.
pub const CARDS: [Card; 31] = [
    Card { name: "", fx: CardFx::Damage(0) },
    Card { name: "STRENGTH", fx: CardFx::Damage(10) },
    Card { name: "THE CHARIOT", fx: CardFx::Move(6) },
    Card { name: "THE MAGICIAN", fx: CardFx::AttackSpeed(8) },
    Card { name: "THE EMPRESS", fx: CardFx::Health(10) },
    Card { name: "TEMPERANCE", fx: CardFx::Regen(5) },
    Card { name: "THE WORLD", fx: CardFx::Size(12) },
    Card { name: "THE STAR", fx: CardFx::Reach(10) },
    Card { name: "THE HIGH PRIESTESS", fx: CardFx::Cooldown(8) },
    Card { name: "WHEEL OF FORTUNE", fx: CardFx::Coin(10) },
    Card { name: "THE HERMIT", fx: CardFx::Xp(8) },
    Card { name: "THE HIEROPHANT", fx: CardFx::Taken(-5) },
    Card { name: "JUSTICE", fx: CardFx::Reflect(20) },
    Card { name: "THE TOWER", fx: CardFx::EveryNth(5) },
    Card { name: "DEATH", fx: CardFx::Execute { pct: 25, under: 30 } },
    Card { name: "THE DEVIL", fx: CardFx::Devil { dmg: 18, taken: 6 } },
    Card { name: "THE MOON", fx: CardFx::Crit(5) },
    Card { name: "THE SUN", fx: CardFx::Sun { pct: 3, px: 100 } },
    Card { name: "THE LOVERS", fx: CardFx::Lifesteal { pct: 1, cap: 2 } },
    Card { name: "THE EMPEROR", fx: CardFx::Elite(15) },
    Card { name: "THE HANGED MAN", fx: CardFx::Raiser { raise: 25, rise: 15 } },
    Card { name: "JUDGEMENT", fx: CardFx::Tide(12) },
    Card { name: "THE FOOL", fx: CardFx::Fool(8) },
    Card { name: "NINE OF SWORDS", fx: CardFx::Push(6) },
    Card { name: "THREE OF CUPS", fx: CardFx::Cups(20) },
    Card { name: "ACE OF WANDS", fx: CardFx::Wands { cdr: 10, dmg: 6 } },
    Card { name: "FIVE OF PENTACLES", fx: CardFx::Alone { pct: 20, px: 150 } },
    Card { name: "SIX OF CUPS", fx: CardFx::Company { pct: 4, max: 20, px: 150 } },
    Card { name: "TEN OF SWORDS", fx: CardFx::Burst { px: 160, dmg: 300 } },
    Card { name: "QUEEN OF PENTACLES", fx: CardFx::Keep(1) },
    Card { name: "KNIGHT OF WANDS", fx: CardFx::KillRush },
];
pub const NCARDS: usize = 30;
pub const MAX_COPIES: u8 = 5;
pub const DECK_SIZE: usize = 20;
pub const DRAW_SIZE: u8 = 3;
pub const DRAW_MAX: u8 = 4;
pub const DRAW_QUEUE: usize = 9;
/// Where a draw comes from (rules 5, `Event::Grant`): entering a place with a fresh outing (her opening draw), a
/// share in an ELITE, CHAMPION or boss kill, a shrine touched.
pub const GRANT_ENTER: u8 = 0;
pub const GRANT_KILL: u8 = 1;
pub const GRANT_SHRINE: u8 = 2;
/// A NOVICE owns the first 12 cards; each even class level to 24 adds one.
pub const NOVICE_CARDS: u8 = 12;
pub const CARD_LEVEL_STEP: u8 = 2;
pub const CARD_LEVEL_TOP: u8 = 24;
/// Cards with an effect on a fall: the haul loses half (in tenths: 5 of 10).
pub const FALL_LOSS_TENTHS: u32 = 5;
pub const TENTHS: u32 = 10;

// ---- potions
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PotionFx {
    Heal(u32),
    Effect(u8),
    /// Not drunk: when she would be FALLEN she rises instead with this % health.
    Phoenix(u32),
}

#[derive(Clone, Copy, Debug)]
pub struct Potion {
    pub name: &'static str,
    pub fx: PotionFx,
    pub carried: u8,
    /// Ticks between uses.
    pub rest: u16,
}

pub const P_HEALING: u8 = 0;
pub const P_VEIL: u8 = 1;
pub const P_WHETSTONE: u8 = 2;
pub const P_INK: u8 = 3;
pub const P_GAMBLER: u8 = 4;
pub const P_PHOENIX: u8 = 5;
/// An empty belt slot.
pub const P_NONE: u8 = u8::MAX;

pub const POTIONS: [Potion; 6] = [
    Potion { name: "HEALING DRAUGHT", fx: PotionFx::Heal(35), carried: 3, rest: secs(10) as u16 },
    Potion { name: "VEIL OF ASH", fx: PotionFx::Effect(super::classes::FX_VEIL), carried: 2, rest: secs(30) as u16 },
    Potion { name: "WHETSTONE OIL", fx: PotionFx::Effect(super::classes::FX_WHETSTONE), carried: 2, rest: secs(30) as u16 },
    Potion { name: "SCHOLAR'S INK", fx: PotionFx::Effect(super::classes::FX_INK), carried: 1, rest: 0 },
    Potion { name: "GAMBLER'S COIN", fx: PotionFx::Effect(super::classes::FX_GAMBLER), carried: 1, rest: 0 },
    Potion { name: "PHOENIX ASH", fx: PotionFx::Phoenix(30), carried: 1, rest: 0 },
];
pub const BELT: usize = 3;

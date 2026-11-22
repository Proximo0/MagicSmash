//! Which module owns which message types: the one table every wire tag is checked against. Each module gets a
//! fixed span of request tags (0x01..=0x7F), of reply tags (0x80..=0x9F) and of push tags (0xA0..=0xBF), so two
//! jobs adding messages at once cannot pick the same byte. A new module takes a reserved row (or a free span),
//! puts its tags in its own `wire.rs`, adds a `gate.rs` (`proto::WireModule`) and one line to `proto::MODULES`.
//!
//! Free today: requests 0x7C..=0x7F, replies 0x8F and 0x92..=0x9F, pushes 0xAC..=0xAF and 0xB2..=0xBF.
//! 0xC0..=0xEF are unused; 0xF0..=0xFF never go on the wire (the client's own markers, e.g. `R_LOST` 0xFF).
//! The Godot client mirrors this table in a comment in `realm/client/ui/gw_wire.gd`.

/// An inclusive span of tags.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Span(pub u8, pub u8);

impl Span {
    pub fn has(&self, t: u8) -> bool {
        (self.0..=self.1).contains(&t)
    }
}

/// One module's row.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Row {
    pub module: &'static str,
    /// The job that owns it (`docs/realm/build_plan.md`).
    pub job: &'static str,
    pub req: Span,
    pub reply: Span,
    pub push: Span,
}

impl Row {
    pub fn has(&self, t: u8) -> bool {
        self.req.has(t) || self.reply.has(t) || self.push.has(t)
    }
}

/// Where each kind of tag may be.
pub const REQ_SPACE: Span = Span(0x01, 0x7F);
pub const REPLY_SPACE: Span = Span(0x80, 0x9F);
pub const PUSH_SPACE: Span = Span(0xA0, 0xBF);

pub const CORE: Row = Row { module: "core", job: "W1", req: Span(0x01, 0x32), reply: Span(0x80, 0x8A), push: Span(0xA0, 0xA7) };
pub const ECONOMY: Row = Row { module: "economy", job: "E1", req: Span(0x33, 0x3F), reply: Span(0x8B, 0x8B), push: Span(0xA8, 0xA8) };
pub const SOCIAL: Row = Row { module: "social", job: "T1", req: Span(0x40, 0x5F), reply: Span(0x90, 0x90), push: Span(0xB0, 0xB0) };
pub const WORLD: Row = Row { module: "world", job: "W2", req: Span(0x60, 0x6F), reply: Span(0x91, 0x91), push: Span(0xB1, 0xB1) };
pub const HOMES: Row = Row { module: "homes", job: "H1", req: Span(0x70, 0x73), reply: Span(0x8C, 0x8C), push: Span(0xA9, 0xA9) };
/// Reserved: players against players, duels and guild wars (job R3).
pub const PVP: Row = Row { module: "pvp", job: "R3", req: Span(0x74, 0x77), reply: Span(0x8D, 0x8D), push: Span(0xAA, 0xAA) };
/// Reserved: Steam login, friends and overlay (job P1).
pub const STEAM: Row = Row { module: "steam", job: "P1", req: Span(0x78, 0x7B), reply: Span(0x8E, 0x8E), push: Span(0xAB, 0xAB) };

pub const TABLE: &[Row] = &[CORE, ECONOMY, SOCIAL, WORLD, HOMES, PVP, STEAM];

/// The module that owns a tag, if any.
pub fn owner(t: u8) -> Option<&'static Row> {
    TABLE.iter().find(|r| r.has(t))
}

/// A module's row by name.
pub fn row(module: &str) -> Option<&'static Row> {
    TABLE.iter().find(|r| r.module == module)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_two_modules_share_a_tag_and_every_span_is_in_its_space() {
        for (i, a) in TABLE.iter().enumerate() {
            for (s, space) in [(a.req, REQ_SPACE), (a.reply, REPLY_SPACE), (a.push, PUSH_SPACE)] {
                assert!(s.0 <= s.1 && space.has(s.0) && space.has(s.1), "{} {s:?} outside {space:?}", a.module);
            }
            for b in &TABLE[i + 1..] {
                assert_ne!(a.module, b.module);
                for t in 0..=255u8 {
                    assert!(!(a.has(t) && b.has(t)), "tag {t:#04x} in both {} and {}", a.module, b.module);
                }
            }
        }
        assert!(owner(0x00).is_none() && (0xC0..=0xFF).all(|t| owner(t).is_none()), "0x00 and 0xC0.. belong to nobody");
    }

    #[test]
    fn every_named_tag_is_in_its_modules_span() {
        use crate::proto::*;
        let core = [
            T_LOGIN_DEV, T_LOGIN_STEAM, T_LIST_HEROES, T_CREATE_HERO, T_DELETE_HERO, T_UNDELETE_HERO, T_ENTER_TOWN, T_LEAVE_TOWN,
            T_TOWN_INPUT, T_CHAT, T_FIELD_TICKET, T_INVENTORY, T_BANK_DEPOSIT, T_BANK_WITHDRAW, T_MAIL_SEND, T_MAIL_TAKE,
            T_SPEND_POINT, T_SET_DECK, T_SET_BELT, T_LEARN_PAGE, T_EQUIP, T_UNEQUIP, T_SOCKET, T_UNSOCKET, T_CHOOSE_JOB,
            T_PING, T_RENAME_HERO, T_SALVAGE, T_UPGRADE, T_REROLL, T_FUSE, T_CARDS, T_BUY, T_SELL,
        ];
        assert!(core.iter().all(|t| CORE.req.has(*t)));
        let core = [R_OK, R_ERR, R_LOGIN, R_HEROES, R_HERO_CREATED, R_TOWN, R_TICKET, R_INVENTORY, R_PONG, R_SMITH, R_CARDS];
        assert!(core.iter().all(|t| CORE.reply.has(*t)));
        let core = [P_TOWN_SNAPSHOT, P_TOWN_CHAT, P_TOWN_ARRIVE, P_TOWN_DEPART, P_OUTING];
        assert!(core.iter().all(|t| CORE.push.has(*t)));
        use crate::economy::wire as e;
        assert!(ECONOMY.req.has(e::T_ECON) && ECONOMY.reply.has(e::R_ECON) && ECONOMY.push.has(e::P_ECON));
        use crate::social as s;
        assert_eq!((s::T_SOC_FIRST, s::T_SOC_LAST), (SOCIAL.req.0, SOCIAL.req.1));
        assert!(SOCIAL.reply.has(s::R_SOCIAL) && SOCIAL.push.has(s::P_SOCIAL));
        use crate::world::wire as w;
        assert!(WORLD.req.has(w::T_WORLD) && WORLD.reply.has(w::R_WORLD) && WORLD.push.has(w::P_WORLD));
        use crate::homes as h;
        assert!(HOMES.req.has(h::T_HOME) && HOMES.reply.has(h::R_HOME) && HOMES.push.has(h::P_HOME));
    }

    /// Every registered module has a row, and every message it encodes (its examples) carries a tag of its own.
    #[test]
    fn every_module_speaks_only_in_its_own_span() {
        use crate::proto::{base, MODULES};
        let mut all = vec![("core", base::examples())];
        all.extend(MODULES.iter().map(|m| (m.module, (m.examples)())));
        for (module, (reqs, resps)) in all {
            let r = row(module).unwrap_or_else(|| panic!("{module} has no row in proto::ranges::TABLE"));
            assert!(!reqs.is_empty() && !resps.is_empty(), "{module} has no examples");
            for q in reqs {
                let (t, _) = q.encode();
                assert!(r.req.has(t), "{module}: {q:?} has tag {t:#04x}, outside {:?}", r.req);
            }
            for p in resps {
                let (t, _) = p.encode();
                assert!(r.reply.has(t) || r.push.has(t), "{module}: {p:?} has tag {t:#04x}, outside its spans");
            }
        }
    }
}

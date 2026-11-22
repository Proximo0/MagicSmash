//! Parties of up to eight heroes. A party is made when the first invitation is accepted and goes when one hero is
//! left. The leader invites, kicks, hands over the lead and calls the party to a field; members leave at will. Loot
//! is per hero already (each ticket has its own haul), so a party shares nothing but the field copy: tickets of a
//! party's heroes ask for the same copy (`Social::party_copy`), for `PARTY_COPY_TTL_MS` after the last ticket.

use super::*;

impl Inner {
    pub fn party_view(&self, id: u64) -> Option<PartyView> {
        let p = self.parties.get(&id)?;
        let members = p
            .members
            .iter()
            .map(|h| match self.online.get(h) {
                Some(pr) => PartyMember { hero: *h, name: pr.name.clone(), class: pr.class, level: pr.level, online: true },
                None => PartyMember { hero: *h, name: String::new(), class: 0, level: 0, online: false },
            })
            .collect();
        Some(PartyView { id, leader: p.leader, members, copy: p.copy.map(|(f, c, _)| (f, c)) })
    }

    pub fn party_push(&self, id: u64) {
        if let Some(p) = self.parties.get(&id) {
            let v = self.party_view(id);
            for h in &p.members {
                self.send(*h, SPush::PartyUpdate(v.clone()));
            }
        }
    }

    pub fn party_changed_for(&self, hero: i64) {
        if let Some(id) = self.party_of.get(&hero) {
            self.party_push(*id);
        }
    }

    /// Takes a hero out of her party (left, kicked, gone). The lead passes to the longest-standing member; a party
    /// of one is dissolved.
    pub fn party_remove(&mut self, hero: i64, _why: &str) {
        let Some(id) = self.party_of.remove(&hero) else { return };
        let Some(p) = self.parties.get_mut(&id) else { return };
        p.members.retain(|h| *h != hero);
        if p.members.len() <= 1 {
            let rest = std::mem::take(&mut p.members);
            self.parties.remove(&id);
            for h in rest {
                self.party_of.remove(&h);
                self.send(h, SPush::PartyUpdate(None));
            }
        } else {
            if p.leader == hero {
                p.leader = p.members[0];
            }
            self.party_push(id);
        }
        self.send(hero, SPush::PartyUpdate(None));
    }
}

impl Social {
    pub(super) fn party_invite(&self, gw: &Gateway, me: &Me, name: &str, now: i64) -> R {
        let target = self.hero_named(gw, name)?;
        let mut g = self.inner.lock().unwrap();
        if target.id == me.hero || target.account == me.account {
            return Err(bad("invite someone else"));
        }
        if let Some(id) = g.party_of.get(&me.hero) {
            let p = &g.parties[id];
            if p.leader != me.hero {
                return Err(fail(code::REFUSED, "only the leader invites"));
            }
            if p.members.len() >= PARTY_MAX {
                return Err(fail(code::FULL, "the party is full"));
            }
        }
        if g.party_of.contains_key(&target.id) {
            return Err(fail(code::BUSY, "she is in a party"));
        }
        if !g.online.contains_key(&target.id) {
            return Err(fail(code::MISSING, "she is not here"));
        }
        g.party_invites.retain(|_, exp| *exp > now);
        // An ignoring hero is not bothered, and the inviter is not told.
        if !g.ignores(target.account, me.account) {
            g.party_invites.insert((target.id, me.hero), now + INVITE_TTL_MS);
            g.send(target.id, SPush::PartyInvite { inviter: me.hero, name: me.name.clone() });
        }
        Ok(Resp::Ok)
    }

    pub(super) fn party_answer(&self, me: &Me, inviter: i64, accept: bool, now: i64) -> R {
        let mut g = self.inner.lock().unwrap();
        let Some(exp) = g.party_invites.remove(&(me.hero, inviter)) else {
            return Err(fail(code::MISSING, "no such invitation"));
        };
        if !accept {
            g.send(inviter, SPush::Notice { text: format!("{} declined your party.", me.name) });
            return Ok(Resp::Ok);
        }
        if exp <= now {
            return Err(fail(code::MISSING, "that invitation ran out"));
        }
        if g.party_of.contains_key(&me.hero) {
            return Err(fail(code::BUSY, "leave your party first"));
        }
        if !g.online.contains_key(&inviter) {
            return Err(fail(code::MISSING, "the inviter has gone"));
        }
        let id = match g.party_of.get(&inviter) {
            Some(id) => *id,
            None => {
                let id = g.next_party;
                g.next_party += 1;
                g.parties.insert(id, Party { id, leader: inviter, members: vec![inviter], copy: None });
                g.party_of.insert(inviter, id);
                id
            }
        };
        let p = g.parties.get_mut(&id).unwrap();
        if p.members.len() >= PARTY_MAX {
            return Err(fail(code::FULL, "the party is full"));
        }
        p.members.push(me.hero);
        g.party_of.insert(me.hero, id);
        g.party_push(id);
        Ok(Resp::Social(SResp::Party(g.party_view(id))))
    }

    pub(super) fn party_leave(&self, me: &Me) -> R {
        let mut g = self.inner.lock().unwrap();
        if !g.party_of.contains_key(&me.hero) {
            return Err(bad("you are in no party"));
        }
        g.party_remove(me.hero, "left");
        Ok(Resp::Ok)
    }

    fn leader_party(g: &Inner, me: &Me) -> R<u64> {
        let id = *g.party_of.get(&me.hero).ok_or_else(|| bad("you are in no party"))?;
        if g.parties[&id].leader != me.hero {
            return Err(fail(code::REFUSED, "only the leader may"));
        }
        Ok(id)
    }

    pub(super) fn party_kick(&self, me: &Me, target: i64) -> R {
        let mut g = self.inner.lock().unwrap();
        let id = Self::leader_party(&g, me)?;
        if target == me.hero || !g.parties[&id].members.contains(&target) {
            return Err(bad("not a member"));
        }
        g.send(target, SPush::Notice { text: "You were removed from the party.".into() });
        g.party_remove(target, "kicked");
        Ok(Resp::Ok)
    }

    pub(super) fn party_lead(&self, me: &Me, target: i64) -> R {
        let mut g = self.inner.lock().unwrap();
        let id = Self::leader_party(&g, me)?;
        if target == me.hero || !g.parties[&id].members.contains(&target) {
            return Err(bad("not a member"));
        }
        g.parties.get_mut(&id).unwrap().leader = target;
        g.party_push(id);
        Ok(Resp::Ok)
    }

    pub(super) fn party_go(&self, me: &Me, field: u8) -> R {
        if field as usize >= realm_core::tables::FIELDS.len() {
            return Err(bad("no such field"));
        }
        let g = self.inner.lock().unwrap();
        let id = Self::leader_party(&g, me)?;
        for h in g.parties[&id].members.iter().filter(|h| **h != me.hero) {
            g.send(*h, SPush::PartyGo { field });
        }
        Ok(Resp::Ok)
    }

    pub(super) fn party_info(&self, me: &Me) -> R {
        let g = self.inner.lock().unwrap();
        Ok(Resp::Social(SResp::Party(g.party_of.get(&me.hero).and_then(|id| g.party_view(*id)))))
    }

    /// The copy of `field` the hero's party shares, if one was set within `PARTY_COPY_TTL_MS` (the gateway asks
    /// before it picks the emptier copy).
    pub fn party_copy(&self, hero: i64, field: u8, now: i64) -> Option<u8> {
        let g = self.inner.lock().unwrap();
        let p = g.parties.get(g.party_of.get(&hero)?)?;
        p.copy.filter(|(f, _, at)| *f == field && now - at < PARTY_COPY_TTL_MS).map(|(_, c, _)| c)
    }

    /// Records the copy a party member's ticket was given, so the others' tickets follow it.
    pub fn party_set_copy(&self, hero: i64, field: u8, copy: u8, now: i64) {
        let mut g = self.inner.lock().unwrap();
        if let Some(id) = g.party_of.get(&hero).copied() {
            let p = g.parties.get_mut(&id).unwrap();
            let changed = p.copy.map(|(f, c, _)| (f, c)) != Some((field, copy));
            p.copy = Some((field, copy, now));
            if changed {
                g.party_push(id);
            }
        }
    }
}

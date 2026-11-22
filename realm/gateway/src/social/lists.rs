//! Friends and ignores, kept by account (a player, not one hero). A friendship needs both to agree (a request, then an
//! answer); an ignore is one-sided and quiet: an ignored account's chat, whispers, invitations and friend requests
//! never reach the one who ignores, and the sender is not told. Ignoring someone ends a friendship with her.

use super::*;

impl Social {
    pub(super) fn friend_add(&self, gw: &Gateway, me: &Me, name: &str, now: i64) -> R {
        let t = self.hero_named(gw, name)?;
        let mut g = self.inner.lock().unwrap();
        if t.account == me.account {
            return Err(bad("that is you"));
        }
        if g.friends.get(&me.account).is_some_and(|s| s.contains(&t.account)) {
            return Err(fail(code::BUSY, "already friends"));
        }
        if g.names.get(&t.account) != Some(&t.name) {
            g.commit("name", &[&t.account.to_string(), &t.name]);
        }
        if g.friends.get(&me.account).map_or(0, |s| s.len()) >= LIST_MAX || g.friends.get(&t.account).map_or(0, |s| s.len()) >= LIST_MAX {
            return Err(fail(code::FULL, "a friends list is full"));
        }
        // She asked us first: that is an answer.
        if g.friend_reqs.get(&(me.account, t.account)).is_some_and(|e| *e > now) {
            g.friend_reqs.remove(&(me.account, t.account));
            return Ok(self.make_friends(&mut g, me.account, t.account));
        }
        g.friend_reqs.retain(|_, e| *e > now);
        if !g.ignores(t.account, me.account) {
            g.friend_reqs.insert((t.account, me.account), now + FRIEND_REQ_TTL_MS);
            g.send_account(t.account, &SPush::FriendRequest { from: me.account, name: me.name.clone() });
        }
        Ok(Resp::Ok)
    }

    fn make_friends(&self, g: &mut Inner, a: i64, b: i64) -> Resp {
        g.commit("friend", &[&a.to_string(), &b.to_string(), "1"]);
        for (x, y) in [(a, b), (b, a)] {
            g.send_account(x, &SPush::FriendStatus { account: y, name: g.name_of(y), online: g.is_online(y), place: g.place_of(y) });
        }
        Resp::Ok
    }

    pub(super) fn friend_answer(&self, me: &Me, from: i64, accept: bool, now: i64) -> R {
        let mut g = self.inner.lock().unwrap();
        let Some(exp) = g.friend_reqs.remove(&(me.account, from)) else {
            return Err(fail(code::MISSING, "no such request"));
        };
        if !accept {
            return Ok(Resp::Ok);
        }
        if exp <= now {
            return Err(fail(code::MISSING, "that request ran out"));
        }
        if g.friends.get(&me.account).map_or(0, |s| s.len()) >= LIST_MAX || g.friends.get(&from).map_or(0, |s| s.len()) >= LIST_MAX {
            return Err(fail(code::FULL, "a friends list is full"));
        }
        Ok(self.make_friends(&mut g, me.account, from))
    }

    pub(super) fn friend_remove(&self, me: &Me, target: i64) -> R {
        let mut g = self.inner.lock().unwrap();
        if !g.friends.get(&me.account).is_some_and(|s| s.contains(&target)) {
            return Err(fail(code::MISSING, "not a friend"));
        }
        g.commit("friend", &[&me.account.to_string(), &target.to_string(), "0"]);
        Ok(Resp::Ok)
    }

    pub(super) fn ignore(&self, gw: &Gateway, me: &Me, name: &str, on: bool) -> R {
        let t = self.hero_named(gw, name)?;
        let mut g = self.inner.lock().unwrap();
        if t.account == me.account {
            return Err(bad("that is you"));
        }
        if on {
            if g.ignores.get(&me.account).map_or(0, |s| s.len()) >= LIST_MAX {
                return Err(fail(code::FULL, "your ignore list is full"));
            }
            if g.friends.get(&me.account).is_some_and(|s| s.contains(&t.account)) {
                g.commit("friend", &[&me.account.to_string(), &t.account.to_string(), "0"]);
            }
            g.friend_reqs.remove(&(me.account, t.account));
            // Her name is kept so the list can show it even when she is away.
            if g.names.get(&t.account) != Some(&t.name) {
                g.commit("name", &[&t.account.to_string(), &t.name]);
            }
        }
        g.commit("ignore", &[&me.account.to_string(), &t.account.to_string(), if on { "1" } else { "0" }]);
        Ok(Resp::Ok)
    }

    pub(super) fn lists(&self, me: &Me, now: i64) -> R {
        let g = self.inner.lock().unwrap();
        let friends = g
            .friends
            .get(&me.account)
            .into_iter()
            .flatten()
            .map(|a| FriendRow { account: *a, name: g.name_of(*a), online: g.is_online(*a), place: g.place_of(*a) })
            .collect();
        let mut pending: Vec<(i64, String)> = g.friend_reqs.iter().filter(|((to, _), e)| *to == me.account && **e > now).map(|((_, from), _)| (*from, g.name_of(*from))).collect();
        pending.sort();
        let ignores = g.ignores.get(&me.account).into_iter().flatten().map(|a| (*a, g.name_of(*a))).collect();
        Ok(Resp::Social(SResp::Lists(Lists { friends, pending, ignores })))
    }
}

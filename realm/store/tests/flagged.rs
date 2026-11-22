//! Job T1's store addition: accounts found by flag, for the moderators' ban wave.
mod common;
use common::*;
use realm_store::*;

#[test]
fn accounts_are_found_by_flag_for_a_ban_wave() {
	let mut t = T::new("flagged");
	let (a, b, c) = (t.account(1), t.account(2), t.account(3));
	let m = t.m();
	t.s.apply_flags(
		m,
		vec![
			FlagChange { account: a, flags: flags::WATCHED, drops_percent: 100, banned_until: None },
			FlagChange { account: b, flags: flags::TRADE_LOCKED | flags::WATCHED, drops_percent: 100, banned_until: None },
		],
		"wave",
	)
	.unwrap();
	let ids = |mask| t.s.accounts_flagged(mask).unwrap().iter().map(|x| x.id).collect::<Vec<_>>();
	assert_eq!(ids(flags::WATCHED), vec![a, b]);
	assert_eq!(ids(flags::TRADE_LOCKED), vec![b]);
	assert_eq!(ids(flags::SHADOWED), Vec::<AccountId>::new());
	assert!(!ids(flags::ALL).contains(&c));
}

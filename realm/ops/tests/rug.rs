//! Pulling the rug, end to end through the real `realm-ops` program on a small store (`--db`, the stopped-realm
//! and backup-copy path; the running realm takes the same line through its admin console, `rug ...`): a farm mints
//! and trades to a buyer who banks some; trace shows the path, plan lists the right items and stacks, a dry run
//! changes nothing, `--yes` claws back with ledger rows, flags are set and cleared, and a wave file works with one
//! bad line reported.

use realm_ops::{backup, rug};
use realm_store::*;
use std::path::{Path, PathBuf};
use std::process::Command;

fn ops(args: &[&str]) -> (bool, String) {
    let o = Command::new(env!("CARGO_BIN_EXE_realm-ops")).args(args).output().expect("run realm-ops");
    let text = format!("{}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr));
    (o.status.success(), text.trim().to_string())
}

fn ok(args: &[&str]) -> String {
    let (good, t) = ops(args);
    assert!(good, "realm-ops {args:?} failed: {t}");
    t
}

fn temp(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("realm-ops-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn spec() -> ItemSpec {
    ItemSpec { base: 7, gear_slot: 0, item_level: 1, rarity: 2, lines: vec![(0, 3)], sockets: 1, plus: 0, bound: false }
}

struct Realm {
    farm: AccountId,
    buyer: AccountId,
    clean: AccountId,
    hb: HeroId,
    farm_items: Vec<ItemId>,
    own_item: ItemId,
}

/// The farm mints 3 items and 1000 coin; trades 2 items and 300 coin to the buyer; the buyer banks one item and
/// 100 coin. An honest account has an item of its own.
fn build(db: &Path) -> Realm {
    let s = SqliteStore::open(db).unwrap();
    let mut n = 0u128;
    let mut m = || {
        n += 1;
        Meta::system(n, 1_700_000_000_000 + n as i64 * 1000)
    };
    let farm = s.account_by_steam(m(), 100).unwrap();
    let buyer = s.account_by_steam(m(), 200).unwrap();
    let clean = s.account_by_steam(m(), 300).unwrap();
    let hf = s.hero_create(m(), farm, "Farmer", 0, 0, 0, false).unwrap();
    let hb = s.hero_create(m(), buyer, "Buyer", 0, 0, 0, false).unwrap();
    let hc = s.hero_create(m(), clean, "Honest", 0, 0, 0, false).unwrap();
    let farm_items: Vec<ItemId> = (0..3).map(|_| s.mint(m(), Dest::bag(hf), spec(), "drop").unwrap().0).collect();
    s.stack_credit(m(), Owner::bag(hf), StackKind::COIN, 1000, true, "drop").unwrap();
    let own_item = s.mint(m(), Dest::bag(hc), spec(), "drop").unwrap().0;
    let a = TradeSide { hero: hf, items: vec![farm_items[0], farm_items[1]], stacks: vec![(StackKind::COIN, 300)] };
    let b = TradeSide { hero: hb, items: vec![], stacks: vec![] };
    let mut t = m();
    t.id = trade_request_id(&a, &b, 1);
    s.trade_commit(t, a, b).unwrap();
    s.move_item(m(), farm_items[0], Dest::bank(buyer, 0)).unwrap();
    s.stack_transfer(m(), Owner::bag(hb), Owner::bank(buyer), StackKind::COIN, 100).unwrap();
    s.close();
    Realm { farm, buyer, clean, hb, farm_items, own_item }
}

fn with<T>(db: &Path, f: impl FnOnce(&SqliteStore) -> T) -> T {
    let s = SqliteStore::open(db).unwrap();
    let r = f(&s);
    s.close();
    r
}

fn coin(s: &SqliteStore, o: Owner) -> u64 {
    s.stack(o, StackKind::COIN).unwrap()
}

fn ledger(db: &Path, reason_like: &str) -> i64 {
    let c = rusqlite::Connection::open(db).unwrap();
    c.query_row("SELECT count(*) FROM ledger WHERE reason LIKE ?1", [format!("%{reason_like}%")], |r| r.get(0)).unwrap()
}

#[test]
fn pull_the_rug_by_hand() {
    let dir = temp("rug");
    let db = dir.join("realm.db");
    let r = build(&db);
    let d = format!("--db={}", db.display());
    let (farm, buyer) = (r.farm.to_string(), r.buyer.to_string());
    let digest = || backup::check(&db).expect("the store verifies").1;

    // trace: the farm's items and coin went to the buyer; the buyer's coin came from the farm
    let t = ok(&["trace", &farm, &d]);
    assert!(t.contains("minted items: 3"), "{t}");
    for i in &r.farm_items[..2] {
        assert!(t.contains(&format!("item {i} minted seq")) && t.contains(&format!("held by #{buyer}")), "{t}");
    }
    assert!(t.contains(&format!("coin: minted 1000 spent 0 holds 700; received from nobody; sent to #{buyer} 300")), "{t}");
    assert!(t.contains(&format!("#{farm} -> #{buyer} item {}", r.farm_items[0])), "{t}");
    assert!(t.contains(&format!("#{farm} -> #{buyer} coin x300")), "{t}");
    let tb = ok(&["trace", "hero:Buyer", &d]);
    assert!(tb.contains(&format!("received from #{farm} 300")) && tb.contains(&format!("item {} minted for #{farm} at bank:{buyer}", r.farm_items[0])), "{tb}");
    let ti = ok(&["trace", &format!("item:{}", r.farm_items[0]), &d]);
    assert!(ti.contains(&format!("minted for #{farm}")) && ti.contains(&format!("held by #{buyer}")) && ti.contains("path: 1 move(s)"), "{ti}");
    let tj = ok(&["trace", &format!("#{farm}"), "--json", &d]);
    assert!(tj.starts_with(&format!("{{\"account\":{farm},")) && tj.contains(&format!("\"to\":\"#{buyer}\"")) && tj.ends_with("]}"), "{tj}");
    assert!(!ops(&["trace", "nobody-at-all", &d]).0);

    // plan: every farm item; coin 700 from the farm's bag, 300 from the buyer (bag 200, bank 100); not the honest item
    let plan_text = ok(&["plan", &farm, &d]);
    let plan = rug::parse_plan(&plan_text).unwrap();
    let mut items = plan.items.clone();
    items.sort();
    assert_eq!(items, r.farm_items, "{plan_text}");
    assert!(!plan.items.contains(&r.own_item));
    let from = |o: Owner| plan.stacks.iter().filter(|s| s.0 == o && s.1 == StackKind::COIN).map(|s| s.2).sum::<u64>();
    assert_eq!(from(Owner::bag(r.hb)) + from(Owner::bank(r.buyer)), 300, "{plan_text}");
    assert_eq!(plan.stacks.iter().map(|s| s.2).sum::<u64>(), 1000, "{plan_text}");
    assert!(plan_text.ends_with("total items 3 stacks coin 1000"), "{plan_text}");
    // the buyer's slice of it, and nothing since a time after everything happened
    let slice = rug::parse_plan(&ok(&["plan", &buyer, "--origin", &farm, &d])).unwrap();
    assert_eq!((slice.items.len(), slice.stacks.iter().map(|s| s.2).sum::<u64>()), (2, 300));
    let late = rug::parse_plan(&ok(&["plan", &farm, "--since", "2030-01-01", &d])).unwrap();
    assert_eq!(late, ClawbackPlan::default());
    let early = rug::parse_plan(&ok(&["plan", &farm, "--since", "2020-01-01T00:00", &d])).unwrap();
    assert_eq!(early, plan);

    // a dry run changes nothing
    let before = digest();
    let dry = ok(&["clawback", &farm, "--reason", "farm wave 1", &d]);
    assert!(dry.contains("dry run: nothing changed"), "{dry}");
    let plan_file = dir.join("farm.plan");
    std::fs::write(&plan_file, &plan_text).unwrap();
    let pf = format!("--plan-file={}", plan_file.display());
    ok(&["clawback", &farm, &pf, "--reason", "farm wave 1", &d]);
    assert_eq!(digest(), before, "a dry run changed the store");
    assert_eq!(ledger(&db, "farm wave 1"), 0);
    assert!(!ops(&["clawback", &farm, &pf, "--yes", &d]).0, "--yes without --reason is refused");
    assert_eq!(digest(), before);

    // --yes: the plan file's items and stacks go, each with its ledger row
    let done = ok(&["clawback", &farm, "--plan-file", plan_file.to_str().unwrap(), "--reason", "farm wave 1", "--yes", &d]);
    assert!(done.contains("removed 3 item(s)") && done.contains("missing 0 []") && done.contains("shortfall none"), "{done}");
    assert!(ledger(&db, "farm wave 1") >= 3 + 3, "{done}");
    assert_ne!(digest(), before);
    with(&db, |s| {
        for i in &r.farm_items {
            assert_eq!(s.item(*i).unwrap(), None);
        }
        assert!(s.item(r.own_item).unwrap().is_some());
        assert_eq!(coin(s, Owner::bag(r.hb)) + coin(s, Owner::bank(r.buyer)), 0);
        assert!(s.verify().unwrap().ok());
    });
    // again: everything is gone already
    let again = ok(&["clawback", &farm, &pf, "--reason", "farm wave 1 again", "--yes", &d]);
    assert!(again.contains("removed 0 item(s)") && again.contains("missing 3"), "{again}");

    // flags: a dry run, then lock, shadow, ban, clear, each a FLAGS row
    let acct = |id: AccountId| with(&db, |s| s.account(id).unwrap().unwrap());
    let dry = ok(&["flag", &farm, "lock", "--reason", "bot", &d]);
    assert!(dry.contains("flags none -> trade_locked") && dry.contains("dry run"), "{dry}");
    assert_eq!(acct(r.farm).flags, 0);
    ok(&["flag", &farm, "lock", "--reason", "bot", "--yes", &d]);
    ok(&["flag", &format!("#{farm}"), "shadow", "--reason", "bot", "--yes", &d]);
    assert_eq!(acct(r.farm).flags, flags::TRADE_LOCKED | flags::SHADOWED);
    ok(&["flag", "Farmer", "ban", "--reason", "bot", "--yes", &d]);
    assert_eq!(acct(r.farm).banned_until, Some(rug::PERM_MS));
    ok(&["flag", &farm, "clear", "--reason", "appeal", "--yes", &d]);
    let a = acct(r.farm);
    assert_eq!((a.flags, a.banned_until), (0, None));
    assert_eq!(ledger(&db, "rug "), 4);
    assert!(!ops(&["flag", &farm, "explode", "--reason", "x", "--yes", &d]).0);

    // a wave of three accounts and one bad line: one line each, a total, the bad line named; dry run first
    let wave = dir.join("wave.txt");
    std::fs::write(&wave, format!("{farm}\n#{buyer}\n\nno-such-hero\nHonest\n")).unwrap();
    let w = wave.to_str().unwrap();
    let dry = ok(&["wave", w, "lock", "--reason", "farm ring", &d]);
    assert!(dry.contains("line 4 \"no-such-hero\"") && dry.contains("total 3 account(s) lock, 1 bad line(s); dry run"), "{dry}");
    assert!([r.farm, r.buyer, r.clean].iter().all(|a| acct(*a).flags == 0));
    let done = ok(&["wave", w, "lock", "--reason", "farm ring", "--yes", &d]);
    for a in [r.farm, r.buyer, r.clean] {
        assert!(done.contains(&format!("#{a}: flags none -> trade_locked")), "{done}");
        assert_eq!(acct(a).flags, flags::TRADE_LOCKED);
    }
    assert!(done.contains("total 3 account(s) lock, 1 bad line(s); applied"), "{done}");
    assert_eq!(ledger(&db, "farm ring"), 3);
    ok(&["wave", w, "clear", "--reason", "test over", "--yes", &d]);
    assert!([r.farm, r.buyer, r.clean].iter().all(|a| acct(*a).flags == 0));
    assert!(with(&db, |s| s.verify().unwrap().ok()));

    // without --db the command goes to the running realm's admin port, and says so when there is none
    let (good, t) = ops(&["plan", &farm, &format!("--root={}", dir.display())]);
    assert!(!good && t.contains("ops.conf"), "{t}");
    let _ = std::fs::remove_dir_all(&dir);
}

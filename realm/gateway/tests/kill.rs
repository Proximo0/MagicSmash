//! The kill test: a real `realm-gateway` process is killed (SIGKILL) in the middle of an outing; everything
//! banked before is still in the store, the store verifies, and the hero logs back in to a restarted server.

use realm_gateway::bot::{play_field, PlayOpts};
use realm_gateway::client::GatewayClient;
use realm_gateway::harness::{cycle, fast_prep, BotStats};
use realm_gateway::proto::*;
use realm_store::*;
use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::time::Duration;

fn spawn(db: &std::path::Path) -> (Child, String) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_realm-gateway"))
        .args([&format!("--db={}", db.display()), "--dev-login", "--bind=127.0.0.1", "--public-host=127.0.0.1", "--port=0", "--field-port=0", "--fields=0", "--monsters=1500", "--seed=5"])
        .stdout(Stdio::piped())
        .spawn()
        .expect("spawn realm-gateway");
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap()).read_line(&mut line).unwrap();
    let tcp = line.split_whitespace().find_map(|w| w.strip_prefix("tcp=")).expect("a LISTEN line").to_string();
    (child, tcp)
}

fn held(store: &SqliteStore, hero: i64) -> (u64, u64) {
    let h = store.hero(hero).unwrap().unwrap();
    let coin = store.stack(Owner::bag(hero), StackKind(1)).unwrap() + store.stack(Owner::bank(h.account), StackKind(1)).unwrap();
    (coin, h.progress.class_xp)
}

#[test]
fn a_server_killed_mid_outing_loses_nothing_banked() {
    let db = std::env::temp_dir().join(format!("realm-kill-{}.db", std::process::id()));
    let files = |db: &std::path::Path| ["", ".secret", ".bosskills", "-wal", "-shm"].map(|e| format!("{}{e}", db.display()));
    for f in files(&db) {
        let _ = std::fs::remove_file(f);
    }
    let t0 = std::time::Instant::now();
    let (mut child, addr) = spawn(&db);
    eprintln!("{:?} spawned", t0.elapsed());
    // A full outing that banks, so there is something to lose.
    let helper = Arc::new(SqliteStore::open(&db).unwrap());
    let prep = fast_prep(helper.clone());
    let mut st = BotStats::default();
    cycle(&addr, 1, 0, &PlayOpts { fight_ticks: 100, drop_after_bank: true, ..PlayOpts::default() }, &prep, &mut st).expect("a banked cycle");
    eprintln!("{:?} cycle {st:?}", t0.elapsed());
    assert!(st.banked_outings >= 1 && st.mismatches == 0, "{st:?}");
    let account = helper.account_by_dev_name(Meta::system(1 << 100, 1), "soak-bot-1").unwrap();
    let hero = helper.heroes(account, false).unwrap()[0].id;
    let before = held(&helper, hero);
    assert!(before.1 > 0);
    // A second outing: she fights and is not yet banked when the process is killed.
    let mut gw = GatewayClient::connect(&addr).unwrap();
    assert!(matches!(gw.login("soak-bot-1").unwrap(), Resp::Login { .. }));
    let ticket = loop {
        match gw.call(Req::FieldTicket { hero, field: 0 }).unwrap() {
            Resp::Err { .. } => std::thread::sleep(Duration::from_millis(200)),
            r => break r,
        }
    };
    let Resp::Ticket { host, port, ticket, .. } = ticket else { panic!("no ticket") };
    eprintln!("{:?} ticket", t0.elapsed());
    let killer = std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(12));
        child.kill().unwrap();
        child.wait().unwrap();
    });
    let play = PlayOpts { bank: false, max_ticks: 20 * 60, ..PlayOpts::default() };
    // The bot's lockstep clock stops with the server, so it is left to the process's end.
    std::thread::spawn(move || {
        let _ = play_field(&mut gw, &host, port, ticket, &play);
    });
    killer.join().unwrap();
    // The store, reopened cold: nothing banked is gone, and it verifies.
    eprintln!("{:?} killed", t0.elapsed());
    drop(helper);
    let store = SqliteStore::open(&db).unwrap();
    let after = held(&store, hero);
    assert!(after.0 >= before.0 && after.1 >= before.1, "{before:?} -> {after:?}");
    let rep = store.verify().unwrap();
    assert!(rep.problems.is_empty(), "{:?}", rep.problems);
    drop(store);
    // A restarted server takes her back.
    let (mut again, addr) = spawn(&db);
    let mut gw = GatewayClient::connect(&addr).unwrap();
    assert!(matches!(gw.login("soak-bot-1").unwrap(), Resp::Login { .. }));
    let heroes = gw.heroes().unwrap();
    assert!(heroes.iter().any(|h| h.id == hero && h.class_xp >= before.1));
    assert!(matches!(gw.call(Req::EnterTown { hero }).unwrap(), Resp::Town { .. }));
    again.kill().unwrap();
    again.wait().unwrap();
    for f in files(&db) {
        let _ = std::fs::remove_file(f);
    }
}

//! Transport security (`docs/realm/wire.md`, "Transport security"): the gateway's TLS (the right certificate
//! works; a wrong, an expired one and a plain-text client are refused with a clear error), a whole login, town and
//! field ticket over TLS, and the field socket's proof of a ticket (a HELLO without the ticket's key, a replayed
//! HELLO from another address, and INPUT or BYE without the session token are all dropped).

use realm_gateway::client::GatewayClient;
use realm_gateway::gateway::{Config, Gateway};
use realm_gateway::proto::*;
use realm_gateway::tls::{self, rustls::ClientConfig, ClientTls};
use realm_server::client::LockstepClient;
use realm_server::host::HostOpts;
use realm_server::sim::SimOpts;
use realm_store::*;
use std::io::{Read, Write};
use std::net::{TcpStream, UdpSocket};
use std::sync::Arc;
use std::time::{Duration, Instant};

struct World {
    gw: Arc<Gateway>,
    addr: String,
    _l: realm_gateway::conn::Listener,
    db: std::path::PathBuf,
}

impl Drop for World {
    fn drop(&mut self) {
        self.gw.shutdown();
        let _ = std::fs::remove_file(&self.db);
    }
}

fn world(name: &str, server_tls: Option<tls::ServerTls>) -> World {
    let db = std::env::temp_dir().join(format!("realm-tls-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&db);
    let store = Arc::new(SqliteStore::open(&db).unwrap());
    let gw = Gateway::start(store, Config { dev_login: true, secret: 9, ..Config::default() });
    // No monsters: nothing but her own inputs may move her.
    let sim = SimOpts { field: 0, seed: 3, monsters: 0, threads: 1, bots: 0, rally_permille: 0, level: 0, vault: None };
    gw.add_host(HostOpts { sim, port: 0, ..HostOpts::default() }).unwrap();
    let l = realm_gateway::conn::listen_tls(gw.clone(), "127.0.0.1:0", server_tls).unwrap();
    World { gw, addr: l.addr.to_string(), _l: l, db }
}

fn pair(from: (i32, u8, u8), until: (i32, u8, u8)) -> (tls::ServerTls, Arc<ClientConfig>) {
    let d = tls::make_cert(&tls::dev_names(""), from, until).unwrap();
    (tls::server_config_pem(d.cert_pem.as_bytes(), d.key_pem.as_bytes()).unwrap(), tls::client_config_ca_pem(d.cert_pem.as_bytes()).unwrap())
}

fn err_of(r: std::io::Result<GatewayClient>) -> String {
    match r {
        Ok(_) => panic!("the connection should have been refused"),
        Err(e) => e.to_string(),
    }
}

#[test]
fn the_right_certificate_is_taken_and_wrong_expired_or_plain_ones_are_refused() {
    let d = tls::make_cert(&tls::dev_names(""), (2026, 1, 1), (2036, 1, 1)).unwrap();
    let server = tls::server_config_pem(d.cert_pem.as_bytes(), d.key_pem.as_bytes()).unwrap();
    let w = world("certs", Some(server));
    // The right certificate, trusted from a file as `--ca=PATH` does: a login works, and more over one connection.
    let pem = w.db.with_extension("ca.pem");
    std::fs::write(&pem, &d.cert_pem).unwrap();
    let mut right = ClientTls::default();
    assert!(right.flag("--ca", pem.to_str().unwrap()));
    let mut c = GatewayClient::connect_with(&w.addr, right.config().unwrap().as_ref()).unwrap();
    assert!(matches!(c.login("ann").unwrap(), Resp::Login { .. }));
    assert_eq!(c.heroes().unwrap(), vec![]);
    // By name as well as by address: the dev certificate names localhost.
    let by_name = w.addr.replace("127.0.0.1", "localhost");
    let mut c = GatewayClient::connect_with(&by_name, right.config().unwrap().as_ref()).unwrap();
    assert!(matches!(c.login("ann").unwrap(), Resp::Login { .. }));
    // A certificate the client was not told to trust (another dev certificate, same name and subject, another
    // key): refused, as its signature is not the trusted one's.
    std::fs::write(&pem, tls::make_cert(&tls::dev_names(""), (2026, 1, 1), (2036, 1, 1)).unwrap().cert_pem).unwrap();
    let e = err_of(GatewayClient::connect_with(&w.addr, right.config().unwrap().as_ref()));
    assert!(e.contains("TLS handshake") && e.contains("invalid peer certificate: BadSignature"), "{e}");
    let _ = std::fs::remove_file(&pem);
    // The public roots (plain `--tls`) do not know a dev certificate either.
    let e = err_of(GatewayClient::connect_with(&w.addr, Some(&tls::client_config_public())));
    assert!(e.contains("UnknownIssuer"), "{e}");
    // `--insecure-dev` takes any certificate (and still encrypts); never the default.
    let mut c = GatewayClient::connect_with(&w.addr, Some(&tls::insecure_config())).unwrap();
    assert!(matches!(c.login("bob").unwrap(), Resp::Login { .. }));

    // A trusted certificate for another name: refused.
    let other = tls::make_cert(&["realm.example"], (2026, 1, 1), (2036, 1, 1)).unwrap();
    let named = world("named", Some(tls::server_config_pem(other.cert_pem.as_bytes(), other.key_pem.as_bytes()).unwrap()));
    let e = err_of(GatewayClient::connect_with(&named.addr, Some(&tls::client_config_ca_pem(other.cert_pem.as_bytes()).unwrap())));
    assert!(e.contains("TLS handshake") && e.contains("not valid for name"), "{e}");

    // A plain-text client at a TLS gateway gets one clear error and the door.
    let mut p = GatewayClient::connect(&w.addr).unwrap();
    match p.login("eve").unwrap() {
        Resp::Err { code, msg } => assert!(code == code::REFUSED && msg.contains("TLS only"), "{code} {msg}"),
        r => panic!("plain text was served: {r:?}"),
    }
    assert!(p.call(Req::ListHeroes).is_err(), "and the connection is closed");

    // An expired certificate: refused, and the error says why.
    let (server, client) = pair((2000, 1, 1), (2001, 1, 1));
    let old = world("expired", Some(server));
    let e = err_of(GatewayClient::connect_with(&old.addr, Some(&client)));
    assert!(e.contains("TLS handshake") && e.contains("certificate expired"), "{e}");

    // A TLS client at a plain gateway: a clear handshake error, never a silent fall back to plain text.
    let plain = world("plain", None);
    let (_, client) = pair((2026, 1, 1), (2036, 1, 1));
    let e = err_of(GatewayClient::connect_with(&plain.addr, Some(&client)));
    assert!(e.contains("TLS handshake"), "{e}");
}

#[test]
fn garbage_and_a_stalled_handshake_do_not_hold_the_gateway() {
    let (server, client) = pair((2026, 1, 1), (2036, 1, 1));
    let w = world("garbage", Some(server));
    // A handshake record of nonsense is closed; a client that opens and says nothing is no bother to others.
    let mut g = TcpStream::connect(&w.addr).unwrap();
    g.write_all(&[0x16, 0x03, 0x01, 0x00, 0x05, 1, 2, 3, 4, 5]).unwrap();
    g.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
    let mut b = [0u8; 64];
    let n = g.read(&mut b).unwrap_or(0);
    assert!(n == 0 || b[0] == 0x15, "an alert or the end, nothing else");
    let _idle = TcpStream::connect(&w.addr).unwrap();
    let mut c = GatewayClient::connect_with(&w.addr, Some(&client)).unwrap();
    assert!(matches!(c.login("ann").unwrap(), Resp::Login { .. }));
}

/// Plays her field client until `until` holds or `secs` pass: HELLO until welcomed, then a standing INPUT every
/// 20 ms (sealed by the client), and `extra` datagrams each round from the same socket.
fn run(sock: &UdpSocket, lc: &mut LockstepClient, secs: u64, mut extra: impl FnMut(&LockstepClient) -> Vec<Vec<u8>>, mut until: impl FnMut(&LockstepClient) -> bool) -> bool {
    let end = Instant::now() + Duration::from_secs(secs);
    let mut buf = [0u8; 2048];
    while Instant::now() < end {
        if !lc.welcomed() {
            let _ = sock.send(&lc.hello());
        }
        while let Ok(k) = sock.recv(&mut buf) {
            lc.receive(&buf[..k]);
        }
        lc.apply();
        if lc.welcomed() {
            let _ = sock.send(&lc.input_word(0));
            for d in extra(lc) {
                let _ = sock.send(&d);
            }
        }
        if until(lc) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    false
}

fn udp(port: u16) -> UdpSocket {
    let s = UdpSocket::bind("127.0.0.1:0").unwrap();
    s.connect(("127.0.0.1", port)).unwrap();
    s.set_nonblocking(true).unwrap();
    s
}

/// Anything the host sends to `s` within `ms`.
fn heard(s: &UdpSocket, ms: u64) -> usize {
    let end = Instant::now() + Duration::from_millis(ms);
    let mut buf = [0u8; 2048];
    let mut n = 0;
    while Instant::now() < end {
        while s.recv(&mut buf).is_ok() {
            n += 1;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    n
}

#[test]
fn login_town_and_a_field_over_tls_and_the_field_takes_only_proven_packets() {
    let (server, client) = pair((2026, 1, 1), (2036, 1, 1));
    let w = world("flow", Some(server));
    let mut c = GatewayClient::connect_with(&w.addr, Some(&client)).unwrap();
    assert!(matches!(c.login("ann").unwrap(), Resp::Login { .. }));
    let h = match c.call(Req::CreateHero { name: "Annie".into(), race: 1, class: 1, look: 4, self_found: false }).unwrap() {
        Resp::HeroCreated(id) => id,
        r => panic!("{r:?}"),
    };
    assert!(matches!(c.call(Req::EnterTown { hero: h }).unwrap(), Resp::Town { .. }));
    let chat = c.call(Req::Chat { text: "over tls".into() }).unwrap();
    assert!(matches!(chat, Resp::Ok), "{chat:?}");
    let Resp::Ticket { host, port, ticket, key, .. } = c.call(Req::FieldTicket { hero: h, field: 0 }).unwrap() else { panic!("no ticket") };
    assert!(host.is_empty() && port > 0 && ticket != 0 && key != [0; 16]);

    // A stranger who knows the ticket number but not its key: no WELCOME, and the ticket is not spent.
    let eve = udp(port);
    let mut wrong = key;
    wrong[0] ^= 1;
    let _ = eve.send(&realm_server::hello_ticket(realm_server::PROTO_BP, 0, 0, ticket, Some(&wrong)));
    let _ = eve.send(&realm_server::hello_ticket(realm_server::PROTO_BP, 0, 0, ticket, None));
    // Nor does a follower get the state stream of a ticketed field.
    let _ = eve.send(&realm_server::hello(realm_server::PROTO_B, 0, 0));
    assert_eq!(heard(&eve, 400), 0, "a HELLO without the key is dropped");

    // Her client proves the ticket and joins.
    let sock = udp(port);
    let mut lc = LockstepClient::with_ticket(ticket, key, 1);
    assert!(run(&sock, &mut lc, 20, |_| Vec::new(), |lc| lc.hero_player().is_some()), "she joined with the key");
    let first = realm_server::hello_ticket(realm_server::PROTO_BP, 0, 0, ticket, Some(&key));

    // Her first packet replayed from another address: dropped (the ticket is spent, and bound to her address).
    let mallory = udp(port);
    for _ in 0..5 {
        let _ = mallory.send(&first);
    }
    assert_eq!(heard(&mallory, 400), 0, "a replayed HELLO from another address is dropped");

    // Forged inputs that would walk her: bare ones, ones sealed with a wrong token, from her own address and from
    // another one, and a BYE of each kind. She stands still and stays.
    let at = lc.hero_player().map(|p| (p.x, p.y)).unwrap();
    let walk = |lc: &LockstepClient, token: u64| -> Vec<Vec<u8>> {
        let seq = 1_000_000 + lc.tick();
        let words = [3u16, 3, 3, 3];
        vec![realm_server::input_seq(lc.tick(), seq, &words), realm_server::seal(token, &realm_server::input_seq(lc.tick(), seq, &words)), vec![realm_server::MSG_BYE], realm_server::seal(token, &[realm_server::MSG_BYE])]
    };
    let ticks0 = lc.tick();
    run(&sock, &mut lc, 2, |lc| walk(lc, 0x1234_5678), |_| false);
    for d in walk(&lc, 0x1234_5678) {
        let _ = mallory.send(&d);
    }
    run(&sock, &mut lc, 1, |_| Vec::new(), |_| false);
    assert!(lc.tick() > ticks0 + 20, "the field ran meanwhile");
    assert_eq!(lc.hero_player().map(|p| (p.x, p.y)), Some(at), "no forged input moved her and no forged BYE took her out");
    assert!(w.gw.is_placed(h));
    assert!(w.gw.host_loads().iter().any(|l| l.2 == 1), "she is still in the field");

    // Her own sealed BYE ends the outing.
    let _ = sock.send(&lc.bye());
    let done = c.wait_push(Duration::from_secs(10), |r| matches!(r, Resp::Outing { hero, .. } if *hero == h).then_some(())).unwrap();
    assert!(done.is_some(), "her sealed BYE took her out");
}

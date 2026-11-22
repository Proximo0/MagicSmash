//! Transport security (`docs/realm/wire.md`, "Transport security"): the gateway's TLS (the right certificate
//! works; a wrong, an expired one and a plain-text client are refused with a clear error), a whole login, town and
//! field ticket over TLS, a frame near FRAME_MAX over TLS, the handshake's total deadline, a plain gateway's first
//! bytes, the secrets on disk, and the field socket's proof of a ticket (a HELLO without proof of the key, a replayed
//! HELLO from another address, INPUT or BYE with a wrong tag or a replayed counter are all dropped).

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
    // The default client is TLS against the public roots, which do not know a dev certificate: refused, never a
    // plain fall back. Plain text only when asked (`--plain`); `--insecure-dev` does not exist in this build.
    let e = err_of(GatewayClient::connect(&w.addr));
    assert!(e.contains("TLS handshake") && e.contains("UnknownIssuer"), "{e}");
    assert!(ClientTls::default().config().unwrap().is_some(), "TLS by default");
    let mut plain = ClientTls::default();
    assert!(plain.flag("--plain", ""));
    assert!(plain.config().unwrap().is_none());
    assert!(!ClientTls::default().flag("--insecure-dev", ""), "no --insecure-dev without the dev-insecure feature");

    // A trusted certificate for another name: refused.
    let other = tls::make_cert(&["realm.example"], (2026, 1, 1), (2036, 1, 1)).unwrap();
    let named = world("named", Some(tls::server_config_pem(other.cert_pem.as_bytes(), other.key_pem.as_bytes()).unwrap()));
    let e = err_of(GatewayClient::connect_with(&named.addr, Some(&tls::client_config_ca_pem(other.cert_pem.as_bytes()).unwrap())));
    assert!(e.contains("TLS handshake") && e.contains("not valid for name"), "{e}");

    // A plain-text client at a TLS gateway gets one clear error and the door.
    let mut p = GatewayClient::connect_plain(&w.addr).unwrap();
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
    // A ClientHello record of nonsense is closed; a client that opens and says nothing is no bother to others.
    let mut g = TcpStream::connect(&w.addr).unwrap();
    g.write_all(&[0x16, 0x03, 0x01, 0x00, 0x08, 0x01, 0, 0, 4, 0x03, 0x03, 9, 9]).unwrap();
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
    assert!(host.is_empty() && port > 0 && ticket != 0 && !key.is_zero());
    assert!(!format!("{:?}", Resp::Ticket { host: String::new(), port, ticket, field: 0, copy: 0, key }).contains(&format!("{:?}", key.0)), "Debug shows no key");

    // A stranger who knows the ticket number but not its key: no WELCOME, and the ticket is not spent.
    let eve = udp(port);
    let mut wrong = key;
    wrong.0[0] ^= 1;
    let _ = eve.send(&realm_server::hello_ticket(realm_server::PROTO_BP, 0, 0, ticket, Some((&wrong, 5))));
    let _ = eve.send(&realm_server::hello_ticket(realm_server::PROTO_BP, 0, 0, ticket, None));
    // Nor does a follower get the state stream of a ticketed field.
    let _ = eve.send(&realm_server::hello(realm_server::PROTO_B, 0, 0));
    assert_eq!(heard(&eve, 400), 0, "a HELLO without the key is dropped");

    // Her client proves the ticket and joins.
    let sock = udp(port);
    let mut lc = LockstepClient::with_ticket(ticket, key, 1);
    assert!(run(&sock, &mut lc, 20, |_| Vec::new(), |lc| lc.hero_player().is_some()), "she joined with the key");
    let first = lc.hello();
    assert!(!first.windows(16).any(|w| w == key.0), "the key itself never crosses UDP");

    // Her first packet replayed from another address: dropped (the ticket is spent, and bound to her address).
    let mallory = udp(port);
    for _ in 0..5 {
        let _ = mallory.send(&first);
    }
    assert_eq!(heard(&mallory, 400), 0, "a replayed HELLO from another address is dropped");

    // Forged inputs that would walk her: bare ones, ones sealed with a wrong key (any counter), ones with a right
    // tag but a counter she already used (a replay of her own datagram), from her own address and from another
    // one, and a BYE of each kind. She stands still and stays.
    let at = lc.hero_player().map(|p| (p.x, p.y)).unwrap();
    let walk = |lc: &LockstepClient| -> Vec<Vec<u8>> {
        let seq = 1_000_000 + lc.tick();
        let words = [3u16, 3, 3, 3];
        let i = realm_server::input_seq(lc.tick(), seq, &words);
        let bye = [realm_server::MSG_BYE];
        vec![i.clone(), realm_server::seal(&wrong, 4_000_000_000, &i), realm_server::seal(&key, 1, &i), bye.to_vec(), realm_server::seal(&wrong, 4_000_000_000, &bye), realm_server::seal(&key, 2, &bye)]
    };
    let ticks0 = lc.tick();
    run(&sock, &mut lc, 2, walk, |_| false);
    for d in walk(&lc) {
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

#[test]
fn a_frame_near_frame_max_crosses_tls_both_ways() {
    // rustls keeps at most 64 KiB unsent: a 900 KiB frame must go in pieces.
    let (server, client) = pair((2026, 1, 1), (2036, 1, 1));
    let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = l.local_addr().unwrap().to_string();
    let big: Vec<u8> = (0..900 * 1024).map(|i| (i * 7 % 251) as u8).collect();
    let sent = big.clone();
    let t = std::thread::spawn(move || {
        let (s, _) = l.accept().unwrap();
        assert!(tls::looks_like_tls(&s).unwrap());
        let d = tls::Duplex::tls(s, &server).unwrap();
        d.write_all(&sent).unwrap();
        let mut back = vec![0u8; sent.len()];
        d.reader().read_exact(&mut back).unwrap();
        back == sent
    });
    let mut c = tls::ClientStream::connect(&addr, Some(&client)).unwrap();
    let mut got = vec![0u8; big.len()];
    c.read_exact(&mut got).unwrap();
    assert!(got == big, "the server's 900 KiB arrived whole");
    c.write_all(&big).unwrap();
    c.flush().unwrap();
    assert!(t.join().unwrap(), "and the client's came back whole");
}

#[test]
fn a_handshake_that_drips_is_cut_off_at_the_total_deadline() {
    let (server, _) = pair((2026, 1, 1), (2036, 1, 1));
    let w = world("drip", Some(server));
    let mut g = TcpStream::connect(&w.addr).unwrap();
    // A ClientHello header promising 16 KiB, then a byte every 400 ms: each read is quick, the whole is not.
    g.write_all(&[0x16, 0x03, 0x01, 0x40, 0x00, 0x01, 0x00, 0x3f, 0xfc, 0x03, 0x03]).unwrap();
    g.set_read_timeout(Some(Duration::from_millis(400))).unwrap();
    let t0 = Instant::now();
    let mut b = [0u8; 64];
    let closed = loop {
        if t0.elapsed() > Duration::from_secs(16) {
            break false;
        }
        if g.write_all(&[7]).is_err() {
            break true;
        }
        match g.read(&mut b) {
            Ok(0) => break true,
            Ok(_) => {}
            Err(e) if matches!(e.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut) => {}
            Err(_) => break true,
        }
    };
    let took = t0.elapsed();
    assert!(closed && took >= Duration::from_secs(9) && took < Duration::from_secs(13), "closed after {took:?}");
}

#[test]
fn a_plain_gateway_bounds_its_wait_and_serves_a_frame_that_starts_like_tls() {
    let w = world("plainfirst", None);
    // A lone 0x16 and silence: closed by the deadline, not peeked at forever.
    let mut g = TcpStream::connect(&w.addr).unwrap();
    g.write_all(&[0x16]).unwrap();
    g.set_read_timeout(Some(Duration::from_secs(14))).unwrap();
    let t0 = Instant::now();
    let mut b = [0u8; 16];
    let n = g.read(&mut b);
    assert!(matches!(n, Ok(0)) || matches!(&n, Err(e) if e.kind() != std::io::ErrorKind::WouldBlock && e.kind() != std::io::ErrorKind::TimedOut), "{n:?}");
    assert!(t0.elapsed() < Duration::from_secs(13), "closed by the deadline, after {:?}", t0.elapsed());
    // A plain frame of 790 bytes starts 0x16 0x03 0x00 0x00: a request, answered, not taken for a ClientHello.
    let mut f = TcpStream::connect(&w.addr).unwrap();
    let body = vec![0u8; 790 - 5];
    f.write_all(&frame(0x7E, 1, &body)).unwrap();
    f.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
    let reply = read_frame(&mut f).unwrap().expect("a reply");
    assert_eq!(reply.1, 1, "the reply to tag 1");
}

#[test]
fn secrets_on_disk_are_random_private_and_kept() {
    let dir = std::env::temp_dir().join(format!("realm-tls-secrets-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    // DB.secret: 32 random bytes from the OS, 0600, read back the same; an old 16-digit file still reads as before.
    let p = dir.join("a.db.secret");
    let v = realm_gateway::gateway::load_secret(&p);
    let text = std::fs::read_to_string(&p).unwrap();
    assert_eq!(text.trim().len(), 64, "32 bytes in hex: {text:?}");
    assert_eq!(realm_gateway::gateway::load_secret(&p), v);
    let q = dir.join("b.db.secret");
    std::fs::write(&q, "00000000deadbeef\n").unwrap();
    assert_eq!(realm_gateway::gateway::load_secret(&q), 0xdead_beef);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = |p: &std::path::Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(&p), 0o600, "DB.secret is the owner's only");
        // write_private tightens a file that was there before, loose.
        let k = dir.join("loose.pem");
        std::fs::write(&k, "x").unwrap();
        std::fs::set_permissions(&k, std::fs::Permissions::from_mode(0o644)).unwrap();
        tls::write_private(&k, b"secret").unwrap();
        assert_eq!(mode(&k), 0o600);
    }
    // The dev pair is kept while its names hold, and made again for a new --public-host.
    let db = dir.join("c.db").to_string_lossy().to_string();
    let (cert, _) = tls::dev_cert_files(&db, "").unwrap();
    let first = std::fs::read_to_string(&cert).unwrap();
    tls::dev_cert_files(&db, "").unwrap();
    assert_eq!(std::fs::read_to_string(&cert).unwrap(), first, "kept");
    let (cert, key) = tls::dev_cert_files(&db, "realm.example").unwrap();
    let second = std::fs::read_to_string(&cert).unwrap();
    assert_ne!(second, first, "a new --public-host makes a new certificate");
    // It names the new host: a client that trusts it may connect by that name (checked by rustls below).
    let server = tls::server_config(&cert, &key).unwrap();
    let w = world("devnames", Some(server));
    let ca = tls::client_config_ca_pem(second.as_bytes()).unwrap();
    assert!(GatewayClient::connect_with(&w.addr, Some(&ca)).is_ok(), "loopback is still named");
    let _ = std::fs::remove_dir_all(&dir);
}

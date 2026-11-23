//! Replies slower than `GatewayClient::fill`'s 200 ms poll must still arrive. A fake gateway (a plain std
//! listener) answers each Ping with a Pong after a delay that sweeps across the 200 ms boundary, some replies
//! split in two writes with a pause between. A reply lost around a read timeout (suspected on Windows, where a
//! timed-out blocking recv leaves the socket in an indeterminate state) shows here as a call over 5 s.

use realm_gateway::client::GatewayClient;
use realm_gateway::proto::{read_frame, resp_frame, Req, Resp};
use std::io::Write;
use std::net::TcpListener;
use std::time::{Duration, Instant};

/// One reply plan: wait `delay_ms`, write the first `split` bytes (all when `split` is 0), wait `pause_ms`, write
/// the rest.
#[derive(Clone, Copy, Debug)]
struct Plan {
    delay_ms: u64,
    split: usize,
    pause_ms: u64,
}

fn plans() -> Vec<Plan> {
    let mut v = Vec::new();
    // A few quick replies first, so a broken setup fails before the slow part.
    for _ in 0..4 {
        v.push(Plan { delay_ms: 0, split: 0, pause_ms: 0 });
    }
    // The sweep: 150..450 ms in 3 ms steps.
    for d in (150..450).step_by(3) {
        v.push(Plan { delay_ms: d, split: 0, pause_ms: 0 });
    }
    // Right on the poll boundaries, give or take a few ms.
    for k in [200u64, 400] {
        for off in -6i64..=6 {
            v.push(Plan { delay_ms: (k as i64 + off) as u64, split: 0, pause_ms: 0 });
        }
    }
    // Split replies (a Pong frame is 9 bytes): the cut moves through the header, the pause crosses 200 ms.
    for i in 0..40u64 {
        v.push(Plan { delay_ms: 150 + (i * 7) % 60, split: 1 + (i as usize % 8), pause_ms: 170 + (i * 11) % 70 });
    }
    v
}

#[test]
fn replies_slower_than_the_poll_all_arrive() {
    sweep(plans());
}

fn sweep(plans: Vec<Plan>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let server_plans = plans.clone();
    let server = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().unwrap();
        s.set_nodelay(true).unwrap();
        for (i, p) in server_plans.iter().enumerate() {
            let Some((t, tag, body)) = read_frame(&mut s).unwrap() else { panic!("client closed before call {i}") };
            assert_eq!(Req::decode(t, &body), Some(Req::Ping), "call {i}: request");
            std::thread::sleep(Duration::from_millis(p.delay_ms));
            let f = resp_frame(tag, &Resp::Pong);
            if p.split == 0 || p.split >= f.len() {
                s.write_all(&f).unwrap();
            } else {
                s.write_all(&f[..p.split]).unwrap();
                s.flush().unwrap();
                std::thread::sleep(Duration::from_millis(p.pause_ms));
                s.write_all(&f[p.split..]).unwrap();
            }
        }
    });

    let mut c = GatewayClient::connect_plain(&addr).unwrap();
    c.set_call_deadline(Duration::from_secs(5));
    let t0 = Instant::now();
    for (i, p) in plans.iter().enumerate() {
        let start = Instant::now();
        let r = c.call(Req::Ping);
        let took = start.elapsed();
        match r {
            Ok(Resp::Pong) => {}
            Ok(other) => panic!("call {i} of {} ({p:?}): wrong reply {other:?} after {took:?}", plans.len()),
            Err(e) => panic!("call {i} of {} ({p:?}): {e} after {took:?} (reply lost?)", plans.len()),
        }
        assert!(took < Duration::from_secs(5), "call {i} of {} ({p:?}) took {took:?}", plans.len());
    }
    assert!(c.pushes.is_empty(), "unexpected pushes: {:?}", c.pushes);
    drop(c);
    server.join().unwrap();
    println!("slow_reply: {} calls ok in {:?}", plans.len(), t0.elapsed());
}

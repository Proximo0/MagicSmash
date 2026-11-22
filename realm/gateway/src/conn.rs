//! The gateway's TCP side: an accept loop, and two threads a connection (a reader that answers requests, a
//! writer that sends replies and everything the server pushes). Threads, not an event loop: at the closed
//! test's size (hundreds of connections) that is plenty, and `Gateway::handle` does not care.

use crate::gateway::{Gateway, Session};
use crate::proto::*;
use std::io::ErrorKind;
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::channel;
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::Duration;

pub struct Listener {
    pub addr: SocketAddr,
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl Listener {
    pub fn stop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

impl Drop for Listener {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Starts accepting connections on `addr` (port 0 picks a free one).
pub fn listen(gw: Arc<Gateway>, addr: &str) -> std::io::Result<Listener> {
    let l = TcpListener::bind(addr)?;
    l.set_nonblocking(true)?;
    let addr = l.local_addr()?;
    let stop = Arc::new(AtomicBool::new(false));
    let st = stop.clone();
    let thread = std::thread::Builder::new().name("accept".into()).spawn(move || {
        while !st.load(Ordering::Relaxed) {
            match l.accept() {
                Ok((s, peer)) => {
                    if !realm_ops::flood::allow_connect(peer.ip()) {
                        continue;
                    }
                    let gw = gw.clone();
                    let _ = std::thread::Builder::new().name("conn".into()).spawn(move || {
                        let ip = s.peer_addr().map(|a| a.ip());
                        serve(gw, s, ip.as_ref().ok().copied());
                        if let Ok(ip) = ip {
                            realm_ops::flood::connection_closed(ip);
                        }
                    });
                }
                Err(e) if e.kind() == ErrorKind::WouldBlock => std::thread::sleep(Duration::from_millis(10)),
                Err(e) => {
                    eprintln!("realm-gateway: accept: {e}");
                    std::thread::sleep(Duration::from_millis(100));
                }
            }
        }
    })?;
    Ok(Listener { addr, stop, thread: Some(thread) })
}

fn serve(gw: Arc<Gateway>, stream: TcpStream, peer: Option<std::net::IpAddr>) {
    let _ = stream.set_nodelay(true);
    let _ = stream.set_nonblocking(false);
    let Ok(mut wr) = stream.try_clone() else { return };
    let (out, rx) = channel::<Vec<u8>>();
    let writer = std::thread::spawn(move || {
        for f in rx {
            // An empty frame is the moderators' "end this connection" (social::modtools::end_sessions).
            if f.is_empty() || write_all(&mut wr, &f).is_err() {
                break;
            }
        }
        let _ = wr.shutdown(std::net::Shutdown::Both);
    });
    let mut s = Session::new(gw.conn_id(), out.clone());
    let mut rd = stream;
    loop {
        let (t, tag, body) = match read_frame(&mut rd) {
            Ok(Some(f)) => f,
            _ => break,
        };
        if peer.is_some_and(|ip| !realm_ops::flood::allow_frame(ip)) {
            break;
        }
        let resp = match Req::decode(t, &body) {
            Some(req) => gw.handle(&mut s, req),
            None => Resp::Err { code: code::BAD_REQUEST, msg: "unreadable request".into() },
        };
        if out.send(resp_frame(tag, &resp)).is_err() {
            break;
        }
    }
    gw.close_session(&mut s);
    drop(s);
    drop(out);
    // The writer ends by itself once the last sender (a town room, a field ticket) lets go.
    drop(writer);
}

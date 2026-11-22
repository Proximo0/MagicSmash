//! The gateway's TCP side: an accept loop, and two threads a connection (a reader that answers requests, a
//! writer that sends replies and everything the server pushes). Threads, not an event loop: at the closed
//! test's size (hundreds of connections) that is plenty, and `Gateway::handle` does not care. With TLS
//! (`listen_tls`) both threads share one `tls::Duplex` (why: `tls.rs`); the frames are the same either way.

use crate::gateway::{Gateway, Session};
use crate::proto::*;
use crate::tls::{Duplex, ServerTls};
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

/// Starts accepting plain-text connections on `addr` (port 0 picks a free one): tests and dev only.
pub fn listen(gw: Arc<Gateway>, addr: &str) -> std::io::Result<Listener> {
    listen_tls(gw, addr, None)
}

/// Starts accepting connections on `addr`, TLS only when `tls` is given.
pub fn listen_tls(gw: Arc<Gateway>, addr: &str, tls: Option<ServerTls>) -> std::io::Result<Listener> {
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
                    let tls = tls.clone();
                    let _ = std::thread::Builder::new().name("conn".into()).spawn(move || {
                        let ip = s.peer_addr().map(|a| a.ip());
                        if let Some(d) = open(s, tls.as_ref()) {
                            serve(gw, d, ip.as_ref().ok().copied());
                        }
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

/// The connection as a `Duplex`: plain, or after the TLS handshake. A plain-text client at a TLS gateway gets one
/// plain frame saying so (an error reply to its first request) and is closed; a failed handshake is closed; a
/// TLS client at a plain gateway is closed.
fn open(stream: TcpStream, tls: Option<&ServerTls>) -> Option<Duplex> {
    let _ = stream.set_nodelay(true);
    let _ = stream.set_nonblocking(false);
    let Some(cfg) = tls else {
        // A TLS client at a plain gateway is closed at once, so it fails its handshake instead of waiting.
        return match crate::tls::looks_like_tls(&stream, None) {
            Ok(false) => Duplex::plain(stream).ok(),
            _ => None,
        };
    };
    match crate::tls::looks_like_tls(&stream, Some(crate::tls::HANDSHAKE_TIMEOUT)) {
        Ok(true) => Duplex::tls(stream, cfg).ok(),
        Ok(false) => {
            let mut s = stream;
            let _ = s.set_read_timeout(Some(crate::tls::HANDSHAKE_TIMEOUT));
            let tag = read_frame(&mut s).ok().flatten().map_or(0, |f| f.1);
            let msg = "this gateway speaks TLS only: connect with TLS (bots: --tls, --ca=PEM)".to_string();
            let _ = write_all(&mut s, &resp_frame(tag, &Resp::Err { code: code::REFUSED, msg }));
            let _ = s.shutdown(std::net::Shutdown::Both);
            None
        }
        Err(_) => None,
    }
}

fn serve(gw: Arc<Gateway>, conn: Duplex, peer: Option<std::net::IpAddr>) {
    let conn = Arc::new(conn);
    let wr = conn.clone();
    let (out, rx) = channel::<Vec<u8>>();
    let writer = std::thread::spawn(move || {
        for f in rx {
            // An empty frame is the moderators' "end this connection" (social::modtools::end_sessions).
            if f.is_empty() || wr.write_all(&f).is_err() {
                break;
            }
        }
        wr.shutdown();
    });
    let mut s = Session::new(gw.conn_id(), out.clone());
    let mut rd = conn.reader();
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

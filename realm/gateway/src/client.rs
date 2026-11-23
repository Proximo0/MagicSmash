//! A blocking gateway client: what the bots, the tests and (in step with the Godot module later) a client
//! use to speak the TCP side, plain or over TLS (`tls::ClientStream`). It keeps what the server pushes
//! (snapshots, chat, outing results) in `pushes`.

use crate::proto::*;
use crate::tls::{rustls::ClientConfig, ClientStream};
use std::collections::VecDeque;
use std::io::{ErrorKind, Read, Write};
use std::sync::Arc;
use std::time::{Duration, Instant};

pub struct GatewayClient {
    stream: ClientStream,
    buf: Vec<u8>,
    tag: u32,
    /// Unsolicited messages, oldest first.
    pub pushes: VecDeque<Resp>,
    /// The address the gateway was reached at (the field host's address when the ticket names none).
    pub peer_ip: String,
    /// Microseconds each `call` took from sending to its reply (the LAN rehearsal's round trips).
    pub rtts_us: Vec<u32>,
    /// How long `call` waits for its reply (30 s; tests shorten it with `set_call_deadline`).
    call_deadline: Duration,
}

impl GatewayClient {
    /// TLS, the gateway's certificate checked against the public roots and the name in `addr`: the default.
    pub fn connect(addr: &str) -> std::io::Result<GatewayClient> {
        GatewayClient::connect_with(addr, Some(&crate::tls::client_config_public()))
    }

    /// Plain TCP, only for a `--plain`/`--dev-login` gateway (the in-process tests).
    pub fn connect_plain(addr: &str) -> std::io::Result<GatewayClient> {
        GatewayClient::connect_with(addr, None)
    }

    /// TLS when `tls` is given (`tls::ClientTls::config`), plain TCP for None: the handshake runs here, so a refused
    /// certificate is this call's error.
    pub fn connect_with(addr: &str, tls: Option<&Arc<ClientConfig>>) -> std::io::Result<GatewayClient> {
        let stream = ClientStream::connect(addr, tls)?;
        let peer_ip = stream.tcp().peer_addr().map(|a| a.ip().to_string()).unwrap_or_default();
        Ok(GatewayClient { stream, buf: Vec::new(), tag: 0, pushes: VecDeque::new(), peer_ip, rtts_us: Vec::new(), call_deadline: Duration::from_secs(30) })
    }

    /// Test hook: how long `call` waits for a reply before `TimedOut` (default 30 s).
    #[doc(hidden)]
    pub fn set_call_deadline(&mut self, d: Duration) {
        self.call_deadline = d;
    }

    /// Reads what has arrived, waiting at most `wait`; `Ok(false)` when the server closed the connection.
    fn fill(&mut self, wait: Duration) -> std::io::Result<bool> {
        self.stream.tcp().set_read_timeout(Some(wait.max(Duration::from_millis(1))))?;
        let mut tmp = [0u8; 16 * 1024];
        match self.stream.read(&mut tmp) {
            Ok(0) => Ok(false),
            Ok(n) => {
                self.buf.extend_from_slice(&tmp[..n]);
                Ok(true)
            }
            // Windows can report a read timeout as ERROR_IO_PENDING (997, "overlapped I/O is in progress").
            Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut | ErrorKind::Interrupted) || e.raw_os_error() == Some(997) => Ok(true),
            Err(e) => Err(e),
        }
    }

    /// The next whole frame in the buffer, if any.
    fn next_frame(&mut self) -> std::io::Result<Option<(u8, u32, Vec<u8>)>> {
        if self.buf.len() < 4 {
            return Ok(None);
        }
        let len = u32::from_le_bytes([self.buf[0], self.buf[1], self.buf[2], self.buf[3]]) as usize;
        if !(5..=FRAME_MAX).contains(&len) {
            return Err(std::io::Error::new(ErrorKind::InvalidData, "bad frame length"));
        }
        if self.buf.len() < 4 + len {
            return Ok(None);
        }
        let t = self.buf[4];
        let tag = u32::from_le_bytes([self.buf[5], self.buf[6], self.buf[7], self.buf[8]]);
        let body = self.buf[9..4 + len].to_vec();
        self.buf.drain(..4 + len);
        Ok(Some((t, tag, body)))
    }

    /// Sends a request and waits for its reply (pushes that arrive meanwhile are kept).
    pub fn call(&mut self, req: Req) -> std::io::Result<Resp> {
        self.tag += 1;
        let tag = self.tag;
        let sent = Instant::now();
        let (t, body) = req.encode();
        self.stream.write_all(&frame(t, tag, &body))?;
        let deadline = Instant::now() + self.call_deadline;
        loop {
            while let Some((t, got, body)) = self.next_frame()? {
                let r = Resp::decode(t, &body).ok_or_else(|| std::io::Error::new(ErrorKind::InvalidData, "unreadable reply"))?;
                if got == tag {
                    self.rtts_us.push(sent.elapsed().as_micros().min(u32::MAX as u128) as u32);
                    return Ok(r);
                }
                self.pushes.push_back(r);
            }
            if Instant::now() > deadline {
                return Err(std::io::Error::new(ErrorKind::TimedOut, "no reply"));
            }
            if !self.fill(Duration::from_millis(200))? {
                return Err(std::io::Error::new(ErrorKind::UnexpectedEof, "the gateway closed the connection"));
            }
        }
    }

    /// Reads whatever the server pushed, waiting at most `wait` for the first.
    pub fn poll(&mut self, wait: Duration) -> std::io::Result<()> {
        if self.next_frame_into_pushes()? {
            return Ok(());
        }
        self.fill(wait)?;
        self.next_frame_into_pushes()?;
        Ok(())
    }

    fn next_frame_into_pushes(&mut self) -> std::io::Result<bool> {
        let mut any = false;
        while let Some((t, _, body)) = self.next_frame()? {
            if let Some(r) = Resp::decode(t, &body) {
                self.pushes.push_back(r);
                any = true;
            }
        }
        Ok(any)
    }

    /// Waits up to `wait` for a push that `pick` accepts; other pushes stay queued in order.
    pub fn wait_push<T>(&mut self, wait: Duration, mut pick: impl FnMut(&Resp) -> Option<T>) -> std::io::Result<Option<T>> {
        let end = Instant::now() + wait;
        loop {
            if let Some(i) = self.pushes.iter().position(|r| pick(r).is_some()) {
                let r = self.pushes.remove(i).unwrap();
                return Ok(pick(&r));
            }
            let left = end.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return Ok(None);
            }
            self.poll(left.min(Duration::from_millis(100)))?;
        }
    }

    // ---- the calls a client makes most

    pub fn login(&mut self, name: &str) -> std::io::Result<Resp> {
        self.call(Req::LoginDev { name: name.into() })
    }

    pub fn heroes(&mut self) -> std::io::Result<Vec<HeroInfo>> {
        match self.call(Req::ListHeroes)? {
            Resp::Heroes(v) => Ok(v),
            r => Err(std::io::Error::new(ErrorKind::InvalidData, format!("{r:?}"))),
        }
    }

    pub fn inventory(&mut self, hero: i64) -> std::io::Result<Inventory> {
        match self.call(Req::Inventory { hero })? {
            Resp::Inventory(i) => Ok(i),
            r => Err(std::io::Error::new(ErrorKind::InvalidData, format!("{r:?}"))),
        }
    }
}

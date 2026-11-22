//! Transport security for the gateway's TCP side (`docs/realm/wire.md`, "Transport security"): rustls on the ring
//! provider, no async runtime. The server wraps each accepted socket in a `Duplex` so `conn.rs` reads and writes the
//! same frames with or without TLS; the blocking clients (bots, tests, tools) use `ClientStream`.
//!
//! Why a lock and a peek: a rustls session is one state machine for both directions, so the connection's reader
//! thread and writer thread cannot each own half of it. The reader waits for bytes with `TcpStream::peek` on a
//! clone of the socket, holding no lock, then takes the session's lock only to pull in what has arrived; the writer
//! takes the same lock to encrypt and send a frame. Neither waits on the network while holding the lock except a
//! write to a peer that does not read (which only stalls that peer's own connection). A reader thread and a write
//! queue in one thread would need a read timeout to look at the queue, which costs latency or CPU on every
//! connection; the peek costs neither.

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{verify_tls12_signature, verify_tls13_signature, CryptoProvider};
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime};
use rustls::{ClientConfig, ClientConnection, DigitallySignedStruct, RootCertStore, ServerConfig, ServerConnection, SignatureScheme, StreamOwned};
use std::io::{self, ErrorKind, Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub use rustls;

/// A TLS handshake (either side) that takes longer than this is given up.
pub const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);

fn provider() -> Arc<CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

/// Fills `b` from the operating system's secure random source (through ring). Panics if there is none, as a
/// server that cannot make secrets must not run.
pub fn fill_random(b: &mut [u8]) {
    provider().secure_random.fill(b).expect("the system's secure random source failed");
}

/// 128 random bits: a field ticket's key.
pub fn random_key() -> [u8; 16] {
    let mut k = [0u8; 16];
    while k == [0; 16] {
        fill_random(&mut k);
    }
    k
}

/// A random non-zero u64: a field session's token.
pub fn random_u64() -> u64 {
    let mut b = [0u8; 8];
    loop {
        fill_random(&mut b);
        let v = u64::from_le_bytes(b);
        if v != 0 {
            return v;
        }
    }
}

fn bad(e: impl std::fmt::Display) -> String {
    e.to_string()
}

// ---- server side

pub type ServerTls = Arc<ServerConfig>;

/// A server configuration from a PEM certificate chain and a PEM private key (PKCS#8, PKCS#1 or SEC1).
pub fn server_config_pem(cert_pem: &[u8], key_pem: &[u8]) -> Result<ServerTls, String> {
    let certs: Vec<CertificateDer<'static>> = CertificateDer::pem_slice_iter(cert_pem).collect::<Result<_, _>>().map_err(|e| format!("certificate: {e}"))?;
    if certs.is_empty() {
        return Err("certificate: no CERTIFICATE in the file".into());
    }
    let key = PrivateKeyDer::from_pem_slice(key_pem).map_err(|e| format!("private key: {e}"))?;
    let mut cfg = ServerConfig::builder_with_provider(provider())
        .with_safe_default_protocol_versions()
        .map_err(bad)?
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .map_err(|e| format!("certificate and key: {e}"))?;
    // No resumption tickets: a client reconnects seldom and a full handshake is cheap at this size.
    cfg.send_tls13_tickets = 0;
    Ok(Arc::new(cfg))
}

pub fn server_config(cert: &Path, key: &Path) -> Result<ServerTls, String> {
    let c = std::fs::read(cert).map_err(|e| format!("{}: {e}", cert.display()))?;
    let k = std::fs::read(key).map_err(|e| format!("{}: {e}", key.display()))?;
    server_config_pem(&c, &k)
}

/// A self-signed certificate and its key, both PEM.
pub struct DevCert {
    pub cert_pem: String,
    pub key_pem: String,
}

/// A self-signed certificate for `names` (DNS names or IP addresses), valid from `from` to `until` (year, month,
/// day). For local play and tests only: nobody trusts it unless told to (`--ca` or `--insecure-dev`).
pub fn make_cert(names: &[&str], from: (i32, u8, u8), until: (i32, u8, u8)) -> Result<DevCert, String> {
    let mut p = rcgen::CertificateParams::new(names.iter().map(|s| s.to_string()).collect::<Vec<_>>()).map_err(bad)?;
    p.distinguished_name = rcgen::DistinguishedName::new();
    p.distinguished_name.push(rcgen::DnType::CommonName, "Horde & Hearth dev gateway");
    p.not_before = rcgen::date_time_ymd(from.0, from.1, from.2);
    p.not_after = rcgen::date_time_ymd(until.0, until.1, until.2);
    let key = rcgen::KeyPair::generate().map_err(bad)?;
    let cert = p.self_signed(&key).map_err(bad)?;
    Ok(DevCert { cert_pem: cert.pem(), key_pem: key.serialize_pem() })
}

/// The dev certificate's names: loopback, and `extra` (the `--public-host`) when given.
pub fn dev_names(extra: &str) -> Vec<&str> {
    let mut v = vec!["localhost", "127.0.0.1", "::1"];
    if !extra.is_empty() && !v.contains(&extra) {
        v.push(extra);
    }
    v
}

/// A fresh in-memory dev pair for an in-process gateway and its own bots (`realm-soak --tls`, the tests): the server
/// configuration and a client configuration that trusts exactly that certificate.
pub fn loopback_pair() -> Result<(ServerTls, Arc<ClientConfig>), String> {
    let d = make_cert(&dev_names(""), (2026, 1, 1), (2036, 1, 1))?;
    Ok((server_config_pem(d.cert_pem.as_bytes(), d.key_pem.as_bytes())?, client_config_ca_pem(d.cert_pem.as_bytes())?))
}

/// `--dev-cert`: the pair beside the store (`DB.dev-cert.pem`, `DB.dev-key.pem`), made once and kept, so a client
/// told to trust it (`--ca=DB.dev-cert.pem`) goes on trusting it after a restart. Never commit them.
pub fn dev_cert_files(db: &str, public_host: &str) -> Result<(PathBuf, PathBuf), String> {
    let cert = PathBuf::from(format!("{db}.dev-cert.pem"));
    let key = PathBuf::from(format!("{db}.dev-key.pem"));
    if cert.exists() && key.exists() {
        return Ok((cert, key));
    }
    let d = make_cert(&dev_names(public_host), (2026, 1, 1), (2036, 1, 1))?;
    write_private(&key, d.key_pem.as_bytes()).map_err(|e| format!("{}: {e}", key.display()))?;
    std::fs::write(&cert, d.cert_pem).map_err(|e| format!("{}: {e}", cert.display()))?;
    Ok((cert, key))
}

fn write_private(path: &Path, b: &[u8]) -> io::Result<()> {
    let mut o = std::fs::OpenOptions::new();
    o.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        o.mode(0o600);
    }
    o.open(path)?.write_all(b)
}

/// True when the first bytes waiting on `s` open a TLS handshake (a handshake record, `0x16 0x03`); false for
/// anything else (a plain-text client's frame). Waits at most `wait` (None: as long as it takes) for two bytes.
pub fn looks_like_tls(s: &TcpStream, wait: Option<Duration>) -> io::Result<bool> {
    s.set_read_timeout(wait)?;
    let mut b = [0u8; 2];
    let end = wait.map(|w| std::time::Instant::now() + w);
    loop {
        let n = s.peek(&mut b)?;
        if n == 0 {
            return Err(io::Error::new(ErrorKind::UnexpectedEof, "closed before a byte"));
        }
        if n >= 2 || b[0] != 0x16 {
            s.set_read_timeout(None)?;
            return Ok(b[0] == 0x16 && b[1] == 0x03);
        }
        if end.is_some_and(|e| std::time::Instant::now() > e) {
            return Err(io::Error::new(ErrorKind::TimedOut, "no handshake"));
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

enum Inner {
    Plain(TcpStream),
    Tls(Box<ServerConnection>, TcpStream),
}

/// An accepted connection, plain or TLS, that one reader thread and any number of writers share.
pub struct Duplex {
    /// A clone of the socket the reader peeks at to wait for bytes without the lock.
    raw: TcpStream,
    inner: Mutex<Inner>,
}

impl Duplex {
    pub fn plain(s: TcpStream) -> io::Result<Duplex> {
        Ok(Duplex { raw: s.try_clone()?, inner: Mutex::new(Inner::Plain(s)) })
    }

    /// Runs the server handshake (at most `HANDSHAKE_TIMEOUT`); an error names what rustls refused.
    pub fn tls(mut s: TcpStream, cfg: &ServerTls) -> io::Result<Duplex> {
        let mut c = ServerConnection::new(cfg.clone()).map_err(|e| io::Error::new(ErrorKind::InvalidData, e))?;
        s.set_read_timeout(Some(HANDSHAKE_TIMEOUT))?;
        s.set_write_timeout(Some(HANDSHAKE_TIMEOUT))?;
        while c.is_handshaking() {
            c.complete_io(&mut s)?;
        }
        while c.wants_write() {
            c.write_tls(&mut s)?;
        }
        s.set_read_timeout(None)?;
        s.set_write_timeout(None)?;
        Ok(Duplex { raw: s.try_clone()?, inner: Mutex::new(Inner::Tls(Box::new(c), s)) })
    }

    /// Sends `b` whole (encrypted when TLS).
    pub fn write_all(&self, b: &[u8]) -> io::Result<()> {
        let mut g = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        match &mut *g {
            Inner::Plain(s) => s.write_all(b),
            Inner::Tls(c, s) => {
                c.writer().write_all(b)?;
                while c.wants_write() {
                    c.write_tls(s)?;
                }
                Ok(())
            }
        }
    }

    /// Ends the connection (a TLS close_notify first); the reader then sees the end.
    pub fn shutdown(&self) {
        if let Ok(mut g) = self.inner.try_lock() {
            if let Inner::Tls(c, s) = &mut *g {
                c.send_close_notify();
                let _ = s.set_write_timeout(Some(Duration::from_secs(1)));
                let _ = c.write_tls(s);
            }
        }
        let _ = self.raw.shutdown(std::net::Shutdown::Both);
    }

    /// The reading side, for `proto::read_frame`. Only one thread may read.
    pub fn reader(&self) -> DuplexReader<'_> {
        DuplexReader(self)
    }
}

pub struct DuplexReader<'a>(&'a Duplex);

impl Read for DuplexReader<'_> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        if buf.is_empty() {
            return Ok(0);
        }
        let d = self.0;
        loop {
            // Plain text already decrypted comes first.
            if let Inner::Tls(c, _) = &mut *d.inner.lock().unwrap_or_else(|p| p.into_inner()) {
                match c.reader().read(buf) {
                    Ok(n) => return Ok(n),
                    Err(e) if e.kind() == ErrorKind::WouldBlock => {}
                    Err(e) => return Err(e),
                }
            }
            // Wait for bytes with no lock held.
            let mut one = [0u8; 1];
            if d.raw.peek(&mut one)? == 0 {
                return Ok(0);
            }
            let mut g = d.inner.lock().unwrap_or_else(|p| p.into_inner());
            match &mut *g {
                Inner::Plain(s) => return s.read(buf),
                Inner::Tls(c, s) => {
                    if c.read_tls(s)? == 0 {
                        return Ok(0);
                    }
                    let r = c.process_new_packets();
                    // An alert, or the answer to a key update, goes out now.
                    while c.wants_write() {
                        if c.write_tls(s).is_err() {
                            break;
                        }
                    }
                    r.map_err(|e| io::Error::new(ErrorKind::InvalidData, e))?;
                }
            }
        }
    }
}

// ---- client side

/// The client's choice: `--tls` (trust the public roots, `webpki-roots`), `--ca=PATH` (trust that PEM, e.g. the
/// gateway's dev certificate; implies `--tls`), `--insecure-dev` (accept any certificate; implies `--tls`; only
/// for a dev gateway, and it says so loudly). None of them: plain TCP.
#[derive(Clone, Debug, Default)]
pub struct ClientTls {
    pub tls: bool,
    pub ca: Option<PathBuf>,
    pub insecure_dev: bool,
}

impl ClientTls {
    /// Takes `--tls`, `--ca=PATH`, `--insecure-dev`; false for any other flag.
    pub fn flag(&mut self, k: &str, v: &str) -> bool {
        match k {
            "--tls" => self.tls = true,
            "--ca" => {
                self.tls = true;
                self.ca = Some(PathBuf::from(v));
            }
            "--insecure-dev" => {
                self.tls = true;
                self.insecure_dev = true;
            }
            _ => return false,
        }
        true
    }

    pub const HELP: &'static str = "[--tls] [--ca=PEM] [--insecure-dev]";

    /// The rustls configuration, or None for plain TCP.
    pub fn config(&self) -> Result<Option<Arc<ClientConfig>>, String> {
        if !self.tls {
            return Ok(None);
        }
        if self.insecure_dev {
            eprintln!("WARNING: --insecure-dev: the gateway's certificate is NOT checked; anyone on the path can read this connection. Dev gateways only.");
            return Ok(Some(insecure_config()));
        }
        match &self.ca {
            Some(p) => {
                let pem = std::fs::read(p).map_err(|e| format!("{}: {e}", p.display()))?;
                client_config_ca_pem(&pem).map(Some)
            }
            None => Ok(Some(client_config_public())),
        }
    }
}

fn with_roots(roots: RootCertStore) -> Arc<ClientConfig> {
    let cfg = ClientConfig::builder_with_provider(provider())
        .with_safe_default_protocol_versions()
        .expect("ring supports the default versions")
        .with_root_certificates(roots)
        .with_no_client_auth();
    Arc::new(cfg)
}

/// Trusts the public web roots (`webpki-roots`), as a launch gateway with a Let's Encrypt certificate needs.
pub fn client_config_public() -> Arc<ClientConfig> {
    let roots = RootCertStore { roots: webpki_roots::TLS_SERVER_ROOTS.to_vec() };
    with_roots(roots)
}

/// Trusts only the certificates in `pem` (a dev certificate, or a private CA).
pub fn client_config_ca_pem(pem: &[u8]) -> Result<Arc<ClientConfig>, String> {
    let mut roots = RootCertStore::empty();
    for c in CertificateDer::pem_slice_iter(pem) {
        roots.add(c.map_err(|e| format!("CA: {e}"))?).map_err(|e| format!("CA: {e}"))?;
    }
    if roots.is_empty() {
        return Err("CA: no CERTIFICATE in the file".into());
    }
    Ok(with_roots(roots))
}

/// `--insecure-dev`: any certificate is taken, but the server must still prove it holds the key of the one it
/// shows (the handshake signature is checked), so the connection is encrypted, just not to a known party.
pub fn insecure_config() -> Arc<ClientConfig> {
    let mut cfg = (*with_roots(RootCertStore::empty())).clone();
    cfg.dangerous().set_certificate_verifier(Arc::new(AnyCert(provider())));
    Arc::new(cfg)
}

#[derive(Debug)]
struct AnyCert(Arc<CryptoProvider>);

impl ServerCertVerifier for AnyCert {
    fn verify_server_cert(&self, _: &CertificateDer<'_>, _: &[CertificateDer<'_>], _: &ServerName<'_>, _: &[u8], _: UnixTime) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(&self, m: &[u8], c: &CertificateDer<'_>, d: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls12_signature(m, c, d, &self.0.signature_verification_algorithms)
    }
    fn verify_tls13_signature(&self, m: &[u8], c: &CertificateDer<'_>, d: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(m, c, d, &self.0.signature_verification_algorithms)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}

/// A blocking client connection, plain or TLS.
pub enum ClientStream {
    Plain(TcpStream),
    Tls(Box<StreamOwned<ClientConnection, TcpStream>>),
}

/// The host part of `host:port` (`[v6]:port` too), the name a certificate must carry.
pub fn host_of(addr: &str) -> &str {
    let h = addr.rsplit_once(':').map_or(addr, |(h, _)| h);
    h.trim_start_matches('[').trim_end_matches(']')
}

impl ClientStream {
    /// Connects to `addr` (`host:port`); with `tls` runs the handshake at once, checking the certificate against
    /// the host part of `addr`, so a refused certificate is an error here (`InvalidData`, rustls's reason).
    pub fn connect(addr: &str, tls: Option<&Arc<ClientConfig>>) -> io::Result<ClientStream> {
        let s = TcpStream::connect(addr)?;
        s.set_nodelay(true)?;
        let Some(cfg) = tls else { return Ok(ClientStream::Plain(s)) };
        let name = ServerName::try_from(host_of(addr).to_string()).map_err(|e| io::Error::new(ErrorKind::InvalidInput, format!("server name {}: {e}", host_of(addr))))?;
        let mut c = ClientConnection::new(cfg.clone(), name).map_err(|e| io::Error::new(ErrorKind::InvalidData, e))?;
        let mut s = s;
        s.set_read_timeout(Some(HANDSHAKE_TIMEOUT))?;
        s.set_write_timeout(Some(HANDSHAKE_TIMEOUT))?;
        while c.is_handshaking() {
            if let Err(e) = c.complete_io(&mut s) {
                return Err(io::Error::new(e.kind(), format!("TLS handshake with {addr} failed: {e}")));
            }
        }
        s.set_write_timeout(None)?;
        Ok(ClientStream::Tls(Box::new(StreamOwned::new(c, s))))
    }

    pub fn tcp(&self) -> &TcpStream {
        match self {
            ClientStream::Plain(s) => s,
            ClientStream::Tls(t) => &t.sock,
        }
    }
}

impl Read for ClientStream {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        match self {
            ClientStream::Plain(s) => s.read(buf),
            ClientStream::Tls(t) => t.read(buf),
        }
    }
}

impl Write for ClientStream {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        match self {
            ClientStream::Plain(s) => s.write(buf),
            ClientStream::Tls(t) => t.write(buf),
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        match self {
            ClientStream::Plain(s) => s.flush(),
            ClientStream::Tls(t) => t.flush(),
        }
    }
}

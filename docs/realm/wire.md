# Wire and gateway (job W1)

What goes between a player and the realm, every number chosen and why. Code: `realm/server` (field wire, hosts) and
`realm/gateway` (accounts, towns, tickets, the bridge to the store and the loot rules).

## Field wire (UDP, lockstep protocol B)

- INPUT is `0x02, u32 ack, u8 b0, u8 zoom, u8 b1, [u32 seq, u8 n, n x u16]`. The word is `b0 | b1<<8`: the core's two input
  bytes (`IN_DIR`, `IN_SKILL1/2`, `IN_ULT`, `IN_INTERACT` in byte 0; picks and potions in byte 1). The core edge-detects
  picks and potions, so a held word is safe to repeat. Why two bytes: the old one-byte shortcut lost skill 2, the ult,
  interact and every pick, which a hero needs to bank and leave. Cost: one byte a datagram.
- HELLO appends `u64 ticket, 16 bytes key`. A ticket is how a hero reaches a field: no ticket and its key, no join
  (Transport security, below). WELCOME ends with a `u64` session token; a ticketed player's INPUT and BYE are sent
  sealed with it (`0x04, u64 token, <INPUT body>`, `0x05, u64 token`). The `Join` record carries the whole
  `Sheet` (class, level, stats, deck, belt, job) and `Outing` (what the hero carries in), so every client builds the same
  hero; `wire::put_sheet/read_sheet` are the only codec.
- Repeating a tick (from Job G): inputs are repeated `INPUT_REPEAT` = 3 times; server records are sent at once when new and
  resent only after `rtt + 1` ticks (`RESEND_SLACK` = 1) without an ack. The RTT is learned from acks as a smoothed value in
  quarter ticks (`srtt4`; whole ticks rounded to a standstill); it starts at `RTT_START` = 4. Measured on a lossy link in the
  `lockstep.rs` tests: 57,776 B against 330,456 B, worst stall 4 ticks against 13.
- `HASH_EVERY` 20 ticks (1 s) keeps desyncs visible. `MAX_DATAGRAM` 1200 stays under any common MTU. `TIMEOUT` 5 s of silence
  drops a client (a disconnect, below).

## Field hosts

- One host per field copy: its own UDP socket and thread group (`--copies`, `--fields`). It runs the 20 Hz loop.
  Joining needs a ticket the gateway issued (`HostCmd::Admit`); a ticket lives `TICKET_TTL` 30 s unused, and an unused one is
  handed back (`HostMsg::Unused`) so the hero is free again.
- A hero enters at the gate (`GATE_ENTRY_PX` 120 from it) or at her waystone for that field, with a scatter of
  `ENTRY_SCATTER_PX` 30. Each hero has tallies fed from core events (coin, xp, potions, kills).
- Result flush: when a hero leaves (gate, waystone), falls, is kicked, disconnects or the host stops, and every
  `XP_FLUSH_TICKS` 200 (10 s) for xp, the host sends a `Flush{ticket, seq, coin, xp, potions, banked, fell, left}` to the
  gateway. The applier applies it with request id `ticket<<64 | seq | attempt<<40`, so a retry is idempotent. Why the 10 s xp
  flush: a killed server loses at most 10 s of xp and nothing banked.

## Gateway (TCP)

- Frame: `u32 len, u8 type, u32 tag, body`, `FRAME_MAX` 1 MiB. `tag` pairs a reply with its request; pushes have tag 0. Thread
  per connection (reader and writer), no async runtime; TLS through rustls (Transport security, below).
- Login: dev (name only, `--dev-login`); Steam answers DISABLED until the Steam job. Character list, create, rename, delete and
  undelete heroes (the store's rules: name 3 to 16 letters, digits, `'` `-`, first a letter).
- Town: rooms of `ROOM_MAX` 100 heroes, `STEP_HZ` 10 steps a second with a snapshot to every member (id, x, y in whole px,
  direction). Town is `TOWN_PX` 4096 square, walking at the field speed. Chat: `CHAT_MAX` 200 chars, a burst of
  `CHAT_BURST` 5 lines, one back a second. A hero is in exactly one place, Town or Field, tracked by the gateway.
- Field ticket: only for a hero who is in no field; a ticket locks the hero (BUSY until her result is applied).
- Store calls (bank, mail, spends, smith) all go through `ops::who_may` as the account (`Who::Owner`). Mail to another
  player's hero is sent as the server after checking the sender owns the sending hero.
- Loot: kills roll in the applier thread with a server secret (kept in `DB.secret`) and `RollKey{field_seed, tick, index,
  slot}`, so the client cannot influence a roll. Kept drops go through `deliver`; common items and materials wait in the
  ticket's `Haul`, banked with the coin at a bank flush, halved by a fall. First boss kills are remembered per hero in
  `DB.bosskills` (one `hero boss` line, fsync'd), because the store has no such record.
- Disconnect: half the haul's coin is lost (`coin/2`) and the rest banked. Gate, waystone, kick and stop bank everything.

- Type bytes are owned per module in one table, `gateway/src/proto/ranges.rs` (core W1, economy E1, social T1, world W2,
  homes H1, reserved pvp R3 and steam P1; a test fails on an overlap or a tag outside its module's span). The core's
  messages are `proto/base.rs`; each other module's `Req`/`Resp` variants are thin wrappers coded and served by its own
  `gate.rs` (`proto::WireModule`), registered with one line in `proto::MODULES`. Decoders refuse what they cannot read
  whole, cap every count at the bytes left, accept flags only as 0 or 1, and re-encode to the same bytes:
  `proto/fuzz.rs` checks it with 200 000 seeded cases a test run (`REALM_FUZZ_CASES`, `REALM_FUZZ_SEED` for more).
- Social calls (job T1): requests 0x40..0x5B, reply 0x90, push 0xB0, error `MUTED` 17; see `social.md`. A connection's writer
  ends on an empty frame (the moderators' "end this session").

## Transport security

Code: `gateway/src/tls.rs`, `gateway/src/conn.rs`, the field checks in `server/src/host.rs`; tests `gateway/tests/tls.rs`.

- **Gateway TCP is TLS** (rustls 0.23 on the ring provider, TLS 1.2 and 1.3, no OpenSSL, no cmake or NASM on Windows).
  `realm-gateway --tls-cert=fullchain.pem --tls-key=privkey.pem` for a real pair, `--dev-cert` for a self-signed pair
  made once beside the store (`DB.dev-cert.pem`, `DB.dev-key.pem`, key mode 0600; never commit them). With neither,
  the gateway refuses to start unless `--plain` or `--dev-login` is given, and then prints one `WARNING: UNENCRYPTED`
  line. `ops.conf`: `tls_cert`, `tls_key`, `tls_dev_cert`, `plain`. The LISTEN line ends `tls=on|off`.
- **What a TLS gateway refuses:** a plain-text client gets one plain error frame (`REFUSED`, "this gateway speaks TLS
  only") and is closed; a handshake that fails or stalls past `HANDSHAKE_TIMEOUT` 10 s is closed. A plain gateway
  closes a client whose first bytes are a TLS handshake, so a TLS client fails at once instead of hanging.
- **Clients:** `GatewayClient::connect_with(addr, tls)`; `tls::ClientTls` parses `--tls` (public roots from
  `webpki-roots`), `--ca=PEM` (trust exactly that file, e.g. a dev certificate) and `--insecure-dev` (any certificate,
  handshake signature still checked, a loud warning; never the default). The name checked is the host part of the
  address. `realm-soak --tls` and `realm-world --tls` run their in-process gateway and bots over TLS with an in-memory
  dev pair; the kill test runs the real binary with `--dev-cert` and trusts the file. No tool connects to a remote
  gateway's TCP today: `realm-gateway admin` and the ops metrics speak to loopback-only ports (left plain), and the
  load test speaks only field UDP.
- **Godot (`client/ui/gw_link.gd`):** `StreamPeerTLS` over the `StreamPeerTCP`, `TLSOptions.client()`: the system's
  trusted roots and the gateway's name. Only a debug build honours `--dev-cert=PEM` (trust that file) or `--plain`; a
  release build ignores both. A failed handshake ends `open` with `last_error`, which the login screen shows; there is
  no retry in clear text. `check_client.sh` runs the shell test against a `--dev-cert` gateway with `--dev-cert=`.
- **One connection, two threads (why a lock and a peek):** a rustls session is one state machine for both directions,
  so the reader and writer threads cannot each own half. `tls::Duplex` keeps the session under one mutex; the reader
  waits for bytes with `TcpStream::peek` on a clone of the socket *without* the lock, then takes it only to pull in
  and decrypt what arrived; the writer takes it to encrypt and send a frame. Chosen over one I/O thread with a write
  queue because that thread would need a read timeout to look at its queue (latency or idle wake-ups on every
  connection); the peek costs neither, and plain connections take the same path. Cost: a peer that stops reading
  stalls its own connection's writer while it holds the lock (as a full socket did before), nobody else's.
- **Field UDP: authenticated, not encrypted.** Lockstep input is not secret, so it stays clear; it must not be
  forgeable by anyone who never held the ticket.
  - *Before:* a ticketed host admitted any HELLO naming a pending ticket number, and took INPUT and BYE from any
    datagram whose source address matched a joined client. Ticket numbers were a splitmix of a counter seeded from the
    boot nonce, and splitmix is invertible: from her own ticket a player could compute the counter and every later
    ticket, then HELLO a victim's ticket in its 30 s window and play her hero. Any source-spoofing stranger could send
    INPUT or BYE for a joined address. A follower HELLO (proto 3) was taken by every host, so any address could be
    sent the full state stream (an amplifier).
  - *Now:* each ticket carries a 128-bit `key` from the OS's secure random source (ring's `SecureRandom`), sent to the
    client only in `Resp::Ticket` / `WResp::Vault` (over TLS), and a random 64-bit session `token`. The HELLO must carry
    the key itself (allowed since the ticket came over TLS; no HMAC: the HELLO is single-use, below); the host
    compares it in constant time. A wrong or missing key drops the HELLO and leaves the ticket waiting (a stranger
    cannot burn it). A right one spends the ticket and binds the session to that source address; a repeated HELLO
    from that address must carry the key again. INPUT and BYE are taken only from the bound address and only sealed
    with the token (`0x04`/`0x05`); a bare `0x02`/`0x03` is dropped on a ticketed host. A ticketed host takes no
    followers. Dropped datagrams count in `HostStatus::refused` and the host's `net ... refused=` line. A hero moved to
    another copy keeps her ticket's key and token. The crowd-test server (no tickets) is unchanged.
  - *What a field host checks before it takes inputs from an address:* HELLO: proto is not a follower; the ticket is
    pending; its key is non-zero and equals the HELLO's. INPUT/BYE: the address has a joined client, and the token in
    the sealed message is that client's.
  - *Not covered:* anyone who can read the field traffic on the path (same Wi-Fi, an ISP) sees the HELLO and the token
    and can forge inputs from a spoofed source address, as with any unencrypted UDP game; a per-packet MAC would close
    that and was not needed for "not forgeable by an outsider".
- **What P1 (Steam tickets) may rely on:** everything on the gateway TCP (login names, Steam session tickets, chat,
  trades, field ticket keys) is encrypted and the server is authenticated by its certificate when the client checks
  it (release Godot builds always do; bots with `--tls`/`--ca`). The client is not authenticated by TLS: the Steam
  ticket is the client's proof. A Steam ticket must still be checked once with Steam (replay inside TLS is not
  possible, but a stolen ticket from a compromised client is). Do not put secrets in field UDP.
- **A real certificate for launch (no cost):** on the rented server, give the gateway a DNS name (an A record), then
  Let's Encrypt with certbot in standalone mode (`certbot certonly --standalone -d realm.example.com`; port 80 open
  for the challenge), or `--webroot` if a web server already runs. Point `tls_cert` at `/etc/letsencrypt/live/NAME/
  fullchain.pem` and `tls_key` at `privkey.pem` (readable by the realm's user). Rotation: certbot renews by itself
  (a timer) 30 days before the 90-day end; the gateway reads the files at start, so add a deploy hook that restarts
  it (`--deploy-hook "systemctl restart realm"`), at a quiet hour. Clients connect by that name (`--gateway=NAME:7700`),
  never by IP, or the name check fails. Field UDP needs no certificate.
- **New crates and licences** (all allow commercial use; none GPL; none needs a system library; ring builds its own
  C and assembly with the platform's C compiler): `rustls` 0.23 (Apache-2.0 OR ISC OR MIT), `ring` 0.17 (Apache-2.0
  AND ISC), `rustls-webpki` (ISC), `rustls-pki-types` (MIT OR Apache-2.0; also reads PEM, so no `rustls-pemfile`),
  `webpki-roots` 1 (CDLA-Permissive-2.0, Mozilla's root list as data), `rcgen` 0.14 for the dev certificate
  (MIT OR Apache-2.0) with `pem` (MIT), `yasna`, `time`, `base64` (MIT OR Apache-2.0); smaller ones under them:
  `untrusted` (ISC), `subtle` (BSD-3-Clause), `zeroize`, `getrandom`, `libc`, `cc` (MIT OR Apache-2.0). The gateway
  crate is no longer std only (core, server and loadtest still are).

## Proof

- `gateway/tests/gateway.rs`: login, names, towns, chat, snapshots, tickets, bank, mail, spends, smith; all over TLS.
- `gateway/tests/tls.rs`: the right certificate, a wrong, an expired and a wrong-name one, plain text at a TLS gateway
  and TLS at a plain one; login, town, chat and a field over TLS; a HELLO without the key, a replayed HELLO from
  another address, and bare or wrongly sealed INPUT and BYE (from her address and another) are all dropped.
- `gateway/tests/kill.rs`: the real binary; a hero banks; a second outing is running; SIGKILL; reopen the store: nothing
  banked is gone, `verify` is clean, a restarted server logs her in. About 90 s.
- `realm-soak --bots=40 --secs=7200 --fast`: bots through the whole stack, one `SOAK ok ...` line. The station word is `soak`
  (role in `tools/station/roles.txt`, `ubuntu`).

## Open questions

- Leaving by waystone in the core discards the coin carried (no Bank event). That is a core (R2) question.
- Bots with a crowd of monsters on a waystone cannot hold interact to leave (every hit breaks the hold); they bank and then
  disconnect. Is that the intended pressure on a waystone?
- Town speed equals field speed; no town collision or zones yet.
- `FRAME_MAX` and the chat limits are guesses; no crowd has played them.

# TLS: encrypt the gateway connection (login, chat, trades) and check who is on the field socket

Why: the tools audit of 22 Nov 2026 found the gateway speaks plain TCP. Once Steam tickets and account names cross it
(job P1), anyone on the path could read or replay them. This must be in before a public demo.

## Build
1. Gateway (`realm/gateway`): TLS on the TCP listener with `rustls` (Apache-2.0/MIT/ISC; use the `ring` provider, not
   aws-lc-rs, so Windows builds need no cmake or NASM; no OpenSSL). Flags: `--tls-cert=PATH --tls-key=PATH` (PEM).
   With neither flag the gateway refuses to start unless `--dev-login` or `--plain` is given, and prints one loud line
   that it is unencrypted. `--dev-cert` writes a self-signed pair under the data folder for local play and tests
   (generate with `rcgen` as a dev-dependency or a tiny built-in generator; never commit a key).
   Keep the code path one: wrap the stream so `conn.rs` reads and writes the same frames either way. No async runtime:
   threads and blocking sockets as now. Watch for the blocking-read plus write-from-another-thread pattern; a rustls
   stream is not split-safe, so own the connection in one place (a lock around the session, or a reader thread and a
   write queue). Say in the doc which you chose and why.
2. Bots and tools that connect (`gateway/src/client.rs`, soak, world, economy, ops, loadtest): the same wrapper, with
   `--tls` / `--ca=PATH` / `--insecure-dev` (accept the dev certificate only when asked; never by default).
3. Godot client (`realm/client/ui/gw_link.gd`): `StreamPeerTLS` over the existing `StreamPeerTCP`, verifying the
   server name against the system trust store in release, and against the bundled dev certificate only in a dev
   build flag. A failed handshake shows a plain error in the shell, never a silent retry in clear text.
4. Field socket: read how field hosts accept UDP (`realm/server`, `gateway` field tickets). Write down in the doc
   exactly what a field host checks before it accepts inputs from an address. If a stranger who never held a ticket
   can inject inputs or join, fix it: the ticket handed out over the (now encrypted) gateway carries a random 128-bit
   secret; the first field packet must prove it (HMAC or the secret itself inside the first packet is acceptable
   since the ticket came over TLS; say which) and later packets are bound to that address plus a per-session token.
   Field traffic itself stays unencrypted lockstep input (it is not secret), but it must not be forgeable by an
   outsider. Wire tags: use the owning ranges in `realm/gateway/src/proto/ranges.rs`; never reuse a number.
5. Tests: handshake with the right certificate works; wrong certificate, expired certificate and plain-text client
   against a TLS gateway are all refused with a clear error; a full login + town + field ticket flow runs over TLS in
   `gateway/tests`; a forged field packet without the secret is dropped (test it), a replayed first packet from
   another address is dropped. Existing tests keep running (they may use `--plain` or the dev certificate; prefer TLS
   for the main gateway flow test).
6. Docs: `docs/realm/wire.md` gets a short "Transport security" part: what is encrypted, what is authenticated, what is
   not and why, how to make and rotate a real certificate for launch (Let's Encrypt on the rented server; no cost),
   and what P1 (Steam tickets) may rely on.

## Rules
- Deterministic core untouched: nothing in `realm/core` changes; no wall clock or randomness enters the sim.
- New crates: only rustls (+ rustls-pemfile / webpki-roots if needed) and one for the dev certificate. Check each
  licence allows commercial use and list them in the doc. Nothing GPL, nothing that needs a system library.
- Linux and Windows must both build (CI runs both). Keep `realm/check.sh` and `realm/store/check.sh` green; run
  `realm/check_client.sh` only if Godot is installed here, otherwise say it was not run.
- Do not run git. Do not message anyone. Read only: this brief, `docs/realm/wire.md`, and the files you touch (grep,
  then read by line range).

## Done
Report in at most 15 lines: what is built, the summary lines of the checks, how the field socket was before and
after, every new crate with its licence, and honest weak points (anything a reviewer should attack first).

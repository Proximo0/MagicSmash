# Living together (job T1)

Parties, guilds, friends, chat, mute, report and the moderators' console. Code: `realm/gateway/src/social/`
(`mod.rs` state and chat gate, `party.rs`, `guild.rs`, `lists.rs`, `modtools.rs`, `admin.rs` the console, `filter.rs`
filter and limits, `log.rs` persistence, `wire.rs` the codec), the shell panels `realm/client/ui/{chat,party,guild}_panel.gd`.
Every number below is a guess for a closed test of a few hundred players; `Open questions` lists what a crowd will settle.

## Presence

A hero is *present* from `EnterTown` (or a field ticket) to the end of her connection. Presence is how a line finds its
listeners, and it is the only thing a social call checks about "who is she": every request names a hero, and the gateway
refuses it unless that hero is present on this connection and belongs to the session's account (`NOT_YOURS`, or
`BAD_REQUEST` "enter the town first"). Leaving the town for the hero list, or closing the connection, ends presence; she
leaves her party; her friends are told she is away. The gateway's edits are one field (`Gateway.social`), one match arm,
one gate on the old `Req::Chat`, and attach/detach lines in `enter_town`, `field_ticket`, `leave_town_of`,
`close_session`.

## Wire (tags from 0x40, replies 0x90, pushes 0xB0; E1 keeps 0x33, 0x8B, 0xA8)

Requests `0x40..=0x5B` (all begin with the acting `hero` u64): `0x40` Talk(chan, to, text), `0x41` PartyInvite(name),
`0x42` PartyAnswer(inviter hero, accept), `0x43` PartyLeave, `0x44` PartyKick(hero), `0x45` PartyLead(hero), `0x46`
PartyGo(field), `0x47` PartyInfo, `0x48` GuildCreate(name), `0x49` GuildInvite(name), `0x4A` GuildAnswer(guild, accept),
`0x4B` GuildLeave, `0x4C` GuildKick(account), `0x4D` GuildRank(account, rank), `0x4E` GuildPerms(rank, bits), `0x4F`
GuildMotd(text), `0x50` GuildPost(text), `0x51` GuildUnpost(post), `0x52` GuildBank(thing, tab, deposit), `0x53`
GuildBankView(tab), `0x54` GuildInfo, `0x55` GuildDisband, `0x56` FriendAdd(name), `0x57` FriendAnswer(account, accept),
`0x58` FriendRemove(account), `0x59` Ignore(name, on), `0x5A` Lists, `0x5B` Report(name, reason, text).
Job R3 took `0x5C` WarDeclare(foe guild name, field), `0x5D` WarAnswer(war, accept), `0x5E` WarList, `0x5F`
Duel(op, name), replies 6 Wars and 7 WarDeclared, and pushes 9 to 15 (war, war off, war result, duel challenge, duel
declined, duel start, duel result); see `docs/realm/pvp.md`. The social request span is now full.
Reply `0x90` is one tagged union (`SResp`: party, guild, guild created, bank view, lists, report id); plain successes are
`R_OK`. Push `0xB0` is `SPush`: chat line, party invite, party update, party go, guild invite, guild changed, friend
request, friend status, notice. New error code `MUTED` = 17 (silenced by a moderator or by the flood limit); `SLOW_DOWN`
(14) is the rate refusal. Channels: SAY 0 (the old `Req::Chat`, the town room), TOWN 1, TRADE 2, PARTY 3, GUILD 4,
WHISPER 5. Why one reply tag and one push tag: `proto.rs` (shared with E1 and the client) gets one variant of each and
this module owns the rest.

## Chat

- Say: the town room (existing). Town: every present hero. Trade: the same, with its own slow limit. Party and guild: their
  members. Whisper: one hero by name; the speaker is sent an echo, so her client shows it, and if the listener ignores her
  she is not told.
- A line goes through, in order: empty (cleaned: control characters dropped, 200 characters), muted, rate, filter. A line
  to nobody (no party, no guild, no such hero) is refused *before* a token is spent.
- Rate limits (token buckets per account and channel, in `filter.rs`): say 5 burst, 1 a second (as the room already had);
  town 3 burst, 1 per 2 s; trade 2 burst, 1 per 10 s; party 8 burst, 2 a second; guild 6 burst, 1 a second; whisper 5
  burst, 1 a second; and one bucket over every channel together, 10 burst and 4 a second, so spreading a flood across
  channels does not help. Why: a talkative human is far under every one of these (a whisper a second is quick typing); the
  trade channel is for adverts and is slowest. Refused lines get `SLOW_DOWN`.
- Strikes: 30 refusals for rate inside 10 s silence the account for 5 minutes (`MUTED`), logged as operator `auto`. A
  1,000 line a second bot gets its first burst through and is silenced about 30 lines later (`tests/social.rs`).
- Word filter hook: `Social::set_filter(Box<dyn Fn(&str) -> Verdict>)`; `Verdict::Pass(text)` sends the text (masked) and
  `Block` refuses it (`REFUSED`). The default masks 8 words with `*` of the same length however they are dressed (case,
  digit swaps like `sh1t`, separators like `f.u.c.k`), blocks links (`http://`, `https://`, `www.`, `.com/`) and a run of
  more than 8 of one character. `{db}.social.words` (one word a line) adds words. Guild names, motds and board posts go
  through the same filter; a masked guild name is refused, not changed. Say, town, guild and the rest all use the one gate.
- Ignore is by account and quiet: an ignored account's town, trade, party and guild lines, whispers, party and guild
  invitations and friend requests do not reach the one who ignores; the sender is not told. Say (the room's own broadcast)
  carries no account, so ignoring a say line is the client's to do by name.
- Mute: `Social::gate` refuses an account with a live silence on *every* channel including say, the board and the motd.
  A silenced player still hears everything and still does bank, rank and party work: silence is about speech only.

## Parties

Up to 8 (`PARTY_MAX`). The leader invites (by hero name, who must be present and in no party), removes, hands over the lead
and calls the party to a field (`PartyGo` pushes the call; each member then takes her own ticket as usual). An invitation
lives 60 s. When the leader goes the lead passes to the longest-standing member; a party of one dissolves. A dropped
connection leaves the party at once (no grace: a rejoin is an invitation).

- Shared field ticket: the party remembers the copy of a field its members' tickets were given and the next member's ticket
  for that field asks for the same copy (`Social::party_copy`, used in `field_ticket`), for 10 minutes after the last
  ticket (`PARTY_COPY_TTL_MS`). Why a time and not "while anyone is inside": the gateway tells the social module nothing
  when an outing ends, and ten minutes is longer than a party takes to assemble and shorter than a session. Each hero
  still gets her own ticket, her own haul and her own loot rolls (`loot is per hero` was already so: rolls are keyed to
  the ticket). The first ticket of a party chooses the emptier copy as before.
- The load figure for "the emptier copy" counts heroes already joined, not tickets waiting, so a copy fills slowly; a party
  that shares a copy is safe from that, others may be sent to the same one until the first join. (W1's number, noted.)

## Guilds

Up to 100 accounts (`GUILD_MAX`), one guild each, found by any hero for free (E1 may price it). A name is 3 to 20 letters,
digits, spaces, `'` and `-`, first a letter, unique ignoring case. Membership is by account; the name shown is the hero
name last seen (`name` log records). Ranks: 0 leader, 1 officer, 2 member, 3 recruit (new members). Permissions are a bit
word per rank (`guild::perm`): INVITE 1, KICK 2, DEPOSIT 4, WITHDRAW 8, POST 16, MOTD 32, COIN 64 (take coin as well as
WITHDRAW), RANKS 128. Defaults: leader and officer all; member DEPOSIT and POST; recruit DEPOSIT. Only the leader sets the
bits of ranks 1 to 3 (`GuildPerms`) and hands over (rank 0 to another; she becomes an officer). Rank work is only on those
below you, to ranks below you. An invitation lives 5 minutes.

- Board: up to 50 posts of 300 characters, a post by anyone with POST (rate-limited with the guild channel), removed by its
  author or by KICK. Message of the day: 200 characters, MOTD. Guild chat: the guild channel above.
- Bank: the store's GUILD place (8 tabs of 100 slots) and its stacks, 100 slots a tab, coin and any stack. The store lets only
  the server move value to or from a guild (`store.md`, "guild membership lives in the gateway; job T1 will pass it in"),
  so `GuildBank` checks the member's rank, that the item is in her bag (deposit) or in *this* guild's bank (withdraw), and
  then does one `MoveItem` or `StackTransfer` as the server. One row moves; nothing is copied; the ledger has who. The
  store still applies TRADE_LOCKED to a guild deposit or withdrawal. Between the permission check and the store call the
  lock is let go (the call fsyncs): a member kicked in that instant may finish one move.
- A leader cannot leave with others in the guild, and a guild with anything in its bank (items or stacks) cannot be
  disbanded or abandoned by its last member, so nothing is orphaned.
- Persistence: the store has no guild tables (and this job added none), so guilds, members, ranks, perms, motd, board,
  friends, ignores, silences, reports and the moderators' log are one append-only text file `{db}.social`, a record a line,
  each fsync'd, replayed through the same `apply` that makes them (so a reopened gateway holds what the last one did;
  `tests/social.rs` reopens and compares). Chat lines are never written. Open questions: a file is fine for hundreds of
  accounts and wrong for a hundred thousand.

## Friends and ignores

By account, 100 each (`LIST_MAX`). A friendship needs a request and an answer (or both asking each other); a request waits
a day. Friends see each other online or away (`FriendStatus` pushes) and whether in town or field. Ignoring someone ends the
friendship.

## Reports and moderation

- A player reports a hero (reason spam, abuse, cheating, name, other; 200 characters of text); the report carries the
  target's last 10 chat lines from a ring of the last 4,096 lines (not stored otherwise). One report per 30 s, at most 20
  open, one open report per (reporter, target).
- Console: `realm-gateway admin ...`, one interpreter (`admin.rs`, `Console::run`) used three ways: the running gateway
  serves it on a loopback port (`--admin-port=N`, token in `{db}.admin`, mode 600, constant-time compare); the client
  `admin --connect=127.0.0.1:N --token-file={db}.admin --op=NAME COMMAND...` talks to that port; and `admin --db=FILE
  COMMAND...` works offline (store and log opened directly; for a stopped server: a ban still refuses login, a silence is
  read at the next start). Commands: `silence NAME SPAN [reason]`, `unsilence NAME`, `kick NAME`, `ban NAME SPAN [reason]`,
  `unban NAME`, `flag NAME FLAGS [drops=PCT]`, `banwave FLAG SPAN [reason]`, `reports [all] [N]`, `resolve ID`, `who NAME`,
  `log [N]`. NAME is a hero's name or `#ACCOUNT`; SPAN is `30m`, `2h`, `7d` or `perm`.
- Effects: a silence is heard on every channel (above) and kept across restarts. A kick tells her, closes her connections
  (the writer ends on an empty frame) and kicks her heroes out of their fields (banked; the host also hands back an unused
  ticket now, a one-line change in `server/src/host.rs`). A ban sets `banned_until` through the store's `apply_flags` (a
  ledger row naming the operator), then does what a kick does; login is refused with `BANNED` until it lapses or `unban`.
  A ban wave is `apply_flags` over every account carrying a flag (the store's new read `accounts_flagged(mask)`), keeping each
  account's flags and drops percent, in one transaction, then a kick of each. All of it is logged with the operator's name in
  the `admin` records (`log`), and by `auto` for the flood silence.
- The offline console and the live one share the log file name rule (`{db}.social`); do not run the offline one against a
  running server (two writers to one log).

## Client (shell)

`CHAT` (channels TOWN TRADE PARTY GUILD WHISPER, friends and requests; `/w /r /t /p /g /friend /ignore /unignore /report`),
`PARTY` (members, invite, kick, lead, call to a field, follow a call) and `GUILD` (found, answer, roster with ranks,
board, motd, invite) are buttons under the town's top row. The shell keeps chat lines, party, guild, friends and
invitations current from the pushes whether or not a panel is open (`Shell.chat_lines`, `party`, `guild`, `invites`).
Not built in the client: the guild bank's screen (the calls and the view exist on the wire), setting guild permissions,
and a report button (the `/report` command is there).

## Proof

`realm/gateway/tests/social.rs` (13 tests, real sockets, the real store): channels, filter, whisper, ignore; friends;
a party of eight, leader rules and a shared copy; party leave, kick, lead, drop; a guild with ranks, permissions, board and
a bank (deposit and withdrawal of an item and coin through the store, `verify` clean, one row, coin conserved); a stocked
guild refuses disbanding and a guild survives a restart; flood (1,000 lines as fast as a socket takes them: 3 through, the
rest refused and the bot silenced; 20 bots at 1,000 lines a second in all through the gate: a burst each); a silenced
player silent on every channel and kept across a restart; reports with evidence; a ban ends the session, refuses login,
frees the field hero, and a wave bans by flag; kick and the admin port's token; the offline console.

## Open questions

- Chat history for evidence is memory only and lost at a restart; is a day of lines on disk wanted for disputes?
- Silence from `auto` flood is five minutes with no appeal; are 30 strikes in 10 s right for a lagging client that resends?
- A party's remembered copy ignores whether the copy is full or closed; W2's field assignment should own it.
- Guild bank logs are the store's ledger (who, what, when); a guild-facing "bank log" screen would read `ledger` by guild.
- Parties by hero and guilds by account is a mix; a player with two heroes can be in a party with herself (refused: same
  account) but her two heroes can be in two parties.

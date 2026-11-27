# Horde & Hearth is shelved (27 Nov 2026)

Curtis, 27 Nov 2026, 22:02 UTC: "we are saving this project for later in the year im going to put four of wand back
up front in a new thread. based on the timeline ive decided to go with our backup game." At 22:03: "make sure my
computers all stop their stations and work as well". At 22:08: "in fact go ahead and do a full stop im shifting to
four of wands now". Nothing under `realm/` is in work. Four of Wands (the rest of the repository) is the game in work.

## What was stopped, and how
- **The four PCs.** `tools/station/roles.txt` carries a `stopped:` line: a station that reads it ends its running jobs
  and the playtest server, publishes one `STATION STOPPED` report (branch `station-results`, `<machine>.txt`), ends its
  launcher and exits (`station.sh`, `station_stop`). Autostart entries and power settings on the PCs were left as they
  are: a start at boot or log-on reads the same line and ends at once.
- **The work queue** (branch `station-queue`): every job cancelled and every running job stopped in one commit. The
  queue as it stood before is commit `c67dd878` of that branch. `tools/station/queue.sh fill-week` loads the standing
  jobs again.
- **The playtest server** on the Ubuntu PC: stopped by its stop file; the store with the heroes is kept in
  `~/HordeAndHearthServer`. Start it again with the queue job `script=playhost`.
- **Scheduled runs.** `station-watch.yml` (every 30 minutes), the nightly run of `realm.yml` and `runner.yml` after each
  merge (the PCs' own GitHub runners) now start by hand only. Each file keeps its old trigger as a comment.
- **The lead's hourly check** and its reminders (scheduled tasks of the project) are switched off.

## Where the work stands
- Plan and jobs: `docs/realm/build_plan.md`. The newest direction is its section "Scope change and second playtest
  (Curtis, 27 Nov)": an MMO first, with survivor horde elements; class level 1 to 60 is the only level.
- Audit of 27 Nov 2026 (the game, the build pipeline, free resources on the web):
  https://claude.ai/artifact/4aaQ4jdE1VMhqpHXgt6uHj. The stop cut its second pass short: the document says which
  findings were checked a second time and which are first-pass only. Notes: project files,
  `magic-smash-rework/research/audit_2026-11-27/` and `research/research_notes/Horde and Hearth resources/`.
- Three jobs were stopped part-way. Each is one work-in-progress commit on its own branch, not reviewed, checks not
  run to the end, docs half-edited:
  - `scope-xp` (job X1): the per-outing field level, its XP and its damage term removed; the deck kept.
  - `fields-quiet` (job Q1): quiet zones, larger fields with routes, bots that push deep instead of waiting at the gate.
  - `ui-font` (job U1): the OFL fonts Jacquard and Jersey for all text, debug text off by default, enemy health bars.

## To start again
1. Read this file, the build plan and the audit. The audit's last section gives the order of the fixes.
2. PCs: take each machine off the `stopped:` line in `tools/station/roles.txt` and give it its jobs (the old roles are
   in that file as a comment), merge, then start each PC's launcher once or restart the PC. Put the three workflow
   triggers back. Load the queue with `tools/station/queue.sh fill-week`.
3. Rebase the three parked branches on main; finish, check and review each before it merges.
4. `CLAUDE.md` at the top of the repository is written for whichever game is in work: point it at `docs/realm/` again.

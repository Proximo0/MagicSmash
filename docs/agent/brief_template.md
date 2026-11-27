# Job <ID>: <one-line goal>
Owns: <exact files; new files named; functions if a shared file>
Reads: <docs/systems.md § ...>, <docs/lessons_learned.md § ...> (only these)
Contract: <APIs, dictionary keys, units, input slots taken, what must not change>
Build: <numbered steps>
Proof: <the command and the summary line that proves it; before and after numbers from the same tool>
Not in scope: <what to leave alone>
Report extra: <anything beyond the standard four lines>

Lead prompt: `Read docs/agent/preamble.md, then do this job: <the text above or docs/agent/briefs/<id>.md>`.
Agent type `worker` (or `claude` when the session lacks it); model sonnet for art, UI, tools and docs, opus for game logic.

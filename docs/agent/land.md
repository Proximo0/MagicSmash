# Landing a change: `tools/land.sh`, `tools/guard.sh`, `tools/versions.env`
For the lead. One script lands a branch the same way every time; a guard refuses paths that must not change.

## land.sh
```
tools/land.sh --title "<text>" --body <file> [--same] [--hold] [--allow-dirty] -- <file> [<file> ...]
```
Run it on a branch that is not main, from anywhere in the repo (file paths are relative to the repo root).
- `--title`: the commit subject and PR title, 1 to 110 characters.
- `--body`: a file with the headings `## What this does`, `## Proof`, `## Known weak spots`, in that order. The first
  section (plain text, heading dropped) becomes the commit message body; the whole file is the PR body.
- `--same`: also run `tools/golden.sh` (use it when the change must not alter play). `--hold`: no auto-merge.
- `--allow-dirty`: skip the stop on changed files that are not listed. Only the listed files are committed.
- List files, never a folder (a folder is refused: the guard reads names one by one). New `.uid` files are files too.
- Untracked files that are not listed are named in a warning and left alone.

Needs three settings in the environment (they differ per session, so they never live in the repo; the script names
the missing ones and goes no further): `LAND_PR_HEAD` (first lines of the PR body), `LAND_PR_FOOT` (last lines),
`LAND_TRAILERS` (lines after a blank line at the end of the commit message).

Steps, each stops at its first failure: refuse main / no files / bad title, the three settings, the headings,
`guard.sh`, unlisted changes, `tools/run_tests.sh` (`TESTS passed=N failed=0`), `tools/lint.sh` (`LINT problems=0`),
with `--same` `tools/golden.sh` (`GOLDEN same`), `git add` by name, commit (a new commit on top of earlier ones; never
amend, never force-push), push with 4 retries (waits 2, 4, 8, 16 s) and a `git ls-remote` sha check, then the pull
request through the REST API only, the assignee (the repo owner), and auto-merge by squash (route
`pulls/N/ccr/auto_merge`, falling back to `gh pr merge N --auto --squash` on a 404). A pull request whose checks are
already green cannot take auto-merge (HTTP 422, "clean status"): the script merges it at once, by squash, only at the
commit it just pushed, and says `merge=done`. A second run on the same branch adds a commit and reuses the open pull
request (its title and body stay as first written).

The last line is the answer: `LAND ok pr=<N> url=<url> merge=auto|held|done` (exit 0) or `LAND FAIL <step>: <why>`
(exit 1). Replace a check for a test only: `LAND_TEST_CMD`, `LAND_LINT_CMD`, `LAND_GOLDEN_CMD`;
`LAND_PUSH_WAITS="0 0 0 0"`.

What the script leaves to the lead: reading the diff and the pictures before the run, the rows the rule on main does
not require (`bot-heroes`, `bot-boss`, `bot-win`, `bot-again`, `tools`, `checks-windows`: auto-merge does not wait
for them; `--hold` keeps the merge in your hands until you have read them), and
following the pull request afterwards (a session that can subscribe to its activity does so after `LAND ok`).

## guard.sh
`tools/guard.sh [--base=origin/main] [file ...]`. Without files it checks the diff against the base plus staged and
unstaged changes. Refuses `realm/`, `docs/realm/`, `game/crowd/`, `.godot/`, `*.import`, `config/*credentials*`,
`addons/sentry/`; file names that are a key, a signing store or an env file (`*.pem`, `*.key`, `*.p12`, `*.pfx`,
`*.keystore`, `*.jks`, `id_rsa*`, `id_ed25519*`, `.env`, `.env.*`, `*.env`, except `tools/versions.env`); a name with
`secret` in it when it is a data or config file (`.json .cfg .ini .txt .yml .yaml .toml .xml`; the game's own
`secrets.gd` passes); and any file over 25 MB (a music track is 14 to 17 MB). Names are compared without case. Prints
each path with its reason, then `GUARD problems=N`; exit 1 when N > 0. The lists are arrays at the top of the script.
It reads names and sizes, never file contents: it does not replace reading the diff.

## versions.env
`GODOT_VERSION` and `GODOT_TEMPLATE_TAG` live in `tools/versions.env` (`KEY=value`, shell-sourceable, a workflow can
append it to `$GITHUB_ENV`). `export_lib.sh`, `export_android.sh` and the session hook read it. `tools/lint.py` counts
one problem for each of build.yml, checks.yml, CLAUDE.md line 1, preamble line 2 and `project.godot` that names another
version. To bump the engine: edit the file, then fix what lint names.

## Self-tests
`bash tools/land_test.sh` (`LAND_TEST passed=N failed=0`, throwaway repos under `${TMPDIR:-/tmp}/l1/`, a stub `gh`, no
network, no engine, about 7 s; `--list` names the cases) and `bash tools/lint_versions_test.sh`
(`LINT_VERSIONS passed=N failed=0`). Both run on every pull request in the `tools` row of
`.github/workflows/checks.yml`. They are not in `tools/check_all.sh`: the stations' Windows shells have not run them.

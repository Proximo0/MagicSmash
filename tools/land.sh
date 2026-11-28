#!/usr/bin/env bash
# Land the current branch the same way every time: guard, checks, commit, push, pull request, assignee, auto-merge.
# Usage: tools/land.sh --title "<text>" --body <file> [--same] [--hold] [--allow-dirty] -- <file> [<file> ...]
# Run from anywhere in the repo; file paths are relative to the repo root. docs/agent/land.md.
# Environment (per session, never in the repo): LAND_PR_HEAD, LAND_PR_FOOT, LAND_TRAILERS (all required).
# Optional: LAND_TEST_CMD LAND_LINT_CMD LAND_GOLDEN_CMD (replace the checks), LAND_PUSH_WAITS (default "2 4 8 16").
# Never deletes, never force-pushes, never amends, never pushes to main (a pull request is the only way in), never edits files.
# Quiet: errors on stderr, then exactly one last line on stdout: `LAND ok pr=<N> url=<url> merge=auto|held|done` or `LAND FAIL <step>: <why>`.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MAX_TITLE=110

fail() { echo "LAND FAIL $1: $2"; exit 1; }
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/land.XXXXXX") || { echo "LAND FAIL setup: no temp folder"; exit 1; }
trap 'rm -rf "$TMPD"' EXIT

title=""; body=""; same=0; hold=0; dirty_ok=0; files=()
while [ $# -gt 0 ]; do
	case "$1" in
		--title) title="${2-}"; shift ;;
		--body) body="${2-}"; shift ;;
		--same) same=1 ;;
		--hold) hold=1 ;;
		--allow-dirty) dirty_ok=1 ;;
		--) shift; while [ $# -gt 0 ]; do files+=("$1"); shift; done; break ;;
		*) fail args "unknown argument $1" ;;
	esac
	shift
done

# a. branch, files, title
root=$(git rev-parse --show-toplevel 2>/dev/null) || fail repo "not in a git repository"
cd "$root" || fail repo "cannot enter $root"
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
{ [ -z "$branch" ] || [ "$branch" = "main" ] || [ "$branch" = "HEAD" ]; } && fail branch "refusing to land from '${branch:-?}' (use a branch that is not main)"
[ ${#files[@]} -gt 0 ] || fail files "no files listed after --"
for f in "${files[@]}"; do
	[ ! -d "$f" ] || fail files "$f is a folder (list each file: the guard reads names one by one)"
	if [ ! -e "$f" ] && ! git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then fail files "$f does not exist and is not a tracked deletion"; fi
done
[ -n "$title" ] || fail title "title is empty"
[ ${#title} -le $MAX_TITLE ] || fail title "title is ${#title} characters (max $MAX_TITLE)"

# b. signing settings
missing=""
[ -n "${LAND_PR_HEAD:-}" ] || missing+=" LAND_PR_HEAD"
[ -n "${LAND_PR_FOOT:-}" ] || missing+=" LAND_PR_FOOT"
[ -n "${LAND_TRAILERS:-}" ] || missing+=" LAND_TRAILERS"
[ -z "$missing" ] || fail env "missing in the environment:$missing"

# c. body headings, in order
[ -n "$body" ] && [ -f "$body" ] || fail body "body file '$body' not found"
prev=0
for h in "## What this does" "## Proof" "## Known weak spots"; do
	n=$(grep -n -x -F -- "$h" "$body" | head -n 1 | cut -d: -f1)
	[ -n "$n" ] || fail body "heading '$h' missing"
	[ "$n" -gt "$prev" ] || fail body "heading '$h' is out of order"
	prev=$n
done

# d. guard
gout=$(bash "$HERE/guard.sh" -- "${files[@]}") || { printf '%s\n' "$gout" >&2; fail guard "$(printf '%s\n' "$gout" | tail -n 1): $(printf '%s\n' "$gout" | head -n 1)"; }

# e. nothing left behind
if [ "$dirty_ok" = 0 ]; then
	extra=$( { git diff --name-only; git diff --name-only --cached; } | sort -u | while IFS= read -r p; do
		listed=0; for f in "${files[@]}"; do [ "$f" = "$p" ] && listed=1; done
		[ "$listed" = 0 ] && echo "$p"
	done)
	[ -z "$extra" ] || { printf '%s\n' "$extra" >&2; fail dirty "changes in files not listed: $(printf '%s' "$extra" | tr '\n' ' ')(list them or use --allow-dirty)"; }
fi
untracked=$(git ls-files --others --exclude-standard | while IFS= read -r p; do
	listed=0; for f in "${files[@]}"; do [ "$f" = "$p" ] && listed=1; done
	[ "$listed" = 0 ] && echo "$p"
done)
[ -z "$untracked" ] || echo "warning: untracked files not listed (left alone): $(printf '%s' "$untracked" | tr '\n' ' ')" >&2

# f. checks, first failure stops
run_check() { # run_check <name> <command> <pass-regex>
	local out rc
	out=$(bash -c "$2" 2>&1); rc=$?
	if [ $rc -ne 0 ] || ! printf '%s\n' "$out" | grep -Eq "$3"; then
		printf '%s\n' "$out" | tail -n 15 >&2
		local line; line=$(printf '%s\n' "$out" | grep -E '^(TESTS|LINT|GOLDEN)' | tail -n 1); [ -n "$line" ] || line=$(printf '%s\n' "$out" | tail -n 1)
		fail "$1" "${line:-no output} (exit $rc)"
	fi
}
run_check tests "${LAND_TEST_CMD:-tools/run_tests.sh}" '^TESTS passed=[0-9]+ failed=0( |$)'
run_check lint "${LAND_LINT_CMD:-tools/lint.sh}" '^LINT problems=0( |$)'
[ "$same" = 0 ] || run_check golden "${LAND_GOLDEN_CMD:-tools/golden.sh}" '^GOLDEN same'

# g. commit (new commit only)
git add -- "${files[@]}" >/dev/null 2>&1 || fail commit "git add failed"
ahead=0; git rev-parse --verify -q origin/main >/dev/null 2>&1 && ahead=$(git rev-list --count origin/main..HEAD)
msg="$TMPD/msg"
{
	printf '%s\n\n' "$title"
	awk '/^## What this does[ \t]*$/ {on=1; next} /^## / {on=0} on {print}' "$body" | awk 'NF {started=1} started {buf[++n]=$0} END {while (n>0 && buf[n] ~ /^[ \t]*$/) n--; for (i=1;i<=n;i++) print buf[i]}'
	printf '\n%s\n' "$LAND_TRAILERS"
} >"$msg"
if git diff --cached --quiet -- "${files[@]}"; then
	[ "$ahead" -gt 0 ] || fail commit "nothing to commit and no commits ahead of origin/main"
else
	git commit -q -F "$msg" -- "${files[@]}" >/dev/null 2>&1 || fail commit "git commit failed"
fi

# h. push with retries, then confirm the remote sha
waits="${LAND_PUSH_WAITS:-2 4 8 16}"; pushed=0
if git push -q -u origin "$branch" >/dev/null 2>&1; then pushed=1; else
	for w in $waits; do
		sleep "$w"
		if git push -q -u origin "$branch" >/dev/null 2>&1; then pushed=1; break; fi
	done
fi
[ "$pushed" = 1 ] || fail push "git push failed after retries"
local_sha=$(git rev-parse HEAD)
remote_sha=$(git ls-remote origin "refs/heads/$branch" | cut -f1 | head -n 1)
[ "$remote_sha" = "$local_sha" ] || fail push "remote sha '${remote_sha:-none}' differs from local $local_sha"

# i. pull request (REST only)
url=$(git remote get-url origin 2>/dev/null) || fail pr "no origin remote"
url="${url%/}"; url="${url%.git}"
repo_name="${url##*[/:]}"; rest="${url%[/:]*}"; owner="${rest##*[/:]}"
[ -n "$owner" ] && [ -n "$repo_name" ] || fail pr "cannot read owner/repo from '$url'"
api="repos/$owner/$repo_name"
num=$(gh api "$api/pulls?head=$owner:$branch&state=open" --jq '.[0].number // empty' 2>/dev/null)
if [ -z "$num" ]; then
	full="$TMPD/pr_body"
	{ printf '%s\n\n' "$LAND_PR_HEAD"; cat "$body"; printf '\n%s\n' "$LAND_PR_FOOT"; } >"$full"
	num=$(gh api "$api/pulls" -f title="$title" -f head="$branch" -f base=main -F body=@"$full" --jq .number 2>"$TMPD/err") || fail pr "$(tail -n 1 "$TMPD/err")"
fi
[ -n "$num" ] || fail pr "no pull request number returned"
html=$(gh api "$api/pulls/$num" --jq .html_url 2>/dev/null)
[ -n "$html" ] || html="https://github.com/$owner/$repo_name/pull/$num"

# j. assignee
gh api -X POST "$api/issues/$num/assignees" -f "assignees[]=$owner" >/dev/null 2>"$TMPD/err" || fail assign "$(tail -n 1 "$TMPD/err")"

# k. auto-merge by squash. A pull request whose checks are already green cannot take auto-merge (HTTP 422, "clean
#    status"): it is merged now, and only at the commit this run pushed.
merge=held
if [ "$hold" = 0 ]; then
	if gh api -X PUT "$api/pulls/$num/ccr/auto_merge" -f merge_method=squash >"$TMPD/out" 2>"$TMPD/err"; then merge=auto
	elif grep -qi "clean status" "$TMPD/err" "$TMPD/out"; then
		gh api -X PUT "$api/pulls/$num/merge" -f merge_method=squash -f sha="$local_sha" -f commit_title="$title (#$num)" >/dev/null 2>"$TMPD/err" || fail merge "merge of a green pull request failed: $(tail -n 1 "$TMPD/err")"
		merge=done
	elif grep -q "404" "$TMPD/err"; then
		gh pr merge "$num" --auto --squash >/dev/null 2>"$TMPD/err" || fail merge "gh pr merge failed: $(tail -n 1 "$TMPD/err")"
		merge=auto
	else fail merge "$(tail -n 1 "$TMPD/err")"; fi
fi

echo "LAND ok pr=$num url=$html merge=$merge"

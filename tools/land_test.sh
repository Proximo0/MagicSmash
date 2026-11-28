#!/usr/bin/env bash
# Self-test of tools/land.sh and tools/guard.sh. No network, no engine: throwaway repositories with a bare "origin" under
# ${TMPDIR:-/tmp}/l1/, a stub `gh` first on PATH that logs its arguments, and the three check commands replaced.
# Nothing in this checkout is touched. Ends with one line: `LAND_TEST passed=N failed=M` (exit 1 when M > 0); `--list` names the cases first.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAND="$HERE/land.sh"; GUARD="$HERE/guard.sh"
T="${TMPDIR:-/tmp}/l1/land_test.$$"
rm -rf "$T"; mkdir -p "$T/bin" || { echo "LAND_TEST passed=0 failed=1"; exit 1; }
trap 'rm -rf "$T"' EXIT
PASSED=0; FAILED=0; NAMES=""
check() { # check <name> <command...>: passes when the command succeeds
	local n="$1"; shift
	if "$@" >/dev/null 2>&1; then PASSED=$((PASSED + 1)); NAMES+=" $n"; else FAILED=$((FAILED + 1)); echo "FAIL case: $n" >&2; echo "  last output: $(tail -n 3 "$OUT" 2>/dev/null | tr '\n' '|')" >&2; fi
}
has() { grep -qF -- "$1" "$2"; }        # has <text> <file>
hasnt() { ! grep -qF -- "$1" "$2"; }
eq() { [ "$1" = "$2" ]; }

# The stub gh: logs "$*" to $GH_STATE/log and answers like the API would (number 7, an html url).
cat >"$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$GH_STATE/log"
for a in "$@"; do case "$a" in body=@*) cp "${a#body=@}" "$GH_STATE/body" ;; esac; done
case "$*" in
	*ccr/auto_merge*) if [ -n "${STUB_AUTOMERGE_404:-}" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
		if [ -n "${STUB_AUTOMERGE_CLEAN:-}" ]; then echo '{"message":"Pull request is in clean status"}'; echo "gh: Pull request is in clean status (HTTP 422)" >&2; exit 1; fi
		if [ -n "${STUB_AUTOMERGE_500:-}" ]; then echo "gh: Server Error (HTTP 500)" >&2; exit 1; fi
		echo '{}' ;;
	*"pulls/7/merge -f"*) if [ -n "${STUB_MERGE_FAIL:-}" ]; then echo "gh: Head branch was modified (HTTP 409)" >&2; exit 1; fi; echo '{"merged":true}' ;;
	*assignees*) echo '{}' ;;
	*"pulls?head="*) if [ -f "$GH_STATE/pr" ]; then echo 7; fi ;;
	*html_url*) echo "https://github.com/o/r/pull/7" ;;
	*"pulls -f title="*) : >"$GH_STATE/pr"; echo 7 ;;
	"pr merge"*) : ;;
	*) echo "stub gh: unexpected $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$T/bin/gh"

N=0
# fresh: a new work clone on branch feature with a bare origin; sets W (work), O (origin), S (gh state), OUT.
fresh() {
	N=$((N + 1)); local d="$T/c$N"; W="$d/work"; O="$d/origin.git"; S="$d/gh"; OUT="$d/out"; BODY="$d/body.md"
	mkdir -p "$S" "$W"; git init -q --bare "$O"; git init -q "$W"
	( cd "$W" && git symbolic-ref HEAD refs/heads/main && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
		&& mkdir -p game docs && echo a >a.txt && echo b >game/x.gd && echo c >docs/other.md && git add -A && git commit -qm init \
		&& git remote add origin "$O" && git push -q -u origin main && git checkout -q -b feature ) >/dev/null 2>&1
	printf '%s\n' '## What this does' 'Does the thing.' 'Second line.' '' '## Proof' 'ran it' '' '## Known weak spots' 'none' >"$BODY"
	echo "change $N" >>"$W/game/x.gd"
}
# land <args...>: run land.sh in $W with a good environment (overridable by exporting before the call); sets RC.
UNSET=""
GOOD_TEST='echo "TESTS passed=3 failed=0"'
land() {
	( cd "$W" && export PATH="$T/bin:$PATH" GH_STATE="$S" LAND_PUSH_WAITS="${LAND_PUSH_WAITS:-0 0 0 0}" \
		LAND_PR_HEAD="${LAND_PR_HEAD-head one}" LAND_PR_FOOT="${LAND_PR_FOOT-$'foot one\nfoot two'}" LAND_TRAILERS="${LAND_TRAILERS-$'Co-Authored-By: T <t@t>\nSession: abc'}" \
		LAND_TEST_CMD="${LAND_TEST_CMD-$GOOD_TEST}" LAND_LINT_CMD="${LAND_LINT_CMD-echo 'LINT problems=0'}" LAND_GOLDEN_CMD="${LAND_GOLDEN_CMD-echo 'GOLDEN same'}"
		[ -z "$UNSET" ] || unset "$UNSET"
		bash "$LAND" "$@" ) >"$OUT" 2>&1
	RC=$?
}
lastline() { tail -n 1 "$OUT"; }
fails() { [ "$RC" = 1 ] && [[ "$(lastline)" == "LAND FAIL "* ]]; }
nocommit() { eq "$(cd "$W" && git rev-parse HEAD)" "$(cd "$W" && git rev-parse origin/main)"; }
nopr() { [ ! -f "$S/log" ] || ! grep -q 'pulls -f title=' "$S/log"; }
std() { land --title "Fix the thing" --body "$BODY" "$@" -- game/x.gd; }

# --- refusals before anything happens
fresh; ( cd "$W" && git checkout -q main ); std
check refuse-main fails; check refuse-main-says-main has main "$OUT"
for k in LAND_PR_HEAD LAND_PR_FOOT LAND_TRAILERS; do
	fresh; UNSET="$k"; std; UNSET=""
	check "refuse-missing-$k" fails; check "refuse-missing-$k-named" has "$k" "$OUT"; check "refuse-missing-$k-no-commit" nocommit
done
fresh; LAND_PR_HEAD="" std; check refuse-empty-LAND_PR_HEAD fails
fresh; printf '%s\n' '## What this does' 'x' '## Known weak spots' 'z' >"$BODY"; std
check refuse-heading-missing fails; check refuse-heading-missing-named has '## Proof' "$OUT"
fresh; printf '%s\n' '## Proof' 'x' '## What this does' 'y' '## Known weak spots' 'z' >"$BODY"; std
check refuse-heading-order fails
fresh; land --title "t" --body "$BODY" --; check refuse-no-files fails
fresh; land --title "t" --body "$BODY" -- game/nope.gd; check refuse-missing-file fails
fresh; land --title "t" --body "$BODY" --allow-dirty -- game; check refuse-folder fails; check refuse-folder-says-so has "game is a folder" "$OUT"; check refuse-folder-no-commit nocommit
fresh; land --title "" --body "$BODY" -- game/x.gd; check refuse-empty-title fails
fresh; land --title "$(printf 'x%.0s' $(seq 1 111))" --body "$BODY" -- game/x.gd; check refuse-long-title fails
fresh; land --title "$(printf 'x%.0s' $(seq 1 110))" --body "$BODY" --hold -- game/x.gd; check accept-110-title eq "$RC" 0

# --- guard classes, through guard.sh alone and through land.sh
mk() { # mk <path> [big]: create the offending file in $W
	mkdir -p "$W/$(dirname "$1")"
	if [ "${2:-}" = big ]; then dd if=/dev/zero of="$W/$1" bs=1048576 count=26 >/dev/null 2>&1; elif [ "${2:-}" = music ]; then dd if=/dev/zero of="$W/$1" bs=1048576 count=17 >/dev/null 2>&1; else echo x >"$W/$1"; fi
}
for spec in "realm/a.gd:realm" "docs/realm/n.md:docs/realm" "game/crowd/c.gd:crowd" "art/tex.png.import:import" ".godot/cache.bin:godot" \
	"config/steam_credentials.json:credentials" "addons/sentry/s.gd:sentry" "keys/server.pem:pem" "k/my.key:key" "k/id_rsa:id_rsa" "k/.env:env" "k/.env.local:env-local" "k/prod.env:env-suffix" \
	"k/top_secret.txt:secret" "k/client_secret.json:secret-json" "android/release.keystore:keystore" "android/upload.jks:jks" "assets/big.bin:big"; do
	p="${spec%%:*}"; nm="${spec##*:}"
	fresh; if [ "$nm" = big ]; then mk "$p" big; else mk "$p"; fi
	( cd "$W" && bash "$GUARD" -- "$p" ) >"$OUT" 2>&1; RC=$?
	check "guard-refuses-$nm" eq "$RC" 1; check "guard-refuses-$nm-names-path" has "$p" "$OUT"; check "guard-refuses-$nm-count" has "GUARD problems=1" "$OUT"
	land --title t --body "$BODY" -- "$p"
	check "land-refuses-$nm" fails; check "land-refuses-$nm-no-commit" nocommit; check "land-refuses-$nm-no-pr" nopr
done
fresh; mk tools/versions.env; ( cd "$W" && bash "$GUARD" -- tools/versions.env game/x.gd ) >"$OUT" 2>&1; RC=$?
check guard-allows-versions-env eq "$RC" 0; check guard-ok-line has "GUARD problems=0" "$OUT"
# The game's own files that only look like the classes above: its Secrets module, a music track, look-alike names.
fresh; mk game/logic/secrets.gd; mk tests/unit/test_urn_secret.gd; mk game/input/x.keybinds.gd; mk game/foo.environment.gd; mk assets/audio/music_battle.wav music
( cd "$W" && bash "$GUARD" -- game/logic/secrets.gd tests/unit/test_urn_secret.gd game/input/x.keybinds.gd game/foo.environment.gd assets/audio/music_battle.wav ) >"$OUT" 2>&1; RC=$?
check guard-allows-the-games-own-names eq "$RC" 0; check guard-allows-own-names-line has "GUARD problems=0" "$OUT"
fresh; mk realm/a.gd; ( cd "$W" && git add realm/a.gd && git commit -qm r ) >/dev/null 2>&1
( cd "$W" && bash "$GUARD" ) >"$OUT" 2>&1; RC=$?; check guard-no-args-sees-branch-commits eq "$RC" 1
( cd "$W" && bash "$GUARD" --base=feature ) >"$OUT" 2>&1; RC=$?; check guard-base-option eq "$RC" 0
fresh; mk docs/realm/z.md; ( cd "$W" && git add docs/realm/z.md ) >/dev/null 2>&1; ( cd "$W" && bash "$GUARD" ) >"$OUT" 2>&1; RC=$?; check guard-no-args-sees-staged eq "$RC" 1
fresh; echo more >>"$W/realm_not.txt"; ( cd "$W" && echo q >>a.txt && bash "$GUARD" ) >"$OUT" 2>&1; RC=$?; check guard-no-args-unstaged-ok eq "$RC" 0

# --- dirty tree, failing checks
fresh; echo edit >>"$W/a.txt"; std
check refuse-unlisted-tracked-change fails; check refuse-unlisted-named has a.txt "$OUT"; check refuse-unlisted-no-commit nocommit
fresh; echo edit >>"$W/a.txt"; std --allow-dirty --hold
check allow-dirty-passes eq "$RC" 0
check allow-dirty-commits-only-listed eq "$(cd "$W" && git show --name-only --format= HEAD)" "game/x.gd"
fresh; echo new >"$W/untracked.txt"; std --hold
check untracked-unlisted-warns-only eq "$RC" 0; check untracked-warning-names-it has untracked.txt "$OUT"
fresh; LAND_TEST_CMD='echo "TESTS passed=2 failed=1"; exit 1' std; check failing-tests-stop fails; check failing-tests-no-commit nocommit
check failing-tests-show-summary has "TESTS passed=2 failed=1" "$OUT"
fresh; LAND_TEST_CMD='echo nothing' std; check tests-without-summary-fail fails
fresh; LAND_LINT_CMD='echo "LINT problems=2"; exit 1' std; check failing-lint-stops fails; check failing-lint-no-commit nocommit
fresh; LAND_GOLDEN_CMD='echo "GOLDEN changed"; exit 1' std; check golden-ignored-without-same eq "$RC" 0
fresh; LAND_GOLDEN_CMD='echo "GOLDEN changed"; exit 1' std --same; check golden-same-stops fails; check golden-same-no-commit nocommit

# --- the good path
fresh; std
check good-path-ok eq "$RC" 0
check good-path-last-line eq "$(lastline)" "LAND ok pr=7 url=https://github.com/o/r/pull/7 merge=auto"
check good-path-one-commit eq "$(cd "$W" && git rev-list --count origin/main..HEAD)" 1
check good-path-subject eq "$(cd "$W" && git log -1 --format=%s)" "Fix the thing"
check good-path-trailers-last eq "$(cd "$W" && git log -1 --format=%B | sed '/^$/d' | tail -n 2)" $'Co-Authored-By: T <t@t>\nSession: abc'
check good-path-blank-before-trailers eq "$(cd "$W" && git log -1 --format=%B | tail -n 4 | head -n 1 | wc -c | tr -d ' ')" 1
check good-path-body-section has "Does the thing." <(cd "$W" && git log -1 --format=%B)
check good-path-body-no-heading hasnt "## What" <(cd "$W" && git log -1 --format=%B)
check good-path-body-no-other-sections hasnt "ran it" <(cd "$W" && git log -1 --format=%B)
check good-path-pushed eq "$(cd "$W" && git rev-parse HEAD)" "$(git --git-dir="$O" rev-parse refs/heads/feature)"
check good-path-main-untouched eq "$(cd "$W" && git rev-parse origin/main)" "$(git --git-dir="$O" rev-parse refs/heads/main)"
check good-path-pr-call has "api repos/c$N/origin/pulls -f title=Fix the thing -f head=feature -f base=main" "$S/log"
check good-path-pr-number-jq has "--jq .number" "$S/log"
check good-path-assignee has "api -X POST repos/c$N/origin/issues/7/assignees -f assignees[]=c$N" "$S/log"
check good-path-automerge has "api -X PUT repos/c$N/origin/pulls/7/ccr/auto_merge -f merge_method=squash" "$S/log"
check good-path-body-starts eq "$(head -n 1 "$S/body")" "head one"
check good-path-body-ends eq "$(tail -n 2 "$S/body")" $'foot one\nfoot two'
check good-path-body-has-file has "## Known weak spots" "$S/body"
# second run on the same branch: new commit on top, no second pull request, no amend
first=$(cd "$W" && git rev-parse HEAD); echo again >>"$W/game/x.gd"; std
check second-run-ok eq "$RC" 0
check second-run-adds-commit eq "$(cd "$W" && git rev-list --count origin/main..HEAD)" 2
check second-run-no-amend eq "$(cd "$W" && git rev-parse HEAD~1)" "$first"
check second-run-one-pr eq "$(grep -c 'pulls -f title=' "$S/log")" 1
check second-run-last-line eq "$(lastline)" "LAND ok pr=7 url=https://github.com/o/r/pull/7 merge=auto"
std; check third-run-nothing-new-no-commit eq "$(cd "$W" && git rev-list --count origin/main..HEAD)" 2
check third-run-still-one-pr eq "$(grep -c 'pulls -f title=' "$S/log")" 1

# --- hold, 404 fallback, push retry
fresh; std --hold
check hold-ok eq "$RC" 0; check hold-last-line eq "$(lastline)" "LAND ok pr=7 url=https://github.com/o/r/pull/7 merge=held"
check hold-skips-merge hasnt auto_merge "$S/log"; check hold-skips-gh-pr-merge hasnt "pr merge" "$S/log"; check hold-still-assigns has assignees "$S/log"
fresh; STUB_AUTOMERGE_404=1 std
check fallback-ok eq "$RC" 0; check fallback-called has "pr merge 7 --auto --squash" "$S/log"; check fallback-tried-route-first has auto_merge "$S/log"
# a pull request that is already green cannot take auto-merge: it is merged now, at the pushed commit, under the title
fresh; STUB_AUTOMERGE_CLEAN=1 std
check clean-merges-now eq "$RC" 0; check clean-last-line eq "$(lastline)" "LAND ok pr=7 url=https://github.com/o/r/pull/7 merge=done"
check clean-merge-call has "api -X PUT repos/c$N/origin/pulls/7/merge -f merge_method=squash -f sha=$(cd "$W" && git rev-parse HEAD) -f commit_title=Fix the thing (#7)" "$S/log"
check clean-no-gh-pr-merge hasnt "pr merge" "$S/log"
fresh; STUB_AUTOMERGE_CLEAN=1 STUB_MERGE_FAIL=1 std
check clean-merge-refused-fails fails; check clean-merge-refused-names-step has "LAND FAIL merge" "$OUT"; check clean-merge-refused-says-why has "Head branch was modified" "$OUT"
fresh; STUB_AUTOMERGE_500=1 std
check automerge-other-error-fails fails; check automerge-other-error-names-step has "LAND FAIL merge" "$OUT"; check automerge-other-error-no-merge hasnt "pulls/7/merge" "$S/log"
fresh; hook="$O/hooks/pre-receive"; printf '#!/bin/sh\nif [ ! -f "%s/pushed_once" ]; then : >"%s/pushed_once"; echo refused-once >&2; exit 1; fi\n' "$S" "$S" >"$hook"; chmod +x "$hook"
std
check push-retry-succeeds eq "$RC" 0; check push-retry-landed eq "$(cd "$W" && git rev-parse HEAD)" "$(git --git-dir="$O" rev-parse refs/heads/feature)"
fresh; printf '#!/bin/sh\nexit 1\n' >"$O/hooks/pre-receive"; chmod +x "$O/hooks/pre-receive"; std
check push-gives-up fails; check push-gives-up-names-step has "LAND FAIL push" "$OUT"; check push-gives-up-no-pr nopr

[ "${1:-}" != "--list" ] || echo "cases:$NAMES" | fold -s -w 150
echo "LAND_TEST passed=$PASSED failed=$FAILED"
[ "$FAILED" = 0 ]

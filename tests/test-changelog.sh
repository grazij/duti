#!/bin/bash
#
# Regression tests for make-changelog.sh.
#
# Deliberately run against this repo's real history: the bug these guard
# against was that untyped commits were dropped silently, which a fixture of
# tidy conventional commits cannot catch -- it shares the bug's assumption.
# Expectations come from git, not hardcoded counts.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

SCRIPT="./make-changelog.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/duti-changelog-test.XXXXXX")
trap 'rm -rf "$TMP"; git worktree prune >/dev/null 2>&1' EXIT

# upstream/master at the fork point. A SHA, not a remote ref: CI has no
# upstream remote.
FORK_POINT=8b5b9a0

pass=0
fail=0

ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

# every non-merge, non-chore commit in range
releasable_hashes() {
	git log "$1..HEAD" --no-merges --pretty=tformat:'%h %s' | while IFS= read -r line; do
		case "${line#* }" in
		"chore: "* | "chore!: "* | "chore("*"): "* | "chore("*")!: "*) ;;
		*) printf '%s\n' "${line%% *}" ;;
		esac
	done
}

echo "=== T1: no releasable commit is dropped (range ${FORK_POINT}..HEAD) ==="
if ! $SCRIPT 9.9.9-test "$TMP/t1.md" "$FORK_POINT" >"$TMP/t1.out" 2>"$TMP/t1.err"; then
	bad "generator exited $? on the real fork range" "$(cat "$TMP/t1.err")"
else
	expected=$(releasable_hashes "$FORK_POINT" | sort -u)
	n_expected=$(printf '%s\n' "$expected" | grep -c .)
	missing=""
	for h in $expected; do
		grep -q "($h)" "$TMP/t1.out" || missing="$missing $h"
	done
	if [ -n "$missing" ]; then
		detail=""
		for h in $missing; do
			detail="$detail
       $h $(git log -1 --format=%s "$h")"
		done
		bad "$n_expected releasable commits, missing:$detail"
	else
		ok "all $n_expected releasable commits present"
	fi
fi

echo "=== T2: canary — the non-conventional commits that were silently dropped ==="
for h in 5c99a68 dd801ba 6543fc0; do
	subject=$(git log -1 --format=%s "$h" 2>/dev/null)
	if grep -q "($h)" "$TMP/t1.out" 2>/dev/null; then
		ok "$h  $subject"
	else
		bad "$h dropped  $subject"
	fi
done

echo "=== T3: chore release commits are excluded ==="
chores=$(git log "$FORK_POINT..HEAD" --no-merges --pretty=tformat:'%h %s' |
	grep -E ' chore(\(.*\))?!?: ' | awk '{print $1}')
if [ -z "$chores" ]; then
	ok "no chore commits in range (nothing to exclude)"
else
	leaked=""
	for h in $chores; do
		grep -q "($h)" "$TMP/t1.out" && leaked="$leaked $h"
	done
	if [ -n "$leaked" ]; then
		bad "chore commits leaked into the changelog:$leaked"
	else
		ok "$(printf '%s\n' "$chores" | grep -c .) chore commit(s) excluded"
	fi
fi

echo "=== T4: empty range exits 1 (no release), prints nothing ==="
out=$($SCRIPT 9.9.9-test "$TMP/t4.md" HEAD 2>"$TMP/t4.err")
rc=$?
if [ "$rc" -eq 1 ] && [ -z "$out" ]; then
	ok "exit 1, no output"
else
	bad "expected exit 1 and empty output, got exit $rc output='$out'"
fi

echo "=== T5: unresolvable baseline exits 2, not 1 ==="
$SCRIPT 9.9.9-test "$TMP/t5.md" no-such-ref-xyz >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
	ok "exit 2"
else
	bad "expected exit 2 (misconfiguration), got $rc" \
		"exit 1 would make CI silently skip the release instead of failing"
fi

echo "=== T6: no v* tag and no baseline exits 2, never walks all history ==="
(
	cd "$TMP" || exit 2
	git init -q repo && cd repo || exit 2
	git config user.email t@t.t && git config user.name t
	echo a >f && git add . && git commit -qm "feat: something"
) >/dev/null 2>&1
cp "$SCRIPT" "$TMP/repo/make-changelog.sh"
( cd "$TMP/repo" && ./make-changelog.sh 1.0.0 CL.md >/dev/null 2>&1 )
rc=$?
if [ "$rc" -eq 2 ]; then
	ok "exit 2"
else
	bad "expected exit 2, got $rc" \
		"an unbounded range describes all of upstream's history"
fi

# make-changelog always ranges <since>..HEAD, so T7/T8 use a detached worktree
# at a real commit to get a range that ends earlier.
WT="$TMP/wt"
if git worktree add --detach -q "$WT" 349e86f >/dev/null 2>&1; then
	cp "$SCRIPT" "$WT/make-changelog.sh"

	echo "=== T7: docs/ci alone does not trigger a release ==="
	( cd "$WT" && ./make-changelog.sh 9.9.9-test CL7.md c6b5ebb ) \
		>"$TMP/t7.out" 2>&1
	rc=$?
	if [ "$rc" -eq 1 ] && [ ! -s "$TMP/t7.out" ]; then
		ok "exit 1, no release cut for docs+ci only"
	else
		bad "expected exit 1 for a docs/ci-only range, got $rc" \
			"$(head -3 "$TMP/t7.out")"
	fi

	echo "=== T8: ...but docs/ci still appear when a release IS triggered ==="
	( cd "$WT" && ./make-changelog.sh 9.9.9-test CL8.md 022a003 ) \
		>"$TMP/t8.out" 2>&1
	rc=$?
	if [ "$rc" -ne 0 ]; then
		bad "expected exit 0 for a range containing untyped commits, got $rc"
	else
		# 349e86f is ci: -- it cannot trigger a release on its own,
		# but it must still be listed when one is cut
		absent=""
		for h in 349e86f; do
			grep -q "($h)" "$TMP/t8.out" || absent="$absent $h"
		done
		if [ -n "$absent" ]; then
			bad "non-triggering commits missing from the notes:$absent" \
				"suppressing the release trigger must not suppress the entry"
		else
			ok "ci/docs commits listed even though they cannot trigger alone"
		fi
	fi

	git worktree remove --force "$WT" >/dev/null 2>&1
else
	bad "could not create a worktree at 349e86f (shallow clone?)"
fi

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

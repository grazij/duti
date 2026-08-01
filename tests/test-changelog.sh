#!/bin/bash
#
# Regression tests for make-changelog.sh, run against this repository's real
# commit history.
#
# Why real history and not a fixture: the bug these guard against is that
# make-changelog.sh once collected only feat/fix/perf, so the fork's many
# non-conventional commits ("Add support for macOS 14, 15, and 26") vanished
# from the release notes with no error at all. The first release listed 4 of
# the 16 commits in the delta over upstream. A hand-built fixture of tidy
# conventional commits cannot catch that, because the fixture encodes the same
# assumption as the bug. Only the actual history does.
#
# Expectations are derived from git rather than hardcoded, so these cannot
# silently drift out of step with the repository.
#
# usage: tests/test-changelog.sh

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

SCRIPT="./make-changelog.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/duti-changelog-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# upstream/master at the point this fork diverged. Pinned as a SHA rather than
# a remote ref because CI has no upstream remote; it is an ancestor of master,
# so a full-depth clone always has it.
FORK_POINT=8b5b9a0

pass=0
fail=0

ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

# commits make-changelog is required to report: every non-merge commit in
# range that is not release plumbing (chore)
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
# these have no conventional prefix at all and are the substance of the fork
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
	cp "$OLDPWD/../make-changelog.sh" . 2>/dev/null ||
		cp /dev/null /dev/null
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

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

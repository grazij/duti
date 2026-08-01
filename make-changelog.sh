#!/bin/bash
#
# usage: make-changelog.sh <version> [changelog] [since-ref]
#
# Prepends a section to the changelog and prints it for use as release notes.
# Exit 1: nothing worth releasing. Exit 2: usage error.

set -euo pipefail

version="${1:-}"
changelog="${2:-CHANGELOG.md}"
since="${3:-}"

if [ -z "$version" ]; then
	printf 'usage: %s <version> [changelog] [since-ref]\n' "$0" >&2
	exit 2
fi

# No "walk all history" fallback: this fork's history includes all of
# upstream's, so an unbounded range describes 15 years of someone else's
# commits. Nor can we fall back to any-recent-tag -- upstream's duti-1.5.2
# through 1.5.4 are not ancestors of this branch.
if [ -z "$since" ]; then
	since=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
fi
if [ -z "$since" ]; then
	printf '%s: no v* tag found and no since-ref given.\n' "$0" >&2
	printf 'Pass an explicit baseline, e.g. the upstream ref this forked from:\n' >&2
	printf '  %s %s CHANGELOG.md upstream/master\n' "$0" "$version" >&2
	exit 2
fi
if ! git rev-parse --verify --quiet "$since^{commit}" >/dev/null; then
	printf '%s: baseline %s does not resolve to a commit\n' "$0" "$since" >&2
	exit 2
fi

range="$since..HEAD"

# tformat: not format: -- format: omits the trailing newline, which makes
# `while read` silently drop the last commit.
log_range() {
	git log "$range" --no-merges --pretty=tformat:'%h %s'
}

collect() {
	log_range | while IFS= read -r line; do
		hash="${line%% *}"
		subject="${line#* }"
		case "$subject" in
		"$1: "* | "$1!: "* | "$1("*"): "* | "$1("*")!: "*)
			printf '* %s (%s)\n' "${subject#*: }" "$hash"
			;;
		esac
	done
}

ALL_TYPES="feat fix perf chore docs ci style test build refactor revert"

has_type() {
	case "$1" in
	"$2: "* | "$2!: "* | "$2("*"): "* | "$2("*")!: "*) return 0 ;;
	esac
	return 1
}

is_conventional() {
	for t in $ALL_TYPES; do
		if has_type "$1" "$t"; then
			return 0
		fi
	done
	return 1
}

# strip "type: " only when there is one, so an untyped subject containing a
# colon is not truncated
entry() {
	if is_conventional "$1"; then
		printf '* %s (%s)\n' "${1#*: }" "$2"
	else
		printf '* %s (%s)\n' "$1" "$2"
	fi
}

# Catch-all. Without it, untyped subjects -- most of this fork's history --
# vanish from the changelog silently.
collect_other() {
	log_range | while IFS= read -r line; do
		hash="${line%% *}"
		subject="${line#* }"
		if has_type "$subject" feat || has_type "$subject" fix ||
			has_type "$subject" perf || has_type "$subject" chore; then
			continue
		fi
		entry "$subject" "$hash"
	done
}

collect_nonconventional() {
	log_range | while IFS= read -r line; do
		hash="${line%% *}"
		subject="${line#* }"
		if ! is_conventional "$subject"; then
			entry "$subject" "$hash"
		fi
	done
}

# ! before the colon, or a BREAKING CHANGE: footer
collect_breaking() {
	log_range | while IFS= read -r line; do
		hash="${line%% *}"
		subject="${line#* }"
		case "$subject" in
		*"!: "*) printf '* %s (%s)\n' "${subject#*: }" "$hash" ;;
		esac
	done
	git log "$range" --no-merges --grep='^BREAKING CHANGE:' \
		--pretty=tformat:'%h %s' | while IFS= read -r line; do
		hash="${line%% *}"
		subject="${line#* }"
		case "$subject" in
		*"!: "*) ;; # already listed above
		*) printf '* %s (%s)\n' "${subject#*: }" "$hash" ;;
		esac
	done
}

section=""
append() {
	if [ -n "$2" ]; then
		section="${section}### $1"$'\n\n'"$2"$'\n\n'
	fi
}

append "BREAKING CHANGES" "$(collect_breaking)"
append "Features" "$(collect feat)"
append "Bug Fixes" "$(collect fix)"
append "Performance" "$(collect perf)"
append "Other Changes" "$(collect_other)"

if [ -z "$section" ]; then
	exit 1
fi

# Notes list everything; only these types justify cutting a release. Untyped
# counts as substantive -- this fork's real work is mostly untyped subjects.
# A docs/ci-only run rides along in the next real release.
if [ -z "$(collect_breaking)$(collect feat)$(collect fix)$(collect perf)$(collect_nonconventional)" ]; then
	exit 1
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/changelog.XXXXXX")
trap 'rm -f "$tmp"' EXIT

{
	printf '## %s\n\n' "$version"
	printf '%s' "$section"
	if [ -f "$changelog" ]; then
		cat "$changelog"
	fi
} >"$tmp"
cat "$tmp" >"$changelog"

printf '%s' "$section"

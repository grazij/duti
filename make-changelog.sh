#!/bin/bash
#
# Write a CHANGELOG.md section for a version from the commits since the
# previous v* tag, and print that section body on stdout so the caller can
# reuse it as release notes.
#
# usage: make-changelog.sh <version> [changelog] [since-ref]
#
# Exits 1, printing nothing, when no release-worthy commit has landed. The
# workflow reads that as "no release this run". Exits 2 on a usage error,
# including the case where no baseline can be determined -- see below.
#
# This replaces TriPSs/conventional-changelog-action, which cannot be used
# here: it bumps the version with semver.inc(), which discards the +grazij.N
# build metadata, and it offers no way to skip its own tagging.

set -euo pipefail

version="${1:-}"
changelog="${2:-CHANGELOG.md}"
since="${3:-}"

if [ -z "$version" ]; then
	printf 'usage: %s <version> [changelog] [since-ref]\n' "$0" >&2
	exit 2
fi

# Baseline for the commit range. An explicit since-ref wins; otherwise the
# most recent v* tag.
#
# There is deliberately no "walk all history" fallback. This repo is a fork,
# and its history reaches back through all of upstream's -- so before the
# first v* tag existed, an unbounded range silently produced a changelog
# describing 15 years of someone else's commits. Failing loudly and making
# the caller name a baseline is the safer default. Note also that upstream's
# duti-1.5.2 through duti-1.5.4 tags are not ancestors of this branch, so
# "most recent reachable tag of any pattern" is not a usable fallback either.
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

# %h and %s for every non-merge commit in range. tformat: (not format:)
# terminates each line with a newline; format: omits the final one, which
# makes `while read` silently drop the last commit.
log_range() {
	git log "$range" --no-merges --pretty=tformat:'%h %s'
}

# subjects carrying the given conventional type, with optional (scope) and !
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

# Everything not already reported under Features, Bug Fixes or Performance,
# and not release plumbing. Without this bucket, plain non-conventional
# subjects -- which most of this fork's history uses -- vanish from the
# changelog without a trace.
collect_other() {
	log_range | while IFS= read -r line; do
		hash="${line%% *}"
		subject="${line#* }"
		case "$subject" in
		"feat: "* | "feat!: "* | "feat("*"): "* | "feat("*")!: "*) ;;
		"fix: "* | "fix!: "* | "fix("*"): "* | "fix("*")!: "*) ;;
		"perf: "* | "perf!: "* | "perf("*"): "* | "perf("*")!: "*) ;;
		"chore: "* | "chore!: "* | "chore("*"): "* | "chore("*")!: "*) ;;
		*) printf '* %s (%s)\n' "${subject#*: }" "$hash" ;;
		esac
	done
}

# breaking: ! before the colon, or a BREAKING CHANGE: footer in the body
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

# prepend the new section, keeping whatever is already in the file
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

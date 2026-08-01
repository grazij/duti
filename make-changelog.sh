#!/bin/bash
#
# Write a CHANGELOG.md section for a version from the conventional-commit
# subjects since the previous v* tag, and print that section body on stdout
# so the caller can reuse it as release notes.
#
# Exits 1, printing nothing, when no release-worthy commit has landed. The
# workflow reads that as "no release this run".
#
# This replaces TriPSs/conventional-changelog-action, which cannot be used
# here: it bumps the version with semver.inc(), which discards the +grazij.N
# build metadata, and it offers no way to skip its own tagging.

set -euo pipefail

version="${1:-}"
changelog="${2:-CHANGELOG.md}"

if [ -z "$version" ]; then
	printf 'usage: %s <version> [changelog]\n' "$0" >&2
	exit 2
fi

prev=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
if [ -n "$prev" ]; then
	range="$prev..HEAD"
else
	range="HEAD"
fi

# print "* subject (hash)" for every commit whose conventional type is $1,
# accepting an optional (scope) and an optional ! breaking marker
collect() {
	git log "$range" --no-merges --pretty=tformat:'%h %s' | while IFS= read -r line; do
		hash="${line%% *}"
		subject="${line#* }"
		case "$subject" in
		"$1: "* | "$1!: "* | "$1("*"): "* | "$1("*")!: "*)
			printf '* %s (%s)\n' "${subject#*: }" "$hash"
			;;
		esac
	done
}

# commits marked breaking, either with ! before the colon or with a
# BREAKING CHANGE: footer in the body
collect_breaking() {
	git log "$range" --no-merges --pretty=tformat:'%h %s' | while IFS= read -r line; do
		hash="${line%% *}"
		subject="${line#* }"
		case "$subject" in
		*"!: "*)
			printf '* %s (%s)\n' "${subject#*: }" "$hash"
			;;
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
	# $1 = heading, $2 = entries
	if [ -n "$2" ]; then
		section="${section}### $1"$'\n\n'"$2"$'\n\n'
	fi
}

append "BREAKING CHANGES" "$(collect_breaking)"
append "Features" "$(collect feat)"
append "Bug Fixes" "$(collect fix)"
append "Performance" "$(collect perf)"

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

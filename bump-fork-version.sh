#!/bin/bash
#
# Increment the fork counter in version.toml and print the new version.
# <upstream core>+<fork>.<counter>, e.g. 1.5.5+grazij.1 -- the core moves by
# hand only. Refuses to guess if the version is not in that shape.

set -euo pipefail

FORK="grazij"
VERSION_FILE="${1:-version.toml}"

die() {
	printf 'bump-fork-version: %s\n' "$1" >&2
	exit 1
}

[ -f "$VERSION_FILE" ] || die "no such file: $VERSION_FILE"

current=$(sed -n \
	's/^version[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
	"$VERSION_FILE")
[ -n "$current" ] || die "no version key in $VERSION_FILE"

case "$current" in
	*"+$FORK."*) ;;
	*) die "version '$current' is not <core>+$FORK.<counter>" ;;
esac

core="${current%%+*}"
counter="${current##*"+$FORK."}"

case "$counter" in
	'' | *[!0-9]*) die "counter '$counter' in '$current' is not a number" ;;
esac

next="$core+$FORK.$((counter + 1))"

# rewrite in place via a temp file, so a failed write cannot truncate
# version.toml, and so the original file's permissions are preserved
tmp=$(mktemp "${TMPDIR:-/tmp}/version.toml.XXXXXX")
trap 'rm -f "$tmp"' EXIT

sed "s|^version[[:space:]]*=.*|version = \"$next\"|" "$VERSION_FILE" >"$tmp"
cat "$tmp" >"$VERSION_FILE"

printf '%s\n' "$next"

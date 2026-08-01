#!/bin/bash
#
# Point Formula/duti.rb at a released tag: rewrite url, version and sha256.
# Version defaults to version.toml. The tag must already be pushed -- GitHub
# generates the tarball on demand, so the checksum does not exist before then.

set -euo pipefail

REPO="grazij/duti"
FORMULA="Formula/duti.rb"
VERSION_FILE="version.toml"
RETRIES=6
RETRY_DELAY=5

die() {
	printf 'update-formula: %s\n' "$1" >&2
	exit 1
}

version="${1:-}"
if [ -z "$version" ]; then
	version=$(sed -n \
		's/^version[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
		"$VERSION_FILE")
	[ -n "$version" ] || die "no version key in $VERSION_FILE"
fi
version="${version#v}"

[ -f "$FORMULA" ] || die "no such file: $FORMULA"

# a literal + in a URL path is ambiguous enough that GitHub's redirects
# mishandle it; %2B is not
tag_path="v${version//+/%2B}"
url="https://github.com/$REPO/archive/refs/tags/$tag_path.tar.gz"

tarball=$(mktemp "${TMPDIR:-/tmp}/duti-formula.XXXXXX")
tmp=$(mktemp "${TMPDIR:-/tmp}/duti-formula-rb.XXXXXX")
trap 'rm -f "$tarball" "$tmp"' EXIT

# a tag tarball 404s for a few seconds after the tag is pushed
attempt=1
while :; do
	if curl -fsSL -o "$tarball" "$url"; then
		break
	fi
	[ "$attempt" -lt "$RETRIES" ] || die "cannot fetch $url"
	printf 'update-formula: fetch failed, retrying in %ss (%s/%s)\n' \
		"$RETRY_DELAY" "$attempt" "$RETRIES" >&2
	sleep "$RETRY_DELAY"
	attempt=$((attempt + 1))
done

sha256=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
[ -n "$sha256" ] || die "empty checksum for $url"

# livecheck's `url :stable` has no quotes, so the url expression skips it
sed -e "s|^\([[:space:]]*\)url \".*\"|\1url \"$url\"|" \
	-e "s|^\([[:space:]]*\)version \".*\"|\1version \"$version\"|" \
	-e "s|^\([[:space:]]*\)sha256 \".*\"|\1sha256 \"$sha256\"|" \
	"$FORMULA" >"$tmp"

grep -q "\"$url\"" "$tmp" || die "url line not found in $FORMULA"
grep -q "version \"$version\"" "$tmp" || die "version line not found in $FORMULA"
grep -q "sha256 \"$sha256\"" "$tmp" || die "sha256 line not found in $FORMULA"

if cmp -s "$tmp" "$FORMULA"; then
	printf '%s already at %s\n' "$FORMULA" "$version"
	exit 0
fi

cat "$tmp" >"$FORMULA"
printf '%s -> %s (%s)\n' "$FORMULA" "$version" "$sha256"

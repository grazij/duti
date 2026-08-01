# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`duti` is a small C99 command-line tool for macOS that sets and queries default
application handlers via LaunchServices (UTIs, URL schemes, filename extensions,
MIME types). Public domain / unsupported upstream. It links only against
`ApplicationServices` and `CoreFoundation` — no third-party dependencies.

## Build

```sh
autoreconf -i      # regenerate configure from configure.ac + aclocal.m4
./configure
make               # produces ./duti
sudo make install  # BINDIR + MANDIR/man1
make clean         # objects + binary
make distclean     # also removes configure output, Makefile, version.c
```

Requires autoconf (`brew install autoconf`) — it is not part of the Xcode
command line tools and may be absent on a fresh machine.

**After changing `version.toml`, run `autoreconf -if`, not `autoreconf -i`.**
`AC_INIT` reads the version via `m4_esyscmd_s` at autoconf time, and plain
`autoreconf` skips autoconf because `configure` is newer than `configure.ac` —
`version.toml` is not in its dependency graph. `./configure` alone is likewise
not enough. Nothing errors; `duti -V` silently reports the previous version.

`autoreconf -i` also rewrites `config.guess`, `config.sub` and `install-sh`,
producing thousands of lines of unrelated diff. Revert those.

CI (`.github/workflows/makefile.yml`) runs `tests/test-changelog.sh`, then
`autoreconf -if && ./configure && make` on `macos-latest`, for both pushes to
`master` and pull requests against it. The release steps are gated on
`github.event_name == 'push'`, so a pull request gets tests and a build and
nothing else.

The **C code has no test suite** — verification means a clean build plus manual
invocation (`./duti -x jpg`, `./duti -d public.html`, `./duti -h`, `./duti -c -`).

`tests/test-changelog.sh` covers `make-changelog.sh` only. It runs against the
repo's **real history** rather than a fixture, because the bug it guards against
was invisible to a fixture of well-formed conventional commits — such a fixture
encodes the same assumption as the bug. It asserts by commit hash with
expectations derived from `git log`, so it cannot drift. `FORK_POINT=8b5b9a0` is
pinned as a SHA, not `upstream/master`, since CI has no upstream remote. T7/T8
use a detached worktree to get a range not ending at `HEAD`.

Changes to `make-changelog.sh` should be mutation-checked — a suite never seen
to fail is worth nothing:

| revert this fix | and this fails |
|---|---|
| remove the "Other Changes" bucket | T1, T2 — names the 12 dropped commits |
| restore the unbounded-history fallback | T6 |
| remove the release-trigger check | T7 |
| exclude `docs`/`ci` from the notes to stop them triggering | T1 **and** T8 |

### macOS version gating

`aclocal.m4` defines `DUTI_CHECK_SDK` and `DUTI_CHECK_DEPLOYMENT_TARGET`, which
switch on `${host_os}`. Everything from Big Sur onward is handled by a single
`darwin2*` case in both macros, so **a new macOS release needs no change here**:
the SDK is always `MacOSX.sdk` with `-arch x86_64 -arch arm64`, and the
deployment target is a fixed `11`.

That 11 is deliberate and is *not* the host's own version. It is the floor the
arm64 slice imposes — the source itself calls no Launch Services or `UTType` API
newer than 10.5 — so the binary runs on macOS 11 and later no matter which
release built it. The macro used to map each `darwinNN` to its own OS version,
which meant a build on macOS 26 carried `minos 26.0` and ran nowhere else.
Beware if reviving that scheme: the mapping is not `NN - 11` past Ventura, since
Apple jumped the marketing version from 15 to 26 (`darwin23`→`14`,
`darwin24`→`15`, `darwin25`→`26`).

The pre-`darwin20` cases are untouched and still map each old host to its
matching SDK and target. If one of *those* is ever unmatched, `configure` fails
with "not a supported system", and neither `--with-macosx-sdk` nor
`--with-macosx-deployment-target` works around it: the `case` runs regardless and
its `*)` branch raises `AC_MSG_ERROR` before either value is consulted. The case
must be added. (The deployment-target `case` has no `*)` branch — an unmatched
host there silently yields an empty target instead.)

Those macros feed `Makefile.in`'s `OPTOPTS` (`-isysroot`, `-arch` flags,
`-mmacosx-version-min`); a current build produces a real 2-architecture Mach-O.
Confirm with `vtool -show-build duti` — both slices should read `minos 11.0`.

`--with-macosx-arches` overrides the arch flags (the Homebrew formula passes
`-arch <native>`). Its assignment sits **after** the `case`, not before it like
`--with-macosx-sdk`'s: the case writes `sdk_path`, but it writes `macosx_arches`
directly and would clobber a value set ahead of it.

## Architecture

Five translation units, linked as `version.o util.o plist.o handler.o duti.o`:

- **`duti.c`** — `main()`, `getopt` dispatch, and the `rtm[]` role table
  (`none`/`viewer`/`editor`/`shell`/`all` → `kLSRoles*`). Query flags (`-d`, `-l`,
  `-x`, `-u`, `-e`, `-V`) `return`/`exit` directly from the getopt loop. Everything
  else falls through to source selection: it `stat()`s the config path and picks
  one of three function pointers — `dirsethandler` (directory), `psethandler`
  (`*.plist`), or `fsethandler` (settings file, or stdin when handed NULL).
  Also holds `usage()`, `config_exists()`, and `default_config_path()`, all
  `static`.
- **`handler.c`** — all LaunchServices work. The three `*sethandler` readers each
  parse their own format and converge on **`duti_handler_set(bid, type, role)`**,
  the single choke point for every write path. Change behavior there, not in the
  readers.
- **`plist.c`** — reads an XML plist into a `CFDictionaryRef` via CFReadStream
  (no Cocoa). `plist.h` defines the `DUTI*` plist keys.
- **`util.c`** — `parseline()` (splits a settings line into 2 or 3 fields; its
  return value *is* the handler type), CFString↔C-string helpers, and `lladd()`,
  which builds a lexically sorted list so a settings directory applies in
  predictable filename order (handler precedence).
- **`version.c`** — generated from `version.c.in` by `configure`; gitignored.

### Key invariants

- `parseline()`'s return value doubles as the discriminator
  `DUTI_TYPE_URL_HANDLER` (2 fields) vs `DUTI_TYPE_UTI_HANDLER` (3 fields).
- In `duti_handler_set()`, **`role == NULL` means "URL scheme"**, non-NULL means
  "UTI/content type". That convention is how a 2-argument `-s` reaches
  `LSSetDefaultHandlerForURLScheme` instead of
  `LSSetDefaultRoleHandlerForContentType`.
- Type coercion also lives in `duti_handler_set()`: a leading `.` or no `.` at all
  is treated as a filename extension, a `/` as a MIME type, and both are run
  through `UTTypeCreatePreferredIdentifierForTag` before being set. A bare
  dotted string is passed through as a literal UTI.
- `set_uti_handler()` rejects anything failing `duti_is_conformant_uti()`
  (conformance to item/content/message/contact/archive), so LaunchServices never
  sees a nonsense type.
- `duti_handler_set()` also rejects a coerced type that resolves to a **dynamic
  UTI** (`dyn.` prefix). That is what the OS synthesises for an extension or MIME
  type nothing has registered, and LaunchServices refuses to bind a handler to
  one, failing with `paramErr` (-50). The check turns that into a readable error
  and exit status 2.
- `nroles` is a global assigned in `main()` *after* the getopt loop, and
  `handler.c` reads it as `extern`. Any new code path that reaches
  `duti_handler_set()` with a role must not bypass that assignment.
- The `ac - optind` switch in `main()` **returns directly from its `-s` cases
  without consulting `err`**. Any rule that must reject an `-s` invocation has
  to be enforced *before* that switch — that is why the `-c`/`-s` conflict check
  calls `usage()` and exits on the spot rather than doing `err++`. Setting `err`
  there would be silently ignored.
- `fsethandler( NULL )` reads stdin. That is how `-c -` is implemented, and it
  is the only remaining path to stdin now that the positional operand is gone.

### CLI surface (diverges from upstream)

`-c config` replaced the positional `settings_path` operand, which was removed.
See duti.1 for the interface; the non-obvious parts:

- `~/.config` is skipped when `XDG_CONFIG_HOME` is set and non-empty. That is
  what the XDG spec requires, not an oversight.
- `-h` goes to stdout and exits 0; usage from an *error* goes to stderr with
  exit 1. `usage()` takes a `FILE *` for that reason — do not hardcode `stderr`.
- `-?` was deliberately not added.

### Known gaps worth knowing before "fixing" them

- **The build is warning-free** — `make 2>&1 | grep -c warning:` prints `0`,
  so any warning is a regression. Four deprecated Launch Services calls carry
  *scoped* `#pragma clang diagnostic` blocks at the call site. Keep them scoped:
  a file-wide pragma or `-Wno-deprecated-declarations` in `OPTOPTS` would hide
  future deprecations too. Their replacements are `NSWorkspace` methods, so
  taking them means Objective-C and AppKit, and upstream issue #29 shows it does
  *not* fix the `-54` errors.
- The `UTType*` calls are deprecated as of macOS 12 but **do not warn**, since
  the deployment target is 11 and clang only reports a deprecation once the
  target reaches it. An LSP ignoring `-mmacosx-version-min` will flag them
  anyway; that is a tooling artifact. Raising the target past 11 makes them real.
- `autoreconf` also warns that `AC_CANONICAL_SYSTEM`, `AC_HELP_STRING`, and
  `AC_ERROR` are obsolete. Harmless with current autoconf; likewise expected.

## Code style

Existing C is BSD/K&R with an unusual layout — the return type sits on its own
line with the function name unindented at column 0, indentation is tabs, and
parentheses are padded (`printf( "%s\n", tmp )`). Match the surrounding file
rather than reformatting. `configure.ac` adds `-Wall -Wmissing-prototypes` under
GCC/Clang, so declare prototypes for anything non-`static`.

## Packaging / release

`version.toml` is the single source of truth for the version. `configure.ac`
reads it via `m4_esyscmd_s` into `AC_INIT`, and `Makefile.in`'s `dist` target
greps it for `DISTDIR`. It replaced the old `VERSION` file (which read
`internal`) and the `AC_INIT(dh, INTERNAL, ...)` placeholder. Bump it there and
nowhere else; `./duti -V` prints whatever it says.

### Fork versioning

Versions are `<upstream core>+grazij.<counter>`, e.g. `1.5.5+grazij.1`. The core
mirrors upstream's last release and changes **only by hand**; releases move the
counter. `./bump-fork-version.sh` does that and nothing else, refusing to run if
the version is not in that shape.

The `+` suffix is why the third-party changelog action is gone. It bumped with
`semver.inc()`, which **discards build metadata** — `1.5.5+grazij.1` would come
back as `1.5.6` — and it has no `skip-tag` input, so it would tag that wrong
version regardless of what else it was told to skip. `./make-changelog.sh`
replaces it: it groups conventional-commit subjects since the last `v*` tag,
prepends a section to `CHANGELOG.md`, prints the section for release notes, and
exits 1 when nothing release-worthy has landed.

Three constraints in `make-changelog.sh`, each of which once produced a
*plausible but wrong* changelog rather than an error:

- `--pretty=tformat:`, never `format:` — the latter omits the trailing newline,
  so `while read` silently drops the last commit in range.
- The **"Other Changes"** bucket catches every non-`chore` commit not already
  reported. Do not remove it: most of this fork's history predates conventional
  commits, and collecting only `feat`/`fix`/`perf` dropped 12 of 16 commits from
  the first release, silently.
- **Notes content and release triggering are separate decisions.** Notes list
  every non-`chore` commit; only breaking/`feat`/`fix`/`perf`/untyped trigger a
  release. Untyped must trigger — this fork's real work is mostly untyped
  subjects. Suppressing `docs`/`ci` triggering by dropping them from
  `collect_other` recreates the silent-drop bug; T8 catches that.

It exits 2 when there is no `v*` tag and no baseline. There is deliberately no
"walk all history" fallback — this repo's history includes all of upstream's.
Nor is any-recent-tag usable: upstream's `duti-1.5.2`–`1.5.4` are not ancestors
of this branch, so `git describe` without `--match` lands on `duti-1.5.1`. To
regenerate a past release, name the baseline:

```sh
./make-changelog.sh 1.5.5+grazij.1 CHANGELOG.md upstream/master
```

Homebrew orders these versions correctly (`1.5.5+grazij.1` > `1.5.5`), because
its tokenizer treats `+`, `-`, and `.` identically. Its version *detection* does
not: `Version.detect` on `.../v1.5.5+grazij.1.tar.gz` returns `1`. A formula
must therefore pin `version` explicitly and use a custom `livecheck` regex — see
README.md.

### Homebrew formula

`Formula/duti.rb` is authored here and copied to `grazij/homebrew-tap` by hand;
nothing pushes to the tap. Non-obvious parts:

- The url percent-encodes `+` as `%2B`, and the tarball unpacks to
  `duti-1.5.5-grazij.3/` — GitHub rewrites `+` to `-` in the directory name.
- `autoconf` is a build dependency because `configure` is gitignored and so is
  absent from a tag tarball.
- `--with-macosx-sdk=#{MacOS.sdk_path}` is not optional. The configure default
  is an `/Applications/Xcode.app/...` path, and a Homebrew user with only the
  Command Line Tools has no such directory.
- `--with-macosx-arches` is belt and braces: Homebrew's `cc` shim already drops
  `-arch` flags unless a formula sets `ENV.permit_arch_flags`, so the build was
  native-only even before the option existed. It stops `configure` from
  emitting flags that get silently stripped, and halves the compile.
- An unknown `--with-*` is only a configure *warning*, so a formula pointing at
  a tag older than the option still builds — universal, then thinned by the shim.

`./update-formula.sh [VERSION]` rewrites the url, version and sha256 lines. It
curls the tag tarball to hash it, with a retry loop because that URL 404s for a
few seconds after the tag is pushed. It is idempotent and exits 0 unchanged,
which is what lets CI gate its commit on `git diff --quiet`.

The workflow's `Update Homebrew formula` step must stay **after** `Commit and
tag` — the tarball does not exist until the tag is pushed — and is placed after
`GitHub Release` so a failure there cannot block shipping. Its commit is
`chore(release): ... [skip ci]`: `chore` keeps it out of the next changelog and
stops it triggering a release, `[skip ci]` stops the loop. A release therefore
lands *two* commits on `master`.

Verify a formula change with `brew style Formula/duti.rb`, then a throwaway tap
(`brew tap-new grazij/dutitest --no-git`, copy the file in, then
`brew audit --strict` and `brew install --build-from-source`). `brew audit`
takes a formula *name*, never a path.

`chmod 644` the copy. Git records mode 644, but a checkout or a `cp` under a
077 umask produces 600, and both audit and style reject that.

`make dist` and `make pkg` are release-only targets and shell out to `sudo`,
`pkgbuild`, and `openssl`. `make pkg` still substitutes `_DUTI_BUILD_DATE` in
`duti.1`, which is why the checked-in man page carries a literal placeholder in
its `.TH` line — leave it alone during normal development. `duti.1` is groff
`man` macros, not `mdoc`.

CI releases on every push to `master`. Step order in
`.github/workflows/makefile.yml` is load-bearing: prepare (bump + changelog,
pushing nothing) → build → commit and tag → release. The bump must precede
`Configure` because `AC_INIT` resolves the version at autoconf time, and the tag
must follow the build so a broken build cannot ship. The release commit carries
`[skip ci]`; without it the push to `master` retriggers the workflow and loops.
Needs `contents: write` and `fetch-depth: 0`. Nothing fires from a branch or PR.

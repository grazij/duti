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
`AC_INIT` pulls the version in through `m4_esyscmd_s`, which autoconf evaluates
when it *generates* `configure`. Plain `autoreconf` skips autoconf entirely
because `configure` is newer than `configure.ac` — `version.toml` is not in its
dependency graph — so the old version stays baked into `configure` and into the
binary. `./configure` alone is likewise not enough. This is easy to miss because
nothing errors; `duti -V` just silently reports the previous version.

Note also that `autoreconf -i` rewrites `config.guess`, `config.sub`, and
`install-sh` to whatever versions the local autoconf ships, which shows up as
thousands of lines of unrelated diff. Revert those unless you actually mean to
update them.

There is **no test suite**. CI (`.github/workflows/makefile.yml`) runs
`autoreconf -if && ./configure && make` on `macos-latest` for both pushes to
`master` and pull requests against it. The release steps are gated on
`github.event_name == 'push'`, so a pull request gets a build and nothing else.
Verification means a clean build plus manual invocation (`./duti -x jpg`,
`./duti -d public.html`).

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

- **`-c config`** replaced the positional `settings_path` operand, which was
  removed. `-` means stdin, per POSIX Utility Syntax Guideline 13.
- With no `-c`, `default_config_path()` returns the first of
  `$XDG_CONFIG_HOME/duti/config`, `~/.config/duti/config`, `~/.duti/config`
  that exists, or NULL. `~/.config` is deliberately skipped when
  `XDG_CONFIG_HOME` is set and non-empty — that is what the XDG spec requires,
  not an oversight. NULL means usage on stderr, exit 1.
- **`-h` prints to stdout and exits 0.** Usage from a command-line *error* still
  goes to stderr with exit 1. Both come from the same `usage( progname, FILE * )`,
  so the stream is the caller's choice — do not hardcode `stderr` in it.
- `-?` was considered and deliberately **not** added. An unknown option still
  reaches the error path and prints usage on stderr. (In zsh a bare `-?` is a
  glob anyway and never reaches the program.)

### Known gaps worth knowing before "fixing" them

- **The build is warning-free. Keep it that way** —
  `make 2>&1 | grep -c warning:` should print `0`, and any warning at all is
  now a regression rather than noise to be filtered.

  It got there two ways. `plist.c` genuinely moved to
  `CFPropertyListCreateWithStream`. The four remaining deprecated Launch
  Services calls are wrapped in *scoped* `#pragma clang diagnostic push` /
  `ignored "-Wdeprecated-declarations"` / `pop` at the call site:
  `LSCopyAllHandlersForURLScheme` and `LSCopyDefaultHandlerForURLScheme` in
  `uti_handler_show()`, `LSGetApplicationForInfo` and `LSCopyDisplayNameForURL`
  in `duti_default_app_for_extension()`. The scoping is the point — do **not**
  collapse them into a file-wide pragma or an `OPTOPTS`
  `-Wno-deprecated-declarations`, which would hide future deprecations too.
  Their replacements are all `NSWorkspace` methods, so taking them means
  Objective-C and AppKit; upstream issue #29 also establishes that migrating
  does *not* fix the `-54` errors people hit.

- `UTTypeConformsTo`, `UTTypeCreatePreferredIdentifierForTag`,
  `UTTypeCopyDescription` and the `kUTType*` constants are deprecated as of
  macOS 12, but **do not warn here**, because the deployment target is 11 and
  clang only reports a deprecation once the target reaches the deprecating
  release. An IDE or language server that ignores `-mmacosx-version-min` will
  show them as warnings anyway; that is a tooling artifact, not a build issue.
  Raising the deployment target past 11 would make all ten of them real.
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

If you touch `make-changelog.sh`, note that it reads `git log` with
`--pretty=tformat:`, not `--pretty=format:`. The latter omits the trailing
newline, which makes `while read` silently drop the **last** commit in the
range — a bug that hides itself whenever that commit happens not to be a
`feat`/`fix`.

Homebrew orders these versions correctly (`1.5.5+grazij.1` > `1.5.5`), because
its tokenizer treats `+`, `-`, and `.` identically. Its version *detection* does
not: `Version.detect` on `.../v1.5.5+grazij.1.tar.gz` returns `1`. A formula
must therefore pin `version` explicitly and use a custom `livecheck` regex — see
README.md.

`make dist` and `make pkg` are release-only targets and shell out to `sudo`,
`pkgbuild`, and `openssl`. `make pkg` still substitutes `_DUTI_BUILD_DATE` in
`duti.1`, which is why the checked-in man page carries a literal placeholder in
its `.TH` line — leave it alone during normal development. `duti.1` is groff
`man` macros, not `mdoc`.

CI cuts releases automatically from conventional commit messages on every push
to `master`. The order in `.github/workflows/makefile.yml` matters:

1. **Prepare release** — `bump-fork-version.sh`, then `make-changelog.sh`. If
   the latter exits 1, the bump is rolled back with `git checkout -- version.toml`
   and the release is skipped. Nothing is pushed yet.
2. **Configure / Build / Verify** — must come *after* the bump, since `AC_INIT`
   resolves the version at autoconf time, and *before* the tag, so a broken
   build cannot be released.
3. **Commit and tag** — commits `version.toml` + `CHANGELOG.md` with `[skip ci]`
   in the message. Without that marker the push to `master` retriggers this same
   workflow and loops.
4. **GitHub Release** — `softprops/action-gh-release` with the tag and the
   changelog section from step 1.

The job needs `permissions: contents: write` and `fetch-depth: 0`; the default
shallow clone has no tags, so the changelog range would be wrong. Nothing fires
from a topic branch or a pull request.

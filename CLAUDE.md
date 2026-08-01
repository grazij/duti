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

There is **no test suite**. CI (`.github/workflows/makefile.yml`) only runs
`autoreconf -i && ./configure && make` on `macos-latest`. Verification means a
clean build plus manual invocation (`./duti -x jpg`, `./duti -d public.html`).

### macOS version gating — the usual reason a build fails

`aclocal.m4` defines `DUTI_CHECK_SDK` and `DUTI_CHECK_DEPLOYMENT_TARGET`, which
switch on `${host_os}` (`darwin8*` … `darwin25*`). An unmatched `darwin` version
makes `configure` fail with "not a supported system". Adding a new macOS release
means adding a `darwinNN*` case to **both** macros — SDK path plus `macosx_arches`
in the first, deployment target string in the second (see commits "Adding support
for latest macos" and "Add ventura version mapping"). The `--with-macosx-sdk` and
`--with-macosx-deployment-target` flags do *not* work around a missing case: the
`case` statement runs regardless and its `*)` branch raises `AC_MSG_ERROR` before
either value is consulted. The case must be added.

The newest mapped case is `darwin25` (macOS 26). Note the OS-version mapping is
not `NN - 11` past Ventura — Apple jumped the marketing version from 15 to 26, so
`darwin23`→`14`, `darwin24`→`15`, `darwin25`→`26`. Each host also gets its own
version as the deployment target, so a binary built on macOS 26 carries
`minos 26.0` and will not run on older systems.

Those macros feed `Makefile.in`'s `OPTOPTS` (`-isysroot`, `-arch` flags,
`-mmacosx-version-min`). Universal builds are expressed as `macosx_arches`
(`-arch x86_64 -arch arm64` for darwin20 and later); a current build produces a
real 2-architecture Mach-O.

## Architecture

Five translation units, linked as `version.o util.o plist.o handler.o duti.o`:

- **`duti.c`** — `main()`, `getopt` dispatch, and the `rtm[]` role table
  (`none`/`viewer`/`editor`/`shell`/`all` → `kLSRoles*`). Query flags (`-d`, `-l`,
  `-x`, `-u`, `-e`, `-V`) `return`/`exit` directly from the getopt loop. Everything
  else falls through to source selection: it `stat()`s the optional path argument
  and picks one of three function pointers — `dirsethandler` (directory),
  `psethandler` (`*.plist`), or `fsethandler` (settings file, or stdin when no path).
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
- `nroles` is a global assigned in `main()` *after* the getopt loop, and
  `handler.c` reads it as `extern`. Any new code path that reaches
  `duti_handler_set()` with a role must not bypass that assignment.

### Known gaps worth knowing before "fixing" them

- The LaunchServices and `UTType*` C APIs used throughout are deprecated in
  recent macOS SDKs. A clean build on macOS 26 emits ~50 warnings, **all** of
  them `-Wdeprecated-declarations` (`LSSetDefaultRoleHandlerForContentType`,
  `LSGetApplicationForInfo`, `LSCopyDisplayNameForURL`, `UTType*`,
  `CFPropertyListCreateFromStream`). That is the expected baseline, not new
  breakage — any *other* warning class is worth investigating. Replacing these
  means moving to `UniformTypeIdentifiers.framework` (macOS 11+) and would drop
  support for the older deployment targets the autoconf macros still handle.
- `autoreconf` also warns that `AC_CANONICAL_SYSTEM`, `AC_HELP_STRING`, and
  `AC_ERROR` are obsolete. Harmless with current autoconf; likewise expected.

## Code style

Existing C is BSD/K&R with an unusual layout — the return type sits on its own
line with the function name unindented at column 0, indentation is tabs, and
parentheses are padded (`printf( "%s\n", tmp )`). Match the surrounding file
rather than reformatting. `configure.ac` adds `-Wall -Wmissing-prototypes` under
GCC/Clang, so declare prototypes for anything non-`static`.

## Packaging / release

`make dist` and `make pkg` are release-only targets and shell out to `sudo`,
`pkgbuild`, and `openssl`. They rewrite `INTERNAL` in `configure.ac` to a date
stamp and substitute `_DUTI_BUILD_DATE` in `duti.1` — which is why the checked-in
`VERSION` reads `internal` and the man page carries a literal placeholder in its
`.TH` line. Leave both alone during normal development. `duti.1` is groff `man`
macros, not `mdoc`.

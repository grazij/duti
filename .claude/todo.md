# TODO

Homebrew formula + updater: **done, released as 1.5.5+grazij.4**, captured in
CLAUDE.md. `-h` option list: committed at `82aa92e`, not pushed.

## Content-detected config sources

**Decisions taken (do not re-litigate)**

| Question | Decision |
|---|---|
| Default config | The first existing *directory* of `$XDG_CONFIG_HOME/duti/`, `~/.config/duti/`, `~/.duti/` |
| Privileged filename | Gone. No `config` file, no `.plist` suffix rule |
| Format detection | Sniff leading bytes: `<?xml`, `<plist`, `bplist00` after whitespace |
| stdin | Detected too, so `-c -` accepts a piped plist |
| Symlinks | Unchanged — `stat()` follows them, verified |

**Target `-c path` behavior**

| path | action |
|---|---|
| `-` | read stdin, detect format |
| directory | scan it, sorted, detect each file's format |
| regular file | read it, detect format |
| anything else | error, exit 1 |

- [x] S1. `plist.c`: replace `read_plist( path, &dict )` with
      `read_plist( buf, len, label, &dict )`. Drops `realpath`, `CFURL` and
      `CFReadStreamCreateWithFile` in favour of
      `CFReadStreamCreateWithBytesNoCopy`; `label` carries the path (or
      "standard input") into the error messages that used `__FUNCTION__`.
- [x] S2. `handler.c`: `static int looks_like_plist( const char *, size_t )` —
      skip leading whitespace, then match `<?xml`, `<plist` or `bplist00`.
      `bplist00` is new capability: the suffix rule accepted binary plists only
      by accident of name.
- [x] S3. `handler.c`: `static char *slurp( FILE *, const char *label, size_t * )`.
      Config files are small; reading them whole is what makes one detection
      path serve files, directory members and stdin alike.
- [x] S4. `handler.c`: split the settings-file loop into
      `static int fsethandler_stream( FILE * )`, unchanged body. Text input
      reaches it through `fmemopen` (10.13+, below the 11 deployment target).
      Guard len == 0 — `fmemopen` with size 0 is not required to succeed.
- [x] S5. `handler.c`: `psethandler` takes the slurped buffer instead of a path.
- [x] S6. `handler.c`: new `sethandler( char *spath )`, spath NULL = stdin.
      Opens, slurps, sniffs, dispatches. Replaces `fsethandler`/`psethandler`
      in `handler.h`; `duti_handler_set` stays the single write choke point.
- [x] S7. `handler.c` `dirsethandler`: drop the `.plist` suffix branch, call
      `sethandler` per file. Sorted order and the dotfile skip are unchanged.
- [x] S8. `duti.c` `default_config_path()`: candidates become `/duti`,
      `/.config/duti`, `/.duti`. The XDG rule is unchanged — `~/.config` is
      skipped when `XDG_CONFIG_HOME` is set and non-empty.
- [x] S9. `duti.c` dispatch: drop the `.plist` suffix branch; regular file and
      stdin both go to `sethandler`, directories to `dirsethandler`.
- [x] S10. `handler.c`: skip a settings line whose first **non-whitespace**
      character is `#`, and treat a whitespace-only line as blank. Today only
      column-0 `#` and a truly empty line are skipped, so `  # note` parses as
      two fields and reaches `duti_handler_set` as a URL-scheme write —
      reported as `setting   # as handler for note:// URLs`, exit 0. An
      indented comment of any other width errors instead. Both are bugs.
- [x] S11. `duti.1`, `README.md`, `examples/config`, `CLAUDE.md`, and the `-c`
      paragraph in `usage()`.

**Compatibility.** An existing `~/.config/duti/config` keeps working: the
directory is now the default, and `config` inside it is a regular file the scan
picks up. The real change is that *every other* file in those directories is now
applied too — a stray `notes.md` there becomes a parse error. Flag it in the
release notes.

## Verification

- [x] V1. Non-mutating throughout: configs name a bogus UTI, which
      `duti_is_conformant_uti()` rejects before any LaunchServices call.
- [x] V2. Matrix, each asserted by which parser's error appears:

      | input | expected |
      |---|---|
      | plist content, no extension | plist parser |
      | settings content, `.plist` name | settings parser |
      | plist piped to `-c -` | plist parser |
      | settings piped to `-c -` | settings parser |
      | binary plist (`plutil -convert binary1`) | plist parser |
      | empty file | no output, exit 0 |
      | directory mixing both | both, sorted order |
      | symlink to file / to directory | as target |
      | fifo via `-c` | error, exit 1 |
      | `  # note` | ignored, exit 0, no write attempted |
      | `\t# c`, `   # c`, `# c` | all ignored |
      | whitespace-only line | ignored, exit 0 |
      | `#` inside a field (`a b#c`) | still data, not a comment |

- [x] V3. Default resolution with `XDG_CONFIG_HOME` set, unset, set-empty, and
      with only `~/.duti/` present.
- [x] V4. Legacy `~/.config/duti/config` still applies.
- [x] V5. `make` — 0 warnings, universal, `vtool` both slices `minos 11.0`.
- [x] V6. `-h`, `-V`, `-x`, `-d`, `-l`, `-u`, `-e`, `-s` unchanged.

duti
====

duti is a command-line utility capable of setting default applications for
various document types on [macOS](https://www.apple.com/macos/), using Apple's
[Uniform Type
Identifiers](https://developer.apple.com/library/content/documentation/FileManagement/Conceptual/understanding_utis/understand_utis_intro/understand_utis_intro.html)
(UTI). A UTI is a unique string describing the format of a file's content. For
instance, a Microsoft Word document has a UTI of `com.microsoft.word.doc`. Using
`duti`, the user can change which application acts as the default handler for a
given UTI.


Compiling
---------

    autoreconf -i
    ./configure
    make
    sudo make install

`autoreconf` comes from autoconf, which is not part of the Xcode command line
tools (`brew install autoconf`).

If you change `version.toml`, re-run `autoreconf -if`. The `-f` matters:
`AC_INIT` reads the version through `m4_esyscmd_s` when `autoconf` runs, and
without `-f` `autoreconf` skips it because `configure` is newer than
`configure.ac` — leaving the old version compiled into the binary.

On Apple silicon and Intel alike, `configure` produces a universal binary
(x86_64 + arm64) with a macOS 11 deployment target, so the result runs on
macOS 11 and later regardless of which release it was built on. Pass
`--with-macosx-deployment-target=VERSION` to override, or
`--with-macosx-arches="-arch arm64"` to build for one architecture only.


Installing with Homebrew
------------------------

    brew install grazij/tap/duti

`Formula/duti.rb` in this repository is the source of that formula; copy it to
[grazij/homebrew-tap](https://github.com/grazij/homebrew-tap) to publish a new
version. It builds only for the architecture running the build, which is why it
passes `--with-macosx-arches`; released tarballs are still built universal.

`./update-formula.sh [VERSION]` points the formula at a released tag, fetching
the tarball to compute its checksum. VERSION defaults to `version.toml`. The tag
must already be pushed — GitHub generates the tarball on demand, so the checksum
does not exist before then. CI runs the script after every release, so the copy
in this repository is normally already current.


Usage
-----

`duti` reads settings from a config given with `-c`, or from command-line
arguments with `-s`:

    duti -c ~/my.duti      # a settings file
    duti -c ~/my.plist     # a property list
    duti -c ~/duti.d       # a directory of either
    duti -c -              # standard input
    duti                   # the default config directory (see below)

    duti -s com.apple.Safari public.html all

The format is detected from the content, not the filename: a source whose
first non-blank bytes are `<?xml`, `<plist` or `bplist00` is read as a
property list, anything else as a settings file. So a directory may hold both
kinds, and either kind may be piped in.

A settings line consists of an application's bundle ID, a UTI, and a string
describing what role the application handles for the given UTI. A line whose
first non-blank character is `#` is a comment, and a blank line is ignored; a
`#` anywhere else on a line is data. The process is similar when `duti`
processes a [property list](https://en.wikipedia.org/wiki/Property_list)
(plist), in either XML or binary form. If the config is a directory, `duti`
applies settings from all valid settings files in it in sorted filename order,
excluding files whose names begin with `.` (single dot).

### Config file location

With no `-c`, `duti` applies the first of these directories that exists:

1. `$XDG_CONFIG_HOME/duti/`
1. `~/.config/duti/`
1. `~/.duti/`

Every file in it is applied, in sorted filename order, each read as whatever
its content says it is. There is no privileged filename — an existing
`~/.config/duti/config` still works, now as one member of that directory.

If `XDG_CONFIG_HOME` is set and non-empty, `~/.config` is not consulted, per
the XDG Base Directory Specification. If none of the three exists, `duti`
prints usage and exits 1.

See [`examples/config`](examples/config) for a commented starting point.

`duti` can also print out the default application information for a given
extension (`-x`). This feature is based on public domain source code posted
by Keith Alperin on the heliumfoot.com blog.

`duti` can additionally report type declarations without changing any handler:
`-u` prints the description and declaration of a UTI, and `-e` does the same for
every UTI claiming a given filename extension.

See the man page for additional usage details.


Examples
--------

* Set Safari as the default handler for HTML documents:

    ```sh
    duti -s com.apple.Safari public.html all
    ```

* Set TextEdit as the default handler for Word documents:

    ```sh
    echo 'com.apple.TextEdit   com.microsoft.word.doc all' | duti -c -
    ```

* Set Finder as the default handler for ftp:// URLs:

    ```sh
    duti -s com.apple.Finder ftp
    ```

* Get default application information for .jpg files:

    ```sh
    duti -x jpg

    # Output
    Preview
    /Applications/Preview.app
    com.apple.Preview
    ```

Versioning
----------

This is a fork. Versions are `<upstream version>+grazij.<counter>`, for example
`1.5.5+grazij.1`. The core tracks whatever upstream last released and only ever
changes by hand; each release here moves the counter. `version.toml` is the
single source of truth — `configure.ac` reads it, `make dist` names the tarball
from it, and `duti -V` prints it. `./bump-fork-version.sh` increments the
counter; CI calls it and does not bump the core.

### Homebrew

Homebrew orders these versions correctly (`1.5.5+grazij.1` sorts above
`1.5.5`, and `.1` below `.2`), but its automatic version *detection* does not
understand the `+` suffix and reads the version as `1`. `Formula/duti.rb`
therefore pins the version explicitly:

```ruby
version "1.5.5+grazij.1"

livecheck do
  url :stable
  strategy :github_latest
  regex(/v?(\d+(?:\.\d+)+\+grazij\.\d+)/i)
end
```

Support
-------

`duti` is unsupported. Upstream (`moretension/duti`) has been dormant since
July 2023; issues and pull requests for this fork belong on the
[grazij/duti project page](https://github.com/grazij/duti).

Related
-------
[dutis](https://github.com/tsonglew/dutis) is a wrapper around duti, providing an
interactive interface to select default applications.

License
-------

`duti` was originally released into the public domain by Andrew Mortensen
in 2008. It's provided as is without warranties of any kind. You can do
anything you want with it. If you incorporate some or all of the code into
another project, I'd appreciate credit for the work I've done, but that's all.

Andrew Mortensen
April 2018

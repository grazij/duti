duti
====

duti is a command-line utility capable of setting default applications for
various document types on [macOS](https://www.apple.com/macos/), using Apple's
[Uniform Type Identifiers](https://developer.apple.com/library/content/documentation/FileManagement/Conceptual/understanding_utis/understand_utis_intro/understand_utis_intro.html)
(UTI). A UTI is a unique string describing the format of a file's content. For
instance, a Microsoft Word document has a UTI of `com.microsoft.word.doc`. Using
`duti`, the user can change which application acts as the default handler for a
given UTI.

Differences from upstream
-------------------------

This is a fork of [moretension/duti](https://github.com/moretension/duti), which
has been dormant since July 2023.

* Builds on macOS newer than Ventura, and the universal binary runs on macOS 11
  and later whichever Mac built it
* More flexible settings configuration — `-c`, a default config directory,
  automatic config file type detection, comment support
* Improved error handling and help output
* Homebrew support

Installing
----------

```sh
brew install grazij/tap/duti
```

Or build it yourself — see [Building](#building).

Usage
-----

`duti` reads settings from a config given with `-c`, or from command-line
arguments with `-s`:

```sh
duti -c ~/my.duti      # a settings file
duti -c ~/my.plist     # a property list
duti -c ~/duti.d       # a directory of either
duti -c -              # standard input
duti                   # the default config directory (see below)

duti -s com.apple.Safari public.html all
```

A settings line is an application's bundle ID, a UTI, and the role the
application plays for it:

```
com.apple.Safari    public.html    all
```

Two fields instead of three set the handler for a URL scheme:

```
com.apple.Safari    https
```

The role is one of `all`, `viewer`, `editor`, `shell` or `none`. A line whose
first non-blank character is `#` is a comment, and blank lines are ignored.

A config may be a [property list](https://en.wikipedia.org/wiki/Property_list)
instead, in either XML or binary form. `duti` tells the two formats apart by
content rather than by filename, so a directory may hold both and either may be
piped in.

See [`examples/config`](examples/config) for a commented starting point.

### Config file location

With no `-c`, `duti` applies the first of these directories that exists, in
this order:

```
$XDG_CONFIG_HOME/duti/
~/.config/duti/
~/.duti/
```

Every file in it is applied, in sorted filename order, excluding files whose
names begin with `.` (single dot). If `XDG_CONFIG_HOME` is set and non-empty,
`~/.config` is not consulted, per the XDG Base Directory Specification. If none
of the three exists, `duti` prints usage and exits 1.

### Queries

`duti` can also report what is registered, without changing any handler:

| command | prints |
|---|---|
| `duti -x jpg` | the default application for a filename extension |
| `duti -d public.html` | the default handler for a UTI |
| `duti -l public.html` | every handler registered for a UTI |
| `duti -u public.html` | a UTI's description and type declaration |
| `duti -e jpg` | every UTI claiming a filename extension |

`duti -h` lists every option. See the man page for the full details.

Examples
--------

Set Safari as the default handler for HTML documents:

```sh
duti -s com.apple.Safari public.html all
```

Set TextEdit as the default handler for Word documents:

```sh
echo 'com.apple.TextEdit   com.microsoft.word.doc all' | duti -c -
```

Set Finder as the default handler for ftp:// URLs:

```sh
duti -s com.apple.Finder ftp
```

Get default application information for .jpg files:

```sh
duti -x jpg
```

```
Preview
/System/Applications/Preview.app
com.apple.Preview
```

Building
--------

```sh
autoreconf -i
./configure
make
sudo make install
```

`autoreconf` comes from autoconf, which is not part of the Xcode command line
tools (`brew install autoconf`).

`configure` produces a universal binary (x86_64 + arm64) with a macOS 11
deployment target, so the result runs on macOS 11 and later whichever machine
built it. Pass `--with-macosx-deployment-target=VERSION` or
`--with-macosx-arches="-arch arm64"` to override.

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

The `-x` option is based on public domain source code posted by Keith Alperin
on the heliumfoot.com blog.

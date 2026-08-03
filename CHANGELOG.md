## 1.5.5+grazij.6

### Other Changes

* WIP (032ede3)
* note that homebrew-core shadows the tap's duti (ef43a51)
* make the README a user manual (c3f03da)

## 1.5.5+grazij.5

### BREAKING CHANGES

* detect config format from content, not filename (c513e75)

### Features

* detect config format from content, not filename (c513e75)
* list every option in duti -h (82aa92e)

### Other Changes

* note the 644 requirement when copying the formula (e70ab97)
* stop the formula comment naming a version (91eb5a4)

## 1.5.5+grazij.4

### Features

* add a Homebrew formula and an on-demand updater (18102f1)

### Other Changes

* cut verbose comments and prose (4205a57)

## 1.5.5+grazij.3

### Features

* separate release notes content from release triggering (086034a)

### Other Changes

* add a changelog regression suite over the real repo history (92b7970)

## 1.5.5+grazij.2

### Bug Fixes

* stop the changelog silently dropping most of the fork's commits (1a84e6c)

## 1.5.5+grazij.1

### BREAKING CHANGES

* replace the settings_path operand with -c, and fork the version scheme (331aab5)

### Features

* replace the settings_path operand with -c, and fork the version scheme (331aab5)

### Bug Fixes

* run CI on master update only (653886b)
* corrected link (ca5025d)
* automated versioning and releases in CI (fbedb2e)

### Other Changes

* restore the pull_request trigger (9c05250)
* update CLAUDE.md for the merged upstream changes (1545d27)
* Document the build requirements and the macOS 11 deployment target (cfa9ab2)
* Strip whitespace when reading the version out of version.toml (4b40008)
* Set a fixed macOS 11 deployment target instead of tracking the host (b682406)
* drop the stale undocumented-options note from CLAUDE.md (fb37160)
* Ignore the built duti binary (45065cc)
* Document the -e and -u options (0a229ce)
* add CLAUDE.md with build and architecture notes (7f4b44f)
* Add SDK and deployment target mappings for macOS 14, 15 and 26 (3e5c7de)
* Add support for macOS 14, 15, and 26 (cf2020f)
* Add validation for dynamic UTI registration (7810364)

